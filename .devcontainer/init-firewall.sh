#!/bin/bash
# Default-deny egress firewall for the dev container. Runs as root at every
# container start (devcontainer.json postStartCommand, or agent-sandbox.zsh when the
# OUTPUT policy is not DROP) and may be re-run on a live container.
#
# Order matters for re-runs: everything that needs the network (GitHub meta,
# DNS lookups) happens FIRST, while the previous rules still allow it; the
# new ipset is built beside the old one and swapped in; the filter table is
# replaced atomically with iptables-restore. The nat and mangle tables are
# never touched — Docker's embedded-DNS NAT rules stay as they are.
#
# Known limits (documented, not fixed here — see README "Security model"):
#   - GitHub is allowed by IP range, so any GitHub repo is reachable, not
#     just this project's.
#   - DNS goes only to the configured resolvers, but a recursive resolver
#     still forwards any name, so DNS tunneling remains possible. A filtering
#     resolver (allowlisted names only) is the follow-up.
set -euo pipefail  # Exit on error, undefined vars, and pipeline failures
IFS=$'\n\t'       # Stricter word splitting

ALLOWED_DOMAINS_FILE=/etc/init-firewall/allowed-domains.txt
ALLOW_HOST_NETWORK=0

# Fail closed. On a FIRST start a failure before the rules are applied (no
# GitHub meta, a typo'd domain) would otherwise leave a running container
# with open egress: the VS Code path keeps the container up and only
# reports the postStart error. On failure, if no DROP policy is in place
# yet, apply a loopback-only DROP table. A re-run cannot then fetch
# GitHub's ranges through it, so recovery is a container restart (agent-sandbox.zsh
# stops the container on failure anyway, and treats this table as "not
# applied" because it lacks the allowlist rule). A re-run that fails keeps
# the previous rules: the gather phase runs before anything is touched.
fail_closed() {
    local rc=$?
    [ "$rc" -eq 0 ] && return 0
    if ! iptables -S OUTPUT 2>/dev/null | grep -q -- '-P OUTPUT DROP'; then
        printf '%s\n' '*filter' ':INPUT DROP [0:0]' ':FORWARD DROP [0:0]' ':OUTPUT DROP [0:0]' \
            '-A INPUT -i lo -j ACCEPT' '-A OUTPUT -o lo -j ACCEPT' 'COMMIT' | iptables-restore
        echo "ERROR: firewall setup failed (exit $rc); all egress is blocked until the container restarts"
    else
        echo "ERROR: firewall setup failed (exit $rc); the previous rules are still in place"
    fi
    exit "$rc"
}
trap fail_closed EXIT

# ---------------------------------------------------------------------------
# 1. Gather everything BEFORE touching a single rule
# ---------------------------------------------------------------------------

# GitHub: published IP ranges, aggregated.
echo "Fetching GitHub IP ranges..."
gh_ranges=$(curl -s --max-time 20 https://api.github.com/meta || true)
if [ -z "$gh_ranges" ]; then
    echo "ERROR: Failed to fetch GitHub IP ranges"
    exit 1
fi
if ! echo "$gh_ranges" | jq -e '.web and .api and .git' >/dev/null; then
    echo "ERROR: GitHub API response missing required fields"
    exit 1
fi
gh_cidrs=()
while read -r cidr; do
    if [[ "$cidr" == *:* ]]; then
        continue  # IPv6 range — the ipset is inet-only; IPv6 egress is dropped wholesale below
    fi
    if [[ ! "$cidr" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        echo "ERROR: Invalid CIDR range from GitHub meta: $cidr"
        exit 1
    fi
    gh_cidrs+=("$cidr")
done < <(echo "$gh_ranges" | jq -r '(.web + .api + .git)[]' | aggregate -q)
echo "GitHub: ${#gh_cidrs[@]} ranges"

# The allowlist. The file is .devcontainer/allowed-domains.txt in the repo,
# baked into the image by the Dockerfile — like this script, the baked copy
# is what runs, so edits take effect only after a rebuild. Keeping the
# domains in a data file means this script is pure harness logic that
# sync-harness.sh can mirror, while the per-project list stays put.
#
# Besides hostnames the file may carry exactly one directive, as a comment
# line of its own:   # allow-host-network
# It opens OUTPUT to the Docker gateway's /24 (sibling service containers on
# the same bridge). Off by default: that network is also where the host and
# its other containers answer. Parsed strictly — the line must match exactly.
if [ ! -f "$ALLOWED_DOMAINS_FILE" ]; then
    echo "ERROR: $ALLOWED_DOMAINS_FILE missing — the Dockerfile must COPY allowed-domains.txt there"
    exit 1
fi
allowed_domains=()
lineno=0
while IFS= read -r line || [ -n "$line" ]; do
    lineno=$((lineno + 1))
    if [[ "$line" =~ ^#[[:space:]]*allow-host-network[[:space:]]*$ ]]; then
        ALLOW_HOST_NETWORK=1
        continue
    fi
    line="${line%%#*}"              # drop comments
    line="${line//[[:space:]]/}"    # drop whitespace
    [ -z "$line" ] && continue
    # A bare hostname: labels of [A-Za-z0-9-], dot-separated, no scheme/path/port.
    if [[ ! "$line" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)+$ ]]; then
        echo "ERROR: $ALLOWED_DOMAINS_FILE:$lineno: not a bare hostname: '$line'"
        exit 1
    fi
    allowed_domains+=("$line")
done < "$ALLOWED_DOMAINS_FILE"
echo "Loaded ${#allowed_domains[@]} domains from $ALLOWED_DOMAINS_FILE (allow-host-network: $ALLOW_HOST_NETWORK)"

# Resolve them now, through the still-open old rules (first run: no rules).
domain_ips=()
for domain in "${allowed_domains[@]}"; do
    # `|| true`: dig exits non-zero when no server answers, and under
    # pipefail that would abort the whole script instead of skipping.
    ips=$(dig +noall +answer +time=5 +tries=2 A "$domain" | awk '$4 == "A" {print $5}' || true)
    if [ -z "$ips" ]; then
        echo "WARN: Failed to resolve $domain — skipping"
        continue
    fi
    while read -r ip; do
        if [[ ! "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            echo "ERROR: Invalid IP from DNS for $domain: $ip"
            exit 1
        fi
        echo "Resolved $domain -> $ip"
        domain_ips+=("$ip")
    done < <(echo "$ips")
done

# Resolvers: only the nameservers the container is configured with (plus
# loopback, which covers Docker's embedded DNS at 127.0.0.11). Before, UDP 53
# was open to the whole internet — a ready-made tunnel to any attacker-run
# resolver. IPv6 nameservers are skipped (IPv6 is dropped below).
#
# On a user-defined network (compose) resolv.conf names only 127.0.0.11, and
# Docker's embedded resolver forwards upstream FROM INSIDE this network
# namespace, so those packets also cross OUTPUT. Docker lists the upstreams
# in resolv.conf as `# ExtServers: [host(192.168.65.7) 8.8.8.8]`; take them
# too. The default bridge (agent-sandbox.zsh, plain devcontainer.json) has the real
# upstream addresses as nameservers and no ExtServers line. The compose path
# is untested here; the DNS self-test below fails closed if it is wrong.
nameservers=()
while read -r ns; do
    if [[ "$ns" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        nameservers+=("$ns")
    else
        echo "Skipping non-IPv4 nameserver $ns"
    fi
done < <(awk '$1 == "nameserver" {print $2}' /etc/resolv.conf;
         grep -m1 '^# ExtServers:' /etc/resolv.conf | grep -oE '[0-9]{1,3}(\.[0-9]{1,3}){3}' || true)
if [ "${#nameservers[@]}" -eq 0 ]; then
    echo "ERROR: no IPv4 nameserver in /etc/resolv.conf"
    exit 1
fi
echo "DNS allowed to: $(printf '%s ' "${nameservers[@]}")"

# Host network: the default gateway's /24. INPUT from it is always allowed
# (published ports arrive from the gateway — an assumption about Docker
# Desktop's port proxy to verify if a published port stops answering).
# OUTPUT to it only with the allow-host-network directive.
HOST_IP=$(ip route | awk '/^default/ {print $3; exit}')
if [ -z "$HOST_IP" ]; then
    echo "ERROR: Failed to detect host IP"
    exit 1
fi
HOST_NETWORK=$(echo "$HOST_IP" | sed "s/\.[0-9]*$/.0\/24/")
echo "Host network detected as: $HOST_NETWORK"

# ---------------------------------------------------------------------------
# 2. ipset: build the new set beside the old one, then swap (atomic)
# ---------------------------------------------------------------------------
ipset destroy allowed-domains-new 2>/dev/null || true   # leftover from an aborted run
ipset create allowed-domains-new hash:net
for cidr in "${gh_cidrs[@]}"; do
    ipset add allowed-domains-new "$cidr" -exist
done
for ip in "${domain_ips[@]}"; do
    ipset add allowed-domains-new "$ip" -exist
done
# `create -exist` makes the first run and a re-run the same path: swap needs
# both sets to exist.
ipset create allowed-domains hash:net -exist
ipset swap allowed-domains-new allowed-domains
ipset destroy allowed-domains-new
echo "ipset allowed-domains: $(ipset list allowed-domains | awk '/Number of entries/ {print $4}') entries"

# ---------------------------------------------------------------------------
# 3. Filter table, replaced in one transaction. Only *filter is listed, so
#    iptables-restore leaves nat and mangle alone (no --noflush needed: it
#    only flushes the tables the input names).
# ---------------------------------------------------------------------------
{
    echo '*filter'
    echo ':INPUT DROP [0:0]'
    echo ':FORWARD DROP [0:0]'
    echo ':OUTPUT DROP [0:0]'
    echo '-A INPUT -i lo -j ACCEPT'
    echo '-A OUTPUT -o lo -j ACCEPT'
    echo '-A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT'
    echo '-A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT'
    # DNS, UDP and TCP, only to the configured resolvers. Replies come back
    # through ESTABLISHED. A recursive resolver still answers for ANY name,
    # so this narrows the tunnel to those resolvers rather than closing it;
    # a filtering resolver that only answers allowlisted names is the
    # follow-up (README "Security model").
    for ns in "${nameservers[@]}"; do
        echo "-A OUTPUT -d $ns/32 -p udp --dport 53 -j ACCEPT"
        echo "-A OUTPUT -d $ns/32 -p tcp --dport 53 -j ACCEPT"
    done
    # No blanket TCP 22 any more: GitHub SSH is covered by the ipset rule
    # below, which accepts any port to GitHub's ranges.
    echo "-A INPUT -s $HOST_NETWORK -j ACCEPT"
    if [ "$ALLOW_HOST_NETWORK" = 1 ]; then
        echo "-A OUTPUT -d $HOST_NETWORK -j ACCEPT"
    fi
    echo '-A OUTPUT -m set --match-set allowed-domains dst -j ACCEPT'
    # REJECT rather than DROP for immediate feedback (hangs are hard to debug).
    echo '-A OUTPUT -j REJECT --reject-with icmp-admin-prohibited'
    echo 'COMMIT'
} | iptables-restore
echo "IPv4 filter table applied"

# IPv6: drop everything but loopback. Hosts without IPv6 (or without the
# ip6tables kernel modules) are tolerated — there is nothing to filter there.
if command -v ip6tables-restore >/dev/null 2>&1 && ip6tables -S >/dev/null 2>&1; then
    {
        echo '*filter'
        echo ':INPUT DROP [0:0]'
        echo ':FORWARD DROP [0:0]'
        echo ':OUTPUT DROP [0:0]'
        echo '-A INPUT -i lo -j ACCEPT'
        echo '-A OUTPUT -o lo -j ACCEPT'
        echo '-A OUTPUT -j REJECT --reject-with icmp6-adm-prohibited'
        echo 'COMMIT'
    } | ip6tables-restore
    echo "IPv6 filter table applied (all egress blocked)"
else
    echo "IPv6: ip6tables unavailable here — nothing to filter"
fi

# ---------------------------------------------------------------------------
# 4. Self-tests. Each failure exits non-zero so a container that starts with
#    a broken firewall never becomes "ready" (devcontainer.json waits for
#    this script; agent-sandbox.zsh stops the container).
# ---------------------------------------------------------------------------
echo "Firewall configuration complete"
echo "Verifying firewall rules..."

if curl --connect-timeout 5 https://example.com >/dev/null 2>&1; then
    echo "ERROR: Firewall verification failed - was able to reach https://example.com"
    exit 1
fi
echo "Verification passed - https://example.com unreachable"

if ! curl --connect-timeout 5 https://api.github.com/zen >/dev/null 2>&1; then
    echo "ERROR: Firewall verification failed - unable to reach https://api.github.com"
    exit 1
fi
echo "Verification passed - https://api.github.com reachable"

# Docker's embedded DNS must still work (we no longer touch the nat table,
# so its 127.0.0.11 redirect must have survived).
if ! dig +short +time=3 +tries=1 api.github.com A | grep -q .; then
    echo "ERROR: Firewall verification failed - DNS resolution broken after applying rules"
    exit 1
fi
echo "Verification passed - DNS still resolves"

# TCP 22 to a non-GitHub host. Two checks, because a connect probe alone
# cannot tell "rejected" from "open but nobody listening" (both fail; the
# second by timeout). First the rules: no ACCEPT for port 22 may exist.
if iptables -S OUTPUT | grep -qE -- '--dport 22 .*-j ACCEPT'; then
    echo "ERROR: Firewall verification failed - OUTPUT has an ACCEPT rule for TCP 22"
    exit 1
fi
# Then behaviour, against a host that does listen on 22 and is not GitHub
# (no nc in the image; bash's /dev/tcp will do). REJECT fails instantly;
# a timeout means the host was unreachable for another reason, so only warn.
if timeout 5 bash -c 'exec 3<>/dev/tcp/gitlab.com/22' 2>/dev/null; then
    echo "ERROR: Firewall verification failed - TCP 22 to gitlab.com is open"
    exit 1
elif [ "$?" = 124 ]; then
    echo "WARN: TCP 22 probe to gitlab.com timed out (expected an immediate reject); rule check passed"
else
    echo "Verification passed - TCP 22 to a non-GitHub host rejected"
fi

# DNS to a resolver that is NOT one of ours.
# (IFS is newline/tab here, so compare element by element, not via ${arr[*]}.)
test_resolver=""
for cand in 1.1.1.1 9.9.9.9 8.8.8.8; do
    is_ours=0
    for ns in "${nameservers[@]}"; do [ "$ns" = "$cand" ] && is_ours=1; done
    if [ "$is_ours" = 0 ]; then test_resolver=$cand; break; fi
done
if [ -n "$test_resolver" ]; then
    if dig +short +time=2 +tries=1 "@$test_resolver" example.com A 2>/dev/null | grep -q .; then
        echo "ERROR: Firewall verification failed - DNS to $test_resolver is open"
        exit 1
    fi
    echo "Verification passed - DNS to $test_resolver blocked"
fi

# IPv6 egress, only where the container has an IPv6 default route.
if ip -6 route show default 2>/dev/null | grep -q default; then
    if curl -6 --connect-timeout 5 https://api.github.com >/dev/null 2>&1; then
        echo "ERROR: Firewall verification failed - IPv6 egress is open"
        exit 1
    fi
    echo "Verification passed - IPv6 egress blocked"
else
    echo "IPv6: no default route — egress test not applicable"
fi

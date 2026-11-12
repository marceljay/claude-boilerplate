- **Firewall: no blanket SSH or DNS, IPv6 blocked, re-runnable on a live
  container.** `init-firewall.sh` no longer opens TCP 22 to the world
  (GitHub SSH is covered by GitHub's IP ranges) or UDP 53 to any resolver
  (DNS tunnelling); DNS is allowed only to the nameservers in
  `/etc/resolv.conf` plus loopback. `ip6tables` drops all IPv6 egress.
  Outbound to the Docker gateway's /24 is off unless `allowed-domains.txt`
  carries the `# allow-host-network` directive (inbound from it stays open
  for published ports). The script now fetches GitHub meta and resolves all
  domains *before* touching rules, builds the ipset beside the old one and
  `ipset swap`s it, and replaces the filter table in one `iptables-restore`
  — so `sudo /usr/local/bin/init-firewall.sh` on a running container works
  and stays fail-closed, and the nat/mangle tables (Docker's DNS redirect)
  are never flushed. New self-tests: DNS still resolves, TCP 22 to a
  non-GitHub address blocked, DNS to a foreign resolver blocked, IPv6
  egress blocked where IPv6 exists.

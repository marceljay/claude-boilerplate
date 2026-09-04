# syntax=docker/dockerfile:1

# Pin the distro, not just the Node major. node:22 alone can silently move to a
# newer Debian release and break the apt-get list below (package availability
# differs between releases). Node 20 is end-of-life — do not stay on it.
FROM node:22-bookworm

ARG TZ
ENV TZ="$TZ"

# Fail the build on an invalid timezone instead of silently falling back to UTC.
# ("Etc/Berlin" is not a zone; the correct name is "Europe/Berlin".)
RUN if [ -n "$TZ" ] && [ ! -f "/usr/share/zoneinfo/$TZ" ]; then \
      echo "ERROR: invalid TZ '$TZ' — use a zoneinfo name like Europe/Berlin"; exit 1; \
    fi

# Install basic development tools and iptables/ipset.
# curl/wget/ca-certificates are added explicitly rather than relied on
# implicitly from the base image.
RUN apt-get update && apt-get install -y --no-install-recommends \
  ca-certificates \
  curl \
  wget \
  less \
  git \
  procps \
  sudo \
  fzf \
  zsh \
  man-db \
  unzip \
  gnupg2 \
  gh \
  iptables \
  ipset \
  iproute2 \
  dnsutils \
  aggregate \
  jq \
  nano \
  vim \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# Upgrade npm as root BEFORE NPM_CONFIG_PREFIX is set. If this runs after the
# prefix change, npm installs a second copy of itself into the npm-global prefix
# and the two shadow each other on PATH.
RUN npm install -g npm@latest

ARG USERNAME=node

# Scope ownership to the npm prefix only — not all of /usr/local/share, which
# would take over man pages and other unrelated shared data.
RUN mkdir -p /usr/local/share/npm-global && \
  chown -R $USERNAME:$USERNAME /usr/local/share/npm-global

# Persist zsh history in the mounted /commandhistory volume. Note zsh, not
# bash: the container's default shell is zsh, and bash-only mechanisms
# (PROMPT_COMMAND, .bash_history) silently do nothing there. The HISTFILE
# export that makes this work is wired into .zshrc by zsh-in-docker below.
RUN mkdir -p /commandhistory && \
  touch /commandhistory/.zsh_history && \
  chown -R $USERNAME:$USERNAME /commandhistory

# Set `DEVCONTAINER` environment variable to help with orientation
ENV DEVCONTAINER=true

# Create workspace and config directories and set permissions
RUN mkdir -p /workspace /home/node/.claude && \
  chown -R $USERNAME:$USERNAME /workspace /home/node/.claude

WORKDIR /workspace

# git-delta, sha256-pinned per architecture. Bumping GIT_DELTA_VERSION means
# recomputing both hashes from the release assets (sha256sum on the .debs) —
# the build fails loudly until you do, which is the point. No `sudo` here —
# this layer already runs as root.
ARG GIT_DELTA_VERSION=0.18.2
ARG GIT_DELTA_SHA256_ARM64=937781aa7788e1510858743fff6c9a8b4a69fe0a22a7c8a69493e633227939a9
ARG GIT_DELTA_SHA256_AMD64=1658c7b61825d411b50734f34016101309e4b6e7f5799944cf8e4ac542cebd7f
RUN ARCH=$(dpkg --print-architecture) && \
  case "$ARCH" in \
    arm64) DELTA_SHA256="$GIT_DELTA_SHA256_ARM64" ;; \
    amd64) DELTA_SHA256="$GIT_DELTA_SHA256_AMD64" ;; \
    *) echo "ERROR: no recorded git-delta hash for arch '$ARCH'"; exit 1 ;; \
  esac && \
  wget -q "https://github.com/dandavison/delta/releases/download/${GIT_DELTA_VERSION}/git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" && \
  echo "$DELTA_SHA256  git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" | sha256sum -c - && \
  dpkg -i "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" && \
  rm "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb"

# Set up non-root user
USER $USERNAME

ENV NPM_CONFIG_PREFIX=/usr/local/share/npm-global
ENV PATH=$PATH:/usr/local/share/npm-global/bin

ENV SHELL=/bin/zsh
ENV EDITOR=nano
ENV VISUAL=nano

# Powerlevel10k theme via zsh-in-docker — downloaded to a file and
# sha256-verified before execution, never piped straight into sh. The recorded
# hash is trust-on-first-use: it guarantees the asset never changes out from
# under us, but the first recording was computed from a download, so confirm it
# against the upstream release once if you haven't. Same recompute rule as
# git-delta when bumping the version.
ARG ZSH_IN_DOCKER_VERSION=1.2.0
ARG ZSH_IN_DOCKER_SHA256=f74e5b08c295b6c3886654bb63c688e5ea16c58a4209435c4ddbab2c42fe9b41
RUN wget -qO /tmp/zsh-in-docker.sh "https://github.com/deluan/zsh-in-docker/releases/download/v${ZSH_IN_DOCKER_VERSION}/zsh-in-docker.sh" && \
  echo "$ZSH_IN_DOCKER_SHA256  /tmp/zsh-in-docker.sh" | sha256sum -c - && \
  sh /tmp/zsh-in-docker.sh \
  -p git \
  -p fzf \
  -a "source /usr/share/doc/fzf/examples/key-bindings.zsh" \
  -a "source /usr/share/doc/fzf/examples/completion.zsh" \
  -a "export HISTFILE=/commandhistory/.zsh_history" \
  -a "setopt INC_APPEND_HISTORY SHARE_HISTORY" \
  -x && \
  rm /tmp/zsh-in-docker.sh

# Updates happen on image rebuild, not mid-session. This matters doubly here:
# a failed autoupdate leaves a half-installed binary, and even a SUCCESSFUL one
# runs from /workspace where the repo's .npmrc (ignore-scripts=true) applies —
# stripping the native binary the install below exists to link. Set BEFORE the
# install layer: ENV only affects later instructions, and the build-time
# `claude --version` check below is itself a claude invocation.
ENV DISABLE_AUTOUPDATER=1

# Install Claude Code.
#
#   --include=optional      pulls the platform-native binary
#                           (@anthropic-ai/claude-code-linux-arm64 and friends)
#   --allow-scripts=<pkg>   lets its postinstall link that binary into place.
#                           npm >= 12 (what `npm install -g npm@latest` above
#                           gives us) blocks ALL lifecycle scripts unless the
#                           package is named in allowScripts; without this the
#                           wrapper installs, the binary does not, and the
#                           build fails at `claude --version` below with
#                           "native binary not installed". Older npm ignores
#                           the flag with a warning and runs scripts anyway.
#   --ignore-scripts=false  the pre-12 override, kept because ignore-scripts=true
#                           inherited from NPM_CONFIG_* env or a runtime
#                           /workspace/.npmrc still blocks scripts on npm < 12,
#                           and because this line doubles as the documented
#                           recipe for any RUNTIME reinstall (see CHANGELOG).
#
# At build time /workspace is empty (the bind mount and its .npmrc exist only
# at runtime), so the .npmrc story applies to runtime reinstalls, where
# ignore-scripts=true (deliberate hardening; STACKS.md §Supply-chain
# hardening) DOES apply to -g installs run from /workspace. `claude --version`
# at the end turns a broken install into a BUILD failure instead of a
# mid-session surprise.
#
# `latest` is a per-rebuild snapshot, not a pin — each rebuild takes the newest
# release and DISABLE_AUTOUPDATER freezes it until the next rebuild. To pin
# exactly, put the version in devcontainer.json's build arg (it OVERRIDES this
# default — changing only this line does nothing).
ARG CLAUDE_CODE_VERSION=latest
RUN npm install -g "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" \
      --include=optional \
      --allow-scripts=@anthropic-ai/claude-code \
      --ignore-scripts=false \
 && claude --version

# Copy and set up firewall script
COPY init-firewall.sh /usr/local/bin/
USER root
RUN chmod +x /usr/local/bin/init-firewall.sh && \
  echo "$USERNAME ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh" > /etc/sudoers.d/node-firewall && \
  chmod 0440 /etc/sudoers.d/node-firewall
USER $USERNAME

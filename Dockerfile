FROM debian:bookworm-slim

# Framework version pinning for reproducible builds
# Update this when upgrading to a new framework version
ARG FRAMEWORK_VERSION=v0.8.0
# SHA256 for the release tarball (see: https://github.com/yaniv-golan/mcp-bash-framework/releases)
ARG FRAMEWORK_SHA256=488469bbc221b6eb9d16d6eec1d85cdd82f49ae128b30d33761e8edb9be45349
ENV XDG_DATA_HOME=/root/.local/share
ENV PATH="/root/.local/bin:${PATH}"

RUN apt-get update && \
    apt-get install -y bash jq git ca-certificates curl && \
    rm -rf /var/lib/apt/lists/*

# Copy tool (and optionally vendored framework)
COPY . /app

WORKDIR /app

# Prefer a vendored framework if present; otherwise install the pinned release tarball with verification.
RUN set -euo pipefail; \
    mkdir -p "${XDG_DATA_HOME}" /root/.local/bin; \
    if [ -x "/app/mcp-bash-framework/bin/mcp-bash" ]; then \
        ln -snf "/app/mcp-bash-framework" "${XDG_DATA_HOME}/mcp-bash"; \
    else \
        tmp="/tmp/mcp-bash.tgz"; \
        url="https://github.com/yaniv-golan/mcp-bash-framework/releases/download/${FRAMEWORK_VERSION}/mcp-bash-${FRAMEWORK_VERSION}.tar.gz"; \
        echo "Downloading mcp-bash framework ${FRAMEWORK_VERSION}..." >&2; \
        curl -fsSL "${url}" -o "${tmp}"; \
        echo "${FRAMEWORK_SHA256}  ${tmp}" | sha256sum -c - >/dev/null; \
        mkdir -p "${XDG_DATA_HOME}/mcp-bash"; \
        tar -xzf "${tmp}" -C "${XDG_DATA_HOME}/mcp-bash" --strip-components 1; \
        rm -f "${tmp}"; \
    fi; \
    ln -snf "${XDG_DATA_HOME}/mcp-bash/bin/mcp-bash" /root/.local/bin/mcp-bash

ENV MCPBASH_PROJECT_ROOT=/app
# mcp-bash-framework v0.7.0+: tool execution is deny-by-default unless allowlisted.
# Default to the full git-hex tool set; callers can override at runtime.
ENV MCPBASH_TOOL_ALLOWLIST="git-hex-getRebasePlan git-hex-checkRebaseConflicts git-hex-getConflictStatus git-hex-rebaseWithPlan git-hex-splitCommit git-hex-createFixup git-hex-amendLastCommit git-hex-cherryPickSingle git-hex-resolveConflict git-hex-continueOperation git-hex-abortOperation git-hex-undoLast"

ENTRYPOINT ["mcp-bash"]

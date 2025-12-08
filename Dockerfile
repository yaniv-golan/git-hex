FROM debian:bookworm-slim

# Framework version pinning for reproducible builds
# Update this when upgrading to a new framework version
ARG FRAMEWORK_VERSION=v0.6.0
ENV XDG_DATA_HOME=/root/.local/share
ENV PATH="/root/.local/bin:${PATH}"

RUN apt-get update && \
    apt-get install -y bash jq git && \
    rm -rf /var/lib/apt/lists/*

# Install framework at pinned version (XDG default layout)
RUN mkdir -p "${XDG_DATA_HOME}" /root/.local/bin && \
    git clone --depth 1 --branch "${FRAMEWORK_VERSION}" \
    https://github.com/yaniv-golan/mcp-bash-framework.git "${XDG_DATA_HOME}/mcp-bash" && \
    ln -snf "${XDG_DATA_HOME}/mcp-bash/bin/mcp-bash" /root/.local/bin/mcp-bash

# Copy tool
COPY . /app
ENV MCPBASH_PROJECT_ROOT=/app

ENTRYPOINT ["mcp-bash"]

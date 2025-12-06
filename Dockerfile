FROM debian:bookworm-slim

# Framework version pinning for reproducible builds
# Update this when upgrading to a new framework version
ARG FRAMEWORK_VERSION=v0.4.0

RUN apt-get update && \
    apt-get install -y bash jq git && \
    rm -rf /var/lib/apt/lists/*

# Install framework at pinned version
RUN git clone --depth 1 --branch "${FRAMEWORK_VERSION}" \
    https://github.com/yaniv-golan/mcp-bash-framework.git /mcp-bash-framework

# Copy tool
COPY . /app
ENV MCPBASH_PROJECT_ROOT=/app

ENTRYPOINT ["/mcp-bash-framework/bin/mcp-bash"]


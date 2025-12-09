FROM debian:bookworm-slim

# Framework version pinning for reproducible builds
# Update this when upgrading to a new framework version
ARG FRAMEWORK_VERSION=v0.6.0
ENV XDG_DATA_HOME=/root/.local/share
ENV PATH="/root/.local/bin:${PATH}"

RUN apt-get update && \
    apt-get install -y bash jq git && \
    rm -rf /var/lib/apt/lists/*

# Copy tool (and optionally vendored framework)
COPY . /app

# If a vendored framework exists, wire it up; otherwise fail fast to avoid remote clones during build
RUN mkdir -p "${XDG_DATA_HOME}" /root/.local/bin && \
    if [ -x "/app/mcp-bash-framework/bin/mcp-bash" ]; then \
        ln -snf "/app/mcp-bash-framework" "${XDG_DATA_HOME}/mcp-bash"; \
        ln -snf "${XDG_DATA_HOME}/mcp-bash/bin/mcp-bash" /root/.local/bin/mcp-bash; \
    else \
        echo "Vendored mcp-bash-framework not found in /app. Add it (e.g., submodule) or pre-bake the framework to avoid network clones in Docker builds." >&2; \
        exit 1; \
    fi

ENV MCPBASH_PROJECT_ROOT=/app

ENTRYPOINT ["mcp-bash"]

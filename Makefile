# Makefile for git-hex MCP server

.PHONY: help validate bundle clean test lint vendor-upgrade vendor-verify

help:
	@echo "Available targets:"
	@echo "  make validate       - Validate project structure"
	@echo "  make bundle         - Create MCPB bundle for distribution"
	@echo "  make clean          - Remove generated files"
	@echo "  make test           - Run integration tests"
	@echo "  make lint           - Run shellcheck linting"
	@echo "  make vendor-upgrade - Upgrade vendored mcp-bash runtime"
	@echo "  make vendor-verify  - Verify vendored runtime integrity"

validate:
	.mcp-bash/bin/mcp-bash validate

bundle:
	.mcp-bash/bin/mcp-bash bundle --verbose

clean:
	rm -f *.mcpb
	rm -rf .registry/
	rm -rf dist/

test:
	./test/run.sh

lint:
	./test/lint.sh

vendor-upgrade:
	mcp-bash vendor --upgrade
	@echo "Upgraded. Run 'make vendor-verify' then commit .mcp-bash/"

vendor-verify:
	mcp-bash vendor --verify
	@echo "Vendored runtime integrity verified."

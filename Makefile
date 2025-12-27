# Makefile for git-hex MCP server

.PHONY: help validate bundle clean test lint

help:
	@echo "Available targets:"
	@echo "  make validate  - Validate project structure"
	@echo "  make bundle    - Create MCPB bundle for distribution"
	@echo "  make clean     - Remove generated files"
	@echo "  make test      - Run integration tests"
	@echo "  make lint      - Run shellcheck linting"

validate:
	mcp-bash validate

bundle:
	mcp-bash bundle --verbose

clean:
	rm -f *.mcpb
	rm -rf .registry/
	rm -rf dist/

test:
	./test/run.sh

lint:
	./test/lint.sh

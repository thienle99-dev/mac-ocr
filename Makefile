.DEFAULT_GOAL := build

.PHONY: build test build-swift build-mcp clean register install help

build:
	swift build -c release
	pnpm --dir mcp install --frozen-lockfile
	pnpm --dir mcp build

test: build-swift build-mcp
	bash tests/smoke.sh
	pnpm --dir mcp typecheck
	bash tests/mcp-smoke.sh

build-swift:
	swift build -c release

build-mcp:
	pnpm --dir mcp install --frozen-lockfile
	pnpm --dir mcp build

clean:
	rm -rf .build mcp/dist

register:
	@echo 'claude mcp add mac-ocr -- node "$(CURDIR)/mcp/dist/index.js"'
	@echo 'codex mcp add mac-ocr -- node "$(CURDIR)/mcp/dist/index.js"'

install: build-swift build-mcp
	bash scripts/install.sh

help:
	@echo 'Targets: build, test, build-swift, build-mcp, install, clean, register, help'

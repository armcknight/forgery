# The `static let version` in the root command is the single source of truth
# for the release version (bumped by vrsn, read by the release workflow).
VERSION_FILE = Sources/forgery/Forgery.swift
VRSN_KEY = version

.PHONY: help build test install uninstall fmt check patch minor major deploy-beta deploy

.DEFAULT_GOAL := help

help: ## Show this help
	@echo "forgery — available make targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| sort \
		| awk 'BEGIN {FS = ":.*?## "} {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

# MARK: - Dev tooling

build: ## Build the release binary
	swift build -c release

test: ## Run the unit tests
	swift test

fmt: ## Format sources with swift-format
	swift format --in-place --recursive Sources Tests

check: fmt test ## Format then test

# MARK: - Local install

# Drops the locally-built `forgery` binary into the homebrew prefix's bin/,
# replacing any cask-installed symlink. Run `make uninstall` to restore the
# Homebrew cask version.
install: build ## Build + install forgery into the Homebrew prefix (shadows the cask)
	rm -f "$$(brew --prefix)/bin/forgery"
	install .build/release/forgery "$$(brew --prefix)/bin/forgery"
	@echo "Installed local forgery to $$(brew --prefix)/bin (shadows the Homebrew cask)"

uninstall: ## Remove the local forgery binary and restore the Homebrew cask
	rm -f "$$(brew --prefix)/bin/forgery"
	@if brew list --cask forgery >/dev/null 2>&1; then \
		brew reinstall --cask forgery; \
	else \
		echo "No Homebrew cask version to restore — run \`brew install --cask armcknight/tools/forgery\` if you want one."; \
	fi


# MARK: - Releasing
#
# Bumps the package version, then tags + pushes. GitHub Actions picks up the
# tag, builds, uploads to armcknight/homebrew-tools releases, and bumps the
# matching cask file there:
#   - tags `X.Y.Z`        → Casks/forgery.rb     (stable channel)
#   - tags `X.Y.Z-rc.N`   → Casks/forgery-rc.rb  (RC channel; users opt in)
#
# Requires `vrsn` + `prepare-release` on PATH (from the armcknight/tools cask).
# `make deploy` migrates the CHANGELOG [Unreleased] section into a dated version
# section, commits, tags, and pushes.

patch: ## Bump the patch version (x.y.Z) and commit
	vrsn patch -f $(VERSION_FILE) -k $(VRSN_KEY) --commit

minor: ## Bump the minor version (x.Y.0) and commit
	vrsn minor -f $(VERSION_FILE) -k $(VRSN_KEY) --commit

major: ## Bump the major version (X.0.0) and commit
	vrsn major -f $(VERSION_FILE) -k $(VRSN_KEY) --commit

# prepare-release auto-numbers the RC from the changelog's RC sections, so you
# can run deploy-beta repeatedly to ship rc.1, rc.2, etc. without re-bumping.
deploy-beta: ## Migrate the changelog, tag an RC, and push (ships the forgery-rc cask)
	prepare-release rc --file $(VERSION_FILE) --key $(VRSN_KEY) --push

deploy: ## Migrate the changelog, tag, and push the release (ships the stable forgery cask)
	prepare-release --file $(VERSION_FILE) --key $(VRSN_KEY) --push

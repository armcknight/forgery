# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- Release binaries are now Developer ID signed and notarized, so the Homebrew
  cask installs and runs without a Gatekeeper prompt.

## [1.0.0] 2026-08-10

First tagged release. `forgery` mirrors a forge's repositories to a local
machine and keeps them in sync.

### Added
- `clone` — clone a user's and/or an organization's repositories, plus starred
  repos, gists and wikis, into a typed directory layout. Deduplicates repos
  owned by both an org and the user, and pulls submodules recursively.
- `sync` — update an existing local mirror: fetch and pull each repo (with
  `--rebase` for forks), update submodules recursively, and optionally surface
  work-in-progress state.
- `status` — a read-only report over a local mirror: directory-structure
  detection (user / org / forked / starred / gist), per-repo git status,
  branch and dirty-working-tree info, WIP status, and local-only branches.
- GitHub authentication with either a classic token or fine-grained user and
  organization tokens.
- Distribution through the `armcknight/homebrew-tools` tap: `ci.yml` and
  `release.yml` delegate to `armcknight/workflows`' reusable SwiftPM pipelines,
  and a `Makefile` wraps `vrsn` for versioning.

### Changed
- Relicensed from GPL-3.0 to Apache-2.0.
- Rewritten in Swift (from the original Python), built on OctoKit, git-kit's
  2.0 async API and swift-argument-parser.

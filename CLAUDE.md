# PH0 – Pi-hole for Raspberry Pi Zero W

## Project Overview

Reproducible, immutable Raspberry Pi OS image with Pi-hole v6 as network-wide DNS ad-blocker. Built with pi-gen (bookworm branch), deployed via GitHub Actions CI/CD. Target: Raspberry Pi Zero W (ARMv6, 512 MB RAM).

This is a **shell-script-heavy infrastructure project**, not a typical application. The codebase is primarily Bash scripts, systemd units, and configuration files.

See @README.md for full project description and @docs/ARCHITECTURE.md for component details.

## Repository Map

```
config                         # pi-gen main configuration
secrets.env.example            # Template for credentials (never commit secrets.env)
stage-pihole/                  # Custom pi-gen stage (the core of the project)
  00-install-packages/         # APT packages + user/directory prep
  01-configure/                # Config files: pihole.toml, log2ram, watchdog, health-check, wlan-monitor
  02-first-boot/               # First-boot service (Pi-hole + Log2RAM install at runtime)
  03-hardening/                # SSH, nftables firewall, tmpfs, kernel tuning
scripts/                       # Host-side tooling: build.sh, flash.sh, validate.sh
docs/                          # ARCHITECTURE.md, SETUP.md, TROUBLESHOOTING.md
.github/workflows/             # GitHub Actions: build-image.yml
```

## Key Commands

```bash
# Lint all shell scripts
shellcheck scripts/*.sh stage-pihole/**/*.sh stage-pihole/**/files/*.sh

# Format shell scripts (check only)
shfmt -d -i 4 -ci scripts/*.sh stage-pihole/**/*.sh

# Run tests
./tests/run-tests.sh

# Build image locally (requires Docker)
./scripts/build.sh --clean

# Flash to SD card
./scripts/flash.sh /dev/sdX

# Validate running Pi
./scripts/validate.sh --wait
```

## Critical Architecture Decisions

- **pi-gen bookworm branch**, NOT master (master = Trixie since Aug 2025)
- **`cp -a` not symlinks** for custom stages — Docker build cannot follow symlinks outside build context
- **First-boot pattern**: Pi-hole and Log2RAM install at runtime (not in chroot) because chroot lacks systemd and network
- **Symlinks for service activation** in chroot — `systemctl enable` does not work in pi-gen chroot
- **All `secrets.env` values MUST be double-quoted** — unquoted values with spaces cause silent first-boot failures
- NetworkManager `dns=none` is set so Pi-hole owns DNS, but first-boot temporarily writes resolv.conf for downloads

## Shell Script Conventions

IMPORTANT: Follow these strictly for all `.sh` files.

- **Shebang**: `#!/bin/bash` (or `#!/bin/bash -e` for pi-gen stage scripts)
- **Formatting**: 4-space indentation, `shfmt -i 4 -ci` style
- **Linting**: All scripts MUST pass `shellcheck` with zero warnings
- **Error handling**: Use `set -euo pipefail` in scripts, or handle errors explicitly per-phase (like first-boot.sh)
- **Quoting**: Always double-quote variables: `"${VAR}"`, never bare `$VAR`
- **Logging**: Use `logger -t <tag>` for systemd journal + `echo` for console where appropriate
- **Comments**: German prose is OK for user-facing docs. Code comments and variable names stay English.
- **File headers**: Every script starts with a comment block: filename, purpose, and usage context

## pi-gen Stage Script Rules

- Scripts in `stage-pihole/*/` run inside the pi-gen **chroot** environment
- NEVER use `systemctl` commands in stage scripts — use symlinks instead
- NEVER use network-dependent operations (curl, apt install custom repos) — use first-boot
- Use `${ROOTFS_DIR}` for all file paths, `${STAGE_DIR}` for source file references
- Use `on_chroot << 'CHEOF' ... CHEOF` for commands that must run inside the chroot
- Use `install -v -m <mode>` for deploying files (not cp)

## systemd Unit Conventions

- All custom services go to `${ROOTFS_DIR}/etc/systemd/system/`
- Activation via symlink: `ln -sf /etc/systemd/system/<unit> ${ROOTFS_DIR}/etc/systemd/system/<target>.wants/<unit>`
- Always include `[Install]` section with appropriate `WantedBy=`
- Critical services: `Restart=on-failure`, `RestartSec=5`, `WatchdogSec` where applicable

## Git Workflow

- Main branch: `main`
- Feature branches: `feat/<description>` or `fix/<description>`
- Tag-based releases: `v<major>.<minor>.<patch>` triggers CI build + GitHub Release
- Commit messages: Conventional Commits (feat:, fix:, docs:, chore:, refactor:)
- Language: Commit messages in English

## Documentation

- All docs in `docs/` directory, Markdown format
- Every doc includes the AI-generated disclaimer: `> **Hinweis:** Dieses Dokument wurde mit Unterstützung von KI (Claude/Anthropic) erstellt.`
- User-facing documentation is in **German**
- Technical terms, commands, and variable names remain in **English**

## Testing

- Shell script tests use `bats-core` (Bash Automated Testing System)
- Tests live in `tests/` directory
- Test file naming: `test-<component>.bats`
- Every script should have corresponding tests for critical paths
- validate.sh is the integration test suite (runs against live Pi)

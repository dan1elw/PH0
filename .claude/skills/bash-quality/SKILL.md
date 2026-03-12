---
name: bash-quality
description: Shell script quality assurance. Use when writing, editing, or reviewing .sh files. Covers shellcheck compliance, shfmt formatting, error handling patterns, and pi-gen chroot constraints.
---

# Bash Script Quality Standards

## Formatting (shfmt)

All scripts follow `shfmt -i 4 -ci` style:
- 4-space indentation (no tabs)
- Switch cases indented (`-ci`)
- Binary operators at end of line (default)

Check: `shfmt -d -i 4 -ci <file>`
Fix: `shfmt -w -i 4 -ci <file>`

## Linting (shellcheck)

All scripts MUST pass shellcheck with zero warnings. Project uses `.shellcheckrc` in repo root.

Common patterns to watch for:
- SC2086: Double-quote variables → `"${var}"` not `$var`
- SC2046: Quote command substitutions → `"$(cmd)"` not `$(cmd)`
- SC2154: Declare or source variables before use
- SC2155: Don't combine declaration and assignment → `local var; var=$(cmd)`
- SC1091: Use `# shellcheck source=/dev/null` for dynamic sources

## Script Structure Template

```bash
#!/bin/bash
# <filename> – <brief description>
#
# <detailed description of what this script does>
# <usage context: when/where/how it runs>

set -euo pipefail

# Constants
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_TAG="<script-name>"

# Functions
log_info() {
    logger -t "${LOG_TAG}" -p daemon.info "$1"
    echo "[INFO]  $(date '+%H:%M:%S') $1"
}

log_err() {
    logger -t "${LOG_TAG}" -p daemon.err "$1"
    echo "[ERROR] $(date '+%H:%M:%S') $1" >&2
}

main() {
    # Script logic here
    :
}

main "$@"
```

## Error Handling Patterns

### Simple scripts (build, flash):
```bash
set -euo pipefail
```

### Complex multi-phase scripts (first-boot):
```bash
set -uo pipefail  # No set -e, handle errors per phase
FAILED_PHASES=()

phase_start() { ... }
phase_fail() { FAILED_PHASES+=("$1"); }
```

### Always handle cd failures:
```bash
cd "${dir}" || exit 1
# Or in a subshell:
(cd "${dir}" && do_something)
```

## pi-gen Stage Script Specifics

Stage scripts (`stage-pihole/*/01-run.sh`) have special constraints:

1. They run in a **chroot** — no systemd, no network
2. Use `${ROOTFS_DIR}` prefix for all target filesystem paths
3. Use `${STAGE_DIR}` for referencing source files within the stage
4. Use `install -v -m <mode>` for file deployment
5. Use `on_chroot << 'CHEOF' ... CHEOF` for chroot commands
6. Activate services via symlinks, never `systemctl enable`

```bash
# CORRECT: Symlink activation
mkdir -p "${ROOTFS_DIR}/etc/systemd/system/multi-user.target.wants"
ln -sf /etc/systemd/system/my.service \
    "${ROOTFS_DIR}/etc/systemd/system/multi-user.target.wants/my.service"

# WRONG: Will silently fail in chroot
on_chroot << 'CHEOF'
systemctl enable my.service
CHEOF
```

## Quoting Rules

- Always use `"${variable}"` (braces + double quotes)
- Exceptions: inside `[[ ]]` where word splitting doesn't apply (but quoting is still preferred for consistency)
- In `secrets.env` and similar sourced files: all values MUST be double-quoted
- Here-docs with variables: use `<< EOF` (expanding) or `<< 'EOF'` (literal) intentionally

## Logging Standards

For services/daemons running on the Pi:
```bash
LOG_TAG="component-name"
log_info() { logger -t "${LOG_TAG}" -p daemon.info "$1"; }
log_warn() { logger -t "${LOG_TAG}" -p daemon.warning "$1"; }
log_err()  { logger -t "${LOG_TAG}" -p daemon.err "$1"; }
```

For host-side scripts (build, flash):
```bash
echo "[INFO] ..."
echo "[WARN] ..."
echo "[FEHLER] ..."  # German for user-facing output
```

## Validation

After writing or editing any .sh file:
1. Run `shellcheck <file>` — must pass clean
2. Run `shfmt -d -i 4 -ci <file>` — must show no diff
3. If the script has tests, run `bats tests/test-<component>.bats`

---
description: Deep review of a shell script for quality, safety, and correctness
allowed-tools: Bash(shellcheck *), Bash(shfmt *), Read
argument-hint: <path-to-script>
---

## Script to review

Read the file: $ARGUMENTS

## Review Checklist

Analyze the script against these criteria:

1. **ShellCheck compliance**: Run shellcheck and report findings
2. **Formatting**: Run `shfmt -d -i 4 -ci` and report deviations
3. **Error handling**: Does it use set -euo pipefail or explicit error handling? Are command failures caught?
4. **Quoting**: Are all variables properly quoted as `"${var}"`?
5. **Security**: No hardcoded secrets, no unsafe temp files, no unvalidated input?
6. **Portability**: Any bashisms that should be flagged? (OK if shebang is #!/bin/bash)
7. **pi-gen chroot safety** (if in stage-pihole/): No systemctl, no network calls, correct use of ROOTFS_DIR?
8. **Documentation**: Does it have a file header with purpose and context?
9. **Logging**: Consistent logging pattern (logger + echo)?
10. **Idempotency**: Can the script be run multiple times safely?

Provide specific, actionable fixes for each finding.

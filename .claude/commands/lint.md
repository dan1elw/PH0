---
description: Lint and format-check all shell scripts in the repository
allowed-tools: Bash(shellcheck *), Bash(shfmt *), Bash(find *)
---

## Find all shell scripts

Scripts to check:
!`find scripts/ stage-pihole/ -name "*.sh" -type f 2>/dev/null | sort`

## Task

1. Run `shellcheck` on every `.sh` file found above
2. Run `shfmt -d -i 4 -ci` on every `.sh` file to check formatting
3. Report a summary: how many files checked, how many passed, list any issues grouped by file
4. For each issue, suggest the fix

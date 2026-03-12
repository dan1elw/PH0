---
description: Scaffold a new step in the pi-gen custom stage
allowed-tools: Read, Bash(ls *), Bash(find *)
argument-hint: <substage-number> <description>
---

## Current stage structure

!`find stage-pihole/ -type f | sort`

## Task

Create a new step in `stage-pihole/` based on: $ARGUMENTS

Follow these rules strictly:
1. Use the pi-gen stage conventions (see `.claude/skills/pi-gen/SKILL.md`)
2. Stage script starts with `#!/bin/bash -e`
3. Comment header explains what the step does and its constraints
4. Use `install -v -m <mode>` for file deployment
5. Use `${ROOTFS_DIR}` for all target paths, `${STAGE_DIR}` for source references
6. NO systemctl commands — use symlinks for service activation
7. NO network-dependent operations — defer to first-boot if needed
8. Config files go in `<substage>/files/`
9. Run shellcheck on the created script
10. Update docs/ARCHITECTURE.md if this adds a new component

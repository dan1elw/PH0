---
description: Update project documentation to reflect recent changes
allowed-tools: Read, Bash(git diff:*), Bash(git log:*)
---

## Recent changes

!`git diff --name-only HEAD~5 2>/dev/null || git diff --name-only --cached 2>/dev/null || echo "No git history available"`

!`git log --oneline -10 2>/dev/null || echo "No git history available"`

## Task

1. Review recent changes listed above
2. Check which docs need updating: README.md, docs/ARCHITECTURE.md, docs/SETUP.md, docs/TROUBLESHOOTING.md, docs/CHANGELOG.md
3. For each affected doc:
   - Update the relevant sections to match the current state
   - Keep language consistent: German for prose, English for technical terms
   - Maintain the AI-generated disclaimer in each doc
4. Update CHANGELOG.md with new entries under `[Unreleased]`
5. If the repository structure changed, update the tree in README.md

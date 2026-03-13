---
description: Open a pull request to main with a summary of all commits in the branch
allowed-tools: Bash(git log:*), Bash(git diff:*), Bash(git branch:*), Bash(git push:*), Bash(gh pr create:*), Bash(gh pr view:*)
argument-hint: [optional PR title override]
---

## Context

Current branch:
!`git branch --show-current`

Commits in this branch not yet in main:
!`git log main..HEAD --oneline`

Full commit details:
!`git log main..HEAD --format="- %s%n%b" --no-merges`

Diff stat vs main:
!`git diff main...HEAD --stat`

## Task

1. Push the current branch to origin if not already up to date:
   `git push -u origin <branch>`

2. Analyze all commits since diverging from main (not just the latest one).
   Group them by type (feat, fix, refactor, etc.) to build the PR description.

3. Write a PR title (≤70 chars) that summarizes the overall change.
   If $ARGUMENTS is provided, use it as the title instead.

4. Create the PR with `gh pr create` targeting `main`:
   - **Base:** `main`
   - **Summary:** bullet points grouped by commit type
   - **Test plan:** checklist of what to verify before merging

   Use this body format:
   ```
   ## Summary
   <grouped bullet points of changes>

   ## Test plan
   - [ ] CI passes
   - [ ] <specific checks relevant to the changes>

   🤖 Generated with [Claude Code](https://claude.com/claude-code)
   ```

5. Return the PR URL so the user can review and merge it on GitHub.

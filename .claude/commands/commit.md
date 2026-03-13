---
description: Create a conventional commit with context-aware message, then push to origin
allowed-tools: Bash(git add:*), Bash(git status:*), Bash(git diff:*), Bash(git commit:*), Bash(git push:*)
argument-hint: [optional commit message override]
---

## Context

Current status:
!`git status --short`

Staged changes:
!`git diff --cached --stat`

Unstaged changes:
!`git diff --stat`

Current branch:
!`git branch --show-current`

## Task

1. If nothing is staged, ask which files to stage (or stage all with confirmation)
2. Analyze the diff to determine the commit type:
   - `feat:` — new functionality
   - `fix:` — bug fix
   - `docs:` — documentation only
   - `chore:` — build, CI, tooling
   - `refactor:` — code change without feature/fix
   - `test:` — adding or updating tests
3. Write a conventional commit message in English
4. If $ARGUMENTS is provided, use it as the message instead
5. Show the proposed commit and ask for confirmation before committing
6. After committing, push to origin with `git push origin <branch>` (use `-u` if the branch has no upstream yet)

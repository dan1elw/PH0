---
description: Generate bats-core tests for a shell script or component
allowed-tools: Read, Bash(find *), Bash(ls *)
argument-hint: <component-name or script-path>
---

## Context

Target: $ARGUMENTS

Existing tests:
!`find tests/ -name "*.bats" -type f 2>/dev/null | sort || echo "No tests directory yet"`

## Task

1. Read the target script to understand its functions and logic
2. Create a bats-core test file in `tests/test-<component>.bats`
3. Tests should cover:
   - Happy path for each major function or phase
   - Error conditions (missing files, bad input, network failures)
   - Edge cases specific to the component
   - Idempotency where relevant (running twice produces same result)
4. Use `setup()` and `teardown()` to create/clean temp directories
5. Mock external commands (curl, pihole, systemctl) where needed
6. Follow this template for test structure:

```bash
#!/usr/bin/env bats
# test-<component>.bats – Tests for <component>

setup() {
    TEST_DIR="$(mktemp -d)"
    export TEST_DIR
}

teardown() {
    rm -rf "${TEST_DIR}"
}

@test "<component>: <what it tests>" {
    run <command>
    [ "$status" -eq 0 ]
    [[ "$output" == *"expected"* ]]
}
```

7. Also ensure `tests/run-tests.sh` exists as test runner

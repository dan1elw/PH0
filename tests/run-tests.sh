#!/bin/bash
# run-tests.sh – Run all bats-core tests
#
# Usage:
#   ./tests/run-tests.sh              # Run all tests
#   ./tests/run-tests.sh <pattern>    # Run tests matching pattern

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check for bats
if ! command -v bats &>/dev/null; then
    echo "[FEHLER] bats-core ist nicht installiert."
    echo "         sudo apt install bats"
    exit 1
fi

# Find test files
PATTERN="${1:-}"
if [ -n "${PATTERN}" ]; then
    TEST_FILES=$(find "${SCRIPT_DIR}" -name "test-*${PATTERN}*.bats" -type f | sort)
else
    TEST_FILES=$(find "${SCRIPT_DIR}" -name "test-*.bats" -type f | sort)
fi

if [ -z "${TEST_FILES}" ]; then
    echo "[INFO] Keine Test-Dateien gefunden."
    exit 0
fi

FILE_COUNT=$(echo "${TEST_FILES}" | wc -l)
echo "=========================================="
echo " PH0 Test Suite"
echo " ${FILE_COUNT} Testdatei(en) gefunden"
echo "=========================================="
echo ""

# Run bats with TAP output
bats ${TEST_FILES}

#!/usr/bin/env bats
# test-secrets-env.bats – Tests for secrets.env format and validation
#
# Validates that secrets.env.example follows the required format
# and that the first-boot script correctly handles various inputs.

setup() {
    TEST_DIR="$(mktemp -d)"
    export TEST_DIR
    PROJECT_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    export PROJECT_DIR
}

teardown() {
    rm -rf "${TEST_DIR}"
}

@test "secrets.env.example exists" {
    [ -f "${PROJECT_DIR}/secrets.env.example" ]
}

@test "secrets.env.example: all values are double-quoted" {
    # Every non-comment, non-empty line with = should have quoted value
    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ "${line}" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line}" ]] && continue
        # Lines with = should have value in double quotes
        if [[ "${line}" =~ = ]]; then
            value="${line#*=}"
            [[ "${value}" =~ ^\" ]] || {
                echo "Unquoted value in line: ${line}"
                return 1
            }
        fi
    done < "${PROJECT_DIR}/secrets.env.example"
}

@test "secrets.env.example: contains all required variables" {
    local required_vars=(
        PI_USER
        PI_USER_PASSWORD
        PIHOLE_PASSWORD
        WIFI_SSID
        WIFI_PASSWORD
        SSH_PUBLIC_KEY
    )
    for var in "${required_vars[@]}"; do
        grep -q "^${var}=" "${PROJECT_DIR}/secrets.env.example" || {
            echo "Missing required variable: ${var}"
            return 1
        }
    done
}

@test "secrets.env.example: optional variables have defaults" {
    local optional_with_defaults=(
        "WIFI_COUNTRY"
        "PI_HOSTNAME"
        "PI_IP"
        "PI_GATEWAY"
        "PI_PREFIX"
    )
    for var in "${optional_with_defaults[@]}"; do
        line=$(grep "^${var}=" "${PROJECT_DIR}/secrets.env.example")
        value="${line#*=}"
        # Should have a non-empty default (quoted)
        [[ "${value}" != '""' ]] || {
            echo "Optional variable ${var} should have a default value"
            return 1
        }
    done
}

@test "secrets.env sourcing: quoted values with spaces work" {
    cat > "${TEST_DIR}/test-secrets.env" << 'EOF'
WIFI_SSID="My Home Network"
WIFI_PASSWORD="password with spaces"
PI_USER="pi"
EOF
    # shellcheck source=/dev/null
    source "${TEST_DIR}/test-secrets.env"
    [ "${WIFI_SSID}" = "My Home Network" ]
    [ "${WIFI_PASSWORD}" = "password with spaces" ]
}

@test "secrets.env sourcing: special characters in values" {
    cat > "${TEST_DIR}/test-secrets.env" << 'EOF'
PIHOLE_PASSWORD="p@$$w0rd!#%"
SSH_PUBLIC_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExample user@host"
EOF
    # shellcheck source=/dev/null
    source "${TEST_DIR}/test-secrets.env"
    [ "${PIHOLE_PASSWORD}" = 'p@$$w0rd!#%' ]
    [[ "${SSH_PUBLIC_KEY}" == ssh-ed25519* ]]
}

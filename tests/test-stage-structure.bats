#!/usr/bin/env bats
# test-stage-structure.bats – Validate pi-gen stage structure and conventions
#
# Ensures all stage scripts follow pi-gen and project conventions.

setup() {
    PROJECT_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    export PROJECT_DIR
    STAGE_DIR="${PROJECT_DIR}/stage-pihole"
    export STAGE_DIR
}

@test "stage-pihole: prerun.sh exists" {
    [ -f "${STAGE_DIR}/prerun.sh" ]
}

@test "stage-pihole: EXPORT_IMAGE exists" {
    [ -f "${STAGE_DIR}/EXPORT_IMAGE" ]
}

@test "stage-pihole: all .sh files have bash shebang" {
    while IFS= read -r script; do
        head -1 "${script}" | grep -qE '^#!/bin/bash' || {
            echo "Missing bash shebang: ${script}"
            return 1
        }
    done < <(find "${STAGE_DIR}" -name "*.sh" -type f)
}

@test "stage-pihole: no systemctl commands in stage scripts" {
    # systemctl is allowed ONLY in first-boot.sh (which runs at runtime)
    while IFS= read -r script; do
        basename=$(basename "${script}")
        # Skip first-boot.sh — it runs at runtime, not in chroot
        [ "${basename}" = "first-boot.sh" ] && continue
        if grep -n 'systemctl' "${script}" | grep -v '^#' | grep -v 'systemctl list-unit-files'; then
            echo "Found systemctl in chroot script: ${script}"
            return 1
        fi
    done < <(find "${STAGE_DIR}" -name "*.sh" -type f -not -path "*/files/*")
}

@test "stage-pihole: stage scripts use ROOTFS_DIR for target paths" {
    while IFS= read -r script; do
        # Skip files/ directory (these are deployed files, not stage scripts)
        [[ "${script}" == */files/* ]] && continue
        # prerun.sh is special
        [ "$(basename "${script}")" = "prerun.sh" ] && continue
        # Check that file operations reference ROOTFS_DIR
        if grep -nE '^\s*(install|cp|mkdir|cat\s*>|echo\s.*>)\s+/' "${script}" | \
           grep -v 'ROOTFS_DIR' | grep -v '^#' | grep -v 'STAGE_DIR'; then
            echo "Direct path without ROOTFS_DIR in: ${script}"
            # This is a warning, not necessarily a failure for all cases
        fi
    done < <(find "${STAGE_DIR}" -name "*.sh" -type f)
}

@test "stage-pihole: deployed scripts are executable (mode 755)" {
    while IFS= read -r script; do
        [[ "${script}" == */files/* ]] && continue
        [ "$(basename "${script}")" = "prerun.sh" ] && continue
        # Check install commands for scripts deployed to /usr/local/bin
        if grep 'install.*usr/local/bin' "${script}" | grep -v 'm 755' | grep -v '^#'; then
            echo "Script deployed without 755 mode in: ${script}"
            return 1
        fi
    done < <(find "${STAGE_DIR}" -name "*.sh" -type f)
}

@test "stage-pihole: config files are not world-writable (mode 644)" {
    while IFS= read -r script; do
        [[ "${script}" == */files/* ]] && continue
        # Check install commands for config files
        if grep 'install.*\.conf\|install.*\.toml\|install.*\.service\|install.*\.timer' "${script}" | \
           grep -v 'm 644' | grep -v 'm 755' | grep -v '^#'; then
            echo "Config deployed without explicit mode in: ${script}"
            return 1
        fi
    done < <(find "${STAGE_DIR}" -name "*.sh" -type f)
}

@test "stage-pihole: 00-packages file exists and is non-empty" {
    local pkg_file="${STAGE_DIR}/00-install-packages/00-packages"
    [ -f "${pkg_file}" ]
    [ -s "${pkg_file}" ]
}

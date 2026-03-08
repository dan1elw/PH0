#!/bin/bash
# validate.sh – Post-Boot Validierung des Pi-hole Images
#
# Führt automatische Tests gegen den laufenden Pi durch.
# Verwendung: ./scripts/validate.sh [IP-Adresse]

set -euo pipefail

PI_HOST="${1:-192.168.178.49}"
PI_USER="pi"
PASSED=0
FAILED=0
TOTAL=0

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

test_result() {
    TOTAL=$((TOTAL + 1))
    local name="$1"
    local result="$2"

    if [ "${result}" -eq 0 ]; then
        PASSED=$((PASSED + 1))
        printf "${GREEN}[PASS]${NC} %s\n" "${name}"
    else
        FAILED=$((FAILED + 1))
        printf "${RED}[FAIL]${NC} %s\n" "${name}"
    fi
}

echo ""
echo "=========================================="
echo " Pi-hole Image Validierung"
echo " Ziel: ${PI_USER}@${PI_HOST}"
echo "=========================================="
echo ""

# ============================================================
# Netzwerk-Tests (vom lokalen Rechner aus)
# ============================================================
echo "--- Netzwerk ---"

# Ping
ping -c 1 -W 5 "${PI_HOST}" > /dev/null 2>&1
test_result "Ping erreichbar" $?

# SSH
ssh -o ConnectTimeout=5 -o BatchMode=yes "${PI_USER}@${PI_HOST}" "echo ok" > /dev/null 2>&1
test_result "SSH-Verbindung" $?

# DNS
dig @"${PI_HOST}" google.com +short +time=5 +tries=1 > /dev/null 2>&1
test_result "DNS-Auflösung (google.com)" $?

# Pi-hole Web UI
curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 \
    "http://${PI_HOST}/admin/" | grep -q "200\|302"
test_result "Pi-hole Web UI erreichbar" $?

# Pi-hole API
curl -s --connect-timeout 5 "http://${PI_HOST}/api/info" | jq -e '.version' > /dev/null 2>&1
test_result "Pi-hole REST API" $?

# ============================================================
# Remote-Tests (via SSH auf dem Pi)
# ============================================================
echo ""
echo "--- Services ---"

run_remote() {
    ssh -o ConnectTimeout=5 -o BatchMode=yes "${PI_USER}@${PI_HOST}" "$1" 2>/dev/null
}

# pihole-FTL
run_remote "systemctl is-active pihole-FTL" | grep -q "active"
test_result "pihole-FTL Service aktiv" $?

# Log2RAM
run_remote "systemctl is-active log2ram" | grep -q "active"
test_result "Log2RAM Service aktiv" $?

# WLAN-Monitor
run_remote "systemctl is-active wlan-monitor" | grep -q "active"
test_result "WLAN-Monitor Service aktiv" $?

# Health-Check Timer
run_remote "systemctl is-active health-check.timer" | grep -q "active"
test_result "Health-Check Timer aktiv" $?

# Watchdog
run_remote "systemctl is-active watchdog" | grep -q "active"
test_result "Watchdog Service aktiv" $?

# nftables
run_remote "systemctl is-active nftables" | grep -q "active"
test_result "nftables Firewall aktiv" $?

echo ""
echo "--- System ---"

# Log2RAM Mount
run_remote "df /var/log" | grep -q "tmpfs\|log2ram"
test_result "Log2RAM /var/log gemountet" $?

# tmpfs /tmp
run_remote "df /tmp" | grep -q "tmpfs"
test_result "tmpfs /tmp gemountet" $?

# Swap deaktiviert
run_remote "free | grep -i swap" | grep -q " 0 "
test_result "Swap deaktiviert" $?

# SSH Key-Only
run_remote "grep -q 'PasswordAuthentication no' /etc/ssh/sshd_config"
test_result "SSH Passwort-Login deaktiviert" $?

# First-Boot Service deaktiviert
run_remote "systemctl is-enabled first-boot.service 2>/dev/null" | grep -q "disabled"
test_result "First-Boot Service deaktiviert" $?

# secrets.env gelöscht
run_remote "test ! -f /boot/firmware/secrets.env && test ! -f /boot/secrets.env"
test_result "secrets.env gelöscht" $?

# ============================================================
# Ergebnis
# ============================================================
echo ""
echo "=========================================="
printf " Ergebnis: ${GREEN}${PASSED} bestanden${NC}, "
if [ ${FAILED} -gt 0 ]; then
    printf "${RED}${FAILED} fehlgeschlagen${NC}"
else
    printf "${GREEN}${FAILED} fehlgeschlagen${NC}"
fi
echo " (${TOTAL} Tests)"
echo "=========================================="
echo ""

if [ ${FAILED} -gt 0 ]; then
    echo "Einige Tests sind fehlgeschlagen. Prüfe die betroffenen Services."
    exit 1
else
    echo "Alle Tests bestanden! Pi-hole ist einsatzbereit."
    exit 0
fi

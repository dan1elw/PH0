#!/bin/bash
# validate.sh – Post-Boot Validierung des Pi-hole Images
#
# Führt automatische Tests gegen den laufenden Pi durch.
# Verwendung:
#   ./scripts/validate.sh                    # Liest PI_IP + PI_USER aus secrets.env
#   ./scripts/validate.sh 192.168.178.50     # Andere IP
#   ./scripts/validate.sh 192.168.178.50 admin  # Andere IP + User
#   ./scripts/validate.sh --wait             # Wartet bis Pi erreichbar ist

# KEIN set -e! Tests dürfen fehlschlagen ohne das Script abzubrechen.
set -uo pipefail

trap 'echo ""; echo "Abbruch."; exit 130' INT TERM

# Standardwerte aus secrets.env laden (immer, falls vorhanden)
SECRETS_ENV="$(dirname "$0")/../secrets.env"
_DEFAULT_HOST="192.168.178.49"
_DEFAULT_USER="pi"
if [ -f "${SECRETS_ENV}" ]; then
    # shellcheck source=/dev/null
    source "${SECRETS_ENV}"
    _DEFAULT_HOST="${PI_IP:-${_DEFAULT_HOST}}"
    _DEFAULT_USER="${PI_USER:-${_DEFAULT_USER}}"
fi

PI_HOST="${1:-${_DEFAULT_HOST}}"
PI_USER="${2:-${_DEFAULT_USER}}"
WAIT_MODE=false
PASSED=0
FAILED=0
SKIPPED=0
TOTAL=0

# --wait als erstes Argument erkennen
if [ "${PI_HOST}" = "--wait" ]; then
    WAIT_MODE=true
    PI_HOST="${2:-${_DEFAULT_HOST}}"
    PI_USER="${3:-${_DEFAULT_USER}}"
fi

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

SSH_OPTS="-o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"

# ============================================================
# Abhängigkeiten prüfen
# ============================================================
MISSING_DEPS=""
for cmd in ssh curl ping; do
    if ! command -v "${cmd}" > /dev/null 2>&1; then
        MISSING_DEPS="${MISSING_DEPS} ${cmd}"
    fi
done
# dig und jq sind optional
HAS_DIG=false
HAS_JQ=false
command -v dig > /dev/null 2>&1 && HAS_DIG=true
command -v jq > /dev/null 2>&1 && HAS_JQ=true

if [ -n "${MISSING_DEPS}" ]; then
    echo "[FEHLER] Fehlende Abhängigkeiten:${MISSING_DEPS}"
    echo "         sudo apt install${MISSING_DEPS}"
    exit 1
fi

# ============================================================
# Test-Funktionen
# ============================================================
test_pass() {
    TOTAL=$((TOTAL + 1))
    PASSED=$((PASSED + 1))
    printf "${GREEN}[PASS]${NC} %s\n" "$1"
}

test_fail() {
    TOTAL=$((TOTAL + 1))
    FAILED=$((FAILED + 1))
    printf "${RED}[FAIL]${NC} %s\n" "$1"
}

test_skip() {
    TOTAL=$((TOTAL + 1))
    SKIPPED=$((SKIPPED + 1))
    printf "${YELLOW}[SKIP]${NC} %s (%s)\n" "$1" "$2"
}

run_test() {
    local name="$1"
    shift
    if "$@" > /dev/null 2>&1; then
        test_pass "${name}"
    else
        test_fail "${name}"
    fi
}

run_remote() {
    ssh ${SSH_OPTS} "${PI_USER}@${PI_HOST}" "$1" 2>/dev/null
}

run_remote_test() {
    local name="$1"
    local cmd="$2"
    local result
    result=$(run_remote "${cmd}" 2>/dev/null) || true
    if [ -n "${result}" ]; then
        test_pass "${name}"
    else
        test_fail "${name}"
    fi
}

# ============================================================
# Warten bis Pi erreichbar ist
# ============================================================
if [ "${WAIT_MODE}" = true ]; then
    echo ""
    echo "[INFO] Warte bis ${PI_HOST} erreichbar ist..."
    echo "       (First Boot mit Pi-hole Installation kann 5-10 Minuten dauern)"
    echo "       Abbruch mit Ctrl+C"
    echo ""
    for i in $(seq 1 120); do
        if ping -c 1 -W 2 "${PI_HOST}" > /dev/null 2>&1; then
            echo "[INFO] Pi antwortet auf Ping nach ${i}x2 Sekunden."
            # Warte noch etwas damit alle Services hochkommen
            echo "[INFO] Warte weitere 30 Sekunden auf Service-Start..."
            sleep 30
            break
        fi
        printf "."
        sleep 2
    done
    echo ""
fi

echo ""
echo "=========================================="
echo " Pi-hole Image Validierung"
echo " Ziel: ${PI_USER}@${PI_HOST}"
echo "=========================================="

# ============================================================
# Netzwerk-Tests (vom lokalen Rechner aus)
# ============================================================
echo ""
echo "--- Netzwerk ---"

# Ping ist Voraussetzung für alle weiteren Tests
PING_OK=false
if ping -c 1 -W 5 "${PI_HOST}" > /dev/null 2>&1; then
    test_pass "Ping erreichbar"
    PING_OK=true
else
    test_fail "Ping erreichbar"
fi

if [ "${PING_OK}" = false ]; then
    echo ""
    echo "=========================================="
    printf " Ergebnis: ${RED}Pi nicht erreichbar${NC}\n"
    echo "=========================================="
    echo ""
    echo " ${PI_HOST} antwortet nicht auf Ping."
    echo ""
    echo " Mögliche Ursachen:"
    echo "   • First Boot läuft noch (Pi-hole Installation dauert 5-10 Min)"
    echo "   • WiFi-Verbindung fehlgeschlagen (falsche SSID/Passwort in secrets.env?)"
    echo "   • Falsche IP-Adresse (erwartet: ${PI_HOST})"
    echo "   • Pi hat keine Stromversorgung oder bootet noch"
    echo ""
    echo " Erneut prüfen mit:"
    echo "   ./scripts/validate.sh --wait"
    echo ""
    exit 1
fi

# Prüfe ob SSH funktioniert, bevor wir Remote-Tests machen
SSH_OK=false
if ssh ${SSH_OPTS} "${PI_USER}@${PI_HOST}" "echo ok" > /dev/null 2>&1; then
    test_pass "SSH-Verbindung"
    SSH_OK=true
else
    test_fail "SSH-Verbindung"
fi

if [ "${HAS_DIG}" = true ]; then
    run_test "DNS-Auflösung (google.com)" dig @"${PI_HOST}" google.com +short +time=5 +tries=1
else
    test_skip "DNS-Auflösung (google.com)" "dig nicht installiert"
fi

# Pi-hole Web UI
if curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 \
    "http://${PI_HOST}/admin/" 2>/dev/null | grep -qE "200|302|301"; then
    test_pass "Pi-hole Web UI erreichbar"
else
    test_fail "Pi-hole Web UI erreichbar"
fi

# Pi-hole API
if [ "${HAS_JQ}" = true ]; then
    if curl -s --connect-timeout 5 "http://${PI_HOST}/api/info" 2>/dev/null | jq -e '.' > /dev/null 2>&1; then
        test_pass "Pi-hole REST API"
    else
        test_fail "Pi-hole REST API"
    fi
else
    test_skip "Pi-hole REST API" "jq nicht installiert"
fi

# ============================================================
# Remote-Tests (via SSH auf dem Pi)
# ============================================================
if [ "${SSH_OK}" = false ]; then
    echo ""
    printf "${YELLOW}[INFO]${NC} SSH nicht verfügbar – Remote-Tests übersprungen.\n"
    echo "       Pi ist erreichbar (Ping OK), aber SSH schlägt fehl."
    echo "       Mögliche Ursachen:"
    echo "         • First Boot noch nicht abgeschlossen"
    echo "         • SSH-Key stimmt nicht überein"
    echo "         • Falscher Benutzer (erwartet: ${PI_USER})"
    echo "       Debug: ssh -v ${PI_USER}@${PI_HOST}"
else
    echo ""
    echo "--- Services ---"

    for svc in pihole-FTL log2ram wlan-monitor watchdog nftables; do
        result=$(run_remote "systemctl is-active ${svc} 2>/dev/null" || echo "inactive")
        if echo "${result}" | grep -q "^active"; then
            test_pass "${svc} Service aktiv"
        else
            test_fail "${svc} Service aktiv (Status: ${result})"
        fi
    done

    # Health-Check Timer
    result=$(run_remote "systemctl is-active health-check.timer 2>/dev/null" || echo "inactive")
    if echo "${result}" | grep -q "^active"; then
        test_pass "health-check.timer aktiv"
    else
        test_fail "health-check.timer aktiv (Status: ${result})"
    fi

    echo ""
    echo "--- System ---"

    # Log2RAM Mount
    result=$(run_remote "df /var/log 2>/dev/null" || echo "")
    if echo "${result}" | grep -qE "tmpfs|log2ram"; then
        test_pass "Log2RAM /var/log gemountet"
    else
        test_fail "Log2RAM /var/log gemountet"
    fi

    # tmpfs /tmp
    result=$(run_remote "df /tmp 2>/dev/null" || echo "")
    if echo "${result}" | grep -q "tmpfs"; then
        test_pass "tmpfs /tmp gemountet"
    else
        test_fail "tmpfs /tmp gemountet"
    fi

    # Swap deaktiviert
    result=$(run_remote "swapon --show 2>/dev/null" || echo "")
    if [ -z "${result}" ]; then
        test_pass "Swap deaktiviert"
    else
        test_fail "Swap deaktiviert"
    fi

    # SSH Key-Only
    result=$(run_remote "grep '^PasswordAuthentication no' /etc/ssh/sshd_config 2>/dev/null" || echo "")
    if [ -n "${result}" ]; then
        test_pass "SSH Passwort-Login deaktiviert"
    else
        test_fail "SSH Passwort-Login deaktiviert"
    fi

    # First-Boot Service deaktiviert
    result=$(run_remote "systemctl is-enabled first-boot.service 2>/dev/null" || echo "unknown")
    if echo "${result}" | grep -q "disabled"; then
        test_pass "First-Boot Service deaktiviert"
    else
        test_fail "First-Boot Service deaktiviert (Status: ${result})"
    fi

    # secrets.env gelöscht
    result=$(run_remote "test ! -f /boot/firmware/secrets.env && test ! -f /boot/secrets.env && echo ok" || echo "")
    if [ "${result}" = "ok" ]; then
        test_pass "secrets.env gelöscht"
    else
        test_fail "secrets.env gelöscht"
    fi

    # Hostname
    result=$(run_remote "hostname" || echo "")
    if [ -n "${result}" ]; then
        test_pass "Hostname: ${result}"
    else
        test_fail "Hostname abrufbar"
    fi

    # Uptime + Temperatur (Info, kein Pass/Fail)
    echo ""
    echo "--- Info ---"
    uptime_result=$(run_remote "uptime -p" || echo "unbekannt")
    temp_result=$(run_remote "cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null" || echo "")
    if [ -n "${temp_result}" ]; then
        temp_c=$((temp_result / 1000))
        echo "  Uptime:      ${uptime_result}"
        echo "  Temperatur:  ${temp_c}°C"
    else
        echo "  Uptime:      ${uptime_result}"
    fi
    mem_result=$(run_remote "free -m | awk '/Mem:/ {printf \"%s/%s MB (%.0f%% frei)\", \$7, \$2, \$7/\$2*100}'" || echo "unbekannt")
    echo "  RAM:         ${mem_result}"
fi

# ============================================================
# Ergebnis
# ============================================================
echo ""
echo "=========================================="
printf " Ergebnis: ${GREEN}${PASSED} bestanden${NC}"
if [ ${FAILED} -gt 0 ]; then
    printf ", ${RED}${FAILED} fehlgeschlagen${NC}"
fi
if [ ${SKIPPED} -gt 0 ]; then
    printf ", ${YELLOW}${SKIPPED} übersprungen${NC}"
fi
echo " (${TOTAL} Tests)"
echo "=========================================="
echo ""

PIHOLE_OK=false
if curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 \
    "http://${PI_HOST}/admin/" 2>/dev/null | grep -qE "200|302|301"; then
    PIHOLE_OK=true
fi

if [ ${FAILED} -gt 0 ]; then
    echo "Einige Tests sind fehlgeschlagen. Prüfe die betroffenen Services."
    if [ "${SSH_OK}" = true ]; then
        echo "Debug: ssh ${PI_USER}@${PI_HOST} 'journalctl -b --no-pager | tail -50'"
        echo "First-Boot Log: ssh ${PI_USER}@${PI_HOST} 'cat /var/log/first-boot.log'"
    fi
else
    echo "Alle Tests bestanden! Pi-hole ist einsatzbereit."
fi

if [ "${PIHOLE_OK}" = true ]; then
    echo ""
    echo "  Pi-hole Admin: http://${PI_HOST}/admin"
    echo ""
fi

[ ${FAILED} -gt 0 ] && exit 1 || exit 0

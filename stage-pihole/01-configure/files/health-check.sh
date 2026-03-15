#!/bin/bash
# health-check.sh – Pi-hole Gesundheitsprüfung
#
# Wird alle 5 Minuten via systemd Timer ausgeführt.
# Prüft: DNS-Auflösung, Pi-hole FTL Status, Speicher, Temperatur, SD-Karte
# Loggt Ergebnisse nach journald.

readonly LOG_TAG="health-check"
readonly HEALTH_LOG="/var/log/pihole-health.log"
ERRORS=0

log_info() {
    logger -t "${LOG_TAG}" -p daemon.info "$1"
}

log_warn() {
    logger -t "${LOG_TAG}" -p daemon.warning "$1"
}

log_err() {
    logger -t "${LOG_TAG}" -p daemon.err "$1"
    ERRORS=$((ERRORS + 1))
}

timestamp=$(date -Iseconds)

# ============================================================
# 1. DNS-Auflösung testen
# ============================================================
if dig @127.0.0.1 google.com +short +time=5 +tries=1 >/dev/null 2>&1; then
    dns_status="OK"
else
    dns_status="FAIL"
    log_err "DNS-Auflösung über Pi-hole fehlgeschlagen!"

    # Versuche Pi-hole FTL neu zu starten
    if systemctl is-active --quiet pihole-FTL; then
        log_warn "FTL läuft, aber DNS schlägt fehl. Prüfe Upstream-DNS..."
        # Teste Upstream direkt
        if ! dig @1.1.1.1 google.com +short +time=5 +tries=1 >/dev/null 2>&1; then
            log_err "Upstream-DNS (1.1.1.1) ebenfalls nicht erreichbar – Netzwerkproblem!"
        fi
    else
        log_err "Pi-hole FTL ist nicht aktiv! Starte neu..."
        systemctl restart pihole-FTL
    fi
fi

# ============================================================
# 2. Pi-hole FTL Status
# ============================================================
if systemctl is-active --quiet pihole-FTL; then
    ftl_status="OK"
else
    ftl_status="FAIL"
    log_err "pihole-FTL Service ist nicht aktiv!"
fi

# ============================================================
# 3. Speicher (RAM)
# ============================================================
mem_available=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
mem_total=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
mem_percent=$((100 * mem_available / mem_total))

if [ "${mem_percent}" -lt 10 ]; then
    mem_status="CRITICAL (${mem_percent}% frei)"
    log_err "Kritisch wenig RAM verfügbar: ${mem_percent}% (${mem_available} kB)"
elif [ "${mem_percent}" -lt 20 ]; then
    mem_status="WARNING (${mem_percent}% frei)"
    log_warn "Wenig RAM verfügbar: ${mem_percent}% (${mem_available} kB)"
else
    mem_status="OK (${mem_percent}% frei)"
fi

# ============================================================
# 4. CPU-Temperatur
# ============================================================
if [ -f /sys/class/thermal/thermal_zone0/temp ]; then
    temp_raw=$(< /sys/class/thermal/thermal_zone0/temp)
    temp_c=$((temp_raw / 1000))

    if [ "${temp_c}" -gt 75 ]; then
        temp_status="CRITICAL (${temp_c}°C)"
        log_err "CPU-Temperatur kritisch: ${temp_c}°C"
    elif [ "${temp_c}" -gt 65 ]; then
        temp_status="WARNING (${temp_c}°C)"
        log_warn "CPU-Temperatur erhöht: ${temp_c}°C"
    else
        temp_status="OK (${temp_c}°C)"
    fi
else
    temp_status="N/A"
fi

# ============================================================
# 5. SD-Karte (Dateisystem-Fehler prüfen)
# ============================================================
if dmesg | tail -50 | grep -Eqi "i/o error|read-only|ext4-fs error"; then
    sd_status="WARNING"
    log_warn "Mögliche SD-Karten-Probleme in dmesg erkannt!"
else
    sd_status="OK"
fi

# ============================================================
# 6. Log2RAM Status
# ============================================================
if systemctl is-active --quiet log2ram; then
    log2ram_status="OK"
    log2ram_usage=$(df -h /var/log | awk 'NR==2 {print $5}')
    log2ram_status="${log2ram_status} (${log2ram_usage} belegt)"
else
    log2ram_status="FAIL"
    log_err "Log2RAM Service ist nicht aktiv!"
fi

# ============================================================
# Ergebnis loggen
# ============================================================
summary="DNS=${dns_status} FTL=${ftl_status} RAM=${mem_status} TEMP=${temp_status} SD=${sd_status} LOG2RAM=${log2ram_status}"

if [ "${ERRORS}" -eq 0 ]; then
    log_info "Health-Check OK: ${summary}"
else
    log_err "Health-Check: ${ERRORS} Fehler! ${summary}"
fi

# Persistentes Log (für Langzeit-Monitoring)
echo "${timestamp} | ${summary}" >>"${HEALTH_LOG}"

# Optional: Webhook bei Fehler auslösen
# Auskommentieren und URL anpassen wenn gewünscht:
# if [ ${ERRORS} -gt 0 ]; then
#     curl -s -o /dev/null -X POST \
#         -H "Content-Type: application/json" \
#         -d "{\"text\":\"Pi-hole Health-Check: ${ERRORS} Fehler! ${summary}\"}" \
#         "https://hooks.example.com/your-webhook-url"
# fi

# Non-zero Exit-Code veranlasst systemd die Unit als failed zu markieren –
# das ist gewollt: journalctl zeigt dann "health-check.service: Failed".
exit "${ERRORS}"

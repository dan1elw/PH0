#!/bin/bash
# wlan-monitor.sh – WLAN-Verbindungsüberwachung und Auto-Reconnect
#
# Prüft alle 30 Sekunden die WLAN-Verbindung.
# Bei Verbindungsverlust wird wlan0 neu initialisiert.
# Nach 5 fehlgeschlagenen Versuchen wird ein Neustart ausgelöst.

readonly INTERFACE="wlan0"
readonly GATEWAY="192.168.178.1"
readonly MAX_FAILURES=5
readonly CHECK_INTERVAL=30
readonly LOG_TAG="wlan-monitor"

failure_count=0

log_info() {
    logger -t "${LOG_TAG}" -p daemon.info "$1"
}

log_warn() {
    logger -t "${LOG_TAG}" -p daemon.warning "$1"
}

log_err() {
    logger -t "${LOG_TAG}" -p daemon.err "$1"
}

restart_interface() {
    log_warn "WLAN-Verbindung verloren. Starte ${INTERFACE} neu..."
    # down + kurze Pause + up: brcmfmac (SDIO auf Pi Zero W) braucht
    # eine explizite Pause zwischen down und up für sauberes Re-Init.
    # sleep 10 danach: Zeit für wpa_supplicant und NM zum Reconnect.
    ip link set "${INTERFACE}" down
    sleep 2
    ip link set "${INTERFACE}" up
    sleep 10
}

while true; do
    # Prüfe ob Interface existiert
    if ! ip link show "${INTERFACE}" >/dev/null 2>&1; then
        log_err "Interface ${INTERFACE} nicht gefunden!"
        sleep "${CHECK_INTERVAL}"
        continue
    fi

    # Prüfe Verbindung via Ping zum Gateway
    if ping -c 1 -W 5 -I "${INTERFACE}" "${GATEWAY}" >/dev/null 2>&1; then
        # Verbindung OK
        if [ ${failure_count} -gt 0 ]; then
            log_info "WLAN-Verbindung wiederhergestellt nach ${failure_count} Fehlversuchen."
        fi
        failure_count=0
    else
        failure_count=$((failure_count + 1))
        log_warn "WLAN-Ping fehlgeschlagen (${failure_count}/${MAX_FAILURES})"

        if [ ${failure_count} -ge ${MAX_FAILURES} ]; then
            log_err "Maximale Fehlversuche erreicht. Starte System neu..."
            # sync vor reboot: sicherstellen dass Logs auf der SD-Karte landen.
            echo "$(date -Iseconds) WLAN-Monitor: Neustart nach ${MAX_FAILURES} Fehlversuchen" \
                >>/var/log/pihole-crashes.log
            sync
            reboot
        fi

        restart_interface
    fi

    sleep "${CHECK_INTERVAL}"
done

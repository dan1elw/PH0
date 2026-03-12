#!/bin/bash
# first-boot.sh – Ersteinrichtung beim ersten Boot
#
# Dieses Script läuft EINMALIG beim allerersten Start des Pi.
# Es installiert Pi-hole und Log2RAM (brauchen Netzwerk + systemd),
# konfiguriert WiFi, SSH, und aktiviert alle Services.
# Danach löscht es die secrets.env und deaktiviert sich selbst.

# Kein set -e: Fehler werden pro Phase explizit behandelt
set -uo pipefail

LOG_TAG="first-boot"
BOOT_PARTITION="/boot/firmware"
SECRETS_FILE="${BOOT_PARTITION}/secrets.env"
LOGFILE="/var/log/first-boot.log"
FAILED_PHASES=()
SCRIPT_START=$(date +%s)
PHASE_START=${SCRIPT_START}

# Alles loggen
exec > >(tee -a "${LOGFILE}") 2>&1

log_info() {
    logger -t "${LOG_TAG}" -p daemon.info -- "$1"
    echo "[INFO]  $(date '+%H:%M:%S') $1"
}

log_warn() {
    logger -t "${LOG_TAG}" -p daemon.warning -- "$1"
    echo "[WARN]  $(date '+%H:%M:%S') $1"
}

log_err() {
    logger -t "${LOG_TAG}" -p daemon.err -- "$1"
    echo "[ERROR] $(date '+%H:%M:%S') $1" >&2
}

phase_start() {
    PHASE_START=$(date +%s)
    log_info "----------------------------------------------------------------"
    log_info "Phase $1: $2"
}

phase_end() {
    local elapsed=$(( $(date +%s) - PHASE_START ))
    log_info "Phase $1 abgeschlossen (${elapsed}s)"
}

phase_fail() {
    local elapsed=$(( $(date +%s) - PHASE_START ))
    log_err "Phase $1 fehlgeschlagen (${elapsed}s)"
    FAILED_PHASES+=("$1")
}

# Wie phase_end, aber nur wenn diese Phase nicht schon als fehlgeschlagen markiert wurde
phase_end_or_skip() {
    local num=$1
    for p in "${FAILED_PHASES[@]}"; do
        [ "$p" = "$num" ] && return 0
    done
    phase_end "$num"
}

# ============================================================
# Prüfe ob secrets.env vorhanden ist
# ============================================================
if [ ! -f "${SECRETS_FILE}" ]; then
    BOOT_PARTITION="/boot"
    SECRETS_FILE="${BOOT_PARTITION}/secrets.env"
    if [ ! -f "${SECRETS_FILE}" ]; then
        log_err "secrets.env nicht gefunden auf der Boot-Partition!"
        exit 1
    fi
fi

log_info "================================================================"
log_info "=== Pi-hole First Boot gestartet ==="
log_info "Kernel: $(uname -r)"
log_info "Uptime: $(uptime -p 2>/dev/null || uptime)"
log_info "secrets.env: ${SECRETS_FILE}"

# ============================================================
# secrets.env einlesen
# ============================================================
# shellcheck source=/dev/null
source "${SECRETS_FILE}"

for var in PI_USER PI_USER_PASSWORD PIHOLE_PASSWORD WIFI_SSID WIFI_PASSWORD SSH_PUBLIC_KEY; do
    if [ -z "${!var:-}" ]; then
        log_err "Pflichtfeld ${var} ist nicht gesetzt in secrets.env!"
        exit 1
    fi
done

WIFI_COUNTRY="${WIFI_COUNTRY:-DE}"
PI_HOSTNAME="${PI_HOSTNAME:-pihole}"
PI_IP="${PI_IP:-192.168.178.49}"
PI_GATEWAY="${PI_GATEWAY:-192.168.178.1}"
PI_PREFIX="${PI_PREFIX:-24}"

log_info "Konfiguration: Hostname=${PI_HOSTNAME}, IP=${PI_IP}/${PI_PREFIX}, GW=${PI_GATEWAY}"
log_info "WiFi: SSID=${WIFI_SSID}, Land=${WIFI_COUNTRY}"
log_info "Benutzer: ${PI_USER}"

# ============================================================
# 1. Hostname setzen
# ============================================================
phase_start 1 "Hostname setzen"

if hostnamectl set-hostname "${PI_HOSTNAME}"; then
    log_info "Hostname gesetzt: ${PI_HOSTNAME}"
else
    log_warn "hostnamectl fehlgeschlagen – schreibe direkt nach /etc/hostname"
    echo "${PI_HOSTNAME}" > /etc/hostname || log_err "Hostname konnte nicht gesetzt werden!"
fi

if grep -q "127.0.1.1" /etc/hosts; then
    sed -i "s/127.0.1.1.*/127.0.1.1\t${PI_HOSTNAME}/" /etc/hosts
else
    printf "127.0.1.1\t%s\n" "${PI_HOSTNAME}" >> /etc/hosts
fi
log_info "/etc/hosts aktualisiert"

phase_end 1

# ============================================================
# 2. Benutzer konfigurieren
# ============================================================
phase_start 2 "Benutzer konfigurieren"
FIRST_USER_NAME="pi"

if id -u "${PI_USER}" &>/dev/null; then
    log_info "Benutzer ${PI_USER} existiert bereits."
elif id -u "${FIRST_USER_NAME}" &>/dev/null && [ "${PI_USER}" != "${FIRST_USER_NAME}" ]; then
    log_info "Benenne Default-Benutzer '${FIRST_USER_NAME}' um zu '${PI_USER}'..."
    if usermod -l "${PI_USER}" -d "/home/${PI_USER}" -m "${FIRST_USER_NAME}" && \
       groupmod -n "${PI_USER}" "${FIRST_USER_NAME}"; then
        log_info "Umbenennung erfolgreich."
    else
        log_warn "Umbenennung fehlgeschlagen – lege neuen Benutzer an."
        if ! useradd -m -s /bin/bash -G sudo "${PI_USER}"; then
            log_err "useradd für ${PI_USER} fehlgeschlagen!"
            phase_fail 2
        fi
    fi
else
    log_info "Lege neuen Benutzer an: ${PI_USER}"
    if useradd -m -s /bin/bash -G sudo "${PI_USER}"; then
        log_info "Benutzer ${PI_USER} angelegt."
    else
        log_err "useradd für ${PI_USER} fehlgeschlagen!"
        phase_fail 2
    fi
fi

if echo "${PI_USER}:${PI_USER_PASSWORD}" | chpasswd; then
    log_info "Passwort für ${PI_USER} gesetzt."
else
    log_err "Passwort für ${PI_USER} konnte nicht gesetzt werden!"
    phase_fail 2
fi

phase_end_or_skip 2

# ============================================================
# 3. WiFi konfigurieren
# ============================================================
phase_start 3 "WiFi konfigurieren"
log_info "SSID: ${WIFI_SSID}, Land: ${WIFI_COUNTRY}"

# rfkill Status
rfkill unblock wifi 2>/dev/null || true
log_info "rfkill Status: $(rfkill list 2>/dev/null | tr '\n' ' ' || echo 'unbekannt')"

# Regulatory Domain setzen und WiFi-Stack über NM-Radio-Toggle neu initialisieren.
# Hintergrund: brcmfmac (SDIO) startet ohne country= in config.txt ohne Regulatory Domain.
# NM's wpa_supplicant markiert wlan0 dann als "unavailable".
# Fix: iw reg set → nmcli radio wifi off/on → wpa_supplicant startet neu mit korrektem Domain.
log_info "Setze Regulatory domain: ${WIFI_COUNTRY}"
echo "REGDOMAIN=${WIFI_COUNTRY}" > /etc/default/crda 2>/dev/null || true
iw reg set "${WIFI_COUNTRY}" 2>/dev/null || true

log_info "WiFi-Radio neu initialisieren (nmcli radio off/on)..."
nmcli radio wifi off 2>/dev/null || true
sleep 3
nmcli radio wifi on 2>/dev/null || true
sleep 5

log_info "NM Radio-Status: $(nmcli radio 2>/dev/null | tr '\n' ' ' || echo 'unbekannt')"
log_info "Kernel brcmfmac Status: $(dmesg 2>/dev/null | grep -E "brcm|wlan0" | tail -5 | tr '\n' '|' || true)"

# Warte auf wlan0 "disconnected" state (max. 60s)
log_info "Warte auf wlan0 (max. 60s)..."
WLAN_READY=false
for i in $(seq 1 60); do
    STATE=$(nmcli -t -f DEVICE,STATE device status 2>/dev/null | grep "^wlan0:" | cut -d: -f2 || echo "")
    case "${STATE}" in
        disconnected|connected)
            log_info "wlan0 nach ${i}s bereit (Status: ${STATE})."
            WLAN_READY=true
            break
            ;;
        unmanaged)
            if [ $(( i % 15 )) -eq 0 ]; then
                log_info "wlan0 unmanaged (${i}/60s) – erzwinge NM-Verwaltung..."
                nmcli device set wlan0 managed yes 2>/dev/null || true
            fi
            ;;
        unavailable)
            if [ $(( i % 15 )) -eq 0 ]; then
                log_info "wlan0 noch unavailable (${i}/60s)."
            fi
            ;;
    esac
    sleep 1
done

if [ "${WLAN_READY}" = false ]; then
    log_warn "wlan0 nach 60s nicht bereit (Status: $(nmcli -t -f DEVICE,STATE device status 2>/dev/null | grep "^wlan0:" | cut -d: -f2 || echo "unbekannt"))."
    log_info "ip link: $(ip link show wlan0 2>/dev/null | head -1 || echo 'nicht gefunden')"
    log_info "dmesg: $(dmesg 2>/dev/null | grep -E "brcm|wlan0" | tail -5 | tr '\n' '|' || true)"
fi

# Scan-Ergebnisse zur Diagnose loggen
nmcli device wifi rescan ifname wlan0 2>/dev/null || true
sleep 5
log_info "Sichtbare Netzwerke (Diagnose):"
nmcli -t -f SSID device wifi list ifname wlan0 2>/dev/null | head -20 || true

# Verbindungsprofil anlegen – NM scannt intern beim Aktivieren
log_info "Lege Verbindungsprofil an..."
nmcli connection delete "pihole-wifi" 2>/dev/null || true

WIFI_CONNECTED=false
if nmcli connection add \
        type wifi \
        con-name "pihole-wifi" \
        ifname wlan0 \
        ssid "${WIFI_SSID}" \
        wifi-sec.key-mgmt wpa-psk \
        wifi-sec.psk "${WIFI_PASSWORD}" \
        ipv4.method manual \
        ipv4.addresses "${PI_IP}/${PI_PREFIX}" \
        ipv4.gateway "${PI_GATEWAY}" \
        ipv4.dns "${PI_GATEWAY}" \
        wifi.cloned-mac-address stable \
        connection.autoconnect yes 2>&1; then
    log_info "Verbindungsprofil erstellt."

    for attempt in $(seq 1 3); do
        log_info "Aktiviere WiFi-Verbindung, Versuch ${attempt}/3 (max. 120s)..."
        # -w: globaler nmcli-Timeout (ältere Versionen kennen kein --timeout bei connection up)
        if nmcli -w 120 connection up "pihole-wifi" 2>&1; then
            log_info "WiFi verbunden (Versuch ${attempt})."
            WIFI_CONNECTED=true
            break
        else
            log_warn "Verbindungsversuch ${attempt} fehlgeschlagen."
            if [ "${attempt}" -lt 3 ]; then
                log_info "Warte 15s vor nächstem Versuch..."
                sleep 15
            fi
        fi
    done
else
    log_err "Verbindungsprofil konnte nicht erstellt werden!"
fi

if [ "${WIFI_CONNECTED}" = true ]; then
    # DNS manuell setzen: NM schreibt resolv.conf nicht wenn dns=none konfiguriert ist
    # (dns=none ist nötig damit Pi-hole DNS übernimmt – aber vor Installation brauchen wir DNS)
    echo "nameserver ${PI_GATEWAY}" > /etc/resolv.conf
    log_info "DNS gesetzt: nameserver ${PI_GATEWAY}"

    # Warten bis IP-Adresse auf wlan0 sichtbar ist
    log_info "Warte auf IP-Adresse auf wlan0..."
    IP_ASSIGNED=false
    for i in $(seq 1 30); do
        if ip -4 addr show wlan0 2>/dev/null | grep -q "inet "; then
            ASSIGNED_IP=$(ip -4 addr show wlan0 | grep "inet " | awk '{print $2}')
            log_info "IP-Adresse nach ${i}s zugewiesen: ${ASSIGNED_IP}"
            IP_ASSIGNED=true
            break
        fi
        sleep 1
    done
    if [ "${IP_ASSIGNED}" = false ]; then
        log_warn "Keine IP-Adresse auf wlan0 nach 30s sichtbar."
    fi
    phase_end 3
else
    log_err "WiFi-Konfiguration fehlgeschlagen. SSID: ${WIFI_SSID}"
    log_err "Bitte manuell konfigurieren."
    phase_fail 3
fi

# ============================================================
# Netzwerk-Konnektivität prüfen (vor Downloads)
# ============================================================
log_info "----------------------------------------------------------------"
log_info "Prüfe Internet-Konnektivität..."
NET_OK=false
if [ "${WIFI_CONNECTED}" = false ]; then
    log_err "Kein Internet erreichbar (WiFi nicht verbunden) – Downloads werden fehlschlagen."
else
    for i in $(seq 1 5); do
        if curl -sSf --max-time 10 https://install.pi-hole.net > /dev/null 2>&1; then
            log_info "Internet erreichbar (Versuch ${i})."
            NET_OK=true
            break
        fi
        log_warn "Kein Internet (Versuch ${i}/5) – warte 15s..."
        sleep 15
    done
    if [ "${NET_OK}" = false ]; then
        log_err "Kein Internet erreichbar! Download-basierte Installationen werden fehlschlagen."
    fi
fi

# ============================================================
# 4. SSH-Key deployen
# ============================================================
phase_start 4 "SSH-Key deployen"
USER_HOME="/home/${PI_USER}"
SSH_DIR="${USER_HOME}/.ssh"

if [ ! -d "${USER_HOME}" ]; then
    log_warn "Home-Verzeichnis ${USER_HOME} existiert nicht – erstelle es."
    mkdir -p "${USER_HOME}"
    chown "${PI_USER}:${PI_USER}" "${USER_HOME}"
    chmod 750 "${USER_HOME}"
fi

SSH_OK=true
mkdir -p "${SSH_DIR}"                                       || SSH_OK=false
echo "${SSH_PUBLIC_KEY}" > "${SSH_DIR}/authorized_keys"    || SSH_OK=false
chmod 700 "${SSH_DIR}"                                      || SSH_OK=false
chmod 600 "${SSH_DIR}/authorized_keys"                     || SSH_OK=false
chown -R "${PI_USER}:${PI_USER}" "${SSH_DIR}"              || SSH_OK=false

if [ "${SSH_OK}" = true ]; then
    KEY_COMMENT=$(echo "${SSH_PUBLIC_KEY}" | awk '{print $NF}' 2>/dev/null || echo "unbekannt")
    log_info "SSH-Key deployt: ${SSH_DIR}/authorized_keys (${KEY_COMMENT})"
else
    log_err "SSH-Key konnte nicht deployt werden!"
    phase_fail 4
fi

phase_end_or_skip 4

# ============================================================
# 5. Pi-hole v6 installieren
# ============================================================
phase_start 5 "Pi-hole v6 installieren"

if command -v pihole &>/dev/null; then
    PIHOLE_VERSION=$(pihole version --pihole 2>/dev/null || echo "unbekannt")
    log_info "Pi-hole bereits installiert (${PIHOLE_VERSION}) – überspringe Installation."
else
    PIHOLE_INSTALLER="/tmp/pihole-install.sh"
    DOWNLOAD_OK=false
    log_info "Lade Pi-hole Installer herunter..."
    for attempt in $(seq 1 3); do
        if curl -sSL --max-time 120 https://install.pi-hole.net -o "${PIHOLE_INSTALLER}"; then
            DOWNLOAD_OK=true
            log_info "Pi-hole Installer heruntergeladen (Versuch ${attempt})."
            break
        fi
        log_warn "Download fehlgeschlagen (Versuch ${attempt}/3) – warte 15s..."
        sleep 15
    done

    if [ "${DOWNLOAD_OK}" = false ]; then
        log_err "Pi-hole Installer konnte nicht heruntergeladen werden!"
        phase_fail 5
    else
        # IPv4 erzwingen und Timeouts setzen damit apt update nicht auf IPv6-Timeouts hängt
        cat > /etc/apt/apt.conf.d/99force-ipv4 << 'APTCONF'
Acquire::ForceIPv4 "true";
Acquire::http::Timeout "60";
Acquire::https::Timeout "60";
Acquire::Retries "3";
APTCONF
        log_info "apt-get update (IPv4 erzwungen, Timeout 60s)..."
        if ! apt-get update -qq 2>&1; then
            log_warn "apt-get update fehlgeschlagen – Pi-hole-Installer versucht es erneut."
        fi

        log_info "Starte Pi-hole Installation (unattended)..."
        if bash "${PIHOLE_INSTALLER}" --unattended; then
            log_info "Pi-hole Installation erfolgreich."
        else
            log_err "Pi-hole Installation fehlgeschlagen (Exit-Code: $?)!"
            phase_fail 5
        fi
        rm -f "${PIHOLE_INSTALLER}"

        # Pi-hole überschreibt /etc/resolv.conf auf 127.0.0.1 (eigener DNS).
        # Für die restlichen Phasen (Log2RAM-Download etc.) Upstream-DNS wiederherstellen.
        echo "nameserver ${PI_GATEWAY}" > /etc/resolv.conf
        log_info "DNS nach Pi-hole-Installation wiederhergestellt: ${PI_GATEWAY}"
    fi
fi

if command -v pihole &>/dev/null; then
    log_info "Setze Pi-hole Admin-Passwort..."
    # pihole setpassword ist v6-Syntax; -a -p als Fallback für v5
    if pihole setpassword "${PIHOLE_PASSWORD}" 2>/dev/null || \
       pihole -a -p "${PIHOLE_PASSWORD}" 2>/dev/null; then
        log_info "Pi-hole Admin-Passwort gesetzt."
    else
        log_warn "Pi-hole Passwort konnte nicht gesetzt werden – bitte manuell setzen."
    fi

    log_info "Lade Pi-hole Gravity (Blocklisten)..."
    if pihole -g; then
        log_info "Gravity-Update erfolgreich."
    else
        log_warn "Gravity-Update fehlgeschlagen (nachholbar mit: pihole -g)."
    fi
else
    log_warn "pihole-Befehl nicht gefunden – Passwort und Gravity übersprungen."
fi

phase_end_or_skip 5

# ============================================================
# 6. Log2RAM installieren
# ============================================================
phase_start 6 "Log2RAM installieren"

# Sicherstellen dass DNS über Gateway erreichbar ist.
# Pi-hole FTL überschreibt resolv.conf auf 127.0.0.1 – stoppen für Downloads.
PIHOLE_FTL_WAS_RUNNING=false
if systemctl is-active pihole-FTL &>/dev/null; then
    log_info "Stoppe pihole-FTL für Log2RAM-Download (DNS-Override verhindern)..."
    systemctl stop pihole-FTL 2>/dev/null || true
    PIHOLE_FTL_WAS_RUNNING=true
fi
echo "nameserver ${PI_GATEWAY}" > /etc/resolv.conf
log_info "DNS für Downloads: ${PI_GATEWAY}"

if command -v log2ram &>/dev/null || [ -f /usr/local/sbin/log2ram ] || [ -f /usr/sbin/log2ram ]; then
    log_info "Log2RAM bereits installiert – überspringe."
else
    LOG2RAM_TARBALL="/tmp/log2ram.tar.gz"
    LOG2RAM_DIR="/tmp/log2ram-install"
    DOWNLOAD_OK=false

    log_info "Lade Log2RAM herunter..."
    for attempt in $(seq 1 3); do
        if curl -sSL --max-time 120 \
                https://github.com/azlux/log2ram/archive/refs/heads/master.tar.gz \
                -o "${LOG2RAM_TARBALL}"; then
            DOWNLOAD_OK=true
            log_info "Log2RAM heruntergeladen (Versuch ${attempt})."
            break
        fi
        log_warn "Download fehlgeschlagen (Versuch ${attempt}/3) – warte 15s..."
        sleep 15
    done

    if [ "${DOWNLOAD_OK}" = false ]; then
        log_err "Log2RAM konnte nicht heruntergeladen werden!"
        phase_fail 6
    else
        mkdir -p "${LOG2RAM_DIR}"
        if tar -xzf "${LOG2RAM_TARBALL}" -C "${LOG2RAM_DIR}" --strip-components=1; then
            log_info "Log2RAM entpackt."
            chmod +x "${LOG2RAM_DIR}/install.sh"
            if (cd "${LOG2RAM_DIR}" && bash install.sh); then
                log_info "Log2RAM Installation erfolgreich."
            else
                log_err "Log2RAM install.sh fehlgeschlagen (Exit-Code: $?)!"
                phase_fail 6
            fi
        else
            log_err "Log2RAM entpacken fehlgeschlagen!"
            phase_fail 6
        fi
        rm -rf "${LOG2RAM_TARBALL}" "${LOG2RAM_DIR}"
    fi
fi

# Log2RAM Konfiguration sichern
if [ -f /etc/log2ram.conf ]; then
    if [ ! -f /etc/log2ram.conf.default ]; then
        cp /etc/log2ram.conf /etc/log2ram.conf.default
        log_info "Log2RAM Default-Konfiguration gesichert nach /etc/log2ram.conf.default"
    else
        log_info "Log2RAM Default-Konfiguration bereits vorhanden."
    fi
fi

# Log2RAM Sync-Intervall auf stündlich setzen
log_info "Setze Log2RAM Sync-Intervall auf stündlich..."
mkdir -p /etc/systemd/system/log2ram-daily.timer.d
cat > /etc/systemd/system/log2ram-daily.timer.d/override.conf << 'EOF'
[Timer]
OnCalendar=
OnCalendar=*-*-* *:00:00
EOF
log_info "Log2RAM Timer-Override geschrieben."

if [ "${PIHOLE_FTL_WAS_RUNNING}" = true ]; then
    log_info "Starte pihole-FTL wieder..."
    systemctl start pihole-FTL 2>/dev/null || true
fi

phase_end_or_skip 6

# ============================================================
# 7. Services aktivieren
# ============================================================
phase_start 7 "Services aktivieren"

# daemon-reload zuerst: Pi-hole apt-Install hat neue Units hinzugefügt
systemctl daemon-reload && log_info "systemd Daemon neu geladen." || \
    log_warn "daemon-reload fehlgeschlagen."

for svc in wlan-monitor health-check.timer; do
    # Dateibasierte Prüfung statt systemctl list-unit-files (nach apt ggf. unvollständig)
    unit_found=false
    for dir in /lib/systemd/system /etc/systemd/system /usr/lib/systemd/system; do
        if [ -f "${dir}/${svc}" ] || [ -f "${dir}/${svc}.service" ]; then
            unit_found=true
            break
        fi
    done

    if [ "${unit_found}" = true ]; then
        if systemctl enable "${svc}" 2>&1; then
            log_info "Service aktiviert: ${svc}"
        else
            log_warn "Service konnte nicht aktiviert werden: ${svc}"
        fi
    else
        log_warn "Service-Datei nicht gefunden, übersprungen: ${svc}"
    fi
done

phase_end 7

# ============================================================
# 8. Aufräumen
# ============================================================
phase_start 8 "Aufräumen"

log_info "Lösche secrets.env sicher: ${SECRETS_FILE}"
if shred -u "${SECRETS_FILE}" 2>/dev/null; then
    log_info "secrets.env sicher gelöscht (shred)."
elif rm -f "${SECRETS_FILE}"; then
    log_warn "secrets.env gelöscht (rm, kein shred verfügbar)."
else
    log_warn "secrets.env konnte nicht gelöscht werden – bitte manuell entfernen!"
fi

phase_end 8

# ============================================================
# 9. First-Boot-Service deaktivieren
# ============================================================
log_info "Deaktiviere First-Boot-Service..."
if systemctl disable first-boot.service 2>&1; then
    log_info "first-boot.service deaktiviert."
else
    log_warn "first-boot.service konnte nicht deaktiviert werden."
fi

# ============================================================
# Zusammenfassung
# ============================================================
TOTAL_ELAPSED=$(( $(date +%s) - SCRIPT_START ))
log_info "================================================================"
log_info "=== First Boot Zusammenfassung ==="
log_info "Gesamtlaufzeit: ${TOTAL_ELAPSED}s"
if [ ${#FAILED_PHASES[@]} -eq 0 ]; then
    log_info "Status: Alle Phasen erfolgreich abgeschlossen."
else
    log_warn "Status: ${#FAILED_PHASES[@]} Phase(n) fehlgeschlagen: Phase ${FAILED_PHASES[*]}"
    log_warn "Bitte Logfile prüfen: ${LOGFILE}"
fi
log_info "================================================================"

# ============================================================
# 10. Neustart
# ============================================================
log_info "=== Ersteinrichtung abgeschlossen. Starte neu in 5 Sekunden... ==="
sleep 5
reboot

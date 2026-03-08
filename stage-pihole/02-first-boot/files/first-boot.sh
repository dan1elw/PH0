#!/bin/bash
# first-boot.sh – Ersteinrichtung beim ersten Boot
#
# Liest secrets.env von der Boot-Partition, konfiguriert:
# - WiFi (SSID + Passwort)
# - SSH Public Key
# - Pi-hole Admin-Passwort
# - Hostname
# Löscht danach secrets.env und deaktiviert sich selbst.

set -euo pipefail

LOG_TAG="first-boot"
BOOT_PARTITION="/boot/firmware"
SECRETS_FILE="${BOOT_PARTITION}/secrets.env"

log_info() {
    logger -t "${LOG_TAG}" -p daemon.info "$1"
    echo "[INFO] $1"
}

log_err() {
    logger -t "${LOG_TAG}" -p daemon.err "$1"
    echo "[ERROR] $1" >&2
}

# ============================================================
# Prüfe ob secrets.env vorhanden ist
# ============================================================
if [ ! -f "${SECRETS_FILE}" ]; then
    # Auch /boot prüfen (ältere Bookworm-Versionen)
    BOOT_PARTITION="/boot"
    SECRETS_FILE="${BOOT_PARTITION}/secrets.env"
    if [ ! -f "${SECRETS_FILE}" ]; then
        log_err "secrets.env nicht gefunden auf der Boot-Partition!"
        log_err "Erwartet unter /boot/firmware/secrets.env oder /boot/secrets.env"
        exit 1
    fi
fi

log_info "secrets.env gefunden: ${SECRETS_FILE}"

# ============================================================
# secrets.env einlesen
# ============================================================
# shellcheck source=/dev/null
source "${SECRETS_FILE}"

# Pflichtfelder prüfen
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

# ============================================================
# 1. Hostname setzen
# ============================================================
log_info "Setze Hostname: ${PI_HOSTNAME}"
hostnamectl set-hostname "${PI_HOSTNAME}"
sed -i "s/127.0.1.1.*/127.0.1.1\t${PI_HOSTNAME}/" /etc/hosts

# ============================================================
# 2. Benutzer-Passwort setzen
# ============================================================
log_info "Setze Passwort für Benutzer: ${PI_USER}"
echo "${PI_USER}:${PI_USER_PASSWORD}" | chpasswd

# ============================================================
# 3. WiFi konfigurieren
# ============================================================
log_info "Konfiguriere WiFi: ${WIFI_SSID}"

# Für Bookworm mit NetworkManager
nmcli device wifi connect "${WIFI_SSID}" \
    password "${WIFI_PASSWORD}" \
    ifname wlan0 \
    name "pihole-wifi" || true

# Statische IP setzen
nmcli connection modify "pihole-wifi" \
    ipv4.method manual \
    ipv4.addresses "${PI_IP}/${PI_PREFIX}" \
    ipv4.gateway "${PI_GATEWAY}" \
    ipv4.dns "127.0.0.1" \
    wifi.cloned-mac-address stable \
    connection.autoconnect yes

# WiFi-Ländercode setzen
iw reg set "${WIFI_COUNTRY}"
if [ -f /etc/default/crda ]; then
    sed -i "s/REGDOMAIN=.*/REGDOMAIN=${WIFI_COUNTRY}/" /etc/default/crda
fi

# ============================================================
# 4. SSH-Key deployen
# ============================================================
log_info "Deploye SSH Public Key für Benutzer: ${PI_USER}"
USER_HOME="/home/${PI_USER}"
SSH_DIR="${USER_HOME}/.ssh"

mkdir -p "${SSH_DIR}"
echo "${SSH_PUBLIC_KEY}" > "${SSH_DIR}/authorized_keys"
chmod 700 "${SSH_DIR}"
chmod 600 "${SSH_DIR}/authorized_keys"
chown -R "${PI_USER}:${PI_USER}" "${SSH_DIR}"

# ============================================================
# 5. Pi-hole Admin-Passwort setzen
# ============================================================
log_info "Setze Pi-hole Admin-Passwort"
pihole setpassword "${PIHOLE_PASSWORD}"

# ============================================================
# 6. Aufräumen
# ============================================================
log_info "Lösche secrets.env von der Boot-Partition"
shred -u "${SECRETS_FILE}" 2>/dev/null || rm -f "${SECRETS_FILE}"

# ============================================================
# 7. First-Boot-Service deaktivieren
# ============================================================
log_info "Deaktiviere First-Boot-Service"
systemctl disable first-boot.service

# ============================================================
# 8. Neustart
# ============================================================
log_info "Ersteinrichtung abgeschlossen. Starte neu..."
sleep 3
reboot

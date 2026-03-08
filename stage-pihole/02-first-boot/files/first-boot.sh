#!/bin/bash
# first-boot.sh – Ersteinrichtung beim ersten Boot
#
# Dieses Script läuft EINMALIG beim allerersten Start des Pi.
# Es installiert Pi-hole und Log2RAM (brauchen Netzwerk + systemd),
# konfiguriert WiFi, SSH, und aktiviert alle Services.
# Danach löscht es die secrets.env und deaktiviert sich selbst.

set -euo pipefail

LOG_TAG="first-boot"
BOOT_PARTITION="/boot/firmware"
SECRETS_FILE="${BOOT_PARTITION}/secrets.env"
LOGFILE="/var/log/first-boot.log"

# Alles loggen
exec > >(tee -a "${LOGFILE}") 2>&1

log_info() {
    logger -t "${LOG_TAG}" -p daemon.info "$1"
    echo "[INFO] $(date '+%H:%M:%S') $1"
}

log_err() {
    logger -t "${LOG_TAG}" -p daemon.err "$1"
    echo "[ERROR] $(date '+%H:%M:%S') $1" >&2
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

log_info "=== Pi-hole First Boot gestartet ==="
log_info "secrets.env gefunden: ${SECRETS_FILE}"

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

iw reg set "${WIFI_COUNTRY}"

nmcli device wifi connect "${WIFI_SSID}" \
    password "${WIFI_PASSWORD}" \
    ifname wlan0 \
    name "pihole-wifi" || true

# Warten bis Verbindung steht
log_info "Warte auf Netzwerkverbindung..."
for i in $(seq 1 30); do
    if nmcli -t -f STATE general status | grep -q "connected"; then
        log_info "Netzwerk verbunden nach ${i} Sekunden."
        break
    fi
    sleep 1
done

# Statische IP setzen
nmcli connection modify "pihole-wifi" \
    ipv4.method manual \
    ipv4.addresses "${PI_IP}/${PI_PREFIX}" \
    ipv4.gateway "${PI_GATEWAY}" \
    ipv4.dns "127.0.0.1 ${PI_GATEWAY}" \
    wifi.cloned-mac-address stable \
    connection.autoconnect yes

# Verbindung mit neuer IP neu starten
nmcli connection up "pihole-wifi"

# Warten bis Netzwerk mit neuer IP steht
sleep 5

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
# 5. Pi-hole v6 installieren
# ============================================================
log_info "Installiere Pi-hole v6 (unattended)..."

# pihole.toml ist bereits vorhanden (aus dem Image-Build)
curl -sSL https://install.pi-hole.net | bash /dev/stdin --unattended

log_info "Pi-hole Installation abgeschlossen."

# Admin-Passwort setzen (v6 Syntax)
pihole -a -p "${PIHOLE_PASSWORD}"

# Gravity laden (Blocklisten)
log_info "Lade Pi-hole Gravity (Blocklisten)..."
pihole -g || log_err "Gravity-Update fehlgeschlagen (kann später nachgeholt werden)"

# ============================================================
# 6. Log2RAM installieren
# ============================================================
log_info "Installiere Log2RAM..."

cd /tmp
curl -sSL https://github.com/azlux/log2ram/archive/refs/heads/master.tar.gz | tar -xz
cd log2ram-master
chmod +x install.sh
./install.sh
cd /tmp
rm -rf log2ram-master

# Log2RAM Konfiguration überschreiben (unsere Version aus dem Image)
if [ -f /etc/log2ram.conf.bak ]; then
    cp /etc/log2ram.conf /etc/log2ram.conf.default
fi
# Unsere Konfiguration wurde bereits im Image nach /etc/log2ram.conf deployed

# Log2RAM Sync-Intervall auf stündlich setzen
mkdir -p /etc/systemd/system/log2ram-daily.timer.d
cat > /etc/systemd/system/log2ram-daily.timer.d/override.conf << 'EOF'
[Timer]
OnCalendar=
OnCalendar=*-*-* *:00:00
EOF

# ============================================================
# 7. Services aktivieren
# ============================================================
log_info "Aktiviere Services..."

systemctl enable watchdog
systemctl enable wlan-monitor
systemctl enable health-check.timer
systemctl daemon-reload

# ============================================================
# 8. Aufräumen
# ============================================================
log_info "Lösche secrets.env von der Boot-Partition"
shred -u "${SECRETS_FILE}" 2>/dev/null || rm -f "${SECRETS_FILE}"

# ============================================================
# 9. First-Boot-Service deaktivieren
# ============================================================
log_info "Deaktiviere First-Boot-Service"
systemctl disable first-boot.service

# ============================================================
# 10. Neustart
# ============================================================
log_info "=== Ersteinrichtung abgeschlossen. Starte neu... ==="
sleep 3
reboot

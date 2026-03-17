#!/bin/bash -e
# 01-run.sh – Konfigurationsdateien deployen
# Wird innerhalb der pi-gen Build-Umgebung ausgeführt.
#
# WICHTIG: Hier werden NUR Dateien kopiert und Verzeichnisse erstellt.
# Keine systemctl-Befehle (funktionieren nicht im chroot).
# Keine Installer-Scripts (brauchen Netzwerk).
# Service-Aktivierung und Installationen erfolgen im First Boot.

# ============================================================
# Pi-hole Konfiguration (wird beim First Boot vom Installer genutzt)
# ============================================================
install -v -m 644 \
    "${STAGE_DIR}/01-configure/files/pihole.toml" \
    "${ROOTFS_DIR}/etc/pihole/pihole.toml"

# Adlists: werden beim First Boot vom Pi-hole Installer in gravity.db migriert
install -v -m 644 \
    "${STAGE_DIR}/01-configure/files/adlists.list" \
    "${ROOTFS_DIR}/etc/pihole/adlists.list"

# Ownership setzen (pihole User wurde in 00-install-packages erstellt)
on_chroot <<'CHEOF'
chown pihole:pihole /etc/pihole/pihole.toml
chown pihole:pihole /etc/pihole/adlists.list
CHEOF

# ============================================================
# Log2RAM Konfiguration (wird beim First Boot installiert)
# ============================================================
install -v -m 644 \
    "${STAGE_DIR}/01-configure/files/log2ram.conf" \
    "${ROOTFS_DIR}/etc/log2ram.conf"

# journald: persistente Logs aktivieren + Größe begrenzen (passend zu Log2RAM 50MB)
# Storage=persistent: Logs in /var/log/journal (via Log2RAM im RAM, stündlich auf SD)
# Ohne Storage=persistent bleibt journald volatile und Logs gehen beim Reboot verloren.
mkdir -p "${ROOTFS_DIR}/etc/systemd/journald.conf.d"
cat >"${ROOTFS_DIR}/etc/systemd/journald.conf.d/log2ram.conf" <<'EOF'
[Journal]
Storage=persistent
SystemMaxUse=20M
RuntimeMaxUse=20M
EOF

# /var/log/journal muss existieren damit journald persistent schreibt
mkdir -p "${ROOTFS_DIR}/var/log/journal"

# ============================================================
# Hardware-Watchdog Konfiguration
# ============================================================
install -v -m 644 \
    "${STAGE_DIR}/01-configure/files/watchdog.conf" \
    "${ROOTFS_DIR}/etc/watchdog.conf"

# Watchdog Kernel-Modul beim Boot laden
if ! grep -q "bcm2835_wdt" "${ROOTFS_DIR}/etc/modules" 2>/dev/null; then
    echo "bcm2835_wdt" >>"${ROOTFS_DIR}/etc/modules"
fi

# Hardware-Watchdog über systemd RuntimeWatchdogSec statt userspace watchdog-Daemon.
# systemd füttert /dev/watchdog direkt – zuverlässiger und ohne Service-Abhängigkeiten.
# RuntimeWatchdogSec=10: systemd muss /dev/watchdog alle 10s beschreiben,
# sonst löst der Hardware-Watchdog nach dem Timeout einen Reboot aus.
mkdir -p "${ROOTFS_DIR}/etc/systemd/system.conf.d"
cat >"${ROOTFS_DIR}/etc/systemd/system.conf.d/watchdog.conf" <<'EOF'
[Manager]
RuntimeWatchdogSec=10
EOF

# ============================================================
# WLAN-Monitor Script + Service Unit
# ============================================================
install -v -m 755 \
    "${STAGE_DIR}/01-configure/files/wlan-monitor.sh" \
    "${ROOTFS_DIR}/usr/local/bin/wlan-monitor.sh"

install -v -m 644 \
    "${STAGE_DIR}/01-configure/files/wlan-monitor.service" \
    "${ROOTFS_DIR}/etc/systemd/system/wlan-monitor.service"

# ============================================================
# Health-Check Script + Service + Timer + Logrotate
# ============================================================
install -v -m 755 \
    "${STAGE_DIR}/01-configure/files/health-check.sh" \
    "${ROOTFS_DIR}/usr/local/bin/health-check.sh"

install -v -m 644 \
    "${STAGE_DIR}/01-configure/files/health-check.service" \
    "${ROOTFS_DIR}/etc/systemd/system/health-check.service"

install -v -m 644 \
    "${STAGE_DIR}/01-configure/files/health-check.timer" \
    "${ROOTFS_DIR}/etc/systemd/system/health-check.timer"

install -v -m 644 \
    "${STAGE_DIR}/01-configure/files/pihole-health" \
    "${ROOTFS_DIR}/etc/logrotate.d/pihole-health"

# ============================================================
# WiFi Country Code in config.txt (KRITISCH: ohne country= bleibt
# brcmfmac beim ersten Boot in NM als "unavailable" hängen)
# ============================================================
CONFIGTXT="${ROOTFS_DIR}/boot/firmware/config.txt"
if [ -f "${CONFIGTXT}" ]; then
    # Entweder vorhandenes country= ersetzen oder am Ende anhängen.
    # Default DE – wird beim First Boot via secrets.env nicht überschrieben
    # (config.txt ist vor secrets.env-Auswertung bereits aktiv).
    if grep -q "^country=" "${CONFIGTXT}"; then
        sed -i "s/^country=.*/country=DE/" "${CONFIGTXT}"
    else
        printf "\n# WiFi Country Code\ncountry=DE\n" >>"${CONFIGTXT}"
    fi
    echo "country=DE in config.txt gesetzt."
else
    echo "[WARN] config.txt nicht gefunden: ${CONFIGTXT}"
fi

# ============================================================
# NetworkManager: DNS-Management deaktivieren (Pi-hole übernimmt)
# ============================================================
mkdir -p "${ROOTFS_DIR}/etc/NetworkManager/conf.d"
cat >"${ROOTFS_DIR}/etc/NetworkManager/conf.d/99-pihole.conf" <<'EOF'
[main]
dns=none
EOF

# ============================================================
# WiFi Power Management deaktivieren
# Pi Zero W geht sonst in Schlafmodus → verpasst Beacons → Verbindungsabbruch.
# wifi.powersave = 2: disable (0=default, 2=disable, 3=enable)
# ============================================================
cat >"${ROOTFS_DIR}/etc/NetworkManager/conf.d/99-wifi-powersave.conf" <<'EOF'
[connection]
wifi.powersave = 2
EOF

# ============================================================
# Pi-hole FTL systemd Hardening (Drop-in Override)
# Wird aktiv sobald pihole-FTL.service beim First Boot installiert wird.
# ============================================================
mkdir -p "${ROOTFS_DIR}/etc/systemd/system/pihole-FTL.service.d"
cat >"${ROOTFS_DIR}/etc/systemd/system/pihole-FTL.service.d/override.conf" <<'EOF'
[Service]
Restart=on-failure         # Bei Absturz automatisch neustarten
RestartSec=5               # 5s warten vor Neustart
WatchdogSec=60             # FTL muss sich alle 60s via sd_notify melden
StartLimitIntervalSec=300  # Innerhalb von 5 Minuten...
StartLimitBurst=5          # ...maximal 5 Neustarts erlaubt
EOF

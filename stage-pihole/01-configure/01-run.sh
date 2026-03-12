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

# Ownership setzen (pihole User wurde in 00-install-packages erstellt)
on_chroot << 'CHEOF'
chown pihole:pihole /etc/pihole/pihole.toml
CHEOF

# ============================================================
# Log2RAM Konfiguration (wird beim First Boot installiert)
# ============================================================
install -v -m 644 \
    "${STAGE_DIR}/01-configure/files/log2ram.conf" \
    "${ROOTFS_DIR}/etc/log2ram.conf"

# journald: SystemMaxUse begrenzen (passend zu Log2RAM 50MB)
mkdir -p "${ROOTFS_DIR}/etc/systemd/journald.conf.d"
cat > "${ROOTFS_DIR}/etc/systemd/journald.conf.d/log2ram.conf" << 'EOF'
[Journal]
SystemMaxUse=20M
RuntimeMaxUse=20M
EOF

# ============================================================
# Hardware-Watchdog Konfiguration
# ============================================================
install -v -m 644 \
    "${STAGE_DIR}/01-configure/files/watchdog.conf" \
    "${ROOTFS_DIR}/etc/watchdog.conf"

# Watchdog Kernel-Modul beim Boot laden
if ! grep -q "bcm2835_wdt" "${ROOTFS_DIR}/etc/modules" 2>/dev/null; then
    echo "bcm2835_wdt" >> "${ROOTFS_DIR}/etc/modules"
fi

# Hardware-Watchdog über systemd RuntimeWatchdogSec statt userspace watchdog-Daemon.
# systemd füttert /dev/watchdog direkt – zuverlässiger und ohne Service-Abhängigkeiten.
mkdir -p "${ROOTFS_DIR}/etc/systemd/system.conf.d"
cat > "${ROOTFS_DIR}/etc/systemd/system.conf.d/watchdog.conf" << 'EOF'
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
# Health-Check Script + Service + Timer
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

# ============================================================
# WiFi Country Code in config.txt (KRITISCH: ohne country= bleibt
# brcmfmac beim ersten Boot in NM als "unavailable" hängen)
# ============================================================
CONFIGTXT="${ROOTFS_DIR}/boot/firmware/config.txt"
if [ -f "${CONFIGTXT}" ]; then
    if grep -q "^country=" "${CONFIGTXT}"; then
        sed -i "s/^country=.*/country=DE/" "${CONFIGTXT}"
    else
        printf "\n# WiFi Country Code\ncountry=DE\n" >> "${CONFIGTXT}"
    fi
    echo "country=DE in config.txt gesetzt."
else
    echo "[WARN] config.txt nicht gefunden: ${CONFIGTXT}"
fi

# ============================================================
# NetworkManager: DNS-Management deaktivieren (Pi-hole übernimmt)
# ============================================================
mkdir -p "${ROOTFS_DIR}/etc/NetworkManager/conf.d"
cat > "${ROOTFS_DIR}/etc/NetworkManager/conf.d/99-pihole.conf" << 'EOF'
[main]
dns=none
EOF

# ============================================================
# Pi-hole FTL systemd Hardening (Override-Datei, wird aktiv sobald
# pihole-FTL.service beim First Boot installiert wird)
# ============================================================
mkdir -p "${ROOTFS_DIR}/etc/systemd/system/pihole-FTL.service.d"
cat > "${ROOTFS_DIR}/etc/systemd/system/pihole-FTL.service.d/override.conf" << 'EOF'
[Service]
Restart=on-failure
RestartSec=5
WatchdogSec=60
StartLimitIntervalSec=300
StartLimitBurst=5
EOF

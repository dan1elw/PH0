#!/bin/bash -e
# 01-run.sh – Konfigurationsdateien deployen und Pi-hole installieren
# Wird innerhalb der pi-gen chroot-Umgebung ausgeführt.

# ============================================================
# Pi-hole Konfiguration (VOR dem Installer!)
# ============================================================
install -v -m 644 -o pihole -g pihole \
    "${STAGE_DIR}/01-configure/files/pihole.toml" \
    "${ROOTFS_DIR}/etc/pihole/pihole.toml"

# ============================================================
# Pi-hole v6 installieren (unattended)
# ============================================================
on_chroot << 'CHEOF'
# pihole.toml ist jetzt vorhanden → unattended Install funktioniert
curl -sSL https://install.pi-hole.net | bash /dev/stdin --unattended

# Gravity initialisieren (Standard-Blocklisten laden)
pihole -g
CHEOF

# ============================================================
# Log2RAM Konfiguration
# ============================================================
install -v -m 644 \
    "${STAGE_DIR}/01-configure/files/log2ram.conf" \
    "${ROOTFS_DIR}/etc/log2ram.conf"

# Log2RAM: Sync-Intervall auf stündlich setzen
mkdir -p "${ROOTFS_DIR}/etc/systemd/system/log2ram-daily.timer.d"
cat > "${ROOTFS_DIR}/etc/systemd/system/log2ram-daily.timer.d/override.conf" << 'EOF'
[Timer]
OnCalendar=
OnCalendar=*-*-* *:00:00
EOF

# journald: SystemMaxUse begrenzen (passend zu Log2RAM 50MB)
mkdir -p "${ROOTFS_DIR}/etc/systemd/journald.conf.d"
cat > "${ROOTFS_DIR}/etc/systemd/journald.conf.d/log2ram.conf" << 'EOF'
[Journal]
SystemMaxUse=20M
RuntimeMaxUse=20M
EOF

# ============================================================
# Hardware-Watchdog
# ============================================================
install -v -m 644 \
    "${STAGE_DIR}/01-configure/files/watchdog.conf" \
    "${ROOTFS_DIR}/etc/watchdog.conf"

# Watchdog Kernel-Modul beim Boot laden
echo "bcm2835_wdt" >> "${ROOTFS_DIR}/etc/modules"

# Watchdog-Verzeichnis erstellen
mkdir -p "${ROOTFS_DIR}/var/log/watchdog"

on_chroot << 'CHEOF'
# Watchdog-Service aktivieren
systemctl enable watchdog
CHEOF

# ============================================================
# WLAN-Monitor
# ============================================================
install -v -m 755 \
    "${STAGE_DIR}/01-configure/files/wlan-monitor.sh" \
    "${ROOTFS_DIR}/usr/local/bin/wlan-monitor.sh"

install -v -m 644 \
    "${STAGE_DIR}/01-configure/files/wlan-monitor.service" \
    "${ROOTFS_DIR}/etc/systemd/system/wlan-monitor.service"

on_chroot << 'CHEOF'
systemctl enable wlan-monitor
CHEOF

# ============================================================
# Health-Check
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

on_chroot << 'CHEOF'
systemctl enable health-check.timer
CHEOF

# ============================================================
# Statische IP Konfiguration
# ============================================================
# Für Bookworm mit NetworkManager (Standard seit Bookworm):
mkdir -p "${ROOTFS_DIR}/etc/NetworkManager/system-connections"
cat > "${ROOTFS_DIR}/etc/NetworkManager/conf.d/99-pihole.conf" << 'EOF'
[main]
dns=none
EOF

# Statische IP via nmcli wird beim First Boot konfiguriert,
# da WiFi-Credentials erst dann verfügbar sind.

# ============================================================
# Pi-hole FTL systemd Hardening
# ============================================================
mkdir -p "${ROOTFS_DIR}/etc/systemd/system/pihole-FTL.service.d"
cat > "${ROOTFS_DIR}/etc/systemd/system/pihole-FTL.service.d/override.conf" << 'EOF'
[Service]
Restart=on-failure
RestartSec=5
WatchdogSec=60

# Neustart-Limit: max 5 Neustarts in 5 Minuten
StartLimitIntervalSec=300
StartLimitBurst=5
EOF

# ============================================================
# Crash-Log Datei vorbereiten
# ============================================================
touch "${ROOTFS_DIR}/var/log/pihole-crashes.log"
touch "${ROOTFS_DIR}/var/log/pihole-health.log"

#!/bin/bash -e
# 01-run.sh – Vorbereitungen für Pi-hole und Log2RAM
# Wird innerhalb der pi-gen chroot-Umgebung ausgeführt.
#
# WICHTIG: Im chroot funktionieren KEINE systemd-Befehle und
# kein Netzwerkzugriff für Installer-Scripts. Daher werden hier
# nur Verzeichnisse, User und Dateien vorbereitet.
# Die eigentliche Installation von Pi-hole und Log2RAM erfolgt
# beim First Boot auf dem realen System.

# ============================================================
# pihole User und Verzeichnis vorbereiten
# ============================================================
on_chroot <<'CHEOF'
# pihole Gruppe und User erstellen
if ! getent group pihole > /dev/null 2>&1; then
    groupadd pihole
fi
if ! id -u pihole > /dev/null 2>&1; then
    # -r: System-Account (keine Login-Shell, kein Home)
    # --no-user-group: keine eigene Gruppe anlegen (Gruppe wird explizit über -g gesetzt)
    # -s /usr/sbin/nologin: kein interaktiver Login möglich
    useradd -r --no-user-group -g pihole -s /usr/sbin/nologin pihole
fi

# Konfigurationsverzeichnis erstellen
mkdir -p /etc/pihole
chown pihole:pihole /etc/pihole
chmod 775 /etc/pihole
CHEOF

# ============================================================
# Log-Verzeichnisse vorbereiten
# ============================================================
# Diese Verzeichnisse werden im Chroot erstellt, damit sie beim First Boot
# sofort verfügbar sind – auch nachdem Log2RAM /var/log als tmpfs mountet.
# Log2RAM kopiert die Verzeichnisstruktur aus dem originalen /var/log ins RAM.
mkdir -p "${ROOTFS_DIR}/var/log/pihole"
mkdir -p "${ROOTFS_DIR}/var/log/watchdog"
touch "${ROOTFS_DIR}/var/log/pihole-crashes.log"
touch "${ROOTFS_DIR}/var/log/pihole-health.log"

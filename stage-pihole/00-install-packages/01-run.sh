#!/bin/bash -e
# 01-run.sh – Pi-hole und Log2RAM Installation
# Wird innerhalb der pi-gen chroot-Umgebung ausgeführt.

# ============================================================
# Pi-hole v6 – Unattended Installation
# ============================================================
# Pi-hole v6 benötigt eine vorhandene pihole.toml für unattended Install.
# Die Datei wird in Stage 01-configure deployed. Hier erstellen wir
# vorab den pihole-User und das Konfigurationsverzeichnis.

on_chroot << 'CHEOF'
# pihole Gruppe und User erstellen
if ! getent group pihole > /dev/null 2>&1; then
    groupadd pihole
fi
if ! id -u pihole > /dev/null 2>&1; then
    useradd -r --no-user-group -g pihole -s /usr/sbin/nologin pihole
fi

# Konfigurationsverzeichnis erstellen
mkdir -p /etc/pihole
chown pihole:pihole /etc/pihole
chmod 775 /etc/pihole
CHEOF

# pihole.toml wird in 01-configure/01-run.sh kopiert, damit sie
# vor dem Installer vorhanden ist.

# Pi-hole installieren (unattended)
# HINWEIS: pihole.toml muss bereits in /etc/pihole liegen.
# Da pi-gen Stages sequentiell abgearbeitet werden und 01-configure
# nach 00-install-packages kommt, installieren wir Pi-hole in
# 01-configure/01-run.sh NACH dem Kopieren der pihole.toml.

# ============================================================
# Log2RAM Installation
# ============================================================
on_chroot << 'CHEOF'
# Log2RAM via GitHub Release installieren (unabhängig vom APT-Repo)
cd /tmp
curl -sSL https://github.com/azlux/log2ram/archive/refs/heads/master.tar.gz | tar -xz
cd log2ram-master
chmod +x install.sh

# Install-Script ausführen (installiert Service + Config)
./install.sh

# Aufräumen
cd /tmp
rm -rf log2ram-master
CHEOF

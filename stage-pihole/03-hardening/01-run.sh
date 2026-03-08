#!/bin/bash -e
# 01-run.sh – System-Härtung: SSH, Firewall, tmpfs

# ============================================================
# SSH Härtung
# ============================================================
# Passwort-Authentifizierung deaktivieren
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' \
    "${ROOTFS_DIR}/etc/ssh/sshd_config"
sed -i 's/^#\?ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' \
    "${ROOTFS_DIR}/etc/ssh/sshd_config"
sed -i 's/^#\?UsePAM.*/UsePAM no/' \
    "${ROOTFS_DIR}/etc/ssh/sshd_config"

# Root-Login via SSH deaktivieren
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' \
    "${ROOTFS_DIR}/etc/ssh/sshd_config"

# Nur Key-basierte Authentifizierung
sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' \
    "${ROOTFS_DIR}/etc/ssh/sshd_config"

# Max Auth Tries begrenzen
sed -i 's/^#\?MaxAuthTries.*/MaxAuthTries 3/' \
    "${ROOTFS_DIR}/etc/ssh/sshd_config"

# ============================================================
# Firewall (nftables)
# ============================================================
cat > "${ROOTFS_DIR}/etc/nftables.conf" << 'EOF'
#!/usr/sbin/nft -f
# Pi-hole Firewall – nftables Konfiguration
#
# Erlaubte Dienste:
# - SSH (22/tcp)
# - DNS (53/tcp, 53/udp)
# - HTTP (80/tcp) – Pi-hole Web UI + API
# - ICMP (Ping)

flush ruleset

table inet filter {
    chain input {
        type filter hook input priority 0; policy drop;

        # Loopback erlauben
        iif "lo" accept

        # Bestehende Verbindungen erlauben
        ct state established,related accept

        # ICMP (Ping) erlauben
        ip protocol icmp accept
        ip6 nexthdr icmpv6 accept

        # SSH
        tcp dport 22 ct state new accept

        # DNS
        tcp dport 53 ct state new accept
        udp dport 53 accept

        # HTTP (Pi-hole Web UI)
        tcp dport 80 ct state new accept

        # Alles andere loggen und droppen
        log prefix "nftables-drop: " flags all counter drop
    }

    chain forward {
        type filter hook forward priority 0; policy drop;
    }

    chain output {
        type filter hook output priority 0; policy accept;
    }
}
EOF

on_chroot << 'CHEOF'
# nftables aktivieren
systemctl enable nftables
CHEOF

# ============================================================
# tmpfs für temporäre Verzeichnisse
# ============================================================
cat >> "${ROOTFS_DIR}/etc/fstab" << 'EOF'

# tmpfs – Temporäre Dateien ins RAM (SD-Karten-Schutz)
tmpfs    /tmp        tmpfs    defaults,noatime,nosuid,nodev,size=30M    0 0
tmpfs    /var/tmp    tmpfs    defaults,noatime,nosuid,nodev,size=10M    0 0
EOF

# ============================================================
# Swap deaktivieren (spart SD-Schreibzyklen)
# ============================================================
on_chroot << 'CHEOF'
systemctl disable dphys-swapfile 2>/dev/null || true
# Swap-Datei entfernen falls vorhanden
rm -f /var/swap
CHEOF

# ============================================================
# Kernel-Parameter für SD-Karten-Schutz
# ============================================================
cat > "${ROOTFS_DIR}/etc/sysctl.d/99-sdcard-protect.conf" << 'EOF'
# Dirty Writeback Intervall erhöhen (60 Sekunden statt 5)
vm.dirty_writeback_centisecs = 6000

# Dirty Ratio erhöhen (mehr Daten im RAM puffern)
vm.dirty_ratio = 60
vm.dirty_background_ratio = 40

# Swappiness minimieren
vm.swappiness = 1
EOF

# ============================================================
# Unnötige Services deaktivieren
# ============================================================
on_chroot << 'CHEOF'
# Bluetooth deaktivieren (nicht benötigt)
systemctl disable bluetooth 2>/dev/null || true
systemctl disable hciuart 2>/dev/null || true

# Avahi deaktivieren (nicht benötigt wenn statische IP)
systemctl disable avahi-daemon 2>/dev/null || true

# Triggerhappy deaktivieren (Hotkey-Daemon, nicht benötigt)
systemctl disable triggerhappy 2>/dev/null || true
CHEOF

# Bluetooth Kernel-Module blockieren
cat > "${ROOTFS_DIR}/etc/modprobe.d/disable-bluetooth.conf" << 'EOF'
blacklist btbcm
blacklist hci_uart
EOF

# config.txt: HDMI und Bluetooth deaktivieren (Strom sparen)
cat >> "${ROOTFS_DIR}/boot/firmware/config.txt" << 'EOF'

# Pi-hole Optimierungen
# HDMI deaktivieren (headless)
dtoverlay=disable-hdmi
# Bluetooth deaktivieren
dtoverlay=disable-bt
# Hardware-Watchdog aktivieren
dtparam=watchdog=on
EOF

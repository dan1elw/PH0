#!/bin/bash -e
# 01-run.sh – System-Härtung: SSH, Firewall, tmpfs
#
# WICHTIG: Keine systemctl-Befehle im chroot.
# Services werden via Symlinks in /etc/systemd/system aktiviert.

# ============================================================
# SSH Härtung
# ============================================================
# Jedes sed-Muster matched auch auskommentierte Direktiven (#Foo),
# sodass Bookworm-Defaults zuverlässig überschrieben werden.
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' \
    "${ROOTFS_DIR}/etc/ssh/sshd_config" # Passwort-Login komplett deaktivieren
sed -i 's/^#\?ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' \
    "${ROOTFS_DIR}/etc/ssh/sshd_config" # Keyboard-interactive Auth deaktivieren
sed -i 's/^#\?UsePAM.*/UsePAM no/' \
    "${ROOTFS_DIR}/etc/ssh/sshd_config" # PAM deaktivieren (nur Key-Auth)
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' \
    "${ROOTFS_DIR}/etc/ssh/sshd_config" # Root-Login über SSH verboten
sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' \
    "${ROOTFS_DIR}/etc/ssh/sshd_config" # Public-Key-Auth explizit aktivieren
sed -i 's/^#\?MaxAuthTries.*/MaxAuthTries 3/' \
    "${ROOTFS_DIR}/etc/ssh/sshd_config" # Brute-Force-Schutz: max. 3 Versuche

# ============================================================
# Firewall (nftables)
# ============================================================
cat >"${ROOTFS_DIR}/etc/nftables.conf" <<'EOF'
#!/usr/sbin/nft -f
# Pi-hole Firewall – nftables Konfiguration

flush ruleset

table inet filter {
    chain input {
        type filter hook input priority 0; policy drop;

        iif "lo" accept
        ct state established,related accept
        ip protocol icmp accept
        ip6 nexthdr icmpv6 accept

        tcp dport 22 ct state new accept
        tcp dport 53 ct state new accept
        udp dport 53 accept
        tcp dport 80 ct state new accept

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

# nftables aktivieren via Symlink (kein systemctl im chroot)
mkdir -p "${ROOTFS_DIR}/etc/systemd/system/multi-user.target.wants"
ln -sf /lib/systemd/system/nftables.service \
    "${ROOTFS_DIR}/etc/systemd/system/multi-user.target.wants/nftables.service"

# ============================================================
# tmpfs für temporäre Verzeichnisse
# ============================================================
# Prüfen ob Einträge nicht schon existieren
if ! grep -q "^tmpfs.*/tmp " "${ROOTFS_DIR}/etc/fstab" 2>/dev/null; then
    cat >>"${ROOTFS_DIR}/etc/fstab" <<'EOF'

# tmpfs – Temporäre Dateien ins RAM (SD-Karten-Schutz)
tmpfs    /tmp        tmpfs    defaults,noatime,nosuid,nodev,size=30M    0 0
tmpfs    /var/tmp    tmpfs    defaults,noatime,nosuid,nodev,size=10M    0 0
EOF
fi

# ============================================================
# Swap deaktivieren (spart SD-Schreibzyklen)
# ============================================================
# dphys-swapfile via Symlink-Entfernung deaktivieren
rm -f "${ROOTFS_DIR}/etc/systemd/system/multi-user.target.wants/dphys-swapfile.service" 2>/dev/null || true
rm -f "${ROOTFS_DIR}/var/swap" 2>/dev/null || true

# ============================================================
# Kernel-Parameter für SD-Karten-Schutz
# ============================================================
cat >"${ROOTFS_DIR}/etc/sysctl.d/99-sdcard-protect.conf" <<'EOF'
# Dirty Writeback alle 60s (statt 5s): reduziert SD-Schreibfrequenz drastisch
vm.dirty_writeback_centisecs = 6000
# Bis zu 60% RAM dirty halten bevor sync blockiert
vm.dirty_ratio = 60
# Hintergrund-Sync erst bei 40% – kein aggressives Flushen
vm.dirty_background_ratio = 40
# Swappiness=1: RAM fast nie in Swap auslagern (kein Swap auf SD)
vm.swappiness = 1
EOF

# ============================================================
# Unnötige Services deaktivieren (via Symlink-Entfernung)
# ============================================================
rm -f "${ROOTFS_DIR}/etc/systemd/system/multi-user.target.wants/bluetooth.service" 2>/dev/null || true
rm -f "${ROOTFS_DIR}/etc/systemd/system/multi-user.target.wants/hciuart.service" 2>/dev/null || true
rm -f "${ROOTFS_DIR}/etc/systemd/system/multi-user.target.wants/avahi-daemon.service" 2>/dev/null || true
rm -f "${ROOTFS_DIR}/etc/systemd/system/multi-user.target.wants/triggerhappy.service" 2>/dev/null || true

# Bluetooth Kernel-Module blockieren
cat >"${ROOTFS_DIR}/etc/modprobe.d/disable-bluetooth.conf" <<'EOF'
blacklist btbcm
blacklist hci_uart
EOF

# ============================================================
# config.txt: Optimierungen für Pi Zero W
# ============================================================
# Boot-Config Pfad: Bookworm nutzt /boot/firmware/, ältere Images /boot/
BOOT_CONFIG="${ROOTFS_DIR}/boot/firmware/config.txt"
if [ ! -f "${BOOT_CONFIG}" ]; then
    BOOT_CONFIG="${ROOTFS_DIR}/boot/config.txt"
fi

if [ -f "${BOOT_CONFIG}" ]; then
    if ! grep -q "disable-bt" "${BOOT_CONFIG}" 2>/dev/null; then
        cat >>"${BOOT_CONFIG}" <<'EOF'

# Pi-hole Optimierungen
dtoverlay=disable-bt
dtparam=watchdog=on
EOF
    fi
fi

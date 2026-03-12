#!/bin/bash -e
# 01-run.sh – System-Härtung: SSH, Firewall, tmpfs
#
# WICHTIG: Keine systemctl-Befehle im chroot.
# Services werden via Symlinks in /etc/systemd/system aktiviert.

# ============================================================
# SSH Härtung
# ============================================================
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' \
    "${ROOTFS_DIR}/etc/ssh/sshd_config"
sed -i 's/^#\?ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' \
    "${ROOTFS_DIR}/etc/ssh/sshd_config"
sed -i 's/^#\?UsePAM.*/UsePAM no/' \
    "${ROOTFS_DIR}/etc/ssh/sshd_config"
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' \
    "${ROOTFS_DIR}/etc/ssh/sshd_config"
sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' \
    "${ROOTFS_DIR}/etc/ssh/sshd_config"
sed -i 's/^#\?MaxAuthTries.*/MaxAuthTries 3/' \
    "${ROOTFS_DIR}/etc/ssh/sshd_config"

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
vm.dirty_writeback_centisecs = 6000
vm.dirty_ratio = 60
vm.dirty_background_ratio = 40
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
# Prüfe ob Pfad existiert (Bookworm: /boot/firmware, älter: /boot)
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

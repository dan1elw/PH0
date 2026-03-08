#!/bin/bash -e
# 01-run.sh – First-Boot-Service installieren
#
# Aktivierung via Symlink (kein systemctl im chroot).

install -v -m 755 \
    "${STAGE_DIR}/02-first-boot/files/first-boot.sh" \
    "${ROOTFS_DIR}/usr/local/bin/first-boot.sh"

install -v -m 644 \
    "${STAGE_DIR}/02-first-boot/files/first-boot.service" \
    "${ROOTFS_DIR}/etc/systemd/system/first-boot.service"

# Service aktivieren via Symlink
mkdir -p "${ROOTFS_DIR}/etc/systemd/system/multi-user.target.wants"
ln -sf /etc/systemd/system/first-boot.service \
    "${ROOTFS_DIR}/etc/systemd/system/multi-user.target.wants/first-boot.service"

#!/bin/bash -e
# 01-run.sh – First-Boot-Service installieren

install -v -m 755 \
    "${STAGE_DIR}/02-first-boot/files/first-boot.sh" \
    "${ROOTFS_DIR}/usr/local/bin/first-boot.sh"

install -v -m 644 \
    "${STAGE_DIR}/02-first-boot/files/first-boot.service" \
    "${ROOTFS_DIR}/etc/systemd/system/first-boot.service"

on_chroot << 'CHEOF'
systemctl enable first-boot.service
CHEOF

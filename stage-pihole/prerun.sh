#!/bin/bash -e
# prerun.sh – Standard pi-gen Stage-Setup
# Kopiert das Build-Verzeichnis der vorherigen Stage
if [ ! -d "${ROOTFS_DIR}" ]; then
    copy_previous
fi

#!/bin/bash
# flash.sh – Image auf SD-Karte schreiben und secrets.env deployen
#
# Verwendung:
#   ./scripts/flash.sh /dev/sdX
#   ./scripts/flash.sh /dev/mmcblk0

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"
DEPLOY_DIR="${PROJECT_DIR}/deploy"

# ============================================================
# Argumente prüfen
# ============================================================
if [ $# -lt 1 ]; then
    echo "Verwendung: $0 <device>"
    echo "  Beispiel: $0 /dev/sdX"
    echo "  Beispiel: $0 /dev/mmcblk0"
    echo ""
    echo "Verfügbare Geräte:"
    lsblk -d -o NAME,SIZE,TYPE,MODEL | grep disk
    exit 1
fi

DEVICE="$1"

# ============================================================
# Sicherheitsprüfungen
# ============================================================
if [ ! -b "${DEVICE}" ]; then
    echo "[FEHLER] ${DEVICE} ist kein Block-Device!"
    exit 1
fi

# Prüfe ob es eine System-Disk ist
ROOT_DISK=$(lsblk -no PKNAME "$(findmnt -n -o SOURCE /)" 2>/dev/null || echo "")
if [ "/dev/${ROOT_DISK}" = "${DEVICE}" ]; then
    echo "[FEHLER] ${DEVICE} ist die System-Disk! Abgebrochen."
    exit 1
fi

# Image finden
IMAGE_FILE=$(ls -t "${DEPLOY_DIR}"/*.img 2>/dev/null | head -1)
if [ -z "${IMAGE_FILE}" ]; then
    # Versuche komprimierte Images zu finden
    COMPRESSED=$(ls -t "${DEPLOY_DIR}"/*.img.xz 2>/dev/null | head -1)
    if [ -n "${COMPRESSED}" ]; then
        echo "[INFO] Entpacke ${COMPRESSED}..."
        xz -dk "${COMPRESSED}"
        IMAGE_FILE="${COMPRESSED%.xz}"
    else
        echo "[FEHLER] Kein Image gefunden in ${DEPLOY_DIR}/"
        echo "         Zuerst './scripts/build.sh' ausführen."
        exit 1
    fi
fi

# Secrets prüfen
SECRETS_FILE="${PROJECT_DIR}/secrets.env"
if [ ! -f "${SECRETS_FILE}" ]; then
    echo "[FEHLER] secrets.env nicht gefunden!"
    exit 1
fi

# ============================================================
# Bestätigung
# ============================================================
echo ""
echo "=========================================="
echo " ACHTUNG: SD-Karte wird überschrieben!"
echo "=========================================="
echo ""
echo " Image:   $(basename "${IMAGE_FILE}")"
echo " Größe:   $(du -h "${IMAGE_FILE}" | awk '{print $1}')"
echo " Ziel:    ${DEVICE}"
echo " Device:  $(lsblk -d -o NAME,SIZE,MODEL "${DEVICE}" | tail -1)"
echo ""
read -rp " Fortfahren? (ja/NEIN): " confirm

if [ "${confirm}" != "ja" ]; then
    echo "Abgebrochen."
    exit 0
fi

# ============================================================
# Image schreiben
# ============================================================
echo ""
echo "[INFO] Unmounte Partitionen auf ${DEVICE}..."
umount "${DEVICE}"* 2>/dev/null || true

echo "[INFO] Schreibe Image auf ${DEVICE}..."
echo "       Das kann einige Minuten dauern..."
sudo dd if="${IMAGE_FILE}" of="${DEVICE}" bs=4M status=progress conv=fsync

echo "[INFO] Synchronisiere..."
sync

# ============================================================
# secrets.env auf Boot-Partition kopieren
# ============================================================
echo "[INFO] Mounte Boot-Partition..."

# Partition-Name bestimmen (sdX1 vs mmcblk0p1)
if [[ "${DEVICE}" == *"mmcblk"* ]]; then
    BOOT_PARTITION="${DEVICE}p1"
else
    BOOT_PARTITION="${DEVICE}1"
fi

MOUNT_POINT=$(mktemp -d)
sudo mount "${BOOT_PARTITION}" "${MOUNT_POINT}"

echo "[INFO] Kopiere secrets.env auf Boot-Partition..."
sudo cp "${SECRETS_FILE}" "${MOUNT_POINT}/secrets.env"
sudo chmod 600 "${MOUNT_POINT}/secrets.env"

echo "[INFO] Unmounte Boot-Partition..."
sudo umount "${MOUNT_POINT}"
rmdir "${MOUNT_POINT}"

# ============================================================
# Fertig
# ============================================================
echo ""
echo "=========================================="
echo " Flash erfolgreich!"
echo "=========================================="
echo ""
echo " Nächste Schritte:"
echo " 1. SD-Karte in den Pi Zero W einlegen"
echo " 2. Netzteil anschließen"
echo " 3. Ca. 2-3 Minuten warten (First Boot)"
echo " 4. Pi-hole erreichbar unter: http://192.168.178.49/admin"
echo " 5. Validierung: ./scripts/validate.sh"
echo ""

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
    lsblk -d -o NAME,SIZE,TYPE,MODEL | grep disk || true
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
if [ -n "${ROOT_DISK}" ] && [ "/dev/${ROOT_DISK}" = "${DEVICE}" ]; then
    echo "[FEHLER] ${DEVICE} ist die System-Disk! Abgebrochen."
    exit 1
fi

# ============================================================
# Image finden
# ============================================================
IMAGE_FILE=""

# Zuerst unkomprimierte .img suchen
if ls "${DEPLOY_DIR}"/*.img 1>/dev/null 2>&1; then
    IMAGE_FILE=$(ls -t "${DEPLOY_DIR}"/*.img 2>/dev/null | head -1)
fi

# Falls kein .img: komprimierte Version suchen und entpacken
if [ -z "${IMAGE_FILE}" ]; then
    COMPRESSED=""
    if ls "${DEPLOY_DIR}"/*.img.xz 1>/dev/null 2>&1; then
        COMPRESSED=$(ls -t "${DEPLOY_DIR}"/*.img.xz | head -1)
    elif ls "${DEPLOY_DIR}"/*.img.gz 1>/dev/null 2>&1; then
        COMPRESSED=$(ls -t "${DEPLOY_DIR}"/*.img.gz | head -1)
    elif ls "${DEPLOY_DIR}"/*.img.zip 1>/dev/null 2>&1; then
        COMPRESSED=$(ls -t "${DEPLOY_DIR}"/*.img.zip | head -1)
    fi

    if [ -n "${COMPRESSED}" ]; then
        echo "[INFO] Entpacke ${COMPRESSED}..."
        case "${COMPRESSED}" in
            *.xz)  xz -dkf "${COMPRESSED}"; IMAGE_FILE="${COMPRESSED%.xz}" ;;
            *.gz)  gzip -dkf "${COMPRESSED}"; IMAGE_FILE="${COMPRESSED%.gz}" ;;
            *.zip) unzip -o "${COMPRESSED}" -d "${DEPLOY_DIR}"; IMAGE_FILE=$(ls -t "${DEPLOY_DIR}"/*.img | head -1) ;;
        esac
    fi
fi

if [ -z "${IMAGE_FILE}" ] || [ ! -f "${IMAGE_FILE}" ]; then
    echo "[FEHLER] Kein Image gefunden in ${DEPLOY_DIR}/"
    echo "         Zuerst './scripts/build.sh' ausführen."
    exit 1
fi

# ============================================================
# Secrets prüfen
# ============================================================
SECRETS_FILE="${PROJECT_DIR}/secrets.env"
if [ ! -f "${SECRETS_FILE}" ]; then
    echo "[FEHLER] secrets.env nicht gefunden!"
    echo "         cp secrets.env.example secrets.env"
    exit 1
fi

# IP aus secrets.env lesen für die Abschlussmeldung
PI_IP=$(grep -E "^PI_IP=" "${SECRETS_FILE}" 2>/dev/null | cut -d'=' -f2 || echo "192.168.178.49")
PI_IP="${PI_IP:-192.168.178.49}"

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
echo " Device:  $(lsblk -d -o NAME,SIZE,MODEL "${DEVICE}" 2>/dev/null | tail -1)"
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
# Glob ohne Quotes damit die Shell expandiert
for part in "${DEVICE}"?*; do
    sudo umount "${part}" 2>/dev/null || true
done

echo "[INFO] Schreibe Image auf ${DEVICE}..."
echo "       Das kann einige Minuten dauern..."
sudo dd if="${IMAGE_FILE}" of="${DEVICE}" bs=4M status=progress conv=fsync

echo "[INFO] Synchronisiere..."
sync

# Kernel über neue Partitionstabelle informieren
sudo partprobe "${DEVICE}" 2>/dev/null || true
sleep 2

# ============================================================
# secrets.env auf Boot-Partition kopieren
# ============================================================
echo "[INFO] Mounte Boot-Partition..."

# Partition-Name bestimmen (sdX1 vs mmcblk0p1 vs nvme0n1p1)
if [[ "${DEVICE}" == *"mmcblk"* ]] || [[ "${DEVICE}" == *"nvme"* ]]; then
    BOOT_PARTITION="${DEVICE}p1"
else
    BOOT_PARTITION="${DEVICE}1"
fi

# Warte bis die Partition verfügbar ist
for i in $(seq 1 10); do
    if [ -b "${BOOT_PARTITION}" ]; then
        break
    fi
    sleep 1
done

if [ ! -b "${BOOT_PARTITION}" ]; then
    echo "[FEHLER] Boot-Partition ${BOOT_PARTITION} nicht gefunden!"
    echo "         Prüfe ob das Image korrekt geschrieben wurde."
    exit 1
fi

MOUNT_POINT=$(mktemp -d)
sudo mount "${BOOT_PARTITION}" "${MOUNT_POINT}"

echo "[INFO] Kopiere secrets.env auf Boot-Partition..."
sudo cp "${SECRETS_FILE}" "${MOUNT_POINT}/secrets.env"
sudo chmod 600 "${MOUNT_POINT}/secrets.env"

# Prüfe ob die Datei tatsächlich angekommen ist
if [ ! -f "${MOUNT_POINT}/secrets.env" ]; then
    echo "[FEHLER] secrets.env konnte nicht auf die Boot-Partition kopiert werden!"
    sudo umount "${MOUNT_POINT}"
    rmdir "${MOUNT_POINT}"
    exit 1
fi

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
echo " 3. Ca. 5-10 Minuten warten (First Boot installiert Pi-hole + Log2RAM)"
echo " 4. Pi-hole erreichbar unter: http://${PI_IP}/admin"
echo " 5. Validierung: ./scripts/validate.sh ${PI_IP}"
echo ""

#!/bin/bash
# flash.sh – Image auf SD-Karte schreiben und secrets.env deployen
#
# Verwendung:
#   ./scripts/flash.sh /dev/sdX       (ganzes Laufwerk)
#   ./scripts/flash.sh /dev/mmcblk0

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"
DEPLOY_DIR="${PROJECT_DIR}/deploy"

# ============================================================
# Fortschritts-Tracking
# ============================================================
FLASH_START=$(date +%s)
CURRENT_STEP=0
TOTAL_STEPS=5   # wird ggf. auf 6 erhöht wenn Entpacken nötig

show_step() {
    local step="$1"
    local label="$2"
    CURRENT_STEP="${step}"

    local pct=$(( step * 100 / TOTAL_STEPS ))
    local filled=$(( step * 24 / TOTAL_STEPS ))
    local empty=$(( 24 - filled ))
    local bar=""
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done

    local elapsed=$(( $(date +%s) - FLASH_START ))
    local eta_str=""
    if [ "${step}" -gt 0 ] && [ "${pct}" -lt 100 ]; then
        local total_est=$(( elapsed * TOTAL_STEPS / step ))
        local remaining=$(( total_est - elapsed ))
        if [ "${remaining}" -gt 0 ]; then
            local rem_m=$(( remaining / 60 ))
            local rem_s=$(( remaining % 60 ))
            eta_str="  |  ETA: ${rem_m}m ${rem_s}s"
        fi
    fi

    echo ""
    printf "  \033[1m[%s]\033[0m  Schritt %d/%d – %s%s\n" \
        "${bar}" "${step}" "${TOTAL_STEPS}" "${label}" "${eta_str}"
    echo ""
}

# ============================================================
# Argumente prüfen
# ============================================================
if [ $# -lt 1 ]; then
    echo "Verwendung: $0 <device>"
    echo "  Beispiel: $0 /dev/sdc       (ganzes Laufwerk, NICHT /dev/sdc1!)"
    echo "  Beispiel: $0 /dev/mmcblk0"
    echo ""
    echo "WICHTIG: Immer das ganze Laufwerk angeben, nicht eine Partition!"
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

# Prüfe ob eine Partition statt des ganzen Laufwerks angegeben wurde
DEVICE_TYPE=$(lsblk -no TYPE "${DEVICE}" 2>/dev/null || echo "unknown")
if [ "${DEVICE_TYPE}" = "part" ]; then
    PARENT_DISK=$(lsblk -no PKNAME "${DEVICE}" 2>/dev/null || echo "")
    if [ -n "${PARENT_DISK}" ]; then
        echo ""
        echo "[WARNUNG] Du hast eine Partition angegeben: ${DEVICE}"
        echo "          Das Image muss auf das ganze Laufwerk geschrieben werden: /dev/${PARENT_DISK}"
        echo ""
        read -rp "  /dev/${PARENT_DISK} verwenden? (ja/NEIN): " use_parent
        if [ "${use_parent}" = "ja" ]; then
            DEVICE="/dev/${PARENT_DISK}"
        else
            echo "Abgebrochen."
            exit 1
        fi
    else
        echo "[FEHLER] ${DEVICE} ist eine Partition. Bitte das ganze Laufwerk angeben (z.B. /dev/sdc)."
        exit 1
    fi
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

if ls "${DEPLOY_DIR}"/*.img 1>/dev/null 2>&1; then
    IMAGE_FILE=$(ls -t "${DEPLOY_DIR}"/*.img 2>/dev/null | head -1)
fi

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
        TOTAL_STEPS=6   # Entpacken kommt als Extra-Schritt hinzu
        COMP_SIZE=$(stat --printf="%s" "${COMPRESSED}")

        show_step 1 "Entpacke $(basename "${COMPRESSED}")"
        if command -v pv > /dev/null 2>&1; then
            case "${COMPRESSED}" in
                *.xz)  pv -N "  Entpacken" -s "${COMP_SIZE}" "${COMPRESSED}" | xz -d > "${COMPRESSED%.xz}"; IMAGE_FILE="${COMPRESSED%.xz}" ;;
                *.gz)  pv -N "  Entpacken" -s "${COMP_SIZE}" "${COMPRESSED}" | gzip -d > "${COMPRESSED%.gz}"; IMAGE_FILE="${COMPRESSED%.gz}" ;;
                *.zip) unzip -o "${COMPRESSED}" -d "${DEPLOY_DIR}"; IMAGE_FILE=$(ls -t "${DEPLOY_DIR}"/*.img | head -1) ;;
            esac
        else
            echo "  (installiere 'pv' für Fortschrittsanzeige: sudo apt install pv)"
            case "${COMPRESSED}" in
                *.xz)  xz -dkf "${COMPRESSED}"; IMAGE_FILE="${COMPRESSED%.xz}" ;;
                *.gz)  gzip -dkf "${COMPRESSED}"; IMAGE_FILE="${COMPRESSED%.gz}" ;;
                *.zip) unzip -o "${COMPRESSED}" -d "${DEPLOY_DIR}"; IMAGE_FILE=$(ls -t "${DEPLOY_DIR}"/*.img | head -1) ;;
            esac
        fi
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

PI_IP=$(grep -E "^PI_IP=" "${SECRETS_FILE}" 2>/dev/null | cut -d'=' -f2 || echo "192.168.178.49")
PI_IP="${PI_IP:-192.168.178.49}"

# ============================================================
# Bestätigung
# ============================================================
IMAGE_SIZE_BYTES=$(stat --printf="%s" "${IMAGE_FILE}")
IMAGE_SIZE_HUMAN=$(du -h "${IMAGE_FILE}" | awk '{print $1}')

echo ""
echo "=========================================="
echo " ACHTUNG: SD-Karte wird überschrieben!"
echo "=========================================="
echo ""
echo " Image:   $(basename "${IMAGE_FILE}")"
echo " Größe:   ${IMAGE_SIZE_HUMAN}"
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
show_step $(( CURRENT_STEP + 1 )) "Unmounte Partitionen auf ${DEVICE}"
for part in "${DEVICE}"?* "${DEVICE}p"?*; do
    [ -b "${part}" ] 2>/dev/null && sudo umount "${part}" 2>/dev/null || true
done

show_step $(( CURRENT_STEP + 1 )) "Schreibe Image auf ${DEVICE} (${IMAGE_SIZE_HUMAN})"
if command -v pv > /dev/null 2>&1; then
    pv -N "  Schreiben" -s "${IMAGE_SIZE_BYTES}" "${IMAGE_FILE}" | sudo dd of="${DEVICE}" bs=4M conv=fsync 2>/dev/null
else
    echo "  (installiere 'pv' für Fortschrittsanzeige: sudo apt install pv)"
    sudo dd if="${IMAGE_FILE}" of="${DEVICE}" bs=4M status=progress conv=fsync
fi

show_step $(( CURRENT_STEP + 1 )) "Synchronisiere Puffer..."
sync

sudo partprobe "${DEVICE}" 2>/dev/null || true
sleep 2

# ============================================================
# secrets.env auf Boot-Partition kopieren
# ============================================================
show_step $(( CURRENT_STEP + 1 )) "Mounte Boot-Partition und kopiere secrets.env"

if [[ "${DEVICE}" == *"mmcblk"* ]] || [[ "${DEVICE}" == *"nvme"* ]]; then
    BOOT_PARTITION="${DEVICE}p1"
else
    BOOT_PARTITION="${DEVICE}1"
fi

for i in $(seq 1 10); do
    if [ -b "${BOOT_PARTITION}" ]; then
        break
    fi
    echo "  Warte auf ${BOOT_PARTITION}... (${i}/10)"
    sleep 1
done

if [ ! -b "${BOOT_PARTITION}" ]; then
    echo "[FEHLER] Boot-Partition ${BOOT_PARTITION} nicht gefunden!"
    echo "         Verfügbare Partitionen:"
    lsblk "${DEVICE}" 2>/dev/null || true
    exit 1
fi

MOUNT_POINT=$(mktemp -d)
sudo mount "${BOOT_PARTITION}" "${MOUNT_POINT}"

echo "[INFO] Kopiere secrets.env auf Boot-Partition..."
sudo cp "${SECRETS_FILE}" "${MOUNT_POINT}/secrets.env"
sudo chmod 600 "${MOUNT_POINT}/secrets.env"

if sudo test -f "${MOUNT_POINT}/secrets.env"; then
    echo "[OK]   secrets.env erfolgreich kopiert."
else
    echo "[FEHLER] secrets.env konnte nicht kopiert werden!"
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
FLASH_END=$(date +%s)
FLASH_TOTAL=$(( FLASH_END - FLASH_START ))
FLASH_M=$(( FLASH_TOTAL / 60 ))
FLASH_S=$(( FLASH_TOTAL % 60 ))

show_step "${TOTAL_STEPS}" "Fertig"
echo "=========================================="
echo " Flash erfolgreich!"
echo " Gesamtdauer: ${FLASH_M}m ${FLASH_S}s"
echo "=========================================="
echo ""
echo " Nächste Schritte:"
echo " 1. SD-Karte in den Pi Zero W einlegen"
echo " 2. Netzteil anschließen"
echo " 3. Ca. 5-10 Minuten warten (First Boot installiert Pi-hole + Log2RAM)"
echo " 4. Pi-hole erreichbar unter: http://${PI_IP}/admin"
echo " 5. Validierung: ./scripts/validate.sh ${PI_IP}"
echo ""
#!/bin/bash
# build.sh – Lokaler Build-Wrapper für pi-gen
#
# Verwendung:
#   ./scripts/build.sh              # Build via Docker (empfohlen)
#   ./scripts/build.sh --native     # Build nativ (nur auf Debian/Ubuntu)
#   ./scripts/build.sh --clean      # Sauberer Build (löscht vorherige Artefakte)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"
PI_GEN_DIR="${PROJECT_DIR}/pi-gen"
PI_GEN_REPO="https://github.com/RPi-Distro/pi-gen.git"
PI_GEN_BRANCH="bookworm"  # bookworm-Branch für Bookworm 32-bit (armhf) Images

USE_DOCKER=true
CLEAN_BUILD=false

# Argumente parsen
while [[ $# -gt 0 ]]; do
    case $1 in
        --native)
            USE_DOCKER=false
            shift
            ;;
        --clean)
            CLEAN_BUILD=true
            shift
            ;;
        -h|--help)
            echo "Verwendung: $0 [--native] [--clean]"
            echo "  --native   Build ohne Docker (nur Debian/Ubuntu)"
            echo "  --clean    Sauberer Build (löscht vorherige Artefakte)"
            exit 0
            ;;
        *)
            echo "Unbekannte Option: $1"
            exit 1
            ;;
    esac
done

echo "=========================================="
echo " Pi-hole Image Builder"
echo "=========================================="
echo " Docker:     ${USE_DOCKER}"
echo " Clean:      ${CLEAN_BUILD}"
echo " Pi-gen:     ${PI_GEN_BRANCH}"
echo "=========================================="

# ============================================================
# 1. Secrets prüfen
# ============================================================
if [ ! -f "${PROJECT_DIR}/secrets.env" ]; then
    echo ""
    echo "[FEHLER] secrets.env nicht gefunden!"
    echo "         Kopiere secrets.env.example nach secrets.env und fülle die Werte aus."
    echo "         cp secrets.env.example secrets.env"
    exit 1
fi

# ============================================================
# 2. pi-gen klonen / aktualisieren
# ============================================================
if [ ! -d "${PI_GEN_DIR}" ]; then
    echo ""
    echo "[INFO] Klone pi-gen Repository..."
    git clone --depth 1 --branch "${PI_GEN_BRANCH}" "${PI_GEN_REPO}" "${PI_GEN_DIR}"
else
    echo ""
    echo "[INFO] Aktualisiere pi-gen Repository..."
    cd "${PI_GEN_DIR}"
    git fetch origin "${PI_GEN_BRANCH}"
    git reset --hard "origin/${PI_GEN_BRANCH}"
    cd "${PROJECT_DIR}"
fi

# ============================================================
# 3. Konfiguration in pi-gen kopieren
# ============================================================
echo ""
echo "[INFO] Kopiere Konfiguration..."

# config Datei
cp "${PROJECT_DIR}/config" "${PI_GEN_DIR}/config"

# Custom Stage kopieren (nicht verlinken – Docker-Build kann Symlinks
# außerhalb des Build-Kontexts nicht auflösen)
if [ -L "${PI_GEN_DIR}/stage-pihole" ] || [ -d "${PI_GEN_DIR}/stage-pihole" ]; then
    rm -rf "${PI_GEN_DIR}/stage-pihole"
fi
cp -a "${PROJECT_DIR}/stage-pihole" "${PI_GEN_DIR}/stage-pihole"

# Stages 3-5 überspringen (wir bauen nur Lite + unsere Stage)
for stage in stage3 stage4 stage5; do
    touch "${PI_GEN_DIR}/${stage}/SKIP" 2>/dev/null || true
done
touch "${PI_GEN_DIR}/stage4/SKIP_IMAGES" 2>/dev/null || true
touch "${PI_GEN_DIR}/stage5/SKIP_IMAGES" 2>/dev/null || true

# ============================================================
# 4. Clean Build falls gewünscht
# ============================================================
if [ "${CLEAN_BUILD}" = true ]; then
    echo ""
    echo "[INFO] Sauberer Build – lösche vorherige Artefakte..."
    rm -rf "${PI_GEN_DIR}/work" "${PI_GEN_DIR}/deploy"
fi

# ============================================================
# 5. Build starten
# ============================================================
cd "${PI_GEN_DIR}"

if [ "${USE_DOCKER}" = true ]; then
    echo ""
    echo "[INFO] Starte Build via Docker..."
    echo "       Das kann 30-60 Minuten dauern."
    echo ""
    ./build-docker.sh
else
    echo ""
    echo "[INFO] Starte nativen Build..."
    echo "       Das kann 30-60 Minuten dauern."
    echo ""
    sudo ./build.sh
fi

# ============================================================
# 6. Ergebnis prüfen
# ============================================================
echo ""
if ls "${PI_GEN_DIR}/deploy/"*.img* 1>/dev/null 2>&1; then
    echo "=========================================="
    echo " Build erfolgreich!"
    echo "=========================================="
    echo ""
    echo " Image(s):"
    ls -lh "${PI_GEN_DIR}/deploy/"*.img*
    echo ""
    echo " Nächster Schritt:"
    echo "   ./scripts/flash.sh /dev/sdX"
    echo ""

    # Kopiere Image ins Projekt-Verzeichnis
    mkdir -p "${PROJECT_DIR}/deploy"
    cp "${PI_GEN_DIR}/deploy/"*.img* "${PROJECT_DIR}/deploy/"
else
    echo "=========================================="
    echo " Build fehlgeschlagen!"
    echo "=========================================="
    echo " Prüfe die Log-Ausgabe oben."
    exit 1
fi

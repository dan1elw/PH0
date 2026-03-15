#!/bin/bash
# build.sh – Lokaler Build-Wrapper für pi-gen
#
# Verwendung:
#   ./scripts/build.sh              # Build via Docker (empfohlen)
#   ./scripts/build.sh --native     # Build nativ (nur auf Debian/Ubuntu)
#   ./scripts/build.sh --clean      # Sauberer Build (löscht vorherige Artefakte)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"
readonly PROJECT_DIR
readonly PI_GEN_DIR="${PROJECT_DIR}/pi-gen"
readonly PI_GEN_REPO="https://github.com/RPi-Distro/pi-gen.git"
# bookworm-Branch: erzeugt 32-bit armhf-Images für den Pi Zero W (ARMv6).
# NICHT master verwenden – master zeigt seit Aug 2025 auf Trixie (64-bit).
readonly PI_GEN_BRANCH="bookworm"

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
        -h | --help)
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

# ============================================================
# Fortschritts-Tracking
# ============================================================
BUILD_START=$(date +%s)
CURRENT_STEP=0
TOTAL_STEPS=4 # wird auf 5 erhöht wenn --clean

[ "${CLEAN_BUILD}" = true ] && TOTAL_STEPS=5

show_step() {
    local step="$1"
    local label="$2"
    CURRENT_STEP="${step}"

    # Fortschrittsbalken: 24 Zeichen breit, proportional zum aktuellen Schritt
    local pct=$((step * 100 / TOTAL_STEPS))
    local filled=$((step * 24 / TOTAL_STEPS))
    local empty=$((24 - filled))
    local bar=""
    for ((i = 0; i < filled; i++)); do bar+="█"; done
    for ((i = 0; i < empty; i++)); do bar+="░"; done

    # Lineare ETA-Schätzung: vergangene Zeit / bisherige Schritte × Gesamtschritte
    local elapsed=$(($(date +%s) - BUILD_START))
    local eta_str=""
    if [ "${step}" -gt 0 ] && [ "${pct}" -lt 100 ]; then
        local total_est=$((elapsed * TOTAL_STEPS / step))
        local remaining=$((total_est - elapsed))
        if [ "${remaining}" -gt 0 ]; then
            local rem_m=$((remaining / 60))
            local rem_s=$((remaining % 60))
            eta_str="  |  ETA: ${rem_m}m ${rem_s}s"
        fi
    fi

    echo ""
    printf "  \033[1m[%s]\033[0m  Schritt %d/%d – %s%s\n" \
        "${bar}" "${step}" "${TOTAL_STEPS}" "${label}" "${eta_str}"
    echo ""
}

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
    show_step 1 "Klone pi-gen Repository (${PI_GEN_BRANCH})..."
    git clone --depth 1 --branch "${PI_GEN_BRANCH}" "${PI_GEN_REPO}" "${PI_GEN_DIR}"
else
    show_step 1 "Aktualisiere pi-gen Repository (${PI_GEN_BRANCH})..."
    cd "${PI_GEN_DIR}"
    git fetch origin "${PI_GEN_BRANCH}"
    git reset --hard "origin/${PI_GEN_BRANCH}"
    cd "${PROJECT_DIR}"
fi

# ============================================================
# 3. Konfiguration in pi-gen kopieren
# ============================================================
show_step 2 "Kopiere Konfiguration und Stage..."

# config Datei – IMG_NAME um Uhrzeit ergänzen (HHMM) damit mehrere
# Builds am gleichen Tag unterscheidbar sind
cp "${PROJECT_DIR}/config" "${PI_GEN_DIR}/config"
BUILD_HHMM="$(date '+%H%M')"
sed -i "s/^IMG_NAME=.*/IMG_NAME=${BUILD_HHMM}-pihole-zerow/" "${PI_GEN_DIR}/config"

# Custom Stage kopieren (nicht verlinken – Docker-Build kann Symlinks
# außerhalb des Build-Kontexts nicht auflösen)
if [ -L "${PI_GEN_DIR}/stage-pihole" ] || [ -d "${PI_GEN_DIR}/stage-pihole" ]; then
    rm -rf "${PI_GEN_DIR}/stage-pihole"
fi
cp -a "${PROJECT_DIR}/stage-pihole" "${PI_GEN_DIR}/stage-pihole"

# Stages 3-5 überspringen: stage0=bootstrap, stage1=minimal, stage2=lite – das
# reicht für Pi-hole. stage3=desktop, stage4/5=full – nicht benötigt.
# SKIP verhindert den Build der Stage; SKIP_IMAGES verhindert zusätzlich das
# Erzeugen eines separaten Images für diese Stage.
for stage in stage3 stage4 stage5; do
    touch "${PI_GEN_DIR}/${stage}/SKIP" 2>/dev/null || true
done
# stage2 = RPi OS Lite (Zwischenergebnis) – kein eigenes Image nötig
touch "${PI_GEN_DIR}/stage2/SKIP_IMAGES" 2>/dev/null || true
touch "${PI_GEN_DIR}/stage4/SKIP_IMAGES" 2>/dev/null || true
touch "${PI_GEN_DIR}/stage5/SKIP_IMAGES" 2>/dev/null || true

# ============================================================
# 4. Clean Build falls gewünscht
# ============================================================
if [ "${CLEAN_BUILD}" = true ]; then
    show_step 3 "Sauberer Build – lösche vorherige Artefakte..."
    rm -rf "${PI_GEN_DIR}/work" "${PI_GEN_DIR}/deploy"
fi

# ============================================================
# 5. Build starten
# ============================================================
cd "${PI_GEN_DIR}"

BUILD_MODE="Docker"
[ "${USE_DOCKER}" = false ] && BUILD_MODE="Nativ"
show_step $((CURRENT_STEP + 1)) "pi-gen Build starten (${BUILD_MODE}) – das dauert 30–60 Minuten..."

# set -e ist aktiv, daher build-docker.sh nicht direkt aufrufen – ein
# Fehler würde das Script sofort abbrechen, bevor wir die Dauer ausgeben
# können. Stattdessen Exit-Code manuell abfangen und am Ende auswerten.
BUILD_EXIT=0
if [ "${USE_DOCKER}" = true ]; then
    # Ein alter pigen_work-Container von einem abgebrochenen Build würde
    # losetup mit "Device or resource busy" blockieren. Vorher entfernen.
    DOCKER_CMD="docker"
    # Rootless Docker braucht kein sudo; reguläres Docker (root-Daemon) schon.
    if ! docker ps >/dev/null 2>&1 || docker info 2>/dev/null | grep -q rootless; then
        DOCKER_CMD="sudo docker"
    fi
    # shellcheck disable=SC2086  # DOCKER_CMD darf auf "sudo docker" splitten
    if ${DOCKER_CMD} ps -a --filter name=pigen_work -q | grep -q .; then
        echo "Entferne alten pigen_work Container..."
        # shellcheck disable=SC2086
        ${DOCKER_CMD} rm -v pigen_work >/dev/null
    fi

    # systemd-resolved (127.0.0.53) ist im Docker-Container nicht erreichbar.
    # Google DNS explizit übergeben, damit apt während des Builds auflösen kann.
    # PIGEN_DOCKER_OPTS wird von build-docker.sh als zusätzliche docker-run-Flags gelesen.
    export PIGEN_DOCKER_OPTS="${PIGEN_DOCKER_OPTS:-} --dns 8.8.8.8 --dns 8.8.4.4"
    ./build-docker.sh || BUILD_EXIT=$?
else
    sudo ./build.sh || BUILD_EXIT=$?
fi

# ============================================================
# 6. Ergebnis prüfen
# ============================================================
BUILD_END=$(date +%s)
BUILD_TOTAL=$((BUILD_END - BUILD_START))
BUILD_M=$((BUILD_TOTAL / 60))
BUILD_S=$((BUILD_TOTAL % 60))

show_step "${TOTAL_STEPS}" "Ergebnis prüfen und kopieren..."
if [ "${BUILD_EXIT}" -ne 0 ]; then
    echo "=========================================="
    echo " Build fehlgeschlagen! (Exit: ${BUILD_EXIT})"
    echo " Vergangene Zeit: ${BUILD_M}m ${BUILD_S}s"
    echo "=========================================="
    echo " Prüfe die Log-Ausgabe oben."
    exit "${BUILD_EXIT}"
fi

if ls "${PI_GEN_DIR}/deploy/"*"${BUILD_HHMM}"*.img* 1>/dev/null 2>&1; then
    # Kopiere nur das gerade gebaute Image ins Projekt-Verzeichnis
    mkdir -p "${PROJECT_DIR}/deploy"
    cp "${PI_GEN_DIR}/deploy/"*"${BUILD_HHMM}"*.img* "${PROJECT_DIR}/deploy/"

    echo "=========================================="
    echo " Build erfolgreich!"
    echo " Gesamtdauer: ${BUILD_M}m ${BUILD_S}s"
    echo "=========================================="
    echo ""
    echo " Image(s):"
    ls -lh "${PI_GEN_DIR}/deploy/"*"${BUILD_HHMM}"*.img*
    echo ""
    echo " Nächster Schritt:"
    echo "   ./scripts/flash.sh /dev/sdX"
    echo ""
else
    echo "=========================================="
    echo " Build fehlgeschlagen!"
    echo " Vergangene Zeit: ${BUILD_M}m ${BUILD_S}s"
    echo "=========================================="
    echo " Prüfe die Log-Ausgabe oben."
    exit 1
fi

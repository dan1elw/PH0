# PH0 - Pi-hole for Raspberry Pi Zero

> **Hinweis:** Dieses Projekt wurde mit Unterstützung von KI (Claude/Anthropic) erstellt.

Reproduzierbares, versioniertes Raspberry Pi OS Image mit Pi-hole v6 als netzwerkweitem
DNS-/Ad-Blocking-Server. Optimiert für den Raspberry Pi Zero W mit SD-Karten-Schutz,
automatisiertem Watchdog-Stack und CI/CD-Pipeline via GitHub Actions.

## Inhalt

- [Funktionsumfang](#funktionsumfang)
- [Voraussetzungen](#voraussetzungen)
- [Schnellstart](#schnellstart)
- [Architektur](#architektur)
- [Repository-Struktur](#repository-struktur)
- [Konfiguration](#konfiguration)
- [Image bauen](#image-bauen)
- [Image flashen](#image-flashen)
- [Ersteinrichtung (First Boot)](#ersteinrichtung-first-boot)
- [Validierung](#validierung)
- [Wartung](#wartung)
- [Troubleshooting](#troubleshooting)
- [Changelog](#changelog)
- [Lizenz](#lizenz)

## Funktionsumfang

- **Pi-hole v6** mit REST API, vorkonfiguriert für unattended Installation
- **Log2RAM** – Logs ins RAM, stündliche Synchronisation auf SD-Karte (50 MB)
- **tmpfs** für `/tmp` und `/var/tmp` – keine temporären Dateien auf der SD-Karte
- **Hardware-Watchdog** (`bcm2835_wdt`) – automatischer Neustart bei Systemhänger
- **WLAN-Monitor** – automatische Reconnection bei Verbindungsverlust
- **Health-Check** – systemd-Timer prüft alle 5 Minuten DNS, FTL-Status, Speicher, Temperatur
- **First-Boot-Service** – Secrets werden beim Erststart aus `secrets.env` geladen, nie im Image gespeichert
- **SSH gehärtet** – Key-basierte Authentifizierung, Passwort-Login deaktiviert
- **Firewall (nftables)** – nur DNS (53), HTTP (80), SSH (22) erlaubt
- **CI/CD** – GitHub Actions baut bei jedem Tag automatisch ein neues Image

## Voraussetzungen

### Hardware

- Raspberry Pi Zero W (ARMv6, 512 MB RAM)
- microSD-Karte (mind. 8 GB, empfohlen: 16 GB Class 10 / A1)
- 5V/1A Micro-USB Netzteil

### Zum Bauen (lokal)

- Linux-System (Debian/Ubuntu empfohlen)
- Docker (für `build-docker.sh`) oder die pi-gen Abhängigkeiten nativ installiert
- ca. 10 GB freier Speicherplatz
- `git`, `curl`, `jq`

### Zum Bauen (CI/CD)

- GitHub Repository mit aktivierten Actions
- Keine zusätzliche Infrastruktur erforderlich

## Schnellstart

```bash
# 1. Repository klonen
git clone https://github.com/dan1elw/PH0.git
cd PH0

# 2. Secrets konfigurieren
cp secrets.env.example secrets.env
nano secrets.env  # Werte ausfüllen

# 3. Image bauen
./scripts/build.sh --clean

# 4. Image auf SD-Karte flashen (ganzes Laufwerk, z.B. /dev/sdc – NICHT /dev/sdc1!)
./scripts/flash.sh /dev/sdX

# 5. Erststart – Pi mit Netzwerk verbinden und booten
# Der First-Boot-Service installiert Pi-hole + Log2RAM und konfiguriert alles. Das dauert ca. 5-10 Minuten. Danach ist Pi-hole erreichbar unter der konfigurierten IP Addresse: http://192.168.178.69/admin (default)
./scripts/validate.sh --wait
```

## Architektur

```
┌──────────────────────────────────────────────────────┐
│              GitHub Repository + Actions             │
│  pi-gen Build → .img Release Asset                   │
└──────────────────────┬───────────────────────────────┘
                       │ Flash auf SD-Karte
                       ▼
┌──────────────────────────────────────────────────────┐
│         Raspberry Pi Zero W (192.168.178.69)         │
│         Raspberry Pi OS Lite (Bookworm, armhf)       │
│                                                      │
│  ┌────────────┐  ┌────────────┐  ┌────────────────┐  │
│  │  Pi-hole   │  │  Log2RAM   │  │  Watchdog      │  │
│  │  v6 (FTL)  │  │  /var/log  │  │  Stack         │  │
│  │            │  │  50MB RAM  │  │                │  │
│  │  DNS :53   │  │  1h Sync   │  │  HW-Watchdog   │  │
│  │  HTTP :80  │  │            │  │  WLAN-Monitor  │  │
│  │  REST API  │  │            │  │  Health-Check  │  │
│  └────────────┘  └────────────┘  └────────────────┘  │
│                                                      │
│  ┌────────────────────────────────────────────────┐  │
│  │  First-Boot → secrets.env lesen → sich selbst  │  │
│  │  deaktivieren                                  │  │
│  └────────────────────────────────────────────────┘  │
│                                                      │
│  ┌────────────────────────────────────────────────┐  │
│  │  Härtung: nftables, SSH Key-Only, tmpfs        │  │
│  └────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────┘
```

## Repository-Struktur

```
pihole-image/
├── README.md                          # Diese Datei
├── LICENSE                            # MIT License
├── config                             # pi-gen Hauptkonfiguration
├── secrets.env.example                # Template für Credentials
├── .gitignore
├── .github/workflows/
│   └── build-image.yml                # GitHub Actions CI/CD
├── stage-pihole/
│   ├── prerun.sh                      # Stage-Setup
│   ├── 00-install-packages/
│   │   ├── 00-packages                # APT-Pakete
│   │   └── 01-run.sh                  # Pi-hole + Log2RAM Installation
│   ├── 01-configure/
│   │   ├── files/                     # Konfigurationsdateien
│   │   │   ├── pihole.toml            # Pi-hole v6 Konfiguration
│   │   │   ├── log2ram.conf           # Log2RAM Konfiguration
│   │   │   ├── watchdog.conf          # Hardware-Watchdog
│   │   │   ├── wlan-monitor.sh        # WLAN Reconnect Script
│   │   │   ├── wlan-monitor.service   # WLAN Monitor systemd Unit
│   │   │   ├── health-check.sh        # Health-Check Script
│   │   │   ├── health-check.service   # Health-Check systemd Unit
│   │   │   └── health-check.timer     # Health-Check Timer (5 Min)
│   │   └── 01-run.sh                  # Konfiguration deployen
│   ├── 02-first-boot/
│   │   ├── files/
│   │   │   ├── first-boot.sh          # First-Boot Script
│   │   │   └── first-boot.service     # First-Boot systemd Unit
│   │   └── 01-run.sh                  # First-Boot installieren
│   └── 03-hardening/
│       └── 01-run.sh                  # SSH, Firewall, tmpfs
├── scripts/
│   ├── build.sh                       # Lokaler Build-Wrapper
│   ├── flash.sh                       # Image auf SD-Karte
│   └── validate.sh                    # Post-Boot Validierung
└── docs/
    ├── ARCHITECTURE.md                # Detaillierte Architektur
    ├── SETUP.md                       # Ersteinrichtung
    ├── TROUBLESHOOTING.md             # Fehlerbehebung
    └── CHANGELOG.md                   # Änderungshistorie
```

## Konfiguration

### secrets.env

Vor dem Build muss `secrets.env` erstellt werden. Das File wird **niemals** ins Repository committed.

```bash
cp secrets.env.example secrets.env
```

Folgende Werte müssen gesetzt werden:

| Variable | Pflicht | Beschreibung | Beispiel |
|---|---|---|---|
| `PI_USER` | Ja | Linux-Benutzername für SSH-Login | `pi` |
| `PI_USER_PASSWORD` | Ja | Passwort für sudo und Console-Login | `mein-passwort` |
| `PIHOLE_PASSWORD` | Ja | Admin-Passwort für Pi-hole Web UI | `mein-sicheres-passwort` |
| `WIFI_SSID` | Ja | WLAN-Name | `MeinWLAN` |
| `WIFI_PASSWORD` | Ja | WLAN-Passwort | `wlan-passwort` |
| `SSH_PUBLIC_KEY` | Ja | Öffentlicher SSH-Schlüssel | `ssh-ed25519 AAAA...` |
| `WIFI_COUNTRY` | Nein | WLAN-Ländercode (Standard: `DE`) | `DE` |
| `PI_HOSTNAME` | Nein | Hostname des Pi (Standard: `pihole`) | `pihole` |
| `PI_IP` | Nein | Statische IP (Standard: `192.168.178.69`) | `192.168.178.69` |
| `PI_GATEWAY` | Nein | Gateway/Router (Standard: `192.168.178.1`) | `192.168.178.1` |
| `PI_PREFIX` | Nein | Subnetz-Präfix (Standard: `24`) | `24` |

### Statische IP

Die statische IP ist über `PI_IP` in `secrets.env` konfigurierbar (Default: `192.168.178.69/24`).

## Image bauen

### Lokal (empfohlen: via Docker)

```bash
# Voraussetzung: Docker installiert
./scripts/build.sh --clean

# Das fertige Image liegt in: deploy/
ls -la deploy/*.img.xz
```

### Via GitHub Actions

1. Repository auf GitHub pushen
2. Ein Tag erstellen: `git tag v1.0.0 && git push --tags`
3. Die Action baut automatisch und erstellt ein Release mit dem Image

## Image flashen

```bash
# SD-Karte identifizieren (das GANZE Laufwerk, z.B. sdc – nicht sdc1!)
lsblk

# Optional: pv installieren für Fortschrittsbalken beim Schreiben
sudo apt install pv

# Image flashen (sdX ersetzen mit dem eigenen identifizierten Laufwerk!)
./scripts/flash.sh /dev/sdX
```

**Wichtig:** Immer das ganze Laufwerk angeben (z.B. `/dev/sdc`), nicht eine Partition (z.B. `/dev/sdc1`).
Falls du versehentlich eine Partition angibst, erkennt das Script das und fragt nach dem richtigen Laufwerk.

Das Flash-Script:
1. Entpackt das komprimierte Image (`.img.xz`) falls nötig (mit Fortschrittsanzeige)
2. Schreibt das Image auf die SD-Karte (mit Fortschrittsanzeige via `pv` oder `dd status=progress`)
3. Kopiert `secrets.env` auf die Boot-Partition
4. Verifiziert, dass `secrets.env` korrekt kopiert wurde

## Ersteinrichtung (First Boot)

Beim ersten Boot passiert automatisch:

1. Der First-Boot-Service liest `secrets.env` von der Boot-Partition
2. Hostname wird gesetzt
3. Benutzer-Passwort wird gesetzt (für sudo und Console-Login)
4. WiFi wird konfiguriert (SSID, Passwort, statische IP)
5. SSH-Key wird deployt
6. **Pi-hole v6 wird installiert** (benötigt Internet-Verbindung)
7. Pi-hole Admin-Passwort wird gesetzt, Gravity (Blocklisten) wird geladen
8. **Log2RAM wird installiert**
9. Alle Services werden aktiviert (Watchdog, WLAN-Monitor, Health-Check)
10. `secrets.env` wird sicher gelöscht
11. Der First-Boot-Service deaktiviert sich selbst
12. Der Pi startet neu

Der gesamte Vorgang dauert ca. **5-10 Minuten** (Pi Zero W ist langsam).
Nach dem Neustart ist Pi-hole erreichbar unter:
- **Web UI:** http://192.168.178.69/admin
- **DNS:** 192.168.178.69:53

## Validierung

Nach dem Erststart:

```bash
# Vom Desktop aus testen (wartet bis Pi erreichbar ist)
./scripts/validate.sh --wait

# Oder ohne Warten (wenn Pi bereits läuft)
./scripts/validate.sh

# Mit anderer IP oder anderem User
./scripts/validate.sh 192.168.178.50 meinuser

# Oder manuell:
ssh pi@192.168.178.69

# Auf dem Pi:
pihole status
systemctl status pihole-FTL
systemctl status log2ram
systemctl status wlan-monitor
systemctl status health-check.timer
dig @127.0.0.1 google.com
```

## Wartung

### Pi-hole Update

```bash
ssh pi@192.168.178.69
pihole -up
```

### Gravity Update (Blocklisten)

```bash
pihole -g
```

### Log2RAM Status prüfen

```bash
systemctl status log2ram
df -h /var/log
```

### SD-Karten-Gesundheit prüfen

```bash
# I/O-Fehler in dmesg suchen
dmesg | grep -i "i/o error\|mmc\|sd"
```

### Image neu bauen und flashen

Bei SD-Karten-Ausfall einfach ein neues Image flashen – alle Konfigurationen sind
im Repository versioniert, Secrets in `secrets.env`.

## Troubleshooting

Siehe [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) für häufige Probleme.

### Schnellhilfe

| Problem | Lösung |
|---|---|
| Pi-hole nicht erreichbar | `ssh pi@192.168.178.69`, `systemctl status pihole-FTL` |
| DNS-Auflösung fehlgeschlagen | `dig @127.0.0.1 google.com`, Upstream prüfen |
| WLAN getrennt | Watchdog sollte automatisch reconnecten, `journalctl -u wlan-monitor` prüfen |
| SD-Karten I/O-Fehler | Neues Image flashen, neue SD-Karte verwenden |
| First-Boot hängt | Boot-Partition prüfen: ist `secrets.env` vorhanden? |

## Changelog

Siehe [docs/CHANGELOG.md](docs/CHANGELOG.md).

## Lizenz

MIT License – siehe [LICENSE](LICENSE).

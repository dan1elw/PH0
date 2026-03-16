# Ersteinrichtung – Setup Guide

## Voraussetzungen

- Git installiert
- Docker installiert (für den lokalen Build) oder GitHub Actions nutzen
- SD-Kartenleser
- SSH-Schlüsselpaar vorhanden (`ssh-keygen -t ed25519` falls nicht)
- Optional: `pv` für Fortschrittsanzeige beim Flashen (`sudo apt install pv`)

## Schritt 1: Repository klonen

```bash
git clone https://github.com/DEIN-USERNAME/pihole-image.git
cd pihole-image
```

## Schritt 2: Secrets konfigurieren

```bash
cp secrets.env.example secrets.env
nano secrets.env
```

Alle Pflichtfelder ausfüllen:

```bash
# Benutzer
PI_USER=pi
PI_USER_PASSWORD=dein-sicheres-passwort

# Pi-hole Admin-Passwort
PIHOLE_PASSWORD=dein-pihole-passwort

# WLAN
WIFI_SSID=DeinWLANName
WIFI_PASSWORD=dein-wlan-passwort
WIFI_COUNTRY=DE

# SSH Public Key (ganzer Key):
SSH_PUBLIC_KEY=ssh-ed25519 AAAA... user@host

# Optional:
PI_HOSTNAME=pihole
PI_IP=192.168.178.69
PI_GATEWAY=192.168.178.1
PI_PREFIX=24
```

Den SSH Public Key findest du unter `~/.ssh/id_ed25519.pub` (oder `.pub` deines bevorzugten Keys).

## Schritt 3: Image bauen

```bash
# Scripts ausführbar machen
chmod +x scripts/*.sh

# Build starten
./scripts/build.sh
```

Der Build dauert ca. 30-60 Minuten. Das fertige Image liegt danach in `deploy/`.
Alternativ: GitHub Actions erstellt das Image automatisch bei einem Tag-Push (`git tag v1.0.0 && git push --tags`).

## Schritt 4: SD-Karte flashen

```bash
# SD-Karte identifizieren – das GANZE Laufwerk, z.B. sdc (nicht sdc1!)
lsblk

# Image flashen
./scripts/flash.sh /dev/sdX
```

Das Script erkennt automatisch, wenn du versehentlich eine Partition statt des Laufwerks angibst,
und schlägt die richtige Korrektur vor. Es entpackt das Image, schreibt es auf die SD-Karte,
und kopiert `secrets.env` auf die Boot-Partition.

## Schritt 5: Erster Boot

1. SD-Karte in den Pi Zero W einlegen
2. Netzteil anschließen
3. **Ca. 5-10 Minuten warten** – der First-Boot-Service:
   - Konfiguriert WiFi und statische IP
   - Setzt Benutzer-Passwort und SSH-Key
   - Installiert Pi-hole v6 (braucht Internet)
   - Installiert Log2RAM
   - Aktiviert Watchdog, WLAN-Monitor, Health-Check
   - Löscht `secrets.env` und startet neu

## Schritt 6: Validierung

```bash
# Wartet bis Pi erreichbar ist, dann testet alle Services
./scripts/validate.sh --wait

# Oder ohne Warten
./scripts/validate.sh
```

## Schritt 7: Router konfigurieren

Konfiguriere deinen Router so, dass `192.168.178.69` als primärer DNS-Server
für alle Geräte im LAN verwendet wird. Setze den Router selbst (z.B. `192.168.178.1`)
als sekundären DNS – so funktioniert DNS auch wenn der Pi ausfällt.

Für Fritz!Box:
1. Internet → DNS-Server → Lokaler DNS-Server
2. Bevorzugter DNS: `192.168.178.69`
3. Alternativer DNS: `192.168.178.1` (oder ein öffentlicher wie `1.1.1.1`)

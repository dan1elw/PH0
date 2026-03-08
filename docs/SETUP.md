# Ersteinrichtung – Setup Guide

> **Hinweis:** Dieses Dokument wurde mit Unterstützung von KI (Claude/Anthropic) erstellt.

## Voraussetzungen

- Git installiert
- Docker installiert (für den Build)
- SD-Kartenleser
- SSH-Schlüsselpaar vorhanden (`ssh-keygen -t ed25519` falls nicht)

## Schritt 1: Repository klonen

```bash
git clone https://github.com/DEIN-USERNAME/pihole-image.git
cd pihole-image
```

## Schritt 2: Secrets konfigurieren

```bash
cp secrets.env.example secrets.env
```

Öffne `secrets.env` und setze alle Werte:

```bash
# Pi-hole Admin-Passwort
PIHOLE_PASSWORD=dein-sicheres-passwort

# WLAN
WIFI_SSID=DeinWLANName
WIFI_PASSWORD=dein-wlan-passwort
WIFI_COUNTRY=DE

# SSH Public Key (ganzer Key, z.B.):
SSH_PUBLIC_KEY=ssh-ed25519 AAAA... user@host

# Hostname
PI_HOSTNAME=pihole
```

Den SSH Public Key findest du unter `~/.ssh/id_ed25519.pub` (oder `.pub` deines bevorzugten Keys).

## Schritt 3: Image bauen

```bash
# Scripts ausführbar machen
chmod +x scripts/*.sh

# Build starten (Docker-Methode, empfohlen)
./scripts/build.sh
```

Der Build dauert ca. 30-60 Minuten. Das fertige Image liegt danach in `deploy/`.

## Schritt 4: SD-Karte flashen

```bash
# SD-Karte identifizieren
lsblk

# ACHTUNG: Richtige Device-Bezeichnung verwenden!
./scripts/flash.sh /dev/sdX
```

Das Script schreibt das Image und kopiert `secrets.env` auf die Boot-Partition.

## Schritt 5: Erster Boot

1. SD-Karte in den Pi Zero W einlegen
2. Netzteil anschließen
3. Warte ca. 2-3 Minuten
4. Der First-Boot-Service konfiguriert WiFi, SSH und Pi-hole automatisch
5. Der Pi startet nach der Ersteinrichtung einmal neu

## Schritt 6: Validierung

```bash
./scripts/validate.sh
```

Oder manuell:

```bash
# SSH-Verbindung testen
ssh pi@192.168.178.49

# Pi-hole Status
pihole status

# DNS testen
dig @192.168.178.49 google.com
```

## Schritt 7: Router konfigurieren

Konfiguriere deinen Router so, dass `192.168.178.49` als primärer DNS-Server
für alle Geräte im LAN verwendet wird. Setze den Router selbst (z.B. `192.168.178.1`)
als sekundären DNS – so funktioniert DNS auch wenn der Pi ausfällt.

Für Fritz!Box:
1. Internet → DNS-Server → Lokaler DNS-Server
2. Bevorzugter DNS: `192.168.178.49`
3. Alternativer DNS: `192.168.178.1` (oder ein öffentlicher wie `1.1.1.1`)

# Architektur – Pi-hole Immutable Image

> **Hinweis:** Dieses Dokument wurde mit Unterstützung von KI (Claude/Anthropic) erstellt.

## Übersicht

Dieses Projekt erzeugt ein reproduzierbares Raspberry Pi OS Image, das bei SD-Karten-Ausfall
innerhalb von Minuten neu geflasht werden kann. Alle Konfiguration ist versioniert, Secrets
werden beim ersten Boot einmalig geladen.

## Komponentenübersicht

### Pi-hole v6 (FTL)

Pi-hole FTL (Faster Than Light) ist der zentrale DNS-Server. Ab Version 6 nutzt Pi-hole eine
TOML-basierte Konfiguration (`/etc/pihole/pihole.toml`) statt der bisherigen `setupVars.conf`.

Konfigurationsentscheidungen:
- **Upstream DNS:** Cloudflare (1.1.1.1) + Google (8.8.8.8) als Fallback
- **DNSSEC:** Aktiviert für DNS-Antwort-Validierung
- **Listening Mode:** `all` – notwendig damit das gesamte LAN den Pi als DNS nutzen kann
- **Query-Log Retention:** 1 Tag – reduziert Datenbankgröße und RAM-Verbrauch
- **DHCP:** Deaktiviert – wird vom Router (Fritz!Box) gehandhabt

### Log2RAM

Log2RAM mountet `/var/log` als tmpfs ins RAM. Konfiguration:
- **Größe:** 50 MB (ca. 10% des Pi Zero W RAM)
- **Sync-Intervall:** Stündlich (via systemd Timer Override)
- **journald:** SystemMaxUse auf 20 MB begrenzt
- **zram:** Deaktiviert (spart CPU auf dem ARMv6)

### Watchdog-Stack (3 Ebenen)

1. **Hardware-Watchdog** (`bcm2835_wdt`): Kernel-Modul, 10s Timeout, startet Pi bei Systemhänger neu
2. **systemd WatchdogSec** für `pihole-FTL.service`: FTL meldet sich alle 60s bei systemd
3. **WLAN-Monitor** (`wlan-monitor.service`): Prüft alle 30s die Gateway-Erreichbarkeit,
   startet `wlan0` bei Verbindungsverlust neu, Reboot nach 5 Fehlversuchen

### Health-Check

systemd Timer führt alle 5 Minuten `/usr/local/bin/health-check.sh` aus. Prüft:
- DNS-Auflösung über Pi-hole
- Pi-hole FTL Service-Status
- RAM-Verfügbarkeit (Warnung <20%, Kritisch <10%)
- CPU-Temperatur (Warnung >65°C, Kritisch >75°C)
- SD-Karten I/O-Fehler in dmesg
- Log2RAM Service-Status

Ergebnisse werden in journald und `/var/log/pihole-health.log` geschrieben.
Ein Webhook-Aufruf bei Fehler ist vorbereitet (auskommentiert).

### First-Boot-Service

Einmaliger systemd-Service mit `ConditionPathExists=/boot/firmware/secrets.env`.
Ablauf:
1. `secrets.env` von Boot-Partition lesen
2. Hostname setzen
3. WiFi via NetworkManager konfigurieren (inkl. statische IP)
4. SSH Public Key deployen
5. Pi-hole Admin-Passwort setzen
6. `secrets.env` sicher löschen (`shred`)
7. Service deaktiviert sich selbst
8. Neustart

### Härtung

- **SSH:** Key-Only, kein Passwort-Login, kein Root-Login, MaxAuthTries=3
- **Firewall:** nftables mit Default-Drop Policy, nur 22/tcp, 53/tcp+udp, 80/tcp, ICMP
- **tmpfs:** `/tmp` (30 MB) und `/var/tmp` (10 MB) im RAM
- **Swap:** Deaktiviert (kein dphys-swapfile)
- **Kernel-Tuning:** Dirty Writeback auf 60s, Swappiness=1
- **Unnötige Services deaktiviert:** Bluetooth, Avahi, Triggerhappy
- **HDMI deaktiviert:** Strom sparen im Headless-Betrieb

## Datenfluss

```
Internet
    │
    ▼
┌──────────┐     ┌──────────────────────────────────┐
│  Router   │────▶│  Pi Zero W (192.168.178.49)      │
│ (Gateway) │◀────│                                  │
│ .178.1    │     │  Port 53: Pi-hole FTL (DNS)     │
└──────────┘     │  Port 80: Pi-hole Web UI + API   │
    │             │  Port 22: SSH                     │
    ▼             └──────────────────────────────────┘
 LAN Geräte              │
 (DNS: .178.49)           │ REST API (Port 80/api)
                          ▼
                  [Optional: Home Assistant]
                  (Polling via Pi-hole Integration)
```

## Single Points of Failure

| Komponente | Risiko | Mitigation |
|---|---|---|
| SD-Karte | Hoch | Log2RAM, tmpfs, Swap-off, Kernel-Tuning, reproduzierbares Image |
| WiFi | Mittel | WLAN-Monitor mit Auto-Reconnect + Reboot-Eskalation |
| Pi-hole FTL | Niedrig | systemd Restart + WatchdogSec, Health-Check |
| Stromausfall | Mittel | Hardware-Watchdog, Log2RAM Sync, kein Swap |
| DNS für LAN | Hoch | Router als sekundären DNS konfigurieren (manuell) |

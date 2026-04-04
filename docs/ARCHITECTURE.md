# Architektur – Pi-hole Immutable Image

## Übersicht

Dieses Projekt erzeugt ein reproduzierbares Raspberry Pi OS Image, das bei SD-Karten-Ausfall
innerhalb von Minuten neu geflasht werden kann. Alle Konfiguration ist versioniert, Secrets
werden beim ersten Boot einmalig geladen.

## Komponentenübersicht

### Pi-hole v6 (FTL)

Pi-hole FTL (Faster Than Light) ist der zentrale DNS-Server. Ab Version 6 nutzt Pi-hole eine
TOML-basierte Konfiguration (`/etc/pihole/pihole.toml`) statt der bisherigen `setupVars.conf`.

Konfigurationsentscheidungen:
- **Upstream DNS:** Quad9 gefiltert + DNSSEC (9.9.9.9 + 149.112.112.112)
- **DNSSEC:** Aktiviert für DNS-Antwort-Validierung
- **Listening Mode:** `all` – notwendig damit das gesamte LAN den Pi als DNS nutzen kann
- **domainNeeded:** Single-Label-Namen (z.B. `router`) werden nicht an Upstream weitergeleitet
- **bogusPriv:** Reverse-Lookups für private IPs werden nicht an Upstream weitergeleitet
- **Query-Datenbank deaktiviert** (`maxDBDays = 0`) – reduziert SD-Karten-Schreibzugriffe
- **Conditional Forwarding:** PTR-Anfragen für `192.168.178.0/24` werden an Fritz!Box (`192.168.178.1`) weitergeleitet, damit Hostnamen im LAN aufgelöst werden
- **DHCP:** Deaktiviert – wird vom Router (Fritz!Box) gehandhabt

### Logging

Logs werden direkt auf die SD-Karte geschrieben. Konfiguration:
- **journald:** `Storage=persistent` – Logs in `/var/log/journal`, überleben Reboots
- **journald:** SystemMaxUse auf 100 MB begrenzt (verhindert unkontrolliertes Wachstum)
- **Logrotate:** `pihole-health.log` (500 KB, 2 Kopien) und `pihole/pihole.log` (1 MB, 1 Kopie) werden per logrotate rotiert

### Watchdog-Stack (3 Ebenen)

1. **Hardware-Watchdog** (`bcm2835_wdt`): Kernel-Modul, 10s Timeout, startet Pi bei Systemhänger neu
2. **systemd WatchdogSec** für `pihole-FTL.service`: FTL meldet sich alle 60s bei systemd
3. **WLAN-Monitor** (`wlan-monitor.service`): Prüft alle 30s die Gateway-Erreichbarkeit,
   startet `wlan0` bei Verbindungsverlust neu, Reboot nach 5 Fehlversuchen

**WiFi Power Management deaktiviert:** Der brcmfmac-Treiber des Pi Zero W aktiviert standardmäßig
WiFi Power Saving (PSM). Dabei schläft die Funkeinheit zwischen Beacon-Intervallen – unter Last
oder bei kurzen Beacons können Pakete verloren gehen, was sich als stille Verbindungsabbrüche
äußert. NetworkManager wird daher über `/etc/NetworkManager/conf.d/99-wifi-powersave.conf` mit
`wifi.powersave = 2` (disable) konfiguriert, bevor der WLAN-Monitor zum Einsatz kommt.

### Health-Check

systemd Timer führt alle 5 Minuten `/usr/local/bin/health-check.sh` aus. Prüft:
- DNS-Auflösung über Pi-hole
- Pi-hole FTL Service-Status
- RAM-Verfügbarkeit (Warnung <20%, Kritisch <10%)
- CPU-Temperatur (Warnung >65°C, Kritisch >75°C)
- SD-Karten I/O-Fehler in dmesg

Ergebnisse werden in journald und `/var/log/pihole-health.log` geschrieben.
Ein Webhook-Aufruf bei Fehler ist vorbereitet (auskommentiert).

### First-Boot-Service

Einmaliger systemd-Service mit `ConditionPathExists=/boot/firmware/secrets.env`.
Sucht `secrets.env` zuerst unter `/boot/firmware/` (Bookworm), dann unter `/boot/` (ältere Kernels).
Ablauf:
1. `secrets.env` von Boot-Partition lesen
2. Hostname setzen
3. Benutzer anlegen / umbenennen, Passwort setzen
4. WiFi via NetworkManager konfigurieren (inkl. statische IP)
5. SSH Public Key deployen
6. Pi-hole v6 installieren (unattended), Admin-Passwort setzen, Gravity laden
7. Self-signed ECDSA-TLS-Zertifikat für HTTPS generieren (`pi.hole`, Hostname, IP als SAN)
8. Services aktivieren (wlan-monitor, health-check.timer)
9. `secrets.env` sicher löschen (`shred`)
10. Service deaktiviert sich selbst
11. Neustart

### Härtung

- **SSH:** Key-Only, kein Passwort-Login, kein Root-Login, MaxAuthTries=3
- **Firewall:** nftables mit Default-Drop Policy; erlaubt: 22/tcp (SSH), 53/tcp+udp (DNS), 80/tcp (HTTP), 443/tcp (HTTPS), 5353/udp (mDNS), ICMP/ICMPv6
- **tmpfs:** `/tmp` (30 MB) und `/var/tmp` (10 MB) im RAM
- **Swap:** Deaktiviert (kein dphys-swapfile)
- **Kernel-Tuning:** Dirty Writeback auf 60s, Swappiness=1
- **Services deaktiviert:** Bluetooth, Triggerhappy
- **Avahi aktiv:** mDNS-Advertisement damit Router (Fritz!Box) den Hostnamen `pihole.local` auflösen kann
- **HDMI deaktiviert:** Strom sparen im Headless-Betrieb

## Datenfluss

```
Internet
    │
    ▼
┌──────────┐     ┌──────────────────────────────────┐
│  Router  │────▶│  Pi Zero W (192.168.178.69)      │
│ (Gateway)│◀────│                                  │
│ .178.1   │     │  Port 53: Pi-hole FTL (DNS)      │
└──────────┘     │  Port 80: Pi-hole Web UI + API   │
    │            │  Port 443: HTTPS                 │
    ▼            │  Port 22: SSH                    │
 LAN Geräte      └──────────────────────────────────┘
 (DNS: ...178.69)         │
                          │ REST API (Port 80+443/api)
                          ▼
                  [Optional: Home Assistant]
                  (Polling via Pi-hole Integration)
```

## Single Points of Failure

| Komponente | Risiko | Mitigation |
|---|---|---|
| SD-Karte | Hoch | tmpfs für /tmp, Swap-off, Kernel-Tuning, reproduzierbares Image |
| WiFi | Mittel | WLAN-Monitor mit Auto-Reconnect + Reboot-Eskalation |
| Pi-hole FTL | Niedrig | systemd Restart + WatchdogSec, Health-Check |
| Stromausfall | Mittel | Hardware-Watchdog, kein Swap |
| DNS für LAN | Hoch | Router als sekundären DNS konfigurieren (manuell) |

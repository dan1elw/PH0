# Changelog

Alle relevanten Änderungen an diesem Projekt werden hier dokumentiert.

## [Unreleased]

### Hinzugefügt
- Initiales Repository-Setup
- pi-gen Custom Stage (`stage-pihole`) mit Pi-hole v6 unattended Installation
- Log2RAM Konfiguration (50 MB, stündlicher Sync)
- Hardware-Watchdog (`bcm2835_wdt`, 10s Timeout)
- WLAN-Monitor Service (30s Intervall, Auto-Reconnect, Reboot nach 5 Fehlversuchen)
- Health-Check Timer (5 Min Intervall: DNS, FTL, RAM, Temperatur, SD-Karte, Log2RAM)
- First-Boot-Service (secrets.env einlesen, WiFi, SSH-Key, Pi-hole Passwort, Self-Disable)
- SSH-Härtung (Key-Only, kein Root, MaxAuthTries=3)
- nftables Firewall (Default-Drop, nur SSH/DNS/HTTP erlaubt)
- tmpfs für /tmp und /var/tmp
- Swap deaktiviert
- Kernel-Tuning für SD-Karten-Schutz
- Build-Script (Docker + nativ)
- Flash-Script mit secrets.env Deployment
- Validierungs-Script (16 automatische Tests)
- GitHub Actions Workflow (Tag-basiertes Release + manueller Trigger)
- Vollständige Dokumentation (README, Architektur, Setup, Troubleshooting)
- AI-Generated Disclaimer in README und Docs

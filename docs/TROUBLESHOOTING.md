# Troubleshooting

> **Hinweis:** Dieses Dokument wurde mit Unterstützung von KI (Claude/Anthropic) erstellt.

## Build-Probleme

### Build bricht mit "No space left on device" ab

Der pi-gen Build benötigt ca. 10 GB Speicherplatz. Lösungen:
- `./scripts/build.sh --clean` für einen sauberen Build
- Docker System aufräumen: `docker system prune -a`
- Bei GitHub Actions: `increase-runner-disk-size: true` ist bereits gesetzt

### Build hängt bei "qemu-arm" / ARM-Emulation

Das kann auf manchen Host-Systemen vorkommen:
```bash
# binfmt_misc prüfen
ls /proc/sys/fs/binfmt_misc/qemu-arm

# Falls nicht vorhanden:
sudo apt install qemu-user-static binfmt-support
sudo systemctl restart systemd-binfmt
```

### Docker-Build: "unable to mount"

pi-gen im Docker-Modus benötigt privilegierte Rechte:
```bash
# Falls der Build fehlschlägt, manuell aufräumen:
docker rm -v pigen_work 2>/dev/null
# Dann neu starten:
./scripts/build.sh --clean
```

## Boot-Probleme

### Pi startet, aber ist nicht im Netzwerk erreichbar

1. Monitor anschließen und Boot-Meldungen prüfen
2. Prüfe ob `secrets.env` auf der Boot-Partition liegt:
   ```bash
   # SD-Karte am PC mounten
   ls /media/*/boot*/secrets.env
   ```
3. Prüfe WiFi-Credentials in `secrets.env`
4. Warte mindestens 3 Minuten – der First Boot braucht Zeit

### First-Boot schlägt fehl

Symptom: Pi startet, aber SSH/DNS nicht erreichbar nach 5 Minuten.

1. Monitor + Tastatur anschließen
2. Login: Standardmäßig `pi` ohne Passwort (SSH Key-Only konfiguriert)
3. Logs prüfen: `journalctl -u first-boot.service`
4. Häufigste Ursache: `secrets.env` fehlt oder enthält leere Pflichtfelder

### SSH-Verbindung wird abgelehnt

```bash
# Prüfe ob SSH läuft
nmap -p 22 192.168.178.69

# Key-Probleme:
ssh -v pi@192.168.178.69  # Verbose für Debug-Output
```

Falls Passwort-Authentifizierung benötigt wird (Notfall):
```bash
# Auf dem Pi (via Monitor):
sudo sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
sudo systemctl restart sshd
```

## DNS-Probleme

### DNS-Auflösung funktioniert nicht

```bash
# Auf dem Pi:
pihole status
dig @127.0.0.1 google.com

# Upstream-DNS testen:
dig @1.1.1.1 google.com

# FTL-Log prüfen:
pihole -t  # Live-Log
```

### Pi-hole blockiert zu viel / zu wenig

```bash
# Blocklisten aktualisieren:
pihole -g

# Domain whitelisten:
pihole -w example.com

# Domain blacklisten:
pihole -b tracking.example.com

# Query-Log prüfen:
# Web UI: http://192.168.178.69/admin → Query Log
```

### Gravity-Update schlägt fehl

```bash
# DNS prüfen (Pi braucht selbst DNS für Gravity-Downloads):
dig @1.1.1.1 raw.githubusercontent.com

# Manuell neu laden:
pihole -g --force
```

## Service-Probleme

### pihole-FTL startet nicht

```bash
# Status prüfen
systemctl status pihole-FTL
journalctl -u pihole-FTL --no-pager -n 50

# Port-Konflikt prüfen
ss -tlnp | grep :53
ss -tlnp | grep :80

# Konfiguration validieren
pihole-FTL --check

# Neustart erzwingen
systemctl restart pihole-FTL
```

### Log2RAM ist nicht aktiv

```bash
systemctl status log2ram
df -h /var/log

# Falls /var/log zu groß ist:
journalctl --vacuum-size=16M
sudo find /var/log/ -name '*.gz' -delete
sudo reboot
```

### Watchdog löst unerwartete Neustarts aus

```bash
# Watchdog-Logs prüfen
journalctl -u watchdog --no-pager -n 50

# Temperatur prüfen
vcgencmd measure_temp

# Last prüfen
uptime

# Watchdog temporär deaktivieren:
sudo systemctl stop watchdog
```

## SD-Karten-Probleme

### I/O-Fehler in dmesg

```bash
dmesg | grep -i "i/o error\|mmc\|mmcblk"
```

Falls Fehler auftreten:
1. **Sofort:** Daten sichern soweit möglich
2. Neues Image auf neue SD-Karte flashen (`./scripts/flash.sh`)
3. Alte SD-Karte entsorgen – I/O-Fehler sind ein Zeichen für fortgeschrittene Degradation

### Read-Only Dateisystem

Symptom: Befehle schlagen fehl mit "Read-only file system"

```bash
# Dateisystem-Check
sudo fsck -f /dev/mmcblk0p2

# Remount read-write (temporär)
sudo mount -o remount,rw /
```

Dies ist oft ein Zeichen für SD-Karten-Probleme. Neues Image flashen empfohlen.

## Netzwerk-Probleme

### WLAN-Verbindung instabil

```bash
# WLAN-Monitor Logs prüfen
journalctl -u wlan-monitor --no-pager -n 50

# Signal-Stärke prüfen
iwconfig wlan0

# NetworkManager Status
nmcli device status
nmcli connection show
```

### Statische IP stimmt nicht

```bash
# Aktuelle IP prüfen
ip addr show wlan0

# NetworkManager-Verbindung prüfen
nmcli connection show pihole-wifi

# IP manuell korrigieren
nmcli connection modify pihole-wifi ipv4.addresses "192.168.178.69/24"
nmcli connection up pihole-wifi
```

---
name: Release Checklist
about: Checklist for preparing and verifying a new release
labels: release
---

## Release v<!-- version here -->

### Automated (CI)
- [ ] All CI checks green on `main`
- [ ] Lint workflow (`lint-shell.yml`) passes
- [ ] Build workflow (`build-image.yml`) passes

### Manual – Build
- [ ] Image built locally: `./scripts/build.sh --clean`
- [ ] Image present in `deploy/*.img.xz`

### Manual – Hardware
- [ ] Flashed to SD card: `./scripts/flash.sh /dev/sdX`
- [ ] `secrets.env` copied to boot partition (confirmed by flash.sh)
- [ ] Pi boots and reaches network within 5 minutes
- [ ] First-boot service completes without errors

```bash
ssh daniel@192.168.178.69 'sudo cat /var/log/first-boot.log'
```

- [ ] `./scripts/validate.sh` passes all checks
- [ ] Validation report TXT uploaded to this ticket.

### Manual – Smoke Test
- [ ] Pi-hole web UI reachable via HTTPS (`https://192.168.178.69/admin`)
- [ ] DNS resolution works: `dig @192.168.178.69 google.com`
- [ ] A known ad domain is blocked: `dig @192.168.178.69 doubleclick.net`
- [ ] `systemctl status pihole-FTL` → active (running)
- [ ] `systemctl status wlan-monitor` → active (running)
- [ ] `systemctl status health-check.timer` → active (waiting)
- [ ] nftables firewall active: `sudo nft list ruleset`

### Release
- [ ] `git tag vX.Y.Z && git push --tags`
- [ ] GitHub Release published with image attached

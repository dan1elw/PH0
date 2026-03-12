---
name: pi-gen-image
description: pi-gen image builder knowledge. Use when working on stage-pihole/ files, config, build.sh, or GitHub Actions workflow. Covers chroot constraints, stage structure, and bookworm-specific details.
---

# pi-gen Image Builder Reference

## Branch Selection

IMPORTANT: Always use the **bookworm** branch of pi-gen. The master branch moved to Trixie (Debian 13) in August 2025 and does NOT support 32-bit armhf builds needed for Pi Zero W.

```bash
git clone --depth 1 --branch bookworm https://github.com/RPi-Distro/pi-gen.git
```

## Stage Structure

A custom stage directory must follow this layout:

```
stage-pihole/
├── prerun.sh                    # Standard: copy_previous if ROOTFS_DIR missing
├── EXPORT_IMAGE                 # Contains IMG_SUFFIX="-pihole"
├── 00-install-packages/
│   ├── 00-packages              # One APT package per line
│   └── 01-run.sh               # Preparation (users, dirs) — NO installers
├── 01-configure/
│   ├── files/                   # Static config files to deploy
│   └── 01-run.sh               # install -v -m to deploy files
├── 02-first-boot/
│   ├── files/
│   │   ├── first-boot.sh       # Runtime installer script
│   │   └── first-boot.service  # systemd oneshot unit
│   └── 01-run.sh               # Deploy + symlink-enable the service
└── 03-hardening/
    └── 01-run.sh               # SSH, firewall, tmpfs, kernel tuning
```

## Chroot Environment Constraints

Inside pi-gen stage scripts, you are operating in a **cross-architecture chroot**:

| Works                          | Does NOT work                    |
|-------------------------------|----------------------------------|
| File operations (cp, mkdir)    | `systemctl` commands             |
| `on_chroot` for user mgmt     | Network access (curl, wget, apt) |
| `install -v -m` for files     | Starting/stopping services       |
| Symlink creation               | DNS resolution                   |
| Writing to `${ROOTFS_DIR}/`   | Mounting filesystems             |
| `sed`, `cat`, `grep` on files | Running Pi-hole installer        |

## Key Variables

- `${ROOTFS_DIR}` — Root of the target filesystem being built
- `${STAGE_DIR}` — Path to the current stage directory
- `${ROOTFS_DIR}/boot/firmware/` — Boot partition (Bookworm path)
- `${ROOTFS_DIR}/boot/` — Boot partition (legacy path, check both)

## File Deployment Pattern

```bash
# Deploy a script (executable)
install -v -m 755 \
    "${STAGE_DIR}/02-first-boot/files/first-boot.sh" \
    "${ROOTFS_DIR}/usr/local/bin/first-boot.sh"

# Deploy a config file (read-only)
install -v -m 644 \
    "${STAGE_DIR}/01-configure/files/pihole.toml" \
    "${ROOTFS_DIR}/etc/pihole/pihole.toml"

# Deploy a systemd unit
install -v -m 644 \
    "${STAGE_DIR}/01-configure/files/my.service" \
    "${ROOTFS_DIR}/etc/systemd/system/my.service"
```

## Service Activation Pattern

```bash
# Enable via symlink (the ONLY way in chroot)
mkdir -p "${ROOTFS_DIR}/etc/systemd/system/multi-user.target.wants"
ln -sf /etc/systemd/system/my.service \
    "${ROOTFS_DIR}/etc/systemd/system/multi-user.target.wants/my.service"

# For timers:
mkdir -p "${ROOTFS_DIR}/etc/systemd/system/timers.target.wants"
ln -sf /etc/systemd/system/my.timer \
    "${ROOTFS_DIR}/etc/systemd/system/timers.target.wants/my.timer"
```

## Docker Build Gotchas

- Stage directory MUST be copied with `cp -a`, not symlinked — Docker cannot follow symlinks outside build context
- DNS inside Docker container: systemd-resolved (127.0.0.53) is not available. Pass `--dns 8.8.8.8 --dns 8.8.4.4` via `PIGEN_DOCKER_OPTS`
- Remove stale `pigen_work` container before rebuild: `docker rm -v pigen_work`

## GitHub Actions Build

The CI uses **native build** (not Docker, not usimd/pi-gen-action) because:
- bookworm pi-gen uses an i386 Docker image
- amd64 GitHub runners cannot run i386 containers reliably
- Native build requires: `qemu-user-static`, `debootstrap`, `binfmt-support`

## config File Reference

Key settings for Pi Zero W builds:
```
IMG_NAME=pihole-zerow
RELEASE=bookworm
TARGET_HOSTNAME=pihole
FIRST_USER_NAME=pi
LOCALE_DEFAULT=de_DE.UTF-8
TIMEZONE_DEFAULT=Europe/Berlin
ENABLE_SSH=1
STAGE_LIST="stage0 stage1 stage2 stage-pihole"
DEPLOY_COMPRESSION=xz
```

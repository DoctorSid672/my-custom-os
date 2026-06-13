# Custom Debian ISO Builder

Build your own bootable Linux distribution based on Debian 12 (Bookworm) with the XFCE desktop — lightweight, fast, and fully customizable.

## Requirements

- A **Debian 12** or **Ubuntu 22.04+** host machine (physical or VM)
- At least **20 GB** of free disk space
- Internet connection (packages are downloaded during build)
- Root / sudo access

> **Note:** This cannot be run inside a standard container or Replit itself — it must be on a real Debian/Ubuntu machine. You can use a VPS (DigitalOcean, Hetzner, Vultr) if you don't have a local Debian machine.

---

## Quick Start

```bash
# 1. Make scripts executable
chmod +x configure.sh build-iso.sh

# 2. Run the interactive configurator
./configure.sh

# 3. Build the ISO (takes 15–40 minutes)
sudo ./build-iso.sh
```

The finished ISO will appear in this folder as `<your-os-slug>.iso`.

---

## What `configure.sh` lets you set

| Option | Description |
|---|---|
| **OS Name** | The name shown in GRUB, login screen, and `uname` |
| **Wallpaper URL** | Direct link to a `.jpg` / `.png` image for the desktop & login screen |
| **Pre-installed apps** | Pick from a numbered menu: browsers, office, media, dev tools |

Settings are saved to `.build-config` and read by `build-iso.sh`.

---

## Re-configuring

Just run `./configure.sh` again — it overwrites `.build-config` with your new choices.

---

## Flashing to USB

```bash
# Replace /dev/sdX with your USB drive (check with lsblk)
sudo dd if=mylinux.iso of=/dev/sdX bs=4M status=progress && sync
```

Or use **Balena Etcher** or **Ventoy** for a GUI method.

---

## Desktop Environment

XFCE is used as the desktop. It is:
- Very lightweight (~300 MB RAM idle)
- Fast on older hardware
- Fully themeable

---

## Build Log

A full build log is saved to `<os-slug>-build.log` in this directory.

#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  Custom Debian ISO Builder
#  Must be run as root (sudo ./build-iso.sh) on a Debian or Ubuntu host.
#  Run configure.sh first to generate .build-config.
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/.build-config"
BUILD_DIR="${SCRIPT_DIR}/build"

# ── Preflight checks ──────────────────────────────────────────────────────────
if [[ "$EUID" -ne 0 ]]; then
  echo "❌  This script must be run as root: sudo ./build-iso.sh"
  exit 1
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "❌  No config found. Run ./configure.sh first."
  exit 1
fi

# shellcheck source=/dev/null
source "$CONFIG_FILE"

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║        Custom Debian ISO Builder             ║"
echo "╚══════════════════════════════════════════════╝"
echo ""
echo "  OS Name  : ${OS_NAME}"
echo "  Slug     : ${OS_SLUG}"
echo "  Wallpaper: ${WALLPAPER_URL:-<default>}"
echo "  Packages : ${PACKAGES:-<none>}"
echo ""

# ── Install live-build if missing ─────────────────────────────────────────────
if ! command -v lb &>/dev/null; then
  echo "→ Installing live-build..."
  apt-get update -qq
  apt-get install -y live-build curl wget squashfs-tools xorriso isolinux
fi

# ── Prepare clean build directory ────────────────────────────────────────────
echo "→ Preparing build directory: ${BUILD_DIR}"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# ── Configure live-build ──────────────────────────────────────────────────────
echo "→ Running lb config..."
lb config \
  --distribution bookworm \
  --archive-areas "main contrib non-free non-free-firmware" \
  --debian-installer live \
  --debian-installer-gui true \
  --bootappend-live "boot=live components quiet splash" \
  --iso-application "${OS_NAME}" \
  --iso-preparer "${OS_NAME} Build System" \
  --iso-publisher "${OS_NAME}" \
  --iso-volume "${OS_SLUG}" \
  --image-name "${OS_SLUG}" \
  --binary-images iso-hybrid \
  --checksums sha256 \
  --compression xz

# ── Desktop environment — XFCE (lightweight) ──────────────────────────────────
echo "→ Writing package lists..."

cat > config/package-lists/desktop.list.chroot <<PKGEOF
# Desktop environment
task-xfce-desktop
xfce4
xfce4-goodies
xfce4-terminal
lightdm
lightdm-gtk-greeter
lightdm-gtk-greeter-settings

# Fonts & themes
fonts-noto
fonts-noto-color-emoji
papirus-icon-theme

# System essentials
network-manager
network-manager-gnome
pulseaudio
pavucontrol
thunar
thunar-archive-plugin
zip
unzip
wget
curl
ca-certificates
sudo
PKGEOF

# ── User-selected packages ─────────────────────────────────────────────────────
if [[ -n "${PACKAGES:-}" ]]; then
  echo ""                                         >> config/package-lists/desktop.list.chroot
  echo "# User-selected packages"                 >> config/package-lists/desktop.list.chroot
  for pkg in $PACKAGES; do
    echo "$pkg"                                   >> config/package-lists/desktop.list.chroot
  done
fi

# Discord is not in Debian repos — download the official .deb and install via a hook
if echo "${PACKAGES:-}" | grep -q "discord"; then
  mkdir -p config/hooks/normal
  cat > config/hooks/normal/1001-discord.hook.chroot <<'HOOKEOF'
#!/bin/bash
set -e
echo "→ Downloading Discord..."
TMPFILE=$(mktemp /tmp/discord-XXXXXX.deb)
wget -q --show-progress \
  "https://discord.com/api/download?platform=linux&format=deb" \
  -O "$TMPFILE"
echo "→ Installing Discord..."
dpkg -i "$TMPFILE" || true
apt-get install -f -y
rm -f "$TMPFILE"
echo "✅ Discord installed."
HOOKEOF
  chmod +x config/hooks/normal/1001-discord.hook.chroot
  # Remove 'discord' from the apt package list — it's handled by the hook above
  PACKAGES=$(echo "${PACKAGES}" | tr ' ' '\n' | grep -v '^discord$' | tr '\n' ' ')
fi

# VSCodium needs a separate apt source
if echo "${PACKAGES:-}" | grep -q "codium"; then
  mkdir -p config/archives
  cat > config/archives/vscodium.list.chroot <<SRCEOF
deb [ signed-by=/usr/share/keyrings/vscodium-archive-keyring.gpg ] https://paulcarroty.gitlab.io/vscodium-distrib/debs vscodium main
SRCEOF
  mkdir -p config/hooks/normal
  cat > config/hooks/normal/1000-vscodium-key.hook.chroot <<HOOKEOF
#!/bin/bash
wget -qO - https://gitlab.com/paulcarroty/vscodium-distrib/raw/master/pub.gpg \
  | gpg --dearmor \
  | tee /usr/share/keyrings/vscodium-archive-keyring.gpg > /dev/null
HOOKEOF
  chmod +x config/hooks/normal/1000-vscodium-key.hook.chroot
fi

# ── Branding: os-release + hostname ──────────────────────────────────────────
echo "→ Writing OS branding and hostname..."
mkdir -p config/includes.chroot/etc

cat > config/includes.chroot/etc/os-release <<OSEOF
PRETTY_NAME="${OS_NAME}"
NAME="${OS_NAME}"
ID=${OS_SLUG}
ID_LIKE=debian
HOME_URL="https://www.debian.org/"
SUPPORT_URL="https://www.debian.org/support"
BUG_REPORT_URL="https://bugs.debian.org/"
VERSION="1.0"
VERSION_ID="1.0"
OSEOF

# System hostname (shows in terminal prompt and network)
echo "${OS_SLUG}" > config/includes.chroot/etc/hostname

# /etc/hosts must resolve the hostname to localhost
cat > config/includes.chroot/etc/hosts <<HOSTSEOF
127.0.0.1   localhost
127.0.1.1   ${OS_SLUG}
::1         localhost ip6-localhost ip6-loopback
ff02::1     ip6-allnodes
ff02::2     ip6-allrouters
HOSTSEOF

# ── Wallpaper ─────────────────────────────────────────────────────────────────
WALLPAPER_DEST="config/includes.chroot/usr/share/backgrounds/${OS_SLUG}-wallpaper.jpg"
mkdir -p "$(dirname "$WALLPAPER_DEST")"

if [[ -n "${WALLPAPER_URL:-}" ]]; then
  echo "→ Downloading wallpaper from: ${WALLPAPER_URL}"
  if wget -q --show-progress -O "$WALLPAPER_DEST" "${WALLPAPER_URL}"; then
    echo "  ✅ Wallpaper downloaded."
  else
    echo "  ⚠  Download failed. Falling back to bundled wallpaper."
    WALLPAPER_URL=""
  fi
fi

if [[ -z "${WALLPAPER_URL:-}" ]]; then
  BUNDLED="${SCRIPT_DIR}/config/includes.chroot/usr/share/backgrounds/default-wallpaper.jpg"
  if [[ -f "$BUNDLED" ]]; then
    cp "$BUNDLED" "$WALLPAPER_DEST"
    echo "  ✅ Bundled wallpaper applied."
  else
    echo "  ⚠  No wallpaper found. Desktop will use the XFCE default."
  fi
fi

# ── XFCE wallpaper hook ───────────────────────────────────────────────────────
mkdir -p config/hooks/live
cat > config/hooks/live/9999-set-wallpaper.hook.chroot <<HOOKEOF
#!/bin/bash
set -e
WALLPAPER_FILE="/usr/share/backgrounds/${OS_SLUG}-wallpaper.jpg"

if [ -f "\$WALLPAPER_FILE" ]; then
  # Set for all future users via /etc/skel
  mkdir -p /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml
  cat > /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml <<XMLEOF
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-desktop" version="1.0">
  <property name="backdrop" type="empty">
    <property name="screen0" type="empty">
      <property name="monitor0" type="empty">
        <property name="workspace0" type="empty">
          <property name="last-image" type="string" value="\$WALLPAPER_FILE"/>
          <property name="image-style" type="int" value="5"/>
        </property>
      </property>
    </property>
  </property>
</channel>
XMLEOF
fi
HOOKEOF
chmod +x config/hooks/live/9999-set-wallpaper.hook.chroot

# ── LightDM greeter branding ──────────────────────────────────────────────────
mkdir -p config/includes.chroot/etc/lightdm
cat > config/includes.chroot/etc/lightdm/lightdm-gtk-greeter.conf <<LDEOF
[greeter]
theme-name=Adwaita-dark
icon-theme-name=Papirus
font-name=Noto Sans 11
xft-antialias=true
background=/usr/share/backgrounds/${OS_SLUG}-wallpaper.jpg
LDEOF

# ── GRUB splash label ─────────────────────────────────────────────────────────
mkdir -p config/bootloaders/grub-pc
cat > config/bootloaders/grub-pc/config.cfg <<GRUBEOF
if background_color 44,0,30,0; then
  clear
fi
set menu_color_normal=white/black
set menu_color_highlight=black/light-gray
GRUBEOF

# ── Build the ISO ─────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Starting live-build. This takes 15–40 min"
echo "  depending on your internet speed."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

lb build 2>&1 | tee "${SCRIPT_DIR}/${OS_SLUG}-build.log"

# ── Rename output ISO ─────────────────────────────────────────────────────────
FINAL_ISO="${SCRIPT_DIR}/${OS_SLUG}.iso"
if ls "${BUILD_DIR}"/*.iso 1>/dev/null 2>&1; then
  mv "${BUILD_DIR}"/*.iso "$FINAL_ISO"
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  ✅  BUILD COMPLETE"
  echo ""
  echo "  ISO : ${FINAL_ISO}"
  echo "  Size: $(du -sh "$FINAL_ISO" | cut -f1)"
  echo ""
  echo "  Flash to USB with:"
  echo "  sudo dd if=${FINAL_ISO} of=/dev/sdX bs=4M status=progress && sync"
  echo ""
  echo "  Or use Balena Etcher / Ventoy for a GUI method."
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
else
  echo "❌  Build failed. Check ${OS_SLUG}-build.log for details."
  exit 1
fi

#!/usr/bin/env bash
set -euo pipefail

# install.sh
# Unified script for Arch Linux installation with Hyprland + Waybar + Alacritty + Brave.
# Supports BIOS legacy, single partition setup.
# Assumes manual partitioning, formatting, and mounting of /dev/sda1 to /mnt.
# Assumes repo cloned manually to /home/prueba-arch inside chroot (visible as /mnt/home/prueba-arch from live).
# Detects CPU for drivers/microcode (Intel i3-2330M or AMD Ryzen 7 5700G compatible).
# For Intel (laptop with WiFi): Includes WiFi firmware via linux-firmware (iwlwifi typically covered).
# For AMD (desktop PC): No WiFi assumed.
# Run from live ISO after manual steps: bash /mnt/home/prueba-arch/scripts/install.sh
# After reboot, login as user: bash /home/prueba-arch/scripts/install.sh

# Constants and defaults
REPO_DIR="/home/prueba-arch"
TARGET_MNT="/mnt"
DEFAULT_LOCALE="en_US.UTF-8"  # Additional: es_CO.UTF-8 will be enabled too
DEFAULT_KEYMAP="us"
DEFAULT_HOSTNAME="jufe"
DEFAULT_USERNAME="jufedev"

# Functions
msg() { printf "\e[1;32m[+]\e[0m %s\n" "$*"; }
warn() { printf "\e[1;33m[-]\e[0m %s\n" "$*"; }
err() { printf "\e[1;31m[!]\e[0m %s\n" "$*"; }

# Detect environment
in_live=false
if [ -d /run/archiso ]; then
  in_live=true
fi

systemd_running=false
if ps -p 1 -o comm= 2>/dev/null | grep -q systemd; then
  systemd_running=true
fi

# Phase 1: Run from live ISO (assumes /mnt mounted and repo cloned)
if $in_live; then
  msg "Detected live ISO environment. Starting Phase 1: Base installation (post-manual mount)."

  if [[ $EUID -ne 0 ]]; then
    err "Must run as root in live ISO."
    exit 1
  fi

  # Check if /mnt is mounted
  if ! mountpoint -q "${TARGET_MNT}"; then
    err "/mnt is not mounted. Mount your root partition to /mnt and run again."
    exit 1
  fi

  # Check if repo exists
  if [[ ! -d "${TARGET_MNT}${REPO_DIR}" ]]; then
    err "Repo not found at ${TARGET_MNT}${REPO_DIR}. Clone it manually inside chroot first."
    exit 1
  fi

  # Enable multilib in live pacman.conf
  msg "Enabling multilib repository..."
  sed -i "/\[multilib\]/,/Include/"'s/^#//' /etc/pacman.conf
  pacman -Syy --noconfirm  # Use -Syy to refresh without upgrading to avoid filling live ISO RAM

  # Prompt for inputs
  read -rp "Hostname [${DEFAULT_HOSTNAME}]: " HOSTNAME
  HOSTNAME=${HOSTNAME:-$DEFAULT_HOSTNAME}

  read -rp "Username [${DEFAULT_USERNAME}]: " USERNAME
  USERNAME=${USERNAME:-$DEFAULT_USERNAME}

  read -s -rp "Root password: " ROOT_PASS
  echo
  read -s -rp "User password for ${USERNAME}: " USER_PASS
  echo

  # Detect CPU vendor for microcode and drivers
  CPU_VENDOR=$(grep -m1 'vendor_id' /proc/cpuinfo | awk '{print $3}' || echo "unknown")
  MICROCODE_PKG=""
  DRIVER_PKGS=""
  if [[ "${CPU_VENDOR,,}" == *"intel"* ]]; then
    msg "Detected Intel CPU (i3-2330M laptop with WiFi compatible)."
    MICROCODE_PKG="intel-ucode"
    DRIVER_PKGS="mesa vulkan-intel lib32-mesa lib32-vulkan-intel xf86-video-intel libva-intel-driver libva-utils"  # WiFi via linux-firmware
  elif [[ "${CPU_VENDOR,,}" == *"authenticamd"* || "${CPU_VENDOR,,}" == *"amd"* ]]; then
    msg "Detected AMD CPU (Ryzen 7 5700G desktop compatible)."
    MICROCODE_PKG="amd-ucode"
    DRIVER_PKGS="mesa vulkan-radeon lib32-mesa lib32-vulkan-radeon libva-mesa-driver"  # Removed amdvlk as it's AUR-only
  else
    warn "CPU vendor unknown. Skipping specific drivers/microcode. Install manually later."
  fi

  # Pacstrap base system (git already installed manually)
  msg "Installing base packages..."
  pacstrap "${TARGET_MNT}" base linux linux-firmware vim sudo networkmanager grub ${MICROCODE_PKG} ${DRIVER_PKGS}

  # Generate fstab
  msg "Generating fstab..."
  genfstab -U "${TARGET_MNT}" >> "${TARGET_MNT}/etc/fstab"

  # Temporary password file (secure)
  PWFILE="${TARGET_MNT}/root/pwfile"
  umask 077
  printf '%s\n' "root:${ROOT_PASS}" "${USERNAME}:${USER_PASS}" > "${PWFILE}"
  chmod 600 "${PWFILE}"
  unset ROOT_PASS USER_PASS

  # Chroot and configure
  msg "Entering chroot for configuration..."
  arch-chroot "${TARGET_MNT}" /bin/bash -e <<EOF
set -e

# Timezone
ln -sf /usr/share/zoneinfo/America/Bogota /etc/localtime
hwclock --systohc

# Locale
echo "LANG=${DEFAULT_LOCALE}" > /etc/locale.conf
sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
sed -i 's/^#es_CO.UTF-8 UTF-8/es_CO.UTF-8 UTF-8/' /etc/locale.gen
locale-gen

# Keymap
echo "KEYMAP=${DEFAULT_KEYMAP}" > /etc/vconsole.conf

# Hostname and hosts
echo "${HOSTNAME}" > /etc/hostname
cat <<HOSTS > /etc/hosts
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}
HOSTS

# Create user and set passwords
useradd -m -G wheel -s /bin/bash ${USERNAME}
chpasswd < /root/pwfile
rm -f /root/pwfile

# Sudoers: enable wheel
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# Install base-devel (for AUR later)
pacman -S --noconfirm base-devel git

# Enable multilib
sed -i "/\[multilib\]/,/Include/"'s/^#//' /etc/pacman.conf
pacman -Syu --noconfirm

# GRUB (assume /dev/sda)
grub-install --target=i386-pc /dev/sda
grub-mkconfig -o /boot/grub/grub.cfg

# Network
systemctl enable NetworkManager

# Regenerate initramfs
mkinitcpio -P
EOF

  if [[ ! -f /etc/vconsole.conf ]]; then
    echo "KEYMAP=${DEFAULT_KEYMAP}" > /etc/vconsole.conf
  fi

  # Unmount and reboot
  msg "Phase 1 complete. Unmounting..."
  msg "Unmount /mnt, Remove ISO and reboot. After login as ${USERNAME}, run: bash ${REPO_DIR}/scripts/phase2-install.sh"
  exit 0
fi

err "Unknown environment. Run from Arch live ISO or installed system."
exit 1
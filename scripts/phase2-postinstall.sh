#!/usr/bin/env bash
set -euo pipefail

# install_phase2.sh
# Phase 2 script for desktop setup after base Arch installation.
# Run from installed system after reboot and login: bash /home/prueba-arch/scripts/install_phase2.sh

# Constants and defaults
REPO_DIR="/home/prueba-arch"

# Functions
msg() { printf "\e[1;32m[+]\e[0m %s\n" "$*"; }
warn() { printf "\e[1;33m[-]\e[0m %s\n" "$*"; }
err() { printf "\e[1;31m[!]\e[0m %s\n" "$*"; }

# Detect environment
systemd_running=false
if ps -p 1 -o comm= 2>/dev/null | grep -q systemd; then
  systemd_running=true
fi

if ! $systemd_running; then
  err "This script must be run from the installed system."
  exit 1
fi

msg "Detected installed system. Starting Phase 2: Desktop setup."

# Update system
msg "Updating system..."
sudo pacman -Syu --noconfirm

# Install SDDM
msg "Installing SDDM..."
sudo pacman -S --noconfirm sddm
sudo systemctl enable --now sddm

# Detect CPU again for any additional drivers (though installed in phase1)
CPU_VENDOR=$(grep -m1 'vendor_id' /proc/cpuinfo | awk '{print $3}' || echo "unknown")
if [[ "${CPU_VENDOR,,}" == *"intel"* ]]; then
  sudo pacman -S --noconfirm vulkan-intel lib32-vulkan-intel
elif [[ "${CPU_VENDOR,,}" == *"authenticamd"* || "${CPU_VENDOR,,}" == *"amd"* ]]; then
  sudo pacman -S --noconfirm vulkan-radeon lib32-vulkan-radeon
fi

# Install AUR helper (yay)
msg "Installing yay AUR helper..."
if ! command -v yay >/dev/null 2>&1; then
  git clone https://aur.archlinux.org/yay.git /tmp/yay
  cd /tmp/yay
  makepkg -si --noconfirm
  cd -
  rm -rf /tmp/yay
fi

# Install Hyprland and related (use AUR git if preferred, but repo for stability)
msg "Installing Hyprland and dependencies..."
sudo pacman -S --noconfirm hyprland waybar alacritty rofi dunst swaybg swaylock swayidle wl-clipboard \
  grim slurp swappy polkit-kde-agent xdg-desktop-portal-hyprland ttf-font-awesome noto-fonts-emoji \
  qt5-wayland qt6-wayland ttf-cascadia-code

# If git version needed: yay -S --noconfirm hyprland-git waybar-hyprland-git

# SDDM wayland config
msg "Configuring SDDM for Wayland..."
sudo mkdir -p /etc/sddm.conf.d
sudo tee /etc/sddm.conf.d/wayland.conf <<SDDM >/dev/null
[General]
DisplayServer=wayland
GreeterEnvironment=QT_WAYLAND_SHELL_INTEGRATION=layer-shell
SDDM
sudo chown root:root /etc/sddm.conf.d/wayland.conf

# Audio (Pipewire)
msg "Installing Pipewire..."
# Handle jack2 conflict if present (common in fresh installs)
if pacman -Qi jack2 &> /dev/null; then
  msg "Removing conflicting jack2 package..."
  sudo pacman -R --noconfirm jack2
fi
sudo pacman -S --noconfirm pipewire pipewire-alsa pipewire-pulse pipewire-jack wireplumber
systemctl --user enable --now pipewire pipewire-pulse wireplumber

# Bluetooth
msg "Installing Bluetooth..."
sudo pacman -S --noconfirm bluez bluez-utils blueman
sudo systemctl enable --now bluetooth

# Utilities
msg "Installing utilities..."
sudo pacman -S --noconfirm pamixer playerctl brightnessctl

# Copy configs
if [[ -d "${REPO_DIR}/configs/wayland" ]]; then
  msg "Copying configs to ~/.config..."
  mkdir -p ~/.config
  cp -r "${REPO_DIR}/configs/wayland/"* ~/.config/
else
  warn "Configs not found in ${REPO_DIR}/configs/wayland."
fi

# Install Brave
msg "Installing Brave..."
if pacman -Si brave-browser >/dev/null 2>&1; then
  sudo pacman -S --noconfirm brave-browser
else
  yay -S --noconfirm brave-bin
fi

# Add user to groups
required_groups=(wheel audio video input)
for g in "${required_groups[@]}"; do
  sudo usermod -aG "$g" "$USER"
done

msg "Phase 2 complete. Reboot to start Hyprland via SDDM."
exit 0
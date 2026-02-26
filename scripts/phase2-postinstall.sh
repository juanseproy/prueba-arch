#!/usr/bin/env bash
set -euo pipefail

# install_phase2.sha
# Phase 2 script for desktop setup after base Arch installation.
# Run from installed system after reboot and login:
# bash /home/prueba-arch/scripts/install_phase2.sh

# Constants and defaults
REPO_DIR="/home/prueba-arch"

# Functions (mensajes)
msg()  { printf "\e[1;32m[+]\e[0m %s\n" "$*"; }
warn() { printf "\e[1;33m[-]\e[0m %s\n" "$*"; }
err()  { printf "\e[1;31m[!]\e[0m %s\n" "$*"; }

# Detect environment
systemd_running=false
if ps -p 1 -o comm= 2>/dev/null | grep -q systemd; then
  systemd_running=true
fi

if ! $systemd_running; then
  err "Este script debe correrse desde el sistema instalado (no desde el instalador en vivo)."
  exit 1
fi

msg "Detected installed system. Starting Phase 2: Desktop setup."

# Detect real user (cuando se ejecuta con sudo)
REAL_USER="${SUDO_USER:-$(logname 2>/dev/null || echo "$USER")}"

msg "Usuario detectado: $REAL_USER"

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
  msg "Detected Intel CPU: instalando drivers Vulkan Intel..."
  sudo pacman -S --noconfirm vulkan-intel lib32-vulkan-intel || warn "Fallo instalando vulkan-intel"
elif [[ "${CPU_VENDOR,,}" == *"authenticamd"* || "${CPU_VENDOR,,}" == *"amd"* ]]; then
  msg "Detected AMD CPU: instalando drivers Vulkan Radeon..."
  sudo pacman -S --noconfirm vulkan-radeon lib32-vulkan-radeon || warn "Fallo instalando vulkan-radeon"
fi

# Install AUR helper (yay)
msg "Installing yay AUR helper..."
if ! command -v yay >/dev/null 2>&1; then
  # asegúrate de tener base-devel instalado antes de makepkg (normalmente ya lo tienes)
  git clone https://aur.archlinux.org/yay.git /tmp/yay
  cd /tmp/yay
  makepkg -si --noconfirm
  cd -
  rm -rf /tmp/yay
else
  msg "yay ya instalado."
fi

# Audio (PipeWire) - manejo de conflicto con jack2 y dependencia waybar
msg "Instalando PipeWire (manejo de posibles conflictos con jack2)..."

# Si jack2 está instalado hay que reemplazarlo por pipewire-jack.
if pacman -Qi jack2 >/dev/null 2>&1; then
  warn "Se detectó jack2 instalado en el sistema."

  # Si waybar depende de jack2, lo removemos temporalmente para permitir el reemplazo.
  if pacman -Qi waybar >/dev/null 2>&1; then
    warn "Se detectó waybar instalado y que puede depender de JACK. Lo removeré temporalmente para evitar conflictos."
    sudo pacman -Rns --noconfirm waybar || {
      err "Fallo al remover waybar. Revisa manualmente antes de continuar."
      exit 1
    }
  fi

  # Remover jack2 (y dependencias huérfanas)
  msg "Removiendo jack2..."
  sudo pacman -Rns --noconfirm jack2 || {
    err "Fallo al remover jack2. Cancelo."
    exit 1
  }
fi

# Instalar pipewire y la compatibilidad JACK
msg "Instalando paquetes de PipeWire y compatibilidad JACK..."
sudo pacman -S --noconfirm pipewire pipewire-alsa pipewire-pulse pipewire-jack wireplumber || {
  err "Fallo instalando paquetes de PipeWire."
  exit 1
}

# Reinstalar waybar si fue removido
if ! pacman -Qi waybar >/dev/null 2>&1; then
  msg "Reinstalando waybar..."
  # Intentar por pacman; si falla, avisar para instalación manual (AUR o variante).
  if ! sudo pacman -S --noconfirm waybar >/dev/null 2>&1; then
    warn "No se pudo reinstalar waybar vía pacman automáticamente. Instálalo manualmente (pacman o AUR) si lo necesitas."
  fi
fi

# Habilitar servicios --user para PipeWire bajo el usuario real
# NOTA: systemctl --user debe ejecutarse en el contexto del usuario (no root). Usamos sudo -u.
if loginctl show-user "$REAL_USER" &>/dev/null; then
  msg "Habilitando servicios user de PipeWire para $REAL_USER..."
  # Ejecutar en el contexto del usuario real; esto requiere que el usuario tenga una sesión PAM activa
  if ! sudo -u "$REAL_USER" systemctl --user enable --now pipewire pipewire-pulse wireplumber >/dev/null 2>&1; then
    warn "No se pudieron habilitar los servicios --user desde aquí. Ejecuta como $REAL_USER: 'systemctl --user enable --now pipewire pipewire-pulse wireplumber' después del login."
  fi
else
  warn "No se detecta una sesión de usuario activa para $REAL_USER. Habilita manualmente los servicios --user tras el login: 'systemctl --user enable --now pipewire pipewire-pulse wireplumber'"
fi

# Install Hyprland and related (use AUR git if preferred, but repo for stability)
msg "Installing Hyprland and dependencies..."
sudo pacman -S --noconfirm hyprland waybar alacritty rofi dunst swaybg swaylock swayidle wl-clipboard \
  grim slurp swappy polkit-kde-agent xdg-desktop-portal-hyprland ttf-font-awesome noto-fonts-emoji \
  qt5-wayland qt6-wayland ttf-cascadia-code || warn "Algunos paquetes de Hyprland/wayland fallaron; revisa la salida."

# If git version needed: yay -S --noconfirm hyprland-git waybar-hyprland-git

# SDDM wayland config
msg "Configuring SDDM for Wayland..."
sudo mkdir -p /etc/sddm.conf.d
sudo tee /etc/sddm.conf.d/wayland.conf >/dev/null <<'SDDM'
[General]
DisplayServer=wayland
GreeterEnvironment=QT_WAYLAND_SHELL_INTEGRATION=layer-shell
SDDM
sudo chown root:root /etc/sddm.conf.d/wayland.conf

# Bluetooth
msg "Installing Bluetooth..."
sudo pacman -S --noconfirm bluez bluez-utils blueman
sudo systemctl enable --now bluetooth

# Utilities
msg "Installing utilities..."
sudo pacman -S --noconfirm pamixer playerctl brightnessctl

# Copy configs
if [[ -d "${REPO_DIR}/configs/wayland" ]]; then
  msg "Copying configs to ~/.config for $REAL_USER..."
  # Crear .config en el home del usuario real (por si ejecutas con sudo)
  USER_HOME=$(eval echo "~${REAL_USER}")
  sudo -u "$REAL_USER" mkdir -p "${USER_HOME}/.config"
  sudo cp -r "${REPO_DIR}/configs/wayland/"* "${USER_HOME}/.config/" || warn "No se pudieron copiar algunos archivos de configuración."
  # Ajustar permisos
  sudo chown -R "${REAL_USER}:${REAL_USER}" "${USER_HOME}/.config"
else
  warn "Configs not found in ${REPO_DIR}/configs/wayland."
fi

# Install Brave
msg "Installing Brave..."
if pacman -Si brave-browser >/dev/null 2>&1; then
  sudo pacman -S --noconfirm brave-browser || warn "Fallo instalando brave-browser desde repositorio."
else
  # usar yay para binarios AUR si no está en repos
  if command -v yay >/dev/null 2>&1; then
    yay -S --noconfirm brave-bin || warn "Fallo instalando brave-bin desde AUR."
  else
    warn "Brave no está en repos y yay no está disponible; instala Brave manualmente."
  fi
fi

# Add user to groups
required_groups=(wheel audio video input)
for g in "${required_groups[@]}"; do
  msg "Añadiendo $REAL_USER al grupo $g..."
  sudo usermod -aG "$g" "$REAL_USER" || warn "No se pudo añadir $REAL_USER al grupo $g"
done

msg "Phase 2 complete. Reboot to start Hyprland via SDDM."
exit 0
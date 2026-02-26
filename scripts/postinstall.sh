#!/usr/bin/env bash
set -euo pipefail

# postinstall.sh
# Phase 2: Desktop setup (Hyprland + Waybar + Alacritty + Brave).
# Ejecutar como el usuario normal (jufedev), NO con sudo:
#   bash /home/prueba-arch/scripts/postinstall.sh

# ─── Constants ────────────────────────────────────────────────────────────────
REPO_DIR="/home/prueba-arch"

# ─── Helpers ──────────────────────────────────────────────────────────────────
msg()  { printf "\e[1;32m[+]\e[0m %s\n" "$*"; }
warn() { printf "\e[1;33m[-]\e[0m %s\n" "$*"; }
err()  { printf "\e[1;31m[!]\e[0m %s\n" "$*"; exit 1; }

# ─── Guards ───────────────────────────────────────────────────────────────────
# Asegurarse de que NO se ejecuta como root
if [ "$EUID" -eq 0 ]; then
  err "No ejecutes este script como root ni con sudo. Úsalo como tu usuario normal (jufedev)."
fi

# Verificar que estamos en el sistema instalado (systemd como PID 1)
if ! ps -p 1 -o comm= 2>/dev/null | grep -q systemd; then
  err "Este script debe correrse desde el sistema instalado, no desde el live ISO."
fi

REAL_USER="$USER"
msg "Usuario detectado: ${REAL_USER}"
msg "Iniciando Phase 2: configuración del escritorio."

# ─── Actualizar sistema ───────────────────────────────────────────────────────
msg "Actualizando sistema..."
sudo pacman -Syu --noconfirm

# ─── Detectar CPU para drivers Vulkan adicionales ────────────────────────────
CPU_VENDOR=$(grep -m1 'vendor_id' /proc/cpuinfo | awk '{print $3}' || echo "unknown")
if [[ "${CPU_VENDOR,,}" == *"intel"* ]]; then
  msg "CPU Intel: verificando drivers Vulkan..."
  sudo pacman -S --noconfirm --needed vulkan-intel lib32-vulkan-intel || warn "Fallo instalando vulkan-intel."
elif [[ "${CPU_VENDOR,,}" == *"authenticamd"* || "${CPU_VENDOR,,}" == *"amd"* ]]; then
  msg "CPU AMD: verificando drivers Vulkan..."
  sudo pacman -S --noconfirm --needed vulkan-radeon lib32-vulkan-radeon || warn "Fallo instalando vulkan-radeon."
fi

# ─── SDDM ────────────────────────────────────────────────────────────────────
msg "Instalando y habilitando SDDM..."
sudo pacman -S --noconfirm --needed sddm
sudo systemctl enable sddm

# ─── PipeWire (con resolución automática de conflicto jack2) ─────────────────
msg "Instalando PipeWire y compatibilidad JACK..."
# --ask 4: confirma automáticamente reemplazos de paquetes en conflicto (jack2 → pipewire-jack)
# Elimina la necesidad de remover jack2/waybar manualmente.
sudo pacman -S --noconfirm --ask 4 --needed \
  pipewire pipewire-alsa pipewire-pulse pipewire-jack wireplumber

# Habilitar servicios --user de PipeWire (corremos como el usuario, sin sudo)
msg "Habilitando servicios PipeWire para ${REAL_USER}..."
systemctl --user enable --now pipewire pipewire-pulse wireplumber || \
  warn "No se pudieron habilitar los servicios --user de PipeWire ahora. Ejecuta manualmente tras el próximo login: 'systemctl --user enable --now pipewire pipewire-pulse wireplumber'"

# ─── Instalar yay (AUR helper) ───────────────────────────────────────────────
msg "Instalando yay (AUR helper)..."
if command -v yay >/dev/null 2>&1; then
  msg "yay ya está instalado."
else
  # makepkg NO puede ejecutarse como root; como ya somos el usuario normal, va directo.
  # /tmp puede tener noexec en algunos setups; usar $HOME como fallback.
  mkdir -p "${HOME}/.cache"
  BUILD_DIR=$(mktemp -d "${HOME}/.cache/yay-build-XXXX")
  git clone https://aur.archlinux.org/yay.git "${BUILD_DIR}"
  cd "${BUILD_DIR}"
  makepkg -si --noconfirm
  cd -
  rm -rf "${BUILD_DIR}"
fi

# ─── Hyprland y dependencias del escritorio ──────────────────────────────────
msg "Instalando Hyprland y dependencias..."
sudo pacman -S --noconfirm --needed \
  hyprland \
  waybar \
  alacritty \
  dunst \
  swaybg \
  swaylock \
  swayidle \
  wl-clipboard \
  grim slurp swappy \
  polkit-kde-agent \
  xdg-desktop-portal-hyprland \
  qt5-wayland qt6-wayland \
  ttf-cascadia-code \
  ttf-font-awesome \
  noto-fonts-emoji || warn "Algunos paquetes fallaron; revisa la salida."

# rofi-wayland: el rofi de repos oficiales no tiene soporte Wayland nativo.
msg "Instalando rofi-wayland (AUR)..."
yay -S --noconfirm rofi-wayland || warn "Fallo instalando rofi-wayland desde AUR."

# ─── Bluetooth ────────────────────────────────────────────────────────────────
msg "Instalando Bluetooth..."
sudo pacman -S --noconfirm --needed bluez bluez-utils blueman
sudo systemctl enable bluetooth

# ─── Utilidades ──────────────────────────────────────────────────────────────
msg "Instalando utilidades (audio/brillo/media)..."
sudo pacman -S --noconfirm --needed pamixer playerctl brightnessctl

# ─── Brave Browser ───────────────────────────────────────────────────────────
msg "Instalando Brave Browser (AUR)..."
if pacman -Si brave-browser >/dev/null 2>&1; then
  sudo pacman -S --noconfirm brave-browser || warn "Fallo instalando brave-browser desde repositorio."
else
  yay -S --noconfirm brave-bin || warn "Fallo instalando brave-bin desde AUR."
fi

# ─── Copiar configuraciones ──────────────────────────────────────────────────
CONFIG_SRC="${REPO_DIR}/configs/wayland"
if [[ -d "${CONFIG_SRC}" ]]; then
  msg "Copiando configs a ~/.config..."
  mkdir -p "${HOME}/.config"
  cp -r "${CONFIG_SRC}/"* "${HOME}/.config/" || warn "No se pudieron copiar algunos archivos de configuración."

  # Copiar configuración de SDDM desde el repo (no generarla en runtime)
  if [[ -d "${CONFIG_SRC}/sddm.conf.d" ]]; then
    msg "Copiando configuración SDDM desde repo..."
    sudo mkdir -p /etc/sddm.conf.d
    sudo cp "${CONFIG_SRC}/sddm.conf.d/"*.conf /etc/sddm.conf.d/ || warn "Fallo copiando config SDDM."
    sudo chown -R root:root /etc/sddm.conf.d
  else
    warn "No se encontró configs/wayland/sddm.conf.d en el repo."
  fi
else
  warn "Directorio de configs no encontrado en ${CONFIG_SRC}."
fi

# ─── Grupos del usuario ──────────────────────────────────────────────────────
msg "Añadiendo ${REAL_USER} a grupos necesarios..."
for g in wheel audio video input; do
  sudo usermod -aG "$g" "${REAL_USER}" || warn "No se pudo añadir ${REAL_USER} al grupo ${g}."
done

# ─── Fin ─────────────────────────────────────────────────────────────────────
msg "Phase 2 completa. Reinicia para entrar a Hyprland via SDDM: sudo reboot"
exit 0
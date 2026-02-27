#!/usr/bin/env bash
set -euo pipefail

# postinstall.sh
# Phase 2: Desktop setup (Hyprland + Waybar + Alacritty + Brave + SilentSDDM).
# Ejecutar como el usuario normal (jufedev), NO con sudo:
#   bash /home/prueba-arch/scripts/postinstall.sh

# ─── Constantes ───────────────────────────────────────────────────────────────
REPO_DIR="/home/prueba-arch"
CONFIGS="${REPO_DIR}/configs/wayland"

# ─── Helpers ──────────────────────────────────────────────────────────────────
msg()  { printf "\e[1;32m[+]\e[0m %s\n" "$*"; }
warn() { printf "\e[1;33m[-]\e[0m %s\n" "$*"; }
err()  { printf "\e[1;31m[!]\e[0m %s\n" "$*"; exit 1; }

# ─── Guards ───────────────────────────────────────────────────────────────────
[ "$EUID" -eq 0 ] && err "No ejecutes este script como root ni con sudo."
ps -p 1 -o comm= 2>/dev/null | grep -q systemd || \
  err "Corre desde el sistema instalado, no desde el live ISO."

REAL_USER="$USER"
msg "Usuario: ${REAL_USER} — Iniciando Phase 2."

# ─── Verificar que el repo tiene los configs necesarios ──────────────────────
[[ -d "${CONFIGS}" ]] || err "No se encontró ${CONFIGS}. Clona el repo antes de continuar."

# ─── Actualizar sistema ───────────────────────────────────────────────────────
msg "Actualizando sistema..."
sudo pacman -Syu --noconfirm

# ─── Drivers Vulkan según CPU ─────────────────────────────────────────────────
CPU_VENDOR=$(grep -m1 'vendor_id' /proc/cpuinfo | awk '{print $3}' || echo "unknown")
if [[ "${CPU_VENDOR,,}" == *"intel"* ]]; then
  msg "CPU Intel: instalando drivers Vulkan..."
  sudo pacman -S --noconfirm --needed vulkan-intel lib32-vulkan-intel || warn "Fallo vulkan-intel."
elif [[ "${CPU_VENDOR,,}" == *"authenticamd"* || "${CPU_VENDOR,,}" == *"amd"* ]]; then
  msg "CPU AMD: instalando drivers Vulkan..."
  sudo pacman -S --noconfirm --needed vulkan-radeon lib32-vulkan-radeon || warn "Fallo vulkan-radeon."
fi

# ─── PipeWire ─────────────────────────────────────────────────────────────────
msg "Instalando PipeWire..."
sudo pacman -S --noconfirm --ask 4 --needed \
  pipewire pipewire-alsa pipewire-pulse pipewire-jack wireplumber

msg "Habilitando servicios PipeWire..."
systemctl --user enable --now pipewire pipewire-pulse wireplumber || \
  warn "Habilita manualmente tras el login: systemctl --user enable --now pipewire pipewire-pulse wireplumber"

# ─── yay ──────────────────────────────────────────────────────────────────────
msg "Instalando yay (AUR helper)..."
if command -v yay >/dev/null 2>&1; then
  msg "yay ya instalado."
else
  mkdir -p "${HOME}/.cache"
  BUILD_DIR=$(mktemp -d "${HOME}/.cache/yay-build-XXXX")
  git clone https://aur.archlinux.org/yay.git "${BUILD_DIR}"
  cd "${BUILD_DIR}" && makepkg -si --noconfirm && cd -
  rm -rf "${BUILD_DIR}"
fi

# ─── Paquetes repos oficiales ─────────────────────────────────────────────────
msg "Instalando paquetes de escritorio (repos oficiales)..."
sudo pacman -S --noconfirm --needed \
  hyprland \
  waybar \
  alacritty \
  pavucontrol \
  dunst \
  swaybg \
  swaylock \
  swayidle \
  wl-clipboard \
  grim slurp swappy \
  polkit-kde-agent \
  xdg-desktop-portal-hyprland \
  qt5-wayland qt6-wayland \
  qt6-svg qt6-virtualkeyboard qt6-multimedia-ffmpeg \
  ttf-font-awesome \
  pamixer playerctl brightnessctl \
  bluez bluez-utils blueman \
  sddm || warn "Algunos paquetes fallaron; revisa la salida."

# ─── Paquetes AUR ─────────────────────────────────────────────────────────────
msg "Instalando paquetes AUR..."
declare -A aur_pkgs=(
  ["ttf-cascadia-code-nerd"]="Nerd Font para iconos en waybar"
  ["rofi-wayland"]="rofi con soporte Wayland nativo"
  ["wlogout"]="Menu de power con iconos"
  ["brave-bin"]="Brave Browser"
  ["sddm-silent-theme"]="Tema SDDM"
)

for pkg in "${!aur_pkgs[@]}"; do
  msg "  -> ${pkg} (${aur_pkgs[$pkg]})"
  yay -S --noconfirm "${pkg}" || warn "Fallo instalando ${pkg}."
done

# ─── Servicios ────────────────────────────────────────────────────────────────
msg "Habilitando servicios del sistema..."
sudo systemctl enable sddm
sudo systemctl enable bluetooth.service

# ─── Grupos del usuario ───────────────────────────────────────────────────────
msg "Añadiendo ${REAL_USER} a grupos..."
for g in wheel audio video input; do
  sudo usermod -aG "$g" "${REAL_USER}" || warn "No se pudo añadir al grupo ${g}."
done

# ─── Copiar configs del repo → ~/.config ─────────────────────────────────────
# Mapa explícito repo -> destino (evita copiar sddm.conf.d al lugar incorrecto)
#
#  configs/wayland/hypr/           -> ~/.config/hypr/
#  configs/wayland/waybar/         -> ~/.config/waybar/
#  configs/wayland/alacritty/      -> ~/.config/alacritty/
#  configs/wayland/wlogout/        -> ~/.config/wlogout/
#
#  configs/wayland/sddm.conf.d/    -> /etc/sddm.conf.d/  (ver sección SDDM)
#                                     + /usr/share/sddm/themes/silent/configs/
#
msg "Creando directorios de config..."
mkdir -p \
  "${HOME}/.config/hypr" \
  "${HOME}/.config/waybar/scripts" \
  "${HOME}/.config/alacritty" \
  "${HOME}/.config/wlogout"

msg "Copiando configs..."
cp "${CONFIGS}/hypr/hyprland.conf"           "${HOME}/.config/hypr/hyprland.conf"
cp "${CONFIGS}/waybar/config"                "${HOME}/.config/waybar/config"
cp "${CONFIGS}/waybar/style.css"             "${HOME}/.config/waybar/style.css"
cp "${CONFIGS}/waybar/scripts/battery.sh"    "${HOME}/.config/waybar/scripts/battery.sh"
chmod +x "${HOME}/.config/waybar/scripts/battery.sh"
cp "${CONFIGS}/alacritty/alacritty.toml"     "${HOME}/.config/alacritty/alacritty.toml"
cp "${CONFIGS}/wlogout/layout"               "${HOME}/.config/wlogout/layout"
cp "${CONFIGS}/wlogout/style.css"            "${HOME}/.config/wlogout/style.css"

msg "Configs copiados correctamente."

# ─── SDDM ────────────────────────────────────────────────────────────────────
msg "Configurando SDDM..."

# wayland.conf -> /etc/sddm.conf.d/ (indica a SDDM usar Wayland como backend)
sudo mkdir -p /etc/sddm.conf.d
sudo cp "${CONFIGS}/sddm.conf.d/wayland.conf" /etc/sddm.conf.d/wayland.conf
sudo chown root:root /etc/sddm.conf.d/wayland.conf

# /etc/sddm.conf: activa SilentSDDM
# InputMethod vacío = sin boton de teclado virtual en pantalla
sudo tee /etc/sddm.conf > /dev/null <<'SDDMEOF'
[General]
InputMethod=
GreeterEnvironment=QML2_IMPORT_PATH=/usr/share/sddm/themes/silent/components/,QT_IM_MODULE=qtvirtualkeyboard

[Theme]
Current=silent

[Wayland]
SessionDir=/usr/share/wayland-sessions
SDDMEOF

# Config personalizado de SilentSDDM
# El archivo silent-custom.conf debe existir en configs/wayland/sddm.conf.d/
SILENT_DIR="/usr/share/sddm/themes/silent"
SILENT_CONF="${CONFIGS}/sddm.conf.d/silent-custom.conf"

if [[ -d "${SILENT_DIR}" ]]; then
  if [[ -f "${SILENT_CONF}" ]]; then
    msg "Aplicando config personalizado de SilentSDDM..."
    sudo cp "${SILENT_CONF}" "${SILENT_DIR}/configs/silent-custom.conf"
    sudo sed -i 's|^ConfigFile=.*|ConfigFile=configs/silent-custom.conf|' \
      "${SILENT_DIR}/metadata.desktop"
    msg "SilentSDDM configurado con silent-custom.conf"
  else
    warn "Falta ${SILENT_CONF} en el repo. SilentSDDM usara su config default."
    warn "Crea configs/wayland/sddm.conf.d/silent-custom.conf y vuelve a correr este bloque."
  fi
else
  warn "SilentSDDM no instalado en ${SILENT_DIR}. Instala sddm-silent-theme y configura manualmente."
fi

# Layout de teclado fisico para la pantalla de login
sudo localectl set-x11-keymap us || warn "Fallo localectl. Configura el layout manualmente."

# ─── Fin ──────────────────────────────────────────────────────────────────────
msg "================================================"
msg "Phase 2 completa. Configs desplegados:"
msg "  ~/.config/hypr/hyprland.conf"
msg "  ~/.config/waybar/config + style.css + scripts/"
msg "  ~/.config/alacritty/alacritty.toml"
msg "  ~/.config/wlogout/layout + style.css"
msg "  /etc/sddm.conf.d/wayland.conf"
msg "  /etc/sddm.conf"
msg ""
msg "Reinicia para entrar a Hyprland via SDDM:"
msg "  sudo reboot"
msg "================================================"
exit 0
#!/usr/bin/env bash
set -euo pipefail

# phase2-desktop.sh
# Configura un entorno de escritorio Hyprland + Waybar + Alacritty.
# Ejecutar como usuario normal (jufedev) después del primer arranque.
# Asume que el repositorio está clonado en ~/arch-install-automated (o en el directorio actual).
# Se necesita conexión a Internet.

# Colores para mensajes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

msg() {
    echo -e "${GREEN}==>${NC} $*"
}

warn() {
    echo -e "${YELLOW}==> ADVERTENCIA:${NC} $*"
}

error() {
    echo -e "${RED}==> ERROR:${NC} $*" >&2
    exit 1
}

# Verificar que no se ejecute como root
if [ "$EUID" -eq 0 ]; then
    error "Este script debe ejecutarse como usuario normal (no como root)."
fi

# Verificar conexión a Internet
if ! ping -c 1 archlinux.org &>/dev/null; then
    error "No hay conexión a Internet. Comprueba tu red."
fi

# Pedir contraseña sudo al principio para evitar preguntas múltiples
sudo -v || error "Necesitas tener permisos sudo. Agrega tu usuario a sudoers."

# Definir directorio del repo (se asume que el script está en scripts/ dentro del repo)
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_DIR="$REPO_DIR/configs/wayland"

msg "Directorio del repositorio: $REPO_DIR"
msg "Directorio de configuraciones: $CONFIG_DIR"

# 1. Actualizar sistema
msg "Actualizando el sistema..."
sudo pacman -Syu --noconfirm

# 2. Instalar herramientas base (si faltan)
msg "Instalando base-devel y git (si es necesario)..."
sudo pacman -S --needed --noconfirm base-devel git

# 3. Detectar GPU e instalar controladores
msg "Detectando GPU..."
GPU_INFO=$(lspci | grep -E "VGA|3D|Display")
msg "GPU detectada: $GPU_INFO"

if echo "$GPU_INFO" | grep -qi "intel"; then
    msg "Instalando controladores Intel..."
    sudo pacman -S --needed --noconfirm mesa vulkan-intel intel-ucode
elif echo "$GPU_INFO" | grep -qi "amd"; then
    msg "Instalando controladores AMD..."
    sudo pacman -S --needed --noconfirm mesa vulkan-radeon amd-ucode
elif echo "$GPU_INFO" | grep -qi "nvidia"; then
    msg "Instalando controladores NVIDIA (propietarios)..."
    sudo pacman -S --needed --noconfirm nvidia nvidia-utils lib32-nvidia-utils
    warn "Si tienes problemas con NVIDIA y Wayland, consulta la wiki de Arch."
else
    warn "No se pudo detectar GPU específica. Instalando solo mesa (controladores genéricos)."
    sudo pacman -S --needed --noconfirm mesa
fi

# 4. Instalar yay (AUR helper) si no está
if ! command -v yay &>/dev/null; then
    msg "Instalando yay desde AUR..."
    cd /tmp
    git clone https://aur.archlinux.org/yay.git
    cd yay
    makepkg -si --noconfirm
    cd ~
else
    msg "yay ya está instalado."
fi

# 5. Instalar paquetes necesarios (oficiales + AUR si es necesario)
msg "Instalando paquetes para Wayland/Hyprland..."

# Paquetes de los repositorios oficiales
PACMAN_PKGS=(
    hyprland waybar alacritty
    xdg-desktop-portal xdg-desktop-portal-hyprland
    pipewire pipewire-pulse wireplumber
    wofi wl-clipboard grim slurp mako
    swaybg swayidle swaylock polkit-gnome
    libinput pamixer playerctl brightnessctl
    noto-fonts noto-fonts-emoji ttf-dejavu ttf-cascadia-code
    fontconfig
    networkmanager nm-connection-editor
    firefox neovim thunar
    mpv pavucontrol
    bluez bluez-utils blueman
    tlp brightnessctl
    sddm   # opcional, puedes quitarlo si prefieres otro
)

sudo pacman -S --needed --noconfirm "${PACMAN_PKGS[@]}"

# Paquetes AUR (si los hubiera, pero en este caso todos están en oficiales)
# Si quisieras instalar versiones git, descomenta las siguientes líneas:
# AUR_PKGS=(
#     hyprland-git waybar-hyprland-git alacritty-git
# )
# yay -S --needed --noconfirm "${AUR_PKGS[@]}"

# 6. Agregar usuario a grupos necesarios
msg "Agregando usuario a grupos (audio, video, network, etc.)..."
sudo usermod -aG wheel,audio,video,input,network,bluetooth,storage,optical,lp "$USER"

# 7. Configurar SDDM (opcional)
msg "Configurando SDDM como gestor de inicio..."
sudo systemctl enable --now sddm

# Forzar SDDM a usar Wayland (opcional, mejora integración)
sudo mkdir -p /etc/sddm.conf.d
sudo tee /etc/sddm.conf.d/wayland.conf > /dev/null <<'EOF'
[General]
DisplayServer=wayland
GreeterEnvironment=QT_WAYLAND_SHELL_INTEGRATION=layer-shell
EOF

# 8. Copiar configuraciones de ejemplo a ~/.config/
msg "Copiando configuraciones de ejemplo..."

# Hyprland
mkdir -p ~/.config/hypr
if [ -f "$CONFIG_DIR/hyprland/hyprland.conf" ]; then
    cp "$CONFIG_DIR/hyprland/hyprland.conf" ~/.config/hypr/
else
    warn "No se encontró hyprland.conf. Se usará la configuración por defecto."
fi

# Waybar
mkdir -p ~/.config/waybar
if [ -f "$CONFIG_DIR/waybar/config" ]; then
    cp "$CONFIG_DIR/waybar/config" ~/.config/waybar/
fi
if [ -f "$CONFIG_DIR/waybar/style.css" ]; then
    cp "$CONFIG_DIR/waybar/style.css" ~/.config/waybar/
fi

# Alacritty
mkdir -p ~/.config/alacritty
if [ -f "$CONFIG_DIR/alacritty/alacritty.yml" ]; then
    cp "$CONFIG_DIR/alacritty/alacritty.yml" ~/.config/alacritty/
fi

# 9. Habilitar servicios de usuario (PipeWire)
msg "Habilitando servicios de audio (PipeWire)..."
systemctl --user enable --now pipewire pipewire-pulse wireplumber

# 10. Habilitar servicios del sistema (NetworkManager ya debería estar activo, TLP)
msg "Habilitando servicios del sistema (NetworkManager, TLP)..."
sudo systemctl enable --now NetworkManager
sudo systemctl enable --now tlp

# 11. Crear archivo .desktop para Hyprland (por si acaso no existe)
if [ ! -f /usr/share/wayland-sessions/hyprland.desktop ]; then
    msg "Creando entrada para Hyprland en el gestor de sesiones..."
    sudo tee /usr/share/wayland-sessions/hyprland.desktop > /dev/null <<'EOF'
[Desktop Entry]
Name=Hyprland
Comment=Hyprland Wayland Compositor
Exec=Hyprland
Type=Application
DesktopNames=Hyprland
EOF
fi

# 12. Mensaje final
msg "¡Fase 2 completada!"
echo -e "${GREEN}Recomendaciones:${NC}"
echo "  1. Reinicia el sistema con 'reboot'."
echo "  2. En el gestor de inicio (SDDM) selecciona 'Hyprland'."
echo "  3. Disfruta de tu nuevo escritorio."
echo ""
echo "Si encuentras problemas, revisa los logs:"
echo "  - journalctl -b -p err"
echo "  - Hyprland (ejecuta 'Hyprland' desde una TTY para ver errores)"
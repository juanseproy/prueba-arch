#!/usr/bin/env bash
set -euo pipefail

# phase2-desktop.sh
# Configura un entorno de escritorio Hyprland + Waybar + Alacritty + Brave.
# Ejecutar como usuario normal (jufedev) después del primer arranque.
# Asume que el repositorio está clonado en ~/prueba-arch (o en el directorio actual).
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

# Verificar que el directorio de configuraciones existe
if [ ! -d "$CONFIG_DIR" ]; then
    warn "No se encontró el directorio de configuraciones en $CONFIG_DIR"
    warn "Se crearán configuraciones mínimas por defecto."
    mkdir -p "$CONFIG_DIR"/{hyprland,waybar,alacritty,sddm.conf.d}
fi

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

# Detectar si estamos en VirtualBox
if dmidecode -s system-product-name | grep -qi "VirtualBox"; then
    msg "Sistema VirtualBox detectado. Instalando virtualbox-guest-utils..."
    sudo pacman -S --needed --noconfirm virtualbox-guest-utils
    sudo systemctl enable vboxservice
    sudo usermod -aG vboxsf "$USER"
fi

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
elif echo "$GPU_INFO" | grep -qi "VMware"; then
    msg "GPU VMware (VirtualBox) detectada. Instalando mesa..."
    sudo pacman -S --needed --noconfirm mesa
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

# 5. Instalar paquetes necesarios
msg "Instalando paquetes para Wayland/Hyprland..."

# Paquetes de los repositorios oficiales
PACMAN_PKGS=(
    # Core Hyprland y Wayland
    hyprland waybar alacritty
    xdg-desktop-portal xdg-desktop-portal-hyprland
    # Audio
    pipewire pipewire-pulse wireplumber pavucontrol
    # Utilidades Wayland
    wofi wl-clipboard grim slurp mako
    # Fondos y bloqueo
    swaybg swayidle swaylock
    # Polkit
    polkit-gnome
    # Hardware
    libinput pamixer playerctl brightnessctl
    # Fuentes
    noto-fonts noto-fonts-emoji ttf-dejavu ttf-cascadia-code fontconfig
    # Red
    networkmanager nm-connection-editor
    # Bluetooth
    bluez bluez-utils blueman
    # Energía
    tlp
    # SDDM
    sddm
    # Utilidades
    firefox thunar mpv
)

sudo pacman -S --needed --noconfirm "${PACMAN_PKGS[@]}"

# Instalar Brave desde AUR
msg "Instalando Brave Browser desde AUR..."
yay -S --needed --noconfirm brave-bin

# 6. Agregar usuario a grupos necesarios
msg "Agregando usuario a grupos (audio, video, network, etc.)..."
sudo usermod -aG wheel,audio,video,input,network,bluetooth,storage,optical,lp "$USER"

# 7. Configurar SDDM como gestor de inicio
msg "Configurando SDDM como gestor de inicio..."
sudo systemctl enable --now sddm

# Copiar configuración de SDDM si existe en el repo
if [ -f "$CONFIG_DIR/sddm.conf.d/wayland.conf" ]; then
    msg "Copiando configuración de SDDM desde el repositorio..."
    sudo mkdir -p /etc/sddm.conf.d
    sudo cp "$CONFIG_DIR/sddm.conf.d/wayland.conf" /etc/sddm.conf.d/
else
    msg "Usando configuración por defecto para SDDM (Wayland)..."
    sudo mkdir -p /etc/sddm.conf.d
    sudo tee /etc/sddm.conf.d/wayland.conf > /dev/null <<'EOF'
[General]
DisplayServer=wayland
GreeterEnvironment=QT_WAYLAND_SHELL_INTEGRATION=layer-shell
EOF
fi

# 8. Copiar configuraciones de ejemplo desde el repo a ~/.config/
msg "Copiando configuraciones desde el repositorio..."

# Hyprland
mkdir -p ~/.config/hypr
if [ -f "$CONFIG_DIR/hyprland/hyprland.conf" ]; then
    cp "$CONFIG_DIR/hyprland/hyprland.conf" ~/.config/hypr/
    msg "  ✓ hyprland.conf copiado"
else
    warn "No se encontró hyprland.conf. Creando configuración mínima para VirtualBox..."
    # Configuración mínima que funciona en VirtualBox (sin efectos)
    tee ~/.config/hypr/hyprland.conf > /dev/null <<'EOF'
# Configuración mínima para Hyprland en VirtualBox
$mainMod = SUPER

# Autostart
exec-once = waybar
exec-once = /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1

# Atajos
bind = $mainMod, RETURN, exec, alacritty
bind = $mainMod, D, exec, wofi --show drun
bind = $mainMod, Q, killactive
bind = $mainMod SHIFT, E, exit

# Workspaces
bind = $mainMod, 1, workspace, 1
bind = $mainMod, 2, workspace, 2
bind = $mainMod, 3, workspace, 3
bind = $mainMod, 4, workspace, 4

# Movimiento
bind = $mainMod, left, movefocus, l
bind = $mainMod, right, movefocus, r
bind = $mainMod, up, movefocus, u
bind = $mainMod, down, movefocus, d

# Apariencia (valores seguros para VirtualBox)
general {
    gaps_in = 0
    gaps_out = 0
    border_size = 1
    col.active_border = rgba(33ccffee)
    col.inactive_border = rgba(595959aa)
}

decoration {
    rounding = 0
    blur = false
}

# Input
input {
    kb_layout = us
    follow_mouse = 1
}

# Monitor (Forzar detección segura)
monitor=,preferred,auto,1
EOF
    msg "  ✓ hyprland.conf mínimo creado"
fi

# Waybar
mkdir -p ~/.config/waybar
if [ -f "$CONFIG_DIR/waybar/config" ]; then
    cp "$CONFIG_DIR/waybar/config" ~/.config/waybar/
    msg "  ✓ waybar/config copiado"
else
    warn "No se encontró waybar/config. Se usará el predeterminado."
fi

if [ -f "$CONFIG_DIR/waybar/style.css" ]; then
    cp "$CONFIG_DIR/waybar/style.css" ~/.config/waybar/
    msg "  ✓ waybar/style.css copiado"
fi

# Alacritty
mkdir -p ~/.config/alacritty
if [ -f "$CONFIG_DIR/alacritty/alacritty.yml" ]; then
    cp "$CONFIG_DIR/alacritty/alacritty.yml" ~/.config/alacritty/
    msg "  ✓ alacritty.yml copiado"
fi

# 9. Habilitar servicios de usuario (PipeWire)
msg "Habilitando servicios de audio (PipeWire)..."
systemctl --user enable --now pipewire pipewire-pulse wireplumber

# 10. Habilitar servicios del sistema
msg "Habilitando servicios del sistema..."
sudo systemctl enable --now NetworkManager
sudo systemctl enable --now tlp
sudo systemctl enable --now bluetooth

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

# 12. Verificar que SDDM está habilitado para el próximo arranque
msg "Verificando que SDDM se inicie automáticamente..."
if systemctl is-enabled sddm &>/dev/null; then
    msg "  ✓ SDDM está habilitado"
else
    warn "SDDM no está habilitado. Habilitando ahora..."
    sudo systemctl enable sddm
fi

# 13. Mensaje final y consejos para VirtualBox
msg "¡Fase 2 completada!"
echo -e "${GREEN}Recomendaciones:${NC}"
echo "  1. Reinicia el sistema con 'reboot'."
echo "  2. En el gestor de inicio (SDDM) selecciona 'Hyprland'."
#!/usr/bin/env bash
set -euo pipefail

# phase2-postinstall.sh
# Ejecutar como usuario normal (no root) después del primer arranque.
# Ajusta USERNAME si quieres ejecutar para otro usuario.

USERNAME="${SUDO_USER:-${USER:-jufedev}}"
REPO_DIR="${HOME}/prueba-arch"   # directorio donde está tu repo con configs

# Mensajes
msg(){ printf "\e[1;32m[+]\e[0m %s\n" "$*"; }
warn(){ printf "\e[1;33m[-]\e[0m %s\n" "$*"; }
err(){ printf "\e[1;31m[!]\e[0m %s\n" "$*"; }

if [[ "$(id -u)" -eq 0 ]]; then
    err "No ejecutes este script como root. Ejecuta como usuario normal."
    exit 1
fi

msg "Usuario objetivo: ${USERNAME}"
msg "Actualizando sistema..."
sudo pacman -Syu --noconfirm

# Paquetes principales
msg "Instalando paquetes principales (Hyprland, Waybar, Alacritty, SDDM y dependencias)…"
sudo pacman -S --needed --noconfirm \
    hyprland wayland-protocols wayland xorg-xwayland \
    waybar alacritty sddm sddm-kcm \
    pipewire wireplumber pipewire-pulse \
    polkit-gnome blueman bluez bluez-utils \
    ntp networkmanager

# Brave: intentar con pacman, si no está, avisar que use AUR
if ! pacman -Si brave >/dev/null 2>&1; then
    warn "Brave no está en repos oficiales (o no detectado). Si quieres instalar Brave, usa AUR (ej. brave-bin) con un helper como 'yay'."
else
    msg "Instalando Brave desde repos oficiales..."
    sudo pacman -S --noconfirm brave
fi

# Grupos de usuario: añadir solo los que existan; crear bluetooth si no existe
required_groups=(wheel audio video lp optical storage)
for g in "${required_groups[@]}"; do
    if getent group "${g}" >/dev/null 2>&1; then
        sudo usermod -aG "${g}" "${USERNAME}" || warn "No se pudo añadir ${USERNAME} al grupo ${g}"
    else
        warn "Grupo ${g} no existe, se omite."
    fi
done

# Grupo bluetooth: si no existe, crearlo primero
if ! getent group bluetooth >/dev/null 2>&1; then
    msg "Grupo 'bluetooth' no existe. Creándolo..."
    sudo groupadd bluetooth || warn "No se pudo crear el grupo bluetooth"
fi
# Añadir usuario al grupo bluetooth (ahora debería existir)
sudo usermod -aG bluetooth "${USERNAME}" || warn "No se pudo añadir ${USERNAME} al grupo bluetooth"

# Habilitar servicios
msg "Habilitando servicios: NetworkManager, bluetooth, pipewire, sddm"
sudo systemctl enable --now NetworkManager
if pacman -Qs bluez >/dev/null 2>&1; then
    sudo systemctl enable --now bluetooth
fi
sudo systemctl enable --now pipewire pipewire-pulse
sudo systemctl enable --now sddm

# Copiar configs (si existen en el repo)
if [[ -d "${REPO_DIR}/configs/wayland" ]]; then
    msg "Instalando configs de Wayland desde ${REPO_DIR}/configs/wayland..."
    mkdir -p "${HOME}/.config"
    cp -r "${REPO_DIR}/configs/wayland/"* "${HOME}/.config/" 2>/dev/null || true
    chown -R "${USERNAME}":"${USERNAME}" "${HOME}/.config" || true
else
    warn "No encuentro ${REPO_DIR}/configs/wayland — omitiendo copia de configs."
fi

msg "Comprobando SDDM: elegir sesión Hyprland en el login si está disponible."
msg "Fase 2 completada. Reinicia para probar el entorno gráfico (recomendado)."
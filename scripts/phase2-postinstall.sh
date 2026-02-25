#!/usr/bin/env bash
set -euo pipefail

# phase2-postinstall.sh
# Modo 1 (chroot target): ejecutar desde el live ISO como root cuando el sistema objetivo está montado en /mnt.
# Modo 2 (sistema instalado): ejecutar desde el sistema ya arrancado (usuario normal con sudo).
#
# Uso:
#  - En entorno live/chroot: sudo ./phase2-postinstall.sh --target /mnt --disk /dev/sda
#  - En sistema instalado: ./phase2-postinstall.sh
#
# IMPORTANTE: revisa DEV_DISK antes de ejecutar (evita sobrescribir el disco equivocado).

# Defaults
TARGET_MNT="/mnt"
DEV_DISK="/dev/sda"        # <<-- ajusta si tu disco no es /dev/sda
USERNAME="${SUDO_USER:-${USER:-jufedev}}"
REPO_DIR="${HOME}/prueba-arch"   # carpeta donde están tus configs (si existe)

# Parse args simples
while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) TARGET_MNT="$2"; shift 2;;
    --disk) DEV_DISK="$2"; shift 2;;
    --repo) REPO_DIR="$2"; shift 2;;
    --help) echo "Uso: $0 [--target /mnt] [--disk /dev/sda]"; exit 0;;
    *) shift;;
  esac
done

msg(){ printf "\e[1;32m[+]\e[0m %s\n" "$*"; }
warn(){ printf "\e[1;33m[-]\e[0m %s\n" "$*"; }
err(){ printf "\e[1;31m[!]\e[0m %s\n" "$*"; }

# Detectar si systemd está corriendo (true en sistema instalado normal)
systemd_running=false
if ps -p 1 -o comm= 2>/dev/null | grep -q systemd; then
  systemd_running=true
fi

# Detectar si estamos en chroot-target mode: root y target existe (y systemd no corre)
in_chroot_target=false
if [[ $EUID -eq 0 && -d "${TARGET_MNT}" && ! $systemd_running ]]; then
  # asumimos que estamos ejecutando desde live y el sistema objetivo está montado en TARGET_MNT
  in_chroot_target=true
fi

msg "Modo detected: systemd_running=${systemd_running}, in_chroot_target=${in_chroot_target}"
msg "Usuario objetivo (para añadir a grupos/copiar configs): ${USERNAME}"
msg "Repo dir (si existe): ${REPO_DIR}"
msg "Disco para GRUB (si aplica): ${DEV_DISK}"
msg "Target mount: ${TARGET_MNT}"

#########################
# MODO CHROOT/TARGET (operaciones que se hacen antes del primer arranque)
#########################
if $in_chroot_target; then
  msg "Ejecutando en modo chroot/target (operando sobre ${TARGET_MNT})."

  # 0) comprobar que existe el mount target
  if [[ ! -d "${TARGET_MNT}" ]]; then
    err "No encuentro ${TARGET_MNT}. Monta tu sistema objetivo en esa ruta y vuelve a ejecutar."
    exit 1
  fi

  # 1) Instalar grub en MBR (si lo deseas)
  msg "Instalando GRUB (MBR). Si usas UEFI, adapta estos pasos (grub-install --target=x86_64-efi ...)."
  arch-chroot "${TARGET_MNT}" /bin/bash -c "
    set -e
    pacman -Syu --noconfirm grub || true
    grub-install --target=i386-pc ${DEV_DISK} || true
    grub-mkconfig -o /boot/grub/grub.cfg || true
  "

  # 2) Microcode / drivers (detectar vendor CPU y sugerir)
  msg "Instalando microcode y drivers (elige el que corresponda). Detectando CPU vendor..."
  CPU_VENDOR=$(grep -m1 'vendor_id' /proc/cpuinfo | awk '{print $3}' || true)
  if [[ -z "${CPU_VENDOR}" ]]; then
    warn "No pude detectar CPU desde live. Instala microcode apropiado manualmente dentro del chroot."
  fi

  if [[ "${CPU_VENDOR,,}" == *"authenticamd"* || "${CPU_VENDOR,,}" == *"amd"* ]]; then
    msg "Detectado AMD (o asumido). Instalando amd-ucode mesa vulkan-radeon dentro del target..."
    arch-chroot "${TARGET_MNT}" /bin/bash -c "pacman -S --noconfirm amd-ucode mesa vulkan-radeon || true"
  elif [[ "${CPU_VENDOR,,}" == *"intel"* ]]; then
    msg "Detectado Intel (o asumido). Instalando intel-ucode mesa vulkan-intel dentro del target..."
    arch-chroot "${TARGET_MNT}" /bin/bash -c "pacman -S --noconfirm intel-ucode mesa vulkan-intel || true"
  else
    warn "No se detectó claramente AMD/Intel. Revisa e instala microcode/drivers apropiados en el chroot."
  fi

  # 3) mkinitcpio dentro del target
  msg "Regenerando initramfs dentro del target (mkinitcpio -P)..."
  arch-chroot "${TARGET_MNT}" /bin/bash -c "mkinitcpio -P || true"

  # 4) Crear usuario y aplicar contraseña interactiva (si no existe)
  msg "Crear usuario ${USERNAME} dentro del target (si no existe). Te pedirá contraseña..."
  arch-chroot "${TARGET_MNT}" /bin/bash -c "
    set -e
    if id -u ${USERNAME} &>/dev/null; then
      echo 'Usuario ${USERNAME} ya existe en target; omitiendo creación.'
    else
      useradd -m -G wheel -s /bin/bash ${USERNAME} || true
    fi
    echo 'Ahora establece la contraseña para root y para ${USERNAME} dentro del chroot:'
    echo '--- Establece contraseña de root ---'
    passwd root || true
    echo '--- Establece contraseña de ${USERNAME} ---'
    passwd ${USERNAME} || true
  "

  # 5) Instalar sudo y configurar visudo (habilitar wheel)
  msg "Instalando sudo y permitiendo grupo wheel en el target (/etc/sudoers)..."
  arch-chroot "${TARGET_MNT}" /bin/bash -c "
    set -e
    pacman -S --noconfirm sudo || true
    # descomentar la linea de wheel en visudo (no interactivo)
    sed -i 's/^# \\(%wheel ALL=(ALL:ALL) ALL\\)/\\1/' /etc/sudoers || true
  "

  # 6) Instalar herramientas build y git (necesarias para AUR si se usará)
  msg "Instalando base-devel y git dentro del target..."
  arch-chroot "${TARGET_MNT}" /bin/bash -c "pacman -S --noconfirm base-devel git || true"

  # 7) Networking / Display manager / Wayland deps (instalar los paquetes base)
  msg "Instalando NetworkManager, sddm y paquetes base de display/wayland (no arrancamos servicios aquí)..."
  arch-chroot "${TARGET_MNT}" /bin/bash -c "
    set -e
    pacman -S --noconfirm networkmanager sddm wayland-protocols xorg-xwayland || true
    # Hyprland suele estar en AUR; dejamos la instalación para el primer login (o instalar vía AUR desde aquí si quieres).
  "

  # 8) Habilitar servicios (solo crear enable - sin arrancar si systemd no está corriendo)
  msg "Habilitando servicios en el target (se crean los symlinks; no se arrancan aquí si no hay systemd activo)..."
  arch-chroot "${TARGET_MNT}" /bin/bash -c "
    set -e
    systemctl enable NetworkManager || true
    systemctl enable sddm || true
    # bluetooth y pipewire se habilitarán si están presentes
    if pacman -Qs bluez >/dev/null 2>&1; then systemctl enable bluetooth || true; fi
    if pacman -Qs pipewire >/dev/null 2>&1; then
      systemctl enable pipewire.service pipewire-pulse.service wireplumber.service || true
    fi
  "

  msg "Modo chroot/target finalizado. Desmonta ${TARGET_MNT} y reinicia para continuar con las tareas de usuario."
  exit 0
fi

#########################
# MODO SISTEMA INSTALADO (systemd activo) - operaciones post-login
#########################
msg "Ejecutando en modo sistema instalado (systemd activo). Se instalarán Hyprland/Waybar/Alacritty y se intentará Brave (repo -> AUR)."

# Actualizar e instalar paquetes necesarios
msg "Actualizando sistema e instalando paquetes principales..."
sudo pacman -Syu --noconfirm

sudo pacman -S --needed --noconfirm \
  hyprland wayland-protocols wayland xorg-xwayland \
  waybar alacritty sddm sddm-kcm \
  pipewire wireplumber pipewire-pulse \
  polkit-gnome blueman bluez bluez-utils \
  ntp networkmanager base-devel git

# Añadir usuario a grupos (solo si existen)
required_groups=(wheel audio video lp optical storage)
for g in "${required_groups[@]}"; do
  if getent group "${g}" >/dev/null 2>&1; then
    sudo usermod -aG "${g}" "${USERNAME}" || warn "No se pudo añadir ${USERNAME} al grupo ${g}"
  else
    warn "Grupo ${g} no existe; omitiendo."
  fi
done

# Bluetooth: crear grupo si no existe y añadir usuario
if ! getent group bluetooth >/dev/null 2>&1; then
  sudo groupadd bluetooth && msg "Grupo 'bluetooth' creado."
fi
sudo usermod -aG bluetooth "${USERNAME}" || warn "No se pudo añadir ${USERNAME} al grupo bluetooth"

# Función segura para habilitar servicios
enable_service_safe() {
  svc="$1"
  if systemctl list-unit-files "$svc" >/dev/null 2>&1 || systemctl status "$svc" >/dev/null 2>&1; then
    msg "Habilitando y arrancando ${svc}..."
    sudo systemctl enable --now "$svc" || warn "No se pudo habilitar/arrancar ${svc}"
  else
    warn "Servicio ${svc} no encontrado; omitiendo."
  fi
}

# Habilitar servicios principales
enable_service_safe NetworkManager
if pacman -Qs bluez >/dev/null 2>&1; then enable_service_safe bluetooth.service; fi

# PipeWire (comprobar si existen unidades system-wide, si no usar user services)
if systemctl list-unit-files | grep -q pipewire; then
  enable_service_safe pipewire.service || true
  enable_service_safe pipewire-pulse.service || true
  enable_service_safe wireplumber.service || true
else
  msg "PipeWire no tiene unidades system-wide; habilitando unidades de usuario (loginctl enable-linger + --user enable)..."
  sudo loginctl enable-linger "${USERNAME}" || true
  sudo -u "${USERNAME}" bash -c "systemctl --user enable --now pipewire.socket wireplumber.service pipewire-pulse.socket || true"
fi

enable_service_safe sddm.service || true

# Copiar configs (si existen)
if [[ -d "${REPO_DIR}/configs/wayland" ]]; then
  msg "Instalando configs de ${REPO_DIR}/configs/wayland -> ${HOME}/.config"
  mkdir -p "${HOME}/.config"
  cp -r "${REPO_DIR}/configs/wayland/"* "${HOME}/.config/" 2>/dev/null || true
  sudo chown -R "${USERNAME}":"${USERNAME}" "${HOME}/.config" || true
else
  warn "No encontré ${REPO_DIR}/configs/wayland — omito copia de configs."
fi

# Brave: repo -> AUR (brave-bin)
if pacman -Si brave >/dev/null 2>&1; then
  msg "Brave encontrado en repositorios; instalando..."
  sudo pacman -S --noconfirm brave || warn "Fallo instalando brave desde repo."
else
  warn "Brave no en repos oficiales. Intentando instalar brave-bin desde AUR con paru."
  if ! command -v paru >/dev/null 2>&1; then
    msg "Paru no instalado; lo compilo como ${USERNAME} (requiere base-devel, git)..."
    sudo -u "${USERNAME}" bash -c '
      set -e
      cd /tmp
      rm -rf paru || true
      git clone https://aur.archlinux.org/paru.git
      cd paru
      makepkg -si --noconfirm || true
    '
  fi
  if command -v paru >/dev/null 2>&1; then
    sudo -u "${USERNAME}" paru -S --noconfirm brave-bin || warn "Fallo instalando brave-bin con paru; instala manualmente."
  else
    warn "No quedó paru instalado; instala Brave manualmente o instala un AUR helper."
  fi
fi

msg "phase2-postinstall COMPLETADO. Revisa advertencias anteriores y reinicia si acabas de hacer cambios críticos (grub, microcode)."

# Aviso final sobre entorno
if ! $systemd_running ; then
  warn "Nota: systemd NO estaba corriendo cuando lanzaste este script. Algunas acciones (arranque inmediato de servicios) se omitieron/pospusieron."
  msg "Si estabas en live/chroot, desmonta e inicia tu sistema instalado, luego corre este script (sin --target) como usuario normal para finalizar configuraciones de Hyprland / AUR."
fi

exit 0
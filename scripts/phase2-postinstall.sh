#!/usr/bin/env bash
set -euo pipefail

# phase2-postinstall.sh - Instala Hyprland + Waybar + Alacritty + Brave (opcional AUR)
# Ejecutar como usuario normal en el sistema instalado (NO en el live ISO).

# Ajustes
USERNAME="${SUDO_USER:-${USER}}"
REPO_DIR="${HOME}/prueba-arch"   # ajusta si tu repo está en otra ruta

msg(){ printf "\e[1;32m[+]\e[0m %s\n" "$*"; }
warn(){ printf "\e[1;33m[-]\e[0m %s\n" "$*"; }
err(){ printf "\e[1;31m[!]\e[0m %s\n" "$*"; }

# Detectar si systemd está corriendo (true cuando estamos en el sistema real arrancado con systemd)
systemd_running=false
if [[ -d /run/systemd/system ]]; then
  systemd_running=true
fi

msg "Usuario objetivo: ${USERNAME}"
msg "Actualizando sistema..."
sudo pacman -Syu --noconfirm

msg "Instalando paquetes principales..."
sudo pacman -S --needed --noconfirm \
    hyprland wayland-protocols wayland xorg-xwayland \
    waybar alacritty sddm sddm-kcm \
    pipewire wireplumber pipewire-pulse \
    polkit-gnome blueman bluez bluez-utils \
    ntp networkmanager base-devel git

# Función para habilitar/arrancar servicios de forma segura
enable_service_safe() {
  svc_name="$1"
  # Si systemd está corriendo, intentar enable --now
  if $systemd_running; then
    if systemctl list-unit-files "$svc_name" >/dev/null 2>&1 || systemctl status "$svc_name" >/dev/null 2>&1; then
      msg "Habilitando y arrancando ${svc_name} (systemd activo)..."
      sudo systemctl enable --now "$svc_name" || warn "No se pudo habilitar/arrancar ${svc_name}"
    else
      warn "Servicio ${svc_name} no encontrado. ¿Está instalado el paquete correspondiente?"
    fi
  else
    # systemd no está corriendo (ej. estás en live/chroot). Solo intentar enable (podría crear symlink) o avisar.
    if sudo pacman -Qi "${svc_name%%.*}" >/dev/null 2>&1 || systemctl list-unit-files "$svc_name" >/dev/null 2>&1; then
      msg "Systemd no está corriendo; crearé la habilitación si es posible (sin arrancar) para ${svc_name}..."
      # Intentar solo enable (puede que falle si systemd no está activo; capturamos)
      if sudo systemctl enable "$svc_name" >/dev/null 2>&1; then
        msg "Habilitación de ${svc_name} creada (se aplicará al arrancar)."
      else
        warn "No se pudo crear la habilitación de ${svc_name} ahora. Habilítalo manualmente tras reiniciar: sudo systemctl enable --now ${svc_name}"
      fi
    else
      warn "Parece que el paquete para ${svc_name} no está instalado; omitiendo habilitación."
    fi
  fi
}

# Habilitar servicios importantes (bluetooth solo si bluez instalado)
msg "Comprobando/creando grupo bluetooth..."
if ! getent group bluetooth >/dev/null 2>&1; then
  sudo groupadd bluetooth && msg "Grupo 'bluetooth' creado."
else
  msg "Grupo 'bluetooth' ya existe."
fi
sudo usermod -aG bluetooth "${USERNAME}" || warn "No se pudo añadir ${USERNAME} al grupo bluetooth"

# Habilitar/arrancar servicios con comprobaciones
enable_service_safe NetworkManager

if pacman -Qs bluez >/dev/null 2>&1; then
  enable_service_safe bluetooth.service || true
fi

# Para pipewire intentamos habilitar los servicios más comunes
if pacman -Qs pipewire >/dev/null 2>&1; then
  # wireplumber suele administrar pipewire, intentamos habilitar ambos
  enable_service_safe pipewire.service || true
  enable_service_safe pipewire-pulse.service || true
  enable_service_safe wireplumber.service || true
else
  warn "pipewire no parece instalado correctamente (pacman no lo detecta). Verifica la instalación."
fi

# SDDM
enable_service_safe sddm.service || true

# Copiar configs si existen en el repo
if [[ -d "${REPO_DIR}/configs/wayland" ]]; then
  msg "Instalando configs de Wayland desde ${REPO_DIR}/configs/wayland..."
  mkdir -p "${HOME}/.config"
  cp -r "${REPO_DIR}/configs/wayland/"* "${HOME}/.config/" 2>/dev/null || true
  sudo chown -R "${USERNAME}":"${USERNAME}" "${HOME}/.config" || true
else
  warn "No encuentro ${REPO_DIR}/configs/wayland — omitiendo copia de configs."
fi

# ------------------------------------------------------------
# Manejo de Brave (repos oficiales o AUR)
# ------------------------------------------------------------
if pacman -Si brave >/dev/null 2>&1; then
  msg "Brave disponible en repositorios. Instalando..."
  sudo pacman -S --noconfirm brave || warn "Fallo instalando brave desde repositorios."
else
  warn "Brave no detectado en repos oficiales. Intentando instalar desde AUR (brave-bin) usando paru."
  # Si ya existe paru, usarlo; si no, intentar crear paru automáticamente
  if command -v paru >/dev/null 2>&1; then
    msg "Usando paru para instalar brave-bin..."
    paru -S --noconfirm brave-bin || warn "Fallo instalando brave-bin con paru. Instálalo manualmente."
  else
    msg "Instalando temporalmente 'paru' (requerirá base-devel y git)..."
    # Asegurarnos de que base-devel y git estén instalados (ya pedimos base-devel arriba)
    # Construir paru como el usuario normal
    sudo -u "${USERNAME}" bash -c '
      set -e
      cd /tmp
      rm -rf paru
      git clone https://aur.archlinux.org/paru.git
      cd paru
      makepkg -si --noconfirm
    ' || warn "No se pudo compilar/instalar paru automáticamente. Instala paru manualmente y luego brave-bin (ej: paru -S brave-bin)."
    if command -v paru >/dev/null 2>&1; then
      msg "Paru instalado; ahora instalando brave-bin..."
      paru -S --noconfirm brave-bin || warn "Fallo instalando brave-bin con paru."
    else
      warn "Paru no quedó instalado. Instala Brave manualmente (ej. con paru/yay o desde la pagina oficial)."
    fi
  fi
fi

msg "phase2-postinstall: tareas completadas (o reportadas)."

if ! $systemd_running ; then
  warn "Atención: systemd NO está corriendo en este entorno. Algunas acciones (arrancar servicios) se omitieron."
  msg "Instrucción: reinicia en tu sistema instalado y corre: sudo systemctl enable --now NetworkManager bluetooth pipewire.service pipewire-pulse.service wireplumber.service sddm"
fi

msg "Finalizado. Reinicia y prueba iniciar sesión en SDDM -> sesión Hyprland."
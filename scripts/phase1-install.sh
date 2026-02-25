#!/usr/bin/env bash
set -euo pipefail

# phase1-install.sh (actualizado)
# Instalación mínima desde live ISO. Ejecutar como root en el entorno live.
# Incluye: grub + microcode/drivers para Intel i3-2330M (HD 3000).
# NOTA: Ajusta valores si tu particionado es diferente.

# Valores por defecto
DEFAULT_DEV="/dev/sda"
DEFAULT_MOUNT="/mnt"
DEFAULT_LOCALE="es_CO.UTF-8"
DEFAULT_HOST="archbox"
DEFAULT_USER="jufedev"

# Funciones
msg(){ printf "\e[1;32m[+]\e[0m %s\n" "$*"; }
warn(){ printf "\e[1;33m[-]\e[0m %s\n" "$*"; }
err(){ printf "\e[1;31m[!]\e[0m %s\n" "$*"; }

# Chequeos básicos
if [[ $EUID -ne 0 ]]; then
    err "Este script debe ejecutarse como root desde el ISO live."
    exit 1
fi

if ! command -v pacstrap >/dev/null 2>&1; then
    err "No encuentro pacstrap. Ejecuta esto desde el ambiente live de Arch."
    exit 1
fi

# Preguntas al usuario (valores por defecto)
read -rp "Dispositivo (ej. /dev/sda) [${DEFAULT_DEV}]: " DEV_DISK
DEV_DISK=${DEV_DISK:-$DEFAULT_DEV}

DEFAULT_ROOT_PART="${DEV_DISK}1"
read -rp "Partición raíz (ej ${DEFAULT_ROOT_PART}) [${DEFAULT_ROOT_PART}]: " ROOT_PART
ROOT_PART=${ROOT_PART:-$DEFAULT_ROOT_PART}

read -rp "Punto de montaje [${DEFAULT_MOUNT}]: " MOUNTPOINT
MOUNTPOINT=${MOUNTPOINT:-$DEFAULT_MOUNT}

read -rp "Hostname [${DEFAULT_HOST}]: " HOSTNAME
HOSTNAME=${HOSTNAME:-$DEFAULT_HOST}

read -rp "Usuario a crear [${DEFAULT_USER}]: " USERNAME
USERNAME=${USERNAME:-$DEFAULT_USER}

# Pedir contraseñas (no mostrarlas por pantalla)
read -s -rp "Contraseña para root: " ROOT_PASS
echo
read -s -rp "Contraseña para ${USERNAME}: " USER_PASS
echo

msg "Particionado/format/etc: este script asume que ${ROOT_PART} ya existe y formateado."
msg "Si necesitas particionar o formatear, hazlo antes y vuelve a ejecutar."

# Montar la partición raíz
msg "Montando ${ROOT_PART} en ${MOUNTPOINT}..."
mkdir -p "${MOUNTPOINT}"
mount "${ROOT_PART}" "${MOUNTPOINT}"

# --- Evitar error mkinitcpio: crear /etc/vconsole.conf dentro del target ANTES de pacstrap ---
msg "Creando ${MOUNTPOINT}/etc/vconsole.conf para evitar error de mkinitcpio..."
mkdir -p "${MOUNTPOINT}/etc"
cat > "${MOUNTPOINT}/etc/vconsole.conf" <<'EOF'
KEYMAP=la-latin1
FONT=lat9w-16
EOF
chmod 644 "${MOUNTPOINT}/etc/vconsole.conf"

# --- Detectar CPU vendor y elegir microcode (intel/amd) ---
CPU_VENDOR=$(grep -m1 'vendor_id' /proc/cpuinfo | awk '{print $3}' || true)
MICROCODE_PKG="intel-ucode"
if [[ -n "${CPU_VENDOR}" && "${CPU_VENDOR,,}" == *"authenticamd"* ]] || [[ "${CPU_VENDOR,,}" == *"amd"* ]]; then
  MICROCODE_PKG="amd-ucode"
fi
msg "CPU vendor detectado: '${CPU_VENDOR:-desconocido}' -> instalaré '${MICROCODE_PKG}'."

# Paquetes base y extras (añadí grub y drivers Intel HD3000)
msg "Instalando paquetes base y utilidades (incluyendo grub y drivers Intel para i3-2330M)..."
pacstrap "${MOUNTPOINT}" base linux linux-firmware sudo vim networkmanager \
    grub ${MICROCODE_PKG} mesa libva-intel-driver libva-utils xf86-video-intel

# Fstab
msg "Generando fstab..."
genfstab -U "${MOUNTPOINT}" >> "${MOUNTPOINT}/etc/fstab"

# Crear archivo temporal con contraseñas dentro del target (modo seguro)
msg "Creando archivo temporal de contraseñas en el sistema objetivo (se eliminará dentro del chroot)..."
PWFILE="${MOUNTPOINT}/root/pwfile"
umask 077
printf '%s\n' "root:${ROOT_PASS}" "${USERNAME}:${USER_PASS}" > "${PWFILE}"
chmod 600 "${PWFILE}"
unset ROOT_PASS USER_PASS

# Chroot: configurar idioma, hostname, usuario y limpiar
msg "Configurando sistema dentro del chroot (hostname, locale, usuarios)..."
arch-chroot "${MOUNTPOINT}" /bin/bash -e <<EOF
set -e

# hostname y zona horaria
echo '${HOSTNAME}' > /etc/hostname
ln -sf /usr/share/zoneinfo/America/Bogota /etc/localtime
hwclock --systohc

# locale
sed -i '/^#${DEFAULT_LOCALE}/s/^#//' /etc/locale.gen || true
locale-gen
echo 'LANG=${DEFAULT_LOCALE}' > /etc/locale.conf

# Asegurar vconsole.conf (redundancia)
if [[ ! -f /etc/vconsole.conf ]]; then
  cat > /etc/vconsole.conf <<'VCON'
KEYMAP=la-latin1
FONT=lat9w-16
VCON
fi

# Crear usuario si no existe, luego aplicar contraseñas desde /root/pwfile
if id -u ${USERNAME} &>/dev/null; then
  chpasswd < /root/pwfile || true
else
  useradd -m -G wheel -s /bin/bash ${USERNAME}
  chpasswd < /root/pwfile
fi
# Eliminar el archivo de contraseñas por seguridad
rm -f /root/pwfile

# Habilitar NetworkManager
systemctl enable NetworkManager

# Regenerar initramfs por si hay cambios
if command -v mkinitcpio >/dev/null 2>&1; then
  mkinitcpio -P || true
fi

EOF

# Asegurarse de eliminar el pwfile si por alguna razón quedó
if [[ -f "${PWFILE}" ]]; then
  rm -f "${PWFILE}" || warn "No se pudo eliminar ${PWFILE} desde el host; revisa manualmente."
fi

msg "Fase 1 completada. Desmonta y reinicia para continuar con la fase 2 (ejecutar como usuario normal)."
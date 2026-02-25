#!/usr/bin/env bash
set -euo pipefail

# phase1-install.sh
# Instalación mínima desde live ISO. Ejecutar como root en el entorno live.
# NOTA: Ajusta DEV_DISK / particiones según tu hardware antes de ejecutar.

DEV_DISK="/dev/sda"
ROOT_PART="${DEV_DISK}1"
MOUNTPOINT="/mnt"
LOCALE="es_CO.UTF-8"
HOSTNAME="archbox"

# Mensajes
msg(){ printf "\e[1;32m[+]\e[0m %s\n" "$*"; }
err(){ printf "\e[1;31m[!]\e[0m %s\n" "$*"; }

# Comprobaciones básicas
if [[ $EUID -ne 0 ]]; then
    err "Este script debe ejecutarse como root desde el ISO live."
    exit 1
fi

if ! command -v pacstrap >/dev/null 2>&1; then
    err "No encuentro pacstrap. Ejecuta esto desde el ambiente live de Arch."
    exit 1
fi

msg "Particionado/format/etc: este script asume que ${ROOT_PART} ya existe y formateado."
msg "Si necesitas particionar, hazlo antes y vuelve a ejecutar."

# --- Formateo y montaje (opcional; descomenta si quieres formatear) ---
# msg "Formateando ${ROOT_PART} como ext4..."
# mkfs.ext4 -F "${ROOT_PART}"

msg "Montando ${ROOT_PART} en ${MOUNTPOINT}..."
mount "${ROOT_PART}" "${MOUNTPOINT}"

# Instalar base
msg "Instalando paquetes base y utilidades..."
pacstrap "${MOUNTPOINT}" base linux linux-firmware sudo vim networkmanager

# Fstab
msg "Generando fstab..."
genfstab -U "${MOUNTPOINT}" >> "${MOUNTPOINT}/etc/fstab"

# Chroot mínimo: configurar idioma, hostname, usuario (ejecutado dentro del chroot)
msg "Configurando sistema dentro del chroot (hostname, locale)."
arch-chroot "${MOUNTPOINT}" /bin/bash -c "
set -e

# hostname y zona horaria
echo '${HOSTNAME}' > /etc/hostname
ln -sf /usr/share/zoneinfo/America/Bogota /etc/localtime
hwclock --systohc

# locale
sed -i '/^#${LOCALE}/s/^#//' /etc/locale.gen || true
locale-gen
echo 'LANG=${LOCALE}' > /etc/locale.conf

# --- Evitar error de mkinitcpio: crear /etc/vconsole.conf si no existe ---
cat > /etc/vconsole.conf <<'VCON'
KEYMAP=la-latin1
FONT=lat9w-16
VCON

# Regenerar initramfs (asegúrate de que el paquete linux ya esté instalado)
mkinitcpio -P

# Usuario por defecto (ajusta nombre y contraseña después del primer arranque)
useradd -m -G wheel -s /bin/bash jufedev || true
echo 'jufedev:changeme' | chpasswd

# Habilitar network
systemctl enable NetworkManager
" enable NetworkManager
"

msg "Fase 1 completada. Desmonta y reinicia para continuar con la fase 2 (ejecutar como usuario normal)."
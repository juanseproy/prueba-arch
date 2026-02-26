#!/usr/bin/env bash
set -euo pipefail

# install.sh
# Phase 1: Arch Linux base installation from live ISO (run as root).
# Supports BIOS legacy and UEFI, auto-detects disk (/dev/sda or /dev/nvme*).
# Assumes manual partitioning, formatting, and mounting already done:
#   BIOS : /mnt  → root partition
#   UEFI : /mnt  → root partition  +  /mnt/boot/efi → EFI partition (vfat)
# Assumes repo already cloned to /mnt/home/prueba-arch from the live environment.
# Run: bash /mnt/home/prueba-arch/scripts/install.sh

# ─── Constants ────────────────────────────────────────────────────────────────
REPO_DIR="/home/prueba-arch"
TARGET_MNT="/mnt"
DEFAULT_LOCALE="en_US.UTF-8"
DEFAULT_KEYMAP="us"
DEFAULT_HOSTNAME="jufe"
DEFAULT_USERNAME="jufedev"

# ─── Helpers ──────────────────────────────────────────────────────────────────
msg()  { printf "\e[1;32m[+]\e[0m %s\n" "$*"; }
warn() { printf "\e[1;33m[-]\e[0m %s\n" "$*"; }
err()  { printf "\e[1;31m[!]\e[0m %s\n" "$*"; exit 1; }

# ─── Guards ───────────────────────────────────────────────────────────────────
[ -d /run/archiso ] || err "Este script debe ejecutarse desde el live ISO de Arch."
[ "$EUID" -eq 0 ]  || err "Debes ejecutar este script como root."
mountpoint -q "${TARGET_MNT}" || err "/mnt no está montado. Monta tu partición raíz en /mnt primero."
[ -d "${TARGET_MNT}${REPO_DIR}" ] || err "Repo no encontrado en ${TARGET_MNT}${REPO_DIR}. Clónalo manualmente primero."

msg "Entorno live ISO detectado. Iniciando Phase 1: instalación base."

# ─── Detect firmware (UEFI vs BIOS) ──────────────────────────────────────────
if [ -d /sys/firmware/efi ]; then
  UEFI=true
  msg "Firmware: UEFI detectado."
  # Verify EFI partition is mounted
  mountpoint -q "${TARGET_MNT}/boot/efi" || err "UEFI detectado pero ${TARGET_MNT}/boot/efi no está montado. Monta tu partición EFI (vfat) ahí primero."
else
  UEFI=false
  msg "Firmware: BIOS/Legacy detectado."
fi

# ─── Detect primary disk ──────────────────────────────────────────────────────
detect_disk() {
  # Prefer NVMe, fall back to sda; skip loop/optical devices
  local candidate
  candidate=$(lsblk -dno NAME,TYPE | awk '$2=="disk"{print $1}' | grep -E '^nvme|^sd' | head -1)
  if [[ -n "$candidate" ]]; then
    echo "/dev/${candidate}"
  else
    echo ""
  fi
}

DETECTED_DISK=$(detect_disk)
if [[ -n "$DETECTED_DISK" ]]; then
  read -rp "Disco detectado: ${DETECTED_DISK}. Usar este disco para GRUB? [S/n]: " DISK_CONFIRM
  if [[ "${DISK_CONFIRM,,}" == "n" ]]; then
    read -rp "Introduce el disco manualmente (ej: /dev/sda o /dev/nvme0n1): " INSTALL_DISK
  else
    INSTALL_DISK="$DETECTED_DISK"
  fi
else
  warn "No se pudo auto-detectar el disco."
  read -rp "Introduce el disco manualmente (ej: /dev/sda o /dev/nvme0n1): " INSTALL_DISK
fi
[[ -b "$INSTALL_DISK" ]] || err "Disco ${INSTALL_DISK} no existe o no es un dispositivo de bloque."
msg "Disco seleccionado para GRUB: ${INSTALL_DISK}"

# ─── User inputs ──────────────────────────────────────────────────────────────
read -rp "Hostname [${DEFAULT_HOSTNAME}]: " HOSTNAME
HOSTNAME=${HOSTNAME:-$DEFAULT_HOSTNAME}

read -rp "Username [${DEFAULT_USERNAME}]: " USERNAME
USERNAME=${USERNAME:-$DEFAULT_USERNAME}

read -s -rp "Contraseña root: " ROOT_PASS; echo
read -s -rp "Contraseña para ${USERNAME}: " USER_PASS; echo

# ─── Detect CPU → microcode + GPU drivers ────────────────────────────────────
CPU_VENDOR=$(grep -m1 'vendor_id' /proc/cpuinfo | awk '{print $3}' || echo "unknown")
MICROCODE_PKG=""
DRIVER_PKGS=""

if [[ "${CPU_VENDOR,,}" == *"intel"* ]]; then
  msg "CPU Intel detectado (laptop i3). Microcode + drivers Mesa/Vulkan Intel."
  MICROCODE_PKG="intel-ucode"
  # xf86-video-intel ELIMINADO: el driver modesetting es superior en Wayland/Hyprland
  # libva-intel-driver: VA-API para i3-2330M (generación Sandy Bridge)
  DRIVER_PKGS="mesa vulkan-intel lib32-mesa lib32-vulkan-intel libva-intel-driver libva-utils"
elif [[ "${CPU_VENDOR,,}" == *"authenticamd"* || "${CPU_VENDOR,,}" == *"amd"* ]]; then
  msg "CPU AMD detectado (Ryzen 7 5700G desktop). Microcode + drivers Mesa/Vulkan Radeon."
  MICROCODE_PKG="amd-ucode"
  # El Ryzen 5700G tiene iGPU RDNA2: vulkan-radeon es el driver correcto
  DRIVER_PKGS="mesa vulkan-radeon lib32-mesa lib32-vulkan-radeon libva-mesa-driver"
else
  warn "Vendor CPU desconocido. Skipping drivers/microcode específicos; instálalos manualmente."
fi

# ─── Multilib en live (para lib32-* en pacstrap) ─────────────────────────────
msg "Habilitando repositorio multilib en live ISO..."
sed -i "/\[multilib\]/,/Include/"'s/^#//' /etc/pacman.conf
pacman -Syy --noconfirm

# ─── Pacstrap ────────────────────────────────────────────────────────────────
msg "Instalando sistema base con pacstrap..."
# shellcheck disable=SC2086
pacstrap "${TARGET_MNT}" \
  base linux linux-firmware \
  vim sudo networkmanager \
  grub efibootmgr \
  base-devel git \
  ${MICROCODE_PKG} ${DRIVER_PKGS}

# ─── fstab ───────────────────────────────────────────────────────────────────
msg "Generando fstab..."
genfstab -U "${TARGET_MNT}" >> "${TARGET_MNT}/etc/fstab"

# ─── Secure password handoff ─────────────────────────────────────────────────
PWFILE="${TARGET_MNT}/root/.pwfile"
umask 077
printf '%s\n' "root:${ROOT_PASS}" "${USERNAME}:${USER_PASS}" > "${PWFILE}"
chmod 600 "${PWFILE}"
unset ROOT_PASS USER_PASS

# ─── Enable multilib en el target antes del chroot ───────────────────────────
msg "Habilitando multilib en el sistema instalado..."
sed -i "/\[multilib\]/,/Include/"'s/^#//' "${TARGET_MNT}/etc/pacman.conf"

# ─── Chroot: configuración del sistema ───────────────────────────────────────
msg "Entrando al chroot para configurar el sistema..."

arch-chroot "${TARGET_MNT}" /bin/bash -e <<CHROOT
set -e

# Timezone
ln -sf /usr/share/zoneinfo/America/Bogota /etc/localtime
hwclock --systohc

# Locale
sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
sed -i 's/^#es_CO.UTF-8 UTF-8/es_CO.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=${DEFAULT_LOCALE}" > /etc/locale.conf

# Keymap (escrito en el target, no en el live)
echo "KEYMAP=${DEFAULT_KEYMAP}" > /etc/vconsole.conf

# Hostname
echo "${HOSTNAME}" > /etc/hostname
cat > /etc/hosts <<HOSTS
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}
HOSTS

# Usuario y contraseñas
useradd -m -G wheel -s /bin/bash "${USERNAME}"
chpasswd < /root/.pwfile
rm -f /root/.pwfile

# Sudoers: habilitar grupo wheel
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# Actualizar base de datos de paquetes (multilib ya habilitado en pacman.conf)
pacman -Syy --noconfirm

# Initramfs
mkinitcpio -P

# GRUB
$(if $UEFI; then
  echo 'grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB --recheck'
else
  echo "grub-install --target=i386-pc ${INSTALL_DISK}"
fi)
grub-mkconfig -o /boot/grub/grub.cfg

# NetworkManager
systemctl enable NetworkManager
CHROOT

msg "Phase 1 completa."
msg "Pasos siguientes:"
msg "  1. umount -R /mnt"
msg "  2. Retira el ISO y reinicia: reboot"
msg "  3. Inicia sesión como ${USERNAME}"
msg "  4. Ejecuta: bash ${REPO_DIR}/scripts/postinstall.sh"
exit 0
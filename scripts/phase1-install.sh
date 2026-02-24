#!/usr/bin/env bash
set -euo pipefail

# phase1-install.sh
# Instalación base de Arch Linux desde live ISO.
# Ejecutar como root.
# Ajusta las variables siguientes según tu hardware y preferencias.

# === CONFIGURACIÓN ===
DEV_DISK="/dev/sda"               # Disco completo (sin número)
DEV_PART="${DEV_DISK}1"           # Partición raíz (asumimos una sola partición)
MOUNTPOINT="/mnt"
USERNAME="jufedev"
USER_SHELL="/bin/bash"
HOSTNAME="jufe"
TIMEZONE="America/Bogota"
LOCALE="en_US.UTF-8"
KEYMAP="us"

# Paquetes adicionales a instalar (separados por espacios)
PACKAGES="base linux linux-headers linux-firmware vim sudo grub networkmanager"

# Si el sistema es UEFI, necesitamos efibootmgr y el target adecuado.
# La detección se hará dentro del chroot, pero podemos añadir efibootmgr ya.
# Lo incluimos siempre, no estorba en BIOS.
PACKAGES="$PACKAGES efibootmgr"

# === FUNCIONES ===
msg() {
    echo "==> $*"
}

error() {
    echo "Error: $*" >&2
    exit 1
}

# === COMPROBACIONES PREVIAS ===
msg "Verificando que $MOUNTPOINT esté montado..."
if ! mountpoint -q "$MOUNTPOINT"; then
    error "$MOUNTPOINT no está montado. Monta la partición (ej: mount $DEV_PART $MOUNTPOINT) y vuelve a ejecutar."
fi

msg "Verificando que la partición montada sea $DEV_PART..."
if ! findmnt "$MOUNTPOINT" | grep -q "$DEV_PART"; then
    error "La partición montada en $MOUNTPOINT no es $DEV_PART. Revisa las variables DEV_DISK/DEV_PART."
fi

# === CONTRASEÑAS ===
: "${ROOT_PASS:=}"
: "${USER_PASS:=}"

if [ -z "$ROOT_PASS" ]; then
    read -s -p "Contraseña para root: " ROOT_PASS
    echo
fi

if [ -z "$USER_PASS" ]; then
    read -s -p "Contraseña para $USERNAME: " USER_PASS
    echo
fi

# === INSTALACIÓN BASE ===
msg "Instalando paquetes base con pacstrap..."
pacstrap -K "$MOUNTPOINT" $PACKAGES

msg "Generando fstab..."
genfstab -U "$MOUNTPOINT" >> "$MOUNTPOINT/etc/fstab"

# === CONFIGURACIÓN DENTRO DEL CHROOT ===
msg "Configurando sistema en el chroot..."
arch-chroot "$MOUNTPOINT" /bin/bash <<EOF
set -euo pipefail

# Zona horaria y reloj
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

# Locales
echo "LANG=$LOCALE" > /etc/locale.conf
sed -i 's/^#$LOCALE/$LOCALE/' /etc/locale.gen
locale-gen

# Teclado
echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf

# Hostname y hosts
echo "$HOSTNAME" > /etc/hostname
cat > /etc/hosts <<EOL
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
EOL

# Contraseña de root
echo "root:$ROOT_PASS" | chpasswd

# Crear usuario y contraseña
useradd -m -G wheel -s $USER_SHELL $USERNAME
echo "$USERNAME:$USER_PASS" | chpasswd

# Habilitar sudo para el grupo wheel
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# Instalación de GRUB (detección automática UEFI/BIOS)
if [ -d /sys/firmware/efi ]; then
    echo "Sistema UEFI detectado, instalando GRUB para UEFI..."
    grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
else
    echo "Sistema BIOS detectado, instalando GRUB para MBR..."
    grub-install --target=i386-pc $DEV_DISK
fi

# Generar configuración de GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# Regenerar initramfs
mkinitcpio -P

# Habilitar NetworkManager para conectividad automática al inicio
systemctl enable NetworkManager

EOF

# === FIN ===
msg "Instalación base completada."
msg "Puedes desmontar las particiones con: umount -R $MOUNTPOINT"
msg "Luego reinicia con: reboot"
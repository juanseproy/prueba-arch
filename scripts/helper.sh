REPO_DIR="/home/prueba-arch"
REPO_DIR="/home/prueba-arch"
CONFIGS="${REPO_DIR}/configs/wayland"

msg()  { printf "\e[1;32m[+]\e[0m %s\n" "$*"; }

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
Set up:

Hyprland + Waybar + Alacritty + Brave


Folder Structure:

```
arch-install/
├── README.md
├── .gitignore
├── scripts/
│   ├── install.sh
│   └── postinstall.sh
└── configs/
    └── wayland/
        ├── alacritty/
        │   └── alacritty.toml
        ├── hypr/
        │   └── hyprland.conf
        ├── sddm-theme/
        │   ├── custom.conf
        ├── sddm.conf.d/
        │   ├── silent-custom.conf
        │   └── wayland.conf
        ├── waybar/
        │   ├── scripts/
        │   │   └── battery.sh
        │   ├── config
        │   └── style.css
        └── wlogout/
            ├── config
            ├── layout
            └── style.css
```

Compatible Processors:
- i3-2330M
- Ryzen 7 5700G


Other Repos (credits):
- https://github.com/uiriansan/SilentSDDM
- https://github.com/HyDE-Project/HyDE?tab=readme-ov-file
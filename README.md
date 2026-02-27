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
        ├── sddm.conf.d/
        │   ├── silent-custom.conf
        │   └── wayland.conf
        ├── waybar/
        │   ├── scripts/
        │   │   └── battery.sh
        │   ├── config
        │   └── style.css
        └── wlogout/
            ├── layout
            └── style.css
```

Compatible Processors:
- i3-2330M
- Ryzen 7 5700G
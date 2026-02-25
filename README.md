Set up:

Hyprland + Waybar + Alacritty + Brave


Folder Structure:

```
arch-install-automated/
├── README.md
├── .gitignore
├── scripts/
│   ├── phase1-install.sh
│   └── phase2-desktop.sh
└── configs/
    └── wayland/
        ├── hyprland/
        │   └── hyprland.conf
        ├── waybar/
        │   ├── config
        │   └── style.css
        ├── alacritty/
        │   └── alacritty.yml
        └── sddm.conf.d/
            └── wayland.conf
```

Compatible Processors:
- i3-2330M
- Ryzen 7 5700G
#!/usr/bin/env bash
# battery.sh — Muestra "Charged" si es PC de mesa o laptop al 100%
# Salida JSON para waybar custom module con return-type=json

BATTERY_PATH=""
for p in /sys/class/power_supply/BAT*; do
  [ -d "$p" ] && BATTERY_PATH="$p" && break
done

# ── Sin batería: es PC de mesa ────────────────────────────────────────────────
if [ -z "$BATTERY_PATH" ]; then
  echo '{"text": "󱐋  Charged", "tooltip": "PC de mesa — sin batería", "class": "charged"}'
  exit 0
fi

CAPACITY=$(cat "${BATTERY_PATH}/capacity" 2>/dev/null || echo "?")
STATUS=$(cat "${BATTERY_PATH}/status" 2>/dev/null || echo "Unknown")

# Seleccionar ícono según nivel
if [ "$CAPACITY" = "?" ]; then
  ICON="󰂑"
elif [ "$CAPACITY" -ge 90 ]; then ICON="󰁹"
elif [ "$CAPACITY" -ge 75 ]; then ICON="󰂁"
elif [ "$CAPACITY" -ge 60 ]; then ICON="󰁿"
elif [ "$CAPACITY" -ge 40 ]; then ICON="󰁽"
elif [ "$CAPACITY" -ge 20 ]; then ICON="󰁻"
else ICON="󰁺"
fi

# Laptop al 100% o cargando al tope
if [ "$CAPACITY" -ge 100 ] || { [ "$STATUS" = "Full" ]; }; then
  echo '{"text": "󱐋  Charged", "tooltip": "Batería completa ('"$CAPACITY"'%)", "class": "charged"}'
  exit 0
fi

# En carga
if [ "$STATUS" = "Charging" ]; then
  echo "{\"text\": \"󰂄  ${CAPACITY}%\", \"tooltip\": \"Cargando — ${CAPACITY}%\", \"class\": \"charging\"}"
  exit 0
fi

# En descarga
CSS_CLASS="normal"
[ "$CAPACITY" -le 20 ] && CSS_CLASS="low"
[ "$CAPACITY" -le 10 ] && CSS_CLASS="critical"

echo "{\"text\": \"${ICON}  ${CAPACITY}%\", \"tooltip\": \"${STATUS} — ${CAPACITY}%\", \"class\": \"${CSS_CLASS}\"}"
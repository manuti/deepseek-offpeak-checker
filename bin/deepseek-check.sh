#!/usr/bin/env bash
#
# deepseek-check.sh - Comprueba si es hora valle para DeepSeek
#
# Uso:
#   deepseek-check                Muestra el estado (0 = valle, 1 = pico)
#   deepseek-check --quiet        Sin salida; solo código de salida
#   deepseek-check --raw          Ídem, pensado para usarse desde scripts
#   deepseek-check --help         Muestra esta ayuda
#
# Configuración: variables de entorno o archivo ~/.deepseekrc
#   PEAK_START_MORNING    Inicio de la franja pico de mañana   (9)
#   PEAK_END_MORNING      Fin de la franja pico de mañana      (12)
#   PEAK_START_AFTERNOON  Inicio de la franja pico de tarde    (14)
#   PEAK_END_AFTERNOON    Fin de la franja pico de tarde       (18)
#   TIMEZONE              Zona horaria de referencia           (Asia/Shanghai)
#   NO_COLOR              Cualquier valor desactiva el color
#
# Códigos de salida: 0 = valle · 1 = pico · 2 = error
# Inspirado en https://deepakness.com/deepseek

set -u

# ── Carga de configuración ─────────────────────────────────────────────
CONFIG_FILE="${DEEPSEEK_RC:-$HOME/.deepseekrc}"
if [ -n "$CONFIG_FILE" ] && [ -f "$CONFIG_FILE" ]; then
    # shellcheck disable=SC1090
    . "$CONFIG_FILE"
fi

# ── Valores por defecto ────────────────────────────────────────────────
: "${PEAK_START_MORNING:=9}"
: "${PEAK_END_MORNING:=12}"
: "${PEAK_START_AFTERNOON:=14}"
: "${PEAK_END_AFTERNOON:=18}"
: "${TIMEZONE:=Asia/Shanghai}"

# ── Validación básica de la configuración ──────────────────────────────
is_hour() { [[ "$1" =~ ^[0-9]{1,2}$ ]] && [ "$1" -ge 0 ] && [ "$1" -le 23 ]; }
for v in PEAK_START_MORNING PEAK_END_MORNING PEAK_START_AFTERNOON PEAK_END_AFTERNOON; do
    if ! is_hour "${!v}"; then
        echo "deepseek-check: $v='${!v}' no es válido (debe ser 0-23)" >&2
        exit 2
    fi
done

# ── Argumentos ─────────────────────────────────────────────────────────
case "${1:-}" in
    -h|--help)
        cat <<'EOF'
deepseek-check - Comprueba si es hora valle para DeepSeek

Uso:
  deepseek-check            Muestra el estado (0 = valle, 1 = pico)
  deepseek-check --quiet    Sin salida; solo código de salida
  deepseek-check --raw      Ídem, pensado para usarse desde scripts
  deepseek-check --help     Muestra esta ayuda

Configuración (variables de entorno o ~/.deepseekrc):
  PEAK_START_MORNING     Inicio pico de mañana      (9)
  PEAK_END_MORNING       Fin pico de mañana         (12)
  PEAK_START_AFTERNOON   Inicio pico de tarde       (14)
  PEAK_END_AFTERNOON     Fin pico de tarde          (18)
  TIMEZONE               Zona horaria de referencia (Asia/Shanghai)
  NO_COLOR               Cualquier valor desactiva el color

Códigos de salida: 0 = valle · 1 = pico · 2 = error
Referencia: https://deepakness.com/deepseek
EOF
        exit 0
        ;;
    --raw|--quiet) MODE="quiet" ;;
    "")            MODE="normal" ;;
    *)
        echo "deepseek-check: argumento desconocido: '$1' (usa --help)" >&2
        exit 2
        ;;
esac

# ── Hora y día en la zona horaria de referencia ────────────────────────
if ! HOUR=$(TZ="$TIMEZONE" date +%H 2>/dev/null) || \
   ! DAY=$(TZ="$TIMEZONE" date +%u 2>/dev/null) || \
   [ -z "$HOUR" ] || [ -z "$DAY" ]; then
    echo "deepseek-check: no se pudo obtener la hora en la zona '$TIMEZONE'" >&2
    exit 2
fi
# DAY: 1=lunes ... 7=domingo

# ── Determinación de pico/valle ────────────────────────────────────────
IS_PEAK=0
if [ "$DAY" -ge 1 ] && [ "$DAY" -le 5 ]; then
    if { [ "$HOUR" -ge "$PEAK_START_MORNING" ] && [ "$HOUR" -lt "$PEAK_END_MORNING" ]; } || \
       { [ "$HOUR" -ge "$PEAK_START_AFTERNOON" ] && [ "$HOUR" -lt "$PEAK_END_AFTERNOON" ]; }; then
        IS_PEAK=1
    fi
fi

# ── Modo silencioso: solo código de salida ─────────────────────────────
if [ "$MODE" = "quiet" ]; then
    exit "$IS_PEAK"
fi

# ── Salida formateada ──────────────────────────────────────────────────
if [ "$IS_PEAK" -eq 1 ]; then
    STATUS="HORA PICO"
    EMOJI="🔴"
else
    STATUS="HORA VALLE"
    if [ "$DAY" -ge 6 ]; then
        STATUS="HORA VALLE (fin de semana)"
    fi
    EMOJI="🟢"
fi

# Color solo si la salida es una terminal y NO_COLOR no está definido
COLOR=""
RESET=""
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    if [ "$IS_PEAK" -eq 1 ]; then
        COLOR='\033[0;31m'
    else
        COLOR='\033[0;32m'
    fi
    RESET='\033[0m'
fi

# Caja de ancho fijo: 46 columnas
BORDER="$(printf '═%.0s' {1..44})"
LINE_1="DeepSeek: $STATUS"
LINE_2="Pico: $(printf '%02d' "$PEAK_START_MORNING"):00-$(printf '%02d' "$PEAK_END_MORNING"):00 y $(printf '%02d' "$PEAK_START_AFTERNOON"):00-$(printf '%02d' "$PEAK_END_AFTERNOON"):00 BJT"

printf '%b%s%b\n' "$COLOR" "╔${BORDER}╗" "$RESET"
printf '%b║  %s %-37s  ║%b\n' "$COLOR" "$EMOJI" "$LINE_1" "$RESET"
printf '%b║  %-40s  ║%b\n' "$COLOR" "$LINE_2" "$RESET"
printf '%b%s%b\n' "$COLOR" "╚${BORDER}╝" "$RESET"

exit "$IS_PEAK"

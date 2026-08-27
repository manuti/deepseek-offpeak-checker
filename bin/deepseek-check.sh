#!/usr/bin/env bash
#
# deepseek-check.sh - Comprueba si es hora valle para DeepSeek
#
# Uso:
#   deepseek-check                Muestra el estado (0 = valle, 1 = pico)
#   deepseek-check --quiet        Sin salida; solo código de salida
#   deepseek-check --raw          Ídem, pensado para usarse desde scripts
#   deepseek-check -update        Comprueba en línea la política y guarda la fecha
#   deepseek-check --help         Muestra esta ayuda
#
# Configuración: variables de entorno o archivo ~/.deepseekrc
#   PEAK_START_MORNING     Inicio de la franja pico de mañana      (9)
#   PEAK_END_MORNING       Fin de la franja pico de mañana         (12)
#   PEAK_START_AFTERNOON   Inicio de la franja pico de tarde       (14)
#   PEAK_END_AFTERNOON     Fin de la franja pico de tarde          (18)
#   TIMEZONE               Zona horaria de referencia              (Asia/Shanghai)
#   NO_COLOR               Cualquier valor desactiva el color
#   POLICY_URL             URL de la política a comprobar          (https://api-docs.deepseek.com/quick_start/pricing/)
#   AUTO_CHECK_TTL_DAYS    Días de validez de la caché              (7; se refresca en segundo plano)
#   CACHE_DIR              Directorio de la caché                   (~/.cache/deepseek-check)
#
# Códigos de salida: 0 = valle · 1 = pico · 2 = error
#   Con -update: 0 = comprobada y coincide · 1 = cambios detectados · 2 = error
# Inspirado en https://deepakness.com/deepseek

set -u

# Ruta absoluta del propio script (para el refresco en segundo plano)
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

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
: "${POLICY_URL:=https://api-docs.deepseek.com/quick_start/pricing/}"
: "${AUTO_CHECK_TTL_DAYS:=7}"
: "${CACHE_DIR:=$HOME/.cache/deepseek-check}"
CACHE_FILE="$CACHE_DIR/policy.info"

# ── Validación básica de la configuración ──────────────────────────────
is_hour() { [[ "$1" =~ ^[0-9]{1,2}$ ]] && [ "$1" -ge 0 ] && [ "$1" -le 23 ]; }
for v in PEAK_START_MORNING PEAK_END_MORNING PEAK_START_AFTERNOON PEAK_END_AFTERNOON; do
    if ! is_hour "${!v}"; then
        echo "deepseek-check: $v='${!v}' no es válido (debe ser 0-23)" >&2
        exit 2
    fi
done
if ! [[ "$AUTO_CHECK_TTL_DAYS" =~ ^[0-9]+$ ]] || [ "$AUTO_CHECK_TTL_DAYS" -lt 1 ]; then
    echo "deepseek-check: AUTO_CHECK_TTL_DAYS='$AUTO_CHECK_TTL_DAYS' no es válido (debe ser >= 1)" >&2
    exit 2
fi

# ── Funciones auxiliares ───────────────────────────────────────────────
# cache_get CLAVE → imprime el valor guardado en la caché (o nada)
cache_get() {
    [ -f "$CACHE_FILE" ] || return 1
    local v
    v=$(sed -n "s/^$1=//p" "$CACHE_FILE" | head -1)
    [ -n "$v" ] && printf '%s' "$v" || return 1
}

# update_cache HTML HDR CODE → guarda la caché (silencioso)
update_cache() {
    local sha="" last_mod="" mentioned=""
    if command -v sha256sum >/dev/null 2>&1; then
        sha=$(sha256sum "$1" | cut -d' ' -f1)
    fi
    last_mod=$(sed -n 's/^[Ll]ast-[Mm]odified:[[:space:]]*//p' "$2" | head -1 | tr -d '\r')
    mentioned=$(parse_windows "$1")
    mkdir -p "$CACHE_DIR"
    : > "$CACHE_FILE"
    {
        printf 'url=%s\n' "$POLICY_URL"
        printf 'checked_epoch=%s\n' "$(date +%s)"
        printf 'checked_iso=%s\n' "$(date '+%Y-%m-%d %H:%M %z')"
        printf 'http_code=%s\n' "$3"
        printf 'last_modified=%s\n' "$last_mod"
        printf 'content_sha256=%s\n' "$sha"
        printf 'mentioned_windows=%s\n' "$mentioned"
    } >> "$CACHE_FILE"
}

# fetch_policy URL → descarga a $TMP_HTML/$TMP_HDR; imprime el código HTTP
fetch_policy() {
    local url="$1" code
    if command -v curl >/dev/null 2>&1; then
        code=$(curl -fsSL --max-time 10 -o "$TMP_HTML" -D "$TMP_HDR" -w '%{http_code}' "$url" 2>/dev/null) || return 1
        [ "$code" = "000" ] && code=200   # file:// y similares sin código HTTP
        [ -z "$code" ] && code=200
        printf '%s' "$code"
    elif command -v wget >/dev/null 2>&1; then
        wget -q -T 10 -O "$TMP_HTML" "$url" 2>/dev/null || return 1
        printf '200'
    else
        return 2
    fi
}

# parse_windows ARCHIVO → "HH:MM-HH:MM y HH:MM-HH:MM" (acepta "and" y guiones - – —)
parse_windows() {
    sed 's/<[^>]*>/ /g' "$1" 2>/dev/null | tr '\n' ' ' | \
        grep -oE '[0-9]{1,2}:[0-9]{2}[[:space:]]*[-–—][[:space:]]*[0-9]{1,2}:[0-9]{2}[[:space:]]*(y|and)[[:space:]]*[0-9]{1,2}:[0-9]{2}[[:space:]]*[-–—][[:space:]]*[0-9]{1,2}:[0-9]{2}' | head -1
}

# parse_ranges ARCHIVO → todos los rangos "HH:MM-HH:MM" encontrados (deduplicados)
parse_ranges() {
    sed 's/<[^>]*>/ /g' "$1" 2>/dev/null | tr '\n' ' ' | \
        grep -oE '[0-9]{1,2}:[0-9]{2}[[:space:]]*[-–—][[:space:]]*[0-9]{1,2}:[0-9]{2}' | sort -u | tr '\n' ' '
}

# current_windows → franjas actuales formateadas ("09:00-12:00 y 14:00-18:00")
current_windows() {
    printf '%02d:00-%02d:00 y %02d:00-%02d:00' \
        "$PEAK_START_MORNING" "$PEAK_END_MORNING" \
        "$PEAK_START_AFTERNOON" "$PEAK_END_AFTERNOON"
}

# ── Argumentos ─────────────────────────────────────────────────────────
case "${1:-}" in
    -h|--help)
        cat <<'EOF'
deepseek-check - Comprueba si es hora valle para DeepSeek

Uso:
  deepseek-check            Muestra el estado (0 = valle, 1 = pico)
  deepseek-check --quiet    Sin salida; solo código de salida
  deepseek-check --raw      Ídem, pensado para usarse desde scripts
  deepseek-check -update    Comprueba en línea la política y guarda la fecha
  deepseek-check --help     Muestra esta ayuda

Configuración (variables de entorno o ~/.deepseekrc):
  PEAK_START_MORNING      Inicio pico de mañana        (9)
  PEAK_END_MORNING        Fin pico de mañana           (12)
  PEAK_START_AFTERNOON    Inicio pico de tarde         (14)
  PEAK_END_AFTERNOON      Fin pico de tarde            (18)
  TIMEZONE                Zona horaria de referencia   (Asia/Shanghai)
  NO_COLOR                Cualquier valor desactiva el color
  POLICY_URL              URL de la política           (https://api-docs.deepseek.com/quick_start/pricing/)
  AUTO_CHECK_TTL_DAYS     Validez de la caché en días   (7; refresco en segundo plano)
  CACHE_DIR               Directorio de la caché        (~/.cache/deepseek-check)

Códigos de salida: 0 = valle · 1 = pico · 2 = error
  Con -update: 0 = comprobada y coincide · 1 = cambios detectados · 2 = error
Referencia: https://deepakness.com/deepseek
EOF
        exit 0
        ;;
    -update|--update) MODE="update" ;;
    --raw|--quiet)    MODE="quiet" ;;
    "")               MODE="normal" ;;
    *)
        echo "deepseek-check: argumento desconocido: '$1' (usa --help)" >&2
        exit 2
        ;;
esac

# ── Modo -update: comprobación en línea ────────────────────────────────
if [ "$MODE" = "update" ]; then
    TMP_DIR=$(mktemp -d) || {
        echo "deepseek-check: no se pudo crear un directorio temporal" >&2
        exit 2
    }
    TMP_HTML="$TMP_DIR/policy.html"
    TMP_HDR="$TMP_DIR/headers.txt"
    trap 'rm -rf "$TMP_DIR"' EXIT

    echo "📥 Comprobando política en $POLICY_URL ..."
    code=$(fetch_policy "$POLICY_URL") || {
        rc=$?
        if [ "$rc" = 2 ]; then
            echo "❌ No hay curl ni wget. Instala curl (en Termux: pkg install curl)." >&2
        else
            echo "❌ No se pudo descargar $POLICY_URL (¿sin conexión o servidor caído?)." >&2
        fi
        exit 2
    }

    last_mod=$(sed -n 's/^[Ll]ast-[Mm]odified:[[:space:]]*//p' "$TMP_HDR" | head -1 | tr -d '\r')
    echo "✓ Descargado (HTTP $code)${last_mod:+ · last-modified: $last_mod}"

    old_sha=$(cache_get content_sha256)
    old_url=$(cache_get url)
    current=$(current_windows)

    changed=0
    found=$(parse_windows "$TMP_HTML")
    if [ -n "$found" ]; then
        # Normaliza guiones largos a ASCII para la regex de bash (tr corrompe multibyte)
        found_ascii=${found//–/-}
        found_ascii=${found_ascii//—/-}
        # A-B y C-D (admite "and" y guiones - – —)
        if [[ "$found_ascii" =~ ([0-9]{1,2}):[0-9]{2}[[:space:]]*-[[:space:]]*([0-9]{1,2}):[0-9]{2}[[:space:]]*(y|and)[[:space:]]*([0-9]{1,2}):[0-9]{2}[[:space:]]*-[[:space:]]*([0-9]{1,2}):[0-9]{2} ]]; then
            a=${BASH_REMATCH[1]}; b=${BASH_REMATCH[2]}
            c=${BASH_REMATCH[4]}; d=${BASH_REMATCH[5]}
            note=""
            # Si la página expresa las franjas en UTC, convertirlas a TIMEZONE
            if grep -qi 'utc' "$TMP_HTML" 2>/dev/null; then
                z=$(TZ="$TIMEZONE" date +%z)
                off=$(( 10#${z:1:2} ))
                [ "${z:0:1}" = "-" ] && off=$(( -off ))
                conv() { printf '%02d' $(( ( 10#$1 + off + 24 ) % 24 )); }
                a=$(conv "$a"); b=$(conv "$b"); c=$(conv "$c"); d=$(conv "$d")
                note=" (UTC) = ${a}:00-${b}:00 y ${c}:00-${d}:00 en $TIMEZONE"
            fi
            echo "📄 Franjas mencionadas en la página: $found$note"
            if { [ $((10#$a)) -eq $((10#$PEAK_START_MORNING)) ] && [ $((10#$b)) -eq $((10#$PEAK_END_MORNING)) ] && \
                 [ $((10#$c)) -eq $((10#$PEAK_START_AFTERNOON)) ] && [ $((10#$d)) -eq $((10#$PEAK_END_AFTERNOON)) ]; } || \
               { [ $((10#$a)) -eq $((10#$PEAK_START_AFTERNOON)) ] && [ $((10#$b)) -eq $((10#$PEAK_END_AFTERNOON)) ] && \
                 [ $((10#$c)) -eq $((10#$PEAK_START_MORNING)) ] && [ $((10#$d)) -eq $((10#$PEAK_END_MORNING)) ]; }; then
                echo "✓ Coinciden con tu configuración actual ($current)"
            else
                echo "⚠️  Difieren de tu configuración actual ($current)"
                echo "   Si la política cambió, actualiza ~/.deepseekrc (o las variables de entorno)."
                changed=1
            fi
        fi
    else
        ranges=$(parse_ranges "$TMP_HTML")
        if [ -n "$ranges" ]; then
            echo "ℹ️  Franjas encontradas (sin comparar): $ranges"
            echo "   Revisa el contexto de zona horaria en la página."
        else
            echo "ℹ️  No se encontraron franjas horarias explícitas en la página."
            echo "   La política no es legible automáticamente; revísala a mano."
        fi
    fi

    update_cache "$TMP_HTML" "$TMP_HDR" "$code"
    new_sha=$(cache_get content_sha256)
    if [ -n "$old_url" ] && [ "$old_url" != "$POLICY_URL" ]; then
        echo "ℹ️  Fuente de política cambiada (antes: $old_url)"
    elif [ -n "$old_sha" ] && [ -n "$new_sha" ] && [ "$old_sha" != "$new_sha" ]; then
        echo "⚠️  El contenido de la página cambió desde la última comprobación."
        changed=1
    elif [ -n "$old_sha" ]; then
        echo "✓ El contenido no cambió desde la última comprobación."
    else
        echo "✓ Primera comprobación guardada."
    fi

    echo "✓ Caché guardada en $CACHE_FILE"
    exit "$changed"
fi

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

# ── Actualización de política en segundo plano (si la caché caducó) ───
last_epoch=$(cache_get checked_epoch)
stale=1
if [ -n "$last_epoch" ]; then
    age=$(( ( $(date +%s) - last_epoch ) / 86400 ))
    [ "$age" -lt "$AUTO_CHECK_TTL_DAYS" ] && stale=0
fi
if [ "$stale" = 1 ]; then
    # Refresco silencioso en segundo plano: no bloquea la terminal ni muestra nada.
    # Se lanza con el intérprete actual ("$BASH") para no depender del shebang
    # (en Termux sin termux-exec el shebang portátil no funciona).
    ( "$BASH" "$SCRIPT_PATH" -update >/dev/null 2>&1 </dev/null & )
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

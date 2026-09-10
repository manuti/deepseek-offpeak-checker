#!/usr/bin/env bash
#
# deepseek-check.sh - Checks whether it is off-peak time for DeepSeek
# Author: manuti <manuti@gmail.com>
#
# Usage:
#   deepseek-check                Shows the status (0 = off-peak, 1 = peak)
#   deepseek-check --quiet        No output; exit code only
#   deepseek-check --raw          Same, meant for scripts
#   deepseek-check -update        Checks the policy online and saves the date
#   deepseek-check --help         Shows this help
#
# Configuration: environment variables or file ~/.deepseekrc
#   PEAK_START_MORNING     Morning peak start            (9)
#   PEAK_END_MORNING       Morning peak end              (12)
#   PEAK_START_AFTERNOON   Afternoon peak start          (14)
#   PEAK_END_AFTERNOON     Afternoon peak end            (18)
#   TIMEZONE               Reference timezone            (Asia/Shanghai)
#   NO_COLOR               Any value disables colors
#   UI_LANG                Output language (en|fr|pt|es) (auto: locale, default en)
#   POLICY_URL             Policy URL to check           (https://api-docs.deepseek.com/quick_start/pricing/)
#   AUTO_CHECK_TTL_DAYS    Cache validity in days        (7; background refresh)
#   CACHE_DIR              Cache directory               (~/.cache/deepseek-check)
#
# Exit codes: 0 = off-peak · 1 = peak · 2 = error
#   With -update: 0 = checked and matches · 1 = changes detected · 2 = error
# Inspired by https://deepakness.com/deepseek

set -u

# Absolute path of this script (used by the background refresh)
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

# ── Load configuration ─────────────────────────────────────────────────
CONFIG_FILE="${DEEPSEEK_RC:-$HOME/.deepseekrc}"
if [ -n "$CONFIG_FILE" ] && [ -f "$CONFIG_FILE" ]; then
    # shellcheck disable=SC1090
    . "$CONFIG_FILE"
fi

# ── Defaults ───────────────────────────────────────────────────────────
: "${PEAK_START_MORNING:=9}"
: "${PEAK_END_MORNING:=12}"
: "${PEAK_START_AFTERNOON:=14}"
: "${PEAK_END_AFTERNOON:=18}"
: "${TIMEZONE:=Asia/Shanghai}"
: "${POLICY_URL:=https://api-docs.deepseek.com/quick_start/pricing/}"
: "${AUTO_CHECK_TTL_DAYS:=7}"
: "${CACHE_DIR:=$HOME/.cache/deepseek-check}"
CACHE_FILE="$CACHE_DIR/policy.info"

# ── Output language ────────────────────────────────────────────────────
# UI_LANG (config) > LC_ALL > LC_MESSAGES > LANG; default: en
DETECT_LANG="${UI_LANG:-${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}}"
case "$DETECT_LANG" in
    es_*|es) UI_LANG=es ;;
    fr_*|fr) UI_LANG=fr ;;
    pt_*|pt) UI_LANG=pt ;;
    *)       UI_LANG=en ;;
esac

# ── Translations ───────────────────────────────────────────────────────
declare -A MSG_en=(
    [and]="and"
    [status_peak]="PEAK HOURS"
    [status_valley]="OFF-PEAK"
    [status_valley_weekend]="OFF-PEAK (weekend)"
    [peak_label]="Peak:"
    [err_arg]="deepseek-check: unknown argument: '%s' (use --help)"
    [err_hour]="deepseek-check: %s='%s' is not valid (must be 0-23)"
    [err_ttl]="deepseek-check: AUTO_CHECK_TTL_DAYS='%s' is not valid (must be >= 1)"
    [err_tz]="deepseek-check: could not get the time in zone '%s'"
    [err_tmp]="deepseek-check: could not create a temporary directory"
    [err_nodl]="❌ No curl or wget available. Install curl (in Termux: pkg install curl)."
    [err_dl]="❌ Could not download %s (offline or server down?)."
    [update_checking]="📥 Checking policy at %s ..."
    [update_ok]="✓ Downloaded (HTTP %s)"
    [update_lm]=" · last-modified: %s"
    [update_found]="📄 Windows mentioned on the page: %s"
    [update_found_utc]=" (UTC) = %s in %s"
    [update_match]="✓ They match your current configuration (%s)"
    [update_mismatch]="⚠️  They differ from your current configuration (%s)"
    [update_hint]="   If the policy changed, update ~/.deepseekrc (or the environment variables)."
    [update_nofound]="ℹ️  No explicit time windows found on the page."
    [update_nofound_hint]="   The policy is not machine-readable; check the page manually."
    [update_ranges]="ℹ️  Windows found (not compared): %s"
    [update_ranges_hint]="   Check the timezone context on the page."
    [update_source]="ℹ️  Policy source changed (was: %s)"
    [update_changed]="⚠️  The page content changed since the last check."
    [update_unchanged]="✓ The content did not change since the last check."
    [update_first]="✓ First check saved."
    [update_cached]="✓ Cache saved to %s"
)
declare -A MSG_es=(
    [and]="y"
    [status_peak]="HORA PICO"
    [status_valley]="HORA VALLE"
    [status_valley_weekend]="HORA VALLE (fin de semana)"
    [peak_label]="Pico:"
    [err_arg]="deepseek-check: argumento desconocido: '%s' (usa --help)"
    [err_hour]="deepseek-check: %s='%s' no es válido (debe ser 0-23)"
    [err_ttl]="deepseek-check: AUTO_CHECK_TTL_DAYS='%s' no es válido (debe ser >= 1)"
    [err_tz]="deepseek-check: no se pudo obtener la hora en la zona '%s'"
    [err_tmp]="deepseek-check: no se pudo crear un directorio temporal"
    [err_nodl]="❌ No hay curl ni wget. Instala curl (en Termux: pkg install curl)."
    [err_dl]="❌ No se pudo descargar %s (¿sin conexión o servidor caído?)."
    [update_checking]="📥 Comprobando política en %s ..."
    [update_ok]="✓ Descargado (HTTP %s)"
    [update_lm]=" · last-modified: %s"
    [update_found]="📄 Franjas mencionadas en la página: %s"
    [update_found_utc]=" (UTC) = %s en %s"
    [update_match]="✓ Coinciden con tu configuración actual (%s)"
    [update_mismatch]="⚠️  Difieren de tu configuración actual (%s)"
    [update_hint]="   Si la política cambió, actualiza ~/.deepseekrc (o las variables de entorno)."
    [update_nofound]="ℹ️  No se encontraron franjas horarias explícitas en la página."
    [update_nofound_hint]="   La política no es legible automáticamente; revísala a mano."
    [update_ranges]="ℹ️  Franjas encontradas (sin comparar): %s"
    [update_ranges_hint]="   Revisa el contexto de zona horaria en la página."
    [update_source]="ℹ️  Fuente de política cambiada (antes: %s)"
    [update_changed]="⚠️  El contenido de la página cambió desde la última comprobación."
    [update_unchanged]="✓ El contenido no cambió desde la última comprobación."
    [update_first]="✓ Primera comprobación guardada."
    [update_cached]="✓ Caché guardada en %s"
)
declare -A MSG_fr=(
    [and]="et"
    [status_peak]="HEURE DE POINTE"
    [status_valley]="HEURES CREUSES"
    [status_valley_weekend]="HEURES CREUSES (week-end)"
    [peak_label]="Pointe :"
    [err_arg]="deepseek-check : argument inconnu : '%s' (utilisez --help)"
    [err_hour]="deepseek-check : %s='%s' n'est pas valide (doit être 0-23)"
    [err_ttl]="deepseek-check : AUTO_CHECK_TTL_DAYS='%s' n'est pas valide (doit être >= 1)"
    [err_tz]="deepseek-check : impossible d'obtenir l'heure dans le fuseau '%s'"
    [err_tmp]="deepseek-check : impossible de créer un répertoire temporaire"
    [err_nodl]="❌ curl ou wget absent. Installez curl (dans Termux : pkg install curl)."
    [err_dl]="❌ Impossible de télécharger %s (hors ligne ou serveur en panne ?)."
    [update_checking]="📥 Vérification de la politique sur %s ..."
    [update_ok]="✓ Téléchargé (HTTP %s)"
    [update_lm]=" · last-modified : %s"
    [update_found]="📄 Plages horaires mentionnées sur la page : %s"
    [update_found_utc]=" (UTC) = %s en %s"
    [update_match]="✓ Elles correspondent à votre configuration actuelle (%s)"
    [update_mismatch]="⚠️  Elles diffèrent de votre configuration actuelle (%s)"
    [update_hint]="   Si la politique a changé, mettez à jour ~/.deepseekrc (ou les variables d'environnement)."
    [update_nofound]="ℹ️  Aucune plage horaire explicite trouvée sur la page."
    [update_nofound_hint]="   La politique n'est pas lisible automatiquement ; vérifiez la page manuellement."
    [update_ranges]="ℹ️  Plages trouvées (non comparées) : %s"
    [update_ranges_hint]="   Vérifiez le contexte de fuseau horaire sur la page."
    [update_source]="ℹ️  Source de la politique changée (précédemment : %s)"
    [update_changed]="⚠️  Le contenu de la page a changé depuis la dernière vérification."
    [update_unchanged]="✓ Le contenu n'a pas changé depuis la dernière vérification."
    [update_first]="✓ Première vérification enregistrée."
    [update_cached]="✓ Cache enregistré dans %s"
)
declare -A MSG_pt=(
    [and]="e"
    [status_peak]="HORÁRIO DE PICO"
    [status_valley]="HORÁRIO DE VALE"
    [status_valley_weekend]="HORÁRIO DE VALE (fim de sem.)"
    [peak_label]="Pico:"
    [err_arg]="deepseek-check: argumento desconhecido: '%s' (use --help)"
    [err_hour]="deepseek-check: %s='%s' não é válido (deve ser 0-23)"
    [err_ttl]="deepseek-check: AUTO_CHECK_TTL_DAYS='%s' não é válido (deve ser >= 1)"
    [err_tz]="deepseek-check: não foi possível obter a hora no fuso '%s'"
    [err_tmp]="deepseek-check: não foi possível criar um diretório temporário"
    [err_nodl]="❌ Sem curl nem wget. Instale o curl (no Termux: pkg install curl)."
    [err_dl]="❌ Não foi possível baixar %s (offline ou servidor fora do ar?)."
    [update_checking]="📥 Verificando política em %s ..."
    [update_ok]="✓ Baixado (HTTP %s)"
    [update_lm]=" · last-modified: %s"
    [update_found]="📄 Faixas mencionadas na página: %s"
    [update_found_utc]=" (UTC) = %s em %s"
    [update_match]="✓ Coincidem com a sua configuração atual (%s)"
    [update_mismatch]="⚠️  Diferem da sua configuração atual (%s)"
    [update_hint]="   Se a política mudou, atualize ~/.deepseekrc (ou as variáveis de ambiente)."
    [update_nofound]="ℹ️  Nenhuma faixa horária explícita encontrada na página."
    [update_nofound_hint]="   A política não é legível automaticamente; verifique a página manualmente."
    [update_ranges]="ℹ️  Faixas encontradas (sem comparar): %s"
    [update_ranges_hint]="   Verifique o contexto de fuso horário na página."
    [update_source]="ℹ️  Fonte da política alterada (antes: %s)"
    [update_changed]="⚠️  O conteúdo da página mudou desde a última verificação."
    [update_unchanged]="✓ O conteúdo não mudou desde a última verificação."
    [update_first]="✓ Primeira verificação salva."
    [update_cached]="✓ Cache salvo em %s"
)
# t KEY [args...] → prints the translated string (printf template)
# Nota: se usa eval (claves internas) porque los namerefs a arrays asociativos
# fallan con set -u en bash 5.3 ("unbound variable").
t() {
    local key="$1"; shift
    local arr="MSG_$UI_LANG" tmpl
    # Nota: "${arr}[$key]" evita que bash interprete $arr[$key] como subíndice de array
    [ -v "${arr}[$key]" ] || return 0
    eval "tmpl=\${${arr}[${key}]}"
    if [ $# -gt 0 ]; then
        printf "$tmpl" "$@"
    else
        printf '%s' "$tmpl"
    fi
}

# ── Basic configuration validation ─────────────────────────────────────
is_hour() { [[ "$1" =~ ^[0-9]{1,2}$ ]] && [ "$1" -ge 0 ] && [ "$1" -le 23 ]; }
for v in PEAK_START_MORNING PEAK_END_MORNING PEAK_START_AFTERNOON PEAK_END_AFTERNOON; do
    if ! is_hour "${!v}"; then
        printf '%s\n' "$(t err_hour "$v" "${!v}")" >&2
        exit 2
    fi
done
if ! [[ "$AUTO_CHECK_TTL_DAYS" =~ ^[0-9]+$ ]] || [ "$AUTO_CHECK_TTL_DAYS" -lt 1 ]; then
    printf '%s\n' "$(t err_ttl "$AUTO_CHECK_TTL_DAYS")" >&2
    exit 2
fi

# ── Helpers ────────────────────────────────────────────────────────────
# cache_get KEY → prints the cached value (or nothing)
cache_get() {
    [ -f "$CACHE_FILE" ] || return 1
    local v
    v=$(sed -n "s/^$1=//p" "$CACHE_FILE" | head -1)
    [ -n "$v" ] && printf '%s' "$v" || return 1
}

# update_cache HTML HDR CODE → saves the cache (silent)
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

# fetch_policy URL → downloads to $TMP_HTML/$TMP_HDR; prints the HTTP code
fetch_policy() {
    local url="$1" code
    if command -v curl >/dev/null 2>&1; then
        code=$(curl -fsSL --max-time 10 -o "$TMP_HTML" -D "$TMP_HDR" -w '%{http_code}' "$url" 2>/dev/null) || return 1
        [ "$code" = "000" ] && code=200   # file:// and similar without an HTTP code
        [ -z "$code" ] && code=200
        printf '%s' "$code"
    elif command -v wget >/dev/null 2>&1; then
        wget -q -T 10 -O "$TMP_HTML" "$url" 2>/dev/null || return 1
        printf '200'
    else
        return 2
    fi
}

# parse_windows FILE → "HH:MM-HH:MM and HH:MM-HH:MM" (accepts "y"/"and" and - – —)
parse_windows() {
    sed 's/<[^>]*>/ /g' "$1" 2>/dev/null | tr '\n' ' ' | \
        grep -oE '[0-9]{1,2}:[0-9]{2}[[:space:]]*[-–—][[:space:]]*[0-9]{1,2}:[0-9]{2}[[:space:]]*(y|and)[[:space:]]*[0-9]{1,2}:[0-9]{2}[[:space:]]*[-–—][[:space:]]*[0-9]{1,2}:[0-9]{2}' | head -1
}

# parse_ranges FILE → all "HH:MM-HH:MM" ranges found (deduplicated)
parse_ranges() {
    sed 's/<[^>]*>/ /g' "$1" 2>/dev/null | tr '\n' ' ' | \
        grep -oE '[0-9]{1,2}:[0-9]{2}[[:space:]]*[-–—][[:space:]]*[0-9]{1,2}:[0-9]{2}' | sort -u | tr '\n' ' '
}

# current_windows → current windows formatted with the localized conjunction
current_windows() {
    printf '%02d:00-%02d:00 %s %02d:00-%02d:00' \
        "$((10#$PEAK_START_MORNING))" "$((10#$PEAK_END_MORNING))" "$(t and)" \
        "$((10#$PEAK_START_AFTERNOON))" "$((10#$PEAK_END_AFTERNOON))"
}

# ── Arguments ──────────────────────────────────────────────────────────
case "${1:-}" in
    -h|--help)
        case "$UI_LANG" in
            es) cat <<'EOF'
deepseek-check - Comprueba si es hora valle para DeepSeek

Uso:
  deepseek-check            Muestra el estado (0 = valle, 1 = pico)
  deepseek-check --quiet    Sin salida; solo código de salida
  deepseek-check --raw      Ídem, pensado para usarse desde scripts
  deepseek-check -update    Comprueba en línea la política y guarda la fecha
  deepseek-check --help     Muestra esta ayuda

Configuración (variables de entorno o ~/.deepseekrc):
  PEAK_START_MORNING      Inicio pico de mañana       (9)
  PEAK_END_MORNING        Fin pico de mañana          (12)
  PEAK_START_AFTERNOON    Inicio pico de tarde        (14)
  PEAK_END_AFTERNOON      Fin pico de tarde           (18)
  TIMEZONE                Zona horaria de referencia  (Asia/Shanghai)
  NO_COLOR                Cualquier valor desactiva el color
  UI_LANG                 Idioma de salida (en|fr|pt|es)
  POLICY_URL              URL de la política          (https://api-docs.deepseek.com/quick_start/pricing/)
  AUTO_CHECK_TTL_DAYS     Validez de la caché en días  (7; refresco en segundo plano)
  CACHE_DIR               Directorio de la caché       (~/.cache/deepseek-check)

Códigos de salida: 0 = valle · 1 = pico · 2 = error
  Con -update: 0 = comprobada y coincide · 1 = cambios detectados · 2 = error
Referencia: https://deepakness.com/deepseek
EOF
                ;;
            fr) cat <<'EOF'
deepseek-check - Vérifie si c'est l'heure creuse pour DeepSeek

Utilisation :
  deepseek-check            Affiche l'état (0 = creux, 1 = pointe)
  deepseek-check --quiet    Sans sortie ; code de sortie uniquement
  deepseek-check --raw      Idem, pour les scripts
  deepseek-check -update    Vérifie la politique en ligne et enregistre la date
  deepseek-check --help     Affiche cette aide

Configuration (variables d'environnement ou ~/.deepseekrc) :
  PEAK_START_MORNING      Début pointe matin         (9)
  PEAK_END_MORNING        Fin pointe matin           (12)
  PEAK_START_AFTERNOON    Début pointe après-midi    (14)
  PEAK_END_AFTERNOON      Fin pointe après-midi      (18)
  TIMEZONE                Fuseau horaire              (Asia/Shanghai)
  NO_COLOR                Toute valeur désactive la couleur
  UI_LANG                 Langue de sortie (en|fr|pt|es)
  POLICY_URL              URL de la politique         (https://api-docs.deepseek.com/quick_start/pricing/)
  AUTO_CHECK_TTL_DAYS     Validité du cache (jours)   (7 ; rafraîchissement en arrière-plan)
  CACHE_DIR               Répertoire du cache         (~/.cache/deepseek-check)

Codes de sortie : 0 = creux · 1 = pointe · 2 = erreur
  Avec -update : 0 = vérifiée et conforme · 1 = changements détectés · 2 = erreur
Référence : https://deepakness.com/deepseek
EOF
                ;;
            pt) cat <<'EOF'
deepseek-check - Verifica se é hora de vale para DeepSeek

Uso:
  deepseek-check            Mostra o estado (0 = vale, 1 = pico)
  deepseek-check --quiet    Sem saída; apenas código de saída
  deepseek-check --raw      Idem, para usar em scripts
  deepseek-check -update    Verifica a política online e salva a data
  deepseek-check --help     Mostra esta ajuda

Configuração (variáveis de ambiente ou ~/.deepseekrc):
  PEAK_START_MORNING      Início do pico da manhã    (9)
  PEAK_END_MORNING        Fim do pico da manhã       (12)
  PEAK_START_AFTERNOON    Início do pico da tarde    (14)
  PEAK_END_AFTERNOON      Fim do pico da tarde       (18)
  TIMEZONE                Fuso horário de referência  (Asia/Shanghai)
  NO_COLOR                Qualquer valor desativa a cor
  UI_LANG                 Idioma da saída (en|fr|pt|es)
  POLICY_URL              URL da política             (https://api-docs.deepseek.com/quick_start/pricing/)
  AUTO_CHECK_TTL_DAYS     Validade do cache em dias   (7; atualização em segundo plano)
  CACHE_DIR               Diretório do cache          (~/.cache/deepseek-check)

Códigos de saída: 0 = vale · 1 = pico · 2 = erro
  Com -update: 0 = verificada e coincide · 1 = mudanças detectadas · 2 = erro
Referência: https://deepakness.com/deepseek
EOF
                ;;
            *) cat <<'EOF'
deepseek-check - Checks whether it is off-peak time for DeepSeek

Usage:
  deepseek-check            Shows the status (0 = off-peak, 1 = peak)
  deepseek-check --quiet    No output; exit code only
  deepseek-check --raw      Same, meant for scripts
  deepseek-check -update    Checks the policy online and saves the date
  deepseek-check --help     Shows this help

Configuration (environment variables or ~/.deepseekrc):
  PEAK_START_MORNING      Morning peak start        (9)
  PEAK_END_MORNING        Morning peak end          (12)
  PEAK_START_AFTERNOON    Afternoon peak start      (14)
  PEAK_END_AFTERNOON      Afternoon peak end        (18)
  TIMEZONE                Reference timezone        (Asia/Shanghai)
  NO_COLOR                Any value disables colors
  UI_LANG                 Output language (en|fr|pt|es)
  POLICY_URL              Policy URL                (https://api-docs.deepseek.com/quick_start/pricing/)
  AUTO_CHECK_TTL_DAYS     Cache validity in days    (7; background refresh)
  CACHE_DIR               Cache directory           (~/.cache/deepseek-check)

Exit codes: 0 = off-peak · 1 = peak · 2 = error
  With -update: 0 = checked and matches · 1 = changes detected · 2 = error
Reference: https://deepakness.com/deepseek
EOF
                ;;
        esac
        exit 0
        ;;
    -update|--update) MODE="update" ;;
    --raw|--quiet)    MODE="quiet" ;;
    "")               MODE="normal" ;;
    *)
        printf '%s\n' "$(t err_arg "$1")" >&2
        exit 2
        ;;
esac

# ── -update mode: online policy check ──────────────────────────────────
if [ "$MODE" = "update" ]; then
    TMP_DIR=$(mktemp -d) || {
        printf '%s\n' "$(t err_tmp)" >&2
        exit 2
    }
    TMP_HTML="$TMP_DIR/policy.html"
    TMP_HDR="$TMP_DIR/headers.txt"
    trap 'rm -rf "$TMP_DIR"' EXIT

    printf '%s\n' "$(t update_checking "$POLICY_URL")"
    code=$(fetch_policy "$POLICY_URL") || {
        rc=$?
        if [ "$rc" = 2 ]; then
            printf '%s\n' "$(t err_nodl)" >&2
        else
            printf '%s\n' "$(t err_dl "$POLICY_URL")" >&2
        fi
        exit 2
    }

    last_mod=$(sed -n 's/^[Ll]ast-[Mm]odified:[[:space:]]*//p' "$TMP_HDR" | head -1 | tr -d '\r')
    msg="$(t update_ok "$code")"
    [ -n "$last_mod" ] && msg="$msg$(t update_lm "$last_mod")"
    printf '%s\n' "$msg"

    old_sha=$(cache_get content_sha256)
    old_url=$(cache_get url)
    current=$(current_windows)

    changed=0
    found=$(parse_windows "$TMP_HTML")
    if [ -n "$found" ]; then
        # A-B y C-D (accepts "and"/"y" and dashes - – —)
        found_ascii=${found//–/-}
        found_ascii=${found_ascii//—/-}
        if [[ "$found_ascii" =~ ([0-9]{1,2}):[0-9]{2}[[:space:]]*-[[:space:]]*([0-9]{1,2}):[0-9]{2}[[:space:]]*(y|and)[[:space:]]*([0-9]{1,2}):[0-9]{2}[[:space:]]*-[[:space:]]*([0-9]{1,2}):[0-9]{2} ]]; then
            a=${BASH_REMATCH[1]}; b=${BASH_REMATCH[2]}
            c=${BASH_REMATCH[4]}; d=${BASH_REMATCH[5]}
            note=""
            # If the page expresses the windows in UTC, convert them to TIMEZONE
            if grep -qi 'utc' "$TMP_HTML" 2>/dev/null; then
                z=$(TZ="$TIMEZONE" date +%z)
                off=$(( 10#${z:1:2} ))
                [ "${z:0:1}" = "-" ] && off=$(( -off ))
                conv() { printf '%02d' $(( ( 10#$1 + off + 24 ) % 24 )); }
                a=$(conv "$a"); b=$(conv "$b"); c=$(conv "$c"); d=$(conv "$d")
                note="$(t update_found_utc "$(printf '%02d:00-%02d:00 %s %02d:00-%02d:00' "$((10#$a))" "$((10#$b))" "$(t and)" "$((10#$c))" "$((10#$d))")" "$TIMEZONE")"
            fi
            printf '%s\n' "$(t update_found "$found")$note"
            if { [ $((10#$a)) -eq $((10#$PEAK_START_MORNING)) ] && [ $((10#$b)) -eq $((10#$PEAK_END_MORNING)) ] && \
                 [ $((10#$c)) -eq $((10#$PEAK_START_AFTERNOON)) ] && [ $((10#$d)) -eq $((10#$PEAK_END_AFTERNOON)) ]; } || \
               { [ $((10#$a)) -eq $((10#$PEAK_START_AFTERNOON)) ] && [ $((10#$b)) -eq $((10#$PEAK_END_AFTERNOON)) ] && \
                 [ $((10#$c)) -eq $((10#$PEAK_START_MORNING)) ] && [ $((10#$d)) -eq $((10#$PEAK_END_MORNING)) ]; }; then
                printf '%s\n' "$(t update_match "$current")"
            else
                printf '%s\n' "$(t update_mismatch "$current")"
                printf '%s\n' "$(t update_hint)"
                changed=1
            fi
        fi
    else
        ranges=$(parse_ranges "$TMP_HTML")
        if [ -n "$ranges" ]; then
            printf '%s\n' "$(t update_ranges "$ranges")"
            printf '%s\n' "$(t update_ranges_hint)"
        else
            printf '%s\n' "$(t update_nofound)"
            printf '%s\n' "$(t update_nofound_hint)"
        fi
    fi

    update_cache "$TMP_HTML" "$TMP_HDR" "$code"
    new_sha=$(cache_get content_sha256)
    if [ -n "$old_url" ] && [ "$old_url" != "$POLICY_URL" ]; then
        printf '%s\n' "$(t update_source "$old_url")"
    elif [ -n "$old_sha" ] && [ -n "$new_sha" ] && [ "$old_sha" != "$new_sha" ]; then
        printf '%s\n' "$(t update_changed)"
        changed=1
    elif [ -n "$old_sha" ]; then
        printf '%s\n' "$(t update_unchanged)"
    else
        printf '%s\n' "$(t update_first)"
    fi

    printf '%s\n' "$(t update_cached "$CACHE_FILE")"
    exit "$changed"
fi

# ── Time and day in the reference timezone ─────────────────────────────
if ! HOUR=$(TZ="$TIMEZONE" date +%H 2>/dev/null) || \
   ! DAY=$(TZ="$TIMEZONE" date +%u 2>/dev/null) || \
   [ -z "$HOUR" ] || [ -z "$DAY" ]; then
    printf '%s\n' "$(t err_tz "$TIMEZONE")" >&2
    exit 2
fi
# DAY: 1=Monday ... 7=Sunday

# ── Peak/off-peak determination ────────────────────────────────────────
IS_PEAK=0
if [ "$DAY" -ge 1 ] && [ "$DAY" -le 5 ]; then
    if { [ "$HOUR" -ge "$PEAK_START_MORNING" ] && [ "$HOUR" -lt "$PEAK_END_MORNING" ]; } || \
       { [ "$HOUR" -ge "$PEAK_START_AFTERNOON" ] && [ "$HOUR" -lt "$PEAK_END_AFTERNOON" ]; }; then
        IS_PEAK=1
    fi
fi

# ── Quiet mode: exit code only ─────────────────────────────────────────
if [ "$MODE" = "quiet" ]; then
    exit "$IS_PEAK"
fi

# ── Background policy refresh (if the cache is stale) ──────────────────
last_epoch=$(cache_get checked_epoch)
stale=1
if [ -n "$last_epoch" ]; then
    age=$(( ( $(date +%s) - last_epoch ) / 86400 ))
    [ "$age" -lt "$AUTO_CHECK_TTL_DAYS" ] && stale=0
fi
if [ "$stale" = 1 ]; then
    # Silent background refresh: does not block the terminal nor print anything.
    # Launched with the current interpreter ("$BASH") so it does not depend on
    # the shebang (in Termux without termux-exec the portable shebang fails).
    ( "$BASH" "$SCRIPT_PATH" -update >/dev/null 2>&1 </dev/null & )
fi

# ── Formatted output ───────────────────────────────────────────────────
if [ "$IS_PEAK" -eq 1 ]; then
    STATUS="$(t status_peak)"
    EMOJI="🔴"
else
    STATUS="$(t status_valley)"
    if [ "$DAY" -ge 6 ]; then
        STATUS="$(t status_valley_weekend)"
    fi
    EMOJI="🟢"
fi

# Colors only if stdout is a terminal and NO_COLOR is not set
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

# Adaptive box: width follows the longest line so no translation deforms it
LINE_1="DeepSeek: $STATUS"
LINE_2="$(t peak_label) $(printf '%02d:00-%02d:00' "$((10#$PEAK_START_MORNING))" "$((10#$PEAK_END_MORNING))") $(t and) $(printf '%02d:00-%02d:00' "$((10#$PEAK_START_AFTERNOON))" "$((10#$PEAK_END_AFTERNOON))") BJT"
W1=$(( 2 + 1 + ${#LINE_1} ))     # emoji (2 columns) + space + text
W2=${#LINE_2}
INNER=$(( W1 > W2 ? W1 : W2 ))
printf -v BORDER '%*s' "$(( INNER + 4 ))" ''
BORDER=${BORDER// /═}

printf '%b%s%b\n' "$COLOR" "╔${BORDER}╗" "$RESET"
printf '%b║  %s %-*s  ║%b\n' "$COLOR" "$EMOJI" "$(( INNER - 3 ))" "$LINE_1" "$RESET"
printf '%b║  %-*s  ║%b\n' "$COLOR" "$INNER" "$LINE_2" "$RESET"
printf '%b%s%b\n' "$COLOR" "╚${BORDER}╝" "$RESET"

exit "$IS_PEAK"

#!/usr/bin/env bash
#
# install.sh - Instalador de deepseek-check
# Autor: manuti <manuti@gmail.com>
#
# Copia el script a ~/.local/bin (o $PREFIX/bin en Termux) y añade el
# aviso de estado al .bashrc / .zshrc para que se muestre al abrir la
# terminal.
#
# Uso: ./install.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_SCRIPT="$SCRIPT_DIR/bin/deepseek-check.sh"

# ── Destino del binario ────────────────────────────────────────────────
BIN_TARGET="$HOME/.local/bin"
if [ -n "${PREFIX:-}" ] && [ -d "$PREFIX/bin" ]; then   # Termux
    BIN_TARGET="$PREFIX/bin"
fi

# ── Comprobaciones previas ─────────────────────────────────────────────
if [ ! -f "$SOURCE_SCRIPT" ]; then
    echo "❌ No se encontró $SOURCE_SCRIPT" >&2
    echo "   Asegúrate de ejecutar install.sh desde la raíz del repositorio." >&2
    exit 1
fi

echo "📦 Instalando deepseek-check en $BIN_TARGET ..."
mkdir -p "$BIN_TARGET"
cp "$SOURCE_SCRIPT" "$BIN_TARGET/deepseek-check"
chmod +x "$BIN_TARGET/deepseek-check"

# En sistemas sin /usr/bin/env (p. ej. Termux sin termux-exec) el shebang
# portátil no funciona: se adapta al intérprete real que ejecuta este script.
if [ ! -e /usr/bin/env ]; then
    sed -i "1s|.*|#!${BASH}|" "$BIN_TARGET/deepseek-check"
    echo "ℹ️  Shebang adaptado a ${BASH}"
fi

# Comprobación rápida de que el script instalado funciona
set +e
"$BIN_TARGET/deepseek-check" --raw >/dev/null 2>&1
rc=$?
set -e
if [ "$rc" -ge 2 ]; then
    echo "⚠️  El script instalado no responde correctamente (código $rc)." >&2
    exit 1
fi

# ── Añadir el hook al archivo rc ───────────────────────────────────────
SHELL_RC="$HOME/.bashrc"
case "${SHELL:-}" in
    *zsh) SHELL_RC="$HOME/.zshrc" ;;
esac

if ! grep -qsF "deepseek-check" "$SHELL_RC" 2>/dev/null; then
    {
        echo ""
        echo "# DeepSeek off-peak checker: muestra el estado al abrir la terminal"
        echo "deepseek-check"
    } >> "$SHELL_RC"
    echo "✅ Añadido el aviso a $SHELL_RC"
else
    echo "ℹ️  Ya estaba configurado en $SHELL_RC"
fi

# ── Aviso si el destino no está en el PATH ─────────────────────────────
case ":$PATH:" in
    *":$BIN_TARGET:"*) ;;
    *)
        echo "⚠️  $BIN_TARGET no está en tu PATH."
        echo "   Añádelo con:  export PATH=\"$BIN_TARGET:\$PATH\""
        ;;
esac

echo "🎉 Instalación completada."
echo "   Reinicia la terminal o ejecuta: source $SHELL_RC"

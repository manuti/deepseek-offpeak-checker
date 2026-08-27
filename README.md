# DeepSeek Off-Peak Checker

Script ligero para **GNU/Linux y Termux** que indica si estás en **horas valle** para usar las APIs de DeepSeek (Pi, dsh, codewhale, etc.) y evitar así posibles sobrecostes o limitaciones de rendimiento.

## ✨ Características

- **Ligero**: solo necesita `bash`, `date` y una terminal UTF-8. Sin dependencias.
- **Compatible con Termux** (Android) y cualquier distro GNU/Linux.
- **Configurable**: horarios pico y zona horaria ajustables con variables de entorno o el archivo `~/.deepseekrc`.
- **Integrable**: códigos de salida (`0` = valle, `1` = pico, `2` = error) para usarlo con alias, scripts o cron.
- **Aviso automático** al abrir la terminal (hook opcional que añade `install.sh`).
- **Colores automáticos**: se desactivan al redirigir la salida o con `NO_COLOR`.

## 🧠 ¿Cómo funciona?

Comprueba la hora actual en **Beijing (UTC+8)** y determina si es hora pico:

- **De lunes a viernes**, entre **09:00-12:00** y **14:00-18:00** (hora de Beijing) → **hora pico**.
- El resto del tiempo (tardes, noches, madrugadas y **fines de semana**) → **hora valle**.

Ambas franjas y la zona horaria son configurables.

## ⚡ Instalación

### Requisitos

- Bash 4+ y `date` (GNU coreutils o BSD).
- Terminal con soporte UTF-8 (cualquiera moderna; Termux por defecto).

### Automática (recomendada)

```bash
git clone https://github.com/TU-USUARIO/deepseek-offpeak-checker.git
cd deepseek-offpeak-checker
./install.sh
```

El instalador:

1. Copia el script a `~/.local/bin/deepseek-check` (o a `$PREFIX/bin` en Termux).
2. Añade el aviso de estado a `~/.bashrc` (o `~/.zshrc` si usas Zsh).

Reinicia la terminal o ejecuta `source ~/.bashrc`.

> **Termux**: si tu instalación no incluye `termux-exec` (error *bad interpreter: /usr/bin/env*), ejecuta `bash install.sh`; el instalador adapta el shebang automáticamente.

### Manual

```bash
install -m 755 bin/deepseek-check.sh ~/.local/bin/deepseek-check
```

## 🚀 Uso

| Comando | Efecto |
|---|---|
| `deepseek-check` | Muestra el estado en una caja de colores |
| `deepseek-check --quiet` | Sin salida; solo código de salida |
| `deepseek-check --raw` | Solo código de salida (para scripts) |
| `deepseek-check --help` | Muestra la ayuda |

### Códigos de salida

- `0` → hora **valle**
- `1` → hora **pico**
- `2` → error (configuración inválida, argumento desconocido, `date` falló…)

Esto permite integrarlo con otros comandos:

```bash
# Solo ejecuta dsh si es hora valle
alias dsh='deepseek-check --quiet && dsh'

# En scripts
if deepseek-check --raw; then
    echo "Es hora valle, lanzando el trabajo..."
fi
```

## ⚙️ Configuración

Crea `~/.deepseekrc` (se carga automáticamente si existe):

```bash
# Franjas pico (en la zona horaria de TIMEZONE)
PEAK_START_MORNING=9
PEAK_END_MORNING=12
PEAK_START_AFTERNOON=14
PEAK_END_AFTERNOON=18

# Zona horaria de referencia (por defecto: Asia/Shanghai)
TIMEZONE="Asia/Shanghai"

# Desactiva los colores (opcional)
NO_COLOR=1
```

| Variable | Descripción | Por defecto |
|---|---|---|
| `PEAK_START_MORNING` | Inicio del pico de mañana | `9` |
| `PEAK_END_MORNING` | Fin del pico de mañana | `12` |
| `PEAK_START_AFTERNOON` | Inicio del pico de tarde | `14` |
| `PEAK_END_AFTERNOON` | Fin del pico de tarde | `18` |
| `TIMEZONE` | Zona horaria de referencia | `Asia/Shanghai` |
| `NO_COLOR` | Cualquier valor desactiva el color | — |

También puedes usar variables de entorno directamente:

```bash
PEAK_START_MORNING=10 PEAK_END_MORNING=13 deepseek-check
```

> Nota: si cambias `TIMEZONE`, las franjas pico se interpretan en esa zona.

## 📄 Ejemplo de salida

```
╔════════════════════════════════════════════╗
║  🟢 DeepSeek: HORA VALLE                   ║
║  Pico: 09:00-12:00 y 14:00-18:00 BJT       ║
╚════════════════════════════════════════════╝
```

Durante el pico la caja se muestra en **rojo** con `🔴 HORA PICO`; los fines de semana siempre es `🟢 HORA VALLE (fin de semana)`. Más ejemplos en [docs/ejemplos.md](docs/ejemplos.md).

## 🗂️ Estructura del repositorio

```
deepseek-offpeak-checker/
├── bin/
│   └── deepseek-check.sh    # Script principal
├── docs/
│   └── ejemplos.md          # Ejemplos de uso
├── install.sh               # Instalador automático
├── LICENSE                  # MIT
└── README.md                # Esta documentación
```

## ✅ Compatibilidad

- GNU/Linux (cualquier distro)
- Termux (Android)
- Bash / Zsh

## 🔗 Referencia

Inspirado en el artículo sobre el uso en horas valle de las APIs de DeepSeek: <https://deepakness.com/deepseek>

## 📝 Licencia

[MIT](LICENSE)

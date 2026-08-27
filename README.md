# DeepSeek Off-Peak Checker

Script ligero para **GNU/Linux y Termux** que indica si estás en **horas valle** para usar las APIs de DeepSeek (Pi, dsh, codewhale, etc.) y evitar así posibles sobrecostes o limitaciones de rendimiento.

## ✨ Características

- **Ligero**: solo necesita `bash`, `date` y una terminal UTF-8. Sin dependencias.
- **Compatible con Termux** (Android) y cualquier distro GNU/Linux.
- **Configurable**: horarios pico y zona horaria ajustables con variables de entorno o el archivo `~/.deepseekrc`.
- **Integrable**: códigos de salida (`0` = valle, `1` = pico, `2` = error) para usarlo con alias, scripts o cron.
- **Comprobación de política**: `deepseek-check -update` descarga la página de referencia, detecta cambios de contenido y avisa si las franjas difieren de tu configuración; comprobación automática opcional (`AUTO_CHECK`).
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
git clone https://github.com/manuti/deepseek-offpeak-checker.git
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
| `deepseek-check -update` | Comprueba en línea la política y guarda la fecha de comprobación |
| `deepseek-check --help` | Muestra la ayuda |

### Códigos de salida

- `0` → hora **valle**
- `1` → hora **pico**
- `2` → error (configuración inválida, argumento desconocido, `date` falló…)

Con `-update`: `0` = comprobada y coincide · `1` = cambios detectados · `2` = error.

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
| `POLICY_URL` | URL de la política a comprobar | `https://deepakness.com/deepseek` |
| `AUTO_CHECK` | Comprobar en línea si la caché caduca (`1` = activado) | `0` |
| `AUTO_CHECK_TTL_DAYS` | Validez de la caché en días | `7` |
| `CACHE_DIR` | Directorio de la caché | `~/.cache/deepseek-check` |

También puedes usar variables de entorno directamente:

```bash
PEAK_START_MORNING=10 PEAK_END_MORNING=13 deepseek-check
```

> Nota: si cambias `TIMEZONE`, las franjas pico se interpretan en esa zona.

## 🌐 Comprobación de la política

Las franjas pico pueden cambiar si DeepSeek actualiza su política. `deepseek-check -update` descarga la página de referencia, guarda la fecha de comprobación y avisa si las franjas mencionadas difieren de tu configuración:

```console
$ deepseek-check -update
📥 Comprobando política en https://deepakness.com/deepseek ...
✓ Descargado (HTTP 200)
📄 Franjas mencionadas en la página: 01:00–04:00 and 06:00–10:00 (UTC) = 09:00-12:00 y 14:00-18:00 en Asia/Shanghai
✓ Coinciden con tu configuración actual (09:00-12:00 y 14:00-18:00)
✓ El contenido no cambió desde la última comprobación.
✓ Caché guardada en ~/.cache/deepseek-check/policy.info
```

- Las franjas se convierten de **UTC a tu `TIMEZONE`** automáticamente cuando la página las expresa en UTC.
- Si la página menciona franjas distintas, el script avisa (devuelve `1`) y tú decides si actualizar `~/.deepseekrc`.
- La caché (`~/.cache/deepseek-check/policy.info`) guarda URL, fecha de comprobación, `last-modified`, hash del contenido y franjas detectadas. Si el **contenido cambia** entre comprobaciones, también se avisa.
- Con caché presente, la línea de estado incluye la fecha de la última comprobación: `DeepSeek: 🟢 HORA VALLE · 2026-08-27` (o `· desactualizada` si la caché lleva más de `AUTO_CHECK_TTL_DAYS` días). En fin de semana el estado es largo y el sufijo se omite para no deformar la caja.

> ⚠️ No existe una API oficial legible por máquina: la extracción de franjas es un heurístico sobre la página de referencia. Si no se encuentran franjas explícitas, confía en la detección de cambios de contenido y revisa la página a mano.

### Comprobación automática (opcional)

`AUTO_CHECK=1` comprueba en línea cuando la caché supera `AUTO_CHECK_TTL_DAYS` días. Está desactivada por defecto para que el aviso al abrir la terminal siga siendo instantáneo:

```bash
# en ~/.deepseekrc
AUTO_CHECK=1
AUTO_CHECK_TTL_DAYS=7
```

## 📄 Ejemplo de salida

```
╔════════════════════════════════════════════╗
║  🟢 DeepSeek: HORA VALLE                   ║
║  Pico: 09:00-12:00 y 14:00-18:00 BJT       ║
║  Hora local: 16:45                         ║
╚════════════════════════════════════════════╝
```

La última línea (`Hora local`) usa la hora del dispositivo y siempre se muestra en el **color estándar** de la terminal. Durante el pico la caja se muestra en **rojo** con `🔴 HORA PICO`; los fines de semana siempre es `🟢 HORA VALLE (fin de semana)`. Más ejemplos en [docs/ejemplos.md](docs/ejemplos.md).

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

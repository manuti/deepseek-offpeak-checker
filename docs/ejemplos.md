# Ejemplos de uso

## Salida normal

```console
$ deepseek-check
╔════════════════════════════════════════════╗
║  🟢 DeepSeek: HORA VALLE                   ║
║  Pico: 09:00-12:00 y 14:00-18:00 BJT       ║
╚════════════════════════════════════════════╝
```

En hora pico (de lunes a viernes, 09:00-12:00 o 14:00-18:00 hora de
Beijing) la caja se muestra en rojo:

```console
$ deepseek-check
╔════════════════════════════════════════════╗
║  🔴 DeepSeek: HORA PICO                    ║
║  Pico: 09:00-12:00 y 14:00-18:00 BJT       ║
╚════════════════════════════════════════════╝
```

Los fines de semana siempre es hora valle:

```console
$ deepseek-check
╔════════════════════════════════════════════╗
║  🟢 DeepSeek: HORA VALLE (fin de semana)   ║
║  Pico: 09:00-12:00 y 14:00-18:00 BJT       ║
╚════════════════════════════════════════════╝
```

## Códigos de salida (integración con scripts)

```bash
#!/usr/bin/env bash
# lanzar_trabajo.sh: solo ejecuta el trabajo en hora valle

if deepseek-check --raw; then
    echo "Es hora valle, lanzando el trabajo..."
    # ... tu trabajo pesado aquí
else
    echo "Es hora pico, se pospone."
    exit 1
fi
```

O en una línea:

```bash
deepseek-check --raw && ./mi_script.sh
```

## Alias en el shell

Para que un comando solo se ejecute cuando es hora valle:

```bash
alias dsh='deepseek-check --quiet && dsh'
alias pi='deepseek-check --quiet && pi'
```

Sin `--quiet` también funciona, pero verás la caja de estado antes de cada
ejecución.

## Configuración personalizada

Con `~/.deepseekrc`:

```bash
# Horario pico de mañana: 10:00-13:00
PEAK_START_MORNING=10
PEAK_END_MORNING=13
# Horario pico de tarde: 15:00-19:00
PEAK_START_AFTERNOON=15
PEAK_END_AFTERNOON=19
# Zona horaria local (por defecto Asia/Shanghai)
TIMEZONE="Europe/Madrid"
```

Con variables de entorno (por ejemplo, en un script):

```bash
PEAK_START_MORNING=10 PEAK_END_MORNING=13 deepseek-check
```

## Desactivar colores

Cuando se redirige la salida o se quiere texto plano:

```bash
NO_COLOR=1 deepseek-check
deepseek-check | cat          # los colores se desactivan solos si no es TTY
```

## Ejecutar al inicio (hook del instalador)

`install.sh` añade una línea `deepseek-check` a tu `.bashrc` / `.zshrc`, de
modo que el estado se muestra cada vez que abres una terminal. Para quitarlo,
elimina o comenta esas líneas:

```bash
# DeepSeek off-peak checker: muestra el estado al abrir la terminal
# deepseek-check
```

## Notificaciones en Android (Termux)

Combinado con `termux-notification`, puedes recibir el estado sin abrir la
terminal:

```bash
if deepseek-check --raw; then
    termux-notification --title "DeepSeek" --content "🟢 Es hora valle"
else
    termux-notification --title "DeepSeek" --content "🔴 Es hora pico"
fi
```

<div align="center">

# Codex for Claude Code

**Corre el CLI de OpenAI Codex dentro de Claude Code. Gasta cuota de ChatGPT, no tu plan de Claude.**

Una skill de Claude Code production-ready que delega exploración, implementación, revisiones, pruebas y refactors a `codex exec` corriendo nativo en una nueva ventana de terminal — mientras Claude solo ve el reporte final.

[![License: MIT](https://img.shields.io/badge/license-MIT-8A2BE2?style=for-the-badge)](./LICENSE)
[![Claude Code](https://img.shields.io/badge/Claude_Code-D97757?style=for-the-badge&logo=anthropic&logoColor=white)](https://claude.com/claude-code)
[![OpenAI Codex](https://img.shields.io/badge/OpenAI_Codex-412991?style=for-the-badge&logo=openai&logoColor=white)](https://github.com/openai/codex)
[![Platforms](https://img.shields.io/badge/platform-Windows_•_macOS_•_Linux-0A7E8C?style=for-the-badge)](#soporte-cross-platform)

[![Estado](https://img.shields.io/badge/estado-production_ready-brightgreen?style=flat-square)](#)
[![Ahorro](https://img.shields.io/badge/ahorro_plan_Claude-~92%25-FFD700?style=flat-square)](#comparativa-de-costos)
[![PRs welcome](https://img.shields.io/badge/PRs-bienvenidos-FF69B4?style=flat-square)](#contribuir)

[**English**](./README.md) • [**Español**](./README.es.md)

</div>

---

## Tabla de contenidos

- [Qué hace](#qué-hace)
- [Por qué importa](#por-qué-importa)
- [Arquitectura](#arquitectura)
- [Inicio rápido](#inicio-rápido)
- [Reglas de enrutamiento](#reglas-de-enrutamiento)
- [Comparativa de costos](#comparativa-de-costos)
- [Soporte cross-platform](#soporte-cross-platform)
- [Features de resiliencia](#features-de-resiliencia)
- [Solución de problemas](#solución-de-problemas)
- [Créditos](#créditos)
- [Licencia](#licencia)

---

## Qué hace

Pones esta skill en `~/.claude/skills/codex/` y Claude Code gana una nueva habilidad: puede abrir una ventana de terminal separada que corre el **CLI real de OpenAI Codex** para hacer el trabajo pesado, y luego solo lee la respuesta final.

Vos miras la experiencia codex en vivo en tu propia terminal (header del modelo, reasoning, exec calls, mensaje del agent, uso de tokens). Claude orquesta y lee solo el resultado final — nunca el stream.

```
┌──────────────────┐         ┌────────────────────────────┐         ┌────────────────────┐
│ Vos pides a Claude│ ─────▶ │  Claude despacha /codex    │ ──────▶ │  Nueva terminal    │
└──────────────────┘         │  (job id, prompt en file)  │         │  corre codex exec  │
                             └────────────────────────────┘         │  (vos miras live)  │
                                       │                            └────────────────────┘
                                       │                                       │
                                       ▼                                       ▼
                             ┌────────────────────────────┐         ┌────────────────────┐
                             │  wait_and_read.sh hace     │ ◀────── │  done flag + status│
                             │  polling + parsea bloque   │         │  + session id file │
                             └────────────────────────────┘         └────────────────────┘
                                       │
                                       ▼
                             ┌────────────────────────────┐
                             │  bloque CODEX_BEGIN / END  │
                             │  solo el mensaje final     │
                             │  (~2K tokens Claude)       │
                             └────────────────────────────┘
```

---

## Por qué importa

| Problema | Solución |
|---|---|
| Los subagents nativos de Claude (`Task`/`Agent`) inundan el contexto con todo el transcript (~30-80K tokens por task). Una exploración pesada revienta tu ventana de 5h del Max. | Esta skill delega a `codex` — un proceso aparte que consume tu **cuota de ChatGPT Plus/Pro**, no tu plan de Claude. Claude solo lee el reporte final (~2K tokens). |
| No podés ver qué está haciendo un subagent en tiempo real. | La nueva ventana muestra el `codex exec` CLI real en vivo — modelo, reasoning, exec calls, mensaje, tokens. Pausa con `Ctrl+S`, resume con `Ctrl+Q`. |
| Cerraste la terminal sin querer? Tu trabajo se pierde. | Cada dispatch captura el `session id` de codex. Corre `resume.sh` para continuar desde donde quedó — sin re-reasoning. |
| Codex se cuelga con quirks del sandbox (Python bloqueado, MCP servers ausentes, signal pipe errors). | Preámbulo defensivo del prompt + detección automática de stuck (heartbeat de crecimiento + contador de errores repetidos) auto-alertan a los 90s con diagnóstico limpio. |

---

## Arquitectura

```
┌─────────────────────────────────────────────────────────────────────┐
│  Claude (esta skill)                                                │
│   1. Genera JOB_ID                                                  │
│   2. Escribe $TMPDIR/cx-<JOB>.prompt    (heredoc — cualquier char)  │
│   3. Escribe $TMPDIR/cx-<JOB>.env       (sourced por run.sh)        │
│   4. Bash background:                                               │
│        bash skill/spawn.sh JOB CONFIG                               │
│        bash skill/wait_and_read.sh JOB [TIMEOUT]                    │
│           ├─ done flag    → parsea bloque final                     │
│           ├─ stuck flag   → diagnóstico + alerta                    │
│           └─ timeout      → abort + ofrece resume                   │
└─────────────────────────────────────────────────────────────────────┘
                  │
                  ▼  (spawn.sh detecta OS, abre terminal)
┌─────────────────────────────────────────────────────────────────────┐
│  Ventana terminal (Windows Terminal · Terminal.app · gnome-terminal)│
│                                                                     │
│   bash run.sh CONFIG                                                │
│     ├─ trap EXIT/INT/TERM/HUP → SIEMPRE escribe done flag           │
│     ├─ source CONFIG (MODEL, EFFORT, SANDBOX, TIER, CWD, PROMPT)    │
│     ├─ codex exec [resume <SID>] ARGS PROMPT  2>&1 | tee OUT        │
│     ├─ captura session id → cx-<JOB>.session  (para resume)         │
│     └─ escribe done + status files                                  │
└─────────────────────────────────────────────────────────────────────┘
```

**Archivos en este repo:**

| Archivo | Propósito |
|---|---|
| [`skill/SKILL.md`](./skill/SKILL.md) · [`SKILL.es.md`](./skill/SKILL.es.md) | Definición de la skill que Claude lee (Inglés / Español). |
| [`skill/run.sh`](./skill/run.sh) | Runner cross-platform que corre **dentro** de la terminal spawneada. Trap del done flag, captura de sesión, sandbox/tier configurables. |
| [`skill/spawn.sh`](./skill/spawn.sh) | Spawner cross-platform de terminal. Detecta OS, elige el mejor emulator. |
| [`skill/spawn-windows.cmd`](./skill/spawn-windows.cmd) | Helper Windows que preserva quoting cuando `spawn.sh` lanza `wt.exe` o `cmd`. |
| [`skill/wait_and_read.sh`](./skill/wait_and_read.sh) | Hace polling + lee resultado. Una sola llamada reemplaza wait loop inline + ctx_execute_file. |
| [`skill/resume.sh`](./skill/resume.sh) | Resume una sesión interrumpida por id. Hereda MODEL/EFFORT/SANDBOX del job previo. |
| [`setup/SETUP.md`](./setup/SETUP.md) · [`SETUP.es.md`](./setup/SETUP.es.md) | Prompts de instalación copy-paste para Claude Code. |

---

## Inicio rápido

### 1. Prerequisitos

```bash
# OpenAI Codex CLI
npm i -g @openai/codex

# Login con tu cuenta ChatGPT Plus / Pro (una vez)
codex login

# Verificar (necesita >= 0.117)
codex --version
```

### 2. Instala la skill — one-liner por OS

<details>
<summary><b>🪟 Windows (PowerShell o Git Bash)</b></summary>

```powershell
git clone https://github.com/xt0n1-t3ch/Codex-for-Claude-Code.git
cd Codex-for-Claude-Code
mkdir -Force "$env:USERPROFILE\.claude\skills\codex" | Out-Null
copy skill\SKILL.es.md         "$env:USERPROFILE\.claude\skills\codex\SKILL.md"
copy skill\run.sh              "$env:USERPROFILE\.claude\skills\codex\run.sh"
copy skill\spawn.sh            "$env:USERPROFILE\.claude\skills\codex\spawn.sh"
copy skill\spawn-windows.cmd   "$env:USERPROFILE\.claude\skills\codex\spawn-windows.cmd"
copy skill\wait_and_read.sh    "$env:USERPROFILE\.claude\skills\codex\wait_and_read.sh"
copy skill\resume.sh           "$env:USERPROFILE\.claude\skills\codex\resume.sh"
# (Para inglés) copy skill\SKILL.md "$env:USERPROFILE\.claude\skills\codex\SKILL.md"
```

Requiere **Git for Windows** (Git Bash) y **Windows Terminal** (default en Win11; en Win10 instalar desde Microsoft Store).
</details>

<details>
<summary><b>🍎 macOS (zsh / bash)</b></summary>

```bash
git clone https://github.com/xt0n1-t3ch/Codex-for-Claude-Code.git
cd Codex-for-Claude-Code
mkdir -p ~/.claude/skills/codex
cp skill/SKILL.es.md ~/.claude/skills/codex/SKILL.md
cp skill/run.sh skill/spawn.sh skill/spawn-windows.cmd skill/wait_and_read.sh skill/resume.sh ~/.claude/skills/codex/
chmod +x ~/.claude/skills/codex/*.sh
# (Para inglés) cp skill/SKILL.md ~/.claude/skills/codex/SKILL.md
```

Usa Terminal.app vía AppleScript. Para iTerm2 / WezTerm / Alacritty: `skill/spawn.sh` cae a `osascript Terminal.app` por default — adáptalo si necesitas.
</details>

<details>
<summary><b>🐧 Linux (bash)</b></summary>

```bash
git clone https://github.com/xt0n1-t3ch/Codex-for-Claude-Code.git
cd Codex-for-Claude-Code
mkdir -p ~/.claude/skills/codex
cp skill/SKILL.es.md ~/.claude/skills/codex/SKILL.md
cp skill/run.sh skill/spawn.sh skill/spawn-windows.cmd skill/wait_and_read.sh skill/resume.sh ~/.claude/skills/codex/
chmod +x ~/.claude/skills/codex/*.sh
# (Para inglés) cp skill/SKILL.md ~/.claude/skills/codex/SKILL.md
```

Auto-detecta: gnome-terminal, konsole, xfce4-terminal, kitty, alacritty, wezterm, xterm (en ese orden).
</details>

### 3. Reinicia Claude Code

Corre `/reload` o cierra y vuelve a abrir. Verifica que la skill cargó:

```
codex: Delega trabajo al CLI de OpenAI Codex (cuota de ChatGPT, NO tu plan de Claude)…
```

### 4. O deja que Claude la instale por vos

Pega el contenido de [`setup/SETUP.es.md`](./setup/SETUP.es.md) (o [`SETUP.md`](./setup/SETUP.md)) en Claude Code. Claude camina por los prerequisitos, instala la skill y corre un dispatch de verificación.

---

## Reglas de enrutamiento

### AUTO (sin trigger — Claude rutea silencioso)

Claude delega esto a **`gpt-5.4-mini` + `medium`** sin que se lo pidas:

- Mapeo de estructura de repo
- Lectura de archivos grandes
- Búsqueda de patrones entre muchos archivos
- Análisis de dependencias
- Cualquier reconocimiento de solo-lectura

### ON-TRIGGER (`usa /codex <acción>`)

| Trigger | Modelo | Esfuerzo |
|---|---|---|
| `usa /codex explora X` *(básico)*       | `gpt-5.4-mini` | `medium` |
| `usa /codex explora X a fondo`          | `gpt-5.4-mini` | `high`   |
| `usa /codex implementa X`               | `gpt-5.4`      | `high`   |
| `usa /codex refactoriza X`              | `gpt-5.4`      | `high`   |
| `usa /codex revisa`                      | `gpt-5.4`      | `high`   |
| `usa /codex corre pruebas` / `prod ready`| `gpt-5.4`      | `high`   |
| `usa /codex busca fallos`                | `gpt-5.4`      | `high`   |

### Tier de urgencia (opt-in manual)

Decí `"modo rápido"`, `"es urgente"`, o `"/fast"`. Claude pone `TIER=fast` (cola prioritaria). Válidos: `default` · `fast` · `flex`. Nunca auto.

---

## Comparativa de costos

Tokens Claude consumidos **de tu plan Claude** por dispatch:

| Approach | Por dispatch | Sesión 2h heavy (28 dispatches) |
|---|---:|---:|
| Subagent nativo (`Task` / `Agent`) | 30K – 80K | 800K – 2.2M |
| `/codex` con stream Monitor completo | 5K – 30K  | 150K – 525K |
| **`/codex` (esta skill)**            | **2K – 4K** | **~60K – 110K** |

```
Subagent nativo:   ████████████████████████████  ~30-80K
Monitor full:      ████████████                    ~5-30K
ESTA skill:        █                                ~2-4K  ← 92% de ahorro
```

El compute de ChatGPT sale de tus **límites de 5h y semanal de ChatGPT Plus/Pro** (visibles en la línea de estado del TUI `codex`). Efecto neto: tu plan Claude rinde ~10× más en trabajo delegado.

---

## Soporte cross-platform

| OS | Emulator de terminal | Mecanismo de spawn | Estado |
|---|---|---|---|
| **Windows 11** | Windows Terminal (`wt.exe`) | `cmd /c start "" wt.exe -w 0 nt …` | ✅ Probado |
| **Windows 10** | `wt.exe` si está instalado, sino fallback `cmd /k` | mismo | ✅ Fallback funciona |
| **macOS** | Terminal.app vía AppleScript | `osascript -e 'tell app "Terminal"…'` | ✅ |
| **Linux (GNOME)** | `gnome-terminal` | `gnome-terminal --title=… -- bash …` | ✅ |
| **Linux (KDE)** | `konsole` | `konsole --title … -e bash …` | ✅ |
| **Linux (otros)** | xfce4-terminal · kitty · alacritty · wezterm · xterm | primero disponible, en orden de prioridad | ✅ |

Detección en [`skill/spawn.sh`](./skill/spawn.sh) vía `$OSTYPE` / `uname -s`.

---

## Features de resiliencia

Esto es lo que la hace production-ready:

| Preocupación | Mitigación |
|---|---|
| **Race conditions** entre dispatches concurrentes | IDs por job (`cx-<JOB_ID>.{prompt,env,txt,done,status,stuck,session,spawn.log}`). |
| **Abort cuelga Claude** (Ctrl+C / cierre de ventana) | `trap EXIT INT TERM HUP` en `run.sh` siempre escribe el done flag. |
| **Codex stuck en loop de retry** | Wait loop vigila heartbeat de crecimiento (umbral 90s) + contador de errores repetidos (3+ matches de `Access is denied`/`signal pipe`/etc) → escribe `cx-<JOB>.stuck`. |
| **Hard timeout** | `TIMEOUT` por task type (3-20 min) → escribe stuck flag y avisa al usuario. |
| **Cierre accidental de ventana** | Session id capturado a `cx-<JOB>.session` → `resume.sh` continúa con `codex exec resume <id>`. |
| **Transporte frágil del prompt** | Prompts escritos a file vía heredoc, nunca pasados por argv a través de `bash → wt → bash`. |
| **Sandbox bloqueando tools de codex** | Default `SANDBOX=danger-full-access` permite a codex usar Python, MCPs, todos los shells. Configurable por dispatch. |
| **Codex alucinando nombres de MCP** | Preámbulo defensivo lista MCPs disponibles y prohíbe los que no existen (`filesystem`). |
| **Respuestas verbose truncadas** | `wait_and_read.sh` usa extracción por marker (entre `codex\n` y `tokens used\n`), no `tail -100`. |
| **Lazy polling / preguntar al usuario qué dice la terminal** | `wait_and_read.sh` como fuente única de verdad + REGLA en `SKILL.md` que prohíbe fallback chatter. |

---

## Solución de problemas

| Síntoma | Solución |
|---|---|
| `unexpected argument '--ask-for-approval'` | Quita la flag — no existe en `codex exec`. |
| `not inside a trusted directory` | `--skip-git-repo-check` debe ser flag CLI real (no `-c`). Ya está en el template. |
| `model is not supported` | Válidos: `gpt-5.4-mini`, `gpt-5.4`. `gpt-5.4-codex` **no** existe. |
| Codex se cuelga leyendo stdin | `run.sh` ya redirige vía `tee`; asegúrate que ningún wrapper `bash -c` se cuele. |
| Loops de `Access is denied` en pwsh | Cambia `SANDBOX` a `danger-full-access` (default) o actualiza el preámbulo para prohibir Python. |
| `unknown MCP server 'filesystem'` | Codex alucinó. El preámbulo ya lo prohíbe. Re-dispatch. |
| La ventana cierra inmediato en Windows | Verifica que `wt.exe` esté instalado y que `bash` de Git Bash esté en `PATH`. Revisa `cx-<JOB>.spawn.log`. |
| El stuck flag se dispara por nada | Aumenta `STUCK_THRESHOLD` en el template del dispatch (default 120 s). |

---

## Créditos

Construido por [@xt0n1-t3ch](https://github.com/xt0n1-t3ch). Inspirado en [openai/codex-plugin-cc](https://github.com/openai/codex-plugin-cc) — este repo esquiva el bug de bloqueo del `app-server` del plugin usando `codex exec` nativo.

---

## Contribuir

PRs bienvenidos. Áreas de interés:

- Detección de preferencia iTerm2 / WezTerm / Alacritty en macOS
- Windows: soporte para Wezterm / Tabby
- Sniffing de versión del CLI codex en `run.sh` para feature-detect flags nuevas
- Pulido del flujo de resume (auto-suggest después de stuck flag)

---

## Licencia

[MIT](./LICENSE)

---
name: codex
description: Delega trabajo al CLI de OpenAI Codex (cuota de ChatGPT, NO tu plan de Claude). AUTO para exploración de repo / recon de solo-lectura → gpt-5.4-mini medium · ON-TRIGGER ("usa /codex <acción>") para implementar / refactorizar / revisar / pruebas / cazar bugs → gpt-5.4 high. Cada dispatch abre una NUEVA ventana de terminal (cross-platform: Windows Terminal · macOS Terminal · Linux gnome/konsole/xterm) corriendo `codex exec` nativo — el usuario ve el CLI completo en vivo (modelo, esfuerzo, prompt, reasoning, exec, mensaje, tokens). Claude solo lee el mensaje final vía `wait_and_read.sh` (~2-4K tokens por dispatch). IDs por job evitan races. Trap del done flag sobrevive Ctrl+C / cierre de ventana. Detección de stuck (crecimiento de archivo + contador de errores repetidos) auto-alerta a los 90s. Sesiones resumibles por id (codex exec resume) — cierres accidentales nunca pierden trabajo. Service tier `fast` / `flex` opt-in. Nunca usar mcp__codex__codex (opaco, sin stream).
---

# /codex — Delega al CLI de OpenAI Codex

## TL;DR

Cada dispatch `/codex`:
1. Escribe un prompt + config por job en `$TMPDIR`.
2. Abre una nueva terminal vía `spawn.sh` (cross-platform).
3. La ventana corre `bash run.sh CONFIG` → que corre `codex exec` nativo.
4. El usuario ve el codex CLI real en vivo (header con modelo, reasoning, exec calls, mensaje del agent, uso de tokens).
5. Claude llama `bash ~/.claude/skills/codex/wait_and_read.sh JOB_ID [TIMEOUT_SEC]`.
6. `wait_and_read.sh` espera done/stuck/timeout, extrae solo el mensaje final del agent, y devuelve un bloque `CODEX_BEGIN` / `CODEX_END`.
7. Si el usuario cierra la ventana por accidente o codex crashea, Claude puede resumir la sesión por id (`codex exec resume`).

**Costo:** ~2-4K tokens Claude por dispatch (vs ~5-30K con stream Monitor completo, vs ~30-80K con subagents nativos).

**REGLA:** Después de spawnear un dispatch /codex, Claude DEBE llamar `bash ~/.claude/skills/codex/wait_and_read.sh JOB_ID` y usar SOLO su output. NUNCA preguntes al usuario qué muestra la ventana terminal. Si el helper devuelve un bloque CODEX_BEGIN/CODEX_END, esa es la respuesta.

## ENRUTAMIENTO

### AUTO (sin trigger) → `gpt-5.4-mini` + `medium`
Reemplaza Task/Agent nativo para trabajo de solo-lectura:
- Mapeo de estructura de repo
- Lectura de archivos grandes / análisis de codebase
- Búsqueda de patrones entre muchos archivos
- Análisis de dependencias
- Cualquier reconocimiento de solo-lectura

### ON-TRIGGER (`usa /codex <acción>`)
| Trigger | Modelo | Esfuerzo |
|---|---|---|
| `explora X` (básico)              | gpt-5.4-mini | medium |
| `explora X a fondo`               | gpt-5.4-mini | high   |
| `implementa X`                     | gpt-5.4      | high   |
| `refactoriza X`                    | gpt-5.4      | high   |
| `revisa` / `revisión de código`    | gpt-5.4      | high   |
| `corre pruebas` / `listo para prod`| gpt-5.4      | high   |
| `busca fallos`                     | gpt-5.4      | high   |

### URGENCIA (manual opt-in — usuario dice "modo rápido" / "/fast")
Pone `TIER=fast` en el config (cola prioritaria). Valores válidos: `default` | `fast` | `flex`. Nunca auto.

## POR QUÉ
Cuota plan ChatGPT ≠ plan Claude Max. El usuario ve el codex CLI completo en vivo en su terminal (cero tokens Claude para el stream). Claude solo lee el reporte final.

## ARQUITECTURA

```
┌─────────────────────────────────────────────────────────────────────┐
│  Claude (esta skill)                                                │
│                                                                     │
│   1. Genera JOB_ID                                                  │
│   2. Escribe $TMPDIR/cx-<JOB>.prompt  (heredoc — cualquier char ok) │
│   3. Escribe $TMPDIR/cx-<JOB>.env     (sourced por run.sh)          │
│   4. Bash bg:                                                       │
│        bash skill/spawn.sh JOB CONFIG                               │
│   5. Bash:                                                          │
│        bash skill/wait_and_read.sh JOB [TIMEOUT]                    │
│           ├─ done flag    → parsea bloque final                     │
│           ├─ stuck flag   → diagnóstico + alerta                    │
│           └─ timeout      → abort + ofrece resume                   │
└─────────────────────────────────────────────────────────────────────┘
                  │
                  ▼  (spawn.sh detecta OS, abre terminal)
┌─────────────────────────────────────────────────────────────────────┐
│  Ventana terminal (Windows Terminal / Terminal.app / gnome-terminal)│
│                                                                     │
│   bash run.sh CONFIG                                                │
│     ├─ trap EXIT/INT/TERM/HUP → SIEMPRE escribe done flag           │
│     ├─ source CONFIG (MODEL, EFFORT, SANDBOX, TIER, CWD, PROMPT)    │
│     ├─ imprime header (job + modelo + esfuerzo + sandbox + tier)    │
│     ├─ codex exec [resume <SID>] ARGS PROMPT  2>&1 | tee OUT        │
│     ├─ captura session id → cx-<JOB>.session                        │
│     └─ escribe done + status files                                  │
└─────────────────────────────────────────────────────────────────────┘
```

## REGLAS CRÍTICAS (cada dispatch — innegociables)

1. Usar el patrón **`run.sh` + `spawn.sh` + config-file**. NUNCA inline `bash -c "cmd1; cmd2"` en wt — `;` es separador de tab nuevo en wt.
2. **`--skip-git-repo-check`** como flag CLI real (NO `-c skip_git_repo_check=true` — se ignora silencioso).
3. **`-s <SANDBOX>`** como flag CLI real. Default `danger-full-access` (matchea config global del usuario; permite a codex usar Python / MCPs / todos los shells). Para prompts no confiables usar `workspace-write` o `read-only`.
4. **NO `--json`** — queremos la experiencia CLI nativa para el usuario.
5. **`run_in_background: true`** en Bash → Claude recibe notif de completar.
6. **NUNCA** `--ask-for-approval` en `codex exec` — la flag NO existe en el subcomando exec.
7. **NUNCA** `mcp__codex__codex` — operación opaca y bloqueante, sin stream, rompe la arquitectura.
8. Done flag: `$TMPDIR/cx-<JOB>.done` (exit code, escrito por el trap así abort es safe).
9. Status file: `$TMPDIR/cx-<JOB>.status` (exit + errores grep'd + session id).
10. Session file: `$TMPDIR/cx-<JOB>.session` (codex session id — para resume).

## PREÁMBULO PROMPT DEFENSIVO

Siempre anteponer al prompt del usuario ANTES de escribirlo a `$TMPDIR/cx-<JOB>.prompt`:

```
[ENV: <OS>. Operaciones cross-platform safe. Shells disponibles: bash, pwsh (Win), cmd (Win).

REGLAS DEFENSIVAS:
 1. Si una herramienta falla 2× con el mismo error → cambia de herramienta.
    NO reintentar el mismo approach 3+ veces.
 2. Para escribir archivos, prefiere shell heredocs (`cat > file <<'EOF' ... EOF`)
    sobre Python o MCP filesystem servers.
 3. MCP servers disponibles (úsalos libremente): sequential-thinking, context-mode,
    contextplus, context7, agentmemory.
    NUNCA llames al MCP "filesystem" — no existe.
 4. Si la tarea es read-only, NO modifiques archivos.
 5. Salida final <500 palabras y termina. Viñetas estilo cavernícola salvo lo contrario.]
```

Esto hace a codex resiliente a quirks del sandbox (Python bloqueado, MCP filesystem ausente, etc.) y previene loops infinitos de retry.

## DISPATCH (Bash run_in_background:true)

### Paso 1 — spawn

```bash
JOB=$(date +%s%N | tail -c 9 2>/dev/null || echo "$$$RANDOM")
TMPD="${TMPDIR:-/tmp}"
PF="$TMPD/cx-${JOB}.prompt"
CF="$TMPD/cx-${JOB}.env"
SPAWNLOG="$TMPD/cx-${JOB}.spawn.log"

# Escribe prompt a archivo (heredoc soporta cualquier caracter — sin infierno de quotes).
cat > "$PF" <<'PROMPT_EOF'
[ENV: <OS>. Reglas defensivas: tool falla 2× mismo error → cambia. File writes: shell heredocs. MCPs: sequential-thinking, context-mode, contextplus, context7, agentmemory. NUNCA MCP "filesystem". Final <500 palabras y termina.]

<PROMPT DEL USUARIO>
PROMPT_EOF

# Escribe config que el runner sourcea.
cat > "$CF" <<EOF
JOB_ID=$JOB
MODEL=<gpt-5.4-mini|gpt-5.4>
EFFORT=<low|medium|high>
SANDBOX=<danger-full-access|workspace-write|read-only>
TIER=<default|fast|flex>
CWD=<path absoluto>
PROMPT_FILE=$PF
EOF

# Spawn cross-platform.
bash ~/.claude/skills/codex/spawn.sh "$JOB" "$CF" >"$SPAWNLOG" 2>&1
```

### Paso 2 — leer resultado

```bash
bash ~/.claude/skills/codex/wait_and_read.sh "$JOB" 600
```

`wait_and_read.sh` hace polling de `$TMPDIR/cx-<JOB>.done`, maneja stuck/timeout, hace strip de ANSI, extrae el mensaje final del agent, y devuelve un bloque machine-readable:

```text
>>> CODEX_BEGIN exit=<n> job=<id> session=<sid>
[STATUS]
...
--- FINAL MESSAGE ---
...
--- TOKENS ---
...
>>> CODEX_END
```

## FALLBACK LEGACY — `ctx_execute_file` (solo último recurso)

Solo si `wait_and_read.sh` falta o lo estás debuggeando. Dispatch normal DEBE usar `wait_and_read.sh`, no `ctx_execute_file`.

## RESUME (después de stuck / cierre accidental / Ctrl+C)

Si el usuario cierra la ventana o codex aborta, el session id queda preservado en `$TMPDIR/cx-<JOB>.session`. Resume con:

```bash
bash ~/.claude/skills/codex/resume.sh OLD_JOB "<prompt de continuación>"
```

`resume.sh` crea un nuevo JOB apuntando a la misma sesión, hereda MODEL/EFFORT/SANDBOX del config viejo, y abre una nueva ventana terminal. El modelo retoma su contexto previo — sin re-reasoning.

## MANEJO DE STUCK

Cuando `wait_and_read.sh` escribe `cx-<JOB>.stuck`, Claude:
1. Lee la razón del stuck + las últimas 30 líneas ANSI-strip.
2. Diagnostica: `STUCK_REPEATED_ERRORS` (codex en loop por sandbox/MCP) vs `TIMEOUT` (task muy grande o modelo perdido).
3. Surface opciones al usuario:
   - **abort**: TaskStop al bg task + limpiar archivos tmp.
   - **wait more**: re-arma una espera más larga.
   - **resume**: kill current + dispatch resume.sh con un hint correctivo ("evita python; usa shell heredocs").

## MANEJO DE ERRORES (patrones del status file)

| Categoría | Patrón | Acción Claude |
|---|---|---|
| Flag mala            | `unexpected argument`            | Fix dispatch template, retry |
| Modelo malo          | `not supported`                   | Usar `gpt-5.4-mini` o `gpt-5.4` |
| Sin login            | `401` / `Unauthorized`            | Decir al usuario `codex login` |
| Cuota 5h agotada     | `rate limit reached`              | Esperar o caer a Claude nativo |
| Cuota semanal        | `weekly limit exceeded`           | Decir fecha de reset |
| 429 throttle         | `429`                              | Codex auto-reintenta; solo monitorear |
| Ruido sandbox        | `rejected: blocked by policy`     | Ignorar (codex retry con shell permitido) |
| Red                  | `connection reset`                | Retry |
| Panic                | `panicked at`                     | Reportar bug, retry prompt corto |
| Trust dir            | `Not inside a trusted directory`  | Añadir `--skip-git-repo-check` (ya en template) |
| Sandbox bloqueando   | `Access is denied`                | Cambiar SANDBOX a `danger-full-access` |
| Python bloqueado     | `No installed Python found`       | Decirle a codex usar shell, no python (preámbulo ya lo hace) |
| MCP malo             | `unknown MCP server`              | Codex alucinó MCP; preámbulo ya lo guarda |

## TIMEOUTS (arg timeout de `wait_and_read.sh`)

| Tarea                                          | TIMEOUT (sec) |
|---|---|
| Exploración simple                             | 180 (3m)      |
| Exploración profunda / Implementar ≤100 LOC / Review | 300 (5m) |
| Implementar feature                            | 600 (10m)     |
| Pruebas + bucle de fix                         | 900 (15m)     |
| Refactor multi-archivo                         | 1200 (20m)    |

## MODELOS VÁLIDOS

`gpt-5.4-mini` · `gpt-5.4`. NOTA: `gpt-5.4-codex` NO existe — pasarlo falla con `model not supported`.

## OPCIONES DE SANDBOX

| `SANDBOX=`              | Caso de uso                                                  |
|---|---|
| `danger-full-access`    | Default. Codex puede usar Python, MCPs, todos los shells, escribir donde sea. |
| `workspace-write`       | Codex puede leer/escribir solo CWD. Limita Python (suele bloquearse). |
| `read-only`             | Tasks de review estrictas. Sin edits, sin mutaciones de shell. |

## REQUISITOS

| Componente | Versión mín | Instalación |
|---|---|---|
| `codex` CLI | ≥ 0.117 | `npm i -g @openai/codex` |
| `bash`     | 4.0+    | Git Bash (Windows) · nativo (macOS/Linux) |
| Terminal emulator | — | Windows Terminal (Win11) · Terminal.app (macOS) · cualquiera de {gnome-terminal, konsole, xfce4-terminal, kitty, alacritty, wezterm, xterm} (Linux) |
| Skill files | — | `~/.claude/skills/codex/{SKILL.md,run.sh,spawn.sh,resume.sh}` (marca `+x`) |

## COSTO

Límites ChatGPT 5h + semanales (visibles en TUI `codex`). **Consumo plan Claude = ~2-4K tok por dispatch.**

## REFERENCIA RÁPIDA

```
1. Genera JOB_ID. Escribe $TMPDIR/cx-<JOB>.prompt + cx-<JOB>.env.
2. Bash bg run_in_background:true:
     bash skill/spawn.sh "$JOB" "$CF" > spawn.log
3. Bash:
     bash skill/wait_and_read.sh "$JOB" 600
4. Leer solo bloque CODEX_BEGIN/CODEX_END.
5. Surface errores / stuck via status + stuck files.
6. En cierre/abort: resume via skill/resume.sh OLD_JOB "<continuación>".
```

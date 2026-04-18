# Skill /codex — Instalar vía Claude Code

Copia el prompt completo de abajo y pégalo en Claude Code. Claude detecta tu OS, verifica prerequisitos, instala los archivos requeridos de la skill, y corre un smoke test.

---

```
Vas a instalar la skill /codex para mí. Sigue estos pasos en orden.

PASO 1 — Detecta OS y shells
Corre un solo comando Bash que imprima OS, versión de bash, versión de codex, disponibilidad del terminal emulator:

  uname -s; bash --version | head -1; command -v codex && codex --version || echo "codex MISSING"
  case "$(uname -s)" in
    Darwin*)            command -v osascript >/dev/null && echo "Terminal.app: ok" ;;
    Linux*)             for t in gnome-terminal konsole xfce4-terminal kitty alacritty wezterm xterm; do command -v "$t" >/dev/null && echo "term: $t" && break; done ;;
    MINGW*|MSYS*|CYGWIN*) command -v wt.exe >/dev/null && echo "wt.exe: ok" || echo "wt.exe missing — usaré cmd /k fallback" ;;
  esac

Si `codex` falta, dime que corra `npm i -g @openai/codex` y luego `codex login`, después continúa.
Si versión de codex < 0.117, dime que actualice.

PASO 2 — Clona el repo a una carpeta temporal
  TMP=$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/codex-skill-install")
  mkdir -p "$TMP"
  git clone --depth=1 https://github.com/xt0n1-t3ch/Codex-for-Claude-Code.git "$TMP/repo"

PASO 3 — Instala a ~/.claude/skills/codex/
Elige Inglés (default) o Español según mi preferencia. Default Inglés salvo que pida Español. Luego:

  DEST="$HOME/.claude/skills/codex"
  mkdir -p "$DEST"
  cp "$TMP/repo/skill/SKILL.es.md"        "$DEST/SKILL.md"          # o SKILL.md → SKILL.md para inglés
  cp "$TMP/repo/skill/run.sh"             "$DEST/run.sh"
  cp "$TMP/repo/skill/spawn.sh"           "$DEST/spawn.sh"
  cp "$TMP/repo/skill/spawn-windows.cmd"  "$DEST/spawn-windows.cmd"
  cp "$TMP/repo/skill/wait_and_read.sh"   "$DEST/wait_and_read.sh"
  cp "$TMP/repo/skill/resume.sh"          "$DEST/resume.sh"
  chmod +x "$DEST"/*.sh

PASO 4 — Verifica
  ls -la "$DEST"
  bash "$DEST/run.sh" --help 2>&1 | head -5 || true   # esperado: imprime "usage: run.sh CONFIG_FILE" o un error de source

Confirma que los archivos requeridos existen y que los `.sh` son ejecutables.

PASO 5 — Smoke test
Avísame que vas a despachar un /codex chico para verificar end-to-end. Usa AUTO mode (gpt-5.4-mini medium) con un prompt trivial tipo "lista los archivos top-level de este repo, cuéntalos, output <30 palabras, viñetas cavernícola". CWD = el repo que acabamos de clonar.

Usa la plantilla del dispatch en SKILL.md. Cuando complete, lee el mensaje final y muéstramelo.

Si algo falla en cualquier paso, surface el error claro con la ruta exacta del log (cx-<JOB>.txt / cx-<JOB>.spawn.log) — NO reintentes silencioso.

Cuando todo pase, dime:
  "/codex instalado y verificado. Plan ChatGPT es ahora tu cuota para trabajo delegado. Probá: 'usa /codex implementa <feature>'"
```

---

## Qué acaba de pasar

1. Claude detectó tu OS, bash, codex CLI, y el terminal emulator que puede spawnear.
2. Clonó este repo, copió los archivos requeridos a `~/.claude/skills/codex/`, marcó ejecutables los `.sh`.
3. Corrió un dispatch de verificación — abrió una ventana terminal real, codex hizo una exploración chica, Claude leyó la respuesta.

Listo. Desde aquí:
- Claude AUTO-rutea exploración / recon de solo-lectura a `gpt-5.4-mini medium` en silencio.
- Triggerea trabajo pesado explícito: `usa /codex implementa X` (gpt-5.4 high) · `usa /codex revisa` · `usa /codex busca fallos` · etc.
- Añade `"modo rápido"` o `"/fast"` para optar a la cola prioritaria.
- Ver el [README](../README.es.md) para reglas de routing completas y features de resiliencia.

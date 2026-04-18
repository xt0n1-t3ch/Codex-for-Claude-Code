# /codex Skill — Install via Claude Code

Copy the entire prompt below and paste it into Claude Code. Claude will detect your OS, verify prerequisites, install the required skill files, and run a smoke test.

---

```
You are installing the /codex skill for me. Follow these steps in order.

STEP 1 — Detect OS and shells
Run a single Bash command that prints OS, bash version, codex version, terminal emulator availability:

  uname -s; bash --version | head -1; command -v codex && codex --version || echo "codex MISSING"
  case "$(uname -s)" in
    Darwin*)            command -v osascript >/dev/null && echo "Terminal.app: ok" ;;
    Linux*)             for t in gnome-terminal konsole xfce4-terminal kitty alacritty wezterm xterm; do command -v "$t" >/dev/null && echo "term: $t" && break; done ;;
    MINGW*|MSYS*|CYGWIN*) command -v wt.exe >/dev/null && echo "wt.exe: ok" || echo "wt.exe missing — will use cmd /k fallback" ;;
  esac

If `codex` is missing, ask me to run `npm i -g @openai/codex` then `codex login`, then resume.
If codex version < 0.117, tell me to upgrade.

STEP 2 — Clone the repo to a temp folder
  TMP=$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/codex-skill-install")
  mkdir -p "$TMP"
  git clone --depth=1 https://github.com/xt0n1-t3ch/Codex-for-Claude-Code.git "$TMP/repo"

STEP 3 — Install to ~/.claude/skills/codex/
Pick English (default) or Spanish based on what I prefer. Default to English unless I asked for Spanish. Then:

  DEST="$HOME/.claude/skills/codex"
  mkdir -p "$DEST"
  cp "$TMP/repo/skill/SKILL.md"           "$DEST/SKILL.md"           # or SKILL.es.md → SKILL.md for Spanish
  cp "$TMP/repo/skill/run.sh"             "$DEST/run.sh"
  cp "$TMP/repo/skill/spawn.sh"           "$DEST/spawn.sh"
  cp "$TMP/repo/skill/spawn-windows.cmd"  "$DEST/spawn-windows.cmd"
  cp "$TMP/repo/skill/wait_and_read.sh"   "$DEST/wait_and_read.sh"
  cp "$TMP/repo/skill/resume.sh"          "$DEST/resume.sh"
  chmod +x "$DEST"/*.sh

STEP 4 — Verify
  ls -la "$DEST"
  bash "$DEST/run.sh" --help 2>&1 | head -5 || true   # expected: prints "usage: run.sh CONFIG_FILE" or sources error

Confirm to me that the required files exist and the `.sh` files are executable.

STEP 5 — Smoke test
Tell me you're about to dispatch a tiny `/codex` task to verify end-to-end. Use AUTO mode (gpt-5.4-mini medium) with a trivial prompt like "list the top-level files in this repo, count them, output <30 words, caveman bullets". CWD = the repo we just cloned.

Use the dispatch template from SKILL.md. After it completes, read the final message and show it to me.

If anything fails at any step, surface the error clearly with the exact log path (cx-<JOB>.txt / cx-<JOB>.spawn.log) — do NOT retry silently.

When everything passes, tell me:
  "/codex installed and verified. ChatGPT plan is now your delegated-work quota. Try: 'use /codex implement <feature>'"
```

---

## What just happened

1. Claude detected your OS, bash, codex CLI, and the terminal emulator it can spawn.
2. Cloned this repo, copied the required files to `~/.claude/skills/codex/`, marked the `.sh` files executable.
3. Ran a verification dispatch — opened a real terminal window, codex did a tiny exploration, Claude read the answer.

You're done. From here:
- Claude will AUTO-route exploration / read-only recon to `gpt-5.4-mini medium` silently.
- Trigger heavier work explicitly: `use /codex implement X` (gpt-5.4 high) · `use /codex review` · `use /codex find bugs` · etc.
- Add `"fast mode"` or `"/fast"` to opt into the priority queue.
- See the [README](../README.md) for full routing rules and resilience features.

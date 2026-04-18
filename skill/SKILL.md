---
name: codex
description: Delegate work to OpenAI Codex CLI (ChatGPT quota, NOT your Claude plan). AUTO-routes repo exploration / read-only recon to gpt-5.4-mini medium · ON-TRIGGER ("use /codex <action>") routes implement / refactor / review / tests / bug hunts to gpt-5.4 high. Each dispatch spawns a NEW terminal window (cross-platform: Windows Terminal · macOS Terminal · Linux gnome/konsole/xterm) running `codex exec` natively — user sees the full CLI live (model, effort, prompt, reasoning, exec, message, tokens). Claude only reads the final agent message via `wait_and_read.sh` (~2-4K tokens per dispatch). Per-job IDs prevent races. Trap-based done flag survives Ctrl+C / window-close. Stuck detection (file growth + repeated-error counter) auto-alerts after 90s. Sessions are resumable by id (codex exec resume) — accidental closes never lose work. Service tier `fast` / `flex` opt-in. Never use mcp__codex__codex (opaque, no stream).
---

# /codex — Delegate to OpenAI Codex CLI

## TL;DR

Each `/codex` dispatch:
1. Writes a per-job prompt + config file under `$TMPDIR`.
2. Spawns a new terminal window via `spawn.sh` (cross-platform).
3. The window runs `bash run.sh CONFIG` → which runs `codex exec` natively.
4. The user sees the real codex CLI live (model header, reasoning, exec calls, agent message, token usage).
5. Claude calls `bash ~/.claude/skills/codex/wait_and_read.sh JOB_ID [TIMEOUT_SEC]`.
6. `wait_and_read.sh` waits for done/stuck/timeout, extracts only the final agent message, and returns one `CODEX_BEGIN` / `CODEX_END` block.
7. If the user accidentally closes the window or codex crashes, Claude can resume the session by id (`codex exec resume`).

**Cost:** ~2-4K Claude tokens per dispatch (vs ~5-30K with full Monitor stream, ~30-80K with native subagents).

**RULE:** After spawning a /codex dispatch, Claude MUST call `bash ~/.claude/skills/codex/wait_and_read.sh JOB_ID` and use ONLY its output. NEVER ask the user what the terminal window shows. If the helper returns a CODEX_BEGIN/CODEX_END block, that is the answer.

## ROUTING

### AUTO (no trigger required) → `gpt-5.4-mini` + `medium`
Replaces native Task/Agent for read-only work:
- Repo structure mapping
- Reading large files / codebase analysis
- Pattern search across many files
- Dependency analysis
- Any read-only recon

### ON-TRIGGER (`use /codex <action>`)
| Trigger | Model | Effort |
|---|---|---|
| `explore X` (basic)             | gpt-5.4-mini | medium |
| `explore X deeply`              | gpt-5.4-mini | high   |
| `implement X`                    | gpt-5.4      | high   |
| `refactor X`                     | gpt-5.4      | high   |
| `review` / `code review`         | gpt-5.4      | high   |
| `run tests` / `prod ready`       | gpt-5.4      | high   |
| `find bugs`                      | gpt-5.4      | high   |

### URGENCY (manual opt-in only — user says "fast mode" / "/fast")
Set `TIER=fast` in the config (priority queue). Valid values: `default` | `fast` | `flex`. Never auto.

## WHY
ChatGPT plan quota ≠ Claude Max plan. The user sees the full live codex CLI in their own terminal window (zero Claude tokens for the stream). Claude only reads the final report.

## WT WINDOW BEHAVIOR

On Windows, `/codex` still uses the Bash wrapper for trap-safe done flags, but the spawned terminal path now seeds `TERM=xterm-256color`, `COLORTERM=truecolor`, keeps UTF-8 active, and runs `codex exec --color always` so colors, diffs, syntax highlighting, box-drawing characters, and other rich CLI output stay much closer to a direct PowerShell `codex exec` run.

## ARCHITECTURE

```
┌─────────────────────────────────────────────────────────────────────┐
│  Claude (this skill)                                                │
│                                                                     │
│   1. Generate JOB_ID                                                │
│   2. Write $TMPDIR/cx-<JOB>.prompt  (heredoc — any chars safe)      │
│   3. Write $TMPDIR/cx-<JOB>.env     (sourced by run.sh)             │
│   4. Bash bg:                                                       │
│        bash skill/spawn.sh JOB CONFIG                               │
│   5. Bash:                                                          │
│        bash skill/wait_and_read.sh JOB [TIMEOUT]                    │
│           ├─ done flag    → parse final block                       │
│           ├─ stuck flag   → diagnose + alert                        │
│           └─ timeout      → abort + offer resume                    │
└─────────────────────────────────────────────────────────────────────┘
                  │
                  ▼  (spawn.sh detects OS, opens terminal)
┌─────────────────────────────────────────────────────────────────────┐
│  Terminal window (Windows Terminal / Terminal.app / gnome-terminal) │
│                                                                     │
│   bash run.sh CONFIG                                                │
│     ├─ trap on EXIT/INT/TERM/HUP → ALWAYS writes done flag          │
│     ├─ source CONFIG (MODEL, EFFORT, SANDBOX, TIER, CWD, PROMPT)    │
│     ├─ print header (job + model + effort + sandbox + tier)         │
│     ├─ codex exec [resume <SID>] ARGS PROMPT  2>&1 | tee OUT        │
│     ├─ capture session id → cx-<JOB>.session                        │
│     └─ write done + status files                                    │
└─────────────────────────────────────────────────────────────────────┘
```

## CRITICAL RULES (every dispatch — non-negotiable)

1. Use the **`run.sh` + `spawn.sh` + config-file** pattern. NEVER inline `bash -c "cmd1; cmd2"` into wt — `;` is a wt new-tab separator.
2. **`--skip-git-repo-check`** as a real CLI flag (NOT `-c skip_git_repo_check=true` — silently ignored).
3. **`-s <SANDBOX>`** as a real CLI flag. Default `danger-full-access` (matches user's global codex config; lets codex use Python / MCPs / all shells). For untrusted prompts use `workspace-write` or `read-only`.
4. **NO `--json`** — we want the native CLI experience for the user.
5. **`run_in_background: true`** in Bash → Claude gets a completion notification.
6. **NEVER** `--ask-for-approval` on `codex exec` — flag does NOT exist on the exec subcommand.
7. **NEVER** `mcp__codex__codex` — opaque blocking op, no stream, defeats the architecture.
8. Done flag: `$TMPDIR/cx-<JOB>.done` (exit code, written by trap so abort is safe).
9. Status file: `$TMPDIR/cx-<JOB>.status` (exit + grep'd errors + session id).
10. Session file: `$TMPDIR/cx-<JOB>.session` (codex session id — for resume).

## DEFENSIVE PROMPT PREAMBLE

Always prepend to the user's prompt BEFORE writing it to `$TMPDIR/cx-<JOB>.prompt`:

```
[ENV: <OS>. Cross-platform safe ops. Available shells: bash, pwsh (Win), cmd (Win).

DEFENSIVE RULES:
 1. If a tool fails 2× with the same error → switch to a different tool.
    Do NOT retry the same approach 3+ times.
 2. For file writes, prefer shell heredocs (`cat > file <<'EOF' ... EOF`)
    over Python or MCP filesystem servers.
 3. MCP servers available (use freely): sequential-thinking, context-mode,
    contextplus, context7, agentmemory.
    NEVER call MCP "filesystem" — it does not exist.
 4. If the task is read-only, do NOT modify files.
 5. Output the final answer in <500 words then stop. Caveman-style bullets unless told otherwise.]
```

This makes codex resilient to sandbox quirks (Python blocked, MCP filesystem missing, etc.) and prevents infinite retry loops.

## DISPATCH (Bash run_in_background:true)

### Step 1 — spawn

```bash
JOB=$(date +%s%N | tail -c 9 2>/dev/null || echo "$$$RANDOM")
TMPD="${TMPDIR:-/tmp}"
PF="$TMPD/cx-${JOB}.prompt"
CF="$TMPD/cx-${JOB}.env"
SPAWNLOG="$TMPD/cx-${JOB}.spawn.log"

# Write prompt to file (heredoc supports any chars — no quoting hell).
cat > "$PF" <<'PROMPT_EOF'
[ENV: <OS>. Defensive rules: tool fails 2× same error → switch. File writes: shell heredocs. MCPs: sequential-thinking, context-mode, contextplus, context7, agentmemory. NEVER MCP "filesystem". Final answer <500 words then stop.]

<USER PROMPT HERE>
PROMPT_EOF

# Write config the runner will source.
cat > "$CF" <<EOF
JOB_ID=$JOB
MODEL=<gpt-5.4-mini|gpt-5.4>
EFFORT=<low|medium|high>
SANDBOX=<danger-full-access|workspace-write|read-only>
TIER=<default|fast|flex>
CWD=<absolute path>
PROMPT_FILE=$PF
EOF

# Spawn cross-platform.
bash ~/.claude/skills/codex/spawn.sh "$JOB" "$CF" >"$SPAWNLOG" 2>&1
```

### Step 2 — read result

```bash
bash ~/.claude/skills/codex/wait_and_read.sh "$JOB" 600
```

`wait_and_read.sh` polls `$TMPDIR/cx-<JOB>.done`, handles stuck/timeout detection, strips ANSI, extracts the final agent message, and returns one machine-readable block:

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

## LEGACY FALLBACK — `ctx_execute_file` (last resort only)

Legacy only if `wait_and_read.sh` is missing or being debugged. Normal dispatches MUST use `wait_and_read.sh`, not `ctx_execute_file`.

## RESUME (after stuck / accidental close / Ctrl+C)

If the user closes the window or codex aborts, the session id is preserved in `$TMPDIR/cx-<JOB>.session`. Resume with:

```bash
bash ~/.claude/skills/codex/resume.sh OLD_JOB "<continuation prompt>"
```

`resume.sh` creates a new JOB pointing at the same session, inheriting MODEL/EFFORT/SANDBOX from the old config, and spawns a fresh terminal window. The model picks up its prior context — no re-reasoning needed.

## STUCK HANDLING

When `wait_and_read.sh` writes `cx-<JOB>.stuck`, Claude:
1. Reads the stuck reason + the last 30 ANSI-stripped lines.
2. Diagnoses: `STUCK_REPEATED_ERRORS` (codex looping on a sandbox/MCP issue) vs `TIMEOUT` (task too big or model wandering).
3. Surfaces options to the user:
   - **abort**: TaskStop the bg task + clean up tmp files.
   - **wait more**: re-arm a longer wait.
   - **resume**: kill current + dispatch resume.sh with a corrective hint ("avoid python; use shell heredocs").

## ERROR HANDLING (status file patterns)

| Category | Pattern | Claude action |
|---|---|---|
| Bad flag             | `unexpected argument`            | Fix dispatch template, retry |
| Bad model            | `not supported`                   | Use `gpt-5.4-mini` or `gpt-5.4` |
| Not logged in        | `401` / `Unauthorized`            | Tell user to run `codex login` |
| 5h quota exhausted   | `rate limit reached`              | Wait or fall back to Claude native |
| Weekly quota         | `weekly limit exceeded`           | Tell user reset date |
| 429 throttle         | `429`                              | Codex auto-retries; just monitor |
| Sandbox noise        | `rejected: blocked by policy`     | Ignore (codex retries with allowed shell) |
| Network              | `connection reset`                | Retry |
| Panic                | `panicked at`                     | Report bug, retry shorter prompt |
| Trust dir            | `Not inside a trusted directory`  | Add `--skip-git-repo-check` (already in template) |
| Sandbox blocking     | `Access is denied`                | Switch SANDBOX to `danger-full-access` |
| Python unavailable   | `No installed Python found`       | Tell codex to use shell, not python (preamble already does this) |
| Bad MCP              | `unknown MCP server`              | Codex hallucinated MCP; preamble guards against this |

## TIMEOUTS (`wait_and_read.sh` timeout arg)

| Task                                          | TIMEOUT (sec) |
|---|---|
| Explore simple                                | 180 (3m)      |
| Explore deep / Implement ≤100 LOC / Review    | 300 (5m)      |
| Implement feature                             | 600 (10m)     |
| Tests + fix loop                              | 900 (15m)     |
| Multi-file refactor                           | 1200 (20m)    |

## VALID MODELS

`gpt-5.4-mini` · `gpt-5.4`. NOTE: `gpt-5.4-codex` does NOT exist — passing it fails with `model not supported`.

## SANDBOX OPTIONS

| `SANDBOX=`              | Use case                                                     |
|---|---|
| `danger-full-access`    | Default. Codex can use Python, MCPs, all shells, write anywhere. |
| `workspace-write`       | Codex can read/write CWD only. Limits Python (often blocked). |
| `read-only`             | Strict review tasks. No edits, no shell mutations. |

## REQUIREMENTS

| Component | Min version | Install |
|---|---|---|
| `codex` CLI | ≥ 0.117 | `npm i -g @openai/codex` |
| `bash`     | 4.0+    | Git Bash (Windows) · native (macOS/Linux) |
| Terminal emulator | — | Windows Terminal (Win11) · Terminal.app (macOS) · any of {gnome-terminal, konsole, xfce4-terminal, kitty, alacritty, wezterm, xterm} (Linux) |
| Skill files | — | `~/.claude/skills/codex/{SKILL.md,run.sh,spawn.sh,resume.sh}` (mark `+x`) |

## COST

ChatGPT 5h + weekly limits (visible in `codex` TUI status line). **Claude plan burn = ~2-4K tok per dispatch.**

## QUICKREF

```
1. Generate JOB_ID. Write $TMPDIR/cx-<JOB>.prompt + cx-<JOB>.env.
2. Bash bg run_in_background:true:
     bash skill/spawn.sh "$JOB" "$CF" > spawn.log
3. Bash:
     bash skill/wait_and_read.sh "$JOB" 600
4. Read only CODEX_BEGIN/CODEX_END block.
5. Surface errors / stuck via status + stuck files.
6. On close/abort: resume via skill/resume.sh OLD_JOB "<continuation>".
```

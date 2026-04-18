<div align="center">

# Codex for Claude Code

**Run the OpenAI Codex CLI inside Claude Code. Spend ChatGPT quota, not your Claude plan.**

A production-ready Claude Code skill that delegates exploration, implementation, reviews, tests and refactors to `codex exec` running natively in a brand-new terminal window — while Claude only sees the final report.

[![License: MIT](https://img.shields.io/badge/license-MIT-8A2BE2?style=for-the-badge)](./LICENSE)
[![Claude Code](https://img.shields.io/badge/Claude_Code-D97757?style=for-the-badge&logo=anthropic&logoColor=white)](https://claude.com/claude-code)
[![OpenAI Codex](https://img.shields.io/badge/OpenAI_Codex-412991?style=for-the-badge&logo=openai&logoColor=white)](https://github.com/openai/codex)
[![Platforms](https://img.shields.io/badge/platform-Windows_•_macOS_•_Linux-0A7E8C?style=for-the-badge)](#cross-platform-support)

[![Status](https://img.shields.io/badge/status-production_ready-brightgreen?style=flat-square)](#)
[![Cost saving](https://img.shields.io/badge/Claude_plan_savings-~92%25-FFD700?style=flat-square)](#cost-comparison)
[![PRs welcome](https://img.shields.io/badge/PRs-welcome-FF69B4?style=flat-square)](#contributing)

[**English**](./README.md) • [**Español**](./README.es.md)

</div>

---

## Table of Contents

- [What it does](#what-it-does)
- [Why it matters](#why-it-matters)
- [Architecture](#architecture)
- [Quick Start](#quick-start)
- [Routing rules](#routing-rules)
- [Cost comparison](#cost-comparison)
- [Cross-platform support](#cross-platform-support)
- [Resilience features](#resilience-features)
- [Troubleshooting](#troubleshooting)
- [Credits](#credits)
- [License](#license)

---

## What it does

Drop this skill into `~/.claude/skills/codex/` and Claude Code gains a new ability: it can spin up a separate terminal window that runs the **real OpenAI Codex CLI** to do the heavy lifting, then read only the final answer.

You watch the full live codex experience in your own terminal pane (model header, reasoning, exec calls, agent message, token usage). Claude orchestrates and reads the final result — never the live stream.

```
┌──────────────────┐         ┌────────────────────────────┐         ┌────────────────────┐
│  You ask Claude  │ ──────▶ │  Claude dispatches /codex  │ ──────▶ │  New terminal pane │
└──────────────────┘         │  (per-job id, prompt file) │         │  runs codex exec   │
                             └────────────────────────────┘         │  (you watch live)  │
                                       │                            └────────────────────┘
                                       │                                       │
                                       ▼                                       ▼
                             ┌────────────────────────────┐         ┌────────────────────┐
                             │  wait_and_read.sh polls +  │ ◀────── │  Done flag + status│
                             │  parses single truth block │         │  + session id file │
                             └────────────────────────────┘         └────────────────────┘
                                       │
                                       ▼
                             ┌────────────────────────────┐
                             │  CODEX_BEGIN / END block   │
                             │  final agent message only  │
                             │  (~2K Claude tokens)       │
                             └────────────────────────────┘
```

---

## Why it matters

| Problem | Solution |
|---|---|
| Native Claude `Task`/`Agent` subagents stream the entire transcript into Claude's context (~30-80K tokens per task). One pesky exploration can blow your 5-hour Max window. | This skill delegates to `codex` — a separate process drawing from your **ChatGPT Plus/Pro quota**, not your Claude plan. Claude only reads the final report (~2K tokens). |
| You can't see what a subagent is doing in real time. | The new terminal window shows the *real* `codex exec` CLI live — model, reasoning, exec calls, message, tokens. Pause with `Ctrl+S`, resume with `Ctrl+Q`. |
| Accidentally close the terminal? Your work is gone. | Every dispatch captures the codex `session id`. Run `resume.sh` to continue from where you left off — no re-reasoning. |
| Codex can hang on sandbox quirks (Python blocked, missing MCP servers, signal pipe errors). | Defensive prompt preamble + automatic stuck detection (file-growth heartbeat + repeated-error counter) auto-alert after 90 seconds with a clean diagnosis. |

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│  Claude (this skill)                                                │
│   1. Generate JOB_ID                                                │
│   2. Write $TMPDIR/cx-<JOB>.prompt    (heredoc — any chars safe)    │
│   3. Write $TMPDIR/cx-<JOB>.env       (sourced by run.sh)           │
│   4. Bash background:                                               │
│        bash skill/spawn.sh JOB CONFIG                               │
│        bash skill/wait_and_read.sh JOB [TIMEOUT]                    │
│           ├─ done flag    → parse final block                       │
│           ├─ stuck flag   → diagnose + alert user                   │
│           └─ timeout      → abort + offer resume                    │
└─────────────────────────────────────────────────────────────────────┘
                  │
                  ▼  (spawn.sh detects OS, opens terminal)
┌─────────────────────────────────────────────────────────────────────┐
│  Terminal window (Windows Terminal · Terminal.app · gnome-terminal) │
│                                                                     │
│   bash run.sh CONFIG                                                │
│     ├─ trap on EXIT/INT/TERM/HUP → ALWAYS writes done flag          │
│     ├─ source CONFIG (MODEL, EFFORT, SANDBOX, TIER, CWD, PROMPT)    │
│     ├─ codex exec [resume <SID>] ARGS PROMPT  2>&1 | tee OUT        │
│     ├─ capture session id → cx-<JOB>.session  (for resume)          │
│     └─ write done + status files                                    │
└─────────────────────────────────────────────────────────────────────┘
```

**Files in this repo:**

| File | Purpose |
|---|---|
| [`skill/SKILL.md`](./skill/SKILL.md) · [`SKILL.es.md`](./skill/SKILL.es.md) | The skill definition Claude reads (English / Spanish). |
| [`skill/run.sh`](./skill/run.sh) | Cross-platform runner that runs **inside** the spawned terminal pane. Trap-based done flag, session capture, sandbox/tier configurable. |
| [`skill/spawn.sh`](./skill/spawn.sh) | Cross-platform terminal spawner. Detects OS, picks best terminal emulator. |
| [`skill/spawn-windows.cmd`](./skill/spawn-windows.cmd) | Windows helper that preserves quoting when `spawn.sh` launches `wt.exe` or `cmd`. |
| [`skill/wait_and_read.sh`](./skill/wait_and_read.sh) | Polls + reads result. Single call replaces inline wait loop + ctx_execute_file. |
| [`skill/resume.sh`](./skill/resume.sh) | Resumes an interrupted session by id. Inherits previous job's MODEL/EFFORT/SANDBOX. |
| [`setup/SETUP.md`](./setup/SETUP.md) · [`SETUP.es.md`](./setup/SETUP.es.md) | Copy-paste install prompts for Claude Code. |

---

## Quick Start

### 1. Prerequisites

```bash
# OpenAI Codex CLI
npm i -g @openai/codex

# Sign in with your ChatGPT Plus / Pro account (one-time)
codex login

# Verify (needs >= 0.117)
codex --version
```

### 2. Install the skill — one-liner per OS

<details>
<summary><b>🪟 Windows (PowerShell or Git Bash)</b></summary>

```powershell
git clone https://github.com/xt0n1-t3ch/Codex-for-Claude-Code.git
cd Codex-for-Claude-Code
mkdir -Force "$env:USERPROFILE\.claude\skills\codex" | Out-Null
copy skill\SKILL.md            "$env:USERPROFILE\.claude\skills\codex\SKILL.md"
copy skill\run.sh              "$env:USERPROFILE\.claude\skills\codex\run.sh"
copy skill\spawn.sh            "$env:USERPROFILE\.claude\skills\codex\spawn.sh"
copy skill\spawn-windows.cmd   "$env:USERPROFILE\.claude\skills\codex\spawn-windows.cmd"
copy skill\wait_and_read.sh    "$env:USERPROFILE\.claude\skills\codex\wait_and_read.sh"
copy skill\resume.sh           "$env:USERPROFILE\.claude\skills\codex\resume.sh"
# (For Spanish) copy skill\SKILL.es.md "$env:USERPROFILE\.claude\skills\codex\SKILL.md"
```

Requires **Git for Windows** (Git Bash) and **Windows Terminal** (Win11 default; Win10 install from Microsoft Store).
</details>

<details>
<summary><b>🍎 macOS (zsh / bash)</b></summary>

```bash
git clone https://github.com/xt0n1-t3ch/Codex-for-Claude-Code.git
cd Codex-for-Claude-Code
mkdir -p ~/.claude/skills/codex
cp skill/SKILL.md skill/run.sh skill/spawn.sh skill/spawn-windows.cmd skill/wait_and_read.sh skill/resume.sh ~/.claude/skills/codex/
chmod +x ~/.claude/skills/codex/*.sh
# (For Spanish) cp skill/SKILL.es.md ~/.claude/skills/codex/SKILL.md
```

Uses Terminal.app via AppleScript. iTerm2 / WezTerm / Alacritty users: skill/spawn.sh falls through to `osascript Terminal.app` by default — adapt if needed.
</details>

<details>
<summary><b>🐧 Linux (bash)</b></summary>

```bash
git clone https://github.com/xt0n1-t3ch/Codex-for-Claude-Code.git
cd Codex-for-Claude-Code
mkdir -p ~/.claude/skills/codex
cp skill/SKILL.md skill/run.sh skill/spawn.sh skill/spawn-windows.cmd skill/wait_and_read.sh skill/resume.sh ~/.claude/skills/codex/
chmod +x ~/.claude/skills/codex/*.sh
# (For Spanish) cp skill/SKILL.es.md ~/.claude/skills/codex/SKILL.md
```

Auto-detects: gnome-terminal, konsole, xfce4-terminal, kitty, alacritty, wezterm, xterm (in that order).
</details>

### 3. Restart Claude Code

Run `/reload` or close and reopen. Verify the skill loaded:

```
codex: Delegate work to OpenAI Codex CLI (ChatGPT quota, NOT your Claude plan)…
```

### 4. Or let Claude install it for you

Paste the contents of [`setup/SETUP.md`](./setup/SETUP.md) (or [`SETUP.es.md`](./setup/SETUP.es.md)) into Claude Code. Claude walks through prerequisites, installs the skill, and runs a verification dispatch.

---

## Routing rules

### AUTO (no trigger — Claude routes silently)

Claude delegates these to **`gpt-5.4-mini` + `medium`** without you asking:

- Repo structure mapping
- Reading large files
- Pattern search across many files
- Dependency analysis
- Any read-only recon

### ON-TRIGGER (`use /codex <action>`)

| Trigger | Model | Effort |
|---|---|---|
| `use /codex explore X` *(basic)*    | `gpt-5.4-mini` | `medium` |
| `use /codex explore X deeply`        | `gpt-5.4-mini` | `high`   |
| `use /codex implement X`             | `gpt-5.4`      | `high`   |
| `use /codex refactor X`              | `gpt-5.4`      | `high`   |
| `use /codex review`                  | `gpt-5.4`      | `high`   |
| `use /codex run tests` / `prod ready`| `gpt-5.4`      | `high`   |
| `use /codex find bugs`               | `gpt-5.4`      | `high`   |

### Urgency tier (manual opt-in)

Say `"fast mode"`, `"it's urgent"`, or `"/fast"`. Claude sets `TIER=fast` (priority queue). Valid: `default` · `fast` · `flex`. Never auto.

---

## Cost comparison

Claude tokens consumed **on your Claude plan** per dispatch:

| Approach | Per dispatch | 2-hour heavy session (28 dispatches) |
|---|---:|---:|
| Native subagent (`Task` / `Agent`) | 30K – 80K | 800K – 2.2M |
| `/codex` with full Monitor stream  | 5K – 30K  | 150K – 525K |
| **`/codex` (this skill)**          | **2K – 4K** | **~60K – 110K** |

```
Native subagent:   ████████████████████████████  ~30-80K
Monitor full:      ████████████                    ~5-30K
THIS skill:        █                                ~2-4K  ← 92% savings
```

ChatGPT compute is paid out of your **ChatGPT Plus/Pro 5-hour and weekly limits** (visible in the `codex` TUI status line). Net effect: your Claude plan stretches ~10× further on delegated work.

---

## Cross-platform support

| OS | Terminal emulator | Spawn mechanism | Status |
|---|---|---|---|
| **Windows 11** | Windows Terminal (`wt.exe`) | `cmd /c start "" wt.exe -w 0 nt …` | ✅ Tested |
| **Windows 10** | `wt.exe` if installed, else `cmd /k` fallback | same | ✅ Fallback works |
| **macOS** | Terminal.app via AppleScript | `osascript -e 'tell app "Terminal"…'` | ✅ |
| **Linux (GNOME)** | `gnome-terminal` | `gnome-terminal --title=… -- bash …` | ✅ |
| **Linux (KDE)** | `konsole` | `konsole --title … -e bash …` | ✅ |
| **Linux (other)** | xfce4-terminal · kitty · alacritty · wezterm · xterm | first available, in priority order | ✅ |

Detection happens in [`skill/spawn.sh`](./skill/spawn.sh) via `$OSTYPE` / `uname -s`.

---

## Resilience features

This is what makes it production-ready:

| Concern | Mitigation |
|---|---|
| **Race conditions** between concurrent dispatches | Per-job IDs (`cx-<JOB_ID>.{prompt,env,txt,done,status,stuck,session,spawn.log}`). |
| **Abort hangs Claude** (Ctrl+C / window close) | `trap EXIT INT TERM HUP` in `run.sh` always writes the done flag. |
| **Codex stuck in a retry loop** | Wait loop watches file-growth heartbeat (90s threshold) + repeated-error counter (3+ matches of `Access is denied`/`signal pipe`/etc) → writes `cx-<JOB>.stuck`. |
| **Hard timeout** | `TIMEOUT` per task type (3-20 min) → writes stuck flag and surfaces to user. |
| **Accidental window close** | Session id captured to `cx-<JOB>.session` → `resume.sh` continues with `codex exec resume <id>`. |
| **Fragile prompt transport** | Prompts written to file via heredoc, never passed via argv through `bash → wt → bash`. |
| **Sandbox blocking codex tools** | Default `SANDBOX=danger-full-access` lets codex use Python, MCPs, all shells. Configurable per dispatch. |
| **Codex hallucinated MCP names** | Defensive prompt preamble explicitly lists available MCPs and forbids non-existent ones (`filesystem`). |
| **Verbose answers truncated** | `wait_and_read.sh` uses marker-based extraction (between `codex\n` and `tokens used\n`), not `tail -100`. |
| **Lazy polling / asking user about terminal contents** | `wait_and_read.sh` as single source of truth + `SKILL.md` RULE forbidding fallback chatter. |

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `unexpected argument '--ask-for-approval'` | Remove the flag — it doesn't exist on `codex exec`. |
| `not inside a trusted directory` | `--skip-git-repo-check` must be a real CLI flag (not `-c`). Already in template. |
| `model is not supported` | Valid: `gpt-5.4-mini`, `gpt-5.4`. `gpt-5.4-codex` does **not** exist. |
| Codex hangs reading stdin | `run.sh` already redirects via `tee`; ensure no `bash -c` wrapper sneaks past. |
| `Access is denied` loops in pwsh | Switch `SANDBOX` to `danger-full-access` (default) or update prompt preamble to forbid Python. |
| `unknown MCP server 'filesystem'` | Codex hallucinated. Preamble already forbids it. Re-dispatch. |
| Window closes immediately on Windows | Ensure `wt.exe` is installed and Git Bash's `bash` is in `PATH`. Check `cx-<JOB>.spawn.log`. |
| Stuck flag fires falsely | Increase `STUCK_THRESHOLD` in the dispatch template (default 120 s). |

---

## Credits

Built by [@xt0n1-t3ch](https://github.com/xt0n1-t3ch). Inspired by [openai/codex-plugin-cc](https://github.com/openai/codex-plugin-cc) — this repo sidesteps the plugin's `app-server` hang by using native `codex exec`.

---

## Contributing

PRs welcome. Areas of interest:

- iTerm2 / WezTerm / Alacritty preference detection on macOS
- Windows: Wezterm / Tabby support
- Codex CLI version sniffing in `run.sh` to feature-detect new flags
- Resume workflow polish (auto-suggest after stuck flag)

---

## License

[MIT](./LICENSE)

#!/usr/bin/env bash
# codex native runner — invoked inside the spawned terminal pane.
#
# Reads ALL parameters from a per-job config file (sourced env). This avoids
# fragile argv quoting through bash → terminal-emulator → bash chain and lets
# prompts contain newlines, quotes, %VAR%, !, backslashes, etc.
#
# Cross-platform: works on Windows (Git Bash), macOS, Linux.
#
# Usage: run.sh CONFIG_FILE
#
# CONFIG_FILE defines:
#   JOB_ID       (required) Unique alphanumeric id for this dispatch.
#   MODEL        (required) gpt-5.4-mini | gpt-5.4
#   EFFORT       (required) low | medium | high
#   CWD          (required) Absolute working directory for codex.
#   PROMPT_FILE  (required) Absolute path to text file with the prompt.
#   SANDBOX      (optional, default: danger-full-access) read-only|workspace-write|danger-full-access
#   TIER         (optional, default: default)            default|fast|flex
#   SESSION_ID   (optional)                               If set, runs `codex exec resume <id>`.
#   EXTRA_FLAGS  (optional)                               Extra `-c key=val` pairs (advanced).
#
# Files produced under TMPDIR (defaults to /tmp):
#   cx-<JOB_ID>.txt        codex stdout/stderr (tee'd)
#   cx-<JOB_ID>.done       exit code (always written via trap)
#   cx-<JOB_ID>.status     exit + grep'd error patterns + session id
#   cx-<JOB_ID>.session    captured codex session id (for resume)

set -u

CONFIG="${1:?usage: run.sh CONFIG_FILE}"
[ -f "$CONFIG" ] || { echo "[ERROR] config not found: $CONFIG" >&2; sleep 5; exit 2; }

# shellcheck disable=SC1090
source "$CONFIG"

: "${JOB_ID:?JOB_ID required in config}"
: "${MODEL:?MODEL required}"
: "${EFFORT:?EFFORT required}"
: "${CWD:?CWD required}"
: "${PROMPT_FILE:?PROMPT_FILE required}"
SANDBOX="${SANDBOX:-danger-full-access}"
TIER="${TIER:-default}"
SESSION_ID="${SESSION_ID:-}"
EXTRA_FLAGS="${EXTRA_FLAGS:-}"

TMPD="${TMPDIR:-/tmp}"
OUT="$TMPD/cx-${JOB_ID}.txt"
DONE="$TMPD/cx-${JOB_ID}.done"
STATUS="$TMPD/cx-${JOB_ID}.status"
SESSION_FILE="$TMPD/cx-${JOB_ID}.session"

# Trap fires on normal exit, signals (SIGINT/SIGTERM/SIGHUP), and shell errors.
# Always writes the done flag → Claude's wait loop never hangs (review CRITICAL #2).
on_exit() {
  rc=$?
  [ -f "$DONE" ] || echo "$rc" > "$DONE" 2>/dev/null
  printf '\n\033[1;36m============================================================\033[0m\n'
  printf '\033[1;36m  DONE  exit=%s  job=%s\033[0m\n' "$rc" "$JOB_ID"
  printf '\033[1;36m  press ENTER to close (session preserved for resume)\033[0m\n'
  printf '\033[1;36m============================================================\033[0m\n'
  read -r || true
}
trap on_exit EXIT INT TERM HUP

# UTF-8 + truecolor/256-color hints for Windows Terminal / Git Bash.
export LANG="${LANG:-C.UTF-8}" LC_ALL="${LC_ALL:-C.UTF-8}"
export TERM="${TERM:-xterm-256color}" COLORTERM="${COLORTERM:-truecolor}"
command -v chcp.com >/dev/null 2>&1 && chcp.com 65001 >/dev/null 2>&1 || true

[ -f "$PROMPT_FILE" ] || { echo "[ERROR] prompt file missing: $PROMPT_FILE" >&2; exit 2; }
PROMPT=$(cat "$PROMPT_FILE")
PROMPT_PREVIEW=$(printf '%s' "$PROMPT" | tr '\n' ' ' | head -c 100)

clear
printf '\033[1;36m============================================================\033[0m\n'
printf '\033[1;36m  CODEX DISPATCH\033[0m  job=\033[1;33m%s\033[0m\n' "$JOB_ID"
printf '  model:   %s\n' "$MODEL"
printf '  effort:  %s\n' "$EFFORT"
printf '  sandbox: %s\n' "$SANDBOX"
printf '  tier:    %s\n' "$TIER"
printf '  cwd:     %s\n' "$CWD"
[ -n "$SESSION_ID" ] && printf '  resume:  %s\n' "$SESSION_ID"
printf '  prompt:  %s%s\n' "$PROMPT_PREVIEW" "$([ ${#PROMPT} -gt 100 ] && echo ' …')"
printf '\033[1;36m============================================================\033[0m\n\n'

# Build optional service_tier flag (review CRITICAL #3 — only fast|flex are valid).
TIER_FLAG=()
case "$TIER" in
  fast) TIER_FLAG=(-c "service_tier=\"fast\"") ;;
  flex) TIER_FLAG=(-c "service_tier=\"flex\"") ;;
  default) ;;
  *) printf '\033[1;33m[warn] unknown TIER=%s — using default\033[0m\n' "$TIER" ;;
esac

# Optional extra `-c key=val` pairs (each whitespace-separated).
EXTRA_ARR=()
if [ -n "$EXTRA_FLAGS" ]; then
  # shellcheck disable=SC2206
  EXTRA_ARR=($EXTRA_FLAGS)
fi

# Common args. Reasoning effort + clean shell env (no user profile noise).
COMMON_ARGS=(
  --color always
  --skip-git-repo-check
  -m "$MODEL"
  -s "$SANDBOX"
  -c "model_reasoning_effort=\"$EFFORT\""
  -c "shell_environment_policy.experimental_use_profile=false"
  -c "allow_login_shell=false"
  "${TIER_FLAG[@]}"
  "${EXTRA_ARR[@]}"
  -C "$CWD"
)

# Run codex NATIVE (no --json) so the user sees the real CLI experience.
# Output mirrored to OUT for Claude's later ctx_execute_file read.
if [ -n "$SESSION_ID" ]; then
  codex exec "${COMMON_ARGS[@]}" resume "$SESSION_ID" "$PROMPT" 2>&1 | tee "$OUT"
else
  codex exec "${COMMON_ARGS[@]}" "$PROMPT" 2>&1 | tee "$OUT"
fi
EXIT=${PIPESTATUS[0]}

# Capture session id from header (for resume support).
NEW_SESSION=$(grep -m1 -E '^session id:' "$OUT" 2>/dev/null | awk '{print $3}')
[ -n "$NEW_SESSION" ] && echo "$NEW_SESSION" > "$SESSION_FILE"

# Done + status (trap is fallback for abort cases; this is the happy path).
echo "$EXIT" > "$DONE"
{
  echo "exit=$EXIT"
  echo "job=$JOB_ID"
  [ -n "$NEW_SESSION" ] && echo "session=$NEW_SESSION"
  tail -120 "$OUT" 2>/dev/null \
    | sed 's/\x1b\[[0-9;]*[mK]//g' \
    | grep -iE 'rate.?limit|quota|weekly|429|401|unauthorized|panic|FATAL|^Error|not supported|unexpected argument|insufficient|expired|invalid_request|not inside|Access is denied|signal pipe|No installed Python|unknown MCP server|connection reset|timeout' \
    | head -10
} > "$STATUS"

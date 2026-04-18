#!/usr/bin/env bash
# Resume a previously interrupted codex session.
#
# Usage: resume.sh JOB_ID NEW_PROMPT [SESSION_ID]
#
# Looks up the saved session id at $TMPDIR/cx-<JOB_ID>.session (or accepts one
# explicitly as the third arg), creates a fresh JOB and CONFIG that points at
# the existing session, and spawns a new terminal pane via spawn.sh.
#
# This lets the user (or Claude) recover from accidentally closing the wt window,
# from a wt crash, or from `Ctrl+C` aborts — without re-running expensive
# reasoning the model already did.

set -u

OLD_JOB="${1:?usage: resume.sh OLD_JOB_ID NEW_PROMPT [SESSION_ID]}"
NEW_PROMPT_TXT="${2:?prompt required}"
SESSION_OVERRIDE="${3:-}"

TMPD="${TMPDIR:-/tmp}"
SESSION_FILE="$TMPD/cx-${OLD_JOB}.session"
OLD_CONFIG="$TMPD/cx-${OLD_JOB}.env"

if [ -n "$SESSION_OVERRIDE" ]; then
  SESSION_ID="$SESSION_OVERRIDE"
elif [ -f "$SESSION_FILE" ]; then
  SESSION_ID=$(cat "$SESSION_FILE")
else
  echo "[resume] no session id found for job $OLD_JOB" >&2
  echo "[resume] expected: $SESSION_FILE" >&2
  exit 2
fi

[ -n "$SESSION_ID" ] || { echo "[resume] empty session id" >&2; exit 2; }

# Inherit MODEL/EFFORT/SANDBOX/TIER/CWD from old config if available.
if [ -f "$OLD_CONFIG" ]; then
  # shellcheck disable=SC1090
  source "$OLD_CONFIG"
fi

NEW_JOB="resume-$(date +%s | tail -c 7)$RANDOM"
NEW_PROMPT_FILE="$TMPD/cx-${NEW_JOB}.prompt"
NEW_CONFIG="$TMPD/cx-${NEW_JOB}.env"

printf '%s' "$NEW_PROMPT_TXT" > "$NEW_PROMPT_FILE"

cat > "$NEW_CONFIG" <<EOF
JOB_ID=$NEW_JOB
MODEL=${MODEL:-gpt-5.4-mini}
EFFORT=${EFFORT:-medium}
SANDBOX=${SANDBOX:-danger-full-access}
TIER=${TIER:-default}
CWD=${CWD:-$PWD}
PROMPT_FILE=$NEW_PROMPT_FILE
SESSION_ID=$SESSION_ID
EOF

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$SCRIPT_DIR/spawn.sh" "$NEW_JOB" "$NEW_CONFIG"

echo "$NEW_JOB"

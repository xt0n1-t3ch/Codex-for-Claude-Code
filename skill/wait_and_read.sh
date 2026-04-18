#!/usr/bin/env bash
# wait_and_read.sh — single source of truth for /codex result polling + parsing.
#
# Usage: wait_and_read.sh JOB_ID [TIMEOUT_SEC]

set -u

usage() {
  echo "usage: wait_and_read.sh JOB_ID [TIMEOUT_SEC]" >&2
}

JOB_ID="${1:-}"
TIMEOUT="${2:-600}"

[ -n "$JOB_ID" ] || { usage; exit 2; }

TMPD="${TMPDIR:-/tmp}"
OUT="$TMPD/cx-${JOB_ID}.txt"
DONE="$TMPD/cx-${JOB_ID}.done"
STATUS="$TMPD/cx-${JOB_ID}.status"
SESSION_FILE="$TMPD/cx-${JOB_ID}.session"
STUCK="$TMPD/cx-${JOB_ID}.stuck"
ERR_RX='Access is denied|ERROR codex_core::tools::router|signal pipe|No installed Python|unknown MCP server'

STRIPPED="$(mktemp "${TMPD%/}/cx-${JOB_ID}.strip.XXXXXX")"
MSG_FILE="$(mktemp "${TMPD%/}/cx-${JOB_ID}.msg.XXXXXX")"
TOK_FILE="$(mktemp "${TMPD%/}/cx-${JOB_ID}.tok.XXXXXX")"
ERR_FILE="$(mktemp "${TMPD%/}/cx-${JOB_ID}.err.XXXXXX")"
cleanup() {
  rm -f "$STRIPPED" "$MSG_FILE" "$TOK_FILE" "$ERR_FILE"
}
trap cleanup EXIT

file_size() {
  if [ -f "$1" ]; then
    wc -c < "$1" 2>/dev/null | tr -d '[:space:]'
  else
    echo 0
  fi
}

strip_ansi_to_file() {
  : > "$STRIPPED"
  if [ -f "$OUT" ]; then
    sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' "$OUT" > "$STRIPPED"
  fi
}

load_session() {
  if [ -f "$SESSION_FILE" ]; then
    head -n 1 "$SESSION_FILE" | tr -d '\r\n'
    return
  fi
  if [ -f "$STATUS" ]; then
    awk -F= '/^session=/{print $2; exit}' "$STATUS" | tr -d '\r\n'
    return
  fi
  printf '%s' '-'
}

collect_status_errors() {
  : > "$ERR_FILE"
  if [ -f "$STATUS" ]; then
    awk '!/^(exit|job|session)=/ && NF{print}' "$STATUS" > "$ERR_FILE"
  fi
}

extract_final_message() {
  : > "$MSG_FILE"
  : > "$TOK_FILE"
  awk -v msgf="$MSG_FILE" -v tokf="$TOK_FILE" '
    { lines[++n] = $0 }
    END {
      start = 0
      tok = 0
      for (i = 1; i <= n; i++) {
        if (lines[i] == "codex") start = i
      }
      if (start == 0) exit
      for (i = start + 1; i <= n; i++) {
        if (lines[i] == "tokens used") {
          tok = i
          break
        }
        print lines[i] >> msgf
      }
      if (tok > 0 && tok < n) print lines[tok + 1] >> tokf
    }
  ' "$STRIPPED"
}

emit_block() {
  local exit_code="$1"
  local session_id
  session_id="$(load_session)"

  collect_status_errors

  printf '>>> CODEX_BEGIN exit=%s job=%s session=%s\n' "$exit_code" "$JOB_ID" "${session_id:--}"
  echo '[STATUS]'
  if [ -s "$ERR_FILE" ]; then
    cat "$ERR_FILE"
  else
    echo 'none'
  fi
  echo '--- FINAL MESSAGE ---'
  if [ -s "$MSG_FILE" ]; then
    cat "$MSG_FILE"
  fi
  echo '--- TOKENS ---'
  if [ -s "$TOK_FILE" ]; then
    cat "$TOK_FILE"
  else
    echo 'unknown'
  fi
  echo '>>> CODEX_END'
}

emit_stuck_block() {
  local reason="$1"
  local exit_code="$2"

  strip_ansi_to_file
  : > "$MSG_FILE"
  : > "$TOK_FILE"

  printf '[STUCK: %s]\n' "$reason" > "$MSG_FILE"
  if [ -s "$STRIPPED" ]; then
    tail -30 "$STRIPPED" >> "$MSG_FILE"
  else
    echo '[no output captured]' >> "$MSG_FILE"
  fi

  emit_block "$exit_code"
  exit "$exit_code"
}

ELAPSED=0
LAST_SIZE="$(file_size "$OUT")"
LAST_GROWTH=0

while :; do
  if [ -f "$DONE" ]; then
    break
  fi

  if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
    REASON="TIMEOUT after ${ELAPSED}s"
    printf '%s\n' "$REASON" > "$STUCK"
    emit_stuck_block "$REASON" 124
  fi

  CUR_SIZE="$(file_size "$OUT")"
  if [ "${CUR_SIZE:-0}" -gt "${LAST_SIZE:-0}" ]; then
    LAST_SIZE="$CUR_SIZE"
    LAST_GROWTH="$ELAPSED"
  fi

  IDLE=$((ELAPSED - LAST_GROWTH))
  if [ "$IDLE" -ge 90 ]; then
    HITS=0
    if [ -f "$OUT" ]; then
      HITS="$(sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' "$OUT" 2>/dev/null | tail -50 | grep -cE "$ERR_RX" || true)"
      HITS="$(printf '%s' "${HITS:-0}" | tr -d '[:space:]')"
    fi
    if [ "${HITS:-0}" -ge 3 ]; then
      REASON="STUCK_REPEATED_ERRORS hits=${HITS} idle=${IDLE}s"
      printf '%s\n' "$REASON" > "$STUCK"
      emit_stuck_block "$REASON" 125
    fi
  fi

  sleep 2
  ELAPSED=$((ELAPSED + 2))
done

strip_ansi_to_file
extract_final_message

EXIT_CODE=0
if [ -f "$DONE" ]; then
  EXIT_CODE="$(head -n 1 "$DONE" | tr -d '\r[:space:]')"
fi
case "$EXIT_CODE" in
  ''|*[!0-9-]*) EXIT_CODE=1 ;;
esac

emit_block "$EXIT_CODE"
exit "$EXIT_CODE"

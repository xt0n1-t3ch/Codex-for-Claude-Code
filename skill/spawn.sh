#!/usr/bin/env bash
# Cross-platform terminal spawner for /codex skill.
# Opens a new terminal window/tab and runs `bash run.sh CONFIG_FILE` inside it.
#
# Usage: spawn.sh JOB_ID CONFIG_FILE [--no-fallback]
#
# Detects OS, picks the best terminal emulator available, returns immediately.
# On total failure, exits non-zero so the caller's wait loop can surface the
# error via the spawn.log file.

set -u

JOB_ID="${1:?usage: spawn.sh JOB_ID CONFIG_FILE}"
CONFIG="${2:?usage: spawn.sh JOB_ID CONFIG_FILE}"
NO_FALLBACK="${3:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER="$SCRIPT_DIR/run.sh"
TITLE="codex-$JOB_ID"

[ -f "$RUNNER" ] || { echo "[spawn] runner missing: $RUNNER" >&2; exit 2; }
[ -f "$CONFIG" ] || { echo "[spawn] config missing: $CONFIG" >&2; exit 2; }

# Normalize OS detection across shells.
case "${OSTYPE:-$(uname -s 2>/dev/null || echo unknown)}" in
  msys*|cygwin*|MINGW*|win32*|Windows_NT) PLATFORM=windows ;;
  darwin*|Darwin*)                         PLATFORM=macos ;;
  linux*|Linux*)                            PLATFORM=linux ;;
  *)                                        PLATFORM=unknown ;;
esac

spawn_windows() {
  # Delegate to a .cmd helper that lives next to this script. Bypassing
  # Git Bash → cmd quote stripping (which would otherwise turn the start
  # title into a phantom command and trigger a "Windows cannot find …" popup).
  local CMDHELPER="$SCRIPT_DIR/spawn-windows.cmd"
  if [ ! -f "$CMDHELPER" ]; then
    echo "[spawn] missing helper: $CMDHELPER" >&2
    return 1
  fi
  # Convert MSYS paths to Windows form so the .cmd file sees normal paths.
  local RUNNER_W CONFIG_W
  RUNNER_W=$(cygpath -w "$RUNNER" 2>/dev/null || echo "$RUNNER")
  CONFIG_W=$(cygpath -w "$CONFIG" 2>/dev/null || echo "$CONFIG")
  cmd //c "$(cygpath -w "$CMDHELPER" 2>/dev/null || echo "$CMDHELPER")" \
    "$TITLE" "$RUNNER_W" "$CONFIG_W" >/dev/null 2>&1 &
  return 0
}

spawn_macos() {
  # Use AppleScript to open a new Terminal window.
  if command -v osascript >/dev/null 2>&1; then
    osascript >/dev/null 2>&1 <<APPLESCRIPT
tell application "Terminal"
  activate
  do script "bash '$RUNNER' '$CONFIG'"
  set custom title of front window to "$TITLE"
end tell
APPLESCRIPT
    return $?
  fi
  return 1
}

spawn_linux() {
  # Try common Linux terminals in order of preference.
  local term
  for term in gnome-terminal konsole xfce4-terminal kitty alacritty wezterm xterm; do
    command -v "$term" >/dev/null 2>&1 || continue
    case "$term" in
      gnome-terminal) "$term" --title="$TITLE" -- bash "$RUNNER" "$CONFIG" >/dev/null 2>&1 & ;;
      konsole)        "$term" --title "$TITLE" -e bash "$RUNNER" "$CONFIG" >/dev/null 2>&1 & ;;
      xfce4-terminal) "$term" --title="$TITLE" -e "bash $RUNNER $CONFIG" >/dev/null 2>&1 & ;;
      kitty)          "$term" --title "$TITLE" bash "$RUNNER" "$CONFIG" >/dev/null 2>&1 & ;;
      alacritty)      "$term" --title "$TITLE" -e bash "$RUNNER" "$CONFIG" >/dev/null 2>&1 & ;;
      wezterm)        "$term" start --always-new-process bash "$RUNNER" "$CONFIG" >/dev/null 2>&1 & ;;
      xterm)          "$term" -title "$TITLE" -e "bash $RUNNER $CONFIG" >/dev/null 2>&1 & ;;
    esac
    return 0
  done
  return 1
}

case "$PLATFORM" in
  windows) spawn_windows ;;
  macos)   spawn_macos ;;
  linux)   spawn_linux ;;
  *)       echo "[spawn] unsupported platform: ${OSTYPE:-unknown}" >&2; exit 1 ;;
esac
RC=$?

if [ "$RC" -ne 0 ]; then
  echo "[spawn] no supported terminal emulator found on $PLATFORM" >&2
  exit 1
fi

# Give the new process a moment to start so callers can detect window existence.
sleep 1
exit 0

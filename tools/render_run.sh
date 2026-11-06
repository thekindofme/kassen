#!/bin/bash
# Run Godot WITH a window (needed for screenshots/movies). Refuses while .screen_lock exists
# (another session is using the real screen/input). Usage: tools/render_run.sh <godot args...>
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ -f "$ROOT/.screen_lock" ]; then
  echo "SCREEN_LOCKED: $(cat "$ROOT/.screen_lock"). Use headless runs for now; retry rendered runs later." >&2
  exit 75
fi
exec godot --path "$ROOT" "$@"

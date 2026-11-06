#!/bin/bash
# Run Godot WITH a renderer (screenshots/movies) but in the BACKGROUND: launched via `open -g`
# so it never steals focus, and placed off-screen so it doesn't flash on the user's display.
# Refuses while .screen_lock exists. Output is printed after the run.
# Usage: tools/render_run.sh <godot args...>      (set KASSEN_VISIBLE=1 for a normal visible window)
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ -f "$ROOT/.screen_lock" ]; then
  echo "SCREEN_LOCKED: $(cat "$ROOT/.screen_lock"). Use headless runs for now; retry rendered runs later." >&2
  exit 75
fi
if [ "${KASSEN_VISIBLE:-0}" = "1" ]; then
  exec godot --path "$ROOT" "$@"
fi
LOG="$(mktemp -t kassen_render).log"
# Insert --position before the user args' `--` separator (engine args must precede it).
ENGINE=(); USER_ARGS=(); seen=0
for a in "$@"; do
  if [ $seen = 0 ] && [ "$a" = "--" ]; then seen=1; continue; fi
  if [ $seen = 0 ]; then ENGINE+=("$a"); else USER_ARGS+=("$a"); fi
done
open -g -n -W -a /Applications/Godot.app --stdout "$LOG" --stderr "$LOG" \
  --args --path "$ROOT" --position 7000,7000 "${ENGINE[@]}" -- "${USER_ARGS[@]}"
rc=$?
cat "$LOG"; rm -f "$LOG"
exit $rc

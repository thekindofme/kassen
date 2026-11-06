#!/bin/bash
# Run Godot WITH a renderer (screenshots/movies) without disturbing the user's screen:
#  - launched via `open -g` so it never steals focus,
#  - the OS window is a borderless 1x1 pixel from the very first frame, while the game renders
#    at full size internally (autoload scripts/dev/offscreen.gd, enabled by --offscreen=WxH).
# Refuses while .screen_lock exists. Output is printed after the run.
# Usage: tools/render_run.sh <godot args...> [-- <user args>]
#   --resolution WxH is honoured as the internal render size (default 1920x1080).
#   KASSEN_VISIBLE=1 runs a normal visible window instead (used for real screen recordings).
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ -f "$ROOT/.screen_lock" ]; then
  echo "SCREEN_LOCKED: $(cat "$ROOT/.screen_lock"). Use headless runs for now; retry rendered runs later." >&2
  exit 75
fi
if [ "${KASSEN_VISIBLE:-0}" = "1" ]; then
  exec godot --path "$ROOT" "$@"
fi
RES="1920x1080"; ENGINE=(); USER_ARGS=(); seen=0; take_res=0
for a in "$@"; do
  if [ $take_res = 1 ]; then RES="$a"; take_res=0; continue; fi
  if [ $seen = 0 ] && [ "$a" = "--" ]; then seen=1; continue; fi
  if [ $seen = 0 ]; then
    case "$a" in
      --resolution) take_res=1 ;;
      --position|--position=*|--windowed|-w|--maximized|-m|--fullscreen|-f) ;;
      *) ENGINE+=("$a") ;;
    esac
  else USER_ARGS+=("$a"); fi
done
LOG="$(mktemp -t kassen_render).log"
open -g -n -W -a /Applications/Godot.app --stdout "$LOG" --stderr "$LOG" \
  --args --path "$ROOT" --resolution 1x1 --position 0,0 "${ENGINE[@]}" -- --offscreen="$RES" "${USER_ARGS[@]}"
rc=$?
cat "$LOG"; rm -f "$LOG"
exit $rc

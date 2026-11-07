#!/bin/bash
# Real macOS SCREEN recording of a visible, live game session (not Godot's internal movie writer).
# Launches the game in a normal visible window running the full menu-to-menu E2E scenario,
# records the whole display with ffmpeg/AVFoundation (cursor included) until the game exits,
# then writes <out>.mp4 and <out>.log. Needs Screen Recording permission for the host app.
# Usage: tools/screen_record.sh [scenario=full_battle] [out=proof/screen_full_flow.mp4]
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCEN="${1:-full_battle}"; OUT="${2:-$ROOT/proof/screen_${SCEN}.mp4}"; LOG="${OUT%.mp4}.log"
RAW="$(mktemp -t kassen_screen).mkv"
SCREEN_IDX=$(ffmpeg -hide_banner -f avfoundation -list_devices true -i "" 2>&1 | sed -n 's/.*\[\([0-9]*\)\] Capture screen 0.*/\1/p' | head -1)
[ -z "$SCREEN_IDX" ] && { echo "no screen capture device" >&2; exit 2; }
# Probe permission first (a denied capture produces no frames).
if ! "$ROOT/tools/tmo" 15 ffmpeg -v error -f avfoundation -framerate 10 -i "${SCREEN_IDX}:none" -frames:v 1 -y "$RAW.png" 2>/dev/null || [ ! -s "$RAW.png" ]; then
  echo "SCREEN_RECORDING_PERMISSION_MISSING" >&2; rm -f "$RAW.png"; exit 3
fi
rm -f "$RAW.png"
ffmpeg -v error -f avfoundation -capture_cursor 1 -capture_mouse_clicks 1 -framerate 30 \
  -i "${SCREEN_IDX}:none" -c:v libx264 -preset ultrafast -crf 18 -y "$RAW" &
FF=$!
sleep 2
E2E_MENU=1 "$ROOT/tools/tmo" 1500 godot --path "$ROOT" --resolution 1920x1080 -- --e2e="$SCEN" --e2e_difficulty=normal > "$LOG" 2>&1
RC=$?
sleep 2; kill -INT $FF; wait $FF 2>/dev/null
ffmpeg -v error -y -i "$RAW" -vf "scale=1920:-2" -c:v libx264 -preset slow -crf 24 -pix_fmt yuv420p -movflags +faststart "$OUT"
rm -f "$RAW"
grep "E2E RESULT" "$LOG"; echo "screen recording: $OUT"
exit $RC

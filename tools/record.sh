#!/bin/bash
# Record an E2E scenario to an H.264 mp4 (and a .log next to it).
# Usage: tools/record.sh <scenario> <out.mp4> [extra user args...]
#   e.g. tools/record.sh full_battle proof/e2e_full_battle.mp4   (E2E_MENU=1 to start from the title)
# Runs through tools/render_run.sh (off-screen unless KASSEN_VISIBLE=1) with Godot's Movie Maker
# (--write-movie, --fixed-fps 30: frame-perfect and deterministic, slower than real time), then
# converts with ffmpeg (crf 22 or $CRF, yuv420p, faststart). Exit code: 0 if the log contains
# "E2E RESULT PASS", 1 if the scenario failed, 2 if the recording/encode failed.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ $# -lt 2 ]; then echo "usage: $0 <scenario> <out.mp4> [extra user args]" >&2; exit 64; fi
SCENARIO="$1"; OUT="$2"; shift 2
case "$OUT" in /*) ;; *) OUT="$ROOT/$OUT" ;; esac
mkdir -p "$(dirname "$OUT")"
LOG="${OUT%.*}.log"
TMPDIR_REC="$(mktemp -d -t kassen_rec)"
AVI="$TMPDIR_REC/run.avi"
BOOT="--battle"
[ "${E2E_MENU:-0}" = "1" ] && BOOT=""   # E2E_MENU=1: start at the title and click through the menus
"$ROOT/tools/render_run.sh" --write-movie "$AVI" --fixed-fps 30 --resolution 1920x1080 \
  -- $BOOT --e2e="$SCENARIO" "$@" 2>&1 | tee "$LOG"
# Keep the local temp path out of the (committed) log.
sed "s#${TMPDIR_REC}/#<tmp>/#g" "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
rc=1
grep -q "E2E RESULT PASS" "$LOG" && rc=0
if [ ! -s "$AVI" ]; then
  echo "record.sh: no movie was written" >&2; rm -rf "$TMPDIR_REC"; exit 2
fi
if ! ffmpeg -y -v error -i "$AVI" -c:v libx264 -preset slow -crf ${CRF:-22} -pix_fmt yuv420p \
     -c:a aac -b:a 160k -movflags +faststart "$OUT"; then
  echo "record.sh: ffmpeg encode failed" >&2; rm -rf "$TMPDIR_REC"; exit 2
fi
rm -rf "$TMPDIR_REC"
echo "record.sh: wrote $OUT ($(du -h "$OUT" | cut -f1)), log $LOG, e2e exit $rc"
exit $rc

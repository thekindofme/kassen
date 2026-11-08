#!/bin/bash
# Build the Godot web export and publish site/ + the game (at /play/) to the gh-pages branch.
# Usage: tools/deploy_site.sh            (needs Godot 4.7 web export templates and push access)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OUT="$(mktemp -d -t kassen_pages)"
echo "== exporting web build"
mkdir -p build/web
"$ROOT/tools/tmo" 900 godot --headless --path . --export-release "Web" build/web/index.html >/dev/null 2>&1
[ -s build/web/index.pck ] || { echo "web export failed" >&2; exit 1; }
echo "== assembling site in $OUT"
cp -R site/. "$OUT/"
mkdir -p "$OUT/play"
cp build/web/index.* "$OUT/play/"
touch "$OUT/.nojekyll"
echo "== publishing to gh-pages"
cd "$OUT"
git init -q -b gh-pages
git add -A
git commit -qm "Deploy site and web build from $(git -C "$ROOT" rev-parse --short HEAD)"
git push -f "$(git -C "$ROOT" remote get-url origin)" gh-pages
echo "deployed: $(du -sh "$OUT" | cut -f1)"
rm -rf "$OUT"

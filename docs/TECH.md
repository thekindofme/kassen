# KASSEN — Technical Architecture

Engine: **Godot 4.7.2** (`/opt/homebrew/bin/godot`), GDScript, 2D, Forward+/Mobile renderer.
Target: ~1,000 soldiers + projectiles + FX at 60 fps on an Apple M5, window 1920×1080 (stretch: canvas_items, expand).

## Directory layout
```
project.godot
assets/atlas/units.png + units.json     # unit sprite atlas (built by tools/build_atlas.py)
assets/terrain/*.png                    # seamless ground textures
assets/props/*.png + props.json         # cut-out props atlas/regions
assets/fx/*.png  assets/ui/*.png  assets/art/*.png  assets/audio/**
scenes/  main.tscn (boot → menu), battle.tscn, ui/*.tscn
scripts/core/   unit_types.gd, sim.gd (BattleSim), regiment.gd, projectiles.gd, morale.gd
scripts/render/ soldier_renderer.gd, shaders/*.gdshader
scripts/world/  terrain.gd, map_def.gd, maps/*.gd
scripts/input/  commander.gd (selection & orders), battle_camera.gd
scripts/ai/     ai_general.gd
scripts/ui/     hud.gd, unit_card.gd, menu.gd, briefing.gd, results.gd
scripts/fx/     fx.gd (particles, decals), weather.gd
scripts/audio/  audio_director.gd
scripts/test/   e2e_runner.gd + scenarios (autoplay via real InputEvents)
tools/          build_atlas.py, recolor, record.sh
```

## Simulation (scripts/core)
- `BattleSim` (node in battle scene; reachable via group "sim"): owns all soldiers as **struct-of-arrays**
  (`PackedVector2Array pos, vel; PackedFloat32Array hp, facing, anim_t, cooldown...; PackedInt32Array regiment, state, target`).
- Fixed tick **30 Hz** (`_physics_process` with physics_ticks_per_second=30 or an accumulator); render interpolates.
- **Spatial hash** (cell 32 px) rebuilt each tick for separation, melee target search and projectile hits.
- Soldier states: IDLE, MOVE, MELEE, SHOOT, DEAD, ROUT. The animation key (idle/walk/attack|shoot|fire/death) is derived from the state.
- `Regiment` (RefCounted): team, type, soldier indices, formation (files, ranks, spacing, centre, facing),
  orders queue (move/attack/halt), flags (running, fire_at_will, braced), morale, fatigue, state (normal/wavering/routing/shattered).
  Formation slots are computed from centre plus facing. Soldiers steer to their slot unless engaged.
- Melee: regiments in contact → soldiers pick the nearest enemy within 40 px and duel. Charge impulse when the
  attacker's speed is above 70% of run speed at contact.
- Ranged: archers spawn arced projectiles (ballistic in 2.5D: ground pos + height z); gunners do hitscan volleys
  with spread and spawn smoke. Projectiles are SoA inside `Projectiles`.
- Signals on the sim: `soldier_died(i)`, `regiment_routed(r)`, `regiment_rallied(r)`, `battle_ended(winner_team)`,
  `melee_contact(pos)`, `volley(pos, kind)`, `charge_impact(pos, strength)`. FX and audio subscribe to these only.
- Deterministic given a seed (RandomNumberGenerator owned by the sim) so E2E tests are reproducible.

## Rendering (scripts/render)
- `SoldierRenderer`: **one MultiMeshInstance2D for living soldiers** (all types and teams, single atlas) with
  `use_custom_data` (custom = atlas UV rect) and `use_colors` (tint/hit flash/selection rim). Instances are
  **sorted by y every frame** (build packed int keys `(y_int << 12) | idx`, `sort()`, then write) so
  overlapping melee depth-sorts correctly. A second multimesh draws soft shadow ellipses underneath.
  Corpses go to a third, append-only multimesh drawn under the living (persisting battlefield dead).
- Atlas contract (`assets/atlas/units.json`):
  ```json
  {"scale": 3.0, "units": {"yari": {"hino": {"idle": [{"x":0,"y":0,"w":96,"h":140,"ax":48,"ay":136}, ...8], "walk": [...], ...}, "mizuno": {...}}}}
  ```
  `scale` = atlas pixels per world pixel. `(ax, ay)` = foot anchor inside the frame. Sprites face RIGHT; flip for left.
  Anim keys: yari/samurai/cavalry/general: idle, walk, attack, death. yumi: idle, walk, shoot, death. teppo: idle, walk, fire, death.
- Props (trees, houses) are Sprite2D nodes in a y-sorted layer. Soldiers render in their own pass. Trees whose base is
  below a soldier are drawn in a canopy pass above soldiers with alpha fade when units are under them.
- Post-processing: a CanvasLayer full-screen shader for colour grade, vignette, cloud shadows and mist.

## World (scripts/world)
- Map = data script (`maps/kurogawa.gd`): size (e.g. 4800×3200 world px), terrain splat (generated from noise +
  painted features: river polyline, roads, forests, hills), prop placements, deployment zones, AI posture hints.
- `Terrain` draws the ground with a splat shader (up to 4–6 seamless textures blended by a splat texture, plus macro
  noise variation and a height-shading layer). It also exposes `speed_mult(pos)`, `is_forest(pos)`, `height(pos)`, `is_water(pos)`.

## Input and camera
- `BattleCamera`: Camera2D with smooth pan (WASD, edges, middle-drag) and cursor-anchored zoom (0.35–2.5), clamped to the map.
- `Commander`: selection (click, box, shift-add, double-click), orders (RMB move, RMB-drag formation line with ghost
  preview, RMB enemy = attack), hotkeys from the GDD. All actions go through `InputEvent`s, so the E2E runner can drive
  the game by injecting events with `Input.parse_input_event`.

## AI (scripts/ai)
`AIGeneral` controls team 1 through the same Regiment order API as the player (no cheating on vision).

## Testing and recording
- `scripts/test/e2e_runner.gd` (autoload, enabled by the `--e2e=<scenario>` user arg) walks the real UI: clicks
  menu buttons, selects regiments by clicking their cards and soldiers, drags formations, issues attacks, and asserts
  on game state (selection count, regiments moving, casualties increasing, victory screen visible). It exits with code 0/1.
- Recording: `godot --path . --write-movie out.avi --fixed-fps 60 -- --e2e=full_battle`, then ffmpeg to mp4.
  A real-window screen capture is done separately with macOS screencapture/ffmpeg avfoundation.
- Headless logic tests: `godot --headless --path . -s scripts/test/sim_tests.gd`.

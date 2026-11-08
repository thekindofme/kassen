# KASSEN 合戦 — Fields of the Warring States

A 2D real-time tactical battle game in **Godot 4.7**, inspired by the battle mode of *Shogun: Total War*.
KASSEN is an independent fan project, not affiliated with or endorsed by Creative Assembly or SEGA;
*Shogun: Total War* and *Total War* are trademarks of their respective owners (see [Trademarks](#license)).
It is Sengoku Japan in 1574. You command the crimson **Hino** clan against the indigo **Mizuno** warlord's AI:
about 830 individually simulated soldiers in 24 regiments, with formations, charges, braced spears, arrow volleys,
matchlock smoke, morale, routs and a general whose death can break an army.

## Play

```bash
godot --path .   # from the repository root
```

Title → **Battles** → choose a battle and difficulty → briefing → **deploy** your army in the gold zone → **Begin Battle**.

| Battle | Setting |
|---|---|
| The Ford at Kurogawa | Summer plain, a river with a main ford, a hidden northern ford, a village, and Hachiman shrine hill |
| Mist over Tenmoku Pass | Dawn mist; the enemy holds the ridge; a narrow throat and a woodcutters' flanking track |

### Controls

| Input | Action |
|---|---|
| LMB / LMB-drag / Shift | Select, box-select, add to the selection |
| RMB ground | Move, keeping formation |
| **RMB-drag** | Draw the formation line (frontage and facing) |
| RMB enemy | Attack; double-RMB to run |
| R / F / H / Backspace | Run toggle / fire at will / halt / withdraw |
| Ctrl+1–9, 1–9, G | Control groups |
| Space or P, + / − | Pause, game speed (×1–×3) |
| WASD / arrows / screen edge / middle-drag / wheel | Camera |
| Unit cards, minimap, order buttons | The same, through the HUD |

## How it was made: a studio of agents

| Role | Output |
|---|---|
| Creative director | `docs/GDD.md`, `docs/ART_BIBLE.md`, `docs/TECH.md`, art direction reviews of every deliverable |
| Technical artist | 57 Codex-generated images → `tools/build_atlas.py` (magenta keying, frame splitting, foot anchors, clan recolour) → a 4096² unit atlas: 6 unit types × 2 clans × 4 animations × 8 frames |
| Lead engine programmer | SoA battle sim at 30 Hz, a y-sorted MultiMesh renderer, TW-style controls, deployment, tests |
| AI programmer | `AIGeneral`: posture (attack, defend, skirmish), battle line, soften-then-assault, cavalry flanking and cycle charges, ford tactics, difficulty levels |
| UI/UX designer | Lacquer and washi theme, title, battle select, briefing, HUD (unit cards, minimap, power bar), results scroll |
| VFX artist | Gunsmoke banks, dust, blood and mud scarring, spent arrows, cloud shadows, low-lying mist, colour grade |
| Level designer | Two hand-composed maps with real props, fords, hills and flanking routes |
| Audio director | 104 sounds: CC0 sources plus synthesised taiko, horagai and shakuhachi music layers, and a pooled positional `AudioDirector` |
| QA automation | `E2E` autoload that plays the game through real input events, plus `tools/record.sh` |

Asset credits: `assets/audio/CREDITS.md`, `assets/fonts/CREDITS.md` (all CC0 or OFL). Art is original, generated with Codex image generation.

## Tests and proof

```bash
tools/tmo 300 godot --headless --path . -s scripts/test/sim_tests.gd     # 87 checks
tools/tmo 300 godot --headless --path . -s scripts/ui/tests/ui_tests.gd  # 76 checks
tools/tmo 200 godot --headless --path . -- --e2e=smoke_input --battle    # 23 checks: every hotkey
E2E_MENU=1 tools/record.sh full_battle proof/e2e_full_flow_kurogawa.mp4  # full menu-to-menu recorded run
```

Recordings in `proof/` (720p shareable copies are in `proof/share/`; logs are committed):

| Video | What it proves | Result |
|---|---|---|
| `e2e_full_flow_kurogawa.mp4` | Title → select → briefing → deploy → battle → **victory** → results → back to title, all through mouse and keyboard events | 29/29 PASS |
| `e2e_tenmoku.mp4` | The same flow on Tenmoku Pass: an uphill attack through mist with a flanking track | 18/18 PASS |
| `e2e_full_battle.mp4` | Battle-level run: selection, formation drags, archers, cavalry charge, hotkeys, victory | 22/22 PASS |
| `showcase.mp4` | Cinematic AI-vs-AI battle with a director camera at close zoom | PASS |

The recordings are frame-perfect captures of the running game (`--write-movie`, fixed 30 fps). A fake cursor
shows every injected click and drag.

## License

- Code: MIT, see [`LICENSE`](LICENSE).
- Art and synthesised audio: CC BY 4.0. Fonts: SIL OFL 1.1. Third-party audio: CC0 / public domain.
  Details and attribution in [`ASSETS-LICENSE.md`](ASSETS-LICENSE.md),
  [`assets/fonts/CREDITS.md`](assets/fonts/CREDITS.md) and [`assets/audio/CREDITS.md`](assets/audio/CREDITS.md).
- Trademarks: *Total War* and *Shogun: Total War* are trademarks of SEGA / Creative Assembly and are named only
  to describe this game's inspiration. KASSEN is not affiliated with, endorsed by or sponsored by
  Creative Assembly or SEGA.

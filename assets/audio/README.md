# KASSEN audio

Every file is Ogg Vorbis, 44.1 kHz stereo. Variants are numbered `_01`, `_02`, and so on.
`scripts/audio/audio_bank.gd` maps each sound name (the file name without `_NN`) to its variants.
The director picks a random variant each time and never repeats the previous one. Sources and
licences are in `CREDITS.md`, and the build scripts are in `art_src/audio_dl/synth/`.

Levels: one-shots are normalised to a fixed short-term RMS (the loudest 100 ms window, about
-13 to -17 dBFS depending on the sound), loops and music to integrated loudness (ffmpeg ebur128),
and everything has true peak ≤ -1 dBTP after encoding. Loops are seamless: they are built
circularly (events and reverb tails wrap around the loop end) or with equal-power crossfades.

## Music (`music/`, bus "Music")

| file | what | how the director uses it |
|---|---|---|
| `music_deploy.ogg` | 64 s loop, 120 BPM, D *miyako-bushi*. Odaiko heartbeat, distant nagado, shakuhachi phrases, koto motifs, low drone. About -17 LUFS. | Layer 1. Full volume in `deploy`, and in `battle` while intensity is low. |
| `music_battle.ogg` | Same tempo, length and bar grid. Two nagado (L/R), shime *ji-uchi*, kane *chan-chiki*, odaiko on 1 and 3, fue lines, kakegoe shouts on fills. About -16 LUFS. | Layer 2. Medium intensity. |
| `music_intense.ogg` | Same grid. Odaiko on every beat, a third nagado on 16ths, shime 16ths, busier fue. About -15.5 LUFS. | Layer 3. High intensity. |
| `music_menu.ogg` | About 73 s loop, 66 BPM. Koto ostinato, shakuhachi melody, drone, distant odaiko. About -16 LUFS. | `set_phase("menu")`. |
| `stinger_victory.ogg` | 9 s. Shime roll, unison hit, fue flourish in the *yo* scale, "don-don-DON". | `set_phase("victory")`. The battle layers fade out. |
| `stinger_defeat.ogg` | 10 s. Two low odaiko strokes, a falling shakuhachi line, drone, damped kane. | `set_phase("defeat")`. |
| `stinger_general_fallen.ogg` | 6 s. Three heavy strokes and an open kane. | `general_killed` signal. |

The three battle layers start together and play continuously, so they stay sample-aligned.
They are crossfaded with equal-power weights driven by the smoothed battle intensity (0 to 1):
deploy fades out over 0.02–0.22, battle takes over, and intense fades in over 0.45–0.8.

## SFX (`sfx/`, bus "SFX", positional unless noted)

| sound | variants | built from | triggered by |
|---|---|---|---|
| `sword_clash` | 8 | StarNinjas clashes with an impact body layer and a small room | melee clusters (throttled one-shots), `melee_contact` |
| `sword_hit` | 6 | blade plus body impact | melee one-shots, `soldier_died` (some) |
| `spear_thrust` | 5 | swish, shaft thunk and stab | melee one-shots when yari are engaged |
| `armour_impact` | 6 | body thud with lamellar/chain rattle | melee one-shots, `soldier_died` (some) |
| `death_grunt` | 10 | CC0 grunt reels | `soldier_died` (about 55%, rate-limited, max 3 at once) |
| `bow_release` | 5 | synthesised yumi twang plus swish | spare (single archers) |
| `bow_volley` | 3 | 22–34 twangs released together, with stragglers | `volley(pos, "arrow")` at the shooters |
| `arrow_whoosh` | 3 | 40 synthesised fly-bys over a CC0 whoosh bed | 0.15 s after an arrow volley, between shooter and target |
| `arrow_rain` | 3 | about 30 thunks and clinks landing | an arrow volley's target, after the flight time (distance / 420 px/s) |
| `arrow_impact` | 6 | single thunk | `projectile_hit(pos)` if the sim ever emits it |
| `matchlock_shot` | 4 | CC0 black-powder shots plus low boom, hill echo | small gun units (≤ 6 men): one per man, spread over 0.5 s |
| `matchlock_volley` | 3 | 16–26 shots, ragged, with a rolling echo | `volley(pos, "gun")` |
| `horse_gallop_loop` | 1 | loop (4 s), three layered offsets of a CC0 six-horse pass | looping voices that follow moving cavalry regiments |
| `horse_whinny` | 3 | PD neigh, pitched | `charge_impact` (45%), cavalry melee |
| `cavalry_charge_impact` | 3 | thud, snapping shafts, armour, whinny | `charge_impact(pos, strength)`, louder with strength |
| `warcry` | 5 | 14–22 layered CC0 yells plus crowd | `melee_contact`, `regiment_rallied`, battle start, charges |
| `rout_cry` | 3 | sparse, higher, scattered yells | `regiment_routed` |
| `kachidoki_01` | 1 | synthesised "Ei! Ei!" / "Oh!" ×3 with yell texture | victory (2.2 s after the stinger) |
| `horagai` | 1 | synthesised conch call, near | battle start (`set_phase("battle")`), non-positional |
| `horagai_answer` | 1 | the same call, distant and darker | 4.2 s later: the enemy answers |
| `march_loop` | 1 | loop (8 s), about 40 men stepping at 2 Hz with gear rattle | looping voices that follow moving infantry regiments (pitched up when running or routing) |
| `melee_loop` | 2 | loop (12 s), crowd bed with dense clashes, impacts, grunts and yells | the "melee bed" voices, one per melee cluster, louder with engaged men |

## UI (`ui/`, bus "UI", non-positional: `play_ui(name)`)

| `play_ui` name | file | sound |
|---|---|---|
| `click` | `ui_click_01..03` | hyoshigi clappers |
| `hover` | `ui_hover_01` | soft single wood tick (played 6 dB down) |
| `back`, `close`, `error` | `ui_back_01` | lower double tap |
| `select`, `open` | `ui_select_01` | clapper with a muted kane |
| `confirm`, `order`, `move` | `order_confirm_01..03` | two quick shime taps ("te-ke") |
| `attack` | `order_attack_01..02` | nagado "don" with a muted kane |

## Ambience (`amb/`, bus "Ambience")

| file | loop | use |
|---|---|---|
| `wind_plain_loop.ogg` | 40 s | always on in deploy and battle |
| `birds_loop.ogg` | 45 s | deploy and quiet battle, fades out as intensity rises above 0.1–0.5 |
| `river_loop.ogg` | 45 s | level follows how much water is around the camera (`terrain.is_water` sampled on a 5×5 grid), or a low constant if the terrain cannot be queried |

## How the director keeps hundreds of soldiers cheap

- **One-shots** use a fixed pool of `sfx_voices` (default 28) AudioStreamPlayer2D nodes. Each request
  passes, in order:
  1. the per-sound minimum gap and maximum concurrent instances (`RULES` in the director);
  2. the global start budget (`max_starts_per_frame`);
  3. an audibility cull (below -42 dB after distance and zoom);
  4. a voice stealer (priority, then current loudness, then age).
- **Melee** is aggregated. Every 0.2 s the director reads `regiment.engaged` and `mean_pos`, merges
  regiments within 320 px into clusters, and gives the largest clusters the few `melee_loop` voices,
  at a level that follows the engaged count. Clash, spear and armour one-shots are then sprinkled at
  about 1 per 10 engaged men per second, capped at 9/s.
- **Movement** works the same way: up to 3 `march_loop` voices and 3 `horse_gallop_loop` voices follow
  the moving regiments nearest the camera.
- **Panning** comes from the 2D players against the current Camera2D, with `panning_strength` 2.5.
  **Attenuation** is the director's own: about -10 dB per screen-width beyond the visible area,
  -9 dB when fully zoomed out (0.35), and a low-pass on the SFX bus that closes to 5 kHz when
  zoomed out.

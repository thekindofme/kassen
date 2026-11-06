# KASSEN Art QA log

Reviewer: Technical Artist / Art QA. Raw source: `art_src/raw/` (gen run 1, 57/57 ok, 2026-11-07).
Previews for review were downscaled JPG montages; keyed results are checked in
`units_contact.png`, `props_contact.jpg`, `fx_contact.jpg`, `terrain_tiled.jpg`.

Verdicts: **PASS** = used as is, **FIX** = used with a pipeline fix, **REGEN** = regenerated.

## Unit sheets (8 frames, facing right, magenta)

| Sheet | Verdict | Notes |
|---|---|---|
| yari idle | PASS | 8 consistent frames; upright spear. Figure drawn slimmer/taller than the other yari sheets. |
| yari walk | FIX | Reads as a jog/run with spear levelled (ok for "walk/run"). Character drawn chunkier (bigger hat) than idle; scaled by body area with an extra 0.85 tweak so the hat size roughly matches idle. |
| yari attack | PASS | Clear wind-up / lunge / recover. |
| yari death | PASS | Struck, kneels, ends lying flat; spear dropped as a detached component (merged into its frame). |
| yumi idle | PASS | |
| yumi walk | PASS | |
| yumi shoot | PASS | Nock, aim high, draw, release (frame 4), reach for next arrow. `fire_frame.yumi.shoot = 4`. |
| yumi death | PASS | Ends lying flat. |
| teppo idle | PASS | |
| teppo walk | PASS | Gun on the shoulder. |
| teppo fire | FIX | Generated muzzle flash (frame 3) and smoke puff (frame 4) removed in the pipeline (engine draws its own FX). `fire_frame.teppo.fire = 3`. |
| teppo death | PASS | Small blood burst on frame 1 is painted on the body (kept). Ends lying flat. |
| samurai idle | PASS | |
| samurai walk | PASS | |
| samurai attack | REGEN | v1 frame 4 had a translucent motion-blur ghost with a purple/magenta tint (would key to a see-through, purple-stained body). Regenerated with `--extra " Every frame fully opaque and solid: no motion blur, no ghosting, no translucent afterimages, no purple or magenta tint on the character."` → v2 clean, overhead raise / diagonal cut / follow-through / return. v1 kept in `art_src/rejected/`. |
| samurai death | PASS | Falls to knees, ends lying flat. |
| cavalry idle | PASS | |
| cavalry walk (gallop) | PASS | Plausible gallop phases, no broken legs at review size. |
| cavalry attack | PASS | |
| cavalry death | PASS | Horse collapses, rider thrown and lying separately in the last 2 frames (two bodies merged per frame by the splitter). |
| general idle | PASS | Raises war fan. |
| general walk (gallop) | PASS | |
| general attack | PASS | Draws katana and slashes. |
| general death | PASS | Horse collapses, general lying beside it at the end. |

## Environment / FX / art

(see sections below; filled in as processed)

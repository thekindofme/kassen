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
| general attack | REGEN | v1 white horse had a pink/lavender cast (white-pixel mean RGB 214,178,184, B>G) that read pink in both clans. Regenerated with `--extra " The white horse must be pure white/grey with no pink, lavender or magenta tint; match a cream-white horse coat."` → v2 cream white (210,184,161), consistent with idle/walk/death (208,187,174 etc). v1 in `art_src/rejected/`. Minor: the war fan has magenta-ish pleats (keyed fine, slightly pink). |
| general death | PASS | Horse collapses, general lying beside it at the end. |

## Environment / FX / art

### Pipeline fixes found in QA
- **Per-sheet scale.** Each generated sheet has its own drawing scale (yari walk figure ~280 px vs idle ~430 px).
  Idle is normalised by figure height (feet → hat/helmet top, thin weapons eroded away); other sheets by eroded
  body *area* relative to idle (pose-invariant). yari walk gets an extra 0.85 (chunkier drawing).
- **Mizuno recolour** (`tools/recolor.py`): hue window around red, saturation > ~0.5, skin guard, and a G/R ratio
  guard (lacquer crimson g/r≈0.2; bay horse, leather and skin ≥0.45) so horse coats/skin/wood/gold stay put.
  Faces checked in the contact sheet: no blue faces.
- **Despill** tolerance tightened (min(R,B) ≤ G+0.01) so light pixels with a magenta cast go neutral.
- teppo fire: flash/smoke stripped from frames 3–4 by colour (bright, desaturated or yellow-orange) in front of the
  body / above the hat, plus removal of orphaned fragments.

### Terrain (`assets/terrain/*.png`, 1024², graded)
| Texture | Verdict | Notes |
|---|---|---|
| grass | FIX | Raw was neon green. Graded to moss #5F7139 family, saturation ×0.65, luma 0.37. |
| meadow | FIX | Graded toward dry grass, luma matched to 0.37. |
| dirt | FIX | Raw too orange. Graded to ochre earth #7A5A3A family. |
| mud | PASS/FIX | Graded, luma 0.35. |
| forestfloor | PASS/FIX | Graded, luma 0.34 (slightly darker for forest readability). |
| riverbed | FIX | Seam score 1.89 → offset-and-blend fixed (1.16). Slate water #3E5A63, luma 0.33. |
| sand | FIX | Seam 1.69 → fixed (1.07). |
| paddy | FIX | Seam 2.45 → 1.83 after offset-blend (regular rice-row grid makes a residual pattern break at the wrap; acceptable at game zoom, candidate for regeneration). |
All textures share a luma std of ~0.075 so splat blends don't pop. Review: `terrain_tiled.jpg` (2×2 tiled).

### Props (`assets/props/<sheet>_<n>.png`, props.json, stored at 2× world)
All 9 sheets PASS: pines 4, maples 4, bamboo 3, rocks 6, houses 3, shrine 4 (shrine, torii, 2 lanterns),
fences 4 (rail fence, bamboo palisade, haystack, cart), camp 4 (maku enclosure, weapon rack + taiko drum were split,
nobori ×2), bushes 8. Tallest-item world heights: pines 160, maples 150, bamboo 150, houses 170, shrine 150,
camp 140, rocks 64, fences 58, bushes 34. Note: camp sheet gives 5 objects in the source; check `props_contact.jpg`
(rack and drum may be one cut-out). Bamboo clumps have faint pink tips on leaf edges at 100% zoom.

### FX (`assets/fx/`, fx.json)
fx_sheet: blood ×4 and muzzle flash ×2 PASS (linear un-mix key). Smoke ×4 keyed cleanly (neutral grey) and are
kept as optional textures. Dust ×3 REJECTED: brown semi-transparent over magenta cannot be un-mixed and keys pink;
the engine should make dust procedurally.

### Art / portraits / UI
- art_title, art_kurogawa, art_tenmoku, art_victory, art_defeat: PASS → `assets/art/<name>.jpg` 1920×1080.
  Minor lore inconsistency: victory/defeat banners show a flower (mokkō) crest instead of the three-tomoe.
- portraits ×6: PASS, raw is 1536×1024 so a centred full-height square is cropped → `portrait_<u>_{512,256}.png`.
  Helmets/hat tops touch the top edge in the source composition (cavalry, general, samurai crests cropped).
- ui_mon_hino / ui_mon_mizuno: PASS, keyed → `assets/ui/mon_<clan>_{512,128}.png` (mizuno feather stripes are
  negative-space cut-outs, intended).
- ui_lacquer / ui_washi: PASS → `assets/ui/{lacquer,washi}.png` 1024².


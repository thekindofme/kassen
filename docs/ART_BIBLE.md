# KASSEN — Art Bible

## Look
"Lacquer and ink diorama." The ground is lush, painterly and slightly desaturated (moss greens,
ochre earth, slate water). Characters are rich and saturated: lacquer red, indigo, gold, black iron.
The UI is black lacquer panels with gold-leaf trim, washi-paper parchments, vermilion seal stamps,
and brush-stroke typography.

Palette anchors:
- Hino (player): lacquer crimson `#A3201E`, gold `#D4A23C`, black `#1A1714`
- Mizuno (AI): indigo `#23356B`, silver-white `#D9D4C5`, black
- Ground: moss `#5F7139`, dry grass `#9C9455`, earth `#7A5A3A`, water `#3E5A63`
- UI: lacquer `#14100D`, gold `#C9A04A`, washi `#E8DDC4`, vermilion `#C23B22`

## Camera and projection
The ground is seen top-down. Characters, trees and buildings use a **3/4 overhead view** (camera
~55° down), so tall objects read as standing. Everything is lit from the top-left, and shadows are
drawn by the engine (soft ellipses and projected silhouettes), never baked into sprites.

## Sprite rules (for AI generation)
- One animation per sheet: **8 frames in one horizontal row**, character **facing right**, pure flat
  `#FF00FF` background, no ground shadow, no text, no grid, same scale every frame, full body.
- Crimson clan only. The indigo clan is produced by a hue remap in the pipeline (`tools/recolor`).
- The pipeline keys out magenta, splits frames by connected components, anchors the feet at
  bottom-centre, normalises height per unit type, and packs a single atlas (`assets/atlas/units.png`
  + `units.json`).
- Infantry in-game height ≈ 44 px at zoom 1.0 (atlas frames stored at 2×, for crisp zoom-in).

## Shared prompt style token
> painterly AAA 2D strategy game sprite art, Sengoku-era Japan 1570s, 3/4 overhead view
> (camera about 55 degrees above), richly detailed lacquered armour, soft top-left light, crisp clean
> silhouette, no ground shadow, no text, no grid lines, pure flat solid #FF00FF magenta background

## Environment
Seamless top-down painted ground textures (grass, meadow, dirt road, mud, riverbed, forest floor,
rice paddy). Props: pines, maples, bamboo, rocks, thatched farmhouses, shrine, torii, fences, and
haystacks, as 3/4-view cut-outs on magenta.

## Effects (engine side)
Procedural plus small generated textures: smoke puff, dust puff, blood splat, spark, arrow,
flag cloth, mist noise, and cloud shadow noise.

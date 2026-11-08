# KASSEN asset licences

The **code** in this repository (GDScript, shaders, scenes, Python and shell tools) is under the
MIT License; see [`LICENSE`](LICENSE). The **assets** are licensed as follows.

| What | Where | Licence |
|---|---|---|
| Original and generated art: unit sprite sheets and atlas, portraits, key art, terrain, props, FX, UI textures and crests, plus the raw and review images in `art_src/` | `assets/art`, `assets/atlas`, `assets/terrain`, `assets/props`, `assets/fx`, `assets/ui`, `art_src/` | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) |
| Audio synthesised for KASSEN (music, stingers, taiko, horagai, UI sounds and the synthesised layers of the SFX) | `assets/audio` | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) |
| Third-party fonts (Shippori Mincho B1, Yuji Boku, Alegreya Sans) | `assets/fonts` | SIL Open Font License 1.1; see [`assets/fonts/CREDITS.md`](assets/fonts/CREDITS.md) and the `OFL-*.txt` files |
| Third-party audio recordings used as source material | `assets/audio` | CC0 1.0 or public domain; see [`assets/audio/CREDITS.md`](assets/audio/CREDITS.md) |
| Design documents and README text | `docs/`, `*.md` | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) |

CC BY 4.0 attribution: "KASSEN by Yasith Fernando", with a link to this repository and to the licence,
and a note of any changes you made.

## Notes

- **Generated art.** Most images were generated with OpenAI image generation (prompts in
  `art_src/manifest.py`) and then keyed, cut, recoloured and assembled by the scripts in `tools/`.
  OpenAI's terms assign the user its rights in the output. Some jurisdictions do not grant copyright
  in purely machine-generated images, so the CC BY 4.0 grant applies to the extent that copyright
  subsists in these assets. The raw PNGs in `art_src/raw/` keep their C2PA provenance metadata.
- **Mixed audio.** Several sounds layer CC0 or public-domain recordings with synthesised material. The
  CC0 parts stay CC0; CC BY 4.0 covers only the original contribution. Attribution for the CC0 sources
  is not required, but they are listed in `assets/audio/CREDITS.md`.
- **Fonts.** The Shippori Mincho B1 and Yuji Boku files are subsets of the originals. They remain under
  the OFL and may not be sold on their own.
- **Clan crests and historical motifs** (mitsudomoe, takanoha and other kamon, torii, armour styles)
  are traditional Japanese designs and are not claimed as trademarks by this project.

## Trademarks

KASSEN is an independent fan project. It is not affiliated with, endorsed by or sponsored by
Creative Assembly or SEGA. *Total War* and *Shogun: Total War* are trademarks or registered
trademarks of their respective owners (SEGA / Creative Assembly) and are mentioned only to describe
what inspired this game. No names, art, UI, music or code from those games are used here.

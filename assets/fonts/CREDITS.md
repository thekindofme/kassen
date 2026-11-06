# KASSEN — Font credits

All fonts are licensed under the **SIL Open Font License 1.1** (licence texts alongside, `OFL-*.txt`).
Downloaded from the Google Fonts repository (`github.com/google/fonts`, `ofl/` tree) on 2026-11-07.

| File | Family | Role in KASSEN | Copyright | Licence |
|---|---|---|---|---|
| `ShipporiMinchoB1-ExtraBold.ttf` | Shippori Mincho B1 ExtraBold | Logo, screen titles, big numbers | © 2021 The Shippori Mincho Project Authors (github.com/fontdasu/ShipporiMincho) | `OFL-ShipporiMinchoB1.txt` |
| `ShipporiMinchoB1-Bold.ttf` | Shippori Mincho B1 Bold | Headings, button captions, card titles | same | `OFL-ShipporiMinchoB1.txt` |
| `YujiBoku-Regular.ttf` | Yuji Boku | Brush kanji (合戦, seal stamps, banners) | © 2021 The Yuji Project Authors (github.com/Kinutafontfactory/Yuji) | `OFL-YujiBoku.txt` |
| `AlegreyaSans-Regular.ttf` / `-Medium.ttf` / `-Bold.ttf` | Alegreya Sans | Body text, HUD numbers, tooltips | © 2013 The Alegreya Sans Project Authors (github.com/huertatipografica/Alegreya-Sans) | `OFL-AlegreyaSans.txt` |

## Modifications (OFL §2/§3 note)

`ShipporiMinchoB1-*.ttf` and `YujiBoku-Regular.ttf` are **subsets** of the original fonts made with
fontTools (`pyftsubset`) to keep the build small: Basic Latin, Latin-1, general punctuation, CJK
punctuation and the ~150 kanji used by the game UI. The family names are unchanged as permitted for
subsetting by the OFL FAQ (no Reserved Font Names are declared by these projects). To add more kanji,
re-run the subset from the original fonts with the extra characters in `--text=`.

Alegreya Sans files are unmodified.

# KASSEN audio credits and licences

Every file in `assets/audio/` is either **synthesised for KASSEN** (no third-party material) or
**built from public-domain / CC0 recordings**. No file needs attribution, but the sources are listed
here so the provenance is auditable and every raw file can be fetched again. Licences were checked
on each source page on 2026-11-07. Raw downloads are kept out of git under `art_src/audio_dl/`, and
the processing and synthesis code lives in `art_src/audio_dl/synth/` (`build_sfx.py`, `music.py`).

## Third-party sources (all CC0 1.0 or public domain)

| # | Source (page) | Author | Licence | Files used | Used in |
|---|---|---|---|---|---|
| 1 | https://opengameart.org/content/20-sword-sound-effects-attacks-and-clashes | StarNinjas | CC0 | `sword_clash.N.ogg`, `sword.N.ogg` | sword_clash_*, sword_hit_*, melee_loop_* |
| 2 | https://opengameart.org/content/10-impactshield-blocks | StarNinjas | CC0 | `impact.N.ogg` | sword_clash_* (body), sword_hit_*, spear_thrust_*, armour_impact_*, cavalry_charge_impact_*, melee_loop_* |
| 3 | https://opengameart.org/content/rpg-sound-pack | artisticdude | CC0 | `inventory/armor-light.wav`, `chainmail1/2.wav`, `metal-small1.wav` | armour_impact_*, arrow_rain_*, cavalry_charge_impact_*, march_loop |
| 4 | https://opengameart.org/content/50-rpg-sound-effects | Kenney | CC0 | `knifeSlice*.ogg`, `chop.ogg`, `metalClick.ogg`, `footstep0N.ogg`, `cloth*.ogg`, `beltHandle*.ogg` | spear_thrust_*, arrow_rain_*, march_loop, melee_loop_* |
| 5 | https://opengameart.org/content/80-cc0-rpg-sfx | rubberduck | CC0 | `blade_0N.ogg`, `metal_02.ogg`, `chain_0N.ogg` | arrow_rain_*, cavalry_charge_impact_*, march_loop, melee_loop_* |
| 6 | https://opengameart.org/content/100-cc0-metal-and-wood-sfx | rubberduck | CC0 | `wood_misc_0N`, `wood_hit_0N`, `wood_breaking_0N`, `metal_hit_03` | spear_thrust_*, armour_impact_*, arrow_impact_*, cavalry_charge_impact_*, melee_loop_* |
| 7 | https://opengameart.org/content/75-cc0-breaking-falling-hit-sfx | rubberduck | CC0 | `bfh1_wood_hit_0N`, `bfh1_hit_06`, `bfh1_metal_hit_0N`, `bfh1_wood_breaking_0N` | spear_thrust_*, armour_impact_*, arrow_impact_*, cavalry_charge_impact_* |
| 8 | https://opengameart.org/content/swishes-sound-pack | artisticdude | CC0 | `swish-N.wav` | spear_thrust_*, bow_release_* |
| 9 | https://opengameart.org/content/air-whoosh | pyranostudios | CC0 | `whoosh2_0.wav` | arrow_whoosh_* (bed) |
| 10 | https://opengameart.org/content/gunshots | kurt | CC0 | `Black Powder.wav`, `Unkown.wav` | matchlock_shot_*, matchlock_volley_* |
| 11 | https://opengameart.org/content/crowd-shoutingspeaking-ambience | StarNinjas | CC0 | `crowd_shouting.ogg` | warcry_*, melee_loop_* |
| 12 | https://opengameart.org/content/male-gruntyelling-sounds | HaelDB | CC0 (dual-licensed CC0 / OGA-BY 3.0; used under CC0) | `yelling sounds/*.wav` | warcry_*, rout_cry_*, death_grunt_*, kachidoki_01 (texture), melee_loop_*, kakegoe shouts in music_battle / music_intense |
| 13 | https://opengameart.org/content/grunts-male-death-and-pain | thebardofblasphemy | CC0 | `death pain grunts.wav` | death_grunt_*, melee_loop_* |
| 14 | https://opengameart.org/content/fantozzis-footsteps-grasssand-stone | qubodup | CC0 | `Fantozzi-Sand*.ogg` | march_loop |
| 15 | https://opengameart.org/content/mild-wind-background-noise | Bashar3A | CC0 | `wind background noise 2.wav` | wind_plain_loop (high-passed under-layer only) |
| 16 | https://opengameart.org/content/park-ambiences | Thimras | CC0 | `park_ambience_birds.wav`, `park_ambience_river.wav` | birds_loop, river_loop |
| 17 | https://commons.wikimedia.org/wiki/File:Six_Horses_Galloping_By.ogg | freesound_community / Bruno Auzet (via Pixabay) | CC0 | whole file | horse_gallop_loop |
| 18 | https://commons.wikimedia.org/wiki/File:Wiehern.ogg | Hü. | Public domain | whole file | horse_whinny_*, cavalry_charge_impact_* |
| 19 | https://commons.wikimedia.org/wiki/File:Shakuhachi-flute-440Hz.ogg | (deleted user) | CC0 | single sustained A4 note | the shakuhachi voice in music_deploy, music_menu, stinger_defeat (re-pitched and re-shaped per note) |

Direct download URLs follow the pattern `https://opengameart.org/sites/default/files/<file>` for
OpenGameArt and `https://upload.wikimedia.org/wikipedia/commons/...` for Commons. The exact URLs
are listed in `art_src/audio_dl/README.md`.

## Synthesised in-house (no third-party material)

All taiko (odaiko, nagado, shime), kane, hyoshigi, koto, shinobue (fue), the drone, the horagai and
the synthetic "Ei! Ei! Oh!" voices are synthesised with numpy (`art_src/audio_dl/synth/instruments.py`),
along with the bow twang and the arrow fly-by noise. The music and stingers are composed in
`synth/music.py`.

- music_menu, music_deploy, music_battle, music_intense, stinger_victory, stinger_defeat, stinger_general_fallen
- horagai_01, horagai_02, kachidoki_01 (synthetic voices plus CC0 yell texture, #12)
- bow_release_* (synth twang plus CC0 swish, #8), bow_volley_*, arrow_whoosh_* (synth plus #9)
- ui_click_*, ui_hover_01, ui_back_01, ui_select_01, order_confirm_*, order_attack_*
- wind_plain_loop (synthesised gusting wind over a high-passed bed from #15)

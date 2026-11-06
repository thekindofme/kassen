# art_src/audio_dl: raw audio sources and the audio build

Raw downloads live in one folder per source (`oga_*`, `commons/`). They are git-ignored, so
re-fetch them with the commands below. All of them are CC0 or public domain (see
`assets/audio/CREDITS.md`). Archives were unpacked into `x/` subfolders with `tar -xf`. Nothing
downloaded is ever executed.

## Re-fetch

```sh
cd art_src/audio_dl
B=https://opengameart.org/sites/default/files
dl(){ mkdir -p "$1" && (cd "$1" && curl -sSfL -O "$B/$2"); }
dl oga_starninjas_sword sword_-_starninjas_1.zip;   dl oga_starninjas_sword sword_clash_-_starninjas_0.zip
dl oga_starninjas_impact impact_-_starninjas.zip;  dl oga_rpg_sound_pack rpg_sound_pack.zip
dl oga_kenney_rpg RPGsounds_Kenney.zip;            dl oga_80cc0_rpg 80-CC0-RPG-SFX_0.zip
dl oga_100cc0_metalwood 100-CC0-wood-metal-SFX.zip; dl oga_75cc0_breaking sfx_breaking_and_falling.zip
dl oga_gunshots "Black%20Powder.wav";             dl oga_gunshots "Unkown.wav"
dl oga_crowd_shouting crowd_shouting.ogg;          dl oga_swishes swishes.zip
dl oga_air_whoosh whoosh2_0.wav;                   dl oga_mild_wind "wind%20background%20noise%202.wav"
dl oga_fantozzi_footsteps Fantozzi-footsteps.7z;   dl oga_grunts_death "death%20pain%20grunts.wav"
dl oga_male_yelling "yelling%20sounds.zip"
dl oga_park_ambiences park_ambience_river.wav;     dl oga_park_ambiences park_ambience_birds.wav
for z in */*.zip */*.7z; do mkdir -p "$(dirname "$z")/x"; tar -xf "$z" -C "$(dirname "$z")/x"; done
mkdir -p commons && cd commons
curl -sSfL -O https://upload.wikimedia.org/wikipedia/commons/d/db/Wiehern.ogg
curl -sSfL -O https://upload.wikimedia.org/wikipedia/commons/9/96/Six_Horses_Galloping_By.ogg
curl -sSfL -O https://upload.wikimedia.org/wikipedia/commons/2/22/Shakuhachi-flute-440Hz.ogg
```

## Build

Requirements: Python 3 with numpy, ffmpeg/ffprobe, and Homebrew `libsndfile`. The local ffmpeg has
no libvorbis, so `synth/oggwrite.py` writes Ogg Vorbis (q 0.6) through libsndfile via ctypes.

```sh
python3 -E art_src/audio_dl/synth/build_sfx.py      # groups: horagai weapons bows guns horses voices loops ui amb
python3 -E art_src/audio_dl/synth/music.py          # deploy battle intense menu stingers
python3 -E art_src/audio_dl/synth/gen_bank.py       # regenerates scripts/audio/audio_bank.gd
python3 -E art_src/audio_dl/synth/analyze.py --env assets/audio/*/*.ogg   # level and spectrum report
```

- `dsp.py`: FFT filters, K-weighted loudness, a look-ahead limiter, synthetic stereo IRs with
  frequency-dependent decay, convolution and circular (loop-safe) reverb, loop crossfades, STFT
  source-filter (`formant_filter`), and `save_checked` (encode, measure with ffmpeg ebur128, then
  correct loudness and true peak).
- `instruments.py`: taiko family, kane, hyoshigi, koto, breath flutes, horagai, shouted voices.
- `build_sfx.py`: processing and layering of the CC0 sources plus synthesised SFX, UI and ambience.
- `music.py`: battle layers, menu theme and stingers.

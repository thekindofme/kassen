# KASSEN 合戦 — Game Design Document

*Studio pillar: "Total War's battle layer, repainted as a living 2D ink-and-lacquer diorama."*

## 1. Vision

A real-time tactical battle game set in Sengoku-era Japan (1570s), focused only on the
battlefield. The player commands an army of regiments (hundreds of individually
simulated soldiers) against an AI warlord on a hand-painted 2D battle map. It is inspired
by the battle mode of *Shogun: Total War* / *Shogun 2*: deploy, manoeuvre, shoot, charge,
break the enemy's morale, and protect your general. The game is all original: no names,
art, UI or music are copied from those games.

Pillars:
1. **Mass and weight.** Regiments are blocks of men. Soldiers move, collide, duel and fall individually.
   A cavalry charge into the flank should feel like an impact.
2. **Readable tactics.** Rock-paper-scissors (spear > cavalry > archers/guns > spear; samurai elite),
   morale, flanking, terrain and fatigue. The player wins by manoeuvre, not by spending more units.
3. **Painted spectacle.** Painterly sprites, swaying sashimono banners, arrow volleys with shadows,
   matchlock smoke, dust, blood, drifting mist, cloud shadows and taiko drums.

## 2. Setting and story

**Year 1574, the Kurogawa Plain, Mino province.** The crimson **Hino clan** (player, mon: three tomoe)
has marched to hold the ford of the Black River against the indigo **Mizuno clan**
(AI, mon: crossed hawk feathers). Lord Mizuno Tadakatsu has broken the old alliance and
seeks to cut the Hino off from the capital road.

The player is **Hino Masatora**, a young heir commanding his father's veterans for the first time.

Battles (scenarios):
1. **The Ford at Kurogawa** (day, open plain, river with ford, small village, forests). Field battle.
2. **Mist over Tenmoku Pass** (dawn mist, hilly pass, pine forests, shrine). Enemy holds the high ground.

Each battle opens with a short ink-painted briefing card (title art plus three lines of narrative)
and closes with a result scroll (victory/defeat, casualties, heroic regiment).

## 3. Game flow

Title screen → Battle select (2 scenarios + difficulty) → Briefing → **Deployment phase**
(drag regiments within your deployment zone, set formation) → **Battle** (real time, pausable,
speed ×0.5/×1/×2/×3) → Result scroll → Back to menu / Replay.

## 4. Units (regiments)

| Unit | Men | Role | Strengths / weaknesses |
|---|---|---|---|
| Yari Ashigaru | 60 | Cheap line infantry | Bonus vs cavalry (brace), low morale |
| Yumi Ashigaru | 40 | Archers | Long range arcs (fire over friends), weak melee |
| Teppo Ashigaru | 40 | Matchlock gunners | Devastating volley, short range, slow reload, scare effect, smoke |
| Katana Samurai | 32 | Elite shock infantry | High attack/defence/morale, no anti-cav bonus |
| Yari Cavalry | 20 | Mounted shock | Big charge bonus, fast; dies to braced spears |
| General's Hatamoto | 12 | Mounted bodyguard | Morale aura, inspires. Death = army-wide morale shock |

Standard army: 1 General, 3 Yari Ashigaru, 2 Yumi, 1 Teppo, 2 Samurai, 2 Cavalry ≈ 456 men per side
(about 900 soldiers on the field).

### Stats (per soldier)
`hp, melee_attack, melee_defence, charge_bonus, armour, speed_walk, speed_run, range, reload, accuracy, morale_base, mass`.

### Combat model
- Each soldier has a **slot** in their regiment formation (ranks × files) and steers to it with
  separation from neighbours (boids-lite). In melee, soldiers break formation to pick a nearby enemy
  and **duel**: attack timers, hit chance = f(attack vs defence), damage vs armour.
- **Charge:** soldiers running into contact above a speed threshold apply charge bonus and a
  knock-back impulse (victims stagger). Braced spears (yari standing still facing the charge)
  negate the charge and deal bonus damage to horses.
- **Ranged:** archers fire arced projectiles at a point in the target regiment with scatter.
  Projectiles fly as real objects with shadows. Gunners fire direct volleys with hitscan plus smoke
  and muzzle flash. Friendly fire is possible for guns, not for arcing arrows.
- **Morale** per regiment, 0–100: drops with casualties, being flanked or rear-charged, the general
  dying, nearby friendly routs, and gunfire. Rises from the general's aura, winning, and high ground.
  States: Eager → Steady → Wavering → **Routing** (flee to the map edge, may rally) → Shattered.
- **Fatigue:** running and fighting tire men. Tired units lose attack and speed.
- **Terrain:** forest (slow, cover vs arrows), river (slow, only fordable at the ford), hills (height
  gives ranged range and melee bonus), roads (fast).
- **Victory:** all enemy regiments routed/shattered/dead, or the enemy general killed and the army broken.

## 5. Controls (TW-style)

- LMB: select a regiment / LMB-drag: box select / Shift: add / double-click a card: select and focus.
- RMB on ground: move (keeps formation and facing toward the move direction).
- **RMB-drag:** draws the formation line (sets frontage width and facing), with a ghost preview.
- RMB on an enemy: attack (melee charge or ranged target). Double-RMB: run.
- Keys: `R` run toggle, `F` fire-at-will toggle, `H` halt, `G` group, `Ctrl+1..9` assign group, `1..9` recall,
  `Space` pause, `+/-` game speed, `Tab` toggle unit labels, `Backspace` withdraw.
- Camera: WASD/arrows/edge pan, mouse wheel zoom (cursor-anchored), middle-drag pan.
- Unit cards along the bottom: portrait, men count, morale bar, state icons (running, firing, routing).

## 6. AI (enemy warlord)

A tactical commander that runs on a 0.5 s think tick with three layers:
1. **Strategy:** picks a posture (Attack / Defend / Skirmish) from relative strength, ranged
   advantage, terrain (hold high ground) and difficulty.
2. **Group tactics:** forms a battle line (spears front, missiles behind or out front while
   skirmishing), cavalry on the wings looking for exposed flanks, missiles, or routing units.
   The general stays behind the line and joins only to finish routers.
3. **Unit micro:** archers hold range and fall back from melee, gunners hold fire until close,
   spears brace against cavalry, cavalry disengages after a charge and recharges (cycle charge),
   and units rally near the general.
Difficulty scales reaction time, morale bonus, and aggression/flank search radius.

## 7. Presentation

- Painterly oblique view: the ground is seen from above, and characters are 3/4 side-view sprites
  (a classic 2.5D look). Soldiers flip horizontally for left/right facing.
- Effects: dust trails, footprints and churned mud decals, blood spurts and decals, arrow trails,
  matchlock smoke clouds that drift with the wind, muzzle flash, impact sparks, corpses that persist,
  sashimono banners on unit leaders, regiment flags, drifting cloud shadows, mist layer, and a
  colour-grading shader with vignette.
- Audio: taiko battle drums that intensify with combat, ambient wind, birds, the river, sword clashes,
  arrow whoosh and volley, gunfire, horse charge, war cries, horagai conch at battle start, and
  victory/defeat stingers.

## 8. Scope and quality bar

Definition of done:
- Two playable scenarios from menu to result, with ~900 soldiers at 60 fps on an Apple M5.
- All six unit types have idle/walk/attack/death animation (cavalry and general mounted).
- The AI wins against a passive player and loses to a competent one.
- Automated end-to-end test: boots the game, plays a full battle through real input events,
  verifies victory, and records a video. A human-style screen recording is captured with the real window.

"""Asset manifest: name -> (prompt, kind). kind: 'sheet' (8-frame anim on magenta), 'prop' (cutouts on magenta),
'tex' (seamless texture), 'art' (illustration), 'icon' (on magenta)."""

STYLE = ("painterly AAA 2D strategy game sprite art, Sengoku-era Japan 1570s, 3/4 overhead view "
         "(camera about 55 degrees above the ground), richly detailed lacquered armour, soft top-left light, "
         "crisp clean silhouette, no ground shadow, no text, no grid lines, no frame borders, "
         "pure flat solid #FF00FF magenta background")

SHEET = ("A wide landscape sprite sheet: exactly 8 animation frames of the SAME single character arranged in ONE "
         "horizontal row with generous empty magenta space between frames, every frame the same scale and fully "
         "visible head to toe, character facing RIGHT. ")

CREST = "small golden three-comma tomoe crest"

UNITS = {
    "yari": f"a Japanese ashigaru foot soldier in crimson-red lacquered jingasa hat with {CREST}, crimson do chest armour, dark indigo-grey trousers, straw sandals, holding a very long yari spear",
    "yumi": f"a Japanese ashigaru archer in crimson-red lacquered jingasa hat with {CREST}, crimson do chest armour, dark trousers, a quiver of arrows on his back, holding a tall asymmetric yumi longbow",
    "teppo": f"a Japanese ashigaru matchlock gunner in crimson-red lacquered jingasa hat with {CREST}, crimson do chest armour, dark trousers, powder flask at the belt, holding a long tanegashima matchlock arquebus",
    "samurai": f"an elite Japanese samurai in full crimson-red lacquered o-yoroi armour with gold lacing, kabuto helmet with gold maedate crest, menpo face mask, wielding a katana, a small crimson sashimono banner on his back with {CREST}",
    "cavalry": f"a mounted Japanese samurai on a dark bay warhorse with crimson tack, rider in crimson lacquered armour and kabuto helmet, holding a long yari spear, small crimson sashimono banner on his back with {CREST}",
    "general": f"a mounted Japanese daimyo general on a white warhorse with gold and crimson caparison, ornate black-and-gold armour with crimson lacing, kabuto helmet with huge golden crescent maedate, crimson horo cloak, holding a gold war fan",
}

ANIMS = {
    "yari": {"idle": "idle breathing stance, spear held upright, slight shifting of weight",
             "walk": "walk cycle marching, spear angled forward over the shoulder",
             "attack": "spear thrust attack: wind back, lunge forward with the spear fully extended, recover",
             "death": "death: struck, staggering, collapsing and falling to lie flat on the ground in the last frames, spear dropped"},
    "yumi": {"idle": "idle stance holding the bow at rest",
             "walk": "walk cycle marching with bow in hand",
             "shoot": "archery: nock arrow, raise bow aiming upward at 30 degrees, full draw, release, follow-through, reach for next arrow",
             "death": "death: struck by an arrow, collapsing and falling to lie flat on the ground in the last frames"},
    "teppo": {"idle": "idle stance holding the matchlock at rest",
              "walk": "walk cycle marching, matchlock carried on the shoulder",
              "fire": "firing: shoulder the matchlock, aim level to the right, fire with a bright muzzle flash and puff of smoke in frames 4-5, recoil, lower the gun, begin reloading with ramrod",
              "death": "death: shot, collapsing and falling to lie flat on the ground in the last frames, gun dropped"},
    "samurai": {"idle": "idle ready stance, katana held in two hands at mid guard",
                "walk": "walk cycle advancing, katana held at the side",
                "attack": "katana attack: raise the katana overhead, powerful diagonal downward slash, follow-through, return to guard",
                "death": "death: struck down, falling to his knees then collapsing to lie flat on the ground in the last frames"},
    "cavalry": {"idle": "idle: horse standing, shifting and tossing its head, rider holding the spear upright",
                "walk": "gallop cycle: horse galloping at full speed with all four legs in proper gallop phases, rider leaning forward, spear levelled",
                "attack": "mounted attack: horse rearing slightly as the rider thrusts the spear down and forward, recover",
                "death": "death: horse stumbles and collapses on its side, rider thrown and lying on the ground in the last frames"},
    "general": {"idle": "idle: horse standing proudly, general raising the war fan to command",
                "walk": "gallop cycle: horse galloping at full speed with proper gallop leg phases, cloak billowing",
                "attack": "mounted attack: general draws a katana and slashes down from horseback, recover",
                "death": "death: horse collapses on its side, general falling and lying on the ground in the last frames"},
}

ASSETS = {}
for u, desc in UNITS.items():
    for a, act in ANIMS[u].items():
        ASSETS[f"unit_{u}_{a}"] = ("sheet", f"{SHEET}The character: {desc}. Animation: {act}. Style: {STYLE}.")

TEX = ("Seamless tileable top-down orthographic ground texture viewed straight from above, painterly hand-painted "
       "AAA strategy game terrain, soft natural lighting, no objects casting long shadows, no text, edges tile perfectly. ")
for name, d in {
    "grass": "lush green summer grass field with subtle clover and small wildflowers, moss greens",
    "meadow": "dry late-summer meadow, ochre and olive grass with patches of green",
    "dirt": "packed dirt road earth with small pebbles and cart wheel ruts, ochre brown",
    "mud": "trampled wet mud with puddles and footprints, dark brown",
    "forestfloor": "forest floor with pine needles, ferns and moss, dark green-brown",
    "riverbed": "shallow river water seen from above with pebbles visible through clear slate-blue water",
    "sand": "river bank gravel and sand with smooth grey stones",
    "paddy": "flooded rice paddy with rows of young green rice shoots in water",
}.items():
    ASSETS[f"tex_{name}"] = ("tex", TEX + d + ".")

PROP = ("Game asset cut-outs for a 2D strategy game, 3/4 overhead view (camera about 55 degrees above), painterly AAA "
        "style, soft top-left light, no ground shadows, no text, each object separate with lots of empty space between "
        "them, pure flat solid #FF00FF magenta background. ")
for name, d in {
    "pines": "4 different Japanese black pine trees (sculpted, windswept, full canopies seen from slightly above)",
    "maples": "4 different Japanese maple and broadleaf trees, two green and two turning autumn red",
    "bamboo": "3 dense clumps of tall green bamboo",
    "rocks": "6 varied mossy granite boulders and rock clusters of different sizes",
    "houses": "3 different traditional Japanese thatched-roof farmhouses (minka) with wooden walls",
    "shrine": "a small Shinto shrine with a vermilion torii gate and stone lanterns, as separate objects",
    "fences": "4 pieces: wooden rail fences, a bamboo palisade segment, a stack of hay, a wooden cart",
    "camp": "military camp props: a large crimson maku curtain enclosure with gold tomoe crest, a weapon rack with spears, a war drum taiko on a stand, tall nobori banners",
    "bushes": "8 small varied shrubs, bushes and tall grass tufts",
}.items():
    ASSETS[f"prop_{name}"] = ("prop", PROP + d + ".")

ART = "Painterly epic illustration, Sengoku-era Japan, ink-wash and lacquer colours, cinematic, no text, no watermark. "
ASSETS["art_title"] = ("art", ART + "Wide 16:9 key art: two great samurai armies clash on a misty plain at dawn, crimson banners with gold three-tomoe crest on the left, indigo banners on the right, a lone mounted general on a white horse in the foreground silhouetted against a huge blood-red sun, mountains behind.")
ASSETS["art_kurogawa"] = ("art", ART + "Wide 16:9: a broad river plain in summer with a shallow ford, a small thatched village, pine woods, crimson army camp on the near bank and indigo army on the far bank, seen from a hill.")
ASSETS["art_tenmoku"] = ("art", ART + "Wide 16:9: a misty mountain pass at dawn, pine forests, a mountain shrine with a torii, indigo-bannered army holding the ridge above, crimson army climbing from below.")
ASSETS["art_victory"] = ("art", ART + "Wide 16:9: victorious crimson samurai raising banners and katana under a golden sunset over a battlefield.")
ASSETS["art_defeat"] = ("art", ART + "Wide 16:9: a fallen crimson banner in the rain on a muddy battlefield, broken spears, mournful grey mood.")
PORT = "Square bust portrait painting for a strategy game unit card, dark lacquer-black background, dramatic rim light, painterly AAA, no text. "
for u, d in {
    "yari": "an ashigaru spearman in crimson jingasa hat and crimson armour, determined face, spear upright",
    "yumi": "an ashigaru archer in crimson jingasa hat, bow over shoulder, focused eyes",
    "teppo": "an ashigaru gunner in crimson jingasa hat holding a matchlock, smoke wisps, burning match cord",
    "samurai": "a samurai in crimson lacquered armour, kabuto with gold crest, iron menpo mask, katana",
    "cavalry": "a mounted samurai's head and shoulders with crimson armour and a horse head beside him",
    "general": "a young daimyo lord in black-gold armour with a golden crescent helmet crest, stern noble face",
}.items():
    ASSETS[f"portrait_{u}"] = ("art", PORT + d + ".")
ASSETS["ui_mon_hino"] = ("icon", "A Japanese family crest (kamon): three-comma mitsudomoe in gold, centred, clean flat vector-like brushed gold, on pure flat #FF00FF magenta background, no text.")
ASSETS["ui_mon_mizuno"] = ("icon", "A Japanese family crest (kamon): two crossed hawk feathers inside a circle, silver-white, centred, clean flat vector-like, on pure flat #FF00FF magenta background, no text.")
ASSETS["ui_lacquer"] = ("tex", "Seamless tileable texture of black urushi lacquer with very subtle warm brown depth and faint fine gold flecks, no text.")
ASSETS["ui_washi"] = ("tex", "Seamless tileable texture of warm cream Japanese washi paper with visible fibres, subtle mottling, no text, flat lighting.")
ASSETS["fx_sheet"] = ("prop", "Game VFX sprites on pure flat #FF00FF magenta background, painterly, separate with lots of space: 4 soft white-grey gunpowder smoke puffs, 3 brown dust clouds, 4 dark red blood splatter decals seen from above, 2 bright orange-yellow muzzle flashes, no text.")

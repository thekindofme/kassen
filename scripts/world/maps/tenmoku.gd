extends MapDef
## Scenario 2: "Mist over Tenmoku Pass" (GDD §2). Dawn, mist, autumn in the mountains.
##
## A pass climbs west → east. The Hino (player) start in the open valley floor to the west and
## must attack uphill. The Mizuno (AI, defending) hold the Tenmoku ridge to the east, crowned by
## a hilltop shrine with a torii on the climbing road. Dense pine forest covers both mountain
## flanks; the field between them narrows to "the Throat" (x≈2400, ~800 px wide, rocky
## outcrops on both shoulders) before opening onto the ridge slope.
##
## Tactical notes:
##  * Frontal: the road through the Throat is fast but funnels the army into arrow and teppo
##    range of the ridge; the ridge gives the defender height bonuses.
##  * North gap: a narrow clearing through the north pines (x≈2950) leads to the Kitsune knoll,
##    a small rise overlooking the Throat and the ridge's left flank (archers / teppo post).
##  * South track: a woodcutters' path winds through the southern forest and comes out on the
##    ridge's right flank behind rocks: slow and hidden, for cavalry or samurai to turn the line.
##  * Forest blocks are passable but slow (0.7) and give cover vs arrows.

const RIDGE := Vector2(3800, 1500)
const THROAT := Vector2(2420, 1620)


func _init() -> void:
	map_name = "tenmoku"
	title = "Mist over Tenmoku Pass"
	size = Vector2(4800, 3200)
	seed_value = 1575
	mist = true
	time_of_day = "dawn"

	river = PackedVector2Array()
	fords = []

	roads = [
		# the pass road: valley floor → Throat → switchbacks up to the shrine → over the crest
		MapDef.smooth_path(PackedVector2Array([Vector2(-30, 1760), Vector2(700, 1700), Vector2(1500, 1720),
			Vector2(2100, 1640), Vector2(2700, 1620), Vector2(3150, 1720), Vector2(3420, 1560),
			Vector2(3560, 1660), Vector2(3800, 1500), Vector2(3990, 1420), Vector2(4400, 1380),
			Vector2(4830, 1300)]), 6),
		# woodcutters' track through the southern pines onto the ridge's right flank
		MapDef.smooth_path(PackedVector2Array([Vector2(1500, 1760), Vector2(1650, 2250), Vector2(2100, 2560),
			Vector2(2700, 2640), Vector2(3150, 2480), Vector2(3450, 2230)]), 6),
	]
	road_width = 34.0

	var pine := "pine"
	forests = [
		# north flank
		{"c": Vector2(150, 280), "r": 420.0, "kind": pine}, {"c": Vector2(700, 330), "r": 400.0, "kind": pine},
		{"c": Vector2(1300, 300), "r": 420.0, "kind": pine}, {"c": Vector2(1850, 470), "r": 400.0, "kind": pine},
		{"c": Vector2(2420, 900), "r": 440.0, "kind": pine}, {"c": Vector2(1950, 800), "r": 260.0, "kind": pine}, {"c": Vector2(2420, 330), "r": 400.0, "kind": pine},
		{"c": Vector2(3420, 380), "r": 390.0, "kind": pine}, {"c": Vector2(3500, 760), "r": 200.0, "kind": "mixed"},
		{"c": Vector2(3950, 280), "r": 380.0, "kind": pine}, {"c": Vector2(4520, 330), "r": 420.0, "kind": pine},
		{"c": Vector2(2930, 130), "r": 200.0, "kind": pine},
		# south flank
		{"c": Vector2(150, 2950), "r": 420.0, "kind": pine}, {"c": Vector2(700, 2900), "r": 400.0, "kind": pine},
		{"c": Vector2(1250, 2950), "r": 400.0, "kind": pine}, {"c": Vector2(1850, 2850), "r": 400.0, "kind": pine},
		{"c": Vector2(2420, 2350), "r": 440.0, "kind": pine}, {"c": Vector2(2900, 2420), "r": 240.0, "kind": pine}, {"c": Vector2(2450, 2950), "r": 380.0, "kind": pine},
		{"c": Vector2(3000, 2850), "r": 380.0, "kind": pine}, {"c": Vector2(3500, 2950), "r": 360.0, "kind": pine},
		{"c": Vector2(4000, 2930), "r": 380.0, "kind": pine}, {"c": Vector2(4550, 2850), "r": 420.0, "kind": pine},
		{"c": Vector2(1780, 2400), "r": 200.0, "kind": "mixed"},
		# shrine grove on the crest (autumn maples)
		{"c": Vector2(4150, 1250), "r": 170.0, "kind": "maple", "red": 0.55},
	]
	for f in forests:
		if not f.has("red"):
			f["red"] = 0.03
	hills = [
		# the Tenmoku ridge (defender's line) and the broad eastern slope behind it
		{"c": Vector2(3680, 1050), "r": 300.0, "h": 30.0}, {"c": Vector2(3700, 1450), "r": 320.0, "h": 34.0},
		{"c": Vector2(3690, 1880), "r": 320.0, "h": 32.0}, {"c": Vector2(3640, 2300), "r": 280.0, "h": 24.0},
		{"c": Vector2(4450, 1600), "r": 1000.0, "h": 28.0},
		# shoulders of the Throat and the mountain flanks
		{"c": Vector2(2420, 850), "r": 380.0, "h": 34.0}, {"c": Vector2(2420, 2400), "r": 380.0, "h": 32.0},
		{"c": Vector2(1200, 150), "r": 700.0, "h": 40.0}, {"c": Vector2(3000, 120), "r": 700.0, "h": 44.0},
		{"c": Vector2(1300, 3120), "r": 700.0, "h": 40.0}, {"c": Vector2(3200, 3120), "r": 700.0, "h": 44.0},
		# Kitsune knoll (north gap) and a low swell on the valley floor
		{"c": Vector2(3000, 1000), "r": 260.0, "h": 28.0}, {"c": Vector2(900, 1650), "r": 420.0, "h": 8.0},
	]
	villages = []
	paddies = []
	ground_patches = [
		{"c": Vector2(3930, 1440), "r": 170.0, "mat": "dirt", "a": 0.6},     # trampled crest by the shrine
		{"c": Vector2(2250, 1260), "r": 120.0, "mat": "sand", "a": 0.7},     # scree under the outcrops
		{"c": Vector2(2620, 1230), "r": 110.0, "mat": "sand", "a": 0.7},
		{"c": Vector2(2300, 2000), "r": 120.0, "mat": "sand", "a": 0.7},
		{"c": Vector2(2640, 2030), "r": 110.0, "mat": "sand", "a": 0.65},
		{"c": Vector2(3350, 1130), "r": 110.0, "mat": "sand", "a": 0.6}, {"c": Vector2(3420, 2080), "r": 120.0, "mat": "sand", "a": 0.6},
		{"c": Vector2(2420, 1640), "r": 90.0, "mat": "mud", "a": 0.55},      # churned road in the Throat
		{"c": Vector2(1200, 1450), "r": 260.0, "mat": "meadow", "a": 0.7}, {"c": Vector2(700, 2000), "r": 240.0, "mat": "meadow", "a": 0.6},
		{"c": Vector2(3000, 1000), "r": 120.0, "mat": "meadow", "a": 0.7},
		# dry autumn grass on the ridge crest so the high ground reads at any zoom
		{"c": Vector2(3720, 1050), "r": 230.0, "mat": "meadow", "a": 0.75}, {"c": Vector2(3740, 1500), "r": 250.0, "mat": "meadow", "a": 0.75},
		{"c": Vector2(3720, 1920), "r": 250.0, "mat": "meadow", "a": 0.75}, {"c": Vector2(3680, 2300), "r": 200.0, "mat": "meadow", "a": 0.7},
		{"c": Vector2(1650, 2150), "r": 70.0, "mat": "mud", "a": 0.5},
	]

	deploy_zones = [Rect2(250, 800, 900, 1700), Rect2(3350, 760, 900, 1700)]
	home_dirs = [Vector2.LEFT, Vector2.RIGHT]
	armies = [
		MapDef.standard_layout(deploy_zones[0], Vector2.RIGHT),
		MapDef.standard_layout(deploy_zones[1], Vector2.LEFT),
	]
	ai_posture_hint = "defend"
	ai_hints = {"high_ground": RIDGE, "posture": "defend", "pass": THROAT,
		"north_gap": Vector2(2950, 760), "south_track": Vector2(3300, 2380)}
	scatter = {"bush": 0.8, "rock": 2.2, "field_tree": 0.7, "field_kind": "pine", "reeds": 0.0, "red": 0.3}
	_place_props()


func _p(id: String, pos: Vector2, s := 1.0, flip := false, clan := 0, b := 1.0) -> void:
	props.append({"id": id, "pos": pos, "s": s, "flip": flip, "clan": clan, "b": b})


## A rocky outcrop: a big boulder or two with smaller stones and a wind-bent pine.
func _outcrop(c: Vector2, n: int, spread: float, with_pine := true, seed_off := 0) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + seed_off * 101 + int(c.x) * 7 + int(c.y)
	var big := ["rocks_0", "rocks_4", "rocks_3"]
	var small := ["rocks_1", "rocks_2", "rocks_5", "rocks_3"]
	_p(big[rng.randi() % big.size()], c, rng.randf_range(1.5, 1.9), rng.randf() < 0.5)
	for k in n:
		var a := rng.randf() * TAU
		var d := rng.randf_range(0.35, 1.0) * spread
		var q := c + Vector2(cos(a) * d, sin(a) * d * 0.6)
		if k < (n + 1) / 2:
			_p(big[rng.randi() % big.size()], q, rng.randf_range(1.0, 1.4), rng.randf() < 0.5)
		else:
			_p(small[rng.randi() % small.size()], q, rng.randf_range(0.7, 1.1), rng.randf() < 0.5)
	for k in 2:
		_p("bushes_3" if k == 0 else "bushes_6", c + Vector2(rng.randf_range(-spread, spread), rng.randf_range(10, 30)), 1.0)
	if with_pine:
		_p(["pines_0", "pines_1", "pines_3"][rng.randi() % 3], c + Vector2(rng.randf_range(-40, 40), -20), 0.8, rng.randf() < 0.5)


func _place_props() -> void:
	# --- the crest: shrine in its maple grove, torii on the road, lanterns lining the approach ---
	_p("shrine_0", Vector2(4060, 1330), 0.85)
	_p("shrine_1", Vector2(3835, 1500), 0.68)
	for k in 3:
		_p("shrine_2", Vector2(3930 + k * 50, 1415 - k * 20), 0.55)
		_p("shrine_3", Vector2(3960 + k * 50, 1490 - k * 20), 0.55)
	_p("maples_3", Vector2(3950, 1300), 0.8); _p("maples_0", Vector2(4200, 1360), 0.75, true)
	_p("pines_2", Vector2(4140, 1500), 0.85)
	_p("rocks_4", Vector2(3990, 1560), 0.7); _p("bushes_1", Vector2(3960, 1580), 1.0)
	# Mizuno nobori planted along the crest behind their line
	for k in 6:
		_p("camp_1", Vector2(4180 + (k % 2) * 30, 1000 + k * 210), 0.85, true, 1)
	_p("camp_0", Vector2(4330, 1720), 1.2, true, 1)
	_p("camp_4", Vector2(4250, 1640), 0.9, true, 1)
	_p("camp_3", Vector2(4420, 1620), 0.9, true, 1)

	# --- outcrops: the Throat's shoulders, the ridge slopes, the valley floor ---
	_outcrop(Vector2(2250, 1250), 6, 110.0, true, 1)
	_outcrop(Vector2(2610, 1225), 5, 100.0, false, 2)
	_outcrop(Vector2(2290, 2010), 6, 110.0, true, 3)
	_outcrop(Vector2(2640, 2040), 5, 100.0, true, 4)
	_outcrop(Vector2(3340, 1130), 4, 90.0, false, 5)
	_outcrop(Vector2(3420, 2090), 5, 100.0, true, 6)
	_outcrop(Vector2(1520, 1270), 3, 80.0, true, 7)
	_outcrop(Vector2(1620, 2180), 3, 80.0, false, 8)
	_outcrop(Vector2(3050, 920), 3, 70.0, true, 9)      # Kitsune knoll
	_outcrop(Vector2(3200, 2330), 4, 90.0, false, 10)   # where the south track comes out
	# a roadside Jizo-like lantern pair where the climb starts
	_p("shrine_2", Vector2(2930, 1670), 0.55); _p("shrine_3", Vector2(2990, 1760), 0.55)

extends MapDef
## Scenario 1: "The Ford at Kurogawa" (GDD §2). Summer day, open plain, 1574.
##
## The Black River meanders north–south. The capital road crosses it at one broad shallow
## ford with sandy beaches (the key to the map). The Hino (player, west) hold the bank with the
## village and Hachiman Hill, a low rise with a shrine that overlooks the ford from ~500 px:
## archers and teppo on it cover the crossing. The Mizuno (AI, east) deploy on their own
## higher hill with their camp behind it.
##
## Flanks: a narrow second ford hides in the northern woods (pine and maple on both banks,
## a gap in the trees leads to it): a slow, single-file route for cavalry or samurai to turn
## a flank. The south is wide open fields and paddies on the west bank and a grove plus woods
## on the east bank, where the river runs deep (no crossing).
##
## Kept invariants (scripts/test/sim_tests.gd, ai_tests.gd): deep water at (2700,1300), the main
## ford is fords[0] centred on (2665,1645) with a=(2540,1640), road fast at (1400,1600), forest at
## (900,650), Mizuno hill > 40 at (3800,1700).

const FORD := Vector2(2665, 1645)


func _init() -> void:
	map_name = "kurogawa"
	title = "The Ford at Kurogawa"
	size = Vector2(4800, 3200)
	seed_value = 1574
	time_of_day = "day"
	mist = false

	river = MapDef.smooth_path(PackedVector2Array([
		Vector2(2790, -80), Vector2(2725, 250), Vector2(2610, 540), Vector2(2690, 830),
		Vector2(2770, 1060), Vector2(2700, 1300), Vector2(2650, 1500), Vector2(2665, 1650),
		Vector2(2745, 1870), Vector2(2880, 2120), Vector2(2925, 2420), Vector2(2835, 2700),
		Vector2(2860, 2960), Vector2(2960, 3280)]), 6)
	river_width = 120.0
	fords = [
		{"a": Vector2(2540, 1640), "b": Vector2(2790, 1650), "width": 230.0},   # the capital-road ford
		{"a": Vector2(2545, 385), "b": Vector2(2790, 400), "width": 140.0},     # hidden woodland ford
	]

	roads = [
		MapDef.smooth_path(PackedVector2Array([Vector2(-30, 1470), Vector2(700, 1515), Vector2(1400, 1600),
			Vector2(2050, 1658), Vector2(2540, 1645), Vector2(2790, 1650), Vector2(3300, 1560),
			Vector2(3900, 1480), Vector2(4830, 1440)]), 5),
		MapDef.smooth_path(PackedVector2Array([Vector2(2060, 1660), Vector2(2095, 1950), Vector2(2080, 2250),
			Vector2(1930, 2750), Vector2(1880, 3230)]), 5),
		MapDef.smooth_path(PackedVector2Array([Vector2(2160, 1662), Vector2(2190, 1450), Vector2(2265, 1185)]), 4),
	]
	road_width = 38.0

	forests = [
		# north-west pine wood (behind the Hino right wing)
		{"c": Vector2(800, 540), "r": 320.0, "kind": "pine"}, {"c": Vector2(1180, 400), "r": 250.0, "kind": "pine"},
		{"c": Vector2(470, 330), "r": 260.0, "kind": "pine"}, {"c": Vector2(1500, 260), "r": 180.0, "kind": "mixed"},
		# northern woods around the hidden ford (gap at y≈400)
		{"c": Vector2(2180, 170), "r": 230.0, "kind": "mixed"}, {"c": Vector2(2300, 650), "r": 210.0, "kind": "mixed"},
		{"c": Vector2(1950, 560), "r": 170.0, "kind": "pine"},
		{"c": Vector2(3080, 160), "r": 220.0, "kind": "maple", "red": 0.08}, {"c": Vector2(3060, 690), "r": 210.0, "kind": "mixed"},
		# shrine grove on Hachiman Hill
		{"c": Vector2(2330, 1000), "r": 140.0, "kind": "maple", "red": 0.06},
		# north-east pine wood (behind the Mizuno left)
		{"c": Vector2(3820, 520), "r": 320.0, "kind": "pine"}, {"c": Vector2(4200, 780), "r": 230.0, "kind": "pine"},
		{"c": Vector2(4450, 330), "r": 260.0, "kind": "mixed"},
		# south-west wood and bamboo grove
		{"c": Vector2(620, 2620), "r": 340.0, "kind": "mixed"}, {"c": Vector2(980, 2840), "r": 250.0, "kind": "pine"},
		{"c": Vector2(330, 2940), "r": 240.0, "kind": "pine"}, {"c": Vector2(1560, 2620), "r": 140.0, "kind": "bamboo"},
		# south-east: grove by the river and the Mizuno southern wood
		{"c": Vector2(3260, 2100), "r": 150.0, "kind": "maple"},
		{"c": Vector2(4060, 2760), "r": 320.0, "kind": "mixed"}, {"c": Vector2(4420, 2960), "r": 230.0, "kind": "pine"},
		{"c": Vector2(3480, 2560), "r": 170.0, "kind": "mixed"},
	]
	hills = [
		{"c": Vector2(2330, 1330), "r": 330.0, "h": 40.0},   # Hachiman Hill, overlooks the ford
		{"c": Vector2(1000, 1300), "r": 520.0, "h": 26.0},   # Hino deployment rise
		{"c": Vector2(3800, 1700), "r": 560.0, "h": 60.0},   # Mizuno hill
		{"c": Vector2(2050, 2700), "r": 380.0, "h": 24.0},
		{"c": Vector2(3350, 620), "r": 300.0, "h": 22.0},
		{"c": Vector2(4500, 2200), "r": 420.0, "h": 30.0},
	]
	villages = [Rect2(1900, 1610, 420, 120)]
	paddies = [Rect2(1720, 1950, 320, 250), Rect2(2135, 1950, 300, 260), Rect2(1760, 2240, 260, 200)]
	ground_patches = [
		{"c": Vector2(2505, 1650), "r": 120.0, "mat": "sand"}, {"c": Vector2(2820, 1655), "r": 110.0, "mat": "sand"},
		{"c": Vector2(2440, 1655), "r": 70.0, "mat": "mud", "a": 0.6}, {"c": Vector2(2880, 1640), "r": 60.0, "mat": "mud", "a": 0.5},
		{"c": Vector2(2510, 390), "r": 95.0, "mat": "sand"}, {"c": Vector2(2820, 405), "r": 95.0, "mat": "sand"},
		{"c": Vector2(270, 1680), "r": 220.0, "mat": "dirt", "a": 0.7},      # Hino camp
		{"c": Vector2(4500, 1640), "r": 220.0, "mat": "dirt", "a": 0.7},     # Mizuno camp
		{"c": Vector2(1810, 1560), "r": 120.0, "mat": "mud", "a": 0.55}, {"c": Vector2(2020, 1570), "r": 120.0, "mat": "mud", "a": 0.55},
		{"c": Vector2(2350, 1570), "r": 120.0, "mat": "mud", "a": 0.55}, {"c": Vector2(1870, 1800), "r": 120.0, "mat": "mud", "a": 0.5},
		{"c": Vector2(2120, 1810), "r": 110.0, "mat": "mud", "a": 0.5}, {"c": Vector2(2330, 1790), "r": 110.0, "mat": "mud", "a": 0.5},
		{"c": Vector2(2360, 1340), "r": 210.0, "mat": "meadow", "a": 0.7},   # dry grass cap: the overlook reads from afar
		{"c": Vector2(2275, 1160), "r": 90.0, "mat": "sand", "a": 0.7},      # shrine forecourt
		{"c": Vector2(2900, 2300), "r": 140.0, "mat": "sand", "a": 0.7},     # shingle bar
		{"c": Vector2(2590, 900), "r": 110.0, "mat": "sand", "a": 0.6},
	]

	deploy_zones = [Rect2(450, 850, 900, 1650), Rect2(3450, 850, 900, 1650)]
	home_dirs = [Vector2.LEFT, Vector2.RIGHT]
	armies = [
		MapDef.standard_layout(deploy_zones[0], Vector2.RIGHT),
		MapDef.standard_layout(deploy_zones[1], Vector2.LEFT),
	]
	ai_posture_hint = "attack"
	ai_hints = {"ford": FORD, "high_ground": Vector2(3800, 1700), "overlook": Vector2(2330, 1330),
		"flank_ford": Vector2(2665, 392), "posture": "attack"}
	scatter = {"bush": 1.0, "rock": 0.8, "field_tree": 1.0, "reeds": 1.2, "red": 0.08}
	_place_props()


func _p(id: String, pos: Vector2, s := 1.0, flip := false, clan := 0, b := 1.0) -> void:
	props.append({"id": id, "pos": pos, "s": s, "flip": flip, "clan": clan, "b": b})


func _place_props() -> void:
	# --- village along the capital road: farmhouses face the road on both sides ---
	_p("houses_1", Vector2(1800, 1588), 0.85)
	_p("houses_0", Vector2(2015, 1598), 0.82)
	_p("houses_2", Vector2(2355, 1598), 0.84, true)
	_p("houses_2", Vector2(1865, 1830), 0.82, true)
	_p("houses_1", Vector2(2125, 1842), 0.8, true)
	_p("houses_0", Vector2(2335, 1822), 0.78)
	# yards: haystacks, a cart by the road, fences on the yard edges
	_p("fences_2", Vector2(1935, 1525), 0.8); _p("fences_2", Vector2(1960, 1545), 0.7)
	_p("fences_2", Vector2(2420, 1540), 0.8); _p("fences_2", Vector2(2000, 1850), 0.75)
	_p("fences_3", Vector2(2215, 1700), 0.8, true)
	_p("fences_3", Vector2(1770, 1700), 0.75)
	for k in 5:
		_p("fences_0", Vector2(1745 + k * 64, 1462 + k * 2), 0.9)
	for k in 4:
		_p("fences_1", Vector2(2265 + k * 56, 1480), 0.9)
	for k in 5:
		_p("fences_0", Vector2(1760 + k * 64, 1915), 0.9)
	for k in 4:
		_p("fences_1", Vector2(2180 + k * 58, 1905), 0.9)
	# paddy dikes: grass tufts on the bunds
	for k in 6:
		_p("bushes_7", Vector2(1730 + k * 58, 2210), 0.8, k % 2 == 0)
		_p("bushes_7", Vector2(2145 + k * 50, 2222), 0.8, k % 2 == 1)

	# --- Hachiman shrine on the north slope of the hill overlooking the ford ---
	_p("shrine_0", Vector2(2280, 1135), 0.78)
	_p("shrine_1", Vector2(2215, 1300), 0.62)
	_p("shrine_2", Vector2(2215, 1210), 0.6); _p("shrine_3", Vector2(2330, 1215), 0.6)
	_p("maples_0", Vector2(2150, 1160), 0.75); _p("maples_2", Vector2(2420, 1170), 0.7, true)
	_p("rocks_4", Vector2(2395, 1290), 0.6); _p("bushes_6", Vector2(2170, 1240), 1.0)

	# --- the ford: stepping stones mark both edges of the shallows ---
	for q in [Vector2(2585, 1540), Vector2(2650, 1532), Vector2(2735, 1545),
			Vector2(2590, 1752), Vector2(2680, 1760), Vector2(2748, 1750)]:
		_p("rocks_2", q, 0.55, int(q.x) % 2 == 0)
	_p("rocks_3", Vector2(2470, 1560), 0.7); _p("rocks_5", Vector2(2860, 1760), 0.7, true)
	_p("bushes_7", Vector2(2480, 1760), 1.0); _p("bushes_7", Vector2(2860, 1540), 1.0, true)
	_p("pines_1", Vector2(2465, 1810), 0.7, true)   # a lone pine leaning over the ford
	for q in [Vector2(2610, 322), Vector2(2700, 330), Vector2(2610, 458), Vector2(2720, 470)]:
		_p("rocks_2", q, 0.5, int(q.y) % 2 == 0)   # hidden ford stepping stones

	# --- Hino camp (west, behind the deployment zone) ---
	_camp(Vector2(270, 1690), 0, false)
	# --- Mizuno camp (east, behind their hill) ---
	_camp(Vector2(4510, 1650), 1, true)


func _camp(c: Vector2, clan: int, flip: bool) -> void:
	var sx := -1.0 if flip else 1.0
	_p("camp_0", c + Vector2(-30 * sx, 0), 1.35, flip, clan)            # maku enclosure
	_p("camp_0", c + Vector2(20 * sx, 190), 1.1, not flip, clan)
	_p("camp_4", c + Vector2(110 * sx, 70), 0.9, flip, clan)            # taiko
	_p("camp_3", c + Vector2(-140 * sx, 60), 0.9, flip, clan)           # spear racks
	_p("camp_3", c + Vector2(-110 * sx, 250), 0.9, not flip, clan)
	for k in 5:   # nobori line facing the field
		_p("camp_1", c + Vector2(170 * sx, -150 + k * 85), 0.85, flip, clan)
	_p("camp_2", c + Vector2(-120 * sx, -70), 0.9, flip, clan)
	_p("camp_2", c + Vector2(-80 * sx, 300), 0.9, flip, clan)

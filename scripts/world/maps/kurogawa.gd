extends MapDef
## Scenario 1: "The Ford at Kurogawa" (GDD §2). Summer day, open plain. The Black River runs
## north–south with one ford where the capital road crosses. The Hino (player) hold the west
## bank with the village; the Mizuno come from the east and their camp sits on a low hill.


func _init() -> void:
	map_name = "kurogawa"
	title = "The Ford at Kurogawa"
	size = Vector2(4800, 3200)
	seed_value = 1574

	river = PackedVector2Array([
		Vector2(2760, -40), Vector2(2640, 420), Vector2(2780, 900), Vector2(2720, 1300),
		Vector2(2660, 1640), Vector2(2730, 2000), Vector2(2900, 2450), Vector2(2860, 2850), Vector2(2950, 3240)])
	river_width = 120.0
	fords = [{"a": Vector2(2540, 1640), "b": Vector2(2790, 1650), "width": 200.0}]

	roads = [
		PackedVector2Array([Vector2(-20, 1480), Vector2(700, 1520), Vector2(1400, 1600), Vector2(2050, 1660),
			Vector2(2660, 1645), Vector2(3300, 1600), Vector2(4000, 1500), Vector2(4820, 1440)]),
		PackedVector2Array([Vector2(2050, 1660), Vector2(2100, 2200), Vector2(1900, 2800), Vector2(1850, 3220)]),
	]
	road_width = 38.0

	forests = [
		{"c": Vector2(900, 650), "r": 320.0}, {"c": Vector2(1200, 520), "r": 220.0},
		{"c": Vector2(650, 2550), "r": 360.0}, {"c": Vector2(950, 2750), "r": 240.0},
		{"c": Vector2(2300, 850), "r": 200.0},
		{"c": Vector2(3750, 750), "r": 380.0}, {"c": Vector2(4100, 950), "r": 230.0},
		{"c": Vector2(3950, 2650), "r": 320.0}, {"c": Vector2(3200, 2250), "r": 190.0},
	]
	hills = [
		{"c": Vector2(1250, 1250), "r": 520.0, "h": 45.0},
		{"c": Vector2(3800, 1700), "r": 560.0, "h": 60.0},
		{"c": Vector2(2050, 2650), "r": 380.0, "h": 30.0},
		{"c": Vector2(3300, 600), "r": 300.0, "h": 25.0},
	]
	villages = [Rect2(1900, 1720, 460, 320)]
	houses = [Vector2(1960, 1800), Vector2(2080, 1790), Vector2(2240, 1830), Vector2(1990, 1940),
		Vector2(2150, 1960), Vector2(2300, 1990), Vector2(2380, 1880)]
	paddies = [Rect2(1620, 2120, 330, 260), Rect2(2200, 2140, 260, 220)]

	deploy_zones = [Rect2(500, 950, 1250, 1400), Rect2(3250, 900, 1250, 1450)]
	home_dirs = [Vector2.LEFT, Vector2.RIGHT]
	armies = [
		MapDef.standard_layout(deploy_zones[0], Vector2.RIGHT),
		MapDef.standard_layout(deploy_zones[1], Vector2.LEFT),
	]
	ai_hints = {"ford": Vector2(2665, 1645), "high_ground": Vector2(3800, 1700), "posture": "attack"}

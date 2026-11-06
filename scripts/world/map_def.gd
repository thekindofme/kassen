class_name MapDef
extends RefCounted
## Data description of a battle map. Subclass per map (see maps/kurogawa.gd) and fill these
## in `_init()`. Terrain rasterises it; battle.gd spawns the armies from `armies`.

var map_name := ""
var title := ""
var size := Vector2(4800, 3200)
var seed_value := 7

## River centre-line polyline and width. Deep water is impassable except at fords.
var river := PackedVector2Array()
var river_width := 110.0
## Fords: {"a": Vector2 bank point, "b": Vector2 other bank point, "width": float corridor width}
var fords: Array[Dictionary] = []
## Roads: polylines.
var roads: Array[PackedVector2Array] = []
var road_width := 36.0
## Forests: union of soft blobs {"c": Vector2, "r": float}.
var forests: Array[Dictionary] = []
## Hills: gaussian bumps {"c": Vector2, "r": float, "h": float (world px of height)}.
var hills: Array[Dictionary] = []
## Village: trampled-earth area plus house positions (house = base-centre point).
var villages: Array[Rect2] = []
var houses: Array[Vector2] = []
var paddies: Array[Rect2] = []
## Deployment zone per team and the direction of each team's home edge (routing / withdraw).
var deploy_zones: Array[Rect2] = [Rect2(), Rect2()]
var home_dirs: Array = [Vector2.LEFT, Vector2.RIGHT]
## Initial armies: per team, list of {"type": String, "pos": Vector2, "facing": Vector2}.
var armies: Array = [[], []]
## Free-form hints for the AI general (e.g. key positions).
var ai_hints: Dictionary = {}


## Lays out a standard army inside `zone`, facing `fwd`. Line: cavalry wings, spears and
## samurai in the centre, teppo out front, archers behind, general at the rear.
static func standard_layout(zone: Rect2, fwd: Vector2, composition: Array = UnitTypes.STANDARD_ARMY) -> Array:
	var c := zone.get_center() + fwd * minf(zone.size.x, zone.size.y) * 0.2
	var right := Vector2(-fwd.y, fwd.x)
	var counts := {}
	for k in composition:
		counts[k] = counts.get(k, 0) + 1
	var out: Array = []
	# front line, left to right
	var line: Array[String] = []
	var inf: Array[String] = []
	for k in ["yari", "samurai"]:
		for q in counts.get(k, 0):
			inf.append(k)
	# interleave yari / samurai: Y S Y S Y
	var ys: Array[String] = []
	var ss: Array[String] = []
	for k in inf:
		(ys if k == "yari" else ss).append(k)
	while not ys.is_empty() or not ss.is_empty():
		if not ys.is_empty():
			line.append(ys.pop_back())
		if not ss.is_empty():
			line.append(ss.pop_back())
	var cav: int = counts.get("cavalry", 0)
	for q in cav:
		if q % 2 == 0:
			line.push_front("cavalry")
		else:
			line.push_back("cavalry")
	var widths: Array[float] = []
	var total := 0.0
	for k in line:
		var s: Dictionary = UnitTypes.STATS[k]
		var w: float = float(s["files"] - 1) * s["spacing"].x
		widths.append(w)
		total += w
	total += 50.0 * float(maxi(0, line.size() - 1))
	var x := -total * 0.5
	for q in line.size():
		var w2: float = widths[q]
		out.append({"type": line[q], "pos": c + right * (x + w2 * 0.5), "facing": fwd})
		x += w2 + 50.0
	# teppo out front, archers behind the line
	var tep: int = counts.get("teppo", 0)
	for q in tep:
		var off := (float(q) - float(tep - 1) * 0.5) * 340.0
		out.append({"type": "teppo", "pos": c + fwd * 110.0 + right * off, "facing": fwd})
	var yumi: int = counts.get("yumi", 0)
	for q in yumi:
		var off2 := (float(q) - float(yumi - 1) * 0.5) * 520.0
		out.append({"type": "yumi", "pos": c - fwd * 120.0 + right * off2, "facing": fwd})
	for q in counts.get("general", 0):
		out.append({"type": "general", "pos": c - fwd * 300.0, "facing": fwd})
	return out

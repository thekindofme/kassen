class_name PropLayer
extends Node2D
## Real prop sprites for a MapDef: assets/props/*.png + props.json packed into one runtime
## atlas and drawn with MultiMeshes (scripts/render/shaders/prop.gdshader).
##
## Usage (battle.gd):
##   var props := PropLayer.new(); props.setup(map, terrain, sim); add_child(props)   # under soldiers
##   ... add the soldier renderer ...
##   add_child(props.canopy)                                                          # above soldiers
##
## This node draws soft contact shadows and LOW props (bushes, rocks, fences, hay, cart) under the
## soldiers. `canopy` draws TALL props (trees, bamboo, houses, shrine, torii, lanterns, camp) above
## the soldiers, y-sorted among themselves, fading to see-through where soldiers stand under or
## just in front of them. Placement = the map's explicit `props` plus deterministic procedural
## dressing: forest trees by forest "kind", edge undergrowth, field trees, bushes, rocks.

const PROPS_DIR := "res://assets/props/"
const TALL_KINDS := ["tree", "bamboo", "house", "shrine", "camp"]
const SPECIES := {
	"pine": ["pines_0", "pines_1", "pines_2", "pines_3"],
	"maple": ["maples_1", "maples_2"],
	"red_maple": ["maples_0", "maples_3"],
	"bamboo": ["bamboo_0", "bamboo_1", "bamboo_2"],
}
const BUSHES := ["bushes_0", "bushes_0", "bushes_3", "bushes_6", "bushes_6", "bushes_7", "bushes_1", "bushes_2", "bushes_5"]
const UNDERGROWTH := ["bushes_0", "bushes_6", "bushes_3", "bushes_0", "bushes_6"]
const SMALL_ROCKS := ["rocks_1", "rocks_2", "rocks_3", "rocks_5"]
const BIG_ROCKS := ["rocks_0", "rocks_4", "rocks_3"]

static var _atlas: Texture2D
static var _reg := {}      # id -> {"uv": Rect2, "w", "h", "ax", "ay" (world px at s=1), "kind"}
static var _shader: Shader

var map: MapDef
var terrain: Terrain
var sim: BattleSim
var canopy: Node2D
var placed: Array = []     # {"id", "pos", "s", "flip", "clan", "b"}
var _blockers: Array = []  # [Vector2, radius]
var _spawns := PackedVector2Array()
var _rng := RandomNumberGenerator.new()
var _tall_mm: MultiMesh
var _tall_rect: Array[Rect2] = []
var _tall_col: Array[Color] = []
var _tall_fade := PackedByteArray()
var _cursor := 0


func setup(p_map: MapDef, p_terrain: Terrain, p_sim: BattleSim = null) -> void:
	map = p_map
	terrain = p_terrain
	sim = p_sim
	_ensure_atlas()
	_rng.seed = map.seed_value * 31 + 77
	for team in map.armies.size():
		for e in map.armies[team]:
			_spawns.append(e["pos"])
	for pr in map.props:
		_add(pr["id"], pr["pos"], pr.get("s", 1.0), pr.get("flip", false), pr.get("clan", 0), pr.get("b", 1.0))
		_blockers.append([pr["pos"], _footprint(pr["id"], pr.get("s", 1.0))])
	_dress_forests()
	_dress_fields()
	_build()


# --------------------------------------------------------------------------------------
#  Atlas
# --------------------------------------------------------------------------------------

static func _ensure_atlas() -> void:
	if _atlas != null:
		return
	_shader = load("res://scripts/render/shaders/prop.gdshader")
	var f := FileAccess.open(PROPS_DIR + "props.json", FileAccess.READ)
	var meta: Dictionary = JSON.parse_string(f.get_as_text())
	var sc: float = meta.get("_scale", 2.0)
	var ids: Array = []
	var imgs := {}
	for id in meta.keys():
		if String(id).begins_with("_"):
			continue
		var img := _load_img(PROPS_DIR + id + ".png")
		if img == null:
			continue
		ids.append(id)
		imgs[id] = img
	ids.sort_custom(func(a, b): return imgs[a].get_height() > imgs[b].get_height())
	# shelf-pack into a 4096-wide atlas, 4 px padding; plus a generated soft shadow blob
	var W := 4096
	var pad := 4
	var shadow := _shadow_img(128, 64)
	var rects := {}
	var x := pad
	var y := pad
	var shelf := 0
	for id in ids + ["_shadow"]:
		var im: Image = shadow if id == "_shadow" else imgs[id]
		if x + im.get_width() + pad > W:
			x = pad
			y += shelf + pad
			shelf = 0
		rects[id] = Rect2i(x, y, im.get_width(), im.get_height())
		x += im.get_width() + pad
		shelf = maxi(shelf, im.get_height())
	var H := nearest_po2(y + shelf + pad)
	var atlas := Image.create(W, H, false, Image.FORMAT_RGBA8)
	atlas.fill(Color(0, 0, 0, 0))
	for id in rects:
		var im: Image = shadow if id == "_shadow" else imgs[id]
		var r: Rect2i = rects[id]
		atlas.blit_rect(im, Rect2i(Vector2i.ZERO, im.get_size()), r.position)
		var m: Dictionary = {} if id == "_shadow" else meta[id]
		_reg[id] = {
			"uv": Rect2(Vector2(r.position) / Vector2(W, H), Vector2(r.size) / Vector2(W, H)),
			"w": r.size.x / sc, "h": r.size.y / sc,
			"ax": float(m.get("ax", r.size.x * 0.5)) / sc, "ay": float(m.get("ay", r.size.y * 0.5)) / sc,
			"kind": m.get("kind", "shadow"),
		}
	atlas.generate_mipmaps()
	_atlas = ImageTexture.create_from_image(atlas)


static func _load_img(path: String) -> Image:
	var img: Image = null
	if ResourceLoader.exists(path):
		var t = load(path)
		if t is Texture2D:
			img = t.get_image()
	if img == null and FileAccess.file_exists(path):
		img = Image.load_from_file(ProjectSettings.globalize_path(path))
	if img == null or img.is_empty():
		return null
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	return img


static func _shadow_img(w: int, h: int) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for py in h:
		for px in w:
			var dx := (px + 0.5 - w * 0.5) / (w * 0.5)
			var dy := (py + 0.5 - h * 0.5) / (h * 0.5)
			var d := sqrt(dx * dx + dy * dy)
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(px, py, Color(0.04, 0.05, 0.02, a * a * (3.0 - 2.0 * a)))
	return img


static func region(id: String) -> Dictionary:
	_ensure_atlas()
	return _reg.get(id, {})


static func is_tall(id: String) -> bool:
	return region(id).get("kind", "") in TALL_KINDS


func _footprint(id: String, s: float) -> float:
	var r := region(id)
	if r.is_empty():
		return 20.0
	return r["w"] * s * (0.42 if r["kind"] in ["house", "shrine", "camp"] else 0.3)


func _add(id: String, pos: Vector2, s := 1.0, flip := false, clan := 0, b := 1.0) -> void:
	if not _reg.has(id):
		push_warning("PropLayer: unknown prop '%s'" % id)
		return
	placed.append({"id": id, "pos": pos, "s": s, "flip": flip, "clan": clan, "b": b})


func _blocked(p: Vector2, extra: float) -> bool:
	for b in _blockers:
		if p.distance_to(b[0]) < b[1] + extra:
			return true
	return false


func _near_spawn(p: Vector2, d: float) -> bool:
	for s in _spawns:
		if absf(p.x - s.x) < d and absf(p.y - s.y) < d * 1.6:
			return true
	return false


## The forest blob whose (soft) edge `p` is deepest inside.
func _forest_at(p: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var bd := INF
	for f in map.forests:
		var d: float = p.distance_to(f["c"]) - float(f["r"])
		if d < bd:
			bd = d
			best = f
	return best


func _pick_tree(kind: String, red: float) -> String:
	var r := _rng.randf()
	var sp := "pine"
	match kind:
		"pine": sp = "pine" if r < 0.86 else "maple"
		"maple": sp = "maple" if r < 0.8 else "pine"
		"bamboo": sp = "bamboo" if r < 0.88 else "maple"
		_: sp = "pine" if r < 0.55 else "maple"
	if sp == "maple" and _rng.randf() < red:
		sp = "red_maple"
	var arr: Array = SPECIES[sp]
	return arr[_rng.randi() % arr.size()]


func _ground_ok(p: Vector2) -> bool:
	if p.x < 8.0 or p.y < 8.0 or p.x > map.size.x - 8.0 or p.y > map.size.y - 8.0:
		return false
	var m := terrain.material_at(p)
	return m != Terrain.Mat.WATER and m != Terrain.Mat.FORD and m != Terrain.Mat.ROAD \
		and m != Terrain.Mat.VILLAGE and m != Terrain.Mat.PADDY


func _dress_forests() -> void:
	var step := 46.0
	var y := step * 0.5
	while y < map.size.y:
		var x := step * 0.5 + (step * 0.5 if int(y / step) % 2 == 1 else 0.0)
		while x < map.size.x:
			var p := Vector2(x, y) + Vector2(_rng.randf_range(-20, 20), _rng.randf_range(-20, 20))
			x += step
			var f := terrain.forest_value(p)
			if f < 0.1 or not _ground_ok(p) or terrain.material_at(p) == Terrain.Mat.BANK or _blocked(p, 10.0):
				continue
			var fd := _forest_at(p)
			var kind: String = fd.get("kind", "mixed")
			var dens: float = fd.get("density", 1.0)
			var red: float = fd.get("red", 0.05)
			var r := _rng.randf()
			if f > 0.5:
				var prob := lerpf(0.3, 0.9, smoothstep(0.5, 0.95, f)) * dens
				if r < prob and not _near_spawn(p, 110.0):
					_add(_pick_tree(kind, red), p, _rng.randf_range(0.7, 0.95) * lerpf(0.85, 1.0, f), _rng.randf() < 0.5, 0, _rng.randf_range(0.82, 1.0))
				elif r < prob + 0.3:
					_add(UNDERGROWTH[_rng.randi() % UNDERGROWTH.size()], p, _rng.randf_range(0.9, 1.3), _rng.randf() < 0.5, 0, _rng.randf_range(0.8, 0.95))
			else:
				# ragged edge: saplings and undergrowth
				if r < 0.16 * dens and not _near_spawn(p, 110.0):
					_add(_pick_tree(kind, red), p, _rng.randf_range(0.5, 0.68), _rng.randf() < 0.5, 0, _rng.randf_range(0.88, 1.0))
				elif r < 0.62:
					_add(UNDERGROWTH[_rng.randi() % UNDERGROWTH.size()], p + Vector2(_rng.randf_range(-12, 12), 0), _rng.randf_range(0.8, 1.25), _rng.randf() < 0.5)
		y += step


func _dress_fields() -> void:
	var sc: Dictionary = map.scatter
	var step := 64.0
	var y := step * 0.5
	while y < map.size.y:
		var x := step * 0.5
		while x < map.size.x:
			var p := Vector2(x, y) + Vector2(_rng.randf_range(-28, 28), _rng.randf_range(-28, 28))
			x += step
			if not _ground_ok(p) or terrain.forest_value(p) > 0.1 or _blocked(p, 24.0):
				continue
			var m := terrain.material_at(p)
			var hgt := terrain.height(p)
			var r := _rng.randf()
			if m == Terrain.Mat.BANK:
				if r < 0.16 * sc.get("reeds", 1.0):
					_add("bushes_7", p, _rng.randf_range(0.8, 1.2), _rng.randf() < 0.5)
				elif r < 0.2 * sc.get("reeds", 1.0):
					_add(SMALL_ROCKS[_rng.randi() % SMALL_ROCKS.size()], p, _rng.randf_range(0.5, 0.8), _rng.randf() < 0.5)
				continue
			var tree_p: float = 0.0035 * sc.get("field_tree", 1.0)
			var rock_p: float = (0.006 + 0.02 * smoothstep(12.0, 50.0, hgt)) * sc.get("rock", 1.0)
			var bush_p: float = 0.03 * sc.get("bush", 1.0)
			if r < tree_p and not _near_spawn(p, 160.0):
				var n := 1 + _rng.randi() % 3
				var kind: String = sc.get("field_kind", "mixed")
				for q in n:
					var tp := p + Vector2(_rng.randf_range(-60, 60), _rng.randf_range(-40, 40)) * float(mini(q, 1))
					if _ground_ok(tp):
						_add(_pick_tree(kind, sc.get("red", 0.15)), tp, _rng.randf_range(0.62, 0.85), _rng.randf() < 0.5, 0, _rng.randf_range(0.9, 1.0))
						_add(BUSHES[_rng.randi() % BUSHES.size()], tp + Vector2(_rng.randf_range(-40, 40), _rng.randf_range(6, 20)), _rng.randf_range(0.8, 1.1))
			elif r < tree_p + rock_p:
				var big := hgt > 25.0 and _rng.randf() < 0.35
				var arr: Array = BIG_ROCKS if big else SMALL_ROCKS
				_add(arr[_rng.randi() % arr.size()], p, _rng.randf_range(0.55, 0.9), _rng.randf() < 0.5)
				if _rng.randf() < 0.5:
					_add(SMALL_ROCKS[_rng.randi() % SMALL_ROCKS.size()], p + Vector2(_rng.randf_range(-36, 36), _rng.randf_range(4, 18)), _rng.randf_range(0.4, 0.6), _rng.randf() < 0.5)
			elif r < tree_p + rock_p + bush_p:
				_add(BUSHES[_rng.randi() % BUSHES.size()], p, _rng.randf_range(0.75, 1.1), _rng.randf() < 0.5)
		y += step


# --------------------------------------------------------------------------------------
#  MultiMeshes
# --------------------------------------------------------------------------------------

func _xform(r: Dictionary, pos: Vector2, s: float, flip: bool) -> Transform2D:
	var w: float = r["w"] * s
	var h: float = r["h"] * s
	var ox: float = r["ax"] * s
	var oy: float = r["ay"] * s
	if flip:
		return Transform2D(Vector2(-w, 0), Vector2(0, h), pos + Vector2(ox, -oy))
	return Transform2D(Vector2(w, 0), Vector2(0, h), pos - Vector2(ox, oy))


func _make_mmi(parent: Node2D, nm: String, n: int) -> MultiMesh:
	var mmi := MultiMeshInstance2D.new()
	mmi.name = nm
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = SoldierRenderer.unit_quad()
	mm.instance_count = n
	mm.custom_aabb = AABB(Vector3(-400, -400, -1), Vector3(map.size.x + 800, map.size.y + 800, 2))
	mmi.multimesh = mm
	mmi.texture = _atlas
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	mat.set_shader_parameter("atlas", _atlas)
	mmi.material = mat
	parent.add_child(mmi)
	return mm


func _sway(id: String, kind: String) -> float:
	match kind:
		"tree": return 0.11
		"bamboo": return 0.2
		"bush": return 0.05
		"camp": return 0.16 if id == "camp_1" or id == "camp_2" else 0.0
	return 0.0


func _shadow_for(pr: Dictionary, r: Dictionary) -> Array:
	# [centre, size, alpha]; light from the top-left, so shadows fall right and slightly down
	var s: float = pr["s"]
	var w: float = r["w"] * s
	var h: float = r["h"] * s
	var p: Vector2 = pr["pos"]
	match r["kind"]:
		"tree", "bamboo":
			var cw := w * (0.5 if r["kind"] == "tree" else 0.6)
			return [p + Vector2(h * 0.16, 2.0), Vector2(cw * 1.1, cw * 0.5), 0.42]
		"house", "shrine":
			if pr["id"] in ["shrine_2", "shrine_3"]:
				return [p + Vector2(6, 0), Vector2(26, 12) * s, 0.4]
			if pr["id"] == "shrine_1":
				return [p + Vector2(w * 0.3, 0), Vector2(w * 0.85, 22.0 * s), 0.3]
			return [p + Vector2(w * 0.07, -h * 0.08), Vector2(w * 0.95, w * 0.42), 0.45]
		"camp":
			if pr["id"] in ["camp_1", "camp_2"]:
				return [p + Vector2(8, 1), Vector2(22, 9) * s, 0.4]
			return [p + Vector2(w * 0.08, -h * 0.05), Vector2(w * 0.95, w * 0.4), 0.38]
		"rock":
			return [p + Vector2(w * 0.08, -2), Vector2(w * 0.85, w * 0.32), 0.38]
		"bush":
			return [p + Vector2(3, -1), Vector2(w * 0.75, w * 0.3), 0.3]
	return [p + Vector2(w * 0.05, -2), Vector2(w * 0.8, maxf(10.0, w * 0.18)), 0.28]


func _build() -> void:
	var low: Array = []
	var tall: Array = []
	for pr in placed:
		(tall if is_tall(pr["id"]) else low).append(pr)
	low.sort_custom(func(a, b): return a["pos"].y < b["pos"].y)
	tall.sort_custom(func(a, b): return a["pos"].y < b["pos"].y)

	var sh: Dictionary = _reg["_shadow"]
	var mm_s := _make_mmi(self, "PropShadows", placed.size())
	for k in placed.size():
		var pr: Dictionary = placed[k]
		var d := _shadow_for(pr, _reg[pr["id"]])
		var c: Vector2 = d[0]
		var sz: Vector2 = d[1]
		mm_s.set_instance_transform_2d(k, Transform2D(Vector2(sz.x, 0), Vector2(0, sz.y), c - sz * 0.5))
		mm_s.set_instance_custom_data(k, _uv(sh))
		mm_s.set_instance_color(k, Color(1, 0, 0, d[2]))

	var mm_l := _make_mmi(self, "PropsLow", low.size())
	for k in low.size():
		_write(mm_l, k, low[k], 1.0)

	canopy = Node2D.new()
	canopy.name = "PropCanopy"
	_tall_mm = _make_mmi(canopy, "PropsTall", tall.size())
	_tall_rect.clear()
	_tall_col.clear()
	_tall_fade.resize(tall.size())
	_tall_fade.fill(255)
	for k in tall.size():
		var pr: Dictionary = tall[k]
		_tall_col.append(_write(_tall_mm, k, pr, 1.0))
		var r: Dictionary = _reg[pr["id"]]
		var s: float = pr["s"]
		var vw: float = r["w"] * s * (0.55 if r["kind"] in ["tree", "bamboo"] else 0.8)
		var vh: float = r["h"] * s * 0.85
		var p: Vector2 = pr["pos"]
		_tall_rect.append(Rect2(p.x - vw * 0.5, p.y - vh, vw, vh + 34.0))


static func _uv(r: Dictionary) -> Color:
	var uv: Rect2 = r["uv"]
	return Color(uv.position.x, uv.position.y, uv.size.x, uv.size.y)


func _write(mm: MultiMesh, k: int, pr: Dictionary, alpha: float) -> Color:
	var r: Dictionary = _reg[pr["id"]]
	mm.set_instance_transform_2d(k, _xform(r, pr["pos"], pr["s"], pr["flip"]))
	mm.set_instance_custom_data(k, _uv(r))
	var col := Color(clampf(pr["b"], 0.0, 1.0), _sway(pr["id"], r["kind"]), float(pr["clan"]), alpha)
	mm.set_instance_color(k, col)
	return col


## Canopy fade: tall props go see-through while soldiers stand under or just in front of them.
## A slice of the props is checked each frame so the cost stays flat.
func _process(_delta: float) -> void:
	if sim == null or _tall_mm == null or _tall_rect.is_empty():
		return
	var n := _tall_rect.size()
	var chunk := maxi(1, n / 8 + 1)
	for q in chunk:
		var k := _cursor
		_cursor = (_cursor + 1) % n
		var under := sim.any_soldier_in(_tall_rect[k])
		var target := 90 if under else 255
		var cur := int(_tall_fade[k])
		if cur != target:
			cur = move_toward(cur, target, 55) as int
			_tall_fade[k] = cur
			var c := _tall_col[k]
			c.a = cur / 255.0
			_tall_mm.set_instance_color(k, c)

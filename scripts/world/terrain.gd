class_name Terrain
extends Node2D
## Battle ground: rasterises a MapDef into gameplay grids (speed, height, material) and draws
## the ground with a texture-driven splat shader (scripts/render/shaders/terrain_splat.gdshader).
##
## Textures are loaded from assets/terrain/<name>.png (or tex_<name>.png). Missing ones fall
## back to procedural greyscale noise tinted with the Art Bible palette, so dropping real
## textures in needs no code change.
##
## Gameplay queries: speed_mult(p), is_water(p), is_forest(p), height(p), find_route(a, b).

const CELL := 16.0
enum Mat { GRASS, ROAD, FOREST, WATER, FORD, BANK, VILLAGE, PADDY }

## Splat materials in channel order: splat0 = rgba(0..3), splat1 = rgba(4..7).
const MATERIALS := ["grass", "meadow", "dirt", "forestfloor", "riverbed", "sand", "mud", "paddy"]
const PLACEHOLDER_TINTS := {
	"grass": Color("#5F7139"), "meadow": Color("#9C9455"), "dirt": Color("#8A6A45"),
	"forestfloor": Color("#3F4A2A"), "riverbed": Color("#3E5A63"), "sand": Color("#9A917C"),
	"mud": Color("#6B5034"), "paddy": Color("#6E8A55"),
}

var map: MapDef
var size := Vector2.ZERO
var cell := CELL
var grid_w := 0
var grid_h := 0
var mat_grid := PackedByteArray()
var speed_grid := PackedFloat32Array()
var height_grid := PackedFloat32Array()
var forest_grid := PackedFloat32Array()
var ford_mask := PackedFloat32Array()   # 0..1 shallow-crossing mask for the shader (height_tex.a)
var trees := PackedVector2Array()
var tree_scale := PackedFloat32Array()

var splat0: Image
var splat1: Image
var height_img: Image
var _mat: ShaderMaterial
var _white: ImageTexture


func build(p_map: MapDef) -> void:
	map = p_map
	size = map.size
	grid_w = int(ceil(size.x / CELL))
	grid_h = int(ceil(size.y / CELL))
	var N := grid_w * grid_h
	mat_grid.resize(N); mat_grid.fill(Mat.GRASS)
	speed_grid.resize(N); speed_grid.fill(1.0)
	height_grid.resize(N); height_grid.fill(0.0)
	forest_grid.resize(N); forest_grid.fill(0.0)
	var w := PackedFloat32Array(); w.resize(N * 8); w.fill(0.0)
	var water_depth := PackedFloat32Array(); water_depth.resize(N); water_depth.fill(0.0)
	ford_mask.resize(N); ford_mask.fill(0.0)

	var noise := FastNoiseLite.new()
	noise.seed = map.seed_value
	noise.frequency = 0.0016
	noise.fractal_octaves = 3
	var noise2 := FastNoiseLite.new()
	noise2.seed = map.seed_value + 11
	noise2.frequency = 0.006

	# base: grass / meadow mix
	for gy in grid_h:
		for gx in grid_w:
			var k := gy * grid_w + gx
			var wx := (gx + 0.5) * CELL
			var wy := (gy + 0.5) * CELL
			var m := smoothstep(-0.15, 0.35, noise.get_noise_2d(wx, wy))
			w[k * 8 + 0] = 1.0 - m
			w[k * 8 + 1] = m

	# hills
	for h in map.hills:
		var c: Vector2 = h["c"]
		var r: float = h["r"]
		var hh: float = h["h"]
		_for_cells_in(Rect2(c - Vector2(r, r) * 1.6, Vector2(r, r) * 3.2), func(k: int, p: Vector2) -> void:
			var d := p.distance_to(c) / r
			height_grid[k] += hh * exp(-d * d * 1.6))

	# paddies / villages
	for pr in map.paddies:
		_for_cells_in(pr, func(k: int, _p: Vector2) -> void:
			_set_w(w, k, 7, 1.0)
			mat_grid[k] = Mat.PADDY)
	for vr in map.villages:
		_for_cells_in(vr.grow(40.0), func(k: int, p: Vector2) -> void:
			var inside := vr.has_point(p)
			var e := 1.0 if inside else 0.0
			if not inside:
				var dx := maxf(maxf(vr.position.x - p.x, 0.0), p.x - vr.end.x)
				var dy := maxf(maxf(vr.position.y - p.y, 0.0), p.y - vr.end.y)
				e = clampf(1.0 - sqrt(dx * dx + dy * dy) / 40.0, 0.0, 1.0)
			e *= 0.55 + 0.45 * absf(noise2.get_noise_2d(p.x, p.y) * 2.0)
			if e > 0.05:
				_set_w(w, k, 6, maxf(w[k * 8 + 6], e))
			if inside:
				mat_grid[k] = Mat.VILLAGE)

	# ground patches (visual only): soft noisy blobs of any splat material, e.g. sandy ford
	# beaches, trampled camp dirt, mud at a crossing. {"c", "r", "mat": MATERIALS name, "a": 0..1}
	for gp in map.ground_patches:
		var gc: Vector2 = gp["c"]
		var gr: float = gp["r"]
		var ch := MATERIALS.find(gp.get("mat", "dirt"))
		var ga: float = gp.get("a", 0.85)
		_for_cells_in(Rect2(gc - Vector2(gr, gr) * 1.3, Vector2(gr, gr) * 2.6), func(k: int, p: Vector2) -> void:
			var d := p.distance_to(gc) + noise2.get_noise_2d(p.x * 1.3, p.y * 1.3) * gr * 0.35
			var e := clampf((gr - d) / (gr * 0.45), 0.0, 1.0) * ga
			if ch >= 0 and e > w[k * 8 + ch]:
				_set_w(w, k, ch, e))

	# forests
	for f in map.forests:
		var fc: Vector2 = f["c"]
		var fr: float = f["r"]
		_for_cells_in(Rect2(fc - Vector2(fr, fr) * 1.3, Vector2(fr, fr) * 2.6), func(k: int, p: Vector2) -> void:
			var d := p.distance_to(fc) + noise2.get_noise_2d(p.x, p.y) * 70.0
			var e := clampf((fr - d) / 60.0, 0.0, 1.0)
			if e > forest_grid[k]:
				forest_grid[k] = e
				_set_w(w, k, 3, e)
				if e > 0.5:
					mat_grid[k] = Mat.FOREST)

	# roads
	for road in map.roads:
		_stamp_polyline(road, map.road_width * 0.5 + 24.0, func(k: int, d: float) -> void:
			var e := clampf((map.road_width * 0.5 + 8.0 - d) / 16.0, 0.0, 1.0)
			if e > w[k * 8 + 2]:
				_set_w(w, k, 2, e)
				if e > 0.5 and mat_grid[k] != Mat.VILLAGE:
					mat_grid[k] = Mat.ROAD)

	# river (deep water + banks), then fords
	var half := map.river_width * 0.5
	_stamp_polyline(map.river, half + 40.0, func(k: int, d: float) -> void:
		var p := Vector2((k % grid_w + 0.5) * CELL, (k / grid_w + 0.5) * CELL)
		var dn := d + noise2.get_noise_2d(p.x * 1.5, p.y * 1.5) * 14.0
		var bank := clampf((half + 30.0 - dn) / 22.0, 0.0, 1.0)
		var water := clampf((half - dn) / 14.0, 0.0, 1.0)
		if bank > w[k * 8 + 5]:
			_set_w(w, k, 5, bank)
		if water > water_depth[k]:
			water_depth[k] = water
			_set_w(w, k, 4, water)
		if water > 0.5:
			mat_grid[k] = Mat.WATER
			forest_grid[k] = 0.0
		elif bank > 0.5 and mat_grid[k] != Mat.WATER:
			mat_grid[k] = Mat.BANK)
	for fd in map.fords:
		var fa: Vector2 = fd["a"]
		var fb: Vector2 = fd["b"]
		var fw: float = fd["width"]
		_stamp_polyline(PackedVector2Array([fa, fb]), fw * 0.5 + 60.0, func(k: int, d: float) -> void:
			# ford mask (height_img alpha): 1 on the causeway centre line, 0 past the wet-sand fringe
			ford_mask[k] = maxf(ford_mask[k], clampf((fw * 0.5 + 50.0 - d) / (fw * 0.5 + 50.0), 0.0, 1.0))
			var e := clampf((fw * 0.5 - d) / 20.0, 0.0, 1.0)
			var ev := clampf((fw * 0.5 + 30.0 - d) / 90.0, 0.0, 1.0)   # softer visual shoaling
			if water_depth[k] > 0.0 and ev > 0.0:
				water_depth[k] = minf(water_depth[k], 1.0 - ev * 0.72)
				_set_w(w, k, 5, maxf(w[k * 8 + 5], ev * 0.6))
				if mat_grid[k] == Mat.WATER and e > 0.5:
					mat_grid[k] = Mat.FORD)

	# derive speed
	for k in N:
		var s := 1.0
		match mat_grid[k]:
			Mat.ROAD: s = 1.15
			Mat.FOREST: s = 0.7
			Mat.WATER: s = 0.0
			Mat.FORD: s = 0.55
			Mat.BANK: s = 0.85
			Mat.VILLAGE: s = 0.9
			Mat.PADDY: s = 0.6
		speed_grid[k] = s

	_build_images(w, water_depth)
	_place_trees()
	_setup_material()
	queue_redraw()


func _set_w(w: PackedFloat32Array, k: int, ch: int, v: float) -> void:
	# assigning a channel scales the others down so the total stays ~1
	var b := k * 8
	var other := 0.0
	for c in 8:
		if c != ch:
			other += w[b + c]
	var keep := 1.0 - v
	if other > 0.0:
		var s := keep / other
		for c in 8:
			if c != ch:
				w[b + c] = w[b + c] * s
	w[b + ch] = v


func _for_cells_in(rect: Rect2, fn: Callable) -> void:
	var x0 := clampi(int(rect.position.x / CELL), 0, grid_w - 1)
	var x1 := clampi(int(rect.end.x / CELL), 0, grid_w - 1)
	var y0 := clampi(int(rect.position.y / CELL), 0, grid_h - 1)
	var y1 := clampi(int(rect.end.y / CELL), 0, grid_h - 1)
	for gy in range(y0, y1 + 1):
		for gx in range(x0, x1 + 1):
			fn.call(gy * grid_w + gx, Vector2((gx + 0.5) * CELL, (gy + 0.5) * CELL))


## Calls fn(cell, distance) for every cell within `reach` of the polyline (min distance only).
func _stamp_polyline(pl: PackedVector2Array, reach: float, fn: Callable) -> void:
	var dist := {}
	for s in pl.size() - 1:
		var a := pl[s]
		var b := pl[s + 1]
		var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2(reach, reach)
		var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2(reach, reach)
		var x0 := clampi(int(lo.x / CELL), 0, grid_w - 1)
		var x1 := clampi(int(hi.x / CELL), 0, grid_w - 1)
		var y0 := clampi(int(lo.y / CELL), 0, grid_h - 1)
		var y1 := clampi(int(hi.y / CELL), 0, grid_h - 1)
		for gy in range(y0, y1 + 1):
			for gx in range(x0, x1 + 1):
				var p := Vector2((gx + 0.5) * CELL, (gy + 0.5) * CELL)
				var q := Geometry2D.get_closest_point_to_segment(p, a, b)
				var d := p.distance_to(q)
				if d <= reach:
					var k := gy * grid_w + gx
					if d < dist.get(k, INF):
						dist[k] = d
	for k in dist:
		fn.call(k, dist[k])


func _build_images(w: PackedFloat32Array, water_depth: PackedFloat32Array) -> void:
	var N := grid_w * grid_h
	var b0 := PackedByteArray(); b0.resize(N * 4)
	var b1 := PackedByteArray(); b1.resize(N * 4)
	var bh := PackedByteArray(); bh.resize(N * 4)
	for k in N:
		var o := k * 8
		var tot := 0.0
		for c in 8:
			tot += w[o + c]
		tot = maxf(tot, 0.0001)
		for c in 4:
			b0[k * 4 + c] = int(clampf(w[o + c] / tot, 0.0, 1.0) * 255.0)
			b1[k * 4 + c] = int(clampf(w[o + 4 + c] / tot, 0.0, 1.0) * 255.0)
		bh[k * 4 + 0] = int(clampf(height_grid[k] / 64.0, 0.0, 1.0) * 255.0)
		bh[k * 4 + 1] = int(clampf(water_depth[k], 0.0, 1.0) * 255.0)
		bh[k * 4 + 2] = int(clampf(forest_grid[k], 0.0, 1.0) * 255.0)
		bh[k * 4 + 3] = int(clampf(ford_mask[k], 0.0, 1.0) * 255.0)
	splat0 = Image.create_from_data(grid_w, grid_h, false, Image.FORMAT_RGBA8, b0)
	splat1 = Image.create_from_data(grid_w, grid_h, false, Image.FORMAT_RGBA8, b1)
	height_img = Image.create_from_data(grid_w, grid_h, false, Image.FORMAT_RGBA8, bh)


func _place_trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = map.seed_value + 3
	trees = PackedVector2Array()
	tree_scale = PackedFloat32Array()
	var step := 44.0
	var y := step * 0.5
	while y < size.y:
		var x := step * 0.5
		while x < size.x:
			var p := Vector2(x, y) + Vector2(rng.randf_range(-16, 16), rng.randf_range(-16, 16))
			var f := forest_value(p)
			if f > 0.55 and rng.randf() < f * 0.95:
				trees.append(p)
				tree_scale.append(rng.randf_range(0.8, 1.2))
			elif f < 0.05 and mat_grid[_k(p)] == Mat.GRASS and rng.randf() < 0.0025:
				trees.append(p)   # lone field trees
				tree_scale.append(rng.randf_range(0.9, 1.25))
			x += step
		y += step


func _load_tex(name: String) -> Texture2D:
	for path in ["res://assets/terrain/%s.png" % name, "res://assets/terrain/tex_%s.png" % name]:
		if ResourceLoader.exists(path):
			var t = load(path)
			if t is Texture2D:
				return t
		if FileAccess.file_exists(path):
			var img := Image.load_from_file(ProjectSettings.globalize_path(path))
			if img != null and not img.is_empty():
				img.generate_mipmaps()
				return ImageTexture.create_from_image(img)
	return null


func _placeholder_tex(seed_off: int, freq: float) -> Texture2D:
	var nz := FastNoiseLite.new()
	nz.seed = 900 + seed_off
	nz.frequency = freq
	nz.fractal_octaves = 4
	var img := nz.get_seamless_image(256, 256, false, false, 0.1, true)
	img.convert(Image.FORMAT_RGBA8)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _setup_material() -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://scripts/render/shaders/terrain_splat.gdshader")
	for q in MATERIALS.size():
		var nm: String = MATERIALS[q]
		var t := _load_tex(nm)
		var placeholder := t == null
		if placeholder:
			t = _placeholder_tex(q, 0.02 + 0.006 * q)
		_mat.set_shader_parameter("tex_%d" % q, t)
		var tint: Color = PLACEHOLDER_TINTS[nm] if placeholder else Color.WHITE
		_mat.set_shader_parameter("tint_%d" % q, tint)
		_mat.set_shader_parameter("placeholder_%d" % q, 1.0 if placeholder else 0.0)
	_mat.set_shader_parameter("splat0", ImageTexture.create_from_image(splat0))
	_mat.set_shader_parameter("splat1", ImageTexture.create_from_image(splat1))
	_mat.set_shader_parameter("height_tex", ImageTexture.create_from_image(height_img))
	var mn := FastNoiseLite.new()
	mn.seed = map.seed_value + 5
	mn.frequency = 0.01
	mn.fractal_octaves = 4
	var nimg := mn.get_seamless_image(256, 256, false, false, 0.1, true)
	nimg.convert(Image.FORMAT_RGBA8)
	_mat.set_shader_parameter("noise_tex", ImageTexture.create_from_image(nimg))
	_mat.set_shader_parameter("map_size", size)
	_mat.set_shader_parameter("grid_size", Vector2(grid_w, grid_h))
	material = _mat


func _draw() -> void:
	if splat0 == null:
		return
	# The shader reads its own textures; the rect just provides UVs (0..1) over the map.
	if _white == null:
		var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_white = ImageTexture.create_from_image(img)
	draw_texture_rect(_white, Rect2(Vector2.ZERO, size), false)


# =====================================================================================
#  Gameplay queries
# =====================================================================================

func _k(p: Vector2) -> int:
	var gx := clampi(int(p.x / CELL), 0, grid_w - 1)
	var gy := clampi(int(p.y / CELL), 0, grid_h - 1)
	return gy * grid_w + gx


func speed_mult(p: Vector2) -> float:
	return speed_grid[_k(p)]


func is_water(p: Vector2) -> bool:
	return mat_grid[_k(p)] == Mat.WATER


func is_ford(p: Vector2) -> bool:
	return mat_grid[_k(p)] == Mat.FORD


func is_forest(p: Vector2) -> bool:
	return forest_grid[_k(p)] > 0.5


func forest_value(p: Vector2) -> float:
	return forest_grid[_k(p)]


func height(p: Vector2) -> float:
	return height_grid[_k(p)]


func material_at(p: Vector2) -> int:
	return mat_grid[_k(p)]


func segment_blocked(a: Vector2, b: Vector2) -> bool:
	var L := a.distance_to(b)
	var steps := int(L / 12.0) + 1
	for s in steps + 1:
		if is_water(a.lerp(b, float(s) / steps)):
			return true
	return false


## Route for a formation anchor from a to b. Returns {"points": PackedVector2Array,
## "narrow": PackedFloat32Array} where narrow[i] > 0 caps the frontage width (px) on the leg
## that ends at points[i] (fords make regiments form a column).
func find_route(a: Vector2, b: Vector2) -> Dictionary:
	if not segment_blocked(a, b) or map == null or map.fords.is_empty():
		return {"points": PackedVector2Array([b]), "narrow": PackedFloat32Array([0.0])}
	var best: Dictionary = {}
	var best_cost := INF
	for fd in map.fords:
		var fa: Vector2 = fd["a"]
		var fb: Vector2 = fd["b"]
		var near := fa if a.distance_to(fa) + fb.distance_to(b) < a.distance_to(fb) + fa.distance_to(b) else fb
		var far := fb if near == fa else fa
		var cost := a.distance_to(near) + near.distance_to(far) + far.distance_to(b)
		if cost < best_cost:
			best_cost = cost
			best = {"near": near, "far": far, "width": fd["width"]}
	var near2: Vector2 = best["near"]
	var far2: Vector2 = best["far"]
	var fw: float = best["width"] * 0.8
	var axis := (far2 - near2).normalized()
	var pre := near2 - axis * 90.0
	var post := far2 + axis * 70.0
	var pts := PackedVector2Array()
	var nar := PackedFloat32Array()
	if a.distance_to(pre) > 30.0 and (pre - a).dot(axis) > -400.0:
		pts.append(pre); nar.append(0.0)
	pts.append(near2); nar.append(fw)
	pts.append(far2); nar.append(fw)
	pts.append(post); nar.append(fw)
	pts.append(b); nar.append(0.0)
	return {"points": pts, "narrow": nar}

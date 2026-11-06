class_name FxTextures
extends RefCounted
## Builds the shared FX Texture2DArray (premultiplied alpha, mipmapped) from assets/fx/*.png
## plus a few procedural layers. Layer indices are the L_* constants below.

const RES := 256
const L_SMOKE := 0     # 0..3
const L_FLASH := 4     # 4..5
const L_BLOOD := 6     # 6..9
const L_DOT := 10
const L_MUD := 11
const L_ARROW := 12
const L_GRASS := 13    # 13..14
const L_SCUFF := 15


static func build_array() -> Texture2DArray:
	var imgs: Array[Image] = []
	for nm in ["smoke_0", "smoke_1", "smoke_2", "smoke_3", "flash_0", "flash_1", "blood_0", "blood_1", "blood_2", "blood_3"]:
		imgs.append(_load(nm))
	imgs.append(_soft_dot())
	imgs.append(_blob(11, 0.55, 0.9))
	imgs.append(_stuck_arrow())
	imgs.append(_grass_tuft(3))
	imgs.append(_grass_tuft(17))
	imgs.append(_blob(29, 0.75, 0.6))
	for im in imgs:
		im.premultiply_alpha()
		im.generate_mipmaps()
	var arr := Texture2DArray.new()
	arr.create_from_images(imgs)
	return arr


static func _blank() -> Image:
	var im := Image.create(RES, RES, false, Image.FORMAT_RGBA8)
	im.fill(Color(1, 1, 1, 0))
	return im


static func _load(nm: String) -> Image:
	var path := "res://assets/fx/%s.png" % nm
	var src: Image = null
	if ResourceLoader.exists(path):
		var t: Texture2D = load(path)
		if t != null:
			src = t.get_image()
	if src == null:
		return _soft_dot()
	if src.is_compressed():
		src.decompress()
	src.convert(Image.FORMAT_RGBA8)
	# stretch into a padded square; quads restore the aspect per kind
	var inner := int(RES * 0.9)
	src.resize(inner, inner, Image.INTERPOLATE_LANCZOS)
	var im := _blank()
	# premultiplied later, so transparent texels filter cleanly whatever their rgb
	im.blit_rect(src, Rect2i(0, 0, inner, inner), Vector2i((RES - inner) / 2, (RES - inner) / 2))
	return im


static func _soft_dot() -> Image:
	var im := _blank()
	for y in RES:
		for x in RES:
			var d := Vector2(x + 0.5 - RES * 0.5, y + 0.5 - RES * 0.5) / (RES * 0.5)
			var a := exp(-d.length_squared() * 5.0) * (1.0 - smoothstep(0.85, 1.0, d.length()))
			im.set_pixel(x, y, Color(1, 1, 1, a))
	return im


## Irregular soft blob (mud / scuff), alpha from radial falloff broken up by fbm noise.
static func _blob(seed_v: int, edge: float, density: float) -> Image:
	var im := _blank()
	var nz := FastNoiseLite.new()
	nz.seed = seed_v
	nz.frequency = 0.035
	nz.fractal_octaves = 4
	for y in RES:
		for x in RES:
			var d := Vector2(x + 0.5 - RES * 0.5, y + 0.5 - RES * 0.5) / (RES * 0.5)
			var r := d.length() + nz.get_noise_2d(x, y) * 0.35
			var a := (1.0 - smoothstep(edge * 0.5, edge + 0.3, r)) * density
			a *= 0.75 + 0.25 * nz.get_noise_2d(x * 3.1, y * 3.1)
			var shade := 0.85 + 0.15 * nz.get_noise_2d(x * 2.0 + 99.0, y * 2.0)
			im.set_pixel(x, y, Color(shade, shade, shade, clampf(a, 0.0, 1.0)))
	return im


static func _line(im: Image, a: Vector2, b: Vector2, w: float, col: Color) -> void:
	var L := a.distance_to(b)
	var steps := int(L * 2.0) + 1
	var r := int(ceil(w))
	for s in steps + 1:
		var p := a.lerp(b, float(s) / steps)
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var q := Vector2(dx, dy)
				var cov := clampf(w - q.length() + 0.5, 0.0, 1.0)
				var px := int(p.x) + dx
				var py := int(p.y) + dy
				if cov <= 0.0 or px < 0 or py < 0 or px >= RES or py >= RES:
					continue
				var o := im.get_pixel(px, py)
				if o.a < cov * col.a:
					im.set_pixel(px, py, Color(col.r, col.g, col.b, cov * col.a))


## Spent arrow stuck in the ground (3/4 view): shaft leaning back, white fletching, ground shadow.
static func _stuck_arrow() -> Image:
	var im := _blank()
	var tip := Vector2(RES * 0.5, RES * 0.78)
	var tail := Vector2(RES * 0.26, RES * 0.16)
	_line(im, tip + Vector2(6, 2), tip + Vector2(70, 10), 5.0, Color(0.05, 0.04, 0.03, 0.35))
	_line(im, tip, tail, 4.5, Color(0.30, 0.20, 0.11, 1.0))
	var dirv := (tail - tip).normalized()
	var perp := Vector2(-dirv.y, dirv.x)
	for k in 3:
		var f := tail - dirv * (6.0 + k * 9.0)
		_line(im, f, f + perp * 13.0 + dirv * 9.0, 3.0, Color(0.93, 0.91, 0.86, 1.0))
		_line(im, f, f - perp * 13.0 + dirv * 9.0, 3.0, Color(0.85, 0.83, 0.78, 1.0))
	_line(im, tip + Vector2(-8, 3), tip + Vector2(10, 3), 6.0, Color(0.15, 0.11, 0.07, 0.5))
	return im


## Grass tuft: tapered blades fanning out from a dark base (top-left lit).
static func _grass_tuft(seed_v: int) -> Image:
	var im := _blank()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var base := Vector2(RES * 0.5, RES * 0.92)
	for k in 26:
		var ang := rng.randf_range(-0.75, 0.75)
		var length := rng.randf_range(0.45, 0.8) * RES
		var root := base + Vector2(rng.randf_range(-40, 40), rng.randf_range(-6, 6))
		var tip := root + Vector2(sin(ang), -cos(ang)) * length
		var lit := rng.randf()
		var col := Color(0.36, 0.46, 0.21).lerp(Color(0.66, 0.68, 0.36), lit * 0.8)
		var mid := root.lerp(tip, 0.5) + Vector2(rng.randf_range(-6, 6), 0)
		_line(im, root, mid, 4.0, col.darkened(0.25))
		_line(im, mid, tip, 2.2, col)
	return im

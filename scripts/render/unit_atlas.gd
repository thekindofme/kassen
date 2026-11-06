class_name UnitAtlas
extends RefCounted
## Loads assets/atlas/units.png + units.json (contract in docs/TECH.md) into a flat frame table
## for the MultiMesh renderer. If the atlas (or some unit/team/anim in it) is missing, a
## procedural placeholder (coloured capsule soldiers) is generated behind the same JSON
## contract and packed into the same texture, so swapping in real art needs no code change.

const JSON_PATH := "res://assets/atlas/units.json"
const PNG_PATH := "res://assets/atlas/units.png"
const FPS_ACTION := 12.0
const FPS_DEATH := 12.0

var texture: Texture2D
var data: Dictionary = {}          # parsed JSON (merged with placeholder entries)
var scale := 1.0
var used_placeholder := false
var placeholder_parts: Array[String] = []

## 8 floats per frame: u0, v0, uw, vh (normalised UV rect), w, h, ax, ay (world px)
var frames := PackedFloat32Array()
## per (unit*2 + team)*4 + anim_slot
var anim_start := PackedInt32Array()
var anim_count := PackedInt32Array()
var unit_height := PackedFloat32Array()   # idle frame-0 height above the feet, world px


static func slot_index(ut: int, team: int, anim: int) -> int:
	return (ut * 2 + team) * 4 + anim


func load_or_generate() -> void:
	var img: Image = null
	if FileAccess.file_exists(JSON_PATH) and (FileAccess.file_exists(PNG_PATH) or ResourceLoader.exists(PNG_PATH)):
		var txt := FileAccess.get_file_as_string(JSON_PATH)
		var parsed = JSON.parse_string(txt)
		if parsed is Dictionary and parsed.has("units"):
			data = parsed
			img = _load_image(PNG_PATH)
	if img == null:
		data = {"scale": 1.5, "units": {}}
	# find missing entries
	var missing: Array = []   # [unit, team, anim]
	for u in UnitTypes.KEYS:
		var ut := UnitTypes.index_of(u)
		for tm in UnitTypes.TEAM_KEYS:
			for a in 4:
				var ak := UnitTypes.anim_key(ut, a)
				var units: Dictionary = data["units"]
				var ok: bool = img != null and units.has(u) and units[u].has(tm) and units[u][tm].has(ak) and not units[u][tm][ak].is_empty()
				if not ok and img != null and tm == "mizuno" and units.has(u) and units[u].has("hino") and units[u]["hino"].has(ak):
					# real art for hino only: reuse it for mizuno rather than mixing in placeholders
					if not units[u].has("mizuno"):
						units[u]["mizuno"] = {}
					units[u]["mizuno"][ak] = units[u]["hino"][ak]
					ok = true
				if not ok:
					missing.append([u, tm, ak])
	if not missing.is_empty():
		used_placeholder = true
		var ph := _generate_placeholder(missing)
		var ph_img: Image = ph["image"]
		var ph_data: Dictionary = ph["data"]
		var real_scale: float = data.get("scale", 1.0) if img != null else ph_data["scale"]
		var y_off := 0
		if img != null:
			# rescale placeholder frames to the real atlas scale by shifting coords only (frame
			# sizes stay in their own pixels, so convert via per-frame scale factor)
			y_off = img.get_height()
			var combined := Image.create(maxi(img.get_width(), ph_img.get_width()), img.get_height() + ph_img.get_height(), false, Image.FORMAT_RGBA8)
			img.convert(Image.FORMAT_RGBA8)
			combined.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i.ZERO)
			combined.blit_rect(ph_img, Rect2i(Vector2i.ZERO, ph_img.get_size()), Vector2i(0, y_off))
			img = combined
		else:
			img = ph_img
		data["scale"] = real_scale
		for m in missing:
			var u: String = m[0]
			var tm: String = m[1]
			var ak: String = m[2]
			var list: Array = ph_data["units"][u][tm][ak]
			var conv: Array = []
			for f in list:
				# frames keep their pixel rect; `sx` tells the table builder their own scale
				conv.append({"x": f["x"], "y": f["y"] + y_off, "w": f["w"], "h": f["h"], "ax": f["ax"], "ay": f["ay"], "s": ph_data["scale"]})
			var units2: Dictionary = data["units"]
			if not units2.has(u):
				units2[u] = {}
			if not units2[u].has(tm):
				units2[u][tm] = {}
			units2[u][tm][ak] = conv
			if not placeholder_parts.has(u):
				placeholder_parts.append(u)
	scale = float(data["scale"])
	img.generate_mipmaps()
	texture = ImageTexture.create_from_image(img)
	_build_table(img.get_width(), img.get_height())


func _load_image(path: String) -> Image:
	if ResourceLoader.exists(path):
		var t = load(path)
		if t is Texture2D:
			var im: Image = t.get_image()
			if im != null:
				if im.is_compressed():
					im.decompress()
				return im
	if FileAccess.file_exists(path):
		var im2 := Image.load_from_file(ProjectSettings.globalize_path(path))
		if im2 != null and not im2.is_empty():
			return im2
	return null


func _build_table(tw: int, th: int) -> void:
	frames = PackedFloat32Array()
	anim_start = PackedInt32Array(); anim_start.resize(UnitTypes.KEYS.size() * 2 * 4)
	anim_count = PackedInt32Array(); anim_count.resize(anim_start.size())
	unit_height = PackedFloat32Array(); unit_height.resize(UnitTypes.KEYS.size())
	var units: Dictionary = data["units"]
	var nf := 0
	for ut in UnitTypes.KEYS.size():
		var u: String = UnitTypes.KEYS[ut]
		for team in 2:
			var tm: String = UnitTypes.TEAM_KEYS[team]
			for a in 4:
				var ak := UnitTypes.anim_key(ut, a)
				var list: Array = units[u][tm][ak]
				var si := slot_index(ut, team, a)
				anim_start[si] = nf
				anim_count[si] = list.size()
				for f in list:
					var s: float = f.get("s", scale)
					var inv := 1.0 / s
					frames.append(float(f["x"]) / tw)
					frames.append(float(f["y"]) / th)
					frames.append(float(f["w"]) / tw)
					frames.append(float(f["h"]) / th)
					frames.append(float(f["w"]) * inv)
					frames.append(float(f["h"]) * inv)
					frames.append(float(f["ax"]) * inv)
					frames.append(float(f["ay"]) * inv)
					nf += 1
		var idle0 := anim_start[slot_index(ut, 0, 0)] * 8
		unit_height[ut] = frames[idle0 + 7]


# =====================================================================================
#  Procedural placeholder atlas
# =====================================================================================

const PH_SCALE := 1.5
const TEAM_COL := [[Color("#A3201E"), Color("#D4A23C"), Color("#1A1714")], [Color("#23356B"), Color("#D9D4C5"), Color("#14151C")]]
const SKIN := Color("#C99A72")
const WOOD := Color("#5A3B22")
const STEEL := Color("#B9BCC2")
var _clip := Rect2i()

func _generate_placeholder(missing: Array) -> Dictionary:
	# one row of 8 frames per missing (unit, team, anim)
	var rows: Array = []
	var width := 0
	var height := 0
	for m in missing:
		var mounted: bool = UnitTypes.STATS[m[0]]["mounted"]
		var fw := 104 if mounted else 72
		var fh := 100 if mounted else 72
		rows.append({"m": m, "fw": fw, "fh": fh, "y": height})
		height += fh
		width = maxi(width, fw * 8)
	var img := Image.create(maxi(width, 8), maxi(height, 8), false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var out := {"scale": PH_SCALE, "units": {}}
	for row in rows:
		var u: String = row["m"][0]
		var tm: String = row["m"][1]
		var ak: String = row["m"][2]
		var team := UnitTypes.TEAM_KEYS.find(tm)
		var fw: int = row["fw"]
		var fh: int = row["fh"]
		var list: Array = []
		for f in 8:
			var ox := f * fw
			var oy: int = row["y"]
			var ax := int(fw * 0.42)
			var ay := fh - 4
			_clip = Rect2i(ox, oy, fw, fh)
			_draw_figure(img, Vector2i(ox, oy), Vector2i(fw, fh), Vector2i(ax, ay), u, team, ak, f)
			list.append({"x": ox, "y": oy, "w": fw, "h": fh, "ax": ax, "ay": ay})
		var units: Dictionary = out["units"]
		if not units.has(u):
			units[u] = {}
		if not units[u].has(tm):
			units[u][tm] = {}
		units[u][tm][ak] = list
	return {"image": img, "data": out}


func _rect(img: Image, o: Vector2i, x: float, y: float, w: float, h: float, c: Color) -> void:
	var r := Rect2i(o.x + int(round(x)), o.y + int(round(y)), maxi(1, int(round(w))), maxi(1, int(round(h))))
	r = r.intersection(_clip)
	if r.size.x > 0 and r.size.y > 0:
		img.fill_rect(r, c)


func _ellipse(img: Image, o: Vector2i, cx: float, cy: float, rx: float, ry: float, c: Color) -> void:
	var y0 := int(floor(cy - ry))
	var y1 := int(ceil(cy + ry))
	for y in range(y0, y1 + 1):
		var t := (float(y) + 0.5 - cy) / ry
		if absf(t) > 1.0:
			continue
		var hw := rx * sqrt(1.0 - t * t)
		_rect(img, o, cx - hw, y, hw * 2.0, 1, c)


func _line(img: Image, o: Vector2i, a: Vector2, b: Vector2, w: float, c: Color) -> void:
	var L := a.distance_to(b)
	var steps := int(L) + 1
	for s in steps + 1:
		var p := a.lerp(b, float(s) / steps)
		_rect(img, o, p.x - w * 0.5, p.y - w * 0.5, w, w, c)


func _draw_figure(img: Image, o: Vector2i, fs: Vector2i, anchor: Vector2i, u: String, team: int, ak: String, f: int) -> void:
	var cols: Array = TEAM_COL[team]
	var main: Color = cols[0]
	var trim: Color = cols[1]
	var dark: Color = cols[2]
	var mounted: bool = UnitTypes.STATS[u]["mounted"]
	var ph := float(f) / 8.0 * TAU
	var fx := float(anchor.x)
	var fy := float(anchor.y)
	var death := ak == "death"
	var action := ak == "attack" or ak == "shoot" or ak == "fire"
	var walk := ak == "walk"
	var fall := clampf(float(f) / 6.0, 0.0, 1.0) if death else 0.0
	if mounted:
		var horse := Color("#5B3A26") if u == "cavalry" else Color("#D8D2C4")
		if death and fall > 0.6:
			_ellipse(img, o, fx, fy - 10, 34, 10, horse.darkened(0.15))
			_ellipse(img, o, fx + 26, fy - 8, 10, 7, horse)
			_rect(img, o, fx - 18, fy - 14, 26, 8, main)
			return
		var bob := sin(ph * 2.0) * 2.0 if walk else 0.0
		var by := fy - 30 + bob + fall * 12.0
		for leg in 4:
			var lx := fx - 22 + leg * 14
			var swing := sin(ph + leg * 1.6) * (8.0 if walk else 1.0)
			_line(img, o, Vector2(lx, by + 6), Vector2(lx + swing, fy), 4, horse.darkened(0.25))
		_ellipse(img, o, fx, by, 30, 12, horse)
		_line(img, o, Vector2(fx + 22, by - 4), Vector2(fx + 34, by - 22), 8, horse)
		_ellipse(img, o, fx + 37, by - 23, 8, 5, horse.darkened(0.1))
		_rect(img, o, fx - 18, by - 12, 30, 6, main)  # caparison
		# rider
		var ry := by - 14
		_rect(img, o, fx - 7, ry - 22, 14, 22, main)
		_rect(img, o, fx - 7, ry - 10, 14, 3, trim)
		_ellipse(img, o, fx, ry - 27, 5, 5, SKIN)
		_rect(img, o, fx - 6, ry - 34, 12, 5, dark)
		if u == "general":
			_line(img, o, Vector2(fx - 4, ry - 34), Vector2(fx - 10, ry - 44), 2, trim)
			_line(img, o, Vector2(fx + 4, ry - 34), Vector2(fx + 10, ry - 44), 2, trim)
		var thrust := sin(float(f) / 7.0 * PI) * 16.0 if action else 0.0
		if u == "cavalry":
			_line(img, o, Vector2(fx - 18 + thrust, ry - 12), Vector2(fx + 40 + thrust, ry - 22 + thrust * 0.4), 2, WOOD)
			_rect(img, o, fx + 38 + thrust, ry - 25 + thrust * 0.4, 6, 3, STEEL)
		else:
			_line(img, o, Vector2(fx + 6, ry - 16), Vector2(fx + 16 + thrust * 0.6, ry - 30 + thrust), 2, STEEL)
		return
	# --- infantry
	if death and fall > 0.7:
		_rect(img, o, fx - 18, fy - 8, 30, 8, main)
		_ellipse(img, o, fx + 15, fy - 5, 5, 5, SKIN)
		_rect(img, o, fx - 24, fy - 6, 8, 5, dark)
		return
	var lean := fall * 10.0
	var bob2 := absf(sin(ph)) * 2.0 if walk else sin(ph) * 0.6
	var hip := Vector2(fx - lean * 0.3, fy - 18 + bob2 * 0.5 + fall * 6.0)
	var stride := sin(ph) * 7.0 if walk else 0.0
	_line(img, o, hip + Vector2(-2, 0), Vector2(fx - 3 + stride, fy), 4, dark)
	_line(img, o, hip + Vector2(2, 0), Vector2(fx + 3 - stride, fy), 4, dark)
	var sh := hip + Vector2(lean, -18)
	_line(img, o, hip, sh, 11, main)
	_rect(img, o, hip.x - 5, hip.y - 9, 11, 2, trim)
	var head := sh + Vector2(1, -6)
	_ellipse(img, o, head.x, head.y, 4.5, 5, SKIN)
	if u == "samurai":
		_rect(img, o, head.x - 6, head.y - 7, 12, 5, dark)
		_line(img, o, Vector2(head.x - 2, head.y - 7), Vector2(head.x - 5, head.y - 13), 2, trim)
		_line(img, o, Vector2(head.x + 2, head.y - 7), Vector2(head.x + 5, head.y - 13), 2, trim)
	else:
		_ellipse(img, o, head.x, head.y - 5, 10, 3, main.darkened(0.2))   # jingasa
		_rect(img, o, head.x - 1, head.y - 8, 2, 2, trim)
	var swing := sin(float(f) / 7.0 * PI) if action else 0.0
	match u:
		"yari":
			var tip := sh + Vector2(30 + swing * 16, -30 + swing * 26) if not walk else sh + Vector2(26, -36)
			_line(img, o, sh + Vector2(-10 + swing * 8, 16 - swing * 4), tip, 2, WOOD)
			_line(img, o, tip, tip + (tip - sh).normalized() * 6, 2, STEEL)
		"yumi":
			var bx := sh.x + 8 + swing * 2
			for s in 9:
				var t := float(s) / 8.0
				var yy := sh.y - 20 + t * 34
				var xx := bx + sin(t * PI) * (6.0 + swing * 4)
				_rect(img, o, xx, yy, 2, 4, WOOD)
			_line(img, o, Vector2(bx, sh.y - 20), Vector2(bx - swing * 8, sh.y - 3), 1, Color(0.9, 0.9, 0.85))
			_line(img, o, Vector2(bx, sh.y + 14), Vector2(bx - swing * 8, sh.y - 3), 1, Color(0.9, 0.9, 0.85))
		"teppo":
			var aim := 1.0 if action else 0.0
			var g0 := sh + Vector2(-6, 6 - aim * 2)
			var g1 := sh + Vector2(26, 2 - aim * 6) if action else sh + Vector2(10, -24)
			_line(img, o, g0, g1, 3, WOOD)
			if action and (f == 3 or f == 4):
				_ellipse(img, o, g1.x + 4, g1.y, 5, 4, Color("#FFD27A"))
		"samurai":
			var a0 := sh + Vector2(6, 2)
			var dirv := Vector2(1, -1).rotated(swing * 2.2).normalized()
			_line(img, o, a0, a0 + dirv * 20, 2, STEEL)

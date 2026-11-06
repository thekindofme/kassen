class_name SoldierRenderer
extends Node2D
## Draws every soldier through MultiMeshes (docs/TECH.md "Rendering"):
##   corpses (append-only, under everything) → shadows → selection rings → living soldiers
##   (one y-sorted multimesh for all types and teams) → missiles/gun FX → sashimono banners.
## Reads BattleSim state only; never mutates it.

const DEATH_FPS := 12.0
const ACTION_FPS_MIN := 8.0
const TEAM_BANNER := [Color("#A3201E"), Color("#23356B")]
const TEAM_MON := [Color("#D4A23C"), Color("#D9D4C5")]

var sim: BattleSim
var atlas: UnitAtlas
var hover_reg: Regiment = null       # set by Commander
var show_labels := false
var team_player := 0

var mm_corpse: MultiMeshInstance2D
var mm_shadow: MultiMeshInstance2D
var mm_ring: MultiMeshInstance2D
var mm_living: MultiMeshInstance2D
var fx_layer: Node2D
var banner_layer: Node2D

var _buf := PackedFloat32Array()      # living: 16 floats/instance
var _sbuf := PackedFloat32Array()     # shadows: 8 floats/instance
var _rbuf := PackedFloat32Array()     # rings: 12 floats/instance
var _corpse_done := PackedByteArray()
var _corpse_n := 0
var _cap := 0
var last_update_ms := 0.0
var visible_count := 0


func setup(p_sim: BattleSim, p_atlas: UnitAtlas = null) -> void:
	sim = p_sim
	atlas = p_atlas
	if atlas == null:
		atlas = UnitAtlas.new()
		atlas.load_or_generate()
	var quad := unit_quad()
	var soldier_mat := ShaderMaterial.new()
	soldier_mat.shader = load("res://scripts/render/shaders/soldier.gdshader")
	soldier_mat.set_shader_parameter("atlas", atlas.texture)
	var shadow_mat := ShaderMaterial.new()
	shadow_mat.shader = load("res://scripts/render/shaders/shadow.gdshader")
	var ring_mat := ShaderMaterial.new()
	ring_mat.shader = load("res://scripts/render/shaders/ring.gdshader")
	mm_corpse = _make_mm("Corpses", quad, soldier_mat, true, true)
	mm_shadow = _make_mm("Shadows", quad, shadow_mat, false, false)
	mm_ring = _make_mm("Rings", quad, ring_mat, true, false)
	mm_living = _make_mm("Soldiers", quad, soldier_mat, true, true)
	fx_layer = _FxLayer.new()
	fx_layer.name = "MissileFX"
	fx_layer.r = self
	add_child(fx_layer)
	banner_layer = _BannerLayer.new()
	banner_layer.name = "Banners"
	banner_layer.r = self
	add_child(banner_layer)
	_ensure_capacity()


static func unit_quad() -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)])
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_FLAG_USE_2D_VERTICES)
	return m


func _make_mm(nm: String, mesh: Mesh, mat: Material, colors: bool, custom: bool) -> MultiMeshInstance2D:
	var mmi := MultiMeshInstance2D.new()
	mmi.name = nm
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = colors
	mm.use_custom_data = custom
	mm.mesh = mesh
	mmi.multimesh = mm
	mmi.material = mat
	add_child(mmi)
	return mmi


func _ensure_capacity() -> void:
	var need := maxi(sim.n, 1)
	if need <= _cap:
		return
	_cap = need
	var big := AABB(Vector3(-200, -200, -1), Vector3(sim.map_size.x + 400, sim.map_size.y + 400, 2))
	for mmi in [mm_living, mm_shadow, mm_ring]:
		mmi.multimesh.instance_count = _cap
		mmi.multimesh.visible_instance_count = 0
		mmi.multimesh.custom_aabb = big
	# corpses keep their contents: rebuild only when growing from empty
	mm_corpse.multimesh.instance_count = _cap
	mm_corpse.multimesh.visible_instance_count = 0
	mm_corpse.multimesh.custom_aabb = big
	_corpse_n = 0
	_corpse_done.resize(_cap)
	_corpse_done.fill(0)
	_buf.resize(_cap * 16)
	_sbuf.resize(_cap * 8)
	_rbuf.resize(_cap * 12)


func _process(_delta: float) -> void:
	if sim == null:
		return
	update_now()


func _view_rect() -> Rect2:
	var vp := get_viewport()
	if vp == null:
		return Rect2(Vector2(-1e6, -1e6), Vector2(2e6, 2e6))
	var ct := vp.get_canvas_transform()
	return (ct.affine_inverse() * Rect2(Vector2.ZERO, vp.get_visible_rect().size)).grow(90.0)


func view_zoom() -> float:
	var vp := get_viewport()
	return vp.get_canvas_transform().get_scale().x if vp != null else 1.0


func _frame_for(i: int, ut: int, tm: int, st: int, spd: float, action_t: PackedFloat32Array, dead_t: PackedFloat32Array,
		anim_t: PackedFloat32Array, actlen: PackedFloat32Array, a_start: PackedInt32Array, a_count: PackedInt32Array) -> int:
	# returns the frame index into atlas.frames
	var base := (ut * 2 + tm) * 4
	if st == BattleSim.DEAD:
		var si := base + UnitTypes.ANIM_DEATH
		return a_start[si] + mini(int(dead_t[i] * DEATH_FPS), a_count[si] - 1)
	var at := action_t[i]
	var alen := actlen[ut]
	if at < alen and (st == BattleSim.MELEE or st == BattleSim.SHOOT):
		var si2 := base + UnitTypes.ANIM_ACTION
		var cnt2 := a_count[si2]
		return a_start[si2] + mini(int(at / alen * cnt2), cnt2 - 1)
	var si3 := base + (UnitTypes.ANIM_WALK if spd > 6.0 else UnitTypes.ANIM_IDLE)
	return a_start[si3] + (int(anim_t[i]) % a_count[si3])


func update_now() -> void:
	var t0 := Time.get_ticks_usec()
	_ensure_capacity()
	var n := sim.n
	var a := sim.alpha
	var spos := sim.pos
	var ppos := sim.prev_pos
	var state := sim.state
	var utype := sim.utype
	var team := sim.team_of
	var facev := sim.face
	var vel := sim.vel
	var fr := atlas.frames
	var a_start := atlas.anim_start
	var a_count := atlas.anim_count
	var action_t := sim.action_t
	var dead_t := sim.dead_t
	var anim_t := sim.anim_t
	var actlen := sim.T_ACTLEN
	var trad := sim.T_RAD
	var view := _view_rect()
	var keys := PackedInt32Array()
	keys.resize(n)
	var count := 0
	for i in n:
		var st := state[i]
		if st == BattleSim.FLED:
			continue
		if st == BattleSim.DEAD:
			var si := UnitAtlas.slot_index(utype[i], team[i], UnitTypes.ANIM_DEATH)
			if dead_t[i] * DEATH_FPS >= float(a_count[si]):
				if _corpse_done[i] == 0:
					_add_corpse(i)
				continue
		var p := ppos[i].lerp(spos[i], a)
		if not view.has_point(p):
			continue
		keys[count] = ((int(p.y) + 1024) << 13) | i
		count += 1
	keys.resize(count)
	keys.sort()
	visible_count = count
	var nring := 0
	var regs := sim.regiments
	var pulse := 0.5 + 0.2 * sin(sim.time * 5.0)
	var flash := sim.flash
	var reg_of := sim.reg_of
	for k in count:
		var i := keys[k] & 8191
		var st := state[i]
		var ut := utype[i]
		var tm := team[i]
		var p := ppos[i].lerp(spos[i], a)
		var spd := vel[i].length()
		var fi := _frame_for(i, ut, tm, st, spd, action_t, dead_t, anim_t, actlen, a_start, a_count) * 8
		var w := fr[fi + 4]
		var h := fr[fi + 5]
		var ax := fr[fi + 6]
		var ay := fr[fi + 7]
		var fl := facev[i]
		var o := k * 16
		_buf[o] = w * fl
		_buf[o + 1] = 0.0
		_buf[o + 2] = 0.0
		_buf[o + 3] = p.x - ax * fl
		_buf[o + 4] = 0.0
		_buf[o + 5] = h
		_buf[o + 6] = 0.0
		_buf[o + 7] = p.y - ay
		var r: Regiment = regs[reg_of[i]]
		var sel := 0.0
		if r.selected:
			sel = pulse
		elif r == hover_reg:
			sel = 0.3
		_buf[o + 8] = clampf(flash[i] / 0.14, 0.0, 1.0) * 0.7 if st < BattleSim.DEAD else 0.0
		_buf[o + 9] = sel
		_buf[o + 10] = 0.8 if st == BattleSim.ROUT else 1.0
		_buf[o + 11] = 1.0
		_buf[o + 12] = fr[fi]
		_buf[o + 13] = fr[fi + 1]
		_buf[o + 14] = fr[fi + 2]
		_buf[o + 15] = fr[fi + 3]
		# shadow
		var rad := trad[ut]
		var sw := rad * 3.3
		var sh := rad * 1.15
		var so := k * 8
		var sa := 1.0 if st != BattleSim.DEAD else 0.0
		_sbuf[so] = sw * sa
		_sbuf[so + 1] = 0.0
		_sbuf[so + 2] = 0.0
		_sbuf[so + 3] = p.x - sw * 0.5 + 3.0
		_sbuf[so + 4] = 0.0
		_sbuf[so + 5] = sh * sa
		_sbuf[so + 6] = 0.0
		_sbuf[so + 7] = p.y - sh * 0.5 + 1.0
		# selection / hover ring
		if st != BattleSim.DEAD and (r.selected or r == hover_reg):
			var rw := rad * 3.6
			var rh := rad * 1.5
			var ro := nring * 12
			_rbuf[ro] = rw
			_rbuf[ro + 1] = 0.0
			_rbuf[ro + 2] = 0.0
			_rbuf[ro + 3] = p.x - rw * 0.5
			_rbuf[ro + 4] = 0.0
			_rbuf[ro + 5] = rh
			_rbuf[ro + 6] = 0.0
			_rbuf[ro + 7] = p.y - rh * 0.5
			var c := Color(1.0, 0.82, 0.35, 0.95)
			if r.team != team_player:
				c = Color(0.95, 0.25, 0.2, 0.9)
			elif not r.selected:
				c = Color(1, 1, 1, 0.5)
			_rbuf[ro + 8] = c.r
			_rbuf[ro + 9] = c.g
			_rbuf[ro + 10] = c.b
			_rbuf[ro + 11] = c.a
			nring += 1
	var mm := mm_living.multimesh
	mm.buffer = _buf
	mm.visible_instance_count = count
	mm_shadow.multimesh.buffer = _sbuf
	mm_shadow.multimesh.visible_instance_count = count
	mm_ring.multimesh.buffer = _rbuf
	mm_ring.multimesh.visible_instance_count = nring
	fx_layer.queue_redraw()
	banner_layer.queue_redraw()
	last_update_ms = float(Time.get_ticks_usec() - t0) / 1000.0


func _add_corpse(i: int) -> void:
	_corpse_done[i] = 1
	var ut := sim.utype[i]
	var tm := sim.team_of[i]
	var si := UnitAtlas.slot_index(ut, tm, UnitTypes.ANIM_DEATH)
	var fi := (atlas.anim_start[si] + atlas.anim_count[si] - 1) * 8
	var fr := atlas.frames
	var w := fr[fi + 4]
	var h := fr[fi + 5]
	var fl := sim.face[i]
	var p := sim.pos[i]
	var mm := mm_corpse.multimesh
	var k := _corpse_n
	if k >= mm.instance_count:
		return
	mm.set_instance_transform_2d(k, Transform2D(Vector2(w * fl, 0), Vector2(0, h), Vector2(p.x - fr[fi + 6] * fl, p.y - fr[fi + 7])))
	mm.set_instance_color(k, Color(0, 0, 0.8, 1))
	mm.set_instance_custom_data(k, Color(fr[fi], fr[fi + 1], fr[fi + 2], fr[fi + 3]))
	_corpse_n += 1
	mm.visible_instance_count = _corpse_n


func corpse_count() -> int:
	return _corpse_n


# =====================================================================================
#  Missiles & gun FX (arrows with ground shadows, muzzle flash, tracer, smoke)
# =====================================================================================

class _FxLayer extends Node2D:
	var r: SoldierRenderer

	func _draw() -> void:
		var sim := r.sim
		if sim == null:
			return
		var pr := sim.projectiles
		var a := sim.alpha
		var view := r._view_rect()
		var pprev := pr.prev
		var ppos := pr.pos
		var pz0 := pr.prev_z
		var pz1 := pr.z
		var pvel := pr.vel
		var pvz := pr.vz
		for k in pr.count:
			var g := pprev[k].lerp(ppos[k], a)
			if not view.has_point(g):
				continue
			var z := lerpf(pz0[k], pz1[k], a)
			var v := pvel[k]
			var sdir := Vector2(v.x, v.y - pvz[k]).normalized()
			var head := g - Vector2(0, z)
			var gd := v.normalized()
			var sa := 0.28 * clampf(1.0 - z / 260.0, 0.25, 1.0)
			draw_line(g - gd * 8.0, g, Color(0.08, 0.07, 0.06, sa), 1.3)
			draw_line(head - sdir * 10.0, head, Color(0.22, 0.15, 0.08, 0.95), 1.4)
			draw_line(head - sdir * 10.0, head - sdir * 7.0, Color(0.92, 0.9, 0.85, 0.9), 2.0)
		var now := sim.time + a * BattleSim.DT
		for s in sim.shot_fx:
			var age := now - float(s[2])
			var from: Vector2 = s[0]
			if not view.has_point(from):
				continue
			if age < 0.08:
				draw_circle(from, 6.0 - age * 40.0, Color(1.0, 0.85, 0.45, 0.9))
				draw_line(from, s[1], Color(1.0, 0.95, 0.75, 0.35 * (1.0 - age / 0.08)), 1.0)
			if age < 2.0:
				var t := age / 2.0
				var drift := Vector2(10.0, -6.0) * age
				var rad := 4.0 + age * 9.0
				draw_circle(from + drift + Vector2(4, -10), rad, Color(0.85, 0.84, 0.8, 0.42 * (1.0 - t)))
				draw_circle(from + drift * 1.4 + Vector2(10, -14), rad * 0.7, Color(0.9, 0.9, 0.86, 0.3 * (1.0 - t)))


# =====================================================================================
#  Sashimono / regiment banners above each regiment's leader
# =====================================================================================

class _BannerLayer extends Node2D:
	var r: SoldierRenderer

	func _draw() -> void:
		var sim := r.sim
		if sim == null:
			return
		var view := r._view_rect()
		var inv_zoom := clampf(1.0 / maxf(r.view_zoom(), 0.01), 1.0, 2.6)
		var font := ThemeDB.fallback_font
		var state := sim.state
		var utype := sim.utype
		var face := sim.face
		var uh := r.atlas.unit_height
		for reg in sim.regiments:
			if reg.alive <= 0 or reg.withdrawn:
				continue
			var L := reg.leader
			if L < 0 or state[L] >= BattleSim.DEAD:
				L = -1
				for i in reg.soldiers:
					if state[i] < BattleSim.DEAD:
						L = i
						break
				if L < 0:
					continue
			var p := sim.render_pos(L)
			if not view.has_point(p):
				continue
			var ut := utype[L]
			var h: float = uh[ut]
			var fl := face[L]
			var general := reg.type == UnitTypes.GENERAL
			var s := inv_zoom * (1.35 if general else 1.0)
			var pole_h := h + 18.0 * s
			var routing := reg.is_routing()
			var base := p + Vector2(-4.0 * fl, -h * 0.55)
			var top := p + Vector2(-6.0 * fl + (16.0 if routing else 0.0) * -fl, -pole_h)
			draw_line(base, top, Color(0.12, 0.09, 0.07, 0.95), 1.6 * s)
			var bw := 9.0 * s
			var bh := 22.0 * s
			var sway := sin(sim.time * 2.3 + float(reg.id) * 1.7) * 2.2 * s
			var col: Color = TEAM_BANNER[reg.team]
			if routing:
				col = col.darkened(0.35)
			var tl := top + Vector2(0, 1.5 * s)
			var poly := PackedVector2Array([tl, tl + Vector2(bw, 0), tl + Vector2(bw + sway, bh), tl + Vector2(sway, bh)])
			draw_line(tl + Vector2(-1, 0), tl + Vector2(bw + 1, 0), Color(0.12, 0.09, 0.07), 1.5 * s)
			draw_colored_polygon(poly, col)
			var mon: Color = TEAM_MON[reg.team]
			draw_circle(tl + Vector2(bw * 0.5 + sway * 0.5, bh * 0.38), 2.6 * s, mon)
			if reg.selected:
				var outline := poly.duplicate()
				outline.append(poly[0])
				draw_polyline(outline, Color(1, 0.9, 0.55), 1.4)
			if general:
				draw_circle(top + Vector2(0, -5 * s), 4.5 * s, Color("#D4A23C"))
				draw_arc(top + Vector2(0, -5 * s), 4.5 * s, 0, TAU, 16, Color(0.2, 0.15, 0.05), 1.0)
			if r.show_labels or reg.selected:
				var fs := int(13 * inv_zoom)
				var label := "%s  %d" % [reg.display_name, reg.alive]
				if routing:
					label += "  (%s)" % reg.morale_name()
				draw_string(font, tl + Vector2(bw + 5 * s, 9 * s), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 0.97, 0.9, 0.95))

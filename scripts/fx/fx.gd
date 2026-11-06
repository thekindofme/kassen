class_name BattleFX
extends Node2D
## Battle VFX director. Subscribes to BattleSim signals (and reads, never writes, its SoA state
## once per sim tick) and renders everything through a handful of MultiMesh ring buffers:
##   ground (inserted just above Terrain, under soldiers): mud/trampling, blood pools, spent arrows, grass tufts
##   air (this node, above soldiers and canopies): smoke, dust, blood drops, splashes, puffs
##   glow (this node, additive): muzzle flashes, sparks, warm glows
## plus BattleWeather (cloud shadows, mist, post grade) as a child. Arrows in flight and gun
## tracers are drawn by SoldierRenderer; this adds their impacts, smoke banks and flashes.
##
## Camera shake: shake(strength) / signal shake_requested. Drives camera.shake() if the camera
## has one, otherwise nudges Camera2D.offset itself.
## User args: --fx=0 (off)  --post=0  --mist=0.8  --clouds=0  --wind=x,y  --fx_stats (print perf)

signal shake_requested(strength: float)

const K_SMOKE := 0
const K_DUST := 1
const K_BLOOD := 2
const K_WATER := 3
const K_PUFF := 4
const K_FLASH := 5
const K_SPARK := 6
const K_GLOW := 7
const K_RING := 8

@export var fx_enabled := true
@export var wind := Vector2(18.0, -4.0)
@export_group("Matchlock")
@export var smoke_puffs_per_shot := 10
@export var smoke_life := Vector2(6.0, 10.0)
@export var smoke_size := 27.0
@export var smoke_alpha := 0.5
@export var muzzle_height := 24.0
@export_group("Dust and water")
@export var dust_alpha := 0.4
@export var dust_rate := 1.0
@export var splash_rate := 1.0
@export_group("Melee and blood")
@export var blood_amount := 1.0
@export var spark_chance := 0.35
@export var mud_rate := 1.4
@export var mud_opacity := 0.16
@export_group("Decals")
@export var blood_decal_cap := 4096
@export var mud_decal_cap := 6144
@export var arrow_decal_cap := 3072
@export var grass_tufts := true
@export var grass_count := 7000
@export_group("Camera")
@export var shake_scale := 1.0
@export var shake_max_px := 10.0

var sim: BattleSim
var terrain: Terrain
var camera: Camera2D
var weather: BattleWeather
var ground: Node2D
var air: FxPool
var glow: FxPool
var dec_mud: FxPool
var dec_blood: FxPool
var dec_arrow: FxPool
var dec_grass: FxPool
var pmat: ShaderMaterial
var dmat: ShaderMaterial
var rng := RandomNumberGenerator.new()   # own RNG: never touches the sim's deterministic one
var last_ms := 0.0
var stats := false
var _ms_acc := 0.0
var _ms_peak := 0.0

var _last_tick := -1
var _last_shot_t := -1.0
var _last_shot_log := -10.0
var _pflash := PackedFloat32Array()
var _trauma := 0.0
var _shake_t := 0.0
var _view := Rect2()


func setup(p_sim: BattleSim, p_terrain: Terrain, p_camera: Camera2D = null) -> void:
	sim = p_sim
	terrain = p_terrain
	camera = p_camera
	rng.seed = 7741
	var args := _args()
	if args.get("fx", "1") == "0":
		fx_enabled = false
	stats = args.has("fx_stats")
	if args.has("wind"):
		var w: PackedStringArray = String(args["wind"]).split(",")
		wind = Vector2(float(w[0]), float(w[1]) if w.size() > 1 else 0.0)
	var world := sim.map_size
	var tex := FxTextures.build_array()
	var quad := _centred_quad()
	pmat = ShaderMaterial.new()
	pmat.shader = load("res://scripts/render/shaders/fx_particles.gdshader")
	pmat.set_shader_parameter("tex", tex)
	dmat = ShaderMaterial.new()
	dmat.shader = load("res://scripts/render/shaders/fx_decal.gdshader")
	dmat.set_shader_parameter("tex", tex)

	# ground decals sit directly above the terrain (under village, corpses and soldiers)
	ground = Node2D.new()
	ground.name = "FXGround"
	var parent := get_parent() if get_parent() != null else self
	parent.add_child(ground)
	if terrain != null and terrain.get_parent() == parent:
		parent.move_child(ground, terrain.get_index() + 1)
	dec_mud = FxPool.new(ground, "Mud", mud_decal_cap, dmat, quad, world)
	dec_blood = FxPool.new(ground, "Blood", blood_decal_cap, dmat, quad, world)
	dec_arrow = FxPool.new(ground, "SpentArrows", arrow_decal_cap, dmat, quad, world)
	dec_grass = FxPool.new(ground, "Grass", maxi(grass_count, 1), dmat, quad, world)
	air = FxPool.new(self, "Air", 8192, pmat, quad, world)
	glow = FxPool.new(self, "Glow", 2048, pmat, quad, world)
	if grass_tufts and fx_enabled:
		_plant_grass()

	weather = BattleWeather.new()
	weather.name = "Weather"
	add_child(weather)
	weather.setup(sim, terrain, args)
	weather.wind = wind

	sim.soldier_died.connect(_on_died)
	sim.melee_contact.connect(_on_melee_contact)
	sim.charge_impact.connect(_on_charge)
	sim.projectile_hit.connect(_on_projectile_hit)
	sim.regiment_routed.connect(_on_routed)
	ground.visible = fx_enabled
	visible = true
	for p in [air, glow]:
		p.mmi.visible = fx_enabled


func _args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1] if kv.size() > 1 else "1"
	return out


static func _centred_quad() -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector2Array([Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)])
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_FLAG_USE_2D_VERTICES)
	return m


func now() -> float:
	return sim.time + sim.alpha * BattleSim.DT


# =====================================================================================
#  Per frame
# =====================================================================================

func _process(delta: float) -> void:
	if sim == null:
		return
	var t0 := Time.get_ticks_usec()
	_view = _view_rect(160.0)
	var t := now()
	if fx_enabled:
		if sim.tick_count != _last_tick:
			_last_tick = sim.tick_count
			_scan_tick()
		_poll_shots()
	_update_shake(delta)
	var tw := fposmod(t, 64.0)
	pmat.set_shader_parameter("fx_time", tw)
	pmat.set_shader_parameter("wind", wind)
	pmat.set_shader_parameter("smoke_alpha", smoke_alpha)
	pmat.set_shader_parameter("dust_alpha", dust_alpha)
	dmat.set_shader_parameter("fx_time", tw)
	dmat.set_shader_parameter("wind", wind)
	weather.wind = wind
	air.flush(t, true)
	glow.flush(t, true)
	dec_mud.flush(t, false)
	dec_blood.flush(t, false)
	dec_arrow.flush(t, false)
	dec_grass.flush(t, false)
	last_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	_ms_acc += last_ms
	_ms_peak = maxf(_ms_peak, last_ms)
	if stats and Engine.get_process_frames() % 120 == 0:
		print("[fx] fps %d  fx cpu avg %.3f / peak %.2f ms  air %d glow %d blood %d mud %d arrows %d" % [Engine.get_frames_per_second(),
			_ms_acc / 120.0, _ms_peak, air.used, glow.used, dec_blood.used, dec_mud.used, dec_arrow.used])
		_ms_acc = 0.0
		_ms_peak = 0.0


func _view_rect(margin: float) -> Rect2:
	var vp := get_viewport()
	var ct := vp.get_canvas_transform()
	return (ct.affine_inverse() * Rect2(Vector2.ZERO, vp.get_visible_rect().size)).grow(margin)


## Matchlock shots: the sim keeps ~2 s of [origin, end, time, hit] records; take the new ones.
func _poll_shots() -> void:
	var newest := _last_shot_t
	for s in sim.shot_fx:
		var st := float(s[2])
		if st <= _last_shot_t:
			continue
		newest = maxf(newest, st)
		if stats and st > _last_shot_log + 2.0:
			_last_shot_log = st
			print("[fx] volley t=%.1f at %s" % [st, s[0]])
		var origin: Vector2 = s[0]
		var end: Vector2 = s[1]
		var dir := (end - origin).normalized()
		_gun_shot(origin + Vector2(dir.x * 4.0, -muzzle_height), dir, st)
	_last_shot_t = newest


func _gun_shot(muzzle: Vector2, dir: Vector2, t: float) -> void:
	var near := _view.has_point(muzzle)
	if near:
		glow.particle(muzzle, K_FLASH, FxTextures.L_FLASH + rng.randi() % 2, rng.randf(), 0.075, dir, t, rng.randf_range(15.0, 21.0))
		glow.particle(muzzle + dir * 6.0, K_GLOW, FxTextures.L_DOT, rng.randf(), 0.14, Vector2.ZERO, t, 46.0)
	# a low, wide bank: puffs spread along the firing line's frontage (perpendicular to the shot)
	# and are pushed only 20-60 px forward; drag k=1.7 in the shader, so travel ~= speed / 1.7
	var perp := Vector2(-dir.y, dir.x)
	for k in smoke_puffs_per_shot:
		var f := float(k) / maxf(1.0, float(smoke_puffs_per_shot - 1))
		var speed := lerpf(100.0, 34.0, f) * rng.randf_range(0.8, 1.15)
		var v := dir * speed + perp * rng.randf_range(-30.0, 30.0)
		var life := rng.randf_range(smoke_life.x, smoke_life.y)
		var size := smoke_size * rng.randf_range(0.7, 1.15) * lerpf(0.8, 1.2, f)
		air.particle(muzzle + perp * rng.randf_range(-14.0, 14.0) + Vector2(0, muzzle_height * 0.6), K_SMOKE,
			FxTextures.L_SMOKE + rng.randi() % 4, rng.randf(), life, v, t + k * 0.015, size)


# =====================================================================================
#  Per sim tick: hits (blood), sword clashes (sparks), trampling (mud), dust, splashes, arrows
# =====================================================================================

func _scan_tick() -> void:
	var n := sim.n
	if _pflash.size() != n:
		_pflash.resize(n)
		_pflash.fill(0.0)
	var t := sim.time
	var dt := BattleSim.DT
	var state := sim.state
	var spos := sim.pos
	var vel := sim.vel
	var flash := sim.flash
	var action_t := sim.action_t
	var utype := sim.utype
	var target := sim.target
	var t_hit := sim.T_HIT
	var t_mount := sim.T_MOUNT
	var t_run := sim.T_RUN
	var view := _view
	var mud_p := 0.0045 * mud_rate
	for i in n:
		var st := state[i]
		if st >= BattleSim.DEAD:
			continue
		var p := spos[i]
		var fl := flash[i]
		if fl > _pflash[i] + 0.001 and view.has_point(p):
			_blood_spurt(p + Vector2(rng.randf_range(-3, 3), -16.0), t, 3 + rng.randi() % 3)
		if st == BattleSim.MELEE:
			var at := action_t[i]
			var ht := t_hit[utype[i]]
			if at >= ht and at - dt < ht and rng.randf() < spark_chance:
				var tg := target[i]
				if tg >= 0 and view.has_point(p):
					_sparks((p + spos[tg]) * 0.5 + Vector2(0, -20.0), t, 4 + rng.randi() % 4)
			if rng.randf() < mud_p:
				_mud(p + Vector2(rng.randf_range(-8, 8), rng.randf_range(-4, 6)), rng.randf_range(32.0, 56.0), mud_opacity)
		var v := vel[i]
		var spd2 := v.length_squared()
		if spd2 < 225.0:
			continue
		var ut := utype[i]
		var mounted := t_mount[ut] == 1
		var spd := sqrt(spd2)
		var runf := spd / t_run[ut]
		var water := false
		var prob := 0.0
		if runf > 0.55:
			prob = (0.32 if mounted else 0.035) * dust_rate * runf
		var roll := rng.randf()
		if roll < maxf(prob, 0.09 * splash_rate):
			var m := terrain.material_at(p) if terrain != null else 0
			water = m == Terrain.Mat.WATER or m == Terrain.Mat.FORD
			if water:
				if view.has_point(p) and roll < 0.09 * splash_rate * (2.0 if mounted else 1.0) * minf(1.0, spd / 40.0):
					_splash(p, v, t, mounted)
			elif roll < prob:
				if view.has_point(p):
					_dust(p - v.normalized() * 6.0, v, t, mounted)
				if mounted and rng.randf() < 0.12:
					_mud(p, rng.randf_range(14.0, 22.0), mud_opacity * 0.8)
	_pflash = flash.duplicate()
	# arrows that will land during the next tick: ground puff (or splash) and a spent shaft
	var pr := sim.projectiles
	for k in pr.count:
		if pr.z[k] + (pr.vz[k] - Projectiles.GRAVITY * dt) * dt > 0.0:
			continue
		var lp := pr.pos[k] + pr.vel[k] * dt
		var m2 := terrain.material_at(lp) if terrain != null else 0
		if m2 == Terrain.Mat.WATER or m2 == Terrain.Mat.FORD:
			if view.has_point(lp):
				_splash(lp, Vector2.ZERO, t, false)
			continue
		if view.has_point(lp):
			air.particle(lp, K_PUFF, FxTextures.L_SMOKE + rng.randi() % 4, rng.randf(), 0.7, pr.vel[k] * 0.05, t, rng.randf_range(5.0, 8.0))
		if rng.randf() < 0.7:
			var s := rng.randf_range(11.0, 14.0)
			var fx_flip := -1.0 if pr.vel[k].x < 0.0 else 1.0
			dec_arrow.decal(lp + Vector2(0, -s * 0.28), Vector2(s * fx_flip, 0), Vector2(0, s), FxTextures.L_ARROW,
				Color(1, 1, 1, 0.95))


# =====================================================================================
#  Emitters
# =====================================================================================

func _blood_spurt(p: Vector2, t: float, count: int) -> void:
	for k in int(count * blood_amount):
		var v := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(15.0, 55.0)
		air.particle(p, K_BLOOD, FxTextures.L_DOT, rng.randf(), 1.0, v, t, rng.randf_range(1.6, 3.0))


func _sparks(p: Vector2, t: float, count: int) -> void:
	for k in count:
		var v := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(50.0, 140.0)
		glow.particle(p, K_SPARK, FxTextures.L_DOT, rng.randf(), rng.randf_range(0.16, 0.3), v, t, rng.randf_range(1.4, 2.2))
	glow.particle(p, K_GLOW, FxTextures.L_DOT, rng.randf(), 0.08, Vector2.ZERO, t, 12.0)


func _dust(p: Vector2, v: Vector2, t: float, mounted: bool) -> void:
	var size := rng.randf_range(20.0, 30.0) if mounted else rng.randf_range(10.0, 15.0)
	var life := rng.randf_range(2.2, 3.4) if mounted else rng.randf_range(1.2, 2.0)
	var dv := -v * 0.12 + Vector2(rng.randf_range(-12, 12), rng.randf_range(-6, 4))
	air.particle(p + Vector2(rng.randf_range(-4, 4), rng.randf_range(-2, 2)), K_DUST, FxTextures.L_SMOKE + rng.randi() % 4,
		rng.randf(), life, dv, sim.time if t < 0.0 else t, size)


func _splash(p: Vector2, v: Vector2, t: float, mounted: bool) -> void:
	var drops := 8 if mounted else 4
	for k in drops:
		var dv := v * 0.2 + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(15.0, 45.0)
		air.particle(p, K_WATER, FxTextures.L_DOT, rng.randf(), 0.9, dv, t, rng.randf_range(2.0, 3.4))
	air.particle(p + Vector2(0, 2), K_RING, FxTextures.L_DOT, rng.randf(), 0.8, Vector2.ZERO, t, 18.0 if mounted else 11.0)


func _mud(p: Vector2, size: float, alpha: float) -> void:
	var ang := rng.randf() * TAU
	var ax := Vector2.from_angle(ang) * size
	var ay := Vector2.from_angle(ang + PI * 0.5) * size * 0.7
	var tone := rng.randf_range(0.0, 1.0)
	var c := Color(0.26, 0.19, 0.12).lerp(Color(0.33, 0.26, 0.17), tone)
	c.a = alpha
	dec_mud.decal(p, ax, ay, FxTextures.L_MUD if rng.randf() < 0.7 else FxTextures.L_SCUFF, c)


func _blood_decal(p: Vector2, size: float) -> void:
	var ang := rng.randf() * TAU
	var c := Color(0.55, 0.06, 0.05).lerp(Color(0.36, 0.05, 0.04), rng.randf())
	c.a = rng.randf_range(0.8, 0.95)
	var ax := Vector2.from_angle(ang) * size * 1.2
	var ay := Vector2.from_angle(ang + PI * 0.5) * size * 0.8
	dec_blood.decal(p, ax, ay, FxTextures.L_BLOOD + rng.randi() % 4, c)


func _burst(p: Vector2, radius: float, count: int, t: float) -> void:
	for k in count:
		var dir := Vector2.from_angle(rng.randf() * TAU)
		var q := p + dir * rng.randf_range(0.0, radius) * Vector2(1.0, 0.6)
		var m := terrain.material_at(q) if terrain != null else 0
		if m == Terrain.Mat.WATER or m == Terrain.Mat.FORD:
			_splash(q, dir * 30.0, t, true)
			continue
		air.particle(q, K_DUST, FxTextures.L_SMOKE + rng.randi() % 4, rng.randf(), rng.randf_range(1.8, 3.2),
			dir * rng.randf_range(30.0, 90.0), t, rng.randf_range(16.0, 28.0))


# =====================================================================================
#  Signal handlers
# =====================================================================================

func _on_died(i: int) -> void:
	if not fx_enabled:
		return
	var p := sim.pos[i]
	var mounted := sim.T_MOUNT[sim.utype[i]] == 1
	var s := rng.randf_range(19.0, 27.0) * (1.5 if mounted else 1.0)
	_blood_decal(p + Vector2(rng.randf_range(-9, 9), rng.randf_range(-3, 6)), s)
	if rng.randf() < 0.45:
		_blood_decal(p + Vector2(rng.randf_range(-10, 10), rng.randf_range(-5, 6)), s * 0.55)
	if _view.has_point(p):
		_blood_spurt(p + Vector2(0, -14), sim.time, 6)


func _on_melee_contact(pos: Vector2) -> void:
	if not fx_enabled:
		return
	_burst(pos, 60.0, 14, sim.time)
	_sparks(pos + Vector2(0, -20), sim.time, 8)


func _on_charge(pos: Vector2, strength: float) -> void:
	if stats:
		print("[fx] charge_impact t=%.1f pos=%s strength=%.1f" % [sim.time, pos, strength])
	if not fx_enabled:
		return
	# sim strengths: ~1 for a single rider's impact, ~8 for a full squadron hitting home
	_burst(pos, 30.0 + strength * 7.0, clampi(int(strength * 3.5), 4, 36), sim.time)
	for k in clampi(int(strength * 0.8), 1, 8):
		_mud(pos + Vector2(rng.randf_range(-40, 40), rng.randf_range(-24, 24)), rng.randf_range(28, 46), mud_opacity)
	if strength >= 2.5:
		var view := _view_rect(0.0)
		var d := view.get_center().distance_to(pos) / maxf(view.size.x, 1.0)
		shake(clampf(strength / 14.0, 0.1, 0.6) * clampf(1.2 - d * 1.4, 0.0, 1.0))


func _on_projectile_hit(pos: Vector2, kind: String) -> void:
	if not fx_enabled or not _view.has_point(pos):
		return
	_blood_spurt(pos + Vector2(0, -16), sim.time, 3 if kind == "arrow" else 5)
	if kind == "gun":
		air.particle(pos + Vector2(0, -14), K_PUFF, FxTextures.L_SMOKE + rng.randi() % 4, rng.randf(), 0.5, Vector2.ZERO, sim.time, 6.0)


func _on_routed(r: Regiment) -> void:
	if fx_enabled:
		_burst(r.mean_pos, 50.0, 10, sim.time)


# =====================================================================================
#  Camera shake (trauma model) and grass
# =====================================================================================

func shake(strength: float) -> void:
	if strength <= 0.0:
		return
	shake_requested.emit(strength)
	if camera != null and camera.has_method("shake"):
		camera.call("shake", strength * shake_scale)
		return
	_trauma = minf(1.0, _trauma + strength * shake_scale)


func _update_shake(delta: float) -> void:
	if camera == null or camera.has_method("shake"):
		return
	if _trauma <= 0.0:
		if camera.offset != Vector2.ZERO:
			camera.offset = Vector2.ZERO
		return
	_trauma = maxf(0.0, _trauma - delta * 1.8)
	_shake_t += delta
	var amp := _trauma * _trauma * shake_max_px / maxf(camera.zoom.x, 0.05)
	camera.offset = Vector2(sin(_shake_t * 61.0) + sin(_shake_t * 37.0) * 0.5, cos(_shake_t * 53.0) + sin(_shake_t * 29.0) * 0.5) * amp * 0.67


func _plant_grass() -> void:
	if terrain == null:
		return
	var g := RandomNumberGenerator.new()
	g.seed = 99
	var size := sim.map_size
	var planted := 0
	var tries := 0
	while planted < grass_count and tries < grass_count * 4:
		tries += 1
		var p := Vector2(g.randf() * size.x, g.randf() * size.y)
		if terrain.material_at(p) != Terrain.Mat.GRASS or terrain.is_forest(p):
			continue
		var s := g.randf_range(9.0, 15.0)
		var c := Color(0.85, 0.85, 0.8).lerp(Color(1.05, 1.0, 0.85), g.randf())
		c.a = g.randf_range(0.7, 0.95)
		dec_grass.decal(p + Vector2(0, -s * 0.45), Vector2(s * (1.0 if g.randf() < 0.5 else -1.0), 0), Vector2(0, s),
			FxTextures.L_GRASS + g.randi() % 2, c, 0.16)
		planted += 1

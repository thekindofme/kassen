class_name BattleSim
extends Node
## The battle simulation. Owns every soldier as struct-of-arrays and advances them at a
## fixed 30 Hz tick (render interpolates with `alpha`). Deterministic for a given seed.
##
## FX / audio / UI subscribe to the signals below only. AI and player code issue orders through
## the Regiment API (see regiment.gd). Reach it with get_tree().get_first_node_in_group("sim").

signal soldier_died(i: int)
signal regiment_routed(r: Regiment)
signal regiment_rallied(r: Regiment)
signal battle_ended(winner_team: int)
signal melee_contact(pos: Vector2)
signal volley(pos: Vector2, kind: String)          # kind: "arrow" | "gun"
signal charge_impact(pos: Vector2, strength: float)
signal general_killed(team: int)
signal battle_started()
signal deployment_started()
signal projectile_hit(pos: Vector2, kind: String)  # "arrow" (landed on a soldier) | "gun" (bullet hit)

const TICK_HZ := 30
const DT := 1.0 / TICK_HZ
const CELL := 32.0
const ID_BITS := 13
const ID_MASK := (1 << ID_BITS) - 1

# soldier states
const IDLE := 0
const MOVE := 1
const MELEE := 2
const SHOOT := 3
const ROUT := 4    # alive, fleeing (ordered before DEAD so `state < DEAD` = alive)
const DEAD := 5
const FLED := 6   # left the map (routed off or withdrew); not drawn, no corpse

var map_size := Vector2(4800, 3200)
var terrain: Node = null           # Terrain (optional; null = flat open field)
var rng := RandomNumberGenerator.new()
var time := 0.0
var tick_count := 0
var time_scale := 1.0
var paused := false
## Deployment phase: the clock is stopped and the player may place regiments inside
## deploy_zones[team] (see deploy_place). begin_battle() ends it.
var deploying := false
var started := false
var deploy_zones: Array[Rect2] = []
var auto_run := true               # advance in _process (false for headless tests that call step())
var alpha := 0.0                   # render interpolation factor in [0,1)
var ended := false
var winner := -1
var _acc := 0.0
var _home := [Vector2.LEFT, Vector2.RIGHT]

var regiments: Array[Regiment] = []
var projectiles := Projectiles.new()
## Recent gunshots for renderer FX: each entry [from: Vector2, to: Vector2, time: float, hit: bool].
var shot_fx: Array = []
var general_alive := [false, false]
var general_idx := [-1, -1]

# ---- soldiers (SoA) -----------------------------------------------------------------
var n := 0
var pos := PackedVector2Array()
var prev_pos := PackedVector2Array()
var vel := PackedVector2Array()
var sep := PackedVector2Array()
var slot_pos := PackedVector2Array()
var hp := PackedFloat32Array()
var face := PackedFloat32Array()        # +1 right, -1 left
var anim_t := PackedFloat32Array()      # idle/walk phase (frames)
var anim_rate := PackedFloat32Array()   # per-soldier animation speed variation (~±8%)
var action_t := PackedFloat32Array()    # seconds since the last attack/shot began
var dead_t := PackedFloat32Array()      # seconds since death
var cooldown := PackedFloat32Array()
var stagger := PackedFloat32Array()
var flash := PackedFloat32Array()       # hit flash timer
var reg_of := PackedInt32Array()
var team_of := PackedInt32Array()
var utype := PackedInt32Array()
var state := PackedInt32Array()
var target := PackedInt32Array()
var slot := PackedInt32Array()
var pending := PackedInt32Array()       # soldier index of a swing/shot in progress (-1 none)
var charge_ready := PackedInt32Array()

# ---- per-type caches ----------------------------------------------------------------
var T_HP := PackedFloat32Array(); var T_ATK := PackedFloat32Array(); var T_DEF := PackedFloat32Array()
var T_DMG := PackedFloat32Array(); var T_INT := PackedFloat32Array(); var T_REACH := PackedFloat32Array()
var T_CHG := PackedFloat32Array(); var T_ARM := PackedFloat32Array(); var T_WALK := PackedFloat32Array()
var T_RUN := PackedFloat32Array(); var T_RANGE := PackedFloat32Array(); var T_RELOAD := PackedFloat32Array()
var T_ACC := PackedFloat32Array(); var T_MDMG := PackedFloat32Array(); var T_RANGED := PackedInt32Array()
var T_MASS := PackedFloat32Array(); var T_MOUNT := PackedInt32Array(); var T_ANTICAV := PackedFloat32Array()
var T_RAD := PackedFloat32Array(); var T_ACTLEN := PackedFloat32Array(); var T_HIT := PackedFloat32Array()

# ---- spatial hash (sorted cell keys) -----------------------------------------------------
var gw := 1
var gh := 1
var cell_start := PackedInt32Array()
var hs_keys := PackedInt32Array()
var hs_ids := PackedInt32Array()
var hs_cell := PackedInt32Array()
var hs_count := 0
var _nb := PackedInt32Array()
var _nb_count := 0

# ---- terrain cache ------------------------------------------------------------------
var _t_speed := PackedFloat32Array()
var _t_cell := 16.0
var _t_w := 0
var _t_h := 0

# stats for tests
var stat_arrows_fired := 0
var stat_arrow_hits := 0
var stat_gun_shots := 0
var stat_gun_hits := 0
var stat_charges := 0
var stat_braced := 0
var stat_kills := [0, 0]


func _init() -> void:
	_nb.resize(1024)
	for k in UnitTypes.KEYS:
		var s: Dictionary = UnitTypes.STATS[k]
		T_HP.append(s["hp"]); T_ATK.append(s["melee_attack"]); T_DEF.append(s["melee_defence"])
		T_DMG.append(s["damage"]); T_INT.append(s["attack_interval"]); T_REACH.append(s["reach"])
		T_CHG.append(s["charge_bonus"]); T_ARM.append(s["armour"]); T_WALK.append(s["speed_walk"])
		T_RUN.append(s["speed_run"]); T_RANGE.append(s["range"]); T_RELOAD.append(s["reload"])
		T_ACC.append(s["accuracy"]); T_MDMG.append(s["missile_damage"]); T_RANGED.append(s["ranged"])
		T_MASS.append(s["mass"]); T_MOUNT.append(1 if s["mounted"] else 0); T_ANTICAV.append(s["anti_cav"])
		T_RAD.append(s["radius"]); T_ACTLEN.append(s["action_len"]); T_HIT.append(s["hit_time"])


func _ready() -> void:
	add_to_group("sim")


## Call once before spawning. `home_dirs[team]` = direction of that team's map edge (routing / withdraw).
func setup(p_size: Vector2, p_terrain: Node = null, seed_value := 1, home_dirs: Array = [Vector2.LEFT, Vector2.RIGHT]) -> void:
	map_size = p_size
	terrain = p_terrain
	rng.seed = seed_value
	_home = home_dirs
	gw = int(ceil(map_size.x / CELL)) + 1
	gh = int(ceil(map_size.y / CELL)) + 1
	cell_start.resize(gw * gh)
	cell_start.fill(-1)
	if terrain != null:
		_t_speed = terrain.speed_grid
		_t_cell = terrain.cell
		_t_w = terrain.grid_w
		_t_h = terrain.grid_h


func home_dir(team: int) -> Vector2:
	return _home[team]


# =====================================================================================
#  Spawning
# =====================================================================================

func spawn_regiment(type_key: String, team: int, centre: Vector2, p_facing := Vector2.RIGHT, men := -1, p_files := -1) -> Regiment:
	var t := UnitTypes.index_of(type_key)
	assert(t >= 0, "unknown unit type " + type_key)
	var r := Regiment.new(self, regiments.size(), team, t)
	var s: Dictionary = r.stats
	if men <= 0:
		men = s["men"]
	if p_files > 0:
		r.files = p_files
	r.initial_men = men
	r.alive = men
	r.centre = centre
	r.dest_centre = centre
	r.facing = p_facing.normalized()
	r.dest_facing = r.facing
	r.dest_files = r.files
	r.mean_pos = centre
	var base := n
	_resize(n + men)
	for k in men:
		var i := base + k
		var p := centre + Regiment.slot_offset(k, men, r.files, r.facing, r.spacing)
		p += Vector2(rng.randf_range(-1.5, 1.5), rng.randf_range(-1.5, 1.5))
		pos[i] = p; prev_pos[i] = p; vel[i] = Vector2.ZERO; sep[i] = Vector2.ZERO; slot_pos[i] = p
		hp[i] = T_HP[t]
		face[i] = 1.0 if r.facing.x >= 0.0 else -1.0
		anim_t[i] = rng.randf() * 8.0
		anim_rate[i] = rng.randf_range(0.92, 1.08)
		action_t[i] = 99.0
		dead_t[i] = 0.0
		cooldown[i] = rng.randf() * maxf(T_INT[t], T_RELOAD[t] * 0.35)
		stagger[i] = 0.0
		flash[i] = 0.0
		reg_of[i] = r.id
		team_of[i] = team
		utype[i] = t
		state[i] = IDLE
		target[i] = -1
		slot[i] = k
		pending[i] = -1
		charge_ready[i] = 0
		r.soldiers.append(i)
	if t == UnitTypes.GENERAL:
		r.general_soldier = base
		hp[base] = T_HP[t] * 3.0
		general_alive[team] = true
		general_idx[team] = base
	regiments.append(r)
	r.assign_slots(centre, r.facing, r.files)
	return r


func _resize(m: int) -> void:
	assert(m <= ID_MASK + 1, "too many soldiers for the hash key layout")
	n = m
	for a in ["pos", "prev_pos", "vel", "sep", "slot_pos", "hp", "face", "anim_t", "anim_rate", "action_t", "dead_t",
			"cooldown", "stagger", "flash", "reg_of", "team_of", "utype", "state", "target", "slot", "pending", "charge_ready"]:
		var arr = get(a)
		arr.resize(m)
		set(a, arr)
	hs_keys.resize(m)
	hs_ids.resize(m)
	hs_cell.resize(m)


# =====================================================================================
#  Queries (for AI, input and UI)
# =====================================================================================

func regiments_of(team: int) -> Array[Regiment]:
	var out: Array[Regiment] = []
	for r in regiments:
		if r.team == team:
			out.append(r)
	return out


func enemies_of(team: int) -> Array[Regiment]:
	var out: Array[Regiment] = []
	for r in regiments:
		if r.team != team:
			out.append(r)
	return out


func general_of(team: int) -> Regiment:
	for r in regiments:
		if r.team == team and r.type == UnitTypes.GENERAL:
			return r
	return null


func men_alive(team: int, include_routing := true) -> int:
	var c := 0
	for r in regiments:
		if r.team == team and not r.withdrawn and (include_routing or not r.is_routing()):
			c += r.alive
	return c


## Picks the soldier whose sprite body is under `world` (feet-anchored sprites, so search a
## little below the point). Returns -1 if none. `team` filters (-1 = any).
func pick_soldier(world: Vector2, team := -1, max_d := 18.0) -> int:
	var best := -1
	var best_d := max_d * max_d
	var c := _query(world + Vector2(0, 18), 34.0)
	for q in c:
		var j := _nb[q]
		if team >= 0 and team_of[j] != team:
			continue
		var body := pos[j] - Vector2(0, 18 if T_MOUNT[utype[j]] == 0 else 26)
		var d2 := body.distance_squared_to(world)
		if d2 < best_d:
			best_d = d2
			best = j
	return best


## True if any living soldier's feet are inside `rect` (used for canopy fading).
func any_soldier_in(rect: Rect2) -> bool:
	var c := _query(rect.get_center(), maxf(rect.size.x, rect.size.y) * 0.5)
	for q in c:
		if rect.has_point(pos[_nb[q]]):
			return true
	return false


func regiment_at(world: Vector2, team := -1) -> Regiment:
	var i := pick_soldier(world, team)
	return regiments[reg_of[i]] if i >= 0 else null


## Regiments of `team` with at least one living soldier inside `rect` (world).
func regiments_in_rect(rect: Rect2, team: int) -> Array[Regiment]:
	var out: Array[Regiment] = []
	for r in regiments:
		if r.team != team or r.alive <= 0 or r.withdrawn:
			continue
		for i in r.soldiers:
			if state[i] < DEAD and rect.has_point(pos[i] - Vector2(0, 16)):
				out.append(r)
				break
	return out


## Used by Regiment.assign_slots (avoids copying the slot array across objects).
func apply_slots(ids: PackedInt32Array, slots: PackedInt32Array) -> void:
	for k in ids.size():
		slot[ids[k]] = slots[k]


func fatigue_speed_mult(r: Regiment) -> float:
	return MoraleRules.fatigue_speed_mult(r)


func effective_range(r: Regiment, t: Regiment) -> float:
	var base: float = r.stats["range"]
	var dh := r.height - t.height
	return base * (1.0 + clampf(dh * 0.004, -0.15, 0.25))


func render_pos(i: int) -> Vector2:
	return prev_pos[i].lerp(pos[i], alpha)


# =====================================================================================
#  Spatial hash
# =====================================================================================

func _rebuild_hash() -> void:
	cell_start.fill(-1)
	var m := 0
	var inv := 1.0 / CELL
	for i in n:
		if state[i] < DEAD:
			var p := pos[i]
			var cx := clampi(int(p.x * inv), 0, gw - 1)
			var cy := clampi(int(p.y * inv), 0, gh - 1)
			hs_keys[m] = ((cy * gw + cx) << ID_BITS) | i
			m += 1
	for k in range(m, n):
		hs_keys[k] = 0x7FFFFFFF
	hs_keys.sort()
	hs_count = m
	var last := -1
	for k in m:
		var key := hs_keys[k]
		var c := key >> ID_BITS
		hs_ids[k] = key & ID_MASK
		hs_cell[k] = c
		if c != last:
			cell_start[c] = k
			last = c


## Fills _nb with living soldiers whose cell overlaps the box around p of half-size r.
## Returns the count. (Box test only; callers do the exact distance check.)
func _query(p: Vector2, r: float) -> int:
	var inv := 1.0 / CELL
	var cx0 := clampi(int((p.x - r) * inv), 0, gw - 1)
	var cx1 := clampi(int((p.x + r) * inv), 0, gw - 1)
	var cy0 := clampi(int((p.y - r) * inv), 0, gh - 1)
	var cy1 := clampi(int((p.y + r) * inv), 0, gh - 1)
	var c := 0
	var cap := _nb.size()
	for cy in range(cy0, cy1 + 1):
		var row := cy * gw
		for cx in range(cx0, cx1 + 1):
			var cell := row + cx
			var k := cell_start[cell]
			if k < 0:
				continue
			while k < hs_count and hs_cell[k] == cell:
				if c < cap:
					_nb[c] = hs_ids[k]
					c += 1
				k += 1
	_nb_count = c
	return c


func _speed_at(p: Vector2) -> float:
	if _t_w == 0:
		return 1.0
	var gx := clampi(int(p.x / _t_cell), 0, _t_w - 1)
	var gy := clampi(int(p.y / _t_cell), 0, _t_h - 1)
	return _t_speed[gy * _t_w + gx]


# =====================================================================================
#  Main loop
# =====================================================================================

func begin_deployment() -> void:
	deploying = true
	# snap every regiment fully inside its zone
	for r in regiments:
		if r.team < deploy_zones.size() and deploy_zones[r.team].size != Vector2.ZERO:
			deploy_place(r, r.centre, r.facing)
	_rebuild_hash()
	deployment_started.emit()


## Ends deployment (Enter / the UI's "Begin Battle") and starts the clock.
func begin_battle() -> void:
	if started and not deploying:
		return
	deploying = false
	if not started:
		started = true
		battle_started.emit()


func set_speed(x: float) -> void:
	time_scale = clampf(x, 0.25, 4.0)


## Clamp a regiment centre so its whole block stays inside the team's deployment zone.
func clamp_to_deploy_zone(team: int, c: Vector2, half_extent: Vector2) -> Vector2:
	if team >= deploy_zones.size() or deploy_zones[team].size == Vector2.ZERO:
		return c
	var z := deploy_zones[team]
	var lo := z.position + half_extent
	var hi := z.end - half_extent
	return Vector2(clampf(c.x, lo.x, maxf(lo.x, hi.x)), clampf(c.y, lo.y, maxf(lo.y, hi.y)))


## Deployment: instantly place a regiment (clamped to its zone), soldiers exactly on their slots.
func deploy_place(r: Regiment, c: Vector2, fwd: Vector2, p_files := 0) -> void:
	if p_files > 0:
		r.files = clampi(p_files, 1, maxi(1, r.alive))
	if fwd.length_squared() > 0.01:
		r.facing = fwd.normalized()
	var ext := (Vector2(-r.facing.y, r.facing.x) * r.width() * 0.5).abs() + (r.facing * r.depth() * 0.5).abs() + Vector2(14, 14)
	c = clamp_to_deploy_zone(r.team, c, ext)
	r.orders.clear()
	r.centre = c
	r.dest_centre = c
	r.dest_facing = r.facing
	r.dest_files = r.files
	r.mean_pos = c
	r.assign_slots(c, r.facing, r.files)
	var f := r._eff_files()
	for i in r.soldiers:
		if state[i] >= DEAD:
			continue
		var p := c + Regiment.slot_offset(slot[i], r.slot_n, f, r.facing, r.spacing)
		pos[i] = p
		prev_pos[i] = p
		slot_pos[i] = p
		vel[i] = Vector2.ZERO
		face[i] = 1.0 if r.facing.x >= 0.0 else -1.0
	if r.id < _r_prev_centre.size():
		_r_prev_centre[r.id] = c
	_rebuild_hash()


func _process(delta: float) -> void:
	if not auto_run or paused or deploying:
		return
	_acc += minf(delta, 0.1) * time_scale
	var steps := 0
	while _acc >= DT and steps < 8:
		_tick()
		_acc -= DT
		steps += 1
	if steps >= 8:
		_acc = 0.0
	alpha = clampf(_acc / DT, 0.0, 1.0)


## Advance `ticks` fixed steps immediately (tests, fast-forward).
## Per-section profiling (wall-clock usec): hash, regiments, slots, soldiers, missiles+morale, total.
const PROF_NAMES := ["hash", "regiments", "slots", "soldiers", "missiles+morale", "total"]
var prof_sum := PackedInt64Array([0, 0, 0, 0, 0, 0])
var prof_max := PackedInt64Array([0, 0, 0, 0, 0, 0])
var prof_ticks := 0


func _prof_add(k: int, us: int) -> void:
	prof_sum[k] += us
	if us > prof_max[k]:
		prof_max[k] = us
	if k == 5:
		prof_ticks += 1


func prof_reset() -> void:
	prof_sum.fill(0)
	prof_max.fill(0)
	prof_ticks = 0


func prof_report() -> String:
	var out := ""
	for k in PROF_NAMES.size():
		out += "%s %.2f/%.1f  " % [PROF_NAMES[k], prof_sum[k] / 1000.0 / maxi(1, prof_ticks), prof_max[k] / 1000.0]
	return out + "(avg/max ms)"


func step(ticks := 1) -> void:
	for k in ticks:
		_tick()
	alpha = 1.0


func _tick() -> void:
	var dt := DT
	if not started:
		started = true
		battle_started.emit()
	time += dt
	tick_count += 1
	var _t0 := Time.get_ticks_usec()
	prev_pos = pos.duplicate()
	_rebuild_hash()
	var _t1 := Time.get_ticks_usec()
	_regiment_pre(dt)
	var _t2 := Time.get_ticks_usec()
	_compute_slots()
	var _t3 := Time.get_ticks_usec()
	_soldiers(dt)
	var _t4 := Time.get_ticks_usec()
	projectiles.update(dt, self)
	_regiment_post(dt)
	var _t5 := Time.get_ticks_usec()
	_prof_add(0, _t1 - _t0); _prof_add(1, _t2 - _t1); _prof_add(2, _t3 - _t2)
	_prof_add(3, _t4 - _t3); _prof_add(4, _t5 - _t4); _prof_add(5, _t5 - _t0)
	if tick_count % 15 == 0:
		_check_victory()
	# expire gun fx
	while not shot_fx.is_empty() and time - float(shot_fx[0][2]) > 2.0:
		shot_fx.pop_front()


# ---- regiments ------------------------------------------------------------------------

var _r_sum := PackedVector2Array()
var _r_cnt := PackedInt32Array()
var _r_eng := PackedInt32Array()
var _r_spd := PackedFloat32Array()
var _r_err := PackedFloat32Array()
var _r_free := PackedInt32Array()
var _r_anchor_vel := PackedVector2Array()
var _r_prev_centre := PackedVector2Array()
var _r_flee := PackedVector2Array()
var _r_tdir := PackedVector2Array()   # sum of directions to melee opponents (auto-face threats)

func _regiment_pre(dt: float) -> void:
	var R := regiments.size()
	if _r_sum.size() != R:
		_r_sum.resize(R); _r_cnt.resize(R); _r_eng.resize(R); _r_spd.resize(R); _r_err.resize(R)
		_r_free.resize(R); _r_anchor_vel.resize(R); _r_prev_centre.resize(R); _r_flee.resize(R); _r_tdir.resize(R)
		for r in regiments:
			_r_prev_centre[r.id] = r.centre
	# aggregate last tick's soldier data
	for r in regiments:
		var k := r.id
		var c := _r_cnt[k]
		if c > 0:
			r.mean_pos = _r_sum[k] / c
			r.avg_speed = _r_spd[k] / c
		r.engaged = _r_eng[k]
		r.cohesion = _r_err[k] / maxf(1.0, float(_r_free[k]))
		if terrain != null:
			r.height = terrain.height(r.mean_pos)
	# nearest enemy regiments (cheap: R^2 on centres)
	if tick_count % 6 == 1 or tick_count <= 2:
		for r in regiments:
			r.nearest_enemy = null
			r.nearest_enemy_dist = INF
			if r.alive <= 0 or r.withdrawn:
				continue
			for e in regiments:
				if e.team == r.team or e.alive <= 0 or e.withdrawn:
					continue
				var d := r.mean_pos.distance_to(e.mean_pos) - (e.depth() + e.width()) * 0.3
				if d < r.nearest_enemy_dist:
					r.nearest_enemy_dist = d
					r.nearest_enemy = e
		_update_crowding()
		_update_fire_targets()
	for r in regiments:
		if r.alive <= 0 or r.withdrawn:
			continue
		if r.is_routing():
			var fd: Vector2 = _home[r.team]
			if r.nearest_enemy != null and r.nearest_enemy_dist < 450.0:
				fd += (r.mean_pos - r.nearest_enemy.mean_pos).normalized() * 0.8
			_r_flee[r.id] = fd.normalized()
			continue
		if r.is_idle() and r.engaged * 4 >= r.alive and _r_tdir[r.id].length() > 2.0:
			_face_threat(r, _r_tdir[r.id].normalized(), dt)
		r.tick_orders(dt)
		# per-tick caches read by every soldier of the regiment
		r.c_speed_mult = MoraleRules.fatigue_speed_mult(r)
		r.c_target = r.target()
		r.c_ranged = r.is_ranged()
		if r.c_ranged and r.fire_target != null:
			r.c_fire_reach = effective_range(r, r.fire_target) + r.fire_target.depth() * 0.5
		else:
			r.c_fire_reach = -1.0
		_r_anchor_vel[r.id] = (r.centre - _r_prev_centre[r.id]) / dt
		_r_prev_centre[r.id] = r.centre
		if r.engaged > 0 and not r.was_engaged and time - r.last_contact_emit > 2.0:
			r.last_contact_emit = time
			melee_contact.emit(r.mean_pos)
		if r.was_engaged and r.engaged == 0 and r.is_idle():
			r.reform_here()
		r.was_engaged = r.engaged > 0
	# reset accumulators
	_r_tdir.fill(Vector2.ZERO)
	_r_sum.fill(Vector2.ZERO); _r_cnt.fill(0); _r_eng.fill(0); _r_spd.fill(0.0); _r_err.fill(0.0); _r_free.fill(0)


## A regiment is "crowded" when another regiment's footprint is close: only then do its
## soldiers need separation (formation spacing already keeps a lone block apart).
## An idle regiment fighting off-axis (flank or rear attack) wheels to face the threat, as TW
## units do on their own, so it stops suffering flank penalties once it has turned.
func _face_threat(r: Regiment, want: Vector2, dt: float) -> void:
	var ang := r.facing.angle_to(want)
	if absf(ang) < 0.35:
		return
	if absf(ang) > 1.2:
		r.facing = want
		r.dest_facing = want
		r.assign_slots(r.centre, r.facing, r.files)
	else:
		r.facing = r.facing.rotated(clampf(ang, -1.2 * dt, 1.2 * dt))
		r.dest_facing = r.facing


func _update_crowding() -> void:
	for r in regiments:
		r.crowded = r.engaged > 0
	var R := regiments.size()
	for a in R:
		var ra := regiments[a]
		if ra.alive <= 0 or ra.withdrawn:
			continue
		var ea := 0.5 * Vector2(ra.width(), ra.depth()).length() + 30.0
		for b in range(a + 1, R):
			var rb := regiments[b]
			if rb.alive <= 0 or rb.withdrawn:
				continue
			var eb := 0.5 * Vector2(rb.width(), rb.depth()).length() + 30.0
			if ra.mean_pos.distance_to(rb.mean_pos) < ea + eb:
				ra.crowded = true
				rb.crowded = true
		if ra.is_routing() or ra.cohesion > ra.spacing.x:
			ra.crowded = true


func _update_fire_targets() -> void:
	for r in regiments:
		if not r.is_ranged() or r.is_broken() or r.withdrawn:
			continue
		var o := r.current_order()
		if not o.is_empty():
			if o["type"] != Regiment.Order.ATTACK:
				r.fire_target = null
			continue
		r.fire_target = null
		if not r.fire_at_will:
			continue
		var best: Regiment = null
		var best_d := INF
		for e in regiments:
			if e.team == r.team or e.alive <= 0 or e.withdrawn or e.state == Regiment.Morale.SHATTERED:
				continue
			var d := r.mean_pos.distance_to(e.mean_pos)
			if d - e.depth() * 0.5 > effective_range(r, e):
				continue
			if r.stats["ranged"] == UnitTypes.RANGED_GUN and _friend_blocks(r, e):
				continue
			if d < best_d:
				best_d = d
				best = e
		r.fire_target = best


func _friend_blocks(r: Regiment, e: Regiment) -> bool:
	var a := r.mean_pos
	var b := e.mean_pos
	var ab := b - a
	var L := ab.length()
	if L < 1.0:
		return false
	var dir := ab / L
	for f in regiments:
		if f == r or f.team != r.team or f.alive <= 0 or f.withdrawn:
			continue
		var t := (f.mean_pos - a).dot(dir)
		if t < 20.0 or t > L - 20.0:
			continue
		var perp := absf((f.mean_pos - a).cross(dir))
		if perp < f.width() * 0.5 + 12.0:
			return true
	return false


func _compute_slots() -> void:
	for r in regiments:
		if r.alive <= 0 or r.is_routing() or r.withdrawn:
			continue
		var f := r._eff_files()
		var nslots := r.alive
		# slot indices may exceed alive until the next reassign: size the block by the max slot
		for i in r.soldiers:
			if state[i] < DEAD and slot[i] >= nslots:
				nslots = slot[i] + 1
		f = maxi(1, mini(f, nslots))
		var nranks := ceili(float(nslots) / f)
		var fwd := r.facing
		var right := Vector2(-fwd.y, fwd.x)
		var sp := r.spacing
		var c := r.centre
		var half_depth := float(nranks - 1) * sp.y * 0.5
		var last_in_rank := nslots - (nranks - 1) * f
		for i in r.soldiers:
			if state[i] >= DEAD:
				continue
			var k := slot[i]
			var rank := k / f
			var file := k % f
			var in_rank := f if rank < nranks - 1 else last_in_rank
			var x := (float(file) - float(in_rank - 1) * 0.5) * sp.x
			var y := float(rank) * sp.y - half_depth
			slot_pos[i] = c + right * x - fwd * y


# ---- soldiers -------------------------------------------------------------------------

func _soldiers(dt: float) -> void:
	var W := map_size.x
	var H := map_size.y
	var tsp := _t_speed
	var tw := _t_w
	var th := _t_h
	var tinv := 1.0 / _t_cell
	var phase := tick_count % 4
	var sep_phase := tick_count % 3
	for i in n:
		var st := state[i]
		if st >= DEAD:
			if st == DEAD:
				dead_t[i] += dt
			continue
		var r: Regiment = regiments[reg_of[i]]
		if r.withdrawn:
			continue
		var ut := utype[i]
		var p := pos[i]
		var v := vel[i]
		var run_s := T_RUN[ut] * r.c_speed_mult
		var walk_s := T_WALK[ut]
		var rad := T_RAD[ut]
		flash[i] = maxf(0.0, flash[i] - dt)
		action_t[i] += dt
		cooldown[i] -= dt
		var stg := stagger[i]
		if stg > 0.0:
			stagger[i] = stg - dt
		var desired := Vector2.ZERO
		var accel := 420.0 if T_MOUNT[ut] == 0 else 300.0
		var t := target[i]

		# resolve a swing / shot in progress
		# fast path: settled soldier of a quiet regiment
		if st <= MOVE and stg <= 0.0 and pending[i] == -1 and not r.crowded and r.nearest_enemy_dist > 220.0 \
				and v == Vector2.ZERO and _r_anchor_vel[r.id] == Vector2.ZERO and r.fire_target == null \
				and p.distance_squared_to(slot_pos[i]) < 0.64:
			anim_t[i] += dt * 6.0 * anim_rate[i]
			flash[i] = 0.0
			state[i] = IDLE
			target[i] = -1
			_r_sum[r.id] += p
			_r_cnt[r.id] += 1
			_r_free[r.id] += 1
			continue
		var pd := pending[i]
		if pd != -1 and action_t[i] >= T_HIT[ut]:
			pending[i] = -1
			if st == SHOOT:
				_release_shot(i, r, pd)
			elif pd >= 0 and state[pd] < DEAD and stg <= 0.0:
				if p.distance_to(pos[pd]) <= T_REACH[ut] + T_RAD[utype[pd]] + 10.0:
					_melee_hit(i, pd, r)

		if st == ROUT:
			var fd: Vector2 = _r_flee[r.id]
			var wob := sin(float(i) * 1.7 + time * 0.6) * 0.35
			desired = fd.rotated(wob) * run_s * 0.92
			if p.x < 8.0 or p.x > W - 8.0 or p.y < 8.0 or p.y > H - 8.0:
				_flee_off(i, r)
				continue
		else:
			# --- target acquisition
			if t >= 0:
				var ts := state[t]
				if ts >= DEAD or p.distance_squared_to(pos[t]) > 140.0 * 140.0:
					t = -1
			if t < 0 and (i % 4) == phase and r.nearest_enemy_dist < 260.0:
				t = _find_enemy(i, p, _seek_radius(r, ut), r)
			target[i] = t
			if t >= 0:
				# --- melee
				_r_eng[r.id] += 1
				var pt := pos[t]
				var dd := pt - p
				var dl := maxf(dd.length(), 0.001)
				var dir := dd / dl
				_r_tdir[r.id] += dir
				var reach := T_REACH[ut] + T_RAD[utype[t]]
				var spd := v.length()
				if dl > reach:
					var close_s := run_s if (r.charging or dl > 28.0 or r.running) else walk_s * 1.5
					desired = dir * close_s
				elif dl < reach * 0.55:
					desired = -dir * 30.0
				if dl <= reach + 3.0 + spd * dt:
					if charge_ready[i] == 1 and spd > run_s * 0.6 and stg <= 0.0:
						charge_ready[i] = 0
						_charge(i, t, r, spd, dir)
						v = vel[i]
					elif cooldown[i] <= 0.0 and stg <= 0.0 and pending[i] == -1:
						action_t[i] = 0.0
						pending[i] = t
						cooldown[i] = T_INT[ut] * rng.randf_range(0.85, 1.2) / maxf(0.6, MoraleRules.fatigue_attack_mult(r))
				st = MELEE
				var dx := pt.x - p.x
				if absf(dx) > 1.5:
					face[i] = 1.0 if dx > 0.0 else -1.0
			else:
				# --- ranged
				var shooting := false
				if T_RANGED[ut] != 0 and r.fire_target != null and not r._anchor_moving and stg <= 0.0:
					var ft := r.fire_target
					if ft.alive > 0 and not ft.withdrawn:
						var tdist := p.distance_to(ft.mean_pos)
						if tdist <= r.c_fire_reach:
							if pending[i] == -1 and cooldown[i] <= 0.0 and p.distance_squared_to(slot_pos[i]) < 100.0:
								st = SHOOT
								action_t[i] = 0.0
								pending[i] = -2
								var rl := T_RELOAD[ut]
								cooldown[i] = rl * rng.randf_range(0.9, 1.15) if T_RANGED[ut] == UnitTypes.RANGED_ARROW else rl * rng.randf_range(0.97, 1.06)
							var fx := ft.mean_pos.x - p.x
							if absf(fx) > 4.0:
								face[i] = 1.0 if fx > 0.0 else -1.0
							shooting = true
				if st == SHOOT and action_t[i] > T_ACTLEN[ut]:
					st = IDLE
				# --- formation slot steering
				var sp := slot_pos[i]
				var d := sp - p
				var dist := d.length()
				var av := _r_anchor_vel[r.id]
				desired = av + d * 2.6
				var maxs := run_s
				if not r.running and not r.charging and dist < r.spacing.x * 3.0:
					maxs = walk_s * 1.45
				if desired.length() > maxs:
					desired = desired.normalized() * maxs
				if dist < 0.8 and av.length_squared() < 1.0:
					desired = Vector2.ZERO
				_r_err[r.id] += dist
				_r_free[r.id] += 1
				if st != SHOOT:
					st = MOVE if v.length() > 6.0 else IDLE
				if not shooting and v.length() < 5.0 and absf(r.facing.x) > 0.3:
					face[i] = 1.0 if r.facing.x > 0.0 else -1.0

		# --- separation (recomputed on alternate ticks)
		if not r.crowded and t < 0 and st != ROUT:
			sep[i] = Vector2.ZERO
		elif (i % 3) == sep_phase:
			var s := Vector2.ZERO
			var c := _query(p, 26.0)
			var mi := T_MASS[ut]
			for q in c:
				var j := _nb[q]
				if j == i:
					continue
				var dj := p - pos[j]
				var minr := rad + T_RAD[utype[j]]
				var d2 := dj.length_squared()
				if d2 < minr * minr:
					if d2 < 0.0001:
						dj = Vector2(float((i * 7) % 5) - 2.0, float((i * 3) % 5) - 2.0) * 0.1
						d2 = dj.length_squared() + 0.0001
					var dl2 := sqrt(d2)
					var mj := T_MASS[utype[j]]
					s += dj / dl2 * ((minr - dl2) / minr) * 150.0 * (2.0 * mj / (mi + mj))
			sep[i] = s
		desired += sep[i]

		# --- integrate
		if stg > 0.0:
			v = v.move_toward(Vector2.ZERO, 260.0 * dt)
		else:
			v = v.move_toward(desired, accel * dt)
		var np := p
		if tw > 0:
			var mult := tsp[clampi(int(p.y * tinv), 0, th - 1) * tw + clampi(int(p.x * tinv), 0, tw - 1)]
			np = p + v * dt * maxf(mult, 0.05)
			if tsp[clampi(int(np.y * tinv), 0, th - 1) * tw + clampi(int(np.x * tinv), 0, tw - 1)] <= 0.0:
				np = _slide(p, np, v)
				v = _slide_v
		else:
			np = p + v * dt
		np.x = clampf(np.x, 2.0, W - 2.0)
		np.y = clampf(np.y, 2.0, H - 2.0)
		pos[i] = np
		vel[i] = v
		var spd2 := v.length()
		# charge readiness
		if spd2 > run_s * 0.7 and t < 0 and r.engaged == 0:
			charge_ready[i] = 1   # only a run-up from outside the melee counts as a charge
		elif spd2 < run_s * 0.3:
			charge_ready[i] = 0
		# facing while moving
		if st != MELEE and st != SHOOT and spd2 > 10.0 and absf(v.x) > 0.35 * spd2:
			face[i] = 1.0 if v.x > 0.0 else -1.0
		# animation phase
		if spd2 > 6.0:
			anim_t[i] += dt * 10.0 * clampf(spd2 / walk_s, 0.6, 2.4) * anim_rate[i]
		else:
			anim_t[i] += dt * 6.0 * anim_rate[i]
		if state[i] >= DEAD:
			continue   # died during its own update (e.g. impaled charging braced spears)
		state[i] = st
		_r_sum[r.id] += np
		_r_cnt[r.id] += 1
		_r_spd[r.id] += spd2


var _slide_v := Vector2.ZERO

## Blocked by deep water: slide along whichever axis is free (sets _slide_v).
func _slide(p: Vector2, np: Vector2, v: Vector2) -> Vector2:
	var nx := Vector2(np.x, p.y)
	var ny := Vector2(p.x, np.y)
	if _speed_at(nx) > 0.0:
		_slide_v = Vector2(v.x, v.y * 0.3)
		return nx
	if _speed_at(ny) > 0.0:
		_slide_v = Vector2(v.x * 0.3, v.y)
		return ny
	_slide_v = v * 0.3
	return p


func _seek_radius(r: Regiment, ut: int) -> float:
	if r.c_ranged:
		return 38.0
	if r.charging:
		return 95.0 if T_MOUNT[ut] == 1 else 70.0
	if r.engaged > 0 or r.c_target != null:
		return 70.0
	return 42.0


func _find_enemy(i: int, p: Vector2, radius: float, r: Regiment) -> int:
	var c := _query(p, radius)
	var best := -1
	var best_d := radius * radius
	var my_team := team_of[i]
	var tgt := r.c_target
	var tgt_id := tgt.id if tgt != null else -1
	for q in c:
		var j := _nb[q]
		if team_of[j] == my_team:
			continue
		var d2 := p.distance_squared_to(pos[j])
		if reg_of[j] == tgt_id:
			d2 *= 0.7
		if d2 < best_d:
			best_d = d2
			best = j
	return best


# ---- combat -----------------------------------------------------------------------------

## Attack direction relative to the victim regiment's facing: 0 front, 1 flank, 2 rear.
func _aspect(victim_reg: Regiment, attack_dir: Vector2) -> int:
	var d := victim_reg.facing.dot(attack_dir)   # attack_dir points attacker → victim
	if d > 0.45:
		return 2
	if d > -0.35:
		return 1
	return 0


func _melee_hit(i: int, t: int, r: Regiment) -> void:
	var ut := utype[i]
	var vt := utype[t]
	var vr: Regiment = regiments[reg_of[t]]
	var dir := (pos[t] - pos[i]).normalized()
	var aspect := _aspect(vr, dir)
	var atk := T_ATK[ut] * MoraleRules.attack_mult(r)
	if aspect == 1:
		atk += 10.0
	elif aspect == 2:
		atk += 22.0
	if terrain != null:
		atk += clampf((r.height - vr.height) * 0.15, -6.0, 8.0)
	var def := T_DEF[vt] * MoraleRules.fatigue_attack_mult(vr)
	if state[t] == ROUT:
		def = 0.0
	elif stagger[t] > 0.0:
		def *= 0.5
	elif state[t] == SHOOT:
		def *= 0.6
	var p_hit := clampf(0.4 + (atk - def) * 0.007, 0.08, 0.92)
	if rng.randf() >= p_hit:
		return
	var dmg := T_DMG[ut] * rng.randf_range(0.75, 1.25)
	if T_ANTICAV[ut] > 0.0 and T_MOUNT[vt] == 1:
		dmg += T_ANTICAV[ut] * (1.25 if r.braced else 1.0)
	dmg *= 100.0 / (100.0 + T_ARM[vt])
	if aspect > 0:
		vr.morale -= MoraleRules.FLANK_HIT_SHOCK if aspect == 1 else MoraleRules.REAR_HIT_SHOCK
	damage(t, dmg, r)


func _charge(i: int, t: int, r: Regiment, spd: float, dir: Vector2) -> void:
	var ut := utype[i]
	var vt := utype[t]
	var vr: Regiment = regiments[reg_of[t]]
	var ratio := clampf(spd / T_RUN[ut], 0.0, 1.3)
	var aspect := _aspect(vr, dir)
	action_t[i] = 0.0
	cooldown[i] = T_INT[ut]
	stat_charges += 1
	var braced_front: bool = vr.braced and vr.stats["brace"] and vr.facing.dot(-dir) > -0.15 and state[t] != ROUT
	if braced_front and T_MOUNT[ut] == 0:
		# infantry rushing a hedge of braced spears: the charge is simply absorbed (no impact)
		vel[i] = vel[i] * 0.4
		return
	if braced_front:
		# braced spears: the charge breaks on the points
		stat_braced += 1
		var dmg := (T_ANTICAV[vt] * 1.5 + T_DMG[vt]) * rng.randf_range(0.85, 1.2)
		if T_MOUNT[ut] == 1:
			dmg *= 1.3
		dmg *= 100.0 / (100.0 + T_ARM[ut])
		stagger[i] = 0.8
		vel[i] = -dir * 50.0
		action_t[t] = 0.0
		_add_charge(r, pos[t], ratio * 0.3 * T_MASS[ut])
		r.morale -= 1.2
		damage(i, dmg, vr)
		return
	var dmg2 := (T_DMG[ut] + T_CHG[ut] * ratio * 0.7) * rng.randf_range(0.85, 1.2) * (1.0 + 0.25 * aspect)
	dmg2 *= 100.0 / (100.0 + T_ARM[vt])
	var impulse := minf(170.0, T_MASS[ut] * ratio * 110.0 / T_MASS[vt])
	# morale shock scales with the impact's weight relative to the victim regiment's size, so a
	# heavy cavalry charge terrifies while an infantry rush only shakes (rear hits double)
	var shock := T_CHG[ut] * ratio * T_MASS[ut] * 0.6 / maxf(10.0, float(vr.initial_men))
	vr.morale -= shock * (2.0 if aspect == 2 else 1.0)
	vel[t] = vel[t] + dir * impulse
	stagger[t] = maxf(stagger[t], 0.4 + 0.35 * ratio)
	# shove nearby enemies of the victim
	var c := _query(pos[t], 20.0)
	var my_team := team_of[i]
	for q in c:
		var j := _nb[q]
		if j == t or team_of[j] == my_team:
			continue
		if pos[j].distance_squared_to(pos[t]) < 400.0:
			vel[j] = vel[j] + dir * impulse * 0.45
			stagger[j] = maxf(stagger[j], 0.3)
	vel[i] = vel[i] * 0.55
	_add_charge(r, pos[t], ratio * T_MASS[ut])
	if rng.randf() < (0.88 if aspect == 0 else 0.97):
		damage(t, dmg2, r)


func _add_charge(r: Regiment, p: Vector2, s: float) -> void:
	r.charge_accum += s
	r.charge_accum_pos += p * s


## Apply damage to soldier t (any source). `src` = attacking regiment (may be null).
func damage(t: int, dmg: float, src: Regiment) -> void:
	if state[t] >= DEAD:
		return
	hp[t] -= dmg
	flash[t] = 0.14
	var vr: Regiment = regiments[reg_of[t]]
	vr.under_fire_t = 0.0 if src == null or src.is_ranged() else vr.under_fire_t
	if hp[t] <= 0.0:
		_kill(t, src)


func _kill(t: int, src: Regiment) -> void:
	if state[t] >= DEAD:
		return
	state[t] = DEAD
	dead_t[t] = 0.0
	face[t] = 1.0 if rng.randf() < 0.5 else -1.0   # fall either way; corpses face randomly
	flash[t] = 0.0
	target[t] = -1
	pending[t] = -1
	vel[t] = vel[t] * 0.2
	var r: Regiment = regiments[reg_of[t]]
	r.alive = maxi(0, r.alive - 1)
	r.slots_dirty = true
	MoraleRules.on_casualty(r)
	if src != null:
		src.kills_recent += 1.0
		src.kills += 1
		stat_kills[src.team] += 1
	if t == r.leader:
		r.leader = -1
	soldier_died.emit(t)
	if t == r.general_soldier:
		_on_general_killed(r.team)
	if r.alive <= 0:
		r.fire_target = null
		r.orders.clear()


func _on_general_killed(team: int) -> void:
	general_alive[team] = false
	for r in regiments:
		if r.team == team:
			r.morale -= MoraleRules.GENERAL_DEATH_SHOCK
	general_killed.emit(team)


func _flee_off(i: int, r: Regiment) -> void:
	state[i] = FLED
	target[i] = -1
	r.alive = maxi(0, r.alive - 1)
	r.slots_dirty = true


func on_regiment_withdrew(r: Regiment) -> void:
	r.withdrawn = true
	for i in r.soldiers:
		if state[i] < DEAD:
			state[i] = FLED
	if r.general_soldier >= 0:
		general_alive[r.team] = false


# ---- missiles ---------------------------------------------------------------------------

func _release_shot(i: int, r: Regiment, _pd: int) -> void:
	var ft := r.fire_target
	if ft == null or ft.alive <= 0:
		return
	var ut := utype[i]
	# aim at a random living soldier of the target regiment
	var aim := -1
	var sz := ft.soldiers.size()
	for tries in 4:
		var j := ft.soldiers[rng.randi() % sz]
		if state[j] < DEAD:
			aim = j
			break
	var p := pos[i]
	var tp := ft.mean_pos if aim < 0 else pos[aim]
	var acc := T_ACC[ut]
	if T_RANGED[ut] == UnitTypes.RANGED_ARROW:
		var dist := p.distance_to(tp)
		var flight := clampf(dist / 430.0, 0.55, 2.2)
		if aim >= 0:
			tp += vel[aim] * flight
		var scatter := 4.0 + dist * (1.0 - acc) * 0.09
		tp += Vector2.from_angle(rng.randf() * TAU) * scatter * sqrt(rng.randf())
		projectiles.spawn(p, 28.0, tp, flight, r.team, r.id, T_MDMG[ut])
		stat_arrows_fired += 1
		if time - r.last_volley_emit > 1.0:
			r.last_volley_emit = time
			volley.emit(r.mean_pos, "arrow")
	else:
		var dir := (tp - p).normalized().rotated(rng.randfn(0.0, (1.0 - acc) * 0.11))
		var origin := p + Vector2(dir.x * 12.0, -2.0)
		var max_len := T_RANGE[ut] * 1.08
		var hit := _raycast_soldier(origin, dir, max_len, r.id)
		if hit >= 0 and rng.randf() > 0.3 + acc * 0.5:
			hit = -1   # ball misses / glances off
		var end := origin + dir * max_len
		stat_gun_shots += 1
		if hit >= 0:
			end = pos[hit]
			stat_gun_hits += 1
			projectile_hit.emit(pos[hit], "gun")
			var vt := utype[hit]
			var vr: Regiment = regiments[reg_of[hit]]
			var dmg := T_MDMG[ut] * rng.randf_range(0.8, 1.25) * 100.0 / (100.0 + T_ARM[vt] * 0.35)
			vr.morale -= MoraleRules.GUN_HIT_SHOCK * (1.5 if T_MOUNT[vt] == 1 else 1.0)
			vr.under_fire_t = 0.0
			damage(hit, dmg, r)
		shot_fx.append([origin, end, time, hit >= 0])
		if time - r.last_volley_emit > 1.0:
			r.last_volley_emit = time
			volley.emit(r.mean_pos, "gun")
			if ft.alive > 0:
				ft.morale -= MoraleRules.GUN_VOLLEY_SHOCK * (1.5 if ft.is_mounted() else 1.0)


func _raycast_soldier(origin: Vector2, dir: Vector2, max_len: float, skip_reg: int) -> int:
	var best := -1
	var best_t := max_len
	var last_cell := -1
	var s := 0.0
	var inv := 1.0 / CELL
	while s < best_t + CELL:
		var sp := origin + dir * s
		s += 12.0
		var cx := int(sp.x * inv)
		var cy := int(sp.y * inv)
		if cx < 0 or cy < 0 or cx >= gw or cy >= gh:
			break
		var cell := cy * gw + cx
		if cell == last_cell:
			continue
		last_cell = cell
		var k := cell_start[cell]
		if k < 0:
			continue
		while k < hs_count and hs_cell[k] == cell:
			var j := hs_ids[k]
			k += 1
			if reg_of[j] == skip_reg or state[j] >= DEAD:
				continue
			var rel := pos[j] - origin
			var t := rel.dot(dir)
			if t <= 0.0 or t >= best_t:
				continue
			if absf(rel.cross(dir)) < T_RAD[utype[j]] + 1.5:
				best_t = t
				best = j
	return best


## Called by Projectiles when an arrow lands.
func arrow_impact(p: Vector2, shooter_team: int, _reg_id: int, dmg: float, _v: Vector2) -> void:
	var c := _query(p, 14.0)
	var best := -1
	var best_d := INF
	for q in c:
		var j := _nb[q]
		if team_of[j] == shooter_team:
			continue
		var d2 := pos[j].distance_squared_to(p)
		var rr := T_RAD[utype[j]] + 2.5
		if d2 < rr * rr and d2 < best_d:
			best_d = d2
			best = j
	if best < 0:
		return
	if terrain != null and terrain.is_forest(p) and rng.randf() < 0.5:
		return
	if rng.randf() < 0.2 + T_ARM[utype[best]] * 0.004:
		return   # glances off armour / sticks in a sleeve
	var vt := utype[best]
	var d := dmg * rng.randf_range(0.8, 1.2) * 100.0 / (100.0 + T_ARM[vt] * 1.2)
	if state[best] == ROUT:
		d *= 1.2
	stat_arrow_hits += 1
	projectile_hit.emit(p, "arrow")
	var vr: Regiment = regiments[reg_of[best]]
	vr.under_fire_t = 0.0
	var src: Regiment = regiments[_reg_id] if _reg_id >= 0 and _reg_id < regiments.size() else null
	damage(best, d, src)


# ---- morale, rout, signals ------------------------------------------------------------

func _regiment_post(dt: float) -> void:
	for r in regiments:
		if r.alive <= 0 or r.withdrawn:
			continue
		if r.charge_accum > 0.0:
			if time - r.last_charge_emit > 0.4:
				r.last_charge_emit = time
				charge_impact.emit(r.charge_accum_pos / r.charge_accum, r.charge_accum)
			r.charge_accum = 0.0
			r.charge_accum_pos = Vector2.ZERO
		var aura := false
		var g: int = general_idx[r.team]
		if general_alive[r.team] and g >= 0 and state[g] < DEAD:
			aura = pos[g].distance_to(r.mean_pos) < 420.0
		MoraleRules.tick(r, dt, aura, r.height > 25.0)
		if r.is_routing():
			_tick_rout(r, dt, aura)
		elif r.morale < MoraleRules.ROUT_BELOW:
			_rout(r)


func _rout(r: Regiment) -> void:
	r.rout_count += 1
	var ratio := float(r.alive) / maxf(1.0, float(r.initial_men))
	r.state = Regiment.Morale.SHATTERED if (r.rout_count >= 3 or ratio < 0.25) else Regiment.Morale.ROUTING
	r.orders.clear()
	r.fire_target = null
	r.charging = false
	r.running = true
	r.rout_time = 0.0
	r.morale = minf(r.morale, 8.0)
	for i in r.soldiers:
		if state[i] < DEAD:
			state[i] = ROUT
			target[i] = -1
			pending[i] = -1
	regiment_routed.emit(r)
	for f in regiments:
		if f != r and f.team == r.team and not f.is_routing() and f.alive > 0:
			if f.mean_pos.distance_to(r.mean_pos) < MoraleRules.NEAR_ROUT_RADIUS:
				f.morale -= MoraleRules.NEAR_ROUT_SHOCK * (1.5 if r.type == UnitTypes.GENERAL else 1.0)


func _tick_rout(r: Regiment, dt: float, aura: bool) -> void:
	r.rout_time += dt
	if r.state == Regiment.Morale.SHATTERED:
		return
	if r.nearest_enemy_dist > 300.0:
		r.morale += (4.0 + (5.0 if aura else 0.0)) * dt
	var ratio := float(r.alive) / maxf(1.0, float(r.initial_men))
	if ratio < 0.25:
		r.state = Regiment.Morale.SHATTERED
		return
	if r.morale >= MoraleRules.RALLY_AT and r.rout_time > 6.0:
		_rally(r)


func _rally(r: Regiment) -> void:
	r.state = Regiment.Morale.WAVERING
	r.morale = MoraleRules.RALLY_AT
	r.running = false
	r.centre = r.mean_pos
	if r.nearest_enemy != null:
		r.facing = (r.nearest_enemy.mean_pos - r.mean_pos).normalized()
	else:
		r.facing = -_home[r.team]
	for i in r.soldiers:
		if state[i] == ROUT:
			state[i] = IDLE
	r.orders.clear()
	r.dest_centre = r.centre
	r.dest_facing = r.facing
	r.assign_slots(r.centre, r.facing, r.files)
	_r_prev_centre[r.id] = r.centre
	regiment_rallied.emit(r)


## Men still standing (not routing / shattered / withdrawn) and the team's starting strength.
func team_strength(team: int) -> Vector2i:
	var standing := 0
	var initial := 0
	for r in regiments:
		if r.team != team:
			continue
		initial += r.initial_men
		if not r.is_out() and not r.is_routing():
			standing += r.alive
	return Vector2i(standing, initial)


## Public: true when the team has lost (TW rule: every regiment routing, shattered, withdrawn
## or dead; or the general is dead and under 35% of the army still stands).
func team_broken(team: int) -> bool:
	var any := false
	var standing := 0
	var initial := 0
	for r in regiments:
		if r.team != team:
			continue
		any = true
		initial += r.initial_men
		if not r.is_out() and not r.is_routing():
			standing += r.alive
	if not any:
		return true
	if standing == 0:
		return true
	if not general_alive[team] and float(standing) < float(initial) * 0.35:
		return true
	return false


func _check_victory() -> void:
	if ended:
		return
	# army-wide collapse: remnants under 15% of the starting army rout with the rest
	for team in 2:
		var st := team_strength(team)
		if st.x > 0 and float(st.x) < float(st.y) * 0.15:
			for r in regiments:
				if r.team == team and not r.is_out() and not r.is_routing():
					_rout(r)
	var b0 := team_broken(0)
	var b1 := team_broken(1)
	if not b0 and not b1:
		return
	ended = true
	if b0 and b1:
		winner = 0 if men_alive(0, false) >= men_alive(1, false) else 1
	else:
		winner = 1 if b0 else 0
	battle_ended.emit(winner)

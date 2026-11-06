class_name Regiment
extends RefCounted
## A regiment: a formation of soldiers owned by one team. The soldiers themselves live in
## BattleSim's struct-of-arrays; a Regiment holds indices into them plus formation, orders,
## morale and fatigue.
##
## ===================================================================================
##  ORDER API (used by the player Commander and by AI generals; no cheating, same calls)
## ===================================================================================
##  Orders (all return immediately; the sim executes them over the following ticks):
##    order_move(dest: Vector2, facing := Vector2.ZERO, files := 0, run := false, queue := false)
##        Move the formation centre to `dest`. `facing` is the final facing (unit vector);
##        ZERO = face the direction of travel. `files` = frontage in men (0 = keep current).
##        `queue` appends after the current order (shift-click behaviour).
##        Routes around impassable water automatically (via fords, narrowing to a column).
##    order_attack(target: Regiment, run := false, queue := false)
##        Melee units close in and fight (auto-charge when close). Ranged units walk until the
##        target is in range, halt and shoot. Completes when the target is destroyed/shattered,
##        or when it routs (only cavalry and the general keep pursuing routers).
##    order_halt()            Stop where you stand and reform; clears the order queue.
##    order_withdraw()        Run for your own map edge and leave the battle (no morale hit).
##    set_running(on)         Run/walk toggle for the current and future orders.
##    set_fire_at_will(on)    Ranged units auto-pick targets in range when not ordered.
##
##  Queries:
##    centre, facing (unit Vector2), files, alive, initial_men, morale (0..100), fatigue (0..1),
##    state (Morale enum), team, type (UnitTypes index), type_key, stats (Dictionary),
##    is_routing(), is_broken(), is_engaged(), is_moving(), is_idle(), current_order(),
##    target(): Regiment or null, get_range(), width(), depth(), mean_pos, leader (soldier index).
##
##  Sim-level helpers for AI code (BattleSim, group "sim"):
##    sim.regiments, sim.regiments_of(team), sim.enemies_of(team), sim.general_of(team),
##    sim.regiment_at(world_pos), sim.terrain (height/forest/water queries).
## ===================================================================================

enum Morale { EAGER, STEADY, WAVERING, ROUTING, SHATTERED }
enum Order { MOVE, ATTACK, HALT, WITHDRAW }

const MORALE_NAMES := ["Eager", "Steady", "Wavering", "Routing", "Shattered"]

var sim: Node = null   # BattleSim (untyped to avoid a cyclic class reference)
var id := 0
var team := 0
var type := 0
var type_key := ""
var stats: Dictionary = {}
var display_name := ""
var soldiers := PackedInt32Array()   # all soldier indices, including the dead
var initial_men := 0
var alive := 0
var general_soldier := -1             # only for the general's regiment

# --- formation ---------------------------------------------------------------------
var centre := Vector2.ZERO            # formation anchor (block centre)
var facing := Vector2.RIGHT           # current formation facing
var files := 10                       # current frontage
var spacing := Vector2(14, 15)        # x: between files, y: between ranks
var dest_centre := Vector2.ZERO
var dest_facing := Vector2.RIGHT
var dest_files := 10
var route := PackedVector2Array()
var route_narrow := PackedFloat32Array()  # per waypoint: max frontage width (px) on the leg ending there, 0 = none
var route_i := 0
var travel_files := 0                 # temporary frontage override while crossing a ford (0 = none)
var leader := -1
var slot_n := 0                       # number of slots in the last assignment
var slots_dirty := true
var _slot_timer := 0.0

# --- orders ------------------------------------------------------------------------
var orders: Array[Dictionary] = []
var running := false
var fire_at_will := true
var braced := false
var fire_target: Regiment = null
var charging := false                 # attack order within charge distance
var withdrawn := false

# --- state written by the sim each tick -----------------------------------------------
var mean_pos := Vector2.ZERO
var cohesion := 0.0                   # mean distance of free soldiers to their slots
var engaged := 0                      # soldiers in melee this tick
var avg_speed := 0.0
var nearest_enemy: Regiment = null
var nearest_enemy_dist := INF
var height := 0.0
# per-tick caches filled by the sim (avoid dictionary look-ups in the soldier loop)
var c_speed_mult := 1.0
var c_target: Regiment = null
var c_ranged := false
var c_fire_reach := -1.0
var crowded := true                   # another regiment is close (sim enables separation)

# --- morale / fatigue --------------------------------------------------------------
var morale := 50.0
var fatigue := 0.0
var state := Morale.STEADY
var rout_count := 0
var rout_time := 0.0
var under_fire_t := 99.0
var losses_recent := 0.0
var kills_recent := 0.0
var last_contact_emit := -99.0
var last_volley_emit := -99.0
var last_charge_emit := -99.0
var charge_accum := 0.0
var charge_accum_pos := Vector2.ZERO
var was_engaged := false

# --- player-side presentation flags ---------------------------------------------------
var selected := false
var group := -1


func _init(p_sim: Node, p_id: int, p_team: int, p_type: int) -> void:
	sim = p_sim
	id = p_id
	team = p_team
	type = p_type
	type_key = UnitTypes.key_of(p_type)
	stats = UnitTypes.get_stats(p_type)
	display_name = stats["name"]
	spacing = stats["spacing"]
	files = stats["files"]
	morale = stats["morale_base"]


# =====================================================================================
#  Order API
# =====================================================================================

func order_move(dest: Vector2, p_facing := Vector2.ZERO, p_files := 0, run := false, queue := false) -> void:
	if is_broken() or withdrawn:
		return
	var o := {"type": Order.MOVE, "pos": dest, "facing": p_facing, "files": p_files, "run": run}
	_push_order(o, queue)


func order_attack(target_reg: Regiment, run := false, queue := false) -> void:
	if is_broken() or withdrawn or target_reg == null or target_reg.team == team:
		return
	var o := {"type": Order.ATTACK, "target": target_reg, "run": run}
	_push_order(o, queue)


func order_halt() -> void:
	if is_broken() or withdrawn:
		return
	orders.clear()
	_halt_here()


func order_withdraw() -> void:
	if is_broken() or withdrawn:
		return
	var edge_x: float = 20.0 if sim.home_dir(team).x < 0.0 else sim.map_size.x - 20.0
	var dest := Vector2(edge_x, clampf(centre.y, 40.0, sim.map_size.y - 40.0))
	orders.clear()
	_push_order({"type": Order.WITHDRAW, "pos": dest, "facing": Vector2.ZERO, "files": 0, "run": true}, false)


func set_running(on: bool) -> void:
	running = on
	if not orders.is_empty():
		orders[0]["run"] = on


func set_fire_at_will(on: bool) -> void:
	fire_at_will = on


# =====================================================================================
#  Queries
# =====================================================================================

func current_order() -> Dictionary:
	return orders[0] if not orders.is_empty() else {}


func target() -> Regiment:
	if orders.is_empty() or orders[0]["type"] != Order.ATTACK:
		return null
	return orders[0]["target"]


func is_routing() -> bool:
	return state == Morale.ROUTING or state == Morale.SHATTERED


func is_broken() -> bool:
	return state == Morale.ROUTING or state == Morale.SHATTERED or alive <= 0


func is_out() -> bool:
	## True when the regiment no longer counts for victory (shattered, dead, or left the field).
	return state == Morale.SHATTERED or alive <= 0 or withdrawn


func is_engaged() -> bool:
	return engaged > 0


func is_moving() -> bool:
	## True while the formation anchor travels or the men are still walking into place.
	if is_broken():
		return false
	return _anchor_moving or avg_speed > speed_walk() * 0.35


func is_idle() -> bool:
	return orders.is_empty()


func is_ranged() -> bool:
	return stats["ranged"] != UnitTypes.RANGED_NONE


func is_mounted() -> bool:
	return stats["mounted"]


func get_range() -> float:
	return stats["range"]


func ranks() -> int:
	var f := maxi(1, _eff_files())
	return maxi(1, ceili(float(maxi(alive, 1)) / f))


func width() -> float:
	return float(mini(_eff_files(), maxi(alive, 1)) - 1) * spacing.x


func depth() -> float:
	return float(ranks() - 1) * spacing.y


func morale_name() -> String:
	return MORALE_NAMES[state]


func speed_walk() -> float:
	return stats["speed_walk"]


func _eff_files() -> int:
	var f := files
	if travel_files > 0:
		f = mini(f, travel_files)
	return maxi(1, mini(f, maxi(alive, 1)))


# =====================================================================================
#  Formation geometry
# =====================================================================================

## Offset of slot k (0 = front-left) for a block of `n` men with `f` files, facing `fwd`.
static func slot_offset(k: int, n: int, f: int, fwd: Vector2, sp: Vector2) -> Vector2:
	f = maxi(1, mini(f, maxi(n, 1)))
	var nranks := ceili(float(n) / f)
	var rank := k / f
	var file := k % f
	var in_rank := f if rank < nranks - 1 else n - rank * f
	var x := (float(file) - float(in_rank - 1) * 0.5) * sp.x
	var y := float(rank) * sp.y - float(nranks - 1) * sp.y * 0.5
	var right := Vector2(-fwd.y, fwd.x)
	return right * x - fwd * y


## World positions of every slot for a hypothetical formation (used for ghost previews).
func preview_slots(c: Vector2, fwd: Vector2, f: int, n := -1) -> PackedVector2Array:
	if n < 0:
		n = alive
	var out := PackedVector2Array()
	out.resize(n)
	for k in n:
		out[k] = c + slot_offset(k, n, f, fwd, spacing)
	return out


## Reassigns alive soldiers to slots of the frame (c, fwd, f) so nobody crosses: sort by depth
## into ranks, then by lateral position into files.
func assign_slots(c: Vector2, fwd: Vector2, f: int) -> void:
	var pos: PackedVector2Array = sim.pos
	var st: PackedInt32Array = sim.state
	var alive_ids := PackedInt32Array()
	for i in soldiers:
		if st[i] < BattleSim.DEAD:
			alive_ids.append(i)
	var n := alive_ids.size()
	alive = n
	if n == 0:
		leader = -1
		return
	f = maxi(1, mini(f, n))
	var right := Vector2(-fwd.y, fwd.x)
	var keys := PackedInt64Array()
	keys.resize(n)
	for k in n:
		var d := -(pos[alive_ids[k]] - c).dot(fwd)
		keys[k] = (int(d * 4.0) + 1_000_000) * 1024 + k
	keys.sort()
	var new_slot := PackedInt32Array()
	new_slot.resize(n)
	var rank_start := 0
	while rank_start < n:
		var cnt := mini(f, n - rank_start)
		var lk := PackedInt64Array()
		lk.resize(cnt)
		for q in cnt:
			var k: int = keys[rank_start + q] & 1023
			var u := (pos[alive_ids[k]] - c).dot(right)
			lk[q] = (int(u * 4.0) + 1_000_000) * 1024 + k
		lk.sort()
		for q in cnt:
			var k2: int = lk[q] & 1023
			new_slot[k2] = rank_start + q
		rank_start += cnt
	pos = PackedVector2Array()
	st = PackedInt32Array()
	sim.apply_slots(alive_ids, new_slot)
	slot_n = n
	# leader = front-centre soldier (or the general himself)
	leader = -1
	var front_mid := mini(f, n) / 2
	if general_soldier >= 0 and alive_ids.has(general_soldier):
		leader = general_soldier
	else:
		for k in n:
			if new_slot[k] == front_mid:
				leader = alive_ids[k]
				break
	slots_dirty = false
	_slot_timer = 0.0


# =====================================================================================
#  Order execution (called by the sim every tick, before soldiers steer)
# =====================================================================================

var _anchor_moving := false
var _route_timer := 0.0
var _last_files_applied := -1

func _push_order(o: Dictionary, queue: bool) -> void:
	if queue and not orders.is_empty():
		orders.append(o)
		return
	orders.clear()
	orders.append(o)
	running = o.get("run", false)
	_begin_order()


func _begin_order() -> void:
	route = PackedVector2Array()
	route_narrow = PackedFloat32Array()
	route_i = 0
	travel_files = 0
	charging = false
	if orders.is_empty():
		return
	var o: Dictionary = orders[0]
	match o["type"]:
		Order.MOVE, Order.WITHDRAW:
			var dest: Vector2 = o["pos"]
			dest_centre = dest
			var fwd: Vector2 = o["facing"]
			if fwd.length_squared() < 0.01:
				fwd = (dest - centre)
				fwd = fwd.normalized() if fwd.length() > 4.0 else facing
			dest_facing = fwd.normalized()
			var nf: int = o["files"]
			dest_files = nf if nf > 0 else files
			_plan_route(dest)
			var travel := dest - centre
			if travel.length() < maxf(depth() * 1.5, 70.0):
				# Short move / re-facing: go straight into the final frame.
				facing = dest_facing
				files = dest_files
				assign_slots(dest_centre, facing, files)
			else:
				var tdir := (route[0] - centre).normalized() if route.size() > 0 else travel.normalized()
				if absf(facing.angle_to(tdir)) > 0.6:
					facing = tdir
				assign_slots(centre, facing, _eff_files())
		Order.ATTACK:
			_route_timer = 0.0
		Order.HALT:
			_halt_here()


func _plan_route(dest: Vector2) -> void:
	route = PackedVector2Array()
	route_narrow = PackedFloat32Array()
	route_i = 0
	if sim.terrain != null:
		var r: Dictionary = sim.terrain.find_route(centre, dest)
		route = r["points"]
		route_narrow = r["narrow"]
	else:
		route.append(dest)
		route_narrow.append(0.0)


func _halt_here() -> void:
	orders.clear()
	running = false
	charging = false
	travel_files = 0
	route = PackedVector2Array()
	_anchor_moving = false
	if alive > 0:
		centre = mean_pos if mean_pos != Vector2.ZERO else centre
		dest_centre = centre
		dest_facing = facing
		assign_slots(centre, facing, files)


func _complete_order() -> void:
	if not orders.is_empty():
		orders.pop_front()
	if orders.is_empty():
		charging = false
		travel_files = 0
		_anchor_moving = false
	else:
		_begin_order()


func move_speed() -> float:
	var s: float = stats["speed_run"] if (running or charging) else stats["speed_walk"]
	s *= sim.fatigue_speed_mult(self)
	if sim.terrain != null:
		s *= clampf(sim.terrain.speed_mult(centre), 0.45, 1.2)
	# cohesion: wait for stragglers so the block moves as one
	var lag := cohesion / maxf(spacing.x, 1.0)
	s *= clampf(1.6 - lag * 0.35, 0.35, 1.0)
	return s


func tick_orders(dt: float) -> void:
	_anchor_moving = false
	_slot_timer += dt
	# casualty refill: at most every ~0.5 s, staggered by id so regiments don't all re-sort at once
	if slots_dirty and _slot_timer > 0.5 and engaged == 0 and (sim.tick_count + id) % 8 == 0:
		assign_slots(centre, facing, _eff_files())
	if is_broken() or withdrawn:
		return
	if orders.is_empty():
		braced = stats["brace"] and avg_speed < 25.0
		return
	braced = false
	var o: Dictionary = orders[0]
	match o["type"]:
		Order.MOVE, Order.WITHDRAW:
			_tick_move(dt)
		Order.ATTACK:
			_tick_attack(dt, o)
		_:
			_complete_order()


func _tick_move(dt: float) -> void:
	if route_i >= route.size():
		_arrive()
		return
	var to := route[route_i]
	var d := to - centre
	var dist := d.length()
	var remaining := dist
	for k in range(route_i + 1, route.size()):
		remaining += route[k].distance_to(route[k - 1])
	# narrow to a column on fording legs
	var narrow := route_narrow[route_i] if route_i < route_narrow.size() else 0.0
	var want_tf := 0
	if narrow > 0.0:
		want_tf = maxi(2, int(narrow / spacing.x))
	if want_tf != travel_files:
		travel_files = want_tf
		assign_slots(centre, facing, _eff_files())
	var arrive_dist := maxf(depth() * 1.2 + 20.0, 60.0)
	if remaining <= arrive_dist and route_i == route.size() - 1 and travel_files == 0:
		# final approach: switch into the destination frame once
		if files != dest_files or facing.dot(dest_facing) < 0.999:
			files = dest_files
			facing = dest_facing
			assign_slots(dest_centre, facing, files)
	elif dist > 1.0:
		var tdir := d / dist
		var ang := facing.angle_to(tdir)
		if absf(ang) > 0.8:
			facing = tdir
			assign_slots(centre, facing, _eff_files())
		else:
			facing = facing.rotated(clampf(ang, -1.6 * dt, 1.6 * dt))
	var step := move_speed() * dt
	if dist <= step:
		centre = to
		route_i += 1
		_anchor_moving = true
		if route_i >= route.size():
			_arrive()
	else:
		centre += d / dist * step
		_anchor_moving = true


func _arrive() -> void:
	centre = dest_centre
	facing = dest_facing
	if files != dest_files or travel_files != 0:
		travel_files = 0
		files = dest_files
		assign_slots(centre, facing, files)
	travel_files = 0
	var o := current_order()
	if not o.is_empty() and o["type"] == Order.WITHDRAW:
		sim.on_regiment_withdrew(self)
	_complete_order()


func _tick_attack(dt: float, o: Dictionary) -> void:
	var t: Regiment = o["target"]
	if t == null or t.alive <= 0 or t.state == Morale.SHATTERED or t.withdrawn:
		_finish_attack()
		return
	if t.state == Morale.ROUTING and not is_mounted():
		_finish_attack()
		return
	var tc := t.mean_pos
	var to_t := tc - centre
	var dist := to_t.length()
	var dir := to_t / maxf(dist, 0.001)
	if is_ranged():
		fire_target = t
		var r: float = sim.effective_range(self, t)
		if dist > r * 0.92:
			_approach(dt, tc, dir, false)
		else:
			# in range: hold and face the target
			var ang := facing.angle_to(dir)
			if absf(ang) > 0.9:
				facing = dir
				assign_slots(centre, facing, files)
			else:
				facing = facing.rotated(clampf(ang, -1.2 * dt, 1.2 * dt))
		return
	# melee: close in; auto-charge inside charge distance
	var charge_dist := 260.0 if is_mounted() else 150.0
	charging = dist < charge_dist + t.depth() * 0.5
	var contact := dist < (depth() + t.depth()) * 0.5 + 18.0
	if engaged > 0 and engaged * 3 >= alive:
		# the fight has started: hold the anchor where the men are, let them brawl
		centre = centre.lerp(mean_pos, 0.05)
		return
	if contact and engaged > 0:
		return
	_approach(dt, tc, dir, true)


func _approach(dt: float, tc: Vector2, dir: Vector2, melee: bool) -> void:
	_route_timer -= dt
	if _route_timer <= 0.0 or route_i >= route.size():
		_route_timer = 1.0
		_plan_route(tc)
	var to := route[mini(route_i, route.size() - 1)]
	var d := to - centre
	var dist := d.length()
	var tdir := d / maxf(dist, 0.001)
	var ang := facing.angle_to(tdir)
	if absf(ang) > 0.8:
		facing = tdir
		assign_slots(centre, facing, files)
	else:
		facing = facing.rotated(clampf(ang, -1.6 * dt, 1.6 * dt))
	var narrow := route_narrow[mini(route_i, route_narrow.size() - 1)] if route_narrow.size() > 0 else 0.0
	var want_tf := maxi(2, int(narrow / spacing.x)) if narrow > 0.0 else 0
	if want_tf != travel_files:
		travel_files = want_tf
		assign_slots(centre, facing, _eff_files())
	var step := move_speed() * dt
	if dist <= step:
		centre = to
		if route_i < route.size() - 1:
			route_i += 1
	else:
		centre += tdir * step
	_anchor_moving = true


func _finish_attack() -> void:
	fire_target = null
	charging = false
	orders.pop_front()
	if orders.is_empty():
		_halt_here()
	else:
		_begin_order()


## Called by the sim when the fight around this regiment ends and it has no orders: reform
## where the men stand.
func reform_here() -> void:
	if alive <= 0:
		return
	centre = mean_pos
	assign_slots(centre, facing, files)

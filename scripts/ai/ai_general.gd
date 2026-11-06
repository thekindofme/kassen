class_name AIGeneral
extends Node2D
## Enemy warlord (GDD §6). Commands one team through the public Regiment order API only
## (order_move / order_attack / order_halt / order_withdraw / set_running / set_fire_at_will)
## and observable sim state (positions, facings, morale states). It never reads the other
## side's orders. The only "cheat" is a small difficulty-scaled morale bonus at battle start.
##
## Three layers, all driven by sim time (works with any time_scale and with manual stepping):
##   1. Strategy (every ~2 s): posture ATTACK / DEFEND / SKIRMISH from relative strength
##      (men × quality × morale), ranged balance, terrain (ford / high ground) and difficulty.
##   2. Group tactics: a battle line facing the enemy centre of mass (yari + samurai), missiles
##      screening ahead then retiring behind the line, cavalry on the wings hunting missiles,
##      flanks, rears and routers, the general behind the line. Crosses rivers only at the ford.
##   3. Unit micro (per regiment, staggered on the think tick): archers kite, gunners hold fire
##      until effective range, spears brace against approaching cavalry, cavalry cycle-charge,
##      wavering units fall back to the general.
##
## Usage: var ai := AIGeneral.new(); ai.sim = sim; ai.team = 1; add_child(ai)
## Headless tests may set `auto = false` and call `update()` after stepping the sim.

enum Posture { ATTACK, DEFEND, SKIRMISH }
const POSTURE_NAMES := ["ATTACK", "DEFEND", "SKIRMISH"]
enum CavState { WING, STAGE, CHARGE, DISENGAGE }

## Unit quality per soldier (relative fighting value) indexed by UnitTypes enum.
const QUALITY := [1.0, 0.8, 0.9, 2.2, 2.6, 4.0]

const DIFF := {
	"easy":   {"react": 0.9, "aggression": 0.7, "flank_radius": 550.0, "morale_bonus": -4.0, "engage": 170.0, "patience": 90.0},
	"normal": {"react": 0.5, "aggression": 1.0, "flank_radius": 850.0, "morale_bonus": 0.0, "engage": 220.0, "patience": 55.0},
	"hard":   {"react": 0.3, "aggression": 1.25, "flank_radius": 1200.0, "morale_bonus": 6.0, "engage": 260.0, "patience": 35.0},
}

var sim: BattleSim
var team := 1
@export_enum("easy", "normal", "hard") var difficulty := "normal"
@export var debug_draw := false
var auto := true                   # drive itself from _process
var start_delay := 3.0
var think_interval := 0.5          # base think tick; scaled by difficulty "react"
var strategy_interval := 2.0
var verbose := true                # print posture changes

# --- strategic state -----------------------------------------------------------------
var posture := Posture.ATTACK
var posture_since := 0.0
var all_out := false               # enemy broken: everybody attacks
var line_anchor := Vector2.ZERO    # centre of our battle line (target)
var line_fwd := Vector2.LEFT       # facing of the battle line
var enemy_com := Vector2.ZERO
var my_com := Vector2.ZERO
var strength_ratio := 1.0
var ranged_ratio := 1.0
var ford := Vector2.INF
var ford_a := Vector2.INF
var ford_b := Vector2.INF
var high_ground := Vector2.INF
var crossing := false              # the river lies between us and the enemy
var contact := false               # lines are close
var general_withdrawn := false
## ATTACK sub-phase: "approach" (dress the line and close to bow range), "soften" (line halts
## out of reach while the archers shoot), "assault" (every line regiment charges together).
var phase := "approach"
var phase_since := 0.0
var line_ready := true             # every free line regiment is near its slot
var _stand_reached := false

# --- per-regiment state (keyed by regiment id) ---------------------------------------
var _next_think := {}              # id -> sim time of its next micro think
var _dest := {}                    # id -> [pos, facing] of the last move we issued
var _intent := {}                  # id -> [from, to, colour] for debug drawing
var _cav := {}                     # id -> {"s": CavState, "t": time, "target": Regiment}
var _enemy_prev := {}              # enemy id -> [pos, time] (velocity estimate from observation)
var _enemy_vel := {}               # enemy id -> Vector2
var _next_strategy := 0.0
var _started := false
var _deployed := false
var _side_fords: Array = []         # secondary fords: {"a", "b", "guard": Regiment, "quiet": time}
var _flank_logged := false
var _soften_men := Vector2.ZERO     # (our men, enemy men) when softening began
var hint_posture := ""              # map's ai_hints["posture"] ("attack" / "defend")
var _line_slots := {}              # id -> Vector2 slot centre on the line

# --- metrics for QA / tests ----------------------------------------------------------
var stats := {"posture_changes": 0, "cav_charges": 0, "cav_charge_aspects": [], "cav_target_types": [],
	"cav_disengages": 0, "braces": 0, "kites": 0, "fallbacks": 0, "general_commits": 0}


func _cfg(key: String) -> float:
	return DIFF.get(difficulty, DIFF["normal"])[key]


func _process(_delta: float) -> void:
	if auto:
		update()
	if debug_draw:
		queue_redraw()


## Called by battle.gd's fast-forward path; same as update().
func think() -> void:
	update()


func update() -> void:
	if sim == null:
		return
	if sim.deploying:
		if not _deployed:
			deploy()
		return
	if sim.paused or sim.ended or sim.time < start_delay:
		return
	if not _started:
		_start()
	_observe_enemies()
	if sim.time >= _next_strategy:
		_next_strategy = sim.time + strategy_interval * (_cfg("react") / 0.5)
		_strategy()
	var mine := sim.regiments_of(team)
	for r in mine:
		if r.is_broken() or r.withdrawn:
			continue
		if sim.time >= float(_next_think.get(r.id, 0.0)):
			_next_think[r.id] = sim.time + think_interval * (_cfg("react") / 0.5)
			_think_regiment(r)


func _start() -> void:
	_started = true
	var mine := sim.regiments_of(team)
	var n := maxi(1, mine.size())
	for k in mine.size():
		var r := mine[k]
		# stagger: spread first thinks over one think interval so not all re-plan together
		_next_think[r.id] = sim.time + think_interval * float(k) / n
		r.morale = clampf(r.morale + _cfg("morale_bonus"), 0.0, 100.0)
	_next_strategy = sim.time
	_read_map()
	_log("AIGeneral online: team %d, difficulty %s, ford %s, high ground %s, map posture %s" % [team, difficulty, ford, high_ground, hint_posture])


var _map_read := false

func _read_map() -> void:
	if _map_read:
		return
	_map_read = true
	var tm = sim.terrain
	if tm != null and tm.map != null:
		var m: MapDef = tm.map
		if not m.fords.is_empty():
			ford_a = m.fords[0]["a"]
			ford_b = m.fords[0]["b"]
			ford = (ford_a + ford_b) * 0.5
		var hints: Dictionary = m.ai_hints
		if hints.has("ford"):
			ford = hints["ford"]
		if hints.has("high_ground"):
			high_ground = hints["high_ground"]
		hint_posture = m.ai_posture_hint if m.ai_posture_hint != "" else hints.get("posture", "")
		for k in range(1, m.fords.size()):
			_side_fords.append({"a": m.fords[k]["a"], "b": m.fords[k]["b"], "guard": null, "quiet": 0.0})


func _log(msg: String) -> void:
	if verbose:
		print("[AI t=%.1f] %s" % [sim.time, msg])


# =====================================================================================
#  Observation helpers (only what anyone can see on the field)
# =====================================================================================

func _observe_enemies() -> void:
	for e in sim.enemies_of(team):
		if e.alive <= 0 or e.withdrawn:
			continue
		var prev = _enemy_prev.get(e.id)
		if prev != null:
			var dt: float = sim.time - float(prev[1])
			if dt >= 0.25:
				var v: Vector2 = (e.mean_pos - prev[0]) / dt
				_enemy_vel[e.id] = _enemy_vel.get(e.id, v).lerp(v, 0.6)
				_enemy_prev[e.id] = [e.mean_pos, sim.time]
		else:
			_enemy_prev[e.id] = [e.mean_pos, sim.time]
			_enemy_vel[e.id] = Vector2.ZERO


func enemy_velocity(e: Regiment) -> Vector2:
	return _enemy_vel.get(e.id, Vector2.ZERO)


static func power(r: Regiment) -> float:
	if r.is_broken() or r.withdrawn:
		return 0.0
	var m := clampf(r.morale / 60.0, 0.4, 1.3)
	var f := 1.0 - 0.3 * r.fatigue
	return float(r.alive) * QUALITY[r.type] * m * f


func _standing(regs: Array[Regiment]) -> Array[Regiment]:
	var out: Array[Regiment] = []
	for r in regs:
		if not r.is_broken() and not r.withdrawn:
			out.append(r)
	return out


func _com(regs: Array[Regiment], skip_general := true) -> Vector2:
	var c := Vector2.ZERO
	var w := 0.0
	for r in regs:
		if skip_general and r.type == UnitTypes.GENERAL:
			continue
		c += r.mean_pos * float(r.alive)
		w += float(r.alive)
	if w <= 0.0:
		for r in regs:
			c += r.mean_pos
			w += 1.0
	return c / maxf(w, 1.0)


func _blocked(a: Vector2, b: Vector2) -> bool:
	return sim.terrain != null and sim.terrain.segment_blocked(a, b)


## True if the straight path a→b crosses the river (deep water or the ford itself).
func _river_between(a: Vector2, b: Vector2) -> bool:
	if sim.terrain == null:
		return false
	var steps := int(a.distance_to(b) / 16.0) + 1
	for s in steps + 1:
		var p := a.lerp(b, float(s) / steps)
		if sim.terrain.is_water(p) or sim.terrain.is_ford(p):
			return true
	return false


func _water(p: Vector2) -> bool:
	return sim.terrain != null and sim.terrain.is_water(p)


# =====================================================================================
#  Layer 1: strategy / posture
# =====================================================================================

var _impatient := false            # enemy sat passive too long: stop waiting, go and get him

func _strategy() -> void:
	var mine_all := sim.regiments_of(team)
	var en_all := sim.enemies_of(team)
	var mine := _standing(mine_all)
	var enemies := _standing(en_all)
	if enemies.is_empty() or mine.is_empty():
		return
	var my_p := 0.0
	var en_p := 0.0
	var my_r := 0.0
	var en_r := 0.0
	var en_init := 0
	var en_stand := 0
	var my_init := 0
	var my_stand := 0
	for r in mine_all:
		my_init += r.initial_men
		my_p += power(r)
		if r.is_ranged() and not r.is_broken():
			my_r += float(r.alive) * (1.2 if r.type == UnitTypes.TEPPO else 1.0)
		if not r.is_broken() and not r.withdrawn:
			my_stand += r.alive
	for e in en_all:
		en_init += e.initial_men
		en_p += power(e)
		if e.is_ranged() and not e.is_broken():
			en_r += float(e.alive) * (1.2 if e.type == UnitTypes.TEPPO else 1.0)
		if not e.is_broken() and not e.withdrawn:
			en_stand += e.alive
	strength_ratio = my_p / maxf(en_p, 1.0)
	ranged_ratio = (my_r + 10.0) / (en_r + 10.0)
	my_com = _com(mine)
	enemy_com = _com(enemies)
	crossing = ford != Vector2.INF and _river_between(my_com, enemy_com)
	var gap := my_com.distance_to(enemy_com)
	contact = gap < 520.0
	var eff := strength_ratio * _cfg("aggression")
	var en_frac := float(en_stand) / maxf(1.0, float(en_init))

	# --- choose posture -----------------------------------------------------------
	var want: int
	var why := ""
	var was_all_out := all_out
	all_out = (en_frac < 0.35 and eff > 1.0) or strength_ratio > 2.4
	# observed enemy drift toward us (px/s), weighted by men
	var adv := 0.0
	var adv_w := 0.0
	for e in enemies:
		adv += enemy_velocity(e).dot((my_com - e.mean_pos).normalized()) * e.alive
		adv_w += e.alive
	adv /= maxf(adv_w, 1.0)
	var on_high := high_ground != Vector2.INF and line_anchor.distance_to(high_ground) < 450.0
	if all_out:
		want = Posture.ATTACK
		why = "enemy broken (%.0f%% standing)" % (en_frac * 100.0) if en_frac < 0.35 else "overwhelming advantage"
	elif eff < 0.8:
		want = Posture.DEFEND
		why = "outmatched"
	elif crossing and enemy_com.distance_to(ford) < 1000.0 and eff < 2.0 \
			and not (posture == Posture.ATTACK and phase == "assault"):
		# the enemy is at the river: let him come through the ford in column instead of us
		want = Posture.DEFEND
		why = "holding the ford, enemy at the river"
	elif posture == Posture.DEFEND and adv > 12.0 and eff < 1.6 and gap < 1400.0:
		# he is coming to us: receive him on our formed line rather than meet him halfway
		want = Posture.DEFEND
		why = "enemy advancing into our line"
	elif hint_posture == "defend" and high_ground != Vector2.INF and eff < 1.5 \
			and not (posture == Posture.ATTACK and phase != "approach"):
		want = Posture.DEFEND
		why = "holding the high ground"
	elif ranged_ratio > 1.4 and eff < 1.6 and not (posture == Posture.ATTACK and phase != "approach"):
		want = Posture.SKIRMISH
		why = "missile advantage"
	else:
		want = Posture.ATTACK
		why = "stronger or even"
	# patience: an enemy that will not come is attacked (passive players lose)
	var patience := _cfg("patience") * (2.5 if on_high else 1.0)
	if enemy_holds_crossing():
		patience *= 3.0   # don't feed the army into a defended ford; wait for him to come
	if want != Posture.ATTACK and posture != Posture.ATTACK and sim.time - posture_since > patience \
			and gap > 700.0 and eff > 0.55 and not _impatient:
		_impatient = true
		_log("enemy is passive for %.0f s: abandoning %s" % [sim.time - posture_since, POSTURE_NAMES[posture]])
	if _impatient:
		if gap < 450.0 and eff < 0.8:
			_impatient = false
		elif want != Posture.ATTACK:
			want = Posture.ATTACK
			why = "enemy passive"
	if all_out and not was_all_out:
		_log("ALL-OUT ATTACK: %s" % why)
	if want != posture and (sim.time - posture_since > 6.0 or all_out or stats["posture_changes"] == 0):
		_log("posture %s -> %s (%s; strength %.2f, ranged %.2f, crossing %s)" % [
			POSTURE_NAMES[posture], POSTURE_NAMES[want], why, strength_ratio, ranged_ratio, crossing])
		posture = want
		posture_since = sim.time
		stats["posture_changes"] += 1
	elif stats["posture_changes"] == 0:
		stats["posture_changes"] = 1
		posture_since = sim.time
		_log("posture %s (%s; strength %.2f, ranged %.2f, crossing %s)" % [
			POSTURE_NAMES[posture], why, strength_ratio, ranged_ratio, crossing])

	# --- save the general when the battle is lost -----------------------------------
	var g := sim.general_of(team)
	if g != null and not general_withdrawn and not g.is_broken() \
			and float(my_stand) < float(my_init) * 0.3 and strength_ratio < 0.45:
		general_withdrawn = true
		g.order_withdraw()
		_log("battle lost (strength %.2f): the general withdraws" % strength_ratio)

	_update_phase(mine, gap)
	_update_guards(mine, enemies)
	_plan_line(mine, enemies)


func _set_phase(p: String, why: String) -> void:
	if p == phase:
		return
	_log("attack phase %s -> %s (%s)" % [phase, p, why])
	phase = p
	phase_since = sim.time


func _update_phase(mine: Array[Regiment], gap: float) -> void:
	line_ready = true
	var my_missiles := 0
	for r in mine:
		var sl: Dictionary = _line_slots.get(r.id, {})
		if sl.is_empty() or sl["role"] != "line" or r.is_engaged():
			continue
		if r.mean_pos.distance_to(sl["pos"]) > 130.0:
			line_ready = false
	for r in mine:
		if r.is_ranged():
			my_missiles += r.alive
	if posture != Posture.ATTACK:
		_set_phase("approach", "posture %s" % POSTURE_NAMES[posture])
		return
	if all_out:
		_set_phase("assault", "all-out")
		return
	var soften_t := 30.0   # aggression changes posture choices, not how well we prepare an assault
	match phase:
		"approach":
			if gap < 330.0:
				_set_phase("assault", "enemy closed in")
			elif _stand_reached and line_ready and not crossing:
				if my_missiles < 20 or ranged_ratio < 0.75:
					_set_phase("assault", "no missile edge to soften with")
				else:
					_set_phase("soften", "line formed at bow range")
					_soften_men = Vector2(sim.men_alive(team, false), sim.men_alive(1 - team, false))
		"soften":
			# keep shooting while the exchange is one-sided (a passive enemy bleeds for free);
			# go in once we are clearly stronger, the arrows stop paying, or he comes at us
			var t := sim.time - phase_since
			var our_loss := _soften_men.x - sim.men_alive(team, false)
			var their_loss := _soften_men.y - sim.men_alive(1 - team, false)
			var paying := their_loss > our_loss * 1.2 + 3.0
			var why := ""
			if gap < 330.0:
				why = "enemy closed in"
			elif my_missiles < 20:
				why = "missiles spent"
			elif strength_ratio > 1.35 and t > 10.0:
				why = "softened to strength %.2f" % strength_ratio
			elif t > soften_t and not paying:
				why = "arrows no longer paying (%d vs %d lost)" % [their_loss, our_loss]
			elif t > soften_t * 5.0:
				why = "softened long enough"
			if why != "":
				_set_phase("assault", "%s after %.0f s" % [why, t])


# =====================================================================================
#  Layer 2: group tactics (battle line, screens, wings, general)
# =====================================================================================

## Which ford to attack across: the main ford unless the enemy army sits on its far bank and a
## secondary (hidden) ford is clear, in which case the army swings round through that one.
## Returns [near end, far end, is_secondary].
func _crossing_choice() -> Array:
	var nf := _near_far_ford()
	var best: Array = [nf[0], nf[1], false]
	if enemy_com.distance_to(nf[1]) > 650.0:
		return best
	var best_cost := my_com.distance_to(nf[0]) + 2000.0   # a defended ford costs dearly
	for f in _side_fords:
		var a: Vector2 = f["a"]
		var b: Vector2 = f["b"]
		var near := a if my_com.distance_to(a) < my_com.distance_to(b) else b
		var far := b if near == a else a
		if enemy_com.distance_to(far) < 800.0:
			continue
		var cost := my_com.distance_to(near) + far.distance_to(enemy_com) * 0.5
		if cost < best_cost:
			best_cost = cost
			best = [near, far, true]
	return best


func enemy_holds_crossing() -> bool:
	## The enemy army sits on the far bank of every ford (crossing would be into his line).
	if not crossing:
		return false
	return not bool(_crossing_choice()[2]) and enemy_com.distance_to(_near_far_ford()[1]) < 650.0


func _near_far_ford() -> Array:
	## [near-side ford end, far-side ford end] relative to our army.
	if ford_a == Vector2.INF:
		return [ford, ford]
	if my_com.distance_to(ford_a) < my_com.distance_to(ford_b):
		return [ford_a, ford_b]
	return [ford_b, ford_a]


func _plan_line(mine: Array[Regiment], enemies: Array[Regiment]) -> void:
	var line: Array[Regiment] = []
	var missiles: Array[Regiment] = []
	var cav: Array[Regiment] = []
	var guards := {}
	for f in _side_fords:
		if f["guard"] != null:
			guards[(f["guard"] as Regiment).id] = f
	for r in mine:
		if guards.has(r.id):
			continue
		match r.type:
			UnitTypes.YARI, UnitTypes.SAMURAI: line.append(r)
			UnitTypes.YUMI, UnitTypes.TEPPO: missiles.append(r)
			UnitTypes.CAVALRY: cav.append(r)
	var cur_line := _com(line) if not line.is_empty() else my_com
	var fwd := (enemy_com - cur_line).normalized()
	var anchor := cur_line
	var nf := _near_far_ford()
	var bow_range := 600.0
	for m in missiles:
		if m.type == UnitTypes.YUMI:
			bow_range = m.get_range()
	match posture:
		Posture.ATTACK:
			if crossing and _river_between(cur_line, enemy_com):
				# bridgehead: cross at the ford and form up on the far bank
				var cc := _crossing_choice()
				var far: Vector2 = cc[1]
				if cc[2] and not _flank_logged:
					_flank_logged = true
					_log("enemy holds the main ford: swinging round through the hidden ford at %s" % far.round())
				fwd = (enemy_com - far).normalized()
				anchor = far + fwd * 320.0
			else:
				var standoff := 160.0 if phase == "assault" else bow_range * 0.88 + 110.0
				var stand := enemy_com - fwd * standoff
				var rem := cur_line.distance_to(stand)
				_stand_reached = rem < 120.0
				if not line_ready and phase != "assault" and line_anchor != Vector2.ZERO \
						and not _river_between(cur_line, line_anchor):
					anchor = line_anchor   # wait for stragglers: dress the line first
					fwd = line_fwd
				else:
					var adv := minf(rem, 320.0)
					anchor = cur_line + (stand - cur_line).normalized() * adv if adv > 1.0 else cur_line
		Posture.DEFEND, Posture.SKIRMISH:
			if crossing and ford != Vector2.INF:
				# hold the river line: our bank, facing the ford
				var near: Vector2 = nf[0]
				var back := (my_com - near).normalized()
				anchor = near + back * (280.0 if posture == Posture.DEFEND else 200.0)
				fwd = (enemy_com - anchor).normalized().lerp(-back, 0.6).normalized()
			elif posture == Posture.DEFEND and high_ground != Vector2.INF \
					and high_ground.distance_to(my_com) < 1100.0 \
					and high_ground.distance_to(enemy_com) > 700.0:
				anchor = high_ground + fwd * 120.0
			elif posture == Posture.SKIRMISH:
				# line sits behind the archers' firing position
				var stand := enemy_com - fwd * (bow_range * 0.85 + 130.0)
				var adv := minf(cur_line.distance_to(stand), 300.0)
				anchor = cur_line + (stand - cur_line).normalized() * adv if adv > 1.0 else cur_line
			else:
				anchor = cur_line
	line_anchor = anchor
	line_fwd = fwd
	var right := Vector2(-fwd.y, fwd.x)
	_line_slots.clear()

	# battle line: keep current left-to-right order so nobody crosses
	line.sort_custom(func(a, b): return (a.mean_pos - anchor).dot(right) < (b.mean_pos - anchor).dot(right))
	var total := 0.0
	for r in line:
		total += _line_width(r) + 34.0
	var x := -total * 0.5
	var line_depth := 0.0
	for r in line:
		var w := _line_width(r) + 34.0
		_line_slots[r.id] = {"pos": _dry(anchor + right * (x + w * 0.5), -fwd), "fwd": fwd, "role": "line"}
		x += w
		line_depth = maxf(line_depth, r.depth())
	var half := maxf(total * 0.5, 150.0)

	# missiles: screen ahead of the line, retire behind it
	missiles.sort_custom(func(a, b): return (a.mean_pos - anchor).dot(right) < (b.mean_pos - anchor).dot(right))
	for k in missiles.size():
		var r := missiles[k]
		var lat := (float(k) + 0.5) / missiles.size() * 2.0 - 1.0
		var base := anchor + right * lat * half * 0.75
		var ahead := line_depth * 0.5 + r.depth() * 0.5 + 60.0
		_line_slots[r.id] = {"pos": _dry(base + fwd * ahead, -fwd), "back": _dry(base - fwd * (line_depth * 0.5 + r.depth() * 0.5 + 70.0), -fwd),
			"fwd": fwd, "role": "missile"}

	# cavalry: wings
	cav.sort_custom(func(a, b): return (a.mean_pos - anchor).dot(right) < (b.mean_pos - anchor).dot(right))
	for k in cav.size():
		var r := cav[k]
		var side := -1.0 if k % 2 == 0 else 1.0
		if cav.size() == 1:
			side = -1.0 if (r.mean_pos - anchor).dot(right) < 0.0 else 1.0
		var p := anchor + right * side * (half + 120.0 + float(k / 2) * 120.0) - fwd * 40.0
		_line_slots[r.id] = {"pos": _dry(p, -fwd), "fwd": fwd, "role": "cav"}

	for gid in guards:
		var f: Dictionary = guards[gid]
		var near: Vector2 = f["a"] if my_com.distance_to(f["a"]) < my_com.distance_to(f["b"]) else f["b"]
		var far: Vector2 = f["b"] if near == f["a"] else f["a"]
		var out := (near - far).normalized()
		_line_slots[gid] = {"pos": _dry(near + out * 170.0, out), "fwd": -out, "role": "guard", "ford": (near + far) * 0.5}
	var g := sim.general_of(team)
	if g != null:
		_line_slots[g.id] = {"pos": _dry(anchor - fwd * (line_depth * 0.5 + 230.0), -fwd), "fwd": fwd, "role": "general"}


func _line_width(r: Regiment) -> float:
	return float(mini(r.files, maxi(r.alive, 1)) - 1) * r.spacing.x


## Pushes `p` along `dir` until it is out of the river (lines never stand in deep water).
func _dry(p: Vector2, dir: Vector2) -> Vector2:
	p = p.clamp(Vector2(60, 60), sim.map_size - Vector2(60, 60))
	var k := 0
	while _water(p) and k < 20:
		p += dir * 40.0
		k += 1
	return p


# =====================================================================================
#  Layer 3: unit micro
# =====================================================================================

func _think_regiment(r: Regiment) -> void:
	var slot: Dictionary = _line_slots.get(r.id, {})
	if slot.is_empty():
		return
	if r.type == UnitTypes.GENERAL:
		_micro_general(r, slot)
		return
	# wavering units fall back toward the general to rally in his aura
	if r.state == Regiment.Morale.WAVERING and r.morale < 26.0 and not r.is_engaged() and not all_out:
		var g := sim.general_of(team)
		if g != null and not g.is_broken() and not g.withdrawn and g.mean_pos.distance_to(r.mean_pos) > 260.0:
			var to := g.mean_pos + (r.mean_pos - g.mean_pos).normalized() * 110.0
			if _move_to(r, to, line_fwd, false, Color(1, 1, 0)):
				stats["fallbacks"] += 1
			return
	match slot["role"]:
		"line": _micro_line(r, slot)
		"missile": _micro_missile(r, slot)
		"cav": _micro_cav(r, slot)
		"guard": _micro_guard(r, slot)


func _micro_line(r: Regiment, slot: Dictionary) -> void:
	if r.is_engaged() and r.engaged * 4 >= r.alive:
		return   # let the brawl run
	# spears brace against approaching cavalry: halt and face it
	if r.type == UnitTypes.YARI:
		var threat := _cav_threat(r)
		if threat != null:
			var dir := (threat.mean_pos - r.mean_pos).normalized()
			if not r.is_idle() or r.facing.dot(dir) < 0.85:
				r.order_move(r.mean_pos, dir)
				_dest[r.id] = [r.mean_pos, dir]
				_intent[r.id] = [r.mean_pos, threat.mean_pos, Color(0.3, 0.6, 1)]
				stats["braces"] += 1
			return
	var engage := _cfg("engage") * (1.8 if all_out else 1.0)
	if posture == Posture.ATTACK and phase == "assault":
		engage = 900.0   # the whole line goes in together (walk, then charge the last stretch)
	elif posture == Posture.ATTACK:
		engage = 140.0
	if posture != Posture.ATTACK:
		# hold the line, only meet whoever comes to us (further at the ford: hit the column)
		engage = 260.0 if crossing else 140.0
	var cur := r.target()
	if cur != null and not cur.is_out() and not cur.is_routing() and cur.mean_pos.distance_to(r.mean_pos) < engage * 1.6:
		return
	var best: Regiment = null
	var best_s := INF
	for e in sim.enemies_of(team):
		if e.is_broken() or e.withdrawn:
			continue
		var d := r.mean_pos.distance_to(e.mean_pos) - e.depth() * 0.5
		if d > engage:
			continue
		if _blocked(r.mean_pos, e.mean_pos):
			continue
		var s := d
		if r.type == UnitTypes.YARI and e.type == UnitTypes.CAVALRY:
			s -= 80.0
		if e.is_ranged():
			s -= 40.0
		if s < best_s:
			best_s = s
			best = e
	if best != null:
		if r.target() != best:
			r.order_attack(best, best_s < 170.0)
			_dest.erase(r.id)
			_intent[r.id] = [r.mean_pos, best.mean_pos, Color(1, 0.2, 0.2)]
		return
	_move_to(r, slot["pos"], slot["fwd"], false, Color(0.8, 0.8, 0.8))


## An enemy cavalry regiment that is observably closing on `r` (no reading of its orders).
func _cav_threat(r: Regiment) -> Regiment:
	for e in sim.enemies_of(team):
		if not e.is_mounted() or e.is_broken() or e.withdrawn:
			continue
		var to_r := r.mean_pos - e.mean_pos
		var d := to_r.length()
		if d > 420.0 or d < 30.0:
			continue
		if e.is_engaged() and d > 120.0:
			continue
		var closing := enemy_velocity(e).dot(to_r / d)
		if closing > 45.0 or d < 160.0:
			return e
	return null


func _nearest_melee_threat(r: Regiment) -> Array:
	## [enemy, distance, closing speed] for the nearest non-broken enemy melee regiment.
	var best: Regiment = null
	var best_d := INF
	for e in sim.enemies_of(team):
		if e.is_broken() or e.withdrawn or e.is_ranged():
			continue
		var d := r.mean_pos.distance_to(e.mean_pos) - e.depth() * 0.5
		if d < best_d:
			best_d = d
			best = e
	var closing := 0.0
	if best != null:
		closing = enemy_velocity(best).dot((r.mean_pos - best.mean_pos).normalized())
	return [best, best_d, closing]


func _micro_missile(r: Regiment, slot: Dictionary) -> void:
	var rng_r := r.get_range()
	var th := _nearest_melee_threat(r)
	var threat: Regiment = th[0]
	var td: float = th[1]
	var closing: float = th[2]
	# gunners hold fire until the enemy is inside effective range (or they're being hit)
	if r.type == UnitTypes.TEPPO:
		var nearest := INF
		for e in sim.enemies_of(team):
			if not e.is_out():
				nearest = minf(nearest, r.mean_pos.distance_to(e.mean_pos))
		r.set_fire_at_will(nearest < rng_r * 0.8 or r.under_fire_t < 2.0)
	# kite: step back from melee that is coming at us
	var kite_d := 230.0 if r.type == UnitTypes.YUMI else 150.0
	if threat != null and (td < kite_d or (td < kite_d * 1.6 and closing > 30.0)):
		var away := (r.mean_pos - threat.mean_pos).normalized()
		var back: Vector2 = slot["back"]
		var to := back
		# behind the line if that is actually away from the threat, else straight away
		if (back - r.mean_pos).dot(away) < 0.0 or back.distance_to(threat.mean_pos) < 260.0:
			to = r.mean_pos + away * 280.0
		to = _dry(to, away)
		if _move_to(r, to, -away, true, Color(1, 0.6, 0)):
			stats["kites"] += 1
		return
	if r.is_engaged():
		return
	# melee lines are about to meet: retire behind our line
	var line_close := threat != null and (td < 300.0 or (td < 420.0 and closing > 25.0))
	if line_close and posture == Posture.ATTACK:
		_move_to(r, slot["back"], slot["fwd"], false, Color(0.6, 0.6, 1))
		return
	# hold max range on the best target in reach
	var tgt: Regiment = null
	var tgt_d := INF
	for e in sim.enemies_of(team):
		if e.is_out():
			continue
		var d := r.mean_pos.distance_to(e.mean_pos)
		if d < tgt_d:
			tgt_d = d
			tgt = e
	if tgt != null:
		rng_r = sim.effective_range(r, tgt)   # height changes reach
	if tgt != null and tgt_d < rng_r * 1.35 and (posture != Posture.DEFEND or tgt_d < rng_r):
		var want := rng_r * 0.88
		if absf(tgt_d - want) < 70.0 or tgt_d < want:
			if tgt_d < want - 90.0:
				var back_to := tgt.mean_pos + (r.mean_pos - tgt.mean_pos).normalized() * want
				_move_to(r, _dry(back_to, -line_fwd), (tgt.mean_pos - r.mean_pos).normalized(), false, Color(1, 0.6, 0))
			elif not r.is_idle():
				r.order_halt()
				_dest.erase(r.id)
			return
		var p := tgt.mean_pos + (r.mean_pos - tgt.mean_pos).normalized() * want
		if not _blocked(r.mean_pos, p) or posture == Posture.ATTACK:
			_move_to(r, _dry(p, -line_fwd), (tgt.mean_pos - p).normalized(), false, Color(1, 0.8, 0.2))
			return
	_move_to(r, slot["pos"], slot["fwd"], false, Color(0.9, 0.9, 0.5))


func _cav_score(r: Regiment, e: Regiment, radius: float) -> float:
	if e.withdrawn or e.alive <= 0 or e.state == Regiment.Morale.SHATTERED:
		return -INF
	var d := r.mean_pos.distance_to(e.mean_pos)
	if d > radius:
		return -INF
	var s := 0.0
	if e.is_routing():
		s = 3.0
	elif e.is_ranged():
		s = 2.6
	elif e.type == UnitTypes.YARI:
		if not e.is_engaged():
			return -INF   # never into the front of formed spears
		s = 1.4
	elif e.type == UnitTypes.CAVALRY:
		s = 1.2
	elif e.type == UnitTypes.GENERAL:
		s = 2.2 if e.is_engaged() else 0.4
	else:
		s = 1.6 if e.is_engaged() else 0.2
	if e.is_engaged() and not e.is_routing():
		s += 0.8
	s += 0.4 * (1.0 - float(e.alive) / maxf(1.0, float(e.initial_men)))
	# danger: free (braced) spears near the target
	for o in sim.enemies_of(team):
		if o == e or o.type != UnitTypes.YARI or o.is_broken() or o.withdrawn or o.is_engaged():
			continue
		if o.mean_pos.distance_to(e.mean_pos) < 200.0:
			s -= 1.4
	# never chase across the river except via the ford: just discount it
	if _blocked(r.mean_pos, e.mean_pos):
		s -= 0.8
	return s - d / radius


func _micro_cav(r: Regiment, slot: Dictionary) -> void:
	var c: Dictionary = _cav.get(r.id, {"s": CavState.WING, "t": sim.time, "target": null, "eng": -1.0})
	_cav[r.id] = c
	var tgt: Regiment = c["target"]
	var radius := _cfg("flank_radius") * (1.5 if all_out else 1.0)
	match c["s"]:
		CavState.WING:
			var best: Regiment = null
			var best_s := 0.7
			for e in sim.enemies_of(team):
				var s := _cav_score(r, e, radius)
				if s > best_s:
					best_s = s
					best = e
			if best == null or r.fatigue > 0.75:
				_move_to(r, slot["pos"], slot["fwd"], false, Color(0.4, 1, 0.4))
				return
			c["target"] = best
			var to_t := best.mean_pos - r.mean_pos
			var aspect := best.facing.dot(to_t.normalized())
			if best.is_routing() or best.is_ranged() or aspect > -0.35:
				_charge(r, c, best)
			else:
				# we'd hit its front: ride round to its flank first
				var right := Vector2(-best.facing.y, best.facing.x)
				var side := 1.0 if (r.mean_pos - best.mean_pos).dot(right) > 0.0 else -1.0
				var stage := best.mean_pos + right * side * (best.width() * 0.5 + 230.0) - best.facing * 140.0
				stage = _dry(stage, (r.mean_pos - stage).normalized())
				c["s"] = CavState.STAGE
				c["t"] = sim.time
				r.order_move(stage, (best.mean_pos - stage).normalized(), 0, true)
				_dest[r.id] = [stage, Vector2.ZERO]
				_intent[r.id] = [r.mean_pos, stage, Color(0.4, 1, 0.4)]
		CavState.STAGE:
			if tgt == null or _cav_score(r, tgt, radius * 1.3) < 0.0:
				c["s"] = CavState.WING
				return
			var to_t := tgt.mean_pos - r.mean_pos
			var aspect := tgt.facing.dot(to_t.normalized())
			if r.is_idle() or aspect > -0.2 or sim.time - float(c["t"]) > 12.0:
				if aspect < -0.35 and not tgt.is_ranged() and not tgt.is_routing():
					c["s"] = CavState.WING   # never got round its flank: don't hit the front
					c["target"] = null
				else:
					_charge(r, c, tgt)
		CavState.CHARGE:
			var done: bool = tgt == null or tgt.alive <= 0 or tgt.withdrawn or tgt.state == Regiment.Morale.SHATTERED \
				or (r.target() == null and not r.is_engaged())
			if tgt != null and tgt.is_routing() and tgt.mean_pos.distance_to(line_anchor) > 1100.0:
				done = true   # don't chase routers off the map
			if r.is_engaged():
				if float(c["eng"]) < 0.0:
					c["eng"] = sim.time
				var winning := r.kills_recent > r.losses_recent * 1.5 + 0.5
				if sim.time - float(c["eng"]) > 6.0 and not winning and not all_out:
					_disengage(r, c, tgt)
					return
			else:
				c["eng"] = -1.0
			if done:
				c["s"] = CavState.WING
				c["target"] = null
		CavState.DISENGAGE:
			if sim.time - float(c["t"]) > 5.0 or (r.is_idle() and sim.time - float(c["t"]) > 2.0):
				c["s"] = CavState.WING   # re-formed: free to charge again
				c["target"] = null


func _charge(r: Regiment, c: Dictionary, tgt: Regiment) -> void:
	c["s"] = CavState.CHARGE
	c["t"] = sim.time
	c["eng"] = -1.0
	c["target"] = tgt
	r.order_attack(tgt, true)
	_dest.erase(r.id)
	_intent[r.id] = [r.mean_pos, tgt.mean_pos, Color(1, 0.1, 0.1)]
	var aspect := tgt.facing.dot((tgt.mean_pos - r.mean_pos).normalized())
	stats["cav_charges"] += 1
	stats["cav_charge_aspects"].append(aspect)
	stats["cav_target_types"].append("router" if tgt.is_routing() else tgt.type_key)


func _disengage(r: Regiment, c: Dictionary, tgt: Regiment) -> void:
	var away := (r.mean_pos - (tgt.mean_pos if tgt != null else r.mean_pos + line_fwd)).normalized()
	var to := _dry(r.mean_pos + (away * 0.6 - line_fwd * 0.4).normalized() * 360.0, -line_fwd)
	r.order_move(to, line_fwd, 0, true)
	_dest[r.id] = [to, line_fwd]
	_intent[r.id] = [r.mean_pos, to, Color(0.4, 1, 1)]
	c["s"] = CavState.DISENGAGE
	c["t"] = sim.time
	stats["cav_disengages"] += 1


func _micro_general(g: Regiment, slot: Dictionary) -> void:
	if general_withdrawn:
		return
	# finish routers that are close and unprotected
	var cur := g.target()
	if cur != null and not cur.is_out() and cur.mean_pos.distance_to(line_anchor) < 900.0:
		return
	if cur != null:
		g.order_halt()   # pursuit went too far: come back to the army
	for e in sim.enemies_of(team):
		if e.alive <= 0 or e.withdrawn or e.state == Regiment.Morale.SHATTERED:
			continue
		var d := g.mean_pos.distance_to(e.mean_pos)
		var commit := (e.is_routing() and d < 500.0 and e.mean_pos.distance_to(line_anchor) < 750.0 and not _protected(e)) \
			or (all_out and strength_ratio > 3.0 and e.is_engaged() and d < 450.0)
		if commit and not _blocked(g.mean_pos, e.mean_pos) and cur != e:
			g.order_attack(e, true)
			_dest.erase(g.id)
			stats["general_commits"] += 1
			_log("general commits against %s (%s)" % [e.display_name, "router" if e.is_routing() else "overwhelming advantage"])
			return
	# keep out of reach of enemy melee
	var th := _nearest_melee_threat(g)
	if th[0] != null and float(th[1]) < 220.0 and not g.is_engaged():
		var away := (g.mean_pos - (th[0] as Regiment).mean_pos).normalized()
		_move_to(g, _dry(g.mean_pos + away * 300.0, away), line_fwd, true, Color(1, 1, 1))
		return
	_move_to(g, slot["pos"], slot["fwd"], false, Color(1, 1, 1))


func _protected(e: Regiment) -> bool:
	for o in sim.enemies_of(team):
		if o != e and not o.is_broken() and not o.withdrawn and not o.is_ranged() \
				and o.mean_pos.distance_to(e.mean_pos) < 260.0:
			return true
	return false


## Issues order_move only when the destination meaningfully changed (avoids order churn).
func _move_to(r: Regiment, p: Vector2, fwd: Vector2, run: bool, col: Color) -> bool:
	_intent[r.id] = [r.mean_pos, p, col]
	var last = _dest.get(r.id)
	var tol := 70.0 if not run else 120.0
	if last != null and r.target() == null:
		var lp: Vector2 = last[0]
		var lf: Vector2 = last[1]
		var same_f := fwd == Vector2.ZERO or lf == Vector2.ZERO or lf.dot(fwd) > 0.94
		if lp.distance_to(p) < tol and same_f and (not r.is_idle() or r.mean_pos.distance_to(p) < tol * 1.5):
			return false
	if r.is_idle() and r.mean_pos.distance_to(p) < 40.0 and r.facing.dot(fwd) > 0.94:
		return false
	r.order_move(p, fwd, 0, run)
	_dest[r.id] = [p, fwd]
	return true


func _draw() -> void:
	if not debug_draw or sim == null:
		return
	draw_circle(line_anchor, 10.0, Color(1, 0, 0, 0.8))
	draw_line(line_anchor, line_anchor + line_fwd * 160.0, Color(1, 0, 0, 0.8), 4.0)
	var right := Vector2(-line_fwd.y, line_fwd.x)
	draw_line(line_anchor - right * 400.0, line_anchor + right * 400.0, Color(1, 0.3, 0.3, 0.4), 2.0)
	for id in _intent:
		var it: Array = _intent[id]
		var r: Regiment = sim.regiments[id]
		if r.is_broken() or r.withdrawn:
			continue
		draw_line(r.mean_pos, it[1], it[2], 2.0)
		draw_circle(it[1], 5.0, it[2])
	var font := ThemeDB.fallback_font
	if font != null:
		draw_string(font, line_anchor + Vector2(14, -14), "%s%s  str %.2f" % [POSTURE_NAMES[posture], " ALL-OUT" if all_out else "", strength_ratio], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 0.2, 0.2))


# =====================================================================================
#  Deployment (sim.deploying): a proper battle line inside our zone
# =====================================================================================

## Places every regiment with sim.deploy_place: spears in the centre with samurai on either
## side, missiles screening in front, cavalry on the wings, the general behind. The line
## stands on the map's high ground when it lies inside the zone, else in the zone's forward part.
func deploy() -> void:
	_deployed = true
	_read_map()
	if team >= sim.deploy_zones.size():
		return
	var zone: Rect2 = sim.deploy_zones[team]
	var mine := sim.regiments_of(team)
	var en := sim.enemies_of(team)
	var zc := zone.get_center()
	var ecom := _com(en) if not en.is_empty() else zc - sim.home_dir(team)
	var fwd := (ecom - zc).normalized()
	if absf(fwd.x) > 0.6:   # face squarely across the field toward the enemy side
		fwd = Vector2(signf(fwd.x), 0.0)
	var right := Vector2(-fwd.y, fwd.x)
	var depth_extent := absf(zone.size.dot(fwd))
	var c := zc + fwd * depth_extent * 0.18
	if high_ground != Vector2.INF and zone.grow(-120.0).has_point(high_ground):
		c = high_ground + fwd * 60.0
	var yari: Array[Regiment] = []
	var sam: Array[Regiment] = []
	var missiles: Array[Regiment] = []
	var cav: Array[Regiment] = []
	var gen: Regiment = null
	for r in mine:
		match r.type:
			UnitTypes.YARI: yari.append(r)
			UnitTypes.SAMURAI: sam.append(r)
			UnitTypes.YUMI, UnitTypes.TEPPO: missiles.append(r)
			UnitTypes.CAVALRY: cav.append(r)
			UnitTypes.GENERAL: gen = r
	# line order: samurai on the outsides, spears in the centre
	var line: Array[Regiment] = []
	for k in sam.size():
		if k % 2 == 0:
			line.push_front(sam[k])
		else:
			line.push_back(sam[k])
	var mid := (sam.size() + 1) / 2
	for k in yari.size():
		line.insert(mid + k, yari[k])
	var total := 0.0
	var line_depth := 0.0
	for r in line:
		total += _line_width(r) + 34.0
		line_depth = maxf(line_depth, r.depth())
	var x := -total * 0.5
	for r in line:
		var w := _line_width(r) + 34.0
		sim.deploy_place(r, c + right * (x + w * 0.5), fwd, r.files)
		x += w
	var half := maxf(total * 0.5, 150.0)
	# missiles: teppo in the centre, archers either side, ahead of the line
	missiles.sort_custom(func(a, b): return a.type == UnitTypes.TEPPO and b.type != UnitTypes.TEPPO)
	var order: Array[Regiment] = []
	for k in missiles.size():
		if k % 2 == 0:
			order.push_back(missiles[k])
		else:
			order.push_front(missiles[k])
	for k in order.size():
		var r := order[k]
		var lat := ((float(k) + 0.5) / order.size() * 2.0 - 1.0) * half * 0.75
		var ahead := line_depth * 0.5 + r.depth() * 0.5 + 60.0
		sim.deploy_place(r, c + right * lat + fwd * ahead, fwd, r.files)
	for k in cav.size():
		var side := -1.0 if k % 2 == 0 else 1.0
		sim.deploy_place(cav[k], c + right * side * (half + 120.0 + float(k / 2) * 120.0) - fwd * 40.0, fwd, cav[k].files)
	if gen != null:
		sim.deploy_place(gen, c - fwd * (line_depth * 0.5 + 200.0), fwd, gen.files)
	line_anchor = c
	line_fwd = fwd
	_log("deployed team %d: line of %d at %s facing %s (%d missiles ahead, %d cavalry on the wings)" % [
		team, line.size(), c.round(), fwd, order.size(), cav.size()])


# =====================================================================================
#  Secondary (hidden) fords: post a guard when the enemy comes near one
# =====================================================================================

func _update_guards(mine: Array[Regiment], enemies: Array[Regiment]) -> void:
	for f in _side_fords:
		var c: Vector2 = (f["a"] + f["b"]) * 0.5
		var threat := false
		for e in enemies:
			if e.mean_pos.distance_to(c) < 750.0:
				threat = true
				break
		var gr: Regiment = f["guard"]
		if gr != null and (gr.is_broken() or gr.withdrawn):
			f["guard"] = null
			gr = null
		if threat:
			f["quiet"] = sim.time
			if gr == null:
				var best: Regiment = null
				var best_d := INF
				for r in mine:
					if r.is_engaged() or not (r.type == UnitTypes.YARI or r.type == UnitTypes.CAVALRY):
						continue
					var d := r.mean_pos.distance_to(c) * (1.0 if r.type == UnitTypes.YARI else 1.4)
					if d < best_d:
						best_d = d
						best = r
				if best != null:
					f["guard"] = best
					_cav.erase(best.id)
					_log("enemy near the hidden ford at %s: %s sent to guard it" % [c.round(), best.display_name])
		elif gr != null and sim.time - float(f["quiet"]) > 25.0:
			f["guard"] = null
			_log("hidden ford quiet: %s rejoins the army" % gr.display_name)


func _micro_guard(r: Regiment, slot: Dictionary) -> void:
	if r.is_engaged():
		return
	var post: Vector2 = slot["pos"]
	for e in sim.enemies_of(team):
		if e.is_broken() or e.withdrawn:
			continue
		if e.mean_pos.distance_to(post) < 320.0 and not _blocked(post, e.mean_pos):
			if r.target() != e:
				r.order_attack(e, false)
				_dest.erase(r.id)
			return
	_move_to(r, post, slot["fwd"], true, Color(0.7, 0.3, 1))

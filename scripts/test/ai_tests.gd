extends SceneTree
## Headless AIGeneral tests on the Kurogawa map at accelerated (manual-step) sim speed.
##   tools/tmo 240 godot --headless --path . -s scripts/test/ai_tests.gd -- --scenario=passive
## Scenarios: passive (AI vs a player who never gives orders), scripted (AI vs PlaceholderAI
## "charge the nearest" player), ford (AI vs a player holding the west bank of the ford),
## aivai (AIGeneral vs AIGeneral). --scenario=all runs every one (slow). --diff=easy|normal|hard.
## Prints metrics per scenario; exit code 0 when all checks pass.

const MAX_T := 480.0

var _fails := 0
var _passes := 0
var _ran := false
var _cur := ""
var map_key := "kurogawa"
var _rows: Array = []


func _process(_d: float) -> bool:
	if _ran:
		return false
	_ran = true
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var which: String = args.get("scenario", "passive")
	var diff: String = args.get("diff", "normal")
	var list: Array = ["passive", "scripted", "ford", "aivai"] if which == "all" else Array(which.split(","))
	map_key = args.get("map", "kurogawa")
	var seeds: Array = Array(String(args.get("seeds", args.get("seed", "1574"))).split(","))
	var diffs: Array = Array(diff.split(","))
	for d in diffs:
		for sd in seeds:
			for s in list:
				run_scenario(s, d, int(sd))
	print("\n=== summary (map %s) ===" % map_key)
	print("  scenario  diff    seed   winner  time   men P/AI")
	for row in _rows:
		print("  %-9s %-7s %-6d %-7s %4.0fs  %d/%d" % row)
	print("\n%d checks passed, %d failed" % [_passes, _fails])
	quit(1 if _fails > 0 else 0)
	return false


func check(cond: bool, msg: String) -> void:
	if cond:
		_passes += 1
		print("    ok  %s" % msg)
	else:
		_fails += 1
		print("    FAIL %s" % msg)


# ------------------------------------------------------------------------------------

## Player who holds the west bank of the ford with everything (a static defensive player).
class FordHolder:
	var sim: BattleSim
	var done := false
	func update() -> void:
		if done or sim.time < 2.0:
			return
		done = true
		var regs := sim.regiments_of(0)
		var k := 0
		for r in regs:
			var p := Vector2(2280, 1450 + k * 70)
			if r.type == UnitTypes.GENERAL:
				p = Vector2(1900, 1650)
			elif r.is_ranged():
				p = Vector2(2400, 1300 + k * 90)
			elif r.is_mounted():
				p = Vector2(2150, 1200 if k % 2 == 0 else 2100)
			r.order_move(p, Vector2.RIGHT)
			k += 1


func run_scenario(name: String, diff: String, seed_value: int) -> void:
	_cur = name
	print("\n=== scenario: %s on %s (difficulty %s, seed %d) ===" % [name, map_key, diff, seed_value])
	var map: MapDef = load("res://scripts/world/maps/%s.gd" % map_key).new()
	var terrain := Terrain.new()
	root.add_child(terrain)
	terrain.build(map)
	var sim := BattleSim.new()
	sim.auto_run = false
	root.add_child(sim)
	sim.setup(map.size, terrain, seed_value, map.home_dirs)
	for team in 2:
		for e in map.armies[team]:
			sim.spawn_regiment(e["type"], team, e["pos"], e["facing"])
	var ai := AIGeneral.new()
	ai.sim = sim
	ai.team = 1
	ai.auto = false
	ai.difficulty = diff
	ai.start_delay = 1.0
	root.add_child(ai)
	var p0 = null
	match name:
		"scripted":
			var pa := PlaceholderAI.new()
			pa.sim = sim; pa.team = 0; pa.start_delay = 1.0
			root.add_child(pa)
			p0 = pa
		"ford":
			p0 = FordHolder.new()
			p0.sim = sim
		"aivai":
			var a0 := AIGeneral.new()
			a0.sim = sim; a0.team = 0; a0.auto = false; a0.difficulty = diff; a0.start_delay = 1.0
			a0.verbose = true
			root.add_child(a0)
			p0 = a0
	# deployment phase: the AI(s) lay out their line inside the zone, then the battle starts
	sim.deploy_zones = map.deploy_zones
	sim.begin_deployment()
	ai.update()
	if p0 is AIGeneral:
		p0.update()
	_check_deploy(sim, ai)
	sim.begin_battle()
	var m := Metrics.new(sim, terrain, ai)
	var t0 := Time.get_ticks_msec()
	var won := -1
	sim.battle_ended.connect(func(w): won = w)
	while sim.time < MAX_T and not sim.ended:
		sim.step(3)
		ai.update()
		if p0 != null:
			if p0 is PlaceholderAI:
				if sim.tick_count % 15 < 3 and sim.time > 1.0:
					p0.think()
			else:
				p0.update()
		m.sample()
		if OS.get_cmdline_user_args().has("--trace") and sim.tick_count % 300 < 3:
			var line := "   t=%.0f" % sim.time
			for r in sim.regiments:
				line += " %d%s%d@%d,%d%s" % [r.team, r.type_key.substr(0, 2), r.alive, int(r.mean_pos.x), int(r.mean_pos.y), "*" if r.is_engaged() else ("R" if r.is_routing() else "")]
			print(line)
		if sim.tick_count % 900 < 3:
			print("  .. t=%.0f wall %.1f s  men %d vs %d  posture %s" % [sim.time, (Time.get_ticks_msec() - t0) / 1000.0, sim.men_alive(0, false), sim.men_alive(1, false), AIGeneral.POSTURE_NAMES[ai.posture]])
	var wall := (Time.get_ticks_msec() - t0) / 1000.0
	won = sim.winner
	for r in sim.regiments:
		print("    T%d %-20s %2d/%2d %s" % [r.team, r.display_name, r.alive, r.initial_men, r.morale_name()])
	m.report(won, wall)
	_rows.append([name, diff, seed_value, ["draw", "player", "AI"][won + 1], sim.time, sim.men_alive(0, false), sim.men_alive(1, false)])
	# --- checks ----------------------------------------------------------------------
	check(sim.ended, "battle resolves within %.0f s sim (ended at %.0f s)" % [MAX_T, sim.time])
	if name == "passive" or name == "scripted":
		check(won == 1, "AI wins vs %s player (winner %d)" % [name, won])
	if name != "aivai":
		check(m.line_samples > 5 and m.mean_depth_dev() < 110.0, "AI keeps a line (depth dev %.0f px)" % m.mean_depth_dev())
		check(m.mean_gap() < 160.0, "line gaps reasonable (mean gap %.0f px)" % m.mean_gap())
	check(m.archer_melee_frac() < 0.15, "archers rarely in melee (%.1f%%)" % (m.archer_melee_frac() * 100.0))
	check(m.bad_cav_charges() == 0, "cavalry never charges a formed spear front (%d bad of %d)" % [m.bad_cav_charges(), ai.stats["cav_charges"]])
	check(m.wet_soldier_samples == 0, "no AI soldier in deep water (%d samples)" % m.wet_soldier_samples)
	if m.crossed > 0:
		check(m.crossed_via_ford == m.crossed, "AI crosses only at the ford (%d/%d regiments)" % [m.crossed_via_ford, m.crossed])
	if name == "passive" and map_key == "kurogawa":
		check(m.crossed > 0, "AI uses the ford to reach the enemy (%d regiments crossed)" % m.crossed)
	ai.queue_free()
	if p0 is Node:
		p0.queue_free()
	sim.queue_free()
	terrain.queue_free()


class Metrics:
	var sim: BattleSim
	var terrain: Terrain
	var ai: AIGeneral
	var line_samples := 0
	var depth_dev_sum := 0.0
	var gap_sum := 0.0
	var gap_n := 0
	var archer_samples := 0
	var archer_melee := 0
	var wet_soldier_samples := 0
	var crossed := 0
	var crossed_via_ford := 0
	var first_contact := -1.0
	var _side := {}      # reg id -> start side (true = east of river)
	var _at_ford := {}
	var _done := {}
	var _next := 0.0
	var home := Vector2(4600, 1600)

	func _init(s: BattleSim, t: Terrain, a: AIGeneral) -> void:
		sim = s; terrain = t; ai = a
		for r in sim.regiments_of(1):
			_side[r.id] = true

	func sample() -> void:
		if sim.time < _next:
			return
		_next = sim.time + 1.0
		var mine := sim.regiments_of(1)
		var any_eng := false
		for r in mine:
			if r.is_engaged():
				any_eng = true
		if any_eng and first_contact < 0.0:
			first_contact = sim.time
		# soldiers in water / ford use / crossings
		for r in mine:
			if r.alive <= 0 or r.withdrawn:
				continue
			for i in r.soldiers:
				if sim.state[i] < BattleSim.DEAD and sim.state[i] != BattleSim.ROUT and terrain.is_water(sim.pos[i]):
					wet_soldier_samples += 1
			for fd in terrain.map.fords:
				if r.mean_pos.distance_to((fd["a"] + fd["b"]) * 0.5) < 260.0:
					_at_ford[r.id] = true
			if not _done.has(r.id) and terrain.segment_blocked(r.mean_pos, home) and not r.is_routing():
				_done[r.id] = true
				crossed += 1
				if _at_ford.has(r.id):
					crossed_via_ford += 1
				else:
					print("    ! %s crossed at %s without passing the ford" % [r.display_name, r.mean_pos])
			if r.type == UnitTypes.YUMI and not r.is_broken():
				for i in r.soldiers:
					if sim.state[i] < BattleSim.DEAD:
						archer_samples += 1
						if sim.state[i] == BattleSim.MELEE:
							archer_melee += 1
		# line coherence: before contact, while the line is not threading the ford
		if first_contact >= 0.0 or sim.time < 15.0:   # line discipline is judged on the approach
			return
		var line: Array[Regiment] = []
		for r in mine:
			if (r.type == UnitTypes.YARI or r.type == UnitTypes.SAMURAI) and not r.is_broken():
				if terrain.segment_blocked(r.mean_pos, ai.line_anchor):
					return   # mid-crossing: not a line-keeping moment
				line.append(r)
		if line.size() < 2:
			return
		var fwd := ai.line_fwd
		var right := Vector2(-fwd.y, fwd.x)
		line.sort_custom(func(a, b): return a.mean_pos.dot(right) < b.mean_pos.dot(right))
		var mean_d := 0.0
		for r in line:
			mean_d += r.mean_pos.dot(fwd)
		mean_d /= line.size()
		var dev := 0.0
		for r in line:
			dev += absf(r.mean_pos.dot(fwd) - mean_d)
		depth_dev_sum += dev / line.size()
		line_samples += 1
		for k in range(1, line.size()):
			var a := line[k - 1]
			var b := line[k]
			var g := (b.mean_pos - a.mean_pos).dot(right) - (a.width() + b.width()) * 0.5
			gap_sum += g
			gap_n += 1

	func mean_depth_dev() -> float:
		return depth_dev_sum / maxf(1.0, line_samples)

	func mean_gap() -> float:
		return gap_sum / maxf(1.0, gap_n)

	func archer_melee_frac() -> float:
		return float(archer_melee) / maxf(1.0, archer_samples)

	func bad_cav_charges() -> int:
		var bad := 0
		var types: Array = ai.stats["cav_target_types"]
		var asp: Array = ai.stats["cav_charge_aspects"]
		for k in types.size():
			if types[k] == "yari" and float(asp[k]) < -0.35:
				bad += 1
		return bad

	func report(won: int, wall: float) -> void:
		var st := ai.stats
		var types: Array = st["cav_target_types"]
		var asp: Array = st["cav_charge_aspects"]
		var flank := 0
		for a in asp:
			if float(a) > -0.35:
				flank += 1
		var tcount := {}
		for t in types:
			tcount[t] = tcount.get(t, 0) + 1
		var men := [sim.men_alive(0, false), sim.men_alive(1, false)]
		print("  result: winner %d at %.0f s sim (%.1f s wall), first contact %.0f s" % [won, sim.time, wall, first_contact])
		print("  men standing: player %d, AI %d; kills player %d, AI %d" % [men[0], men[1], sim.stat_kills[0], sim.stat_kills[1]])
		print("  posture: %s%s, posture changes %d" % [AIGeneral.POSTURE_NAMES[ai.posture], " (all-out)" if ai.all_out else "", st["posture_changes"]])
		print("  line: %d samples, mean depth deviation %.0f px, mean gap %.0f px" % [line_samples, mean_depth_dev(), mean_gap()])
		print("  archers in melee: %.1f%% of soldier-samples; kites %d" % [archer_melee_frac() * 100.0, st["kites"]])
		print("  cavalry: %d charges, %d flank/rear, targets %s, disengages %d" % [st["cav_charges"], flank, tcount, st["cav_disengages"]])
		print("  spears braced %d, wavering fallbacks %d, general commits %d" % [st["braces"], st["fallbacks"], st["general_commits"]])
		print("  ford: %d regiments crossed, %d via ford, wet soldier samples %d" % [crossed, crossed_via_ford, wet_soldier_samples])


## Deployment sanity: everyone inside the zone, missiles ahead of the line, cavalry outermost,
## general behind.
func _check_deploy(sim: BattleSim, ai: AIGeneral) -> void:
	var zone: Rect2 = sim.deploy_zones[ai.team].grow(2.0)
	var fwd := ai.line_fwd
	var right := Vector2(-fwd.y, fwd.x)
	var inside := true
	var line_d := 0.0
	var nl := 0
	var miss_ahead := true
	var cav_lat := 0.0
	var line_lat := 0.0
	var gen_behind := true
	for r in sim.regiments_of(ai.team):
		if not zone.has_point(r.centre):
			inside = false
		if r.type == UnitTypes.YARI or r.type == UnitTypes.SAMURAI:
			line_d += (r.centre - ai.line_anchor).dot(fwd)
			nl += 1
			line_lat = maxf(line_lat, absf((r.centre - ai.line_anchor).dot(right)))
	line_d /= maxf(1, nl)
	for r in sim.regiments_of(ai.team):
		var d := (r.centre - ai.line_anchor).dot(fwd)
		if r.is_ranged() and d < line_d + 10.0:
			miss_ahead = false
		if r.type == UnitTypes.CAVALRY:
			cav_lat = maxf(cav_lat, absf((r.centre - ai.line_anchor).dot(right)))
		if r.type == UnitTypes.GENERAL and d > line_d - 60.0:
			gen_behind = false
	check(inside, "deployment: every AI regiment inside its zone")
	check(miss_ahead, "deployment: missiles ahead of the line")
	check(cav_lat > line_lat, "deployment: cavalry on the wings")
	check(gen_behind, "deployment: general behind the line")

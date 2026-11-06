extends SceneTree
## Headless map smoke tests: builds each registered map (terrain + props), checks spawn points,
## then runs a full battle with AI on both sides and checks that armies reach each other (fords,
## pass) and the battle resolves.
##   tools/tmo 230 godot --headless --path . -s scripts/test/map_tests.gd -- --map=tenmoku --ai=general
## --map=kurogawa|tenmoku|all, --ai=placeholder|general (default placeholder = battle.gd --demo).

const MAX_T := 600.0

var _fails := 0
var _passes := 0
var _ran := false


func check(ok: bool, msg: String) -> void:
	if ok:
		_passes += 1
		print("  ok   ", msg)
	else:
		_fails += 1
		print("  FAIL ", msg)


func _process(_d: float) -> bool:
	if _ran:
		return false
	_ran = true
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var which: String = args.get("map", "all")
	var keys: Array = ["kurogawa", "tenmoku"] if which == "all" else Array(which.split(","))
	for k in keys:
		run_map(k, args.get("ai", "placeholder"), int(args.get("seed", "7")))
	print("\n%d checks passed, %d failed" % [_passes, _fails])
	quit(0 if _fails == 0 else 1)
	return false


func run_map(key: String, ai_kind: String, seed_value: int) -> void:
	print("\n=== map %s (ai %s, seed %d) ===" % [key, ai_kind, seed_value])
	var map: MapDef = load("res://scripts/world/maps/%s.gd" % key).new()
	var terrain := Terrain.new()
	root.add_child(terrain)
	var t0 := Time.get_ticks_msec()
	terrain.build(map)
	var props := PropLayer.new()
	props.setup(map, terrain)
	print("  terrain + %d props built in %d ms" % [props.placed.size(), Time.get_ticks_msec() - t0])
	check(map.ai_posture_hint in ["", "attack", "defend", "skirmish"], "posture hint '%s' valid" % map.ai_posture_hint)
	for team in 2:
		var zone: Rect2 = map.deploy_zones[team]
		for e in map.armies[team]:
			var p: Vector2 = e["pos"]
			if not zone.grow(60.0).has_point(p) or terrain.is_water(p) or terrain.is_forest(p):
				check(false, "spawn %s team %d at %s is in zone, dry and clear" % [e["type"], team, p])
	var sim := BattleSim.new()
	sim.auto_run = false
	root.add_child(sim)
	sim.setup(map.size, terrain, seed_value, map.home_dirs)
	for team in 2:
		for e in map.armies[team]:
			sim.spawn_regiment(e["type"], team, e["pos"], e["facing"])
	var ais: Array = []
	for team in 2:
		var ai: Node
		if ai_kind == "general":
			var g := AIGeneral.new()
			g.sim = sim; g.team = team; g.auto = false; g.start_delay = 1.0; g.verbose = false
			ai = g
		else:
			var pa := PlaceholderAI.new()
			pa.sim = sim; pa.team = team; pa.start_delay = 1.0
			ai = pa
		root.add_child(ai)
		ais.append(ai)
	var wet := 0
	var contact_t := -1.0
	var w0 := Time.get_ticks_msec()
	while sim.time < MAX_T and not sim.ended:
		sim.step(3)
		for ai in ais:
			if ai is AIGeneral:
				ai.update()
			elif sim.tick_count % 15 < 3 and sim.time > 1.0:
				ai.think()
		if sim.tick_count % 30 < 3:
			for r in sim.regiments:
				if contact_t < 0.0 and r.is_engaged():
					contact_t = sim.time
				if r.alive > 0 and not r.is_routing() and terrain.is_water(r.mean_pos):
					wet += 1
					if wet <= 5:
						print("  wet: T%d %s at %s t=%.0f routing=%s" % [r.team, r.type_key, r.mean_pos, sim.time, r.is_routing()])
		if sim.tick_count % 1800 < 3:
			print("  .. t=%.0f  men %d vs %d" % [sim.time, sim.men_alive(0, false), sim.men_alive(1, false)])
	print("  ended=%s winner=%d t=%.0f s (wall %.1f s)  men %d vs %d" % [sim.ended, sim.winner, sim.time,
		(Time.get_ticks_msec() - w0) / 1000.0, sim.men_alive(0, false), sim.men_alive(1, false)])
	check(contact_t > 0.0, "armies reach each other (first melee at t=%.0f s)" % contact_t)
	check(wet == 0, "no formed regiment centre in deep water (%d samples; routers ignored)" % wet)
	check(sim.ended, "battle resolves within %.0f s (t=%.0f)" % [MAX_T, sim.time])
	for ai in ais:
		ai.queue_free()
	sim.queue_free()
	props.free()
	terrain.queue_free()

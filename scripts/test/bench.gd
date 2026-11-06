extends SceneTree
## Performance benchmark: two standard armies plus reserves (~1000 soldiers) on the
## Kurogawa map, both sides attacking. Prints sim ms/tick and renderer ms/frame.
##   godot --headless --path . -s scripts/test/bench.gd

var _ran := false


func _process(_d: float) -> bool:
	if _ran:
		return false
	_ran = true
	_run()
	return false


func _run() -> void:
	var map: MapDef = load("res://scripts/world/maps/kurogawa.gd").new()
	var terrain := Terrain.new()
	root.add_child(terrain)
	terrain.build(map)
	var sim := BattleSim.new()
	sim.auto_run = false
	root.add_child(sim)
	sim.setup(map.size, terrain, 1, map.home_dirs)
	# armies on the near side of the river so they clash quickly
	var zones := [Rect2(1000, 900, 700, 1400), Rect2(1900, 900, 700, 1400)]
	var fwd := [Vector2.RIGHT, Vector2.LEFT]
	for team in 2:
		for e in MapDef.standard_layout(zones[team], fwd[team]):
			sim.spawn_regiment(e["type"], team, e["pos"], e["facing"])
		# reserves to reach ~1000
		sim.spawn_regiment("yari", team, zones[team].get_center() - fwd[team] * 420.0, fwd[team])
	print("soldiers: %d, regiments: %d" % [sim.n, sim.regiments.size()])
	var ai0 := PlaceholderAI.new(); ai0.sim = sim; ai0.team = 0; ai0.start_delay = 0.0
	var ai1 := PlaceholderAI.new(); ai1.sim = sim; ai1.team = 1; ai1.start_delay = 0.0
	var renderer := SoldierRenderer.new()
	root.add_child(renderer)
	renderer.setup(sim)
	ai0.think(); ai1.think()
	var quick := OS.get_cmdline_user_args().has("--quick")
	var only := -1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ticks="):
			only = int(a.substr(8))
	var phases := [["approach", 30], ["melee", 60]] if quick else [["approach", 300], ["melee", 600], ["melee+routs", 600]]
	if only >= 0:
		# CPU-time mode: run N ticks (+ render every other) and quit; compare `time` of N vs 0.
		for k in only:
			if k % 15 == 0:
				ai0.think(); ai1.think()
			sim.step(1)
			if k % 2 == 0:
				renderer.update_now()
		print("ran %d ticks, t=%.0fs alive %d+%d" % [only, sim.time, sim.men_alive(0), sim.men_alive(1)])
		quit()
		return
	sim.prof_reset()
	for ph in phases:
		var ticks: int = ph[1]
		var tot := 0
		var worst := 0
		var rtot := 0
		for k in ticks:
			if k % 15 == 0:
				ai0.think(); ai1.think()
			var t0 := Time.get_ticks_usec()
			sim.step(1)
			var dt := Time.get_ticks_usec() - t0
			tot += dt
			worst = maxi(worst, dt)
			if k % 2 == 0:
				var t1 := Time.get_ticks_usec()
				renderer.update_now()
				rtot += Time.get_ticks_usec() - t1
		print("   sections: " + sim.prof_report())
		sim.prof_reset()
		var engaged := 0
		for r in sim.regiments:
			engaged += r.engaged
		print("%-12s sim %.2f ms/tick avg, %.2f ms worst | render %.2f ms/frame | engaged %d, alive %d+%d, arrows %d" % [
			ph[0], tot / 1000.0 / ticks, worst / 1000.0, rtot / 1000.0 / (ticks / 2), engaged,
			sim.men_alive(0), sim.men_alive(1), sim.projectiles.count])
	print("battle t=%.0fs ended=%s winner=%d" % [sim.time, sim.ended, sim.winner])
	quit()

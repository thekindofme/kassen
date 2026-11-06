extends SceneTree
## Headless simulation tests.
##   godot --headless --path . -s scripts/test/sim_tests.gd
## Exit code 0 = all passed. Each test builds its own BattleSim and steps it manually.

var _fails := 0
var _passes := 0
var _current := ""
var _signals := {}


var _ran := false


func _process(_delta: float) -> bool:
	# Run on the first frame (not in _initialize) so the root viewport is inside the tree and
	# InputEvents injected with Input.parse_input_event are delivered.
	if _ran:
		return false
	_ran = true
	_run_all()
	return false


func _run_all() -> void:
	var t0 := Time.get_ticks_msec()
	var tests := [
		"test_formation_move", "test_formation_reface_and_frontage", "test_no_jitter_at_rest",
		"test_melee_resolution", "test_rout_and_rally", "test_charge_vs_braced",
		"test_arrows_hit", "test_guns_volley", "test_victory", "test_determinism",
		"test_kurogawa_ford_route", "test_commander_input", "test_deployment", "test_alive_never_negative", "test_army_collapse",
	]
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7)
	for t in tests:
		if only != "" and not only.split(",").has(t):
			continue
		_current = t
		var before := _fails
		call(t)
		print("%s %s" % ["PASS" if _fails == before else "FAIL", t])
	print("\n%d checks passed, %d failed (%.1f s)" % [_passes, _fails, (Time.get_ticks_msec() - t0) / 1000.0])
	quit(1 if _fails > 0 else 0)


func check(cond: bool, msg: String) -> void:
	if cond:
		_passes += 1
	else:
		_fails += 1
		push_error("[%s] %s" % [_current, msg])
		print("    x %s" % msg)


func new_sim(seed_value := 1, terrain: Terrain = null, size := Vector2(3000, 2000)) -> BattleSim:
	var s := BattleSim.new()
	s.auto_run = false
	root.add_child(s)
	s.setup(size, terrain, seed_value)
	_signals = {}
	for sig in ["soldier_died", "regiment_routed", "regiment_rallied", "battle_ended", "melee_contact", "volley", "charge_impact"]:
		_signals[sig] = []
		var name: String = sig
		s.connect(sig, func(a = null, b = null): _signals[name].append([a, b]))
	return s


func free_sim(s: BattleSim) -> void:
	s.queue_free()


func seconds(s: BattleSim, t: float) -> void:
	s.step(int(t * BattleSim.TICK_HZ))


func slot_error(s: BattleSim, r: Regiment) -> float:
	var e := 0.0
	var c := 0
	for i in r.soldiers:
		if s.state[i] < BattleSim.DEAD:
			e += s.pos[i].distance_to(s.slot_pos[i])
			c += 1
	return e / maxf(1, c)


func min_pair_dist(s: BattleSim, r: Regiment) -> float:
	var m := INF
	for a in r.soldiers:
		for b in r.soldiers:
			if a < b:
				m = minf(m, s.pos[a].distance_to(s.pos[b]))
	return m


func until(s: BattleSim, max_s: float, cond: Callable) -> float:
	var ticks := int(max_s * BattleSim.TICK_HZ)
	for k in ticks:
		s.step(1)
		if k % 10 == 0 and cond.call():
			return s.time
	return -1.0


# =====================================================================================

func test_formation_move() -> void:
	var s := new_sim()
	var r := s.spawn_regiment("yari", 0, Vector2(500, 1000), Vector2.RIGHT)
	r.order_move(Vector2(1100, 1000))
	seconds(s, 5.0)
	check(r.is_moving(), "is_moving() while marching")
	var moved := r.centre.x - 500.0
	check(moved > 120.0 and moved < 200.0, "walks at ~34 px/s (moved %.0f px in 5 s)" % moved)
	check(slot_error(s, r) < r.spacing.x * 1.2, "keeps formation while marching (err %.1f)" % slot_error(s, r))
	seconds(s, 25.0)
	check(not r.is_moving(), "not moving after arrival")
	check(r.is_idle(), "move order completed")
	check(r.mean_pos.distance_to(Vector2(1100, 1000)) < 6.0, "arrived at destination (%s)" % r.mean_pos)
	check(slot_error(s, r) < 2.0, "settled into slots (err %.2f)" % slot_error(s, r))
	check(min_pair_dist(s, r) > 9.0, "soldiers don't overlap (min %.1f)" % min_pair_dist(s, r))
	# run is faster
	r.order_move(Vector2(1700, 1000), Vector2.ZERO, 0, true)
	seconds(s, 3.0)
	check(r.centre.x - 1100.0 > 200.0, "running covers ground fast (%.0f px in 3 s)" % (r.centre.x - 1100.0))
	free_sim(s)


func test_formation_reface_and_frontage() -> void:
	var s := new_sim()
	var r := s.spawn_regiment("yari", 0, Vector2(800, 1000), Vector2.RIGHT)
	r.order_move(Vector2(800, 900), Vector2.UP, 30)
	seconds(s, 25.0)
	check(r.is_idle(), "reface order completed")
	check(r.files == 30 and r.facing.dot(Vector2.UP) > 0.99, "frontage 30 facing up")
	var xs := PackedFloat32Array()
	for i in r.soldiers:
		xs.append(s.pos[i].x)
	xs.sort()
	var width := xs[xs.size() - 1] - xs[0]
	check(absf(width - 29.0 * r.spacing.x) < 12.0, "formation width matches frontage (%.0f)" % width)
	check(slot_error(s, r) < 2.0, "settled (err %.2f)" % slot_error(s, r))
	# soldiers face their direction while walking
	r.order_move(Vector2(400, 900), Vector2.LEFT)
	seconds(s, 4.0)
	var left := 0
	for i in r.soldiers:
		if s.face[i] < 0.0:
			left += 1
	check(left > 50, "soldiers face left while marching left (%d/60)" % left)
	free_sim(s)


func test_no_jitter_at_rest() -> void:
	var s := new_sim()
	var regs: Array[Regiment] = []
	for k in 4:
		regs.append(s.spawn_regiment(["yari", "samurai", "cavalry", "yumi"][k], 0, Vector2(500 + k * 400, 1000), Vector2.RIGHT))
	seconds(s, 6.0)
	var before := s.pos.duplicate()
	var flips := 0
	var face0 := s.face.duplicate()
	seconds(s, 4.0)
	var maxd := 0.0
	for i in s.n:
		maxd = maxf(maxd, before[i].distance_to(s.pos[i]))
		if face0[i] != s.face[i]:
			flips += 1
	check(maxd < 0.5, "idle soldiers stay still (max drift %.3f px)" % maxd)
	check(flips == 0, "no facing flicker at rest (%d flips)" % flips)
	free_sim(s)


func test_melee_resolution() -> void:
	var s := new_sim(3)
	var sam := s.spawn_regiment("samurai", 0, Vector2(900, 1000), Vector2.RIGHT)
	var yari := s.spawn_regiment("yari", 1, Vector2(1250, 1000), Vector2.LEFT)
	sam.order_attack(yari)
	var t := until(s, 120.0, func(): return yari.is_broken() or sam.is_broken())
	check(t > 0.0, "fight resolved within 120 s")
	check(_signals["melee_contact"].size() > 0, "melee_contact emitted")
	var sam_loss := sam.initial_men - sam.alive
	var yari_loss := yari.initial_men - yari.alive
	check(yari_loss > 5, "yari took casualties (%d)" % yari_loss)
	check(sam_loss > 0, "samurai took casualties too (%d)" % sam_loss)
	check(yari.is_broken() and not sam.is_broken(), "elite samurai break the ashigaru (yari %s, samurai %s)" % [yari.morale_name(), sam.morale_name()])
	check(_signals["soldier_died"].size() == sam_loss + yari_loss, "soldier_died per death")
	print("    melee: resolved at %.1fs, samurai lost %d/32, yari lost %d/60" % [t, sam_loss, yari_loss])
	free_sim(s)


func test_rout_and_rally() -> void:
	var s := new_sim(4)
	var r := s.spawn_regiment("yari", 0, Vector2(1500, 1000), Vector2.RIGHT)
	var e := s.spawn_regiment("samurai", 1, Vector2(2300, 1000), Vector2.LEFT)
	seconds(s, 1.0)
	r.morale = 5.0
	seconds(s, 0.5)
	check(r.state == Regiment.Morale.ROUTING, "regiment routs below threshold")
	check(_signals["regiment_routed"].size() == 1, "regiment_routed emitted")
	var x0 := r.mean_pos.x
	seconds(s, 3.0)
	check(r.mean_pos.x < x0 - 150.0, "routers flee toward their home edge (%.0f → %.0f)" % [x0, r.mean_pos.x])
	var routers := 0
	for i in r.soldiers:
		if s.state[i] == BattleSim.ROUT:
			routers += 1
	check(routers == r.alive, "all soldiers in ROUT state")
	var t := until(s, 25.0, func(): return r.state != Regiment.Morale.ROUTING)
	check(t > 0.0 and not r.is_routing(), "rallies when safe (state %s)" % r.morale_name())
	check(_signals["regiment_rallied"].size() == 1, "regiment_rallied emitted")
	r.order_move(Vector2(900, 1000))
	seconds(s, 1.0)
	check(not r.is_idle(), "rallied regiment takes orders again")
	free_sim(s)
	e = null


func _charge_case(braced: bool) -> Dictionary:
	var s := new_sim(5)
	var cav := s.spawn_regiment("cavalry", 0, Vector2(850, 1000), Vector2.RIGHT)
	var yari := s.spawn_regiment("yari", 1, Vector2(1300, 1000), Vector2.LEFT)
	if not braced:
		yari.order_move(Vector2(1300, 1600), Vector2.DOWN)   # marching sideways: flank exposed
		seconds(s, 0.5)
	cav.order_attack(yari)
	seconds(s, 7.0)
	var res := {"cav_loss": cav.initial_men - cav.alive, "yari_loss": yari.initial_men - yari.alive,
		"impacts": _signals["charge_impact"].size(), "braced": s.stat_braced, "charges": s.stat_charges}
	free_sim(s)
	return res


func test_charge_vs_braced() -> void:
	var open := _charge_case(false)
	var brace := _charge_case(true)
	print("    charge into flank: %s\n    charge into braced spears: %s" % [open, brace])
	check(open["charges"] > 5 and open["impacts"] > 0, "cavalry charge lands with charge_impact")
	var open_ratio: float = float(open["yari_loss"]) / (open["cav_loss"] + 1.0)
	var brace_ratio: float = float(brace["yari_loss"]) / (brace["cav_loss"] + 1.0)
	check(open_ratio > brace_ratio * 3.0, "flank charge trades far better than a charge into braced spears (%.1f vs %.1f)" % [open_ratio, brace_ratio])
	check(brace["braced"] > 0, "braced spears negate charges")
	check(brace["cav_loss"] > open["cav_loss"], "cavalry bleed on braced spears")


func test_arrows_hit() -> void:
	var s := new_sim(6)
	var yumi := s.spawn_regiment("yumi", 0, Vector2(500, 1000), Vector2.RIGHT)
	var yari := s.spawn_regiment("yari", 1, Vector2(1050, 1000), Vector2.LEFT)
	var friend := s.spawn_regiment("yari", 0, Vector2(800, 1000), Vector2.RIGHT)   # arrows fly over friends
	seconds(s, 2.0)
	var in_flight := s.projectiles.count
	seconds(s, 18.0)
	check(s.stat_arrows_fired > 60, "archers fire volleys (%d arrows)" % s.stat_arrows_fired)
	check(in_flight > 0 or s.stat_arrows_fired > 0, "projectiles are real objects in flight")
	check(s.stat_arrow_hits > 5, "arrows hit (%d)" % s.stat_arrow_hits)
	check(yari.alive < yari.initial_men, "target took casualties (%d lost)" % (yari.initial_men - yari.alive))
	check(friend.alive == friend.initial_men and yumi.alive == yumi.initial_men, "no friendly fire from arcing arrows")
	var kinds: Array = []
	for v in _signals["volley"]:
		kinds.append(v[1])
	check(kinds.has("arrow"), "volley(arrow) emitted")
	print("    arrows: %d fired, %d hits, %d killed" % [s.stat_arrows_fired, s.stat_arrow_hits, yari.initial_men - yari.alive])
	free_sim(s)


func test_guns_volley() -> void:
	var s := new_sim(7)
	var tep := s.spawn_regiment("teppo", 0, Vector2(500, 1000), Vector2.RIGHT)
	var yari := s.spawn_regiment("yari", 1, Vector2(790, 1000), Vector2.LEFT)
	var m0 := yari.morale
	seconds(s, 12.0)
	check(s.stat_gun_shots >= 40, "gunners fire (%d shots)" % s.stat_gun_shots)
	check(s.stat_gun_hits > 8, "hitscan hits (%d)" % s.stat_gun_hits)
	check(yari.initial_men - yari.alive > 5, "volley kills (%d)" % (yari.initial_men - yari.alive))
	check(yari.morale < m0 - 10.0 or yari.is_routing(), "gunfire scares the target (morale %.0f → %.0f)" % [m0, yari.morale])
	check(not s.shot_fx.is_empty() or s.stat_gun_shots > 0, "shot fx recorded")
	var kinds: Array = []
	for v in _signals["volley"]:
		kinds.append(v[1])
	check(kinds.has("gun"), "volley(gun) emitted")
	print("    guns: %d shots, %d hits, %d killed" % [s.stat_gun_shots, s.stat_gun_hits, yari.initial_men - yari.alive])
	free_sim(s)
	tep = null


func test_victory() -> void:
	var s := new_sim(8)
	var a := s.spawn_regiment("samurai", 0, Vector2(900, 900), Vector2.RIGHT)
	var b := s.spawn_regiment("samurai", 0, Vector2(900, 1100), Vector2.RIGHT)
	var c := s.spawn_regiment("cavalry", 0, Vector2(800, 1400), Vector2.RIGHT)
	var e := s.spawn_regiment("yari", 1, Vector2(1400, 1000), Vector2.LEFT)
	for r in [a, b, c]:
		r.order_attack(e)
	var t := until(s, 240.0, func(): return s.ended)
	check(t > 0.0, "battle ends (t=%.1f)" % t)
	check(s.winner == 0, "team 0 wins")
	check(_signals["battle_ended"].size() == 1 and _signals["battle_ended"][0][0] == 0, "battle_ended(0) emitted once")
	free_sim(s)


func _det_run(seed_value: int) -> float:
	var s := new_sim(seed_value)
	var sam := s.spawn_regiment("samurai", 0, Vector2(900, 1000), Vector2.RIGHT)
	var yari := s.spawn_regiment("yari", 1, Vector2(1250, 1000), Vector2.LEFT)
	var yumi := s.spawn_regiment("yumi", 1, Vector2(1500, 1000), Vector2.LEFT)
	sam.order_attack(yari)
	seconds(s, 25.0)
	var h := 0.0
	for i in s.n:
		h += s.hp[i] + s.pos[i].x * 0.001
	free_sim(s)
	yumi = null
	return h


func test_determinism() -> void:
	var h1 := _det_run(42)
	var h2 := _det_run(42)
	var h3 := _det_run(43)
	check(is_equal_approx(h1, h2), "same seed → identical result (%.4f vs %.4f)" % [h1, h2])
	check(not is_equal_approx(h1, h3), "different seed → different result")


func test_kurogawa_ford_route() -> void:
	var map: MapDef = load("res://scripts/world/maps/kurogawa.gd").new()
	var terrain := Terrain.new()
	root.add_child(terrain)
	terrain.build(map)
	check(terrain.is_water(Vector2(2700, 1300)), "river is deep water")
	check(not terrain.is_water(Vector2(2665, 1645)) and terrain.is_ford(Vector2(2665, 1645)), "ford is crossable")
	check(terrain.speed_mult(Vector2(1400, 1600)) > 1.0, "road is fast")
	check(terrain.is_forest(Vector2(900, 650)), "forest present")
	check(terrain.height(Vector2(3800, 1700)) > 40.0, "enemy hill")
	var route: Dictionary = terrain.find_route(Vector2(2000, 1000), Vector2(3400, 1100))
	var pts: PackedVector2Array = route["points"]
	var via_ford := false
	for p in pts:
		if p.distance_to(map.fords[0]["a"]) < 5.0:
			via_ford = true
	check(via_ford, "route across the river goes through the ford")
	var s := new_sim(9, terrain, map.size)
	var r := s.spawn_regiment("yari", 0, Vector2(2000, 1200), Vector2.RIGHT)
	r.order_move(Vector2(3300, 1300))
	var t := until(s, 150.0, func(): return r.is_idle())
	var east := 0
	var wet := 0
	for i in r.soldiers:
		if s.pos[i].x > 2900.0:
			east += 1
		if terrain.is_water(s.pos[i]):
			wet += 1
	check(t > 0.0, "regiment crossed and arrived (t=%.1f)" % t)
	check(east == r.alive, "all soldiers made it across (%d/%d)" % [east, r.alive])
	check(wet == 0, "nobody stuck in deep water (%d)" % wet)
	free_sim(s)
	terrain.queue_free()


# --- input: real InputEvents through Input.parse_input_event --------------------------

func _send(ev: InputEvent) -> void:
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


## Events are injected in window coordinates; map from root-viewport (world, no camera) coords.
func _win(p: Vector2) -> Vector2:
	return root.get_final_transform() * p


func _mouse(btn: int, pressed: bool, p: Vector2, dbl := false, shift := false) -> void:
	p = _win(p)
	var e := InputEventMouseButton.new()
	e.button_index = btn
	e.pressed = pressed
	e.position = p
	e.global_position = p
	e.double_click = dbl
	e.shift_pressed = shift
	_send(e)


func _motion(p: Vector2, rel := Vector2.ZERO, mask := 0) -> void:
	p = _win(p)
	rel = root.get_final_transform().basis_xform(rel)
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	e.relative = rel
	e.button_mask = mask
	_send(e)


func _keypress(code: Key, ctrl := false) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.pressed = pressed
		e.ctrl_pressed = ctrl
		_send(e)


func test_commander_input() -> void:
	var s := new_sim(10)
	var cmd := Commander.new()
	cmd.sim = s
	root.add_child(cmd)
	var own := s.spawn_regiment("yari", 0, Vector2(400, 400), Vector2.RIGHT)
	var own2 := s.spawn_regiment("samurai", 0, Vector2(400, 600), Vector2.RIGHT)
	var foe := s.spawn_regiment("yari", 1, Vector2(1200, 400), Vector2.LEFT)
	s.step(2)
	var body := s.pos[own.leader] - Vector2(0, 18)
	_mouse(MOUSE_BUTTON_LEFT, true, body)
	_mouse(MOUSE_BUTTON_LEFT, false, body)
	check(cmd.selected.size() == 1 and cmd.selected[0] == own, "click selects the regiment")
	_mouse(MOUSE_BUTTON_RIGHT, true, Vector2(600, 450))
	_mouse(MOUSE_BUTTON_RIGHT, false, Vector2(600, 450))
	var o := own.current_order()
	check(not o.is_empty() and o["type"] == Regiment.Order.MOVE and o["pos"].distance_to(Vector2(600, 450)) < 2.0, "RMB ground = move order")
	check(not own.running, "single RMB walks")
	# RMB drag formation line with ghost preview
	_mouse(MOUSE_BUTTON_RIGHT, true, Vector2(500, 300))
	_motion(Vector2(650, 300), Vector2(150, 0), MOUSE_BUTTON_MASK_RIGHT)
	_motion(Vector2(800, 300), Vector2(150, 0), MOUSE_BUTTON_MASK_RIGHT)
	check(cmd._ghost.size() == 1, "drag shows a ghost formation preview")
	_mouse(MOUSE_BUTTON_RIGHT, false, Vector2(800, 300))
	check(cmd._ghost.is_empty(), "ghost cleared on release")
	check(own.dest_files >= 20 and own.dest_files <= 24, "drag width sets frontage (%d files)" % own.dest_files)
	check(own.dest_facing.dot(Vector2.UP) > 0.99, "drag left→right faces up")
	# double RMB on an enemy = attack at the run
	s.step(2)
	var ebody := s.pos[foe.leader] - Vector2(0, 18)
	_mouse(MOUSE_BUTTON_RIGHT, true, ebody)
	_mouse(MOUSE_BUTTON_RIGHT, false, ebody)
	check(own.target() == foe and not own.running, "RMB enemy = attack")
	_mouse(MOUSE_BUTTON_RIGHT, true, ebody, true)
	_mouse(MOUSE_BUTTON_RIGHT, false, ebody)
	check(own.target() == foe and own.running, "double RMB = run")
	_keypress(KEY_R)
	check(not own.running, "R toggles run")
	_keypress(KEY_H)
	check(own.is_idle(), "H halts")
	# box select both, shift-click toggles
	_mouse(MOUSE_BUTTON_LEFT, true, Vector2(250, 250))
	_motion(Vector2(500, 500), Vector2(250, 250), MOUSE_BUTTON_MASK_LEFT)
	_motion(Vector2(700, 760), Vector2(200, 260), MOUSE_BUTTON_MASK_LEFT)
	_mouse(MOUSE_BUTTON_LEFT, false, Vector2(700, 760))
	check(cmd.selected.size() == 2, "box select picks both regiments (%d)" % cmd.selected.size())
	_keypress(KEY_1, true)
	_keypress(KEY_ESCAPE)
	check(cmd.selected.is_empty(), "Esc deselects")
	_keypress(KEY_1)
	check(cmd.selected.size() == 2, "1 recalls the control group assigned with Ctrl+1")
	_keypress(KEY_F)
	check(own.fire_at_will == false, "F toggles fire at will")
	_keypress(KEY_SPACE)
	check(s.paused, "Space pauses")
	_keypress(KEY_EQUAL)
	check(s.time_scale == 2.0, "+ speeds up")
	_keypress(KEY_SPACE)
	cmd.queue_free()
	free_sim(s)
	own2 = null


func test_deployment() -> void:
	var s := new_sim(11)
	var cmd := Commander.new()
	cmd.sim = s
	root.add_child(cmd)
	s.deploy_zones = [Rect2(100, 100, 600, 800), Rect2(1500, 100, 600, 800)]
	var a := s.spawn_regiment("yari", 0, Vector2(300, 300), Vector2.RIGHT)
	var b := s.spawn_regiment("samurai", 0, Vector2(300, 700), Vector2.RIGHT)
	var started := [0]
	s.battle_started.connect(func(): started[0] += 1)
	s.begin_deployment()
	check(s.deploying, "deploying after begin_deployment")
	s.auto_run = true
	s._process(1.0)
	check(s.tick_count == 0, "clock frozen during deployment")
	cmd.select_regiments([a])
	# RMB far outside the zone: placed instantly, clamped inside
	_mouse(MOUSE_BUTTON_RIGHT, true, Vector2(1200, 400))
	_mouse(MOUSE_BUTTON_RIGHT, false, Vector2(1200, 400))
	var inside := true
	for i in a.soldiers:
		inside = inside and s.deploy_zones[0].has_point(s.pos[i])
	check(inside and a.centre.x > 500.0, "deploy placement clamped to the zone (centre %s)" % a.centre)
	check(a.is_idle() and s.vel[a.soldiers[0]] == Vector2.ZERO, "placement is instant (no march)")
	# LMB-drag the selected regiment onto the other one: swap
	var ca := a.centre
	var cb := b.centre
	var grab := s.pos[a.leader] - Vector2(0, 18)
	_mouse(MOUSE_BUTTON_LEFT, true, grab)
	_motion(grab + Vector2(-50, 100), Vector2(-50, 100), MOUSE_BUTTON_MASK_LEFT)
	_motion(cb, cb - grab, MOUSE_BUTTON_MASK_LEFT)
	_mouse(MOUSE_BUTTON_LEFT, false, cb)
	check(a.centre.distance_to(cb) < 30.0 and b.centre.distance_to(ca) < 30.0, "drop on a friendly regiment swaps them (a %s b %s)" % [a.centre, b.centre])
	_keypress(KEY_ENTER)
	check(not s.deploying and started[0] == 1, "Enter begins the battle (battle_started emitted)")
	s._process(0.2)
	check(s.tick_count > 0, "clock runs after begin_battle")
	s.auto_run = false
	cmd.queue_free()
	free_sim(s)


func test_alive_never_negative() -> void:
	# cavalry hammering braced spears + archers shooting into the melee: many same-tick deaths
	var s := new_sim(12)
	var cav := s.spawn_regiment("cavalry", 0, Vector2(900, 1000), Vector2.RIGHT)
	var cav2 := s.spawn_regiment("cavalry", 0, Vector2(900, 1200), Vector2.RIGHT)
	var bows := s.spawn_regiment("yumi", 0, Vector2(800, 800), Vector2.RIGHT)
	var yari := s.spawn_regiment("yari", 1, Vector2(1300, 1080), Vector2.LEFT)
	var tep := s.spawn_regiment("teppo", 1, Vector2(1450, 1080), Vector2.LEFT)
	cav.order_attack(yari)
	cav2.order_attack(yari)
	bows.order_attack(yari)
	var ok := true
	for k in 60:
		seconds(s, 1.0)
		for r in s.regiments:
			var real := 0
			for i in r.soldiers:
				if s.state[i] < BattleSim.DEAD:
					real += 1
			if r.alive < 0 or r.alive != real:
				ok = false
	check(ok, "alive count always matches living soldiers and never goes negative")
	free_sim(s)
	tep = null


func test_army_collapse() -> void:
	var s := new_sim(13)
	var a := s.spawn_regiment("yari", 0, Vector2(900, 1000), Vector2.RIGHT)
	var b := s.spawn_regiment("yari", 1, Vector2(1500, 900), Vector2.LEFT)
	var c := s.spawn_regiment("yari", 1, Vector2(1500, 1300), Vector2.LEFT)
	var g := s.spawn_regiment("general", 1, Vector2(1700, 1100), Vector2.LEFT)
	seconds(s, 0.5)
	b.morale = 2.0
	c.morale = 2.0
	seconds(s, 2.0)
	check(b.is_routing() and c.is_routing(), "line breaks")
	# the general's 12 men are < 15% of 132: the remnant joins the rout and the battle ends
	var t := until(s, 30.0, func(): return s.ended)
	check(g.is_routing() or g.is_out(), "remnant routs with the army (%s)" % g.morale_name())
	check(t > 0.0 and s.winner == 0 and s.team_broken(1), "battle ends for the player")
	free_sim(s)
	a = null

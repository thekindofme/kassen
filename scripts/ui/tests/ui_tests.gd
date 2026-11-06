extends SceneTree
## Headless UI tests: instantiate every UI scene, check node trees and drive the controls with
## real mouse InputEvents (Input.parse_input_event), like the QA E2E runner will.
##   tools/tmo 120 godot --headless --path . -s res://scripts/ui/tests/ui_tests.gd

var fails := 0
var passes := 0
var game: Node


func _initialize() -> void:
	_run.call_deferred()


func ok(cond: bool, msg: String) -> void:
	if cond:
		passes += 1
		print("  ok   ", msg)
	else:
		fails += 1
		print("  FAIL ", msg)


func frames(n: int) -> void:
	for i in n:
		await process_frame


func click(c: Control, shift := false, double := false) -> void:
	var p := c.get_global_rect().get_center()
	var mm := InputEventMouseMotion.new()
	mm.position = p
	mm.global_position = p
	_send(mm)
	await process_frame
	if OS.get_environment("UI_DEBUG") != "":
		print("    hover at ", p, ": ", root.gui_get_hovered_control())
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = p
		ev.global_position = p
		ev.shift_pressed = shift
		ev.double_click = double and pressed
		_send(ev)
		await process_frame
	await process_frame


## Real InputEvents through Input.parse_input_event; the headless display server does not
## dispatch those to the viewport, so there the event is pushed straight into the root viewport.
func _send(ev: InputEvent) -> void:
	if DisplayServer.get_name() == "headless":
		root.push_input(ev, true)
	else:
		Input.parse_input_event(ev)


func node(root_node: Node, n: String) -> Control:
	return root_node.find_child(n, true, false) as Control


func _run() -> void:
	game = root.get_node_or_null("Game")
	if game == null:
		game = load("res://scripts/ui/game_flow.gd").new()
		game.name = "Game"
		root.add_child(game)
	await frames(2)
	print("viewport ", root.get_visible_rect().size, " window ", root.size)
	await _test_title()
	await _test_select()
	await _test_briefing()
	await _test_hud()
	await _test_results()
	print("UI TESTS: %d passed, %d failed" % [passes, fails])
	quit(1 if fails > 0 else 0)


func _load(path: String) -> Node:
	var n: Node = (load(path) as PackedScene).instantiate()
	root.add_child(n)
	current_scene = n
	await frames(3)
	return n


func _unload(n: Node) -> void:
	n.queue_free()
	await frames(2)


func _test_title() -> void:
	print("[title]")
	var t := await _load("res://scenes/ui/title_screen.tscn")
	for n in ["BattlesButton", "SettingsButton", "QuitButton", "SettingsPanel", "MasterSlider", "MusicSlider", "SfxSlider", "FullscreenCheck", "SettingsClose"]:
		ok(t.get_node_or_null("%" + n) != null, "title has %" + n)
	await frames(100)   # menu items fade in
	var got := [false]
	t.battles_pressed.connect(func(): got[0] = true)
	await click(t.get_node("%SettingsButton"))
	await frames(20)
	ok(t.get_node("%SettingsPanel").visible, "Settings click opens the panel")
	var sl := t.get_node("%MusicSlider") as HSlider
	sl.value = 0.33
	ok(is_equal_approx(float(game.settings["music"]), 0.33), "music slider writes Game.settings")
	await click(t.get_node("%SettingsClose"))
	await frames(20)
	ok(not t.get_node("%SettingsPanel").visible, "Done closes the settings panel")
	game.set("_busy", true)   # keep the flow from actually changing scenes here
	await click(t.get_node("%BattlesButton"))
	ok(got[0], "Battles click emits battles_pressed")
	game.set("_busy", false)
	await _unload(t)


func _test_select() -> void:
	print("[battle select]")
	var s := await _load("res://scenes/ui/battle_select.tscn")
	for n in ["CardKurogawa", "CardTenmoku", "DifficultyEasy", "DifficultyNormal", "DifficultyHard", "BeginButton", "BackButton"]:
		ok(s.get_node_or_null("%" + n) != null, "select has %" + n)
	await frames(60)
	await click(s.get_node("%CardTenmoku"))
	ok(s.selected_key == "tenmoku", "clicking the Tenmoku card selects it")
	ok((s.get_node("%CardTenmoku") as Button).button_pressed and not (s.get_node("%CardKurogawa") as Button).button_pressed, "card toggle group")
	await click(s.get_node("%DifficultyHard"))
	ok(s.difficulty == 2, "difficulty Hard selected")
	var got := []
	s.begin_pressed.connect(func(k, d): got.append([k, d]))
	game.set("_busy", true)
	await click(s.get_node("%BeginButton"))
	game.set("_busy", false)
	ok(got.size() == 1 and got[0] == ["tenmoku", 2], "Begin emits (tenmoku, 2)")
	ok(game.scenario_key == "tenmoku" and game.difficulty == 2, "Game remembers scenario + difficulty")
	game.choose("kurogawa", 1)
	await _unload(s)


func _test_briefing() -> void:
	print("[briefing]")
	var b := await _load("res://scenes/ui/briefing.tscn")
	for n in ["ContinueButton", "BackButton", "Line1", "Line2", "Line3", "BriefTitle"]:
		ok(b.get_node_or_null("%" + n) != null, "briefing has %" + n)
	ok((b.get_node("%Line1") as Label).text.length() > 20, "line 1 has narrative text")
	b.skip()
	await frames(2)
	ok(is_equal_approx((b.get_node("%Line3") as Label).visible_ratio, 1.0), "skip() finishes the ink reveal")
	await _unload(b)


func _test_hud() -> void:
	print("[battle HUD]")
	var battle: Node = (load("res://scenes/battle.tscn") as PackedScene).instantiate()
	var hud: Node = battle.find_child("Hud", false, false)
	if hud == null:
		hud = (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate()
		battle.add_child(hud)
	root.add_child(battle)
	current_scene = battle
	await frames(5)
	var sim: BattleSim = battle.get("sim")
	var cmd: Commander = battle.get("commander")
	var cam: Camera2D = battle.get("camera")
	ok(hud.sim == sim and hud.commander == cmd, "Hud auto-bound to the battle")
	var hr: Control = hud.root
	for n in ["CardTray", "Minimap", "BattleTimer", "SpeedPause", "Speed1", "Speed2", "Speed3", "PowerBar", "OrdersPanel",
			"OrderHalt", "OrderRun", "OrderFire", "OrderWithdraw", "DeployBanner", "BeginBattleButton", "Toasts"]:
		ok(hr.get_node_or_null("%" + n) != null, "hud has %" + n)
	var own := sim.regiments_of(0)
	ok(hud.cards.size() == own.size(), "one card per player regiment (%d)" % own.size())
	ok(hud.deploying and (bool(sim.get("deploying")) if sim.get("deploying") != null else sim.paused), "battle starts in deployment")
	await frames(30)
	var c0: UnitCard = hr.get_node("%" + ("Card_%d" % own[0].id))
	var c1: UnitCard = hr.get_node("%" + ("Card_%d" % own[1].id))
	await click(c0)
	ok(cmd.selected == [own[0]], "card click selects its regiment")
	ok(c0.selected, "card shows selected")
	await click(c1, true)
	ok(cmd.selected.size() == 2 and cmd.selected.has(own[1]), "shift-click adds")
	await click(c1, true)
	ok(cmd.selected.size() == 1, "shift-click on a selected card removes it")
	await frames(15)
	ok(hr.get_node("%OrdersPanel").visible, "orders panel visible with a selection")
	var run_before := own[0].running
	await click(hr.get_node("%OrderRun"))
	ok(own[0].running != run_before, "Run order button toggles running")
	var far := own[own.size() - 1]
	var before: Vector2 = cam.get("target_pos")
	await click(hr.get_node("%" + ("Card_%d" % far.id)), false, true)
	ok(cmd.selected == [far], "double-click selects")
	ok((cam.get("target_pos") as Vector2).distance_to(far.mean_pos) < 400.0 or before.distance_to(far.mean_pos) < 5.0, "double-click centres the camera")
	var mm: Minimap = hr.get_node("%Minimap")
	await click(mm)
	var expect := mm.m2w(mm.size * 0.5)
	ok((cam.get("target_pos") as Vector2).distance_to(expect) < 600.0, "minimap click moves the camera")
	var begun := [false]
	hud.battle_begun.connect(func(): begun[0] = true)
	await click(hr.get_node("%BeginBattleButton"))
	ok(begun[0] and not hud.deploying and not sim.paused and not bool(sim.get("deploying")), "Begin Battle ends deployment")
	await frames(5)
	await click(hr.get_node("%Speed3"))
	ok(is_equal_approx(sim.time_scale, 3.0), "×3 speed button")
	await click(hr.get_node("%SpeedPause"))
	ok(sim.paused, "pause button")
	await click(hr.get_node("%Speed1"))
	ok(not sim.paused and is_equal_approx(sim.time_scale, 1.0), "×1 resumes")
	var enemy := sim.regiments_of(1)[0]
	sim.regiment_routed.emit(enemy)
	sim.general_killed.emit(0)
	await frames(2)
	ok(hr.get_node("%Toasts").get_child_count() >= 2, "rout / general toasts shown")
	var fin := [-1]
	hud.battle_finished.connect(func(w): fin[0] = w)
	game.set("_results_shown", true)   # don't open the scroll from the Game here
	sim.battle_ended.emit(0)
	await frames(2)
	ok(fin[0] == 0, "battle_finished(0) on victory")
	var res: Dictionary = hud.collect_result(0)
	ok(res.has("teams") and res["teams"].size() == 2 and res.has("regiments") and res.has("heroic"), "collect_result shape")
	await _unload(battle)


func _test_results() -> void:
	print("[results]")
	var res: Node = (load("res://scenes/ui/results.tscn") as PackedScene).instantiate()
	root.add_child(res)
	await frames(2)
	res.show_result(load("res://scripts/ui/dev/ui_shot.gd")._fake_result())
	res.finish_animation()
	await frames(150)
	var rr: Control = res.root
	for n in ["ReplayButton", "MenuButton", "Scroll", "RegimentTable", "HeroPanel", "ResultTitle"]:
		ok(rr.get_node_or_null("%" + n) != null, "results has %" + n)
	ok((rr.get_node("%RegimentTable") as GridContainer).get_child_count() == 5 * 7, "regiments table rows")
	var got := [0]
	res.replay_pressed.connect(func(): got[0] += 1)
	res.menu_pressed.connect(func(): got[0] += 10)
	await click(rr.get_node("%ReplayButton"))
	await click(rr.get_node("%MenuButton"))
	ok(got[0] == 11, "Replay and Main Menu buttons emit")
	res.queue_free()
	await frames(2)

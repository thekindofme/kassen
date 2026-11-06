extends SceneTree
## Headless end-to-end flow through the real UI with mouse events:
## title → Battles → select (Tenmoku, Hard) → Begin → briefing → Continue → battle (deploy) →
## Begin Battle → forced victory → Results scroll → Main Menu → title.
##   tools/tmo 180 godot --headless --path . -s res://scripts/ui/tests/flow_test.gd

var fails := 0


func _initialize() -> void:
	_run.call_deferred()


func ok(c: bool, m: String) -> void:
	print(("  ok   " if c else "  FAIL ") + m)
	if not c:
		fails += 1


func frames(n: int) -> void:
	for i in n:
		await process_frame


func wait_state(game: Node, s: String, max_frames := 600) -> bool:
	for i in max_frames:
		if game.state == s and not game.get("_busy"):
			await frames(3)
			return true
		await process_frame
	return false


func click_named(n: String) -> bool:
	var c := root.find_child(n, true, false) as Control
	if c == null:
		print("    (no control ", n, ")")
		return false
	var p := c.get_global_rect().get_center()
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = p
		ev.global_position = p
		if DisplayServer.get_name() == "headless":
			root.push_input(ev, true)
		else:
			Input.parse_input_event(ev)
		await process_frame
	return true


func _run() -> void:
	var game := root.get_node("Game")
	game.goto_title(false)
	ok(await wait_state(game, "title"), "title shown")
	await frames(120)
	await click_named("BattlesButton")
	ok(await wait_state(game, "select"), "Battles → battle select")
	await frames(30)
	await click_named("CardTenmoku")
	await click_named("DifficultyHard")
	await click_named("BeginButton")
	ok(await wait_state(game, "briefing"), "Begin → briefing")
	ok(game.scenario_key == "tenmoku" and game.difficulty == 2, "choice passed to Game (tenmoku, hard)")
	game.choose("kurogawa", 1)
	await frames(10)
	current_scene.call("skip")
	await frames(5)
	await click_named("ContinueButton")
	ok(await wait_state(game, "battle"), "Continue → battle")
	await frames(10)
	var hud := current_scene.find_child("Hud", false, false)
	ok(hud != null and hud.get("sim") != null, "battle has a bound Hud")
	var sim = current_scene.get("sim")
	ok(hud.deploying, "deployment phase")
	await click_named("BeginBattleButton")
	await frames(5)
	ok(not hud.deploying and not bool(sim.get("deploying")), "Begin Battle starts the fight")
	await frames(30)
	sim.battle_ended.emit(0)
	ok(await wait_state(game, "results", 900), "victory → results scroll")
	var res := current_scene.find_child("Results", false, false)
	ok(res != null, "Results node in the battle scene")
	if res != null:
		res.call("finish_animation")
	await frames(10)
	await click_named("MenuButton")
	ok(await wait_state(game, "title"), "Main Menu → title")
	print("FLOW TEST: %s" % ("PASS" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails > 0 else 0)

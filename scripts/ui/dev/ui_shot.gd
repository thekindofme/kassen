extends SceneTree
## Dev tool: render a UI scene and save a screenshot.
##   tools/render_run.sh -s res://scripts/ui/dev/ui_shot.gd -- --scene=res://scenes/ui/title_screen.tscn \
##       --out=/tmp/x.png [--frames=90] [--hover=NodeName] [--call=method] [--battle]
## --battle loads scenes/battle.tscn (the Hud binds itself); --results shows a fake result scroll.

var args := {}
var frames := 0
var target := 90
var scene: Node


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1] if kv.size() > 1 else true
	target = int(args.get("frames", 90))
	if root.get_node_or_null("Game") == null:
		var g: Node = load("res://scripts/ui/game_flow.gd").new()
		g.name = "Game"
		root.add_child(g)
	var path: String = args.get("scene", "res://scenes/ui/title_screen.tscn")
	if args.has("battle"):
		path = "res://scenes/battle.tscn"
	change_scene_to_file.call_deferred(path)


func _process(_d: float) -> bool:
	frames += 1
	if frames == 3 and args.has("battle") and current_scene.find_child("Hud", false, false) == null:
		current_scene.add_child(load("res://scenes/ui/hud.tscn").instantiate())
	if frames == 20 and args.has("battle"):
		var hud := current_scene.find_child("Hud", false, false)
		var cmd = current_scene.get("commander")
		if args.has("select") and cmd != null:
			var regs: Array = current_scene.sim.regiments_of(0).slice(0, int(args["select"]))
			cmd.select_regiments(regs, false)
		if args.has("fight") and hud != null:
			hud.begin_battle()
			current_scene.sim.time_scale = float(args.get("speed", 3.0))
		if args.has("toast") and hud != null:
			hud.toast("Mizuno Yari Cavalry are routing!", "good")
			hud.toast("Your general has fallen!", "bad")
	if frames == 5 and args.has("results"):
		var g := root.get_node("Game")
		g.show_results(_fake_result())
	if frames == 10 and args.has("hover"):
		var n := current_scene.find_child(String(args["hover"]), true, false) as Control
		if n != null:
			var ev := InputEventMouseMotion.new()
			ev.position = n.get_global_rect().get_center()
			ev.global_position = ev.position
			Input.parse_input_event(ev)
	if frames == 12 and args.has("call"):
		for c in String(args["call"]).split(";"):
			var parts := c.split(":")
			var node := current_scene if parts.size() == 1 else current_scene.find_child(parts[0], true, false)
			node.call(parts[-1])
	if frames == target:
		_save()
	return false


func _save() -> void:
	if args.has("dump"):
		for n in String(args["dump"]).split(","):
			var c := current_scene.find_child(n, true, false) as Control
			if c != null:
				print("[dump] ", n, " ", c.get_global_rect(), " anchors ", c.anchor_left, " off ", c.offset_left, ",", c.offset_right)
				for ch in c.get_children():
					if ch is Control:
						print("    child ", ch.name, " ", ch.get_global_rect())
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var out: String = args.get("out", "/tmp/ui_shot.png")
	img.save_png(out)
	print("[ui_shot] saved ", out)
	quit(0)


static func _fake_result() -> Dictionary:
	return {
		"winner": 0, "scenario": "The Ford at Kurogawa", "time": 734.0, "difficulty": "Bushidō",
		"teams": [
			{"name": "Hino", "initial": 456, "alive": 301, "lost": 155, "kills": 322},
			{"name": "Mizuno", "initial": 456, "alive": 134, "lost": 322, "kills": 155},
		],
		"regiments": [
			{"name": "Katana Samurai", "type": "samurai", "team": 0, "initial": 32, "alive": 27, "kills": 61, "status": "Steady"},
			{"name": "Yari Ashigaru", "type": "yari", "team": 0, "initial": 60, "alive": 31, "kills": 48, "status": "Wavering"},
			{"name": "Yumi Ashigaru", "type": "yumi", "team": 0, "initial": 40, "alive": 38, "kills": 44, "status": "Eager"},
			{"name": "Teppo Ashigaru", "type": "teppo", "team": 0, "initial": 40, "alive": 35, "kills": 39, "status": "Steady"},
			{"name": "Yari Cavalry", "type": "cavalry", "team": 0, "initial": 20, "alive": 9, "kills": 30, "status": "Routing"},
			{"name": "General's Hatamoto", "type": "general", "team": 0, "initial": 12, "alive": 11, "kills": 12, "status": "Eager"},
		],
		"heroic": {"name": "Katana Samurai", "type": "samurai", "team": 0, "kills": 61, "initial": 32, "alive": 27},
	}

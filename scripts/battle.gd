extends Node2D
## Battle scene root: builds terrain, sim, renderer, input and the (placeholder) enemy AI,
## spawns both armies from the map definition, and shows a minimal debug HUD.
##
## User args (after `--`):
##   --map=kurogawa  --seed=N  --demo (AI plays both sides)  --speed=X
##   --shot=path.png [--shot_frames=N] [--shot_sim=SECONDS] [--cam=x,y,zoom]
##       fast-forward SECONDS of simulation, wait N rendered frames, save a screenshot and quit.

const MAPS := {"kurogawa": "res://scripts/world/maps/kurogawa.gd"}

var map: MapDef
var terrain: Terrain
var sim: BattleSim
var renderer: SoldierRenderer
var commander: Commander
var camera: BattleCamera
var ai: PlaceholderAI
var ai_player: PlaceholderAI
var trees: Node2D
var hud_label: Label
var result_label: Label
var args := {}
var _frames := 0
var _shot_pending := false


func _ready() -> void:
	args = _parse_args()
	var map_key: String = args.get("map", "kurogawa")
	map = load(MAPS.get(map_key, MAPS["kurogawa"])).new()

	terrain = Terrain.new()
	terrain.name = "Terrain"
	add_child(terrain)
	terrain.build(map)

	var village := _VillageLayer.new()
	village.name = "Village"
	village.map = map
	add_child(village)

	sim = BattleSim.new()
	sim.name = "BattleSim"
	add_child(sim)
	sim.setup(map.size, terrain, int(args.get("seed", map.seed_value)), map.home_dirs)
	for team in 2:
		for e in map.armies[team]:
			sim.spawn_regiment(e["type"], team, e["pos"], e["facing"])

	commander = Commander.new()
	commander.name = "Commander"
	commander.sim = sim
	add_child(commander)   # ghost markers under the soldiers

	renderer = SoldierRenderer.new()
	renderer.name = "SoldierRenderer"
	add_child(renderer)
	renderer.setup(sim)
	commander.renderer = renderer

	trees = _TreeLayer.new()
	trees.name = "TreeCanopy"
	trees.terrain = terrain
	trees.sim = sim
	add_child(trees)

	camera = BattleCamera.new()
	camera.name = "BattleCamera"
	camera.map_rect = Rect2(Vector2.ZERO, map.size)
	add_child(camera)
	camera.make_current()
	var own := sim.regiments_of(0)
	var start := map.deploy_zones[0].get_center() + Vector2(500, 0)
	camera.position = start
	camera.focus_on(start, 0.6)
	camera.snap()
	commander.camera = camera

	ai = PlaceholderAI.new()
	ai.name = "EnemyAI"
	ai.sim = sim
	ai.team = 1
	add_child(ai)
	if args.has("demo"):
		ai_player = PlaceholderAI.new()
		ai_player.name = "PlayerAI"
		ai_player.sim = sim
		ai_player.team = 0
		add_child(ai_player)
	if args.has("speed"):
		sim.time_scale = float(args["speed"])

	_build_hud()
	sim.battle_ended.connect(_on_battle_ended)

	if args.has("shot"):
		_shot_pending = true
		var pre := float(args.get("shot_sim", 0.0))
		if pre > 0.0:
			if ai_player == null:
				ai_player = PlaceholderAI.new()
				ai_player.sim = sim
				ai_player.team = 0
				add_child(ai_player)
			var ticks := int(pre * BattleSim.TICK_HZ)
			for k in ticks:
				sim.step(1)
				if k % 15 == 0 and sim.time > ai.start_delay:
					ai.think()
					ai_player.think()
		if args.has("cam"):
			var c: PackedStringArray = String(args["cam"]).split(",")
			camera.focus_on(Vector2(float(c[0]), float(c[1])), float(c[2]) if c.size() > 2 else 1.0)
			camera.snap()


func _parse_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1] if kv.size() > 1 else true
	return out


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "DebugHud"
	add_child(layer)
	hud_label = Label.new()
	hud_label.position = Vector2(16, 12)
	hud_label.add_theme_color_override("font_color", Color("#E8DDC4"))
	hud_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	hud_label.add_theme_constant_override("shadow_offset_x", 1)
	hud_label.add_theme_constant_override("shadow_offset_y", 1)
	layer.add_child(hud_label)
	result_label = Label.new()
	result_label.add_theme_font_size_override("font_size", 64)
	result_label.add_theme_color_override("font_color", Color("#C9A04A"))
	result_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	result_label.add_theme_constant_override("shadow_offset_x", 3)
	result_label.add_theme_constant_override("shadow_offset_y", 3)
	result_label.anchor_left = 0.5
	result_label.anchor_right = 0.5
	result_label.anchor_top = 0.3
	result_label.offset_left = -400
	result_label.offset_right = 400
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.visible = false
	layer.add_child(result_label)


func _on_battle_ended(winner: int) -> void:
	result_label.text = "VICTORY" if winner == 0 else "DEFEAT"
	result_label.visible = true


func _process(_delta: float) -> void:
	_frames += 1
	if hud_label != null and _frames % 6 == 0:
		var sel := ""
		for r in commander.selected:
			sel += "\n  %s  %d men  morale %d (%s)  fatigue %d%%%s%s" % [r.display_name, r.alive, int(r.morale), r.morale_name(),
				int(r.fatigue * 100), "  RUN" if r.running else "", "" if r.fire_at_will or not r.is_ranged() else "  HOLD FIRE"]
		hud_label.text = "KASSEN — %s   %s x%.1f   t=%ds\nHino %d   Mizuno %d   fps %d  render %.2f ms%s" % [
			map.title, "PAUSED " if sim.paused else "", sim.time_scale, int(sim.time),
			sim.men_alive(0, false), sim.men_alive(1, false), Engine.get_frames_per_second(), renderer.last_update_ms, sel]
	if _shot_pending and _frames >= int(args.get("shot_frames", 90)):
		_shot_pending = false
		_save_shot(String(args["shot"]))


func _save_shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(path)
	print("[battle] screenshot -> %s (err %d)" % [path, err])
	get_tree().quit(0 if err == OK else 1)


# =====================================================================================
#  Placeholder props: village houses (ground layer) and tree canopies (above soldiers,
#  fading where soldiers stand underneath).
# =====================================================================================

class _VillageLayer extends Node2D:
	var map: MapDef

	func _draw() -> void:
		for h in map.houses:
			var w := 70.0
			var d := 44.0
			draw_colored_polygon(PackedVector2Array([h + Vector2(-w * 0.5 + 8, 6), h + Vector2(w * 0.5 + 14, 6), h + Vector2(w * 0.5 + 14, -10), h + Vector2(-w * 0.5 + 8, -10)]), Color(0.08, 0.07, 0.05, 0.3))
			draw_rect(Rect2(h + Vector2(-w * 0.5, -26), Vector2(w, 26)), Color("#6B4A2E"))
			draw_rect(Rect2(h + Vector2(-w * 0.5 + 6, -20), Vector2(14, 20)), Color("#2A1D13"))
			var roof := PackedVector2Array([h + Vector2(-w * 0.5 - 8, -24), h + Vector2(w * 0.5 + 8, -24), h + Vector2(w * 0.5 - 6, -24 - d), h + Vector2(-w * 0.5 + 6, -24 - d)])
			draw_colored_polygon(roof, Color("#9C8452"))
			draw_line(h + Vector2(-w * 0.5 + 6, -24 - d), h + Vector2(w * 0.5 - 6, -24 - d), Color("#5A4A2C"), 4.0)


class _TreeLayer extends Node2D:
	var terrain: Terrain
	var sim: BattleSim
	var mmi: MultiMeshInstance2D
	var alpha := PackedFloat32Array()
	var _t := 0.0

	func _ready() -> void:
		var tex := _make_tree_texture()
		mmi = MultiMeshInstance2D.new()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_2D
		mm.use_colors = true
		mm.mesh = SoldierRenderer.unit_quad()
		var n := terrain.trees.size()
		mm.instance_count = n
		mm.custom_aabb = AABB(Vector3(-100, -200, -1), Vector3(terrain.size.x + 200, terrain.size.y + 400, 2))
		alpha.resize(n)
		alpha.fill(1.0)
		var order := Array(range(n))
		order.sort_custom(func(a, b): return terrain.trees[a].y < terrain.trees[b].y)
		var sorted := PackedVector2Array()
		var scales := PackedFloat32Array()
		for i in order:
			sorted.append(terrain.trees[i])
			scales.append(terrain.tree_scale[i])
		terrain.trees = sorted
		terrain.tree_scale = scales
		for k in n:
			var s := terrain.tree_scale[k]
			var w := 92.0 * s
			var h := 118.0 * s
			var p := terrain.trees[k]
			mm.set_instance_transform_2d(k, Transform2D(Vector2(w, 0), Vector2(0, h), p + Vector2(-w * 0.5, -h + 6)))
			var tint := 0.85 + 0.15 * fmod(float(k) * 0.618, 1.0)
			mm.set_instance_color(k, Color(tint, tint, tint * 0.95, 1.0))
		mmi.multimesh = mm
		mmi.texture = tex
		add_child(mmi)

	func _process(delta: float) -> void:
		_t += delta
		if _t < 0.2 or sim == null:
			return
		_t = 0.0
		var mm := mmi.multimesh
		for k in terrain.trees.size():
			var p := terrain.trees[k]
			var under := false
			var c := sim._query(p + Vector2(0, -20), 34.0)
			for q in c:
				var j: int = sim._nb[q]
				var d: Vector2 = sim.pos[j] - p
				if d.y < 12.0 and d.y > -70.0 and absf(d.x) < 40.0:
					under = true
					break
			var target := 0.35 if under else 1.0
			if absf(alpha[k] - target) > 0.01:
				alpha[k] = move_toward(alpha[k], target, 0.25)
				var tint := 0.85 + 0.15 * fmod(float(k) * 0.618, 1.0)
				mm.set_instance_color(k, Color(tint, tint, tint * 0.95, alpha[k]))

	func _make_tree_texture() -> Texture2D:
		var W := 92
		var H := 118
		var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		img.fill_rect(Rect2i(W / 2 - 4, H - 40, 8, 36), Color("#4A3322"))
		var blobs := [[46, 52, 34, Color("#2F4A26")], [30, 62, 24, Color("#34522A")], [62, 60, 25, Color("#2B4422")],
			[46, 34, 26, Color("#3B5C2E")], [38, 44, 18, Color("#46693A")], [56, 40, 16, Color("#40613A")]]
		for b in blobs:
			var cx: int = b[0]
			var cy: int = b[1]
			var r: int = b[2]
			var col: Color = b[3]
			for y in range(cy - r, cy + r + 1):
				var t := float(y - cy) / r
				var hw := int(r * sqrt(maxf(0.0, 1.0 - t * t)))
				if y >= 0 and y < H:
					var shade := col.lightened(0.12 * (1.0 - float(y - cy + r) / (2.0 * r)))
					img.fill_rect(Rect2i(clampi(cx - hw, 0, W - 1), y, mini(hw * 2, W - (cx - hw)), 1), shade)
		img.generate_mipmaps()
		return ImageTexture.create_from_image(img)

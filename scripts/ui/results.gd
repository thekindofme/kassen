class_name Results
extends CanvasLayer
## Results scroll: victory/defeat painting, a washi scroll that unrolls between two lacquer rods,
## casualties per side, the regiments table (kills / losses), the heroic regiment and
## Replay / Main Menu.
##
##   Results.show_result(data)   data from Hud.collect_result(winner):
##     {winner, time, scenario, difficulty, teams:[{name, initial, alive, lost, kills}x2],
##      regiments:[{name, type, team, initial, alive, kills, status}], heroic:{...}}
## Stable nodes: %ReplayButton %MenuButton %Scroll %RegimentTable %HeroPanel %ResultTitle

signal replay_pressed
signal menu_pressed

const SCROLL_W := 1100.0
const SCROLL_H := 740.0

var root: Control
var data: Dictionary
var _scroll: Control
var _paper: Control
var _content: VBoxContainer
var _top_rod: Control
var _bot_rod: Control


func _ready() -> void:
	layer = 50
	name = "Results"
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.name = "Root"
	root.theme = UiKit.theme()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)


func show_result(p_data: Dictionary) -> void:
	data = p_data
	var win := int(data.get("winner", 0)) == 0
	var g := get_node_or_null("/root/Game")
	# pause the battle underneath
	var sim := get_tree().get_first_node_in_group("sim")
	if sim != null and sim.get("paused") != null:
		sim.set("paused", true)
	UiKit.phase(self, "victory" if win else "defeat")
	# backdrop
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.015, 0.01, 0.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	create_tween().tween_property(bg, "color:a", 0.85, 0.6)
	var art := TextureRect.new()
	art.name = "ResultArt"
	art.texture = UiKit.art("victory" if win else "defeat")
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(art)
	art.modulate = Color(0.75, 0.72, 0.7, 0.0)
	create_tween().tween_property(art, "modulate:a", 1.0, 1.2).set_delay(0.2)
	TitleFx.ken_burns(self, art, Vector2(1920, 1080), 30.0, Vector2(-0.05, -0.02))
	root.add_child(TitleFx.gradient_rect(Color(0.02, 0.015, 0.01, 0.15), Color(0.02, 0.015, 0.01, 0.8), false, 1.0))
	if win:
		root.add_child(TitleFx.embers(Vector2(1920, 1080), 30))
	else:
		root.add_child(TitleFx.mist_layer(Vector2(1920, 1080), 12, Color(0.8, 0.8, 0.82, 0.16)))
	# title
	var title := UiKit.label("Victory" if win else "Defeat", "TitleLabel", 96, UiKit.GOLD if win else Color("#D8533A"))
	title.add_theme_constant_override("outline_size", 10)
	title.position = Vector2(110, 60)
	root.add_child(title)
	UiKit.expose(title, "ResultTitle", root)
	UiKit.fade_in(title, 0.8, 0.4)
	var kan := UiKit.label("勝利" if win else "敗北", "BrushLabel", 64, UiKit.WASHI if win else Color("#E8B0A0"))
	kan.position = Vector2(116, 190)
	root.add_child(kan)
	UiKit.fade_in(kan, 0.8, 0.7)
	var sub := UiKit.label("%s\n%s · %s" % [String(data.get("scenario", "")), UiKit.fmt_time(float(data.get("time", 0.0))),
		String(data.get("difficulty", ""))], "", 22, Color(UiKit.WASHI, 0.85))
	sub.position = Vector2(118, 290)
	root.add_child(sub)
	UiKit.fade_in(sub, 0.8, 0.9)
	_build_scroll()
	_build_buttons()
	_unroll()


func _build_scroll() -> void:
	_scroll = Control.new()
	_scroll.name = "ScrollHolder"
	_scroll.position = Vector2(700, 110)
	_scroll.size = Vector2(SCROLL_W, SCROLL_H)
	_scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_scroll)
	_paper = Control.new()
	_paper.position = Vector2(20, 22)
	_paper.size = Vector2(SCROLL_W - 40, 0)
	_paper.clip_contents = true
	_scroll.add_child(_paper)
	UiKit.expose(_paper, "Scroll", root)
	var washi := PanelContainer.new()
	washi.theme_type_variation = &"WashiPanel"
	washi.position = Vector2.ZERO
	washi.size = Vector2(SCROLL_W - 40, SCROLL_H - 44)
	washi.custom_minimum_size = washi.size
	_paper.add_child(washi)
	var m := MarginContainer.new()
	for side in ["left", "right"]:
		m.add_theme_constant_override("margin_" + side, 48)
	m.add_theme_constant_override("margin_top", 26)
	washi.add_child(m)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 10)
	m.add_child(_content)
	_fill_content()
	_top_rod = _Rod.new()
	_top_rod.size = Vector2(SCROLL_W, 30)
	_top_rod.position = Vector2(0, 8)
	_scroll.add_child(_top_rod)
	_bot_rod = _Rod.new()
	_bot_rod.size = Vector2(SCROLL_W, 30)
	_bot_rod.position = Vector2(0, 8)
	_scroll.add_child(_bot_rod)


func _fill_content() -> void:
	var teams: Array = data.get("teams", [])
	# casualties per side
	var head := UiKit.label("Casualties  死傷", "InkLabel", 30)
	head.add_theme_font_override("font", UiKit.font_title())
	_content.add_child(head)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 40)
	_content.add_child(row)
	for t in mini(teams.size(), 2):
		var td: Dictionary = teams[t]
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", 12)
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(box)
		var mon := TextureRect.new()
		mon.texture = UiKit.mon(t)
		mon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		mon.custom_minimum_size = Vector2(56, 56)
		mon.modulate = Color(0.25, 0.15, 0.1) if t == 1 else Color(1, 1, 1)
		box.add_child(mon)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		box.add_child(v)
		v.add_child(UiKit.label(String(td.get("name", "")), "InkLabel", 24, UiKit.team_color(t)))
		v.add_child(UiKit.label("%d fallen of %d  ·  %d remain" % [int(td.get("lost", 0)), int(td.get("initial", 0)), int(td.get("alive", 0))], "InkLabel", 20, Color("#3A2A1C")))
	_content.add_child(_rule())
	# regiments table (player)
	var th := UiKit.label("Your regiments  部隊", "InkLabel", 26)
	th.add_theme_font_override("font", UiKit.font_title())
	_content.add_child(th)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 26)
	grid.add_theme_constant_override("v_separation", 2)
	_content.add_child(grid)
	UiKit.expose(grid, "RegimentTable", root)
	for hcap in ["Regiment", "Men", "Losses", "Kills", "State"]:
		grid.add_child(UiKit.label(hcap.to_upper(), "InkLabel", 16, Color("#7A1A10")))
	var regs: Array = data.get("regiments", [])
	for rd in regs:
		if int(rd.get("team", 0)) != 0:
			continue
		var losses := int(rd.get("initial", 0)) - int(rd.get("alive", 0))
		var cells := [String(rd.get("name", "")), "%d/%d" % [int(rd.get("alive", 0)), int(rd.get("initial", 0))], str(losses),
			str(int(rd.get("kills", 0))), String(rd.get("status", ""))]
		for i in cells.size():
			var l := UiKit.label(cells[i], "InkLabel", 20, Color("#21170F"))
			if i > 0:
				l.add_theme_font_override("font", UiKit.font_body())
			if i == 0:
				l.custom_minimum_size = Vector2(300, 0)
			grid.add_child(l)
	_content.add_child(_rule())
	# heroic regiment
	var hero: Dictionary = data.get("heroic", {})
	if not hero.is_empty():
		var hp := HBoxContainer.new()
		hp.add_theme_constant_override("separation", 20)
		_content.add_child(hp)
		UiKit.expose(hp, "HeroPanel", root)
		var por := TextureRect.new()
		por.texture = UiKit.portrait(String(hero.get("type", "samurai")))
		por.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		por.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		por.custom_minimum_size = Vector2(110, 110)
		hp.add_child(por)
		var hv := VBoxContainer.new()
		hv.alignment = BoxContainer.ALIGNMENT_CENTER
		hp.add_child(hv)
		hv.add_child(UiKit.label("Heroic regiment  誉", "InkLabel", 18, Color("#7A1A10")))
		var hn := UiKit.label(String(hero.get("name", "")), "InkLabel", 34)
		hn.add_theme_font_override("font", UiKit.font_title())
		hv.add_child(hn)
		hv.add_child(UiKit.label("%d enemies slain · %d of %d men stand" % [int(hero.get("kills", 0)), int(hero.get("alive", 0)), int(hero.get("initial", 0))],
			"InkLabel", 20, Color("#3A2A1C")))


func _rule() -> Control:
	var c := ColorRect.new()
	c.color = Color(0.45, 0.12, 0.08, 0.45)
	c.custom_minimum_size = Vector2(0, 2)
	return c


func _build_buttons() -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 24)
	h.position = Vector2(110, 940)
	root.add_child(h)
	var rp := Button.new()
	rp.text = "Replay  再戦"
	rp.custom_minimum_size = Vector2(250, 70)
	rp.pressed.connect(func():
		UiKit.sfx(self, "confirm")
		replay_pressed.emit())
	h.add_child(rp)
	UiKit.expose(rp, "ReplayButton", root)
	var mm := Button.new()
	mm.text = "Main Menu"
	mm.custom_minimum_size = Vector2(250, 70)
	mm.pressed.connect(func():
		UiKit.sfx(self, "back")
		menu_pressed.emit())
	h.add_child(mm)
	UiKit.expose(mm, "MenuButton", root)
	UiKit.fade_in(h, 0.6, 2.2)


func _unroll() -> void:
	var t := create_tween().set_parallel(true)
	t.tween_property(_paper, "size:y", SCROLL_H - 44, 1.5).set_delay(0.6).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(_bot_rod, "position:y", SCROLL_H - 38, 1.5).set_delay(0.6).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN_OUT)
	_scroll.modulate.a = 0.0
	t.tween_property(_scroll, "modulate:a", 1.0, 0.4).set_delay(0.3)
	t.tween_callback(func(): UiKit.sfx(self, "open")).set_delay(0.6)


## Skip the unroll animation (tests / impatient players).
func finish_animation() -> void:
	_paper.size.y = SCROLL_H - 44
	_bot_rod.position.y = SCROLL_H - 38
	_scroll.modulate.a = 1.0


class _Rod extends Control:
	func _draw() -> void:
		var r := Rect2(Vector2(14, 4), Vector2(size.x - 28, size.y - 8))
		draw_rect(r, Color("#1A110C"))
		draw_rect(Rect2(r.position.x, r.position.y + 3, r.size.x, 4), Color(1, 0.85, 0.6, 0.18))
		draw_rect(r, UiKit.GOLD_LO, false, 1.5)
		for side in [0.0, 1.0]:
			var x := lerpf(0.0, size.x - 22, side)
			var cap := Rect2(Vector2(x, 0), Vector2(22, size.y))
			draw_rect(cap, UiKit.GOLD)
			draw_rect(Rect2(cap.position + Vector2(3, 3), cap.size - Vector2(6, 6)), Color("#8A6526"))
			draw_rect(cap, Color("#3A2A10"), false, 1.0)

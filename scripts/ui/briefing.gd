extends Control
## Briefing card: the scenario painting (Ken Burns), title and date, and three narrative lines
## that appear like ink soaking into washi. Continue → battle. Click / Space skips the writing.
##
## Stable nodes: %ContinueButton %BackButton %Line1 %Line2 %Line3 %BriefTitle

signal continue_pressed

var lines: Array[Label] = []
var _continue: Button
var _writing := true
var _tweens: Array[Tween] = []


func _ready() -> void:
	theme = UiKit.theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var g := get_node_or_null("/root/Game")
	var sc: Dictionary = g.scenario() if g != null else {"title": "The Ford at Kurogawa", "art": "kurogawa", "kanji": "黒川",
		"date": "Tenshō 2 (1574)", "briefing": ["…", "…", "…"]}
	var bg := ColorRect.new()
	bg.color = UiKit.LACQUER
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var art := TextureRect.new()
	art.name = "Painting"
	art.texture = UiKit.art(String(sc["art"]))
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(art)
	TitleFx.ken_burns(self, art, Vector2(1920, 1080), 26.0, Vector2(-0.08, -0.03))
	add_child(TitleFx.mist_layer(Vector2(1920, 1080), 10, Color(0.95, 0.92, 0.88, 0.12)))
	add_child(TitleFx.gradient_rect(Color(0, 0, 0, 0.0), Color(0.03, 0.02, 0.015, 0.92), false, 1.0))
	# washi strip
	var strip := PanelContainer.new()
	strip.name = "Scroll"
	strip.theme_type_variation = &"WashiPanel"
	strip.position = Vector2(220, 640)
	strip.custom_minimum_size = Vector2(1480, 0)
	add_child(strip)
	var m := MarginContainer.new()
	for s in ["left", "right"]:
		m.add_theme_constant_override("margin_" + s, 60)
	m.add_theme_constant_override("margin_top", 30)
	m.add_theme_constant_override("margin_bottom", 36)
	strip.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	m.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var t := UiKit.label(String(sc["title"]), "InkLabel", 44)
	t.add_theme_font_override("font", UiKit.font_title())
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	UiKit.expose(t, "BriefTitle", self)
	var d := UiKit.label(String(sc.get("date", "")), "InkLabel", 20, Color(0.35, 0.22, 0.14))
	d.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(d)
	var rule := ColorRect.new()
	rule.color = Color(0.45, 0.12, 0.08, 0.6)
	rule.custom_minimum_size = Vector2(0, 2)
	v.add_child(rule)
	var brief: Array = sc.get("briefing", [])
	for i in 3:
		var l := UiKit.label(String(brief[i]) if i < brief.size() else "", "InkLabel", 27)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(1340, 0)
		l.visible_ratio = 0.0
		v.add_child(l)
		UiKit.expose(l, "Line%d" % (i + 1), self)
		lines.append(l)
	# seal
	var seal := TextureRect.new()
	seal.texture = UiKit.tex("seal_stamp")
	seal.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	seal.size = Vector2(120, 120)
	seal.position = Vector2(1620, 548)
	seal.rotation = deg_to_rad(5)
	seal.name = "Seal"
	add_child(seal)
	var kan := UiKit.label(String(sc.get("kanji", "")), "BrushLabel", 40 if String(sc.get("kanji", "")).length() <= 2 else 32, UiKit.WASHI)
	kan.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	kan.position = Vector2(1632, 578)
	kan.rotation = deg_to_rad(5)
	add_child(kan)
	seal.modulate.a = 0.0
	kan.modulate.a = 0.0
	# buttons
	_continue = Button.new()
	_continue.text = "Continue"
	_continue.custom_minimum_size = Vector2(300, 66)
	_continue.position = Vector2(1400, 990)
	_continue.add_theme_font_size_override("font_size", 28)
	_continue.pressed.connect(_on_continue)
	_continue.mouse_entered.connect(func(): UiKit.sfx(self, "hover"))
	add_child(_continue)
	UiKit.expose(_continue, "ContinueButton", self)
	_continue.modulate.a = 0.0
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(200, 66)
	back.position = Vector2(220, 990)
	back.pressed.connect(func():
		UiKit.sfx(self, "back")
		if g != null:
			g.goto_select())
	add_child(back)
	UiKit.expose(back, "BackButton", self)
	# animate
	strip.modulate.a = 0.0
	var ts := create_tween()
	ts.tween_property(strip, "modulate:a", 1.0, 0.6).set_delay(0.3)
	var delay := 0.9
	for l in lines:
		var tw := create_tween()
		l.modulate = Color(1, 1, 1, 0.0)
		var dur := clampf(l.text.length() * 0.028, 1.2, 3.2)
		tw.tween_property(l, "modulate:a", 1.0, 0.4).set_delay(delay)
		tw.parallel().tween_property(l, "visible_ratio", 1.0, dur).set_delay(delay).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_tweens.append(tw)
		delay += dur + 0.45
	var tw2 := create_tween().set_parallel(true)
	tw2.tween_property(seal, "modulate:a", 1.0, 0.15).set_delay(delay)
	tw2.tween_property(kan, "modulate:a", 1.0, 0.15).set_delay(delay)
	tw2.tween_property(_continue, "modulate:a", 1.0, 0.5).set_delay(delay + 0.2)
	tw2.chain().tween_callback(func(): _writing = false)
	_tweens.append(tw2)


## Finish all ink animations immediately.
func skip() -> void:
	for t in _tweens:
		if t.is_valid():
			t.custom_step(60.0)
	_writing = false


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and _writing:
		skip()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		if _writing:
			skip()
		else:
			_on_continue()
	elif event.is_action_pressed("ui_cancel"):
		var g := get_node_or_null("/root/Game")
		if g != null:
			g.goto_select()


func _on_continue() -> void:
	UiKit.sfx(self, "confirm")
	continue_pressed.emit()
	var g := get_node_or_null("/root/Game")
	if g != null:
		g.start_battle()

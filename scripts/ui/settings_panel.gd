class_name SettingsPanel
extends PanelContainer
## Lacquer settings panel: master / music / effects volume, fullscreen. Reads and writes
## Game.settings (autoload) when present; otherwise drives the audio buses directly.
## Children: MasterSlider, MusicSlider, SfxSlider, FullscreenCheck, SettingsClose.

signal closed


func _init() -> void:
	custom_minimum_size = Vector2(560, 0)


func _ready() -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var t := UiKit.label("Settings", "HeaderLabel", 34)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var k := UiKit.label("設定", "BrushLabel", 34)
	head.add_child(k)
	var div := TextureRect.new()
	div.texture = UiKit.tex("gold_divider")
	div.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	div.custom_minimum_size = Vector2(0, 18)
	v.add_child(div)
	var g := _game()
	var s: Dictionary = g.settings if g != null else {"master": 0.9, "music": 0.8, "sfx": 0.9, "fullscreen": false}
	_slider(v, "MasterSlider", "Master volume", "master", float(s["master"]))
	_slider(v, "MusicSlider", "Music", "music", float(s["music"]))
	_slider(v, "SfxSlider", "Battle & effects", "sfx", float(s["sfx"]))
	var fs := CheckBox.new()
	fs.name = "FullscreenCheck"
	fs.text = "  Fullscreen"
	fs.button_pressed = bool(s["fullscreen"])
	fs.add_theme_font_size_override("font_size", 24)
	fs.toggled.connect(func(on: bool):
		UiKit.sfx(self, "click")
		_apply("fullscreen", on))
	v.add_child(fs)
	var close := Button.new()
	close.name = "SettingsClose"
	close.text = "Done"
	close.custom_minimum_size = Vector2(180, 54)
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	close.pressed.connect(func():
		UiKit.sfx(self, "back")
		close_panel())
	v.add_child(close)


func _slider(parent: Control, node_name: String, caption: String, key: String, value: float) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	parent.add_child(row)
	var l := UiKit.label(caption, "", 22)
	l.custom_minimum_size = Vector2(200, 0)
	row.add_child(l)
	var sl := HSlider.new()
	sl.name = node_name
	sl.min_value = 0.0
	sl.max_value = 1.0
	sl.step = 0.01
	sl.value = value
	sl.custom_minimum_size = Vector2(250, 32)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var pct := UiKit.label("%d%%" % int(value * 100), "", 20, UiKit.GOLD_HI)
	pct.custom_minimum_size = Vector2(56, 0)
	pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sl.value_changed.connect(func(x: float):
		pct.text = "%d%%" % int(x * 100)
		_apply(key, x))
	sl.drag_ended.connect(func(_c): UiKit.sfx(self, "click"))
	row.add_child(sl)
	row.add_child(pct)


func _game() -> Node:
	return get_node_or_null("/root/Game") if is_inside_tree() else null


func _apply(key: String, value) -> void:
	var g := _game()
	if g != null:
		g.set_setting(key, value)


func open() -> void:
	visible = true
	UiKit.sfx(self, "open")
	modulate.a = 0.0
	pivot_offset = size * 0.5
	scale = Vector2(0.96, 0.96)
	var t := create_tween().set_parallel(true)
	t.tween_property(self, "modulate:a", 1.0, 0.2)
	t.tween_property(self, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func close_panel() -> void:
	var g := _game()
	if g != null:
		g.save_settings()
	var t := create_tween()
	t.tween_property(self, "modulate:a", 0.0, 0.15)
	t.tween_callback(func():
		visible = false
		closed.emit())


func close() -> void:
	close_panel()

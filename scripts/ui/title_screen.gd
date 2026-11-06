extends Control
## Title / main menu: key art with a slow Ken Burns drift, mist and embers, the KASSEN 合戦 logo
## and the menu (Battles, Settings, Quit). Settings opens an in-place lacquer panel.
##
## Stable nodes (unique names): %BattlesButton %SettingsButton %QuitButton %SettingsPanel
##   %MasterSlider %MusicSlider %SfxSlider %FullscreenCheck %SettingsClose

signal battles_pressed
signal quit_pressed

var art: TextureRect
var _settings: Control
var _logo: Control
var _menu: VBoxContainer
var _kb_tween: Tween


func _ready() -> void:
	theme = UiKit.theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_background()
	_build_logo()
	_build_menu()
	_build_settings()
	_intro()
	UiKit.phase(self, "menu")


# ------------------------------------------------------------------------- background
func _build_background() -> void:
	var bg := ColorRect.new()
	bg.color = UiKit.LACQUER
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	art = TextureRect.new()
	art.name = "KeyArt"
	art.texture = UiKit.art("title")
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(art)
	resized.connect(_ken_burns)
	_ken_burns()
	# mist + embers
	add_child(TitleFx.mist_layer(size if size.x > 0 else Vector2(1920, 1080)))
	add_child(TitleFx.embers(size if size.x > 0 else Vector2(1920, 1080)))
	# legibility gradients: left-side dusk for the menu, bottom vignette
	var g := TitleFx.gradient_rect(Color(0.03, 0.02, 0.015, 0.88), Color(0.03, 0.02, 0.015, 0.0), true, 0.62)
	add_child(g)
	var g2 := TitleFx.gradient_rect(Color(0, 0, 0, 0.0), Color(0.02, 0.01, 0.01, 0.75), false, 1.0)
	add_child(g2)


## Slow pan + zoom that ping-pongs forever (Ken Burns).
func _ken_burns() -> void:
	var vs := size if size.x > 0 else Vector2(1920, 1080)
	art.size = vs * 1.16
	art.pivot_offset = art.size * 0.5
	if _kb_tween != null:
		_kb_tween.kill()
	art.position = Vector2(-vs.x * 0.02, -vs.y * 0.08)
	art.scale = Vector2.ONE
	_kb_tween = create_tween().set_loops()
	_kb_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_kb_tween.tween_property(art, "position", Vector2(-vs.x * 0.14, -vs.y * 0.06), 34.0)
	_kb_tween.parallel().tween_property(art, "scale", Vector2(1.08, 1.08), 34.0)
	_kb_tween.tween_property(art, "position", Vector2(-vs.x * 0.02, -vs.y * 0.08), 34.0)
	_kb_tween.parallel().tween_property(art, "scale", Vector2.ONE, 34.0)


# ------------------------------------------------------------------------------- logo
func _build_logo() -> void:
	_logo = Control.new()
	_logo.name = "Logo"
	_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_logo.position = Vector2(140, 150)
	_logo.size = Vector2(900, 330)
	add_child(_logo)
	var shadow := TextureRect.new()
	shadow.texture = UiKit.tex("glow")
	shadow.position = Vector2(818, 0)
	shadow.size = Vector2(212, 212)
	shadow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shadow.modulate = Color(0, 0, 0, 0.75)
	_logo.add_child(shadow)
	var seal := TextureRect.new()
	seal.texture = UiKit.tex("seal_stamp")
	seal.self_modulate = Color(0.85, 0.85, 0.85)
	seal.position = Vector2(858, 40)
	seal.size = Vector2(132, 132)
	seal.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	seal.rotation = deg_to_rad(-4)
	seal.name = "Seal"
	_logo.add_child(seal)
	var kan := UiKit.label("合戦", "BrushLabel", 60, UiKit.WASHI)
	kan.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.0))
	kan.position = Vector2(868, 50)
	kan.rotation = deg_to_rad(-4)
	kan.name = "Kanji"
	_logo.add_child(kan)
	var title := UiKit.label("KASSEN", "TitleLabel", 156, UiKit.GOLD)
	title.add_theme_constant_override("outline_size", 10)
	title.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.02, 0.85))
	title.add_theme_constant_override("shadow_offset_y", 8)
	title.add_theme_constant_override("shadow_outline_size", 18)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	title.position = Vector2(0, 0)
	title.name = "Title"
	_logo.add_child(title)
	var div := TextureRect.new()
	div.texture = UiKit.tex("gold_divider")
	div.position = Vector2(-40, 196)
	div.size = Vector2(760, 24)
	div.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.add_child(div)
	var sub := UiKit.label("FIELDS OF THE WARRING STATES", "HeaderLabel", 30, UiKit.WASHI)
	sub.position = Vector2(4, 228)
	sub.name = "Subtitle"
	_logo.add_child(sub)
	_spacing(sub, 7)


func _spacing(l: Label, px: int) -> void:
	var fv := FontVariation.new()
	fv.base_font = UiKit.font_head()
	fv.spacing_glyph = px
	l.add_theme_font_override("font", fv)


# ------------------------------------------------------------------------------- menu
func _build_menu() -> void:
	_menu = VBoxContainer.new()
	_menu.name = "Menu"
	_menu.position = Vector2(176, 560)
	_menu.size = Vector2(520, 300)
	_menu.add_theme_constant_override("separation", 14)
	add_child(_menu)
	var items := [["BattlesButton", "Battles", "戦", _on_battles], ["SettingsButton", "Settings", "設定", _on_settings],
		["QuitButton", "Quit", "退", _on_quit]]
	for it in items:
		var b := BrushButton.new()
		b.text = it[1]
		b.sub_text = it[2]
		b.custom_minimum_size = Vector2(420, 64)
		b.add_theme_font_size_override("font_size", 46)
		_menu.add_child(b)
		UiKit.expose(b, it[0], self)
		b.pressed.connect(it[3])
	var ver := UiKit.label("Hino Masatora's first command  ·  1574", "", 18, Color(UiKit.WASHI, 0.55))
	ver.position = Vector2(40, 1030)
	ver.name = "Footer"
	add_child(ver)


func _intro() -> void:
	var t := create_tween()
	_logo.modulate.a = 0.0
	_logo.scale = Vector2(1.04, 1.04)
	t.tween_property(_logo, "modulate:a", 1.0, 1.6).set_delay(0.2).set_trans(Tween.TRANS_SINE)
	t.parallel().tween_property(_logo, "scale", Vector2.ONE, 2.2).set_delay(0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var seal := _logo.get_node("Seal") as Control
	var kan := _logo.get_node("Kanji") as Control
	for n in [seal, kan]:
		n.modulate.a = 0.0
		n.scale = Vector2(1.6, 1.6)
		n.pivot_offset = Vector2(66, 66)
	var t2 := create_tween().set_parallel(true)
	for n in [seal, kan]:
		t2.tween_property(n, "modulate:a", 1.0, 0.18).set_delay(1.25)
		t2.tween_property(n, "scale", Vector2.ONE, 0.22).set_delay(1.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var k := 0
	for b in _menu.get_children():
		b.modulate.a = 0.0
		var t3 := create_tween()
		t3.tween_property(b, "modulate:a", 1.0, 0.5).set_delay(1.4 + 0.12 * k)
		k += 1


# --------------------------------------------------------------------------- settings
func _build_settings() -> void:
	_settings = SettingsPanel.new()
	add_child(_settings)
	UiKit.expose(_settings, "SettingsPanel", self)
	_settings.position = Vector2(760, 330)
	_settings.visible = false
	for n in ["MasterSlider", "MusicSlider", "SfxSlider", "FullscreenCheck", "SettingsClose"]:
		var c := _settings.find_child(n, true, false)
		if c != null:
			UiKit.expose(c, n, self)


func _on_battles() -> void:
	battles_pressed.emit()
	var g := get_node_or_null("/root/Game")
	if g != null:
		g.goto_select()


func _on_settings() -> void:
	if _settings.visible:
		_settings.call("close")
	else:
		_settings.call("open")


func _on_quit() -> void:
	quit_pressed.emit()
	get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _settings.visible:
		_settings.call("close")
		get_viewport().set_input_as_handled()

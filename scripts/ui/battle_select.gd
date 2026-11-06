extends Control
## Battle select: two scenario cards, a difficulty selector and Begin / Back.
##
## Stable nodes: %CardKurogawa %CardTenmoku %DifficultyEasy %DifficultyNormal %DifficultyHard
##               %DifficultyDesc %BeginButton %BackButton

signal begin_pressed(scenario_key: String, difficulty: int)
signal back_pressed

var cards := {}
var diff_buttons: Array[Button] = []
var selected_key := "kurogawa"
var difficulty := 1
var _desc: Label
var _bg: TextureRect


func _ready() -> void:
	theme = UiKit.theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var g := _game()
	var scen: Dictionary = g.SCENARIOS if g != null else {}
	var order: Array = g.ORDER if g != null else []
	if g != null:
		selected_key = g.scenario_key
		difficulty = g.difficulty
	_build_bg()
	# header
	var head := UiKit.label("Choose your battle", "TitleLabel", 58)
	head.position = Vector2(120, 70)
	head.name = "Header"
	add_child(head)
	var hk := UiKit.label("合戦の地", "BrushLabel", 46, Color(UiKit.VERMILION, 0.95))
	hk.position = Vector2(120, 140)
	add_child(hk)
	var div := TextureRect.new()
	div.texture = UiKit.tex("gold_divider")
	div.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	div.position = Vector2(80, 196)
	div.size = Vector2(1760, 24)
	add_child(div)
	# cards
	var row := HBoxContainer.new()
	row.name = "Cards"
	row.add_theme_constant_override("separation", 60)
	row.position = Vector2(120, 238)
	add_child(row)
	var group := ButtonGroup.new()
	for key in order:
		var c := ScenarioCard.new()
		c.setup(scen[key], _army_sizes(String(scen[key].get("map", key))))
		c.button_group = group
		row.add_child(c)
		UiKit.expose(c, "Card" + String(key).capitalize().replace(" ", ""), self)
		c.button_pressed = key == selected_key
		c.pressed.connect(_on_card.bind(String(key)))
		cards[key] = c
	# difficulty + actions column
	var col := VBoxContainer.new()
	col.name = "SideColumn"
	col.position = Vector2(1420, 238)
	col.custom_minimum_size = Vector2(400, 640)
	col.add_theme_constant_override("separation", 14)
	add_child(col)
	var panel := PanelContainer.new()
	col.add_child(panel)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 10)
	panel.add_child(pv)
	pv.add_child(UiKit.label("Difficulty", "HeaderLabel", 28))
	var dg := ButtonGroup.new()
	var diffs: Array = g.DIFFICULTIES if g != null else [{"name": "Gentle", "kanji": "易", "desc": ""}, {"name": "Bushidō", "kanji": "武", "desc": ""}, {"name": "Shura", "kanji": "修羅", "desc": ""}]
	var names := ["DifficultyEasy", "DifficultyNormal", "DifficultyHard"]
	for i in diffs.size():
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = dg
		b.text = "%s   %s" % [diffs[i]["name"], diffs[i]["kanji"]]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(340, 56)
		b.theme_type_variation = &"ToggleButton"
		b.button_pressed = i == difficulty
		b.pressed.connect(_on_diff.bind(i))
		b.mouse_entered.connect(func(): UiKit.sfx(self, "hover"))
		pv.add_child(b)
		UiKit.expose(b, names[i], self)
		diff_buttons.append(b)
	_desc = UiKit.label("", "", 20, Color(UiKit.WASHI, 0.8))
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.custom_minimum_size = Vector2(340, 84)
	pv.add_child(_desc)
	UiKit.expose(_desc, "DifficultyDesc", self)
	_diffs = diffs
	_update_desc()
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(spacer)
	var begin := Button.new()
	begin.text = "Begin  出陣"
	begin.custom_minimum_size = Vector2(400, 84)
	begin.add_theme_font_size_override("font_size", 34)
	begin.add_theme_stylebox_override("normal", UiKit.stylebox("frame_lacquer_hover"))
	begin.pressed.connect(_on_begin)
	begin.mouse_entered.connect(func(): UiKit.sfx(self, "hover"))
	col.add_child(begin)
	UiKit.expose(begin, "BeginButton", self)
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(400, 58)
	back.pressed.connect(_on_back)
	back.mouse_entered.connect(func(): UiKit.sfx(self, "hover"))
	col.add_child(back)
	UiKit.expose(back, "BackButton", self)
	# entrance
	var k := 0
	for c in row.get_children():
		c.modulate.a = 0.0
		create_tween().tween_property(c, "modulate:a", 1.0, 0.5).set_delay(0.1 + 0.12 * k)
		k += 1
	col.modulate.a = 0.0
	create_tween().tween_property(col, "modulate:a", 1.0, 0.5).set_delay(0.4)


var _diffs: Array = []


func _build_bg() -> void:
	var bg := ColorRect.new()
	bg.color = UiKit.LACQUER
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_bg = TextureRect.new()
	_bg.name = "Backdrop"
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.modulate = Color(0.32, 0.28, 0.26)
	add_child(_bg)
	_set_backdrop()
	TitleFx.ken_burns(self, _bg, Vector2(1920, 1080), 40.0)
	var lac := TextureRect.new()
	lac.texture = UiKit.res("res://assets/ui/lacquer.png") as Texture2D
	lac.stretch_mode = TextureRect.STRETCH_TILE
	lac.set_anchors_preset(Control.PRESET_FULL_RECT)
	lac.modulate = Color(1, 1, 1, 0.45)
	lac.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lac)
	add_child(TitleFx.mist_layer(Vector2(1920, 1080), 10, Color(0.9, 0.85, 0.8, 0.07)))
	add_child(TitleFx.embers(Vector2(1920, 1080), 24))


func _set_backdrop() -> void:
	var g := _game()
	var key := selected_key
	var art := "kurogawa"
	if g != null and g.SCENARIOS.has(key):
		art = String(g.SCENARIOS[key]["art"])
	_bg.texture = UiKit.art(art)


func _army_sizes(map_name: String) -> Array:
	var path := "res://scripts/world/maps/%s.gd" % map_name
	var men := [0, 0]
	if ResourceLoader.exists(path):
		var m = load(path).new()
		var armies = m.get("armies")
		if armies is Array and armies.size() == 2:
			for t in 2:
				for e in armies[t]:
					men[t] += int(UnitTypes.get_stats(UnitTypes.KEYS.find(String(e["type"])))["men"])
	for t in 2:
		if men[t] == 0:
			for k in UnitTypes.STANDARD_ARMY:
				men[t] += int(UnitTypes.STATS[k]["men"])
	return men


func _on_card(key: String) -> void:
	UiKit.sfx(self, "select")
	selected_key = key
	var c: ScenarioCard = cards[key]
	c.button_pressed = true
	_set_backdrop()


func _on_diff(i: int) -> void:
	UiKit.sfx(self, "select")
	difficulty = i
	_update_desc()


func _update_desc() -> void:
	if _desc != null and difficulty < _diffs.size():
		_desc.text = String(_diffs[difficulty].get("desc", ""))


func _on_begin() -> void:
	UiKit.sfx(self, "confirm")
	begin_pressed.emit(selected_key, difficulty)
	var g := _game()
	if g != null:
		g.choose(selected_key, difficulty)
		g.goto_briefing()


func _on_back() -> void:
	UiKit.sfx(self, "back")
	back_pressed.emit()
	var g := _game()
	if g != null:
		g.goto_title()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_back()


func _game() -> Node:
	return get_node_or_null("/root/Game")

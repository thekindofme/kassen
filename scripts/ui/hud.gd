class_name Hud
extends CanvasLayer
## KASSEN battle HUD.
##
##   Hud.bind(sim, commander, camera, map := null)   wire to a battle (auto-called when the Hud is
##                                                    a child of a node exposing sim/commander/camera)
##   Hud.begin_battle()          end deployment (also the %BeginBattleButton)
##   Hud.toast(text, kind)       kind: "good" | "bad" | "info"
##   Hud.collect_result(winner) -> Dictionary        data for Results.show_result()
##   signals: battle_begun, battle_finished(winner_team), toast_shown(text)
##
## Stable nodes (unique names, via get_node("%Name") on the Hud's root or find_child):
##   %CardTray (UnitCard children named Card_<regiment id>), %Minimap, %BattleTimer,
##   %SpeedPause %Speed1 %Speed2 %Speed3, %PowerBar, %OrdersPanel, %OrderHalt %OrderRun
##   %OrderFire %OrderWithdraw, %DeployBanner, %BeginBattleButton, %Toasts

signal battle_begun
signal battle_finished(winner_team: int)
signal toast_shown(text: String)

const SPEEDS := [1.0, 2.0, 3.0]

var sim: BattleSim
var commander: Commander
var camera: Camera2D
var map: MapDef
var deploying := false
var cards: Array[UnitCard] = []
var kills := {}               # regiment id -> kills (fallback tracker when Regiment has no `kills`)
var _kr_last := {}
var root: Control
var tray: HBoxContainer
var minimap: Minimap
var timer_label: Label
var speed_buttons: Array[Button] = []
var power_bar: Control
var orders_panel: PanelContainer
var order_buttons := {}
var deploy_banner: PanelContainer
var toasts: VBoxContainer
var _men_labels: Array[Label] = []
var _ended := false
var _bound := false


func _ready() -> void:
	layer = 10
	name = "Hud"
	root = Control.new()
	root.name = "Root"
	root.theme = UiKit.theme()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_top_bar()
	_build_minimap()
	_build_tray()
	_build_orders()
	_build_deploy_banner()
	_build_toasts()
	_auto_bind.call_deferred()


func _ui(n: Node, node_name: String) -> Node:
	return UiKit.expose(n, node_name, root)


func _auto_bind() -> void:
	if _bound:
		return
	var p := get_parent()
	while p != null:
		var s = p.get("sim")
		if s is BattleSim:
			bind(s, p.get("commander") as Commander, p.get("camera") as Camera2D, p.get("map") as MapDef)
			return
		p = p.get_parent()
	var s2 := get_tree().get_first_node_in_group("sim") as BattleSim
	if s2 != null:
		bind(s2, null, get_viewport().get_camera_2d())


# =====================================================================================
#  Bind
# =====================================================================================

func bind(p_sim: BattleSim, p_commander: Commander = null, p_camera: Camera2D = null, p_map: MapDef = null) -> void:
	sim = p_sim
	commander = p_commander
	camera = p_camera
	map = p_map
	if map == null and sim != null and sim.terrain != null:
		map = sim.terrain.get("map") as MapDef
	_bound = true
	# the engine's debug overlay is replaced by this HUD
	var dbg := get_parent().get_node_or_null("DebugHud") if get_parent() != null else null
	if dbg != null and not Game_user_arg("debug_hud"):
		dbg.visible = false
	for c in tray.get_children():
		c.queue_free()
	cards.clear()
	kills.clear()
	_kr_last.clear()
	for r in sim.regiments_of(0):
		var card := UnitCard.new()
		card.setup(r)
		card.card_clicked.connect(_on_card_clicked)
		card.card_double_clicked.connect(_on_card_double)
		tray.add_child(card)
		_ui(card, "Card_%d" % r.id)
		cards.append(card)
	for r in sim.regiments:
		kills[r.id] = 0
		_kr_last[r.id] = r.kills_recent
	minimap.bind(sim, camera, map)
	if commander != null:
		if not commander.selection_changed.is_connected(_on_selection_changed):
			commander.selection_changed.connect(_on_selection_changed)
		_on_selection_changed(commander.selected)
	var hooks := {"regiment_routed": _on_routed, "regiment_rallied": _on_rallied, "general_killed": _on_general_killed,
		"battle_ended": _on_battle_ended}
	for sig in hooks:
		if sim.has_signal(sig) and not sim.is_connected(sig, hooks[sig]):
			sim.connect(sig, hooks[sig])
	var g := get_node_or_null("/root/Game")
	if g != null:
		g.apply_settings()
	# deployment phase: follow sim.deploying when the sim has one (engine-driven deployment);
	# otherwise fall back to holding the sim paused until Begin Battle.
	if _sim_has_deploy():
		if bool(sim.get("deploying")):
			_enter_deploy()
		else:
			deploy_banner.visible = false
	else:
		var skip := Game_user_arg("shot") or Game_user_arg("demo") or Game_user_arg("skip_deploy")
		if sim.time <= 0.0 and not skip:
			_enter_deploy()
		else:
			deploy_banner.visible = false
	_intro_anim()


static func Game_user_arg(k: String) -> bool:
	for a in OS.get_cmdline_user_args():
		if a == "--" + k or a.begins_with("--" + k + "="):
			return true
	return false


func _sim_has_deploy() -> bool:
	return sim != null and sim.get("deploying") != null


func _enter_deploy() -> void:
	deploying = true
	if not _sim_has_deploy():
		sim.paused = true
	deploy_banner.visible = true
	UiKit.fade_in(deploy_banner, 0.6, 0.4)
	UiKit.phase(self, "deploy")


func begin_battle() -> void:
	if not deploying:
		return
	deploying = false
	if sim.has_method("begin_battle"):
		sim.call("begin_battle")
	if not _sim_has_deploy():
		sim.paused = false
	UiKit.sfx(self, "confirm")
	UiKit.phase(self, "battle")
	var t := create_tween()
	t.tween_property(deploy_banner, "modulate:a", 0.0, 0.35)
	t.tween_callback(func(): deploy_banner.visible = false)
	_big_banner("Battle!", "開戦", UiKit.VERMILION)
	battle_begun.emit()


# =====================================================================================
#  Per-frame
# =====================================================================================

func _process(_delta: float) -> void:
	if sim == null:
		return
	_track_kills()
	if _sim_has_deploy():
		var d := bool(sim.get("deploying"))
		if d and not deploying:
			_enter_deploy()               # (re)entered deployment
		elif deploying and not d:
			begin_battle()                # ended elsewhere (Enter key, tests, AI demo)
	elif deploying and not sim.paused:
		begin_battle()                    # unpaused by hotkey during deployment
	timer_label.text = UiKit.fmt_time(sim.time)
	# speed buttons reflect the sim (hotkeys can change it too)
	speed_buttons[0].set_pressed_no_signal(sim.paused)
	for i in SPEEDS.size():
		speed_buttons[i + 1].set_pressed_no_signal(not sim.paused and is_equal_approx(sim.time_scale, SPEEDS[i]))
	for b in speed_buttons:
		b.disabled = deploying
	for t in 2:
		_men_labels[t].text = str(sim.men_alive(t, false))
	power_bar.queue_redraw()
	# hotkey badges
	if commander != null:
		var hk := {}
		for k in commander.groups:
			for r in commander.groups[k]:
				if not hk.has(r):
					hk[r] = int(k)
		for c in cards:
			c.hotkey = hk.get(c.reg, -1)
	_update_order_states()


func _track_kills() -> void:
	for r in sim.regiments:
		var k = r.get("kills")
		if k != null:
			kills[r.id] = int(k)
			continue
		var last: float = _kr_last.get(r.id, 0.0)
		if r.kills_recent > last + 0.5:
			kills[r.id] = int(kills.get(r.id, 0)) + int(round(r.kills_recent - last))
		_kr_last[r.id] = r.kills_recent


func strength(team: int) -> float:
	var s := 0.0
	for r in sim.regiments_of(team):
		if r.is_out():
			continue
		var w := 0.35 if r.is_routing() else 1.0
		s += r.alive * w * (1.6 if r.type_key == "samurai" or r.is_mounted() else 1.0)
	return s


# =====================================================================================
#  Builders
# =====================================================================================

func _build_top_bar() -> void:
	var bar := PanelContainer.new()
	bar.name = "TopBar"
	bar.set_anchors_preset(Control.PRESET_CENTER_TOP)
	bar.custom_minimum_size = Vector2(820, 0)
	_place(bar, Vector2(-410, 10))
	bar.add_theme_stylebox_override("panel", _panel_sb(16, 8))
	root.add_child(bar)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	bar.add_child(v)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(h)
	for t in 2:
		if t == 1:
			_build_clock(h)
		var side := HBoxContainer.new()
		side.add_theme_constant_override("separation", 8)
		side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		side.alignment = BoxContainer.ALIGNMENT_BEGIN if t == 0 else BoxContainer.ALIGNMENT_END
		h.add_child(side)
		var mon := TextureRect.new()
		mon.texture = UiKit.mon(t)
		mon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		mon.custom_minimum_size = Vector2(38, 38)
		var nm := UiKit.label(UiKit.TEAM_NAMES[t], "HeaderLabel", 22, UiKit.team_color(t, true).lightened(0.3))
		var men := UiKit.label("0", "", 22, UiKit.WASHI)
		men.add_theme_font_override("font", UiKit.font_bold())
		_men_labels.append(men)
		var parts: Array = [mon, nm, men] if t == 0 else [men, nm, mon]
		for p in parts:
			side.add_child(p)
	power_bar = _PowerBar.new()
	power_bar.hud = self
	power_bar.custom_minimum_size = Vector2(0, 14)
	v.add_child(power_bar)
	_ui(power_bar, "PowerBar")


func _build_clock(h: HBoxContainer) -> void:
	var mid := HBoxContainer.new()
	mid.add_theme_constant_override("separation", 4)
	h.add_child(mid)
	timer_label = UiKit.label("00:00", "TitleLabel", 30, UiKit.GOLD_HI)
	timer_label.custom_minimum_size = Vector2(108, 0)
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mid.add_child(timer_label)
	_ui(timer_label, "BattleTimer")
	var defs := [["SpeedPause", "", "pause", "Pause (Space)"], ["Speed1", "×1", "", "Normal speed"],
		["Speed2", "×2", "", "Double speed"], ["Speed3", "×3", "", "Triple speed"]]
	for i in defs.size():
		var b := Button.new()
		b.toggle_mode = true
		b.text = defs[i][1]
		if defs[i][2] != "":
			b.icon = UiKit.tex("icon_" + defs[i][2])
			b.expand_icon = true
		b.tooltip_text = defs[i][3]
		b.custom_minimum_size = Vector2(46, 40)
		b.focus_mode = Control.FOCUS_NONE
		b.theme_type_variation = &"ToggleButton"
		b.add_theme_font_size_override("font_size", 18)
		for s in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			b.add_theme_stylebox_override(s, _small_sb(s))
		b.pressed.connect(_on_speed.bind(i))
		mid.add_child(b)
		_ui(b, defs[i][0])
		speed_buttons.append(b)


func _small_sb(state: String) -> StyleBox:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.07, 0.05, 0.95)
	sb.border_color = UiKit.GOLD_LO
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	match state:
		"hover":
			sb.border_color = UiKit.GOLD_HI
			sb.shadow_color = Color(UiKit.GOLD_HI, 0.25)
			sb.shadow_size = 5
		"pressed", "hover_pressed":
			sb.bg_color = Color(0.45, 0.09, 0.08, 1)
			sb.border_color = UiKit.GOLD_HI
			sb.shadow_color = Color(UiKit.GOLD_HI, 0.3)
			sb.shadow_size = 6
		"disabled":
			sb.bg_color = Color(0.06, 0.05, 0.04, 0.7)
			sb.border_color = Color(UiKit.GOLD_LO, 0.4)
	return sb


func _panel_sb(h: float, v: float) -> StyleBoxTexture:
	var sb := UiKit.stylebox("frame_lacquer", 26.0).duplicate() as StyleBoxTexture
	sb.content_margin_left = h
	sb.content_margin_right = h
	sb.content_margin_top = v
	sb.content_margin_bottom = v
	return sb


func _build_minimap() -> void:
	var p := PanelContainer.new()
	p.name = "MinimapFrame"
	p.add_theme_stylebox_override("panel", _panel_sb(12, 12))
	p.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	p.custom_minimum_size = Vector2(324, 224)
	_place(p, Vector2(12, -232))
	root.add_child(p)
	minimap = Minimap.new()
	minimap.custom_minimum_size = Vector2(300, 200)
	p.add_child(minimap)
	_ui(minimap, "Minimap")


func _build_tray() -> void:
	tray = HBoxContainer.new()
	tray.add_theme_constant_override("separation", 5)
	tray.alignment = BoxContainer.ALIGNMENT_CENTER
	tray.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	tray.custom_minimum_size = Vector2(1260, UnitCard.CARD_SIZE.y)
	_place(tray, Vector2(-592, -UnitCard.CARD_SIZE.y - 10))
	tray.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(tray)
	_ui(tray, "CardTray")


func _build_orders() -> void:
	orders_panel = PanelContainer.new()
	orders_panel.add_theme_stylebox_override("panel", _panel_sb(14, 12))
	orders_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	orders_panel.custom_minimum_size = Vector2(250, 180)
	_place(orders_panel, Vector2(-262, -194))
	root.add_child(orders_panel)
	_ui(orders_panel, "OrdersPanel")
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	orders_panel.add_child(v)
	v.add_child(UiKit.label("Orders  采配", "HeaderLabel", 18))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	v.add_child(grid)
	var defs := [["OrderHalt", "Halt", "halt", false, "Halt and reform (H)"], ["OrderRun", "Run", "run", true, "Run / walk (R)"],
		["OrderFire", "Fire", "fire", true, "Fire at will (F)"], ["OrderWithdraw", "Withdraw", "withdraw", false, "Withdraw from the field (Backspace)"]]
	for d in defs:
		var b := Button.new()
		b.text = d[1]
		b.icon = UiKit.tex("icon_" + d[2])
		b.expand_icon = false
		b.add_theme_constant_override("icon_max_width", 22)
		b.toggle_mode = d[3]
		b.tooltip_text = d[4]
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(110, 44)
		b.add_theme_font_size_override("font_size", 17)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		for s in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			b.add_theme_stylebox_override(s, _small_sb(s))
		b.pressed.connect(_on_order.bind(String(d[2])))
		grid.add_child(b)
		_ui(b, d[0])
		order_buttons[d[2]] = b
	orders_panel.modulate.a = 0.0
	orders_panel.visible = false


func _build_deploy_banner() -> void:
	deploy_banner = PanelContainer.new()
	deploy_banner.add_theme_stylebox_override("panel", _panel_sb(30, 16))
	deploy_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	deploy_banner.custom_minimum_size = Vector2(760, 0)
	_place(deploy_banner, Vector2(-380, 112))
	root.add_child(deploy_banner)
	_ui(deploy_banner, "DeployBanner")
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 22)
	deploy_banner.add_child(h)
	var seal := _SealLabel.new()
	seal.text = "布陣"
	seal.custom_minimum_size = Vector2(84, 84)
	h.add_child(seal)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(v)
	v.add_child(UiKit.label("Deployment", "TitleLabel", 34))
	var sub := UiKit.label("Drag your regiments into position within the crimson zone; right-drag sets frontage and facing. Enter begins the battle.", "", 18, Color(UiKit.WASHI, 0.85))
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.custom_minimum_size = Vector2(380, 0)
	v.add_child(sub)
	var b := Button.new()
	b.text = "Begin Battle"
	b.custom_minimum_size = Vector2(200, 64)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.add_theme_stylebox_override("normal", UiKit.stylebox("frame_lacquer_hover"))
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(begin_battle)
	h.add_child(b)
	_ui(b, "BeginBattleButton")
	deploy_banner.visible = false


func _build_toasts() -> void:
	toasts = VBoxContainer.new()
	toasts.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toasts.custom_minimum_size = Vector2(660, 0)
	_place(toasts, Vector2(-330, 240))
	toasts.add_theme_constant_override("separation", 8)
	toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(toasts)
	_ui(toasts, "Toasts")


## Offsets relative to the control's anchor point (set the anchors preset first).
func _place(c: Control, off: Vector2) -> void:
	var sz := c.custom_minimum_size
	c.offset_left = off.x
	c.offset_top = off.y
	c.offset_right = off.x + sz.x
	c.offset_bottom = off.y + sz.y
	if c.anchor_top >= 1.0:
		c.grow_vertical = Control.GROW_DIRECTION_BEGIN
	if c.anchor_left >= 1.0:
		c.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	elif c.anchor_left == 0.5:
		c.grow_horizontal = Control.GROW_DIRECTION_BOTH


# =====================================================================================
#  Interaction
# =====================================================================================

func _on_card_clicked(card: UnitCard, shift: bool) -> void:
	if commander == null or card.reg == null or card.reg.is_out():
		UiKit.sfx(self, "error")
		return
	UiKit.sfx(self, "select")
	if shift and commander.selected.has(card.reg):
		var rest: Array = []
		for r in commander.selected:
			if r != card.reg:
				rest.append(r)
		commander.select_regiments(rest, false)
	else:
		commander.select_regiments([card.reg], shift)


func _on_card_double(card: UnitCard) -> void:
	if card.reg == null or card.reg.is_out():
		return
	if commander != null:
		commander.select_regiments([card.reg], false)
	if camera != null and camera.has_method("focus_on"):
		camera.call("focus_on", card.reg.mean_pos)
	UiKit.sfx(self, "select")


func _on_selection_changed(sel: Array) -> void:
	for c in cards:
		c.selected = sel.has(c.reg)
	var show := not sel.is_empty()
	if show == orders_panel.visible and (not show or orders_panel.modulate.a > 0.9):
		return
	var t := create_tween()
	if show:
		orders_panel.visible = true
		t.tween_property(orders_panel, "modulate:a", 1.0, 0.18)
	else:
		t.tween_property(orders_panel, "modulate:a", 0.0, 0.18)
		t.tween_callback(func(): orders_panel.visible = not commander.selected.is_empty() if commander != null else false)


func _update_order_states() -> void:
	if commander == null or not orders_panel.visible:
		return
	var sel := commander.selected
	var all_run := not sel.is_empty()
	var all_fire := true
	var any_ranged := false
	for r in sel:
		all_run = all_run and r.running
		if r.is_ranged():
			any_ranged = true
			all_fire = all_fire and r.fire_at_will
	order_buttons["run"].set_pressed_no_signal(all_run)
	order_buttons["fire"].disabled = not any_ranged
	order_buttons["fire"].set_pressed_no_signal(any_ranged and all_fire)


func _on_order(kind: String) -> void:
	if commander == null or commander.selected.is_empty():
		return
	var sel := commander.selected.duplicate()
	match kind:
		"halt":
			for r in sel:
				r.order_halt()
		"run":
			var all_run := true
			for r in sel:
				all_run = all_run and r.running
			for r in sel:
				r.set_running(not all_run)
		"fire":
			var all_on := true
			for r in sel:
				if r.is_ranged():
					all_on = all_on and r.fire_at_will
			for r in sel:
				if r.is_ranged():
					r.set_fire_at_will(not all_on)
			kind = "fire_at_will"
		"withdraw":
			for r in sel:
				r.order_withdraw()
	commander.order_issued.emit(kind)
	UiKit.sfx(self, "order")


func _on_speed(i: int) -> void:
	if sim == null or deploying:
		return
	UiKit.sfx(self, "click")
	if i == 0:
		sim.paused = not sim.paused
	else:
		sim.paused = false
		sim.time_scale = SPEEDS[i - 1]


# =====================================================================================
#  Events → toasts
# =====================================================================================

func _reg_label(r: Regiment) -> String:
	return r.display_name


func _on_routed(r: Regiment) -> void:
	if r.team == 0:
		toast("Your %s are routing!" % _reg_label(r), "bad")
	else:
		toast("Mizuno %s are routing!" % _reg_label(r), "good")


func _on_rallied(r: Regiment) -> void:
	if r.team == 0:
		toast("Your %s have rallied." % _reg_label(r), "info")
	else:
		toast("Mizuno %s have rallied." % _reg_label(r), "info")


func _on_general_killed(team: int) -> void:
	if team == 0:
		toast("Your general has fallen!", "bad")
	else:
		toast("The Mizuno general has fallen!", "good")


func _on_battle_ended(winner: int) -> void:
	if _ended:
		return
	_ended = true
	var win := winner == 0
	_big_banner("Victory" if win else "Defeat", "勝利" if win else "敗北", UiKit.GOLD if win else UiKit.VERMILION)
	battle_finished.emit(winner)
	if get_node_or_null("/root/Game") == null:
		# standalone battle (no Game autoload): open the scroll ourselves
		await get_tree().create_timer(2.6).timeout
		var ps := load("res://scenes/ui/results.tscn") as PackedScene
		if ps != null:
			var res := ps.instantiate()
			get_parent().add_child(res)
			res.call("show_result", collect_result(winner))


func toast(text: String, kind := "info") -> void:
	var t := _Toast.new()
	t.text = text
	t.kind = kind
	toasts.add_child(t)
	toasts.move_child(t, 0)
	while toasts.get_child_count() > 4:
		var old := toasts.get_child(toasts.get_child_count() - 1)
		toasts.remove_child(old)
		old.queue_free()
	toast_shown.emit(text)
	if kind == "bad":
		UiKit.sfx(self, "error")


func _big_banner(text: String, kanji: String, col: Color) -> void:
	var b := _Banner.new()
	b.text = text
	b.kanji = kanji
	b.col = col
	b.set_anchors_preset(Control.PRESET_FULL_RECT)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(b)


func _intro_anim() -> void:
	var k := 0
	for c in cards:
		c.modulate.a = 0.0
		create_tween().tween_property(c, "modulate:a", 1.0, 0.35).set_delay(0.3 + 0.05 * k)
		k += 1


# =====================================================================================
#  Results
# =====================================================================================

func collect_result(winner: int) -> Dictionary:
	_track_kills()
	var teams := []
	for t in 2:
		var initial := 0
		var alive := 0
		var k := 0
		for r in sim.regiments_of(t):
			initial += r.initial_men
			alive += maxi(r.alive, 0)
			k += int(kills.get(r.id, 0))
		teams.append({"name": UiKit.TEAM_NAMES[t], "initial": initial, "alive": alive, "lost": initial - alive,
			"kills": maxi(k, int(sim.stat_kills[t]))})
	var regs := []
	var hero := {}
	var best := -1.0
	for r in sim.regiments:
		var status := r.morale_name()
		if r.withdrawn:
			status = "Withdrawn"
		elif r.alive <= 0:
			status = "Destroyed"
		var d := {"name": r.display_name, "type": r.type_key, "team": r.team, "initial": r.initial_men,
			"alive": maxi(r.alive, 0), "kills": int(kills.get(r.id, 0)), "status": status}
		regs.append(d)
		if r.team == 0:
			var score := float(d["kills"]) * 2.0 + float(d["alive"]) / maxf(1.0, r.initial_men) * 4.0
			if score > best:
				best = score
				hero = d
	var g := get_node_or_null("/root/Game")
	return {"winner": winner, "time": sim.time, "teams": teams, "regiments": regs, "heroic": hero,
		"scenario": String(g.scenario()["title"]) if g != null else (map.title if map != null else "Battle"),
		"difficulty": String(g.difficulty_info()["name"]) if g != null else ""}


# =====================================================================================
#  Widgets
# =====================================================================================

class _PowerBar extends Control:
	## Balance of power: crimson (Hino) vs indigo (Mizuno) remaining strength, with a gold
	## needle that eases toward the current ratio.
	var hud: Hud
	var shown := 0.5

	func _draw() -> void:
		if hud == null or hud.sim == null:
			return
		var a := hud.strength(0)
		var b := hud.strength(1)
		var target := 0.5 if a + b <= 0.0 else a / (a + b)
		shown = lerpf(shown, target, 0.08)
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(0.03, 0.02, 0.015))
		var split := r.size.x * shown
		draw_rect(Rect2(1, 1, split - 1, r.size.y - 2), UiKit.HINO)
		draw_rect(Rect2(split, 1, r.size.x - split - 1, r.size.y - 2), UiKit.MIZUNO)
		draw_rect(Rect2(1, 1, split - 1, 3), Color(1, 0.6, 0.5, 0.25))
		draw_rect(Rect2(split, 1, r.size.x - split - 1, 3), Color(0.6, 0.7, 1, 0.25))
		draw_line(Vector2(r.size.x * 0.5, 0), Vector2(r.size.x * 0.5, r.size.y), Color(UiKit.WASHI, 0.25), 1.0)
		var c := Vector2(split, r.size.y * 0.5)
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -9), c + Vector2(6, 0), c + Vector2(0, 9), c + Vector2(-6, 0)]), UiKit.GOLD_HI)
		draw_rect(r, UiKit.GOLD_LO, false, 1.0)


class _SealLabel extends Control:
	var text := ""

	func _draw() -> void:
		draw_texture_rect(UiKit.tex("seal_stamp"), Rect2(Vector2.ZERO, size), false)
		var f := UiKit.font_brush()
		var fs := int(size.y * (0.42 if text.length() <= 2 else 0.3))
		var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f, Vector2((size.x - w) * 0.5, size.y * 0.5 + fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiKit.WASHI)


class _Toast extends PanelContainer:
	## Washi strip that slides down, holds, then fades. good = gold seal, bad = vermilion.
	var text := ""
	var kind := "info"

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		theme_type_variation = &"WashiPanel"
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 12)
		h.alignment = BoxContainer.ALIGNMENT_CENTER
		add_child(h)
		var dot := TextureRect.new()
		dot.texture = UiKit.tex("seal_stamp")
		dot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		dot.custom_minimum_size = Vector2(26, 26)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.modulate = {"good": Color(1.3, 1.1, 0.4), "bad": Color(1, 1, 1), "info": Color(0.55, 0.6, 0.75)}.get(kind, Color.WHITE)
		h.add_child(dot)
		var l := UiKit.label(text, "InkLabel", 24)
		l.add_theme_color_override("font_color", {"bad": Color("#7A1A10"), "good": Color("#2A1A0C")}.get(kind, Color("#2A2620")))
		h.add_child(l)
		modulate.a = 0.0
		var t := create_tween()
		t.tween_property(self, "modulate:a", 1.0, 0.2)
		t.tween_interval(3.6)
		t.tween_property(self, "modulate:a", 0.0, 0.6)
		t.tween_callback(queue_free)


class _Banner extends Control:
	## Big centred title ("Battle!", "Victory") with a seal, ink-splash fade in and out.
	var text := ""
	var kanji := ""
	var col := Color.WHITE
	var t := 0.0

	func _process(delta: float) -> void:
		t += delta
		queue_redraw()
		if t > 2.8:
			queue_free()

	func _draw() -> void:
		var a := clampf(t / 0.25, 0, 1) * clampf((2.8 - t) / 0.6, 0, 1)
		var c := size * Vector2(0.5, 0.36)
		var s := 1.0 + 0.15 * (1.0 - clampf(t / 0.35, 0, 1))
		draw_set_transform(c, 0.0, Vector2(s, s))
		draw_rect(Rect2(-900, -70, 1800, 140), Color(0, 0, 0, 0.45 * a))
		var f := UiKit.font_title()
		var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 110).x
		draw_string_outline(f, Vector2(-w * 0.5 - 40, 38), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 110, 12, Color(0, 0, 0, 0.8 * a))
		draw_string(f, Vector2(-w * 0.5 - 40, 38), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 110, Color(col.lightened(0.2), a))
		var sr := Rect2(w * 0.5 - 10, -56, 112, 112)
		draw_texture_rect(UiKit.tex("seal_stamp"), sr, false, Color(1, 1, 1, a))
		var bf := UiKit.font_brush()
		var fs := 46
		var kw := bf.get_string_size(kanji, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(bf, sr.position + Vector2((sr.size.x - kw) * 0.5, sr.size.y * 0.5 + 16), kanji, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(UiKit.WASHI, a))
		draw_set_transform(Vector2.ZERO)

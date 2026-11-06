class_name UnitCard
extends Control
## One regiment card in the HUD tray: portrait, men alive/initial, morale bar coloured by
## state, fatigue bar, state icons (running / fire at will / routing / engaged), gold selected
## frame, red flash on casualties, greyed when the regiment is out of the battle.
##
## Input (real mouse events): LMB = select · Shift+LMB = add/toggle · double-click = select and
## centre the camera. Emits signals; the Hud turns them into Commander/camera calls.

signal card_clicked(card: UnitCard, shift: bool)
signal card_double_clicked(card: UnitCard)

const CARD_SIZE := Vector2(108, 188)

var reg: Regiment
var selected := false
var hotkey := -1                     # Ctrl+N group number (set by the Hud)
var _hover := 0.0
var _flash := 0.0
var _sel_t := 0.0
var _last_alive := -1
var _lift := 0.0
var _morale_shown := 0.5
var _pulse := 0.0


func _init() -> void:
	custom_minimum_size = CARD_SIZE
	size = CARD_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	focus_mode = Control.FOCUS_NONE


func setup(r: Regiment) -> void:
	reg = r
	_last_alive = r.alive
	_morale_shown = r.morale / 100.0
	tooltip_text = "%s\n%s" % [r.display_name, _tooltip_stats()]
	mouse_entered.connect(func():
		_hover = 1.0
		UiKit.sfx(self, "hover"))
	mouse_exited.connect(func(): _hover = 0.0)


func _tooltip_stats() -> String:
	var s := reg.stats
	var t := "Men %d · Attack %d · Defence %d · Armour %d" % [int(s.get("men", 0)), int(s.get("melee_attack", 0)), int(s.get("melee_defence", 0)), int(s.get("armour", 0))]
	if float(s.get("range", 0.0)) > 0.0:
		t += "\nRange %d · Reload %.1fs" % [int(s["range"]), float(s["reload"])]
	return t


func _gui_input(event: InputEvent) -> void:
	if reg == null:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if event.double_click:
			card_double_clicked.emit(self)
		else:
			card_clicked.emit(self, event.shift_pressed)
		accept_event()


func _process(delta: float) -> void:
	if reg == null:
		return
	if reg.alive < _last_alive:
		_flash = 1.0
		_pulse = 1.0
	_last_alive = reg.alive
	_flash = maxf(0.0, _flash - delta * 2.2)
	_pulse = maxf(0.0, _pulse - delta * 4.0)
	_sel_t = move_toward(_sel_t, 1.0 if selected else 0.0, delta * 6.0)
	_lift = lerpf(_lift, (8.0 if selected else 0.0) + (4.0 if _hover > 0.0 else 0.0), 1.0 - exp(-14.0 * delta))
	_morale_shown = lerpf(_morale_shown, clampf(reg.morale / 100.0, 0.0, 1.0), 1.0 - exp(-6.0 * delta))
	queue_redraw()


func is_out() -> bool:
	return reg == null or reg.is_out()


func _draw() -> void:
	if reg == null:
		return
	var out := reg.is_out()
	var routing := reg.is_routing()
	var r := Rect2(Vector2(0, -_lift), size)
	var shake := Vector2(sin(Time.get_ticks_msec() * 0.09) * 2.0 * _pulse, 0)
	r.position += shake
	# selection glow
	if _sel_t > 0.01:
		draw_texture_rect(UiKit.tex("glow"), r.grow(26), false, Color(UiKit.GOLD_HI, 0.55 * _sel_t))
	# frame
	var frame := "frame_lacquer_hover" if selected or _hover > 0.0 else "frame_lacquer"
	if out:
		frame = "frame_lacquer_disabled"
	draw_style_box(UiKit.stylebox(frame, 26.0), r)
	# portrait
	var pr := Rect2(r.position + Vector2(9, 9), Vector2(r.size.x - 18, 100))
	var tex := UiKit.portrait(reg.type_key)
	var tint := Color(1, 1, 1)
	if out:
		tint = Color(0.35, 0.33, 0.32)
	elif routing:
		tint = Color(1.0, 0.72, 0.68)
	if tex != null:
		var tw := float(tex.get_width())
		var src_h := tw * pr.size.y / pr.size.x
		draw_texture_rect_region(tex, pr, Rect2(0, tex.get_height() * 0.08, tw, src_h), tint)
	else:
		draw_rect(pr, UiKit.team_color(reg.team))
	# team strip under the portrait + mon
	draw_rect(Rect2(pr.position.x, pr.end.y - 3, pr.size.x, 3), UiKit.team_color(reg.team, true))
	# casualty flash
	if _flash > 0.0:
		draw_rect(pr, Color(0.85, 0.08, 0.04, 0.55 * _flash))
	# state icons (top-left column)
	var icons: Array = []
	if routing:
		icons.append(["rout", Color("#FF6A4D")])
	if reg.is_engaged() and not routing:
		icons.append(["engaged", Color("#F2D27A")])
	if reg.running and not routing:
		icons.append(["run", Color("#E8DDC4")])
	if reg.is_ranged() and reg.fire_at_will and not routing:
		icons.append(["fire", Color("#9FD3FF")])
	var iy := pr.position.y + 3
	for ic in icons:
		var ir := Rect2(pr.position.x + 3, iy, 22, 22)
		draw_circle(ir.get_center(), 12.5, Color(0.05, 0.03, 0.02, 0.78))
		draw_texture_rect(UiKit.tex("icon_" + String(ic[0])), ir.grow(-2), false, ic[1])
		iy += 25
	# group badge
	if hotkey > 0:
		_badge(Vector2(pr.end.x - 14, pr.position.y + 14), str(hotkey))
	# men count over the bottom of the portrait
	var bf := UiKit.font_bold()
	var men := "%d" % reg.alive
	var tot := "/%d" % reg.initial_men
	var fs := 22
	var mw := bf.get_string_size(men, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var tw2 := bf.get_string_size(tot, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	var mx := pr.end.x - mw - tw2 - 5
	var my := pr.end.y - 8
	draw_rect(Rect2(mx - 6, my - 20, mw + tw2 + 12, 24), Color(0.04, 0.03, 0.02, 0.7))
	draw_string_outline(bf, Vector2(mx, my), men, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.8))
	draw_string(bf, Vector2(mx, my), men, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("#FF8A70") if _flash > 0.2 else UiKit.WASHI)
	draw_string(bf, Vector2(mx + mw, my), tot, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(UiKit.WASHI, 0.6))
	# name
	var nf := UiKit.font_head()
	var short := _short_name()
	var nfs := 14
	var nw := nf.get_string_size(short, HORIZONTAL_ALIGNMENT_LEFT, -1, nfs).x
	while nw > pr.size.x - 4 and nfs > 10:
		nfs -= 1
		nw = nf.get_string_size(short, HORIZONTAL_ALIGNMENT_LEFT, -1, nfs).x
	draw_string(nf, Vector2(r.position.x + (r.size.x - nw) * 0.5, pr.end.y + 18), short, HORIZONTAL_ALIGNMENT_LEFT, -1, nfs,
		UiKit.GOLD_HI if selected else Color(UiKit.WASHI, 0.85 if not out else 0.4))
	# morale bar
	var by := pr.end.y + 26
	var bw := pr.size.x
	var st: int = clampi(int(reg.state), 0, 4)
	var mcol: Color = UiKit.MORALE_COLORS[st]
	if out and not routing:
		mcol = UiKit.MORALE_COLORS[4]
	draw_rect(Rect2(pr.position.x, by, bw, 9), Color(0.04, 0.03, 0.02, 0.95))
	draw_rect(Rect2(pr.position.x + 1, by + 1, (bw - 2) * _morale_shown, 7), mcol)
	draw_rect(Rect2(pr.position.x + 1, by + 1, (bw - 2) * _morale_shown, 2), Color(1, 1, 1, 0.25))
	if routing:
		var blink := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012)
		draw_rect(Rect2(pr.position.x, by, bw, 9), Color(1, 0.3, 0.2, 0.35 * blink), false, 1.0)
	# fatigue bar
	var fy := by + 13
	draw_rect(Rect2(pr.position.x, fy, bw, 5), Color(0.04, 0.03, 0.02, 0.95))
	var fat := clampf(reg.fatigue, 0.0, 1.0)
	var fcol := Color("#7FA6B8").lerp(Color("#B8673A"), fat)
	draw_rect(Rect2(pr.position.x + 1, fy + 1, (bw - 2) * (1.0 - fat), 3), fcol)
	# state word
	var word: String = Regiment.MORALE_NAMES[st]
	if reg.withdrawn:
		word = "Withdrawn"
	elif reg.alive <= 0:
		word = "Destroyed"
	var sw := UiKit.font_body().get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	draw_string(UiKit.font_body(), Vector2(r.position.x + (r.size.x - sw) * 0.5, fy + 20), word, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(mcol, 0.95).lightened(0.15))
	# selected gold border on top
	if _sel_t > 0.01:
		draw_rect(r.grow(-2), Color(UiKit.GOLD_HI, _sel_t), false, 2.0)


func _short_name() -> String:
	match reg.type_key:
		"yari": return "Yari Ashigaru"
		"yumi": return "Yumi Ashigaru"
		"teppo": return "Teppō"
		"samurai": return "Samurai"
		"cavalry": return "Yari Cavalry"
		"general": return "Hatamoto"
	return reg.display_name


func _badge(c: Vector2, txt: String) -> void:
	draw_circle(c, 10.0, UiKit.VERMILION)
	draw_arc(c, 10.0, 0, TAU, 20, UiKit.GOLD, 1.5)
	var f := UiKit.font_bold()
	var w := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	draw_string(f, c + Vector2(-w * 0.5, 5), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UiKit.WASHI)

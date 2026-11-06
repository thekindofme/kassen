class_name ScenarioCard
extends Button
## Battle-select card: painted art in a lacquer frame, kanji seal, title, description and
## army sizes. Toggle button (one card is selected); hover lifts and glows.

var data: Dictionary
var hino_men := 0
var mizuno_men := 0
var _lift := 0.0:
	set(v):
		_lift = v
		queue_redraw()
var _tw: Tween
var _shine := 0.0


func setup(d: Dictionary, men: Array) -> void:
	data = d
	hino_men = men[0]
	mizuno_men = men[1]
	toggle_mode = true
	text = ""
	custom_minimum_size = Vector2(600, 640)
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var empty := StyleBoxEmpty.new()
	for s in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		add_theme_stylebox_override(s, empty)
	mouse_entered.connect(func():
		UiKit.sfx(self, "hover")
		_to(1.0))
	mouse_exited.connect(func(): _to(0.0))
	toggled.connect(func(_on): queue_redraw())


func _to(v: float) -> void:
	if _tw != null:
		_tw.kill()
	_tw = create_tween()
	_tw.tween_property(self, "_lift", v, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	if button_pressed:
		_shine = fmod(_shine + delta * 0.35, 1.0)
		queue_redraw()


func _draw() -> void:
	var sel := button_pressed
	var off := Vector2(0, -10.0 * _lift - (6.0 if sel else 0.0))
	var r := Rect2(off, size)
	# glow
	if sel or _lift > 0.01:
		var glow := UiKit.tex("glow")
		var a := 0.55 if sel else 0.3 * _lift
		draw_texture_rect(glow, r.grow(40), false, Color(UiKit.GOLD_HI, a))
	draw_style_box(UiKit.stylebox("frame_lacquer_hover" if (sel or _lift > 0.5) else "frame_lacquer"), r)
	# art
	var art := UiKit.art(String(data.get("art", "")))
	var ar := Rect2(r.position + Vector2(14, 14), Vector2(r.size.x - 28, 330))
	if art != null:
		var tw := float(art.get_width())
		var th := float(art.get_height())
		var src_h := tw * ar.size.y / ar.size.x
		var zoom := 1.0 - 0.05 * _lift
		var sw := tw * zoom
		var sh := src_h * zoom
		draw_texture_rect_region(art, ar, Rect2((tw - sw) * 0.5, (th - sh) * 0.45, sw, sh),
			Color(1, 1, 1) if sel or _lift > 0.1 else Color(0.78, 0.74, 0.7))
	draw_rect(ar, UiKit.GOLD_LO, false, 2.0)
	if sel:
		# moving sheen across the art
		var x := ar.position.x + ar.size.x * (_shine * 1.6 - 0.3)
		var pts := PackedVector2Array([Vector2(x, ar.position.y), Vector2(x + 60, ar.position.y), Vector2(x + 10, ar.end.y), Vector2(x - 50, ar.end.y)])
		var clipped := Geometry2D.intersect_polygons(pts, PackedVector2Array([ar.position, Vector2(ar.end.x, ar.position.y), ar.end, Vector2(ar.position.x, ar.end.y)]))
		for poly in clipped:
			draw_colored_polygon(poly, Color(1, 0.95, 0.8, 0.08))
	# seal with kanji
	var seal := UiKit.tex("seal_stamp")
	var kan := String(data.get("kanji", ""))
	var ss := 96.0 if kan.length() <= 2 else 116.0
	var sp := Vector2(ar.end.x - ss - 16, ar.position.y + 16)
	draw_texture_rect(seal, Rect2(sp, Vector2(ss, ss)), false)
	var bf := UiKit.font_brush()
	var fs := 40 if kan.length() <= 2 else 34
	var kw := bf.get_string_size(kan, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(bf, sp + Vector2((ss - kw) * 0.5, ss * 0.5 + fs * 0.36), kan, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiKit.WASHI)
	# text
	var x0 := r.position.x + 34
	var y := ar.end.y + 56
	var hf := UiKit.font_title()
	draw_string(hf, Vector2(x0, y), String(data.get("title", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 36, UiKit.GOLD_HI if sel else UiKit.GOLD)
	y += 32
	draw_string(UiKit.font_head(), Vector2(x0, y), String(data.get("subtitle", "")).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(UiKit.WASHI, 0.7))
	y += 18
	draw_line(Vector2(x0, y), Vector2(r.end.x - 34, y), Color(UiKit.GOLD_LO, 0.9), 1.0)
	y += 34
	var body := UiKit.font_body()
	var desc := String(data.get("desc", ""))
	var para := TextParagraph.new()
	para.add_string(desc, body, 22)
	para.width = r.size.x - 68
	para.draw(get_canvas_item(), Vector2(x0, y - 22), UiKit.WASHI)
	# armies
	var by := r.end.y - 62
	var bf2 := UiKit.font_bold()
	for t in 2:
		var bx := x0 + t * 270
		var mon := UiKit.mon(t)
		draw_texture_rect(mon, Rect2(bx, by - 24, 44, 44), false)
		draw_string(bf2, Vector2(bx + 54, by - 4), UiKit.TEAM_NAMES[t].to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(UiKit.WASHI, 0.65))
		draw_string(UiKit.font_title(), Vector2(bx + 54, by + 22), "%d men" % (hino_men if t == 0 else mizuno_men), HORIZONTAL_ALIGNMENT_LEFT, -1, 24,
			UiKit.team_color(t, true).lightened(0.25))

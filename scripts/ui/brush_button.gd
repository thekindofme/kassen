class_name BrushButton
extends Button
## Flat menu item with a brush-stroke underline that sweeps in on hover (left→right) and
## out on exit, a vermilion lozenge marker and a soft text lift. Plays AudioDirector ui sounds.

@export var stroke_color := Color(0.76, 0.23, 0.13, 0.92)
@export var marker := true
@export var sub_text := ""          # small caption under the main text (e.g. kanji)

var sweep := 0.0:
	set(v):
		sweep = v
		if _under != null:
			_under.queue_redraw()
var _tw: Tween
var _under: _Under


func _init() -> void:
	theme_type_variation = &"FlatButton"
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func _ready() -> void:
	mouse_entered.connect(_on_enter)
	mouse_exited.connect(_on_exit)
	focus_entered.connect(_on_enter)
	focus_exited.connect(_on_exit)
	pressed.connect(func(): UiKit.sfx(self, "click"))
	_under = _Under.new()
	_under.b = self
	_under.show_behind_parent = true
	_under.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_under.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_under, false, Node.INTERNAL_MODE_FRONT)
	add_theme_constant_override("h_separation", 0)
	if marker:
		add_theme_constant_override("outline_size", 6)


func _on_enter() -> void:
	if disabled:
		return
	UiKit.sfx(self, "hover")
	_animate(1.0, 0.28)


func _on_exit() -> void:
	if has_focus() and is_hovered():
		return
	_animate(0.0, 0.22)


func _animate(to: float, dur: float) -> void:
	if _tw != null:
		_tw.kill()
	_tw = create_tween()
	_tw.tween_property(self, "sweep", to, dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _draw_under(ci: Control) -> void:
	var font := get_theme_font("font")
	var fs := get_theme_font_size("font_size")
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var left := get_theme_stylebox("normal").get_margin(SIDE_LEFT)
	if sweep > 0.001:
		var st := UiKit.tex("brush_stroke")
		if st != null:
			var w := (tw + 60.0) * sweep
			var h := 34.0
			var r := Rect2(left - 26.0, size.y * 0.5 - h * 0.5 + fs * 0.28, w, h)
			var src := Rect2(0, 0, st.get_width() * sweep, st.get_height())
			ci.draw_texture_rect_region(st, r, src, stroke_color * Color(1, 1, 1, clampf(sweep * 1.4, 0, 1)))
		if marker:
			var c := Vector2(left - 22.0, size.y * 0.5)
			var s := 7.0 * sweep
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s), c + Vector2(s, 0), c + Vector2(0, s), c + Vector2(-s, 0)]), UiKit.GOLD_HI)
	if sub_text != "":
		var bf := UiKit.font_brush()
		if bf != null:
			ci.draw_string(bf, Vector2(left + tw + 18.0, size.y * 0.5 + 10.0), sub_text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs * 0.62),
				Color(UiKit.GOLD, 0.55 + 0.45 * sweep))


class _Under extends Control:
	var b: BrushButton

	func _draw() -> void:
		b._draw_under(self)

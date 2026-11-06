class_name Minimap
extends Control
## Painted minimap: terrain thumbnail (from the MapDef: river, ford, roads, forests, hills,
## village, deployment zones), live regiment dots (team colours, selected = gold ring,
## routing = blinking), and the camera view rectangle. LMB click/drag moves the camera.

signal jump_requested(world: Vector2)

var sim: BattleSim
var camera: Camera2D
var map: MapDef
var world_size := Vector2(4800, 3200)
var show_deploy := true
var _drag := false
var _thumb: ImageTexture
var _redraw_t := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_CROSS
	clip_contents = true


func bind(p_sim: BattleSim, p_camera: Camera2D, p_map: MapDef) -> void:
	sim = p_sim
	camera = p_camera
	map = p_map
	if map != null:
		world_size = map.size
	elif sim != null:
		world_size = sim.map_size
	_build_thumb()


func _build_thumb() -> void:
	# Prefer the terrain's splat/height images if exposed; otherwise paint from the MapDef in _draw.
	_thumb = null


func w2m(w: Vector2) -> Vector2:
	return w / world_size * size


func m2w(m: Vector2) -> Vector2:
	return (m / size * world_size).clamp(Vector2.ZERO, world_size)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_drag = event.pressed
		if event.pressed:
			_jump(event.position)
		accept_event()
	elif event is InputEventMouseMotion and _drag:
		_jump(event.position)
		accept_event()


func _jump(p: Vector2) -> void:
	var w := m2w(p)
	jump_requested.emit(w)
	if camera != null:
		if camera.has_method("focus_on"):
			camera.call("focus_on", w)
		else:
			camera.position = w


func _process(delta: float) -> void:
	_redraw_t -= delta
	if _redraw_t <= 0.0:
		_redraw_t = 0.05
		queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color("#5F7139").darkened(0.15))
	if map != null:
		_draw_map()
	# vignette edge
	draw_rect(r, Color(0, 0, 0, 0.25), false, 6.0)
	if sim != null:
		_draw_units()
	if camera != null:
		var vs := camera.get_viewport_rect().size / camera.zoom
		var c := camera.get_screen_center_position()
		var cr := Rect2(w2m(c - vs * 0.5), vs / world_size * size)
		draw_rect(cr, Color(1, 1, 1, 0.08))
		draw_rect(cr, Color(UiKit.WASHI, 0.95), false, 1.5)
	draw_rect(r, UiKit.GOLD, false, 2.0)


func _draw_map() -> void:
	var k := size / world_size
	for h in map.hills:
		var c: Vector2 = h["c"] * k
		var rad: float = float(h["r"]) * k.x
		for i in 4:
			draw_circle(c, rad * (1.0 - i * 0.22), Color("#9C9455").darkened(0.25 - i * 0.07) * Color(1, 1, 1, 0.55))
	for p in map.paddies:
		draw_rect(Rect2(p.position * k, p.size * k), Color("#6E8A4A"))
	for f in map.forests:
		var c2: Vector2 = f["c"] * k
		var rad2: float = float(f["r"]) * k.x
		draw_circle(c2, rad2, Color("#2E4424"))
		draw_circle(c2 + Vector2(-rad2 * 0.2, -rad2 * 0.2), rad2 * 0.6, Color("#38522B"))
	for road in map.roads:
		var pts := PackedVector2Array()
		for p2 in road:
			pts.append(p2 * k)
		draw_polyline(pts, Color("#B59A64"), maxf(1.5, map.road_width * k.x), true)
	if map.river.size() > 1:
		var rp := PackedVector2Array()
		for p3 in map.river:
			rp.append(p3 * k)
		draw_polyline(rp, Color("#3E5A63"), maxf(3.0, map.river_width * k.x), true)
		draw_polyline(rp, Color("#5C808A"), maxf(1.0, map.river_width * k.x * 0.4), true)
	for fd in map.fords:
		draw_line(fd["a"] * k, fd["b"] * k, Color("#B8A77A"), maxf(3.0, float(fd["width"]) * k.x * 0.5))
	for v in map.villages:
		draw_rect(Rect2(v.position * k, v.size * k), Color("#7A5A3A", 0.8))
	if show_deploy and sim != null and (sim.paused and sim.time <= 0.0):
		for t in 2:
			var z: Rect2 = map.deploy_zones[t]
			if z.size != Vector2.ZERO:
				var zr := Rect2(z.position * k, z.size * k)
				draw_rect(zr, Color(UiKit.team_color(t, true), 0.18))
				draw_rect(zr, Color(UiKit.team_color(t, true), 0.7), false, 1.0)


func _draw_units() -> void:
	var blink := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012)
	for reg in sim.regiments:
		if reg.is_out():
			continue
		var p := w2m(reg.mean_pos if reg.alive > 0 else reg.centre)
		var col := UiKit.team_color(reg.team, true).lightened(0.15)
		var rad := 3.0 + clampf(reg.alive / 20.0, 0.0, 3.0)
		if reg.is_routing():
			col = Color(col, 0.35 + 0.65 * blink)
		var fwd := reg.facing.normalized() if reg.facing != Vector2.ZERO else Vector2.RIGHT
		var right := Vector2(-fwd.y, fwd.x)
		var w := rad * 1.6
		var pts := PackedVector2Array([p + right * w + fwd * rad * 0.6, p - right * w + fwd * rad * 0.6,
			p - right * w - fwd * rad * 0.6, p + right * w - fwd * rad * 0.6])
		draw_colored_polygon(pts, Color(0, 0, 0, 0.55 * col.a))
		var inner := PackedVector2Array()
		for q in pts:
			inner.append(p + (q - p) * 0.75)
		draw_colored_polygon(inner, col)
		if reg.type_key == "general":
			draw_circle(p, 2.0, UiKit.GOLD_HI)
		if reg.selected:
			draw_arc(p, w + 3.0, 0, TAU, 16, UiKit.GOLD_HI, 1.5)

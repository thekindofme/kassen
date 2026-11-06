class_name BattleCamera
extends Camera2D
## TW-style battle camera: WASD/arrow pan, screen-edge pan, middle-drag pan, cursor-anchored
## wheel zoom (0.35–2.5), smoothing, clamped to the map. Driven only by InputEvents and the
## input map, so automated tests can steer it with Input.parse_input_event.

const ZOOM_MIN := 0.35
const ZOOM_MAX := 2.5

var map_rect := Rect2(0, 0, 4800, 3200)
var pan_speed := 1100.0          # screen px / s at zoom 1
var edge_pan := true
var edge_px := 6.0
var target_pos := Vector2.ZERO
var target_zoom := 1.0
var _anchor_world := Vector2.ZERO
var _anchor_screen := Vector2.ZERO
var _anchored := false
var _mid_drag := false
var _mouse := Vector2(-1, -1)    # last mouse position seen through events


func _ready() -> void:
	target_pos = position
	target_zoom = zoom.x
	if DisplayServer.get_name() == "headless":
		edge_pan = false
	var off := get_node_or_null("/root/Offscreen")
	if off != null and off.active:
		edge_pan = false   # 1x1 offscreen window: the real mouse is always "outside" it


func focus_on(world: Vector2, z := -1.0) -> void:
	target_pos = world
	if z > 0.0:
		target_zoom = clampf(z, ZOOM_MIN, ZOOM_MAX)
	_anchored = false


func snap() -> void:
	position = target_pos
	zoom = Vector2.ONE * target_zoom
	_clamp()
	target_pos = position


func _view_size() -> Vector2:
	return get_viewport_rect().size


func screen_to_world(screen: Vector2) -> Vector2:
	return get_canvas_transform().affine_inverse() * screen


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		_mouse = mb.position
		if mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			var f := 1.15 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15
			if mb.factor > 0.0 and mb.factor != 1.0:
				f = pow(f, mb.factor)
			_zoom_at(mb.position, target_zoom * f)
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_mid_drag = mb.pressed
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		_mouse = mm.position
		if _mid_drag:
			target_pos -= mm.relative / zoom.x
			position = target_pos
			_anchored = false
			_clamp()
			get_viewport().set_input_as_handled()
	elif event is InputEventMagnifyGesture:
		var mg := event as InputEventMagnifyGesture
		_zoom_at(mg.position, target_zoom * mg.factor)
	elif event is InputEventPanGesture:
		var pg := event as InputEventPanGesture
		target_pos += pg.delta * 18.0 / zoom.x
		_anchored = false
	elif event.is_action_pressed("cam_home"):
		focus_on(map_rect.get_center(), 0.45)


func _zoom_at(screen: Vector2, z: float) -> void:
	z = clampf(z, ZOOM_MIN, ZOOM_MAX)
	_anchor_screen = screen
	_anchor_world = screen_to_world(screen)
	_anchored = true
	target_zoom = z


func _process(delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_action_pressed("cam_left"): dir.x -= 1.0
	if Input.is_action_pressed("cam_right"): dir.x += 1.0
	if Input.is_action_pressed("cam_up"): dir.y -= 1.0
	if Input.is_action_pressed("cam_down"): dir.y += 1.0
	if Input.is_action_pressed("cam_zoom_in"):
		_zoom_at(_view_size() * 0.5, target_zoom * (1.0 + 1.5 * delta))
	if Input.is_action_pressed("cam_zoom_out"):
		_zoom_at(_view_size() * 0.5, target_zoom / (1.0 + 1.5 * delta))
	if edge_pan and _mouse.x >= 0.0 and DisplayServer.window_is_focused():
		var vs := _view_size()
		if _mouse.x <= edge_px: dir.x -= 1.0
		if _mouse.x >= vs.x - edge_px: dir.x += 1.0
		if _mouse.y <= edge_px: dir.y -= 1.0
		if _mouse.y >= vs.y - edge_px: dir.y += 1.0
	if dir != Vector2.ZERO:
		target_pos += dir.normalized() * pan_speed * delta / zoom.x
		_anchored = false
	var k := 1.0 - exp(-14.0 * delta)
	var z := lerpf(zoom.x, target_zoom, k)
	if absf(z - target_zoom) < 0.0005:
		z = target_zoom
	zoom = Vector2(z, z)
	if _anchored:
		# keep the world point under the cursor fixed while zooming
		var vs2 := _view_size()
		position = _anchor_world - (_anchor_screen - vs2 * 0.5) / z
		target_pos = position
		if z == target_zoom:
			_anchored = false
	else:
		position = position.lerp(target_pos, k)
	_clamp()


func _clamp() -> void:
	var half := _view_size() * 0.5 / zoom.x
	var lo := map_rect.position + half
	var hi := map_rect.end - half
	var p := position
	p.x = map_rect.get_center().x if lo.x > hi.x else clampf(p.x, lo.x, hi.x)
	p.y = map_rect.get_center().y if lo.y > hi.y else clampf(p.y, lo.y, hi.y)
	if p != position:
		position = p
		target_pos = target_pos.clamp(Vector2(minf(lo.x, hi.x), minf(lo.y, hi.y)), Vector2(maxf(lo.x, hi.x), maxf(lo.y, hi.y)))

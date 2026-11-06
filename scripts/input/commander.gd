class_name Commander
extends Node2D
## Player selection and orders, Total War style. Everything is driven by InputEvents
## (_unhandled_input), so the E2E runner can play through Input.parse_input_event.
##
##   LMB click: select regiment (Shift = add/toggle) · LMB drag: box select · double-click: select+focus
##   RMB click ground: move (keeps frontage, faces the move direction) · RMB drag: formation line
##   with ghost preview (drag left→right faces "up"/away) · RMB enemy: attack · double-RMB: run
##   Shift+RMB: queue order · R run · F fire at will · H halt · G group · Ctrl+1..9 / 1..9 groups
##   Space pause · +/- speed · Tab labels · Backspace withdraw · Esc deselect · Ctrl+A select all
##
## Draws (world space, under the soldiers): destination ghost markers for selected regiments and
## the live drag preview. The box-select rectangle is drawn by a child above the soldiers.

signal selection_changed(selected: Array)
signal order_issued(kind: String)

const DRAG_PX := 10.0
const SPEEDS := [0.5, 1.0, 2.0, 3.0]

var sim: BattleSim
var camera: BattleCamera
var renderer: SoldierRenderer
var team := 0
var selected: Array[Regiment] = []
var groups := {}                 # 1..9 -> Array[Regiment]
var _next_group_id := 100
var show_labels := false
var enabled := true

var _lmb_down := false
var _lmb_start := Vector2.ZERO
var _lmb_cur := Vector2.ZERO
var _box := false
var _rmb_down := false
var _rmb_start := Vector2.ZERO   # screen
var _rmb_cur := Vector2.ZERO
var _rmb_drag := false
var _ghost: Array = []           # [{reg, centre, facing, files}]
var _last_recall := {"n": -1, "t": 0}
var _box_layer: Node2D
var _drag_regs: Array = []       # deployment drag: [{reg, off, home, facing}]


func _ready() -> void:
	_box_layer = _BoxLayer.new()
	_box_layer.c = self
	_box_layer.z_index = 50
	add_child(_box_layer)


func _world(screen: Vector2) -> Vector2:
	return get_canvas_transform().affine_inverse() * screen


# =====================================================================================
#  Input
# =====================================================================================

func _unhandled_input(event: InputEvent) -> void:
	if not enabled or sim == null:
		return
	if event is InputEventMouseButton:
		_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		_mouse_motion(event as InputEventMouseMotion)
	elif event is InputEventKey and event.pressed and not event.echo:
		_key(event)


func _mouse_button(mb: InputEventMouseButton) -> void:
	if mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			_lmb_down = true
			_lmb_start = mb.position
			_lmb_cur = mb.position
			_box = false
			_drag_regs.clear()
			if sim.deploying and not mb.double_click:
				var under := sim.regiment_at(_world(mb.position), team)
				if under != null and under.selected:
					# deployment: drag the selected regiments around the zone
					for r in selected:
						_drag_regs.append({"reg": r, "off": r.centre - _world(mb.position), "home": r.centre, "facing": r.facing})
			if mb.double_click:
				var r := sim.regiment_at(_world(mb.position), team)
				if r != null:
					_select([r], false)
					focus_regiment(r)
				_lmb_down = false
		elif _lmb_down:
			_lmb_down = false
			if not _drag_regs.is_empty():
				_finish_deploy_drag(_world(mb.position))
			elif _box:
				var a := _world(_lmb_start)
				var b := _world(mb.position)
				var rect := Rect2(a, Vector2.ZERO).expand(b)
				_select(sim.regiments_in_rect(rect, team), mb.shift_pressed)
			else:
				_click_select(mb.position, mb.shift_pressed)
			_box = false
			_box_layer.queue_redraw()
		get_viewport().set_input_as_handled()
	elif mb.button_index == MOUSE_BUTTON_RIGHT:
		if mb.pressed:
			_rmb_down = true
			_rmb_start = mb.position
			_rmb_cur = mb.position
			_rmb_drag = false
			if mb.double_click:
				# second click of a double-click: re-issue the last order as a run
				_rmb_down = false
				_right_click(mb.position, true, mb.shift_pressed)
		elif _rmb_down:
			_rmb_down = false
			if _rmb_drag:
				_issue_layout(_ghost, false, mb.shift_pressed)
				_ghost.clear()
				_rmb_drag = false
			else:
				_right_click(mb.position, false, mb.shift_pressed)
			queue_redraw()
		get_viewport().set_input_as_handled()


func _mouse_motion(mm: InputEventMouseMotion) -> void:
	if _lmb_down and not _drag_regs.is_empty():
		_lmb_cur = mm.position
		if _lmb_cur.distance_to(_lmb_start) > DRAG_PX * 0.5:
			var w := _world(mm.position)
			for e in _drag_regs:
				var r: Regiment = e["reg"]
				sim.deploy_place(r, w + e["off"], r.facing)
			queue_redraw()
	elif _lmb_down:
		_lmb_cur = mm.position
		if not _box and _lmb_cur.distance_to(_lmb_start) > DRAG_PX:
			_box = true
		_box_layer.queue_redraw()
	if _rmb_down and not selected.is_empty():
		_rmb_cur = mm.position
		if not _rmb_drag and _rmb_cur.distance_to(_rmb_start) > DRAG_PX:
			_rmb_drag = true
		if _rmb_drag:
			_ghost = _layout_line(_world(_rmb_start), _world(_rmb_cur))
			queue_redraw()
	if renderer != null and not _rmb_drag:
		var hover := sim.regiment_at(_world(mm.position))
		renderer.hover_reg = hover


func _key(ev: InputEvent) -> void:
	if ev.is_action_pressed("begin_battle"):
		if sim.deploying:
			sim.begin_battle()
			queue_redraw()
	elif ev.is_action_pressed("cmd_run"):
		cmd_toggle_run()
	elif ev.is_action_pressed("cmd_fire_at_will"):
		cmd_toggle_fire()
	elif ev.is_action_pressed("cmd_halt"):
		cmd_halt()
	elif ev.is_action_pressed("cmd_withdraw"):
		cmd_withdraw()
	elif ev.is_action_pressed("cmd_group"):
		_toggle_group()
	elif ev.is_action_pressed("select_all", false, true):
		var all: Array[Regiment] = []
		for r in sim.regiments_of(team):
			if not r.is_out():
				all.append(r)
		_select(all, false)
	elif ev.is_action_pressed("toggle_pause"):
		sim.paused = not sim.paused
	elif ev.is_action_pressed("speed_up"):
		_change_speed(1)
	elif ev.is_action_pressed("speed_down"):
		_change_speed(-1)
	elif ev.is_action_pressed("toggle_labels"):
		show_labels = not show_labels
		if renderer != null:
			renderer.show_labels = show_labels
	elif ev.is_action_pressed("deselect"):
		_select([], false)
	else:
		for k in range(1, 10):
			if ev.is_action_pressed("group_assign_%d" % k, false, true):
				groups[k] = selected.duplicate()
				return
			if ev.is_action_pressed("group_recall_%d" % k, false, true):
				var g: Array = groups.get(k, [])
				var live: Array[Regiment] = []
				for r in g:
					if not r.is_out():
						live.append(r)
				_select(live, ev.shift_pressed)
				var now := Time.get_ticks_msec()
				if _last_recall["n"] == k and now - int(_last_recall["t"]) < 400 and camera != null and not live.is_empty():
					camera.focus_on(_group_centre(live))
				_last_recall = {"n": k, "t": now}
				return


## Deployment drag release: dropping a single regiment onto another of ours swaps them.
func _finish_deploy_drag(w: Vector2) -> void:
	if _drag_regs.size() == 1:
		var dragged: Regiment = _drag_regs[0]["reg"]
		for o in sim.regiments_of(team):
			if o == dragged or o.is_out():
				continue
			var half := Vector2(o.width(), o.depth()) * 0.5 + Vector2(12, 12)
			var rel := w - o.centre
			var local := Vector2(rel.dot(Vector2(-o.facing.y, o.facing.x)), rel.dot(o.facing))
			if absf(local.x) < half.x and absf(local.y) < half.y:
				var oc := o.centre
				var of := o.facing
				sim.deploy_place(o, _drag_regs[0]["home"], _drag_regs[0]["facing"])
				sim.deploy_place(dragged, oc, of)
				break
	_drag_regs.clear()
	order_issued.emit("deploy")
	queue_redraw()


# ---- order API for UI buttons (act on the current selection) ---------------------------

func cmd_toggle_run() -> void:
	var all_run := true
	for r in selected:
		all_run = all_run and r.running
	for r in selected:
		r.set_running(not all_run)
	order_issued.emit("run")


func cmd_toggle_fire() -> void:
	var all_on := true
	for r in selected:
		all_on = all_on and r.fire_at_will
	for r in selected:
		r.set_fire_at_will(not all_on)
	order_issued.emit("fire_at_will")


func cmd_halt() -> void:
	if sim.deploying:
		return
	for r in selected:
		r.order_halt()
	order_issued.emit("halt")


func cmd_withdraw() -> void:
	if sim.deploying:
		return
	for r in selected:
		r.order_withdraw()
	order_issued.emit("withdraw")


func focus_regiment(r: Regiment) -> void:
	if camera != null and r != null:
		camera.focus_on(r.mean_pos)


func _change_speed(d: int) -> void:
	var idx := SPEEDS.find(sim.time_scale)
	if idx < 0:
		idx = 1
	sim.time_scale = SPEEDS[clampi(idx + d, 0, SPEEDS.size() - 1)]


func _toggle_group() -> void:
	if selected.is_empty():
		return
	var same := selected[0].group >= 0
	for r in selected:
		same = same and r.group == selected[0].group
	var gid := -1 if same else _next_group_id
	_next_group_id += 1
	for r in selected:
		r.group = gid


# =====================================================================================
#  Selection
# =====================================================================================

func _click_select(screen: Vector2, shift: bool) -> void:
	var r := sim.regiment_at(_world(screen), team)
	if r == null:
		if not shift:
			_select([], false)
		return
	var pick: Array[Regiment] = [r]
	if r.group >= 0:
		for o in sim.regiments_of(team):
			if o != r and o.group == r.group and not o.is_out():
				pick.append(o)
	if shift and selected.has(r):
		var rest: Array[Regiment] = []
		for s in selected:
			if not pick.has(s):
				rest.append(s)
		_select(rest, false)
	else:
		_select(pick, shift)


func _select(regs: Array, add: bool) -> void:
	var out: Array[Regiment] = []
	if add:
		out = selected.duplicate()
	for r in regs:
		if r is Regiment and r.team == team and not out.has(r) and not r.is_out():
			out.append(r)
	for r in sim.regiments:
		r.selected = false
	for r in out:
		r.selected = true
	selected = out
	queue_redraw()
	selection_changed.emit(selected)


func select_regiments(list: Array, additive := false) -> void:
	_select(list, additive)


# =====================================================================================
#  Orders
# =====================================================================================

func _right_click(screen: Vector2, run: bool, queue: bool) -> void:
	_prune_selection()
	if selected.is_empty():
		return
	var w := _world(screen)
	var enemy := sim.regiment_at(w)
	if enemy != null and enemy.team != team and not enemy.is_out() and not sim.deploying:
		for r in selected:
			r.order_attack(enemy, run or r.running, queue)
		order_issued.emit("attack")
		return
	# move: line the selection up across the click, facing the direction of travel
	var gc := _group_centre(selected)
	var fwd := w - gc
	fwd = fwd.normalized() if fwd.length() > 8.0 else selected[0].facing
	var right := Vector2(-fwd.y, fwd.x)
	var total := 0.0
	for r in selected:
		total += r.width() + 40.0
	total -= 40.0
	var layout := _layout_line(w - right * total * 0.5, w + right * total * 0.5, fwd, false)
	_issue_layout(layout, run, queue)


func _prune_selection() -> void:
	var live: Array[Regiment] = []
	for r in selected:
		if not r.is_out() and not r.is_routing():
			live.append(r)
	if live.size() != selected.size():
		_select(live, false)


func _group_centre(regs: Array) -> Vector2:
	var c := Vector2.ZERO
	for r in regs:
		c += r.mean_pos
	return c / maxf(1.0, regs.size())


## Distributes the selected regiments along the line a→b. Frontage per regiment is
## proportional to its men. Facing defaults to the perpendicular of the drag (left→right =
## face up the screen). With front_on_line the front rank stands on the line.
func _layout_line(a: Vector2, b: Vector2, fwd := Vector2.ZERO, front_on_line := true) -> Array:
	var out: Array = []
	var regs: Array[Regiment] = []
	for r in selected:
		if not r.is_out() and not r.is_routing():
			regs.append(r)
	if regs.is_empty():
		return out
	var line := b - a
	var L := line.length()
	var ldir := line / L if L > 0.001 else Vector2(-fwd.y, fwd.x)
	if fwd == Vector2.ZERO:
		fwd = Vector2(ldir.y, -ldir.x)
	# keep left-to-right order along the line (no crossing paths)
	regs.sort_custom(func(p: Regiment, q: Regiment) -> bool: return p.mean_pos.dot(ldir) < q.mean_pos.dot(ldir))
	var men := 0
	for r in regs:
		men += r.alive
	var gap := 30.0
	var usable := maxf(L - gap * (regs.size() - 1), 0.0)
	var x := 0.0
	for r in regs:
		var share := usable * float(r.alive) / maxf(1.0, men)
		var f := clampi(int(round(share / r.spacing.x)) + 1, 2, maxi(2, r.alive))
		if L < 20.0:
			f = r.files
		var w := float(mini(f, r.alive) - 1) * r.spacing.x
		var ranks := ceili(float(r.alive) / f)
		var depth := float(ranks - 1) * r.spacing.y
		var c := a + ldir * (x + w * 0.5)
		if L < 20.0:
			c = a
		if front_on_line:
			c -= fwd * depth * 0.5
		out.append({"reg": r, "centre": c, "facing": fwd, "files": f})
		x += maxf(share, w) + gap
	return out


func _issue_layout(layout: Array, run: bool, queue: bool) -> void:
	if sim.deploying:
		for e in layout:
			sim.deploy_place(e["reg"], e["centre"], e["facing"], e["files"])
		if not layout.is_empty():
			order_issued.emit("deploy")
		queue_redraw()
		return
	for e in layout:
		var r: Regiment = e["reg"]
		r.order_move(e["centre"], e["facing"], e["files"], run or r.running, queue)
	if not layout.is_empty():
		order_issued.emit("move")
	queue_redraw()


# =====================================================================================
#  Drawing: ghost previews + destination markers (under soldiers)
# =====================================================================================

func _process(_d: float) -> void:
	if not selected.is_empty() or not _ghost.is_empty() or (sim != null and sim.deploying):
		queue_redraw()


func _draw() -> void:
	if sim == null:
		return
	if sim.deploying and team < sim.deploy_zones.size():
		var z: Rect2 = sim.deploy_zones[team]
		draw_rect(z, Color(0.83, 0.64, 0.24, 0.08), true)
		draw_rect(z.grow(-3.0), Color(0.83, 0.64, 0.24, 0.25), false, 6.0)
		draw_rect(z, Color(0.95, 0.78, 0.38, 0.85), false, 2.0)
	var col_ghost := Color(1.0, 0.86, 0.45, 0.55)
	for e in _ghost:
		var r: Regiment = e["reg"]
		_draw_formation(r.preview_slots(e["centre"], e["facing"], e["files"]), e["centre"], e["facing"], r, col_ghost, true)
	if _ghost.is_empty():
		for r in selected:
			if r.is_out():
				continue
			var o := r.current_order()
			if o.is_empty():
				continue
			if o["type"] == Regiment.Order.MOVE or o["type"] == Regiment.Order.WITHDRAW:
				draw_line(r.mean_pos, r.dest_centre, Color(1, 0.9, 0.6, 0.35), 2.0)
				_draw_formation(r.preview_slots(r.dest_centre, r.dest_facing, r.dest_files), r.dest_centre, r.dest_facing, r, Color(1, 0.9, 0.6, 0.35), false)
				# queued waypoints
				var prev := r.dest_centre
				for q in range(1, r.orders.size()):
					var qo: Dictionary = r.orders[q]
					if qo.has("pos"):
						draw_line(prev, qo["pos"], Color(1, 0.9, 0.6, 0.22), 1.5)
						draw_circle(qo["pos"], 5.0, Color(1, 0.9, 0.6, 0.35))
						prev = qo["pos"]
			elif o["type"] == Regiment.Order.ATTACK:
				var t: Regiment = o["target"]
				if t != null and t.alive > 0:
					draw_line(r.mean_pos, t.mean_pos, Color(0.95, 0.3, 0.2, 0.45), 2.5)
					draw_arc(t.mean_pos, 14.0, 0, TAU, 20, Color(0.95, 0.3, 0.2, 0.6), 2.0)


func _draw_formation(slots: PackedVector2Array, c: Vector2, fwd: Vector2, r: Regiment, col: Color, strong: bool) -> void:
	var rad: float = r.stats["radius"]
	for p in slots:
		draw_circle(p, rad * (0.7 if strong else 0.55), col)
	# facing arrow from the front edge
	var front := c + fwd * (r.depth() * 0.5 + 14.0)
	var tip := front + fwd * 22.0
	var side := Vector2(-fwd.y, fwd.x) * 8.0
	draw_line(front, tip, col, 2.5)
	draw_colored_polygon(PackedVector2Array([tip + fwd * 8.0, tip + side, tip - side]), col)


class _BoxLayer extends Node2D:
	var c: Commander

	func _draw() -> void:
		if c == null or not c._box:
			return
		var a := c._world(c._lmb_start)
		var b := c._world(c._lmb_cur)
		var rect := Rect2(a, Vector2.ZERO).expand(b)
		draw_rect(rect, Color(1, 0.9, 0.6, 0.12), true)
		draw_rect(rect, Color(1, 0.9, 0.6, 0.8), false, 1.5)

extends Node
## End-to-end runner (autoload "E2E"). Inert unless launched with `-- --e2e=<scenario>`.
##
## Plays the game ONLY through real InputEvents (Input.parse_input_event): mouse motion,
## clicks, drags, wheel and keys at screen positions computed from world positions through the
## camera transform. A fake cursor (with click ripples and drag lines) is drawn on a top
## CanvasLayer so recordings show what is being clicked. Every assertion logs
## `E2E PASS <step>` / `E2E FAIL <step>`; the run ends with `E2E RESULT PASS|FAIL` and exit
## code 0/1.
##
## Scenarios: full_battle, smoke_input.  Record: tools/record.sh full_battle proof/e2e.mp4
## Extra args: --e2e_timeout=<frames> (default 60000), --e2e_debug (periodic state dumps).

const DODGE := false
const SAFE_BATTLE := Rect2(150, 150, 1450, 640)   # screen area free of HUD panels (viewport coords)
const SAFE_DEPLOY := Rect2(150, 280, 1450, 540)   # below the deployment banner

var scenario := ""
var failures := 0
var passes := 0
var orders := 0
var cur := Vector2(960, 540)                # fake cursor, viewport coords
var _held := 0                              # mouse button mask currently held
var _drag_from := Vector2(-1, -1)
var _ripples: Array = []                    # [pos, age, color]
var _cursor: Node2D
var _frames := 0
var _scene_name := ""
var _assault := false   # doctrine treats every enemy as a target (attacking a defended position)
var _ford := Vector2(2665, 1645)

## Enemy regiments that have crossed to our (west) bank: fighting in the ford funnel is suicide.
func _on_our_bank(e: Regiment) -> bool:
	return e.mean_pos.x < _ford.x - 60.0
var _timeout := 30000
var _t0 := 0


func _ready() -> void:
	var args := _args()
	if not args.has("e2e"):
		set_process(false)
		return
	scenario = String(args["e2e"])
	_timeout = int(args.get("e2e_timeout", 60000))
	process_mode = Node.PROCESS_MODE_ALWAYS
	var layer := CanvasLayer.new()
	layer.layer = 200
	add_child(layer)
	_cursor = _Cursor.new()
	_cursor.r = self
	layer.add_child(_cursor)
	_t0 = Time.get_ticks_msec()
	log_line("E2E START %s" % scenario)
	_run.call_deferred()


func _args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1] if kv.size() > 1 else true
	return out


func _process(delta: float) -> void:
	_frames += 1
	for rp in _ripples:
		rp[1] += delta
	_ripples = _ripples.filter(func(rp): return rp[1] < 0.6)
	_cursor.queue_redraw()
	var cs := get_tree().current_scene
	var nm := String(cs.name) if cs != null else "<none>"
	if nm != _scene_name:
		log_line("E2E INFO scene -> %s (frame %d)" % [nm, _frames])
		_scene_name = nm
	if _frames % 150 == 0 and sim() != null and _args().has("e2e_strength"):
		log_line("E2E STR t=%.0f %s vs %s" % [sim().time, sim().team_strength(0), sim().team_strength(1)])
	if _frames % 120 == 0 and sim() != null and _args().has("e2e_debug"):
		var line := "E2E DBG t=%.0f " % sim().time
		for r in sim().regiments:
			line += "[%d%s %s %d %s %s] " % [r.team, r.type_key.substr(0, 3), r.morale_name().substr(0, 3), r.alive, "%d,%d" % [int(r.mean_pos.x), int(r.mean_pos.y)], "T" if r.target() != null else ("M" if not r.is_idle() else "-")]
		log_line(line)
	if _frames > _timeout:
		check(false, "timeout after %d frames" % _timeout)
		finish()


func log_line(s: String) -> void:
	print(s)


func check(cond: bool, step: String) -> bool:
	if cond:
		passes += 1
		log_line("E2E PASS %s" % step)
	else:
		failures += 1
		log_line("E2E FAIL %s" % step)
	return cond


var _finished := false

func finish() -> void:
	if _finished:
		return
	_finished = true
	var ok := failures == 0 and passes > 0
	log_line("E2E RESULT %s (%d passed, %d failed, %d frames, %.1f s wall)" % ["PASS" if ok else "FAIL", passes, failures, _frames, (Time.get_ticks_msec() - _t0) / 1000.0])
	await get_tree().process_frame
	get_tree().quit(0 if ok else 1)


func _run() -> void:
	# Real OS mouse events (the off-screen window is 1x1) would trigger camera edge-panning.
	get_tree().node_added.connect(func(n):
		if n is BattleCamera:
			n.edge_pan = false)
	match scenario:
		"full_battle":
			await _scenario_full_battle()
		"smoke_input":
			await _scenario_smoke_input()
		"tenmoku":
			await _scenario_tenmoku()
		"showcase":
			await _scenario_showcase()
		_:
			check(false, "unknown scenario '%s'" % scenario)
	finish()


# =====================================================================================
#  Game access (read-only, for targeting and assertions)
# =====================================================================================

func battle() -> Node:
	var cs := get_tree().current_scene
	if cs != null and "sim" in cs and cs.sim != null:
		return cs
	return null


func sim() -> BattleSim:
	var b := battle()
	return b.sim if b != null else null


func cam() -> Camera2D:
	return get_viewport().get_camera_2d()


func cmd() -> Commander:
	var b := battle()
	return b.commander if b != null else null


func to_screen(world: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * world


func _win(p: Vector2) -> Vector2:
	return get_tree().root.get_final_transform() * p


## A good on-screen point to click a regiment: the body of the living soldier nearest its centre.
func reg_point(r: Regiment, nth := 0) -> Vector2:
	# nth > 0 picks the soldier nearest a point shifted toward the regiment's rear (a retry
	# when a neighbour's sprite overlapped the first choice)
	var s := sim()
	var best := -1
	var bd := INF
	var spos := s.pos
	var st := s.state
	var aim := r.mean_pos - r.facing * r.depth() * 0.35 * nth
	for i in r.soldiers:
		if st[i] < BattleSim.DEAD:
			var d := spos[i].distance_squared_to(aim)
			if d < bd:
				bd = d
				best = i
	if best < 0:
		return r.mean_pos
	return spos[best] - Vector2(0, 26 if r.is_mounted() else 18)


func own(type_key := "") -> Array[Regiment]:
	var out: Array[Regiment] = []
	for r in sim().regiments_of(0):
		if not r.is_out() and not r.is_routing() and (type_key == "" or r.type_key == type_key):
			out.append(r)
	return out


func enemies(type_key := "") -> Array[Regiment]:
	var out: Array[Regiment] = []
	for r in sim().regiments_of(1):
		if not r.is_out() and not r.is_routing() and (type_key == "" or r.type_key == type_key):
			out.append(r)
	return out


func nearest(from: Vector2, regs: Array) -> Regiment:
	var best: Regiment = null
	var bd := INF
	for r in regs:
		var d: float = from.distance_to(r.mean_pos)
		if d < bd:
			bd = d
			best = r
	return best


# =====================================================================================
#  Input primitives (real InputEvents only)
# =====================================================================================

func frames(n: int) -> void:
	for k in n:
		await get_tree().process_frame


## Waits until cond() is true (checked every frame), at most max_frames. Returns success.
func wait_until(cond: Callable, max_frames: int) -> bool:
	for k in max_frames:
		if cond.call():
			return true
		await get_tree().process_frame
	return cond.call()


func _motion(p: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = _win(p)
	e.global_position = e.position
	e.relative = _win(p) - _win(cur)
	e.button_mask = _held
	cur = p
	Input.parse_input_event(e)


## Glide the cursor to p over n frames (ease in/out), emitting motion events each frame.
func move(p: Vector2, n := 12) -> void:
	var a := cur
	for k in range(1, n + 1):
		var t := float(k) / n
		t = t * t * (3.0 - 2.0 * t)
		_motion(a.lerp(p, t))
		await get_tree().process_frame


func _button(btn: int, pressed: bool, dbl := false, shift := false) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = btn
	e.pressed = pressed
	e.double_click = dbl
	e.shift_pressed = shift
	e.position = _win(cur)
	e.global_position = e.position
	var bit := 1 << (btn - 1)
	_held = (_held | bit) if pressed else (_held & ~bit)
	e.button_mask = _held
	Input.parse_input_event(e)
	if pressed and btn <= MOUSE_BUTTON_RIGHT:
		_ripples.append([cur, 0.0, Color(1, 0.85, 0.4) if btn == MOUSE_BUTTON_LEFT else Color(1, 0.35, 0.25)])


var glide := 12   # frames per cursor glide (shorter while commanding the melee)

func click(p: Vector2, btn := MOUSE_BUTTON_LEFT, shift := false, n := -1) -> void:
	await move(p, glide if n < 0 else n)
	_button(btn, true, false, shift)
	await frames(2)
	_button(btn, false, false, shift)
	await frames(2)


func double_click(p: Vector2, btn := MOUSE_BUTTON_LEFT, n := -1) -> void:
	await click(p, btn, false, n)
	_button(btn, true, true)
	await frames(2)
	_button(btn, false)
	await frames(2)


func drag(a: Vector2, b: Vector2, btn := MOUSE_BUTTON_LEFT, n := 24, shift := false) -> void:
	await move(a)
	_button(btn, true, false, shift)
	_drag_from = a
	await frames(2)
	await move(b, n)
	await frames(2)
	_button(btn, false, false, shift)
	_drag_from = Vector2(-1, -1)
	await frames(2)


func wheel(p: Vector2, up: bool, notches := 1) -> void:
	await move(p, 8)
	for k in notches:
		var btn := MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
		var e := InputEventMouseButton.new()
		e.button_index = btn
		e.pressed = true
		e.factor = 1.0
		e.position = _win(cur)
		e.global_position = e.position
		Input.parse_input_event(e)
		var e2 := e.duplicate()
		e2.pressed = false
		Input.parse_input_event(e2)
		await frames(3)


func key(code: Key, ctrl := false, hold := 2, shift := false) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = pressed
		e.ctrl_pressed = ctrl
		e.shift_pressed = shift
		Input.parse_input_event(e)
		await frames(hold if pressed else 1)


## Pans with the arrow keys until every world point is inside SAFE (zooming out with the wheel if
## they can't all fit). Real keyboard input; returns true when visible.
func ensure_visible(pts: Array, max_frames := 360, area := Rect2()) -> bool:
	var SAFE := SAFE_DEPLOY if (sim() != null and sim().deploying) else SAFE_BATTLE
	if area.size != Vector2.ZERO:
		SAFE = area
	for attempt in max_frames / 6:
		var rect := Rect2(to_screen(pts[0]), Vector2.ZERO)
		for p in pts:
			rect = rect.expand(to_screen(p))
		rect = rect.grow(30)
		if SAFE.encloses(rect):
			if await settle():
				return true
			continue
		if rect.size.x > SAFE.size.x * 0.85 or rect.size.y > SAFE.size.y * 0.85:
			await wheel(SAFE.get_center(), false, 1)
			continue
		var dx := 0
		var dy := 0
		if rect.position.x < SAFE.position.x: dx = -1
		elif rect.end.x > SAFE.end.x: dx = 1
		if rect.position.y < SAFE.position.y: dy = -1
		elif rect.end.y > SAFE.end.y: dy = 1
		var keys: Array[Key] = []
		if dx < 0: keys.append(KEY_LEFT)
		if dx > 0: keys.append(KEY_RIGHT)
		if dy < 0: keys.append(KEY_UP)
		if dy > 0: keys.append(KEY_DOWN)
		var cp0 := cam().position
		for k in keys:
			_key_state(k, true)
		var off := maxf(maxf(SAFE.position.x - rect.position.x, rect.end.x - SAFE.end.x), maxf(SAFE.position.y - rect.position.y, rect.end.y - SAFE.end.y))
		await frames(clampi(int(off / 60.0), 1, 6))
		if _args().has("e2e_debug"):
			log_line("E2E DIAG pan %s rect %s cam %s -> %s action %s" % [keys, rect, cp0, cam().position, Input.is_action_pressed("cam_up")])
		for k in keys:
			_key_state(k, false)
		await settle()
	await frames(10)
	return false


## Waits for the camera's smoothing to come to rest (so screen positions stay valid).
func settle(max_frames := 90) -> bool:
	var last := Vector2(INF, INF)
	var still := 0
	var moved := false
	for k in max_frames:
		var c := cam()
		var now := c.position + Vector2(c.zoom.x * 10000.0, 0)
		if now.distance_to(last) < 0.25:
			still += 1
			if still >= 3:
				return not moved
		else:
			if last.x != INF:
				moved = true
			still = 0
		last = now
		await get_tree().process_frame
	return false


func _key_state(code: Key, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = pressed
	Input.parse_input_event(e)


# =====================================================================================
#  Fake cursor overlay
# =====================================================================================

class _Cursor extends Node2D:
	var r

	func _draw() -> void:
		var p: Vector2 = r.cur
		if r._drag_from.x >= 0.0:
			draw_line(r._drag_from, p, Color(1, 0.9, 0.5, 0.9), 2.5)
			draw_circle(r._drag_from, 5.0, Color(1, 0.9, 0.5, 0.9))
		for rp in r._ripples:
			var t: float = rp[1] / 0.6
			var c: Color = rp[2]
			c.a = 1.0 - t
			draw_arc(rp[0], 6.0 + 30.0 * t, 0, TAU, 32, c, 3.0)
		var arrow := PackedVector2Array([p, p + Vector2(0, 26), p + Vector2(7, 20), p + Vector2(12, 31),
			p + Vector2(17, 29), p + Vector2(12, 18), p + Vector2(21, 18)])
		var shadow := PackedVector2Array()
		for q in arrow:
			shadow.append(q + Vector2(2, 3))
		draw_colored_polygon(shadow, Color(0, 0, 0, 0.45))
		draw_colored_polygon(arrow, Color(1, 1, 1))
		var outline := arrow.duplicate()
		outline.append(p)
		draw_polyline(outline, Color(0.05, 0.05, 0.05), 1.5)
		if r._held & 1:
			draw_circle(p, 4.0, Color(1, 0.85, 0.4))
		elif r._held & 2:
			draw_circle(p, 4.0, Color(1, 0.35, 0.25))


# =====================================================================================
#  Order helpers (all through the mouse / keyboard)
# =====================================================================================

func select_regs(regs: Array) -> void:
	var pts: Array = []
	for r in regs:
		pts.append(r.mean_pos)
	# soldiers must be big enough on screen to click reliably
	if cam().zoom.x < 0.62:
		await wheel(to_screen(pts[0]), true, 1)
		await settle()
	await ensure_visible(pts)
	var first := true
	for r in regs:
		for attempt in 3:
			await click(to_screen(reg_point(r, attempt)), MOUSE_BUTTON_LEFT, not first)
			if r.selected:
				break
		first = false
	if not regs.all(func(r): return r.selected):
		log_line("E2E INFO selection incomplete: %d/%d" % [regs.filter(func(r): return r.selected).size(), regs.size()])


func attack_with(regs: Array, target: Regiment, run := false) -> void:
	await select_regs(regs)
	await ensure_visible([target.mean_pos] + regs.map(func(r): return r.mean_pos))
	var p := to_screen(reg_point(target))
	if run:
		await double_click(p, MOUSE_BUTTON_RIGHT)
	else:
		await click(p, MOUSE_BUTTON_RIGHT)
	orders += 1


func line_move(regs: Array, a: Vector2, b: Vector2) -> void:
	await select_regs(regs)
	await ensure_visible([a, b])
	await drag(to_screen(a), to_screen(b), MOUSE_BUTTON_RIGHT, 30)
	orders += 1


func set_paused(on: bool) -> void:
	# P (also bound to toggle_pause): Space doubles as ui_accept for any focused HUD button
	if sim().paused != on:
		await key(KEY_P)
	if sim().paused != on:
		log_line("E2E INFO pause toggle did not take (wanted %s)" % on)


func casualties(team: int) -> int:
	var c := 0
	for r in sim().regiments_of(team):
		c += r.initial_men - r.alive
	return c


func _controls_at(p: Vector2) -> Array:
	var out: Array = []
	var stack: Array = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for ch in n.get_children():
			stack.append(ch)
		if n is Control and n.is_visible_in_tree() and n.mouse_filter != Control.MOUSE_FILTER_IGNORE and n.get_global_rect().has_point(p):
			out.append(String(n.get_path()).right(60))
	return out


func find_control(n: String) -> Control:
	var found := get_tree().root.find_child(n, true, false)
	return found as Control


# =====================================================================================
#  Scenario: smoke_input (every hotkey once)
# =====================================================================================

func _scenario_smoke_input() -> void:
	if not check(await wait_until(func(): return sim() != null, 600), "battle scene loaded"):
		return
	var s := sim()
	var c := cmd()
	await frames(10)
	var y := own("yari")
	await select_regs([y[0]])
	check(c.selected.size() == 1, "click selects")
	var ok_deploy := s.deploying
	await key(KEY_ENTER)
	check(not s.deploying, "Enter begins battle (was deploying %s)" % ok_deploy)
	await key(KEY_R)
	check(y[0].running, "R run on")
	await key(KEY_R)
	check(not y[0].running, "R run off")
	var yumi := own("yumi")[0]
	await select_regs([yumi])
	await key(KEY_F)
	check(not yumi.fire_at_will, "F hold fire")
	await key(KEY_F)
	check(yumi.fire_at_will, "F fire at will")
	await click(to_screen(yumi.mean_pos + Vector2(150, 0)), MOUSE_BUTTON_RIGHT)
	await frames(5)
	check(not yumi.is_idle(), "RMB move")
	await key(KEY_H)
	check(yumi.is_idle(), "H halts")
	await key(KEY_1, true)
	await key(KEY_ESCAPE)
	check(c.selected.is_empty(), "Esc deselects")
	await key(KEY_1)
	check(c.selected.size() == 1 and c.selected[0] == yumi, "Ctrl+1 / 1 control group")
	await select_regs([y[0], y[1]])
	await key(KEY_G)
	check(y[0].group >= 0 and y[0].group == y[1].group, "G groups")
	await key(KEY_ESCAPE)
	await ensure_visible([y[0].mean_pos])
	await click(to_screen(reg_point(y[0])))
	check(c.selected.size() == 2, "clicking a grouped regiment selects the group (%d)" % c.selected.size())
	await key(KEY_G)
	await key(KEY_A, true)
	check(c.selected.size() >= own().size() - 1, "Ctrl+A selects all")
	await key(KEY_ESCAPE)
	await key(KEY_SPACE)
	check(s.paused, "Space pauses")
	await key(KEY_SPACE)
	check(not s.paused, "Space resumes")
	await key(KEY_EQUAL)
	check(s.time_scale == 2.0, "+ speeds up")
	await key(KEY_MINUS)
	check(s.time_scale == 1.0, "- slows down")
	var lab: bool = c.show_labels
	await key(KEY_TAB)
	check(c.show_labels != lab, "Tab toggles labels")
	var p0 := cam().position
	_key_state(KEY_D, true)
	await frames(15)
	_key_state(KEY_D, false)
	await frames(10)
	check(cam().position.x > p0.x + 20.0, "D pans the camera")
	var z0 := cam().zoom.x
	await wheel(Vector2(900, 500), true, 2)
	await frames(15)
	check(cam().zoom.x > z0, "wheel zooms in")
	_key_state(KEY_Q, true)
	await frames(10)
	_key_state(KEY_Q, false)
	check(cam().zoom.x < z0 * 1.3, "Q zooms out")
	var y2: Regiment = own("yari")[2] if own("yari").size() > 2 else y[0]
	await select_regs([y2])
	await key(KEY_BACKSPACE)
	await frames(5)
	var o := y2.current_order()
	check(not o.is_empty() and o["type"] == Regiment.Order.WITHDRAW, "Backspace withdraws")


# =====================================================================================
#  Scenario: full_battle
# =====================================================================================

## Title → battle select → briefing, clicking the real buttons (only when booted into the menus).
func _menu_flow(card := "CardKurogawa") -> void:
	var diff := String(_args().get("e2e_difficulty", "normal")).capitalize()
	log_line("E2E INFO menu flow: %s, difficulty %s" % [card, diff])
	for step in [["BattlesButton", "title: Battles"], [card, "select: %s card" % card],
			["Difficulty" + diff, "select: difficulty " + diff], ["BeginButton", "select: Begin"],
			["ContinueButton", "briefing: Continue"]]:
		var ok := await wait_until(func():
			var c := find_control(step[0])
			return c != null and c.is_visible_in_tree(), 600)
		if not check(ok, step[1]):
			return
		await frames(20)
		await click(find_control(step[0]).get_global_rect().get_center())
		await frames(30)


func _scenario_full_battle() -> void:
	await frames(30)
	if sim() == null and find_control("BattlesButton") != null:
		await _menu_flow()
	if not check(await wait_until(func(): return sim() != null, 900), "battle scene loaded"):
		return
	var s := sim()
	var c := cmd()
	await frames(20)
	check(s.deploying, "battle opens in deployment")

	# --- deployment: box-select two adjacent spear regiments, lay them out with an RMB-drag
	var ys := own("yari")
	ys.sort_custom(func(p, q): return p.mean_pos.y < q.mean_pos.y)
	var a: Regiment = ys[0]
	var b: Regiment = ys[1]
	await ensure_visible([a.mean_pos, b.mean_pos])
	var ra := Rect2(to_screen(a.mean_pos), Vector2.ZERO).expand(to_screen(b.mean_pos))
	await drag(ra.position - Vector2(12, 12), ra.end + Vector2(12, 12), MOUSE_BUTTON_LEFT, 20)
	if not check(c.selected.has(a) and c.selected.has(b), "box-select picks two regiments (%d selected)" % c.selected.size()):
		log_line("E2E DIAG box from %s to %s; controls there: %s; win xf %s" % [ra.position, ra.end, _controls_at(ra.position - Vector2(12, 12)), get_tree().root.get_final_transform()])
	var zone: Rect2 = s.deploy_zones[0]
	_ford = battle().map.ai_hints.get("ford", _ford)
	var ca := a.centre
	var mid := (a.centre + b.centre) * 0.5
	var lx := zone.end.x - 90.0
	var half := (a.width() + b.width()) * 0.5 + 40.0
	await ensure_visible([Vector2(lx, mid.y - half), Vector2(lx, mid.y + half)])
	await drag(to_screen(Vector2(lx, mid.y - half)), to_screen(Vector2(lx, mid.y + half)), MOUSE_BUTTON_RIGHT, 30)
	orders += 1
	await frames(5)
	check(a.centre.distance_to(ca) > 20.0 and zone.has_point(a.centre) and zone.has_point(b.centre), "RMB-drag redeploys inside the zone")
	check(a.facing.x > 0.9, "line faces the enemy")
	await _deploy_army(zone)
	var begin := find_control("BeginBattleButton")
	if begin != null and begin.is_visible_in_tree():
		await click(begin.get_global_rect().get_center())
	if s.deploying:
		await key(KEY_ENTER)
	check(not s.deploying, "battle begins")
	if _args().has("e2e_quick"):
		return

	# --- camera: keys + wheel
	var p0 := cam().position
	_key_state(KEY_D, true)
	await frames(20)
	_key_state(KEY_D, false)
	_key_state(KEY_W, true)
	await frames(10)
	_key_state(KEY_W, false)
	await frames(10)
	check(cam().position.distance_to(p0) > 30.0, "camera pans with WASD")
	var z0 := cam().zoom.x
	await wheel(Vector2(960, 480), false, 2)
	await frames(20)
	check(cam().zoom.x < z0, "wheel zooms out")
	await wheel(Vector2(960, 480), true, 1)

	await _battle_plan()


## Full deployment with RMB-drags: the battle line along the front of the zone facing the ford,
## archers and gunners as a skirmish screen just ahead of it, cavalry behind the wings.
func _deploy_army(zone: Rect2) -> void:
	var cy: float = clampf(_ford.y, zone.position.y + 450.0, zone.end.y - 450.0)
	var fx := zone.end.x - 150.0
	var line: Array = own("yari") + own("samurai")
	var span := 0.0
	for r in line:
		span += r.width() + 30.0
	await line_move(line, Vector2(fx, cy - span * 0.5), Vector2(fx, cy + span * 0.5))
	var screen: Array = own("yumi") + own("teppo")
	await line_move(screen, Vector2(fx + 95.0, cy - 430.0), Vector2(fx + 95.0, cy + 430.0))
	var cav := own("cavalry")
	if cav.size() >= 2:
		await line_move([cav[0]], Vector2(fx - 150.0, cy - span * 0.5 - 60.0), Vector2(fx - 150.0, cy - span * 0.5 + 100.0))
		await line_move([cav[1]], Vector2(fx - 150.0, cy + span * 0.5 - 100.0), Vector2(fx - 150.0, cy + span * 0.5 + 60.0))
	var gen := own("general")
	if not gen.is_empty():
		await line_move(gen, Vector2(fx - 260.0, cy - 60.0), Vector2(fx - 260.0, cy + 60.0))
	var inside := true
	for r in own():
		inside = inside and zone.grow(4.0).has_point(r.centre)
	check(inside, "whole army deployed inside the zone")


# ---- streamer camera: zoom in on the action between orders (keys + wheel only) -----------

const CENTRE := Rect2(700, 330, 520, 300)
var _last_spectate := -999

## Where the action is: the biggest melee, else the closest pair of opposing regiments.
func hotspot() -> Vector2:
	var s := sim()
	var best := Vector2.INF
	var most := 0
	for r in s.regiments:
		if r.engaged > most and not r.is_out():
			most = r.engaged
			best = r.mean_pos
	if best != Vector2.INF:
		return best
	var bd := INF
	for a in own():
		for e in enemies():
			var d: float = a.mean_pos.distance_to(e.mean_pos)
			if d < bd:
				bd = d
				best = (a.mean_pos * 0.65 + e.mean_pos * 0.35)
	return best if best != Vector2.INF else cam().position


## Pan (arrow keys) so `world` is near the screen centre, then wheel to roughly `z`.
func focus(world: Vector2, z := 1.4) -> void:
	await ensure_visible([world], 240, CENTRE)
	var c := cam()
	for k in 8:
		if c.zoom.x < z / 1.12:
			await wheel(to_screen(world), true, 1)
		elif c.zoom.x > z * 1.12:
			await wheel(to_screen(world), false, 1)
		else:
			break
	await settle()


func spectate(every := 150) -> void:
	if _frames - _last_spectate < every or sim() == null or sim().ended:
		return
	_last_spectate = _frames
	await focus(hotspot(), 1.45)


func _set_speed(x: float) -> void:
	var s := sim()
	for k in 6:
		if is_equal_approx(s.time_scale, x):
			return
		await key(KEY_EQUAL if s.time_scale < x else KEY_MINUS)


func _closest_enemy_dist(regs: Array) -> float:
	var best := INF
	for r in regs:
		for e in enemies():
			best = minf(best, r.mean_pos.distance_to(e.mean_pos))
	return best


func _battle_plan() -> void:
	var s := sim()
	var t_begin := s.time
	var bows := own("yumi")
	var guns := own("teppo")
	var line: Array = own("yari") + own("samurai")
	var cav := own("cavalry")
	var ford: Vector2 = battle().map.ai_hints.get("ford", Vector2(2665, 1645))
	_ford = ford

	await wheel(Vector2(900, 470), false, 2)
	await settle()
	# --- race to the ford and hold its west exit in an arc: the enemy must come through the
	#     shallows in column, under our bows and guns, into a hedge of braced spears
	var exit_x: float = minf(battle().map.fords[0]["a"].x, battle().map.fords[0]["b"].x) - 130.0
	var spears := own("yari")
	await set_paused(true)
	await line_move(spears, Vector2(exit_x - 430.0, ford.y - 280.0), Vector2(exit_x - 430.0, ford.y + 280.0))
	await key(KEY_R)
	check(spears.all(func(r): return r.running and not r.is_idle()), "spears run to the ford (RMB-drag + R)")
	await line_move(own("samurai"), Vector2(exit_x - 380.0, ford.y - 500.0), Vector2(exit_x - 380.0, ford.y + 500.0))
	await key(KEY_R)
	await line_move(bows + guns, Vector2(exit_x - 200.0, ford.y - 300.0), Vector2(exit_x - 200.0, ford.y + 300.0))
	await key(KEY_R)
	await line_move(cav, Vector2(exit_x - 560.0, ford.y - 560.0), Vector2(exit_x - 560.0, ford.y + 560.0))
	await line_move(own("general"), Vector2(exit_x - 600.0, ford.y - 60.0), Vector2(exit_x - 600.0, ford.y + 60.0))
	check(line.all(func(r): return not r.is_idle()), "battle line advances (RMB-drag)")
	await set_paused(false)
	await _set_speed(3.0)
	await fight_until(func(): return _closest_enemy_dist(bows) < 620.0 or s.ended, 3000)

	if s.ended:
		await _end_of_battle(t_begin)
		return
	# --- archers: target the nearest enemy, see arrows land
	var arrows0 := s.stat_arrows_fired
	var cas0 := casualties(1)
	await set_paused(true)
	# counter-battery: enemy missiles first
	var their_missiles: Array = enemies("yumi") + enemies("teppo")
	var tgt := nearest(bows[0].mean_pos, their_missiles)
	if tgt == null or tgt.mean_pos.distance_to(bows[0].mean_pos) > 660.0:
		tgt = nearest(bows[0].mean_pos, enemies())
	if tgt != null and tgt.mean_pos.distance_to(bows[0].mean_pos) > 660.0:
		tgt = null
	if tgt != null:
		await attack_with(bows, tgt)
		check(bows[0].target() == tgt, "archers ordered onto %s" % tgt.display_name)
	await set_paused(false)
	check(await fight_until(func(): return s.stat_arrows_fired > arrows0 + 20, 1200), "archers loose volleys (%d arrows)" % (s.stat_arrows_fired - arrows0))
	check(await fight_until(func(): return casualties(1) > cas0 + 3, 1500), "enemy casualties rise (%d)" % (casualties(1) - cas0))

	# --- cavalry: run round the flank, then charge an enemy missile unit
	var charges0 := s.stat_charges
	await set_paused(true)
	await set_paused(false)
	await fight_until(func(): return s.ended or (enemies("yumi") + enemies("teppo")).any(func(e): return _on_our_bank(e)), 1800)
	await set_paused(true)
	var mis: Array = (enemies("yumi") + enemies("teppo")).filter(func(e): return _on_our_bank(e))
	if mis.is_empty():
		mis = enemies("yumi") + enemies("teppo")
	var aim: Vector2 = (nearest(cav[0].mean_pos, mis).mean_pos if not mis.is_empty() else ford)
	var flank := Vector2(aim.x - 150.0, aim.y - 520.0 if aim.y > 1300.0 else aim.y + 520.0)
	await select_regs(cav)
	await ensure_visible([flank])
	await double_click(to_screen(flank), MOUSE_BUTTON_RIGHT)
	orders += 1
	check(cav.all(func(r): return r.running), "double-RMB sends the cavalry at the run")
	await set_paused(false)
	await frames(60)
	var missiles: Array = enemies("yumi") + enemies("teppo")
	missiles = missiles.filter(func(e): return _on_our_bank(e))
	var mt := nearest(cav[0].mean_pos, missiles if not missiles.is_empty() else enemies())
	if mt != null:
		await set_paused(true)
		await attack_with(cav, mt, true)
		await set_paused(false)
	check(await fight_until(func(): return s.stat_charges > charges0, 1800), "cavalry charge lands (%d impacts)" % (s.stat_charges - charges0))

	# --- spears & samurai close and attack
	await fight_until(func(): return s.ended or enemies().any(func(e): return _on_our_bank(e) and not e.is_mounted() and _closest_enemy_dist(line) < 300.0), 3000)
	await set_paused(true)
	var near_foes: Array = enemies().filter(func(e): return _on_our_bank(e))
	if not near_foes.is_empty():
		# each regiment of the line takes the enemy in front of it (no blob on one target)
		var engaged_any := false
		for r in line:
			var f := nearest(r.mean_pos, near_foes)
			if f.mean_pos.distance_to(r.mean_pos) < 450.0:
				await attack_with([r], f)
				engaged_any = true
		if not engaged_any:
			await attack_with([line[0]], nearest(line[0].mean_pos, near_foes))
	await set_paused(false)
	check(await fight_until(func(): return line.any(func(r): return r.engaged > 0), 1500), "melee engaged")

	# --- hotkeys (on the gunners, or whichever regiment still stands)
	var hk: Array = own("teppo") + own("yumi") + own()
	if not hk.is_empty():
		var g: Regiment = hk[0]
		await set_paused(true)
		await select_regs([g])
		var f0 := g.fire_at_will
		await key(KEY_F)
		check(g.fire_at_will != f0, "F toggles fire at will")
		await key(KEY_F)
		var r0 := g.running
		await key(KEY_R)
		check(g.running != r0, "R toggles run")
		await key(KEY_R)
		await key(KEY_H)
		check(g.is_idle(), "H halts")
		await set_paused(false)

	# --- fight it out at x3 with a simple competent doctrine
	await _set_speed(3.0)
	var tick := 0
	while not s.ended:
		await frames(30)
		tick += 1
		if s.ended:
			break
		if tick % 10 == 0:
			log_line("E2E INFO t=%.0fs standing %s vs %s" % [s.time, s.team_strength(0), s.team_strength(1)])
		await _doctrine_tick()
		await spectate()
	await _end_of_battle(t_begin)


## Like wait_until, but keeps commanding the army (doctrine) every second of game time.
func fight_until(cond: Callable, max_frames: int) -> bool:
	var k := 0
	while k < max_frames:
		if cond.call():
			return true
		if sim() == null or sim().ended:
			return cond.call()
		await frames(10)
		k += 10
		if k % 30 == 0:
			await _doctrine_tick()
			await spectate()
	return cond.call()


var _last_order := {}   # regiment id -> sim time of our last doctrine order

func _doctrine_tick() -> void:
	var plan: Array = _doctrine().filter(func(e): return sim().time - float(_last_order.get(e[0].id, -99.0)) > 10.0)
	if plan.is_empty():
		return
	for e in plan:
		_last_order[e[0].id] = sim().time
	await set_paused(true)
	glide = 6
	for e in plan:
		if e[0].is_out():
			continue
		if e[1] is String:
			await select_regs([e[0]])
			await key(KEY_H)
			orders += 1
		elif e[1] is Vector2:
			await select_regs([e[0]])
			await ensure_visible([e[1], e[0].mean_pos])
			await click(to_screen(e[1]), MOUSE_BUTTON_RIGHT)
			orders += 1
		elif not e[1].is_out():
			await attack_with([e[0]], e[1], e[2] if e.size() > 2 else e[0].is_mounted())
	glide = 12
	await set_paused(false)


func _end_of_battle(t_begin: float) -> void:
	var s := sim()
	var dur := s.time - t_begin
	check(s.ended and s.winner == 0, "victory for the player (winner %d)" % s.winner)
	var lines: Array = []
	for r in s.regiments:
		lines.append("E2E REG %d %-8s kills %3d lost %3d/%d %s" % [r.team, r.type_key, r.kills, r.initial_men - r.alive, r.initial_men, r.morale_name()])
	lines.append("E2E SUMMARY duration %.0f s game time | Hino lost %d/%d | Mizuno lost %d/%d | orders issued %d" % [
		dur, casualties(0), s.team_strength(0).y, casualties(1), s.team_strength(1).y, orders])
	var shown := await wait_until(func(): return _result_visible(), 300)
	check(shown, "result screen visible")
	await frames(120)
	for l in lines:
		log_line(l)
	# results scroll -> Main Menu -> title
	var ok_btn := await wait_until(func():
		var b := find_control("MenuButton")
		return b != null and b.is_visible_in_tree(), 600)
	if check(ok_btn, "results scroll offers Main Menu"):
		await frames(45)
		await click(find_control("MenuButton").get_global_rect().get_center())
		check(await wait_until(func():
			var t := find_control("BattlesButton")
			return t != null and t.is_visible_in_tree(), 600), "back on the title screen")
		await frames(60)


## Orders worth giving now: [[own regiment, enemy regiment], ...]. Missiles shoot what is in
## range, spears hold braced and only meet infantry that reaches them, samurai hit enemies
## already locked in melee, cavalry hunt missiles, routers and engaged enemies; once the enemy is
## clearly beaten everyone pursues.
func _doctrine() -> Array:
	var s := sim()
	var out: Array = []
	var mine := s.team_strength(0).x
	var theirs := s.team_strength(1).x
	var their_melee := 0
	for e in enemies():
		if not e.is_ranged():
			their_melee += e.alive
	# press the advantage: clearly ahead, or the enemy is down to skirmishers
	var pursue := theirs * 2 < mine or (their_melee * 3 < theirs and mine > theirs) or (mine > theirs * 1.3 and their_melee < 80)
	if _assault:
		pursue = true
	var foes := enemies()
	var all_foes := foes
	if not pursue:
		foes = foes.filter(func(e): return _on_our_bank(e))
	if all_foes.is_empty():
		return out
	for r in own():
		if r.type == UnitTypes.GENERAL:
			continue
		var cur := r.target()
		if r.is_ranged() and cur != null and not pursue and cur.mean_pos.distance_to(r.mean_pos) > r.get_range() * 1.05:
			out.append([r, "halt"])   # don't chase kiting archers across the river
			continue
		if cur != null and not cur.is_out() and not cur.is_routing():
			continue
		if r.engaged > 0:
			continue
		var e := nearest(r.mean_pos, foes)
		var d := INF if e == null else r.mean_pos.distance_to(e.mean_pos)
		var want: Regiment = null
		if pursue:
			want = e
		elif r.is_ranged() and foes.any(func(f): return not f.is_ranged() and f.mean_pos.distance_to(r.mean_pos) < 230.0) \
				and r.mean_pos.x > _line_x() - 60.0:
			out.append([r, Vector2(_line_x() - 170.0, r.mean_pos.y)])
			continue
		elif r.is_ranged() and r.is_idle() and r.mean_pos.x < _line_x() - 60.0 \
				and not foes.any(func(f): return not f.is_ranged() and f.mean_pos.distance_to(r.mean_pos) < 450.0):
			# the melee threat has passed: step back out in front of the line to answer their bows
			out.append([r, Vector2(_line_x() + 210.0, r.mean_pos.y)])
			continue
		elif r.is_ranged() and r.under_fire_t < 2.0 and not pursue:
			# losing an archery duel (outnumbered by bows in range): step back out of their reach
			var their_bows: Array = all_foes.filter(func(f): return f.is_ranged() and f.mean_pos.distance_to(r.mean_pos) < f.get_range() + 40.0)
			var their_n := 0
			for f in their_bows:
				their_n += f.alive
			if their_n > r.alive * 1.4:
				var sh2 := nearest(r.mean_pos, their_bows)
				out.append([r, r.mean_pos + (r.mean_pos - sh2.mean_pos).normalized() * 260.0])
				continue
			var inr2: Array = all_foes.filter(func(f): return f.mean_pos.distance_to(r.mean_pos) < r.get_range() * 0.95)
			if not inr2.is_empty() and cur == null:
				want = nearest(r.mean_pos, inr2)
		elif r.is_ranged():
			var inr: Array = all_foes.filter(func(f): return f.mean_pos.distance_to(r.mean_pos) < r.get_range() * 0.95)
			# shoot what stands still (dense, static blocks): kiting skirmishers are a waste of arrows
			var still: Array = inr.filter(func(f): return f.avg_speed < 15.0)
			if not still.is_empty():
				want = nearest(r.mean_pos, still)
			elif not inr.is_empty():
				want = nearest(r.mean_pos, inr)
		elif not r.is_mounted() and not r.is_ranged() and r.under_fire_t < 2.5 and not foes.any(func(f): return not f.is_ranged() and f.mean_pos.distance_to(r.mean_pos) < 320.0):
			# being shot at with no enemy infantry close: rush the archers
			var shooters: Array = foes.filter(func(f): return f.is_ranged() and f.mean_pos.distance_to(r.mean_pos) < 800.0)
			if not shooters.is_empty():
				want = nearest(r.mean_pos, shooters)
		elif DODGE and r.type_key == "yari" and r.under_fire_t < 2.0 and d > 380.0 and r.is_idle():
			var sh := nearest(r.mean_pos, all_foes.filter(func(f): return f.is_ranged()))
			if sh != null and sh.mean_pos.distance_to(r.mean_pos) < sh.get_range() + 60.0:
				var away := (r.mean_pos - sh.mean_pos).normalized()
				out.append([r, r.mean_pos + away * 220.0])
				continue
		elif r.type_key == "yari":
			var busy_y: Array = foes.filter(func(f): return f.engaged > 0 and f.mean_pos.distance_to(r.mean_pos) < 450.0)
			if d < 170.0 and not e.is_mounted():
				want = e
			elif not busy_y.is_empty():
				want = nearest(r.mean_pos, busy_y)   # help the neighbours already fighting
		elif r.type_key == "samurai":
			var busy: Array = foes.filter(func(f): return f.engaged > 0 and f.mean_pos.distance_to(r.mean_pos) < 500.0)
			if not busy.is_empty():
				want = nearest(r.mean_pos, busy)
			elif d < 200.0:
				want = e
		elif r.is_mounted() and foes.any(func(f): return f.type == UnitTypes.GENERAL and f.mean_pos.distance_to(r.mean_pos) < 1000.0):
			want = foes.filter(func(f): return f.type == UnitTypes.GENERAL)[0]   # go for their general
		elif r.is_mounted():
			var soft: Array = foes.filter(func(f): return (f.is_ranged() or f.engaged > 0) and f.mean_pos.distance_to(r.mean_pos) < 900.0)
			if not soft.is_empty():
				want = nearest(r.mean_pos, soft)
		if want != null and want != cur:
			# run down skirmishers and routers; walk into formed lines
			out.append([r, want, r.is_mounted() or want.is_ranged() or want.is_routing() or pursue])
	return out


func _line_x() -> float:
	var xs := 0.0
	var n := 0
	for r in own("yari") + own("samurai"):
		xs += r.mean_pos.x
		n += 1
	return xs / maxf(1, n)


func _result_visible() -> bool:
	if get_tree().root.find_child("Results*", true, false) != null:
		var n := get_tree().root.find_child("Results*", true, false)
		if n is CanvasItem and n.is_visible_in_tree():
			return true
		if n is CanvasLayer and n.visible:
			return true
	var b := battle()
	return b != null and b.result_label != null and b.result_label.visible



# =====================================================================================
#  Scenario: tenmoku (uphill assault on a defended ridge, flank by the woodcutters' track)
# =====================================================================================

func _scenario_tenmoku() -> void:
	await frames(30)
	if sim() == null and find_control("BattlesButton") != null:
		await _menu_flow("CardTenmoku")
	if not check(await wait_until(func(): return sim() != null, 900), "battle scene loaded"):
		return
	var s := sim()
	var m: MapDef = battle().map
	check(m.map_name == "tenmoku", "Tenmoku Pass loaded (%s)" % m.map_name)
	var throat: Vector2 = m.ai_hints.get("pass", Vector2(2420, 1620))
	var track: Vector2 = m.ai_hints.get("south_track", Vector2(3300, 2380))
	_ford = throat + Vector2(320, 0)
	await frames(20)
	check(s.deploying, "battle opens in deployment")
	var zone: Rect2 = s.deploy_zones[0]
	await _deploy_army(zone)
	var begin := find_control("BeginBattleButton")
	if begin != null and begin.is_visible_in_tree():
		await click(begin.get_global_rect().get_center())
	if s.deploying:
		await key(KEY_ENTER)
	check(not s.deploying, "battle begins")
	var t_begin := s.time
	await _set_speed(3.0)

	# main body to the mouth of the Throat, out of bow range of the ridge
	var line: Array = own("yari") + own("samurai").slice(0, 1)
	var screen: Array = own("yumi") + own("teppo")
	var flankers: Array = own("cavalry") + own("samurai").slice(1)
	await set_paused(true)
	var span := 0.0
	for r in line:
		span += r.width() + 30.0
	var hold_x := throat.x - 420.0
	await line_move(line, Vector2(hold_x, throat.y - span * 0.5), Vector2(hold_x, throat.y + span * 0.5))
	await line_move(screen, Vector2(hold_x + 110.0, throat.y - 330.0), Vector2(hold_x + 110.0, throat.y + 330.0))
	await line_move(own("general"), Vector2(hold_x - 200.0, throat.y - 40.0), Vector2(hold_x - 200.0, throat.y + 40.0))
	# flanking column down the woodcutters' track (shift-RMB queues the waypoints)
	await select_regs(flankers)
	for wp in [Vector2(1650, 2250), Vector2(2150, 2560), Vector2(2750, 2620), track - Vector2(150, -40)]:
		await ensure_visible([wp], 240)
		await click(to_screen(wp), MOUSE_BUTTON_RIGHT, true)
		orders += 1
	check(flankers.all(func(r): return r.orders.size() >= 3), "flank column queued along the south track (shift-RMB)")
	await set_paused(false)
	check(await fight_until(func(): return s.ended or flankers.all(func(r): return r.is_out() or r.is_idle()), 4000),
		"flankers reach the ridge's right flank")
	check(s.stat_arrows_fired > 0, "skirmish under way (%d arrows)" % s.stat_arrows_fired)

	# assault: the main body storms the Throat as the flankers hit the line's end
	_assault = true
	await set_paused(true)
	for r in flankers:
		if not r.is_out():
			var tgt := nearest(r.mean_pos, enemies("yumi") + enemies("teppo") + enemies("general"))
			if tgt == null:
				tgt = nearest(r.mean_pos, enemies())
			if tgt != null:
				await attack_with([r], tgt, true)
	for r in line:
		if not r.is_out():
			var t2 := nearest(r.mean_pos, enemies())
			if t2 != null:
				await attack_with([r], t2)
	await set_paused(false)
	check(await fight_until(func(): return own().any(func(r): return r.engaged > 0) or s.ended, 3000), "assault reaches the enemy line")
	while not s.ended:
		await frames(30)
		await _doctrine_tick()
		await spectate()
	await _end_of_battle(t_begin)



# =====================================================================================
#  Scenario: showcase (AI vs AI, "director" camera, HUD hidden). Not input-driven: the
#  director moves the camera directly for smooth dollies. ~90 s of video.
# =====================================================================================

var _events: Array = []   # [priority, world pos, kind, sim time]

func _scenario_showcase() -> void:
	if not check(await wait_until(func(): return sim() != null, 900), "battle scene loaded"):
		return
	var s := sim()
	_cursor.visible = false
	var hud := get_tree().current_scene.get_node_or_null("Hud")
	if hud != null:
		hud.visible = false
	var dbg := get_tree().current_scene.get_node_or_null("DebugHud")
	if dbg != null:
		dbg.visible = false
	# a second AIGeneral commands the Hino
	var ai0 := AIGeneral.new()
	ai0.sim = s
	ai0.team = 0
	ai0.verbose = false
	get_tree().current_scene.add_child(ai0)
	s.volley.connect(func(p, kind): _events.append([2.0 if kind == "gun" else 1.0, p, kind, s.time]))
	s.charge_impact.connect(func(p, st): if st > 2.0: _events.append([3.0 + st * 0.05, p, "charge", s.time]))
	s.regiment_routed.connect(func(r): _events.append([1.5, r.mean_pos, "rout", s.time]))
	s.melee_contact.connect(func(p): _events.append([2.5, p, "contact", s.time]))
	var c := cam() as BattleCamera
	c.edge_pan = false
	var mid := Vector2.ZERO
	for r in s.regiments:
		mid += r.mean_pos
	mid /= s.regiments.size()
	# shot 1: deployment overview, slow push-in
	await _dolly(mid + Vector2(-500, 0), 0.5, mid + Vector2(-250, 0), 0.62, 150)
	s.begin_battle()
	s.time_scale = 2.0
	# shot 2: follow the first advance at the lines
	var own_mid := Vector2.ZERO
	for r in own():
		own_mid += r.mean_pos
	own_mid /= own().size()
	await _dolly(own_mid, 0.9, own_mid + Vector2(250, 0), 1.4, 150)
	var shots := 0
	var shot_end := 0
	var cur_target := c.position
	var cur_zoom := 1.4
	while not s.ended and shots < 40:
		var best: Array = []
		for e in _events:
			if s.time - float(e[3]) < 5.0 and (best.is_empty() or e[0] > best[0]):
				best = e
		_events = _events.filter(func(e): return s.time - float(e[3]) < 5.0)
		var tgt: Vector2 = best[1] if not best.is_empty() else hotspot()
		var z := 1.5
		if not best.is_empty():
			match best[2]:
				"charge": z = 2.1
				"contact": z = 1.8
				"gun": z = 1.9
				"rout": z = 1.5
				_: z = 1.6
		s.time_scale = 1.0 if (not best.is_empty() and best[2] in ["charge", "contact", "gun"]) else 2.2
		await _dolly(cur_target, cur_zoom, tgt, z, 45)
		cur_target = tgt
		cur_zoom = z
		# hold and drift gently with the action
		for k in 75:
			var drift := cur_target.lerp(hotspot(), 0.004 * k)
			c.focus_on(drift, cur_zoom)
			await get_tree().process_frame
			if s.ended:
				break
		shots += 1
		_events.clear()
	check(s.ended, "battle reached a result (winner %d)" % s.winner)
	s.time_scale = 1.0
	if hud != null:
		hud.visible = true
	await _dolly(c.position, c.zoom.x, hotspot(), 1.1, 60)
	check(await wait_until(func(): return _result_visible(), 300), "victory banner / results shown")
	await frames(150)


## Smooth camera move (ease in/out) from a/za to b/zb over n frames.
func _dolly(a: Vector2, za: float, b: Vector2, zb: float, n: int) -> void:
	var c := cam() as BattleCamera
	for k in range(1, n + 1):
		var t := float(k) / n
		t = t * t * (3.0 - 2.0 * t)
		c.focus_on(a.lerp(b, t), lerpf(za, zb, t))
		await get_tree().process_frame

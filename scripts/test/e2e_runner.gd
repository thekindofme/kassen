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
## Extra args: --e2e_timeout=<frames> (default 30000).

const SAFE_BATTLE := Rect2(150, 150, 1450, 640)   # screen area free of HUD panels (viewport coords)
const SAFE_DEPLOY := Rect2(150, 300, 1450, 490)   # below the deployment banner

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
	_timeout = int(args.get("e2e_timeout", 30000))
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
	match scenario:
		"full_battle":
			await _scenario_full_battle()
		"smoke_input":
			await _scenario_smoke_input()
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
func reg_point(r: Regiment) -> Vector2:
	var s := sim()
	var best := -1
	var bd := INF
	var spos := s.pos
	var st := s.state
	for i in r.soldiers:
		if st[i] < BattleSim.DEAD:
			var d := spos[i].distance_squared_to(r.mean_pos)
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


func click(p: Vector2, btn := MOUSE_BUTTON_LEFT, shift := false, n := 12) -> void:
	await move(p, n)
	_button(btn, true, false, shift)
	await frames(2)
	_button(btn, false, false, shift)
	await frames(2)


func double_click(p: Vector2, btn := MOUSE_BUTTON_LEFT, n := 12) -> void:
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
func ensure_visible(pts: Array, max_frames := 360) -> bool:
	var SAFE := SAFE_DEPLOY if (sim() != null and sim().deploying) else SAFE_BATTLE
	for attempt in max_frames / 6:
		var rect := Rect2(to_screen(pts[0]), Vector2.ZERO)
		for p in pts:
			rect = rect.expand(to_screen(p))
		rect = rect.grow(30)
		if SAFE.encloses(rect):
			return true
		if rect.size.x > SAFE.size.x or rect.size.y > SAFE.size.y:
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
		for k in keys:
			_key_state(k, true)
		await frames(6)
		for k in keys:
			_key_state(k, false)
	await frames(10)   # let the camera smoothing settle
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
	await ensure_visible(pts)
	var first := true
	for r in regs:
		await click(to_screen(reg_point(r)), MOUSE_BUTTON_LEFT, not first)
		first = false


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
	if sim().paused != on:
		await key(KEY_SPACE)


func casualties(team: int) -> int:
	var c := 0
	for r in sim().regiments_of(team):
		c += r.initial_men - r.alive
	return c


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
	await click(to_screen(reg_point(y[0])))
	check(c.selected.size() == 2, "clicking a grouped regiment selects the group")
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

func _scenario_full_battle() -> void:
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
	check(c.selected.has(a) and c.selected.has(b), "box-select picks two regiments (%d selected)" % c.selected.size())
	var zone: Rect2 = s.deploy_zones[0]
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
	var begin := find_control("BeginBattleButton")
	if begin != null and begin.is_visible_in_tree():
		await click(begin.get_global_rect().get_center())
	if s.deploying:
		await key(KEY_ENTER)
	check(not s.deploying, "battle begins")

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

	# --- dress the battle line a little forward, on the gentle rise, and let the enemy come
	var lx := 0.0
	for r in line:
		lx = maxf(lx, r.mean_pos.x)
	var front_x := lx + 140.0
	var span := 0.0
	for r in line:
		span += r.width() + 30.0
	await line_move(line, Vector2(front_x, ford.y - span * 0.5), Vector2(front_x, ford.y + span * 0.5))
	check(line.all(func(r): return not r.is_idle()), "battle line advances (RMB-drag)")
	# archers right behind the line so they can answer the enemy bows
	var bmid := Vector2(front_x - 85.0, (line[0].mean_pos.y + line[line.size() - 1].mean_pos.y) * 0.5)
	await line_move(bows, bmid - Vector2(0, 330), bmid + Vector2(0, 330))
	await _set_speed(3.0)
	await wait_until(func(): return _closest_enemy_dist(bows) < 620.0 or s.ended, 3000)

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
	check(await wait_until(func(): return s.stat_arrows_fired > arrows0 + 20, 1200), "archers loose volleys (%d arrows)" % (s.stat_arrows_fired - arrows0))
	check(await wait_until(func(): return casualties(1) > cas0 + 3, 1500), "enemy casualties rise (%d)" % (casualties(1) - cas0))

	# --- cavalry: run round the flank, then charge an enemy missile unit
	var charges0 := s.stat_charges
	await set_paused(true)
	var mis: Array = enemies("yumi") + enemies("teppo")
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
	var mt := nearest(cav[0].mean_pos, missiles if not missiles.is_empty() else enemies())
	if mt != null:
		await set_paused(true)
		await attack_with(cav, mt, true)
		await set_paused(false)
	check(await wait_until(func(): return s.stat_charges > charges0, 1800), "cavalry charge lands (%d impacts)" % (s.stat_charges - charges0))

	# --- spears & samurai close and attack
	await wait_until(func(): return s.ended or enemies().any(func(e): return _on_our_bank(e) and not e.is_mounted() and _closest_enemy_dist(line) < 300.0), 3000)
	await set_paused(true)
	var near_foes: Array = enemies().filter(func(e): return _on_our_bank(e))
	var foe := nearest(line[0].mean_pos, near_foes) if not near_foes.is_empty() else null
	if foe != null:
		await attack_with(line, foe)
	await set_paused(false)
	check(await wait_until(func(): return line.any(func(r): return r.engaged > 0), 1500), "melee engaged")

	# --- hotkeys on the gunners
	if not guns.is_empty():
		var g: Regiment = guns[0]
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
		var plan := _doctrine()
		if plan.is_empty():
			continue
		await set_paused(true)
		for e in plan:
			if not e[0].is_out() and not e[1].is_out():
				await attack_with([e[0]], e[1], e[0].is_mounted())
		await set_paused(false)
	var dur := s.time - t_begin
	check(s.ended and s.winner == 0, "victory for the player (winner %d)" % s.winner)
	var shown := await wait_until(func(): return _result_visible(), 300)
	check(shown, "result screen visible")
	await frames(90)
	log_line("E2E SUMMARY duration %.0f s game time | Hino lost %d/%d | Mizuno lost %d/%d | orders issued %d" % [
		dur, casualties(0), s.team_strength(0).y, casualties(1), s.team_strength(1).y, orders])


## Orders worth giving now: [[own regiment, enemy regiment], ...]. Missiles shoot what is in
## range, spears hold braced and only meet infantry that reaches them, samurai hit enemies
## already locked in melee, cavalry hunt missiles, routers and engaged enemies; once the enemy is
## clearly beaten everyone pursues.
func _doctrine() -> Array:
	var s := sim()
	var out: Array = []
	var mine := s.team_strength(0).x
	var theirs := s.team_strength(1).x
	var pursue := theirs * 2 < mine
	var foes := enemies()
	if not pursue:
		foes = foes.filter(func(e): return _on_our_bank(e))
	if foes.is_empty():
		return out
	for r in own():
		if r.type == UnitTypes.GENERAL:
			continue
		var cur := r.target()
		if cur != null and not cur.is_out() and not cur.is_routing():
			continue
		if r.engaged > 0:
			continue
		var e := nearest(r.mean_pos, foes)
		var d := r.mean_pos.distance_to(e.mean_pos)
		var want: Regiment = null
		if pursue:
			want = e
		elif r.is_ranged():
			var inr: Array = foes.filter(func(f): return f.mean_pos.distance_to(r.mean_pos) < r.get_range() * 0.95)
			var mis2: Array = inr.filter(func(f): return f.is_ranged())
			if not mis2.is_empty():
				want = nearest(r.mean_pos, mis2)
			elif not inr.is_empty():
				want = nearest(r.mean_pos, inr)
		elif r.type_key == "yari":
			if d < 170.0 and not e.is_mounted():
				want = e
		elif r.type_key == "samurai":
			var busy: Array = foes.filter(func(f): return f.engaged > 0 and f.mean_pos.distance_to(r.mean_pos) < 500.0)
			if not busy.is_empty():
				want = nearest(r.mean_pos, busy)
			elif d < 200.0:
				want = e
		elif r.is_mounted():
			var soft: Array = foes.filter(func(f): return (f.is_ranged() or f.engaged > 0) and f.mean_pos.distance_to(r.mean_pos) < 900.0)
			if not soft.is_empty():
				want = nearest(r.mean_pos, soft)
		if want != null and want != cur:
			out.append([r, want])
	return out


func _result_visible() -> bool:
	if get_tree().root.find_child("Results*", true, false) != null:
		var n := get_tree().root.find_child("Results*", true, false)
		if n is CanvasItem and n.is_visible_in_tree():
			return true
		if n is CanvasLayer and n.visible:
			return true
	var b := battle()
	return b != null and b.result_label != null and b.result_label.visible

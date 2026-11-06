class_name PlaceholderAI
extends Node
## Stand-in enemy commander so battles resolve until the real AIGeneral (scripts/ai/ai_general.gd)
## lands. Uses only the public Regiment order API, on a 0.5 s think tick:
##   - waits `start_delay`, then every regiment attacks the nearest enemy regiment
##     (ranged units walk into range and shoot; melee units close and charge),
##   - the general follows behind the army's centre and only joins against routers.

var sim: BattleSim
var team := 1
var start_delay := 3.0
var think_interval := 0.5
var _t := 0.0
var _started := false


func _process(delta: float) -> void:
	if sim == null or sim.paused or sim.ended:
		return
	_t += delta * sim.time_scale
	if _t < think_interval:
		return
	_t = 0.0
	if sim.time < start_delay:
		return
	think()


func think() -> void:
	var mine := sim.regiments_of(team)
	var enemies: Array[Regiment] = []
	for e in sim.enemies_of(team):
		if not e.is_out():
			enemies.append(e)
	if enemies.is_empty():
		return
	var centre := Vector2.ZERO
	var cnt := 0
	for r in mine:
		if not r.is_broken() and r.type != UnitTypes.GENERAL:
			centre += r.mean_pos
			cnt += 1
	if cnt > 0:
		centre /= cnt
	for r in mine:
		if r.is_broken() or r.withdrawn:
			continue
		if r.type == UnitTypes.GENERAL:
			_general(r, centre, enemies)
			continue
		var cur := r.target()
		if cur != null and not cur.is_out() and not (cur.is_routing() and not r.is_mounted()):
			continue
		if not r.is_idle() and cur == null and r.current_order().get("type", -1) == Regiment.Order.MOVE:
			continue
		var best: Regiment = null
		var best_d := INF
		for e in enemies:
			if e.is_routing() and not r.is_mounted():
				continue
			var d := r.mean_pos.distance_to(e.mean_pos)
			if d < best_d:
				best_d = d
				best = e
		if best != null:
			r.order_attack(best, false)


func _general(g: Regiment, centre: Vector2, enemies: Array[Regiment]) -> void:
	# finish nearby routers, otherwise stay ~300 px behind the line
	for e in enemies:
		if e.is_routing() and e.mean_pos.distance_to(g.mean_pos) < 400.0:
			if g.target() != e:
				g.order_attack(e, true)
			return
	if g.target() != null:
		return
	var home: Vector2 = sim.home_dir(team)
	var want := centre + home * 300.0
	if g.is_idle() and g.mean_pos.distance_to(want) > 150.0:
		g.order_move(want, -home)

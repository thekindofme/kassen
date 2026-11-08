extends Node
## Web builds only: publishes engine fps and battle sim time to `window.kassenStats` once a second,
## so browser-side tests can measure real performance of the WebAssembly build.

var _t := 0.0


func _ready() -> void:
	if not OS.has_feature("web"):
		set_process(false)


func _process(delta: float) -> void:
	_t += delta
	if _t < 1.0:
		return
	_t = 0.0
	var sim := get_tree().get_first_node_in_group("sim")
	var sim_time := -1.0
	var alive := -1
	if sim != null:
		sim_time = float(sim.get("time"))
		if sim.has_method("men_alive"):
			alive = int(sim.men_alive(0)) + int(sim.men_alive(1))
	JavaScriptBridge.eval("window.kassenStats={fps:%d,simTime:%.2f,alive:%d,ts:Date.now()}" % [Engine.get_frames_per_second(), sim_time, alive], true)

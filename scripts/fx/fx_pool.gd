class_name FxPool
extends RefCounted
## One MultiMeshInstance2D used as a ring buffer of FX instances (never one node per event).
## Particles: identity basis + spawn origin, written once at spawn, animated analytically in fx_particles.gdshader; expired
## slots are swept a few hundred per frame so the 64 s time wrap can never resurrect them.
## Decals: static quads (blood, mud, arrows, grass); when full the oldest is overwritten.

const STRIDE := 16      # TRANSFORM_2D (8) + colour (4) + custom (4)

var mmi: MultiMeshInstance2D
var cap := 0
var buf := PackedFloat32Array()
var t_end := PackedFloat32Array()
var head := 0
var used := 0
var dirty := false
var _sweep := 0
var _slots := PackedInt32Array()   # slots touched since the last flush (small batches go per-instance)
var _full := false


func _init(parent: Node, nm: String, p_cap: int, mat: Material, mesh: Mesh, world_size: Vector2) -> void:
	cap = p_cap
	buf.resize(cap * STRIDE)
	buf.fill(0.0)
	t_end.resize(cap)
	t_end.fill(-1.0)
	mmi = MultiMeshInstance2D.new()
	mmi.name = nm
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = cap
	mm.visible_instance_count = 0
	mm.custom_aabb = AABB(Vector3(-400, -400, -1), Vector3(world_size.x + 800, world_size.y + 800, 2))
	mmi.multimesh = mm
	mmi.material = mat
	parent.add_child(mmi)


## Particle spawn. `t0` = absolute sim time of birth (stored wrapped mod 64 for the shader).
func particle(p: Vector2, kind: int, layer: int, seed: float, life: float, v0: Vector2, t0: float, size: float) -> void:
	var o := head * STRIDE
	buf[o] = 1.0; buf[o + 1] = 0.0; buf[o + 2] = 0.0; buf[o + 3] = p.x
	buf[o + 4] = 0.0; buf[o + 5] = 1.0; buf[o + 6] = 0.0; buf[o + 7] = p.y
	buf[o + 8] = float(kind); buf[o + 9] = float(layer); buf[o + 10] = seed; buf[o + 11] = life
	buf[o + 12] = v0.x; buf[o + 13] = v0.y; buf[o + 14] = fposmod(t0, 64.0); buf[o + 15] = size
	t_end[head] = t0 + life
	_advance()


## Static decal: centred quad with basis axes `ax`, `ay` (size and rotation baked in).
func decal(p: Vector2, ax: Vector2, ay: Vector2, layer: int, tint: Color, sway := 0.0) -> void:
	# NB: Godot applies the instance transform after vertex(), so shaders work in quad-local space
	var o := head * STRIDE
	buf[o] = ax.x; buf[o + 1] = ay.x; buf[o + 2] = 0.0; buf[o + 3] = p.x
	buf[o + 4] = ax.y; buf[o + 5] = ay.y; buf[o + 6] = 0.0; buf[o + 7] = p.y
	buf[o + 8] = tint.r; buf[o + 9] = tint.g; buf[o + 10] = tint.b; buf[o + 11] = tint.a
	buf[o + 12] = float(layer); buf[o + 13] = sway; buf[o + 14] = fposmod(p.x * 0.05 + p.y * 0.03, TAU); buf[o + 15] = 0.0
	_advance()


func _advance() -> void:
	_touch(head)
	head += 1
	if head >= cap:
		head = 0
	used = mini(used + 1, cap)


func _touch(s: int) -> void:
	dirty = true
	if not _full:
		if _slots.size() >= 96:
			_full = true
		else:
			_slots.append(s)


## Kill expired particles (incrementally) and upload the buffer if anything changed.
func flush(now: float, sweep_particles: bool) -> void:
	if sweep_particles and used > 0:
		for q in mini(384, used):
			var s := _sweep
			_sweep += 1
			if _sweep >= used:
				_sweep = 0
			if t_end[s] >= 0.0 and t_end[s] < now:
				t_end[s] = -1.0
				buf[s * STRIDE + 11] = 0.0
				_touch(s)
	if not dirty:
		return
	dirty = false
	var mm := mmi.multimesh
	if mm.visible_instance_count != used:
		mm.visible_instance_count = used
	if _full:
		mm.buffer = buf
	else:
		var rid := mm.get_rid()
		for s in _slots:
			var o := s * STRIDE
			RenderingServer.multimesh_instance_set_transform_2d(rid, s, Transform2D(Vector2(buf[o], buf[o + 4]), Vector2(buf[o + 1], buf[o + 5]), Vector2(buf[o + 3], buf[o + 7])))
			RenderingServer.multimesh_instance_set_color(rid, s, Color(buf[o + 8], buf[o + 9], buf[o + 10], buf[o + 11]))
			RenderingServer.multimesh_instance_set_custom_data(rid, s, Color(buf[o + 12], buf[o + 13], buf[o + 14], buf[o + 15]))
	_slots.clear()
	_full = false

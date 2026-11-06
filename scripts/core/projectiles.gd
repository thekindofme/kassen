class_name Projectiles
extends RefCounted
## Arced arrows as struct-of-arrays. Ground position + height z (2.5D ballistics).
## Arrows land when z <= 0; the sim resolves the impact (no friendly fire for arcing arrows).

const GRAVITY := 520.0

var count := 0
var pos := PackedVector2Array()
var prev := PackedVector2Array()
var vel := PackedVector2Array()
var z := PackedFloat32Array()
var prev_z := PackedFloat32Array()
var vz := PackedFloat32Array()
var team := PackedInt32Array()
var reg := PackedInt32Array()
var dmg := PackedFloat32Array()


func _grow(cap: int) -> void:
	pos.resize(cap); prev.resize(cap); vel.resize(cap)
	z.resize(cap); prev_z.resize(cap); vz.resize(cap)
	team.resize(cap); reg.resize(cap); dmg.resize(cap)


## Launch from ground point `from` at height z0 so it lands on `to` after `flight` seconds.
func spawn(from: Vector2, z0: float, to: Vector2, flight: float, p_team: int, p_reg: int, p_dmg: float) -> void:
	if count >= pos.size():
		_grow(maxi(64, pos.size() * 2))
	var k := count
	count += 1
	pos[k] = from
	prev[k] = from
	vel[k] = (to - from) / flight
	z[k] = z0
	prev_z[k] = z0
	vz[k] = (0.5 * GRAVITY * flight * flight - z0) / flight
	team[k] = p_team
	reg[k] = p_reg
	dmg[k] = p_dmg


func update(dt: float, sim: Node) -> void:
	var k := 0
	while k < count:
		prev[k] = pos[k]
		prev_z[k] = z[k]
		pos[k] = pos[k] + vel[k] * dt
		vz[k] = vz[k] - GRAVITY * dt
		z[k] = z[k] + vz[k] * dt
		if z[k] <= 0.0:
			sim.arrow_impact(pos[k], team[k], reg[k], dmg[k], vel[k])
			_remove(k)
			continue
		k += 1


func _remove(k: int) -> void:
	var last := count - 1
	if k != last:
		pos[k] = pos[last]; prev[k] = prev[last]; vel[k] = vel[last]
		z[k] = z[last]; prev_z[k] = prev_z[last]; vz[k] = vz[last]
		team[k] = team[last]; reg[k] = reg[last]; dmg[k] = dmg[last]
	count = last

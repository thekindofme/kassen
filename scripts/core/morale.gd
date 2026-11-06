class_name MoraleRules
extends RefCounted
## Morale and fatigue rules (GDD §4 "Morale", "Fatigue"). Pure functions on a Regiment; the
## sim calls `tick()` once per regiment per sim tick and `state_for()` to map value → state.

const ROUT_BELOW := 12.0
const RALLY_AT := 40.0
const EAGER_AT := 75.0
const STEADY_AT := 40.0
const WAVERING_AT := ROUT_BELOW

const CASUALTY_SHOCK := 34.0        # losing every man costs this much on top of the extra below
const NEAR_ROUT_SHOCK := 8.0        # a friendly regiment within NEAR_ROUT_RADIUS routs
const NEAR_ROUT_RADIUS := 450.0
const GENERAL_DEATH_SHOCK := 25.0
const GUN_VOLLEY_SHOCK := 3.5       # teppo scare per volley received
const GUN_HIT_SHOCK := 0.6
const FLANK_HIT_SHOCK := 0.12
const REAR_HIT_SHOCK := 0.35


static func state_for(morale: float) -> int:
	if morale >= EAGER_AT:
		return Regiment.Morale.EAGER
	if morale >= STEADY_AT:
		return Regiment.Morale.STEADY
	return Regiment.Morale.WAVERING


static func attack_mult(r: Regiment) -> float:
	var m := 1.0
	if r.state == Regiment.Morale.EAGER:
		m = 1.06
	elif r.state == Regiment.Morale.WAVERING:
		m = 0.88
	return m * fatigue_attack_mult(r)


static func fatigue_attack_mult(r: Regiment) -> float:
	return 1.0 - 0.35 * clampf((r.fatigue - 0.4) / 0.6, 0.0, 1.0)


static func fatigue_speed_mult(r: Regiment) -> float:
	return 1.0 - 0.3 * clampf((r.fatigue - 0.5) / 0.5, 0.0, 1.0)


static func on_casualty(r: Regiment) -> void:
	var ratio := float(r.alive) / maxf(1.0, float(r.initial_men))
	var shock := CASUALTY_SHOCK / maxf(1.0, float(r.initial_men))
	if ratio < 0.5:
		shock *= 1.8
	r.morale -= shock
	r.losses_recent += 1.0


## Continuous morale + fatigue drift. `aura` = general's aura applies, `high` = holds high ground.
static func tick(r: Regiment, dt: float, aura: bool, high: bool) -> void:
	# fatigue
	var walk: float = r.stats["speed_walk"]
	if r.engaged * 5 > r.alive:
		r.fatigue += 0.0065 * dt
	elif r.avg_speed > walk * 1.5:
		r.fatigue += 0.011 * dt
	elif r.avg_speed > walk * 0.4:
		r.fatigue += 0.0012 * dt
	else:
		r.fatigue -= 0.012 * dt
	r.fatigue = clampf(r.fatigue, 0.0, 1.0)

	var decay := exp(-dt / 6.0)
	r.losses_recent *= decay
	r.kills_recent *= decay
	r.under_fire_t += dt

	if r.is_routing():
		return
	var d := 0.0
	if r.engaged > 0:
		if r.losses_recent > r.kills_recent * 1.5 + 1.0:
			d -= 1.0
		elif r.kills_recent > r.losses_recent * 1.3 + 0.6:
			d += 1.2
	if aura:
		d += 1.5
	if high:
		d += 0.3
	if r.fatigue > 0.8:
		d -= 0.5
	r.morale += d * dt
	var calm := r.engaged == 0 and r.under_fire_t > 4.0
	if calm:
		var ratio := float(r.alive) / maxf(1.0, float(r.initial_men))
		var cap: float = r.stats["morale_base"] * (0.55 + 0.45 * ratio) + (10.0 if aura else 0.0)
		if r.morale < cap:
			r.morale = minf(cap, r.morale + 2.5 * dt)
	r.morale = clampf(r.morale, 0.0, 100.0)
	r.state = state_for(r.morale)

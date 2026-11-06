class_name AudioDirector
extends Node
## KASSEN audio director.
##
## Add one instance to the battle scene (or as an autoload; it survives without a sim).
## It finds the BattleSim through group "sim" and subscribes to its signals. Everything is
## defensive (`has_signal`, `in` checks), so it also works while the sim is still changing.
##
## Design
##  * One-shots go through a fixed pool of AudioStreamPlayer2D voices (`sfx_voices`). Every request
##    passes a per-sound rate limiter (min gap + max concurrent) and a global per-frame budget,
##    then a priority/loudness voice stealer. Hundreds of fighting soldiers never create hundreds
##    of players: melee is aggregated per regiment cluster into a few looping "melee bed" voices
##    whose loudness follows the number of engaged men, with throttled clash one-shots on top.
##  * Panning is done by the 2D players against the current Camera2D (screen-space x, strength
##    `panning_strength`). Attenuation is ours: distance from the screen centre in units of the
##    visible half-extent (so it scales with zoom), plus a zoom term (zoomed-out = quieter, duller:
##    a low-pass on the SFX bus follows zoom).
##  * Music: three synchronised battle layers (deploy / battle / intense) always play together
##    and are crossfaded with equal-power weights from a smoothed battle-intensity value.
##    Menu theme and stingers use their own players.
##  * Ambience: wind, birds (fade out as the fighting grows) and river (follows camera proximity to
##    water when the terrain exposes `is_water(pos)`).
##
## Public API
##   set_phase(phase: String)            "menu" | "deploy" | "battle" | "victory" | "defeat"
##   play_ui(name: String)               "click" | "hover" | "back" | "select" | "confirm" | "order" |
##                                       "move" | "attack" | "error" | "open" | "close"
##   play_at(name, world_pos, vol_db := 0.0, pitch := 1.0, priority := 1) -> bool
##   play_global(name, vol_db := 0.0, bus := "SFX")     non-positional one-shot
##   set_intensity_override(v: float)    0..1, or -1 to return to automatic intensity
##   attach_sim(sim: Node)               normally automatic (group "sim")
##   get_intensity() -> float
## Buses: uses "Music", "SFX", "Ambience", "UI" (creates any that are missing at runtime, all
## sending to Master; SFX gets a zoom-driven low-pass and a compressor).

signal phase_changed(phase: String)

const Bank := preload("res://scripts/audio/audio_bank.gd")

const BUS_MUSIC := "Music"
const BUS_SFX := "SFX"
const BUS_AMB := "Ambience"
const BUS_UI := "UI"

## Per-sound playback rules. vol: base dB, gap: min seconds between starts, max: concurrent
## instances, pitch: random pitch range (+/-), prio: 0 (low) .. 3 (high), bus.
const RULES := {
	"sword_clash": {"vol": -6.0, "gap": 0.05, "max": 5, "pitch": 0.08, "prio": 1},
	"sword_hit": {"vol": -7.0, "gap": 0.06, "max": 4, "pitch": 0.08, "prio": 1},
	"spear_thrust": {"vol": -6.0, "gap": 0.07, "max": 4, "pitch": 0.07, "prio": 1},
	"armour_impact": {"vol": -8.0, "gap": 0.06, "max": 4, "pitch": 0.08, "prio": 1},
	"death_grunt": {"vol": -9.0, "gap": 0.13, "max": 3, "pitch": 0.08, "prio": 1},
	"bow_release": {"vol": -6.0, "gap": 0.05, "max": 3, "pitch": 0.06, "prio": 1},
	"bow_volley": {"vol": -3.0, "gap": 0.25, "max": 3, "pitch": 0.04, "prio": 2},
	"arrow_whoosh": {"vol": -5.0, "gap": 0.25, "max": 3, "pitch": 0.06, "prio": 2},
	"arrow_impact": {"vol": -9.0, "gap": 0.05, "max": 4, "pitch": 0.08, "prio": 0},
	"arrow_rain": {"vol": -4.0, "gap": 0.3, "max": 3, "pitch": 0.05, "prio": 2},
	"matchlock_shot": {"vol": -3.0, "gap": 0.06, "max": 4, "pitch": 0.05, "prio": 2},
	"matchlock_volley": {"vol": 0.0, "gap": 0.3, "max": 3, "pitch": 0.03, "prio": 3},
	"horse_whinny": {"vol": -6.0, "gap": 1.5, "max": 2, "pitch": 0.07, "prio": 1},
	"cavalry_charge_impact": {"vol": 0.0, "gap": 0.35, "max": 3, "pitch": 0.05, "prio": 3},
	"warcry": {"vol": -3.0, "gap": 1.2, "max": 2, "pitch": 0.04, "prio": 2},
	"rout_cry": {"vol": -4.0, "gap": 1.5, "max": 2, "pitch": 0.05, "prio": 2},
	"kachidoki": {"vol": 0.0, "gap": 3.0, "max": 1, "pitch": 0.0, "prio": 3},
	"horagai": {"vol": -1.0, "gap": 5.0, "max": 1, "pitch": 0.0, "prio": 3},
	"horagai_answer": {"vol": -4.0, "gap": 5.0, "max": 1, "pitch": 0.0, "prio": 3},
}

const UI_MAP := {
	"click": "ui_click", "hover": "ui_hover", "back": "ui_back", "close": "ui_back", "select": "ui_select",
	"open": "ui_select", "confirm": "order_confirm", "order": "order_confirm", "move": "order_confirm",
	"attack": "order_attack", "error": "ui_back",
}

const LAYERS := ["deploy", "battle", "intense"]

@export var player_team := 0
@export var sfx_voices := 28
@export var melee_bed_voices := 4
@export var march_voices := 3
@export var gallop_voices := 3
@export var max_starts_per_frame := 5
@export var panning_strength := 2.5
@export var music_db := -4.0
@export var ambience_db := -6.0
@export var debug_log := false
## When true the director moves deploy -> battle by itself once the sim clock runs (or, if the sim
## exposes a `deploying` bool, when it turns false). Turn off if the game calls set_phase itself.
@export var auto_phase := true

var phase := ""
var sim: Node = null

var _streams := {}            # name -> Array[AudioStream]
var _last_variant := {}       # name -> int (no immediate repeats)
var _last_start := {}         # name -> time (s)
var _voices: Array[AudioStreamPlayer2D] = []
var _voice_meta: Array[Dictionary] = []
var _ui_players: Array[AudioStreamPlayer] = []
var _ui_next := 0
var _global_players: Array[AudioStreamPlayer] = []
var _global_next := 0
var _starts_this_frame := 0

var _music := {}              # layer -> AudioStreamPlayer
var _music_w := {}            # layer -> current linear weight
var _music_target := {}       # layer -> target linear weight
var _menu_player: AudioStreamPlayer
var _menu_w := 0.0
var _menu_target := 0.0
var _stinger: AudioStreamPlayer
var _amb := {}                # name -> AudioStreamPlayer
var _amb_w := {}
var _amb_target := {}

class LoopVoice:
	var player: AudioStreamPlayer2D
	var target_db := -80.0
	var cur_db := -80.0
	var pos := Vector2.ZERO
	var key := -1            # what it is following (regiment id or cluster index)
	var pitch := 1.0

var _beds: Array[LoopVoice] = []
var _marches: Array[LoopVoice] = []
var _gallops: Array[LoopVoice] = []

var _time := 0.0
var _poll_t := 0.0
var _intensity := 0.0
var _intensity_raw := 0.0
var _intensity_override := -1.0
var _deaths_recent := 0.0     # decaying counters
var _volleys_recent := 0.0
var _contacts := []           # fallback melee heat when regiments are not readable: [pos, heat]
var _clusters := []           # [{pos, weight, kinds}]
var _clash_accum := 0.0
var _pending := []            # scheduled one-shots: [time, name, pos, vol_db]
var _water_near := 0.0
var _lp_effect: AudioEffectLowPassFilter
var _rng := RandomNumberGenerator.new()


# =============================================================================== setup
func _ready() -> void:
	_rng.randomize()
	_setup_buses()
	_load_bank()
	for i in sfx_voices:
		var p := AudioStreamPlayer2D.new()
		p.bus = BUS_SFX
		_configure_2d(p)
		add_child(p)
		_voices.append(p)
		_voice_meta.append({"name": "", "prio": -1, "base_db": -80.0, "start": -99.0})
	for i in 4:
		var u := AudioStreamPlayer.new()
		u.bus = BUS_UI
		add_child(u)
		_ui_players.append(u)
	for i in 4:
		var g := AudioStreamPlayer.new()
		g.bus = BUS_SFX
		add_child(g)
		_global_players.append(g)
	_beds = _make_loops(melee_bed_voices, "melee_loop")
	_marches = _make_loops(march_voices, "march_loop")
	_gallops = _make_loops(gallop_voices, "horse_gallop_loop")
	# music layers (started together so they stay sample-aligned)
	for l in LAYERS:
		var mp := AudioStreamPlayer.new()
		mp.bus = BUS_MUSIC
		mp.stream = _looped(_first("music_" + l))
		mp.volume_db = -80.0
		add_child(mp)
		_music[l] = mp
		_music_w[l] = 0.0
		_music_target[l] = 0.0
	_menu_player = AudioStreamPlayer.new()
	_menu_player.bus = BUS_MUSIC
	_menu_player.stream = _looped(_first("music_menu"))
	_menu_player.volume_db = -80.0
	add_child(_menu_player)
	_stinger = AudioStreamPlayer.new()
	_stinger.bus = BUS_MUSIC
	add_child(_stinger)
	for a in ["wind", "birds", "river"]:
		var ap := AudioStreamPlayer.new()
		ap.bus = BUS_AMB
		ap.stream = _looped(_first("amb_" + a))
		ap.volume_db = -80.0
		add_child(ap)
		_amb[a] = ap
		_amb_w[a] = 0.0
		_amb_target[a] = 0.0
	_try_attach()
	if phase == "":
		set_phase("deploy" if sim != null else "menu")


func _configure_2d(p: AudioStreamPlayer2D) -> void:
	p.attenuation = 0.0          # we attenuate ourselves (camera distance + zoom)
	p.max_distance = 1.0e7
	p.panning_strength = panning_strength
	p.max_polyphony = 1


func _make_loops(count: int, sound: String) -> Array[LoopVoice]:
	var out: Array[LoopVoice] = []
	var variants: Array = _streams.get(sound, [])
	for i in count:
		var lv := LoopVoice.new()
		lv.player = AudioStreamPlayer2D.new()
		lv.player.bus = BUS_SFX
		_configure_2d(lv.player)
		if variants.size() > 0:
			lv.player.stream = _looped(variants[i % variants.size()])
		lv.player.volume_db = -80.0
		add_child(lv.player)
		out.append(lv)
	return out


func _setup_buses() -> void:
	for b in [BUS_MUSIC, BUS_SFX, BUS_AMB, BUS_UI]:
		if AudioServer.get_bus_index(b) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, b)
			AudioServer.set_bus_send(idx, "Master")
	var sfx := AudioServer.get_bus_index(BUS_SFX)
	for i in AudioServer.get_bus_effect_count(sfx):
		var e := AudioServer.get_bus_effect(sfx, i)
		if e is AudioEffectLowPassFilter:
			_lp_effect = e
	if _lp_effect == null:
		_lp_effect = AudioEffectLowPassFilter.new()
		_lp_effect.cutoff_hz = 20000.0
		_lp_effect.resonance = 0.5
		AudioServer.add_bus_effect(sfx, _lp_effect, 0)
		var comp := AudioEffectCompressor.new()
		comp.threshold = -14.0
		comp.ratio = 3.0
		comp.attack_us = 3000.0
		comp.release_ms = 180.0
		AudioServer.add_bus_effect(sfx, comp)
	var master := AudioServer.get_bus_index("Master")
	if AudioServer.get_bus_effect_count(master) == 0:
		var lim := AudioEffectHardLimiter.new()
		lim.ceiling_db = -0.8
		AudioServer.add_bus_effect(master, lim)


func _load_bank() -> void:
	for sound_name in Bank.FILES:
		var arr: Array = []
		for path in Bank.FILES[sound_name]:
			if ResourceLoader.exists(path):
				var s: AudioStream = load(path)
				if s != null:
					arr.append(s)
			elif debug_log:
				push_warning("AudioDirector: missing %s" % path)
		_streams[sound_name] = arr


func _first(sound_name: String) -> AudioStream:
	var arr: Array = _streams.get(sound_name, [])
	return arr[0] if arr.size() > 0 else null


func _looped(s: AudioStream) -> AudioStream:
	if s == null:
		return null
	if "loop" in s:
		s.set("loop", true)
	return s


# =============================================================================== sim hookup
func _try_attach() -> void:
	if sim != null and is_instance_valid(sim):
		return
	var s := get_tree().get_first_node_in_group("sim") if is_inside_tree() else null
	if s != null:
		attach_sim(s)
		if phase in ["", "menu"]:
			set_phase("deploy")


func attach_sim(s: Node) -> void:
	if sim == s:
		return
	sim = s
	var hooks := {
		"soldier_died": _on_soldier_died,
		"regiment_routed": _on_regiment_routed,
		"regiment_rallied": _on_regiment_rallied,
		"melee_contact": _on_melee_contact,
		"volley": _on_volley,
		"charge_impact": _on_charge_impact,
		"battle_ended": _on_battle_ended,
		"general_killed": _on_general_killed,
		"battle_started": _on_battle_started,
		"deployment_started": _on_deployment_started,
		"projectile_hit": _on_projectile_hit,
	}
	for sig in hooks:
		if s.has_signal(sig) and not s.is_connected(sig, hooks[sig]):
			s.connect(sig, hooks[sig])
	if debug_log:
		print("AudioDirector attached to ", s.name)


func _sim_get(prop: String, default = null):
	if sim == null or not is_instance_valid(sim):
		return default
	var v = sim.get(prop)
	return default if v == null else v


# =============================================================================== public API
func set_phase(p: String) -> void:
	p = p.to_lower()
	if p == phase:
		return
	var prev := phase
	phase = p
	match p:
		"menu":
			_menu_target = 1.0
			if not _menu_player.playing and _menu_player.stream:
				_menu_player.play()
			_stop_layers_soft()
			_set_amb(0.0, 0.0, 0.0)
		"deploy":
			_menu_target = 0.0
			_start_layers()
			_set_layer_targets(1.0, 0.0, 0.0)
			_set_amb(1.0, 1.0, 1.0)
		"battle":
			_menu_target = 0.0
			_start_layers()
			_set_amb(1.0, 1.0, 1.0)
			if prev != "battle":
				play_global("horagai", 0.0, BUS_SFX)
				_schedule(4.2, "horagai_answer", Vector2.INF, 0.0)   # the enemy's conch answers
				_schedule(8.5, "warcry", Vector2.INF, 0.0)
		"victory", "defeat":
			_menu_target = 0.0
			_set_layer_targets(0.0, 0.0, 0.0)
			var st := _first("stinger_" + p)
			if st:
				_stinger.stream = st
				_stinger.volume_db = music_db + 1.0
				_stinger.play()
			if p == "victory":
				_schedule(2.2, "kachidoki", Vector2.INF, -2.0)
	phase_changed.emit(phase)


func play_ui(ui_name: String) -> void:
	var sound: String = UI_MAP.get(ui_name, ui_name)
	var s := _pick(sound)
	if s == null:
		s = _pick("ui_click")
	if s == null:
		return
	var p := _ui_players[_ui_next]
	_ui_next = (_ui_next + 1) % _ui_players.size()
	p.stream = s
	p.pitch_scale = 1.0 + _rng.randf_range(-0.03, 0.03)
	p.volume_db = -6.0 if sound == "ui_hover" else 0.0
	p.play()


## Non-positional one-shot (stingers, horagai, big global cues).
func play_global(sound: String, vol_db := 0.0, bus := BUS_SFX) -> void:
	var s := _pick(sound)
	if s == null:
		return
	var p := _global_players[_global_next]
	_global_next = (_global_next + 1) % _global_players.size()
	p.bus = bus
	p.stream = s
	var rule: Dictionary = RULES.get(sound, {})
	p.volume_db = vol_db + float(rule.get("vol", 0.0))
	p.pitch_scale = 1.0
	p.play()
	_last_start[sound] = _time


## Positional one-shot through the pooled, rate-limited voices. Returns true if it played.
func play_at(sound: String, world_pos: Vector2, vol_db := 0.0, pitch := 1.0, priority := -1) -> bool:
	var rule: Dictionary = RULES.get(sound, {})
	var gap := float(rule.get("gap", 0.05))
	if _time - float(_last_start.get(sound, -99.0)) < gap:
		return false
	if _starts_this_frame >= max_starts_per_frame:
		return false
	var maxc := int(rule.get("max", 4))
	var active := 0
	for i in _voices.size():
		if _voices[i].playing and _voice_meta[i]["name"] == sound:
			active += 1
	if active >= maxc:
		return false
	var base_db := float(rule.get("vol", 0.0)) + vol_db
	var heard := base_db + _spatial_db(world_pos)
	if heard < -42.0:
		return false
	var prio := priority if priority >= 0 else int(rule.get("prio", 1))
	var s := _pick(sound)
	if s == null:
		return false
	var vi := _find_voice(prio, heard)
	if vi < 0:
		return false
	var v := _voices[vi]
	v.stop()
	v.stream = s
	v.global_position = world_pos
	var pr := float(rule.get("pitch", 0.05))
	v.pitch_scale = pitch * (1.0 + _rng.randf_range(-pr, pr))
	v.volume_db = heard
	v.play()
	_voice_meta[vi] = {"name": sound, "prio": prio, "base_db": base_db, "start": _time}
	_last_start[sound] = _time
	_starts_this_frame += 1
	return true


func set_intensity_override(v: float) -> void:
	_intensity_override = v


func get_intensity() -> float:
	return _intensity


# =============================================================================== signal handlers
func _on_soldier_died(i: int) -> void:
	_deaths_recent += 1.0
	var p := _soldier_pos(i)
	if p == Vector2.INF:
		return
	# throttled: most deaths are silent, the bed carries the mass
	if _rng.randf() < 0.55:
		play_at("death_grunt", p, _rng.randf_range(-3.0, 0.0))
	if _rng.randf() < 0.6:
		play_at("armour_impact" if _rng.randf() < 0.5 else "sword_hit", p, -2.0)


func _on_regiment_routed(r) -> void:
	var p := _reg_pos(r)
	if p != Vector2.INF:
		play_at("rout_cry", p, 0.0, 1.0, 2)


func _on_regiment_rallied(r) -> void:
	var p := _reg_pos(r)
	if p != Vector2.INF:
		play_at("warcry", p, -4.0, 1.04, 2)


func _on_melee_contact(p: Vector2) -> void:
	_contacts.append([p, 1.0])
	play_at("warcry", p, -3.0, 1.0, 2)
	for k in 3:
		_schedule(_rng.randf_range(0.0, 0.35), ["sword_clash", "spear_thrust", "armour_impact"][k], p + _jitter(40.0), -2.0)


func _on_volley(p: Vector2, kind) -> void:
	_volleys_recent += 1.0
	var k := str(kind).to_lower()
	var shooter = _regiment_near(p)
	if k.begins_with("gun") or k.begins_with("teppo") or k == "2" or k.begins_with("match"):
		var few: bool = shooter != null and "alive" in shooter and int(shooter.alive) <= 6
		if few:
			for s in int(shooter.alive):
				_schedule(_rng.randf_range(0.0, 0.5), "matchlock_shot", p + _jitter(30.0), 0.0)
		else:
			play_at("matchlock_volley", p, 0.0, 1.0, 3)
	else:
		play_at("bow_volley", p, 0.0, 1.0, 2)
		var target_pos := _fire_target_pos(shooter)
		if target_pos != Vector2.INF:
			var d := p.distance_to(target_pos)
			var flight := clampf(d / 420.0, 0.7, 2.4)
			_schedule(0.15, "arrow_whoosh", p.lerp(target_pos, 0.45), 0.0)
			_schedule(flight, "arrow_rain", target_pos, 0.0)
		else:
			_schedule(0.15, "arrow_whoosh", p, -2.0)


func _on_projectile_hit(p: Vector2, _kind = null) -> void:
	play_at("arrow_impact", p)


func _on_charge_impact(p: Vector2, strength: float) -> void:
	var db := clampf(-6.0 + 3.0 * log(maxf(strength, 0.1)) / log(2.0), -9.0, 3.0)
	play_at("cavalry_charge_impact", p, db, 1.0, 3)
	if _rng.randf() < 0.45:
		_schedule(_rng.randf_range(0.05, 0.3), "horse_whinny", p + _jitter(30.0), db - 2.0)
	if _rng.randf() < 0.3:
		_schedule(0.2, "warcry", p, -4.0)


func _on_general_killed(team: int) -> void:
	var st := _first("stinger_general_fallen")
	if st and not _stinger.playing:
		_stinger.stream = st
		_stinger.volume_db = music_db
		_stinger.play()
	# the side that killed him cheers
	_schedule(1.0, "warcry", Vector2.INF, -2.0 if team != player_team else -6.0)


func _on_battle_ended(winner_team: int) -> void:
	set_phase("victory" if winner_team == player_team else "defeat")


func _on_battle_started() -> void:
	set_phase("battle")


func _on_deployment_started() -> void:
	set_phase("deploy")


# =============================================================================== per-frame
func _process(delta: float) -> void:
	_time += delta
	_starts_this_frame = 0
	if sim == null or not is_instance_valid(sim):
		sim = null
		if Engine.get_process_frames() % 30 == 0:
			_try_attach()
	_run_schedule()
	_poll_t -= delta
	if _poll_t <= 0.0:
		_poll_t = 0.2
		_poll_sim()
	_update_intensity(delta)
	_update_music(delta)
	_update_zoom_filter()
	_update_voice_levels()
	_update_loops(delta)
	_update_clash_oneshots(delta)
	_update_ambience(delta)


func _poll_sim() -> void:
	if auto_phase and phase == "deploy" and sim != null:
		var dep = sim.get("deploying")
		var started: bool = (not bool(dep)) if dep != null else float(_sim_get("time", 0.0)) > 1.5
		if started and not bool(_sim_get("ended", false)):
			set_phase("battle")
	_clusters.clear()
	var regs = _sim_get("regiments", [])
	var total_engaged := 0.0
	var moving_inf := []
	var moving_cav := []
	if regs is Array and regs.size() > 0:
		for r in regs:
			if r == null or not ("alive" in r) or int(r.alive) <= 0:
				continue
			var rp := _reg_pos(r)
			if rp == Vector2.INF:
				continue
			var engaged := float(r.engaged) if "engaged" in r else 0.0
			if engaged > 0.0:
				total_engaged += engaged
				_add_to_cluster(rp, engaged, r)
			var mounted := false
			if "stats" in r and r.stats is Dictionary:
				mounted = bool(r.stats.get("mounted", false))
			var moving := false
			if r.has_method("is_moving"):
				moving = r.is_moving()
			var routing: bool = r.has_method("is_routing") and r.is_routing()
			var spd := float(r.avg_speed) if "avg_speed" in r else 0.0
			if (moving or routing or spd > 12.0) and engaged <= 0.0:
				var entry := {"pos": rp, "id": int(r.id) if "id" in r else r.get_instance_id(),
						"men": float(r.alive), "speed": spd,
						"run": (bool(r.running) if "running" in r else false) or routing}
				if mounted:
					moving_cav.append(entry)
				else:
					moving_inf.append(entry)
	else:
		# fallback: melee heat from contact events
		for c in _contacts:
			_add_to_cluster(c[0], 30.0 * c[1], null)
			total_engaged += 30.0 * c[1]
	for c in _contacts:
		c[1] *= 0.85
	_contacts = _contacts.filter(func(c): return c[1] > 0.05)
	_clusters.sort_custom(func(a, b): return a["weight"] > b["weight"])
	_assign_beds()
	_assign_movers(_marches, moving_inf, false)
	_assign_movers(_gallops, moving_cav, true)
	# battle intensity (0..1) from engaged men, recent deaths and volleys
	_deaths_recent *= 0.8
	_volleys_recent *= 0.85
	_intensity_raw = clampf(total_engaged / 180.0 + _deaths_recent / 25.0 + _volleys_recent / 12.0, 0.0, 1.0)


func _add_to_cluster(p: Vector2, w: float, r) -> void:
	for c in _clusters:
		if c["pos"].distance_to(p) < 320.0:
			var tw: float = c["weight"] + w
			c["pos"] = (c["pos"] * c["weight"] + p * w) / tw
			c["weight"] = tw
			if r != null and "type_key" in r:
				c["kinds"].append(str(r.type_key))
			return
	_clusters.append({"pos": p, "weight": w, "kinds": [str(r.type_key)] if r != null and "type_key" in r else []})


func _assign_beds() -> void:
	var used := {}
	for lv in _beds:
		var best := -1
		var bd := INF
		for ci in _clusters.size():
			if used.has(ci) or ci >= _beds.size():
				continue
			var d: float = lv.pos.distance_to(_clusters[ci]["pos"]) if lv.key >= 0 else float(ci)
			if d < bd:
				bd = d
				best = ci
		if best >= 0:
			used[best] = true
			var c: Dictionary = _clusters[best]
			lv.pos = c["pos"]
			lv.key = best
			# 6 men -> about -14 dB, 60 -> 0 dB, 200 -> +4 dB
			lv.target_db = clampf(10.0 * log(c["weight"] / 60.0) / log(10.0) * 1.2, -18.0, 4.0) - 4.0
		else:
			lv.key = -1
			lv.target_db = -80.0


func _assign_movers(loops: Array[LoopVoice], movers: Array, cav: bool) -> void:
	var cam := _cam_center()
	movers.sort_custom(func(a, b): return a["pos"].distance_squared_to(cam) < b["pos"].distance_squared_to(cam))
	for i in loops.size():
		var lv := loops[i]
		if i < movers.size():
			var m: Dictionary = movers[i]
			lv.pos = m["pos"]
			lv.key = m["id"]
			var men: float = m["men"]
			lv.target_db = clampf(10.0 * log(maxf(men, 1.0) / 40.0) / log(10.0), -14.0, 3.0) - (2.0 if cav else 6.0)
			if cav:
				lv.pitch = 1.12 if m["run"] else 0.95
			else:
				lv.pitch = 1.22 if m["run"] else 1.0
		else:
			lv.key = -1
			lv.target_db = -80.0


func _update_loops(delta: float) -> void:
	for group in [_beds, _marches, _gallops]:
		for lv: LoopVoice in group:
			var p := lv.player
			if p.stream == null:
				continue
			var want := lv.target_db + (_spatial_db(lv.pos) if lv.target_db > -79.0 else 0.0)
			var rate := 10.0 * delta   # dB per frame-ish smoothing
			lv.cur_db = move_toward(lv.cur_db, want, maxf(rate * 4.0, absf(want - lv.cur_db) * 3.0 * delta))
			if lv.cur_db > -60.0:
				if not p.playing:
					p.play(_rng.randf() * maxf(0.0, p.stream.get_length() - 0.1))
				p.global_position = p.global_position.lerp(lv.pos, clampf(delta * 3.0, 0.0, 1.0)) \
						if p.global_position.distance_to(lv.pos) < 600.0 else lv.pos
				p.volume_db = lv.cur_db
				p.pitch_scale = lerpf(p.pitch_scale, lv.pitch, clampf(delta * 2.0, 0.0, 1.0))
			elif p.playing:
				p.stop()


func _update_clash_oneshots(delta: float) -> void:
	if _clusters.is_empty():
		_clash_accum = 0.0
		return
	var total := 0.0
	for c in _clusters:
		total += c["weight"]
	# ~1 clash per 10 engaged men per second, capped (the bed carries the rest)
	_clash_accum += clampf(total * 0.1, 0.0, 9.0) * delta
	while _clash_accum >= 1.0:
		_clash_accum -= 1.0
		var c: Dictionary = _weighted_cluster(total)
		var kinds: Array = c["kinds"]
		var k := "" if kinds.is_empty() else str(kinds[_rng.randi() % kinds.size()])
		var sound := "sword_clash"
		var roll := _rng.randf()
		match k:
			"yari":
				sound = "spear_thrust" if roll < 0.55 else ("armour_impact" if roll < 0.8 else "sword_clash")
			"cavalry", "general":
				sound = "sword_clash" if roll < 0.5 else ("armour_impact" if roll < 0.85 else "horse_whinny")
			_:
				sound = "sword_clash" if roll < 0.55 else ("sword_hit" if roll < 0.8 else "armour_impact")
		play_at(sound, c["pos"] + _jitter(70.0), _rng.randf_range(-4.0, 0.0))


func _weighted_cluster(total: float) -> Dictionary:
	var x := _rng.randf() * total
	for c in _clusters:
		x -= c["weight"]
		if x <= 0.0:
			return c
	return _clusters[0]


func _update_intensity(delta: float) -> void:
	var target := _intensity_override if _intensity_override >= 0.0 else _intensity_raw
	var k := 0.5 if target > _intensity else 0.12   # rise in ~2 s, fall in ~8 s
	_intensity = lerpf(_intensity, target, clampf(k * delta, 0.0, 1.0))
	if phase == "battle":
		var i := _intensity
		var w_int := smoothstep(0.45, 0.8, i)
		var w_bat := smoothstep(0.02, 0.22, i) * (1.0 - w_int)
		var w_dep := 1.0 - smoothstep(0.02, 0.22, i)
		_set_layer_targets(w_dep, w_bat, w_int)
		_amb_target["birds"] = 1.0 - smoothstep(0.1, 0.5, i)


func _update_music(delta: float) -> void:
	var any := false
	for l in LAYERS:
		_music_w[l] = move_toward(_music_w[l], _music_target[l], delta / 2.5)
		var mp: AudioStreamPlayer = _music[l]
		mp.volume_db = _lin_db(sqrt(_music_w[l])) + music_db   # equal-power crossfade
		any = any or _music_w[l] > 0.001
	if not any and phase in ["menu", "victory", "defeat"]:
		for l in LAYERS:
			if _music[l].playing and _music_w[l] <= 0.0:
				_music[l].stop()
	_menu_w = move_toward(_menu_w, _menu_target, delta / 2.0)
	_menu_player.volume_db = _lin_db(sqrt(_menu_w)) + music_db
	if _menu_w <= 0.0 and _menu_player.playing:
		_menu_player.stop()


func _update_ambience(delta: float) -> void:
	# river follows proximity to water when the terrain can tell us
	if Engine.get_process_frames() % 15 == 0:
		_water_near = _probe_water()
	if phase in ["deploy", "battle"]:
		_amb_target["river"] = _water_near
	var levels := {"wind": 0.0, "birds": -4.0, "river": -2.0}
	for a in _amb:
		_amb_w[a] = move_toward(_amb_w[a], _amb_target[a], delta / 3.0)
		var ap: AudioStreamPlayer = _amb[a]
		if ap.stream == null:
			continue
		if _amb_w[a] > 0.001:
			if not ap.playing:
				ap.play(_rng.randf() * maxf(0.0, ap.stream.get_length() - 1.0))
			ap.volume_db = _lin_db(_amb_w[a]) + ambience_db + float(levels[a])
		elif ap.playing:
			ap.stop()


func _update_zoom_filter() -> void:
	if _lp_effect == null:
		return
	var z := _cam_zoom()
	# zoomed right out (0.35) -> 5 kHz, 1.0 and closer -> open
	_lp_effect.cutoff_hz = lerpf(5000.0, 20000.0, smoothstep(0.35, 1.0, z))


func _update_voice_levels() -> void:
	# keep one-shots tracking the camera (pan is automatic; distance/zoom gain is ours)
	for i in _voices.size():
		var v := _voices[i]
		if v.playing:
			v.volume_db = float(_voice_meta[i]["base_db"]) + _spatial_db(v.global_position)
		elif _voice_meta[i]["prio"] >= 0:
			_voice_meta[i] = {"name": "", "prio": -1, "base_db": -80.0, "start": -99.0}


# =============================================================================== helpers
func _spatial_db(p: Vector2) -> float:
	if p == Vector2.INF:
		return 0.0
	var vp := get_viewport()
	var cam := vp.get_camera_2d() if vp else null
	if cam == null:
		return 0.0
	var z := maxf(cam.zoom.x, 0.05)
	var half := vp.get_visible_rect().size * 0.5 / z
	var d := (p - cam.get_screen_center_position()) / Vector2(maxf(half.x, 1.0), maxf(half.y, 1.0))
	var r := d.length()
	var dist_db := -10.0 * maxf(0.0, r - 0.75)          # gentle inside the screen, -10 dB per screen beyond
	dist_db = maxf(dist_db, -60.0)
	var zoom_db := lerpf(-9.0, 0.0, smoothstep(0.35, 1.2, z))
	return dist_db + zoom_db


func _cam_center() -> Vector2:
	var vp := get_viewport()
	var cam := vp.get_camera_2d() if vp else null
	return cam.get_screen_center_position() if cam else Vector2.ZERO


func _cam_zoom() -> float:
	var vp := get_viewport()
	var cam := vp.get_camera_2d() if vp else null
	return cam.zoom.x if cam else 1.0


func _find_voice(prio: int, heard_db: float) -> int:
	var worst := -1
	var worst_score := INF
	for i in _voices.size():
		if not _voices[i].playing:
			return i
		var m: Dictionary = _voice_meta[i]
		# score: priority dominates, then current loudness, then age
		var score := float(m["prio"]) * 100.0 + _voices[i].volume_db - (_time - float(m["start"])) * 6.0
		if score < worst_score:
			worst_score = score
			worst = i
	var new_score := float(prio) * 100.0 + heard_db
	return worst if worst >= 0 and new_score > worst_score else -1


func _pick(sound: String) -> AudioStream:
	var arr: Array = _streams.get(sound, [])
	if arr.is_empty():
		return null
	if arr.size() == 1:
		return arr[0]
	var last := int(_last_variant.get(sound, -1))
	var i := _rng.randi() % arr.size()
	if i == last:
		i = (i + 1 + _rng.randi() % (arr.size() - 1)) % arr.size()
	_last_variant[sound] = i
	return arr[i]


func _schedule(delay: float, sound: String, p: Vector2, vol_db: float) -> void:
	_pending.append([_time + delay, sound, p, vol_db])


func _run_schedule() -> void:
	if _pending.is_empty():
		return
	var keep := []
	for e in _pending:
		if e[0] <= _time:
			if e[2] == Vector2.INF:
				play_global(e[1], e[3])
			else:
				play_at(e[1], e[2], e[3])
		else:
			keep.append(e)
	_pending = keep


func _soldier_pos(i: int) -> Vector2:
	var arr = _sim_get("pos")
	if arr is PackedVector2Array and i >= 0 and i < arr.size():
		return arr[i]
	return Vector2.INF


func _reg_pos(r) -> Vector2:
	if r == null:
		return Vector2.INF
	if r is Object:
		if "mean_pos" in r and r.mean_pos != Vector2.ZERO:
			return r.mean_pos
		if "centre" in r:
			return r.centre
		if "center" in r:
			return r.center
	elif r is int:
		var regs = _sim_get("regiments", [])
		if regs is Array and r >= 0 and r < regs.size():
			return _reg_pos(regs[r])
	return Vector2.INF


func _regiment_near(p: Vector2):
	var regs = _sim_get("regiments", [])
	if not (regs is Array):
		return null
	var best = null
	var bd := 60.0
	for r in regs:
		if r == null:
			continue
		var d := _reg_pos(r).distance_to(p)
		if d < bd:
			bd = d
			best = r
	return best


func _fire_target_pos(shooter) -> Vector2:
	if shooter == null:
		return Vector2.INF
	var t = null
	if "fire_target" in shooter and shooter.fire_target != null:
		t = shooter.fire_target
	elif shooter.has_method("target"):
		t = shooter.target()
	if t == null and "nearest_enemy" in shooter:
		t = shooter.nearest_enemy
	return _reg_pos(t) if t != null else Vector2.INF


func _probe_water() -> float:
	var terrain = _sim_get("terrain")
	if terrain == null or not terrain.has_method("is_water"):
		return 0.25 if phase in ["deploy", "battle"] else 0.0
	var c := _cam_center()
	var half := get_viewport().get_visible_rect().size * 0.5 / maxf(_cam_zoom(), 0.05)
	var hits := 0.0
	var total := 0.0
	for gx in range(-2, 3):
		for gy in range(-2, 3):
			var p := c + Vector2(gx, gy) * half * 0.6
			var w := 1.0 / (1.0 + Vector2(gx, gy).length())
			total += w
			if terrain.is_water(p):
				hits += w
	return clampf(hits / total * 3.0, 0.0, 1.0)


func _set_layer_targets(dep: float, bat: float, inten: float) -> void:
	_music_target["deploy"] = dep
	_music_target["battle"] = bat
	_music_target["intense"] = inten


func _start_layers() -> void:
	var any_playing := false
	for l in LAYERS:
		any_playing = any_playing or _music[l].playing
	if any_playing:
		return
	for l in LAYERS:
		if _music[l].stream:
			_music[l].play(0.0)


func _stop_layers_soft() -> void:
	_set_layer_targets(0.0, 0.0, 0.0)


func _set_amb(w: float, b: float, r: float) -> void:
	_amb_target["wind"] = w
	_amb_target["birds"] = b
	_amb_target["river"] = r * _water_near


func _jitter(r: float) -> Vector2:
	return Vector2(_rng.randf_range(-r, r), _rng.randf_range(-r, r) * 0.6)


static func _lin_db(x: float) -> float:
	return -80.0 if x <= 0.0001 else 20.0 * log(x) / log(10.0)

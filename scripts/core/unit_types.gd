class_name UnitTypes
extends RefCounted
## Static unit database for the six regiment types (GDD §4).
##
## Units are world pixels (infantry ≈ 44 px tall ≈ 1.7 m, so ~26 px per metre, with gameplay
## compression on ranges). Times are seconds. The sim caches these into packed per-type arrays,
## so look-ups in hot loops never touch the dictionaries.

enum { YARI, YUMI, TEPPO, SAMURAI, CAVALRY, GENERAL }

const KEYS := ["yari", "yumi", "teppo", "samurai", "cavalry", "general"]
const TEAM_KEYS := ["hino", "mizuno"]

## Ranged kinds
const RANGED_NONE := 0
const RANGED_ARROW := 1
const RANGED_GUN := 2

## Animation slots used by the renderer. Slot 2 maps to the unit's `action_anim` key.
const ANIM_IDLE := 0
const ANIM_WALK := 1
const ANIM_ACTION := 2
const ANIM_DEATH := 3

## Default standard army (GDD §4): 1 general, 3 yari, 2 yumi, 1 teppo, 2 samurai, 2 cavalry.
const STANDARD_ARMY := ["general", "yari", "yari", "yari", "yumi", "yumi", "teppo", "samurai", "samurai", "cavalry", "cavalry"]

const STATS := {
	"yari": {
		"name": "Yari Ashigaru", "men": 60, "files": 12, "spacing": Vector2(15.5, 16.5), "radius": 6.5,
		"hp": 28.0, "melee_attack": 30.0, "melee_defence": 38.0, "damage": 9.0, "attack_interval": 1.5,
		"reach": 20.0, "charge_bonus": 8.0, "armour": 20.0, "speed_walk": 34.0, "speed_run": 96.0,
		"range": 0.0, "reload": 0.0, "accuracy": 0.0, "missile_damage": 0.0, "ranged": RANGED_NONE,
		"morale_base": 52.0, "mass": 1.0, "mounted": false, "anti_cav": 22.0, "brace": true,
		"action_anim": "attack", "action_len": 0.7, "hit_time": 0.32, "height": 44.0, "aura": 0.0,
	},
	"yumi": {
		"name": "Yumi Ashigaru", "men": 40, "files": 10, "spacing": Vector2(15, 17), "radius": 6.5,
		"hp": 24.0, "melee_attack": 18.0, "melee_defence": 20.0, "damage": 7.0, "attack_interval": 1.4,
		"reach": 13.0, "charge_bonus": 4.0, "armour": 10.0, "speed_walk": 36.0, "speed_run": 100.0,
		"range": 640.0, "reload": 4.2, "accuracy": 0.72, "missile_damage": 13.0, "ranged": RANGED_ARROW,
		"morale_base": 45.0, "mass": 1.0, "mounted": false, "anti_cav": 0.0, "brace": false,
		"action_anim": "shoot", "action_len": 0.8, "hit_time": 0.5, "height": 44.0, "aura": 0.0,
	},
	"teppo": {
		"name": "Teppo Ashigaru", "men": 40, "files": 14, "spacing": Vector2(15, 17), "radius": 6.5,
		"hp": 24.0, "melee_attack": 16.0, "melee_defence": 18.0, "damage": 6.0, "attack_interval": 1.5,
		"reach": 13.0, "charge_bonus": 4.0, "armour": 10.0, "speed_walk": 34.0, "speed_run": 96.0,
		"range": 330.0, "reload": 9.0, "accuracy": 0.55, "missile_damage": 26.0, "ranged": RANGED_GUN,
		"morale_base": 45.0, "mass": 1.0, "mounted": false, "anti_cav": 0.0, "brace": false,
		"action_anim": "fire", "action_len": 0.8, "hit_time": 0.36, "height": 44.0, "aura": 0.0,
	},
	"samurai": {
		"name": "Katana Samurai", "men": 32, "files": 8, "spacing": Vector2(16, 17), "radius": 7.0,
		"hp": 40.0, "melee_attack": 55.0, "melee_defence": 50.0, "damage": 12.0, "attack_interval": 1.2,
		"reach": 15.0, "charge_bonus": 18.0, "armour": 45.0, "speed_walk": 36.0, "speed_run": 104.0,
		"range": 0.0, "reload": 0.0, "accuracy": 0.0, "missile_damage": 0.0, "ranged": RANGED_NONE,
		"morale_base": 80.0, "mass": 1.15, "mounted": false, "anti_cav": 0.0, "brace": false,
		"action_anim": "attack", "action_len": 0.6, "hit_time": 0.3, "height": 46.0, "aura": 0.0,
	},
	"cavalry": {
		"name": "Yari Cavalry", "men": 20, "files": 7, "spacing": Vector2(26, 44), "radius": 12.0,
		"hp": 50.0, "melee_attack": 42.0, "melee_defence": 30.0, "damage": 12.0, "attack_interval": 1.4,
		"reach": 22.0, "charge_bonus": 55.0, "armour": 35.0, "speed_walk": 62.0, "speed_run": 190.0,
		"range": 0.0, "reload": 0.0, "accuracy": 0.0, "missile_damage": 0.0, "ranged": RANGED_NONE,
		"morale_base": 65.0, "mass": 4.0, "mounted": true, "anti_cav": 0.0, "brace": false,
		"action_anim": "attack", "action_len": 0.7, "hit_time": 0.33, "height": 60.0, "aura": 0.0,
	},
	"general": {
		"name": "General's Hatamoto", "men": 12, "files": 6, "spacing": Vector2(28, 46), "radius": 12.0,
		"hp": 70.0, "melee_attack": 55.0, "melee_defence": 55.0, "damage": 14.0, "attack_interval": 1.2,
		"reach": 20.0, "charge_bonus": 45.0, "armour": 60.0, "speed_walk": 60.0, "speed_run": 180.0,
		"range": 0.0, "reload": 0.0, "accuracy": 0.0, "missile_damage": 0.0, "ranged": RANGED_NONE,
		"morale_base": 95.0, "mass": 4.0, "mounted": true, "anti_cav": 0.0, "brace": false,
		"action_anim": "attack", "action_len": 0.7, "hit_time": 0.33, "height": 62.0, "aura": 420.0,
	},
}


static func index_of(key: String) -> int:
	return KEYS.find(key)


static func key_of(t: int) -> String:
	return KEYS[t]


static func get_stats(t: int) -> Dictionary:
	return STATS[KEYS[t]]


static func anim_key(t: int, slot: int) -> String:
	match slot:
		ANIM_IDLE: return "idle"
		ANIM_WALK: return "walk"
		ANIM_ACTION: return get_stats(t)["action_anim"]
		_: return "death"

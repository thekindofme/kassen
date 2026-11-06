extends Node
## KASSEN game flow controller (autoload "Game").
##
##   title → battle select → briefing → battle (deploy → fight) → results → title / replay
##
## Public API
##   Game.boot()                         called by scenes/main.tscn; goes to the title (or straight
##                                       into battle when launched with --shot/--demo/--map/--battle)
##   Game.goto_title() / goto_select() / goto_briefing() / start_battle() / replay()
##   Game.choose(scenario_key, difficulty)   remember the player's choice
##   Game.scenario_key, Game.difficulty (0 Easy, 1 Normal, 2 Hard), Game.scenario() -> Dictionary
##   Game.map_key() -> String            map script key the battle scene should load
##   Game.settings (Dictionary), Game.apply_settings(), Game.save_settings()
##   signal state_changed(state: String)  "title" | "select" | "briefing" | "battle" | "results"
## The battle scene's Hud (scenes/ui/hud.tscn) binds itself; Game listens for the battle end
## and opens the Results scroll on top of the battlefield.

signal state_changed(state: String)

const TITLE_SCENE := "res://scenes/ui/title_screen.tscn"
const SELECT_SCENE := "res://scenes/ui/battle_select.tscn"
const BRIEFING_SCENE := "res://scenes/ui/briefing.tscn"
const BATTLE_SCENE := "res://scenes/battle.tscn"
const RESULTS_SCENE := "res://scenes/ui/results.tscn"
const HUD_SCENE := "res://scenes/ui/hud.tscn"
const SETTINGS_PATH := "user://settings.cfg"

const DIFFICULTIES := [
	{"key": "easy", "name": "Gentle", "kanji": "易", "desc": "The Mizuno react slowly and their resolve is brittle."},
	{"key": "normal", "name": "Bushidō", "kanji": "武", "desc": "A fair fight between two clans of equal mettle."},
	{"key": "hard", "name": "Shura", "kanji": "修羅", "desc": "Swift, cunning enemies who hunt for open flanks."},
]

const SCENARIOS := {
	"kurogawa": {
		"key": "kurogawa", "map": "kurogawa", "art": "kurogawa",
		"title": "The Ford at Kurogawa", "kanji": "黒川", "subtitle": "Summer · midday · open plain",
		"desc": "Hold the only ford of the Black River. The Mizuno must cross the shallows under your bows, or not at all.",
		"date": "Tenshō 2 (1574) · Mino Province",
		"briefing": [
			"Summer, 1574. Lord Mizuno Tadakatsu has broken the old alliance and marches on the capital road.",
			"Only the ford at Kurogawa lets an army cross the Black River. Your father's veterans hold the west bank.",
			"Hino Masatora, this is your first command. Hold the ford, and break the indigo host in the shallows.",
		],
	},
	"tenmoku": {
		"key": "tenmoku", "map": "tenmoku", "art": "tenmoku",
		"title": "Mist over Tenmoku Pass", "kanji": "天目峠", "subtitle": "Dawn · mist · hill pass",
		"desc": "The Mizuno hold the high ground above a fog-choked pass. Climb through pine and mist to dislodge them.",
		"date": "Tenshō 2 (1574) · Tenmoku Pass",
		"briefing": [
			"Dawn. Fog pours through Tenmoku Pass, and the Mizuno banners crown the ridge above the shrine.",
			"Their archers hold the slopes. Every step uphill will be paid for in blood and breath.",
			"Use the mist, Masatora. Close before their bows find you, and drive them from the heights.",
		],
	},
}
const ORDER := ["kurogawa", "tenmoku"]

var state := ""
var scenario_key := "kurogawa"
var difficulty := 1
var settings := {"master": 0.9, "music": 0.8, "sfx": 0.9, "fullscreen": false}
var menu_audio: Node = null           # AudioDirector used outside battle (the battle scene has its own)
var last_result: Dictionary = {}
var _fade: ColorRect
var _busy := false
var _results_shown := false
var _hud: Node = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var layer := CanvasLayer.new()
	layer.name = "FadeLayer"
	layer.layer = 120
	add_child(layer)
	_fade = ColorRect.new()
	_fade.name = "Fade"
	_fade.color = Color(0.03, 0.02, 0.015, 0.0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_fade)
	load_settings()
	apply_settings()
	get_tree().node_added.connect(_on_node_added)


# =====================================================================================
#  Flow
# =====================================================================================

func boot() -> void:
	var args := user_args()
	for k in ["shot", "demo", "map", "battle", "skip_menu"]:
		if args.has(k):
			if args.has("map") and SCENARIOS.has(String(args["map"])):
				scenario_key = String(args["map"])
			start_battle(false)
			return
	goto_title(false)


func scenario() -> Dictionary:
	return SCENARIOS.get(scenario_key, SCENARIOS["kurogawa"])


func map_key() -> String:
	return String(scenario().get("map", "kurogawa"))


func difficulty_info() -> Dictionary:
	return DIFFICULTIES[clampi(difficulty, 0, DIFFICULTIES.size() - 1)]


func choose(key: String, diff := -1) -> void:
	if SCENARIOS.has(key):
		scenario_key = key
	if diff >= 0:
		difficulty = clampi(diff, 0, DIFFICULTIES.size() - 1)


func goto_title(fade := true) -> void:
	_ensure_menu_audio()
	_change(TITLE_SCENE, "title", fade)


func goto_select(fade := true) -> void:
	_ensure_menu_audio()
	_change(SELECT_SCENE, "select", fade)


func goto_briefing(fade := true) -> void:
	_ensure_menu_audio()
	_change(BRIEFING_SCENE, "briefing", fade)


func start_battle(fade := true) -> void:
	_results_shown = false
	_hud = null
	_free_menu_audio()
	_change(BATTLE_SCENE, "battle", fade)


func replay() -> void:
	get_tree().paused = false
	start_battle(true)


func _change(path: String, new_state: String, fade: bool) -> void:
	if _busy:
		return
	_busy = true
	get_tree().paused = false
	if fade and is_inside_tree():
		var t := create_tween()
		t.tween_property(_fade, "color:a", 1.0, 0.35)
		await t.finished
	if new_state == "battle":
		_free_menu_audio()
	var err := get_tree().change_scene_to_file(path)
	if err != OK:
		push_error("Game: cannot load %s (%d)" % [path, err])
	state = new_state
	state_changed.emit(state)
	await get_tree().process_frame
	await get_tree().process_frame
	if new_state != "battle":
		UiKit.phase(self, "menu")
	_busy = false
	var t2 := create_tween()
	t2.tween_property(_fade, "color:a", 0.0, 0.5 if fade else 0.01)


## Hook the HUD of a freshly loaded battle scene (works whether the Hud is placed in
## battle.tscn or added later).
func _on_node_added(n: Node) -> void:
	if n.name == "Hud" and n.has_signal("battle_finished"):
		_hud = n
		if not n.is_connected("battle_finished", _on_battle_finished):
			n.connect("battle_finished", _on_battle_finished)


func _on_battle_finished(winner: int) -> void:
	if _results_shown or _hud == null or not is_instance_valid(_hud):
		return
	_results_shown = true
	var data: Dictionary = _hud.call("collect_result", winner)
	last_result = data
	await get_tree().create_timer(2.6).timeout
	show_results(data)


## Opens the Results scroll over the current scene (normally the battle).
func show_results(data: Dictionary) -> Node:
	var ps := load(RESULTS_SCENE) as PackedScene
	if ps == null:
		return null
	var res := ps.instantiate()
	var host := get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	host.add_child(res)
	state = "results"
	state_changed.emit(state)
	if res.has_signal("replay_pressed"):
		res.connect("replay_pressed", replay)
	if res.has_signal("menu_pressed"):
		res.connect("menu_pressed", func(): goto_title(true))
	res.call("show_result", data)
	return res


# =====================================================================================
#  Audio outside battle
# =====================================================================================

func _ensure_menu_audio() -> void:
	if menu_audio != null and is_instance_valid(menu_audio):
		return
	var script := load("res://scripts/audio/audio_director.gd") as Script
	if script == null:
		return
	menu_audio = script.new()
	menu_audio.name = "MenuAudio"
	add_child(menu_audio)
	if menu_audio.has_method("set_phase"):
		menu_audio.set_phase("menu")
	apply_settings()


func _free_menu_audio() -> void:
	if menu_audio != null and is_instance_valid(menu_audio):
		menu_audio.queue_free()
	menu_audio = null


# =====================================================================================
#  Settings
# =====================================================================================

func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) != OK:
		return
	for k in settings.keys():
		settings[k] = cf.get_value("settings", k, settings[k])


func save_settings() -> void:
	var cf := ConfigFile.new()
	for k in settings.keys():
		cf.set_value("settings", k, settings[k])
	cf.save(SETTINGS_PATH)


func set_setting(key: String, value) -> void:
	settings[key] = value
	apply_settings()


func apply_settings() -> void:
	_bus("Master", float(settings["master"]))
	_bus("Music", float(settings["music"]))
	_bus("SFX", float(settings["sfx"]))
	_bus("UI", float(settings["sfx"]))
	_bus("Ambience", float(settings["sfx"]))
	if DisplayServer.get_name() != "headless":
		var want_fs := bool(settings["fullscreen"])
		var mode := DisplayServer.window_get_mode()
		var is_fs := mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
		if want_fs != is_fs:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if want_fs else DisplayServer.WINDOW_MODE_WINDOWED)


func _bus(bus_name: String, v: float) -> void:
	var i := AudioServer.get_bus_index(bus_name)
	if i < 0:
		return
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.0001)))
	AudioServer.set_bus_mute(i, v <= 0.001)


static func user_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1] if kv.size() > 1 else true
	return out

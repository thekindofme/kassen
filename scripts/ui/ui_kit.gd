class_name UiKit
extends RefCounted
## Shared UI constants and helpers: palette, fonts, textures, audio lookup, little tweens.

const THEME_PATH := "res://assets/ui/kassen_theme.tres"

# --- palette (ART_BIBLE) -------------------------------------------------------------
const LACQUER := Color("#14100D")
const GOLD := Color("#C9A04A")
const GOLD_HI := Color("#F0CE80")
const GOLD_LO := Color("#785824")
const WASHI := Color("#E8DDC4")
const INK := Color("#21170F")
const VERMILION := Color("#C23B22")
const HINO := Color("#A3201E")
const HINO_HI := Color("#D8433A")
const MIZUNO := Color("#23356B")
const MIZUNO_HI := Color("#4A68B8")
const SILVER := Color("#D9D4C5")

const TEAM_NAMES := ["Hino", "Mizuno"]
const MORALE_COLORS := [Color("#E2C15A"), Color("#6FA04B"), Color("#D98A2B"), Color("#C8321F"), Color("#5A534C")]

static var _cache := {}


static func res(path: String) -> Resource:
	if not _cache.has(path):
		_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _cache[path]


static func theme() -> Theme:
	return res(THEME_PATH) as Theme


static func font_title() -> Font:
	return res("res://assets/fonts/ShipporiMinchoB1-ExtraBold.ttf") as Font


static func font_head() -> Font:
	return res("res://assets/fonts/ShipporiMinchoB1-Bold.ttf") as Font


static func font_brush() -> Font:
	return res("res://assets/fonts/YujiBoku-Regular.ttf") as Font


static func font_body() -> Font:
	return res("res://assets/fonts/AlegreyaSans-Medium.ttf") as Font


static func font_bold() -> Font:
	return res("res://assets/fonts/AlegreyaSans-Bold.ttf") as Font


static func tex(name: String) -> Texture2D:
	return res("res://assets/ui/%s.png" % name) as Texture2D


static func art(name: String) -> Texture2D:
	var p := "res://assets/art/%s.jpg" % name
	if not ResourceLoader.exists(p):
		p = "res://assets/art/%s.png" % name
	return res(p) as Texture2D


static func portrait(type_key: String, big := false) -> Texture2D:
	return res("res://assets/art/portrait_%s_%d.png" % [type_key, 512 if big else 256]) as Texture2D


static func mon(team: int, big := false) -> Texture2D:
	return res("res://assets/ui/mon_%s_%d.png" % ["hino" if team == 0 else "mizuno", 512 if big else 128]) as Texture2D


static func team_color(team: int, hi := false) -> Color:
	if team == 0:
		return HINO_HI if hi else HINO
	return MIZUNO_HI if hi else MIZUNO


static func stylebox(name: String, margin := 30.0) -> StyleBoxTexture:
	var key := "sb:%s:%f" % [name, margin]
	if not _cache.has(key):
		var sb := StyleBoxTexture.new()
		sb.texture = tex(name)
		sb.texture_margin_left = margin
		sb.texture_margin_top = margin
		sb.texture_margin_right = margin
		sb.texture_margin_bottom = margin
		_cache[key] = sb
	return _cache[key]


# --- audio -------------------------------------------------------------------------------

## Finds the active AudioDirector: one inside the current scene (battle), an autoload, or the
## menu director owned by the Game flow. Returns null when there is none.
static func audio(tree: SceneTree) -> Node:
	if tree == null:
		return null
	var root := tree.root
	for n in ["Audio", "AudioDirector"]:
		var a := root.get_node_or_null(n)
		if a != null and a.has_method("play_ui"):
			return a
	var cs := tree.current_scene
	if cs != null:
		var a2 := cs.find_child("AudioDirector", true, false)
		if a2 != null and a2.has_method("play_ui"):
			return a2
	var g := root.get_node_or_null("Game")
	if g != null:
		var a3 = g.get("menu_audio")
		if a3 is Node and is_instance_valid(a3) and a3.has_method("play_ui"):
			return a3
	return null


static func sfx(node: Node, ui_name: String) -> void:
	if node == null or not node.is_inside_tree():
		return
	var a := audio(node.get_tree())
	if a != null:
		a.play_ui(ui_name)


static func phase(node: Node, p: String) -> void:
	if node == null or not node.is_inside_tree():
		return
	var a := audio(node.get_tree())
	if a != null and a.has_method("set_phase"):
		a.set_phase(p)


# --- builders ----------------------------------------------------------------------------

static func label(text: String, variation := "", size := 0, color := Color(0, 0, 0, 0)) -> Label:
	var l := Label.new()
	l.text = text
	if variation != "":
		l.theme_type_variation = variation
	if size > 0:
		l.add_theme_font_size_override("font_size", size)
	if color.a > 0.0:
		l.add_theme_color_override("font_color", color)
	return l


## Make `n` reachable as %Name from `owner_node` (stable names for tests).
static func expose(n: Node, node_name: String, owner_node: Node) -> Node:
	n.name = node_name
	n.owner = owner_node
	n.unique_name_in_owner = true
	return n


static func fmt_time(t: float) -> String:
	var s := int(t)
	return "%02d:%02d" % [s / 60, s % 60]


static func fade_in(n: CanvasItem, dur := 0.4, delay := 0.0, rise := 0.0) -> Tween:
	n.modulate.a = 0.0
	var t := n.create_tween().set_parallel(true)
	t.tween_property(n, "modulate:a", 1.0, dur).set_delay(delay).set_trans(Tween.TRANS_SINE)
	if rise != 0.0 and n is Control:
		var c := n as Control
		var y := c.position.y
		c.position.y = y + rise
		t.tween_property(c, "position:y", y, dur * 1.3).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	return t

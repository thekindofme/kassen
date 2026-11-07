class_name BattleWeather
extends Node2D
## Atmosphere + post-process for the battlefield: ground mist (fx_mist.gdshader, a layer inserted
## just below SoldierRenderer so units always stay crisp) that pools in hollows/forest edges and
## clears over time, and (post_grade.gdshader) drifting cloud shadows and a filmic grade
## (lacquer reds, muted ground), bloom on highlights, vignette and fine grain.
##
## The pass is a world-space rect that tracks the view and sits at the top z of the world canvas,
## so it reads every world draw (terrain, soldiers, smoke) but never the HUD/UI CanvasLayers.
## Maps may define `var weather := {"mist": 0.8, "mist_clear_time": 300.0, "clouds": 0.2, ...}`.

@export var post_enabled := true
@export var wind := Vector2(18.0, -4.0)
@export_group("Cloud shadows")
@export_range(0.0, 0.6) var cloud_strength := 0.11
@export_range(0.0, 1.0) var cloud_coverage := 0.52
@export var cloud_softness := 0.16
@export var cloud_scale := 0.00032
@export var cloud_tint := Color(0.82, 0.88, 1.0)
@export_group("Mist")
@export_range(0.0, 1.0) var mist_density := 0.0       ## at battle start
@export_range(0.0, 1.0) var mist_min := 0.08          ## what is left after mist_clear_time
@export var mist_clear_time := 135.0                  ## sim seconds for the mist to thin out
@export_range(0.0, 1.0) var mist_max_alpha := 0.62   ## peak opacity of a bank (on the ground only)
@export var mist_color := Color(0.84, 0.87, 0.86)
@export_group("Grade")
@export var exposure := 1.1
@export var contrast := 1.06
@export var midtone_gamma := 0.88     ## <1 lifts midtones
@export var saturation := 1.0
@export_range(0.0, 1.0) var ground_desat := 0.16
@export_range(0.0, 1.0) var red_boost := 0.35
@export var shadow_tint := Color(0.94, 0.96, 1.04)
@export var highlight_tint := Color(1.04, 1.01, 0.95)
@export_group("Lens")
@export var bloom_threshold := 0.72
@export var bloom_strength := 0.3
@export_range(0.0, 1.0) var vignette := 0.16
@export_range(0.0, 0.2) var grain := 0.022

var sim: BattleSim
var terrain: Terrain
var post: ColorRect
var mat: ShaderMaterial
var mist: ColorRect
var mist_mat: ShaderMaterial


func setup(p_sim: BattleSim, p_terrain: Terrain, args: Dictionary = {}) -> void:
	sim = p_sim
	terrain = p_terrain
	if terrain != null and terrain.map != null:
		if terrain.map.get("mist") == true:
			mist_density = 1.0
			mist_min = 0.0
			mist_clear_time = 135.0
		apply_time_of_day(String(terrain.map.get("time_of_day")) if terrain.map.get("time_of_day") != null else "day")
		var w = terrain.map.get("weather")
		if w is Dictionary:
			for k in w:
				match String(k):
					"mist": mist_density = float(w[k])
					"mist_min": mist_min = float(w[k])
					"mist_clear_time": mist_clear_time = float(w[k])
					"clouds": cloud_strength = float(w[k])
					"cloud_coverage": cloud_coverage = float(w[k])
	if args.has("mist"):
		mist_density = float(args["mist"])
	if args.has("clouds"):
		cloud_strength = float(args["clouds"])
	if args.get("post", "1") == "0":
		post_enabled = false
	mat = ShaderMaterial.new()
	mat.shader = load("res://scripts/render/shaders/post_grade.gdshader")
	mat.set_shader_parameter("cloud_tex", _noise_tex(311, 0.006, 5))
	mat.set_shader_parameter("mist_tex", _noise_tex(911, 0.009, 4))
	if terrain != null and terrain.height_img != null:
		mat.set_shader_parameter("height_tex", ImageTexture.create_from_image(terrain.height_img))
	mat.set_shader_parameter("map_size", sim.map_size)
	post = ColorRect.new()
	post.name = "PostProcess"
	post.mouse_filter = Control.MOUSE_FILTER_IGNORE
	post.color = Color.WHITE
	post.material = mat
	post.z_as_relative = false
	post.z_index = RenderingServer.CANVAS_ITEM_Z_MAX
	add_child(post)
	_build_mist()


## Mist rect goes into the battle root right before SoldierRenderer: above terrain and low props,
## below corpses, soldiers, banners and tree canopies.
func _build_mist() -> void:
	mist_mat = ShaderMaterial.new()
	mist_mat.shader = load("res://scripts/render/shaders/fx_mist.gdshader")
	mist_mat.set_shader_parameter("mist_tex", mat.get_shader_parameter("mist_tex"))
	mist_mat.set_shader_parameter("height_tex", mat.get_shader_parameter("height_tex"))
	mist_mat.set_shader_parameter("map_size", sim.map_size)
	mist = ColorRect.new()
	mist.name = "GroundMist"
	mist.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mist.material = mist_mat
	var root := get_parent().get_parent() if get_parent() != null else null
	var renderer: Node = root.get_node_or_null("SoldierRenderer") if root != null else null
	if renderer != null:
		root.add_child(mist)
		root.move_child(mist, renderer.get_index())
	else:
		add_child(mist)


## Grade presets per MapDef.time_of_day. Called from setup(); exported vars stay tweakable after.
func apply_time_of_day(tod: String) -> void:
	match tod:
		"dawn":
			exposure = 1.08
			shadow_tint = Color(0.93, 0.95, 1.05)
			highlight_tint = Color(1.09, 1.01, 0.9)
			mist_color = Color(0.9, 0.88, 0.86)
			cloud_tint = Color(0.84, 0.88, 1.0)
			saturation = 0.98
		"dusk":
			exposure = 0.98
			shadow_tint = Color(0.9, 0.9, 1.06)
			highlight_tint = Color(1.12, 0.98, 0.84)
			mist_color = Color(0.8, 0.76, 0.74)
			saturation = 0.96


static func _noise_tex(seed_v: int, freq: float, octaves: int) -> ImageTexture:
	var nz := FastNoiseLite.new()
	nz.seed = seed_v
	nz.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	nz.frequency = freq
	nz.fractal_octaves = octaves
	var img := nz.get_seamless_image(512, 512, false, false, 0.15, true)
	img.convert(Image.FORMAT_RGBA8)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func current_mist() -> float:
	if sim == null or mist_density <= 0.0:
		return 0.0
	var k := clampf(sim.time / maxf(mist_clear_time, 1.0), 0.0, 1.0)
	return lerpf(mist_density, minf(mist_min, mist_density), k)


func _process(_delta: float) -> void:
	if post == null:
		return
	var vp := get_viewport()
	var view := vp.get_canvas_transform().affine_inverse() * Rect2(Vector2.ZERO, vp.get_visible_rect().size)
	view = view.grow(maxf(view.size.x, view.size.y) * 0.3)
	var t := sim.time + sim.alpha * BattleSim.DT
	var ma := current_mist()
	if mist != null:
		mist.visible = ma > 0.001
		if mist.visible:
			mist.position = view.position
			mist.size = view.size
			mist_mat.set_shader_parameter("t", t)
			mist_mat.set_shader_parameter("wind", wind)
			mist_mat.set_shader_parameter("amount", ma)
			mist_mat.set_shader_parameter("mist_color", mist_color)
			mist_mat.set_shader_parameter("max_alpha", mist_max_alpha)
	post.visible = post_enabled
	if not post_enabled:
		return
	post.position = view.position
	post.size = view.size
	mat.set_shader_parameter("t", t)
	mat.set_shader_parameter("wind", wind)
	mat.set_shader_parameter("cloud_strength", cloud_strength)
	mat.set_shader_parameter("cloud_coverage", cloud_coverage)
	mat.set_shader_parameter("cloud_softness", cloud_softness)
	mat.set_shader_parameter("cloud_scale", cloud_scale)
	mat.set_shader_parameter("cloud_tint", cloud_tint)
	mat.set_shader_parameter("mist_amount", 0.0)   # mist lives in the ground layer now
	mat.set_shader_parameter("mist_color", mist_color)
	mat.set_shader_parameter("exposure", exposure)
	mat.set_shader_parameter("contrast", contrast)
	mat.set_shader_parameter("midtone_gamma", midtone_gamma)
	mat.set_shader_parameter("saturation", saturation)
	mat.set_shader_parameter("ground_desat", ground_desat)
	mat.set_shader_parameter("red_boost", red_boost)
	mat.set_shader_parameter("shadow_tint", shadow_tint)
	mat.set_shader_parameter("highlight_tint", highlight_tint)
	mat.set_shader_parameter("bloom_threshold", bloom_threshold)
	mat.set_shader_parameter("bloom_strength", bloom_strength)
	mat.set_shader_parameter("vignette", vignette)
	mat.set_shader_parameter("grain", grain)

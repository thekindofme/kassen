class_name TitleFx
extends RefCounted
## Atmosphere builders shared by the menu screens: drifting mist, rising embers, gradients.


static func mist_layer(vs: Vector2, count := 14, tint := Color(0.92, 0.88, 0.82, 0.16)) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.name = "Mist"
	p.texture = UiKit.tex("mist")
	p.amount = count
	p.lifetime = 38.0
	p.preprocess = 38.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(vs.x * 0.7, vs.y * 0.3)
	p.position = Vector2(vs.x * 0.35, vs.y * 0.72)
	p.direction = Vector2(1, -0.05)
	p.spread = 6.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 14.0
	p.initial_velocity_max = 34.0
	p.scale_amount_min = 3.5
	p.scale_amount_max = 7.0
	p.angle_min = -10.0
	p.angle_max = 10.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(tint, 0.0))
	ramp.set_color(1, Color(tint, 0.0))
	ramp.add_point(0.25, tint)
	ramp.add_point(0.75, tint)
	p.color_ramp = ramp
	return p


static func embers(vs: Vector2, count := 46) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.name = "Embers"
	p.texture = UiKit.tex("ember")
	p.amount = count
	p.lifetime = 9.0
	p.preprocess = 9.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(vs.x * 0.55, 20)
	p.position = Vector2(vs.x * 0.55, vs.y + 30)
	p.direction = Vector2(0.25, -1)
	p.spread = 20.0
	p.gravity = Vector2(6, -4)
	p.initial_velocity_min = 40.0
	p.initial_velocity_max = 120.0
	p.orbit_velocity_min = -0.01
	p.orbit_velocity_max = 0.01
	p.tangential_accel_min = -12.0
	p.tangential_accel_max = 12.0
	p.scale_amount_min = 0.15
	p.scale_amount_max = 0.55
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.75, 0.35, 0.0))
	ramp.add_point(0.15, Color(1.0, 0.62, 0.25, 0.95))
	ramp.add_point(0.7, Color(0.9, 0.3, 0.1, 0.6))
	ramp.set_color(ramp.get_point_count() - 1, Color(0.6, 0.15, 0.05, 0.0))
	p.color_ramp = ramp
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.material = mat
	return p


## Full-rect gradient. horizontal: from `a` at the left to `b` at `extent` of the width;
## vertical: from `a` at the top to `b` at the bottom.
static func gradient_rect(a: Color, b: Color, horizontal: bool, extent := 1.0) -> TextureRect:
	var g := Gradient.new()
	g.set_color(0, a)
	g.set_color(1, b)
	g.set_offset(1, clampf(extent, 0.01, 1.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 256
	gt.height = 256
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 0) if horizontal else Vector2(0, 1)
	var tr := TextureRect.new()
	tr.texture = gt
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


## Ken Burns drift on a TextureRect that covers `vs`.
static func ken_burns(owner_node: Node, art: TextureRect, vs: Vector2, period := 30.0, drift := Vector2(-0.1, -0.04)) -> Tween:
	art.size = vs * 1.14
	art.pivot_offset = art.size * 0.5
	art.position = -vs * 0.04
	var t := owner_node.create_tween().set_loops()
	t.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(art, "position", art.position + vs * drift, period)
	t.parallel().tween_property(art, "scale", Vector2(1.06, 1.06), period)
	t.tween_property(art, "position", art.position, period)
	t.parallel().tween_property(art, "scale", Vector2.ONE, period)
	return t

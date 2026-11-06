shader_type canvas_item;
// Soldier sprites from the unit atlas, one MultiMesh instance each.
// INSTANCE_CUSTOM = atlas UV rect (u0, v0, uw, vh).
// Instance colour (arrives in COLOR in vertex()):
//   r = hit flash 0..1, g = selection highlight 0..1, b = brightness (1 normal, <1 darker), a = opacity.

uniform sampler2D atlas : filter_linear_mipmap, repeat_disable;
uniform vec3 select_tint : source_color = vec3(1.0, 0.86, 0.45);

varying vec4 v_inst;
varying vec2 v_uv;

void vertex() {
	v_inst = COLOR;
	v_uv = INSTANCE_CUSTOM.xy + UV * INSTANCE_CUSTOM.zw;
}

void fragment() {
	vec4 c = texture(atlas, v_uv);
	vec3 col = c.rgb * v_inst.b;
	col = mix(col, col * 0.75 + select_tint * 0.35, v_inst.g * 0.6);
	col = mix(col, vec3(1.0, 0.96, 0.9), v_inst.r * 0.85);
	COLOR = vec4(col, c.a * v_inst.a);
}

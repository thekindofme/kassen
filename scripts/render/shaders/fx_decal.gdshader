shader_type canvas_item;
render_mode blend_premul_alpha, unshaded;
// Persistent ground decals (blood pools, trampled mud, spent arrows, grass tufts) from the FX
// texture array. One MultiMesh per decal class (scripts/fx/fx_pool.gd, ring buffer, capped).
//   COLOR = tint (rgb) and opacity (a);  INSTANCE_CUSTOM.x = texture layer, .y = sway (fraction
//   of the quad), .z = per-instance phase. VERTEX is quad-local (instance transform comes after).

uniform sampler2DArray tex : filter_linear_mipmap, repeat_disable;
uniform float fx_time = 0.0;
uniform vec2 wind = vec2(16.0, -3.0);

varying vec4 v_col;
varying vec3 v_uvl;

void vertex() {
	v_col = COLOR;
	v_uvl = vec3(UV, INSTANCE_CUSTOM.x);
	float sway = INSTANCE_CUSTOM.y;
	if (sway > 0.0) {
		// grass tufts: bend the top edge with the wind, travelling gusts across the field
		float ph = INSTANCE_CUSTOM.z;
		float gust = 0.6 + 0.4 * sin(fx_time * 0.9 + ph * 0.15);
		float w = sin(fx_time * 2.3 + ph) * 0.5 + 0.5;
		VERTEX.x += (1.0 - UV.y) * sway * (normalize(wind + vec2(1e-3, 0.0)).x * gust * 1.2 + (w - 0.5) * 0.8);
	}
}

void fragment() {
	vec4 t = texture(tex, v_uvl);
	COLOR = vec4(t.rgb * v_col.rgb * v_col.a, t.a * v_col.a);
}

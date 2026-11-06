shader_type canvas_item;
// Map props (trees, houses, shrine, camp, rocks, bushes) from the runtime prop atlas built by
// PropLayer, one MultiMesh instance each. INSTANCE_CUSTOM = atlas UV rect (u0, v0, uw, vh).
// Instance colour: r = brightness (0.75..1.1; its fraction also seeds the sway phase),
//   g = wind sway amplitude (x 10% of sprite width; 0 = rigid), b = clan recolour (1 = Hino red -> Mizuno indigo),
//   a = opacity (canopy fade).

uniform sampler2D atlas : filter_linear_mipmap, repeat_disable;
uniform vec3 indigo : source_color = vec3(0.17, 0.22, 0.48);

varying vec4 v_inst;
varying vec2 v_uv;

void vertex() {
	v_inst = COLOR;
	v_uv = INSTANCE_CUSTOM.xy + UV * INSTANCE_CUSTOM.zw;
	// sway: bottom fixed, top bends
	float top = 1.0 - UV.y;
	float phase = COLOR.r * 173.0;
	float sway = sin(TIME * 0.9 + phase) * 0.7 + sin(TIME * 2.3 + phase * 1.7) * 0.3;
	VERTEX.x += sway * COLOR.g * 0.1 * top * top;   // VERTEX is quad-local (0..1): fraction of the sprite width
}

void fragment() {
	vec4 c = texture(atlas, v_uv);
	vec3 col = c.rgb;
	if (v_inst.b > 0.5) {
		// saturated red cloth -> indigo; gold, wood and lacquer browns stay
		float red = smoothstep(0.5, 0.32, c.g / max(c.r, 0.01)) * smoothstep(0.12, 0.25, c.r - c.b);
		float lum = dot(c.rgb, vec3(0.3, 0.55, 0.15));
		col = mix(col, indigo * (0.55 + lum * 2.2), red);
	}
	COLOR = vec4(col * v_inst.r, c.a * v_inst.a);
}

shader_type canvas_item;
// Selection ring ellipse under a soldier's feet (unit quad). Colour = instance colour.
void fragment() {
	vec2 d = UV * 2.0 - 1.0;
	float r = length(d);
	float ring = smoothstep(0.62, 0.78, r) * (1.0 - smoothstep(0.86, 1.0, r));
	float fill = (1.0 - smoothstep(0.0, 0.8, r)) * 0.18;
	COLOR = vec4(COLOR.rgb, COLOR.a * max(ring, fill));
}

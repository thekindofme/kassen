shader_type canvas_item;
// Soft contact-shadow ellipse (unit quad, UV 0..1). Light from the top-left: drawn by the
// renderer slightly offset to the bottom-right of the feet.
uniform vec4 shadow_color : source_color = vec4(0.10, 0.09, 0.08, 0.38);

void fragment() {
	vec2 d = UV * 2.0 - 1.0;
	float r = length(d);
	float a = 1.0 - smoothstep(0.35, 1.0, r);
	COLOR = vec4(shadow_color.rgb, shadow_color.a * a * COLOR.a);
}

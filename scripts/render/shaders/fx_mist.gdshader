shader_type canvas_item;
render_mode unshaded;
// Ground mist (scripts/fx/weather.gd). A world-space rect that tracks the view, inserted in the
// scene tree just BELOW SoldierRenderer: it veils terrain and low props but never the soldiers,
// corpses or banners. Patchy wisps and banks pool in hollows, along forest edges and over water,
// thin out on high ground, drift with the wind and shrink as `amount` falls toward 0.

uniform sampler2D mist_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D height_tex : filter_linear, repeat_disable; // r = height/64, g = water, b = forest
uniform vec2 map_size = vec2(4800.0, 3200.0);
uniform float t = 0.0;
uniform vec2 wind = vec2(18.0, -4.0);
uniform float amount = 1.0;          // 1 = dawn bank, 0 = gone
uniform vec3 mist_color : source_color = vec3(0.86, 0.87, 0.9);
uniform float max_alpha = 0.72;

varying vec2 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	if (amount <= 0.001) {
		discard;
	}
	// two drifting layers: broad banks + faster stretched wisps
	vec2 uv1 = (world + wind * t * 1.6) * 0.00045;
	vec2 uv2 = (world * vec2(1.0, 2.2) + wind * t * 3.0) * 0.0012;
	float banks = texture(mist_tex, uv1).r;
	float wisps = texture(mist_tex, uv2 + vec2(0.37, 0.11)).r;
	float n = banks * 0.7 + wisps * 0.3;

	// where mist likes to sit: hollows, forest edges, water; not the ridge top
	vec4 hv = texture(height_tex, world / map_size);
	float low = 1.0 - smoothstep(0.08, 0.5, hv.r);
	float edge = clamp(hv.b * (1.0 - hv.b) * 4.0, 0.0, 1.0);
	float site = max(low, max(edge * 0.85, hv.g));
	site *= 1.0 - smoothstep(0.45, 0.8, hv.r);

	// higher threshold as it clears: banks shrink and break apart instead of just fading
	float thr = mix(0.8, 0.42, amount);
	float v = n * (0.3 + 0.75 * site);
	float m = smoothstep(thr, thr + 0.32, v);
	m *= m;   // soft feathered edges, denser cores
	float a = m * max_alpha * (0.4 + 0.6 * amount) * (0.6 + 0.4 * wisps);
	COLOR = vec4(mist_color, a);
}

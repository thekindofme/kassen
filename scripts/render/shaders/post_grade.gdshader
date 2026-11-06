shader_type canvas_item;
render_mode unshaded;
// KASSEN battlefield post-process (scripts/fx/weather.gd). Drawn as a world-space rect covering
// the view at the top z of the world canvas, so the HUD/UI CanvasLayers stay ungraded.
// Order: bloom pick-up -> cloud shadows -> low-lying mist -> filmic grade -> vignette -> grain.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform sampler2D cloud_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D mist_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D height_tex : filter_linear, repeat_disable; // r = height/64, g = water depth
uniform vec2 map_size = vec2(4800.0, 3200.0);
uniform float t = 0.0;
uniform vec2 wind = vec2(16.0, -3.0);

uniform float cloud_strength = 0.2;
uniform float cloud_coverage = 0.5;
uniform float cloud_softness = 0.16;
uniform float cloud_scale = 0.00032;
uniform vec3 cloud_tint : source_color = vec3(0.82, 0.88, 1.0);

uniform float mist_amount = 0.0;
uniform vec3 mist_color : source_color = vec3(0.84, 0.87, 0.86);
uniform float mist_low = 0.12;
uniform float mist_high = 0.75;
uniform float mist_max = 0.62;

uniform float exposure = 1.0;
uniform float contrast = 1.12;
uniform float saturation = 1.0;
uniform float ground_desat = 0.16;
uniform float red_boost = 0.3;
uniform vec3 shadow_tint : source_color = vec3(0.94, 0.96, 1.04);
uniform vec3 highlight_tint : source_color = vec3(1.04, 1.01, 0.95);

uniform float bloom_threshold = 0.72;
uniform float bloom_strength = 0.3;
uniform float vignette = 0.32;
uniform float grain = 0.025;

varying vec2 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

float hash(vec2 p) {
	p = fract(p * vec2(443.897, 441.423));
	p += dot(p, p.yx + 19.19);
	return fract((p.x + p.y) * p.x);
}

void fragment() {
	vec3 c = textureLod(screen_tex, SCREEN_UV, 0.0).rgb;
	// soft bloom from blurred mips, only the bright highlights (flashes, sunlit armour)
	vec3 b = textureLod(screen_tex, SCREEN_UV, 2.0).rgb * 0.45 + textureLod(screen_tex, SCREEN_UV, 4.0).rgb * 0.55;
	float bl = max(max(b.r, b.g), b.b);
	vec3 bloom = b * smoothstep(bloom_threshold, 1.0, bl);

	// drifting cloud shadows (world-anchored, slower than the wind at ground level)
	vec2 cuv = (world + wind * t * 2.5) * cloud_scale;
	float n = texture(cloud_tex, cuv).r * 0.7 + texture(cloud_tex, cuv * 2.7 + vec2(0.31, 0.77)).r * 0.3;
	float sh = smoothstep(cloud_coverage - cloud_softness, cloud_coverage + cloud_softness, n);
	c *= mix(vec3(1.0), cloud_tint * (1.0 - cloud_strength), sh * step(0.001, cloud_strength));

	// low-lying mist: pools in valleys and over the river, slow rolling noise, thins with height
	if (mist_amount > 0.001) {
		vec2 muv = (world + wind * t * 1.4) * 0.0006;
		float m = texture(mist_tex, muv).r * 0.6 + texture(mist_tex, muv * 2.6 - vec2(t * 0.004, 0.0)).r * 0.4;
		vec4 hv = texture(height_tex, world / map_size);
		float low = 1.0 - smoothstep(mist_low, mist_high, hv.r);
		low = max(low, hv.g * 0.9);
		float f = mist_amount * (0.22 + 0.78 * low) * (0.35 + 0.65 * smoothstep(0.25, 0.8, m));
		// soft-light the mist so silhouettes and banners still read through it
		c = mix(c, mix(c * 0.6 + mist_color * 0.55, mist_color, 0.5), clamp(f, 0.0, mist_max));
	}

	c += bloom * bloom_strength;
	c *= exposure;

	// grade toward the art bible: rich lacquer reds, muted vegetation/earth, warm highlights
	float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
	float mx = max(c.r, max(c.g, c.b));
	float mn = min(c.r, min(c.g, c.b));
	float sat = (mx - mn) / (mx + 1e-4);
	float redm = smoothstep(0.3, 0.55, sat) * smoothstep(0.06, 0.2, c.r - max(c.g, c.b));
	float grnm = smoothstep(-0.01, 0.06, c.g - c.b) * smoothstep(0.02, -0.04, c.r - c.g - 0.1) * (1.0 - redm);
	vec3 chroma = (c - l) * saturation * (1.0 + red_boost * redm) * (1.0 - ground_desat * grnm);
	c = l + chroma;
	c *= mix(shadow_tint, highlight_tint, smoothstep(0.08, 0.8, l));
	c = clamp(c, 0.0, 1.0);
	c = mix(c, c * c * (3.0 - 2.0 * c), clamp(contrast - 1.0, -1.0, 1.0));

	// vignette (aspect-correct)
	vec2 d = SCREEN_UV - 0.5;
	d.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	float v = smoothstep(0.35, 1.05, length(d) * 1.25);
	c *= 1.0 - vignette * v;

	// fine film/paper grain, strongest in the midtones
	float g = hash(floor(SCREEN_UV / SCREEN_PIXEL_SIZE) + fract(TIME * 7.0) * vec2(131.0, 71.0)) - 0.5;
	c += g * grain * (0.5 + l * (1.0 - l) * 2.0);
	COLOR = vec4(c, 1.0);
}

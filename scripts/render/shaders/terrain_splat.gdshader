shader_type canvas_item;
// Ground splat shader. 8 seamless materials blended by two RGBA splat maps (one texel per
// 16 px cell, bilinear + noise edge break-up), with macro variation, height shading lit from
// the top-left, animated water and a soft forest-floor darkening.
// Channel order matches Terrain.MATERIALS:
//   splat0: grass, meadow, dirt, forestfloor     splat1: riverbed, sand, mud, paddy

uniform sampler2D splat0 : filter_linear, repeat_disable;
uniform sampler2D splat1 : filter_linear, repeat_disable;
uniform sampler2D height_tex : filter_linear, repeat_disable;  // r height, g water depth, b forest, a ford mask
uniform sampler2D noise_tex : filter_linear, repeat_enable;
uniform sampler2D tex_0 : filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_1 : filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_2 : filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_3 : filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_4 : filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_5 : filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_6 : filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_7 : filter_linear_mipmap, repeat_enable;
uniform vec4 tint_0 : source_color = vec4(1.0);
uniform vec4 tint_1 : source_color = vec4(1.0);
uniform vec4 tint_2 : source_color = vec4(1.0);
uniform vec4 tint_3 : source_color = vec4(1.0);
uniform vec4 tint_4 : source_color = vec4(1.0);
uniform vec4 tint_5 : source_color = vec4(1.0);
uniform vec4 tint_6 : source_color = vec4(1.0);
uniform vec4 tint_7 : source_color = vec4(1.0);
uniform float placeholder_0 = 0.0;
uniform float placeholder_1 = 0.0;
uniform float placeholder_2 = 0.0;
uniform float placeholder_3 = 0.0;
uniform float placeholder_4 = 0.0;
uniform float placeholder_5 = 0.0;
uniform float placeholder_6 = 0.0;
uniform float placeholder_7 = 0.0;
uniform vec2 map_size = vec2(4800.0, 3200.0);
uniform vec2 grid_size = vec2(300.0, 200.0);
uniform float tile_world = 384.0;
uniform float height_light = 13.0;
uniform float crest_light = 0.9;   // rim highlight on convex crests / shade in hollows

vec3 mat_sample(sampler2D t, vec4 tint, float ph, vec2 uv) {
	// two scales, mixed by macro noise, hide tiling
	vec3 a = texture(t, uv).rgb;
	vec3 b = texture(t, uv * 0.37 + vec2(0.31, 0.17)).rgb;
	vec3 c = mix(a, b, 0.35);
	vec3 placeholder = tint.rgb * (0.70 + 0.62 * (c.r - 0.5) + 0.3);
	return mix(c * tint.rgb, placeholder, ph);
}

void fragment() {
	vec2 world = UV * map_size;
	vec2 tuv = world / tile_world;
	vec4 nz = texture(noise_tex, world / 2200.0);
	vec4 nz2 = texture(noise_tex, world / 420.0 + vec2(0.5));
	// splat edge break-up: offset by up to ~1.5 cells
	vec2 suv = UV + (nz2.rg - 0.5) * (2.5 / grid_size);
	vec4 s0 = texture(splat0, suv);
	vec4 s1 = texture(splat1, suv);
	// sharpen transitions a little using the detail noise as a height-blend
	s0 = pow(s0, vec4(1.35));
	s1 = pow(s1, vec4(1.35));
	float tot = dot(s0, vec4(1.0)) + dot(s1, vec4(1.0)) + 0.0001;

	vec3 col = vec3(0.0);
	col += mat_sample(tex_0, tint_0, placeholder_0, tuv) * s0.r;
	col += mat_sample(tex_1, tint_1, placeholder_1, tuv * 1.1) * s0.g;
	col += mat_sample(tex_2, tint_2, placeholder_2, tuv * 1.6) * s0.b;
	col += mat_sample(tex_3, tint_3, placeholder_3, tuv * 1.3) * s0.a;
	vec2 flow = vec2(0.0, TIME * 0.012);
	col += mat_sample(tex_4, tint_4, placeholder_4, tuv * 0.9 + flow) * s1.r;
	col += mat_sample(tex_5, tint_5, placeholder_5, tuv * 1.4) * s1.g;
	col += mat_sample(tex_6, tint_6, placeholder_6, tuv * 1.5) * s1.b;
	col += mat_sample(tex_7, tint_7, placeholder_7, tuv * 1.2) * s1.a;
	col /= tot;

	vec4 hw = texture(height_tex, UV);
	vec3 ground = col;   // splat colour before the water tint (fords reuse it)
	// water: deepen, cool and ripple
	float depth = smoothstep(0.15, 1.0, hw.g);
	float ripple = sin(world.x * 0.045 + world.y * 0.02 + TIME * 1.7) * sin(world.y * 0.05 - TIME * 1.1);
	vec3 water = mix(col, vec3(0.20, 0.31, 0.35), 0.55 * depth) + ripple * 0.025 * depth;
	water += smoothstep(0.55, 0.95, nz2.b) * 0.05 * depth;
	col = mix(col, water, step(0.01, hw.g));

	// fords: visibly shallow. Turquoise film over sand and pebbles, a gravel causeway down the
	// centre, foam lines where the shallows meet deep water, wet sand fading out on the banks.
	float ford = hw.a;
	if (ford > 0.005) {
		float fm = clamp(ford + (nz2.r - 0.5) * 0.2, 0.0, 1.0);   // organic edges
		float wet = smoothstep(0.01, 0.12, hw.g);
		vec3 sandc = mat_sample(tex_5, tint_5, placeholder_5, tuv * 1.4);
		float peb = smoothstep(0.55, 0.68, texture(noise_tex, world / 45.0).r);
		float peb2 = smoothstep(0.58, 0.7, texture(noise_tex, world / 21.0 + vec2(0.37)).g);
		// gravel bed: the splat's sand/riverbed with pebble specks, a paler causeway down the middle
		vec3 gravel = mix(ground, sandc, 0.2) * (0.9 + 0.18 * peb - 0.16 * peb2);
		float causeway = smoothstep(0.72, 0.9, fm);
		gravel = mix(gravel, sandc * (0.95 + 0.25 * peb) + vec3(0.03, 0.025, 0.0), causeway * 0.6);
		// thin turquoise film with moving sun glints
		float rip2 = sin(world.x * 0.07 - world.y * 0.03 + TIME * 2.2) * sin(world.y * 0.09 + TIME * 1.3);
		vec3 shallow = mix(gravel, vec3(0.33, 0.56, 0.55), 0.38 * (1.0 - causeway * 0.7)) * (0.95 + causeway * 0.1);
		shallow += ripple * 0.02 + vec3(0.05, 0.07, 0.07) * smoothstep(0.6, 0.95, rip2) * (0.4 + 0.6 * nz2.b);
		// broken foam line where the shallows drop into the deep channel
		float edge = smoothstep(0.16, 0.24, fm) * (1.0 - smoothstep(0.3, 0.4, fm));
		float fn = texture(noise_tex, vec2(world.x / 70.0, world.y / 16.0) + vec2(TIME * 0.015, 0.0)).r;
		float fn2 = texture(noise_tex, world / 26.0 - vec2(0.0, TIME * 0.01)).g;
		float foam = edge * smoothstep(0.36, 0.7, fn * 0.7 + fn2 * 0.5);
		shallow = mix(shallow, vec3(0.88, 0.92, 0.9), foam * 0.75 * wet);
		vec3 wet_sand = mix(col, sandc, 0.4) * 0.84;
		col = mix(col, mix(wet_sand, shallow, wet), smoothstep(0.1, 0.5, fm));
	}

	// height shading (light from top-left)
	vec2 texel = 1.0 / grid_size;
	float hl = texture(height_tex, UV - vec2(texel.x, 0.0)).r;
	float hr = texture(height_tex, UV + vec2(texel.x, 0.0)).r;
	float hu = texture(height_tex, UV - vec2(0.0, texel.y)).r;
	float hd = texture(height_tex, UV + vec2(0.0, texel.y)).r;
	// slopes rising toward the bottom-right face the top-left sun -> brighter (matches prop shadows)
	float slope_light = ((hr - hl) + (hd - hu)) * height_light;
	// wider-baseline slope for a softer, readable relief at far zoom
	vec2 t2 = texel * 3.0;
	float sl2 = ((texture(height_tex, UV + vec2(t2.x, 0.0)).r - texture(height_tex, UV - vec2(t2.x, 0.0)).r)
		+ (texture(height_tex, UV + vec2(0.0, t2.y)).r - texture(height_tex, UV - vec2(0.0, t2.y)).r)) * height_light * 0.45;
	float relief = clamp(slope_light * 0.6 + sl2, -0.2, 0.26);
	// crest rim light / hollow shade from the height laplacian (convex = brighter)
	float lap = (hl + hr + hu + hd) * 0.25 - hw.r;
	float crest = clamp(-lap * 60.0 * crest_light, -0.12, 0.14) * smoothstep(0.08, 0.3, hw.r);
	col *= 1.0 + relief;
	col += col * crest + vec3(0.05, 0.045, 0.02) * max(crest, 0.0);
	col *= 1.0 + hw.r * 0.12;

	// forest floor darkening under canopies, macro variation
	col *= 1.0 - hw.b * 0.18;
	col *= mix(0.9, 1.07, nz.r);
	COLOR = vec4(col, 1.0);
}

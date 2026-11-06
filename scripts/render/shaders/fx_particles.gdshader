shader_type canvas_item;
render_mode blend_premul_alpha, unshaded;
// KASSEN battle particles: stateless, analytic GPU particles in one MultiMesh (scripts/fx/fx_pool.gd).
// The CPU writes an instance once at spawn; motion, growth and fading are evaluated here from age.
// Instance layout. Godot applies the instance transform (identity basis, origin = spawn point)
// AFTER vertex(), so all motion below is computed as a local offset from the spawn point:
//   COLOR           = (kind, texture layer, seed 0..1, life seconds)
//   INSTANCE_CUSTOM = (v0.x, v0.y, t0 wrapped to [0,64), size px)
// Textures are premultiplied; an output alpha of 0 makes a kind purely additive (flash/spark/glow).

uniform sampler2DArray tex : filter_linear_mipmap, repeat_disable;
uniform float fx_time = 0.0;          // sim time wrapped to [0, 64)
uniform vec2 wind = vec2(16.0, -3.0); // world px / s
uniform float smoke_alpha = 0.6;
uniform float dust_alpha = 0.3;
uniform vec3 smoke_color : source_color = vec3(0.90, 0.89, 0.86);
uniform vec3 dust_color : source_color = vec3(0.64, 0.53, 0.39);

varying vec4 v_col;
varying vec3 v_uvl;

vec2 rot(vec2 p, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(p.x * c - p.y * s, p.x * s + p.y * c);
}

// drag-damped launch velocity that hands over to the wind: integral of v(t) = w + (v0 - w) e^{-kt}
vec2 drift(vec2 v0, vec2 w, float k, float a) {
	float e = (1.0 - exp(-k * a)) / k;
	return v0 * e + w * (a - e);
}

void vertex() {
	int kind = int(COLOR.r + 0.5);
	float layer = COLOR.g;
	float seed = COLOR.b;
	float life = COLOR.a;
	vec2 v0 = INSTANCE_CUSTOM.xy;
	float size = INSTANCE_CUSTOM.w;
	float age = mod(fx_time - INSTANCE_CUSTOM.z + 64.0, 64.0);
	vec2 corner = UV - 0.5;
	vec2 off = vec2(0.0);
	vec2 dim = vec2(size);
	float ang = seed * 6.2832;
	vec3 col = vec3(1.0);
	float a = 0.0;
	float additive = 0.0;
	bool alive = life > 0.0 && age < life;
	if (alive) {
		float fin = 1.0 - smoothstep(life * 0.35, life, age);
		if (kind == 0) { // matchlock smoke: muzzle blast, billow, hand over to wind, rise
			float g = 1.0 + 2.2 * (1.0 - exp(-age / 2.0));
			// per-puff wind speed varies with seed, so the bank slowly shears downwind;
			// top-down view: only a few px of "rise", the rest is expansion and fade
			off = drift(v0, wind * (0.55 + 0.9 * seed), 1.7, age) + vec2(0.0, -5.0 * (1.0 - exp(-age * 0.45)));
			off += vec2(sin(age * 0.6 + seed * 21.0), cos(age * 0.45 + seed * 13.0)) * 3.0 * sqrt(age);
			dim = vec2(size * 1.3, size) * g;
			ang += age * (seed - 0.5) * 0.18;
			float hot = 1.0 - smoothstep(0.0, 0.22, age);
			col = mix(smoke_color * (0.86 + 0.2 * seed), vec3(1.0, 0.78, 0.5), hot * 0.7);
			a = smoke_alpha * smoothstep(0.0, 0.15, age) * fin * clamp(1.3 / sqrt(g), 0.0, 1.0) * (0.6 + 0.4 * fract(seed * 7.13));
		} else if (kind == 1 || kind == 4) { // dust (1) / impact puff (4)
			float tau = kind == 1 ? 0.9 : 0.3;
			float gr = kind == 1 ? 1.9 : 1.3;
			float g = 1.0 + gr * (1.0 - exp(-age / tau));
			off = drift(v0, wind * 0.6, 2.4, age) + vec2(0.0, -8.0 * (1.0 - exp(-age)));
			dim = vec2(size * 1.3, size) * g;
			ang += age * (seed - 0.5) * 0.4;
			col = dust_color * (0.82 + 0.3 * seed);
			a = dust_alpha * smoothstep(0.0, 0.08, age) * fin * (kind == 4 ? 1.6 : 1.0);
		} else if (kind == 2 || kind == 3 || kind == 6) { // ballistic drops: blood, water, sparks
			float vz = (kind == 3 ? 95.0 : 70.0) + 70.0 * seed;
			float h = kind == 3 ? 0.0 : (kind == 2 ? 16.0 : 22.0);
			float z = vz * age - 210.0 * age * age;
			alive = z > -h;
			off = v0 * age + vec2(0.0, -z);
			vec2 vel = v0 + vec2(0.0, -(vz - 420.0 * age));
			ang = atan(vel.y, vel.x);
			float stretch = kind == 6 ? 3.5 : 1.6;
			dim = vec2(size * stretch, size);
			if (kind == 2) {
				col = vec3(0.40, 0.025, 0.02) * (0.8 + 0.4 * seed);
				a = 0.95;
			} else if (kind == 3) {
				col = vec3(0.86, 0.92, 0.96);
				a = 0.75 * fin;
			} else {
				col = mix(vec3(1.0, 0.92, 0.65), vec3(1.0, 0.38, 0.1), age / life) * 1.6;
				a = 1.0 - age / life;
				additive = 1.0;
			}
		} else if (kind == 5) { // muzzle flash, aimed along v0, core sits on the muzzle
			vec2 d = normalize(v0 + vec2(1e-4, 0.0));
			ang = atan(d.y, d.x);
			float k = age / life;
			dim = vec2(size * 2.0, size) * (0.8 + 0.5 * k);
			off = d * size * 0.45;
			col = vec3(1.25);
			a = 1.0 - k * k;
			additive = 1.0;
		} else if (kind == 7) { // warm glow (muzzle light, charge spark bloom)
			float k = age / life;
			dim = vec2(size * 1.4, size) * (0.7 + 0.6 * k);
			col = vec3(1.0, 0.62, 0.28);
			a = 0.55 * (1.0 - k);
			additive = 1.0;
			ang = 0.0;
		} else if (kind == 8) { // water ring on the surface
			float k = age / life;
			dim = vec2(size * 1.6, size * 0.7) * (0.4 + 1.2 * k);
			col = vec3(0.88, 0.94, 0.97);
			a = 0.7 * (1.0 - k);
			ang = 0.0;
		}
	}
	if (!alive) {
		VERTEX = vec2(0.0);
		v_col = vec4(0.0);
	} else {
		VERTEX = off + rot(corner * dim, ang);
		// additive kinds: premultiplied colour with zero alpha adds onto the screen
		v_col = vec4(col * a, a * (1.0 - additive));
	}
	v_uvl = vec3(UV, layer);
}

void fragment() {
	vec4 t = texture(tex, v_uvl);
	COLOR = vec4(t.rgb * v_col.rgb, t.a * v_col.a);
}

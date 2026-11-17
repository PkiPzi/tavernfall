shader_type spatial;
// Blends two BG3 terrain materials (A everywhere, B where the mask says so, e.g. rough ground or a road).
// World-space UVs, two scales mixed by noise so the repeat does not show, B edges broken up by noise.

uniform sampler2D col_a : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D nrm_a : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D col_b : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D nrm_b : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D mask : repeat_disable, filter_linear_mipmap;
uniform vec2 field_origin = vec2(0.0);
uniform vec2 field_size = vec2(24.0, 18.0);
uniform float tile = 4.0;       // metres covered by one texture repeat
uniform float normal_strength = 1.0;
uniform float roughness_val = 0.85;
uniform vec3 tint : source_color = vec3(1.0);
uniform sampler2D relief : repeat_disable, filter_linear;  // ground height in metres over the playing field, flat outside it
uniform float relief_on = 0.0;

varying vec2 wp;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) { return 0.5 * vnoise(p) + 0.3 * vnoise(p * 2.1) + 0.2 * vnoise(p * 4.3); }

float rel(vec2 w) { return textureLod(relief, (w - field_origin) / field_size, 0.0).r; }

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	if (relief_on > 0.5) {
		VERTEX.y += rel(wp);
		float e = 0.4;
		float hx = rel(wp + vec2(e, 0.0)) - rel(wp - vec2(e, 0.0));
		float hz = rel(wp + vec2(0.0, e)) - rel(wp - vec2(0.0, e));
		NORMAL = normalize(vec3(-hx / (2.0 * e), 1.0, -hz / (2.0 * e)));
	}
}

vec3 sample_col(sampler2D t, vec2 uv, float n) {
	vec3 c1 = texture(t, uv).rgb;
	vec3 c2 = texture(t, uv * 0.31 + vec2(0.37, 0.71)).rgb;  // a second, larger scale hides the repeat
	return mix(c1, c2, 0.35 * smoothstep(0.3, 0.7, n));
}
vec3 sample_nrm(sampler2D t, vec2 uv) {
	vec4 s = texture(t, uv);
	vec2 xy = vec2(s.a, s.g) * 2.0 - 1.0;  // BG3 stores x in alpha, y in green
	xy.y = -xy.y;                           // DirectX green-down to OpenGL
	xy *= normal_strength;
	float z = sqrt(max(1.0 - dot(xy, xy), 0.0));
	return vec3(xy, z);
}

void fragment() {
	vec2 uv = wp / tile;
	float n = fbm(wp * 0.35);
	vec2 muv = (wp - field_origin) / field_size;
	float m = textureLod(mask, clamp(muv, vec2(0.0), vec2(1.0)), 0.0).r;
	m = smoothstep(0.40, 0.55, m + (fbm(wp * 0.9) - 0.5) * 0.55);
	vec3 a = sample_col(col_a, uv, n);
	vec3 b = sample_col(col_b, uv * 1.3, n);
	vec3 c = mix(a, b, m);
	// large soft colour variation, like the game's terrain blending
	c *= mix(0.82, 1.12, fbm(wp * 0.12 + 7.0));
	// a fine-grained third look at the same texture, so the ground still has detail when the camera comes close
	float grain = dot(texture(col_a, wp / (tile * 0.17)).rgb, vec3(0.333));
	c *= mix(1.0, clamp(grain * 1.9, 0.6, 1.4), 0.32);
	ALBEDO = c * tint;
	vec3 nn = mix(sample_nrm(nrm_a, uv), sample_nrm(nrm_b, uv * 1.3), m);
	NORMAL_MAP = nn * 0.5 + 0.5;
	// polished in places, rough in others, so reflections break up like worn stone or wet boards
	float wear = fbm(wp * 0.7 + 3.0);
	ROUGHNESS = clamp(roughness_val + (wear - 0.5) * 0.55 - (1.0 - roughness_val) * 0.2 * smoothstep(0.55, 0.8, fbm(wp * 0.25)), 0.12, 1.0);
	SPECULAR = 0.65;
}

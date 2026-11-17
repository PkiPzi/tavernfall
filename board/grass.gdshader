shader_type spatial;
// Blades of grass: base colour at the root, lighter at the tip, instance colour for variety, a slow wind sway.
render_mode cull_disabled;

uniform vec3 base_col : source_color = vec3(0.10, 0.20, 0.05);
uniform vec3 tip_col : source_color = vec3(0.50, 0.58, 0.20);
uniform float sway = 0.07;
uniform float blade_h = 0.4;

varying float h;

void vertex() {
	h = clamp(VERTEX.y / blade_h, 0.0, 1.0);
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float gust = sin(TIME * 1.5 + w.x * 0.7 + w.z * 0.5) + 0.5 * sin(TIME * 2.7 + w.x * 1.9);
	VERTEX.x += gust * sway * h * h;
	VERTEX.z += gust * sway * 0.5 * h * h;
}

void fragment() {
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);  // every blade is lit like the ground under it, so the far side of a tuft is not a dark cone
	ALBEDO = mix(base_col, tip_col, h) * COLOR.rgb;
	ROUGHNESS = 0.85;
	SPECULAR = 0.2;
	BACKLIGHT = vec3(0.12, 0.2, 0.05) * h;
}

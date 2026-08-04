shader_type spatial;
render_mode unshaded, blend_mix, depth_prepass_alpha, cull_disabled;

// The original DAO mesh supplies the shoreline and elevation. Surface detail is
// generated in world space so a very large lake cannot expose stretched mesh UVs.
uniform vec4 deep_color : source_color = vec4(0.025, 0.105, 0.145, 0.91);
uniform vec4 shallow_color : source_color = vec4(0.12, 0.31, 0.32, 0.82);
uniform vec4 sky_tint : source_color = vec4(0.28, 0.43, 0.55, 1.0);
uniform float wave_strength : hint_range(0.0, 1.0) = 0.34;
uniform float surface_scale = 0.085;

varying vec3 world_position;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0)), f.x), f.y);
}

float water_height(vec2 p, float t) {
	float broad = sin(p.x * 0.72 + p.y * 0.46 + t * 0.62) * 0.48;
	broad += sin(p.x * -0.31 + p.y * 1.03 - t * 0.43) * 0.30;
	float detail = value_noise(p * 1.8 + vec2(t * 0.19, -t * 0.12)) * 2.0 - 1.0;
	detail += (value_noise(p * 4.7 + vec2(-t * 0.12, t * 0.16)) * 2.0 - 1.0) * 0.34;
	return broad + detail * 0.31;
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_position.xz * surface_scale;
	float t = TIME;
	float h = water_height(p, t);
	float eps = 0.075;
	float hx = water_height(p + vec2(eps, 0.0), t) - h;
	float hz = water_height(p + vec2(0.0, eps), t) - h;
	vec3 generated_normal = normalize(vec3(-hx * wave_strength, 1.0, -hz * wave_strength));
	vec3 view_normal = normalize((VIEW_MATRIX * vec4(generated_normal, 0.0)).xyz);

	float fresnel = pow(1.0 - clamp(dot(view_normal, normalize(VIEW)), 0.0, 1.0), 4.0);
	float variation = clamp(h * 0.075 + 0.48, 0.0, 1.0);
	vec3 base = mix(deep_color.rgb, shallow_color.rgb, variation);
	base = mix(base, sky_tint.rgb, fresnel * 0.48);

	ALBEDO = base;
	ROUGHNESS = mix(0.22, 0.08, fresnel);
	METALLIC = 0.0;
	SPECULAR = 0.72;
	NORMAL = view_normal;
	ALPHA = mix(deep_color.a, shallow_color.a, 0.42) + fresnel * 0.05;
}

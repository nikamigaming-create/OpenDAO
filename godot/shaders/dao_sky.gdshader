shader_type sky;

uniform vec3 zenith_color = vec3(0.055, 0.135, 0.275);
uniform vec3 horizon_color = vec3(0.34, 0.44, 0.56);
uniform vec3 cloud_light = vec3(0.96, 0.94, 0.88);
uniform vec3 cloud_mid = vec3(0.64, 0.67, 0.70);
uniform vec3 cloud_shadow = vec3(0.27, 0.32, 0.39);
uniform vec3 sun_color = vec3(1.0, 0.76, 0.42);
uniform vec3 sun_direction = vec3(0.0, 0.7, 0.7);
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.55;
uniform float cloud_speed = 0.0022;
uniform float cloud_density : hint_range(0.0, 2.0) = 1.0;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.52;
	mat2 octave = mat2(vec2(1.67, 1.13), vec2(-1.13, 1.67));
	for (int i = 0; i < 5; i++) {
		value += noise2(p) * amplitude;
		p = octave * p + vec2(7.1, -3.8);
		amplitude *= 0.5;
	}
	return value;
}

float cloud_field(vec2 p) {
	float body = fbm(p);
	float detail = fbm(p * 2.37 + vec2(13.7, -9.2));
	return body * 0.80 + detail * 0.20;
}

void sky() {
	vec3 ray = normalize(EYEDIR);
	vec3 sun_dir = normalize(sun_direction);
	float elevation = clamp(ray.y, -0.2, 1.0);
	float atmospheric_height = pow(smoothstep(-0.12, 0.90, elevation), 0.70);
	vec3 color = mix(horizon_color, zenith_color, atmospheric_height);

	float facing_sun = max(dot(ray, sun_dir), 0.0);
	float sun_disc = smoothstep(0.99945, 0.99982, facing_sun);
	float sun_glow = pow(facing_sun, 18.0) * 0.17;
	color += sun_color * (sun_disc * 2.6 + sun_glow);

	float plane_height = max(ray.y + 0.28, 0.11);
	vec2 projected = ray.xz / plane_height;
	vec2 wind = vec2(TIME * cloud_speed, TIME * cloud_speed * -0.64);
	vec2 p = projected * 1.42 + wind;
	float field = cloud_field(p);
	float sun_sample = cloud_field(p + sun_dir.xz * 0.18);
	float shadowing = clamp((field - sun_sample) * 4.8 + 0.48, 0.0, 1.0);
	float mask = smoothstep(cloud_coverage, cloud_coverage + 0.135, field) * cloud_density;
	mask *= smoothstep(0.015, 0.15, ray.y);
	float dense_core = smoothstep(cloud_coverage + 0.08, cloud_coverage + 0.22, field);
	vec3 cloud_color = mix(cloud_shadow, cloud_mid, shadowing);
	cloud_color = mix(cloud_color, cloud_light, (1.0 - dense_core) * 0.48 + shadowing * 0.28);
	float silver_lining = pow(facing_sun, 9.0) * mask * (1.0 - dense_core);
	cloud_color += sun_color * silver_lining * 0.42;
	color = mix(color, cloud_color, clamp(mask * 0.92, 0.0, 0.92));

	float cirrus = smoothstep(0.70, 0.86, fbm(projected * 4.8 - wind * 1.8));
	color = mix(color, cloud_light, cirrus * 0.13 * smoothstep(0.08, 0.3, ray.y));
	COLOR = color;
}

shader_type sky;
// Daylight sky: gradient, sun disc with glow, and soft procedural clouds.
// Static (no TIME), so the radiance map is only computed once.

uniform vec3 top_color : source_color = vec3(0.16, 0.36, 0.72);
uniform vec3 horizon_color : source_color = vec3(0.66, 0.78, 0.9);
uniform vec3 ground_color : source_color = vec3(0.32, 0.36, 0.3);
uniform vec3 cloud_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 cloud_shade : source_color = vec3(0.62, 0.68, 0.78);
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.45;
uniform float sun_size = 0.9994;
uniform float haze = 1.0;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int k = 0; k < 5; k++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 d = EYEDIR;
	float h = d.y;
	vec3 col;
	if (h >= 0.0) {
		col = mix(horizon_color, top_color, pow(h, 0.45));
		// Clouds on a plane above the world.
		vec2 uv = d.xz / (h + 0.09) * 0.55;
		float c = fbm(uv * 1.3);
		float detail = fbm(uv * 4.5 + vec2(3.1, 7.7));
		float shape = smoothstep(1.0 - cloud_cover - 0.08, 1.0 - cloud_cover + 0.22, c * 0.85 + detail * 0.25);
		vec3 cc = mix(cloud_shade, cloud_color, smoothstep(0.35, 0.8, detail));
		col = mix(col, cc, shape * smoothstep(0.0, 0.12, h) * 0.95);
		// Haze near the horizon.
		col = mix(col, horizon_color * 1.05, (1.0 - smoothstep(0.0, 0.18, h)) * 0.55 * haze);
	} else {
		col = mix(horizon_color, ground_color, smoothstep(0.0, 0.25, -h));
	}
	// Sun.
	float sd = dot(d, LIGHT0_DIRECTION);
	col += LIGHT0_COLOR * (smoothstep(sun_size, sun_size + 0.0003, sd) * 6.0 + pow(max(sd, 0.0), 220.0) * 0.6 + pow(max(sd, 0.0), 12.0) * 0.12);
	COLOR = col;
}

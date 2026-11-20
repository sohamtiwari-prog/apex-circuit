shader_type spatial;
// Open water for the boat courses (scripts/water.gd): the swell the boats
// ride (the same four waves as Water.height), fine drifting ripples on top,
// the sky and sun reflected in it, lighter on the crests, whitecaps on the
// steepest ones.
render_mode cull_disabled;

uniform vec3 deep : source_color = vec3(0.02, 0.13, 0.17);
uniform vec3 shallow : source_color = vec3(0.05, 0.3, 0.32);
uniform sampler2D ripples : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 waves[4];          // kx, kz, amplitude, omega
uniform vec4 phases;
uniform float wave_time;
uniform float level;

varying vec3 wpos;
varying float near;

float swell(vec2 p, out vec2 slope) {
	float h = 0.0;
	slope = vec2(0.0);
	for (int i = 0; i < 4; i++) {
		vec4 w = waves[i];
		float ph = w.x * p.x + w.y * p.y - w.w * wave_time + phases[i];
		h += w.z * sin(ph);
		slope += w.z * cos(ph) * w.xy;
	}
	return h;
}

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float d = length(VERTEX.xz);
	// The swell's shape near the camera; beyond, only its shading.
	near = 1.0 - smoothstep(80.0, 320.0, d);
	vec2 sl;
	float h = swell(world.xz, sl);
	VERTEX.y += h * near;
	wpos = world;
	wpos.y = level + h * near;
}

void fragment() {
	vec2 sl;
	float h = swell(wpos.xz, sl);
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	float far = smoothstep(150.0, 1400.0, dist);
	// Fine ripples: two layers drifting different ways.
	float t = wave_time;
	vec3 r1 = texture(ripples, wpos.xz * 0.07 + vec2(t * 0.018, t * 0.011)).xyz * 2.0 - 1.0;
	vec3 r2 = texture(ripples, wpos.xz * 0.19 - vec2(t * 0.023, -t * 0.031)).xyz * 2.0 - 1.0;
	vec2 rip = (r1.xy * 0.5 + r2.xy * 0.5) * mix(0.3, 0.1, far);
	vec2 s = sl * mix(1.0, 0.35, far) + rip;
	vec3 n = normalize(vec3(-s.x, 1.0, -s.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);

	// Lighter and greener where the water is thin at a crest, and looking
	// down into it; darker in the troughs and at a glance.
	float amp = waves[0].z + waves[1].z + waves[2].z + waves[3].z + 0.0001;
	float crest = clamp(h / amp * 0.5 + 0.5, 0.0, 1.0);
	vec3 view = normalize(CAMERA_POSITION_WORLD - wpos);
	float look_down = clamp(view.y, 0.0, 1.0);
	vec3 col = mix(deep, shallow, clamp(crest * 0.75 + look_down * 0.35 - 0.15, 0.0, 1.0));
	// Whitecaps: only on the tallest, steepest crests, broken up by the ripples.
	float steep = length(sl);
	float cap = smoothstep(0.84, 0.98, crest) * smoothstep(0.11, 0.17, steep) * smoothstep(0.2, 0.6, r1.x + r2.y * 0.5);
	col = mix(col, vec3(0.8, 0.86, 0.88), cap * 0.45 * (1.0 - far));
	ALBEDO = col;
	ROUGHNESS = mix(0.035, 0.22, far) + cap * 0.4;
	METALLIC = 0.0;
	SPECULAR = 0.55;
}

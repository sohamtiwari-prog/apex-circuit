shader_type spatial;
// Open water (scripts/water.gd): six trochoidal (Gerstner) waves - the same
// ones the boats float on - with sharp crests and broad troughs; fine
// drifting ripples; the sky and sun reflected; light glowing through the
// crests when you look towards the sun; whitecaps on the steepest crests;
// and, where there's a shore, water turning clear and green over the
// shallows and breaking into foam at its edge.
render_mode cull_disabled;

uniform vec3 deep : source_color = vec3(0.015, 0.11, 0.15);
uniform vec3 shallow : source_color = vec3(0.05, 0.3, 0.32);
uniform vec3 shoal : source_color = vec3(0.42, 0.5, 0.36);
uniform sampler2D ripples : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D foam_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D ground : filter_linear, repeat_disable;
uniform vec4 ground_rect = vec4(0.0, 0.0, 1.0, 1.0);   // x0, z0, width, depth
uniform vec2 ground_texel = vec2(1.0);
uniform float has_ground = 0.0;
uniform vec4 waves[6];          // dir x, dir z, k, amplitude
uniform vec4 wave_params[6];    // omega, phase, q (peaking)
uniform float wave_time;
uniform float level;
uniform float rough = 1.0;      // how rough today (bigger waves: more whitecaps)
uniform vec3 sun_dir = vec3(0.4, 0.7, 0.3);   // towards the sun
// What the water mirrors low down: the shore round it (hills or the town),
// not sky.
uniform vec3 surround : source_color = vec3(0.12, 0.17, 0.13);
uniform float surround_cover = 0.0;

varying vec3 rest;              // where this water sits at rest (world)
varying float near;

// The water at rest at p, now: its shift (xz) and height (y); and the two
// tangents of the surface (for the normal).
vec3 gerstner(vec2 p, float fade, out vec3 tx, out vec3 tz) {
	vec3 o = vec3(0.0);
	tx = vec3(1.0, 0.0, 0.0);
	tz = vec3(0.0, 0.0, 1.0);
	for (int i = 0; i < 6; i++) {
		vec4 w = waves[i];
		vec4 pr = wave_params[i];
		float th = w.z * dot(w.xy, p) - pr.x * wave_time + pr.y;
		float s = sin(th);
		float c = cos(th);
		float a = w.w * fade;
		float qa = pr.z * a;
		o.x -= qa * w.x * s;
		o.z -= qa * w.y * s;
		o.y += a * c;
		float wa = w.z * a;
		float wq = w.z * qa;
		tx += vec3(-wq * w.x * w.x * c, -wa * w.x * s, -wq * w.x * w.y * c);
		tz += vec3(-wq * w.x * w.y * c, -wa * w.y * s, -wq * w.y * w.y * c);
	}
	return o;
}

float bed(vec2 xz) {
	vec2 uv = (xz - ground_rect.xy) / ground_rect.zw;
	uv = uv * (1.0 - ground_texel) + ground_texel * 0.5;
	return texture(ground, uv).r;
}

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float d = length(VERTEX.xz);
	// The swell's shape near the camera; beyond, only its shading.
	near = 1.0 - smoothstep(90.0, 360.0, d);
	vec3 tx;
	vec3 tz;
	vec3 o = gerstner(world.xz, near, tx, tz);
	VERTEX += o;
	rest = world;
}

void fragment() {
	float dist = length(rest - CAMERA_POSITION_WORLD);
	float far = smoothstep(150.0, 1400.0, dist);
	vec3 tx;
	vec3 tz;
	vec3 o = gerstner(rest.xz, 1.0 - far * 0.65, tx, tz);
	vec3 wp = rest + o;
	vec3 n = normalize(cross(tz, tx));
	// Fine ripples: two layers drifting different ways.
	float t = wave_time;
	vec3 r1 = texture(ripples, rest.xz * 0.07 + vec2(t * 0.018, t * 0.011)).xyz * 2.0 - 1.0;
	vec3 r2 = texture(ripples, rest.xz * 0.19 - vec2(t * 0.023, -t * 0.031)).xyz * 2.0 - 1.0;
	vec2 rip = (r1.xy * 0.5 + r2.xy * 0.5) * mix(0.28, 0.08, far);
	n = normalize(n + vec3(rip.x, 0.0, rip.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);

	// The water's colour: deeper blue in the troughs and at a glance, lighter
	// and greener up the crests and looking down into it.
	float amp = waves[0].w + waves[1].w + waves[2].w + waves[3].w + 0.0001;
	float crest = clamp(o.y / amp * 0.5 + 0.5, 0.0, 1.0);
	vec3 view = normalize(CAMERA_POSITION_WORLD - wp);
	float look_down = clamp(view.y, 0.0, 1.0);
	vec3 col = mix(deep, shallow, clamp(crest * 0.7 + look_down * 0.35 - 0.15, 0.0, 1.0));
	// Light through the crests, looking towards the sun.
	vec2 to_sun = normalize(sun_dir.xz + vec2(0.0001));
	vec2 look = normalize(-view.xz + vec2(0.0001));
	float back = pow(clamp(dot(look, to_sun) * 0.5 + 0.5, 0.0, 1.0), 4.0);
	col += shallow * 1.3 * back * smoothstep(0.55, 1.0, crest) * (1.0 - far);
	// Whitecaps: on the tallest, steepest crests, more when it's rough.
	float steep = 1.0 - n.y;
	float foam_n = texture(foam_tex, rest.xz * 0.11 + vec2(t * 0.02, 0.0)).r;
	float cap = smoothstep(0.86 - 0.08 * (rough - 1.0), 1.0, crest) * smoothstep(0.012, 0.04, steep * rough) * smoothstep(0.35, 0.75, foam_n);
	float foam = cap * 0.55 * (1.0 - far);
	// Shallows and the water's edge.
	if (has_ground > 0.5) {
		float depth = level - bed(rest.xz);
		float shoaling = 1.0 - smoothstep(0.0, 5.0, depth);
		col = mix(col, shoal, shoaling * 0.75);
		// Foam where it laps the shore: bands running in with the swell.
		float edge = 1.0 - smoothstep(0.0, 0.9, depth - o.y * 1.5);
		float lap = 0.5 + 0.5 * sin(depth * 7.0 - t * 1.6 + foam_n * 3.0);
		foam = max(foam, edge * smoothstep(0.25, 0.75, foam_n * 0.7 + lap * 0.5));
	}
	// Glancing reflections that would meet the shore show the shore.
	float rv = reflect(-view, n).y;
	float shore = surround_cover * (1.0 - smoothstep(0.015, 0.12, rv));
	float fres = 0.02 + 0.98 * pow(1.0 - clamp(dot(n, view), 0.0, 1.0), 5.0);
	col = mix(col, surround, clamp(shore * fres * 1.6, 0.0, 0.85));
	col = mix(col, vec3(0.86, 0.9, 0.92), clamp(foam, 0.0, 1.0));
	ALBEDO = col;
	ROUGHNESS = mix(0.03, 0.2, far) + foam * 0.5;
	METALLIC = 0.0;
	SPECULAR = mix(0.55, 0.2, foam) * (1.0 - shore * 0.8);
}

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
uniform float night = 0.0;       // stars, no sun disc (the light is the floodlights)
// The far horizon, drawn into the sky (it is too far away to move as the
// cars do): 0 none, 1 mountains, 2 hills, 3 a city skyline.
uniform int horizon_kind = 0;
uniform float horizon_height = 0.0;      // tallest point (radians above the horizon)
uniform vec3 horizon_tint : source_color = vec3(0.3, 0.36, 0.3);
uniform float snow = 0.0;               // snow on the tops (mountains)
uniform float horizon_seed = 0.0;
// The land's outline round the horizon, worked out once (Look): r the far
// range, g the nearer one, as a share of horizon_height.
uniform sampler2D horizon_profile : filter_linear, repeat_enable;

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

// Height (radians) of the far land at azimuth az: x the far range, y the
// nearer one in front of it.
vec2 land(float az) {
	return texture(horizon_profile, vec2(az / 6.2831853 + 0.5, 0.5)).rg * horizon_height;
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
	// The far land: hazy, lit from the sun's side, snow on the peaks.
	if (horizon_kind > 0 && h > -0.03 && h < horizon_height * 1.3 + 0.01) {
		float az = atan(d.z, d.x);
		vec3 haze_c = horizon_color;
		if (horizon_kind == 3) {
			// Skyline: blocks of towers, taller where the city is dense.
			float bins = 900.0;
			float a01 = az / 6.2831853 + 0.5;
			float b = floor(a01 * bins);
			float dense = smoothstep(0.35, 0.75, fbm(vec2(cos(az), sin(az)) * 2.0 + horizon_seed));
			float r = hash(vec2(b, horizon_seed));
			float tower = horizon_height * (0.08 + 0.35 * r * r + 0.65 * dense * step(0.55, hash(vec2(b * 1.7, 2.0))) * hash(vec2(b, 9.0)));
			tower *= step(0.2, dense + 0.25 * r);
			if (h < tower) {
				vec3 bc = mix(horizon_tint, horizon_tint * 1.25, hash(vec2(b, 4.0)));
				// (in the dark, windows lit)
				float win = step(0.6, hash(floor(vec2(a01 * bins * 4.0, h * 1800.0)))) * night;
				bc = mix(bc, vec3(1.0, 0.85, 0.55) * 1.6, win * 0.7);
				col = mix(bc, haze_c, 0.55 * (1.0 - night * 0.6));
			}
		} else {
			vec2 hl = land(az);
			if (h < hl.x || h < hl.y) {
				float e = 0.03;
				vec2 hr = land(az + e);
				vec2 hl2 = land(az - e);
				bool near = h < hl.y;
				float top = near ? hl.y : hl.x;
				float slope = ((near ? hr.y : hr.x) - (near ? hl2.y : hl2.x)) / (2.0 * e);
				float sun_az = atan(LIGHT0_DIRECTION.z, LIGHT0_DIRECTION.x);
				// Faces towards the sun lit, away in shade; ridges and gullies
				// (noise across and down the slope) break it up.
				float rock = noise(vec2(az * 55.0, h * 90.0)) * 0.6 + noise(vec2(az * 140.0, h * 260.0)) * 0.4;
				float lit = clamp(0.85 - slope * 2.2 * sin(az - sun_az) + (rock - 0.5) * 0.35, 0.45, 1.25);
				lit *= mix(0.85, 1.0, smoothstep(0.0, top + 0.0001, h));
				vec3 mc = horizon_tint * lit;
				if (horizon_kind == 1 && !near) {
					// Snow above the snow line, and in streaks down the gullies.
					float line = mix(0.95, 0.5, snow) * horizon_height;
					float s = smoothstep(line - 0.006, line + 0.004, h + (rock - 0.5) * 0.022) * step(0.001, snow);
					mc = mix(mc, vec3(0.92, 0.94, 0.98) * lit * 1.1, s);
				}
				// Haze: the far range almost the colour of the sky, the nearer
				// one less so; thicker low down, in the valleys.
				float hz = near ? 0.38 : 0.62;
				hz += 0.25 * (1.0 - smoothstep(0.0, top + 0.0001, h));
				col = mix(mc, haze_c, clamp(hz, 0.0, 0.9) * (1.0 - night * 0.5));
				if (night > 0.5) col = mix(col, vec3(0.02, 0.02, 0.03), 0.6);
			}
		}
	}
	if (night > 0.5) {
		// Stars, fading into the light glow near the horizon.
		if (h > 0.0) {
			vec2 sp = d.xz / (h + 0.25) * 140.0;
			float s = hash(floor(sp));
			float tw = step(0.9965, s) * (0.5 + 0.5 * hash(floor(sp) + 3.1));
			col += vec3(tw) * smoothstep(0.08, 0.4, h) * 0.9;
		}
		COLOR = col;
	} else {
		// Sun.
		float sd = dot(d, LIGHT0_DIRECTION);
		col += LIGHT0_COLOR * (smoothstep(sun_size, sun_size + 0.0003, sd) * 6.0 + pow(max(sd, 0.0), 220.0) * 0.6 + pow(max(sd, 0.0), 12.0) * 0.12);
		COLOR = col;
	}
}

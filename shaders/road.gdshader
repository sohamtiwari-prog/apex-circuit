shader_type spatial;
render_mode cull_disabled;
// Track surface. Vertex colour = paint (kerbs, lines, run-off), vertex alpha =
// material: 1 asphalt, 0.66 gravel, 0.33 run-off asphalt, 0 paint.
// UV = metres / 8 (x across, y along); UV2.x = lateral position (m),
// UV2.y = racing-line position: the line is rubbered in (darker, smoother)
// where the cars actually drive.

uniform sampler2D grain : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grain_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float rubber = 0.42;
uniform float edge_dust_from = 4.5;   // metres from the centre where the off-line dust starts
uniform float wetness = 0.0;     // 0 dry .. 1 soaked: darker, glossy, puddles off the line
uniform float road_half = 6.0;   // (kerbs run from road_half to road_half + kerb_w)
uniform float kerb_w = 1.3;

varying float cam_dist;

void vertex() {
	cam_dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}

void fragment() {
	vec3 c = COLOR.rgb;
	c = c * (c * (c * 0.305306 + 0.682171) + 0.012523);   // sRGB -> linear
	float code = COLOR.a;
	float asphalt = step(0.9, code);
	float gravel = step(0.5, code) * (1.0 - asphalt);
	float runoff = step(0.2, code) * (1.0 - gravel - asphalt);
	float paint = 1.0 - asphalt - gravel - runoff;
	// Close up the fine texture shows; far off it would only shimmer, so it
	// fades to its average.
	float near = 1.0 - smoothstep(18.0, 70.0, cam_dist);
	float g1 = texture(grain, UV * vec2(0.6, 0.6)).r;
	float g2 = texture(grain, UV * vec2(5.0, 5.0)).r;
	float g3 = texture(grain, UV * vec2(0.08, 0.08)).r;
	float g4 = texture(grain, UV * vec2(23.0, 23.0)).r;       // the stones in the mix
	float stones = mix(0.5, g4, near);
	// Asphalt: aggregate (dark binder, lighter stones), large patches of
	// repair, a rubbered line (the whole line darker, the two wheel tracks
	// darkest), and dust and marbles off line, lightest towards the edges.
	float d = UV2.x - UV2.y;
	float line_band = exp(-d * d / 7.5);
	float tracks = exp(-pow(abs(d) - 0.8, 2.0) / 0.35);
	float rub = clamp(line_band * 0.65 + tracks * 0.55, 0.0, 1.0) * asphalt;
	float edge = smoothstep(edge_dust_from, edge_dust_from + 2.5, abs(UV2.x)) * asphalt;
	float patches = smoothstep(0.42, 0.62, g3);
	vec3 asphalt_c = c * (0.86 + 0.22 * g2) * (0.9 + 0.2 * g3);
	asphalt_c *= 0.82 + 0.36 * smoothstep(0.35, 0.75, stones) * (1.0 - rub * 0.6);
	asphalt_c *= 1.0 - 0.09 * patches;                       // resurfaced patches (darker, newer)
	// Joins between the resurfaced patches and the old surface: thin dark seams.
	float seam = 1.0 - smoothstep(0.0, 0.016, abs(g3 - 0.52));
	asphalt_c *= 1.0 - 0.2 * seam * near;
	asphalt_c *= 1.0 - rubber * rub * (0.75 + 0.5 * g1);
	asphalt_c = mix(asphalt_c, asphalt_c * vec3(1.18, 1.14, 1.08), edge * (0.5 + 0.5 * g1)); // dust
	// Tyre marks: long dark streaks along the line (locked wheels into the
	// corners, wheelspin out of them), in stretches, not everywhere.
	float streak = texture(grain, vec2(UV2.x * 0.55, UV.y * 0.045)).r;
	float stretch = smoothstep(0.52, 0.72, texture(grain, vec2(0.37, UV.y * 0.011)).r);
	float skid = smoothstep(0.56, 0.78, streak) * stretch * (line_band * 0.7 + tracks * 0.6) * asphalt;
	asphalt_c *= 1.0 - 0.5 * clamp(skid, 0.0, 1.0);
	// Gravel: coarse, high contrast.
	vec3 gravel_c = c * (0.7 + 0.6 * g2) * (0.85 + 0.3 * g1) * (0.8 + 0.4 * stones);
	// Paint lies over asphalt: the aggregate shows through as pits, and it
	// is grubby and worn in places.
	vec3 paint_c = c * (0.9 + 0.1 * g2) * (0.86 + 0.18 * smoothstep(0.25, 0.7, stones));
	paint_c *= 1.0 - 0.12 * smoothstep(0.55, 0.8, g1);
	// Kerbs: rubber laid on them where cars run over (along their inner half),
	// in streaks.
	float lat = abs(UV2.x);
	float on_kerb = step(road_half, lat) * step(lat, road_half + kerb_w) * paint;
	float kerb_rub = on_kerb * (1.0 - smoothstep(road_half, road_half + kerb_w, lat)) * smoothstep(0.45, 0.8, texture(grain, vec2(UV2.x * 0.9, UV.y * 0.12)).r);
	paint_c *= 1.0 - 0.55 * kerb_rub;
	vec3 col = paint_c;
	col = mix(col, asphalt_c, asphalt);
	col = mix(col, gravel_c, gravel);
	// Run-off asphalt: coarser and dustier than the track, in patches.
	vec3 runoff_c = c * (0.8 + 0.3 * g2) * (0.86 + 0.28 * g3) * (1.0 - 0.08 * patches) * (0.8 + 0.4 * stones);
	col = mix(col, runoff_c, runoff);
	// The rubbered line has a slight sheen; paint is smoother than asphalt.
	float rough = mix(0.8, 0.6, rub);
	rough = mix(rough, 0.55, paint);
	float spec = mix(0.5, 0.15, gravel);
	if (wetness > 0.0) {
		// Standing water collects in the low patches; the line dries first.
		float puddle = smoothstep(0.45, 0.75, g3 + g1 * 0.25) * (1.0 - rub * 0.6);
		float w = wetness * (1.0 - gravel * 0.5);
		col *= 1.0 - 0.38 * w;
		rough = mix(rough, mix(0.32, 0.06, puddle), w);
		spec = mix(spec, 0.65, w);
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = spec;
	// Aggregate texture: a fine bump from the grain, so the surface catches
	// the light (stronger on gravel, gentler on the rubbered line and paint),
	// over a gentle unevenness at a larger scale.
	vec3 fine = texture(grain_normal, UV * 16.0).rgb;
	vec3 broad = texture(grain_normal, UV * 2.2).rgb;
	NORMAL_MAP = mix(broad, fine, near * 0.7);
	NORMAL_MAP_DEPTH = (mix(0.5, 0.28, rub) - 0.2 * paint + gravel * 1.2) * mix(0.6, 1.0, near);
}

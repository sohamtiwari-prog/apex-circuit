shader_type spatial;
render_mode cull_disabled;
// Track surface. Vertex colour = paint (kerbs, lines, run-off), vertex alpha =
// material: 1 asphalt, 0.66 gravel, 0.33 run-off asphalt, 0 paint.
// UV2.x = lateral position, UV2.y = racing-line position: the line is
// rubbered in (darker, smoother) where the cars actually drive.

uniform sampler2D grain : filter_linear_mipmap, repeat_enable;
uniform sampler2D grain_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float rubber = 0.42;
uniform float edge_dust_from = 4.5;   // metres from the centre where the off-line dust starts
uniform float wetness = 0.0;     // 0 dry .. 1 soaked: darker, glossy, puddles off the line

void fragment() {
	vec3 c = COLOR.rgb;
	c = c * (c * (c * 0.305306 + 0.682171) + 0.012523);   // sRGB -> linear
	float code = COLOR.a;
	float asphalt = step(0.9, code);
	float gravel = step(0.5, code) * (1.0 - asphalt);
	float runoff = step(0.2, code) * (1.0 - gravel - asphalt);
	float g1 = texture(grain, UV * vec2(0.6, 0.6)).r;
	float g2 = texture(grain, UV * vec2(5.0, 5.0)).r;
	float g3 = texture(grain, UV * vec2(0.08, 0.08)).r;
	// Asphalt: fine aggregate, large patches of repair, a rubbered line
	// (the whole line darker, the two wheel tracks darkest), and dust and
	// marbles off line, lightest towards the edges.
	float d = UV2.x - UV2.y;
	float line_band = exp(-d * d / 7.5);
	float tracks = exp(-pow(abs(d) - 0.8, 2.0) / 0.35);
	float rub = clamp(line_band * 0.65 + tracks * 0.55, 0.0, 1.0) * asphalt;
	float edge = smoothstep(edge_dust_from, edge_dust_from + 2.5, abs(UV2.x)) * asphalt;
	float patches = smoothstep(0.42, 0.62, g3);
	vec3 asphalt_c = c * (0.8 + 0.34 * g2) * (0.9 + 0.2 * g3);
	asphalt_c *= 1.0 - 0.07 * patches;                       // resurfaced patches
	asphalt_c *= 1.0 - rubber * rub * (0.75 + 0.5 * g1);
	asphalt_c = mix(asphalt_c, asphalt_c * vec3(1.16, 1.13, 1.08), edge * (0.5 + 0.5 * g1)); // dust
	// Tyre marks: long dark streaks along the line (locked wheels into the
	// corners, wheelspin out of them), in stretches, not everywhere.
	float streak = texture(grain, vec2(UV2.x * 0.55, UV.y * 0.045)).r;
	float stretch = smoothstep(0.52, 0.72, texture(grain, vec2(0.37, UV.y * 0.011)).r);
	float skid = smoothstep(0.56, 0.78, streak) * stretch * (line_band * 0.7 + tracks * 0.6) * asphalt;
	asphalt_c *= 1.0 - 0.5 * clamp(skid, 0.0, 1.0);
	// Gravel: coarse, high contrast.
	vec3 gravel_c = c * (0.7 + 0.6 * g2) * (0.85 + 0.3 * g1);
	vec3 paint_c = c * (0.94 + 0.08 * g2);
	vec3 col = paint_c;
	col = mix(col, asphalt_c, asphalt);
	col = mix(col, gravel_c, gravel);
	// Run-off asphalt: coarser and dustier than the track, in patches.
	vec3 runoff_c = c * (0.78 + 0.34 * g2) * (0.86 + 0.28 * g3) * (1.0 - 0.08 * patches);
	col = mix(col, runoff_c, runoff);
	// The rubbered line has a slight sheen; paint is smoother than asphalt.
	float rough = mix(0.88, 0.62, rub) - 0.14 * (1.0 - code) * step(code, 0.1);
	float spec = mix(0.4, 0.15, gravel);
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
	// the light (stronger on gravel, gentler on the rubbered line). The
	// normals are baked into a texture: one sample per pixel.
	NORMAL_MAP = texture(grain_normal, UV * 7.0).rgb;
	NORMAL_MAP_DEPTH = mix(1.0, 0.5, rub) + gravel * 1.55;
}

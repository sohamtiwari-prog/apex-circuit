shader_type spatial;
render_mode cull_disabled;
// Track surface. Vertex colour = paint (kerbs, lines, run-off), vertex alpha =
// material: 1 asphalt, 0.66 gravel, 0.33 run-off asphalt, 0 paint.
// UV2.x = lateral position, UV2.y = racing-line position: the line is
// rubbered in (darker, smoother) where the cars actually drive.

uniform sampler2D grain : filter_linear_mipmap, repeat_enable;
uniform float rubber = 0.32;

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
	// Asphalt: fine aggregate, large patches of repair, rubbered line.
	float d = UV2.x - UV2.y;
	float rub = exp(-d * d / 2.2) * asphalt;
	vec3 asphalt_c = c * (0.82 + 0.32 * g2) * (0.9 + 0.2 * g3);
	asphalt_c *= 1.0 - rubber * rub * (0.75 + 0.5 * g1);
	// Gravel: coarse, high contrast.
	vec3 gravel_c = c * (0.7 + 0.6 * g2) * (0.85 + 0.3 * g1);
	vec3 paint_c = c * (0.94 + 0.08 * g2);
	vec3 col = paint_c;
	col = mix(col, asphalt_c, asphalt);
	col = mix(col, gravel_c, gravel);
	col = mix(col, c * (0.88 + 0.22 * g2), runoff);
	ALBEDO = col;
	ROUGHNESS = mix(0.9, 0.72, rub) - 0.12 * (1.0 - code) * step(code, 0.1);
	SPECULAR = mix(0.4, 0.15, gravel);
}

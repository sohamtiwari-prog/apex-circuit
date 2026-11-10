shader_type spatial;
render_mode cull_disabled;
// Tyre rubber: a scrubbed, faintly shiny tread and a matt sidewall with the
// maker's lettering round it. Mapped from the wheel's own coordinates (the
// axle along x, the outer face on +x), so it turns with the wheel.

uniform sampler2D letters : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float rim_r = 0.2;
uniform float tyre_r = 0.33;
uniform float band_lo = 0.15;            // lettering band, as a share of the sidewall height
uniform float band_hi = 0.5;
uniform vec3 letter_color : source_color = vec3(0.86, 0.86, 0.84);
uniform vec3 rubber_color : source_color = vec3(0.04, 0.04, 0.042);

varying vec3 lp;
varying vec3 ln;

void vertex() {
	lp = VERTEX;
	ln = NORMAL;
}

void fragment() {
	float side = smoothstep(0.55, 0.85, abs(ln.x));
	float r = length(lp.yz);
	float h = (r - rim_r) / max(tyre_r - rim_r, 0.001);
	float v = (h - band_lo) / (band_hi - band_lo);
	float u = 0.5 - atan(lp.z, lp.y) / 6.2831853;     // (reads clockwise, the tops of the letters outwards)
	float t = 0.0;
	if (v > 0.0 && v < 1.0 && lp.x > 0.0) {
		t = texture(letters, vec2(u, 1.0 - v)).r;
	}
	vec3 col = mix(rubber_color, letter_color, t * side);
	// The tread: scrubbed in, marked with fine grooves of wear round it.
	float wear = fract(sin(floor(lp.x * 140.0) * 91.7) * 4375.5);
	col *= mix(1.0, 0.94 + 0.12 * wear, 1.0 - side);
	ALBEDO = col;
	ROUGHNESS = mix(0.8, 0.92, side) - 0.3 * t;
	SPECULAR = mix(0.2, 0.12, side);
}

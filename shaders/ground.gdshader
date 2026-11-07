shader_type spatial;
// Grass (with mowing stripes), sand or pavement around the circuit.

uniform vec3 base_color : source_color = vec3(0.22, 0.42, 0.14);
uniform vec3 alt_color : source_color = vec3(0.27, 0.5, 0.17);
uniform float stripe_width = 7.0;
uniform float stripe_strength = 1.0;
uniform vec3 far_color : source_color = vec3(0.25, 0.42, 0.2);
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
// Away from the circuit (vertex alpha -> 1): rough land in patches, no mowing.
uniform vec3 wild_color : source_color = vec3(0.2, 0.36, 0.13);
uniform vec3 wild_color2 : source_color = vec3(0.3, 0.38, 0.16);
// Sun-dried patches (straw coloured), and how much of the land has them.
uniform vec3 dry_color : source_color = vec3(0.42, 0.4, 0.22);
uniform float dryness = 0.35;
uniform float blades = 1.0;          // fine grass texture close up (0: sand / paving)

varying vec3 wpos;
varying float wild;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wild = COLOR.a;
}

void fragment() {
	vec2 p = wpos.xz;
	float n1 = texture(noise_tex, p * 0.004).r;
	float n2 = texture(noise_tex, p * 0.031).r;
	float n3 = texture(noise_tex, p * 0.37).r;
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	// Mowing stripes: light and dark bands (the grass laid one way, then
	// the other), soft edged.
	float s = sin((p.x * 0.8 + p.y * 0.6) / stripe_width * 3.14159);
	float stripe = smoothstep(-0.35, 0.35, s) * stripe_strength * (1.0 - wild);
	vec3 c = mix(base_color, alt_color, stripe);
	// Open land: patches of two greens and dry grass.
	float patch = smoothstep(0.35, 0.65, texture(noise_tex, p * 0.011).r);
	c = mix(c, mix(wild_color, wild_color2, patch), wild);
	float dry = smoothstep(0.62, 0.8, texture(noise_tex, p * 0.0065 + 0.37).r) * dryness * (0.35 + 0.65 * wild);
	c = mix(c, dry_color, dry);
	c *= 0.8 + 0.4 * n1;
	c *= 0.88 + 0.24 * n2;
	c *= 0.9 + 0.2 * n3;
	// Blades: a fine, high-contrast speckle close up that fades with distance
	// (before it could shimmer).
	float fine = texture(noise_tex, p * 3.1).r * 0.6 + texture(noise_tex, p * 7.3).r * 0.4;
	c *= mix(1.0, 0.72 + 0.56 * fine, blades * (1.0 - smoothstep(10.0, 45.0, dist)));
	// Haze into the distance.
	c = mix(c, far_color, smoothstep(150.0, 900.0, dist) * 0.6);
	ALBEDO = c;
	ROUGHNESS = 0.93;
	SPECULAR = 0.2;
}

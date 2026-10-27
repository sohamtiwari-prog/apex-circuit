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
	float s = sin((p.x * 0.8 + p.y * 0.6) / stripe_width * 3.14159);
	float stripe = smoothstep(-0.2, 0.2, s) * stripe_strength * (1.0 - wild);
	vec3 c = mix(base_color, alt_color, stripe);
	float patch = smoothstep(0.35, 0.65, texture(noise_tex, p * 0.011).r);
	c = mix(c, mix(wild_color, wild_color2, patch), wild);
	c *= 0.78 + 0.42 * n1;
	c *= 0.88 + 0.24 * n2;
	c *= 0.9 + 0.2 * n3;
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	c = mix(c, far_color, smoothstep(150.0, 900.0, dist) * 0.6);
	ALBEDO = c;
	ROUGHNESS = 0.96;
	SPECULAR = 0.15;
}

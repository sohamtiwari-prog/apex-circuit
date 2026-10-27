shader_type spatial;
// Sea / harbour: deep blue-green, sky-coloured glints, gently moving ripples.
render_mode cull_disabled;

uniform vec3 deep : source_color = vec3(0.03, 0.18, 0.26);
uniform vec3 shallow : source_color = vec3(0.06, 0.32, 0.38);
uniform sampler2D ripples : filter_linear_mipmap, repeat_enable;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	float t = TIME * 0.03;
	float a = texture(ripples, p * 0.02 + vec2(t, t * 0.6)).r;
	float b = texture(ripples, p * 0.051 - vec2(t * 0.8, t * 1.3)).r;
	vec3 nrm = normalize(vec3((a - 0.5) * 0.35, 1.0, (b - 0.5) * 0.35));
	NORMAL = (VIEW_MATRIX * vec4(nrm, 0.0)).xyz;
	ALBEDO = mix(deep, shallow, a * 0.6);
	ROUGHNESS = 0.08;
	METALLIC = 0.0;
	SPECULAR = 0.7;
}

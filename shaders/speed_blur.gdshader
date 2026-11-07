shader_type spatial;
// Speed: the world at the edges of the picture streaks towards the point
// you're heading for, more the faster you go (a camera's motion blur, the
// way TV and the eye see speed). Drawn on a quad covering the screen, after
// the scene. The middle (where you look) stays sharp, and so does your own
// car (it moves with the camera): behind it, the area it covers on screen;
// onboard, the bottom of the picture (the cockpit) and the halo above.
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, skip_vertex_transform, shadows_disabled, fog_disabled;

uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform float amount = 0.0;            // 0 still .. 1 flat out
uniform vec2 focus = vec2(0.5, 0.46);  // where the streaks point (the road ahead)
uniform float clear_radius = 0.22;     // sharp within this (fraction of the screen height)
uniform vec2 car_c = vec2(0.5, 0.7);   // your car on screen (chase): centre ...
uniform vec2 car_r = vec2(0.0, 0.0);   // ... and half size (0: none)
uniform vec2 keep_band = vec2(-1.0, 2.0);  // onboard: blur only between these heights (0 top .. 1 bottom)

void vertex() {
	POSITION = vec4(VERTEX.xy * 2.0, 0.0, 1.0);
}

// 1 on your car, 0 off it (soft edged).
float on_car(vec2 uv) {
	if (car_r.x <= 0.0) {
		return 0.0;
	}
	float e = length((uv - car_c) / car_r);
	return 1.0 - smoothstep(0.85, 1.15, e);
}

float band(vec2 uv) {
	return smoothstep(keep_band.x, keep_band.x + 0.06, uv.y) * (1.0 - smoothstep(keep_band.y - 0.06, keep_band.y, uv.y));
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float aspect = VIEWPORT_SIZE.x / VIEWPORT_SIZE.y;
	vec2 d = uv - focus;
	float r = length(vec2(d.x * aspect, d.y));
	float mask = smoothstep(clear_radius, clear_radius + 0.45, r) * amount;
	// The sky barely moves: less above the horizon.
	mask *= mix(0.35, 1.0, smoothstep(focus.y - 0.2, focus.y + 0.02, uv.y));
	mask *= (1.0 - on_car(uv)) * band(uv);
	if (mask < 0.004) {
		discard;
	}
	// Taps back towards the focus, offset by a per-pixel dither so they
	// blend into a smooth streak instead of separate copies; the streak is
	// longer further from the middle (things at the edge move fastest).
	// Taps that land on your car are left out, so it doesn't smear.
	float jitter = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
	vec2 stp = -d * 0.04 * mask;
	vec3 acc = texture(screen, uv).rgb;
	float wsum = 1.0;
	for (int k = 1; k <= 6; k++) {
		vec2 t = uv + stp * (float(k) - jitter);
		float w = (1.0 - on_car(t)) * band(t);
		acc += texture(screen, t).rgb * w;
		wsum += w;
	}
	ALBEDO = acc / wsum;
	ALPHA = clamp(mask * 1.8, 0.0, 1.0);
}

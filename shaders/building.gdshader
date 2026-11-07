shader_type spatial;
// Facades for city blocks, all from world position so any box size works:
// stucco walls, storeys of framed windows (some with open or closed
// shutters, some with balconies), a shopfront ground floor with awnings, a
// cornice at the top and a flat roof. Instance colour (MultiMesh) is the
// wall colour.

uniform float storey = 3.3;
uniform float bay = 3.1;
uniform float night = 0.0;       // lit windows

varying vec3 wpos;
varying vec3 wnormal;
varying float top_y;
varying float bld;               // a number per building

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	top_y = (MODEL_MATRIX * vec4(0.0, 0.5, 0.0, 1.0)).y;
	vec3 o = MODEL_MATRIX[3].xyz;
	bld = hash(o.xz * 0.013);
}

void fragment() {
	vec3 wall = COLOR.rgb;
	wall = wall * (wall * (wall * 0.305306 + 0.682171) + 0.012523);   // sRGB -> linear
	vec3 n = abs(wnormal);
	if (n.y > 0.6) {
		// Roof: tar and gravel, with a few patches.
		float r = vnoise(wpos.xz * 0.4);
		ALBEDO = vec3(0.16, 0.16, 0.17) * (0.8 + 0.4 * r);
		ROUGHNESS = 0.95;
	} else {
		float u = n.x > n.z ? wpos.z : wpos.x;
		float h = wpos.y;
		// Stucco: weathered, a little darker low down and in streaks.
		float st = vnoise(vec2(u, h) * 0.9) * 0.6 + vnoise(vec2(u, h) * 4.0) * 0.4;
		float streak = vnoise(vec2(u * 1.7, h * 0.08)) ;
		vec3 c = wall * (0.86 + 0.18 * st) * (0.92 + 0.08 * streak);
		vec2 cell = vec2(fract(u / bay), fract(h / storey));
		float floor_i = floor(h / storey);
		vec2 wid = vec2(floor(u / bay), floor_i);
		float id = hash(wid + bld * 17.0);
		float rough = 0.92;
		float metal = 0.0;
		vec3 emit = vec3(0.0);
		bool cornice = h > top_y - 0.9;
		if (cornice) {
			c = wall * 0.78 * (step(fract(h * 2.2), 0.5) * 0.12 + 0.9);
		} else if (floor_i < 1.0) {
			// Ground floor: shop windows under awnings.
			float shop = step(0.06, cell.x) * step(cell.x, 0.94) * step(0.04, cell.y) * step(cell.y, 0.68);
			float frame = step(0.04, cell.x) * step(cell.x, 0.96) * step(0.02, cell.y) * step(cell.y, 0.72) - shop;
			vec3 awning_col = mix(vec3(0.55, 0.08, 0.06), vec3(0.08, 0.3, 0.2), step(0.5, hash(vec2(wid.x, bld))));
			float stripe = step(0.5, fract(u * 1.6));
			float awning = step(0.72, cell.y) * step(cell.y, 0.86) * step(0.4, hash(vec2(wid.x * 3.1, bld)));
			vec3 glass = vec3(0.05, 0.06, 0.07);
			c = mix(c, vec3(0.08, 0.08, 0.09), frame);
			c = mix(c, glass, shop);
			c = mix(c, mix(awning_col, vec3(0.85), stripe * 0.6), awning);
			rough = mix(rough, 0.06, shop);
			metal = shop * 0.5;
			emit = vec3(1.0, 0.82, 0.55) * shop * (0.25 + night * 1.6) * step(0.25, id);
		} else {
			// Upper floors: framed windows, shutters, balconies.
			float wx0 = 0.32;
			float wx1 = 0.68;
			float wy0 = 0.26;
			float wy1 = 0.84;
			float win = step(wx0, cell.x) * step(cell.x, wx1) * step(wy0, cell.y) * step(cell.y, wy1);
			float frame = step(wx0 - 0.03, cell.x) * step(cell.x, wx1 + 0.03) * step(wy0 - 0.03, cell.y) * step(cell.y, wy1 + 0.02) - win;
			float sill = step(wx0 - 0.05, cell.x) * step(cell.x, wx1 + 0.05) * step(wy0 - 0.07, cell.y) * step(cell.y, wy0 - 0.02);
			// Shutters: open (beside the window) or closed (over it), in the
			// building's colour (green, teal or brown).
			float bs = hash(vec2(bld, 3.7));
			vec3 shut_col = bs < 0.33 ? vec3(0.12, 0.28, 0.16) : (bs < 0.66 ? vec3(0.1, 0.27, 0.3) : vec3(0.3, 0.18, 0.1));
			float has_shutters = step(0.35, bld);
			float open_sh = (step(wx0 - 0.17, cell.x) * step(cell.x, wx0 - 0.03) + step(wx1 + 0.03, cell.x) * step(cell.x, wx1 + 0.17))
				* step(wy0, cell.y) * step(cell.y, wy1) * has_shutters * step(id, 0.7);
			float closed = win * has_shutters * step(0.82, id);
			float slats = 0.85 + 0.15 * step(0.5, fract(h * 9.0));
			// Balconies on some buildings: a slab and dark railing.
			float balc = step(0.5, hash(vec2(bld, 9.1))) * step(0.18, cell.x) * step(cell.x, 0.82);
			float slab = balc * step(0.18, cell.y) * step(cell.y, 0.24);
			float rail = balc * step(0.24, cell.y) * step(cell.y, 0.5) * step(0.75, fract(u * 6.0));
			// Glass: dark, with the sky in it (high gloss picks up reflections).
			vec3 glass = mix(vec3(0.04, 0.05, 0.06), vec3(0.18, 0.21, 0.24), id * 0.5);
			c = mix(c, wall * 1.08, sill);
			c = mix(c, vec3(0.86, 0.85, 0.82) * 0.8, frame);
			c = mix(c, glass, win);
			c = mix(c, shut_col * slats, open_sh + closed);
			c = mix(c, wall * 0.7, slab);
			c = mix(c, vec3(0.05), rail);
			float clear_glass = win * (1.0 - closed);
			// (At night: dull glass. The night sky's stars in glossy glass
			// read as static.)
			rough = mix(rough, mix(0.05, 0.35, night), clear_glass);
			metal = clear_glass * mix(0.6, 0.1, night);
			// Night: about half the rooms lit, warm or cool.
			float lit = step(0.45, fract(id * 7.31)) * night;
			vec3 lamp = mix(vec3(1.0, 0.72, 0.4), vec3(0.75, 0.85, 1.0), step(0.7, fract(id * 3.7)));
			emit = lamp * clear_glass * lit * 1.6;
			// Floor slab between storeys.
			c *= 1.0 - 0.12 * step(cell.y, 0.03);
		}
		if (night > 0.5) {
			c *= 0.6;
		}
		ALBEDO = c;
		ROUGHNESS = rough;
		METALLIC = metal;
		EMISSION = emit;
	}
}

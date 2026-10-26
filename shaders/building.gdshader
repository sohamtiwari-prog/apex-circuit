shader_type spatial;
// Facades for city blocks: storeys of windows, a shopfront ground floor and
// a flat roof, all from world position, so any box size works.
// Instance colour (MultiMesh) is the render colour of the walls.

uniform float storey = 3.3;
uniform float bay = 3.1;

varying vec3 wpos;
varying vec3 wnormal;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 wall = COLOR.rgb;
	wall = wall * (wall * (wall * 0.305306 + 0.682171) + 0.012523);   // sRGB -> linear
	vec3 n = abs(wnormal);
	if (n.y > 0.6) {
		ALBEDO = wall * 0.55;
		ROUGHNESS = 0.95;
	} else {
		float u = n.x > n.z ? wpos.z : wpos.x;
		float h = wpos.y;
		vec2 cell = vec2(fract(u / bay), fract(h / storey));
		float floor_i = floor(h / storey);
		float win = step(0.18, cell.x) * step(cell.x, 0.82) * step(0.28, cell.y) * step(cell.y, 0.84);
		// Ground floor: big shop windows and awnings.
		if (floor_i < 1.0) {
			win = step(0.08, cell.x) * step(cell.x, 0.92) * step(0.05, cell.y) * step(cell.y, 0.7);
		}
		// Some shutters closed, varying by window.
		float id = fract(sin(dot(floor(vec2(u / bay, floor_i)), vec2(12.9898, 78.233))) * 43758.5453);
		vec3 glass = mix(vec3(0.1, 0.16, 0.22), vec3(0.35, 0.45, 0.55), id * 0.6);
		vec3 shutter = wall * vec3(0.75, 0.82, 0.7);
		vec3 wcol = id > 0.8 ? shutter : glass;
		// Balcony ledge under each window row.
		float ledge = step(0.2, cell.y) * step(cell.y, 0.26) * step(1.0, floor_i);
		vec3 c = mix(wall, wcol, win);
		c = mix(c, wall * 1.15, ledge);
		ALBEDO = c;
		ROUGHNESS = mix(0.9, 0.12, win * step(id, 0.8));
		METALLIC = win * step(id, 0.8) * 0.4;
	}
}

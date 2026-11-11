class_name Look
extends RefCounted
## Lighting, sky and post-processing for each kind of venue, so every scene
## (race, menu) shares one consistent look.

const SKIES := {
	"park": {"top": Color(0.17, 0.38, 0.74), "horizon": Color(0.68, 0.79, 0.9), "cover": 0.42,
		"sun": Color(1.0, 0.96, 0.88), "sun_energy": 2.05, "sun_rot": Vector3(-48, 35, 0), "fog": Color(0.72, 0.8, 0.9)},
	"forest": {"top": Color(0.28, 0.42, 0.62), "horizon": Color(0.72, 0.77, 0.82), "cover": 0.62,
		"sun": Color(0.98, 0.95, 0.9), "sun_energy": 1.8, "sun_rot": Vector3(-40, 60, 0), "fog": Color(0.74, 0.78, 0.82)},
	"desert": {"top": Color(0.2, 0.44, 0.78), "horizon": Color(0.9, 0.84, 0.72), "cover": 0.12,
		"sun": Color(1.0, 0.9, 0.74), "sun_energy": 2.25, "sun_rot": Vector3(-34, -40, 0), "fog": Color(0.9, 0.84, 0.74)},
	"city": {"top": Color(0.14, 0.38, 0.78), "horizon": Color(0.7, 0.8, 0.92), "cover": 0.28,
		"sun": Color(1.0, 0.95, 0.86), "sun_energy": 2.1, "sun_rot": Vector3(-56, 20, 0), "fog": Color(0.76, 0.83, 0.92)},
	"studio": {"top": Color(0.08, 0.09, 0.12), "horizon": Color(0.22, 0.24, 0.3), "cover": 0.0,
		"sun": Color(1.0, 0.97, 0.92), "sun_energy": 1.2, "sun_rot": Vector3(-40, 30, 0), "fog": Color(0.1, 0.1, 0.12)},
	# The team garage behind the menus: daylight through the open door,
	# strip lights overhead.
	"garage": {"top": Color(0.78, 0.81, 0.85), "horizon": Color(0.9, 0.91, 0.92), "cover": 0.0,
		"sun": Color(1.0, 0.99, 0.97), "sun_energy": 0.9, "sun_rot": Vector3(-70, 35, 0), "fog": Color(0.9, 0.9, 0.9)},
}


## Late-evening light: low golden sun, long shadows, warm haze.
const SUNSET := {"top": Color(0.14, 0.2, 0.42), "horizon": Color(1.0, 0.62, 0.34), "cover": 0.36,
	"sun": Color(1.0, 0.64, 0.36), "sun_energy": 1.85, "fog": Color(0.95, 0.66, 0.46),
	"cloud": Color(1.0, 0.78, 0.6), "cloud_shade": Color(0.42, 0.34, 0.46)}


## Night under floodlights: a dark sky with stars and a glow of light on
## the horizon; the "sun" is the floodlighting, white and nearly overhead.
const NIGHT := {"top": Color(0.012, 0.02, 0.05), "horizon": Color(0.24, 0.19, 0.2), "cover": 0.18,
	"sun": Color(0.93, 0.96, 1.0), "sun_energy": 1.05, "fog": Color(0.16, 0.14, 0.16),
	"cloud": Color(0.16, 0.15, 0.17), "cloud_shade": Color(0.05, 0.05, 0.07)}


## The far horizon behind each circuit (drawn in the sky): mountains, hills
## or a city skyline. [kind, height (radians), tint, snow, seed]
const HORIZONS := {
	"styria": [1, 0.16, Color(0.26, 0.33, 0.3), 0.65, 3.0],
	"riviera": [1, 0.2, Color(0.36, 0.38, 0.34), 0.0, 7.0],
	"brianza": [1, 0.045, Color(0.4, 0.45, 0.52), 0.9, 1.0],
	"ardennes": [2, 0.05, Color(0.16, 0.24, 0.16), 0.0, 4.0],
	"pannonia": [2, 0.035, Color(0.24, 0.3, 0.2), 0.0, 6.0],
	"isebay": [2, 0.06, Color(0.2, 0.3, 0.22), 0.0, 2.0],
	"kestrel_park": [2, 0.04, Color(0.22, 0.3, 0.2), 0.0, 5.0],
	"silvermoor": [2, 0.012, Color(0.24, 0.3, 0.22), 0.0, 8.0],
	"lone_star": [2, 0.015, Color(0.3, 0.33, 0.24), 0.0, 9.0],
	"duinen": [2, 0.025, Color(0.42, 0.42, 0.3), 0.0, 10.0],
	"desert": [2, 0.02, Color(0.62, 0.5, 0.36), 0.0, 11.0],
	"lakeside": [3, 0.035, Color(0.38, 0.42, 0.48), 0.0, 12.0],
	"entrelagos": [3, 0.045, Color(0.38, 0.4, 0.42), 0.0, 13.0],
	"ile_royale": [3, 0.05, Color(0.36, 0.4, 0.46), 0.0, 14.0],
	"jiading": [3, 0.035, Color(0.4, 0.42, 0.46), 0.0, 15.0],
	"caspian": [3, 0.04, Color(0.46, 0.44, 0.4), 0.0, 16.0],
	"gulf": [3, 0.03, Color(0.3, 0.3, 0.32), 0.0, 17.0],
	"marina": [3, 0.06, Color(0.3, 0.32, 0.36), 0.0, 18.0],
	"red_sea": [3, 0.035, Color(0.34, 0.33, 0.32), 0.0, 19.0],
}


## The outline of the far land round the horizon (once per circuit): the
## far range (red) and a nearer, lower one (green), 0..1 of the height.
## Mountains are ridged and sharp; hills smooth.
static func _horizon_profile(kind: int, seed: int) -> ImageTexture:
	var n := 2048
	var far_n := FastNoiseLite.new()
	far_n.seed = seed
	far_n.noise_type = FastNoiseLite.TYPE_PERLIN
	far_n.fractal_octaves = 5 if kind == 1 else 3
	far_n.frequency = 1.0
	var near_n := FastNoiseLite.new()
	near_n.seed = seed + 50
	near_n.noise_type = FastNoiseLite.TYPE_PERLIN
	near_n.fractal_octaves = 3 if kind == 1 else 2
	near_n.frequency = 1.0
	if kind == 1:
		far_n.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	# Round a circle in the noise, so the outline joins up all the way round;
	# then each outline stretched to fill 0..1.
	var fs := PackedFloat32Array()
	var ms := PackedFloat32Array()
	for i in n:
		var a := TAU * float(i) / n
		var rad := 2.8 if kind == 1 else 1.9
		var px := cos(a) * rad
		var pz := sin(a) * rad
		fs.append(far_n.get_noise_2d(px, pz))
		ms.append(near_n.get_noise_2d(px * 1.5 + 30.0, pz * 1.5))
	var f_lo := INF
	var f_hi := -INF
	var m_lo := INF
	var m_hi := -INF
	for i in n:
		f_lo = minf(f_lo, fs[i])
		f_hi = maxf(f_hi, fs[i])
		m_lo = minf(m_lo, ms[i])
		m_hi = maxf(m_hi, ms[i])
	var img := Image.create(n, 1, false, Image.FORMAT_RGF)
	for i in n:
		var f := (fs[i] - f_lo) / maxf(f_hi - f_lo, 0.0001)
		var m := (ms[i] - m_lo) / maxf(m_hi - m_lo, 0.0001)
		var far_h: float
		var near_h: float
		if kind == 1:
			far_h = 0.1 + 0.9 * pow(f, 1.7)
			near_h = 0.42 * smoothstep(0.25, 0.9, m)
		else:
			far_h = 0.25 + 0.75 * smoothstep(0.1, 0.95, f)
			near_h = 0.6 * smoothstep(0.3, 0.9, m)
		img.set_pixel(i, 0, Color(far_h, near_h, 0.0))
	return ImageTexture.create_from_image(img)


## "auto" picks the track's own time: night for the night races.
static func resolve_time(time_of_day: String, track_id: String) -> String:
	if time_of_day == "auto" or time_of_day == "":
		return "night" if bool(Track.catalog_entry(track_id).get("night", false)) else "day"
	return time_of_day


## Adds a WorldEnvironment and sun to `parent`; returns the sun.
static func build(parent: Node, style: String, time_of_day := "day", track_id := "") -> DirectionalLight3D:
	var cfg: Dictionary = SKIES.get(style, SKIES["park"]).duplicate()
	var sunset := time_of_day == "sunset" and not style in ["studio", "garage"]
	if sunset:
		for k in SUNSET:
			cfg[k] = SUNSET[k]
		var rot: Vector3 = SKIES.get(style, SKIES["park"])["sun_rot"]
		cfg["sun_rot"] = Vector3(-9.0, rot.y + 25.0, 0)
	var night := time_of_day == "night" and not style in ["studio", "garage"]
	if night:
		for k in NIGHT:
			cfg[k] = NIGHT[k]
		cfg["sun_rot"] = Vector3(-72.0, 25.0, 0)
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/sky.gdshader")
	sky_mat.set_shader_parameter("top_color", cfg["top"])
	sky_mat.set_shader_parameter("horizon_color", cfg["horizon"])
	sky_mat.set_shader_parameter("ground_color", Color(cfg["horizon"]).darkened(0.45))
	sky_mat.set_shader_parameter("cloud_cover", cfg["cover"])
	sky_mat.set_shader_parameter("night", 1.0 if night else 0.0)
	if HORIZONS.has(track_id):
		var hz: Array = HORIZONS[track_id]
		sky_mat.set_shader_parameter("horizon_kind", int(hz[0]))
		sky_mat.set_shader_parameter("horizon_height", float(hz[1]))
		var tint: Color = hz[2]
		if sunset:
			tint = tint.lerp(Color(0.42, 0.3, 0.3), 0.4)
		sky_mat.set_shader_parameter("horizon_tint", tint)
		sky_mat.set_shader_parameter("snow", float(hz[3]))
		sky_mat.set_shader_parameter("horizon_seed", float(hz[4]))
		if int(hz[0]) != 3:
			sky_mat.set_shader_parameter("horizon_profile", _horizon_profile(int(hz[0]), int(hz[4])))
	if cfg.has("cloud"):
		sky_mat.set_shader_parameter("cloud_color", cfg["cloud"])
		sky_mat.set_shader_parameter("cloud_shade", cfg["cloud_shade"])
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_256     # (sharp reflections in paint and glass; the sky is still, so made once)

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	# Less fill than before, more sun: shadows and form, not flat light.
	env.ambient_light_energy = 0.42 if sunset else 0.5
	# Shade lit partly by the sky (blue) and partly by light bounced off
	# the ground and buildings (warm), not by pure sky: walls in shadow
	# stay their colour instead of going blue.
	env.ambient_light_sky_contribution = 0.55
	env.ambient_light_color = Color(0.62, 0.58, 0.52)
	if night:
		# The bowl of floodlights fills in from every side.
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.36, 0.38, 0.45)
		env.ambient_light_energy = 0.9
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.1
	env.adjustment_saturation = 1.0
	if night:
		env.glow_intensity = 0.8
		env.glow_bloom = 0.08
		env.glow_hdr_threshold = 0.9
	env.fog_enabled = not style in ["studio", "garage"]
	env.fog_light_color = cfg["fog"]
	env.fog_density = 0.00045
	env.fog_aerial_perspective = 0.6
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	parent.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = cfg["sun_rot"]
	sun.light_color = cfg["sun"]
	sun.light_energy = cfg["sun_energy"]
	sun.shadow_enabled = true
	sun.shadow_blur = 1.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 160.0 if sunset else 140.0
	sun.directional_shadow_split_1 = 0.25
	parent.add_child(sun)
	return sun


## High: shadows and glow. Battery saver: neither, and shorter draw distance
## for trees (MultiMeshInstance3D with a visibility range).
static func apply_quality(root: Node, high: bool) -> void:
	for n in root.find_children("*", "DirectionalLight3D", true, false):
		(n as DirectionalLight3D).shadow_enabled = high
	for n in root.find_children("*", "WorldEnvironment", true, false):
		var env: Environment = (n as WorldEnvironment).environment
		env.glow_enabled = high
	for n in root.find_children("*", "MultiMeshInstance3D", true, false):
		var mmi := n as MultiMeshInstance3D
		if mmi.visibility_range_end > 0.0:
			mmi.visibility_range_end = 1100.0 if high else 450.0

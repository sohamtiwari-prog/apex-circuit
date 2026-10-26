class_name Look
extends RefCounted
## Lighting, sky and post-processing for each kind of venue, so every scene
## (race, menu) shares one consistent look.

const SKIES := {
	"park": {"top": Color(0.17, 0.38, 0.74), "horizon": Color(0.68, 0.79, 0.9), "cover": 0.42,
		"sun": Color(1.0, 0.96, 0.88), "sun_energy": 1.35, "sun_rot": Vector3(-48, 35, 0), "fog": Color(0.72, 0.8, 0.9)},
	"forest": {"top": Color(0.28, 0.42, 0.62), "horizon": Color(0.72, 0.77, 0.82), "cover": 0.62,
		"sun": Color(0.98, 0.95, 0.9), "sun_energy": 1.15, "sun_rot": Vector3(-40, 60, 0), "fog": Color(0.74, 0.78, 0.82)},
	"desert": {"top": Color(0.2, 0.44, 0.78), "horizon": Color(0.9, 0.84, 0.72), "cover": 0.12,
		"sun": Color(1.0, 0.9, 0.74), "sun_energy": 1.5, "sun_rot": Vector3(-34, -40, 0), "fog": Color(0.9, 0.84, 0.74)},
	"city": {"top": Color(0.14, 0.38, 0.78), "horizon": Color(0.7, 0.8, 0.92), "cover": 0.28,
		"sun": Color(1.0, 0.95, 0.86), "sun_energy": 1.4, "sun_rot": Vector3(-56, 20, 0), "fog": Color(0.76, 0.83, 0.92)},
	"studio": {"top": Color(0.08, 0.09, 0.12), "horizon": Color(0.22, 0.24, 0.3), "cover": 0.0,
		"sun": Color(1.0, 0.97, 0.92), "sun_energy": 1.2, "sun_rot": Vector3(-40, 30, 0), "fog": Color(0.1, 0.1, 0.12)},
}


## Adds a WorldEnvironment and sun to `parent`; returns the sun.
static func build(parent: Node, style: String) -> DirectionalLight3D:
	var cfg: Dictionary = SKIES.get(style, SKIES["park"])
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/sky.gdshader")
	sky_mat.set_shader_parameter("top_color", cfg["top"])
	sky_mat.set_shader_parameter("horizon_color", cfg["horizon"])
	sky_mat.set_shader_parameter("ground_color", Color(cfg["horizon"]).darkened(0.45))
	sky_mat.set_shader_parameter("cloud_cover", cfg["cover"])
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.75
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.08
	env.fog_enabled = style != "studio"
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
	sun.shadow_blur = 1.5
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 140.0
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

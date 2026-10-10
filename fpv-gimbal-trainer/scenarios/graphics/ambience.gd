class_name Ambience
extends RefCounted
## Time of day and weather of a session, applied on top of the environment's style (EnvironmentStyle):
##  - "noon": the style as it is (bright day);
##  - "morning": low sun from the side, soft warm light, a little haze;
##  - "golden": end of the day, grazing orange sun, long shadows, warm haze;
##  - "overcast": grey sky, no sharp shadow, diffuse light, more haze;
##  - "snowfall": overcast and snow falling around the camera (snowy environments only).
## The ambience of a session is drawn when the session is generated (or chosen in the menu) and saved with it, so a
## replay looks the same.

const IDS := ["noon", "morning", "golden", "overcast", "snowfall"]
## Menu entries: "auto" draws one at random.
const MENU := ["auto", "noon", "morning", "golden", "overcast", "snowfall"]
const LABELS := {"auto": "Aléatoire", "noon": "Plein jour", "morning": "Matin", "golden": "Fin de journée",
		"overcast": "Couvert", "snowfall": "Chute de neige"}
## Chance of each ambience when drawn at random (snowfall only where there is snow).
const WEIGHTS := {"noon": 0.32, "morning": 0.22, "golden": 0.24, "overcast": 0.14, "snowfall": 0.08}
const SNOWY := ["neige", "descente", "glace"]

## Choice of the menu (an id of MENU), kept in the menu preferences.
static var choice := "auto"


static func is_snowy(environment_tag: String) -> bool:
	return environment_tag in SNOWY


## The ambience of a new session: the menu choice, or one drawn with `rng`.
static func pick(rng: RandomNumberGenerator, snowy: bool) -> String:
	if choice != "auto":
		return choice if (choice != "snowfall" or snowy) else "overcast"
	var total := 0.0
	for id in IDS:
		if id != "snowfall" or snowy:
			total += float(WEIGHTS[id])
	var r := rng.randf() * total
	for id in IDS:
		if id == "snowfall" and not snowy:
			continue
		r -= float(WEIGHTS[id])
		if r <= 0.0:
			return id
	return "noon"


## The environment style with the light, sky and haze of the ambience.
static func variant(base: EnvironmentStyle, id: String) -> EnvironmentStyle:
	var s: EnvironmentStyle = base.duplicate()
	# a deep valley (mountain road) hides a very low sun: the sun stays a little higher there
	var valley := base.builder == "mountain_road"
	match id:
		"morning":
			s.sun_elevation = 22.0 if valley else 13.0
			s.sun_azimuth = base.sun_azimuth - (20.0 if valley else 65.0)
			s.sun_color = Color(1.0, 0.86, 0.7)
			s.sun_energy = base.sun_energy * 0.95
			s.sky_top_color = base.sky_top_color.lerp(Color(0.34, 0.52, 0.82), 0.4)
			s.sky_horizon_color = base.sky_horizon_color.lerp(Color(1.0, 0.87, 0.74), 0.4)
			s.ground_horizon_color = base.ground_horizon_color.lerp(Color(1.0, 0.87, 0.74), 0.35)
			s.fog_color = base.fog_color.lerp(Color(1.0, 0.89, 0.8), 0.4)
			# (an environment that already has dense haze, like the forest, keeps nearly its own)
			s.fog_density = base.fog_density * (1.7 if base.fog_density < 0.003 else 1.1)
			s.light_shafts = base.light_shafts * 1.25
			s.fog_sun_scatter = 0.55
			s.ambient_energy = base.ambient_energy * (1.0 if valley else 0.8)
			s.cloud_coverage = base.cloud_coverage * 0.7
		"golden":
			s.sun_elevation = 20.0 if valley else 11.0
			s.sun_azimuth = base.sun_azimuth + (15.0 if valley else 60.0)
			s.sun_color = Color(1.0, 0.64, 0.36)
			s.sun_energy = base.sun_energy * 1.05
			s.sky_top_color = base.sky_top_color.lerp(Color(0.14, 0.24, 0.52), 0.5)
			s.sky_horizon_color = base.sky_horizon_color.lerp(Color(1.0, 0.64, 0.4), 0.6)
			s.ground_horizon_color = base.ground_horizon_color.lerp(Color(0.9, 0.6, 0.45), 0.55)
			s.fog_color = base.fog_color.lerp(Color(0.98, 0.68, 0.48), 0.55)
			s.fog_density = base.fog_density * (1.3 if base.fog_density < 0.003 else 1.0)
			s.light_shafts = base.light_shafts * 1.25
			s.fog_sun_scatter = 0.85
			s.ambient_energy = base.ambient_energy * (1.0 if valley else 0.8)
			s.cloud_coverage = base.cloud_coverage * 0.9
			s.adjustment_saturation = base.adjustment_saturation * 1.07
			s.glow_intensity = base.glow_intensity * 1.4
			s.sun_angle_max = base.sun_angle_max * 1.6
		"overcast", "snowfall":
			var snow := id == "snowfall"
			s.sun_elevation = 48.0
			s.sun_color = Color(0.92, 0.94, 1.0)
			s.sun_energy = base.sun_energy * (0.22 if snow else 0.32)
			s.sun_angular_distance = 9.0  # (very soft shadows)
			var top := Color(0.6, 0.63, 0.69) if not snow else Color(0.66, 0.68, 0.72)
			var hor := Color(0.79, 0.81, 0.85) if not snow else Color(0.82, 0.83, 0.86)
			s.sky_top_color = top
			s.sky_horizon_color = hor
			s.ground_horizon_color = hor
			s.cloud_coverage = 0.97
			s.fog_color = hor
			s.fog_density = maxf(base.fog_density * (1.4 if base.fog_density >= 0.003 else (5.0 if snow else 3.0)), 0.004 if snow else 0.0015)
			s.light_shafts = base.light_shafts * 0.3
			s.fog_sun_scatter = 0.0
			s.ambient_energy = base.ambient_energy * 1.3
			s.adjustment_saturation = base.adjustment_saturation * (0.78 if snow else 0.86)
			s.adjustment_contrast = base.adjustment_contrast * 0.97
			s.glow_intensity = base.glow_intensity * 0.6
	return s


## What the style cannot hold: exposure and the shape of the light of the ambience.
static func finish(id: String, e: Environment, style: EnvironmentStyle) -> void:
	var k := {"noon": 1.0, "morning": 1.02, "golden": 1.1, "overcast": 1.12, "snowfall": 1.12}
	e.tonemap_exposure = style.exposure * float(k.get(id, 1.0))


## Ground material tuned for the ambience: a grazing sun turns the fine relief of the snow into dunes.
static func tune_ground(id: String, ground: Material) -> void:
	if ground is ShaderMaterial:
		var low := {"morning": 0.5, "golden": 0.35}
		(ground as ShaderMaterial).set_shader_parameter("ripple", float(low.get(id, 1.0)))


## Weather around the camera (falling snow); nothing for the other ambiences.
static func add_weather(id: String, parent: Node3D, camera: Camera3D) -> void:
	if id != "snowfall":
		return
	var w := Snowfall.new()
	w.name = "Snowfall"
	w.camera = camera
	parent.add_child(w)


## Falling snow: a box of flakes around the camera, shifted ahead of its motion (the flakes live in the world, so a
## fast drone flies through them; short-lived flakes keep the box full where the camera goes).
class Snowfall:
	extends Node3D
	var camera: Camera3D
	var _p: GPUParticles3D
	var _prev := Vector3.INF
	var _vel := Vector3.ZERO

	func _ready() -> void:
		_p = GPUParticles3D.new()
		var q := GraphicsSettings.quality
		_p.amount = [2500, 5000, 8000, 11000][clampi(q, 0, 3)]
		_p.lifetime = 3.0
		_p.preprocess = 3.0
		_p.local_coords = false
		_p.visibility_aabb = AABB(Vector3(-40, -30, -40), Vector3(80, 60, 80))
		_p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = Vector3(22, 10, 22)
		pm.direction = Vector3(0.2, -1, 0.1)
		pm.spread = 12.0
		pm.initial_velocity_min = 1.0
		pm.initial_velocity_max = 2.2
		pm.gravity = Vector3(0.3, -0.9, 0.15)
		pm.turbulence_enabled = true
		pm.turbulence_noise_strength = 0.6
		pm.turbulence_noise_scale = 6.0
		pm.scale_min = 0.6
		pm.scale_max = 1.4
		_p.process_material = pm
		var quad := QuadMesh.new()
		quad.size = Vector2(0.11, 0.11)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(1, 1, 1, 0.95)
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		var tex := GradientTexture2D.new()
		tex.gradient = g
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		tex.width = 32
		tex.height = 32
		m.albedo_texture = tex
		quad.material = m
		_p.draw_pass_1 = quad
		add_child(_p)

	func _process(delta: float) -> void:
		if camera == null or not is_instance_valid(camera) or delta <= 0.0:
			return
		var p := camera.global_position
		if _prev.x < INF:
			_vel = _vel.lerp((p - _prev) / delta, 1.0 - exp(-delta / 0.5))
		_prev = p
		global_position = p + _vel * 1.0 + Vector3(0, 4, 0)

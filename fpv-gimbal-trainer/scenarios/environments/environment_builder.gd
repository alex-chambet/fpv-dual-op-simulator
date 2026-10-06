class_name EnvironmentBuilder
extends RefCounted
## Builds the world of a scenario from an EnvironmentStyle. One subclass per kind of world:
## EnvSnow, EnvMountainRoad, EnvForest and EnvGeneric (every other tag). The ScenarioRunner calls,
## in this order:
##   setup() -> base_height() (used by archetypes to place the path) -> build_terrain(path)
##   -> [legacy_drone_path()] -> populate(path, drone) -> adjust_drone_path()
## and queries ground() / extra_occlusion() during the run.

var host: ScenarioBase
var style: EnvironmentStyle
## Overrides of the environment parameters (SubjectDefinition.env_overrides).
var overrides := {}
## Added to ground() when the subject is snapped (road surface...).
var surface_offset := 0.0
## Half width of the corridor (road / trail) built along the path, m.
var corridor_half_width := 1.2
## Largest dimension of the subject, m (set by the runner; sizes corridors).
var subject_size := 1.8
## Set by the runner before populate(): the archetype and the (level-scaled) parameters of the subject.
var arch: SubjectArchetype
var params := {}


func setup(h: ScenarioBase, s: EnvironmentStyle, o: Dictionary) -> void:
	host = h
	style = s
	overrides = o
	configure()


## Reads the parameters (override first, then the style).
func opt(key: String, default: Variant) -> Variant:
	return overrides.get(key, default)


func configure() -> void:
	pass


## Ground height before any path-dependent change (road bed...). Archetypes place paths with it.
func base_height(_x: float, _z: float) -> float:
	return 0.0


## Final ground height (after build_terrain).
func ground(x: float, z: float) -> float:
	return base_height(x, z)


func subject_ground(x: float, z: float) -> float:
	return ground(x, z) + surface_offset


## Builds the terrain (and anything that depends on the path only).
func build_terrain(_path: PackedVector3Array, _plan: Dictionary) -> void:
	pass


## Scenery, obstacles (registered as occluders). `legacy` is true for the fixed scenarios.
func populate(_path: PackedVector3Array, _drone: PackedVector3Array, _plan: Dictionary,
		_legacy: bool) -> void:
	pass


## Scripted drone path of the fixed scenario of this environment (empty = none).
func legacy_drone_path(_path: PackedVector3Array) -> PackedVector3Array:
	return PackedVector3Array()


func legacy_drift() -> float:
	return 0.0


func legacy_drift_events() -> Array[float]:
	return []


## Lets the environment correct a drone path (tunnels...). Same number of points.
func adjust_drone_path(drone: PackedVector3Array, _path: PackedVector3Array) -> PackedVector3Array:
	return drone


## Height the drone must stay above (the ground, or the top of a tunnel hull...). The planner turns it
## into a smooth envelope.
func clearance(x: float, z: float) -> float:
	return ground(x, z)


## Mean speed of the subject (m/s), to turn distances into times.
func nominal_speed() -> float:
	return (float(params.get("speed_min", 8.0)) + float(params.get("speed_max", 12.0))) * 0.5


## Horizontal push getting a drone sphere out of the moving obstacles of the world (traffic...).
func dynamic_push(_pos: Vector3, _radius: float) -> Vector3:
	return Vector3.ZERO


## Extra line-of-sight blockers (tunnel hull...). from = camera, to = subject.
func extra_occlusion(_from: Vector3, _to: Vector3) -> bool:
	return false


func hud_extra() -> String:
	return ""


## What hides the subject on a line of sight: trees / rocks / walls / players / clouds / none.
func occluder_kind() -> String:
	return style.occluder_kind


## Applies sky, fog, light and post-processing to the scene nodes.
func apply_to_scene(world_env: WorldEnvironment, sun: DirectionalLight3D) -> void:
	var e := world_env.environment
	var sky_mat := e.sky.sky_material as ProceduralSkyMaterial
	sky_mat.sky_top_color = style.sky_top_color
	sky_mat.sky_horizon_color = style.sky_horizon_color
	sky_mat.sky_curve = style.sky_curve
	sky_mat.ground_horizon_color = style.ground_horizon_color
	sky_mat.ground_bottom_color = style.ground_bottom_color
	sky_mat.ground_curve = style.ground_curve
	sky_mat.sun_angle_max = style.sun_angle_max
	sky_mat.sun_curve = style.sun_curve
	e.ambient_light_energy = style.ambient_energy
	e.ssao_radius = style.ssao_radius
	e.ssao_intensity = style.ssao_intensity
	e.glow_intensity = style.glow_intensity
	e.glow_bloom = style.glow_bloom
	e.glow_hdr_threshold = style.glow_hdr_threshold
	e.adjustment_contrast = style.adjustment_contrast
	e.adjustment_saturation = style.adjustment_saturation
	e.fog_enabled = style.fog_enabled
	e.fog_light_color = style.fog_color
	e.fog_density = style.fog_density
	e.fog_sun_scatter = style.fog_sun_scatter
	e.fog_sky_affect = style.fog_sky_affect
	e.fog_aerial_perspective = style.fog_aerial_perspective
	sun.light_color = style.sun_color
	sun.light_energy = style.sun_energy
	sun.light_angular_distance = style.sun_angular_distance
	sun.directional_shadow_max_distance = style.shadow_max_distance
	sun.rotation_degrees = Vector3(-style.sun_elevation, style.sun_azimuth, 0.0)

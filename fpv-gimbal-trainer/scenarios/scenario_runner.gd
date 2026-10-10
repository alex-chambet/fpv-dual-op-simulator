class_name ScenarioRunner
extends ScenarioBase
## The one scenario that plays every sport. From a SessionConfig (a SubjectDefinition + drone
## movement + level, or a fixed scenario) it
##   1. builds the environment of the sport's tag (specific builder or generic style),
##   2. asks the movement archetype for the subject's path and speed profile,
##   3. plans the drone path (MovementPlanner, or the scripted path of a fixed scenario),
##   4. adds the scenery and the obstacles, and creates the subject (a coloured placeholder).
## No sport-specific code: everything comes from data.

@onready var world_env: WorldEnvironment = $WorldEnvironment
@onready var sun: DirectionalLight3D = $Sun

var def: SubjectDefinition
var style: EnvironmentStyle
var env: EnvironmentBuilder
var arch: SubjectArchetype
## Archetype parameters after the level scaling.
var params := {}
var plan := {}
var grass: GrassField


## Applies the graphics quality (GraphicsSettings) to the scene; called again when it changes in the pause menu.
func apply_graphics() -> void:
	GraphicsSettings.apply(world_env.environment, sun, get_viewport())
	if is_inside_tree():
		Vegetation.update_ranges(get_tree())
	if grass != null:
		grass.apply_quality()


func _default_config() -> SessionConfig:
	return ScenarioMatrix.fixed_config(ScenarioRegistry.find("ski_slope"))


func _ground_fn() -> Callable:
	return Callable(env, "ground") if env != null else Callable()


func _clearance_fn() -> Callable:
	return Callable(env, "clearance") if env != null else Callable()


func _occluder_kind() -> String:
	return env.occluder_kind() if env != null else "trees"


func _planner_extras() -> Dictionary:
	if params.is_empty():
		return {}
	return {
		"distance_scale": float(params.drone_distance_scale),
		"relative_height": bool(params.drone_relative_height),
		"min_height": float(params.drone_min_height),
		"speed_hint": arch.expected_speed(plan, params),
		"profile": plan.get("profile", PackedFloat32Array()),
		"speed_variation": arch.speed_variation(params) if arch.uses_default_speed() else 0.0,
		"min_speed": maxf(0.05, 0.3 * float(params.speed_min)),
		"subject_size": def.effective_size(),
	}


func dynamic_push(pos: Vector3, radius: float) -> Vector3:
	return env.dynamic_push(pos, radius) if env != null else Vector3.ZERO


func _extra_occlusion(from: Vector3, to: Vector3) -> bool:
	return env.extra_occlusion(from, to) if env != null else false


func _hud_extra() -> String:
	# The hint of a guided course (e.g. "the drone swings around the road...") does not apply to generated sessions
	return env.hud_extra() if env != null and matrix != null and matrix.fixed else ""


func _build_scenario() -> void:
	var cfg := matrix
	def = cfg.subject
	scenario_id = cfg.scenario_id()
	scenario_title = cfg.title()

	# the environment's look, in the light and weather of the session
	style = Ambience.variant(EnvironmentRegistry.style_for(def.environment), cfg.ambience)
	env = EnvironmentRegistry.create(style, self, def.env_overrides)
	env.subject_size = def.effective_size()
	env.apply_to_scene(world_env, sun)
	Ambience.finish(cfg.ambience, world_env.environment, style)
	Ambience.add_weather(cfg.ambience, self, flight.rig.camera)
	apply_graphics()

	arch = ArchetypeRegistry.get_archetype(def.archetype)
	params = arch.scale_for_level(def.resolved_params(), cfg.params)
	env.arch = arch
	env.params = params

	# Subject path, then the terrain built around it
	plan = _generate_plan()
	env.params = params
	subject_pts = plan.points
	env.build_terrain(subject_pts, plan)

	# Drone path
	if cfg.fixed:
		drone_pts = env.legacy_drone_path(subject_pts)
		drone_drift = env.legacy_drift()
		drift_events.assign(env.legacy_drift_events())
	else:
		drone_pts = plan_drone_path()
	if cfg.fixed:
		# The scripted drone of a guided course flies over the tunnel (chase-and-climb path): smooth what
		# the environment changed and keep it above the ground / the hull. A generated session is planned
		# smooth and above the hull; the tunnel is then just one more thing that can hide the subject.
		drone_pts = env.adjust_drone_path(drone_pts, subject_pts)
		plan_ctx = _planner_context()
		plan_ctx["tau"] = 0.05  # the guided courses are not filtered: the drone is at point i when the subject is
		drone_pts = MovementPlanner.condition(drone_pts, subject_pts, plan_ctx)

	env.populate(subject_pts, drone_pts, plan, cfg.fixed)
	_add_jump_markers()
	if env.terrain_material != null:
		Ambience.tune_ground(cfg.ambience, env.terrain_material)
	if env.terrain_rect.has_area() and env.terrain_material != null:
		FarScenery.build(env, env.terrain_rect, env.terrain_material, env.far_scenery())
	flight.rig.camera.far = 9000.0  # the distant mountains
	var gp := env.grass_params()
	if not gp.is_empty() and not TerrainBuilder.last_info.is_empty():
		grass = GrassField.new()
		grass.name = "Grass"
		add_child(grass)
		grass.setup(gp, TerrainBuilder.last_info, env.ground_mask, flight.rig.camera)

	var s := ArchetypeSubject.new(def, arch, params, plan, world_seed)
	if arch.uses_ground():
		s.ground_height = Callable(env, "subject_ground")
	subject = s


## Generates the subject's path. A sheet that gives a target `duration` and no explicit path_length
## would otherwise run longer than announced (a winding or sloping path is longer than its extent
## along Z), so the length is corrected until the nominal run time matches the duration. Each pass
## uses the same random seed, so the shape of the path stays the same. Sets params.path_length.
func _generate_plan() -> Dictionary:
	var fit := arch.fits_duration() and float(params.path_length) <= 0.0 and float(params.duration) > 0.0
	var length := arch.path_length(params)
	var p := params
	var result := {}
	for _pass in (4 if fit else 1):
		p = params.duplicate()
		if fit:
			p.path_length = length
		var rng := RandomNumberGenerator.new()
		rng.seed = 1000 + world_seed
		result = arch.generate(ArchetypeContext.new(env, p, rng, def))
		if not fit:
			break
		var factor := clampf(float(params.duration) / maxf(arch.nominal_time(result, p), 0.1), 0.3, 3.0)
		if absf(factor - 1.0) < 0.04:
			break
		length *= factor
	params = p
	return result


# --- Jumps -------------------------------------------------------------------------------------------

## A kicker (wedge) or a fence at each take-off.
func _add_jump_markers() -> void:
	var visual := str(params.get("jump_visual", "ramp"))
	if visual == "none" or style.has_water:
		return
	var pts: PackedVector3Array = plan.points
	var snow := def.environment == "neige" or def.environment == "glace"
	var mat := PathSubject.make_mat(Color(0.93, 0.96, 1.0) if snow else Color(0.5, 0.36, 0.22), 0.8)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for ev in plan.events:
		if ev.get("type", "") != "jump":
			continue
		var a: Vector3 = pts[int(ev.ramp_i)]
		var b: Vector3 = ev.p0
		if visual == "obstacle":
			_add_fence(b, a, mat)
		else:
			_add_ramp(a, b, mat)


func _add_ramp(a: Vector3, b: Vector3, mat: Material) -> void:
	var dir := b - a
	dir.y = 0.0
	if dir.length() < 0.5:
		return
	var right := dir.normalized().cross(Vector3.UP) * 1.2
	var a_top := a
	var b_top := b
	var a_bot := Vector3(a.x, env.ground(a.x, a.z), a.z)
	var b_bot := Vector3(b.x, env.ground(b.x, b.z), b.z)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var quads := [
		[a_top - right, a_top + right, b_top + right, b_top - right],      # top
		[b_top - right, b_top + right, b_bot + right, b_bot - right],      # back face
		[a_top - right, b_top - right, b_bot - right, a_bot - right],      # left side
		[a_top + right, a_bot + right, b_bot + right, b_top + right],      # right side
	]
	for q in quads:
		for idx in [0, 1, 2, 0, 2, 3]:
			st.add_vertex(q[idx])
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "Kicker"
	mi.mesh = st.commit()
	mi.material_override = mat
	add_child(mi)


func _add_fence(at: Vector3, from: Vector3, mat: Material) -> void:
	var dir := at - from
	dir.y = 0.0
	var yaw := atan2(dir.x, dir.z) if dir.length() > 0.1 else 0.0
	var g := env.ground(at.x, at.z)
	for side in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		var pb := BoxMesh.new()
		pb.size = Vector3(0.15, 1.5, 0.15)
		post.mesh = pb
		post.material_override = mat
		post.position = Vector3(at.x, g + 0.75, at.z) + Vector3(cos(yaw), 0.0, -sin(yaw)) * side * 1.6
		add_child(post)
	var rail := MeshInstance3D.new()
	var rb := BoxMesh.new()
	rb.size = Vector3(3.4, 0.15, 0.15)
	rail.mesh = rb
	rail.material_override = PathSubject.make_mat(Color(0.9, 0.9, 0.9), 0.7)
	rail.position = Vector3(at.x, g + 1.2, at.z)
	rail.rotation.y = yaw
	add_child(rail)

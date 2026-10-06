class_name ArchetypeGlissePente
extends SubjectArchetype
## GLISSE_PENTE: descent of a slope with S-turns (alpine skiing, snowboard, luge, downhill bike).
## Path: x(z) = amplitude * (1 + weave * sin(slow modulation)) * sin(2 pi z / period), going down +Z.

const TRAIL_STEP := 0.6
const TRAIL_MAX := 1800


func id() -> String:
	return "GLISSE_PENTE"


func summary() -> String:
	return "Descent with S-turns: ski, snowboard, luge, downhill sports."


func defaults() -> Dictionary:
	var d := common_defaults()
	d.merge({
		"subject_size": 1.8,
		"speed_min": 6.0, "speed_max": 16.0, "speed_variability": 1.0,
		"turn_frequency": 2.857142857142857, "lateral_amplitude": 9.0,
		"lean_max_deg": 30.0, "lean_gain": 0.8,
		"sample_step": 6.0,
		"weave_ratio": 0.25, "weave_period": 314.1592653589793,
		"gates": true, "leaves_tracks": true, "spray": true,
	}, true)
	return d


func generate(ctx: ArchetypeContext) -> Dictionary:
	var p := ctx.params
	var length := path_length(p)
	var step := float(p.sample_step)
	if float(p.jump_frequency) > 0.0:
		step = minf(step, 2.0)
	var n := int(length / step) + 1
	var pts := PackedVector3Array()
	for i in n:
		var z := i * step
		var x := _x(z, p)
		pts.append(Vector3(x, ctx.ground(x, z), z))
	var events := inject_jumps(pts, ctx, step)
	var speeds := PackedFloat32Array()
	if float(p.cornering_accel) > 0.0:
		speeds = PathUtil.speeds_from_curvature(pts, float(p.cornering_accel), float(p.speed_min), float(p.speed_max))
	return finish_plan(pts, speeds, events)


func _x(z: float, p: Dictionary) -> float:
	var period := 200.0 / maxf(float(p.turn_frequency), 0.01)
	return float(p.lateral_amplitude) * (1.0 + float(p.weave_ratio) * sin(z * TAU / float(p.weave_period))) \
			* sin(z * TAU / period)


func lateral_fn(p: Dictionary, _pts: PackedVector3Array) -> Callable:
	return func(z: float) -> float: return _x(z, p)


# --- Effects: tracks in the snow and spray --------------------------------------------------------

func on_ready(s: ArchetypeSubject) -> void:
	if bool(s.params.leaves_tracks):
		_build_trail(s)
	if bool(s.params.spray):
		_build_spray(s)


func animate(s: ArchetypeSubject, delta: float) -> void:
	super.animate(s, delta)
	if s.state.has("trail"):
		_update_trail(s)
	if s.state.has("spray"):
		var spray: GPUParticles3D = s.state["spray"]
		spray.emitting = absf(s.lean_deg) > 8.0 and s.speed_now > 4.0


func _build_trail(s: ArchetypeSubject) -> void:
	var box := BoxMesh.new()
	box.size = Vector3(0.1, 0.02, TRAIL_STEP * 1.25)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.6, 0.66, 0.8)
	mat.roughness = 1.0
	box.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = box
	mm.instance_count = TRAIL_MAX
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	s.add_child(mmi)
	s.state["trail"] = mm
	s.state["trail_count"] = 0
	s.state["trail_last"] = Vector3(1e9, 1e9, 1e9)


func _update_trail(s: ArchetypeSubject) -> void:
	var mm: MultiMesh = s.state["trail"]
	var gp := s.follower.global_position
	var last: Vector3 = s.state["trail_last"]
	var count: int = s.state["trail_count"]
	if last.x > 1e8:
		last = gp
	var b := s.follower.global_basis
	# Several segments per frame at high speed, so the tracks stay continuous
	while gp.distance_to(last) >= TRAIL_STEP and count + 2 <= TRAIL_MAX:
		last += (gp - last).normalized() * TRAIL_STEP
		for side in [-1.0, 1.0]:
			var q: Vector3 = last + b.x * side * 0.2
			if s.ground_height.is_valid():
				q.y = float(s.ground_height.call(q.x, q.z)) + 0.02
			mm.set_instance_transform(count, Transform3D(b, q))
			count += 1
	mm.visible_instance_count = count
	s.state["trail_count"] = count
	s.state["trail_last"] = last


func _build_spray(s: ArchetypeSubject) -> void:
	var spray := GPUParticles3D.new()
	spray.amount = 160
	spray.lifetime = 1.0
	spray.local_coords = false
	spray.emitting = false
	spray.position = Vector3(0, 0.15, 0.7)
	spray.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0.6)
	pm.spread = 35.0
	pm.initial_velocity_min = 1.5
	pm.initial_velocity_max = 4.0
	pm.gravity = Vector3(0, -5.0, 0)
	pm.damping_min = 0.5
	pm.damping_max = 1.0
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0.85))
	ramp.set_color(1, Color(1, 1, 1, 0.0))
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp
	pm.color_ramp = ramp_tex
	spray.process_material = pm
	var puff := SphereMesh.new()
	puff.radius = 0.12
	puff.height = 0.24
	puff.radial_segments = 6
	puff.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(1, 1, 1)
	puff.material = mat
	spray.draw_pass_1 = puff
	s.model.add_child(spray)
	s.state["spray"] = spray

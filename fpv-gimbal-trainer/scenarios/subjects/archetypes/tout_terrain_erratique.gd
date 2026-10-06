class_name ArchetypeToutTerrainErratique
extends SubjectArchetype
## TOUT_TERRAIN_ERRATIQUE: irregular speed and path with jumps (mountain bike, motocross, quad,
## rally). The path mixes two waves with smooth random drift; the speed follows a random profile
## and brakes in turns; the body bounces over the bumps.


func id() -> String:
	return "TOUT_TERRAIN_ERRATIQUE"


func summary() -> String:
	return "Irregular speed and path, jumps: mountain bike, motocross, quad, rally."


func defaults() -> Dictionary:
	var d := common_defaults()
	d.merge({
		"subject_size": 2.0,
		"speed_min": 5.0, "speed_max": 14.0, "speed_variability": 0.8,
		"turn_frequency": 3.0, "lateral_amplitude": 10.0,
		"jump_frequency": 0.35, "jump_height": 1.8, "jump_length": 12.0,
		"lean_max_deg": 25.0, "lean_gain": 0.7,
		"sample_step": 4.0, "cornering_accel": 6.0,
		"irregularity": 0.6, "bump": 0.07,
	}, true)
	return d


func follows_slope() -> bool:
	return true


func generate(ctx: ArchetypeContext) -> Dictionary:
	var p := ctx.params
	var rng := ctx.rng
	var length := path_length(p)
	var step := float(p.sample_step)
	if float(p.jump_frequency) > 0.0:
		step = minf(step, 2.0)
	var n := int(length / step) + 1
	var w1 := TAU * float(p.turn_frequency) / 200.0
	var amp := float(p.lateral_amplitude)
	var irr := clampf(float(p.irregularity), 0.0, 1.0)
	var ph1 := rng.randf() * TAU
	var ph2 := rng.randf() * TAU
	var drift := FastNoiseLite.new()
	drift.seed = rng.randi()
	drift.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	drift.frequency = 0.015
	var pts := PackedVector3Array()
	for i in n:
		var z := i * step
		var x := amp * (0.65 * sin(z * w1 + ph1) + 0.35 * sin(z * w1 * 2.3 + ph2)) \
				+ irr * amp * 1.2 * drift.get_noise_1d(z)
		pts.append(Vector3(x, ctx.ground(x, z), z))
	var events := inject_jumps(pts, ctx, step)

	# Random smooth speed profile, limited by the curvature
	var vmin := float(p.speed_min)
	var vmax := float(p.speed_max)
	var sp := FastNoiseLite.new()
	sp.seed = rng.randi()
	sp.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	sp.frequency = 0.02
	var curve_v := PackedFloat32Array()
	if float(p.cornering_accel) > 0.0:
		curve_v = PathUtil.speeds_from_curvature(pts, float(p.cornering_accel), vmin, vmax)
	var speeds := PackedFloat32Array()
	for i in n:
		var u := clampf(0.5 + 0.5 * irr * 1.6 * sp.get_noise_1d(i * step), 0.0, 1.0)
		var v := lerpf(vmin, vmax, u)
		if not curve_v.is_empty():
			v = minf(v, curve_v[i])
		speeds.append(v)
	return finish_plan(pts, speeds, events)


func animate(s: ArchetypeSubject, delta: float) -> void:
	super.animate(s, delta)
	var t := float(s.state.get("t", 0.0)) + delta
	s.state["t"] = t
	var bump := float(s.params.bump) * clampf(s.speed_now / 8.0, 0.2, 1.5)
	var body: Node3D = s.parts["body"]
	if s.current_jump().is_empty():
		body.rotation.x = bump * (0.6 * sin(t * 7.3) + 0.4 * sin(t * 13.1 + 1.0))
		body.rotation.z = bump * 0.6 * sin(t * 5.1)
		body.position.y = absf(sin(t * 9.0)) * bump * 0.5

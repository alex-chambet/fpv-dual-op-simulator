class_name ArchetypeCourseSolCyclique
extends SubjectArchetype
## COURSE_SOL_CYCLIQUE: a cyclic gait on the ground along a winding path (running, trail, walking,
## cross-country skiing, climbing, horse gallop, skating). The path is the sum of a main wave and
## shorter wiggles; the speed drops in tight turns; legs / arms swing at `cadence`.


func id() -> String:
	return "COURSE_SOL_CYCLIQUE"


func summary() -> String:
	return "Cyclic gait on a winding path: running, trail, walking, horse gallop, skating."


func defaults() -> Dictionary:
	var d := common_defaults()
	d.merge({
		"subject_size": 1.8,
		"speed_min": 3.0, "speed_max": 5.5, "speed_variability": 0.5,
		"turn_frequency": 1.768388256, "lateral_amplitude": 14.0,
		"lean_max_deg": 14.0, "lean_gain": 0.6,
		"sample_step": 4.0, "cornering_accel": 3.0,
		"cadence": 1.7, "cadence_coupling": 0.5,
		"wiggle_ratio": 0.571428571, "wiggle_period_ratio": 0.405555556,
		"bob": 0.05, "limb_swing": 0.8,
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
	var w1 := TAU * float(p.turn_frequency) / 200.0
	var a := float(p.lateral_amplitude)
	return a * sin(z * w1) + a * float(p.wiggle_ratio) * sin(z * w1 / float(p.wiggle_period_ratio) + 1.0)


func lateral_fn(p: Dictionary, _pts: PackedVector3Array) -> Callable:
	return func(z: float) -> float: return _x(z, p)

class_name ArchetypeSautAcrobatique
extends SubjectArchetype
## SAUT_ACROBATIQUE: run-up (the speed builds up), then jump_count jumps, each made of a kicker, an
## aerial phase (ballistic arc, somersaults / spin) and a landing followed by a rollout (freestyle
## skiing / snowboard, ski jumping, skate, BMX, show jumping).


func id() -> String:
	return "SAUT_ACROBATIQUE"


func summary() -> String:
	return "Run-up, aerial phase, landing: freestyle, ski jumping, skate, BMX, show jumping."


func defaults() -> Dictionary:
	var d := common_defaults()
	d.merge({
		"subject_size": 1.8,
		"speed_min": 8.0, "speed_max": 14.0, "speed_variability": 0.3,
		"turn_frequency": 0.8, "lateral_amplitude": 6.0,
		"lean_max_deg": 25.0, "lean_gain": 0.7,
		"sample_step": 2.0,
		"jump_count": 3, "approach_length": 80.0, "rollout_length": 45.0,
		"jump_length": 22.0, "jump_height": 3.5, "flips": 1, "spin_deg": 180.0,
	}, true)
	return d


## The length comes from approach_length, jump_count, jump_length and rollout_length.
func fits_duration() -> bool:
	return false


func generate(ctx: ArchetypeContext) -> Dictionary:
	var p := ctx.params
	var count := maxi(1, roundi(float(p.jump_count)))
	var approach := float(p.approach_length)
	var rollout := float(p.rollout_length)
	var jump_len := float(p.jump_length)
	var step := minf(float(p.sample_step), 2.0)
	var total := approach + count * (jump_len + rollout)
	var period := 200.0 / maxf(float(p.turn_frequency), 0.01)
	var pts := PackedVector3Array()
	var speeds := PackedFloat32Array()
	var vmin := float(p.speed_min)
	var vmax := float(p.speed_max)
	for i in int(total / step) + 1:
		var z := i * step
		var x := float(p.lateral_amplitude) * sin(z * TAU / period)
		pts.append(Vector3(x, ctx.ground(x, z), z))
		speeds.append(lerpf(vmin, vmax, smoothstep(0.0, maxf(approach, 1.0), z)))  # the run-up builds speed
	var len_n := maxi(3, int(jump_len / step))
	var ramp_n := maxi(2, int(5.0 / step))
	var height := float(p.jump_height)
	var ramp_h := minf(0.45 * height + 0.2, 1.6)
	var events: Array = []
	for k in count:
		var i0 := int((approach + k * (jump_len + rollout)) / step)
		events.append(PathUtil.apply_jump(pts, ctx.ground_fn(), i0, i0 + len_n, height, ramp_n, ramp_h))
	return finish_plan(pts, speeds, events)

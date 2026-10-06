class_name ArchetypeEauSurface
extends SubjectArchetype
## EAU_SURFACE: lateral movement with oscillation on a surface (kayak, surf, wakeboard, sailing,
## rowing, paddle). Wide gentle weaves plus a small lateral oscillation; the placeholder bobs and
## rolls on the waves; `surge` makes the speed pulse at the stroke cadence (rowing, paddling).


func id() -> String:
	return "EAU_SURFACE"


func summary() -> String:
	return "Lateral movement with oscillation on a surface: kayak, surf, wakeboard, sailing, rowing, paddle."


func defaults() -> Dictionary:
	var d := common_defaults()
	d.merge({
		"subject_size": 3.0,
		"speed_min": 3.0, "speed_max": 6.0, "speed_variability": 0.4,
		"turn_frequency": 1.5, "lateral_amplitude": 8.0,
		"lean_max_deg": 12.0, "lean_gain": 0.6,
		"sample_step": 6.0, "cadence": 0.8, "cadence_coupling": 0.0,
		"wave_period": 3.2, "wave_roll_deg": 6.0, "wave_heave": 0.12,
		"surge": 0.0, "osc_amplitude": 0.8, "osc_period": 18.0,
	}, true)
	return d


func generate(ctx: ArchetypeContext) -> Dictionary:
	var p := ctx.params
	var length := path_length(p)
	var step := float(p.sample_step)
	if float(p.jump_frequency) > 0.0:
		step = minf(step, 2.0)
	var period := 200.0 / maxf(float(p.turn_frequency), 0.01)
	var pts := PackedVector3Array()
	for i in int(length / step) + 1:
		var z := i * step
		var x := float(p.lateral_amplitude) * sin(z * TAU / period) \
				+ float(p.osc_amplitude) * sin(z * TAU / maxf(float(p.osc_period), 1.0))
		pts.append(Vector3(x, ctx.ground(x, z), z))
	var events := inject_jumps(pts, ctx, step)
	return finish_plan(pts, PackedFloat32Array(), events)


func compute_speed(s: ArchetypeSubject, _delta: float) -> float:
	var v := s.default_speed()
	var surge := float(s.params.surge)
	if surge > 0.0 and float(s.params.cadence) > 0.0:
		v *= 1.0 + surge * sin(TAU * float(s.params.cadence) * float(s._t))
	return maxf(v, s.min_speed)


func animate(s: ArchetypeSubject, delta: float) -> void:
	super.animate(s, delta)
	var t := float(s.state.get("wave_t", 0.0)) + delta
	s.state["wave_t"] = t
	var w := TAU * t / maxf(float(s.params.wave_period), 0.5)
	var body: Node3D = s.parts["body"]
	if s.current_jump().is_empty():
		body.position.y = float(s.params.wave_heave) * sin(w)
		body.rotation.z = deg_to_rad(float(s.params.wave_roll_deg)) * sin(w * 0.8 + 1.0)
		body.rotation.x = deg_to_rad(float(s.params.wave_roll_deg)) * 0.4 * sin(w * 1.1)

class_name ArchetypeVehiculeRoute
extends SubjectArchetype
## VEHICULE_ROUTE: follows a road at a steady speed, braking in bends (car, motorbike, road bike,
## kart). Layouts: 'switchback' (hairpins: straight legs of 2 x lateral_amplitude joined by half
## circles; legs = turn_frequency x path_length / 100) or 'winding' (sinusoidal road).

const ARC_STEPS := 12


func id() -> String:
	return "VEHICULE_ROUTE"


func summary() -> String:
	return "Follows a road, steady speed, braking in bends: car, motorbike, road bike, kart."


func defaults() -> Dictionary:
	var d := common_defaults()
	d.merge({
		"subject_size": 4.2,
		"speed_min": 6.5, "speed_max": 16.0, "speed_variability": 0.25,
		"turn_frequency": 1.0, "lateral_amplitude": 35.0, "turn_radius": 12.5,
		"lean_max_deg": 5.0, "lean_gain": 0.15,
		"sample_step": 5.0, "cornering_accel": 5.5, "path_length": 600.0,
		"layout": "switchback",
	}, true)
	return d


func follows_slope() -> bool:
	return true


func generate(ctx: ArchetypeContext) -> Dictionary:
	var p := ctx.params
	var pts := PackedVector3Array()
	var step := float(p.sample_step)
	if str(p.layout) == "winding":
		var length := path_length(p)
		var period := 200.0 / maxf(float(p.turn_frequency), 0.01)
		for i in int(length / step) + 1:
			var z := i * step
			var x := float(p.lateral_amplitude) * sin(z * TAU / period)
			pts.append(Vector3(x, ctx.ground(x, z), z))
	else:
		pts = _switchback(ctx, p, step)
	var speeds := PackedFloat32Array()
	if float(p.cornering_accel) > 0.0:
		speeds = PathUtil.speeds_from_curvature(pts, float(p.cornering_accel), float(p.speed_min), float(p.speed_max))
	return finish_plan(pts, speeds, [])


## Hairpin road in plan: straight legs along x joined by semicircles, climbing along +Z.
func _switchback(ctx: ArchetypeContext, p: Dictionary, step: float) -> PackedVector3Array:
	var legs := clampi(roundi(float(p.turn_frequency) * path_length(p) / 100.0), 3, 12)
	var half := float(p.lateral_amplitude)
	var r := float(p.turn_radius)
	var out := PackedVector3Array()
	for k in legs:
		var z0 := k * 2.0 * r
		var dir := 1.0 if k % 2 == 0 else -1.0
		var x_from := -half * dir
		for i in int(2.0 * half / step) + 1:
			var x := x_from + dir * i * step
			out.append(Vector3(x, ctx.ground(x, z0), z0))
		if k < legs - 1:
			var cx := half * dir
			for a in range(1, ARC_STEPS):
				var th := PI * a / ARC_STEPS
				var x := cx + dir * r * sin(th)
				var z := z0 + r - r * cos(th)
				out.append(Vector3(x, ctx.ground(x, z), z))
	return out

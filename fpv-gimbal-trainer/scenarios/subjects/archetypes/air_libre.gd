class_name ArchetypeAirLibre
extends SubjectArchetype
## AIR_LIBRE: slow, ample 3D trajectory with altitude changes (paraglider, wingsuit, parachute).
## The altitude is relative to the start ground (never lower than 25 m above the terrain); the
## horizontal path is a lazy S; `descent_per_100m` makes the subject lose height.


func id() -> String:
	return "AIR_LIBRE"


func summary() -> String:
	return "Slow, ample 3D trajectory with altitude changes: paraglider, wingsuit, parachute."


func defaults() -> Dictionary:
	var d := common_defaults()
	d.merge({
		"subject_size": 8.0,
		"speed_min": 9.0, "speed_max": 14.0, "speed_variability": 0.3,
		"turn_frequency": 0.25, "lateral_amplitude": 150.0,
		"lean_max_deg": 30.0, "lean_gain": 1.0,
		"sample_step": 20.0,
		"altitude": 180.0, "altitude_variation": 40.0, "altitude_period": 700.0,
		"descent_per_100m": 3.0,
		"drone_distance_scale": 4.0, "drone_min_height": 15.0, "drone_relative_height": true,
	}, true)
	return d


func uses_ground() -> bool:
	return false


func follows_slope() -> bool:
	return true


func generate(ctx: ArchetypeContext) -> Dictionary:
	var p := ctx.params
	var length := path_length(p)
	var step := float(p.sample_step)
	var period := 200.0 / maxf(float(p.turn_frequency), 0.01)
	var base := ctx.ground(0.0, 0.0)
	var pts := PackedVector3Array()
	for i in int(length / step) + 1:
		var z := i * step
		var x := float(p.lateral_amplitude) * sin(z * TAU / period)
		var alt := float(p.altitude) + float(p.altitude_variation) * sin(z * TAU / maxf(float(p.altitude_period), 10.0) + 1.0) \
				- float(p.descent_per_100m) * z / 100.0
		var y := maxf(base + alt, ctx.ground(x, z) + 25.0)
		pts.append(Vector3(x, y, z))
	return finish_plan(pts, PackedFloat32Array(), [])


func animate(s: ArchetypeSubject, delta: float) -> void:
	super.animate(s, delta)
	var t := float(s.state.get("t", 0.0)) + delta
	s.state["t"] = t
	var body: Node3D = s.parts["body"]
	body.rotation.z = 0.06 * sin(t * 0.9)
	body.rotation.x = 0.04 * sin(t * 0.7 + 1.0)

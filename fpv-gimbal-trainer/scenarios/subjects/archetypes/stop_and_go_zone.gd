class_name ArchetypeStopAndGoZone
extends SubjectArchetype
## STOP_AND_GO_ZONE: moves inside a bounded zone with sudden accelerations, pauses and
## unpredictable changes of direction (football, rugby, basketball, tennis, hockey).
## Path: a random tour of waypoints inside the zone (each leg turns by 35-150 degrees),
## rounded at the corners. Speed: bursts (accelerate, cruise, brake, sometimes pause) driven by a
## small state machine, independent of the path.


func id() -> String:
	return "STOP_AND_GO_ZONE"


func summary() -> String:
	return "Bounded zone, sudden accelerations and unpredictable turns: football, rugby, basketball, tennis, hockey."


func defaults() -> Dictionary:
	var d := common_defaults()
	d.merge({
		"subject_size": 1.8,
		"speed_min": 0.6, "speed_max": 9.0, "speed_variability": 0.0,
		"turn_frequency": 5.0, "lateral_amplitude": 0.0,
		"lean_max_deg": 18.0, "lean_gain": 0.8,
		"sample_step": 2.0, "cadence": 2.4, "cadence_coupling": 1.0,
		"zone_width": 60.0, "zone_length": 100.0, "corner_radius": 2.0,
		"pause_probability": 0.35, "burst_ratio": 0.8,
		"bob": 0.05, "limb_swing": 0.9,
		"drone_distance_scale": 1.3,
	}, true)
	return d


## Mean speed (m/s) of the burst state machine, from the average duration of its phases: accelerate
## 0.8 s, cruise 1.1 s, brake 0.55 s, then a pause of 0.85 s with probability pause_probability.
func mean_speed(p: Dictionary) -> float:
	var vmin := float(p.speed_min)
	var top := maxf(0.8 * float(p.burst_ratio) * float(p.speed_max), 2.0 * vmin)
	var low := 1.75 * vmin
	var q := float(p.pause_probability)
	var dist := 0.5 * (low + top) * (0.8 + 0.55) + top * 1.1 + vmin * 0.85 * q
	return dist / (0.8 + 1.1 + 0.55 + 0.85 * q)


func uses_default_speed() -> bool:
	return false


func expected_speed(_plan: Dictionary, p: Dictionary) -> float:
	return mean_speed(p)


## Nominal time: the length of the (corner-rounded) path at the mean speed of the state machine.
func nominal_time(plan: Dictionary, p: Dictionary) -> float:
	return PathUtil.total_length(plan.points) / maxf(mean_speed(p), 0.05)


## Length of the waypoint tour (the rounded path is a little shorter).
func path_length(p: Dictionary) -> float:
	var l := float(p.path_length)
	if l > 0.0:
		return l
	return float(p.duration) * mean_speed(p)


func generate(ctx: ArchetypeContext) -> Dictionary:
	var p := ctx.params
	var rng := ctx.rng
	var width := float(p.zone_width)
	var depth := float(p.zone_length)
	var zone := Rect2(-width * 0.5, 0.0, width, depth)
	var inner := zone.grow(-minf(2.5, 0.25 * minf(width, depth)))  # keep away from the edges (less in a tiny zone)
	var length := path_length(p)
	# A leg never exceeds what fits in the zone (squash court, small gym...)
	var spacing := minf(100.0 / maxf(float(p.turn_frequency), 0.1), 0.7 * maxf(inner.size.x, inner.size.y))
	var center := Vector2(0.0, depth * 0.5)
	var pos := center
	var heading := rng.randf() * TAU
	var wps := PackedVector2Array([pos])
	var total := 0.0
	var guard := 0
	while total < length and guard < 600:
		guard += 1
		var next := Vector2.ZERO
		var found := false
		for _attempt in 12:
			var turn := deg_to_rad(rng.randf_range(35.0, 150.0)) * (-1.0 if rng.randf() < 0.5 else 1.0)
			var h := heading + turn
			var cand := pos + Vector2(cos(h), sin(h)) * spacing * rng.randf_range(0.6, 1.5)
			if inner.has_point(cand):
				next = cand
				heading = h
				found = true
				break
		if not found:  # cornered: go to another point of the zone (never straight back where we came from)
			for _attempt in 20:
				var cand := Vector2(rng.randf_range(inner.position.x, inner.end.x), rng.randf_range(inner.position.y, inner.end.y))
				if cand.distance_to(pos) >= spacing * 0.4:
					next = cand
					found = true
					break
			if not found:  # tiny zone: the farthest corner
				next = inner.position
				for corner in [Vector2(inner.end.x, inner.position.y), inner.end, Vector2(inner.position.x, inner.end.y)]:
					if corner.distance_to(pos) > next.distance_to(pos):
						next = corner
			heading = (next - pos).angle()
		total += pos.distance_to(next)
		pos = next
		wps.append(pos)
	var poly := PathUtil.fillet(wps, float(p.corner_radius), float(p.sample_step))
	return finish_plan(PathUtil.lift(poly, ctx.ground_fn()), PackedFloat32Array(), [], zone)


# --- Speed bursts ----------------------------------------------------------------------------------

func compute_speed(s: ArchetypeSubject, delta: float) -> float:
	var st := s.state
	var vmin := float(s.params.speed_min)
	var vmax := float(s.params.speed_max)
	var r: RandomNumberGenerator
	if not st.has("rng"):
		r = RandomNumberGenerator.new()
		r.seed = s.seed_value * 7919 + 13
		st["rng"] = r
		_enter_phase(st, "pause", vmin, vmin, r.randf_range(0.2, 0.6))
	r = st["rng"]
	st["left"] = float(st["left"]) - delta
	var guard := 0
	while float(st["left"]) <= 0.0 and guard < 8:
		_next(st, r, vmin, vmax, s.params)
		guard += 1
	var u := 1.0 - clampf(float(st["left"]) / maxf(float(st["dur"]), 0.001), 0.0, 1.0)
	var v := float(st["v_to"])
	if st["phase"] == "accel" or st["phase"] == "brake":
		v = lerpf(float(st["v_from"]), float(st["v_to"]), smoothstep(0.0, 1.0, u))
	return maxf(v, s.min_speed)


func _next(st: Dictionary, r: RandomNumberGenerator, vmin: float, vmax: float, p: Dictionary) -> void:
	var phase: String = st["phase"]
	var v_end := float(st["v_to"])
	match phase:
		"pause", "brake":
			if phase == "brake" and r.randf() < float(p.pause_probability):
				_enter_phase(st, "pause", v_end, vmin, r.randf_range(0.3, 1.4))
			else:
				var target := maxf(vmax * float(p.burst_ratio) * r.randf_range(0.6, 1.0), vmin * 2.0)
				_enter_phase(st, "accel", v_end, target, r.randf_range(0.5, 1.1))
		"accel":
			_enter_phase(st, "cruise", v_end, v_end, r.randf_range(0.4, 1.8))
		_:
			_enter_phase(st, "brake", v_end, maxf(vmin * r.randf_range(1.0, 2.5), vmin), r.randf_range(0.3, 0.8))


func _enter_phase(st: Dictionary, phase: String, v_from: float, v_to: float, dur: float) -> void:
	st["phase"] = phase
	st["v_from"] = v_from
	st["v_to"] = v_to
	st["dur"] = dur
	st["left"] = dur

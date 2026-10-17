class_name ArchetypeCircuit
extends SubjectArchetype
## CIRCUIT: a racing car doing a full lap of a closed circuit (the Nürburgring Grand-Prix-Strecke,
## see CircuitTrack). Nothing is drawn at random: the line and the speed come from the track itself.
##
##  - the path is the racing line of the circuit (CircuitLayout.racing_line): wide into a corner,
##    on the apex, wide again on the exit, inside the white lines;
##  - the speed comes from a lap simulation of a real car (RaceCarPhysics): grip circle with
##    aerodynamic downforce, engine power and traction, drag, slope. The car therefore brakes hard
##    and late into the slow corners, holds a steady speed through them and pulls away on the exit -
##    and every change of speed has a visible cause on the track, which is what lets the operator
##    anticipate.
##
## The lap starts and ends on the start / finish line, at racing speed (a flying lap).

const SAMPLE := 3.0   ## m between path points, before the scale


func id() -> String:
	return "CIRCUIT"


func summary() -> String:
	return "A racing car on a full lap of a circuit: racing line and speed from a real car model."


func defaults() -> Dictionary:
	var d := common_defaults()
	d.merge({
		"subject_size": 4.6,
		"speed_min": 8.0, "speed_max": 60.0, "speed_variability": 0.0,
		"lean_max_deg": 3.0, "lean_gain": 0.12,
		"sample_step": SAMPLE,
		"cornering_accel": 0.0,
		"drone_distance_scale": 1.1, "drone_min_height": 2.5,
		# A racing car brakes at nearly 2 g and corners at 1.5 g: a chase drone has to pull as hard to
		# stay with it (a real FPV chase drone does, and far harder). Without this the planner would
		# spend its whole budget trying to meet a limit made for a skier, and end up flying worse.
		"drone_smoothing": 2.0, "drone_accel_relax": 3.8,
		"car": "gt4", "track_scale": 0.5, "line_margin": 1.5, "line_swing": 1.0,
		"grip": 0.0, "power": 0.0, "pace": 1.0,
	}, true)
	return d


func follows_slope() -> bool:
	return true


func fits_duration() -> bool:
	return false   # the lap is as long as the circuit is


func path_length(p: Dictionary) -> float:
	return CircuitTrack.LAP_LENGTH * float(p.get("track_scale", 0.5))


## The car of this sheet: the preset named by `car`, with `grip`, `power` and `pace` overriding it
## when they are set (so a sheet can slow a car down without describing a whole new one).
static func car_of(p: Dictionary) -> Dictionary:
	var c := RaceCarPhysics.car(str(p.get("car", "gt4")))
	if float(p.get("grip", 0.0)) > 0.0:
		c["grip"] = float(p.grip)
	if float(p.get("power", 0.0)) > 0.0:
		c["power"] = float(p.power)
	if float(p.get("pace", 1.0)) != 1.0:
		c["pace"] = float(p.pace)
	return c


## The layout of the circuit: the one the environment built (so the car runs on the very asphalt that
## is drawn), or a fresh one with the same numbers when the sheet is played on another environment.
static func layout_of(ctx: ArchetypeContext) -> CircuitLayout:
	var p := ctx.params
	if ctx.env != null and ctx.env.has_method("circuit_layout"):
		return ctx.env.call("circuit_layout")
	return CircuitLayout.new(float(p.get("track_scale", 0.5)), float(p.get("sample_step", SAMPLE)))


func generate(ctx: ArchetypeContext) -> Dictionary:
	var p := ctx.params
	var layout := layout_of(ctx)
	var line := layout.racing_line(float(p.get("line_margin", 1.5)), float(p.get("line_swing", 1.0)))
	var speeds := RaceCarPhysics.solve_closed(line, car_of(p))
	# the lap is closed: the car crosses the start / finish line again at the end
	var pts := CircuitLayout.close_lap(line)
	var v := speeds.duplicate()
	v.append(speeds[0])
	# a fine profile: a braking zone is only a few tens of metres long, 200 samples would blur it
	var profile := PathUtil.profile_from_samples(v, PathUtil.cumulative(pts), 900)
	return {"points": pts, "profile": profile, "events": [], "zone": Rect2(),
			"lap_time": RaceCarPhysics.lap_time(line, speeds)}


# --- Runtime -----------------------------------------------------------------------------------

func configure_subject(s: ArchetypeSubject) -> void:
	super.configure_subject(s)
	var prof: PackedFloat32Array = s.plan.get("profile", PackedFloat32Array())
	var lo := 6.0
	for x in prof:
		lo = minf(lo, x)
	s.speed_variation = 0.0        # the profile is the truth: no random wandering
	s.min_speed = maxf(2.0, lo * 0.5)
	s.base_speed = 30.0


## The car squats under power and dives under braking, and its rear lights come on when it brakes.
func animate(s: ArchetypeSubject, delta: float) -> void:
	animate_wheels(s, delta)
	var prev := float(s.state.get("prev_speed", s.speed_now))
	var acc := (s.speed_now - prev) / maxf(delta, 0.0001)
	s.state["prev_speed"] = s.speed_now
	var smooth := lerpf(float(s.state.get("accel", 0.0)), acc, 1.0 - exp(-delta / 0.12))
	s.state["accel"] = smooth
	# 1 g of braking pitches the nose down by about 1.4 deg
	s.model.rotation.x = lerpf(s.model.rotation.x, clampf(-smooth * 0.0025, -0.045, 0.045),
			1.0 - exp(-delta / 0.1))
	var braking := clampf(-smooth / 6.0, 0.0, 1.0)
	for light in s.parts.get("brake_lights", []):
		var mat := (light as MeshInstance3D).material_override as StandardMaterial3D
		if mat != null:
			mat.emission_energy_multiplier = lerpf(0.25, 4.0, braking)

class_name ArchetypeCible
extends SubjectArchetype
## CIBLE: the subject of a movement drill ("Mouvements" menu). It does as little as possible, so
## that everything the operator sees in the frame comes from the drone figure and not from the
## subject: a runner going straight ahead at a chosen, constant speed, on open ground.
##
## The speed is the difficulty of a drill. At the first step the subject is standing still, and the
## path is then only a metre long - the run still ends because the subject creeps along it and
## reaches the end after `duration`. Two things follow from that:
##  - `floor_speed` is the chosen speed itself (the usual floor of 0.05 m/s would make the subject
##    walk away, and would make the drone planner expect it to);
##  - the terrain cannot be sized from the path (`zone` below), and the drone path cannot be
##    sampled from the path length either (`drone_path_samples`).

## Playing area around the subject, m: the drone figures are flown inside it, and the terrain and
## the props of EnvDrill are built over it whatever the length of the path.
const FIELD := 420.0
## Samples of the drone path. A drill lasts a minute and a half around a subject that may not move:
## the flight has to be sampled from the run, not from the (possibly very short) subject path. It
## is about ten per second of run - the density the planner is built for. Many more would be worse,
## not better: the planner walks its timeline at 50 Hz, and samples closer together than a few of
## those steps get times that no longer mean anything (and speeds and accelerations with them).
const SAMPLES := 800


func id() -> String:
	return "CIBLE"


func summary() -> String:
	return "Drill subject: goes straight ahead at a constant speed (or stands still) on open ground."


func defaults() -> Dictionary:
	var d := common_defaults()
	d.merge({
		"subject_size": 1.8,
		"speed_min": 0.01, "speed_max": 0.01, "speed_variability": 0.0,
		"turn_frequency": 0.0, "lateral_amplitude": 0.0,
		"duration": 90.0, "sample_step": 2.0,
		"cadence": 1.75, "cadence_coupling": 1.0,
		"lean_max_deg": 6.0, "lean_gain": 0.4,
		"bob": 0.05, "limb_swing": 0.8,
		"cornering_accel": 0.0,
		"drone_path_samples": float(SAMPLES),
		"anticipation": 0.0,
	}, true)
	return d


## The speed is the difficulty of the drill, so the subject travels at exactly the speed asked for -
## the usual floor would turn a standing subject into a walking one.
func floor_speed(p: Dictionary) -> float:
	return maxf(0.5 * float(p.speed_min), 0.005)


func generate(ctx: ArchetypeContext) -> Dictionary:
	var p := ctx.params
	# No floor worth speaking of: the length IS the duration times the speed, and at the first step
	# that is less than a metre. Rounding it up would make the standing drill run longer than asked.
	var length := maxf(path_length(p), 0.2)
	var step := minf(float(p.sample_step), length / 8.0)
	var n := int(length / step) + 1
	var pts := PackedVector3Array()
	for i in n:
		var z := i * step
		pts.append(Vector3(0.0, ctx.ground(0.0, z), z))
	# The ground is built over the whole path plus the same open field all around it, whatever the
	# speed: a standing subject has a path a metre long and still needs room for the figure.
	return finish_plan(pts, PackedFloat32Array(), [],
			Rect2(-0.5 * FIELD, -0.5 * FIELD, FIELD, length + FIELD))

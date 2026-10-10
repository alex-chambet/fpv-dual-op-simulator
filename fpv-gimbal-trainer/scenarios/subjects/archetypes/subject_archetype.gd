class_name SubjectArchetype
extends RefCounted
## Base class of the movement archetypes. An archetype turns a set of numeric parameters into
##  - a path (Curve3D points) and a speed profile  -> generate()
##  - the way the subject moves along it            -> compute_speed()
##  - the way the placeholder animates              -> on_ready() / animate()
## It knows nothing about any particular sport: sports are data (SubjectDefinition .tres).
## Archetype instances are stateless and shared; per-subject state lives in ArchetypeSubject.state.

## Documentation of every parameter (shown by docs/ajouter_un_sport.md and used by validation).
const PARAM_DOCS := {
	"subject_size": "Typical size of the subject of this archetype, m (largest dimension of the placeholder). Used when the sheet's subject_size is 0.",
	"speed_min": "Lowest nominal speed, m/s (the speed profile never goes below it, e.g. in tight turns).",
	"speed_max": "Highest nominal speed, m/s.",
	"speed_variability": "Time-varying speed oscillation, as a fraction (0..1+) of half the speed range.",
	"turn_frequency": "Direction changes per 100 m of path (how often the subject turns).",
	"lateral_amplitude": "Lateral swing of the path, m (half-width of the slalom / road leg / zone...).",
	"jump_frequency": "Jumps per 100 m of path (0 = no jumps).",
	"jump_height": "Height of a jump above the take-off / landing chord, m.",
	"jump_length": "Length of a jump, m of path.",
	"jump_visual": "What marks a take-off: 'ramp' (kicker), 'obstacle' (fence), 'none'.",
	"cadence": "Cycles per second of the cyclic motion (steps, strokes, gallop, pedalling). 0 = not cyclic.",
	"cadence_coupling": "0..1: how much the cadence follows the speed (0 = constant cadence).",
	"lean_max_deg": "Maximum lean (roll) into turns, degrees.",
	"lean_gain": "Lean strength relative to the physical bank angle.",
	"path_length": "Path length, m (fixed). 0 = computed so that the run lasts `duration`.",
	"duration": "Target run duration, s. The path length is fitted to it unless path_length is given (and for SAUT_ACROBATIQUE, whose length comes from its jumps).",
	"sample_step": "Spacing of the path control points, m.",
	"cornering_accel": "Lateral acceleration (m/s²) used to brake in turns. 0 = no braking in turns.",
	"drone_distance_scale": "Scales every drone distance (a paraglider needs a far drone, a climber a close one).",
	"drone_min_height": "Minimum drone height above the ground, m.",
	"drone_relative_height": "true: the drone height is relative to the subject (airborne subjects) instead of the ground.",
	# GLISSE_PENTE
	"weave_ratio": "Slow modulation of the slalom amplitude (0 = constant).",
	"weave_period": "Period of that modulation, m.",
	"gates": "Place slalom gates along the path (snow).",
	"leaves_tracks": "Leave tracks behind (snow).",
	"spray": "Throw spray / powder in hard turns.",
	# DESCENTE
	"tight_turns": "Share of tight turns (radius 34-52 m, often two in an S) among the turns (the others are wide sweeps).",
	"air_drag": "Air drag of the skier, 1/m (the higher, the lower the top speed on a given slope).",
	"snow_friction": "Friction coefficient of the skis on the snow.",
	# COURSE_SOL_CYCLIQUE
	"wiggle_ratio": "Amplitude of the short wiggles relative to lateral_amplitude.",
	"wiggle_period_ratio": "Period of the wiggles relative to the main turns.",
	"bob": "Vertical bounce of the body per cycle, m.",
	"limb_swing": "Swing of legs and arms, radians.",
	# VEHICULE_ROUTE
	"layout": "'switchback' (hairpins, uses turn_frequency x path_length for the number of legs) or 'winding'.",
	"turn_radius": "Radius of the hairpins, m (switchback layout).",
	# TOUT_TERRAIN_ERRATIQUE
	"irregularity": "0..1: how irregular the path and the speed are.",
	"bump": "Amplitude of the random bumps / pitch of the body, rad.",
	# EAU_SURFACE
	"wave_period": "Period of the wave bobbing, s.",
	"wave_roll_deg": "Roll oscillation on the waves, degrees.",
	"wave_heave": "Vertical bobbing on the waves, m.",
	"surge": "0..1: speed oscillation at the cadence (rowing, paddling).",
	"osc_amplitude": "Small lateral oscillation of the path, m.",
	"osc_period": "Period of that oscillation, m.",
	# AIR_LIBRE
	"altitude": "Mean altitude of the subject above the start ground, m.",
	"altitude_variation": "Altitude changes (+/-), m.",
	"altitude_period": "Path length of one altitude cycle, m.",
	"descent_per_100m": "Altitude lost per 100 m of path (glide / descent), m.",
	# STOP_AND_GO_ZONE
	"zone_width": "Width of the playing zone (x), m.",
	"zone_length": "Length of the playing zone (z), m.",
	"corner_radius": "Radius of the corners of the path, m.",
	"pause_probability": "Chance of a pause after each burst.",
	"burst_ratio": "Burst speed as a fraction of speed_max.",
	# SAUT_ACROBATIQUE
	"jump_count": "Number of jumps.",
	"approach_length": "Run-up before the first jump, m.",
	"rollout_length": "Distance between a landing and the next take-off / the end, m.",
	"flips": "Somersaults during a jump.",
	"spin_deg": "Spin during a jump, degrees.",
}


## Archetype id as used in SubjectDefinition.archetype.
func id() -> String:
	return ""


func summary() -> String:
	return ""


## Default value of every parameter of this archetype.
func defaults() -> Dictionary:
	return common_defaults()


static func common_defaults() -> Dictionary:
	return {
		"subject_size": 1.8,
		"speed_min": 4.0, "speed_max": 10.0, "speed_variability": 0.5,
		"turn_frequency": 1.5, "lateral_amplitude": 10.0,
		"jump_frequency": 0.0, "jump_height": 2.0, "jump_length": 14.0, "jump_visual": "ramp",
		"flips": 0, "spin_deg": 0.0,
		"cadence": 0.0, "cadence_coupling": 0.5,
		"lean_max_deg": 20.0, "lean_gain": 0.8,
		"path_length": 0.0, "duration": 55.0, "sample_step": 5.0,
		"cornering_accel": 0.0,
		"drone_distance_scale": 1.0, "drone_min_height": 3.0, "drone_relative_height": false,
	}


## Applies the session parameters to the archetype parameters. The level does not change the subject
## (speed_scale and turn_scale are 1): the difficulty comes from the drone flight (DroneDifficulty).
func scale_for_level(p: Dictionary, lp: Dictionary) -> Dictionary:
	var q := p.duplicate()
	q.speed_min = float(p.speed_min) * float(lp.speed_scale)
	q.speed_max = float(p.speed_max) * float(lp.speed_scale)
	q.turn_frequency = float(p.turn_frequency) * float(lp.turn_scale)
	return q


## False when compute_speed() is not the default (profile + slow oscillation): the speed cannot be predicted.
func uses_default_speed() -> bool:
	return true


## Amplitude (m/s) of the slow oscillation of the speed (see PathSubject.default_speed).
func speed_variation(p: Dictionary) -> float:
	return float(p.speed_variability) * (float(p.speed_max) - float(p.speed_min)) * 0.5


## Mean speed (m/s) of the subject, used by the drone planner to turn distances into times.
func expected_speed(plan: Dictionary, p: Dictionary) -> float:
	var prof: PackedFloat32Array = plan.profile
	if prof.size() >= 2:
		var sum := 0.0
		for v in prof:
			sum += v
		return sum / prof.size()
	return (float(p.speed_min) + float(p.speed_max)) * 0.5


# --- Path ----------------------------------------------------------------------------------

## Builds the path. Returns {points, profile (speed by arc ratio, may be empty), events, zone}.
func generate(_ctx: ArchetypeContext) -> Dictionary:
	return finish_plan(PackedVector3Array(), PackedFloat32Array(), [])


## Path length from the parameters: path_length, or a first guess of duration x mean speed (the
## ScenarioRunner then refines it so that the run really lasts `duration`, see fits_duration()).
func path_length(p: Dictionary) -> float:
	var l := float(p.path_length)
	if l > 0.0:
		return l
	return float(p.duration) * (float(p.speed_min) + float(p.speed_max)) * 0.5


## Whether a sheet that gives a `duration` (and no path_length) gets its path length corrected so the
## run really lasts that long. False when the path length is not a free parameter (jump sequences,
## zone tours).
func fits_duration() -> bool:
	return true


## Nominal travel time of a plan (s): path length divided by the planned speed along it.
func nominal_time(plan: Dictionary, p: Dictionary) -> float:
	var total := PathUtil.total_length(plan.points)
	if total <= 0.0:
		return 0.0
	var vmin := float(p.speed_min)
	var vmean := (vmin + float(p.speed_max)) * 0.5
	var floor_v := maxf(0.05, 0.3 * vmin)
	var profile: PackedFloat32Array = plan.profile
	var n := 200
	var t := 0.0
	for i in n:
		var v := vmean
		if profile.size() >= 2:
			var f := (i + 0.5) / n * (profile.size() - 1)
			var k := mini(int(f), profile.size() - 2)
			v = lerpf(profile[k], profile[k + 1], f - k)
		t += total / n / maxf(v, floor_v)
	return t


## x of the path as a function of z (paths that advance along +Z), used by environment-specific
## legacy scripts. Default: interpolation of the generated points.
func lateral_fn(_p: Dictionary, pts: PackedVector3Array) -> Callable:
	return func(z: float) -> float: return PathUtil.x_at_z(pts, z)


func finish_plan(pts: PackedVector3Array, speeds: PackedFloat32Array, events: Array,
		zone := Rect2()) -> Dictionary:
	var profile := PackedFloat32Array()
	if pts.size() >= 2 and speeds.size() == pts.size():
		profile = PathUtil.profile_from_samples(speeds, PathUtil.cumulative(pts))
	return {"points": pts, "profile": profile, "events": events, "zone": zone}


## Adds `jump_frequency` jumps per 100 m to a dense ground path (y = ground) and returns their events.
func inject_jumps(pts: PackedVector3Array, ctx: ArchetypeContext, step: float) -> Array:
	var p := ctx.params
	var events: Array = []
	var total := PathUtil.total_length(pts)
	var count := roundi(float(p.jump_frequency) * total / 100.0)
	if count <= 0 or step <= 0.0:
		return events
	var len_n := maxi(3, int(float(p.jump_length) / step))
	var ramp_n := maxi(2, int(4.0 / step))
	var ramp_h := minf(0.45 * float(p.jump_height) + 0.2, 1.4)
	var starts := PathUtil.pick_jump_indices(pts.size(), count, len_n, int(8.0 / step) + ramp_n,
			int(14.0 / step) + ramp_n, ctx.rng)
	for i0 in starts:
		events.append(PathUtil.apply_jump(pts, ctx.ground_fn(), i0, i0 + len_n, float(p.jump_height),
				ramp_n, ramp_h))
	return events


# --- Runtime ----------------------------------------------------------------------------------

## Whether the placeholder is snapped on the ground (false for airborne subjects).
func uses_ground() -> bool:
	return true


## Pitch the model with the slope of the path (vehicles, gliders) instead of staying upright.
func follows_slope() -> bool:
	return false


## Copies the speed / lean parameters into the subject.
func configure_subject(s: ArchetypeSubject) -> void:
	var p := s.params
	var vmin := float(p.speed_min)
	var vmax := float(p.speed_max)
	s.base_speed = (vmin + vmax) * 0.5
	s.speed_variation = float(p.speed_variability) * (vmax - vmin) * 0.5
	s.min_speed = maxf(0.05, 0.3 * vmin)
	s.max_lean_deg = float(p.lean_max_deg)
	s.lean_gain = float(p.lean_gain)
	s.follow_slope = follows_slope()
	s.speed_profile = s.plan.profile


func compute_speed(s: ArchetypeSubject, _delta: float) -> float:
	return s.default_speed()


## Called once the subject's nodes exist (add effects here).
func on_ready(_s: ArchetypeSubject) -> void:
	pass


## Called after every advance().
func animate(s: ArchetypeSubject, delta: float) -> void:
	animate_jump(s, delta)
	animate_wheels(s, delta)
	if s.parts.has("athlete"):
		s.parts["athlete"].update(s, delta)  # the rigged athlete animates itself (no swinging limbs, no bob)
	else:
		animate_cycle(s, delta)


## Wheels spin with the speed.
func animate_wheels(s: ArchetypeSubject, delta: float) -> void:
	var wheels: Array = s.parts["wheels"]
	if wheels.is_empty():
		return
	var radius := float(s.parts["wheel_radius"]) * s.model.scale.x  # the model is scaled to subject_size
	var spin := float(s.state.get("spin", 0.0)) + s.speed_now * delta / maxf(radius, 0.02)
	s.state["spin"] = spin
	for w in wheels:
		w.rotation = Vector3(spin, 0.0, PI * 0.5)


## Cyclic motion at `cadence` Hz: legs and arms swing, horse legs gallop, the body bobs, the
## paddle sweeps. The cadence follows the speed by `cadence_coupling`.
func animate_cycle(s: ArchetypeSubject, delta: float) -> void:
	var cadence := float(s.params.cadence)
	if cadence <= 0.0:
		return
	var k := lerpf(1.0, s.speed_now / maxf(s.base_speed, 0.1), float(s.params.cadence_coupling))
	var phase := float(s.state.get("cycle_phase", 0.0)) + TAU * cadence * k * delta
	s.state["cycle_phase"] = phase
	var swing := sin(phase)
	var amp := float(s.params.get("limb_swing", 0.8))
	var parts := s.parts
	var legs: Array = parts["legs"]
	if legs.size() == 2 and not parts.get("seated", false):
		legs[0].rotation.x = swing * amp
		legs[1].rotation.x = -swing * amp
	var arms: Array = parts["arms"]
	if arms.size() == 2:
		arms[0].rotation.x = -swing * amp * 0.85
		arms[1].rotation.x = swing * amp * 0.85
	var hl: Array = parts["horse_legs"]
	if hl.size() == 4:
		hl[0].rotation.x = swing * 0.8
		hl[1].rotation.x = sin(phase + 0.5) * 0.8
		hl[2].rotation.x = -swing * 0.8
		hl[3].rotation.x = -sin(phase + 0.5) * 0.8
	parts["body"].position.y = absf(swing) * float(s.params.get("bob", 0.0))
	if parts.has("paddle"):
		parts["paddle"].rotation.z = swing * 0.45


## Somersault / spin / pitch of the model during a jump event.
func animate_jump(s: ArchetypeSubject, _delta: float) -> void:
	var ev := s.current_jump()
	if ev.is_empty():
		s.model.rotation.x = lerpf(s.model.rotation.x, 0.0, 0.5)
		s.model.rotation.y = 0.0
		return
	var u := clampf((s.progress_ratio - float(ev.r0)) / maxf(float(ev.r1) - float(ev.r0), 0.0001), 0.0, 1.0)
	var flips := roundi(float(s.params.get("flips", 0.0)))
	if flips != 0:
		s.model.rotation.x = -TAU * flips * smoothstep(0.0, 1.0, u)
	else:
		s.model.rotation.x = -0.25 * sin(PI * u)
	s.model.rotation.y = deg_to_rad(float(s.params.get("spin_deg", 0.0))) * smoothstep(0.0, 1.0, u)

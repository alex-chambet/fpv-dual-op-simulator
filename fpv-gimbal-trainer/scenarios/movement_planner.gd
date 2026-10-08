class_name MovementPlanner
extends RefCounted
## Plans the drone flight around a subject path for a drone movement and a difficulty level.
## The result has one drone point per subject point: point i is where the drone is when its progress along
## the path reaches the i-th point of the subject path. ScenarioBase moves the drone along its path with a
## low-passed copy of the subject's speed (DroneDifficulty.FOLLOW_TAU) and this planner simulates exactly
## that, so the drone is where the plan says it is, whatever the subject does in between.
##
## The flight is smooth by construction, whatever the level:
##  - it is designed in time (seconds of subject travel) with slow sinusoids and quintic blends,
##    around a low-passed copy of the subject path (the drone does not copy the subject's wobbles);
##  - the offsets are applied in a slowly turning frame, so sharp turns of the subject do not make
##    the camera rotate abruptly;
##  - the whole trajectory is low-passed, kept above the ground with a smooth envelope, and checked:
##    if the acceleration of the drone or the speed of the subject in the image exceeds the limits of
##    the level, the drone is moved away / the path is smoothed more.
## Difficulty only comes from DroneDifficulty: the movement, the axes (pan / tilt) and the distance.
##
## plan(movement, subject_points, ctx) -> {"drone": PackedVector3Array, "barriers": Array[Dictionary],
##                                          "stats": Dictionary}
## ctx: level, ground (Callable(x, z) -> height, may be invalid), occlusion (0..1), side (+1/-1), seed,
##      speed_hint (m/s), profile (subject speed by arc ratio, optional), min_height (m),
##      distance_scale (every distance is multiplied by it: a paraglider needs a far drone, a climber a
##      close one), subject_size (m), speed_variation / min_speed (the slow oscillation of the subject's
##      speed, see PathSubject.default_speed), tau (follow time constant, chosen by plan()),
##      min_distance (condition() only: closest the drone may get to the subject, m)

const FINAL_SIGMA := 0.7       # s, low-pass of the final drone trajectory
const HEADING_SIGMA := 3.5     # s, low-pass of the heading of the offset frame
const ENVELOPE_WINDOW := 5.0  # s: the drone clears the highest ground within this time (4 sigma)...
const ENVELOPE_SIGMA := 1.25   # s: ...and its height follows the smoothed envelope
const AIM_HEIGHT := 1.0        # m, height of the point of the subject that is framed
const BASE_ELEVATION := 0.26   # rad (15 deg): the drone is a little above the subject
const MAX_AZIMUTH := 1.22      # rad
const REF_DISTANCE := {"pursuit": 15.0, "frontal": 15.0, "lateral": 14.0, "orbit": 14.0, "reveal": 15.0,
		"flyby": 16.0}
const CENTER_SIGMA := {"pursuit": 1.8, "frontal": 1.8, "lateral": 1.4, "orbit": 1.4, "reveal": 1.4,
		"flyby": 1.4}
const SWAY_FACTOR := {"pursuit": 0.8, "frontal": 1.0, "lateral": 1.15, "orbit": 1.0, "reveal": 0.8,
		"flyby": 0.8}
## Where the obstacles of a reveal stand on the line of sight (fraction of the way from the subject to the
## drone): the usual one first, the others when the drone / subject would meet the obstacle at another time.
const HIDE_FRACTIONS := [0.46, 0.38, 0.55, 0.64]
const EVENT_ANGLE := 1.0       # rad: widest angle, seen from the subject, of the drone ahead of / behind it in an event
const EVENT_ACCEL := 0.8       # share of the level's acceleration limit that the blends of an event may use
const ORBIT_ACCEL := 0.6       # same for the centripetal acceleration of an orbit (the rest is for the path)
const EVENT_LEAD := 2.8        # s, shortest lead-in / tail of an event
const EVENT_FADE := 3.0        # s, the sway of the drone fades out before an event and back in after it
const EVENT_GAP := 4.0         # s, free time wanted between two events
const QUINTIC_PEAK := 5.77     # peak acceleration of a quintic blend = 5.77 x distance / duration^2
## Movements that are inherently fast in the image get a larger pan / tilt limit.
const PAN_CAP_FACTOR := {"pursuit": 1.0, "frontal": 1.1, "lateral": 1.2, "reveal": 1.5, "orbit": 1.25, "flyby": 1.7,
		"approach_orbit": 1.3, "dive": 1.3, "choreo": 1.35}
const TILT_CAP_FACTOR := {"pursuit": 1.0, "frontal": 1.0, "lateral": 1.0, "reveal": 1.2, "orbit": 1.2, "flyby": 1.5,
		"approach_orbit": 1.3, "dive": 1.6, "choreo": 1.5}
## Figures (expert movements, see _build_figures)
const FIGURE_SIGMA := 0.8      # s, low-pass of the azimuth / distance / height of the drone around the subject
const FIGURE_SPEED_CAP := 40.0 # m/s (144 km/h), 99th percentile of the drone speed in a figure flight
const FIGURE_LEAD := 2.5       # s alongside the subject before the first figure
const FIGURE_HIDDEN_CAP := 0.04  # share of the run the ground may stand between the drone and the subject


static func plan(movement: String, S: PackedVector3Array, ctx: Dictionary) -> Dictionary:
	# The drone follows the subject through a low-pass of its speed. A smaller time constant lets it brake
	# with the subject in the bends (less centripetal acceleration): used when the limits cannot be met.
	var best := {}
	var best_score := INF
	for tau in DroneDifficulty.FOLLOW_TAU_CANDIDATES:
		var c := ctx.duplicate()
		c["tau"] = tau
		var r := _plan_with(movement, S, c)
		if float(r.stats.score) < best_score:
			best_score = float(r.stats.score)
			best = r
			best.stats["tau"] = tau
		if best_score <= 1.3:
			break
	return best


static func _plan_with(movement: String, S: PackedVector3Array, ctx: Dictionary) -> Dictionary:
	var g := _prepare(movement, S, ctx)
	var lp: Dictionary = g.lp
	var k_dist := 1.0     # distance multiplier (moves the drone away)
	var sig_mul := 1.0    # smoothing multiplier
	var time_mul := 1.0   # slows the orbit / the sweeps
	var sway_k := 1.0     # softens the sway (last resort: a tortuous path leaves little room for it)
	var figures := movement in DroneDifficulty.EXPERT_MOVEMENTS
	var fast := movement == "orbit" or movement == "reveal" or movement == "flyby" or figures
	var cap_pan := float(lp.pan_cap) * float(PAN_CAP_FACTOR[movement])
	var cap_tilt := float(lp.tilt_cap) * float(TILT_CAP_FACTOR[movement])
	var best := {}
	var best_score := INF
	var last_score := INF
	for _attempt in 8:
		var res := _build(g, k_dist, sig_mul, time_mul, sway_k)
		var stats := _measure(res.drone, g.S, g.tt)
		var over_pan: float = stats.pan95 / cap_pan
		var over_tilt: float = stats.tilt95 / cap_tilt
		var over_acc: float = stats.acc99 / (1.15 * float(lp.accel_cap))
		# A figure flight also keeps a believable top speed (the far legs are flown fast), and its far legs
		# must not put a hill between the drone and the subject (they are brought closer if they do).
		var over_spd: float = float(stats.spd99) / FIGURE_SPEED_CAP if figures else 0.0
		var blocked := _terrain_blocked(res.drone, g) if figures else 0.0
		var over_los := blocked / FIGURE_HIDDEN_CAP if figures else 0.0
		var score := maxf(maxf(maxf(over_pan, over_spd), over_los), maxf(over_tilt, over_acc))
		if score < best_score:  # keep the best flight of the attempts
			best_score = score
			stats["los_blocked"] = blocked
			stats["far_k"] = float(g.get("far_k", 1.0))
			stats["k_dist"] = k_dist
			stats["sig_mul"] = sig_mul
			stats["time_mul"] = time_mul
			stats["sway_k"] = sway_k
			stats["score"] = score
			stats["events"] = res.events.map(func(e): return [snappedf(float(e.t0), 0.1), snappedf(float(e.dur), 0.1)])
			best = {"drone": res.drone, "events": res.events, "heads": res.heads, "stats": stats}
		if score <= 1.0 or (_attempt >= 3 and score > 0.97 * last_score):
			break
		last_score = score
		if over_acc > 1.0:
			# Smooth the path more; slow the movement down only when the smoothing is used up (the level asks
			# for a given speed of orbit / sweep, which the planner should change as little as it can).
			if sig_mul < 2.49:
				sig_mul = minf(sig_mul * clampf(pow(over_acc, 0.6), 1.12, 1.5), 2.5)
			elif fast:
				time_mul = minf(time_mul * clampf(pow(over_acc, 0.5), 1.1, 1.4), 2.2)
			if _attempt >= 1 and over_acc > 1.03:
				sway_k = maxf(sway_k * clampf(pow(over_acc, -0.6), 0.8, 0.95), 0.55)
		if over_pan > 1.0 or over_tilt > 1.0:
			var over := maxf(over_pan, over_tilt)
			k_dist = minf(k_dist * clampf(pow(over, 0.85), 1.06, 1.4), 2.0)
			if fast:
				time_mul = minf(time_mul * clampf(pow(over, 0.5), 1.05, 1.3), 2.2)
		if over_spd > 1.0:
			time_mul = minf(time_mul * clampf(over_spd, 1.05, 1.4), 2.2)
		if over_los > 1.0:
			g["far_k"] = maxf(float(g.get("far_k", 1.0)) * 0.78, 0.45)
	best["barriers"] = _barriers(g, best.drone, best.events, best.heads)
	return best


## Smooths a drone path that was modified after planning (tunnels...): same low-pass and ground
## clearance as the planner. ctx: same as plan().
static func condition(D: PackedVector3Array, S: PackedVector3Array, ctx: Dictionary) -> PackedVector3Array:
	var g := _prepare("lateral", S, ctx)
	var out := _smooth(D, g.tt, 1.0)
	out = _keep_away(out, S, g.tt, float(ctx.get("min_distance", 2.0 * float(g.size) + 2.0)), _headings(S), 0.7)
	return _clear_ground(out, g.tt, g.ground, float(g.min_h))


# --- Preparation ------------------------------------------------------------------------------

static func _prepare(movement: String, S: PackedVector3Array, ctx: Dictionary) -> Dictionary:
	var n := S.size()
	var cum := PathUtil.cumulative(S)
	var total: float = cum[n - 1]
	var v_hint := maxf(float(ctx.get("speed_hint", 8.0)), 0.3)
	# Timeline of the drone (it does not copy the speed changes of the subject) and place of the
	# subject at each point of the drone path.
	var tl := _timeline(cum, total, ctx.get("profile", PackedFloat32Array()), v_hint,
			float(ctx.get("speed_variation", 0.0)), float(ctx.get("min_speed", 0.15)),
			float(ctx.get("tau", DroneDifficulty.FOLLOW_TAU)))
	var tt: PackedFloat32Array = tl.tt
	var Sx := PackedVector3Array()
	Sx.resize(n)
	for i in n:
		Sx[i] = PathUtil.polyline_at(S, cum, clampf(cum[i] + float(tl.e[i]), 0.0, total))
	var size := maxf(float(ctx.get("subject_size", 1.8)), 0.3)
	var ds := maxf(float(ctx.get("distance_scale", 1.0)), 0.05)
	return {
		"movement": movement, "S": Sx, "n": n, "cum": cum, "total": total, "tt": tt, "T": tt[n - 1],
		"v": v_hint, "size": size, "ds": ds,
		"ground": ctx.get("ground", Callable()), "min_h": float(ctx.get("min_height", 3.0)),
		"side": float(ctx.get("side", 1.0)), "seed": int(ctx.get("seed", 1)),
		"occlusion": float(ctx.get("occlusion", 0.5)),
		"lp": DroneDifficulty.params(float(ctx.get("level", 3.0))),
		"curv": PathUtil.curvature(Sx),
		"cache": {},
	}


## Nominal speed of the subject (m/s) at arc length s: profile by arc ratio, or a constant.
static func _nominal_speed(profile: PackedFloat32Array, s: float, total: float, v_hint: float) -> float:
	if profile.size() >= 2 and total > 0.0:
		var f := clampf(s / total, 0.0, 1.0) * (profile.size() - 1)
		var k := mini(int(f), profile.size() - 2)
		return maxf(lerpf(profile[k], profile[k + 1], f - k), 0.15)
	return v_hint


## Simulates the drone following the subject at its nominal speed (the same filter as
## ScenarioBase._follow): returns the time `tt` at which the drone reaches each point of the path and
## `e`, how far ahead of that point the subject is at that moment (m).
static func _timeline(cum: PackedFloat32Array, total: float, profile: PackedFloat32Array,
		v_hint: float, variation: float, min_speed: float, tau: float) -> Dictionary:
	var n := cum.size()
	var tt := PackedFloat32Array()
	var e := PackedFloat32Array()
	tt.resize(n)
	e.resize(n)
	var dt := 0.02
	var k_v := 1.0 - exp(-dt / tau)
	var k_c := 1.0 - exp(-dt / DroneDifficulty.FOLLOW_PULL)
	var s := 0.0
	var sig := 0.0
	var vf := _nominal_speed(profile, 0.0, total, v_hint)
	var t := 0.0
	var i := 1
	var guard := 0
	while i < n and guard < 600000:
		guard += 1
		var s_prev := s
		var vn := 0.0
		if s < total:  # same law as PathSubject.default_speed()
			vn = maxf(min_speed, _nominal_speed(profile, s, total, v_hint) + variation * (0.7 * sin(0.45 * t) + 0.3 * sin(1.1 * t + 1.0)))
		s = minf(s + vn * dt, total)
		vf += (vn - vf) * k_v
		var sig_new := sig + vf * dt
		sig_new += (s - sig_new) * k_c
		t += dt
		while i < n and sig_new >= cum[i] - (0.05 if i == n - 1 else 0.0):
			var f := clampf((cum[i] - sig) / maxf(sig_new - sig, 0.000001), 0.0, 1.0)
			tt[i] = t - dt + dt * f
			e[i] = lerpf(s_prev, s, f) - cum[i]
			i += 1
		sig = sig_new
	while i < n:  # the drone never got there (the subject stopped): extrapolate
		tt[i] = tt[i - 1] + 0.05
		e[i] = 0.0
		i += 1
	tt[0] = 0.0
	e[0] = 0.0
	# strictly increasing times
	for j in range(1, n):
		if tt[j] <= tt[j - 1]:
			tt[j] = tt[j - 1] + 0.0005
	return {"tt": tt, "e": e}

# --- One flight -------------------------------------------------------------------------------

static func _build(g: Dictionary, k_dist: float, sig_mul: float, time_mul: float, sway_k := 1.0) -> Dictionary:
	if g.movement in DroneDifficulty.EXPERT_MOVEMENTS:
		return _build_figures(g, k_dist, sig_mul, time_mul)
	var movement: String = g.movement
	var S: PackedVector3Array = g.S
	var tt: PackedFloat32Array = g.tt
	var n: int = g.n
	var lp: Dictionary = g.lp
	var ds: float = g.ds
	var side: float = g.side
	var rng := RandomNumberGenerator.new()
	rng.seed = int(g.seed)
	var phi_az := rng.randf() * TAU
	var phi_el := rng.randf() * TAU
	var single_tilt := rng.randf() < 0.5
	var both: bool = lp.both_axes
	var pan_on := true
	var tilt_on := true
	if not both:
		if movement == "pursuit" or movement == "frontal" or movement == "lateral":
			pan_on = not single_tilt   # one axis only: pan or tilt
			tilt_on = single_tilt
		else:
			tilt_on = false            # orbit / reveal / flyby already ask for a lot of pan
	var sway := float(SWAY_FACTOR[movement])
	var a_az := float(lp.pan_amp) * sway * sway_k if pan_on else 0.0
	var a_el := float(lp.tilt_amp) * sway_k if tilt_on else 0.0
	var t_az := float(lp.pan_period)
	var t_el := float(lp.tilt_period)

	# Distances (m)
	var sf := clampf(pow(float(g.v) / 8.0, 0.3), 0.85, 1.4)
	var d_floor: float = 1.4 * float(g.size) + 0.8
	var d0 := maxf(float(REF_DISTANCE[movement]) * float(lp.proximity) * ds * sf * k_dist, 1.6 * d_floor)
	var d_min := maxf(7.0 * float(lp.proximity) * ds * sf, d_floor)

	# Low-passed copy of the subject path (cached per smoothing)
	var key := snappedf(sig_mul, 0.001)
	var cache: Dictionary = g.cache
	if not cache.has(key):
		var c0 := _smooth(S, tt, float(CENTER_SIGMA[movement]) * sig_mul)
		cache[key] = [c0, _swing(S, c0)]
	var C: PackedVector3Array = cache[key][0]
	# The subject swings around the smoothed path: keep clear of it when it can swing towards the drone.
	var swing: float = cache[key][1]
	if movement == "orbit" or movement == "lateral" or movement == "reveal":
		d0 = maxf(d0, 1.25 * swing + 1.4 * d_floor)
	if movement == "flyby":
		d0 = maxf(d0, 1.25 * swing + 2.2 * d_floor)
		d_min = maxf(d_min, 1.1 * swing + 1.4 * d_floor)
	# The offsets are applied in a slowly turning frame; the farther the drone, the slower the frame turns
	# (a far drone swinging round at the end of a long arm would need a lot of acceleration).
	var h_sigma := HEADING_SIGMA * sig_mul * clampf(d0 / 18.0, 1.0, 4.0)
	var hkey := "h%.3f" % snappedf(h_sigma, 0.05)
	if not cache.has(hkey):
		cache[hkey] = _headings(_smooth(S, tt, h_sigma))
	var heads: PackedVector3Array = cache[hkey]
	var events := _events(g, lp, time_mul, d0) if (movement == "reveal" or movement == "flyby") else []
	# An orbit never turns faster than its centripetal acceleration allows: a wide orbit takes longer.
	var orbit_period := maxf(float(lp.orbit_period) * time_mul,
			TAU * sqrt(1.05 * d0 / (ORBIT_ACCEL * float(lp.accel_cap))))

	var theta0 := 0.0
	if movement == "orbit":
		theta0 = atan2(heads[0].z, heads[0].x) + PI + rng.randf_range(-0.4, 0.4)
	var D := PackedVector3Array()
	D.resize(n)
	for i in n:
		var t := tt[i]
		var head: Vector3 = heads[i]
		var right := head.cross(Vector3.UP)
		var w_ev := 0.0
		var ahead_ev := 0.0
		var dl_ev := 0.0
		for e in events:
			var te: float = t - float(e.t0)
			if te >= -EVENT_FADE and te <= float(e.dur) + EVENT_FADE:
				var w := _sstep(-EVENT_FADE, 0.0, te) * (1.0 - _sstep(float(e.dur), float(e.dur) + EVENT_FADE, te))
				w_ev = maxf(w_ev, w)
				ahead_ev += _track(e.ahead, te)
				if e.kind == "flyby":
					var u := clampf((te - float(e.pass0)) / float(e.pass_t), 0.0, 1.0)
					dl_ev -= (d0 - d_min) * sin(PI * u) * sin(PI * u)
		var az := clampf(a_az * sin(TAU * t / t_az + phi_az) * (1.0 - w_ev), -MAX_AZIMUTH, MAX_AZIMUTH)
		var el := BASE_ELEVATION + a_el * sin(TAU * t / t_el + phi_el)
		var xz: Vector3
		var dh := d0
		match movement:
			"pursuit":
				xz = right * (d0 * tan(az)) - head * d0
			"frontal":
				xz = right * (d0 * tan(az)) + head * d0
			"orbit":
				var th := theta0 + side * TAU * t / orbit_period
				var r := d0 * (1.0 + 0.05 * sin(TAU * t / 17.0 + phi_az))
				xz = Vector3(cos(th), 0.0, sin(th)) * r
				dh = r
			_:  # lateral, reveal, flyby: alongside, drifting ahead / behind
				var l := maxf(d0 + dl_ev, d_floor)
				var ahead := l * tan(az) + ahead_ev
				xz = right * (side * l) + head * ahead
				dh = sqrt(l * l + ahead * ahead)
		var base: Vector3 = C[i]
		D[i] = Vector3(base.x + xz.x, base.y + dh * tan(el), base.z + xz.z)
	return _finish(g, D, sig_mul, d_floor, events, heads)


## Smooth, above the ground, away from the subject.
static func _finish(g: Dictionary, D_raw: PackedVector3Array, sig_mul: float, d_floor: float,
		events: Array, heads: PackedVector3Array) -> Dictionary:
	var S: PackedVector3Array = g.S
	var tt: PackedFloat32Array = g.tt
	var sig := FINAL_SIGMA * (1.0 + 0.3 * (sig_mul - 1.0))
	var D := _smooth(D_raw, tt, sig)
	D = _keep_away(D, S, tt, d_floor, heads, 0.5 * sig)
	return {"drone": _clear_ground(D, tt, g.ground, float(g.min_h)), "events": events, "heads": heads}


# --- Figures (expert movements) ----------------------------------------------------------------

## Flight of an expert movement (DroneDifficulty.EXPERT_MOVEMENTS): a chain of figures flown around the
## subject, written in a frame that follows it - azimuth (0 = alongside on `side`, +PI/2 = ahead,
## -PI/2 = behind), horizontal distance, height above the subject. A figure is a list of keys joined by
## straight legs flown at the figure speed of the level; the three channels are then low-passed in time, so
## the drone never changes direction or speed abruptly (the planner still checks its acceleration, its top
## speed and the pan / tilt speed it asks for):
##  - "approach": the drone pulls away far and high (the subject gets tiny in the frame), rushes back in and
##    wraps into a fast orbit of one turn or more, with its height rising and falling;
##  - "dive": it climbs high ahead of the subject, dives onto it, skims past it low and climbs out behind;
##  - "cross": it waits far ahead, rushes head-on at the subject, crosses it close and flies away behind;
##  - "spiral": it orbits the subject while climbing away from it, then comes back down close.
## approach_orbit chains approaches, dive chains dives, choreo mixes the four (never twice the same in a row).
static func _build_figures(g: Dictionary, k_dist: float, sig_mul: float, time_mul: float) -> Dictionary:
	var S: PackedVector3Array = g.S
	var tt: PackedFloat32Array = g.tt
	var n: int = g.n
	var lp: Dictionary = g.lp
	var T: float = g.T
	var side: float = g.side
	var rng := RandomNumberGenerator.new()
	rng.seed = int(g.seed)
	var size: float = g.size
	var sf := clampf(pow(float(g.v) / 8.0, 0.3), 0.85, 1.4)
	var u := float(g.ds) * sf  # distance unit of the sport
	var d_floor := 1.4 * size + 0.8

	# Close to the subject the drone flies around its real path (a low-passed copy would cut the bends and
	# leave the drone far from the subject there); far away it flies around a smoother copy, in a frame that
	# turns slowly (a far drone swinging round with every bend would need a lot of acceleration).
	var ckey := "f%.3f" % snappedf(sig_mul, 0.001)
	var cache: Dictionary = g.cache
	if not cache.has(ckey):
		var c_near := _smooth(S, tt, 0.6 * sig_mul)
		cache[ckey] = [c_near, _swing(S, c_near), _smooth(S, tt, 2.0 * sig_mul)]
	var C_near: PackedVector3Array = cache[ckey][0]
	var swing: float = cache[ckey][1]
	var C_far: PackedVector3Array = cache[ckey][2]

	# Distances (m), speed of the legs (m/s, relative to the subject), time scale of the figures
	var r_close := maxf(12.0 * float(lp.proximity) * u * k_dist, maxf(1.6 * d_floor, 1.25 * swing + 1.4 * d_floor))
	var r_far := maxf(clampf(36.0 * u, 24.0, 50.0 * maxf(u, 0.6)) * float(g.get("far_k", 1.0)), 3.0 * r_close)
	var r_orbit := 1.1 * r_close
	g["far_from"] = 2.5 * r_close
	var f := {
		"r_close": r_close, "r_far": r_far, "r_orbit": r_orbit,
		"h_close": r_close * tan(BASE_ELEVATION), "h_low": 1.0 + 0.9 * size, "h_far": 0.4 * r_far,
		"r_top": 0.32 * r_far, "h_top": 0.62 * r_far,
		"v": float(lp.figure_speed) * clampf(u, 0.7, 1.6) / time_mul,
		"tempo": float(lp.figure_tempo) * time_mul,
		# an orbit never turns faster than its centripetal acceleration allows
		"period": maxf(float(lp.orbit_period) * time_mul,
				TAU * sqrt(1.05 * r_orbit / (ORBIT_ACCEL * float(lp.accel_cap)))),
		"rot": -1.0 if rng.randf() < 0.5 else 1.0,
		"b": 0.0,
	}
	var kinds: Array
	match str(g.movement):
		"approach_orbit": kinds = ["approach", "spiral"]
		"dive": kinds = ["dive", "cross"]
		_: kinds = ["approach", "dive", "cross", "spiral"]

	# Alongside the subject, then figures as long as they fit in the run, then back alongside.
	var keys: Array = [[0.0, 0.0, 1.5 * r_close, float(f.h_close)]]
	_hold(keys, FIGURE_LEAD)
	var events := []
	var last := ""
	while true:
		# the movement's own figure, or the shorter one when it no longer fits (choreo: a random one, never
		# the same twice in a row, an approach first)
		var order: Array = kinds.duplicate()
		if kinds.size() > 2:
			order.clear()
			for kd in kinds:
				if kd != last:
					order.insert(rng.randi_range(0, order.size()), kd)
			if last == "":
				order.erase("approach")
				order.push_front("approach")
		var placed := false
		for kind in order:
			var trial := keys.duplicate(true)
			var state := f.duplicate()
			var t0 := float(keys[keys.size() - 1][0])
			_figure(str(kind), trial, state, rng)
			if float(trial[trial.size() - 1][0]) <= T - 2.0:
				keys = trial
				f = state
				events.append({"kind": str(kind), "t0": t0, "dur": float(keys[keys.size() - 1][0]) - t0})
				last = str(kind)
				placed = true
				break
		if not placed:
			break
	var a_last := float(keys[keys.size() - 1][1])
	var a_end := _wrap_near(0.0, a_last)
	if absf(_wrap_near(PI, a_last) - a_last) < absf(a_end - a_last):
		a_end = _wrap_near(PI, a_last)
	_leg(keys, a_end, 1.5 * r_close, float(f.h_close), float(f.v), 2.5 * float(f.tempo))
	_hold(keys, maxf(T - float(keys[keys.size() - 1][0]), 0.0) + 2.0)

	# Channels at the drone's times, low-passed, then placed around the subject.
	var P := PackedVector3Array()
	P.resize(n)
	var k := 1
	for i in n:
		while k < keys.size() - 1 and float(keys[k][0]) < tt[i]:
			k += 1
		var a: Array = keys[k - 1]
		var b: Array = keys[k]
		var w := clampf((tt[i] - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.0001), 0.0, 1.0)
		P[i] = Vector3(lerpf(a[1], b[1], w), lerpf(a[2], b[2], w), lerpf(a[3], b[3], w))
	P = _smooth(P, tt, FIGURE_SIGMA * sig_mul)
	var heads_near := _cached_headings(g, S, tt, HEADING_SIGMA * sig_mul)
	var heads_far := _cached_headings(g, S, tt, HEADING_SIGMA * sig_mul * clampf(r_far / 18.0, 1.0, 3.0))
	var heads := PackedVector3Array()
	heads.resize(n)
	var D := PackedVector3Array()
	D.resize(n)
	for i in n:
		var p := P[i]
		var w := _sstep(r_close, r_far, p.y)  # 0 close to the subject, 1 far away
		var head := heads_near[i].lerp(heads_far[i], w)
		head = head.normalized() if head.length() > 0.01 else heads_far[i]
		heads[i] = head
		var right := head.cross(Vector3.UP)
		D[i] = C_near[i].lerp(C_far[i], w) + (right * (side * cos(p.x)) + head * sin(p.x)) * p.y + Vector3(0.0, p.z, 0.0)
	return _finish(g, D, sig_mul, d_floor, events, heads)


## Headings of the path low-passed with `sigma` (s), cached in the planning context.
static func _cached_headings(g: Dictionary, S: PackedVector3Array, tt: PackedFloat32Array, sigma: float) -> PackedVector3Array:
	var cache: Dictionary = g.cache
	var key := "h%.3f" % snappedf(sigma, 0.05)
	if not cache.has(key):
		cache[key] = _headings(_smooth(S, tt, sigma))
	return cache[key]


## Share of the samples where the ground stands between the drone and the subject while the drone is far
## from it (g.far_from, m; close to the subject the drone flies like in the other movements, and a tunnel
## hides the subject whatever the drone does).
static func _terrain_blocked(D: PackedVector3Array, g: Dictionary) -> float:
	var ground: Callable = g.ground
	if not ground.is_valid():
		return 0.0
	var S: PackedVector3Array = g.S
	var far_from := float(g.get("far_from", 0.0))
	var blocked := 0
	var count := 0
	for i in range(0, D.size(), 2):
		count += 1
		var aim := S[i] + Vector3(0.0, AIM_HEIGHT, 0.0)
		if Vector2(D[i].x - aim.x, D[i].z - aim.z).length() < far_from:
			continue
		for k in range(1, 10):
			var q := D[i].lerp(aim, k / 10.0)
			if float(ground.call(q.x, q.z)) > q.y + 0.3:
				blocked += 1
				break
	return blocked / maxf(count, 1.0)


## Appends the keys of one figure, from the last key (see _build_figures). f: the distances and speeds of
## the flight, and what alternates from one figure to the next (orbit direction, side of a dive / crossing).
static func _figure(kind: String, keys: Array, f: Dictionary, rng: RandomNumberGenerator) -> void:
	var a0 := float(keys[keys.size() - 1][1])
	var v := float(f.v)
	var tempo := float(f.tempo)
	var r_close := float(f.r_close)
	var r_far := float(f.r_far)
	var r_orbit := float(f.r_orbit)
	var h_close := float(f.h_close)
	var h_low := float(f.h_low)
	var h_top := float(f.h_top)
	var period := float(f.period)
	# b: the side the figure passes on (0 = the movement's side, PI = the other one); q: the direction of the
	# azimuth from ahead to behind on that side.
	var b := float(f.b)
	var q := -1.0 if b == 0.0 else 1.0
	match kind:
		"approach":
			var rot := float(f.rot)
			f.rot = -rot
			var e := rng.randf_range(0.35, 1.1) if rng.randf() < 0.6 else -rng.randf_range(0.35, 1.0)
			var a_in := _wrap_near(e if rng.randf() < 0.5 else PI - e, a0)
			_leg(keys, a_in, r_far, float(f.h_far), 1.1 * v, 2.6 * tempo)        # away: the subject gets tiny
			_hold(keys, 0.4 * tempo)
			var a_c := a_in + rot * 0.7
			_leg(keys, a_c, 1.4 * r_orbit, h_close + 0.2 * float(f.h_far), 1.25 * v, 2.2 * tempo)  # rushes in
			# the orbit rises and falls one and a half times: the camera tilts while it pans
			var turns := rng.randf_range(1.25, 1.75)
			var steps := 12
			for s in steps:
				var ph := float(s + 1) / steps
				_append(keys, period * turns / steps, a_c + rot * TAU * turns * ph, r_orbit,
						lerpf(h_low + 0.5, maxf(h_close, h_low) + 0.7 * r_orbit, 0.5 + 0.5 * cos(3.0 * PI * ph)))
		"dive":
			f.b = PI - b
			var a_top := b - q * (0.5 * PI - rng.randf_range(0.2, 0.55))
			var off := _wrap_near(a_top, a0) - a_top
			_leg(keys, a_top + off, float(f.r_top), h_top, v, 2.6 * tempo)                  # up, ahead
			_hold(keys, 0.3 * tempo)
			_leg(keys, b - q * 0.15 + off, r_close, h_low, 1.35 * v, 1.8 * tempo)            # dives onto it
			_leg(keys, b + q * 0.9 + off, 1.2 * r_close, h_low + 0.5 * h_close, v, 1.6 * tempo)  # skims past
			_leg(keys, b + q * 1.35 + off, float(f.r_top), 0.75 * h_top, 0.9 * v, 2.5 * tempo)  # climbs out behind
		"cross":
			f.b = PI - b
			var a_far := b - q * (0.5 * PI - rng.randf_range(0.12, 0.3))
			var off := _wrap_near(a_far, a0) - a_far
			_leg(keys, a_far + off, 0.85 * r_far, h_close + 0.12 * r_far, 1.1 * v, 2.6 * tempo)  # far ahead
			_hold(keys, 0.3 * tempo)
			_leg(keys, b - q * 0.1 + off, 1.15 * r_close, h_low + 0.3 * h_close, 1.4 * v, 2.0 * tempo)  # head-on
			_leg(keys, b + q * (0.5 * PI - 0.3) + off, 0.75 * r_far, h_close + 0.2 * r_far, 1.4 * v, 2.5 * tempo)
		_:  # spiral
			var rot := float(f.rot)
			f.rot = -rot
			var a_s := a0 + rot * 0.5
			_leg(keys, a_s, r_orbit, h_close, v, 2.0 * tempo)
			var turns := 1.25
			var steps := 10
			for s in steps:
				var ph := float(s + 1) / steps
				var up := sin(PI * ph)
				# a wider turn is flown slower: the centripetal acceleration stays the same
				_append(keys, period * turns / steps * (1.0 + 0.7 * up), a_s + rot * TAU * turns * ph,
						r_orbit * (1.0 + 1.6 * up), h_close + (0.7 * h_top - h_close) * up)


## Straight leg to (azimuth, distance, height) at `speed` (m/s, along the leg), lasting at least `min_dur` s.
static func _leg(keys: Array, az: float, r: float, h: float, speed: float, min_dur: float) -> void:
	var last: Array = keys[keys.size() - 1]
	var r0 := float(last[2])
	var length := Vector3(r - r0, 0.5 * (r + r0) * (az - float(last[1])), h - float(last[3])).length()
	_append(keys, maxf(min_dur, length / maxf(speed, 0.1)), az, r, h)


static func _hold(keys: Array, dur: float) -> void:
	var last: Array = keys[keys.size() - 1]
	_append(keys, dur, float(last[1]), float(last[2]), float(last[3]))


static func _append(keys: Array, dur: float, az: float, r: float, h: float) -> void:
	keys.append([float(keys[keys.size() - 1][0]) + dur, az, r, h])


## The angle equal to `a` (modulo a turn) nearest to `ref`.
static func _wrap_near(a: float, ref: float) -> float:
	return a + TAU * roundf((ref - a) / TAU)


# --- Events (reveal / flyby) -----------------------------------------------------------------

## The reveal / flyby events: when they happen and, over each, the track of the drone's place along the
## path relative to the subject (m, + = ahead) in seconds from the start of the event. The drone eases out
## to one end, sweeps across the subject to the other end, then eases back alongside. Every blend lasts as
## long as the acceleration limit of the level requires (a far drone has a longer way to go, so it takes
## longer). When the run is too short for the wanted number of events at that size, the events get smaller,
## then fewer.
static func _events(g: Dictionary, lp: Dictionary, time_mul: float, d0: float) -> Array:
	var movement: String = g.movement
	var T: float = g.T
	var keys: Array = [0.0, 1.0, -1.0, 0.0] if movement == "flyby" else [0.0, -0.96, 0.56, 0.0]
	var margin := 2.0
	var usable := T - 2.0 * margin
	var amp_full := tan(EVENT_ANGLE) * d0
	var count := 1 + int((float(lp.level) - 1.0) / 2.0)  # 1 event at levels 1-2, 2 at 3-4, 3 at 5
	var n_ev := 0
	var amp := 0.0
	for c in range(count, 0, -1):
		var f_min := 0.6 if c > 1 else 0.2  # fewer events rather than very small ones
		if not _events_fit(keys, lp, time_mul, amp_full * f_min, c, usable):
			continue
		var lo := f_min
		if _events_fit(keys, lp, time_mul, amp_full, c, usable):
			lo = 1.0
		else:
			var hi := 1.0
			for _it in 12:
				var mid := 0.5 * (lo + hi)
				if _events_fit(keys, lp, time_mul, amp_full * mid, c, usable):
					lo = mid
				else:
					hi = mid
		n_ev = c
		amp = amp_full * lo
		break
	if n_ev == 0:
		return []
	var durs := _event_durations(keys, lp, time_mul, amp)
	var total: float = durs[0] + durs[1] + durs[2]
	var out := []
	for tc in _event_times(g, total, n_ev, margin):
		var e := {"kind": movement, "t0": tc - 0.5 * total, "dur": total}
		var ts := [0.0, durs[0], durs[0] + durs[1], total]
		var track := []
		for k in 4:
			track.append([ts[k], float(keys[k]) * amp])
		e["ahead"] = track
		if movement == "reveal":
			# The row of obstacles hides the subject for a few seconds, around the start of the sweep.
			var occ := float(g.occlusion)
			e["hide1"] = durs[0] + (0.18 + 0.3 * occ) * durs[1]
			e["hide0"] = maxf(float(e.hide1) - (2.4 + 3.0 * occ), 0.0)
		else:
			e["pass0"] = durs[0]
			e["pass_t"] = durs[1]
		out.append(e)
	return out


## Seconds taken by the lead-in, the sweep and the tail of an event of amplitude `amp` (m): at least the
## nominal time, and long enough for a quintic blend of that length to respect the acceleration limit.
static func _event_durations(keys: Array, lp: Dictionary, time_mul: float, amp: float) -> Array:
	var a_lim := EVENT_ACCEL * float(lp.accel_cap)
	var nominal := [EVENT_LEAD, float(lp.sweep_time), EVENT_LEAD]
	var out := []
	for k in 3:
		var dist := absf(float(keys[k + 1]) - float(keys[k])) * amp
		out.append(time_mul * maxf(float(nominal[k]), sqrt(QUINTIC_PEAK * dist / a_lim)))
	return out


## True if `count` events of amplitude `amp` fit in `usable` seconds, with a free gap between them.
static func _events_fit(keys: Array, lp: Dictionary, time_mul: float, amp: float, count: int, usable: float) -> bool:
	var durs := _event_durations(keys, lp, time_mul, amp)
	return count * (durs[0] + durs[1] + durs[2]) + (count - 1) * EVENT_GAP <= usable


## Centre times of `count` events of `total` seconds, spread evenly over the run; each one moves to the
## straightest part of the path that the free time around it allows.
static func _event_times(g: Dictionary, total: float, count: int, margin: float) -> Array[float]:
	var tt: PackedFloat32Array = g.tt
	var curv: PackedFloat32Array = g.curv
	var n: int = g.n
	var T: float = g.T
	var out: Array[float] = []
	var slack := maxf(T - 2.0 * margin - count * total, 0.0) / float(count + 1)
	var prefix := PackedFloat32Array()
	prefix.resize(n + 1)
	for i in n:
		prefix[i + 1] = prefix[i] + curv[i]
	for k in count:
		var centre := margin + slack * (k + 1.0) + total * (k + 0.5)
		var best_t := centre
		var best_score := INF
		for i in n:
			var t := tt[i]
			if absf(t - centre) > 0.4 * slack:
				continue
			var lo := clampi(tt.bsearch(t - 0.5 * total), 0, n)
			var hi := clampi(tt.bsearch(t + 0.5 * total), 0, n)
			var score := prefix[hi] - prefix[lo]
			if score < best_score:
				best_score = score
				best_t = t
		out.append(best_t)
	return out


## Row of obstacles on the line of sight, long enough to hide the subject during each reveal. On a path that
## doubles back on itself (hairpins) the drone can fly right through an obstacle at another time of the run
## (or the subject drive through it): such an obstacle is moved along the line of sight (HIDE_FRACTIONS),
## or left out when no place is free.
static func _barriers(g: Dictionary, D: PackedVector3Array, events: Array,
		heads: PackedVector3Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if g.movement != "reveal":
		return out
	var S: PackedVector3Array = g.S
	var tt: PackedFloat32Array = g.tt
	var ground: Callable = g.ground
	var spacing := 3.0 * maxf(float(g.ds), 0.4)
	for e in events:
		var t_a := float(e.t0) + float(e.hide0)
		var t_b := float(e.t0) + float(e.hide1)
		var last := Vector3(INF, 0.0, INF)
		for i in g.n:
			if tt[i] < t_a or tt[i] > t_b:
				continue
			var aim: Vector3 = S[i] + Vector3(0.0, AIM_HEIGHT, 0.0)
			var usual: Vector3 = aim.lerp(D[i], HIDE_FRACTIONS[0])
			if Vector2(usual.x - last.x, usual.z - last.z).length() < spacing:
				continue
			for f in HIDE_FRACTIONS:
				var p: Vector3 = aim.lerp(D[i], f)
				var floor_y: float = float(ground.call(p.x, p.z)) if ground.is_valid() else S[i].y
				# A tree is only wide above 1.5 x its scale: the line of sight must cross it at that height, or it
				# only meets the trunk (a low drone looks along the ground).
				var tree_scale := clampf((p.y - floor_y) / 1.6, 1.0, 2.2)
				if _blocks_the_way(g, D, p, floor_y, tree_scale, t_a - 1.5, t_b + 1.5):
					continue
				last = p
				var head: Vector3 = heads[i]
				out.append({"pos": p, "scale": tree_scale, "yaw": atan2(head.x, head.z)})
				break
	return out


## True if a tree at `p` (ground height `floor_y`) would stand in the drone's flight, or on the subject's
## path, or hide the subject (for about half a second) at a time outside [t_a, t_b].
static func _blocks_the_way(g: Dictionary, D: PackedVector3Array, p: Vector3, floor_y: float, tree_scale: float,
		t_a: float, t_b: float) -> bool:
	var S: PackedVector3Array = g.S
	var tt: PackedFloat32Array = g.tt
	var r_crown: float = PropFactory.CONE_R[0] * tree_scale
	var r_drone := r_crown + 2.0
	var r_path := 0.35 * tree_scale + 2.5
	var top := floor_y + PropFactory.TREE_HEIGHT * tree_scale + 1.0
	var c := Vector2(p.x, p.z)
	var hidden := 0
	for j in g.n:
		if tt[j] >= t_a and tt[j] <= t_b:
			continue
		var a := Vector2(D[j].x, D[j].z)
		if a.distance_to(c) < r_drone and D[j].y < top:
			return true
		if Vector2(S[j].x, S[j].z).distance_to(c) < r_path:
			return true
		# the line of sight from the drone to the subject
		var ab := Vector2(S[j].x, S[j].z) - a
		var len2 := ab.length_squared()
		var u := 0.0 if len2 < 0.0001 else clampf((c - a).dot(ab) / len2, 0.0, 1.0)
		var d := (a + ab * u).distance_to(c)
		if d < r_crown:
			var y := lerpf(D[j].y, S[j].y + AIM_HEIGHT, u) - floor_y
			if d < PropFactory.tree_radius_at(y / tree_scale) * tree_scale:
				hidden += 1
				if hidden >= 3:
					return true
	return false


## Piecewise quintic blend through [[time, value], ...] keys (zero speed and acceleration at the keys).
static func _track(keys: Array, t: float) -> float:
	if t <= float(keys[0][0]):
		return float(keys[0][1])
	for k in range(1, keys.size()):
		if t <= float(keys[k][0]):
			var a: Array = keys[k - 1]
			var b: Array = keys[k]
			return lerpf(float(a[1]), float(b[1]), _sstep(float(a[0]), float(b[0]), t))
	return float(keys[keys.size() - 1][1])


# --- Measures ---------------------------------------------------------------------------------

## 95th percentile of the pan / tilt speed of the subject in the image (deg/s), 99th percentile of the
## acceleration (m/s²) and of the speed (m/s) of the drone, and the closest distance (m).
static func _measure(D: PackedVector3Array, S: PackedVector3Array, tt: PackedFloat32Array) -> Dictionary:
	var n := D.size()
	var az := PackedFloat32Array()
	var el := PackedFloat32Array()
	az.resize(n)
	el.resize(n)
	var prev := 0.0
	var dmin := INF
	for i in n:
		var d := S[i] + Vector3(0.0, AIM_HEIGHT, 0.0) - D[i]
		var a := atan2(d.x, d.z)
		if i > 0:
			a = prev + angle_difference(prev, a)
		prev = a
		az[i] = rad_to_deg(a)
		el[i] = rad_to_deg(atan2(d.y, Vector2(d.x, d.z).length()))
		dmin = minf(dmin, d.length())
	var wa := PackedFloat32Array()
	var we := PackedFloat32Array()
	var ac := PackedFloat32Array()
	var sp := PackedFloat32Array()
	for i in range(2, n - 2):
		var h0 := tt[i] - tt[i - 1]
		var h1 := tt[i + 1] - tt[i]
		if h0 < 0.001 or h1 < 0.001:
			continue
		wa.append(absf(az[i + 1] - az[i - 1]) / (h0 + h1))
		we.append(absf(el[i + 1] - el[i - 1]) / (h0 + h1))
		var a2 := 2.0 * ((D[i + 1] - D[i]) / h1 - (D[i] - D[i - 1]) / h0) / (h0 + h1)
		ac.append(a2.length())
		sp.append((D[i + 1] - D[i - 1]).length() / (h0 + h1))
	return {"pan95": _pct(wa, 0.95), "tilt95": _pct(we, 0.95), "acc99": _pct(ac, 0.99), "dmin": dmin,
			"spd99": _pct(sp, 0.99)}


static func _pct(a: PackedFloat32Array, q: float) -> float:
	if a.is_empty():
		return 0.0
	var b := a.duplicate()
	b.sort()
	return b[clampi(int(q * (b.size() - 1)), 0, b.size() - 1)]


# --- Filters ------------------------------------------------------------------------------------

## Gaussian low-pass in time (sigma in s) of a trajectory; the ends are kept in place (odd reflection).
## The kernel is cut at 4 sigma and shifted so that it reaches zero there, and every sample is weighted
## by the time it stands for: no jitter when the samples are not evenly spaced in time.
static func _smooth(P: PackedVector3Array, tt: PackedFloat32Array, sigma: float) -> PackedVector3Array:
	var n := P.size()
	if sigma <= 0.0 or n < 3:
		return P
	var span := 4.0 * sigma
	var pt := PackedFloat32Array()
	var pp := PackedVector3Array()
	var k0 := 1
	while k0 < n - 1 and tt[k0] - tt[0] <= span:
		k0 += 1
	for k in range(k0, 0, -1):
		pt.append(2.0 * tt[0] - tt[k])
		pp.append(2.0 * P[0] - P[k])
	var off := pt.size()
	for i in n:
		pt.append(tt[i])
		pp.append(P[i])
	var k1 := n - 2
	while k1 > 0 and tt[n - 1] - tt[k1] <= span:
		k1 -= 1
	for k in range(n - 2, k1 - 1, -1):
		pt.append(2.0 * tt[n - 1] - tt[k])
		pp.append(2.0 * P[n - 1] - P[k])
	# The kernel is wide: the sums only need samples a fraction of sigma apart (trapezoid rule on a Gaussian).
	var dt_mean := (tt[n - 1] - tt[0]) / float(n - 1)
	var step := maxi(1, int(0.2 * sigma / maxf(dt_mean, 0.0001)))
	if step > 1:
		var dpt := PackedFloat32Array()
		var dpp := PackedVector3Array()
		var j0 := 0
		while j0 < pt.size():
			dpt.append(pt[j0])
			dpp.append(pp[j0])
			j0 += step
		if dpt[dpt.size() - 1] < pt[pt.size() - 1]:
			dpt.append(pt[pt.size() - 1])
			dpp.append(pp[pp.size() - 1])
		pt = dpt
		pp = dpp
	var total := pt.size()
	var width := PackedFloat32Array()  # time represented by each sample
	width.resize(total)
	for j in total:
		width[j] = 0.5 * (pt[mini(j + 1, total - 1)] - pt[maxi(j - 1, 0)])
	var out := PackedVector3Array()
	out.resize(n)
	var inv := -0.5 / (sigma * sigma)
	var edge := exp(-8.0)  # value of the Gaussian at 4 sigma
	var lo := 0
	for i in n:
		var ti := tt[i]
		while pt[lo] < ti - span:
			lo += 1
		var acc := Vector3.ZERO
		var wsum := 0.0
		var j := lo
		while j < total and pt[j] <= ti + span:
			var dt := pt[j] - ti
			var w := (exp(dt * dt * inv) - edge) * width[j]
			acc += pp[j] * w
			wsum += w
			j += 1
		out[i] = acc / wsum if wsum > 0.0 else P[i]
	return out

## Smooth upper envelope of a signal: maximum over +/- win seconds, then Gaussian low-pass.
static func _envelope(v: PackedFloat32Array, tt: PackedFloat32Array, win: float, sigma: float) -> PackedFloat32Array:
	var n := v.size()
	var m := PackedVector3Array()
	m.resize(n)
	var lo := 0
	var hi := 0
	for i in n:
		while tt[lo] < tt[i] - win:
			lo += 1
		while hi < n and tt[hi] <= tt[i] + win:
			hi += 1
		var best := -INF
		for j in range(lo, hi):
			best = maxf(best, v[j])
		m[i] = Vector3(best, 0.0, 0.0)
	var sm := _smooth(m, tt, sigma)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = maxf(sm[i].x, v[i])
	return out


## Quintic smoothstep: zero speed and acceleration at both ends.
static func _sstep(a: float, b: float, x: float) -> float:
	var t := clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)


## 97th percentile of the horizontal distance between the subject and its low-passed path.
static func _swing(S: PackedVector3Array, C: PackedVector3Array) -> float:
	var d := PackedFloat32Array()
	for i in S.size():
		d.append(Vector2(S[i].x - C[i].x, S[i].z - C[i].z).length())
	return _pct(d, 0.97)


## Never closer to the subject than d_min (horizontally): pushes the drone away radially, then smooths
## the pushed path a little.
static func _keep_away(D: PackedVector3Array, S: PackedVector3Array, tt: PackedFloat32Array, d_min: float,
		heads: PackedVector3Array, sigma: float) -> PackedVector3Array:
	var pushed := false
	var out := D.duplicate()
	for i in out.size():
		var away := Vector2(out[i].x - S[i].x, out[i].z - S[i].z)
		var l := away.length()
		if l < d_min:
			var dir := away / l if l > 0.01 else Vector2(heads[i].z, -heads[i].x)
			out[i].x = S[i].x + dir.x * d_min
			out[i].z = S[i].z + dir.y * d_min
			pushed = true
	return _smooth(out, tt, sigma) if pushed else out


## Lifts the drone where it would be lower than min_h above the ground (or the hull of a tunnel): the
## lift is the smooth upper envelope of what is missing, so the height changes gently and the drone
## does not stay high for long on a slope.
static func _clear_ground(D: PackedVector3Array, tt: PackedFloat32Array, ground: Callable,
		min_h: float) -> PackedVector3Array:
	if not ground.is_valid():
		return D
	var n := D.size()
	var missing := PackedFloat32Array()
	missing.resize(n)
	var any := false
	for i in n:
		missing[i] = maxf(float(ground.call(D[i].x, D[i].z)) + min_h - D[i].y, 0.0)
		any = any or missing[i] > 0.0
	if not any:
		return D
	var lift := _envelope(missing, tt, ENVELOPE_WINDOW, ENVELOPE_SIGMA)
	var out := D.duplicate()
	for i in n:
		out[i].y += lift[i]
	return out


## Smooth maximum (never below max(a, b)).
static func _smax(a: float, b: float, k: float) -> float:
	return 0.5 * (a + b + sqrt((a - b) * (a - b) + k * k))


## Horizontal unit heading at each point of a smooth path.
static func _headings(P: PackedVector3Array) -> PackedVector3Array:
	var n := P.size()
	var out := PackedVector3Array()
	out.resize(n)
	var last := Vector3(0.0, 0.0, -1.0)
	for i in n:
		var d := P[mini(n - 1, i + 3)] - P[maxi(0, i - 3)]
		d.y = 0.0
		if d.length() > 0.001:
			last = d.normalized()
		out[i] = last
	# the first points (no direction yet) take the first known direction
	var first := 0
	while first < n and (P[mini(n - 1, first + 3)] - P[maxi(0, first - 3)]).length() <= 0.001:
		first += 1
	if first > 0 and first < n:
		for i in first:
			out[i] = out[first]
	return out

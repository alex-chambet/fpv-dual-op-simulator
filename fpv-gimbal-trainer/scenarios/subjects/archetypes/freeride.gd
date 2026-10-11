class_name ArchetypeFreeride
extends ArchetypeGlissePente
## FREERIDE: a rider's line down a big steep face (EnvFreeride), as in a Freeride World Tour run.
## The line is planned band by band: across each rock band the rider either drops a cliff (a straight approach with
## the speed checked at the lip, a flight of 1 to 2 s, a hard landing that kills part of the speed) or skis a
## couloir through the rock (short, slow turns). Between the bands each stretch has its own style: big fast turns,
## medium turns, a straight-line, or short technical turns. At the bottom, a fast run over the apron, through the
## finish and a skid to a stop.
## The speed comes from a small physical model: gravity on the slope, friction in the powder, air drag, the
## hardest carve the rider can hold, the rider braking (skidding) to the speed of the next stretch, the flight, and
## the landing (only the speed along the slope is kept, and not all of it). So the speed jumps around: 5 m/s in a
## couloir, 25 m/s and more in a straight-line, a fall to half speed at a landing.
## Airs are not placed by hand: wherever the ground falls away faster than the rider's ballistic arc (the lip of a
## cliff, a convex roll, a spine), the rider takes off; tiny ones are absorbed.

const DZ := 1.0               # m of z between path points (the line is a function x(z), down the face along +Z)
const GRAVITY := 9.81
const BRAKE := 7.0            # m/s², skidding to check the speed
const STOP_BRAKE := 6.0       # m/s², the skid to a stop after the finish
const START_SPEED := 7.5      # m/s, after the push-off (poles) and the first strides
const FIG_POP := 3.2          # m/s: the pop at the lip of a cliff where the rider does a figure
const SPIN_MIN_AIR := 0.7     # s of flight needed for the 360
const FLIP_MIN_AIR := 0.95    # s of flight needed for the backflip
const POP_TIME := 0.12        # s, how fast the pop at the lip builds up
const LIP_CARRY := 6.0        # m: on a rounded lip the snow carries the rider this long before the flight
const MIN_AIR := 1.8          # m: a smaller air (a roll, a spine) is absorbed: the rider stays on the snow
const DROP_LEAD := 22.0       # m of straight line before a cliff...
const DROP_TAIL := 20.0       # ...and after it (the landing and the ride-out)
const STOP_LENGTH := 36.0     # m from the finish line to where the rider stops
const ABSORB := 2.5           # m/s: over a roll he did not choose to jump, the rider presses his skis down this much
const BLIND_SPEED := 14.0     # m/s: the speed checked above a band crossed without dropping (a roll, a couloir)
const MAX_AIR := 38.0         # m: an air longer than this that the rider did not choose: he checks his speed before
const FACE_STRAIGHT := 23.0   # m/s: the fastest straight-line on the face (faster on the apron)


func id() -> String:
	return "FREERIDE"


func summary() -> String:
	return "Freeride: a line down a steep face, cliff drops, couloirs, big turns, straight-lines, abrupt speed changes."


func defaults() -> Dictionary:
	var d := super.defaults()
	d.merge({
		"subject_size": 1.8,
		"speed_min": 3.0, "speed_max": 30.0, "speed_variability": 0.0,
		"cornering_accel": 9.0,
		"lean_max_deg": 50.0, "lean_gain": 0.85,
		"sample_step": DZ,
		"duration": 90.0,
		"gates": false, "leaves_tracks": true, "spray": true,
		"jump_visual": "none", "jump_height": 0.8,
		"drop_share": 0.65, "snow_friction": 0.07, "air_drag": 0.0035,
		"drone_min_height": 5.0,
	}, true)
	return d


## The face is what it is: the run lasts what the line takes (about 1 min 20 to 1 min 50).
func fits_duration() -> bool:
	return false


func path_length(_p: Dictionary) -> float:
	return 1400.0


# --- Line ----------------------------------------------------------------------------------------

func generate(ctx: ArchetypeContext) -> Dictionary:
	var env = ctx.env
	if not env.has_method("band_count"):
		return super.generate(ctx)  # not on a freeride face: plain turns down the slope
	var p := ctx.params
	var rng := ctx.rng
	var s0: Vector3 = env.freeride_start()
	var z_fin: float = env.freeride_finish_z()
	var xlim: float = env.face_half_width(0.0)
	var wps := _plan_line(env, p, rng, s0, z_fin, xlim)
	var line := _line(ctx, env, wps, rng, s0, z_fin, xlim)
	var ground_pts: PackedVector3Array = line.points
	var cap: PackedFloat32Array = line.cap
	# speeds on the ground, then the airs those speeds give, then the speeds with the airs (twice)
	var speeds := _speeds(ground_pts, cap, p, {}, {})
	var pts := ground_pts
	var events: Array = []
	# where the rider means to jump: the lips of the cliffs of the line
	# two of them (the biggest cliffs) carry a figure: a 360 on the first, a backflip on the second (a lone one: the flip)
	var drops: Array = wps.filter(func(w): return str(w.kind) == "drop")
	var by_size := drops.duplicate()
	by_size.sort_custom(func(a, b): return float(env.band_drop(int(a.k))) > float(env.band_drop(int(b.k))))
	var figs: Array = by_size.slice(0, 2)
	figs.sort_custom(func(a, b): return float(a.z) < float(b.z))
	for fi in figs.size():
		figs[fi]["fig"] = ("spin" if fi == 0 else "flip") if figs.size() == 2 else "flip"
	var lips := PackedVector3Array()   # x, z of the lip, pop (m/s)
	var pop0 := float(p.get("jump_height", 0.8))
	for w in drops:
		lips.append(Vector3(float(w.x), float(w.z) - float(env.band_width(int(w.k), float(w.x))) * 0.5,
				FIG_POP if w.has("fig") else pop0))
	for _pass in 6:
		pts = ground_pts.duplicate()
		var too_long: Array = []
		events = _airs(pts, speeds, pop0, lips, {}, {}, too_long)
		if too_long.is_empty():
			break
		# he would fly too far over that roll: he checks his speed before it
		for i0 in too_long:
			var v0 := speeds[i0]
			for i in range(maxi(int(i0) - 45, 0), int(i0) + 1):
				cap[i] = minf(cap[i], maxf(v0 * 0.72, 8.0))
		speeds = _speeds(ground_pts, cap, p, {}, {})
	# the airs at these speeds, then the speeds with the airs and the airs again with those (the landings change
	# the speed further down)
	for _pass in 2:
		pts = ground_pts.duplicate()
		var air := {}
		var landing := {}
		events = _airs(pts, speeds, pop0, lips, air, landing, [])
		speeds = _speeds(pts, cap, p, air, landing)
	# the figures, where the flight is long enough for them
	for w in figs:
		var lip_z := float(w.z) - float(env.band_width(int(w.k), float(w.x))) * 0.5
		for ev in events:
			if absf(float(ev.p0.x) - float(w.x)) < 10.0 and float(ev.p0.z) > lip_z - 12.0 and float(ev.p0.z) < lip_z + 6.0:
				if str(w.fig) == "spin" and float(ev.air_time) >= SPIN_MIN_AIR:
					ev["spin_deg"] = 360.0
				elif str(w.fig) == "flip" and float(ev.air_time) >= FLIP_MIN_AIR:
					ev["flips"] = 1
	# a figure missing (too few cliffs on the line): done on the longest other air that is long enough
	for want in ["spin_deg", "flips"]:
		var have := false
		for ev in events:
			have = have or ev.has(want)
		if have:
			continue
		var best = null
		for ev in events:
			if ev.has("spin_deg") or ev.has("flips"):
				continue
			if float(ev.air_time) >= (SPIN_MIN_AIR if want == "spin_deg" else FLIP_MIN_AIR) + 0.3 \
					and (best == null or float(ev.air_time) > float(best.air_time)):
				best = ev
		if best != null:
			best[want] = 360.0 if want == "spin_deg" else 1
	var cum := PathUtil.cumulative(pts)
	var profile := PathUtil.profile_from_samples(speeds, cum, maxi(200, int(cum[cum.size() - 1] / 1.5)))
	return {"points": pts, "profile": profile, "events": events, "zone": Rect2()}


## Where the line crosses each rock band (a cliff to drop, a couloir, or a roll beyond the rock), within reach of
## where the rider comes from. Returns [{z, x, kind, k}] from the start to the finish.
func _plan_line(env, p: Dictionary, rng: RandomNumberGenerator, s0: Vector3, z_fin: float, xlim: float) -> Array:
	var wps := [{"z": s0.z, "x": s0.x, "kind": "start", "k": -1}]
	var x := s0.x
	var z := s0.z
	var drops_made := 0
	var drop_share := float(p.get("drop_share", 0.65))
	for k in int(env.band_count()):
		var dz: float = float(env.band_z(k, x)) - z
		var reach := clampf(0.5 * (dz - 30.0), 12.0, 140.0)
		var cliffs := []
		var couloirs := []
		var rolls := []
		var cx := -xlim
		while cx <= xlim:
			if absf(cx - x) <= reach:
				var rock: float = env.band_rock(k, cx)
				var w: float = env.band_width(k, cx)
				if rock > 0.95 and float(env.band_rock(k, cx - 6.0)) > 0.9 and float(env.band_rock(k, cx + 6.0)) > 0.9:
					cliffs.append(cx)
				elif rock < 0.05 and w < 40.0 and float(env.band_width(k, cx - 3.0)) < 40.0 \
						and float(env.band_width(k, cx + 3.0)) < 40.0:
					couloirs.append(cx)
				elif w > 47.0:
					rolls.append(cx)
			cx += 2.0
		var kind := ""
		var pick := []
		# two drops at least (the figures are done over cliffs): forced when the bands left are just enough for them
		var forced := drops_made < 2 and int(env.band_count()) - k <= 2 - drops_made
		if not cliffs.is_empty() and (forced or rng.randf() < drop_share or (couloirs.is_empty() and rolls.is_empty())):
			kind = "drop"
			pick = cliffs
			drops_made += 1
		elif not couloirs.is_empty():
			kind = "couloir"
			pick = couloirs
		elif not rolls.is_empty():
			kind = "roll"
			pick = rolls
		elif not cliffs.is_empty():
			kind = "drop"
			pick = cliffs
			drops_made += 1
		else:
			continue
		var nx: float = pick[rng.randi() % pick.size()]
		var nz: float = env.band_z(k, nx)
		wps.append({"z": nz, "x": nx, "kind": kind, "k": k})
		x = nx
		z = nz
	var xf := clampf(x * 0.3 + rng.randf_range(-30.0, 30.0), -60.0, 60.0)
	wps.append({"z": z_fin, "x": xf, "kind": "finish", "k": -1})
	return wps


## The path on the ground: a base line through the waypoints (straight down the fall line at each of them), with
## the turns of each stretch on top. Returns {points, cap (speed the rider allows himself at each point)}.
func _line(ctx: ArchetypeContext, env, wps: Array, rng: RandomNumberGenerator, s0: Vector3, z_fin: float,
		xlim: float) -> Dictionary:
	var z_stop := z_fin + STOP_LENGTH
	var n := int((z_stop - s0.z) / DZ) + 1
	var face_end := float(env.get("face_end")) if env.get("face_end") != null else z_fin - 300.0
	# a style per stretch: [amplitude (m), wavelength (m), speed (m/s)]
	var styles := []
	for j in wps.size() - 1:
		var r := rng.randf()
		var last := j == wps.size() - 2
		if r >= 0.43 and r < 0.6 and float(wps[j + 1].z) - float(wps[j].z) > 90.0:
			r = 0.1  # no long technical stretch: medium turns instead
		if j == 0 or (not last and r < 0.25):
			if j == 0:
				styles.append([rng.randf_range(1.5, 2.5), rng.randf_range(60.0, 80.0), 24.0])  # a quick first stretch, nearly straight
			else:
				styles.append([rng.randf_range(4.0, 6.0), rng.randf_range(40.0, 55.0), 15.0])      # medium turns
		elif last and r < 0.5 or (not last and r < 0.43):
			styles.append([rng.randf_range(0.6, 1.4), rng.randf_range(60.0, 80.0), 29.0])      # straight-line
		elif not last and r < 0.6:
			styles.append([rng.randf_range(1.6, 2.2), rng.randf_range(11.0, 14.0), 9.0])       # technical
		else:
			styles.append([rng.randf_range(7.0, 11.0), rng.randf_range(95.0, 125.0), 22.0])    # big turns
	var amp := PackedFloat32Array()
	var wl := PackedFloat32Array()
	var cap := PackedFloat32Array()
	var base := PackedFloat32Array()
	amp.resize(n)
	wl.resize(n)
	cap.resize(n)
	base.resize(n)
	var j := 0
	var stop_side := -1.0 if rng.randf() < 0.5 else 1.0
	for i in n:
		var z := s0.z + i * DZ
		while j < wps.size() - 2 and z >= float(wps[j + 1].z):
			j += 1
		var w0: Dictionary = wps[j]
		var w1: Dictionary = wps[j + 1]
		var u := clampf((z - float(w0.z)) / maxf(float(w1.z) - float(w0.z), 1.0), 0.0, 1.0)
		base[i] = lerpf(float(w0.x), float(w1.x), u * u * u * (u * (u * 6.0 - 15.0) + 10.0))
		var st: Array = styles[j]
		var a := float(st[0])
		var l := float(st[1])
		var c := float(st[2])
		for w in wps:
			var dz := z - float(w.z)
			match str(w.kind):
				"drop":
					# straight at the cliff, the speed checked at the lip, then the ride-out
					a *= 1.0 - smoothstep(-DROP_LEAD - 14.0, -DROP_LEAD, dz) * (1.0 - smoothstep(DROP_TAIL, DROP_TAIL + 14.0, dz))
					if dz > -DROP_LEAD - 20.0 and dz < -1.0:
						c = minf(c, 9.0 + 0.25 * float(env.band_drop(int(w.k))))
				"couloir", "roll":
					# the speed checked above a band crossed without dropping (the rider cannot see what is below)
					if dz > -45.0 and dz < -float(env.band_width(int(w.k), float(w.x))) * 0.5:
						c = minf(c, BLIND_SPEED)
					if str(w.kind) == "roll":
						continue
					var half := float(env.band_width(int(w.k), float(w.x))) * 0.5 + 6.0
					if absf(dz) < half + 8.0:
						var k := 1.0 - smoothstep(half, half + 8.0, absf(dz))
						a = lerpf(a, 1.6, k)
						l = lerpf(l, 12.0, k)
						c = lerpf(c, 7.0, k)
				"start":
					if dz < 18.0:
						a *= smoothstep(8.0, 18.0, dz)
						c = minf(c, 17.0)
		if z > z_fin - 80.0:
			a *= 1.0 - smoothstep(z_fin - 80.0, z_fin - 55.0, z)  # straight into the finish (the spectators line it)
		if z > z_fin:
			# the skid to a stop, curving to one side
			var f := (z - z_fin) / STOP_LENGTH
			base[i] += stop_side * 12.0 * f * f
			c = minf(c, sqrt(2.0 * STOP_BRAKE * maxf(z_stop - z, 0.0)) + 0.5)
		if z < face_end:
			c = minf(c, FACE_STRAIGHT)
		amp[i] = a
		wl[i] = l
		cap[i] = c
	amp = _box(amp, 8)
	wl = _box(wl, 8)
	var pts := PackedVector3Array()
	pts.resize(n)
	var phase := rng.randf() * TAU
	for i in n:
		phase += TAU * DZ / maxf(wl[i], 4.0)
		var z := s0.z + i * DZ
		var x := clampf(base[i] + amp[i] * sin(phase), -xlim, xlim)
		pts[i] = Vector3(x, ctx.ground(x, z), z)
	# the hardest carve the rider holds in the turns
	var a_lat := float(ctx.params.cornering_accel)
	var kappa := PathUtil.curvature(pts)
	for i in n:
		cap[i] = minf(cap[i], sqrt(a_lat / maxf(absf(kappa[i]), 0.0001)))
	return {"points": pts, "cap": cap}


static func _box(a: PackedFloat32Array, r: int) -> PackedFloat32Array:
	var n := a.size()
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var s := 0.0
		var c := 0
		for k in range(maxi(i - r, 0), mini(i + r + 1, n)):
			s += a[k]
			c += 1
		out[i] = s / c
	return out


# --- Airs ----------------------------------------------------------------------------------------

## Finds the airs along the ground path `pts` at the given speeds and puts the flights in `pts`: the rider leaves the
## snow where its arc, launched along the slope, is already 12 cm above it 3 m further; the arc (with a pop built up
## over POP_TIME) is followed until it meets the snow. Airs under MIN_AIR are absorbed. Fills `air` (indices in
## the air) and `landing` (index of each landing -> share of the speed kept). Returns the jump events.
func _airs(pts: PackedVector3Array, speeds: PackedFloat32Array, pop0: float, lips: PackedVector3Array, air: Dictionary,
		landing: Dictionary, too_long: Array) -> Array:
	var events: Array = []
	var n := pts.size()
	var i := 3
	while i < n - 8:
		var a := pts[i - 2]
		var b := pts[i]
		var dist := a.distance_to(b)
		if dist < 0.01:
			i += 1
			continue
		var v := speeds[i]
		var vh := maxf(v * Vector2(b.x - a.x, b.z - a.z).length() / dist, 0.5)
		var vy := v * (b.y - a.y) / dist
		# at the lip of a cliff of his line the rider pops; anywhere else he presses over the roll
		var pop := -ABSORB
		for lp in lips:
			if absf(lp.x - b.x) < 8.0 and b.z > lp.y - 10.0 and b.z < lp.y + 4.0:
				pop = lp.z
		var d := 0.0
		for k in range(i + 1, i + 4):
			d += Vector2(pts[k].x - pts[k - 1].x, pts[k].z - pts[k - 1].z).length()
		var t3 := d / vh
		if b.y + vy * t3 - 0.5 * GRAVITY * t3 * t3 - pts[i + 3].y < 0.12:
			i += 1
			continue
		# the flight
		d = 0.0
		var i1 := -1
		var flight := PackedFloat32Array()
		var peak := 0.0
		var t := 0.0
		for k in range(i + 1, n):
			d += Vector2(pts[k].x - pts[k - 1].x, pts[k].z - pts[k - 1].z).length()
			t = d / vh
			var lift := pop * (t - POP_TIME * (1.0 - exp(-t / POP_TIME)))
			var y := b.y + vy * t - 0.5 * GRAVITY * t * t + lift
			if d < LIP_CARRY:
				y = maxf(y, pts[k].y)
			elif y <= pts[k].y:
				i1 = k
				break
			elif d > 70.0:
				break  # no landing found: not an air (the rider stays on the snow)
			flight.append(y)
			peak = maxf(peak, y - pts[k].y)
		if pop < 0.0 and (i1 < 0 or d > MAX_AIR):
			too_long.append(i)
		if i1 < 0 or peak < MIN_AIR:
			i += 2
			continue
		for k in range(i + 1, i1):
			pts[k] = Vector3(pts[k].x, flight[k - i - 1], pts[k].z)
			air[k] = true
		# landing: only the speed along the slope is kept, and the powder takes some of it
		var vy_land := vy - GRAVITY * t + pop * (1.0 - exp(-t / POP_TIME))
		var dir_h := Vector2(pts[i1].x - pts[i1 - 1].x, pts[i1].z - pts[i1 - 1].z).normalized()
		var vel := Vector3(dir_h.x * vh, vy_land, dir_h.y * vh)
		var slope := (pts[mini(i1 + 2, n - 1)] - pts[i1]).normalized()
		landing[i1] = clampf(vel.normalized().dot(slope), 0.3, 1.0) * 0.85
		events.append({"type": "jump", "i0": i, "i1": i1, "p0": pts[i], "p1": pts[i1], "height": peak,
				"ramp_i": i, "ramp_h": 0.0, "length": d, "air_time": t})
		i = i1 + 6
	return events


# --- Speed ---------------------------------------------------------------------------------------

## Speed at each point: gravity, friction in the powder (not in the air), air drag; never above the rider's cap
## (braking to it beforehand, BRAKE m/s², except before an air: a landing is not chosen); at a landing, only the
## share of the speed in `landing` is kept.
func _speeds(pts: PackedVector3Array, cap: PackedFloat32Array, p: Dictionary, air: Dictionary,
		landing: Dictionary) -> PackedFloat32Array:
	var n := pts.size()
	var mu := float(p.get("snow_friction", 0.07))
	var drag := float(p.get("air_drag", 0.0035))
	var vmax := float(p.speed_max)
	var vmin := float(p.speed_min)
	var v := PackedFloat32Array()
	v.resize(n)
	v[0] = START_SPEED
	for i in range(1, n):
		var ds := maxf(pts[i].distance_to(pts[i - 1]), 0.001)
		var drop := pts[i - 1].y - pts[i].y
		var cos_b := Vector2(pts[i].x - pts[i - 1].x, pts[i].z - pts[i - 1].z).length() / ds
		var v2 := v[i - 1] * v[i - 1] + 2.0 * GRAVITY * drop
		if not air.has(i):
			v2 -= 2.0 * mu * GRAVITY * cos_b * ds
		v2 -= 2.0 * drag * v[i - 1] * v[i - 1] * ds
		var vi := sqrt(maxf(v2, 0.25))
		if landing.has(i):
			vi *= float(landing[i])
		v[i] = vi if air.has(i) else minf(vi, cap[i])
	for i in range(n - 2, -1, -1):
		if air.has(i + 1) or landing.has(i + 1):
			continue
		var ds := pts[i + 1].distance_to(pts[i])
		v[i] = minf(v[i], sqrt(v[i + 1] * v[i + 1] + 2.0 * BRAKE * ds))
	for i in n:
		if not air.has(i):
			v[i] = clampf(v[i], vmin if i > 20 and i < n - 25 else 0.8, vmax)
	return v


# --- Runtime -------------------------------------------------------------------------------------

func on_ready(s: ArchetypeSubject) -> void:
	if bool(s.params.leaves_tracks):
		_build_trail(s)
	if bool(s.params.spray):
		_build_powder(s)


## The figures of the jump events: a backflip (event "flips") or a 360 (event "spin_deg"), done between the pop and
## the landing and turning about the rider's centre (the model's origin is at his feet).
func animate_jump(s: ArchetypeSubject, delta: float) -> void:
	var ev := s.current_jump()
	if ev.is_empty() or not (ev.has("flips") or ev.has("spin_deg")):
		super.animate_jump(s, delta)
		s.model.position.x = 0.0
		s.model.position.z = 0.0
		return
	var u := clampf((s.progress_ratio - float(ev.r0)) / maxf(float(ev.r1) - float(ev.r0), 0.0001), 0.0, 1.0)
	var k := smoothstep(0.12, 0.85, u)
	s.model.rotation.x = TAU * float(ev.get("flips", 0)) * k      # backwards (the rider faces -z)
	s.model.rotation.y = deg_to_rad(float(ev.get("spin_deg", 0.0))) * k
	var c := Vector3(0.0, 0.95, 0.0)
	var off := c - Basis.from_euler(s.model.rotation, EULER_ORDER_YXZ) * c
	s.model.position.x = off.x
	s.model.position.z = off.z
	s.model.position.y += off.y


## A freerider stands fairly tall in the powder, sinks a little when fast, opens up in the air and absorbs every
## landing; a cloud of powder at each landing.
func animate(s: ArchetypeSubject, delta: float) -> void:
	super.animate(s, delta)
	var in_air := not s.current_jump().is_empty()
	var since := float(s.state.get("landed", 9.0)) + delta
	if bool(s.state.get("air", false)) and not in_air:
		since = 0.0
		if s.state.has("burst"):
			var burst: GPUParticles3D = s.state["burst"]
			burst.restart()
	s.state["air"] = in_air
	s.state["landed"] = since
	if not s.parts.has("athlete"):
		return
	var target := 0.12 + 0.25 * smoothstep(14.0, 26.0, s.speed_now)
	if in_air:
		var ev := s.current_jump()
		target = 1.0 if (ev.has("flips") or ev.has("spin_deg")) else 0.35  # tucked for a figure
	target = maxf(target, 0.95 * (1.0 - smoothstep(0.08, 0.5, since)))
	var a: AthleteModel = s.parts["athlete"]
	a.tuck = lerpf(a.tuck, target, 1.0 - exp(-delta / 0.08))


## Powder: a big spray in the turns (toggled by ArchetypeGlissePente.animate, like the spray of the slopes) and a
## one-shot cloud at each landing.
func _build_powder(s: ArchetypeSubject) -> void:
	var q := clampi(GraphicsSettings.quality, 0, 3)
	var spray := _puffs([140, 200, 280, 340][q], 1.5, 0.2)
	spray.position = Vector3(0, 0.2, 0.6)
	var pm := spray.process_material as ParticleProcessMaterial
	pm.direction = Vector3(0, 1, 0.8)
	pm.spread = 40.0
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 5.5
	pm.gravity = Vector3(0, -2.5, 0)
	pm.damping_min = 1.5
	pm.damping_max = 2.5
	pm.scale_min = 0.8
	pm.scale_max = 1.9
	s.model.add_child(spray)
	s.state["spray"] = spray
	var burst := _puffs([60, 90, 130, 160][q], 1.9, 0.32)
	burst.one_shot = true
	burst.explosiveness = 0.85
	burst.position = Vector3(0, 0.3, 0)
	var bm := burst.process_material as ParticleProcessMaterial
	bm.direction = Vector3(0, 1, 0)
	bm.spread = 75.0
	bm.initial_velocity_min = 2.5
	bm.initial_velocity_max = 7.0
	bm.gravity = Vector3(0, -2.0, 0)
	bm.damping_min = 2.0
	bm.damping_max = 3.0
	bm.scale_min = 0.9
	bm.scale_max = 2.2
	s.model.add_child(burst)
	s.state["burst"] = burst


static func _puffs(amount: int, lifetime: float, radius: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.local_coords = false
	p.emitting = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-12, -6, -12), Vector3(24, 14, 24))
	var pm := ParticleProcessMaterial.new()
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0.8))
	ramp.set_color(1, Color(1, 1, 1, 0.0))
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp
	pm.color_ramp = ramp_tex
	p.process_material = pm
	var puff := SphereMesh.new()
	puff.radius = radius
	puff.height = radius * 2.0
	puff.radial_segments = 6
	puff.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(1, 1, 1)
	puff.material = mat
	p.draw_pass_1 = puff
	return p

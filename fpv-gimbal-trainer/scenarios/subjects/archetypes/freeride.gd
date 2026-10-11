class_name ArchetypeFreeride
extends ArchetypeGlissePente
## FREERIDE: a rider's line down a big steep face (EnvFreeride), as in a Freeride World Tour run.
## The line is planned band by band: across each rock band the rider either drops a cliff (a check turn above it,
## a short straight approach, a flight of 1 to 2 s, a hard landing that kills part of the speed) or skis a couloir
## through the rock (short turns). Between the bands each stretch has its own style: big fast turns, medium turns,
## a straight-line, or short turns. At the bottom, a fast run over the apron, through the finish and a skid to a stop.
## The speed is ridden, not imposed (as in a winning FWT run watched second by second, POV and drone views): the
## slope, the friction in the powder and the air drag act all the time, and the rider can only lose speed by
## skidding, skis across the slope:
##  - at the end of each of his turns (short turns hold the speed on the steepest face),
##  - in a check turn: a hard skid to one side, about a second long, thrown when he goes faster than he wants (in a
##    straight-line, before a cliff, after a landing),
##  - when he is too fast for a curve (he cannot hold it on his edges: he slides),
##  - and in the stop after the finish.
## So he never slows down with his skis straight down the slope: a straight-line always accelerates, a skid (skis
## across, a cloud of snow) always brakes, a landing kills part of the speed, a flatter slope slows him gently. The
## operator can read what comes next from what the skis do.
## Airs are not placed by hand: wherever the ground falls away faster than the rider's ballistic arc (the lip of a
## cliff, a convex roll, a spine), the rider takes off; tiny ones are absorbed.

const DZ := 1.0               # m of z between path points (the line is a function x(z), down the face along +Z)
const GRAVITY := 9.81
const D_SKID := 16.0          # m/s²: the hardest skid, skis right across the slope (on top of the friction)
const SKID_RANGE := 3.0       # m/s over the speed he wants for the hardest skid (less over it: a lighter skid)
const D_PLAN := 8.0           # m/s²: how early the rider starts slowing down for what comes (late: he keeps his speed, then checks hard)
const CHECK_TOL := 3.0        # m/s over the speed he wants before he throws a check turn
const CHECK_SCRUB := 0.8      # share of the speed left after a check turn (a short skid, not a stop)
const STOP_BRAKE := 6.0       # m/s², the skid to a stop after the finish
const START_SPEED := 7.5      # m/s, after the push-off (poles) and the first strides
const LIP_CHECK := 18.0       # m: above a technical take-off, the check turn starts this far before the lip...
const LIP_CHECK_LEN := 14     # ...and lasts this long (m); then a few metres to the lip
const LIP_SPEED := 3.5        # m/s left after that check: he nearly stops, looks over the edge, places himself, goes
const FAST_CHECK := 22.0      # m: above an easy take-off, a light check turn this far before the lip...
const FAST_CHECK_LEN := 16    # ...this long (m)...
const FAST_SPEED := 9.0       # ...down to this speed only: he takes the cliff with speed (about 14 m/s at the lip)
const FAST_LIP := 14.0        # m/s he allows himself at an easy lip
const SKID_YAW := 1.05        # rad: in the hardest skid the skis point this much further across than he goes
const FIG_POP := 3.2          # m/s: the pop at the lip of a cliff where the rider does a figure
const SPIN_MIN_AIR := 0.7     # s of flight needed for the 360
const FLIP_MIN_AIR := 0.95    # s of flight needed for the backflip
const POP_TIME := 0.12        # s, how fast the pop at the lip builds up
const LIP_CARRY := 6.0        # m: on a rounded lip the snow carries the rider this long before the flight
const MIN_AIR := 1.8          # m: a smaller air (a roll, a spine) is absorbed: the rider stays on the snow
const DROP_LEAD := 30.0       # m of straight line before a cliff (the check turn above it is the last turn)...
const DROP_TAIL := 24.0       # ...and after it (the landing and the ride-out)
const STOP_LENGTH := 36.0     # m from the finish line to where the rider stops
const ABSORB := 2.5           # m/s: over a roll he did not choose to jump, the rider presses his skis down this much
const BLIND_SPEED := 14.0     # m/s: the speed checked above a band crossed without dropping (a roll, a couloir)
const MAX_AIR := 30.0         # m: an air longer than this that the rider did not choose: he checks his speed before
const MAX_DROP_AIR := 42.0    # m: a cliff he chose, taken with speed, never flies further (he comes in slower)
const FACE_STRAIGHT := 23.0   # m/s: the fastest straight-line on the face (faster on the apron)


func id() -> String:
	return "FREERIDE"


func summary() -> String:
	return "Freeride: a line down a steep face, cliff drops, couloirs, turns, straight-lines; slows down only by skidding."


func defaults() -> Dictionary:
	var d := super.defaults()
	d.merge({
		"subject_size": 1.8,
		"speed_min": 3.0, "speed_max": 30.0, "speed_variability": 0.0,
		"cornering_accel": 12.0,
		"lean_max_deg": 50.0, "lean_gain": 0.85,
		"sample_step": DZ,
		"duration": 90.0,
		"gates": false, "leaves_tracks": true, "spray": true,
		"jump_visual": "none", "jump_height": 0.3,
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
	var base := _line(ctx, env, wps, rng, s0, z_fin, xlim)
	var n: int = (base.x as PackedFloat32Array).size()
	# where he means to jump: the lips of the cliffs of the line, each with a check turn above it
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
	var checks: Array = []
	for w in drops:
		var lip_z := float(w.z) - float(env.band_width(int(w.k), float(w.x))) * 0.5
		lips.append(Vector3(float(w.x), lip_z, FIG_POP if w.has("fig") else pop0))
		# a technical take-off: he nearly stops above it; an easy one: a light check, then he goes for it with speed
		var tech := bool(w.tech)
		var length := LIP_CHECK_LEN if tech else FAST_CHECK_LEN
		var i0 := clampi(int((lip_z - (LIP_CHECK if tech else FAST_CHECK) - s0.z) / DZ), 12, n - length - 1)
		checks.append(_check(i0, length, _side(rng, base.x, i0 + (length >> 1), xlim),
				LIP_SPEED if tech else FAST_SPEED, 0.85 if tech else 0.7))
	# the ride, the airs it gives and the ride with those airs, again and again: each time the rider goes clearly
	# faster than he wants and his turns cannot help, he throws a check turn there; before an air he did not choose
	# and that would be too long, he allows himself less speed
	var extra := PackedFloat32Array()
	extra.resize(n)
	extra.fill(INF)
	var air := {}
	var landing := {}
	var pts := PackedVector3Array()
	var path := {}
	var ride := {}
	var events: Array = []
	for _pass in 100:
		path = _with_checks(ctx, base, checks, xlim)
		var g: PackedVector3Array = path.pts
		var kappa := PathUtil.curvature(g)
		var want := _plan_speed(g, base.want, extra, path, kappa, air, landing, p)
		ride = _ride(g, want, path, kappa, air, landing, p)
		pts = g.duplicate()
		air = {}
		landing = {}
		var too_long: Array = []
		events = _airs(pts, ride.v, pop0, lips, air, landing, too_long)
		want = _plan_speed(pts, base.want, extra, path, kappa, air, landing, p)
		ride = _ride(pts, want, path, kappa, air, landing, p)
		var lower := false
		for i0 in too_long:
			var c := maxf(float(ride.v[int(i0)]) * 0.72, 8.0)
			for i in range(maxi(int(i0) - 45, 0), int(i0) + 1):
				if c < extra[i] - 0.5:
					extra[i] = c
					lower = true
		# after a real air, as soon as his skis are back on the snow (0 to 0.5 s), he checks his speed with a skid
		for ev in events:
			if float(ev.air_time) < 0.45:
				continue
			var i1 := int(ev.i1)
			var c := maxf(float(ride.v[i1]) * 0.7, 9.0)
			for i in range(i1 + 2, mini(i1 + 16, n)):
				if c < extra[i] - 0.5:
					extra[i] = c
					lower = true
		if lower:
			continue
		var check := _next_check(ride.v, want, base, checks, air, landing, rng, xlim)
		if check.is_empty():
			break
		if not check.has("harder"):
			checks.append(check)
	# each cliff's air knows whether its take-off was technical
	for w in drops:
		var lz := float(w.z) - float(env.band_width(int(w.k), float(w.x))) * 0.5
		for ev in events:
			if absf(float(ev.p0.x) - float(w.x)) < 10.0 and float(ev.p0.z) > lz - 12.0 and float(ev.p0.z) < lz + 6.0:
				ev["technical"] = bool(w.tech)
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
	var v: PackedFloat32Array = ride.v
	var vmax := float(p.speed_max)
	for i in n:
		if not air.has(i):
			v[i] = clampf(v[i], 0.8, vmax)
	# the skid, signed: + when the skis turn towards +x (the side he is going to), - towards -x; the skis turn across
	# a little before the speed drops (3 m, about 0.2 s): the operator sees it coming. In the stop, skis right across.
	var side := _skid_side(pts, path.side)
	var sk: PackedFloat32Array = ride.skid
	var stop: PackedFloat32Array = base.stop
	var skid := PackedFloat32Array()
	skid.resize(n)
	for i in n:
		var s := maxf(maxf(sk[i], sk[mini(i + 1, n - 1)]), maxf(sk[mini(i + 2, n - 1)], sk[mini(i + 3, n - 1)]))
		skid[i] = maxf(s, 0.9 * stop[i]) * side[i]
	var cum := PathUtil.cumulative(pts)
	var count := maxi(200, int(cum[cum.size() - 1] / 1.5))
	return {"points": pts, "profile": PathUtil.profile_from_samples(v, cum, count),
			"skid": PathUtil.profile_from_samples(skid, cum, count), "events": events, "zone": Rect2()}


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
		var wp := {"z": nz, "x": nx, "kind": kind, "k": k}
		if kind == "drop":
			# how technical the take-off is: a lip running across the line at an angle, a big drop (and the rider's
			# own reading of it)
			var oblique := absf(float(env.band_z(k, nx + 3.0)) - float(env.band_z(k, nx - 3.0))) / 6.0
			var score := 0.45 * smoothstep(0.12, 0.5, oblique) + 0.35 * clampf((float(env.band_drop(k)) - 7.0) / 6.0, 0.0, 1.0) \
					+ 0.3 * rng.randf()
			wp["tech"] = score > 0.45
		wps.append(wp)
		x = nx
		z = nz
	var xf := clampf(x * 0.3 + rng.randf_range(-30.0, 30.0), -60.0, 60.0)
	wps.append({"z": z_fin, "x": xf, "kind": "finish", "k": -1})
	return wps


## The path on the ground before the check turns: a base line through the waypoints (straight down the fall line at
## each of them) with the turns of each stretch on top. Returns {z0, x, y (the ground), want (the speed of the
## stretch, or what the rider allows himself before a band, a cliff, in the stop), win (0..1, where he can skid: the
## end of each turn, a traverse, the stop), room (1 where he may throw a check turn)}.
func _line(ctx: ArchetypeContext, env, wps: Array, rng: RandomNumberGenerator, s0: Vector3, z_fin: float,
		xlim: float) -> Dictionary:
	var z_stop := z_fin + STOP_LENGTH
	var n := int((z_stop - s0.z) / DZ) + 1
	var face_end := float(env.get("face_end")) if env.get("face_end") != null else z_fin - 300.0
	# a style per stretch: [amplitude (m), wavelength (m), speed he wants on the steepest face (m/s), 0 for no turns or
	# the length of its turns relative to medium turns (the turns' own size then comes from the slope, see below)]
	var styles := []
	for j in wps.size() - 1:
		var r := rng.randf()
		var last := j == wps.size() - 2
		if r >= 0.43 and r < 0.6 and float(wps[j + 1].z) - float(wps[j].z) > 90.0:
			r = 0.1  # no long stretch of short turns: medium turns instead
		if j == 0 or (not last and r < 0.25):
			if j == 0:
				styles.append([rng.randf_range(1.0, 1.8), rng.randf_range(60.0, 80.0), 20.0, 0.0])  # a quick first stretch, nearly straight
			else:
				styles.append([rng.randf_range(4.0, 5.5), rng.randf_range(55.0, 65.0), 16.0, 1.0])   # medium turns
		elif last and r < 0.5 or (not last and r < 0.43):
			styles.append([rng.randf_range(0.5, 1.2), rng.randf_range(60.0, 80.0), 27.0, 0.0])  # straight-line
		elif not last and r < 0.6:
			styles.append([rng.randf_range(1.0, 1.4), rng.randf_range(16.0, 20.0), 11.0, 0.75])  # short turns
		else:
			styles.append([rng.randf_range(9.0, 12.0), rng.randf_range(100.0, 125.0), 21.0, 1.35])  # big turns
	var amp := PackedFloat32Array()
	var wl := PackedFloat32Array()
	var want := PackedFloat32Array()
	var base := PackedFloat32Array()
	var stop := PackedFloat32Array()
	var room := PackedByteArray()
	amp.resize(n)
	wl.resize(n)
	want.resize(n)
	base.resize(n)
	stop.resize(n)
	room.resize(n)
	var steep := PackedFloat32Array()
	steep.resize(n)
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
		# on a less steep stretch he carves his turns rather than skids them: they keep more speed (the face of the
		# reference run was steeper than most of this one)
		var grade := (float(env.fall_line(z - 6.0)) - float(env.fall_line(z + 6.0))) / 12.0 if env.has_method("fall_line") else 1.0
		steep[i] = smoothstep(0.8, 1.1, grade)
		if float(st[3]) > 0.0:
			c *= lerpf(1.3, 1.0, steep[i])
			# and the steeper, the shorter his turns (FPV runs): about 0.5-0.6 s each at 45 degrees (short, pivoted, skidded),
			# about 1 s at 35, 1.5-2 s on 25 (longer arcs); each about 25 degrees off the fall line at most
			var period := lerpf(1.6, 0.6, smoothstep(0.45, 1.1, grade)) * float(st[3]) * float(st[1]) / (60.0 if float(st[3]) == 1.0 else (18.0 if float(st[3]) < 1.0 else 112.0))
			l = 2.0 * maxf(period, 0.45) * c
			a = 0.45 * l / TAU
		var can_check := i >= 12 and z < z_fin - 10.0
		for w in wps:
			var dz := z - float(w.z)
			match str(w.kind):
				"drop":
					# straight at the cliff (the check turn above it is the last turn), then the ride-out; slow to a
					# technical take-off, with speed to an easy one
					var lip := -float(env.band_width(int(w.k), float(w.x))) * 0.5
					var tech := bool(w.tech)
					var lead := DROP_LEAD if tech else FAST_CHECK + 4.0
					a *= 1.0 - smoothstep(lip - lead - 12.0, lip - lead, dz) \
							* (1.0 - smoothstep(DROP_TAIL, DROP_TAIL + 14.0, dz))
					var check_at := LIP_CHECK if tech else FAST_CHECK
					if dz > lip - check_at - 4.0 and dz < lip:
						c = minf(c, 13.0 if tech else FAST_LIP)
					if dz > lip - check_at - 4.0 and dz < lip + 4.0:
						can_check = false
				"couloir", "roll":
					# the speed checked above a band crossed without dropping (the rider cannot see what is below)
					var half := float(env.band_width(int(w.k), float(w.x))) * 0.5
					if dz > -45.0 and dz < -half:
						c = minf(c, BLIND_SPEED)
					if str(w.kind) == "roll":
						continue
					# short turns down the couloir, no room for a check turn between its walls
					var hz := half + 6.0
					if absf(dz) < hz + 8.0:
						var k := 1.0 - smoothstep(hz, hz + 8.0, absf(dz))
						a = lerpf(a, 1.1, k)
						l = lerpf(l, 17.0, k)
						c = lerpf(c, 8.0, k)
						can_check = false
				"start":
					if dz < 18.0:
						a *= smoothstep(8.0, 18.0, dz)
		if z > z_fin - 80.0:
			a *= 1.0 - smoothstep(z_fin - 80.0, z_fin - 55.0, z)  # straight into the finish (the spectators line it)
		if z > z_fin:
			# the skid to a stop, curving to one side
			var f := (z - z_fin) / STOP_LENGTH
			base[i] += stop_side * 12.0 * f * f
			c = minf(c, maxf(sqrt(2.0 * STOP_BRAKE * maxf(z_stop - z, 0.0)) - 3.0, 0.0))
			stop[i] = smoothstep(0.0, 4.0, z - z_fin)
		if z < face_end:
			c = minf(c, FACE_STRAIGHT)
		amp[i] = a
		wl[i] = l
		want[i] = c
		room[i] = 1 if can_check else 0
	amp = _box(amp, 8)
	wl = _box(wl, 8)
	var xs := PackedFloat32Array()
	var ys := PackedFloat32Array()
	var win := PackedFloat32Array()
	xs.resize(n)
	ys.resize(n)
	win.resize(n)
	var phase := rng.randf() * TAU
	for i in n:
		phase += TAU * DZ / maxf(wl[i], 4.0)
		var z := s0.z + i * DZ
		xs[i] = clampf(base[i] + amp[i] * sin(phase), -xlim, xlim)
		ys[i] = ctx.ground(xs[i], z)
		# where he can skid: the end of each turn (as the skis come across the slope, before the next turn; the more
		# of a turn, the more), a traverse across the slope, the stop
		var turn := smoothstep(0.12, 0.3, amp[i] * TAU / maxf(wl[i], 4.0)) * smoothstep(0.45, 0.92, absf(cos(phase + 0.35))) \
				* lerpf(0.6, 1.0, steep[i])
		var slope := absf(base[mini(i + 1, n - 1)] - base[maxi(i - 1, 0)]) * 0.5 / DZ
		win[i] = maxf(maxf(turn, 0.6 * smoothstep(0.35, 0.8, slope)), stop[i])
	return {"z0": s0.z, "x": xs, "y": ys, "want": want, "win": win, "room": room, "stop": stop}


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


# --- Check turns -----------------------------------------------------------------------------------

## A check turn from point i0, `length` points long: the rider swings out to `side` (amp m) and back, skidding
## hard (skis across) down to v_out until `hold` of it.
static func _check(i0: int, length: int, side: float, v_out: float, hold := 0.6) -> Dictionary:
	return {"i0": i0, "len": length, "side": side, "amp": clampf(0.2 * length, 2.8, 5.0), "v_out": v_out, "hold": hold}


## The side of a check turn around point i of the line xs: further across the way he is going (on a traverse),
## towards the middle of the face near its edges, else either side.
static func _side(rng: RandomNumberGenerator, xs: PackedFloat32Array, i: int, xlim: float) -> float:
	var r := rng.randf()
	var x := xs[i]
	if x > xlim - 12.0:
		return -1.0
	if x < -xlim + 12.0:
		return 1.0
	var slope := (xs[mini(i + 3, xs.size() - 1)] - xs[maxi(i - 3, 0)]) / 6.0
	if absf(slope) > 0.15:
		return signf(slope)
	return -1.0 if r < 0.5 else 1.0


## The ground path with the check turns on it, the windows where he can skid (`win`: his turns, the checks, the
## stop), the speed each check takes him down to (`cap`), where the checks are (`in_check`) and the side of each
## check's skid (`side`, 0 elsewhere).
func _with_checks(ctx: ArchetypeContext, base: Dictionary, checks: Array, xlim: float) -> Dictionary:
	var xs: PackedFloat32Array = base.x
	var ys: PackedFloat32Array = base.y
	var n := xs.size()
	var off := PackedFloat32Array()
	var cap := PackedFloat32Array()
	var side := PackedFloat32Array()
	var in_check := PackedByteArray()
	off.resize(n)
	cap.resize(n)
	cap.fill(INF)
	side.resize(n)
	in_check.resize(n)
	var win: PackedFloat32Array = (base.win as PackedFloat32Array).duplicate()
	for c in checks:
		var length := int(c.len)
		var hold := float(c.hold)
		for k in length + 1:
			var i := int(c.i0) + k
			if i >= n:
				break
			var u := float(k) / length
			var s := sin(PI * u)
			off[i] += float(c.side) * float(c.amp) * s * s
			var w := smoothstep(0.0, 0.12, u) * (1.0 - smoothstep(hold - 0.1, hold + 0.12, u))
			win[i] = maxf(win[i], w)
			if w > 0.0:
				side[i] = float(c.side)
			if u > 0.04 and u < hold:
				cap[i] = minf(cap[i], float(c.v_out))
			in_check[i] = 1
	var pts := PackedVector3Array()
	pts.resize(n)
	for i in n:
		var z := float(base.z0) + i * DZ
		if off[i] == 0.0:
			pts[i] = Vector3(xs[i], ys[i], z)
		else:
			var x := clampf(xs[i] + off[i], -xlim, xlim)
			pts[i] = Vector3(x, ctx.ground(x, z), z)
	return {"pts": pts, "win": win, "cap": cap, "in_check": in_check, "side": side}


## The first place where the rider goes clearly faster than he wants (CHECK_TOL) where he may throw a check turn
## (not on a cliff's approach, in a couloir, in the air or just after a landing, nor on another check): a check turn
## there, down to CHECK_SCRUB of his speed or the speed he wants after it. Empty when there is none.
func _next_check(v: PackedFloat32Array, want: PackedFloat32Array, base: Dictionary, checks: Array, air: Dictionary,
		landing: Dictionary, rng: RandomNumberGenerator, xlim: float) -> Dictionary:
	var n := v.size()
	var busy: PackedByteArray = (base.room as PackedByteArray).duplicate()   # 1: free
	for c in checks:
		for i in range(maxi(int(c.i0) - 4, 0), mini(int(c.i0) + int(c.len) + 8, n)):
			busy[i] = 0
	for i0 in landing:
		for i in range(int(i0), mini(int(i0) + 2, n)):
			busy[i] = 0
	for i in air:
		busy[int(i)] = 0
	var run := PackedInt32Array()   # free points in a row from each one on
	run.resize(n)
	for i in range(n - 1, -1, -1):
		run[i] = 0 if busy[i] == 0 else (1 if i == n - 1 else run[i + 1] + 1)
	for i in range(12, n - 2):
		if busy[i] == 0 or v[i] <= want[i] + CHECK_TOL:
			continue
		# there, or a little earlier when what comes next leaves no room for it (a cliff's approach, a couloir, an air)
		var length := int(clampf(v[i], 14.0, 26.0) / DZ)
		var at := _room_before(run, i, 50, length)
		if at < 0:
			# no room for one: he checks harder in his last check turn before, if it is not too far back, else he
			# throws one further back
			var last = null
			for c in checks:
				if int(c.i0) + int(c.len) <= i and (last == null or int(c.i0) > int(last.i0)):
					last = c
			if last != null and i - int(last.i0) - int(last.len) < 60 and float(last.v_out) > 8.5:
				last.v_out = maxf(float(last.v_out) - 1.5, 8.0)
				return {"harder": true}
			at = _room_before(run, i, 130, length)
		if at >= 0:
			var v_out := maxf(minf(v[at + 2] * CHECK_SCRUB, want[at + int(length * 0.6)]), 6.0)
			return _check(at, length, _side(rng, base.x, at + (length >> 1), xlim), v_out)
	return {}


## The latest start of a check turn `length` long in the free points, from point i - 2 back `back` points; -1 if none.
static func _room_before(run: PackedInt32Array, i: int, back: int, length: int) -> int:
	for i0 in range(i - 2, maxi(i - back, 12) - 1, -1):
		if run[i0] > length:
			return i0
	return -1


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
		if i1 < 0 or d > (MAX_AIR if pop < 0.0 else MAX_DROP_AIR):
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
				"ramp_i": i, "ramp_h": 0.0, "length": d, "air_time": t, "drop": pop > 0.0})
		i = i1 + 6
	return events


# --- Speed ---------------------------------------------------------------------------------------

## The speed the rider wants at each point: the speed of his stretch (or what he allows himself before a band, a
## cliff, an air he did not choose, in the stop), never faster than he can carve the curve (a check turn is his own
## skid: its curve does not count), slowing down early enough (D_PLAN) for what comes (not across an air: a landing
## is not chosen), and the speed each check turn takes him down to.
func _plan_speed(pts: PackedVector3Array, base_want: PackedFloat32Array, extra: PackedFloat32Array, path: Dictionary,
		kappa: PackedFloat32Array, air: Dictionary, landing: Dictionary, p: Dictionary) -> PackedFloat32Array:
	var n := pts.size()
	var a_carve := float(p.cornering_accel)
	var vmax := float(p.speed_max)
	var in_check: PackedByteArray = path.in_check
	var cap: PackedFloat32Array = path.cap
	var w := PackedFloat32Array()
	w.resize(n)
	for i in n:
		var c := minf(minf(base_want[i], extra[i]), vmax)
		if in_check[i] == 0:
			c = minf(c, sqrt(a_carve / maxf(kappa[i], 0.0001)))
		w[i] = c
	for i in range(n - 2, -1, -1):
		if air.has(i + 1) or landing.has(i + 1):
			continue
		w[i] = minf(w[i], sqrt(w[i + 1] * w[i + 1] + 2.0 * D_PLAN * pts[i + 1].distance_to(pts[i])))
	for i in n:
		w[i] = minf(w[i], cap[i])
	return w


## The ride along `pts`: gravity, friction in the powder (not in the air) and air drag act all the time; at each
## landing only the share of the speed in `landing` is kept. The rider loses speed only by skidding: where he can
## (`win`: the end of his turns, a check turn, a traverse, the stop) when he goes faster than he wants (`want`; the
## further over it, the harder), and wherever he is too fast for the curve (he cannot hold it on his edges: he
## slides). Returns {v, skid (0..1: share of the hardest skid)}.
func _ride(pts: PackedVector3Array, want: PackedFloat32Array, path: Dictionary, kappa: PackedFloat32Array,
		air: Dictionary, landing: Dictionary, p: Dictionary) -> Dictionary:
	var n := pts.size()
	var mu := float(p.get("snow_friction", 0.07))
	var drag := float(p.get("air_drag", 0.0035))
	var a_carve := float(p.cornering_accel)
	var win: PackedFloat32Array = path.win
	var in_check: PackedByteArray = path.in_check
	var v := PackedFloat32Array()
	var skid := PackedFloat32Array()
	v.resize(n)
	skid.resize(n)
	v[0] = START_SPEED
	for i in range(1, n):
		var ds := maxf(pts[i].distance_to(pts[i - 1]), 0.001)
		var v2 := v[i - 1] * v[i - 1] * (1.0 - 2.0 * drag * ds) + 2.0 * GRAVITY * (pts[i - 1].y - pts[i].y)
		if air.has(i):
			v[i] = sqrt(maxf(v2, 0.04))
			continue
		var cos_b := Vector2(pts[i].x - pts[i - 1].x, pts[i].z - pts[i - 1].z).length() / ds
		v2 -= 2.0 * mu * GRAVITY * cos_b * ds
		var vi := sqrt(maxf(v2, 0.04))
		if landing.has(i):
			vi *= float(landing[i])
		var b := 0.0
		if vi > want[i]:
			b = minf(D_SKID * win[i] * smoothstep(0.0, SKID_RANGE, vi - want[i]), (vi * vi - want[i] * want[i]) / (2.0 * ds))
		# (in a check turn he doses the skid himself: its tight swing does not force more)
		var vc := sqrt(a_carve / maxf(kappa[i], 0.0001))
		if vi > vc and in_check[i] == 0:
			b = maxf(b, minf(D_SKID * smoothstep(0.0, SKID_RANGE, vi - vc), (vi * vi - vc * vc) / (2.0 * ds)))
		v[i] = sqrt(maxf(vi * vi - 2.0 * b * ds, 0.04))
		skid[i] = b / D_SKID
	return {"v": v, "skid": skid}


## The side the skis turn to in a skid at each point (+1 towards +x, -1 towards -x): the side of the check turn,
## else further across the way he is going, else (going straight down) the way the curve turns.
static func _skid_side(pts: PackedVector3Array, check_side: PackedFloat32Array) -> PackedFloat32Array:
	var n := pts.size()
	var out := PackedFloat32Array()
	out.resize(n)
	var last := 1.0
	for i in n:
		var a := pts[maxi(i - 1, 0)]
		var b := pts[mini(i + 1, n - 1)]
		var dxdz := (b.x - a.x) / maxf(b.z - a.z, 0.001)
		var bend := b.x - 2.0 * pts[i].x + a.x
		if check_side[i] != 0.0:
			last = check_side[i]
		elif absf(dxdz) > 0.1:
			last = signf(dxdz)
		elif absf(bend) > 0.002:
			last = signf(bend)
		out[i] = last
	return out


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
## landing. When he skids (the "skid" of the plan) his skis turn across the way he goes and he sinks into it,
## throwing a cloud of snow downhill: what tells the operator he is slowing down. A cloud of powder at each landing.
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
	var sk := lerpf(float(s.state.get("skid", 0.0)), 0.0 if in_air else _skid_at(s), 1.0 - exp(-delta / 0.1))
	s.state["skid"] = sk
	if not in_air:
		s.model.rotation.y = sk * SKID_YAW
	if s.state.has("spray"):
		var spray: GPUParticles3D = s.state["spray"]
		spray.emitting = absf(sk) > 0.12 and s.speed_now > 3.0 and not in_air
		if spray.emitting:
			spray.amount_ratio = 0.15 + 0.5 * absf(sk)
			spray.position = Vector3(0.0, 0.2, 0.6 - 0.5 * absf(sk))
			# downhill (+z), a little the way the skis turn
			var dir := spray.global_transform.basis.inverse() * Vector3(signf(sk) * 0.35, 0.9, 1.0)
			(spray.process_material as ParticleProcessMaterial).direction = dir.normalized()
	if not s.parts.has("athlete"):
		return
	# as in the FPV runs: low at the apex of a turn, up tall (skis flat) through the edge change, low in a skid
	var lean := absf(s.lean_deg)
	var target := 0.08 + 0.2 * smoothstep(14.0, 26.0, s.speed_now) + 0.3 * smoothstep(10.0, 38.0, lean) + 0.3 * absf(sk)
	if in_air:
		var ev := s.current_jump()
		target = 1.0 if (ev.has("flips") or ev.has("spin_deg")) else 0.35  # tucked for a figure
	target = maxf(target, 0.95 * (1.0 - smoothstep(0.08, 0.5, since)))
	var a: AthleteModel = s.parts["athlete"]
	a.tuck = lerpf(a.tuck, target, 1.0 - exp(-delta / 0.08))
	# pole plant: as a turn ends (the lean going back through 10 degrees), the pole on the side of the next turn
	# touches the snow, 0.1-0.2 s before the edge change; it stays planted a moment, then swings back
	var peak := maxf(float(s.state.get("lean_peak", 0.0)) * exp(-delta / 1.5), lean)
	var planted := float(s.state.get("plant", 0.0))
	if peak > 16.0 and lean < 10.0 and not in_air and float(s.state.get("prev_lean", 0.0)) >= 10.0:
		planted = signf(s.lean_deg) if absf(s.lean_deg) > 0.5 else signf(float(s.state.get("lean_sign", 1.0)))
		s.state["plant_t"] = 0.0
		peak = 0.0
	var pt := float(s.state.get("plant_t", 9.0)) + delta
	s.state["plant_t"] = pt
	s.state["lean_peak"] = peak
	s.state["prev_lean"] = lean
	if absf(s.lean_deg) > 3.0:
		s.state["lean_sign"] = signf(s.lean_deg)
	s.state["plant"] = planted
	a.plant = signf(planted) * smoothstep(0.0, 0.08, pt) * (1.0 - smoothstep(0.25, 0.5, pt)) if planted != 0.0 else 0.0


## The skid of the plan where the rider is (signed: + skis turned towards +x).
static func _skid_at(s: ArchetypeSubject) -> float:
	if not s.plan.has("skid"):
		return 0.0
	var prof: PackedFloat32Array = s.plan["skid"]
	if prof.size() < 2:
		return 0.0
	var f := clampf(s.progress_ratio, 0.0, 1.0) * (prof.size() - 1)
	var i := mini(int(f), prof.size() - 2)
	return lerpf(prof[i], prof[i + 1], f - i)


## Powder: a spray in each skid (see animate) and a one-shot cloud at each landing.
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
	pm.inherit_velocity_ratio = 0.45   # the snow thrown by a skid goes on with the rider, then hangs
	pm.damping_min = 3.0
	pm.damping_max = 4.5
	pm.scale_min = 0.7
	pm.scale_max = 1.4
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

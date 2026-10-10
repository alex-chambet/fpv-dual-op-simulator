class_name ArchetypeDescente
extends ArchetypeGlissePente
## DESCENTE: a downhill race (Streif, Bellevarde...): a long and fast course down the mountain, made of wide
## sweeping turns, tight turns (often two in a row, in an S), straight schusses, and jumps where the slope breaks
## (a flat stretch ending on a steep wall: the skier takes off on the crest and lands on the steep part).
## The speed comes from a small physical model along the path: gravity on the slope, snow friction, air drag, a
## limit of lateral acceleration in the turns (with braking before the tight ones) and a ballistic flight in the air.
## So the skier accelerates on the steep parts, slows down on the flats and before tight turns, and flies far over
## the crests. Gates, nets and the piste itself come from the environment ("descente").

const STEP := 2.0             # m between path points
const MAX_HEADING := 0.95     # rad (54 deg): the course never runs more across the slope than this
const X_LIMIT := 170.0        # m: the course stays within this distance of the axis of the mountain
const BRAKE := 6.5            # m/s², braking (skidding) before a tight turn
const START_SPEED := 7.0      # m/s, after the push out of the start house
const GRAVITY := 9.81
const FINISH_STRAIGHT := 170.0  # m of straight schuss into the finish


func id() -> String:
	return "DESCENTE"


func summary() -> String:
	return "Downhill race: long fast course, sweeping and tight turns, schusses, jumps on the crests."


func defaults() -> Dictionary:
	var d := super.defaults()
	d.merge({
		"subject_size": 1.8,
		"speed_min": 14.0, "speed_max": 34.0, "speed_variability": 0.04,
		"cornering_accel": 12.0,
		"lean_max_deg": 55.0, "lean_gain": 0.9,
		"sample_step": STEP,
		"duration": 98.0,
		"gates": false, "leaves_tracks": true, "spray": true,
		"jump_visual": "none", "jump_height": 1.2,
		"turn_frequency": 0.55, "tight_turns": 0.4, "air_drag": 0.0042, "snow_friction": 0.035,
	}, true)
	return d


# --- Course ------------------------------------------------------------------------------------

func generate(ctx: ArchetypeContext) -> Dictionary:
	var p := ctx.params
	var length := path_length(p)
	var crests := find_crests(ctx, -50.0, length + 400.0)
	var course := _course(ctx, length, crests)
	var pts: PackedVector3Array = course.points
	var kappa: PackedFloat32Array = course.kappa
	var speeds := _speeds(pts, kappa, p, {})
	var events := _jumps(ctx, pts, kappa, speeds, crests)
	var air := {}
	for ev in events:
		for i in range(int(ev.i0) + 1, int(ev.i1)):
			air[i] = true
	speeds = _speeds(pts, kappa, p, air)
	return finish_plan(pts, speeds, events)


## z of the crests of the slope (a flat stretch ending on a much steeper one), seen along the fall line at x = 0.
static func find_crests(ctx: ArchetypeContext, z0: float, z1: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var best_z := 0.0
	var best := 0.0
	var z := z0
	while z < z1:
		var before := (ctx.ground(0.0, z - 8.0) - ctx.ground(0.0, z)) / 8.0
		var after := (ctx.ground(0.0, z) - ctx.ground(0.0, z + 8.0)) / 8.0
		var jump := after - before
		if jump > 0.16:
			if jump > best:
				best = jump
				best_z = z
		elif best > 0.0:
			out.append(best_z)
			best = 0.0
		z += 1.0
	return out


## The racing line: a sequence of straights and turns (curvature ramps up and down over a few tens of metres, so the
## heading never changes abruptly), straight across every crest and into the finish.
## Returns {points (y = ground), kappa (signed curvature at each point)}.
func _course(ctx: ArchetypeContext, length: float, crests: PackedFloat32Array) -> Dictionary:
	var rng := ctx.rng
	var p := ctx.params
	var st := {"x": 0.0, "z": 0.0, "th": 0.0, "s": 0.0,
			"pts": PackedVector3Array([Vector3(0.0, ctx.ground(0.0, 0.0), 0.0)]), "k": PackedFloat32Array([0.0])}
	_straight(st, ctx, 60.0)
	var tight_share := float(p.get("tight_turns", 0.4))
	var straight_share := clampf(1.0 - float(p.turn_frequency) * 1.3, 0.1, 0.5)
	var last_dir := 1.0 if rng.randf() < 0.5 else -1.0
	var guard := 0
	while float(st.s) < length - FINISH_STRAIGHT and guard < 5000:
		guard += 1
		var th: float = st.th
		var x: float = st.x
		var z: float = st.z
		# a crest close ahead: straighten up and run straight over it and its landing
		var crest := -1.0
		for c in crests:
			if c > z + 4.0:
				crest = c
				break
		# next element, and how far down it goes
		var kind := "straight"
		var r := rng.randf()
		if r > straight_share:
			kind = "tight" if rng.randf() < tight_share else "sweep"
		var dir := -signf(th) if absf(th) > 0.2 else -last_dir
		var far_out := absf(x) > X_LIMIT - 50.0
		if far_out:
			dir = -signf(x)
		# no long straight across the slope (the course would drift sideways): a sweep back towards the fall line
		if kind == "straight" and (absf(th) > 0.45 or (far_out and signf(th) == signf(x))):
			kind = "sweep"
			dir = -signf(th) if not far_out else -signf(x)
		var angle := rng.randf_range(0.5, 0.85) if kind == "sweep" else rng.randf_range(0.8, 1.25)
		var radius := rng.randf_range(110.0, 190.0) if kind == "sweep" else rng.randf_range(34.0, 52.0)
		var target := clampf(th + dir * angle, -MAX_HEADING, MAX_HEADING)
		if kind != "straight" and absf(target - th) < 0.05:
			kind = "straight"  # already turned as far as this turn would go (heading at its limit): go on straight
		var est := 70.0 if kind == "straight" else absf(target - th) * radius + 50.0
		if crest > 0.0 and crest - z < est + 60.0:
			# ease the heading towards the fall line (or back towards the axis when far out) if there is room, then
			# straight over the crest
			if far_out and crest - z > 110.0:
				_turn(st, ctx, -signf(x) * 0.25, 170.0)
			elif absf(th) > 0.3 and crest - z > 110.0:
				_turn(st, ctx, signf(th) * 0.2, 170.0)
			var over := (crest - float(st.z)) / maxf(cos(float(st.th)), 0.5) + 110.0
			_straight(st, ctx, maxf(over, 20.0))
			continue
		match kind:
			"straight":
				_straight(st, ctx, rng.randf_range(50.0, 120.0))
			"sweep":
				_turn(st, ctx, target, radius)
			_:
				_turn(st, ctx, target, radius)
				# often a second tight turn the other way, straight after the first one (an S)
				if rng.randf() < 0.55 and float(st.s) < length - FINISH_STRAIGHT - 80.0:
					var back := clampf(float(st.th) - dir * rng.randf_range(0.9, 1.3), -MAX_HEADING, MAX_HEADING)
					_turn(st, ctx, back, rng.randf_range(34.0, 52.0))
		last_dir = dir
	# into the finish: back towards the fall line, then straight
	if absf(float(st.th)) > 0.15:
		_turn(st, ctx, 0.0, 150.0)
	_straight(st, ctx, maxf(length - float(st.s), 40.0))
	return {"points": st.pts, "kappa": st.k}


func _straight(st: Dictionary, ctx: ArchetypeContext, dist: float) -> void:
	var n := maxi(1, roundi(dist / STEP))
	for _i in n:
		_advance(st, ctx, 0.0)


## Turn to the heading `target` (rad) with a smallest radius `radius`: the curvature ramps up over T metres, holds,
## and ramps down over T metres (transition curves).
func _turn(st: Dictionary, ctx: ArchetypeContext, target: float, radius: float) -> void:
	var delta := target - float(st.th)
	if absf(delta) < 0.02:
		return
	var kmax := 1.0 / radius
	var ramp := clampf(0.35 * radius, 12.0, 34.0)
	var hold := (absf(delta) - kmax * ramp) / kmax
	if hold < 0.0:
		kmax = absf(delta) / ramp
		hold = 0.0
	var total := 2.0 * ramp + hold
	var n := maxi(2, roundi(total / STEP))
	var sgn := signf(delta)
	for i in n:
		var s := (i + 0.5) * total / n
		var k := kmax
		if s < ramp:
			k = kmax * s / ramp
		elif s > ramp + hold:
			k = kmax * (total - s) / ramp
		_advance(st, ctx, sgn * k * total / n / STEP)
	# exact final heading (rounding of the steps)
	st.th = target


func _advance(st: Dictionary, ctx: ArchetypeContext, k: float) -> void:
	var th: float = float(st.th) + k * STEP
	th = clampf(th, -MAX_HEADING - 0.05, MAX_HEADING + 0.05)
	var mid: float = (float(st.th) + th) * 0.5
	st.x = float(st.x) + sin(mid) * STEP
	st.z = float(st.z) + cos(mid) * STEP
	st.th = th
	st.s = float(st.s) + STEP
	var pts: PackedVector3Array = st.pts
	pts.append(Vector3(st.x, ctx.ground(st.x, st.z), st.z))
	st.pts = pts
	var ks: PackedFloat32Array = st.k
	ks.append(k)
	st.k = ks


# --- Jumps -------------------------------------------------------------------------------------

## A jump on every crest the course crosses: the skier takes off on the crest with the speed it has there (and a
## small pop), flies a ballistic arc and lands where the arc meets the slope again.
func _jumps(ctx: ArchetypeContext, pts: PackedVector3Array, kappa: PackedFloat32Array, speeds: PackedFloat32Array,
		crests: PackedFloat32Array) -> Array:
	var events: Array = []
	var pop := float(ctx.params.get("jump_height", 1.2))
	var n := pts.size()
	var last_end := 0
	for c in crests:
		var i0 := -1
		for i in range(maxi(last_end, 4), n - 6):
			if pts[i].z >= c:
				i0 = i
				break
		if i0 < 0:
			continue
		var straight := true
		for i in range(maxi(i0 - 5, 0), mini(i0 + 15, n)):
			if absf(kappa[i]) > 1.0 / 400.0:
				straight = false
		if not straight:
			continue
		var a := pts[i0 - 3]
		var b := pts[i0]
		var run := Vector2(b.x - a.x, b.z - a.z).length()
		var angle := atan2(b.y - a.y, run)  # negative: going down
		var v := speeds[i0]
		var vh := v * cos(angle)
		var vy := v * sin(angle) + pop
		var d := 0.0
		var i1 := -1
		var flight := PackedFloat32Array()
		for k in range(i0 + 1, n):
			d += Vector2(pts[k].x - pts[k - 1].x, pts[k].z - pts[k - 1].z).length()
			var t := d / maxf(vh, 1.0)
			var y := b.y + vy * t - 0.5 * GRAVITY * t * t
			if y <= pts[k].y or d > 90.0:
				i1 = k
				break
			flight.append(y)
		if i1 < 0 or d < 8.0:
			continue
		var peak := 0.0
		for k in range(i0 + 1, i1):
			var y := flight[k - i0 - 1]
			peak = maxf(peak, y - pts[k].y)
			pts[k] = Vector3(pts[k].x, y, pts[k].z)
		events.append({"type": "jump", "i0": i0, "i1": i1, "p0": pts[i0], "p1": pts[i1], "height": peak,
				"ramp_i": i0, "ramp_h": 0.0, "length": d})
		last_end = i1 + 10
	return events


# --- Speed -------------------------------------------------------------------------------------

## Speed at each point: v² grows with the drop (gravity) and shrinks with snow friction and air drag; in a turn the
## lateral acceleration is limited (the skier brakes before a tight turn, BRAKE m/s²); in the air only the drop and
## the drag count. Clamped to [speed_min, speed_max] (the first seconds after the start excepted).
func _speeds(pts: PackedVector3Array, kappa: PackedFloat32Array, p: Dictionary, air: Dictionary) -> PackedFloat32Array:
	var n := pts.size()
	var vmax := float(p.speed_max)
	var vmin := float(p.speed_min)
	var drag := float(p.get("air_drag", 0.0042))
	var mu := float(p.get("snow_friction", 0.035))
	var a_lat := maxf(float(p.cornering_accel), 1.0)
	# turn limit, smoothed a little along the path (the curvature of the points is noisy at the joints)
	var lim := PackedFloat32Array()
	lim.resize(n)
	for i in n:
		var k := 0.0
		for j in range(maxi(i - 3, 0), mini(i + 4, n)):
			k = maxf(k, absf(kappa[j]))
		lim[i] = minf(vmax, sqrt(a_lat / maxf(k, 0.00001)))
	var v := PackedFloat32Array()
	v.resize(n)
	v[0] = START_SPEED
	for i in range(1, n):
		var ds := pts[i].distance_to(pts[i - 1])
		var drop := pts[i - 1].y - pts[i].y
		var flat := maxf(Vector2(pts[i].x - pts[i - 1].x, pts[i].z - pts[i - 1].z).length(), 0.001)
		var cos_b := flat / maxf(ds, 0.001)
		var v2 := v[i - 1] * v[i - 1] + 2.0 * GRAVITY * drop
		if not air.has(i):
			v2 -= 2.0 * mu * GRAVITY * cos_b * ds
		v2 -= 2.0 * drag * v[i - 1] * v[i - 1] * ds
		v[i] = minf(sqrt(maxf(v2, 1.0)), lim[i])
	# braking before the turns: never faster than what lets the skier slow down in time
	for i in range(n - 2, -1, -1):
		var ds := pts[i + 1].distance_to(pts[i])
		v[i] = minf(v[i], sqrt(v[i + 1] * v[i + 1] + 2.0 * BRAKE * ds))
	for i in n:
		v[i] = clampf(v[i], START_SPEED if pts[i].z < 60.0 else vmin, vmax)
	return v


# --- Runtime -----------------------------------------------------------------------------------

## The skier crouches in a tuck in the fast straights and in the air, and stands up in the turns.
func animate(s: ArchetypeSubject, delta: float) -> void:
	super.animate(s, delta)
	var fast := smoothstep(22.0, 30.0, s.speed_now)
	var turning := smoothstep(10.0, 28.0, absf(s.lean_deg))
	var target := maxf(fast * (1.0 - turning), 1.0 if not s.current_jump().is_empty() else 0.0)
	var tuck := float(s.state.get("tuck", 0.0))
	tuck = lerpf(tuck, target, 1.0 - exp(-delta / 0.35))
	s.state["tuck"] = tuck
	var body: Node3D = s.parts["body"]
	body.scale = Vector3(1.0, 1.0 - 0.3 * tuck, 1.0)
	var arms: Array = s.parts["arms"]
	for arm in arms:
		arm.rotation.x = -1.2 * tuck

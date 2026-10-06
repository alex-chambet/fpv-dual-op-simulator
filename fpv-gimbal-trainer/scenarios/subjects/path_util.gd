class_name PathUtil
extends RefCounted
## Geometry helpers shared by archetypes, environments and scenarios.
## Conventions: a subject path is a PackedVector3Array of points (x, y, z); the main direction of
## travel is +Z; lengths are metres.


static func cumulative(pts: PackedVector3Array) -> PackedFloat32Array:
	var cum := PackedFloat32Array()
	cum.append(0.0)
	for i in range(1, pts.size()):
		cum.append(cum[i - 1] + pts[i].distance_to(pts[i - 1]))
	return cum


static func total_length(pts: PackedVector3Array) -> float:
	var l := 0.0
	for i in range(1, pts.size()):
		l += pts[i].distance_to(pts[i - 1])
	return l


## Fractional sample index at which the cumulative length equals s.
static func index_at(cum: PackedFloat32Array, s: float) -> float:
	var i := clampi(cum.bsearch(s) - 1, 0, cum.size() - 2)
	return i + clampf((s - cum[i]) / maxf(cum[i + 1] - cum[i], 0.0001), 0.0, 1.0)


## Point on a polyline at arc length s (extrapolated along the first segment when s < 0).
static func polyline_at(pts: PackedVector3Array, cum: PackedFloat32Array, s: float) -> Vector3:
	if s <= 0.0:
		return pts[0] + (pts[1] - pts[0]).normalized() * s
	var f := index_at(cum, s)
	var i := mini(int(f), pts.size() - 2)
	return pts[i].lerp(pts[i + 1], f - i)


## Resamples per-point values to `count` samples uniform in arc length (for PathSubject.speed_profile).
static func profile_from_samples(values: PackedFloat32Array, cum: PackedFloat32Array,
		count := 200) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for j in count:
		var f := index_at(cum, cum[cum.size() - 1] * j / float(count - 1))
		var i := mini(int(f), values.size() - 2)
		out.append(lerpf(values[i], values[i + 1], f - i))
	return out


## Curvature (1/m) at each point of a polyline, lightly smoothed.
static func curvature(pts: PackedVector3Array, smooth_passes := 3) -> PackedFloat32Array:
	var k := PackedFloat32Array()
	k.resize(pts.size())
	for i in range(1, pts.size() - 1):
		var a := pts[i] - pts[i - 1]
		var b := pts[i + 1] - pts[i]
		a.y = 0.0
		b.y = 0.0
		var seg := (a.length() + b.length()) * 0.5
		k[i] = absf(a.angle_to(b)) / maxf(seg, 0.001)
	for _p in smooth_passes:
		var s := k.duplicate()
		for i in range(1, k.size() - 1):
			s[i] = (k[i - 1] + 2.0 * k[i] + k[i + 1]) * 0.25
		k = s
	return k


## Per-point speed that brakes in bends: sqrt(accel / curvature), clamped to [vmin, vmax].
static func speeds_from_curvature(pts: PackedVector3Array, accel: float, vmin: float,
		vmax: float) -> PackedFloat32Array:
	var v := PackedFloat32Array()
	for k in curvature(pts):
		v.append(clampf(sqrt(accel / maxf(k, 0.0005)), vmin, vmax))
	return v


## x of a path that advances along +Z (linear interpolation between samples).
static func x_at_z(pts: PackedVector3Array, z: float) -> float:
	if pts.size() < 2:
		return 0.0
	if z <= pts[0].z:
		return pts[0].x
	for i in range(1, pts.size()):
		if pts[i].z >= z:
			var t := (z - pts[i - 1].z) / maxf(pts[i].z - pts[i - 1].z, 0.0001)
			return lerpf(pts[i - 1].x, pts[i].x, t)
	return pts[pts.size() - 1].x


static func bounds_xz(pts: PackedVector3Array) -> Rect2:
	if pts.is_empty():
		return Rect2()
	var lo := Vector2(pts[0].x, pts[0].z)
	var hi := lo
	for p in pts:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.z))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.z))
	return Rect2(lo, hi - lo)


# --- 2D polylines (plan view, x/z as Vector2) ---------------------------------------------

## Points every `step` metres along a 2D polyline.
static func resample_2d(poly: PackedVector2Array, step: float) -> PackedVector2Array:
	if poly.size() < 2:
		return poly
	var out := PackedVector2Array()
	out.append(poly[0])
	var carry := 0.0
	var prev := poly[0]
	for i in range(1, poly.size()):
		var seg := poly[i] - prev
		var seg_len := seg.length()
		if seg_len < 0.0001:
			continue
		var dir := seg / seg_len
		var next_at := step - carry
		while next_at <= seg_len:
			out.append(prev + dir * next_at)
			next_at += step
		carry = seg_len - (next_at - step)
		prev = poly[i]
	if out[out.size() - 1].distance_to(poly[poly.size() - 1]) > step * 0.3:
		out.append(poly[poly.size() - 1])
	return out


## Polyline through waypoints with rounded corners (quadratic curves), resampled every `step`.
static func fillet(wps: PackedVector2Array, radius: float, step: float) -> PackedVector2Array:
	var n := wps.size()
	if n < 3:
		return resample_2d(wps, step)
	var poly := PackedVector2Array()
	poly.append(wps[0])
	for i in range(1, n - 1):
		var p := wps[i]
		var din := p - wps[i - 1]
		var dout := wps[i + 1] - p
		var lin := din.length()
		var lout := dout.length()
		if lin < 0.001 or lout < 0.001:
			continue
		var u := din / lin
		var v := dout / lout
		# The half angle is capped (a U-turn would give tan(90 deg) = infinity)
		var t := radius * tan(minf(absf(u.angle_to(v)) * 0.5, 1.45))
		t = clampf(t, 0.0, 0.45 * minf(lin, lout))
		var a := p - u * t
		var b := p + v * t
		poly.append(a)
		var m := maxi(4, int(ceil(t * 2.0 / maxf(step, 0.5))))
		for k in range(1, m):
			var s := k / float(m)
			poly.append(a * ((1.0 - s) * (1.0 - s)) + p * (2.0 * s * (1.0 - s)) + b * (s * s))
		poly.append(b)
	poly.append(wps[n - 1])
	return resample_2d(poly, step)


## Lifts a plan-view polyline to 3D with y = height(x, z).
static func lift(poly: PackedVector2Array, height: Callable) -> PackedVector3Array:
	var out := PackedVector3Array()
	for p in poly:
		out.append(Vector3(p.x, float(height.call(p.x, p.y)), p.y))
	return out


# --- Jumps ---------------------------------------------------------------------------------

## Turns the section [i0, i1] of a (dense) path into a ballistic arc: a straight chord from the
## take-off point to the landing point plus a parabola of the given height. A small kicker ramp
## (ramp_n points long, rising by ramp_h) is added just before the take-off point.
## Returns the jump event {type, i0, i1, p0, p1, height, ramp_i, ramp_h}.
static func apply_jump(pts: PackedVector3Array, ground: Callable, i0: int, i1: int, height: float,
		ramp_n: int, ramp_h: float) -> Dictionary:
	var n := pts.size()
	i0 = clampi(i0, 1, n - 3)
	i1 = clampi(i1, i0 + 2, n - 1)
	var r0 := maxi(0, i0 - ramp_n)
	for i in range(r0, i0 + 1):
		var u := float(i - r0) / float(maxi(i0 - r0, 1))
		var v := pts[i]
		v.y = float(ground.call(v.x, v.z)) + ramp_h * pow(u, 1.6)
		pts[i] = v
	var y0 := pts[i0].y
	var land := pts[i1]
	land.y = float(ground.call(land.x, land.z))
	pts[i1] = land
	for i in range(i0 + 1, i1):
		var u := float(i - i0) / float(i1 - i0)
		var v := pts[i]
		v.y = lerpf(y0, land.y, u) + 4.0 * height * u * (1.0 - u)
		pts[i] = v
	return {"type": "jump", "i0": i0, "i1": i1, "p0": pts[i0], "p1": pts[i1], "height": height,
			"ramp_i": r0, "ramp_h": ramp_h}


## Random take-off indices (at least `gap` points apart) for `count` jumps of `len_n` points.
static func pick_jump_indices(n_points: int, count: int, len_n: int, gap: int, margin: int,
		rng: RandomNumberGenerator) -> Array[int]:
	var out: Array[int] = []
	var span := n_points - 2 * margin - len_n
	if count <= 0 or span <= 0:
		return out
	var slot := float(span) / float(count)
	for k in count:
		var lo := margin + int(slot * k)
		var hi := margin + int(slot * (k + 1)) - len_n - gap
		hi = maxi(hi, lo)
		out.append(rng.randi_range(lo, hi))
	return out

class_name CircuitLayout
extends RefCounted
## The circuit placed in the world: the centre line of CircuitTrack at `scale`, the height of the
## track surface along it, the ground around it, and the queries everything else needs
## (nearest point of the track, racing line, position at a lap distance).
##
## The ground is the track surface itself where the track is (the asphalt and its run-off are flat
## across), blended within BLEND metres into the Eifel hillside around it. That hillside is a smooth
## field built from the track heights themselves, so the circuit never sits on a shelf, plus a relief
## that only grows away from the track.

const CELL := 44.0          ## spatial grid of the centre line, m (a query searches 3 x 3 cells)
const GRID_STRIDE := 2      ## one point out of two goes in the grid (its neighbours are tested too)
## The ground is exactly the track surface out to the far side of the run-off and its guardrail
## (which is why the run-off is computed here and not in the scenery: the two have to agree, or a
## flat run-off ends up drawn over sloping ground), then blends into the hillside over BLEND metres.
const SHOULDER := 2.5       ## flat ground kept beyond the guardrail, m
const BLEND := 16.0
const RUNOFF_BASE := 4.5    ## width of the run-off along a straight, m
const RUNOFF_CORNER := 16.0 ## ...and on the outside of a corner, m
const BARRIER_GAP := 2.5    ## between the edge of the run-off and the guardrail, m
const FIELD_CELL := 16.0    ## coarse grid of the surrounding ground, m
const FIELD_MARGIN := 320.0 ## how far around the circuit that grid goes, m
const HILL_START := 34.0    ## the relief of the ground starts this far from the track, m
const HILL_FULL := 150.0    ## ...and is at full amplitude here
const HILL_HEIGHT := 5.0    ## amplitude of that relief, m (gentle: the Eifel rolls, it has no dunes)

var scale := 0.5
var step := 3.0
## Centre line of the track (xz), point 0 on the start / finish line.
var centre := PackedVector2Array()
## Lap distance of each centre point, m.
var s_at := PackedFloat32Array()
## Unit normal to the right of the direction of travel at each centre point.
var normals := PackedVector2Array()
## Height of the track surface at each centre point, m.
var surface := PackedFloat32Array()
## Signed curvature of the centre line at each point, 1/m.
var curvature := PackedFloat32Array()
## Width of the run-off on each side of the asphalt at each point, m (left = towards -normal).
var runoff_l := PackedFloat32Array()
var runoff_r := PackedFloat32Array()
var lap_length := 0.0
var half_width := 5.6
var kerb_width := 1.1
## xz bounding box of the track.
var bounds := Rect2()

var _grid := {}
var _field := PackedFloat32Array()
var _dist := PackedFloat32Array()
var _fx0 := 0.0
var _fz0 := 0.0
var _fw := 0
var _fh := 0
var _noise: FastNoiseLite
var _noise2: FastNoiseLite

## Layouts already built, by scale and point spacing. Building one costs about 110 ms, and the
## result is entirely determined by those two numbers: the same track, the same grid, the same
## ground, every time. A second session on the circuit, and the sandbox, therefore reuse the first
## one. Sharing is safe because nothing writes to a layout once _init has returned - the run-off
## widths included, which is why _barrier_fit runs in there and not in the scenery.
static var _shared := {}


## A layout for this scale and spacing, built once and kept (see _shared).
static func shared(track_scale := 0.5, point_step := 3.0) -> CircuitLayout:
	var key := "%.4f/%.4f" % [track_scale, point_step]
	if not _shared.has(key):
		_shared[key] = CircuitLayout.new(track_scale, point_step)
	return _shared[key]


func _init(track_scale := 0.5, point_step := 3.0) -> void:
	scale = track_scale
	step = point_step
	half_width = CircuitTrack.HALF_WIDTH
	kerb_width = CircuitTrack.KERB_WIDTH
	centre = CircuitTrack.centre_line(scale, step)
	s_at = CircuitTrack.arc_lengths(centre)
	normals = CircuitTrack.right_normals(centre)
	curvature = CircuitTrack.signed_curvature(centre)
	lap_length = s_at[s_at.size() - 1] + centre[centre.size() - 1].distance_to(centre[0])
	surface = PackedFloat32Array()
	for i in centre.size():
		surface.append(CircuitTrack.height_at(s_at[i], scale))
	_level_folds()
	bounds = _bounds()
	_build_grid()
	_build_noise()
	_build_field()
	_build_runoff()   # (needs distance_to_track, so after the field)


## The elevation profile is written along the lap, which knows nothing about the lap folding back on
## itself: it can give two legs that run forty metres apart - the Mercedes-Arena omega, the hairpin
## and the straight beside it - heights fifteen metres apart, and the ground between them then has
## to be a cliff. Here every point is pulled towards the height of the points that are close to it
## ON THE GROUND but far from it along the lap, until neighbouring legs sit at a believable height
## of each other. The shape of the profile along the lap survives; only the folds are levelled.
const FOLD_REACH := 60.0    ## two legs closer than this in plan have to agree on their height, m
const FOLD_APART := 150.0   ## ...when they are at least this far apart along the lap, m

func _level_folds() -> void:
	var n := centre.size()
	var every := maxi(1, roundi(15.0 / step))
	var idx := PackedInt32Array()
	for i in range(0, n, every):
		idx.append(i)
	var m := idx.size()
	var reach2 := FOLD_REACH * FOLD_REACH
	for _pass in 20:
		var delta := PackedFloat32Array()
		delta.resize(m)
		for a in m:
			var ia := idx[a]
			var sum := 0.0
			var wsum := 0.0
			for b in m:
				if b == a:
					continue
				var ib := idx[b]
				var along := absf(wrapf(s_at[ib] - s_at[ia], -lap_length * 0.5, lap_length * 0.5))
				if along < FOLD_APART:
					continue
				var d2 := centre[ia].distance_squared_to(centre[ib])
				if d2 > reach2:
					continue
				var w := 1.0 - sqrt(d2) / FOLD_REACH
				sum += (surface[ib] - surface[ia]) * w
				wsum += w
			delta[a] = 0.0 if wsum <= 0.0 else sum / wsum * 0.3
		for a in m:
			surface[idx[a]] += delta[a]
		# spread each correction back over the points between the samples, then smooth along the lap
		for a in m:
			var i0 := idx[a]
			var i1 := idx[(a + 1) % m]
			var span := (i1 - i0 + n) % n
			for k in range(1, span):
				surface[(i0 + k) % n] = lerpf(surface[i0], surface[i1], float(k) / span)
		surface = _smoothed(surface, 2)


func _bounds() -> Rect2:
	var lo := centre[0]
	var hi := centre[0]
	for p in centre:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	return Rect2(lo, hi - lo)


func _build_grid() -> void:
	for i in range(0, centre.size(), GRID_STRIDE):
		var key := Vector2i(floori(centre[i].x / CELL), floori(centre[i].y / CELL))
		if not _grid.has(key):
			_grid[key] = PackedInt32Array()
		_grid[key].append(i)


func _build_noise() -> void:
	_noise = FastNoiseLite.new()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.0028 / maxf(scale, 0.1)
	_noise.fractal_octaves = 4
	_noise2 = FastNoiseLite.new()
	_noise2.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise2.frequency = 0.013 / maxf(scale, 0.1)
	_noise2.fractal_octaves = 3


## Coarse height and distance fields around the circuit: the height is an inverse-distance average of
## the track heights (so the ground follows the circuit without any step), the distance is used to
## fade the relief in away from the track.
func _build_field() -> void:
	var sub := PackedVector2Array()
	var sub_h := PackedFloat32Array()
	var every := maxi(1, roundi(18.0 / step))
	for i in range(0, centre.size(), every):
		sub.append(centre[i])
		sub_h.append(surface[i])
	_fx0 = bounds.position.x - FIELD_MARGIN
	_fz0 = bounds.position.y - FIELD_MARGIN
	_fw = ceili((bounds.size.x + 2.0 * FIELD_MARGIN) / FIELD_CELL) + 1
	_fh = ceili((bounds.size.y + 2.0 * FIELD_MARGIN) / FIELD_CELL) + 1
	_field.resize(_fw * _fh)
	_dist.resize(_fw * _fh)
	var soft := 90.0 * maxf(scale, 0.1) / 0.5
	var soft2 := soft * soft
	for iz in _fh:
		for ix in _fw:
			var q := Vector2(_fx0 + ix * FIELD_CELL, _fz0 + iz * FIELD_CELL)
			var sum := 0.0
			var wsum := 0.0
			var best := INF
			for j in sub.size():
				var d2 := q.distance_squared_to(sub[j])
				best = minf(best, d2)
				var w := 1.0 / (d2 + soft2)
				sum += sub_h[j] * w
				wsum += w
			_field[iz * _fw + ix] = sum / maxf(wsum, 0.0001)
			_dist[iz * _fw + ix] = sqrt(best)


func _sample(f: PackedFloat32Array, x: float, z: float) -> float:
	var fx := clampf((x - _fx0) / FIELD_CELL, 0.0, _fw - 1.001)
	var fz := clampf((z - _fz0) / FIELD_CELL, 0.0, _fh - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var a := lerpf(f[iz * _fw + ix], f[iz * _fw + ix + 1], tx)
	var b := lerpf(f[(iz + 1) * _fw + ix], f[(iz + 1) * _fw + ix + 1], tx)
	return lerpf(a, b, tz)


# --- Queries -----------------------------------------------------------------------------------

## Nearest point of the centre line: (distance in xz, height of the track surface there, lap
## distance, which side it is on: +1 to the right of the direction of travel). The distance is INF
## when nothing is within about CELL metres (the caller is far from the track).
func nearest(x: float, z: float) -> Vector4:
	var cx := floori(x / CELL)
	var cz := floori(z / CELL)
	var p := Vector2(x, z)
	var best := INF
	var best_y := 0.0
	var best_s := 0.0
	var best_i := 0
	var best_at := Vector2.ZERO
	var n := centre.size()
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var key := Vector2i(cx + dx, cz + dz)
			if not _grid.has(key):
				continue
			for i in _grid[key]:
				for j in range(i - GRID_STRIDE, i + GRID_STRIDE + 1):
					var a: int = (j % n + n) % n
					var b: int = (a + 1) % n
					var pa := centre[a]
					var ab := centre[b] - pa
					var l2 := ab.length_squared()
					var t := 0.0 if l2 < 0.0001 else clampf((p - pa).dot(ab) / l2, 0.0, 1.0)
					var at := pa + ab * t
					var d := p.distance_to(at)
					if d < best:
						best = d
						best_y = lerpf(surface[a], surface[b], t)
						best_s = s_at[a] + t * sqrt(l2)
						best_i = a
						best_at = at
	if is_inf(best):
		return Vector4(best, 0.0, 0.0, 1.0)
	return Vector4(best, best_y, best_s, 1.0 if (p - best_at).dot(normals[best_i]) >= 0.0 else -1.0)


## Width of the run-off on each side: narrow along a straight, wide on the OUTSIDE of a corner
## (which is where a car leaves the road), and narrowed again wherever the lap folds back close to
## itself - the Mercedes-Arena is an omega whose two legs are only a few tens of metres apart, and a
## full-width run-off there would put its guardrail on the other leg.
func _build_runoff() -> void:
	var n := centre.size()
	runoff_l.resize(n)
	runoff_r.resize(n)
	for i in n:
		runoff_l[i] = RUNOFF_BASE
		runoff_r[i] = RUNOFF_BASE
	var k_thresh := 1.0 / (0.043 * lap_length)
	var i0 := -1
	for c in n * 2:
		var i := c % n
		var strong: bool = absf(curvature[i]) > k_thresh
		if strong and i0 < 0:
			i0 = c
		elif not strong and i0 >= 0:
			if (c - i0) * step >= 12.0:
				_widen_corner(i0, c - 1)
			i0 = -1
			if c >= n:
				break
	runoff_l = _smoothed(runoff_l, 5)
	runoff_r = _smoothed(runoff_r, 5)
	_fit_runoff()
	runoff_l = _smoothed(runoff_l, 3)
	runoff_r = _smoothed(runoff_r, 3)
	# last, because it is what makes the width rail-safe: nothing may widen it afterwards
	runoff_l = _barrier_fit(runoff_l, -1.0)
	runoff_r = _barrier_fit(runoff_r, 1.0)


## The guardrail stands BARRIER_GAP beyond the run-off, and it has to be smoothed and rate-capped
## so that it bends instead of kinking. Both of those may only pull it IN - a line parallel to the
## track folds as soon as it is offset further than the radius of the bend, so a rail that is
## pushed out in a hairpin ends up several metres inside the white lines.
##
## Whatever they take off the rail has to come off the run-off as well, which is why this lives
## here and not in the scenery: the width below is the one thing that says where the gravel is
## drawn, where the ground is flattened and where the rail stands. If the rail alone were pulled
## in, the gravel would be drawn outside its own barrier.
func _barrier_fit(w: PackedFloat32Array, side: float) -> PackedFloat32Array:
	var n := centre.size()
	var cap := PackedFloat32Array()
	cap.resize(n)
	for i in n:
		cap[i] = _clear_of_lap(i, side, absf(safe_offset(i, side * (half_width + w[i] + BARRIER_GAP))))
	var mag := _smoothed(cap, 6)
	for i in n:
		mag[i] = minf(mag[i], cap[i])
	_limit_rise(mag, 0.22 * step)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = maxf(mag[i] - half_width - BARRIER_GAP, 0.0)
	return out


## Pulls an offset in until it stands clear of every part of the lap, not only of the leg it
## belongs to (at the Mercedes-Arena the two sides of the omega are a few tens of metres apart).
func _clear_of_lap(i: int, side: float, mag: float) -> float:
	var low := half_width + BARRIER_GAP
	var m := mag
	while m > low:
		var p := centre[i] + normals[i] * (side * m)
		if nearest(p.x, p.y).x >= half_width + 0.3:
			return m
		m -= 0.5
	return low


## Caps how fast a line may move away from the track from one point to the next, both ways round
## the loop, by pulling the far point IN - never by pushing the near point out. Run in both
## directions it leaves a line that never changes by more than `max_step` per point and never
## exceeds what it was given.
static func _limit_rise(mag: PackedFloat32Array, max_step: float) -> void:
	var n := mag.size()
	for _pass in 2:
		for c in n * 2:
			var i := c % n
			mag[(i + 1) % n] = minf(mag[(i + 1) % n], mag[i] + max_step)
		for c in n * 2:
			var i := (n - 1 - (c % n) + n) % n
			mag[(i - 1 + n) % n] = minf(mag[(i - 1 + n) % n], mag[i] + max_step)


func _widen_corner(a: int, b: int) -> void:
	var n := centre.size()
	var dir := 0.0
	for c in range(a, b + 1):
		dir += curvature[c % n]
	var left := dir > 0.0          # turns left: the outside is the right-hand side
	var span := b - a
	var pad := roundi(26.0 / step)
	for c in range(a - pad, b + pad * 2 + 1):
		var i := (c % n + n) % n
		var t := clampf(float(c - a + pad) / float(span + pad * 3), 0.0, 1.0)
		var w := RUNOFF_CORNER * sin(PI * t)
		if left:
			runoff_r[i] = maxf(runoff_r[i], RUNOFF_BASE + w)
		else:
			runoff_l[i] = maxf(runoff_l[i], RUNOFF_BASE + w)


## Narrows each side until its guardrail stands clear of every part of the track.
func _fit_runoff() -> void:
	var clear := half_width + 6.0
	for i in centre.size():
		for side in [-1.0, 1.0]:
			var w: float = runoff_l[i] if side < 0.0 else runoff_r[i]
			while w > 1.5:
				var off := safe_offset(i, side * (half_width + w + BARRIER_GAP + 1.0))
				var p := centre[i] + normals[i] * off
				if distance_to_track(p.x, p.y) > clear:
					break
				w -= 1.5
			if side < 0.0:
				runoff_l[i] = w
			else:
				runoff_r[i] = w


static func _smoothed(a: PackedFloat32Array, passes: int) -> PackedFloat32Array:
	var n := a.size()
	var cur := a
	for _p in passes:
		var s := cur.duplicate()
		for i in n:
			s[i] = (cur[(i - 1 + n) % n] + 2.0 * cur[i] + cur[(i + 1) % n]) * 0.25
		cur = s
	return cur


## How far from the centre line the ground is still flat on `side` (+1 = right), at point `i`:
## the asphalt, its run-off, the guardrail and a little shoulder behind it.
func flat_half_width(i: int, side: float) -> float:
	var w: float = runoff_l[i] if side < 0.0 else runoff_r[i]
	return half_width + w + BARRIER_GAP + SHOULDER


## A lateral offset (positive = to the right of the direction of travel) that stays usable at point
## `i`. A line drawn parallel to the track folds over itself as soon as it is offset further than
## the radius of the bend towards its centre - a 35 m wide run-off on the inside of a 14 m hairpin
## turns inside out. The offset is therefore kept to 80% of that radius on the inside.
func safe_offset(i: int, off: float) -> float:
	var k := curvature[i % curvature.size()]
	if off * k >= 0.0 or absf(k) < 0.000001:
		return off          # away from the centre of the bend: never folds
	return signf(off) * minf(absf(off), 0.8 / absf(k))


## Same, at a lap distance.
func safe_offset_at(lap_s: float, off: float) -> float:
	return safe_offset(index_at(lap_s), off)


## Distance (m) from (x, z) to the nearest part of the track, anywhere on the lap (a few metres of
## error: it is read from the coarse field). Used to keep the buildings out of the run-off of
## another corner - the lap folds back on itself, so "40 m to the right of the straight" can be
## 10 m from the next corner.
func distance_to_track(x: float, z: float) -> float:
	return _sample(_dist, x, z)


## Height of the ground: the track surface, flat across the asphalt, its run-off and its guardrail,
## then blending into the hillside. The flat part follows the width of the run-off, so a wide
## run-off is never drawn on a slope.
func ground(x: float, z: float) -> float:
	var free := free_height(x, z)
	if _sample(_dist, x, z) > half_width + RUNOFF_CORNER + BARRIER_GAP + SHOULDER + BLEND + FIELD_CELL * 1.6:
		return free
	var q := nearest(x, z)
	if is_inf(q.x):
		return free
	var flat := flat_half_width(index_at(q.z), q.w) if runoff_l.size() > 0 else half_width + 8.0
	if q.x >= flat + BLEND:
		return free
	return lerpf(free, q.y, 1.0 - smoothstep(flat, flat + BLEND, q.x))


## The hillside without the track: the smooth field plus a relief that only grows away from the circuit.
func free_height(x: float, z: float) -> float:
	var d := _sample(_dist, x, z)
	var amp := HILL_HEIGHT * scale / 0.5 * smoothstep(HILL_START, HILL_FULL, d)
	return _sample(_field, x, z) + amp * (_noise.get_noise_2d(x, z) + 0.35 * _noise2.get_noise_2d(x, z))


## Position (xz) and height on the centre line at a lap distance.
func point_at(lap_s: float) -> Vector3:
	var n := centre.size()
	var f := fposmod(lap_s, lap_length) / maxf(lap_length, 0.001) * n
	var i := int(f) % n
	var j := (i + 1) % n
	var t := f - int(f)
	var p := centre[i].lerp(centre[j], t)
	return Vector3(p.x, lerpf(surface[i], surface[j], t), p.y)


## Unit direction of travel (xz) at a lap distance.
func dir_at(lap_s: float) -> Vector2:
	var n := centre.size()
	var i := int(fposmod(lap_s, lap_length) / maxf(lap_length, 0.001) * n) % n
	return (centre[(i + 1) % n] - centre[(i - 1 + n) % n]).normalized()


## Unit normal to the right of the direction of travel at a lap distance.
func normal_at(lap_s: float) -> Vector2:
	var d := dir_at(lap_s)
	return Vector2(d.y, -d.x)


## A point `lateral` metres to the right of the centre line at a lap distance, on the ground.
## The offset is kept inside the radius of the bend (see safe_offset).
func side_point(lap_s: float, lateral: float) -> Vector3:
	var c := point_at(lap_s)
	var nrm := normal_at(lap_s)
	var off := safe_offset_at(lap_s, lateral)
	var x := c.x + nrm.x * off
	var z := c.z + nrm.y * off
	return Vector3(x, ground(x, z), z)


## Index of the centre point nearest to a lap distance.
func index_at(lap_s: float) -> int:
	var n := centre.size()
	return int(fposmod(lap_s, lap_length) / maxf(lap_length, 0.001) * n) % n


# --- Lines -------------------------------------------------------------------------------------

## The centre line in 3D (y = track surface), closed (the last point is not the first one).
func centre3d() -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in centre.size():
		out.append(Vector3(centre[i].x, surface[i], centre[i].y))
	return out


## The line a car drives: the racing line, `margin` metres inside the white lines.
## `swing` scales how much of the width it uses (1 = a racing driver, 0 = the centre line).
func racing_line(margin := 1.4, swing := 1.0) -> PackedVector3Array:
	var off := CircuitTrack.line_offsets(centre, maxf(half_width - margin, 0.2))
	var out := PackedVector3Array()
	for i in centre.size():
		var o := off[i] * swing
		var p := centre[i] + normals[i] * o
		out.append(Vector3(p.x, surface[i], p.y))
	return out


## A full lap starting and ending on the start / finish line: `line` plus its first point again, so
## the subject really crosses the line at both ends.
static func close_lap(line: PackedVector3Array) -> PackedVector3Array:
	var out := line.duplicate()
	out.append(line[0])
	return out


## A lane `lateral` metres to the right of the centre line, as a closed 3D polyline.
func lane(lateral: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in centre.size():
		var p := centre[i] + normals[i] * safe_offset(i, lateral)
		out.append(Vector3(p.x, surface[i], p.y))
	return out

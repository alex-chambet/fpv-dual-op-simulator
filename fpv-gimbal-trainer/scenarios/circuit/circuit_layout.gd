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

const CELL := 28.0          ## spatial grid of the centre line, m (a query searches 3 x 3 cells)
const GRID_STRIDE := 2      ## one point out of two goes in the grid (its neighbours are tested too)
const FLAT := 13.0          ## the ground is exactly the track surface within this distance, m
const BLEND := 26.0         ## ...and is the free terrain beyond this one, m
const FIELD_CELL := 16.0    ## coarse grid of the surrounding ground, m
const FIELD_MARGIN := 320.0 ## how far around the circuit that grid goes, m
const HILL_START := 40.0    ## the relief of the ground starts this far from the track, m
const HILL_FULL := 190.0    ## ...and is at full amplitude here
const HILL_HEIGHT := 7.5    ## amplitude of that relief, m

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
	bounds = _bounds()
	_build_grid()
	_build_noise()
	_build_field()


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
	_noise.frequency = 0.0016 / maxf(scale, 0.1)
	_noise.fractal_octaves = 3
	_noise2 = FastNoiseLite.new()
	_noise2.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise2.frequency = 0.0075 / maxf(scale, 0.1)
	_noise2.fractal_octaves = 2


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

## Nearest point of the centre line: (distance in xz, height of the track surface there, lap distance).
## The distance is INF when nothing is within about CELL metres (the caller is far from the track).
func nearest(x: float, z: float) -> Vector3:
	var cx := floori(x / CELL)
	var cz := floori(z / CELL)
	var p := Vector2(x, z)
	var best := INF
	var best_y := 0.0
	var best_s := 0.0
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
					var d := p.distance_to(pa + ab * t)
					if d < best:
						best = d
						best_y = lerpf(surface[a], surface[b], t)
						best_s = s_at[a] + t * sqrt(l2)
	return Vector3(best, best_y, best_s)


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


## Height of the ground: the track surface on and around the track, the hillside beyond it.
func ground(x: float, z: float) -> float:
	var free := free_height(x, z)
	if _sample(_dist, x, z) > BLEND + FIELD_CELL * 1.6:
		return free
	var q := nearest(x, z)
	if q.x >= BLEND:
		return free
	return lerpf(free, q.y, 1.0 - smoothstep(FLAT, BLEND, q.x))


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

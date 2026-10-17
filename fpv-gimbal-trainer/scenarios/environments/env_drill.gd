class_name EnvDrill
extends EnvGeneric
## Ground of a movement drill ("Mouvements" menu): the generic meadow, but the props are placed so
## that they can never come between the camera and the subject. In a drill the operator is learning
## one figure; losing the subject behind a tree would be noise, not difficulty.
##
## So: nothing tall within reach of the figure (a corridor of open ground along the subject's path,
## as wide as the drone flies), trees and rocks outside it for the parallax that tells the eye how
## fast the drone is really going, and low bushes and boulders inside it - close to the ground,
## under every line of sight.
##
## env_overrides: terrain_kind, slope, bump (as EnvGeneric), plus `clearing` (half width of the
## open corridor, m; 0 = from the drone path).

## Kept clear beyond the widest point of the drone figure, m.
const CLEAR_MARGIN := 20.0
## Nothing in the clearing stands higher than this, m: it stays under every line of sight.
const LOW := 0.75
## The trees stand in a band this deep just outside the clearing, m - a proper edge of forest
## rather than a scatter over the whole field. Spread thinly over 400 by 1300 metres they cost one
## MultiMesh each (measured: 501 trees, 506 MultiMesh nodes, 990 draw calls for an empty meadow),
## because the renderer groups them by 64 m chunk and almost every chunk held a single tree. In a
## band they group properly, they read as a tree line, and what is beyond is fog anyway.
const BAND := 80.0
## One tree per this much ground inside that band, m². Chosen so the band holds about as many trees
## as the old scatter over the whole field did - the point of the band is that they group into a
## tenth of the MultiMesh nodes and read as an edge of forest, not that there are more of them.
const TREE_AREA := 260.0
## One low prop per this much ground inside the clearing, m².
const BUSH_AREA := 450.0

var _clear := 60.0
var _line := PackedVector2Array()


func populate(path: PackedVector3Array, drone: PackedVector3Array, _plan: Dictionary,
		_legacy: bool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 613 + host.world_seed
	_line = _flatten(path)
	_clear = float(opt("clearing", 0.0))
	if _clear <= 0.0:
		_clear = _reach(path, drone) + CLEAR_MARGIN
	var field := _field()
	_tall(rng, field)
	_low(rng, field)


## The ground the props are spread over: the playing area of the drill plus the usual margin.
func _field() -> Rect2:
	var b := _bounds if _bounds.has_area() else Rect2(-60.0, -60.0, 120.0, 120.0)
	return b.grow(style.margin)


## The edge of forest just outside the clearing: far enough never to hide the subject, close enough
## to read the speed of the drone against it. Points are drawn on the band itself rather than over
## the whole field and rejected, so they land where they are wanted and group into few MultiMeshes.
func _tall(rng: RandomNumberGenerator, _field: Rect2) -> void:
	var grounds := PackedVector3Array()
	var scales := PackedFloat32Array()
	var length := maxf(_line_length(), 1.0)
	var area := 2.0 * BAND * length + PI * ((_clear + BAND) * (_clear + BAND) - _clear * _clear)
	var want := clampi(int(area / TREE_AREA), 120, 1400)
	var placed := 0
	var tries := 0
	while placed < want and tries < want * 5:
		tries += 1
		var p := _band_point(rng)
		var d := _to_line(p.x, p.y)
		if d < _clear or d > _clear + BAND:
			continue   # the draw landed along the path rather than beside it
		placed += 1
		var g := Vector3(p.x, ground(p.x, p.y), p.y)
		if rng.randf() < 0.86:
			grounds.append(g)
			scales.append(rng.randf_range(0.9, 1.8))
			host.add_tree_occluder(g, scales[scales.size() - 1])
		else:
			PropFactory.add_rock(host, g, Vector3(rng.randf_range(1.4, 3.4),
					rng.randf_range(1.2, 2.8), rng.randf_range(1.4, 3.6)))
	PropFactory.build_forest(host, grounds, scales, style.prop_color, 41)


## A candidate for the band: a random place on the subject's path, then a random direction and a
## distance inside the band. The caller keeps it only if it really landed in the band - drawing the
## direction over the whole circle is what closes the tree line round the ends of the path, and the
## draws that point along the path instead of across it are simply thrown away.
func _band_point(rng: RandomNumberGenerator) -> Vector2:
	var a: Vector2 = _line[rng.randi() % _line.size()]
	var ang := rng.randf() * TAU
	var r := _clear + BAND * sqrt(rng.randf())
	return a + Vector2(cos(ang), sin(ang)) * r


func _line_length() -> float:
	var l := 0.0
	for i in range(1, _line.size()):
		l += _line[i].distance_to(_line[i - 1])
	return l


## Bushes and boulders inside the clearing. They are low on purpose (LOW): the drone sees over them
## whatever the figure, and they give the near-ground detail that an empty field has not.
func _low(rng: RandomNumberGenerator, field: Rect2) -> void:
	var bushes: Array[Transform3D] = []
	var stones: Array[Transform3D] = []
	var want := clampi(int(field.get_area() / BUSH_AREA), 60, 1200)
	for _i in want * 2:
		if bushes.size() + stones.size() >= want:
			break
		var x := rng.randf_range(field.position.x, field.end.x)
		var z := rng.randf_range(field.position.y, field.end.y)
		var d := _to_line(x, z)
		if d >= _clear or d < 4.0:  # outside the clearing, or right where the subject walks
			continue
		var s := rng.randf_range(0.45, 1.0)
		var b := Basis().scaled(Vector3(s, s * rng.randf_range(0.5, 0.8), s)) \
				.rotated(Vector3.UP, rng.randf() * TAU)
		var t := Transform3D(b, Vector3(x, ground(x, z), z))
		if rng.randf() < 0.65:
			bushes.append(t)
		else:
			stones.append(t)
	_clump(bushes, _bush_mesh(), PathSubject.make_mat(style.prop_color.lightened(0.14), 0.95))
	_clump(stones, _stone_mesh(), PathSubject.make_mat(Color(0.47, 0.46, 0.43), 0.95))


func _bush_mesh() -> Mesh:
	var m := SphereMesh.new()
	m.radius = LOW * 0.75
	m.height = LOW * 1.1
	m.radial_segments = 7
	m.rings = 4
	return m


func _stone_mesh() -> Mesh:
	var m := BoxMesh.new()
	m.size = Vector3(LOW * 1.3, LOW * 0.8, LOW * 1.1)
	return m


func _clump(xforms: Array[Transform3D], mesh: Mesh, mat: Material) -> void:
	MeshBatch.add(host, mesh, xforms, {"material": mat, "shadows": false})


## How far the drone gets from the subject, horizontally, over the whole figure.
func _reach(path: PackedVector3Array, drone: PackedVector3Array) -> float:
	var r := 30.0
	for i in mini(path.size(), drone.size()):
		r = maxf(r, Vector2(drone[i].x - path[i].x, drone[i].z - path[i].z).length())
	return r


func _flatten(path: PackedVector3Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	var last := Vector2(INF, INF)
	for p in path:
		var q := Vector2(p.x, p.z)
		if last.x == INF or q.distance_to(last) >= 8.0:
			out.append(q)
			last = q
	if out.is_empty():
		out.append(Vector2.ZERO)
	return out


func _to_line(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var best := INF
	for q in _line:
		best = minf(best, p.distance_squared_to(q))
	return sqrt(best)

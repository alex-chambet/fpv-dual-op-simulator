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
## One tall prop per this much ground outside the clearing, m².
const TREE_AREA := 900.0
## One low prop per this much ground inside it, m².
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


## Trees and rocks outside the clearing: far enough never to hide the subject, close enough to read
## the speed of the drone against them.
func _tall(rng: RandomNumberGenerator, field: Rect2) -> void:
	var grounds := PackedVector3Array()
	var scales := PackedFloat32Array()
	var want := clampi(int(field.get_area() / TREE_AREA), 40, 900)
	var tries := 0
	while grounds.size() + 1 < want and tries < want * 6:
		tries += 1
		var x := rng.randf_range(field.position.x, field.end.x)
		var z := rng.randf_range(field.position.y, field.end.y)
		if _to_line(x, z) < _clear:
			continue
		var g := Vector3(x, ground(x, z), z)
		if rng.randf() < 0.76:
			grounds.append(g)
			scales.append(rng.randf_range(0.9, 1.8))
			host.add_tree_occluder(g, scales[scales.size() - 1])
		else:
			PropFactory.add_rock(host, g, Vector3(rng.randf_range(1.4, 3.4),
					rng.randf_range(1.2, 2.8), rng.randf_range(1.4, 3.6)))
	PropFactory.build_forest(host, grounds, scales, style.prop_color, 41)


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
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	host.add_child(mmi)


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

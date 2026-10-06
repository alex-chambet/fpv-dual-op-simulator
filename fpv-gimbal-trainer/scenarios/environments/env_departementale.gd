class_name EnvDepartementale
extends EnvironmentBuilder
## French departmental road (tag "departementale"): flat farmland, a two-lane asphalt road with a dashed centre
## line, edge lines and gravel verges, plane trees along the road, poles, hedgerows, farm houses - and traffic:
## cars, vans and trucks coming the other way, cyclists on the verges (RoadTraffic).
## The subject drives in its lane (to the right of the road's centre line, which it follows at CENTRE metres).

## Distance from the subject's line to the centre line of the road (half a lane), m.
const CENTRE := 1.85
const LANE := 3.7
## Half width of the asphalt around the centre line, m.
const HALF_ROAD := 3.7
const SHOULDER := 1.3
const TRAFFIC_TIME := 130.0  # seconds of traffic prepared (longer than any run)

var _road: RoadBuilder
var _dense := PackedVector3Array()   # the subject's line, every 2 m
var _centre := PackedVector3Array()  # centre line of the road
var _traffic: RoadTraffic
var _los := PackedVector2Array()


func configure() -> void:
	surface_offset = 0.12
	corridor_half_width = HALF_ROAD


func base_height(x: float, z: float) -> float:
	return 0.9 * sin(x * 0.011 + z * 0.0045) + 0.6 * sin(z * 0.0085 + 1.0) * cos(x * 0.019) + 0.25 * sin(x * 0.05 + z * 0.03)


func ground(x: float, z: float) -> float:
	if _road == null:
		return base_height(x, z)
	return _road.blend_height(x, z, base_height(x, z), 6.5, 20.0)


func occluder_kind() -> String:
	return "trees"


## Points of a polyline moved sideways: lateral > 0 = to the right of the direction of travel.
static func _offset(pts: PackedVector3Array, lateral: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in pts.size():
		var t := pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]
		t.y = 0.0
		var r := t.normalized().cross(Vector3.UP)
		out.append(pts[i] + r * lateral)
	return out


func build_terrain(path: PackedVector3Array, _plan: Dictionary) -> void:
	_dense = RoadBuilder.sample_curve(host.make_curve(path), 2.0)
	_centre = _offset(_dense, -CENTRE)
	_road = RoadBuilder.new(_centre)
	var b := PathUtil.bounds_xz(path)

	var mi := MeshInstance3D.new()
	mi.name = "Terrain"
	mi.mesh = TerrainBuilder.build(Callable(self, "ground"), 170.0, b.position.y - 120.0, b.end.y + 260.0, 5.0, 40.0)
	mi.material_override = TerrainBuilder.make_material(Color(0.2, 0.34, 0.1), Color(0.6, 0.64, 0.28), 0.4, 0.006)
	host.add_child(mi)

	var shoulder := MeshInstance3D.new()
	shoulder.mesh = RoadBuilder.build_ribbon(_centre, HALF_ROAD + SHOULDER, 0.09)
	shoulder.material_override = PathSubject.make_mat(Color(0.46, 0.43, 0.36), 0.95)
	host.add_child(shoulder)
	var asphalt := MeshInstance3D.new()
	asphalt.mesh = RoadBuilder.build_ribbon(_centre, HALF_ROAD, 0.12)
	asphalt.material_override = PathSubject.make_mat(Color(0.21, 0.21, 0.22), 0.88)
	host.add_child(asphalt)
	var white := PathSubject.make_mat(Color(0.92, 0.92, 0.88), 0.8)
	var dashes := MeshInstance3D.new()
	dashes.mesh = RoadBuilder.build_dashes(_centre, 0.1, 0.16, 2, 5)
	dashes.material_override = white
	dashes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	host.add_child(dashes)
	for side in [-1.0, 1.0]:
		var edge := MeshInstance3D.new()
		edge.mesh = RoadBuilder.build_ribbon(_offset(_centre, side * (HALF_ROAD - 0.3)), 0.07, 0.16)
		edge.material_override = white
		edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		host.add_child(edge)


## The subject's line extended in a straight line before its start and after its end.
func _line_at(s: float, cum: PackedFloat32Array) -> Vector3:
	var total: float = cum[cum.size() - 1]
	if s < 0.0:
		var d := (_dense[1] - _dense[0])
		d.y = 0.0
		return _dense[0] + d.normalized() * s
	if s > total:
		var n := _dense.size()
		var d2 := _dense[n - 1] - _dense[n - 2]
		d2.y = 0.0
		return _dense[n - 1] + d2.normalized() * (s - total)
	return ScenarioBase.polyline_at(_dense, cum, s)


func _side(s: float, cum: PackedFloat32Array) -> Vector3:
	var a := _line_at(s - 2.0, cum)
	var c := _line_at(s + 2.0, cum)
	var t := c - a
	t.y = 0.0
	return t.normalized().cross(Vector3.UP)


func populate(path: PackedVector3Array, drone: PackedVector3Array, _plan: Dictionary, legacy: bool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77 + host.world_seed
	var cum := ScenarioBase.cumulative(_dense)
	var total: float = cum[cum.size() - 1]
	# lines of sight of the session: the trees keep clear of them (the subject is hidden by the traffic, not by chance)
	_los = PackedVector2Array()
	if not legacy:
		for i in range(0, path.size(), 2):
			_los.append(Vector2(path[i].x, path[i].z))
			_los.append(Vector2(drone[i].x, drone[i].z))

	_traffic = RoadTraffic.new()
	_traffic.setup(host, _dense, rng, LANE, HALF_ROAD - CENTRE, -(HALF_ROAD + CENTRE), TRAFFIC_TIME)

	# Electric poles along the right side
	var pole := BoxMesh.new()
	pole.size = Vector3(0.22, 8.0, 0.22)
	pole.material = PathSubject.make_mat(Color(0.4, 0.33, 0.25), 0.9)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = pole
	var poles: Array[Vector3] = []
	var s := -80.0
	while s < total + 200.0:
		var p := _line_at(s, cum) + _side(s, cum) * 7.5
		poles.append(Vector3(p.x, ground(p.x, p.z), p.z))
		s += 45.0
	mm.instance_count = poles.size()
	for i in poles.size():
		mm.set_instance_transform(i, Transform3D(Basis(), poles[i] + Vector3(0, 4.0, 0)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	host.add_child(mmi)

	# Plane trees along both sides of the road
	var grounds := PackedVector3Array()
	var scales := PackedFloat32Array()
	for side in [1.0, -1.0]:
		s = -120.0
		while s < total + 260.0:
			s += rng.randf_range(11.0, 28.0)
			if rng.randf() < 0.25:
				continue
			var lat: float = rng.randf_range(9.0, 12.5) if side > 0.0 else -rng.randf_range(10.5, 14.0)
			_add_round_tree(_line_at(s, cum) + _side(s, cum) * lat, rng.randf_range(0.9, 1.4), grounds, scales)
	# Trees and clumps in the fields
	for i in 170:
		var sz := rng.randf_range(-100.0, total + 250.0)
		var lat2: float = rng.randf_range(30.0, 160.0) * (1.0 if rng.randf() < 0.5 else -1.0)
		_add_round_tree(_line_at(sz, cum) + _side(sz, cum) * lat2, rng.randf_range(0.9, 1.7), grounds, scales)
	PropFactory.build_round_trees(host, grounds, scales, Color(0.2, 0.42, 0.12), 11)

	# Hedgerows between the fields
	var hedge := BoxMesh.new()
	hedge.size = Vector3(1.0, 1.0, 1.0)
	hedge.material = PathSubject.make_mat(Color(0.14, 0.3, 0.1), 0.95)
	var hm := MultiMesh.new()
	hm.transform_format = MultiMesh.TRANSFORM_3D
	hm.mesh = hedge
	hm.instance_count = 140
	for i in 140:
		var hs := rng.randf_range(-100.0, total + 250.0)
		var hl: float = rng.randf_range(24.0, 130.0) * (1.0 if rng.randf() < 0.5 else -1.0)
		var hp := _line_at(hs, cum) + _side(hs, cum) * hl
		var length := rng.randf_range(30.0, 110.0)
		var yaw := 0.0 if rng.randf() < 0.55 else PI * 0.5
		var gy := ground(hp.x, hp.z)
		hm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(1.6, 1.5, length)), Vector3(hp.x, gy + 0.75, hp.z)))
	var hmi := MultiMeshInstance3D.new()
	hmi.multimesh = hm
	host.add_child(hmi)

	# Farm houses and barns
	var house_s := rng.randf_range(150.0, 350.0)
	while house_s < total + 200.0:
		var side_h := 1.0 if rng.randf() < 0.5 else -1.0
		var hp2 := _line_at(house_s, cum) + _side(house_s, cum) * (side_h * rng.randf_range(26.0, 60.0))
		_add_house(Vector3(hp2.x, ground(hp2.x, hp2.z), hp2.z), rng)
		house_s += rng.randf_range(320.0, 700.0)


func _add_round_tree(p: Vector3, tree_scale: float, grounds: PackedVector3Array, scales: PackedFloat32Array) -> void:
	if _near_los(p.x, p.z):
		return
	var g := Vector3(p.x, ground(p.x, p.z), p.z)
	grounds.append(g)
	scales.append(tree_scale)
	host.add_round_tree_occluder(g, tree_scale)


func _add_house(g: Vector3, rng: RandomNumberGenerator) -> void:
	var w := rng.randf_range(7.0, 10.0)
	var l := rng.randf_range(11.0, 16.0)
	var yaw := rng.randf() * PI
	var root := Node3D.new()
	root.position = g
	root.rotation.y = yaw
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(w, 5.0, l)
	body.mesh = bm
	body.material_override = PathSubject.make_mat([Color(0.92, 0.88, 0.78), Color(0.85, 0.8, 0.7), Color(0.9, 0.9, 0.88)][rng.randi() % 3], 0.9)
	body.position = Vector3(0, 2.5, 0)
	root.add_child(body)
	var roof := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(w + 0.8, 2.6, l + 0.8)
	roof.mesh = pm
	roof.material_override = PathSubject.make_mat(Color(0.62, 0.28, 0.18), 0.85)
	roof.position = Vector3(0, 6.3, 0)
	root.add_child(roof)
	host.add_child(root)
	host.add_cylinder_occluder(g, 0.5 * maxf(w, l), 7.0)


## True if (x, z) is within 5 m of a line of sight (drone -> subject) of the session (a crown is up to 4 m wide).
func _near_los(x: float, z: float) -> bool:
	var q := Vector2(x, z)
	for k in range(0, _los.size(), 2):
		var a := _los[k]
		var ab := _los[k + 1] - a
		var l2 := ab.length_squared()
		var t := 0.0 if l2 < 0.0001 else clampf((q - a).dot(ab) / l2, 0.0, 1.0)
		if q.distance_squared_to(a + ab * t) < 25.0:
			return true
	return false


func extra_occlusion(from: Vector3, to: Vector3) -> bool:
	return _traffic != null and _traffic.blocks(from, to)


func dynamic_push(pos: Vector3, radius: float) -> Vector3:
	return _traffic.push(pos, radius) if _traffic != null else Vector3.ZERO

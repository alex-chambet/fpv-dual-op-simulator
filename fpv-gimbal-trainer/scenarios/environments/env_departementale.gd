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
var _ground_params := {}


func configure() -> void:
	surface_offset = 0.12
	corridor_half_width = HALF_ROAD


func base_height(x: float, z: float) -> float:
	return 0.9 * sin(x * 0.011 + z * 0.0045) + 0.6 * sin(z * 0.0085 + 1.0) * cos(x * 0.019) + 0.25 * sin(x * 0.05 + z * 0.03)


func ground(x: float, z: float) -> float:
	if _road == null:
		return base_height(x, z)
	return _road.blend_height(x, z, base_height(x, z), 6.5, 20.0)


func grass_params() -> Dictionary:
	var p := _ground_params.duplicate()
	p.merge({"height": 0.32, "density": 1.0, "crops": true, "flowers": 0.03, "max_slope": 0.4})
	return p


## Farmland going on to the horizon, groves of trees, low wooded hills far away.
func far_scenery() -> Dictionary:
	return {"ring_radius": 1600.0, "ring_cell": 30.0,
		"hills": {"height": 150.0, "r0": 1800.0, "r1": 5500.0, "frequency": 0.0006,
			"forest": Color(0.1, 0.18, 0.07), "grass": Color(0.3, 0.38, 0.15)},
		"trees": {"kind": "broadleaf", "count": 1500, "r0": 150.0, "r1": 1200.0, "colour": Color(0.2, 0.42, 0.12),
			"grove": 0.15}}

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

	var z0 := b.position.y - 120.0
	var z1 := b.end.y + 260.0
	var mi := MeshInstance3D.new()
	mi.name = "Terrain"
	mi.mesh = TerrainBuilder.build(Callable(self, "ground"), 170.0, z0, z1, 5.0, 40.0)
	_ground_params = {"grass_a": Color(0.17, 0.3, 0.08), "grass_b": Color(0.33, 0.43, 0.13),
			"dry": Color(0.52, 0.5, 0.27), "dry_amount": 0.35, "dirt_amount": 0.1, "fields": 1.0,
			"field_size": 125.0, "field_angle": 0.3 + 0.9 * fposmod(host.world_seed * 0.618, 1.0)}
	var mat := GroundMaterials.terrain(_ground_params)
	mi.material_override = mat
	host.add_child(mi)
	terrain_rect = Rect2(-170.0, z0, 340.0, z1 - z0)
	terrain_material = mat
	ground_mask = GroundMask.new()
	ground_mask.setup(terrain_rect)
	ground_mask.add_band(_centre, 30.0, Color(0, 1, 0))
	ground_mask.add_band(_centre, HALF_ROAD + SHOULDER + 1.3, Color(0, 1, 1))
	ground_mask.add_band(_centre, HALF_ROAD + SHOULDER - 0.2, Color(1, 1, 1))
	host.add_child(ground_mask)
	ground_mask.bind(mat)

	var shoulder := MeshInstance3D.new()
	shoulder.mesh = RoadBuilder.build_ribbon(_centre, HALF_ROAD + SHOULDER, 0.09)
	shoulder.material_override = GroundMaterials.gravel({"half_width": HALF_ROAD + SHOULDER})
	shoulder.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	host.add_child(shoulder)
	var asphalt := MeshInstance3D.new()
	asphalt.mesh = RoadBuilder.build_ribbon(_centre, HALF_ROAD, 0.12)
	asphalt.material_override = GroundMaterials.asphalt({"half_width": HALF_ROAD})
	asphalt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	host.add_child(asphalt)
	var white := GroundMaterials.paint()
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

	# Power line along the right side (wooden poles, wires), kilometre / hectometre markers on the verge
	var poles := PackedVector3Array()
	var s := -80.0
	while s < total + 200.0:
		var p := _line_at(s, cum) + _side(s, cum) * 7.5
		poles.append(Vector3(p.x, ground(p.x, p.z), p.z))
		s += 45.0
	Buildings.power_line(host, poles)
	var markers := PackedVector3Array()
	var marker_yaws := PackedFloat32Array()
	var ms := 100.0
	while ms < total:
		var side_dir := _side(ms, cum)
		var mp := _line_at(ms, cum) + side_dir * (CENTRE + HALF_ROAD + SHOULDER - 0.35)
		markers.append(Vector3(mp.x, ground(mp.x, mp.z), mp.z))
		marker_yaws.append(atan2(side_dir.x, side_dir.z))
		ms += 100.0
	Buildings.road_markers(host, markers, marker_yaws)
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

	# Hedgerows between the fields: segments of leafy hedge, kept off the road and the lines of sight
	var hrng := RandomNumberGenerator.new()
	hrng.seed = 950 + host.world_seed
	var hedges: Array[Transform3D] = []
	var hedge_tints := PackedColorArray()
	var bushes: Array[Transform3D] = []
	var bush_tints := PackedColorArray()
	for i in 140:
		var hs := rng.randf_range(-100.0, total + 250.0)
		var hl: float = rng.randf_range(24.0, 130.0) * (1.0 if rng.randf() < 0.5 else -1.0)
		var hp := _line_at(hs, cum) + _side(hs, cum) * hl
		var length := rng.randf_range(30.0, 110.0)
		var yaw := 0.0 if rng.randf() < 0.55 else PI * 0.5
		var along := Basis(Vector3.UP, yaw) * Vector3.BACK
		var n := ceili(length / 5.0)
		var tint := hrng.randf_range(0.8, 1.15)
		for k in n:
			var p := hp + along * (-length * 0.5 + (k + 0.5) * length / n)
			if _road.nearest(p.x, p.z).x < HALF_ROAD + 9.0 or _near_los(p.x, p.z):
				continue
			var t := tint * hrng.randf_range(0.9, 1.1)
			var basis := Basis(Vector3.UP, yaw + hrng.randf_range(-0.08, 0.08)).scaled(
					Vector3(hrng.randf_range(0.9, 1.15), hrng.randf_range(0.85, 1.2), length / n / 6.0 * 1.2))
			hedges.append(Transform3D(basis, Vector3(p.x, ground(p.x, p.z), p.z)))
			hedge_tints.append(Color(0.15 * t, 0.3 * t, 0.1 * t, hrng.randf()))
			if hrng.randf() < 0.3:
				var bp := p + along.cross(Vector3.UP) * (1.3 if hrng.randf() < 0.5 else -1.3)
				if not _near_los(bp.x, bp.z):
					bushes.append(Transform3D(Basis(Vector3.UP, hrng.randf() * TAU).scaled(Vector3.ONE * hrng.randf_range(0.8, 1.3)),
							Vector3(bp.x, ground(bp.x, bp.z), bp.z)))
					bush_tints.append(Color(0.17 * t, 0.32 * t, 0.1 * t, hrng.randf()))
	Vegetation.place(host, "hedge", hedges, hedge_tints, hrng)
	Vegetation.place(host, "bush", bushes, bush_tints, hrng, 250.0)

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
	var kind := rng.randi() % 3
	# the details come from their own random stream (the session's stream is unchanged)
	var drng := RandomNumberGenerator.new()
	drng.seed = absi(int(g.x * 13.0 + g.z * 7.0)) + host.world_seed
	var root := Buildings.barn(drng, w, l) if kind == 2 and drng.randf() < 0.5 else Buildings.farmhouse(drng, w, l, 4.4)
	root.position = g
	root.rotation.y = yaw
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

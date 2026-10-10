class_name SandboxWorld
extends RefCounted
## The sandbox map: a piece of French countryside of 1.6 x 1.6 km in the style of the "Départementale" scenario.
##  - roads: a ring road (about 4 km), two departmental roads crossing it (west-east "A", north-south "B") that meet
##    in the village, a village street, gravel tracks to the farms;
##  - a village at the crossroads: houses facing the streets, a church on the square, pavements, street lamps,
##    parked cars;
##  - farms (farmhouse + barn) in the fields, plane trees along the roads, hedges, groves, a power line, kilometre
##    markers, farmland parcels, 3D grass and the far landscape.
## Moving things (traffic, cyclists, pedestrians) are added by SandboxTraffic and Pedestrians from `roads`.
## Positions: x east, z south (north = -z). The village is at the origin.

const HALF := 800.0
const LANE := 3.6
const MAIN_HALF := 3.6        ## half width of the asphalt of the main roads
const STREET_HALF := 3.0
const SHOULDER := 1.2
const VILLAGE_R := 230.0
const SEED := 2024

## Roads: {name, pts (every 2 m, y = road surface), half, closed, kind ("main" / "street" / "track")}
var roads: Array[Dictionary] = []
## Junction points (xz) where roads meet (no centre line there).
var junctions := PackedVector2Array()
## Sidewalk lines in the village: polylines walked by the pedestrians.
var sidewalks: Array[PackedVector3Array] = []
## Spots of the village square where people stand and chat.
var square_spots := PackedVector3Array()
## Where the drone takes off and the direction it faces at start.
var start_pos := Vector3.ZERO
var start_look := Vector3.FORWARD

# Static obstacles for the drone: houses / church / barns as oriented boxes, trees as round crowns.
var _boxes: Array[Dictionary] = []   # {c: Vector3 (ground centre), yaw, hx, hz, h}
var _trees := PackedVector3Array()   # ground positions
var _tree_scales := PackedFloat32Array()
var _grid := {}
var _builders: Array[RoadBuilder] = []
var _host: Node3D
var _rng := RandomNumberGenerator.new()
var _houses := PackedVector2Array()  # centres, to keep buildings apart
var _ground_params := {}
var terrain_material: Material
var mask: GroundMask


# --- Ground ------------------------------------------------------------------------------------------

func ground(x: float, z: float) -> float:
	return 1.4 * sin(x * 0.0041 + 0.5) * cos(z * 0.0036 - 0.3) + 0.7 * sin(x * 0.0093 + z * 0.0061) \
			+ 0.25 * sin(x * 0.021 - z * 0.017)


## Far away the plain goes on with wider undulations.
func far_height(x: float, z: float) -> float:
	var d := maxf(0.0, maxf(absf(x), absf(z)) - HALF)
	return ground(x, z) + 6.0 * sin(x * 0.0013 + 1.1) * sin(z * 0.0011) * smoothstep(0.0, 400.0, d) \
			- 0.5 * smoothstep(0.0, 60.0, d)


func grass_params() -> Dictionary:
	var p := _ground_params.duplicate()
	p.merge({"height": 0.32, "density": 1.0, "crops": true, "flowers": 0.04, "max_slope": 0.4})
	return p


# --- Build --------------------------------------------------------------------------------------------

func build(host: Node3D) -> void:
	_host = host
	_rng.seed = SEED
	_make_roads()
	_build_terrain()
	_build_roads()
	_build_village()
	_build_farms()
	_build_vegetation()
	_build_furniture()
	FarScenery.build_into(host, Callable(self, "far_height"), SEED, Rect2(-HALF, -HALF, 2.0 * HALF, 2.0 * HALF),
			terrain_material, {"ring_radius": 2600.0, "ring_cell": 40.0,
				"hills": {"height": 170.0, "r0": 2800.0, "r1": 7000.0, "frequency": 0.0006,
					"forest": Color(0.1, 0.18, 0.07), "grass": Color(0.3, 0.38, 0.15)},
				"trees": {"kind": "broadleaf", "count": 1800, "r0": 820.0, "r1": 2200.0, "colour": Color(0.2, 0.42, 0.12),
					"grove": 0.15}})
	_build_grid()


static func ring_radius(theta: float) -> float:
	return 640.0 + 55.0 * sin(3.0 * theta + 1.0) + 25.0 * sin(5.0 * theta + 0.4)


static func ring_point(theta: float) -> Vector3:
	var r := ring_radius(theta)
	return Vector3(cos(theta) * r, 0.0, sin(theta) * r)


func _smooth(ctrl: Array, closed := false) -> PackedVector3Array:
	var c := Curve3D.new()
	c.closed = closed
	for p in ctrl:
		c.add_point(p)
	FlightPath.auto_smooth(c)
	c.bake_interval = 0.5
	var pts := RoadBuilder.sample_curve(c, 2.0)
	if closed and pts.size() > 2 and pts[pts.size() - 1].distance_to(pts[0]) < 1.0:
		pts.remove_at(pts.size() - 1)
	for i in pts.size():
		pts[i].y = ground(pts[i].x, pts[i].z)
	return pts


func _make_roads() -> void:
	var ring_ctrl := []
	for k in 12:
		ring_ctrl.append(ring_point(TAU * k / 12.0))
	roads.append({"name": "ring", "pts": _smooth(ring_ctrl, true), "half": MAIN_HALF, "closed": true, "kind": "main"})
	var west := ring_point(PI)
	var east := ring_point(0.0)
	var north := ring_point(PI * 1.5)
	var south := ring_point(PI * 0.5)
	roads.append({"name": "A", "pts": _smooth([west, Vector3(-420, 0, 30), Vector3(-180, 0, -12), Vector3(0, 0, 0),
			Vector3(190, 0, 10), Vector3(400, 0, -35), east]), "half": MAIN_HALF, "closed": false, "kind": "main"})
	roads.append({"name": "B", "pts": _smooth([north, Vector3(35, 0, -380), Vector3(-10, 0, -170), Vector3(0, 0, 0),
			Vector3(12, 0, 175), Vector3(-40, 0, 400), south]), "half": MAIN_HALF, "closed": false, "kind": "main"})
	# village street: leaves road A west of the crossroads, curves south to a small square
	var a_pts: PackedVector3Array = roads[1].pts
	var s0 := _nearest_point(a_pts, Vector3(-110, 0, 0))
	roads.append({"name": "street", "pts": _smooth([s0, s0 + Vector3(4, 0, 40), Vector3(-80, 0, 95), Vector3(-30, 0, 140)]),
			"half": STREET_HALF, "closed": false, "kind": "street"})
	junctions.append(Vector2(west.x, west.z))
	junctions.append(Vector2(east.x, east.z))
	junctions.append(Vector2(north.x, north.z))
	junctions.append(Vector2(south.x, south.z))
	junctions.append(Vector2.ZERO)
	junctions.append(Vector2(s0.x, s0.z))
	# gravel tracks from the main roads to the farms (farm at the end)
	var farms := [[PI * 0.25, -1.0], [PI * 0.8, 1.0], [PI * 1.3, -1.0], [PI * 1.8, 1.0], [PI * 1.05, 1.0], [PI * 0.45, 1.0]]
	for f in farms:
		var on_ring := ring_point(f[0])
		var inward: float = f[1]
		var dir := -on_ring.normalized() * inward
		var mid := on_ring + dir * 70.0 + dir.cross(Vector3.UP) * 25.0
		var end := on_ring + dir * 150.0
		roads.append({"name": "track", "pts": _smooth([on_ring, mid, end]), "half": 1.6, "closed": false, "kind": "track"})
		junctions.append(Vector2(on_ring.x, on_ring.z))
	for r in roads:
		_builders.append(RoadBuilder.new(_closed_pts(r)))


static func _closed_pts(r: Dictionary) -> PackedVector3Array:
	var pts: PackedVector3Array = r.pts
	if r.closed:
		pts = pts.duplicate()
		pts.append(pts[0])
	return pts


static func _nearest_point(pts: PackedVector3Array, p: Vector3) -> Vector3:
	var best := pts[0]
	for q in pts:
		if Vector2(q.x - p.x, q.z - p.z).length() < Vector2(best.x - p.x, best.z - p.z).length():
			best = q
	return best


## Distance (xz) to the nearest road centre line, and that road's half width.
func road_distance(x: float, z: float) -> Vector2:
	var best := Vector2(INF, 0.0)
	for i in _builders.size():
		var d := _builders[i].nearest(x, z).x
		if d < best.x:
			best = Vector2(d, float(roads[i].half))
	return best


## True if (x, z) is on a road, its shoulder or within `margin` metres of them.
func near_road(x: float, z: float, margin: float) -> bool:
	var d := road_distance(x, z)
	return d.x < d.y + SHOULDER + margin


func _near_junction(p: Vector3, r: float) -> bool:
	for j in junctions:
		if Vector2(p.x, p.z).distance_to(j) < r:
			return true
	return false


func _build_terrain() -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Terrain"
	mi.mesh = TerrainBuilder.build(Callable(self, "ground"), HALF, -HALF, HALF, 6.0, 40.0)
	_ground_params = {"grass_a": Color(0.17, 0.3, 0.08), "grass_b": Color(0.33, 0.43, 0.13),
			"dry": Color(0.52, 0.5, 0.27), "dry_amount": 0.35, "dirt_amount": 0.1, "fields": 1.0,
			"field_size": 120.0, "field_angle": 0.45}
	var mat := GroundMaterials.terrain(_ground_params)
	mi.material_override = mat
	terrain_material = mat
	_host.add_child(mi)
	mask = GroundMask.new()
	mask.setup(Rect2(-HALF, -HALF, 2.0 * HALF, 2.0 * HALF), 0.45)
	mask.add_disc(Vector2.ZERO, VILLAGE_R + 40.0, Color(0, 1, 0))  # no fields in the village
	for r in roads:
		if r.kind != "track":
			mask.add_band(_closed_pts(r), 24.0, Color(0, 1, 0))
	for r in roads:
		var half: float = r.half
		mask.add_band(_closed_pts(r), half + SHOULDER + 1.3, Color(0, 1, 1))
	for r in roads:
		var half: float = r.half
		mask.add_band(_closed_pts(r), half + (SHOULDER - 0.2 if r.kind == "main" else 0.6), Color(1, 1, 1))
	_host.add_child(mask)
	mask.bind(mat)


func _ribbon(pts: PackedVector3Array, half: float, y: float, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = RoadBuilder.build_ribbon(pts, half, y)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_host.add_child(mi)


## Parts of a polyline farther than r from every junction (and, if inside_village >= 0, only inside (1) or
## outside (0) the village).
func _split(pts: PackedVector3Array, r: float, inside_village := -1) -> Array[PackedVector3Array]:
	var out: Array[PackedVector3Array] = []
	var cur := PackedVector3Array()
	for p in pts:
		var ok := not _near_junction(p, r)
		if inside_village >= 0:
			ok = ok and ((Vector2(p.x, p.z).length() < VILLAGE_R) == (inside_village == 1))
		if ok:
			cur.append(p)
		elif cur.size() > 1:
			out.append(cur)
			cur = PackedVector3Array()
		else:
			cur = PackedVector3Array()
	if cur.size() > 1:
		out.append(cur)
	return out


static func offset_line(pts: PackedVector3Array, lateral: float, closed := false) -> PackedVector3Array:
	var out := PackedVector3Array()
	var n := pts.size()
	for i in n:
		var a := pts[(i - 1 + n) % n] if closed else pts[maxi(i - 1, 0)]
		var b := pts[(i + 1) % n] if closed else pts[mini(i + 1, n - 1)]
		var t := b - a
		t.y = 0.0
		var right := t.normalized().cross(Vector3.UP)
		out.append(pts[i] + right * lateral)
	return out


func _build_roads() -> void:
	var white := GroundMaterials.paint()
	var k := 0
	for r in roads:
		var pts := _closed_pts(r)
		var half: float = r.half
		var y := 0.12 + 0.006 * k  # each road a little higher: no flicker where two roads overlap
		k += 1
		match r.kind:
			"track":
				_ribbon(pts, half + 0.3, y - 0.04, GroundMaterials.gravel({"half_width": half + 0.3}))
			_:
				_ribbon(pts, half + SHOULDER, y - 0.03, GroundMaterials.gravel({"half_width": half + SHOULDER}))
				_ribbon(pts, half, y, GroundMaterials.asphalt({"half_width": half}))
				if r.kind == "main":
					for part in _split(pts, 14.0):
						var d := MeshInstance3D.new()
						d.mesh = RoadBuilder.build_dashes(part, 0.07, y + 0.02, 2, 5)
						d.material_override = white
						d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
						_host.add_child(d)
					for side in [-1.0, 1.0]:
						for part in _split(offset_line(pts, side * (half - 0.3)), 12.0, 0):
							var e := MeshInstance3D.new()
							e.mesh = RoadBuilder.build_ribbon(part, 0.07, y + 0.02)
							e.material_override = white
							e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
							_host.add_child(e)


# --- Village ------------------------------------------------------------------------------------------

func _build_village() -> void:
	var pave := PathSubject.make_mat(Color(0.56, 0.55, 0.52), 0.9)
	var curb := PathSubject.make_mat(Color(0.7, 0.7, 0.68), 0.8)
	# pavements on both sides of the village roads, the walking lines of the pedestrians
	for r in roads:
		if r.kind == "track":
			continue
		var half: float = r.half
		for side in [-1.0, 1.0]:
			var line := offset_line(r.pts, side * (half + 1.3), r.closed)
			for part in _split(line, 9.0, 1):
				if part.size() < 8:
					continue
				var raised := PackedVector3Array()
				for p in part:
					raised.append(p)
				_ribbon(raised, 1.1, 0.2, pave)
				_ribbon(offset_line(raised, -side * 1.1), 0.08, 0.24, curb)
				sidewalks.append(raised)
	# the square: paved disc north-east of the crossroads, with the church
	var sq := Vector3(32, 0, -30)
	sq.y = ground(sq.x, sq.z)
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 20.0
	cyl.bottom_radius = 20.0
	cyl.height = 0.6
	cyl.radial_segments = 32
	disc.mesh = cyl
	disc.material_override = pave
	disc.position = sq + Vector3(0, -0.12, 0)
	_host.add_child(disc)
	_church(sq + Vector3(16, 0, -18), deg_to_rad(-35.0))
	for k in 8:
		var a := TAU * k / 8.0 + 0.3
		var p := sq + Vector3(cos(a), 0, sin(a)) * _rng.randf_range(5.0, 13.0)
		p.y = ground(p.x, p.z) + 0.2
		square_spots.append(p)
	start_pos = sq + Vector3(-6, 0, 8)
	start_pos.y = ground(start_pos.x, start_pos.z) + 0.2
	start_look = Vector3(-1, 0, 0.6)
	# houses along the village roads
	var drng := RandomNumberGenerator.new()
	drng.seed = SEED + 7
	for r in roads:
		if r.kind == "track":
			continue
		var pts: PackedVector3Array = r.pts
		var cum := PathUtil.cumulative(pts)
		var total: float = cum[cum.size() - 1]
		var half: float = r.half
		for side in [-1.0, 1.0]:
			var s := 6.0
			while s < total:
				var p := PathUtil.polyline_at(pts, cum, s)
				var inside := Vector2(p.x, p.z).length() < VILLAGE_R
				var step := drng.randf_range(13.0, 20.0) if inside else 60.0
				s += step
				if not inside or _near_junction(p, 18.0):
					continue
				# dense in the centre, gaps (gardens, fields) towards the edge of the village
				var dc := Vector2(p.x, p.z).length()
				if drng.randf() < smoothstep(90.0, VILLAGE_R, dc) * 0.65:
					continue
				var t := PathUtil.polyline_at(pts, cum, minf(s - step + 2.0, total)) - PathUtil.polyline_at(pts, cum, maxf(s - step - 2.0, 0.0))
				t.y = 0.0
				var right := t.normalized().cross(Vector3.UP)
				var w := drng.randf_range(7.5, 9.5)
				var l := drng.randf_range(9.0, 13.0)
				var c: Vector3 = p + right * side * (half + 3.2 + w * 0.5)
				if near_road(c.x, c.z, w * 0.5 + 1.0) or _too_close(c, 11.0):
					continue
				c.y = ground(c.x, c.z)
				var to_road: Vector3 = -right * side
				var yaw := atan2(-to_road.z, to_road.x)
				var house := Buildings.farmhouse(drng, w, l, 6.0, false, true)
				house.position = c
				house.rotation.y = yaw
				_host.add_child(house)
				_add_box(c, yaw, w * 0.5, l * 0.5, 9.0)
				_houses.append(Vector2(c.x, c.z))
				# a garden tree behind some houses
				if drng.randf() < 0.45:
					var g: Vector3 = c - to_road * (w * 0.5 + drng.randf_range(4.0, 7.0)) + right * drng.randf_range(-3.0, 3.0)
					if not near_road(g.x, g.z, 3.0):
						_add_tree(Vector3(g.x, ground(g.x, g.z), g.z), drng.randf_range(0.6, 0.85))
				# a parked car in front of some houses
				if drng.randf() < 0.3 and r.kind == "street":
					var pc: Vector3 = p + right * side * (half - 1.1)
					var car_root := Node3D.new()
					CarModel.build(car_root, TrafficModels.CAR_COLORS[drng.randi() % TrafficModels.CAR_COLORS.size()], drng.randi() % 2)
					car_root.position = Vector3(pc.x, ground(pc.x, pc.z) + 0.12, pc.z)
					car_root.rotation.y = atan2(-t.x, -t.z)
					_host.add_child(car_root)
					_add_box(car_root.position, car_root.rotation.y, 0.9, 2.1, 1.5)


func _too_close(c: Vector3, d: float) -> bool:
	for h in _houses:
		if h.distance_to(Vector2(c.x, c.z)) < d:
			return true
	return false


## A village church: nave with a tiled roof and a bell tower with a slate spire.
func _church(g: Vector3, yaw: float) -> void:
	g.y = ground(g.x, g.z)
	var root := Node3D.new()
	root.position = g
	root.rotation.y = yaw
	var stone := PathSubject.make_mat(Color(0.74, 0.68, 0.56), 0.95)
	var slate := PathSubject.make_mat(Color(0.25, 0.27, 0.3), 0.6)
	var tiles := PathSubject.make_mat(Color(0.58, 0.3, 0.2), 0.85)
	_box_mesh(root, Vector3(10, 9, 24), Vector3(0, 4.3, 0), stone)
	var roof := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(11, 4.5, 24.6)
	roof.mesh = pm
	roof.material_override = tiles
	roof.position = Vector3(0, 11.0, 0)
	root.add_child(roof)
	_box_mesh(root, Vector3(5.5, 20, 5.5), Vector3(0, 9.8, -14.5), stone)
	var spire := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 3.9
	cone.height = 9.0
	cone.radial_segments = 4
	spire.mesh = cone
	spire.material_override = slate
	spire.position = Vector3(0, 24.3, -14.5)
	spire.rotation.y = PI * 0.25
	root.add_child(spire)
	var dark := PathSubject.make_mat(Color(0.12, 0.1, 0.09), 0.9)
	_box_mesh(root, Vector3(1.6, 2.2, 0.1), Vector3(0, 15.5, -17.3), dark)  # bell openings
	_box_mesh(root, Vector3(2.2, 3.6, 0.1), Vector3(0, 1.6, -17.3), dark)   # door
	for k in 4:
		for sx in [-1.0, 1.0]:
			_box_mesh(root, Vector3(0.1, 3.0, 1.2), Vector3(sx * 5.02, 5.0, -7.5 + k * 5.0), dark)  # windows
	_host.add_child(root)
	_add_box(g, yaw, 5.0, 12.0, 13.0)
	_add_box(g + Basis(Vector3.UP, yaw) * Vector3(0, 0, -14.5), yaw, 2.8, 2.8, 29.0)
	_houses.append(Vector2(g.x, g.z))


func _box_mesh(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)


# --- Farms, trees, hedges ----------------------------------------------------------------------------

func _build_farms() -> void:
	var frng := RandomNumberGenerator.new()
	frng.seed = SEED + 11
	for r in roads:
		if r.kind != "track":
			continue
		var pts: PackedVector3Array = r.pts
		var end := pts[pts.size() - 1]
		var dir := end - pts[pts.size() - 4]
		dir.y = 0.0
		dir = dir.normalized()
		var side := dir.cross(Vector3.UP)
		var h := end + dir * 12.0 + side * 8.0
		h.y = ground(h.x, h.z)
		var w := frng.randf_range(8.0, 10.0)
		var l := frng.randf_range(13.0, 17.0)
		var house := Buildings.farmhouse(frng, w, l, 5.0, true, true)
		house.position = h
		house.rotation.y = atan2(-dir.z, dir.x) + PI * 0.5
		_host.add_child(house)
		_add_box(h, house.rotation.y, w * 0.5, l * 0.5, 8.0)
		var b := end + dir * 16.0 - side * 16.0
		b.y = ground(b.x, b.z)
		var barn := Buildings.barn(frng, 12.0, 20.0)
		barn.position = b
		barn.rotation.y = atan2(-dir.z, dir.x)
		_host.add_child(barn)
		_add_box(b, barn.rotation.y, 6.0, 10.0, 7.0)
		_houses.append(Vector2(h.x, h.z))
		_houses.append(Vector2(b.x, b.z))
		for k in 5:
			var tp := end + dir * frng.randf_range(-10.0, 34.0) + side * frng.randf_range(-30.0, 30.0)
			if not near_road(tp.x, tp.z, 4.0) and not _too_close(tp, 12.0):
				_add_tree(Vector3(tp.x, ground(tp.x, tp.z), tp.z), frng.randf_range(0.9, 1.4))


func _add_tree(g: Vector3, s: float) -> void:
	_trees.append(g)
	_tree_scales.append(s)


func _build_vegetation() -> void:
	var trng := RandomNumberGenerator.new()
	trng.seed = SEED + 21
	# plane trees along the departmental roads, outside the village
	for r in roads:
		if r.kind != "main":
			continue
		var pts: PackedVector3Array = r.pts
		var cum := PathUtil.cumulative(pts)
		var total: float = cum[cum.size() - 1]
		for side in [-1.0, 1.0]:
			var s := 0.0
			while s < total:
				s += trng.randf_range(12.0, 24.0)
				if trng.randf() < (0.3 if r.name != "ring" else 0.6):
					continue
				var p := PathUtil.polyline_at(pts, cum, minf(s, total))
				if Vector2(p.x, p.z).length() < VILLAGE_R + 30.0 or _near_junction(p, 20.0):
					continue
				var t := PathUtil.polyline_at(pts, cum, minf(s + 2.0, total)) - PathUtil.polyline_at(pts, cum, maxf(s - 2.0, 0.0))
				t.y = 0.0
				var q: Vector3 = p + t.normalized().cross(Vector3.UP) * side * trng.randf_range(9.0, 11.5)
				if near_road(q.x, q.z, 3.0):
					continue
				_add_tree(Vector3(q.x, ground(q.x, q.z), q.z), trng.randf_range(0.95, 1.35))
	# groves and lone trees in the fields
	var placed := 0
	var tries := 0
	while placed < 420 and tries < 4000:
		tries += 1
		var c := Vector3(trng.randf_range(-HALF + 20.0, HALF - 20.0), 0.0, trng.randf_range(-HALF + 20.0, HALF - 20.0))
		if Vector2(c.x, c.z).length() < VILLAGE_R + 20.0:
			continue
		var n := trng.randi_range(1, 9)
		for k in n:
			var q := c + Vector3(trng.randf_range(-14.0, 14.0), 0.0, trng.randf_range(-14.0, 14.0))
			if near_road(q.x, q.z, 6.0) or _too_close(q, 14.0):
				continue
			_add_tree(Vector3(q.x, ground(q.x, q.z), q.z), trng.randf_range(0.8, 1.6))
			placed += 1
	Vegetation.plant(_host, "broadleaf", _trees, _tree_scales, Color(0.2, 0.42, 0.12), SEED + 22)
	# hedgerows between the fields, bushes along them
	var hedges: Array[Transform3D] = []
	var hedge_tints := PackedColorArray()
	var bushes: Array[Transform3D] = []
	var bush_tints := PackedColorArray()
	for i in 220:
		var c := Vector3(trng.randf_range(-HALF + 30.0, HALF - 30.0), 0.0, trng.randf_range(-HALF + 30.0, HALF - 30.0))
		var length := trng.randf_range(30.0, 120.0)
		var yaw := 0.45 + (0.0 if trng.randf() < 0.55 else PI * 0.5)
		var along := Basis(Vector3.UP, yaw) * Vector3.BACK
		var n := ceili(length / 5.0)
		var tint := trng.randf_range(0.8, 1.15)
		for k in n:
			var p := c + along * (-length * 0.5 + (k + 0.5) * length / n)
			if near_road(p.x, p.z, 7.0) or Vector2(p.x, p.z).length() < VILLAGE_R or _too_close(p, 12.0):
				continue
			var t := tint * trng.randf_range(0.9, 1.1)
			var basis := Basis(Vector3.UP, yaw + trng.randf_range(-0.08, 0.08)).scaled(
					Vector3(trng.randf_range(0.9, 1.15), trng.randf_range(0.85, 1.2), length / n / 6.0 * 1.2))
			hedges.append(Transform3D(basis, Vector3(p.x, ground(p.x, p.z), p.z)))
			hedge_tints.append(Color(0.15 * t, 0.3 * t, 0.1 * t, trng.randf()))
			if trng.randf() < 0.25:
				var bp := p + along.cross(Vector3.UP) * (1.3 if trng.randf() < 0.5 else -1.3)
				bushes.append(Transform3D(Basis(Vector3.UP, trng.randf() * TAU).scaled(Vector3.ONE * trng.randf_range(0.8, 1.3)),
						Vector3(bp.x, ground(bp.x, bp.z), bp.z)))
				bush_tints.append(Color(0.17 * t, 0.32 * t, 0.1 * t, trng.randf()))
	Vegetation.place(_host, "hedge", hedges, hedge_tints, trng)
	Vegetation.place(_host, "bush", bushes, bush_tints, trng, 250.0)


# --- Furniture: power line, markers, street lamps ----------------------------------------------------

func _build_furniture() -> void:
	# power line along the outside of the ring road
	var ring: PackedVector3Array = roads[0].pts
	var poles := PackedVector3Array()
	var line := offset_line(ring, -9.0, true)
	var cum := PathUtil.cumulative(line)
	var total: float = cum[cum.size() - 1]
	var s := 0.0
	while s < total - 20.0:
		var p := PathUtil.polyline_at(line, cum, s)
		if not near_road(p.x, p.z, 2.0):
			poles.append(Vector3(p.x, ground(p.x, p.z), p.z))
		elif poles.size() > 1:
			Buildings.power_line(_host, poles)
			poles = PackedVector3Array()
		s += 45.0
	Buildings.power_line(_host, poles)
	# kilometre / hectometre markers on the main roads
	var markers := PackedVector3Array()
	var yaws := PackedFloat32Array()
	for r in roads:
		if r.kind != "main":
			continue
		var pts: PackedVector3Array = r.pts
		var rc := PathUtil.cumulative(pts)
		var rt: float = rc[rc.size() - 1]
		var m := 100.0
		while m < rt:
			var p := PathUtil.polyline_at(pts, rc, m)
			if Vector2(p.x, p.z).length() > VILLAGE_R and not _near_junction(p, 15.0):
				var t := PathUtil.polyline_at(pts, rc, minf(m + 2.0, rt)) - PathUtil.polyline_at(pts, rc, m - 2.0)
				t.y = 0.0
				var side := t.normalized().cross(Vector3.UP)
				var q := p + side * (MAIN_HALF + SHOULDER - 0.35)
				markers.append(Vector3(q.x, ground(q.x, q.z), q.z))
				yaws.append(atan2(side.x, side.z))
			m += 100.0
	Buildings.road_markers(_host, markers, yaws)
	# street lamps along the village pavements
	var lamp_pole := CylinderMesh.new()
	lamp_pole.top_radius = 0.06
	lamp_pole.bottom_radius = 0.09
	lamp_pole.height = 5.5
	lamp_pole.radial_segments = 6
	lamp_pole.material = PathSubject.make_mat(Color(0.18, 0.2, 0.2), 0.5)
	var head := BoxMesh.new()
	head.size = Vector3(0.35, 0.18, 0.7)
	head.material = PathSubject.make_mat(Color(0.2, 0.22, 0.22), 0.5)
	var xs: Array[Transform3D] = []
	var hs: Array[Transform3D] = []
	var flip := false
	for w in sidewalks:
		flip = not flip
		if flip:
			continue
		var wc := PathUtil.cumulative(w)
		var wt: float = wc[wc.size() - 1]
		var d := 8.0
		while d < wt:
			var p := PathUtil.polyline_at(w, wc, d)
			var t := PathUtil.polyline_at(w, wc, minf(d + 1.0, wt)) - PathUtil.polyline_at(w, wc, maxf(d - 1.0, 0.0))
			var b := Basis(Vector3.UP, atan2(t.x, t.z))
			xs.append(Transform3D(b, p + Vector3(0, 2.75, 0)))
			hs.append(Transform3D(b, p + Vector3(0, 5.45, 0)))
			d += 28.0
	for spec in [[lamp_pole, xs], [head, hs]]:
		var list: Array = spec[1]
		if list.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = spec[0]
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		_host.add_child(mmi)


# --- Obstacles for the drone ---------------------------------------------------------------------------

func _add_box(c: Vector3, yaw: float, hx: float, hz: float, h: float) -> void:
	_boxes.append({"c": c, "yaw": yaw, "hx": hx, "hz": hz, "h": h})


func _build_grid() -> void:
	for i in _boxes.size():
		var b: Dictionary = _boxes[i]
		var r: float = maxf(b.hx, b.hz) * 1.5
		for gx in range(floori((b.c.x - r) / 16.0), floori((b.c.x + r) / 16.0) + 1):
			for gz in range(floori((b.c.z - r) / 16.0), floori((b.c.z + r) / 16.0) + 1):
				_cell(Vector2i(gx, gz)).append(-1 - i)
	for i in _trees.size():
		var t := _trees[i]
		_cell(Vector2i(floori(t.x / 16.0), floori(t.z / 16.0))).append(i)


func _cell(key: Vector2i) -> Array:
	if not _grid.has(key):
		_grid[key] = []
	return _grid[key]


## Horizontal push getting a sphere of radius r at `pos` out of the buildings and trees.
func push(pos: Vector3, r: float) -> Vector3:
	var best := Vector3.ZERO
	var cx := floori(pos.x / 16.0)
	var cz := floori(pos.z / 16.0)
	for gx in range(cx - 1, cx + 2):
		for gz in range(cz - 1, cz + 2):
			for idx in _grid.get(Vector2i(gx, gz), []):
				var p := Vector3.ZERO
				if idx < 0:
					var b: Dictionary = _boxes[-1 - idx]
					p = box_push(pos, r, b.c, b.yaw, b.hx, b.hz, b.h)
				else:
					var t := _trees[idx]
					var s := _tree_scales[idx]
					var rad := PropFactory.round_tree_radius_at((pos.y - t.y) / s) * s
					var off := Vector2(pos.x - t.x, pos.z - t.z)
					var d := off.length()
					if rad > 0.0 and d < rad + r:
						var dir := off / d if d > 0.001 else Vector2(1, 0)
						p = Vector3(dir.x, 0.0, dir.y) * (rad + r - d)
				if p.length() > best.length():
					best = p
	return best


## Push out of an oriented box (ground centre c, yaw, half sizes, height); zero when outside.
static func box_push(pos: Vector3, r: float, c: Vector3, yaw: float, hx: float, hz: float, h: float) -> Vector3:
	var l := Basis(Vector3.UP, yaw).inverse() * (pos - c)
	if l.y > h + r or l.y < -r:
		return Vector3.ZERO
	var closest := Vector3(clampf(l.x, -hx, hx), 0.0, clampf(l.z, -hz, hz))
	var off := Vector2(l.x - closest.x, l.z - closest.z)
	var lp := Vector3.ZERO
	if off.length() > 0.0001:
		if off.length() < r:
			lp = Vector3(off.x, 0.0, off.y).normalized() * (r - off.length())
	else:
		var dx := hx - absf(l.x)
		var dz := hz - absf(l.z)
		lp = Vector3(signf(l.x) * (dx + r), 0.0, 0.0) if dx < dz else Vector3(0.0, 0.0, signf(l.z) * (dz + r))
	return Basis(Vector3.UP, yaw) * lp

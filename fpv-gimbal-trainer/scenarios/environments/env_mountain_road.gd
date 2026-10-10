class_name EnvMountainRoad
extends EnvironmentBuilder
## Mountain road (tag "route_montagne"): a hillside climbing along +Z with steep valley walls, an
## asphalt road laid along the subject's path (the terrain is flattened under it), posts along the
## road, pines on the valley sides, rocks beyond the outer edge of each bend, and - when the path
## has a long straight section - a tunnel: the drone flies over the hill, so the subject vanishes
## completely for a few seconds.

const ROAD_HALF_WIDTH := 3.5
const TUNNEL_HALF := 30.0
const TUNNEL_R := 7.5
## Fixed scenario drone: the camera swings around the road (see legacy_drone_path).
const LEGACY_LATERAL := 14.0
const LEGACY_LONGITUDINAL := 11.0
const LEGACY_HEIGHT_MIN := 3.5
const LEGACY_HEIGHT_MAX := 12.0
const LEGACY_MIN_DISTANCE := 9.0
## Chase-and-climb path used over the tunnel.
const CHASE_DISTANCE := 16.0
const CHASE_HEIGHT := 4.5
const TUNNEL_LIFT := 9.0

var _road: RoadBuilder
var _coarse := PackedVector3Array()  # the path the road was built on
var _dense := PackedVector3Array()   # the same road, every 2 m
var _tunnel_active := false
var _tunnel_center := Vector3.ZERO  # on the road surface
var _tunnel_dir := Vector3.RIGHT    # horizontal unit vector along the axis
var _tunnel_right := Vector3.BACK
var _s_in := 0.0
var _s_out := 0.0
var _drift_event := -1.0
var _ground_params := {}


func configure() -> void:
	surface_offset = 0.12
	corridor_half_width = ROAD_HALF_WIDTH


func base_height(x: float, z: float) -> float:
	var wall := 0.012 * pow(maxf(0.0, absf(x) - 62.0), 2.0)
	return 0.16 * z + 2.0 * sin(x * 0.05 + 1.0) * sin(z * 0.045) + 1.0 * sin(x * 0.12) * cos(z * 0.1) + wall


func ground(x: float, z: float) -> float:
	if _road == null:
		return base_height(x, z)
	return _road.blend_height(x, z, base_height(x, z), 7.5, 15.0)


func grass_params() -> Dictionary:
	var p := _ground_params.duplicate()
	p.merge({"height": 0.26, "density": 0.9, "flowers": 0.12, "max_slope": 0.22})
	return p


## Valley walls rising to high snowy mountains.
func far_scenery() -> Dictionary:
	return {"ring_radius": 1600.0, "ring_cell": 30.0,
		"hills": {"height": 1900.0, "r0": 1800.0, "r1": 6500.0, "frequency": 0.0009, "snow_line": 1500.0,
			"tree_line": 1000.0, "forest": Color(0.08, 0.17, 0.08), "grass": Color(0.34, 0.38, 0.18)},
		"trees": {"kind": "conifer", "count": 1300, "r0": 160.0, "r1": 1000.0, "colour": Color(0.1, 0.28, 0.14),
			"grove": 0.0},
		"canopy": {"r0": 140.0, "height": 16.0, "colour": Color(0.07, 0.19, 0.09), "grove": 0.15}}


## Outside the playing area the valley walls stop steepening: a U-shaped glacial valley whose sides ease to about
## 30 degrees (grass and forest), up to the high mountains of the far scenery. Same height as the terrain up to
## its edge (|x| = 140).
func far_height(x: float, z: float) -> float:
	var d := maxf(0.0, absf(x) - 62.0)
	if d <= 78.0:
		return base_height(x, z)
	var e := d - 78.0
	var wall := 0.012 * 78.0 * 78.0 + 0.6 * e + 1.27 * 50.0 * (1.0 - exp(-e / 50.0))
	return 0.16 * z + 2.0 * sin(x * 0.05 + 1.0) * sin(z * 0.045) + 1.0 * sin(x * 0.12) * cos(z * 0.1) + wall


func occluder_kind() -> String:
	return "trees"


func build_terrain(path: PackedVector3Array, _plan: Dictionary) -> void:
	_coarse = path.duplicate()
	var dense := RoadBuilder.sample_curve(host.make_curve(path), 2.0)
	_dense = dense
	_road = RoadBuilder.new(dense)
	var b := PathUtil.bounds_xz(path)

	var z0 := b.position.y - 60.0
	var z1 := b.end.y + 85.0
	var mi := MeshInstance3D.new()
	mi.name = "Terrain"
	mi.mesh = TerrainBuilder.build(Callable(self, "ground"), 140.0, z0, z1, 3.0)
	# alpine pasture, rock on the steep valley walls
	_ground_params = {"grass_a": Color(0.2, 0.3, 0.1), "grass_b": Color(0.38, 0.44, 0.17),
			"dry": Color(0.55, 0.5, 0.3), "dry_amount": 0.5, "dirt_amount": 0.2, "rock_start": 0.26, "rock_end": 0.44,
			"rock_a": Color(0.5, 0.48, 0.45), "rock_b": Color(0.27, 0.26, 0.25), "fringe_color": Color(0.45, 0.42, 0.36)}
	var mat := GroundMaterials.terrain(_ground_params)
	mi.material_override = mat
	host.add_child(mi)
	terrain_rect = Rect2(-140.0, z0, 280.0, z1 - z0)
	terrain_material = mat
	ground_mask = GroundMask.new()
	ground_mask.setup(terrain_rect)
	ground_mask.add_band(dense, ROAD_HALF_WIDTH + 2.2, Color(0, 0, 1))
	ground_mask.add_band(dense, ROAD_HALF_WIDTH + 0.5, Color(1, 0, 1))
	host.add_child(ground_mask)
	ground_mask.bind(mat)

	var asphalt := MeshInstance3D.new()
	asphalt.mesh = RoadBuilder.build_ribbon(dense, ROAD_HALF_WIDTH, 0.12)
	asphalt.material_override = GroundMaterials.asphalt({"half_width": ROAD_HALF_WIDTH, "base": Color(0.17, 0.17, 0.18)})
	asphalt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	host.add_child(asphalt)
	var line := MeshInstance3D.new()
	line.mesh = RoadBuilder.build_dashes(dense, 0.09, 0.14, 3, 3)
	line.material_override = GroundMaterials.paint()
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	host.add_child(line)

	_build_tunnel(path)


func populate(_path: PackedVector3Array, _drone: PackedVector3Array, _plan: Dictionary, legacy: bool) -> void:
	# Built on the original (coarse) path, even when the scenario later densifies its own copy
	var path := _coarse
	var dense := _dense
	var b := PathUtil.bounds_xz(path)

	# Roadside posts (not inside the tunnel)
	var post := BoxMesh.new()
	post.size = Vector3(0.14, 0.8, 0.14)
	post.material = PathSubject.make_mat(Color(0.92, 0.92, 0.9), 0.7)
	var posts: Array[Transform3D] = []
	for i in range(0, dense.size() - 1, 4):
		var p := dense[i]
		if _tunnel_active:
			var rel := p - _tunnel_center
			if absf(rel.dot(_tunnel_right)) < 10.0 and absf(rel.dot(_tunnel_dir)) < TUNNEL_HALF + 3.0:
				continue
		var t := dense[i + 1] - p
		t.y = 0.0
		var r := t.normalized().cross(Vector3.UP)
		for side in [-1.0, 1.0]:
			posts.append(Transform3D(Basis(), p + r * side * (ROAD_HALF_WIDTH + 0.9) + Vector3(0, 0.4, 0)))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = post
	mm.instance_count = posts.size()
	for i in posts.size():
		mm.set_instance_transform(i, posts[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	host.add_child(mmi)

	var rng := RandomNumberGenerator.new()
	rng.seed = 5 + host.world_seed

	# Pines on the valley sides, never in the drone's flight (a far drone of a generated session crosses them)
	var grounds := PackedVector3Array()
	var scales := PackedFloat32Array()
	var flight := PackedVector2Array()
	if not legacy:
		for i in range(0, _drone.size(), 3):
			flight.append(Vector2(_drone[i].x, _drone[i].z))
	for i in 90:
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var x := side * rng.randf_range(68.0, 125.0)
		var z := rng.randf_range(b.position.y - 40.0, b.end.y + 65.0)
		var g := Vector3(x, ground(x, z), z)
		var s := rng.randf_range(1.0, 1.8)
		if _near_points(flight, x, z, 6.0 + 3.0 * s):
			continue
		grounds.append(g)
		scales.append(s)
		host.add_tree_occluder(g, s)
	PropFactory.build_forest(host, grounds, scales, Color(0.1, 0.28, 0.14), 3)

	if not legacy:
		var count := roundi(float(host.matrix.params.occlusion) * 4.0)
		var fr: Array = []
		for k in count:
			fr.append((k + 1.0) / (count + 1.0))
		host.add_los_occluders(fr)

	# Stones and boulders on the slopes (the big ones far from the road and off the lines of sight, so they never
	# hide the car)
	var los := PackedVector2Array()
	for i in range(0, mini(_path.size(), _drone.size()), 2):
		los.append(Vector2(_path[i].x, _path[i].z))
		los.append(Vector2(_drone[i].x, _drone[i].z))
	var srng := RandomNumberGenerator.new()
	srng.seed = 960 + host.world_seed
	var stones := PackedVector3Array()
	var sizes := PackedFloat32Array()
	for i in roundi(340 * GraphicsSettings.detail_amount()):
		var x := srng.randf_range(-135.0, 135.0)
		var z := srng.randf_range(b.position.y - 55.0, b.end.y + 80.0)
		var d := _road.nearest(x, z).x
		var big := srng.randf() < 0.15
		if d < ROAD_HALF_WIDTH + (14.0 if big else 2.5) or near_drone_start(x, z):
			continue
		if big and _near_segments(los, x, z, 4.0):
			continue
		stones.append(Vector3(x, ground(x, z), z))
		sizes.append(srng.randf_range(1.0, 1.9) if big else srng.randf_range(0.2, 0.8))
	Rocks.scatter(host, stones, sizes, 961 + host.world_seed)

	# Rocks beyond the outer edge of each bend (the extremes of the road across the slope)
	for i in range(1, path.size() - 1):
		if (path[i].x - path[i - 1].x) * (path[i + 1].x - path[i].x) >= 0.0:
			continue
		var dir := signf(path[i].x)
		var x := path[i].x + dir * (9.0 + rng.randf_range(0.0, 5.0))
		var z := path[i].z + rng.randf_range(-4.0, 4.0)
		var g := Vector3(x, ground(x, z), z)
		var size := Vector3(rng.randf_range(2.0, 3.2), rng.randf_range(1.8, 3.0), rng.randf_range(2.0, 3.5))
		PropFactory.add_rock(host, g, size)
		host.add_cylinder_occluder(g, maxf(size.x, size.z) * 0.9, size.y * 1.4)


# --- Tunnel ----------------------------------------------------------------------------------------

## Straight sections of the (coarse) path: runs of points whose heading stays within 1.5 degrees.
func _straight_sections(path: PackedVector3Array, min_len: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var n := path.size()
	if n < 3:
		return out
	var i0 := 0
	var h0 := _heading(path, 0)
	for i in range(1, n - 1):
		if absf(h0.angle_to(_heading(path, i))) > deg_to_rad(1.5):
			_close_section(out, path, i0, i, min_len)
			i0 = i
			h0 = _heading(path, i)
	_close_section(out, path, i0, n - 1, min_len)
	return out


func _heading(path: PackedVector3Array, i: int) -> Vector2:
	return Vector2(path[i + 1].x - path[i].x, path[i + 1].z - path[i].z).normalized()


func _close_section(out: Array[Dictionary], path: PackedVector3Array, i0: int, i1: int, min_len: float) -> void:
	var d := path[i1] - path[i0]
	d.y = 0.0
	if d.length() >= min_len:
		out.append({"center": (path[i0] + path[i1]) * 0.5, "dir": d.normalized()})


func _build_tunnel(path: PackedVector3Array) -> void:
	var sections := _straight_sections(path, 2.0 * TUNNEL_HALF + 6.0)
	if sections.is_empty():
		return
	var sec: Dictionary = sections[mini(2, sections.size() - 1)]
	var c: Vector3 = sec.center
	_tunnel_dir = sec.dir
	_tunnel_right = _tunnel_dir.cross(Vector3.UP)
	_tunnel_center = Vector3(c.x, _road.nearest(c.x, c.z).y, c.z)
	_tunnel_active = true

	var hull := CylinderMesh.new()
	hull.top_radius = TUNNEL_R
	hull.bottom_radius = TUNNEL_R
	hull.height = TUNNEL_HALF * 2.0
	hull.radial_segments = 24
	hull.cap_top = false
	hull.cap_bottom = false
	var mat := PathSubject.make_mat(Color(0.3, 0.29, 0.27), 0.95)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := MeshInstance3D.new()
	mi.mesh = hull
	mi.material_override = mat
	mi.position = _tunnel_center
	mi.basis = Basis(Quaternion(Vector3.UP, _tunnel_dir))
	host.add_child(mi)
	_build_tunnel_hill()

	# Arc lengths of the entry / exit along the (coarse) path
	var cum := PathUtil.cumulative(path)
	var first := true
	for i in path.size():
		var rel := path[i] - _tunnel_center
		if absf(rel.dot(_tunnel_right)) < 1.0 and absf(rel.dot(_tunnel_dir)) <= TUNNEL_HALF + 0.01:
			if first:
				_s_in = cum[i]
				first = false
			_s_out = cum[i]
	_drift_event = PathUtil.index_at(cum, (_s_in + _s_out) * 0.5) / float(path.size() - 1)


## Seen from outside the tunnel is a grassy / rocky hill with a concrete portal at each end, not a tube. The hill
## stays below the heights the drone already keeps away from (clearance: the hull top within TUNNEL_R + 3 m of the
## axis, at least 3 m above the ground elsewhere), so the planned flights do not change.
func _build_tunnel_hill() -> void:
	var cy := _tunnel_center.y
	var cell := 1.5
	var na := ceili(44.0 / cell)
	var nl := ceili(TUNNEL_HALF * 2.0 / cell)
	var grid := []
	for il in nl + 1:
		var along := -TUNNEL_HALF + TUNNEL_HALF * 2.0 * il / nl
		var row := PackedVector3Array()
		for ia in na + 1:
			var a := -22.0 + 44.0 * ia / na
			var p := _tunnel_center + _tunnel_dir * along + _tunnel_right * a
			row.append(Vector3(p.x, _hill_height(a, ground(p.x, p.z), cy), p.z))
		grid.append(row)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for il in nl:
		var r0: PackedVector3Array = grid[il]
		var r1: PackedVector3Array = grid[il + 1]
		for ia in na:
			_tri_up(st, r0[ia], r0[ia + 1], r1[ia])
			_tri_up(st, r0[ia + 1], r1[ia + 1], r1[ia])
	st.generate_normals()
	var hill := MeshInstance3D.new()
	hill.name = "TunnelHill"
	hill.mesh = st.commit()
	hill.material_override = terrain_material
	host.add_child(hill)

	# portals: the cross-section of the hill at each end, with the arch of the tube cut out
	var concrete := PathSubject.make_mat(Color(0.58, 0.57, 0.53), 0.9)
	concrete.cull_mode = BaseMaterial3D.CULL_DISABLED
	var pst := SurfaceTool.new()
	pst.begin(Mesh.PRIMITIVE_TRIANGLES)
	for end in [-1.0, 1.0]:
		var row: PackedVector3Array = grid[0 if end < 0.0 else nl]
		var cols := []
		for ia in na + 1:
			var a := -22.0 + 44.0 * ia / na
			var top: Vector3 = row[ia] + _tunnel_dir * end * 0.15
			var g := ground(top.x, top.z)
			var bottom := cy + sqrt(TUNNEL_R * TUNNEL_R - a * a) if absf(a) < TUNNEL_R else g - 1.0
			if top.y > bottom + 0.05:
				cols.append([Vector3(top.x, bottom, top.z), top])
			else:
				cols.append([])
		for k in cols.size() - 1:
			if cols[k].is_empty() or cols[k + 1].is_empty():
				continue
			var b0: Vector3 = cols[k][0]
			var t0: Vector3 = cols[k][1]
			var b1: Vector3 = cols[k + 1][0]
			var t1: Vector3 = cols[k + 1][1]
			for v in [b0, t0, b1, b1, t0, t1]:
				pst.set_normal(_tunnel_dir * end)
				pst.add_vertex(v)
	var portals := MeshInstance3D.new()
	portals.name = "TunnelPortals"
	portals.mesh = pst.commit()
	portals.material_override = concrete
	host.add_child(portals)


## Height of the hill over the tunnel at `a` metres from its axis (ground g, road level cy at the centre).
func _hill_height(a: float, g: float, cy: float) -> float:
	var aa := absf(a)
	var h: float
	if aa <= TUNNEL_R + 3.0:
		h = cy + 2.5 + (TUNNEL_R + 1.8 - 2.5) * pow(1.0 - pow(aa / (TUNNEL_R + 3.0), 2.0), 0.8)
	else:
		var f := 1.0 - smoothstep(TUNNEL_R + 3.0, 22.0, aa)
		h = minf(cy + 2.5 * f, g + 2.0 * f - 0.3 * (1.0 - f))
	return maxf(h, g - 0.3)


## True if (x, z) is within r metres of one of the segments (pairs of points) of `segs`.
static func _near_segments(segs: PackedVector2Array, x: float, z: float, r: float) -> bool:
	var q := Vector2(x, z)
	for k in range(0, segs.size() - 1, 2):
		var a := segs[k]
		var ab := segs[k + 1] - a
		var l2 := ab.length_squared()
		var t := 0.0 if l2 < 0.0001 else clampf((q - a).dot(ab) / l2, 0.0, 1.0)
		if q.distance_squared_to(a + ab * t) < r * r:
			return true
	return false


## True if (x, z) is within r metres of the polyline `pts`.
static func _near_points(pts: PackedVector2Array, x: float, z: float, r: float) -> bool:
	var q := Vector2(x, z)
	for k in range(pts.size() - 1):
		var a := pts[k]
		var ab := pts[k + 1] - a
		var l2 := ab.length_squared()
		var t := 0.0 if l2 < 0.0001 else clampf((q - a).dot(ab) / l2, 0.0, 1.0)
		if q.distance_squared_to(a + ab * t) < r * r:
			return true
	return false


## Adds a triangle facing up (clockwise seen from above, the front face for the renderer).
static func _tri_up(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	if (b - a).cross(c - a).y > 0.0:
		var tmp := b
		b = c
		c = tmp
	for v in [a, b, c]:
		st.add_vertex(v)


func _in_tunnel(p: Vector3) -> bool:
	var rel := p - _tunnel_center
	if absf(rel.dot(_tunnel_dir)) > TUNNEL_HALF:
		return false
	return Vector2(rel.y, rel.dot(_tunnel_right)).length() < TUNNEL_R


## The segment is blocked when it crosses the lateral hull of the tunnel (not its open ends).
func extra_occlusion(from: Vector3, to: Vector3) -> bool:
	if not _tunnel_active:
		return false
	var steps := maxi(48, int(from.distance_to(to) / 0.15))
	var prev_in := _in_tunnel(from)
	var prev := from
	for i in range(1, steps + 1):
		var p := from.lerp(to, i / float(steps))
		var now_in := _in_tunnel(p)
		if now_in != prev_in:
			# Crossing the lateral hull, not the open end (with a small margin at the rim)
			var outside := prev if prev_in else p
			if absf((outside - _tunnel_center).dot(_tunnel_dir)) <= TUNNEL_HALF - 0.4:
				return true
		prev_in = now_in
		prev = p
	return false


## Over the tunnel the drone follows the chase-and-climb path (behind the subject, over the hill)
## so that the subject is hidden by the hull; elsewhere its path is untouched.
func adjust_drone_path(drone: PackedVector3Array, path: PackedVector3Array) -> PackedVector3Array:
	if not _tunnel_active:
		return drone
	var cum := PathUtil.cumulative(path)
	var out := PackedVector3Array()
	# The transitions last about 4 s whatever the speed of the subject (the climb over the hill must not
	# be a jerk): their length in metres grows with the speed.
	var f := clampf(nominal_speed() * 6.0 / 24.0, 1.0, 4.0)
	for i in path.size():
		var sd := cum[i] - CHASE_DISTANCE
		var cp := PathUtil.polyline_at(path, cum, sd)
		var lift := TUNNEL_LIFT * smoothstep(_s_in - 8.0 - 16.0 * f, _s_in - 8.0, sd) \
				* (1.0 - smoothstep(_s_out - 4.0, _s_out - 4.0 + 14.0 * f, sd))
		var chase := cp + Vector3.UP * (CHASE_HEIGHT + lift)
		var w := smoothstep(_s_in - 22.0 - 23.0 * f, _s_in - 22.0, cum[i]) \
				* (1.0 - smoothstep(_s_out + 6.0, _s_out + 6.0 + 26.0 * f, cum[i]))
		out.append(drone[i].lerp(chase, w))
	return out


## The drone must also stay above the tunnel hull.
func clearance(x: float, z: float) -> float:
	var g := ground(x, z)
	if not _tunnel_active:
		return g
	var rel := Vector3(x - _tunnel_center.x, 0.0, z - _tunnel_center.z)
	if absf(rel.dot(_tunnel_dir)) < TUNNEL_HALF + 2.0 and absf(rel.dot(_tunnel_right)) < TUNNEL_R + 3.0:
		return maxf(g, _tunnel_center.y + TUNNEL_R)
	return g


## Keeps the drone above the tunnel hull when its path crosses it.
func _clear_tunnel(p: Vector3) -> Vector3:
	var rel := p - _tunnel_center
	if absf(rel.dot(_tunnel_dir)) < TUNNEL_HALF + 2.0 and absf(rel.dot(_tunnel_right)) < TUNNEL_R + 3.0:
		p.y = maxf(p.y, _tunnel_center.y + TUNNEL_R + 3.0)
	return p


# --- Fixed scenario ---------------------------------------------------------------------------------

## A "cameraman" flight that is NOT the road: around a corner-cutting version of the path the
## drone swings from side to side, moves ahead of and behind the subject and changes altitude.
func legacy_drone_path(path: PackedVector3Array) -> PackedVector3Array:
	var cum := PathUtil.cumulative(path)
	var total: float = cum[cum.size() - 1]
	var n := path.size()
	var out := PackedVector3Array()
	for i in n:
		var t: float = cum[i] / total
		var p := path[i]
		var avg := Vector3.ZERO
		var cnt := 0
		for j in range(maxi(0, i - 5), mini(n, i + 6)):
			avg += path[j]
			cnt += 1
		avg /= cnt
		var head := path[mini(n - 1, i + 3)] - path[maxi(0, i - 3)]
		head.y = 0.0
		head = head.normalized()
		var right := head.cross(Vector3.UP)
		var lat := LEGACY_LATERAL * sin(TAU * t * 3.3 + 0.8)
		var lon := -8.0 + LEGACY_LONGITUDINAL * sin(TAU * t * 1.7 + 0.3)
		var h := lerpf(LEGACY_HEIGHT_MIN, LEGACY_HEIGHT_MAX, 0.5 + 0.5 * sin(TAU * t * 2.1 + 2.0))
		var q := Vector3(avg.x, 0.0, avg.z) + right * lat + head * lon
		# Never closer than LEGACY_MIN_DISTANCE to the subject (seen from above)
		var away := Vector2(q.x - p.x, q.z - p.z)
		if away.length() < LEGACY_MIN_DISTANCE:
			var dir := away.normalized() if away.length() > 0.01 else Vector2(right.x, right.z)
			q.x = p.x + dir.x * LEGACY_MIN_DISTANCE
			q.z = p.z + dir.y * LEGACY_MIN_DISTANCE
		out.append(Vector3(q.x, ground(q.x, q.z) + h, q.z))
	return out


func legacy_drift() -> float:
	return 3.0


func legacy_drift_events() -> Array[float]:
	var out: Array[float] = []
	if _tunnel_active:
		out.append(_drift_event)
	return out


func hud_extra() -> String:
	if _tunnel_active:
		return "The drone swings around the road, ahead and behind. A tunnel hides the subject completely for a few seconds."
	return ""

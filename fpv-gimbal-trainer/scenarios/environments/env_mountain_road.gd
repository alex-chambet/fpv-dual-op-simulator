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


func occluder_kind() -> String:
	return "trees"


func build_terrain(path: PackedVector3Array, _plan: Dictionary) -> void:
	_coarse = path.duplicate()
	var dense := RoadBuilder.sample_curve(host.make_curve(path), 2.0)
	_dense = dense
	_road = RoadBuilder.new(dense)
	var b := PathUtil.bounds_xz(path)

	var mi := MeshInstance3D.new()
	mi.name = "Terrain"
	mi.mesh = TerrainBuilder.build(Callable(self, "ground"), 140.0, b.position.y - 60.0, b.end.y + 85.0, 3.0)
	mi.material_override = TerrainBuilder.make_material(Color(0.3, 0.33, 0.22), Color(0.55, 0.52, 0.42))
	host.add_child(mi)

	var asphalt := MeshInstance3D.new()
	asphalt.mesh = RoadBuilder.build_ribbon(dense, ROAD_HALF_WIDTH, 0.12)
	asphalt.material_override = PathSubject.make_mat(Color(0.16, 0.16, 0.18), 0.85)
	host.add_child(asphalt)
	var line := MeshInstance3D.new()
	line.mesh = RoadBuilder.build_dashes(dense, 0.09, 0.14, 3, 3)
	line.material_override = PathSubject.make_mat(Color(0.9, 0.9, 0.85), 0.8)
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

	# Pines on the valley sides
	var grounds := PackedVector3Array()
	var scales := PackedFloat32Array()
	for i in 90:
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var x := side * rng.randf_range(68.0, 125.0)
		var z := rng.randf_range(b.position.y - 40.0, b.end.y + 65.0)
		var g := Vector3(x, ground(x, z), z)
		var s := rng.randf_range(1.0, 1.8)
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
	var mat := PathSubject.make_mat(Color(0.38, 0.36, 0.33), 0.95)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := MeshInstance3D.new()
	mi.mesh = hull
	mi.material_override = mat
	mi.position = _tunnel_center
	mi.basis = Basis(Quaternion(Vector3.UP, _tunnel_dir))
	host.add_child(mi)

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

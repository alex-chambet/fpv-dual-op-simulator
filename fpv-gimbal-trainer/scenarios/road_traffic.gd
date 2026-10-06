class_name RoadTraffic
extends Node3D
## Moving traffic along a straight-ish road: oncoming cars, vans and trucks in the opposite lane, cyclists on the
## verges. Every vehicle's place is a function of the run time (host._run_time), so live runs and replays agree.
## The vehicles hide the subject (extra_occlusion) and are solid for the drone of the 2-player mode (push).
##
## Positions are given along the subject's line: s = arc length, `lateral` = metres to the right of that line.

class Vehicle:
	var node: Node3D
	var kind := "car"
	var dir := 1.0       # +1 drives with the subject, -1 comes towards it
	var speed := 0.0
	var s0 := 0.0
	var lateral := 0.0
	var half_len := 2.0
	var half_width := 0.9
	var height := 1.5
	# state at the last update
	var pos := Vector3.ZERO
	var yaw := 0.0
	var active := false

var host: ScenarioBase
var _pts := PackedVector3Array()
var _cum := PackedFloat32Array()
var _total := 0.0
var _vehicles: Array[Vehicle] = []
var _view := 650.0  # vehicles farther than this (along the road) from the subject are not shown


func setup(h: ScenarioBase, pts: PackedVector3Array, rng: RandomNumberGenerator, lane: float, right_edge: float,
		left_edge: float, run_time_max: float) -> void:
	host = h
	_pts = pts
	_cum = ScenarioBase.cumulative(pts)
	_total = _cum[_cum.size() - 1]
	var reach := 32.0 * run_time_max  # distance an oncoming vehicle travels during the run
	# Oncoming traffic: lane to the left of the subject's, one vehicle every ~130 m on average
	var s := -60.0
	while s < _total + reach:
		s += rng.randf_range(45.0, 220.0)
		var roll := rng.randf()
		var kind := "car" if roll < 0.62 else ("truck" if roll < 0.85 else "van")
		_add(kind, -1.0, rng.randf_range(20.0, 26.0), s, -lane, rng)
	# Cyclists in the verge to the right (same direction, slow) and a few on the left (coming)
	s = 120.0
	while s < _total:
		s += rng.randf_range(160.0, 420.0)
		_add("cyclist", 1.0, rng.randf_range(5.0, 8.0), s, right_edge + 0.8, rng)
	s = 200.0
	while s < _total + 300.0:
		s += rng.randf_range(300.0, 700.0)
		_add("cyclist", -1.0, rng.randf_range(5.0, 8.0), s, left_edge - 0.8, rng)
	host.add_child(self)


func _add(kind: String, dir: float, speed: float, s0: float, lateral: float, rng: RandomNumberGenerator) -> void:
	var m: Dictionary
	match kind:
		"truck": m = TrafficModels.truck(rng)
		"van": m = TrafficModels.van(rng)
		"cyclist": m = TrafficModels.cyclist(rng)
		_: m = TrafficModels.car(rng)
	var v := Vehicle.new()
	v.node = m.node
	v.kind = kind
	v.dir = dir
	v.speed = speed
	v.s0 = s0
	v.lateral = lateral
	v.half_len = m.half_len
	v.half_width = m.half_width
	v.height = m.height
	v.node.visible = false
	add_child(v.node)
	_vehicles.append(v)


## Place of a vehicle at run time t: Vector3 position and yaw (rotation about Y, model front = -Z).
func _place(v: Vehicle, t: float) -> void:
	var s := v.s0 + v.dir * v.speed * t
	var sc := clampf(s, 0.0, _total)
	var p := ScenarioBase.polyline_at(_pts, _cum, sc)
	var ahead := ScenarioBase.polyline_at(_pts, _cum, minf(sc + 3.0, _total))
	var behind := ScenarioBase.polyline_at(_pts, _cum, maxf(sc - 3.0, 0.0))
	var tang := ahead - behind
	tang.y = 0.0
	if tang.length() < 0.001:
		tang = Vector3(0, 0, 1)
	tang = tang.normalized()
	var right := tang.cross(Vector3.UP).normalized()
	v.pos = p + right * v.lateral
	v.pos.y = p.y + 0.12
	var heading := tang * v.dir
	v.yaw = atan2(-heading.x, -heading.z)
	v.active = s > -40.0 and s < _total + 40.0


func _process(_delta: float) -> void:
	if host == null or host.subject == null:
		return
	var t := host._run_time
	var s_subject := host.subject.progress_ratio * _total
	for v in _vehicles:
		_place(v, t)
		var s := v.s0 + v.dir * v.speed * t
		var show := v.active and absf(s - s_subject) < _view
		v.node.visible = show
		if show:
			v.node.position = v.pos
			v.node.rotation.y = v.yaw


## Vehicle states for queries (recomputed for the current run time, so it works before the first frame too).
func _current(v: Vehicle) -> void:
	_place(v, host._run_time)


## True when the segment from -> to crosses a vehicle (oriented box).
func blocks(from: Vector3, to: Vector3) -> bool:
	if host == null:
		return false
	var mid := (from + to) * 0.5
	var reach := from.distance_to(to) * 0.5 + 10.0
	for v in _vehicles:
		_current(v)
		if not v.active or Vector2(v.pos.x - mid.x, v.pos.z - mid.z).length() > reach + v.half_len:
			continue
		var basis := Basis(Vector3.UP, v.yaw)
		var inv := basis.inverse()
		var a := inv * (from - v.pos)
		var b := inv * (to - v.pos)
		if _segment_hits_box(a, b, Vector3(-v.half_width, 0.0, -v.half_len), Vector3(v.half_width, v.height, v.half_len)):
			return true
	return false


static func _segment_hits_box(a: Vector3, b: Vector3, lo: Vector3, hi: Vector3) -> bool:
	var d := b - a
	var t0 := 0.0
	var t1 := 1.0
	for axis in 3:
		if absf(d[axis]) < 0.00001:
			if a[axis] < lo[axis] or a[axis] > hi[axis]:
				return false
		else:
			var u0 := (lo[axis] - a[axis]) / d[axis]
			var u1 := (hi[axis] - a[axis]) / d[axis]
			if u0 > u1:
				var tmp := u0
				u0 = u1
				u1 = tmp
			t0 = maxf(t0, u0)
			t1 = minf(t1, u1)
			if t0 > t1:
				return false
	return true


## Horizontal push getting a sphere of radius r at `pos` out of the vehicles (zero if none).
func push(pos: Vector3, r: float) -> Vector3:
	if host == null:
		return Vector3.ZERO
	var best := Vector3.ZERO
	for v in _vehicles:
		_current(v)
		if not v.active or Vector2(v.pos.x - pos.x, v.pos.z - pos.z).length() > v.half_len + 6.0:
			continue
		var inv := Basis(Vector3.UP, v.yaw).inverse()
		var l := inv * (pos - v.pos)
		if l.y > v.height + r or l.y < -r:
			continue
		var closest := Vector3(clampf(l.x, -v.half_width, v.half_width), 0.0, clampf(l.z, -v.half_len, v.half_len))
		var off := Vector2(l.x - closest.x, l.z - closest.z)
		var local_push := Vector3.ZERO
		if off.length() > 0.0001:
			if off.length() < r:
				local_push = Vector3(off.x, 0.0, off.y).normalized() * (r - off.length())
		else:  # inside the footprint: out through the nearest face
			var dx := v.half_width - absf(l.x)
			var dz := v.half_len - absf(l.z)
			if dx < dz:
				local_push = Vector3(signf(l.x) * (dx + r), 0.0, 0.0)
			else:
				local_push = Vector3(0.0, 0.0, signf(l.z) * (dz + r))
		var world := Basis(Vector3.UP, v.yaw) * local_push
		if world.length() > best.length():
			best = world
	return best

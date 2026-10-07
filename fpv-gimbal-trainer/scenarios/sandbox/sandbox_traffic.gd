class_name SandboxTraffic
extends Node3D
## Endless traffic of the sandbox: cars, vans, trucks and cyclists drive around closed routes made of the roads of
## SandboxWorld (the ring road both ways, and loops through the village on roads A and B), on the right-hand side.
## Each vehicle keeps its distance to the one ahead and slows down in bends and in the village. Junctions follow the
## rules of the road: the ring road and road A have priority; a vehicle turning at a junction, or crossing road A on
## road B, gives way and only goes when the junction is clear. Vehicles are solid for the drone (push).

const VILLAGE_SPEED := 13.0
const ACCEL := 2.2
const BRAKE := 6.0

class Route:
	var pts := PackedVector3Array()   ## lane line (closed), y = road surface
	var cum := PackedFloat32Array()
	var total := 0.0
	var vmax := PackedFloat32Array()  ## speed limit at each point (bends, village)
	## junctions on the route: {j: index in world.junctions, s: arc length, yield: bool}
	var junctions: Array[Dictionary] = []

class Vehicle:
	var node: Node3D
	var route: Route
	var s := 0.0
	var v := 0.0
	var cruise := 20.0
	var cyclist := false
	var half_len := 2.0
	var half_width := 0.9
	var height := 1.5
	var pos := Vector3.ZERO
	var fwd := Vector3.FORWARD
	var wheels: Array = []

var world: SandboxWorld
var _routes: Array[Route] = []
var _vehicles: Array[Vehicle] = []
var _rng := RandomNumberGenerator.new()
## junction index -> the vehicle crossing it
var _owner := {}


func setup(w: SandboxWorld) -> void:
	world = w
	_rng.seed = SandboxWorld.SEED + 31
	var ring: PackedVector3Array = w.roads[0].pts
	var a: PackedVector3Array = w.roads[1].pts
	var b: PackedVector3Array = w.roads[2].pts
	var n := ring.size()
	var i_e := _nearest_index(ring, a[a.size() - 1])
	var i_w := _nearest_index(ring, a[0])
	var i_n := _nearest_index(ring, b[0])
	var i_s := _nearest_index(ring, b[b.size() - 1])
	var ring_fwd := ring
	var ring_back := _reversed(ring)
	# loops: (road part, then the ring back to its start)
	var loops := [
		ring_fwd,
		ring_back,
		_cat(a, _ring_walk(ring, i_e, i_w, -1)),
		_cat(_reversed(a), _ring_walk(ring, i_w, i_e, -1)),
		_cat(b, _ring_walk(ring, i_s, i_n, 1)),
		_cat(_reversed(b), _ring_walk(ring, i_n, i_s, 1)),
	]
	for l in loops:
		_routes.append(_make_route(l, LANE_OFFSET))
	var lane_routes := _routes.duplicate()
	# cars, vans and trucks, spread along each route
	for r in lane_routes:
		var count := maxi(2, int(r.total / 380.0))
		for k in count:
			var roll := _rng.randf()
			var m: Dictionary
			if roll < 0.7:
				m = TrafficModels.car(_rng)
			elif roll < 0.88:
				m = TrafficModels.van(_rng)
			else:
				m = TrafficModels.truck(_rng)
			_add(m, r, r.total * (k + _rng.randf_range(0.0, 0.5)) / count, _rng.randf_range(18.0, 23.0), false)
	# cyclists on the edge of the road, both ways on the ring, and through the village
	for idx in [0, 1, 2, 5]:
		var cr := _make_route(_raw_of(idx, ring_fwd, ring_back, a, b, ring, i_e, i_w, i_n, i_s), SandboxWorld.MAIN_HALF - 0.55)
		for k in 3:
			_add(TrafficModels.cyclist(_rng), cr, cr.total * (k + _rng.randf()) / 3.0, _rng.randf_range(5.0, 7.5), true)
	set_process(true)


const LANE_OFFSET := SandboxWorld.LANE * 0.5


func _raw_of(idx: int, rf: PackedVector3Array, rb: PackedVector3Array, a: PackedVector3Array, b: PackedVector3Array,
		ring: PackedVector3Array, i_e: int, i_w: int, i_n: int, i_s: int) -> PackedVector3Array:
	match idx:
		0: return rf
		1: return rb
		2: return _cat(a, _ring_walk(ring, i_e, i_w, -1))
		5: return _cat(_reversed(b), _ring_walk(ring, i_n, i_s, 1))
	return rf


static func _nearest_index(pts: PackedVector3Array, p: Vector3) -> int:
	var best := 0
	var bd := INF
	for i in pts.size():
		var d := Vector2(pts[i].x - p.x, pts[i].z - p.z).length()
		if d < bd:
			bd = d
			best = i
	return best


static func _reversed(pts: PackedVector3Array) -> PackedVector3Array:
	var out := pts.duplicate()
	out.reverse()
	return out


## Ring points from index i0 to i1 (excluded ends) walking in direction step (+1 / -1), wrapping around.
static func _ring_walk(ring: PackedVector3Array, i0: int, i1: int, step: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	var n := ring.size()
	var i := posmod(i0 + step, n)
	while i != i1:
		out.append(ring[i])
		i = posmod(i + step, n)
	return out


static func _cat(a: PackedVector3Array, b: PackedVector3Array) -> PackedVector3Array:
	var out := a.duplicate()
	out.append_array(b)
	return out


func _make_route(centre: PackedVector3Array, lateral: float) -> Route:
	var r := Route.new()
	r.pts = SandboxWorld.offset_line(centre, lateral, true)
	for i in r.pts.size():
		r.pts[i].y = world.ground(r.pts[i].x, r.pts[i].z) + 0.12
	var closed := r.pts.duplicate()
	closed.append(r.pts[0])
	r.cum = PathUtil.cumulative(closed)
	r.total = r.cum[r.cum.size() - 1]
	var n := r.pts.size()
	r.vmax.resize(n)
	for i in n:
		# radius of the bend from three points 6 m apart
		var p0 := r.pts[posmod(i - 3, n)]
		var p1 := r.pts[i]
		var p2 := r.pts[(i + 3) % n]
		var a := Vector2(p1.x - p0.x, p1.z - p0.z)
		var b := Vector2(p2.x - p1.x, p2.z - p1.z)
		var ang := absf(a.angle_to(b))
		var radius := (a.length() + b.length()) * 0.5 / maxf(ang, 0.0001)
		var lim := sqrt(2.6 * radius)
		if Vector2(p1.x, p1.z).length() < SandboxWorld.VILLAGE_R:
			lim = minf(lim, VILLAGE_SPEED)
		r.vmax[i] = lim
	# smooth the limits backwards so the vehicles brake before the bends
	for _pass in 2:
		for j in range(n - 1, -1, -1):
			var nxt: float = r.vmax[(j + 1) % n]
			var ds := r.cum[j + 1] - r.cum[j]
			r.vmax[j] = minf(r.vmax[j], sqrt(nxt * nxt + 2.0 * 2.5 * ds))
	_find_junctions(r)
	return r


func _add(m: Dictionary, r: Route, s: float, cruise: float, cyclist: bool) -> void:
	var v := Vehicle.new()
	v.node = m.node
	v.route = r
	v.s = fposmod(s, r.total)
	v.cruise = cruise
	v.v = cruise * 0.6
	v.cyclist = cyclist
	v.half_len = m.half_len
	v.half_width = m.half_width
	v.height = m.height
	_place(v)
	# not on top of another vehicle (routes share lanes): move along until the spot is free
	for _try in 40:
		var clash := world._near_junction(v.pos, 35.0)
		for o in _vehicles:
			if o.cyclist == cyclist and o.pos.distance_to(v.pos) < 14.0:
				clash = true
				break
		if not clash:
			break
		v.s = fposmod(v.s + 15.0, r.total)
		_place(v)
	add_child(v.node)
	for c in v.node.get_children():
		if c is MeshInstance3D and c.name != "CarBody" and absf(c.rotation.z - PI * 0.5) < 0.01:
			v.wheels.append(c)
	_place(v)
	_vehicles.append(v)


func _place(v: Vehicle) -> void:
	var r := v.route
	v.pos = _at(r, v.s)
	var ahead := _at(r, v.s + 2.5)
	var behind := _at(r, v.s - 2.5)
	var t := ahead - behind
	t.y = 0.0
	if t.length() > 0.001:
		v.fwd = t.normalized()
	v.node.position = v.pos
	v.node.rotation.y = atan2(-v.fwd.x, -v.fwd.z)


func _at(r: Route, s: float) -> Vector3:
	s = fposmod(s, r.total)
	var lo := 0
	var hi := r.cum.size() - 1
	while hi - lo > 1:
		var mid := (lo + hi) >> 1
		if r.cum[mid] <= s:
			lo = mid
		else:
			hi = mid
	var a := r.pts[lo % r.pts.size()]
	var b := r.pts[(lo + 1) % r.pts.size()]
	var seg := r.cum[lo + 1] - r.cum[lo]
	return a.lerp(b, (s - r.cum[lo]) / seg if seg > 0.0001 else 0.0)


func _limit_at(r: Route, s: float) -> float:
	var i := int(fposmod(s, r.total) / r.total * r.pts.size()) % r.pts.size()
	return r.vmax[i]


func _process(delta: float) -> void:
	if delta <= 0.0:
		return
	for v in _vehicles:
		var target := minf(v.cruise, _limit_at(v.route, v.s))
		var look := clampf(v.v * 0.6, 4.0, 20.0)
		target = minf(target, _limit_at(v.route, v.s + look))
		# keep the distance to the vehicle ahead (cars ignore the cyclists on the edge, and the other way)
		for o in _vehicles:
			if o == v or o.cyclist != v.cyclist or absf(o.pos.x - v.pos.x) > 92.0 or absf(o.pos.z - v.pos.z) > 92.0:
				continue
			var rel := o.pos - v.pos
			rel.y = 0.0
			var along := rel.dot(v.fwd)
			if along > 90.0 or along < -0.5 or (along <= 0.5 and o.get_instance_id() > v.get_instance_id()):
				continue  # (side by side: the older one goes first)
			if absf(rel.dot(v.fwd.cross(Vector3.UP))) > 1.8 or o.fwd.dot(v.fwd) < 0.3:
				continue
			# the speed from which it can still stop (or match the speed of the one ahead) with a margin
			var gap := along - v.half_len - o.half_len - 3.0 - 0.6 * v.v
			target = minf(target, sqrt(o.v * o.v + 2.0 * 4.5 * maxf(0.0, gap)) if gap > 0.0 else minf(o.v, maxf(0.0, gap + 3.0)))
		target = minf(target, _junction_limit(v))
		# last guard: never drive into anything just in front (merges, crossings)
		for o in _vehicles:
			if o == v or o.cyclist != v.cyclist or absf(o.pos.x - v.pos.x) > 14.0 or absf(o.pos.z - v.pos.z) > 14.0:
				continue
			var rel2 := o.pos - v.pos
			rel2.y = 0.0
			var ahead := rel2.dot(v.fwd)
			if ahead > 0.0 and ahead < v.half_len + o.half_len + 2.5 and absf(rel2.dot(v.fwd.cross(Vector3.UP))) < v.half_width + o.half_width + 0.6:
				target = 0.0
				if ahead < v.half_len + o.half_len + 1.0:
					v.v = 0.0
		var rate := ACCEL if target > v.v else BRAKE
		v.v = move_toward(v.v, target, rate * delta)
		v.s = fposmod(v.s + v.v * delta, v.route.total)
		_place(v)
		var spin := v.v * delta / 0.33
		for w in v.wheels:
			w.rotation.x += spin


## Finds the junctions a route goes through and whether it must give way there (it turns, or it is road B crossing
## road A in the village). Only the junctions of the ring road and the village crossroads carry traffic.
func _find_junctions(r: Route) -> void:
	var n := r.pts.size()
	for j in 5:
		var jp := world.junctions[j]
		var best := -1
		var bd := 7.0
		for i in n:
			var d := Vector2(r.pts[i].x - jp.x, r.pts[i].z - jp.y).length()
			if d < bd:
				bd = d
				best = i
		if best < 0:
			continue
		var before := r.pts[best] - r.pts[posmod(best - 8, n)]
		var after := r.pts[(best + 8) % n] - r.pts[best]
		var turns := absf(Vector2(before.x, before.z).angle_to(Vector2(after.x, after.z))) > 0.5
		var crossing_b := j == 4 and absf(before.z) > absf(before.x)
		r.junctions.append({"j": j, "s": r.cum[best], "yield": turns or crossing_b})


## Speed limit from the junctions ahead. A vehicle that must give way stops 11 m before the centre until the junction
## is clear (nothing inside, nothing coming within 70 m), then reserves it until it is 18 m past. A vehicle with
## priority only slows down if someone has already committed to the junction.
func _junction_limit(v: Vehicle) -> float:
	var lim := INF
	for e in v.route.junctions:
		var j: int = e.j
		var to := fposmod(float(e.s) - v.s, v.route.total)
		var passed := v.route.total - to
		if _owner.get(j) == v:
			if passed > 18.0 and to > 30.0:
				_owner.erase(j)
			continue
		if to > 60.0:
			continue
		if e.yield:
			if to < 10.0:
				continue  # already in it
			if _owner.get(j) == null and to < 14.0 and _clear(j, v):
				_owner[j] = v
				continue
			lim = minf(lim, sqrt(2.0 * 4.0 * maxf(0.0, to - 11.0)))
		elif _owner.has(j) and to > 8.0:
			lim = minf(lim, sqrt(2.0 * 4.0 * maxf(0.0, to - 15.0)))
	return lim


## Nothing in the junction j and nothing coming towards it within 70 m (vehicles waiting to give way do not count).
func _clear(j: int, me: Vehicle) -> bool:
	var jp := world.junctions[j]
	for o in _vehicles:
		if o == me:
			continue
		var rel := Vector2(jp.x - o.pos.x, jp.y - o.pos.z)
		var d := rel.length()
		if d < 8.0 or (d < 12.0 and o.v > 1.0):  # (vehicles waiting at the line do not count)
			return false
		if d < 70.0 and o.v > 2.0 and rel.dot(Vector2(o.fwd.x, o.fwd.z)) > 0.0:
			return false
	return true

## Horizontal push getting a sphere of radius r out of the vehicles.
func push(pos: Vector3, r: float) -> Vector3:
	var best := Vector3.ZERO
	for v in _vehicles:
		if Vector2(v.pos.x - pos.x, v.pos.z - pos.z).length() > v.half_len + 3.0:
			continue
		var p := SandboxWorld.box_push(pos, r, v.pos, v.node.rotation.y, v.half_width, v.half_len, v.height)
		if p.length() > best.length():
			best = p
	return best


func count() -> int:
	return _vehicles.size()

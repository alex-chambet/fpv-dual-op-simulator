class_name AutoFlight
extends RefCounted
## Random but always smooth flight of the sandbox drone, so a gimbal operator alone can try their settings.
##
## A generator makes an endless queue of waypoints, alternating
##  - "road" legs: follow a road of the village / countryside 6 - 11 m above it (a few metres off its axis),
##  - "free" legs: cross the countryside or the village at 16 - 45 m, towards a random spot.
## Every leg is checked against the buildings and trees (the queue only holds legs that are clear), the drone
## stays inside the map and never goes lower than MIN_AGL above the ground (after take-off).
##
## The drone is a point mass that follows the waypoints with a bounded acceleration, itself low-passed: the jerk is
## bounded, so the path has no sudden change of direction or speed (bends are rounded, the speed drops in sharp
## turns, climbs and descents are gentle). The first waypoint is straight above the take-off spot: the drone lifts
## off by itself.

const A_MAX := 3.2        ## horizontal acceleration limit, m/s2
const A_VERT := 1.8       ## vertical acceleration limit, m/s2
const ACC_TAU := 0.7      ## low-pass of the acceleration (s): bounds the jerk
const MIN_AGL := 4.0
const BOUND := 680.0

var world: SandboxWorld
var position := Vector3.ZERO
var velocity := Vector3.ZERO
var heading := 0.0
## Smoothed acceleration (m/s2), for the lean of the body.
var accel := Vector3.ZERO

var _rng := RandomNumberGenerator.new()
var _queue: Array[Dictionary] = []   # {p, speed, r}


## Starts at `pos`: lifting off from the ground (takeoff) or taking over a drone already flying with velocity `vel`.
func start(w: SandboxWorld, pos: Vector3, look: Vector3, takeoff := true, vel := Vector3.ZERO) -> void:
	world = w
	_rng.randomize()
	position = pos
	velocity = vel
	accel = Vector3.ZERO
	heading = atan2(-look.x, -look.z)
	_queue.clear()
	if takeoff:
		_queue.append({"p": pos + Vector3(0, 12.0, 0), "speed": 2.5, "r": 3.0})
	_extend()


func step(dt: float) -> void:
	if dt <= 0.0:
		return
	while _queue.size() < 8:
		_extend()
	var w: Dictionary = _queue[0]
	var to: Vector3 = w.p - position
	var to_h := Vector3(to.x, 0.0, to.z)
	var vel_h := Vector3(velocity.x, 0.0, velocity.z)
	var reach: float = maxf(float(w.r), vel_h.length() * 1.6)
	if to_h.length() < reach and absf(to.y) < 12.0 and _queue.size() > 1:
		_queue.pop_front()
		return step_target(dt)
	step_target(dt)


func step_target(dt: float) -> void:
	var w: Dictionary = _queue[0]
	var to: Vector3 = w.p - position
	var to_h := Vector3(to.x, 0.0, to.z)
	var vel_h := Vector3(velocity.x, 0.0, velocity.z)
	var dir := to_h.normalized() if to_h.length() > 0.01 else Vector3.ZERO
	# slower in sharp turns and close to the ground (take-off), never stopping
	var turn := 0.0
	if vel_h.length() > 1.0 and dir != Vector3.ZERO:
		turn = clampf(vel_h.angle_to(dir) / PI, 0.0, 1.0)
	var agl := position.y - world.ground(position.x, position.z)
	var factor := lerpf(1.0, 0.4, turn) * smoothstep(1.5, 7.0, agl)
	var want := dir * float(w.speed) * factor
	want.y = clampf(to.y * 0.5, -3.0, 3.5)
	var a_cmd := (want - velocity) / 0.9
	var ah := Vector2(a_cmd.x, a_cmd.z)
	if ah.length() > A_MAX:
		ah = ah.normalized() * A_MAX
	a_cmd = Vector3(ah.x, clampf(a_cmd.y, -A_VERT, A_VERT), ah.y)
	accel += (a_cmd - accel) * (1.0 - exp(-dt / ACC_TAU))
	velocity += accel * dt
	position += velocity * dt
	var floor_y := world.ground(position.x, position.z) + 0.15
	if position.y < floor_y:
		position.y = floor_y
		velocity.y = maxf(velocity.y, 0.0)
	var vh := Vector3(velocity.x, 0.0, velocity.z)
	if vh.length() > 1.5:
		var want_heading := atan2(-vh.x, -vh.z)
		heading = wrapf(heading + clampf(angle_difference(heading, want_heading), -1.0, 1.0) * (1.0 - exp(-dt / 0.5)), -PI, PI)


# --- Generator ------------------------------------------------------------------------------------------

func _last() -> Vector3:
	return _queue.back().p if not _queue.is_empty() else position


func _extend() -> void:
	for _try in 12:
		if _rng.randf() < 0.5:
			if _road_leg():
				return
		elif _free_leg():
			return
	# nothing clear found: climb straight up and try again from there
	var up: Vector3 = _last() + Vector3(0, 20.0, 0)
	_queue.append({"p": up, "speed": 4.0, "r": 6.0})


func _free_leg() -> bool:
	var a := _last()
	var x := clampf(a.x + _rng.randf_range(-420.0, 420.0), -BOUND, BOUND)
	var z := clampf(a.z + _rng.randf_range(-420.0, 420.0), -BOUND, BOUND)
	var p := Vector3(x, world.ground(x, z) + _rng.randf_range(16.0, 45.0), z)
	if Vector2(p.x - a.x, p.z - a.z).length() < 120.0 or not _clear(a, p):
		return false
	_queue.append({"p": p, "speed": _rng.randf_range(9.0, 16.0), "r": 16.0})
	return true


func _road_leg() -> bool:
	var candidates: Array[Dictionary] = []
	for r in world.roads:
		if r.kind != "track":
			candidates.append(r)
	var road: Dictionary = candidates[_rng.randi() % candidates.size()]
	var pts: PackedVector3Array = road.pts
	var n := pts.size()
	var a := _last()
	var best := 0
	var bd := INF
	for i in n:
		var d := Vector2(pts[i].x - a.x, pts[i].z - a.z).length()
		if d < bd:
			bd = d
			best = i
	var dir := 1 if _rng.randf() < 0.5 else -1
	var count := _rng.randi_range(6, 14)
	var height := _rng.randf_range(10.5, 14.0)  # just above the roofs (9 m) in the village
	var lateral := _rng.randf_range(-1.5, 1.5)
	var speed := _rng.randf_range(8.0, 13.0)
	var closed: bool = road.closed
	var leg: Array[Dictionary] = []
	var prev := a
	for k in count:
		var i := best + dir * k * 15
		if closed:
			i = posmod(i, n)
		elif i < 0 or i >= n:
			break
		var c := pts[i]
		var t := pts[mini(i + 3, n - 1) if not closed else (i + 3) % n] - pts[maxi(i - 3, 0) if not closed else posmod(i - 3, n)]
		t.y = 0.0
		var side := t.normalized().cross(Vector3.UP) if t.length() > 0.001 else Vector3.RIGHT
		# low in the village (no tall trees), above the crowns of the roadside plane trees outside it
		var h := height if Vector2(c.x, c.z).length() < SandboxWorld.VILLAGE_R + 20.0 else height + 9.0
		var p := Vector3(c.x, world.ground(c.x, c.z) + h, c.z) + side * lateral
		if absf(p.x) > BOUND or absf(p.z) > BOUND or not _clear(prev, p, 3.5 if h < 16.0 else 5.0):
			break
		leg.append({"p": p, "speed": speed, "r": 10.0})
		prev = p
	if leg.size() < 4:
		return false
	for e in leg:
		_queue.append(e)
	return true


## True if the straight leg a -> b is clear of buildings and trees (radius 5 m) and above the ground.
func _clear(a: Vector3, b: Vector3, radius := 5.0) -> bool:
	var len := a.distance_to(b)
	var steps := maxi(2, int(len / 4.0))
	for i in steps + 1:
		var p := a.lerp(b, float(i) / steps)
		if p.y < world.ground(p.x, p.z) + MIN_AGL and i > 0:
			return false
		if world.push(p, radius).length() > 0.0:
			return false
	return true

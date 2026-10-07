class_name FpvDrone
extends Node3D
## Freely flown FPV drone in ACRO mode (2-player mode). The sticks command angular RATES (no self-levelling),
## the throttle commands the thrust along the drone's own up axis: to move, you tilt the drone.
##   rates   : Betaflight-style curve (centre sensitivity + expo + max rate), followed with a short lag (PID loop)
##   thrust  : throttle^k * max_thrust, with motor lag; hover at `hover_throttle`
##   forces  : thrust along body up, gravity, linear + quadratic drag
##   contact : ground (or any "clearance" height), obstacles (callable), ceiling; hard hits count as crashes
## Everything is deterministic for a given sequence of (dt, inputs): sessions can be replayed.
## Body axes (Godot): forward = -Z, up = +Y, right = +X.

signal crashed(count: int)

const GRAVITY := 9.81

@export_group("Thrust")
## Acceleration (m/s²) at full throttle: 36 = thrust-to-weight 3.7 (a cinewhoop / light freestyle quad).
@export var max_thrust_accel := 36.0
## Throttle stick position (0..1) at which the drone hovers.
@export_range(0.2, 0.7, 0.01) var hover_throttle := 0.38
@export var thrust_lag := 0.05

@export_group("Rates")
## Roll and pitch: sensitivity around the centre and at full stick (deg/s).
@export var rp_center := 140.0
@export var rp_max := 520.0
@export var yaw_center := 110.0
@export var yaw_max := 380.0
@export_range(0.0, 1.0, 0.01) var rate_expo := 0.25
## Time constant of the angular rate following the command (s).
@export var rate_lag := 0.03

@export_group("Air")
@export var drag_linear := 0.15
@export var drag_quadratic := 0.018

@export_group("Body")
@export var radius := 0.15
@export var max_height := 150.0
## Hits harder than this (m/s) are crashes.
@export var crash_speed := 4.5

var velocity := Vector3.ZERO
var omega := Vector3.ZERO          ## body angular rate (rad/s)
var thrust := 0.0                  ## current thrust acceleration (m/s²)
var orientation := Quaternion.IDENTITY
var crash_count := 0
var grounded := false
## The motors only run once armed (see DuoSession): a disarmed drone stays where it is.
var armed := false
var heading := 0.0                 ## yaw of the drone (rad), used by the gimbal to follow it

## Callable(x, z) -> height below which the drone cannot go (ground, tunnel hull...). Invalid = flat ground at 0.
var ground_fn := Callable()
## Callable(position: Vector3, radius: float) -> Vector3: horizontal push that gets the drone out of an obstacle.
var obstacle_fn := Callable()

var _since_crash := 10.0
var _thr_exp := 1.0
var _fpv_cam: Camera3D


func _ready() -> void:
	_update_exponent()


func _update_exponent() -> void:
	var frac := clampf(GRAVITY / max_thrust_accel, 0.01, 0.99)
	_thr_exp = log(frac) / log(hover_throttle)


## Puts the drone at `pos`, nose towards the horizontal direction `dir`, at rest.
func reset_to(pos: Vector3, dir: Vector3) -> void:
	_update_exponent()
	position = pos
	velocity = Vector3.ZERO
	omega = Vector3.ZERO
	thrust = GRAVITY
	var d := Vector3(dir.x, 0.0, dir.z)
	if d.length() < 0.001:
		d = Vector3(0, 0, -1)
	d = d.normalized()
	orientation = Basis.looking_at(d, Vector3.UP).get_rotation_quaternion()
	heading = atan2(-d.x, -d.z)
	crash_count = 0
	_since_crash = 10.0
	_sync()


## Command rate (rad/s) for a stick value in -1..1.
func rate_for(stick: float, center: float, maxr: float) -> float:
	var x := (1.0 - rate_expo) * stick + rate_expo * stick * stick * stick
	return deg_to_rad(center * x + (maxr - center) * x * x * x)


## One frame. inputs = [throttle 0..1, yaw, pitch, roll] (sticks -1..1; pitch + = forward, yaw + = right, roll + = right).
func step(dt: float, inputs: Array) -> void:
	if dt <= 0.0 or not armed:
		return
	var n := maxi(1, ceili(dt / 0.004))
	var h := dt / n
	for _i in n:
		_substep(h, inputs)
	_since_crash += dt
	_update_heading(dt)
	_sync()


func _substep(h: float, inputs: Array) -> void:
	var thr := clampf(float(inputs[0]), 0.0, 1.0)
	var cmd := Vector3(
		-rate_for(float(inputs[2]), rp_center, rp_max),
		-rate_for(float(inputs[1]), yaw_center, yaw_max),
		-rate_for(float(inputs[3]), rp_center, rp_max))
	var k_rate := 1.0 - exp(-h / maxf(rate_lag, 0.001))
	omega = omega.lerp(cmd, k_rate)
	var rot := omega * h
	if rot.length() > 0.000001:
		orientation = (orientation * Quaternion(rot.normalized(), rot.length())).normalized()

	var k_thr := 1.0 - exp(-h / maxf(thrust_lag, 0.001))
	thrust = lerpf(thrust, pow(thr, _thr_exp) * max_thrust_accel, k_thr)
	var up := Basis(orientation).y
	var speed := velocity.length()
	var acc := up * thrust + Vector3(0.0, -GRAVITY, 0.0) - velocity * (drag_linear + drag_quadratic * speed)
	velocity += acc * h
	position += velocity * h
	_collide(h)


func _collide(h: float) -> void:
	grounded = false
	# obstacles
	if obstacle_fn.is_valid():
		var push: Vector3 = obstacle_fn.call(position, radius)
		if push.length() > 0.0001:
			var nrm := push.normalized()
			position += push
			var vn := velocity.dot(nrm)
			if vn < 0.0:
				if -vn > crash_speed:
					_crash()
				velocity -= nrm * vn * 1.2
				omega *= 0.5
	# ground
	var gy := 0.0
	if ground_fn.is_valid():
		gy = float(ground_fn.call(position.x, position.z))
	if position.y < gy + radius:
		position.y = gy + radius
		grounded = true
		if velocity.y < 0.0:
			var hard := -velocity.y > crash_speed or (Basis(orientation).y.y < 0.3 and velocity.length() > crash_speed)
			if hard:
				_crash()
			velocity.y = -velocity.y * 0.1 if hard else 0.0
		var fr := exp(-5.0 * h)
		velocity.x *= fr
		velocity.z *= fr
		omega *= exp(-8.0 * h)
		if velocity.length() < 2.0:  # lying on the ground: put the drone back on its feet (no turtle mode)
			var level := Basis.looking_at(_flat_forward(), Vector3.UP).get_rotation_quaternion()
			orientation = orientation.slerp(level, clampf(2.0 * h, 0.0, 1.0)).normalized()
	# ceiling
	if position.y > max_height:
		position.y = max_height
		velocity.y = minf(velocity.y, 0.0)


func _flat_forward() -> Vector3:
	var f := -Basis(orientation).z
	f.y = 0.0
	if f.length() < 0.1:
		f = Vector3(-sin(heading), 0.0, -cos(heading))
	return f.normalized()


func _crash() -> void:
	if _since_crash < 1.2:
		return
	_since_crash = 0.0
	crash_count += 1
	crashed.emit(crash_count)


## Yaw of the drone, robust when it points almost straight up / down; limited to 400 deg/s so a loop
## does not make the gimbal spin instantly.
func _update_heading(dt: float) -> void:
	var b := Basis(orientation)
	var f := -b.z
	var u := b.y
	var target := Vector2(f.x, f.z)
	if target.length() < 0.35:
		target = Vector2(u.x, u.z) * (1.0 if f.y < 0.0 else -1.0)
	if target.length() < 0.05:
		return
	var want := atan2(-target.x, -target.y)
	var maxstep := deg_to_rad(400.0) * dt
	heading = wrapf(heading + clampf(angle_difference(heading, want), -maxstep, maxstep), -PI, PI)


func _sync() -> void:
	if not is_inside_tree():
		return
	global_transform = Transform3D(Basis(orientation), position)
	if _fpv_cam != null and is_instance_valid(_fpv_cam) and _fpv_cam.is_inside_tree():
		var b := Basis(orientation) * Basis(Vector3.RIGHT, deg_to_rad(25.0))
		_fpv_cam.global_transform = Transform3D(b, position + Basis(orientation) * Vector3(0.0, 0.03, -0.12))


## Creates the pilot's FPV camera (wide, tilted up 25°) rendering into `viewport`.
func attach_fpv_camera(viewport: SubViewport) -> void:
	_fpv_cam = Camera3D.new()
	_fpv_cam.fov = 105.0
	_fpv_cam.near = 0.05
	viewport.add_child(_fpv_cam)
	_fpv_cam.add_child(MotionBlur.new())
	_fpv_cam.current = true
	_sync()


## Speed in km/h and height above the ground (m), for the pilot's OSD.
func speed_kmh() -> float:
	return velocity.length() * 3.6

class_name PathSubject
extends Path3D
## Base class of the tracked subject of a scenario. Follows its own Curve3D at a varying speed;
## the scenario calls advance(delta) each frame. ArchetypeSubject is the data-driven subclass
## used by every sport; _build_model() / _compute_speed() / _on_ready_done() / _on_advanced()
## are the extension points.

@export_range(0.5, 40.0, 0.1, "suffix:m/s") var base_speed := 8.0
## Speed oscillates by about +/- this much (m/s) on top of base_speed / speed_profile.
@export_range(0.0, 10.0, 0.1, "suffix:m/s") var speed_variation := 1.0
@export_range(0.05, 20.0, 0.05, "suffix:m/s") var min_speed := 2.0
@export_range(0.0, 60.0, 1.0, "suffix:°") var max_lean_deg := 0.0
@export_range(0.0, 2.0, 0.05) var lean_gain := 0.8
## Height above the model origin of the point the camera should frame.
@export_range(0.0, 3.0, 0.05, "suffix:m") var aim_height := 1.0
## Pitch the model with the slope of the path (vehicles, gliders) instead of staying level.
@export var follow_slope := false

## Optional speed by progress ratio (uniformly spaced samples, m/s), e.g. slower in tight turns.
var speed_profile := PackedFloat32Array()
## Optional Callable(x, z) -> ground height; the model is snapped on it (when the path is close to it).
var ground_height := Callable()
## The model is only snapped on the ground when the path is within this distance of it (m), so
## jumps and flights are not pulled back to the ground.
var snap_tolerance := 0.8

## How far ahead the subject "sees" its own path (s). An athlete prepares the next change of
## direction before it happens - he swings his pole, stands up, moves his knees across - and the
## operator reads what is coming in that preparation. Set to 0 for a subject that never anticipates.
@export_range(0.0, 1.5, 0.05, "suffix:s") var anticipation := 0.5

var speed_now := 0.0
var progress_ratio := 0.0
var finished := false
var lean_deg := 0.0
## The lean the path will ask for in `anticipation` seconds: same formula and same sign as lean_deg,
## read `anticipation` seconds further along the curve. This is what the body prepares for.
var lean_soon_deg := 0.0
## Vertical acceleration of the path (m/s², positive = pushed into the ground: a compression), used
## by an athlete to absorb a landing or a bump.
var heave_g := 0.0

var follower: PathFollow3D
var model: Node3D

var _t := 0.0
var _prev_yaw := 0.0
var _has_prev := false
var _prev_y := 0.0
var _prev_vy := 0.0


func _ready() -> void:
	follower = PathFollow3D.new()
	follower.rotation_mode = PathFollow3D.ROTATION_ORIENTED if follow_slope else PathFollow3D.ROTATION_Y
	follower.loop = false
	add_child(follower)
	model = _build_model()
	follower.add_child(model)
	_on_ready_done()


## World position of the point to frame.
func torso_position() -> Vector3:
	return model.global_position + Vector3.UP * aim_height


func advance(delta: float) -> void:
	if finished or delta <= 0.0:
		return
	_t += delta
	speed_now = _compute_speed(delta)
	follower.progress += speed_now * delta
	progress_ratio = follower.progress_ratio
	if progress_ratio >= 0.999:
		finished = true
		speed_now = 0.0

	# Lean into turns
	var fwd := -follower.global_transform.basis.z
	var yaw := atan2(-fwd.x, -fwd.z)
	var yaw_rate := 0.0
	if _has_prev:
		yaw_rate = angle_difference(_prev_yaw, yaw) / delta
	_prev_yaw = yaw
	_has_prev = true
	var target := _lean_for(yaw_rate)
	lean_deg = lerpf(lean_deg, target, 1.0 - exp(-delta / 0.15))
	model.rotation.z = deg_to_rad(lean_deg)
	lean_soon_deg = _lean_ahead()

	# vertical acceleration of the path: large and positive when the subject lands or crosses a dip
	var y := follower.global_position.y
	if _has_prev and delta > 0.0:
		var vy := (y - _prev_y) / delta
		heave_g = lerpf(heave_g, clampf((vy - _prev_vy) / delta, -80.0, 80.0), 1.0 - exp(-delta / 0.08))
		_prev_vy = vy
	_prev_y = y

	if ground_height.is_valid():
		var gp := follower.global_position
		var dy := float(ground_height.call(gp.x, gp.z)) - gp.y
		# not in the air: the flight would stay glued to the ground, then pop up by snap_tolerance
		model.position.y = dy if absf(dy) < snap_tolerance and not _in_air() else 0.0
	_on_advanced(delta)


## Bank angle (deg) that a yaw rate asks for at the current speed.
func _lean_for(yaw_rate: float) -> float:
	return clampf(rad_to_deg(atan2(speed_now * yaw_rate, 9.81)) * lean_gain, -max_lean_deg, max_lean_deg)


## Heading of the curve at arc length `s`, in the same convention as the follower's.
func _path_yaw(s: float) -> float:
	var total := curve.get_baked_length()
	var a := curve.sample_baked(clampf(s - 1.0, 0.0, total))
	var b := curve.sample_baked(clampf(s + 1.0, 0.0, total))
	var d := b - a
	if Vector2(d.x, d.z).length() < 0.0001:
		return _prev_yaw
	return atan2(-d.x, -d.z)


## The lean the curve will ask for `anticipation` seconds further on, measured exactly like the
## current one (same yaw convention, same formula), so the two can be compared.
func _lean_ahead() -> float:
	if curve == null or curve.get_baked_length() < 4.0 or anticipation <= 0.0 or speed_now < 0.5:
		return lean_deg
	var s := follower.progress + speed_now * anticipation
	var h := clampf(speed_now * 0.12, 0.8, 4.0)
	return _lean_for(angle_difference(_path_yaw(s - h), _path_yaw(s + h)) / (2.0 * h / speed_now))


## True during a jump (the model follows the path, not the ground).
func _in_air() -> bool:
	return false


## Nominal speed: base_speed / speed_profile plus the slow oscillation (speed_variation).
func default_speed() -> float:
	return maxf(min_speed, _profile_speed() + speed_variation * 0.7 * sin(_t * 0.45)
			+ speed_variation * 0.3 * sin(_t * 1.1 + 1.0))


func _profile_speed() -> float:
	if speed_profile.size() < 2:
		return base_speed
	var f := clampf(progress_ratio, 0.0, 1.0) * (speed_profile.size() - 1)
	var i := mini(int(f), speed_profile.size() - 2)
	return lerpf(speed_profile[i], speed_profile[i + 1], f - i)


## Override to change how the speed is computed each frame.
func _compute_speed(_delta: float) -> float:
	return default_speed()


func _build_model() -> Node3D:
	return Node3D.new()


func _on_ready_done() -> void:
	pass


func _on_advanced(_delta: float) -> void:
	pass


static func make_mat(c: Color, rough := 0.8) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m

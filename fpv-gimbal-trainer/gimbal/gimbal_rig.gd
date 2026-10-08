class_name GimbalRig
extends Node3D
## Gimbal handheld model (Ronin RS3 Pro style).
## Pipeline per axis: input -> smoothing (SmoothTrack) -> target speed (profile)
## -> angular acceleration limited by rise/fall time (BLDC feel) -> angle -> limits.
## Pan is applied on the rig (outer yaw), tilt then roll on the Camera3D child
## (true gimbal order: yaw -> pitch -> roll).
## Sign convention for inputs / angles: pan + = right, tilt + = up, roll + = clockwise.

enum SpeedProfile { SLOW, MEDIUM, FAST }

## Speed profile every new gimbal starts with (keys 1 / 2 / 3 change it): Medium by default, then the last one chosen,
## kept in the menu preferences. -1 = not read yet.
static var default_profile := -1
const PREFS_PATH := "user://menu_prefs.json"


static func load_default_profile() -> int:
	if default_profile < 0:
		default_profile = SpeedProfile.MEDIUM
		if FileAccess.file_exists(PREFS_PATH):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(PREFS_PATH))
			if typeof(parsed) == TYPE_DICTIONARY and parsed.has("gimbal_profile"):
				default_profile = clampi(int(parsed["gimbal_profile"]), 0, SpeedProfile.FAST)
	return default_profile


## Remembers the profile chosen by the player for the next sessions.
static func save_default_profile(p: int) -> void:
	default_profile = p
	var prefs := {}
	if FileAccess.file_exists(PREFS_PATH):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(PREFS_PATH))
		if typeof(parsed) == TYPE_DICTIONARY:
			prefs = parsed
	prefs["gimbal_profile"] = p
	var f := FileAccess.open(PREFS_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(prefs, "\t"))

@export_group("Stabilization")
## true: camera orientation is world-fixed, unaffected by the parent's rotation
## (drone turns, banks, pitches). Pan 0 = heading of the parent at start / recenter.
## false: the rig is rigidly attached to its parent.
@export var stabilized := true

@export_group("Input")
@export var use_controller := true
@export var use_keyboard := true
## 0 = raw input, 1 = very heavy smoothing (SmoothTrack-like low-pass on the stick signal).
@export_range(0.0, 1.0, 0.01) var input_smoothing := 0.25
## Low-pass time constant (s) reached when input_smoothing = 1.
@export_range(0.05, 3.0, 0.05, "suffix:s") var smoothing_max_time := 0.8

@export_group("Pan")
@export var pan_profile: SpeedProfile = SpeedProfile.SLOW
## Max speed (deg/s) for Slow / Medium / Fast.
@export var pan_speeds := Vector3(60.0, 150.0, 345.0)
## Time to reach full speed from rest.
@export_range(0.02, 3.0, 0.01, "suffix:s") var pan_rise_time := 0.15
## Time to stop from full speed.
@export_range(0.02, 3.0, 0.01, "suffix:s") var pan_fall_time := 0.1
@export var pan_limited := false
@export_range(-180.0, 180.0, 0.5, "suffix:°") var pan_min := -90.0
@export_range(-180.0, 180.0, 0.5, "suffix:°") var pan_max := 90.0

@export_group("Tilt")
@export var tilt_profile: SpeedProfile = SpeedProfile.SLOW
@export var tilt_speeds := Vector3(45.0, 110.0, 253.0)
@export_range(0.02, 3.0, 0.01, "suffix:s") var tilt_rise_time := 0.15
@export_range(0.02, 3.0, 0.01, "suffix:s") var tilt_fall_time := 0.1
@export var tilt_limited := true
@export_range(-90.0, 90.0, 0.5, "suffix:°") var tilt_min := -85.0
@export_range(-90.0, 90.0, 0.5, "suffix:°") var tilt_max := 85.0

@export_group("Roll")
@export var roll_profile: SpeedProfile = SpeedProfile.SLOW
@export var roll_speeds := Vector3(20.0, 50.0, 115.0)
@export_range(0.02, 3.0, 0.01, "suffix:s") var roll_rise_time := 0.2
@export_range(0.02, 3.0, 0.01, "suffix:s") var roll_fall_time := 0.15
@export var roll_limited := true
@export_range(-180.0, 180.0, 0.5, "suffix:°") var roll_min := -15.0
@export_range(-180.0, 180.0, 0.5, "suffix:°") var roll_max := 15.0

@export_group("Keyboard")
## Arrows / WASD = pan & tilt, Q / E = roll.
@export var keyboard_enabled_keys := true

# Axis indices
const PAN := 0
const TILT := 1
const ROLL := 2

var angles := [0.0, 0.0, 0.0]      ## current angles (deg)
var velocities := [0.0, 0.0, 0.0]  ## current angular speeds (deg/s)
var filtered := [0.0, 0.0, 0.0]    ## smoothed inputs (-1..1)
var raw_inputs := [0.0, 0.0, 0.0]  ## inputs before smoothing (-1..1)
## Replay: when non-empty, [pan, tilt, roll] used instead of the live controller / keyboard.
var input_override: Array = []

@onready var camera: Camera3D = $Camera3D

## 2-player mode: the pan follows the heading of the drone (like a gimbal in "follow" mode) instead of staying
## fixed in the world. Pitch and roll stay stabilised.
var yaw_follow := false
## Callable() -> heading (rad) of the drone; when valid it replaces the heading of the parent node.
var heading_provider := Callable()

var _heading0 := 0.0
var _aligned := false


func _ready() -> void:
	var start := load_default_profile()
	pan_profile = start
	tilt_profile = start
	roll_profile = start
	# Wait one frame so a parent (e.g. PathFollow3D) has its final orientation.
	await get_tree().process_frame
	_heading0 = _parent_heading()
	_aligned = true


func _process(delta: float) -> void:
	if not _aligned:
		return
	raw_inputs = _read_inputs()
	var tau := input_smoothing * smoothing_max_time
	var k := 1.0 if tau <= 0.0001 else 1.0 - exp(-delta / tau)
	for i in 3:
		filtered[i] = lerpf(filtered[i], raw_inputs[i], k)
		_step_axis(i, delta)
	_apply()


## Points the camera at a world position (sets pan/tilt, zeroes roll and speeds).
func aim_at(world_point: Vector3) -> void:
	var dir := world_point - camera.global_position
	if dir.length() < 0.001:
		return
	var base := _base_heading()
	angles[PAN] = -rad_to_deg(angle_difference(base, atan2(-dir.x, -dir.z)))
	angles[TILT] = rad_to_deg(asin(clampf(dir.normalized().y, -1.0, 1.0)))
	angles[ROLL] = 0.0
	velocities = [0.0, 0.0, 0.0]
	filtered = [0.0, 0.0, 0.0]
	_apply()


## Zero all angles; when stabilized, pan 0 becomes the drone's current heading.
func recenter() -> void:
	_heading0 = _parent_heading()
	angles = [0.0, 0.0, 0.0]
	velocities = [0.0, 0.0, 0.0]
	filtered = [0.0, 0.0, 0.0]
	_apply()


## Public view of the inputs the rig will use this frame (used by the session recorder).
func read_inputs() -> Array:
	return _read_inputs()


## Replay: restores the gimbal state saved at the start of a recorded run.
func restore_state(a: Array, v: Array, f: Array) -> void:
	angles = a.duplicate()
	velocities = v.duplicate()
	filtered = f.duplicate()
	_apply()


func _read_inputs() -> Array:
	if not input_override.is_empty():
		return input_override.duplicate()
	var v := [0.0, 0.0, 0.0]
	if use_controller:
		v[PAN] = ControllerInput.pan_input
		v[TILT] = ControllerInput.tilt_input
		v[ROLL] = ControllerInput.roll_input
	if use_keyboard and keyboard_enabled_keys:
		v[PAN] += _key_axis([KEY_LEFT, KEY_A], [KEY_RIGHT, KEY_D])
		v[TILT] += _key_axis([KEY_DOWN, KEY_S], [KEY_UP, KEY_W])
		v[ROLL] += _key_axis([KEY_Q], [KEY_E])
	for i in 3:
		v[i] = clampf(v[i], -1.0, 1.0)
	return v


func _key_axis(neg: Array, pos: Array) -> float:
	var out := 0.0
	for k in neg:
		if Input.is_physical_key_pressed(k):
			out -= 1.0
	for k in pos:
		if Input.is_physical_key_pressed(k):
			out += 1.0
	return clampf(out, -1.0, 1.0)


func _axis_config(i: int) -> Dictionary:
	match i:
		PAN:
			return {"speeds": pan_speeds, "profile": pan_profile, "rise": pan_rise_time,
				"fall": pan_fall_time, "limited": pan_limited, "min": pan_min, "max": pan_max}
		TILT:
			return {"speeds": tilt_speeds, "profile": tilt_profile, "rise": tilt_rise_time,
				"fall": tilt_fall_time, "limited": tilt_limited, "min": tilt_min, "max": tilt_max}
		_:
			return {"speeds": roll_speeds, "profile": roll_profile, "rise": roll_rise_time,
				"fall": roll_fall_time, "limited": roll_limited, "min": roll_min, "max": roll_max}


func get_max_speed(i: int) -> float:
	var c := _axis_config(i)
	return c.speeds[c.profile]


func _step_axis(i: int, delta: float) -> void:
	var c := _axis_config(i)
	var max_speed: float = c.speeds[c.profile]
	var target: float = filtered[i] * max_speed
	var vel: float = velocities[i]
	var accelerating := absf(target) > absf(vel) and vel * target >= 0.0
	var rate := max_speed / maxf(c.rise if accelerating else c.fall, 0.001)
	vel = move_toward(vel, target, rate * delta)

	var angle: float = angles[i] + vel * delta
	if c.limited:
		var lo := minf(c.min, c.max)
		var hi := maxf(c.min, c.max)
		if angle <= lo or angle >= hi:
			angle = clampf(angle, lo, hi)
			vel = 0.0
	else:
		angle = wrapf(angle, -180.0, 180.0)
	velocities[i] = vel
	angles[i] = angle


func _base_heading() -> float:
	return _parent_heading() if (yaw_follow or not stabilized) else _heading0


func _parent_heading() -> float:
	if heading_provider.is_valid():
		return float(heading_provider.call())
	var p := get_parent_node_3d()
	if p == null:
		return 0.0
	var f := -p.global_basis.z
	return atan2(-f.x, -f.z)


func _apply() -> void:
	var yaw := deg_to_rad(-angles[PAN])
	if stabilized:
		# Orientation is independent of the parent (drone): only the position follows it.
		global_basis = Basis(Vector3.UP, (_parent_heading() if yaw_follow else _heading0) + yaw)
	else:
		rotation.y = yaw
	camera.rotation = Vector3(deg_to_rad(angles[TILT]), 0.0, deg_to_rad(-angles[ROLL]))

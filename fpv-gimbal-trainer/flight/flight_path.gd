class_name FlightPath
extends Path3D
## Scripted drone flight along a Curve3D.
## Hierarchy: FlightPath (Path3D) > Follower (PathFollow3D) > DroneBody > GimbalRig > Camera3D
## The procedural noise (speed wobble, bank in turns, pitch on accel, turbulence)
## moves ONLY DroneBody, i.e. the rig. The camera angles stay under gimbal control,
## so the operator has to compensate with the gimbal.

signal finished

@export_group("Playback")
@export var playing := true
## Wrap around at the end. Best used with a closed curve (no jump).
@export var loop_path := true
## Optional Curve3D .tres (e.g. saved by the flight editor). Overrides the curve at start.
@export_file("*.tres") var curve_file := ""

## true: progress along the curve is imposed through external_ratio instead of base_speed
## (used to keep the drone abeam of a moving subject).
@export var externally_driven := false

@export_group("Speed")
@export_range(0.5, 60.0, 0.1, "suffix:m/s") var base_speed := 6.0
## Multiplier handy for scenarios / difficulty.
@export_range(0.1, 3.0, 0.05) var speed_scale := 1.0
## Forward speed oscillation, fraction of the speed.
@export_range(0.0, 0.8, 0.01) var speed_wobble := 0.12
@export_range(0.05, 5.0, 0.05, "suffix:Hz") var speed_wobble_freq := 0.4

@export_group("Drone body (affects rig only)")
@export_range(0.0, 60.0, 0.5, "suffix:°") var max_bank_deg := 25.0
@export_range(0.0, 2.0, 0.05) var bank_gain := 1.0
@export_range(0.0, 30.0, 0.5, "suffix:°") var max_pitch_deg := 12.0
## Degrees of nose-down per m/s² of forward acceleration.
@export_range(0.0, 5.0, 0.05) var pitch_gain := 1.5
## Lag of the body following the target bank / pitch.
@export_range(0.02, 1.5, 0.01, "suffix:s") var body_response_time := 0.25

@export_group("Turbulence")
@export_range(0.0, 10.0, 0.1, "suffix:°") var turbulence_tilt_deg := 1.0
@export_range(0.0, 2.0, 0.01, "suffix:m") var turbulence_pos := 0.15
@export_range(0.05, 5.0, 0.05, "suffix:Hz") var turbulence_freq := 0.8
@export var noise_seed := 1

## Set by a scenario each frame (0..1) when externally_driven is true.
var external_ratio := 0.0
var speed_now := 0.0
var bank_deg := 0.0
var pitch_deg := 0.0

var _noise := FastNoiseLite.new()
var _t := 0.0
var _prev_yaw := 0.0
var _has_prev := false
var _prev_speed := -1.0
var _last_progress := 0.0

@onready var follower: PathFollow3D = $Follower
@onready var body: Node3D = $Follower/DroneBody
@onready var rig: GimbalRig = $Follower/DroneBody/GimbalRig


func _ready() -> void:
	if curve_file != "":
		var c := ResourceLoader.load(curve_file) as Curve3D
		if c:
			curve = c
	if curve == null or curve.point_count < 2:
		curve = make_demo_curve()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.seed = noise_seed
	follower.rotation_mode = PathFollow3D.ROTATION_ORIENTED
	follower.progress = 0.0


## Scenario hook: {"speed": m/s, "speed_scale": x, "loop": bool, ...any exported property}
func configure(settings: Dictionary) -> void:
	if settings.has("speed"):
		base_speed = settings.speed
	for key in settings:
		if key != "speed" and key in self:
			set(key, settings[key])


func restart() -> void:
	follower.progress = 0.0
	_t = 0.0
	_has_prev = false
	_prev_speed = -1.0
	_last_progress = 0.0
	bank_deg = 0.0
	pitch_deg = 0.0


func _n(channel: int, freq: float) -> float:
	return clampf(_noise.get_noise_2d(_t * freq, channel * 37.1) * 1.4, -1.0, 1.0)


func _process(delta: float) -> void:
	if not playing or delta <= 0.0 or curve == null or curve.point_count < 2:
		return
	_t += delta

	follower.loop = loop_path
	if externally_driven:
		# Progress imposed by a scenario (e.g. matched to a subject); speed is derived from it.
		var new_progress := clampf(external_ratio, 0.0, 1.0) * curve.get_baked_length()
		speed_now = maxf(0.0, (new_progress - follower.progress) / delta)
		follower.progress = new_progress
	else:
		# Forward progress with speed wobble
		speed_now = maxf(0.0, base_speed * speed_scale * (1.0 + speed_wobble * _n(0, speed_wobble_freq)))
		follower.progress += speed_now * delta
		if not loop_path and follower.progress_ratio >= 0.999:
			playing = false
			finished.emit()
	if follower.progress < _last_progress - 1.0:
		_has_prev = false  # wrapped around
	_last_progress = follower.progress

	# Yaw rate -> lateral acceleration -> bank
	var fwd := -follower.global_transform.basis.z
	var yaw := atan2(-fwd.x, -fwd.z)
	var yaw_rate := 0.0
	if _has_prev:
		yaw_rate = angle_difference(_prev_yaw, yaw) / delta
	_prev_yaw = yaw
	_has_prev = true
	var accel := 0.0 if _prev_speed < 0.0 else (speed_now - _prev_speed) / delta
	_prev_speed = speed_now

	var bank_target := clampf(rad_to_deg(atan2(speed_now * yaw_rate, 9.81)) * bank_gain,
			-max_bank_deg, max_bank_deg)
	var pitch_target := clampf(-accel * pitch_gain, -max_pitch_deg, max_pitch_deg)
	var k := 1.0 - exp(-delta / maxf(body_response_time, 0.001))
	bank_deg = lerpf(bank_deg, bank_target, k)
	pitch_deg = lerpf(pitch_deg, pitch_target, k)

	# Applied to the drone body only (never to the camera)
	body.rotation = Vector3(
		deg_to_rad(pitch_deg + _n(1, turbulence_freq) * turbulence_tilt_deg),
		0.0,
		deg_to_rad(bank_deg + _n(2, turbulence_freq) * turbulence_tilt_deg))
	body.position = Vector3(_n(3, turbulence_freq), _n(4, turbulence_freq),
			_n(5, turbulence_freq)) * turbulence_pos


## Sets smooth (Catmull-Rom style) in/out handles on every point.
static func auto_smooth(c: Curve3D) -> void:
	var n := c.point_count
	for i in n:
		var pi := i - 1
		var ni := i + 1
		if c.closed:
			pi = posmod(pi, n)
			ni = posmod(ni, n)
		else:
			pi = maxi(pi, 0)
			ni = mini(ni, n - 1)
		var t := (c.get_point_position(ni) - c.get_point_position(pi)) / 6.0
		c.set_point_in(i, -t)
		c.set_point_out(i, t)


static func make_demo_curve() -> Curve3D:
	var c := Curve3D.new()
	c.closed = true
	var n := 8
	for i in n:
		var a := TAU * i / n
		var r := 26.0 + (6.0 if i % 2 == 0 else -4.0)
		c.add_point(Vector3(cos(a) * r, 5.0 + 2.5 * sin(i * 1.3), sin(a) * r))
	auto_smooth(c)
	return c

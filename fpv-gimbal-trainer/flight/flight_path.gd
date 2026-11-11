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

@export_group("Airframe")
## true: the drone is a mass that chases the planned line the way a pilot flies it, instead of sitting on it
## like a cable cam: it lags and overshoots a little when the line changes quickly, sinks when it banks hard
## (the pilot adds throttle a moment late) and is never exactly on the line (the pilot's constant small
## corrections). Its attitude is the one that produces its acceleration, as on a real multirotor.
## false: the body sits on the path (legacy flight, kept for old replays).
@export var inertia := false
## true: the line's speed / acceleration are low-passed before the airframe uses them (flight model 4, see
## LINE_VEL_TAU). false: the raw finite differences, as flight models 1-3 recorded (so old replays are identical).
@export var smooth_line := true
## How tightly the pilot holds the line: natural frequency (Hz) and damping of the chase, across / along the
## path and in height (throttle is held less precisely than the sticks).
@export var track_hz := 0.55
@export var track_hz_vertical := 0.35
@export var track_damping := 0.62
## The pilot's small corrections: slow wander of the line held (m) and up / down "pumping" (m), and their
## frequencies (Hz).
@export var wander := 0.3
@export var pump := 0.22
@export var wander_freq := 0.35
@export var pump_freq := 0.5
## Share of the extra lift a banked turn needs that the pilot gives late (the drone sinks, then is caught).
@export var turn_sink := 0.6
## Share of the line's acceleration the pilot anticipates (stick input before the error builds up): the rest
## shows as lag / overshoot.
@export var anticipation := 0.5
## Ground height (Callable(x, z) -> m), set by the scenario: the drone never sinks closer than 1 m to it.
var ground_fn := Callable()

const MAX_ACCEL := 35.0     ## m/s², horizontal: a 9" X8 at thrust-to-weight 3.8 (see FpvDrone)
const MAX_SINK := 1.5       ## m/s², most a late throttle in a turn pulls the drone down
const SPEED_JUMP := 5.0     ## m/s in one frame: a discontinuity of the line, not a manoeuvre
const ATTITUDE_LAG := 0.12  ## s, the frame follows the thrust direction the pilot commands

## Filtering of the line the airframe chases (smooth_line). The line is a baked curve sampled once per frame; its
## position is good to a centimetre, which is nothing - but differentiated twice at 60 Hz a centimetre is 36 m/s².
## Fed straight into the airframe, those isolated spikes (measured: 23 - 50 m/s² against a normal 0.2 m/s²) were
## the commanded acceleration, so the thrust axis - the attitude of the drone, and what the drone view shows -
## flipped by up to 70 degrees in a single frame and came back. A pilot does not do that: his sticks have
## bandwidth. Each stage is a first-order filter with this time constant (s).
const LINE_VEL_TAU := 0.05   ## line speed, from the position
const LINE_ACC_TAU := 0.15   ## line acceleration, from the speed
const ATT_ACC_TAU := 0.10    ## acceleration that tilts the frame (the spring's output)
const FLOOR_MARGIN := 0.25   ## m above the 1 m floor that the aim point keeps, so the drone does not graze it

## Set by a scenario each frame (0..1) when externally_driven is true.
var external_ratio := 0.0
var speed_now := 0.0
var bank_deg := 0.0
var pitch_deg := 0.0

var _noise := FastNoiseLite.new()
## FastNoiseLite's default frequency is 0.01, so _noise ran 100x slower than its "Hz" said (the legacy
## turbulence was an all but fixed offset). The airframe uses a noise at frequency 1: `freq` is then in Hz.
var _noise_air := FastNoiseLite.new()
var _t := 0.0
var _prev_yaw := 0.0
var _has_prev := false
var _prev_speed := -1.0
var _last_progress := 0.0
# airframe: simulated position / velocity, last target, acceleration and attitude
var _x := Vector3.ZERO
var _v := Vector3.ZERO
var _p_prev := Vector3.ZERO
var _pv_prev := Vector3.ZERO
var _pv_raw := Vector3.ZERO     # unfiltered line speed of the previous frame (to spot a real jump)
var _pa_s := Vector3.ZERO       # filtered line acceleration
var _acc := Vector3.ZERO
var _acc_s := Vector3.ZERO      # filtered acceleration that sets the attitude
var _q := Quaternion.IDENTITY
var _air_ready := false

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
	_noise_air.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise_air.seed = noise_seed
	_noise_air.frequency = 1.0
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
	_air_ready = false


func _n(channel: int, freq: float) -> float:
	var src := _noise_air if inertia else _noise
	return clampf(src.get_noise_2d(_t * freq, channel * 37.1) * 1.4, -1.0, 1.0)


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
	if inertia:
		_step_airframe(delta)


## The airframe (see `inertia`): a mass pulled towards where the pilot aims - the planned point plus the slow
## wander of a hand-flown line - by a damped spring with feed-forward of the line's speed (no lag at a steady
## speed, a little lag / overshoot when the line accelerates or turns). Deterministic for a given sequence of
## time steps (noise driven by _t), so replays reproduce it.
func _step_airframe(delta: float) -> void:
	var fwd := -follower.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.001 else Vector3.FORWARD
	var right := fwd.cross(Vector3.UP)
	# The line, and the offset of the pilot's wander / pumping / the fine turbulence (which goes through the
	# mass too: the frame is buffeted, it does not teleport). Only the line's own speed and acceleration are
	# fed forward: the offset is a slow position error the spring smooths out.
	var p := follower.global_position
	var o := right * (_n(6, wander_freq) * wander) + fwd * (_n(7, wander_freq * 0.8) * wander * 0.6) \
			+ Vector3.UP * (_n(8, pump_freq) * pump) + follower.global_basis * body.position
	# The floor, seen by the pilot BEFORE the drone hits it: when the wander / pumping would take the aim point
	# below 1 m of the ground (a hover on a slope: the ground rises 0.3 m when the drone drifts 0.5 m sideways),
	# the aim point stays above it. The hard clamp at the end was the only floor, and a clamp is a snap: the
	# position was pushed out in one step, the spring answered, and the frame tilted 30 degrees and back - in
	# every hover on a slope (the countdown of a descent, of a freeride face).
	if smooth_line and ground_fn.is_valid():
		var aim := p + o
		var floor_aim := float(ground_fn.call(aim.x, aim.z)) + 1.0 + FLOOR_MARGIN
		if aim.y < floor_aim:
			o.y += floor_aim - aim.y
	if not _air_ready or _x.distance_to(p + o) > 40.0:  # first frame, or the path was restarted
		_x = p + o
		_v = Vector3.ZERO
		_p_prev = p
		_pv_prev = Vector3.ZERO
		_pv_raw = Vector3.ZERO
		_pa_s = Vector3.ZERO
		_acc = Vector3.ZERO
		_acc_s = Vector3.ZERO
		_q = follower.global_basis.get_rotation_quaternion()
		if smooth_line:
			# level, with the heading of the path: the follower's own basis is tilted by the slope of the path (-35
			# degrees nose-down at the start wall of a freeride face), and the frame used to start the countdown
			# in that attitude and straighten up in half a second
			_q = Basis(right, Vector3.UP, -fwd).get_rotation_quaternion()
		_air_ready = true
	var pv_raw := (p - _p_prev) / delta
	var pv := pv_raw
	var jumped := (pv - _pv_prev).length() > SPEED_JUMP
	if smooth_line:
		jumped = (pv_raw - _pv_raw) .length() > SPEED_JUMP
		pv = _pv_prev.lerp(pv_raw, 1.0 - exp(-delta / LINE_VEL_TAU))
	_pv_raw = pv_raw
	var pa := (pv - _pv_prev) / delta * anticipation
	if smooth_line:
		_pa_s = _pa_s.lerp((pv - _pv_prev) / delta, 1.0 - exp(-delta / LINE_ACC_TAU))
		pa = _pa_s * anticipation
	# A line whose speed jumps in one frame is not something to chase (the subject's flying start at "GO"):
	# the pilot was already on the move, the drone takes the jump as it is.
	if jumped:
		pv = pv_raw
		_v += pv - _pv_prev
		_pv_prev = pv
		_pa_s = Vector3.ZERO
		pa = Vector3.ZERO
	var w := TAU * track_hz
	var wv := TAU * track_hz_vertical
	var n := maxi(1, ceili(delta / 0.01))
	var h := delta / n
	for i in n:
		var u := float(i + 1) / n
		var e := _p_prev.lerp(p, u) + o - _x
		var ev := _pv_prev.lerp(pv, u) - _v
		var a := pa + Vector3(e.x * w * w + ev.x * 2.0 * track_damping * w, e.y * wv * wv + ev.y * 2.0 * track_damping * wv,
				e.z * w * w + ev.z * 2.0 * track_damping * w)
		var a_h := Vector2(a.x, a.z)
		if a_h.length() > MAX_ACCEL:
			a_h = a_h.limit_length(MAX_ACCEL)
			a.x = a_h.x
			a.z = a_h.y
		# banking costs lift: the drone sinks in a hard turn until the pilot catches it (the "pump")
		a.y -= minf(turn_sink * (sqrt(9.81 * 9.81 + a_h.length_squared()) - 9.81), MAX_SINK)
		_v += a * h
		_x += _v * h
		_acc = a
	_p_prev = p
	_pv_prev = pv
	if ground_fn.is_valid():
		var floor_y := float(ground_fn.call(_x.x, _x.z)) + 1.0
		if _x.y < floor_y:
			_x.y = floor_y
			_v.y = maxf(_v.y, 0.0)
	# attitude: the thrust axis tilts to produce the acceleration (plus the small turbulence of the frame)
	var acc_att := _acc
	if smooth_line:
		_acc_s = _acc_s.lerp(_acc, 1.0 - exp(-delta / ATT_ACC_TAU))
		acc_att = _acc_s
	var up := (acc_att + Vector3(0.0, 9.81, 0.0)).normalized()
	var f := (fwd - up * fwd.dot(up)).normalized()
	var b := Basis(f.cross(up), up, -f) * Basis.from_euler(Vector3(
			deg_to_rad(_n(1, turbulence_freq) * turbulence_tilt_deg), 0.0, deg_to_rad(_n(2, turbulence_freq) * turbulence_tilt_deg)))
	_q = _q.slerp(b.get_rotation_quaternion(), 1.0 - exp(-delta / ATTITUDE_LAG))
	body.global_transform = Transform3D(Basis(_q), _x)


## Airframe state at the start of a recorded run (replays restore it).
func airframe_state() -> Dictionary:
	return {"x": [_x.x, _x.y, _x.z], "v": [_v.x, _v.y, _v.z], "p": [_p_prev.x, _p_prev.y, _p_prev.z],
			"pv": [_pv_prev.x, _pv_prev.y, _pv_prev.z], "a": [_acc.x, _acc.y, _acc.z],
			"q": [_q.x, _q.y, _q.z, _q.w], "ready": _air_ready,
			"pvr": [_pv_raw.x, _pv_raw.y, _pv_raw.z], "pas": [_pa_s.x, _pa_s.y, _pa_s.z],
			"as": [_acc_s.x, _acc_s.y, _acc_s.z]}


func restore_airframe(d: Dictionary) -> void:
	_x = Vector3(d.x[0], d.x[1], d.x[2])
	_v = Vector3(d.v[0], d.v[1], d.v[2])
	_p_prev = Vector3(d.p[0], d.p[1], d.p[2])
	_pv_prev = Vector3(d.pv[0], d.pv[1], d.pv[2])
	_acc = Vector3(d.a[0], d.a[1], d.a[2])
	_q = Quaternion(d.q[0], d.q[1], d.q[2], d.q[3])
	_air_ready = bool(d.ready)
	# the filter states exist only in flight model 4 recordings
	for pair in [["pvr", "_pv_raw"], ["pas", "_pa_s"], ["as", "_acc_s"]]:
		var a = d.get(pair[0], [0.0, 0.0, 0.0])
		set(pair[1], Vector3(a[0], a[1], a[2]))


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

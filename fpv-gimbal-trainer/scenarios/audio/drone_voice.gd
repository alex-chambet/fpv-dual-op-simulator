class_name DroneVoice
extends Node
## The drone the operator is sitting on: props and the air going past.
##
## Deliberately NOT a 3D source. The listener is the gimbal camera, which is bolted to this drone,
## so its own noise is simply always there - and that is what makes the subject's 3D sound read as
## distance rather than as volume. Props rise when the drone works (it accelerates, it climbs) and
## the airflow follows the speed, so the operator can hear the flight he is not flying.

const PROP_IDLE := 0.80      ## pitch of the blade-pass loop when the drone is just holding station
const PROP_MAX := 1.55
const WIND_FROM := 6.0       ## m/s below which there is no airflow worth hearing
const WIND_FULL := 38.0
const SILENT_DB := -60.0

var _prop: AudioStreamPlayer
var _wind: AudioStreamPlayer
var _prev := Vector3.ZERO
var _has_prev := false
var _speed := 0.0
var _effort := 0.0


func setup() -> void:
	SoundSettings.ensure_buses()
	_prop = _player(SoundBank.prop(), -17.0)
	_wind = _player(SoundBank.wind(), -40.0)


func _player(stream: AudioStream, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = db
	p.bus = SoundSettings.BUS_DRONE
	add_child(p)
	p.play()
	return p


## `pos` is where the drone is this frame; the speed and the work it is doing come from that alone,
## so this does not care which of the flight modes is driving it.
func update(delta: float, pos: Vector3) -> void:
	if _prop == null or delta <= 0.0:
		return
	if not _has_prev:
		_prev = pos
		_has_prev = true
		return
	var step := (pos - _prev) / delta
	_prev = pos
	var v := step.length()
	var accel := (v - _speed) / delta
	_speed = lerpf(_speed, v, clampf(delta * 8.0, 0.0, 1.0))
	# A quad leans on its props to climb and to change speed; both raise the note. The weights are
	# set so that a drone holding station sits near the bottom and a chase at 45 m/s near the top,
	# instead of pinning at full tilt the moment it moves at all.
	var work := clampf(0.12 + maxf(step.y, 0.0) * 0.05 + absf(accel) * 0.015 + _speed * 0.013,
			0.0, 1.0)
	_effort = lerpf(_effort, work, clampf(delta * 5.0, 0.0, 1.0))
	_prop.pitch_scale = lerpf(PROP_IDLE, PROP_MAX, _effort)
	_prop.volume_db = _db(0.5 + 0.5 * _effort) - 15.0
	var air := clampf((_speed - WIND_FROM) / (WIND_FULL - WIND_FROM), 0.0, 1.0)
	_wind.volume_db = _db(air * air) - 12.0
	_wind.pitch_scale = clampf(0.85 + air * 0.5, 0.8, 1.5)


## Volume in dB, floored instead of running off to -inf when the layer goes silent.
static func _db(linear: float) -> float:
	return SILENT_DB if linear <= 0.002 else maxf(linear_to_db(linear), SILENT_DB)

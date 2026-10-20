class_name DroneVoice
extends Node
## The drone the operator is sitting on: props and the air going past.
##
## Deliberately NOT a 3D source. The listener is the gimbal camera, which is bolted to this drone,
## so its own noise is simply always there - and that is what makes the subject's 3D sound read as
## distance rather than as volume.
##
## The airflow is three recordings layered, not one turned up: a low rumble that is there from the
## first metres per second, the body of the wind over it, and a high whistle that only appears
## near top speed. Each has its own window (see SoundLayer), so accelerating does not just get
## louder, it changes colour - which is how you hear speed rather than volume. A fourth layer is
## the gust, driven by how hard the drone is changing speed, so a hard stop has air in it.
##
## Everything is deduced from the drone's position alone, frame to frame, so it works unchanged on
## a planned flight (training), on acro sticks (2 players) and in the sandbox.

const WIND_LAYERS := {
	"wind_low": {"window": [0.0, 3.0, 14.0, 27.0], "pitch": Vector2(0.9, 1.15), "db": -21.0},
	"wind_mid": {"window": [5.0, 14.0, 27.0, 42.0], "pitch": Vector2(0.92, 1.2), "db": -15.0},
	"wind_high": {"window": [17.0, 29.0, 48.0, 75.0], "pitch": Vector2(0.95, 1.28), "db": -13.0},
}
## Driven by |acceleration| in m/s^2, not by speed: this is the air you hear when the drone leans.
const GUST_LAYER := {"window": [2.0, 7.0, 1.0e9, 1.0e9], "pitch": Vector2(0.9, 1.2),
		"over": Vector2(2.0, 25.0), "db": -19.0, "smooth": 4.0}
## Props, on how hard the drone is working (0 holding station .. 1 flat out).
const PROP_LAYERS := {
	"prop_low": {"window": [-1.0, -1.0, 0.45, 0.85], "pitch": Vector2(0.85, 1.12), "db": -17.0},
	"prop_high": {"window": [0.28, 0.6, 1.0e9, 1.0e9], "pitch": Vector2(0.9, 1.32),
			"over": Vector2(0.28, 1.0), "db": -16.0},
}

var _layers := {}
var _prev := Vector3.ZERO
var _has_prev := false
var _speed := 0.0
var _effort := 0.0
var _gust := 0.0


func setup() -> void:
	SoundSettings.ensure_buses()
	var cfgs := WIND_LAYERS.duplicate()
	cfgs["wind_gust"] = GUST_LAYER
	cfgs.merge(PROP_LAYERS)
	for name in cfgs:
		var l := SoundLayer.make(self, name, cfgs[name], false)
		if l == null:
			continue
		l.player.bus = SoundSettings.BUS_DRONE
		l.start()
		_layers[name] = l


## `pos` is where the drone is this frame; the speed and the work it is doing come from that alone,
## so this does not care which of the flight modes is driving it.
func update(delta: float, pos: Vector3) -> void:
	if _layers.is_empty() or delta <= 0.0:
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
	_gust = lerpf(_gust, absf(accel), clampf(delta * 6.0, 0.0, 1.0))
	# A quad leans on its props to climb and to change speed; both raise the note. The weights are
	# set so that a drone holding station sits near the bottom and a chase at 45 m/s near the top,
	# instead of pinning at full tilt the moment it moves at all.
	var work := clampf(0.12 + maxf(step.y, 0.0) * 0.05 + absf(accel) * 0.015 + _speed * 0.013,
			0.0, 1.0)
	_effort = lerpf(_effort, work, clampf(delta * 5.0, 0.0, 1.0))
	for name in WIND_LAYERS:
		_drive(name, _speed, delta)
	_drive("wind_gust", _gust, delta)
	for name in PROP_LAYERS:
		_drive(name, _effort, delta)


func _drive(name: String, v: float, delta: float) -> void:
	if _layers.has(name):
		_layers[name].set_value(v, delta)

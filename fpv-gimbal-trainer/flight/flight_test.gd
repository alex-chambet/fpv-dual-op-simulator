extends Node3D
## Scripted flight test: FlightPath (demo curve, or any curve you assign) + props.
## Keys: Space = pause, -/+ = speed, 1/2/3 = gimbal profile, R = recenter gimbal, F1 = HUD.
## Gimbal: arrows/WASD (pan+tilt), Q/E (roll), or the controller.

const PROFILE_NAMES := ["Slow", "Medium", "Fast"]

@onready var flight: FlightPath = $FlightPath
@onready var hud: Label = $HUD/Label


func _ready() -> void:
	# Keep props away from the demo path band so the drone does not fly through them.
	WorldProps.spawn(self, 40, 8.0, 70.0, 42, 14.0, 40.0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_SPACE: flight.playing = not flight.playing
			KEY_MINUS, KEY_KP_SUBTRACT: flight.speed_scale = maxf(0.1, flight.speed_scale - 0.1)
			KEY_EQUAL, KEY_KP_ADD: flight.speed_scale = minf(3.0, flight.speed_scale + 0.1)
			KEY_1: _set_profile(GimbalRig.SpeedProfile.SLOW)
			KEY_2: _set_profile(GimbalRig.SpeedProfile.MEDIUM)
			KEY_3: _set_profile(GimbalRig.SpeedProfile.FAST)
			KEY_R: flight.rig.recenter()
			KEY_F1: hud.visible = not hud.visible


func _set_profile(p: GimbalRig.SpeedProfile) -> void:
	flight.rig.pan_profile = p
	flight.rig.tilt_profile = p
	flight.rig.roll_profile = p


func _process(_delta: float) -> void:
	var rig := flight.rig
	var ratio := flight.follower.progress_ratio
	hud.text = "Flight %s   %.0f%%   speed %.1f m/s (x%.1f)\nDrone body: bank %+.1f°  pitch %+.1f°\n\nGimbal  pan %+.1f°  tilt %+.1f°  roll %+.1f°   [%s]\n\nSpace: pause   -/+: speed   1/2/3: gimbal profile   R: recenter   F1: hide\nArrows/WASD: pan+tilt   Q/E: roll" % [
		"PLAY" if flight.playing else "PAUSE", ratio * 100.0, flight.speed_now, flight.speed_scale,
		flight.bank_deg, flight.pitch_deg,
		rig.angles[0], rig.angles[1], rig.angles[2], PROFILE_NAMES[rig.pan_profile]]

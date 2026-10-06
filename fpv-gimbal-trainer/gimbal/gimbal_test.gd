extends Node3D
## Test scene: neutral environment + GimbalRig. Spawns coloured primitives
## around the rig to give motion cues. Keys: 1/2/3 = Slow/Medium/Fast on all
## axes, R = recenter, F1 = toggle HUD.

@onready var rig: GimbalRig = $GimbalRig
@onready var hud: Label = $HUD/Label

const PROFILE_NAMES := ["Slow", "Medium", "Fast"]


func _ready() -> void:
	_spawn_props()


func _spawn_props() -> void:
	WorldProps.spawn(self, 28, 6.0, 16.0, 42)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_1: _set_profile(GimbalRig.SpeedProfile.SLOW)
			KEY_2: _set_profile(GimbalRig.SpeedProfile.MEDIUM)
			KEY_3: _set_profile(GimbalRig.SpeedProfile.FAST)
			KEY_R: rig.recenter()
			KEY_F1: hud.visible = not hud.visible
			KEY_ESCAPE: get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _set_profile(p: GimbalRig.SpeedProfile) -> void:
	rig.pan_profile = p
	rig.tilt_profile = p
	rig.roll_profile = p


func _process(_delta: float) -> void:
	hud.text = "Pan  %7.1f°  %6.1f°/s  [%s]\nTilt %7.1f°  %6.1f°/s  [%s]\nRoll %7.1f°  %6.1f°/s  [%s]\n\nin: pan %+.2f  tilt %+.2f  roll %+.2f\n\nArrows/WASD: pan+tilt   Q/E: roll\n1/2/3: Slow/Medium/Fast   R: recenter   F1: hide   Esc: menu" % [
		rig.angles[0], rig.velocities[0], PROFILE_NAMES[rig.pan_profile],
		rig.angles[1], rig.velocities[1], PROFILE_NAMES[rig.tilt_profile],
		rig.angles[2], rig.velocities[2], PROFILE_NAMES[rig.roll_profile],
		rig.raw_inputs[0], rig.raw_inputs[1], rig.raw_inputs[2]]

class_name MotionBlur
extends Node
## Motion blur of a camera (add it as a child of a Camera3D): the blur a real camera records during its shutter time.
## Each object is blurred by its own motion relative to the camera (MotionBlurEffect, run by the renderer): what the
## camera follows stays sharp, the landscape rushing past streaks, a car crossing a still shot is a smear.
## The length of the blur is the motion during the shutter time (not the frame time), so it looks the same at 60 or
## 144 fps. Needs the Forward+ renderer (nothing happens without a RenderingDevice, e.g. headless runs).

## 0 off, 1 light (shutter 1/120 s), 2 realistic (1/60 s), 3 strong (1/30 s). Chosen in the pause menu > Graphismes.
static var level := 1
const SHUTTERS := [0.0, 1.0 / 120.0, 1.0 / 60.0, 1.0 / 30.0]
const LABELS := ["Désactivé", "Léger (1/120)", "Réaliste (1/60)", "Fort (1/30)"]

## Remembers the chosen level in the menu preferences file (the main menu reads it back).
static func save_level() -> void:
	var path := "user://menu_prefs.json"
	var prefs := {}
	if FileAccess.file_exists(path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(parsed) == TYPE_DICTIONARY:
			prefs = parsed
	prefs["blur"] = level
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(prefs, "\t"))


var effect: MotionBlurEffect
var _cam: Camera3D
var _prev := Transform3D.IDENTITY
var _has_prev := false


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 1000  # after everything that moves the camera in the frame


func _ready() -> void:
	_cam = get_parent() as Camera3D
	if _cam == null or RenderingServer.get_rendering_device() == null:
		return
	effect = MotionBlurEffect.new()
	var comp := Compositor.new()
	comp.compositor_effects = [effect]
	_cam.compositor = comp


func _process(delta: float) -> void:
	if effect == null:
		return
	var shutter: float = SHUTTERS[clampi(level, 0, SHUTTERS.size() - 1)]
	var cur := _cam.global_transform
	var scale := shutter / maxf(delta, 1.0 / 240.0)
	# a jump of the camera (start of a run, restart) is not a movement: no blur in that frame
	if not _has_prev or cur.origin.distance_to(_prev.origin) > 30.0 \
			or cur.basis.get_rotation_quaternion().angle_to(_prev.basis.get_rotation_quaternion()) > 1.0:
		scale = 0.0
	effect.shutter_scale = scale
	effect.near = _cam.near
	effect.far = _cam.far
	_prev = cur
	_has_prev = true

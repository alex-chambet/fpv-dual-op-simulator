class_name TiltIndicator
extends Control
## The tilt of the drone's FPV camera, shown in the middle of the screen for a moment each time it changes (2-player
## mode: the gimbal operator's up / down keys tilt the pilot's camera): a bar from the lowest to the highest tilt with
## the current one marked, and its value. Fades out about a second after the last change.

const SHOW_TIME := 1.4
const FADE_TIME := 0.5
const BAR_W := 300.0
const TILT_MIN := 0.0       # degrees above the drone's nose
const TILT_MAX := 75.0
const TILT_SPEED := 35.0    # degrees per second while a key is held

var min_deg := TILT_MIN
var max_deg := TILT_MAX
var _deg := 25.0
var _left := 0.0
var _was_adjusting := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false


## Shows the tilt `deg` (degrees above the drone's nose) for a moment.
func show_tilt(deg: float) -> void:
	_deg = deg
	_left = SHOW_TIME + FADE_TIME
	visible = true
	queue_redraw()


## Up / down arrows tilt the drone's FPV camera (up raises it); shows the value while it moves. Call every frame.
## Saved once the keys are released, kept for the next sessions (FpvDrone.load_default_cam_tilt).
func step_keys(drone: FpvDrone, delta: float) -> void:
	var dir := 0.0
	if Input.is_physical_key_pressed(KEY_UP):
		dir += 1.0
	if Input.is_physical_key_pressed(KEY_DOWN):
		dir -= 1.0
	if dir == 0.0:
		if _was_adjusting:
			_was_adjusting = false
			FpvDrone.save_default_cam_tilt(drone.cam_tilt_deg)
		return
	_was_adjusting = true
	drone.cam_tilt_deg = clampf(drone.cam_tilt_deg + dir * TILT_SPEED * delta, TILT_MIN, TILT_MAX)
	show_tilt(drone.cam_tilt_deg)   # also against an end stop, so the player sees he is at the limit


func _process(delta: float) -> void:
	if not visible:
		return
	_left -= delta
	if _left <= 0.0:
		visible = false
		return
	modulate.a = clampf(_left / FADE_TIME, 0.0, 1.0)
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var font := ThemeDB.fallback_font
	var title := "TILT CAMÉRA DRONE"
	var value := "%d°" % roundi(_deg)
	var back := Rect2(c + Vector2(-BAR_W * 0.5 - 26.0, -44.0), Vector2(BAR_W + 52.0, 92.0))
	draw_rect(back, Color(0.02, 0.03, 0.08, 0.6))
	draw_rect(back, Neon.CYAN, false, 1.5)
	draw_string(font, Vector2(back.position.x, back.position.y + 24.0), title, HORIZONTAL_ALIGNMENT_CENTER, back.size.x, 16, Neon.TEXT_DIM)
	draw_string(font, Vector2(back.position.x, back.position.y + 58.0), value, HORIZONTAL_ALIGNMENT_CENTER, back.size.x, 34, Color.WHITE)
	var bar := Rect2(c + Vector2(-BAR_W * 0.5, 36.0 - 8.0), Vector2(BAR_W, 6.0))
	draw_rect(bar, Color(1, 1, 1, 0.18))
	var t := clampf(inverse_lerp(min_deg, max_deg, _deg), 0.0, 1.0)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * t, bar.size.y)), Neon.CYAN)
	draw_circle(bar.position + Vector2(bar.size.x * t, 3.0), 7.0, Color.WHITE)

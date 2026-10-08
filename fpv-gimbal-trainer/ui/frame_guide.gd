class_name FrameGuide
extends Control
## Draws the "good framing" zone: a centred rectangle covering `fraction` of the screen.

@export_range(0.1, 1.0, 0.05) var fraction := 0.6
## Rule-of-thirds grid inside the frame (key G); kept from one session to the next.
static var show_thirds := false
## Everything outside the frame is black: the operator only sees what the gimbal camera shows in the frame (pause menu
## > Gameplay). Kept in the menu preferences.
static var blackout := false


## Remembers the choice in the menu preferences file (the main menu reads it back).
static func save_blackout() -> void:
	var path := "user://menu_prefs.json"
	var prefs := {}
	if FileAccess.file_exists(path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(parsed) == TYPE_DICTIONARY:
			prefs = parsed
	prefs["blackout"] = blackout
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(prefs, "\t"))
## Share of the frame (half-size) that counts as safe: the subject beyond it is too close to the edge.
var safe_margin := 0.15
## true: the subject is inside the frame but beyond the safe zone.
var danger := false:
	set(v):
		if v != danger:
			danger = v
			queue_redraw()
var in_frame := true:
	set(v):
		if v != in_frame:
			in_frame = v
			queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	resized.connect(queue_redraw)


func _draw() -> void:
	var size_px := size * fraction
	var rect := Rect2((size - size_px) * 0.5, size_px)
	if blackout:
		var black := Color.BLACK
		draw_rect(Rect2(0.0, 0.0, size.x, rect.position.y), black)
		draw_rect(Rect2(0.0, rect.end.y, size.x, size.y - rect.end.y), black)
		draw_rect(Rect2(0.0, rect.position.y, rect.position.x, rect.size.y), black)
		draw_rect(Rect2(rect.end.x, rect.position.y, size.x - rect.end.x, rect.size.y), black)
	var col := Color(0.3, 1.0, 0.4, 0.7) if in_frame else Color(1.0, 0.3, 0.2, 0.9)
	if in_frame and danger:
		col = Color(1.0, 0.75, 0.15, 0.9)
	draw_rect(rect, col, false, 2.0)
	if show_thirds:
		var tc := Color(1, 1, 1, 0.45)
		for k in 2:
			var x: float = rect.position.x + rect.size.x * (k + 1.0) / 3.0
			var y: float = rect.position.y + rect.size.y * (k + 1.0) / 3.0
			draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), tc, 1.0)
			draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), tc, 1.0)
	var safe_px := size_px * (1.0 - safe_margin)
	draw_rect(Rect2((size - safe_px) * 0.5, safe_px), Color(1, 1, 1, 0.25), false, 1.0)
	var c := size * 0.5
	draw_line(c + Vector2(-8, 0), c + Vector2(8, 0), col, 1.0)
	draw_line(c + Vector2(0, -8), c + Vector2(0, 8), col, 1.0)

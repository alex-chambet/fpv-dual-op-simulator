class_name CountdownBanner
extends Control
## The 3 - 2 - 1 before a session starts, big in the middle of the screen so the camera operator is ready; "GO" for a
## moment when the run starts. Each number pops in (a little bigger, then to its size) and fades out as its second
## runs out.

const GO_TIME := 0.9
const SHOW_FROM := 3.0     # s before the start: the first number

var _text := ""
var _frac := 0.0           # 0 at the beginning of the second, 1 at its end
var _go_left := 0.0
var _color := Neon.CYAN


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false


## Remaining time of the countdown (s); call every frame while it runs.
func update_remaining(remaining: float) -> void:
	if remaining > SHOW_FROM or remaining <= 0.0:
		if _go_left <= 0.0:
			visible = false
		return
	var n := ceili(remaining)
	_text = str(n)
	_frac = 1.0 - (remaining - float(n - 1))
	_color = [Neon.PINK, Neon.SUN, Neon.CYAN][clampi(n - 1, 0, 2)] if n <= 3 else Neon.CYAN
	_go_left = 0.0
	visible = true
	queue_redraw()


## The run starts: "GO".
func go() -> void:
	_text = "GO"
	_go_left = GO_TIME
	_frac = 0.0
	_color = Neon.GOOD
	visible = true
	queue_redraw()


func _process(delta: float) -> void:
	if _go_left > 0.0:
		_go_left -= delta
		_frac = 1.0 - _go_left / GO_TIME
		if _go_left <= 0.0:
			visible = false
		queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var fs := int(size.y * 0.36)
	var pop := 1.0 + 0.45 * pow(1.0 - clampf(_frac * 3.0, 0.0, 1.0), 2.0)   # a pop at the start of the second
	var alpha := 0.82 * (1.0 - smoothstep(0.65, 1.0, _frac))                            # fades out at its end
	var c := size * 0.5
	var w := font.get_string_size(_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_set_transform(c, 0.0, Vector2(pop, pop))
	var base := Vector2(-w * 0.5, fs * 0.36)
	var col := Color(_color, alpha)
	draw_string_outline(font, base, _text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(fs / 9, 8), Color(0.04, 0.0, 0.1, 0.85 * alpha))
	draw_string(font, base, _text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

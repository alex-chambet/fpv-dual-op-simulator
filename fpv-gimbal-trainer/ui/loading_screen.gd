extends CanvasLayer
## Autoload "LoadingScreen". Launching a session (or the sandbox) can take a moment: the subject's path is planned, the terrain
## built and populated, all before the first frame of the new scene can show - without this, the player just sees
## the last frame of the menu (or of the previous run) hang for that long, which looks like a freeze or a crash.
## run() shows a full-screen loading screen, waits for it to actually be on screen, performs the scene change, then
## hides it again. Being an autoload, it lives under /root and is never freed by the scene change it wraps.

var _dots: Label
var _t := 0.0


func _init() -> void:
	layer = 200
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

	var bg := ColorRect.new()
	bg.color = Neon.NIGHT
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# keep_offsets = true: a fresh Control has a zero-size rect at this point; with keep_offsets = false Godot
	# would "preserve" that zero rect by making the offsets negative, leaving this stuck at size (0, 0) (see
	# the same fix in frame_guide.gd). _init() runs before the node is in the tree, where the parent area size
	# is 0 too, so this particular gotcha would not actually bite here - but keep_offsets = true is correct
	# either way and costs nothing.
	bg.set_anchors_preset(Control.PRESET_FULL_RECT, true)
	add_child(bg)

	var title := Label.new()
	title.text = "CHARGEMENT"
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Neon.TEXT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_CENTER, true)
	title.position = Vector2(-220, -60)
	title.size = Vector2(440, 50)
	bg.add_child(title)

	_dots = Label.new()
	_dots.add_theme_font_size_override("font_size", 40)
	_dots.add_theme_color_override("font_color", Neon.CYAN)
	_dots.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_dots.set_anchors_preset(Control.PRESET_CENTER, true)
	_dots.position = Vector2(224, -60)
	_dots.size = Vector2(60, 50)
	bg.add_child(_dots)


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	_dots.text = ".".repeat(1 + int(_t / 0.35) % 3)


## At most this many frames are drawn behind the loading screen after the scene change, and a frame
## this quick means there is nothing left to compile.
const WARM_FRAMES := 14
const WARM_FAST_MS := 45.0


## Shows the loading screen, waits for it to actually be drawn, runs `action` (typically a scene change), then
## hides it again. Not meant to be awaited: call it plainly (fire-and-forget) so the caller's own return value
## (e.g. a success bool checked right after) is unaffected.
func run(action: Callable) -> void:
	_t = 0.0
	visible = true
	await get_tree().process_frame
	await get_tree().process_frame
	action.call()
	await _warm_up()
	visible = false


## Holds the screen while the new scene draws its first frames.
##
## Building the scene is only half the wait. The first time a level is played, the first frame that
## shows it compiles the shader of every material that comes into view - measured at 941 ms on the
## ski slope, against 47 ms for the frames after it. Hiding the loading screen the moment the scene
## change returned put that second squarely in the player's face, as a frozen half-drawn level.
## Drawn behind the loading screen instead, it is just a load that took a moment longer, which is
## what the screen is for. Once the frames come back quick - the usual case, the shaders being
## cached on disk after the first time - this costs two frames.
func _warm_up() -> void:
	var fast := 0
	for _i in WARM_FRAMES:
		var t0 := Time.get_ticks_msec()
		await get_tree().process_frame
		if Time.get_ticks_msec() - t0 <= WARM_FAST_MS:
			fast += 1
			if fast >= 2:
				return
		else:
			fast = 0

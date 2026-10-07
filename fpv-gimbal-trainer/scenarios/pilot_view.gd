class_name PilotView
extends Node
## The pilot's FPV picture and OSD text: picture-in-picture in the bottom-right corner of the main window, or full
## screen on a second monitor. Used by the 2-player sessions and the sandbox.

## Share of the screen width taken by the pilot picture (4:3).
const PIP_WIDTH := 0.30
const PIP_MARGIN := 14.0

## The OSD label (its text is set by the owner).
var osd: Label

var _win: Window
var _pip: SubViewportContainer
var _vp: SubViewport


## Builds the view of `drone`'s FPV camera. `hud` receives the picture-in-picture; `second_screen` puts it on
## another monitor when there is one.
func build(hud: Node, drone: FpvDrone, second_screen: bool) -> void:
	if second_screen and DisplayServer.get_screen_count() > 1:
		_build_window(drone)
		return
	_pip = SubViewportContainer.new()
	_pip.stretch = true
	hud.add_child(_pip)
	_vp = SubViewport.new()
	_vp.size = Vector2i(384, 288)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_pip.add_child(_vp)
	drone.attach_fpv_camera(_vp)
	osd = Label.new()
	osd.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	osd.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
	osd.add_theme_constant_override("shadow_offset_x", 1)
	osd.add_theme_constant_override("shadow_offset_y", 1)
	hud.add_child(osd)
	get_viewport().size_changed.connect(_layout)
	_layout()


## The pilot picture on its own full-screen window on another monitor (the gimbal operator keeps the main window).
func _build_window(drone: FpvDrone) -> void:
	var main_win := get_window()
	main_win.gui_embed_subwindows = false  # real OS windows, not panels inside the main one
	var screen := 0
	for i in DisplayServer.get_screen_count():
		if i != main_win.current_screen:
			screen = i
			break
	var pos := DisplayServer.screen_get_position(screen)
	var size := DisplayServer.screen_get_size(screen)
	_vp = SubViewport.new()
	_vp.size = Vector2i(size.x * 2 / 3, size.y * 2 / 3)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	drone.attach_fpv_camera(_vp)
	_win = Window.new()
	_win.title = "FPV pilot"
	_win.borderless = true
	_win.unfocusable = true  # the keyboard stays with the gimbal operator window
	_win.position = pos
	_win.size = size
	add_child(_win)
	_win.position = pos
	_win.size = size
	var tex := TextureRect.new()
	tex.texture = _vp.get_texture()
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_SCALE
	tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	_win.add_child(tex)
	osd = Label.new()
	osd.position = Vector2(24, size.y - 140)
	osd.size = Vector2(size.x - 48, 120)
	osd.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	osd.add_theme_font_size_override("font_size", 26)
	osd.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
	osd.add_theme_constant_override("shadow_offset_x", 2)
	osd.add_theme_constant_override("shadow_offset_y", 2)
	_win.add_child(osd)


## Shows / hides the pilot picture and its OSD (a hidden picture is not rendered).
func set_shown(on: bool) -> void:
	if _vp != null:
		var mode := SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
		if _vp.render_target_update_mode != mode:
			_vp.render_target_update_mode = mode
	if _pip != null:
		_pip.visible = on
	if _win != null:
		_win.visible = on
	if osd != null:
		osd.visible = on


## Pilot picture in the bottom-right corner, PIP_WIDTH of the screen width, with its OSD above it.
func _layout() -> void:
	var screen := get_viewport().get_visible_rect().size
	var w := screen.x * PIP_WIDTH
	var h := w * 0.75
	_pip.position = Vector2(screen.x - w - PIP_MARGIN, screen.y - h - PIP_MARGIN)
	_pip.size = Vector2(w, h)  # the container (stretch) gives its size to the pilot's viewport
	osd.position = Vector2(_pip.position.x, _pip.position.y - 84.0)
	osd.size = Vector2(w, 80.0)

class_name DronePip
extends Node
## 1-player mode: the view of the drone's own FPV camera (looking along its nose, tilted up like the pilot's camera
## in the 2-player mode, 105 degrees) as a small picture in the bottom-right corner, so the camera operator can see
## which way the drone is looking. It follows the body of the scripted drone (with its bank and pitch).

const PIP_WIDTH := 0.22      # share of the screen width (4:3)
const PIP_MARGIN := 14.0
const TILT_DEG := 25.0       # same as the pilot camera in the 2-player mode

## Shown or not (pause menu > Gameplay); kept in the menu preferences.
static var enabled := true

var _body: Node3D
var _pip: SubViewportContainer
var _vp: SubViewport
var _cam: Camera3D
var _frame: Panel


static func save_enabled() -> void:
	var path := "user://menu_prefs.json"
	var prefs := {}
	if FileAccess.file_exists(path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(parsed) == TYPE_DICTIONARY:
			prefs = parsed
	prefs["drone_pip"] = enabled
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(prefs, "\t"))


## `body` is the drone body to follow, `hud` the layer that receives the picture.
func setup(body: Node3D, hud: Node) -> void:
	_body = body
	process_priority = 100   # after the flight has placed the body
	_pip = SubViewportContainer.new()
	_pip.stretch = true
	_pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(_pip)
	_vp = SubViewport.new()
	_vp.size = Vector2i(384, 288)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_pip.add_child(_vp)
	_cam = Camera3D.new()
	_cam.fov = 105.0
	_cam.near = 0.05
	_cam.far = 3000.0
	_vp.add_child(_cam)
	_cam.current = true
	_frame = Panel.new()
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.set_border_width_all(2)
	sb.border_color = Neon.PURPLE.lightened(0.3)
	_frame.add_theme_stylebox_override("panel", sb)
	_pip.add_child(_frame)
	_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	var tag := Label.new()
	tag.text = "VUE DRONE"
	tag.add_theme_font_size_override("font_size", 13)
	tag.add_theme_color_override("font_color", Color.WHITE)
	tag.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
	tag.add_theme_constant_override("shadow_offset_x", 1)
	tag.add_theme_constant_override("shadow_offset_y", 1)
	tag.position = Vector2(6, 3)
	_frame.add_child(tag)
	get_viewport().size_changed.connect(_layout)
	_layout()


func _process(_delta: float) -> void:
	if _pip == null or _body == null:
		return
	if _pip.visible != enabled:
		_pip.visible = enabled
		_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if enabled else SubViewport.UPDATE_DISABLED
	if not enabled:
		return
	var b := _body.global_transform.basis.orthonormalized() * Basis(Vector3.RIGHT, deg_to_rad(TILT_DEG))
	_cam.global_transform = Transform3D(b, _body.global_position + _body.global_transform.basis * Vector3(0.0, 0.03, -0.12))


func _layout() -> void:
	var screen := get_viewport().get_visible_rect().size
	var w := screen.x * PIP_WIDTH
	var h := w * 0.75
	_pip.position = Vector2(screen.x - w - PIP_MARGIN, screen.y - h - PIP_MARGIN)
	_pip.size = Vector2(w, h)

extends Node3D
## In-game flight path editor (top-down orbit camera).
##  Left click empty ground : add a point (at the "new point height")
##  Left click / drag a point : select / move it on the horizontal plane
##  PageUp / PageDown : raise / lower selected point    Delete : remove it
##  Right drag : orbit    Middle drag : pan    Wheel : zoom
## Handles are smoothed automatically (Catmull-Rom). Save writes a Curve3D .tres
## you can assign to any FlightPath (or its "curve_file").

const PICK_RADIUS := 0.03
const GRID_HALF := 150
const GRID_STEP := 10

@onready var flight: FlightPath = $FlightPath

var cam: Camera3D
var gizmos := Node3D.new()
var line := MeshInstance3D.new()
var drops := MeshInstance3D.new()
var markers: Array[MeshInstance3D] = []
var mat_line := _unshaded(Color(1.0, 0.6, 0.1))
var mat_drop := _unshaded(Color(1.0, 1.0, 1.0, 0.25))
var mat_normal := _unshaded(Color(0.95, 0.95, 0.95))
var mat_selected := _unshaded(Color(1.0, 0.9, 0.1))
var mat_start := _unshaded(Color(0.2, 1.0, 0.3))

var selected := -1
var dragging := false
var previewing := false
var yaw := 0.5
var pitch := -1.0
var dist := 80.0
var target := Vector3.ZERO

var name_edit: LineEdit
var height_spin: SpinBox
var speed_spin: SpinBox
var closed_check: CheckBox
var status: Label
var panel: Control
var preview_label: Label


func _ready() -> void:
	flight.curve = Curve3D.new()
	flight.playing = false
	cam = Camera3D.new()
	cam.far = 1500.0
	add_child(cam)
	add_child(gizmos)
	_build_grid()
	line.mesh = ImmediateMesh.new()
	drops.mesh = ImmediateMesh.new()
	gizmos.add_child(line)
	gizmos.add_child(drops)
	_build_ui()
	_update_camera()
	cam.make_current()
	_refresh()


static func _unshaded(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


func _build_grid() -> void:
	var mi := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES, _unshaded(Color(0.15, 0.15, 0.18)))
	for i in range(-GRID_HALF, GRID_HALF + 1, GRID_STEP):
		im.surface_add_vertex(Vector3(i, 0.03, -GRID_HALF))
		im.surface_add_vertex(Vector3(i, 0.03, GRID_HALF))
		im.surface_add_vertex(Vector3(-GRID_HALF, 0.03, i))
		im.surface_add_vertex(Vector3(GRID_HALF, 0.03, i))
	im.surface_end()
	mi.mesh = im
	add_child(mi)


# --- UI ------------------------------------------------------------------------

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var pc := PanelContainer.new()
	pc.position = Vector2(10, 10)
	layer.add_child(pc)
	panel = pc
	var v := VBoxContainer.new()
	pc.add_child(v)

	var help := Label.new()
	help.text = "Click ground: add point   Click/drag point: move\nPageUp/PageDown: height   Delete: remove\nRight drag: orbit   Middle drag: pan   Wheel: zoom   Esc: menu"
	v.add_child(help)

	var r1 := HBoxContainer.new()
	v.add_child(r1)
	r1.add_child(_label("Name"))
	name_edit = LineEdit.new()
	name_edit.text = "my_path"
	name_edit.custom_minimum_size.x = 140
	r1.add_child(name_edit)
	r1.add_child(_button("Save", _on_save))
	r1.add_child(_button("Load", _on_load))
	r1.add_child(_button("Clear", _on_clear))

	var r2 := HBoxContainer.new()
	v.add_child(r2)
	r2.add_child(_label("New point height (m)"))
	height_spin = _spin(0.0, 100.0, 0.5, 5.0)
	r2.add_child(height_spin)
	closed_check = CheckBox.new()
	closed_check.text = "Closed loop"
	closed_check.toggled.connect(func(on):
		flight.curve.closed = on
		_refresh())
	r2.add_child(closed_check)

	var r3 := HBoxContainer.new()
	v.add_child(r3)
	r3.add_child(_label("Preview speed (m/s)"))
	speed_spin = _spin(0.5, 40.0, 0.5, 6.0)
	r3.add_child(speed_spin)
	r3.add_child(_button("Preview flight", _start_preview))

	status = _label("")
	v.add_child(status)

	preview_label = _label("PREVIEW - gimbal: arrows/WASD + Q/E or controller - Esc: back to editor")
	preview_label.position = Vector2(10, 10)
	preview_label.visible = false
	layer.add_child(preview_label)


func _label(t: String) -> Label:
	var l := Label.new()
	l.text = t
	return l


func _button(t: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.pressed.connect(cb)
	return b


func _spin(lo: float, hi: float, step: float, val: float) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = val
	return s


# --- Curve editing ---------------------------------------------------------------

func _refresh() -> void:
	var c := flight.curve
	FlightPath.auto_smooth(c)

	while markers.size() < c.point_count:
		var m := MeshInstance3D.new()
		m.mesh = SphereMesh.new()
		gizmos.add_child(m)
		markers.append(m)
	while markers.size() > c.point_count:
		markers.pop_back().queue_free()
	for i in markers.size():
		markers[i].position = c.get_point_position(i)
		markers[i].material_override = mat_selected if i == selected else (mat_start if i == 0 else mat_normal)

	var im := line.mesh as ImmediateMesh
	im.clear_surfaces()
	if c.point_count >= 2:
		im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, mat_line)
		for p in c.get_baked_points():
			im.surface_add_vertex(p)
		im.surface_end()

	var dm := drops.mesh as ImmediateMesh
	dm.clear_surfaces()
	if c.point_count >= 1:
		dm.surface_begin(Mesh.PRIMITIVE_LINES, mat_drop)
		for i in c.point_count:
			var p := c.get_point_position(i)
			dm.surface_add_vertex(p)
			dm.surface_add_vertex(Vector3(p.x, 0.03, p.z))
		dm.surface_end()

	var info := "%d points, %.0f m" % [c.point_count, c.get_baked_length()]
	if selected >= 0 and selected < c.point_count:
		info += "  |  selected #%d  height %.1f m" % [selected, c.get_point_position(selected).y]
	status.text = info


func _pick(mouse: Vector2) -> int:
	var o := cam.project_ray_origin(mouse)
	var n := cam.project_ray_normal(mouse)
	var best := -1
	var best_t := INF
	var c := flight.curve
	for i in c.point_count:
		var to := c.get_point_position(i) - o
		var t := to.dot(n)
		if t > 0.0 and (to - n * t).length() < t * PICK_RADIUS and t < best_t:
			best = i
			best_t = t
	return best


func _plane_hit(mouse: Vector2, height: float) -> Variant:
	return Plane(Vector3.UP, height).intersects_ray(cam.project_ray_origin(mouse), cam.project_ray_normal(mouse))


# --- Input -----------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if previewing:
		if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
			_stop_preview()
		return
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		return
	var c := flight.curve
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				if event.pressed:
					_left_press(event.position)
				else:
					dragging = false
			MOUSE_BUTTON_WHEEL_UP:
				dist = maxf(5.0, dist * 0.9)
			MOUSE_BUTTON_WHEEL_DOWN:
				dist = minf(600.0, dist * 1.1)
		_update_camera()
	elif event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			yaw -= event.relative.x * 0.005
			pitch = clampf(pitch - event.relative.y * 0.005, -1.55, -0.1)
		elif event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
			target += (-cam.basis.x * event.relative.x + cam.basis.y * event.relative.y) * dist * 0.0015
			target.y = 0.0
		elif dragging and selected >= 0:
			var p := c.get_point_position(selected)
			var hit = _plane_hit(event.position, p.y)
			if hit != null:
				c.set_point_position(selected, Vector3(hit.x, p.y, hit.z))
				_refresh()
		_update_camera()
	elif event is InputEventKey and event.pressed and selected >= 0 and selected < c.point_count:
		var p := c.get_point_position(selected)
		match event.physical_keycode:
			KEY_PAGEUP:
				c.set_point_position(selected, p + Vector3.UP * 0.5)
			KEY_PAGEDOWN:
				c.set_point_position(selected, Vector3(p.x, maxf(0.0, p.y - 0.5), p.z))
			KEY_DELETE, KEY_BACKSPACE:
				c.remove_point(selected)
				selected = -1
		_refresh()


func _left_press(pos: Vector2) -> void:
	var idx := _pick(pos)
	if idx >= 0:
		selected = idx
		dragging = true
	else:
		var hit = _plane_hit(pos, height_spin.value)
		if hit != null:
			flight.curve.add_point(hit)
			selected = flight.curve.point_count - 1
	_refresh()


func _update_camera() -> void:
	var offset := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch) * Vector3(0, 0, dist)
	cam.position = target + offset
	cam.look_at(target, Vector3.UP)


func _process(_delta: float) -> void:
	if previewing:
		return
	var s := cam.position.distance_to(target) * 0.012
	for m in markers:
		m.scale = Vector3.ONE * s


# --- Preview / files ---------------------------------------------------------------

func _start_preview() -> void:
	if flight.curve.point_count < 2:
		status.text = "Need at least 2 points to preview."
		return
	previewing = true
	gizmos.visible = false
	panel.visible = false
	preview_label.visible = true
	flight.base_speed = speed_spin.value
	flight.loop_path = flight.curve.closed
	flight.restart()
	flight.rig.recenter()
	flight.playing = true
	flight.rig.camera.make_current()


func _stop_preview() -> void:
	previewing = false
	flight.playing = false
	gizmos.visible = true
	panel.visible = true
	preview_label.visible = false
	cam.make_current()


func _paths_dir() -> String:
	return "res://flight/paths/" if OS.has_feature("editor") else "user://flight_paths/"


func _file_path() -> String:
	return _paths_dir() + name_edit.text.strip_edges().validate_filename() + ".tres"


func _on_save() -> void:
	if flight.curve.point_count < 2:
		status.text = "Nothing to save (need 2+ points)."
		return
	DirAccess.make_dir_recursive_absolute(_paths_dir())
	var path := _file_path()
	var err := ResourceSaver.save(flight.curve, path)
	status.text = ("Saved " + path) if err == OK else "Save failed: " + error_string(err)


func _on_load() -> void:
	var path := _file_path()
	if not FileAccess.file_exists(path):
		status.text = "Not found: " + path
		return
	var c := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as Curve3D
	if c == null:
		status.text = "Not a Curve3D: " + path
		return
	flight.curve = c.duplicate()
	closed_check.set_pressed_no_signal(flight.curve.closed)
	selected = -1
	_refresh()
	status.text = "Loaded " + path


func _on_clear() -> void:
	flight.curve = Curve3D.new()
	closed_check.set_pressed_no_signal(false)
	selected = -1
	_refresh()

class_name DuoSession
extends Node
## 2-player mode, attached to a ScenarioBase: the pilot flies the drone (FpvDrone, acro, second controller)
## while the gimbal operator films. Owns the drone, the pilot's FPV picture-in-picture + OSD and the pilot score.
## The subject stays scripted (it follows its path at its own speed).

## Share of the screen width taken by the pilot picture (4:3).
const PIP_WIDTH := 0.30
const PIP_MARGIN := 14.0
const ARM_THROTTLE := 0.08

var scn: ScenarioBase
var drone: FpvDrone
var scorer := PilotScorer.new()
## Replay / tests: inputs [throttle, yaw, pitch, roll] used instead of the controller.
var input_override: Array = []

## true: the pilot picture goes full screen on a second monitor (set by the menu); ignored with a single monitor.
static var dual_screen := false

var _win: Window
var _osd: Label
var _pip: SubViewportContainer
var _vp: SubViewport
var _grid: Dictionary = {}
var _grid_built := false


func setup(s: ScenarioBase) -> void:
	scn = s
	s.add_child(self)
	drone = FpvDrone.new()
	add_child(drone)
	drone.ground_fn = s._clearance_fn()
	drone.obstacle_fn = Callable(self, "obstacle_push")
	# Start near the planned drone position, nose towards the subject
	var start := s.drone_pts[0]
	var gy := 0.0
	if drone.ground_fn.is_valid():
		gy = float(drone.ground_fn.call(start.x, start.z))
	start.y = gy + drone.radius  # takes off from the ground, like a real quad
	var look := s.subject_pts[mini(s.subject_pts.size() - 1, 12)] - start
	drone.reset_to(start, look)
	# The gimbal follows the heading of the drone; the body of the drone is placed by us, not by the path
	s.flight.playing = false
	s.flight.set_process(false)
	s.flight.body.top_level = true
	# The gimbal stays independent of the drone: its pan is fixed in the world (only the position follows the drone)
	s.flight.rig.yaw_follow = false
	s.flight.rig.heading_provider = func(): return drone.heading
	_apply_body()
	scorer.ideal_distance = 14.0 * pow(float(s.matrix.lens) / 24.0, 0.7)
	_build_pip()


func _build_pip() -> void:
	if dual_screen and DisplayServer.get_screen_count() > 1:
		_build_pilot_window()
		return
	var hud: Node = scn.get_node("HUD")
	_pip = SubViewportContainer.new()
	_pip.stretch = true
	hud.add_child(_pip)
	_vp = SubViewport.new()
	_vp.size = Vector2i(384, 288)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_pip.add_child(_vp)
	drone.attach_fpv_camera(_vp)
	_osd = Label.new()
	_osd.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_osd.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
	_osd.add_theme_constant_override("shadow_offset_x", 1)
	_osd.add_theme_constant_override("shadow_offset_y", 1)
	hud.add_child(_osd)
	get_viewport().size_changed.connect(_layout_pip)
	_layout_pip()


## The pilot picture on its own full-screen window on another monitor (the gimbal operator keeps the main window).
func _build_pilot_window() -> void:
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
	_osd = Label.new()
	_osd.position = Vector2(24, size.y - 140)
	_osd.size = Vector2(size.x - 48, 120)
	_osd.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_osd.add_theme_font_size_override("font_size", 26)
	_osd.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
	_osd.add_theme_constant_override("shadow_offset_x", 2)
	_osd.add_theme_constant_override("shadow_offset_y", 2)
	_win.add_child(_osd)


## Pilot picture in the bottom-right corner, PIP_WIDTH of the screen width, with its OSD above it.
func _layout_pip() -> void:
	var screen := get_viewport().get_visible_rect().size
	var w := screen.x * PIP_WIDTH
	var h := w * 0.75
	_pip.position = Vector2(screen.x - w - PIP_MARGIN, screen.y - h - PIP_MARGIN)
	_pip.size = Vector2(w, h)
	_vp.size = Vector2i(int(w), int(h))
	_osd.position = Vector2(_pip.position.x, _pip.position.y - 84.0)
	_osd.size = Vector2(w, 80.0)

## [throttle, yaw, pitch, roll] of the pilot right now.
func current_inputs() -> Array:
	# Same precision as the recording, so a replay reproduces the flight exactly
	var src: Array = input_override if not input_override.is_empty() else ControllerInput.pilot_inputs
	return [snappedf(src[0], 0.00001), snappedf(src[1], 0.00001), snappedf(src[2], 0.00001), snappedf(src[3], 0.00001)]


func step(dt: float, inputs: Array, running: bool, hidden: bool) -> void:
	dt = snappedf(dt, 0.0000001)  # as recorded
	# Safety: the motors are armed only when the throttle stick has been seen at the minimum
	if not drone.armed and float(inputs[0]) <= ARM_THROTTLE:
		drone.armed = true
	drone.step(dt, inputs)
	_apply_body()
	if running:
		scorer.update(dt, drone.position, drone.velocity, scn.subject.torso_position(), hidden)


func _apply_body() -> void:
	scn.flight.body.global_position = drone.position


func update_osd() -> void:
	if _osd == null:
		return
	var gy := 0.0
	if drone.ground_fn.is_valid():
		gy = float(drone.ground_fn.call(drone.position.x, drone.position.z))
	var d := drone.position.distance_to(scn.subject.torso_position())
	var inp := current_inputs()
	var dev := "NO PILOT CONTROLLER (menu > Configuration manette > Drone)"
	if not input_override.is_empty():
		dev = "(scripted pilot)"
	elif ControllerInput.has_pilot_device():
		dev = "%s  [thr %.0f%% yaw %+.2f pitch %+.2f roll %+.2f]" % [Input.get_joy_name(ControllerInput.pilot_device), 100.0 * float(inp[0]), float(inp[1]), float(inp[2]), float(inp[3])]
	var arm := "" if drone.armed else "\nDISARMED: put the throttle stick at its MINIMUM to arm, then take off"
	_osd.text = "PILOT   ALT %.0f m   %.0f km/h   subject %.0f m   THR %.0f%%   crashes %d\n%s%s" % [
		drone.position.y - gy, drone.speed_kmh(), d, 100.0 * float(inp[0]), drone.crash_count, dev, arm]


## Initial state of the drone, saved with the recording (the pilot may fly during the countdown).
func state() -> Dictionary:
	var q := drone.orientation
	return {
		"pos": [drone.position.x, drone.position.y, drone.position.z],
		"vel": [drone.velocity.x, drone.velocity.y, drone.velocity.z],
		"q": [q.x, q.y, q.z, q.w],
		"omega": [drone.omega.x, drone.omega.y, drone.omega.z],
		"thrust": drone.thrust,
		"heading": drone.heading,
		"armed": drone.armed,
	}


func restore(d: Dictionary) -> void:
	var p: Array = d.pos
	var v: Array = d.vel
	var q: Array = d.q
	var o: Array = d.omega
	drone.position = Vector3(p[0], p[1], p[2])
	drone.velocity = Vector3(v[0], v[1], v[2])
	drone.orientation = Quaternion(q[0], q[1], q[2], q[3])
	drone.omega = Vector3(o[0], o[1], o[2])
	drone.thrust = float(d.thrust)
	drone.heading = float(d.heading)
	drone.armed = bool(d.get("armed", true))
	drone.crash_count = 0
	drone._since_crash = 10.0
	drone._sync()
	_apply_body()


func start_run() -> void:
	drone.crash_count = 0
	scorer = PilotScorer.new()
	scorer.ideal_distance = 14.0 * pow(float(scn.matrix.lens) / 24.0, 0.7)


## Pilot results for the result screen.
func results() -> Dictionary:
	return scorer.results(drone.crash_count)


# --- Obstacles (trees, rocks, walls of the scenario) ----------------------------------------------

func _build_grid() -> void:
	_grid_built = true
	for i in scn.occ_pos.size():
		var key := Vector2i(floori(scn.occ_pos[i].x / 8.0), floori(scn.occ_pos[i].z / 8.0))
		if not _grid.has(key):
			_grid[key] = []
		_grid[key].append(i)


## Horizontal push getting a sphere of radius r at `pos` out of the obstacles of the scenario.
func obstacle_push(pos: Vector3, r: float) -> Vector3:
	if not _grid_built:
		_build_grid()
	var cx := floori(pos.x / 8.0)
	var cz := floori(pos.z / 8.0)
	var best := Vector3.ZERO
	for gx in range(cx - 1, cx + 2):
		for gz in range(cz - 1, cz + 2):
			var list: Array = _grid.get(Vector2i(gx, gz), [])
			for i in list:
				var base: Vector3 = scn.occ_pos[i]
				var y := pos.y - base.y
				if y < -1.0:
					continue
				var rad := 0.0
				var size: float = scn.occ_a[i]
				if scn.occ_kind[i] == 0:
					if y < scn.occ_h[i]:
						rad = size
				else:
					rad = PropFactory.tree_radius_at(y / size) * size
				if rad <= 0.0:
					continue
				var off := Vector2(pos.x - base.x, pos.z - base.z)
				var dist := off.length()
				if dist < rad + r:
					var dir := off / dist if dist > 0.001 else Vector2(1, 0)
					var push := Vector3(dir.x, 0.0, dir.y) * (rad + r - dist)
					if push.length() > best.length():
						best = push
	return best

class_name Sandbox
extends Node3D
## Sandbox mode: the Départementale countryside (SandboxWorld) with no time limit, no subject and no score.
## The drone flies freely and the gimbal operator films whatever they like: traffic, cyclists, villagers...
##  - drone in ACRO with the pilot controller (menu > Configuration manette > Drone), as in the 2-player mode;
##  - without a pilot controller (or with key M), an assisted drone flown with the keyboard:
##    I/K forward/back, J/L left/right, U/O turn, Y/H up/down, Shift = fast. It holds its position when released.
## Gimbal as everywhere (controller, or arrows/WASD + Q/E). Esc: pause, Backspace: drone back to the take-off spot.

const MENU_SCENE := "res://scenes/main_menu.tscn"
const PROFILE_NAMES := ["Slow", "Medium", "Fast"]

## Lens of the gimbal camera (mm), set by the menu.
static var lens_mm := 24

var world: SandboxWorld
var traffic: SandboxTraffic
var people: Pedestrians
var drone: FpvDrone
var rig: GimbalRig
var grass: GrassField
var assisted := true

var _env: WorldEnvironment
var _sun: DirectionalLight3D
var _body: Node3D
var _view: PilotView
var _hud: Label
var _guide: FrameGuide
var _hud_layer: CanvasLayer
var _pause: PauseMenu
var _time := 0.0
var _yaw_rate := 0.0
var _vel := Vector3.ZERO


func _ready() -> void:
	get_tree().paused = false
	Vegetation.snow_cover = 0.0
	Rocks.moss_amount = 0.25
	_build_environment()
	world = SandboxWorld.new()
	world.build(self)
	traffic = SandboxTraffic.new()
	traffic.name = "Traffic"
	add_child(traffic)
	traffic.setup(world)
	people = Pedestrians.new()
	people.name = "Pedestrians"
	add_child(people)
	people.setup(world)
	_build_drone()
	_build_hud()
	grass = GrassField.new()
	grass.name = "Grass"
	add_child(grass)
	grass.setup(world.grass_params(), TerrainBuilder.last_info, world.mask, rig.camera)
	apply_graphics()


func _build_environment() -> void:
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	e.sky = Sky.new()
	e.sky.sky_material = ProceduralSkyMaterial.new()
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.tonemap_white = 4.0
	e.ssao_enabled = true
	e.glow_enabled = true
	e.fog_enabled = true
	e.adjustment_enabled = true
	_env = WorldEnvironment.new()
	_env.environment = e
	add_child(_env)
	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = true
	_sun.shadow_blur = 1.5
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	add_child(_sun)
	var looks := EnvironmentBuilder.new()
	looks.style = load("res://scenarios/environments/styles/departementale.tres")
	looks.apply_to_scene(_env, _sun)
	var cam_look := CanvasLayer.new()
	cam_look.set_script(load("res://ui/camera_look.gd"))
	add_child(cam_look)


## Applies the graphics quality (GraphicsSettings); called again when it changes in the pause menu.
func apply_graphics() -> void:
	GraphicsSettings.apply(_env.environment, _sun, get_viewport())
	Vegetation.update_ranges(get_tree())
	if grass != null:
		grass.apply_quality()


func _build_drone() -> void:
	drone = FpvDrone.new()
	drone.name = "Drone"
	add_child(drone)
	drone.ground_fn = Callable(world, "ground")
	drone.obstacle_fn = Callable(self, "_obstacle_push")
	_body = Node3D.new()
	_body.name = "DroneBody"
	_body.top_level = true
	add_child(_body)
	rig = load("res://gimbal/gimbal_rig.tscn").instantiate()
	rig.yaw_follow = false  # the gimbal stays independent of the drone
	rig.heading_provider = func(): return drone.heading
	_body.add_child(rig)
	rig.camera.fov = SessionConfig.fov_for(lens_mm)
	rig.camera.far = 9000.0
	rig.camera.add_child(MotionBlur.new())
	_reset_drone()
	assisted = not ControllerInput.has_pilot_device()


func _reset_drone() -> void:
	var p := world.start_pos
	p.y = world.ground(p.x, p.z) + drone.radius
	drone.reset_to(p, world.start_look)
	drone.armed = false
	_vel = Vector3.ZERO
	_yaw_rate = 0.0
	_body.global_position = drone.position


func _build_hud() -> void:
	_hud_layer = CanvasLayer.new()
	_hud_layer.name = "HUD"
	add_child(_hud_layer)
	_guide = FrameGuide.new()
	_guide.fraction = 0.6
	_hud_layer.add_child(_guide)
	_hud = Label.new()
	_hud.position = Vector2(12, 12)
	_hud.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
	_hud.add_theme_constant_override("shadow_offset_x", 1)
	_hud.add_theme_constant_override("shadow_offset_y", 1)
	_hud_layer.add_child(_hud)
	_view = PilotView.new()
	add_child(_view)
	_view.build(_hud_layer, drone, DuoSession.dual_screen)
	_pause = PauseMenu.new()
	add_child(_pause)
	_pause.resume_requested.connect(_close_pause)
	_pause.restart_requested.connect(func():
		get_tree().paused = false
		get_tree().reload_current_scene())
	_pause.quit_requested.connect(func():
		get_tree().paused = false
		get_tree().change_scene_to_file(MENU_SCENE))


func _obstacle_push(pos: Vector3, r: float) -> Vector3:
	var a := world.push(pos, r)
	var b := traffic.push(pos, r)
	return a if a.length() > b.length() else b


func _process(delta: float) -> void:
	_time += delta
	if assisted:
		_fly_assisted(delta)
	else:
		var inp: Array = ControllerInput.pilot_inputs
		if not drone.armed and float(inp[0]) <= DuoSession.ARM_THROTTLE:
			drone.armed = true
		drone.step(delta, inp)
	_body.global_position = drone.position
	_view.set_shown(not assisted)
	_guide.visible = FrameGuide.show_thirds
	_update_hud()


## Assisted flight (keyboard): the sticks give velocities, the drone accelerates smoothly and holds its position.
func _fly_assisted(delta: float) -> void:
	var fast := Input.is_key_pressed(KEY_SHIFT)
	var fwd := _key(KEY_I) - _key(KEY_K)
	var side := _key(KEY_L) - _key(KEY_J)
	var up := _key(KEY_Y) - _key(KEY_H)
	var turn := _key(KEY_O) - _key(KEY_U)
	var speed := 20.0 if fast else 9.0
	var yaw_basis := Basis(Vector3.UP, drone.heading)
	var target := yaw_basis * Vector3(side * speed, up * (6.0 if fast else 3.5), -fwd * speed)
	var before := _vel
	_vel = _vel.move_toward(target, (9.0 if fast else 6.0) * delta)
	_yaw_rate = move_toward(_yaw_rate, -turn * deg_to_rad(75.0), deg_to_rad(240.0) * delta)
	drone.heading = wrapf(drone.heading + _yaw_rate * delta, -PI, PI)
	var p := drone.position + _vel * delta
	var push := _obstacle_push(p, drone.radius)
	if push.length() > 0.0:
		p += push
		var n := push.normalized()
		_vel -= n * minf(_vel.dot(n), 0.0)
	var gy := world.ground(p.x, p.z) + drone.radius
	if p.y < gy:
		p.y = gy
		_vel.y = maxf(_vel.y, 0.0)
	p.y = minf(p.y, drone.max_height)
	drone.position = p
	drone.velocity = _vel
	# the body leans with the acceleration, like a real quad (the gimbal compensates)
	var acc := (_vel - before) / maxf(delta, 0.0001)
	var local := yaw_basis.inverse() * acc
	var tilt := Basis(Vector3.UP, drone.heading) * Basis(Vector3.RIGHT, clampf(local.z * 0.05, -0.5, 0.5)) \
			* Basis(Vector3.BACK, clampf(-local.x * 0.05, -0.5, 0.5))
	drone.orientation = tilt.get_rotation_quaternion()
	drone._sync()


func _key(k: Key) -> float:
	return 1.0 if Input.is_key_pressed(k) else 0.0


func _update_hud() -> void:
	var gy := world.ground(drone.position.x, drone.position.z)
	var mode := "ASSISTÉ (clavier : I/K J/L avancer / côtés, U/O tourner, Y/H monter / descendre, Maj rapide)" if assisted \
			else "ACRO (manette pilote)" + ("" if drone.armed else " - DÉSARMÉ : gaz au minimum pour armer")
	var t := int(_time)
	_hud.text = "BAC À SABLE - Départementale   temps libre %02d:%02d   %d véhicules\nDrone %s\nAlt %.0f m   %.0f km/h   %d mm   gimbal [%s]  pan %+.0f°  tilt %+.0f°  roll %+.0f°\nFlèches/WASD : gimbal   Q/E : roll   1/2/3 : profil   G : grille   M : mode drone   Retour : drone au départ   Échap : pause   F1 : masquer" % [
			t / 60, t % 60, traffic.count(), mode, drone.position.y - gy, drone.speed_kmh(), lens_mm,
			PROFILE_NAMES[rig.pan_profile], rig.angles[0], rig.angles[1], rig.angles[2]]
	if _view.osd != null:
		_view.osd.text = "PILOTE   ALT %.0f m   %.0f km/h   %s" % [drone.position.y - gy, drone.speed_kmh(),
				"assisté" if assisted else ("acro, %d crash" % drone.crash_count)]


func _set_profile(p: GimbalRig.SpeedProfile) -> void:
	rig.pan_profile = p
	rig.tilt_profile = p
	rig.roll_profile = p


func _open_pause() -> void:
	get_tree().paused = true
	_pause.open()


func _close_pause() -> void:
	_pause.close()
	get_tree().paused = false


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.physical_keycode:
		KEY_ESCAPE:
			_open_pause()
		KEY_1:
			_set_profile(GimbalRig.SpeedProfile.SLOW)
		KEY_2:
			_set_profile(GimbalRig.SpeedProfile.MEDIUM)
		KEY_3:
			_set_profile(GimbalRig.SpeedProfile.FAST)
		KEY_G:
			FrameGuide.show_thirds = not FrameGuide.show_thirds
			_guide.queue_redraw()
		KEY_M:
			assisted = not assisted
			if not assisted:
				drone.armed = false
		KEY_BACKSPACE:
			_reset_drone()
		KEY_F1:
			_hud_layer.visible = not _hud_layer.visible
		_:
			return
	get_viewport().set_input_as_handled()

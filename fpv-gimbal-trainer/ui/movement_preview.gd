class_name MovementPreview
extends SubViewportContainer
## The little demo of a movement drill, on the setup page of the "Mouvements" menu: the figure
## flying, on a loop.
##
## It is not a video and not a drawing: it asks MovementPlanner for the very flight the drill will
## fly, at the level chosen, and plays it back. What the demo shows is therefore what the exercise
## does - change the level and the demo changes with it.
##
## Everything is drawn in the frame of the subject (which goes straight ahead, so that frame is
## just a translation): the subject stays in the middle, the drone turns around it and the neon
## grid of the ground scrolls backwards at the speed of the subject. A drill figure comes back to
## where it started after one period, and the planner fits a whole number of periods into a run, so
## the loop closes on itself with nothing to hide.

## Subject speed and duration of the demo flight (a run long enough for one whole figure).
const DEMO_SPEED := 4.0
const DEMO_TIME := 30.0
const SAMPLE_DT := 0.05
## Played back this much faster than real time.
const PLAYBACK := 1.6
## Samples of the bright trail behind the drone (the rest of the figure stays drawn, but dim).
const TRAIL := 110

var _vp: SubViewport
var _cam: Camera3D
var _subject: Node3D
var _drone: Node3D
var _sight: MeshInstance3D
var _trail: MeshInstance3D
var _whole: MeshInstance3D
var _grid: Node3D
var _grid_mi: MeshInstance3D
var _step := 10.0                  ## spacing of the ground grid, m (sized to the figure)
var _dist := 40.0                  ## how far the camera had to back off to frame the figure
var _rel := PackedVector3Array()   ## drone position relative to the subject, one per sample
var _movement := ""
var _level := -1
var _t := 0.0


func _init() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vp = SubViewport.new()
	_vp.transparent_bg = false
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.msaa_3d = Viewport.MSAA_4X
	add_child(_vp)
	_build_world()
	set_process(false)


# --- The little world -----------------------------------------------------------------------

func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Neon.NIGHT
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.45, 0.35, 0.6)
	e.ambient_light_energy = 1.1
	env.environment = e
	_vp.add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-48.0), deg_to_rad(38.0), 0.0)
	sun.light_energy = 0.7
	sun.light_color = Color(1.0, 0.85, 0.95)
	sun.shadow_enabled = false
	_vp.add_child(sun)

	_cam = Camera3D.new()
	_cam.fov = 46.0
	_cam.near = 0.3
	_cam.far = 900.0
	_vp.add_child(_cam)

	_grid = Node3D.new()
	_grid_mi = MeshInstance3D.new()
	_grid_mi.mesh = ImmediateMesh.new()
	_grid_mi.material_override = _line_mat()
	_grid.add_child(_grid_mi)
	_vp.add_child(_grid)

	# the whole figure, drawn dim: the shape is readable even standing still
	_whole = _line_node(Color(Neon.PINK, 0.3))
	_vp.add_child(_whole)

	_subject = Node3D.new()
	_subject.add_child(_capsule(1.8, 0.28, Neon.SUN))
	_subject.add_child(_arrow(Neon.SUN))
	_vp.add_child(_subject)

	_drone = Node3D.new()
	_drone.add_child(_quad())
	_vp.add_child(_drone)

	_sight = _line_node(Color(Neon.CYAN, 0.45))
	_vp.add_child(_sight)
	_trail = _line_node(Neon.PINK)
	_vp.add_child(_trail)


## The synthwave grid of the ground: lines along and across, fading out with the distance. The
## spacing is sized to the figure, so a tight orbit and a wide flyby both read at a glance.
func _build_grid(step: float, reach: float) -> void:
	var im: ImmediateMesh = _grid_mi.mesh
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var n := int(reach / step)
	for i in range(-n, n + 1):
		var u := i * step
		for pair in [[Vector3(u, 0, -reach), Vector3(u, 0, reach)],
				[Vector3(-reach, 0, u), Vector3(reach, 0, u)]]:
			for p in pair:
				im.surface_set_color(Color(Neon.PURPLE, 0.6 * (1.0 - absf(u) / reach)))
				im.surface_add_vertex(p)
	im.surface_end()


func _line_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.disable_receive_shadows = true
	# the paths are ribbons facing the camera: a strip alternates its winding, so half of it would
	# be culled away
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _line_node(col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = ImmediateMesh.new()
	mi.material_override = _line_mat()
	mi.set_meta("colour", col)
	return mi


func _glow(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 1.4
	m.roughness = 0.5
	return m


func _capsule(height: float, radius: float, col: Color) -> MeshInstance3D:
	var cm := CapsuleMesh.new()
	cm.height = height
	cm.radius = radius
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	mi.material_override = _glow(col)
	mi.position.y = height * 0.5
	return mi


## A flat triangle on the ground showing which way the subject is going (+Z).
func _arrow(col: Color) -> MeshInstance3D:
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for p in [Vector3(0, 0.06, 2.6), Vector3(-0.9, 0.06, 0.9), Vector3(0.9, 0.06, 0.9)]:
		im.surface_add_vertex(p)
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	var m := _glow(col)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	return mi


## The drone: a body and four arms, small but readable against the grid.
func _quad() -> Node3D:
	var root := Node3D.new()
	var body := BoxMesh.new()
	body.size = Vector3(1.1, 0.4, 1.4)
	var mi := MeshInstance3D.new()
	mi.mesh = body
	mi.material_override = _glow(Neon.CYAN)
	root.add_child(mi)
	var arm := BoxMesh.new()
	arm.size = Vector3(0.18, 0.1, 0.18)
	for dx in [-1.0, 1.0]:
		for dz in [-1.0, 1.0]:
			var a := MeshInstance3D.new()
			a.mesh = arm
			a.material_override = _glow(Neon.PINK)
			a.position = Vector3(dx * 0.85, 0.12, dz * 0.95)
			a.scale = Vector3(4.0, 1.0, 4.0)
			root.add_child(a)
	# a short snout pointing where the camera looks (the drone node is aimed at the subject)
	var nose := BoxMesh.new()
	nose.size = Vector3(0.3, 0.3, 1.1)
	var nm := MeshInstance3D.new()
	nm.mesh = nose
	nm.material_override = _glow(Neon.SUN)
	nm.position = Vector3(0, 0, -0.9)
	root.add_child(nm)
	return root


# --- The flight -------------------------------------------------------------------------------

## Plans the figure and starts the loop. Cheap when nothing changed.
func show_movement(movement: String, level: int) -> void:
	if movement == _movement and level == _level:
		set_process(visible)
		return
	_movement = movement
	_level = level
	_rel = _plan(movement, level)
	_t = 0.0
	_frame_camera()
	_line(_whole, _rel, Color(Neon.PURPLE, 0.5), Color(Neon.PURPLE, 0.5), 0.5)
	set_process(not _rel.is_empty())


## The drone flight of one drill run, in the frame of the subject. The subject walks straight along
## +Z at a constant speed, so that frame is a plain translation and the figure is exactly what the
## planner will fly in the drill itself.
func _plan(movement: String, level: int) -> PackedVector3Array:
	var n := int(DEMO_TIME / SAMPLE_DT)
	var S := PackedVector3Array()
	S.resize(n)
	for i in n:
		S[i] = Vector3(0.0, 0.0, i * DEMO_SPEED * SAMPLE_DT)
	var res := MovementPlanner.plan(movement, S, {
		"level": level, "side": 1.0, "seed": 7, "occlusion": 0.0,
		"speed_hint": DEMO_SPEED, "min_speed": DEMO_SPEED, "min_height": 2.0,
		"subject_size": 1.8, "distance_scale": 1.0, "speed_variation": 0.0,
	})
	var D: PackedVector3Array = res.drone
	var out := PackedVector3Array()
	out.resize(mini(D.size(), n))
	for i in out.size():
		out[i] = D[i] - S[i]
	return out


## Puts the camera where the figure and the subject both fit, seen from three quarters and well
## above - the angle from which a flight path reads, rather than one of the drone's own views.
## The distance is worked out rather than guessed: the camera backs off until the last point of the
## figure falls inside the frame, so a tight orbit and a wide flyby are both framed the same way.
const VIEW_DIR := Vector3(0.70, 0.95, 0.80)
const MARGIN := 1.14


func _frame_camera() -> void:
	if _rel.is_empty():
		return
	var lo := Vector3(-2, 0, -2)
	var hi := Vector3(2, 2, 2)
	for p in _rel:
		lo = lo.min(p)
		hi = hi.max(p)
	var centre := (lo + hi) * 0.5
	var dir := VIEW_DIR.normalized()
	var fwd := -dir
	var right := fwd.cross(Vector3.UP).normalized()
	var up := right.cross(fwd)
	var aspect := 16.0 / 9.0
	if size.y > 1.0:
		aspect = size.x / size.y
	var tan_v := tan(deg_to_rad(_cam.fov * 0.5)) / MARGIN
	var tan_h := tan_v * aspect
	var dist := 8.0
	for p in _rel:
		var q := p - centre
		var depth := q.dot(fwd)
		dist = maxf(dist, maxf(absf(q.dot(right)) / tan_h, absf(q.dot(up)) / tan_v) - depth)
	_dist = dist
	_step = clampf(snappedf(dist / 5.0, 5.0), 5.0, 40.0)
	_build_grid(_step, _step * 16.0)
	_cam.position = centre + dir * dist
	_cam.look_at(centre, Vector3.UP)
	# the subject and the drone keep the same size on screen whatever the figure
	var k := _scale()
	_subject.scale = Vector3.ONE * k
	_drone.scale = Vector3.ONE * k


func _process(delta: float) -> void:
	if _rel.is_empty():
		return
	_t = fposmod(_t + delta * PLAYBACK, DEMO_TIME)
	var f := _t / SAMPLE_DT
	var i := clampi(int(f), 0, _rel.size() - 1)
	var pos: Vector3 = _rel[i].lerp(_rel[mini(i + 1, _rel.size() - 1)], f - i)
	var aim := Vector3(0.0, 1.2, 0.0)
	_drone.position = pos
	if pos.distance_to(aim) > 0.5:
		_drone.look_at(aim, Vector3.UP)
		_drone.scale = Vector3.ONE * _scale()  # look_at leaves an orthonormal basis behind
	# the ground slides backwards: the subject is walking, even though it stays in the middle
	_grid.position.z = -fposmod(_t * DEMO_SPEED, _step)
	_line(_sight, PackedVector3Array([pos, aim]), Color(Neon.CYAN, 0.35), Color(Neon.CYAN, 0.1), 0.25)
	_line(_trail, _tail(i), Color(Neon.PINK, 0.0), Color(Neon.PINK, 1.0), 1.1)


## The last TRAIL samples flown, wrapping round the end of the loop (the figure is a closed one).
func _tail(i: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	var n := _rel.size()
	for k in range(TRAIL, -1, -1):
		out.append(_rel[posmod(i - k, n)])
	return out


## A path drawn as a ribbon facing the camera rather than a line: a one-pixel line vanishes at the
## size of a menu card. The width is a share of the camera distance, so it is the same on screen
## whatever the size of the figure.
func _line(node: MeshInstance3D, pts: PackedVector3Array, from: Color, to: Color,
		width := 1.0) -> void:
	var im: ImmediateMesh = node.mesh
	im.clear_surfaces()
	var n := pts.size()
	if n < 2:
		return
	var view := _cam.transform.basis.z
	var half := 0.5 * width * _scale()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for k in n:
		var tan := (pts[mini(k + 1, n - 1)] - pts[maxi(k - 1, 0)])
		if tan.length_squared() < 0.000001:
			tan = Vector3.FORWARD
		var side := tan.cross(view)
		if side.length_squared() < 0.000001:
			side = tan.cross(Vector3.UP)
		side = side.normalized() * half
		im.surface_set_color(from.lerp(to, float(k) / float(n - 1)))
		im.surface_add_vertex(pts[k] - side)
		im.surface_set_color(from.lerp(to, float(k) / float(n - 1)))
		im.surface_add_vertex(pts[k] + side)
	im.surface_end()


## Size of a marker (and the width of a ribbon) so that it reads the same on screen whatever the
## size of the figure: a share of how far the camera had to back off.
func _scale() -> float:
	return clampf(_dist * 0.032, 0.5, 4.0)


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		set_process(visible and not _rel.is_empty())

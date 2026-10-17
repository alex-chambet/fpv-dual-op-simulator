class_name CourseIntro
extends Node
## Before each session (1 or 2 players): a flight over the course with an animated line that is drawn along the path
## the subject is going to take, so the camera operator understands the line he has to film. A camera follows the
## head of the line from behind and above, close to the ground (like a drone would), so the terrain and the
## environment look as they do in the session. The line is drawn in a time that follows the length of the course
## (about 95 m/s), the flight stays a moment at the finish, then the session goes on with its countdown; Enter skips
## it at any time. Not shown again when the same session is restarted.

const LEAD_TIME := 1.0         # s on the start before the line starts
const HOLD_TIME := 2.2         # s at the finish
const BACK := 70.0             # m behind the head of the line (along the path)
const HEIGHT := 40.0           # m above the surface
const AHEAD := 60.0            # m ahead of the head: where the camera looks
const FOV := 65.0
const LINE_WIDTH := 0.011      # of the distance to the camera: about the same width on screen
const MARK_SIZE := 0.0016      # Label3D pixel size (fixed on screen)

## The session already shown (instance id of its config): a restart of the same session goes straight to the countdown.
static var last_shown_id := 0

var _scn: ScenarioBase
var _cam: Camera3D
var _line: MeshInstance3D
var _mat: ShaderMaterial
var _head: MeshInstance3D
var _layer: CanvasLayer
var _hint: Label
var _pts := PackedVector3Array()
var _cum := PackedFloat32Array()
var _total := 0.0
var _draw_time := 8.0
var _marks: Array = []          # [Label3D, ratio at which it appears]
var _t := 0.0
var _was_hud_visible := true
var _ground := Callable()
var _look := Vector3.ZERO
var _has_cam := false
var _last_mark := Vector3.INF

const LINE_SHADER := """
shader_type spatial;
render_mode unshaded, depth_test_disabled, cull_disabled, fog_disabled, blend_mix;
uniform float reveal = 0.0;
uniform float width = 0.011;
uniform vec4 col_a : source_color = vec4(0.15, 0.95, 1.0, 1.0);
uniform vec4 col_b : source_color = vec4(1.0, 0.2, 0.72, 1.0);
uniform float head_len = 0.02;
void vertex() {
	// a ribbon that always faces the camera, about the same width on screen (NORMAL holds the direction of the path)
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 tangent = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 to_p = wp - CAMERA_POSITION_WORLD;
	float dist = length(to_p);
	vec3 side = normalize(cross(tangent, to_p / dist));
	wp += side * (UV.y * 2.0 - 1.0) * dist * width * 0.5 + vec3(0.0, 0.25, 0.0);
	VERTEX = (inverse(MODEL_MATRIX) * vec4(wp, 1.0)).xyz;
}
void fragment() {
	float u = UV.x;
	float edge = 1.0 - pow(abs(UV.y * 2.0 - 1.0), 4.0);
	if (u > reveal) {
		// the part to come: a faint trace of the whole line, that gets filled in
		ALBEDO = vec3(1.0);
		ALPHA = edge * 0.28;
	} else {
	float head = smoothstep(head_len, 0.0, reveal - u);
	ALBEDO = mix(col_a.rgb, col_b.rgb, u) + vec3(0.7 * head);
	ALPHA = edge;
	}
}
"""


## True when this session's flight over the course has not been seen yet.
static func wanted(scn: ScenarioBase) -> bool:
	# A movement drill has no course to show: the subject goes straight ahead, or stands still.
	# What the operator needs to see is the drone figure, and the menu already plays that on the
	# setup page - flying over the line would only keep the exercise waiting.
	if scn.matrix != null and scn.matrix.is_drill():
		return false
	var id := scn.matrix.get_instance_id() if scn.matrix != null else 0
	return id == 0 or id != last_shown_id


func setup(scn: ScenarioBase) -> void:
	_scn = scn
	last_shown_id = scn.matrix.get_instance_id() if scn.matrix != null else 0
	_sample_path(scn.subject_pts)
	if _pts.size() < 2 or _total < 10.0:
		# Nothing worth flying over. Stop processing before freeing: the node lives until the end
		# of the frame, and _process would run once more on a line that was never built.
		set_process(false)
		queue_free()
		return
	_draw_time = clampf(_total / 95.0, 6.0, 16.0)
	_ground = scn._clearance_fn()
	scn.intro_active = true
	_build_camera()
	_build_line()
	_build_ui()
	_was_hud_visible = scn.get_node("HUD").visible
	scn.get_node("HUD").visible = false
	_cam.current = true
	scn.flight.rig.set_process(false)   # (the gimbal waits too)
	_place_camera(0.0, 1.0)


func _sample_path(src: PackedVector3Array) -> void:
	var step := maxi(1, src.size() / 1200)
	for i in range(0, src.size(), step):
		_pts.append(src[i])
	if (src.size() - 1) % step != 0:
		_pts.append(src[src.size() - 1])
	_cum = PathUtil.cumulative(_pts)
	_total = _cum[_cum.size() - 1]


func _build_camera() -> void:
	_cam = Camera3D.new()
	_cam.fov = FOV
	_cam.near = 0.5
	_cam.far = 9000.0
	_scn.add_child(_cam)


## The ribbon along the path (its width is set in the shader, facing the camera); the shader shows it up to `reveal`.
func _build_line() -> void:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for i in _pts.size():
		var a := _pts[maxi(i - 1, 0)]
		var b := _pts[mini(i + 1, _pts.size() - 1)]
		var dir := (b - a).normalized()
		for s in 2:
			verts.append(_pts[i])
			normals.append(dir)
			uvs.append(Vector2(_cum[i] / _total, float(s)))
		if i > 0:
			var k := (i - 1) * 2
			idx.append_array([k, k + 1, k + 2, k + 1, k + 3, k + 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.custom_aabb = AABB(Vector3(-20000, -20000, -20000), Vector3(40000, 40000, 40000))
	var sh := Shader.new()
	sh.code = LINE_SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_mat.render_priority = 100
	_mat.set_shader_parameter("width", LINE_WIDTH)
	_line = MeshInstance3D.new()
	_line.mesh = mesh
	_line.material_override = _mat
	_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_scn.add_child(_line)
	# the moving head (resized with its distance to the camera)
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	var hm := StandardMaterial3D.new()
	hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hm.no_depth_test = true
	hm.disable_fog = true
	hm.albedo_color = Color.WHITE
	hm.render_priority = 101
	_head = MeshInstance3D.new()
	_head.mesh = sphere
	_head.material_override = hm
	_head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_scn.add_child(_head)
	# labels: start, finish and the jumps of the line
	_add_mark("DÉPART", _pts[0], 0.0, Neon.CYAN, 44)
	_add_mark("ARRIVÉE", _pts[_pts.size() - 1], 0.995, Neon.PINK, 44)
	var events = _scn.subject.get("jump_events")
	if events != null:
		for ev in events:
			var at: Vector3 = ev.p0
			if _last_mark != Vector3.INF and at.distance_to(_last_mark) < 25.0:
				continue   # (a tight series: one label)
			_last_mark = at
			_add_mark("SAUT", at, float(ev.r0), Neon.SUN, 30)


func _add_mark(text: String, at: Vector3, ratio: float, color: Color, size: int) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = MARK_SIZE
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.fixed_size = true
	l.no_depth_test = true
	l.shaded = false
	l.double_sided = true
	l.modulate = color
	l.outline_size = 10
	l.outline_modulate = Color(0.04, 0.0, 0.1, 0.9)
	l.render_priority = 102
	l.outline_render_priority = 101
	l.position = at + Vector3.UP * 6.0
	l.visible = ratio <= 0.0
	_scn.add_child(l)
	_marks.append([l, ratio])


func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 40
	add_child(_layer)
	var title := Label.new()
	title.text = "VUE D'ENSEMBLE   %s" % _scn.scenario_title.trim_prefix("TRAINING - ")
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Neon.TEXT)
	title.add_theme_color_override("font_shadow_color", Color(0.05, 0, 0.12, 0.9))
	title.add_theme_constant_override("shadow_outline_size", 6)
	title.position = Vector2(24, 18)
	_layer.add_child(title)
	var sub := Label.new()
	sub.text = "La ligne du sujet à filmer"
	sub.add_theme_font_size_override("font_size", 18)
	sub.add_theme_color_override("font_color", Neon.CYAN)
	sub.add_theme_color_override("font_shadow_color", Color(0.05, 0, 0.12, 0.9))
	sub.add_theme_constant_override("shadow_outline_size", 5)
	sub.position = Vector2(26, 54)
	_layer.add_child(sub)
	_hint = Label.new()
	_hint.text = "Entrée : passer l'introduction"
	_hint.add_theme_font_size_override("font_size", 22)
	_hint.add_theme_color_override("font_color", Neon.SUN)
	_hint.add_theme_color_override("font_shadow_color", Color(0.05, 0, 0.12, 0.9))
	_hint.add_theme_constant_override("shadow_outline_size", 6)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.offset_top = -56.0
	_hint.offset_bottom = -16.0
	_layer.add_child(_hint)


## The camera: behind the head of the line along the path, lifted off the surface (never into the ground), looking
## ahead of the head; smoothed so that the flight is fluid.
func _place_camera(s_head: float, k: float) -> void:
	var s_cam := s_head - BACK
	var p := PathUtil.polyline_at(_pts, _cum, s_cam)
	var tan := (PathUtil.polyline_at(_pts, _cum, s_cam + 30.0) - PathUtil.polyline_at(_pts, _cum, s_cam - 30.0)).normalized()
	var away := (Vector3.UP - tan * Vector3.UP.dot(tan)).normalized()   # off the surface, perpendicular to the run
	var pos := p + away * HEIGHT
	if _ground.is_valid():
		pos.y = maxf(pos.y, float(_ground.call(pos.x, pos.z)) + 14.0)
	var target := PathUtil.polyline_at(_pts, _cum, minf(s_head + AHEAD, _total)) + Vector3.UP * 3.0
	if not _has_cam:
		_has_cam = true
		_cam.global_position = pos
		_look = target
	else:
		_cam.global_position = _cam.global_position.lerp(pos, k)
		_look = _look.lerp(target, k)
	var fwd := _look - _cam.global_position
	if fwd.length() > 0.1:
		_cam.look_at(_cam.global_position + fwd, Vector3.UP)


func _process(delta: float) -> void:
	if _mat == null:
		return
	_t += delta
	var r := clampf((_t - LEAD_TIME) / _draw_time, 0.0, 1.0)
	r = r * r * (3.0 - 2.0 * r) * 0.3 + r * 0.7   # slow start and end, a steady pace in between
	_mat.set_shader_parameter("reveal", r)
	var s := r * _total
	_place_camera(s, 1.0 - exp(-delta / 0.45))
	var hp := PathUtil.polyline_at(_pts, _cum, s)
	_head.position = hp + Vector3.UP * 0.4
	var d := _cam.global_position.distance_to(hp)
	_head.scale = Vector3.ONE * d * LINE_WIDTH * 1.5
	_head.visible = r < 1.0 and r > 0.0
	for m in _marks:
		if r >= float(m[1]):
			(m[0] as Label3D).visible = true
	_hint.modulate.a = 0.65 + 0.35 * sin(_t * 4.0)
	if _t >= LEAD_TIME + _draw_time + HOLD_TIME:
		finish()


## Enter skips the flight (before the session sees the key).
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and (event.physical_keycode == KEY_ENTER or event.physical_keycode == KEY_KP_ENTER):
		get_viewport().set_input_as_handled()
		finish()


## Back to the session: the gimbal camera and the HUD, and the countdown starts from its beginning.
func finish() -> void:
	if _scn == null:
		return
	var scn := _scn
	_scn = null
	scn.get_node("HUD").visible = _was_hud_visible
	if scn.flight != null and scn.flight.rig != null:
		scn.flight.rig.camera.current = true
		scn.flight.rig.set_process(true)
	for n in [_cam, _line, _head]:
		if is_instance_valid(n):
			n.queue_free()
	for m in _marks:
		if is_instance_valid(m[0]):
			m[0].queue_free()
	scn.end_intro()
	queue_free()

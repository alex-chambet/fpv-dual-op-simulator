class_name MotionBlur
extends MeshInstance3D
## Camera motion blur (Godot has none built in): a full-screen quad child of a Camera3D whose shader rebuilds the world
## position of every pixel from the depth buffer, projects it with the camera of the previous frame and blurs the image
## along the displacement. The length of the blur is the distance covered during the shutter time (not the frame
## time), so it looks the same at 60 or 144 fps. Only the motion of the camera is blurred (pan, tilt, drone
## movement), which is what a gimbal camera does.

## 0 off, 1 light (shutter 1/120 s), 2 realistic (1/60 s), 3 strong (1/30 s). Chosen in the menu.
static var level := 1
const SHUTTERS := [0.0, 1.0 / 120.0, 1.0 / 60.0, 1.0 / 30.0]
const LABELS := ["Désactivé", "Léger (1/120)", "Réaliste (1/60)", "Fort (1/30)"]

const CODE := """
shader_type spatial;
render_mode unshaded, depth_test_disabled, cull_disabled, fog_disabled, shadows_disabled;

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;
uniform mat4 prev_view;
uniform float blur_scale = 1.0;
uniform float max_blur = 0.07;
uniform int samples = 24;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	float depth = max(texture(depth_tex, SCREEN_UV).x, 0.00001);
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;
	vec4 world = INV_VIEW_MATRIX * vec4(view.xyz, 1.0);
	vec4 prev_clip = PROJECTION_MATRIX * (prev_view * vec4(world.xyz, 1.0));
	vec2 prev_uv = prev_clip.xy / prev_clip.w * 0.5 + 0.5;
	vec2 vel = (SCREEN_UV - prev_uv) * blur_scale;
	float len = length(vel);
	if (len > max_blur) {
		vel *= max_blur / len;
	}
	vec3 col = vec3(0.0);
	for (int i = 0; i < samples; i++) {
		float t = (float(i) + 0.5) / float(samples) - 0.5;
		col += texture(screen_tex, clamp(SCREEN_UV + vel * t, vec2(0.001), vec2(0.999))).rgb;
	}
	ALBEDO = col / float(samples);
}
"""

## Remembers the chosen level in the menu preferences file (the main menu reads it back).
static func save_level() -> void:
	var path := "user://menu_prefs.json"
	var prefs := {}
	if FileAccess.file_exists(path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(parsed) == TYPE_DICTIONARY:
			prefs = parsed
	prefs["blur"] = level
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(prefs, "\t"))


static var _shader: Shader

var _material := ShaderMaterial.new()
var _prev := Transform3D.IDENTITY
var _has_prev := false


func _init() -> void:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = CODE
	_material.shader = _shader
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	mesh = quad
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 16384.0
	ignore_occlusion_culling = true


func _process(delta: float) -> void:
	var cam := get_parent() as Camera3D
	var shutter: float = SHUTTERS[clampi(level, 0, SHUTTERS.size() - 1)]
	visible = shutter > 0.0
	if cam == null or delta <= 0.0:
		return
	var cur := cam.global_transform
	if not visible:
		_has_prev = false
		return
	var scale := shutter / maxf(delta, 1.0 / 240.0)
	# a jump of the camera (start of a run, restart) is not a movement
	if not _has_prev or cur.origin.distance_to(_prev.origin) > 30.0 \
			or (cur.basis.get_rotation_quaternion().angle_to(_prev.basis.get_rotation_quaternion())) > 1.0:
		scale = 0.0
	_material.set_shader_parameter("prev_view", _prev.affine_inverse() if _has_prev else cur.affine_inverse())
	_material.set_shader_parameter("blur_scale", scale)
	_prev = cur
	_has_prev = true

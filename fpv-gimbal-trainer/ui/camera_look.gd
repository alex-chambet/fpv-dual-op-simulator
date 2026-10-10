extends CanvasLayer
## Cheap "real camera" look over the 3D view: lens vignette, chromatic aberration growing towards the edges (the red
## and blue of the image slightly apart, as with a real lens), and film grain. Place it below the HUD in the tree.

@export_range(0.0, 1.0, 0.01) var vignette := 0.4
@export_range(0.0, 0.3, 0.005) var grain := 0.05
## Separation of the red and blue at the corners, in pixels of a 1600 px wide image.
@export_range(0.0, 6.0, 0.1) var aberration := 1.6

const SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float vignette = 0.4;
uniform float grain = 0.05;
uniform float aberration = 1.6;
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 d = uv - 0.5;
	float r2 = dot(d, d);
	vec2 off = d * (4.0 * r2) * aberration / 1600.0;
	vec3 col = vec3(texture(screen_tex, uv + off).r, texture(screen_tex, uv).g, texture(screen_tex, uv - off).b);
	vec2 c = UV * 2.0 - 1.0;
	col *= 1.0 - smoothstep(0.5, 1.6, length(c * vec2(1.0, 0.85))) * vignette;
	float g = hash(UV * vec2(1920.0, 1080.0) + fract(TIME) * 97.0) - 0.5;
	col += g * grain * 0.6;
	COLOR = vec4(col, 1.0);
}
"""

var _mat := ShaderMaterial.new()


func _ready() -> void:
	layer = 0
	var shader := Shader.new()
	shader.code = SHADER
	_mat.shader = shader
	var rect := ColorRect.new()
	rect.material = _mat
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(rect)


func _process(_delta: float) -> void:
	_mat.set_shader_parameter("vignette", vignette)
	_mat.set_shader_parameter("grain", grain)
	_mat.set_shader_parameter("aberration", aberration)

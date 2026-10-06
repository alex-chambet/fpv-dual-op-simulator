extends CanvasLayer
## Cheap "real camera" overlay: vignette + film grain. Place it below the HUD in the tree.

@export_range(0.0, 1.0, 0.01) var vignette := 0.4
@export_range(0.0, 0.3, 0.005) var grain := 0.05

const SHADER := """
shader_type canvas_item;
uniform float vignette = 0.4;
uniform float grain = 0.05;
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float a_v = smoothstep(0.5, 1.6, length(uv * vec2(1.0, 0.85))) * vignette;
	float g = hash(UV * vec2(1920.0, 1080.0) + fract(TIME) * 97.0) - 0.5;
	float a_g = abs(g) * 2.0 * grain;
	float c_g = g > 0.0 ? 1.0 : 0.0;
	float a = a_g + a_v * (1.0 - a_g);
	COLOR = vec4(vec3(c_g * a_g / max(a, 0.0001)), a);
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

class_name GrassField
extends MultiMeshInstance3D
## 3D grass around the camera: a grid of clumps of blades that moves with the camera (always in front of it).
## Each clump is placed by the GPU from its world cell (so it never swims): jittered, rotated, standing on the
## terrain (height texture of TerrainBuilder), with the colours of the terrain shader under it. No grass on the
## roads / trails (GroundMask), on rock slopes or on ploughed fields; ripe wheat, rapeseed, young crops and stubble
## grow on the farmland parcels. The node itself never moves (the motion vectors stay those of a still ground).
##
## params: the terrain shader parameters (grass_a, grass_b, dry, dry_amount, fields, field_size, field_angle) plus
## height (m), density (0..1, fraction of the clumps of the quality level), flowers (0..1), max_slope (1 - normal.y),
## crops (bool), wind.

const SHADER := """
shader_type spatial;
render_mode cull_disabled, world_vertex_coords;
#COMMON
uniform sampler2D height_tex : filter_linear, repeat_disable;
uniform vec4 height_frame = vec4(0.0, 0.0, 1.0, 0.0);
uniform vec2 center = vec2(0.0);
uniform float cell = 0.5;
uniform float fade_start = 30.0;
uniform float fade_end = 48.0;
uniform vec3 grass_a : source_color = vec3(0.16, 0.28, 0.07);
uniform vec3 grass_b : source_color = vec3(0.3, 0.4, 0.12);
uniform vec3 dry : source_color = vec3(0.5, 0.46, 0.26);
uniform float dry_amount = 0.4;
uniform float blade_height = 0.35;
uniform float density = 1.0;
uniform float flowers = 0.0;
uniform float max_slope = 0.3;
uniform float crops = 0.0;
uniform float wind = 1.0;

varying vec3 v_base;
varying vec3 v_tip;
varying float v_h;
varying vec3 v_flower;

float ground_at(vec2 xz) {
	vec2 size = vec2(textureSize(height_tex, 0));
	vec2 uv = ((xz - height_frame.xy) / height_frame.z + 0.5) / size;
	return textureLod(height_tex, uv, 0.0).r;
}

void vertex() {
	vec3 inst = MODEL_MATRIX[3].xyz;
	vec3 local = VERTEX - inst;
	vec2 id = floor((center + inst.xz) / cell + 0.5);
	vec2 xz = (id + hash22(id) - 0.5) * cell;
	float r1 = hash12(id + 7.7);
	float r2 = hash12(id + 3.1);
	float r3 = hash12(id + 11.3);

	// colour of the ground here (same formulas as the terrain shader)
	float m_big = texture(macro_tex, xz * 0.0021).r;
	float m_mid = texture(macro_tex, xz * 0.0117 + 0.31).r;
	float d1 = texture(detail_tex, xz * 0.083).r;
	vec3 g = mix(grass_a, grass_b, smoothstep(0.25, 0.75, m_mid * 0.65 + d1 * 0.35));
	g = mix(g, dry, smoothstep(0.5, 0.85, m_big * 0.75 + d1 * 0.25) * dry_amount);
	vec3 base = g * (0.92 + 0.16 * r2);
	vec3 tip = mix(base * 1.18, dry * 1.05, 0.3 * r1);
	float hgt = blade_height * (0.55 + 0.9 * r2);
	float dens = density * smoothstep(0.2, 0.55, texture(macro_tex, xz * 0.031 + 0.7).r + 0.2);
	float width = 1.0;

	vec4 mk = mask_at(xz);
	hgt *= 1.0 + 0.35 * mk.g * (1.0 - mk.b);
	dens *= 1.0 - mk.b * 0.65;
	if (mk.r > 0.35) {
		dens = 0.0;
	}
	if (fields > 0.5 && crops > 0.5 && mk.g < 0.5) {
		vec4 pc = parcel(xz);
		if (pc.y > 2.0 && pc.x >= 0.32) {
			float row = fract(dot(xz, pc.zw) / 0.75);
			if (pc.x < 0.5) {            // ripe wheat
				hgt = 0.8 * (0.85 + 0.3 * r2); dens = 1.0; width = 0.7;
				base = vec3(0.42, 0.34, 0.13); tip = vec3(0.78, 0.64, 0.3) * (0.9 + 0.2 * r1);
			} else if (pc.x < 0.64) {    // young crop in rows
				hgt = 0.28 * (0.8 + 0.4 * r2); dens = row < 0.4 ? 1.0 : 0.0;
				base = vec3(0.12, 0.26, 0.05); tip = vec3(0.3, 0.5, 0.12);
			} else if (pc.x < 0.8) {     // ploughed: bare soil
				dens = 0.0;
			} else if (pc.x < 0.9) {     // rapeseed in flower
				hgt = 1.0 * (0.85 + 0.3 * r2); dens = 1.0; width = 1.3;
				base = vec3(0.16, 0.3, 0.06); tip = vec3(0.95, 0.82, 0.08);
			} else {                     // stubble
				hgt = 0.14; dens = 0.85; width = 0.8;
				base = vec3(0.4, 0.35, 0.2); tip = vec3(0.7, 0.63, 0.42);
			}
		}
	}
	// wild flowers: a small coloured head at the top of some blades
	v_flower = vec3(-1.0);
	if (flowers > 0.0 && r1 < flowers && (fields < 0.5 || crops < 0.5 || mk.g > 0.5)) {
		v_flower = r3 < 0.5 ? vec3(0.95, 0.93, 0.85) : (r3 < 0.8 ? vec3(0.95, 0.8, 0.15) : vec3(0.6, 0.45, 0.85));
	}

	// steepness from the height texture
	float hc = ground_at(xz);
	float dx = ground_at(xz + vec2(1.0, 0.0)) - ground_at(xz - vec2(1.0, 0.0));
	float dz = ground_at(xz + vec2(0.0, 1.0)) - ground_at(xz - vec2(0.0, 1.0));
	float slope = 1.0 - 1.0 / sqrt(1.0 + 0.25 * (dx * dx + dz * dz));
	if (slope > max_slope) {
		dens = 0.0;
	}

	// distance to the camera, stretched in the direction of view (the grass reaches further ahead)
	vec2 rel = xz - CAMERA_POSITION_WORLD.xz;
	vec2 fwd = normalize(CAMERA_DIRECTION_WORLD.xz + vec2(0.0001));
	float along = dot(rel, fwd);
	float across = dot(rel, vec2(-fwd.y, fwd.x));
	float dist = length(vec2(along * (along > 0.0 ? 0.6 : 1.0), across));
	float fade = 1.0 - smoothstep(fade_start, fade_end, dist);
	float keep = step(r3, dens) * fade;
	// a camera standing in the grass (drone on its take-off spot) is not blinded by blades touching the lens
	keep *= smoothstep(0.8, 1.6, length(vec2(dist, (hc - CAMERA_POSITION_WORLD.y) * 2.0)));

	float ang = r1 * 6.2832;
	vec2 lxz = mat2(vec2(cos(ang), sin(ang)), vec2(-sin(ang), cos(ang))) * local.xz;
	float h = local.y;
	vec3 p = vec3(xz.x + lxz.x * width, hc - 0.04 + h * hgt * keep, xz.y + lxz.y * width);
	float w = sin(TIME * 1.6 + xz.x * 0.31 + xz.y * 0.23) * 0.6 + sin(TIME * 3.3 + xz.x * 0.9 - xz.y * 0.4) * 0.25;
	p.xz += vec2(0.8, 0.45) * w * wind * h * h * hgt * 0.22 * keep;
	if (keep <= 0.0) {
		p = vec3(xz.x, hc - 0.2, xz.y);
	}
	VERTEX = p;
	NORMAL = normalize(vec3(lxz.x, 0.0, lxz.y) * 0.35 + vec3(0.0, 1.0, 0.0));
	v_base = base;
	v_tip = tip;
	v_h = h;
}

void fragment() {
	// a blade is lit the same on both faces (the renderer flips the normal of back faces)
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	vec3 col = mix(v_base * 0.62, v_tip, smoothstep(0.0, 0.9, v_h));
	if (v_flower.r >= 0.0) {
		col = mix(col, v_flower, smoothstep(0.86, 0.93, v_h));
	}
	ALBEDO = col;
	ROUGHNESS = 0.85;
	SPECULAR = 0.25;
	BACKLIGHT = col * 0.5 * v_h;
	AO = mix(0.55, 1.0, v_h);
	AO_LIGHT_AFFECT = 0.3;
}
"""

static var _shader: Shader
static var _clump: ArrayMesh

var camera: Camera3D
var params := {}
var _mat: ShaderMaterial
var _cell := 0.5
var _extent := 100.0


func setup(p: Dictionary, hinfo: Dictionary, mask: GroundMask, cam: Camera3D) -> void:
	params = p
	camera = cam
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER.replace("#COMMON", GroundMaterials.COMMON)
	_mat = ShaderMaterial.new()
	_mat.shader = _shader
	for t in ["macro", "detail", "cell", "normal"]:
		_mat.set_shader_parameter(t + "_tex", GroundMaterials.noise(t))
	for k in ["grass_a", "grass_b", "dry", "dry_amount", "fields", "field_size", "field_angle"]:
		if p.has(k):
			_mat.set_shader_parameter(k, p[k])
	_mat.set_shader_parameter("blade_height", float(p.get("height", 0.35)))
	_mat.set_shader_parameter("flowers", float(p.get("flowers", 0.0)))
	_mat.set_shader_parameter("max_slope", float(p.get("max_slope", 0.3)))
	_mat.set_shader_parameter("crops", 1.0 if p.get("crops", false) else 0.0)
	_mat.set_shader_parameter("wind", float(p.get("wind", 1.0)))
	_mat.set_shader_parameter("height_tex", TerrainBuilder.height_texture(hinfo))
	_mat.set_shader_parameter("height_frame", Vector4(hinfo.x0, hinfo.z0, hinfo.cell, 0.0))
	if mask != null:
		mask.bind(_mat)
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	custom_aabb = AABB(Vector3(-50000, -5000, -50000), Vector3(100000, 10000, 100000))
	apply_quality()


## (Re)builds the grid for the current graphics quality.
func apply_quality() -> void:
	var d := GraphicsSettings.grass_density()
	if d <= 0.0 or params.is_empty():
		visible = false
		return
	visible = true
	# a sparse grass is a coarser grid, not a dense grid with most clumps hidden
	_cell = 1.0 / sqrt(d * clampf(float(params.get("density", 1.0)), 0.05, 1.0))
	_extent = GraphicsSettings.grass_extent()
	var n := ceili(_extent / _cell)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _clump_mesh()
	mm.instance_count = n * n
	var buf := PackedFloat32Array()
	buf.resize(n * n * 12)
	var half := (n - 1) * 0.5
	var k := 0
	for iz in n:
		for ix in n:
			# basis = identity, origin = offset of the cell from the centre of the grid
			buf[k] = 1.0
			buf[k + 3] = (ix - half) * _cell
			buf[k + 5] = 1.0
			buf[k + 10] = 1.0
			buf[k + 11] = (iz - half) * _cell
			k += 12
	mm.buffer = buf
	multimesh = mm
	_mat.set_shader_parameter("cell", _cell)
	_mat.set_shader_parameter("fade_start", _extent * 0.22)
	_mat.set_shader_parameter("fade_end", _extent * 0.48)


func _process(_delta: float) -> void:
	if camera == null or not visible:
		return
	var fwd := -camera.global_basis.z
	fwd.y = 0.0
	var c := camera.global_position + (fwd.normalized() if fwd.length() > 0.01 else Vector3.ZERO) * _extent * 0.3
	_mat.set_shader_parameter("center", Vector2(snappedf(c.x, _cell), snappedf(c.z, _cell)))


## A clump of 9 blades, 1 m high (scaled by the shader), each 3 triangles; VERTEX.y = height along the blade.
static func _clump_mesh() -> ArrayMesh:
	if _clump != null:
		return _clump
	var rng := RandomNumberGenerator.new()
	rng.seed = 12
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b in 9:
		var a := TAU * b / 9.0 + rng.randf_range(-0.4, 0.4)
		var r := rng.randf_range(0.02, 0.13)
		var root := Vector3(cos(a) * r, 0.0, sin(a) * r)
		var lean := Vector3(cos(a + rng.randf_range(-0.6, 0.6)), 0.0, sin(a + rng.randf_range(-0.6, 0.6))) \
				* rng.randf_range(0.08, 0.3)
		var face := rng.randf() * TAU
		var side := Vector3(cos(face), 0.0, sin(face)) * rng.randf_range(0.011, 0.017)
		var hb := rng.randf_range(0.7, 1.0)
		var m := root + lean * 0.3 + Vector3(0, 0.55 * hb, 0)
		var t := root + lean + Vector3(0, hb, 0)
		var pts := [root - side, root + side, m - side * 0.6, m + side * 0.6, t]
		for tri in [[0, 1, 2], [2, 1, 3], [2, 3, 4]]:
			for i in tri:
				var p: Vector3 = pts[i]
				st.set_normal(Vector3.UP)
				st.add_vertex(Vector3(p.x, p.y, p.z))
	_clump = st.commit()
	return _clump

class_name Rocks
extends RefCounted
## Procedural rocks: irregular boulders (a sphere displaced by 3D noise, flat underneath) with a rock shader
## (strata and cracks seen from every side, moss or lichen on the top, snow in snowy places). A rock of size
## (1, 1, 1) fits in a sphere of radius 1, like the SphereMesh it replaces.

const VARIANTS := 5

const SHADER := """
shader_type spatial;

uniform sampler2D detail_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D cell_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 rock_a : source_color = vec3(0.5, 0.49, 0.47);
uniform vec3 rock_b : source_color = vec3(0.27, 0.26, 0.25);
uniform vec3 moss : source_color = vec3(0.22, 0.3, 0.1);
uniform float moss_amount = 0.0;
uniform float snow = 0.0;
varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 bw = pow(abs(wnrm), vec3(4.0));
	bw /= bw.x + bw.y + bw.z;
	vec3 p = wpos * 0.55;
	float n = texture(detail_tex, p.zy * vec2(1.0, 2.2)).r * bw.x + texture(detail_tex, p.xz).r * bw.y
			+ texture(detail_tex, p.xy * vec2(1.0, 2.2)).r * bw.z;
	float c = texture(cell_tex, p.zy * 1.7).r * bw.x + texture(cell_tex, p.xz * 1.7).r * bw.y
			+ texture(cell_tex, p.xy * 1.7).r * bw.z;
	vec3 col = mix(rock_b, rock_a, smoothstep(0.2, 0.8, n)) * (0.7 + 0.4 * smoothstep(0.05, 0.45, c));
	float top = smoothstep(0.35, 0.85, wnrm.y + (n - 0.5) * 0.5);
	col = mix(col, moss * (0.75 + 0.5 * n), top * moss_amount);
	float sn = smoothstep(0.3, 0.6, wnrm.y + (n - 0.5) * 0.4) * snow;
	col = mix(col, vec3(0.9, 0.93, 0.98), sn);
	vec2 a = texture(normal_tex, p.zy * 2.0).rg * 2.0 - 1.0;
	vec2 b = texture(normal_tex, p.xz * 2.0).rg * 2.0 - 1.0;
	vec2 d = texture(normal_tex, p.xy * 2.0).rg * 2.0 - 1.0;
	vec3 off = vec3(0.0, a.x, a.y) * bw.x + vec3(b.x, 0.0, b.y) * bw.y + vec3(d.x, d.y, 0.0) * bw.z;
	vec3 nw = normalize(wnrm + off * 0.45 * (1.0 - sn * 0.7));
	ALBEDO = col;
	ROUGHNESS = mix(0.88, 0.7, sn);
	SPECULAR = 0.3;
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
}
"""

static var _meshes := []
static var _mat: ShaderMaterial
## Moss on the rocks of the current scene (0 = none), set by the environment.
static var moss_amount := 0.0


static func material() -> ShaderMaterial:
	if _mat == null:
		var sh := Shader.new()
		sh.code = SHADER
		_mat = ShaderMaterial.new()
		_mat.shader = sh
		for t in ["detail", "cell", "normal"]:
			_mat.set_shader_parameter(t + "_tex", GroundMaterials.noise(t))
	_mat.set_shader_parameter("moss_amount", moss_amount)
	_mat.set_shader_parameter("snow", Vegetation.snow_cover)
	return _mat


static func mesh(variant: int) -> ArrayMesh:
	if _meshes.is_empty():
		for v in VARIANTS:
			_meshes.append(_build(v))
	return _meshes[posmod(variant, VARIANTS)]


## A boulder: an icosphere (subdivided twice) displaced by noise and flattened underneath.
static func _build(variant: int) -> ArrayMesh:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = 71 + variant * 13
	noise.frequency = 0.9
	noise.fractal_octaves = 3
	var t := (1.0 + sqrt(5.0)) / 2.0
	var verts: Array[Vector3] = []
	for v in [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0), Vector3(0, -1, t),
			Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t), Vector3(t, 0, -1), Vector3(t, 0, 1),
			Vector3(-t, 0, -1), Vector3(-t, 0, 1)]:
		verts.append(v.normalized())
	var faces := [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2],
			[10, 7, 6], [7, 1, 8], [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11],
			[6, 2, 10], [8, 6, 7], [9, 8, 1]]
	for _level in 2:
		var mid := {}
		var next := []
		for f in faces:
			var m := []
			for e in 3:
				var a: int = f[e]
				var b: int = f[(e + 1) % 3]
				var key := Vector2i(mini(a, b), maxi(a, b))
				if not mid.has(key):
					verts.append(((verts[a] + verts[b]) * 0.5).normalized())
					mid[key] = verts.size() - 1
				m.append(mid[key])
			next.append([f[0], m[0], m[2]])
			next.append([f[1], m[1], m[0]])
			next.append([f[2], m[2], m[1]])
			next.append([m[0], m[1], m[2]])
		faces = next
	var squash := Vector3(1.0, 0.75 + 0.2 * (variant % 3) / 2.0, 0.85 + 0.15 * float(variant % 2))
	var shaped := PackedVector3Array()
	for v in verts:
		var r := 1.0 + 0.22 * noise.get_noise_3dv(v * 1.3) + 0.07 * noise.get_noise_3dv(v * 4.1 + Vector3(5, 1, 3))
		var p := v * r * 0.9 * squash
		if p.y < -0.35:
			p.y = -0.35 + (p.y + 0.35) * 0.25
		shaped.append(p)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for v in shaped:
		st.add_vertex(v)
	for f in faces:
		st.add_index(f[0])
		st.add_index(f[2])
		st.add_index(f[1])
	st.generate_normals()
	var mesh := st.commit()
	mesh.surface_set_material(0, material())
	return mesh


## One rock as a MeshInstance3D: ground point, size (scale of the unit rock), seed for the shape and yaw.
static func add(parent: Node3D, ground: Vector3, size: Vector3, seed_value: int) -> MeshInstance3D:
	material()  # moss / snow of the current scene
	var mi := MeshInstance3D.new()
	mi.mesh = mesh(seed_value)
	mi.position = ground + Vector3(0, size.y * 0.4, 0)
	mi.scale = size
	mi.rotation.y = float(seed_value % 360) * 0.0175
	parent.add_child(mi)
	return mi


## Many small rocks (MultiMesh per variant): ground points and sizes (uniform), half buried.
static func scatter(parent: Node3D, grounds: PackedVector3Array, sizes: PackedFloat32Array, seed_value: int) -> void:
	material()
	if grounds.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var buckets := []
	for v in VARIANTS:
		buckets.append([])
	for i in grounds.size():
		var s := sizes[i]
		var basis := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.2, 0.2))
		basis = basis.scaled(Vector3(s * rng.randf_range(0.8, 1.3), s * rng.randf_range(0.6, 1.0), s))
		buckets[rng.randi() % VARIANTS].append(Transform3D(basis, grounds[i] + Vector3(0, s * 0.05, 0)))
	for v in VARIANTS:
		var items: Array = buckets[v]
		if items.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh(v)
		mm.instance_count = items.size()
		for j in items.size():
			mm.set_instance_transform(j, items[j])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.visibility_range_end = 160.0
		parent.add_child(mmi)

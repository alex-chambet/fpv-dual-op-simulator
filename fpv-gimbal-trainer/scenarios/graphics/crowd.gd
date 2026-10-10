class_name Crowd
extends Node3D
## Spectators of a race: low-poly people (boots, trousers, ski jacket, beanie with a pompom), some of them waving a
## national flag, and advertising banners in front of them. One Crowd node per group (its own MultiMeshes, so a far
## group is culled). The people idle, and jump with their arms up when the racer comes close (`host.subject`).

const FLAG_RATE := 0.08

const PEOPLE_SHADER := """
shader_type spatial;
// part of the person in the vertex alpha: 0 fixed colour (skin, boots), 0.25 jacket, 0.5 arm (jacket colour,
// raised when cheering), 0.75 beanie, 1 trousers; INSTANCE_CUSTOM = jacket colour (linear) + a random number
uniform vec3 focus = vec3(0.0, -10000.0, 0.0);
varying vec3 tint;

void vertex() {
	float part = COLOR.a;
	float rnd = INSTANCE_CUSTOM.a;
	float phase = rnd * 6.2832;
	vec3 base = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float excite = 1.0 - smoothstep(25.0, 80.0, distance(base, focus));
	if (part > 0.4 && part < 0.6) {
		float side = sign(VERTEX.x);
		vec3 sh = vec3(0.21 * side, 1.4, 0.0);
		float a = side * excite * (2.65 + 0.3 * sin(TIME * 9.0 + phase));
		vec3 p = VERTEX - sh;
		p.xy = vec2(p.x * cos(a) - p.y * sin(a), p.x * sin(a) + p.y * cos(a));
		VERTEX = sh + p;
	}
	VERTEX.y += excite * max(0.0, sin(TIME * 7.5 + phase)) * 0.12;
	VERTEX.x += sin(TIME * 0.8 + phase) * 0.025 * VERTEX.y;
	vec3 beanie = 0.5 + 0.5 * cos(6.2832 * (rnd * 5.0 + vec3(0.0, 0.33, 0.67)));
	vec3 trousers = mix(vec3(0.012, 0.014, 0.02), vec3(0.03, 0.04, 0.09), fract(rnd * 13.0));
	if (part < 0.1) {
		tint = pow(COLOR.rgb, vec3(2.2));
	} else if (part < 0.6) {
		tint = INSTANCE_CUSTOM.rgb;
	} else if (part < 0.9) {
		tint = beanie * beanie;
	} else {
		tint = trousers;
	}
}

void fragment() {
	ALBEDO = tint;
	ROUGHNESS = 0.75;
}
"""

const FLAG_SHADER := """
shader_type spatial;
render_mode cull_disabled;
// INSTANCE_CUSTOM.x = flag (0 Austria, 1 France, 2 Italy, 3 Switzerland, 4 Germany, 5 Norway), .a = random
uniform vec3 focus = vec3(0.0, -10000.0, 0.0);
varying float pole;
varying float kindf;

void vertex() {
	pole = 1.0 - COLOR.a;
	kindf = INSTANCE_CUSTOM.x;
	float phase = INSTANCE_CUSTOM.a * 6.2832;
	vec3 base = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float excite = 1.0 - smoothstep(25.0, 80.0, distance(base, focus));
	if (pole < 0.5) {
		float u = UV.x;
		VERTEX.z += sin(u * 6.5 - TIME * (5.0 + 5.0 * excite) + phase) * 0.13 * u;
		VERTEX.y -= (1.0 - excite) * 0.12 * u * u;
	}
	// raised and swung when the racer comes
	VERTEX.y += excite * 0.45;
	VERTEX.x += excite * sin(TIME * 4.0 + phase) * 0.25 * max(VERTEX.y - 1.2, 0.0);
}

vec3 lin(vec3 c) { return pow(c, vec3(2.2)); }

void fragment() {
	vec2 uv = UV;
	int kind = int(kindf + 0.5);
	vec3 red = lin(vec3(0.82, 0.08, 0.12));
	vec3 white = vec3(0.92);
	vec3 c = white;
	if (kind == 0) {
		c = abs(uv.y - 0.5) < 0.1667 ? white : red;
	} else if (kind == 1) {
		c = uv.x < 0.333 ? lin(vec3(0.0, 0.14, 0.58)) : (uv.x < 0.667 ? white : red);
	} else if (kind == 2) {
		c = uv.x < 0.333 ? lin(vec3(0.0, 0.55, 0.27)) : (uv.x < 0.667 ? white : red);
	} else if (kind == 3) {
		vec2 q = abs(uv - 0.5) * vec2(1.6, 1.0);
		c = (q.x < 0.1 && q.y < 0.32) || (q.y < 0.1 && q.x < 0.32) ? white : red;
	} else if (kind == 4) {
		c = uv.y < 0.333 ? lin(vec3(1.0, 0.8, 0.0)) : (uv.y < 0.667 ? red : vec3(0.01));
	} else {
		float d = min(abs(uv.x - 0.36), abs(uv.y - 0.5) * 1.2);
		c = d < 0.06 ? lin(vec3(0.0, 0.13, 0.4)) : (d < 0.1 ? white : red);
	}
	ALBEDO = pole > 0.5 ? vec3(0.3) : c;
	ROUGHNESS = 0.8;
}
"""

const BANNER_SHADER := """
shader_type spatial;
render_mode cull_disabled;
// made-up advertising: a coloured field with a block logo and a row of pseudo-letters
// INSTANCE_CUSTOM.rgb = field colour (linear), .a = random (logo and letters)
varying flat vec4 custom;

float hash(float n) { return fract(sin(n * 91.345) * 47453.11); }

void vertex() {
	custom = INSTANCE_CUSTOM;
}

void fragment() {
	vec2 uv = UV;
	float rnd = custom.a * 97.0;
	vec3 field = custom.rgb;
	float lum = dot(field, vec3(0.3, 0.6, 0.1));
	vec3 ink = lum > 0.35 ? vec3(0.02) : vec3(0.9);
	vec3 accent = 0.5 + 0.5 * cos(6.2832 * (hash(rnd) + vec3(0.0, 0.33, 0.67)));
	accent *= accent;
	vec3 c = field;
	// logo: a disc or a square on the left
	vec2 lp = (uv - vec2(0.12, 0.5)) * vec2(3.1, 1.0);
	float logo = hash(rnd + 1.0) < 0.5 ? step(length(lp), 0.3) : step(max(abs(lp.x), abs(lp.y)), 0.26);
	c = mix(c, accent, logo);
	// letters: columns of bars with random heights
	if (uv.x > 0.25 && uv.x < 0.92 && abs(uv.y - 0.5) < 0.22) {
		float col = floor(uv.x * 46.0);
		float on = step(0.3, hash(col + rnd)) * step(fract(uv.x * 46.0), 0.72);
		float h = 0.12 + 0.1 * hash(col * 1.7 + rnd);
		on *= step(abs(uv.y - 0.5), h);
		c = mix(c, ink, on);
	}
	// thin border
	float b = min(min(uv.x, 1.0 - uv.x) * 3.1, min(uv.y, 1.0 - uv.y));
	c = mix(ink * 0.5 + field * 0.5, c, step(0.04, b));
	ALBEDO = c;
	ROUGHNESS = 0.6;
}
"""

static var _people_mat: ShaderMaterial
static var _flag_mat: ShaderMaterial
static var _banner_mat: ShaderMaterial
static var _person: ArrayMesh
static var _flag: ArrayMesh
static var _banner: ArrayMesh

var host: ScenarioBase
var _people: Array[Transform3D] = []
var _people_data := PackedColorArray()
var _flags: Array[Transform3D] = []
var _flag_data := PackedColorArray()
var _banners: Array[Transform3D] = []
var _banner_data := PackedColorArray()


## Fraction of the places of a crowd that get someone, by graphics quality.
static func density() -> float:
	return [0.4, 0.6, 0.8, 0.92][clampi(GraphicsSettings.quality, 0, 3)]


## A person standing at `pos` (ground), facing the direction `face` (horizontal).
func add_person(pos: Vector3, face: Vector3, rng: RandomNumberGenerator, flags := true) -> void:
	var yaw := atan2(face.x, face.z) + rng.randf_range(-0.45, 0.45)
	var b := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * rng.randf_range(0.9, 1.08))
	_people.append(Transform3D(b, pos))
	var jacket: Color
	if rng.randf() < 0.3:
		jacket = Color.from_hsv(rng.randf_range(0.55, 0.7), 0.5, rng.randf_range(0.08, 0.25))
	else:
		jacket = Color.from_hsv(rng.randf(), rng.randf_range(0.55, 0.95), rng.randf_range(0.45, 0.95))
	jacket = jacket.srgb_to_linear()
	_people_data.append(Color(jacket.r, jacket.g, jacket.b, rng.randf()))
	if flags and rng.randf() < FLAG_RATE:
		_flags.append(Transform3D(b, pos + b * Vector3(0.3, 0.0, 0.12)))
		_flag_data.append(Color(rng.randi() % 6, 0.0, 0.0, rng.randf()))


## A banner (2.8 x 0.9 m) on the ground from `a` to `b` (ground points 2.8 m apart, it follows the slope), its face
## towards `face`.
func add_banner(a: Vector3, b: Vector3, face: Vector3, rng: RandomNumberGenerator) -> void:
	_banners.append(Transform3D(Basis((b - a) / 2.8, Vector3.UP, face.normalized()), (a + b) * 0.5))
	var fields := [Color(0.95, 0.95, 0.95), Color(0.8, 0.06, 0.06), Color(0.05, 0.2, 0.6), Color(0.98, 0.78, 0.05),
			Color(0.02, 0.02, 0.03), Color(0.0, 0.5, 0.3)]
	var f: Color = (fields[rng.randi() % fields.size()] as Color).srgb_to_linear()
	_banner_data.append(Color(f.r, f.g, f.b, rng.randf()))


func is_empty() -> bool:
	return _people.is_empty() and _banners.is_empty()


## Makes the MultiMeshes (call once, after the adds). Far groups fade out beyond `range_end` metres.
func build(range_end := 900.0) -> void:
	var shadows := GraphicsSettings.quality >= 2
	_make(_person_mesh(), _people_mat_get(), _people, _people_data, shadows, range_end)
	_make(_flag_mesh(), _flag_mat_get(), _flags, _flag_data, false, range_end * 0.7)
	_make(_banner_mesh(), _banner_mat_get(), _banners, _banner_data, shadows, range_end)


func _make(mesh: Mesh, mat: Material, xforms: Array[Transform3D], data: PackedColorArray, shadows: bool,
		range_end: float) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_custom_data(i, data[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = range_end
	mmi.visibility_range_end_margin = 60.0
	mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(mmi)


func _process(_delta: float) -> void:
	if host == null or host.subject == null:
		return
	var p := host.subject.global_position
	_people_mat_get().set_shader_parameter("focus", p)
	_flag_mat_get().set_shader_parameter("focus", p)


# --- Shared meshes and materials ----------------------------------------------------------------

static func _people_mat_get() -> ShaderMaterial:
	if _people_mat == null:
		_people_mat = _shader(PEOPLE_SHADER)
	return _people_mat


static func _flag_mat_get() -> ShaderMaterial:
	if _flag_mat == null:
		_flag_mat = _shader(FLAG_SHADER)
	return _flag_mat


static func _banner_mat_get() -> ShaderMaterial:
	if _banner_mat == null:
		_banner_mat = _shader(BANNER_SHADER)
	return _banner_mat


static func _shader(code: String) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = code
	var m := ShaderMaterial.new()
	m.shader = sh
	return m


## Appends a primitive mesh, transformed, with one vertex colour (alpha = part), to a SurfaceTool.
static func _part(st: SurfaceTool, mesh: PrimitiveMesh, xf: Transform3D, col: Color) -> void:
	var arrays := mesh.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for i in idx:
		st.set_color(col)
		st.set_normal((xf.basis * norms[i]).normalized())
		if not uvs.is_empty():
			st.set_uv(uvs[i])
		st.add_vertex(xf * verts[i])


static func _capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	c.radial_segments = 7
	c.rings = 2
	return c


static func _sphere(r: float, hemi := false) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * (1.0 if hemi else 2.0)
	s.is_hemisphere = hemi
	s.radial_segments = 8
	s.rings = 3 if hemi else 5
	return s


## About 1.75 m tall, feet at the origin, facing +z.
static func _person_mesh() -> ArrayMesh:
	if _person != null:
		return _person
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var boots := Color(0.12, 0.12, 0.13, 0.0)
	var skin := Color(0.86, 0.68, 0.56, 0.0)
	var jacket := Color(1, 1, 1, 0.25)
	var arm := Color(1, 1, 1, 0.5)
	var beanie := Color(1, 1, 1, 0.75)
	var trousers := Color(1, 1, 1, 1.0)
	for sx in [-1.0, 1.0]:
		var bx := BoxMesh.new()
		bx.size = Vector3(0.13, 0.13, 0.28)
		_part(st, bx, Transform3D(Basis(), Vector3(sx * 0.1, 0.065, 0.03)), boots)
		_part(st, _capsule(0.08, 0.86), Transform3D(Basis(), Vector3(sx * 0.1, 0.52, 0.0)), trousers)
		_part(st, _capsule(0.05, 0.6), Transform3D(Basis(Vector3.BACK, sx * 0.08), Vector3(sx * 0.245, 1.12, 0.0)), arm)
		_part(st, _sphere(0.05), Transform3D(Basis(), Vector3(sx * 0.27, 0.83, 0.0)), arm)
	_part(st, _capsule(0.2, 0.72), Transform3D(Basis().scaled(Vector3(1.0, 1.0, 0.78)), Vector3(0, 1.17, 0)), jacket)
	_part(st, _sphere(0.11), Transform3D(Basis(), Vector3(0, 1.6, 0.0)), skin)
	_part(st, _sphere(0.118, true), Transform3D(Basis(), Vector3(0, 1.63, 0.0)), beanie)
	_part(st, _sphere(0.045), Transform3D(Basis(), Vector3(0, 1.77, 0.0)), beanie)
	_person = st.commit()
	return _person


## A pole held at hand height (1.0 to 2.9 m) with a 1.1 x 0.7 m flag at its top (UV.x 0 at the pole).
static func _flag_mesh() -> ArrayMesh:
	if _flag != null:
		return _flag
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.018
	cyl.bottom_radius = 0.018
	cyl.height = 1.9
	cyl.radial_segments = 5
	cyl.rings = 1
	_part(st, cyl, Transform3D(Basis(), Vector3(0, 1.95, 0)), Color(0.3, 0.3, 0.3, 0.0))
	var cols := 8
	for i in cols:
		var u0 := float(i) / cols
		var u1 := float(i + 1) / cols
		var quad := [[u0, 0.0], [u0, 1.0], [u1, 1.0], [u0, 0.0], [u1, 1.0], [u1, 0.0]]
		for q in quad:
			st.set_color(Color(1, 1, 1, 1))
			st.set_normal(Vector3.BACK)
			st.set_uv(Vector2(q[0], 1.0 - q[1]))
			st.add_vertex(Vector3(q[0] * 1.1, 2.18 + q[1] * 0.7, 0.0))
	_flag = st.commit()
	return _flag


## A banner on two short posts: 2.8 x 0.9 m, its bottom 0.15 m above the ground, face towards +z.
static func _banner_mesh() -> ArrayMesh:
	if _banner != null:
		return _banner
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for q in [[0.0, 0.0], [0.0, 1.0], [1.0, 1.0], [0.0, 0.0], [1.0, 1.0], [1.0, 0.0]]:
		st.set_normal(Vector3.BACK)
		st.set_uv(Vector2(q[0], 1.0 - q[1]))
		st.add_vertex(Vector3((q[0] - 0.5) * 2.8, 0.15 + q[1] * 0.9, 0.0))
	_banner = st.commit()
	return _banner

class_name Buildings
extends RefCounted
## Countryside buildings and road furniture: French farmhouses (plastered walls, terracotta tile roof with an
## overhang, windows with painted shutters, door, chimney), wooden power-line poles with sagging wires, and the
## small kilometre / hectometre markers of the departmental roads.

const SHUTTER_COLORS := [Color(0.24, 0.38, 0.55), Color(0.3, 0.45, 0.3), Color(0.5, 0.33, 0.2), Color(0.62, 0.62, 0.6),
		Color(0.55, 0.2, 0.17)]
const WALL_COLORS := [Color(0.88, 0.83, 0.72), Color(0.82, 0.76, 0.64), Color(0.9, 0.88, 0.84), Color(0.76, 0.68, 0.55)]
const STONE_COLORS := [Color(0.72, 0.66, 0.56), Color(0.62, 0.58, 0.52), Color(0.78, 0.72, 0.6), Color(0.6, 0.52, 0.43)]

const WALL_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D detail_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D cell_tex : filter_linear_mipmap, repeat_enable;
uniform float tiles = 0.0;
varying vec3 wpos;
varying vec3 opos;
// horizontal coordinate along the face: z on the faces looking along x, x on the others (hip ends, gables)
varying float oh;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	opos = VERTEX;
	oh = abs(NORMAL.x) > abs(NORMAL.z) ? VERTEX.z : VERTEX.x;
}

// vertex colours are sRGB; their alpha picks the variant: walls 1 = plaster, 0 = rubble stone;
// roofs 1 = roman tiles, 0 = slates
void fragment() {
	float n = texture(detail_tex, (wpos.xz + wpos.yy) * 0.4).r;
	vec3 col = pow(COLOR.rgb, vec3(2.2)) * (0.88 + 0.2 * n);
	float rough = 0.92;
	if (tiles > 0.5 && COLOR.a > 0.5) {
		// roman tiles: rows along the slope, rounded channels across, a few darker tiles
		float row = fract(opos.y * 3.1);
		float ch = 0.5 + 0.5 * cos(oh * 26.0);
		float id = texture(cell_tex, floor(vec2(oh * 4.1, opos.y * 3.1)) * 0.137).r;
		col *= (0.78 + 0.22 * ch) * (1.0 - 0.25 * smoothstep(0.85, 1.0, row)) * (0.85 + 0.3 * id);
		rough = 0.8;
	} else if (tiles > 0.5) {
		// slates: small staggered rectangles, slightly bluish, a little sheen
		float rowi = floor(opos.y * 4.4);
		float row = fract(opos.y * 4.4);
		float colm = fract(oh * 3.0 + rowi * 0.5);
		float id = texture(cell_tex, vec2(floor(oh * 3.0 + rowi * 0.5), rowi) * 0.173).r;
		col *= (1.0 - 0.35 * smoothstep(0.88, 1.0, row)) * (1.0 - 0.25 * smoothstep(0.92, 1.0, colm)) * (0.85 + 0.3 * id);
		rough = 0.55;
	} else if (COLOR.a < 0.5) {
		// rubble stone: irregular blocks (cellular noise) with light mortar joints, lighter quoins at the corners
		vec2 sp = vec2(oh * 1.6, opos.y * 2.6);
		float cell = texture(cell_tex, sp * 0.12).r;
		float tone = texture(detail_tex, floor(sp) * 0.31).r;
		col *= (0.72 + 0.45 * tone) * (0.8 + 0.25 * smoothstep(0.05, 0.2, cell));
		col = mix(col * 1.35, col, smoothstep(0.02, 0.1, cell));
		rough = 0.95;
	} else {
		// plaster with stains towards the ground
		col *= 1.0 - 0.18 * (1.0 - smoothstep(0.0, 1.2, opos.y)) * n;
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.3;
}
"""

static var _wall_mat: ShaderMaterial
static var _roof_mat: ShaderMaterial
static var _plain := {}


static func _mat(c: Color, rough := 0.85, metal := 0.0) -> StandardMaterial3D:
	var key := "%s/%s/%s" % [c.to_html(), rough, metal]
	if not _plain.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = rough
		m.metallic = metal
		_plain[key] = m
	return _plain[key]


static func _shader_mat(tiles: bool) -> ShaderMaterial:
	if tiles and _roof_mat != null:
		return _roof_mat
	if not tiles and _wall_mat != null:
		return _wall_mat
	var sh := Shader.new()
	sh.code = WALL_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("detail_tex", GroundMaterials.noise("detail"))
	m.set_shader_parameter("cell_tex", GroundMaterials.noise("cell"))
	m.set_shader_parameter("tiles", 1.0 if tiles else 0.0)
	if tiles:
		_roof_mat = m
	else:
		_wall_mat = m
	return m


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	var n := (b - a).cross(d - a).normalized()
	for v in [a, b, c, a, c, d]:
		st.set_color(col)
		st.set_normal(-n)
		st.add_vertex(v)


static func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


## A farmhouse of w x l metres (ridge along local z), walls `height` high. Returns its root node (origin on the
## ground, at the centre). Plastered or rubble-stone walls; gable or hipped roof in roman tiles or slates. With
## `annex`, some get a lower outbuilding against a gable; with `garden`, a garden behind (local -x) closed by a
## wooden fence or a low stone wall.
static func farmhouse(rng: RandomNumberGenerator, w: float, l: float, height := 5.0, annex := false,
		garden := false) -> Node3D:
	var root := Node3D.new()
	var stone := rng.randf() < 0.35
	var wall_c: Color = (STONE_COLORS if stone else WALL_COLORS)[rng.randi() % 4]
	wall_c.a = 0.0 if stone else 1.0
	var slate := rng.randf() < 0.3
	var roof_c := (Color(0.32, 0.34, 0.38) if slate else Color(0.6, 0.3, 0.19)) * rng.randf_range(0.85, 1.1)
	roof_c.a = 0.0 if slate else 1.0
	var hip := rng.randf() < 0.35 and l > w + 1.0
	var shutter_c: Color = SHUTTER_COLORS[rng.randi() % SHUTTER_COLORS.size()]
	var hw := w * 0.5
	var hl := l * 0.5

	# walls (from 0.4 m under the ground) and roof of the house and of its annex: two meshes
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rst := SurfaceTool.new()
	rst.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ridge := _block(st, rst, Vector3.ZERO, w, l, height, wall_c, roof_c, hip)
	# chimney, doors, windows with frames and shutters, fence: one mesh (vertex colours), so a few draw calls
	var st2 := SurfaceTool.new()
	st2.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wood := Color(0.36, 0.27, 0.19) * rng.randf_range(0.8, 1.15)
	if annex and rng.randf() < 0.55:
		var w2 := w * rng.randf_range(0.7, 0.85)
		var l2 := rng.randf_range(4.0, 6.5)
		var s2 := 1.0 if rng.randf() < 0.5 else -1.0
		var c2 := Vector3(0.0, 0.0, s2 * (hl + l2 * 0.5 - 0.1))
		_block(st, rst, c2, w2, l2, height * 0.62, wall_c, roof_c, false)
		_add_box(st2, Vector3(0.1, 2.5, 2.4), c2 + Vector3(w2 * 0.5 + 0.03, 1.2, 0.0), wood)
	if garden and rng.randf() < 0.7:
		var gd := rng.randf_range(6.0, 10.0)
		var x0 := -hw - gd
		var gl := hl + 0.6
		var sides := [[Vector3(x0, 0, -gl), Vector3(x0, 0, gl)], [Vector3(x0, 0, -gl), Vector3(-hw, 0, -gl)],
				[Vector3(x0, 0, gl), Vector3(-hw, 0, gl)]]
		if rng.randf() < 0.4:
			var low := Color(0.66, 0.6, 0.5, 0.0) if not stone else wall_c
			for sd in sides:
				var a: Vector3 = sd[0]
				var b: Vector3 = sd[1]
				_add_box(st, Vector3(absf(b.x - a.x) + 0.5, 1.3, absf(b.z - a.z) + 0.5), (a + b) * 0.5 + Vector3(0, 0.25, 0), low)
		else:
			var post_c := wood * 1.2
			for sd in sides:
				var a: Vector3 = sd[0]
				var b: Vector3 = sd[1]
				var n_posts := maxi(2, ceili(a.distance_to(b) / 2.4) + 1)
				for k in n_posts:
					_add_box(st2, Vector3(0.12, 1.1, 0.12), a.lerp(b, float(k) / (n_posts - 1)) + Vector3(0, 0.45, 0), post_c)
				var size := Vector3(absf(b.x - a.x) + 0.06, 0.08, absf(b.z - a.z) + 0.06)
				for y in [0.45, 0.85]:
					_add_box(st2, size, (a + b) * 0.5 + Vector3(0, y, 0), post_c)
	var walls := MeshInstance3D.new()
	walls.mesh = st.commit()
	walls.material_override = _shader_mat(false)
	root.add_child(walls)
	var roof := MeshInstance3D.new()
	roof.mesh = rst.commit()
	roof.material_override = _shader_mat(true)
	root.add_child(roof)

	# the chimney goes from the top of the walls to above the ridge (a hipped roof is lower towards the ends)
	var cz := hl * rng.randf_range(0.3, 0.7) * (1 if rng.randf() < 0.5 else -1)
	if hip:
		cz *= 0.4
	_add_box(st2, Vector3(0.7, ridge + 1.1 - height, 0.7), Vector3(0.6, (ridge + 1.1 + height) * 0.5, cz), wall_c * 0.9)
	var glass := Color(0.12, 0.14, 0.17)
	var frame := Color(0.92, 0.92, 0.9)
	var n := maxi(2, floori(l / 3.4))
	var door_k := n / 2
	for s in [-1.0, 1.0]:
		for k in n:
			var z := -hl + l * (k + 0.5) / n
			var x: float = (hw + 0.02) * s
			if s > 0.0 and k == door_k:
				_add_box(st2, Vector3(0.1, 2.1, 1.1), Vector3(x, 1.05, z), shutter_c * 0.8)
				continue
			for floor_y in ([1.7, 3.8] if height > 4.5 else [1.7]):
				var wh := 1.3 if floor_y < 2.0 else 1.0
				_add_box(st2, Vector3(0.08, wh + 0.16, 1.06), Vector3(x, floor_y, z), frame)
				_add_box(st2, Vector3(0.1, wh, 0.9), Vector3(x + 0.01 * s, floor_y, z), glass)
				for side in [-1.0, 1.0]:
					var open := rng.randf() < 0.6
					var sz: float = z + side * (0.95 if open else 0.24)
					_add_box(st2, Vector3(0.06, wh, 0.47), Vector3(x + 0.05 * s, floor_y, sz), shutter_c)
	var details := MeshInstance3D.new()
	details.mesh = st2.commit()
	details.material_override = _details_mat()
	details.visibility_range_end = 400.0
	root.add_child(details)
	return root


## Appends the walls (gables unless the roof is hipped) and the roof (0.5 m overhang) of a w x l block centred on
## `c` (ground level) to `st` and `rst`. Returns the height of the ridge.
static func _block(st: SurfaceTool, rst: SurfaceTool, c: Vector3, w: float, l: float, height: float, wall_c: Color,
		roof_c: Color, hip: bool) -> float:
	var hw := w * 0.5
	var hl := l * 0.5
	var ridge := height + w * 0.3
	var over := 0.5
	var y0 := -0.4
	_quad(st, c + Vector3(-hw, y0, -hl), c + Vector3(-hw, height, -hl), c + Vector3(-hw, height, hl), c + Vector3(-hw, y0, hl), wall_c)
	_quad(st, c + Vector3(hw, y0, hl), c + Vector3(hw, height, hl), c + Vector3(hw, height, -hl), c + Vector3(hw, y0, -hl), wall_c)
	for s in [-1.0, 1.0]:
		var z: float = hl * s
		var b := c + Vector3(-hw * s, height, z)
		var d := c + Vector3(hw * s, height, z)
		_quad(st, c + Vector3(-hw * s, y0, z), b, d, c + Vector3(hw * s, y0, z), wall_c)
		if not hip:
			_tri(st, b, c + Vector3(0, ridge, z), d, wall_c, Vector3(0, 0, s))
	# same pitch on every slope: the hips start at hw from the ends
	var eave_y := height - over * (ridge - height) / hw
	var rl := maxf(hl - hw, 0.3) if hip else hl + over
	var top := ridge + 0.05
	for s in [-1.0, 1.0]:
		var e0 := c + Vector3((hw + over) * s, eave_y, -hl - over)
		var e1 := c + Vector3((hw + over) * s, eave_y, hl + over)
		var r0 := c + Vector3(0, top, -rl)
		var r1 := c + Vector3(0, top, rl)
		if s > 0.0:
			_quad(rst, e1, r1, r0, e0, roof_c)
		else:
			_quad(rst, e0, r0, r1, e1, roof_c)
		if hip:
			var z: float = (hl + over) * s
			_tri(rst, c + Vector3(-hw - over, eave_y, z), c + Vector3(0, top, rl * s), c + Vector3(hw + over, eave_y, z),
					roof_c, Vector3(0, 0.5, s))
	return ridge


## Appends a triangle whose normal points to the side of `outward`.
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color, outward: Vector3) -> void:
	var n := (b - a).cross(c - a).normalized()
	if n.dot(outward) < 0.0:
		n = -n
	for v in [a, b, c]:
		st.set_color(col)
		st.set_normal(n)
		st.add_vertex(v)


static var _detail_mat: StandardMaterial3D

static func _details_mat() -> StandardMaterial3D:
	if _detail_mat == null:
		_detail_mat = StandardMaterial3D.new()
		_detail_mat.vertex_color_use_as_albedo = true
		_detail_mat.vertex_color_is_srgb = true
		_detail_mat.roughness = 0.6
	return _detail_mat


## Appends a box (size, centre) with a vertex colour to a SurfaceTool.
static func _add_box(st: SurfaceTool, size: Vector3, c: Vector3, col: Color) -> void:
	var b := BoxMesh.new()
	b.size = size
	var arrays := b.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for i in idx:
		st.set_color(col)
		st.set_normal(norms[i])
		st.add_vertex(verts[i] + c)

## A barn: wooden walls, corrugated-looking roof, a wide open door. Returns its root (origin on the ground).
static func barn(rng: RandomNumberGenerator, w: float, l: float) -> Node3D:
	var root := Node3D.new()
	var wood := Color(0.42, 0.3, 0.2) * rng.randf_range(0.8, 1.15)
	var height := 4.5
	var body := _box(root, Vector3(w, height + 0.4, l), Vector3(0, height * 0.5 - 0.2, 0), _mat(wood, 0.9))
	body.name = "Body"
	var pm := PrismMesh.new()
	pm.size = Vector3(w + 0.8, 2.2, l + 0.6)
	var roof := MeshInstance3D.new()
	roof.mesh = pm
	roof.material_override = _mat(Color(0.45, 0.46, 0.47), 0.55, 0.3)
	roof.position = Vector3(0, height + 1.1, 0)
	root.add_child(roof)
	_box(root, Vector3(0.1, 3.4, 3.6), Vector3(w * 0.5 + 0.02, 1.7, 0), _mat(Color(0.05, 0.05, 0.05), 1.0))
	return root


## Wooden poles along `points` (ground positions) with a cross-arm and three sagging wires between them.
static func power_line(parent: Node3D, points: PackedVector3Array, height := 8.0) -> void:
	if points.size() < 2:
		return
	var wood := _mat(Color(0.32, 0.25, 0.18), 0.9)
	var pole := CylinderMesh.new()
	pole.top_radius = 0.1
	pole.bottom_radius = 0.14
	pole.height = height
	pole.radial_segments = 6
	pole.material = wood
	var arm := BoxMesh.new()
	arm.size = Vector3(1.6, 0.12, 0.12)
	arm.material = wood
	var mm_p := MultiMesh.new()
	mm_p.transform_format = MultiMesh.TRANSFORM_3D
	mm_p.mesh = pole
	mm_p.instance_count = points.size()
	var mm_a := MultiMesh.new()
	mm_a.transform_format = MultiMesh.TRANSFORM_3D
	mm_a.mesh = arm
	mm_a.instance_count = points.size()
	var tops := []
	for i in points.size():
		var dir := points[mini(i + 1, points.size() - 1)] - points[maxi(i - 1, 0)]
		dir.y = 0.0
		var yaw := atan2(dir.x, dir.z)
		var basis := Basis(Vector3.UP, yaw)
		mm_p.set_instance_transform(i, Transform3D(basis, points[i] + Vector3(0, height * 0.5 - 0.3, 0)))
		mm_a.set_instance_transform(i, Transform3D(basis, points[i] + Vector3(0, height - 0.6, 0)))
		var side := basis * Vector3.RIGHT
		tops.append([points[i] + Vector3(0, height - 0.5, 0) - side * 0.65, points[i] + Vector3(0, height - 0.5, 0),
				points[i] + Vector3(0, height - 0.5, 0) + side * 0.65])
	for mm in [mm_p, mm_a]:
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		parent.add_child(mmi)
	# wires: thin triangular tubes sagging between the poles
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in points.size() - 1:
		for k in 3:
			var a: Vector3 = tops[i][k]
			var b: Vector3 = tops[i + 1][k]
			var sag := a.distance_to(b) * 0.025
			var prev := a
			for s in range(1, 13):
				var t := s / 12.0
				var p := a.lerp(b, t) - Vector3(0, sag * 4.0 * t * (1.0 - t), 0)
				_wire(st, prev, p, 0.014)
				prev = p
	var wires := MeshInstance3D.new()
	wires.mesh = st.commit()
	wires.material_override = _mat(Color(0.12, 0.12, 0.12), 0.5, 0.6)
	wires.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(wires)


static func _wire(st: SurfaceTool, a: Vector3, b: Vector3, r: float) -> void:
	var axis := (b - a).normalized()
	var x := axis.cross(Vector3.UP).normalized() * r
	var y := axis.cross(x).normalized() * r
	var ring := [x, -x * 0.5 + y * 0.87, -x * 0.5 - y * 0.87]
	for k in 3:
		var p0: Vector3 = ring[k]
		var p1: Vector3 = ring[(k + 1) % 3]
		for v in [a + p0, b + p0, a + p1, a + p1, b + p0, b + p1]:
			st.set_normal((v - a).normalized())
			st.add_vertex(v)


## Small white markers with a coloured cap (red every km, yellow otherwise) at the given ground positions.
static func road_markers(parent: Node3D, points: PackedVector3Array, yaws: PackedFloat32Array, km_every := 10) -> void:
	if points.is_empty():
		return
	var post := BoxMesh.new()
	post.size = Vector3(0.18, 0.55, 0.1)
	post.material = _mat(Color(0.92, 0.92, 0.9), 0.6)
	var cap := BoxMesh.new()
	cap.size = Vector3(0.19, 0.14, 0.11)
	var big := BoxMesh.new()
	big.size = Vector3(0.4, 0.9, 0.25)
	big.material = _mat(Color(0.93, 0.93, 0.92), 0.6)
	var red_cap := BoxMesh.new()
	red_cap.size = Vector3(0.41, 0.22, 0.26)
	red_cap.material = _mat(Color(0.75, 0.12, 0.1), 0.6)
	cap.material = _mat(Color(0.9, 0.75, 0.1), 0.6)
	var small_t: Array[Transform3D] = []
	var big_t: Array[Transform3D] = []
	for i in points.size():
		var b := Basis(Vector3.UP, yaws[i])
		if i % km_every == 0:
			big_t.append(Transform3D(b, points[i]))
		else:
			small_t.append(Transform3D(b, points[i]))
	for spec in [[post, small_t, 0.25], [cap, small_t, 0.58], [big, big_t, 0.4], [red_cap, big_t, 0.96]]:
		var list: Array = spec[1]
		if list.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = spec[0]
		mm.instance_count = list.size()
		for j in list.size():
			var t: Transform3D = list[j]
			mm.set_instance_transform(j, Transform3D(t.basis, t.origin + Vector3(0, float(spec[2]), 0)))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.visibility_range_end = 250.0
		parent.add_child(mmi)

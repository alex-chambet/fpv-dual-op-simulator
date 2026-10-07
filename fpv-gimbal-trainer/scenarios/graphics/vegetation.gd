class_name Vegetation
extends RefCounted
## Procedural trees: spruces (whorls of drooping branches covered with a needle texture) and broadleaf trees (a
## trunk, limbs and clusters of leaf cards around darker cores). Both keep the size of the occlusion profiles of
## PropFactory (tree_radius_at / round_tree_radius_at), so what hides the subject on screen is what the scoring
## counts. They sway in the wind, are lit through when backlit, and can carry snow on their upper faces.
##
## Trees are planted in chunks of CHUNK metres, each with a detailed and a simple model: the renderer shows the
## detailed one up to GraphicsSettings.tree_detail_distance().

const CHUNK := 64.0
const VARIANTS := 3
const GROUP := &"vegetation_lod"

## Snow on the trees of the current scene (0..1), set by the environment before planting.
static var snow_cover := 0.0

const LEAF_SHADER := """
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D leaf_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 tip_tint : source_color = vec3(1.1, 1.15, 0.75);
uniform float alpha_cut = 0.35;
uniform float wind_strength = 1.0;
uniform float snow = 0.0;

varying vec3 tint;
varying vec3 vcol;
varying float up_facing;

void vertex() {
	tint = INSTANCE_CUSTOM.rgb;
	vcol = COLOR.rgb;
	vec3 root = MODEL_MATRIX[3].xyz;
	float ph = INSTANCE_CUSTOM.a * 6.2832 + root.x * 0.05 + root.z * 0.03;
	float h = max(VERTEX.y - 1.0, 0.0);
	float sway = (sin(TIME * 0.9 + ph) * 0.7 + sin(TIME * 2.3 + ph * 1.7) * 0.3) * wind_strength;
	VERTEX.xz += vec2(0.005, 0.0035) * sway * h * h;
	VERTEX += NORMAL * sin(TIME * 6.5 + dot(VERTEX, vec3(4.1, 3.3, 5.7))) * 0.02 * COLOR.g * wind_strength;
	up_facing = NORMAL.y;
}

void fragment() {
	// cards are lit the same on both faces (the renderer flips the normal of back faces)
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	vec4 t = texture(leaf_tex, UV);
	float ao = vcol.r;
	vec3 col = t.rgb * tint * mix(0.3, 1.0, ao);
	col = mix(col, col * tip_tint, vcol.g * 0.4);
	float sn = snow * smoothstep(0.45, 0.85, up_facing + (vcol.b - 0.5) * 0.5) * smoothstep(0.35, 0.7, ao);
	col = mix(col, vec3(0.9, 0.93, 0.97), sn);
	ALBEDO = col;
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	ROUGHNESS = mix(0.82, 0.7, sn);
	SPECULAR = 0.3;
	BACKLIGHT = col * 0.6 * (1.0 - sn);
}
"""

const BARK_SHADER := """
shader_type spatial;

uniform sampler2D detail_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 bark : source_color = vec3(0.3, 0.24, 0.18);
varying vec3 opos;
varying vec3 vcol;

void vertex() {
	opos = VERTEX;
	vcol = COLOR.rgb;
}

void fragment() {
	// vertical furrows: noise stretched along the trunk
	float a = atan(opos.x, opos.z);
	float n = texture(detail_tex, vec2(a * 0.6, opos.y * 0.12)).r;
	float f = texture(detail_tex, vec2(a * 2.3 + 0.3, opos.y * 0.5)).r;
	vec3 col = bark * vcol.r * (0.62 + 0.45 * n) * (0.8 + 0.3 * f);
	if (vcol.b < 0.5) {  // cut wood (ends of logs, stumps): rings
		float rings = 0.5 + 0.5 * sin(length(opos.xz) * 90.0);
		col = vec3(0.58, 0.45, 0.3) * (0.85 + 0.15 * rings) * (0.8 + 0.3 * n);
	}
	ALBEDO = col;
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
}
"""

static var _meshes := {}
static var _leaf_mat: ShaderMaterial
static var _needle_mat: ShaderMaterial
static var _bark_mat: ShaderMaterial


# --- Planting ------------------------------------------------------------------------------------

## Plants trees of `kind` ("conifer" or "broadleaf") at the ground points, scaled by `scales`.
static func plant(parent: Node3D, kind: String, grounds: PackedVector3Array, scales: PackedFloat32Array,
		foliage: Color, seed_value: int) -> void:
	var n := grounds.size()
	if n == 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var xforms: Array[Transform3D] = []
	var customs := PackedColorArray()
	for i in n:
		var s := scales[i]
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s)
		var tint := rng.randf_range(0.75, 1.25) if kind == "conifer" else rng.randf_range(0.8, 1.2)
		var hue := rng.randf_range(-0.04, 0.04)
		customs.append(Color(foliage.r * tint * (1.0 + hue * 2.0), foliage.g * tint, foliage.b * tint * (1.0 - hue * 2.0),
				rng.randf()))
		xforms.append(Transform3D(basis, grounds[i]))
	place(parent, kind, xforms, customs, rng)


## Places instances of a mesh kind (trees, or a Decor kind) in chunks, each with a detailed and a simple model.
## customs = per-instance tint (rgb) and random value (a). end_distance > 0 hides them beyond it.
static func place(parent: Node3D, kind: String, xforms: Array[Transform3D], customs: PackedColorArray,
		rng: RandomNumberGenerator, end_distance := 0.0) -> void:
	for needles in [true, false]:  # snow of the current scene on the shared leaf materials
		leaf_material(needles).set_shader_parameter("snow", snow_cover)
	var variants := Decor.variants(kind) if Decor.handles(kind) else VARIANTS
	var two_lods := not Decor.handles(kind) or Decor.has_lod(kind)
	var buckets := {}
	for i in xforms.size():
		var g := xforms[i].origin
		var key := Vector3i(floori(g.x / CHUNK), floori(g.z / CHUNK), rng.randi() % variants)
		if not buckets.has(key):
			buckets[key] = []
		buckets[key].append(i)
	var detail := GraphicsSettings.tree_detail_distance()
	for key in buckets:
		var items: Array = buckets[key]
		for lod in (2 if two_lods else 1):
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_custom_data = true
			mm.mesh = mesh(kind, lod, key.z)
			mm.instance_count = items.size()
			for j in items.size():
				mm.set_instance_transform(j, xforms[items[j]])
				mm.set_instance_custom_data(j, customs[items[j]])
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			if two_lods:
				mmi.set_meta("lod", lod)
				mmi.set_meta("end", end_distance)
				mmi.add_to_group(GROUP)
				_apply_range(mmi, detail)
			elif end_distance > 0.0:
				mmi.visibility_range_end = end_distance
				mmi.visibility_range_end_margin = 5.0
			if Decor.handles(kind) and not Decor.casts_shadow(kind):
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			parent.add_child(mmi)


static func _apply_range(mmi: GeometryInstance3D, detail: float) -> void:
	var end := float(mmi.get_meta("end", 0.0))
	if int(mmi.get_meta("lod", 0)) == 0:
		mmi.visibility_range_begin = 0.0
		mmi.visibility_range_end = minf(detail, end) if end > 0.0 else detail
		mmi.visibility_range_end_margin = 8.0
	else:
		mmi.visibility_range_begin = detail
		mmi.visibility_range_begin_margin = 8.0
		mmi.visibility_range_end = end
		mmi.visible = end <= 0.0 or end > detail


## Updates the detail distance of the trees of a scene (graphics quality changed).
static func update_ranges(tree: SceneTree) -> void:
	var detail := GraphicsSettings.tree_detail_distance()
	for node in tree.get_nodes_in_group(GROUP):
		_apply_range(node, detail)


static func mesh(kind: String, lod: int, variant: int) -> ArrayMesh:
	var key := "%s/%d/%d" % [kind, lod, variant]
	if not _meshes.has(key):
		match kind:
			"conifer":
				_meshes[key] = _conifer(lod, variant)
			"broadleaf":
				_meshes[key] = _broadleaf(lod, variant)
			_:
				_meshes[key] = Decor.build(kind, lod, variant)
	return _meshes[key]

# --- Materials -----------------------------------------------------------------------------------

static func leaf_material(needles: bool) -> ShaderMaterial:
	if needles and _needle_mat != null:
		return _needle_mat
	if not needles and _leaf_mat != null:
		return _leaf_mat
	var sh := Shader.new()
	sh.code = LEAF_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("leaf_tex", needle_texture() if needles else _leaves_texture())
	if needles:
		m.set_shader_parameter("tip_tint", Color(1.08, 1.15, 0.85))
		m.set_shader_parameter("alpha_cut", 0.3)
		_needle_mat = m
	else:
		m.set_shader_parameter("tip_tint", Color(1.12, 1.12, 0.7))
		m.set_shader_parameter("alpha_cut", 0.4)
		_leaf_mat = m
	return m


static func bark_material() -> ShaderMaterial:
	if _bark_mat == null:
		var sh := Shader.new()
		sh.code = BARK_SHADER
		_bark_mat = ShaderMaterial.new()
		_bark_mat.shader = sh
		_bark_mat.set_shader_parameter("detail_tex", GroundMaterials.noise("detail"))
	return _bark_mat


static func _hash(k: int) -> float:
	var x := (k * 374761393 + 668265263) & 0x7fffffff
	x = ((x ^ (x >> 13)) * 1274126177) & 0x7fffffff
	return float(x & 0xffff) / 65535.0


## Spruce branch seen from above: a main twig along v, side twigs going out and forward on both sides, each a
## fuzzy band of needles. The outline (narrow at the base and the tip) comes from the texture, not the card.
static func needle_texture() -> ImageTexture:
	var w := 128
	var h := 256
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var twigs := []  # [v start, length, side]
	for side in 2:
		for k in 15:
			var v0 := 0.035 + k * 0.064 + (_hash(k * 5 + side * 31) - 0.5) * 0.03
			var env := pow(sin(PI * clampf(v0 + 0.12, 0.0, 1.0)), 0.6)
			twigs.append([v0, env * (0.75 + 0.25 * _hash(k * 3 + side * 17)), side])
	for y in h:
		var v := (y + 0.5) / h
		for x in w:
			var u := (x + 0.5) / w
			var s := absf(u - 0.5) * 2.0
			var side := 1 if u > 0.5 else 0
			var p := Vector2(s, v)
			var best := 9.0
			var along := 0.0
			for t in twigs:
				if t[2] != side or absf(float(t[0]) - v) > 0.7:
					continue
				var a := Vector2(0.0, t[0])
				var b := Vector2(t[1], float(t[0]) + float(t[1]) * 0.6)
				var ab := b - a
				var k := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
				var d := p.distance_to(a + ab * k) / (1.0 - 0.45 * k)  # twigs thin out towards their tip
				if d < best:
					best = d
					along = k
			var fuzz := (_hash(x * 131 + y * 977) - 0.5) * 0.014
			var alpha := 1.0 - smoothstep(0.009, 0.02, best + fuzz)
			var stem := 1.0 - smoothstep(0.025, 0.045, s)
			alpha = maxf(alpha, stem * (1.0 - smoothstep(0.9, 0.97, v)))
			alpha *= smoothstep(0.0, 0.03, v)
			var shade := 0.7 + 0.32 * along + 0.18 * (_hash(x * 17 + y * 3) - 0.5)
			var c := Color(shade * 0.93, shade, shade * 0.86)
			if stem > 0.5 and best > 0.06:
				c = Color(0.55, 0.5, 0.4)
			img.set_pixel(x, y, Color(c.r, c.g, c.b, alpha))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

## Cluster of leaves on a disc; the corner (u, v < 0.1) is solid foliage, used by the cores of the crowns.
static func _leaves_texture() -> ImageTexture:
	var n := 256
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.85, 0.9, 0.8, 0.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	for i in 70:
		var ang := rng.randf() * TAU
		var rad := sqrt(rng.randf()) * 0.4
		var cx := (0.5 + cos(ang) * rad) * n
		var cy := (0.5 + sin(ang) * rad) * n
		var length := rng.randf_range(0.09, 0.15) * n
		var width := length * rng.randf_range(0.42, 0.55)
		var rot := rng.randf() * TAU
		var dir := Vector2(cos(rot), sin(rot))
		var shade := rng.randf_range(0.72, 1.08)
		var yellow := rng.randf_range(-0.06, 0.1)
		var base := Color(shade * (0.9 + yellow), shade, shade * (0.78 - yellow))
		var r := int(length) + 1
		for py in range(maxi(0, int(cy) - r), mini(n, int(cy) + r + 1)):
			for px in range(maxi(0, int(cx) - r), mini(n, int(cx) + r + 1)):
				var d := Vector2(px + 0.5 - cx, py + 0.5 - cy)
				var al := d.dot(dir) / (length * 0.5)
				var ac := d.dot(Vector2(-dir.y, dir.x)) / (width * 0.5)
				var e := al * al + ac * ac * (1.0 + 0.6 * al)
				if e < 1.0:
					var vein := 1.0 - 0.25 * (1.0 - smoothstep(0.0, 0.12, absf(ac)))
					var light := 0.92 + 0.12 * ac
					var c := Color(base.r * vein * light, base.g * vein * light, base.b * vein * light, 1.0)
					img.set_pixel(px, py, c)
	for py in 24:
		for px in 24:
			img.set_pixel(px, py, Color(0.8, 0.86, 0.72, 1.0))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


# --- Geometry ------------------------------------------------------------------------------------

## Tapered cylinder from a to b (radii r0 -> r1), vertex colour c.
static func cylinder(st: SurfaceTool, a: Vector3, b: Vector3, r0: float, r1: float, sides: int, c: Color) -> void:
	var axis := (b - a).normalized()
	var ref := Vector3.RIGHT if absf(axis.dot(Vector3.UP)) > 0.9 else Vector3.UP
	var x := axis.cross(ref).normalized()
	var z := axis.cross(x).normalized()
	for k in sides:
		var a0 := TAU * k / sides
		var a1 := TAU * (k + 1) / sides
		var d0 := x * cos(a0) + z * sin(a0)
		var d1 := x * cos(a1) + z * sin(a1)
		var quad := [[a + d0 * r0, d0], [b + d0 * r1, d0], [a + d1 * r0, d1], [a + d1 * r0, d1], [b + d0 * r1, d0], [b + d1 * r1, d1]]
		for q in quad:
			st.set_color(c)
			st.set_normal(q[1])
			st.set_uv(Vector2.ZERO)
			st.add_vertex(q[0])


static func vert(st: SurfaceTool, p: Vector3, n: Vector3, uv: Vector2, c: Color) -> void:
	st.set_color(c)
	st.set_normal(n)
	st.set_uv(uv)
	st.add_vertex(p)


static func _conifer(lod: int, variant: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 100 + variant * 7 + lod * 1000
	var bark := SurfaceTool.new()
	bark.begin(Mesh.PRIMITIVE_TRIANGLES)
	cylinder(bark, Vector3.ZERO, Vector3(0, 6.9, 0), 0.2, 0.03, 7 if lod == 0 else 5, Color(1, 1, 1))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := 0.3 if lod == 0 else 0.6
	var y := 1.12 + rng.randf() * 0.1
	var ang := rng.randf() * TAU
	while y < 6.85:
		var t := (y - 1.1) / 5.9
		var r := 1.95 * (7.1 - y) / 5.95 * rng.randf_range(0.9, 1.06)
		var count := clampi(roundi(4.0 + 4.5 * r / 1.95), 4, 9) if lod == 0 else clampi(roundi(3.0 + 3.0 * r / 1.95), 3, 6)
		for b in count:
			var a := ang + TAU * b / count + rng.randf_range(-0.25, 0.25)
			var length := r * rng.randf_range(0.88, 1.1) + 0.12
			var width := length * (1.0 if lod == 0 else 1.15)
			_branch(st, Vector3(0, y, 0), a, length, width, 0.32 - 0.12 * t, t, rng)
		ang += 2.39996
		y += step * rng.randf_range(0.85, 1.15)
	# leader at the top
	for k in 3:
		var a2 := TAU * k / 3.0
		var side := Vector3(cos(a2), 0, sin(a2)) * 0.22
		var top := Vector3(0, 7.15, 0)
		var low := Vector3(0, 6.45, 0)
		var n := Vector3(cos(a2), 0.4, sin(a2)).normalized()
		var c0 := Color(0.85, 0.6, 0.5)
		var c1 := Color(1.0, 1.0, 0.5)
		vert(st, low - side, n, Vector2(0, 0.3), c0)
		vert(st, top, n, Vector2(0.5, 1.0), c1)
		vert(st, low + side, n, Vector2(1, 0.3), c0)
	var mesh := bark.commit()
	st.commit(mesh)
	mesh.surface_set_material(0, bark_material())
	mesh.surface_set_material(1, leaf_material(true))
	return mesh


## One spruce branch: a diamond-shaped card folded along its twig, drooping towards the tip.
static func _branch(st: SurfaceTool, base: Vector3, ang: float, length: float, width: float, droop: float,
		t: float, rng: RandomNumberGenerator) -> void:
	var d := Vector3(cos(ang), 0.0, sin(ang))
	var side := d.cross(Vector3.UP).normalized()
	var b := base + d * 0.08
	var tip := base + d * length + Vector3.UP * (-droop * length + rng.randf_range(-0.05, 0.08))
	var mid := base + d * length * 0.5 + Vector3.UP * (-droop * length * 0.3 + 0.07 * length)
	var ml := mid - side * width * 0.5 - Vector3.UP * 0.08 * length
	var mr := mid + side * width * 0.5 - Vector3.UP * 0.08 * length
	var rnd := rng.randf()
	var ao_in := lerpf(0.3, 0.6, t)
	var ao_out := lerpf(0.78, 1.0, t)
	var c_b := Color(ao_in, 0.0, rnd)
	var c_m := Color(lerpf(ao_in, ao_out, 0.6), 0.5, rnd)
	var c_t := Color(ao_out, 1.0, rnd)
	var n_in := (d * 0.45 + Vector3.UP * 0.7).normalized()
	var n_out := (d * 0.8 + Vector3.UP * 0.45).normalized()
	var n_mid := (n_in + n_out).normalized()
	for tri in [[b, ml, mid], [b, mid, mr], [ml, tip, mid], [mid, tip, mr]]:
		for p in tri:
			var uv: Vector2
			var c: Color
			var n: Vector3
			if p == b:
				uv = Vector2(0.5, 0.0)
				c = c_b
				n = n_in
			elif p == tip:
				uv = Vector2(0.5, 1.0)
				c = c_t
				n = n_out
			elif p == ml:
				uv = Vector2(0.0, 0.5)
				c = c_m
				n = (n_mid - side * 0.3).normalized()
			elif p == mr:
				uv = Vector2(1.0, 0.5)
				c = c_m
				n = (n_mid + side * 0.3).normalized()
			else:
				uv = Vector2(0.5, 0.5)
				c = c_m
				n = n_mid
			vert(st, p, n, uv, c)


static func _broadleaf(lod: int, variant: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 300 + variant * 11 + lod * 1000
	var bark := SurfaceTool.new()
	bark.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center := Vector3(0, 6.1, 0)
	cylinder(bark, Vector3.ZERO, Vector3(0, 4.4, 0), 0.32, 0.22, 7 if lod == 0 else 5, Color(1, 1, 1))
	var limbs := 4 if lod == 0 else 3
	for k in limbs:
		var a := TAU * k / limbs + rng.randf_range(-0.4, 0.4)
		var start := Vector3(0, rng.randf_range(3.5, 4.2), 0)
		var end := center + Vector3(cos(a) * 1.4, rng.randf_range(-0.3, 0.9), sin(a) * 1.4)
		cylinder(bark, start, end, 0.16, 0.05, 5 if lod == 0 else 4, Color(0.9, 0.9, 0.9))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var clusters := 13 if lod == 0 else 8
	for k in clusters:
		# spread the clusters over an ellipsoid (golden spiral), the top one in the middle
		var yy := 1.0 - 2.0 * (k + 0.5) / clusters
		var rr := sqrt(maxf(0.0, 1.0 - yy * yy))
		var a := k * 2.39996 + variant
		var dir := Vector3(cos(a) * rr, yy * 0.8, sin(a) * rr)
		var c := center + Vector3(dir.x * 1.85, dir.y * 1.6, dir.z * 1.85) * rng.randf_range(0.7, 1.0)
		var rc := rng.randf_range(1.0, 1.3)
		cluster(st, c, rc, center, lod, rng)
	var mesh := bark.commit()
	st.commit(mesh)
	mesh.surface_set_material(0, bark_material())
	mesh.surface_set_material(1, leaf_material(false))
	return mesh


## Leaf cluster: a dark core (solid corner of the texture) and leaf cards facing outwards.
static func cluster(st: SurfaceTool, c: Vector3, rc: float, crown: Vector3, lod: int, rng: RandomNumberGenerator) -> void:
	var core_uv := Vector2(0.03, 0.03)
	# core: an octahedron, slightly irregular
	var axes := [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]
	var pts := []
	for ax in axes:
		pts.append(c + ax * rc * rng.randf_range(0.55, 0.75))
	var faces := [[0, 2, 4], [4, 2, 1], [1, 2, 5], [5, 2, 0], [4, 3, 0], [1, 3, 4], [5, 3, 1], [0, 3, 5]]
	for f in faces:
		for idx in f:
			var p: Vector3 = pts[idx]
			var n := (p - crown).normalized()
			vert(st, p, n, core_uv, Color(crown_ao(p, crown) * 0.75, 0.2, rng.randf()))
	var cards := 14 if lod == 0 else 7
	var size := rc * (1.15 if lod == 0 else 1.45)
	for i in cards:
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.6, 1), rng.randf_range(-1, 1)).normalized()
		var outward := (c - crown).normalized()
		dir = (dir + outward * 0.6).normalized()
		var p := c + dir * rc * rng.randf_range(0.6, 0.95)
		var ref := Vector3.UP if absf(dir.y) < 0.9 else Vector3.RIGHT
		var u := dir.cross(ref).normalized()
		var v := dir.cross(u).normalized()
		var rot := rng.randf() * TAU
		var uu := (u * cos(rot) + v * sin(rot)) * size * 0.5
		var vv := (v * cos(rot) - u * sin(rot)) * size * 0.5
		var q := [p - uu - vv, p + uu - vv, p + uu + vv, p - uu + vv]
		var uvs := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
		var rnd := rng.randf()
		for idx in [0, 1, 2, 0, 2, 3]:
			var pp: Vector3 = q[idx]
			var n := ((pp - crown).normalized() * 0.7 + dir * 0.3).normalized()
			vert(st, pp, n, uvs[idx], Color(crown_ao(pp, crown), 1.0, rnd))


## Ambient occlusion of a point of a crown: dark inside and underneath, bright on the top and the outside.
static func crown_ao(p: Vector3, crown: Vector3) -> float:
	var rel := p - crown
	var outward := clampf(Vector2(rel.x, rel.z).length() / 2.8, 0.0, 1.0)
	var up := clampf((rel.y + 2.5) / 5.0, 0.0, 1.0)
	return clampf(0.25 + 0.45 * up + 0.35 * outward, 0.2, 1.0)

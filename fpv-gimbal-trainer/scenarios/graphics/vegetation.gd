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

## The textures come from photographs (assets/foliage/, baked by tools/bake_foliage.gd). They are stored
## around a fixed mean and multiplied back here, because the colour of a tree is its per-instance tint.
const TEX_GAIN := 2.1
const BOUGH_TEX := "res://assets/foliage/spruce_bough.png"
const LEAVES_TEX := "res://assets/foliage/leaf_cluster.png"
const BARK_TEX := "res://assets/foliage/bark.jpg"

const LEAF_SHADER := """
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D leaf_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec3 tip_tint : source_color = vec3(1.1, 1.15, 0.75);
uniform float alpha_cut = 0.35;
uniform float wind_strength = 1.0;
uniform float snow = 0.0;
uniform float gain = 2.1;
// 1 on the boughs of the conifers: the snow lies along the middle of the card and closes it
uniform float bough = 0.0;

varying vec3 tint;
varying vec3 vcol;
varying float up_facing;
varying vec3 wpos;

void vertex() {
	// The tints of the scenes were chosen for flat painted cards: a photograph multiplied by them
	// comes out as green as a toy. Foliage is a dull, dark green; half of the hue is enough.
	vec3 raw = INSTANCE_CUSTOM.rgb;
	float lum = dot(raw, vec3(0.3, 0.5, 0.2));
	tint = mix(vec3(lum), raw, 0.5) * mix(0.82, 0.6, bough);
	vcol = COLOR.rgb;
	vec3 root = MODEL_MATRIX[3].xyz;
	float ph = INSTANCE_CUSTOM.a * 6.2832 + root.x * 0.05 + root.z * 0.03;
	float h = max(VERTEX.y - 1.0, 0.0);
	// gusts roll across the forest along the wind: stronger sway and leaf flutter where one passes
	float gust = 0.5 + 0.5 * sin(dot(root.xz, vec2(0.045, 0.03)) - TIME * 1.1);
	gust *= gust;
	float sway = (sin(TIME * 0.9 + ph) * 0.7 + sin(TIME * 2.3 + ph * 1.7) * 0.3) * wind_strength * (0.75 + 0.5 * gust);
	VERTEX.xz += vec2(0.005, 0.0035) * sway * h * h;
	VERTEX += NORMAL * sin(TIME * (6.5 + 3.0 * gust) + dot(VERTEX, vec3(4.1, 3.3, 5.7))) * (0.014 + 0.03 * gust) * COLOR.g * wind_strength;
	up_facing = NORMAL.y;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// cards are lit the same on both faces (the renderer flips the normal of back faces)
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	vec4 t = texture(leaf_tex, UV);
	float ao = vcol.r;
	vec3 col = t.rgb * gain * tint * mix(0.22, 1.0, ao * ao);
	col = mix(col, col * tip_tint, vcol.g * 0.35);
	// far away the mipmaps average the gaps between the needles into the alpha, and a cut-out
	// tree thins into a skeleton: the cut is lowered with the distance instead
	float dist = length(VERTEX);
	float alpha = t.a * (1.0 + 1.6 * smoothstep(12.0, 110.0, dist));
	// snow: on what faces up, heaped along the middle of a bough (it closes the gaps between the
	// needles there, and leaves a dark fringe of twigs hanging out underneath)
	float heap = 1.0 - smoothstep(0.04, 0.3 + 0.1 * vcol.b, abs(UV.x - 0.5));
	heap *= smoothstep(0.02, 0.2, UV.y) * (1.0 - smoothstep(0.6, 0.92, UV.y));
	float lump = sin(wpos.x * 5.1 + wpos.z * 3.3) * sin(wpos.z * 4.7 - wpos.y * 2.9);
	// (the needles themselves hold some snow too: the alpha of the photograph lets it through)
	heap = mix(1.0, max(smoothstep(0.35, 0.8, heap + 0.3 * lump), 0.45 * t.a * heap), bough);
	float sn = snow * heap * smoothstep(0.2, 0.7, up_facing + (vcol.b - 0.5) * 0.4) * smoothstep(0.2, 0.55, ao);
	col = mix(col, vec3(0.86, 0.9, 0.96), sn);
	alpha = max(alpha, smoothstep(0.3, 0.6, sn) * bough);
	ALBEDO = col;
	ALPHA = alpha;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	ROUGHNESS = mix(0.75, 0.6, sn);
	SPECULAR = 0.25;
	BACKLIGHT = col * 0.75 * (1.0 - sn);
	if (alpha_cut < -1.0) {  // (never true: keeps the vertex-only uniform alive in this stage, for Metal)
		ALBEDO *= wind_strength;
	}
}
"""

const BARK_SHADER := """
shader_type spatial;

uniform sampler2D detail_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D bark_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 bark : source_color = vec3(0.37, 0.33, 0.28);
varying vec3 opos;
varying vec3 vcol;

void vertex() {
	opos = VERTEX;
	vcol = COLOR.rgb;
}

void fragment() {
	// the photographed bark wrapped around the trunk, its furrows along it
	float a = atan(opos.x, opos.z);
	vec3 photo = texture(bark_tex, vec2(a * 0.3183, opos.y * 0.45)).rgb * 2.0;
	float n = texture(detail_tex, vec2(a * 0.6, opos.y * 0.12)).r;
	vec3 col = bark * vcol.r * photo * (0.75 + 0.4 * n);
	if (vcol.b < 0.5) {  // cut wood (ends of logs, stumps): rings
		float rings = 0.5 + 0.5 * sin(length(opos.xz) * 90.0);
		col = vec3(0.58, 0.45, 0.3) * (0.85 + 0.15 * rings) * (0.8 + 0.3 * n);
	}
	ALBEDO = col;
	ROUGHNESS = 0.95;
	SPECULAR = 0.15;
}
"""

static var _meshes := {}
static var _leaf_mat: ShaderMaterial
static var _needle_mat: ShaderMaterial
static var _bark_mat: ShaderMaterial


# --- Planting ------------------------------------------------------------------------------------

## Plants trees of `kind` ("conifer" or "broadleaf") at the ground points, scaled by `scales`. end_distance > 0
## hides them beyond it (very large forests: the far scenery shows the forest further away).
static func plant(parent: Node3D, kind: String, grounds: PackedVector3Array, scales: PackedFloat32Array,
		foliage: Color, seed_value: int, end_distance := 0.0) -> void:
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
	place(parent, kind, xforms, customs, rng, end_distance)


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
		var batch: Array[Transform3D] = []
		var tints := PackedColorArray()
		for j in items.size():
			batch.append(xforms[items[j]])
			tints.append(customs[items[j]])
		for lod in (2 if two_lods else 1):
			var mmi := MeshBatch.add(null, mesh(kind, lod, key.z), batch, {"custom": tints})
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
	m.set_shader_parameter("leaf_tex", load(BOUGH_TEX if needles else LEAVES_TEX))
	m.set_shader_parameter("gain", TEX_GAIN)
	if needles:
		m.set_shader_parameter("tip_tint", Color(1.16, 1.14, 0.84))
		m.set_shader_parameter("alpha_cut", 0.32)
		m.set_shader_parameter("bough", 1.0)
		_needle_mat = m
	else:
		m.set_shader_parameter("tip_tint", Color(1.15, 1.12, 0.78))
		m.set_shader_parameter("alpha_cut", 0.4)
		m.set_shader_parameter("bough", 0.0)
		_leaf_mat = m
	return m


static func bark_material() -> ShaderMaterial:
	if _bark_mat == null:
		var sh := Shader.new()
		sh.code = BARK_SHADER
		_bark_mat = ShaderMaterial.new()
		_bark_mat.shader = sh
		_bark_mat.set_shader_parameter("detail_tex", GroundMaterials.noise("detail"))
		_bark_mat.set_shader_parameter("bark_tex", load(BARK_TEX))
	return _bark_mat


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


## Spruce: a trunk and whorls of boughs all the way up, long and drooping at the bottom, short and rising
## at the top. The outline stays inside PropFactory.tree_radius_at (what the scoring counts as hiding).
static func _conifer(lod: int, variant: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 100 + variant * 7 + lod * 1000
	var bark := SurfaceTool.new()
	bark.begin(Mesh.PRIMITIVE_TRIANGLES)
	cylinder(bark, Vector3.ZERO, Vector3(0, 6.9, 0), 0.17, 0.02, 8 if lod == 0 else 5, Color(1, 1, 1))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := 0.34 if lod == 0 else 0.62
	var y := 1.15 + rng.randf() * 0.1
	var ang := rng.randf() * TAU
	while y < 6.7:
		var t := (y - 1.1) / 5.9
		# a spruce is not a cone: the whorls of a year are longer or shorter than their neighbours
		var r := 1.95 * (7.1 - y) / 5.95 * rng.randf_range(0.8, 1.04)
		var count := clampi(roundi(3.6 + 3.6 * r / 1.95), 4, 7) if lod == 0 else clampi(roundi(3.0 + 3.0 * r / 1.95), 3, 6)
		for b in count:
			var a := ang + TAU * b / count + rng.randf_range(-0.3, 0.3)
			var length := r * rng.randf_range(0.82, 1.06) + 0.14 + 0.16 * t
			var yy := y + rng.randf_range(-0.14, 0.14)
			if lod == 0:
				_bough(st, Vector3(0, yy, 0), a, length, lerpf(0.62, -0.3, pow(t, 0.8)) + rng.randf_range(-0.08, 0.08),
						t, rng, t < 0.6)
			else:
				_branch(st, Vector3(0, yy, 0), a, length, length * 1.1, 0.5 - 0.5 * t, t, rng)
		if lod == 0 and r > 0.9:
			# short boughs close to the trunk: the inside of the tree is not empty
			for b2 in 3:
				_bough(st, Vector3(0, y + 0.14, 0), ang + 1.0 + TAU * b2 / 3.0, r * rng.randf_range(0.4, 0.55), 0.3,
						t * 0.4, rng, false)
		ang += 2.39996
		y += step * rng.randf_range(0.85, 1.15) * (1.0 - 0.3 * t if lod == 0 else 1.0)
	# the last shoots, and the leader: two crossed cards standing on the trunk
	for k in 3:
		var a2 := TAU * k / 3.0 + rng.randf()
		if lod == 0:
			_bough(st, Vector3(0, 6.55, 0), a2, 0.42, -0.7, 1.0, rng, false)
		var side := Vector3(cos(a2), 0, sin(a2)) * 0.2
		var low := Vector3(0, 6.35, 0)
		var top := Vector3(0, 7.12, 0)
		var n := Vector3(cos(a2 + 1.57), 0.5, sin(a2 + 1.57)).normalized()
		var c0 := Color(0.8, 0.5, 0.5)
		var c1 := Color(1.0, 1.0, 0.5)
		var quad := [[low - side, Vector2(0.2, 0.62), c0], [low + side, Vector2(0.8, 0.62), c0],
				[top + side, Vector2(0.8, 1.0), c1], [top - side, Vector2(0.2, 1.0), c1]]
		for idx in [0, 1, 2, 0, 2, 3]:
			vert(st, quad[idx][0], n, quad[idx][1], quad[idx][2])
	var mesh := bark.commit()
	st.commit(mesh)
	mesh.surface_set_material(0, bark_material())
	mesh.surface_set_material(1, leaf_material(true))
	return mesh


## One spruce bough, detailed. droop > 0 hangs, < 0 rises (top of the tree).
##  - a strip of three quads curving along its length (it droops, then the tip turns back up), folded like
##    a roof along its twig: seen from the side a flat card would be a line;
##  - with `curtain`, the twigs hanging under it: a vertical card along the bough. This is what makes a
##    spruce a solid mass seen from the ground, and it stays green under the snow.
static func _bough(st: SurfaceTool, base: Vector3, ang: float, length: float, droop: float, t: float,
		rng: RandomNumberGenerator, curtain: bool) -> void:
	var d := Vector3(cos(ang), 0.0, sin(ang))
	var side := d.cross(Vector3.UP).normalized()
	var width := length * rng.randf_range(0.52, 0.64)
	var rnd := rng.randf()
	var twist := rng.randf_range(-0.14, 0.14)
	var ao_in := lerpf(0.22, 0.5, t)
	var ao_out := lerpf(0.8, 1.0, t)
	var sag := maxf(droop, 0.0)
	var rows := []   # [mid, left, right, s]
	for k in 4:
		var s := k / 3.0
		var reach := 0.06 + length * s * (1.0 - 0.14 * absf(droop) * s)
		var h := length * (-droop * pow(s, 1.4) * 0.8 + 0.24 * sag * s * s * s)
		var mid := base + d * reach + Vector3.UP * h
		var hang := width * (0.2 + 0.22 * sag)
		var roll := twist * width * (s - 0.3)
		var l := mid - side * width * 0.5 - Vector3.UP * (hang + roll)
		var r := mid + side * width * 0.5 - Vector3.UP * (hang - roll)
		rows.append([mid, l, r, s])
	for k in 3:
		var r0: Array = rows[k]
		var r1: Array = rows[k + 1]
		var along := (Vector3(r1[0]) - Vector3(r0[0])).normalized()
		var up := side.cross(along).normalized()
		if up.y < 0.0:
			up = -up
		for q in [[r0[1], r0[0], r1[0], r1[1], 0.0, 0.5], [r0[0], r0[2], r1[2], r1[0], 0.5, 1.0]]:
			var u0: float = q[4]
			var u1: float = q[5]
			var pts := [q[0], q[1], q[2], q[3]]
			var uvs: Array[Vector2] = [Vector2(u0, r0[3]), Vector2(u1, r0[3]), Vector2(u1, r1[3]), Vector2(u0, r1[3])]
			for idx in [0, 1, 2, 0, 2, 3]:
				var s2: float = uvs[idx].y
				# shaded as a soft volume: mostly up and outwards, the edges leaning to their side
				var edge: float = (uvs[idx].x - 0.5) * 2.0
				var n: Vector3 = (up * 0.75 + d * (0.25 + 0.45 * s2) + side * edge * 0.5).normalized()
				vert(st, pts[idx], n, uvs[idx], Color(lerpf(ao_in, ao_out, pow(s2, 0.7)), s2, rnd))
	if not curtain:
		return
	var drop := length * (0.2 + 0.3 * sag) * rng.randf_range(0.8, 1.2)
	var lean := side * rng.randf_range(-0.25, 0.25) * drop
	var nc := (d * 0.7 + Vector3.UP * 0.25 + side * (0.4 if rnd > 0.5 else -0.4)).normalized()
	for pair in [[0, 1], [1, 3]]:  # (two quads are enough for what hangs)
		var r0: Array = rows[pair[0]]
		var r1: Array = rows[pair[1]]
		var s0: float = r0[3]
		var s1: float = r1[3]
		# the curtain is deepest in the middle of the bough
		var d0 := drop * (0.35 + 0.65 * sin(PI * minf(s0 * 1.15, 1.0)))
		var d1 := drop * (0.35 + 0.65 * sin(PI * minf(s1 * 1.15, 1.0)))
		var pts := [r0[0], r1[0], Vector3(r1[0]) + lean - Vector3.UP * d1, Vector3(r0[0]) + lean - Vector3.UP * d0]
		var uvs: Array[Vector2] = [Vector2(0.5, s0), Vector2(0.5, s1), Vector2(0.97, s1), Vector2(0.97, s0)]
		var ao0 := lerpf(ao_in, ao_out, pow(s0, 0.7))
		var ao1 := lerpf(ao_in, ao_out, pow(s1, 0.7))
		var cols := [Color(ao0, s0, rnd), Color(ao1, s1, rnd), Color(ao1 * 0.8, 1.0, rnd), Color(ao0 * 0.8, 1.0, rnd)]
		for idx in [0, 1, 2, 0, 2, 3]:
			vert(st, pts[idx], nc, uvs[idx], cols[idx])


## One spruce branch of the simple model: a diamond-shaped card folded along its twig, drooping towards the tip.
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


## Broadleaf tree: a trunk that forks into limbs, and a crown made of lobes of leaf cards - wider than
## tall, uneven, hanging lower on its sides. A ball on a pole is what a child draws. The crown stays
## inside PropFactory.round_tree_radius_at (what the scoring counts as hiding).
static func _broadleaf(lod: int, variant: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 300 + variant * 11 + lod * 1000
	var bark := SurfaceTool.new()
	bark.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center := Vector3(0, 6.0, 0)
	# the trunk leans a little and narrows up to the fork
	var fork := Vector3(rng.randf_range(-0.25, 0.25), 3.6, rng.randf_range(-0.25, 0.25))
	var sides := 9 if lod == 0 else 5
	cylinder(bark, Vector3(0, -0.1, 0), Vector3(fork.x * 0.3, 1.6, fork.z * 0.3), 0.33, 0.25, sides, Color(1, 1, 1))
	cylinder(bark, Vector3(fork.x * 0.3, 1.6, fork.z * 0.3), fork, 0.25, 0.18, sides, Color(1, 1, 1))
	# lobes of the crown: around an ellipsoid, a few low ones on the sides, one on top
	var lobes: Array[Vector3] = []
	var count := 14 if lod == 0 else 8
	for k in count:
		var yy := 1.0 - 2.0 * (k + 0.5) / count
		var rr := sqrt(maxf(0.0, 1.0 - yy * yy))
		var a := k * 2.39996 + variant * 1.3
		var reach := rng.randf_range(0.6, 1.0)
		lobes.append(center + Vector3(cos(a) * rr * 2.0 * reach, yy * 1.6 + 0.05, sin(a) * rr * 2.0 * reach))
	for k in lobes.size():
		var c := lobes[k]
		# a limb from the fork towards each lobe (the lowest ones leave the trunk lower)
		var start := fork + Vector3(0, minf(0.0, (c.y - center.y) * 0.4), 0)
		var elbow := start.lerp(c, 0.5) + Vector3(0, 0.35, 0)
		cylinder(bark, start, elbow, 0.13, 0.08, 5 if lod == 0 else 4, Color(0.85, 0.85, 0.85))
		cylinder(bark, elbow, c, 0.08, 0.03, 5 if lod == 0 else 4, Color(0.75, 0.75, 0.75))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for c in lobes:
		cluster(st, c, rng.randf_range(0.75, 1.02) * (1.0 if lod == 0 else 1.3), center, lod, rng)
	var mesh := bark.commit()
	st.commit(mesh)
	mesh.surface_set_material(0, bark_material())
	mesh.surface_set_material(1, leaf_material(false))
	return mesh


## Leaf cluster: a dark core (solid corner of the texture) and leaf cards facing outwards.
static func cluster(st: SurfaceTool, c: Vector3, rc: float, crown: Vector3, lod: int, rng: RandomNumberGenerator) -> void:
	var core_uv := Vector2(0.02, 0.02)
	# core: an octahedron, slightly irregular
	var axes := [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]
	var pts := []
	for ax in axes:
		pts.append(c + ax * rc * rng.randf_range(0.42, 0.6))
	var faces := [[0, 2, 4], [4, 2, 1], [1, 2, 5], [5, 2, 0], [4, 3, 0], [1, 3, 4], [5, 3, 1], [0, 3, 5]]
	for f in faces:
		for idx in f:
			var p: Vector3 = pts[idx]
			var n := (p - crown).normalized()
			vert(st, p, n, core_uv, Color(crown_ao(p, crown) * 0.6, 0.2, rng.randf()))
	var cards := 12 if lod == 0 else 7
	var size := rc * (1.45 if lod == 0 else 1.8)
	var outward := (c - crown).normalized()
	for i in cards:
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.7, 1), rng.randf_range(-1, 1)).normalized()
		dir = (dir + outward * 0.55).normalized()
		var p := c + dir * rc * rng.randf_range(0.55, 1.0)
		# the card lies across `face`: mostly outwards, but tilted - a leafy branch is never square to the eye
		var face := (dir + Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(-0.2, 0.7), rng.randf_range(-0.6, 0.6))).normalized()
		var ref := Vector3.UP if absf(face.y) < 0.9 else Vector3.RIGHT
		var u := face.cross(ref).normalized()
		var v := face.cross(u).normalized()
		var rot := rng.randf() * TAU
		var sz := size * rng.randf_range(0.75, 1.15)
		var uu := (u * cos(rot) + v * sin(rot)) * sz * 0.5
		var vv := (v * cos(rot) - u * sin(rot)) * sz * 0.5
		var q := [p - uu - vv, p + uu - vv, p + uu + vv, p - uu + vv]
		# (the corner of the texture is the solid patch of the cores: the cards stay clear of it)
		var uvs := [Vector2(0.06, 0.06), Vector2(1, 0.06), Vector2(1, 1), Vector2(0.06, 1)]
		var rnd := rng.randf()
		for idx in [0, 1, 2, 0, 2, 3]:
			var pp: Vector3 = q[idx]
			# lit as part of the whole crown, with some of its own lobe: the lobes then read as volumes
			var n := ((pp - crown).normalized() * 0.5 + (pp - c).normalized() * 0.35 + dir * 0.15).normalized()
			vert(st, pp, n, uvs[idx], Color(crown_ao(pp, crown), 1.0, rnd))


## Ambient occlusion of a point of a crown: dark inside and underneath, bright on the top and the outside.
static func crown_ao(p: Vector3, crown: Vector3) -> float:
	var rel := p - crown
	var outward := clampf(Vector2(rel.x, rel.z).length() / 2.8, 0.0, 1.0)
	var up := clampf((rel.y + 2.5) / 5.0, 0.0, 1.0)
	return clampf(0.3 + 0.42 * up + 0.35 * outward, 0.3, 1.0)

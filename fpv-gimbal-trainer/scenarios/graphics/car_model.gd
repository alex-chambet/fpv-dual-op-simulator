class_name CarModel
extends RefCounted
## A passenger car built from lofted sections (no 3D asset): rounded lower body in glossy paint (clear coat),
## tinted glasshouse with the roof, wheels with rims, headlights, tail lights, grille, number plates, mirrors.
## About 4.2 x 1.8 x 1.45 m, front towards -Z, standing on y = 0 (the same size as the old box car).
## Two body styles: 0 saloon (boot), 1 hatchback.

static var _cache := {}


static func _paint(c: Color) -> StandardMaterial3D:
	var key := "paint/" + c.to_html()
	if not _cache.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.32
		m.metallic = 0.35
		m.clearcoat_enabled = true
		m.clearcoat = 0.8
		m.clearcoat_roughness = 0.12
		_cache[key] = m
	return _cache[key]


static func _flat(key: String, c: Color, rough: float, metal := 0.0, emit := 0.0) -> StandardMaterial3D:
	if not _cache.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = rough
		m.metallic = metal
		if emit > 0.0:
			m.emission_enabled = true
			m.emission = c
			m.emission_energy_multiplier = emit
		_cache[key] = m
	return _cache[key]


## Builds a car under `parent`. Returns the wheel nodes (axle along X after their rotation, spin about X).
static func build(parent: Node3D, color: Color, style := 0) -> Array[MeshInstance3D]:
	var body_mesh := _body_mesh(style)
	var body := MeshInstance3D.new()
	body.name = "CarBody"
	body.mesh = body_mesh
	body.set_surface_override_material(0, _paint(color))
	body.set_surface_override_material(1, _flat("glass", Color(0.05, 0.07, 0.09), 0.05, 0.2))
	body.set_surface_override_material(2, _flat("trim", Color(0.04, 0.04, 0.045), 0.6))
	parent.add_child(body)
	# lights, plates, mirrors
	var head := _flat("head", Color(0.95, 0.95, 0.9), 0.1, 0.0, 0.6)
	var tail := _flat("tail", Color(1.0, 0.05, 0.02), 0.3, 0.0, 2.0)
	var plate := _flat("plate", Color(0.92, 0.92, 0.9), 0.5)
	for sx in [-1.0, 1.0]:
		_box(parent, Vector3(0.36, 0.12, 0.06), Vector3(sx * 0.6, 0.78, -2.09), head)
		_box(parent, Vector3(0.34, 0.12, 0.06), Vector3(sx * 0.62, 0.84 if style == 0 else 0.92, 2.08), tail)
		_box(parent, Vector3(0.18, 0.1, 0.08), Vector3(sx * 0.95, 1.06, -0.82), _paint(color))
	_box(parent, Vector3(0.52, 0.11, 0.03), Vector3(0, 0.5, -2.13), plate)
	_box(parent, Vector3(0.52, 0.11, 0.03), Vector3(0, 0.55, 2.13), plate)
	var wheels: Array[MeshInstance3D] = []
	for wx in [-0.8, 0.8]:
		for wz in [-1.3, 1.32]:
			var w := MeshInstance3D.new()
			w.mesh = _wheel_mesh()
			w.position = Vector3(wx, 0.33, wz)
			w.rotation = Vector3(0.0, 0.0, PI * 0.5)
			parent.add_child(w)
			wheels.append(w)
	return wheels


static func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)


## Rounded rectangle section at z: from y0 to y1, half widths w0 (bottom) / w1 (top), corner radius r.
static func _ring(z: float, y0: float, y1: float, w0: float, w1: float, r: float) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var corners := [[w1, y1, 0.0], [-w1, y1, PI * 0.5], [-w0, y0, PI], [w0, y0, PI * 1.5]]
	r = minf(r, (y1 - y0) * 0.45)
	for c in corners:
		var cx: float = c[0] - signf(c[0]) * r
		var cy: float = c[1] - signf(c[1] - (y0 + y1) * 0.5) * r
		for k in 3:
			var a: float = c[2] + PI * 0.5 * k / 2.0
			pts.append(Vector3(cx + cos(a) * r, cy + sin(a) * r, z))
	return pts


## Lofts rings into one smooth surface (indexed), closing both ends with flat caps.
static func _loft(st: SurfaceTool, rings: Array) -> void:
	var base := 0
	var n: int = (rings[0] as PackedVector3Array).size()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ring in rings:
		for p in ring:
			st.add_vertex(p)
	for i in rings.size() - 1:
		for k in n:
			var a := base + i * n + k
			var b := base + i * n + (k + 1) % n
			var c := base + (i + 1) * n + k
			var d := base + (i + 1) * n + (k + 1) % n
			for idx in [a, c, b, b, c, d]:
				st.add_index(idx)
	st.generate_normals()
	st.deindex()  # so caps (not indexed) can be appended to the same surface


static func _cap(st: SurfaceTool, ring: PackedVector3Array, facing: float) -> void:
	var c := Vector3.ZERO
	for p in ring:
		c += p
	c /= ring.size()
	for k in ring.size():
		var a := ring[k]
		var b := ring[(k + 1) % ring.size()]
		for v in ([c, a, b] if facing > 0.0 else [c, b, a]):
			st.set_normal(Vector3(0, 0, facing))
			st.add_vertex(v)


static func _body_mesh(style: int) -> ArrayMesh:
	var key := "body/%d" % style
	if _cache.has(key):
		return _cache[key]
	# lower body: [z, bottom, top (beltline), half width]
	var lower := [[-2.12, 0.34, 0.6, 0.8], [-2.02, 0.28, 0.8, 0.86], [-1.7, 0.26, 0.9, 0.89], [-1.15, 0.26, 0.97, 0.9],
			[0.0, 0.26, 0.99, 0.9], [1.4, 0.26, 1.0, 0.9], [1.85, 0.27, 0.99 if style == 0 else 1.02, 0.89],
			[2.05, 0.3, 0.93 if style == 0 else 1.0, 0.86], [2.12, 0.38, 0.82 if style == 0 else 0.9, 0.82]]
	var rings := []
	for s in lower:
		rings.append(_ring(s[0], s[1], s[2], s[3] - 0.05, s[3], 0.12))
	var st := SurfaceTool.new()
	_loft(st, rings)
	var mesh := st.commit()
	var caps := SurfaceTool.new()
	caps.begin(Mesh.PRIMITIVE_TRIANGLES)
	_cap(caps, rings[0], -1.0)
	_cap(caps, rings[rings.size() - 1], 1.0)
	caps.commit(mesh)
	# glasshouse: windscreen, roof, rear window (hatchback: steep rear down to the tail)
	var top := [[-1.15, 0.97, 0.98, 0.82, 0.8], [-0.35, 0.99, 1.42, 0.82, 0.66], [0.85, 1.0, 1.44, 0.83, 0.66],
			[1.55 if style == 0 else 1.95, 1.0, 1.0 if style == 0 else 1.32, 0.83, 0.8 if style == 0 else 0.7]]
	if style == 1:
		top.append([2.04, 1.0, 1.04, 0.82, 0.78])
	var grings := []
	for s in top:
		grings.append(_ring(s[0], s[1], s[2], s[3], s[4], 0.08))
	var gst := SurfaceTool.new()
	_loft(gst, grings)
	gst.commit(mesh)
	# the glass surface is 1; caps of the glasshouse + trim (bumpers, wheel arches) are surface 2
	var trim := SurfaceTool.new()
	trim.begin(Mesh.PRIMITIVE_TRIANGLES)
	_cap(trim, grings[0], -1.0)
	_cap(trim, grings[grings.size() - 1], 1.0)
	for bz in [-2.1, 2.1]:
		_slab(trim, Vector3(0, 0.36, bz), Vector3(1.74, 0.14, 0.12))
	_slab(trim, Vector3(0, 0.62, -2.11), Vector3(0.9, 0.16, 0.04))  # grille
	for wx in [-1.0, 1.0]:
		for wz in [-1.3, 1.32]:
			_slab(trim, Vector3(wx * 0.885, 0.52, wz), Vector3(0.05, 0.5, 0.86))  # dark wheel arch
		_slab(trim, Vector3(wx * 0.905, 0.3, 0.0), Vector3(0.03, 0.1, 1.7))  # sill
	trim.commit(mesh)
	# merge: surface 0 = paint (lower body + caps), 1 = glass, 2 = trim
	var out := ArrayMesh.new()
	var paint := SurfaceTool.new()
	paint.append_from(mesh, 0, Transform3D.IDENTITY)
	paint.append_from(mesh, 1, Transform3D.IDENTITY)
	paint.commit(out)
	var glass := SurfaceTool.new()
	glass.append_from(mesh, 2, Transform3D.IDENTITY)
	glass.commit(out)
	var tr := SurfaceTool.new()
	tr.append_from(mesh, 3, Transform3D.IDENTITY)
	tr.commit(out)
	_cache[key] = out
	return out


static func _slab(st: SurfaceTool, c: Vector3, size: Vector3) -> void:
	var b := BoxMesh.new()
	b.size = size
	var arrays := b.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for i in idx:
		st.set_normal(norms[i])
		st.add_vertex(verts[i] + c)


## Tyre with a light alloy rim and five dark holes (so the rotation shows); axle along local Y.
static func _wheel_mesh() -> ArrayMesh:
	if _cache.has("wheel"):
		return _cache["wheel"]
	var r := 0.33
	var w := 0.22
	var mesh := ArrayMesh.new()
	var tyre := CylinderMesh.new()
	tyre.top_radius = r
	tyre.bottom_radius = r
	tyre.height = w
	tyre.radial_segments = 16
	var st := SurfaceTool.new()
	st.append_from(tyre, 0, Transform3D.IDENTITY)
	st.commit(mesh)
	var rim := SurfaceTool.new()
	rim.begin(Mesh.PRIMITIVE_TRIANGLES)
	var holes := SurfaceTool.new()
	holes.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [-1.0, 1.0]:
		var y: float = side * (w * 0.5 + 0.004)
		var n := Vector3(0, side, 0)
		_disc(rim, Vector3(0, y, 0), r * 0.66, n, 16)
		for k in 5:
			var a := TAU * k / 5.0
			_disc(holes, Vector3(cos(a) * r * 0.4, y + side * 0.003, sin(a) * r * 0.4), r * 0.13, n, 8)
		_disc(holes, Vector3(0, y + side * 0.003, 0), r * 0.1, n, 8)
	rim.commit(mesh)
	holes.commit(mesh)
	mesh.surface_set_material(0, _flat("tyre", Color(0.04, 0.04, 0.04), 0.9))
	mesh.surface_set_material(1, _flat("rim", Color(0.72, 0.73, 0.75), 0.3, 0.8))
	mesh.surface_set_material(2, _flat("holes", Color(0.05, 0.05, 0.05), 0.7))
	_cache["wheel"] = mesh
	return mesh


static func _disc(st: SurfaceTool, c: Vector3, r: float, n: Vector3, sides: int) -> void:
	for k in sides:
		var a0 := TAU * k / sides
		var a1 := TAU * (k + 1) / sides
		var p0 := c + Vector3(cos(a0) * r, 0, sin(a0) * r)
		var p1 := c + Vector3(cos(a1) * r, 0, sin(a1) * r)
		for v in ([c, p1, p0] if n.y > 0.0 else [c, p0, p1]):
			st.set_normal(n)
			st.add_vertex(v)

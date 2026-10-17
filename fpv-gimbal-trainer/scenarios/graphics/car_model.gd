class_name CarModel
extends RefCounted
## A passenger car built from lofted sections (no 3D asset): rounded lower body in glossy paint (clear coat),
## tinted glasshouse with the roof, wheels with rims, headlights, tail lights, grille, number plates, mirrors.
## About 4.2 x 1.8 x 1.45 m, front towards -Z, standing on y = 0 (the same size as the old box car).
## Three body styles: 0 saloon (boot), 1 hatchback, 2 racing coupe (lower, flatter roof) - the last
## one is used by race(), which adds the wing, the splitter, the slicks and the livery.

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


## A GT racing car: the low coupe body in a two-tone livery, a big rear wing, a front splitter, a
## diffuser, slicks on wide rims, tow hooks and a roof hatch. Returns
## {"wheels": [MeshInstance3D], "brake_lights": [MeshInstance3D], "wheel_radius": float}.
static func race(parent: Node3D, colour: Color, accent: Color) -> Dictionary:
	var body := MeshInstance3D.new()
	body.name = "RaceBody"
	body.mesh = _body_mesh(2)
	body.set_surface_override_material(0, _paint(colour))
	body.set_surface_override_material(1, _glass())
	body.set_surface_override_material(2, _flat("race_trim", Color(0.07, 0.07, 0.08), 0.45))
	parent.add_child(body)
	var dark := _flat("race_dark", Color(0.06, 0.06, 0.07), 0.55)
	var carbon := _flat("race_carbon", Color(0.11, 0.11, 0.12), 0.3, 0.25)
	var livery := _paint(accent)
	# Livery: a stripe over the bonnet and another over the roof, each sitting ON its own panel.
	# (A single long box would float above the nose and the tail, which is exactly what it used to do.)
	_box(parent, Vector3(0.34, 0.02, 1.25), Vector3(0, 0.905, -1.42), livery)   # bonnet
	_box(parent, Vector3(0.3, 0.02, 1.5), Vector3(0, 1.252, 0.2), livery)       # roof
	_box(parent, Vector3(0.9, 0.02, 0.5), Vector3(0, 0.925, 1.62), livery)      # engine cover
	# number roundel on each door, flush with the flank
	for sx in [-1.0, 1.0]:
		var disc := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.23
		cyl.bottom_radius = 0.23
		cyl.height = 0.012
		cyl.radial_segments = 20
		disc.mesh = cyl
		disc.material_override = _flat("race_plate", Color(0.95, 0.95, 0.93), 0.5)
		disc.position = Vector3(sx * 0.995, 0.72, 0.15)
		disc.rotation = Vector3(0.0, 0.0, PI * 0.5)
		parent.add_child(disc)
	# front splitter (a thin lip, barely proud of the nose) and two small dive planes
	_box(parent, Vector3(1.86, 0.035, 0.34), Vector3(0, 0.125, -2.22), carbon)
	for sx in [-1.0, 1.0]:
		var plane := _box_node(parent, Vector3(0.26, 0.022, 0.16), Vector3(sx * 0.9, 0.42, -2.05), carbon)
		plane.rotation.x = 0.16
	# side skirts and rear diffuser
	for sx in [-1.0, 1.0]:
		_box(parent, Vector3(0.07, 0.1, 2.2), Vector3(sx * 0.985, 0.155, 0.1), carbon)
	_box(parent, Vector3(1.6, 0.18, 0.44), Vector3(0, 0.2, 2.16), carbon)
	# rear wing: a thin plane on two slim swan necks, with low endplates
	for sx in [-1.0, 1.0]:
		_box(parent, Vector3(0.025, 0.3, 0.58), Vector3(sx * 0.9, 1.19, 1.98), carbon)
		var neck := _box_node(parent, Vector3(0.05, 0.3, 0.07), Vector3(sx * 0.42, 1.06, 2.04), carbon)
		neck.rotation.x = -0.25
	var wing := _box_node(parent, Vector3(1.84, 0.035, 0.46), Vector3(0, 1.25, 1.98), carbon)
	wing.rotation.x = 0.13
	_box(parent, Vector3(1.84, 0.022, 0.14), Vector3(0, 1.14, 2.18), carbon)
	# roof hatch, bonnet vents and mirrors
	_box(parent, Vector3(0.4, 0.015, 0.42), Vector3(0, 1.253, 0.72), dark)
	for sx in [-1.0, 1.0]:
		_box(parent, Vector3(0.26, 0.012, 0.3), Vector3(sx * 0.44, 0.902, -1.1), dark)
		var mirror := _box_node(parent, Vector3(0.17, 0.085, 0.06), Vector3(sx * 1.02, 0.97, -0.86), _paint(colour))
		mirror.rotation.y = sx * 0.18
		_box(parent, Vector3(0.04, 0.03, 0.12), Vector3(sx * 0.95, 0.95, -0.82), dark)   # stalk
	# lights: headlight tape and the tail lights (which glow under braking)
	for sx in [-1.0, 1.0]:
		_box(parent, Vector3(0.42, 0.13, 0.04), Vector3(sx * 0.6, 0.71, -2.145),
				_flat("race_tape", Color(0.95, 0.8, 0.1), 0.4))
	var lights: Array[MeshInstance3D] = []
	for sx in [-1.0, 1.0]:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.5, 0.03, 0.02)
		m.roughness = 0.3
		m.emission_enabled = true
		m.emission = Color(1.0, 0.05, 0.02)
		m.emission_energy_multiplier = 0.25
		var mi := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.4, 0.1, 0.05)
		mi.mesh = b
		mi.material_override = m
		mi.position = Vector3(sx * 0.6, 0.9, 2.12)
		parent.add_child(mi)
		lights.append(mi)
	var rain := StandardMaterial3D.new()
	rain.albedo_color = Color(0.4, 0.02, 0.02)
	rain.roughness = 0.3
	rain.emission_enabled = true
	rain.emission = Color(1.0, 0.05, 0.02)
	rain.emission_energy_multiplier = 1.6
	var rain_mi := MeshInstance3D.new()
	var rb := BoxMesh.new()
	rb.size = Vector3(0.12, 0.12, 0.05)
	rain_mi.mesh = rb
	rain_mi.material_override = rain
	rain_mi.position = Vector3(0.0, 1.05, 2.1)
	parent.add_child(rain_mi)
	# slicks: wider and a little bigger than the road wheels, and flush with the flanks (a racing car
	# fills its arches; set any further in, the tyres disappear inside the bodywork)
	var wheels: Array[MeshInstance3D] = []
	for wx in [-0.96, 0.96]:
		for wz in [-1.32, 1.34]:
			var w := MeshInstance3D.new()
			w.mesh = _wheel_mesh()
			w.position = Vector3(wx, 0.35, wz)
			w.rotation = Vector3(0.0, 0.0, PI * 0.5)
			w.scale = Vector3(1.06, 1.45, 1.06)  # the axle is along local Y: Y = width
			parent.add_child(w)
			wheels.append(w)
	return {"wheels": wheels, "brake_lights": lights, "wheel_radius": 0.35}


## Tinted glass that still shows the sky: a dark blue-grey that reflects, not a black slab.
static func _glass() -> StandardMaterial3D:
	if not _cache.has("race_glass2"):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.09, 0.12, 0.15)
		m.roughness = 0.06
		m.metallic = 0.65
		m.metallic_specular = 0.9
		_cache["race_glass2"] = m
	return _cache["race_glass2"]


## Same as _box, but returns the node so the caller can angle it.
static func _box_node(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


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
	# lower body: [z, bottom, top (beltline), half width]. Style 2 (racing coupe) sits lower on the
	# ground, is wider over the wheels and has a flatter nose.
	var lower := [[-2.12, 0.34, 0.6, 0.8], [-2.02, 0.28, 0.8, 0.86], [-1.7, 0.26, 0.9, 0.89], [-1.15, 0.26, 0.97, 0.9],
			[0.0, 0.26, 0.99, 0.9], [1.4, 0.26, 1.0, 0.9], [1.85, 0.27, 0.99 if style == 0 else 1.02, 0.89],
			[2.05, 0.3, 0.93 if style == 0 else 1.0, 0.86], [2.12, 0.38, 0.82 if style == 0 else 0.9, 0.82]]
	if style == 2:
		lower = [[-2.2, 0.17, 0.5, 0.84], [-2.06, 0.14, 0.7, 0.92], [-1.7, 0.13, 0.82, 0.97], [-1.15, 0.13, 0.88, 0.99],
				[0.0, 0.13, 0.9, 1.0], [1.4, 0.13, 0.92, 0.99], [1.85, 0.14, 0.95, 0.97],
				[2.08, 0.17, 0.9, 0.92], [2.2, 0.28, 0.76, 0.84]]
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
	if style == 2:
		top = [[-1.3, 0.88, 0.89, 0.88, 0.86], [-0.5, 0.9, 1.22, 0.88, 0.6], [0.8, 0.9, 1.24, 0.88, 0.6],
				[1.95, 0.9, 0.96, 0.88, 0.74]]
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
	var arch_x := 0.985 if style == 2 else 0.885
	var sill_x := 1.005 if style == 2 else 0.905
	var bumper_y := 0.3 if style == 2 else 0.36
	for bz in [-2.1, 2.1]:
		_slab(trim, Vector3(0, bumper_y, bz), Vector3(1.74, 0.14, 0.12))
	_slab(trim, Vector3(0, 0.62 if style != 2 else 0.5, -2.11), Vector3(0.9, 0.16, 0.04))  # grille
	# wheel arches: a thin dark lip round the top of the wheel, not a panel over the whole flank
	var arch := Vector3(0.05, 0.5, 0.9) if style != 2 else Vector3(0.035, 0.26, 0.84)
	var arch_y := 0.52 if style != 2 else 0.6
	for wx in [-1.0, 1.0]:
		for wz in [-1.3, 1.32]:
			_slab(trim, Vector3(wx * arch_x, arch_y, wz), arch)
		_slab(trim, Vector3(wx * sill_x, 0.3, 0.0), Vector3(0.03, 0.1, 1.7))  # sill
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

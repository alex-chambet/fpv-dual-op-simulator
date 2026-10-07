class_name PlaceholderModel
extends RefCounted
## Builds the placeholder of a sport from primitives (no 3D asset needed): a coloured person /
## capsule / box, plus a "gear" (skis, bike, horse, canopy...). Scaled so that its largest
## dimension equals SubjectDefinition.effective_size().
##
## build() returns the model root and fills `parts` for the animations:
##   body (Node3D bobbing), legs / arms (swing pivots), wheels (spin), horse_legs, paddle,
##   wheel_radius, aim_y (height of the point to frame, already scaled).


static func build(def: SubjectDefinition, parts: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Model"
	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)
	parts["body"] = body
	parts["legs"] = []
	parts["arms"] = []
	parts["wheels"] = []
	parts["horse_legs"] = []
	parts["wheel_radius"] = 0.35
	parts["aim_y"] = 0.9
	var col := def.placeholder_color
	var acc := def.placeholder_accent
	var gear := def.placeholder_gear
	match def.placeholder_shape:
		"person_lying":
			_lying(body, col, acc, gear, parts)
		"box":
			_box_vehicle(body, col, acc, gear, parts)
		"capsule":
			_mesh(body, _capsule(0.3, 1.5), _mat(col), Vector3(0, 0.75, 0))
			parts["aim_y"] = 0.75
		"sphere":
			_mesh(body, _sphere(0.5), _mat(col), Vector3(0, 0.5, 0))
			parts["aim_y"] = 0.5
		_:
			_person_with_gear(body, col, acc, gear, parts)

	var aabb := _tree_aabb(body, Transform3D.IDENTITY)
	var natural := maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	var k := def.effective_size() / maxf(natural, 0.05)
	root.scale = Vector3.ONE * k
	parts["aim_y"] = float(parts["aim_y"]) * k
	return root


# --- Persons ---------------------------------------------------------------------------------

## A standing / seated person, feet at y0.
static func _person(parent: Node3D, col: Color, acc: Color, parts: Dictionary, y0 := 0.0,
		seated := false) -> void:
	var jacket := _mat(col)
	var skin := _mat(acc)
	var shorts := _mat(col.darkened(0.6))
	var torso := _mesh(parent, _capsule(0.17, 0.65), jacket, Vector3(0, y0 + 1.15, 0))
	torso.rotation.x = deg_to_rad(-8.0)  # leaning forward
	_mesh(parent, _sphere(0.12), skin, Vector3(0, y0 + 1.62, -0.04))
	for side in [-1.0, 1.0]:
		var leg := _limb(parent, Vector3(side * 0.09, y0 + 0.85, 0), 0.085, 0.8, shorts)
		if seated:
			leg.rotation.x = -1.1
		parts["legs"].append(leg)
		parts["arms"].append(_limb(parent, Vector3(side * 0.24, y0 + 1.38, 0), 0.06, 0.55, jacket))
	parts["aim_y"] = y0 + 1.15
	parts["seated"] = seated


static func _person_with_gear(parent: Node3D, col: Color, acc: Color, gear: String, parts: Dictionary) -> void:
	var dark := _mat(Color(0.1, 0.1, 0.12))
	var gear_mat := _mat(acc.darkened(0.2))
	match gear:
		"skis":
			for side in [-1.0, 1.0]:
				_mesh(parent, _box(0.12, 0.04, 1.8), dark, Vector3(side * 0.2, 0.03, 0))
			_person(parent, col, acc, parts, 0.05)
		"snowboard":
			_mesh(parent, _box(0.3, 0.04, 1.55), gear_mat, Vector3(0, 0.03, 0))
			_person(parent, col, acc, parts, 0.05)
		"skates":
			for side in [-1.0, 1.0]:
				_mesh(parent, _box(0.05, 0.1, 0.32), dark, Vector3(side * 0.1, 0.05, 0))
			_person(parent, col, acc, parts, 0.1)
		"wheels":
			for side in [-1.0, 1.0]:
				for z in [-0.12, 0.12]:
					_wheel(parent, Vector3(side * 0.1, 0.05, z), 0.05, 0.03, dark, parts)
			_person(parent, col, acc, parts, 0.1)
		"skateboard":
			_mesh(parent, _box(0.22, 0.03, 0.8), gear_mat, Vector3(0, 0.1, 0))
			for side in [-1.0, 1.0]:
				for z in [-0.3, 0.3]:
					_wheel(parent, Vector3(side * 0.1, 0.04, z), 0.04, 0.04, dark, parts)
			_person(parent, col, acc, parts, 0.12)
		"wakeboard":
			_mesh(parent, _box(0.32, 0.03, 1.4), gear_mat, Vector3(0, 0.03, 0))
			_person(parent, col, acc, parts, 0.05)
		"surfboard":
			_mesh(parent, _box(0.5, 0.07, 1.9), gear_mat, Vector3(0, 0.04, 0))
			_person(parent, col, acc, parts, 0.08)
		"sup":
			_mesh(parent, _box(0.8, 0.12, 3.0), gear_mat, Vector3(0, 0.06, 0))
			_person(parent, col, acc, parts, 0.12)
			var paddle := _mesh(parent, _box(0.05, 0.05, 2.0), dark, Vector3(0.3, 1.0, 0))
			paddle.rotation.x = deg_to_rad(25.0)
			parts["paddle"] = paddle
		"scooter":
			_mesh(parent, _box(0.18, 0.05, 0.9), gear_mat, Vector3(0, 0.12, 0))
			_wheel(parent, Vector3(0, 0.1, -0.4), 0.1, 0.04, dark, parts)
			_wheel(parent, Vector3(0, 0.1, 0.4), 0.1, 0.04, dark, parts)
			_mesh(parent, _box(0.04, 1.0, 0.04), dark, Vector3(0, 0.62, -0.38))
			_person(parent, col, acc, parts, 0.15)
		"bike":
			_bike(parent, col, acc, parts, 0.34, 0.55, false)
		"moto":
			_bike(parent, col, acc, parts, 0.35, 0.7, true)
		"horse":
			_horse(parent, col, acc, parts)
		"kart":
			_mesh(parent, _box(1.0, 0.18, 1.8), _mat(col), Vector3(0, 0.25, 0))
			for side in [-1.0, 1.0]:
				for z in [-0.65, 0.65]:
					_wheel(parent, Vector3(side * 0.55, 0.14, z), 0.14, 0.15, dark, parts)
			_person(parent, col, acc, parts, 0.15, true)
		"kayak":
			_mesh(parent, _box(0.55, 0.25, 3.5), _mat(col), Vector3(0, 0.12, 0))
			_person(parent, col, acc, parts, 0.12, true)
			var paddle := _mesh(parent, _box(2.2, 0.04, 0.12), dark, Vector3(0, 0.95, -0.2))
			parts["paddle"] = paddle
		"scull":
			_mesh(parent, _box(0.35, 0.18, 8.0), _mat(col), Vector3(0, 0.09, 0))
			_person(parent, col, acc, parts, 0.12, true)
			var oars := _mesh(parent, _box(4.2, 0.03, 0.08), dark, Vector3(0, 0.5, 0))
			parts["paddle"] = oars
		"sail":
			_mesh(parent, _box(0.9, 0.35, 4.5), _mat(col), Vector3(0, 0.17, 0))
			_mesh(parent, _cylinder(0.04, 6.0), dark, Vector3(0, 3.2, -0.3))
			_mesh(parent, _box(0.04, 4.5, 2.8), _mat(Color(0.95, 0.95, 0.92)), Vector3(0, 3.0, 1.1))
			_person(parent, col, acc, parts, 0.2, true)
			parts["aim_y"] = 1.4
		"canopy":
			_person(parent, col, acc, parts, 0.0, true)
			_mesh(parent, _box(10.0, 0.12, 3.2), _mat(acc), Vector3(0, 5.2, -0.3))
			for side in [-1.0, 1.0]:
				var line := _mesh(parent, _box(0.015, 4.6, 0.015), dark, Vector3(side * 1.25, 3.3, -0.15))
				line.rotation.z = side * deg_to_rad(33.0)
		_:
			_person(parent, col, acc, parts)


static func _lying(parent: Node3D, col: Color, acc: Color, gear: String, parts: Dictionary) -> void:
	var dark := _mat(Color(0.1, 0.1, 0.12))
	var pivot := Node3D.new()
	parent.add_child(pivot)
	var sub := {"legs": [], "arms": [], "aim_y": 0.0, "seated": false}
	_person(pivot, col, acc, sub)
	pivot.rotation.x = deg_to_rad(90.0 if gear == "sled" else -90.0)
	pivot.position.y = 0.22
	parts["legs"] = sub["legs"]
	parts["arms"] = sub["arms"]
	parts["aim_y"] = 0.3
	if gear == "sled":
		for side in [-1.0, 1.0]:
			_mesh(parent, _box(0.05, 0.06, 1.7), dark, Vector3(side * 0.2, 0.03, 0))
		_mesh(parent, _box(0.5, 0.04, 1.5), _mat(acc.darkened(0.2)), Vector3(0, 0.08, 0))
	elif gear == "wings":
		_mesh(parent, _box(3.0, 0.05, 1.5), _mat(acc), Vector3(0, 0.22, 0))


# --- Vehicles and mounts ----------------------------------------------------------------------

static func _box_vehicle(parent: Node3D, col: Color, acc: Color, gear: String, parts: Dictionary) -> void:
	if gear == "car":
		for w in CarModel.build(parent, col, 0):
			parts["wheels"].append(w)
		parts["wheel_radius"] = 0.33
		parts["aim_y"] = 0.9
	else:
		_mesh(parent, _box(1.0, 0.8, 2.0), _mat(col, 0.35), Vector3(0, 0.5, 0))
		_mesh(parent, _box(0.8, 0.3, 0.9), _mat(acc), Vector3(0, 1.05, 0.2))
		parts["aim_y"] = 0.7


static func _bike(parent: Node3D, col: Color, acc: Color, parts: Dictionary, r: float, half: float,
		motor: bool) -> void:
	var dark := _mat(Color(0.08, 0.08, 0.09))
	var frame := _mat(acc.darkened(0.1))
	_wheel(parent, Vector3(0, r, -half), r, 0.1 if not motor else 0.14, dark, parts)
	_wheel(parent, Vector3(0, r, half), r, 0.1 if not motor else 0.14, dark, parts)
	if motor:
		_mesh(parent, _box(0.25, 0.45, 1.2), frame, Vector3(0, r + 0.25, 0.05))
		_mesh(parent, _box(0.3, 0.2, 0.5), _mat(col), Vector3(0, r + 0.55, -0.25))
	else:
		_mesh(parent, _box(0.04, 0.04, half * 1.5), frame, Vector3(0, r + 0.2, 0))
		_mesh(parent, _box(0.04, 0.5, 0.04), frame, Vector3(0, r + 0.2, 0.2))
	_mesh(parent, _box(0.5, 0.03, 0.03), dark, Vector3(0, r + 0.7, -half * 0.8))  # handlebar
	_person(parent, col, acc, parts, r + 0.1 if not motor else r + 0.3, true)


static func _horse(parent: Node3D, col: Color, acc: Color, parts: Dictionary) -> void:
	var brown := _mat(Color(0.42, 0.27, 0.16))
	var dark := _mat(Color(0.2, 0.13, 0.08))
	var body := _mesh(parent, _capsule(0.3, 1.6), brown, Vector3(0, 1.0, 0))
	body.rotation.x = PI * 0.5
	var neck := _mesh(parent, _capsule(0.13, 0.75), brown, Vector3(0, 1.4, -0.85))
	neck.rotation.x = -0.7
	var head := _mesh(parent, _capsule(0.1, 0.5), brown, Vector3(0, 1.6, -1.2))
	head.rotation.x = -1.15
	var tail := _mesh(parent, _capsule(0.05, 0.6), dark, Vector3(0, 1.05, 0.95))
	tail.rotation.x = 0.7
	for z in [-0.6, 0.6]:
		for side in [-1.0, 1.0]:
			parts["horse_legs"].append(_limb(parent, Vector3(side * 0.16, 0.95, z), 0.06, 0.9, dark))
	_person(parent, col, acc, parts, 1.0, true)


# --- Primitive helpers ---------------------------------------------------------------------------

static func _mat(c: Color, rough := 0.8) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


static func _box(x: float, y: float, z: float) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3(x, y, z)
	return b


static func _capsule(radius: float, height: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = radius
	c.height = maxf(height, radius * 2.0)
	return c


static func _sphere(radius: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	return s


static func _cylinder(radius: float, height: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = 10
	return c


static func _mesh(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


## A limb hanging from a pivot at `pos` (rotating the pivot swings it).
static func _limb(parent: Node3D, pos: Vector3, radius: float, length: float, mat: Material) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = pos
	parent.add_child(pivot)
	_mesh(pivot, _capsule(radius, length), mat, Vector3(0, -length * 0.5, 0))
	return pivot


## A wheel with its axle along X; animations spin it with rotation = (spin, 0, PI/2).
static func _wheel(parent: Node3D, pos: Vector3, radius: float, width: float, mat: Material,
		parts: Dictionary) -> MeshInstance3D:
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = width
	cyl.radial_segments = 12
	var w := _mesh(parent, cyl, mat, pos)
	w.rotation = Vector3(0.0, 0.0, PI * 0.5)
	parts["wheels"].append(w)
	parts["wheel_radius"] = radius
	return w


static func _tree_aabb(node: Node3D, xf: Transform3D) -> AABB:
	var out := AABB()
	var first := true
	for c in node.get_children():
		if not c is Node3D:
			continue
		var t: Transform3D = xf * (c as Node3D).transform
		var box := AABB(t.origin, Vector3.ZERO)
		if c is MeshInstance3D and (c as MeshInstance3D).mesh:
			box = t * (c as MeshInstance3D).mesh.get_aabb()
		var sub := _tree_aabb(c as Node3D, t)
		if sub.size != Vector3.ZERO or sub.position != Vector3.ZERO:
			box = box.merge(sub)
		out = box if first else out.merge(box)
		first = false
	return out

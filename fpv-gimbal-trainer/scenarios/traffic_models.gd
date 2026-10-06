class_name TrafficModels
extends RefCounted
## Placeholder models (primitives only) of the road traffic: car, van, semi-trailer truck, cyclist.
## Every model looks along -Z (its front), stands on y = 0, and is returned with its size:
## {"node": Node3D, "half_len", "half_width", "height"}.

const CAR_COLORS := [Color(0.85, 0.85, 0.87), Color(0.1, 0.1, 0.12), Color(0.6, 0.62, 0.66), Color(0.15, 0.25, 0.55),
		Color(0.55, 0.1, 0.1), Color(0.9, 0.9, 0.9), Color(0.2, 0.4, 0.3), Color(0.8, 0.7, 0.2)]
const TRUCK_COLORS := [Color(0.9, 0.9, 0.9), Color(0.15, 0.3, 0.6), Color(0.75, 0.1, 0.1), Color(0.8, 0.8, 0.82),
		Color(0.2, 0.5, 0.25)]

static var _mats := {}


static func _mat(c: Color, rough := 0.6) -> StandardMaterial3D:
	var key := "%s/%s" % [c.to_html(), rough]
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = rough
		_mats[key] = m
	return _mats[key]


static func _box(parent: Node3D, size: Vector3, pos: Vector3, c: Color, rough := 0.6) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = _mat(c, rough)
	mi.position = pos
	parent.add_child(mi)
	return mi


static func _wheel(parent: Node3D, pos: Vector3, radius: float, width: float) -> void:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = width
	cyl.radial_segments = 10
	mi.mesh = cyl
	mi.material_override = _mat(Color(0.05, 0.05, 0.05), 0.9)
	mi.position = pos
	mi.rotation.z = PI * 0.5
	parent.add_child(mi)


static func car(rng: RandomNumberGenerator) -> Dictionary:
	var root := Node3D.new()
	var col: Color = CAR_COLORS[rng.randi() % CAR_COLORS.size()]
	_box(root, Vector3(1.75, 0.6, 4.2), Vector3(0, 0.65, 0), col, 0.35)
	_box(root, Vector3(1.5, 0.5, 2.0), Vector3(0, 1.17, 0.25), Color(0.08, 0.1, 0.14), 0.15)
	_box(root, Vector3(1.6, 0.06, 1.1), Vector3(0, 1.44, 0.25), col, 0.35)
	for wx in [-0.9, 0.9]:
		for wz in [-1.3, 1.3]:
			_wheel(root, Vector3(wx, 0.32, wz), 0.32, 0.22)
	return {"node": root, "half_len": 2.1, "half_width": 0.9, "height": 1.5}


static func van(rng: RandomNumberGenerator) -> Dictionary:
	var root := Node3D.new()
	var col: Color = Color(0.92, 0.92, 0.92) if rng.randf() < 0.7 else CAR_COLORS[rng.randi() % CAR_COLORS.size()]
	_box(root, Vector3(1.9, 1.9, 4.9), Vector3(0, 1.2, 0), col, 0.45)
	_box(root, Vector3(1.75, 0.6, 0.08), Vector3(0, 1.75, -2.46), Color(0.08, 0.1, 0.14), 0.15)
	for wx in [-0.95, 0.95]:
		for wz in [-1.6, 1.5]:
			_wheel(root, Vector3(wx, 0.36, wz), 0.36, 0.24)
	return {"node": root, "half_len": 2.45, "half_width": 0.95, "height": 2.2}


## Semi-trailer: cab in front, long box trailer behind.
static func truck(rng: RandomNumberGenerator) -> Dictionary:
	var root := Node3D.new()
	var cab: Color = TRUCK_COLORS[rng.randi() % TRUCK_COLORS.size()]
	var trailer: Color = Color(0.92, 0.92, 0.92) if rng.randf() < 0.6 else TRUCK_COLORS[rng.randi() % TRUCK_COLORS.size()]
	_box(root, Vector3(2.4, 2.6, 2.3), Vector3(0, 1.9, -6.0), cab, 0.4)
	_box(root, Vector3(2.2, 0.9, 0.08), Vector3(0, 2.5, -7.18), Color(0.08, 0.1, 0.14), 0.15)
	_box(root, Vector3(2.5, 0.35, 12.0), Vector3(0, 0.75, 0.0), Color(0.15, 0.15, 0.16), 0.8)  # chassis
	_box(root, Vector3(2.5, 3.0, 11.8), Vector3(0, 2.6, 0.2), trailer, 0.55)
	for wx in [-1.1, 1.1]:
		for wz in [-6.0, 2.5, 3.8, 5.1]:
			_wheel(root, Vector3(wx, 0.5, wz), 0.5, 0.3)
	return {"node": root, "half_len": 7.2, "half_width": 1.25, "height": 4.1}


static func cyclist(rng: RandomNumberGenerator) -> Dictionary:
	var root := Node3D.new()
	var jersey := Color.from_hsv(rng.randf(), 0.75, 0.9)
	var dark := Color(0.08, 0.08, 0.09)
	for wz in [-0.55, 0.55]:
		var mi := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.34
		cyl.bottom_radius = 0.34
		cyl.height = 0.04
		cyl.radial_segments = 12
		mi.mesh = cyl
		mi.material_override = _mat(dark, 0.9)
		mi.position = Vector3(0, 0.34, wz)
		mi.rotation.z = PI * 0.5
		root.add_child(mi)
	_box(root, Vector3(0.04, 0.05, 1.0), Vector3(0, 0.62, 0.0), Color(0.7, 0.7, 0.72), 0.4)
	_box(root, Vector3(0.45, 0.03, 0.03), Vector3(0, 0.98, -0.5), dark)
	_box(root, Vector3(0.1, 0.1, 0.1), Vector3(0, 0.98, 0.4), dark)
	var torso := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.17
	cap.height = 0.7
	torso.mesh = cap
	torso.material_override = _mat(jersey, 0.7)
	torso.position = Vector3(0, 1.25, -0.1)
	torso.rotation.x = deg_to_rad(-55.0)
	root.add_child(torso)
	var head := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.12
	sph.height = 0.24
	head.mesh = sph
	head.material_override = _mat(Color(0.9, 0.9, 0.95), 0.5)
	head.position = Vector3(0, 1.5, -0.38)
	root.add_child(head)
	return {"node": root, "half_len": 0.9, "half_width": 0.3, "height": 1.7}

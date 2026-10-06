class_name PropFactory
extends RefCounted
## Shared scenery builders: trees (MultiMesh, so hundreds are cheap) and rocks.
## Tree layout (unscaled): trunk 0..2 m, then three cones of height 2.6 starting at 1.5, 3.0, 4.5 m.

const CONE_R := [1.9, 1.5, 1.0]
const TREE_HEIGHT := 7.1

static var _rock_mat: StandardMaterial3D


## Radius of a tree of scale 1 at height y above the ground (0 outside the tree).
static func tree_radius_at(y: float) -> float:
	if y < 0.0 or y > TREE_HEIGHT:
		return 0.0
	var r := 0.35 if y < 2.0 else 0.0
	for k in 3:
		var yb := 1.5 + 1.5 * k
		if y >= yb and y <= yb + 2.6:
			r = maxf(r, CONE_R[k] * (1.0 - (y - yb) / 2.6))
	return r


## Deciduous tree (plane tree): trunk to 4 m, round crown of radius 3 centred at 6 m (scale 1). Radius at height y.
const ROUND_CENTER := 6.0
const ROUND_R := 3.0
const ROUND_HEIGHT := 9.0


static func round_tree_radius_at(y: float) -> float:
	if y < 0.0 or y > ROUND_HEIGHT:
		return 0.0
	var r := 0.4 if y < 4.0 else 0.0
	var dy := y - ROUND_CENTER
	if absf(dy) < ROUND_R:
		r = maxf(r, sqrt(ROUND_R * ROUND_R - dy * dy))
	return r


## Deciduous trees (MultiMesh): grounds = base positions, scales = size factors.
static func build_round_trees(parent: Node3D, grounds: PackedVector3Array, scales: PackedFloat32Array,
		foliage := Color(0.2, 0.42, 0.12), seed_value := 1) -> void:
	var n := grounds.size()
	if n == 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.28
	trunk.bottom_radius = 0.4
	trunk.height = 5.0
	trunk.radial_segments = 6
	var crown := SphereMesh.new()
	crown.radius = ROUND_R
	crown.height = ROUND_R * 1.7
	crown.radial_segments = 9
	crown.rings = 5
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.9
	for layer in [{"mesh": trunk, "y": 2.5, "trunk": true}, {"mesh": crown, "y": ROUND_CENTER, "trunk": false}]:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = layer.mesh
		mm.instance_count = n
		for i in n:
			var s := scales[i]
			var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s)
			mm.set_instance_transform(i, Transform3D(basis, grounds[i] + Vector3(0, float(layer.y) * s, 0)))
			var col := Color(0.32, 0.25, 0.18) if layer.trunk else foliage * rng.randf_range(0.8, 1.2)
			mm.set_instance_color(i, Color(col.r, col.g, col.b, 1.0))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mat
		parent.add_child(mmi)


static func build_forest(parent: Node3D, grounds: PackedVector3Array, scales: PackedFloat32Array,
		foliage := Color(0.08, 0.3, 0.14), seed_value := 1) -> void:
	var n := grounds.size()
	if n == 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var rots := PackedFloat32Array()
	var tints := PackedFloat32Array()
	for i in n:
		rots.append(rng.randf() * TAU)
		tints.append(rng.randf_range(0.75, 1.25))

	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.25
	trunk.bottom_radius = 0.35
	trunk.height = 2.0
	trunk.radial_segments = 6
	var layers: Array[Dictionary] = [{"mesh": trunk, "y": 1.0, "trunk": true}]
	for k in 3:
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = CONE_R[k]
		cone.height = 2.6
		cone.radial_segments = 7
		layers.append({"mesh": cone, "y": 2.8 + 1.5 * k, "trunk": false})

	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.9
	for layer in layers:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = layer.mesh
		mm.instance_count = n
		for i in n:
			var s := scales[i]
			var basis := Basis(Vector3.UP, rots[i]).scaled(Vector3.ONE * s)
			mm.set_instance_transform(i, Transform3D(basis, grounds[i] + Vector3(0, layer.y * s, 0)))
			var col := Color(0.35, 0.22, 0.12) if layer.trunk else foliage * tints[i]
			mm.set_instance_color(i, Color(col.r, col.g, col.b, 1.0))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mat
		parent.add_child(mmi)


static func add_rock(parent: Node3D, ground: Vector3, size: Vector3) -> MeshInstance3D:
	if _rock_mat == null:
		_rock_mat = StandardMaterial3D.new()
		_rock_mat.albedo_color = Color(0.42, 0.42, 0.45)
		_rock_mat.roughness = 0.95
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 8
	sphere.rings = 4
	var mi := MeshInstance3D.new()
	mi.mesh = sphere
	mi.material_override = _rock_mat
	mi.position = ground + Vector3(0, size.y * 0.4, 0)
	mi.scale = size
	mi.rotation.y = ground.x * 0.37
	parent.add_child(mi)
	return mi


## An obstacle of the given kind ("rocks", "walls", "players", "clouds") for the lines of sight of
## the training sessions. `pos` is the ground position (the base of a cloud). Returns the
## occluders to register: [{pos, r, h}] (vertical cylinders).
static func add_occluder_prop(parent: Node3D, kind: String, pos: Vector3, yaw: float,
		rng: RandomNumberGenerator, sc := 1.0) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	match kind:
		"rocks":
			var size := Vector3(2.2, 2.2, 4.5) * sc
			add_rock(parent, pos, size)
			out.append({"pos": pos, "r": maxf(size.x, size.z) * 0.9, "h": size.y * 1.4})
		"walls":
			var mi := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(5.0, 2.6, 0.5) * sc
			mi.mesh = box
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.55, 0.55, 0.58)
			mat.roughness = 0.85
			mi.material_override = mat
			mi.position = pos + Vector3(0, 1.3 * sc, 0)
			mi.rotation.y = yaw
			parent.add_child(mi)
			out.append({"pos": pos, "r": 2.5 * sc, "h": 2.6 * sc})
		"players":
			var along := Vector3(sin(yaw), 0.0, cos(yaw))
			for k in [-1, 0, 1]:
				var pp: Vector3 = pos + along * (k * 1.2)
				var mi := MeshInstance3D.new()
				var cap := CapsuleMesh.new()
				cap.radius = 0.25
				cap.height = 1.8
				mi.mesh = cap
				var mat := StandardMaterial3D.new()
				mat.albedo_color = Color.from_hsv(rng.randf(), 0.7, 0.85)
				mi.material_override = mat
				mi.position = pp + Vector3(0, 0.9, 0)
				parent.add_child(mi)
				out.append({"pos": pp, "r": 0.5, "h": 1.85})
		"clouds":
			var r := rng.randf_range(9.0, 14.0) * sc
			var mi := MeshInstance3D.new()
			var sph := SphereMesh.new()
			sph.radius = r
			sph.height = r * 2.0
			mi.mesh = sph
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.97, 0.98, 1.0)
			mat.roughness = 1.0
			mi.material_override = mat
			mi.position = pos + Vector3(0, r, 0)
			mi.scale = Vector3(1.3, 0.8, 1.0)
			parent.add_child(mi)
			out.append({"pos": pos, "r": r * 1.1, "h": r * 1.8})
	return out
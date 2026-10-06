class_name WorldProps
extends RefCounted
## Spawns coloured primitives around the origin to give motion cues.


static func spawn(parent: Node3D, count: int, r_min: float, r_max: float, seed_value: int = 42,
		avoid_min: float = 0.0, avoid_max: float = 0.0) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var meshes: Array[Mesh] = [BoxMesh.new(), SphereMesh.new(), CylinderMesh.new(), CapsuleMesh.new()]
	for i in count:
		var dist := rng.randf_range(r_min, r_max)
		while avoid_max > avoid_min and dist > avoid_min and dist < avoid_max:
			dist = rng.randf_range(r_min, r_max)
		var mi := MeshInstance3D.new()
		mi.mesh = meshes[i % meshes.size()]
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color.from_hsv(rng.randf(), 0.55, 0.9)
		mi.material_override = mat
		var ang := TAU * i / count + rng.randf_range(-0.1, 0.1)
		var s := rng.randf_range(0.8, 2.4)
		mi.scale = Vector3(s, s * rng.randf_range(0.8, 2.5), s)
		mi.position = Vector3(cos(ang) * dist, mi.scale.y * 0.5, sin(ang) * dist)
		parent.add_child(mi)

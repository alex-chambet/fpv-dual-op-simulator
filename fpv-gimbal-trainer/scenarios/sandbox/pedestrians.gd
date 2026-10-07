class_name Pedestrians
extends Node3D
## Villagers of the sandbox: people walking up and down the pavements (legs and arms swinging, turning back at the
## end of the pavement) and small groups standing and chatting on the square.

const SKIN := [Color(0.95, 0.8, 0.68), Color(0.85, 0.66, 0.5), Color(0.6, 0.42, 0.3), Color(0.4, 0.28, 0.2)]
const HAIR := [Color(0.1, 0.07, 0.05), Color(0.3, 0.2, 0.1), Color(0.6, 0.45, 0.25), Color(0.75, 0.75, 0.75)]

class Walker:
	var node: Node3D
	var legs: Array = []
	var arms: Array = []
	var line := PackedVector3Array()
	var cum := PackedFloat32Array()
	var s := 0.0
	var dir := 1.0
	var speed := 1.3
	var phase := 0.0
	var idle := false
	var lateral := 0.0

var _walkers: Array[Walker] = []
var _rng := RandomNumberGenerator.new()
static var _mats := {}


func setup(world: SandboxWorld, walkers := 46) -> void:
	_rng.seed = SandboxWorld.SEED + 41
	var lines := world.sidewalks
	if not lines.is_empty():
		for i in walkers:
			var w := Walker.new()
			w.line = lines[_rng.randi() % lines.size()]
			w.cum = PathUtil.cumulative(w.line)
			w.s = _rng.randf() * w.cum[w.cum.size() - 1]
			w.dir = 1.0 if _rng.randf() < 0.5 else -1.0
			w.speed = _rng.randf_range(1.0, 1.6)
			w.lateral = _rng.randf_range(-0.4, 0.4)
			w.phase = _rng.randf() * TAU
			_build(w)
			_walkers.append(w)
	# groups on the square, facing each other
	var k := 0
	while k < world.square_spots.size():
		var c := world.square_spots[k]
		var n := _rng.randi_range(2, 3)
		for j in n:
			var w := Walker.new()
			w.idle = true
			w.phase = _rng.randf() * TAU
			_build(w)
			var a := TAU * j / n + _rng.randf_range(-0.3, 0.3)
			var p := c + Vector3(cos(a), 0, sin(a)) * 0.75
			w.node.position = p
			w.node.rotation.y = atan2(cos(a), sin(a))  # face the centre of the group
			_walkers.append(w)
		k += 2


func _mat(c: Color) -> StandardMaterial3D:
	var key := c.to_html()
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.85
		_mats[key] = m
	return _mats[key]


func _part(parent: Node3D, mesh: Mesh, col: Color, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(col)
	mi.position = pos
	parent.add_child(mi)
	return mi


func _capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	c.radial_segments = 8
	c.rings = 2
	return c


## A person 1.6 - 1.9 m tall: legs and arms on pivots (hips, shoulders) so they can swing.
func _build(w: Walker) -> void:
	var root := Node3D.new()
	var k := _rng.randf_range(0.9, 1.05)
	root.scale = Vector3.ONE * k
	var top := Color.from_hsv(_rng.randf(), _rng.randf_range(0.2, 0.8), _rng.randf_range(0.3, 0.95))
	var trousers: Color = [Color(0.15, 0.2, 0.35), Color(0.12, 0.12, 0.13), Color(0.45, 0.4, 0.32), Color(0.3, 0.32, 0.35)][_rng.randi() % 4]
	var skin: Color = SKIN[_rng.randi() % SKIN.size()]
	var hair: Color = HAIR[_rng.randi() % HAIR.size()]
	_part(root, _capsule(0.19, 0.68), top, Vector3(0, 1.25, 0))
	var head := SphereMesh.new()
	head.radius = 0.11
	head.height = 0.24
	_part(root, head, skin, Vector3(0, 1.72, 0))
	var cap := SphereMesh.new()
	cap.radius = 0.115
	cap.height = 0.14
	cap.is_hemisphere = true
	_part(root, cap, hair, Vector3(0, 1.75, 0.01))
	for side in [-1.0, 1.0]:
		var hip := Node3D.new()
		hip.position = Vector3(side * 0.09, 0.92, 0)
		root.add_child(hip)
		_part(hip, _capsule(0.075, 0.9), trousers, Vector3(0, -0.45, 0))
		w.legs.append(hip)
		var shoulder := Node3D.new()
		shoulder.position = Vector3(side * 0.24, 1.48, 0)
		root.add_child(shoulder)
		_part(shoulder, _capsule(0.055, 0.62), top, Vector3(0, -0.3, 0))
		_part(shoulder, _capsule(0.045, 0.12), skin, Vector3(0, -0.64, 0))
		w.arms.append(shoulder)
	add_child(root)
	w.node = root


func _process(delta: float) -> void:
	for w in _walkers:
		if w.idle:
			w.phase += delta * 0.8
			for i in 2:
				w.arms[i].rotation.x = 0.06 * sin(w.phase + i)
			w.node.rotation.z = 0.015 * sin(w.phase * 0.7)
			continue
		var total: float = w.cum[w.cum.size() - 1]
		w.s += w.dir * w.speed * delta
		if w.s > total - 0.5 or w.s < 0.5:
			w.dir = -w.dir  # end of the pavement: turn back
			w.s = clampf(w.s, 0.5, total - 0.5)
		var p := PathUtil.polyline_at(w.line, w.cum, w.s)
		var q := PathUtil.polyline_at(w.line, w.cum, clampf(w.s + w.dir * 0.8, 0.0, total))
		var f := q - p
		f.y = 0.0
		if f.length() > 0.001:
			f = f.normalized()
			var right := f.cross(Vector3.UP)
			w.node.position = p + right * w.lateral
			var want := atan2(-f.x, -f.z)
			w.node.rotation.y = lerp_angle(w.node.rotation.y, want, clampf(delta * 6.0, 0.0, 1.0))
		w.phase += delta * w.speed * 4.4
		var sw := sin(w.phase) * 0.45
		w.legs[0].rotation.x = sw
		w.legs[1].rotation.x = -sw
		w.arms[0].rotation.x = -sw * 0.7
		w.arms[1].rotation.x = sw * 0.7

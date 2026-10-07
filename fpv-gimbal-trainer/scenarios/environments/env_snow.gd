class_name EnvSnow
extends EnvironmentBuilder
## Snow slope (tag "neige"): an inclined plane going down along +Z with fine bumps, snow texture,
## trees on both sides, rocks, slalom gates along the path, obstacles on the line of sight.
## Environment parameters (env_overrides): "slope" (grade, default 0.3).

const LEGACY_LATERAL_OFFSET := 18.0
const LEGACY_DRONE_HEIGHT := 5.0
const LEGACY_EVENTS: Array[float] = [0.30, 0.58, 0.86]

var slope := 0.3

var _tree_pos := PackedVector3Array()
var _tree_scale := PackedFloat32Array()


func configure() -> void:
	slope = float(opt("slope", 0.3))
	Vegetation.snow_cover = 0.8


func base_height(x: float, z: float) -> float:
	return -z * slope + 0.7 * sin(x * 0.09 + 0.5) * sin(z * 0.06) + 0.4 * sin(x * 0.21) * cos(z * 0.13)


## The ski area: the slope goes on, snowy forests, high mountains all around.
func far_scenery() -> Dictionary:
	return {"ring_radius": 1500.0, "ring_cell": 30.0,
		"hills": {"height": 1400.0, "r0": 2500.0, "r1": 7000.0, "frequency": 0.0011, "snow_line": -150.0,
			"tree_line": -250.0, "forest": Color(0.07, 0.15, 0.09), "rock": Color(0.36, 0.35, 0.36)},
		"trees": {"kind": "conifer", "count": 1100, "r0": 130.0, "r1": 900.0, "colour": Color(0.08, 0.3, 0.14),
			"grove": 0.1}}

func occluder_kind() -> String:
	return "trees"


func build_terrain(path: PackedVector3Array, _plan: Dictionary) -> void:
	var b := PathUtil.bounds_xz(path)
	var x_half := maxf(120.0, maxf(absf(b.position.x), absf(b.end.x)) + 100.0)
	var z0 := b.position.y - 60.0
	var z1 := b.end.y + 80.0
	var mi := MeshInstance3D.new()
	mi.name = "Terrain"
	mi.mesh = TerrainBuilder.build(Callable(self, "base_height"), x_half, z0, z1, 4.0, 24.0)
	var mat := GroundMaterials.snow()
	mi.material_override = mat
	host.add_child(mi)
	# the groomed piste: a band along the skier's line
	terrain_rect = Rect2(-x_half, z0, 2.0 * x_half, z1 - z0)
	terrain_material = mat
	ground_mask = GroundMask.new()
	ground_mask.setup(terrain_rect, 0.6)
	ground_mask.add_band(RoadBuilder.sample_curve(host.make_curve(path), 3.0), 16.0, Color(0, 1, 0))
	host.add_child(ground_mask)
	ground_mask.bind(mat)


func populate(path: PackedVector3Array, drone: PackedVector3Array, _plan: Dictionary, legacy: bool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7 + host.world_seed
	var b := PathUtil.bounds_xz(path)
	var db := PathUtil.bounds_xz(drone)
	var left_min := maxf(26.0, maxf(-b.position.x, b.end.x) + 14.0)
	var right_min := maxf(46.0, db.end.x + 14.0)

	# Forest behind the subject (-X side) and behind the drone (+X side)
	for i in 80:
		var left := rng.randf() < 0.7
		var x := rng.randf_range(-maxf(105.0, left_min + 20.0), -left_min) if left \
				else rng.randf_range(right_min, maxf(105.0, right_min + 20.0))
		var z := rng.randf_range(b.position.y - 40.0, b.end.y + 60.0)
		_add_tree(Vector3(x, base_height(x, z), z), rng.randf_range(0.9, 1.6))

	# Decorative rocks
	for p in [Vector3(-30.0, 0, 90.0), Vector3(-24.0, 0, 250.0), Vector3(52.0, 0, 160.0)]:
		if p.z < b.end.y + 40.0:
			_add_rock(Vector3(p.x, base_height(p.x, p.z), p.z), Vector3(1.8, 1.4, 2.2))

	# Slalom gates at the extremes of the path
	if bool(params.get("gates", false)):
		var k := 0
		for i in range(1, path.size() - 1):
			if (path[i].x - path[i - 1].x) * (path[i + 1].x - path[i].x) < 0.0:
				var gx := path[i].x * 0.4
				_add_gate(Vector3(gx, base_height(gx, path[i].z), path[i].z), k % 2 == 0)
				k += 1

	# Forced occlusions on the drone -> subject line of sight
	if legacy:
		for e in LEGACY_EVENTS.size():
			var i := int(LEGACY_EVENTS[e] * (path.size() - 1))
			var s: Vector3 = path[i]
			var d: Vector3 = drone[i]
			var flat := Vector3(d.x - s.x, 0.0, 0.0)
			if e == 1:
				# One big rock close to the skier line
				var rp := s + flat * 0.35
				_add_rock(Vector3(rp.x, base_height(rp.x, rp.z), rp.z), Vector3(2.2, 2.2, 4.5))
			else:
				# Five trees across the line of sight
				for k in [-2, -1, 0, 1, 2]:
					var tp: Vector3 = s + flat * 0.5 + Vector3(rng.randf_range(-0.8, 0.8), 0.0, k * 2.4)
					_add_tree(Vector3(tp.x, base_height(tp.x, tp.z), tp.z), 1.5)
	else:
		var count := roundi(float(host.matrix.params.occlusion) * 4.0)
		var fr: Array = []
		for k in count:
			fr.append((k + 1.0) / (count + 1.0))
		host.add_los_occluders(fr)
	PropFactory.build_forest(host, _tree_pos, _tree_scale, Color(0.08, 0.3, 0.14), 11)
	_add_ski_area(path, drone, left_min)


## Piste furniture: marker poles along both edges of the groomed piste, orange safety nets here and there, and
## a chairlift beyond the trees of the subject's side. Nothing tall stands on a line of sight of the session.
func _add_ski_area(path: PackedVector3Array, drone: PackedVector3Array, left_min: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 980 + host.world_seed
	var los := PackedVector2Array()
	for i in range(0, mini(path.size(), drone.size()), 2):
		los.append(Vector2(path[i].x, path[i].z))
		los.append(Vector2(drone[i].x, drone[i].z))
	var dense := RoadBuilder.sample_curve(host.make_curve(path), 2.0)
	var cum := PathUtil.cumulative(dense)
	var total: float = cum[cum.size() - 1]
	var piste: Color = [Color(0.85, 0.12, 0.1), Color(0.12, 0.3, 0.85), Color(0.06, 0.06, 0.07)][rng.randi() % 3]
	var poles: Array[Transform3D] = []
	var nets := []
	var s := 10.0
	while s < total:
		var p := PathUtil.polyline_at(dense, cum, s)
		var t := PathUtil.polyline_at(dense, cum, minf(s + 2.0, total)) - PathUtil.polyline_at(dense, cum, maxf(s - 2.0, 0.0))
		t.y = 0.0
		var side := t.normalized().cross(Vector3.UP)
		for sd in [-1.0, 1.0]:
			var q: Vector3 = p + side * sd * 16.5
			if not _near(los, q.x, q.z, 1.5):
				poles.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(q.x, base_height(q.x, q.z), q.z)))
			if rng.randf() < 0.06:
				nets.append([q, t.normalized(), sd])
		s += 24.0
	_marker_poles(poles, piste)
	for n in nets:
		_safety_net(n[0], n[1], los)
	# chairlift: towers every 70 m along the slope, beyond the subject's side
	var x := -(left_min + 12.0)
	var b := PathUtil.bounds_xz(path)
	var towers := PackedVector3Array()
	var z := b.position.y - 30.0
	while z < b.end.y + 60.0:
		var g := Vector3(x, base_height(x, z), z)
		if not _near(los, g.x, g.z, 6.0):
			towers.append(g)
		z += 70.0
	_chairlift(towers)


func _near(los: PackedVector2Array, x: float, z: float, r: float) -> bool:
	var q := Vector2(x, z)
	for k in range(0, los.size(), 2):
		var a := los[k]
		var ab := los[k + 1] - a
		var l2 := ab.length_squared()
		var t := 0.0 if l2 < 0.0001 else clampf((q - a).dot(ab) / l2, 0.0, 1.0)
		if q.distance_squared_to(a + ab * t) < r * r:
			return true
	return false


func _marker_poles(xforms: Array[Transform3D], top: Color) -> void:
	for part in [[Color(0.08, 0.08, 0.08), 1.3, 0.65], [top, 0.5, 1.55]]:
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.035
		cyl.bottom_radius = 0.035
		cyl.height = part[1]
		cyl.radial_segments = 6
		cyl.material = PathSubject.make_mat(part[0], 0.6)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = cyl
		mm.instance_count = xforms.size()
		for i in xforms.size():
			mm.set_instance_transform(i, Transform3D(xforms[i].basis, xforms[i].origin + Vector3(0, float(part[2]), 0)))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		host.add_child(mmi)


## A 20 m orange safety net along the piste edge (a see-through mesh on poles).
func _safety_net(at: Vector3, dir: Vector3, los: PackedVector2Array) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 10
	var prev := Vector3.ZERO
	for k in n + 1:
		var p := at + dir * (-10.0 + 20.0 * k / n)
		var g := Vector3(p.x, base_height(p.x, p.z), p.z)
		if k > 0:
			if _near(los, (g.x + prev.x) * 0.5, (g.z + prev.z) * 0.5, 2.0):
				prev = g
				continue
			var u0 := (k - 1) * 2.0
			var u1 := k * 2.0
			for v in [[prev, Vector2(u0, 1.8)], [prev + Vector3(0, 1.8, 0), Vector2(u0, 0.0)], [g, Vector2(u1, 1.8)],
					[g, Vector2(u1, 1.8)], [prev + Vector3(0, 1.8, 0), Vector2(u0, 0.0)], [g + Vector3(0, 1.8, 0), Vector2(u1, 0.0)]]:
				st.set_normal(dir.cross(Vector3.UP))
				st.set_uv(v[1])
				st.add_vertex(v[0])
		prev = g
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _net_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	host.add_child(mi)


static var _net_mat: ShaderMaterial

static func _net_material() -> ShaderMaterial:
	if _net_mat == null:
		var sh := Shader.new()
		sh.code = """
shader_type spatial;
render_mode cull_disabled;
void fragment() {
	vec2 g = fract(UV * vec2(9.0, 10.0));
	float w = fwidth(UV.x * 9.0) * 0.8 + 0.035;
	float line = max(1.0 - smoothstep(0.0, w, min(g.x, 1.0 - g.x)), 1.0 - smoothstep(0.0, w, min(g.y, 1.0 - g.y)));
	float rim = 1.0 - smoothstep(0.0, 0.05, min(UV.y, 1.8 - UV.y));
	ALBEDO = vec3(1.0, 0.3, 0.02);
	ALPHA = max(line, rim);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 0.8;
}
"""
		_net_mat = ShaderMaterial.new()
		_net_mat.shader = sh
	return _net_mat


## Chairlift: grey towers with a cross-beam, two cables, chairs hanging every 18 m.
func _chairlift(towers: PackedVector3Array) -> void:
	if towers.size() < 2:
		return
	var steel := PathSubject.make_mat(Color(0.55, 0.57, 0.6), 0.5)
	steel.metallic = 0.6
	for g in towers:
		var mast := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.25
		cyl.bottom_radius = 0.35
		cyl.height = 10.0
		cyl.radial_segments = 8
		mast.mesh = cyl
		mast.material_override = steel
		mast.position = g + Vector3(0, 5.0, 0)
		host.add_child(mast)
		var beam := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(4.6, 0.3, 0.3)
		beam.mesh = bm
		beam.material_override = steel
		beam.position = g + Vector3(0, 10.0, 0)
		host.add_child(beam)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var chairs: Array[Transform3D] = []
	for i in towers.size() - 1:
		for side in [-2.1, 2.1]:
			var a := towers[i] + Vector3(side, 9.8, 0)
			var b := towers[i + 1] + Vector3(side, 9.8, 0)
			var prev := a
			for k in range(1, 9):
				var t := k / 8.0
				var p := a.lerp(b, t) - Vector3(0, 0.8 * 4.0 * t * (1.0 - t), 0)
				Buildings._wire(st, prev, p, 0.03)
				prev = p
			var d := a.distance_to(b)
			var c := 9.0 if side < 0.0 else 0.0
			while c < d:
				var t2 := c / d
				var p2 := a.lerp(b, t2) - Vector3(0, 0.8 * 4.0 * t2 * (1.0 - t2), 0)
				chairs.append(Transform3D(Basis(), p2))
				c += 18.0
	var cables := MeshInstance3D.new()
	cables.mesh = st.commit()
	cables.material_override = PathSubject.make_mat(Color(0.15, 0.15, 0.16), 0.5)
	cables.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	host.add_child(cables)
	# chair: a hanger and a seat with a back rest, as one small mesh
	var cst := SurfaceTool.new()
	cst.begin(Mesh.PRIMITIVE_TRIANGLES)
	for box in [[Vector3(0, -0.95, 0), Vector3(0.05, 1.9, 0.05)], [Vector3(0, -2.0, 0.15), Vector3(1.4, 0.08, 0.5)],
			[Vector3(0, -1.7, 0.4), Vector3(1.4, 0.55, 0.08)]]:
		var bmesh := BoxMesh.new()
		bmesh.size = box[1]
		cst.append_from(bmesh, 0, Transform3D(Basis(), box[0]))
	var chair_mesh := cst.commit()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = chair_mesh
	mm.instance_count = chairs.size()
	for i in chairs.size():
		mm.set_instance_transform(i, chairs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = PathSubject.make_mat(Color(0.2, 0.22, 0.25), 0.6)
	host.add_child(mmi)


## Scripted drone path of the fixed scenario: the slalom averaged over one period (nearly
## straight), shifted sideways.
func legacy_drone_path(path: PackedVector3Array) -> PackedVector3Array:
	var xfun: Callable = arch.lateral_fn(params, path)
	var period := 200.0 / float(params.turn_frequency)
	var out := PackedVector3Array()
	for p in path:
		var avg := 0.0
		for k in 15:
			avg += float(xfun.call(p.z - period * 0.5 + period * k / 14.0))
		avg /= 15.0
		var dx := avg + LEGACY_LATERAL_OFFSET
		out.append(Vector3(dx, base_height(dx, p.z) + LEGACY_DRONE_HEIGHT, p.z))
	return out


func legacy_drift() -> float:
	return 12.0


func legacy_drift_events() -> Array[float]:
	return LEGACY_EVENTS.duplicate()


# --- Props ------------------------------------------------------------------------------------

func _add_tree(ground_pos: Vector3, s: float) -> void:
	_tree_pos.append(ground_pos)
	_tree_scale.append(s)
	host.add_tree_occluder(ground_pos, s)


func _add_rock(ground_pos: Vector3, size: Vector3) -> void:
	PropFactory.add_rock(host, ground_pos, size)
	host.add_cylinder_occluder(ground_pos, maxf(size.x, size.z) * 0.9, size.y * 1.4)


func _add_gate(ground_pos: Vector3, red: bool) -> void:
	var pole := CylinderMesh.new()
	pole.top_radius = 0.04
	pole.bottom_radius = 0.04
	pole.height = 2.4
	pole.radial_segments = 5
	var mi := MeshInstance3D.new()
	mi.mesh = pole
	mi.material_override = PathSubject.make_mat(Color(0.9, 0.1, 0.1) if red else Color(0.1, 0.25, 0.9))
	mi.position = ground_pos + Vector3(0, 1.2, 0)
	host.add_child(mi)

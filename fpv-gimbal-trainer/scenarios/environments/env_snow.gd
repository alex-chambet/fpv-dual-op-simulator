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


func base_height(x: float, z: float) -> float:
	return -z * slope + 0.7 * sin(x * 0.09 + 0.5) * sin(z * 0.06) + 0.4 * sin(x * 0.21) * cos(z * 0.13)


func occluder_kind() -> String:
	return "trees"


func build_terrain(path: PackedVector3Array, _plan: Dictionary) -> void:
	var b := PathUtil.bounds_xz(path)
	var x_half := maxf(120.0, maxf(absf(b.position.x), absf(b.end.x)) + 100.0)
	var mi := MeshInstance3D.new()
	mi.name = "Terrain"
	mi.mesh = TerrainBuilder.build(Callable(self, "base_height"), x_half, b.position.y - 60.0,
			b.end.y + 80.0, 4.0, 24.0)
	mi.material_override = _make_material()
	host.add_child(mi)


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


## Snow: low-frequency tint + fine relief so the surface catches the light.
func _make_material() -> StandardMaterial3D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.02
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.78, 0.84, 0.95))
	ramp.set_color(1, Color(1.0, 1.0, 1.0))
	var tex := NoiseTexture2D.new()
	tex.noise = noise
	tex.color_ramp = ramp
	tex.seamless = true
	tex.width = 512
	tex.height = 512

	var bump_noise := FastNoiseLite.new()
	bump_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	bump_noise.frequency = 0.09
	bump_noise.fractal_octaves = 4
	var normal_tex := NoiseTexture2D.new()
	normal_tex.noise = bump_noise
	normal_tex.as_normal_map = true
	normal_tex.bump_strength = 6.0
	normal_tex.seamless = true
	normal_tex.width = 1024
	normal_tex.height = 1024

	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.normal_enabled = true
	mat.normal_texture = normal_tex
	mat.normal_scale = 0.7
	mat.roughness = 0.75
	mat.rim_enabled = true
	mat.rim = 0.25
	mat.rim_tint = 0.6
	mat.subsurf_scatter_enabled = true
	mat.subsurf_scatter_strength = 0.35
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat

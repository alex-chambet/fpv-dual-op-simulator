class_name EnvForest
extends EnvironmentBuilder
## Forest (tag "foret"): rolling forest floor, a dirt trail laid along the subject's path (the
## terrain is flattened under it) and dense woods. Trees stand clear of the trail and of the drone
## path; the trees between them hide the subject often and for short moments.
## Environment parameters (env_overrides): "trail_clearance", "drone_clearance", "background_trees".

const LEGACY_LATERAL_OFFSET := 13.0
const LEGACY_DRONE_HEIGHT := 3.3
const LEGACY_BAND_DENSITY := 0.12
const LEGACY_BACKGROUND_TREES := 1300

var trail_clearance := 2.3
var drone_clearance := 3.4

var _road: RoadBuilder
var _drone_road: RoadBuilder
var _los := PackedVector2Array()  # pairs (subject, drone) of points of the lines of sight
var _grounds := PackedVector3Array()
var _scales := PackedFloat32Array()
var _ground_params := {}


func configure() -> void:
	trail_clearance = float(opt("trail_clearance", 2.3))
	drone_clearance = float(opt("drone_clearance", 3.4))
	surface_offset = 0.07
	Rocks.moss_amount = 0.85


func base_height(x: float, z: float) -> float:
	return 0.05 * z + 1.0 * sin(x * 0.07) * sin(z * 0.05) + 0.5 * sin(x * 0.19 + z * 0.11)


func ground(x: float, z: float) -> float:
	if _road == null:
		return base_height(x, z)
	return _road.blend_height(x, z, base_height(x, z), 2.5, 7.0)


func grass_params() -> Dictionary:
	var p := _ground_params.duplicate()
	p.merge({"height": 0.3, "density": 0.45, "max_slope": 0.35})
	return p


## The forest goes on beyond the playing area (the fog hides what is further).
func far_scenery() -> Dictionary:
	return {"ring_radius": 700.0, "ring_cell": 20.0,
		"trees": {"kind": "conifer", "count": 2600, "r0": 60.0, "r1": 420.0, "colour": Color(0.06, 0.22, 0.1)}}

func occluder_kind() -> String:
	return "trees"


func build_terrain(path: PackedVector3Array, _plan: Dictionary) -> void:
	var dense := RoadBuilder.sample_curve(host.make_curve(path), 2.0)
	_road = RoadBuilder.new(dense)
	var b := PathUtil.bounds_xz(path)

	var z0 := b.position.y - 30.0
	var z1 := b.end.y + 40.0
	var mi := MeshInstance3D.new()
	mi.name = "Terrain"
	mi.mesh = TerrainBuilder.build(Callable(self, "ground"), 80.0, z0, z1, 2.5, 20.0)
	# forest floor: moss, needles, dead leaves, bare soil; rock on the steep banks
	_ground_params = {"grass_a": Color(0.12, 0.17, 0.06), "grass_b": Color(0.23, 0.27, 0.1),
			"dry": Color(0.36, 0.25, 0.14), "dry_amount": 0.75, "dirt": Color(0.26, 0.19, 0.12), "dirt_amount": 0.45,
			"fringe_color": Color(0.33, 0.24, 0.15), "rock_start": 0.38, "rock_end": 0.55, "normal_strength": 0.5}
	var mat := GroundMaterials.terrain(_ground_params)
	mi.material_override = mat
	host.add_child(mi)

	var dirt := MeshInstance3D.new()
	corridor_half_width = maxf(1.1, 0.6 * subject_size)
	dirt.mesh = RoadBuilder.build_ribbon(dense, corridor_half_width + 0.35, 0.07)
	dirt.material_override = GroundMaterials.trail({"half_width": corridor_half_width + 0.35})
	dirt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	host.add_child(dirt)
	terrain_rect = Rect2(-80.0, z0, 160.0, z1 - z0)
	terrain_material = mat
	ground_mask = GroundMask.new()
	ground_mask.setup(terrain_rect, 0.35)
	ground_mask.add_band(dense, corridor_half_width + 1.4, Color(0, 0, 1))
	ground_mask.add_band(dense, corridor_half_width, Color(1, 0, 1))
	host.add_child(ground_mask)
	ground_mask.bind(mat)


func legacy_drone_path(path: PackedVector3Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for p in path:
		var dx := p.x + LEGACY_LATERAL_OFFSET
		out.append(Vector3(dx, ground(dx, p.z) + LEGACY_DRONE_HEIGHT, p.z))
	return out


func legacy_drift() -> float:
	return 10.0


func populate(path: PackedVector3Array, drone: PackedVector3Array, _plan: Dictionary, legacy: bool) -> void:
	_drone_road = RoadBuilder.new(RoadBuilder.sample_curve(host.make_curve(drone), 2.0))
	# Generated sessions: the trees keep clear of the line of sight between the drone and the subject, so
	# the subject is only hidden where the session says so (reveal barriers, forced occlusions below).
	_los = PackedVector2Array()
	if not legacy:
		for i in range(0, path.size(), 4):
			_los.append(Vector2(path[i].x, path[i].z))
			_los.append(Vector2(drone[i].x, drone[i].z))
	var rng := RandomNumberGenerator.new()
	rng.seed = 21 + host.world_seed
	var b := PathUtil.bounds_xz(path)
	var z0 := b.position.y
	var z1 := b.end.y
	var xfun: Callable = arch.lateral_fn(params, path)

	if legacy:
		# Trees between the trail and the drone line: they hide the subject.
		var lat_min := trail_clearance + 0.4
		var lat_max := LEGACY_LATERAL_OFFSET - drone_clearance - 0.4
		for i in int((z1 - z0) * LEGACY_BAND_DENSITY):
			var z := rng.randf_range(z0, z1)
			var x := float(xfun.call(z)) + rng.randf_range(lat_min, lat_max)
			_add_tree(Vector3(x, ground(x, z), z), rng.randf_range(1.0, 1.8))

	# Background forest, kept clear of the trail and of the drone line.
	var wanted := LEGACY_BACKGROUND_TREES if legacy \
			else roundi(float(opt("background_trees", 250.0 + 700.0 * float(host.matrix.params.occlusion))))
	var placed := 0
	var attempts := 0
	while placed < wanted and attempts < wanted * 6:
		attempts += 1
		var x := rng.randf_range(-62.0, 62.0)
		var z := rng.randf_range(z0 - 25.0, z1 + 25.0)
		# The strip between the trail and the drone line is planted separately in the fixed scenario
		var side := x - float(xfun.call(z))
		if legacy and side > -trail_clearance and side < LEGACY_LATERAL_OFFSET + drone_clearance:
			continue
		if _road.nearest(x, z).x < trail_clearance or _drone_road.nearest(x, z).x < drone_clearance:
			continue
		if _near_los(x, z):
			continue
		_add_tree(Vector3(x, ground(x, z), z), rng.randf_range(1.0, 1.9))
		placed += 1
	if not legacy:
		# Outer forest: far from both the trail and the drone, so it adds depth without hiding the subject.
		var outer := 0
		var tries := 0
		while outer < 900 and tries < 6000:
			tries += 1
			var x := rng.randf_range(-70.0, 70.0)
			var z := rng.randf_range(z0 - 25.0, z1 + 25.0)
			if _road.nearest(x, z).x < 12.0 or _drone_road.nearest(x, z).x < 12.0 or _near_los(x, z):
				continue
			_add_tree(Vector3(x, ground(x, z), z), rng.randf_range(1.0, 1.9))
			outer += 1
	PropFactory.build_forest(host, _grounds, _scales, Color(0.06, 0.22, 0.1), 9)
	if not legacy:
		var count := roundi(float(host.matrix.params.occlusion) * 4.0)
		var fr: Array = []
		for k in count:
			fr.append((k + 1.0) / (count + 1.0))
		host.add_los_occluders(fr)
	_add_undergrowth(z0, z1)


## Forest floor: ferns, bushes, fallen logs, stumps and stones, clear of the trail, of the drone line and (for
## what is tall enough to hide the subject) of the lines of sight. Own random stream: the trees do not change.
func _add_undergrowth(z0: float, z1: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 900 + host.world_seed
	var amount := GraphicsSettings.detail_amount()
	var kinds := [["fern", 900, 1.4, false], ["bush", 160, 2.2, true], ["log", 22, 3.0, true], ["stump", 45, 1.8, true]]
	for spec in kinds:
		var kind: String = spec[0]
		var wanted := roundi(float(spec[1]) * (amount if kind == "fern" or kind == "bush" else 1.0))
		var clear: float = spec[2]
		var xforms: Array[Transform3D] = []
		var customs := PackedColorArray()
		var tries := 0
		while xforms.size() < wanted and tries < wanted * 5:
			tries += 1
			var x := rng.randf_range(-70.0, 70.0)
			var z := rng.randf_range(z0 - 20.0, z1 + 20.0)
			if _road.nearest(x, z).x < corridor_half_width + clear or _drone_road.nearest(x, z).x < 2.5:
				continue
			if (spec[3] and _near_los(x, z)) or near_drone_start(x, z):
				continue
			var g := Vector3(x, ground(x, z), z)
			var basis := Basis(Vector3.UP, rng.randf() * TAU)
			var tint := rng.randf_range(0.8, 1.2)
			match kind:
				"fern":
					basis = basis.scaled(Vector3.ONE * rng.randf_range(0.7, 1.3))
					customs.append(Color(0.2 * tint, 0.36 * tint, 0.1 * tint, rng.randf()))
				"bush":
					basis = basis.scaled(Vector3.ONE * rng.randf_range(0.7, 1.2))
					customs.append(Color(0.16 * tint, 0.3 * tint, 0.09 * tint, rng.randf()))
				"log":
					basis = basis * Basis(Vector3.BACK, PI * 0.5 + rng.randf_range(-0.06, 0.06))
					g.y += 0.18
					customs.append(Color(1, 1, 1, rng.randf()))
				_:
					customs.append(Color(1, 1, 1, rng.randf()))
			xforms.append(Transform3D(basis, g))
		Vegetation.place(host, kind, xforms, customs, rng, 90.0 if kind == "fern" else 160.0)
	var stones := PackedVector3Array()
	var sizes := PackedFloat32Array()
	for i in roundi(140 * amount):
		var x := rng.randf_range(-70.0, 70.0)
		var z := rng.randf_range(z0 - 20.0, z1 + 20.0)
		if _road.nearest(x, z).x < corridor_half_width + 0.6 or near_drone_start(x, z):
			continue
		stones.append(Vector3(x, ground(x, z), z))
		sizes.append(rng.randf_range(0.15, 0.5))
	Rocks.scatter(host, stones, sizes, 901 + host.world_seed)


## True if (x, z) is within 3.5 m of a line of sight (drone -> subject) of the session.
func _near_los(x: float, z: float) -> bool:
	var q := Vector2(x, z)
	for k in range(0, _los.size(), 2):
		var a := _los[k]
		var ab := _los[k + 1] - a
		var l2 := ab.length_squared()
		var t := 0.0 if l2 < 0.0001 else clampf((q - a).dot(ab) / l2, 0.0, 1.0)
		if q.distance_squared_to(a + ab * t) < 12.25:
			return true
	return false


func _add_tree(ground_pos: Vector3, s: float) -> void:
	_grounds.append(ground_pos)
	_scales.append(s)
	host.add_tree_occluder(ground_pos, s)


func hud_extra() -> String:
	return "Dense forest: the subject keeps disappearing behind trunks - anticipate."

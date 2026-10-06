class_name EnvGeneric
extends EnvironmentBuilder
## Generic environment: a simple ground (flat, rolling, slope, wall, ridge, river, mountains or
## water), optional court / pitch markings, a perimeter, and a few primitives (trees, rocks,
## boxes, buildings, stands, buoys, clouds). Everything comes from the EnvironmentStyle (.tres),
## so a new environment tag is a new style file - or, with no style at all, a plain ground.
## Environment parameters (env_overrides): terrain_kind, slope, bump, river_half_width.

var kind := "flat"
var slope := 0.0
var bump := 0.0
var river_half := 14.0

var _bounds := Rect2()   # playing area (zone or path bounds)


func configure() -> void:
	kind = str(opt("terrain_kind", style.terrain_kind))
	slope = float(opt("slope", style.slope))
	bump = float(opt("bump", style.bump))
	river_half = float(opt("river_half_width", style.river_half_width))


func occluder_kind() -> String:
	return style.occluder_kind


func base_height(x: float, z: float) -> float:
	match kind:
		"rolling":
			return bump * (sin(x * 0.05 + 1.0) * sin(z * 0.04) + 0.5 * sin(x * 0.11) * cos(z * 0.09)) - z * slope
		"slope":
			return -z * slope + bump * sin(x * 0.07) * sin(z * 0.05)
		"wall":
			return z * slope + bump * sin(x * 0.35) * sin(z * 0.3)
		"ridge":
			var cx := 3.0 * sin(z * 0.02)
			return 30.0 - 0.9 * absf(x - cx) + 0.25 * z + bump * sin(z * 0.2) * 0.3
		"river":
			var cx := 5.0 * sin(z * 0.021)
			var d := absf(x - cx)
			return -0.8 + maxf(0.0, d - (river_half - 2.2)) * 0.35 \
					+ bump * sin(x * 0.1) * sin(z * 0.08) * smoothstep(river_half, river_half + 6.0, d)
		"mountains":
			return bump * (sin(x * 0.004 + 1.0) * sin(z * 0.0035) + 0.5 * sin(x * 0.011) * cos(z * 0.009)
					+ 0.25 * sin(x * 0.027 + z * 0.021))
		_:
			return 0.0


func ground(x: float, z: float) -> float:
	var h := base_height(x, z)
	return maxf(h, style.water_level) if style.has_water else h


func build_terrain(path: PackedVector3Array, plan: Dictionary) -> void:
	_bounds = plan.zone if plan.has("zone") and plan.zone.has_area() else PathUtil.bounds_xz(path)
	var m := style.margin
	var x_half := maxf(absf(_bounds.position.x - m), absf(_bounds.end.x + m))
	var z0 := _bounds.position.y - m
	var z1 := _bounds.end.y + m
	if kind != "water":
		var span := maxf(x_half * 2.0, z1 - z0)
		var cell := style.cell if style.cell > 0.0 else clampf(span / 90.0, 2.0, 25.0)
		var mi := MeshInstance3D.new()
		mi.name = "Terrain"
		mi.mesh = TerrainBuilder.build(Callable(self, "base_height"), x_half, z0, z1, cell, 24.0)
		var mat := TerrainBuilder.make_material(style.ground_color_dark, style.ground_color_light,
				style.ground_relief, style.ground_texture_frequency)
		mat.roughness = style.ground_roughness
		mi.material_override = mat
		host.add_child(mi)
	if style.has_water:
		_add_water(x_half, z0, z1)
	if style.markings != "none":
		_add_markings(_bounds if plan.has("zone") and plan.zone.has_area() else _bounds.grow(10.0))
	if style.perimeter != "none":
		_add_perimeter(_bounds.grow(1.5) if plan.has("zone") and plan.zone.has_area() else _bounds.grow(style.margin * 0.5))


func populate(path: PackedVector3Array, drone: PackedVector3Array, plan: Dictionary, _legacy: bool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 31 + host.world_seed
	_scatter_props(path, drone, rng, plan)
	var count := roundi(float(host.matrix.params.occlusion) * 4.0)
	if count > 0:
		var fr: Array = []
		for k in count:
			fr.append((k + 1.0) / (count + 1.0))
		host.add_los_occluders(fr)


# --- Water ------------------------------------------------------------------------------------------

func _add_water(x_half: float, z0: float, z1: float) -> void:
	var big := kind == "water"
	var plane := PlaneMesh.new()
	plane.size = Vector2(3000.0, 3000.0) if big else Vector2(x_half * 2.0 + 20.0, (z1 - z0) + 20.0)
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.04
	var ntex := NoiseTexture2D.new()
	ntex.noise = noise
	ntex.as_normal_map = true
	ntex.bump_strength = 3.0
	ntex.seamless = true
	ntex.width = 512
	ntex.height = 512
	var mat := StandardMaterial3D.new()
	mat.albedo_color = style.water_color
	mat.roughness = 0.1
	mat.metallic = 0.1
	mat.normal_enabled = true
	mat.normal_texture = ntex
	mat.normal_scale = 0.4
	mat.uv1_scale = Vector3(120.0, 120.0, 1.0) if big else Vector3(maxf(x_half, 10.0) / 6.0, maxf(z1 - z0, 10.0) / 6.0, 1.0)
	var mi := MeshInstance3D.new()
	mi.name = "Water"
	mi.mesh = plane
	mi.material_override = mat
	mi.position = Vector3((0.0 if big else 0.0), style.water_level, (_bounds.get_center().y if big else (z0 + z1) * 0.5))
	host.add_child(mi)


# --- Markings and perimeter ---------------------------------------------------------------------------

func _add_markings(rect: Rect2) -> void:
	var lines: Array[PackedVector2Array] = []
	var c := rect.get_center()
	var w := rect.size.x
	var d := rect.size.y
	lines.append(_rect_poly(rect))
	match style.markings:
		"pitch":
			lines.append(PackedVector2Array([Vector2(rect.position.x, c.y), Vector2(rect.end.x, c.y)]))
			lines.append(_circle_poly(c, minf(w, d) * 0.12))
			for end_z in [rect.position.y, rect.end.y]:
				var dir := 1.0 if end_z == rect.position.y else -1.0
				lines.append(_rect_poly(Rect2(c.x - w * 0.2, minf(end_z, end_z + dir * d * 0.16), w * 0.4, d * 0.16)))
		"rink":
			lines.append(PackedVector2Array([Vector2(rect.position.x, c.y), Vector2(rect.end.x, c.y)]))
			for k in [1.0 / 3.0, 2.0 / 3.0]:
				lines.append(PackedVector2Array([Vector2(rect.position.x, rect.position.y + d * k),
						Vector2(rect.end.x, rect.position.y + d * k)]))
			lines.append(_circle_poly(c, minf(w, d) * 0.09))
			for fx in [-0.25, 0.25]:
				for fz in [0.2, 0.8]:
					lines.append(_circle_poly(Vector2(c.x + w * fx, rect.position.y + d * fz), minf(w, d) * 0.07))
		"tennis":
			lines.append(PackedVector2Array([Vector2(rect.position.x, c.y), Vector2(rect.end.x, c.y)]))
			for k in [0.25, 0.75]:
				lines.append(PackedVector2Array([Vector2(rect.position.x, rect.position.y + d * k),
						Vector2(rect.end.x, rect.position.y + d * k)]))
			lines.append(PackedVector2Array([Vector2(c.x, rect.position.y + d * 0.25), Vector2(c.x, rect.position.y + d * 0.75)]))
		"court":
			lines.append(PackedVector2Array([Vector2(rect.position.x, c.y), Vector2(rect.end.x, c.y)]))
			lines.append(_circle_poly(c, minf(w, d) * 0.12))
			for end_z in [rect.position.y, rect.end.y]:
				var dir := 1.0 if end_z == rect.position.y else -1.0
				lines.append(_rect_poly(Rect2(c.x - w * 0.18, minf(end_z, end_z + dir * d * 0.3), w * 0.36, d * 0.3)))
	var mat := PathSubject.make_mat(style.marking_color, 0.8)
	for poly in lines:
		var pts := PathUtil.lift(PathUtil.resample_2d(poly, 1.0), Callable(self, "ground"))
		if pts.size() < 2:
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = RoadBuilder.build_ribbon(pts, 0.07, 0.04)
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		host.add_child(mi)


func _rect_poly(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end,
			Vector2(r.position.x, r.end.y), r.position])


func _circle_poly(center: Vector2, radius: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in 33:
		var a := TAU * i / 32.0
		out.append(center + Vector2(cos(a), sin(a)) * radius)
	return out


func _add_perimeter(rect: Rect2) -> void:
	var h := 1.2 if style.perimeter == "boards" else (5.0 if style.perimeter == "walls" else 1.8)
	var col := Color(0.92, 0.92, 0.95) if style.perimeter == "boards" else style.prop_color
	var mat := PathSubject.make_mat(col, 0.7)
	var y := ground(rect.get_center().x, rect.get_center().y)
	var sides := [
		[Vector2(rect.get_center().x, rect.position.y), Vector2(rect.size.x, 0.4)],
		[Vector2(rect.get_center().x, rect.end.y), Vector2(rect.size.x, 0.4)],
		[Vector2(rect.position.x, rect.get_center().y), Vector2(0.4, rect.size.y)],
		[Vector2(rect.end.x, rect.get_center().y), Vector2(0.4, rect.size.y)],
	]
	for s in sides:
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		var size: Vector2 = s[1]
		if style.perimeter == "fence":
			box.size = Vector3(size.x, 0.12, size.y)
			mi.position = Vector3((s[0] as Vector2).x, y + h, (s[0] as Vector2).y)
		else:
			box.size = Vector3(size.x, h, size.y)
			mi.position = Vector3((s[0] as Vector2).x, y + h * 0.5, (s[0] as Vector2).y)
		mi.mesh = box
		mi.material_override = mat
		host.add_child(mi)
	if style.perimeter == "fence":
		var post := BoxMesh.new()
		post.size = Vector3(0.12, h, 0.12)
		var posts: Array[Transform3D] = []
		for poly in [_rect_poly(rect)]:
			for p in PathUtil.resample_2d(poly, 4.0):
				posts.append(Transform3D(Basis(), Vector3(p.x, y + h * 0.5, p.y)))
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = post
		mm.instance_count = posts.size()
		for i in posts.size():
			mm.set_instance_transform(i, posts[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mat
		host.add_child(mmi)


# --- Props ---------------------------------------------------------------------------------------------

func _scatter_props(path: PackedVector3Array, drone: PackedVector3Array, rng: RandomNumberGenerator,
		_plan: Dictionary) -> void:
	if style.prop_kind == "none" or style.prop_count <= 0:
		return
	if style.prop_kind == "stands":
		_add_stands(_bounds)
		return
	var b := _bounds
	var m := style.margin
	var x0 := b.position.x - m
	var x1 := b.end.x + m
	var z0 := b.position.y - m
	var z1 := b.end.y + m
	var sub_pts := _every(path, 8)
	var drone_pts := _every(drone, 8)
	var grounds := PackedVector3Array()
	var scales := PackedFloat32Array()
	var count := style.prop_count
	var placed := 0
	var tries := 0
	while placed < count and tries < count * 20:
		tries += 1
		var x := rng.randf_range(x0, x1)
		var z := rng.randf_range(z0, z1)
		if _near(sub_pts, x, z, 9.0) or _near(drone_pts, x, z, 7.0):
			continue
		if b.has_point(Vector2(x, z)) and style.markings != "none":
			continue  # keep the playing area clear
		var g := Vector3(x, ground(x, z), z)
		placed += 1
		match style.prop_kind:
			"trees":
				grounds.append(g)
				scales.append(rng.randf_range(0.9, 1.7))
				host.add_tree_occluder(g, scales[scales.size() - 1])
			"rocks":
				var size := Vector3(rng.randf_range(1.2, 3.0), rng.randf_range(1.0, 2.6), rng.randf_range(1.2, 3.2))
				PropFactory.add_rock(host, g, size)
				host.add_cylinder_occluder(g, maxf(size.x, size.z) * 0.9, size.y * 1.4)
			"boxes":
				var size := Vector3(rng.randf_range(1.0, 3.0), rng.randf_range(0.8, 2.4), rng.randf_range(1.0, 3.0))
				_box(g, size, Color.from_hsv(rng.randf(), 0.25, 0.7), rng.randf() * TAU)
				host.add_cylinder_occluder(g, maxf(size.x, size.z) * 0.75, size.y)
			"buildings":
				var size := Vector3(rng.randf_range(8.0, 20.0), rng.randf_range(8.0, 30.0), rng.randf_range(8.0, 20.0))
				var gg := Vector3(x, ground(x, z), z)
				if _near(sub_pts, x, z, 28.0):
					placed -= 1
					continue
				_box(gg, size, style.prop_color.lightened(rng.randf_range(-0.1, 0.25)), 0.0)
				host.add_cylinder_occluder(gg, maxf(size.x, size.z) * 0.6, size.y)
			"posts":
				var mi := MeshInstance3D.new()
				var cyl := CylinderMesh.new()
				cyl.top_radius = 0.1
				cyl.bottom_radius = 0.14
				cyl.height = 6.0
				cyl.radial_segments = 6
				mi.mesh = cyl
				mi.material_override = PathSubject.make_mat(style.prop_color, 0.6)
				mi.position = g + Vector3(0, 3.0, 0)
				host.add_child(mi)
			"buoys":
				if ground(x, z) > style.water_level + 0.2:
					placed -= 1
					continue
				var mi := MeshInstance3D.new()
				var sph := SphereMesh.new()
				sph.radius = 0.35
				sph.height = 0.7
				mi.mesh = sph
				mi.material_override = PathSubject.make_mat(style.prop_color, 0.5)
				mi.position = Vector3(x, style.water_level, z)
				host.add_child(mi)
			"clouds":
				# A cumulus is a cluster of overlapping flattened puffs.
				var yr := _path_y_range(path)
				var y := rng.randf_range(yr.x - 60.0, yr.y + 80.0)
				var base_r := rng.randf_range(12.0, 32.0)
				var cloud_mat := PathSubject.make_mat(Color(0.97, 0.98, 1.0), 1.0)
				for k in rng.randi_range(4, 7):
					var mi := MeshInstance3D.new()
					var sph := SphereMesh.new()
					var r := base_r * rng.randf_range(0.55, 1.0)
					sph.radius = r
					sph.height = r * 1.6
					sph.radial_segments = 20
					sph.rings = 10
					mi.mesh = sph
					mi.material_override = cloud_mat
					mi.position = Vector3(x, y, z) + Vector3(rng.randf_range(-1.7, 1.7) * base_r,
							rng.randf_range(-0.2, 0.45) * base_r, rng.randf_range(-1.0, 1.0) * base_r)
					mi.scale = Vector3(1.3, 0.8, 1.1)
					host.add_child(mi)
	if style.prop_kind == "trees":
		PropFactory.build_forest(host, grounds, scales, style.prop_color, 41)


func _every(pts: PackedVector3Array, step: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in range(0, pts.size(), step):
		out.append(pts[i])
	return out


func _near(pts: PackedVector3Array, x: float, z: float, dist: float) -> bool:
	var d2 := dist * dist
	for p in pts:
		var dx := p.x - x
		var dz := p.z - z
		if dx * dx + dz * dz < d2:
			return true
	return false


func _path_y_range(pts: PackedVector3Array) -> Vector2:
	var lo := INF
	var hi := -INF
	for p in pts:
		lo = minf(lo, p.y)
		hi = maxf(hi, p.y)
	return Vector2(lo, hi)


func _box(ground_pos: Vector3, size: Vector3, col: Color, yaw: float) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = PathSubject.make_mat(col, 0.8)
	mi.position = ground_pos + Vector3(0, size.y * 0.5, 0)
	mi.rotation.y = yaw
	host.add_child(mi)


## Tiered stands on the four sides of the playing area.
func _add_stands(rect: Rect2) -> void:
	var y := ground(rect.get_center().x, rect.get_center().y)
	var mat := PathSubject.make_mat(style.prop_color, 0.9)
	var sides := [
		[Vector2(rect.get_center().x, rect.position.y - 7.0), Vector2(rect.size.x + 20.0, 1.0)],
		[Vector2(rect.get_center().x, rect.end.y + 7.0), Vector2(rect.size.x + 20.0, 1.0)],
		[Vector2(rect.position.x - 7.0, rect.get_center().y), Vector2(1.0, rect.size.y + 20.0)],
		[Vector2(rect.end.x + 7.0, rect.get_center().y), Vector2(1.0, rect.size.y + 20.0)],
	]
	for s in sides:
		var c: Vector2 = s[0]
		var axis: Vector2 = s[1]
		var outward := Vector2(signf(c.x - rect.get_center().x), signf(c.y - rect.get_center().y))
		for tier in 3:
			var mi := MeshInstance3D.new()
			var box := BoxMesh.new()
			var depth := 3.0
			var h := 2.0 + tier * 2.0
			var size := Vector3(axis.x if axis.x > 1.5 else depth, h, axis.y if axis.y > 1.5 else depth)
			box.size = size
			mi.mesh = box
			mi.material_override = mat
			var off := Vector2(outward.x if axis.x <= 1.5 else 0.0, outward.y if axis.y <= 1.5 else 0.0) * (tier * depth)
			mi.position = Vector3(c.x + off.x, y + h * 0.5, c.y + off.y)
			host.add_child(mi)

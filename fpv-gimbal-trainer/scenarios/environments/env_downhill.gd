class_name EnvDownhill
extends EnvSnow
## Downhill race course (tag "descente"), in the spirit of the Streif (Kitzbühel) or of Bellevarde (Val d'Isère):
##  - a long mountainside whose grade changes by sections: glides (17-28 %), fast parts (33-44 %), steep walls
##    (46-62 %), and sharp crests where a glide ends on a steep wall: the jumps of the course (ArchetypeDescente
##    finds them and makes the skier fly over them);
##  - a wide groomed piste (36 to 60 m) cut through a snowy forest along the racing line, a little lower than the
##    forest on both sides;
##  - red downhill gates, red A-nets (4 m) on the outside of the turns and along the landings, orange B-nets
##    elsewhere, blue dye lines across the piste before the jumps;
##  - a chairlift alongside the piste and another one crossing high above it, the start house, the finish (red line,
##    arch, grandstand with spectators, advertising boards).
## Nothing is built in the drone's flight, and the forest keeps clear of the lines of sight of the session (only the
## obstacles of the session hide the subject).

const Z_MIN := -900.0
const Z_MAX := 5400.0
const FAR_GRADE := 0.35
const CELL := 25.0          # m, size of the cells of the spatial lookups (drone points, lines of sight)
const FOREST_END := 700.0   # m: the trees of the course are not drawn beyond (the far scenery has its own forest)

var crests := PackedFloat32Array()   ## z of the crests (the jumps)
var _h := PackedFloat32Array()       ## height of the fall line every metre from Z_MIN
var _xc := PackedFloat32Array()      ## x of the piste centre every metre from _c_z0
var _hw := PackedFloat32Array()      ## half width of the piste measured along x, every metre from _c_z0
var _c_z0 := 0.0
var _phase := 0.0
var _drone_cells := {}               ## cell -> PackedVector3Array of drone points
var _los_cells := {}                 ## cell -> PackedVector2Array of line-of-sight segments (pairs of points)
var _lift_lines := []                ## [Vector2, Vector2]: the forest keeps clear of the lift lines
## The lifts that were built ("alongside", "crossing"): a lift is left out when the drone flies near its cables.
var lifts_built: Array[String] = []
static var _net_mats := {}


func configure() -> void:
	Vegetation.snow_cover = 0.85
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150 + host.world_seed
	_phase = rng.randf() * TAU
	# Sections of the slope: [start z, grade, length of the transition from the previous grade]
	var sections := [[Z_MIN, 0.3, 0.0], [-70.0, 0.5, 30.0]]  # above the start, then the steep start ramp
	var z := 45.0
	var g := 0.5
	var since := 0.0
	var next_crest := rng.randf_range(250.0, 340.0)
	while z < Z_MAX:
		var length := rng.randf_range(110.0, 230.0)
		var tr := rng.randf_range(25.0, 45.0)
		var ng := 0.0
		if since >= next_crest and g <= 0.3:
			ng = rng.randf_range(0.52, 0.62)  # a glide ends on a steep wall: a crest
			tr = 4.0
			crests.append(z)
			since = 0.0
			next_crest = rng.randf_range(380.0, 540.0)
		elif since >= next_crest - 160.0 and g > 0.3:
			ng = rng.randf_range(0.17, 0.25)  # the glide before the next crest
			length = rng.randf_range(80.0, 120.0)
		else:
			var pick := rng.randf()
			if pick < 0.3:
				ng = rng.randf_range(0.16, 0.26)
			elif pick < 0.7:
				ng = rng.randf_range(0.3, 0.4)
			else:
				ng = rng.randf_range(0.45, 0.56)
		sections.append([z, ng, tr])
		since += length
		z += length
		g = ng
	var n := int(Z_MAX - Z_MIN) + 1
	var grade := PackedFloat32Array()
	grade.resize(n)
	var si := 0
	var prev_g: float = sections[0][1]
	for k in n:
		var zk := Z_MIN + k
		while si + 1 < sections.size() and zk >= float(sections[si + 1][0]):
			prev_g = float(sections[si][1])
			si += 1
		grade[k] = _grade_at_section(sections[si], prev_g, zk)
	_h.resize(n)
	_h[0] = 0.0
	for k in range(1, n):
		_h[k] = _h[k - 1] - 0.5 * (grade[k - 1] + grade[k])
	var h0 := _h[int(-Z_MIN)]
	for k in n:
		_h[k] -= h0


func _grade_at_section(sec: Array, prev_g: float, zk: float) -> float:
	var tr := float(sec[2])
	if tr <= 0.0:
		return float(sec[1])
	return lerpf(prev_g, float(sec[1]), smoothstep(0.0, 1.0, (zk - float(sec[0])) / tr))


## Height of the fall line (m) at z.
func fall_line(z: float) -> float:
	var f := z - Z_MIN
	if f <= 0.0:
		return _h[0] - f * 0.3
	var last := _h.size() - 1
	if f >= last:
		return _h[last] - (f - last) * FAR_GRADE
	var i := int(f)
	return lerpf(_h[i], _h[i + 1], f - i)


func base_height(x: float, z: float) -> float:
	return fall_line(z) + 0.05 * x * sin(z * 0.0017 + _phase) \
			+ 0.5 * sin(x * 0.045 + 1.0) * sin(z * 0.031) + 0.25 * sin(x * 0.11 - z * 0.07)


## The piste is groomed flat across; beyond its edges the forest floor rises a little and gets rougher.
func ground(x: float, z: float) -> float:
	var b := base_height(x, z)
	if _xc.is_empty():
		return b
	var d := absf(x - _centre(z)) - _half(z)
	if d <= 0.0:
		return b
	var w := smoothstep(0.0, 28.0, d)
	return b + 3.5 * w + 0.05 * d + 1.2 * w * sin(x * 0.09 + z * 0.07) * sin(z * 0.05 - x * 0.03)


func _centre(z: float) -> float:
	var i := clampi(int(z - _c_z0), 0, _xc.size() - 1)
	return _xc[i]


func _half(z: float) -> float:
	var i := clampi(int(z - _c_z0), 0, _hw.size() - 1)
	return _hw[i]


func far_height(x: float, z: float) -> float:
	return base_height(x, z)


func far_scenery() -> Dictionary:
	var r := terrain_rect.size.length() * 0.5 + 900.0
	return {"ring_radius": r, "ring_cell": 40.0,
		"hills": {"height": 1500.0, "r0": r + 700.0, "r1": r + 6500.0, "frequency": 0.001, "snow_line": -4000.0,
			"tree_line": -4000.0, "forest": Color(0.07, 0.15, 0.09), "rock": Color(0.36, 0.35, 0.36)},
		"trees": {"kind": "conifer", "count": 1800, "r0": 150.0, "r1": r - 150.0, "colour": Color(0.08, 0.3, 0.14),
			"grove": -0.2}}


# --- Terrain -------------------------------------------------------------------------------------

func build_terrain(path: PackedVector3Array, _plan: Dictionary) -> void:
	_piste_from(path)
	var b := PathUtil.bounds_xz(path)
	var x_half := maxf(absf(b.position.x), absf(b.end.x)) + 230.0
	var z0 := b.position.y - 170.0
	var z1 := b.end.y + 230.0
	var mi := MeshInstance3D.new()
	mi.name = "Terrain"
	mi.mesh = TerrainBuilder.build(Callable(self, "ground"), x_half, z0, z1, 3.5, 24.0)
	var mat := GroundMaterials.snow()
	mi.material_override = mat
	host.add_child(mi)
	terrain_rect = Rect2(-x_half, z0, 2.0 * x_half, z1 - z0)
	terrain_material = mat
	ground_mask = GroundMask.new()
	ground_mask.setup(terrain_rect, 0.6)
	# the groomed piste, by pieces of 120 m (its width changes along the course)
	var z := z0
	while z < z1:
		var line := PackedVector3Array()
		var narrow := INF
		var zz := z
		while zz <= minf(z + 124.0, z1):
			line.append(Vector3(_centre(zz), 0.0, zz))
			narrow = minf(narrow, _half(zz) * _cos_at(zz))
			zz += 4.0
		ground_mask.add_band(line, narrow - 1.0, Color(0, 1, 0))
		z += 120.0
	host.add_child(ground_mask)
	ground_mask.bind(mat)


## Piste centre (the racing line smoothed over about 60 m, so the piste is wider than the line where the line swings
## from one side to the other) and half width along x, every metre of z.
func _piste_from(path: PackedVector3Array) -> void:
	var b := PathUtil.bounds_xz(path)
	_c_z0 = floorf(b.position.y) - 1.0
	var m := int(b.end.y - _c_z0) + 3
	var raw := PackedFloat32Array()
	raw.resize(m)
	var j := 1
	for k in m:
		var z := _c_z0 + k
		while j < path.size() - 1 and path[j].z < z:
			j += 1
		var a := path[j - 1]
		var c := path[j]
		raw[k] = lerpf(a.x, c.x, clampf((z - a.z) / maxf(c.z - a.z, 0.001), 0.0, 1.0))
	var smooth := _box(_box(raw, 30), 30)
	_xc = smooth
	_hw.resize(m)
	for k in m:
		var z := _c_z0 + k
		var base := 23.0 + 6.0 * sin(z * 0.0045 + _phase)
		var slope := (_xc[mini(k + 5, m - 1)] - _xc[maxi(k - 5, 0)]) / 10.0
		_hw[k] = (base + absf(raw[k] - _xc[k])) * sqrt(1.0 + slope * slope)


## Cosine of the angle of the piste with the fall line at z.
func _cos_at(z: float) -> float:
	var slope := (_centre(z + 5.0) - _centre(z - 5.0)) / 10.0
	return 1.0 / sqrt(1.0 + slope * slope)


static func _box(a: PackedFloat32Array, r: int) -> PackedFloat32Array:
	var n := a.size()
	var out := PackedFloat32Array()
	out.resize(n)
	var acc := 0.0
	var cnt := 0
	for k in mini(r, n):
		acc += a[k]
		cnt += 1
	for k in n:
		if k + r < n:
			acc += a[k + r]
			cnt += 1
		if k - r - 1 >= 0:
			acc -= a[k - r - 1]
			cnt -= 1
		out[k] = acc / cnt
	return out


# --- Scenery -------------------------------------------------------------------------------------

func populate(path: PackedVector3Array, drone: PackedVector3Array, plan: Dictionary, legacy: bool) -> void:
	_index(path, drone, legacy)
	var b := PathUtil.bounds_xz(path)
	var rng := RandomNumberGenerator.new()
	rng.seed = 61 + host.world_seed
	_lifts(path, rng)
	_forest(b, rng)
	_rocks(b, rng)
	var dense := RoadBuilder.sample_curve(host.make_curve(path), 2.0)
	_nets(dense, plan, rng)
	_gates(dense, plan)
	_dye_lines()
	_start(path)
	_finish(path, rng)
	if not legacy:
		var count := roundi(float(host.matrix.params.occlusion) * 8.0)
		var fr: Array = []
		for k in count:
			fr.append((k + 1.0) / (count + 1.0))
		host.add_los_occluders(fr)
	PropFactory.build_forest(host, _tree_pos, _tree_scale, Color(0.08, 0.3, 0.14), 11, FOREST_END)


## Spatial lookups of the drone's flight and of the lines of sight of the session.
func _index(path: PackedVector3Array, drone: PackedVector3Array, legacy: bool) -> void:
	_drone_cells.clear()
	_los_cells.clear()
	for p in drone:
		var c := int(floorf(p.z / CELL))
		if not _drone_cells.has(c):
			_drone_cells[c] = PackedVector3Array()
		var arr: PackedVector3Array = _drone_cells[c]
		arr.append(p)
		_drone_cells[c] = arr
	if legacy:
		return
	for i in range(0, mini(path.size(), drone.size()), 2):
		var a := Vector2(path[i].x, path[i].z)
		var d := Vector2(drone[i].x, drone[i].z)
		for c in range(int(floorf(minf(a.y, d.y) / CELL)), int(floorf(maxf(a.y, d.y) / CELL)) + 1):
			if not _los_cells.has(c):
				_los_cells[c] = PackedVector2Array()
			var arr: PackedVector2Array = _los_cells[c]
			arr.append(a)
			arr.append(d)
			_los_cells[c] = arr


## True if the drone flies within r metres (horizontally) of (x, z) lower than `top` + 1.5 m.
func _in_flight(x: float, z: float, r: float, top: float) -> bool:
	var q := Vector2(x, z)
	for c in range(int(floorf((z - r) / CELL)), int(floorf((z + r) / CELL)) + 1):
		if not _drone_cells.has(c):
			continue
		for p in _drone_cells[c]:
			if p.y < top + 1.5 and Vector2(p.x, p.z).distance_squared_to(q) < r * r:
				return true
	return false


## True within r metres of a line of sight drone -> subject of the session.
func _near_sight(x: float, z: float, r: float) -> bool:
	var q := Vector2(x, z)
	for c in range(int(floorf((z - r) / CELL)), int(floorf((z + r) / CELL)) + 1):
		if not _los_cells.has(c):
			continue
		var segs: PackedVector2Array = _los_cells[c]
		for k in range(0, segs.size(), 2):
			var a := segs[k]
			var ab := segs[k + 1] - a
			var l2 := ab.length_squared()
			var t := 0.0 if l2 < 0.0001 else clampf((q - a).dot(ab) / l2, 0.0, 1.0)
			if q.distance_squared_to(a + ab * t) < r * r:
				return true
	return false


func _off_piste(x: float, z: float) -> float:
	return absf(x - _centre(z)) - _half(z)


## The forest on both sides of the piste, denser near its edges; clear of the lines of sight, of the drone's flight
## and of the lift lines.
func _forest(b: Rect2, rng: RandomNumberGenerator) -> void:
	var z0 := b.position.y - 150.0
	var z1 := b.end.y + 200.0
	var wanted := int((z1 - z0) * 1.5)
	var placed := 0
	var tries := 0
	while placed < wanted and tries < wanted * 4:
		tries += 1
		var z := rng.randf_range(z0, z1)
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var d := 2.0 + pow(rng.randf(), 1.8) * 120.0
		var x := _centre(z) + side * (_half(z) + d)
		var s := rng.randf_range(0.9, 1.8)
		# glades: a few gaps in the forest
		if sin(x * 0.013 + _phase) * sin(z * 0.011) > 0.72:
			continue
		if _near_lift(x, z, 7.0):
			continue
		if _near_sight(x, z, PropFactory.CONE_R[0] * s + 1.0):
			continue
		var g := ground(x, z)
		if _in_flight(x, z, PropFactory.CONE_R[0] * s + 2.5, g + PropFactory.TREE_HEIGHT * s):
			continue
		_add_tree(Vector3(x, g, z), s)
		placed += 1


func _near_lift(x: float, z: float, r: float) -> bool:
	var q := Vector2(x, z)
	for l in _lift_lines:
		var a: Vector2 = l[0]
		var ab: Vector2 = l[1] - a
		var t := clampf((q - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		if q.distance_to(a + ab * t) < r:
			return true
	return false


## Rocky outcrops in the forest by the steep parts.
func _rocks(b: Rect2, rng: RandomNumberGenerator) -> void:
	for k in 26:
		var z := rng.randf_range(b.position.y, b.end.y)
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var x := _centre(z) + side * (_half(z) + rng.randf_range(8.0, 70.0))
		var size := Vector3(rng.randf_range(1.5, 3.5), rng.randf_range(1.0, 2.6), rng.randf_range(1.8, 4.0))
		if _near_sight(x, z, 4.0) or _near_lift(x, z, 6.0):
			continue
		var g := ground(x, z)
		if _in_flight(x, z, maxf(size.x, size.z) + 1.5, g + size.y * 1.4):
			continue
		_add_rock(Vector3(x, g - 0.3, z), size)


# --- Nets, gates, dye --------------------------------------------------------------------------

## Red A-nets (4 m) on the outside of the turns and on both sides of the landings, orange B-nets (1.8 m) here and
## there along the straights. A net is open where the drone flies through it.
func _nets(dense: PackedVector3Array, plan: Dictionary, rng: RandomNumberGenerator) -> void:
	var n := dense.size()
	var outer := PackedFloat32Array()  # -1 / +1: side (along x) of the outside of the turn at each point, 0 = none
	outer.resize(n)
	for i in range(4, n - 4):
		var t0 := dense[i] - dense[i - 4]
		var t1 := dense[i + 4] - dense[i]
		t0.y = 0.0
		t1.y = 0.0
		var k := t0.normalized().angle_to(t1.normalized()) / maxf((t0.length() + t1.length()) * 0.5, 0.1)
		if k > 1.0 / 260.0:
			var inward := t1.normalized() - t0.normalized()
			outer[i] = -signf(inward.x) if absf(inward.x) > 0.0001 else 0.0
	# extend each turn by 30 m (15 points) on both ends
	var marks := outer.duplicate()
	for i in n:
		if outer[i] != 0.0:
			for j in range(maxi(i - 15, 0), mini(i + 16, n)):
				if marks[j] == 0.0:
					marks[j] = outer[i]
	var landing := []
	for ev in plan.events:
		if ev.get("type", "") == "jump":
			landing.append(Vector2(float(ev.p0.z) - 20.0, float(ev.p1.z) + 120.0))
	for side in [-1.0, 1.0]:
		var run := PackedVector3Array()
		var kind := ""
		for i in range(0, n, 3):
			var z := dense[i].z
			var land := false
			for l in landing:
				if z >= l.x and z <= l.y:
					land = true
			var want := ""
			if land or marks[i] == side:
				want = "A"
			elif sin(z * 0.021 + side * 1.7 + _phase) > 0.35:
				want = "B"
			if want != kind and run.size() >= 2:
				_net_run(run, 4.0 if kind == "A" else 1.8, kind == "A")
			if want != kind:
				run = PackedVector3Array()
				kind = want
			if want != "":
				var x: float = _centre(z) + side * (_half(z) + (1.5 if want == "A" else 0.6))
				run.append(Vector3(x, ground(x, z), z))
		if run.size() >= 2 and kind != "":
			_net_run(run, 4.0 if kind == "A" else 1.8, kind == "A")


## A net along `pts` (ground positions), `height` m tall, on poles every 3 points; open where the drone passes.
func _net_run(pts: PackedVector3Array, height: float, red: bool) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var poles: Array[Transform3D] = []
	var u := 0.0
	var any := false
	for k in range(1, pts.size()):
		var a := pts[k - 1]
		var c := pts[k]
		var seg := Vector2(c.x - a.x, c.z - a.z).length()
		var mid := (a + c) * 0.5
		if _in_flight(mid.x, mid.z, seg * 0.5 + 1.5, mid.y + height):
			u += seg
			continue
		var nrm := Vector3(c.z - a.z, 0.0, a.x - c.x).normalized()
		for v in [[a, Vector2(u, 0.0)], [a + Vector3(0, height, 0), Vector2(u, height)], [c, Vector2(u + seg, 0.0)],
				[c, Vector2(u + seg, 0.0)], [a + Vector3(0, height, 0), Vector2(u, height)], [c + Vector3(0, height, 0), Vector2(u + seg, height)]]:
			st.set_normal(nrm)
			st.set_uv(v[1])
			st.add_vertex(v[0])
		any = true
		if k % 3 == 1:
			poles.append(Transform3D(Basis().scaled(Vector3(1.0, height + 0.3, 1.0)), a + Vector3(0, (height + 0.3) * 0.5, 0)))
		u += seg
	if not any:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _downhill_net(height, red)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	host.add_child(mi)
	if not poles.is_empty():
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.04
		cyl.bottom_radius = 0.05
		cyl.height = 1.0
		cyl.radial_segments = 6
		cyl.material = PathSubject.make_mat(Color(0.12, 0.12, 0.13), 0.6)
		_multimesh(cyl, poles)


## Net material: a square mesh (UV in metres) with a band along the top and the bottom.
static func _downhill_net(height: float, red: bool) -> ShaderMaterial:
	var key := "%.1f_%s" % [height, red]
	if _net_mats.has(key):
		return _net_mats[key]
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode cull_disabled;
uniform vec3 colour : source_color;
uniform float height = 4.0;
uniform float mesh_size = 0.12;
void fragment() {
	vec2 g = fract(UV / mesh_size);
	float w = fwidth(UV.x / mesh_size) * 0.8 + 0.06;
	float line = max(1.0 - smoothstep(0.0, w, min(g.x, 1.0 - g.x)), 1.0 - smoothstep(0.0, w, min(g.y, 1.0 - g.y)));
	float rim = 1.0 - smoothstep(0.0, 0.08, min(UV.y, height - UV.y));
	ALBEDO = colour;
	ALPHA = max(line, rim);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 0.8;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("colour", Color(0.85, 0.06, 0.05) if red else Color(1.0, 0.35, 0.02))
	m.set_shader_parameter("height", height)
	_net_mats[key] = m
	return m


## Red downhill gates (two flags on two poles each, on both sides of the racing line) about every 110 m, not where
## the skier is in the air.
func _gates(dense: PackedVector3Array, plan: Dictionary) -> void:
	var cum := PathUtil.cumulative(dense)
	var total: float = cum[cum.size() - 1]
	var air := []
	for ev in plan.events:
		if ev.get("type", "") == "jump":
			air.append(Vector2(float(ev.p0.z) - 15.0, float(ev.p1.z) + 10.0))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var poles := SurfaceTool.new()
	poles.begin(Mesh.PRIMITIVE_TRIANGLES)
	var s := 90.0
	while s < total - 60.0:
		var p := PathUtil.polyline_at(dense, cum, s)
		var flying := false
		for a in air:
			if p.z >= a.x and p.z <= a.y:
				flying = true
		if not flying:
			var t := PathUtil.polyline_at(dense, cum, s + 2.0) - PathUtil.polyline_at(dense, cum, s - 2.0)
			t.y = 0.0
			t = t.normalized()
			var right := t.cross(Vector3.UP)
			for sd in [-1.0, 1.0]:
				var c: Vector3 = p + right * sd * 5.0
				var g := ground(c.x, c.z)
				if _in_flight(c.x, c.z, 1.5, g + 2.0):
					continue
				var basis := Basis(Vector3.UP, atan2(t.x, t.z))  # the flag faces the skier
				for pp in [-0.42, 0.42]:
					var pm := BoxMesh.new()
					pm.size = Vector3(0.05, 1.9, 0.05)
					poles.append_from(pm, 0, Transform3D(basis, Vector3(c.x, g, c.z) + basis * Vector3(pp, 0.95, 0.0)))
				var flag := BoxMesh.new()
				flag.size = Vector3(0.82, 0.95, 0.02)
				st.append_from(flag, 0, Transform3D(basis, Vector3(c.x, g + 1.35, c.z)))
		s += 110.0
	for pair in [[st, Color(0.85, 0.05, 0.05)], [poles, Color(0.92, 0.92, 0.92)]]:
		var mi := MeshInstance3D.new()
		mi.mesh = pair[0].commit()
		mi.material_override = PathSubject.make_mat(pair[1], 0.6)
		host.add_child(mi)


## Blue dye lines across the piste just before each crest (so the racers see the take-off).
func _dye_lines() -> void:
	var xforms: Array[Transform3D] = []
	for c in crests:
		if c < _c_z0 or c > _c_z0 + _xc.size():
			continue
		for dz in [-6.0, -3.0]:
			var z: float = c + dz
			var half := _half(z)
			var x := _centre(z) - half
			while x < _centre(z) + half:
				var g := ground(x, z)
				var tilt := atan2(ground(x, z - 0.5) - ground(x, z + 0.5), 1.0)
				xforms.append(Transform3D(Basis(Vector3.RIGHT, tilt), Vector3(x + 0.5, g + 0.03, z)))
				x += 1.0
	if xforms.is_empty():
		return
	var box := BoxMesh.new()
	box.size = Vector3(1.02, 0.02, 0.45)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.1, 0.25, 0.85)
	m.roughness = 0.9
	box.material = m
	_multimesh(box, xforms, false)


# --- Lifts ---------------------------------------------------------------------------------------

## A chairlift alongside the piste, beyond the forest edge, and another one crossing high above the piste. Each is
## placed where the drone never flies close to its cables (a few places are tried; no lift if none is free).
func _lifts(path: PackedVector3Array, rng: RandomNumberGenerator) -> void:
	var b := PathUtil.bounds_xz(path)
	# alongside: a straight line over about 900 m, 50 m beyond the edge
	for _try in 8:
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var za := rng.randf_range(b.position.y + 100.0, maxf(b.position.y + 110.0, b.end.y - 1000.0))
		var zb := minf(za + 900.0, b.end.y)
		var xa := _centre(za) + side * (_half(za) + 50.0)
		var xb := _centre(zb) + side * (_half(zb) + 50.0)
		var towers := PackedVector3Array()
		var count := maxi(2, int((zb - za) / 80.0) + 1)
		var ok := true
		for k in count:
			var t := float(k) / (count - 1)
			var x := lerpf(xa, xb, t)
			var z := lerpf(za, zb, t)
			if _off_piste(x, z) < 12.0:
				ok = false
				break
			towers.append(Vector3(x, ground(x, z), z))
		if ok and _lift_free(towers, 11.0):
			_lift(towers, 11.0)
			lifts_built.append("alongside")
			break
	# crossing: across the piste, a little diagonal, high above it
	var candidates := []
	var z := b.position.y + 300.0
	while z < b.end.y - 300.0:
		var near_crest := false
		for c in crests:
			if absf(c - z) < 160.0:
				near_crest = true
		if not near_crest:
			candidates.append(z)
		z += 90.0
	for k in range(candidates.size() - 1, 0, -1):
		var j := rng.randi_range(0, k)
		var tmp = candidates[k]
		candidates[k] = candidates[j]
		candidates[j] = tmp
	for zc in candidates:
		var centre := Vector2(_centre(zc), zc)
		var u := Vector2(1.0, tan(deg_to_rad(16.0))).normalized()
		var hw := _half(zc) * _cos_at(zc)
		var towers := PackedVector3Array()
		for f in [-(hw + 120.0), -(hw + 14.0), hw + 14.0, hw + 120.0]:
			var q: Vector2 = centre + u * f
			towers.append(Vector3(q.x, ground(q.x, q.y), q.y))
		var top := maxf(towers[1].y, towers[2].y) - minf(towers[1].y, towers[2].y)
		var height := 16.0 + top
		if _lift_free(towers, height):
			_lift(towers, height)
			lifts_built.append("crossing")
			break


## True if the drone never flies close to the cables and chairs of a lift with these towers.
func _lift_free(towers: PackedVector3Array, height: float) -> bool:
	for i in towers.size() - 1:
		var a := towers[i] + Vector3(0, height, 0)
		var c := towers[i + 1] + Vector3(0, height, 0)
		var d := a.distance_to(c)
		var steps := maxi(2, int(d / 3.0))
		for k in steps + 1:
			var t := float(k) / steps
			var p := a.lerp(c, t) - Vector3(0, 0.8 * 4.0 * t * (1.0 - t), 0)
			for cell in range(int(floorf((p.z - 7.0) / CELL)), int(floorf((p.z + 7.0) / CELL)) + 1):
				if not _drone_cells.has(cell):
					continue
				for q in _drone_cells[cell]:
					if Vector2(q.x - p.x, q.z - p.z).length() < 7.0 and q.y > p.y - 9.0 and q.y < p.y + 3.0:
						return false
	for t in towers:
		if _in_flight(t.x, t.z, 4.0, t.y + height):
			return false
	return true


## Chairlift: towers with a cross beam, two cables with a little sag, chairs every 18 m (facing along the line).
func _lift(towers: PackedVector3Array, height: float) -> void:
	var steel := PathSubject.make_mat(Color(0.55, 0.57, 0.6), 0.5)
	steel.metallic = 0.6
	for i in towers.size():
		var g := towers[i]
		var dir := (towers[mini(i + 1, towers.size() - 1)] - towers[maxi(i - 1, 0)])
		dir.y = 0.0
		dir = dir.normalized()
		_lift_lines.append([Vector2(g.x, g.z) - Vector2(dir.x, dir.z) * 10.0, Vector2(g.x, g.z) + Vector2(dir.x, dir.z) * 10.0])
		var mast := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.28
		cyl.bottom_radius = 0.4
		cyl.height = height
		cyl.radial_segments = 8
		mast.mesh = cyl
		mast.material_override = steel
		mast.position = g + Vector3(0, height * 0.5, 0)
		host.add_child(mast)
		host.add_cylinder_occluder(g, 0.45, height)
		var beam := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(4.8, 0.32, 0.32)
		beam.mesh = bm
		beam.material_override = steel
		beam.position = g + Vector3(0, height, 0)
		beam.rotation.y = atan2(dir.x, dir.z) + PI * 0.5
		host.add_child(beam)
	for i in towers.size() - 1:
		_lift_lines.append([Vector2(towers[i].x, towers[i].z), Vector2(towers[i + 1].x, towers[i + 1].z)])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var chairs: Array[Transform3D] = []
	for i in towers.size() - 1:
		var dir := towers[i + 1] - towers[i]
		dir.y = 0.0
		var perp := dir.normalized().cross(Vector3.UP)
		var yaw := atan2(dir.x, dir.z)
		for side in [-2.2, 2.2]:
			var a: Vector3 = towers[i] + perp * side + Vector3(0, height - 0.2, 0)
			var c: Vector3 = towers[i + 1] + perp * side + Vector3(0, height - 0.2, 0)
			var prev := a
			for k in range(1, 13):
				var t := k / 12.0
				var p := a.lerp(c, t) - Vector3(0, 0.8 * 4.0 * t * (1.0 - t), 0)
				Buildings._wire(st, prev, p, 0.03)
				prev = p
			var d := a.distance_to(c)
			var s := 9.0 if side < 0.0 else 0.0
			while s < d:
				var t2 := s / d
				chairs.append(Transform3D(Basis(Vector3.UP, yaw + (PI if side < 0.0 else 0.0)),
						a.lerp(c, t2) - Vector3(0, 0.8 * 4.0 * t2 * (1.0 - t2), 0)))
				s += 18.0
	var cables := MeshInstance3D.new()
	cables.mesh = st.commit()
	cables.material_override = PathSubject.make_mat(Color(0.15, 0.15, 0.16), 0.5)
	cables.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	host.add_child(cables)
	var cst := SurfaceTool.new()
	cst.begin(Mesh.PRIMITIVE_TRIANGLES)
	for box in [[Vector3(0, -0.95, 0), Vector3(0.05, 1.9, 0.05)], [Vector3(0, -2.0, 0.15), Vector3(1.4, 0.08, 0.5)],
			[Vector3(0, -1.7, 0.4), Vector3(1.4, 0.55, 0.08)]]:
		var bmesh := BoxMesh.new()
		bmesh.size = box[1]
		cst.append_from(bmesh, 0, Transform3D(Basis(), box[0]))
	var cm := cst.commit()
	var mmi := _multimesh(cm, chairs)
	mmi.material_override = PathSubject.make_mat(Color(0.2, 0.22, 0.25), 0.6)


# --- Start and finish ----------------------------------------------------------------------------

## Start house above the first metres of the course, with the start banner.
func _start(path: PackedVector3Array) -> void:
	var p := path[0]
	for dx in [0.0, 14.0, -14.0]:
		var c := Vector3(p.x + dx, 0.0, p.z - 16.0)
		c.y = ground(c.x, c.z)
		if _in_flight(c.x, c.z, 5.0, c.y + 5.5):
			continue
		var wood := PathSubject.make_mat(Color(0.45, 0.3, 0.18), 0.85)
		_box_at(Vector3(6.0, 4.0, 5.0), c + Vector3(0, 2.0, 0), wood)
		var roof := _box_at(Vector3(7.0, 0.35, 6.2), c + Vector3(0, 4.4, 0), PathSubject.make_mat(Color(0.25, 0.1, 0.08), 0.7))
		roof.rotation.x = deg_to_rad(-12.0)
		host.add_cylinder_occluder(c, 3.5, 4.5)
		break
	# banner over the start gate
	var g := ground(p.x, p.z - 4.0)
	if not _in_flight(p.x, p.z - 4.0, 5.0, g + 3.6):
		var red := PathSubject.make_mat(Color(0.85, 0.06, 0.05), 0.6)
		for sd in [-3.2, 3.2]:
			_box_at(Vector3(0.15, 3.2, 0.15), Vector3(p.x + sd, g + 1.6, p.z - 4.0), red)
		_box_at(Vector3(6.6, 0.8, 0.08), Vector3(p.x, g + 2.9, p.z - 4.0), PathSubject.make_mat(Color(0.95, 0.95, 0.95), 0.6))


## Finish: red line, arch beyond it, grandstand with spectators on one side, advertising boards along the last
## 200 m (all where the drone does not fly).
func _finish(path: PackedVector3Array, rng: RandomNumberGenerator) -> void:
	var e := path[path.size() - 1]
	var z_end := e.z
	# red finish line
	var xforms: Array[Transform3D] = []
	var half := _half(z_end)
	var x := _centre(z_end) - half
	while x < _centre(z_end) + half:
		xforms.append(Transform3D(Basis(), Vector3(x + 0.5, ground(x, z_end) + 0.03, z_end)))
		x += 1.0
	var box := BoxMesh.new()
	box.size = Vector3(1.02, 0.02, 0.6)
	box.material = PathSubject.make_mat(Color(0.85, 0.05, 0.05), 0.9)
	_multimesh(box, xforms, false)
	# arch 25 m after the line
	var za := z_end + 25.0
	var ha := _half(za) - 1.0
	var xl := _centre(za) - ha
	var xr := _centre(za) + ha
	var red := PathSubject.make_mat(Color(0.85, 0.06, 0.05), 0.6)
	var white := PathSubject.make_mat(Color(0.95, 0.95, 0.95), 0.6)
	var pillars_ok := true
	for px in [xl, xr]:
		if _in_flight(px, za, 2.0, ground(px, za) + 8.0):
			pillars_ok = false
	if pillars_ok:
		for px in [xl, xr]:
			var g := ground(px, za)
			_box_at(Vector3(1.2, 8.0, 1.2), Vector3(px, g + 4.0, za), red)
			host.add_cylinder_occluder(Vector3(px, g, za), 0.9, 8.0)
		var banner_free := true
		var bx := xl
		var top := maxf(ground(xl, za), ground(xr, za)) + 7.0
		while bx <= xr:
			if _in_flight(bx, za, 2.5, top + 0.8):
				banner_free = false
			bx += 3.0
		if banner_free:
			_box_at(Vector3(xr - xl, 1.6, 0.4), Vector3((xl + xr) * 0.5, top, za), white)
			_box_at(Vector3(xr - xl, 0.4, 0.42), Vector3((xl + xr) * 0.5, top - 0.75, za), red)
	# grandstand on the side where the drone flies less, just past the line
	var best_side := 1.0
	var best := INF
	for sd in [-1.0, 1.0]:
		var hits := 0
		for k in 8:
			var zz := z_end - 30.0 + k * 10.0
			var xx: float = _centre(zz) + sd * (_half(zz) + 12.0)
			if _in_flight(xx, zz, 12.0, ground(xx, zz) + 9.0):
				hits += 1
		if hits < best:
			best = hits
			best_side = sd
	if best == 0:
		_grandstand(z_end, best_side, rng)
	# advertising boards along both edges of the last 200 m
	var bxf: Array[Transform3D] = []
	var bcol := PackedColorArray()
	var palette := [Color(0.85, 0.06, 0.05), Color(0.1, 0.3, 0.8), Color(0.95, 0.95, 0.95), Color(0.95, 0.75, 0.05)]
	for sd in [-1.0, 1.0]:
		var zb := z_end - 200.0
		while zb < z_end + 40.0:
			var xb: float = _centre(zb) + sd * (_half(zb) - 0.5)
			var g := ground(xb, zb)
			if not _in_flight(xb, zb, 2.0, g + 1.0):
				var t := Vector3(_centre(zb + 2.0) - _centre(zb - 2.0), 0.0, 4.0).normalized()
				bxf.append(Transform3D(Basis(Vector3.UP, atan2(t.x, t.z)), Vector3(xb, g + 0.45, zb)))
				bcol.append(palette[rng.randi() % palette.size()])
			zb += 3.0
	if not bxf.is_empty():
		var board := BoxMesh.new()
		board.size = Vector3(0.12, 0.9, 2.9)
		_multimesh(board, bxf, true, bcol)


func _grandstand(z_end: float, side: float, rng: RandomNumberGenerator) -> void:
	var grey := PathSubject.make_mat(Color(0.5, 0.52, 0.55), 0.7)
	var people: Array[Transform3D] = []
	var colours := PackedColorArray()
	var zc := z_end + 5.0
	var x0 := _centre(zc) + side * (_half(zc) + 8.0)
	var g := ground(x0, zc)
	for step in 5:
		var xs := x0 + side * step * 1.6
		var h := 0.6 + step * 0.8
		_box_at(Vector3(1.6, h, 60.0), Vector3(xs, g + h * 0.5 - 0.3, zc), grey)
		for k in 34:
			if rng.randf() < 0.25:
				continue
			var zp := zc - 29.0 + k * 1.75 + rng.randf_range(-0.3, 0.3)
			people.append(Transform3D(Basis().scaled(Vector3.ONE * rng.randf_range(0.9, 1.1)), Vector3(xs, g + h - 0.3 + 0.8, zp)))
			colours.append(Color.from_hsv(rng.randf(), rng.randf_range(0.5, 0.9), rng.randf_range(0.4, 0.95)))
	host.add_cylinder_occluder(Vector3(x0 + side * 4.0, g, zc), 5.0, 4.5)
	var body := CapsuleMesh.new()
	body.radius = 0.25
	body.height = 1.6
	body.radial_segments = 8
	body.rings = 2
	_multimesh(body, people, true, colours)


# --- Helpers -------------------------------------------------------------------------------------

func _box_at(size: Vector3, centre: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat
	mi.position = centre
	host.add_child(mi)
	return mi


func _multimesh(mesh: Mesh, xforms: Array[Transform3D], shadows := true, colours := PackedColorArray()) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not colours.is_empty()
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		if mm.use_colors:
			mm.set_instance_color(i, colours[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	if not shadows:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if mm.use_colors:
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.roughness = 0.7
		mmi.material_override = m
	host.add_child(mmi)
	return mmi

class_name EnvFreeride
extends EnvDownhill
## Freeride face (tag "freeride"), in the spirit of the Freeride World Tour venues (Bec des Rosses, Fieberbrunn,
## Ordino...): a big steep face of untracked snow under a summit ridge.
##  - the start on the summit ridge (a small platform, feather flags, officials), then the roll-in onto the face;
##  - the face, 600 m or so of it at 38 to 50°, with convex rolls, spines and couloirs running down the fall line,
##    and four or five rock bands across it. A band has the same drop all across the face (so the slope below it
##    is even), but not the same shape: a cliff of 7 to 13 m where its rock stands, a steep couloir through each gap
##    of the rock, and a mere steeper roll beyond the rock. Just above a band the slope eases (the lip);
##  - the apron below the face, flattening into the finish basin (inflatable arch, banners, flags, spectators);
##  - rocky ridges on both sides, rock islands and boulders on the face, spruces down in the basin, old tracks of
##    the riders who skied the face before.
## The face only depends on the world seed. The rider's line (ArchetypeFreeride) reads the start, the finish and
## the rock bands (band_z / band_width / band_rock / band_drop) to pick a cliff to drop or a couloir to ski.
## Nothing is built in the drone's flight, nor on a line of sight of the session.

const Z_BACK := -320.0       # m: the fall-line profile starts behind the summit ridge
const Z_RIDGE := -24.0       # crest of the summit ridge (the start platform is just below it)
const FACE_W := 230.0        # half width of the skiable face, m
const X_HALF := 330.0        # half width of the detailed terrain, m
const W_SOFT := 50.0         # m: beyond its rock, the drop of a band is a steeper roll this long
const CELL_T := 2.5          # m, cell of the detailed terrain

var face_end := 600.0        ## z where the face gives way to the apron
var finish_z := 900.0        ## z of the finish line, in the flat basin
var start := Vector3.ZERO    ## start gate, on the platform below the summit ridge
# Rock bands (sorted by z): z, amplitude and phase of their curve, drop (m), x extent of their rock, width of the
# cliff and of the couloirs; gaps in the rock (x centre, half width) from _bgap0[k] to _bgap0[k + 1].
var _bz := PackedFloat32Array()
var _bamp := PackedFloat32Array()
var _bph := PackedFloat32Array()
var _bdrop := PackedFloat32Array()
var _bxa := PackedFloat32Array()
var _bxb := PackedFloat32Array()
var _bwc := PackedFloat32Array()
var _bwg := PackedFloat32Array()
var _bgap0 := PackedInt32Array()
var _gaps := PackedVector2Array()
var _fh := PackedFloat32Array()   # height of the fall line every metre from Z_BACK
var _n_bump: FastNoiseLite
var _n_cross: FastNoiseLite
var _n_band: FastNoiseLite
var _n_crest: FastNoiseLite
var _n_big: FastNoiseLite
var _hinfo := {}                  # heights of the detailed terrain (TerrainBuilder.last_info), for the lines of sight
var _path_cells := {}             # cell of z -> PackedVector2Array of path points
var _crowd_spots := []            # [Rect2 (x, z)] where spectators stand: no tree, no rock there
var _isl := PackedVector3Array()  # islands of rock on the face: x, z, radius (a mound of rock and snow)


func configure() -> void:
	Vegetation.snow_cover = 0.9
	Rocks.moss_amount = 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7310 + host.world_seed
	_phase = rng.randf() * TAU
	_n_bump = _noise(rng, 0.035, 3)
	_n_cross = _noise(rng, 0.01, 2)
	_n_band = _noise(rng, 0.045, 2)
	_n_crest = _noise(rng, 0.009, 3)
	_n_big = _noise(rng, 0.0016, 3)
	start = Vector3(rng.randf_range(-45.0, 45.0), 0.0, Z_RIDGE + 7.0)
	face_end = rng.randf_range(570.0, 640.0)
	finish_z = face_end + 290.0

	# Rock bands across the face, at least 95 m apart
	var count := rng.randi_range(4, 5)
	var zs: Array[float] = []
	var tries := 0
	while zs.size() < count and tries < 400:
		tries += 1
		var zc := rng.randf_range(85.0, face_end - 45.0)
		var ok := true
		for o in zs:
			if absf(o - zc) < 95.0:
				ok = false
		if ok:
			zs.append(zc)
	zs.sort()
	for zc in zs:
		_bz.append(zc)
		_bamp.append(rng.randf_range(4.0, 9.0))
		_bph.append(rng.randf() * TAU)
		var drop := rng.randf_range(7.0, 13.0)
		_bdrop.append(drop)
		# the rock spans part of the face, a different part for each band
		var mid := rng.randf_range(-150.0, 150.0)
		var half := rng.randf_range(55.0, 170.0)
		var xa := maxf(mid - half, -FACE_W - 20.0)
		var xb := minf(mid + half, FACE_W + 20.0)
		_bxa.append(xa)
		_bxb.append(xb)
		_bwc.append(2.4 + 0.14 * drop)
		_bwg.append(2.6 * drop)
		_bgap0.append(_gaps.size())
		for _k in rng.randi_range(1, 3):
			_gaps.append(Vector2(rng.randf_range(xa + 25.0, maxf(xb - 25.0, xa + 26.0)), rng.randf_range(6.0, 11.0)))
	_bgap0.append(_gaps.size())
	# islands of rock on the face, away from the bands
	tries = 0
	while _isl.size() < 20 and tries < 400:
		tries += 1
		var ix := rng.randf_range(-FACE_W + 15.0, FACE_W - 15.0)
		var iz := rng.randf_range(45.0, face_end + 40.0)
		var ok := true
		for k in _bz.size():
			if absf(iz - _bz[k]) < 30.0:
				ok = false
		for o in _isl:
			if Vector2(o.x - ix, o.y - iz).length() < 38.0:
				ok = false
		if ok:
			_isl.append(Vector3(ix, iz, rng.randf_range(6.0, 12.0)))

	# Fall line: sections [start z, grade, length of the transition from the previous grade]
	var sections := [[Z_BACK, -0.5, 0.0], [Z_RIDGE - 16.0, 0.22, 14.0], [-22.0, 0.7, 6.0],
			[-8.0, rng.randf_range(0.95, 1.1), 8.0]]
	var z := 60.0
	var steep := false
	while z < face_end:
		var length := rng.randf_range(60.0, 110.0)
		var g := rng.randf_range(0.95, 1.15) if steep else rng.randf_range(0.72, 0.88)
		sections.append([z, g, rng.randf_range(18.0, 38.0)])
		steep = not steep
		z += length
	# the apron, the finish basin, then the valley going on gently
	sections.append([face_end, 0.62, 30.0])
	sections.append([face_end + 70.0, 0.4, 40.0])
	sections.append([face_end + 150.0, 0.22, 50.0])
	sections.append([face_end + 225.0, 0.05, 50.0])
	sections.append([finish_z + 180.0, 0.16, 90.0])
	var z_end := finish_z + 1200.0
	var n := int(z_end - Z_BACK) + 1
	var grade := PackedFloat32Array()
	grade.resize(n)
	var si := 0
	var prev_g: float = sections[0][1]
	for k in n:
		var zk := Z_BACK + k
		while si + 1 < sections.size() and zk >= float(sections[si + 1][0]):
			prev_g = float(sections[si][1])
			si += 1
		grade[k] = _grade_at_section(sections[si], prev_g, zk)
		# a bench just above each rock band: the lip
		for zb in _bz:
			var a := smoothstep(zb - 48.0, zb - 32.0, zk) * (1.0 - smoothstep(zb - 10.0, zb - 2.0, zk))
			if a > 0.0 and grade[k] > 0.55:
				grade[k] = lerpf(grade[k], 0.55, 0.8 * a)
	_fh.resize(n)
	_fh[0] = 0.0
	for k in range(1, n):
		_fh[k] = _fh[k - 1] - 0.5 * (grade[k - 1] + grade[k])
	var h0 := _fh[int(Z_RIDGE - Z_BACK)]
	for k in n:
		_fh[k] -= h0
	start.y = base_height(start.x, start.z)


static func _noise(rng: RandomNumberGenerator, freq: float, octaves: int) -> FastNoiseLite:
	var nz := FastNoiseLite.new()
	nz.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	nz.seed = rng.randi()
	nz.frequency = freq
	nz.fractal_octaves = octaves
	return nz


# --- Relief --------------------------------------------------------------------------------------

func fall_line(z: float) -> float:
	var f := z - Z_BACK
	if f <= 0.0:
		return _fh[0] + f * 0.5
	var last := _fh.size() - 1
	if f >= last:
		return _fh[last] - (f - last) * 0.16
	var i := int(f)
	return lerpf(_fh[i], _fh[i + 1], f - i)


func base_height(x: float, z: float) -> float:
	var ax := absf(x)
	var h := fall_line(z)
	# the face is a wide shallow bowl; rocky ribs on both sides, then the mountain side goes on (more ribs)
	h += 0.00025 * minf(x * x, FACE_W * FACE_W) * smoothstep(-40.0, 40.0, z)
	var fl := ax - (FACE_W - 20.0)
	if fl > 0.0:
		var below := smoothstep(-10.0, 40.0, z)
		# the rib framing the face (wandering a little), then ribs here and there down the mountain side
		var sx := signf(x)
		var rc := FACE_W + 50.0 + 35.0 * _n_big.get_noise_2d(z * 1.5, 77.0 + sx * 300.0)
		var rh := 20.0 + 60.0 * clampf(0.5 + 1.2 * _n_big.get_noise_2d(z * 2.5, sx * 500.0), 0.0, 1.0)
		var rib := exp(-pow((ax - rc) / 30.0, 2.0)) * (rh + 12.0 * _n_bump.get_noise_2d(x * 0.3, z * 0.3))
		var far := smoothstep(FACE_W + 70.0, FACE_W + 180.0, ax)
		var rn := clampf(1.0 - 2.2 * absf(_n_big.get_noise_2d(x * 1.6, z * 0.5)), 0.0, 1.0)
		rib += far * 60.0 * rn * rn * rn * rn * (0.6 + 0.6 * _n_big.get_noise_2d(x, z))
		h += rib * below + 6.0 * _n_bump.get_noise_2d(x * 0.5, z * 0.5) * smoothstep(0.0, 40.0, fl)
		# the faces beyond are steeper or gentler than this one
		h += (fall_line(z) - fall_line(0.0)) * 0.22 * _n_big.get_noise_2d(x * 0.7, 900.0) * far * below
	# big undulations across the mountain side (gentle on the face itself)
	h += _n_big.get_noise_2d(x, z) * lerpf(8.0, 30.0, smoothstep(FACE_W - 40.0, FACE_W + 150.0, ax)) * smoothstep(-30.0, 30.0, z)
	# summit ridge: rocky peaks along the crest, away from the start
	var ck := (z - Z_RIDGE + 6.0) / 30.0
	if absf(ck) < 2.5:
		var peaks := maxf(_n_crest.get_noise_1d(x), 0.0) * smoothstep(30.0, 90.0, absf(x - start.x))
		h += exp(-ck * ck) * 55.0 * peaks
	# spines and couloirs down the fall line (on the face only)
	var fk := smoothstep(20.0, 70.0, z) * (1.0 - smoothstep(face_end - 30.0, face_end + 90.0, z)) \
			* (1.0 - smoothstep(FACE_W - 50.0, FACE_W, ax))
	if fk > 0.0:
		# ridged noise stretched along the fall line: spines that wander, gullies between them
		var r := clampf(1.0 - 1.7 * absf(_n_cross.get_noise_2d(x, z * 0.22)), 0.0, 1.0)
		var r2 := clampf(1.0 - 1.7 * absf(_n_cross.get_noise_2d(x * 2.6 + 400.0, z * 0.5)), 0.0, 1.0)
		h += fk * (6.5 * (r * r * r - 0.2) + 2.2 * (r2 * r2 * r2 * r2 - 0.15))
	# islands of rock: mounds
	for o in _isl:
		var di := Vector2(x - o.x, z - o.y).length() / o.z
		if di < 1.6:
			h += 3.5 * exp(-di * di * 1.6)
	# rolls and pillows
	h += 1.6 * _n_bump.get_noise_2d(x, z) + 0.3 * sin(x * 0.37 + 1.3 * sin(z * 0.21)) * sin(z * 0.29)
	return h - _band_offset(x, z)


func ground(x: float, z: float) -> float:
	return base_height(x, z)


func far_height(x: float, z: float) -> float:
	return base_height(x, z)


## How much the rock bands above (x, z) have dropped the ground there.
func _band_offset(x: float, z: float) -> float:
	var off := 0.0
	for k in _bz.size():
		var dz := z - _bz[k]
		var reach := _bamp[k] + 11.0 + W_SOFT * 0.5
		if dz < -reach:
			break  # (sorted by z: the next ones are further down)
		if dz > reach:
			off += _bdrop[k]
			continue
		var u := (z - band_z(k, x)) / band_width(k, x) + 0.5
		if u >= 1.0:
			off += _bdrop[k]
		elif u > 0.0:
			off += _bdrop[k] * u * u * u * (u * (u * 6.0 - 15.0) + 10.0)
	return off


# --- What the rider's line reads ----------------------------------------------------------------

func band_count() -> int:
	return _bz.size()


## z of the middle of band k at x.
func band_z(k: int, x: float) -> float:
	return _bz[k] + _bamp[k] * sin(x * 0.02 + _bph[k]) + 7.0 * _n_band.get_noise_2d(x * 0.25, k * 37.0) \
			+ 2.5 * _n_band.get_noise_2d(x, k * 37.0)


func band_drop(k: int) -> float:
	return _bdrop[k]


## 1 where band k is a cliff at x, 0 in a couloir through its rock or beyond its rock.
func band_rock(k: int, x: float) -> float:
	var inside := smoothstep(_bxa[k] - 18.0, _bxa[k] + 4.0, x) * (1.0 - smoothstep(_bxb[k] - 4.0, _bxb[k] + 18.0, x))
	return inside * (1.0 - _gap_k(k, x))


## Horizontal length (along z) over which band k drops at x: a few metres for a cliff, more for a couloir.
func band_width(k: int, x: float) -> float:
	var inside := smoothstep(_bxa[k] - 18.0, _bxa[k] + 4.0, x) * (1.0 - smoothstep(_bxb[k] - 4.0, _bxb[k] + 18.0, x))
	return lerpf(W_SOFT, lerpf(_bwc[k], _bwg[k], _gap_k(k, x)), inside)


## 1 inside a gap of the rock of band k (a couloir), 0 elsewhere.
func _gap_k(k: int, x: float) -> float:
	var g := 0.0
	for j in range(_bgap0[k], _bgap0[k + 1]):
		var p := _gaps[j]
		g = maxf(g, 1.0 - smoothstep(p.y, p.y + 5.0, absf(x - p.x)))
	return g


func freeride_start() -> Vector3:
	return start


func freeride_finish_z() -> float:
	return finish_z


## Half width of the skiable face at z (the line keeps inside it).
func face_half_width(_z: float) -> float:
	return FACE_W - 25.0


# --- Terrain ---------------------------------------------------------------------------------------

func occluder_kind() -> String:
	return "rocks"


func far_scenery() -> Dictionary:
	var r := terrain_rect.size.length() * 0.5 + 900.0
	return {"ring_radius": r, "ring_cell": 40.0,
		"hills": {"height": 1800.0, "r0": r + 600.0, "r1": r + 6500.0, "frequency": 0.001, "snow_line": -4000.0,
			"tree_line": -4000.0, "forest": Color(0.07, 0.15, 0.09), "rock": Color(0.38, 0.35, 0.33)},
		"trees": {"kind": "conifer", "count": 900, "r0": 500.0, "r1": r - 150.0, "colour": Color(0.08, 0.28, 0.14),
			"grove": -0.1}}


func build_terrain(path: PackedVector3Array, _plan: Dictionary) -> void:
	var z0 := Z_RIDGE - 120.0
	var z1 := finish_z + 260.0
	var mi := MeshInstance3D.new()
	mi.name = "Terrain"
	mi.mesh = TerrainBuilder.build(Callable(self, "ground"), X_HALF, z0, z1, CELL_T, 24.0)
	_hinfo = TerrainBuilder.last_info
	var mat := GroundMaterials.snow({"old_tracks": 1.0, "rock_paint": 1.0, "far_rock_x": FACE_W + 70.0, "rock_a": Color(0.46, 0.41, 0.36),
			"rock_b": Color(0.19, 0.17, 0.16), "rock_start": 0.36, "rock_end": 0.52})
	mi.material_override = mat
	host.add_child(mi)
	terrain_rect = Rect2(-X_HALF, z0, 2.0 * X_HALF, z1 - z0)
	terrain_material = mat
	# where the rock shows whatever the slope: along the cliffs, on the islands
	ground_mask = GroundMask.new()
	ground_mask.setup(terrain_rect, 0.6)
	var red := Color(1, 0, 0)
	var prng := RandomNumberGenerator.new()
	prng.seed = 515 + host.world_seed
	# the cliffs: irregular patches of rock along the band, wider here, broken there
	for k in _bz.size():
		var x := -X_HALF
		while x <= X_HALF:
			if band_rock(k, x) > 0.5:
				var r := 2.5 + 5.5 * maxf(_n_band.get_noise_2d(x * 0.6, k * 91.0) + 0.3, 0.0)
				ground_mask.add_disc(Vector2(x + prng.randf_range(-1.0, 1.0), band_z(k, x) + prng.randf_range(-2.0, 2.5)), r, red)
			x += 3.0
	for o in _isl:
		ground_mask.add_disc(Vector2(o.x, o.y), o.z * 0.9, red)
	# rock showing on the crests of the biggest spines
	var gz := 40.0
	while gz < face_end:
		var gx := -FACE_W
		while gx < FACE_W:
			var r := clampf(1.0 - 1.7 * absf(_n_cross.get_noise_2d(gx, gz * 0.22)), 0.0, 1.0)
			if r > 0.93 and _n_bump.get_noise_2d(gx * 0.7, gz * 0.7) > 0.15:
				ground_mask.add_disc(Vector2(gx, gz), prng.randf_range(2.0, 4.0), red)
			gx += 5.0
		gz += 5.0
	# no rock on the subject's line (blue: the snow shader keeps its streaks of rock off it)
	ground_mask.add_band(RoadBuilder.sample_curve(host.make_curve(path), 3.0), 6.0, Color(0, 0, 1))
	host.add_child(ground_mask)
	ground_mask.bind(mat)


## The relief itself hides the subject behind a roll, a spine or the lip of a cliff (the detailed terrain only;
## the last 3 m before the subject are its own ground).
func extra_occlusion(from: Vector3, to: Vector3) -> bool:
	if _hinfo.is_empty():
		return false
	var d := to - from
	var flat := Vector2(d.x, d.z).length()
	if flat < 4.0:
		return false
	var steps := clampi(int(flat / 2.5), 2, 90)
	var t_max := 1.0 - 3.0 / flat
	for k in range(1, steps):
		var t := float(k) / steps
		if t > t_max:
			break
		var p := from + d * t
		var h := TerrainBuilder.height_in(_hinfo, p.x, p.z)
		if not is_nan(h) and h > p.y + 0.15:
			return true
	return false


# --- Scenery -------------------------------------------------------------------------------------

func populate(path: PackedVector3Array, drone: PackedVector3Array, _plan: Dictionary, legacy: bool) -> void:
	_index(path, drone, legacy)
	_index_path(path)
	var rng := RandomNumberGenerator.new()
	rng.seed = 61 + host.world_seed
	_start_area(path, rng)
	_finish_area(path, rng)
	_band_rocks(rng)
	_rock_islands(rng)
	_flank_rocks(rng)
	_boulders(rng)
	_trees(rng)
	if not legacy:
		var count := roundi(float(host.matrix.params.occlusion) * 6.0)
		var fr: Array = []
		for k in count:
			fr.append((k + 1.0) / (count + 1.0))
		host.add_los_occluders(fr)
	PropFactory.build_forest(host, _tree_pos, _tree_scale, Color(0.08, 0.28, 0.14), 13)


func _index_path(path: PackedVector3Array) -> void:
	_path_cells.clear()
	for p in path:
		var c := int(floorf(p.z / CELL))
		if not _path_cells.has(c):
			_path_cells[c] = PackedVector2Array()
		var arr: PackedVector2Array = _path_cells[c]
		arr.append(Vector2(p.x, p.z))
		_path_cells[c] = arr


## True within r metres (horizontally) of the subject's path.
func _near_path(x: float, z: float, r: float) -> bool:
	var q := Vector2(x, z)
	for c in range(int(floorf((z - r) / CELL)), int(floorf((z + r) / CELL)) + 1):
		if not _path_cells.has(c):
			continue
		for p in _path_cells[c]:
			if p.distance_squared_to(q) < r * r:
				return true
	return false


func _in_crowd_spot(x: float, z: float, margin: float) -> bool:
	for r in _crowd_spots:
		if (r as Rect2).grow(margin).has_point(Vector2(x, z)):
			return true
	return false


## Something of radius r and height h may stand at (x, z): off the path, the drone's flight, the lines of sight.
func _free(x: float, z: float, r: float, h: float, path_margin := 4.0) -> bool:
	if _near_path(x, z, r + path_margin) or _near_sight(x, z, r + 1.0):
		return false
	return not _in_flight(x, z, r + 1.5, ground(x, z) + h)


## Rocks along the cliffs of the bands: a row of big blocks in the cliff face (its rock looks broken, not smooth).
func _band_rocks(rng: RandomNumberGenerator) -> void:
	for k in _bz.size():
		var x := -FACE_W - 10.0
		while x < FACE_W + 10.0:
			var rock := band_rock(k, x)
			var drop := _bdrop[k]
			var s := drop * rng.randf_range(0.28, 0.42)
			if rock > 0.9 and rng.randf() < 0.55:
				var zb := band_z(k, x) + rng.randf_range(-1.0, 2.5)
				if _free(x, zb, s, s * 1.4, 6.0):
					var g := Vector3(x, ground(x, zb) - s * 0.55, zb)
					var size := Vector3(s * rng.randf_range(1.2, 1.8), s * rng.randf_range(0.5, 0.75), s * rng.randf_range(0.7, 1.0))
					PropFactory.add_rock(host, g, size)
					host.add_cylinder_occluder(g, maxf(size.x, size.z) * 0.8, size.y * 1.1)
			x += s * rng.randf_range(1.5, 4.0) + 3.0


## The islands of rock on the face: a few blocks breaking out of their mound.
func _rock_islands(rng: RandomNumberGenerator) -> void:
	for o in _isl:
		for _r in rng.randi_range(2, 5):
			var x := o.x + rng.randf_range(-0.6, 0.6) * o.z
			var z := o.y + rng.randf_range(-0.6, 0.6) * o.z
			var s := rng.randf_range(1.4, 4.0)
			if not _free(x, z, s, s * 1.3, 6.0):
				continue
			var g := Vector3(x, ground(x, z) - s * 0.45, z)
			var size := Vector3(s * rng.randf_range(1.0, 1.5), s * rng.randf_range(0.5, 0.8), s)
			PropFactory.add_rock(host, g, size)
			host.add_cylinder_occluder(g, maxf(size.x, size.z) * 0.8, size.y * 1.0)


## The rocky ridges on both sides of the face: big blocks and buttresses.
func _flank_rocks(rng: RandomNumberGenerator) -> void:
	for _i in 110:
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var x := side * rng.randf_range(FACE_W - 15.0, X_HALF - 15.0)
		var z := rng.randf_range(Z_RIDGE - 60.0, face_end + 120.0)
		var s := rng.randf_range(3.0, 9.0)
		if not _free(x, z, s, s * 1.3, 8.0):
			continue
		var g := Vector3(x, ground(x, z) - s * 0.35, z)
		PropFactory.add_rock(host, g, Vector3(s * rng.randf_range(1.0, 1.6), s * rng.randf_range(0.7, 1.2), s))
		host.add_cylinder_occluder(g, s * 1.1, s * 1.1)


## Small stones sticking out of the snow here and there (no occluder: too small to hide a skier).
func _boulders(rng: RandomNumberGenerator) -> void:
	var grounds := PackedVector3Array()
	var sizes := PackedFloat32Array()
	var amount := int(220 * GraphicsSettings.detail_amount())
	for _i in amount:
		var x := rng.randf_range(-FACE_W, FACE_W)
		var z := rng.randf_range(10.0, face_end + 150.0)
		var s := rng.randf_range(0.35, 1.2)
		if _near_path(x, z, 3.0) or _in_flight(x, z, 2.0, ground(x, z) + 1.5):
			continue
		grounds.append(Vector3(x, ground(x, z) - s * 0.25, z))
		sizes.append(s)
	Rocks.scatter(host, grounds, sizes, 4100 + host.world_seed)


## Spruces at the foot of the face and around the finish basin, in groves.
func _trees(rng: RandomNumberGenerator) -> void:
	var placed := 0
	var tries := 0
	while placed < 170 and tries < 2500:
		tries += 1
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var x := side * rng.randf_range(60.0, X_HALF - 10.0)
		var z := rng.randf_range(face_end + 70.0, finish_z + 250.0)
		if FarScenery.grove_at(x * 2.0, z * 2.0) < 0.1 - 0.004 * (absf(x) - 60.0):
			continue
		var s := rng.randf_range(0.9, 1.7)
		if _near_path(x, z, 14.0) or _near_sight(x, z, PropFactory.CONE_R[0] * s + 1.0) or _in_crowd_spot(x, z, 3.0):
			continue
		var g := ground(x, z)
		if _in_flight(x, z, PropFactory.CONE_R[0] * s + 2.5, g + PropFactory.TREE_HEIGHT * s):
			continue
		_add_tree(Vector3(x, g, z), s)
		placed += 1


# --- Start and finish ----------------------------------------------------------------------------

## The start on the ridge: a gate with its banner, feather flags, a few officials and riders waiting.
func _start_area(path: PackedVector3Array, rng: RandomNumberGenerator) -> void:
	var p := path[0]
	var crowd := Crowd.new()
	crowd.host = host
	var gz := p.z + 3.0
	var g := ground(p.x, gz)
	if not _in_flight(p.x, gz, 4.5, g + 3.4):
		var dark := PathSubject.make_mat(Color(0.06, 0.07, 0.12), 0.6)
		for sd in [-2.6, 2.6]:
			_box_at(Vector3(0.14, 3.0, 0.14), Vector3(p.x + sd, ground(p.x + sd, gz) + 1.5, gz), dark)
		_box_at(Vector3(5.4, 0.7, 0.08), Vector3(p.x, g + 2.75, gz), PathSubject.make_mat(Color(0.95, 0.95, 0.95), 0.6))
		_box_at(Vector3(5.4, 0.18, 0.09), Vector3(p.x, g + 2.35, gz), PathSubject.make_mat(Color(0.95, 0.35, 0.05), 0.6))
	for k in 6:
		var a := float(k) / 6.0 * TAU
		var fx := p.x + cos(a) * rng.randf_range(6.0, 9.0)
		var fz := p.z - 4.0 + sin(a) * rng.randf_range(3.0, 6.0)
		if fz > p.z + 1.0 or not _free(fx, fz, 0.6, 5.0, 2.5):
			continue
		crowd.add_feather(Vector3(fx, ground(fx, fz), fz), Vector3(0, 0, 1), rng)
	for k in 9:
		var ox := rng.randf_range(4.0, 12.0) * (-1.0 if k % 2 == 0 else 1.0)
		var px := p.x + ox
		var pz := p.z - rng.randf_range(2.0, 10.0)
		if not _free(px, pz, 0.5, 2.0, 2.0):
			continue
		crowd.add_person(Vector3(px, ground(px, pz), pz), Vector3(-ox * 0.2, 0.0, 1.0), rng, false)
	_crowd_spots.append(Rect2(p.x - 14.0, p.z - 12.0, 28.0, 14.0))
	host.add_child(crowd)
	crowd.build(700.0)


## The finish in the basin: a line, an inflatable arch, spectators behind banners on both sides of the run-out,
## feather flags, and a group watching from the side of the apron.
func _finish_area(path: PackedVector3Array, rng: RandomNumberGenerator) -> void:
	var fp := _path_point_at_z(path, finish_z)
	# line across the run-out
	var xforms: Array[Transform3D] = []
	var x := fp.x - 12.0
	while x < fp.x + 12.0:
		xforms.append(Transform3D(Basis(), Vector3(x + 0.5, ground(x + 0.5, finish_z) + 0.03, finish_z)))
		x += 1.0
	var box := BoxMesh.new()
	box.size = Vector3(1.02, 0.02, 0.5)
	box.material = PathSubject.make_mat(Color(0.05, 0.25, 0.85), 0.9)
	_multimesh(box, xforms, false)
	# inflatable arch (half of a torus standing on the snow), not where the drone flies
	var arch_ok := true
	for k in 17:
		var a := PI * k / 16.0
		var ax := fp.x + cos(a) * 7.0
		if _in_flight(ax, finish_z, 4.5, ground(ax, finish_z) + sin(a) * 7.0 + 2.0):
			arch_ok = false
	if arch_ok:
		var tm := TorusMesh.new()
		tm.inner_radius = 6.2
		tm.outer_radius = 7.8
		tm.rings = 48
		tm.ring_segments = 14
		var mi := MeshInstance3D.new()
		mi.mesh = tm
		mi.material_override = PathSubject.make_mat(Color(0.05, 0.07, 0.16), 0.45)
		mi.position = Vector3(fp.x, ground(fp.x, finish_z), finish_z)
		mi.rotation.x = PI * 0.5
		host.add_child(mi)
		_box_at(Vector3(6.0, 1.1, 0.25), Vector3(fp.x, ground(fp.x, finish_z) + 7.4, finish_z - 0.5),
				PathSubject.make_mat(Color(0.95, 0.95, 0.95), 0.6))
		_box_at(Vector3(6.0, 0.2, 0.26), Vector3(fp.x, ground(fp.x, finish_z) + 7.0, finish_z - 0.5),
				PathSubject.make_mat(Color(0.95, 0.35, 0.05), 0.6))
		for sd in [-1.0, 1.0]:
			host.add_cylinder_occluder(Vector3(fp.x + sd * 6.6, ground(fp.x + sd * 6.6, finish_z), finish_z), 0.9, 4.0)
	# spectators along both sides of the run-out, behind banners
	var dens := Crowd.density()
	for sd in [-1.0, 1.0]:
		var crowd := Crowd.new()
		crowd.host = host
		var z := finish_z - 50.0
		while z < finish_z + 22.0:
			var c := _path_point_at_z(path, z)
			for r in 5:
				if rng.randf() > dens:
					continue
				var px: float = c.x + sd * (15.0 + r * 0.95 + rng.randf_range(-0.15, 0.15))
				var pz := z + rng.randf_range(-0.25, 0.25) + (0.4 if r % 2 == 1 else 0.0)
				if not _free(px, pz, 0.4, 2.2, 6.0):
					continue
				crowd.add_person(Vector3(px, ground(px, pz), pz), Vector3(-sd, 0.0, -0.6).normalized(), rng)
			z += 0.85
		var zb := finish_z - 48.0
		while zb < finish_z + 20.0:
			var c0 := _path_point_at_z(path, zb - 1.4)
			var c1 := _path_point_at_z(path, zb + 1.4)
			var a0 := Vector3(c0.x + sd * 13.0, 0.0, zb - 1.4)
			var a1 := Vector3(c1.x + sd * 13.0, 0.0, zb + 1.4)
			a0.y = ground(a0.x, a0.z) - 0.05
			a1.y = ground(a1.x, a1.z) - 0.05
			if _free((a0.x + a1.x) * 0.5, zb, 1.5, 1.2, 5.0):
				crowd.add_banner(a0, a1, Vector3(-sd, 0.0, 0.0), rng)
			zb += 2.9
		var zf := finish_z - 46.0
		while zf < finish_z + 18.0:
			var cf := _path_point_at_z(path, zf)
			var fx: float = cf.x + sd * 12.2
			if _free(fx, zf, 0.6, 5.0, 4.0):
				crowd.add_feather(Vector3(fx, ground(fx, zf), zf), Vector3(-sd, 0.0, 0.0), rng)
			zf += 13.0
		var cr := _path_point_at_z(path, finish_z - 20.0)
		_crowd_spots.append(Rect2(minf(cr.x + sd * 11.0, cr.x + sd * 21.0), finish_z - 48.0, 10.0, 72.0))
		if not crowd.is_empty():
			host.add_child(crowd)
			crowd.build()
		else:
			crowd.free()
	# a group watching the face from the side of the apron
	var watch := Crowd.new()
	watch.host = host
	var wz := face_end + rng.randf_range(70.0, 110.0)
	var wc := _path_point_at_z(path, wz)
	var wside := -1.0 if wc.x > 0.0 else 1.0
	var wx: float = wc.x + wside * rng.randf_range(45.0, 70.0)
	for _i in int(70 * dens):
		var px := wx + rng.randf_range(-9.0, 9.0)
		var pz := wz + rng.randf_range(-4.0, 4.0)
		if _free(px, pz, 0.4, 2.2, 8.0):
			watch.add_person(Vector3(px, ground(px, pz), pz), Vector3(-wside * 0.4, 0.0, -1.0), rng)
	_crowd_spots.append(Rect2(wx - 10.0, wz - 5.0, 20.0, 10.0))
	if not watch.is_empty():
		host.add_child(watch)
		watch.build()
	else:
		watch.free()


## The path point where the path first reaches z (its last point beyond).
func _path_point_at_z(path: PackedVector3Array, z: float) -> Vector3:
	for i in range(1, path.size()):
		if path[i].z >= z:
			var a := path[i - 1]
			var b := path[i]
			return a.lerp(b, clampf((z - a.z) / maxf(b.z - a.z, 0.001), 0.0, 1.0))
	return path[path.size() - 1]

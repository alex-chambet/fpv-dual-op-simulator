class_name CircuitScenery
extends RefCounted
## Builds the Nürburgring Grand-Prix-Strecke in 3D from a CircuitLayout: the ground of the Eifel,
## the asphalt and its white lines, the red and white kerbs, the asphalt run-off and the gravel
## traps, the guardrails and the debris fences, the advertising hoardings and the marshal posts,
## the pit building and the pit lane along the start / finish straight with the main grandstand
## facing it, the start / finish gantry, the Dunlop bridge, the grandstands of the Mercedes-Arena
## and of the big corners with their spectators, and the spruce forest around the circuit.
##
## It is used by both the training environment (EnvCircuit) and the sandbox (CircuitWorld), so the
## circuit looks the same in both.

const RUNOFF_BASE := 5.0     ## width of the painted / asphalt strip along the track everywhere, m
const RUNOFF_CORNER := 22.0  ## ...and on the outside of a corner, m
const BARRIER_GAP := 2.5     ## between the edge of the run-off and the guardrail, m
const FENCE_HEIGHT := 3.6    ## debris fence above the guardrail, m
const PIT_LANE := 20.0       ## offset of the pit lane from the centre line, m
const STAND_SETBACK := 7.0   ## between the guardrail and the first row of a grandstand, m
const STAND_CORRIDOR := 41.0 ## ...and never closer than this to the centre line (the drone's room), m
const PIT_BUILDING := 42.0   ## offset of the front of the pit garages from the centre line, m
const LOW_STRUCTURE := 2.0   ## a structure lower than this does not push the drone up, m
const TREE_CLEAR := 26.0     ## no tree within this distance of the guardrails, m

var host: Node3D
var layout: CircuitLayout
var rng := RandomNumberGenerator.new()
## Obstacles of the world: {c: Vector3 (ground centre), yaw, hx, hz, h}. Used by the sandbox drone
## and, through EnvCircuit, by the line-of-sight tests.
var boxes: Array[Dictionary] = []
var mask: GroundMask
var terrain_material: Material
var terrain_rect := Rect2()
## Height of the structures above the ground, on a coarse grid (the drone planner stays above it).
var _tops := PackedFloat32Array()
var _tx0 := 0.0
var _tz0 := 0.0
var _tw := 0
var _th := 0
const TOP_CELL := 8.0

var _runoff_l := PackedFloat32Array()
var _runoff_r := PackedFloat32Array()
var _kerb_l := PackedByteArray()
var _kerb_r := PackedByteArray()
var _ground_params := {}
var _pit_from := 0.0
var _pit_to := 0.0

static var _mats := {}


func build(h: Node3D, l: CircuitLayout, seed_value := 7) -> void:
	host = h
	layout = l
	rng.seed = seed_value
	_pit_from = -0.068 * layout.lap_length   # about 350 m before the line at full scale
	_pit_to = 0.050 * layout.lap_length
	_zones()
	_terrain()
	_surface()
	_barriers()
	_pit_complex()
	_structures()
	_vegetation()


# --- Where the run-off and the kerbs go ---------------------------------------------------------

## For every point of the centre line: how wide the run-off is on each side (wide on the outside of
## a corner, narrow along a straight) and where the kerbs are (inside of a corner, and the exit).
func _zones() -> void:
	var n := layout.centre.size()
	var k := CircuitTrack.signed_curvature(layout.centre)
	var k_thresh := 1.0 / (0.043 * layout.lap_length)
	_runoff_l.resize(n)
	_runoff_r.resize(n)
	_kerb_l.resize(n)
	_kerb_r.resize(n)
	for i in n:
		_runoff_l[i] = RUNOFF_BASE
		_runoff_r[i] = RUNOFF_BASE
		_kerb_l[i] = 0
		_kerb_r[i] = 0
	var i0 := -1
	for c in n * 2:
		var i := c % n
		var strong: bool = absf(k[i]) > k_thresh
		if strong and i0 < 0:
			i0 = c
		elif not strong and i0 >= 0:
			var span := c - i0
			if span * layout.step >= 12.0:
				_mark_corner(i0, c - 1, k)
			i0 = -1
			if c >= n:
				break
	_fit_runoff()


## The lap folds back on itself (the Mercedes-Arena is an omega whose two legs are only a few tens of
## metres apart): a run-off as wide as the one of an open corner would put its guardrail on the other
## leg. Each side is narrowed until its barrier stands clear of every part of the track.
func _fit_runoff() -> void:
	var n := layout.centre.size()
	var hw := layout.half_width
	var clear := hw + 7.0
	for i in n:
		for side in [-1.0, 1.0]:
			var w: float = _runoff_l[i] if side < 0.0 else _runoff_r[i]
			while w > 1.5:
				var off := layout.safe_offset(i, side * (hw + w + BARRIER_GAP + 1.0))
				var p := layout.centre[i] + layout.normals[i] * off
				if layout.distance_to_track(p.x, p.y) > clear:
					break
				w -= 1.5
			if side < 0.0:
				_runoff_l[i] = w
			else:
				_runoff_r[i] = w
	# and smooth the two profiles so the edge of the run-off has no step
	_runoff_l = _smoothed(_runoff_l, 4)
	_runoff_r = _smoothed(_runoff_r, 4)


static func _smoothed(a: PackedFloat32Array, passes: int) -> PackedFloat32Array:
	var n := a.size()
	var cur := a
	for _p in passes:
		var s := cur.duplicate()
		for i in n:
			s[i] = (cur[(i - 1 + n) % n] + 2.0 * cur[i] + cur[(i + 1) % n]) * 0.25
		cur = s
	return cur


func _mark_corner(a: int, b: int, k: PackedFloat32Array) -> void:
	var n := layout.centre.size()
	var dir := 0.0
	for c in range(a, b + 1):
		dir += k[c % n]
	var left := dir > 0.0          # the corner turns left: inside = left, outside = right
	var span := b - a
	var pad := roundi(30.0 / layout.step)
	for c in range(a - pad, b + pad * 2 + 1):
		var i := (c % n + n) % n
		var t := clampf(float(c - a + pad) / float(span + pad * 3), 0.0, 1.0)
		var w := RUNOFF_CORNER * sin(PI * t)
		if left:
			_runoff_r[i] = maxf(_runoff_r[i], RUNOFF_BASE + w)
		else:
			_runoff_l[i] = maxf(_runoff_l[i], RUNOFF_BASE + w)
	# inside kerb over the whole corner, outside kerb on the exit half
	for c in range(a, b + 1):
		var i := (c % n + n) % n
		if left:
			_kerb_l[i] = 1
		else:
			_kerb_r[i] = 1
	for c in range(a + span / 2, b + maxi(span / 2, 4) + 1):
		var i := (c % n + n) % n
		if left:
			_kerb_r[i] = 1
		else:
			_kerb_l[i] = 1


# --- Ground --------------------------------------------------------------------------------------

func _terrain() -> void:
	var b := layout.bounds.grow(190.0)
	var x_half := maxf(absf(b.position.x), absf(b.end.x)) + 10.0
	var mi := MeshInstance3D.new()
	mi.name = "Terrain"
	mi.mesh = TerrainBuilder.build(Callable(layout, "ground"), x_half, b.position.y, b.end.y, 6.0, 34.0)
	_ground_params = {"grass_a": Color(0.15, 0.3, 0.09), "grass_b": Color(0.3, 0.42, 0.14),
			"dry": Color(0.45, 0.46, 0.25), "dry_amount": 0.18, "dirt_amount": 0.12, "fields": 0.0}
	var mat := GroundMaterials.terrain(_ground_params)
	mi.material_override = mat
	host.add_child(mi)
	terrain_rect = Rect2(-x_half, b.position.y, 2.0 * x_half, b.size.y)
	terrain_material = mat
	mask = GroundMask.new()
	mask.setup(terrain_rect)
	var centre := layout.centre3d()
	mask.add_band(centre, 52.0, Color(0, 1, 0))
	mask.add_band(centre, layout.half_width + RUNOFF_BASE + 4.0, Color(0, 1, 1))
	mask.add_band(centre, layout.half_width + 0.6, Color(1, 1, 1))
	host.add_child(mask)
	mask.bind(mat)
	# the height of the structures starts empty
	var tb := terrain_rect.grow(40.0)
	_tx0 = tb.position.x
	_tz0 = tb.position.y
	_tw = ceili(tb.size.x / TOP_CELL) + 1
	_th = ceili(tb.size.y / TOP_CELL) + 1
	_tops.resize(_tw * _th)


func grass_params() -> Dictionary:
	var p := _ground_params.duplicate()
	p.merge({"height": 0.26, "density": 0.9, "crops": false, "flowers": 0.02, "max_slope": 0.45})
	return p


# --- The track itself ------------------------------------------------------------------------

func _surface() -> void:
	var n := layout.centre.size()
	var hw := layout.half_width
	# run-off (grey asphalt) on both sides, then the gravel of the fastest corners, then the asphalt
	var ro_in := PackedFloat32Array()
	var ro_out := PackedFloat32Array()
	ro_in.resize(n)
	ro_out.resize(n)
	for i in n:
		ro_in[i] = -hw - _runoff_l[i]
		ro_out[i] = hw + _runoff_r[i]
	_band(ro_in, _const_offsets(-hw), 0.015, _runoff_mat(), 0.09)
	_band(_const_offsets(hw), ro_out, 0.015, _runoff_mat(), 0.09)
	# asphalt
	_band(_const_offsets(-hw), _const_offsets(hw), 0.05, GroundMaterials.asphalt({"half_width": hw}), 0.1)
	# white lines along both edges
	var paint := GroundMaterials.paint()
	_band(_const_offsets(-hw + 0.02), _const_offsets(-hw + 0.17), 0.07, paint, 1.0)
	_band(_const_offsets(hw - 0.17), _const_offsets(hw - 0.02), 0.07, paint, 1.0)
	_kerbs()
	_start_line()
	_pit_lane()


func _const_offsets(v: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(layout.centre.size())
	for i in out.size():
		out[i] = v
	return out


## A flat band between two lateral offsets of the centre line, `y` above the track surface.
func _band(inner: PackedFloat32Array, outer: PackedFloat32Array, y: float, mat: Material,
		uv_per_m := 0.1, from := -1, to := -1) -> MeshInstance3D:
	var n := layout.centre.size()
	var i0 := 0 if from < 0 else from
	var i1 := n if to < 0 else to
	if i1 - i0 < 2:
		return null
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var run := 0.0
	var prev := Vector2.ZERO
	for c in range(i0, i1 + 1):
		var i := (c % n + n) % n
		var j := ((c + 1) % n + n) % n
		if c > i0:
			run += layout.centre[i].distance_to(prev)
		prev = layout.centre[i]
		if c == i1:
			break
		var quad := []
		for pair in [[i, inner[i]], [i, outer[i]], [j, inner[j]], [j, outer[j]]]:
			var idx: int = pair[0]
			var off: float = layout.safe_offset(idx, pair[1])
			var p := layout.centre[idx] + layout.normals[idx] * off
			quad.append(Vector3(p.x, layout.surface[idx] + y, p.y))
		var seg := layout.centre[i].distance_to(layout.centre[j])
		var uv := [Vector2(0.0, run * uv_per_m), Vector2(1.0, run * uv_per_m),
				Vector2(0.0, (run + seg) * uv_per_m), Vector2(1.0, (run + seg) * uv_per_m)]
		for idx in [0, 2, 1, 1, 2, 3]:
			st.set_normal(Vector3.UP)
			st.set_uv(uv[idx])
			st.add_vertex(quad[idx])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	host.add_child(mi)
	return mi


## Red and white kerbs: a strip just outside the white line, raised at its outer edge.
func _kerbs() -> void:
	var n := layout.centre.size()
	var hw := layout.half_width
	var kw := layout.kerb_width
	for side in [-1.0, 1.0]:
		var flags: PackedByteArray = _kerb_l if side < 0.0 else _kerb_r
		var c := 0
		while c < n:
			if flags[c] == 0:
				c += 1
				continue
			var a := c
			while c < n and flags[c] == 1:
				c += 1
			if (c - a) * layout.step < 6.0:
				continue
			var inner := _const_offsets(side * hw)
			var outer := _const_offsets(side * (hw + kw))
			var strip := _band(inner if side > 0.0 else outer, outer if side > 0.0 else inner,
					0.06, _kerb_mat(), 1.0, a, c)
			if strip != null:
				strip.name = "Kerb"


## Start / finish line, the grid boxes behind it and the gantry over the track.
func _start_line() -> void:
	var hw := layout.half_width
	var paint := GroundMaterials.paint()
	_s_band(-1.2, 1.2, -hw + 0.2, hw - 0.2, 0.09, paint)
	# the grid: two columns of boxes before the line
	var dark := _mat("grid", Color(0.9, 0.9, 0.88), 0.7)
	var s := -8.0
	var k := 0
	while s > -0.034 * layout.lap_length:
		var lat := (-hw * 0.45) if k % 2 == 0 else (hw * 0.45)
		_s_band(s - 5.0, s - 4.85, lat - 1.6, lat + 1.6, 0.085, dark)
		_s_band(s - 5.0, s, lat - 1.6, lat - 1.45, 0.085, dark)
		_s_band(s - 5.0, s, lat + 1.45, lat + 1.6, 0.085, dark)
		s -= 8.0
		k += 1
	_gantry(0.0)


## A painted rectangle given in lap distance and lateral offset.
func _s_band(s0: float, s1: float, lat0: float, lat1: float, y: float, mat: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := maxi(2, roundi(absf(s1 - s0) / 2.0))
	for i in steps:
		var sa := lerpf(s0, s1, float(i) / steps)
		var sb := lerpf(s0, s1, float(i + 1) / steps)
		var quad := []
		for pair in [[sa, lat0], [sa, lat1], [sb, lat0], [sb, lat1]]:
			var p := layout.point_at(pair[0])
			var nrm := layout.normal_at(pair[0])
			quad.append(Vector3(p.x + nrm.x * pair[1], p.y + y, p.z + nrm.y * pair[1]))
		for idx in [0, 2, 1, 1, 2, 3]:
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(0.0, 0.0))
			st.add_vertex(quad[idx])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	host.add_child(mi)


## The gantry over the start / finish line: two legs and a beam with the lights.
func _gantry(s: float) -> void:
	var hw := layout.half_width
	var steel := _mat("steel", Color(0.32, 0.34, 0.38), 0.5, 0.5)
	var dark := _mat("gantry_dark", Color(0.08, 0.08, 0.09), 0.6)
	var left := layout.side_point(s, -hw - 2.4)
	var right := layout.side_point(s, hw + 2.4)
	var top := maxf(left.y, right.y) + 8.0
	for p in [left, right]:
		_box_at(Vector3(1.0, top - p.y, 1.0), Vector3(p.x, (p.y + top) * 0.5, p.z), steel)
		_obstacle(Vector3(p.x, p.y, p.z), 0.0, 0.8, 0.8, top - p.y)
	var mid := (left + right) * 0.5
	var width := left.distance_to(right)
	var dir := layout.dir_at(s)
	var yaw := atan2(dir.x, dir.y)
	var beam := _box_at(Vector3(width, 1.5, 0.9), Vector3(mid.x, top - 0.75, mid.z), steel)
	beam.rotation.y = yaw
	var lights := _box_at(Vector3(width * 0.45, 0.8, 0.35), Vector3(mid.x, top - 2.1, mid.z), dark)
	lights.rotation.y = yaw
	_top_box(Vector3(mid.x, 0.0, mid.z), width * 0.6, 2.0, top)


## The pit lane: a parallel strip of asphalt with its white lines, behind the pit wall.
func _pit_lane() -> void:
	var paint := GroundMaterials.paint()
	var a := PackedFloat32Array()
	var b := PackedFloat32Array()
	var n := layout.centre.size()
	a.resize(n)
	b.resize(n)
	for i in n:
		a[i] = PIT_LANE - 6.0
		b[i] = PIT_LANE + 6.0
	var i0 := layout.index_at(_pit_from)
	var i1 := i0 + roundi((_pit_to - _pit_from) / layout.step)
	_band(a, b, 0.04, GroundMaterials.asphalt({"half_width": 6.0}), 0.1, i0, i1)
	var e0 := _const_offsets(PIT_LANE - 6.0)
	var e1 := _const_offsets(PIT_LANE - 5.85)
	_band(e0, e1, 0.06, paint, 1.0, i0, i1)


# --- Guardrails, fences, hoardings ---------------------------------------------------------------

func _barriers() -> void:
	var n := layout.centre.size()
	var hw := layout.half_width
	for side in [-1.0, 1.0]:
		var off := PackedFloat32Array()
		off.resize(n)
		for i in n:
			var ro: float = _runoff_l[i] if side < 0.0 else _runoff_r[i]
			off[i] = side * (hw + ro + BARRIER_GAP)
		_guardrail(_smoothed(off, 4), side)


## Steel guardrail (two rails on posts) with a debris fence above it, and advertising hoardings in
## front of it. Built as one mesh per side, plus multimeshes for the posts and the hoardings.
func _guardrail(off: PackedFloat32Array, side: float) -> void:
	var n := layout.centre.size()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var fence := SurfaceTool.new()
	fence.begin(Mesh.PRIMITIVE_TRIANGLES)
	var posts: Array[Transform3D] = []
	var boards: Array[Transform3D] = []
	var tints := PackedColorArray()
	var palette := [Color(0.85, 0.08, 0.06), Color(0.1, 0.3, 0.75), Color(0.93, 0.93, 0.93),
			Color(0.95, 0.72, 0.05), Color(0.1, 0.5, 0.25)]
	var run := 0.0
	for i in n:
		var j := (i + 1) % n
		var pa := _rail_point(off, i)
		var pb := _rail_point(off, j)
		var seg := Vector2(pb.x - pa.x, pb.z - pa.z).length()
		var nrm := Vector3(pb.z - pa.z, 0.0, pa.x - pb.x).normalized() * side
		for y0 in [0.42, 0.72]:
			_quad(st, pa + Vector3(0, y0, 0), pb + Vector3(0, y0, 0),
					pb + Vector3(0, y0 + 0.26, 0), pa + Vector3(0, y0 + 0.26, 0), nrm,
					Vector2(run, 0.0), Vector2(run + seg, 0.26))
		_quad(fence, pa + Vector3(0, 1.1, 0), pb + Vector3(0, 1.1, 0),
				pb + Vector3(0, 1.1 + FENCE_HEIGHT, 0), pa + Vector3(0, 1.1 + FENCE_HEIGHT, 0), nrm,
				Vector2(run, 0.0), Vector2(run + seg, FENCE_HEIGHT))
		if i % maxi(1, roundi(3.5 / layout.step)) == 0:
			posts.append(Transform3D(Basis().scaled(Vector3(1.0, 1.15, 1.0)), pa + Vector3(0, 0.57, 0)))
		if rng.randf() < 0.55:
			var along := (pb - pa).normalized()
			var right := Vector3(nrm.x, 0.0, nrm.z)
			boards.append(Transform3D(Basis(right, Vector3.UP, along),
					(pa + pb) * 0.5 + right * 0.35 + Vector3(0, 0.5, 0)))
			tints.append(palette[rng.randi() % palette.size()])
		run += seg
	var rail := MeshInstance3D.new()
	rail.name = "Guardrail"
	rail.mesh = st.commit()
	rail.material_override = _mat("rail", Color(0.62, 0.64, 0.67), 0.4, 0.7)
	host.add_child(rail)
	var fn := MeshInstance3D.new()
	fn.name = "DebrisFence"
	fn.mesh = fence.commit()
	fn.material_override = _fence_mat()
	fn.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	host.add_child(fn)
	var post := BoxMesh.new()
	post.size = Vector3(0.12, 1.0, 0.12)
	post.material = _mat("rail_post", Color(0.4, 0.42, 0.45), 0.6, 0.4)
	_multimesh(post, posts)
	if not boards.is_empty():
		var board := BoxMesh.new()
		board.size = Vector3(0.1, 0.9, layout.step * 0.88)
		_multimesh(board, boards, true, tints)


func _rail_point(off: PackedFloat32Array, i: int) -> Vector3:
	var p := layout.centre[i] + layout.normals[i] * layout.safe_offset(i, off[i])
	return Vector3(p.x, layout.ground(p.x, p.y), p.y)


# --- Buildings -----------------------------------------------------------------------------------

## The pit building, the pit wall and the main grandstand along the start / finish straight.
func _pit_complex() -> void:
	var grey := _mat("concrete", Color(0.62, 0.62, 0.6), 0.85)
	var dark := _mat("pit_dark", Color(0.18, 0.19, 0.22), 0.6)
	var white := _mat("pit_white", Color(0.88, 0.89, 0.9), 0.7)
	var glass := _mat("pit_glass", Color(0.1, 0.16, 0.2), 0.12, 0.6)
	# pit wall between the track and the pit lane
	var s := _pit_from
	while s < _pit_to:
		var p := layout.side_point(s, PIT_LANE - 7.5)
		var d := layout.dir_at(s)
		var w := _box_at(Vector3(0.4, 1.1, 6.0), p + Vector3(0, 0.55, 0), white)
		w.rotation.y = atan2(d.x, d.y)
		s += 6.0
	# the garages and the two floors above them, behind the pit lane
	var step := 9.0
	s = _pit_from
	while s < _pit_to:
		var p := layout.side_point(s, PIT_BUILDING)
		if layout.distance_to_track(p.x, p.z) < 34.0:
			s += step
			continue
		var d := layout.dir_at(s)
		var yaw := atan2(d.x, d.y)
		var g := _box_at(Vector3(13.0, 5.2, step * 0.97), p + Vector3(0, 2.6, 0), grey)
		g.rotation.y = yaw
		var door := _box_at(Vector3(0.4, 3.6, step * 0.72), p + Vector3(0, 1.8, 0) - Vector3(sin(yaw), 0, cos(yaw)) * 0.0, dark)
		door.position = p + Vector3(0, 1.8, 0) + Vector3(cos(yaw), 0.0, -sin(yaw)) * -6.4
		door.rotation.y = yaw
		var f1 := _box_at(Vector3(13.0, 3.2, step * 0.97), p + Vector3(0, 6.9, 0), white)
		f1.rotation.y = yaw
		var win := _box_at(Vector3(0.3, 1.9, step * 0.85), p + Vector3(0, 7.1, 0) + Vector3(cos(yaw), 0.0, -sin(yaw)) * -6.6, glass)
		win.rotation.y = yaw
		_obstacle(p, yaw, 6.6, step * 0.5, 8.6)
		s += step
	# main grandstand facing the pits, on the other side of the track
	_grandstand(-0.055 * layout.lap_length, 0.040 * layout.lap_length, -1.0, 8, true)


## The landmarks of the circuit: the big grandstand of the Mercedes-Arena, the stands of the main
## corners, the Dunlop bridge and the marshal posts.
func _structures() -> void:
	var lap := layout.lap_length
	var full := CircuitTrack.LAP_LENGTH
	for lm in CircuitTrack.LANDMARKS:
		var s: float = float(lm[0]) / full * lap
		match str(lm[1]):
			"arena":
				_grandstand(s - 0.030 * lap, s + 0.030 * lap, 1.0, 10, true)
			"stand":
				_grandstand(s - 0.016 * lap, s + 0.016 * lap, _outer_side(s), 6, false)
			"bridge":
				_bridge(s)
	_marshal_posts()
	_paddock()
	_castle()


## Paddock buildings behind the pits (the hospitality units of the Nürburgring).
func _paddock() -> void:
	var wall := _mat("paddock", Color(0.78, 0.78, 0.76), 0.85)
	var roof := _mat("paddock_roof", Color(0.3, 0.32, 0.35), 0.7)
	var s := _pit_from + 20.0
	while s < _pit_to - 20.0:
		var p := layout.side_point(s, PIT_BUILDING + 33.0 + rng.randf_range(-6.0, 6.0))
		if layout.distance_to_track(p.x, p.z) < 60.0:
			s += 20.0
			continue    # that spot is in the run-off of another corner of the lap
		var d := layout.dir_at(s)
		var yaw := atan2(d.x, d.y)
		var w := rng.randf_range(10.0, 16.0)
		var l := rng.randf_range(16.0, 30.0)
		var hgt := rng.randf_range(5.0, 8.0)
		var b := _box_at(Vector3(w, hgt, l), p + Vector3(0, hgt * 0.5, 0), wall)
		b.rotation.y = yaw
		var r := _box_at(Vector3(w + 0.8, 0.4, l + 0.8), p + Vector3(0, hgt + 0.2, 0), roof)
		r.rotation.y = yaw
		_obstacle(p, yaw, w * 0.5, l * 0.5, hgt + 0.5)
		s += rng.randf_range(34.0, 52.0)


## The tower of Nürburg castle on its hill, which overlooks the circuit.
func _castle() -> void:
	var b := layout.bounds
	var c := Vector2(b.position.x + b.size.x * 0.18, b.end.y + 128.0)
	if layout.distance_to_track(c.x, c.y) < 110.0:
		return
	var stone := _mat("castle", Color(0.52, 0.5, 0.46), 0.95)
	var roof := _mat("castle_roof", Color(0.32, 0.22, 0.2), 0.8)
	var g := layout.ground(c.x, c.y) + 16.0   # the castle sits on a knoll
	var knoll := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 26.0
	cyl.bottom_radius = 62.0
	cyl.height = 17.0
	cyl.radial_segments = 20
	knoll.mesh = cyl
	knoll.material_override = _mat("knoll", Color(0.24, 0.33, 0.14), 0.95)
	knoll.position = Vector3(c.x, g - 8.5, c.y)
	host.add_child(knoll)
	_box_at(Vector3(9.0, 17.0, 9.0), Vector3(c.x, g + 8.5, c.y), stone)
	_box_at(Vector3(10.4, 1.4, 10.4), Vector3(c.x, g + 17.4, c.y), stone)
	_box_at(Vector3(7.0, 5.0, 7.0), Vector3(c.x, g + 20.6, c.y), roof)
	for dx in [-14.0, 15.0]:
		_box_at(Vector3(7.0, 9.0, 11.0), Vector3(c.x + dx, g + 4.5, c.y + 6.0), stone)
	_obstacle(Vector3(c.x, g, c.y), 0.0, 14.0, 10.0, 23.0)


## Which side of the track is the outside of the corner at this lap distance (+1 = right).
func _outer_side(s: float) -> float:
	var i := layout.index_at(s)
	var k := CircuitTrack.signed_curvature(layout.centre)
	return 1.0 if k[i] > 0.0 else -1.0


## A tiered grandstand along the track between two lap distances, with its roof and its crowd.
## It is set back far enough (STAND_SETBACK) that the chase drone flies between the track and it
## rather than over its roof, as the grandstands of a real circuit sit behind the run-off.
func _grandstand(s0: float, s1: float, side: float, rows: int, roof: bool) -> void:
	var grey := _mat("stand", Color(0.52, 0.54, 0.57), 0.8)
	# never closer than STAND_CORRIDOR to the centre line: the chase drone works out to about 35 m
	# from the track, and a stand inside that would force it to climb over the roof (and lose the car)
	var base_off := maxf(layout.half_width + maxf(_runoff_at(s0, side), _runoff_at(s1, side))
			+ BARRIER_GAP + STAND_SETBACK, STAND_CORRIDOR)
	# the lap folds back on itself: the chosen side may put the stand beside another corner. Take the
	# side with the most room, and build no stand at all when neither side has any.
	var room := _stand_room(s0, s1, side, base_off)
	var other := _stand_room(s0, s1, -side, base_off)
	if other > room + 6.0:
		side = -side
		room = other
	if room < STAND_CORRIDOR - 8.0:
		return
	var crowd := Crowd.new()
	crowd.host = host
	var dens := Crowd.density()
	var length := absf(s1 - s0)
	var steps := maxi(4, roundi(length / 5.0))
	for r in rows:
		var off := base_off + r * 1.5
		var h := 0.7 + r * 0.95
		for i in steps:
			var sa := lerpf(s0, s1, float(i) / steps)
			var sb := lerpf(s0, s1, float(i + 1) / steps)
			var pa := layout.side_point(sa, side * off)
			var pb := layout.side_point(sb, side * off)
			var mid := (pa + pb) * 0.5
			var d := pb - pa
			var tier := _box_at(Vector3(1.5, h, d.length() * 1.05), mid + Vector3(0, h * 0.5 - 0.2, 0), grey)
			tier.rotation.y = atan2(d.x, d.z)
			var face := Vector3(-side * layout.normal_at(sa).x, 0.0, -side * layout.normal_at(sa).y)
			var people := roundi(d.length() / 0.85)
			for k in people:
				if rng.randf() > dens:
					continue
				var t := (k + 0.5) / float(people)
				var pp := pa.lerp(pb, t)
				crowd.add_person(Vector3(pp.x + rng.randf_range(-0.2, 0.2), pa.y + h - 0.2,
						pp.z + rng.randf_range(-0.2, 0.2)), face, rng)
	var top := 0.7 + rows * 0.95
	# roof on posts over the back half of the stand (it never reaches out over the track)
	var roof_h := top + 3.2
	if roof:
		var white := _mat("stand_roof", Color(0.8, 0.81, 0.83), 0.6)
		var steps2 := maxi(3, roundi(length / 14.0))
		var back := base_off + rows * 1.1
		for i in steps2:
			var sa := lerpf(s0, s1, float(i) / steps2)
			var sb := lerpf(s0, s1, float(i + 1) / steps2)
			var pa := layout.side_point(sa, side * back)
			var pb := layout.side_point(sb, side * back)
			var mid := (pa + pb) * 0.5
			var d := pb - pa
			var base_y := layout.side_point((s0 + s1) * 0.5, side * base_off).y
			var roof_mi := _box_at(Vector3(rows * 1.1, 0.3, d.length() * 1.04),
					Vector3(mid.x, base_y + roof_h, mid.z), white)
			roof_mi.rotation.y = atan2(d.x, d.z)
			var post := layout.side_point((sa + sb) * 0.5, side * (back + rows * 0.5))
			_box_at(Vector3(0.3, roof_h, 0.3), Vector3(post.x, base_y + roof_h * 0.5, post.z), grey)
	# the stand blocks the drone and the line of sight
	var marks := maxi(3, roundi(length / 18.0))
	for i in marks:
		var p := layout.side_point(lerpf(s0, s1, (i + 0.5) / marks), side * (base_off + rows * 0.75))
		_obstacle(p, 0.0, rows * 0.9, length / marks * 0.5, top + (3.5 if roof else 0.0))
	host.add_child(crowd)
	crowd.build()


## Smallest distance from any part of the track to the front of a stand built on that side, m.
func _stand_room(s0: float, s1: float, side: float, base_off: float) -> float:
	var worst := INF
	for i in 7:
		var p := layout.side_point(lerpf(s0, s1, i / 6.0), side * base_off)
		worst = minf(worst, layout.distance_to_track(p.x, p.z))
	return worst


func _runoff_at(s: float, side: float) -> float:
	var i := layout.index_at(s)
	return _runoff_l[i] if side < 0.0 else _runoff_r[i]


## The Dunlop bridge: an arch over the track with its advertising banner.
func _bridge(s: float) -> void:
	var hw := layout.half_width
	var yellow := _mat("bridge", Color(0.92, 0.76, 0.06), 0.55)
	var dark := _mat("bridge_dark", Color(0.15, 0.15, 0.17), 0.6)
	var left := layout.side_point(s, -hw - 7.0)
	var right := layout.side_point(s, hw + 7.0)
	var top := maxf(left.y, right.y) + 9.5
	var dir := layout.dir_at(s)
	var yaw := atan2(dir.x, dir.y)
	for p in [left, right]:
		_box_at(Vector3(1.6, top - p.y, 1.6), Vector3(p.x, (p.y + top) * 0.5, p.z), dark)
		_obstacle(Vector3(p.x, p.y, p.z), 0.0, 1.2, 1.2, top - p.y)
	var mid := (left + right) * 0.5
	var width := left.distance_to(right)
	var span := _box_at(Vector3(width, 2.6, 1.6), Vector3(mid.x, top - 1.3, mid.z), yellow)
	span.rotation.y = yaw
	var walk := _box_at(Vector3(width, 0.3, 2.6), Vector3(mid.x, top - 2.8, mid.z), dark)
	walk.rotation.y = yaw
	_top_box(Vector3(mid.x, 0.0, mid.z), width * 0.55, 2.2, top)


## Marshal posts around the lap: a small cabin with a flag.
func _marshal_posts() -> void:
	var orange := _mat("marshal", Color(0.92, 0.5, 0.07), 0.7)
	var white := _mat("marshal_w", Color(0.9, 0.9, 0.9), 0.7)
	var count := 14
	for i in count:
		var s := layout.lap_length * (i + 0.35) / count
		var side := _outer_side(s)
		var off := layout.half_width + _runoff_at(s, side) + BARRIER_GAP + 3.0
		var p := layout.side_point(s, side * off)
		_box_at(Vector3(2.2, 2.1, 2.2), p + Vector3(0, 1.05, 0), white)
		_box_at(Vector3(2.5, 0.2, 2.5), p + Vector3(0, 2.2, 0), orange)
		_obstacle(p, 0.0, 1.3, 1.3, 2.4)


# --- Trees ---------------------------------------------------------------------------------------

## Spruce forest of the Eifel all around the circuit, and a few groups in the infield; nothing within
## TREE_CLEAR of the track, nothing where a structure already stands.
func _vegetation() -> void:
	var b := layout.bounds.grow(170.0)
	var grounds := PackedVector3Array()
	var scales := PackedFloat32Array()
	var tries := 5200
	for _i in tries:
		var x := rng.randf_range(b.position.x, b.end.x)
		var z := rng.randf_range(b.position.y, b.end.y)
		var q := layout.nearest(x, z)
		var d := q.x
		if d < 120.0:
			# close to the track: only beyond the barriers, and not everywhere
			var limit: float = layout.half_width + maxf(_runoff_l[layout.index_at(q.z)], _runoff_r[layout.index_at(q.z)]) + TREE_CLEAR
			if d < limit or rng.randf() < 0.55:
				continue
		if _top_at(x, z) > 0.5:
			continue
		var g := layout.ground(x, z)
		var s := rng.randf_range(0.9, 1.9)
		grounds.append(Vector3(x, g, z))
		scales.append(s)
	PropFactory.build_forest(host, grounds, scales, Color(0.07, 0.26, 0.12), 31, 950.0)


# --- Helpers -------------------------------------------------------------------------------------

func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, nrm: Vector3,
		uv0: Vector2, uv1: Vector2) -> void:
	var uvs := [uv0, Vector2(uv1.x, uv0.y), uv1, Vector2(uv0.x, uv1.y)]
	var vs := [a, b, c, d]
	for idx in [0, 1, 2, 0, 2, 3]:
		st.set_normal(nrm)
		st.set_uv(uvs[idx])
		st.add_vertex(vs[idx])


func _box_at(size: Vector3, centre: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat
	mi.position = centre
	host.add_child(mi)
	return mi


func _multimesh(mesh: Mesh, xforms: Array[Transform3D], shadows := true,
		colours := PackedColorArray()) -> void:
	if xforms.is_empty():
		return
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


## Registers a box obstacle (drone collisions, lines of sight) and raises the structure height field.
func _obstacle(ground_pos: Vector3, yaw: float, hx: float, hz: float, h: float) -> void:
	boxes.append({"c": ground_pos, "yaw": yaw, "hx": hx, "hz": hz, "h": h})
	if h >= LOW_STRUCTURE:
		_top_box(ground_pos, hx, hz, ground_pos.y + h)


func _top_box(ground_pos: Vector3, hx: float, hz: float, top: float) -> void:
	if _tw == 0:
		return
	var r := maxf(hx, hz) + 1.0
	var x0 := floori((ground_pos.x - r - _tx0) / TOP_CELL)
	var x1 := ceili((ground_pos.x + r - _tx0) / TOP_CELL)
	var z0 := floori((ground_pos.z - r - _tz0) / TOP_CELL)
	var z1 := ceili((ground_pos.z + r - _tz0) / TOP_CELL)
	for iz in range(maxi(z0, 0), mini(z1 + 1, _th)):
		for ix in range(maxi(x0, 0), mini(x1 + 1, _tw)):
			var k := iz * _tw + ix
			_tops[k] = maxf(_tops[k], top)


## Top of the structures at (x, z), 0 where there is none.
func _top_at(x: float, z: float) -> float:
	if _tw == 0:
		return 0.0
	var ix := clampi(roundi((x - _tx0) / TOP_CELL), 0, _tw - 1)
	var iz := clampi(roundi((z - _tz0) / TOP_CELL), 0, _th - 1)
	return _tops[iz * _tw + ix]


## Height the drone must stay above at (x, z): the ground, or the top of a structure.
func clearance(x: float, z: float) -> float:
	return maxf(layout.ground(x, z), _top_at(x, z))


## Horizontal push getting a sphere out of the structures (sandbox drone).
func push(pos: Vector3, radius: float) -> Vector3:
	var best := Vector3.ZERO
	var best_d := 0.0
	for b in boxes:
		var c: Vector3 = b.c
		if pos.y > c.y + float(b.h) + radius or pos.y < c.y - radius:
			continue
		var local := Vector3(pos.x - c.x, 0.0, pos.z - c.z).rotated(Vector3.UP, -float(b.yaw))
		var hx: float = float(b.hx) + radius
		var hz: float = float(b.hz) + radius
		if absf(local.x) > hx or absf(local.z) > hz:
			continue
		var dx := hx - absf(local.x)
		var dz := hz - absf(local.z)
		var push_local := Vector3(signf(local.x) * dx, 0.0, 0.0) if dx < dz else Vector3(0.0, 0.0, signf(local.z) * dz)
		var p := push_local.rotated(Vector3.UP, float(b.yaw))
		if p.length() > best_d:
			best_d = p.length()
			best = p
	return best


static func _mat(key: String, c: Color, rough := 0.8, metal := 0.0) -> StandardMaterial3D:
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = rough
		m.metallic = metal
		_mats[key] = m
	return _mats[key]


## Red and white kerb: stripes about 1 m long along the band (V is in metres).
static func _kerb_mat() -> ShaderMaterial:
	if _mats.has("kerb"):
		return _mats["kerb"]
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
void fragment() {
	float s = step(0.5, fract(UV.y * 0.5));
	ALBEDO = mix(vec3(0.78, 0.09, 0.07), vec3(0.88, 0.88, 0.86), s);
	ROUGHNESS = 0.75;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	_mats["kerb"] = m
	return m


## Grey asphalt run-off with a green tint at its outer edge (the painted run-off of a modern circuit).
static func _runoff_mat() -> ShaderMaterial:
	if _mats.has("runoff"):
		return _mats["runoff"]
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
void fragment() {
	float edge = abs(UV.x - 0.5) * 2.0;
	vec3 grey = vec3(0.30, 0.30, 0.31);
	vec3 green = vec3(0.17, 0.33, 0.17);
	ALBEDO = mix(grey, green, smoothstep(0.55, 0.95, edge));
	ROUGHNESS = 0.92;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	_mats["runoff"] = m
	return m


## Debris fence: a fine mesh, mostly transparent (UV in metres).
static func _fence_mat() -> ShaderMaterial:
	if _mats.has("fence"):
		return _mats["fence"]
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha;
void fragment() {
	vec2 g = fract(UV / 0.1);
	float w = fwidth(UV.x / 0.1) * 0.8 + 0.1;
	float wire = max(1.0 - smoothstep(0.0, w, min(g.x, 1.0 - g.x)),
					 1.0 - smoothstep(0.0, w, min(g.y, 1.0 - g.y)));
	ALPHA = clamp(wire, 0.0, 1.0) * 0.85;
	ALBEDO = vec3(0.35, 0.37, 0.4);
	ROUGHNESS = 0.5;
	METALLIC = 0.5;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	_mats["fence"] = m
	return m

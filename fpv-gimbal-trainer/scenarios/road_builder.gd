class_name RoadBuilder
extends RefCounted
## Helpers for a road / trail laid on terrain: nearest-centerline queries (to flatten the
## ground under the road) and ribbon meshes (asphalt, dirt trail, dashed centre line).

const BUCKET := 16.0

var points := PackedVector3Array()
var _grid := {}  # Vector2i -> PackedInt32Array of point indices


func _init(centerline: PackedVector3Array) -> void:
	points = centerline
	for i in points.size():
		var key := Vector2i(floori(points[i].x / BUCKET), floori(points[i].z / BUCKET))
		if not _grid.has(key):
			_grid[key] = PackedInt32Array()
		_grid[key].append(i)


static func sample_curve(curve: Curve3D, step: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	var length := curve.get_baked_length()
	var d := 0.0
	while d < length:
		out.append(curve.sample_baked(d))
		d += step
	out.append(curve.sample_baked(length))
	return out


## Distance (xz) to the centerline and the interpolated road height at the closest point.
## Returns Vector2(INF, 0) when no sample is within BUCKET.
func nearest(x: float, z: float) -> Vector2:
	var cx := floori(x / BUCKET)
	var cz := floori(z / BUCKET)
	var best_d := INF
	var best_y := 0.0
	var p := Vector2(x, z)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var key := Vector2i(cx + dx, cz + dz)
			if not _grid.has(key):
				continue
			for i in _grid[key]:
				for j in [i - 1, i + 1]:
					if j < 0 or j >= points.size():
						continue
					var a := Vector2(points[i].x, points[i].z)
					var b := Vector2(points[j].x, points[j].z)
					var ab := b - a
					var l2 := ab.length_squared()
					var t := 0.0 if l2 < 0.0001 else clampf((p - a).dot(ab) / l2, 0.0, 1.0)
					var d := p.distance_to(a + ab * t)
					if d < best_d:
						best_d = d
						best_y = lerpf(points[i].y, points[j].y, t)
	return Vector2(best_d, best_y)


## Ground height flattened to the road height within flat_w, blending back to base_h by blend_w.
func blend_height(x: float, z: float, base_h: float, flat_w: float, blend_w: float) -> float:
	var n := nearest(x, z)
	if n.x >= blend_w:
		return base_h
	return lerpf(base_h, n.y, 1.0 - smoothstep(flat_w, blend_w, n.x))


static func build_ribbon(pts: PackedVector3Array, half_width: float, y_offset: float,
		uv_per_m := 0.25) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var left := PackedVector3Array()
	var right := PackedVector3Array()
	var v_along := PackedFloat32Array()
	var run := 0.0
	for i in pts.size():
		var t := (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)])
		t.y = 0.0
		t = t.normalized()
		var r := t.cross(Vector3.UP).normalized()
		left.append(pts[i] - r * half_width + Vector3.UP * y_offset)
		right.append(pts[i] + r * half_width + Vector3.UP * y_offset)
		if i > 0:
			run += pts[i].distance_to(pts[i - 1])
		v_along.append(run * uv_per_m)
	for i in pts.size() - 1:
		# clockwise seen from above: (L0, L1, R0) and (R0, L1, R1)
		for c in [[i, 0], [i + 1, 0], [i, 1], [i, 1], [i + 1, 0], [i + 1, 1]]:
			var k: int = c[0]
			var is_right: bool = c[1] == 1
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(1.0 if is_right else 0.0, v_along[k]))
			st.add_vertex(right[k] if is_right else left[k])
	return st.commit()


## Dashed line along the centerline: `dash` samples on, `gap` samples off.
static func build_dashes(pts: PackedVector3Array, half_width: float, y_offset: float,
		dash := 2, gap := 2) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cycle := dash + gap
	for i in pts.size() - 1:
		if i % cycle >= dash:
			continue
		var t := (pts[i + 1] - pts[i])
		t.y = 0.0
		t = t.normalized()
		var r := t.cross(Vector3.UP).normalized() * half_width
		var l0 := pts[i] - r + Vector3.UP * y_offset
		var r0 := pts[i] + r + Vector3.UP * y_offset
		var l1 := pts[i + 1] - r + Vector3.UP * y_offset
		var r1 := pts[i + 1] + r + Vector3.UP * y_offset
		for v in [l0, l1, r0, r0, l1, r1]:
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
	return st.commit()

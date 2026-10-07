class_name Decor
extends RefCounted
## Small scenery built like the trees (Vegetation.place): ferns, bushes, hedge segments, fallen logs, stumps.
## Ferns use the spruce branch texture as fronds, bushes and hedges the leaf clusters of the broadleaf trees.

## kind -> [variants, detailed + simple model, casts shadows]
const KINDS := {
	"fern": [3, false, false],
	"bush": [3, true, true],
	"hedge": [2, true, true],
	"log": [2, false, true],
	"stump": [2, false, true],
}


static func handles(kind: String) -> bool:
	return KINDS.has(kind)


static func variants(kind: String) -> int:
	return KINDS[kind][0]


static func has_lod(kind: String) -> bool:
	return KINDS[kind][1]


static func casts_shadow(kind: String) -> bool:
	return KINDS[kind][2]


static func build(kind: String, lod: int, variant: int) -> ArrayMesh:
	match kind:
		"fern":
			return _fern(variant)
		"bush":
			return _bush(lod, variant)
		"hedge":
			return _hedge(lod, variant)
		"log":
			return _log(variant)
	return _stump(variant)


## Fern: arching fronds around the centre (about 1 m across, 0.6 m high).
static func _fern(variant: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 500 + variant
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var fronds := 7 + variant
	for f in fronds:
		var a := TAU * f / fronds + rng.randf_range(-0.3, 0.3)
		var d := Vector3(cos(a), 0.0, sin(a))
		var side := d.cross(Vector3.UP).normalized()
		var length := rng.randf_range(0.65, 1.0)
		var rise := rng.randf_range(1.0, 1.5)
		var rnd := rng.randf()
		var rows := []
		for k in 5:
			var t := k / 4.0
			var s := t * length
			var c := d * s + Vector3.UP * (rise * s - 1.25 * s * s)
			var w := 0.2 * sin(PI * pow(t, 0.75)) + 0.02
			rows.append([c - side * w, c + side * w, t])
		for k in 4:
			var r0: Array = rows[k]
			var r1: Array = rows[k + 1]
			var quad := [[r0[0], 0.0, r0[2]], [r1[0], 0.0, r1[2]], [r0[1], 1.0, r0[2]],
					[r0[1], 1.0, r0[2]], [r1[0], 0.0, r1[2]], [r1[1], 1.0, r1[2]]]
			for q in quad:
				var t: float = q[2]
				var n := (Vector3.UP * 0.8 + d * 0.4).normalized()
				Vegetation.vert(st, q[0], n, Vector2(q[1], t), Color(0.35 + 0.65 * t, t, rnd))
	var mesh := st.commit()
	mesh.surface_set_material(0, Vegetation.leaf_material(true))
	return mesh


## Bush: a few leaf clusters around a short stem (about 1.4 m across, 1.2 m high).
static func _bush(lod: int, variant: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 600 + variant * 7 + lod * 100
	var bark := SurfaceTool.new()
	bark.begin(Mesh.PRIMITIVE_TRIANGLES)
	Vegetation.cylinder(bark, Vector3.ZERO, Vector3(0, 0.6, 0), 0.06, 0.03, 4, Color(0.8, 0.8, 0.8))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center := Vector3(0, 0.55, 0)
	var n := 4 if lod == 0 else 2
	for k in n:
		var a := TAU * k / n + rng.randf_range(-0.5, 0.5)
		var r := 0.0 if k == 0 else rng.randf_range(0.25, 0.45)
		var c := Vector3(cos(a) * r, rng.randf_range(0.45, 0.75), sin(a) * r)
		Vegetation.cluster(st, c, rng.randf_range(0.45, 0.6) * (1.0 if lod == 0 else 1.3), center, lod, rng)
	var mesh := bark.commit()
	st.commit(mesh)
	mesh.surface_set_material(0, Vegetation.bark_material())
	mesh.surface_set_material(1, Vegetation.leaf_material(false))
	return mesh


## Hedge segment: 6 m along z, 1.6 m wide, about 1.6 m high.
static func _hedge(lod: int, variant: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 700 + variant * 5 + lod * 100
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 7 if lod == 0 else 3
	for k in n:
		var z := -3.0 + 6.0 * (k + 0.5) / n + rng.randf_range(-0.3, 0.3)
		var c := Vector3(rng.randf_range(-0.25, 0.25), rng.randf_range(0.6, 1.0), z)
		var rc := rng.randf_range(0.7, 0.9) * (1.0 if lod == 0 else 1.35)
		Vegetation.cluster(st, c, rc, Vector3(0, 0.4, z), lod, rng)
	var mesh := st.commit()
	mesh.surface_set_material(0, Vegetation.leaf_material(false))
	return mesh


## Fallen log, built standing along +y (the bark texture runs along y): lay it down with the instance transform.
static func _log(variant: int) -> ArrayMesh:
	var r := 0.2 + 0.08 * variant
	var length := 3.2 + variant * 1.1
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	Vegetation.cylinder(st, Vector3(0, -length * 0.5, 0), Vector3(0, length * 0.5, 0), r, r * 0.8, 8, Color(0.85, 0.85, 0.85))
	_cap(st, Vector3(0, -length * 0.5, 0), r, Vector3.DOWN, 8)
	_cap(st, Vector3(0, length * 0.5, 0), r * 0.8, Vector3.UP, 8)
	var mesh := st.commit()
	mesh.surface_set_material(0, Vegetation.bark_material())
	return mesh


static func _stump(variant: int) -> ArrayMesh:
	var r := 0.26 + 0.08 * variant
	var h := 0.35 + 0.2 * variant
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	Vegetation.cylinder(st, Vector3(0, -0.1, 0), Vector3(0, h, 0), r * 1.25, r, 9, Color(0.9, 0.9, 0.9))
	_cap(st, Vector3(0, h, 0), r, Vector3.UP, 9)
	var mesh := st.commit()
	mesh.surface_set_material(0, Vegetation.bark_material())
	return mesh


## Disc of cut wood (light colour).
static func _cap(st: SurfaceTool, c: Vector3, r: float, n: Vector3, sides: int) -> void:
	var x := Vector3.RIGHT
	var z := n.cross(x).normalized()
	for k in sides:
		var a0 := TAU * k / sides
		var a1 := TAU * (k + 1) / sides
		var p0 := c + (x * cos(a0) + z * sin(a0)) * r
		var p1 := c + (x * cos(a1) + z * sin(a1)) * r
		for p in ([c, p0, p1] if n.y > 0.0 else [c, p1, p0]):
			Vegetation.vert(st, p, n, Vector2.ZERO, Color(1.0, 1.0, 0.0))  # blue 0 = cut wood (bark shader)

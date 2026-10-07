class_name TerrainBuilder
extends RefCounted
## Builds a terrain mesh from a height Callable(x, z) -> float.

## Heights of the last terrain built (for the grass): {heights, w, h, x0, z0, cell}.
static var last_info := {}


## The heights of `info` as a float texture (one texel per vertex) and its frame for the shaders:
## uv = (xz - (x0, z0)) * inverse size + half a texel.
static func height_texture(info: Dictionary) -> ImageTexture:
	var img := Image.create_from_data(int(info.w), int(info.h), false, Image.FORMAT_RF, info.heights.to_byte_array())
	return ImageTexture.create_from_image(img)


static func build(height: Callable, x_half: float, z_min: float, z_max: float, cell: float,
		uv_scale := 24.0) -> ArrayMesh:
	var nx := int(2.0 * x_half / cell)
	var nz := int((z_max - z_min) / cell)
	var w := nx + 1
	var heights := PackedFloat32Array()
	heights.resize(w * (nz + 1))
	for iz in nz + 1:
		for ix in w:
			heights[iz * w + ix] = float(height.call(-x_half + ix * cell, z_min + iz * cell))
	last_info = {"heights": heights, "w": w, "h": nz + 1, "x0": -x_half, "z0": z_min, "cell": cell}

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iz in nz:
		for ix in nx:
			# clockwise seen from above: (v00, v10, v01) and (v10, v11, v01)
			for corner in [[0, 0], [1, 0], [0, 1], [1, 0], [1, 1], [0, 1]]:
				var cx: int = ix + corner[0]
				var cz: int = iz + corner[1]
				var x := -x_half + cx * cell
				var z := z_min + cz * cell
				var dx := (_h(heights, nx, nz, cx + 1, cz) - _h(heights, nx, nz, cx - 1, cz)) / (2.0 * cell)
				var dz := (_h(heights, nx, nz, cx, cz + 1) - _h(heights, nx, nz, cx, cz - 1)) / (2.0 * cell)
				st.set_normal(Vector3(-dx, 1.0, -dz).normalized())
				st.set_uv(Vector2(x, z) / uv_scale)
				st.add_vertex(Vector3(x, heights[cz * w + cx], z))
	# skirt: a band hanging 8 m down from the border, so no gap shows where the far terrain meets this one
	var border := []
	for ix in nx + 1:
		border.append(Vector2i(ix, 0))
	for iz in range(1, nz + 1):
		border.append(Vector2i(nx, iz))
	for ix in range(nx - 1, -1, -1):
		border.append(Vector2i(ix, nz))
	for iz in range(nz - 1, -1, -1):
		border.append(Vector2i(0, iz))
	var mid := Vector2(0.0, (z_min + z_max) * 0.5)
	for k in border.size() - 1:
		var a: Vector2i = border[k]
		var b: Vector2i = border[k + 1]
		var pa := Vector3(-x_half + a.x * cell, heights[a.y * w + a.x], z_min + a.y * cell)
		var pb := Vector3(-x_half + b.x * cell, heights[b.y * w + b.x], z_min + b.y * cell)
		var out := Vector3((pa.x + pb.x) * 0.5 - mid.x, 0.0, (pa.z + pb.z) * 0.5 - mid.y).normalized()
		for p in [pa, pb, pa - Vector3(0, 8, 0), pa - Vector3(0, 8, 0), pb, pb - Vector3(0, 8, 0)]:
			st.set_normal(out)
			st.set_uv(Vector2(p.x, p.z) / uv_scale)
			st.add_vertex(p)
	return st.commit()


## Height of the last terrain built at (x, z), bilinear between its vertices (NAN outside it).
static func last_height(x: float, z: float) -> float:
	if last_info.is_empty():
		return NAN
	var fx := (x - float(last_info.x0)) / float(last_info.cell)
	var fz := (z - float(last_info.z0)) / float(last_info.cell)
	var w := int(last_info.w)
	var h := int(last_info.h)
	if fx < 0.0 or fz < 0.0 or fx > w - 1 or fz > h - 1:
		return NAN
	var ix := mini(int(fx), w - 2)
	var iz := mini(int(fz), h - 2)
	var tx := fx - ix
	var tz := fz - iz
	var hs: PackedFloat32Array = last_info.heights
	var a := lerpf(hs[iz * w + ix], hs[iz * w + ix + 1], tx)
	var b := lerpf(hs[(iz + 1) * w + ix], hs[(iz + 1) * w + ix + 1], tx)
	return lerpf(a, b, tz)


static func _h(heights: PackedFloat32Array, nx: int, nz: int, ix: int, iz: int) -> float:
	return heights[clampi(iz, 0, nz) * (nx + 1) + clampi(ix, 0, nx)]


## Noise-tinted ground material with fine relief.
static func make_material(dark: Color, light: Color, relief := 0.8, tex_freq := 0.03) -> StandardMaterial3D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = tex_freq
	noise.fractal_octaves = 4
	var ramp := Gradient.new()
	ramp.set_color(0, dark)
	ramp.set_color(1, light)
	var tex := NoiseTexture2D.new()
	tex.noise = noise
	tex.color_ramp = ramp
	tex.seamless = true
	tex.width = 512
	tex.height = 512

	var bump := FastNoiseLite.new()
	bump.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	bump.frequency = 0.09
	bump.fractal_octaves = 4
	var ntex := NoiseTexture2D.new()
	ntex.noise = bump
	ntex.as_normal_map = true
	ntex.bump_strength = 8.0
	ntex.seamless = true
	ntex.width = 1024
	ntex.height = 1024

	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.normal_enabled = true
	mat.normal_texture = ntex
	mat.normal_scale = relief
	mat.roughness = 0.9
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat

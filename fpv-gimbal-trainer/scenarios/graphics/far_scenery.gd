class_name FarScenery
extends RefCounted
## What lies beyond the playing area, so the horizon is a landscape and not the edge of the world:
##  - an outer ring of terrain continuing the environment's relief (EnvironmentBuilder.far_height) with the same
##    material, slightly lowered under the detailed terrain so the junction never shows;
##  - a ring of distant hills or mountains (ridged noise), shaded by height and slope (forest, grass, rock, snow);
##  - optionally scattered trees on the outer ring.
## cfg (EnvironmentBuilder.far_scenery): ring_radius, ring_cell, hills {height, r0, r1, base, snow_line,
## tree_line, forest (colour), grass (colour), rock (colour)}, trees {kind, count, r0, r1, colour}.

const MOUNTAIN_SHADER := """
shader_type spatial;

uniform sampler2D macro_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D detail_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 forest : source_color = vec3(0.08, 0.16, 0.07);
uniform vec3 grass : source_color = vec3(0.3, 0.38, 0.14);
uniform vec3 rock : source_color = vec3(0.42, 0.4, 0.38);
uniform float snow_line = 100000.0;
uniform float tree_line = 100000.0;
varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float m = texture(macro_tex, wpos.xz * 0.00045).r;
	float d = texture(detail_tex, wpos.xz * 0.004).r;
	float slope = 1.0 - wnrm.y;
	float h = wpos.y + (m - 0.5) * 160.0 + (d - 0.5) * 60.0;
	vec3 col = mix(forest * (0.7 + 0.6 * d), grass * (0.8 + 0.4 * d), smoothstep(0.45, 0.65, m));
	col = mix(col, grass * 0.9, smoothstep(tree_line - 80.0, tree_line + 80.0, h));
	col = mix(col, rock * (0.75 + 0.5 * d), smoothstep(0.28, 0.45, slope + (d - 0.5) * 0.2));
	float snow = smoothstep(snow_line - 60.0, snow_line + 60.0, h) * (1.0 - smoothstep(0.55, 0.75, slope));
	col = mix(col, vec3(0.92, 0.94, 0.98), snow);
	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.7, snow);
	SPECULAR = 0.3;
}
"""

static var _shader: Shader


## Builds the far scenery of `env` around the detailed terrain rectangle `inner` (x, z, width, depth).
static func build(env: EnvironmentBuilder, inner: Rect2, near_material: Material, cfg: Dictionary) -> void:
	build_into(env.host, Callable(env, "far_height"), env.host.world_seed, inner, near_material, cfg)


## Same, for any world: `height` = Callable(x, z) -> ground height outside the detailed terrain.
static func build_into(host: Node3D, height: Callable, world_seed: int, inner: Rect2, near_material: Material,
		cfg: Dictionary) -> void:
	if cfg.is_empty():
		return
	var center := inner.get_center()
	var ring_r := float(cfg.get("ring_radius", 1500.0))
	var cell := float(cfg.get("ring_cell", 30.0))
	var ring := MeshInstance3D.new()
	ring.name = "FarTerrain"
	ring.mesh = _ring_mesh(height, inner, center, ring_r, cell)
	ring.material_override = near_material
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	host.add_child(ring)
	if cfg.has("hills"):
		var hills: Dictionary = cfg.hills
		var mi := MeshInstance3D.new()
		mi.name = "FarHills"
		mi.mesh = _hills_mesh(height, world_seed, center, hills, ring_r)
		mi.material_override = _mountain_material(hills)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		host.add_child(mi)
	if cfg.has("trees"):
		var t: Dictionary = cfg.trees
		var rng := RandomNumberGenerator.new()
		rng.seed = 970 + world_seed
		var grounds := PackedVector3Array()
		var scales := PackedFloat32Array()
		var grown := inner.grow(4.0)
		var tries := 0
		while grounds.size() < int(t.count) and tries < int(t.count) * 4:
			tries += 1
			var a := rng.randf() * TAU
			var r := lerpf(float(t.r0), float(t.r1), sqrt(rng.randf()))
			var x := center.x + cos(a) * r
			var z := center.y + sin(a) * r
			if grown.has_point(Vector2(x, z)):
				continue
			# trees in groves: keep those where a low-frequency pattern is high
			if sin(x * 0.011 + 1.3) * sin(z * 0.009 - 0.7) + 0.3 * sin(x * 0.037 + z * 0.029) < float(t.get("grove", -1.0)):
				continue
			grounds.append(Vector3(x, float(height.call(x, z)) - 0.3, z))
			scales.append(rng.randf_range(1.0, 1.8))
		Vegetation.plant(host, str(t.kind), grounds, scales, t.colour, 971 + world_seed)


static func _mountain_material(hills: Dictionary) -> ShaderMaterial:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = MOUNTAIN_SHADER
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("macro_tex", GroundMaterials.noise("macro"))
	m.set_shader_parameter("detail_tex", GroundMaterials.noise("detail"))
	for k in ["forest", "grass", "rock", "snow_line", "tree_line"]:
		if hills.has(k):
			m.set_shader_parameter(k, hills[k])
	return m


## Square grid of `cell` metres out to `radius` around the centre, without the cells inside the detailed terrain
## (one cell of overlap, lowered so the detailed terrain covers it).
static func _ring_mesh(height: Callable, inner: Rect2, center: Vector2, radius: float, cell: float) -> ArrayMesh:
	var n := ceili(radius * 2.0 / cell)
	var x0 := center.x - n * cell * 0.5
	var z0 := center.y - n * cell * 0.5
	var heights := PackedFloat32Array()
	heights.resize((n + 1) * (n + 1))
	var hole := inner.grow(-cell)
	var covered := inner.grow(cell * 0.5)
	for iz in n + 1:
		for ix in n + 1:
			var x := x0 + ix * cell
			var z := z0 + iz * cell
			var h := float(height.call(x, z))
			if covered.has_point(Vector2(x, z)):
				# under the detailed terrain: follow it, just below
				var inner_h := TerrainBuilder.last_height(x, z)
				h = (inner_h if not is_nan(inner_h) else h) - 0.25
			heights[iz * (n + 1) + ix] = h
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iz in n:
		for ix in n:
			var cx := x0 + (ix + 0.5) * cell
			var cz := z0 + (iz + 0.5) * cell
			if hole.has_point(Vector2(cx, cz)) or Vector2(cx, cz).distance_to(center) > radius:
				continue
			for corner in [[0, 0], [1, 0], [0, 1], [1, 0], [1, 1], [0, 1]]:
				var gx: int = ix + corner[0]
				var gz: int = iz + corner[1]
				st.add_vertex(Vector3(x0 + gx * cell, heights[gz * (n + 1) + gx], z0 + gz * cell))
	st.generate_normals()
	return st.commit()


## Polar ring of hills / mountains from r0 to r1 (beyond the outer terrain), rising from the far terrain.
static func _hills_mesh(height: Callable, world_seed: int, center: Vector2, hills: Dictionary, ring_r: float) -> ArrayMesh:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	noise.frequency = float(hills.get("frequency", 0.0008))
	noise.fractal_octaves = 5
	noise.seed = 31 + world_seed
	# the hills start under the edge of the outer terrain (no gap), then rise towards r0 and beyond
	var r0 := ring_r * 0.9
	var rise_r := maxf(float(hills.get("r0", 2000.0)), ring_r)
	var r1 := float(hills.get("r1", 5000.0))
	var amp := float(hills.get("height", 500.0))
	var segs := 220
	var rings := 22
	var pts := []
	for k in rings + 1:
		var t := float(k) / rings
		var r := r0 * pow(r1 / r0, t)
		var row := PackedVector3Array()
		for s in segs:
			var a := TAU * s / segs
			var x := center.x + cos(a) * r
			var z := center.y + sin(a) * r
			var base := float(height.call(x, z)) if k == 0 else float(height.call(center.x + cos(a) * r0, center.y + sin(a) * r0))
			var rise := smoothstep(ring_r, rise_r + (r1 - rise_r) * 0.25, r)
			var nn := 0.5 + 0.5 * noise.get_noise_2d(x, z)
			row.append(Vector3(x, base - 4.0 + amp * rise * pow(nn, 1.6) * (0.6 + 0.4 * t), z))
		pts.append(row)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in rings:
		var a: PackedVector3Array = pts[k]
		var b: PackedVector3Array = pts[k + 1]
		for s in segs:
			var s1 := (s + 1) % segs
			for v in [a[s], b[s], a[s1], a[s1], b[s], b[s1]]:  # front faces up (clockwise seen from above)
				st.add_vertex(v)
	st.generate_normals()
	return st.commit()

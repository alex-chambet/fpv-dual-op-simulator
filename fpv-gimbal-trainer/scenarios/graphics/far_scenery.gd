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

// relief of the mountains at a scale the mesh cannot hold: ridges and gullies (ridged noise, bumps the normal)
float ridges(vec2 p) {
	float a = 1.0 - abs(texture(detail_tex, p * 0.0016).r * 2.0 - 1.0);
	float b = 1.0 - abs(texture(detail_tex, p * 0.0047 + 0.31).r * 2.0 - 1.0);
	return a * a * 0.65 + b * b * 0.35;
}

void fragment() {
	float m = texture(macro_tex, wpos.xz * 0.00045).r;
	float d = texture(detail_tex, wpos.xz * 0.004).r;
	// bumped normal: the ridges run down the slopes (stretched along the fall line)
	float e = 6.0;
	float r0 = ridges(wpos.xz);
	vec3 bump = vec3(r0 - ridges(wpos.xz + vec2(e, 0.0)), 0.0, r0 - ridges(wpos.xz + vec2(0.0, e))) * 55.0;
	float steep0 = 1.0 - wnrm.y;
	vec3 n = normalize(wnrm + bump * smoothstep(0.05, 0.35, steep0));
	float slope = 1.0 - n.y;
	float h = wpos.y + (m - 0.5) * 160.0 + (d - 0.5) * 60.0;
	vec3 col = mix(forest * (0.7 + 0.6 * d), grass * (0.8 + 0.4 * d), smoothstep(0.45, 0.65, m));
	col = mix(col, grass * 0.9, smoothstep(tree_line - 80.0, tree_line + 80.0, h));
	// bare rock on the steep faces and the crests of the ridges, with strata
	float strata = 0.85 + 0.3 * texture(detail_tex, vec2(wpos.y * 0.02, wpos.x * 0.0007)).r;
	float rock_w = smoothstep(0.3, 0.5, slope + (d - 0.5) * 0.25 + r0 * 0.12);
	col = mix(col, rock * (0.7 + 0.45 * d) * strata, rock_w);
	// snow above the snow line, kept in the gullies and off the steepest faces
	float snow = smoothstep(snow_line - 60.0, snow_line + 60.0, h) * (1.0 - smoothstep(0.5, 0.7, slope - (1.0 - r0) * 0.15));
	col = mix(col, vec3(0.92, 0.94, 0.98) * (0.92 + 0.08 * d), snow);
	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.65, snow);
	SPECULAR = 0.3;
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
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
	if cfg.has("canopy"):
		var cp: Dictionary = cfg.canopy
		var cm := MeshInstance3D.new()
		cm.name = "FarCanopy"
		cm.mesh = _canopy_mesh(height, inner, center, ring_r, cp)
		cm.material_override = _canopy_material(cp)
		cm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		host.add_child(cm)
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
			if grove_at(x, z) < float(t.get("grove", -1.0)):
				continue
			grounds.append(Vector3(x, float(height.call(x, z)) - 0.3, z))
			scales.append(rng.randf_range(1.0, 1.8))
		Vegetation.plant(host, str(t.kind), grounds, scales, t.colour, 971 + world_seed)


## Grove pattern of the far scenery (the same for the scattered trees and the canopy): high where trees grow.
static func grove_at(x: float, z: float) -> float:
	return sin(x * 0.011 + 1.3) * sin(z * 0.009 - 0.7) + 0.3 * sin(x * 0.037 + z * 0.029)


## Far forest: a "blanket" of tree crowns raised `height` m over the ground where the groves are, from `r0` m around
## the playing area to the edge of the outer terrain. It continues the real trees much further than they can be
## drawn (cfg: r0, height, colour, grove (threshold of grove_at, -9 = everywhere), snow (0..1)).
static func _canopy_mesh(height: Callable, inner: Rect2, center: Vector2, radius: float, cp: Dictionary) -> ArrayMesh:
	var cell := float(cp.get("cell", 18.0))
	var n := ceili(radius * 2.0 / cell)
	var x0 := center.x - n * cell * 0.5
	var z0 := center.y - n * cell * 0.5
	var h := float(cp.get("height", 16.0))
	var r0 := float(cp.get("r0", 300.0))
	var thr := float(cp.get("grove", -9.0))
	var keep := inner.grow(r0)
	var ys := PackedFloat32Array()
	ys.resize((n + 1) * (n + 1))
	var on := PackedByteArray()
	on.resize((n + 1) * (n + 1))
	for iz in n + 1:
		for ix in n + 1:
			var x := x0 + ix * cell
			var z := z0 + iz * cell
			# distance outside the kept-free rectangle around the playing area
			var dx := maxf(maxf(keep.position.x - x, x - keep.end.x), 0.0)
			var dz := maxf(maxf(keep.position.y - z, z - keep.end.y), 0.0)
			var out := Vector2(dx, dz).length()
			var edge := 8.0 * sin(x * 0.05 + z * 0.031) + 6.0 * sin(z * 0.07 - x * 0.023)
			# (the ragged edge never reaches into the kept-free area: out - 20 + edge < 0 there)
			var m := smoothstep(0.0, 40.0, out - 20.0 + edge) * smoothstep(-0.12, 0.12, grove_at(x, z) - thr)
			m *= 1.0 - smoothstep(radius * 0.92, radius, Vector2(x, z).distance_to(center))
			var g := float(height.call(x, z))
			var top := h * (0.75 + 0.25 * sin(x * 0.13 + z * 0.07) * sin(z * 0.11 - x * 0.05))  # uneven crowns
			ys[iz * (n + 1) + ix] = g - 2.0 + (top + 2.0) * m
			on[iz * (n + 1) + ix] = 1 if m > 0.02 else 0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iz in n:
		for ix in n:
			var i00 := iz * (n + 1) + ix
			if on[i00] + on[i00 + 1] + on[i00 + n + 1] + on[i00 + n + 2] == 0:
				continue  # under the ground everywhere: no triangle
			for corner in [[0, 0], [1, 0], [0, 1], [1, 0], [1, 1], [0, 1]]:
				var gx: int = ix + corner[0]
				var gz: int = iz + corner[1]
				st.add_vertex(Vector3(x0 + gx * cell, ys[gz * (n + 1) + gx], z0 + gz * cell))
	st.index()
	st.generate_normals()
	return st.commit()


const CANOPY_SHADER := """
shader_type spatial;
uniform sampler2D cell_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D detail_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 colour : source_color = vec3(0.08, 0.22, 0.1);
uniform float snow = 0.0;
varying vec3 wpos;
varying vec3 wnrm;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	// tree crowns: cells of about 5 m, bright tops and dark gaps between them
	vec2 uv = wpos.xz * 0.011;
	float c = texture(cell_tex, uv).r;
	float c2 = texture(cell_tex, uv * 2.3 + 0.37).r;
	float crown = 1.0 - smoothstep(0.1, 0.6, c * 0.7 + c2 * 0.3);
	float d = texture(detail_tex, wpos.xz * 0.004).r;
	vec3 col = colour * (0.3 + 0.8 * crown) * (0.8 + 0.4 * d);
	// snow on the crowns (snowy forests)
	col = mix(col, vec3(0.86, 0.89, 0.95) * (0.7 + 0.3 * crown), snow * smoothstep(0.55, 0.95, crown + (d - 0.5) * 0.5) * smoothstep(0.6, 0.9, wnrm.y));
	// bumps of the crowns on the normal
	float e = 0.6;
	float c_x = texture(cell_tex, (wpos.xz + vec2(e, 0.0)) * 0.011).r;
	float c_z = texture(cell_tex, (wpos.xz + vec2(0.0, e)) * 0.011).r;
	vec3 n = normalize(wnrm + vec3(c_x - c, 0.0, c_z - c) * 9.0);
	ALBEDO = col;
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
}
"""
static var _canopy_shader: Shader


static func _canopy_material(cp: Dictionary) -> ShaderMaterial:
	if _canopy_shader == null:
		_canopy_shader = Shader.new()
		_canopy_shader.code = CANOPY_SHADER
	var m := ShaderMaterial.new()
	m.shader = _canopy_shader
	m.set_shader_parameter("cell_tex", GroundMaterials.noise("cell"))
	m.set_shader_parameter("detail_tex", GroundMaterials.noise("detail"))
	m.set_shader_parameter("colour", cp.get("colour", Color(0.08, 0.22, 0.1)))
	m.set_shader_parameter("snow", float(cp.get("snow", 0.0)))
	return m


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
	st.index()  # shared vertices: smooth normals (no facets)
	st.generate_normals()
	return st.commit()


## Polar ring of hills / mountains from r0 to r1 (beyond the outer terrain), rising from the far terrain.
static func _hills_mesh(height: Callable, world_seed: int, center: Vector2, hills: Dictionary, ring_r: float) -> ArrayMesh:
	# broad massifs (smooth noise, low frequency) carrying ridges (ridged noise): mountains, not a row of needles
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	noise.frequency = float(hills.get("frequency", 0.0008)) * 0.8
	noise.fractal_octaves = 4
	noise.fractal_gain = 0.42
	noise.seed = 31 + world_seed
	var massif := FastNoiseLite.new()
	massif.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	massif.fractal_type = FastNoiseLite.FRACTAL_FBM
	massif.frequency = float(hills.get("frequency", 0.0008)) * 0.3
	massif.fractal_octaves = 3
	massif.seed = 77 + world_seed
	# the hills start under the edge of the outer terrain (no gap), then rise towards r0 and beyond
	var r0 := ring_r * 0.9
	var rise_r := maxf(float(hills.get("r0", 2000.0)), ring_r)
	var r1 := float(hills.get("r1", 5000.0))
	var amp := float(hills.get("height", 500.0))
	var segs := 360
	var rings := 34
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
			var big := clampf(0.5 + 0.7 * massif.get_noise_2d(x, z), 0.0, 1.0)
			var ridge := 0.5 + 0.5 * noise.get_noise_2d(x, z)
			var hgt := big * (0.55 + 0.45 * pow(ridge, 1.3))
			row.append(Vector3(x, base - 4.0 + amp * rise * hgt * (0.6 + 0.4 * t), z))
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
	st.index()  # shared vertices: smooth normals (no facets)
	st.generate_normals()
	return st.commit()

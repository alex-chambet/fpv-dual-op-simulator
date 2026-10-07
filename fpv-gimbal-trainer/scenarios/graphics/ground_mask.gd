class_name GroundMask
extends SubViewport
## Map of the ground seen from above (rendered once by the GPU), read by the terrain and grass shaders:
##   R = hard surface (road, shoulder, trail): no grass, no field
##   B = fringe along the surface: worn / dusty ground
##   G = wide zone along the path (verges of a road, groomed piste of a ski slope): no crop fields
## Ribbons are drawn flat at increasing heights, so the later ones cover the earlier ones.

var rect := Rect2()
var _world: Node3D
var _layer := 0


## Covers the xz rectangle `r` (x, z, width, depth) with texels of about `texel` metres (at most 4096 per side).
func setup(r: Rect2, texel := 0.5) -> void:
	rect = r
	var t := maxf(texel, maxf(r.size.x, r.size.y) / 4096.0)
	size = Vector2i(maxi(8, ceili(r.size.x / t)), maxi(8, ceili(r.size.y / t)))
	own_world_3d = true
	transparent_bg = false
	render_target_update_mode = SubViewport.UPDATE_ONCE
	_world = Node3D.new()
	add_child(_world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	_world.add_child(we)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.size = r.size.y
	cam.near = 1.0
	cam.far = 1000.0
	# looking down, image right = +x, image up = -z (row 0 = smallest z)
	cam.transform = Transform3D(Basis(Vector3.RIGHT, Vector3.FORWARD, Vector3.UP),
			Vector3(r.position.x + r.size.x * 0.5, 500.0, r.position.y + r.size.y * 0.5))
	_world.add_child(cam)
	cam.current = true


## A band of half width `half_width` along the polyline, painted with `color` over what was drawn before.
func add_band(pts: PackedVector3Array, half_width: float, color: Color) -> void:
	if pts.size() < 2 or half_width <= 0.0:
		return
	_layer += 1
	var flat := PackedVector3Array()
	for p in pts:
		flat.append(Vector3(p.x, 0.0, p.z))
	var mi := MeshInstance3D.new()
	mi.mesh = RoadBuilder.build_ribbon(flat, half_width, _layer * 0.5)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_world.add_child(mi)


## (x min, z min, 1 / width, 1 / depth): uv = (xz - min) * inverse size.
func uv_frame() -> Vector4:
	return Vector4(rect.position.x, rect.position.y, 1.0 / rect.size.x, 1.0 / rect.size.y)


## Sets the mask uniforms of a shader material.
func bind(m: ShaderMaterial) -> void:
	m.set_shader_parameter("ground_mask", get_texture())
	m.set_shader_parameter("mask_frame", uv_frame())
	m.set_shader_parameter("use_mask", 1.0)

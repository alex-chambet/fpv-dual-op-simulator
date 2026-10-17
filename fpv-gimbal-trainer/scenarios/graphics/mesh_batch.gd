class_name MeshBatch
extends RefCounted
## One MultiMeshInstance3D from a list of transforms.
##
## Thirteen files were writing the same dozen lines - make the MultiMesh, set TRANSFORM_3D, size it,
## fill it, wrap it in a node, add it - and two of them (the circuit and the downhill) held copies of
## the same helper down to the character. Getting it wrong is quiet rather than loud: forget
## `transform_format` and every instance lands at the origin, forget `use_colors` and the per
## instance colours are ignored. One place to get it right.
##
## opts, all optional:
##   colours    PackedColorArray, one per instance -> turns on use_colors
##   custom     PackedColorArray, one per instance -> turns on use_custom_data (shaders read
##              INSTANCE_CUSTOM: tints, wind phase, animation offset)
##   material   Material for material_override
##   shadows    false to stop the batch casting shadows (default true)
##   range_end  hides the batch beyond this distance, m (0 = never)
##   range_margin  fade distance for range_end, m
##
## With `colours` and no `material`, the batch gets a plain material that reads the per-instance
## colour as albedo - which is the only reason to pass colours at all, and what the two copies of
## this helper used to do.
static func add(parent: Node, mesh: Mesh, xforms: Array[Transform3D], opts := {}) -> MultiMeshInstance3D:
	if mesh == null or xforms.is_empty():
		return null
	var colours: PackedColorArray = opts.get("colours", PackedColorArray())
	var custom: PackedColorArray = opts.get("custom", PackedColorArray())
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not colours.is_empty()
	mm.use_custom_data = not custom.is_empty()
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		if mm.use_colors:
			mm.set_instance_color(i, colours[i])
		if mm.use_custom_data:
			mm.set_instance_custom_data(i, custom[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	if opts.has("material"):
		mmi.material_override = opts.material
	elif mm.use_colors:
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.roughness = 0.7
		mmi.material_override = m
	if not bool(opts.get("shadows", true)):
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var range_end := float(opts.get("range_end", 0.0))
	if range_end > 0.0:
		mmi.visibility_range_end = range_end
		mmi.visibility_range_end_margin = float(opts.get("range_margin", 0.0))
	if parent != null:
		parent.add_child(mmi)
	return mmi

extends SceneTree
## Packs an ambientCG (CC0) material into the one-texture detail format of GroundMaterials (assets/ground/):
##   R = albedo as a variation around 0.5 (luminance / mean luminance * 0.5), G = roughness,
##   B, A = normal X, Y (OpenGL convention).
## The colour of a surface stays the game's own (styles, ambiences): the photograph only brings the detail.
##
##   Godot --headless --path <project> --script res://tools/bake_ground_detail.gd -- \
##       --src=C:/path/to/Rock030_1K-JPG --name=Rock030_1K-JPG --out=rock --size=1024
## `src` holds <name>_Color.jpg, <name>_Roughness.jpg and <name>_NormalGL.jpg.
##
## rock.png was made this way from https://ambientcg.com/a/Rock030 (grey fractured cliff).

func _initialize() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=")
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	var base := str(args.get("src", "")).path_join(str(args.get("name", "")))
	var size := int(args.get("size", "1024"))
	var col := Image.load_from_file(base + "_Color.jpg")
	var rough := Image.load_from_file(base + "_Roughness.jpg")
	var nrm := Image.load_from_file(base + "_NormalGL.jpg")
	if col == null or rough == null or nrm == null:
		push_error("missing maps for " + base)
		quit(1)
		return
	for img in [col, rough, nrm]:
		img.resize(size, size, Image.INTERPOLATE_LANCZOS)
		img.convert(Image.FORMAT_RGB8)
	var c := col.get_data()
	var r := rough.get_data()
	var n := nrm.get_data()
	var sum := 0.0
	for i in range(0, c.size(), 3):
		sum += c[i] * 0.3 + c[i + 1] * 0.5 + c[i + 2] * 0.2
	var mean := sum / (c.size() / 3.0)
	var out := PackedByteArray()
	out.resize(size * size * 4)
	for p in size * size:
		var i := p * 3
		var lum := (c[i] * 0.3 + c[i + 1] * 0.5 + c[i + 2] * 0.2) / mean * 0.5
		out[p * 4] = clampi(int(lum * 255.0), 0, 255)
		out[p * 4 + 1] = r[i]
		out[p * 4 + 2] = n[i]
		out[p * 4 + 3] = n[i + 1]
	var img := Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, out)
	var path := "res://assets/ground/%s.png" % str(args.get("out", "detail"))
	img.save_png(path)
	print("packed ", path)
	quit()

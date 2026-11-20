extends SceneTree
## Bakes the foliage textures of the trees (assets/foliage/) from CC0 photographed sets - one of Poly Haven:
##   fir_tree_01   (twig_diff, twig_alpha)              https://polyhaven.com/a/fir_tree_01
## and two of ambientCG:
##   LeafSet005 (Color, Opacity)                        https://ambientcg.com/a/LeafSet005
##   Bark012 (Color)                                    https://ambientcg.com/a/Bark012
## The sets hold single sprigs and single leaves, far too small to be a card of a tree seen from a drone:
## this tool arranges them into one whole spruce bough and one cluster of leaves, as Vegetation expects them
## (a bough along v, base at v = 0; a cluster on a disc with a solid corner for the cores of the crowns).
##
## Run it windowed (it renders with the GPU), with the folder holding the 1k JPG files named above:
##   Godot --path <project> --script res://tools/bake_foliage.gd -- --src=C:/path/to/jpgs
## The colours are normalised to a fixed mean (Vegetation multiplies them back by TEX_GAIN): the game tints
## the trees per instance, so the texture only carries the detail.

const OUT := "res://assets/foliage/"
# Sprigs of fir_tree_01_twig (1k): [region, base of the stem]
const SPRIGS := [
	[Rect2(306, 400, 358, 404), Vector2(492, 796)],
	[Rect2(644, 458, 340, 398), Vector2(806, 850)],
	[Rect2(664, 34, 302, 350), Vector2(828, 378)],
	[Rect2(188, 40, 256, 286), Vector2(313, 320)],
	[Rect2(496, 258, 152, 156), Vector2(552, 408)],
]
# LeafSet005 (1k, 1024 x 512): a twig of three leaves, then two single leaves [region, base of the stalk]
const LEAF_TWIG := [Rect2(12, 0, 412, 512), Vector2(288, 502)]
const LEAVES := [
	[Rect2(452, 44, 242, 368), Vector2(588, 406)],
	[Rect2(766, 30, 244, 402), Vector2(896, 427)],
]

const MIX := """
shader_type canvas_item;
render_mode blend_premul_alpha;
uniform sampler2D alpha_tex : filter_linear;
uniform float shade = 1.0;
void fragment() {
	float a = smoothstep(0.25, 0.75, texture(alpha_tex, UV).r);
	COLOR = vec4(texture(TEXTURE, UV).rgb * shade * a, a);
}
"""

var _src := ""
var _step := 0
var _jobs: Array = []   # [SubViewport, file name, target mean colour]
var _mix: Shader


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--src="):
			_src = a.trim_prefix("--src=")
	_mix = Shader.new()
	_mix.code = MIX
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_jobs.append([_bough(), "spruce_bough.png", Color(0.40, 0.47, 0.35)])
	_jobs.append([_cluster(), "leaf_cluster.png", Color(0.40, 0.46, 0.30)])
	_copy_bark("Bark012_1K-JPG_Color.jpg", "bark.jpg")


func _tex(file: String) -> ImageTexture:
	var img := Image.load_from_file(_src.path_join(file))
	return ImageTexture.create_from_image(img)


func _viewport(size: Vector2i) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = size
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	return vp


func _sprite(vp: SubViewport, tex: Texture2D, alpha: Texture2D, spr: Array, at: Vector2, rot: float, sc: float,
		shade: float, flip := false) -> void:
	var at_tex := AtlasTexture.new()
	at_tex.atlas = tex
	at_tex.region = spr[0]
	var s := Sprite2D.new()
	s.texture = at_tex
	s.centered = false
	s.offset = -(Vector2(spr[1]) - Rect2(spr[0]).position)
	s.position = at
	s.rotation = rot
	s.scale = Vector2(-sc if flip else sc, sc)
	s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var m := ShaderMaterial.new()
	m.shader = _mix
	m.set_shader_parameter("alpha_tex", alpha)
	m.set_shader_parameter("shade", shade)
	s.material = m
	vp.add_child(s)


## One spruce bough, 512 x 1024: stem from the bottom centre to the top, side branches leaning forward.
func _bough() -> SubViewport:
	var vp := _viewport(Vector2i(512, 1024))
	var tex := _tex("fir_tree_01_twig_diff_1k.jpg")
	var alpha := _tex("fir_tree_01_twig_alpha_1k.jpg")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var base := Vector2(256, 1016)
	var length := 985.0
	# the stem itself
	var stem := Line2D.new()
	stem.default_color = Color(0.16, 0.12, 0.08)
	stem.width_curve = Curve.new()
	stem.width_curve.add_point(Vector2(0, 1.0))
	stem.width_curve.add_point(Vector2(1, 0.15))
	stem.width = 10.0
	for k in 12:
		var t := k / 11.0
		stem.add_point(base + Vector2(sin(t * 5.0) * 4.0, -t * length * 0.93))
	vp.add_child(stem)
	# side branches, from the base to the tip, the lower layers first (darker: they are underneath)
	for layer in 2:
		var n := 21 if layer == 0 else 26
		for k in n:
			var t := (k + 0.5 + rng.randf_range(-0.3, 0.3)) / n
			t = lerpf(0.03, 0.9, t)
			var env := pow(sin(PI * pow(t, 0.62)), 0.75)  # widest at a third of the bough
			var side := -1.0 if (k + layer) % 2 == 0 else 1.0
			var reach := env * rng.randf_range(205.0, 250.0) * (0.78 if layer == 0 else 1.0)
			var ang := side * deg_to_rad(lerpf(64.0, 38.0, t) + rng.randf_range(-9.0, 9.0))
			var spr: Array = SPRIGS[rng.randi() % 4]
			var sc := reach / (Rect2(spr[0]).size.y * 0.97)
			var at := base + Vector2(0, -t * length)
			_sprite(vp, tex, alpha, spr, at, ang, maxf(sc, 0.12), rng.randf_range(0.6, 0.8) if layer == 0
					else rng.randf_range(0.85, 1.12), rng.randf() < 0.5)
	# twigs along the stem, pointing forward, and the tip
	for k in 13:
		var t := lerpf(0.1, 0.8, (k + rng.randf()) / 13.0)
		var spr: Array = SPRIGS[rng.randi() % SPRIGS.size()]
		_sprite(vp, tex, alpha, spr, base + Vector2(rng.randf_range(-6, 6), -t * length),
				deg_to_rad(rng.randf_range(-16.0, 16.0)), rng.randf_range(0.26, 0.4), rng.randf_range(0.9, 1.15),
				rng.randf() < 0.5)
	_sprite(vp, tex, alpha, SPRIGS[2], base + Vector2(0, -length * 0.8), 0.0, 0.52, 1.1)
	return vp


## A cluster of leaves on a disc, 1024 x 1024: branches of leafy twigs radiating from the centre, the
## layers underneath darker, single leaves filling the gaps.
func _cluster() -> SubViewport:
	var vp := _viewport(Vector2i(1024, 1024))
	var tex := _tex("LeafSet005_1K-JPG_Color.jpg")
	var alpha := _tex("LeafSet005_1K-JPG_Opacity.jpg")
	var rng := RandomNumberGenerator.new()
	rng.seed = 12
	var c := Vector2(512, 512)
	for layer in 3:
		var n: int = [9, 10, 8][layer]
		var shade: float = [0.42, 0.68, 1.0][layer]
		for k in n:
			var a := TAU * (k + rng.randf_range(-0.3, 0.3)) / n + layer * 0.41
			var dir := Vector2(cos(a), sin(a))
			var steps := 4 if layer < 2 else 3
			for j in steps:
				var r := 15.0 + j * 78.0 + rng.randf_range(-20.0, 20.0)
				if layer == 2:
					r += 30.0
				var side := Vector2(-dir.y, dir.x) * rng.randf_range(-40.0, 40.0)
				_sprite(vp, tex, alpha, LEAF_TWIG, c + dir * r + side, a + PI * 0.5 + rng.randf_range(-0.6, 0.6),
						rng.randf_range(0.33, 0.43), shade * rng.randf_range(0.85, 1.12), rng.randf() < 0.5)
	for k in 60:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * 400.0
		var spr: Array = LEAVES[rng.randi() % LEAVES.size()]
		_sprite(vp, tex, alpha, spr, c + Vector2(cos(a), sin(a)) * r, rng.randf() * TAU, rng.randf_range(0.22, 0.32),
				rng.randf_range(0.8, 1.15), rng.randf() < 0.5)
	return vp


## The bark, 512 x 512, as detail around a fixed mean (the shader gives it the colour of the tree).
func _copy_bark(src: String, dst: String) -> void:
	var img := Image.load_from_file(_src.path_join(src))
	if img == null:
		push_error("missing " + src)
		return
	img.resize(512, 512, Image.INTERPOLATE_LANCZOS)
	img.convert(Image.FORMAT_RGB8)
	var data := img.get_data()
	var sum := Vector3.ZERO
	for i in range(0, data.size(), 3):
		sum += Vector3(data[i], data[i + 1], data[i + 2])
	var mean := sum / (data.size() / 3.0)
	for i in range(0, data.size(), 3):
		for k in 3:
			# a quarter of the hue of the photo is kept: lichen and the red of the cracks
			var v := data[i + k] / lerpf((mean.x + mean.y + mean.z) / 3.0, mean[k], 0.75) * 0.5
			data[i + k] = clampi(int(v * 255.0), 0, 255)
	img.set_data(512, 512, false, Image.FORMAT_RGB8, data)
	img.save_jpg(OUT + dst, 0.9)


func _process(_dt: float) -> bool:
	_step += 1
	if _step < 6:
		return false
	for job in _jobs:
		var img: Image = (job[0] as SubViewport).get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		_finish(img, job[2])
		if str(job[1]).begins_with("spruce"):
			img.flip_y()  # Vegetation reads a bough from its base (v = 0) to its tip
		else:
			# nothing may reach the edge of the card: a leaf cut by it shows the square
			for y in img.get_height():
				for x in img.get_width():
					var rr := Vector2(x - 511.5, y - 511.5).length() / 512.0
					if rr > 0.9:
						var c := img.get_pixel(x, y)
						c.a *= 1.0 - smoothstep(0.9, 0.99, rr)
						img.set_pixel(x, y, c)
			# solid foliage in the corner: the cores of the crowns read it (Vegetation.cluster)
			var t: Color = job[2]
			img.fill_rect(Rect2i(0, 0, 56, 56), Color(t.r * 0.8, t.g * 0.8, t.b * 0.8, 1.0))
		img.save_png(OUT + str(job[1]))
		print("baked ", job[1], " ", img.get_size())
	quit()
	return true


## Un-premultiplies, normalises the colour to `target`, and fills the transparent pixels with the mean colour
## (so that the mipmaps do not bleed black into the edges of the needles).
func _finish(img: Image, target: Color) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var data := img.get_data()
	var sum := Vector3.ZERO
	var count := 0.0
	for i in range(0, data.size(), 4):
		var a := data[i + 3] / 255.0
		if a > 0.5:
			sum += Vector3(data[i], data[i + 1], data[i + 2]) / (255.0 * a)
			count += 1.0
	var mean := sum / maxf(count, 1.0)
	var k := Vector3(target.r / mean.x, target.g / mean.y, target.b / mean.z)
	var fill := Vector3(target.r, target.g, target.b) * 0.8
	for i in range(0, data.size(), 4):
		var a := data[i + 3] / 255.0
		var c := fill
		if a > 0.02:
			c = Vector3(data[i], data[i + 1], data[i + 2]) / (255.0 * a) * k
			c = c.lerp(fill, 1.0 - smoothstep(0.02, 0.4, a))
		data[i] = clampi(int(c.x * 255.0), 0, 255)
		data[i + 1] = clampi(int(c.y * 255.0), 0, 255)
		data[i + 2] = clampi(int(c.z * 255.0), 0, 255)
	img.set_data(w, h, false, Image.FORMAT_RGBA8, data)

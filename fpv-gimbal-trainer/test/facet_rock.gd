extends RefCounted
## Blocs de roche **à facettes**, pour les barres rocheuses.
##
## Les rochers du jeu (`Rocks`) sont des galets : une sphère subdivisée deux fois puis déformée par du
## bruit, donc des formes molles et rondes. C'est juste pour un bloc roulé au pied d'une pente, pas
## pour une barre : sur les téléobjectifs du Bec Rouge, les affleurements sont de la roche **cassée**,
## des plans francs qui se coupent en arêtes vives, empilés selon un même litage.
##
## D'où ces blocs-ci : un icosaèdre **non subdivisé** (12 sommets, 20 faces), chaque sommet poussé ou
## tiré au hasard, aplati selon le litage, la base coupée à plat — et surtout des **normales par
## face**, qui sont ce qui fait lire une arête. Un bloc de taille 1 tient dans une sphère de rayon 1,
## comme ceux du jeu.
##
## Le matériau est celui de `Rocks` : son shader est entièrement triplanaire sur la position du monde
## (strates, fissures, neige sur les faces hautes), il n'a besoin d'aucune UV et se moque de la forme.

const VARIANTS := 10

## Sommets de l'icosaèdre, et ses 20 faces.
const PHI := 1.618033988749895
## Tranches de taille : jusqu'à quelle taille (m), avec quelle échelle de texture et quelle force de
## relief. Un motif qui se répète tous les 1,8 m (0.55) est juste sur un caillou et s'étale en peau de
## léopard sur une paroi de douze mètres ; et plus la paroi est grande, moins on veut que la normale
## brouille ses arêtes.
## `coarse` monte avec la taille là où `bump` descend : sur une grande paroi, le relief fin est
## moyenné par les mipmaps dès vingt mètres de distance et la paroi redevient lisse ; celui de
## grande longueur d'onde, lui, tient jusqu'au bout.
const BUCKETS := [
	{"up_to": 3.0, "scale": 0.55, "bump": 0.45, "coarse": 0.30},
	{"up_to": 6.0, "scale": 0.36, "bump": 0.36, "coarse": 0.45},
	{"up_to": 10.0, "scale": 0.23, "bump": 0.28, "coarse": 0.58},
	{"up_to": 99.0, "scale": 0.15, "bump": 0.22, "coarse": 0.70},
]

## Niveau de cassure selon la taille. Vingt facettes suffisent à un caillou d'un mètre : à dix mètres
## de la caméra il n'en montre que trois ou quatre. Une paroi de douze mètres, elle, remplit le cadre
## et ses vingt grands plans se lisent comme un polyèdre de carton — le reproche de « trop lisse ».
## Chaque passe coupe les faces en quatre et décale les nouveaux sommets : 20, 80, puis 320 facettes,
## c'est-à-dire des plans de la taille d'un homme sur une paroi de douze mètres, comme sur les
## téléobjectifs.
const LOD := [{"up_to": 3.0, "cuts": 0}, {"up_to": 7.0, "cuts": 1}, {"up_to": 99.0, "cuts": 2}]

static var _meshes := {}
static var _mats := []


## Le matériau d'une paroi de taille `size`, pris dans sa tranche. Le shader est la copie de celui
## des rochers du jeu, à échelle réglable (`facet_rock.gdshader`) ; la roche y est plus sombre et plus
## contrastée, sinon les facettes ne se détachent pas.
static func material_for(size: float) -> ShaderMaterial:
	if _mats.is_empty():
		var sh: Shader = load("res://test/facet_rock.gdshader")
		for b in BUCKETS:
			var m := ShaderMaterial.new()
			m.shader = sh
			for t in ["detail", "cell", "normal"]:
				m.set_shader_parameter(t + "_tex", GroundMaterials.noise(t))
			m.set_shader_parameter("rock_a", Color(0.60, 0.575, 0.545))
			m.set_shader_parameter("rock_b", Color(0.135, 0.125, 0.12))
			m.set_shader_parameter("snow", Vegetation.snow_cover)
			m.set_shader_parameter("tex_scale", float(b.scale))
			m.set_shader_parameter("bump", float(b.bump))
			m.set_shader_parameter("bump_coarse", float(b.coarse))
			_mats.append(m)
	for i in BUCKETS.size():
		if size <= float(BUCKETS[i].up_to):
			return _mats[i]
	return _mats[_mats.size() - 1]


## Le nombre de passes de cassure que demande une paroi de taille `size`.
static func cuts_for(size: float) -> int:
	for l in LOD:
		if size <= float(l.up_to):
			return int(l.cuts)
	return int(LOD[LOD.size() - 1].cuts)


static func mesh(variant: int, cuts := 0) -> ArrayMesh:
	if not _meshes.has(cuts):
		var list: Array[ArrayMesh] = []
		for v in VARIANTS:
			list.append(_build(v, cuts))
		_meshes[cuts] = list
	return _meshes[cuts][posmod(variant, VARIANTS)]


static func _ico_vertices() -> Array:
	return [
		Vector3(-1, PHI, 0), Vector3(1, PHI, 0), Vector3(-1, -PHI, 0), Vector3(1, -PHI, 0),
		Vector3(0, -1, PHI), Vector3(0, 1, PHI), Vector3(0, -1, -PHI), Vector3(0, 1, -PHI),
		Vector3(PHI, 0, -1), Vector3(PHI, 0, 1), Vector3(-PHI, 0, -1), Vector3(-PHI, 0, 1),
	]


static func _ico_faces() -> Array:
	return [
		[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11],
		[1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
		[3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
		[4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1],
	]


## Un bloc : sommets déplacés, aplati selon y (le litage), faces cassées en quatre `cuts` fois, base
## tranchée, normales par face.
static func _build(variant: int, cuts := 0) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7700 + variant * 131 + cuts * 9173
	var flat := rng.randf_range(0.34, 0.62)      # épaisseur du banc, en fraction de sa largeur
	var pts: Array[Vector3] = []
	for v in _ico_vertices():
		var p: Vector3 = (v as Vector3).normalized()
		# chaque sommet pousse ou rentre : c'est ce qui casse la symétrie sans arrondir les faces
		p *= rng.randf_range(0.70, 1.32)
		p.y *= flat
		# léger cisaillement : les bancs ne sont jamais parfaitement d'équerre
		p.x += p.y * rng.randf_range(-0.35, 0.35)
		p.z += p.y * rng.randf_range(-0.35, 0.35)
		pts.append(p)
	var faces := _ico_faces()
	# Les passes de cassure. Chaque face est coupée en quatre sur ses milieux, et chaque nouveau
	# sommet est repoussé ou enfoncé le long de son rayon. Repoussé il fait un angle saillant, enfoncé
	# un dièdre rentrant : c'est le mélange des deux qui donne une roche cassée et non une boule
	# bosselée. L'amplitude se divise par deux à chaque passe, comme un bruit fractal — sinon la
	# troisième passe hérisse le bloc de pointes.
	var amp := 0.14
	for pass_i in cuts:
		var mids := {}
		var nf: Array = []
		for f in faces:
			var m: Array[int] = []
			for e in [[f[0], f[1]], [f[1], f[2]], [f[2], f[0]]]:
				var key: String = "%d_%d" % [mini(e[0], e[1]), maxi(e[0], e[1])]
				if not mids.has(key):
					var mid: Vector3 = (pts[e[0]] + pts[e[1]]) * 0.5
					mids[key] = pts.size()
					pts.append(mid * rng.randf_range(1.0 - amp, 1.0 + amp))
				m.append(int(mids[key]))
			nf.append([f[0], m[0], m[2]])
			nf.append([m[0], f[1], m[1]])
			nf.append([m[2], m[1], f[2]])
			nf.append([m[0], m[1], m[2]])
		faces = nf
		amp *= 0.5
	# base tranchée : le bloc est enfoncé dans la pente, pas posé dessus
	var cut := -flat * rng.randf_range(0.45, 0.85)
	for i in pts.size():
		if pts[i].y < cut:
			pts[i].y = cut
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for f in faces:
		var a: Vector3 = pts[f[0]]
		var b: Vector3 = pts[f[1]]
		var c: Vector3 = pts[f[2]]
		var n := (b - a).cross(c - a)
		if n.length() < 0.0001:
			continue          # la coupe de la base a aplati cette face en une arête
		n = n.normalized()
		for p in [a, b, c]:
			st.set_normal(n)
			st.add_vertex(p)
	# le fond, pour que le bloc ne soit pas creux vu d'en dessous
	var low: Array[int] = []
	for i in pts.size():
		if is_equal_approx(pts[i].y, cut):
			low.append(i)
	if low.size() >= 3:
		var centre := Vector3.ZERO
		for i in low:
			centre += pts[i]
		centre /= low.size()
		low.sort_custom(func(i: int, j: int) -> bool:
			return atan2(pts[i].z - centre.z, pts[i].x - centre.x) \
					< atan2(pts[j].z - centre.z, pts[j].x - centre.x))
		for k in low.size():
			for p in [centre, pts[low[(k + 1) % low.size()]], pts[low[k]]]:
				st.set_normal(Vector3.DOWN)
				st.add_vertex(p)
	return st.commit()


## Une paroi : deux à cinq bancs empilés selon le litage et décalés le long de la direction de la
## barre, ce qui donne les vires où la neige se pose. `up` est la normale du litage, `strike` la
## direction horizontale de la barre, `size` la taille du plus gros banc (m).
static func add_wall(parent: Node3D, base: Vector3, up: Vector3, strike: Vector3, size: float,
		rng: RandomNumberGenerator) -> int:
	var y := up.normalized()
	var x := (strike - y * strike.dot(y))
	if x.length() < 0.001:
		x = Vector3.RIGHT
	x = x.normalized()
	var z := x.cross(y)
	var n := rng.randi_range(2, 6)
	for k in n:
		var s: float = size * (1.0 - 0.10 * k) * rng.randf_range(0.7, 1.2)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh(rng.randi_range(0, VARIANTS - 1), cuts_for(s))
		mi.material_override = material_for(s)
		var b := Basis(x, y, z)
		# chaque banc est un peu de travers : alignés, ils dessinent des nattes rayées
		b = b.rotated(y, rng.randf_range(-0.7, 0.7))
		b = b.rotated(x, rng.randf_range(-0.25, 0.25))
		b = b.rotated(z, rng.randf_range(-0.25, 0.25))
		# scaled_local et non scaled : le banc doit être aplati selon SON litage, pas selon la
		# verticale du monde (Basis.scaled multiplie par la gauche)
		mi.basis = b.scaled_local(Vector3(s * rng.randf_range(0.9, 1.5), s, s * rng.randf_range(0.8, 1.2)))
		# empilés le long de la barre, chacun un peu plus bas et un peu décalé
		mi.position = base + x * (k * size * rng.randf_range(0.5, 0.95)) \
				- y * (k * size * 0.22) + z * rng.randf_range(-0.3, 0.3) * size
		mi.visibility_range_end = 260.0 + 110.0 * s
		mi.visibility_range_end_margin = 40.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DEPENDENCIES
		parent.add_child(mi)
	return n

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
const BUCKETS := [
	{"up_to": 3.0, "scale": 0.55, "bump": 0.45},
	{"up_to": 6.0, "scale": 0.36, "bump": 0.36},
	{"up_to": 10.0, "scale": 0.23, "bump": 0.28},
	{"up_to": 99.0, "scale": 0.15, "bump": 0.22},
]

static var _meshes := []
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
			_mats.append(m)
	for i in BUCKETS.size():
		if size <= float(BUCKETS[i].up_to):
			return _mats[i]
	return _mats[_mats.size() - 1]


static func mesh(variant: int) -> ArrayMesh:
	if _meshes.is_empty():
		for v in VARIANTS:
			_meshes.append(_build(v))
	return _meshes[posmod(variant, VARIANTS)]


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


## Un bloc : sommets déplacés, aplati selon y (le litage), base tranchée, normales par face.
static func _build(variant: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7700 + variant * 131
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
	# base tranchée : le bloc est enfoncé dans la pente, pas posé dessus
	var cut := -flat * rng.randf_range(0.45, 0.85)
	for i in pts.size():
		if pts[i].y < cut:
			pts[i].y = cut
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for f in _ico_faces():
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
		mi.mesh = mesh(rng.randi_range(0, VARIANTS - 1))
		mi.material_override = material_for(s)
		var b := Basis(x, y, z)
		# chaque banc est un peu de travers : alignés, ils dessinent des nattes rayées
		b = b.rotated(y, rng.randf_range(-0.7, 0.7))
		b = b.rotated(x, rng.randf_range(-0.25, 0.25))
		b = b.rotated(z, rng.randf_range(-0.25, 0.25))
		mi.basis = b.scaled(Vector3(s * rng.randf_range(0.9, 1.5), s, s * rng.randf_range(0.8, 1.2)))
		# empilés le long de la barre, chacun un peu plus bas et un peu décalé
		mi.position = base + x * (k * size * rng.randf_range(0.5, 0.95)) \
				- y * (k * size * 0.22) + z * rng.randf_range(-0.3, 0.3) * size
		mi.visibility_range_end = 260.0 + 110.0 * s
		mi.visibility_range_end_margin = 40.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DEPENDENCIES
		parent.add_child(mi)
	return n

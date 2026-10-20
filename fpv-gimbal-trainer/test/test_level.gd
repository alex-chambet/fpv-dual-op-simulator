extends Node3D
## Niveau de TEST : une face réelle, construite sur le MNT de l'IGN (RGE ALTI 1 m).
##
## Rien ici n'entre dans un build (voir test/README.md) : c'est un banc d'essai pour regarder un
## relief importé, en vol libre, sans sujet ni trajectoire de drone.
##
## Le terrain est bâti exactement comme ceux du jeu — `TerrainBuilder.build` à partir d'une fonction
## de hauteur — sauf que la hauteur ne vient pas d'un bruit : elle est lue dans la carte de hauteurs
## découpée dans le MNT (`test/dem/face_wnw.f32`). Autour, une deuxième carte au 10 m porte le relief
## réel sur 4 km, pour que l'horizon soit la vraie vallée et non un anneau inventé.

const DemMap := preload("res://test/dem_map.gd")
const FacetRock := preload("res://test/facet_rock.gd")
const NEAR := "res://test/dem/face_wnw"
const FAR := "res://test/dem/face_wnw_far"
const HORIZON := "res://test/dem/face_wnw_horizon"
const ORTHO := "res://test/dem/ortho"
const LINES := "res://test/dem/lignes.json"
const STYLE := "res://scenarios/environments/styles/freeride.tres"

## Maille du maillage détaillé, m. La carte est au mètre (moyenne de 4 points du lidar 50 cm) :
## à 1 m, le maillage rend donc tout ce que la donnée contient, barres rocheuses comprises.
const CELL := 1.0
## Rayon de l'anneau de terrain proche, m (il tient dans la carte au 10 m), puis de l'horizon, qui
## va chercher les vrais sommets de Tarentaise dans la carte au 25 m.
const FAR_RADIUS := 1800.0
const HORIZON_RADIUS := 9000.0
## Soleil : azimut et hauteur **vrais**. La face regarde au NW-WNW (305° mesurés) : en hiver le
## soleil ne la prend qu'en lumière rasante. Réglé sur un début d'après-midi de janvier (soleil au
## SSW, bas) : il frise la face par la gauche, les barres portent leur ombre et les couloirs se
## creusent. Comparé en rendu avec six positions : plus haut ou plus de face, la neige s'écrase en
## nappe blanche sans forme.
const SUN_AZIMUTH_TRUE := 205.0
const SUN_ELEVATION := 24.0
const AMBIENT_ENERGY := 0.62
## Plafond du nombre de blocs posés un par un sur les barres (les petites pierres, elles, passent
## toutes dans un MultiMesh et ne coûtent presque rien).
const MAX_BLOCKS := 2200

## Points de vue (F1 à F4). Chaque Vector3 est (x, hauteur AU-DESSUS DU SOL, z) : la hauteur est
## résolue sur le terrain, pour qu'un point de vue reste bon quel que soit le relief importé.
const VIEWS := [
	{"name": "Départ, sur la crête", "from": Vector3(0, 12, -35), "to": Vector3(0, 8, 260)},
	{"name": "Haut de la face, vue drone", "from": Vector3(-120, 60, 230), "to": Vector3(10, 10, 470)},
	{"name": "Barres du milieu", "from": Vector3(140, 70, 760), "to": Vector3(-10, 30, 480)},
	{"name": "Vue d'ensemble", "from": Vector3(-150, 540, 1700), "to": Vector3(0, 90, 480)},
	{"name": "Ligne FREERIDE_3", "from": Vector3(-40, 80, 320), "to": Vector3(-160, 5, 210)},
	{"name": "Ligne FREERIDE_5", "from": Vector3(110, 45, 640), "to": Vector3(20, 5, 560)},
]

var _near: DemMap
var _far: DemMap
var _horizon: DemMap
var _cam: Camera3D
var _hud: Label
var _speed := 25.0
var _yaw := 0.0
var _pitch := 0.0
var _view := 0
var _snow_material: Material
var _ortho_material: Material
var _ortho := false
## Les deux descentes filmées : {name, points (PackedVector3Array), dt, marker (MeshInstance3D), note}
var _lines := []
var _play := true
var _line_t := 0.0


func _ready() -> void:
	_near = DemMap.new()
	_far = DemMap.new()
	_horizon = DemMap.new()
	if not _near.load_map(NEAR):
		return
	if not _far.load_map(FAR):
		return
	if not _horizon.load_map(HORIZON):
		return
	var world_env: WorldEnvironment = $WorldEnvironment
	var sun: DirectionalLight3D = $Sun
	# Copie du style de la face inventée, recalée sur les rushs réels (voir _tune_style) : le fichier
	# du jeu n'est pas touché, c'est cette copie qui est appliquée.
	var style := (load(STYLE) as EnvironmentStyle).duplicate() as EnvironmentStyle
	_tune_style(style)
	var looks := EnvironmentBuilder.new()
	looks.style = style
	looks.apply_to_scene(world_env, sun)
	_place_sun(sun)
	# air d'altitude : sur les rushs, une crête à 3 km est encore franche — deux fois moins de brume
	# que ce que j'avais mis, et l'horizon à 9 km reste tout de même voilé
	world_env.environment.fog_density = 0.00004
	GraphicsSettings.apply(world_env.environment, sun, get_viewport())

	# Le rocher PEINT par le shader ne sort qu'à partir de ~56° (1 - cos 56 = 0.44). Deux raisons :
	#  - à 43°, la face se couvrait de mouchetis — elle ondule autour de 31°, donc un seuil bas est
	#    franchi partout et chaque bosse devenait une tache grise ;
	#  - et de près, cette peinture est le point faible du rendu : son mélange se dithère en taches
	#    grises floues, là où les rushs montrent des cailloux nets avec de la neige autour.
	# Le rocher visible est donc porté par la GÉOMÉTRIE (les parois à facettes), la peinture ne
	# servant plus que sur les presque-verticales où aucun bloc ne tiendrait.
	# Neige et rocher repris des rushs : la neige au soleil est très légèrement plus chaude que le
	# bleu du style (R210 G217 B223 mesuré), et les stries de vent sont partout sur place, d'où un
	# `ripple` plus fort.
	# Le rocher est volontairement plus chaud que sa couleur vraie : à l'ombre il ne reçoit que la
	# lumière du ciel, et sans ce correctif il vire au bleu (mesuré B - R = +41 contre +18 sur place).
	# Les deux blancs de la neige sont volontairement très proches : le shader les mélange avec un
	# bruit de 70 m, ce qui moutonnait la face en taches claires et sombres. La vraie neige a un
	# albédo uniforme — ce qu'on voit d'elle, c'est son relief et ses stries de vent, pas sa couleur.
	var mat := GroundMaterials.snow({"snow_a": Color(0.875, 0.91, 0.935), "snow_b": Color(0.915, 0.945, 0.97),
			"rock_a": Color(0.47, 0.445, 0.42), "rock_b": Color(0.19, 0.18, 0.17),
			"rock_start": 0.58, "rock_end": 0.74, "ripple": 2.0, "old_tracks": 0.6})
	var rect: Rect2 = _near.rect()
	var t0 := Time.get_ticks_msec()
	var mi := MeshInstance3D.new()
	mi.name = "Terrain"
	mi.mesh = TerrainBuilder.build(Callable(self, "ground"), rect.size.x * 0.5,
			rect.position.y, rect.end.y, CELL, 24.0)
	mi.material_override = mat
	add_child(mi)
	print("[TEST] terrain %.0f x %.0f m à la maille %.1f m : %d sommets en %d ms"
			% [rect.size.x, rect.size.y, CELL,
			(int(rect.size.x / CELL) + 1) * (int(rect.size.y / CELL) + 1), Time.get_ticks_msec() - t0])
	# Le relief réel continue au-delà du terrain détaillé, en deux anneaux : le proche (carte au 10 m,
	# maille fine, pour que la jonction ne se voie pas) et l'horizon (carte au 25 m, jusqu'à 9 km :
	# les vrais sommets de Tarentaise).
	# Pas de sommets inventés (FarScenery "hills") : leur base est une jupe PLATE posée à l'altitude
	# du bord de l'anneau, ce qui marche sur un décor de plaine mais pas ici — la vallée descend de
	# 1 000 m sous la face, et la jupe se voyait comme un mur vert en travers du paysage.
	FarScenery.build_into(self, Callable(self, "far_height"), 0, rect, mat,
			{"ring_radius": FAR_RADIUS, "ring_cell": 14.0})
	# le second anneau part du carré inscrit dans le premier (aucun trou entre les deux) et passe
	# 2 m plus bas, pour que le premier gagne partout où ils se recouvrent
	var c := rect.get_center()
	var side := FAR_RADIUS * sqrt(2.0)
	FarScenery.build_into(self, Callable(self, "horizon_height"), 0,
			Rect2(c.x - side * 0.5, c.y - side * 0.5, side, side), mat,
			{"ring_radius": HORIZON_RADIUS, "ring_cell": 50.0})
	# les deux anneaux s'appellent "FarTerrain" : le second est renommé pour s'y retrouver
	get_child(get_child_count() - 1).name = "HorizonTerrain"
	_snow_material = mat
	_paint_bands(mat, rect)
	_build_ortho_material()
	_build_rocks()
	_build_lines()

	_cam = Camera3D.new()
	_cam.far = 20000.0
	_cam.fov = 60.0
	add_child(_cam)
	_cam.make_current()
	_build_hud()
	_set_view(0)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Recale le style sur les rushs tournés sur place (DRONE_FPV + les quatre téléobjectifs).
##
## Mesuré sur les images réelles, puis sur le rendu, en classant les pixels (ciel / neige au soleil /
## neige à l'ombre / rocher) — `scratchpad/couleurs.py`. Deux écarts sautaient aux yeux des chiffres :
##   - le ciel du jeu est un bleu cobalt (B - R = +100) là où le vrai ciel d'altitude est un bleu
##     acier bien moins saturé (B - R = +68), et il pâlit plus vite vers l'horizon ;
##   - le rocher du jeu virait franchement au bleu (R 69 G 84 B 121) alors qu'il est neutre sur place
##     (R 74 G 83 B 92) : c'est l'ambiante, prise du ciel, qui le teintait.
## Dé-saturer le ciel corrige les deux d'un coup, puisque c'est lui qui éclaire les ombres.
func _tune_style(s: EnvironmentStyle) -> void:
	s.sky_top_color = Color(0.22, 0.38, 0.70)
	s.sky_horizon_color = Color(0.72, 0.80, 0.88)
	# le bleu profond descend bas et ne pâlit que juste au-dessus des crêtes (sur les rushs au grand
	# angle, le haut du cadre est presque marine) ; et le ciel était vide ce jour-là
	s.sky_curve = 0.06
	s.cloud_coverage = 0.04
	s.ground_horizon_color = Color(0.74, 0.80, 0.87)
	s.ground_bottom_color = Color(0.80, 0.85, 0.90)
	s.ambient_energy = AMBIENT_ENERGY
	s.adjustment_saturation = 1.0      # la scène réelle est bleu-blanc-gris, sans autre couleur
	# la vraie image a plus d'écart entre le soleil et l'ombre que le style du jeu (mesuré : 225 contre
	# 136 sur un plan à contre-jour, là où je plafonnais à 207 / 163)
	s.adjustment_contrast = 1.08
	s.exposure = 0.89
	s.fog_color = Color(0.78, 0.83, 0.90)
	s.fog_sun_scatter = 0.18
	# la brume ne doit pas blanchir le ciel : sur les rushs il reste franc jusqu'au ras de l'horizon
	s.fog_sky_affect = 0.08
	s.glow_intensity = 0.35
	s.glow_bloom = 0.02


## Matériau « orthophoto » : la vraie photo aérienne IGN plaquée sur le relief (touche O). Il sert à
## se repérer — comparer un rendu à une image de vidéo réelle — pas à jouer : forêts, routes, hameaux
## et barres rocheuses y sont à leur place exacte, ce qu'aucune texture procédurale ne donne.
func _build_ortho_material() -> void:
	var f := FileAccess.open(ORTHO + ".json", FileAccess.READ)
	if f == null:
		print("[TEST] pas d'orthophoto (", ORTHO, ".json absent)")
		return
	var txt := f.get_as_text()
	if not txt.is_empty() and txt.unicode_at(0) == 0xFEFF:
		txt = txt.substr(1)   # marque d'ordre des octets laissée par PowerShell
	var meta = JSON.parse_string(txt)
	if typeof(meta) != TYPE_DICTIONARY:
		print("[TEST] orthophoto : cadrage illisible")
		return
	if not ResourceLoader.exists(ORTHO + "_near.jpg"):
		print("[TEST] orthophoto : images non importées (lancer Godot --import)")
		return
	var m := ShaderMaterial.new()
	m.shader = load("res://test/ortho.gdshader")
	m.set_shader_parameter("near_tex", load(ORTHO + "_near.jpg"))
	m.set_shader_parameter("far_tex", load(ORTHO + "_far.jpg"))
	for key in ["near", "far"]:
		var b: Dictionary = meta[("ortho_" + key)]
		m.set_shader_parameter(key + "_frame", Vector4(float(b.x0), float(b.y1),
				1.0 / (float(b.x1) - float(b.x0)), 1.0 / (float(b.y1) - float(b.y0))))
	# mêmes rotation et origine que le découpage du MNT (azimut vrai de +z, convergence comprise)
	var g := deg_to_rad(float(_near.info.down_azimuth) - float(_near.info.convergence_deg))
	var dez := sin(g)
	var dnz := cos(g)
	m.set_shader_parameter("l93_basis", Vector4(-dnz, dez, dez, dnz))
	var o: Array = _near.info.origin_l93
	m.set_shader_parameter("l93_origin", Vector2(float(o[0]), float(o[1])))
	_ortho_material = m


## Peint le rocher des barres dans le masque de sol, au lieu de le laisser au seuil de pente.
##
## Le shader de neige tire le rocher de deux sources : la pente de la maille, ou le rouge du
## `GroundMask` — c'est ce second mécanisme qu'utilise la face freeride du jeu pour ses barres.
## Par la pente, le rocher tombait aux mauvais endroits : le shader lit la pente **à 1 m**, donc la
## moindre bosse, pendant que les parois à facettes se posent sur la pente **à 12 m**, celle des
## vraies barres. Deux zones différentes, d'où des taches grises sans un bloc dessus. Avec le
## masque, les deux coïncident : le rocher peint est exactement là où les parois se dressent.
func _paint_bands(mat: ShaderMaterial, rect: Rect2) -> void:
	var t0 := Time.get_ticks_msec()
	var mask := GroundMask.new()
	mask.setup(rect, 0.7)
	var red := Color(1, 0, 0)
	var n := 0
	var z := rect.position.y + 5.0
	while z < rect.end.y - 5.0:
		var x := rect.position.x + 5.0
		while x < rect.end.x - 5.0:
			if _slope_wide(x, z) > 54.0:
				mask.add_disc(Vector2(x, z), 3.6, red)
				n += 1
			x += 6.0
		z += 6.0
	add_child(mask)
	mask.bind(mat)
	mat.set_shader_parameter("rock_paint", 1.0)
	print("[TEST] barres peintes : %d disques en %d ms" % [n, Time.get_ticks_msec() - t0])


## Des blocs posés sur les barres rocheuses.
##
## La maille du MNT est le mètre : une barre y est une marche propre, alors que sur les rushs c'est
## de la roche cassée, avec des blocs qui dépassent et de la neige accrochée sur leurs vires. Les
## rochers du jeu (`Rocks`) savent justement se couvrir de neige sur leurs faces hautes, d'où
## `Vegetation.snow_cover`.
##
## Ils ne sont posés que là où la pente dépasse 46° **mesurée sur 12 m** : à 4 m, les stries de vent
## gravées dans la neige suffiraient à franchir le seuil et on sèmerait des blocs en pleine pente.
func _build_rocks() -> void:
	var t0 := Time.get_ticks_msec()
	# 0,3 et pas 0,9 : à 0,9 le shader enneige toute face tournée vers le haut et les blocs
	# ressortaient en points blancs. Sur les rushs ils sont noirs, avec de la neige seulement sur
	# leurs vires les plus plates.
	Vegetation.snow_cover = 0.42
	Rocks.moss_amount = 0.0
	var root := Node3D.new()
	root.name = "Rochers"
	add_child(root)
	var rng := RandomNumberGenerator.new()
	rng.seed = 918
	var rect: Rect2 = _near.rect()
	var grounds := PackedVector3Array()
	var sizes := PackedFloat32Array()
	var big := 0
	var z := rect.position.y + 6.0
	while z < rect.end.y - 6.0:
		var x := rect.position.x + 6.0
		while x < rect.end.x - 6.0:
			var sl := _slope_wide(x, z)
			var p := rng.randf()
			if sl > 46.0:
				var k := clampf((sl - 46.0) / 18.0, 0.0, 1.0)
				if p < 0.09 + 0.30 * k and big < MAX_BLOCKS:
					# Une paroi, pas un bloc isolé : les bancs s'empilent selon un même litage,
					# incliné entre la pente et l'horizontale, et s'étagent LE LONG de la barre.
					# La taille suit la raideur : 2 m sur une cassure à 46°, jusqu'à 15 m sur une
					# vraie paroi à 64°. C'est ce qui demandait une copie du shader des rochers à
					# échelle réglable (`facet_rock.gdshader`) : au-delà de 5 m, celui du jeu étale
					# son motif et la roche tourne à la peau de léopard. Bien enfoncés, sinon ils ont
					# l'air posés sur la neige au lieu d'en sortir.
					var s := (3.2 + 9.5 * k) * rng.randf_range(0.8, 1.25)
					var bx := x + rng.randf_range(-1.4, 1.4)
					var bz := z + rng.randf_range(-1.4, 1.4)
					var nrm := _normal_wide(bx, bz)
					var up := nrm.lerp(Vector3.UP, 0.35).normalized()
					var strike := Vector3(-nrm.z, 0.0, nrm.x).normalized()
					big += FacetRock.add_wall(root, Vector3(bx, ground(bx, bz) - s * 0.45, bz),
							up, strike, s, rng)
				elif p < 0.42:
					var ss := rng.randf_range(0.5, 1.4)
					grounds.append(Vector3(x, ground(x, z) - ss * 0.3, z))
					sizes.append(ss)
			elif sl > 28.0 and p < 0.004:
				# quelques pierres isolées en pleine pente, comme sur les rushs - rares, sinon la
				# face se couvre de points
				var s2 := rng.randf_range(0.5, 1.2)
				grounds.append(Vector3(x, ground(x, z) - s2 * 0.3, z))
				sizes.append(s2)
			x += 3.0
		z += 3.0
	var before := root.get_child_count()
	Rocks.scatter(root, grounds, sizes, 4100)
	# les pierres de moins d'un mètre : ni ombre portée (invisible de toute façon sous elles), ni
	# existence au-delà de 150 m
	for i in range(before, root.get_child_count()):
		var mm := root.get_child(i) as GeometryInstance3D
		if mm != null:
			mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mm.visibility_range_end = 150.0
			mm.visibility_range_end_margin = 30.0
	print("[TEST] rochers : %d blocs + %d pierres en %d ms" % [big, grounds.size(), Time.get_ticks_msec() - t0])


## Normale du terrain sur 12 m : l'assiette de la barre, dont on tire le litage des bancs.
func _normal_wide(x: float, z: float) -> Vector3:
	var gx := (ground_any(x + 6.0, z) - ground_any(x - 6.0, z)) / 12.0
	var gz := (ground_any(x, z + 6.0) - ground_any(x, z - 6.0)) / 12.0
	return Vector3(-gx, 1.0, -gz).normalized()


## Pente locale mesurée sur 12 m : celle de la barre, pas celle des stries de neige.
func _slope_wide(x: float, z: float) -> float:
	var gx := (ground_any(x + 6.0, z) - ground_any(x - 6.0, z)) / 12.0
	var gz := (ground_any(x, z + 6.0) - ground_any(x, z - 6.0)) / 12.0
	return rad_to_deg(atan(Vector2(gx, gz).length()))


## Les deux descentes filmées : la trace au sol et un skieur qui la parcourt à la vraie vitesse.
## Les lignes sont reconstituées (aucune des deux vidéos ne porte de GPS) : voir test/README.md.
func _build_lines() -> void:
	var f := FileAccess.open(LINES, FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY or not data.has("lines"):
		return
	var root := Node3D.new()
	root.name = "Lignes"
	add_child(root)
	for item in data.lines:
		var pts := PackedVector3Array()
		for p in item.points:
			pts.append(Vector3(float(p[0]), float(p[1]), float(p[2])))
		if pts.size() < 2:
			continue
		var col := Color(float(item.color[0]), float(item.color[1]), float(item.color[2]))
		var trace := MeshInstance3D.new()
		trace.name = "Trace_" + str(item.id)
		trace.mesh = _ribbon(pts, 1.6, 0.75)
		trace.material_override = _flat(col, 0.9)
		trace.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(trace)
		var marker := MeshInstance3D.new()
		marker.name = "Skieur_" + str(item.id)
		var caps := CapsuleMesh.new()
		caps.radius = 0.38
		caps.height = 1.75
		marker.mesh = caps
		marker.material_override = _flat(col, 1.0)
		root.add_child(marker)
		_lines.append({"name": str(item.name), "points": pts, "dt": float(item.dt),
				"marker": marker, "note": str(item.get("note", "")),
				"turns": item.get("turns", [])})
	print("[TEST] %d descentes chargées" % _lines.size())


## Ruban plat posé sur la trace, `half` mètres de part et d'autre, `drop` mètres sous les points
## (qui sont au centre du skieur, 90 cm au-dessus de la neige).
func _ribbon(pts: PackedVector3Array, half: float, drop: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in pts.size() - 1:
		var a := pts[i] - Vector3(0, drop, 0)
		var b := pts[i + 1] - Vector3(0, drop, 0)
		var d := b - a
		d.y = 0.0
		if d.length() < 0.001:
			continue
		d = d.normalized()
		var s := Vector3(-d.z, 0, d.x) * half
		for v in [a - s, a + s, b - s, b + s, b - s, a + s]:
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
	return st.commit()


func _flat(col: Color, alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(col, alpha)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


## Avance les skieurs des deux descentes (en boucle, avec une pause entre deux passages).
func _step_lines(delta: float) -> void:
	if _lines.is_empty():
		return
	var longest := 0.0
	for l in _lines:
		longest = maxf(longest, (l.points as PackedVector3Array).size() * float(l.dt))
	if _play:
		_line_t = fmod(_line_t + delta, longest + 2.5)
	for l in _lines:
		var pts: PackedVector3Array = l.points
		var k := int(_line_t / float(l.dt))
		var marker: MeshInstance3D = l.marker
		if k >= pts.size() - 1:
			marker.visible = false
			continue
		marker.visible = true
		var p := pts[k].lerp(pts[k + 1], fmod(_line_t / float(l.dt), 1.0))
		marker.position = p
		var d := pts[mini(k + 2, pts.size() - 1)] - pts[k]
		if d.length() > 0.01:
			marker.look_at(p + d, Vector3.UP)
			marker.rotate_object_local(Vector3.RIGHT, PI * 0.5)   # la capsule est debout


## Bascule entre la neige du jeu et l'orthophoto.
func set_ortho(on: bool) -> void:
	if _ortho_material == null:
		return
	_ortho = on
	for n in ["Terrain", "FarTerrain", "HorizonTerrain"]:
		var mi: MeshInstance3D = get_node_or_null(NodePath(n))
		if mi != null:
			mi.material_override = _ortho_material if on else _snow_material
	# en mode orthophoto on compare un motif à une image : les blocs posés gêneraient
	var rocks := get_node_or_null(^"Rochers")
	if rocks != null:
		(rocks as Node3D).visible = not on


## Pose le soleil à son vrai azimut. Le style, lui, range le soleil avec `sun_azimuth`, dont la
## convention est celle des décors inventés : ici on connaît le nord, alors on construit la direction
## et on y regarde. Azimut dans le repère du jeu : 0 = dans l'axe +z (le soleil fait face au versant),
## 90 = vers +x ; +z vaut l'azimut vrai `down_azimuth`, d'où la soustraction.
func _place_sun(sun: DirectionalLight3D) -> void:
	var a := deg_to_rad(float(_near.info.get("down_azimuth", 112.5)) - SUN_AZIMUTH_TRUE)
	var e := deg_to_rad(SUN_ELEVATION)
	var to_sun := Vector3(sin(a) * cos(e), sin(e), cos(a) * cos(e))
	sun.look_at_from_position(Vector3.ZERO, -to_sun, Vector3.UP)


## Hauteur du terrain détaillé (c'est elle que TerrainBuilder échantillonne).
func ground(x: float, z: float) -> float:
	return _near.height(x, z)


## Hauteur autour du terrain détaillé : la carte au 10 m tant qu'elle couvre, l'horizon au-delà.
func far_height(x: float, z: float) -> float:
	return _far.height(x, z) if _far.rect().has_point(Vector2(x, z)) else _horizon.height(x, z)


## Idem, 2 m plus bas : l'anneau de l'horizon passe sous l'anneau proche là où ils se recouvrent
## (deux mailles différentes sur le même relief se battraient en profondeur).
func horizon_height(x: float, z: float) -> float:
	return far_height(x, z) - 2.0


# --- Vol libre -------------------------------------------------------------------------------------

## Le sol où qu'on soit : le terrain détaillé s'il couvre le point, sinon la carte au 10 m.
func ground_any(x: float, z: float) -> float:
	return _near.height(x, z) if _near.rect().has_point(Vector2(x, z)) else _far.height(x, z)


## (x, hauteur au-dessus du sol, z) -> point du monde.
func _above_ground(v: Vector3) -> Vector3:
	return Vector3(v.x, ground_any(v.x, v.z) + v.y, v.z)


func _set_view(i: int) -> void:
	_view = wrapi(i, 0, VIEWS.size())
	var v: Dictionary = VIEWS[_view]
	_cam.position = _above_ground(v.from)
	_cam.look_at(_above_ground(v.to), Vector3.UP)
	_yaw = _cam.rotation.y
	_pitch = _cam.rotation.x


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * 0.003
		_pitch = clampf(_pitch - event.relative.y * 0.003, -1.5, 1.5)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_speed = minf(_speed * 1.25, 400.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_speed = maxf(_speed * 0.8, 2.0)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_ESCAPE:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
			KEY_TAB:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
						else Input.MOUSE_MODE_CAPTURED
			KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_F5, KEY_F6:
				_set_view(event.physical_keycode - KEY_F1)
			KEY_F:
				_set_view(_view + 1)
			KEY_O:
				set_ortho(not _ortho)
			KEY_P:
				_play = not _play
			KEY_R:
				_line_t = 0.0


func _process(delta: float) -> void:
	if _cam == null:
		return
	_cam.rotation = Vector3(_pitch, _yaw, 0.0)
	var dir := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		dir -= _cam.global_transform.basis.z
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		dir += _cam.global_transform.basis.z
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		dir -= _cam.global_transform.basis.x
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		dir += _cam.global_transform.basis.x
	if Input.is_physical_key_pressed(KEY_SPACE):
		dir += Vector3.UP
	if Input.is_physical_key_pressed(KEY_CTRL):
		dir -= Vector3.UP
	var boost := 4.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0
	if dir != Vector3.ZERO:
		_cam.position += dir.normalized() * _speed * boost * delta
	_step_lines(delta)
	_update_hud()


# --- Affichage -------------------------------------------------------------------------------------

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(14, 12)
	_hud.add_theme_font_size_override("font_size", 15)
	_hud.add_theme_color_override("font_shadow_color", Color(0.05, 0.0, 0.1, 0.9))
	_hud.add_theme_constant_override("shadow_outline_size", 5)
	_hud.add_theme_constant_override("shadow_offset_x", 0)
	_hud.add_theme_constant_override("shadow_offset_y", 0)
	layer.add_child(_hud)


func _update_hud() -> void:
	var p := _cam.position
	var g: float = ground_any(p.x, p.z)
	var slope := _slope_at(p.x, p.z)
	_hud.text = "TEST  -  %s\n%s\n%s  -  maille %.0f m\n\n" % [
			str(_near.info.get("name", "")), str(VIEWS[_view].name),
			str(_near.info.get("source", "")).get_slice(" (", 0), CELL]
	_hud.text += "x %+.0f   z %+.0f   altitude %.0f m  (%.0f m au-dessus du sol)\n" % [
			p.x, p.z, _near.real_altitude(p.y), p.y - g]
	_hud.text += "pente sous la caméra %.0f deg   vitesse %.0f m/s   %d img/s\n\n" % [
			slope, _speed, Engine.get_frames_per_second()]
	_hud.text += "ZQSD / flèches : voler   Espace / Ctrl : monter, descendre   Maj : x4\n"
	_hud.text += "molette : vitesse   F1-F6 ou F : points de vue   O : orthophoto   P : pause des descentes   R : les rejouer   Tab : souris   Échap : menu"


func _slope_at(x: float, z: float) -> float:
	var gx := (ground_any(x + 2.0, z) - ground_any(x - 2.0, z)) * 0.25
	var gz := (ground_any(x, z + 2.0) - ground_any(x, z - 2.0)) * 0.25
	return rad_to_deg(atan(Vector2(gx, gz).length()))

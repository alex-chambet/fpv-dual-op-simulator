extends PathSubject
## Une descente filmée, rejouée par le vrai skieur du jeu.
##
## `PathSubject` est la classe que suivent tous les sujets du jeu : elle avance le long d'une courbe,
## calcule l'inclinaison que le virage demande (`lean_deg`), celle qu'il demandera dans une demi-
## seconde (`lean_soon_deg`) et l'accélération verticale du terrain (`heave_g`). `AthleteModel` lit
## ces trois nombres et en tire toute la gestuelle : genoux qui traversent, bâton qui part en avant,
## extension, planter, angulation, absorption. En héritant d'elle, la descente reconstituée profite
## de tout ça sans le réécrire — et le skieur du TEST est exactement celui du jeu.
##
## La seule chose qu'on impose, c'est la trajectoire et le **tempo** : les points viennent de
## `dem/lignes.json`, espacés de `dt` secondes, donc leur écartement EST la vitesse mesurée dans les
## rushs. On en fait un profil de vitesse pour que la courbe soit parcourue au bon rythme.

const CATALOGUE := "res://scenarios/subjects/catalogue/ski_freeride.tres"

var parts := {}
var athlete: AthleteModel
var loop_pause := 2.0      ## s d'attente avant de recommencer la descente

var _pause := 0.0
var _jumps: Array[Dictionary] = []   ## {r0, r1} : les passages en l'air, en fraction de la courbe
var _was_air := false
var _since_land := 9.0


## À appeler avant d'ajouter le nœud à la scène. `pts` sont les points de la ligne, espacés de `dt`
## secondes ; `ground` est la hauteur du terrain, pour coller les skis à la neige.
func setup(pts: PackedVector3Array, dt: float, ground: Callable) -> void:
	var c := Curve3D.new()
	# tangentes lissées : sans elles la courbe est une ligne brisée, le lacet saute à chaque point
	# et l'inclinaison que `PathSubject` en déduit devient du bruit
	for i in pts.size():
		var t: Vector3 = (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]) * 0.25
		c.add_point(pts[i], -t, t)
	curve = c
	ground_height = ground
	snap_tolerance = 2.5
	anticipation = 0.5
	max_lean_deg = 55.0        # freeride : il met beaucoup de carre
	lean_gain = 0.85
	speed_variation = 0.0      # le tempo vient des rushs, pas d'une oscillation inventée
	min_speed = 3.0
	base_speed = 12.0
	speed_profile = _profile_from(pts, dt)


## Les passages en l'air, donnés par le générateur en **indices de points**, traduits en fractions de
## la courbe — c'est dans cette unité que `PathSubject` suit la descente. Un point sur deux cents
## n'est pas une fraction sur deux cents : les points sont à pas de temps constant, donc d'autant
## plus écartés qu'il va vite, et un saut est justement l'endroit où il va le plus vite.
func set_air_spans(spans: Array, pts: PackedVector3Array) -> void:
	_jumps.clear()
	var n := pts.size()
	if n < 2:
		return
	var cum := PackedFloat32Array()
	cum.resize(n)
	cum[0] = 0.0
	for i in range(1, n):
		cum[i] = cum[i - 1] + pts[i].distance_to(pts[i - 1])
	var total: float = cum[n - 1]
	if total <= 0.0:
		return
	for s in spans:
		var a := clampi(int(s[0]), 0, n - 1)
		var b := clampi(int(s[1]), 0, n - 1)
		# un demi-segment de marge de part et d'autre : le point `a` est le premier qui est EN
		# L'AIR, donc le décollage est quelque part entre lui et le précédent. Sans cette marge, le
		# skieur passe une ou deux images en pose de ski alors qu'il est à quatre mètres du sol.
		var r0: float = cum[a] / total
		var r1: float = cum[b] / total
		if a > 0:
			r0 -= (cum[a] - cum[a - 1]) * 0.5 / total
		if b < n - 1:
			r1 += (cum[b + 1] - cum[b]) * 0.5 / total
		_jumps.append({"r0": r0, "r1": r1})


## Le saut en cours, vide s'il est sur la neige. C'est la convention du jeu : `AthleteModel` la lit
## pour poser le skieur en l'air (jambes ramassées, bâtons rentrés, aucun planter), et
## `PathSubject._in_air()` pour cesser de coller le modèle au sol pendant le vol.
func current_jump() -> Dictionary:
	for ev in _jumps:
		if progress_ratio >= float(ev.r0) - 0.0005 and progress_ratio <= float(ev.r1):
			return ev
	return {}


func _in_air() -> bool:
	return not current_jump().is_empty()


## Vitesse le long de la courbe, relevée sur l'espacement des points (qui sont à pas de temps fixe).
func _profile_from(pts: PackedVector3Array, dt: float) -> PackedFloat32Array:
	var n := pts.size()
	if n < 3 or dt <= 0.0:
		return PackedFloat32Array()
	var cum := PackedFloat32Array()
	cum.resize(n)
	cum[0] = 0.0
	for i in range(1, n):
		cum[i] = cum[i - 1] + pts[i].distance_to(pts[i - 1])
	var total := cum[n - 1]
	if total <= 0.0:
		return PackedFloat32Array()
	var out := PackedFloat32Array()
	var samples := 240
	out.resize(samples)
	var k := 1
	for i in samples:
		var target := total * float(i) / float(samples - 1)
		while k < n - 1 and cum[k] < target:
			k += 1
		out[i] = pts[k].distance_to(pts[k - 1]) / dt
	return out


func _build_model() -> Node3D:
	var sheet := load(CATALOGUE) as SubjectDefinition
	if sheet == null:
		return Node3D.new()
	# une copie de la fiche du jeu, aux couleurs du skieur des rushs (veste rouge, casque sombre) :
	# c'est elle qu'on a suivie image par image, autant qu'on la reconnaisse
	var def := sheet.duplicate() as SubjectDefinition
	def.placeholder_color = Color(0.80, 0.16, 0.12)
	def.placeholder_accent = Color(0.10, 0.10, 0.12)
	var root := PlaceholderModel.build(def, parts)
	aim_height = float(parts.get("aim_y", 1.1))
	if parts.has("athlete"):
		athlete = parts["athlete"]
	return root


func _on_advanced(delta: float) -> void:
	if athlete == null:
		return
	# il se ramasse un peu quand ça va vite, comme le fait l'archétype GLISSE_PENTE du jeu
	var want := 0.3 * smoothstep(11.0, 17.0, speed_now)
	var in_air := _in_air()
	if _was_air and not in_air:
		_since_land = 0.0
	_was_air = in_air
	_since_land += delta
	if in_air:
		want = 0.35                              # ramassé sur ses jambes, comme l'archétype FREERIDE
	# réception écrasée : c'est elle qui se voit, bien plus que le vol lui-même
	want = maxf(want, 0.95 * (1.0 - smoothstep(0.08, 0.5, _since_land)))
	athlete.tuck = lerpf(athlete.tuck, want, 1.0 - exp(-delta / (0.08 if in_air or _since_land < 0.5 else 0.5)))
	athlete.update(self, delta)


## Repart du sommet tout de suite.
func restart() -> void:
	_pause = 0.0
	_was_air = false
	_since_land = 9.0
	finished = false
	progress_ratio = 0.0
	lean_deg = 0.0
	lean_soon_deg = 0.0
	if follower != null:
		follower.progress = 0.0


## Avance la descente et la relance après une pause, pour qu'on puisse la regarder en boucle.
func step(delta: float) -> void:
	if finished:
		_pause += delta
		if _pause >= loop_pause:
			_pause = 0.0
			finished = false
			follower.progress = 0.0
			progress_ratio = 0.0
			lean_deg = 0.0
			lean_soon_deg = 0.0
		if model != null:
			model.visible = false
		return
	if model != null:
		model.visible = true
	advance(delta)

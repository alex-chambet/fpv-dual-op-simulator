class_name GraphicsPanel
extends SettingsRows
## The graphics settings (GraphicsSettings and the motion blur), shared by Paramètres and the pause menu (Échap >
## Graphismes): display, quality (a preset, then each detail on its own), image, display of the game. Every change
## is saved at once and applied to the running scene.

var _preset: OptionButton
var _details := {}      # name of a detail -> its control (refreshed when the preset changes)


func _init() -> void:
	add_theme_constant_override("separation", 8)
	custom_minimum_size.x = 600

	_heading("Affichage")
	_opt("Mode d'affichage", GraphicsSettings.WINDOW_LABELS, GraphicsSettings.window_mode, func(i):
		GraphicsSettings.window_mode = i
		_changed(true))
	_check("Synchro verticale", GraphicsSettings.vsync, func(on):
		GraphicsSettings.vsync = on
		_changed(true))
	_opt("Limite d'images / s", GraphicsSettings.FPS_LABELS, GraphicsSettings.fps_cap, func(i):
		GraphicsSettings.fps_cap = i
		_changed(true))
	_opt("Échelle de rendu", GraphicsSettings.SCALE_LABELS, GraphicsSettings.render_scale, func(i):
		GraphicsSettings.render_scale = i
		_changed())
	_note("En dessous de 100 %, l'image 3D est calculée plus petite puis agrandie (AMD FSR) : beaucoup plus fluide, "
			+ "un peu moins nette. Le texte et le cadre restent nets.")

	_heading("Qualité")
	_preset = _opt("Préréglage", GraphicsSettings.LABELS + ["Personnalisé"], 0, func(i):
		if i < GraphicsSettings.LABELS.size():
			GraphicsSettings.set_preset(i)
			_refresh()
			_changed())
	_preset.set_item_disabled(GraphicsSettings.LABELS.size(), true)
	_detail_opt("aa", "Anticrénelage", GraphicsSettings.AA_LABELS)
	_detail_opt("aniso", "Filtrage des textures", GraphicsSettings.ANISO_LABELS)
	_detail_opt("shadows", "Ombres", GraphicsSettings.SHADOW_LABELS)
	_detail_opt("ssao", "Occlusion ambiante", GraphicsSettings.SSAO_LABELS)
	_detail_check("ssil", "Lumière indirecte")
	_detail_check("shafts", "Rayons de lumière (forêt)")
	_detail_opt("trees", "Distance des arbres détaillés", GraphicsSettings.TREE_LABELS)
	_detail_opt("grass", "Herbe et petits détails", GraphicsSettings.GRASS_LABELS)
	_detail_opt("crowd", "Spectateurs", GraphicsSettings.CROWD_LABELS)
	_note("Choisir un préréglage règle tous les détails ; changer un détail passe en « Personnalisé ». Les petits "
			+ "détails (pierres, plantes) et les spectateurs sont pris en compte à la session suivante.")

	_heading("Image")
	_slider("Luminosité", -1.0, 1.0, 0.1, GraphicsSettings.brightness, func(v): return "%+.1f IL" % v, func(v):
		GraphicsSettings.brightness = v
		_changed())
	_slider("Contraste", 0.8, 1.25, 0.05, GraphicsSettings.contrast, func(v): return "%d %%" % roundi(v * 100.0), func(v):
		GraphicsSettings.contrast = v
		_changed())
	_slider("Saturation", 0.5, 1.5, 0.05, GraphicsSettings.saturation, func(v): return "%d %%" % roundi(v * 100.0), func(v):
		GraphicsSettings.saturation = v
		_changed())
	_check("Vignettage", GraphicsSettings.vignette, func(on):
		GraphicsSettings.vignette = on
		_changed())
	_check("Aberration chromatique", GraphicsSettings.aberration, func(on):
		GraphicsSettings.aberration = on
		_changed())
	_check("Grain", GraphicsSettings.grain, func(on):
		GraphicsSettings.grain = on
		_changed())
	_check("Profondeur de champ", GraphicsSettings.dof, func(on):
		GraphicsSettings.dof = on
		_changed())
	_check("Exposition automatique", GraphicsSettings.auto_exposure, func(on):
		GraphicsSettings.auto_exposure = on
		_changed())
	_note("La profondeur de champ est celle de l'optique choisie, à f/2 : à 85 mm le sujet se détache "
			+ "du fond, à 24 mm tout reste net à partir de 6 m. C'est la vraie raison de changer "
			+ "d'optique. L'exposition automatique imite le diaphragme auto d'une caméra, qui met un "
			+ "instant à rattraper quand on panote vers le ciel.")
	_opt("Flou de mouvement", MotionBlur.LABELS, MotionBlur.level, func(i):
		MotionBlur.level = i
		MotionBlur.save_level())
	_note("Le flou est celui du temps de pose de la caméra, pas celui du jeu : l'angle d'obturation. "
			+ "La règle des 180° (obturateur ouvert sur un demi-tour) est ce qui donne son mouvement "
			+ "au cinéma — c'est 1/60 s pour une image livrée en 30 i/s.")

	_heading("Interface en jeu")
	_slider("Opacité des infos", 0.2, 1.0, 0.05, GraphicsSettings.hud_opacity, func(v): return "%d %%" % roundi(v * 100.0), func(v):
		GraphicsSettings.hud_opacity = v
		_changed())
	_opt("Taille des infos", GraphicsSettings.HUD_SIZE_LABELS, GraphicsSettings.hud_size, func(i):
		GraphicsSettings.hud_size = i
		_changed())
	_slider("Opacité du cadre", 0.3, 1.0, 0.05, GraphicsSettings.frame_opacity, func(v): return "%d %%" % roundi(v * 100.0), func(v):
		GraphicsSettings.frame_opacity = v
		_changed())
	_opt("Couleurs du cadre", GraphicsSettings.FRAME_COLOR_LABELS, GraphicsSettings.frame_colors, func(i):
		GraphicsSettings.frame_colors = i
		_changed())
	_refresh()


## Saves, then applies to the window (display settings) and to the running scene.
func _changed(display := false) -> void:
	GraphicsSettings.save()
	if display:
		GraphicsSettings.apply_display()
	if is_inside_tree():
		GraphicsSettings.apply_live(get_tree())


## Shows the preset ("Personnalisé" when the details differ from it) and the value of every detail.
func _refresh() -> void:
	_preset.select(GraphicsSettings.LABELS.size() if GraphicsSettings.custom else GraphicsSettings.quality)
	for key in _details:
		var c: Control = _details[key]
		var v = GraphicsSettings.detail(key)
		if c is OptionButton:
			(c as OptionButton).select(int(v))
		elif c is CheckButton:
			(c as CheckButton).set_pressed_no_signal(bool(v))


func _detail_opt(key: String, label: String, items: Array) -> void:
	_details[key] = _opt(label, items, int(GraphicsSettings.detail(key)), func(i):
		GraphicsSettings.set_detail(key, i)
		_refresh()
		_changed())


func _detail_check(key: String, label: String) -> void:
	_details[key] = _check(label, bool(GraphicsSettings.detail(key)), func(on):
		GraphicsSettings.set_detail(key, on)
		_refresh()
		_changed())


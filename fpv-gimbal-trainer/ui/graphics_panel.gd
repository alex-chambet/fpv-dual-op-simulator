class_name GraphicsPanel
extends VBoxContainer
## The graphics settings (GraphicsSettings and the motion blur), shared by Paramètres and the pause menu (Échap >
## Graphismes): display, quality (a preset, then each detail on its own), image, display of the game. Every change
## is saved at once and applied to the running scene.

const LABEL_WIDTH := 250.0

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
	_opt("Flou de mouvement", MotionBlur.LABELS, MotionBlur.level, func(i):
		MotionBlur.level = i
		MotionBlur.save_level())

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


# --- Rows ---------------------------------------------------------------------------------------------

func _heading(t: String) -> void:
	var l := Label.new()
	l.text = t
	if get_child_count() > 0:
		var gap := Control.new()
		gap.custom_minimum_size.y = 6
		add_child(gap)
	add_child(Neon.caps(l, 20))


func _note(t: String) -> void:
	var l := Label.new()
	l.text = t
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 560
	l.add_theme_color_override("font_color", Neon.TEXT_DIM)
	l.add_theme_font_size_override("font_size", 15)
	add_child(l)


func _row(label: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	add_child(row)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size.x = LABEL_WIDTH
	row.add_child(l)
	return row


func _opt(label: String, items: Array, selected: int, on_change: Callable) -> OptionButton:
	var o := OptionButton.new()
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for t in items:
		o.add_item(str(t))
	o.select(clampi(selected, 0, items.size() - 1))
	o.item_selected.connect(on_change)
	_row(label).add_child(o)
	return o


func _check(label: String, on: bool, on_change: Callable) -> CheckButton:
	var c := CheckButton.new()
	c.button_pressed = on
	c.toggled.connect(on_change)
	var row := _row(label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	row.add_child(c)
	return c


func _slider(label: String, lo: float, hi: float, step: float, value: float, fmt: Callable,
		on_change: Callable) -> HSlider:
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var v := Label.new()
	v.custom_minimum_size.x = 80
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.text = str(fmt.call(value))
	s.value_changed.connect(func(x):
		v.text = str(fmt.call(x))
		on_change.call(x))
	var row := _row(label)
	row.add_child(s)
	row.add_child(v)
	return s

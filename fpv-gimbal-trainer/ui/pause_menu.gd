class_name PauseMenu
extends CanvasLayer
## Pause menu of a session (Esc): resume, restart, graphics, gameplay (lens), back to the main menu. It keeps working while the
## game tree is paused (process_mode ALWAYS). Esc resumes (or leaves the graphics page).

signal resume_requested
signal restart_requested
signal quit_requested
## The player picked another lens (focal length in mm); only emitted when `lens_editable`.
signal lens_changed(mm: int)
## The player changed a frame-guide display option (thirds grid): the frame guide should redraw.
signal guide_changed

## Lens shown in the Gameplay page, and whether it can be changed here (not during a scored session: the score and
## the replay depend on it).
var lens_mm := 24
var lens_editable := false

var _main_page: Control
var _graphics_page: Control
var _gameplay_page: Control
var _lens_opt: OptionButton
var _lens_note: Label
var _profile_opt: OptionButton
var _thirds_check: CheckButton
var _resume_button: Button
var _ambience_opt: OptionButton
var _ambience_ids: Array = []


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 120
	visible = false
	_build()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.06, 0.0, 0.13, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	panel.add_child(margin)
	var stack := VBoxContainer.new()
	margin.add_child(stack)

	_main_page = VBoxContainer.new()
	_main_page.custom_minimum_size.x = 380
	_main_page.add_theme_constant_override("separation", 12)
	stack.add_child(_main_page)
	var title := Label.new()
	title.text = "PAUSE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Neon.title(title, 44)
	_main_page.add_child(title)
	_resume_button = _button(_main_page, "Reprendre (Échap)", func(): resume_requested.emit())
	_button(_main_page, "Recommencer", func(): restart_requested.emit())
	_button(_main_page, "Graphismes", func(): _show_page(_graphics_page))
	_button(_main_page, "Gameplay", func(): _show_page(_gameplay_page))
	_button(_main_page, "Quitter vers le menu", func(): quit_requested.emit())

	_graphics_page = VBoxContainer.new()
	_graphics_page.custom_minimum_size.x = 660
	_graphics_page.add_theme_constant_override("separation", 12)
	_graphics_page.visible = false
	stack.add_child(_graphics_page)
	var gtitle := Label.new()
	gtitle.text = "GRAPHISMES"
	gtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Neon.title(gtitle, 44)
	_graphics_page.add_child(gtitle)
	# ambience of this session, then every graphics setting (shared with Paramètres), in a scrolling list
	var arow := HBoxContainer.new()
	_graphics_page.add_child(arow)
	var al := Label.new()
	al.text = "Ambiance"
	al.custom_minimum_size.x = GraphicsPanel.LABEL_WIDTH
	arow.add_child(al)
	_ambience_opt = OptionButton.new()
	_ambience_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ambience_opt.item_selected.connect(func(i):
		var scn := get_tree().current_scene
		if scn != null and scn.has_method("set_ambience") and i < _ambience_ids.size():
			scn.set_ambience(_ambience_ids[i]))
	arow.add_child(_ambience_opt)
	visibility_changed.connect(_refresh_ambience)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(640, 560)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_graphics_page.add_child(scroll)
	scroll.add_child(GraphicsPanel.new())
	_button(_graphics_page, "Retour (Échap)", func(): _show_page(null))

	_gameplay_page = VBoxContainer.new()
	_gameplay_page.custom_minimum_size.x = 380
	_gameplay_page.add_theme_constant_override("separation", 12)
	_gameplay_page.visible = false
	stack.add_child(_gameplay_page)
	var ptitle := Label.new()
	ptitle.text = "GAMEPLAY"
	ptitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Neon.title(ptitle, 44)
	_gameplay_page.add_child(ptitle)
	var lrow := HBoxContainer.new()
	_gameplay_page.add_child(lrow)
	var ll := Label.new()
	ll.text = "Optique"
	ll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lrow.add_child(ll)
	_lens_opt = OptionButton.new()
	for mm in SessionConfig.LENSES:
		_lens_opt.add_item("%d mm" % mm)
	_lens_opt.item_selected.connect(func(i):
		lens_mm = SessionConfig.LENSES[i]
		lens_changed.emit(lens_mm))
	lrow.add_child(_lens_opt)
	var grow := HBoxContainer.new()
	_gameplay_page.add_child(grow)
	var gl := Label.new()
	gl.text = "Sensibilité gimbal"
	gl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grow.add_child(gl)
	_profile_opt = OptionButton.new()
	for t in ["Lent", "Moyen", "Rapide"]:
		_profile_opt.add_item(t)
	_profile_opt.item_selected.connect(func(i):
		var scn := get_tree().current_scene
		if scn != null and scn.has_method("set_gimbal_profile"):
			scn.set_gimbal_profile(i))
	grow.add_child(_profile_opt)
	var trow := HBoxContainer.new()
	_gameplay_page.add_child(trow)
	var tl := Label.new()
	tl.text = "Grille des tiers"
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	trow.add_child(tl)
	var tcheck := CheckButton.new()
	tcheck.button_pressed = FrameGuide.show_thirds
	tcheck.toggled.connect(func(on: bool):
		FrameGuide.show_thirds = on
		FrameGuide.save_thirds()
		guide_changed.emit())  # (the frame guide redraws)
	trow.add_child(tcheck)
	_thirds_check = tcheck
	var prow := HBoxContainer.new()
	_gameplay_page.add_child(prow)
	var pl := Label.new()
	pl.text = "Vue du drone (1 joueur)"
	pl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prow.add_child(pl)
	var pcheck := CheckButton.new()
	pcheck.button_pressed = DronePip.enabled
	pcheck.toggled.connect(func(on: bool):
		DronePip.enabled = on
		DronePip.save_enabled())
	prow.add_child(pcheck)
	_lens_note = Label.new()
	_lens_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lens_note.add_theme_color_override("font_color", Neon.TEXT_DIM)
	_gameplay_page.add_child(_lens_note)
	_button(_gameplay_page, "Retour (Échap)", func(): _show_page(null))

func _button(parent: Control, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = 44
	b.pressed.connect(action)
	parent.add_child(b)
	return b


## Shows a sub-page (null = the main page).
func _show_page(page: Control) -> void:
	_graphics_page.visible = page == _graphics_page
	_gameplay_page.visible = page == _gameplay_page
	_main_page.visible = page == null
	if page == _gameplay_page:
		var i := SessionConfig.LENSES.find(lens_mm)
		_lens_opt.select(maxi(i, 0))
		_lens_opt.disabled = not lens_editable
		_thirds_check.set_pressed_no_signal(FrameGuide.show_thirds)  # (the G key may have changed it)
		var scn := get_tree().current_scene
		if scn != null and scn.has_method("current_gimbal_profile"):
			_profile_opt.select(clampi(int(scn.current_gimbal_profile()), 0, 2))
		_lens_note.text = "" if lens_editable else "L'optique est figée pendant une session notée (le score en dépend) : change-la dans le menu d'accueil."
	if page == null:
		_resume_button.grab_focus()


func open() -> void:
	_show_page(null)
	visible = true
	_resume_button.grab_focus()


func close() -> void:
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		if not _main_page.visible:
			_show_page(null)
		else:
			resume_requested.emit()


## Fills the ambience list with what the running scene offers, its current one selected (hidden if none).
func _refresh_ambience() -> void:
	if not visible or _ambience_opt == null:
		return
	var scn := get_tree().current_scene
	var row := _ambience_opt.get_parent() as Control
	if scn == null or not scn.has_method("ambience_choices"):
		row.visible = false
		return
	row.visible = true
	_ambience_ids = scn.ambience_choices()
	_ambience_opt.clear()
	for id in _ambience_ids:
		_ambience_opt.add_item(str(Ambience.LABELS[id]))
	_ambience_opt.select(maxi(_ambience_ids.find(scn.current_ambience()), 0))

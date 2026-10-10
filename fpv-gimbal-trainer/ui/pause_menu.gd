class_name PauseMenu
extends CanvasLayer
## Pause menu of a session (Esc): resume, restart, graphics, gameplay (lens), back to the main menu. It keeps working while the
## game tree is paused (process_mode ALWAYS). Esc resumes (or leaves the graphics page).

signal resume_requested
signal restart_requested
signal quit_requested
## The player picked another lens (focal length in mm); only emitted when `lens_editable`.
signal lens_changed(mm: int)
## The player turned the "dark outside the frame" option on or off (FrameGuide.blackout was already updated).
signal blackout_changed

## Lens shown in the Gameplay page, and whether it can be changed here (not during a scored session: the score and
## the replay depend on it).
var lens_mm := 24
var lens_editable := false

var _main_page: Control
var _graphics_page: Control
var _gameplay_page: Control
var _lens_opt: OptionButton
var _lens_note: Label
var _resume_button: Button


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
	_graphics_page.custom_minimum_size.x = 380
	_graphics_page.add_theme_constant_override("separation", 12)
	_graphics_page.visible = false
	stack.add_child(_graphics_page)
	var gtitle := Label.new()
	gtitle.text = "GRAPHISMES"
	gtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Neon.title(gtitle, 44)
	_graphics_page.add_child(gtitle)
	var qrow := HBoxContainer.new()
	_graphics_page.add_child(qrow)
	var ql := Label.new()
	ql.text = "Qualité graphique"
	ql.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	qrow.add_child(ql)
	var qopt := OptionButton.new()
	for t in GraphicsSettings.LABELS:
		qopt.add_item(t)
	qopt.select(GraphicsSettings.quality)
	qopt.item_selected.connect(func(i):
		GraphicsSettings.quality = i
		GraphicsSettings.save()
		GraphicsSettings.apply_live(get_tree()))
	qrow.add_child(qopt)
	var row := HBoxContainer.new()
	_graphics_page.add_child(row)
	var l := Label.new()
	l.text = "Flou de mouvement"
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var opt := OptionButton.new()
	for t in MotionBlur.LABELS:
		opt.add_item(t)
	opt.select(MotionBlur.level)
	opt.item_selected.connect(func(i):
		MotionBlur.level = i
		MotionBlur.save_level())
	row.add_child(opt)
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
	var brow := HBoxContainer.new()
	_gameplay_page.add_child(brow)
	var bl := Label.new()
	bl.text = "Noir hors du cadre"
	bl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	brow.add_child(bl)
	var bcheck := CheckButton.new()
	bcheck.button_pressed = FrameGuide.blackout
	bcheck.toggled.connect(func(on: bool):
		FrameGuide.blackout = on
		FrameGuide.save_blackout()
		blackout_changed.emit())
	brow.add_child(bcheck)
	var bnote := Label.new()
	bnote.text = "Assombrit tout ce qui est hors du rectangle vert : on ne voit pas l'environnement autour du cadre, comme avec une vraie caméra."
	bnote.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bnote.add_theme_color_override("font_color", Neon.TEXT_DIM)
	_gameplay_page.add_child(bnote)
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

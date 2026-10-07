class_name PauseMenu
extends CanvasLayer
## Pause menu of a session (Esc): resume, restart, graphics, back to the main menu. It keeps working while the
## game tree is paused (process_mode ALWAYS). Esc resumes (or leaves the graphics page).

signal resume_requested
signal restart_requested
signal quit_requested

var _main_page: Control
var _graphics_page: Control
var _resume_button: Button


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 120
	visible = false
	_build()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
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
	title.add_theme_font_size_override("font_size", 32)
	_main_page.add_child(title)
	_resume_button = _button(_main_page, "Reprendre (Échap)", func(): resume_requested.emit())
	_button(_main_page, "Recommencer", func(): restart_requested.emit())
	_button(_main_page, "Graphismes", func(): _show_graphics(true))
	_button(_main_page, "Quitter vers le menu", func(): quit_requested.emit())

	_graphics_page = VBoxContainer.new()
	_graphics_page.custom_minimum_size.x = 380
	_graphics_page.add_theme_constant_override("separation", 12)
	_graphics_page.visible = false
	stack.add_child(_graphics_page)
	var gtitle := Label.new()
	gtitle.text = "GRAPHISMES"
	gtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gtitle.add_theme_font_size_override("font_size", 32)
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
	_button(_graphics_page, "Retour (Échap)", func(): _show_graphics(false))


func _button(parent: Control, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = 44
	b.pressed.connect(action)
	parent.add_child(b)
	return b


func _show_graphics(on: bool) -> void:
	_graphics_page.visible = on
	_main_page.visible = not on
	if not on:
		_resume_button.grab_focus()


func open() -> void:
	_show_graphics(false)
	visible = true
	_resume_button.grab_focus()


func close() -> void:
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		if _graphics_page.visible:
			_show_graphics(false)
		else:
			resume_requested.emit()

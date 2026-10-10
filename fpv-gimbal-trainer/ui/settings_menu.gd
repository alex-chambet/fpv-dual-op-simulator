extends Control
## Settings: controller configuration (sub-menu), graphics quality and motion blur. The choices are saved at once
## in user://menu_prefs.json (read back by the main menu and the sessions).

const MENU_SCENE := "res://scenes/main_menu.tscn"
const INPUT_SCENE := "res://scenes/input_debug.tscn"


func _ready() -> void:
	var bg := Neon.backdrop()
	bg.material.set_shader_parameter("dim", 0.55)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 640
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)

	var title := Label.new()
	title.text = "PARAMÈTRES"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Neon.title(title, 52)
	box.add_child(title)
	box.add_child(HSeparator.new())

	box.add_child(_heading("Manettes"))
	var pad := Button.new()
	pad.text = "Configuration manette"
	pad.custom_minimum_size.y = 44
	pad.pressed.connect(func(): get_tree().change_scene_to_file(INPUT_SCENE))
	box.add_child(pad)
	box.add_child(HSeparator.new())

	box.add_child(_heading("Graphismes"))
	var q := _option_row(box, "Qualité graphique", GraphicsSettings.LABELS, GraphicsSettings.quality)
	q.item_selected.connect(func(i):
		GraphicsSettings.quality = i
		GraphicsSettings.save())
	var b := _option_row(box, "Flou de mouvement", MotionBlur.LABELS, MotionBlur.level)
	b.item_selected.connect(func(i):
		MotionBlur.level = i
		MotionBlur.save_level())
	var hint := Label.new()
	hint.text = "Ces réglages sont aussi accessibles en jeu (Échap > Graphismes)."
	hint.add_theme_color_override("font_color", Neon.TEXT_DIM)
	box.add_child(hint)
	box.add_child(HSeparator.new())

	var back := Button.new()
	back.text = "Retour (Échap)"
	back.custom_minimum_size.y = 44
	back.pressed.connect(_back)
	box.add_child(back)
	pad.grab_focus()


func _heading(t: String) -> Label:
	var l := Label.new()
	l.text = t
	return Neon.caps(l, 20)


func _option_row(parent: Control, label: String, items: Array, selected: int) -> OptionButton:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size.x = 200
	row.add_child(l)
	var o := OptionButton.new()
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for t in items:
		o.add_item(t)
	o.select(selected)
	row.add_child(o)
	return o


func _back() -> void:
	get_tree().change_scene_to_file(MENU_SCENE)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		_back()

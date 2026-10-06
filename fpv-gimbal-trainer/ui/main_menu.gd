extends Control
## Main menu, in three steps: 1. choose a sport (only the sports flagged `in_menu`), 2. choose how to
## play it (guided course when the sport has one, or training session with a drone movement and a
## level), 3. launch. Tools at the bottom.

const TOOLS := [
	{"name": "Historique et replays", "scene": "res://scenes/history.tscn"},
	{"name": "Configuration manette", "scene": "res://scenes/input_debug.tscn"},
	{"name": "Bac à sable gimbal", "scene": "res://scenes/gimbal_test.tscn"},
	{"name": "Éditeur de trajectoire", "scene": "res://scenes/flight_editor.tscn"},
]

const MOVEMENT_LABELS := {
	"pursuit": ["Poursuite arrière", "Le drone suit le sujet par l'arrière."],
	"lateral": ["Suivi latéral", "Le drone vole à côté du sujet, en avançant et reculant."],
	"frontal": ["Face au sujet", "Le drone recule devant le sujet, en le filmant de face."],
	"orbit": ["Orbite", "Le drone tourne autour du sujet pendant qu'il avance."],
	"reveal": ["Dévoilement", "Le sujet est caché derrière un obstacle, puis découvert quand le drone le dépasse."],
	"flyby": ["Survol rapide", "Le drone croise le sujet à grande vitesse, tout près."],
}

const LEVEL_LABELS := ["Auto (difficulté du sport)", "Aléatoire", "Niveau 1 - très facile", "Niveau 2 - facile",
		"Niveau 3 - moyen", "Niveau 4 - difficile", "Niveau 5 - très difficile"]
## What makes a session hard (see DroneDifficulty): the movement, the axes (pan / tilt) and the proximity.
const DIFFICULTY_HELP := "La difficulté vient du mouvement du drone, des axes à gérer (pan seul / tilt seul, puis les deux) et de la distance au sujet. Le drone vole toujours de façon fluide."

var _sports: Array[SubjectDefinition] = []
var _sport: SubjectDefinition
var _group := ButtonGroup.new()
var _cards: Array[Button] = []
var _sport_info: Label
var _guided_box: Control
var _guided_button: Button
var _guided_info: Label
var _movement_opt: OptionButton
var _level_opt: OptionButton
var _movement_info: Label
var _level_info: Label
const LENS_HELP := {24: "  (large, plus facile)", 35: "", 50: "  (le sujet est plus gros, plus dur à garder)", 85: "  (très serré : chaque geste compte)"}
var _lens_opt: OptionButton
var _train_button: Button


func _ready() -> void:
	SessionScorer.reset()
	SessionScorer.next_label = ""
	ScenarioMatrix.current = null
	SubjectCatalogue.reload()
	_sports = SubjectCatalogue.menu_sports()
	_build_ui()
	if not _sports.is_empty():
		_select(0)
	if not _cards.is_empty():
		_cards[0].grab_focus()


# --- UI -------------------------------------------------------------------------------------------

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.1, 0.13)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 1140
	box.add_theme_constant_override("separation", 8)
	center.add_child(box)

	var title := Label.new()
	title.text = "FPV GIMBAL TRAINER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	box.add_child(title)
	var sub := Label.new()
	sub.text = "Garde le sujet dans le cadre avec le gimbal."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.modulate = Color(1, 1, 1, 0.7)
	box.add_child(sub)
	box.add_child(HSeparator.new())

	box.add_child(_heading("1.  Choisis ton sport"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	for i in _sports.size():
		var s := _sports[i]
		var card := Button.new()
		card.toggle_mode = true
		card.button_group = _group
		card.text = "%d   %s\n%s" % [i + 1, s.display_name, _stars(s.base_difficulty)]
		card.custom_minimum_size = Vector2(0, 70)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.add_theme_font_size_override("font_size", 18)
		card.pressed.connect(_select.bind(i))
		row.add_child(card)
		_cards.append(card)
	_sport_info = Label.new()
	_sport_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sport_info.custom_minimum_size.y = 44
	_sport_info.modulate = Color(1, 1, 1, 0.75)
	box.add_child(_sport_info)
	box.add_child(HSeparator.new())

	box.add_child(_heading("2.  Choisis comment jouer"))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 20)
	box.add_child(cols)
	cols.add_child(_build_guided_panel())
	cols.add_child(_build_training_panel())
	box.add_child(HSeparator.new())

	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 10)
	box.add_child(tools)
	var rnd := Button.new()
	rnd.text = "Session aléatoire (R)"
	rnd.pressed.connect(_start_random)
	tools.add_child(rnd)
	tools.add_child(VSeparator.new())
	for t in TOOLS:
		var b := Button.new()
		b.text = t.name
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func(): get_tree().change_scene_to_file(t.scene))
		tools.add_child(b)
	var quit := Button.new()
	quit.text = "Quitter"
	quit.pressed.connect(func(): get_tree().quit())
	tools.add_child(quit)


func _panel(heading: String, width: float) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = width
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	panel.add_child(margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	margin.add_child(v)
	var h := Label.new()
	h.text = heading
	h.add_theme_font_size_override("font_size", 20)
	v.add_child(h)
	return v


func _build_guided_panel() -> Control:
	var v := _panel("Parcours guidé", 440)
	_guided_box = v.get_parent().get_parent()
	var d := Label.new()
	d.text = "Un parcours fixe, identique à chaque fois : idéal pour progresser et battre ton meilleur score."
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.modulate = Color(1, 1, 1, 0.65)
	v.add_child(d)
	_guided_info = Label.new()
	_guided_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_guided_info.custom_minimum_size.y = 80
	v.add_child(_guided_info)
	_guided_button = Button.new()
	_guided_button.text = "Lancer le parcours guidé (G)"
	_guided_button.custom_minimum_size.y = 46
	_guided_button.pressed.connect(_start_guided)
	v.add_child(_guided_button)
	return _guided_box


func _build_training_panel() -> Control:
	var v := _panel("Session d'entraînement", 640)
	var d := Label.new()
	d.text = "Choisis le mouvement du drone et la difficulté : chaque session est générée avec un trajet différent."
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.modulate = Color(1, 1, 1, 0.65)
	v.add_child(d)
	_movement_opt = _option_row(v, "Mouvement du drone")
	_movement_opt.add_item("Au hasard (selon le niveau)")
	for m in ScenarioMatrix.MOVEMENTS:
		_movement_opt.add_item("%s   %s" % [MOVEMENT_LABELS[m.id][0], _dots(DroneDifficulty.movement_tier(m.id))])
	_movement_opt.item_selected.connect(func(_i): _update_info())
	_movement_info = Label.new()
	_movement_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_movement_info.custom_minimum_size.y = 40
	_movement_info.modulate = Color(1, 1, 1, 0.65)
	v.add_child(_movement_info)
	_level_opt = _option_row(v, "Niveau")
	for t in LEVEL_LABELS:
		_level_opt.add_item(t)
	_level_opt.item_selected.connect(func(_i): _update_info())
	_level_info = Label.new()
	_level_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_level_info.custom_minimum_size.y = 40
	_level_info.modulate = Color(1, 1, 1, 0.65)
	v.add_child(_level_info)
	_lens_opt = _option_row(v, "Optique")
	for mm in SessionConfig.LENSES:
		_lens_opt.add_item("%d mm%s" % [mm, LENS_HELP[mm]])
	_train_button = Button.new()
	_train_button.text = "Lancer la session d'entraînement (Entrée)"
	_train_button.custom_minimum_size.y = 46
	_train_button.pressed.connect(_start_training)
	v.add_child(_train_button)
	return v.get_parent().get_parent()


func _option_row(parent: Control, label: String) -> OptionButton:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size.x = 170
	row.add_child(l)
	var o := OptionButton.new()
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(o)
	return o


func _heading(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", 22)
	return l


static func _stars(n: int) -> String:
	return "Difficulté " + _dots(n)


static func _dots(n: int) -> String:
	return "●".repeat(n) + "○".repeat(5 - n)


# --- State ---------------------------------------------------------------------------------------

## The fixed scenario of the selected sport ({} if it has none).
func _guided_entry() -> Dictionary:
	if _sport == null:
		return {}
	for e in ScenarioRegistry.list():
		if str(e.subject) == _sport.id:
			return e
	return {}


func _select(i: int) -> void:
	_sport = _sports[i]
	_cards[i].button_pressed = true
	_update_info()


func _update_info() -> void:
	if _sport == null:
		return
	_sport_info.text = "%s  -  %s" % [_sport.display_name, _sport.description]
	var e := _guided_entry()
	_guided_button.disabled = e.is_empty()
	if e.is_empty():
		_guided_info.text = "Pas de parcours guidé pour ce sport : lance une session d'entraînement."
	else:
		var best: int = SessionScorer.get_best(str(e.id))
		_guided_info.text = "%s\n%s\nMeilleur score : %s" % [e.name, e.desc, str(best) if best > 0 else "-"]
	var m := _selected_movement()
	_movement_info.text = str(MOVEMENT_LABELS[m][1]) if m != "" else "Un mouvement tiré au hasard, d'autant plus difficile que le niveau est élevé."
	var lv := _level_opt.selected  # 0 auto, 1 random, 2..6 = level 1..5
	if lv == 0:
		_level_info.text = "Niveau %d (celui du sport). %s" % [_sport.base_difficulty, DroneDifficulty.describe(_sport.base_difficulty)]
	elif lv == 1:
		_level_info.text = "Un niveau tiré au hasard à chaque session.\n" + DIFFICULTY_HELP
	else:
		_level_info.text = DroneDifficulty.describe(lv - 1)


func _selected_movement() -> String:
	return "" if _movement_opt.selected <= 0 else str(ScenarioMatrix.MOVEMENTS[_movement_opt.selected - 1].id)


# --- Launch --------------------------------------------------------------------------------------

func _start_guided() -> void:
	var e := _guided_entry()
	if not e.is_empty():
		ScenarioMatrix.launch_fixed(get_tree(), e)


func _start_training() -> void:
	if _sport == null:
		return
	var lv := _level_opt.selected  # 0 auto, 1 random, 2..6 = level 1..5
	var level := -1 if lv == 0 else (0 if lv == 1 else lv - 1)
	ScenarioMatrix.launch(get_tree(), ScenarioMatrix.generate(_sport.id, _selected_movement(), level, null, {}, SessionConfig.LENSES[_lens_opt.selected]))


func _start_random() -> void:
	ScenarioMatrix.launch(get_tree(), ScenarioMatrix.generate())


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var n: int = event.physical_keycode - KEY_1
	if n >= 0 and n < _sports.size():
		_select(n)
		return
	match event.physical_keycode:
		KEY_G: _start_guided()
		KEY_ENTER, KEY_KP_ENTER: _start_training()
		KEY_R: _start_random()
		KEY_ESCAPE: get_tree().quit()

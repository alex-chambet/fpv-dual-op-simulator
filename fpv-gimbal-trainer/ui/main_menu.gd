extends Control
## Main menu, in three steps: 1. choose a sport (only the sports flagged `in_menu`), 2. choose how to
## play it (training session: 1 or 2 players, drone movement, level, lens), 3. launch. Next to it the sandbox
## (free flight in the countryside, no time limit). Tools at the bottom.

const TOOLS := [
	{"name": "Historique et replays", "scene": "res://scenes/history.tscn"},
	{"name": "Paramètres", "scene": "res://scenes/settings.tscn"},
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
var _mode_opt: OptionButton
var _mode_info: Label
var _screens_opt: OptionButton
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
	var prefs := _load_prefs()
	if not _sports.is_empty():
		var idx := 0
		for i in _sports.size():
			if _sports[i].id == str(prefs.get("sport", "")):
				idx = i
		_select(idx)
	_apply_prefs(prefs)
	for o in [_mode_opt, _movement_opt, _level_opt, _lens_opt, _screens_opt]:
		o.item_selected.connect(func(_i): _save_prefs())
	if not _cards.is_empty():
		_cards[0].grab_focus()


# --- Saved choices ---------------------------------------------------------------------------------

const PREFS_PATH := "user://menu_prefs.json"


func _load_prefs() -> Dictionary:
	if not FileAccess.file_exists(PREFS_PATH):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(PREFS_PATH))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func _apply_prefs(prefs: Dictionary) -> void:
	MotionBlur.level = clampi(int(prefs.get("blur", MotionBlur.level)), 0, MotionBlur.LABELS.size() - 1)
	GraphicsSettings.quality = clampi(int(prefs.get("quality", GraphicsSettings.quality)), 0, GraphicsSettings.LABELS.size() - 1)
	for pair in [[_mode_opt, "mode"], [_movement_opt, "movement"], [_level_opt, "level"], [_lens_opt, "lens"], [_screens_opt, "screens"]]:
		var o: OptionButton = pair[0]
		var i := int(prefs.get(pair[1], 1 if pair[1] == "blur" else 0))
		if i >= 0 and i < o.item_count:
			o.select(i)
	_update_info()


func _save_prefs() -> void:
	if _sport == null:
		return
	var f := FileAccess.open(PREFS_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"sport": _sport.id, "mode": _mode_opt.selected, "movement": _movement_opt.selected,
				"level": _level_opt.selected, "lens": _lens_opt.selected, "screens": _screens_opt.selected, "blur": MotionBlur.level,
				"quality": GraphicsSettings.quality}, "\t"))


# --- UI -------------------------------------------------------------------------------------------

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.1, 0.13)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	# Scrolls if the menu is taller than the window
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
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
	cols.add_child(_build_training_panel())
	cols.add_child(_build_sandbox_panel())
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


func _build_training_panel() -> Control:
	var v := _panel("Session d'entraînement", 640)
	var d := Label.new()
	d.text = "Choisis le mouvement du drone et la difficulté : chaque session est générée avec un trajet différent."
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.modulate = Color(1, 1, 1, 0.65)
	v.add_child(d)
	_mode_opt = _option_row(v, "Mode de jeu")
	_mode_opt.add_item("1 joueur  -  le drone vole tout seul")
	_mode_opt.add_item("2 joueurs  -  un pilote FPV + un cadreur")
	_mode_opt.item_selected.connect(func(_i): _update_info())
	_mode_info = Label.new()
	_mode_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mode_info.modulate = Color(1, 1, 1, 0.65)
	v.add_child(_mode_info)
	_screens_opt = _option_row(v, "Écrans (2 joueurs)")
	_screens_opt.add_item("Un écran  -  vue pilote en incrustation")
	var n_screens := DisplayServer.get_screen_count()
	_screens_opt.add_item("Deux écrans  -  vue pilote sur le 2e écran" + ("" if n_screens > 1 else "  (aucun 2e écran détecté)"))
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


func _build_sandbox_panel() -> Control:
	var v := _panel("Bac à sable", 400)
	var d := Label.new()
	d.text = "La campagne de la Départementale en libre, sans limite de temps ni score : routes, village, fermes, voitures, camions, cyclistes et piétons.\n\nSans manette, ou avec une seule (celle de la gimbal) : le drone décolle tout seul et vole de façon aléatoire mais fluide dans la carte, pour que tu règles ta gimbal.\nAvec une 2e manette (pilote) : vol acro.\nLa touche M change de mode (auto, clavier, acro).\nL'optique et l'écran du pilote sont ceux de la session d'entraînement."
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.modulate = Color(1, 1, 1, 0.65)
	d.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(d)
	var b := Button.new()
	b.text = "Lancer le bac à sable (B)"
	b.custom_minimum_size.y = 46
	b.pressed.connect(_start_sandbox)
	v.add_child(b)
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

func _select(i: int) -> void:
	_sport = _sports[i]
	_cards[i].button_pressed = true
	_update_info()
	if is_node_ready() and _lens_opt != null and _mode_opt != null:
		_save_prefs()


func _update_info() -> void:
	if _sport == null:
		return
	_sport_info.text = "%s  -  %s" % [_sport.display_name, _sport.description]
	var duo := _two_players()
	_mode_info.text = "Manette 1 = gimbal (cadreur), manette 2 = drone en mode acro (pilote). Le sujet reste scripté. Réglage : Paramètres > Configuration manette." if duo else "Un seul joueur : le drone suit le sujet, tu gères la gimbal."
	_movement_opt.disabled = duo
	_level_opt.disabled = duo
	_train_button.text = "Lancer la session à 2 joueurs (Entrée)" if duo else "Lancer la session d'entraînement (Entrée)"
	var m := _selected_movement()
	_movement_info.text = str(MOVEMENT_LABELS[m][1]) if m != "" else "Un mouvement tiré au hasard, d'autant plus difficile que le niveau est élevé."
	var lv := _level_opt.selected  # 0 auto, 1 random, 2..6 = level 1..5
	if lv == 0:
		_level_info.text = "Niveau %d (celui du sport). %s" % [_sport.base_difficulty, DroneDifficulty.describe(_sport.base_difficulty)]
	elif lv == 1:
		_level_info.text = "Un niveau tiré au hasard à chaque session.\n" + DIFFICULTY_HELP
	else:
		_level_info.text = DroneDifficulty.describe(lv - 1)


func _two_players() -> bool:
	return _mode_opt != null and _mode_opt.selected == 1


func _selected_movement() -> String:
	return "" if _movement_opt.selected <= 0 else str(ScenarioMatrix.MOVEMENTS[_movement_opt.selected - 1].id)


# --- Launch --------------------------------------------------------------------------------------

func _start_training() -> void:
	if _sport == null:
		return
	DuoSession.dual_screen = _screens_opt.selected == 1
	var lv := _level_opt.selected  # 0 auto, 1 random, 2..6 = level 1..5
	var level := -1 if lv == 0 else (0 if lv == 1 else lv - 1)
	ScenarioMatrix.launch(get_tree(), ScenarioMatrix.generate(_sport.id, _selected_movement(), level, null, {}, SessionConfig.LENSES[_lens_opt.selected], _two_players()))


func _start_sandbox() -> void:
	DuoSession.dual_screen = _screens_opt.selected == 1
	Sandbox.lens_mm = SessionConfig.LENSES[_lens_opt.selected]
	get_tree().change_scene_to_file("res://scenarios/sandbox/sandbox.tscn")


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
		KEY_ENTER, KEY_KP_ENTER: _start_training()
		KEY_R: _start_random()
		KEY_B: _start_sandbox()
		KEY_ESCAPE: get_tree().quit()

extends Control
## Main menu, in pages (like the menus of the FPV simulators):
##  1. Home: PLAY (big tile), then random session, history and replays, settings; quit.
##  2. Play: training (a scored session on one of the sports) or sandbox (free flight in the countryside), and the
##     terrain, as a grid of picture cards.
##  3. Session: only the options of what was chosen (players, screens, drone movement, level, lens), and LAUNCH.
## Esc (or Back) goes back one page. After a session the menu opens on the page of that session, ready to play again.

const MOVEMENT_LABELS := {
	"pursuit": ["Poursuite arrière", "Le drone suit le sujet par l'arrière."],
	"lateral": ["Suivi latéral", "Le drone vole à côté du sujet, en avançant et reculant."],
	"frontal": ["Face au sujet", "Le drone recule devant le sujet, en le filmant de face."],
	"orbit": ["Orbite", "Le drone tourne autour du sujet pendant qu'il avance."],
	"reveal": ["Dévoilement", "Le sujet est caché derrière un obstacle, puis découvert quand le drone le dépasse."],
	"flyby": ["Survol rapide", "Le drone croise le sujet à grande vitesse, tout près."],
	"approach_orbit": ["Entrée + orbite", "Le drone s'éloigne loin et haut (le sujet devient minuscule), revient à toute vitesse et s'enroule autour du sujet dans une orbite rapide qui monte et descend, puis repart chercher une autre entrée."],
	"dive": ["Plongeon", "Le drone monte haut devant le sujet, plonge sur lui, le frôle à basse altitude et remonte derrière lui, en alternant les côtés."],
	"choreo": ["Chorégraphie expert", "Enchaînement de figures : entrées de loin en orbite, plongeons, croisements face à face et spirales montantes, jamais deux fois la même à la suite."],
}

const LEVEL_LABELS := ["Auto (difficulté du sport)", "Aléatoire (niveaux 1 à 5)", "Niveau 1 - très facile", "Niveau 2 - facile",
		"Niveau 3 - moyen", "Niveau 4 - difficile", "Niveau 5 - très difficile", "Niveau 6 - EXPERT"]
## What makes a session hard (see DroneDifficulty): the movement, the axes (pan / tilt) and the proximity.
const DIFFICULTY_HELP := "La difficulté vient du mouvement du drone, des axes à gérer (pan seul / tilt seul, puis les deux) et de la distance au sujet. Le drone vole toujours de façon fluide."
const LENS_HELP := {24: "  (large, plus facile)", 35: "", 50: "  (le sujet est plus gros, plus dur à garder)", 85: "  (très serré : chaque geste compte)"}
const SANDBOX_TEXT := "La campagne de la Départementale en libre, sans limite de temps ni score : routes, village, fermes, voitures, camions, cyclistes, piétons, un avion et un hélicoptère.\n\nSans manette, ou avec seulement celle de la gimbal, le drone décolle tout seul et vole de façon aléatoire mais fluide dans toute la carte : tu règles ta gimbal et tu filmes ce qui passe. Avec une 2e manette (pilote) : vol acro. En jeu, la touche M change le mode du drone (auto, clavier, acro)."
const VERSION := "Version 1.6"
const THUMBS := "res://ui/thumbs/%s.png"

## Page to open the next time the menu is shown ("home", "play", "setup"), and whether "setup" is the sandbox.
static var return_page := "home"
static var return_sandbox := false

var _sports: Array[SubjectDefinition] = []
var _sport: SubjectDefinition
var _sandbox := false   ## the play / setup pages are for the sandbox (else a training session)

var _home: Control
var _play: Control
var _setup: Control
var _page: Control
var _play_tile: MenuTile
var _train_tab: Button
var _sandbox_tab: Button
var _grid: GridContainer
var _play_text: Label
var _cards: Array[MenuTile] = []

# setup page
var _setup_picture: MenuTile
var _setup_title: Label
var _setup_text: Label
var _setup_heading: Label
var _rows := {}   ## option name -> the row (shown / hidden by mode)
var _mode_opt: OptionButton
var _mode_info: Label
var _screens_opt: OptionButton
var _movement_opt: OptionButton
var _movement_info: Label
var _level_opt: OptionButton
var _level_info: Label
var _lens_opt: OptionButton
var _launch: Button


func _ready() -> void:
	SessionScorer.reset()
	SessionScorer.next_label = ""
	ScenarioMatrix.current = null
	SubjectCatalogue.reload()
	_sports = SubjectCatalogue.menu_sports()
	_build_ui()
	var prefs := _load_prefs()
	_sport = _sports[0] if not _sports.is_empty() else null
	for s in _sports:
		if s.id == str(prefs.get("sport", "")):
			_sport = s
	_apply_prefs(prefs)
	for o in [_mode_opt, _movement_opt, _level_opt, _lens_opt, _screens_opt]:
		o.item_selected.connect(func(_i): _save_prefs())
	_sandbox = return_sandbox
	match return_page:
		"setup":
			_open_setup(_sandbox)
		"play":
			_open_play(_sandbox)
		_:
			_show(_home)
	return_page = "home"


# --- Saved choices ---------------------------------------------------------------------------------

const PREFS_PATH := "user://menu_prefs.json"


func _load_prefs() -> Dictionary:
	if not FileAccess.file_exists(PREFS_PATH):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(PREFS_PATH))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func _apply_prefs(prefs: Dictionary) -> void:
	MotionBlur.level = clampi(int(prefs.get("blur", MotionBlur.level)), 0, MotionBlur.LABELS.size() - 1)
	FrameGuide.blackout = bool(prefs.get("blackout", FrameGuide.blackout))
	GraphicsSettings.quality = clampi(int(prefs.get("quality", GraphicsSettings.quality)), 0, GraphicsSettings.LABELS.size() - 1)
	for pair in [[_mode_opt, "mode"], [_movement_opt, "movement"], [_level_opt, "level"], [_lens_opt, "lens"], [_screens_opt, "screens"]]:
		var o: OptionButton = pair[0]
		var i := int(prefs.get(pair[1], 0))
		if i >= 0 and i < o.item_count:
			o.select(i)
	_update_info()


func _save_prefs() -> void:
	if _sport == null:
		return
	# merged into the file: the other keys (gimbal profile, blackout...) are written by other screens
	var prefs := _load_prefs()
	prefs.merge({"sport": _sport.id, "mode": _mode_opt.selected, "movement": _movement_opt.selected,
			"level": _level_opt.selected, "lens": _lens_opt.selected, "screens": _screens_opt.selected, "blur": MotionBlur.level,
			"quality": GraphicsSettings.quality, "blackout": FrameGuide.blackout}, true)
	var f := FileAccess.open(PREFS_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(prefs, "\t"))


# --- UI: common ---------------------------------------------------------------------------------

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.025, 0.035, 0.07)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var backdrop := TextureRect.new()
	backdrop.texture = _thumb("ski_descente")
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.modulate = Color(0.55, 0.62, 0.9, 0.1)
	add_child(backdrop)
	_home = _build_home()
	_play = _build_play()
	_setup = _build_setup()
	for p in [_home, _play, _setup]:
		p.visible = false
		add_child(p)


func _show(page: Control) -> void:
	for p in [_home, _play, _setup]:
		p.visible = p == page
	_page = page
	match page:
		_home:
			_focus_later(_play_tile)
		_play:
			if not _cards.is_empty():
				var focus: MenuTile = _cards[0]
				for c in _cards:
					if c.selected:
						focus = c
				_focus_later(focus)
		_setup:
			_focus_later(_launch)


## Focus for the keyboard / controller, at the end of the frame (when the page is laid out), if still in the menu.
func _focus_later(c: Control) -> void:
	(func(): if is_instance_valid(c) and c.is_inside_tree() and c.is_visible_in_tree(): c.grab_focus()).call_deferred()


func _thumb(id: String) -> Texture2D:
	var path := THUMBS % id
	return load(path) if ResourceLoader.exists(path) else null


func _label(text: String, font_size: int, alpha := 1.0, bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	if bold:
		l.add_theme_font_override("font", MenuTile.bold_italic())
	l.modulate = Color(1, 1, 1, alpha)
	return l


func _text_button(text: String, font_size: int, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	b.add_theme_color_override("font_hover_color", MenuTile.AMBER)
	b.add_theme_color_override("font_focus_color", MenuTile.AMBER)
	b.pressed.connect(action)
	return b


## A full-window page with margins.
func _page_root() -> MarginContainer:
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		m.add_theme_constant_override("margin_" + side, 70)
	m.add_theme_constant_override("margin_top", 40)
	m.add_theme_constant_override("margin_bottom", 30)
	return m


## Column on the left of the play / setup pages: big title, subtitle, free space, then Back and Quit.
func _side_column(title: String, subtitle: String, back: Callable) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.custom_minimum_size.x = 360
	v.add_theme_constant_override("separation", 6)
	v.add_child(_label(title, 60, 1.0, true))
	v.add_child(_label(subtitle, 26, 0.9, true))
	return v


func _side_bottom(v: VBoxContainer, back: Callable) -> void:
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(spacer)
	v.add_child(_text_button("Retour  (Échap)", 26, back))
	v.add_child(_text_button("Quitter le jeu", 26, func(): get_tree().quit()))


# --- Page 1: home -------------------------------------------------------------------------------

func _build_home() -> Control:
	var root := _page_root()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 22)
	root.add_child(v)
	var head := VBoxContainer.new()
	head.add_theme_constant_override("separation", 0)
	v.add_child(head)
	var t := _label("FPV DUALOP", 72, 1.0, true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(t)
	var st := _label("SIMULATEUR DE CADRAGE GIMBAL  ·  DRONE FPV", 18, 1.0)
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	st.add_theme_color_override("font_color", Color(0.35, 1.0, 0.45))
	head.add_child(st)

	var tiles := VBoxContainer.new()
	tiles.add_theme_constant_override("separation", 22)
	tiles.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tiles.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(tiles)
	var row1 := HBoxContainer.new()
	row1.alignment = BoxContainer.ALIGNMENT_CENTER
	tiles.add_child(row1)
	_play_tile = _tile("Jouer", "Entraînement noté sur 6 sports, ou bac à sable en vol libre", Vector2(1180, 380), 52)
	_play_tile.picture = _thumb("ski_descente")
	_play_tile.icon_kind = ""
	_play_tile.pressed.connect(func(): _open_play(false))
	row1.add_child(_play_tile)
	var row2 := HBoxContainer.new()
	row2.alignment = BoxContainer.ALIGNMENT_CENTER
	row2.add_theme_constant_override("separation", 22)
	tiles.add_child(row2)
	var small := [
		["Session aléatoire", "Sport, mouvement et niveau au hasard", "dice", _start_random],
		["Historique et replays", "Tes scores, revoir tes sessions", "history",
			func(): get_tree().change_scene_to_file("res://scenes/history.tscn")],
		["Paramètres", "Manettes, graphismes, flou", "gear",
			func(): get_tree().change_scene_to_file("res://scenes/settings.tscn")],
	]
	for s in small:
		var tile := _tile(s[0], s[1], Vector2(378, 220), 26)
		tile.icon_kind = s[2]
		tile.pressed.connect(s[3])
		row2.add_child(tile)

	var bottom := HBoxContainer.new()
	v.add_child(bottom)
	var quit := _text_button("Quitter le jeu", 26, func(): get_tree().quit())
	bottom.add_child(quit)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(spacer)
	var ver := _label(VERSION, 14, 0.5)
	ver.size_flags_vertical = Control.SIZE_SHRINK_END
	bottom.add_child(ver)
	return root


func _tile(title: String, subtitle: String, min_size: Vector2, title_size: int) -> MenuTile:
	var t := MenuTile.new()
	t.title = title
	t.subtitle = subtitle
	t.custom_minimum_size = min_size
	t.title_size = title_size
	return t


# --- Page 2: play (training or sandbox, terrain) -------------------------------------------------

func _build_play() -> Control:
	var root := _page_root()
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 40)
	root.add_child(h)
	var side := _side_column("Jouer", "Choisis ton terrain", Callable())
	h.add_child(side)
	_play_text = _label("", 17, 0.75)
	_play_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_play_text.custom_minimum_size = Vector2(340, 0)
	side.add_child(Control.new())
	side.add_child(_play_text)
	_side_bottom(side, func(): _show(_home))

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 22)
	h.add_child(right)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 0)
	right.add_child(tabs)
	var group := ButtonGroup.new()
	_train_tab = _tab("Entraînement", group, true)
	_train_tab.pressed.connect(func(): _fill_play(false))
	tabs.add_child(_train_tab)
	_sandbox_tab = _tab("Bac à sable", group, false)
	_sandbox_tab.pressed.connect(func(): _fill_play(true))
	tabs.add_child(_sandbox_tab)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", 22)
	_grid.add_theme_constant_override("v_separation", 22)
	scroll.add_child(_grid)
	return root


## A tab of the "Training / Sandbox" switch: a pill, filled when selected.
func _tab(text: String, group: ButtonGroup, left: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_group = group
	b.custom_minimum_size = Vector2(260, 52)
	b.add_theme_font_size_override("font_size", 22)
	b.focus_mode = Control.FOCUS_ALL
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.5, 0.52, 0.58, 0.55) if state in ["pressed", "hover_pressed"] else Color(0.08, 0.1, 0.16, 0.85)
		if state == "hover":
			sb.bg_color = Color(0.16, 0.19, 0.27, 0.9)
		if state == "focus":
			sb.bg_color = Color(0, 0, 0, 0)
			sb.draw_center = false
		sb.border_color = MenuTile.AMBER if state == "focus" else Color(0.75, 0.78, 0.85)
		sb.set_border_width_all(2)
		sb.corner_radius_top_left = 26 if left else 0
		sb.corner_radius_bottom_left = 26 if left else 0
		sb.corner_radius_top_right = 0 if left else 26
		sb.corner_radius_bottom_right = 0 if left else 26
		b.add_theme_stylebox_override(state, sb)
	return b


func _open_play(sandbox: bool) -> void:
	_fill_play(sandbox)
	_show(_play)


## Fills the grid: one card per sport (training), or the sandbox map.
func _fill_play(sandbox: bool) -> void:
	_sandbox = sandbox
	_train_tab.set_pressed_no_signal(not sandbox)
	_sandbox_tab.set_pressed_no_signal(sandbox)
	for c in _grid.get_children():
		c.queue_free()
	_cards.clear()
	if sandbox:
		_play_text.text = SANDBOX_TEXT
		var card := _tile("Campagne", "Village, routes, fermes, trafic, avion, hélicoptère", Vector2(420, 250), 26)
		card.picture = _thumb("sandbox")
		card.skew = 0.0
		card.pressed.connect(func(): _open_setup(true))
		_grid.add_child(card)
		_cards.append(card)
	else:
		_play_text.text = "Un sport, un parcours généré à chaque session : le drone vole tout seul (ou piloté par un 2e joueur) et tu gardes le sujet dans le cadre avec la gimbal. À la fin, une note sur 100.\n\nTouches 1 à %d : choisir un sport." % _sports.size()
		for i in _sports.size():
			var s := _sports[i]
			var card := _tile(s.display_name, "", Vector2(330, 210), 24)
			card.picture = _thumb(s.id)
			card.skew = 0.0
			card.badge = _dots(s.base_difficulty)
			card.selected = _sport == s
			card.pressed.connect(_choose_sport.bind(i))
			_grid.add_child(card)
			_cards.append(card)
	if _page == _play and not _cards.is_empty():
		_focus_later(_cards[0])


func _choose_sport(i: int) -> void:
	_sport = _sports[i]
	_save_prefs()
	_open_setup(false)


# --- Page 3: session setup -----------------------------------------------------------------------

func _build_setup() -> Control:
	var root := _page_root()
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 50)
	root.add_child(h)
	var side := _side_column("Session", "", Callable())
	_setup_heading = side.get_child(1) as Label
	h.add_child(side)
	_setup_picture = MenuTile.new()
	_setup_picture.custom_minimum_size = Vector2(360, 210)
	_setup_picture.skew = 0.0
	_setup_picture.focus_mode = Control.FOCUS_NONE
	_setup_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	side.add_child(Control.new())
	side.add_child(_setup_picture)
	_setup_text = _label("", 16, 0.75)
	_setup_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_setup_text.custom_minimum_size = Vector2(360, 0)
	side.add_child(_setup_text)
	_side_bottom(side, func(): _open_play(_sandbox))

	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.06, 0.11, 0.85)
	sb.border_color = MenuTile.BLUE
	sb.set_border_width_all(2)
	sb.set_content_margin_all(28)
	panel.add_theme_stylebox_override("panel", sb)
	h.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	_setup_title = _label("", 34, 1.0, true)
	v.add_child(_setup_title)

	_mode_opt = _option_row(v, "mode", "Mode de jeu")
	_mode_opt.add_item("1 joueur  -  le drone vole tout seul")
	_mode_opt.add_item("2 joueurs  -  un pilote FPV + un cadreur")
	_mode_opt.item_selected.connect(func(_i): _update_info())
	_mode_info = _info(v, "mode_info")
	_screens_opt = _option_row(v, "screens", "Écran du pilote")
	_screens_opt.add_item("Un écran  -  vue pilote en incrustation")
	var n_screens := DisplayServer.get_screen_count()
	_screens_opt.add_item("Deux écrans  -  vue pilote sur le 2e écran" + ("" if n_screens > 1 else "  (aucun 2e écran détecté)"))
	_movement_opt = _option_row(v, "movement", "Mouvement du drone")
	_movement_opt.add_item("Au hasard (selon le niveau)")
	for m in ScenarioMatrix.MOVEMENTS:
		_movement_opt.add_item("%s   %s" % [MOVEMENT_LABELS[m.id][0], _dots(DroneDifficulty.movement_tier(m.id))])
	_movement_opt.item_selected.connect(func(_i): _update_info())
	_movement_info = _info(v, "movement_info")
	_level_opt = _option_row(v, "level", "Niveau")
	for t in LEVEL_LABELS:
		_level_opt.add_item(t)
	_level_opt.item_selected.connect(func(_i): _update_info())
	_level_info = _info(v, "level_info")
	_lens_opt = _option_row(v, "lens", "Optique")
	for mm in SessionConfig.LENSES:
		_lens_opt.add_item("%d mm%s" % [mm, LENS_HELP[mm]])
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(spacer)
	_launch = Button.new()
	_launch.custom_minimum_size = Vector2(0, 70)
	_launch.add_theme_font_override("font", MenuTile.bold_italic())
	_launch.add_theme_font_size_override("font_size", 30)
	for state in ["normal", "hover", "pressed", "focus"]:
		var bsb := StyleBoxFlat.new()
		bsb.bg_color = MenuTile.AMBER if state != "normal" else MenuTile.AMBER.darkened(0.15)
		bsb.border_color = Color(1, 1, 1)
		bsb.set_border_width_all(3 if state == "focus" else 0)
		bsb.skew = Vector2(0.15, 0.0)
		bsb.set_corner_radius_all(4)
		_launch.add_theme_stylebox_override(state, bsb)
	_launch.add_theme_color_override("font_color", Color(0.05, 0.05, 0.08))
	_launch.add_theme_color_override("font_hover_color", Color(0.05, 0.05, 0.08))
	_launch.add_theme_color_override("font_focus_color", Color(0.05, 0.05, 0.08))
	_launch.add_theme_color_override("font_pressed_color", Color(0.05, 0.05, 0.08))
	_launch.pressed.connect(_launch_session)
	v.add_child(_launch)
	return root


func _option_row(parent: Control, key: String, label: String) -> OptionButton:
	var row := HBoxContainer.new()
	parent.add_child(row)
	_rows[key] = row
	var l := _label(label, 19)
	l.custom_minimum_size.x = 220
	row.add_child(l)
	var o := OptionButton.new()
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	o.custom_minimum_size.y = 40
	o.add_theme_font_size_override("font_size", 17)
	row.add_child(o)
	return o


func _info(parent: Control, key: String) -> Label:
	var l := _label("", 15, 0.65)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)
	_rows[key] = l
	return l


func _open_setup(sandbox: bool) -> void:
	_sandbox = sandbox
	if sandbox:
		_setup_heading.text = "Bac à sable"
		_setup_title.text = "Bac à sable  -  vol libre"
		_setup_picture.picture = _thumb("sandbox")
		_setup_picture.title = "Campagne"
		_setup_picture.badge = ""
		_setup_text.text = "Pas de chrono, pas de score. Retour arrière en jeu : le drone revient sur la place du village."
	elif _sport != null:
		_setup_heading.text = "Entraînement"
		_setup_title.text = "Session d'entraînement"
		_setup_picture.picture = _thumb(_sport.id)
		_setup_picture.title = _sport.display_name
		_setup_picture.badge = _dots(_sport.base_difficulty)
		_setup_text.text = _sport.description
	_setup_picture.queue_redraw()
	_update_info()
	_show(_setup)


func _update_info() -> void:
	if _mode_opt == null:
		return
	var duo := _two_players()
	var training := not _sandbox
	_rows.mode.visible = training
	_rows.mode_info.visible = training
	_rows.movement.visible = training and not duo
	_rows.movement_info.visible = training and not duo
	_rows.level.visible = training and not duo
	_rows.level_info.visible = training and not duo
	# the pilot's screen only matters when someone flies the drone
	_rows.screens.visible = duo or _sandbox
	if _sandbox:
		_launch.text = "LANCER LE BAC À SABLE"
		return
	_mode_info.text = "Manette 1 = gimbal (cadreur), manette 2 = drone en mode acro (pilote). Le sujet reste scripté. Réglage : Paramètres > Configuration manette." if duo else "Un seul joueur : le drone suit le sujet, tu gères la gimbal."
	_launch.text = "LANCER LA SESSION À 2 JOUEURS" if duo else "LANCER LA SESSION"
	var m := _selected_movement()
	_movement_info.text = str(MOVEMENT_LABELS[m][1]) if m != "" else "Un mouvement tiré au hasard, d'autant plus difficile que le niveau est élevé (au niveau Expert : orbite, survol ou une figure expert)."
	var lv := _level_opt.selected  # 0 auto, 1 random, 2..7 = level 1..6
	if lv == 0 and _sport != null:
		_level_info.text = "Niveau %d (celui du sport). %s" % [_sport.base_difficulty, DroneDifficulty.describe(_sport.base_difficulty)]
	elif lv == 1:
		_level_info.text = "Un niveau tiré au hasard à chaque session. " + DIFFICULTY_HELP
	else:
		_level_info.text = DroneDifficulty.describe(lv - 1)


static func _dots(n: int) -> String:
	if n > 5:
		return "●●●●●  EXPERT"
	return "●".repeat(n) + "○".repeat(5 - n)


func _two_players() -> bool:
	return _mode_opt != null and _mode_opt.selected == 1


func _selected_movement() -> String:
	return "" if _movement_opt.selected <= 0 else str(ScenarioMatrix.MOVEMENTS[_movement_opt.selected - 1].id)


# --- Launch --------------------------------------------------------------------------------------

func _launch_session() -> void:
	if _sandbox:
		_start_sandbox()
	else:
		_start_training()


func _start_training() -> void:
	if _sport == null:
		return
	_save_prefs()
	return_page = "setup"
	return_sandbox = false
	DuoSession.dual_screen = _screens_opt.selected == 1
	var lv := _level_opt.selected  # 0 auto, 1 random, 2..7 = level 1..6
	var level := -1 if lv == 0 else (0 if lv == 1 else lv - 1)
	ScenarioMatrix.launch(get_tree(), ScenarioMatrix.generate(_sport.id, _selected_movement(), level, null, {}, SessionConfig.LENSES[_lens_opt.selected], _two_players()))


func _start_sandbox() -> void:
	_save_prefs()
	return_page = "setup"
	return_sandbox = true
	DuoSession.dual_screen = _screens_opt.selected == 1
	Sandbox.lens_mm = SessionConfig.LENSES[_lens_opt.selected]
	get_tree().change_scene_to_file("res://scenarios/sandbox/sandbox.tscn")


func _start_random() -> void:
	return_page = "home"
	ScenarioMatrix.launch(get_tree(), ScenarioMatrix.generate())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		match _page:
			_setup:
				_open_play(_sandbox)
			_play:
				_show(_home)
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match _page:
		_home:
			match event.physical_keycode:
				KEY_R: _start_random()
				KEY_ENTER, KEY_KP_ENTER: _open_play(false)
		_play:
			var n: int = event.physical_keycode - KEY_1
			if not _sandbox and n >= 0 and n < _sports.size():
				_choose_sport(n)
		_setup:
			if event.physical_keycode in [KEY_ENTER, KEY_KP_ENTER]:
				_launch_session()

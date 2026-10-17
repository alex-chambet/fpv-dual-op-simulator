extends Control
## Main menu, in pages (like the menus of the FPV simulators):
##  1. Home: PLAY (big tile), then random session, history and replays, settings; quit.
##  2. Play: one of three modes - training (a scored session on one of the sports), movement drills
##     (one drone figure, repeated, to learn it) or sandbox (free flight) - and the terrain or the
##     figure, as a grid of picture cards.
##  3. Session: only the options of what was chosen (players, screens, drone movement, level, lens), and LAUNCH.
## Esc (or Back) goes back one page. After a session the menu opens on the page of that session, ready to play again.

## The "À travailler" card on the home page (PracticeAdvisor): off for now, to be looked at again
## later. Everything behind it still works - the three steps per sport it shares its data with are
## on the sport cards either way - so this is the only line to change to bring it back.
const SHOW_ADVICE := false

## The three modes of the play / setup pages.
const TRAINING := "training"
const DRILLS := "drills"
const SANDBOX := "sandbox"

## The movement drills ("Mouvements"): name, subtitle of the card, and what the operator has to do.
const DRILL_LABELS := {
	"orbit": ["Orbite", "Tourner autour du sujet",
		"Le drone décrit un cercle autour du sujet, à distance constante. C'est la figure de base : un pan régulier, sans à-coup, pendant tout le tour. Garde le sujet au même endroit du cadre et accompagne-le au lieu de le rattraper."],
	"spiral_in": ["Spirale vers l'intérieur", "Une orbite qui se resserre",
		"Le même cercle, mais le rayon diminue : le sujet grossit et le pan s'accélère à mesure que le drone se rapproche. Il faut anticiper cette accélération, sinon on se fait déborder au plus près. Le drone ressort ensuite pour recommencer."],
	"reveal_up": ["Reveal tilt bas vers haut", "Du sol vers l'horizon",
		"Le drone part haut et tout près, caméra plongeant à pic sur le sol, puis descend en s'éloignant jusqu'à passer devant le sujet : le tilt remonte du sol jusqu'à l'horizon pendant que le sujet se dévoile. Exercice de tilt presque pur, le pan ne bouge que peu."],
	"pass_behind": ["Flyby par derrière", "Rattraper, passer derrière, ressortir",
		"Le drone arrive de loin, décalé en arrière et sur un côté, rattrape le sujet en passant derrière lui et ressort de l'autre côté pour le suivre latéralement. Le pan s'inverse au moment du passage : c'est là qu'il faut être propre. La figure repart ensuite dans l'autre sens."],
	"vertical_pass": ["Vertical tilt", "Passage juste au-dessus",
		"Le drone passe au-dessus du sujet sur une trajectoire presque perpendiculaire à sa course : il entre un peu par l'arrière et ressort un peu en avant. Au plus près il faut piquer fort et panoter en même temps — c'est la seule figure où les deux axes travaillent à fond ensemble."],
}

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
const SANDBOX_TEXT := "Un terrain en libre, sans limite de temps ni score.\n\nSans manette, ou avec seulement celle de la gimbal, le drone décolle tout seul et vole de façon aléatoire mais fluide dans toute la carte : tu règles ta gimbal et tu filmes ce qui passe. Avec une 2e manette (pilote) : vol acro. En jeu, la touche M change le mode du drone (auto, clavier, acro)."
## The sandbox maps (Sandbox.map).
const SANDBOX_MAPS := [
	{"id": "campagne", "name": "Campagne", "thumb": "sandbox",
		"subtitle": "Village, routes, fermes, trafic, avion, hélicoptère",
		"text": "La campagne de la Départementale : routes, village, fermes, voitures, camions, cyclistes, piétons, un avion et un hélicoptère. Retour arrière en jeu : le drone revient sur la place du village."},
	{"id": "circuit", "name": "Circuit", "thumb": "sandbox_circuit",
		"subtitle": "Nürburgring : 9 voitures de course, 6 classes",
		"text": "Le Nürburgring (Grand-Prix-Strecke) à l'échelle 1/2, avec neuf voitures de six classes qui tournent à leur propre rythme : deux GT3, deux GT4, deux tourismes, une historique, une GT de route et la safety car. Elles se rattrapent et se doublent toutes seules. Retour arrière en jeu : le drone revient sur la ligne de départ."},
]
const VERSION := "Version 1.6"
const THUMBS := "res://ui/thumbs/%s.png"

## Page to open the next time the menu is shown ("home", "play", "setup"), and in which mode.
static var return_page := "home"
static var return_mode := TRAINING

var _sports: Array[SubjectDefinition] = []
var _sport: SubjectDefinition
var _profile_opt: OptionButton
var _mode := TRAINING    ## which of the three modes the play / setup pages are showing
var _drill := "orbit"    ## the movement of the drill chosen on the "Mouvements" tab

var _home: Control
var _play: Control
var _setup: Control
var _page: Control
var _backdrop: ColorRect
var _play_tile: MenuTile
var _advice_tile: MenuTile
var _advice_line: Label
var _advice := {}   ## what PracticeAdvisor suggests playing next
var _tabs := {}   ## mode -> the pill of the play page
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
var _ambience_opt: OptionButton
var _speed_opt: OptionButton
var _speed_info: Label
var _preview: MovementPreview
var _launch: Button


func _ready() -> void:
	SessionScorer.reset()
	SessionScorer.next_label = ""
	ScenarioMatrix.current = null
	SubjectCatalogue.reload()
	_sports = SubjectCatalogue.menu_sports()
	# easiest first (the number keys follow this order); same difficulty: alphabetical
	_sports.sort_custom(func(a: SubjectDefinition, b: SubjectDefinition):
		if a.base_difficulty != b.base_difficulty:
			return a.base_difficulty < b.base_difficulty
		return a.display_name.naturalnocasecmp_to(b.display_name) < 0)
	_build_ui()
	var prefs := _load_prefs()
	_sport = _sports[0] if not _sports.is_empty() else null
	for s in _sports:
		if s.id == str(prefs.get("sport", "")):
			_sport = s
	_apply_prefs(prefs)
	_refresh_advice()
	for o in [_mode_opt, _movement_opt, _level_opt, _lens_opt, _screens_opt, _ambience_opt]:
		o.item_selected.connect(func(_i): _save_prefs())
	_mode = return_mode
	match return_page:
		"setup":
			_open_setup(_mode)
		"play":
			_open_play(_mode)
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
	FrameGuide.show_thirds = bool(prefs.get("show_thirds", FrameGuide.show_thirds))
	DronePip.enabled = bool(prefs.get("drone_pip", DronePip.enabled))
	GraphicsSettings.load_prefs(prefs)
	GraphicsSettings.apply_display()
	var saved_map := str(prefs.get("sandbox_map", Sandbox.map))
	for m in SANDBOX_MAPS:
		if str(m.id) == saved_map:
			Sandbox.map = saved_map
	var saved_drill := str(prefs.get("drill", _drill))
	if saved_drill in ScenarioMatrix.DRILL_MOVEMENTS:
		_drill = saved_drill
	for pair in [[_mode_opt, "mode"], [_movement_opt, "movement"], [_level_opt, "level"], [_lens_opt, "lens"], [_screens_opt, "screens"], [_ambience_opt, "ambience"], [_speed_opt, "drill_speed"]]:
		var o: OptionButton = pair[0]
		var i := int(prefs.get(pair[1], 0))
		if i >= 0 and i < o.item_count:
			o.select(i)
	Ambience.choice = str(Ambience.MENU[_ambience_opt.selected])
	_update_info()


func _save_prefs() -> void:
	Ambience.choice = str(Ambience.MENU[_ambience_opt.selected])
	if _sport == null:
		return
	# merged into the file: the other keys (gimbal profile, thirds grid...) are written by other screens
	var prefs := _load_prefs()
	prefs.merge({"sport": _sport.id, "mode": _mode_opt.selected, "movement": _movement_opt.selected,
			"level": _level_opt.selected, "lens": _lens_opt.selected, "screens": _screens_opt.selected, "ambience": _ambience_opt.selected, "blur": MotionBlur.level,
			"quality": GraphicsSettings.quality, "sandbox_map": Sandbox.map,
			"drill": _drill, "drill_speed": _speed_opt.selected}, true)
	var f := FileAccess.open(PREFS_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(prefs, "\t"))


# --- UI: common ---------------------------------------------------------------------------------

func _build_ui() -> void:
	# the synthwave night (animated), a little darker behind the pages with options
	_backdrop = Neon.backdrop()
	add_child(_backdrop)
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
	_backdrop.material.set_shader_parameter("dim", 0.0 if page == _home else 0.5)
	match page:
		_home:
			# no tile is highlighted when the page opens (JOUER would stay pink while another tile is clicked); the first arrow key of the keyboard / controller gives the focus to JOUER (see _unhandled_input)
			var owner_home := get_viewport().gui_get_focus_owner()
			if owner_home != null:
				owner_home.release_focus()
		_play:
			# no card is highlighted when the page opens; the keyboard / controller gives the focus to the first one
			# (see _unhandled_input)
			var owner := get_viewport().gui_get_focus_owner()
			if owner != null:
				owner.release_focus()
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
		Neon.title(l, font_size, font_size >= 50)
	elif alpha < 1.0:
		l.add_theme_color_override("font_color", Color(Neon.TEXT_DIM, alpha))
	return l


func _text_button(text: String, font_size: int, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_font_override("font", Neon.title_font())
	b.add_theme_color_override("font_color", Color(Neon.TEXT, 0.85))
	b.add_theme_color_override("font_hover_color", Neon.PINK)
	b.add_theme_color_override("font_focus_color", Neon.CYAN)
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
	v.add_child(Neon.caps(_label(subtitle, 22), 22))
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
	Neon.caps(st, 18)
	head.add_child(st)

	var tiles := VBoxContainer.new()
	tiles.add_theme_constant_override("separation", 22)
	tiles.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tiles.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(tiles)
	var row1 := HBoxContainer.new()
	row1.alignment = BoxContainer.ALIGNMENT_CENTER
	tiles.add_child(row1)
	_play_tile = _tile("Jouer", "", Vector2(1180, 380), 52)
	_play_tile.picture = _thumb("ski_descente")
	_play_tile.icon_kind = ""
	_play_tile.pressed.connect(func(): _open_play(TRAINING))
	row1.add_child(_play_tile)
	var row2 := HBoxContainer.new()
	row2.alignment = BoxContainer.ALIGNMENT_CENTER
	row2.add_theme_constant_override("separation", 22)
	tiles.add_child(row2)
	# The "À travailler" card. With SHOW_ADVICE off, the home page is the one it always was and the
	# three tiles keep their full size; PracticeAdvisor and SportProgress carry on working, so
	# turning it back on is this one flag.
	if SHOW_ADVICE:
		_advice_tile = _tile("À travailler", "", Vector2(282, 200), 24)
		_advice_tile.icon_kind = ""   # it shows the picture of what it proposes
		_advice_tile.pressed.connect(_start_advice)
		row2.add_child(_advice_tile)
	var small := [
		["Session aléatoire", "Sport, mouvement et niveau au hasard", "dice", _start_random],
		["Historique et replays", "Tes scores, revoir tes sessions", "history",
			func(): get_tree().change_scene_to_file("res://scenes/history.tscn")],
		["Paramètres", "Réglage manette et graphismes", "gear",
			func(): get_tree().change_scene_to_file("res://scenes/settings.tscn")],
	]
	var small_size := Vector2(282, 200) if SHOW_ADVICE else Vector2(378, 220)
	for s in small:
		var tile := _tile(s[0], s[1], small_size, 26 if not SHOW_ADVICE else 24)
		tile.icon_kind = s[2]
		tile.pressed.connect(s[3])
		row2.add_child(tile)
	if SHOW_ADVICE:
		_advice_line = _label("", 15, 0.7)
		_advice_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tiles.add_child(_advice_line)

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
	var names := {TRAINING: "Entraînement", DRILLS: "Mouvements", SANDBOX: "Bac à sable"}
	var modes := [TRAINING, DRILLS, SANDBOX]
	for i in modes.size():
		var mode: String = modes[i]
		var b := _tab(str(names[mode]), group, -1 if i == 0 else (1 if i == modes.size() - 1 else 0))
		b.pressed.connect(func(): _fill_play(mode))
		tabs.add_child(b)
		_tabs[mode] = b
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


## A tab of the mode switch: a pill, filled when selected. `pos` is -1 for the leftmost tab, +1 for
## the rightmost, 0 for the ones in between (only their outer corners are rounded).
func _tab(text: String, group: ButtonGroup, pos: int) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_group = group
	b.custom_minimum_size = Vector2(230, 52)
	b.add_theme_font_size_override("font_size", 22)
	b.add_theme_font_override("font", Neon.title_font())
	b.focus_mode = Control.FOCUS_ALL
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.75, 0.1, 0.55, 0.8) if state in ["pressed", "hover_pressed"] else Color(0.08, 0.02, 0.16, 0.85)
		if state == "hover":
			sb.bg_color = Color(0.22, 0.05, 0.34, 0.9)
		if state == "focus":
			sb.bg_color = Color(0, 0, 0, 0)
			sb.draw_center = false
		sb.border_color = Neon.CYAN if state == "focus" else Neon.PINK
		sb.shadow_color = Color(sb.border_color, 0.4)
		sb.shadow_size = 10 if state in ["pressed", "hover_pressed", "focus"] else 0
		sb.set_border_width_all(2)
		sb.corner_radius_top_left = 26 if pos < 0 else 0
		sb.corner_radius_bottom_left = 26 if pos < 0 else 0
		sb.corner_radius_top_right = 26 if pos > 0 else 0
		sb.corner_radius_bottom_right = 26 if pos > 0 else 0
		b.add_theme_stylebox_override(state, sb)
	return b


func _open_play(mode: String) -> void:
	_fill_play(mode)
	_show(_play)


## Fills the grid: one card per sport (training), per figure (drills) or per sandbox map.
func _fill_play(mode: String) -> void:
	_mode = mode
	for k in _tabs:
		(_tabs[k] as Button).set_pressed_no_signal(k == mode)
	for c in _grid.get_children():
		c.queue_free()
	_cards.clear()
	match mode:
		SANDBOX:
			_play_text.text = SANDBOX_TEXT + "\n\nTouches 1 à %d : choisir un terrain." % SANDBOX_MAPS.size()
			for m in SANDBOX_MAPS:
				var card := _tile(str(m.name), str(m.subtitle), Vector2(420, 250), 26)
				card.picture = _thumb(str(m.thumb))
				card.skew = 0.0
				card.pressed.connect(_choose_sandbox_map.bind(str(m.id)))
				_grid.add_child(card)
				_cards.append(card)
		DRILLS:
			_play_text.text = "Une seule figure de drone, répétée du début à la fin, autour d'un sujet qui ne fait rien d'autre qu'avancer tout droit. Le but n'est pas la note mais le geste : commence sujet immobile, puis fais-le marcher, courir, filer.\n\nLes figures sont rangées de la plus simple à la plus difficile.\nTouches 1 à %d : choisir un mouvement." % ScenarioMatrix.DRILL_MOVEMENTS.size()
			for id in ScenarioMatrix.drills_by_difficulty():
				var lab: Array = DRILL_LABELS[id]
				var card := _tile(str(lab[0]), str(lab[1]), Vector2(330, 210), 22)
				card.picture = _thumb("drill_" + id)
				card.skew = 0.0
				card.badge = _dots(int(ScenarioMatrix.DRILL_TIER.get(id, 3)))
				card.pressed.connect(_choose_drill.bind(str(id)))
				_grid.add_child(card)
				_cards.append(card)
		_:
			_play_text.text = "Un sport, un parcours généré à chaque session : le drone vole tout seul (ou piloté par un 2e joueur) et tu gardes le sujet dans le cadre avec la gimbal. À la fin, une note sur 100.\n\nTouches 1 à %d : choisir un sport." % _sports.size()
			var best := SessionScorer.all_best()
			for i in _sports.size():
				var s := _sports[i]
				var card := _tile(s.display_name, "", Vector2(330, 210), 24)
				card.picture = _thumb(s.id)
				card.skew = 0.0
				card.badge = _dots(s.base_difficulty)
				# where the player is on this sport, so it reads as something to finish
				var pg := SportProgress.of(s.id, best)
				card.subtitle = "%s  %s" % [str(pg.dots), str(pg.name)]
				card.pressed.connect(_choose_sport.bind(i))
				_grid.add_child(card)
				_cards.append(card)


## Fills the "À travailler" tile from the sessions already played. Hidden when there is nothing to
## say (an empty catalogue); on a first run it proposes the gentlest thing, which is the point.
func _refresh_advice() -> void:
	if not SHOW_ADVICE or _advice_tile == null:
		return
	_advice = PracticeAdvisor.suggest()
	var has: bool = not _advice.is_empty()
	_advice_tile.visible = has
	_advice_line.visible = has
	if not has:
		return
	var label := _movement_label(str(_advice.movement), str(_advice.label))
	_advice_tile.subtitle = label
	_advice_tile.picture = _thumb("drill_" + str(_advice.movement) if _advice.kind == "drill" \
			else str(_advice.get("subject", "")))
	_advice_tile.queue_redraw()
	_advice_line.text = "%s   ·   %s   ·   %s" % [label, str(_advice.where), str(_advice.reason)]


## The French name of a movement (the ids carry English names, used in saved sessions).
func _movement_label(mv: String, fallback: String) -> String:
	if DRILL_LABELS.has(mv):
		return str(DRILL_LABELS[mv][0])
	if MOVEMENT_LABELS.has(mv):
		return str(MOVEMENT_LABELS[mv][0])
	return fallback


func _start_advice() -> void:
	if _advice.is_empty():
		return
	return_page = "home"
	return_mode = DRILLS if _advice.kind == "drill" else TRAINING
	DuoSession.dual_screen = false
	Ambience.choice = str(Ambience.MENU[_ambience_opt.selected])
	ScenarioMatrix.launch(get_tree(),
			PracticeAdvisor.config_for(_advice, SessionConfig.LENSES[_lens_opt.selected]))


func _choose_sport(i: int) -> void:
	_sport = _sports[i]
	_save_prefs()
	_open_setup(TRAINING)


func _choose_drill(id: String) -> void:
	_drill = id
	_save_prefs()
	_open_setup(DRILLS)


func _choose_sandbox_map(id: String) -> void:
	Sandbox.map = id
	_save_prefs()
	_open_setup(SANDBOX)


## The entry of SANDBOX_MAPS currently selected.
static func _sandbox_map() -> Dictionary:
	for m in SANDBOX_MAPS:
		if str(m.id) == Sandbox.map:
			return m
	return SANDBOX_MAPS[0]


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
	# The drills show the figure flying instead of a photo: the real planned flight, on a loop.
	_preview = MovementPreview.new()
	_preview.custom_minimum_size = Vector2(360, 230)
	_preview.visible = false
	side.add_child(_preview)
	_setup_text = _label("", 16, 0.75)
	_setup_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_setup_text.custom_minimum_size = Vector2(360, 0)
	side.add_child(_setup_text)
	_side_bottom(side, func(): _open_play(_mode))

	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := Neon.box(Neon.PANEL, Neon.PINK, 2, 18, 6, 28.0)
	sb.set_content_margin_all(28)
	sb.shadow_color = Color(Neon.PINK, 0.25)
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
	# the drills are not offered here: they are played from the "Mouvements" tab, on their own
	# subject and at a chosen subject speed
	for m in _training_movements():
		_movement_opt.add_item("%s   %s" % [MOVEMENT_LABELS[m][0], _dots(DroneDifficulty.movement_tier(m))])
	_movement_opt.item_selected.connect(func(_i): _update_info())
	_movement_info = _info(v, "movement_info")
	_speed_opt = _option_row(v, "speed", "Vitesse du sujet")
	for s in ScenarioMatrix.DRILL_STEPS:
		_speed_opt.add_item("%s  -  %s" % [str(s.name),
				"immobile" if float(s.speed) < 0.5 else "%.0f km/h" % (float(s.speed) * 3.6)])
	_speed_opt.item_selected.connect(func(_i): _update_info())
	_speed_info = _info(v, "speed_info")
	_level_opt = _option_row(v, "level", "Niveau")
	for t in LEVEL_LABELS:
		_level_opt.add_item(t)
	_level_opt.item_selected.connect(func(_i): _update_info())
	_level_info = _info(v, "level_info")
	_lens_opt = _option_row(v, "lens", "Optique")
	for mm in SessionConfig.LENSES:
		_lens_opt.add_item("%d mm%s" % [mm, LENS_HELP[mm]])
	_profile_opt = _option_row(v, "gimbal_profile", "Sensibilité gimbal")
	for t in ["Lent  -  mouvements doux", "Moyen", "Rapide  -  gimbal très réactive"]:
		_profile_opt.add_item(t)
	_profile_opt.select(GimbalRig.load_default_profile())
	_profile_opt.item_selected.connect(func(i): GimbalRig.save_default_profile(i))
	_ambience_opt = _option_row(v, "ambience", "Ambiance")
	for id in Ambience.MENU:
		_ambience_opt.add_item(str(Ambience.LABELS[id]) + ("  (sports de neige)" if id == "snowfall" else ""))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(spacer)
	_launch = Button.new()
	_launch.custom_minimum_size = Vector2(0, 70)
	_launch.add_theme_font_override("font", Neon.title_font())
	_launch.add_theme_font_size_override("font_size", 32)
	# a sunset bar (yellow, orange, pink) that glows; a cyan neon frame when focused
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	grad.colors = PackedColorArray([Neon.SUN, Neon.ORANGE, Neon.PINK])
	for state in ["normal", "hover", "pressed"]:
		var tex := GradientTexture2D.new()
		tex.gradient = grad
		tex.width = 256
		tex.height = 8
		var bsb := StyleBoxTexture.new()
		bsb.texture = tex
		bsb.modulate_color = Color(1, 1, 1) if state != "normal" else Color(0.85, 0.8, 0.85)
		_launch.add_theme_stylebox_override(state, bsb)
	var fsb := Neon.box(Color(0, 0, 0, 0), Neon.CYAN, 3, 14, 3)
	fsb.draw_center = false
	_launch.add_theme_stylebox_override("focus", fsb)
	for k in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
		_launch.add_theme_color_override(k, Color(0.12, 0.0, 0.2))
	_launch.pressed.connect(_launch_session)
	v.add_child(_launch)
	return root


func _option_row(parent: Control, key: String, label: String) -> OptionButton:
	var row := HBoxContainer.new()
	parent.add_child(row)
	_rows[key] = row
	var l := _label(label, 19)
	l.add_theme_font_override("font", Neon.bold_font())
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


func _open_setup(mode: String) -> void:
	_mode = mode
	_preview.visible = mode == DRILLS
	_setup_picture.visible = mode != DRILLS
	match mode:
		SANDBOX:
			var m := _sandbox_map()
			_setup_heading.text = "BAC À SABLE"
			_setup_title.text = "Bac à sable  -  %s" % str(m.name)
			_setup_picture.picture = _thumb(str(m.thumb))
			_setup_picture.title = str(m.name)
			_setup_picture.badge = ""
			_setup_text.text = "Pas de chrono, pas de score. " + str(m.text)
		DRILLS:
			var lab: Array = DRILL_LABELS[_drill]
			_setup_heading.text = "MOUVEMENT"
			_setup_title.text = str(lab[0])
			_setup_text.text = str(lab[2])
			_preview.show_movement(_drill, _level_opt.selected)
		_:
			if _sport != null:
				var pg := SportProgress.of(_sport.id)
				_setup_heading.text = "ENTRAÎNEMENT"
				_setup_title.text = "Session d'entraînement"
				_setup_picture.picture = _thumb(_sport.id)
				_setup_picture.title = _sport.display_name
				_setup_picture.badge = "%s  %s" % [str(pg.dots), str(pg.name)]
				_setup_text.text = "%s\n\n%s %s\n%s" % [_sport.description, str(pg.dots),
						("Prochain palier : " + str(pg.next)) if str(pg.next) != "" else "Sport terminé.",
						str(pg.detail)]
	_setup_picture.queue_redraw()
	_update_info()
	_show(_setup)


func _update_info() -> void:
	if _mode_opt == null:
		return
	var duo := _two_players()
	var training := _mode == TRAINING
	var drill := _mode == DRILLS
	_rows.mode.visible = training
	_rows.mode_info.visible = training
	_rows.movement.visible = training and not duo
	_rows.movement_info.visible = training and not duo
	_rows.speed.visible = drill
	_rows.speed_info.visible = drill
	_rows.level.visible = drill or (training and not duo)
	_rows.level_info.visible = drill or (training and not duo)
	# the pilot's screen only matters when someone flies the drone
	_rows.screens.visible = (duo and training) or _mode == SANDBOX
	if _mode == SANDBOX:
		_launch.text = "LANCER LE BAC À SABLE"
		return
	if drill:
		_speed_info.text = str(ScenarioMatrix.DRILL_STEPS[_speed_opt.selected].desc)
		_level_info.text = DroneDifficulty.describe(_drill_level())
		if _level_opt.selected <= 1:
			_level_info.text += "\n(Auto et Aléatoire n'ont pas de sens pour un exercice : c'est le niveau 2.)"
		_launch.text = "LANCER L'EXERCICE"
		_preview.show_movement(_drill, _drill_level())
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


## Level of a drill: the same row as a training session, but "Auto" (the difficulty of the sport)
## and "Aléatoire" mean nothing here, so they become level 2.
func _drill_level() -> int:
	return 2 if _level_opt.selected <= 1 else _level_opt.selected - 1


## The movements a training session may be asked for: everything but the drills.
func _training_movements() -> Array:
	var out: Array = []
	for m in ScenarioMatrix.MOVEMENTS:
		if not m.get("drill", false):
			out.append(str(m.id))
	return out


func _selected_movement() -> String:
	var all := _training_movements()
	var i := _movement_opt.selected - 1
	return "" if i < 0 or i >= all.size() else str(all[i])


# --- Launch --------------------------------------------------------------------------------------

func _launch_session() -> void:
	Ambience.choice = str(Ambience.MENU[_ambience_opt.selected])
	match _mode:
		SANDBOX: _start_sandbox()
		DRILLS: _start_drill()
		_: _start_training()


func _start_drill() -> void:
	_save_prefs()
	return_page = "setup"
	return_mode = DRILLS
	DuoSession.dual_screen = false
	ScenarioMatrix.launch(get_tree(), ScenarioMatrix.drill_config(_drill, _speed_opt.selected,
			_drill_level(), SessionConfig.LENSES[_lens_opt.selected]))


func _start_training() -> void:
	if _sport == null:
		return
	_save_prefs()
	return_page = "setup"
	return_mode = TRAINING
	DuoSession.dual_screen = _screens_opt.selected == 1
	var lv := _level_opt.selected  # 0 auto, 1 random, 2..7 = level 1..6
	var level := -1 if lv == 0 else (0 if lv == 1 else lv - 1)
	ScenarioMatrix.launch(get_tree(), ScenarioMatrix.generate(_sport.id, _selected_movement(), level, null, {}, SessionConfig.LENSES[_lens_opt.selected], _two_players()))


func _start_sandbox() -> void:
	_save_prefs()
	return_page = "setup"
	return_mode = SANDBOX
	DuoSession.dual_screen = _screens_opt.selected == 1
	Sandbox.lens_mm = SessionConfig.LENSES[_lens_opt.selected]
	LoadingScreen.run(func(): get_tree().change_scene_to_file("res://scenarios/sandbox/sandbox.tscn"))


func _start_random() -> void:
	return_page = "home"
	ScenarioMatrix.launch(get_tree(), ScenarioMatrix.generate())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		match _page:
			_setup:
				_open_play(_mode)
			_play:
				_show(_home)
		return
	if (_page == _home or (_page == _play and not _cards.is_empty())) and get_viewport().gui_get_focus_owner() == null:
		for a in ["ui_up", "ui_down", "ui_left", "ui_right", "ui_focus_next", "ui_focus_prev"]:
			if event.is_action_pressed(a):
				get_viewport().set_input_as_handled()
				(_play_tile if _page == _home else _cards[0] as Control).grab_focus()
				return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match _page:
		_home:
			match event.physical_keycode:
				KEY_R: _start_random()
				KEY_ENTER, KEY_KP_ENTER: _open_play(TRAINING)
		_play:
			var n: int = event.physical_keycode - KEY_1
			if n < 0:
				return
			match _mode:
				SANDBOX:
					if n < SANDBOX_MAPS.size():
						_choose_sandbox_map(str(SANDBOX_MAPS[n].id))
				DRILLS:
					var order := ScenarioMatrix.drills_by_difficulty()
					if n < order.size():
						_choose_drill(str(order[n]))
				_:
					if n < _sports.size():
						_choose_sport(n)
		_setup:
			if event.physical_keycode in [KEY_ENTER, KEY_KP_ENTER]:
				_launch_session()

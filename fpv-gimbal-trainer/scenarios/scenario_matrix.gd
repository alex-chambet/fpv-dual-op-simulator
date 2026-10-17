class_name ScenarioMatrix
extends RefCounted
## Generates training sessions by combining a sport, a drone movement and a difficulty level.
##  - sports   : the catalogue (every SubjectDefinition .tres under scenarios/subjects/catalogue/)
##  - movements: MOVEMENTS below (planned by MovementPlanner); a random session picks among the
##               movements the sport recommends
##  - level    : 1..6 (6 = Expert), mapped by DroneDifficulty to how close and how fast the drone flies
##               and the axes the operator has to handle
## ScenarioBase reads ScenarioMatrix.current when its scene starts.

const STATS_PATH := "user://matrix_stats.json"
## The one scene that plays every sport and every fixed scenario.
const RUNNER_SCENE := "res://scenarios/scenario.tscn"
## Sheets of the first version (recorded sessions of that time refer to them).
const LEGACY_SUBJECTS := {"skier": "ski_alpin", "car": "voiture_route", "runner": "trail"}
## Level parameters of a fixed scenario: the sheet is played as it is.
const FIXED_PARAMS := {"speed_scale": 1.0, "turn_scale": 1.0, "occlusion": 0.0, "aggression": 0.4}

const MOVEMENTS: Array[Dictionary] = [
	{"id": "pursuit", "name": "Rear pursuit", "desc": "The drone follows behind the subject, on its path."},
	{"id": "lateral", "name": "Lateral follow", "desc": "The drone flies alongside, drifting ahead and behind."},
	{"id": "frontal", "name": "Frontal", "desc": "The drone flies backwards in front of the subject, facing it."},
	{"id": "orbit", "name": "Orbit", "desc": "The drone circles the subject while it moves."},
	{"id": "reveal", "name": "Reveal", "desc": "The subject is hidden behind a barrier, then discovered as the drone flies past it."},
	{"id": "flyby", "name": "Flyby", "desc": "The drone crosses the subject at high relative speed, close to it."},
	# Expert figures (see MovementPlanner._build_figures)
	{"id": "approach_orbit", "name": "Approach + orbit", "desc": "The drone comes in from far and high and wraps into a fast orbit, again and again."},
	{"id": "dive", "name": "Dive", "desc": "The drone climbs high ahead of the subject, dives onto it, skims past and climbs out behind."},
	{"id": "choreo", "name": "Expert choreography", "desc": "Chained figures: approaches into an orbit, dives, head-on crossings, spirals."},
	# Drills ("Mouvements" menu): one figure, repeated. Never drawn for a training session - they are
	# played on purpose, on their own subject, at a chosen subject speed.
	{"id": "spiral_in", "name": "Spirale vers l'intérieur", "drill": true,
		"desc": "Le drone tourne autour du sujet en se rapprochant de plus en plus, puis ressort pour recommencer."},
	{"id": "reveal_up", "name": "Reveal tilt bas vers haut", "drill": true,
		"desc": "Le drone part haut et tout près, caméra plongeant sur le sol, puis descend en s'éloignant : le tilt remonte du sol jusqu'à l'horizon."},
	{"id": "pass_behind", "name": "Translation flyby par derrière", "drill": true,
		"desc": "Le drone arrive de loin, décalé en arrière, rattrape le sujet en passant derrière lui et ressort de l'autre côté pour le suivre latéralement."},
	{"id": "vertical_pass", "name": "Vertical tilt", "drill": true,
		"desc": "Le drone passe au-dessus du sujet, presque perpendiculairement : il entre légèrement par l'arrière et sort légèrement en avant. Mélange de tilt et de pan."},
]
## Ids of the drills, easiest figure first - the order the "Mouvements" menu shows them in.
const DRILL_MOVEMENTS := ["orbit", "reveal_up", "pass_behind", "spiral_in", "vertical_pass"]
## How hard each figure is to hold, 1 to 5. This is deliberately NOT
## DroneDifficulty.MOVEMENT_TIER: that one also weights the random draw of a training session,
## where an orbit is one of the harder movements among easy ones. Here it is the gentlest of five
## hard figures, and the rating has to rank the five against each other.
##  - orbit         one steady axis, the figure everything else is built on
##  - reveal_up     one axis again, but tilt, and it has to arrive on time
##  - pass_behind   fast pan with one reversal, long easy stretches either side
##  - spiral_in     as fast, but the pan keeps accelerating: harder to anticipate
##  - vertical_pass pan and tilt at full stretch together, right overhead
const DRILL_TIER := {"orbit": 2, "reveal_up": 3, "pass_behind": 4, "spiral_in": 4,
		"vertical_pass": 5}


## The drills, easiest first.
static func drills_by_difficulty() -> Array:
	var out := DRILL_MOVEMENTS.duplicate()
	out.sort_custom(func(a, b): return int(DRILL_TIER.get(a, 3)) < int(DRILL_TIER.get(b, 3)))
	return out
## Sheet the drills are flown around (a subject that does nothing but go straight ahead).
const DRILL_SUBJECT := "cible"
## Steps of a drill: the same figure around a subject that goes faster and faster. The first step
## is a subject standing still - the figure alone, nothing else to follow.
const DRILL_STEPS: Array[Dictionary] = [
	{"name": "Sujet immobile", "speed": 0.01, "duration": 80.0,
		"desc": "Le sujet ne bouge pas : il ne reste que la figure du drone à suivre."},
	{"name": "Marche", "speed": 1.5, "duration": 85.0,
		"desc": "Le sujet avance au pas : la figure se décale lentement, il faut recadrer en continu."},
	{"name": "Course", "speed": 4.5, "duration": 90.0,
		"desc": "Le sujet court : la figure et le sujet bougent tous les deux, à des vitesses différentes."},
	{"name": "Rapide", "speed": 9.0, "duration": 90.0,
		"desc": "Le sujet file à 32 km/h : le drone doit le rattraper pendant la figure."},
]

## The session being played.
static var current: SessionConfig = null


static func movement_info(id: String) -> Dictionary:
	for m in MOVEMENTS:
		if m.id == id:
			return m
	return {}


static func subjects() -> Array[SubjectDefinition]:
	return SubjectCatalogue.all()


## Parameters of a level: the subject is never changed by the level; the difficulty comes from the
## drone flight (see DroneDifficulty: movement, pan / tilt axes, proximity).
static func level_params(level: int) -> Dictionary:
	return DroneDifficulty.session_params(level)


## A random session. Empty subject_id / movement = random (movement among those the sport
## recommends); level 0 = random (1..5: the Expert level is only played on purpose), -1 = the base
## difficulty of the sport, 1..6 = that level.
## filter: {"category": "", "difficulty": 0, "movement": ""} restricts the sports drawn at random.
static func generate(subject_id := "", movement := "", level := 0, rng: RandomNumberGenerator = null,
		filter := {}, lens := 24, two_player := false) -> SessionConfig:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var cfg := SessionConfig.new()
	cfg.filter = filter
	cfg.lens = lens
	cfg.two_player = two_player
	if two_player:  # the drone is flown by a player: the movement / level only serve to plan the scenery
		movement = "lateral"
		level = 3
	var pool := SubjectCatalogue.filter(str(filter.get("category", "")), int(filter.get("difficulty", 0)),
			str(filter.get("movement", "")))
	if pool.is_empty():
		pool = SubjectCatalogue.menu_sports()
	if pool.is_empty():
		pool = SubjectCatalogue.all()
	var def := SubjectCatalogue.by_id(subject_id) if subject_id != "" else null
	cfg.lock_subject = def != null
	if def == null:
		def = pool[rng.randi() % pool.size()]
	cfg.subject = def

	if level > 0:
		cfg.level = level
		cfg.lock_level = true
	elif level < 0:
		cfg.level = clampi(def.base_difficulty, 1, 5)
		cfg.level_auto = true
	else:
		cfg.level = rng.randi_range(1, 5)
	cfg.params = level_params(cfg.level)

	if movement != "":
		cfg.movement = movement
		cfg.lock_movement = true
	else:
		# a movement that suits the level (an orbit or a flyby is rarely drawn at level 1)
		var allowed: Array = []
		for m in MOVEMENTS:
			if not m.get("drill", false) and def.movement_ok(m.id):
				allowed.append(m.id)
		if allowed.is_empty():
			for m in MOVEMENTS:
				if not m.get("drill", false):
					allowed.append(m.id)
		cfg.movement = DroneDifficulty.pick_movement(allowed, cfg.level, rng)
	cfg.seed = rng.randi() % 100000
	cfg.side = -1.0 if rng.randf() < 0.5 else 1.0
	cfg.ambience = Ambience.pick(rng, Ambience.is_snowy(def.environment))
	return cfg


## A movement drill ("Mouvements" menu): one figure, repeated around the drill subject, at the
## speed of `step` (DRILL_STEPS). The sheet is copied and its speed overridden, so the catalogue is
## is never touched.
##
## The ground stays as good as level. A sloping field would be the only one on which the camera
## really has to rise above the horizon to find a subject standing on it - but a gimbal holds the
## horizon level, so a slope puts the skyline across the frame at an angle for the whole run, which
## looks exactly like a gimbal that has stopped working. The reveal_up figure gets its tilt from
## its own geometry instead (high and close, looking steeply down, to low and far, looking level).
static func drill_config(movement: String, step: int, level: int, lens := 24,
		rng: RandomNumberGenerator = null) -> SessionConfig:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var base := SubjectCatalogue.by_id(DRILL_SUBJECT)
	if base == null:
		return generate("", movement, level, rng, {}, lens, false)
	var s: Dictionary = DRILL_STEPS[clampi(step, 0, DRILL_STEPS.size() - 1)]
	var def: SubjectDefinition = base.duplicate()
	def.overrides = base.overrides.duplicate(true)
	def.overrides.merge({"speed_min": float(s.speed), "speed_max": float(s.speed),
			"duration": float(s.duration)}, true)
	def.env_overrides = base.env_overrides.duplicate(true)
	var cfg := SessionConfig.new()
	cfg.subject = def
	cfg.movement = movement
	cfg.level = clampi(level, 1, DroneDifficulty.MAX_LEVEL)
	cfg.params = level_params(cfg.level)
	cfg.drill_step = clampi(step, 0, DRILL_STEPS.size() - 1)
	cfg.lens = lens
	cfg.lock_subject = true
	cfg.lock_movement = true
	cfg.lock_level = true
	cfg.seed = rng.randi() % 100000
	cfg.side = -1.0 if rng.randf() < 0.5 else 1.0
	cfg.ambience = Ambience.pick(rng, false)
	return cfg


## A new session with the same locked choices and filters.
static func next_session(cfg: SessionConfig) -> SessionConfig:
	if cfg.is_drill():
		return drill_config(cfg.movement, cfg.drill_step, cfg.level, cfg.lens)
	return generate(cfg.subject.id if cfg.lock_subject else "",
			cfg.movement if cfg.lock_movement else "",
			cfg.level if cfg.lock_level else (-1 if cfg.level_auto else 0), null, cfg.filter, cfg.lens, cfg.two_player)


## The session of a fixed scenario of the menu (ScenarioRegistry entry).
static func fixed_config(entry: Dictionary) -> SessionConfig:
	var cfg := SessionConfig.new()
	cfg.subject = SubjectCatalogue.by_id(str(entry.subject))
	cfg.movement = "legacy"
	cfg.level = 3
	cfg.params = FIXED_PARAMS.duplicate()
	cfg.seed = 0
	cfg.side = 1.0
	cfg.fixed = true
	cfg.fixed_id = str(entry.id)
	cfg.fixed_title = str(entry.title)
	return cfg


## Rebuilds a session from SessionConfig.to_dict() (null if it cannot be played any more).
static func config_from_dict(d: Dictionary) -> SessionConfig:
	var cfg := SessionConfig.new()
	if d.has("definition"):
		cfg.subject = SubjectDefinition.from_dict(d.definition)
	else:  # recorded before the catalogue existed
		var sid := str(d.get("subject", ""))
		cfg.subject = SubjectCatalogue.by_id(str(LEGACY_SUBJECTS.get(sid, sid)))
	if cfg.subject == null:
		return null
	cfg.movement = str(d.get("movement", "lateral"))
	cfg.level = int(d.get("level", 3))
	cfg.fixed = bool(d.get("fixed", false))
	cfg.fixed_id = str(d.get("fixed_id", ""))
	cfg.fixed_title = str(d.get("fixed_title", ""))
	cfg.params = FIXED_PARAMS.duplicate() if cfg.fixed else level_params(cfg.level)
	cfg.seed = int(d.get("seed", 0))
	cfg.side = float(d.get("side", 1.0))
	cfg.lens = int(d.get("lens", 24))
	cfg.two_player = bool(d.get("two_player", false))
	cfg.drill_step = int(d.get("drill_step", -1))
	cfg.ambience = str(d.get("ambience", "noon"))  # (sessions recorded before the ambiences: a bright day)
	return cfg


static func launch(tree: SceneTree, cfg: SessionConfig) -> void:
	current = cfg
	# planning the path and building the terrain can take a moment: a loading screen instead of a frozen frame
	LoadingScreen.run(func(): tree.change_scene_to_file(RUNNER_SCENE))


static func launch_fixed(tree: SceneTree, entry: Dictionary) -> void:
	launch(tree, fixed_config(entry))


# --- Training statistics ----------------------------------------------------------------------

static func get_stats() -> Dictionary:
	if not FileAccess.file_exists(STATS_PATH):
		return {"sessions": 0, "total": 0, "by_movement": {}}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(STATS_PATH))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {"sessions": 0, "total": 0, "by_movement": {}}


static func record_result(cfg: SessionConfig, overall: int) -> void:
	var s := get_stats()
	s.sessions = int(s.get("sessions", 0)) + 1
	s.total = int(s.get("total", 0)) + overall
	var by: Dictionary = s.get("by_movement", {})
	var m: Dictionary = by.get(cfg.movement, {"n": 0, "total": 0})
	m.n = int(m.n) + 1
	m.total = int(m.total) + overall
	by[cfg.movement] = m
	s.by_movement = by
	var f := FileAccess.open(STATS_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(s, "\t"))

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
			if def.movement_ok(m.id):
				allowed.append(m.id)
		if allowed.is_empty():
			for m in MOVEMENTS:
				allowed.append(m.id)
		cfg.movement = DroneDifficulty.pick_movement(allowed, cfg.level, rng)
	cfg.seed = rng.randi() % 100000
	cfg.side = -1.0 if rng.randf() < 0.5 else 1.0
	cfg.ambience = Ambience.pick(rng, Ambience.is_snowy(def.environment))
	return cfg


## A new session with the same locked choices and filters.
static func next_session(cfg: SessionConfig) -> SessionConfig:
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
	cfg.ambience = str(d.get("ambience", "noon"))  # (sessions recorded before the ambiences: a bright day)
	return cfg


static func launch(tree: SceneTree, cfg: SessionConfig) -> void:
	current = cfg
	tree.change_scene_to_file(RUNNER_SCENE)


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

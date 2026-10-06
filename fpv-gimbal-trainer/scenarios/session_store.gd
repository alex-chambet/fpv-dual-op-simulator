class_name SessionStore
extends RefCounted
## Recorded sessions on disk: user://sessions/<id>.json (full record: inputs + scores) and
## user://sessions/index.json (small metadata list, for the History screen).

const DIR := "user://sessions/"
const INDEX_PATH := "user://sessions/index.json"

## Set by start_replay(); consumed (and cleared) by ScenarioBase when its scene starts.
static var replay_record: Dictionary = {}
## Why the last start_replay() returned false.
static var last_error := ""


static func save(record: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var f := FileAccess.open(DIR + str(record.id) + ".json", FileAccess.WRITE)
	if f == null:
		push_error("SessionStore: cannot write session %s" % record.id)
		return
	f.store_string(JSON.stringify(record))
	f.close()
	var idx := index()
	idx.append(meta_of(record))
	_write_index(idx)


## Metadata of every saved session (unsorted).
static func index() -> Array:
	if FileAccess.file_exists(INDEX_PATH):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(INDEX_PATH))
		if typeof(parsed) == TYPE_ARRAY:
			return parsed
	return rebuild_index()


static func rebuild_index() -> Array:
	var out := []
	var dir := DirAccess.open(DIR)
	if dir:
		for file in dir.get_files():
			if file.ends_with(".json") and file != "index.json":
				var rec := load_full(file.get_basename())
				if not rec.is_empty():
					out.append(meta_of(rec))
	_write_index(out)
	return out


static func load_full(id: String) -> Dictionary:
	var path := DIR + id + ".json"
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


static func delete(id: String) -> void:
	DirAccess.remove_absolute(DIR + id + ".json")
	var idx := index().filter(func(m): return m.id != id)
	_write_index(idx)


static func meta_of(rec: Dictionary) -> Dictionary:
	var sc: Dictionary = rec.scenario
	var res: Dictionary = rec.scores
	return {
		"id": rec.id,
		"timestamp": rec.timestamp,
		"date": rec.date,
		"scenario_id": sc.id,
		"title": sc.title,
		"group": "Training (generated)" if (sc.get("matrix") != null and not bool(sc.matrix.get("fixed", false))) else str(sc.title).capitalize(),
		"overall": res.overall,
		"grade": res.grade,
		"framing": res.framing,
		"fluidity": res.fluidity,
		"tracking": res.tracking,
		"run_time": res.run_time,
	}


## Loads a session and starts its replay (the scenario scene in replay mode). False if impossible.
static func start_replay(tree: SceneTree, id: String) -> bool:
	var rec := load_full(id)
	if rec.is_empty():
		return false
	var m = rec.scenario.get("matrix")
	last_error = "This session cannot be replayed (its scenario or subject is no longer available)."
	if m != null and not bool(m.get("fixed", false)) and int(rec.get("flight", 1)) < DroneDifficulty.FLIGHT_VERSION:
		last_error = "This training session was recorded with an older drone flight model and cannot be replayed."
		return false
	var cfg: SessionConfig
	if m != null:
		cfg = ScenarioMatrix.config_from_dict(m)
	else:  # fixed scenario recorded before the catalogue existed
		var entry := ScenarioRegistry.find(str(rec.scenario.id))
		if not entry.is_empty():
			cfg = ScenarioMatrix.fixed_config(entry)
	if cfg == null or cfg.subject == null:
		return false
	ScenarioMatrix.current = cfg
	replay_record = rec
	tree.change_scene_to_file(ScenarioMatrix.RUNNER_SCENE)
	return true


static func _write_index(idx: Array) -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var f := FileAccess.open(INDEX_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(idx))

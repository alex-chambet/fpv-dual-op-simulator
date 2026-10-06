class_name SubjectCatalogue
extends RefCounted
## The catalogue of sports: every SubjectDefinition (.tres) found under
## res://scenarios/subjects/catalogue/ (sub-folders included). Read once per run; adding a sheet is
## enough for it to appear in the menu and in the random generation.

const DIR := "res://scenarios/subjects/catalogue"
## Display order of the categories (unknown categories follow, alphabetically).
const CATEGORY_ORDER := ["Neige / glace", "Montagne / outdoor", "Mécanique", "Eau", "Air",
		"Cycle / urbain", "Équestre", "Collectifs / terrain"]

static var _all: Array[SubjectDefinition] = []
static var _loaded := false


static func all() -> Array[SubjectDefinition]:
	if not _loaded:
		reload()
	return _all


static func reload() -> void:
	_all = []
	_scan(DIR)
	_all.sort_custom(func(a: SubjectDefinition, b: SubjectDefinition):
		var ca := _category_rank(a.category)
		var cb := _category_rank(b.category)
		if ca != cb:
			return ca < cb
		if a.category != b.category:
			return a.category < b.category
		return a.display_name.naturalnocasecmp_to(b.display_name) < 0)
	_loaded = true


static func by_id(sport_id: String) -> SubjectDefinition:
	for s in all():
		if s.id == sport_id:
			return s
	return null


## The sheets offered to the players (in_menu = true). all() still returns every sheet.
static func menu_sports() -> Array[SubjectDefinition]:
	var out: Array[SubjectDefinition] = []
	for s in all():
		if s.in_menu:
			out.append(s)
	return out


static func categories() -> Array[String]:
	var out: Array[String] = []
	for s in menu_sports():
		if not s.category in out:
			out.append(s.category)
	return out


## Menu sheets matching the filters (empty category / 0 difficulty / empty movement = no filter).
static func filter(category := "", difficulty := 0, movement := "") -> Array[SubjectDefinition]:
	var out: Array[SubjectDefinition] = []
	for s in menu_sports():
		if category != "" and s.category != category:
			continue
		if difficulty > 0 and s.base_difficulty != difficulty:
			continue
		if movement != "" and not s.movement_ok(movement):
			continue
		out.append(s)
	return out


## Human-readable problems found in the catalogue (empty = all good).
static func validate() -> PackedStringArray:
	var out := PackedStringArray()
	var seen := {}
	for s in all():
		var tag := "[%s]" % (s.id if s.id != "" else s.resource_path.get_file())
		if s.id == "":
			out.append("%s sheet without id" % tag)
		elif seen.has(s.id):
			out.append("%s duplicate id (also %s)" % [tag, seen[s.id]])
		seen[s.id] = s.resource_path.get_file()
		if not s.archetype in SubjectDefinition.ARCHETYPES:
			out.append("%s unknown archetype '%s'" % [tag, s.archetype])
		else:
			var known: Dictionary = ArchetypeRegistry.get_archetype(s.archetype).defaults()
			for k in s.overrides:
				if not known.has(k):
					out.append("%s unknown parameter '%s' for %s" % [tag, k, s.archetype])
			var params := s.resolved_params()
			if float(params.speed_min) > float(params.speed_max):
				out.append("%s speed_min is greater than speed_max" % tag)
			if s.archetype != "SAUT_ACROBATIQUE" and float(params.path_length) <= 0.0 and float(params.duration) <= 0.0:
				out.append("%s needs a positive duration or path_length" % tag)
		for m in s.recommended_movements:
			if ScenarioMatrix.movement_info(m).is_empty():
				out.append("%s unknown drone movement '%s'" % [tag, m])
		if s.base_difficulty < 1 or s.base_difficulty > 5:
			out.append("%s base_difficulty must be 1..5" % tag)
		if s.subject_size < 0.0 or s.effective_size() <= 0.0:
			out.append("%s subject_size must be >= 0 (0 = archetype default) and the size must be > 0" % tag)
		if not EnvironmentRegistry.has_style(s.environment):
			out.append("%s environment '%s' has no style: generic fallback ground used" % [tag, s.environment])
	return out


static func _category_rank(c: String) -> int:
	var i := CATEGORY_ORDER.find(c)
	return i if i >= 0 else CATEGORY_ORDER.size()


static func _scan(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_scan(dir_path.path_join(sub))
	for file in dir.get_files():
		# exported projects list text resources as "<name>.tres.remap"
		var fname := file.trim_suffix(".remap")
		if fname.ends_with(".tres"):
			var res := ResourceLoader.load(dir_path.path_join(fname))
			if res is SubjectDefinition:
				_all.append(res)

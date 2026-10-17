class_name PracticeAdvisor
extends RefCounted
## What the player should work on next, worked out from what they have already played.
##
## The catalogue is 8 sports x 9 drone movements x 6 levels x 4 lenses: over 1 700 combinations.
## Nobody explores that by hand, and the recorded sessions show it - half of them are lateral
## follows. The two files needed to give useful advice were already being written and nobody was
## reading them:
##   - matrix_stats.json  : how many sessions of each movement, and the total of their scores
##   - best_scores.json   : the best score of every combination played (SessionConfig.scenario_id)
##
## suggest() turns them into one session to play. The rule is deliberately plain, so that what the
## menu says can always be justified by a number it shows: the movement whose scores are weakest
## wins, a movement barely played counts as weak, and one never played is treated as an unknown
## rather than as a disaster (otherwise the advice would never leave the easiest movement).

## At or above this, a combination counts as mastered.
const GOOD := 75.0
## What a movement that has never been played is assumed to be worth, out of 100.
const UNKNOWN := 60.0
## A movement gets a bonus for every session short of this many.
const ENOUGH := 6.0
const PER_MISSING := 4.0
## Level proposed for a drill (the drill's own ladder is its subject speed, not the level).
const DRILL_LEVEL := 3


## The session to play next, or {} when there is nothing to suggest.
## {kind: "drill"|"training", movement, label, where, reason, level, step?, subject?}
static func suggest() -> Dictionary:
	var by: Dictionary = ScenarioMatrix.get_stats().get("by_movement", {})
	var best: Dictionary = SessionScorer.all_best()
	var ranked := _rank(by)
	if ranked.is_empty():
		return {}
	var top: Dictionary = ranked[0]
	var mv: String = top.id
	if mv in ScenarioMatrix.DRILL_MOVEMENTS:
		return _drill_for(mv, top, best)
	return _training_for(mv, top, best)


## Every movement worth proposing, weakest first. Expert figures are left out: they are level 6 on
## purpose, not homework.
static func _rank(by: Dictionary) -> Array:
	var out: Array = []
	for m in ScenarioMatrix.MOVEMENTS:
		var id := str(m.id)
		if id in DroneDifficulty.EXPERT_MOVEMENTS:
			continue
		var e: Dictionary = by.get(id, {})
		var n := int(e.get("n", 0))
		var mean := (float(e.get("total", 0)) / float(n)) if n > 0 else UNKNOWN
		out.append({
			"id": id, "n": n, "mean": mean,
			"need": (100.0 - mean) + maxf(0.0, ENOUGH - n) * PER_MISSING,
		})
	# weakest first; between two equals, the gentler figure comes first
	out.sort_custom(func(a, b):
		if absf(float(a.need) - float(b.need)) > 0.01:
			return float(a.need) > float(b.need)
		return DroneDifficulty.movement_tier(str(a.id)) < DroneDifficulty.movement_tier(str(b.id)))
	return out


## A movement that has a drill: the drill is the point of the "Mouvements" tab. Its ladder is the
## subject speed, so the step proposed is the first one not yet done well.
static func _drill_for(mv: String, top: Dictionary, best: Dictionary) -> Dictionary:
	var step := 0
	for s in ScenarioMatrix.DRILL_STEPS.size():
		step = s
		var b := 0
		for key in best:
			if str(key).begins_with("drill_%s_v%d_L" % [mv, s]):
				b = maxi(b, int(best[key]))
		if b < GOOD:
			break
	var name := str(ScenarioMatrix.movement_info(mv).get("name", mv))
	return {
		"kind": "drill", "movement": mv, "step": step, "level": DRILL_LEVEL,
		"label": name,
		"where": "Exercice  -  %s" % str(ScenarioMatrix.DRILL_STEPS[step].name),
		"reason": _reason(top),
	}


## A movement with no drill: a training session, on the sport where it went worst if it has been
## played, otherwise on the sport played most (a familiar course, so the movement is the difficulty).
static func _training_for(mv: String, top: Dictionary, best: Dictionary) -> Dictionary:
	var sport := ""
	var level := 3
	var lens := 24
	var worst := 101
	var counts := {}
	for key in best:
		var parts := _parse(str(key))
		if parts.is_empty():
			continue
		counts[parts.sport] = int(counts.get(parts.sport, 0)) + 1
		if str(parts.movement) == mv and int(best[key]) < worst:
			worst = int(best[key])
			sport = str(parts.sport)
			level = int(parts.level)
			lens = int(parts.lens)
	if sport == "" or SubjectCatalogue.by_id(sport) == null:
		sport = _most_played(counts)
		var def := SubjectCatalogue.by_id(sport)
		level = clampi(def.base_difficulty, 2, 5) if def != null else 3
		lens = 24
	var def2 := SubjectCatalogue.by_id(sport)
	return {
		"kind": "training", "movement": mv, "subject": sport, "level": level, "lens": lens,
		"label": str(ScenarioMatrix.movement_info(mv).get("name", mv)),
		"where": "%s  -  niveau %d" % [def2.display_name if def2 != null else sport, level],
		"reason": _reason(top),
	}


static func _reason(top: Dictionary) -> String:
	var n := int(top.n)
	if n == 0:
		return "Jamais travaillé."
	if n == 1:
		return "Une seule session, %d/100." % roundi(float(top.mean))
	return "Ta moyenne : %d/100 sur %d sessions." % [roundi(float(top.mean)), n]


## "matrix_<sport>_<movement>_L<level>[_<lens>mm]" -> {sport, movement, level, lens}, or {}.
## The sport and the movement both contain underscores, so the movement is matched against the
## known ids rather than guessed from the position of the separators.
static func _parse(key: String) -> Dictionary:
	if not key.begins_with("matrix_"):
		return {}
	var rest := key.substr(7)
	var lens := 24
	if rest.ends_with("mm"):
		var cut := rest.rfind("_")
		if cut > 0:
			lens = int(rest.substr(cut + 1).trim_suffix("mm"))
			rest = rest.substr(0, cut)
	var cut_l := rest.rfind("_L")
	if cut_l <= 0:
		return {}
	var level := int(rest.substr(cut_l + 2))
	rest = rest.substr(0, cut_l)
	# the LONGEST matching id wins: "..._approach_orbit" also ends with "_orbit"
	var found := ""
	for m in ScenarioMatrix.MOVEMENTS:
		var id := str(m.id)
		if rest.ends_with("_" + id) and id.length() > found.length():
			found = id
	if found == "":
		return {}
	return {"sport": rest.substr(0, rest.length() - found.length() - 1),
		"movement": found, "level": level, "lens": lens}


static func _most_played(counts: Dictionary) -> String:
	var best_id := ""
	var best_n := -1
	for s in counts:
		if int(counts[s]) > best_n:
			best_n = int(counts[s])
			best_id = str(s)
	if best_id != "" and SubjectCatalogue.by_id(best_id) != null:
		return best_id
	var pool := SubjectCatalogue.menu_sports()
	return pool[0].id if not pool.is_empty() else ""


## The session itself, ready for ScenarioMatrix.launch().
static func config_for(s: Dictionary, lens := 0) -> SessionConfig:
	var mm := lens if lens > 0 else int(s.get("lens", 24))
	if str(s.get("kind", "")) == "drill":
		return ScenarioMatrix.drill_config(str(s.movement), int(s.step), int(s.level), mm)
	return ScenarioMatrix.generate(str(s.subject), str(s.movement), int(s.level), null, {}, mm, false)

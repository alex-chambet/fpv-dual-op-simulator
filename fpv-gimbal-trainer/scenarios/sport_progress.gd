class_name SportProgress
extends RefCounted
## NOT SHOWN AT THE MOMENT. The steps were on the sport cards and on the setup page; they were
## taken off because they did not read clearly enough. Nothing calls this any more - it is kept
## because the thresholds below and the way they are named took measuring to get right, not
## because anything depends on it. Delete it if it is still unused in a while.
##
## Three steps to reach on each sport, so that a sport is something you can get to the end of
## rather than an endless list of combinations to pick from.
##
## Like PracticeAdvisor, this invents no data: it reads the best scores the game already records
## (best_scores.json, keyed by SessionConfig.scenario_id). The steps are deliberately about
## *breadth then quality*, because that is what the recorded sessions show is missing - half of
## them are lateral follows, and 2 % of the catalogue has ever been played.

## 70/100 counts as "the movement is under control", 85 at level 4+ as "mastered".
const SOLID := 70
const SOLID_MOVEMENTS := 3
const MASTER := 85
const MASTER_LEVEL := 4

const STEPS := [
	{"name": "Découverte", "goal": "finir une session sur ce sport"},
	{"name": "Solide", "goal": "70/100 sur trois mouvements différents"},
	{"name": "Maîtrise", "goal": "85/100 au niveau 4 ou plus"},
]


## Where the player is on a sport:
## {done: 0..3, name: the step being worked on, next: its goal (empty when finished), detail: where
##  they are on it, dots: "●●○"}
##
## The steps are counted independently, not in order - someone can master a sport at level 5 while
## still having only two movements at 70. `dots` therefore says how many of the three are ticked,
## and `name` says which one is being worked on, which is the first one NOT ticked. Naming the
## highest step counted instead would label that player "Solide" while Solide is exactly what they
## are missing.
static func of(sport_id: String, best := {}) -> Dictionary:
	if best.is_empty():
		best = SessionScorer.all_best()
	var played := 0
	var solid := {}        # movements already at SOLID
	var mastered := false
	var top := 0
	for key in best:
		var p: Dictionary = PracticeAdvisor.parse_key(str(key))
		if p.is_empty() or str(p.sport) != sport_id:
			continue
		var score := int(best[key])
		played += 1
		top = maxi(top, score)
		if score >= SOLID:
			solid[str(p.movement)] = true
		if score >= MASTER and int(p.level) >= MASTER_LEVEL:
			mastered = true
	var hit := [played > 0, solid.size() >= SOLID_MOVEMENTS, mastered]
	var done := 0
	for h in hit:
		if h:
			done += 1
	var next_i := -1
	for i in hit.size():
		if not hit[i]:
			next_i = i
			break
	return {
		"done": done,
		"name": "Terminé" if next_i < 0 else str(STEPS[next_i].name),
		"next": "" if next_i < 0 else str(STEPS[next_i].goal),
		"detail": _detail(next_i, played, solid.size(), top),
		"dots": "●".repeat(done) + "○".repeat(STEPS.size() - done),
	}


static func _detail(next_i: int, played: int, solid: int, top: int) -> String:
	match next_i:
		-1: return "Les trois paliers sont passés."
		0: return "Jamais joué."
		1: return "%d mouvement%s sur %d à %d/100." % [solid, "s" if solid > 1 else "", SOLID_MOVEMENTS, SOLID]
		_: return "Meilleur score : %d/100." % top if played > 0 else ""

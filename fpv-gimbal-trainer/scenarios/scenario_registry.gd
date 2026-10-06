class_name ScenarioRegistry
extends RefCounted
## The fixed scenarios of the menu. Each one is a sport of the catalogue ("subject" = the id of
## its sheet) played in its environment with a scripted drone and a fixed layout. "id" is the key
## of the best scores; "title" is shown in the scenario.


static func list() -> Array[Dictionary]:
	return [
		{
			"id": "ski_slope",
			"name": "Slalom",
			"title": "SKI SLALOM",
			"difficulty": "Moyen",
			"subject": "ski_alpin",
			"desc": "Suivi latéral d'un skieur entre les portes. Changements de direction rapides, quelques arbres et un rocher qui masquent le sujet.",
		},
		{
			"id": "mountain_pass",
			"name": "Col de montagne",
			"title": "MOUNTAIN PASS",
			"difficulty": "Moyen",
			"subject": "voiture_route",
			"desc": "Poursuite d'une voiture dans les lacets. La route passe dans un tunnel : la voiture disparaît complètement quelques secondes.",
		},
		{
			"id": "forest_trail",
			"name": "Sentier en forêt",
			"title": "FOREST TRAIL",
			"difficulty": "Difficile",
			"subject": "trail",
			"desc": "Un coureur sur un sentier sinueux en forêt dense. Le drone vole bas entre les troncs : occultations fréquentes et brèves.",
		},
	]


static func find(id: String) -> Dictionary:
	for e in list():
		if e.id == id:
			return e
	return {}

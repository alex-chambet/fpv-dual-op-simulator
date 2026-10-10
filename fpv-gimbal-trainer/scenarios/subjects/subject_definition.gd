class_name SubjectDefinition
extends Resource
## Data sheet of a sport / subject. One .tres per sport in res://scenarios/subjects/catalogue/
## (any sub-folder): the catalogue is read automatically by the menu and by ScenarioMatrix.
## To add a sport, duplicate a sheet and edit it - see docs/ajouter_un_sport.md.

const ARCHETYPES := ["GLISSE_PENTE", "COURSE_SOL_CYCLIQUE", "VEHICULE_ROUTE", "TOUT_TERRAIN_ERRATIQUE",
		"EAU_SURFACE", "AIR_LIBRE", "STOP_AND_GO_ZONE", "SAUT_ACROBATIQUE", "DESCENTE"]

## Unique identifier (letters, digits, underscore). Used in saved sessions: do not rename lightly.
@export var id := ""
@export var display_name := ""
## Menu group, e.g. "Neige / glace", "Eau"...
@export var category := ""
@export_multiline var description := ""

## false = the sheet stays in the catalogue (tests, replays, direct use) but the menu does not offer it.
@export var in_menu := true

@export_group("Movement")
## Movement archetype (see docs): the way the subject moves along its path.
@export_enum("GLISSE_PENTE", "COURSE_SOL_CYCLIQUE", "VEHICULE_ROUTE", "TOUT_TERRAIN_ERRATIQUE",
		"EAU_SURFACE", "AIR_LIBRE", "STOP_AND_GO_ZONE", "SAUT_ACROBATIQUE", "DESCENTE") var archetype := "GLISSE_PENTE"
## Archetype parameters to override, e.g. {"speed_max": 20.0, "lateral_amplitude": 12.0}.
## Everything not listed keeps the archetype default (list: docs/ajouter_un_sport.md).
@export var overrides := {}

@export_group("Subject (placeholder)")
## Largest dimension of the placeholder, in metres (a person is about 1.8, a car 4.2).
## 0 = the typical size of the archetype (its `subject_size` parameter).
@export_range(0.0, 20.0, 0.05, "suffix:m") var subject_size := 0.0
@export_enum("person", "person_lying", "box", "capsule", "sphere") var placeholder_shape := "person"
## Extra primitives attached to the placeholder (skis, bike, horse...).
@export_enum("none", "skis", "snowboard", "sled", "skates", "wheels", "skateboard", "wakeboard",
		"surfboard", "sup", "bike", "moto", "horse", "car", "kart", "scooter", "kayak", "scull", "sail",
		"canopy", "wings") var placeholder_gear := "none"
@export var placeholder_color := Color(0.95, 0.4, 0.05)
## Secondary colour (helmet, head...).
@export var placeholder_accent := Color(0.1, 0.35, 0.9)

@export_group("Environment")
## Environment tag (free text with suggestions). Specific environments exist for neige,
## route_montagne and foret; the other tags are generic styles (res://scenarios/environments/styles/).
## An unknown tag falls back to a simple generic ground so the sport can still be tested.
@export_custom(PROPERTY_HINT_ENUM_SUGGESTION, "neige,descente,glace,route_montagne,foret,terrain_vague,piste_urbaine,stade,salle,court,prairie,eau_vive,lac,mer,ciel,falaise,arete") var environment := "neige"
## Overrides of the environment parameters (e.g. {"slope": 0.08} for a gentle ski slope).
@export var env_overrides := {}

@export_group("Training")
## Drone movements that suit this sport (ids from ScenarioMatrix: pursuit, lateral, frontal,
## orbit, reveal, flyby). Random sessions pick among them; empty = all.
@export var recommended_movements := PackedStringArray()
## Base difficulty of the sport, 1 (easy to frame) to 5 (very hard).
@export_range(1, 5) var base_difficulty := 3


## Archetype parameters: the archetype defaults overridden by this sheet.
func resolved_params() -> Dictionary:
	var arch := ArchetypeRegistry.get_archetype(archetype)
	var p: Dictionary = arch.defaults().duplicate()
	for k in overrides:
		p[k] = overrides[k]
	return p


## Size of the placeholder, m: this sheet's subject_size, or the archetype's typical size when it is 0.
func effective_size() -> float:
	if subject_size > 0.0:
		return subject_size
	return float(resolved_params().get("subject_size", 1.8))


func movement_ok(movement_id: String) -> bool:
	return recommended_movements.is_empty() or movement_id in recommended_movements


## Plain-data copy (saved with each recorded session so a replay never depends on later edits).
func to_dict() -> Dictionary:
	return {
		"id": id, "display_name": display_name, "category": category, "description": description, "in_menu": in_menu,
		"archetype": archetype, "overrides": overrides.duplicate(true), "subject_size": subject_size,
		"placeholder_shape": placeholder_shape, "placeholder_gear": placeholder_gear,
		"placeholder_color": placeholder_color.to_html(true),
		"placeholder_accent": placeholder_accent.to_html(true),
		"environment": environment, "env_overrides": env_overrides.duplicate(true),
		"recommended_movements": Array(recommended_movements), "base_difficulty": base_difficulty,
	}


static func from_dict(d: Dictionary) -> SubjectDefinition:
	var s := SubjectDefinition.new()
	s.id = str(d.get("id", ""))
	s.display_name = str(d.get("display_name", s.id))
	s.category = str(d.get("category", ""))
	s.description = str(d.get("description", ""))
	s.in_menu = bool(d.get("in_menu", true))
	s.archetype = str(d.get("archetype", "GLISSE_PENTE"))
	s.overrides = d.get("overrides", {}).duplicate(true)
	s.subject_size = float(d.get("subject_size", 0.0))
	s.placeholder_shape = str(d.get("placeholder_shape", "person"))
	s.placeholder_gear = str(d.get("placeholder_gear", "none"))
	s.placeholder_color = Color.html(str(d.get("placeholder_color", "f26619ff")))
	s.placeholder_accent = Color.html(str(d.get("placeholder_accent", "1a59e6ff")))
	s.environment = str(d.get("environment", "neige"))
	s.env_overrides = d.get("env_overrides", {}).duplicate(true)
	s.recommended_movements = PackedStringArray(d.get("recommended_movements", []))
	s.base_difficulty = int(d.get("base_difficulty", 3))
	return s

class_name ArchetypeRegistry
extends RefCounted
## The nine movement archetypes, by id.

static var _cache := {}


static func ids() -> Array[String]:
	var out: Array[String] = []
	for a in SubjectDefinition.ARCHETYPES:
		out.append(a)
	return out


static func get_archetype(id: String) -> SubjectArchetype:
	if _cache.has(id):
		return _cache[id]
	var a: SubjectArchetype
	match id:
		"GLISSE_PENTE": a = ArchetypeGlissePente.new()
		"COURSE_SOL_CYCLIQUE": a = ArchetypeCourseSolCyclique.new()
		"VEHICULE_ROUTE": a = ArchetypeVehiculeRoute.new()
		"TOUT_TERRAIN_ERRATIQUE": a = ArchetypeToutTerrainErratique.new()
		"EAU_SURFACE": a = ArchetypeEauSurface.new()
		"AIR_LIBRE": a = ArchetypeAirLibre.new()
		"STOP_AND_GO_ZONE": a = ArchetypeStopAndGoZone.new()
		"SAUT_ACROBATIQUE": a = ArchetypeSautAcrobatique.new()
		"DESCENTE": a = ArchetypeDescente.new()
		_:
			push_warning("Unknown archetype '%s', using GLISSE_PENTE" % id)
			a = ArchetypeGlissePente.new()
	_cache[id] = a
	return a

class_name EnvironmentRegistry
extends RefCounted
## Finds the style of an environment tag and creates its builder.

const STYLE_DIR := "res://scenarios/environments/styles/"
const FALLBACK_TAG := "generic"


static func has_style(tag: String) -> bool:
	return ResourceLoader.exists(STYLE_DIR + tag + ".tres")


## The style of a tag; an unknown tag gets the generic fallback style (simple ground + props).
static func style_for(tag: String) -> EnvironmentStyle:
	var path := STYLE_DIR + tag + ".tres"
	if not ResourceLoader.exists(path):
		path = STYLE_DIR + FALLBACK_TAG + ".tres"
	var s := ResourceLoader.load(path) as EnvironmentStyle
	if s == null:
		s = EnvironmentStyle.new()
	return s


static func create(style: EnvironmentStyle, host: ScenarioBase, overrides: Dictionary) -> EnvironmentBuilder:
	var b: EnvironmentBuilder
	match style.builder:
		"snow": b = EnvSnow.new()
		"mountain_road": b = EnvMountainRoad.new()
		"forest": b = EnvForest.new()
		_: b = EnvGeneric.new()
	b.setup(host, style, overrides)
	return b


## Tags that have a style file.
static func known_tags() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(STYLE_DIR)
	if dir:
		for f in dir.get_files():
			var fname := f.trim_suffix(".remap")
			if fname.ends_with(".tres"):
				out.append(fname.get_basename())
	out.sort()
	return out

class_name ArchetypeContext
extends RefCounted
## What an archetype needs to build a path: the environment (ground height), the resolved
## parameters and a random generator.

var env: EnvironmentBuilder
var params: Dictionary
var rng: RandomNumberGenerator
var def: SubjectDefinition


func _init(e: EnvironmentBuilder, p: Dictionary, r: RandomNumberGenerator, d: SubjectDefinition) -> void:
	env = e
	params = p
	rng = r
	def = d


## Ground height of the environment before any path-dependent change (road bed...).
func ground(x: float, z: float) -> float:
	return env.base_height(x, z)


func ground_fn() -> Callable:
	return Callable(env, "base_height")

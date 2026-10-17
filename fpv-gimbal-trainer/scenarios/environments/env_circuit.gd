class_name EnvCircuit
extends EnvironmentBuilder
## Racing circuit (tag "circuit"): the Nürburgring Grand-Prix-Strecke at half scale, built by
## CircuitScenery from a CircuitLayout - asphalt, kerbs, run-off, guardrails and debris fences,
## pit building and pit lane, grandstands with their crowd, the start / finish gantry, the Dunlop
## bridge, the marshal posts, the spruce forest of the Eifel and the tower of Nürburg castle.
##
## The subject (ArchetypeCircuit) asks this builder for the very same CircuitLayout, so the car runs
## on the asphalt that is drawn, with the real gradients of the circuit.
##
## env_overrides: `track_scale` (0.5 by default: half the real circuit), `point_step` (spacing of the
## centre line, m).

var layout: CircuitLayout
var scenery: CircuitScenery


func configure() -> void:
	surface_offset = 0.05
	layout = CircuitLayout.new(float(opt("track_scale", 0.5)), float(opt("point_step", 3.0)))
	corridor_half_width = layout.half_width


## The circuit the subject drives on (read by ArchetypeCircuit).
func circuit_layout() -> CircuitLayout:
	return layout


func base_height(x: float, z: float) -> float:
	return layout.ground(x, z)


func ground(x: float, z: float) -> float:
	return layout.ground(x, z)


func far_height(x: float, z: float) -> float:
	return layout.free_height(x, z)


## The drone stays above the ground and above the grandstands, the pit building and the bridges.
func clearance(x: float, z: float) -> float:
	return scenery.clearance(x, z) if scenery != null else ground(x, z)


func occluder_kind() -> String:
	return "walls"


## Everything is built here (not in populate) because the drone planner runs in between and needs
## clearance() to already know where the buildings are.
func build_terrain(_path: PackedVector3Array, _plan: Dictionary) -> void:
	scenery = CircuitScenery.new()
	scenery.build(host, layout, 7 + host.world_seed)
	ground_mask = scenery.mask
	terrain_rect = scenery.terrain_rect
	terrain_material = scenery.terrain_material
	for b in scenery.boxes:
		host.add_cylinder_occluder(b.c, maxf(float(b.hx), float(b.hz)), float(b.h))


func grass_params() -> Dictionary:
	return scenery.grass_params() if scenery != null else {}


## Wooded Eifel hills all around, and the forest going on to the horizon.
func far_scenery() -> Dictionary:
	return {"ring_radius": 1700.0, "ring_cell": 34.0,
		"hills": {"height": 170.0, "r0": 1500.0, "r1": 5200.0, "frequency": 0.0007,
			"forest": Color(0.07, 0.17, 0.08), "grass": Color(0.24, 0.35, 0.14)},
		"trees": {"kind": "conifer", "count": 1700, "r0": 230.0, "r1": 1300.0,
			"colour": Color(0.07, 0.26, 0.12), "grove": 0.3},
		"canopy": {"r0": 330.0, "height": 15.0, "colour": Color(0.08, 0.22, 0.1), "grove": 0.5}}


func dynamic_push(pos: Vector3, radius: float) -> Vector3:
	return scenery.push(pos, radius) if scenery != null else Vector3.ZERO


func hud_extra() -> String:
	return ""

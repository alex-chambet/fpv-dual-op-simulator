class_name CircuitWorld
extends RefCounted
## The circuit as a sandbox map: the same Nürburgring Grand-Prix-Strecke as the training level
## (CircuitLayout + CircuitScenery), with the interface the Sandbox scene and the autopilot expect
## (ground, push, roads, start_pos...). The cars are added by CircuitTraffic.

var layout: CircuitLayout
var scenery: CircuitScenery
## Roads the autopilot may follow: the track itself (closed) and the pit lane.
var roads: Array[Dictionary] = []
var start_pos := Vector3.ZERO
var start_look := Vector3.FORWARD
var mask: GroundMask
var terrain_material: Material

var _host: Node3D


func build(host: Node3D) -> void:
	_host = host
	layout = CircuitLayout.new(0.5, 3.0)
	scenery = CircuitScenery.new()
	scenery.build(host, layout, 7)
	mask = scenery.mask
	terrain_material = scenery.terrain_material
	roads = [{"kind": "circuit", "pts": layout.centre3d(), "closed": true}]
	FarScenery.build_into(host, Callable(self, "far_height"), 7, scenery.terrain_rect,
			terrain_material, far_scenery())
	# the drone starts on the start / finish straight, just past the line, looking down the track
	var p := layout.side_point(30.0, -layout.half_width - 7.0)
	start_pos = p
	var d := layout.dir_at(30.0)
	start_look = Vector3(d.x, 0.0, d.y)


func ground(x: float, z: float) -> float:
	return layout.ground(x, z)


func far_height(x: float, z: float) -> float:
	return layout.free_height(x, z)


func grass_params() -> Dictionary:
	return scenery.grass_params()


func push(pos: Vector3, r: float) -> Vector3:
	return scenery.push(pos, r)


## Where the autopilot may wander: the circuit and a margin around it, all over the built terrain.
func flight_area() -> Rect2:
	return layout.bounds.grow(130.0)


## Inside this radius the autopilot flies low ("no tall trees"): the whole circuit, which has none.
func low_zone_radius() -> float:
	return 100000.0


func far_scenery() -> Dictionary:
	return {"ring_radius": 1700.0, "ring_cell": 34.0,
		"hills": {"height": 170.0, "r0": 1500.0, "r1": 5200.0, "frequency": 0.0007,
			"forest": Color(0.07, 0.17, 0.08), "grass": Color(0.24, 0.35, 0.14)},
		"trees": {"kind": "conifer", "count": 1700, "r0": 230.0, "r1": 1300.0,
			"colour": Color(0.07, 0.26, 0.12), "grove": 0.3},
		"canopy": {"r0": 330.0, "height": 15.0, "colour": Color(0.08, 0.22, 0.1), "grove": 0.5}}

class_name LensFocus
extends Node
## The focus of the gimbal camera: the subject sharp, the rest soft, as a real lens does it.
##
## This is not decoration. At 85 mm the background detaches from the subject and at 24 mm it does
## not — that difference *is* the lesson of the four lenses, and it is the single thing that most
## makes a shot read as filmed rather than rendered. So the limits here are the real ones, not a
## nice-looking blur: the hyperfocal distance of the chosen focal length at f/2.0, on the full-frame
## sensor the field of view is computed for (SessionConfig.SENSOR_HEIGHT_MM), so the full-frame
## circle of confusion, 0.03 mm.
##
## The focus is *pulled*, not snapped: it follows the subject over a few tenths of a second, like a
## focus puller riding the wheel. A cut to a new distance therefore passes through a soft moment,
## which is exactly what happens on set.

const COC := 0.03        ## circle of confusion, mm (full frame)
const F_NUMBER := 2.0    ## a cine prime wide open; the four focal lengths then separate properly
const PULL := 3.0        ## how fast the focus follows the subject, per second
const MAX_FAR := 3000.0  ## past this there is nothing left to separate from: far blur off

var focal_mm := 24.0
var _cam: Camera3D
var _attr: CameraAttributesPractical
var _focus := 0.0


func setup(cam: Camera3D, mm: float) -> void:
	_cam = cam
	set_lens(mm)
	_attr = cam.attributes as CameraAttributesPractical
	if _attr == null:
		_attr = CameraAttributesPractical.new()
		cam.attributes = _attr


func set_lens(mm: float) -> void:
	focal_mm = maxf(mm, 1.0)


## Near and far limits of acceptable sharpness when focused at `s_m` metres, in metres; the far one
## is INF once the focus reaches the hyperfocal distance (everything beyond it is sharp — which is
## why a 24 mm never separates anything). H = f² / (N·c) + f, then the textbook limits.
static func depth_of_field(s_m: float, mm: float) -> Array:
	var f := mm * 0.001
	var h := (mm * mm) / (F_NUMBER * COC) * 0.001 + f
	var s := maxf(s_m, f * 1.01)
	var near := s * (h - f) / (h + s - 2.0 * f)
	return [near, INF if s >= h else s * (h - f) / (h - s)]


## `distance` is how far the camera is from what it is filming, in metres. Called every frame, after
## the camera and the subject have moved.
func update(delta: float, distance: float) -> void:
	if _attr == null:
		return
	_attr.auto_exposure_enabled = GraphicsSettings.auto_exposure
	if GraphicsSettings.auto_exposure:
		# a camera's auto iris, which lags: pan from the snow up to the sky and it takes a moment
		_attr.auto_exposure_speed = 0.4
		_attr.auto_exposure_scale = 0.5
	if not GraphicsSettings.dof:
		_attr.dof_blur_far_enabled = false
		_attr.dof_blur_near_enabled = false
		return
	var d := clampf(distance, 0.5, 2000.0)
	_focus = d if _focus <= 0.0 else lerpf(_focus, d, clampf(delta * PULL, 0.0, 1.0))
	var limits := depth_of_field(_focus, focal_mm)
	var near: float = limits[0]
	var far: float = minf(limits[1], MAX_FAR)
	# diameter of the blur circle of a point at infinity, in circles of confusion: how far out of
	# focus the background actually is. It is what sets the strength, so a long lens blurs more.
	var blur := (focal_mm * focal_mm) / (F_NUMBER * _focus * 1000.0) / COC
	_attr.dof_blur_amount = clampf(blur * 0.1, 0.04, 1.0)
	_attr.dof_blur_near_enabled = near > _cam.near * 3.0
	_attr.dof_blur_near_distance = near
	_attr.dof_blur_near_transition = maxf(near * 0.45, 0.2)
	_attr.dof_blur_far_enabled = limits[1] < MAX_FAR
	_attr.dof_blur_far_distance = far
	_attr.dof_blur_far_transition = maxf(far * 0.6, 1.0)

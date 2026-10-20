class_name SoundLayer
extends RefCounted
## One loop in a stack of loops, with the window of speed (or effort, or skid) where it is heard.
##
## This is the whole reason the sound stopped being synthetic. A single recording stretched by
## pitch over a whole speed range always sounds like one recording stretched: a car at 40 km/h and
## the same car at 160 km/h are not the same sound played faster, they are different sounds. So
## each voice holds several samples and crossfades between them, exactly as a racing game does -
## and the ear reads the result as one machine changing state rather than as a tape speeding up.
##
## A layer is described by data, not code:
##   sound   name in SoundLibrary
##   window  [a, b, c, d] on the driving value: silent below a, full from b to c, silent past d
##   pitch   Vector2, pitch_scale at the two ends of `over`
##   over    Vector2, the span of the driving value the pitch is mapped across. It defaults to the
##           window, which is right for a layer that fades out again - but a layer that stays on to
##           the top (window [.., .., 1e9, 1e9]) would then never move its pitch at all, which is
##           exactly the bug this field exists to prevent: the tyres sat at 0.75 for a whole lap.
##   db      level when the layer is at full
## A layer whose window is [-1, -1, 1e9, 1e9] is simply always on, which is how a bed is written.

const SILENT_DB := -60.0

var player: Node
var window := PackedFloat32Array([0.0, 0.0, 1.0e9, 1.0e9])
var pitch := Vector2.ONE
var over := Vector2(0.0, 1.0)
var db := 0.0
## Smoothing of the gain, per second; 0 = follow the value exactly. Keeps a layer from clicking in
## when the driving value is noisy (a measured speed always is).
var smooth := 8.0

## Multiplies the windowed gain, for what the window cannot say: how hard the engine is pulling at
## a rev it would pass through either way, how much of the airframe the wind is actually hitting.
var gain_mul := 1.0

var _gain := 0.0
var _started := false


static func make(parent: Node, name: String, cfg: Dictionary, positional: bool) -> SoundLayer:
	var stream := SoundLibrary.stream(name)
	if stream == null:
		return null
	var l := SoundLayer.new()
	var p: Node = AudioStreamPlayer3D.new() if positional else AudioStreamPlayer.new()
	p.stream = stream
	p.name = "L_" + name
	l.player = p
	l.window = PackedFloat32Array(cfg.get("window", [0.0, 0.0, 1.0e9, 1.0e9]))
	l.pitch = cfg.get("pitch", Vector2.ONE)
	l.over = cfg.get("over", Vector2(l.window[0], l.window[3]))
	l.db = float(cfg.get("db", 0.0))
	l.smooth = float(cfg.get("smooth", 8.0))
	parent.add_child(p)
	return l


## Starts the loop at a random point, so several copies of the same sample (two wind beds, the
## props of two drones) never sit in phase and comb-filter each other.
func start() -> void:
	if player == null or _started:
		return
	_started = true
	player.volume_db = SILENT_DB
	var len_s := 0.0
	if player.stream != null:
		len_s = player.stream.get_length()
	player.play(randf() * len_s if len_s > 0.0 else 0.0)


## `v` is the value this layer listens to: the subject's speed, the engine's rev, the skid, the
## drone's effort - whatever the voice decided to drive it with.
func set_value(v: float, delta: float) -> void:
	if player == null:
		return
	var target := _window_gain(v) * clampf(gain_mul, 0.0, 4.0)
	_gain = target if smooth <= 0.0 else lerpf(_gain, target, clampf(delta * smooth, 0.0, 1.0))
	player.volume_db = SILENT_DB if _gain <= 0.004 else maxf(linear_to_db(_gain) + db, SILENT_DB)
	var span := over.y - over.x
	var t := 0.0 if absf(span) < 1e-6 else clampf((v - over.x) / span, 0.0, 1.0)
	player.pitch_scale = maxf(lerpf(pitch.x, pitch.y, t), 0.01)


## Trapezoid, with smoothstep edges so two neighbouring layers sum to roughly constant power
## instead of dipping in the middle of the crossfade.
func _window_gain(v: float) -> float:
	if v <= window[0] or v >= window[3]:
		return 0.0
	if v < window[1]:
		return smoothstep(window[0], window[1], v)
	if v > window[2]:
		return 1.0 - smoothstep(window[2], window[3], v)
	return 1.0


func set_paused(on: bool) -> void:
	if player != null:
		player.stream_paused = on

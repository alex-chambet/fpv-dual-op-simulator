class_name SoundLibrary
extends RefCounted
## Where every sound in the game comes from.
##
## A recorded sample if the project has one, otherwise the procedural loop that SoundBank builds.
## That fallback is not a courtesy: it means the game always has a voice, the project still runs
## with no audio assets at all, and a missing or badly named file degrades to something audible
## instead of to silence - which is the failure you do not notice until someone reports it.
##
## Names are the contract between the files on disk and the voices that mix them (see
## SubjectVoice, DroneVoice). A sample is mono, seamless, and loops; everything expressive -
## level, pitch, crossfade - is done at runtime by the layers, never baked in.

const DIR := "res://assets/audio/%s.ogg"

## What to generate when a file is missing: which SoundBank loop, and its roughness when it has one.
const FALLBACK := {
	"wind_low": ["wind", 0.0],
	"wind_mid": ["wind", 0.0],
	"wind_high": ["wind", 0.0],
	"wind_gust": ["wind", 0.0],
	"engine_idle": ["engine", 0.3],
	"engine_mid": ["engine", 0.6],
	"engine_high": ["engine", 0.9],
	"tyres": ["rolling", 0.0],
	"ski_carve": ["edges", 0.0],
	"ski_skid": ["edges", 0.0],
	"prop_low": ["prop", 0.0],
	"prop_high": ["prop", 0.0],
}

static var _cache := {}
static var _missing := {}


## True when a real recording is on disk for this name.
static func recorded(name: String) -> bool:
	return ResourceLoader.exists(DIR % name)


## The stream for a name, loaded or generated once and kept.
static func stream(name: String) -> AudioStream:
	if _cache.has(name):
		return _cache[name]
	var s: AudioStream = null
	if recorded(name):
		s = load(DIR % name)
		if s is AudioStreamOggVorbis:
			(s as AudioStreamOggVorbis).loop = true
	if s == null:
		if not FALLBACK.has(name):
			push_warning("SoundLibrary: no file and no fallback for '%s'" % name)
			return null
		_missing[name] = true
		var spec: Array = FALLBACK[name]
		match str(spec[0]):
			"engine": s = SoundBank.engine(float(spec[1]))
			"rolling": s = SoundBank.rolling()
			"edges": s = SoundBank.edges()
			"prop": s = SoundBank.prop()
			_: s = SoundBank.wind()
	_cache[name] = s
	return s


## Names that fell back to a generated loop; empty once every sample is in place.
static func missing() -> Array:
	return _missing.keys()

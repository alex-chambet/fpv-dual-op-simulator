extends RefCounted
## Carte de hauteurs d'un terrain réel (MNT), lue dans un fichier brut de float32.
##
## Deux fichiers portent le même nom : `<base>.f32` (les altitudes, ligne par ligne, du bord -z vers
## +z et du bord -x vers +x) et `<base>.json` (le cadre : `w`, `h`, `cell`, `x0`, `z0`, plus ce qui a
## servi à le fabriquer). Les altitudes sont relatives à `origin_altitude` : le 0 du monde du jeu est
## l'altitude du point d'origine, sinon toute la scène serait à 2 000 m de l'origine de Godot.
##
## Pas de `class_name` : ce dossier n'est jamais exporté (voir test/README.md), et un nom de classe
## global survivrait dans le cache des classes d'un build où le script, lui, n'existe plus.

var w := 0
var h := 0
var cell := 1.0
var x0 := 0.0
var z0 := 0.0
var heights := PackedFloat32Array()
var info := {}


## Charge `<base>.f32` + `<base>.json`. Renvoie faux (et se plaint dans la console) si l'un manque.
func load_map(base: String) -> bool:
	var jf := FileAccess.open(base + ".json", FileAccess.READ)
	if jf == null:
		push_error("MNT introuvable : " + base + ".json")
		return false
	var parsed = JSON.parse_string(jf.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("MNT illisible : " + base + ".json")
		return false
	info = parsed
	w = int(info.get("w", 0))
	h = int(info.get("h", 0))
	cell = float(info.get("cell", 1.0))
	x0 = float(info.get("x0", 0.0))
	z0 = float(info.get("z0", 0.0))
	var f := FileAccess.open(base + ".f32", FileAccess.READ)
	if f == null:
		push_error("MNT introuvable : " + base + ".f32")
		return false
	heights = f.get_buffer(f.get_length()).to_float32_array()
	if heights.size() != w * h:
		push_error("MNT incohérent : %d altitudes pour %d x %d" % [heights.size(), w, h])
		return false
	return true


## Altitude en (x, z), bilinéaire entre les texels. Au-delà du bord, la valeur du bord (le terrain
## lointain s'appuie dessus : mieux vaut un prolongement plat qu'un trou).
func height(x: float, z: float) -> float:
	if heights.is_empty():
		return 0.0
	var fx := clampf((x - x0) / cell, 0.0, float(w - 1))
	var fz := clampf((z - z0) / cell, 0.0, float(h - 1))
	var ix := mini(int(fx), w - 2)
	var iz := mini(int(fz), h - 2)
	var tx := fx - ix
	var tz := fz - iz
	var a := lerpf(heights[iz * w + ix], heights[iz * w + ix + 1], tx)
	var b := lerpf(heights[(iz + 1) * w + ix], heights[(iz + 1) * w + ix + 1], tx)
	return lerpf(a, b, tz)


## Le rectangle couvert, en xz.
func rect() -> Rect2:
	return Rect2(x0, z0, (w - 1) * cell, (h - 1) * cell)


## Altitude réelle (m, NGF) correspondant à une hauteur du jeu.
func real_altitude(y: float) -> float:
	return y + float(info.get("origin_altitude", 0.0))

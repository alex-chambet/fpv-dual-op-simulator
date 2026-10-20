# `test/` — banc d'essai, jamais dans un build

Ce dossier est un bac d'expérimentation : on y essaie des choses (ici : un terrain réel importé
d'un modèle numérique de terrain) avant de décider si elles entrent dans le jeu.

**Il n'est jamais exporté.** Trois verrous, indépendants :

1. `export_presets.cfg` : `exclude_filter="test/*"` sur chaque préréglage (Windows et macOS) — les
   fichiers ne sont pas mis dans le `.pck`. Vérifié en exportant un `.pck` en ligne de commande :
   aucune occurrence de `res://test/`, `face_wnw` ni `test_level` dedans.
2. L'onglet **TEST** du menu n'apparaît que si `OS.has_feature("editor")` est vrai, c'est-à-dire
   depuis l'éditeur seulement (`ui/main_menu.gd`, `_test_available`).
3. Le même test vérifie aussi que `res://test/test_level.tscn` existe : dans un build, il n'y est
   pas, donc l'onglet ne peut pas s'afficher même si le premier verrou sautait.

Aucun script d'ici ne déclare de `class_name`, et rien dans le jeu ne référence ce dossier en dehors
de `_test_available()` et du chemin de la scène : le reste du projet se compile et s'exporte
exactement pareil, que ce dossier soit là ou non.

## Ce qu'il y a dedans

| Fichier | Rôle |
|---|---|
| `test_level.tscn` / `.gd` | la scène : terrain réel, ciel d'hiver, caméra en vol libre |
| `dem_map.gd` | lecture d'une carte de hauteurs (`.f32` brut + `.json` de cadrage) |
| `dem/face_wnw.*` | la face, maillée au mètre : 760 × 1 120 m |
| `dem/face_wnw_far.*` | le relief alentour au 10 m, jusqu'à 1,8 km (jonction fine) |
| `dem/face_wnw_horizon.*` | le relief au 25 m jusqu'à 9 km : les vrais sommets à l'horizon |
| `dem/ortho_near.jpg`, `ortho_far.jpg`, `ortho.json` | l'orthophoto IGN (44 cm sur 1,8 km, 3,9 m sur 16 km) |
| `ortho.gdshader` | la plaque sur le relief (touche **O**) — sert à se repérer, pas à jouer |
| `dem/lignes.json` | les deux descentes filmées, reconstituées (touches **P** / **R**) |

## D'où viennent les altitudes

**IGN LIDAR HD, MNT 50 cm** (couche `IGNF_LIDAR-HD_MNT_ELEVATION.ELEVATIONGRIDCOVERAGE.LAMB93` de la
Géoplateforme, format BIL float32), **licence Etalab 2.0**.

Le **RGE ALTI 1 m** a d'abord été essayé : dans cette zone de montagne il est interpolé, pas mesuré.
Mesuré sur la dalle native, non tournée : **0,80 m** d'écart résiduel entre un point et la moyenne de
ses voisins, contre **0,056 m** pour le lidar — soit un bruit 14 fois plus fort, qui se voyait comme
un croisillon régulier sur toute la face et fabriquait de fausses pentes (18 % du terrain sous 10° et
16 % au-dessus de 50°, contre 3 % et 7 % en vrai). Les barres rocheuses ne s'en distinguaient pas.

L'horizon, lui, vient de la couche `ELEVATION.ELEVATIONGRIDCOVERAGE` (RGE ALTI en France, SRTM
au-delà) : le RGE ALTI seul s'arrête à la frontière italienne et laissait 7 % de trous sur 24 km.

Le découpage se fait hors du jeu (scripts Python, sans dépendance) : téléchargement des dalles,
passage en Lambert-93, rotation dans le repère du jeu, puis **moyenne de 4 points du lidar par texel
de 1 m** — aucun filtre de lissage, la donnée est assez propre pour s'en passer. L'échantillonnage
est **bicubique** : en bilinéaire, la pente saute à chaque bord de maille source et la grille tournée
(22°) ressort en croisillon dans l'ombrage.

## Repère

`face_wnw.json` porte tout ce qu'il faut pour revenir au terrain réel :

- origine du monde = **le point donné** (45°37'06.81"N 6°54'01.87"E), sur la crête, à **2 509,5 m**,
  qui est le `y = 0` du jeu ; en Lambert-93, 1 003 842 / 6 509 620 ;
- `+z` = ligne de pente descendante, **azimut vrai 295°** (WNW) ; `+x` = azimut 205° ;
- la face va de `z = 0` (2 510 m) à `z = 1 060` (**1 979 m**), sur `x` de -380 à +380 ;
- `convergence_deg` = 2,830° : l'écart entre le nord de la grille Lambert-93 et le nord vrai, déjà
  pris en compte dans la rotation.

## Les deux vidéos FPV

`data/REAL_WORLD_MAPS/FREERIDE_BEC_ROUGE/` : deux descentes filmées en FPV derrière un skieur,
1080p50, 15,5 s et 16,5 s, exportées de DaVinci Resolve (timecodes 12:21 et 13:52).

**Où elles se passent.** La carte IGN nomme **Bec Rouge** exactement au point donné : c'est le sommet
dont cette face est le versant WNW. Dans FREERIDE_5, entre 8 et 10 s, le drone franchit l'arête et
découvre la vallée : on y reconnaît, sur le versant d'en face, les pistes et les routes de
Sainte-Foy-Tarentaise, et le même éboulis clair que l'orthophoto. Le rendu du terrain avec
l'orthophoto plaquée, pris depuis le bas de la face vers l'azimut 280-285°, donne le même cadre.

**Ce qui est mesuré** (`scratchpad` : `skier.py`, `rythme.py`) : le skieur est suivi **toutes les
2 images** (25 Hz) sur sa veste rouge — seul objet saturé d'une scène de neige — avec un suivi
temporel pour ne pas sauter sur un rocher brun.

| | FREERIDE_3 | FREERIDE_5 |
|---|---|---|
| skieur visible | 4,6 → 15,4 s (10,9 s) | 8,1 → 16,5 s (8,4 s) |
| distance drone-skieur | médiane 95 m | médiane 48 m, jusqu'à 20 m |
| changement de côté dans le cadre | toutes les 0,64 s | toutes les 0,52 s |
| place dans l'image | u 0,46 / v 0,39 | u 0,48 / v 0,49 |

**Les lignes** (`dem/lignes.json`) ne sont pas un relevé GPS : les fichiers n'en portent aucun.
Ce sont des **reconstitutions** : le skieur descend par le calcul en visant la ligne de plus grande
pente du relief réel, écartée alternativement à gauche et à droite **au rythme mesuré**, pendant la
**durée mesurée**, à une vitesse qui suit la pente. La ligne contourne donc les arêtes et plonge dans
les couloirs comme la vraie, puisque c'est le même relief — mais sa position latérale exacte reste à
confirmer par celui qui a filmé.

---

Mesures sur l'extrait : **31° de pente moyenne**, exposition **305°** (WNW, comme annoncé), et par
tranche de pente — 14 % entre 10 et 20°, 25 % entre 20 et 30°, 36 % entre 30 et 40°, 16 % entre 40 et
50°, 4 % entre 50 et 60°, 2,6 % au-delà : ce dernier dixième, ce sont les barres.

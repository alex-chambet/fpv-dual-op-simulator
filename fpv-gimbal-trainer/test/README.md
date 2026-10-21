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

## Le rendu, calé sur les rushs

Cinq autres fichiers servent de référence : `DRONE_FPV.mov` (3 min de vol, grand angle) et
`LIGNE_1..4.mov` (téléobjectifs sur la face). Le réglage n'a pas été fait à l'œil : un script
(`scratchpad/couleurs.py`) classe les pixels d'une image en ciel / neige au soleil / neige à l'ombre
/ rocher, et donne la couleur moyenne de chaque classe. On mesure le réel, on mesure le rendu, on
corrige l'écart. Ce que ça a donné :

| | rushs | rendu avant | rendu après |
|---|---|---|---|
| ciel, haut du cadre | R110 G140 B178 | R80 G118 B181 | R103 G134 B175 |
| ciel, vers l'horizon | R136 G162 B184 | R100 G132 B184 | R133 G153 B180 |
| neige au soleil | R210 G217 B223 | R205 G208 B217 | R212 G213 B215 |
| neige à l'ombre | R161 G175 B190 | R145 G160 B193 | R153 G166 B187 |
| rocher | R74 G83 B92 | R64 G81 B120 | R81 G94 B116 |

Trois corrections, toutes dictées par ces chiffres :

1. **Le ciel était un bleu cobalt** (B − R = +100) là où le vrai ciel d'altitude est un bleu acier
   (+68) qui pâlit juste au-dessus des crêtes. Comme l'ambiante est prise du ciel, le dé-saturer a
   réparé du même coup le **rocher, qui virait franchement au bleu**.
2. **Le mouchetis.** Le seuil de rocher du shader était à 43° : sur une face qui ondule autour de 31°,
   il est franchi partout et chaque bosse devenait une tache grise, alors que les téléobjectifs
   montrent de la neige lisse et quelques îlots noirs francs. Remonté à **50°**, il ne reste que 6 %
   du terrain — les barres et les ressauts. Et les deux blancs de la neige ont été rapprochés : le
   shader les mélange avec un bruit de 70 m qui moutonnait toute la face, alors que l'albédo de la
   neige est uniforme.
3. **La brume mangeait tout** : divisée par deux (une crête à 3 km est encore franche sur les rushs),
   et elle ne blanchit plus le ciel. Nuages retirés — il n'y en avait pas ce jour-là.

Le MNT, lui, est passé par une **surface de neige** : fermeture morphologique de 7 m puis lissage.
Le lidar est levé en été, c'est la surface du rocher ; la neige comble les clefts étroits (jusqu'à
15 m dans les plus marquées) et arrondit le reste. L'effet est faible en moyenne (2 cm) mais il
divise par trois le bruit résiduel au mètre.

### Ce que le MNT seul ne donne pas : les stries et les blocs

Deux choses des rushs ne sont dans aucun modèle de terrain, et ont été ajoutées par-dessus.

**Les stries de vent**, gravées dans la carte de hauteurs (`add_flutes` dans `export3.py`) : la neige
soufflée s'organise en côtes et en gouttières dans la ligne de pente. Elles sont **gravées** et pas
seulement peintes dans la normale du shader, parce que celui-ci les efface au-delà de 220 m alors
qu'en vrai on les voit sur toute la face. 70 cm de creux pour 19 m d'écartement, plus une ondulation
secondaire de 16 cm : **larges et pas seulement hautes**, parce qu'à amplitude égale des côtes
serrées ajoutent beaucoup de pente locale et remettraient le mouchetis de rocher. Pour la même
raison elles s'effacent dès 40° — les pentes raides sont de toute façon soufflées ou rocheuses.
Vérifié : la répartition des pentes est inchangée au dixième de point près.

**Les parois à facettes** (`facet_rock.gd` + `_build_rocks` dans `test_level.gd`) : à la maille du
mètre, une barre est une marche propre, alors que sur place c'est de la roche **cassée**. Les rochers
du jeu (`Rocks`) ne convenaient pas : ce sont des galets, une sphère subdivisée deux fois puis
déformée par du bruit, donc des formes molles. D'où un générateur à part — un icosaèdre **non
subdivisé** (12 sommets, 20 faces), chaque sommet poussé ou tiré au hasard, aplati selon le litage,
la base tranchée, et surtout des **normales par face** : c'est ce qui fait lire une arête.

**Vingt facettes suffisent à un caillou, pas à une paroi.** À dix mètres, un bloc d'un mètre n'en
montre que trois ou quatre ; une paroi de douze mètres remplit le cadre et ses vingt grands plans se
lisent comme un polyèdre de carton — c'est le « trop lisse » du dernier retour. D'où les **passes de
cassure** (`LOD` dans `facet_rock.gd`) : chaque face est coupée en quatre sur ses milieux et les
nouveaux sommets sont repoussés **ou enfoncés** le long de leur rayon, l'amplitude divisée par deux à
chaque passe comme un bruit fractal. Repoussé, un sommet fait un angle saillant ; enfoncé, un dièdre
rentrant — c'est le mélange des deux qui donne de la roche cassée et non une boule bosselée. 20
facettes jusqu'à 3 m, 80 jusqu'à 7 m, 320 au-delà, soit des plans de la taille d'un homme sur une
paroi de douze mètres, comme sur les téléobjectifs.

Et une **deuxième octave de relief** dans le shader (`bump_coarse`), de longueur d'onde quatre fois
plus grande, qui monte avec la taille là où `bump` descend : le relief fin est moyenné par les
mipmaps dès vingt mètres de distance et la grande paroi redevenait lisse justement à la distance où
on la regarde. S'y ajoutent les grandes plages claires et sombres (bancs mouillés, faces fraîchement
cassées) et l'assombrissement du fond des diaclases, qui ne voit pas le ciel.

Ils sont posés par **parois** et non un par un : deux à six bancs empilés selon un même litage —
incliné entre la pente et l'horizontale — et étagés le long de la barre, ce qui crée les vires où la
neige se pose. 3 600 bancs et ~2 800 pierres roulées (celles-là restent les rochers du jeu, c'est la
bonne forme pour des blocs tombés), là où la pente dépasse 46° **mesurée sur 12 m** — à 4 m, les
stries gravées suffiraient à franchir le seuil et on sèmerait des blocs en pleine pente.

Le plafond a été porté de 2 200 à **3 600** bancs, et la probabilité de poser une paroi passe de
0,09 à **0,71** entre 46° et 64° (au lieu de 0,39) : à l'ancien réglage, une barre franche n'avait
droit qu'à quatre ou cinq parois et le reste de son nez n'était que du rocher **peint**, qui sur une
face à 55° s'étire en traînées verticales et ne ressemble à rien. Les blocs sont du même coup un peu
plus petits (2,4 à 10 m au lieu de 3,2 à 15), donc plus nombreux sur la même surface.

Quatre réglages trouvés en comparant aux rushs :

- `Vegetation.snow_cover` à **0,42** et non 0,9 : à 0,9 le shader enneige toute face tournée vers le
  haut et les blocs ressortaient en **points blancs**, alors qu'ils sont noirs sur les rushs, avec de
  la neige seulement sur leurs vires les plus plates.
- **Un shader à échelle réglable** (`facet_rock.gdshader`, copie de celui du jeu) : son motif était
  figé à `wpos * 0.55`, soit une répétition tous les 1,8 m — le bon réglage pour un caillou de deux
  mètres, qui s'étale en **peau de léopard** sur une paroi de douze. L'échelle est maintenant choisie
  par tranche de taille (0,55 / 0,36 / 0,23 / 0,15), ce qui a permis de passer de 5 m à **16 m** :
  la taille d'une paroi suit la raideur, 3 m sur une cassure à 46°, jusqu'à 16 m sur une vraie paroi
  à 64°. La force de la normale baisse avec la taille, elle brouillait les arêtes.
- Roche **plus sombre et plus contrastée** que celle du jeu, sinon les facettes ne se détachent pas.
  Mesuré : R81 G94 B116 contre R80 G93 B103 sur les rushs.
- **Le rocher peint vient du masque de sol, plus du seuil de pente.** Le shader de neige lit la pente
  **à 1 m** — donc la moindre bosse — alors que les parois se posent sur la pente **à 12 m**, celle
  des vraies barres : deux zones différentes, d'où des taches grises sans un bloc dessus. Un
  `GroundMask` (le mécanisme qu'utilise déjà la face freeride du jeu) peint le rouge là où la pente
  large dépasse 54°, et le seuil de pente est repoussé à 68° pour ne plus servir que sur les
  presque-verticales. Le rocher peint et le rocher en volume coïncident enfin.

### Entailler les barres en gradins : essayé, abandonné

Idée suivante, et elle était juste sur le principe : une barre n'est pas une rampe mais un escalier,
des vires presque plates séparées par des ressauts presque verticaux. On l'obtient en aimantant
l'altitude sur une famille de plans parallèles, dans les zones raides. Codé (`terrace` dans
`export3.py`, gardé mais **désactivé**), essayé à deux échelles, abandonné :

- **le pas est contraint par le bas.** Sur une pente à 50°, un gradin de H mètres n'occupe que
  0,84 × H à l'horizontale. À 1,6 m il tient dans une seule maille : ce n'est plus un escalier, c'est
  un crénelage. Il faut au moins 4 m pour qu'une vire fasse quatre mailles de large.
- **il est contraint par le haut par l'aspect.** À 4,5 m, une barre portait dix vires et
  l'alternance rocher (ressaut) / neige (vire) se dithérait dès qu'on s'éloignait : la face prenait
  un air de tôle ondulée. À 10 m, les vires alignaient les bancs posés dessus et l'ensemble lisait
  comme des nattes rayées. Entre les deux, rien ne marche.
- et de toute façon **une carte de hauteurs ne sait pas représenter un surplomb**, qui est justement
  ce qui fait une paroi.

Conclusion : le relief d'une barre doit venir de **maillages posés par-dessus** — les parois à
facettes — et non d'une quantification du MNT. Ce qui a été gardé de l'essai : les bancs d'une même
paroi sont maintenant légèrement de travers les uns par rapport aux autres, parce qu'alignés ils
dessinaient eux aussi des rayures.

Les bancs disparaissent au-delà de 260 à 800 m selon leur taille, les pierres au-delà de 150 m et
sans ombre portée. Mesuré au chronomètre sur 2,5 s : **60 img/s avec ou sans**, c'est-à-dire que ça
ne coûte rien (et non les « 19 img/s » qu'affichait `get_frames_per_second`, qui ne se rafraîchit
qu'une fois par seconde et mentait sur des poses de 0,3 s).

### Le skieur

`ski_run.gd` hérite de **`PathSubject`**, la classe que suivent tous les sujets du jeu : elle avance
le long d'une courbe, calcule l'inclinaison que le virage demande (`lean_deg`), **celle qu'il
demandera une demi-seconde plus tard** (`lean_soon_deg`) et l'accélération verticale du terrain
(`heave_g`). `AthleteModel` lit ces trois nombres et en tire toute la gestuelle : les genoux qui
traversent, le bâton qui part en avant, l'extension, le planter, l'angulation, l'absorption. Le
skieur du TEST est donc exactement celui du jeu — rien n'a été réécrit, et la fiche `ski_freeride`
est juste copiée pour lui mettre la veste rouge du rush.

Ce qu'on impose, c'est la trajectoire et le **tempo** : les points de `lignes.json` sont espacés d'un
pas de temps fixe, donc leur écartement **est** la vitesse, qu'on repasse en profil de vitesse. La
trace au sol est un MultiMesh dont on ne montre que la partie déjà skiée — sinon le skieur descend
sur une piste déjà faite.

**Vérifié après coup**, en laissant tourner la descente : **17,0 s** et un changement de carre toutes
les **0,53 s**, contre **0,52 s** mesurées sur FREERIDE_5. Deux bogues trouvés par cette mesure :

- le générateur avançait à la vitesse voulue **à l'horizontale**, donc sur une pente à 50° le skieur
  parcourait une fois et demie trop de chemin le long de la neige, et la descente se jouait d'autant
  plus vite ;
- `Basis.scaled()` met à l'échelle sur les axes du **monde**, pas sur ceux de l'objet : les morceaux
  de trace sortaient en pointillés et les bancs rocheux étaient aplatis selon la verticale au lieu de
  leur litage. C'est `scaled_local()` qu'il faut.

### La double barre

Sur FREERIDE_5, à **9 s** de rush, le skieur ne traverse pas une barre : il en saute **deux à la
suite**, avec une touche de neige entre les deux, et il **freine fortement** avant. Découpé image
par image (`scratchpad/jump/`, planches de contact) :

| | |
|---|---|
| freinage en dérapage, gros nuage de poudreuse | 9,6 → 10,3 s (**0,7 s**) |
| premier vol | 10,38 → 10,74 s (**0,36 s**) |
| touche de neige | 10,74 → 10,82 s (**0,10 s**) |
| deuxième vol | 10,82 → 10,92 s (**0,16 s**) |
| réception écrasée | à partir de 10,92 s |

**Il a fallu entailler la barre dans le MNT** (`test/tools/barre.py`). Pourquoi : les deux ressauts
font 3,4 m et 1,1 m, séparés d'une vire de 2,5 m — or la surface de **neige** qu'on tire du LIDAR
(fermeture morphologique à 7 m puis trois passes binomiales, `export3.py`) lisse par construction
tout ce qui est plus petit que la dizaine de mètres. C'est ce qui enlève le bruit de mesure sous la
neige, et ça enlève les ressauts avec. Vérifié en balayant toute la face : les seules pentes qui
dépassent 55° sur 12 m sont les **grandes parois de 60 à 70°**, où un skieur ne passe pas ; partout
ailleurs la face lissée n'a plus une seule cassure franche à l'échelle d'un saut. Deux essais
l'avaient montré avant :

- sur la grande barre du bas (x −9, z 436, 60-64°), le skieur saute bien, mais il atterrit au milieu
  d'un **pierrier** entièrement peint en rocher — exactement le reproche « on dirait qu'il ski dans
  les cailloux » ;
- sur la plus forte cassure que la ligne croise en neige (51° à x −24, z 247), il n'y a **aucun nez
  visible** : un simple roulis blanc, et le saut semble sorti de nulle part.

La barre est donc écrite **dans le `.f32`**, et non posée côté Godot : comme ça le terrain, le
générateur de la ligne et le placement des rochers voient tous les trois la même chose, et la barre
se couvre toute seule de parois à facettes (> 46°) et de rocher peint (> 54°) par les règles déjà en
place. Le profil, le long de la descente :

- au-dessus, le terrain est **relevé** de D1 + D2 et ce relèvement s'efface sur 80 m vers le haut —
  ce qui donne le bombé convexe qui annonce la barre, au lieu d'un mur surgi de la pente ;
- **première marche** 3,4 m en 1,5 m ; **vire** de 2,5 m, *aplatie* (on lui rajoute exactement ce que
  le terrain perd, sinon elle tombe à 45° et les deux marches se fondent en une seule rampe) ;
  **deuxième marche** 1,1 m plus le rattrapage de la vire ;
- en dessous, le terrain d'origine, inchangé ;
- 36 m de large, fondue sur ses bords — et surtout **elle serpente** (±3,9 m) et sa hauteur varie le
  long d'elle (±26 %) : une barre tirée au cordeau est ce qui trahit le plus sûrement une barre
  fabriquée. La phase est calée pour qu'elle soit un peu **plus haute là où il saute**.

Côté ligne (`lignes.py`), une machine à états : *ski → freinage → vol 1 → touche → vol 2 → ski*,
déclenchée par la première pente > 50° rencontrée après 5 s. Pendant le freinage la vitesse tombe de
55 % ; en vol, les points suivent la **corde décollage-réception** bombée du `pop` du jeu, et leurs
indices sont écrits dans `lignes.json` (`air`). Côté Godot, `ski_run.set_air_spans()` les traduit en
fractions de courbe (un point sur deux cents n'est pas une fraction sur deux cents : les points sont
à pas de temps constant, donc d'autant plus écartés qu'il va vite, et un saut est justement l'endroit
où il va le plus vite), avec un demi-segment de marge de chaque côté — sans elle il passait une ou
deux images en pose de ski à quatre mètres du sol. `current_jump()` est la **convention du jeu** :
`AthleteModel` la lit déjà pour poser le skieur en l'air (jambes ramassées, bâtons rentrés, aucun
planter) et `PathSubject._in_air()` pour cesser de coller le modèle au sol. On y ajoute la réception
écrasée (`tuck` à 0,95 pendant une demi-seconde) et l'absence de sillon sous le saut.

**Vérifié au rendu** : 0,40 s de vol, 0,10 s de touche, 0,20 s de vol (le pas de 0,05 s du
générateur arrondit vers le haut), jusqu'à **4,1 m au-dessus du sol**, à 9,2 s de descente contre
9 s sur le rush.

**Le départ de FREERIDE_5 a été redescendu** de la crête (x 8, z 12) à l'épaule (x −70, z 170). De la
crête, la ligne mettait 30 s à atteindre quoi que ce soit de raide, soit le double de ce que durent
les rushs. On garde donc le **temps mesuré**, qui est ce qu'on sait, plutôt qu'un point de départ
estimé — et la position latérale de la ligne reste, comme avant, à confirmer par celui qui a filmé.

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

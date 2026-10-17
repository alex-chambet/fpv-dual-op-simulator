# Mouvements

Le troisième onglet du menu *Jouer*, à côté d'*Entraînement* et de *Bac à sable*. Un exercice de mouvement, c'est
**une seule figure de drone, répétée du début à la fin**, autour d'un sujet qui ne fait rien d'autre qu'avancer tout
droit. Une session d'entraînement cherche à ressembler à un tournage ; un exercice cherche l'inverse : enlever tout ce
qui n'est pas le geste à apprendre.

Chaque carte montre la figure dessinée, et la page de réglages la montre **en vol, en boucle** : ce n'est pas une vidéo
ni un schéma, c'est la trajectoire que le planificateur va réellement voler, replanifiée quand on change de niveau
(`ui/movement_preview.gd`).

## Les cinq figures

Le menu les range **de la plus simple à la plus difficile** (`ScenarioMatrix.drills_by_difficulty()`),
et les pastilles de chaque carte donnent la même note.

| Figure | Ce que fait le drone | Ce que fait le cadreur |
| --- | --- | --- |
| ●●○○○ **Orbite** (`orbit`) | Un cercle autour du sujet, à distance constante. | Pan régulier, sans à-coup, sur tout le tour. C'est la figure dont les autres découlent. |
| ●●●○○ **Reveal tilt bas vers haut** (`reveal_up`) | Part haut et tout près, caméra plongeant à pic sur le sol, puis descend en s'éloignant jusqu'à passer devant le sujet. | Un seul axe à nouveau, mais le tilt, du sol jusqu'à l'horizon — et il faut arriver à l'heure. |
| ●●●●○ **Flyby par derrière** (`pass_behind`) | Arrive de loin, décalé en arrière et sur un côté, rattrape le sujet **en passant derrière lui**, ressort de l'autre côté et le suit latéralement ; puis recule et repart dans l'autre sens. | Pan rapide avec une inversion au moment du passage, et de longues portions tranquilles de part et d'autre. |
| ●●●●○ **Spirale vers l'intérieur** (`spiral_in`) | Le même cercle que l'orbite, mais le rayon se resserre tour après tour, puis ressort pour recommencer. | Aussi rapide, mais le pan **accélère en continu** : plus dur à anticiper que l'inversion unique du flyby. |
| ●●●●● **Vertical tilt** (`vertical_pass`) | Passe au-dessus du sujet sur une trajectoire presque perpendiculaire à sa course : il entre un peu par l'arrière et ressort un peu en avant, puis revient par un grand demi-cercle. | Pan et tilt à fond en même temps, juste à la verticale : la seule figure où les deux axes travaillent ensemble.

Cette note (`ScenarioMatrix.DRILL_TIER`) n'est **pas** `DroneDifficulty.MOVEMENT_TIER` : celle-là pondère
aussi le tirage au sort d'une session d'entraînement, où une orbite compte parmi les mouvements durs. Ici
il faut classer cinq figures difficiles les unes par rapport aux autres, et l'orbite est la plus simple
des cinq.

Un exercice **n'a pas de survol de reconnaissance** avant le départ (`CourseIntro.wanted`) : il n'y a pas
de parcours à montrer, le sujet va tout droit, et ce qu'il faut avoir vu c'est la figure du drone — que la
page de réglages joue déjà. Le décompte démarre tout de suite.

## La difficulté : d'abord la vitesse du sujet

Le niveau (1 à 6) agit comme partout ailleurs — distance au sujet, axes à gérer, rapidité de la figure
(voir [ajouter_un_sport.md](ajouter_un_sport.md)). Mais la vraie progression d'un exercice, c'est la ligne
**Vitesse du sujet** (`ScenarioMatrix.DRILL_STEPS`) :

1. **Sujet immobile** — il ne reste que la figure du drone à suivre.
2. **Marche** (5 km/h) — la figure se décale lentement, il faut recadrer en continu.
3. **Course** (16 km/h) — la figure et le sujet bougent tous les deux, à des vitesses différentes.
4. **Rapide** (32 km/h) — le drone doit rattraper le sujet pendant la figure.

La figure elle-même ne change pas d'un pas à l'autre : à chaque vitesse, le drone décrit exactement la même trajectoire
autour du sujet. Seul le décor défile plus ou moins vite.

Chaque combinaison (figure × vitesse × niveau × optique) a son propre meilleur score
(`SessionConfig.scenario_id()` → `drill_<figure>_v<pas>_L<niveau>`).

## Comment c'est construit

### La figure (`scenarios/movement_planner.gd`)
Les quatre nouvelles figures sont des `movement` comme les autres, avec leur entrée dans `ScenarioMatrix.MOVEMENTS`
(marquée `drill: true`, donc **jamais tirée au hasard** pour une session d'entraînement) et dans
`DroneDifficulty.MOVEMENT_TIER` / `PAN_CAP_FACTOR` / `TILT_CAP_FACTOR`.

Une figure d'exercice est découpée en phases, chacune un fondu quintique (`_sstep`) : elle part et arrive à l'arrêt,
donc les raccords entre phases **et le retour au début de la boucle** sont lisses quelles que soient les dimensions.
`_drill_setup()` choisit ces dimensions et la période :

- la période est assez longue pour qu'aucune phase ne demande plus d'accélération que le niveau n'en autorise
  (`5,77 × distance / durée²` pour une translation, `v² / r` pour un demi-cercle de retour) ;
- elle est ensuite ajustée pour qu'un **nombre entier de figures** tienne dans la durée du run — la dernière n'est
  jamais coupée en deux.

À niveau 3, cela donne 2 à 5 répétitions par exercice.

### Le sujet (`scenarios/subjects/archetypes/cible.gd`, archétype `CIBLE`)
Un coureur qui avance tout droit à vitesse constante, sur la fiche `catalogue/cible.tres` (`in_menu = false` : elle
n'apparaît pas dans la liste des sports). Deux particularités viennent du pas « sujet immobile » :

- **`floor_speed()`** rend la vitesse demandée telle quelle. Le plancher habituel (0,05 m/s) ferait marcher un sujet
  censé être arrêté — et le ferait croire au planificateur.
- **`drone_path_samples`** (nouveau paramètre commun) fixe le nombre de points du vol. D'habitude il vient de la
  longueur du chemin ; ici le chemin fait moins d'un mètre, donc c'est la durée du run qui décide (≈ 10 points par
  seconde, la densité pour laquelle le planificateur est fait — beaucoup plus serait pire, voir le commentaire dans
  `cible.gd`).

La zone de jeu renvoyée par `generate()` fait 420 m de côté quelle que soit la longueur du chemin : le terrain est
construit autour de la figure, pas autour du sujet.

### Le terrain (`scenarios/environments/env_drill.gd`, style `drill.tres`)
Une prairie vallonnée, mais les décors sont placés pour **ne jamais pouvoir passer entre la caméra et le sujet** :
perdre le sujet derrière un arbre pendant un exercice serait du bruit, pas de la difficulté.

- un couloir dégagé le long du chemin du sujet, aussi large que la figure va loin (mesuré sur la trajectoire planifiée) ;
- des arbres et des rochers **en dehors** de ce couloir, pour la parallaxe qui dit à l'œil à quelle vitesse le drone va ;
- à l'intérieur, seulement des buissons et des pierres de moins de 80 cm, sous toutes les lignes de visée.

Mesuré sur les 20 combinaisons figure × vitesse : **0 % du temps le sujet est caché**.

### Le terrain reste plat : une gimbal tient l'horizon

Le sol vallonné de `drill` ne dépasse jamais une fraction de degré en travers du champ (mesuré : 0,3° en moyenne,
0,8° au pire, sur les cinq figures). C'est volontaire.

Le *reveal tilt bas vers haut* a d'abord été posé sur une pente de 24 % : c'est le seul terrain sur lequel la caméra
doit vraiment relever **au-dessus** de l'horizon pour trouver un sujet posé dessus. Mais une gimbal garde l'horizontale
par principe — c'est tout son objet —, donc sur une pente elle filme un horizon en travers du cadre pendant toute la
session, ce qui ressemble exactement à une gimbal en panne. La pente a été retirée.

La figure n'y a rien perdu : son amplitude de tilt vient de sa propre géométrie (haut et tout près, caméra à pic, vers
bas et loin, caméra à l'horizontale), et elle demande sur le plat 15,8 à 17,3 °/s de tilt contre 11,7 à 12,8 °/s de
pan — toujours la plus « tilt » des cinq, et même un peu plus qu'avec la pente.

## Ajouter une figure

1. Une entrée dans `ScenarioMatrix.MOVEMENTS` avec `"drill": true`, et son id dans `DRILL_MOVEMENTS`.
2. Sa note dans `ScenarioMatrix.DRILL_TIER` (le menu s'en sert pour le rang et pour les pastilles),
   son rang dans `DroneDifficulty.MOVEMENT_TIER` et son id dans `DroneDifficulty.DRILL_MOVEMENTS`.
3. `REF_DISTANCE`, `CENTER_SIGMA`, `SWAY_FACTOR`, `PAN_CAP_FACTOR`, `TILT_CAP_FACTOR` dans `MovementPlanner`, et son id
   dans `MovementPlanner.DRILLS`.
4. Ses dimensions dans `MovementPlanner._drill_setup()` (`legs` = les translations, `turns` = les demi-cercles) et sa
   géométrie dans le `match movement` de `_build()`.
5. Son texte dans `MainMenu.DRILL_LABELS`, et sa vignette : voir plus bas.

### Refaire les vignettes des cartes
Les images `ui/thumbs/drill_<id>.png` sont rendues depuis l'aperçu lui-même, donc elles ne peuvent pas mentir sur la
figure. Un script `SceneTree` qui, pour chaque id : crée un `MovementPreview` de 640×360, appelle
`show_movement(id, 3)`, fige `_t`, redessine `_whole` en vif, et enregistre `_vp.get_texture().get_image()`. Lancer
ensuite `--import` pour que Godot importe les PNG.

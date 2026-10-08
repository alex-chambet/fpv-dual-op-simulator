# Ajouter un sport en moins de 5 minutes

Un sport est une **fiche de données** (`.tres`) : aucun code à écrire. La fiche choisit
- un **archétype de mouvement** (la façon dont le sujet se déplace),
- un **environnement** (le décor),
- des **paramètres** qui surchargent les valeurs par défaut de l'archétype,
- l'apparence du **placeholder** (capsule colorée, vélo, cheval…),
- les **mouvements de drone** conseillés et la **difficulté de base**.

Dès que la fiche est enregistrée, le sport apparaît dans le menu (liste « Sport », filtres) et dans la
génération aléatoire. Les fiches sont dans `res://scenarios/subjects/catalogue/` (les sous-dossiers
sont lus aussi : vous pouvez ranger vos fiches comme vous voulez).

---

## En 5 minutes

1. Dans Godot, panneau **Système de fichiers** → `scenarios/subjects/catalogue/`.
   Clic droit sur une fiche **proche de votre sport** → **Dupliquer…** → nommez le fichier
   `mon_sport.tres`.
2. Double-clic sur `mon_sport.tres` : tout se règle dans l'**Inspecteur**.
   - `id` : identifiant unique (minuscules, chiffres, `_`). **Ne le changez plus ensuite** : les
     sessions enregistrées et les scores le gardent.
   - `display_name`, `category` (le groupe du menu), `description`.
   - `archetype` : liste déroulante. `environment` : champ avec suggestions (vous pouvez aussi saisir un
     tag à vous, voir « L'environnement »).
   - `overrides` : les paramètres à changer (voir les tableaux plus bas). Ce que vous ne listez pas
     garde la valeur par défaut de l'archétype.
   - `subject_size` (taille en mètres ; 0 = taille typique de l'archétype), `placeholder_shape`,
     `placeholder_gear`, couleurs.
   - `recommended_movements` : les mouvements de drone qui conviennent (`pursuit`, `lateral`,
     `frontal`, `orbit`, `reveal`, `flyby`, et les figures expert `approach_orbit`, `dive`, `choreo`).
     Vide = tous.
   - `base_difficulty` : 1 (facile à cadrer) à 5 (très difficile).
3. **Ctrl+S**, puis lancez le jeu (**F5**).
4. Dans le menu, panneau **Training session** : choisissez votre sport dans la liste « Sport »
   (ou filtrez par catégorie / difficulté / mouvement de drone), puis **Start generated session**.
5. Si quelque chose cloche, le menu affiche `Catalogue: N sports, W warning(s)` et la console
   (panneau « Sortie ») détaille le problème : archétype ou paramètre inconnu, mouvement inconnu,
   difficulté hors de 1..5, id en double…

Pour régler un sport : lancez-le plusieurs fois, ajustez `overrides`, rechargez. La durée de la course
se règle avec `duration` (en secondes) : le trajet s'allonge ou se raccourcit tout seul. La vitesse se
règle avec `speed_min` / `speed_max`.

---

## Les archétypes

| Archétype | Mouvement | Exemples |
|---|---|---|
| `GLISSE_PENTE` | descente avec virages en S, traces et poudreuse | ski, snowboard, luge |
| `COURSE_SOL_CYCLIQUE` | allure cyclique (jambes, bras) sur un chemin sinueux ; la vitesse baisse dans les virages | course, trail, ski de fond, escalade, patinage, cheval au galop |
| `VEHICULE_ROUTE` | suit une route, vitesse stable, freine dans les virages (lacets ou courbes) | voiture, moto, vélo de route, kart, trottinette |
| `TOUT_TERRAIN_ERRATIQUE` | vitesse et trajectoire irrégulières, sauts aléatoires | VTT, motocross, rallye |
| `EAU_SURFACE` | grandes courbes, oscillation latérale, tangage et roulis sur l'eau | kayak, surf, wakeboard, voile, aviron, paddle |
| `AIR_LIBRE` | trajectoire 3D lente et ample, changements d'altitude, descente | parapente, wingsuit, parachute |
| `STOP_AND_GO_ZONE` | déplacements dans une zone délimitée : accélérations brusques, arrêts, directions imprévisibles | football, rugby, basket, tennis, hockey |
| `SAUT_ACROBATIQUE` | élan, phase aérienne (rotation, saltos), réception, plusieurs sauts | freestyle, saut à ski, skate, BMX, saut d'obstacles |

### Paramètres communs (tous les archétypes)

| Paramètre | Unité | Rôle |
|---|---|---|
| `subject_size` | m | taille typique du sujet de l'archétype (utilisée quand le champ `subject_size` de la fiche vaut 0 ; voir « Le placeholder ») |
| `speed_min`, `speed_max` | m/s | bornes de la vitesse nominale (le minimum sert par exemple dans les virages serrés) |
| `speed_variability` | 0 à 1+ | oscillation de la vitesse dans le temps, en fraction de la moitié de l'écart `speed_max − speed_min` |
| `turn_frequency` | pour 100 m | changements de direction par 100 m de trajet (interprétation propre à chaque archétype, voir plus bas) |
| `lateral_amplitude` | m | amplitude latérale de la trajectoire (demi-largeur du slalom, d'une jambe de lacet, de la zone…) |
| `jump_frequency` | pour 100 m | sauts par 100 m de trajet (0 = aucun) |
| `jump_height`, `jump_length` | m | hauteur d'un saut au-dessus de la corde décollage–réception, et sa longueur |
| `jump_visual` | texte | `ramp` (kicker), `obstacle` (barre), `none` |
| `flips`, `spin_deg` | tours, ° | saltos et rotation pendant un saut |
| `cadence` | Hz | cycles par seconde du mouvement cyclique (foulée, coup de pagaie, galop…) ; 0 = pas cyclique |
| `cadence_coupling` | 0 à 1 | 0 = cadence constante, 1 = proportionnelle à la vitesse |
| `lean_max_deg`, `lean_gain` | °, – | inclinaison maximale dans les virages et sa force |
| `duration` | s | **durée visée de la course** (55 s par défaut). La longueur du trajet est ajustée automatiquement pour que la course dure ce temps |
| `path_length` | m | longueur imposée du trajet. À 0 (par défaut), elle est calculée à partir de `duration`. Sert surtout à figer un parcours précis |
| `sample_step` | m | espacement des points de la trajectoire |
| `cornering_accel` | m/s² | accélération latérale pour freiner dans les virages ; 0 = pas de freinage |
| `drone_distance_scale` | × | échelle de toutes les distances du drone (parapente : 4, grimpeur : 0,35) |
| `drone_min_height` | m | hauteur minimale du drone au-dessus du sol |
| `drone_relative_height` | vrai/faux | vrai : hauteur du drone relative au sujet (sujets en l'air) |

### Paramètres propres à chaque archétype (valeur par défaut)

| Archétype | Paramètres spécifiques |
|---|---|
| `GLISSE_PENTE` | `weave_ratio` 0,25 et `weave_period` 314 (modulation lente de l'amplitude), `gates` vrai (portes de slalom), `leaves_tracks` vrai (traces), `spray` vrai (poudreuse) |
| `COURSE_SOL_CYCLIQUE` | `wiggle_ratio` 0,57 et `wiggle_period_ratio` 0,41 (petites ondulations), `bob` 0,05 m (rebond), `limb_swing` 0,8 rad (balancement des membres) |
| `VEHICULE_ROUTE` | `layout` : `switchback` (lacets : nombre de jambes = `turn_frequency` × `path_length` / 100, demi-longueur d'une jambe = `lateral_amplitude`) ou `winding` (route sinueuse) ; `turn_radius` 12,5 m (rayon des lacets) |
| `TOUT_TERRAIN_ERRATIQUE` | `irregularity` 0,6 (0 à 1), `bump` 0,07 rad (secousses du corps) |
| `EAU_SURFACE` | `wave_period` 3,2 s, `wave_roll_deg` 6°, `wave_heave` 0,12 m, `surge` 0 à 1 (pulsation de la vitesse à la cadence : aviron, pagaie), `osc_amplitude` 0,8 m et `osc_period` 18 m (oscillation latérale) |
| `AIR_LIBRE` | `altitude` 180 m, `altitude_variation` 40 m, `altitude_period` 700 m, `descent_per_100m` 3 m (perte d'altitude : 28 pour un wingsuit, 80 pour un parachute) |
| `STOP_AND_GO_ZONE` | `zone_width` 60 m, `zone_length` 100 m, `corner_radius` 2 m, `pause_probability` 0,35, `burst_ratio` 0,8 (vitesse d'une pointe en fraction de `speed_max`), `bob`, `limb_swing` |
| `SAUT_ACROBATIQUE` | `jump_count` 3, `approach_length` 80 m (élan), `rollout_length` 45 m (distance entre une réception et le saut suivant), plus `jump_length`, `jump_height`, `flips`, `spin_deg` |

`turn_frequency` selon l'archétype : `GLISSE_PENTE` = demi-périodes du slalom ; `COURSE_SOL_CYCLIQUE`
= ondes de la trajectoire ; `VEHICULE_ROUTE` = jambes de lacets (`switchback`) ou ondes de la route
(`winding`) ; `STOP_AND_GO_ZONE` = un changement de direction tous les `100 / turn_frequency` mètres ;
`AIR_LIBRE` = ondes de la trajectoire (valeurs très basses : 0,12 à 0,7).

### Niveau de session

Le niveau (1 à 5, plus le niveau 6 **Expert**) choisi dans le menu **ne change pas le sujet** : sa vitesse, ses virages et ses sauts
sont ceux de la fiche, et la durée de la course ne dépend pas du niveau. Seul le vol du drone change, et il
reste **toujours fluide** (accélérations limitées, pas de changement de direction brusque). Trois choses font
la difficulté pour le cadreur :

1. **Le mouvement du drone** (voir plus bas) : un suivi latéral est plus simple qu'une orbite.
2. **Les axes à gérer** : aux niveaux 1 et 2 le drone ne demande qu'un axe à la fois (pan **ou** tilt) ;
   à partir du niveau 3, pan **et** tilt ensemble, de plus en plus amples.
3. **La proximité** : plus le drone est près du sujet, plus le sujet traverse vite l'image. Le drone est
   loin au niveau 1 (distance ×1,45) et de plus en plus près jusqu'au niveau 5 (×0,68).

| Niveau | Distance | Axes | Orbite (1 tour) | Balayage dévoilement / survol (minimum) |
|---|---|---|---|---|
| 1 | ×1,45 | pan **ou** tilt | 30 s | 9 s |
| 2 | ×1,22 | pan **ou** tilt | 24 s | 8 s |
| 3 | ×1,00 | pan + tilt | 19 s | 7 s |
| 4 | ×0,82 | pan + tilt | 15 s | 6 s |
| 5 | ×0,68 | pan + tilt | 12 s | 5 s |
| 6 Expert | ×0,56 | pan + tilt | 8 s | 4 s |

**Niveau 6 – Expert.** Le drone vole comme un drone FPV de cinéma rapide : accélération jusqu'à 9 m/s²
(6 au niveau 5), jusqu'à environ 140 km/h sur les longues lignes, orbites d'un tour en 8 s au plus près du
sujet. Tiré « au hasard », le mouvement est une **figure expert** (voir les mouvements plus bas), sinon une
orbite ou un survol. Les figures enchaînent des phases très différentes : le sujet passe de minuscule
(drone à 25 - 50 m) à plein cadre, le pan et le tilt changent sans cesse de sens et de vitesse. Mesuré sur
les 5 sports du menu : pan de 40 à 70°/s (95e centile, pointes de 90 à 150°/s pendant les croisements), tilt
jusqu'à -70° pendant les plongeons, contre 35 à 58°/s de pan au niveau 5. Le drone reste fluide (pas de
changement brusque) et ne touche ni le sol, ni les arbres. Le niveau Expert n'est jamais tiré par
`Aléatoire` : il se choisit exprès.

Dans un dévoilement ou un survol, le drone passe devant puis derrière le sujet : l'approche, le balayage et le
retour durent chacun **assez longtemps pour ne jamais dépasser l'accélération maximale du niveau** (un drone
éloigné, qui a plus de chemin à faire, met plus longtemps ; le balayage est plus long que le minimum du
tableau si besoin). Les passages sont au nombre de 1 aux niveaux 1-2, 2 aux niveaux 3-4 et 3 au niveau 5 ; si
la course est trop courte pour les contenir, ils sont un peu plus petits, puis moins nombreux. Les obstacles
d'un dévoilement sont posés sur la ligne de visée, jamais là où le drone ou le sujet passent à un autre moment
de la course (route en lacets).

**Garde-fous.** Avant chaque session, le planificateur vérifie le vol (valeurs dans
`scenarios/drone_difficulty.gd`) : vitesse de pan et de tilt du sujet dans l'image (95e centile, par exemple
16°/s en pan au niveau 1 contre 60°/s au niveau 5), accélération du drone (3,5 m/s² au niveau 1, 6 m/s² au
niveau 5). Si une limite est dépassée, il éloigne le drone (vitesse dans l'image), lisse davantage la
trajectoire, ralentit l'orbite ou les balayages et, en dernier recours, atténue le balancement du drone,
jusqu'à la respecter. Un sport qui bouge très vite ou en lacets serrés (voiture dans des épingles) verra donc
le drone plus loin, ou un peu plus calme, que prévu.

`Auto` prend la `base_difficulty` de la fiche comme niveau. `Aléatoire` tire un niveau de 1 à 5, puis un
mouvement d'autant plus difficile que le niveau est élevé (jamais une figure expert).

---

## Le placeholder (aucun modèle 3D)

`subject_size` est la **plus grande dimension** du placeholder, en mètres (personne 1,8 ; voiture 4,2).
À 0, la fiche prend la taille typique de son archétype (paramètre `subject_size` de l'archétype) :
1,8 m pour `GLISSE_PENTE`, `COURSE_SOL_CYCLIQUE`, `STOP_AND_GO_ZONE` et `SAUT_ACROBATIQUE`, 2 m pour
`TOUT_TERRAIN_ERRATIQUE`, 3 m pour `EAU_SURFACE`, 4,2 m pour `VEHICULE_ROUTE`, 8 m pour `AIR_LIBRE`.

| `placeholder_shape` | Rendu |
|---|---|
| `person` | personne debout (tronc, tête, bras et jambes qui bougent) |
| `person_lying` | personne allongée (luge : sur le dos, pieds devant ; wingsuit : tête devant) |
| `box` | boîte, ou voiture avec `placeholder_gear = car` |
| `capsule`, `sphere` | formes simples |

| `placeholder_gear` | Ajoute |
|---|---|
| `none` | rien |
| `skis`, `snowboard`, `sled` (avec `person_lying`) | équipement de neige |
| `skates`, `wheels`, `skateboard`, `scooter` | patins, rollers, skate, trottinette |
| `wakeboard`, `surfboard`, `sup` | planches |
| `bike`, `moto`, `kart` | deux-roues (roues qui tournent), kart avec pilote |
| `horse` | cheval avec cavalier (pattes qui galopent à la `cadence`) |
| `kayak`, `scull`, `sail` | bateaux (pagaie, avirons, voile) |
| `canopy`, `wings` | voile de parapente / parachute, ailes de wingsuit |
| `car` (avec `box`) | voiture |

`placeholder_color` colore le corps ou le véhicule ; `placeholder_accent` la tête, le casque ou l'équipement.

---

## L'environnement

`environment` est un **tag**. Les tags `neige`, `route_montagne` et `foret` ont un constructeur dédié ;
tous les autres utilisent le constructeur générique configuré par un fichier de style
`res://scenarios/environments/styles/<tag>.tres`.

| Tag | Décor |
|---|---|
| `neige` | pente neigeuse, arbres, rochers, portes de slalom (`env_overrides` : `slope`, pente de 0,3 par défaut) |
| `route_montagne` | route de montagne posée sur le trajet, bornes, pins, rochers, **tunnel** si le trajet a une partie droite de 66 m ou plus |
| `foret` | forêt dense et sentier (`env_overrides` : `trail_clearance`, `drone_clearance`, `background_trees`) |
| `glace` | patinoire : bandes, lignes, tribunes ; les joueurs servent d'obstacles |
| `stade` | pelouse, lignes de terrain, tribunes |
| `salle` | salle de sport : parquet, lignes de basket, murs |
| `court` | court de tennis, clôture |
| `piste_urbaine` | asphalte et immeubles |
| `terrain_vague` | sol bosselé et blocs |
| `prairie` | prairie vallonnée et arbres |
| `falaise` | paroi raide (pour grimper) |
| `arete` | arête rocheuse et neigeuse |
| `eau_vive` | rivière avec rochers |
| `lac` | lac calme avec bouées |
| `mer` | mer ouverte |
| `ciel` | montagnes lointaines et nuages |
| *(tag inconnu)* | sol plat simple + quelques boîtes : le sport est testable immédiatement (`styles/generic.tres`) |

Pour les environnements génériques, `env_overrides` accepte `terrain_kind` (`flat`, `rolling`, `slope`,
`wall`, `ridge`, `river`, `mountains`, `water`), `slope`, `bump` et `river_half_width`.

**Ajouter un environnement** : dupliquez un fichier de `styles/` (par exemple `prairie.tres`), nommez-le
avec le nouveau tag (`mon_decor.tres`) et modifiez les couleurs du ciel, du sol, le brouillard, le type de
terrain, les marquages et les objets (`prop_kind`, `occluder_kind`). Mettez ensuite ce tag dans
`environment` d'une fiche : le champ de l'Inspecteur propose les tags connus mais accepte n'importe quel
texte, il suffit d'y saisir votre tag.

---

## Les mouvements de drone

| Mouvement | Ce que fait le drone | Difficulté |
|---|---|---|
| `lateral` suivi latéral | vole à côté du sujet, en avançant et reculant doucement | ●○○○○ |
| `pursuit` poursuite arrière | suit le sujet par l'arrière | ●○○○○ |
| `frontal` face au sujet | recule devant le sujet en le filmant de face | ●●○○○ |
| `reveal` dévoilement | le sujet est caché derrière une barrière, puis découvert quand le drone la dépasse | ●●●○○ |
| `orbit` orbite | tourne autour du sujet pendant qu'il avance | ●●●●○ |
| `flyby` survol rapide | croise le sujet de près, d'un côté à l'autre | ●●●●● |
| `approach_orbit` entrée + orbite | s'éloigne loin et haut, revient à toute vitesse et s'enroule autour du sujet (1 tour à 1 tour 3/4, en montant et descendant), puis repart chercher une autre entrée | Expert |
| `dive` plongeon | monte haut devant le sujet, plonge sur lui, le frôle à basse altitude et remonte derrière, en alternant les côtés | Expert |
| `choreo` chorégraphie expert | enchaîne les figures : entrée + orbite, plongeon, croisement face à face (le drone attend loin devant et fonce sur le sujet), spirale montante ; jamais deux fois la même à la suite | Expert |

Les figures expert (`scenarios/movement_planner.gd`, `_build_figures`) sont décrites autour du sujet
(angle, distance, hauteur) par des segments parcourus à la vitesse du niveau, puis lissés dans le temps :
le drone ne change jamais brusquement de direction ni de vitesse. Le planificateur vérifie ensuite
l'accélération, la vitesse maximale (40 m/s), la vitesse de pan / tilt et, pour les phases lointaines, que
le relief ne cache pas le sujet (il rapproche le drone sinon). Elles peuvent aussi être choisies à un niveau
plus bas : elles sont alors plus lentes et plus lointaines.

Tous ces vols sont dessinés en secondes (balancements lents de quelques degrés vus du sujet, courbes
quintiques), autour d'une copie lissée de la trajectoire du sujet : le drone ne reproduit pas les
secousses, les virages serrés ni les freinages du sujet, il les suit avec un léger retard (le sujet dérive
un peu dans l'image, ce qui fait partie du travail du cadreur).

`recommended_movements` limite les mouvements tirés au hasard pour ce sport (par exemple, pas de
`frontal` pour un sujet qui avance très lentement si cela n'a pas de sens pour vous).

---

## Exemple : ajouter le squash

Dupliquez `tennis.tres` en `squash.tres` et remplacez :

```
id = "squash"
display_name = "Squash"
category = "Collectifs / terrain"
description = "Joueur de squash dans une cage vitrée : espace très réduit, accélérations constantes."
archetype = "STOP_AND_GO_ZONE"
overrides = {
"burst_ratio": 0.85,
"cadence": 2.8,
"corner_radius": 1.2,
"drone_distance_scale": 0.5,
"pause_probability": 0.15,
"speed_max": 5.5,
"speed_min": 0.8,
"turn_frequency": 12.0,
"zone_length": 9.75,
"zone_width": 6.4
}
environment = "salle"
base_difficulty = 5
```

Enregistrez, relancez : « Squash » est dans la catégorie « Collectifs / terrain ».

---

## Bon à savoir

- **Id** : ne le changez pas après coup ; un doublon est signalé dans la console.
- **Replays** : chaque session enregistrée embarque une copie de la fiche. Modifier ou supprimer une
  fiche ensuite ne casse pas les anciens replays.
- **Durée des courses** : `duration` (55 s par défaut) est respectée à quelques pour cent près pour
  tous les archétypes sauf `SAUT_ACROBATIQUE`, dont la durée vient du parcours lui-même
  (`approach_length` + `jump_count` × (`jump_length` + `rollout_length`), divisé par la vitesse) :
  ajoutez des sauts ou allongez l'élan pour allonger la course. Si vous imposez `path_length`, c'est la
  longueur qui commande et la durée en découle. Visez 40 à 70 s ; une discipline naturellement brève
  (saut à ski, environ 20 s) est acceptable. Le HUD affiche le temps écoulé et la progression en % :
  durée totale ≈ temps ÷ progression.
- **Sujet toujours seul** : un sport collectif est représenté par un seul joueur ; les autres joueurs
  n'existent que comme obstacles sur la ligne de vue.
- **Tester vite** : dans le menu, choisissez votre fiche dans « Sport », un « Drone movement » et un
  « Session level » précis. Sur l'écran de résultat, « Next random session » (touche N) garde ces
  choix verrouillés et ne tire au hasard que le reste.
- **Roues** : les roues (vélo, moto, voiture, kart…) tournent à la vitesse du sujet ; leur taille vient
  du placeholder, il n'y a rien à régler.

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
| `FREERIDE` | freeride sur une grande face raide (environnement `freeride`) : la ligne est choisie barre rocheuse par barre rocheuse (sauter une falaise ou passer par un couloir) ; grandes courbes, moyennes, tout-droit ou virages serrés techniques entre les barres ; vitesse « skiée », jamais imposée : la pente, le frottement dans la poudreuse et l'air agissent en permanence, et le skieur ne perd de la vitesse qu'en dérapant, skis en travers (en fin de virage, dans un virage de contrôle lancé quand il va plus vite qu'il ne le veut ou après une réception, au-dessus de chaque falaise (presque à l'arrêt au-dessus d'un départ technique — bord en biais, grosse barre —, un simple contrôle au-dessus d'un départ facile qu'il prend avec de la vitesse), quand la courbe est trop serrée pour sa vitesse, et à l'arrêt), à la réception d'un saut ou quand la pente s'adoucit ; un tout-droit accélère toujours ; le rythme de ses virages suit la pente, comme dans des runs filmés en FPV (environ 0,5-0,6 s par virage court et dérapé à 45°, 1 s vers 35°, 1,5-2 s en courbes plus coupées sur 25°, qui gardent la vitesse) ; il se grandit, skis à plat, à chaque changement de carre et plante le bâton aval juste avant, s'écrase au sommet du virage ; il se laisse tomber des barres presque sans pop et contrôle sa vitesse par un dérapage juste après chaque réception. Les skis se mettent en travers juste avant le freinage (profil skid du plan, avec un nuage de neige) pour que le cadreur puisse anticiper ; sauts là où le terrain s'éloigne plus vite que la trajectoire balistique ; deux figures par descente sur les plus grosses falaises (un 360 puis un backflip) | ski freeride |
| `DESCENTE` | course de descente : grandes courbes, virages serrés (souvent en S), schuss, sauts sur les cassures de pente ; vitesse calculée par un petit modèle physique (pente, frottement, air, freinage avant les virages serrés, vol balistique) | ski de descente |
| `CIBLE` | **sujet d'exercice** (onglet « Mouvements », environnement `drill`) : un coureur qui avance tout droit à vitesse constante — ou qui ne bouge pas du tout — sur un terrain dégagé. Il ne sert qu'à donner un point de mire à une figure de drone répétée ; sa vitesse est la difficulté de l'exercice. Voir [docs/mouvements.md](mouvements.md) | exercices de mouvement |
| `CIRCUIT` | **un tour complet d'un circuit fermé** (le Nürburgring Grand-Prix-Strecke, environnement `circuit`) : la trajectoire de course du circuit (large à l'entrée, à la corde, large à la sortie) et une vitesse qui sort d'une **simulation de tour** d'une vraie voiture — cercle d'adhérence avec appui aérodynamique, motricité puis puissance / vitesse, traînée, pente, et partage de l'adhérence entre virage et freinage. Le tour part et revient sur la ligne de départ, lancé. Voir [docs/circuit.md](circuit.md) | voiture de course |

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
| `drone_smoothing` | × | lissage supplémentaire autorisé au planificateur du drone (1 = budget normal) ; utile pour un sujet au trajet très tortueux |
| `drone_accel_relax` | × | combien de fois plus fort que la limite du niveau le drone de poursuite a le droit de travailler (1 = la limite du niveau). Une voiture de course freine à près de 2 g : son drone doit tirer autant pour rester avec elle, comme un vrai drone FPV de poursuite |
| `drone_path_samples` | points | nombre de points avec lesquels le vol du drone est planifié. 0 (par défaut) = déduit de la longueur du trajet du sujet. Ne sert qu'à un sujet qui ne bouge presque pas, dont le trajet est trop court pour échantillonner le vol : il faut alors viser une dizaine de points par seconde de course, la densité pour laquelle le planificateur est fait (beaucoup plus serait pire — il parcourt sa chronologie à 50 Hz) |
| `anticipation` | s | à quelle distance devant lui le sujet lit son propre trajet (0,5 par défaut). Un athlète animé prépare son prochain changement de direction ce temps-là à l'avance — c'est ce qui permet au cadreur de le voir venir (voir « Le skieur » plus bas). 0 = aucune anticipation |

### Paramètres propres à chaque archétype (valeur par défaut)

| Archétype | Paramètres spécifiques |
|---|---|
| `GLISSE_PENTE` | `weave_ratio` 0,25 et `weave_period` 314 (modulation lente de l'amplitude), `gates` vrai (portes de slalom), `leaves_tracks` vrai (traces), `spray` vrai (poudreuse), `rhythm` 0 (0 à 1 : rythme irrégulier des virages, qui se resserrent et s'espacent, avec une amplitude qui varie ; utilisé par le ski alpin), `grade_speed` 0 (0 à 1 : la pente règle la vitesse, plus vite sur les raides, plus lent sur les replats) |
| `COURSE_SOL_CYCLIQUE` | `wiggle_ratio` 0,57 et `wiggle_period_ratio` 0,41 (petites ondulations), `bob` 0,05 m (rebond), `limb_swing` 0,8 rad (balancement des membres) |
| `VEHICULE_ROUTE` | `layout` : `switchback` (lacets : nombre de jambes = `turn_frequency` × `path_length` / 100, demi-longueur d'une jambe = `lateral_amplitude`) ou `winding` (route sinueuse) ; `turn_radius` 12,5 m (rayon des lacets) |
| `TOUT_TERRAIN_ERRATIQUE` | `irregularity` 0,6 (0 à 1), `bump` 0,07 rad (secousses du corps) |
| `EAU_SURFACE` | `wave_period` 3,2 s, `wave_roll_deg` 6°, `wave_heave` 0,12 m, `surge` 0 à 1 (pulsation de la vitesse à la cadence : aviron, pagaie), `osc_amplitude` 0,8 m et `osc_period` 18 m (oscillation latérale) |
| `AIR_LIBRE` | `altitude` 180 m, `altitude_variation` 40 m, `altitude_period` 700 m, `descent_per_100m` 3 m (perte d'altitude : 28 pour un wingsuit, 80 pour un parachute) |
| `STOP_AND_GO_ZONE` | `zone_width` 60 m, `zone_length` 100 m, `corner_radius` 2 m, `pause_probability` 0,35, `burst_ratio` 0,8 (vitesse d'une pointe en fraction de `speed_max`), `bob`, `limb_swing` |
| `SAUT_ACROBATIQUE` | `jump_count` 3, `approach_length` 80 m (élan), `rollout_length` 45 m (distance entre une réception et le saut suivant), plus `jump_length`, `jump_height`, `flips`, `spin_deg` |
| `FREERIDE` | `cornering_accel` 12 (accélération latérale tenue sur les carres, au-delà il dérape), `drop_share` 0,65 (part des barres rocheuses sautées par une falaise, les autres passées par un couloir ou par le côté), `snow_friction` 0,07, `air_drag` 0,0035, `jump_height` 0,8 (pop au bord d'une falaise, m/s), `drone_min_height` 5 m. La durée vient de la face elle-même (environ 1 min 20 à 1 min 50) : `duration` n'allonge pas la ligne |
| `CIRCUIT` | `car` (identifiant de `RaceCarPhysics.CARS` : `gt3`, `gt4`, `tcr`, `historique`, `gt_route`, `safety`), `track_scale` 0,5 (échelle du circuit — longueurs **et** hauteurs, donc les pentes sont les vraies ; à mettre aussi dans `env_overrides`), `line_margin` 1,5 m (distance de la trajectoire aux lignes blanches), `line_swing` 1 (part de la largeur utilisée : 0 = l'axe), `grip` / `power` / `pace` (surchargent la voiture choisie : adhérence, kW, et à quel point le pilote est à la limite). La durée vient du circuit : `duration` ne l'allonge pas |
| `CIBLE` | `speed_min` = `speed_max` = la vitesse de l'exercice (0,01 m/s pour un sujet immobile), `duration` 90 s, `drone_path_samples` 800. Sa méthode `floor_speed()` rend la vitesse demandée telle quelle, au lieu du plancher habituel de 0,05 m/s qui ferait marcher un sujet censé être arrêté. Le terrain est construit sur une zone de 420 m quelle que soit la longueur du chemin |
| `DESCENTE` | `turn_frequency` 0,55 (part des virages parmi les éléments du tracé), `tight_turns` 0,4 (part des virages serrés, rayon 34 - 52 m ; les autres sont de grandes courbes de 110 - 190 m), `cornering_accel` 12 m/s² (accélération latérale max en virage), `air_drag` 0,0042 et `snow_friction` 0,035 (vitesse de pointe selon la pente), `jump_height` 1,2 (impulsion verticale au décollage, m/s), `duration` 98 s. Les sauts ne sont pas tirés au hasard : ils sont placés sur les cassures de pente du terrain (un replat qui se termine sur un mur raide), `turn_tightness` 0 (0 à 1 : tracé plus sinueux, rayons plus serrés, tout-droits plus courts, enchaînements de 3 à 4 virages serrés ; 1 pour le ski de descente, qui a aussi `tight_turns` 0,65 et `turn_frequency` 0,9) |

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
| `race_car` (avec `box`) | voiture de course GT : carrosserie basse, aileron arrière, lame avant, diffuseur, slicks, livrée deux tons avec un rond de numéro, feux arrière qui s'allument au freinage |
| `skis`, `snowboard`, `sled` (avec `person_lying`) | équipement de neige |
| `skates`, `wheels`, `skateboard`, `scooter` | patins, rollers, skate, trottinette |
| `wakeboard`, `surfboard`, `sup` | planches |
| `bike`, `moto`, `kart` | deux-roues (roues qui tournent), kart avec pilote |
| `horse` | cheval avec cavalier (pattes qui galopent à la `cadence`) |
| `kayak`, `scull`, `sail` | bateaux (pagaie, avirons, voile) |
| `canopy`, `wings` | voile de parapente / parachute, ailes de wingsuit |
| `car` (avec `box`) | voiture |

`placeholder_color` colore le corps ou le véhicule ; `placeholder_accent` la tête, le casque ou l'équipement.

### L'athlète animé

Un sujet `person` sans équipement, avec des `skis` ou avec un `bike` n'est pas une capsule : c'est le
mannequin articulé de la bibliothèque Quaternius (`scenarios/subjects/athlete_model.gd`). Le coureur
joue les animations de la bibliothèque (marche, trot, sprint) à son allure, le vététiste pédale ou
roue libre, et le skieur est posé **par le code**, image par image.

### Le skieur

Un skieur ne tient pas une position : il s'écrase dans le virage et se redresse pour en changer. Tout
est piloté par deux nombres — le virage qu'il est en train de faire (son inclinaison) et **celui qui
arrive**, lu `anticipation` secondes plus loin sur le trajet :

| Ce qu'il fait | Quand, par rapport au changement de carre |
|---|---|
| Les genoux traversent vers le nouveau virage | ~1 s avant |
| La main part en avant, le bâton se balance | 0,7 à 0,8 s avant |
| Il se grandit (extension, jambes tendues) | 0,4 à 0,8 s avant |
| Le bâton touche la neige | au changement lui-même |
| Il s'écrase et s'angule dans le nouveau virage | après |

S'y ajoutent, en permanence : l'**angulation** (le bassin rentre dans le virage, le buste reste par-dessus
le ski extérieur — la « virgule »), la **dissociation** (le haut du corps reste face à la pente pendant
que les jambes tournent), l'**avancée du ski intérieur**, l'**absorption** des réceptions et des
cassures (lue sur l'accélération verticale du trajet), et un léger mouvement permanent : il n'est
jamais parfaitement immobile.

C'est volontairement le **mouvement du corps qui annonce le virage**, pas l'inverse : le cadreur qui
regarde le skieur voit le bâton partir en avant et le corps se grandir une bonne demi-seconde avant
que les skis ne changent de direction. Les trois sports de ski en profitent sans rien avoir à régler.

---

## L'environnement

`environment` est un **tag**. Les tags `neige`, `descente`, `freeride`, `route_montagne`, `foret`,
`circuit` et `drill` ont un constructeur dédié (`builder` dans leur fichier de style) ;
tous les autres utilisent le constructeur générique configuré par un fichier de style
`res://scenarios/environments/styles/<tag>.tres`.

| Tag | Décor |
|---|---|
| `neige` | pente neigeuse, arbres, rochers, portes de slalom (`env_overrides` : `slope`, pente de 0,3 par défaut ; `relief`, de 0 à 1, fait varier la pente le long de la descente : raides, replats et cassures, 0 par défaut, 0,6 pour le ski alpin) |
| `descente` | piste de descente façon Streif / Bellevarde : versant de 2 à 2,5 km dont la pente change par sections (replats 16 - 26 %, parties rapides 30 - 40 %, murs 45 - 62 %), cassures de pente pour les sauts, piste damée de 36 à 60 m de large taillée dans la forêt, portes rouges, filets A rouges (4 m) à l'extérieur des virages et le long des réceptions, filets B orange, lignes bleues avant les sauts, un télésiège le long de la piste et un autre qui la survole, cabane de départ, arrivée (ligne, arche, tribune avec spectateurs, panneaux). Rien n'est construit sur le trajet du drone (un télésiège est déplacé, ou retiré, si le drone passe près de ses câbles) ; `env_overrides` : `relief` (0 à 1, 0,7 pour le ski de descente) raccourcit les sections de pente, ajoute des ondulations de 30 à 60 m qui font varier la pente et rapproche les cassures |
| `freeride` | grande face raide façon Freeride World Tour : départ sur l'arête sommitale (portique, drapeaux, officiels), face de 600 m environ à 38 - 50° avec bosses, arêtes et couloirs dans la ligne de pente, 3 à 5 barres rocheuses (falaises de 7 à 13 m, couloirs dans leurs brèches), îlots rocheux, arêtes latérales, vieilles traces dans la neige ; en bas, cône de déjection puis cuvette d'arrivée (ligne, arche gonflable, public derrière des banderoles, drapeaux), sapins. Le relief qui cache le sujet compte comme obstacle |
| `circuit` | **circuit automobile** : le Nürburgring Grand-Prix-Strecke à l'échelle ½ (2 573 m, 15 virages, 20 m de dénivelé) — asphalte, lignes blanches, vibreurs, dégagements et bacs à gravier, rails et grillages pare-débris, panneaux, stands et voie des stands, tribunes avec public, portique de départ, pont Dunlop, forêt de l'Eifel, château de Nürburg (`env_overrides` : `track_scale`, `point_step`). Voir [docs/circuit.md](circuit.md) |
| `route_montagne` | route de montagne posée sur le trajet, bornes, pins, rochers, **tunnel** si le trajet a une partie droite de 66 m ou plus |
| `foret` | forêt dense et sentier (`env_overrides` : `trail_clearance`, `drone_clearance`, `background_trees`) |
| `glace` | patinoire : bandes, lignes, tribunes ; les joueurs servent d'obstacles |
| `stade` | pelouse, lignes de terrain, tribunes |
| `salle` | salle de sport : parquet, lignes de basket, murs |
| `court` | court de tennis, clôture |
| `piste_urbaine` | asphalte et immeubles |
| `terrain_vague` | sol bosselé et blocs |
| `prairie` | prairie vallonnée et arbres |
| `drill` | **terrain d'exercice** (onglet « Mouvements ») : la même prairie vallonnée, mais les décors sont placés pour ne jamais pouvoir passer entre la caméra et le sujet — couloir dégagé le long du trajet, aussi large que la figure du drone va loin ; arbres et rochers en dehors, pour la parallaxe ; à l'intérieur, seulement des buissons et des pierres de moins de 80 cm (`env_overrides` : `terrain_kind`, `slope`, `bump`, plus `clearing` pour imposer la demi-largeur du couloir). Voir [docs/mouvements.md](mouvements.md) |
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

### Les figures d'exercice (onglet « Mouvements »)

Quatre mouvements de plus existent, marqués `"drill": true` dans `ScenarioMatrix.MOVEMENTS` :
`spiral_in` (spirale vers l'intérieur), `reveal_up` (reveal tilt bas vers haut), `pass_behind`
(flyby par derrière) et `vertical_pass` (vertical tilt). Ils ne sont **jamais tirés au hasard** pour
une session d'entraînement et ne figurent pas dans la liste « Mouvement du drone » de la page de
réglages : on les joue depuis l'onglet « Mouvements », sur leur propre sujet (`CIBLE`) et à une
vitesse de sujet choisie. Les mettre dans `recommended_movements` d'un sport n'y changerait rien.
Voir [mouvements.md](mouvements.md).

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
  tous les archétypes sauf `CIRCUIT` (la durée vient du circuit : un tour) et `SAUT_ACROBATIQUE`, dont la durée vient du parcours lui-même
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

# Le circuit — Nürburgring (Grand-Prix-Strecke)

Le circuit du Nürburgring, version **Grand-Prix-Strecke** (le tracé moderne, 5,148 km, 15 virages,
dessin de 2002), **réduit de moitié**. Il sert à deux choses :

- le sport **« Circuit de course »** : une GT lancée fait **un tour complet**, environ **1 min 30** ;
- le terrain **« Circuit »** du bac à sable : **neuf voitures de six classes** tournent en même temps.

> Pourquoi la GP-Strecke et pas la Nordschleife ? Un tour de Nordschleife (20,8 km, 73 virages) dure
> 8 minutes en vrai. Pour le ramener à 1 min 30 il faudrait diviser le tracé par 8 à 10 : les virages
> tomberaient à 2 - 15 m de rayon, infranchissables pour une voiture de 4,6 m. La GP-Strecke divisée
> par 2 donne exactement la durée demandée avec des rayons qui restent ceux d'un vrai circuit.

---

## Le tracé (`scenarios/circuit/circuit_track.gd`)

| | Réel | Dans le jeu (÷ 2) |
|---|---|---|
| Longueur du tour | 5 148 m | **2 573 m** |
| Emprise | 1 695 × 878 m | **847 × 439 m** |
| Dénivelé | ~40 m | **20 m** (mêmes pentes : tout est divisé par 2, longueurs **et** hauteurs) |
| Rayon du virage le plus serré (axe) | ~30 m | **15 m** |
| Largeur de piste | 10 à 15 m | **11,2 m** (*non* réduite : une voiture de 4,6 m a besoin de place pour sa trajectoire) |

**D'où vient la forme.** Le plan du circuit de l'article Wikipédia
(`Nürburgring - Grand-Prix-Strecke.svg`) a été aplati en polyligne, mis à l'échelle pour que sa
longueur fasse les 5,148 km officiels, puis **re-parcouru par un « pilote » à courbure bornée** :
il vise un point 17 m devant lui sur le dessin et braque vers lui, sans jamais descendre sous 30 m
de rayon ni changer de braquage trop vite. Un plan schématique dessine les virages lents beaucoup
plus pointus qu'ils ne sont ; ce passage les rouvre à des valeurs réalistes sans déplacer le tracé.

**Le relief** est donné par une table de hauteurs le long du tour, calée sur le vrai circuit :
descente depuis la ligne droite des stands vers le **point bas de la Mercedes-Arena**, remontée par
la Valvoline et la Ford-Kurve jusqu'au **point haut vers la Kumho-Kurve**, puis descente de la
ligne droite arrière vers la **chicane Veedol** et remontée par la **Coca-Cola-Kurve**.

**Les 15 virages** sont nommés dans `CircuitTrack.CORNERS` : Castrol-S (T1), Mercedes-Arena (T2 à
T4), Valvoline-Kurve (T5), Ford-Kurve (T6), Dunlop-Kehre (T7), Michael-Schumacher-S (T8 - T9),
Kumho-Kurve (T10), Bit-Kurve (T11), NGK-Schikane (T12), Veedol-Schikane (T13 - T14),
Coca-Cola-Kurve (T15).

## La trajectoire de course

`CircuitTrack.line_offsets` place la voiture **large à l'entrée, à la corde au point de corde,
large à la sortie**, sans jamais sortir des lignes blanches (1,5 m de marge). Les points de passage
sont reliés par des rampes douces : entre deux virages la voiture traverse la piste
progressivement, et dans une chicane les deux consignes se rencontrent et s'annulent — elle passe
tout droit.

La traversée est d'autant plus courte que le virage est serré (environ 3 rayons) : **c'est ce qui
ouvre la corde**. Se mettre à l'intérieur resserre la trajectoire d'à peu près `k² × décalage` ;
seul un braquage tardif et rapide compense ce resserrement, exactement comme un pilote dans une
épingle.

## La dynamique des voitures (`scenarios/circuit/race_car_physics.gd`)

La vitesse n'est **pas** dessinée à la main : c'est une **simulation de tour quasi-statique**, le
modèle qu'utilisent les logiciels de temps au tour. En chaque point la voiture est limitée par

- **les pneus** : `a_max = µ · g · (1 + appui / poids)`, l'appui aérodynamique croissant avec le
  carré de la vitesse — un virage rapide tient donc beaucoup plus de g qu'un virage lent ;
- **le moteur** : la motricité (`a_max × part du poids sur l'essieu moteur`) à basse vitesse, puis
  `puissance / (masse × v)`, si bien que la reprise s'émousse quand la vitesse monte ;
- **la traînée** et la résistance au roulement, qui aident aussi au freinage ;
- **la pente**, qui coûte ou rend de l'accélération.

Virage et accélération/freinage **se partagent la même adhérence** (ellipse de friction) : ce qui
reste au moteur ou aux freins est `√(a_max² − a_latéral²)`. C'est pour cela qu'on ne peut pas
remettre les gaz en plein virage.

Une passe avant (jusqu'où la voiture peut accélérer) et une passe arrière (jusqu'où elle peut
retarder son freinage) tournent trois fois autour de la boucle fermée jusqu'à se rejoindre.

**Validation** : à l'échelle **1** le modèle donne **2'03 pour une GT3** et **2'12 pour une GT4** au
Nürburgring GP — les vrais temps de ces catégories. C'est le même code qui tourne à l'échelle ½.

| Voiture | Masse | µ | Puissance | Appui (à 180 km/h) | Tour (÷ 2) | Vitesses |
|---|---|---|---|---|---|---|
| GT3 | 1 300 kg | 1,50 | 550 ch | 0,35 g | 1'23 | 49 - 215 km/h |
| **GT4** (niveau « Circuit de course ») | 1 350 kg | 1,38 | 430 ch | 0,16 g | **1'30** | 47 - 193 km/h |
| Tourisme TCR | 1 250 kg | 1,30 | 350 ch | 0,10 g | 1'35 | 45 - 180 km/h |
| Historique | 1 100 kg | 1,15 | 300 ch | 0,05 g | 1'41 | 42 - 172 km/h |
| GT de route | 1 550 kg | 1,05 | 400 ch | 0,04 g | 1'56 | 37 - 158 km/h |
| Safety car | 1 700 kg | 1,00 | 320 ch | 0,02 g | 2'21 | 30 - 128 km/h |

La GT4 freine jusqu'à **1,8 g**, tient **1,6 g** en courbe et reprend à **0,75 g** : chaque
changement de vitesse a une cause visible sur la piste (une zone de freinage, une corde, une
sortie), ce qui permet au cadreur d'anticiper.

## Le drone de poursuite

Un drone ne peut pas freiner avec une voiture de course : pour rester à son niveau il doit tirer
**autant de g qu'elle**. Les limites d'accélération du niveau (3,5 à 9 m/s²) sont faites pour un
skieur ; la fiche du circuit les desserre avec deux réglages, utilisables par n'importe quel sport :

- `drone_accel_relax` (3,8 ici) : combien de fois plus fort que la limite du niveau le drone de
  poursuite a le droit de travailler ;
- `drone_smoothing` (2,0 ici) : combien de lissage supplémentaire le planificateur a le droit
  d'utiliser avant d'en arriver là.

Mesuré sur un tour complet (suivi latéral) : **accélération du drone 11 à 15 m/s² (p95)**, pointes à
13 - 18 m/s² (p99) — soit 1,3 à 1,8 g, ce que fait un vrai drone FPV de poursuite. La vitesse de
défilement du sujet dans l'image reste dans les clous du niveau (**pan 20 à 34 °/s au 95e
centile**), et le sujet n'est caché que **0,3 s par tour**.

## Les décors (`scenarios/circuit/circuit_scenery.gd`)

Asphalte et lignes blanches, **vibreurs rouge et blanc** à la corde de chaque virage et en sortie,
**dégagements** (bande d'asphalte peint, gris à bord vert) qui s'élargissent à l'extérieur des courbes, **rails de
sécurité** doublés d'un **grillage pare-débris**, **panneaux publicitaires**, **postes de
commissaires**, **bâtiment des stands** et sa **voie des stands** le long de la ligne droite de
départ, **tribunes** avec public à la Mercedes-Arena et aux grands virages, **portique de départ**,
**pont Dunlop**, **paddock**, **forêt d'épicéas de l'Eifel** et la **tour du château de Nürburg**
sur sa butte.

Les **vibreurs** sont de vrais vibreurs en relief : une pente qui monte depuis l'asphalte puis une
joue verticale à l'extérieur, avec des bandes rouges et blanches d'un mètre peintes par la
coordonnée de texture. La **trajectoire de course** laisse une trace de gomme sombre de 3 m de large
sur l'asphalte, estompée sur ses bords. Des **murs de pneus** sont empilés là où le dégagement
atteint plus de la moitié de sa largeur maximale.

Le **dégagement** est un vrai sol, pas un aplat : `GroundMaterials.runoff()`, de l'asphalte scellé
gris posé par lots, fissuré, avec ses gravillons jusqu'à 26 m et le détail photographié par-dessus,
peint en vert vers ses bords et usé par les voitures. C'est la deuxième surface de l'image après la
piste et le drone vole à cinq mètres au-dessus. Coût mesuré **dans le même processus** (le même
cadrage à 30 m, 600 images chacun, matériau échangé à chaud) : la différence avec l'aplat d'avant
reste **sous le bruit de mesure** — ±0,15 ms sur 2,5 à 3,5 ms par image, alors que d'un lancement à
l'autre l'horloge GPU fait bouger le total d'une milliseconde entière.

**Le sens des triangles d'une bande plate** (`_band`, `_s_band`) : le quadrilatère est donné dans
l'ordre (intérieur i, extérieur i, intérieur j, extérieur j), et une seule des deux diagonales
oriente ses triangles **vers le haut**. Avec l'autre, ils regardent le sol : un décor dont le
matériau ne dit pas `cull_disabled` ne dessine alors **rien du tout** vu d'un drone. C'est ce qui a
tenu hors de l'image le **dégagement**, les **lignes blanches de rive**, la **ligne
de départ** et les **emplacements de la grille** — tout ce qui est en `GroundMaterials.paint()` —
pendant que l'asphalte et le terrain, eux, s'en tiraient parce que leurs shaders ont `cull_disabled`.
Constaté par capture : bande seule → visible ; bande dans la scène → zéro pixel ; matériau passé en
`cull_disabled` → visible de nouveau.

Les **grillages pare-débris** ne sont montés que **devant les tribunes et le long de la ligne des
stands** — partout ailleurs il n'y a que le rail, comme sur le vrai circuit. Un grillage posé tout
autour du tour finissait par traverser la piste dans les épingles : au-delà d'un certain décalage,
une parallèle au tracé se retourne.

C'est la première de quatre contraintes géométriques gérées automatiquement, sans quoi le circuit se
replie sur lui-même :

- **Décalages bornés par le rayon** (`CircuitLayout.safe_offset`) : une ligne parallèle à la piste
  se retourne dès qu'on la décale de plus que le rayon du virage vers son centre. Un dégagement de
  35 m à l'intérieur d'une épingle de 14 m deviendrait un nœud.
- **Rails lissés et bornés qui ne peuvent que se rapprocher** (`CircuitLayout._barrier_fit`) : un
  rail se courbe, il ne se plie pas, donc sa ligne est lissée puis limitée en variation par mètre
  de piste. Mais ces deux opérations n'ont le droit que de **rapprocher** le rail de la piste,
  jamais de l'en écarter : lisser une ligne qui épouse l'intérieur d'une épingle la repoussait de
  plusieurs mètres **à l'intérieur des lignes blanches** (jusqu'à 7,9 m), et le limiteur de pente
  aggravait le cas. Ce qu'ils retirent au rail est retiré au dégagement en même temps — c'est
  pourquoi le calcul vit dans le `CircuitLayout` et non dans le décor : la largeur du dégagement
  est la seule chose qui dise à la fois où le gravier est dessiné, où le sol est aplani et où le
  rail se tient. Corriger le rail seul laisserait le gravier dessiné **derrière** sa propre
  glissière. Vérifié sur tout le tour, aux deux échelles de points (429 et 858) et des deux côtés :
  aucun point de rail sur l'asphalte, aucun repli, aucune marche, aucun gravier au-delà du rail.
- **Dégagements ajustés aux autres brins du tour** (`CircuitLayout._build_runoff`) : la
  Mercedes-Arena est un oméga dont les deux brins ne sont qu'à quelques dizaines de mètres l'un de
  l'autre. Chaque côté est rétréci jusqu'à ce que son rail soit dégagé de **toute** partie du
  circuit. La largeur du dégagement appartient au `CircuitLayout` lui-même, et non au décor : c'est
  ce qui permet au terrain de s'aplanir exactement sous le dégagement dessiné. Les tribunes et les
  bâtiments sont placés de la même façon, et ceux qui n'ont de place nulle part ne sont pas
  construits.
- **Altitudes relâchées entre brins voisins** (`CircuitLayout._level_folds`) : l'altitude est
  donnée le long du tour, donc deux brins qui se croisent presque peuvent se retrouver à 25 m l'un
  au-dessus de l'autre — une falaise au milieu du paddock. Chaque point est tiré vers les points
  proches en plan (moins de 60 m) mais éloignés le long du tour (plus de 150 m), en vingt passes.

Les tribunes et le bâtiment des stands sont par ailleurs reculés à **au moins 41 m de l'axe** : le
drone de poursuite travaille jusqu'à 35 m de la piste, et une tribune plus près l'obligerait à
passer **au-dessus du toit** — en perdant la voiture de vue.

## Ce que heurte le drone piloté (mode 2 joueurs, bac à sable)

Le décor est décrit trois fois, pour trois usages, et il ne faut pas les mélanger :

| Description | Sert à | Précision |
|---|---|---|
| `CircuitScenery.clearance()` (grille `_tops`, cases de 8 m) | garder le **drone automatique** des sessions au-dessus des structures (planificateur) | enveloppe grossière : chaque structure y devient un carré, et le portique et le pont Dunlop un bloc plein jusqu'au sol |
| `CircuitScenery.boxes` → cylindres d'occlusion | **ligne de vue** (sujet caché) | un bloc par structure |
| `CircuitScenery.solids` + `solid_push()` | **collisions** : drone piloté en 2 joueurs, drone et pilote automatique du bac à sable | les formes dessinées, rien de plus |

En 2 joueurs, le drone piloté utilisait les deux premières. Résultat : des **planchers invisibles en plein air** —
le drone qui rasait la piste était remonté d'un coup sur la « dalle » de la grille puis freiné comme
s'il était posé : 9 m au-dessus de la piste sous le pont Dunlop, 8 m sous le portique, 2,4 m sur
16 m de côté autour de chaque poste de commissaire (jusque sur l'asphalte), et jusqu'à 12 m autour
des tribunes des derniers virages, à 14 m de l'axe. Il décollait d'ailleurs déjà perché à 8–12 m du
sol. Relevé en rejouant huit vols enregistrés : plusieurs secondes par tour passées sur ces dalles,
abordées jusqu'à 86 km/h.

Désormais (`EnvCircuit.pilot_floor`, `pilot_hits_occluders`, `dynamic_push`) :

- le **sol** du drone piloté est le vrai terrain ;
- il ne heurte que les `solids` : garages des stands, paddock, postes de commissaires, tour du
  château, jambes **et poutres** du portique et du pont (on passe dessous, on se cogne dedans),
  **gradins** des tribunes — une rampe par segment de tribune, qui passe par le pied des marches et
  ne dépasse donc jamais du dessin — et leur **toit** ;
- la poussée sort par la face la plus proche, **dessus et dessous compris** : le drone se pose sur
  un toit (qui compte alors comme un sol : frottement, remise à plat) et se cogne sous une poutre.

Les rails, grillages, panneaux, pneus, arbres et le muret des stands ne sont pas solides : la règle
est qu'une collision sans objet dessiné est un bug, l'inverse une simple tolérance.

Vérifié en comparant chaque poussée aux `BoxMesh` réellement affichés : sur 940 000 points autour
des 142 solides, **aucune** collision à plus de 0,35 m d'un objet dessiné (pire cas 0,27 m, rayon du
drone compris) ; sol du pilote = terrain sur 52 000 points à ±60 m de l'axe ; passage sous le
portique et sous le pont à 1, 3 et 5 m sans contact. `clearance()` et `boxes` n'ont pas changé : le
drone automatique et la ligne de vue du mode solo sont identiques à avant.

Conséquence : les replays des vols 2 joueurs enregistrés **avant** ce correctif sur le circuit ne
retombent plus sur la trajectoire d'origine (le replay rejoue les manches, et le drone ne bute plus
aux mêmes endroits).

Le **bac à sable « Circuit »** (`CircuitWorld.push`) utilise les mêmes `solids` : il n'avait pas de
plancher invisible (son sol était déjà le terrain), mais ses tribunes étaient des blocs pleins mal
orientés et ses poutres se traversaient. Son pilote automatique garde 3,5 à 5 m de marge autour de
ces formes, et vérifie désormais aussi le trajet **à l'altitude d'arrivée** de chaque tronçon
(`AutoFlight._clear`) : le drone descend d'emblée puis vole à plat, bien sous la ligne droite entre
deux points de passage, et rasait ainsi le toit de la grande tribune. Sur 40 vols de 5 minutes
(121 km) : 1 traversée d'un objet dessiné et 401 images à moins de 2 m **avant**, **aucune** après ;
54 % du temps en tronçons bas (59 % avant), accélération max inchangée (3,6 m/s²).

## Les voitures du bac à sable saccadaient en roulant

`CircuitTraffic._place()` recalcule chaque image la position et le cap d'une voiture à partir de
`CircuitLayout.dir_at(s)` / `normal_at(s)` : la direction de la piste à sa distance de tour `s`.
Cette fonction ne regardait que le point échantillonné le plus proche (un tous les 3 m) au lieu
d'interpoler entre les deux points autour de `s`, contrairement à `point_at()` qui, elle,
interpole bien la position. Direction et cap **sautaient donc d'un coup** à chaque point
échantillonné, pendant que la position elle-même avançait sans à-coup : mesuré, jusqu'à 12° d'un
coup dans l'épingle la plus serrée, **au même endroit du tour à chaque tour, quelle que soit la
vitesse** - la signature d'un saut au lieu d'un mouvement.

Corrigé en interpolant aussi la direction (`CircuitLayout.dir_at`), par slerp entre les deux
directions voisines, avec le même paramètre `t` que `point_at()`. Vérifié : le saut de cap devient
proportionnel à la vitesse (1 à 3° par image selon la vitesse, comme un virage qui tourne
réellement) au lieu d'un saut fixe de 12° indépendant d'elle.

**Un second saut, plus gros, restait dans les virages** : la trajectoire de course de chaque voiture
(`_offsets`, à quel point du bord à bord elle roule) et le calcul qui la garde hors de l'intérieur
d'un virage serré (`safe_offset`) étaient lus eux aussi au point échantillonné le plus proche - pas
interpolés. Dans un virage, où cette trajectoire traverse la piste sur plusieurs mètres en peu de
distance, cela sautait d'un coup **jusqu'à 1,33 m** (mesuré, à la corde 312 m) - indépendamment de la
vitesse, et c'est lui le plus gros, surtout visible quand une voiture balaie large une partie du
virage (ce que l'utilisateur a décrit comme « en drift »). Corrigé en ajoutant
`CircuitLayout.sample_along()` (même interpolation que `point_at()`, pour n'importe quelle valeur
donnée point par point : trajectoire, courbure) et en l'utilisant pour la position latérale de
`CircuitTraffic._place()` et pour le roulis (`_yaw_rate`, qui avait le même défaut, jusqu'à 0,85°
d'un coup). Vérifié : le saut latéral redevient proportionnel à la vitesse (0,11 à 0,33 m selon la
vitesse) au lieu d'un saut fixe de 1,33 m ; sur 2 minutes de trafic réel (9 voitures), écart
latéral/avancement maximal 0,13 m sur 64 755 mesures, le saut de cap plafonne à 1,26°. Dépassements
et distances entre voitures inchangés.

La voiture unique du niveau d'entraînement (`ArchetypeCircuit`) ne roule pas sur cette trajectoire
image par image : son tracé vient de `CircuitLayout.racing_line()`, déjà rééchantillonné et lissé
d'avance, donc elle n'avait aucun de ces deux défauts.

**Une troisième cause, celle-là dans le terrain lui-même : des voitures en roue arrière ou avant.**
Le relevé d'altitude du tour (`CircuitTrack.HEIGHT_S/HEIGHT_M`) ne sait rien des endroits où le tour
se replie sur lui-même - l'oméga de la Mercedes-Arena, une épingle à côté de sa propre ligne droite -
qui peuvent placer deux brins à quelques dizaines de mètres l'un de l'autre en plan mais à plus de
dix mètres d'écart d'altitude : sans correction, le sol entre eux serait une falaise.
`CircuitLayout._level_folds()` existe pour ça : chaque point est tiré vers l'altitude des points
proches en plan mais éloignés le long du tour. Mais cette correction ne regarde pas sur quelle
distance, le long du tour, elle doit étaler le changement - un tirage de onze mètres peut se tasser
sur à peine cinquante mètres de piste. La falaise disparaît, mais une voiture qui roule dessus tangue
comme si elle avait pris une rampe : mesuré, **jusqu'à 35 % de pente par endroits, sur 9 zones
distinctes du tour**, alors que le relevé d'altitude d'origine ne dépasse jamais 7 %.

Corrigé en ajoutant `CircuitLayout._limit_grade()` : une passe qui plafonne la pente du profil final
à 10 %, en redonnant la moitié de tout excès de chaque côté du segment qui le porte - jusqu'à ce que
le changement nécessaire soit étalé sur assez de distance pour rester sous ce plafond, sans toucher
au reste du relevé (qui, lui, reste sous les 10 %). Vérifié : les 9 zones trouvées descendent toutes
sous 12 %, l'altitude extrême du tour reste cohérente avec le relevé d'origine (environ 28 m
d'écart à pleine échelle), et sur 2 minutes de trafic réel (9 voitures), le tangage maximal observé
tombe à 8° - contre 19 à 35° avant - sans rien changer aux dépassements ni à l'espacement entre
voitures.

**Un quatrième défaut, lui dans le SIGNE du tangage** : même une fois la pente plafonnée à une valeur
réaliste, les voitures continuaient à sembler « en roue arrière ou avant » dans les montées et les
descentes. `CircuitTraffic._place()` calculait l'angle de tangage avec un signe inversé
(`atan2(-slope, 1.0)`, et de même pour l'accélération) : vérifié par un test isolé (une pente
montante donnait un angle qui penche le NEZ VERS LE BAS, l'inverse de ce qu'une voiture fait
réellement en montée). Le même signe inversé s'appliquait au tangage d'accélération/freinage
(cabrage à l'accélération, plongée au freinage). Corrigé en retirant les deux signes moins
(`atan2(slope, 1.0) + accel * 0.0025`). Vérifié : sur 2 minutes de trafic réel, le tangage affiché
est maintenant du même signe que la pente réelle du tour 31 394 fois sur 31 435 mesures (les rares
désaccords sont aux points d'inflexion, où le terme d'accélération l'emporte brièvement sur une
pente quasi nulle - normal). Tangage maximal inchangé (8°), dépassements et espacement entre
voitures inchangés.

## Le sol sous la piste est creusé exprès

Le terrain est dessiné en triangles de 6 m de côté et, entre ses sommets, il interpole en ligne
droite. Là où la piste est bombée — un sommet de côte, un virage relevé — cette ligne droite passe
**au-dessus** de la surface qu'elle est censée suivre, jusqu'à 14 cm (mesuré, pire cas à 69 % du
tour). Comme la bande d'asphalte n'est posée qu'à 5 cm au-dessus de la surface, le terrain
ressortait à travers la route : des plaques de sol, et de l'herbe que son shader peint, en plein
milieu de la piste.

Affiner le terrain assez pour qu'il épouse la courbure coûterait quatre fois plus de sommets pour
quelque chose que personne ne voit — c'est sous l'asphalte. Le sol est donc simplement **abaissé de
45 cm sous l'ensemble routier** (`CircuitLayout.ROAD_DIP`) et ramené à la surface exactement là où
il redevient visible, au bord extérieur du dégagement, là où l'œil verrait une marche. La face
extérieure du vibreur s'appuie du coup sur la bande de dégagement et non sur le sol, sinon elle
mesurerait un demi-mètre. Vérifié sur les 858 points du tour : plus aucun percement, marge minimale
de 12 cm.

## Construit une seule fois

`CircuitLayout.shared(échelle, pas)` construit le tracé, sa grille, son champ de hauteur et ses
dégagements **une fois pour toutes** : tout cela est entièrement déterminé par l'échelle et le pas,
et rien n'écrit dans un layout après sa construction. La deuxième session sur le circuit et le bac
à sable réutilisent le premier (139 ms → 0,01 ms). Le maillage du terrain, qui en découle
entièrement — 41 000 sommets, un appel à `ground()` chacun, 216 ms — est conservé avec lui
(`CircuitScenery._terrain_cache`). Seul le maillage est partagé : le matériau porte le masque de sol
de la session et reste privé. Au total, le circuit passe de 2,3 s à 0,9 s de construction au
deuxième lancement. Voir [optimisation.md](optimisation.md).

## Le bac à sable « Circuit »

`scenarios/sandbox/circuit_world.gd` et `circuit_traffic.gd`. Neuf voitures (deux GT3, deux GT4,
deux tourismes, une historique, une GT de route, la safety car) tournent chacune à son rythme sur
sa propre trajectoire, plus ou moins large selon le pilote. Elles se rattrapent donc, et le
dépassement n'est pas scripté :

1. une voiture gênée pendant plus de 0,45 s par une voiture **plus lente et sur sa ligne** choisit
   un côté et se déporte de 3,4 m ;
2. elle y reste tant que l'autre n'est pas repassée derrière (sinon elle se rabattrait dessus) ;
3. une fois vraiment à côté, elle reprend son propre rythme et passe.

Le « sur sa ligne » est testé **à l'endroit de l'autre voiture**, pas à l'endroit de celle qui
suit : les trajectoires se croisent le long du tour, et deux voitures qui se croisent à 50 m
d'intervalle ne roulent pas au même endroit.

Vérifié sur **4 minutes** de simulation : aucune voiture qui en traverse une autre, aucune voiture
bloquée (jamais sous 6 m/s), écart minimal entre deux voitures **0,2 m** (du vrai roue contre roue),
et **aucune collision** du drone automatique avec le décor.

## Changer quelque chose

- **L'échelle** : `track_scale` dans la fiche `circuit_course.tres` (et dans ses `env_overrides`,
  les deux doivent correspondre). 0,5 par défaut.
- **La voiture** : `car` dans la fiche — un identifiant de `RaceCarPhysics.CARS`. `grip`, `power` et
  `pace` surchargent la voiture choisie sans décrire une classe entière.
- **La trajectoire** : `line_margin` (distance aux lignes blanches) et `line_swing` (0 = l'axe,
  1 = un pilote de course).
- **Le plateau du bac à sable** : `CircuitTraffic.FIELD`.
- **Une nouvelle classe de voiture** : une entrée dans `RaceCarPhysics.CARS` suffit, les deux
  niveaux la reprennent.

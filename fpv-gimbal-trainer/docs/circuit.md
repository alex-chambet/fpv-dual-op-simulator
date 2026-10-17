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
**dégagements** (bande peinte puis gravier) qui s'élargissent à l'extérieur des courbes, **rails de
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

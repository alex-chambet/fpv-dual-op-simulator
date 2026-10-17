# FPV DUALOP v2.0 — Le circuit, les exercices de mouvement, et un jeu plus rapide

Deux ans de contenu en une version : un **circuit automobile** complet, une **troisième section de jeu** consacrée aux figures de drone, deux nouveaux terrains de ski, et une passe d'optimisation qui supprime le gel d'une seconde au lancement d'un niveau.

## Téléchargement

- `FPV_DUALOP_v2.0.exe` + `FPV_DUALOP_v2.0.pck` (Windows 64 bits). **Gardez les deux fichiers dans le même dossier.**
- Carte graphique compatible Vulkan requise (rendu Forward+).

---

## Nouveautés

### Circuit de course — le Nürburgring
Le Grand-Prix-Strecke réduit de moitié : **2,6 km, 15 virages, 20 m de dénivelé**, un tour complet à suivre. Le tracé vient du plan réel, aplati puis re-parcouru à courbure bornée pour rester pilotable à cette échelle.

La vitesse de la voiture n'est pas dessinée à la main : elle sort d'une **simulation de tour** (appui aérodynamique, cercle d'adhérence, motricité, traînée, pente, partage de l'adhérence entre virage et freinage), le même modèle que les logiciels de temps au tour. À l'échelle 1 il donne 2'03 pour une GT3 et 2'12 pour une GT4 — les vrais temps de ces catégories. Une GT4 lancée boucle le circuit réduit en **1 min 30**.

Chaque changement de vitesse a une cause visible sur la piste : gros freinage avant le Castrol-S et la Dunlop-Kehre, relance dans la Mercedes-Arena, pleine charge dans le Schumacher-S. Le décor suit : vibreurs en relief, trace de gomme sur la trajectoire de course, dégagements et bacs à gravier, rails, grillages pare-débris devant les tribunes, stands et voie des stands, portique de départ, pont Dunlop, forêt de l'Eifel et la tour du château de Nürburg.

Le drone de poursuite a dû apprendre à suivre : une GT freine à près de 2 g, et la fiche du circuit autorise explicitement son drone à tirer aussi fort, comme un vrai drone FPV de poursuite.

### Mouvements — une troisième section, à côté d'Entraînement et Bac à sable
Une seule figure de drone, répétée du début à la fin, autour d'un sujet qui ne fait rien d'autre qu'avancer tout droit : tout ce qui n'est pas le geste à apprendre est enlevé. **Cinq figures**, rangées de la plus simple à la plus difficile :

| Figure | Ce qu'elle travaille |
| --- | --- |
| **Orbite** | Un pan régulier, sans à-coup, sur tout le tour. |
| **Reveal tilt bas vers haut** | Un tilt presque pur, du sol jusqu'à l'horizon. |
| **Flyby par derrière** | Le drone rattrape le sujet en passant derrière lui et ressort de l'autre côté : le pan s'inverse au passage. |
| **Spirale vers l'intérieur** | Une orbite qui se resserre : le pan accélère en continu. |
| **Vertical tilt** | Passage juste au-dessus, presque perpendiculaire : pan et tilt à fond en même temps. |

La progression se fait d'abord sur la **vitesse du sujet** — immobile, marche, course, 32 km/h — et la figure ne change pas d'un palier à l'autre. Chaque carte montre la figure dessinée, et la page de réglages la joue **en vol, en boucle** : pas une vidéo, mais la trajectoire que le drone va réellement suivre, replanifiée quand on change de niveau.

### Deux terrains de ski
- **Ski de descente** : une piste de 2 km et plus façon Streif ou Bellevarde, à plus de 110 km/h, avec des sauts posés sur les cassures de pente, filets, portes, télésièges et public.
- **Ski freeride** : une grande face raide façon Freeride World Tour. La ligne est choisie barre rocheuse par barre rocheuse — sauter la falaise ou passer par un couloir — et la vitesse n'est jamais imposée : le skieur ne ralentit qu'en dérapant, skis en travers, ce que le cadreur peut voir venir. **Le plus dur à filmer du jeu.**

### Bac à sable « Circuit »
Le même Nürburgring, avec **neuf voitures de six classes** (deux GT3, deux GT4, deux tourismes, une historique, une GT de route, la safety car) qui tournent à leur propre rythme, se rattrapent et se doublent toutes seules.

### Le skieur bouge enfin comme un skieur
Les athlètes sont des mannequins articulés et animés. Le skieur en particulier prépare chaque virage : il se grandit skis à plat au changement de carre, plante le bâton aval juste avant, s'écrase au sommet du virage, et met les skis en travers avant de freiner. **Le cadreur peut anticiper les changements de direction en regardant le corps**, ce qui est tout l'intérêt de l'exercice.

### Interface et confort
- **Écran de chargement** qui reste affiché jusqu'à ce que le niveau soit vraiment prêt.
- **Vue du drone en incrustation** en bas à droite.
- **Survol de reconnaissance** du parcours avant le départ (sauté pour les exercices, qui n'ont pas de parcours à montrer).
- **Météo et ambiance** réglables en jeu : plein jour, matin, fin de journée, couvert, chute de neige.
- Menu refait en trois onglets, préférences conservées d'une partie à l'autre, tilt de la caméra pilote réglable, décompte en plein écran.

---

## Plus rapide

Tout est mesuré sur RTX 4070 Laptop, en 1080p, qualité Haute.

| | Avant | Après |
| --- | ---: | ---: |
| **Pire image vue au lancement d'un niveau** | **3 084 ms** | **18 ms** |
| Circuit, attente totale (1er / 2e lancement) | 3,28 / 2,06 s | **1,68 / 1,65 s** |
| Ski alpin, attente totale (1er / 2e) | 2,43 / 0,80 s | **1,03 / 0,71 s** |

Le gel d'une seconde au premier lancement d'un niveau — la compilation des shaders — se produisait **après** la disparition de l'écran de chargement, en pleine vue. Il se produit maintenant derrière lui : le temps total n'a pas changé, c'est le gel qui a disparu.

Le circuit est construit une seule fois et réutilisé par les sessions suivantes et par le bac à sable. Et le masque de sol du freeride créait 613 matériaux identiques là où un seul suffit : 758 000 triangles sont tombés à 439 000.

En jeu, le simulateur tourne entre **141 et 377 images par seconde** selon le niveau.

---

## Corrections

- **Circuit — plaques sur la piste et herbe sur la route.** Le terrain est dessiné en triangles de 6 m et interpole en ligne droite entre ses sommets ; là où la piste est bombée, il remontait jusqu'à 14 cm au-dessus de l'asphalte, qui n'est posé qu'à 5 cm. Le sol est maintenant creusé sous la route et ramené à la surface au bord du dégagement. Vérifié sur les 858 points du tour : plus aucun percement.
- **Circuit — rails sur la piste.** Le lissage de la ligne des glissières pouvait les repousser jusqu'à 7,9 m **à l'intérieur** des lignes blanches dans les épingles. Le lissage ne peut désormais que les rapprocher de la piste, jamais les en écarter, et le dégagement est rétréci avec eux.
- **Circuit — grillages pare-débris** montés seulement devant les tribunes et les stands, comme sur le vrai circuit : ils traversaient la piste dans les épingles.
- **Exercices impossibles à lancer** : le survol de reconnaissance se déclenchait devant une ligne droite et plantait sur le sujet immobile.
- **Exercices — horizon de travers** : la pente du terrain du « reveal tilt » donnait un horizon penché en permanence, alors qu'une gimbal garde l'horizontale par principe. Terrain remis à plat ; la figure n'y a rien perdu.
- **Voiture de course** : une planche flottait au-dessus du toit, et les roues ne tombaient pas en face des ailes.
- **Ski freeride et neige** : le relief de la neige s'arrêtait à 45 m et laissait un aplat blanc au-delà ; il porte maintenant jusqu'à 220 m. Les masques de roche ne scintillent plus en poivre et sel au loin.

---

## Compatibilité

- **Le trail et le VTT de descente sont temporairement retirés du menu.** Ils restent dans le jeu : les sessions enregistrées sur ces deux sports se rejouent normalement.
- Les meilleurs scores et l'historique de la 1.6 sont conservés.
- Le vol du drone a changé sur les sessions générées : une session enregistrée avec une version plus ancienne du modèle de vol ne se rejoue pas.

## Configuration testée

Windows 11, NVIDIA RTX 4070 Laptop, Vulkan.

## Limites connues

- Les performances n'ont été mesurées qu'en 1080p ; en 4K elles n'ont pas été relevées sur cette version.
- Le mode 2 joueurs et le vol acro n'ont pas été retestés avec deux manettes physiques sur cette version.
- Le niveau Expert reste validé surtout en simulation.
- Sur la route de montagne, le tunnel et le relief cachent encore la voiture 6 à 10 % du temps.

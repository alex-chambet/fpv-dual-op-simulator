# Analyse d'optimisation

Relevé fait le 17/10/2026 sur le projet complet (105 scripts, 23 664 lignes), machine RTX 4070
Laptop, Godot 4.7.2. Tout ce qui suit est **mesuré**, pas estimé ; les chiffres sont reproductibles
avec les scripts décrits en fin de document.

**La conclusion courte, qui va à l'encontre de l'intuition : le jeu n'est pas lent à l'exécution.**
Entre 141 et 377 i/s en 1080p en qualité Haute. Ce qui coûte, c'est **l'attente au lancement** (1 à
3,3 s) et surtout **un gel d'une seconde à la première image** d'un niveau jamais joué. Et le vrai
manque n'est pas technique : c'est qu'il n'y a aucune progression pour guider le joueur dans une
matrice de plus de mille combinaisons.

---

## 0. Fait (17/10/2026) : A1, A2 et A3

| | Avant | Après |
| --- | ---: | ---: |
| Pire image **vue par le joueur** au lancement | **3 084 ms** | **18 ms** |
| Circuit, construction au 2e lancement | 2 297 ms | **903 ms** |
| Circuit, attente totale (1er / 2e) | 3,28 / 2,06 s | **1,68 / 1,65 s** |
| ski_alpin, attente totale (1er / 2e) | 2,43 / 0,80 s | **1,03 / 0,71 s** |
| `CircuitLayout`, 2e construction | 139 ms | **0,014 ms** |

**A1 — l'écran de chargement reste pendant les premières images.** `LoadingScreen.run()` masquait
l'écran **à l'instant où le changement de scène rendait la main**, c'est-à-dire juste avant l'image
la plus chère de toute la session : celle qui compile le shader de chaque matériau qui entre dans le
champ. Mesuré sur un lancement réel depuis le menu : **10 images sont dessinées derrière l'écran de
chargement, dont une de 3 084 ms, et la première image que le joueur voit prend 18 ms.** Le temps
total n'a pas changé — c'est le gel qui a disparu. `_warm_up()` s'arrête dès que deux images
d'affilée passent sous 45 ms, donc quand les shaders sont déjà en cache cela coûte deux images.

**A2 — `CircuitLayout.shared(échelle, pas)`.** Le layout est entièrement déterminé par ces deux
nombres et rien ne l'écrit après sa construction : il est désormais construit une fois et réutilisé
par les sessions suivantes **et par le bac à sable**, qui en construisait un deuxième.

**A3 — le maillage du terrain du circuit est mis en cache avec le layout.** 41 000 sommets, chacun
un appel à `CircuitLayout.ground()` : la phase la plus chère du circuit (216 ms). Comme elle découle
entièrement du layout partagé, le résultat est conservé. Seul le maillage l'est — le matériau porte
le masque de sol de la session et reste privé.

Vérifié : les 8 niveaux d'entraînement se construisent sans erreur, la scène du circuit est
identique au nœud près d'un lancement à l'autre (4 060 nœuds, 896 maillages, 3 124 MultiMesh,
127 k triangles), et le bac à sable se construit correctement après le niveau d'entraînement en
partageant le même layout.

## 0 bis. Fait (17/10/2026) : B1, B2 — et B3 mesuré puis **abandonné**

**B1 — les arbres du terrain d'exercice forment une lisière.** Ils étaient semés sur les 420 × 1 300 m
du terrain : si clairsemés que le moteur, qui les regroupe par chunk de 64 m, en mettait **un par
MultiMesh** (501 arbres, 506 nœuds MultiMesh, 990 appels de rendu pour une prairie vide). Ils
occupent maintenant une bande de 80 m juste au-delà du dégagement, à densité constante.

| exercice | avant | après |
| --- | ---: | ---: |
| appels de rendu | 990 | **630** (−36 %) |
| nœuds MultiMesh d'arbres | 506 | **198** |
| nœuds de la scène | 677 | **287** |
| triangles | 93 k | **54 k** |
| GPU | 3,68 ms | 3,81 ms |

Le GPU ne bouge pas : il y a moins d'arbres, mais ils sont désormais tous dans le champ au lieu
d'être majoritairement hors cadre. En échange l'horizon est une vraie lisière de forêt et non des
arbres isolés.

**B2 — la duplication n'était pas où je l'avais cherchée.** Le relevé des matériaux de chaque
niveau le dit sans ambiguïté :

| niveau | objets matériau | distincts | avant → après |
| --- | ---: | ---: | --- |
| ski_freeride | 638 | **24** | 638 → **26** |
| ski_descente | 54 | 31 | 54 → 37 |
| departementale | 70 | 66 | 70 → 65 |
| circuit_course | 54 | 48 | inchangé |
| trail | 17 | 17 | inchangé |

Quatre niveaux sur cinq n'avaient **rien** à partager : un cache général `shared_mat()` sur les 48
appels à `make_mat()` n'aurait rien rapporté, et aurait cassé les 5 appelants qui modifient le
matériau qu'ils reçoivent. Toute la duplication venait d'un seul endroit : `GroundMask.add_disc()`
créait **un maillage de cylindre à 48 segments, un matériau et un nœud par disque**, et la face de
freeride en peint 613 du même rouge. Un disque unitaire partagé (14 côtés : un texel du masque fait
50 cm, le reste était invisible) et un matériau par couleur suffisent. Les triangles du freeride
tombent de **758 k à 439 k**.

**B3 — élargir `Vegetation.CHUNK` : mesuré sur 64 / 96 / 128 / 192 m, puis abandonné.**

| CHUNK | ski_descente | | trail | | exercice | |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| | appels | GPU | appels | GPU | appels | GPU |
| **64** | 870 | **6,10** | 625 | **7,78** | 990 | **3,68** |
| 96 | 690 | 6,08 | 425 | 7,90 | 711 | 3,74 |
| 128 | 603 | 6,29 | 383 | 8,03 | 542 | 3,79 |
| 192 | 440 | 6,47 | 339 | 8,48 | 439 | 3,83 |

Les appels de rendu chutent de 31 à 46 %, **et le temps GPU monte**. Le découpage fin coûte des
appels mais les fait gagner ailleurs : il permet d'écarter par le culling, et de basculer en modèle
simplifié, des paquets d'arbres plus petits et plus justes. Sur cette carte graphique un appel de
rendu est bon marché et la géométrie ne l'est pas. `CHUNK` reste à 64 m. (À reconsidérer sur une
machine plus faible, où l'arbitrage s'inverserait.)

## 0 ter. Fait (17/10/2026) : D1, la carte « À travailler »

`scenarios/practice_advisor.gd`, affichée sur l'accueil à gauche de « Session aléatoire ». Elle lit
les deux fichiers que le jeu écrivait déjà sans que personne ne les relise, et propose **une**
session à jouer, avec la raison en toutes lettres sous les cartes :

> Dévoilement · Départementale, niveau 4 · Une seule session, 51/100.

La règle est volontairement simple, pour que ce que dit le menu soit toujours justifiable par un
chiffre qu'il affiche : pour chaque mouvement, `besoin = (100 − moyenne) + 4 × (6 − sessions)`, les
sessions manquantes comptant jusqu'à six. Un mouvement jamais joué est traité comme une **inconnue
à 60/100**, et non comme une catastrophe : sinon le conseil ne quitterait jamais le mouvement le
plus facile. À besoin égal, la figure la plus douce passe devant. Les figures expert sont exclues :
elles sont au niveau 6 exprès, ce n'est pas du travail de fond.

Le mouvement retenu décide de la suite : s'il existe un exercice pour lui (onglet « Mouvements »),
la carte propose l'exercice, au premier palier de vitesse pas encore réussi — **c'est le chaînon qui
manquait entre apprendre un geste et l'utiliser en situation**. Sinon elle propose une session
d'entraînement, sur le sport où ce mouvement a donné le plus mauvais score (pour qu'il y ait un
score à battre), ou à défaut sur le sport le plus joué.

Sur la sauvegarde réelle (24 sessions), le classement produit :

| mouvement | sessions | moyenne | besoin |
| --- | ---: | ---: | ---: |
| **dévoilement** | 1 | 51 | **69** |
| jamais joués (poursuite, les 4 exercices) | 0 | — | 64 |
| face au sujet | 2 | 72 | 44 |
| orbite | 5 | 74 | 30 |
| suivi latéral | 12 | 71 | 29 |
| survol rapide | 1 | 94 | 26 |

Vérifié aussi sur des sauvegardes fabriquées : joueur neuf → poursuite arrière niveau 3 ; joueur qui
ne fait que du latéral et le réussit → poursuite arrière (le seul mouvement facile jamais touché) ;
joueur faible en vertical tilt → l'exercice vertical tilt, sujet immobile.

Reste à faire : **D2** (des paliers par sport) et **D3**, décrits plus bas.

---

## 1. Ce qui a été mesuré

### Temps d'exécution, vue du drone, 1080p, qualité Haute

| Niveau | GPU ms | CPU ms | i/s | draw calls | primitives |
| --- | ---: | ---: | ---: | ---: | ---: |
| ski_alpin | 3,19 | 0,69 | 257 | 581 | 421 k |
| ski_descente | 3,76 | 0,93 | 213 | 838 | 2 488 k |
| ski_freeride | 3,64 | 0,60 | 236 | 398 | 1 594 k |
| trail | 4,92 | 0,90 | 172 | 599 | 2 571 k |
| **circuit_course** | **5,82** | **1,26** | **141** | **1 256** | **5 755 k** |
| departementale | 4,92 | 0,92 | 171 | 571 | 1 655 k |
| **exercice (orbite)** | 2,38 | 0,28 | 377 | **967** | 570 k |

Moyenne sur les images 120 à 520, après compilation des shaders.

### Attente réelle entre LANCER et une session jouable

| Niveau | 1er lancement | 2e lancement | pire image |
| --- | ---: | ---: | ---: |
| ski_alpin | 2,43 s | 0,80 s | **941 ms** |
| **circuit_course** | **3,28 s** | **2,06 s** | 82 ms |
| ski_freeride | 1,42 s | 1,47 s | 50 ms |
| departementale | 1,41 s | 1,00 s | 73 ms |
| exercice (orbite) | 0,75 s | 0,77 s | 4 ms |

### Construction de la scène, sans GPU

| Niveau | total | dont plan du drone | nœuds | MeshInstance | MultiMesh | instances |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| ski_alpin | 700 ms | 15 | 1 723 | 78 | 1 588 | 4 947 |
| ski_descente | 665 ms | 25 | 4 392 | 147 | **4 173** | 17 415 |
| ski_freeride | 800 ms | 20 | 2 649 | **855** | 1 729 | 4 824 |
| circuit_course | 909 ms | 63 | 4 060 | 896 | 3 124 | 56 279 |
| departementale | 437 ms | 29 | 4 072 | 686 | 3 285 | 48 626 |
| exercice | 311 ms | 21 | 677 | 137 | 508 | 1 229 |

### Le circuit, phase par phase

```
CircuitLayout.new()   112 ms      _barriers       110 ms
_terrain              216 ms      _vegetation      55 ms
_surface               56 ms      _structures      44 ms
_kerb_zones / _stand_zones / _pit_complex : 3 ms en tout
```

Soit ~600 ms identifiés sur 1 383 ms : le reste est le tronc commun (masque du sol, herbe, décor
lointain, public, plan du drone).

---

## 2. Ce que disent ces chiffres

**Le planificateur de drone n'est pas un problème.** 15 à 63 ms sur des scènes qui en prennent 300
à 900. C'est la partie la plus élaborée du code et la moins chère ; inutile d'y toucher.

**Le pire moment du jeu est une image à 941 ms**, au premier lancement d'un niveau. Ce n'est pas du
calcul, c'est la compilation des shaders au moment où le premier objet de chaque matériau entre
dans le champ. Le cache fait déjà 51,7 Mo et 254 fichiers, donc cela ne se produit qu'une fois par
matériau et par machine — mais c'est la première impression de chaque nouveau niveau.

**Le circuit est deux fois plus cher que tout le reste**, au chargement comme à l'exécution : 2,06 s
même au deuxième lancement, 1 256 draw calls, 5,7 M de primitives. Il est aussi le seul dont le
coût ne baisse pas d'un lancement à l'autre, parce qu'il reconstruit intégralement sa géométrie.

**4 173 MultiMeshInstance pour 17 415 instances** (ski_descente) : 4 instances par lot. Un MultiMesh
existe pour regrouper des instances en un seul appel de rendu ; à 4 par lot il n'apporte presque
rien. La cause est dans `Vegetation.place()` : les arbres sont rangés par **chunk de 64 m × 3
variantes × 2 niveaux de détail**, soit six lots par chunk occupé. Le découpage sert au culling et
au LOD, et il fonctionne (à l'écran il ne reste que 400 à 850 draw calls), mais la granularité est
trop fine d'un facteur 3 à 4.

**L'exercice est le pire rapport coût / contenu du jeu** : 967 draw calls et 1 572 objets pour une
prairie vide avec un coureur. C'est mon `EnvDrill` qui sème jusqu'à 900 arbres et 1 200 buissons sur
un terrain de 420 × 1 300 m dont le joueur ne voit qu'un disque de 60 m.

**36 `StandardMaterial3D.new()` répartis dans 22 fichiers, 14 blocs de code MultiMesh identiques
dans 13 fichiers, `_mat()` réécrit dans 7 fichiers.** Deux matériaux identiques créés séparément
sont deux ressources distinctes pour le moteur : elles cassent le regroupement des appels de rendu
et s'ajoutent au temps de construction. Seuls `car_model.gd` et `archetype_registry.gd` ont un cache.

---

## 3. Ce que je changerais, par rapport valeur / effort

### A. Les trois qui valent vraiment le coup

**A1 — Préchauffer les shaders pendant l'écran de chargement.** Supprime le gel de 941 ms, qui est
le défaut le plus visible du jeu. L'écran de chargement existe déjà (`LoadingScreen.run`) : il
suffit d'y faire rendre une image hors écran avant de céder la main. Gain : 0,9 s sur chaque premier
lancement d'un niveau, et la fin des à-coups des premières secondes.

**A2 — Mettre en cache le `CircuitLayout`.** Il est entièrement déterministe pour un couple
(échelle, pas) : même tracé, même grille, même champ de hauteur à chaque fois. Il est aujourd'hui
reconstruit à chaque session **et** par le bac à sable. Un cache statique économise 112 ms par
lancement, et surtout ouvre la voie à A3.

**A3 — Alléger le terrain du circuit** (216 ms, la plus grosse phase nommée, et une bonne part des
5,7 M de primitives). Le maillage est généré à une densité uniforme sur toute l'emprise ; le joueur
ne voit jamais le sol à plus de quelques centaines de mètres de la piste.

Ensemble, A1 à A3 devraient ramener le circuit sous la seconde au deuxième lancement et supprimer le
gel initial partout.

### B. Les trois faciles et sûres

*(B1, B2 et B3 ont été traités : voir la section 0 bis. B1 et B2 sont faits, B3 a été mesuré puis
abandonné — élargir les chunks économise des appels de rendu et coûte du temps GPU.)*

### C. Rangement du code, sans gain de performance

`movement_planner.gd` (1 122 lignes), `circuit_scenery.gd` (910), `env_downhill.gd` (907) sont les
trois fichiers qui mériteraient d'être coupés. Le dédoublonnage de `_multimesh` / `_mat` / `_quad`
va dans le même sens. À faire **après** A et B, et seulement si le code gêne : rien de tout cela ne
se voit à l'écran.

### D. Le gameplay : c'est là que manque le plus

Le relevé des 24 sessions jouées est plus parlant que n'importe quelle mesure technique :

| Mouvement | sessions | moyenne |
| --- | ---: | ---: |
| lateral | 12 | 71 |
| orbit | 5 | 74 |
| frontal | 2 | 72 |
| approach_orbit | 2 | 60 |
| flyby | 1 | 94 |
| choreo | 1 | 77 |
| reveal | 1 | **51** |

**La moitié des sessions sont des suivis latéraux.** 36 meilleurs scores enregistrés pour une
matrice de 8 sports × 9 mouvements × 6 niveaux × 4 optiques, soit plus de 1 700 combinaisons : 2 %
d'exploration. Ce n'est pas un défaut du joueur, c'est qu'aucun écran ne dit quoi jouer ensuite.

Trois propositions, de la plus simple à la plus ambitieuse :

1. ~~**« À travailler »** sur l'accueil~~ — **fait**, voir la section 0 ter.
2. **Un objectif par sport** : trois paliers (par exemple 70 / 85 / 95 sur trois mouvements
   différents) qui donnent une raison de revenir. Les scores nécessaires sont déjà stockés.
3. **Lier les exercices à l'entraînement** : les « Mouvements » sont déjà une échelle de difficulté
   propre (5 figures × 4 vitesses). Un mauvais score sur une orbite en session pourrait renvoyer
   vers l'exercice d'orbite correspondant. C'est le chaînon qui manque entre apprendre un geste et
   l'utiliser en situation.

---

## 4. Ce que je n'ai pas mesuré

- La performance en 4K, l'écran du joueur. Les chiffres ci-dessus sont en 1080p ; le GPU y est à peu
  près quadruplé, ce qui placerait le circuit autour de 23 ms (≈ 43 i/s) dans le pire cas si la
  charge était purement pixellaire — elle ne l'est pas, et un relevé antérieur donnait 90-120 i/s en
  4K. À refaire sur la vraie résolution avant de conclure quoi que ce soit sur le 4K.
- Le mode 2 joueurs et le bac à sable (deux caméras, plus de trafic).
- Le flou de mouvement, désactivé pendant les mesures.
- La mémoire et le temps de démarrage de l'application elle-même.

## 5. Refaire les mesures

Quatre scripts `SceneTree` temporaires, lancés comme décrit dans la note de test du projet :

- **temps de construction et contenu des scènes** : pour chaque fiche du catalogue, construire la
  scène, chronométrer, puis parcourir l'arbre en comptant nœuds, `MeshInstance3D`,
  `MultiMeshInstance3D`, instances et triangles (`surface_get_arrays`).
- **coût GPU** : fenêtré, vsync coupée, `viewport_set_measure_render_time`, puis moyenne de
  `viewport_get_measured_render_time_gpu/_cpu` et de `get_rendering_info(...)` sur les images 120 à
  520, caméra du drone visée sur le sujet.
- **attente au lancement** : fenêtré, chronométrer `instantiate()` + `add_child()`, puis la durée de
  chacune des 90 images suivantes (le maximum donne le gel de compilation). Deux passes pour
  séparer le premier lancement du second.
- **phases du circuit** : instancier un `CircuitScenery` sur un `CircuitLayout` déjà construit et
  chronométrer `_terrain`, `_surface`, `_barriers`, `_vegetation`… un par un.

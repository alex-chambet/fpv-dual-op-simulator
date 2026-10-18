# Graphismes

Tout le décor est généré par le code au lancement d'une session : les textures sont des bruits procéduraux et les
formes (arbres, rochers, voitures, maisons, spectateurs) sont construites en géométrie. Seul le mannequin animé des
athlètes est un modèle importé (voir « Athlètes »). Les fichiers sont dans `scenarios/graphics/`.

## Qualité graphique (menu Pause > Graphismes)

Le niveau est enregistré dans `user://menu_prefs.json` (clé `quality`) et peut être changé en jeu.

| Niveau  | Anticrénelage | Ombres                 | Occlusion ambiante | Lumière indirecte (SSIL) | Herbe 3D           | Arbres détaillés jusqu'à |
|---------|---------------|------------------------|--------------------|--------------------------|--------------------|--------------------------|
| Basse   | FXAA          | dures, 2 cascades      | non                | non                      | non                | 60 m                     |
| Moyenne | SMAA          | douces                 | basse              | non                      | 2 touffes/m², 70 m | 110 m                    |
| Haute   | SMAA          | douces, 4 cascades     | moyenne            | non                      | 4 touffes/m², 100 m| 170 m                    |
| Ultra   | SMAA          | douces, carte 8192     | haute              | oui                      | 5,5 touffes/m², 130 m | 260 m                 |

Mesures en 4K plein écran sur RTX 4070 portable (sans flou de mouvement) : Basse ≈ 210 i/s, Haute ≈ 90 à 120 i/s,
Ultra ≈ 45 à 55 i/s.

Coût des deux ajouts d'octobre 2026, mesurés sur le circuit en Haute, 4K plein écran, sans vsync
(`viewport_get_measured_render_time_gpu`, moyenne sur 600 images) :

| Configuration | GPU / image | Écart |
|---|---|---|
| Ni l'un ni l'autre | 13,66 ms | référence |
| Détail photographié des sols seul | 14,03 ms | **+0,37 ms** (+2,7 %) |
| Profondeur de champ seule | 16,72 ms | **+3,06 ms** (+22 %) |
| Les deux | 17,32 ms | +3,66 ms |

La profondeur de champ est une passe plein écran : **le niveau de bokeh n'y change rien** (17,15 ms en « boîte »
contre 17,32 en « hexagone » — mesuré). Les seuls leviers sont donc l'échelle de rendu et l'interrupteur, et le
coût baisse avec la résolution. Elle est **éteinte dans le préréglage Basse**, allumée à partir de Moyenne, et
reste décochable dans Image.

En Ultra seulement, la forêt a des **rayons de lumière** entre les arbres (brouillard volumétrique éclairé par le
soleil, `light_shafts` dans le style, environ +2 ms par image). Le nombre de spectateurs et la neige qui tombe
dépendent aussi du niveau.

## Tous les réglages (Paramètres > Graphismes, ou Échap > Graphismes en jeu)

Enregistrés dans `user://menu_prefs.json` (clé `graphics`), appliqués tout de suite (`scenarios/graphics/graphics_settings.gd`,
panneau commun `ui/graphics_panel.gd`).

| Groupe | Réglages |
|---|---|
| Affichage | mode (plein écran, fenêtre sans bordure, fenêtre), synchro verticale, limite d'images/s (30 à 240 ou aucune), échelle de rendu de 50 à 100 % (agrandissement AMD FSR 1 : le texte et le cadre restent nets) |
| Qualité | préréglage Basse / Moyenne / Haute / Ultra, puis chaque détail à part (le préréglage affiche alors « Personnalisé ») : anticrénelage (aucun, FXAA, SMAA, TAA), filtrage des textures, ombres (désactivées à ultra), occlusion ambiante, lumière indirecte, rayons de lumière en forêt, distance des arbres détaillés, herbe et petits détails, spectateurs (ces deux derniers à la session suivante) |
| Image | luminosité (±1 IL), contraste, saturation, vignettage, aberration chromatique, grain, flou de mouvement, **profondeur de champ**, **exposition automatique** |
| Interface en jeu | opacité et taille des infos, opacité du cadre, couleurs du cadre (néon, daltonisme bleu / jaune / vermillon, contraste élevé) |

## La caméra

Le jeu apprend à **filmer**, donc la caméra est simulée comme une caméra, pas comme une caméra de jeu vidéo.

### Profondeur de champ (`scenarios/graphics/lens_focus.gd`)

Ce n'est pas un flou décoratif : ce sont les **vraies limites de netteté** de l'optique choisie, à f/2, sur le
capteur qu'implique le champ de vision du jeu (60° vertical à 24 mm ⇒ 27,7 mm de haut, donc le cercle de confusion
du plein format, 0,03 mm). Hyperfocale H = f²/(N·c) + f, puis les limites proche et lointaine habituelles.

| Focale | Hyperfocale | Net à 8 m | Net à 15 m | Net à 40 m |
|---|---|---|---|---|
| 24 mm | 9,6 m | 4,4 – 47,3 m | 5,9 m – ∞ | 7,7 m – ∞ |
| 35 mm | 20,5 m | 5,8 – 13,1 m | 8,7 – 56,2 m | 13,5 m – ∞ |
| 50 mm | 41,7 m | 6,7 – 9,9 m | 11,0 – 23,4 m | 20,4 – 971 m |
| 85 mm | 120,5 m | 7,5 – 8,6 m | 13,3 – 17,1 m | 30,0 – 59,8 m |

C'est **la vraie raison de changer d'optique** : à 85 mm le sujet se détache du fond, à 24 mm tout est net à partir
de 6 m et rien ne se détache jamais. La mise au point suit le sujet comme un pointeur suit sa molette — elle est
*tirée*, pas collée, donc un changement de distance brusque passe par un instant de flou, comme sur un plateau.
Au bac à sable il n'y a pas de sujet : la mise au point suit le sol au centre de l'image (rayon marché contre le
relief). La qualité du bokeh suit le préréglage (boîte en Basse, cercle en Ultra).

### Exposition automatique

Le diaphragme automatique d'une caméra, qui met un instant à rattraper quand on panote du sol vers le ciel.
**Désactivée par défaut** : un opérateur de drone verrouille son exposition, et une image qui se rééquilibre sans
arrêt masque les erreurs de cadrage au lieu de les montrer.

### Angle d'obturation (`ui/motion_blur.gd`)

Le flou de mouvement est celui du **temps de pose**, pas du temps d'image : la même image à 60 ou à 144 i/s. Les
libellés donnent l'angle, parce que c'est comme ça qu'on le règle sur une caméra (angle = 360 × pose × cadence) :
1/120 s est un obturateur à 180° pour une livraison en 60 i/s, 1/60 s pour une livraison en 30 i/s — la règle des
180°, celle qui donne au cinéma son mouvement.

## Ce qui compose une scène

- **Ambiance** (`ambience.gd`) : chaque session tire une ambiance (ou prend celle choisie dans le menu, ligne
  « Ambiance ») : plein jour, matin (soleil bas, léger voile), fin de journée (soleil rasant orangé, ombres longues),
  couvert (ciel gris, lumière diffuse), chute de neige (couvert + flocons autour de la caméra, terrains enneigés
  seulement). L'ambiance est enregistrée avec la session : un replay a la même lumière.
- **Ciel** (`game_sky.gd`) : dégradé du style, soleil avec halo, nuages éclairés par le soleil. Rendu AgX (plus
  proche d'une caméra que l'ancien Filmic). Couverture nuageuse par décor : `cloud_coverage` dans les fichiers de
  style (`scenarios/environments/styles/*.tres`).

  **Un ciel photographié (HDRI) a été essayé et écarté** (octobre 2026). Une HDRI 2K de Poly Haven
  (`aristea_wreck_puresky`, 5,3 Mo) a été câblée comme `PanoramaSkyMaterial`, avec le soleil replacé là où l'image
  a le sien (point le plus brillant, inversion de la projection équirectangulaire). Résultat mesuré :
  - soleil de l'HDRI appliqué → image délavée, ombres contredisant le modelé réglé par le style ;
  - énergie corrigée et soleil du jeu conservé → équivalent, pas meilleur ;
  - **à l'horizon, là où le drone regarde, l'HDRI donne une bande grise plate** là où le shader a un dégradé et des
    nuages — le brouillard du style (`fog_sky_affect`) écrase ce qui restait.

  Coût refusé : 5 fichiers (un par ambiance) ≈ 27 Mo, soit trois fois tout le reste des assets, plus la perte du
  réglage de couverture nuageuse et des teintes par ambiance. Le ciel peint est accordé à l'exposition, au
  brouillard et aux couleurs de chaque ambiance ; une panoramique se bat contre les trois.
- **Sols** (`ground_materials.gd`) : herbe / herbe sèche / terre / roche selon la pente (sur les parois de vallée :
  contreforts et creux, strates, coulées sombres, vires herbeuses), parcelles agricoles (blé, colza, labours, chaumes,
  jeunes cultures, avec rangs, passages de tracteur, tournières et zones plus ou moins mûres) sur la départementale, neige damée (sillons de dameuse) ou poudreuse,
  asphalte (traces de roues, rustines, fissures, bord qui s'effrite), peinture usée, **dégagement de circuit**
  (asphalte scellé gris posé par lots, fissuré, chaussé de gravillons, peint en vert vers ses bords et usé par les
  voitures qui passent dessus), gravier, sentier de terre.
  La neige garde son relief jusqu'à l'horizon : le dégradé bleuté des creux et le grain de surface s'estompent sur
  220 m au lieu de 45, de sorte qu'une grande face ne devient pas un aplat blanc au fond. Les seuils des masques de
  roche s'élargissent avec la distance (`soft` dans `ground_materials.gd`) : au loin, une transition large remplace le
  pixel par pixel qui scintillait sous forme de poivre et sel.
  Même famille de problème sur le **gravier** (dégagements, accotements) : sa couleur venait d'**une seule** lecture du
  bruit de détail, qui se répète avec sa texture — une tuile de 1,4 m, sur une surface qui remplit le cadre, se lit
  comme un quadrillage régulier dès une vingtaine de mètres. Elle en prend maintenant **deux, écartées d'un tiers de
  décade** (0,7 et 0,203 tuile/m), ce qui supprime la répétition. Et ses cailloux (bruit cellulaire) sont passés à leur
  taille réelle, 3 cm : échantillonnés six fois plus fin ils passaient sous le pixel dès 2 m et se moyennaient en gris
  uni partout, donc ils ne cassaient rien ; à leur vraie taille ils doivent disparaître **avant** de repasser sous le
  pixel, d'où un fondu propre entre 8 et 26 m au lieu du fondu lointain du reste de la surface.
- **Détail photographié des sols** (`assets/ground/`) : par-dessus la couleur procédurale, une couche de détail
  tirée de trois sets PBR **CC0 d'ambientCG** (asphalte, neige, herbe ; voir
  `assets/ground/LICENSE_ambientCG_CC0.txt`). Chacun est empaqueté dans une seule image RGBA 512 × 512 — R
  variation d'albédo centrée, G rugosité, BA normale XY — soit 2,4 Mo et **une seule lecture de texture** par pixel
  de sol. C'est une couche de *détail*, pas un remplacement : elle fait varier ce que la couleur procédurale a déjà
  décidé, donc les teintes des styles et des ambiances continuent de fonctionner. Elle s'efface entre 35 et 110 m.
  L'intérêt est la **corrélation** : un bruit donne un albédo et une normale qui n'ont rien à voir l'un avec
  l'autre, ce qui se lit comme du flou ; une photo donne un caillou dont la bosse et le côté sombre sont le même
  caillou.
  Deux choses mesurées en l'implémentant, qui valent d'être sues :
  - Les coordonnées sont celles du **monde**, et sur le circuit elles montent à 600 m. Un UV flottant à 600 a perdu
    assez de précision pour que le gradient qu'en déduit la carte graphique soit faux : elle prend alors le plus
    petit mip et la texture s'aplatit en gris uni. D'où `detail_tap()`, qui ramène la coordonnée près de zéro et
    passe le gradient explicitement (`textureGrad`).
  - L'échelle n'est pas « celle à laquelle la photo a été prise » mais **ce qui est résolvable d'où vole le drone**.
    À une tuile par mètre, le granulat de l'asphalte passe sous le pixel dès 5 m et se moyenne en gris : mesuré, pas
    supposé. Les échelles de `PBR` sont donc plus larges que la taille réelle.
  - Verdict honnête : **net sur la neige** (elle a enfin une croûte, c'est la plus grande surface de trois sports
    sur cinq), **marginal sur l'asphalte** — le shader procédural y faisait déjà beaucoup, et de l'asphalte à 10 m
    *est* gris uniforme.
- **Masque du sol** (`ground_mask.gd`) : carte vue de dessus des routes, sentiers, accotements et de la piste damée,
  lue par les shaders (pas d'herbe sur la route, pas de champ au bord de la route, piste damée sous le skieur).
- **Herbe 3D** (`grass_field.gd`) : une grille de touffes qui suit la caméra, posée par la carte graphique sur le
  relief, avec les couleurs du sol, des fleurs sauvages, les cultures des champs ; elle ondule au vent.
- **Arbres** (`vegetation.gd`) : épicéas (étages de branches couvertes d'aiguilles) et feuillus (tronc, branches,
  bouquets de feuilles), lumière à travers les feuilles en contre-jour, neige sur les branches en montagne ; des
  rafales de vent traversent la forêt. Ils gardent
  exactement la taille utilisée par le calcul « sujet caché ». Un modèle simple remplace le détaillé au loin.
- **Petit décor** (`decor.gd`, `rocks.gd`) : fougères, buissons, haies, troncs couchés, souches, pierres et rochers
  (mousse en forêt).
- **Bâtiments et équipements** (`buildings.gd`, `car_model.gd`) : fermes variées (crépi ou moellons, toit à deux ou
  quatre pans, tuiles canal ou ardoises, volets peints, cheminée, annexe basse, jardin clos d'une barrière en bois ou
  d'un muret, cour en herbe, grange en L), granges, ligne électrique avec fils, bornes kilométriques ; voitures carrossées (peinture vernie, vitres, phares,
  feux, jantes) pour le sujet et le trafic ; colline et portails du tunnel ; sur les pistes de ski : jalons de piste,
  filets orange, télésiège.
  La carrosserie est **loftée par sections** : `CORNER_STEPS` points par coin d'une section (5, contre 3 avant —
  à 3 on voyait les facettes de l'épaulement dès 10 m) et une **roue en tonneau** de `WHEEL_SIDES` côtés (28, contre
  16 : une roue est la seule chose parfaitement ronde de l'image et le drone passe à quelques mètres), dont la bande
  de roulement s'arrondit vers les flancs au lieu de finir sur une arête. Une voiture reste à quelques milliers de
  triangles, donc les neuf du circuit libre ne coûtent rien.

  **Un modèle GT3 importé a été cherché, essayé et écarté** (octobre 2026). Il n'existe pas de GT3 en CC0 : la
  catégorie est entièrement sous marque déposée, et les modèles « GT3 » gratuits trouvés sont CC-BY (Sketchfab) ou
  sous licence d'usage restreinte. Les trois meilleurs candidats réellement CC0 et téléchargeables ont été importés,
  mis à l'échelle d'une GT3 (4,60 m) et rendus côte à côte avec la voiture du jeu, même sol, même ciel, même soleil :

  | Modèle | Longueur d'origine | Triangles | Verdict |
  |---|---|---|---|
  | `CarModel.race()` (le jeu) | 4,77 × 2,26 × 1,34 m | 3 928 | référence |
  | Kenney *race* | **2,56 m** (×1,80 pour atteindre 4,6) | 1 952 | monoplace de dessin animé, roues énormes |
  | Kenney *sedan-sports* | **2,55 m** (×1,80) | 2 088 | compacte de dessin animé, pas une voiture de course |
  | Quaternius *RaceCar* | 4,91 m (×0,94) | 1 876 | bonne échelle, mais facetté et sans texture dans l'OBJ |

  Une GT3 réelle fait 4,60 × 2,05 × 1,19 m : la voiture du jeu en est à 4 % près en longueur. Les deux Kenney sont
  à l'échelle jouet et leurs proportions sont volontairement caricaturales ; le Quaternius est à la bonne taille
  mais deux fois moins détaillé, et son export OBJ a perdu la texture. Aucun des trois ne vaut le corps
  paramétrique — qui a en plus l'avantage de se décliner (berline, compacte, coupé de course) et de suivre le
  terrain. *Si un jour il faut vraiment une GT3, il faudra la modéliser dans Blender, pas la télécharger.*
- **Horizon** (`far_scenery.gd`) : le relief continue au-delà de la zone de jeu (champs et bosquets, forêt, vallée
  glaciaire) et se termine sur une chaîne de collines ou de montagnes enneigées (massifs, arêtes, strates). Une nappe
  de forêt dense couvre les versants lointains.
- **Athlètes** (`scenarios/subjects/athlete_model.gd`) : skieurs, coureurs et vététistes sont un mannequin articulé et
  animé : position de ski et recherche de vitesse avec skis, bâtons, casque et masque ; foulée qui passe de la marche
  au sprint selon la vitesse, avec casquette et dossard ; pédalage sur un VTT détaillé (roue libre au-delà de
  30 km/h). Le mannequin vient de la « Universal Animation Library » de **Quaternius**, sous licence **CC0** (domaine
  public) : `assets/characters/LICENSE_Quaternius_CC0.txt`.
- **Face de freeride** (`env_freeride.gd`) : roche vue de tous les côtés (strates, fissures, relief) sur les falaises et les parois de couloir, roche apparente peinte par l'environnement le long des barres rocheuses, sur les îlots et sur les crêtes des arêtes de neige, affleurements qui strient le versant au-delà de la face (jamais sur la ligne du skieur), vieilles traces de skieurs dans la poudreuse, skis en travers et nuage de neige à chaque dérapage (fin de virage, virage de contrôle, arrêt), nuage de poudreuse à chaque réception.
- **Circuit** (`scenarios/circuit/circuit_scenery.gd`) : vrais vibreurs en relief (pente puis joue verticale, bandes
  rouges et blanches d'un mètre) aux cordes et aux sorties, trace de gomme sombre de la trajectoire de course sur
  l'asphalte, murs de pneus là où le dégagement est le plus large. Les rails suivent le bord du dégagement, lissés et
  à pente bornée pour ne jamais couper la piste dans une épingle, et les **grillages pare-débris ne sont montés que
  devant les tribunes et la ligne des stands** — ailleurs il n'y a que le rail, comme sur le vrai circuit. La largeur
  du dégagement appartient à `CircuitLayout`, donc le terrain s'aplanit exactement dessous.
- **Terrain d'exercice** (`env_drill.gd`) : prairie vallonnée dont les décors ne peuvent jamais passer entre la caméra
  et le sujet (voir [mouvements.md](mouvements.md)).
- **Public** (`crowd.gd`) : sur la descente et à l'arrivée du freeride, des spectateurs (veste de ski, bonnet à pompon) se massent aux sauts, dans
  quelques virages et à l'arrivée, derrière les filets, avec des drapeaux nationaux qui flottent et des banderoles
  publicitaires (marques inventées). Ils lèvent les bras et sautent quand le skieur arrive. Ils restent en dehors du vol
  du drone et des lignes de vue.
- **Look caméra** (`ui/camera_look.gd`) : vignettage de l'objectif, légère aberration chromatique vers les bords et
  grain, comme sur une vraie caméra.

Ce qui peut cacher le sujet (arbres, haies, rochers) reste écarté des lignes de vue prévues par la session : les
nouveaux éléments décoratifs ne changent pas la difficulté ni le score.

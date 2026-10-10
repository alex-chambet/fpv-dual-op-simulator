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

En Ultra seulement, la forêt a des **rayons de lumière** entre les arbres (brouillard volumétrique éclairé par le
soleil, `light_shafts` dans le style, environ +2 ms par image). Le nombre de spectateurs et la neige qui tombe
dépendent aussi du niveau.

## Ce qui compose une scène

- **Ambiance** (`ambience.gd`) : chaque session tire une ambiance (ou prend celle choisie dans le menu, ligne
  « Ambiance ») : plein jour, matin (soleil bas, léger voile), fin de journée (soleil rasant orangé, ombres longues),
  couvert (ciel gris, lumière diffuse), chute de neige (couvert + flocons autour de la caméra, terrains enneigés
  seulement). L'ambiance est enregistrée avec la session : un replay a la même lumière.
- **Ciel** (`game_sky.gd`) : dégradé du style, soleil avec halo, nuages éclairés par le soleil. Rendu AgX (plus
  proche d'une caméra que l'ancien Filmic). Couverture nuageuse par décor : `cloud_coverage` dans les fichiers de
  style (`scenarios/environments/styles/*.tres`).
- **Sols** (`ground_materials.gd`) : herbe / herbe sèche / terre / roche selon la pente (sur les parois de vallée :
  contreforts et creux, strates, coulées sombres, vires herbeuses), parcelles agricoles (blé, colza, labours, chaumes,
  jeunes cultures, avec rangs, passages de tracteur, tournières et zones plus ou moins mûres) sur la départementale, neige damée (sillons de dameuse) ou poudreuse,
  asphalte (traces de roues, rustines, fissures, bord qui s'effrite), peinture usée, gravier, sentier de terre.
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
- **Horizon** (`far_scenery.gd`) : le relief continue au-delà de la zone de jeu (champs et bosquets, forêt, vallée
  glaciaire) et se termine sur une chaîne de collines ou de montagnes enneigées (massifs, arêtes, strates). Une nappe
  de forêt dense couvre les versants lointains.
- **Athlètes** (`scenarios/subjects/athlete_model.gd`) : skieurs, coureurs et vététistes sont un mannequin articulé et
  animé : position de ski et recherche de vitesse avec skis, bâtons, casque et masque ; foulée qui passe de la marche
  au sprint selon la vitesse, avec casquette et dossard ; pédalage sur un VTT détaillé (roue libre au-delà de
  30 km/h). Le mannequin vient de la « Universal Animation Library » de **Quaternius**, sous licence **CC0** (domaine
  public) : `assets/characters/LICENSE_Quaternius_CC0.txt`.
- **Public** (`crowd.gd`) : sur la descente, des spectateurs (veste de ski, bonnet à pompon) se massent aux sauts, dans
  quelques virages et à l'arrivée, derrière les filets, avec des drapeaux nationaux qui flottent et des banderoles
  publicitaires (marques inventées). Ils lèvent les bras et sautent quand le skieur arrive. Ils restent en dehors du vol
  du drone et des lignes de vue.
- **Look caméra** (`ui/camera_look.gd`) : vignettage de l'objectif, légère aberration chromatique vers les bords et
  grain, comme sur une vraie caméra.

Ce qui peut cacher le sujet (arbres, haies, rochers) reste écarté des lignes de vue prévues par la session : les
nouveaux éléments décoratifs ne changent pas la difficulté ni le score.

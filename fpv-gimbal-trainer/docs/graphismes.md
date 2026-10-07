# Graphismes

Tout le décor est généré par le code au lancement d'une session, sans aucun modèle 3D importé : les textures sont des
bruits procéduraux et les formes (arbres, rochers, voitures, maisons) sont construites en géométrie. Les fichiers sont
dans `scenarios/graphics/`.

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

## Ce qui compose une scène

- **Ciel** (`game_sky.gd`) : dégradé du style, soleil avec halo, nuages éclairés par le soleil. Rendu AgX (plus
  proche d'une caméra que l'ancien Filmic). Couverture nuageuse par décor : `cloud_coverage` dans les fichiers de
  style (`scenarios/environments/styles/*.tres`).
- **Sols** (`ground_materials.gd`) : herbe / herbe sèche / terre / roche selon la pente, parcelles agricoles (blé,
  colza, labours, chaumes, jeunes cultures) sur la départementale, neige damée (sillons de dameuse) ou poudreuse,
  asphalte (traces de roues, rustines, fissures, bord qui s'effrite), peinture usée, gravier, sentier de terre.
- **Masque du sol** (`ground_mask.gd`) : carte vue de dessus des routes, sentiers, accotements et de la piste damée,
  lue par les shaders (pas d'herbe sur la route, pas de champ au bord de la route, piste damée sous le skieur).
- **Herbe 3D** (`grass_field.gd`) : une grille de touffes qui suit la caméra, posée par la carte graphique sur le
  relief, avec les couleurs du sol, des fleurs sauvages, les cultures des champs ; elle ondule au vent.
- **Arbres** (`vegetation.gd`) : épicéas (étages de branches couvertes d'aiguilles) et feuillus (tronc, branches,
  bouquets de feuilles), lumière à travers les feuilles en contre-jour, neige sur les branches en montagne. Ils gardent
  exactement la taille utilisée par le calcul « sujet caché ». Un modèle simple remplace le détaillé au loin.
- **Petit décor** (`decor.gd`, `rocks.gd`) : fougères, buissons, haies, troncs couchés, souches, pierres et rochers
  (mousse en forêt).
- **Bâtiments et équipements** (`buildings.gd`, `car_model.gd`) : fermes (crépi, tuiles, volets peints, cheminée),
  granges, ligne électrique avec fils, bornes kilométriques ; voitures carrossées (peinture vernie, vitres, phares,
  feux, jantes) pour le sujet et le trafic ; colline et portails du tunnel ; sur les pistes de ski : jalons de piste,
  filets orange, télésiège.
- **Horizon** (`far_scenery.gd`) : le relief continue au-delà de la zone de jeu (champs et bosquets, forêt, vallée
  glaciaire) et se termine sur une chaîne de collines ou de montagnes enneigées.

Ce qui peut cacher le sujet (arbres, haies, rochers) reste écarté des lignes de vue prévues par la session : les
nouveaux éléments décoratifs ne changent pas la difficulté ni le score.

# Merge `dev` → `main` — récap des 10 et 11 novembre 2026

5 commits sur `dev`, 24 fichiers touchés (+825 / −171), partis de `main` (`9964d39`).
`main` n'a rien reçu depuis : le merge est un **fast-forward**, sans conflit possible.

| Commit | Date | Sujet |
|---|---|---|
| `1cdc214` | 10/11 18:10 | Corrected graphics bugs |
| `ee6d58b` | 10/11 22:56 | Updated graphism |
| `4f2bbf5` | 10/11 23:15 | Updated steepness of freeride level (en réalité : le ski de **descente**) |
| `43851e4` | 10/11 23:20 | Check if version is up to date |
| `1e44810` | 11/11 09:09 | New drone view incrustation |

## 1. Voitures : suspension et roues (`1cdc214`)

- Nouveau `animate_car()` dans `subject_archetype.gd`, partagé par toutes les voitures : la caisse roule vers
  l'**extérieur** du virage, plonge au freinage, s'accroupit à l'accélération ; les roues avant braquent selon
  l'empattement (2,62 m) ; les feux arrière s'allument au freinage. Les roues restent sur la route (seul le châssis bouge).
- `car_model.gd` : `chassis()` et `own_tail_lights()` (un matériau par feu pour qu'ils s'allument séparément),
  vitres et pare-brise redessinés par style de carrosserie.
- `circuit.gd` perd son code de tangage maison, remplacé par `animate_car()`. `placeholder_model.gd` branche le châssis
  et les feux sur les voitures de décor.
- **Circuit** : `ground()` n'est plus « creusé » sous la route ; le terrain dessiné utilise le nouveau
  `terrain_height()`. Avant, les voitures roulaient 40 cm sous l'asphalte.

## 2. Skieur habillé, neige, ambiances (`ee6d58b`, `1cdc214`)

- `athlete_model.gd` : le mannequin nu est habillé en ski (veste, pantalon, moufles, manchettes de chaussures,
  dossard blanc devant et derrière pour repérer le skieur). Casque intégral avec masque. Articulations d'une
  teinte plus sombre que la combinaison.
- `glisse_pente.gd` : traces de ski posées dans le sens réel de la glisse (deux rainures continues au lieu d'une
  rangée de tirets, et visibles au-dessus de la neige), poudreuse en bouffées douces qui gonflent.
- `ambience.gd` : plus de lumière d'ambiance en fin de journée et en « golden » (une route à l'ombre de sa vallée
  était un écran noir).

## 3. Ski de descente refait (`4f2bbf5`)

Voir [docs/ski_descente.md](fpv-gimbal-trainer/docs/ski_descente.md) (nouveau), qui contient les mesures avant / après.
En bref : mur de départ à 64–72 %, grands murs à 58–72 %, une porte à chaque virage (25–29 par run), rayons de
virage de descendeur, vitesse max 137 km/h, pré-saut au décollage, longueur ≈ 3 km pour ≈ 1 000 m de dénivelé.
Fichiers : `env_downhill.gd`, `descente.gd`, `ski_descente.tres`, README (phrase des sports + lien).

## 4. Bannière « nouvelle version disponible » (`43851e4`)

- Nouveau `ui/update_check.gd` : une requête asynchrone à l'API GitHub Releases, une fois par lancement,
  timeout 8 s ; tout échec est silencieux (pas de réseau, quota…).
- `main_menu.gd` : bandeau en haut de l'accueil avec lien « Télécharger » et croix de fermeture, si la dernière
  release est plus récente que `VERSION` (`"Version 2.1"`).
- ⚠️ Compare avec la release **GitHub la plus récente** : penser à mettre `VERSION` à jour dans `main_menu.gd`
  au prochain build, sinon la bannière s'affichera pour la version qu'on vient de publier.

## 5. Vue du drone plus stable (`1e44810`)

L'incrustation « vue du drone » montrait des bascules d'assiette brutales (jusqu'à 70° en une image).
- `flight_path.gd` : la ligne que suit le drone est filtrée (constantes `LINE_VEL_TAU`, `LINE_ACC_TAU`,
  `ATT_ACC_TAU`) ; le plancher est anticipé (`FLOOR_MARGIN`) au lieu d'un clamp brutal ; le drone démarre à plat,
  cap du chemin, au lieu d'être incliné par la pente.
- `scenario_base.gd` : stationnaire moins agité (`HOVER_WANDER` 0,5 → 0,35 ; `HOVER_PUMP` 0,35 → 0,25).
- `drone_difficulty.gd` : `FLIGHT_VERSION` 3 → **4**.

## À savoir avant / après le merge

- **Replays** : les sessions enregistrées en modèle de vol 1–3 se rejouent avec l'ancien calcul (le filtre n'est
  actif qu'à partir du modèle 4), donc le vol du drone y est identique. Les replays de **ski de descente** enregistrés
  avant le commit `4f2bbf5` rejouent un autre tracé (la scène est régénérée depuis la graine) : le score reste
  juste, l'image ne correspond plus. Les sauvegardes ne sont pas touchées.
- **`.godot/` est dans `.gitignore` mais 252 fichiers y sont déjà suivis** (cache d'import, `uid_cache.bin`,
  `editor_layout.cfg`…). Ils apparaissent dans le diff sans rien de pertinent et créeront des conflits dès que deux
  machines (Windows / Mac) les modifient. À sortir de l'index à part : `git rm -r --cached fpv-gimbal-trainer/.godot`.
- Ce récap vient de l'historique git et des diffs ; je n'ai pas relancé de session de jeu pour le rédiger.
  Les mesures de la descente sont celles consignées dans `docs/ski_descente.md`.

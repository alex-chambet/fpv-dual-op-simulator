# Les sons enregistrés

Ce dossier est **vide par défaut**, et le jeu fonctionne quand même : chaque son manquant est
remplacé par une boucle générée par le code (`scenarios/audio/sound_bank.gd`). Déposer un fichier
ici le remplace, sans toucher à une ligne de code — c'est tout le rôle de
`scenarios/audio/sound_library.gd`.

## Le contrat

Un fichier `<nom>.ogg` remplace le son `<nom>`. Les noms attendus, et ce que chacun doit être :

| Nom | Ce que c'est | Piloté par |
|---|---|---|
| `wind_low` | souffle grave et continu | vitesse du drone, dès les premiers m/s |
| `wind_mid` | le corps du vent | vitesse du drone, 5 à 42 m/s |
| `wind_high` | sifflement aigu | vitesse du drone, au-delà de 17 m/s |
| `wind_gust` | rafale | accélération du drone (pas sa vitesse) |
| `engine_idle` | moteur au ralenti | régime dans le rapport |
| `engine_mid` | régime moyen, stable | régime dans le rapport |
| `engine_high` | haut régime | régime dans le rapport |
| `tyres` | roulement sur asphalte | vitesse du véhicule |
| `ski_carve` | carres qui mordent, fin et clair | vitesse × angulation |
| `ski_skid` | dérapage, large et fort | vitesse × dérapage |
| `prop_low` | hélices en stationnaire | effort du drone |
| `prop_high` | hélices qui travaillent | effort du drone |

## Ce qu'un fichier doit être

- **mono**, OGG Vorbis — c'est ce que Godot boucle le mieux ;
- **une boucle, pas un effet** : pas d'attaque au début, pas de chute à la fin, rien qui raconte
  quelque chose. Les voix se chargent du niveau, de la hauteur et des fondus ; tout ce qui est
  figé dans le fichier devient une répétition qu'on finit par entendre ;
- **sans silence ni musique**, et aussi uniforme que possible : c'est une matière, pas un plan.

Rien de tout cela ne se fait à la main : `tools/make_sfx.ps1` prend un enregistrement brut,
en extrait une fenêtre, recolle la boucle (queue fondue sur la tête), normalise en crête et
convertit. Voir `docs/son.md`.

## Comment ceux-ci ont été faits

Sources brutes dans `data/SFX/` (hors dépôt : `data/` est dans le `.gitignore`), 96 kHz stéréo,
de 12 s à 3 min. Pour chacune, la fenêtre a été **choisie par mesure** et non à l'oreille : RMS par
trames de 0,25 s, puis la plus longue fenêtre (8, 6, 4, 3 ou 2 s) dont le coefficient de variation
reste sous 0,45 et dont le niveau reste au-dessus de la moitié du 90ᵉ centile du fichier. Les douze
fichiers produits pèsent 560 Ko.

Quatre sources se sont révélées **événementielles** plutôt que continues — `ski_carve`, `ski_skid`,
`wind_gust` et `prop_high` sont des passages, pas des nappes : aucune fenêtre de 8 s n'y tenait, et
elles ont dû être réduites à 1,6 – 5 s. Si une répétition s'entend en jeu, c'est de là qu'elle
vient, et le remède est une source plus longue et plus régulière, pas un réglage.

## Licence

**Tout fichier déposé ici part dans le `.pck` distribué** : il faut donc que sa licence autorise la
redistribution dans un logiciel. Un abonnement de musique de production couvre en général des
vidéos, pas l'intégration dans un jeu diffusé — à vérifier auprès de l'éditeur avant toute
distribution publique du jeu.

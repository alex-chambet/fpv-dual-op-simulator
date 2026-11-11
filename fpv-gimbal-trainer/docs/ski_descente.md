# Le ski de descente

Une descente façon Streif (Kitzbühel) ou Face de Bellevarde (Val d'Isère), générée à chaque session :
la montagne par `scenarios/environments/env_downhill.gd`, la ligne de course et la vitesse par
`scenarios/subjects/archetypes/descente.gd`, les réglages par `scenarios/subjects/catalogue/ski_descente.tres`.

## Les deux références

| | Longueur | Dénivelé | Pente moyenne | Pente max |
|---|---|---|---|---|
| Streif, Kitzbühel | 3 312 m | 860 m | 27 % | 85 % (Mausefalle), Steilhang ~72–85 %, Hausbergkante ~70 % |
| Face de Bellevarde, Val d'Isère | 2 998 m | 959 m | 32 % | 71 % (le mur de départ) |

Sources : [hahnenkamm.com](https://hahnenkamm.com/en/racetracks/the-streif-downhill/),
[Wikipedia — Streif](https://en.wikipedia.org/wiki/Streif),
[Wikipedia — La face de Bellevarde](https://en.wikipedia.org/wiki/La_face_de_Bellevarde),
[worldcup-valdisere.com](https://www.worldcup-valdisere.com/en/?p=5144). Aucune source ne publie le profil
section par section ; les chiffres de sections sont de seconde main et approximatifs.

Ce que les deux ont en commun, et qui fait leur caractère : elles **ouvrent sur un mur** (Bellevarde part à
71 %, la Mausefalle est dans les 300 premiers mètres de la Streif), elles gardent **deux ou trois longs murs à
65–85 %** dans le parcours, et entre les deux ce sont des glisses et de grandes courbes — pas un géant. Les virages
serrés d'une descente font 40–60 m de rayon, les grandes courbes 100–250 m.

## Ce qui a été mesuré avant de toucher au code (novembre 2026)

Trois graines, en construisant la vraie scène et en lisant la ligne générée (`subject_pts`) et le plan :

| | Avant |
|---|---|
| Pente moyenne | 34–37 % — **déjà au-dessus de Bellevarde** |
| Plus long mur continu à plus de 50 % | 100–150 m |
| Virages | 15–22 par run, rayon **20–35 m** |
| Vitesse max | 107–110 km/h |
| Portes | 16, posées tous les 110 m sans regarder le tracé : 5–9 sur du droit, et **5 à 10 virages sur 15–22 sans porte** |

Le diagnostic n'était donc pas « pas assez de pente » au sens de la moyenne : c'était l'absence de longs murs,
et surtout un tracé de **géant** — des virages de 20–35 m de rayon qui obligeaient le skieur à freiner à 60 km/h
à chacun, avec une adhérence latérale de 12 m/s² (1,2 g) alors qu'un descendeur tient 2 g (le Karussell de la
Streif est mesuré à 3,1 g). Et des portes posées à intervalle régulier, indépendamment des virages.

## Ce qui a changé

**Une porte à chaque virage.** L'archétype enregistre l'apex de chaque virage qu'il trace (`turn_i`, un index de
point : pas une distance, parce que `st.s` compte l'avance horizontale et que la ligne 3D est 6 % plus longue sur
35 % de pente — 90 m de dérive en bas, de quoi poser la porte sur le mauvais virage). L'environnement pose une
porte à chaque apex, puis des portes de direction pour qu'aucun tronçon ne dépasse 130 m sans porte. Les portes
posées sont exposées dans `EnvDownhill.gate_s` pour les mesures.

**Des rayons de descente.** Virages serrés 38–96 m, grandes courbes 95–260 m (selon `turn_tightness`), moins
d'enchaînements en S, `turn_frequency` 0,6 au lieu de 0,9. Adhérence 20 m/s², vitesse max 38 m/s (137 km/h, le
Zielschuss).

**La traînée.** `air_drag` passe de 0,0042 à 0,0032 : c'est k = ½·ρ·Cd·A/m d'un coureur en œuf
(0,5 × 1,1 × 0,45 m² / 80 kg). À 0,0042 la vitesse terminale sur 40 % de pente était 28 m/s et les runs
plafonnaient à 115–122 km/h quels que soient les virages.

**La montagne.** Un mur de départ à 64–72 % sur 130–190 m, de grands murs à 58–72 % sur 120–200 m tous les
900–1 200 m, des atterrissages de cassure à 54–66 %, le reste en glisses (14–24 %), parties rapides (30–42 %) et
murs ordinaires (44–56 %). Pente plafonnée à 85 % après les ondulations du relief.

**Le pré-saut.** Lancé tangent à une glisse à 35 m/s sur un atterrissage à 60 %, un arc balistique reste 10 m
au-dessus de la neige pendant 90 m — ce que personne ne fait : un coureur *pré-saute*, il pousse avant la lèvre
pour que l'arc colle au mur, et vole 50–70 m à quelques mètres de haut. Modélisé comme une poussée vers le bas au
décollage, un peu plus à chaque essai jusqu'à ce que le vol culmine sous `PREJUMP_MAX` (3,5 m). Avant, l'arc était
simplement coupé à 90 m et le skieur tombait de 11 m sur la neige en un pas — c'est le premier réglage de pente
qui l'a fait apparaître, et la mesure qui l'a attrapé.

## Mesuré après, sur huit graines

| | Après |
|---|---|
| Longueur / dénivelé | 2 874–3 043 m / 1 017–1 136 m |
| Pente moyenne | 38–42 % |
| Pente max sur 20 m | 72–78 % (dans le mur de départ ou un grand mur) |
| Plus long mur continu à plus de 50 % | 175–200 m |
| Virages | 9–15 par run, rayon 54–218 m |
| Virages avec une porte dedans | **89 / 90** (le raté : un frémissement de 13 m à 218 m de rayon) |
| Portes | 25–29 par run, 8,7–10 par km (une vraie descente : ~11) |
| Sauts | 3–6 par run, 0,9–3,4 m de haut, 30–66 m de long |
| Vitesse max | 128–136 km/h |
| Durée | 95–101 s |
| Vol du drone | acc99 4,5–5,1 m/s², pan95 11–18 °/s, ligne de vue jamais coupée, score 0,87–0,99 |

La moyenne est au-dessus des deux références (qui comptent de longs plats, le Gschöss de la Streif), les murs
sont à leur hauteur, et la longueur comme le dénivelé sont ceux de Bellevarde.

## Ce que ça change pour ce qui existe déjà

Un replay rejoue les entrées de gimbal enregistrées sur une scène **regénérée depuis la graine**. Les sessions de
ski de descente enregistrées avant ce changement rejouent donc un autre tracé sous les mêmes mouvements : le score
affiché reste le bon, l'image ne lui correspond plus. C'est inhérent à tout changement de générateur ; les
sauvegardes n'ont pas été touchées.

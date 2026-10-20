# Le son

Le son est fait de **boucles empilées et mélangées en temps réel** par deux voix, celle du sujet et celle du drone.
Chaque boucle vient d'un fichier enregistré si le projet en a un (`assets/audio/`), sinon d'une boucle calculée par
le code (`sound_bank.gd`). Le jeu tourne donc avec zéro fichier audio, et déposer un fichier le remplace sans
toucher au code.

Les douze sons actuels sont des enregistrements (560 Ko au total) ; voir
[`assets/audio/README.md`](../assets/audio/README.md) pour leur provenance et **la question de licence, qui
n'est pas réglée pour une distribution publique**.

Le son n'est pas là pour faire joli. Tout le jeu repose sur la capacité du cadreur à **anticiper** : le son est un
deuxième canal pour ça, à côté de l'attitude du skieur ou de la voiture. Entendre le moteur monter avant la zone de
freinage, ou la note tomber au moment où la voiture passe sous le drone, c'est le signal pour lancer le panoramique.

## Les réglages (Paramètres > Son, ou Échap > Son en jeu)

| Réglage | Ce qu'il coupe |
|---|---|
| Volume général | Tout |
| Sujet (moteur, carres) | Ce que fait le sujet |
| Drone (hélices, vent) | Ce que fait le drone |

Les deux derniers sont séparés exprès : ils ne font pas le même travail. Le sujet **informe** (où il est, quand il
va passer) ; le drone est le siège sur lequel on est assis. Quelqu'un qui veut entendre le premier peut baisser le
second à zéro sans jouer en silence.

Ce sont trois **bus audio** (`Master`, `Sujet`, `Drone`), donc le réglage s'entend tout de suite, même avec la
session en pause derrière le menu. Les valeurs sont enregistrées dans `user://menu_prefs.json`, clé `sound`.
La mise en pause (Échap) arrête les boucles : Godot met les lecteurs en pause avec l'arbre.

## Pourquoi des couches (`scenarios/audio/sound_layer.gd`)

C'est le point qui change tout. **Une seule prise étirée au pitch sonne toujours comme une seule prise étirée** :
une voiture à 40 km/h et la même à 160 ne sont pas le même son joué plus vite, ce sont deux sons différents. Chaque
voix tient donc plusieurs échantillons en même temps et passe de l'un à l'autre — ce que fait un jeu de course — et
l'oreille lit le résultat comme une machine qui change d'état, pas comme une bande qui accélère.

Une couche est décrite par des données, pas par du code :

| Champ | Ce qu'il dit |
|---|---|
| `window` | `[a, b, c, d]` sur la valeur qui pilote : muet sous `a`, plein de `b` à `c`, muet au-delà de `d` |
| `pitch` | hauteur aux deux bouts de `over` |
| `over` | la plage sur laquelle la hauteur est étalée (par défaut la fenêtre) |
| `db` | niveau quand la couche est à plein |
| `smooth` | lissage du gain, pour qu'une valeur mesurée bruitée ne fasse pas claquer la couche |

Les bords de la fenêtre sont des `smoothstep`, donc deux couches voisines s'additionnent à puissance à peu près
constante au lieu de creuser au milieu du fondu. Chaque boucle démarre à un point tiré au hasard : deux copies du
même échantillon ne se retrouvent jamais en phase.

`over` existe à cause d'un vrai bug, trouvé en mesurant : une couche qui reste allumée jusqu'en haut a une fenêtre
qui finit à l'infini, donc une hauteur étalée sur l'infini — elle ne bougeait jamais. Les pneus sont restés à 0,75
pendant un tour entier avant que la mesure ne le montre.

## D'où vient chaque son (`scenarios/audio/sound_library.gd`)

Un nom (`wind_mid`, `engine_high`, `ski_skid`…) est résolu dans cet ordre : `assets/audio/<nom>.ogg` s'il existe,
sinon la boucle procédurale correspondante. Ce repli n'est pas une politesse : il veut dire qu'un fichier manquant
ou mal nommé dégrade vers quelque chose d'audible au lieu de dégrader vers le silence — la panne qu'on ne remarque
pas avant qu'un joueur la signale. `SoundLibrary.missing()` liste ce qui est encore généré.

Le contrat de nommage et ce qu'un fichier doit être : [`assets/audio/README.md`](../assets/audio/README.md).

**Licence** : tout fichier déposé là part dans le `.pck` distribué. Un abonnement de musique de production
(type Epidemic Sound) couvre en général des vidéos, pas la redistribution dans un logiciel — à vérifier fichier par
fichier, et à noter dans le tableau du README.

## Préparer un enregistrement (`tools/make_sfx.ps1`)

Un son brut ne boucle jamais tout seul : il claque une fois par tour. L'outil prend un fichier, en extrait une
fenêtre stable, **recolle la boucle** (la queue est fondue sur la tête, donc le fichier dure `Duration - Fade` et
se referme sur lui-même), normalise en crête à −1 dBFS et convertit en OGG mono 32 kHz.

```powershell
.\tools\make_sfx.ps1 -In "$HOME\Documents\fpv_sfx\wind_mid.wav" -Name wind_mid -Start 2 -Duration 6
```

Si ça claque encore, rallonger `-Fade`. La qualité du raccord se vérifie en comparant le saut d'échantillon au
raccord avec le **saut moyen du même fichier** — c'est le bon dénominateur, parce qu'un bruit large saute beaucoup
d'un échantillon à l'autre et qu'un grondement grave ne saute presque pas. Sur les douze sons, onze tiennent entre
0,0 et 2,5 fois le saut moyen ; `wind_low` était à 8,0 et il a fallu lui donner un fondu de 2,5 s au lieu de 1,0
pour descendre à 3,9. C'est exactement le piège du grave : le même raccord absolu y paraît énorme.

La normalisation est **en sonie (EBU R128, deux passes, linéaire), pas en crête**. La première version normalisait
en crête et laissait 12,2 dB d'écart de sonie entre le moteur et les hélices : les niveaux écrits dans les couches
ne voulaient alors plus rien dire. En sonie, l'écart tombe à 6,0 dB — le reste vient de la pondération K, qui juge
différemment un souffle large et un grondement grave, et c'est normal.

## Les boucles calculées (`scenarios/audio/sound_bank.gd`)

Cinq boucles mono, 22 050 Hz, une seconde chacune, normalisées à 0,92 et **raccordées** : la queue est fondue sur la
tête (512 échantillons) et la moyenne est retirée, sinon la boucle claque une fois par seconde.

| Boucle | Comment elle est faite |
|---|---|
| `engine` | Une impulsion de combustion par explosion (50 Hz), ses harmoniques, et le râle de l'admission. Deux explosions par période, légèrement inégales — un moteur parfaitement régulier bourdonne. Le paramètre `roughness` sépare un V8 de course d'un petit moteur de route. |
| `rolling` | Bruit large passe-bas : les pneus et la suspension. |
| `edges` | Bruit passe-bande : les carres sur la neige. |
| `prop` | Quatre rotors à 110 / 111 / 109 / 112 Hz, jamais tout à fait en phase — ce battement lent est ce qui fait entendre un quadricoptère plutôt qu'une sirène. Les fréquences sont des nombres **entiers** de cycles par boucle, donc chacune est continue au raccord. |
| `wind` | Bruit large : l'air sur la cellule. |

## La voix du sujet (`scenarios/audio/subject_voice.gd`)

Une source **3D posée sur le sujet**, avec le Doppler activé (`DOPPLER_TRACKING_PHYSICS_STEP`). L'auditeur est la
caméra de la gimbal : le son porte donc exactement la même information que l'image — à quelle distance le sujet est,
de quel côté il est parti, s'il vient ou s'il s'en va.

Rien n'est écrit sport par sport. Trois familles, choisies d'après l'accessoire de la fiche (`placeholder_gear`) :

- **Moteur** (voiture, kart, moto) : une **boîte 6 vitesses**, et trois boucles — ralenti, régime moyen, haut
  régime — fondues l'une dans l'autre **par le régime dans le rapport**. Le régime monte, retombe au passage de
  rapport, et remonte : comme les trois boucles suivent ce même régime, c'est le *timbre* qui retombe avec lui, pas
  seulement la hauteur. C'est cette chute qui dit à l'oreille que la voiture accélère fort, au lieu d'une note qui
  glisse vers l'aigu indéfiniment. Le roulement des pneus est posé dessous, sur la vitesse.
- **Neige** (ski, snowboard, luge) : le carving est un sifflement fin et clair ; le **dérapage** est large et
  beaucoup plus fort, et il efface le carving. C'est le son à apprendre à entendre, parce qu'un skieur ne ralentit
  qu'en dérapant (voir [ajouter_un_sport.md](ajouter_un_sport.md)) — on l'entend avant de le voir. Le dérapage de
  l'archétype est **signé** (il porte le côté vers lequel les skis sont jetés) : c'est sa valeur absolue qui est
  écoutée. L'avoir pris tel quel rendait muet un dérapage sur deux, ce que seule la mesure a montré.
  En ski alpin il n'y a pas de dérapage du tout — un coureur carve — et c'est correct.
- **Air** (tout le reste) : le vent de déplacement, en v².

La « charge » (accélération du sujet, lissée) module le niveau du moteur : une voiture qui relance est plus forte
qu'une voiture qui roule à la même vitesse sur son élan.

## La voix du drone (`scenarios/audio/drone_voice.gd`)

Volontairement **pas** une source 3D : l'auditeur est boulonné sur ce drone, donc son bruit est simplement toujours
là — et c'est précisément ce qui fait que le son du sujet se lit comme une **distance** et pas comme un volume.

L'air est **trois enregistrements superposés**, pas un seul monté : un grondement grave présent dès les premiers
mètres par seconde, le corps du vent par-dessus, et un sifflement aigu qui n'apparaît qu'en haut de l'échelle.
Chacun a sa fenêtre, donc accélérer ne fait pas seulement « plus fort », ça change de couleur — et c'est comme ça
qu'on entend une vitesse plutôt qu'un volume. Une quatrième couche est la **rafale**, pilotée par l'accélération
du drone et non par sa vitesse : un freinage sec a de l'air dedans.

Les hélices sont deux boucles fondues par l'effort (0 en stationnaire, 1 à fond). Tout est déduit de la seule
position du drone d'une image à l'autre, donc ça marche sans changement en vol planifié (entraînement), en vol
acro (2 joueurs) et au bac à sable.

## Vérifié

- Les boucles calculées : durée exacte, pas de composante continue (< 0,002), crête à 0,92, raccord fondu,
  `LOOP_FORWARD`. Génération 34 ms au premier appel, 0 ms ensuite (cache).
- La résolution fichier / repli : les douze noms sont résolus sur un fichier (`missing()` est vide), bouclé
  (`loop = true`) ; en retirant un fichier, le nom retombe sur la boucle calculée.
- **La marge avant écrêtage**, mesurée image par image comme la somme en puissance des couches actives d'un même
  bus (des bruits décorrélés s'additionnent en puissance, pas en amplitude). Le premier réglage montait le bus du
  sujet à **+2,4 dB** sur le freeride, donc au-dessus de la pleine échelle : les niveaux ont été redescendus
  jusqu'à **−7,6 dB (sujet) et −10,1 dB (drone)**, ce qui laisse la place au volume général et aux moments où deux
  boucles moteur corrélées se recouvrent.
- La chaîne de préparation, essayée de bout en bout sur un vrai enregistrement 48 kHz stéréo de 20 s : fenêtre,
  raccord, normalisation, OGG mono — saut au raccord 1,8 fois le saut moyen du fichier, donc inaudible.
- Le mélange, mesuré image par image sur un tour de circuit, une descente de slalom et une face de freeride :
  - circuit — les trois boucles moteur se relaient avec le régime (`engine_high` −14 dB puis `engine_mid` −7 dB au
    rapport suivant), les pneus suivent la vitesse, toutes les hauteurs bougent ;
  - freeride — le dérapage brut va de −1,00 à +1,00 et occupe **61 % des images** : `ski_skid` monte à −5 dB
    pendant que `ski_carve` s'efface ;
  - ski alpin — pas de dérapage (0 image sur 3 607), carving seul, conforme à l'archétype.
- Les bus : créés une seule fois, coupés à zéro, volumes relus depuis les préférences.
- La pause : les lecteurs passent en `stream_paused` quand l'arbre est mis en pause, et repartent à la reprise.

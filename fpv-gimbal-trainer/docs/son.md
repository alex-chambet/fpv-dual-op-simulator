# Le son

Tout le son du jeu est **calculé par le code** : il n'y a pas un seul fichier audio dans le projet. Cinq boucles
d'une seconde sont fabriquées au premier lancement (34 ms en tout, une fois par partie), puis étirées et mélangées
en temps réel par deux « voix ».

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

## La banque de sons (`scenarios/audio/sound_bank.gd`)

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

- **Moteur** (voiture, kart, moto) : une **boîte 6 vitesses**. Le régime monte, retombe au passage de rapport, et
  remonte. C'est cette chute qui dit à l'oreille que la voiture accélère fort, au lieu d'une note qui glisse vers
  l'aigu indéfiniment. Un roulement large se mélange par-dessus, proportionnel à la vitesse.
- **Neige** (ski, snowboard, luge) : les carres. Le carving est un sifflement fin et clair ; le **dérapage** est
  large et beaucoup plus fort. C'est le son à apprendre à entendre, parce qu'un skieur ne ralentit qu'en dérapant
  (voir [ajouter_un_sport.md](ajouter_un_sport.md)) — on l'entend avant de le voir.
- **Air** (tout le reste) : le vent de déplacement, en v².

La « charge » (accélération du sujet, lissée) module le niveau : un sujet qui relance est plus fort qu'un sujet qui
se laisse rouler à la même vitesse.

## La voix du drone (`scenarios/audio/drone_voice.gd`)

Volontairement **pas** une source 3D : l'auditeur est boulonné sur ce drone, donc son bruit est simplement toujours
là — et c'est précisément ce qui fait que le son du sujet se lit comme une **distance** et pas comme un volume.

Les hélices montent quand le drone travaille (il monte, il change de vitesse), le vent suit sa vitesse. Tout est
déduit de la seule position du drone d'une image à l'autre, donc ça marche sans changement en vol planifié
(entraînement), en vol acro (2 joueurs) et au bac à sable.

## Vérifié

- Les cinq boucles : durée exacte, pas de composante continue (< 0,002), crête à 0,92, raccord fondu, `LOOP_FORWARD`.
- Génération : 34 ms au premier appel, 0 ms ensuite (cache).
- Pilotage par la vitesse, mesuré sur un tour de circuit et une descente de ski : la hauteur du moteur suit bien la
  dent de scie de la boîte, le sifflement des carres suit le dérapage, les hélices et le vent suivent le drone.
- Les bus : créés une seule fois, coupés à zéro, volumes relus depuis les préférences.
- La pause : les cinq lecteurs passent en `stream_paused` quand l'arbre est mis en pause, et repartent à la reprise.

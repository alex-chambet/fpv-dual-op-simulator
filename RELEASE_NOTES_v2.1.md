# FPV DUALOP v2.1 — Le son, la vraie profondeur de champ, et un drone qui a une masse

Trois ajouts qui tirent dans le même sens : donner au cadreur **de quoi anticiper**. Le son dit où est le sujet et ce qu'il fait avant qu'on le voie ; la profondeur de champ donne enfin une raison de changer d'optique ; et le drone cesse d'être un chariot de travelling parfait pour devenir une machine qui a de l'inertie, comme celle qu'on a vraiment au bout des doigts.

## Téléchargement

- **Windows 64 bits** : `FPV_DUALOP_v2.1.exe` + `FPV_DUALOP_v2.1.pck`. **Gardez les deux fichiers dans le même dossier.**
- **macOS** : `FPV_DUALOP_v2.1_macOS.zip` — binaire universel, Intel (macOS 11+) et Apple Silicon (macOS 13+). Voir « Ouvrir sur macOS » ci-dessous.
- Carte graphique compatible Vulkan requise (rendu Forward+). Sur Mac, le rendu passe par Metal via MoltenVK.

### Ouvrir sur macOS

L'application n'est pas signée avec un compte développeur Apple ni notariée : au premier lancement, macOS la refusera (« impossible de vérifier le développeur », ou « endommagée »). Deux façons de l'autoriser, après avoir décompressé l'archive :

- **Clic droit sur l'application → Ouvrir**, puis confirmer. À faire une seule fois.
- Ou, si macOS la dit endommagée, retirer la mise en quarantaine dans le Terminal :
  ```
  xattr -dr com.apple.quarantine /chemin/vers/fpv-gimbal-trainer.app
  ```

L'application s'appelle toujours `fpv-gimbal-trainer.app` : c'est le nom interne du projet, et le renommer déplacerait le dossier des scores et de l'historique.

---

## Nouveautés

### Le son

**Le jeu avait l'image, il lui manquait l'oreille.** Tout repose sur la capacité du cadreur à anticiper : le son est un deuxième canal pour ça, à côté de l'attitude du skieur ou de la voiture. Entendre le moteur monter avant la zone de freinage, ou la note tomber au moment où la voiture passe sous le drone, c'est le signal pour lancer le panoramique.

Ce ne sont pas des bruitages déclenchés à l'événement, mais **des boucles empilées et mélangées en temps réel**. Une seule prise étirée au pitch sonne toujours comme une seule prise étirée : une voiture à 40 km/h et la même à 160 ne sont pas le même son joué plus vite. Chaque voix tient donc plusieurs échantillons en même temps et passe de l'un à l'autre, comme un jeu de course — l'oreille lit une machine qui change d'état, pas une bande qui accélère.

- **Le sujet** sonne depuis l'endroit où il est, en 3D, avec effet Doppler, l'auditeur étant la caméra de la gimbal : le son porte donc exactement la même information que l'image — à quelle distance le sujet est, de quel côté il est parti, s'il vient ou s'il s'en va. Les voitures ont une boîte 6 vitesses et trois boucles moteur qui suivent le régime : c'est le **timbre** qui retombe à chaque rapport, pas seulement la hauteur. Les skis ont leurs carres : fin et clair en carving, large et fort en dérapage — c'est-à-dire exactement quand le skieur ralentit.
- **Le drone** n'est pas une source 3D : on est assis dessus. Ses hélices montent quand il accélère ou qu'il monte, son vent suit sa vitesse. Quatre rotors à 110, 111, 109 et 112 Hz, jamais tout à fait en phase : ce battement lent est ce qui fait entendre un quadricoptère plutôt qu'une sirène.
- **Trois volumes séparés** — général, sujet, drone — dans **Paramètres > Son** ou **Échap > Son** en jeu. Ce sont trois bus audio, donc le réglage s'entend tout de suite, même session en pause derrière le menu. On peut couper le drone à zéro pour n'écouter que le sujet sans jouer en silence.

Douze sons enregistrés (560 Ko au total), et **chaque son manquant est remplacé par une boucle calculée par le code** : le jeu tourne avec zéro fichier audio, et un fichier mal nommé dégrade vers quelque chose d'audible au lieu de dégrader vers le silence. Détails : [docs/son.md](fpv-gimbal-trainer/docs/son.md).

### La profondeur de champ est devenue celle de l'optique

Ce n'est plus un flou décoratif : ce sont les **vraies limites de netteté** de l'optique choisie, à f/2, sur le capteur qu'implique le champ de vision du jeu (plein format, cercle de confusion 0,03 mm). Hyperfocale H = f²/(N·c) + f, puis les limites proche et lointaine habituelles.

| Focale | Hyperfocale | Net à 8 m | Net à 15 m | Net à 40 m |
|---|---|---|---|---|
| 24 mm | 9,6 m | 4,4 – 47,3 m | 5,9 m – ∞ | 7,7 m – ∞ |
| 35 mm | 20,5 m | 5,8 – 13,1 m | 8,7 – 56,2 m | 13,5 m – ∞ |
| 50 mm | 41,7 m | 6,7 – 9,9 m | 11,0 – 23,4 m | 20,4 – 971 m |
| 85 mm | 120,5 m | 7,5 – 8,6 m | 13,3 – 17,1 m | 30,0 – 59,8 m |

**C'est la vraie raison de changer d'optique** : à 85 mm le sujet se détache du fond, à 24 mm tout est net à partir de 6 m et rien ne se détache jamais. Et la mise au point est *tirée*, pas collée : elle suit le sujet en quelques dixièmes de seconde, comme un pointeur qui suit sa molette — un changement brusque de distance passe donc par un moment flou, ce qui est exactement ce qui arrive sur un plateau.

Elle est éteinte dans le préréglage Basse, allumée à partir de Moyenne, et reste décochable dans **Graphismes > Image**.

### Exposition automatique

Le diaphragme automatique d'une caméra, qui met un instant à rattraper quand on panote du sol vers le ciel. **Désactivée par défaut** : un opérateur de drone verrouille son exposition, et une image qui se rééquilibre sans arrêt masque les erreurs de cadrage au lieu de les montrer. À activer dans **Graphismes > Image** pour s'entraîner avec.

### Un drone qui a une masse

Jusqu'ici le drone était posé sur sa trajectoire comme un chariot sur son rail. Il la **chasse** maintenant comme un pilote la vole : il prend du retard et déborde un peu quand la ligne change vite, s'enfonce quand il s'incline fort (le pilote remet des gaz un instant trop tard), et n'est jamais exactement sur sa ligne — les petites corrections permanentes d'un pilote FPV. Son assiette est celle qui produit son accélération, comme sur un vrai multirotor.

Rien de tout cela ne rend le vol brutal : l'accélération reste bornée, et la difficulté continue de venir du mouvement, des axes à gérer et de la proximité — jamais de coups de volant. **Le niveau 6 (Expert) est en revanche volé nettement plus près** qu'avant, et ses limites de vitesse d'image ont été relevées en conséquence.

---

## Compatibilité

- **Les sessions d'entraînement enregistrées avec une version antérieure du modèle de vol ne se rejouent pas** (le drone ne volait pas pareil). Les parcours guidés, dont la géométrie n'a pas changé, se rejouent normalement.
- Les meilleurs scores et l'historique de la 2.0 sont conservés.
- Les réglages (manette, graphismes, ambiance) sont conservés ; les trois volumes sonores s'ajoutent avec leurs valeurs par défaut.

## Configuration testée

Windows 11, NVIDIA RTX 4070 Laptop, Vulkan. Le build Windows a été lancé : démarrage propre, aucune erreur au journal, manette détectée.

## Limites connues

- **La licence des douze sons n'est pas réglée pour une distribution publique.** Ils viennent d'un abonnement Epidemic Sound, qui couvre en général les productions vidéo et pas l'intégration dans un logiciel diffusé — à vérifier auprès de l'éditeur, fichier par fichier, avant toute diffusion hors cercle privé. Le jeu fonctionne sans eux : retirer `assets/audio/` et chaque son repasse sur sa boucle calculée.
- **Le build macOS n'a pas été lancé sur un Mac.** Il a été produit depuis Windows et vérifié sur pièces : paquet `.app` complet, `Info.plist` en 2.1.0, `.pck` identique à celui de Windows, signature ad-hoc présente. Rien ne remplace un vrai démarrage — à essayer avant de le diffuser.
- **Le son n'a pas été écouté dans le build exporté** : sa présence a été vérifiée dans le `.pck`, pas son rendu à l'oreille.
- Les performances n'ont **pas** été re-mesurées sur cette version : les chiffres de la 2.0 restent la dernière mesure connue, et la profondeur de champ y coûtait déjà environ 3 ms par image en 1080p.
- Le mode 2 joueurs et le vol acro n'ont pas été retestés avec deux manettes physiques sur cette version.
- Le niveau Expert reste validé surtout en simulation — et il est maintenant plus proche du sujet qu'avant.
- Le trail et le VTT de descente restent retirés du menu ; leurs sessions enregistrées se rejouent.

# FPV DUALOP

**Un simulateur pour s'entraîner à cadrer avec une gimbal, accrochée à un drone FPV.**

Sur un tournage en drone, deux personnes travaillent ensemble : le **pilote** vole, le **cadreur** tient la gimbal et garde le sujet dans l'image. FPV DUALOP permet de s'entraîner à ce second rôle (ou aux deux), sans risquer un vrai drone ni un vrai tournage.

Vous tenez une manette, un drone vole autour d'un sujet (un skieur, une voiture, un vététiste…), et votre travail est de le garder bien cadré, de façon fluide.

> Projet réalisé avec le moteur Godot 4.7. Pour Windows 64 bits.

---

## Ce qu'on y fait

### Session d'entraînement (1 joueur)
Le drone vole tout seul autour du sujet. **Vous gérez uniquement la gimbal** : pan (gauche / droite), tilt (haut / bas) et roll. Une session dure environ une minute.

À la fin, vous recevez une **note sur 100** (et une lettre, jusqu'à S) :
- **Cadrage (45 %)** : le sujet reste-t-il dans le rectangle vert, sans toucher les bords ?
- **Fluidité (35 %)** : vos mouvements sont-ils doux, sans à-coups ?
- **Suivi (20 %)** : retrouvez-vous vite le sujet quand vous le perdez ?

Votre meilleur score est enregistré pour chaque sport. Vous pouvez revoir et rejouer vos sessions dans « Historique et replays ».

**Les sports** : ski alpin (slalom), ski de descente (une piste de 2 km et plus façon Streif ou Bellevarde, à plus de 110 km/h, avec des sauts), trail, VTT de descente, voiture sur la Départementale, voiture sur route de montagne. Chaque session est générée avec un trajet différent.

**Les mouvements du drone** (au choix, ou au hasard) :

| Mouvement | Ce que fait le drone |
|---|---|
| Suivi latéral, poursuite arrière | À côté du sujet, ou derrière lui |
| Face au sujet | Recule devant le sujet en le filmant de face |
| Dévoilement | Le sujet est caché derrière un obstacle, puis découvert |
| Orbite | Tourne autour du sujet |
| Survol rapide | Croise le sujet de près, à grande vitesse |
| Entrée + orbite, Plongeon, Chorégraphie *(Expert)* | Figures de cinéma FPV, voir plus bas |

**Six niveaux de difficulté.** Plus le niveau monte, plus le drone est proche et plus il va vite. Le niveau 1 ne demande qu'un seul axe à la fois (pan ou tilt). À partir du niveau 3, il faut gérer les deux ensemble. Le drone vole toujours de façon fluide : la difficulté vient du mouvement, pas de coups de volant.

**Le niveau 6 – Expert** est conçu comme un vrai entraînement de cadreur : le drone s'éloigne puis revient à toute vitesse pour s'enrouler autour du sujet, plonge dessus, le croise face à face, enchaîne les figures. Le sujet passe de minuscule à plein cadre en quelques secondes.

**Quatre optiques** : 24, 35, 50 et 85 mm. Plus l'optique est serrée, plus le cadrage est difficile.

### Mode 2 joueurs
Un joueur **pilote** le drone en mode acro (manette FPV, sans stabilisation, comme en vrai). L'autre tient la **gimbal**. Le pilote voit sa vue FPV en incrustation, ou sur un second écran. Les deux sont notés, et vous obtenez un score d'équipe.

### Bac à sable
Un monde ouvert, sans chrono ni score : 1,6 × 1,6 km de campagne avec un village, des fermes, une rocade, des voitures, des camions, des cyclistes, des piétons, et un avion et un hélicoptère dans le ciel.
- **Sans manette, ou avec une seule** (celle de la gimbal) : le drone décolle tout seul et vole de façon aléatoire mais fluide dans toute la carte. C'est idéal pour régler sa gimbal et filmer ce qui passe.
- **Avec une 2e manette** : vol acro libre.
- **Au clavier** : vol assisté.

---

## Ce qu'il vous faut

- **Windows 64 bits**
- Une **carte graphique compatible Vulkan** (la plupart des cartes de moins de 8 ans)
- Une **manette**, de préférence. Le clavier fonctionne aussi. Pour jouer à deux, il faut deux manettes.

## Installation

1. Téléchargez les deux fichiers de la dernière version dans l'onglet **Releases** :
   `FPV_DUALOP_vX.Y.exe` et `FPV_DUALOP_vX.Y.pck`.
2. Mettez-les **dans le même dossier**.
3. Lancez le fichier `.exe`. Il n'y a rien d'autre à installer.

> Windows peut afficher un avertissement « SmartScreen » au premier lancement, car le programme n'est pas signé. Cliquez sur « Informations complémentaires » puis « Exécuter quand même ».

## Premiers pas

1. Sur l'accueil, cliquez sur **JOUER**.
2. Choisissez **Entraînement** (ou **Bac à sable** pour le vol libre), puis un **terrain** (touches 1 à 6).
3. Réglez le **mouvement du drone**, le **niveau** et l'**optique**. Au début : suivi latéral, niveau 1 ou 2, 24 mm.
4. **LANCER** (ou Entrée). Un compte à rebours de quelques secondes laisse le temps de s'installer.
5. Gardez le sujet dans le rectangle vert. À la fin, regardez votre note, et rejouez pour la battre.

Le menu se pilote aussi au clavier ou à la manette (flèches, Entrée, Échap pour revenir en arrière). Après une session, il rouvre directement la page de réglages de cette session, pour rejouer en un clic.

Pour changer les réglages de manette, la qualité graphique et le flou de mouvement : tuile **Paramètres** de l'accueil.

## Commandes

| Action | Manette | Clavier |
|---|---|---|
| Pan / tilt | Sticks de la gimbal | Flèches ou WASD |
| Roll | Selon votre configuration | Q / E |
| Profil de vitesse de la gimbal | – | 1 / 2 / 3 |
| Grille des tiers | – | G |
| Masquer l'affichage | – | F1 |
| Pause | – | Échap |
| Recommencer | – | Entrée |

Dans le bac à sable : **M** change de mode de vol (auto, clavier, acro), **Retour arrière** ramène le drone sur la place du village. Sur l'accueil : **R** lance une session aléatoire.

**Configurer ses manettes** : menu « Paramètres » → « Configuration manette ». Vous pouvez y choisir la manette de la gimbal et celle du pilote, affecter chaque axe, inverser, régler la zone morte et l'expo.

**Option « Noir hors du cadre »** : dans la pause (Échap → Gameplay), elle assombrit complètement tout ce qui est hors du rectangle vert. Vous ne voyez alors que ce que montrerait le cadre, sans l'environnement autour. Elle est désactivée par défaut et mémorisée d'une partie à l'autre.

**Conseil pour le niveau Expert** : prenez un profil de gimbal rapide (touche 2 ou 3). Les croisements demandent des pointes de plus de 100 °/s.

---

## Graphismes

Quatre niveaux de qualité (Basse, Moyenne, Haute, Ultra) et un **flou de mouvement** réaliste, par objet : le décor file derrière un sujet net, comme sur une vraie caméra. Si le jeu est lent sur votre machine, baissez la qualité dans « Paramètres » ou pendant la partie (Échap → Graphismes).

- **Ambiances** : plein jour, matin, fin de journée, temps couvert, chute de neige (sur la neige), ou au hasard. Elles se choisissent sur la page de réglages de la session (ligne « Ambiance »).
- **Athlètes animés** : le skieur prend la position de recherche de vitesse, le coureur passe de la marche au sprint, le vététiste pédale sur un vrai VTT.
- **Décors vivants** : public, drapeaux et banderoles sur la descente ; fermes, champs labourés et blés mûrs sur la Départementale ; parois rocheuses et massifs sur la route de montagne ; rayons de lumière dans la forêt (qualité Ultra).
- **Rendu caméra** : vignettage, légère aberration chromatique et grain, comme une vraie optique.

## Limites connues

- Les athlètes sont des **mannequins animés**, sans visage ni vêtements détaillés.
- Le vol acro à deux manettes n'a pas encore été testé sur tous les modèles de manette.
- Le niveau Expert a surtout été validé en simulation. Vos retours sont les bienvenus.

## Pour aller plus loin

- Ajouter un sport, régler la difficulté : [docs/ajouter_un_sport.md](fpv-gimbal-trainer/docs/ajouter_un_sport.md)
- Le mode 2 joueurs : [docs/mode_2_joueurs.md](fpv-gimbal-trainer/docs/mode_2_joueurs.md)
- Le bac à sable : [docs/bac_a_sable.md](fpv-gimbal-trainer/docs/bac_a_sable.md)
- La Départementale : [docs/departementale.md](fpv-gimbal-trainer/docs/departementale.md)
- Les graphismes : [docs/graphismes.md](fpv-gimbal-trainer/docs/graphismes.md)
- L'historique des versions : onglet **Releases**

Le code source est dans le dossier `fpv-gimbal-trainer/` (projet Godot 4.7).

## Crédits

- Mannequin animé des athlètes : « Universal Animation Library » de [Quaternius](https://quaternius.com), licence CC0 (domaine public).
- Moteur : [Godot Engine](https://godotengine.org) (licence MIT).

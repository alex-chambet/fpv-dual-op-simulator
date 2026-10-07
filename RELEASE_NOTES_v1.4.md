# FPV DUALOP v1.4 — première release publique

**FPV DUALOP** est un simulateur d'entraînement pour **cadreurs gimbal de drone FPV** (tournage « dual operator ») : un drone vole le long d'un sujet en mouvement (skieur, vététiste, coureur, voiture…) et vous tenez la gimbal à la manette pour le garder dans le cadre. Chaque passage est noté, enregistré et peut être revu.

Cette première release regroupe tout le travail réalisé jusqu'à la v1.4.

## Téléchargement

- `FPV_DUALOP_v1.4.exe` + `FPV_DUALOP_v1.4.pck` (Windows 64 bits). **Gardez les deux fichiers dans le même dossier.**
- Carte graphique compatible Vulkan requise (rendu Forward+).
- Une manette (radio FPV type TBS Tango ou manette de jeu) est recommandée ; le clavier fonctionne aussi.

---

## Fonctionnalités

### Gimbal réaliste
- Modèle de gimbal inspiré d'une Ronin RS3 Pro : lissage des commandes, vitesse cible par axe, accélération et inertie sur pan, tilt et roll.
- **3 profils de vitesse** (touches 1 / 2 / 3) : *Slow*, *Medium*, *Fast*.
- Gimbal toujours **indépendante du cap du drone**.
- Contrôle à la manette (axes configurables) ou au clavier (flèches / WASD, Q/E pour le roll).

### Sports et environnements
- **5 sports au menu** :
  - **Ski alpin** sur piste enneigée ;
  - **Trail** en forêt ;
  - **VTT descente** en forêt ;
  - **Voiture sur route de montagne**, avec lacets et tunnel ;
  - **Départementale** : voiture sur une route de campagne française, environ 1 min 15 de course, avec **trafic en sens inverse** (voitures, camionnettes, semi-remorques) et cyclistes.
- Moteur générique piloté par des **fiches de données** : 8 archétypes de mouvement (glisse, course, véhicule sur route, tout-terrain, sauts, sports collectifs, surface de l'eau, vol libre) et une quarantaine de fiches de sports déjà décrites.
- **Ajouter un sport ne demande aucun code** : on duplique une fiche `.tres` (voir `docs/ajouter_un_sport.md`).

### Sessions d'entraînement générées
Une session combine un sport, un mouvement de drone, un niveau et une optique.
- **Mouvements de drone** : poursuite arrière, latéral, frontal, orbite, révélations…
- **Niveaux de difficulté** : la difficulté vient du mouvement, des axes à gérer (pan / tilt) et de la proximité. **Le vol du drone reste toujours fluide** (accélérations limitées, pas d'à-coups).
- **Optiques** : 24, 35, 50 ou 85 mm.
- **Obstacles** : arbres, rochers ou véhicules masquent le sujet par moments. La durée pendant laquelle le sujet est caché est mesurée.
- Mode aléatoire : session suivante tirée au hasard (touche N).

### Score
- **Cadrage** : le sujet doit rester dans le cadre vert, avec une **marge de sécurité de 15 %** à l'intérieur. Toute sortie de cadre pénalise immédiatement, sans délai de tolérance.
- **Fluidité** : les à-coups de gimbal (jerk) sont fortement pénalisés.
- Écran de résultats détaillé, meilleurs scores enregistrés par session.
- Touche **G** : grille des tiers.

### Historique et rejeux
- Chaque passage est enregistré : entrées de la gimbal image par image, scores, trajectoire.
- Écran **Historique** : tri par date, scénario ou score ; filtres ; courbe de progression avec moyenne glissante.
- **Rejeu exact** de n'importe quelle session, y compris en 2 joueurs et avec le trafic.

### Mode 2 joueurs
- Un **pilote** vole le drone en **mode acro** sur une seconde manette FPV, pendant que le **cadreur** tient la gimbal.
- Physique de quadricoptère : courbe de rates, poussée, traînée, retard moteur, crashs.
- **Armement de sécurité** : décollage depuis le sol, le drone ne s'envole pas tout seul.
- Image FPV du pilote en **incrustation** (30 % de la largeur de l'écran) ou sur un **second écran**.
- **Score du pilote** : distance au sujet, fluidité, ligne de vue, nombre de crashs.
- Voir `docs/mode_2_joueurs.md`.

### Image et rendu
- **Flou de mouvement réaliste, objet par objet** : un sujet suivi par la caméra reste net pendant que le décor file. Quatre réglages : désactivé, 1/120, 1/60, 1/30 s.
- **Environnements détaillés** (voir `docs/graphismes.md`) :
  - ciel avec nuages et halo du soleil, rendu AgX ;
  - sols procéduraux :
    - herbe, terre et roche selon la pente ;
    - champs cultivés autour de la Départementale ;
    - neige damée sur la piste de ski ;
    - asphalte usé et marquages ;
  - herbe 3D animée par le vent, avec des fleurs et des cultures ;
  - sapins et feuillus détaillés qui bougent au vent, enneigés en montagne ;
  - petit décor :
    - en forêt : fougères, buissons, troncs couchés, souches, rochers moussus ;
    - sur la Départementale : haies, fermes et granges, ligne électrique, bornes kilométriques ;
    - au ski : jalons de piste, filets de sécurité, télésiège ;
    - sur la route de montagne : colline et portails du tunnel ;
  - paysage lointain : champs et bosquets, vallée glaciaire, montagnes enneigées ;
  - voitures carrossées (peinture vernie, vitres, phares, jantes).
- **Qualité graphique** : Basse, Moyenne, Haute ou Ultra.
- Effet « vraie caméra » : vignettage et grain.

### Interface
- Menu principal :
  - choix du sport par cartes ;
  - réglages de session : mode de jeu, écrans, mouvement, niveau, optique ;
  - **les choix sont mémorisés** d'une partie à l'autre.
- **Menu Pause** (Échap) : Reprendre, Recommencer, Graphismes (qualité et flou de mouvement), Quitter vers le menu.
- Interface adaptée aux écrans **4K**.
- **Configuration manette** : vue des axes en direct, affectation des axes de la gimbal et du pilote, inversion, zone morte, expo.

---

## Historique des versions

- **v1.1** : premier exécutable Windows. Contenu :
  - gimbal et profils de vitesse ;
  - sports et sessions générées ;
  - choix de l'optique ;
  - score avec marge de sécurité et pénalisation des à-coups ;
  - historique et rejeux.
- **v1.2** :
  - sorties de cadre pénalisées sans délai de tolérance ;
  - grille des tiers (touche G) ;
  - profil Fast 15 % plus rapide.
- **v1.3** : mode 2 joueurs :
  - drone acro et armement de sécurité ;
  - incrustation à 30 % ou second écran ;
  - gimbal indépendante du drone ;
  - choix du menu mémorisés.
- **v1.4** :
  - interface 4K ;
  - scénario Départementale avec trafic ;
  - flou de mouvement par objet ;
  - menu Pause ;
  - menu d'accueil simplifié ;
  - refonte graphique complète des environnements et option de qualité graphique.

## Configuration testée

Windows 11, NVIDIA RTX 4070 Laptop, Vulkan. En 4K plein écran, qualité Haute, sans flou de mouvement : 90 à 120 images/s.

## Limites connues
- Les sujets autres que la voiture (skieur, coureur, vététiste) restent des silhouettes simplifiées. Les camionnettes et camions du trafic sont des formes simples.
- La qualité Ultra est exigeante en 4K : environ 50 images/s sur un GPU portable de milieu de gamme.
- En pause, l'image figée est nette (pas de flou de mouvement).

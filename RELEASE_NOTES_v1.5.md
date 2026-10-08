# FPV DUALOP v1.5 — Bac à sable

Cette version ajoute un **mode bac à sable** : une campagne ouverte, sans chrono ni score, où l'on vole et filme librement. Elle ajoute aussi une page **Paramètres**, le choix de l'optique en cours de partie et des sessions plus longues.

## Téléchargement

- `FPV_DUALOP_v1.5.exe` + `FPV_DUALOP_v1.5.pck` (Windows 64 bits). **Gardez les deux fichiers dans le même dossier.**
- Carte graphique compatible Vulkan requise (rendu Forward+).

---

## Nouveautés

### Mode bac à sable
Lancement depuis le panneau « Bac à sable » du menu d'accueil, ou touche **B**.

- **La carte** : 1,6 × 1,6 km de campagne dans le style de la Départementale.
  - Une rocade d'environ 4 km.
  - Deux routes départementales qui se croisent au centre d'un village.
  - Une rue de village et des chemins vers six fermes.
- **Le village** :
  - maisons, église sur la place ;
  - trottoirs, lampadaires ;
  - voitures garées.
- **La campagne** :
  - fermes et granges, platanes, bosquets, haies ;
  - ligne électrique, bornes kilométriques ;
  - champs cultivés, paysage lointain.
- **Ce qui bouge** :
  - **circulation permanente** : voitures, camionnettes, camions et cyclistes. Les véhicules gardent leurs distances, ralentissent dans les virages et respectent les priorités aux carrefours.
  - **villageois** : ils se promènent sur les trottoirs ou discutent en groupe sur la place.
- **Trois modes de vol du drone** (touche **M** pour passer de l'un à l'autre) :
  - **Auto** (par défaut sans manette, ou avec la seule manette de la gimbal) : le drone décolle tout seul, puis vole de façon aléatoire mais toujours fluide dans toute la carte, au-dessus des routes, du village et des champs. Un cadreur seul peut ainsi tester ses réglages de gimbal.
  - **Acro** (par défaut avec une 2e manette configurée comme manette pilote) : vol acro comme en mode 2 joueurs, avec la vue FPV en incrustation ou sur un second écran.
  - **Assisté** : vol au clavier (I/K, J/L, U/O, Y/H, Maj pour aller vite).
- Le drone se cogne aux maisons, aux arbres et aux véhicules. **Retour arrière** le ramène sur la place du village.

### Paramètres
- Dans le menu d'accueil, « Configuration manette » devient **« Paramètres »**. Cette page regroupe :
  - la configuration des manettes ;
  - la qualité graphique (Basse, Moyenne, Haute, Ultra) ;
  - le flou de mouvement.
- Les réglages sont enregistrés immédiatement.

### Menu Pause : sous-menu « Gameplay »
- Nouveau sous-menu entre « Graphismes » et « Quitter » pour **changer l'optique** (24, 35, 50 ou 85 mm) en cours de partie dans le bac à sable.
- En session d'entraînement, l'optique reste figée : le score et le rejeu en dépendent.

### Sessions plus longues
Le ski alpin, le trail, le VTT descente et la voiture sur route de montagne durent maintenant **environ 1 minute**, quel que soit le niveau. La Départementale reste à environ 1 min 15.

## Améliorations

- **Performances** :
  - les détails des maisons (fenêtres, volets, porte, cheminée) sont réunis en un seul objet ;
  - la vue du pilote n'est plus calculée quand elle est masquée.
- Le menu d'accueil est simplifié : les outils « Test gimbal » et « Éditeur de trajectoire » sont retirés.

---

## Configuration testée

Windows 11, NVIDIA RTX 4070 Laptop, Vulkan.

## Limites connues

- Le vol acro dans le bac à sable n'a pas encore été testé avec deux manettes physiques. Il utilise le même code que le mode 2 joueurs.
- Le choix d'optique fait dans le menu Pause du bac à sable n'est pas mémorisé d'une partie à l'autre.
- Aux carrefours, un cycliste qui doit tourner peut attendre longtemps une ouverture dans la circulation.

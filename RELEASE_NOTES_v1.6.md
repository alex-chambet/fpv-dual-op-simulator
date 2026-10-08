# FPV DUALOP v1.6 — Niveau Expert

Cette version ajoute un **6e niveau de difficulté, « Expert »**, pour les sessions à 1 joueur. Le drone y vole vite et enchaîne des figures de cinéma FPV : c'est un autre exercice, pas un niveau 5 un peu plus rapide.

## Téléchargement

- `FPV_DUALOP_v1.6.exe` + `FPV_DUALOP_v1.6.pck` (Windows 64 bits). **Gardez les deux fichiers dans le même dossier.**
- Carte graphique compatible Vulkan requise (rendu Forward+).

---

## Nouveautés

### Niveau 6 – Expert
Dans le menu d'accueil, le choix « Niveau » propose maintenant « Niveau 6 - EXPERT ». Il s'applique aux cinq sports du menu : ski alpin, trail, VTT descente, Départementale et voiture sur route de montagne.

- **Un drone plus rapide et plus près du sujet** :
  - accélération jusqu'à 9 m/s² (6 au niveau 5) ;
  - jusqu'à environ 130 km/h sur les longues lignes ;
  - orbite d'un tour en 8 s au plus près du sujet.
- **Trois nouveaux mouvements de drone** :
  - **Entrée + orbite** : le drone s'éloigne loin et haut (le sujet devient minuscule), revient à toute vitesse et s'enroule autour du sujet sur 1 à 1,75 tour, en montant et en descendant. Il repart ensuite chercher une autre entrée.
  - **Plongeon** : il monte haut devant le sujet, plonge dessus (tilt jusqu'à −70°), le frôle à basse altitude et remonte derrière lui, en changeant de côté à chaque fois.
  - **Chorégraphie expert** : elle enchaîne entrées en orbite, plongeons, croisements face à face (le drone attend loin devant puis fonce sur le sujet) et spirales montantes, jamais deux fois la même figure de suite.
- **Pour le cadreur** : le sujet passe de minuscule à plein cadre. Le pan atteint 40 à 70 °/s (95e centile, pointes de 90 à 150 °/s pendant les croisements) et le tilt change sans cesse de sens. Prévoyez le profil de gimbal 2 ou 3.
- **Le drone reste fluide** : aucun changement brusque de direction ni de vitesse, et il ne touche ni le sol ni les arbres.
- **Tirage au sort** : avec « Mouvement : au hasard », le niveau Expert tire une figure expert dans environ 80 % des cas, sinon une orbite ou un survol. Le niveau « Aléatoire » ne tire que les niveaux 1 à 5 : l'Expert se choisit exprès.
- Les trois figures peuvent aussi être choisies à un niveau plus bas : elles sont alors plus lentes et plus lointaines.

## Corrections

- **Dévoilement et survol rapide** : le drone traversait parfois les arbres posés pour cacher le sujet, à tous les niveaux. Ces obstacles ne sont plus placés sur sa trajectoire.
- **Route de montagne** : les sapins sont écartés de la trajectoire du drone.

---

## Compatibilité

- Les niveaux 1 à 5 volent comme avant. Les sessions enregistrées restent rejouables, mais le moment où le sujet est caché peut légèrement changer lors d'un rejeu.

## Configuration testée

Windows 11, NVIDIA RTX 4070 Laptop, Vulkan.

## Limites connues

- Le niveau Expert n'a été vérifié qu'en simulation et sur captures d'écran, pas encore avec une vraie manette sur une session complète.
- Sur la route de montagne, le tunnel et le relief cachent la voiture 6 à 10 % du temps, et le drone reste à 12 – 20 m du sujet à cause des épingles.
- Le vol acro du bac à sable n'a pas encore été testé avec deux manettes physiques (même code que le mode 2 joueurs).

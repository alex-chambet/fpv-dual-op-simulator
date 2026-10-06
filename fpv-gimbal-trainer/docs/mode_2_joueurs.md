# Mode 2 joueurs

Un pilote vole le drone (mode **acro**, manette FPV), un cadreur tient la gimbal (autre manette). Le sujet reste
scripté (il suit son chemin à sa vitesse).

## Lancer
Menu > « Mode de jeu » : *2 joueurs*, puis choisir le sport et l'optique, puis Entrée.
Mouvement et niveau sont ignorés (le drone n'est plus automatique).

## Manettes
- **Gimbal** : la première manette détectée (ou celle configurée), comme avant.
- **Pilote** : la deuxième manette. Réglage dans *Configuration manette* (liste « Drone (pilote FPV) ») :
  affecter chaque axe à throttle / yaw / pitch / roll, inverser si besoin, zone morte et expo.
  Valeurs par défaut : ordre AETR (roll = axe 0, pitch = 1, throttle = 2, yaw = 3), pitch inversé.
  Contrôle : manche vers le haut = throttle monte, manche à droite = yaw/roll positifs, manche en avant = pitch positif.
- Sans manette pilote, le drone reste en vol stationnaire (le message « NO PILOT CONTROLLER » s'affiche).

## Le drone (flight/fpv_drone.gd)
Acro : les manches commandent des **vitesses de rotation** (pas d'auto-stabilisation), le throttle commande la poussée
le long de l'axe vertical du drone. Pour avancer, on incline le drone. Modèle : courbe de rates (centre / max / expo),
retard moteur, poussée max 36 m/s² (rapport poussée/poids 3,7, vol stationnaire à 38 % de throttle), gravité,
traînée linéaire + quadratique, sol et obstacles (arbres, rochers...) ; un choc violent compte comme un crash.
Tous les réglages sont des variables exportées de `FpvDrone`.

## Gimbal en 2 joueurs
La gimbal est **indépendante du drone** : pan, tilt et roll sont stabilisés dans le monde ; seule la position
de la caméra suit le drone. Quand le pilote vire ou s'incline, l'image ne tourne pas.

## Affichage
Image principale = caméra gimbal (cadreur). Incrustation en bas à droite = caméra FPV du pilote (105°, inclinée de 25°)
+ OSD (altitude, vitesse, distance au sujet, throttle, crashs).

## Scores
- Cadreur : cadrage / fluidité / suivi, comme en 1 joueur.
- Pilote (scenarios/pilot_scorer.gd) : distance au sujet dans une bonne plage (dépend de l'optique), fluidité du vol
  (accélérations et à-coups), stabilité de la ligne de visée (le sujet change lentement de direction, n'est pas caché),
  - 8 points par crash.
- Score d'équipe = moyenne des deux. Meilleur score enregistré sous « duo_<sport>[_<optique>] ».
- Les sessions sont enregistrées avec les entrées du pilote : le rejeu est identique.

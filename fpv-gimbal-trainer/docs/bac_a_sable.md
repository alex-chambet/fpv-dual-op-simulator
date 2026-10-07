# Bac à sable

La campagne de la Départementale en libre : pas de sujet, pas de chrono, pas de score. Le drone vole où il veut et le
cadreur filme ce qui lui plaît (trafic, cyclistes, villageois, paysage).

## Lancer
Menu principal > panneau « Bac à sable » > *Lancer le bac à sable* (ou touche **B**). L'optique et le choix
« Écrans » de la session d'entraînement s'appliquent aussi au bac à sable.

## Commandes
- **Gimbal** : comme partout (manette gimbal, ou flèches / WASD + Q / E), profils 1 / 2 / 3, G = grille des tiers.
- **Drone** :
  - avec une manette pilote configurée : vol **acro** comme en mode 2 joueurs (gaz au minimum pour armer), vue FPV
    du pilote en incrustation ou sur le 2e écran ;
  - sans manette pilote : **vol assisté au clavier** (I / K avancer / reculer, J / L décaler, U / O tourner,
    Y / H monter / descendre, Maj = rapide). Le drone garde sa position quand on lâche les touches ;
  - **M** passe de l'un à l'autre, **Retour arrière** ramène le drone à son point de départ (place du village).
- Échap : pause (Reprendre, Recommencer, Graphismes, Quitter). F1 : masquer l'affichage.

## La carte (scenarios/sandbox/)
- `sandbox_world.gd` : 1,6 x 1,6 km de campagne autour d'un village.
  - Routes : une rocade d'environ 4 km, deux départementales qui se croisent au centre du village, une rue de
    village, des chemins de terre vers six fermes.
  - Village : maisons le long des rues (plus serrées au centre), place avec église, trottoirs, lampadaires,
    voitures garées.
  - Campagne : fermes et granges, platanes le long des routes, bosquets, haies, ligne électrique, bornes, champs
    cultivés, herbe 3D, paysage lointain.
  - Le drone se cogne aux maisons, aux arbres et aux véhicules.
- `sandbox_traffic.gd` : trafic permanent (voitures, camionnettes, camions, cyclistes) sur six boucles (la rocade
  dans les deux sens et des boucles qui traversent le village par les routes A et B). Les véhicules gardent leurs
  distances, ralentissent dans les virages et dans le village. Aux carrefours, la rocade et la route A sont
  prioritaires ; un véhicule qui tourne, ou qui traverse la route A par la route B, cède le passage et ne s'engage
  que si le carrefour est libre.
- `pedestrians.gd` : villageois qui marchent sur les trottoirs (demi-tour au bout) et petits groupes qui discutent
  sur la place.
- `sandbox.gd` : la scène (drone, gimbal, affichage, pause).

Vérifié sur 3 minutes de trafic simulé : aucun véhicule bloqué, aucune voiture qui en traverse une autre.

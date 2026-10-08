# Bac à sable

La campagne de la Départementale en libre : pas de sujet, pas de chrono, pas de score. Le drone vole où il veut et le
cadreur filme ce qui lui plaît (trafic, cyclistes, villageois, paysage).

## Lancer
Menu principal > panneau « Bac à sable » > *Lancer le bac à sable* (ou touche **B**). L'optique et le choix
« Écrans » de la session d'entraînement s'appliquent aussi au bac à sable.

## Commandes
- **Gimbal** : comme partout (manette gimbal, ou flèches / WASD + Q / E), profils 1 / 2 / 3, G = grille des tiers.
- **Drone** (**M** passe d'un mode à l'autre, **Retour arrière** ramène le drone sur la place du village) :
  - **auto** (par défaut sans manette, ou avec une seule manette, celle de la gimbal) : le drone décolle tout seul
    puis vole de façon aléatoire mais toujours fluide dans toute la carte, pour que le cadreur règle sa gimbal seul ;
  - **acro** (par défaut quand une 2e manette est configurée comme manette pilote) : vol acro comme en mode
    2 joueurs (gaz au minimum pour armer), vue FPV en incrustation ou sur le 2e écran ;
  - **assisté** : vol au clavier (I / K avancer / reculer, J / L décaler, U / O tourner, Y / H monter / descendre,
    Maj = rapide).
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
- `auto_flight.gd` : le pilote automatique. Un générateur enchaîne sans fin des tronçons le long des routes (juste
  au-dessus des toits dans le village, au-dessus des arbres à la campagne) et des traversées libres à 16 - 45 m, tous
  vérifiés contre les bâtiments et les arbres. Le drone est un point matériel dont l'accélération (3,2 m/s² au plus)
  est elle-même lissée : pas de changement brusque de direction ni de vitesse, virages arrondis, vitesse réduite dans
  les virages serrés. Mesuré sur 10 minutes : accélération max 3,6 m/s², variation d'accélération max environ
  8 m/s³, aucune collision, toute la carte parcourue.
- `pedestrians.gd` : villageois qui marchent sur les trottoirs (demi-tour au bout) et petits groupes qui discutent
  sur la place.
- `sky_traffic.gd` : un **avion** léger (hélice qui tourne) et un **hélicoptère** qui volent dans le ciel.
  L'avion décrit une grande boucle autour de la carte à environ 190 m, virages inclinés de 23° au plus, 40 m/s
  (144 km/h). L'hélicoptère tourne autour du village à environ 95 m (rotor principal et rotor de queue qui
  tournent, nez baissé en avançant) et ralentit presque jusqu'au vol stationnaire au-dessus de deux endroits.
  Les deux volent toujours bien au-dessus du drone automatique (45 m au plus) : pas de collision. Mesuré : accélération
  de 4,2 m/s² au plus pour l'avion, 3 m/s² pour l'hélicoptère.
- `sandbox.gd` : la scène (drone, gimbal, affichage, pause).

Un véhicule qui tient un carrefour (un long camion qui tourne, par exemple) n'attend pas les véhicules qui
attendent après lui, et un véhicule qui cède le passage accepte un écart de plus en plus petit à mesure qu'il
attend (de 70 m à 26 m) : les files ne se bloquent plus.

Vérifié sur 20 minutes de trafic simulé (64 véhicules) : aucune voiture qui en traverse une autre, aucun carrefour
bloqué (le centre d'un carrefour n'a jamais eu de véhicule arrêté plus de quelques secondes) ; l'attente la plus
longue est d'environ 50 s dans une file à un carrefour de la rocade.

# Scénario « Départementale »

Voiture sur une route départementale française, en plaine, plus rapide que le col de montagne
(21 à 27 m/s, soit 75 à 97 km/h, contre 6,5 à 16 m/s) et plus longue : environ 1 min 15 de course.

- **Route** (scenarios/environments/env_departementale.gd) : deux voies avec ligne centrale discontinue, lignes de rive,
  accotements en gravier, champs, haies, platanes (arbres le long de la route), poteaux électriques, maisons.
  Le sujet roule dans sa voie, à droite de la ligne centrale.
- **Trafic** (scenarios/road_traffic.gd, traffic_models.gd) : voitures, camionnettes et semi-remorques en sens inverse ;
  cyclistes sur les bas-côtés (dans le sens du sujet ou en sens inverse). La position de chaque véhicule ne dépend que
  du temps de course : les rejeux sont identiques. Les véhicules peuvent cacher le sujet et sont solides pour le drone
  du mode 2 joueurs.
- **Fiche** : scenarios/subjects/catalogue/departementale.tres (archétype VEHICULE_ROUTE, route sinueuse douce,
  `duration` = 75 s). Changer la durée ou la vitesse = changer `duration`, `speed_min`, `speed_max`.
- Le drone automatique est plus proche qu'ailleurs rapporté à la vitesse (`drone_distance_scale` = 0,75).

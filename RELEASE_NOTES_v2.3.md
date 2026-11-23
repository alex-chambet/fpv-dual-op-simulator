# FPV DUALOP v2.3 — Linux, un décor retravaillé et un circuit sans murs invisibles

La 2.3 ajoute une **version Linux**, refait la végétation, la roche et les voitures pour qu'ils ressemblent moins à un jeu, et corrige une série de défauts du **circuit** : des planchers invisibles pour le drone piloté, des voitures qui saccadaient ou se cabraient dans le bac à sable.

## Téléchargement

- **Windows 64 bits** : `FPV_DUALOP_v2.3.exe` + `FPV_DUALOP_v2.3.pck`. **Gardez les deux fichiers dans le même dossier.**
- **macOS** : `FPV_DUALOP_v2.3_macOS.zip` — binaire universel, Intel (macOS 11+) et Apple Silicon (macOS 13+). Voir « Ouvrir sur macOS » ci-dessous.
- **Linux 64 bits (nouveau)** : `FPV_DUALOP_v2.3.x86_64` + `FPV_DUALOP_v2.3.pck`, dans le même dossier. Voir « Lancer sur Linux » ci-dessous.
- Carte graphique compatible Vulkan requise (rendu Forward+). Sur Mac, le rendu passe par Metal.

### Ouvrir sur macOS

L'application n'est pas signée avec un compte développeur Apple ni notariée : au premier lancement, macOS la refusera (« impossible de vérifier le développeur », ou « endommagée »). Deux façons de l'autoriser, après avoir décompressé l'archive :

- **Clic droit sur l'application → Ouvrir**, puis confirmer. À faire une seule fois.
- Ou, si macOS la dit endommagée, retirer la mise en quarantaine dans le Terminal :
  ```
  xattr -dr com.apple.quarantine /chemin/vers/fpv-gimbal-trainer.app
  ```

L'application s'appelle toujours `fpv-gimbal-trainer.app` : c'est le nom interne du projet, et le renommer déplacerait le dossier des scores et de l'historique.

### Lancer sur Linux

Un fichier téléchargé n'est pas exécutable : après avoir mis les deux fichiers dans le même dossier,

```
chmod +x FPV_DUALOP_v2.3.x86_64
./FPV_DUALOP_v2.3.x86_64
```

---

## Nouveautés

### Une version Linux

Le jeu tourne maintenant sous Linux 64 bits, testé sur Debian. La compatibilité vient d'une contribution de **nolanribet** (polices de repli pour l'interface, et un correctif du contrôle de mise à jour), reprise ici avec l'export Linux. Le build est nouveau : les retours sont les bienvenus.

### Végétation, roche et voitures retravaillées

Six éléments « faisaient jeu » et ont été refaits, jugés sur des captures avant / après prises au même instant de la même session.

| Élément | Avant | Après |
|---|---|---|
| Épicéas | étages de losanges vert vif, plaques de neige | branches photographiées qui retombent, rameaux pendants, neige en tas sur le dessus |
| Feuillus | boule sur un piquet | tronc qui fourche, charpentières, houppier en lobes inégaux, feuilles de charme |
| Roche (falaises du freeride, parois, rochers) | bruit « camouflage » | falaise photographiée, vue de tous les côtés, à deux échelles |
| Montagnes lointaines | moucheté sel-et-poivre | faces rocheuses sur les pentes raides, champs de neige ailleurs |
| Voitures | caisse en boîte, passages de roue peints | flancs galbés, capot bombé, passages de roue creusés dans la caisse |
| Herbe 3D | touffes isolées en rangs | gazon continu |

Les textures de végétation et de roche viennent de photographies CC0 (Poly Haven, ambientCG), assemblées par le code en branches entières et en bouquets ; leurs couleurs sont ramenées à une moyenne fixe pour que la teinte des arbres reste celle de chaque style et de chaque ambiance. Détail et méthode : [docs/graphismes.md](fpv-gimbal-trainer/docs/graphismes.md).

**Ce que ça coûte.** Mesuré en qualité Haute, 1600 × 900, sur une puce intégrée Radeon 890M (le pire cas, pas une carte dédiée) :

| Niveau | Avant | Après | Écart |
|---|---|---|---|
| ski_descente (le plus boisé) | 9,69 ms | 11,25 ms | +16 % |
| circuit_course | 18,47 ms | 20,50 ms | +11 % |
| departementale | 11,44 ms | 13,04 ms | +14 % |

L'essentiel vient des épicéas détaillés et de l'herbe. Les chiffres du circuit et de la départementale datent d'avant l'allègement des épicéas : ils sont un peu pessimistes. Si le jeu est lent chez vous, baissez la qualité ou l'échelle de rendu dans « Paramètres ».

**Les voitures avaient un trou à chaque bout.** L'intérieur creux de la caisse se voyait par l'arrière (« pas de pare-chocs arrière, on voit au travers ») et, masqué par hasard, par l'avant. Corrigé pour toutes les voitures : entraînement, circuit, trafic de la route.

### Un drone piloté qui ne heurte plus que ce qui est dessiné

En mode 2 joueurs, le drone piloté sur le circuit rencontrait des **planchers invisibles en plein air** : remonté d'un coup puis freiné comme s'il était posé, à 9 m au-dessus de la piste sous le pont Dunlop, 8 m sous le portique, autour des postes de commissaires et des tribunes. Il ne heurte désormais que les structures réellement visibles : garages, postes, tour du château, jambes et poutres du portique et du pont, gradins et toits des tribunes. Son sol est le vrai terrain, on passe sous un pont ou une poutre, et on peut se poser sur un toit.

Vérifié sur 940 000 points autour des 142 solides : aucune collision à plus de 0,35 m d'un objet dessiné. Le bac à sable « Circuit » utilise les mêmes formes, et son pilote automatique vérifie en plus chaque tronçon **à l'altitude d'arrivée** : sur 40 vols de 5 minutes, il traversait un objet dessiné une fois (et passait 401 images à moins de 2 m) ; plus aucune après. Dans la campagne, 2 traversées de toit ou de cime sur 40 vols avant, aucune après. Détails : [docs/circuit.md](fpv-gimbal-trainer/docs/circuit.md) et [docs/bac_a_sable.md](fpv-gimbal-trainer/docs/bac_a_sable.md).

### Les voitures du bac à sable roulent proprement

Quatre défauts, tous dans le trafic du circuit :

- **Elles saccadaient.** Direction et trajectoire étaient lues au point échantillonné le plus proche (un tous les 3 m) au lieu d'être interpolées : le cap sautait de 12° d'un coup dans l'épingle la plus serrée, et la position latérale jusqu'à 1,33 m dans les virages (le « drift » qu'on voyait). Le saut est maintenant proportionnel à la vitesse.
- **Elles tanguaient comme sur une rampe.** Aux endroits où le tour se replie sur lui-même, le relevé d'altitude créait des pentes jusqu'à 35 % sur 9 zones, alors que le relevé d'origine ne dépasse jamais 7 %. La pente est plafonnée à 10 % : le tangage maximal passe de 19-35° à 8°.
- **Elles se cabraient dans le mauvais sens.** Le signe du tangage était inversé : nez vers le bas en montée. Corrigé, y compris pour le cabrage à l'accélération et la plongée au freinage.
- Dépassements et distances entre voitures sont inchangés.

### Le contrôle de mise à jour attend que le menu soit prêt

La bannière « nouvelle version disponible » est maintenant affichée une fois l'accueil prêt, et non plus pendant sa construction.

---

## Compatibilité

- **Les replays de sessions 2 joueurs enregistrées sur le circuit avant la 2.3 ne retombent plus sur la trajectoire d'origine** : un replay rejoue les manches, et le drone ne bute plus aux mêmes endroits. Les scores affichés restent justes.
- Les replays des autres sports et les sessions en solo ne sont pas touchés.
- Les meilleurs scores, l'historique et les réglages sont conservés.

## Limites connues

- **Plantage signalé sur Mac au lancement de certains niveaux d'entraînement** (observé sur un Apple M1 Pro, macOS 13.5 : le moteur échoue à compiler des shaders avec Metal, puis s'arrête). La cause n'est pas confirmée et **cette version ne la corrige pas**. Le bac à sable, lui, fonctionne. Si vous le rencontrez, envoyez le fichier `godot.log` (`~/Library/Application Support/Godot/app_userdata/fpv-gimbal-trainer/logs/`).
- **Le build macOS et le build Linux n'ont pas été lancés sur leur machine d'origine** : ils sont produits depuis Windows (macOS en signature ad-hoc, non notarié). À essayer avant de s'y fier.
- Les performances ont été mesurées sur une puce intégrée Radeon 890M, pas sur toutes les configurations. Les nouveaux arbres coûtent de 11 à 16 % de temps de rendu.
- Le mode 2 joueurs et le vol acro n'ont pas été retestés avec deux manettes physiques sur cette version.
- Le niveau Expert reste validé surtout en simulation.
- Les athlètes restent des mannequins animés, sans visage.
- Le trail et le VTT de descente restent retirés du menu ; leurs sessions enregistrées se rejouent.

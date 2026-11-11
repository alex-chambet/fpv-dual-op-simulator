# FPV DUALOP v2.2 — Une vraie descente, un skieur habillé, une vue du drone qui ne bascule plus

La 2.2 refait le **ski de descente** pour qu'il ressemble à une vraie piste de coupe du monde, habille le skieur et donne aux voitures une suspension lisible, stabilise l'incrustation de la vue du drone, et prévient quand une nouvelle version est disponible.

## Téléchargement

- **Windows 64 bits** : `FPV_DUALOP_v2.2.exe` + `FPV_DUALOP_v2.2.pck`. **Gardez les deux fichiers dans le même dossier.**
- **macOS** : `FPV_DUALOP_v2.2_macOS.zip` — binaire universel, Intel (macOS 11+) et Apple Silicon (macOS 13+). Voir « Ouvrir sur macOS » ci-dessous.
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

### Le ski de descente, refait

Mesuré avant de toucher au code : la piste avait une pente moyenne déjà au-dessus de Bellevarde, mais pas de longs murs, et un tracé de **géant** — des virages de 20 à 35 m de rayon qui forçaient à freiner à chacun — avec des portes posées à intervalle régulier sans regarder le tracé. Elle est refaite sur le modèle de la Streif (Kitzbühel) et de la face de Bellevarde (Val d'Isère).

- **Un mur de départ à 64–72 %** sur 130–190 m, puis de **grands murs à 58–72 %** tous les 900–1 200 m, des glisses, des parties rapides.
- **Une porte à chaque virage** (89 virages sur 90 en ont une), 25 à 29 portes par run.
- **Des rayons de descendeur** : 54 à 218 m, au lieu de 20–35 m. Moins d'enchaînements en S.
- **Plus vite, plus loin** : 128–136 km/h en pointe (le Zielschuss), 2,9 à 3 km pour 1 000 à 1 100 m de dénivelé, 95 à 101 s par run.
- **Des sauts de 30 à 66 m** (3 à 6 par run). Le skieur **pré-saute**, comme un vrai coureur : il pousse avant la lèvre pour que l'arc colle au mur, au lieu de retomber de 11 m d'un coup.
- Vol du drone sur ces parcours : ligne de vue jamais coupée, score entre 0,87 et 0,99.

Tous les chiffres, les références et la méthode : [docs/ski_descente.md](fpv-gimbal-trainer/docs/ski_descente.md).

### Un skieur habillé

Le mannequin nu (muscles sculptés, ce qu'on voyait du drone) est remplacé par une **vraie tenue de ski** : veste, pantalon, moufles, manchettes des chaussures, casque intégral et masque. Un **dossard blanc devant et derrière** donne un repère clair à garder dans le cadre. Les traces dans la neige sont deux rainures continues (elles étaient une rangée de tirets, à moitié enfouies), et la poudreuse est un nuage de bouffées douces qui gonflent.

### Des voitures sur leur suspension

Toutes les voitures ont maintenant une caisse qui bouge sur ses roues : elle se penche vers l'**extérieur** du virage, plonge au freinage, s'accroupit à l'accélération. Les roues avant braquent selon l'empattement, et les feux arrière s'allument au freinage. Chaque indice vient de ce que fait la trajectoire — le cadreur voit la voiture se préparer avant qu'elle ait changé de cap.

Sur le circuit, les voitures roulaient 40 cm sous l'asphalte : le sol sous la route était creusé pour le terrain dessiné, et les voitures s'y posaient. Corrigé.

### Une vue du drone qui ne bascule plus

L'incrustation « vue du drone » montrait des bascules d'assiette brutales, jusqu'à 70° en une image. La cause : la ligne que suit le drone est une courbe échantillonnée dont la position est juste au centimètre, mais dérivée deux fois à 60 Hz, un centimètre vaut 36 m/s² — des pointes de 23 à 50 m/s² contre 0,2 normalement. Un pilote n'a pas cette bande passante ; la ligne est maintenant filtrée. De plus :

- le drone anticipe le sol au lieu de se faire repousser d'un coup (un stationnaire en pente faisait basculer l'image de 30° et retour) ;
- il démarre **à plat**, cap du chemin, au lieu d'être incliné par la pente (jusqu'à −35° au mur de départ d'une face de freeride) ;
- le stationnaire du compte à rebours est calmé : ±1-2° au lieu de ±7°, comme à la main.

### Une bannière « nouvelle version disponible »

Quand une release plus récente existe sur GitHub, un bandeau apparaît en haut de l'accueil avec un lien de téléchargement et une croix pour le fermer. Une seule requête par lancement, avec un délai maximum de 8 s ; sans réseau, ou en cas d'erreur, rien ne s'affiche et rien ne ralentit le menu.

### Ambiances plus lisibles

Fin de journée et « golden » : plus de lumière d'ambiance, pour que l'ombre soit bleue et sombre, pas noire (une route à l'ombre de sa vallée était un écran noir).

---

## Compatibilité

- **Les sessions de ski de descente enregistrées avant la 2.2 rejouent un autre tracé** : un replay rejoue vos mouvements sur une scène régénérée depuis la graine, et le générateur a changé. Le score affiché reste le bon ; l'image ne lui correspond plus.
- Les sessions des autres sports se rejouent normalement : le filtrage de la vue du drone (modèle de vol 4) ne s'applique qu'aux nouvelles sessions, les enregistrements des modèles 1 à 3 gardent l'ancien calcul.
- Les meilleurs scores, l'historique et les réglages sont conservés.

## Limites connues

- **La licence des douze sons n'est pas réglée pour une distribution publique** (abonnement Epidemic Sound) — à vérifier avant toute diffusion hors cercle privé. Le jeu fonctionne sans eux.
- **Le build macOS n'a pas été lancé sur un Mac** : il est produit depuis Windows, signature ad-hoc, non notarié. À essayer avant de le diffuser.
- La bannière de mise à jour compare avec la dernière release GitHub : elle n'apparaîtra que quand la 2.2 y sera publiée et qu'une version plus récente existera.
- Les performances n'ont pas été re-mesurées sur cette version, et le ski de descente refait n'a été validé qu'en simulation et sur huit graines.
- Le mode 2 joueurs et le vol acro n'ont pas été retestés avec deux manettes physiques.
- Les athlètes restent des mannequins animés, sans visage.
- Le trail et le VTT de descente restent retirés du menu ; leurs sessions enregistrées se rejouent.

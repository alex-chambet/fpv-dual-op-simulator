"""Entaille la double barre rocheuse dans le MNT.

Pourquoi il faut l'entailler. Les deux sauts releves image par image sur FREERIDE_5 sont des
ressauts de 3 m et de 1,5 m, separes d'une vire de deux metres. Le MNT ne peut pas les porter :
le LIDAR est a 50 cm, mais la surface de NEIGE qu'on en tire (`export3.py`, fermeture morphologique
a 7 m puis trois passes binomiales) lisse justement tout ce qui est plus petit que la dizaine de
metres - c'est ce qui enleve le bruit de mesure sous la neige, et ca enleve les ressauts avec.
Resultat : nulle part sur la face lissee il n'existe de cassure franche a l'echelle d'un saut. Les
seules pentes > 55 deg qui restent sont les grandes parois de 60-70 deg, ou un skieur ne passe pas.

On la remet donc a la main, LA OU LE SKIEUR PASSE, et on l'ecrit dans le .f32 : comme ca le terrain
de Godot, le generateur de la ligne et le placement des rochers voient tous les trois la meme
chose, et la barre se couvre toute seule de parois a facettes (pente > 46 deg) et de rocher peint
(> 54 deg) par les regles deja en place.

Le profil, le long de la ligne de descente (u croissant vers le bas) :
    u < 0          : le terrain est RELEVE de D1 + D2, et ce relevement s'efface sur 80 m vers le
                     haut - ce qui donne le bombe convexe qui annonce la barre ;
    0 .. W1        : premiere marche, D1 = 3,4 m en 1,6 m -> 65 deg ;
    W1 .. W1+SH    : la vire, 2,2 m de plat ou il pose les skis ;
    puis W2        : deuxieme marche, D2 = 1,6 m en 0,9 m -> 61 deg ;
    au-dela        : le terrain d'origine, inchange.
Lateralement la barre fait 36 m de large et se fond dans la pente sur ses bords.
"""
import json
import math
import os
from array import array

DEST = r"C:\Users\alexc\Documents\CLAUDE CODE\fpv-dual-op-simulator\fpv-gimbal-trainer\test\dem"

# le point de decollage, releve sur la ligne generee sans barre (t = 9,2 s), et le cap du skieur
LIP = (-22.1, 251.1)
HEAD = (0.62, 0.79)
D1, W1 = 3.4, 1.5          # premiere marche : hauteur, longueur horizontale
SH = 2.5                   # la vire entre les deux, APLATIE (voir plus bas)
D2, W2 = 1.1, 0.9          # deuxieme marche
TAPER = 80.0               # sur combien de metres le relevement s'efface vers le haut
HALF, FADE = 18.0, 14.0    # demi-largeur a pleine hauteur, puis fondu


def smoothstep(a, b, x):
    if b <= a:
        return 0.0 if x < a else 1.0
    t = min(max((x - a) / (b - a), 0.0), 1.0)
    return t * t * (3.0 - 2.0 * t)


def main():
    info = json.load(open(os.path.join(DEST, "face_wnw.json")))
    if info.get("band_carved"):
        print("la barre est deja entaillee ; rien a faire")
        return
    w, h, cell, x0, z0 = info["w"], info["h"], info["cell"], info["x0"], info["z0"]
    hs = array("f")
    with open(os.path.join(DEST, "face_wnw.f32"), "rb") as f:
        hs.fromfile(f, w * h)
    hx, hz = HEAD
    n = math.hypot(hx, hz)
    hx, hz = hx / n, hz / n
    sx, sz = -hz, hx                      # la direction de la barre, perpendiculaire a la descente
    total = D1 + D2
    u2 = W1 + SH                          # debut de la deuxieme marche
    touched = 0
    orig = array("f", hs)                 # le relief d'origine, pour aplatir la vire

    def orig_at(x, z):
        fx = min(max((x - x0) / cell, 0.0), w - 1.001)
        fz = min(max((z - z0) / cell, 0.0), h - 1.001)
        ix, iz = int(fx), int(fz)
        tx, tz = fx - ix, fz - iz
        a = orig[iz * w + ix] * (1 - tx) + orig[iz * w + ix + 1] * tx
        b = orig[(iz + 1) * w + ix] * (1 - tx) + orig[(iz + 1) * w + ix + 1] * tx
        return a * (1 - tz) + b * tz
    for iz in range(h):
        z = z0 + iz * cell
        for ix in range(w):
            x = x0 + ix * cell
            dx, dz = x - LIP[0], z - LIP[1]
            v = dx * sx + dz * sz
            if abs(v) > HALF + FADE:
                continue
            # Une barre n'est pas une regle : son nez serpente, et sa hauteur change le long d'elle.
            # Sans ca on voit une ligne droite tiree au cordeau en travers de la pente, qui est ce
            # qui trahit le plus surement une barre fabriquee.
            u = dx * hx + dz * hz - (2.6 * math.sin(v / 11.0 + 0.7) + 1.3 * math.sin(v / 4.3 + 2.1))
            # la phase est calee pour que la barre soit un peu PLUS haute la ou il saute (v = 0) :
            # ailleurs elle s'efface, et on ne voyait plus que le gros affleurement d'a cote
            tall = 1.0 + 0.26 * math.sin(v / 7.3 + 0.6) + 0.12 * math.sin(v / 2.9)
            if u > u2 + W2 + 1.0 or u < -TAPER:
                continue
            # ce qu'il reste du relevement a l'abscisse u
            left = total * tall
            left -= D1 * tall * smoothstep(0.0, W1, u)
            left -= D2 * tall * smoothstep(u2, u2 + W2, u)
            # La vire doit etre PLATE, sinon elle tombe a la pente du terrain (45 deg ici) et les
            # deux marches se fondent en une seule rampe raide : on lui rajoute exactement ce que le
            # terrain perd entre le haut de la vire et le point courant, et ce rattrapage se vide
            # dans la deuxieme marche, qu'il creuse d'autant.
            if u > W1:
                uu = min(u, u2)
                sh = orig_at(LIP[0] + hx * W1 + sx * v, LIP[1] + hz * W1 + sz * v) \
                        - orig_at(LIP[0] + hx * uu + sx * v, LIP[1] + hz * uu + sz * v)
                left += sh * (1.0 - smoothstep(u2, u2 + W2, u))
            # il s'efface vers le haut, pour que la barre soit annoncee par un bombe et non par un mur
            left *= smoothstep(-TAPER, -TAPER * 0.45, u)
            left *= 1.0 - smoothstep(HALF, HALF + FADE, abs(v))
            if left > 0.001:
                hs[iz * w + ix] += left
                touched += 1
    with open(os.path.join(DEST, "face_wnw.f32"), "wb") as f:
        hs.tofile(f)
    info["band_carved"] = {"lip": list(LIP), "head": list(HEAD),
                           "steps": [[D1, W1], [SH], [D2, W2]], "half": HALF}
    json.dump(info, open(os.path.join(DEST, "face_wnw.json"), "w"))
    print("barre entaillee : %d mailles relevees autour de (%.0f, %.0f)" % (touched, LIP[0], LIP[1]))

    # verification : la pente le long de la descente, de part et d'autre du nez
    def ground(x, z):
        fx = min(max((x - x0) / cell, 0.0), w - 1.001)
        fz = min(max((z - z0) / cell, 0.0), h - 1.001)
        ix, iz = int(fx), int(fz)
        tx, tz = fx - ix, fz - iz
        a = hs[iz * w + ix] * (1 - tx) + hs[iz * w + ix + 1] * tx
        b = hs[(iz + 1) * w + ix] * (1 - tx) + hs[(iz + 1) * w + ix + 1] * tx
        return a * (1 - tz) + b * tz

    print("   profil (u, altitude relative, pente sur 12 m) :")
    for u in [-30, -20, -12, -6, -2, 0, 1, 2, 3, 4, 5, 6, 8, 12, 20]:
        px, pz = LIP[0] + hx * u, LIP[1] + hz * u
        gx = (ground(px + 6, pz) - ground(px - 6, pz)) / 12.0
        gz = (ground(px, pz + 6) - ground(px, pz - 6)) / 12.0
        print("     u %+4d  y %7.2f  %4.0f deg" % (u, ground(px, pz),
              math.degrees(math.atan(math.hypot(gx, gz)))))


main()

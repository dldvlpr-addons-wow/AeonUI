# AeonUI 1.0.0 — guide du testeur

Merci de tester AeonUI. Ce guide tient en une page : installer, choisir un profil, vérifier
quelques points, et signaler ce qui cloche. Aucune connaissance d'addon n'est nécessaire.

## 1. Installer

1. Ferme le jeu.
2. Décompresse `AeonUI-1.0.0.zip`.
3. Copie le dossier `AeonUI` dans le dossier des addons de ton client Forever :
   `World of Warcraft/_classic_beta_/Interface/AddOns/`.
   Le dossier doit s'appeler exactement `AeonUI` et contenir `AeonUI.toc`.
4. Lance le jeu. Sur l'écran des personnages, bouton **AddOns** : AeonUI doit être coché.
5. Active l'affichage des erreurs, une seule fois, dans le chat :
   ```
   /console scriptErrors 1
   ```

Si tu as ElvUI, Bartender, Dominos, Prat ou SexyMap : AeonUI leur laisse la place (les modules
concernés restent éteints). Pour un test complet, désactive ces addons.

## 2. Choisir un profil

À la première connexion, la fenêtre d'installation s'ouvre seule. Sinon :

```
/aeon setup
```

Page **Installation rapide** : trois boutons, un par rôle, et un bouton Léger.

| Bouton | Ce que ça fait |
|---|---|
| Installer le profil « Dégâts » | Interface complète, recharges et barre d'incantation sous le personnage, groupe en colonne à gauche |
| Installer le profil « Soigneur » | Idem, raid en grille 8 × 5 sous les recharges, vie en pourcentage, dispel et portée |
| Installer le profil « Tank » | Comme Dégâts, plus l'agro sur les cadres de groupe et le cadre du co-tank |
| Léger : modules de confort seulement | Cadres Blizzard conservés ; barre du haut, automatisation, rappels, alertes |

Clique sur ton rôle, puis tape `/reload`. Tu peux changer de profil à tout moment avec
`/aeon setup` ou `/aeon install dps|heal|tank`.

## 3. Déplacer un cadre

```
/aeon unlock     puis glisse les calques colorés, puis
/aeon lock
```

Après `/reload`, les positions doivent être conservées.

## 4. Régler

```
/aeon
```

Ouvre les options. Colonne de gauche : une page par module, classées par ordre alphabétique.
Page **Général** : échelle de l'interface, couleurs. Page **Profils** : import, export, rôle.

## 5. Ce qu'il faut vérifier

Coche chaque ligne, note ce qui ne va pas.

**Seul, en ville**
- [ ] Aucune fenêtre d'erreur Lua à la connexion ni après `/reload`.
- [ ] Barres d'action : les sorts se lancent, les raccourcis clavier fonctionnent, les recharges tournent.
- [ ] La barre Blizzard d'origine n'est plus visible (pas de doublon en bas de l'écran).
- [ ] Minimap carrée en haut à droite, boutons d'addons regroupés dessous au survol.
- [ ] Chat habillé, les liens `http` sont cliquables, bouton `[c]` au survol pour copier.
- [ ] Cadre du joueur à gauche du centre, cible à droite quand tu cibles quelqu'un.
- [ ] Barre d'expérience ou de réputation en bas, avec le bon rang de réputation.

**En combat (un ou deux monstres)**
- [ ] Aucune erreur Lua pendant ni après le combat.
- [ ] Plaques de nom AeonUI : rouge quand le monstre t'attaque ; nom seul sur les alliés.
- [ ] Barre d'incantation du monstre visible sur sa plaque et sur le cadre de cible.
- [ ] Ta barre d'incantation apparaît sous les recharges (Dégâts, Tank) ou sous ton cadre (Soigneur).
- [ ] Pendant le combat, aucun message « Échec d'une action d'interface ».

**En groupe ou en raid**
- [ ] Cadres de groupe AeonUI à gauche, cadres Blizzard cachés.
- [ ] Un membre trop loin est grisé ; un membre avec un débuff que ta classe dissipe a une bordure colorée.
- [ ] En raid : grille par groupes de 5 ; clic gauche cible le membre.
- [ ] Nom long tronqué à 8 caractères (réglable dans les options).

**Druide, voleur, chasseur, démoniste, prêtre**
- [ ] Changer de forme ou passer furtif change bien la barre 1.
- [ ] Barre du familier et barre de posture affichées et déplaçables.
- [ ] Contrôle mental ou Yeux de la bête : ta barre 1 s'efface, la barre spéciale Blizzard apparaît.

**Options**
- [ ] Options > Chat : « Couleur et opacité du fond des fenêtres » ouvre un sélecteur avec un curseur d'opacité.
- [ ] Options > Général : « Échelle de l'interface » à 1,20 grossit tout, retour à 1,00 remet en place.
- [ ] Options > Profils : Exporter remplit la zone de texte, Ctrl-C fonctionne ; la zone défile à la molette.

**Barres, infobulles, absence, boss**
- [ ] `/aeon kb`, survoler un bouton, appuyer sur une touche : la touche lance ce bouton. Échap pour fermer.
- [ ] Options > Barres d'action, « Visible seulement au survol » sur une barre : elle n'apparaît qu'au survol.
- [ ] Options > Interface épurée, « Chiffres de recharge » : les secondes s'affichent sur les recharges.
- [ ] Survol d'un joueur : sa cible et son rang de guilde dans l'infobulle.
- [ ] `/afk` hors combat : écran d'absence ; tout revient en reprenant la main ou si un monstre t'attaque.
- [ ] En donjon, face à un boss : cadres de boss à droite de l'écran.

**Recherche, déplacement précis, profil au groupe**
- [ ] Options > AeonUI : tape « butin » dans la recherche en haut. Clique le résultat : la page Butin s'ouvre.
- [ ] `/aeon unlock`, clique un cadre : une case X / Y apparaît en haut. Tourne la molette sur le cadre : il bouge de 1 px. Tape 0 et 0 puis Entrée : il se centre sur son point.
- [ ] En groupe avec un autre testeur : Options > Profils, « Envoyer ce profil à mon groupe ». L'autre reçoit une question ; « Oui » prend ton profil. Dis-nous combien de temps l'envoi a pris.

**Sacs**
- [ ] Options > Sacs : coche le module, puis appuie sur B. Tous tes sacs s'ouvrent dans une seule fenêtre. B ou Échap la referment.
- [ ] Tape un nom dans la recherche : les autres objets s'assombrissent. « Trier » range les sacs.
- [ ] En combat, clic droit sur une potion dans la fenêtre : elle est bue. Dis-nous si une erreur apparaît.
- [ ] Chez un marchand, la fenêtre s'ouvre toute seule et les objets gris portent une pièce.

**Niveau d'objet, utilitaire de raid**
- [ ] Survole un autre joueur hors combat : après un instant, son niveau d'objet moyen s'ajoute à l'infobulle.
- [ ] Inspecte un joueur : le niveau de chaque objet s'affiche sur ses emplacements, avec la moyenne en haut.
- [ ] Options > Utilitaire de raid : coche le module. En groupe, un bouton « Raid » apparaît en haut. Ouvre-le et essaie l'appel prêt, le compte à rebours, un marqueur sur ta cible et un marqueur au sol. Dis-nous si le marqueur au sol se pose.

**Chat et butin**
- [ ] Écris quelques lignes dans le chat, puis `/reload` : elles reviennent sous « Session précédente ».
- [ ] Options > Chat, « Mots-clés » : mets `tank`. Quand quelqu'un écrit tank, le mot est surligné et un son joue.
- [ ] Options > Chat, coche « Anti-spam ». En commerce, une annonce répétée n'apparaît plus qu'une fois par minute.
- [ ] Options > Butin : coche le module. Tue un monstre et ouvre son butin : la fenêtre s'ouvre sous ta souris.
- [ ] En groupe, un objet vert tombe : une barre de jet apparaît en haut. Clique un bouton, elle disparaît. Dis-nous si le jet est bien pris.

**Panneaux de données**
- [ ] Options > Panneaux de données : coche le module. Un bandeau apparaît en bas à gauche avec tes coordonnées, ta vitesse, ta régénération de mana et tes quêtes.
- [ ] Active le panneau 3 et frappe un mannequin : l'emplacement DPS montre un chiffre ou un tiret. Dis-nous lequel.
- [ ] Options > Barre du haut, « Emplacement libre à gauche » : choisis Coordonnées, elles s'affichent dans la barre.

**Filtres de style des plaques**
- [ ] Options > Plaques de nom > Filtres de style, règle 1 : « Active », « Incante » sur « Oui », « Lueur ». Un ennemi qui incante s'entoure d'un halo.
- [ ] Règle 2 : « Vie sous » 30 %, « Taille » 1,5. Un ennemi presque mort grossit. Dis-nous si ça marche aussi en plein combat.
- [ ] Règle 3 : « Noms » `totem`, « Masquer ». Les totems n'ont plus de plaque.

**Indicateurs de groupe, portrait**
- [ ] En groupe, lance un appel (`/readycheck`) : chaque cadre montre une icône d'attente, puis prêt ou pas prêt.
- [ ] Un soigneur te soigne : une barre verte claire apparaît au bout de ta vie sur les cadres de groupe.
- [ ] Options > Cadres de groupe, « Affichage de la menace » sur « Lueur » : un halo orange ou rouge entoure le membre qui prend l'agro.
- [ ] En raid, « Cadres des tanks principaux » : les tanks assignés ont leur propre colonne.
- [ ] Options > Cadres d'unité, bloc Joueur, « Portrait » : ton portrait s'affiche à gauche du cadre.

**Textes et filtres d'auras**
- [ ] Options > Cadres d'unité, bloc Cible, « Format de vie » : taper `[cur] / [max] ([perc])`, la vie de la cible s'affiche ainsi, même en combat.
- [ ] Options > Cadres d'unité, bloc Cible, « Filtre des débuffs » sur « Les miens » : seuls tes débuffs restent. Sur les plaques, c'est le réglage par défaut.
- [ ] Options > Cadres d'unité, « Liste noire » : un identifiant de sort y disparaît des cadres, des plaques et du co-tank.

**Valeurs secrètes et recharges**
- [ ] `/aeon diag` : copier la ligne « Midnight » dans ton signalement (elle dit ce que ton client permet).
- [ ] Options > Interface épurée, « Texte de recharge coloré » : sur les barres AeonUI, secondes en jaune, dernières secondes en rouge avec une décimale.
- [ ] Options > Cadres d'unité, « Couleur de vie du rouge au vert » : la barre change de couleur en perdant de la vie, même en combat.
- [ ] En groupe, un membre qui s'éloigne est grisé, y compris en combat.

## 6. Signaler un problème

Pour chaque problème, envoie :

1. **Ce que tu faisais** (une phrase) et **ce que tu attendais**.
2. **Une capture d'écran** en plein écran.
3. **Le texte de l'erreur** s'il y en a une : dans la fenêtre d'erreur, Ctrl-A puis Ctrl-C.
4. Le résultat de cette commande, copié depuis le chat (bouton `[c]` au survol de la fenêtre) :
   ```
   /aeon diag
   ```
5. Ta classe, ton niveau, et si tu étais seul, en groupe ou en raid.

## 7. Tout remettre comme avant

```
/aeon uninstall
```

Rend tous les réglages Blizzard et coupe AeonUI. Puis `/reload`. Pour repartir de zéro sur le
profil actuel sans désinstaller : `/aeon reset`.

## Commandes utiles

```
/aeon             options
/aeon setup       installation rapide (profils Dégâts, Soigneur, Tank)
/aeon unlock      déplacer les cadres        /aeon lock   figer
/aeon kb          lier des touches aux boutons en les survolant
/aeon status      profil actif et état des modules
/aeon diag        infos à joindre à un signalement
/aeon reset       remettre le profil actuel par défaut
/aeon uninstall   tout rendre à Blizzard
```

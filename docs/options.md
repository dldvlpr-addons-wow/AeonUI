# AeonUI — Référence des réglages

Généré par `tools/generate_options_doc.lua` depuis la fenêtre d'options (`/aeon`). Valeurs par défaut d'un profil neuf.

## Pages

- [Général](#général)
- [Modules](#modules)
- [Profils](#profils)
- [Maintenance](#maintenance)
- [Alertes](#alertes)
- [Autre tank](#autre-tank)
- [Barre du haut](#barre-du-haut)
- [Barres d'action AeonUI](#barres-daction-aeonui)
- [Barres de données AeonUI](#barres-de-données-aeonui)
- [Barres de nom](#barres-de-nom)
- [Barres de ressources](#barres-de-ressources)
- [Butin](#butin)
- [Cadres Blizzard déplaçables](#cadres-blizzard-déplaçables)
- [Cadres d'unité](#cadres-dunité)
- [Cadres d'unité AeonUI](#cadres-dunité-aeonui)
- [Cadres de groupe et de raid AeonUI](#cadres-de-groupe-et-de-raid-aeonui)
- [Chat AeonUI](#chat-aeonui)
- [Confort automatique](#confort-automatique)
- [Curseur et réticule](#curseur-et-réticule)
- [Écran d'absence](#écran-dabsence)
- [Fiche de personnage](#fiche-de-personnage)
- [Gestionnaire de recharges](#gestionnaire-de-recharges)
- [Habillage](#habillage)
- [Interface épurée](#interface-épurée)
- [Menu radial](#menu-radial)
- [Minimap AeonUI](#minimap-aeonui)
- [Minuteur d'attaque](#minuteur-dattaque)
- [Panneaux de données](#panneaux-de-données)
- [Plaques de nom AeonUI](#plaques-de-nom-aeonui)
- [Rappels](#rappels)
- [Recharges de raid](#recharges-de-raid)
- [Recherche de groupe](#recherche-de-groupe)
- [Sacs](#sacs)
- [Suivi de quêtes AeonUI](#suivi-de-quêtes-aeonui)
- [Suivi par ID](#suivi-par-id)
- [Utilitaire de raid](#utilitaire-de-raid)

## Général

Chaque module s'active ou se désactive séparément. Les changements s'appliquent tout de suite.

- **Langue** — liste, défaut **Langue du jeu**

### Apparence

- **Police de AeonUI** — liste, défaut **Arial Narrow**
- **Taille du texte** — curseur, défaut **12**, 9 – 18, pas 1
- **Contour du texte** — liste, défaut **Aucun**
- **Couleur d'accent** — couleur, défaut **#3FA8F4**
- **Couleur de fond** — couleur, défaut **#0C0F14**
- **Couleur de bordure** — couleur, défaut **#000000**
- **Échelle pixel perfect** — case, défaut **cochée**  
  _Met toute l'interface à l'échelle pour qu'une unité vaille un pixel d'écran : bordures nettes à 1 px. Décocher rend l'échelle précédente._
- **Échelle de l'interface** — curseur, défaut **1.00**, 0.5 – 1.5, pas 0.05  
  _Multiplie l'échelle (pixel perfect ou celle du jeu) : 1,00 = inchangée, 1,20 = plus grand. Hors combat._
- **Taille de la fenêtre d'options** — curseur, défaut **1.00**, 0.8 – 1.5, pas 0.05

### Cadres mobiles

- **Grille d'alignement en mode déverrouillé** — liste, défaut **Aucune**
- **Déverrouiller / verrouiller les cadres mobiles** — bouton
- **Réinitialiser toutes les positions** — bouton

## Modules

Active ou coupe chaque module ici. Chacun a sa propre page dans la liste de gauche. Survole un module pour lire ce qu'il fait.

- **Alertes** — case, défaut **cochée**  
  _Grands messages à l'écran : entrée et sortie de combat, mort d'un membre du groupe, et chronomètre de combat._
- **Autre tank** — case, défaut **décochée**  
  _Quand tu tankes en raid, une barre de vie pour l'autre tank. Clique dessus pour le cibler. Tank = rôle de groupe, assignation « tank principal », ou forcé ci-dessous._
- **Barre du haut** — case, défaut **cochée**  
  _Une fine barre en haut de l'écran : amis et guilde en ligne, heure, or, durabilité, places libres dans les sacs, FPS et latence, et un bouton pierre de foyer._
- **Barres d'action AeonUI** — case, défaut **décochée**  
  _Six barres d'action déplaçables faites de boutons Blizzard (icônes, recharges, compteurs, raccourcis, glisser-déposer gérés par le code Blizzard) : boutons par barre, par ligne, taille, espacement, opacité. La barre 1 change de page avec les postures et la furtivité. Remplace les barres Blizzard._
- **Barres de données AeonUI** — case, défaut **décochée**  
  _Barre d'expérience (avec le bonus de repos, cachée au niveau maximum) et barre de la réputation suivie, déplaçables, avec texte et infobulle. Remplacent les barres Blizzard._
- **Barres de nom** — case, défaut **cochée**  
  _Deux chevrons autour de la barre de nom de ta cible, pour ne jamais la perdre dans un pack. Celui de gauche s'écarte quand la cible incante._
- **Barres de ressources** — case, défaut **décochée**  
  _Votre vie, puissance, points de combo et mana de druide en barres séparées, placées et ancrées où vous voulez._
- **Butin** — case, défaut **décochée**  
  _Fenêtre de butin au thème (au curseur ou sur son mover) et barres de jets de groupe : besoin, cupidité, désenchantement, passer, temps restant._
- **Cadres Blizzard déplaçables** — case, défaut **décochée**  
  _Gestionnaire de recharges (essentiel, utilitaire, icônes de buff, barres de buff), buffs et débuffs du joueur sur des movers AeonUI, jamais reparentés. Chacun peut rester à Edit Mode._
- **Cadres d'unité** — case, défaut **décochée**  
  _Retouches des cadres Blizzard du joueur, de la cible, du focus et du raid : mode sombre, vie et noms à la couleur de classe, et repère de combat sur la cible._
- **Cadres d'unité AeonUI** — case, défaut **décochée**  
  _Remplace les cadres Blizzard du joueur, de la cible, de la cible de la cible, du focus et du familier par des cadres AeonUI : vie, puissance, barre d'incantation, auras, nom, niveau, repères de combat, repos et chef, marqueur de raid, points de combo. Déplaçables avec /aeon unlock._
- **Cadres de groupe et de raid AeonUI** — case, défaut **décochée**  
  _Remplace les cadres Blizzard de groupe et de raid par des grilles AeonUI : vie, puissance, nom, icônes de rôle et de chef, marqueur de raid, bordures d'agro et de débuff dissipable, atténuation hors de portée. Clic pour cibler, clic droit pour le menu._
- **Chat AeonUI** — case, défaut **décochée**  
  _Fenêtres de chat au thème (fond, police, onglets plats, boutons latéraux cachés, sans fondu), URL cliquables, bouton de copie du chat, noms de canaux courts, couleur de classe partout, horodatage, zone de saisie en haut ou en bas._
- **Confort automatique** — case, défaut **cochée**  
  _Les petites corvées faites pour toi : réparation et vente des objets gris chez le marchand, maintien de ALT pour libérer l'esprit, invitations des amis et de la guilde acceptées, suppression d'objet pré-remplie._
- **Curseur et réticule** — case, défaut **décochée**  
  _Un anneau autour du curseur pour le retrouver tout de suite, et un réticule au centre de l'écran._
- **Écran d'absence** — case, défaut **décochée**  
  _Quand tu passes absent hors combat, l'interface s'efface, la caméra tourne lentement et un bandeau montre ton personnage et la durée de l'absence._
- **Fiche de personnage** — case, défaut **cochée**  
  _Niveau d'objet sur chaque emplacement de la fiche, à la couleur de qualité, le niveau moyen, et un repère sur les pièces enchantables sans enchantement. Mêmes niveaux sur la fenêtre d'inspection, et niveau moyen des joueurs dans leur infobulle._
- **Gestionnaire de recharges** — case, défaut **décochée**  
  _Réglages sort par sort du gestionnaire de recharges Blizzard : afficher ou masquer chaque sort sur sa barre, lueur quand il est prêt ou en permanence._
- **Habillage** — case, défaut **cochée**  
  _Infobulles sombres avec nom et bordure à la couleur de classe, et deux flèches autour de la barre de nom de ta cible._
- **Interface épurée** — case, défaut **cochée**  
  _Moins d'encombrement et un accès direct à des réglages Blizzard. Tout réglage Blizzard changé ici est rendu quand tu coupes l'option._
- **Menu radial** — case, défaut **décochée**  
  _Maintenir une touche : un anneau de sorts, objets, macros et montures s'ouvre autour du curseur ; relâcher sur l'un le lance. Hors combat seulement._
- **Minimap AeonUI** — case, défaut **décochée**  
  _Minimap carrée (ou ronde) à la taille voulue, bordure au thème, nom de zone et coordonnées, zoom à la molette, boutons d'addons regroupés en rangée sous la carte. Déplaçable avec /aeon unlock._
- **Minuteur d'attaque** — case, défaut **décochée**  
  _Une barre par arme jusqu'à votre prochaine attaque automatique. Demande l'événement PLAYER_SWING du client._
- **Panneaux de données** — case, défaut **décochée**  
  _Bandeaux d'informations libres sur les movers : coordonnées, quêtes, régénération, vitesse, DPS et les textes de la barre du haut._
- **Plaques de nom AeonUI** — case, défaut **décochée**  
  _Remplace l'habillage Blizzard des plaques de nom par des barres AeonUI : vie (couleurs de réaction, de classe, de menace), nom, niveau, barre d'incantation avec icône, marqueur de raid, débuffs, surbrillance de la cible. Compatible avec le module des chevrons de cible._
- **Rappels** — case, défaut **cochée**  
  _Hors combat uniquement : te prévient quand un buff de classe manque (seulement pour les sorts que tu connais), quand la durabilité est basse, quand tes sacs sont pleins, ou quand tu as oublié de te camoufler._
- **Recharges de raid** — case, défaut **décochée**  
  _Charges de rez en combat du groupe et verrou de Furie sanguinaire / Héroïsme sur vous._
- **Recherche de groupe** — case, défaut **décochée**  
  _Raccourcis de l'outil de recherche de groupe : inscription en un clic quand ton rôle est évident, et note de candidature mémorisée._
- **Sacs** — case, défaut **décochée**  
  _Une seule fenêtre pour le sac à dos et les sacs équipés, sur son mover : recherche, tri, niveau d'objet sur l'équipement, objets gris signalés, bordure de qualité, recharges, emplacements libres et or. La banque reste celle de Blizzard._
- **Suivi de quêtes AeonUI** — case, défaut **décochée**  
  _Le suivi d'objectifs Blizzard sur un support déplaçable, à la hauteur voulue, en-têtes au thème, replié de lui-même en combat ou en instance._
- **Suivi par ID** — case, défaut **décochée**  
  _Une rangée d'icônes pour les sorts et auras choisis par leur identifiant : aura présente sur toi ou posée par toi sur la cible (durée, stacks), sinon recharge du sort._
- **Utilitaire de raid** — case, défaut **décochée**  
  _Bouton « Raid » sur son mover, visible en groupe : appel prêt, vérification des rôles, compte à rebours, marqueurs de cible et marqueurs au sol._

## Profils

Un profil contient tous les réglages de AeonUI. « Default » est partagé par tous tes personnages ; crée-en un pour ce personnage pour qu'il ait ses propres réglages.

- **Profil utilisé par ce personnage** — liste, défaut **Default**
- **Créer un profil pour ce personnage (copie de l'actuel)** — bouton
- **Remettre le profil actuel par défaut** — bouton
- **Supprimer le profil actuel (retour à Default)** — bouton

### Partage

> Partage un profil en texte : exporte-le ici, colle-le sur un autre personnage ou envoie-le à un ami. Importer remplace le profil actuel.

- **Chaîne de profil** — zone de texte

> N'exporter que ce qui est coché. Importer une chaîne partielle ne change que ces parties.

- **Thème** — case, défaut **cochée**
- **Listes d'auras** — case, défaut **cochée**
- **Alertes** — case, défaut **cochée**
- **Autre tank** — case, défaut **cochée**
- **Barre du haut** — case, défaut **cochée**
- **Barres d'action AeonUI** — case, défaut **cochée**
- **Barres de données AeonUI** — case, défaut **cochée**
- **Barres de nom** — case, défaut **cochée**
- **Barres de ressources** — case, défaut **cochée**
- **Butin** — case, défaut **cochée**
- **Cadres Blizzard déplaçables** — case, défaut **cochée**
- **Cadres d'unité** — case, défaut **cochée**
- **Cadres d'unité AeonUI** — case, défaut **cochée**
- **Cadres de groupe et de raid AeonUI** — case, défaut **cochée**
- **Chat AeonUI** — case, défaut **cochée**
- **Confort automatique** — case, défaut **cochée**
- **Curseur et réticule** — case, défaut **cochée**
- **Écran d'absence** — case, défaut **cochée**
- **Fiche de personnage** — case, défaut **cochée**
- **Gestionnaire de recharges** — case, défaut **cochée**
- **Habillage** — case, défaut **cochée**
- **Interface épurée** — case, défaut **cochée**
- **Menu radial** — case, défaut **cochée**
- **Minimap AeonUI** — case, défaut **cochée**
- **Minuteur d'attaque** — case, défaut **cochée**
- **Panneaux de données** — case, défaut **cochée**
- **Plaques de nom AeonUI** — case, défaut **cochée**
- **Rappels** — case, défaut **cochée**
- **Recharges de raid** — case, défaut **cochée**
- **Recherche de groupe** — case, défaut **cochée**
- **Sacs** — case, défaut **cochée**
- **Suivi de quêtes AeonUI** — case, défaut **cochée**
- **Suivi par ID** — case, défaut **cochée**
- **Utilitaire de raid** — case, défaut **cochée**
- **Exporter le profil actuel** — bouton
- **Importer la chaîne ci-dessus** — bouton
- **Envoyer ce profil à mon groupe** — bouton

### Profil par spécialisation

> Chaque spécialisation peut avoir son profil : changer de spé change de profil. « Aucun » : le profil du personnage ci-dessus.

> Ce client n'expose aucune spécialisation.

### Préréglages de rôle

> Les préréglages de rôle ajustent cadres de groupe, cadres d'unité et plaques de nom pour un rôle. Applique-en un au profil actuel, ou crée un profil dédié pour ce personnage (copie de l'actuel, puis ajusté).

- **Rôle** — liste, défaut **Soigneur**
- **Appliquer ce rôle au profil actuel** — bouton
- **Basculer sur le profil de base de ce rôle (créé s'il manque)** — bouton

## Maintenance

Le diagnostic liste ce que ce client de jeu propose, pour signaler un problème. Désinstaller rend tous les réglages Blizzard que AeonUI a changés.

- **Revoir la fenêtre de bienvenue** — bouton
- **Lancer le diagnostic (/aeon diag)** — bouton
- **Désinstaller proprement (/aeon uninstall)** — bouton

## Alertes

Grands messages à l'écran : entrée et sortie de combat, mort d'un membre du groupe, et chronomètre de combat.

- **Activer : Alertes** — case, défaut **cochée**
- **Afficher l'entrée et la sortie de combat** — case, défaut **cochée**
- **Afficher** — liste, défaut **Entrée et sortie**
- **Texte d'entrée (vide = défaut)** — zone de texte
- **Couleur d'entrée** — couleur, défaut **#FF4C4C**
- **Texte de sortie (vide = défaut)** — zone de texte
- **Couleur de sortie** — couleur, défaut **#4CFF4C**
- **Taille du texte** — curseur, défaut **22**, 12 – 48, pas 2
- **Avec un son** — case, défaut **décochée**
  - **Son** — liste, défaut **Clic**
  - **Son importé (vide = son par défaut)** — zone de texte

> Fichier .ogg ou .mp3, chemin depuis le dossier du jeu, ex. Interface\AddOns\MesSons\alerte.ogg. Relancer le jeu après avoir ajouté le fichier.

  - **Écouter** — bouton
- **Annoncer la mort des membres du groupe** — case, défaut **cochée**
- **Taille du texte** — curseur, défaut **22**, 12 – 48, pas 2
- **Avec un son** — case, défaut **cochée**
  - **Son** — liste, défaut **Avertissement de raid**
  - **Son importé (vide = son par défaut)** — zone de texte

> Fichier .ogg ou .mp3, chemin depuis le dossier du jeu, ex. Interface\AddOns\MesSons\alerte.ogg. Relancer le jeu après avoir ajouté le fichier.

  - **Écouter** — bouton
- **Chronomètre de combat** — case, défaut **décochée**
- **Déverrouiller / verrouiller les cadres mobiles** — bouton

## Autre tank

Quand tu tankes en raid, une barre de vie pour l'autre tank. Clique dessus pour le cibler. Tank = rôle de groupe, assignation « tank principal », ou forcé ci-dessous.

- **Activer : Autre tank** — case, défaut **décochée**
- **Je suis tank (même sans rôle assigné)** — case, défaut **décochée**
- **Aussi en groupe à 5** — case, défaut **décochée**
- **Couleur de classe** — case, défaut **cochée**
- **Afficher le nom** — case, défaut **cochée**
- **Largeur** — curseur, défaut **150**, 80 – 300, pas 10
- **Hauteur** — curseur, défaut **20**, 12 – 40, pas 2
- **Afficher ses débuffs sous la barre (quand le client le permet)** — case, défaut **cochée**
- **Quels débuffs** — liste, défaut **Tous**
- **Afficher le nombre de stacks** — case, défaut **cochée**
- **Débuffs affichés** — curseur, défaut **4**, 1 – 8, pas 1
- **Taille des icônes de débuff** — curseur, défaut **20**, 12 – 32, pas 2
- **Aperçu et déplacement (déverrouiller)** — bouton

## Barre du haut

Une fine barre en haut de l'écran : amis et guilde en ligne, heure, or, durabilité, places libres dans les sacs, FPS et latence, et un bouton pierre de foyer.

- **Activer : Barre du haut** — case, défaut **cochée**
- **Position** — liste, défaut **En haut**
- **Déverrouiller / verrouiller les cadres mobiles** — bouton
- **Réinitialiser la position de la barre** — bouton
- **Opacité du fond** — curseur, défaut **0.75**, 0 – 1, pas 0.05
- **Masquer la barre en combat** — case, défaut **décochée**
- **Garder FPS et latence visibles en combat** — case, défaut **cochée**  
  _Disponible quand « Masquer la barre en combat » est coché. Sinon, la barre et ses FPS restent déjà visibles en combat._

### Horloge

- **Format 24 h** — case, défaut **cochée**
- **Afficher l'heure du serveur au lieu de l'heure locale** — case, défaut **décochée**
- **Afficher « zzz » à côté de l'heure au repos** — case, défaut **cochée**

### Éléments affichés sur la barre :

- **Amis en ligne** — case, défaut **cochée**
- **Membres de la guilde en ligne** — case, défaut **cochée**
- **Heure** — case, défaut **cochée**
- **Or** — case, défaut **cochée**
- **Durabilité** — case, défaut **cochée**
- **Places libres dans les sacs** — case, défaut **cochée**
- **FPS et latence** — case, défaut **cochée**
- **Menu Voyage (téléportations de mage, druide et chaman)** — case, défaut **cochée**
- **Bouton pierre de foyer** — case, défaut **cochée**
- **Emplacement libre à gauche** — liste, défaut **Aucun**
- **Emplacement libre à droite** — liste, défaut **Aucun**

## Barres d'action AeonUI

Six barres d'action déplaçables faites de boutons Blizzard (icônes, recharges, compteurs, raccourcis, glisser-déposer gérés par le code Blizzard) : boutons par barre, par ligne, taille, espacement, opacité. La barre 1 change de page avec les postures et la furtivité. Remplace les barres Blizzard.

- **Activer : Barres d'action AeonUI** — case, défaut **décochée**

> Les barres Blizzard reviennent après un /reload une fois ce module coupé. Les raccourcis sont ceux de Blizzard (Options > Raccourcis).

- **Masquer les barres d'action Blizzard** — case, défaut **cochée**
- **Micro-menu (personnage, grimoire, options…)** — liste, défaut **Déplaçable (/aeon unlock)**
- **Barre des sacs** — liste, défaut **Déplaçable (/aeon unlock)**
- **Barre de posture (postures, formes, auras, furtivité)** — liste, défaut **Déplaçable (/aeon unlock)**
- **Barre de totems du chaman (Appel des éléments)** — liste, défaut **Déplaçable (/aeon unlock)**
- **Barre du familier** — liste, défaut **Déplaçable (/aeon unlock)**
- **Afficher les raccourcis sur les boutons** — case, défaut **cochée**
- **Afficher le nom des macros sur les boutons** — case, défaut **cochée**
- **Mode raccourcis (/aeon kb)** — bouton  
  _Survoler un bouton et appuyer sur une touche pour la lier. Échap sur un bouton efface ses touches, Échap ailleurs ferme le mode._
- **Déverrouiller (déplacer les cadres)** — bouton

### Barre d'action 1

- **Afficher cette barre** — case, défaut **cochée**
- **Copier les réglages depuis** — liste
- **Boutons** — curseur, défaut **12**, 1 – 12, pas 1
- **Boutons par ligne** — curseur, défaut **12**, 1 – 12, pas 1
- **Taille des boutons** — curseur, défaut **36**, 20 – 64, pas 1
- **Espacement** — curseur, défaut **4**, 0 – 16, pas 1
- **Opacité** — curseur, défaut **1.0**, 0.1 – 1, pas 0.1
- **Visible seulement au survol** — case, défaut **décochée**

### Barre d'action 2

- **Afficher cette barre** — case, défaut **cochée**
- **Copier les réglages depuis** — liste
- **Boutons** — curseur, défaut **12**, 1 – 12, pas 1
- **Boutons par ligne** — curseur, défaut **12**, 1 – 12, pas 1
- **Taille des boutons** — curseur, défaut **36**, 20 – 64, pas 1
- **Espacement** — curseur, défaut **4**, 0 – 16, pas 1
- **Opacité** — curseur, défaut **1.0**, 0.1 – 1, pas 0.1
- **Visible seulement au survol** — case, défaut **décochée**

### Barre d'action 3

- **Afficher cette barre** — case, défaut **cochée**
- **Copier les réglages depuis** — liste
- **Boutons** — curseur, défaut **12**, 1 – 12, pas 1
- **Boutons par ligne** — curseur, défaut **12**, 1 – 12, pas 1
- **Taille des boutons** — curseur, défaut **36**, 20 – 64, pas 1
- **Espacement** — curseur, défaut **4**, 0 – 16, pas 1
- **Opacité** — curseur, défaut **1.0**, 0.1 – 1, pas 0.1
- **Visible seulement au survol** — case, défaut **décochée**

### Barre d'action 4

- **Afficher cette barre** — case, défaut **décochée**
- **Copier les réglages depuis** — liste
- **Boutons** — curseur, défaut **12**, 1 – 12, pas 1
- **Boutons par ligne** — curseur, défaut **1**, 1 – 12, pas 1
- **Taille des boutons** — curseur, défaut **36**, 20 – 64, pas 1
- **Espacement** — curseur, défaut **4**, 0 – 16, pas 1
- **Opacité** — curseur, défaut **1.0**, 0.1 – 1, pas 0.1
- **Visible seulement au survol** — case, défaut **décochée**

### Barre d'action 5

- **Afficher cette barre** — case, défaut **décochée**
- **Copier les réglages depuis** — liste
- **Boutons** — curseur, défaut **12**, 1 – 12, pas 1
- **Boutons par ligne** — curseur, défaut **1**, 1 – 12, pas 1
- **Taille des boutons** — curseur, défaut **36**, 20 – 64, pas 1
- **Espacement** — curseur, défaut **4**, 0 – 16, pas 1
- **Opacité** — curseur, défaut **1.0**, 0.1 – 1, pas 0.1
- **Visible seulement au survol** — case, défaut **décochée**

### Barre d'action 6

- **Afficher cette barre** — case, défaut **décochée**
- **Copier les réglages depuis** — liste
- **Boutons** — curseur, défaut **12**, 1 – 12, pas 1
- **Boutons par ligne** — curseur, défaut **12**, 1 – 12, pas 1
- **Taille des boutons** — curseur, défaut **36**, 20 – 64, pas 1
- **Espacement** — curseur, défaut **4**, 0 – 16, pas 1
- **Opacité** — curseur, défaut **1.0**, 0.1 – 1, pas 0.1
- **Visible seulement au survol** — case, défaut **décochée**

## Barres de données AeonUI

Barre d'expérience (avec le bonus de repos, cachée au niveau maximum) et barre de la réputation suivie, déplaçables, avec texte et infobulle. Remplacent les barres Blizzard.

- **Activer : Barres de données AeonUI** — case, défaut **décochée**

> Les barres Blizzard reviennent après un /reload une fois ce module coupé. Suis une réputation depuis le panneau de réputation.

- **Cacher les barres Blizzard d'expérience et de réputation** — case, défaut **cochée**
- **Déverrouiller (déplacer les cadres)** — bouton

### Expérience

- **Afficher cette barre** — case, défaut **cochée**
- **Largeur** — curseur, défaut **300**, 100 – 800, pas 10
- **Hauteur** — curseur, défaut **10**, 4 – 30, pas 1
- **Texte sur la barre** — case, défaut **cochée**

### Réputation

- **Afficher cette barre** — case, défaut **cochée**
- **Largeur** — curseur, défaut **300**, 100 – 800, pas 10
- **Hauteur** — curseur, défaut **10**, 4 – 30, pas 1
- **Texte sur la barre** — case, défaut **cochée**

## Barres de nom

Deux chevrons autour de la barre de nom de ta cible, pour ne jamais la perdre dans un pack. Celui de gauche s'écarte quand la cible incante.

- **Activer : Barres de nom** — case, défaut **cochée**
- **Cibles hostiles seulement** — case, défaut **cochée**
- **Taille** — curseur, défaut **26**, 8 – 48, pas 2
- **Écart avec la barre de nom** — curseur, défaut **4**, 0 – 40, pas 1
- **Couleur hors combat** — couleur, défaut **#FFD119**
- **Couleur en combat** — couleur, défaut **#FF4C33**
- **Couleur quand un autre tank a l'agro** — couleur, défaut **#4C99FF**
- **Écarter le chevron gauche pendant une incantation de la cible** — case, défaut **cochée**
- **Écart supplémentaire pendant l'incantation** — curseur, défaut **8**, 0 – 30, pas 1

## Barres de ressources

Votre vie, puissance, points de combo et mana de druide en barres séparées, placées et ancrées où vous voulez.

- **Activer : Barres de ressources** — case, défaut **décochée**
- **Orientation** — liste, défaut **Horizontale**
- **Longueur** — curseur, défaut **220**, 60 – 500, pas 2
- **Afficher** — liste, défaut **Toujours**
- **Opacité hors combat** — curseur, défaut **1.00**, 0 – 1, pas 0.05

### Vie

- **Afficher** — case, défaut **décochée**
- **Épaisseur** — curseur, défaut **14**, 4 – 40, pas 1
- **Texte** — liste, défaut **Valeur | pourcentage**
- **Couleur de classe** — case, défaut **cochée**

### Puissance

- **Afficher** — case, défaut **cochée**
- **Épaisseur** — curseur, défaut **12**, 4 – 40, pas 1
- **Texte** — liste, défaut **Valeur courante**
- **Repère à (%, 0 = aucun)** — curseur, défaut **0**, 0 – 100, pas 5

### Points de combo

- **Afficher** — case, défaut **cochée**
- **Épaisseur** — curseur, défaut **8**, 4 – 30, pas 1

### Mana en forme de druide

- **Afficher** — case, défaut **cochée**
- **Épaisseur** — curseur, défaut **6**, 2 – 30, pas 1

## Butin

Fenêtre de butin au thème (au curseur ou sur son mover) et barres de jets de groupe : besoin, cupidité, désenchantement, passer, temps restant.

- **Activer : Butin** — case, défaut **décochée**
- **Fenêtre de butin AeonUI** — case, défaut **cochée**
- **Ouvrir au curseur (sinon sur son mover)** — case, défaut **cochée**
- **Barres de jets AeonUI** — case, défaut **cochée**
- **Largeur** — curseur, défaut **300**, 200 – 500, pas 10
- **Déverrouiller / verrouiller les cadres mobiles** — bouton

## Cadres Blizzard déplaçables

Gestionnaire de recharges (essentiel, utilitaire, icônes de buff, barres de buff), buffs et débuffs du joueur sur des movers AeonUI, jamais reparentés. Chacun peut rester à Edit Mode.

- **Activer : Cadres Blizzard déplaçables** — case, défaut **décochée**

> Taille des icônes et lignes restent dans Edit Mode ; seule la position est AeonUI. Les positions Blizzard reviennent après un /reload une fois ce module coupé.

- **Recharges : essentiel** — liste, défaut **Déplaçable (/aeon unlock)**
- **Recharges : utilitaire** — liste, défaut **Déplaçable (/aeon unlock)**
- **Recharges : icônes de buff** — liste, défaut **Déplaçable (/aeon unlock)**
- **Recharges : barres de buff** — liste, défaut **Déplaçable (/aeon unlock)**
- **Buffs** — liste, défaut **Déplaçable (/aeon unlock)**
- **Débuffs** — liste, défaut **Déplaçable (/aeon unlock)**
- **Déverrouiller (déplacer les cadres)** — bouton

## Cadres d'unité

Retouches des cadres Blizzard du joueur, de la cible, du focus et du raid : mode sombre, vie et noms à la couleur de classe, et repère de combat sur la cible.

- **Activer : Cadres d'unité** — case, défaut **décochée**
- **Mode sombre (bordures des cadres assombries)** — case, défaut **cochée**
- **Barres de vie à la couleur de classe pour les joueurs** — case, défaut **cochée**
- **Noms à la couleur de classe sur les cadres de raid** — case, défaut **cochée**
- **Épées croisées à côté de la cible quand elle est en combat** — case, défaut **cochée**

## Cadres d'unité AeonUI

Remplace les cadres Blizzard du joueur, de la cible, de la cible de la cible, du focus et du familier par des cadres AeonUI : vie, puissance, barre d'incantation, auras, nom, niveau, repères de combat, repos et chef, marqueur de raid, points de combo. Déplaçables avec /aeon unlock.

- **Activer : Cadres d'unité AeonUI** — case, défaut **décochée**

> Les cadres Blizzard reviennent après un /reload une fois ce module coupé.

- **Couleur de classe pour les joueurs (couleur de réaction sinon)** — case, défaut **cochée**
- **Couleur de vie du rouge au vert selon le pourcentage** — case, défaut **décochée**
- **Soins entrants et absorptions** — case, défaut **cochée**
- **Texte de vie** — liste, défaut **Valeur courante**
- **Texte de puissance** — liste, défaut **Aucun**
- **Opacité des cadres estompés** — curseur, défaut **0.35**, 0 – 0.9, pas 0.05

> Format personnalisé par cadre : texte libre avec [cur], [max], [perc], [missing], [status]. Exemple : [cur] / [max] ([perc]). Un format vide reprend le préréglage ci-dessus.

### Listes d'auras (partagées)

> Identifiants de sorts séparés par des virgules. Partagées par les cadres d'unité, les plaques et la barre co-tank. Liste blanche : toujours montrés. Liste noire : toujours cachés.

- **Liste blanche** — zone de texte
- **Liste noire** — zone de texte
- **Déverrouiller (déplacer les cadres)** — bouton

### Joueur

- **Afficher ce cadre** — case, défaut **cochée**
- **Copier les réglages depuis** — liste
- **Largeur** — curseur, défaut **220**, 60 – 400, pas 2
- **Hauteur** — curseur, défaut **42**, 12 – 80, pas 1
- **Nom** — case, défaut **cochée**
- **Niveau** — case, défaut **cochée**
- **Estomper hors combat quand rien ne se passe** — case, défaut **décochée**
- **Portrait** — case, défaut **décochée**
- **Barre de points de combo** — case, défaut **cochée**
- **Totems (barre déplaçable, clic droit : détruire)** — case, défaut **cochée**
  - **Taille des totems** — curseur, défaut **30**, 16 – 60, pas 2
- **Barre de puissance** — case, défaut **cochée**
  - **Hauteur de la barre de puissance** — curseur, défaut **6**, 0 – 16, pas 1
- **Barre d'incantation** — case, défaut **cochée**
  - **Hauteur de la barre d'incantation** — curseur, défaut **18**, 8 – 30, pas 1
  - **Barre d'incantation détachée (son propre mover)** — case, défaut **décochée**
    - **Largeur de la barre d'incantation détachée** — curseur, défaut **260**, 100 – 500, pas 2
- **Auras (buffs et débuffs)** — case, défaut **cochée**
  - **Auras au-dessus du cadre** — case, défaut **cochée**
  - **Taille des icônes d'auras** — curseur, défaut **22**, 12 – 40, pas 1
  - **Filtre des débuffs** — liste, défaut **Tous**
- **Format de vie (vide = préréglage)** — zone de texte
- **Format de puissance (vide = préréglage)** — zone de texte

### Cible

- **Afficher ce cadre** — case, défaut **cochée**
- **Copier les réglages depuis** — liste
- **Largeur** — curseur, défaut **220**, 60 – 400, pas 2
- **Hauteur** — curseur, défaut **42**, 12 – 80, pas 1
- **Nom** — case, défaut **cochée**
- **Niveau** — case, défaut **cochée**
- **Estomper hors combat quand rien ne se passe** — case, défaut **décochée**
- **Portrait** — case, défaut **décochée**
- **Barre de puissance** — case, défaut **cochée**
  - **Hauteur de la barre de puissance** — curseur, défaut **6**, 0 – 16, pas 1
- **Barre d'incantation** — case, défaut **cochée**
  - **Hauteur de la barre d'incantation** — curseur, défaut **18**, 8 – 30, pas 1
  - **Barre d'incantation détachée (son propre mover)** — case, défaut **décochée**
    - **Largeur de la barre d'incantation détachée** — curseur, défaut **260**, 100 – 500, pas 2
- **Auras (buffs et débuffs)** — case, défaut **cochée**
  - **Auras au-dessus du cadre** — case, défaut **décochée**
  - **Taille des icônes d'auras** — curseur, défaut **22**, 12 – 40, pas 1
  - **Filtre des débuffs** — liste, défaut **Tous**
- **Format de vie (vide = préréglage)** — zone de texte
- **Format de puissance (vide = préréglage)** — zone de texte

### Cible de la cible

- **Afficher ce cadre** — case, défaut **cochée**
- **Copier les réglages depuis** — liste
- **Largeur** — curseur, défaut **110**, 60 – 400, pas 2
- **Hauteur** — curseur, défaut **24**, 12 – 80, pas 1
- **Nom** — case, défaut **cochée**
- **Niveau** — case, défaut **décochée**
- **Estomper hors combat quand rien ne se passe** — case, défaut **décochée**
- **Portrait** — case, défaut **décochée**
- **Barre de puissance** — case, défaut **décochée**
  - **Hauteur de la barre de puissance** — curseur, défaut **0**, 0 – 16, pas 1
- **Barre d'incantation** — case, défaut **décochée**
  - **Hauteur de la barre d'incantation** — curseur, défaut **18**, 8 – 30, pas 1
  - **Barre d'incantation détachée (son propre mover)** — case, défaut **décochée**
    - **Largeur de la barre d'incantation détachée** — curseur, défaut **260**, 100 – 500, pas 2
- **Auras (buffs et débuffs)** — case, défaut **décochée**
  - **Auras au-dessus du cadre** — case, défaut **décochée**
  - **Taille des icônes d'auras** — curseur, défaut **22**, 12 – 40, pas 1
  - **Filtre des débuffs** — liste, défaut **Tous**
- **Format de vie (vide = préréglage)** — zone de texte

### Focus

- **Afficher ce cadre** — case, défaut **cochée**
- **Copier les réglages depuis** — liste
- **Largeur** — curseur, défaut **180**, 60 – 400, pas 2
- **Hauteur** — curseur, défaut **36**, 12 – 80, pas 1
- **Nom** — case, défaut **cochée**
- **Niveau** — case, défaut **cochée**
- **Estomper hors combat quand rien ne se passe** — case, défaut **décochée**
- **Portrait** — case, défaut **décochée**
- **Barre de puissance** — case, défaut **cochée**
  - **Hauteur de la barre de puissance** — curseur, défaut **6**, 0 – 16, pas 1
- **Barre d'incantation** — case, défaut **cochée**
  - **Hauteur de la barre d'incantation** — curseur, défaut **18**, 8 – 30, pas 1
  - **Barre d'incantation détachée (son propre mover)** — case, défaut **décochée**
    - **Largeur de la barre d'incantation détachée** — curseur, défaut **260**, 100 – 500, pas 2
- **Auras (buffs et débuffs)** — case, défaut **cochée**
  - **Auras au-dessus du cadre** — case, défaut **décochée**
  - **Taille des icônes d'auras** — curseur, défaut **22**, 12 – 40, pas 1
  - **Filtre des débuffs** — liste, défaut **Tous**
- **Format de vie (vide = préréglage)** — zone de texte
- **Format de puissance (vide = préréglage)** — zone de texte

### Cible du focus

- **Afficher ce cadre** — case, défaut **décochée**
- **Copier les réglages depuis** — liste
- **Largeur** — curseur, défaut **110**, 60 – 400, pas 2
- **Hauteur** — curseur, défaut **24**, 12 – 80, pas 1
- **Nom** — case, défaut **cochée**
- **Niveau** — case, défaut **décochée**
- **Estomper hors combat quand rien ne se passe** — case, défaut **décochée**
- **Portrait** — case, défaut **décochée**
- **Barre de puissance** — case, défaut **décochée**
  - **Hauteur de la barre de puissance** — curseur, défaut **0**, 0 – 16, pas 1
- **Barre d'incantation** — case, défaut **décochée**
  - **Hauteur de la barre d'incantation** — curseur, défaut **18**, 8 – 30, pas 1
  - **Barre d'incantation détachée (son propre mover)** — case, défaut **décochée**
    - **Largeur de la barre d'incantation détachée** — curseur, défaut **260**, 100 – 500, pas 2
- **Auras (buffs et débuffs)** — case, défaut **décochée**
  - **Auras au-dessus du cadre** — case, défaut **décochée**
  - **Taille des icônes d'auras** — curseur, défaut **22**, 12 – 40, pas 1
  - **Filtre des débuffs** — liste, défaut **Tous**
- **Format de vie (vide = préréglage)** — zone de texte

### Familier

- **Afficher ce cadre** — case, défaut **cochée**
- **Copier les réglages depuis** — liste
- **Largeur** — curseur, défaut **110**, 60 – 400, pas 2
- **Hauteur** — curseur, défaut **24**, 12 – 80, pas 1
- **Nom** — case, défaut **cochée**
- **Niveau** — case, défaut **décochée**
- **Estomper hors combat quand rien ne se passe** — case, défaut **décochée**
- **Portrait** — case, défaut **décochée**
- **Barre de puissance** — case, défaut **cochée**
  - **Hauteur de la barre de puissance** — curseur, défaut **4**, 0 – 16, pas 1
- **Barre d'incantation** — case, défaut **décochée**
  - **Hauteur de la barre d'incantation** — curseur, défaut **18**, 8 – 30, pas 1
  - **Barre d'incantation détachée (son propre mover)** — case, défaut **décochée**
    - **Largeur de la barre d'incantation détachée** — curseur, défaut **260**, 100 – 500, pas 2
- **Auras (buffs et débuffs)** — case, défaut **décochée**
  - **Auras au-dessus du cadre** — case, défaut **décochée**
  - **Taille des icônes d'auras** — curseur, défaut **22**, 12 – 40, pas 1
  - **Filtre des débuffs** — liste, défaut **Tous**
- **Format de vie (vide = préréglage)** — zone de texte
- **Format de puissance (vide = préréglage)** — zone de texte

### Boss (1 à 5)

- **Afficher ce cadre** — case, défaut **cochée**
- **Copier les réglages depuis** — liste
- **Largeur** — curseur, défaut **200**, 60 – 400, pas 2
- **Hauteur** — curseur, défaut **36**, 12 – 80, pas 1
- **Nom** — case, défaut **cochée**
- **Niveau** — case, défaut **cochée**
- **Estomper hors combat quand rien ne se passe** — case, défaut **décochée**
- **Portrait** — case, défaut **décochée**
- **Barre de puissance** — case, défaut **cochée**
  - **Hauteur de la barre de puissance** — curseur, défaut **6**, 0 – 16, pas 1
- **Barre d'incantation** — case, défaut **cochée**
  - **Hauteur de la barre d'incantation** — curseur, défaut **18**, 8 – 30, pas 1
  - **Barre d'incantation détachée (son propre mover)** — case, défaut **décochée**
    - **Largeur de la barre d'incantation détachée** — curseur, défaut **260**, 100 – 500, pas 2
- **Auras (buffs et débuffs)** — case, défaut **cochée**
  - **Auras au-dessus du cadre** — case, défaut **décochée**
  - **Taille des icônes d'auras** — curseur, défaut **20**, 12 – 40, pas 1
  - **Filtre des débuffs** — liste, défaut **Tous**
- **Format de vie (vide = préréglage)** — zone de texte
- **Format de puissance (vide = préréglage)** — zone de texte

## Cadres de groupe et de raid AeonUI

Remplace les cadres Blizzard de groupe et de raid par des grilles AeonUI : vie, puissance, nom, icônes de rôle et de chef, marqueur de raid, bordures d'agro et de débuff dissipable, atténuation hors de portée. Clic pour cibler, clic droit pour le menu.

- **Activer : Cadres de groupe et de raid AeonUI** — case, défaut **décochée**

> Les cadres Blizzard de groupe et de raid reviennent après un /reload une fois ce module coupé.

- **Largeur** — curseur, défaut **90**, 40 – 200, pas 2
- **Hauteur** — curseur, défaut **36**, 12 – 80, pas 1
- **Espacement entre les cadres** — curseur, défaut **4**, 0 – 20, pas 1
- **Barre de puissance** — case, défaut **cochée**
- **Hauteur de la barre de puissance** — curseur, défaut **4**, 0 – 12, pas 1
- **Texte de vie** — liste, défaut **Aucun**
- **Couleur de classe pour les joueurs (couleur de réaction sinon)** — case, défaut **cochée**
- **Couleur de vie du rouge au vert selon le pourcentage** — case, défaut **décochée**
- **Soins entrants et absorptions** — case, défaut **cochée**
- **Longueur du nom (0 = entier)** — curseur, défaut **8**, 0 – 20, pas 1
- **Masquer l'habillage Blizzard des plaques** — case, défaut **cochée**
- **Déverrouiller (déplacer les cadres)** — bouton

### Groupe

- **T'afficher dans le groupe** — case, défaut **cochée**
- **Afficher le cadre de groupe en solo (pour le régler)** — case, défaut **décochée**
- **Groupe en ligne plutôt qu'en colonne** — case, défaut **décochée**

### Raid

- **Unités par colonne** — curseur, défaut **5**, 1 – 10, pas 1
- **Colonnes** — curseur, défaut **8**, 1 – 8, pas 1
- **Trier par** — liste, défaut **Groupe**
- **Cadres de raid au-delà de** — liste, défaut **5**  
  _Nombre de membres : jusqu'à ce seuil, un raid garde la disposition du groupe (colonne ou ligne par groupe de 5) ; au-delà, la grille de raid prend le relais. 5 = dès qu'on est en raid._
- **Cadres des tanks principaux (raid)** — case, défaut **décochée**
- **Cadres des assistants principaux (raid)** — case, défaut **décochée**

### Indicateurs

- **Icônes de rôle et de chef** — case, défaut **cochée**
- **Bordure à la couleur d'un débuff que tu peux dissiper** — case, défaut **cochée**
- **Afficher la menace (orange : instable, rouge : agro)** — case, défaut **cochée**
- **Affichage de la menace** — liste, défaut **Bordure**
- **Icônes d'appel, d'invocation et de résurrection** — case, défaut **cochée**
- **Atténuer les unités hors de portée** — case, défaut **cochée**
- **Opacité hors de portée** — curseur, défaut **0.4**, 0.1 – 0.9, pas 0.1

## Chat AeonUI

Fenêtres de chat au thème (fond, police, onglets plats, boutons latéraux cachés, sans fondu), URL cliquables, bouton de copie du chat, noms de canaux courts, couleur de classe partout, horodatage, zone de saisie en haut ou en bas.

- **Activer : Chat AeonUI** — case, défaut **décochée**

> Position et taille de la fenêtre de chat : Edit Mode de Blizzard (Échap > Mode édition).

- **Fond et police au thème** — case, défaut **cochée**
- **Couleur et opacité du fond des fenêtres** — couleur, défaut **#0C0F14**
- **Taille de police** — curseur, défaut **12**, 9 – 20, pas 1
- **Onglets plats** — case, défaut **cochée**
- **Cacher les boutons latéraux (menu, canaux, voix, défilement)** — case, défaut **cochée**
- **Ne jamais estomper les lignes** — case, défaut **cochée**
- **Lignes gardées en historique** — curseur, défaut **1000**, 128 – 4096, pas 128
- **Zone de saisie au-dessus de la fenêtre** — case, défaut **décochée**
- **URL cliquables (clic pour copier)** — case, défaut **cochée**
- **Bouton de copie au survol ([c], en haut à droite)** — case, défaut **cochée**
- **Noms de canaux courts ([2] au lieu de [2. Commerce])** — case, défaut **cochée**
- **Couleur de classe sur tous les canaux** — case, défaut **cochée**
- **Horodatage** — liste, défaut **Aucun**

### Historique

- **Conserver l'historique du chat au /reload et à la connexion** — case, défaut **cochée**
- **Lignes conservées par fenêtre** — curseur, défaut **100**, 20 – 500, pas 10
- **Effacer l'historique** — bouton

### Mots-clés

- **Mots-clés (séparés par des virgules), surlignés dans les messages** — zone de texte
- **Le nom du personnage compte comme mot-clé** — case, défaut **cochée**
- **Son sur mot-clé (au plus toutes les 5 s)** — case, défaut **cochée**
- **Son importé (vide = son par défaut)** — zone de texte

> Fichier .ogg ou .mp3, chemin depuis le dossier du jeu, ex. Interface\AddOns\MesSons\alerte.ogg. Relancer le jeu après avoir ajouté le fichier.

- **Écouter** — bouton

### Anti-spam

- **Masquer les messages répétés (dire, crier, canaux), même avec casse ou ponctuation changée** — case, défaut **décochée**
- **Fenêtre de répétition (secondes)** — curseur, défaut **60**, 10 – 600, pas 10

## Confort automatique

Les petites corvées faites pour toi : réparation et vente des objets gris chez le marchand, maintien de ALT pour libérer l'esprit, invitations des amis et de la guilde acceptées, suppression d'objet pré-remplie.

- **Activer : Confort automatique** — case, défaut **cochée**

### Chez le marchand

- **Réparer automatiquement chez le marchand** — case, défaut **cochée**
- **Utiliser d'abord la banque de guilde si autorisé** — case, défaut **cochée**
- **Vendre automatiquement les objets gris** — case, défaut **cochée**

### Butin et quêtes

- **Butin rapide : tout ramasser d'un coup (Maj pour ramasser à la main)** — case, défaut **cochée**
- **Accepter et rendre les quêtes automatiquement (Maj pour suspendre ; tu choisis toujours toi-même la récompense)** — case, défaut **décochée**

### À la mort

- **Maintenir ALT pour libérer l'esprit (évite les clics accidentels)** — case, défaut **cochée**
- **Seulement en donjon et en raid** — case, défaut **cochée**
- **Durée de maintien** — curseur, défaut **1.0 s**, 0.5 – 3, pas 0.5

### Divers

- **Accepter les invitations de groupe des amis, de Battle.net et de la guilde** — case, défaut **décochée**
- **Pré-remplir le mot de confirmation à la suppression d'un objet** — case, défaut **cochée**
- **Passer les cinématiques et vidéos** — case, défaut **décochée**
- **Prévenir le groupe quand tu réinitialises les instances** — case, défaut **décochée**

## Curseur et réticule

Un anneau autour du curseur pour le retrouver tout de suite, et un réticule au centre de l'écran.

- **Activer : Curseur et réticule** — case, défaut **décochée**

### Anneau du curseur

- **Afficher un anneau autour du curseur** — case, défaut **cochée**
- **Seulement en combat** — case, défaut **cochée**
- **Taille** — curseur, défaut **48**, 24 – 128, pas 4
- **Couleur** — couleur, défaut **#3FA8F4**

### Réticule

- **Afficher un réticule au centre de l'écran** — case, défaut **décochée**
- **Seulement en combat** — case, défaut **cochée**
- **Taille** — curseur, défaut **20**, 8 – 64, pas 2
- **Épaisseur** — curseur, défaut **2**, 1 – 6, pas 1
- **Couleur** — couleur, défaut **#FFFFFF**

## Écran d'absence

Quand tu passes absent hors combat, l'interface s'efface, la caméra tourne lentement et un bandeau montre ton personnage et la durée de l'absence.

- **Activer : Écran d'absence** — case, défaut **décochée**
- **Faire tourner la caméra** — case, défaut **cochée**
- **Vitesse de rotation** — curseur, défaut **0.035**, 0.01 – 0.1, pas 0.005

## Fiche de personnage

Niveau d'objet sur chaque emplacement de la fiche, à la couleur de qualité, le niveau moyen, et un repère sur les pièces enchantables sans enchantement. Mêmes niveaux sur la fenêtre d'inspection, et niveau moyen des joueurs dans leur infobulle.

- **Activer : Fiche de personnage** — case, défaut **cochée**
- **Niveau d'objet sur chaque emplacement** — case, défaut **cochée**
- **Niveau d'objet moyen** — case, défaut **cochée**
- **« ! » rouge sur les pièces enchantables sans enchantement** — case, défaut **décochée**
- **Taille du texte** — curseur, défaut **11**, 6 – 20, pas 1
- **Niveaux d'objet sur la fenêtre d'inspection** — case, défaut **cochée**
- **Niveau d'objet moyen des joueurs dans leur infobulle (inspection hors combat)** — case, défaut **cochée**

## Gestionnaire de recharges

Réglages sort par sort du gestionnaire de recharges Blizzard : afficher ou masquer chaque sort sur sa barre, lueur quand il est prêt ou en permanence.

- **Activer : Gestionnaire de recharges** — case, défaut **décochée**

> Choisis une barre, clique sur un sort, puis règle-le. Un sort masqué libère sa place : les suivants remontent. La liste suit la spécialisation en cours ; les réglages valent pour toutes.

- **Couleur de la lueur** — couleur, défaut **#FFD133**

## Habillage

Infobulles sombres avec nom et bordure à la couleur de classe, et deux flèches autour de la barre de nom de ta cible.

- **Activer : Habillage** — case, défaut **cochée**

### Infobulles

- **Infobulles sombres** — case, défaut **cochée**
- **Noms des joueurs à la couleur de classe dans les infobulles** — case, défaut **cochée**
- **Masquer les infobulles d'unité en combat** — case, défaut **décochée**
- **Masquer toutes les infobulles en combat** — case, défaut **décochée**
- **Infobulles par défaut collées au curseur** — case, défaut **décochée**
- **Afficher la cible de l'unité** — case, défaut **cochée**
- **Afficher le rang de guilde** — case, défaut **cochée**
- **Afficher l'ID des sorts, objets et auras** — case, défaut **décochée**
- **Masquer la barre de vie sous les infobulles d'unité** — case, défaut **décochée**

### Icônes

- **Rogner le liseré des icônes de buffs et de temps de recharge** — case, défaut **cochée**
- **Rognage** — curseur, défaut **8 %**, 0 – 20, pas 1

### Panneaux

- **Panneaux Blizzard sombres (personnage, grimoire, marchand, quêtes, carte…)** — case, défaut **décochée**
- **Fiche de personnage et fenêtre d'amis au thème (fond plat, bordures de qualité sur l'équipement)** — case, défaut **décochée**

## Interface épurée

Moins d'encombrement et un accès direct à des réglages Blizzard. Tout réglage Blizzard changé ici est rendu quand tu coupes l'option.

- **Activer : Interface épurée** — case, défaut **cochée**

### Encombrement

- **Masquer les messages d'erreur rouges (« Pas assez de mana »…)** — case, défaut **décochée**
- **Masquer la tête parlante** — case, défaut **cochée**
- **Désactiver les tutoriels** — case, défaut **cochée**
- **Masquer le message « Capture d'écran enregistrée »** — case, défaut **cochée**
- **Masquer les fenêtres d'erreur Lua** — case, défaut **décochée**

### Alertes de sort (procs)

- **Opacité personnalisée des alertes de sort** — case, défaut **décochée**
- **Opacité** — curseur, défaut **0.65**, 0 – 1, pas 0.05
- **Masquer les alertes de sort sur les personnages MAGE** — case

### Barres d'action

- **Toujours afficher les barres d'action, même les cases vides (mode débutant)** — case, défaut **décochée**
- **Chiffres de recharge sur tous les boutons et icônes** — case, défaut **décochée**
- **Texte de recharge coloré sur les boutons et icônes AeonUI** — case, défaut **décochée**
- **Presque fini sous (secondes, avec une décimale)** — curseur, défaut **3**, 0 – 10, pas 1
- **Couleur « presque fini »** — couleur, défaut **#FF3333**
- **Couleur des secondes** — couleur, défaut **#FFE54C**
- **Couleur des minutes et heures** — couleur, défaut **#FFFFFF**

## Menu radial

Maintenir une touche : un anneau de sorts, objets, macros et montures s'ouvre autour du curseur ; relâcher sur l'un le lance. Hors combat seulement.

- **Activer : Menu radial** — case, défaut **décochée**

> Hors combat seulement : ce client ne peut pas exécuter le code sécurisé qu'un menu radial demande en combat. En combat, la touche ne fait rien.

- **Touche (ex. SHIFT-Q)** — zone de texte
- **Disposition** — liste, défaut **Anneau**
- **Rayon de l'anneau** — curseur, défaut **90**, 50 – 200, pas 5
- **Taille des icônes** — curseur, défaut **36**, 20 – 64, pas 2

### Entrées

> Une par ligne : spell:ID, item:ID, macro:Nom, mount:ID (16 au plus). Ou prenez un sort, objet, macro ou monture sur le curseur et cliquez le bouton ci-dessous.

- **Entrées** — zone de texte
- **Ajouter ce qui est sur le curseur** — bouton

## Minimap AeonUI

Minimap carrée (ou ronde) à la taille voulue, bordure au thème, nom de zone et coordonnées, zoom à la molette, boutons d'addons regroupés en rangée sous la carte. Déplaçable avec /aeon unlock.

- **Activer : Minimap AeonUI** — case, défaut **décochée**

> Le décor Blizzard de la minimap revient après un /reload une fois ce module coupé.

- **Taille** — curseur, défaut **180**, 100 – 400, pas 2
- **Carte carrée** — case, défaut **cochée**
- **Cacher le décor Blizzard (bordure, boussole, horloge, boutons de zoom)** — case, défaut **cochée**
- **Nom de zone au-dessus de la carte** — case, défaut **cochée**
- **Coordonnées sous la carte** — case, défaut **décochée**
- **La molette zoome** — case, défaut **cochée**
- **Boutons d'addons** — liste, défaut **Rangée sous la carte, au survol**
  (choix : rangée au survol, rangée toujours, un bouton sous la carte qui ouvre la grille des addons, les laisser sur la carte)
- **Taille des boutons d'addons** — curseur, défaut **24**, 16 – 40, pas 1
- **Déverrouiller (déplacer les cadres)** — bouton

## Minuteur d'attaque

Une barre par arme jusqu'à votre prochaine attaque automatique. Demande l'événement PLAYER_SWING du client.

- **Activer : Minuteur d'attaque** — case, défaut **décochée**

> Ce client ne signale pas les coups d'arme (pas de C_SwingTimer) : le module reste inactif.

- **Main droite** — case, défaut **cochée**
- **Main gauche** — case, défaut **cochée**
- **Distance** — case, défaut **cochée**
- **En combat seulement** — case, défaut **cochée**
- **Orientation** — liste, défaut **Horizontale**
- **Longueur** — curseur, défaut **200**, 60 – 400, pas 2
- **Épaisseur** — curseur, défaut **10**, 4 – 30, pas 1
- **Couleur de la barre** — couleur, défaut **#D8D8D8**
- **Couleur quand une attaque au prochain coup est en file** — couleur, défaut **#FF8C19**

## Panneaux de données

Bandeaux d'informations libres sur les movers : coordonnées, quêtes, régénération, vitesse, DPS et les textes de la barre du haut.

- **Activer : Panneaux de données** — case, défaut **décochée**

> Chaque panneau est découpé en emplacements égaux. Choisis un texte par emplacement ; déplace les panneaux en mode déverrouillé.

- **Déverrouiller / verrouiller les cadres mobiles** — bouton

### Panneau 1

- **Afficher ce panneau** — case, défaut **cochée**
- **Largeur** — curseur, défaut **360**, 60 – 1200, pas 10
- **Hauteur** — curseur, défaut **22**, 14 – 40, pas 1
- **Emplacements** — curseur, défaut **4**, 1 – 6, pas 1
- **Opacité du fond** — curseur, défaut **0.75**, 0 – 1, pas 0.05
- **Masquer en combat** — case, défaut **décochée**
- **Emplacement 1** — liste, défaut **Coordonnées**
- **Emplacement 2** — liste, défaut **Vitesse de déplacement**
- **Emplacement 3** — liste, défaut **Régénération de mana (par 5 s)**
- **Emplacement 4** — liste, défaut **Quêtes**
- **Emplacement 5** — liste, défaut **Aucun**
- **Emplacement 6** — liste, défaut **Aucun**

### Panneau 2

- **Afficher ce panneau** — case, défaut **décochée**
- **Largeur** — curseur, défaut **360**, 60 – 1200, pas 10
- **Hauteur** — curseur, défaut **22**, 14 – 40, pas 1
- **Emplacements** — curseur, défaut **3**, 1 – 6, pas 1
- **Opacité du fond** — curseur, défaut **0.75**, 0 – 1, pas 0.05
- **Masquer en combat** — case, défaut **décochée**
- **Emplacement 1** — liste, défaut **Or**
- **Emplacement 2** — liste, défaut **Durabilité**
- **Emplacement 3** — liste, défaut **Sacs**
- **Emplacement 4** — liste, défaut **Aucun**
- **Emplacement 5** — liste, défaut **Aucun**
- **Emplacement 6** — liste, défaut **Aucun**

### Panneau 3

- **Afficher ce panneau** — case, défaut **décochée**
- **Largeur** — curseur, défaut **360**, 60 – 1200, pas 10
- **Hauteur** — curseur, défaut **22**, 14 – 40, pas 1
- **Emplacements** — curseur, défaut **2**, 1 – 6, pas 1
- **Opacité du fond** — curseur, défaut **0.75**, 0 – 1, pas 0.05
- **Masquer en combat** — case, défaut **décochée**
- **Emplacement 1** — liste, défaut **DPS (compteur de dégâts natif)**
- **Emplacement 2** — liste, défaut **FPS et latence**
- **Emplacement 3** — liste, défaut **Aucun**
- **Emplacement 4** — liste, défaut **Aucun**
- **Emplacement 5** — liste, défaut **Aucun**
- **Emplacement 6** — liste, défaut **Aucun**

## Plaques de nom AeonUI

Remplace l'habillage Blizzard des plaques de nom par des barres AeonUI : vie (couleurs de réaction, de classe, de menace), nom, niveau, barre d'incantation avec icône, marqueur de raid, débuffs, surbrillance de la cible. Compatible avec le module des chevrons de cible.

- **Activer : Plaques de nom AeonUI** — case, défaut **décochée**

> Les plaques Blizzard reviennent après un /reload une fois ce module coupé.

- **Largeur** — curseur, défaut **120**, 60 – 250, pas 2
- **Hauteur** — curseur, défaut **10**, 4 – 30, pas 1
- **Nom** — case, défaut **cochée**
- **Niveau** — case, défaut **cochée**
- **Taille des textes (écart avec le thème)** — curseur, défaut **-1**, -4 – 4, pas 1
- **Texte de vie** — liste, défaut **Aucun**
- **Format de vie (vide = préréglage)** — zone de texte
- **Barre d'incantation** — case, défaut **cochée**
- **Hauteur de la barre d'incantation** — curseur, défaut **10**, 6 – 24, pas 1
- **Débuffs au-dessus de la plaque** — case, défaut **cochée**
- **Buffs aussi (ligne au-dessus des débuffs)** — case, défaut **cochée**
- **Taille des icônes d'auras** — curseur, défaut **18**, 12 – 32, pas 1
- **Filtre des débuffs** — liste, défaut **Les miens**
- **Barre de vie sur les plaques alliées (nom seul sinon)** — case, défaut **décochée**
- **Surbrillance de la cible (bordure d'accent, les autres atténuées)** — case, défaut **cochée**
- **Couleur de menace en combat (rouge = agro sur toi)** — case, défaut **cochée**
- **Couleur de classe pour les joueurs (couleur de réaction sinon)** — case, défaut **cochée**
- **Masquer l'habillage Blizzard des plaques** — case, défaut **cochée**

### Filtres de style

> Règles lues dans l'ordre : la première règle active dont toutes les conditions sont vraies habille la plaque. Une condition que le client garde secrète (en combat) fait échouer la règle.

### Règle 1

- **Active** — case, défaut **décochée**
- **Est ma cible** — liste, défaut **Peu importe**
- **Incante** — liste, défaut **Peu importe**
- **Est en combat** — liste, défaut **Peu importe**
- **Réaction** — liste, défaut **Peu importe**
- **Classification** — liste, défaut **Peu importe**
- **Liée à une quête en cours** — case, défaut **décochée**
- **Vie sous (%, 0 = ignoré)** — curseur, défaut **0**, 0 – 100, pas 5
- **Noms (séparés par des virgules, vide = tous)** — zone de texte
- **Colorer la barre de vie** — case, défaut **décochée**
  - **Couleur (barre et lueur)** — couleur, défaut **#FF7F00**
- **Lueur** — case, défaut **décochée**
- **Taille** — curseur, défaut **1.00**, 0.5 – 2, pas 0.05
- **Opacité** — curseur, défaut **1.00**, 0 – 1, pas 0.05
- **Masquer** — case, défaut **décochée**

### Règle 2

- **Active** — case, défaut **décochée**
- **Est ma cible** — liste, défaut **Peu importe**
- **Incante** — liste, défaut **Peu importe**
- **Est en combat** — liste, défaut **Peu importe**
- **Réaction** — liste, défaut **Peu importe**
- **Classification** — liste, défaut **Peu importe**
- **Liée à une quête en cours** — case, défaut **décochée**
- **Vie sous (%, 0 = ignoré)** — curseur, défaut **0**, 0 – 100, pas 5
- **Noms (séparés par des virgules, vide = tous)** — zone de texte
- **Colorer la barre de vie** — case, défaut **décochée**
  - **Couleur (barre et lueur)** — couleur, défaut **#FF7F00**
- **Lueur** — case, défaut **décochée**
- **Taille** — curseur, défaut **1.00**, 0.5 – 2, pas 0.05
- **Opacité** — curseur, défaut **1.00**, 0 – 1, pas 0.05
- **Masquer** — case, défaut **décochée**

### Règle 3

- **Active** — case, défaut **décochée**
- **Est ma cible** — liste, défaut **Peu importe**
- **Incante** — liste, défaut **Peu importe**
- **Est en combat** — liste, défaut **Peu importe**
- **Réaction** — liste, défaut **Peu importe**
- **Classification** — liste, défaut **Peu importe**
- **Liée à une quête en cours** — case, défaut **décochée**
- **Vie sous (%, 0 = ignoré)** — curseur, défaut **0**, 0 – 100, pas 5
- **Noms (séparés par des virgules, vide = tous)** — zone de texte
- **Colorer la barre de vie** — case, défaut **décochée**
  - **Couleur (barre et lueur)** — couleur, défaut **#FF7F00**
- **Lueur** — case, défaut **décochée**
- **Taille** — curseur, défaut **1.00**, 0.5 – 2, pas 0.05
- **Opacité** — curseur, défaut **1.00**, 0 – 1, pas 0.05
- **Masquer** — case, défaut **décochée**

### Règle 4

- **Active** — case, défaut **décochée**
- **Est ma cible** — liste, défaut **Peu importe**
- **Incante** — liste, défaut **Peu importe**
- **Est en combat** — liste, défaut **Peu importe**
- **Réaction** — liste, défaut **Peu importe**
- **Classification** — liste, défaut **Peu importe**
- **Liée à une quête en cours** — case, défaut **décochée**
- **Vie sous (%, 0 = ignoré)** — curseur, défaut **0**, 0 – 100, pas 5
- **Noms (séparés par des virgules, vide = tous)** — zone de texte
- **Colorer la barre de vie** — case, défaut **décochée**
  - **Couleur (barre et lueur)** — couleur, défaut **#FF7F00**
- **Lueur** — case, défaut **décochée**
- **Taille** — curseur, défaut **1.00**, 0.5 – 2, pas 0.05
- **Opacité** — curseur, défaut **1.00**, 0 – 1, pas 0.05
- **Masquer** — case, défaut **décochée**

### Règle 5

- **Active** — case, défaut **décochée**
- **Est ma cible** — liste, défaut **Peu importe**
- **Incante** — liste, défaut **Peu importe**
- **Est en combat** — liste, défaut **Peu importe**
- **Réaction** — liste, défaut **Peu importe**
- **Classification** — liste, défaut **Peu importe**
- **Liée à une quête en cours** — case, défaut **décochée**
- **Vie sous (%, 0 = ignoré)** — curseur, défaut **0**, 0 – 100, pas 5
- **Noms (séparés par des virgules, vide = tous)** — zone de texte
- **Colorer la barre de vie** — case, défaut **décochée**
  - **Couleur (barre et lueur)** — couleur, défaut **#FF7F00**
- **Lueur** — case, défaut **décochée**
- **Taille** — curseur, défaut **1.00**, 0.5 – 2, pas 0.05
- **Opacité** — curseur, défaut **1.00**, 0 – 1, pas 0.05
- **Masquer** — case, défaut **décochée**

## Rappels

Hors combat uniquement : te prévient quand un buff de classe manque (seulement pour les sorts que tu connais), quand la durabilité est basse, quand tes sacs sont pleins, ou quand tu as oublié de te camoufler.

- **Activer : Rappels** — case, défaut **cochée**

### Buffs, formes et familiers

- **Buff de classe manquant (armure, aura, poison, aspect…)** — case, défaut **cochée**
- **Pas en ville ni à l'auberge** — case, défaut **cochée**
- **Prêtre : rappeler la Forme d'Ombre** — case, défaut **décochée**
- **Paladin : rappeler la Fureur vertueuse (tank)** — case, défaut **décochée**
- **Chasseur / démoniste : familier non invoqué** — case, défaut **cochée**
- **Pas « Bien nourri » en donjon et en raid** — case, défaut **décochée**
- **Camouflage oublié (voleur, druide félin ; donjons et raids)** — case, défaut **décochée**
- **Partout, pas seulement en donjon et raid** — case, défaut **décochée**
- **Texte personnalisé (vide = défaut)** — zone de texte
- **Couleur du texte** — couleur, défaut **#FF8C26**

### Équipement et sacs

- **Durabilité basse** — case, défaut **cochée**
- **Seuil** — curseur, défaut **20 %**, 5 – 50, pas 5
- **Sacs pleins** — case, défaut **cochée**

### Son et position

- **Jouer un son quand un rappel apparaît** — case, défaut **cochée**
- **Son** — liste, défaut **Clic**
- **Son importé (vide = son par défaut)** — zone de texte

> Fichier .ogg ou .mp3, chemin depuis le dossier du jeu, ex. Interface\AddOns\MesSons\alerte.ogg. Relancer le jeu après avoir ajouté le fichier.

- **Écouter** — bouton
- **Répéter le son tant que le rappel camouflage ou posture reste (0 = une fois)** — curseur, défaut **0 s**, 0 – 30, pas 1
- **Déverrouiller / verrouiller les cadres mobiles** — bouton

## Recharges de raid

Charges de rez en combat du groupe et verrou de Furie sanguinaire / Héroïsme sur vous.

- **Activer : Recharges de raid** — case, défaut **décochée**

> Affiché seulement si le client fournit les données : charges de rez partagées en instance de groupe, affaiblissement sur vous.

- **Charges de rez en combat** — case, défaut **cochée**
- **Verrou Furie sanguinaire / Héroïsme** — case, défaut **cochée**
- **Taille des icônes** — curseur, défaut **36**, 20 – 64, pas 2

## Recherche de groupe

Raccourcis de l'outil de recherche de groupe : inscription en un clic quand ton rôle est évident, et note de candidature mémorisée.

- **Activer : Recherche de groupe** — case, défaut **décochée**
- **S'inscrire automatiquement quand un seul rôle est coché** — case, défaut **cochée**  
  _Maj enfoncée à l'ouverture du dialogue pour s'inscrire à la main._
- **Mémoriser ma note de candidature** — case, défaut **décochée**
- **Note** — zone de texte

## Sacs

Une seule fenêtre pour le sac à dos et les sacs équipés, sur son mover : recherche, tri, niveau d'objet sur l'équipement, objets gris signalés, bordure de qualité, recharges, emplacements libres et or. La banque reste celle de Blizzard.

- **Activer : Sacs** — case, défaut **décochée**
- **Colonnes** — curseur, défaut **12**, 4 – 24, pas 1
- **Taille des boutons** — curseur, défaut **34**, 24 – 48, pas 1
- **Niveau d'objet sur l'équipement** — case, défaut **cochée**
- **Pièce sur les objets gris (camelote)** — case, défaut **cochée**
- **Déverrouiller / verrouiller les cadres mobiles** — bouton

## Suivi de quêtes AeonUI

Le suivi d'objectifs Blizzard sur un support déplaçable, à la hauteur voulue, en-têtes au thème, replié de lui-même en combat ou en instance.

- **Activer : Suivi de quêtes AeonUI** — case, défaut **décochée**

> Le suivi Blizzard reprend sa place après un /reload une fois ce module coupé.

- **Hauteur** — curseur, défaut **500**, 200 – 1000, pas 10
- **En-têtes au thème (sans fond, police du thème)** — case, défaut **cochée**
- **Taille de police des en-têtes** — curseur, défaut **14**, 10 – 20, pas 1
- **Replier en combat** — case, défaut **décochée**
- **Replier en instance** — case, défaut **décochée**
- **Déverrouiller (déplacer les cadres)** — bouton

## Suivi par ID

Une rangée d'icônes pour les sorts et auras choisis par leur identifiant : aura présente sur toi ou posée par toi sur la cible (durée, stacks), sinon recharge du sort.

- **Activer : Suivi par ID** — case, défaut **décochée**

> Identifiants séparés par des virgules, dans l'ordre d'affichage (ID visible dans l'infobulle, option de l'Habillage). En combat, le jeu cache souvent les auras : elles peuvent alors apparaître absentes.

- **Sorts et auras suivis (ID)** — zone de texte
- **Taille des icônes** — curseur, défaut **36**, 16 – 64, pas 2
- **Espacement** — curseur, défaut **4**, 0 – 20, pas 1
- **Opacité d'une aura absente** — curseur, défaut **0.35**, 0 – 1, pas 0.05
- **Déverrouiller / verrouiller les cadres mobiles** — bouton

## Utilitaire de raid

Bouton « Raid » sur son mover, visible en groupe : appel prêt, vérification des rôles, compte à rebours, marqueurs de cible et marqueurs au sol.

- **Activer : Utilitaire de raid** — case, défaut **décochée**
- **Compte à rebours (secondes)** — curseur, défaut **10**, 3 – 30, pas 1
- **Déverrouiller / verrouiller les cadres mobiles** — bouton

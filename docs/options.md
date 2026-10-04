# AeonUI — Référence des réglages

Généré par `tools/generate_options_doc.lua` depuis la fenêtre d'options (`/aeon`). Valeurs par défaut d'un profil neuf.

## Pages

- [Général](#général)
- [Polices et textures](#polices-et-textures)
- [Modules](#modules)
- [Profils](#profils)
- [Maintenance](#maintenance)
- [Alertes](#alertes)
- [Alertes de mouvement](#alertes-de-mouvement)
- [Autre tank](#autre-tank)
- [Banque](#banque)
- [Barre de recharge globale](#barre-de-recharge-globale)
- [Barre du haut](#barre-du-haut)
- [Barres d'action AeonUI](#barres-daction-aeonui)
- [Barres d'auras](#barres-dauras)
- [Barres de données AeonUI](#barres-de-données-aeonui)
- [Barres de nom](#barres-de-nom)
- [Barres de recharges personnalisées](#barres-de-recharges-personnalisées)
- [Barres de ressources](#barres-de-ressources)
- [Bulles de dialogue](#bulles-de-dialogue)
- [Butin](#butin)
- [Cadres Blizzard déplaçables](#cadres-blizzard-déplaçables)
- [Cadres d'unité](#cadres-dunité)
- [Cadres d'unité AeonUI](#cadres-dunité-aeonui)
- [Cadres de groupe et de raid AeonUI](#cadres-de-groupe-et-de-raid-aeonui)
- [Chat AeonUI](#chat-aeonui)
- [Clic-sort](#clic-sort)
- [Confort automatique](#confort-automatique)
- [Curseur et réticule](#curseur-et-réticule)
- [Écran d'absence](#écran-dabsence)
- [Fenêtres déplaçables](#fenêtres-déplaçables)
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

- **Préréglage d'accent** — liste, défaut **Personnalisé**
- **Couleur d'accent** — couleur, défaut **#3FA8F4**
- **Couleur de fond** — couleur, défaut **#0C0F14**
- **Couleur de bordure** — couleur, défaut **#000000**
- **Épaisseur des bordures (pixels)** — curseur, défaut **1**, 1 – 4, pas 1
- **Échelle pixel perfect** — case, défaut **cochée**  
  _Met toute l'interface à l'échelle pour qu'une unité vaille un pixel d'écran : bordures nettes à 1 px. Décocher rend l'échelle précédente._
- **Échelle de l'interface** — curseur, défaut **1.00**, 0.5 – 1.5, pas 0.05  
  _Multiplie l'échelle (pixel perfect ou celle du jeu) : 1,00 = inchangée, 1,20 = plus grand. Hors combat._
- **Taille de la fenêtre d'options** — curseur, défaut **1.00**, 0.8 – 1.5, pas 0.05

### Cadres mobiles

- **Grille d'alignement en mode déverrouillé** — liste, défaut **Aucune**
- **Déverrouiller / verrouiller les cadres mobiles** — bouton
- **Réinitialiser toutes les positions** — bouton

## Polices et textures

Police et texture de barre pour tout AeonUI, puis par module quand l'un doit se distinguer.

- **Police de AeonUI** — liste, défaut **Arial Narrow**
- **Taille du texte** — curseur, défaut **12**, 9 – 18, pas 1
- **Contour du texte** — liste, défaut **Aucun**
- **Texture des barres** — liste, défaut **Plate**
- **Mode sombre des barres de vie** — case, défaut **décochée**  
  _Cadres d'unité, groupe, plaques et barres de ressources : remplissage sombre, la couleur de l'unité montre la vie manquante._

### Par module

- **Cadres d'unité AeonUI : Police de AeonUI** — liste, défaut **Comme le thème**
- **Cadres d'unité AeonUI : Texture des barres** — liste, défaut **Comme le thème**
- **Cadres de groupe et de raid AeonUI : Police de AeonUI** — liste, défaut **Comme le thème**
- **Cadres de groupe et de raid AeonUI : Texture des barres** — liste, défaut **Comme le thème**
- **Plaques de nom AeonUI : Police de AeonUI** — liste, défaut **Comme le thème**
- **Plaques de nom AeonUI : Texture des barres** — liste, défaut **Comme le thème**
- **Barres de ressources : Police de AeonUI** — liste, défaut **Comme le thème**
- **Barres de ressources : Texture des barres** — liste, défaut **Comme le thème**
- **Minuteur d'attaque : Police de AeonUI** — liste, défaut **Comme le thème**
- **Minuteur d'attaque : Texture des barres** — liste, défaut **Comme le thème**
- **Barres de données AeonUI : Police de AeonUI** — liste, défaut **Comme le thème**
- **Barres de données AeonUI : Texture des barres** — liste, défaut **Comme le thème**

## Modules

Active ou coupe chaque module ici. Chacun a sa propre page dans la liste de gauche. Survole un module pour lire ce qu'il fait.

- **Alertes** — case, défaut **cochée**  
  _Grands messages à l'écran : entrée et sortie de combat, mort d'un membre du groupe, et chronomètre de combat._
- **Alertes de mouvement** — case, défaut **décochée**  
  _Les sorts de déplacement de ta classe affichés pendant leur recharge, avec une annonce à leur retour._
- **Autre tank** — case, défaut **décochée**  
  _Quand tu tankes en raid, une barre de vie pour l'autre tank. Clique dessus pour le cibler. Tank = rôle de groupe, assignation « tank principal », ou forcé ci-dessous._
- **Banque** — case, défaut **décochée**  
  _Fenêtre de banque au thème, un onglet par coffre, cases habillées comme les sacs._
- **Barre de recharge globale** — case, défaut **décochée**  
  _Une barre fine qui se remplit pendant votre recharge globale, cachée le reste du temps._
- **Barre du haut** — case, défaut **cochée**  
  _Une fine barre en haut de l'écran : amis et guilde en ligne, heure, or, durabilité, places libres dans les sacs, FPS et latence, et un bouton pierre de foyer._
- **Barres d'action AeonUI** — case, défaut **décochée**  
  _Six barres d'action déplaçables faites de boutons Blizzard (icônes, recharges, compteurs, raccourcis, glisser-déposer gérés par le code Blizzard) : boutons par barre, par ligne, taille, espacement, opacité. La barre 1 change de page avec les postures et la furtivité. Remplace les barres Blizzard._
- **Barres d'auras** — case, défaut **décochée**  
  _Tes buffs et débuffs en barres horizontales avec le temps restant, les plus courts d'abord._
- **Barres de données AeonUI** — case, défaut **décochée**  
  _Barre d'expérience (avec le bonus de repos, cachée au niveau maximum) et barre de la réputation suivie, déplaçables, avec texte et infobulle. Remplacent les barres Blizzard._
- **Barres de nom** — case, défaut **cochée**  
  _Deux chevrons autour de la barre de nom de ta cible, pour ne jamais la perdre dans un pack. Celui de gauche s'écarte quand la cible incante._
- **Barres de recharges personnalisées** — case, défaut **décochée**  
  _Jusqu'à trois rangées d'icônes de sorts au choix, avec recharge et charges._
- **Barres de ressources** — case, défaut **décochée**  
  _Votre vie, puissance, points de combo et mana de druide en barres séparées, placées et ancrées où vous voulez._
- **Bulles de dialogue** — case, défaut **décochée**  
  _Bulles au thème, bordure à la couleur du canal, canaux affichés un par un._
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
- **Clic-sort** — case, défaut **décochée**  
  _Lance un sort sur un membre du groupe ou du raid d'un clic de souris et d'un modificateur._
- **Confort automatique** — case, défaut **cochée**  
  _Les petites corvées faites pour toi : réparation et vente des objets gris chez le marchand, maintien de ALT pour libérer l'esprit, invitations des amis et de la guilde acceptées, suppression d'objet pré-remplie._
- **Curseur et réticule** — case, défaut **décochée**  
  _Un anneau autour du curseur pour le retrouver tout de suite, et un réticule au centre de l'écran._
- **Écran d'absence** — case, défaut **décochée**  
  _Quand tu passes absent hors combat, l'interface s'efface, la caméra tourne lentement et un bandeau montre ton personnage et la durée de l'absence._
- **Fenêtres déplaçables** — case, défaut **décochée**  
  _Déplacer les fenêtres Blizzard à la souris : Maj pour garder la place, Ctrl pour cette fois seulement._
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
- **Nom (renommer ou dupliquer)** — zone de texte
- **Renommer le profil actif** — bouton
- **Dupliquer le profil actif** — bouton
- **Touche qui bascule sur le profil actif (ex. CTRL-F5)** — zone de texte

### Partage

> Partage un profil en texte : exporte-le ici, colle-le sur un autre personnage ou envoie-le à un ami. Importer remplace le profil actuel.

- **Chaîne de profil** — zone de texte

> N'exporter que ce qui est coché. Importer une chaîne partielle ne change que ces parties.

- **Thème** — case, défaut **cochée**
- **Listes d'auras** — case, défaut **cochée**
- **Alertes** — case, défaut **cochée**
- **Alertes de mouvement** — case, défaut **cochée**
- **Autre tank** — case, défaut **cochée**
- **Banque** — case, défaut **cochée**
- **Barre de recharge globale** — case, défaut **cochée**
- **Barre du haut** — case, défaut **cochée**
- **Barres d'action AeonUI** — case, défaut **cochée**
- **Barres d'auras** — case, défaut **cochée**
- **Barres de données AeonUI** — case, défaut **cochée**
- **Barres de nom** — case, défaut **cochée**
- **Barres de recharges personnalisées** — case, défaut **cochée**
- **Barres de ressources** — case, défaut **cochée**
- **Bulles de dialogue** — case, défaut **cochée**
- **Butin** — case, défaut **cochée**
- **Cadres Blizzard déplaçables** — case, défaut **cochée**
- **Cadres d'unité** — case, défaut **cochée**
- **Cadres d'unité AeonUI** — case, défaut **cochée**
- **Cadres de groupe et de raid AeonUI** — case, défaut **cochée**
- **Chat AeonUI** — case, défaut **cochée**
- **Clic-sort** — case, défaut **cochée**
- **Confort automatique** — case, défaut **cochée**
- **Curseur et réticule** — case, défaut **cochée**
- **Écran d'absence** — case, défaut **cochée**
- **Fenêtres déplaçables** — case, défaut **cochée**
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
- **Exporter tous les profils du compte** — bouton
- **Importer la chaîne ci-dessus** — bouton
- **Envoyer ce profil à mon groupe** — bouton

### Profil par spécialisation

> Chaque spécialisation peut avoir son profil : changer de spé change de profil. « Aucun » : le profil du personnage ci-dessus.

> Ce client n'expose aucune spécialisation.

### Profil par contexte

> Prime sur la spécialisation. Bascule à l'écran de chargement, après le combat. « Aucun » : profil de la spé, puis du personnage.

- **Hors instance** — liste, défaut **Aucun**
- **Donjon** — liste, défaut **Aucun**
- **Raid** — liste, défaut **Aucun**
- **Champ de bataille et arène** — liste, défaut **Aucun**

### Préréglages de rôle

> Les préréglages de rôle ajustent cadres de groupe, cadres d'unité et plaques de nom pour un rôle. Applique-en un au profil actuel, bascule sur le profil de base du rôle (partagé par tous tes personnages, créé depuis les défauts s'il manque), ou crée un profil pour ce personnage (copie de l'actuel, puis ajusté).

- **Rôle** — liste, défaut **Soigneur**
- **Appliquer ce rôle au profil actuel** — bouton
- **Basculer sur le profil de base de ce rôle (créé s'il manque)** — bouton
- **Créer un profil pour ce personnage avec ce rôle** — bouton

### Profils de classe

> Profils pensés pour ta classe, un par façon de la jouer : disposition du rôle, plus les réglages du style (ressources, coups blancs, barre d'incantation, recharge globale) et de la classe (familier, totems, formes, rappels). Applique-en un au profil actuel, ou bascule sur le profil « Classe - Style » (partagé par tes personnages de cette classe, créé avec toute l'interface AeonUI s'il manque).

- **Style** — liste, défaut **Lanceur de sorts**
- **Appliquer ce style au profil actuel** — bouton
- **Basculer sur le profil de classe de ce style (créé s'il manque)** — bouton

## Maintenance

Le diagnostic liste ce que ce client de jeu propose, pour signaler un problème. Désinstaller rend tous les réglages Blizzard que AeonUI a changés.

- **Revoir la fenêtre de bienvenue** — bouton
- **Lancer le diagnostic (/aeon diag)** — bouton
- **Désinstaller proprement (/aeon uninstall)** — bouton

## Alertes

Grands messages à l'écran : entrée et sortie de combat, mort d'un membre du groupe, et chronomètre de combat.

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

## Alertes de mouvement

Les sorts de déplacement de ta classe affichés pendant leur recharge, avec une annonce à leur retour.

- **Taille des icônes** — curseur, défaut **36**, 16 – 64, pas 1
- **Annoncer le retour d'un sort** — case, défaut **cochée**
- **Identifiants de sorts en plus** — zone de texte

## Autre tank

Quand tu tankes en raid, une barre de vie pour l'autre tank. Clique dessus pour le cibler. Tank = rôle de groupe, assignation « tank principal », ou forcé ci-dessous.

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

## Banque

Fenêtre de banque au thème, un onglet par coffre, cases habillées comme les sacs.

> Niveau d'objet, camelote et bordures suivent les réglages du module Sacs.

- **Colonnes** — curseur, défaut **14**, 4 – 24, pas 1
- **Taille des boutons** — curseur, défaut **34**, 24 – 48, pas 1

## Barre de recharge globale

Une barre fine qui se remplit pendant votre recharge globale, cachée le reste du temps.

- **Longueur** — curseur, défaut **220**, 60 – 500, pas 2
- **Épaisseur** — curseur, défaut **4**, 2 – 30, pas 1
- **Couleur** — couleur, défaut **#FFD133**

## Barre du haut

Une fine barre en haut de l'écran : amis et guilde en ligne, heure, or, durabilité, places libres dans les sacs, FPS et latence, et un bouton pierre de foyer.

- **Position** — liste, défaut **En haut**
- **Déverrouiller / verrouiller les cadres mobiles** — bouton
- **Réinitialiser la position de la barre** — bouton
- **Opacité du fond** — curseur, défaut **0.75**, 0 – 1, pas 0.05
- **Garder FPS et latence visibles quand la barre est cachée** — case, défaut **cochée**

### Visibilité

- **Afficher quand** — liste, défaut **Toutes les conditions sont remplies**
- **En combat** — liste, défaut **Indifférent**
- **En groupe** — liste, défaut **Indifférent**
- **En raid** — liste, défaut **Indifférent**
- **Sur une monture** — liste, défaut **Indifférent**
- **Avec une cible** — liste, défaut **Indifférent**
- **Au survol seulement** — case, défaut **décochée**

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

> Les barres Blizzard reviennent après un /reload une fois ce module coupé. Les raccourcis sont ceux de Blizzard (Options > Raccourcis).

- **Masquer les barres d'action Blizzard** — case, défaut **cochée**
- **Micro-menu (personnage, grimoire, options…)** — liste, défaut **Déplaçable (/aeon unlock)**
- **Barre des sacs** — liste, défaut **Déplaçable (/aeon unlock)**
- **Barre de posture (postures, formes, auras, furtivité)** — liste, défaut **Déplaçable (/aeon unlock)**
- **Barre de totems du chaman (Appel des éléments)** — liste, défaut **Déplaçable (/aeon unlock)**
- **Barre du familier** — liste, défaut **Déplaçable (/aeon unlock)**
- **Afficher les raccourcis sur les boutons** — case, défaut **cochée**
- **Afficher le nom des macros sur les boutons** — case, défaut **cochée**
- **Survoler une barre « au survol » les révèle toutes** — case, défaut **décochée**

### Style des boutons

- **Icônes** — liste, défaut **Blizzard**
- **Recadrage de l'icône** — curseur, défaut **0.08**, 0 – 0.2, pas 0.01
- **Bordure couleur de classe** — case, défaut **décochée**
- **Icônes grisées pendant la recharge** — case, défaut **cochée**
- **Couleur du voile de recharge** — couleur, défaut **#000000**
- **Lueur des sorts en surbrillance** — liste, défaut **Blizzard**
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

#### Visibilité

- **Afficher quand** — liste, défaut **Toutes les conditions sont remplies**
- **En combat** — liste, défaut **Indifférent**
- **En groupe** — liste, défaut **Indifférent**
- **En raid** — liste, défaut **Indifférent**
- **Sur une monture** — liste, défaut **Indifférent**
- **Avec une cible** — liste, défaut **Indifférent**

### Barre d'action 2

- **Afficher cette barre** — case, défaut **cochée**
- **Copier les réglages depuis** — liste
- **Boutons** — curseur, défaut **12**, 1 – 12, pas 1
- **Boutons par ligne** — curseur, défaut **12**, 1 – 12, pas 1
- **Taille des boutons** — curseur, défaut **36**, 20 – 64, pas 1
- **Espacement** — curseur, défaut **4**, 0 – 16, pas 1
- **Opacité** — curseur, défaut **1.0**, 0.1 – 1, pas 0.1
- **Visible seulement au survol** — case, défaut **décochée**

#### Visibilité

- **Afficher quand** — liste, défaut **Toutes les conditions sont remplies**
- **En combat** — liste, défaut **Indifférent**
- **En groupe** — liste, défaut **Indifférent**
- **En raid** — liste, défaut **Indifférent**
- **Sur une monture** — liste, défaut **Indifférent**
- **Avec une cible** — liste, défaut **Indifférent**

### Barre d'action 3

- **Afficher cette barre** — case, défaut **cochée**
- **Copier les réglages depuis** — liste
- **Boutons** — curseur, défaut **12**, 1 – 12, pas 1
- **Boutons par ligne** — curseur, défaut **12**, 1 – 12, pas 1
- **Taille des boutons** — curseur, défaut **36**, 20 – 64, pas 1
- **Espacement** — curseur, défaut **4**, 0 – 16, pas 1
- **Opacité** — curseur, défaut **1.0**, 0.1 – 1, pas 0.1
- **Visible seulement au survol** — case, défaut **décochée**

#### Visibilité

- **Afficher quand** — liste, défaut **Toutes les conditions sont remplies**
- **En combat** — liste, défaut **Indifférent**
- **En groupe** — liste, défaut **Indifférent**
- **En raid** — liste, défaut **Indifférent**
- **Sur une monture** — liste, défaut **Indifférent**
- **Avec une cible** — liste, défaut **Indifférent**

### Barre d'action 4

- **Afficher cette barre** — case, défaut **décochée**
- **Copier les réglages depuis** — liste
- **Boutons** — curseur, défaut **12**, 1 – 12, pas 1
- **Boutons par ligne** — curseur, défaut **1**, 1 – 12, pas 1
- **Taille des boutons** — curseur, défaut **36**, 20 – 64, pas 1
- **Espacement** — curseur, défaut **4**, 0 – 16, pas 1
- **Opacité** — curseur, défaut **1.0**, 0.1 – 1, pas 0.1
- **Visible seulement au survol** — case, défaut **décochée**

#### Visibilité

- **Afficher quand** — liste, défaut **Toutes les conditions sont remplies**
- **En combat** — liste, défaut **Indifférent**
- **En groupe** — liste, défaut **Indifférent**
- **En raid** — liste, défaut **Indifférent**
- **Sur une monture** — liste, défaut **Indifférent**
- **Avec une cible** — liste, défaut **Indifférent**

### Barre d'action 5

- **Afficher cette barre** — case, défaut **décochée**
- **Copier les réglages depuis** — liste
- **Boutons** — curseur, défaut **12**, 1 – 12, pas 1
- **Boutons par ligne** — curseur, défaut **1**, 1 – 12, pas 1
- **Taille des boutons** — curseur, défaut **36**, 20 – 64, pas 1
- **Espacement** — curseur, défaut **4**, 0 – 16, pas 1
- **Opacité** — curseur, défaut **1.0**, 0.1 – 1, pas 0.1
- **Visible seulement au survol** — case, défaut **décochée**

#### Visibilité

- **Afficher quand** — liste, défaut **Toutes les conditions sont remplies**
- **En combat** — liste, défaut **Indifférent**
- **En groupe** — liste, défaut **Indifférent**
- **En raid** — liste, défaut **Indifférent**
- **Sur une monture** — liste, défaut **Indifférent**
- **Avec une cible** — liste, défaut **Indifférent**

### Barre d'action 6

- **Afficher cette barre** — case, défaut **décochée**
- **Copier les réglages depuis** — liste
- **Boutons** — curseur, défaut **12**, 1 – 12, pas 1
- **Boutons par ligne** — curseur, défaut **12**, 1 – 12, pas 1
- **Taille des boutons** — curseur, défaut **36**, 20 – 64, pas 1
- **Espacement** — curseur, défaut **4**, 0 – 16, pas 1
- **Opacité** — curseur, défaut **1.0**, 0.1 – 1, pas 0.1
- **Visible seulement au survol** — case, défaut **décochée**

#### Visibilité

- **Afficher quand** — liste, défaut **Toutes les conditions sont remplies**
- **En combat** — liste, défaut **Indifférent**
- **En groupe** — liste, défaut **Indifférent**
- **En raid** — liste, défaut **Indifférent**
- **Sur une monture** — liste, défaut **Indifférent**
- **Avec une cible** — liste, défaut **Indifférent**

### Barre d'action 7

- **Afficher cette barre** — case, défaut **décochée**
- **Copier les réglages depuis** — liste
- **Boutons** — curseur, défaut **12**, 1 – 12, pas 1
- **Boutons par ligne** — curseur, défaut **12**, 1 – 12, pas 1
- **Taille des boutons** — curseur, défaut **36**, 20 – 64, pas 1
- **Espacement** — curseur, défaut **4**, 0 – 16, pas 1
- **Opacité** — curseur, défaut **1.0**, 0.1 – 1, pas 0.1
- **Visible seulement au survol** — case, défaut **décochée**

#### Visibilité

- **Afficher quand** — liste, défaut **Toutes les conditions sont remplies**
- **En combat** — liste, défaut **Indifférent**
- **En groupe** — liste, défaut **Indifférent**
- **En raid** — liste, défaut **Indifférent**
- **Sur une monture** — liste, défaut **Indifférent**
- **Avec une cible** — liste, défaut **Indifférent**

### Barre d'action 8

- **Afficher cette barre** — case, défaut **décochée**
- **Copier les réglages depuis** — liste
- **Boutons** — curseur, défaut **12**, 1 – 12, pas 1
- **Boutons par ligne** — curseur, défaut **12**, 1 – 12, pas 1
- **Taille des boutons** — curseur, défaut **36**, 20 – 64, pas 1
- **Espacement** — curseur, défaut **4**, 0 – 16, pas 1
- **Opacité** — curseur, défaut **1.0**, 0.1 – 1, pas 0.1
- **Visible seulement au survol** — case, défaut **décochée**

#### Visibilité

- **Afficher quand** — liste, défaut **Toutes les conditions sont remplies**
- **En combat** — liste, défaut **Indifférent**
- **En groupe** — liste, défaut **Indifférent**
- **En raid** — liste, défaut **Indifférent**
- **Sur une monture** — liste, défaut **Indifférent**
- **Avec une cible** — liste, défaut **Indifférent**

## Barres d'auras

Tes buffs et débuffs en barres horizontales avec le temps restant, les plus courts d'abord.

- **Afficher** — liste, défaut **Buffs et débuffs**
- **Masquer les auras sans durée** — case, défaut **cochée**
- **Nombre de barres maximum** — curseur, défaut **12**, 1 – 40, pas 1
- **Longueur** — curseur, défaut **220**, 100 – 500, pas 2
- **Épaisseur** — curseur, défaut **18**, 10 – 40, pas 1
- **Espacement** — curseur, défaut **2**, 0 – 10, pas 1
- **Empiler vers le haut** — case, défaut **décochée**
- **Couleur des buffs** — couleur, défaut **#3FA8F4**

## Barres de données AeonUI

Barre d'expérience (avec le bonus de repos, cachée au niveau maximum) et barre de la réputation suivie, déplaçables, avec texte et infobulle. Remplacent les barres Blizzard.

> Les barres Blizzard reviennent après un /reload une fois ce module coupé. Suis une réputation depuis le panneau de réputation.

- **Cacher les barres Blizzard d'expérience et de réputation** — case, défaut **cochée**
- **Déverrouiller (déplacer les cadres)** — bouton

### Expérience

- **Afficher cette barre** — case, défaut **cochée**
- **Orientation** — liste, défaut **Horizontale**
- **Longueur** — curseur, défaut **300**, 100 – 800, pas 10
- **Épaisseur** — curseur, défaut **10**, 4 – 30, pas 1
- **Texte sur la barre** — case, défaut **cochée**

### Réputation

- **Afficher cette barre** — case, défaut **cochée**
- **Orientation** — liste, défaut **Horizontale**
- **Longueur** — curseur, défaut **300**, 100 – 800, pas 10
- **Épaisseur** — curseur, défaut **10**, 4 – 30, pas 1
- **Texte sur la barre** — case, défaut **cochée**

## Barres de nom

Deux chevrons autour de la barre de nom de ta cible, pour ne jamais la perdre dans un pack. Celui de gauche s'écarte quand la cible incante.

- **Cibles hostiles seulement** — case, défaut **cochée**
- **Taille** — curseur, défaut **26**, 8 – 48, pas 2
- **Écart avec la barre de nom** — curseur, défaut **4**, 0 – 40, pas 1
- **Couleur hors combat** — couleur, défaut **#FFD119**
- **Couleur en combat** — couleur, défaut **#FF4C33**
- **Couleur quand un autre tank a l'agro** — couleur, défaut **#4C99FF**
- **Écarter le chevron gauche pendant une incantation de la cible** — case, défaut **cochée**
- **Écart supplémentaire pendant l'incantation** — curseur, défaut **8**, 0 – 30, pas 1

## Barres de recharges personnalisées

Jusqu'à trois rangées d'icônes de sorts au choix, avec recharge et charges.

### Barre de recharges 1

- **Afficher cette barre** — case, défaut **cochée**
- **Identifiants des sorts, dans l'ordre** — zone de texte
- **Taille des icônes** — curseur, défaut **36**, 16 – 64, pas 1
- **Espacement** — curseur, défaut **4**, 0 – 12, pas 1
- **Icônes par rangée** — curseur, défaut **12**, 1 – 24, pas 1
- **Masquer les sorts prêts** — case, défaut **décochée**
- **Icônes grisées pendant la recharge** — case, défaut **cochée**

### Barre de recharges 2

- **Afficher cette barre** — case, défaut **décochée**
- **Identifiants des sorts, dans l'ordre** — zone de texte
- **Taille des icônes** — curseur, défaut **36**, 16 – 64, pas 1
- **Espacement** — curseur, défaut **4**, 0 – 12, pas 1
- **Icônes par rangée** — curseur, défaut **12**, 1 – 24, pas 1
- **Masquer les sorts prêts** — case, défaut **décochée**
- **Icônes grisées pendant la recharge** — case, défaut **cochée**

### Barre de recharges 3

- **Afficher cette barre** — case, défaut **décochée**
- **Identifiants des sorts, dans l'ordre** — zone de texte
- **Taille des icônes** — curseur, défaut **36**, 16 – 64, pas 1
- **Espacement** — curseur, défaut **4**, 0 – 12, pas 1
- **Icônes par rangée** — curseur, défaut **12**, 1 – 24, pas 1
- **Masquer les sorts prêts** — case, défaut **décochée**
- **Icônes grisées pendant la recharge** — case, défaut **cochée**

## Barres de ressources

Votre vie, puissance, points de combo et mana de druide en barres séparées, placées et ancrées où vous voulez.

- **Orientation** — liste, défaut **Horizontale**
- **Longueur** — curseur, défaut **220**, 60 – 500, pas 2
- **Opacité hors combat** — curseur, défaut **1.00**, 0 – 1, pas 0.05

### Visibilité

- **Afficher quand** — liste, défaut **Toutes les conditions sont remplies**
- **En combat** — liste, défaut **Indifférent**
- **En groupe** — liste, défaut **Indifférent**
- **En raid** — liste, défaut **Indifférent**
- **En instance** — liste, défaut **Indifférent**
- **Sur une monture** — liste, défaut **Indifférent**
- **Avec une cible** — liste, défaut **Indifférent**

### Vie

- **Afficher** — case, défaut **décochée**
- **Épaisseur** — curseur, défaut **14**, 4 – 40, pas 1
- **Texte** — liste, défaut **Valeur | pourcentage**
- **Couleur de classe** — case, défaut **cochée**
- **Couleur sous (%)** — curseur, défaut **0**, 0 – 90, pas 5
  - **Couleur** — couleur, défaut **#E52626**
- **Deuxième couleur sous (%)** — curseur, défaut **0**, 0 – 95, pas 5
  - **Couleur** — couleur, défaut **#F2BF19**
- **Repères à (%, par ex. 25, 50)** — zone de texte

### Puissance

- **Afficher** — case, défaut **cochée**
- **Épaisseur** — curseur, défaut **12**, 4 – 40, pas 1
- **Texte** — liste, défaut **Valeur courante**
- **Repère à (%, 0 = aucun)** — curseur, défaut **0**, 0 – 100, pas 5
- **Couleur sous (%)** — curseur, défaut **0**, 0 – 90, pas 5
  - **Couleur** — couleur, défaut **#E52626**
- **Deuxième couleur sous (%)** — curseur, défaut **0**, 0 – 95, pas 5
  - **Couleur** — couleur, défaut **#F2BF19**
- **Repères à (%, par ex. 25, 50)** — zone de texte

### Points de combo

- **Afficher** — case, défaut **cochée**
- **Épaisseur** — curseur, défaut **8**, 4 – 30, pas 1

### Mana en forme de druide

- **Afficher** — case, défaut **cochée**
- **Épaisseur** — curseur, défaut **6**, 2 – 30, pas 1

## Bulles de dialogue

Bulles au thème, bordure à la couleur du canal, canaux affichés un par un.

> En instance, le jeu protège les bulles : elles gardent l'aspect Blizzard.

- **Dire** — case, défaut **cochée**
- **Crier** — case, défaut **cochée**
- **Groupe** — case, défaut **cochée**
- **PNJ** — case, défaut **cochée**
- **Taille de police** — curseur, défaut **12**, 8 – 20, pas 1
- **Bordure à la couleur du canal** — case, défaut **cochée**

## Butin

Fenêtre de butin au thème (au curseur ou sur son mover) et barres de jets de groupe : besoin, cupidité, désenchantement, passer, temps restant.

- **Fenêtre de butin AeonUI** — case, défaut **cochée**
- **Ouvrir au curseur (sinon sur son mover)** — case, défaut **cochée**
- **Barres de jets AeonUI** — case, défaut **cochée**
- **Largeur** — curseur, défaut **300**, 200 – 500, pas 10
- **Déverrouiller / verrouiller les cadres mobiles** — bouton

## Cadres Blizzard déplaçables

Gestionnaire de recharges (essentiel, utilitaire, icônes de buff, barres de buff), buffs et débuffs du joueur sur des movers AeonUI, jamais reparentés. Chacun peut rester à Edit Mode.

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

- **Mode sombre (bordures des cadres assombries)** — case, défaut **cochée**
- **Barres de vie à la couleur de classe pour les joueurs** — case, défaut **cochée**
- **Noms à la couleur de classe sur les cadres de raid** — case, défaut **cochée**
- **Épées croisées à côté de la cible quand elle est en combat** — case, défaut **cochée**

## Cadres d'unité AeonUI

Remplace les cadres Blizzard du joueur, de la cible, de la cible de la cible, du focus et du familier par des cadres AeonUI : vie, puissance, barre d'incantation, auras, nom, niveau, repères de combat, repos et chef, marqueur de raid, points de combo. Déplaçables avec /aeon unlock.

> Les cadres Blizzard reviennent après un /reload une fois ce module coupé.

- **Couleur de classe pour les joueurs (couleur de réaction sinon)** — case, défaut **cochée**
- **Couleur de vie du rouge au vert selon le pourcentage** — case, défaut **décochée**
- **Couleur sous (%)** — curseur, défaut **0**, 0 – 90, pas 5
  - **Couleur** — couleur, défaut **#E52626**
- **Soins entrants et absorptions** — case, défaut **cochée**
- **Couleur des soins entrants** — couleur, défaut **#33E54C**
- **Couleur des absorptions** — couleur, défaut **#FFFFFF**
- **Couleur des soins absorbés** — couleur, défaut **#CC2626**
- **Hauteur des absorptions (%)** — curseur, défaut **100**, 10 – 100, pas 5
- **Couleur hostile** — couleur, défaut **#D83333**
- **Couleur neutre** — couleur, défaut **#E5CC33**
- **Couleur amicale** — couleur, défaut **#33BF33**
- **Couleur déjà engagé** — couleur, défaut **#7F7F7F**
- **Texte de vie** — liste, défaut **Valeur courante**
- **Texte de puissance** — liste, défaut **Aucun**
- **Opacité des cadres estompés** — curseur, défaut **0.35**, 0 – 0.9, pas 0.05
- **Opacité hors de portée** — curseur, défaut **0.50**, 0.1 – 0.9, pas 0.05
- **Barre d'incantation : cible du sort** — case, défaut **cochée**
- **Incantation du joueur : zone de latence** — case, défaut **cochée**
- **Incantation du joueur : tops des canalisations** — case, défaut **cochée**
- **Incantation du joueur : fin de la recharge globale** — case, défaut **décochée**
- **Barre d'incantation colorée quand ton interruption est prête** — case, défaut **cochée**
- **Couleur « interruption prête »** — couleur, défaut **#33D859**

> Format personnalisé par cadre : texte libre avec [cur], [max], [perc], [missing], [status], [name], [level]. Exemple : [cur] / [max] ([perc]). Un format vide reprend le préréglage ci-dessus.

### Listes d'auras (partagées)

> Identifiants de sorts séparés par des virgules. Partagées par les cadres d'unité, les plaques et la barre co-tank. Liste blanche : toujours montrés. Liste noire : toujours cachés.

- **Liste blanche** — zone de texte
- **Liste noire** — zone de texte
- **Débuffs en tête : boss, contrôle, dissipable** — case, défaut **cochée**
- **Lueur sur les contrôles** — liste, défaut **Traits pixel**
- **Déverrouiller (déplacer les cadres)** — bouton

### Joueur

- **Afficher ce cadre** — case, défaut **cochée**
- **Copier les réglages depuis** — liste
- **Largeur** — curseur, défaut **220**, 60 – 400, pas 2
- **Hauteur** — curseur, défaut **42**, 12 – 80, pas 1
- **Barre de vie verticale (remplie de bas en haut)** — case, défaut **décochée**
- **Nom** — case, défaut **cochée**
- **Niveau** — case, défaut **cochée**
- **Estomper hors combat quand rien ne se passe** — case, défaut **décochée**
- **Portrait** — case, défaut **décochée**
- **Icône élite ou rare** — case, défaut **décochée**
- **Écusson de faction si marqué JcJ** — case, défaut **cochée**
- **Bordure à la couleur de la menace** — case, défaut **cochée**
- **Barre de points de combo** — case, défaut **cochée**
  - **Pastilles séparées** — case, défaut **décochée**
  - **Espace entre pastilles** — curseur, défaut **2**, 0 – 10, pas 1
  - **Couleur des points de combo** — couleur, défaut **#FFD100**
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
- **Texte central (barre de vie)** — zone de texte
- **Format de puissance (vide = préréglage)** — zone de texte

#### Visibilité

- **Afficher quand** — liste, défaut **Toutes les conditions sont remplies**
- **En combat** — liste, défaut **Indifférent**
- **En groupe** — liste, défaut **Indifférent**
- **En raid** — liste, défaut **Indifférent**
- **Sur une monture** — liste, défaut **Indifférent**
- **Avec une cible** — liste, défaut **Indifférent**

### Cible

- **Afficher ce cadre** — case, défaut **cochée**
- **Copier les réglages depuis** — liste
- **Largeur** — curseur, défaut **220**, 60 – 400, pas 2
- **Hauteur** — curseur, défaut **42**, 12 – 80, pas 1
- **Barre de vie verticale (remplie de bas en haut)** — case, défaut **décochée**
- **Nom** — case, défaut **cochée**
- **Niveau** — case, défaut **cochée**
- **Estomper hors combat quand rien ne se passe** — case, défaut **décochée**
- **Atténuer les ennemis hors de portée d'attaque** — case, défaut **décochée**
- **Portrait** — case, défaut **décochée**
- **Icône élite ou rare** — case, défaut **cochée**
- **Écusson de faction si marqué JcJ** — case, défaut **cochée**
- **Bordure à la couleur de la menace** — case, défaut **décochée**
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
- **Texte central (barre de vie)** — zone de texte
- **Format de puissance (vide = préréglage)** — zone de texte

#### Visibilité

- **Afficher quand** — liste, défaut **Toutes les conditions sont remplies**
- **En combat** — liste, défaut **Indifférent**
- **En groupe** — liste, défaut **Indifférent**
- **En raid** — liste, défaut **Indifférent**
- **Sur une monture** — liste, défaut **Indifférent**
- **Avec une cible** — liste, défaut **Indifférent**

### Cible de la cible

- **Afficher ce cadre** — case, défaut **cochée**
- **Copier les réglages depuis** — liste
- **Largeur** — curseur, défaut **110**, 60 – 400, pas 2
- **Hauteur** — curseur, défaut **24**, 12 – 80, pas 1
- **Barre de vie verticale (remplie de bas en haut)** — case, défaut **décochée**
- **Nom** — case, défaut **cochée**
- **Niveau** — case, défaut **décochée**
- **Estomper hors combat quand rien ne se passe** — case, défaut **décochée**
- **Atténuer les ennemis hors de portée d'attaque** — case, défaut **décochée**
- **Portrait** — case, défaut **décochée**
- **Icône élite ou rare** — case, défaut **décochée**
- **Écusson de faction si marqué JcJ** — case, défaut **décochée**
- **Bordure à la couleur de la menace** — case, défaut **décochée**
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
- **Texte central (barre de vie)** — zone de texte

#### Visibilité

- **Afficher quand** — liste, défaut **Toutes les conditions sont remplies**
- **En combat** — liste, défaut **Indifférent**
- **En groupe** — liste, défaut **Indifférent**
- **En raid** — liste, défaut **Indifférent**
- **Sur une monture** — liste, défaut **Indifférent**
- **Avec une cible** — liste, défaut **Indifférent**

### Focus

- **Afficher ce cadre** — case, défaut **cochée**
- **Copier les réglages depuis** — liste
- **Largeur** — curseur, défaut **180**, 60 – 400, pas 2
- **Hauteur** — curseur, défaut **36**, 12 – 80, pas 1
- **Barre de vie verticale (remplie de bas en haut)** — case, défaut **décochée**
- **Nom** — case, défaut **cochée**
- **Niveau** — case, défaut **cochée**
- **Estomper hors combat quand rien ne se passe** — case, défaut **décochée**
- **Atténuer les ennemis hors de portée d'attaque** — case, défaut **décochée**
- **Portrait** — case, défaut **décochée**
- **Icône élite ou rare** — case, défaut **cochée**
- **Écusson de faction si marqué JcJ** — case, défaut **décochée**
- **Bordure à la couleur de la menace** — case, défaut **décochée**
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
- **Texte central (barre de vie)** — zone de texte
- **Format de puissance (vide = préréglage)** — zone de texte

#### Visibilité

- **Afficher quand** — liste, défaut **Toutes les conditions sont remplies**
- **En combat** — liste, défaut **Indifférent**
- **En groupe** — liste, défaut **Indifférent**
- **En raid** — liste, défaut **Indifférent**
- **Sur une monture** — liste, défaut **Indifférent**
- **Avec une cible** — liste, défaut **Indifférent**

### Cible du focus

- **Afficher ce cadre** — case, défaut **décochée**
- **Copier les réglages depuis** — liste
- **Largeur** — curseur, défaut **110**, 60 – 400, pas 2
- **Hauteur** — curseur, défaut **24**, 12 – 80, pas 1
- **Barre de vie verticale (remplie de bas en haut)** — case, défaut **décochée**
- **Nom** — case, défaut **cochée**
- **Niveau** — case, défaut **décochée**
- **Estomper hors combat quand rien ne se passe** — case, défaut **décochée**
- **Atténuer les ennemis hors de portée d'attaque** — case, défaut **décochée**
- **Portrait** — case, défaut **décochée**
- **Icône élite ou rare** — case, défaut **décochée**
- **Écusson de faction si marqué JcJ** — case, défaut **décochée**
- **Bordure à la couleur de la menace** — case, défaut **décochée**
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
- **Texte central (barre de vie)** — zone de texte

#### Visibilité

- **Afficher quand** — liste, défaut **Toutes les conditions sont remplies**
- **En combat** — liste, défaut **Indifférent**
- **En groupe** — liste, défaut **Indifférent**
- **En raid** — liste, défaut **Indifférent**
- **Sur une monture** — liste, défaut **Indifférent**
- **Avec une cible** — liste, défaut **Indifférent**

### Familier

- **Afficher ce cadre** — case, défaut **cochée**
- **Copier les réglages depuis** — liste
- **Largeur** — curseur, défaut **110**, 60 – 400, pas 2
- **Hauteur** — curseur, défaut **24**, 12 – 80, pas 1
- **Barre de vie verticale (remplie de bas en haut)** — case, défaut **décochée**
- **Nom** — case, défaut **cochée**
- **Niveau** — case, défaut **décochée**
- **Estomper hors combat quand rien ne se passe** — case, défaut **décochée**
- **Atténuer les ennemis hors de portée d'attaque** — case, défaut **décochée**
- **Portrait** — case, défaut **décochée**
- **Icône élite ou rare** — case, défaut **décochée**
- **Écusson de faction si marqué JcJ** — case, défaut **décochée**
- **Bordure à la couleur de la menace** — case, défaut **décochée**
- **Humeur du familier de chasseur** — case, défaut **cochée**
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
- **Texte central (barre de vie)** — zone de texte
- **Format de puissance (vide = préréglage)** — zone de texte

#### Visibilité

- **Afficher quand** — liste, défaut **Toutes les conditions sont remplies**
- **En combat** — liste, défaut **Indifférent**
- **En groupe** — liste, défaut **Indifférent**
- **En raid** — liste, défaut **Indifférent**
- **Sur une monture** — liste, défaut **Indifférent**
- **Avec une cible** — liste, défaut **Indifférent**

### Boss (1 à 5)

- **Afficher ce cadre** — case, défaut **cochée**
- **Copier les réglages depuis** — liste
- **Largeur** — curseur, défaut **200**, 60 – 400, pas 2
- **Hauteur** — curseur, défaut **36**, 12 – 80, pas 1
- **Barre de vie verticale (remplie de bas en haut)** — case, défaut **décochée**
- **Nom** — case, défaut **cochée**
- **Niveau** — case, défaut **cochée**
- **Estomper hors combat quand rien ne se passe** — case, défaut **décochée**
- **Atténuer les ennemis hors de portée d'attaque** — case, défaut **décochée**
- **Portrait** — case, défaut **décochée**
- **Icône élite ou rare** — case, défaut **cochée**
- **Écusson de faction si marqué JcJ** — case, défaut **décochée**
- **Bordure à la couleur de la menace** — case, défaut **décochée**
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
- **Texte central (barre de vie)** — zone de texte
- **Format de puissance (vide = préréglage)** — zone de texte

#### Visibilité

- **Afficher quand** — liste, défaut **Toutes les conditions sont remplies**
- **En combat** — liste, défaut **Indifférent**
- **En groupe** — liste, défaut **Indifférent**
- **En raid** — liste, défaut **Indifférent**
- **Sur une monture** — liste, défaut **Indifférent**
- **Avec une cible** — liste, défaut **Indifférent**

## Cadres de groupe et de raid AeonUI

Remplace les cadres Blizzard de groupe et de raid par des grilles AeonUI : vie, puissance, nom, icônes de rôle et de chef, marqueur de raid, bordures d'agro et de débuff dissipable, atténuation hors de portée. Clic pour cibler, clic droit pour le menu.

> Les cadres Blizzard de groupe et de raid reviennent après un /reload une fois ce module coupé.

- **Aperçu : groupe** — bouton
- **Aperçu : raid** — bouton
- **Masquer l'aperçu** — bouton
- **Déverrouiller (déplacer les cadres)** — bouton
- **Espacement entre les cadres** — curseur, défaut **3**, 0 – 20, pas 1
- **Masquer l'habillage Blizzard des plaques** — case, défaut **cochée**

### Groupe

- **Largeur** — curseur, défaut **120**, 40 – 200, pas 2
- **Hauteur** — curseur, défaut **56**, 12 – 80, pas 1
- **Trier par rôle (tanks, soigneurs, dégâts)** — case, défaut **cochée**
- **T'afficher dans le groupe** — case, défaut **cochée**
- **Afficher le cadre de groupe en solo (pour le régler)** — case, défaut **décochée**
- **Groupe en ligne plutôt qu'en colonne** — case, défaut **décochée**
- **Croissance inversée (vers le haut ou la gauche)** — case, défaut **décochée**

### Raid

- **Largeur** — curseur, défaut **96**, 40 – 200, pas 2
- **Hauteur** — curseur, défaut **44**, 12 – 80, pas 1
- **Trier par** — liste, défaut **Rôle (tank, soigneur, dégâts)**
- **Unités par colonne** — curseur, défaut **5**, 1 – 10, pas 1
- **Colonnes** — curseur, défaut **8**, 1 – 8, pas 1
- **Croissance des membres** — liste, défaut **Vers le bas**
- **Croissance des colonnes** — liste, défaut **Vers la droite**  
  _Les colonnes croissent toujours en travers des membres : une colonne sur le même axe est corrigée._
- **Groupes affichés (1 à N)** — curseur, défaut **8**, 1 – 8, pas 1
- **Cadres de raid au-delà de** — liste, défaut **5**  
  _Nombre de membres : jusqu'à ce seuil, un raid garde la disposition du groupe (colonne ou ligne par groupe de 5) ; au-delà, la grille de raid prend le relais. 5 = dès qu'on est en raid._
- **Cadres des tanks principaux (raid)** — case, défaut **décochée**
- **Cadres des assistants principaux (raid)** — case, défaut **décochée**
- **Cadres extra (tanks du groupe)** — case, défaut **décochée**
- **Joueurs à la place des tanks** — zone de texte  
  _Noms séparés par des virgules. Vide : les joueurs au rôle de tank._
- **Cadres des boss alliés** — case, défaut **décochée**
- **Mana des soigneurs (texte)** — liste, défaut **Désactivé**

### Barres

- **Couleur de classe pour les joueurs (couleur de réaction sinon)** — case, défaut **cochée**
- **Couleur de vie du rouge au vert selon le pourcentage** — case, défaut **décochée**
- **Soins entrants et absorptions** — case, défaut **cochée**
- **Barre de vie verticale (remplie de bas en haut)** — case, défaut **décochée**
- **Barre de puissance** — case, défaut **cochée**
- **Hauteur de la barre de puissance** — curseur, défaut **4**, 0 – 12, pas 1
- **Afficher pour les tanks** — case, défaut **cochée**
- **Afficher pour les soigneurs** — case, défaut **cochée**
- **Afficher pour les dégâts** — case, défaut **décochée**  
  _Rôle inconnu (aucun assigné) : ressource affichée._
- **Barre d'incantation** — case, défaut **décochée**
- **Hauteur de la barre d'incantation** — curseur, défaut **4**, 2 – 10, pas 1
- **Portrait** — case, défaut **décochée**

### Textes et icônes

- **Position du nom** — liste, défaut **En haut à gauche**
- **Longueur du nom (0 = entier)** — curseur, défaut **12**, 0 – 20, pas 1
- **Texte de vie** — liste, défaut **Aucun**
- **Mort et hors ligne : fond teinté et texte** — case, défaut **cochée**
- **Icônes de rôle** — case, défaut **cochée**
- **Style de l'icône de rôle** — liste, défaut **Portrait**
- **Taille de l'icône de rôle** — curseur, défaut **13**, 8 – 24, pas 1
- **Coin de l'icône de rôle** — liste, défaut **En bas à gauche**
- **Afficher pour les tanks** — case, défaut **cochée**
- **Afficher pour les soigneurs** — case, défaut **cochée**
- **Afficher pour les dégâts** — case, défaut **décochée**
- **Cacher les icônes de rôle en combat** — case, défaut **décochée**
- **Icône du chef de groupe** — case, défaut **décochée**
- **Icônes d'appel, d'invocation et de résurrection** — case, défaut **cochée**
- **Appel prêt** — case, défaut **cochée**
- **Invocations** — case, défaut **cochée**
- **Résurrections (incantation, puis offre à accepter)** — case, défaut **cochée**
- **Taille de l'icône d'état** — curseur, défaut **16**, 10 – 32, pas 1

### Auras

- **Auras (buffs et débuffs)** — case, défaut **cochée**
- **Position des auras** — liste, défaut **Dans le cadre, en bas à droite**
- **Taille des icônes d'auras** — curseur, défaut **18**, 10 – 32, pas 1
- **Nombre d'auras** — curseur, défaut **3**, 1 – 16, pas 1
- **Filtre des débuffs** — liste, défaut **Tous**
- **Afficher aussi les buffs** — case, défaut **décochée**

### Alertes

- **Bordure à la couleur d'un débuff que tu peux dissiper** — case, défaut **cochée**
- **Débuffs signalés** — liste, défaut **Ceux que je dissipe**
- **Voile de la couleur du type sur la vie** — case, défaut **cochée**
- **Lueur de la couleur du type de débuff** — case, défaut **décochée**
- **Afficher la menace (orange : instable, rouge : agro)** — case, défaut **cochée**
- **Affichage de la menace** — liste, défaut **Lueur**
- **Bordure d'accent sur la cible** — case, défaut **cochée**
- **Surbrillance au survol** — case, défaut **cochée**
- **Atténuer les unités hors de portée** — case, défaut **cochée**
- **Opacité hors de portée** — curseur, défaut **0.4**, 0.1 – 0.9, pas 0.1

### Sorts suivis

> Identifiants de sorts par coin, séparés par des virgules : le premier buff trouvé s'affiche. Tous les rangs d'un sort comptent.

- **En haut à gauche** — zone de texte
- **En haut à droite** — zone de texte
- **En bas à gauche** — zone de texte
- **En bas à droite** — zone de texte
- **Taille des icônes** — curseur, défaut **10**, 6 – 20, pas 1
- **Seulement mes propres sorts** — case, défaut **cochée**
- **Remplir avec le préréglage de ma classe** — bouton

## Chat AeonUI

Fenêtres de chat au thème (fond, police, onglets plats, boutons latéraux cachés, sans fondu), URL cliquables, bouton de copie du chat, noms de canaux courts, couleur de classe partout, horodatage, zone de saisie en haut ou en bas.

- **Fond et police au thème** — case, défaut **cochée**
- **Couleur et opacité du fond des fenêtres** — couleur, défaut **#0C0F14**
- **Texture du fond** — liste, défaut **Plate**
- **Cacher la barre de défilement (la molette défile toujours)** — case, défaut **décochée**
- **Taille de police** — curseur, défaut **12**, 9 – 20, pas 1
- **Onglets plats** — case, défaut **cochée**
- **Taille de police des onglets** — curseur, défaut **12**, 8 – 20, pas 1
- **Couleur de l'onglet actif** — couleur, défaut **#3FA8F4**
- **Souligner l'onglet actif** — case, défaut **cochée**
- **Barre de raccourcis** — liste, défaut **Aucune**
- **Boutons, dans l'ordre** — zone de texte  
  _Mots : copy, friends, channels, options._
- **Cacher les boutons latéraux (menu, canaux, voix, défilement)** — case, défaut **cochée**
- **Ne jamais estomper les lignes** — case, défaut **cochée**
- **Secondes avant le fondu des lignes** — curseur, défaut **120**, 5 – 600, pas 5
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

### Fenêtres

- **Fenêtre principale à gauche, fenêtre détachée à droite (déplaçables par /aeon unlock)** — case, défaut **cochée**
- **Largeur à gauche** — curseur, défaut **430**, 296 – 900, pas 2
- **Hauteur à gauche** — curseur, défaut **180**, 120 – 600, pas 2
- **Largeur à droite** — curseur, défaut **320**, 296 – 900, pas 2
- **Hauteur à droite** — curseur, défaut **160**, 120 – 600, pas 2
- **Déverrouiller (déplacer les cadres)** — bouton
- **Réorganiser : général à gauche, butin / commerce à droite** — bouton

## Clic-sort

Lance un sort sur un membre du groupe ou du raid d'un clic de souris et d'un modificateur.

> S'applique aux cadres de groupe et de raid AeonUI, hors combat. Les clics sans liaison gardent cible (gauche) et menu (droit). Nom du sort sans rang : le rang le plus haut part.

- **Remplir avec le préréglage de ma classe** — bouton

### Liaison 1

- **Nom du sort** — zone de texte
- **Bouton de souris** — liste, défaut **Gauche**
- **Modificateur** — liste, défaut **Maj**

### Liaison 2

- **Nom du sort** — zone de texte
- **Bouton de souris** — liste, défaut **Gauche**
- **Modificateur** — liste, défaut **Maj**

### Liaison 3

- **Nom du sort** — zone de texte
- **Bouton de souris** — liste, défaut **Gauche**
- **Modificateur** — liste, défaut **Maj**

### Liaison 4

- **Nom du sort** — zone de texte
- **Bouton de souris** — liste, défaut **Gauche**
- **Modificateur** — liste, défaut **Maj**

### Liaison 5

- **Nom du sort** — zone de texte
- **Bouton de souris** — liste, défaut **Gauche**
- **Modificateur** — liste, défaut **Maj**

### Liaison 6

- **Nom du sort** — zone de texte
- **Bouton de souris** — liste, défaut **Gauche**
- **Modificateur** — liste, défaut **Maj**

### Liaison 7

- **Nom du sort** — zone de texte
- **Bouton de souris** — liste, défaut **Gauche**
- **Modificateur** — liste, défaut **Maj**

### Liaison 8

- **Nom du sort** — zone de texte
- **Bouton de souris** — liste, défaut **Gauche**
- **Modificateur** — liste, défaut **Maj**

## Confort automatique

Les petites corvées faites pour toi : réparation et vente des objets gris chez le marchand, maintien de ALT pour libérer l'esprit, invitations des amis et de la guilde acceptées, suppression d'objet pré-remplie.

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

- **Faire tourner la caméra** — case, défaut **cochée**
- **Vitesse de rotation** — curseur, défaut **0.035**, 0.01 – 0.1, pas 0.005

## Fenêtres déplaçables

Déplacer les fenêtres Blizzard à la souris : Maj pour garder la place, Ctrl pour cette fois seulement.

> Maj + glisser : position gardée. Ctrl + glisser : jusqu'à la fermeture. Pas en combat.

- **Remettre les fenêtres à leur place** — bouton

## Fiche de personnage

Niveau d'objet sur chaque emplacement de la fiche, à la couleur de qualité, le niveau moyen, et un repère sur les pièces enchantables sans enchantement. Mêmes niveaux sur la fenêtre d'inspection, et niveau moyen des joueurs dans leur infobulle.

- **Niveau d'objet sur chaque emplacement** — case, défaut **cochée**
- **Niveau d'objet moyen** — case, défaut **cochée**
- **« ! » rouge sur les pièces enchantables sans enchantement** — case, défaut **décochée**
- **Taille du texte** — curseur, défaut **11**, 6 – 20, pas 1
- **Niveaux d'objet sur la fenêtre d'inspection** — case, défaut **cochée**
- **Niveau d'objet moyen des joueurs dans leur infobulle (inspection hors combat)** — case, défaut **cochée**

## Gestionnaire de recharges

Réglages sort par sort du gestionnaire de recharges Blizzard : afficher ou masquer chaque sort sur sa barre, lueur quand il est prêt ou en permanence.

> Choisis une barre, clique sur un sort, puis règle-le. Un sort masqué libère sa place : les suivants remontent. La liste suit la spécialisation en cours ; les réglages valent pour toutes.

- **Style de lueur** — liste, défaut **Halo pulsé**
- **Couleur de la lueur** — couleur, défaut **#FFD133**

### Apparence, barre par barre

- **Bordure du thème** — case, défaut **cochée**
- **Taille des textes (0 = Blizzard)** — curseur, défaut **0**, 0 – 24, pas 1
- **Bordure du thème** — case, défaut **cochée**
- **Taille des textes (0 = Blizzard)** — curseur, défaut **0**, 0 – 24, pas 1
- **Bordure du thème** — case, défaut **cochée**
- **Taille des textes (0 = Blizzard)** — curseur, défaut **0**, 0 – 24, pas 1
- **Bordure du thème** — case, défaut **cochée**
- **Taille des textes (0 = Blizzard)** — curseur, défaut **0**, 0 – 24, pas 1
- **Texture et couleur de barre du thème** — case, défaut **cochée**
  - **Couleur de la barre** — couleur, défaut **#3FA8F4**
- **Afficher le nom du sort** — case, défaut **cochée**
- **Afficher le temps restant** — case, défaut **cochée**

### Sort par sort

## Habillage

Infobulles sombres avec nom et bordure à la couleur de classe, et deux flèches autour de la barre de nom de ta cible.

### Infobulles

- **Infobulles sombres** — case, défaut **cochée**
- **Noms des joueurs à la couleur de classe dans les infobulles** — case, défaut **cochée**
- **Masquer les infobulles d'unité en combat** — case, défaut **décochée**
- **Masquer toutes les infobulles en combat** — case, défaut **décochée**
- **Infobulles par défaut collées au curseur** — case, défaut **décochée**
- **Infobulles par défaut à une position fixe (mover, prioritaire sur le curseur)** — case, défaut **décochée**
- **Sens de croissance** — liste, défaut **Vers le haut et la gauche**
- **Décalage horizontal** — curseur, défaut **0**, -100 – 100, pas 1
- **Décalage vertical** — curseur, défaut **0**, -100 – 100, pas 1
- **Afficher la cible de l'unité** — case, défaut **cochée**
- **Afficher le rang de guilde** — case, défaut **cochée**
- **Afficher l'ID des sorts, objets et auras** — case, défaut **décochée**
- **Masquer la barre de vie sous les infobulles d'unité** — case, défaut **décochée**

### Icônes

- **Rogner le liseré des icônes de buffs et de temps de recharge** — case, défaut **cochée**
- **Rognage** — curseur, défaut **8 %**, 0 – 20, pas 1

### Panneaux

- **Habiller les fenêtres, popups et menus Blizzard (fiche de personnage : bordures de qualité sur l'équipement)** — case, défaut **décochée**
- **Style par défaut** — liste, défaut **Thème AeonUI (plat)**

#### Fenêtre par fenêtre

- **CharacterFrame** — liste
- **InspectFrame** — liste
- **SpellBookFrame** — liste
- **PlayerSpellsFrame** — liste
- **ClassTalentFrame** — liste
- **TalentFrame** — liste
- **FriendsFrame** — liste
- **QuestLogFrame** — liste
- **MerchantFrame** — liste
- **GameMenuFrame** — liste
- **MailFrame** — liste
- **OpenMailFrame** — liste
- **DressUpFrame** — liste
- **TradeFrame** — liste
- **TaxiFrame** — liste
- **GossipFrame** — liste
- **QuestFrame** — liste
- **LootFrame** — liste
- **BankFrame** — liste
- **PVEFrame** — liste
- **PVPFrame** — liste
- **GuildFrame** — liste
- **ItemTextFrame** — liste
- **TabardFrame** — liste
- **PetStableFrame** — liste
- **MacroFrame** — liste
- **KeyBindingFrame** — liste
- **AuctionHouseFrame** — liste
- **ProfessionsFrame** — liste
- **EncounterJournal** — liste
- **AchievementFrame** — liste
- **CalendarFrame** — liste
- **CollectionsJournal** — liste
- **AddonList** — liste
- **HelpFrame** — liste
- **ChannelFrame** — liste
- **RaidParentFrame** — liste
- **CommunitiesFrame** — liste
- **WorldMapFrame** — liste
- **ReadyCheckFrame** — liste
- **StaticPopup1** — liste
- **StaticPopup2** — liste
- **StaticPopup3** — liste
- **StaticPopup4** — liste
- **DropDownList1** — liste
- **DropDownList2** — liste
- **DropDownList3** — liste

## Interface épurée

Moins d'encombrement et un accès direct à des réglages Blizzard. Tout réglage Blizzard changé ici est rendu quand tu coupes l'option.

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

> Hors combat seulement : ce client ne peut pas exécuter le code sécurisé qu'un menu radial demande en combat. En combat, la touche ne fait rien.

- **Touche (ex. SHIFT-Q)** — zone de texte
- **Disposition** — liste, défaut **Anneau**
- **Rayon de l'anneau** — curseur, défaut **90**, 50 – 200, pas 5
- **Taille des icônes** — curseur, défaut **36**, 20 – 64, pas 2
- **Couleur de sélection** — couleur, défaut **#FFD100**
- **Nom de l'entrée survolée** — case, défaut **cochée**

### Entrées

> Une par ligne : spell:ID, item:ID, macro:Nom, mount:ID, mount:0, marker:0-8 (16 au plus). Ou prenez un sort, objet, macro ou monture sur le curseur et cliquez le bouton ci-dessous.

> menu:2 ouvre la palette 2 en sous-menu : survolez l'entrée un instant. Une palette sans touche ne sert que de sous-menu.

- **Entrées** — zone de texte
- **Ajouter ce qui est sur le curseur** — bouton

### Palette 2

- **Touche (ex. SHIFT-Q)** — zone de texte
- **Entrées** — zone de texte
- **Ajouter ce qui est sur le curseur** — bouton

### Palette 3

- **Touche (ex. SHIFT-Q)** — zone de texte
- **Entrées** — zone de texte
- **Ajouter ce qui est sur le curseur** — bouton

### Palette 4

- **Touche (ex. SHIFT-Q)** — zone de texte
- **Entrées** — zone de texte
- **Ajouter ce qui est sur le curseur** — bouton

## Minimap AeonUI

Minimap carrée (ou ronde) à la taille voulue, bordure au thème, nom de zone et coordonnées, zoom à la molette, boutons d'addons regroupés en rangée sous la carte. Déplaçable avec /aeon unlock.

> Le décor Blizzard de la minimap revient après un /reload une fois ce module coupé.

- **Taille** — curseur, défaut **180**, 100 – 400, pas 2
- **Carte carrée** — case, défaut **cochée**
- **Cacher le décor Blizzard (bordure, boussole, horloge, boutons de zoom)** — case, défaut **cochée**
- **Nom de zone au-dessus de la carte** — case, défaut **cochée**
- **Coordonnées sous la carte** — case, défaut **décochée**
- **Affichage des coordonnées** — liste, défaut **Rangée sous la carte, toujours**
- **Décimales des coordonnées** — curseur, défaut **1**, 0 – 2, pas 1
- **Images par seconde et latence sous la carte** — case, défaut **décochée**
- **Difficulté d'instance compacte (« 5 », « 10H »)** — case, défaut **décochée**
- **La molette zoome** — case, défaut **cochée**
- **Boutons d'addons** — liste, défaut **Un bouton dans la carte**
- **Taille des boutons d'addons** — curseur, défaut **24**, 16 – 40, pas 1
- **Déverrouiller (déplacer les cadres)** — bouton

## Minuteur d'attaque

Une barre par arme jusqu'à votre prochaine attaque automatique. Demande l'événement PLAYER_SWING du client.

> Ce client ne signale pas les coups d'arme (pas de C_SwingTimer) : le module reste inactif.

- **Main droite** — case, défaut **cochée**
- **Main gauche** — case, défaut **cochée**
- **Distance** — case, défaut **cochée**
- **Temps restant avant le coup** — case, défaut **cochée**
- **Étiquette de l'arme sur la barre** — case, défaut **décochée**
- **Atténuer la barre quand la cible est hors de portée** — case, défaut **cochée**
- **Opacité hors de portée** — curseur, défaut **0.35**, 0.1 – 0.9, pas 0.05
- **Orientation** — liste, défaut **Horizontale**
- **Longueur** — curseur, défaut **200**, 60 – 400, pas 2
- **Épaisseur** — curseur, défaut **10**, 4 – 30, pas 1
- **Couleur de la barre** — couleur, défaut **#D8D8D8**
- **Couleur de la main gauche** — couleur, défaut **#99BFF2**
- **Couleur de la distance** — couleur, défaut **#8CD872**
- **Couleur quand une attaque au prochain coup est en file** — couleur, défaut **#FF8C19**

### Visibilité

- **Afficher quand** — liste, défaut **Toutes les conditions sont remplies**
- **En combat** — liste, défaut **Oui**
- **En groupe** — liste, défaut **Indifférent**
- **En raid** — liste, défaut **Indifférent**
- **En instance** — liste, défaut **Indifférent**
- **Sur une monture** — liste, défaut **Indifférent**
- **Avec une cible** — liste, défaut **Indifférent**
- **Au survol seulement** — case, défaut **décochée**

## Panneaux de données

Bandeaux d'informations libres sur les movers : coordonnées, quêtes, régénération, vitesse, DPS et les textes de la barre du haut.

> Chaque panneau est découpé en emplacements égaux. Choisis un texte par emplacement ; déplace les panneaux en mode déverrouillé.

> Maj + glisser un emplacement sur un autre (tout panneau) échange leurs textes. Un panneau à un emplacement fait un bloc libre.

- **Déverrouiller / verrouiller les cadres mobiles** — bouton
- **Nombre de panneaux** — curseur, défaut **6**, 1 – 12, pas 1
- **Panneau à régler** — liste, défaut **Panneau 1**
- **Afficher ce panneau** — case, défaut **cochée**
- **Largeur** — curseur, défaut **360**, 60 – 1200, pas 10
- **Hauteur** — curseur, défaut **22**, 14 – 40, pas 1
- **Emplacements** — curseur, défaut **4**, 1 – 10, pas 1
- **Opacité du fond** — curseur, défaut **0.75**, 0 – 1, pas 0.05
- **Emplacement 1** — liste, défaut **Coordonnées**
- **Emplacement 2** — liste, défaut **Vitesse de déplacement**
- **Emplacement 3** — liste, défaut **Régénération de mana (par 5 s)**
- **Emplacement 4** — liste, défaut **Quêtes**
- **Emplacement 5** — liste, défaut **Aucun**
- **Emplacement 6** — liste, défaut **Aucun**
- **Emplacement 7** — liste, défaut **Aucun**
- **Emplacement 8** — liste, défaut **Aucun**
- **Emplacement 9** — liste, défaut **Aucun**
- **Emplacement 10** — liste, défaut **Aucun**

### Visibilité

- **Afficher quand** — liste, défaut **Toutes les conditions sont remplies**
- **En combat** — liste, défaut **Indifférent**
- **En groupe** — liste, défaut **Indifférent**
- **En raid** — liste, défaut **Indifférent**
- **Sur une monture** — liste, défaut **Indifférent**
- **Avec une cible** — liste, défaut **Indifférent**
- **Au survol seulement** — case, défaut **décochée**

## Plaques de nom AeonUI

Remplace l'habillage Blizzard des plaques de nom par des barres AeonUI : vie (couleurs de réaction, de classe, de menace), nom, niveau, barre d'incantation avec icône, marqueur de raid, débuffs, surbrillance de la cible. Compatible avec le module des chevrons de cible.

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
- **Barre d'incantation : cible du sort** — case, défaut **cochée**
- **Barre d'incantation colorée quand ton interruption est prête** — case, défaut **cochée**
  - **Couleur « interruption prête »** — couleur, défaut **#33D859**
- **Débuffs au-dessus de la plaque** — case, défaut **cochée**
- **Buffs aussi (ligne au-dessus des débuffs)** — case, défaut **cochée**
- **Taille des icônes d'auras** — curseur, défaut **18**, 12 – 32, pas 1
- **Filtre des débuffs** — liste, défaut **Les miens**
- **Barre de vie sur les plaques alliées (nom seul sinon)** — case, défaut **décochée**
- **Plaques sur les PNJ alliés** — case, défaut **cochée**
- **Plaques sur les familiers et gardiens** — case, défaut **cochée**
- **Portée des plaques (mètres)** — curseur, défaut **60**, 20 – 60, pas 5
- **Masquer les noms flottants Blizzard (aucun nom au-delà de la portée des plaques)** — case, défaut **décochée**
- **Surbrillance de la cible (bordure d'accent, les autres atténuées)** — case, défaut **cochée**
- **Couleur de menace en combat (rouge = agro sur toi)** — case, défaut **cochée**
- **Lire la menace en tant que** — liste, défaut **Auto**
  - **Tank : agro tenue** — couleur, défaut **#33BF4C**
  - **Tank : agro en train de partir** — couleur, défaut **#F28C19**
  - **Tank : agro perdue** — couleur, défaut **#D83333**
  - **Tank : tenue par un autre tank** — couleur, défaut **#8C66E5**
  - **Dégâts ou soigneur : menace élevée** — couleur, défaut **#F2D833**
  - **Dégâts ou soigneur : agro presque prise** — couleur, défaut **#F28C19**
  - **Dégâts ou soigneur : agro prise** — couleur, défaut **#D83333**
- **Points de combo sur la plaque de la cible** — case, défaut **cochée**
- **Contrôle dans un emplacement à part, à droite de la plaque** — case, défaut **cochée**
- **Couleur des ennemis par type (boss, élite, rare, lanceur de sorts)** — case, défaut **décochée**
- **Boss** — couleur, défaut **#A54CE5**
- **Élite** — couleur, défaut **#E57F26**
- **Rare** — couleur, défaut **#BFC6D8**
- **Lanceur de sorts** — couleur, défaut **#4C8CF2**
- **Assombrir les ennemis hors combat** — case, défaut **décochée**
- **Atténuer les ennemis hors de portée d'attaque** — case, défaut **décochée**
- **Opacité hors de portée** — curseur, défaut **0.50**, 0.1 – 0.9, pas 0.05
- **Icône de quête sur les unités liées à une quête en cours** — case, défaut **cochée**
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
  - **Style de lueur** — liste, défaut **Halo pulsé**
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
  - **Style de lueur** — liste, défaut **Halo pulsé**
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
  - **Style de lueur** — liste, défaut **Halo pulsé**
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
  - **Style de lueur** — liste, défaut **Halo pulsé**
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
  - **Style de lueur** — liste, défaut **Halo pulsé**
- **Taille** — curseur, défaut **1.00**, 0.5 – 2, pas 0.05
- **Opacité** — curseur, défaut **1.00**, 0 – 1, pas 0.05
- **Masquer** — case, défaut **décochée**

## Rappels

Hors combat uniquement : te prévient quand un buff de classe manque (seulement pour les sorts que tu connais), quand la durabilité est basse, quand tes sacs sont pleins, ou quand tu as oublié de te camoufler.

### Buffs, formes et familiers

- **Buff de classe manquant (armure, aura, poison, aspect…)** — case, défaut **cochée**
- **Pas en ville ni à l'auberge** — case, défaut **cochée**
- **Prêtre : rappeler la Forme d'Ombre** — case, défaut **décochée**
- **Paladin : rappeler la Fureur vertueuse (tank)** — case, défaut **décochée**
- **Chasseur / démoniste : familier non invoqué** — case, défaut **cochée**
- **Pas « Bien nourri » en donjon et en raid** — case, défaut **décochée**
- **Membres du groupe sans mon buff de groupe** — case, défaut **cochée**
- **Buffs à garder (identifiants : 1234, 5678)** — zone de texte
- **Icône cliquable qui lance le sort manquant (hors combat)** — case, défaut **cochée**
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

> Affiché seulement si le client fournit les données : charges de rez partagées en instance de groupe, affaiblissement sur vous.

- **Charges de rez en combat** — case, défaut **cochée**
- **Verrou Furie sanguinaire / Héroïsme** — case, défaut **cochée**
- **Taille des icônes** — curseur, défaut **36**, 20 – 64, pas 2

## Recherche de groupe

Raccourcis de l'outil de recherche de groupe : inscription en un clic quand ton rôle est évident, et note de candidature mémorisée.

- **S'inscrire automatiquement quand un seul rôle est coché** — case, défaut **cochée**  
  _Maj enfoncée à l'ouverture du dialogue pour s'inscrire à la main._
- **Mémoriser ma note de candidature** — case, défaut **décochée**
- **Note** — zone de texte

## Sacs

Une seule fenêtre pour le sac à dos et les sacs équipés, sur son mover : recherche, tri, niveau d'objet sur l'équipement, objets gris signalés, bordure de qualité, recharges, emplacements libres et or. La banque reste celle de Blizzard.

- **Colonnes** — curseur, défaut **12**, 4 – 24, pas 1
- **Taille des boutons** — curseur, défaut **34**, 24 – 48, pas 1
- **Niveau d'objet sur l'équipement** — case, défaut **cochée**
- **Pièce sur les objets gris (camelote)** — case, défaut **cochée**
- **Flèche sur l'équipement de niveau supérieur** — case, défaut **cochée**
- **Objets récents en tête** — case, défaut **cochée**
- **Objets épinglés, identifiants (toujours en tête)** — zone de texte

### Catégories

- **Disposition** — liste, défaut **Grille unique (ordre des sacs)**
- **Ordre des sections** — zone de texte  
  _Mots : pinned, custom, new, equipment, consumable, tradegoods, quest, recipe, junk, other, empty._
- **Épinglés** — case, défaut **cochée**
- **Récents** — case, défaut **cochée**
- **Équipement** — case, défaut **cochée**
- **Consommables** — case, défaut **cochée**
- **Artisanat** — case, défaut **cochée**
- **Quête** — case, défaut **cochée**
- **Recettes** — case, défaut **cochée**
- **Camelote** — case, défaut **cochée**
- **Groupes libres** — zone de texte  
  _Une ligne par groupe : Potions = 118, 858_
- **Nom de « Épinglés »** — zone de texte
- **Nom de « Récents »** — zone de texte
- **Nom de « Équipement »** — zone de texte
- **Nom de « Consommables »** — zone de texte
- **Nom de « Artisanat »** — zone de texte
- **Nom de « Quête »** — zone de texte
- **Nom de « Recettes »** — zone de texte
- **Nom de « Camelote »** — zone de texte
- **Nom de « Divers »** — zone de texte
- **Nom de « Cases libres »** — zone de texte
- **Déverrouiller / verrouiller les cadres mobiles** — bouton

## Suivi de quêtes AeonUI

Le suivi d'objectifs Blizzard sur un support déplaçable, à la hauteur voulue, en-têtes au thème, replié de lui-même en combat ou en instance.

> Le suivi Blizzard reprend sa place après un /reload une fois ce module coupé.

- **Hauteur** — curseur, défaut **500**, 200 – 1000, pas 10
- **En-têtes au thème (sans fond, police du thème)** — case, défaut **cochée**
- **Taille de police des en-têtes** — curseur, défaut **14**, 10 – 20, pas 1
- **Replier en combat** — case, défaut **décochée**
- **Replier en instance** — case, défaut **décochée**
- **En raid** — liste, défaut **Toujours affiché**
- **Titres et objectifs : police du thème, tailles et couleurs par état** — case, défaut **décochée**
- **Taille des titres de quête** — curseur, défaut **13**, 8 – 20, pas 1
- **Taille des objectifs** — curseur, défaut **12**, 8 – 20, pas 1
- **Couleur des titres** — couleur, défaut **#FFD100**
- **Couleur des objectifs** — couleur, défaut **#CCCCCC**
- **Couleur d'une quête terminée** — couleur, défaut **#3FFF59**
- **Touche d'objet de quête (quête suivie d'abord, ex. G)** — zone de texte
- **Déverrouiller (déplacer les cadres)** — bouton

### Visibilité

- **Afficher quand** — liste, défaut **Toutes les conditions sont remplies**
- **En combat** — liste, défaut **Indifférent**
- **En groupe** — liste, défaut **Indifférent**
- **En raid** — liste, défaut **Indifférent**
- **En instance** — liste, défaut **Indifférent**
- **Sur une monture** — liste, défaut **Indifférent**
- **Avec une cible** — liste, défaut **Indifférent**

## Suivi par ID

Une rangée d'icônes pour les sorts et auras choisis par leur identifiant : aura présente sur toi ou posée par toi sur la cible (durée, stacks), sinon recharge du sort.

> Identifiants séparés par des virgules, dans l'ordre d'affichage (ID visible dans l'infobulle, option de l'Habillage). En combat, le jeu cache souvent les auras : elles peuvent alors apparaître absentes.

- **Sorts et auras suivis (ID)** — zone de texte
- **Taille des icônes** — curseur, défaut **36**, 16 – 64, pas 2
- **Espacement** — curseur, défaut **4**, 0 – 20, pas 1
- **Opacité d'une aura absente** — curseur, défaut **0.35**, 0 – 1, pas 0.05
- **Déverrouiller / verrouiller les cadres mobiles** — bouton

## Utilitaire de raid

Bouton « Raid » sur son mover, visible en groupe : appel prêt, vérification des rôles, compte à rebours, marqueurs de cible et marqueurs au sol.

- **Disposition** — liste, défaut **Bouton et panneau**
- **Afficher** — liste, défaut **En groupe**  
  _En raid, caché si vous n'êtes ni chef ni assistant : le serveur refuse alors marqueurs et appels._
- **Échelle de la bande** — curseur, défaut **1.00**, 0.75 – 1.5, pas 0.05
- **Touche d'ouverture du panneau (ex. CTRL-R)** — zone de texte
- **Compte à rebours 1 (secondes)** — curseur, défaut **5**, 3 – 30, pas 1
- **Touche du compte à rebours 1 (ex. CTRL-F1)** — zone de texte
- **Compte à rebours 2 (secondes)** — curseur, défaut **10**, 3 – 30, pas 1
- **Touche du compte à rebours 2 (ex. CTRL-F1)** — zone de texte
- **Compte à rebours 3 (secondes)** — curseur, défaut **15**, 3 – 30, pas 1
- **Touche du compte à rebours 3 (ex. CTRL-F1)** — zone de texte

> /aeon pull [secondes] lance un compte à rebours (le premier par défaut) ; /aeon pull 0 l'annule.

- **Déverrouiller / verrouiller les cadres mobiles** — bouton

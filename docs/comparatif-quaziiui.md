# Comparatif QuaziiUI (QUI) / MuscaUI

Date : 2026-10-12. Références comparées :
- QUI v5.3.1 : retail 12.1, Interface 120100, GPL-3, dans `quazii/addon-qui/QUI-main`.
- MuscaUI : Interface 16001, cible WoW Forever 1.60.1.

Ce document compare des fonctionnalités et des limites du client. Aucun code QUI n'y est repris.

## 0. Périmètre et fiabilité

| Source | Couverture | Fiabilité |
|---|---|---|
| QUI : cœur, UnitFrames, GroupFrames, Nameplates, Bags, Chat | Code lu par extraits et par greps | Bonne |
| QUI : ActionBars, ResourceBars, DamageMeter, Reminders | Fichiers lus en entier (code et pages de réglages) | Bonne |
| QUI : CDM | 39 fichiers lus en entier, dont `cdm_icon_runtime_refresh.lua` (1213 lignes) ; `core/defaults.lua` lu en entier (4524 lignes) | Bonne ; défauts des filtres de conteneur absents de `defaults.lua` (posés ailleurs) |
| QUI : Options (tuiles, assistant, éditeur d'auras, recherche, widgets, profils) | Fichiers lus en entier, dont `framework.lua` (7949 lignes) et `core/migrations.lua` (1697 lignes) ; `search_cache.lua` lu pour son schéma (fichier généré) | Bonne ; pas de reset par réglage, pas de dépendances entre réglages (vérifié) |
| QUI : Debug, Logger, meta | En-têtes | Outillage dev, hors produit |
| MuscaUI : cœur (Core, Config) | Code lu | Bonne |
| MuscaUI : Modules/*.lua et sous-addons `MuscaUI_*` | README, `docs/options.md`, greps `Register`/`secure`/`yieldsTo` | Moyenne : corps des fichiers non lu |

Non vérifié sur Forever : `C_EncounterTimeline`, `C_CooldownViewer`, `C_Secrets`, `CustomAuraButtonTemplate` (slots d'aura sécurisés), `CustomAuraContainerTemplate` (AuraContainer), `C_DeathRecap`, `C_CurveUtil.EvaluateColorValueFromBoolean`, `C_ActionBar.GetActionCooldownDuration` (vu en jeu sur 70124, signature non relue), `C_NamePlateManager`, `UnitGetDetailedHealPrediction` et `CreateUnitHealPredictionCalculator`, les filtres d'aura `BIG_DEFENSIVE`, `EXTERNAL_DEFENSIVE`, `IMPORTANT` et `CROWD_CONTROL`. Ces API sont à passer à l'agent `wow-api` avant toute reprise d'idée qui en dépend. `C_DamageMeter` est vérifié : il est chargé sur Forever (`Blizzard_DamageMeter.toc`, `AllowLoadGameType: standard, camelot`), et ses accesseurs de session sont secrets en combat.

## 1. Synthèse

Légende de pertinence sur Forever : **forte** (le contenu vanilla s'en sert), **partielle** (une partie seulement), **faible** (retail, spé, M+).

| Domaine | QUI | MuscaUI | Écart principal | Pertinence Forever |
|---|---|---|---|---|
| Architecture | Cœur + 11 sous-addons LoadOnDemand, options en LOD | Cœur + 8 sous-addons, options chargées au login | Options en LOD, page « Module Addons » en jeu | Partielle |
| Options | 18 tuiles, index de recherche généré, synonymes, widget modifiable dans les résultats, aperçus intégrés, éditeur d'auras par intention | Catégories, recherche à la volée, mode simple/avancé | Synonymes, saut au widget, aperçus, sélecteur de sorts | Forte (UX) |
| Assistant | 7 pages, chaque étape immédiate | 8 pages, HUD Musca, CVars réversibles | Équivalent ; MuscaUI plus riche | — |
| Profils | AceDB, pins, copie par catégorie, aperçu d'import par catégorie, STRIP des clés invalides, sauvegardes de migration | Perso/spé/contexte, export partiel, export compte, envoi au groupe, miroir de persistance | Pins, aperçu d'import, sauvegarde avant migration | Forte |
| Layout / movers | Layout Mode avec poignées, désancrage, intégrations boss mods | Movers, aimant, ancrage mover à mover, Lock X/Y | Proches ; QUI a les intégrations tierces | Partielle |
| Valeurs secrètes | Taxonomie `@secret-policy`, SafeCall à politiques | `Compat.lua` seul point d'appel, `NS.IsSecret` | Taxonomie documentée | Forte (méthode) |
| UnitFrames | Très complet (absorbs, heal prediction, ticks de canal, Dark Mode, GCD en castbar) | Complet, formats à balises, totems, humeur du familier | Ticks de canal, GCD en castbar, castbar standalone, aperçu dans la page | Forte |
| GroupFrames | Spotlight, targeted spells, overlay de dispel par slots sécurisés, raid buffs, click-cast avancé | En-têtes sécurisés, tanks/assist, dissipation table Classic, click-cast 8 liaisons | Click-cast, spotlight, mode test, raid buffs manquants | Forte |
| Nameplates | 6 types de plaque, presets, kick tick, CVars en file | Plaques ancrées, 5 règles de style, chevrons de cible | Kick tick, presets nommés, types de plaque | Forte |
| ActionBars | Moteur « owned », flyout, GSE, mouseover, buff borders | 8 barres, `/musca kb`, cession à Bartender/Dominos | Proches ; QUI plus fin sur le style | Forte |
| ResourceBars | Liées au Cooldown Manager, indexées par spé | Barres séparées (puissance, combo, mana druide) | QUI peu adapté à Forever | MuscaUI mieux placé |
| Cooldown Manager | ~42 000 lignes autour des viewers Blizzard + conteneurs perso | Réglages par sort, movers des viewers | Composer, conteneurs perso | Faible (dépend du CDM) |
| Damage meter | `C_DamageMeter`, 5 fenêtres, 11 modes, breakout | Absent (laissé à ForeverMeter) | Module entier | API présente, lecture secrète en combat |
| Reminders | Défensive à presser sur timer de boss mod | Rappels de buffs de classe, groupe, durabilité, posture | Objets différents | QUI faible, MuscaUI fort |
| Bags | Catégories, recherche à opérateurs, tri multi-passes, cache multi-perso, banque de guilde | Fenêtre unique, recherche, tri, banque au thème | Écart large | Forte |
| Chat | Remplacement complet de l'affichage, historique persistant, conversations, combat log en onglet | Habillage de ChatFrame, copie, mots-clés, historique au reload | Écart large, coût et risque élevés | Partielle |
| Minimap / infobar / datatexts | Minimap, infobar LDB | TopBar, DataPanels, Minimap, LDB | Équivalent | — |
| Skinning | Très nombreuses frames, panneau personnage à stats | ~50 frames, Gear (ilvl, enchantements) | Proches | Forte |
| QoL | ~40 éléments | Automation, Alerts, Cursor, AFK, RadialMenu, MovableWindows… | Proches ; contenu différent | Forte |
| Donjon / M+ | Timer, keystones, teleports | Absent | Sans objet | Nulle |

## 2. Transverse

### 2.1 Architecture et chargement
QUI :
- Chaque sous-addon est LoadOnDemand, avec un bootstrap qui vérifie le cœur et hérite de son namespace.
- La page « Module Addons » appelle EnableAddOn/DisableAddOn. Elle signale les dépendances (« Dependency Disabled ») et propose un reload.
- QUI_Options (~2,9 Mo) n'est chargé qu'à la première ouverture. Le thème est servi au login par le cœur.
- Les locales compilées s'auto-désactivent.

MuscaUI :
- Sous-addons `MuscaUI_*` chargés au login, désactivables dans la liste d'addons du jeu.
- Registre de modules avec xpcall, `failed`, `secure`, `reloadOnDisable`, `yieldsTo`.
- Options construites page par page à la première ouverture, mais leur code est chargé au login.

Écart : QUI ne charge pas le code des options au login. MuscaUI construit déjà ses pages à la demande ; le gain restant est la mémoire et le temps de compilation. Une page « Modules » existe déjà dans MuscaUI. Il lui manque la gestion des sous-addons eux-mêmes (activer `MuscaUI_Bags` depuis les options), qui demande `C_AddOns.EnableAddOn` et un reload.

### 2.2 Fenêtre d'options
QUI :
- 18 tuiles dans l'ordre : Welcome, General (Profiles, Pinned Globals, Feature Toggles, Import/Export, Third-party, Click-Cast), Unit Frames, Group Frames, Nameplates, Action Bars (7 sous-pages), Auras (7 sous-pages, dont Setup Wizard et Aura Displays), Cooldown Manager, Resource Bars, Minimap & Datatext, Info Bar, Appearance (11 sous-pages), Chat & Tooltips (6), Gameplay (9), Quality of Life (16), Bags, Alts, Help (Help et Tools).
- Une tuile déclare seulement id, icône, sous-pages, routes, alias de recherche, liens « Related » en pied, CTA vers le mover du Layout Mode, et module requis (tuile grisée si le sous-addon manque). Le contenu vient des pages déclaratives de chaque sous-addon.
- Bandeau d'outils : ouvrir le CDM Blizzard, ouvrir l'Edit Mode, lancer le Layout Mode (refusés en combat).
- Fenêtre : taille (poignée), échelle (0,8 à 1,5, appliquée au relâchement), accent (8 préréglages, couleur de classe, faction, personnalisé avec annulation) et langue (11, reload confirmé) mémorisés. Changer d'accent ou de police reconstruit la fenêtre, tuile, sous-page et position restaurées.
- Navigation : fil d'Ariane ; sous-pages en onglets sur plusieurs rangées, construites à la première sélection ; puces de sections allumées selon le défilement ; tuile ramenée dans la vue de la barre latérale.
- Combat : la fenêtre se ferme à `PLAYER_REGEN_DISABLED` (« Settings closed (combat) »), sans réouverture automatique.
- Clavier : Échap ferme, Ctrl+F donne le focus à la recherche.
- Recherche :
  - index de ~4 130 réglages généré hors jeu, en exécutant les pages dans un Lua simulé ; chargé à la première recherche ;
  - un seul index anglais, traduit à l'affichage ; le libellé anglais reste cherchable sur un client localisé ;
  - 2 lettres minimum, délai 0,15 s, normalisation des accents et séparateurs ;
  - score exact / préfixe / contient, pondéré par mots-clés et contexte ; une faute de frappe tolérée ;
  - synonymes bidirectionnels avec pénalité (aura/buff/debuff, bar/castbar, party/group…) ; non traduits ;
  - 30 réglages et 10 pages au plus ;
  - le widget réel est recréé dans la liste de résultats : on modifie la valeur sans quitter la recherche ;
  - un clic ouvre la tuile et la sous-page, fait défiler jusqu'au widget et le fait clignoter.
- Widgets (ligne 28 px, libellé 170 px) : interrupteur pilule (animation réversible en cours de clic), case carrée, curseur, liste déroulante, couleur, champ texte.
  - Curseur : boutons -/+, saisie bornée, Échap restaure ; `onChange` limité à 1 appel par 0,1 s pendant le glissé, ou différé au relâchement avec aperçu.
  - Liste : menu partagé, filtre, groupes repliables, ouverture vers le haut si la place manque.
  - Couleur : annuler restaure la valeur précédente.
- Désactivation avec raison : infobulle au survol, seulement sur la pilule et la case carrée. Contrôle atténué à 0,3, libellé à 0,45.
- Un réglage affiché deux fois (page et résultat de recherche) reste synchronisé.
- Infobulles maison : fondu 0,25 s, désactivables, contenu calculé sous protection.
- Confirmation générique avec mode destructif (bouton d'accord en couleur d'alerte).
- Pins sur tous les widgets sauf le champ texte ; bandes alternées.
- Aperçus intégrés à la page (hauteur fixe par tuile : 110 à 230 px) ; panneau d'aperçu détachable, échelle 0,4 à 1,25.
- Page Modules : pastilles groupées, compteur « X of Y enabled », verrou en combat ; page Module Addons avec dépendances et invite de reload.
- Help : 6 étapes de démarrage, commandes slash, guides par fonctionnalité, 7 fiches de dépannage, ~30 boutons de diagnostic (les dangereux sont marqués).
- Surcharges par instance (damage meter : « Editing Window » Global ou une fenêtre, bouton Override par widget).
- Reset : un seul bouton « Reset to Defaults » en pied de fenêtre. Il appelle le hook de la tuile active, sinon « No reset hook registered for this page ». Pas de reset par réglage, pas de valeur par défaut affichée, pas d'undo hors couleur et Échap du curseur.
- Dépendances : aucune entre réglages, hors désactivation codée dans chaque page. `relatedTo` et « Related » sont de simples liens de navigation.

MuscaUI :
- Catégories Général, Cadres, Combat, Interface, Confort ; liste à gauche avec point d'état vert/gris/orange.
- Recherche à la volée (2 lettres minimum), mode simple/avancé, réinitialiser la page, recharger par bouton macro.
- Aperçus party/raid dans les options de groupe.

Écarts utiles :
- Synonymes de recherche : peu de code, gain direct pour un joueur qui ne connaît pas le vocabulaire.
- Aperçu dans la page pour unit frames, castbar, plaques et barres d'action.
- Saut vers la section exacte depuis un résultat de recherche, avec clignotement du widget.
- Widget modifiable directement dans la liste de résultats.
- Raison affichée sur un réglage désactivé.
- Liens « Related » entre pages voisines, CTA vers le mover de l'élément.
- Fiches de dépannage dans l'aide (frames disparues, erreurs de valeur secrète, conflits d'addons).

### 2.2 bis Éditeur d'auras
QUI a un éditeur commun aux unit frames, group frames, nameplates, cadres de buffs et « Aura Displays » :
- trois types d'élément : bande filtrée (strip), aura suivie (tracked), buff de raid manquant ;
- liste en accordéon avec interrupteur, icône, badge de type ; ajout plafonné à 4 bandes ;
- mode simple : phrase de résumé en langage courant, mise à jour à chaque changement ; champ « What to Show » par intention (tout, les miens, défensifs, dissipables, contrôle, boss, liste blanche, personnalisé) qui écrit les filtres sous-jacents ;
- mode avancé : filtres tri-état, classement par catégorie, liste blanche ou noire, durée max, type de dissipation (dont « les miens » selon la classe), rôles ;
- rendu : icône, carré, barre, teinte de la barre de vie, bordure ; couleur en fin de durée ; lueur pandemic ; clic droit pour annuler ;
- tri : expiration, nom, défensifs d'abord, priorité de debuff, inversé ;
- sélecteur de sorts : recherche, sections (auras actives, grimoire, talents, déjà vus, presets), homonymes groupés avec « ajouter toutes les variantes », résolution sort lancé vers aura.

MuscaUI : listes d'auras partagées entre unit frames, plaques et co-tank, saisies par ID.

Écarts utiles : sélecteur de sorts avec recherche (plus de saisie d'ID), mode simple par intention avec phrase de résumé. Seaux par spé et filtres retail à écarter.

### 2.3 Assistant d'installation
QUI, 7 pages (fenêtre 560x440, compteur « n / 7 », Back/Next, fermer = « Not now ») :
1. Bienvenue.
2. Échelle : actuelle et recommandée ; bouton seulement si l'écart dépasse 0,005.
3. Profil : profil de départ embarqué, ou chaîne collée.
4. Features : CDM et fondu des barres, appliqués en direct.
5. Nameplates : activation (après reload), barres amicales ou nom seul en monde ouvert.
6. Layout Edit Mode : crée ou remplace le layout compte « QUI » ; en cas d'échec, la chaîne est affichée pour un import manuel.
7. Fin : liste des actions appliquées pendant ce passage, bouton Reload.

Ouverture automatique sur installation fraîche ; sur un profil existant, un seul message au login. Échelle, import et layout sont refusés en combat.

MuscaUI, 8 pages : profils de classe, modules, style, disposition Edit Mode, Cooldown Manager, CVars réversibles, HUD Musca, résumé.

Écart : MuscaUI est déjà plus complet. Idées à reprendre : afficher la chaîne Edit Mode à copier quand l'import automatique échoue ; récapitulatif final des seules actions faites pendant ce passage.

### 2.4 Profils, import et export
QUI :
- AceDB + LibDualSpec, profil par spé.
- Préfixes `QUI1:`, `CDM1:`, `NP1:` ; message précis si on colle un profil complet dans l'import nameplate.
- Profils : Reset, Reset All Positions, Factory Reset ; Copy From sans confirmation ; Starter Profile embarqué.
- Garde-fous chiffrés : profondeur 20, 50 000 nœuds, erreurs de schéma plafonnées.
- Validation : types refusés, forme comparée aux défauts, nettoyage itératif sur une copie, bouton STRIP qui retire les clés invalides.
- Aperçu avant import par catégories hiérarchiques, avec import sélectif ; bouton ANALYZE ; aperçu invalidé si la chaîne change ; « Save As Profile ».
- Import sélectif : thème et layout non cochés restaurés tels quels ; nouveaux IDs pour les barres perso importées.
- Pins par réglage : valeur globale + ombre par profil ; un pin est déclaré périmé après 3 échecs ; page « Pinned Globals ». Pins par fonctionnalité (aura displays, group frames).
- Copie d'une catégorie de réglages depuis un autre profil.
- Migrations : pas d'étape par version. Version courante 62, plancher 47. Tout profil sous 62 reçoit un lot unique et idempotent. Sous 47, il est sauvegardé puis remplacé par le profil de départ.
  - Sauvegarde : un slot, rangé dans le profil (`_migrationBackup`, versions et horodatage). Créée seulement s'il y a des données utilisateur. Jamais exportée.
  - Aucun pcall, aucun retour arrière automatique. Une dépendance manquante laisse la version non incrémentée.
  - Passe tardive au login : reprend les positions des barres depuis l'Edit Mode, réessaie s'il n'est pas prêt, n'écrase jamais une position du joueur.
  - `/qui migration status|restore [N]` (restauration puis reload), `/qui miglog [clear]`.
  - Import d'une chaîne sous le plancher refusé avec un message explicite.
- Aucune sauvegarde avant import.

MuscaUI :
- Profils par personnage, par spé, par contexte (world, dungeon, raid, pvp), raccourci clavier par profil.
- `AEON1:` / `AEON2:`, export partiel par modules, export de tout le compte, `Sanitize`/`ClampColors`/`DropNonFinite`.
- Envoi du profil au groupe, avec confirmation avant décompression.
- Migrations v2 à v7 sous pcall, échecs listés par `/musca diag`.
- Persistance de secours (table hôte, CVars miroir) propre à Forever.

Écarts utiles :
- Aperçu d'import avec cases par module : MuscaUI a déjà l'export partiel, l'import sélectif est la moitié manquante.
- Sauvegarde du profil avant migration, avec le pcall existant : en cas d'échec, restauration automatique et version non incrémentée. QUI sauvegarde mais ne restaure qu'à la main.
- Garde-fous chiffrés (profondeur, nombre de nœuds) dans `Sanitize`, si absents.
- Rapport de nettoyage à l'import (clés retirées), comme le bouton STRIP.
- Import sélectif : garder le thème et la disposition locaux quand ils ne sont pas cochés.
- Sauvegarde avant import : QUI ne la fait pas ; MuscaUI pourrait la faire avec le même slot que la migration.
- Pins : utile si les joueurs changent souvent de profil ; à décider.

MuscaUI a en plus : profils par contexte, envoi au groupe, export du compte, persistance de secours.

### 2.5 Mode disposition
QUI : barre d'outils, grille, snap, poignées (clic droit réglages, Shift redimension, clic milieu désancrage), save/discard, suspension en combat, gardes contre l'Edit Mode, intégration BigWigs, DandersFrames, AbilityTimeline.

MuscaUI : calques glissés, aimant 8 px, lignes guides, flèches 1/10 px, clic droit vers la page du module, ancrage mover à mover avec détection de cycle, Lock X/Y, `fallback`, `pin`, `grow`, enregistrer/annuler.

Écart : MuscaUI est au niveau, et plus riche sur l'ancrage. Il manque le redimensionnement au mover (Shift + glisser) et les movers pour les addons tiers (DBM/BigWigs sont placés par `AddonPlacements`, sans mover).

### 2.6 Valeurs secrètes
QUI :
- Chaque endroit qui touche une valeur possiblement secrète porte un marqueur `@secret-policy: <règle>`. Règles : collapse-only, reject-secret-value, reject-secret-ids, sink-passthrough, defer-until-readable, keep-visible-when-unknown, shadow-state, report-secret-detected, readable-only-scan, zero-degrade, opaque-value-present.
- Le « rulebook » est en tête de `QUI_Nameplates/nameplates/shared.lua`.
- Logique tri-état (vrai, faux, inconnu) dans Reminders et la recherche des sacs.

MuscaUI : `Compat.lua` est le seul fichier qui appelle des API à risque ; `NS.IsSecret` ; les modules passent par `NS.*`.

Écart : la méthode d'MuscaUI (un seul point d'appel) est plus stricte. La taxonomie de QUI apporte la documentation de la décision à chaque site d'appel. Elle se reprend sous forme de convention de commentaire, sans code.

## 3. Modules

### 3.1 Unit frames
QUI a, et MuscaUI n'a pas (d'après la doc MuscaUI) :
- ticks de canal (table statique, calibration par combat log désactivée dans QUI) ;
- GCD affiché dans la castbar du joueur ;
- castbar joueur standalone, active même sans unit frames ;
- castbar de test (sort fictif) et mode preview par unité ;
- Dark Mode global et surcharges « Color ALL … Text » ;
- second overlay d'absorb quand l'absorb dépasse la barre ;
- texte de stance/forme avec icône ;
- ToT inline sur la frame cible ;
- surbrillance de la frame boss ciblée et fondu hors de portée des boss ;
- intégration Clique (`ClickCastFrames`).

MuscaUI a, et QUI n'a pas : balises de texte libres (`[cur] [max] [perc] [missing] [status] [name] [level]`), totems cliquables, humeur du familier de chasseur, castbar colorée quand l'interruption est prête, zone de latence, listes d'auras partagées avec plaques et co-tank, lueur sur contrôles.

Pertinence Forever : forte. Les ticks de canal (Drain Life, Arcane Missiles, Blizzard, Mind Flay) servent en vanilla ; la table statique suffit, le combat log est interdit.

### 3.2 Group frames
QUI a, et MuscaUI n'a pas :
- dimensions par taille de raid (6-15, 16-25, 26-40) ;
- spotlight (en-tête séparé tanks/healers) ;
- party target frames ;
- targeted spells (sort ennemi qui vise un membre, retrouvé par empreinte depuis les nameplates) ;
- missing raid buffs et fenêtre de rappel de buffs de raid ;
- overlay de dispel par slots d'aura sécurisés : le moteur montre le slot, l'addon ne lit jamais le type secret ;
- modes de rendu d'aura : icône, carré, barre, teinte de la barre de vie, bordure ;
- click-cast avancé : molette, touches clavier au survol, types cible/focus/assist/menu/ping, « Smart Resurrection », filtre ami/ennemi, tooltip des liaisons, application aux autres frames ;
- mode test avec frames factices ;
- throttle par famille d'événement, budget « heavy » par frame.

MuscaUI a, et QUI n'a pas : cadres tanks et assistants principaux, cadres boss alliés, CoTank, sorts suivis par coin avec préréglage de classe.

Pertinence Forever : forte, sauf spé/loadout, Mythic, Bleed/Enrage, buffs Evoker/Skyfury. Missing raid buffs en version vanilla (Fortitude, Arcane Intellect, Mark of the Wild, Blessings) recoupe Reminders d'MuscaUI. Les slots d'aura sécurisés sont à vérifier sur Forever.

### 3.3 Nameplates
QUI a, et MuscaUI n'a pas :
- 6 types de plaque avec réglages complets chacun (familier, amical, boss/élite, mineur, joueur ennemi, PNJ ennemi) ;
- modes normal / simplified / nameonly / off ;
- priorité de couleur sur 8 niveaux, assombrissement hors combat ;
- indicateur d'execute (seuil manuel) ;
- kick tick : repère sur la castbar quand votre interruption sera prête ;
- résumé d'interruption (qui a interrompu) ;
- hitbox réglable et clic à travers ;
- presets (default, compact, chunky) et profils nommés assignables par rôle ;
- CVars de plaque écrites en file hors combat.

MuscaUI a, et QUI n'a pas : règles de style conditionnelles (5 règles, première qui correspond), chevrons de cible, masquage des noms flottants, plaques sur familiers et gardiens jusqu'à 60 yards.

Pertinence Forever : forte. Le kick tick sert à tout interrupteur vanilla (Kick, Pummel, Shield Bash, Earth Shock, Counterspell). Les règles d'MuscaUI couvrent déjà une bonne part des types de plaque de QUI.

### 3.4 Action bars
QUI :
- Moteur « owned » : boutons sécurisés propres ; barres Blizzard reparentées vers un cadre caché.
- Barres 1 à 8 (7 et 8 désactivées par défaut), familier, posture, micro-menu, sacs ; pagination de la barre 1 par state driver.
- Barres annexes : totems (4 emplacements, clic droit pour détruire), marqueurs de raid (cible et sol) avec bande de chef (ready check, role poll, pull 10 s), Extra Action et Zone Ability sur movers.
- Remplacement des cadres de buffs/debuffs du joueur : 40 icônes, croissance vers la gauche, clic droit pour annuler.
- Style : zoom, fond, gloss, flash, bordures, textures ; textes keybind, macro, quantité, cooldown, chacun réglable.
- Indicateurs : hors de portée en rouge, manque de mana en bleu, inutilisable en gris.
- Cooldowns : charges, perte de contrôle, objets Duration avec repli sur l'ancienne fonction Blizzard.
- Emplacements vides cachés ; aperçu à 30 % pendant un glisser.
- Fondu : par contexte, lien entre barres 1-8, maintien en combat et grimoire ouvert ; « Always Show » pour 14 éléments ; mouseover.
- Lueur de proc : Button, Pixel ou AutoCast.
- Keybind par LibKeyBound, déclenchement à l'appui, verrou des boutons par CVar.
- Pages : générale, une par barre (layout, visuel, textes, visibilité, « Apply to All Bars », « Copy Settings From »), aperçu en direct.
- Taint : boutons retirés des registres de dispatch Blizzard, ajout auto de sort à la barre neutralisé, layout en combat par attributs seulement.
- Performance : une seule frame OnUpdate (0,033 s en combat, 0,2 s hors combat), seuls les emplacements « sales » sont relus.
- Retail seulement : flyout propre, Rotation Assist, GSE.

MuscaUI : 8 barres, pagination par attribute driver, `/musca kb`, micro-menu, sacs, posture, totems, familier en 4 modes, style des boutons, cession à Bartender4/Dominos.

Écarts :
- couleur distincte pour le manque de mana ;
- gloss et fond des boutons ;
- « Copy Settings From » et « Apply to All Bars » ;
- barre de marqueurs de raid avec bande de chef (MuscaUI a les marqueurs dans RaidUtility) ;
- remplacement des cadres de buffs du joueur ;
- aperçu à 30 % des emplacements vides pendant un glisser.

À vérifier sur Forever : `C_ActionBar.GetActionCooldownDuration` (déjà vu en jeu sur 70124) et noms des barres Blizzard (`MainActionBar`, `MultiBar5-7`, `BagsBar`, `MicroMenuContainer`).

### 3.5 Resource bars
QUI :
- Barre primaire et secondaire, ancre commune, permutation possible.
- Primaire choisie par spé ou forme de druide. Sans spé, `GetSpecialization()` rend nil et la primaire retombe sur Mana, même pour guerrier ou voleur. La secondaire n'existe pas sans spé.
- Trackers reconstitués à partir des sorts lancés (Maelstrom Weapon, Tip of the Spear, Whirlwind, Renewing Mist, Stagger) : retail.
- Ticks par point (combo, shards, holy power) ; 3 repères de seuil par spé, lisibles même avec un max secret.
- Verrou de largeur sur les viewers du CDM (actif par défaut) ; sans CDM, la barre se cache 3 s puis prend 200 px.
- Visibilité : toujours, en combat, cible hostile.
- Couleurs pour 25 ressources, sans éditeur dans les options.
- Aperçu en direct : cycle simulé de 10 s.
- Performance : mise à jour limitée à 0,016 s ; runes et essence à 50 ms.

MuscaUI : barres de vie, puissance, combo, mana de druide, chacune sur son mover, seuils colorés, repères en %.

Verdict : MuscaUI est mieux adapté à Forever. À reprendre seulement : l'aperçu animé dans la page d'options, les repères de seuil si absents.

### 3.6 Cooldown Manager
QUI :
- Reprise des viewers Blizzard (Essential, Utility, BuffIcon, BuffBar) : frames Blizzard réclamées et posées dans les conteneurs QUI, sinon icônes propres ; frames inutiles parquées hors écran.
- Conteneurs : essential (12/10/10 icônes par rangée, 39 px), utility (7/6/6, 30 px, ancrable sous essential), buff (30 px, centré), barres suivies (215x25), barres perso (icône ou barre, 6 icônes par défaut).
- Jusqu'à 3 rangées par conteneur, bord de croissance fixe, layout dynamique qui compacte les trous ; affichage toujours, actif ou en combat.
- Icônes : décompte natif, stacks (aura, charges, objet), désaturation en cooldown sauf s'il reste une charge, grisage des inactifs, teinte hors portée ou inutilisable, icône cliquable sécurisée, infobulle, qualité de métier.
- Entrées perso : sort, objet, bijou, emplacement, consommable, macro ; placement avant, après ou à une position.
- Barres : remplissage par Duration native, texte de durée, nom et stacks, couleur de classe ou par sort, mode inactif (masqué, fondu, toujours).
- Effets : lueur (Pixel, Autocast, Button, Flash, Hammer, Proc), lueur pandemic par courbe, animation pop des buffs, surbrillance à la pression, swipe coloré mémorisé contre les autres addons.
- Composer : grille réordonnable par glisser-déposer, ajout par clic droit et recherche, entrées dormantes (sort inconnu gardé en réserve), réglages par sort, alertes son/TTS (prêt, en cooldown, aura gagnée ou perdue).
- Visibilité HUD commune à 6 éléments (CDM, trackers, auras, UF, barres d'action, chat) : monture, vol, véhicule, combat ; fondu quand la santé est sous 100 %, calculé par courbe sans lire la valeur.
- Charges max mémorisées hors combat ; liste des raciaux par race ; objets utilisables (bijoux, sacs).
- Combat : layout, mutations et snapshot du catalogue Blizzard différés.
- Rafraîchissement à l'exécution, par événement :
  - 5 files différées en combat (barres, sorts, usabilité, objets, catalogue), vidées après 0,3 s par un OnUpdate ;
  - `UNIT_AURA` : texte des stacks et portée des auras ; changement de cible, focus ou cible douce : portée recalculée ;
  - fin de cast ou de canalisation : unité secrète traitée comme `player`, sort secret donc rafraîchissement global ;
  - cooldown modifié : catégorie GCD ou illisible, seuls les cooldowns sont repris ; charge vide ou secrète, tout est repris ;
  - équipement : bijoux (emplacements 13 et 14) seulement ; sacs : objets ; totems ; macros : cache seulement ;
  - sortie de combat : rafraîchissement complet en attente et attributs sécurisés appliqués ;
  - ID de sort secret ramené à nil, catégorie de recharge secrète traitée comme illisible.
- Défauts (`core/defaults.lua`) :
  - swipes : radial, recharge, bords, buffs sur icônes, phase d'aura activés ; GCD et swipe des barres de buff désactivés ;
  - lueur perso essential et utility : Pixel, jaune, 14 lignes, épaisseur 2, vitesse 0,25 ; lueur pandemic buffs et debuffs activée ;
  - surbrillance au cast désactivée (blanc, 0,4 s) ; effets Blizzard gardés ;
  - raccourcis affichés sur les viewers (taille 12, jaune, coin haut gauche) mais masqués sur les barres perso ;
  - viewers : essential 50 px, utility 42 px, chevauchement -11 ; aide de rotation activée ;
  - barre perso livrée « Trinket & Pot », désactivée : objet 224022, GCD masqué, charges d'objet, état actif en lueur ;
  - aucun défaut de filtre pour les conteneurs CDM dans ce fichier (layout dynamique, swipe de recharge, désaturation avec charges : introuvables) ;
  - barre de puissance ancrée sous essential, largeur 236 ; barre secondaire à 10 spés retail.
- Sans CDM Blizzard : seuls les conteneurs autonomes et les barres perso fonctionnent ; le reste est inerte, sans repli. Réglages rangés par « classe-spé ».

Page de réglages d'un conteneur, 6 onglets (Filters et Per-Spec seulement pour les conteneurs perso) :
- Entries : le composer ; bandeau si une barre « par spé » n'a aucune entrée pour la spé courante.
- Appearance :
  - général : mode d'affichage, direction (horizontal/vertical, ou 4 sens pour une barre perso), icônes cliquables, désaturation, grisage des inactifs, ancrage sous essential avec écart (-200 à 200) ;
  - par rangée (3 au plus) : icônes par rangée (0-20), taille (5-80), bordure (0-5) et source de couleur, zoom (0-0,2), espacement (-20 à 20, négatif = chevauchement), décalages X/Y, croissance, opacité, textes de durée et de stacks (taille, police, ancre 9 points, décalage, couleur), forme d'icône (rapport 1 à 2) ;
  - essential : largeur minimale du HUD (100-500, défaut 200) pour les cadres joueur et cible qui s'y ancrent ;
  - barres : hauteur (2-48), largeur (100-400) ou largeur auto depuis l'ancre, texture, espacement, couleur de classe, fond, orientation, sens de remplissage, comportement inactif (masqué, fondu à 0,3, toujours ; emplacement réservé).
- Filters : masquer le GCD, masquer l'inutilisable, seulement en cooldown / hors cooldown / actif (exclusifs), seulement en combat, layout dynamique (exclusif avec icônes cliquables), charges d'objet, swipe de recharge, pas de désaturation s'il reste une charge, qualité d'objet fabriqué.
- Per-Spec : une case « entrées par spé » ; case « Per-Loadout » en haut de page.
- Effects : swipes (radial, GCD, buff, phase d'aura sur icône de cooldown, bords), couleurs d'overlay et de swipe (Blizzard, classe, accent, perso), masquage des effets Blizzard, lueur perso (6 types, couleur, lignes 1-30, épaisseur 1-10, échelle, vitesse, décalages), lueur pandemic buffs et debuffs, état actif des barres perso, effet de pression (off, Blizzard, QUI), surbrillance au cast (0,4 s), bordure « prochain sort recommandé » (Assisted Combat, retail), skin externe et presets de bouton.
- Keybinds : afficher, ancre (4 coins ou centre), taille 6-18, couleur, décalages ; surcharges de raccourci.

Réglages portables sans CDM ni spé : Appearance par rangée, Filters, lueurs, textes de raccourci. Liés au CDM : conteneurs intégrés, masquage des effets Blizzard, effet de pression Blizzard, bordure de recommandation. Liés à la spé : Per-Spec, Per-Loadout, bandeau d'Entries.

MuscaUI : `cooldownmanager` (réglages par sort, lueur, bordure, couleur de barre) et `blizzardframes` (viewers sur movers). `cooldownbars` et `tracker` couvrent les rangées par ID de sort.

Verdict : faible pertinence tant que le Cooldown Manager n'est pas confirmé sur Forever. Le HUD Musca joue ce rôle côté MuscaUI. Idées reprenables sans le CDM :
- composer (ajout par recherche et réordonnancement visuels) pour `cooldownbars` et `tracker`, qui demandent aujourd'hui des ID ;
- désaturation qui tient compte des charges restantes ;
- fondu de HUD quand la santé est sous 100 %, par courbe ;
- entrées dormantes pour les sorts pas encore appris (utile avec les rangs vanilla).

### 3.7 Damage meter
QUI :
- `C_DamageMeter` natif, sans combat log.
- 5 fenêtres au plus, réglages globaux surchargés par fenêtre.
- 11 modes (dégâts, DPS, soins, HPS, absorbs, interruptions, dissipations, dégâts subis, dégâts évitables, morts, dégâts ennemis subis).
- Segments : en cours, global, 20 derniers.
- 40 lignes recyclées, ligne du joueur épinglée.
- Infobulle, détail par sort, fenêtre détachée « breakout » à 5 panneaux (joueurs, segments, sorts, cibles, comparaison).
- Récapitulatif de mort par `C_DeathRecap`.
- Rafraîchissement 0,5 s en combat, 2 s au repos.
- GUID secrets en combat : joueurs reconnus par icône de spé mise en cache. Nombres secrets ramenés à 0, tris abandonnés sur clé secrète.

MuscaUI : absent, laissé à ForeverMeter (dépendance requise côté CurseForge). DataPanels affiche un DPS secret à largeur fixe.

Verdict : à ne pas reprendre tant que ForeverMeter couvre le besoin. `C_DamageMeter` existe sur Forever, mais ses accesseurs de session sont secrets en combat : un module natif ne pourrait afficher les chiffres qu'à travers des widgets qui acceptent les valeurs secrètes. L'identification par icône de spé ne marche pas sans spé.

### 3.8 Reminders
QUI :
- Un seul usage : « quelle défensive presser ».
- Source : timer de BigWigs, DBM ou `C_EncounterTimeline`, une seule active ; sorts du Dungeon Journal lus en jeu.
- Choix : première défensive prête dans une liste de priorité par spé (LibOpenRaid).
- Réglages : 3 s d'avance, 4 s d'affichage, seulement si tank, ignoré si déjà couvert.
- Sorties : callout, son/TTS, chat, lueur sur le CDM.
- Catalogue des sorts déjà vus (400 au plus).

MuscaUI : rappels de buffs de classe et de groupe, durabilité, sacs pleins, posture, familier, nourriture, buffs personnalisés, icône cliquable.

Verdict : objets différents. Le module QUI dépend de la spé et des saisons retail : faible sur Forever. À retenir : le bus normalisé BigWigs/DBM (une seule source active), utile si MuscaUI veut un jour réagir aux timers de boss ; la liste par spé serait remplacée par une liste par classe.

### 3.9 Bags et banque
QUI a, et MuscaUI n'a pas :
- layout par catégories (Recent, Equipment, Consumables, Trade Goods, Quest, Recipes, Misc, Junk) ;
- coins d'icône configurables (quantité, ilvl, junk, set d'équipement, liaison BoE) avec widget de repli ;
- teinte rouge des objets inutilisables ;
- barre des sacs équipés (glisser pour équiper, Alt+clic pour masquer un sac) ;
- mode sélection et transfert en lot (banque, courrier, échange, marchand) ;
- recherche à opérateurs (`&`, `|`, `~`, `>n`, `a-b`, qualité, emplacement, mots-clés), insensible aux accents ;
- recherche partout, sur tous les personnages, via un cache ;
- compteurs d'objets par personnage dans l'infobulle ;
- tri multi-passes avec reprise, détection de blocage, arrêt en combat ;
- vente des gris avec liste d'exclusions ;
- auto-ouverture selon l'interaction (marchand, courrier, HV, échange, banque) ;
- banque de guilde complète (onglets, droits, journaux) ;
- barre de monnaies en pied.

MuscaUI : fenêtre unique, recherche, tri client, ilvl, gris signalés, bordure de qualité, recharges, places libres et or ; banque au thème.

Pertinence Forever : forte, hors banque de bande de guerre, sac de réactifs, qualité de craft, scrapping. Écart le plus large de tous les modules : compteurs multi-personnages, catégories, recherche à opérateurs, auto-ouverture, banque de guilde.

### 3.10 Chat
QUI : remplacement complet de l'affichage (capture des `CHAT_MSG_*`, store de messages, rendu par `ScrollingMessageFrame` propre), onglets à filtres, conversations de chuchotement par interlocuteur, journal de combat en onglet, historique persistant (5000 lignes, en tranches), copie, URLs et coordonnées cliquables, menu joueur étendu, alerte mots-clés, texte redondant compacté (loot, XP, réputation), sons par canal, barre de boutons.

MuscaUI : habillage des ChatFrame Blizzard, URLs, copie `[c]`, canaux courts, couleur de classe, horodatage, mots-clés avec son, anti-spam, historique au reload (100 lignes par fenêtre), deux fenêtres réorganisables, bulles au thème.

Verdict : l'approche de QUI coûte très cher. Elle doit suivre le lockdown de messagerie, les corps secrets et la restauration de Blizzard. MuscaUI reste sur l'habillage, plus sûr. Petits écarts reprenables : texte redondant compacté, coordonnées cliquables, onglet par interlocuteur.

### 3.11 Minimap, barre d'infos, datatexts
Équivalent fonctionnel. MuscaUI a TopBar, DataPanels (jusqu'à 12 panneaux), menu Voyage, ledger d'or, LDB. QUI a infobar et datatexts LDB, minimap. Rien de notable à reprendre.

### 3.12 Skinning et fiche de personnage
QUI : très nombreuses frames, panneau personnage avec stats sensibles aux secrets, inspection avec ilvl, enchantements et gemmes.

MuscaUI : `skin` (~50 frames, infobulles), `gear` (ilvl par emplacement, enchantements manquants, inspection).

Écart : gemmes sans objet en vanilla. Équivalent sinon.

### 3.13 QoL
QUI : combat timer, lust, brez, consumables, crosshair, curseur, tooltip, vendeur, sons, Blizzard Mover, macros de consommables, masquage d'éléments Blizzard par type d'instance, texte de combat, range utils, incoming casts.

MuscaUI : Automation, Alerts, Cursor, AFK, RadialMenu, MovableWindows, Interface épurée, GroupFinder, RaidUtility, Loot, MovementAlert, AuraBars.

Écart : macros de consommables (bouton qui prend le meilleur consommable en sac), masquage d'éléments Blizzard par type d'instance. MuscaUI a en plus RadialMenu, AFK, GroupFinder, MovementAlert.

### 3.14 Hors objet sur Forever
M+ timer, keystones, teleports de donjon, Skyriding, Prey Tracker, saisons du Dungeon Journal, réglages par spé et par loadout, outillage de debug QUI.

### 3.15 Packs Quazii hors addon
Les dossiers `quazii/cataclysm-classic` et `quazii/classic-era-sod-hardcore` contiennent des chaînes d'export (Details, ElvUI, Plater, WeakAuras). Contenu non décodé. Ce sont les seuls packs proches du contenu Forever. Hunter, Priest et Rogue manquent côté Classic Era.

## 4. Limites Blizzard révélées par QUI

Constats tirés du code QUI (retail 12.1), à confirmer sur Forever :
- `Show` d'une frame protégée est restreint en combat : basculer l'alpha à 0 au lieu de cacher. Test : `C_RestrictedActions.CheckAllowProtectedFunctions`.
- `SetAlphaFromBoolean` affiche un overlay piloté par un booléen secret (non-interruptible, absorb) sans le lire.
- Pourcentage de santé secret : `UnitHealthPercent` avec courbe, formaté côté C par `SetFormattedText("%.0f%%")`. `%d` sur une valeur secrète fait ignorer l'appel.
- Fin de cast décidée par `UnitExists`, pas par le résultat de `UnitCastingInfo`.
- `UnitIsUnit` inutilisable sur la cible d'un caster : identification par élimination (classe, rôle, race, sexe).
- Dispel secret : slots d'aura sécurisés cachés (`CustomAuraButtonTemplate`, `AddDispelTypeTexture`) ; le moteur montre le slot, aucun script dans le sous-arbre, `DenyTaintedAccessWhenAurasAreSecret`.
- `C_Secrets.ShouldAurasBeSecret()` : geler le cache d'auras Lua quand vrai.
- Cooldowns en combat instancié : chiffres secrets, mais `isActive` et `isOnGCD` lisibles.
- `UnitClass` peut renvoyer une valeur secrète (12.1 PTR7).
- `C_ChatInfo.InChatMessagingLockdown` : corps de message secrets, pas de persistance, pas de traitement.
- `C_StringUtil.WrapString` accepte les chaînes secrètes.
- `C_NamePlate.SetNamePlateSize` unique et centré ; `SetStackingBoundsFrame` lit les régions rendues ; `SetFillStyle` réactive le pixel snapping ; `SetNamePlateHitTestInsets` refuse les arguments secrets.
- CVars : écriture différée en combat, rejouée à `PLAYER_REGEN_ENABLED` (MuscaUI le fait déjà).
- Ticks de canal par combat log : désactivés dans QUI (`CHANNEL_TICK_CLEU_SANCTIONED = false`) ; table statique seulement.
- Compte secret (stacks, charges) : envoyé tel quel à une FontString, jamais comparé ni formaté. Alpha du texte piloté par `C_CurveUtil.EvaluateColorValueFromBoolean`.
- Charges en combat : lisibles seulement si déjà connues hors combat ; QUI mémorise les charges max hors combat.
- Portée et usabilité : utilisées seulement si le booléen rendu n'est pas secret ; portée testée contre `target` et `softenemy` seulement.
- `GameTooltip:SetUnitAuraByAuraInstanceID` lève depuis du code teinté : `pcall` obligatoire.
- Arguments secrets d'événements : `UNIT_SPELLCAST_*` (unité traitée comme `player`), `UNIT_AURA` (rafraîchir player, pet, target).
- IDs de sort secrets : jamais utilisés comme clé de table ni publiés.
- `C_Secrets.ShouldAurasBeSecret` vrai : un AuraContainer natif ne peut être ni créé ni modifié.
- Combat : création de frames, attributs sécurisés, libération d'icônes protégées, redimensionnement de barres et lecture du catalogue CDM différés à la sortie de combat.
- D'autres addons écrasent le swipe d'un Cooldown : QUI garde l'état voulu et le repose.
- Détection par présence de méthode (`SetDesaturation`, `GetCountdownFontString`, `EvaluateRemainingPercent`, `C_DurationUtil`, `C_StringUtil`) avec repli : même principe que `Compat.lua`.
- Santé sous 100 % sans lecture : courbe `C_CurveUtil.CreateCurve` passée à `UnitHealthPercent`, résultat appliqué à l'alpha.
- `GetSpecialization()` sans garde casse le choix de ressource quand il rend nil (cas Forever).
- GUID secrets en combat dans le damage meter : identification par icône de spé.
- Fenêtre d'options fermée à l'entrée en combat ; mode disposition refusé en combat.
- Texte d'une FontString parfois secret : ignoré par la recherche par libellé. Géométrie d'une frame parfois secrète : repli sur une taille par défaut.
- Un bouton désactivé ignore `OnClick` mais garde `OnEnter`/`OnLeave` (`SetMotionScriptsWhileDisabled`) : de quoi montrer la raison de la désactivation.
- Langue de l'interface : changement seulement après reload.
- Charge d'un événement de cooldown vide ou secrète : rafraîchir tout, faute de savoir quel sort.

## 5. Ce qu'MuscaUI a et que QUI n'a pas

- Cible Forever : persistance de secours (table hôte, CVars miroir), reload par bouton macro, layout Edit Mode capturé sur 1.60.1.
- Cession automatique à un addon tiers (`yieldsTo`) et module qui revient seul.
- Désinstallation propre, y compris quand l'addon est décoché (CVars rendues à la déconnexion).
- Profils par contexte (world, dungeon, raid, pvp), raccourci clavier par profil, envoi du profil au groupe.
- Visibilité commune à tous les modules (combat, groupe, raid, instance, monture, cible, survol).
- Règles de style des plaques.
- Intégration du HUD Musca-Auras : import du pack de classe, placement, bordure à l'accent.
- Modules absents de QUI : RadialMenu, AFK, CoTank, MovementAlert, GroupFinder, Loot avec jets de groupe, DataPanels multiples, chevrons de cible, `/musca diag` orienté client.

## 6. Écarts les plus pertinents sur Forever

Classés par rapport gain / coût, sans engagement :
1. Bags : compteurs multi-personnages dans l'infobulle, catégories, recherche à opérateurs, auto-ouverture selon l'interaction.
2. Nameplates : kick tick ; résumé d'interruption.
3. Unit frames : ticks de canal (table statique), GCD dans la castbar, aperçu dans la page d'options.
4. Group frames : mode test, missing raid buffs vanilla, click-cast étendu (molette, cible/focus/menu, rez auto).
5. Options : synonymes de recherche, saut vers le widget avec clignotement, widget modifiable dans les résultats, raison affichée sur un réglage désactivé.
6. Éditeur d'auras : sélecteur de sorts avec recherche, mode simple par intention avec phrase de résumé.
7. Profils : sauvegarde avant migration avec restauration automatique sur échec (QUI ne restaure qu'à la main), et avant import ; import sélectif qui garde thème et disposition locaux ; rapport de nettoyage à l'import.
8. Action bars : couleur de manque de mana, « Copy Settings From » et « Apply to All Bars », barre de marqueurs de raid avec bande de chef, remplacement des cadres de buffs du joueur.
9. Tracker / cooldownbars : ajout par recherche et réordonnancement visuels, entrées dormantes, désaturation selon les charges restantes.
10. HUD : fondu quand la santé est sous 100 %, par courbe (API à vérifier).
11. Chat : texte redondant compacté, coordonnées cliquables.
12. Boss mods : bus BigWigs/DBM normalisé, si MuscaUI doit réagir aux timers.
13. Pins de réglages : à décider selon l'usage des profils.

À écarter : Cooldown Manager QUI (sauf idées du point 9), ResourceBars QUI, Reminders QUI, tout ce qui touche spé, loadout, M+, Assisted Combat et contenu retail.

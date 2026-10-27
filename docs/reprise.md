# Reprise du chantier MuscaUI

Date : 2026-10-27. Cible : WoW Forever 1.60.1 (Interface 16001, moteur retail 12.x, Lua 5.1, game type `camelot`).
Point d'entrée pour reprendre sur un autre poste. Rien n'est commité à cette date : tout est dans l'arbre de travail.

## 1. Où est quoi

| Document | Contenu |
|---|---|
| `docs/comparatif-ellesmereui.md` | Les ~750 écarts avec EllesmereUI v9.6.8, un par ligne de tableau. L'avant-dernière cellule donne l'état réel, à jour au 2026-10-27. |
| `docs/reprise-chantier-h.md` | Détail des tickets H #44 à #87 (lots 1 à 7, profil dérivé), tests en jeu à faire, bugs existants non corrigés. |
| `docs/options.md` | Référence des réglages, générée depuis la fenêtre d'options (`tools/generate_options_doc.lua`). Une option affichée seulement selon le client (ex. `keyring` des sacs) n'y figure pas. |
| `docs/guide-testeur.md` | Guide de test en jeu. |
| `docs/comparatif-quaziiui.md` | Ancien comparatif avec QuaziiUI. |

## 2. Lire l'état d'une ligne du comparatif

Chaque ligne finit par `| Chez nous | Valeur |`. Valeur : H = besoin fréquent, M = utile, G = gadget.
Préfixes de la cellule « Chez nous » :
- `fait : <quoi> (Fichier.lua)` : usage couvert ;
- `partiel : <ce qui est fait> ; reste : <ce qui manque>` ;
- `non fait : <raison>` : décision prise (retail, API absente de Forever, valeur secrète, coût L, données ou textures EllesmereUI à recopier, addon tiers) ;
- `non fait : non traité` : jamais décidé, **c'est le vrai reste à faire** ;
- `présent`, `équivalent`, `couvert`, `sans objet`, `n/a`, `retiré` : rien à faire.

Filtrer, depuis la racine du dépôt :
```
grep -n "non fait : non traité" docs/comparatif-ellesmereui.md           # reste à faire
grep -n "| partiel" docs/comparatif-ellesmereui.md | grep "| H |"          # H partiels
grep -c "| fait" docs/comparatif-ellesmereui.md                           # nombre de lignes faites
```

## 3. Décompte (lignes de tableau)

| Valeur | fait | partiel | non fait (raison) | non fait (non traité) |
|---|---|---|---|---|
| H | 25 | 22 | 8 | 0 |
| M | 40 | 169 | 11 | 149 |
| G | 155 | 0 | 160 | 0 |

Hors décompte : les lignes `présent`, `équivalent`, `couvert`, `sans objet`, `n/a`, `retiré`, et les lignes `retail` sans valeur.
Les lignes G sont toutes tranchées. Les H et M ont été implémentées par lots (tickets #35 à #87, lots M1 à M7). Leur état a été relevé dans le code le 2026-10-27 : un agent par zone, grep de `docs/options.md` puis du code.
Les « non fait : non traité » des lignes M n'ont jamais fait l'objet d'une décision : les lots M n'ont pris qu'une partie des lignes M.

## 4. Travail de la dernière session (2026-10-27)

### Intégration Musca Auras et ForeverMeter
Décision : MuscaUI garde ses propres modules d'auras. Musca Auras (fork WeakAuras) reste optionnel : le joueur qui veut le HUD de classe l'installe, et MuscaUI importe le pack sans surcouche.
- `MuscaUI.toc` : `## Dependencies: ForeverMeter` (obligatoire), `## OptionalDeps: LibSharedMedia-3.0, WeakAuras`.
- Le dossier et la globale du fork s'appellent `WeakAuras` (seul `## Title` vaut « Musca Auras »). Ne pas les renommer : `WeakAurasSaved`, les compagnons `WeakAurasOptions`/`Templates`/`Archive` et les auras importées en dépendent.
- HUD (déjà présent avant) : `Config/Install.lua` (`MuscaHud`, `Install.ImportHud` via `WeakAuras.ImportClassPack`, `HUD_OVERRIDES` qui coupe `resourcebars`, `swingtimer`, `gcdbar`). Groupe racine attendu : `"<Classe> (Musca)"`.
- `Config/FirstRun.lua` : sans Musca Auras, l'assistant affiche une note `SETUP_HUD_MISSING` (où le trouver). Clé ajoutée aux 11 locales.
- Menace sans double son : `Modules/ThreatWarning.lua` pose `ForeverMeter.externalWarning` (fonction `SyncForeverMeter`) quand le module est actif, son coché et joueur non tank. Dans le dépôt voisin `../threatMeter/ForeverMeter.lua` (vers la ligne 1010), ForeverMeter ne joue plus son son quand `FM.externalWarning` est vrai.
- Test : `tests/test_lot7.lua`, « menace : ForeverMeter se tait seulement quand MuscaUI peut sonner ».

Contenu des packs de classe Musca Auras : Reminders, Procs, Effects, Resource, Main/Utility, Bars (Cast, Swing). Swing pour Guerrier, Paladin, Chaman, Voleur, Chasseur (distance). Aucune barre de GCD.

### Comparatif
- Toutes les lignes G traitées (155 faites, 160 non faites avec raison).
- État des 417 lignes H et M relevé et écrit dans le comparatif (voir 3).
- Nouvel outil `tools/add_locale_keys.py` (voir 7).

## 5. Reste à faire

### 5.1 Lignes H pas finies
- **Cœur et réglages globaux** — Overrides par spécialisation (« Editing as ») : partiel : variante de spé = profil parent + écart (Core/Database.lua `profileVariants`, `SyncVariants` ; options.md « Variante de spé ») ; reste : valeurs par réglage dans un profil partagé, bordures dorées, « Editing as »
- **Fonctions Forever et qualité de vie** — Junk Items window : activer, Items Shown, Include White Items, Skip Confirmation for White, Excluded Items … : partiel : vente auto des gris, marquage Alt+clic `junkMarked`, pièce sur les gris, `junkGray` (Modules/Automation.lua, MuscaUI_Bags/Bags.lua) ; reste : fenêtre dédiée (Ctrl+clic supprime, exclusions, seuil de places libres)
- **Fonctions Forever et qualité de vie** — Threat Meter : fenêtre (activer, Only With Threat, source Cible/Focus, Ignore Pets, ligne Pull Aggro, titre… : non fait : fenêtre de menace laissée à ForeverMeter (dépendance obligatoire de MuscaUI)
- **Fonctions Forever et qualité de vie** — Secondary Stat Display : partiel : crit, hâte, toucher, puissance, armure, esquive en textes des Panneaux de données (Core/DataTexts.lua `NS.GetStat`) ; reste : fenêtre « Choose Stats », réordonnancement, échelle
- **Cadres d'unité et barres de ressources** — Menace : % de menace sur cible et focus (6 positions dont « hors cadre »), unités, couleur par menace, « af… : partiel : `threatPercent` (% de menace au-dessus du cadre, cible et focus) (UnitFrames.lua, `Elements.UpdateThreatPercent`) ; reste : 6 positions, unités, couleur réglable
- **Cadres de groupe et de raid** — Tailles par palier de raid (10/15/20/25/30/40) : partiel : paliers de raid <=10, <=25, au-delà (`raidTiers`, largeur/hauteur/colonnes) (MuscaUI_GroupFrames/GroupFrames.lua) ; reste : paliers 15/20/30/40, croissance et décalages par palier, bornes réglables
- **Cadres de groupe et de raid** — Position du joueur : défaut / premier / dernier : partiel : `playerPosition` premier/dernier dans le groupe (MuscaUI_GroupFrames/GroupFrames.lua) ; reste : raid, trié par rôle, défaut
- **Cadres de groupe et de raid** — Cibles de groupe : un bouton cible à côté de chaque cadre de groupe, « inclure ma cible », couleur, fond, t… : partiel : cible de chaque membre du groupe `memberTarget`, `memberTargetSide`, `memberTargetWidth` (MuscaUI_GroupFrames/GroupFrames.lua) ; reste : raid, inclure ma cible, couleur, fond, décalages
- **Cadres de groupe et de raid** — Indicateurs multiples placés librement (jusqu'à 20 par spec) : partiel : 8 indicateurs à ancre sur 9 points, `indicators[1..8]` (MuscaUI_GroupFrames/GroupFrames.lua) ; reste : jusqu'à 20 par spé, décalages et taille par indicateur
- **Cadres de groupe et de raid** — Filtres nommés de sorts (10 préréglages : Défensifs, CD de raid, Externes, Soins principaux/secondaires, Of… : partiel : 5 préréglages ajoutés par bouton (soins sur la durée, défensifs, externes, recharges de raid, déplacement) (`INDICATOR_PRESETS`) (MuscaUI_GroupFrames/GroupFrames.lua) ; reste : filtres nommés personnalisés, catalogue de 10, case par sort
- **Cadres de groupe et de raid** — Grille de base : cases cumulables « Non-joueur, Important, Contrôle, Boss, Rôle, Raid, Raid en combat, Diss… : partiel : 5 cases de débuffs cumulatives `debuffGroups` (contrôle, boss, dissipables par moi, pas d'un joueur, avec durée) (MuscaUI_GroupFrames/GroupFrames.lua) ; reste : Important, Raid, Raid en combat, Tous comme cases
- **Gestionnaire de recharges** — Barres propres (cooldowns / utility / buffs) re-dessinées : partiel : 3 barres maison (taille, espacement, icônes par rangée) (Modules/CooldownBars.lua) ; viewers Blizzard laissés à Edit Mode ; reste : croissance, orientation verticale, recapture des icônes Blizzard
- **Gestionnaire de recharges** — Échelle, espacement d'icônes par barre : partiel : taille et espacement par barre maison (CooldownBars.lua `size`, `spacing`) ; viewers : Edit Mode ; reste : échelle et espacement des viewers
- **Gestionnaire de recharges** — Show Keybind + style du texte de raccourci (police, contour, taille, ancre, offsets, fond, bordure, Keep Ke… : partiel : raccourci lu sur nos barres d'action, sur les icônes essentiel et utilitaire : activable, police, taille, ancre (CooldownManager.lua `keybind.*`) ; reste : contour, fond, bordure, décalages, raccourcis hors de nos barres
- **Gestionnaire de recharges** — Cooldown State Effect : partiel : sur un sort, estompé ou caché selon recharge, prêt ou inutilisable, les suivants remontent (CooldownManager.lua `state` : dim, hideCooldown, hideReady, hideUnusable) ; reste : caché hors forme/posture, alpha d'estompe réglable (50 % fixe)
- **Gestionnaire de recharges** — Proc Glow / Active State Glow / Max Charges Glow / CD Ready Glow / Buff Glow : partiel : lueur « prête », « charges max » ou « toujours » par sort (`glow`), lueur de proc (`procGlowStyle`), lueur de buff actif (`buffGlowStyle`), fenêtre après lancement avec lueur (CooldownManager.lua) ; 4 styles seulement (Core/Glow.lua) ; reste : Shape, GCD, Modern WoW, couleur par sort
- **Gestionnaire de recharges** — Audio on Buff Gain / Loss, Audio Effect on CD Ready : partiel : barres maison : son « recharge terminée » au choix ou importé (CooldownBars.lua `sound`, `soundPreset`, `soundFile`) ; reste : sons sur les viewers, gain/perte de buff
- **Gestionnaire de recharges** — Sélecteur : ajouter / remplacer / retirer un sort sur une barre depuis le catalogue : partiel : sélecteur par catégorie (essentiel, utilitaire, buffs, communs et équipement) pour masquer/afficher un sort (CooldownManager.lua `OPT_CDM_EXTRA`) ; barres maison : ajouter/retirer depuis le catalogue (CooldownBars.lua) ; reste : ajouter à une barre Blizzard un sort « non affiché »
- **Barres d'action et sacs** — Paging configurable par barre : états par barre (formes de classe, Maj/Ctrl/Alt, cible amie/hostile) : partiel : pages Alt/Ctrl/Maj de la barre 1 (pageAlt, pageCtrl, pageShift) + paging de forme (formPaging) (ActionBars.lua:1431-1436) ; reste : réglage par barre, cible amie/hostile
- **Barres d'action et sacs** — Coffre de bataillon (Warbank) : onglets, vue consolidée OneWarbank, or de bataillon : partiel : onglets du personnage et du coffre de bataillon quand le client l'expose (Bank.Tabs, Bank.lua:42-61), dépôt automatique (NS.BankAutoDeposit) ; reste : or de bataillon, vue consolidée tout-en-un
- **Chat, minimap, quêtes, barres de données, amis, recherche de groupe** — Éléments Blizzard afficher/cacher individuellement : calendrier, courrier, suivi, ordre d'artisanat, diffic… : partiel : suivi, courrier, horloge, zoom, difficulté affichables un par un (showTracking, showMail, showClock, showZoom, showDifficulty ; ELEMENTS, MinimapFrame.lua:67-76) + échelle (decorScale) ; reste : calendrier, ordre d'artisanat, position de la rangée et décalages
- **Chat, minimap, quêtes, barres de données, amis, recherche de groupe** — Trier les quêtes suivies : ordre du journal, zone, niveau, nom, progression, type ; terminées en haut/bas/m… : partiel : tri journal/niveau/nom/proximité et terminées en haut/bas/mêlées (sortMode, completedPosition, QuestTracker.lua:35-36) ; reste : zone, progression, type, tri secondaire
- **Habillage Blizzard, compteur de dégâts, M+, menu radial** — Fenêtres de compteur (jusqu'à 5), mode par fenêtre : Dégâts, Soins, Dégâts subis, Dégâts évitables, Dégâts … : non fait : compteur laissé à l'addon tiers ForeverMeter ; seuls un texte de données DPS (Core/DataTexts.lua, C_DamageMeter) et la synchro d'alerte de menace (ThreatWarning.lua)
- **Habillage Blizzard, compteur de dégâts, M+, menu radial** — Segments : Actuel / Global / liste des combats passés, synchronisation de la sélection, « Actuel en combat … : non fait : compteur laissé à l'addon tiers ForeverMeter
- **Habillage Blizzard, compteur de dégâts, M+, menu radial** — Détail d'un joueur (breakdown par sort, plus de sorts, survol), infobulle de sorts, détail des morts (récap… : non fait : compteur laissé à l'addon tiers ForeverMeter


### 5.2 Lignes non traitées (aucune décision prise)
Libellés raccourcis : le détail (preuve EllesmereUI, disponibilité Forever) est dans la ligne du comparatif.

**Cœur et réglages globaux**

- [M] Cycle de chevauchement
- [M] Optimiser mes FPS et graphismes / Restaurer
- [M] Visibilité : au repos (en ville / auberge)
- [M] Visibilité : en véhicule
- [M] Couleurs de classe personnalisées
- [M] Couleurs de ressource (puissance) personnalisées
- [M] 23 polices fournies
- [M] « Apply to All Game Text »
- [M] Loadout Manager : échange auto d'ensemble d'équipement et de loadout de talents selon l'instance, la diffic…
- [M] Simple Loot Council : vote du butin de raid synchronisé par messages d'addon

**Fonctions Forever et qualité de vie**

- [M] Classic Spellbook
- [M] Classic Talents
- [M] Simplified Stats : Shorten Equip Lines, Merge Equal Spell Power, Color Stats, Number Color
- [M] Auto Summon Pet + Favorites per Character
- [M] Active Stance, Form, Aspect & Aura icon
- [M] Gathering Skill in Tooltips (+ option Minimap)
- [M] Fade Map While Moving
- [M] Reveal Unexplored Areas (+ couleur de teinte)
- [M] Show Map Markers (jeux : transports, entrées d'instance, points de vol, sorties de zone)
- [M] Gold per Hour Tracker
- [M] Items : Minimum Quality, Show Item Level, Show Item Price, Use Auctionator Prices
- [M] Macro Manager (/euimacros) : éditeur visuel des macros du compte et du personnage (icônes en grille, liste …
- [M] Fishing Key
- [M] Fishing : Reel In With the Key, Bobber Indicator (mover), Apply Lure
- [M] Double-Click to Cast (+ Apply Lure)
- [M] Masquer fenêtre de jets de groupe
- [M] Hide Item Transforms
- [M] Waypoint (/way, /euiway) + Hand-Placed Pin Arrival
- [M] Disable Right Click Targeting
- [M] Target Distance Text
- [M] Equipment Flyout : niveaux d'objet (+ lettres de stats)
- [M] GCD Circle
- [M] Cast Bar Circle
- [M] Potion Ready Alert
- [M] Son + TTS (voix, volume, message)

**Cadres d'unité et barres de ressources**

- [M] Styles « stock » : kits Blizzard, Classic WoW, WoW Forever (art, masques, forme des barres) posés sur les c…
- [M] Surcouche de dissipation sur la barre de vie (opacité, « seulement ce que vous dissipez », icône de type)
- [M] Affichage en grille d'icônes (par ligne, nombre de lignes, max total, forme d'icône, zoom, balayage de duré…
- [M] Filtres de débuffs par catégorie (type, saignement, boss…), mode « tous les critères »
- [M] Barres personnalisées libres (créer N barres de buffs/débuffs, chacune avec ses filtres et son mover)
- [M] Lissage des barres
- [M] Décalage automatique : agrandir la puissance sans ressource de classe, décaler les éléments, masquer la pui…
- [M] Minuteur d'attaque : guide de mouvement (zones GO/STILL pour Tir automatique et baguette, texte d'aide)

**Cadres de groupe et de raid**

- [M] Quickbind : survoler un sort, presser une touche
- [M] Cible conditionnelle : Ami / Ennemi dans la même liaison
- [M] Lier « Déclencher sur appui » (down)
- [M] Effacer le ciblage de sort coincé
- [M] Auto-redimensionnement des icônes d'aura/indicateurs avec la taille du cadre
- [M] Mode compact / mode grille
- [M] Style de bordure du cadre + options (décalage, derrière, rayon des coins)
- [M] Masquer les groupes vides (fermer les trous)
- [M] Ordre personnalisé des groupes
- [M] Utiliser les réglages raid pour le groupe / les familiers / extras
- [M] Remplir avec la vie manquante
- [M] Opacité du remplissage, fond de barre (opacité, couleur, couleur de classe)
- [M] Barre d'absorption dédiée (hauteur, rendu, croissance verticale)
- [M] Réduction de vie max : style, opacité, rendu
- [M] Texte de niveau : position (attaché au nom ou libre), taille, décalages
- [M] Barre de nom en haut (Top Name Bar) : hauteur, diviseur, fond, texte, alignement, position bas
- [M] Texte d'état AFK + taille/position
- [M] Numéros de groupe (raid) : taille, décalages
- [M] Boss alliés : affichage « toujours / soigneurs seulement » ; sort de portée du soigneur (Forever)
- [M] Cadres des familiers : en-tête de familiers groupe/raid ou un familier à côté de son propriétaire ; positio…
- [M] Infobulles : unité au survol, buffs, touche modificateur, réglages
- [M] Ordre personnalisé des buffs par indicateur
- [M] Mode de correspondance : « n'importe quel » / « tous » (conjonction)

**Plaques de nom et rappels**

- [M] Empilement : stacking, espacement, vitesse, marge haute d'écran
- [M] Noms amis non cliquables
- [M] Opacité hors ligne de vue
- [M] Incantations devant les plaques
- [M] Nombre max de débuffs
- [M] Lueur de pandémie
- [M] Sunder Armor (guerriers Forever)
- [M] Coloration par débuff (plaque ou bordure, mes débuffs, bordure extra, lignes sort/combo)
- [M] % de menace et écart de menace sur les plaques (position, texte, couleur, taille)
- [M] Avantages de camp (buff 1229741)

**Gestionnaire de recharges**

- [M] Max Icons (0 = off) + Overflow To
- [M] Keep Buffs in Same Place (barre de buffs)
- [M] Always Show Buffs (placeholders)
- [M] Masquer les items vides / items manquants (potions, pierre de soin)
- [M] Supprimer le GCD (Suppress GCD)
- [M] Mirror Key Presses
- [M] Surbrillance d'attaque en file (queued attack, Heroic Strike/Cleave/Maul/Raptor)
- [M] Out of Range Coloring
- [M] Portée d'application (ce sort / toute la barre / toutes spés)
- [M] Cooldown Swipe : couleur, classe, masquer l'état actif, inverser le swipe, masquer le swipe
- [M] CD Ready Glow « Resource Aware »
- [M] Threshold Text (seuil en secondes, couleur, décimales)
- [M] Desaturate Inactive / Visibility When Missing / Always Show Buff (buffs)
- [M] Stance Bar (caché dans/hors d'une page de posture de la classe)
- [M] Replace with Buff / Buff to CD
- [M] Texte de durée / de stacks / bordure par icône (cog)
- [M] Sous-menu « Potions & Healthstone »
- [M] Suivi de recharge (Cooldowns) et de buff (Buffs), barre à charges (hash lines, teinte de charge partielle)
- [M] Stack Based Bar / ticks aux stacks / seuil de stacks
- [M] Groupes de barres (par spé et globaux), croissance, espacement, nom, auto-ajout, décalage si vide
- [M] Pandemic Glow par barre (+ synchro vers nameplates/toutes barres)
- [M] Mode actif / manquant (MISSING)
- [M] Seulement en combat
- [M] Glow at Stacks (comparaison + valeur)
- [M] Show Glows Only in Combat (global)
- [M] FocusKick (barre épinglée sur la plaque du focus : sort d'interruption, rappel texte, son de cast du focus,…

**Barres d'action et sacs**

- [M] Barres 9 et 10 (boutons EUI propres, pages 2 et 10, raccourcis via Bindings.xml)
- [M] Sens de croissance, orientation verticale, ordre des icônes
- [M] Barre cliquable à travers (click through)
- [M] Afficher à l'ouverture du grimoire
- [M] Basculer une barre par raccourci (Toggle Action Bar)
- [M] Coloration hors de portée (couleur choisie)
- [M] Bordure de couleur d'objet équipé
- [M] Superposition d'XP de quêtes (terminées/incomplètes, zone courante)
- [M] Styles d'affichage : Grille / Liste (une ligne par emplacement, colonnes triables) / Compact (blocs par gro…
- [M] Nom de l'ensemble d'équipement sur les pièces
- [M] Sac par défaut à l'ouverture ; ouvrir avec la fenêtre du personnage
- [M] Diviseur de pile maison
- [M] Monnaies suivies dans le pied de fenêtre (Enabled Currencies)
- [M] Actions rapides (Quick Actions) : Désenchanter, Crochetage, Compréhension (parchemins Forever) sur l'objet …
- [M] Affichage banque : Grille / Liste / Compact
- [M] Regroupement par catégorie, imbrication par extension, masquer les vides quand groupé
- [M] Barre latérale de catégories de banque, masquer les onglets
- [M] File d'attente de transferts (clics droits rapides)

**Chat, minimap, quêtes, barres de données, amis, recherche de groupe**

- [M] Moteur d'affichage propre (cadre de messages à nous, texte Blizzard masqué, liens servis par les zones invi…
- [M] Taille de police et police de la zone de saisie, hauteur de la zone de saisie
- [M] Bouton Défiler vers le bas ancré sur le panneau
- [M] Visibilité (règles combat/groupe/etc.) + opacité de la carte
- [M] Remise à zéro du zoom après N secondes (0-15)
- [M] Rotation de la minimap (CVar rotateMinimap)
- [M] Boutons supplémentaires : Grand Coffre, Amis en ligne, Portails M+, Bouton de groupe (cochables, réordonnab…
- [M] Infobulle Amis (plafond de lignes, afficher les notes), échelle d'infobulle perso
- [M] Infobulle calendrier avec liste des verrous d'instance (sur horloge ou FPS/MS : « Verrous »)
- [M] Annoncer la progression au groupe/instance (jamais en raid)
- [M] Son d'objectif terminé / son de quête terminée (liste de sons dont voix de péon)
- [M] Couleur des objectifs selon progression
- [M] Masquer tous les objectifs
- [M] Liens Wowhead au clic droit (langue du client, aller aux commentaires)
- [M] Bloc Ressources de classe (Supplies : composants/munitions/poisons par classe)
- [M] Mode de visibilité « verrous d'instance » sur l'infobulle d'horloge
- [M] Tuiles « Social UI 12.1 » (carte d'ami : icône de classe, nom, personnage, infos, fond en dégradé pour les …
- [M] Icônes de région (ami d'une autre région)
- [M] Liste enrichie : icônes de spé à la place des icônes classe/rôle, taille d'icône des rôles, couronne du che…
- [M] Annuler la plus ancienne candidature au clic quand la limite est atteinte

**Habillage Blizzard, compteur de dégâts, M+, menu radial**

- [M] Fiche : flyout d'équipement (ilvl, stats en lettres, masquer flèches des emplacements)
- [M] Infobulle : buffs du joueur survolé (position, taille d'icône, par ligne, décalages)
- [M] Historique des sorts lancés : bandeau d'icônes (direction, taille, nombre, animation, visibilité par instan…
- [M] Cacher le compteur Blizzard (`damageMeterEnabled` à 0)
- [M] Types Dps / Hps / Absorbs de `C_DamageMeter`
- [M] Mode « touche basculée » (« Toggle Menu Open », « Toggled Menu Select Action ») + « Menu Cancel Action » (t…
- [M] Détection de touche déjà utilisée (« Key Already Bound »)
- [M] Assignation d'un menu à une spé/classe (« Assign to Spec ») + touche partagée entre menus exclusifs
- [M] Ouvrir au curseur ou à une position fixe (X/Y), échelle

### 5.3 Lignes partielles
Environ 190 lignes M partielles. Chacune dit ce qui reste après « reste : ». Les lister :
`grep -n "| partiel" docs/comparatif-ellesmereui.md`.

### 5.4 Tests en jeu (rien n'est testé en jeu)
Avant chaque essai : `/console scriptErrors 1`, puis `/reload`.
- Tous les points de `docs/reprise-chantier-h.md`, section « Tester en jeu ».
- Menace : un seul son, avec le son MuscaUI coché, puis décoché (ForeverMeter doit alors sonner), puis en tank.
- HUD : assistant sans Musca Auras (note affichée), puis avec (bouton d'import, barres MuscaUI coupées).
- Lignes G : absorption, indicateurs de groupe, barre d'incantation, minuteur d'attaque, manette et cible douce, couleurs du profil dérivé.
- Condition manette sans effet en mode « Au moins une » avec une condition macro sur les barres d'action.
- `GetSpellAuraSecrecy` de 25771 et 6788 : le filtre par ID n'agit que sur les auras NeverSecret.

### 5.5 Points de la section « Points à vérifier » du comparatif
GCD 61304 ou 29515, remplacement d'`AddMessage` du chat, `COMBO_TARGET_CHANGED`, `C_DamageMeter` sur Forever. Voir le début de `docs/comparatif-ellesmereui.md`.

### 5.6 Suivis non corrigés
- ForeverMeter : publier une nouvelle version, avec une entrée `externalWarning` dans `../threatMeter/CHANGELOG.md`.
- `MuscaUI.toc` : Notes en français seulement (les `MuscaUI_*` ont Notes en anglais + `Notes-frFR`).
- Musca Auras ancien, sans `ImportClassPack` : la note de l'assistant dit « installe » au lieu de « mets à jour ».
- Double rappel possible : module Reminders de MuscaUI et rappels du pack de classe Musca Auras.
- `docs/options.md` omet les options conditionnelles au client (générateur lancé sur le client simulé).
- Bugs existants listés dans `docs/reprise-chantier-h.md`, section « Suivis non corrigés ».

## 6. Contraintes du projet
- Licence « All Rights Reserved » : aucun code repris d'EllesmereUI (copie de référence dans `~/Téléchargements/EllesmereUI-v9.6.8`, lecture seule), ni de Musca Auras ou ForeverMeter (GPL).
- Rendu par défaut inchangé : une nouvelle option a pour défaut le comportement actuel.
- Ce qui varie entre clients passe par `Core/Compat.lua` (`NS.*`).
- Pas d'action protégée en combat, pas de lecture ni comparaison de valeur secrète (`NS.IsSecret`).
- Source Blizzard Forever : `~/wow-ui-source/forever/Interface/AddOns/` (`Camelot/` prime sur `Mainline/`).

## 7. Commandes
- Tests (~5 min) : `bash tests/run.sh`. Dernier résultat : 590 ok, 0 échec, `.toc` ok.
- Doc des options : `lua tools/generate_options_doc.lua frFR > $TMPDIR/options.md && command cp -f $TMPDIR/options.md docs/options.md`.
- Clés de traduction : écrire un JSON `{"CLE": {"enUS": "...", "frFR": "...", "deDE": "...", ...}}`, puis `python3 tools/add_locale_keys.py cles.json`. Ajoute la clé aux 11 fichiers `Locale/*.lua`.
- Nouveau test : fichier `tests/test_<sujet>.lua`, enregistré dans `tests/run_tests.lua`.

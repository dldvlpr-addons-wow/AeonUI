# Reprise du chantier des tickets H (#44 à #87)

Date : 2026-10-26. Cible : WoW Forever 1.60.x (Interface 16001, game type `camelot`).

## Contexte
- Un comparatif avec EllesmereUI v9.6.8 se trouve dans `docs/comparatif-ellesmereui.md`. Il a produit 44 issues GitHub, de #44 à #87.
- Chaque ticket a été retravaillé pour faire mieux qu'EllesmereUI. Chacun porte un verdict : garder, réduire, fusionner ou abandonner.
- Issues fermées :
  - abandonnées : #65, #74, #86, #87 ;
  - fusionnées : #63 dans #62, #81 dans #80, #85 dans #84.
- Les 37 tickets ouverts sont implémentés, chacun dans le périmètre de son verdict.
- Nouvelles fonctions activées par défaut, sur décision de l'utilisateur.
- Les brouillons de tickets étaient dans `/tmp/claude-1000/musca-h/tickets/NN.md` (fichier NN = issue NN+43). Ils ne sont pas versionnés. Sur un autre poste, se référer aux issues GitHub.

## État
- Tous les lots sont implémentés et relus par un agent relecteur. Les constats bloquants et importants sont corrigés.
- `bash tests/run.sh` : 488 ok, 0 échec, `.toc` ok.
- `docs/options.md` est régénéré, sans écart avec la sortie du générateur.
- Rien n'est commité : tout est dans l'arbre de travail.
- Rien n'est testé en jeu.

## Contenu par lot
- **Lot 1** (#51, #52, #64) :
  - barres d'enchantement d'arme dans AuraBars (`weaponEnchants`) ;
  - segment de coût en mana sur la barre de puissance (`manaCostPrediction`) ;
  - listes d'auras propres aux plaques, avec `whitelistAnyCaster`.
  - Migration v8 : copie des listes globales vers `modules.nameplateframes.auraLists`.
- **Lot 2** (#53, #54, #55) : `ClickCast.lua` réécrit.
  - En-tête `MuscaUI_ClickCastHeader`, liaisons clavier au survol.
  - Types d'action : sort, macro, objet, bijou 1 et bijou 2.
  - Réglage `unitFrames`.
- **Lot 3** (#76 à #80, #82) :
  - barres révélées pendant un glisser ;
  - `pageAlt`, `pageCtrl` et `pageShift` sur la barre 1 ;
  - `bindText` ;
  - catégorie « special » dans les sacs ;
  - banque : onglets, coffre de bataillon, onglet « Tous », dépôt automatique, recherche et tri.
- **Lot 4** (#83, #84) :
  - éléments de la minimap masqués un par un. Migration v9.
  - tri et filtre des quêtes (`filterZone`, `hideTrivial`), avec `questWatches` par personnage.
- **Lot 5** (#66 à #73, #75 ; #70 réduit) : `CooldownManager.lua` réécrit, `CooldownBars.lua` modifié.
  - Lueurs, bijoux, raccourcis affichés sur les icônes.
  - Clic droit pour réordonner.
- **Lot 6** (#56 à #62) :
  - paliers de raid 10, 25 et 40 (`raidTiers`) ;
  - position du joueur, premier ou dernier, dans un groupe de 5 ;
  - buffs manquants sur les cadres, via une détection unique `NS.MissingBuffs` dans Reminders ;
  - cible de chaque membre en groupe ;
  - 8 indicateurs ;
  - préréglages ;
  - 5 cases de débuffs cumulatives.
  - Migration v10 : les 4 coins deviennent des indicateurs, et la taille de raid passe aux paliers.
- **Lot 7** (#45 à #50) :
  - nouveaux modules `FlightTimer`, `ThreatWarning` et `LootFeed` ;
  - uprank automatique des sorts ;
  - camelote marquée par Alt+clic (`junkMarked`) ;
  - 6 barres de données ;
  - nouveau fichier de test `tests/test_lot7.lua`.
- **#44, profil dérivé** :
  - Une variante = un profil parent plus un écart, liée à une spé.
  - `global.profileVariants[name] = { parent, diff }`, au niveau du compte, jamais exporté.
  - Le profil vivant reste complet dans `profiles[variant]`.
  - L'écart est calculé avec Prune, plus un marqueur `"\001removed"` pour les clés supprimées.
  - Synchronisation : au tick du miroir, avant une bascule de profil, et à `PLAYER_LOGOUT`.
  - Pas de migration v11.

## Fichiers modifiés
- **Core** : `Compat.lua`, `Database.lua`, `Core.lua`, `DataTexts.lua`, `CVars.lua`, `Movers.lua`, `Visibility.lua`.
- **Config** : `Options.lua`, `Install.lua`.
- **Modules** : `AuraBars`, `UnitFrameElements`, `CooldownManager`, `CooldownBars`, `Automation`, `Reminders`, `RadialMenu`, `TopBar`.
  - Nouveaux : `FlightTimer.lua`, `ThreatWarning.lua`, `LootFeed.lua`.
- **MuscaUI_ActionBars** : `ActionBars.lua`.
- **MuscaUI_Bags** : `Bags.lua`, `Bank.lua`.
- **MuscaUI_Chat** : `Chat.lua`.
- **MuscaUI_GroupFrames** : `ClickCast.lua`, `GroupFrames.lua`.
- **MuscaUI_Minimap** : `MinimapFrame.lua`.
- **MuscaUI_Nameplates** : `NamePlateFrames.lua`.
- **MuscaUI_QuestTracker** : `QuestTracker.lua`.
- **MuscaUI_UnitFrames** : `ResourceBars.lua`, `UnitFrames.lua`.
- **Autres** :
  - `MuscaUI.toc` ;
  - les 11 fichiers `Locale/*.lua` ;
  - `tests/*` ;
  - `docs/options.md` ;
  - `docs/comparatif-ellesmereui.md` (nouveau).

## Reste à faire

### 1. Tester en jeu
Avant chaque essai : `/console scriptErrors 1`, puis `/reload`. Faire chaque action hors combat, puis en combat sur une cible hostile.

- **Lot 1** :
  - barres d'enchantement d'arme. Vérifier aussi qu'un enchantement permanent n'est pas affiché par erreur.
  - segment de coût en mana ;
  - listes d'auras des plaques.
- **Lot 2** : click-cast au survol, avec sort, macro, objet et bijou. Vérifier `GetMacroInfo` appelé par nom.
- **Lot 3** :
  - barres révélées pendant un glisser ;
  - pages Alt, Ctrl et Maj (`[mod:]`) ;
  - banque : onglets, coffre de bataillon, tri.
- **Lot 4** :
  - éléments de la minimap ;
  - filtre des quêtes par zone ;
  - plafond de 25 quêtes suivies ;
  - sens d'insertion d'`AddQuestWatch`.
- **Lot 5** :
  - lueurs ;
  - réordonnancement par clic droit ;
  - bijoux ;
  - `CROWD_CONTROL` ;
  - `damageMeterEnabled`.
- **Lot 6** :
  1. Changer de palier de raid hors combat. En combat, le changement doit attendre la fin du combat.
  2. Vérifier que le joueur est dernier dans un groupe de 5.
  3. Vérifier que la vie de la cible d'un membre suit en combat, et que ce bouton n'existe pas en raid.
  4. Vérifier que les icônes de buffs manquants se cachent en combat et s'effacent à la déconnexion d'un membre.
  5. Tester les 8 indicateurs, les préréglages et les cases de débuffs.
  6. Charger un ancien profil pour tester la migration.
- **Lot 7** :
  - minuteur de vol (`PLAYER_CONTROL_LOST`, `UnitOnTaxi`) ;
  - alerte de menace ;
  - flux de butin : l'aperçu reste visible et la police suit le réglage de taille ;
  - uprank ;
  - Alt+clic pour marquer de la camelote ;
  - gain de réputation avec bonus, sur une seule ligne et avec le bon montant.
- **#44** :
  1. Créer une variante pour la spé.
  2. Changer un réglage, puis `/reload`.
  3. Changer le parent : la variante doit suivre.
  4. Utiliser « revenir au parent ».
  5. Supprimer la variante, puis le parent.
  6. Changer de spé.
- **Tickets #35 à #43** : les tests en jeu sont aussi en attente.

### 2. Point à trancher
L'uprank parcourt les emplacements de barre 1 à 180. Le ticket l'excluait, mais les pages de posture et de forme en ont besoin. Le parcours est gardé pour l'instant.

### 3. API non vérifiées dans le source Blizzard
- Identifiants de sorts du catalogue de buffs, repris de Classic 1.x. Un sort inconnu est ignoré sans erreur.
- Globales `FACTION_STANDING_INCREASED_*_BONUS`. Elles sont lues seulement si elles existent.
- Secret de `UnitIsUnit` sur les unités de raid, et de `GetRaidRosterInfo`.

### 4. Suivis non corrigés

**Bugs existants, hors demande :**
- `MuscaUI_Bags/Bank.lua:131` n'a pas `generalOnly`.
- `Modules/AuraBars.lua:76` (`FormatTime`) : une erreur d'arrondi affiche « 9m » au lieu de « 10m ».
- `Reminders.lua` n'écoute pas `WEAPON_ENCHANT_CHANGED`.
- `ActionBars.lua:636-645` duplique `NS.IsSpellOverlayed`.
- `Bags.lua` appelle `C_Item` et `C_Container` directement, hors de Compat. `RestoreButton` ne cache pas `muscaUpgrade`.
- `Elements.UpdatePower` et `ResourceBars` appellent `UnitPower` directement.
- `ChatFrame_AddMessageEventFilter` est déprécié.
- `GroupFinder.lua` est probablement du code mort.
- `C_ClickBindings` passe avant ClickCast.
- `docs/comparatif-quaziiui.md:21` : `C_Secrets` y est noté non vérifié.

**Liés au chantier :**
- Un profil importé ne passe pas par les migrations.
- Toute migration future des profils doit aussi migrer `profileVariants[*].diff`.
- Le miroir CVar stocke chaque variante deux fois (profil complet plus écart). Cela rapproche la limite `MSG_MIRROR_TOO_BIG`.
- Le buff Épines est vérifié par défaut sur chaque membre, ce qui peut afficher beaucoup d'icônes.
- Les icônes de buffs manquants ne se rafraîchissent pas à `SPELLS_CHANGED`.
- Les préréglages d'installation ne règlent que le palier de raid au-delà de 25.
- La vie de la cible d'un membre est relue toutes les 0,25 s par le ticker de portée. Le client n'envoie pas d'événement pour ces unités.
- Le gestionnaire de recharges se met à jour à chaque `UNIT_AURA` : coût à surveiller.
- Un viewer de recharges caché affiche encore ses infobulles.
- Quêtes :
  - l'exemption manuelle d'une quête ne dure que la session ;
  - une fenêtre de 0,2 s reste ouverte autour de `QUEST_WATCH_UPDATE`.
- Le filtre de plaque en affichage manuel passe par `NS.AuraPasses`.
- `LootFeed` n'a pas de test automatique pour l'aperçu ni pour la police.

## Commandes utiles
- Tests : `bash tests/run.sh`.
- Doc des options :
  ```
  lua tools/generate_options_doc.lua frFR > $TMPDIR/options.md && command cp -f $TMPDIR/options.md docs/options.md
  ```
- Source Blizzard Forever : `~/wow-ui-source/forever/Interface/AddOns/`.

# Comparatif EllesmereUI / MuscaUI : ce qui nous manque

Date : 2026-10-26. Références comparées :
- EllesmereUI v9.6.8 : Interface 120000…120105 et 16001 (WoW Forever), 23 addons, environ 700 000 lignes. Copie donnée par l'auteur pour comparaison, dans `~/Téléchargements/EllesmereUI-v9.6.8`.
- MuscaUI : Interface 16001, cible WoW Forever 1.60.1.

Ce document inventorie des fonctionnalités et des limites du client. Aucun code EllesmereUI n'y est repris. Il ne recommande rien : le tri de ce qu'il faut implémenter vient dans une seconde étape.

## 0. Méthode et fiabilité

- Source de l'inventaire : les fichiers d'options d'EllesmereUI (`EllesmereUIOptions/EUI_*_Options.lua`), complétés par les noms et en-têtes des fichiers de chaque module. Un réglage = une fonction.
- Côté MuscaUI : `docs/options.md`, puis grep dans le code.
- Neuf zones, une par section ci-dessous. Les gros fichiers d'implémentation n'ont été lus que par en-têtes et extraits : chaque section se termine par son « Non couvert ».
- Les faits sur le client cités dans les sections « Limites client révélées » viennent de commentaires d'EllesmereUI. Aucun n'a été vérifié en jeu.

Légende des tableaux :
- **Forever ?** : `oui` = code actif sur Forever ; `retail` = absent ou inerte sur Forever (M+, clés, skyriding, talents de héros…) ; `?` = non tranché.
- **Chez nous** : `absent` ou `partiel (ce qui manque)`. Les fonctions présentes à l'identique sont résumées en fin de section.
- **Valeur** pour un joueur : H = besoin réel et fréquent, M = utile, G = gadget ou cosmétique. Cette note est celle de l'agent qui a fait l'inventaire, pas une décision.

## 1. Synthèse

| Zone | H | M | G |
|---|---|---|---|
| 2. Cœur et réglages globaux | 1 | 32 | 42 |
| 3. Fonctions Forever et qualité de vie | 8 | 42 | 31 |
| 4. Cadres d'unité et barres de ressources | 4 | 42 | 49 |
| 5. Cadres de groupe et de raid | 11 | 63 | 37 |
| 6. Plaques de nom et rappels | 1 | 34 | 40 |
| 7. Gestionnaire de recharges | 13 | 47 | 24 |
| 8. Barres d'action et sacs | 8 | 36 | 44 |
| 9. Chat, minimap, quêtes, barres de données, amis, recherche de groupe | 5 | 39 | 43 |
| 10. Habillage Blizzard, compteur de dégâts, M+, menu radial | 4 | 34 | 18 |

Décompte = nombre de lignes de tableau par valeur. Une ligne regroupe parfois plusieurs réglages ; une ligne `retail` est comptée si l'agent lui a donné une valeur.

### Écarts notés H, par zone

**Cœur** : surcharges par spécialisation à l'intérieur d'un profil (nous : un profil entier par spé).

**Forever et qualité de vie** : remplacement auto des rangs de sorts (uprank) ; meilleure récompense de quête ; fenêtre de camelote (nous : vente auto des gris seulement) ; minuteur de vol ; fenêtre de menace et alerte de menace ; flux de butin ; affichage des statistiques secondaires.

**Cadres d'unité et ressources** : étincelle de régénération de mana (règle des 5 secondes) sur les cadres et la barre de ressource, avec prédiction du coût ; % de menace sur cible et focus ; cases d'imprégnation d'arme dans la barre de buffs.

**Cadres de groupe et de raid** :
- click-cast : liaisons clavier au survol, types d'action sort / macro / objet, mode « Cast On » (cadres, survol, les deux) ;
- disposition : tailles par palier de raid (10 à 40), position du joueur (premier / dernier), cibles de groupe à côté de chaque cadre ;
- auras : buffs manquants sur les cadres (nous : rappel personnel), indicateurs librement placés (nous : 4 coins), filtres nommés de sorts, grille de filtres cumulables, tuiles d'icônes de débuffs.

**Plaques** : listes d'inclusion et d'exclusion d'auras par ID de sort.

**Gestionnaire de recharges** :
- barres et mise en page : barres redessinées, visibilité par barre, échelle et espacement par barre, raccourcis affichés sur les icônes ;
- états et effets : effet d'état de recharge, lueurs par événement, état actif personnalisé, sons ;
- contenu des barres : sélecteur de sorts dans le catalogue, bijoux, barres de suivi autonomes, lien buff vers bouton d'action.

**Barres d'action et sacs** :
- barres : afficher pendant un glisser, paging configurable (formes, Maj/Ctrl/Alt, cible) ;
- sacs : marqueur et vente de camelote, texte BoE, sacs spéciaux Forever (carquois, âme, herbes…) ;
- banque : coffre de bataillon, vues tout-en-un, recherche et tri dans la banque.

**Chat, minimap, quêtes, divers** : éléments de la minimap affichés ou cachés un par un ; tri, filtre et suivi automatique des quêtes par zone ; panneau de filtres de la recherche de groupe (disponibilité Forever non tranchée, plusieurs filtres sont du contenu retail).

**Habillage, compteur, radial** : compteur de dégâts (fenêtres par mode, segments, détail par joueur ; `C_DamageMeter` est chargé sur Forever, lecture des champs secrète en combat) ; menu radial utilisable en combat (contredit notre constat `Modules/RadialMenu.lua:6`, non vérifié en jeu).

### Points à vérifier avant tout choix

- Barre de recharge globale : nous utilisons le sort 61304 (`Core/Compat.lua:393`) ; selon EllesmereUI, Forever ne renvoie rien pour lui et il faut 29515.
- Chat : `MuscaUI_Chat/Chat.lua:436-437` remplace `AddMessage` sur les fenêtres Blizzard ; selon EllesmereUI, ce motif contamine le gestionnaire de messages et casse les chuchotements en contenu restreint.
- Combo : aucun de nos fichiers n'écoute `COMBO_TARGET_CHANGED`.
- `docs/comparatif-quaziiui.md:41` : `C_DamageMeter` est chargé sur Forever (`Blizzard_DamageMeter.toc` : `AllowLoadGameType: standard, camelot`).


## 2. Cœur et réglages globaux

Légende : Forever = oui / retail / ? ; Valeur = H / M / G. Chemins EUI relatifs à `EllesmereUI-v9.6.8/`, `EllesmereUIOptions/` abrégé `Opt/`, `EllesmereUI/` abrégé `Core/`.
Chez nous : `docs/options.md` (sections Général, Polices et textures, Modules, Profils, Maintenance) et `Core/`, `Config/`, `Locale/`.

### 1. Général : affichage, boutons, combat, développeur

| Fonction | Ce qu'elle fait | Forever ? | Preuve EUI | Chez nous | Valeur |
|---|---|---|---|---|---|
| Thèmes d'accent nommés (Horde, Alliance, Faction auto, Midnight, Dark, Pixels, EllesmereUI Forever) | Presets d'accent complets, qui retintent aussi l'habillage du panneau | oui | Core/EllesmereUI.lua:37-50 ; Opt/EUI__General_Options.lua:2163 | partiel : préréglages d'accent `aeon`, `bronze`, classe, faction, personnalisé (Core/Media.lua `ACCENT_PRESETS`) ; pas de thème qui change tout le panneau | G |
| Couleur d'accent liée à la classe, bascule classe / perso | Swatch avec choix « couleur de classe » ou custom | oui | Opt/EUI__General_Options.lua:2120-2158 | présent (préréglage « classe ») | - |
| Langue du panneau d'options | Liste 12 entrées (auto, enUS, deDE, frFR, esES, esMX, itIT, ptBR, ruRU, koKR, zhCN, zhTW) ; texte non traduit repli sur anglais | oui | Opt/EUI__General_Options.lua:2228-2275 (langCfg) | présent (liste Langue, 11 fichiers Locale/) | - |
| Boutons EUI du menu Échap : masquer « pause », masquer « unlock », afficher bouton minimap | Choix des boutons ajoutés au GameMenu et bouton minimap propre | oui | Opt/EUI__General_Options.lua:2337-2351 | partiel : bouton dans le GameMenu (Config/Options.lua:1309-1324), non masquable ; aucun bouton minimap propre (ni LibDataBroker launcher) | M |
| Désactiver les icônes de synchro | Cache les icônes de sync de profil dans la liste des modules | oui | Opt/EUI__General_Options.lua:2350-2400 | absent (dépend de la synchro de profil, absente) | G |
| Ancrage par points (Point Anchoring) | Neuf points source, puis point cible, en mode déverrouillé | oui | Opt/EUI__General_Options.lua:2417 ; Core/EUI_UnlockMode_PointAnchors.lua, _PointPicker.lua | partiel : choix de point relatif dans le panneau de coordonnées (Core/Movers.lua `PointChoices`, `Movers:AttachTo`) ; pas de poignées visuelles sur le mover | M |
| Cycle de chevauchement | Molette + modificateur pour parcourir les cadres superposés en mode déverrouillé | oui | Opt/EUI__General_Options.lua:2424 | absent | M |
| Couleurs du mode déverrouillé (lignes, bordure, point) | Couleur des lignes de connexion, bordures, points d'ancrage | oui | Opt/EUI__General_Options.lua:2437-2446 | absent (couleur du calque fixe) | G |
| Distance de caméra max | Slider 1-2.6 de `cameraDistanceMaxZoomFactor` | oui (CVar référencée par Camelot/ControlsOverrides.lua dans le source Forever) | Opt/EUI__General_Options.lua:2455-2460 | partiel : CVar posée seulement à l'assistant de première installation (Config/FirstRun.lua:20), pas de curseur | M |
| Améliorer la qualité d'image (netteté) | Bascule `ResampleAlwaysSharpen` | ? (CVar absente du source Forever lu) | Opt/EUI__General_Options.lua:2462-2468 | absent | G |
| Lancer les sorts à l'appui de la touche | Bascule `ActionButtonUseKeyDown` | oui (CVar présente : Blizzard_FrameXML/SecureTemplates.lua) | Opt/EUI__General_Options.lua:2470-2476 | partiel : lue seulement par RadialMenu/TopBar ; aucun réglage utilisateur | M |
| Tolérance de latence (fenêtre de file de sorts) | Slider `SpellQueueWindow` | oui (C_Spell.GetSpellQueueWindow documentée sur Forever) | Opt/EUI__General_Options.lua:2478-2486 | absent | M |
| Texte de combat flottant : police, taille, activer dégâts / soins / périodiques / familier / absorbs / effets de sort / effets cible, échelle du texte du monde | Police du texte de combat (nécessite reconnexion) et une bascule par type de texte flottant | ? (CVars `_v2` ; EUI filtre par `GetCVarInfo`, Opt/EUI__General_Options.lua:2569) | Opt/EUI__General_Options.lua:2547-2625 ; Opt/EUI_Fonts_Options.lua:1093 | absent (aucun texte de combat flottant géré) | M |
| Empêcher l'icône de Prompt de Soin Rapide de s'assombrir | Évite l'atténuation de Swiftmend sur barres et CDM selon Efflorescence | retail (sort druide retail) | Opt/EUI__General_Options.lua:2630 | absent | G |
| Supprimer les erreurs Lua | Bascule `scriptErrors` | oui | Opt/EUI__General_Options.lua:2660-2668 | partiel : équivalent existant `hideLuaErrors` (Modules/Interface.lua:51), à l'identique | - |
| ID de sort dans l'infobulle | Affiche le spell ID dans les infobulles (et alimente une CVar d'ID d'aura en combat) | ? | Opt/EUI__General_Options.lua:2670-2682 | absent | M |
| Optimiser mes FPS et graphismes / Restaurer | Applique ~17 CVars graphiques (ombres, liquides, particules, SSAO, profondeur, distance de vue, reverb, contraste +10), sauvegarde et restauration en un bouton | ? (les CVars `graphics*` existent dans Blizzard_SettingsDefinitions_Shared ; absentes du dossier Forever pour `ResampleAlwaysSharpen`) | Opt/EUI__General_Options.lua:1790-1860 | absent | M |
| Réinitialiser les réglages d'un module ou de TOUS (bouton avec confirmation à saisir) | Remise à zéro d'un module au choix, ou de tout le compte | oui | Opt/EUI__General_Options.lua:1880-1990 | partiel : « Remettre le profil actuel par défaut » (profil entier seulement), pas de remise à zéro par module ni de remise à zéro compte | M |
| Écran « Légendes / remerciements » | Page de crédits | oui | Opt/EUI__General_Options.lua:179-224, 3139 | absent | G |
| Page notes de version (What's New) | Liste des changements par module avec marqueur Forever, popup à chaque mise à jour | oui | Opt/EUI_WhatsNew_Options.lua ; Core/EllesmereUI_PatchNotesPopup.lua | partiel : fenêtre de bienvenue seulement ; `CHANGELOG.md` hors jeu | G |

### 2. Style global (EUI / Blizzard / Classic / Forever)

| Fonction | Ce qu'elle fait | Forever ? | Preuve EUI | Chez nous | Valeur |
|---|---|---|---|---|---|
| Choix d'un style par module : look EllesmereUI, Blizzard Style, Classic WoW UI, variante WoW Forever | Page Style : cartes de style, liste à cases par carte, tout écrit par « Apply Styles » avec un rechargement ; drapeaux `useBlizzardStyle*`, `useClassicStyle*`, `useForeverStyle*` par module | oui (4e carte réservée à Forever) | Opt/EUI_Style_Options.lua:1-60, 174-201 ; Core/EllesmereUI_StyleCards.lua | absent (un seul look MuscaUI) ; texture « Blizzard Classic » de barre seulement (Core/Media.lua:29) | M |
| Cadre classique de barre (bordure de cast bar vanilla en neuf tranches) | Habille n'importe quelle barre avec la bordure UI-CastingBar | oui | Core/EllesmereUI_ClassicArt.lua ; Opt/EUI_Style_Options.lua:846 | absent | G |
| Popup de choix de style au premier lancement + popup de lancement de style | Choix du style à l'installation | oui | Core/EllesmereUI_StyleChoicePopup.lua, _StyleLaunchPopup.lua ; Opt/EUI_Style_Options.lua:962 | absent (FirstRun propose un préréglage et des CVars, pas de style) | G |
| Coins arrondis partagés des barres (rayon 0-16, styles Solid / Glow / Shadow) | Masque arrondi pour cadres d'unité, barres de ressources, cellules de raid, minuteur d'attaque, plaques | oui | Core/EllesmereUI_RoundedCorners.lua:1-30 ; media/rounded/ | absent | G |

### 3. Panneau d'options (navigation, recherche, widgets partagés) et règles de visibilité

| Fonction | Ce qu'elle fait | Forever ? | Preuve EUI | Chez nous | Valeur |
|---|---|---|---|---|---|
| « Apply to All » / « Apply to Multiple » sur un réglage | Un réglage porte une icône de synchro : un clic recopie sa valeur sur tous les éléments équivalents ou sur ceux cochés (flash d'accent sur les cibles) | oui | Opt/EllesmereUI_Widgets_ApplyToAll.lua:114, 431-454, 614 | partiel : « Copier les réglages depuis » par barre / bloc (docs/options.md:441-581), pas de propagation d'un réglage unique à plusieurs éléments | M |
| Modèle de lueur global + « Apply to All Active Glows » | Un style de lueur réglé une fois, appliqué à toutes les lueurs actives de tous les modules ; masque les lueurs inactives ; page « Module Glows » | oui | Opt/EUI_Glows_Options.lua:719-739, 295, 574 | absent (la lueur est réglée module par module ; Core/Glow.lua est un moteur sans page globale) | M |
| Recherche globale floue (« Search Features... », « Search Module Settings... ») | Recherche floue sur tous les réglages de tous les modules, fil d'Ariane, ouvre la page au réglage | oui | Core/EllesmereUI_GlobalSearch.lua:1-30 ; Core/EllesmereUI_Panel.lua (strings Search Features...) | présent (Config/OptionsWindow.lua:120-137, Options.Search) | - |
| Visibilité : « Uniquement en donjon » (distinct de « en instance ») | Axe donjon seul | oui | Core/EllesmereUI_VisibilityRules.lua:393-397 | partiel : seule la condition `instance` (Core/Visibility.lua:19), sans distinction donjon / raid / champ de bataille ; ignorée dans le state driver | M |
| Visibilité : au repos (en ville / auberge) | Cacher ou montrer quand `IsResting()` | oui | Core/EllesmereUI_VisibilityRules.lua:418 | absent (6 conditions : combat, groupe, raid, instance, monté, cible) | M |
| Visibilité : en véhicule | Cacher ou montrer selon `UnitInVehicle` | oui | Core/EllesmereUI_VisibilityRules.lua:422 | absent | M |
| Visibilité : cible ennemie (hors cible quelconque) | « Hide without Enemy Target » / « Hide with Enemy » | oui | Core/EllesmereUI_VisibilityRules.lua:435-440 ; 104-106 | partiel : condition `target` = existence de cible seulement (`@target,exists`) | M |
| Visibilité : pendant Party Mode | Cacher / montrer pendant la fête | oui | Core/EllesmereUI_VisibilityRules.lua:427 | absent (pas de Party Mode) | G |
| Visibilité : cible douce (soft target) comme front d'événement | Réévalue `[exists]`/`[harm]` sur les changements de cible douce | ? | Core/EllesmereUI_VisibilityRules.lua:431-433 | absent (non vérifié que Forever expose la cible douce) | G |
| Visibilité : en logement (housing) / skyriding / monté en vol | Axes logement et vol à dos de monture | retail | Core/EllesmereUI_VisibilityRules.lua:93-101, 398-410 | absent (contenu absent sur Forever) | - |
| Pages d'état de classe pour la visibilité (Prowl, forme de félin, Ours, Moonkin, Furtivité, Postures de guerrier) | Conditions macro `bonusbar` par classe pour paginer / masquer selon forme ou posture ; Forever : Berserker oui, Moonkin non | oui (déjà adapté par EUI à Forever) | Core/EllesmereUI_VisibilityRules.lua:56-90 (`CLASS_PAGING_STATES`) | partiel : la barre 1 change de page avec postures et furtivité (docs/options.md, Barres d'action) ; pas de visibilité par forme dans Core/Visibility.lua | M |
| Modes de visibilité nommés partagés (Jamais, Toujours, Survol, En combat, Hors combat, Raid, Groupe, Seul) | Menus déroulants communs aux barres d'action, CDM, barres de ressources, cadres d'unité | oui | Core/EllesmereUI_VisibilityRules.lua:15-54 | présent (autre modèle, tri-état + « toutes / au moins une », Core/Visibility.lua:2-4) | - |
| Visibilité « Any » / « All » entre axes | Mode de correspondance tout / au moins un | oui | Core/EllesmereUI_Visibility.lua:5-9 | présent (`match = "all"`/`any`, Core/Visibility.lua:30) | - |
| Récap : fenêtre guidée « vidéo / guide » | Popups d'annonce avec URL copiable (presets site, midnight_121, settings_overrides…) | oui | Core/EllesmereUI_VideoGuides.lua:1-30 | absent | G |
| Astuce de la barre latérale pour Unlock Mode | Bulle d'aide à la première utilisation | oui | Core/EllesmereUI_Panel.lua (L("Unlock Mode is where you can adjust…")) | partiel : l'assistant et la fenêtre de bienvenue expliquent `/musca unlock` ; pas de bulle sur le bouton | G |
| Groupes du menu latéral : étendre / réduire des groupes (Expand / Collapse), icône Twitch | Groupes repliables du menu latéral | oui | Core/EllesmereUI_Panel.lua (L("Expand") / L("Collapse")) | partiel : onglets de catégorie en haut (Config/OptionsWindow.lua:2-9), pas de groupes repliables | G |

### 4. Profils, presets, overrides par spécialisation, conditions, synchro

| Fonction | Ce qu'elle fait (1 ligne) | Forever ? | Preuve EUI | Chez nous | Valeur |
|---|---|---|---|---|---|
| Overrides par spécialisation (« Editing as ») | Valeurs propres à une spé (ou groupe de spés) à l'intérieur d'UN seul profil, capture automatique, bordures dorées sur les réglages surchargés, liste de gestion | oui (spés Forever mappées via FOREVER_CLASS_SPEC) | Core/EllesmereUI_SpecOverrides.lua:71,279-288 ; Core/EUI_SpecOverrides_Session.lua, _Harvest.lua, _Borders.lua, _ListPage.lua, _Popups.lua | partiel (un profil entier par spé, Core/Database.lua ; pas de valeur par réglage dans un profil partagé) | H |
| Layout Unlock Mode par spé (couches / forks) | Position des éléments différente par spé sans dupliquer le profil | oui | Core/EUI_SpecOverrides_Layers.lua | absent (positions = profil entier) | M |
| Overrides conditionnels | Réglages surchargés selon condition : touche, groupe, donjon, raid, arène, champ de bataille, seul, mode sombre ; priorité keybind > darkmode > instance > groupe > seul | oui (conditions de contenu génériques) | Core/EllesmereUI_Conditions.lua:14-80 ; Core/EUI_SpecOverrides_Conditional.lua | partiel (bascule de profil entier par contexte : hors instance, donjon, raid, BG/arène, Core/Database.lua ; pas par réglage, pas de condition touche ni groupe/seul) | M |
| Groupes de synchro de profils (miroirs) | Des modules/réglages restent identiques entre profils (groupes de miroir) | oui | Core/EllesmereUI_ProfileSync.lua | partiel (un « miroir » via CVar `MuscaUIMirror`, Core/Database.lua ; non vérifié : granularité) | G |
| Export par addon avec menu « Include » | À l'export/import, choisir Overrides, layout Unlock Mode, réglages globaux, skins de fenêtres/infobulles | oui (skins Blizzard : retail) | Opt/EUI_Profiles_Options.lua:711-746,1057-1066 ; Core/EllesmereUI_Profiles.lua:634 | partiel (cases par module, docs/options.md Profils > Partage ; pas de case layout/positions séparée : non vérifié) | M |
| Export / import compte entier | Tous les profils, assignations de spés et layouts en une chaîne | oui | Core/EllesmereUI_Profiles.lua (ExportAll / ImportAll, 94 fonctions) | partiel (AccountExport existe, Core/Database.lua ; assignations de spés : non vérifié) | M |
| « Auto Assign to Specs » à l'import | Applique les assignations spé -> profil contenues dans la chaîne reçue | oui | Opt/EUI_Profiles_Options.lua:1013-1038 | absent | G |
| Import avec popup de décalage d'échelle UI | Avertit quand l'échelle UI de la chaîne diffère de l'écran local | oui | Opt/EUI_Profiles_Options.lua:31-69 | absent | G |
| API d'import pour installeurs tiers | ImportProfileInteractive / ImportProfileSilent / RegisterExternalInstaller | oui | Core/EllesmereUI_Profiles.lua:4843-5080 | absent | G |
| Presets populaires (site) | Chaînes de profils d'auteurs, installables | oui | Core/EllesmereUI_Presets.lua:181-339 (popup de sélection classe/spé) | partiel (presets rôle et classe maison, docs/options.md Profils de classe ; pas de bibliothèque communautaire) | G |
| Garde client à l'import | Refuse ou adapte une chaîne produite sur l'autre client (retail / forever) | oui | Core/EllesmereUI_Profiles.lua:1898-1907 | absent (non vérifié : version de chaîne) | G |

Équivalents complets : profil par perso, renommer / dupliquer / supprimer / restaurer sauvegarde, touche de bascule d'un profil, profil par spé, partage par chaîne avec cases de sections, envoi au groupe.

### 5. Couleurs

| Fonction | Ce qu'elle fait (1 ligne) | Forever ? | Preuve EUI | Chez nous | Valeur |
|---|---|---|---|---|---|
| Mode sombre par module | Interrupteur propre aux cadres d'unité, cadres de groupe/raid, barre de ressource de classe ; réglages Color Darkening, Dark Mode Fill et Background | oui | Opt/EUI_Colors_Options.lua ; Core/EllesmereUI_Colors.lua | partiel (une case globale « Mode sombre des barres de vie », Core/Media.lua `DARK` ; pas par module, pas de curseurs) | M |
| « Apply to All Profiles » / « Pull Colors From » | Propage ou copie les couleurs entre profils | oui | Opt/EUI_Colors_Options.lua | absent | G |
| Couleurs de classe personnalisées | Remplace la palette RAID_CLASS_COLORS | oui | Opt/EUI_Colors_Options.lua ; Core/EllesmereUI_Colors.lua | absent | M |
| Couleurs de ressource (puissance) personnalisées | Couleur de mana, rage, énergie, etc. | oui | Opt/EUI_Colors_Options.lua | absent | M |
| Couleurs des ressources de classe (points de combo, runes, fragments, puissance sacrée, charges arcaniques, chi, essence, etc.) | Une couleur par ressource de spé | retail pour essence, fragments d'âme, maelstrom weapon, tip of the spear, whirlwind, sweeping strikes ; oui pour combo, runes, fragments de Démoniste de base | Opt/EUI_Colors_Options.lua | absent (non vérifié : couleurs fixes dans Modules/ barres de ressources) | M |

### 6. Polices

| Fonction | Ce qu'elle fait (1 ligne) | Forever ? | Preuve EUI | Chez nous | Valeur |
|---|---|---|---|---|---|
| 23 polices fournies | Pack de polices embarqué | oui | EllesmereUI/media/fonts | absent (aucune police embarquée ; LibSharedMedia + police Blizzard, Core/Media.lua) | M |
| Mode de contour global | Ombre / contour / contour épais appliqué partout | oui | Opt/EUI_Fonts_Options.lua ; Core/EllesmereUI_Fonts.lua | partiel (police, taille, contour du thème, Core/Media.lua ; couverture « tout le texte » : voir ligne suivante) | G |
| « Apply to All Game Text » | Remplace les polices Blizzard (objets de police globaux), rechargement | oui | Opt/EUI_Fonts_Options.lua ; Core/EllesmereUI_Fonts.lua | absent (non vérifié : overrides de polices Blizzard) | M |
| « Game Text Scale » | Échelle globale du texte du jeu | oui | Opt/EUI_Fonts_Options.lua | absent | G |
| « Disable Slug Outline » | Désactive le contour Slug (moteur de texte 12.x) | retail (non vérifié) | Opt/EUI_Fonts_Options.lua | absent | G |
| Pages police/taille par module (noms, nombre d'objets, avertissement de mana, chat/onglet/zone de saisie, chrono, suivi de quêtes, infobulle, enchantements, texte de combat) | Police, taille, contour d'un texte précis | oui | Opt/EUI_Fonts_Options.lua | partiel (police par module via `theme.moduleMedia`, Core/Media.lua ; pas par texte) | G |

### 7. Textures

| Fonction | Ce qu'elle fait (1 ligne) | Forever ? | Preuve EUI | Chez nous | Valeur |
|---|---|---|---|---|---|
| 25 textures fournies | Pack de textures de barres embarqué | oui | EllesmereUI/media/textures | partiel (4 textures + Blizzard Classic + LSM, Core/Media.lua) | G |
| Texture par élément | Santé, absorption, absorption de soins, vie max, barre d'incantation, barre GCD, fond/onglet du chat, alerte de mouvement, curseur, anneaux GCD / incantation, barres du compteur de dégâts | oui | Opt/EUI_Textures_Options.lua | partiel (texture globale + surcharge par module, Core/Media.lua) | G |
| Styles d'absorption, d'absorption de soins, de vie max | Rendu de ces couches (rayé, plein, etc.) | oui | Opt/EUI_Textures_Options.lua | absent (non vérifié) | G |

### 8. Lueurs (glow)

| Fonction | Ce qu'elle fait (1 ligne) | Forever ? | Preuve EUI | Chez nous | Valeur |
|---|---|---|---|---|---|
| Styles de lueur supplémentaires | Shape Glow, flipbook GCD, Modern WoW Glow (atlas Proc-Loop), Classic WoW Glow (IconAlertAnts), Blackout, en plus de pixel / auto-cast / bouton | atlas : ? | Core/EllesmereUI_Glows.lua:25-45 | partiel (4 styles : pixel, autocast, bouton, classique, Core/Glow.lua:1-20) | G |
| Modèle de lueur global + réglages (couleur, épaisseur, fréquence) | Un gabarit appliqué à tous les modules | oui | Opt/EUI_Glows_Options.lua | partiel (non vérifié : réglages par module dans Core/Glow.lua) | G |

### 9. Pixel perfect

| Fonction | Ce qu'elle fait (1 ligne) | Forever ? | Preuve EUI | Chez nous | Valeur |
|---|---|---|---|---|---|
| Système PP, PanelPP, bordures texturées | Aligne tout sur le pixel physique ; version dédiée pour le panneau d'options ; moteur de bordures | oui | Core/EllesmereUI_PixelPerfect.lua:1-25 | partiel (NS.Pixel existe, Config/Options.lua:407 ; panneau d'options : non vérifié) | G |

### 10. Mode déplacement (Unlock Mode), compléments

| Fonction | Ce qu'elle fait (1 ligne) | Forever ? | Preuve EUI | Chez nous | Valeur |
|---|---|---|---|---|---|
| Filtre par nom saisi | Cherche un élément par nom dans les mouvers | oui | Core/EUI_UnlockMode_Filter.lua | partiel (filtre par module, Core/Movers.lua) | G |
| Ancres fantômes / de secours | Si la cible d'une ancre manque, l'élément retombe sur une ancre de secours | oui | Core/EUI_UnlockMode_Anchors.lua | partiel (fallback existe, Core/Movers.lua) | G |
| Garde contre Edit Mode | Empêche Edit Mode de repositionner les cadres gérés | retail (Edit Mode absent sur Forever : non vérifié) | Core/EUI_UnlockMode_Positions.lua:2741 | sans objet | - |
| Superpositions d'info Blizzard, taille visuelle des barres d'action, bannière animée, astuce unique | Aides visuelles du mode | oui | Core/EUI_UnlockMode_Tools.lua, _Session.lua | absent | G |

Équivalents complets : mouvers avec grille et aimantation, ancrage sur un autre mouver avec correspondance largeur/hauteur, épingle / croissance, flèches de précision, annulation de session.

### 11. Mode fête (Party Mode)

| Fonction | Ce qu'elle fait (1 ligne) | Forever ? | Preuve EUI | Chez nous | Valeur |
|---|---|---|---|---|---|
| Projecteur disco, rotation des éléments, déclencheurs de célébration (aléatoire, Bloodlust, niveau, clé, boss, victoire arène/BG, M0) | Animations festives | partiel : porte Forever ligne 322, déclencheurs de clé/arène retail | Opt/EUI_PartyMode_Options.lua:80-352 ; Core/EllesmereUI_PartyMode.lua | absent | G |

### 12. Manette

| Fonction | Ce qu'elle fait (1 ligne) | Forever ? | Preuve EUI | Chez nous | Valeur |
|---|---|---|---|---|---|
| Masquer barres d'action, barre d'incantation des cadres d'unité et des ressources quand une manette est connectée | Bascule d'affichage selon manette | ? (non vérifié : API manette sur Forever) | Opt/EUI_Gamepad_Options.lua:118-186 | absent (aucune occurrence manette dans Core/, Modules/, Config/) | G |

### 13. Gestionnaire d'équipement/talents (Loadout Manager) et Conseil de butin (Simple Loot Council)

| Fonction | Ce qu'elle fait (1 ligne) | Forever ? | Preuve EUI | Chez nous | Valeur |
|---|---|---|---|---|---|
| Loadout Manager : échange auto d'ensemble d'équipement et de loadout de talents selon l'instance, la difficulté et la spé | Assigne un set / loadout par instance ou difficulté, échange hors combat ou en file, avertissement de changement de talents, annonce dans le chat, vérification des sets | ? (C_EquipmentSet : fichier Mainline seulement ; loadouts de talents : système retail, non vérifié sur Forever) | Opt/EUI_LoadoutManager_Options.lua:379-660 | absent | M |
| Simple Loot Council : vote du butin de raid synchronisé par messages d'addon | Pages butin/sessions, conseil, vote, réponses, historique, diagnostics | ? (maître du butin : non vérifié) | Opt/EUI_SimpleLootCouncil_Options.lua:57-63 | absent (Modules/Loot.lua = cadre de butin, pas de conseil) | M |
| Page « Nouveautés » / « Legends » | Notes de patch par version, cartes dépliables | oui | Opt/EUI_WhatsNew_Options.lua ; Core/EllesmereUI_PatchNotesPopup.lua | absent (déjà noté en section 1) | G |
| Calculateur de mise à niveau d'objets | Coût des améliorations | retail (page quitte sur Forever) | Opt/EUI_UpgradeCalc_Options.lua | sans objet | - |

### 14. Services du coeur divers

| Fonction | Ce qu'elle fait (1 ligne) | Forever ? | Preuve EUI | Chez nous | Valeur |
|---|---|---|---|---|---|
| Popup de première installation (choix des modules à garder) | Active / désactive des addons à la première exécution | oui | Core/EllesmereUI_FirstInstall.lua | partiel (assistant de premier lancement avec CVars recommandés, Config/FirstRun.lua ; pas de choix des modules : non vérifié) | G |
| Désinstallation : instantané et restauration des CVars, Edit Mode, polices du chat, touches | Restaure l'état Blizzard | oui (Edit Mode : retail) | Core/EllesmereUI_Uninstall.lua | partiel (restauration CVars Core/CVars.lua + /musca uninstall, Core/Core.lua:282 ; polices du chat et touches : non vérifié) | M |
| Format de nombres avec paliers CJK | Abréviations 万 / 억 / 萬 selon la langue | oui | Core/EllesmereUI_NumberFormat.lua | partiel (AbbreviateNumbers dans les modules, Core/DataTexts.lua, Modules/UnitFrameElements.lua ; non vérifié : paliers CJK) | G |
| Données d'interruption par classe | Table des sorts d'interruption, liste Forever | oui | Core/EllesmereUI_KickData.lua ; Core/EllesmereUI_Kick.lua ; Core/EllesmereUI_KickTrackerPopup.lua | voir agent nameplates/rappels (non traité ici) | - |
| ManaRegenSpark | Marqueur de régénération de mana (règle des 5 secondes) sur la barre de mana | oui (Forever uniquement) | Core/EllesmereUI_ManaRegenSpark.lua | absent (non vérifié) | M |
| WarriorCharges | Charges de guerrier | retail (12.1) | Core/EllesmereUI_WarriorCharges.lua | sans objet | - |
| BuffPresets | Familles d'améliorations préréglées pour les listes d'auras (FOREVER_BUFF_FAMILIES) | oui | Core/EllesmereUI_BuffPresets.lua | voir agent auras (non traité ici) | - |
| Masquer le gestionnaire de raid Blizzard | Cache CompactRaidFrameManager | oui | Core/EllesmereUI_BlizzardParty.lua | non vérifié (Modules/BlizzardFrames.lua) | G |
| MenuFallbacks | Repli des menus contextuels (logement, retail) | retail | Core/EllesmereUI_MenuFallbacks.lua | sans objet | - |
| Garde client | Désactive l'addon sur client trop ancien | oui | Core/EllesmereUI_ClientGate.lua | sans objet | - |
| Service curseur partagé | Un service de position du curseur pour plusieurs modules | oui | Core/EllesmereUI_Mouse.lua | partiel (Modules/Cursor.lua) | G |

Équivalents complets : registre d'or par personnage (Core/DataTexts.lua:356-365), échelle UI et pixel perfect (Config/Options.lua:407-442).

### 15. Langues

| Fonction | Ce qu'elle fait (1 ligne) | Forever ? | Preuve EUI | Chez nous | Valeur |
|---|---|---|---|---|---|
| Langues fournies | deDE, esES, esMX, frFR, itIT, koKR, ptBR, ruRU, zhCN, zhTW ; fichiers SLC en plus pour deDE et ptBR | oui | EllesmereUILocales/ | équivalent : enUS + 10 traductions (Locale/) | - |

### Limites client révélées

- Fenêtre « Slug outline » : option propre au moteur de texte 12.x, absente du moteur Forever (non vérifié) : Opt/EUI_Fonts_Options.lua.
- Page Upgrade Calc quitte aussitôt sur Forever (pas de système de mise à niveau d'objets) : Opt/EUI_UpgradeCalc_Options.lua (début de fichier).
- CVars d'affichage 12.x `ResampleAlwaysSharpen`, texte de combat flottant `_v2` et `WorldTextScale_v2` introuvables dans ~/wow-ui-source/forever (non vérifié au runtime) : voir section 1.
- `cameraDistanceMaxZoomFactor` utilisé par Camelot/ControlsOverrides.lua sur Forever ; `C_Spell.GetSpellQueueWindow` documenté ; `ActionButtonUseKeyDown` dans SecureTemplates.lua (section 1).
- Atlas des lueurs flipbook (RotationHelper_Ants_Flipbook, UI-HUD-ActionBar-Proc-Loop-Flipbook, IconAlertAnts) : présence sur Forever non tranchée : Core/EllesmereUI_Glows.lua:25-45.
- C_EquipmentSet n'apparaît que dans un fichier Mainline du source Forever ; talents de classe (C_ClassTalents) seulement en documentation générée : à vérifier avant tout Loadout Manager.

### Non couvert

- Sources des modules LoadoutManager et SimpleLootCouncil : absentes du paquet (seules leurs pages d'options existent). Lus par leurs options seulement.
- Core/EllesmereUI_Migration.lua (255 K) : migrations de données, non lu.
- Core/EllesmereUI_Panel.lua (280 K), EllesmereUI.lua (235 K) : parcourus par grep, pas lus en entier.
- Core/EllesmereUI_PixelPerfect.lua (2224 lignes) : en-tête seulement.
- EllesmereUI_FriendsKit, AuraKit, MacroFactory, GroupFinderPopup, Range, SpellCostPrediction, Ticker, SignupHelpers : relèvent d'autres zones ou non examinés.
- Pages d'options de chaque module (Nameplates, UnitFrames, etc.) : hors zone.

## 3. Fonctions Forever et qualité de vie

Chemins EUI relatifs à `EllesmereUI-v9.6.8/`. FE = `EllesmereUIForeverEssentials/EllesmereUIForeverEssentials_`, FEO = `EllesmereUIOptions/EUI_ForeverEssentials_`. Tout le module FE est gaté `EllesmereUI.IS_FOREVER` (chaque fichier, ligne 2) : « Forever ? » = oui sauf mention.
Aucun équivalent MuscaUI de tout le module Forever Essentials (grep du code, hors docs : aucune occurrence de uprank, fishing, flight, lootfeed, zone level, gather, map fade, quest reward).

### 1. Forever Essentials : général

| Fonction | Ce qu'elle fait | Forever ? | Preuve EUI | Chez nous | Valeur |
|---|---|---|---|---|---|
| Auto Uprank Spells | Au apprentissage d'un nouveau rang, remplace les rangs inférieurs sur les barres d'action et le dit dans le chat | oui | FE Uprank.lua:3-6 ; FEO General:163 | absent | H |
| Classic Spellbook | La touche du grimoire ouvre le grimoire vanilla (onglets d'école, 12 sorts/page, recherche), fonctionne en combat via snippets restreints | oui | FE ClassicSpellbook.lua:3-14 ; FEO General:302 | absent (Skin.lua / MovableWindows.lua ne font que l'habillage / le déplacement du grimoire Blizzard) | M |
| Classic Talents | La touche des talents ouvre la fenêtre de talents vanilla (arbres, rangs, flèches, points posés puis « Learn ») | oui | FE ClassicTalents.lua:3-11 ; FEO General:309 | absent | M |
| Simplified Stats : Shorten Equip Lines, Merge Equal Spell Power, Color Stats, Number Color | Réécrit les lignes « Equip: Increases… » / « Set: » des infobulles d'objet en « +X Stat », fusionne dégâts/soins de sorts, colore les stats | oui | FE SimplifiedStats.lua:3-22 ; FEO General:335-352 | absent (Habillage = infobulles sombres, pas de réécriture de lignes de stat) | M |
| Most Valuable Reward | Sac d'or sur le choix de récompense de quête qui se vend le plus cher (fenêtre de quête, journal, carte) | oui | FE QuestRewards.lua:3-13 ; FEO General:369 | absent | H |
| Auto Summon Pet + Favorites per Character | Réinvoque un mascotte favorite après mort, écran de chargement, vol, véhicule ; favoris par personnage via menu du journal ; jamais en combat/instance/PvP/furtif/monté | oui | FE PetSummon.lua:3-22 ; FEO General:388-397 | absent (Reminders.lua gère le familier de chasseur/démoniste, pas les mascottes) | M |
| Active Stance, Form, Aspect & Aura icon | Une icône click-through de la posture/forme/aura/aspect active, taille, zoom, style et taille de bordure, offsets de bordure texturée, visibilité | oui | FE ActiveForm.lua:3-8 ; FEO General:418-530 | absent (Reminders.lua rappelle une posture manquante, n'affiche pas l'active) | M |
| Gathering Skill in Tooltips (+ option Minimap) | Ajoute le skill requis d'un filon/herbe à l'infobulle, couleur selon la chance de progresser ; sur la minimap aussi | oui | FE GatherSkill.lua:3-22 ; FEO General:597-612 | absent | M |
| Junk Items window : activer, Items Shown, Include White Items, Skip Confirmation for White, Excluded Items (clear), Icon Size/Spacing, Price Position, Show Empty Bag Slots, Only Show When Bag Space Low (seuil) | Petite fenêtre des déchets les moins chers : Ctrl+clic gauche supprime, clic milieu l'exclut à jamais, prix sous l'icône | oui | FE JunkItems.lua:3-12 ; FEO General:646-735 | partiel : vente auto des gris (Automation.lua, docs/options.md « Confort automatique ») et objets gris signalés dans les sacs (MuscaUI_Bags) ; pas de fenêtre de suppression/libération de places | H |
| Name Format (First / Last / First and Last) | Un seul endroit qui règle l'affichage du prénom/nom sur cadres d'unité, raid/groupe, plaques ennemies/amies, damage meters, threat meter | oui | FEO General:11-155, 532-587 | absent (réglage de nom propre à chaque module, pas de miroir central) | G |

### 2. Forever Essentials : carte du monde

| Fonction | Ce qu'elle fait | Forever ? | Preuve EUI | Chez nous | Valeur |
|---|---|---|---|---|---|
| Fade Map While Moving | Active le CVar mapFade : la carte devient transparente pendant le déplacement | oui | FE MapFade.lua:3-8 ; FEO General:196 | absent | M |
| Show the Game Behind the Map | Éclaircit le noir derrière la carte maximisée (alpha 20 %) | oui | FE MapFade.lua:6-8 ; FEO General:200 | absent | G |
| Reveal Unexplored Areas (+ couleur de teinte) | Dessine les overlays de zones non explorées, teintés | oui | FE MapReveal.lua:3-12 + MapRevealData.lua ; FEO General:208,247 | absent | M |
| Show Zone Levels | Plage de niveaux de la zone survolée sur la carte d'un continent, colorée par difficulté | oui | FE ZoneLevels.lua:3-8 ; FEO General:216 | absent | M |
| Show Fishing Skill | Skill de pêche requis par zone sous son nom, rouge/jaune/vert | oui | FE ZoneLevels.lua:9-12 ; FEO General:235 | absent | G |
| Show Map Markers (jeux : transports, entrées d'instance, points de vol, sorties de zone) | Pins de voyage sur la carte ; survol = nom, clic gauche = lien de pin dans le chat, clic droit = niveau de carte au-dessus | oui | FE MapTravel.lua:3-14 + MapTravelData.lua ; FEO General:227,262 | absent | M |

### 3. Forever Essentials : voyage (Travel)

| Fonction | Ce qu'elle fait | Forever ? | Preuve EUI | Chez nous | Valeur |
|---|---|---|---|---|---|
| Flight Timer : activer, Fade In/Out | Barre de piste avec durée restante pendant un vol de maître de vol, arrêts qui défilent, marqueur « vous » | oui | FE FlightTimer.lua:3-12 ; FEO Travel:82-90 | absent | H |
| Flight Timer : Show Time, Show Total Time, Show Names, Early Exit Button (atterrit au prochain point de vol), End Caps, Separator, Spark | Éléments de la barre | oui | FEO Travel:268-358 | absent | M |
| Flight Timer : apparence (largeur, hauteur, style/taille/couleur/décalage de bordure, texture et opacité de barre et de fond, couleur perso ou de classe, taille/offset du texte) | Cosmétique de la barre | oui | FEO Travel:43-260 | absent | G |

### 4. Forever Essentials : menace (Threat Meter)

| Fonction | Ce qu'elle fait | Forever ? | Preuve EUI | Chez nous | Valeur |
|---|---|---|---|---|---|
| Threat Meter : fenêtre (activer, Only With Threat, source Cible/Focus, Ignore Pets, ligne Pull Aggro, titre « Threat - mob », mode entraînement) | Fenêtre de barres triées par menace de chaque membre du groupe sur la cible (ou sur ce que combat un ami ciblé) | oui | FE ThreatMeter.lua:3-10,1007,1140 ; ThreatData.lua:3-9 ; FEO Threat:200-233 | absent (nous colorons la menace sur plaques/cadres seulement ; « Autre tank » n'est pas une liste) | H |
| Threat Meter : Displayed Value (Pull %, Tank %), valeur colorée vert→rouge, marqueur du joueur, Bar Color (classe/menace…) | Valeurs et couleurs des barres | oui | FE ThreatMeter.lua:1433 ; FEO Threat:560-700 | absent | M |
| Threat Meter : Warning (son + seuil Warn At %) | Son quand la menace du joueur approche le pull | oui | FE ThreatMeter.lua:1446 ; FEO Threat:244-261 | absent | H |
| Threat Meter : fenêtre mobile (verrou, poignée de redimensionnement, accroche aux bords des fenêtres Damage Meters, largeur/hauteur par menu, molette si trop de lignes, menu contextuel) | Châssis de fenêtre | oui | FE Window.lua:3-12 ; ThreatMeter.lua:1398-1461 | absent | M |
| Threat Meter : apparence (texture, style d'icône, zoom, séparateur, en-tête, bordures, fond, police/contour) | Cosmétique | oui | FEO Threat:418-830 | absent | G |
| Threat % Text (plaques et cadres d'unité) : activer, position, Color by Threat, Text Shows (dont Threat Gap), Show on Focus, offsets | Chiffre de menace en % sur la plaque de la cible / le cadre d'unité | oui | FEO Threat:284-410 | absent (docs/options.md : seulement couleurs de menace des plaques l.1689-1695 et bordures de menace des cadres) | M |
| Threat type dans Damage Meters | Liste de menace servie comme « type de meter » | oui | FE ThreatFeed.lua:3-11 | absent (nous n'avons pas de damage meter, hors zone) | G |

### 5. Forever Essentials : butin (Loot Feed)

| Fonction | Ce qu'elle fait | Forever ? | Preuve EUI | Chez nous | Valeur |
|---|---|---|---|---|---|
| Loot Feed : activer + aperçu | Pile de lignes éphémères pour objets, argent, réputation, monnaies, progression de compétence ; un gain répété s'ajoute à sa ligne | oui | FE LootFeed.lua:3-9 ; FEO Loot:114-130 | absent (Loot.lua = fenêtre de butin et jets, pas de flux) | H |
| Sources : Items, Money, Reputation, Currencies, Skill Ups | Choix des sources | oui | FEO Loot:150-171 | absent | M |
| Gold per Hour Tracker | Ligne fixe cumulant l'or de la session par heure | oui | FE LootFeed.lua:8-9 ; FEO Loot:167 | absent | M |
| Items : Minimum Quality, Show Item Level, Show Item Price, Use Auctionator Prices | Filtre et infos des lignes d'objet | oui | FEO Loot:181-215 | absent | M |
| Layout : largeur, hauteur de ligne, Max Rows, Display Time, Grow Direction, taille du texte, espacement ; Style (Box, Icon Tray, Loot Toast…) | Mise en page et styles | oui | FEO Loot:132-245 | absent | G |
| Display : texture et opacité du fond, style/couleur de bordure, Accent Bar Width, Show Behind, Separator | Cosmétique | oui | FEO Loot:247-330 | absent | G |

### 6. Forever Essentials : macros et pêche

| Fonction | Ce qu'elle fait | Forever ? | Preuve EUI | Chez nous | Valeur |
|---|---|---|---|---|---|
| Macro Manager (/euimacros) : éditeur visuel des macros du compte et du personnage (icônes en grille, liste de lignes /cast /use /castsequence /target /focus /equip /click /petattack etc., variantes `[@cible,conditions]`, « Else variant », conditions avec Not, Saved For, choix d'icône, Show Spell Tooltip, texte brut, ligne libre) | Construit et relit les macros sans les taper ; une ligne non reconstructible est conservée en brut | oui | FE MacroManager.lua:3-8 ; FEO Macros:3-14,1388 ; MacroModel:3-35,42-146 | absent (Menu radial accepte `macro:Nom`, aucun éditeur) | M |
| Fishing Key | Une touche lance la ligne, équipe d'abord une canne, applique un leurre | oui | FE Fishing.lua:3-12 ; FEO General:763-790 | absent | M |
| Fishing : Reel In With the Key, Bobber Indicator (mover), Apply Lure | Ramène la ligne via soft-interact sur la bobbe, indicateur de prise | oui | FE Fishing.lua:7-9 ; FEO General:790-801 | absent | M |
| Double-Click to Cast (+ Apply Lure) | Double clic droit sur le monde avec une canne : lance | oui | FE Fishing.lua:10-11 ; FEO General:765 | absent | M |
| Fishing Sounds | Musique/ambiance baissées, effets montés, son en arrière-plan pendant la pêche | oui | FE Fishing.lua:12-13 ; FEO General:819 | absent | G |


### 7. QoL : automatisation et masquage d'éléments Blizzard

| Fonction | Ce qu'elle fait | Forever ? | Preuve EUI | Chez nous | Valeur |
|---|---|---|---|---|---|
| Self Combat Text | Dégâts subis, soins, esquives, entrée/sortie de combat au-dessus du cadre joueur ; taille, distance et durée de défilement, échelle des critiques, animation (Straight/Fountain/Static), direction, police, couleurs par catégorie | oui | EllesmereUIQoL/SelfCombatText.lua:3-20,323 ; EUI_QoL_Options.lua:281-385 | absent (aucun code de texte de combat) | M |
| Masquer Party Panel (Sidebar) | Cache le panneau de groupe Blizzard | oui | EUI_QoL_Options.lua (section Hide Blizzard Elements) | absent (Interface épurée, options.md l.1502) | G |
| Masquer fenêtre de jets de groupe | Cache ou ferme après délai (slider) la fenêtre de loot de groupe | oui | EUI_QoL_Options.lua:565,663-671 | absent (options.md Butin l.748) | M |
| Skip Cinematics : modes | Mode, fermer après délai, passer automatiquement si possible | oui | EUI_QoL_Options.lua:625-692 | partiel (simple case « Passer les cinématiques », options.md l.1323) | G |
| Auto Sell Junk : résumé en icônes de pièces | Affiche le gain en icônes de pièces | oui | EUI_QoL_Options.lua (Auto Sell Junk) | partiel (vente présente, pas de résumé en icônes) | G |
| Hide Item Transforms | Retire automatiquement les buffs de transformation choisis (popup de sélection) | oui | EllesmereUIQoL.lua:4861 ; EUI_QoL_Options.lua:792 | absent | M |
| Auto Select Single Gossip | Choisit l'option unique d'un PNJ ; Maj pour ignorer, désactivé en instance, ignore quêtes bas niveau | oui | EUI_QoL_Options.lua:805-861 | partiel (Automation.lua:307 accepte/rend les quêtes, ne choisit pas l'option de gossip unique) | M |
| Train All Button | Bouton « tout apprendre » chez l'entraîneur | ? (source Forever : TrainerUI présent seulement sous Mainline/, non vérifié) | EllesmereUIQoL.lua:864 | absent | M |
| Auto Unwrap Collections | Ouvre montures/mascottes/jouets en attente | ? (API MountJournal fanfare non vérifiée sur Forever) | EllesmereUIQoL.lua:243 | absent | G |
| Auto Open Containers | Ouvre les conteneurs du sac automatiquement | ? | EllesmereUIQoL.lua:354 | absent | M |
| Auto Combat Logging | Active /combatlog selon raids/donjons (Forever), arrêt différé 30 s pour Warcraft Recorder, force Advanced Combat Logging | oui | EllesmereUIQoL_AutoLogging.lua:86 ; EUI_QoL_AutoLogging_Options.lua:251-322 | absent | M |
| Waypoint (/way, /euiway) + Hand-Placed Pin Arrival | Pose un point de route par coordonnées | oui (C_Map.SetUserWaypoint présent dans le source Forever) | Waypoint.lua:1-14 ; options 204-236 | absent | M |
| Type /cd | Ouvre le gestionnaire de recharges Blizzard | ? (non vérifié) | EUI_QoL_Options.lua | absent | G |

### 8. QoL : extras

| Fonction | Ce qu'elle fait | Forever ? | Preuve EUI | Chez nous | Valeur |
|---|---|---|---|---|---|
| FPS Counter autonome | Compteur FPS + latence Local/World, raccourci, intervalle, masquer libellé, attache aux Secondary Stats | oui | EUI_QoL_Options.lua:924-1090 | partiel (FPS/latence dans TopBar, minimap, Panneaux de données, options.md l.1622 ; pas de compteur flottant ni raccourci) | G |
| Low Durability Warning : réglages | Taille du texte, décalage Y, % de réparation | oui | EUI_QoL_Options.lua (Extras) | partiel (seuil seul, options.md Rappels l.1811) | G |
| Disable Right Click Targeting | Bloque le clic droit de ciblage (ennemis / alliés en combat) via mouselook | oui | EllesmereUIQoL.lua:3275 | absent (aucun résultat grep) | M |
| Secondary Stat Display | Stats du catalogue Forever (fenêtre Choose Stats, réordonner, valeurs colorées, abréger, échelle) | oui | EllesmereUIQoL_ForeverStats.lua ; EUI_QoL_StatPicker.lua ; EUI_QoL_Options.lua:1547-1690 | absent (ni DataBars ni Panneaux ne montrent de stats) | H |
| Guild Chat Privacy Cover | Voile sur le chat de guilde | oui | EllesmereUIQoL.lua:2087 | absent | G |
| Target Distance Text | Distance à la cible : format, alignement, taille, strate, couleur par tranche de mètres | oui | EllesmereUIQoL.lua:4567 ; EUI_QoL_Options.lua:1707-1815 | absent | M |
| Environment Ping (raccourci) | Ping d'environnement au clavier | ? (non vérifié) | EllesmereUIQoL.lua:3043 ; options 1836 | absent | G |
| Show Coordinates on Map | Coordonnées curseur/joueur sur la carte du monde, taille du texte | oui | EUI_QoL_Options.lua:1837-1857 | partiel (coordonnées minimap/Panneaux seulement, pas sur la carte) | M |
| Equipment Flyout : niveaux d'objet (+ lettres de stats) | Affiche l'ilvl dans le menu de comparaison d'équipement | oui | EllesmereUIQoL.lua:5067 | absent (Gear.lua sans flyout) | M |

### 9. QoL : réticule et curseur

| Fonction | Ce qu'elle fait | Forever ? | Preuve EUI | Chez nous | Valeur |
|---|---|---|---|---|---|
| Crosshair avancé | None/Thin/Normal/Thick/Custom, longueur/largeur H et V, bordure + couleur, décalage X/Y, strate, visibilité Toujours/Combat/Instances, portée mêlée Hpal, couleur hors portée | oui | EllesmereUIQoL.lua:3463 ; EUI_QoL_Options.lua:1891-2245 | partiel (réticule : actif, combat seul, taille, épaisseur, couleur ; options.md l.1351) | G |
| Cursor Circle : modes et traînée | Couleur perso/classe/accent, texture, échelle, opacité, traînée, instances seulement, souris masquée seulement, point central | oui | EUI_QoL_Cursor_Options.lua | partiel (Cursor.lua : anneau actif/combat/taille/couleur) | G |
| GCD Circle | Anneau de GCD autour du curseur (couleur, texture, échelle, opacité, attache, instances/combat) | oui | EUI_QoL_Cursor_Options.lua | absent (la GCD est une barre, module séparé) | M |
| Cast Bar Circle | Anneau de cast autour du curseur + étincelle | oui | EUI_QoL_Cursor_Options.lua | absent | M |

### 10. QoL : alertes

| Fonction | Ce qu'elle fait | Forever ? | Preuve EUI | Chez nous | Valeur |
|---|---|---|---|---|---|
| Potion Ready Alert | Alerte quand la potion de combat est prête | oui | EllesmereUIQoL_Alerts.lua ; EUI_QoL_Alerts_Options.lua | absent | M |
| Unspent Talents Alert | Alerte si des talents sont non dépensés | ? (runtime utilise C_SpecializationInfo.CanPlayerUseTalentUI, Alerts.lua:466 ; GetUnspentTalentPoints existe dans Cata/TalentFrameBase.lua) | Alerts.lua:466 | absent | M |
| Combat Alert : « Show On » et couleur de classe | Choix du contexte d'affichage, couleur de classe | oui | EUI_QoL_Alerts_Options.lua | partiel (alerte présente, options.md l.298) | G |

### 11. QoL : alerte de mouvement

| Fonction | Ce qu'elle fait | Forever ? | Preuve EUI | Chez nous | Valeur |
|---|---|---|---|---|---|
| Modes d'affichage | Texte, icône ou barre ; texture, icône sur barre, texte de durée, taille texte/icône, décimales | oui | EUI_QoL_MovementAlert_Options.lua:408-1109 | partiel (iconSize, readyAlert, extraSpells seuls ; options.md l.328) | M |
| Combat Only + sélection de classes | Limite au combat, liste de classes | oui | idem | absent | G |
| Son + TTS (voix, volume, message) | Son et synthèse vocale à l'usage | oui (SpeakText présent dans Blizzard_ChatFrame/Shared/TextToSpeechFrame.lua du source Forever) | idem | absent | M |
| Grille Tracked Spells | Ajouter, remplacer, masquer par sort | oui | idem | partiel (extraSpells : ajout seulement) | M |
| Gateway Shard (Démoniste) | Alerte de portail | ? (non vérifié) | MovementAlert.lua | absent | G |
| Time Spiral | Suivi de Spirale temporelle | retail (non vérifié) | MovementAlert.lua | absent | G |
| Écart de liste : sort 781 | EUI exclut Disengage (781) sur Forever ; notre CLASS_SPELLS HUNTER l'inclut | oui | MovementAlert.lua:850-852 | écart (Modules/MovementAlert.lua ~l.29) | G |

### 12. QoL : Raid Tools

| Fonction | Ce qu'elle fait | Forever ? | Preuve EUI | Chez nous | Valeur |
|---|---|---|---|---|---|
| Quick Fire world markers | Raccourcis Poser/Annuler/Effacer marqueurs de monde, utilisables en combat | oui | RaidTools.lua ; EUI_QoL_RaidTools_Options.lua | absent | M |
| Boutons activables un par un | Role Check, Convert to Raid, Disband affichables à la carte | oui | idem | absent (RaidUtility.lua : tous présents, non masquables) | G |
| Timers de pull par clic modificateur | 3 timers, Ctrl/Shift/Clic, clic droit stoppe | oui | idem | partiel (3 comptes à rebours par touches, pas de clic modificateur) | G |
| Fenêtre repliée par défaut, sens de déploiement, échelle fenêtre 0.5-2, icône repliée | Réglages de la fenêtre classique | oui | idem | partiel (bandScale seul, options.md l.1950) | G |

### 13. QoL : fenêtres déplaçables (Shifter)

| Fonction | Ce qu'elle fait | Forever ? | Preuve EUI | Chez nous | Valeur |
|---|---|---|---|---|---|
| Reset d'une fenêtre précise | Liste déroulante de réinitialisation par fenêtre | oui | EUI_QoL_Shifter_Options.lua | partiel (reset global seul, MovableWindows.lua, options.md l.1377) | G |
| Déplacer sans Maj | Option sans touche modificatrice | oui | idem | absent | G |
| Déplacer fenêtres de butin / toasts en mode déverrouillage | Moveurs Bonus Roll, jets de groupe, toasts d'alertes | oui (Bonus Roll : retail) | idem | absent | M |
| Moveur du texte d'événement haut-centre | Scénario / événement / rencontre | oui | idem | absent | G |

### 14. Fonctions retail (gatées, non applicables à Forever)

Bonus Roll Confirmation (EllesmereUIQoL.lua:84), AH Current Expansion Only (:982), Auto Insert Keystone / Quick Signup / Persistent Signup Note (:1569 ; options 2253-2299), Talking Head hide/mute (:1636 ; options 511-530), Top Screen Banners (:1838), Battle Res (BattleRes.lua:463), Bloodlust (Bloodlust.lua:2), /keys (Keys.lua:2), TeleportPrompt/LFG Reminder (TeleportPrompt.lua:2), Upgrade Calculator (EUI_UpgradeCalc.lua:2), Macro Factory (options 439), Exclude Warbound Containers, Hold Capped Artisan Payouts. Forever ? = retail pour toutes.

### Équivalents complets
Auto-réparation + banque de guilde, vente des gris, Quick Loot, remplissage de la confirmation de suppression, ALT pour libérer, accepter invitations, annonce de reset d'instance, masquage tutoriels / erreurs / capture d'écran / erreurs Lua, Talking Head, indicateur de repos, alerte entrée/sortie de combat, alerte morts de groupe, avertissement durabilité (base), échelle pixel-perfect, bases Raid Utility, ilvl sur fiche de personnage.

### Limites client révélées
- Menace lisible sur Forever, C_Secrets.ShouldUnitThreatValuesBeSecret faux ; unités à valeur secrète ignorées : ThreatData.lua:3-9
- Aucune durée de vol exposée : temps = longueur / vitesse, rechargement en vol perd la barre : FlightTimer.lua:3-12
- Cadre Classic Spellbook protégé, snippets restreints ; recherche/options changées en combat appliquées après : ClassicSpellbook.lua:3-14
- C_Map.GetMapLevels renvoie 0 sur Forever : ZoneLevels.lua:3-8
- CancelUnitBuff bloqué en combat (Hide Item Transforms, balayage à PLAYER_REGEN_ENABLED) : EllesmereUIQoL.lua:4861
- Données de C_CombatText.GetCurrentEventInfo secrètes : SelfCombatText.lua:9
- Forever : aucun nombre sous 10 000 ne s'abrège : SelfCombatText.lua:22
- Forever sans notes/tertiaires : ForeverStats.lua:3-8
- Disengage 781 pas un sort de mouvement sur Forever : MovementAlert.lua:850-852
- Waypoint : setters C_Map/C_SuperTrack jamais appelés depuis l'addon (risque de taint), pin posé par le gestionnaire de lien de la carte : Waypoint.lua:9-14
- Hide Error Messages : désactiver exige un rechargement : EllesmereUIQoL.lua:3852
- Raid Tools : coques protégées, Show/Hide et SetAttribute bloqués en combat, changements d'options différés à PLAYER_REGEN_ENABLED : RaidTools.lua (en-tête)
- Pêche : boutons sécurisés liés hors combat seulement : Fishing.lua:14-16
- PetSummon : jamais en combat, invocation refusée en combat : PetSummon.lua
- Absents sur Forever (contenu) : Macro Factory, clés, bonus rolls, amélioration d'objet, Battle Res, Bloodlust, Talking Head, AH extension courante

### Non couvert
EUI_UpgradeCalc.lua (1920 lignes, retail) ; BattleRes/Bloodlust/Keys (retail, en-têtes seuls) ; corps de JunkItems, LootFeed, ThreatMeter, Window (en-têtes seuls) ; détail de l'UI Macro Manager ; fichiers de données FE ; réglages purement cosmétiques survolés ; AFK, Frames, Reminders, Loot : comparés via options.md seulement ; disponibilité Forever des lignes marquées « ? » non tranchée.

## 4. Cadres d'unité et barres de ressources

Abréviations de chemins (racine EUI = `EllesmereUIOptions/` sauf mention) :
- SB = `UnitFrames_Options/SharedBars_Options.lua`, SA = `UnitFrames_Options/SharedAppearance_Options.lua`, SC = `UnitFrames_Options/SharedCastAuras_Options.lua`, MF = `UnitFrames_Options/MiniFrames_Options.lua`, TS = `UnitFrames_Options/TextSlots_Options.lua`, UFO = `EUI_UnitFrames_Options.lua`, PM = `EUI_PlayerAuraBars_ManagerPages.lua`.
- RB = `ResourceBars_Options/` (BarDisplayPage, CastBarPage, ClassResourceSection, GCDBarPage, HealthSection, PowerSection, SwingTimerPage, TotemBarPage).
- UF = `EllesmereUIUnitFrames/EUI_UnitFrames_*.lua`, ERB = `EllesmereUIResourceBars/EUI_ResourceBars_*.lua`.
- Nous : UnitFrames.lua = `MuscaUI_UnitFrames/UnitFrames.lua`, UFE = `Modules/UnitFrameElements.lua`, ResourceBars.lua = `MuscaUI_UnitFrames/ResourceBars.lua`. « options.md » = docs/options.md (sections Cadres d'unité MuscaUI l.781-1094, Barres de ressources l.683-733, Barres d'auras l.598, Barre de recharge globale l.362, Minuteur d'attaque l.1590).

Note de portée : EUI possède aussi Forever Essentials (menace, hors zone) et un réglage global « Style » (cadres Blizzard/Classic/WoW Forever) dans le noyau EllesmereUI ; seul ce qui touche les cadres d'unité est repris ici.

---

### 1. Cadres d'unité : textes et noms

| Fonction | Ce qu'elle fait | Forever ? | Preuve EUI | Chez nous | Valeur |
|---|---|---|---|---|---|
| Emplacements de texte gauche / droite / centre / « extra pleine largeur » sur la barre de vie, chacun avec contenu au choix (nom, niveau+nom, vie %, vie #, cible…), taille, décalages X/Y, largeur %, séparateur, préfixe, couleur de classe, couleur de l'indicateur | Placement libre des textes du cadre | oui | SB:589,793,992,1170 ; TS:35-174 | partiel : un texte de vie (préréglage ou format `[cur]/[max]`…) + un texte central, jetons `[name]` `[level]` (options.md « Format de vie », « Texte central ») ; aucune position, taille, largeur % ni séparateur par texte | M |
| Format du nom : premier mot / dernier mot / nom court | Raccourcit les noms (aussi pour « nom > cible ») | oui (gaté Forever) | TS:48 ; EUI_UnitFrames_Options.lua:48 ; UF_Text.lua:1072 | absent | M |
| Couleur du niveau selon la difficulté (+ option « amicaux inclus ») | Colore le niveau gris→rouge selon l'écart de niveau | oui | TS:13-25 | absent (UFE : niveau sans couleur de difficulté) | G |
| Texte « nom > cible » / « cible > nom » dans un emplacement | Affiche la cible de l'unité à côté du nom | oui | TS (HAS_NAME `nametotarget`, `targetname`) ; TS:7-8 | absent | G |
| Surnoms (nicknames) sur les noms | Utilise le surnom d'un addon de surnoms | ? (non vérifié) | SA:145 | absent | G |
| Décimales du texte de vie, « 2 pour les boss », masquer zéros finaux | Format fin du pourcentage de vie | oui | SA:838,878-894 | absent | G |
| Texte de puissance : position, couleur, taille, décalages, « afficher % » | Réglages du texte de puissance | oui | SB:1554-1579,1898-1963 | partiel : préréglage de texte de puissance + format personnalisé (options.md) ; ni position ni couleur ni taille | M |
| Barre de texte détachée (« Text Bar » : textes gauche/droite/centre + icône de classe, position/largeur/hauteur/strates) | Bandeau de texte sous ou sur le cadre | oui | SA:1904-2669 | absent | G |

### 2. Cadres d'unité : barres, couleurs, géométrie

| Fonction | Ce qu'elle fait | Forever ? | Preuve EUI | Chez nous | Valeur |
|---|---|---|---|---|---|
| Couleur de remplissage de la vie personnalisée, couleur dynamique, dégradé (activer + direction), opacité de remplissage, fond de barre (opacité/couleur) | Style de la barre de vie | oui | SB:154,230,411-429,504 | partiel : classe/réaction/dégradé rouge-vert/palier « couleur sous % » + couleurs de réaction ; pas de couleur libre, pas de fond ni d'opacité réglables (options.md l.790-810) | M |
| Barres de vie lissées (animation de remplissage) | Interpolation du remplissage | oui | SB:501 | absent (UFE:976 impose `Immediate`) | M |
| Échelle du cadre | Facteur d'échelle par cadre | oui | SB:56 ; MF:323 | absent par cadre (échelle globale seulement, UnitFrames.lua « Thème ou échelle ») | M |
| Strate du cadre (principaux, boss, barres détachées) | Ordre d'empilement | oui | SA:718-789 | absent | G |
| Position de la barre de puissance (dessus/dessous/détachée/aucune), largeur et décalages, barre de puissance au-dessus de la vie sur mini-cadres | Placement de la puissance | oui | SB:1394-1440 ; MF:1182-1185 | partiel : hauteur seule (0 = masquée), toujours collée au cadre (options.md « Hauteur de la barre de puissance ») | M |
| Puissance : couleur de remplissage, fond, dégradé, opacité, remplissage inversé | Style de la barre de puissance | oui | SB:1509-1713,1882-1887 | absent (couleur Blizzard imposée, UFE:96) | G |
| Type de puissance au choix (druide : Mana dans toutes les formes) et « Mana + puissance de forme » : seconde barre pour l'énergie/rage de la forme | Barre de forme sous la puissance | oui (druide) | SB:2274,2321-2347 ; UF_ForeverFormBar.lua:1-22 | partiel : le mana de druide existe comme barre de ressource séparée (ResourceBars.lua:1-5, options.md « Mana en forme de druide ») ; rien sur la barre de puissance du cadre joueur | M |
| Étincelle de régénération de mana (règle des 5 secondes, ticks de 2 s) sur la puissance | Montre la fenêtre sans régénération | oui | SB:2256 ; EllesmereUI_ManaRegenSpark.lua:1-25 | absent | H |
| Prédiction du coût d'un sort sur la barre de mana | Segment clair = mana que le sort va dépenser | oui | SB:2204-2208 ; EllesmereUI_SpellCostPrediction.lua:1-14 | absent | M |
| Bordure du cadre : style, taille, décalage, « derrière », rayon de coin, séparateur de barre de puissance | Habillage de bordure | oui | SA:346-433,684 ; UFO:248-325 | absent (bordure du thème, UnitFrames.lua « Le thème repeint les bordures ») | G |
| Bordure au survol / au ciblage, surbrillance | Bordures de survol et de cible | oui | SA:847-912 ; MF:174-175,297 | absent | G |
| Infobulle d'unité : « Afficher pour » (qui) | Filtre l'infobulle | oui | SA:713 | absent | G |
| Fade hors combat avec opacité, « afficher quand la vie manque » | Atténuation du cadre | oui | SA:164-180 ; UF_Visibility.lua:17-35 | équivalent partiel suffisant : « Estomper hors combat » + opacité estompée ; « vie manquante » couvert par « blessé » (UnitFrames.lua:264-266) | — |
| Source du cadre par unité : EUI ou Blizzard par défaut | Garde le cadre Blizzard d'une unité précise | oui | UFO:2017-2030 | partiel : « Afficher ce cadre » par unité + coupure du module entier (options.md l.827 etc.) ; les cadres Blizzard ne reviennent qu'au /reload | M |
| Styles « stock » : kits Blizzard, Classic WoW, WoW Forever (art, masques, forme des barres) posés sur les cadres | Cadres à l'apparence d'origine | oui | UF_StockStyles.lua:1-38,321-340 | absent | M |
| Cadres boss : sens d'empilement, espacement vertical, activer | Disposition des 5 boss | oui | MF:1968-2011 | partiel : un bloc commun « Boss (1 à 5) » ; pas de sens ni d'espacement réglables (options.md l.1057) | G |
| Cible de la cible / familier / focus (mini-cadres) : portrait à droite, icône de classe, portrait non-joueur personnalisé | Variantes de portrait | oui | MF:1490-1599 | partiel : portrait 2D avec côté (UFE:323) ; pas de style « classe » ni de portrait non-joueur | G |

### 3. Cadres d'unité : portrait, indicateurs, absorptions

| Fonction | Ce qu'elle fait | Forever ? | Preuve EUI | Chez nous | Valeur |
|---|---|---|---|---|---|
| Portrait 3D animé, 2D en miroir, mode classe, zoom 2D/3D/classe, taille, position, séparateur vertical | Modes de portrait | oui | UFO:145,166 ; SA:1119-1550 | partiel : portrait 2D rogné fixe, côté réglable (UFE:323-328,716-717) ; pas de 3D, zoom, miroir, taille | M |
| Forme du portrait, anneau externe, ombre interne, bordure de forme, dragon décoratif (taille/strate/classe) | Décor de portrait | oui | SA:1568-1867 | absent | G |
| Indicateur de combat, repos : taille, position, décalages, couleur de classe, couleurs ennemies | Réglages fins de l'indicateur | oui | SA:2811-2958 | partiel : on/off des « repères de combat, repos » seulement (UnitFrames.lua:2-9) | G |
| Marqueur de raid : taille, position, décalages | Réglages du marqueur | oui | SA:3009-3032 | partiel : affiché, taille/position fixes (UFE:889-897) | G |
| Icône de chef : taille, style, position | Réglages de l'icône | oui | SA:3119-3149 | partiel : on/off | G |
| Icône élite/rare : taille, style, position, « en instance » | Réglages de l'icône | oui | SA:3226-3285 | partiel : on/off (« Icône élite ou rare ») | G |
| Écusson de faction / drapeau JcJ : taille, style, position, « joueurs seulement » | Réglages de l'icône | oui | SA:3315-3367 | partiel : on/off (UFE:816-833) | G |
| Absorptions : style (plusieurs rendus), opacité, placement, « surbouclier », ligne lumineuse Blizzard, sur les boss | Rendu des absorptions | oui | SB:3176-3306 | partiel : couleur, hauteur %, activer (options.md l.789-794) ; pas de style, placement, surbouclier | M |
| Absorptions de soins : style, opacité, placement, opacité du fond | Rendu des soins absorbés | oui | SB:3360-3472 | partiel : couleur seule | G |
| Barres d'absorption séparées (hauteur 1-20) + prédiction de soins : opacité, texture, « surguérison » | Barres dédiées | oui | SB:3520-3688 | absent (prédiction et absorption superposées à la vie, UFE:296-311,430) | G |
| Menace : % de menace sur cible et focus (6 positions dont « hors cadre »), unités, couleur par menace, « afficher sur le focus » | Texte de menace pour les tanks | oui (gaté Forever) | SA:1039-1070 ; UF_Threat.lua:1-9,130-238 | absent (nous : seulement la bordure à la couleur de la menace, UFE:842-860) | H |
| Bordure de menace « joueur non-tank » additive en instance de groupe | Alerte de menace hors tank | oui (Forever : la menace joueur) | SA:916 ; UF_Threat.lua:20-32 | partiel : bordure de menace générique par cadre (options.md « Bordure à la couleur de la menace ») ; pas de règle non-tank/instance | M |
| En-tête de cible coloré à la Blizzard | Bandeau de couleur | oui | SA:1086 | absent | G |

### 4. Cadres d'unité : barre d'incantation

| Fonction | Ce qu'elle fait | Forever ? | Preuve EUI | Chez nous | Valeur |
|---|---|---|---|---|---|
| Icône : afficher, à droite, sur le portrait, intégrée à la barre, bordure autour de l'icône, séparateur vertical, décalages | Placement de l'icône d'incantation | oui | SC:394,455-597 ; MF:3116-3172 | partiel : icône présente (UFE:367) ; aucune option | G |
| Nom du sort, durée, cible du sort : taille, décalages, « fusionner nom et cible » | Textes de la barre | oui | SC:691-945 ; MF:3209-3279 | partiel : « cible du sort » on/off (options.md l.797) ; pas de position/taille | G |
| Masquer au repos, opacité de remplissage, remplissage inversé, fond, bordure perso, strate relevée | Style de la barre | oui | SC:253-311,914 ; MF:3069-3097 | absent | G |
| Marque « interruption prête » en milieu de barre (tic ou barre) | Aide à l'interruption | oui | SC:283-294 ; MF:3081-3085 | partiel : couleur « interruption prête » (options.md l.801) ; pas de tic | G |
| Lueur « incantation importante » (cible/focus) | Lueur sur sorts importants | oui | UFO:1144-1148 | partiel : couleur « sort important » (options.md l.803) ; pas de lueur ni de choix de style | M |

### 5. Cadres d'unité : auras

| Fonction | Ce qu'elle fait | Forever ? | Preuve EUI | Chez nous | Valeur |
|---|---|---|---|---|---|
| Emplacement séparé des buffs et des débuffs (dessus/dessous/côté), taille par type, nombre max, par ligne, sens de croissance, décalages, espacement | Disposition fine des auras | oui | SC:1106-1155,1216-1427 ; MF:1819-1836,2115-2130,2342-2448 | partiel : « Auras au-dessus du cadre » (une seule position), taille unique (options.md l.848-851) ; pas de max/ligne/croissance | M |
| Durée et piles : taille, position, décalages, « précis sous N minutes », « S pour secondes » | Textes d'aura | oui | SC:1354-1403,1498-1547 ; MF:2166-2188 | absent (textes du moteur seuls) | M |
| Bordures par type de dissipation, anneau de dissipation texturé, couleurs de dissipation | Couleur des débuffs par type | oui | SC:1324,1449-1459,1636,2228 | partiel : `dispel = true` à l'init des boutons (UFE:1308-1310), couleurs non réglables | M |
| Surcouche de dissipation sur la barre de vie (opacité, « seulement ce que vous dissipez », icône de type) | Repère visuel de débuff dissipable | oui | SC:2223-2355 | absent | M |
| Filtres d'auras : « tous », « a une durée », « montrer » (volés, défensifs majeurs, dissipables…), blacklist/liste incluse, copie des filtres d'une unité, « masquer épuisement » | Filtrage fin des auras | partiel : « Big Defensive » est un contenu retail non vérifié ; le reste oui | SC:1688-1693,1764-1805,2005-2163 ; UFO:707-853 | partiel : filtre des débuffs + liste blanche/noire d'identifiants + « débuffs en tête » (options.md l.815-823) ; pas de filtres par catégorie ni de copie | M |
| Lueur sur les buffs dissipables (« purgeable ») de la cible/focus | Montre ce qu'on peut purger/voler | oui | UFO:1133-1139 | absent (seule la lueur sur les contrôles existe, options.md « Lueur sur les contrôles ») | M |
| Bordure d'icône : style, taille, décalage, « derrière le cadre », zoom d'icône | Habillage des icônes d'aura | oui | SC:1316,1562-1633 ; MF:2661-2721 | absent | G |
| Auras « simples » des cadres boss (nombre, par ligne, espacement) | Disposition des auras boss | oui | MF:2066-2330 | absent | G |

### 6. Cadres d'unité : points de combo, puissance de classe, familier

| Fonction | Ce qu'elle fait | Forever ? | Preuve EUI | Chez nous | Valeur |
|---|---|---|---|---|---|
| Points de combo : emplacement cible / joueur / jamais (défaut cible sur Forever) | Combos sur le cadre de la cible, comme Blizzard Forever | oui | SB:3017-3022 ; EllesmereUIUnitFrames.lua:441 ; UF_ClassPower.lua:428,573 | partiel : barre de combo sur le cadre du joueur seulement, aucune option sur le cadre cible (options.md l.835-840 vs l.868-905) | M |
| Ressource de classe : style (moderne, aucun…), position (dessus/dessous…), taille, espacement, couleur de fond, décalages | Réglages de la barre de combo du cadre | oui | SB:2579-2922 ; EllesmereUIUnitFrames.lua:425-431 | partiel : pastilles séparées, espacement, couleur (options.md l.836-838) ; pas de position, taille de pastille ni couleur de fond | G |
| Humeur du familier : taille, position | Réglage de l'icône d'humeur | oui | MF:1736-1771 ; UF_ForeverExtras.lua:19-31 | partiel : on/off (options.md « Humeur du familier de chasseur ») | G |
| Barre de puissance du familier | Puissance sous le familier | oui | UF_Builders.lua:856 | équivalent (« Barre de puissance » du familier, options.md l.1042) | — |

### 7. Barres d'auras du joueur (Player Aura Bars)

EUI : grilles d'icônes de buffs et débuffs (moteur d'aura 12.1, `AuraKit`) ; MuscaUI : barres horizontales avec nom et temps. Les deux ne montrent pas la même chose.

| Fonction | Ce qu'elle fait | Forever ? | Preuve EUI | Chez nous | Valeur |
|---|---|---|---|---|---|
| Affichage en grille d'icônes (par ligne, nombre de lignes, max total, forme d'icône, zoom, balayage de durée, infobulle) | Alternative compacte aux barres | oui | PM:1346-1587 ; UF_PlayerAuraBars_Config.lua (en-tête) | absent (Modules/AuraBars.lua : barres uniquement, `maxBars`, longueur, épaisseur, espacement) | M |
| Tri : méthode et sens | Ordre des auras | oui | PM:981-987 | partiel : toujours « plus court d'abord » (AuraBars.lua:1-5) | G |
| Filtres de buffs par classe/catégorie + sorts supplémentaires par identifiant + blacklist + préréglages + copie | Choix précis des buffs affichés | oui (préréglages retail masqués) | PM:431-695 ; UF_PlayerAuraBars_Filters.lua:1-40,140 | partiel : « Afficher » (buffs/débuffs/les deux), « masquer sans durée » (options.md l.600-601) ; pas de liste ni de catégories | M |
| Filtres de débuffs par catégorie (type, saignement, boss…), mode « tous les critères » | Choix des débuffs | oui | PM:751-811 ; UF_PlayerAuraBars_Groups.lua:1-15 | absent | M |
| Barres personnalisées libres (créer N barres de buffs/débuffs, chacune avec ses filtres et son mover) | Plusieurs barres d'auras | oui | UF_PlayerAuraBars_CustomBars.lua:1-9 ; UF_PlayerAuraBars_Filters.lua:19-40 | absent (une seule barre) | M |
| Cases d'imprégnation d'arme (Forever : Rockbiter, Flamme, Furie des vents…) intégrées à la barre de buffs | Montre les imprégnations (enchantements d'arme) | oui | UF_ForeverImbues.lua:1-26 | absent (aucune recherche d'enchantement d'arme dans Modules/AuraBars.lua) | H |
| Clic droit pour annuler un buff | Retire un buff au clic | oui (non vérifié sur Forever) | PM:1614 | absent | M |
| Couleurs de dissipation, icône de type, effets par catégorie (bordure/taille), anneau texturé | Habillage des débuffs | oui | PM:1647-1830 | partiel : débuffs à la couleur de leur type (AuraBars.lua:98) ; buffs en couleur unique (options.md « Couleur des buffs ») | G |
| Durée/piles : taille, position, décalages, « précis sous N minutes », contour | Textes d'aura | oui | PM:1038-1112 | absent | G |
| Bordure d'icône (style, taille, décalage) | Habillage | oui | PM:1128-1232 | absent | G |
| Spécialisations : buckets de filtres par spécialisation | Filtres selon la spé | retail (Forever : une seule entrée « allspecs ») | UF_PlayerAuraBars_Filters.lua:889 ; PM:2876 | absent | G |

### 8. Barres de ressources : vie, puissance, mana de druide

| Fonction | Ce qu'elle fait | Forever ? | Preuve EUI | Chez nous | Valeur |
|---|---|---|---|---|---|
| Barre de vie : dégradé, bordure (style/taille/rayon/décalage), couleur libre, opacité, texture, fond | Habillage de la barre de vie | oui | RB/Health:113-636 | partiel : épaisseur, texte, couleur de classe, couleur sous % x2, repères (options.md l.701-711) ; pas de bordure, dégradé, couleur libre, opacité | M |
| Texte de vie : ancre, décalages, taille, couleur | Position du texte | oui | RB/Health:696-793 | partiel : choix du format seul (« Texte », options.md l.704) | G |
| Fondu hors combat par barre (opacité propre) et « afficher quand il manque de la vie/du mana » | Masque la barre quand elle est pleine | oui | RB/Health:654-670 ; RB/Power:608-646 | partiel : « Opacité hors combat » globale (options.md l.687) ; pas de « vie manquante » ni d'opacité par barre | M |
| Réduction de la vie maximum (affichage) | Montre la part de vie max retirée | ? (non vérifié) | RB/Health:103-107 ; ERB_HealthIndicators.lua:1-12 | absent | G |
| Absorptions et absorptions de soins sur la barre de vie (style, opacité) | Superposition d'absorptions | oui | ERB_HealthIndicators.lua:1-12 | absent sur la barre de ressource (présent sur les cadres d'unité) | G |
| Puissance : couleur, dégradé, bordure, opacité, texture, fond, « au-dessus de la barre GCD » | Habillage de la puissance | oui | RB/Power:79-608 | partiel : épaisseur, texte, repère, couleurs sous % (options.md l.713-723) | M |
| Texte de puissance : ancre, taille, décalages, « afficher % », couleur | Position du texte | oui | RB/Power:679-786 | partiel : format seul | G |
| Seuils par valeur (couleur sous une valeur absolue, lignes de repère) | Seuils colorés | oui | RB/Power:755-809 ; ERB_Thresholds.lua:1-10 | partiel : seuils en % (« Couleur sous (%) », « Repères à (%) ») ; pas de seuil absolu | G |
| Étincelle de régénération de mana + prédiction du coût sur la barre de ressource | Idem cadres | oui | RB/BarDisplay:986,1001 ; ERB_Events.lua:329 | absent | H |
| Type de puissance au choix (druide : mana seulement) | Force le mana en forme | oui | RB/BarDisplay:925,982,1033 ; EllesmereUIResourceBars.lua:339-345 | partiel : barre de mana de druide séparée | G |
| Mana de druide en forme : position (dessus/dessous/dedans), écart, hauteur, texte (taille, ancre, décalages, %) | Réglage de la barre de mana secondaire | oui | RB/BarDisplay:1088-1238 ; ERB_ForeverDruidMana.lua:1-14 | partiel : « Afficher » + « Épaisseur » seulement (options.md l.730-733) | M |
| Lissage des barres | Animation | oui | RB/BarDisplay:206 | absent | M |
| Textures et fonds par barre, strate, bordure autour du groupe, séparateur | Habillage global du groupe | oui | RB/BarDisplay:335-668 ; ERB_Groups.lua:1-8 | partiel : texture/police par module (options.md « Polices et textures ») ; pas de fond, strate ni bordure de groupe | G |
| Décalage automatique : agrandir la puissance sans ressource de classe, décaler les éléments, masquer la puissance si ressource | Réagence la pile de barres | oui | RB/BarDisplay:687-847 | absent (chaque barre a son mover, pas de réagencement automatique) | M |
| Ancrage, déverrouillage, tailles liées entre barres | Positionnement | oui | ERB_Anchors.lua:1-5 | partiel : mover par barre, ancrage sous le cadre du joueur, largeur reprise (ResourceBars.lua:1-8) | — |
| Orientation propre à chaque barre (vie, puissance) | Orientation de chaque barre | oui | RB/Health:47 ; RB/Power:45 | partiel : orientation commune à toutes les barres (options.md l.685) | G |

### 9. Barres de ressources : ressource de classe

Sur Forever, EUI n'offre comme ressource de classe que les points de combo (Voleur, Druide en félin) : EllesmereUIResourceBars.lua:516. Les options propres à Gardien/Guerrier/Moine/Sorcier, runes, etc. sont retail.

| Fonction | Ce qu'elle fait | Forever ? | Preuve EUI | Chez nous | Valeur |
|---|---|---|---|---|---|
| Combos : orientation, taille, bordure de pastille, fond par pastille, séparateurs, espacement, rayon de coin, superposition « vide » | Habillage fin de la barre de combo | oui | RB/Class:215-796 | partiel : épaisseur seule (« Points de combo », options.md l.725-728) ; pastilles non réglables sur la barre | M |
| Couleur de remplissage (par palier), couleur « chargé », assombrir les points partiels | Couleurs des combos | oui pour la couleur ; « chargé » (combos chargés) : ? non vérifié | RB/Class:796-913 | absent | G |
| Texte de ressource (%, max, ancre, décalages), seuils, lignes de repère | Valeur numérique du combo | oui | RB/Class:991-1090 | absent | G |
| Fondu hors combat propre à la ressource de classe | Opacité | oui | RB/Class:959-967 | partiel : opacité commune des barres | G |
| Combos lus sur la cible (Forever garde les combos sur la cible, repeint au changement de cible) | Valeur correcte sur Forever | oui | EllesmereUIResourceBars.lua:526-538 | `NS.ComboPointsRaw` utilisé (UFE:921) ; non vérifié que la lecture suit la cible | ? |
| Barre de Gardien (Fer-peau), Guerrier (Ignorer la douleur), Frappes balayantes, Esprit arcanique, Runes, Maelström, Moine/Chi, Paladin/Puissance sacrée, Mage/charges, Chasseur/Focus, Chaman/Enhance… | Ressources spécifiques de classe | retail | RB/Class:103-205,1371-1395 ; RB/BarDisplay:1292-1303 ; ERB_ArcaneSoul.lua:56 ; ERB_EbonMight121.lua ; EllesmereUIResourceBars.lua:516 | absent (non applicable Forever) | — |
| Art de ressource Blizzard (frame natif) | Réutilise le cadre natif de ressource | retail | ERB_BlizzClassArt.lua:90,430 | absent | — |

### 10. Barres de ressources : barre d'incantation du joueur, GCD, minuteur d'attaque, totems

| Fonction | Ce qu'elle fait | Forever ? | Preuve EUI | Chez nous | Valeur |
|---|---|---|---|---|---|
| Barre d'incantation du joueur autonome : activer, strate, hauteur, largeur, étincelle, icône (à droite, séparateur, art de bordure), « toujours afficher », animation lisse | Barre de lancement indépendante | oui | RB/CastBar:86-290 | partiel : barre d'incantation du cadre joueur, détachable avec mover, largeur et hauteur (options.md l.842-849) ; pas d'étincelle, strate | M |
| Bordure, étendues (haut/bas/gauche/droite), séparateur du bas, dégradé, texture, fond | Habillage de la barre | oui | RB/CastBar:298-726 | absent | G |
| Couleurs forcées : canalisation, non interrompable, « grisée hors de portée » | Couleurs selon le type d'incantation | oui | RB/CastBar:631-668 | partiel : couleurs « interruption prête » et « sort important » ; pas de couleur de canalisation ni de non interrompable (options.md l.801-806) | M |
| Texte du sort et minuteur : taille, décalages, durée totale, rang du sort (Forever) | Textes de la barre | oui | RB/CastBar:739-937 ; ERB_CastBar.lua:1352 | partiel : texte présent ; pas de réglage, ni de rang | M |
| Repères de canalisation (par tic), dernier tic, étages d'invocation colorés (Évocateur retail) | Tics de canalisation | oui (données Forever : Fouet mental, Pénitence) | RB/CastBar:937-1055 ; EllesmereUIResourceBars.lua:173-185 | équivalent partiel : « tops des canalisations » (options.md l.799) ; pas de dernier tic ; étages retail | — |
| Superposition de latence + texte de latence | Latence de lancement | oui | RB/CastBar:1055-1075 | partiel : zone de latence présente (options.md l.798) ; pas de texte | G |
| Barre GCD : position X/Y, orientation, « instance seulement », « incantations instantanées seulement », « toujours afficher », remplissage au repos, bordure, dégradé, texture, étincelle, « remplissage décroissant » | Réglages de la barre de recharge globale | oui | RB/GCD:63-445 | partiel : longueur, épaisseur, couleur seulement (options.md l.362-368) ; pas d'orientation verticale, de condition, d'étincelle, de bordure | M |
| Minuteur d'attaque : étincelle (largeur, dépassement, couleurs), lignes au repos, « masquer au repos », « toujours afficher les lignes », fusionner les mains, bouclier = main gauche, « masquer l'étiquette sans arme » | Détails du minuteur Forever | oui | RB/Swing:172-182,435-556 ; ERB_SwingTimer.lua:1-45 | partiel : une barre par arme, étiquette, temps, couleurs ; pas d'étincelle, de fusion des mains, de « masquer au repos » (SwingTimer.lua:19-31, options.md l.1590-1610) | M |
| Minuteur d'attaque : état d'attaque (en file, actif, en attente) avec couleurs, « en file sur la main droite seulement » | Retour visuel de l'attaque | oui | RB/Swing:595-624 | partiel : couleur « attaque en file » (QUEUED_SPELLS, SwingTimer.lua:39) ; pas d'état « en attente » | G |
| Minuteur d'attaque : guide de mouvement (zones GO/STILL pour Tir automatique et baguette, texte d'aide) | Aide à ne pas bouger au mauvais moment | oui | RB/Swing:637-654 ; ERB_SwingTimer.lua:25-35 | absent | M |
| Minuteur d'attaque : bordure, rayon de coin, dégradé, texture, fond, espacement des lignes, taille et position du texte, décalages X/Y, strate | Habillage du minuteur | oui | RB/Swing:55-430 | partiel : longueur, épaisseur, espacement (SwingTimer.lua:22-25) ; pas de position X/Y propre, ni du reste | G |
| Barre de totems (Chaman Forever) : taille, espacement, minuteur, bordure, orientation, strate, classes activées | Barre de totems indépendante | oui | RB/Totem:60-338 ; ERB_Totem.lua | partiel : barre de totems du cadre joueur (taille, mover, clic droit détruire, options.md l.844-846) ; pas d'espacement, de minuteur, de bordure, d'orientation | M |
| Barre d'appel des totems (Call of the Elements, Rappel totémique) reprise dans le même habillage | Réhabille la barre native MultiCast | oui (Forever, Chaman) | RB/Totem:396-407 ; ERB_CallTotemBar.lua:1-15 | absent (UnitFrames.lua:326-356 ne traite que les emplacements de totems) | M |
| Barre de charges du Guerrier (moteur) | Charges d'une compétence | retail (moteur 12.x, non vérifié Forever) | ERB_WarriorCharges.lua:1-8 | absent | — |

---

### Équivalents complets (une ligne)

Couleur de classe/réaction, soins entrants, tailles et visibilité par cadre, fondu hors combat avec opacité de portée, copie des réglages d'une unité à l'autre, barre de vie verticale, familier (puissance, humeur), repères de vie en %, couleurs par palier sous %, formats de texte `[cur]/[max]`, liste blanche/noire d'auras partagée, lueur sur les contrôles, totems sur le cadre joueur (base), barre d'incantation détachée avec latence et tops de canalisation, mode sombre, mover par cadre, visibilité par conditions des barres de ressources, repère de puissance, orientation commune, mana de druide (base), minuteur d'attaque de base (mains, étiquette, temps, portée, file).

### Limites client révélées

- Forever : la plage d'abréviation des nombres diffère (« rien sous 10 000 n'est abrégé ») : EUI emballe `AbbreviateNumbers` dans `EllesmereUI.ForeverAbbreviateNumbers` (EllesmereUIUnitFrames.lua:13, ERB_Update.lua:75 ; EllesmereUI_NumberFormat.lua:20,163). Notre UFE utilise `AbbreviateNumbers` brut (UFE:124-133) : rendu différent sur Forever (non vérifié en jeu).
- Forever : la mana est une valeur secrète ; l'étincelle de régénération et la prédiction de coût ne lisent jamais la valeur, seulement l'événement de lancement et le type de coût (EllesmereUI_ManaRegenSpark.lua:8-14 ; EllesmereUI_SpellCostPrediction.lua:10-14).
- Forever : les points de combo restent sur la cible ; leur lecture passe par `GetComboPoints` et un repeint au changement de cible (EllesmereUIResourceBars.lua:526-538 ; UF_ClassPower.lua:428).
- Forever : pas de spécialisations rétail ; les tables par spécialisation ne s'appliquent pas, EUI utilise une clé de chaîne pour le druide (UF_Text.lua:296-310 ; EllesmereUIResourceBars.lua:339-345).
- Forever : l'enchantement d'arme « imprégnation » est un type distinct et `C_PaperDollInfo.GetTemporaryEnchantmentInfo` ne le rapporte pas ; il faut `C_Item.GetWeaponEnchantInfo` (UF_ForeverImbues.lua:5-12).
- Forever : le minuteur d'attaque natif vient de Blizzard_SwingTimer (`PLAYER_SWING`, `C_SwingTimer.EnableRangeCheck`, `PLAYER_SWING_RANGE_UPDATE`, `Enum.PlayerSwingType`) ; le journal de combat n'existe plus en 12.x (ERB_SwingTimer.lua:4-12). La note d'options.md l.1594 (« pas de C_SwingTimer, module inactif ») concerne un client sans l'API, pas Forever (~/wow-ui-source/forever/Interface/AddOns/Blizzard_SwingTimer/Blizzard_SwingTimer.lua:35-70).
- Forever : la barre d'appel des totems est celle de Blizzard (`MultiCastActionBarFrame`), sécurisée ; EUI ne la modifie qu'hors combat et la repositionne avec les bases d'Edit Mode (ERB_CallTotemBar.lua:1-25).
- Retail seulement : art de ressource Blizzard (ERB_BlizzClassArt.lua:90,430) et options Fer-peau, Ignorer la douleur, Esprit arcanique, Chasseur/Chaman (RB/Class:103,1371,1388 ; RB/BarDisplay:1292).
- Cadre d'unité EUI : limite de 60 upvalues par fonction de page (SB, TS:`ns.UF_*` mis sur `ns`) : sans objet pour nous (limite de leur code).

### Non couvert

- Corps de code des fichiers `EUI_UnitFrames_AuraContainers.lua` (178 Ko), `EUI_UnitFrames_Absorb.lua`, `EUI_UnitFrames_Engine.lua`, `EUI_UnitFrames_Layout.lua`, `EUI_UnitFrames_Unlock.lua`, `EUI_PlayerAuraBars_Preview.lua`, `ERB_Update.lua` (163 Ko) : seuls les en-têtes et lignes gatées ont été lus.
- `UnitFrames_Options/UnitPreview_Options.lua` (aperçu des cadres, 224 Ko) : non lu (n'ajoute pas de réglages, il rend l'aperçu).
- Les infobulles et valeurs par défaut des réglages EUI n'ont pas été lues ligne par ligne ; les inventaires reposent sur les libellés `text=`/`label=`.
- Disponibilité Forever de `SetModel` (portrait 3D), des balayages d'aura 12.1 (`AuraKit`) et de l'API de réduction de vie max : non vérifiée.
- Notre code : seuls les en-têtes et les recherches ciblées (grep) ont été lus ; l'absence de « lissage », de lecture de combos sur la cible pour le cadre cible et d'enchantements d'arme repose sur un grep sur MuscaUI_UnitFrames/, Modules/UnitFrameElements.lua, Modules/AuraBars.lua.

## 5. Cadres de groupe et de raid

Légende chemins EUI : `RF/` = EllesmereUIRaidFrames/EUI_RaidFrames_ ; `OPT/` = EllesmereUIOptions/ ; `VB/VI/FP` = EllesmereUIOptions/RaidFrames_Options/{VisualBars,VisualIndicators,FramesPages}_Options.lua ; `MP` = EllesmereUIOptions/EUI_RaidFrames_ManagerPages.lua ; `RFO` = EllesmereUIOptions/EUI_RaidFrames_Options.lua.
Nous : GF = MuscaUI_GroupFrames/GroupFrames.lua, CC = MuscaUI_GroupFrames/ClickCast.lua.
Le .toc EUI cible 16001 (Forever) : tout le module charge sur Forever ; `IS_FOREVER` ne gate que des variantes (rangs de sorts, spec = classe) et le contenu Forever-only (Missing Buffs).

### 1. Click-cast (page « HoverCast »)

Nous : 8 liaisons fixes, nom de sort seul, bouton souris 1-5 + un modificateur (aucun/maj/ctrl/alt), globales à tous les persos, posées hors combat, cadres MuscaUI seulement, préréglage par classe (CC:1-30, options.md « Clic-sort »).

| Fonction | Ce qu'elle fait | Forever ? | Preuve EUI | Chez nous | Valeur |
|---|---|---|---|---|---|
| Liaisons clavier (touche + modificateurs) sur survol de cadre | Une touche du clavier lance le sort sur le cadre survolé (SetBindingClick via WrapScript OnEnter/OnLeave) | oui | RF/ClickCast.lua:1510-1539, 1677-1721 | absent (souris seulement) | H |
| Molette haut/bas comme déclencheur | MOUSEWHEELUP/DOWN capturés comme touche | oui | RF/ClickCast.lua:234, 655 | absent | M |
| Combinaisons de modificateurs (ALT-CTRL-SHIFT) | Plusieurs modificateurs à la fois, ordre canonique, META | oui | RF/ClickCast.lua:614-675, 685 | partiel (un seul modificateur, CC:44-46) | M |
| Nombre de liaisons illimité | Listes globales + par spec avec bouton « Add » | oui | RF/ClickCast.lua:3433-3471, 3702 | partiel (8 emplacements fixes, CC:11-15) | M |
| Liaisons par spécialisation | Jeu de liaisons par spec, fusionné aux globales | retail (Forever : spec = classe, id 0 « no spec », RF/ClickCast.lua:295-305, 2612) | RF/ClickCast.lua:311-322, 552-586 | absent (sans objet sur Forever) | G |
| Types d'action : sort, macro, objet équipé (trinket) | Une liaison peut lancer une macro du joueur ou un objet à usage | oui | RF/ClickCast.lua:1351-1440 (GetGlobalMacros, GetEquippedItems), page : onglets Spells/Macros/Items | absent (nom de sort seul) | H |
| Sélecteur de sort dans le livre de sorts + icônes | Liste des sorts de classe cliquable, icône et nom affichés | oui | RF/ClickCast.lua:1267-1350, 1189-1266 | absent (saisie texte du nom) | M |
| Quickbind : survoler un sort, presser une touche | Lie directement | oui | RF/ClickCast.lua:3751, 3795 | absent | M |
| Actions prédéfinies : Cible / Menu / Macro, + préréglages dispel, externe, rez | Choix « Action » et « Preset » par liaison | oui | RF/ClickCast.lua:67-135 (listes de sorts), page « Action »/« Preset » | partiel (préréglage « Remplir pour ma classe » : sorts de CC:28-40 par classe, CC:93-101, pas d'action Cible/Menu en remappage) | M |
| Rez dynamique / Smart Rez | Un seul bouton lance le bon rez (simple, de groupe, de combat, objet) selon l'état de la cible | partiel (Forever : pas de rez de groupe ni de rez de combat, RF/ClickCast.lua:137-169) | RF/ClickCast.lua:885-953, 1141-1188 | absent | M |
| Cible conditionnelle : Ami / Ennemi dans la même liaison | Un sort bienveillant et un sort hostile sur la même touche, fusionnés en une macro | oui | RF/ClickCast.lua:372-500, 842-868 | absent | M |
| Hovercast : « Cast On » Frames / Mouseover / les deux | Lance sur @mouseover, sur tout cadre d'unité ou le décor 3D, pas seulement les cadres du module | oui | RF/ClickCast.lua:349-359, 4682-4708 | absent | H |
| Cadres couverts : tous les cadres d'unité Blizzard + cadres EUI | Interrupteur « All Unit Frames » vs « EUI Raid & Party Frames » (joueur, cible, focus, pool de groupe Blizzard) | oui | RF/ClickCast.lua:2502-2560, 4488 | absent (cadres de groupe MuscaUI seulement) | M |
| Restrictions hors combat par type | « Only Cast / Open Menu / Target Out of Combat » par liaison | oui | RF/ClickCast.lua:1448-1465, 4612-4616 | partiel (écriture des attributs hors combat seulement, CC:67, pas de choix par liaison) | G |
| Contexte d'activation par liaison (solo, groupe, raid, champ de bataille/arène) | « Active In » | oui | RF/ClickCast.lua:324-348, 4630 | absent | M |
| Rangs de sorts Forever : choisir un rang précis ou suivre le plus haut | Proxy par rang via CastSpellByID | oui (Forever seulement) | RF/ClickCast.lua:748-841 | partiel (nom de sort sans rang : le plus haut part, CC:4 ; pas de rang épinglé) | M |
| Lier « Déclencher sur appui » (down) | Option globale AnyDown | oui | RF/ClickCast.lua:2135, 4460 | absent | M |
| Effacer le ciblage de sort coincé | Annule le curseur de ciblage après un sort sans cible (Rédemption) | oui | RF/ClickCast.lua:1081-1128, 4471 | absent | M |
| Détection de conflits de touches + liaison grisée si sort non connu / pas en talent | Avertit des doublons, grise les sorts non appris | oui | RF/ClickCast.lua:379-424, 2436-2496, 2487 | absent | M |
| Interop Clique (ClickCastFrames) | Cède ou récupère les cadres | oui | RF/ClickCast.lua:1722-1735, 2148-2181 | absent | G |
| Neutraliser les clics sans liaison (ne rien faire) / conserver cible+menu natif | Restaure le clic natif au retrait | oui | RF/ClickCast.lua:245-262, 1745-1770 | partiel (nous gardons cible/menu natifs, pas l'option « rien ») | G |
| Infobulle d'aura/sort avec touche modificateur | CC_SetTipModKey | oui | RF/ClickCast.lua:2051-2078 | absent | G |

Équivalents complets : liaison nom de sort + bouton 1-5 + un modificateur, préréglage de classe, gating hors combat, cible clic gauche / menu clic droit conservés.

### 2. Disposition, tailles, tri, groupes (pages Frames et Party)

Nous : largeur/hauteur groupe et raid, espacement unique, tri raid GROUP/CLASS/ROLE/NAME (ordre de classe fixe, GF:140 CLASS_ORDER), croissance membres/colonnes, groupes 1 à N, seuil raid, tanks/assistants principaux, cadres extra, boss alliés, groupe en ligne/colonne + croissance inversée, tri par rôle du groupe, afficher le joueur, afficher en solo (options.md « Groupe » et « Raid »).

| Fonction | Ce qu'elle fait | Forever ? | Preuve EUI | Chez nous | Valeur |
|---|---|---|---|---|---|
| Tailles par palier de raid (10/15/20/25/30/40) | Largeur, hauteur, croissance, décalages X/Y propres à chaque taille de raid, bornes « Covers Up To / Switch At » réglables | oui | FP:376-388, 572-720 | absent (une seule taille raid) | H |
| Interrupteurs « Exclure les groupes cachés du compte » | Les groupes masqués ne comptent pas pour le palier | oui | FP:1300 | absent | G |
| Auto-redimensionnement des icônes d'aura/indicateurs avec la taille du cadre | Échelle des icônes suivant la taille | oui | FP:685, 1728 | absent (tailles d'icônes fixes en px) | M |
| Mode compact / mode grille | Colle les cadres d'un groupe en un bloc bordé ; grille unique pour le raid | oui | FP:775, 787, 1755 ; RF/Compact.lua | absent | M |
| Espacement de groupes distinct de l'espacement de cadres (-5 à 15) | Deux espacements | oui | FP:754-759 | partiel (un espacement 0-20, options.md « Espacement entre les cadres ») | M |
| Style de bordure du cadre + options (décalage, derrière, rayon des coins) | Textures de bordure, rayon d'angle, décalage X/Y | oui | FP:803-885 | absent | M |
| Bordures survol/cible : taille réglable, style, couleur | Réglage de l'épaisseur et du type de bordure de survol et de cible | oui | FP:949-1037 | partiel (cible et survol on/off seulement) | G |
| Position du joueur : défaut / premier / dernier | « Self Position » (raid et groupe), nom-liste sécurisée | oui | FP:1131, 1708 ; RF/Sort.lua:1-30 | partiel (afficher le joueur on/off, mais pas premier/dernier) | H |
| Cacher le joueur dans le groupe distinctement du raid | « Hide Self » page Party | oui | FP:1720 | présent côté groupe (« T'afficher dans le groupe ») | - |
| Ordre des classes configurable + « Prioriser la classe » | Liste d'ordre de classe, priorité | oui | FP:1180-1199 ; RF/Sort.lua | absent (ordre fixe) | M |
| Tri par FrameSort (addon tiers) | Ordre fourni par FrameSort | oui | FP:1127 ; RF/Sort.lua:410-430 | absent | G |
| Tri séparé pour le groupe (partySortMode) | Mode de tri propre au groupe : groupe / rôle / etc. | oui | RF/EllesmereUIRaidFrames.lua:792 ; FP:1652 | partiel (rôle on/off seulement, GF « partySortRole ») | M |
| Fusionner les groupes (Merge Groups) | Un seul bloc plutôt qu'un bloc par groupe, tri global | oui | FP:1204 | partiel (un seul en-tête fusionné, GF:863-880 ; pas de mode un bloc par groupe) | M |
| Masquer les groupes vides (fermer les trous) | Les sous-groupes vides se referment | oui | FP:1292 | absent | M |
| Masquer groupes 5-8 en raid mythique (20 joueurs) | Gate retail | retail (raid mythique) | FP:1296 | sans objet | - |
| Ordre personnalisé des groupes | « Custom Group Order » : glisser les groupes | oui | FP:1239-1243, 1330 | absent (fixe 1→N) | M |
| Groupes affichés : sélection libre (ex. 1,2,3,6) | « Show Groups » liste cochable | oui | FP:1200, 1317 | partiel (plage 1 à N, GF « raidGroups ») | M |
| Style Blizzard / Classic WoW UI | Remplace l'habillage par le style stock (bordure, surbrillance de cible/menace, diviseur vie/puissance) sur raid, groupe, boss, extra, familiers et aperçu | oui | FP:1408 ; RF/Stock.lua:1-30 | absent | G |
| « Party Frames » : cadre de groupe stock à portrait, échelle, espacement, tailles de buff/débuff, ancres | Variante cadre de groupe 3D portrait façon Blizzard | oui | FP:1400-1490 ; RF/PartyLayout.lua | absent | G |
| Utiliser les réglages raid pour le groupe / les familiers / extras | Un seul profil de réglages | oui | FP:1513 | absent (réglages groupe et raid séparés partiellement) | M |
| Centrer en solo | Cadre joueur centré sur le cadre de groupe quand solo | oui | FP:1535 | absent | G |
| Croissance du groupe : défaut / inversée / centrée | Centrée garde les cadres centrés quand la taille change | oui | FP:1786 | partiel (défaut/inversée seulement, GF « reverse ») | M |
| Cadres de groupe dans les petits raids (< 10 : groupe 1 seul) | Raid de moins de 10 affiché en cadres de groupe | oui | FP:1801 | partiel (seuil raidThreshold : le groupe garde sa disposition jusqu'à N membres, mais n'efface pas les autres) | M |
| Taille groupe indépendante de l'aperçu : aperçu raid/groupe par taille | Aperçu en options par taille de raid | oui | RF/Preview*.lua ; FP:370 | partiel (aperçu membres, options.md « Aperçu ») | G |

### 3. Barres : vie, absorptions, puissance, texte

Nous : classe/réaction, dégradé rouge-vert, vertical, soins entrants + absorptions + soins absorbés (une case ; Modules/UnitFrameElements.lua:306-316), puissance par rôle + hauteur, barre d'incantation, portrait 2D, texture de barre globale par module (options.md « Barres », « Polices et textures »), nom (2 positions, longueur), texte de vie (liste de formats), mana des soigneurs en texte (GF:1213).

| Fonction | Ce qu'elle fait | Forever ? | Preuve EUI | Chez nous | Valeur |
|---|---|---|---|---|---|
| Couleur de vie : modes classe / personnalisée / dynamique à 3 couleurs (100 %, 50 %, 0 %) | Choix du mode et des couleurs | oui | VB:300-355 | partiel (classe ou dégradé fixe, pas de couleurs choisies) | M |
| Remplir avec la vie manquante | La barre grandit avec les dégâts | oui | VB:296 | absent | M |
| Opacité du remplissage, fond de barre (opacité, couleur, couleur de classe) | Réglages de fond | oui | VB:280, 315, 400-430 | absent | M |
| Lissage des barres de vie et de puissance | Animation douce | oui | VB:531, 1401 | absent | G |
| Opacité des soins entrants | Curseur 5-100 | oui | VB:475-478 | absent | G |
| Style d'absorption (une quinzaine de rendus), opacité, placement, sur-bouclier, ligne de lueur Blizzard | Visuel des absorptions | oui | VB:639-760 ; OPT/EUI_Textures_Options.lua:450-470 | partiel (un rendu blanc 35 %, UnitFrameElements.lua:306-308) | M |
| Barre d'absorption dédiée (hauteur, rendu, croissance verticale) | Barre séparée de la vie | oui | VB:794-860 | absent | M |
| Soins absorbés : style, opacité, placement, barre dédiée, « sur les dissipations », texte (taille/position) | Réglage séparé du heal absorb | oui | VB:869-1030, 1832-1923 | partiel (rouge fixe, UnitFrameElements.lua:310-312, pas de texte) | M |
| Réduction de vie max : style, opacité, rendu | Affiche la vie max réduite | oui | VB:1039-1085 ; RF/Absorb.lua:144, 781 | absent | M |
| Puissance : étendre la vie derrière la barre, icônes ignorent la barre, bordure propre, fond, hauteur par mode | Finitions | oui | VB:1253-1420 | partiel (hauteur + rôles) | G |
| Texte de puissance (taille, position, décalages) sur chaque cadre | Valeur de ressource | oui | VB:1725-1823 | absent (seulement le mana des soigneurs, GF:1213) | M |
| Mana des soigneurs : couleur, taille, espacement, alignement, sens | Bloc mana complet | oui | VI:1814-1900 | partiel (liste désactivé/groupe/raid/les deux) | G |
| Texte de vie : position 9 points, taille, décalages | Placement libre | oui | VB:1657-1672 | partiel (format seulement) | M |
| Nom : taille, couleur, décalages, 9 positions, nom au-dessus des icônes d'aura | Placement et couleur libres | oui | VB:1475-1590 | partiel (2 positions, longueur) | M |
| Format du nom : complet / premier mot / dernier mot | Raccourcit le nom | oui (Forever seulement) | VB:1549 ; RF/Colors.lua:368 | absent | G |
| Texte de niveau : position (attaché au nom ou libre), taille, décalages | Niveau de l'unité (défaut Forever : attaché au nom) | oui | VB:1684-1715 ; RF/EllesmereUIRaidFrames.lua:325 | absent (level=false codé en dur, GF:182) | M |
| Noms en raid, noms colorés par classe | Interrupteurs | oui | VI:1905-1915 | partiel (couleur de classe globale) | G |
| Barre de nom en haut (Top Name Bar) : hauteur, diviseur, fond, texte, alignement, position bas | Bandeau de nom | oui | VI:1101-1191 | absent | M |
| Portrait : modes classe/2D/3D, art, zoom, formes avec bordure, position, taille | Portrait riche | oui | RFO:107-360 ; RF/Portrait.lua | partiel (portrait 2D on/off) | M |
| Couleurs d'état (mort, hors ligne…) | Palette réglable | oui | VI:1967 | partiel (fond teinté on/off, couleurs fixes) | G |

### 4. Indicateurs, icônes, dissipations, cadres annexes, extras

Nous : icônes de rôle (style, taille, coin, par rôle, cacher en combat), chef, appel/invocation/rez (taille), marqueur de raid sans réglage (GF:662-664), dissipation (bordure, voile, lueur, filtre), menace (lueur/bordure), cible, survol, portée (opacité), sorts suivis par coin (4 coins, taille, mes sorts seulement, préréglage de classe).

| Fonction | Ce qu'elle fait | Forever ? | Preuve EUI | Chez nous | Valeur |
|---|---|---|---|---|---|
| Buffs manquants sur les cadres (Missing Buffs) | Sur chaque cadre de raid/groupe/extra, l'icône de chaque buff que le membre n'a pas et que le joueur peut lancer : Robustesse, Esprit, Marque du fauve, Épines, Salut, une bénédiction paladin par rôle ; Rois sur soi en solo | oui (Forever seulement) | RF/ForeverMissingBuffs.lua:1-58 ; VI:139-331 ; RF/EllesmereUIRaidFrames.lua:589-596 | partiel (Modules/Reminders.lua:38-84 : liste de membres sans ton buff dans la pile de rappels, hors combat ; aucune icône sur les cadres) | H |
| Missing Buffs : position, taille, décalages, interrupteur par buff, Épines sur le tank seulement, listes de bénédictions par rôle (tank/soigneur/dps) et exceptions par classe, lueur | Réglages détaillés | oui | VI:154-331 ; RF/ForeverMissingBuffs.lua:30-55 | absent | M |
| Icône de rôle : texte de rôle, derrière la bordure, position 9 points, décalages | Finitions | oui | VI:370-475 | partiel (style, taille, coin) | G |
| Marqueur de raid : position, taille, décalages | Icône de cible sur le cadre | oui | VI:496-525 | partiel (affiché, taille/position fixes, GF:662-664) | G |
| Appel/invocation/rez : position, décalages | Placement | oui | VI:555-579 | partiel (taille seulement) | G |
| Texte d'état AFK + taille/position | « Show AFK » | oui | VI:601-618 | absent (mort/hors ligne seulement) | M |
| Icône de chef : taille, décalages, afficher en combat | Réglages | oui | VI:657-696 | partiel (on/off) | G |
| Icône de combat : taille, style, couleur de classe, décalages | Icône « en combat » sur chaque cadre | oui | VI:730-770 | absent | G |
| Numéros de groupe (raid) : taille, décalages | Numéro du sous-groupe | oui | VI:797-828 | absent | M |
| Marqueur de ping : taille, décalages | Ping de groupe (C_Ping) | ? (C_Ping existe dans le source Forever, mais le contenu ping joueur n'est pas tranché) | VI:854-883 | absent | G |
| Dissipation : opacité du voile, bordure, icône de type (position/taille/décalages), bordure d'icône de débuff, couleurs des types | Visuels de dissipation | oui | VI:977-1088 | partiel (bordure, voile, lueur on/off, couleurs fixes) | M |
| Bordure de menace : épaisseur 0-4, recoloration de la bordure | Réglage | oui | VB:534-549 | partiel (style lueur/bordure) | G |
| Cadres extra : raccourci « ajouter au groupe extra », exclure moi-même, position libre ou attachée, sens de croissance, retour à la ligne après N, taille propre, redimensionnement auto | Gestion complète des extras | oui | VI:1399-1590 ; RF/ExtraFrames.lua | partiel (tanks par rôle ou liste de noms, GF « extraFrames/extraNames », options.md « Cadres extra ») | M |
| Cadres des boss alliés : position attachée/libre, afficher en donjon, couleur de vie du boss, orientation, tailles propres | Réglages boss1-5 | oui | VI:1253-1384 ; RF/BossFrames.lua:1-45 | partiel (on/off, GF « friendlyBoss ») | M |
| Boss alliés : affichage « toujours / soigneurs seulement » ; sort de portée du soigneur (Forever) | Visible seulement si la classe soigne | oui (Forever : table FOREVER_HEAL_SPELLS) | RF/BossFrames.lua:155-165, 951 | absent | M |
| Cadres des familiers : en-tête de familiers groupe/raid ou un familier à côté de son propriétaire ; position, taille, sens, côté | Vie, nom, portée, bordures, clic-cast | oui | RF/PetFrames.lua:1-20 ; VI:1603-1711 | absent | M |
| Cibles de groupe : un bouton cible à côté de chaque cadre de groupe, « inclure ma cible », couleur, fond, taille, position, décalages | Cible de chaque allié, ciblage sécurisé | oui | RFO:364-600 ; RF/PartyTargets.lua:1-30 | absent | H |
| Infobulles : unité au survol, buffs, touche modificateur, réglages | Infobulle sur cadre/aura | oui | VI:1768-1797 ; MP « Tooltips » | absent (aucun GameTooltip dans GroupFrames.lua, grep) | M |
| Déverrouillage de la caméra au clic droit | Option | oui | VI:1979 | absent | G |
| Strate des cadres | Réglage de strate | oui | VI:1983 | absent | G |

### 5. Gestionnaire de buffs (page « Buff Manager »)

Nous : « Sorts suivis » : 4 coins fixes, identifiants de sorts séparés par des virgules, le premier buff trouvé s'affiche, taille d'icône unique, « mes sorts seulement », préréglage de classe (GF:56-59 ; options.md « Sorts suivis »). Auras : buffs optionnels après les débuffs, position/taille/nombre (options.md « Auras »).
EUI : modèle indicateur -> filtres -> sorts, par spécialisation (Forever : une seule vue « All Specs » + bucket de la classe, RF/BuffManager.lua:321, 1546, 2298 ; RF/BuffManager2.lua:634, 1017).

| Fonction | Ce qu'elle fait | Forever ? | Preuve EUI | Chez nous | Valeur |
|---|---|---|---|---|---|
| Indicateurs multiples placés librement (jusqu'à 20 par spec) | Un indicateur = un jeu de sorts + position 9 points + décalages + taille | oui | RF/BuffManager.lua:1-12, 40-52 | partiel (4 coins fixes, GF:56-59) | H |
| Types d'indicateur : icône, carré (couleur par sort), barre | Trois rendus placés | oui | RF/BuffManager.lua:40-45 ; 3892, 4035-4110 | partiel (icône seulement) | M |
| Types d'indicateur à effet : couleur de la barre de vie, couleur de fond, bordure du cadre (largeur, style, tirets), opacité du cadre | Teinte tout le cadre quand un buff est présent | oui (présence seulement ; alpha non créable) | RF/BuffManager.lua:45-52, 4189-4350 | absent | M |
| Mode « Afficher quand » : présent / tous présents / un absent / tous absents | Absence d'un buff signalée | partiel (modes d'absence retirés des effets sur 12.1 : RF/BuffManager.lua:120-130) | RF/BuffManager.lua:120-130 ; 4189 | absent | M |
| Filtres nommés de sorts (10 préréglages : Défensifs, CD de raid, Externes, Soins principaux/secondaires, Offensifs, Mouvement, Utilitaire, Consommables ; filtres personnalisés ; case par sort) | Assigne un jeu de sorts à un indicateur | oui (catalogue vanilla dédié) | RF/BuffManager2.lua:1-45 ; EllesmereUI/EllesmereUI_BuffPresets.lua:1-38 | absent (liste d'ids à la main) | H |
| Éditeur de filtres, sélecteur « Spells », ajout par ID, recherche dans les sorts préréglés | Interface de curation | oui | MP:2906, 3552-3690 ; RF/BuffManager2.lua:98-115 | absent | M |
| Familles de buffs de groupe Forever (tous les rangs d'un même buff regroupés) | Un buff = tous ses rangs/identifiants | oui (Forever seulement) | EllesmereUI/EllesmereUI_BuffPresets.lua:7-8 ; RF/BuffManager2.lua:102-110 | partiel (« tous les rangs d'un sort comptent, lus par nom », options.md « Sorts suivis ») | M |
| Ordre personnalisé des buffs par indicateur | Priorité d'affichage | oui | MP:3788-3841 | absent (ordre de saisie) | M |
| Buffs de rôles/classe : « Show In » (tous, soigneurs, non-soigneurs, rôle) | Cibler un jeu de membres | retail en partie (rôles : pas de rôle de spec sur Forever, RF/BuffManager.lua:355 ; classes oui) | MP:3721 ; RF/BuffManager.lua:355, 425 | absent | G |
| Seulement mes buffs (Own Only) par indicateur | Filtre par lanceur | oui | RF/BuffManager.lua:3505 | partiel (une case globale « Seulement mes sorts ») | M |
| Texte de seuil de durée (secondes) | Affiche la durée sous un seuil | oui | RF/BuffManager.lua:3532-3535 | absent (durée par recharge seulement) | G |
| Aspect de l'icône : taille, espacement, zoom, opacité, balayage de durée, texte de durée/stacks (taille), icônes par ligne, max, sens de croissance, niveau de cadre | Réglage fin d'un indicateur | oui | RF/BuffManager.lua:3635-3830 | partiel (taille d'icône globale seulement) | M |
| Lueur de l'icône (types, couleur, paramètres, partagée avec Glows) | Glow sur indicateur | oui | RF/BuffManager.lua:3879 ; OPT/EUI_Glows_Options.lua | absent | G |
| Bordure « pandemic » | Rappel de fenêtre de rafraîchissement | retail (RF/AuraContainers.lua:1205) | RF/BuffManager.lua:3976-4020 | absent | - |
| Indicateurs dans le groupe et les cadres extra, aperçu en options | Même config pour groupe, raid, extra | oui | RF/BuffManager.lua:1-12 | partiel (raid et groupe partagent la config) | G |
| Sets de défaut selon la spécialisation (ex. « Core Healing Buffs » en haut à gauche, « Lesser » en haut à droite, « Defensives & Utility » au centre) | Amorçage automatique | oui (Forever : par classe) | RF/BuffManager2.lua:1-24 | partiel (préréglage de classe sur 4 coins) | M |

### 6. Gestionnaire de débuffs (page « Debuff Manager »)

Nous : auras (on/off), position INSIDE/ABOVE/BELOW, taille, nombre 1-16, filtre unique `all/mine/important/dispellable/boss` (Core/Compat.lua:535), buffs après débuffs (options.md « Auras »). Pas de durée/pile spécifiques cités dans options.md pour le groupe.

| Fonction | Ce qu'elle fait | Forever ? | Preuve EUI | Chez nous | Valeur |
|---|---|---|---|---|---|
| Grille de base : cases cumulables « Non-joueur, Important, Contrôle, Boss, Rôle, Raid, Raid en combat, Dissipables par moi, Dissipations, Tous, Avec durée » | Combinaison de catégories, chaque aura rendue une fois | oui (jetons de filtre CROWD_CONTROL/RAID/RAID_IN_COMBAT dans RF/DebuffManager.lua:239-241 ; absents du source local Forever : non vérifié) | MP:257-354 ; RF/DebuffManager.lua:1-40, 239 | partiel (un seul filtre à choix unique) | H |
| Filtres moins courants : lancé par moi, de tout joueur, par type (Magie, Malédiction, Poison, Maladie, Saignement), « Peut appliquer l'aura » | Filtres fins | oui (même réserve) | MP:344-354 | partiel (dissipable seulement) | M |
| Mode de correspondance : « n'importe quel » / « tous » (conjonction) | Combine des catégories | oui | MP:393 ; RF/DebuffManager.lua:1-40 | absent | M |
| Tuiles d'icônes assignées (plusieurs groupes de débuffs avec ancre, taille, plafond propres) | Un conteneur par catégorie : ex. CC au centre, boss en haut | oui (par classe sur Forever : « All Specs + bucket de la classe », RF/DebuffManager.lua:3474-3510, 3563) | MP:680-1135 ; RF/DebuffManager.lua:1-40 | absent | H |
| Tuiles d'effet : lueur, carré, couleur de vie, barre (une catégorie -> un signal visuel) | Signal additif | oui | MP:547-680, 1356-1503 ; RF/DebuffManager.lua:25-33 | partiel (voile/lueur dissipation seulement) | M |
| Taille, max, zoom, position 9 points, décalages, icônes par ligne, espacement, sens de croissance | Réglages d'aspect des débuffs | oui | MP:927-995 | partiel (taille, nombre, 3 positions) | M |
| Texte de durée, piles (taille, décalages), balayage de durée, infobulle (modificateur) | Affichage des débuffs | oui | MP:997-1105 | partiel (non vérifié : durée/piles du groupe absentes d'options.md) | M |
| Style de bordure des auras (texture, anneau de dissipation texturé, couleurs) | Bordure des icônes de débuff | oui | MP:79-155 | absent (couleur de type fixe) | G |
| Masquer l'épuisement (Hide Exhaustion) | Cache Épuisement/Pré-fatigue | retail (Héroïsme/BL) : sur Forever, Furie existe en Shaman (Épuisement partiel) non vérifié | MP:717 | absent | G |
| Configuration par spec / par rôle + héritage entre « All Specs », rôle et spec | Jeux de tuiles par bucket | retail (Forever = « All Specs » + classe) | RF/DebuffManager.lua:3474-3640 | absent | G |

### 7. Autre tank, recharges de raid, utilitaire de raid

Nous : Modules/CoTank.lua (barre cliquable de l'autre tank, débuffs sous la barre), Modules/RaidCooldowns.lua (charges de rez en combat, affaiblissement Rassasié/Héroïsme ; options.md « Recharges de raid » 1849-1858).
EUI : aucune fonction équivalente de barre « autre tank » ni d'icône de rez de combat trouvée dans mon zone (grep `battle res|co-tank|other tank` : 0 résultat hors listes de débuffs). Fonctions EUI liées :

| Fonction | Ce qu'elle fait | Forever ? | Preuve EUI | Chez nous | Valeur |
|---|---|---|---|---|---|
| Masquer les débuffs de type Rassasié/Épuisement sur les cadres (« Show Lust Debuff ») | Retire le bruit Héroïsme des grilles de débuffs | oui | RF/AuraContainers.lua:30-36, 1033 ; RF/DebuffManager.lua:1354-1364 | absent (aucun filtre de ces ids sur les cadres de groupe ; RaidCooldowns les suit côté joueur, Modules/RaidCooldowns.lua:27) | G |
| Exclusion interne de bruit (Forbearance, etc.) des grilles | Liste codée en dur d'auras jamais affichées | oui | RF/DebuffManager.lua:73, 1568 | absent | G |

Équivalent EUI du CoTank et de RaidCooldowns : non trouvé dans ma zone (voir « Non couvert » pour les autres addons EUI).

### Équivalents complets

Cible au clic et menu, icônes de rôle/chef/ready check/invocation/rez (présence), bordure/remplissage/lueur de dissipation, bordure de menace, surbrillance cible/survol, alpha hors portée, couleur de classe, dégradé, barre verticale, prédiction de soins, puissance par rôle, barre d'incantation, portrait 2D, texte de nom/vie, mana des soigneurs, masquage des cadres Blizzard, tanks supplémentaires (extra), cadres de boss on/off, groupes/colonnes/seuil/tri de base.

### Limites client révélées

- Alpha du cadre par aura impossible : la présence d'aura est secrète en combat (RF/BuffManager.lua:52-56).
- Indicateurs à effet : présence seulement, les modes « absent » sont retirés car SetShown sur un secret lève une erreur sur boutons scriptés (RF/BuffManager.lua:120-130).
- Forever : pas de bucket spec/rôle pour les buffs (RF/BuffManager.lua:355, 425) ni pour les débuffs (RF/DebuffManager.lua:3474-3622).
- Forever : bordure pandemic retirée (RF/AuraContainers.lua:1205).
- Forever : pas de rez de groupe/combat pour le click-cast intelligent (RF/ClickCast.lua:137-169) ; sorts à rangs gérés via table (RF/ClickCast.lua:756).
- Attributs sécurisés (click-cast) modifiables hors combat seulement (RF/ClickCast.lua:1448).
- Cibles de groupe (party targets) : aucune mutation protégée en combat (en-tête RF/PartyTargets.lua).
- Jetons de filtre d'aura CROWD_CONTROL / RAID_IN_COMBAT utilisés par EUI (RF/DebuffManager.lua:239-241) : non trouvés par nom dans le source Forever local, disponibilité non vérifiée.

### Non couvert

- RF/Events, Lifecycle, Reload, Visibility, Update, fichiers Preview* : non lus (en-têtes seulement).
- Pages ManagerPages : lues par libellés et plages, pas ligne à ligne.
- Disponibilité sur Forever de C_Ping et des jetons de filtre d'aura : non vérifiée (agent wow-api non lancé).
- EUI Cooldown Manager et autres addons EUI (rez de combat éventuel) : hors zone.
- Numéros de ligne des sections 1-6 : plages approximatives sur les gros fichiers (non revérifiées une à une).

## 6. Plaques de nom et rappels

Chemins EUI relatifs à /home/ludovic/Téléchargements/EllesmereUI-v9.6.8. Abréviations : GP = EllesmereUIOptions/Nameplates_Options/GeneralPage_Options.lua, DB = DisplayBars_Options.lua, DL = DisplayLayout_Options.lua, CP = ColorsPage_Options.lua (même dossier), ABR = EllesmereUIOptions/EUI_AuraBuffReminders_Options.lua. Chez nous : NPF = MuscaUI_Nameplates/NamePlateFrames.lua, UFE = Modules/UnitFrameElements.lua, REM = Modules/Reminders.lua. Rien ici n'a été testé en jeu.

### 1. Plaques : général, amis, PNJ, espacement

| Fonction | Ce qu'elle fait | Forever ? | Preuve EUI | Chez nous | Valeur |
|---|---|---|---|---|---|
| Empilement : stacking, espacement, vitesse, marge haute d'écran | Règle le chevauchement des plaques et leur marge en haut d'écran | ? | GP:515-519, GP:631, GP:649 | absent (seul CVar nameplateMotion posé dans Config/FirstRun.lua:19) | M |
| Taille de hitbox X/Y | Agrandit la zone cliquable des plaques | ? | GP:562, GP:570 | absent | G |
| Distance du nom à la barre | Décale le nom | oui | GP:494 | absent | G |
| Plaques amies : barre/nom colorés classe, taille, % vie, bordure cible | Réglages détaillés des plaques de joueurs amis | oui | GP:122-161 | partiel (case « vie amie » seule, options.md « Plaques de nom ») | M |
| Mode nom seul amis | Affiche le nom sans barre sur les amis | oui | GP:98 | absent | M |
| Sous-titre (titre/guilde/les deux), couleur guilde, crochets | Texte sous le nom | oui | GP:292-339 | absent | G |
| PNJ amis : titres, tailles, couleurs | Réglages des plaques de PNJ amis | oui | GP:357-423 | partiel (activer/désactiver via CVAR_RULES NPF) | G |
| Noms amis non cliquables | Rend les plaques amies traversables | ? | GP:474 | absent | M |
| Masquer plaques ennemies hors combat | Cache les ennemis hors combat | oui | GP:1287 | partiel (assombrir hors combat seulement) | M |
| Vérif. de portée Désactivé/Auto/Perso + opacité hors portée | Choix de la méthode de portée | oui | GP:1211-1263 | partiel (portée 20-60 + alpha, pas de mode Auto par classe) | G |
| Opacité hors ligne de vue | Atténue les plaques sans LOS | ? | GP:1179 | absent | M |

### 2. Plaques : barres de vie et d'incantation

| Fonction | Ce qu'elle fait | Forever ? | Preuve EUI | Chez nous | Valeur |
|---|---|---|---|---|---|
| Icône de sort : échelle, décalages, sur la droite, pleine taille, bordure, couleur bordure cible | Réglages de l'icône d'incantation | oui | DB:106-218 | partiel (icône présente, aucun réglage) | G |
| Fond, bordure, texte de durée, décalage Y de la barre d'incantation | Habillage de la barre | oui | DB:241-324 | partiel (pas de texte de durée trouvé dans UFE ; fond/bordure absents) | M |
| Étincelle, icône de bouclier incantation non interrompible | Marqueurs visuels de la barre | oui | DB:387-532 | partiel (grisé 0.6 non interrompible, UFE:1093-1130 ; pas d'étincelle ni bouclier) | G |
| Repère/remplissage « interruption prête » en cours d'incantation | Trait sur la barre à l'instant où le kick sera prêt | ? | DB:387-532 ; EUI_Nameplates_Cast.lua:505-575, :572 (« API not available; hide tick ») | partiel (couleur interruption prête, options.md) | M |
| Incantations devant les plaques | Passe la barre de cast au-dessus des autres plaques | oui | DB:563 ; EllesmereUINameplates_CastOverlay.lua (reparent en strate HIGH) | absent | M |
| Échelle pendant l'incantation, masquer le nom ennemi pendant l'incantation | Met en avant l'incantation | oui | GP:1094, GP:1102 | absent | G |
| Verrou d'incantation affiché comme icône de CC (4 s génériques) | Icône après interruption réussie | oui | GP:1139 | absent | G |
| Texte nom de sort / cible du sort : taille, côté, largeur, retour à la ligne | Réglages texte de cast | oui | DB:1814-1960 | partiel (texte de sort présent, réglages absents) | M |
| Rappels de focus (texte) | Texte à l'écran sur le focus qui incante | oui | DB:626 | absent | G |

### 3. Plaques : cible, focus, survol

| Fonction | Ce qu'elle fait | Forever ? | Preuve EUI | Chez nous | Valeur |
|---|---|---|---|---|---|
| Échelle de la cible, opacité des non-ciblées, focus gardé opaque | Distingue la cible | oui | GP:882, GP:893, GP:927 | absent | M |
| Focus : couleur, texture, lettre, hauteur de cast | Distingue le focus | oui | GP:944-1006 ; DB:1043-1292 | absent | M |
| Effet de cible : flèches, lueur, surbrillance, bordure (styles, couleurs) | Indicateur de cible multi-styles | oui | DB:718-955 | partiel (chevrons dans MuscaUI_Nameplates/Nameplates.lua + case surbrillance) | G |
| Couleur/texture de recouvrement cible et focus | Habillage de cible | oui | DB:1043-1292 | absent | G |
| Effet et texture de survol | Surligne la plaque sous la souris | oui | DB:1403-1577 | absent | G |
| Trait de seuil de vie (hash line à X %) | Marque un seuil sur la barre de vie | oui | GP:814, GP:822 | absent | G |
| Texte distance à la cible | Affiche la distance sur la plaque | ? | GP:1020-1074 | absent | G |
| Pulsation d'exécution < 30 % | Lueur en phase d'exécution | oui | GP:1280 | partiel (règle de style « vie sous X » peut mettre une lueur, options.md) | M |

### 4. Plaques : texte et positions

| Fonction | Ce qu'elle fait | Forever ? | Preuve EUI | Chez nous | Valeur |
|---|---|---|---|---|---|
| Six emplacements de texte libres (haut/droite/gauche/centre/bas-g/bas-d) avec 13 éléments (nom, niveau, ToT, 9 formats de vie…) | Place librement chaque texte | oui | DL:2751 | partiel (nom, niveau, vie à positions fixes ; liste de formats de vie dans options.md) | M |
| Réglages par emplacement : taille, décalages, strate, couleur/classe, largeur %, retour ligne, décimales | Détail du texte | oui | DL:2751-2960 | absent | G |
| Format du nom : premier/dernier mot | Raccourcit le nom | oui (Forever) | DL:2897 ; EUI_Nameplates_Layout.lua:750 ; EllesmereUINameplatesFriendly.lua:672-700 | absent | G |
| Couleur personnalisée nom/niveau, couleur de difficulté du niveau | Colore le texte | oui | CoreTextColoring_Options.lua | absent | G |
| Case de niveau (Forever) | Boîte de niveau style stock | oui | DL:775 ; EUI_Nameplates_Styles.lua:144-159 | absent | G |
| Abréviation de nombres propre à Forever | Format des grands nombres | oui | EUI_Nameplates_Health.lua:29-31 | ? (non vérifié chez nous) | G |

### 5. Plaques : auras, emplacements, indicateurs

| Fonction | Ce qu'elle fait | Forever ? | Preuve EUI | Chez nous | Valeur |
|---|---|---|---|---|---|
| Six emplacements (haut/droite/gauche/haut-d/haut-g/bas) pour débuffs, buffs, CC, marqueur, rare/quête, faction | Place chaque famille d'icônes | oui | DL:795 | partiel (une seule rangée au-dessus, débuffs/buffs, + emplacement CC, options.md) | M |
| Par emplacement : taille, décalage, croissance, strate, espacement, icônes rognées + %, sans bordure, en instance | Détail d'affichage des icônes | oui | DL:795-2168 | partiel (taille seule) | G |
| Listes d'inclusion/exclusion par ID de sort (NPF_Include/NPF_Exclude), « tous les débuffs » | Force ou bloque des auras précises | oui | DL:2168 ; popups NPF_Include/NPF_Exclude | absent (filtre all/mine/important/dispellable/boss seulement) | H |
| Nombre max de débuffs | Limite l'affichage | oui | GP:677 | absent | M |
| Tooltips d'aura | Info-bulle au survol | oui | GP:706 | absent | G |
| Lueur de pandémie | Lueur quand l'aura va expirer | oui | GP:723 ; EUI_Nameplates_Options.lua:239-340 | absent | M |
| Filtre de buffs ennemis important/dispellable/tout | Filtre dédié aux buffs ennemis | oui | GP:780 ; EllesmereUINameplates.lua:484 | partiel (filtre commun aux auras) | G |
| Texte de durée et de piles : police, taille, position | Réglage du texte d'aura | oui | DB:1814-1960 | partiel (cooldown + compteur présents dans UFE, pas de réglage) | M |
| Lueur dispel | Marque les buffs dispellables | oui | EUI_Nameplates_Options.lua:239-340 | partiel (surbrillance dispel UFE) | G |
| Marqueur de raid : emplacement/taille, marqueur dans le nom | Place l'icône de cible | oui | DL:795 ; GP:1130-1156 | partiel (icône via UFE, pas de position/taille) | G |
| Indicateur rare/élite/quête, badge de faction, drapeau JcJ | Icônes d'état | oui | DL:795 ; EllesmereUINameplates_Faction.lua | partiel (icône de quête, classification en couleur) | G |
| Remplacer l'icône de quête par l'objectif | Affiche l'objectif au lieu de l'icône | oui | GP:1170, GP:1196 ; EllesmereUINameplates.lua:489 | absent | G |
| Sunder Armor (guerriers Forever) | Compteur de Sunder sur les plaques | oui | GP:1316-1318 ; EUI_Nameplates_AuraContainers.lua:714 | absent | M |
| Masquer les copies de Blood Plague | Retire les doublons DK | retail | GP:1304 | absent | G |

### 6. Plaques : couleurs, menace, débuffs

| Fonction | Ce qu'elle fait | Forever ? | Preuve EUI | Chez nous | Valeur |
|---|---|---|---|---|---|
| Coloration par débuff (plaque ou bordure, mes débuffs, bordure extra, lignes sort/combo) | Colore selon un débuff posé | oui (sans préréglages) | CP:310, CP:159, CP:665-706 ; EllesmereUINameplates_DebuffColors.lua | absent | M |
| Couleurs d'ennemi : types, neutres, mini-ennemis, hors combat | Palette par type | oui | CP:1264 | partiel (couleurs de classification, options.md) | G |
| Couleur mob de quête | Colore les mobs de quête | oui | CP:1264 | absent | M |
| Menace : lueur proche aggro, tank classique, surcharges boss/caster, « afficher la menace sur » | Variantes de couleur de menace | oui | CP:1469 | partiel (7 couleurs de menace + rôle, options.md ; états tank/dps NPF) | M |
| % de menace et écart de menace sur les plaques (position, texte, couleur, taille) | Texte de menace | oui (Forever seulement) | CP:1780, CP:1828, CP:39 ; EUI_Nameplates_Overlays.lua:542, :620 | absent | M |
| Détection du tank (formes guerrier/druide, Fureur Juste 25780, rôle de groupe) | Sait si le joueur tanke | oui | EUI_Nameplates_Colors.lua:124-140 | partiel (réglage manuel du rôle, options.md) | M |
| Couleur du second tank sous restriction d'identité | Colore l'autre tank | oui | EUI_Nameplates_Colors.lua:33 | partiel (otherTankColor des chevrons seulement) | G |
| Simple coloring / mini coloring M+ | Variantes M+ | retail | CP:1264 | absent | G |

### 7. Plaques : ressource de classe, styles, préréglages

| Fonction | Ce qu'elle fait | Forever ? | Preuve EUI | Chez nous | Valeur |
|---|---|---|---|---|---|
| Ressource de classe sur plaque : points de combo Voleur/Druide, couleur, position, taille, espacement, fond, forme, bordure | Points de combo sur la cible | oui | DB:1599-1790 ; EUI_Nameplates_ClassPower.lua:836-870 | partiel (case combo seule, options.md) | M |
| Style de bordure (aucune/basique/perso), taille, rayon d'angle, ligne de séparation, textures perso | Habillage de la barre | oui | DL STYLE (DL:~700-795) | absent | G |
| Fond, style d'absorption, texture de barre et de cast, fond texturé | Habillage de la barre | oui | DL STYLE ; EUI_Nameplates_Options.lua:1107 | partiel (absorption affichée par UFE, aucun réglage de style) | G |
| Variantes de style stock Blizzard/Classic/Forever | Reprend l'apparence de plaque stock | oui | EUI_Nameplates_Styles.lua:376 | absent | G |
| Préréglages par spé, et classe vue comme chaque spé sur Forever | Profils d'affichage/couleur par spé | oui | EUI_Nameplates_Init.lua:45-60 ; EUI_Nameplates_Options.lua:1224-1243 | absent | M |

### 8. Rappels d'auras et de buffs (module EUI ABR, réduit sur Forever)

| Fonction | Ce qu'elle fait | Forever ? | Preuve EUI | Chez nous | Valeur |
|---|---|---|---|---|---|
| Affichage en icônes : échelle, sens de croissance, espacement, strate, décalage Y, opacité | Présentation en icônes | oui | ABR CORE/DISPLAY | partiel (pile de 6 lignes de texte MAX_LINES, REM) | M |
| Bordure d'icône (style, taille), nom, compteur d'objet, tooltips | Habillage des icônes | oui | ABR DISPLAY | absent | G |
| Lueur de rappel | Lueur sur l'icône | oui | ABR DISPLAY | absent | G |
| Rattacher les rappels importants au curseur (option combat seul) | Suit la souris | oui | ABR DISPLAY | absent | G |
| Où afficher : Monde ouvert / Donjons / Raids / En combat | Filtre de contexte par section | oui | ABR:1681 (section WOW FOREVER), RAID BUFFS | partiel (hors combat seulement ; « sauter en repos » ; Well Fed donjon/raid, options.md « Rappels ») | M |
| Quand afficher : « il manque mon buff chez d'autres » / « il me manque des buffs d'autres » | Logique fournisseur de buff | oui | ABR RAID BUFFS ; EUI_AuraBuffReminders_Refresh.lua:265-300 | partiel (couverture de groupe COVERAGE_RULES, REM) | M |
| Grille de buffs de raid par buff (Marque du fauve 1126, Cri de guerre 6673 auto-lancé, Mot de pouvoir : Robustesse 1243, Intelligence des arcanes 1459) | Active chaque buff individuellement | oui | ABR RAID BUFFS | partiel (règles de classe CLASS_RULES, REM) | M |
| Avantages de camp (buff 1229741) | Rappel du buff de camp | oui | ABR:1681 ; EUI_AuraBuffReminders_Defaults.lua | absent | M |
| Groupes de sorts personnalisés (un rappel tant qu'aucun ID actif), renommer/retirer, familles de rangs FOREVER_BUFF_FAMILIES | Rappel « un parmi N » avec rangs | oui | ABR:966-1012 ; EUI_AuraBuffReminders_Refresh.lua:850 | partiel (IDs personnalisés simples, REM) | M |
| Son par section | Son distinct par type de rappel | oui | EUI_AuraBuffReminders_Defaults.lua:~200-255 | partiel (un seul son, options.md) | G |
| Clic milieu : masquer jusqu'au prochain écran de chargement | Ignore un rappel pour la session | oui | EUI_AuraBuffReminders_Icons.lua | absent | M |
| Bouton sécurisé de pose du buff sur un membre (rang et membre liés) | Clic pour lancer le buff | oui | EUI_AuraBuffReminders_Icons.lua:499-535 | partiel (bouton sécurisé CastButton présent, sans choix de membre/rang) | M |
| Mode Unlock sur page dédiée | Déplace le cadre | oui | EUI_AuraBuffReminders_Unlock.lua | partiel (bouton unlock présent, options.md) | G |
| Auras, consommables, poisons, rites, imprégnations, familiers, démoniste, rappels de talents, Beacon M+, seuils d'expiration, alerte mana ready-check | Sections complètes | retail | ABR sections ; EllesmereUIABR_TalentReminders.lua (retour immédiat sur Forever) | absent | G |

### Équivalents complets

Largeur/hauteur des barres, nom, niveau, liste de formats du texte de vie, barre d'incantation avec icône et couleur important, flash d'interruption, débuffs/buffs au-dessus, filtre all/mine/important/dispellable/boss, plaques de familiers, masquer noms du monde, classe en couleur, masquer Blizzard, assombrir hors combat, atténuation par portée, rôle de menace, règles de style (NPF), Well Fed 19705 (donjon/raid), IDs de buff personnalisés, bouton cliquable, un son. Rappels que nous avons en plus : stance, camouflage, familier, Forme d'ombre, Fureur Juste, durabilité, sacs pleins, texte perso.

### Limites client révélées

- Points de combo renvoyés en valeur secrète sur Forever : EUI_Nameplates_ClassPower.lua:508
- kickProtected est un booléen secret : EUI_Nameplates_Cast.lua:415
- Valeurs de menace lues via un token de plaque sont secrètes ; lecture via « target » seulement : EUI_Nameplates_Overlays.lua:620
- GUID de l'interrupteur secret, nom/classe possibles secrets via GetPlayerInfoByGUID : EUI_Nameplates_Cast.lua:656
- Rôle de la cible du mob secret sous restriction d'identité : EUI_Nameplates_Colors.lua:33
- Lecture des auras de raid ignorée tant qu'un rang est secret : EUI_AuraBuffReminders_Refresh.lua:265-300
- Ne pas parenter sur les frames C_NamePlate de Blizzard (taint) : EllesmereUINameplates.lua:40
- Aucune API de durée de reprise exploitable pour le repère kick : EUI_Nameplates_Cast.lua:572 (non vérifié côté Blizzard Forever)
- GetSpecialization non enregistré sur Forever : EUI_AuraBuffReminders.lua:120

Ces faits n'ont pas été comparés à la base de connaissances existante : leur caractère « nouveau » n'est pas vérifié.

### Non couvert

- Sources non lues en détail : EllesmereUINameplates_Faction.lua, EUI_Nameplates_Styles.lua hors lignes citées, Nameplates_Options hors pages General/DisplayBars/DisplayLayout/Colors/CoreTextColoring, Pickers.
- Absences chez nous établies par grep ciblé (spark, texte de durée de cast, hitbox, empilement) et lecture d'options.md ; le reste est issu de options.md seul.
- Disponibilité Forever des CVars (nameplateMotion, hitbox, etc.) non vérifiée dans ~/wow-ui-source/forever.
- Disponibilité des fonctionnalités marquées « ? » non tranchée.

## 7. Gestionnaire de recharges

Légende : Forever ? = oui / retail / ?. Valeur = H / M / G.
Chemins EUI relatifs à `EllesmereUICooldownManager/` (CDM) et `EllesmereUIOptions/` (OPT ; sous-dossier `CooldownManager_Options/` = CMO).
Chemins MUI : `Modules/CooldownManager.lua` (MCM, 436 l.), `Modules/CooldownBars.lua` (MCB, 173 l.), `Core/Glow.lua` (212 l.), `docs/options.md` sections « Gestionnaire de recharges » (l.1396-1420) et « Barres de recharges personnalisées » (l.649-700).

### 0. Ce que fait EUI (cadre) et ce que fait MUI

- EUI : remplace entièrement le CDM Blizzard. Il lit les cadres Blizzard (hooks OnCooldownIDSet, pool Acquire, Layout : CDM/EllesmereUICdmHooks.lua:1-12) et re-dessine les icônes dans SES barres (cooldowns, utility, buffs, barres custom, ghost bars, FocusKick), avec magasin par spé (EUI_CDM_Store.lua), reconcile du catalogue (EUI_CDM_Reconcile.lua), aperçu interactif, 3 pages d'options : CDM Bars, Bar Glows, Buff Bars (OPT/EUI_CooldownManager_Options.lua:2207).
- MUI : garde les 4 viewers Blizzard et leur mise en page Edit Mode ; par sort (spellID) : masquer, lueur « prêt » ou « toujours » ; par viewer : bordure du thème, taille des compteurs ; barres de buff : texture/couleur/nom/durée (MCM.lua:1-35, 76-110 ; options.md:1396-1418). MCB : 3 rangées d'icônes de sorts par identifiants (MCB.lua:1-40 ; options.md:649-700). Core/Glow : 4 styles (pixel, autocast, button, classic ; Glow.lua:1-15).
- Forever : le client expose `CooldownViewer` (~/wow-ui-source/forever/Interface/AddOns/Blizzard_CooldownViewer/, incl. PandemicAlertAnimation.xml, CooldownViewerSoundAlertData.lua) ; EUI y tourne (TOC 16001) avec des branches Forever (CDM/EllesmereUICooldownManager.lua:59,75,299,542 ; EUI_CDM_Spec.lua:58 ; EUI_CDM_Reconcile.lua:830 ; EllesmereUICdmRPTSync.lua:50,116,306).

### 1. Barres CDM : structure, mise en page, visibilité

| Fonction | Ce qu'elle fait | Forever ? | Preuve EUI | Chez nous | Valeur |
|---|---|---|---|---|---|
| Barres propres (cooldowns / utility / buffs) re-dessinées | Icônes Blizzard recapturées dans des barres EUI : taille, lignes, croissance (centré/droite/gauche/bas/haut), espacement, orientation verticale | oui | CDM/EUI_CDM_Bars.lua:1-5 ; CMO/BarsPage_Options.lua:988,1144-1155,1444,1964 | absent (mise en page = Edit Mode Blizzard, MCM.lua:8-10) | H |
| Rangées de base/seconde : nombre d'icônes et taille distinctes | 1re ligne et 2e ligne à tailles propres, « Number of Rows » | oui | BarsPage_Options.lua:1153-1271 | absent | M |
| Barres personnalisées illimitées (type cooldowns/utility/custom_buff) + ghost bars | Créer, renommer, supprimer, réordonner des barres | oui | BarsPage_Options.lua:751,775 ; CDM/EUI_CDM_Rebuild.lua:1-4 ; CDM/EllesmereUICdmSpellPicker.lua:1-4 | partiel : 3 rangées d'identifiants fixes (MCB.lua:11-27) | M |
| Visibilité par barre (combat, groupe, instance, monture, cible, mouseover...) | Règles d'affichage par barre (`barVisibility`) + copie vers les autres barres | oui | BarsPage_Options.lua:966-1040 ; CDM/EUI_CDM_Rebuild.lua:1-4 | absent (aucun réglage de visibilité CDM, options.md:1396-1420) | H |
| Fondu hors combat + alpha hors combat | Opacité réduite hors combat par barre | oui | BarsPage_Options.lua:1300-1311 | absent | M |
| Opacité de la barre / fond de barre | Alpha global et fond coloré derrière la barre | oui | BarsPage_Options.lua:1062,1075 | absent | G |
| Max Icons (0 = off) + Overflow To | Plafond d'icônes, surplus déversé dans une autre barre | oui | BarsPage_Options.lua:1382,1404 | absent | M |
| Keep Buffs in Same Place (barre de buffs) | Les buffs gardent leur emplacement même inactifs | oui | BarsPage_Options.lua:1473 | absent | M |
| Always Show Buffs (placeholders) | Emplacements de buffs visibles même inactifs (désaturés) | oui | BarsPage_Options.lua:1895,1941 ; CDM/EUI_CDM_HookPresetFrames.lua:1-4 | absent | M |
| Ancrage de la barre : unlock mode, ancrage à un autre module/élément, décalage additionnel (X/Y) | Position, ancrage, « Additional Bar Offset » rendu-seulement | oui | BarsPage_Options.lua:3655 ; CDM/EUI_CDM_Lifecycle.lua:1-4 | partiel : MCM ne bouge rien (Edit Mode), MCB a un mover par rangée (MCB.lua:50 MoverKey) | M |
| Bar Strata | Niveau de strate de la barre | oui | BarsPage_Options.lua:3552 | absent | G |
| Cache les cadres Blizzard + force l'Edit Mode (verrou) | Masque le CDM Blizzard, restaure à la coupure | oui | CDM/EUI_CDM_Blizzard.lua:1-4 ; CDM/EUI_CDM_HookViewers.lua:1-4 | sans objet (design différent) | - |
| Masquer les items vides / items manquants (potions, pierre de soin) | « Hide Items if Missing » : consommable absent du sac = icône cachée | oui | BarsPage_Options.lua:3211 | absent | M |
| Slots vides (Empty Slots) dans une barre | Espaceur d'icône vide pour caler la mise en page | oui | CDM/EUI_CDM_HookPresetFrames.lua:1-4 ; CMO/SpellPicker_Options.lua:4463 | absent | G |
| Clic droit sur une icône d'aperçu, glisser-déposer pour réordonner | Aperçu en direct interactif (réordonner, retirer) | oui | CMO/LivePreview_Options.lua:2044 ; CDM/EllesmereUICdmSpellPicker.lua:1-4 | partiel : liste de boutons par viewer, pas de réordonnancement (MCM.lua ~l.260-290) | M |
| « Missing Spells? Add in Blizzard CDM » | Renvoie vers le catalogue Blizzard pour les sorts absents | oui | CMO/SpellPicker_Options.lua:5992 | sans objet | G |

### 2. Habillage des icônes (par barre)

| Fonction | Ce qu'elle fait | Forever ? | Preuve EUI | Chez nous | Valeur |
|---|---|---|---|---|---|
| Forme d'icône personnalisée + rognage (Custom Icon Shape, Adjust Crop, Icon Zoom) | Formes autres que carré, zoom de la texture | oui | BarsPage_Options.lua:1847-1849,1986,2018,2787-2819 ; CDM/EUI_CDM_Icons.lua:1-4 | partiel : rognage global 8 % dans Habillage > Icônes (options.md:1431-1433) | M |
| Échelle, espacement d'icônes par barre | Icon Scale / Icon Spacing | oui | BarsPage_Options.lua:1917,1964,2378,2396 | absent | H |
| Bordure : taille, style, couleur, texture, Shift X/Y, Show Behind | Bordure complète par barre | oui | BarsPage_Options.lua:2089-2203,2485-2599 | partiel : seulement bordure du thème oui/non (options.md:1407) | M |
| Texte de durée : taille, position, offsets, afficher/masquer, décimales | Texte du compteur de recharge réglable | oui | BarsPage_Options.lua:2884-2953 | partiel : taille unique des compteurs (0 = Blizzard) (options.md:1408) | M |
| Texte de charges/stacks : taille, position, offsets, masquer à 0 | Charges réglables par barre | oui | BarsPage_Options.lua:2891,2995-3051,3189 | partiel : même taille unique | M |
| Compte/qualité d'objet affichés (Show Item Count / Item Quality) | Quantité et qualité des consommables | oui | BarsPage_Options.lua:3002,3017 | absent | G |
| Supprimer le GCD (Suppress GCD) | Ne pas animer le swipe pour le GCD | oui | BarsPage_Options.lua:3070 | absent | M |
| Pixel Glow : épaisseur, lignes, vitesse, fond, couleur du fond | Paramètres de la lueur pixel par barre | oui | BarsPage_Options.lua:3074-3163 ; OPT/EUI_CooldownManager_Options.lua:349-379 | partiel : style + couleur globaux seulement, paramètres fixes (Core/Glow.lua:20 PIXEL) | M |
| Charges/Stacks Only (No Icon) / Only Show Numbers | Mode « nombre seul » sans icône | oui | BarsPage_Options.lua:3132,3182 | absent | G |
| Show Tooltip on Hover | Infobulle au survol des icônes | oui | BarsPage_Options.lua:3222,3234 | absent (infobulle Blizzard native, non gérée) | G |
| Show Keybind + style du texte de raccourci (police, contour, taille, ancre, offsets, fond, bordure, Keep Keys on Bar Swap) | Raccourci clavier affiché sur chaque icône | oui | BarsPage_Options.lua:3241 ; OPT/EUI_CooldownManager_Options.lua:1902-1976 ; CDM/EllesmereUICdmKeybindStyle.lua:1-8 | absent | H |
| Always Show Cooldown Edge | Liseré de swipe permanent | oui | BarsPage_Options.lua:3622 | absent | G |
| Mirror Key Presses | L'icône s'enfonce quand la touche est pressée (art de presse des barres d'action, variante Forever) | oui | BarsPage_Options.lua:3538 ; CDM/EUI_CDM_HookPressMirror.lua:5,79-81,127 | absent | M |
| Surbrillance d'attaque en file (queued attack, Heroic Strike/Cleave/Maul/Raptor) | Lueur sur l'icône tant qu'une attaque « à la prochaine frappe » est en file | oui | CDM/EUI_CDM_HookPressMirror.lua:5,530-581 (EllesmereUI.FOREVER_NEXT_SWING) | absent | M |
| Styles de rendu : EllesmereUI / Blizzard Style / Classic WoW UI / variante Forever | Art d'icône stock Blizzard, classique, ou art des barres d'action Forever | oui | CDM/EllesmereUICooldownManager.lua:48-75 | partiel : on garde l'art Blizzard par défaut + bordure thème (MCM.lua:76-110) | G |
| Out of Range Coloring | Teinte rouge de l'icône quand la cible est hors portée (Color Out of Range) | oui | CMO/SpellPicker_Options.lua:3603,3399 ; CDM/EUI_CDM_HookPresetFrames.lua:1-4 | absent | M |
| Style de barre de buff (EllesmereUI / Blizzard / Classic, Forever) | Mêmes 3 styles côté barres de suivi | oui | CDM/EllesmereUICooldownManager.lua:66-75 | absent | G |

### 3. Réglages par sort (menu clic droit sur une icône)

Portée : « Apply to This Spell / Apply to Bar / Apply to Bar (All Specs) » (CMO/SpellPicker_Options.lua:1159-1195) ; MUI : réglages par sort communs à toutes les spés, sans niveau « barre » (MCM.lua:5-6 ; options.md:1400).

| Fonction | Ce qu'elle fait | Forever ? | Preuve EUI | Chez nous | Valeur |
|---|---|---|---|---|---|
| Portée d'application (ce sort / toute la barre / toutes spés) | Applique un réglage à une barre entière d'un clic | oui | SpellPicker_Options.lua:1159-1195,1314 | absent | M |
| Cooldown State Effect | Sur recharge : alpha réduit, caché (+ décalage des suivants), caché prêt, caché tant qu'inutilisable, caché hors forme/posture | oui | SpellPicker_Options.lua:1740-1760,3420,4110 ; CDM/EUI_CDM_HookIconWatch.lua:1-4 | partiel : on sait masquer un sort en permanence, pas sur condition d'état (MCM.lua:20-22 hidden) | H |
| Cooldown Saturation | Désaturer ou garder en couleur pendant la recharge | oui | SpellPicker_Options.lua:3201-3203,3512,4082 | partiel : MCB a « Icônes grisées pendant la recharge » (options.md:661) ; viewers : absent | M |
| Cooldown Swipe : couleur, classe, masquer l'état actif, inverser le swipe, masquer le swipe | Réglages du balayage | oui | SpellPicker_Options.lua:1537-1539,1778-1798,3224,3336-3338,3553 | absent | M |
| Proc Glow / Active State Glow / Max Charges Glow / CD Ready Glow / Buff Glow | Lueurs distinctes par événement (proc, état actif, charges max, recharge prête, buff) avec 8 types : Pixel, Action Button, Auto-Cast, Shape Glow, GCD, Modern WoW, Classic WoW | oui | SpellPicker_Options.lua:1516-1524,3840,4003,4025,4110,4182,2796 ; CDM/EUI_CDM_Glows.lua:1-4 | partiel : lueur « prête » ou « toujours » seulement, 4 styles globaux (MCM.lua:70-75 ; Glow.lua:14) | H |
| CD Ready Glow « Resource Aware » | La lueur « prêt » tient compte de la ressource disponible | oui | SpellPicker_Options.lua:1396,1675 ; CDM/EUI_CDM_HookTrinkets.lua:1-4 | absent (MUI : NS.IsSpellReady seul, MCM.lua:77-80) | M |
| Glow Effect Color par sort (défaut / classe / personnalisé) | Couleur de lueur propre à chaque sort | oui | SpellPicker_Options.lua:2814-2816,3760,4356 | partiel : couleur unique globale (options.md:1403) | M |
| Glow When Visible / Glow at Stacks (comparaison + nombre) | Lueur seulement quand le buff est visible ou à N stacks | oui | SpellPicker_Options.lua:2806,3044-3059 ; OPT/EUI_CooldownManager_Options.lua:1422-1469 | absent | M |
| Threshold Text (seuil en secondes, couleur, décimales) | Le compteur change de couleur sous N secondes | oui | SpellPicker_Options.lua:2550-2608,2621,3252,3548 ; CDM/EUI_CDM_Icons.lua:1-4 | absent | M |
| Custom Active State (fenêtre d'effet manuelle : durée + swipe/lueur propre) | Dessine sa propre icône saturée avec swipe pendant X s après le lancer (sorts sans aura) | oui | SpellPicker_Options.lua:3660-3806 ; CDM/EllesmereUICdmFakeActive.lua:1-10 | absent | H |
| Desaturate Inactive / Visibility When Missing / Always Show Buff (buffs) | Comportement d'un buff absent : désaturé, caché, affiché | oui | SpellPicker_Options.lua:2692-2738,3205 | absent | M |
| Audio on Buff Gain / Loss, Audio Effect on CD Ready | Son joué au gain/perte d'un buff, ou quand la recharge se termine | oui | SpellPicker_Options.lua:3157-3175,3648,4320 ; CDM/EUI_CDM_BuffBarAssign.lua:1-4 ; CDM/EUI_CDM_HookIconWatch.lua:1-4 | absent | H |
| Stance Bar (caché dans/hors d'une page de posture de la classe) | Cache l'icône selon la forme/posture | oui | SpellPicker_Options.lua:1813,3578,4269 ; CDM/EllesmereUICdmStanceBar.lua:1-8 | absent | M |
| Custom Icon (remplacer la texture d'une icône) | Icône personnalisée par sort | oui | SpellPicker_Options.lua:4487 ; OPT/CMO/Pickers_Options.lua:1851 | absent | G |
| Replace with Buff / Buff to CD | Remplace une icône de recharge par le buff correspondant | oui | SpellPicker_Options.lua:4432 ; Pickers_Options.lua:1292 | absent | M |
| Copy to / Remove from Other Specs | Copie un sort et ses réglages vers d'autres spés/classes | oui | SpellPicker_Options.lua:4537-4568 | absent (Forever : une spé par classe, EllesmereUICdmRPTSync.lua:50) | G |
| Texte de durée / de stacks / bordure par icône (cog) | Mini-panneaux de réglages par icône | oui | SpellPicker_Options.lua:2990-3110 | absent | M |

### 4. Sélecteur de sorts et sorts personnalisés

| Fonction | Ce qu'elle fait | Forever ? | Preuve EUI | Chez nous | Valeur |
|---|---|---|---|---|---|
| Sélecteur : ajouter / remplacer / retirer un sort sur une barre depuis le catalogue | Choix de sorts, dont ceux « Not Displayed » du CDM Blizzard | oui | CMO/SpellPicker_Options.lua:73-250 ; CDM/EllesmereUICdmSpellPicker.lua:1-4 ; CDM/EUI_CDM_Reconcile.lua:830-870 (CDMForeverListedSet) | partiel : on bascule masqué/visible parmi ceux que Blizzard affiche (MCM.lua:191-290) | H |
| Ajouter un sort personnalisé par ID (avec durée) | Sort hors catalogue, suivi par durée fixe | oui | Pickers_Options.lua:372,545 ; SpellPicker_Options.lua:4723 | partiel : MCB prend des IDs mais sans durée de buff (MCB.lua:35-45) | M |
| Ajouter un objet par ID / un emplacement d'équipement | Objet de sac ou slot équipé (dont trinkets) | oui | Pickers_Options.lua:633,788 | absent | M |
| Sous-menu « Custom Tracking » (objets du sac) | Choix d'objets présents dans les sacs | oui | SpellPicker_Options.lua:5159,5269 | absent | G |
| Sous-menu « Potions & Healthstone » | Presets d'objets de soin/potions (Forever : pierres de soin vanilla à 5 rangs) | oui | SpellPicker_Options.lua:5594 ; CDM/EllesmereUICooldownManager.lua:542-560 | absent | M |
| Slot racial unique géré (racials Forever : Will to Survive, Shadowmeld, Berserking, Read Ley Line, Skysight) | Un seul slot racial, remappé selon la race | oui | CDM/EllesmereUICooldownManager.lua:299-310 | absent | G |
| Cartographie spell id (base / live / override) | Résolution des formes de sorts pour router vers la bonne barre | oui | CDM/EUI_CDM_HookResolve.lua:1-4 | partiel : NS.GetCooldownViewerSpell (MCM.lua:~105) | - |

### 5. Trinkets

| Fonction | Ce qu'elle fait | Forever ? | Preuve EUI | Chez nous | Valeur |
|---|---|---|---|---|---|
| Trinkets sur les barres CDM (emplacements -13/-14) avec recharge, glow « prêt » | Les deux bijoux équipés apparaissent comme icônes de recharge | oui | CDM/EUI_CDM_HookTrinkets.lua:1-4 ; CDM/EllesmereUICdmRPTSync.lua:1-6 | absent (aucune mention de bijou dans MCM/MCB ; grep sur les .lua du dépôt : Gear/Skin/Bags seulement) | H |
| Show Non-On Use Trinkets | Affiche aussi les bijoux passifs | oui (déplacé sur la ligne de Forever) | BarsPage_Options.lua:3291,3629-3636 | absent | G |
| Slot Racial/trinket/preset partagés entre spés | Synchro « Generic CDs/Buffs » entre spés (Forever : une ligne par classe) | oui | EllesmereUICdmRPTSync.lua:1-12,50,116,306 ; EUI_CooldownManager_Options.lua:2368 | absent | G |

### 6. Barres de suivi (Tracking Bars / Buff Bars)

Page « Buff Bars » (OPT/EUI_CooldownManager_Options.lua:2207 ; CMO/BuffBarsPage_Options.lua). EUI crée des barres StatusBar pilotées par les cadres CDM Blizzard (CDM/EllesmereUICdmBuffBars.lua:1-6). MUI : seulement un habillage de la barre de buffs Blizzard (texture, couleur, nom, durée) (MCM.lua:36-45 ; options.md:1415-1418).

| Fonction | Ce qu'elle fait | Forever ? | Preuve EUI | Chez nous | Valeur |
|---|---|---|---|---|---|
| Barres de suivi autonomes, N barres, une par buff/recharge | Une barre par aura suivie, assignée depuis le catalogue CDM | oui | BuffBarsPage_Options.lua:215,606,2204,2292 ; CDM/EUI_CDM_BuffBarAssign.lua:1-4 | absent (une seule barre de buffs Blizzard recolorée) | H |
| Suivi de recharge (Cooldowns) et de buff (Buffs), barre à charges (hash lines, teinte de charge partielle) | Barre de cooldown avec lignes par charge | oui | BuffBarsPage_Options.lua:3898-3988 ; CDM/EUI_CDM_BuffBarCooldown.lua:1-4 | absent | M |
| Stack Based Bar / ticks aux stacks / seuil de stacks | Barre graduée par stacks, repères et couleur au seuil | oui | BuffBarsPage_Options.lua:4353-4547 ; CDM/EUI_CDM_BuffBarTick.lua:1-4 | absent | M |
| Dimensions, orientation verticale, texture, couleurs (fond, remplissage, bordure), étincelle, remplissage inversé, icône, opacité, lisser | Apparence complète par barre | oui | BuffBarsPage_Options.lua:3312-3445,3852-3929,4043-4313 | partiel : texture/couleur uniques pour la barre de buffs Blizzard (options.md:1415-1416) | M |
| Textes : nom (position, taille, retour à la ligne), durée (décimales, seuil), stacks (taille, offsets), « Apply to all Bars » | Textes de barre réglables | oui | BuffBarsPage_Options.lua:3522-3823 | partiel : afficher/masquer nom et durée seulement (options.md:1417-1418) | M |
| Décimales de durée « engine-driven » (secret en combat) | Dixièmes de seconde en combat via conteneur d'aura caché | retail | CDM/EllesmereUICdmTbbDecimals.lua:1-8 (« 12.1-only ») | absent | G |
| Groupes de barres (par spé et globaux), croissance, espacement, nom, auto-ajout, décalage si vide | Empiler/organiser les barres en groupes | oui | BuffBarsPage_Options.lua:2109-2145,3089-3200 ; CDM/EUI_CDM_BuffBarGroups.lua:1-4 | absent | M |
| Presets de style (sauver, renommer, appliquer au groupe, assigner à une spé) | Bibliothèque de styles de barres | oui | BuffBarsPage_Options.lua:2727-3051 ; CDM/EUI_CDM_BuffBarGroups.lua:1-4 | absent | G |
| Presets auto-chronométrés : Bloodlust/Heroism, Time Spiral, Light's Potential, potions de buff | Barres de suivi pour effets sans aura lisible | retail (partiel Forever : Bloodlust, Time Spiral, Light's Potential... retirés de la liste ; potions de Forever gérées) | CDM/EllesmereUICooldownManager.lua:542-548 ; CDM/EUI_CDM_BuffBarPresets.lua:372,560,641 | absent | M |
| Sons gain/perte de buff par barre | Voir §3 | oui | BuffBarsPage_Options.lua:1954-1955,2248,2472 | absent | H |
| Pandemic Glow par barre (+ synchro vers nameplates/toutes barres) | Lueur dans les 30 % de durée restante, copiable partout | oui | BuffBarsPage_Options.lua:4365 ; OPT/EUI_CooldownManager_Options.lua:261-310,583 ; BarsPage_Options.lua:3265 ; CDM/EUI_CDM_BuffBarPresets.lua:1-4 ; (Forever : PandemicAlertAnimation.xml présent dans Blizzard_CooldownViewer) | absent (Pandemic seulement côté nameplates, hors zone) | M |
| Diffuser une barre à toutes les spés (broadcast) | Copier une barre vers les autres spés | retail (Forever : « no other specs ») | BuffBarsPage_Options.lua:2553,2680-2694 ; CDM/EUI_CDM_BuffBarStore.lua:435,476,513 | absent | G |
| Utiliser les barres Blizzard (« Use Blizzard Bars ») | Retour aux barres natives | oui | BuffBarsPage_Options.lua:2638 | sans objet (MUI garde les barres Blizzard) | - |
| Unlock Mode des barres et groupes | Déplacement libre | oui | CDM/EUI_CDM_BuffBarUnlock.lua:1-4 | absent (MCM ne déplace rien) | M |

### 7. Bar Glows (lueur sur boutons de barre d'action / barres CDM selon un buff)

Page « Bar Glows » (OPT/EUI_CooldownManager_Options.lua:763-1690 ; CDM/EllesmereUICdmBarGlows.lua:1-6). Lueur sur un bouton quand un buff est actif (ou absent) ; adossé aux boutons EAB ou Blizzard (ActionButton, MultiBar*Button : EllesmereUICdmBarGlows.lua:~30-45).

| Fonction | Ce qu'elle fait | Forever ? | Preuve EUI | Chez nous | Valeur |
|---|---|---|---|---|---|
| Assigner un buff à un bouton d'action ou une icône CDM | « Quand ce buff est actif, le bouton X brille » | oui | EUI_CooldownManager_Options.lua:645-763,763-860 ; CDM/EllesmereUICdmBarGlows.lua:1-6 | absent (nous : lueur d'un sort sur son propre item CDM, pas le lien buff -> bouton) | H |
| Mode actif / manquant (MISSING) | Brille quand le buff est présent ou absent | oui | CDM/EllesmereUICdmBarGlows.lua:3-4 ; CDM/EllesmereUICdmBarGlowConditions.lua:1-12 | absent | M |
| Type de lueur, couleur, aperçu, opacité (Blackout), retirer | Look de la lueur par entrée | oui | EUI_CooldownManager_Options.lua:1433,1540-1569 | partiel : 4 styles globaux (Glow.lua:14) | M |
| Seulement en combat | Condition de combat | oui | EUI_CooldownManager_BarGlowConditions.lua:430 ; CDM/EllesmereUICdmBarGlowConditions.lua:1-12 | absent | M |
| Condition « second buff actif/manquant » (ET) | Deux buffs requis pour la lueur | oui | EUI_CooldownManager_BarGlowConditions.lua:337 ; CDM/EllesmereUICdmBarGlowConditions.lua:1-12 | absent | G |
| Glow at Stacks (comparaison + valeur) | Lueur à N stacks | oui | EUI_CooldownManager_Options.lua:1422-1469 | absent | M |
| Condition arbre de héros (Hero Talent) | Entrée active seulement avec l'arbre de héros choisi | retail | EUI_CooldownManager_BarGlowConditions.lua:456-457 ; CDM/EllesmereUICdmBarGlowConditions.lua:52 ; CDM/EllesmereUICdmBarGlows.lua:565 | absent | - |
| Show Glows Only in Combat (global) | Toutes les lueurs de barre limitées au combat | oui | BarsPage_Options.lua:3590 | absent | M |

### 8. Conditions de talents

| Fonction | Ce qu'elle fait | Forever ? | Preuve EUI | Chez nous | Valeur |
|---|---|---|---|---|---|
| Talent Conditions par sort (« talent X pris / non pris » : l'icône n'apparaît que si toutes les conditions tiennent) + popup d'arbre | Filtre dynamique sur les talents (+ conditions sur les Empty Slots) | retail (code désactivé sur Forever : « vanilla trees have no class/spec split for the popup ») | CDM/EllesmereUICdmTalentConditions.lua:1-9 ; SpellPicker_Options.lua:331,4463 (`not IS_FOREVER`), :407 ; EUI_CooldownManager_TalentConditions.lua ; LivePreview_Options.lua:1501 | absent | - (retail) |

### 9. Aides au tour de rotation et divers

| Fonction | Ce qu'elle fait | Forever ? | Preuve EUI | Chez nous | Valeur |
|---|---|---|---|---|---|
| Rotation Assist (Show Rotation Helper, style, couleur, épaisseur, décalage) : surbrillance du sort recommandé (C_AssistedCombat) | Lueur sur la prochaine capacité conseillée | retail (« Not on Forever: no Assisted Highlight there ») | EUI_CooldownManager_Options.lua:494,2207 ; BarsPage_Options.lua:3298-3320,3352-3491 ; CDM/EUI_CDM_Rotation.lua:1-4 | absent | - (retail) |
| Rotation Assist Icon (icône séparée, taille, combat seul, raccourci, GCD) | Icône flottante du sort conseillé | retail | EUI_CooldownManager_Options.lua:2032-2110 ; CDM/EllesmereUICdmRotationIcon.lua:43,277 | absent | - (retail) |
| FocusKick (barre épinglée sur la plaque du focus : sort d'interruption, rappel texte, son de cast du focus, réglages) | Suivi d'interruption lié à la nameplate du focus | ? (non vérifié : aucun gate Forever dans le fichier, plaque + cast du focus à confirmer) | BarsPage_Options.lua:1496,1512-1626,1755,1759,1798 ; CDM/EUI_CDM_FocusKick.lua:1-12 | absent | M |
| Repopulate Bars | Remplit à nouveau les barres depuis le catalogue | oui | BarsPage_Options.lua:333 | sans objet | G |
| Reconcile du catalogue (reseed, drops, familles de buffs, 1re connexion) | Maintient la cohérence barres <-> catalogue Blizzard (Forever : id inconnus conservés) | oui | CDM/EUI_CDM_Reconcile.lua:1-4,830-870,1055-1070 | sans objet (MUI lit Blizzard en direct) | - |
| Clé de spé Forever (une spé par classe, clé mémorisée par profil) | Magasin par clé résolue pour Forever | oui | CDM/EUI_CDM_Spec.lua:58-75 | sans objet | - |
| Réinitialiser les réglages du module (par spé/classe) | Reset d'un module avec nettoyage des clés Forever | oui | EUI_CooldownManager_Options.lua:2360-2380 | partiel (profils globaux MUI, hors zone) | G |
| Pandemic/Glow « sync to all surfaces » | Propage un style de lueur de pandémie à plaques + barres | oui | EUI_CooldownManager_Options.lua:261-310 ; BarsPage_Options.lua:3277-3290 | absent | G |

### 10. Core/Glow : écart de moteur de lueur

| Fonction | Ce qu'elle fait | Forever ? | Preuve EUI | Chez nous | Valeur |
|---|---|---|---|---|---|
| 8 types de lueur : Pixel, Action Button, Auto-Cast Shine, Shape Glow (suit la forme d'icône), GCD, Modern WoW Glow, Classic WoW Glow, None | Palette de lueurs choisie par événement | oui (Modern WoW Glow : non vérifié si ressource Forever) | SpellPicker_Options.lua:1516-1524 ; CDM/EUI_CDM_Glows.lua:1-4 (StartNativeGlow/StopNativeGlow) | partiel : 4 styles (pixel, autocast, button, classic) (Glow.lua:14) ; manquent Shape Glow, GCD, Modern WoW | M |
| Paramètres de lueur modifiables (lignes, vitesse, épaisseur, fond) | Réglage fin du pixel glow | oui | BarsPage_Options.lua:3074-3163 | absent (constantes PIXEL/AUTOCAST fixes, Glow.lua:20-21) | G |

### Équivalents complets (ou quasi)

- Masquer un sort d'une barre avec remontée des suivants : MCM.lua:90-115 (EUI : filtres de la passe de reanchor, CDM/EUI_CDM_HookReanchor.lua).
- Lueur « prête » et « toujours » par sort : MCM.lua:70-80 (partiel face à la matrice complète du §3).
- Bordure du thème + taille de compteur par viewer, couleur/texture de barre de buffs, nom et durée de barre : MCM.lua:76-110 ; options.md:1405-1418.
- Rangées d'icônes de sorts par identifiants avec masquage des sorts prêts et grisage en recharge : MCB.lua ; options.md:649-700 (EUI : barres custom, BarsPage_Options.lua:1943 « Desaturate Off CD »).

### Limites client révélées (nouveaux faits)

- Talent Conditions désactivé sur Forever (« vanilla trees have no class/spec split ») : CMO/SpellPicker_Options.lua:4463 ; LivePreview_Options.lua:1501.
- Pas d'Assisted Highlight / C_AssistedCombat exploitable sur Forever (le code retail est gaté) : EUI_CooldownManager_Options.lua:494,2207 ; CDM/EllesmereUICdmRotationIcon.lua:43. (L'API existe dans la doc Forever, ActionBarFrameDocumentation.lua, mais EUI la considère indisponible : non vérifié au runtime.)
- Durée restante d'un buff secrète en combat : lecture verbatim de la FontString Blizzard (TBB) ; les dixièmes exigent un conteneur d'aura moteur « 12.1-only » : CDM/EllesmereUICdmTbbDecimals.lua:1-8. Aucune équivalence confirmée sur Forever.
- `isActive` d'une aura de viewer lisible en combat, mais durée/startTime secrets (« Midnight ») : CDM/EUI_CDM_FocusKick.lua:381-385 ; GetSpellID d'un cadre d'aura secret tant que l'aura est active : EUI_CDM_FocusKick.lua:401-403 (comportement de la branche 12.x ; non vérifié sur Forever 1.60).
- Forever : une seule spé par classe ; les clés de magasin par spé retail doivent être résolues par classe : CDM/EUI_CDM_Spec.lua:58-75 ; EllesmereUICdmRPTSync.lua:50,116.
- Catalogue CDM Forever lisible via `CooldownViewerSettings:GetDataProvider()` + `C_CooldownViewer.GetCooldownViewerCooldownInfo` (liste complète « Not Displayed » comprise) : CDM/EUI_CDM_Reconcile.lua:830-870. Utile pour un sélecteur qui ajoute des sorts que Blizzard n'affiche pas.
- Broadcast de barre vers autres spés impossible sur Forever (une spé) : BuffBarsPage_Options.lua:2553,2691.
- Presets retail retirés sur Forever (Bloodlust, Time Spiral, Light's Potential, potions retail, pierre démoniaque...) et pierres de soin vanilla à 5 rangs avec cooldown partagé : CDM/EllesmereUICooldownManager.lua:542-560.

### Non couvert

- Lecture intégrale non faite : EUI_CDM_HookReanchor.lua (2393 l.), EUI_CDM_HookDecorate.lua (1606 l.), EUI_CDM_HookIconWatch.lua (1760 l.), EllesmereUICdmFakeActive.lua, EllesmereUICdmSpellPicker.lua, BarsPage_Options.lua / BuffBarsPage_Options.lua / SpellPicker_Options.lua au-delà des libellés et en-têtes (inventaire fait par grep de libellés et de gates Forever).
- EUI_CooldownManager_TalentConditions.lua et Pickers_Options.lua : seuls les en-têtes et signatures lus.
- Fonctionnement réel de FocusKick sur Forever, de Modern WoW Glow, de Shape Glow : non vérifié.
- Côté MUI : seule la zone MCM/MCB/Glow lue ; `docs/options.md` lu aux sections ciblées. Les modules voisins (barres d'action, plaques) peuvent couvrir des morceaux de Pandemic/Bar Glows : non vérifié.
- Lignes de preuve de forme « ~l. » ou plages larges (ex. OPT:645-763) : approximatives, à reconfirmer avant implémentation.

## 8. Barres d'action et sacs

Chemins : EUI = /home/ludovic/Téléchargements/EllesmereUI-v9.6.8. Abréviations de preuve : OPT = EllesmereUIOptions, ABO = EllesmereUIOptions/ActionBars_Options, AB = EllesmereUIActionBars, BG = EllesmereUIBags.
Chez nous : MuscaUI_ActionBars/ActionBars.lua (1178 l.), MuscaUI_Bags/Bags.lua (728 l.), MuscaUI_Bags/Bank.lua (222 l.), docs/options.md sections « Barres d'action MuscaUI », « Sacs », « Banque », « Barres de données MuscaUI ».
Contexte : EUI tourne sur Forever (IS_FOREVER gère quelques branches) ; Forever = banque en onglets-sacs (Enum.BagIndex.Characterbanktab, BG/EllesmereUIBags_Bank.lua:373) et coffre de bataillon (BG_Bank.lua:496 « Warband Gold »).
Nous : 8 barres (BAR_DEFS, ActionBars.lua:51-60), EUI : 10 barres + Stance + Pet + Micro + Bag + QueueStatus + XP/Rep/Favor + Extra Action/Encounter (AB/EllesmereUIActionBars.lua:250-290).

---

### 1. Barres d'action : disposition et visibilité

| Fonction | Ce qu'elle fait | Forever ? | Preuve EUI | Chez nous | Valeur |
|---|---|---|---|---|---|
| Barres 9 et 10 (boutons EUI propres, pages 2 et 10, raccourcis via Bindings.xml) | Deux barres supplémentaires sans cadre Blizzard | oui | AB/EllesmereUIActionBars.lua:268-270 | absent (8 barres) | M |
| Barre de posture réglable (mêmes réglages que les barres) | Stance Bar stylée : taille, espacement, visibilité, etc. | oui | AB/EllesmereUIActionBars.lua:271 | partiel : déplaçable/cachée/gardée seulement (liste « Barre de posture », ActionBars.lua:1077) | M |
| Barre du familier réglable | Pet Bar stylée (mêmes réglages) | oui | AB/EllesmereUIActionBars.lua:272 | partiel : déplaçable/cachée seulement (ActionBars.lua:1079) | M |
| Sens de croissance, orientation verticale, ordre des icônes | Grow Direction, Vertical Orientation, Icon Order | oui | ABO/BarVisibilityLayout_Options.lua:658,678,692 | absent (seulement boutons, par ligne) | M |
| Nombre de lignes | Slider « Number of Rows » (nous : boutons par ligne) | oui | ABO/BarVisibilityLayout_Options.lua:557 | équivalent par « Boutons par ligne » | -- |
| Fond de barre (activer, couleur, opacité, espacement, largeur, hauteur) | Cadre/diviseurs derrière les boutons | oui | ABO/BarAppearance_Options.lua:41-222 ; BarVisibilityLayout_Options.lua:853-904 | absent | G |
| Bordure de barre (style, taille, décalages X/Y, derrière, multiplicateurs X/Y) | Bordure personnalisée autour de la barre | oui | ABO/BarAppearance_Options.lua:251-543 | absent | G |
| Embouts (gryphons, 3 arts Moderne/Classique/WoW Forever, taille, décalages) sur barres, micro et sacs | Chrome latéral de la barre 1 | oui | EUI_ActionBars_Options.lua:474-533 ; AB/EUI_ActionBars_Chrome.lua:569 | absent | G |
| « Appliquer à toutes les barres » sur chaque réglage | Copie d'un réglage vers toutes les barres | oui | ABO/BarVisibilityLayout_Options.lua:131,274,330,453,505... | partiel : « Copier les réglages depuis » (tout d'une barre, pas par réglage) ActionBars.lua:1128 | M |
| Barre cliquable à travers (click through) | La barre ne capte pas la souris | oui | ABO/BarVisibilityLayout_Options.lua:315 | absent | M |
| Toujours montrer les boutons (emplacements vides) | Fonds de boutons vides visibles | oui | ABO/BarVisibilityLayout_Options.lua:255 | absent (vide : comportement Blizzard) | M |
| Afficher à l'ouverture du grimoire | Barre révélée quand le livre de sorts est ouvert | oui | ABO/BarVisibilityLayout_Options.lua:182 | absent | M |
| Afficher pendant un glisser (sort/objet) | Barre masquée révélée pendant un drag pour y déposer | oui | ABO/BarVisibilityLayout_Options.lua:196 | absent | H |
| Visibilité multi-conditions : Jamais, Toujours, Survol, mode « toutes/une des conditions », voies Afficher/Masquer par condition | Sélection multiple avec voies de masquage | oui | OPT/EllesmereUI_Widgets_Visibility.lua:55-78 ; EllesmereUI/EllesmereUI_Visibility.lua:285-345 | partiel : « Afficher quand » (toutes/une) + En combat, groupe, raid, monture, cible en trois états (options.md « Visibilité ») ; pas de voie Masquer séparée, pas de Jamais/Toujours | M |
| Conditions de visibilité supplémentaires : hors combat, solo/groupe séparés, Instances, Donjons, Cible ennemie, Au repos, En véhicule, Party Mode | Axes de visibilité de plus | oui (sauf skyriding, logement) | OPT/EllesmereUI_Widgets_Visibility.lua:72-116 | partiel : pas Instances, Donjons, Cible ennemie, Au repos, En véhicule ; hors combat via tri-état En combat | M |
| Skyriding (en vol / pas en vol / monture), Logement (housing) | Conditions retail | retail | OPT/EllesmereUI_Widgets_Visibility.lua:83-98 (`forever = "never"/"always"`) | sans objet | -- |
| Basculer une barre par raccourci (Toggle Action Bar) | Touche qui affiche/cache la barre | oui | ABO/BarVisibilityLayout_Options.lua:121,387 ; AB/EUI_ActionBars_Visibility.lua (RebuildVisToggleBindings) | absent | M |
| Barre de mini-menu, sacs, QueueStatus : visibilité propre (Jamais/Toujours/Survol/conditions) | Visibilité fine des barres micro et sacs | oui | ABO/MenuBagsRepPage_Options.lua:~790-830 | partiel : afficher/cacher/déplacer (ActionBars.lua:1075-1076), sans conditions ni survol | G |
| Barre de l'objet d'action supplémentaire / Barre de rencontre (visibilité) | Extra Action Button, Encounter Bar | `ExtraActionButton` retiré sur Forever (EllesmereUIActionBars.lua:295-299) ; Encounter bar `?` | AB/EllesmereUIActionBars.lua:289-290 | absent | G |
| Survol lié à toutes les barres | Un survol révèle toutes les barres « au survol » | oui | ABO/BarVisibilityLayout_Options.lua:227 | équivalent (`linkedMouseover`) | -- |
| Opacité de barre | Slider | oui | ABO/BarVisibilityLayout_Options.lua:238 | équivalent | -- |

### 2. Barres d'action : apparence des boutons

| Fonction | Ce qu'elle fait | Forever ? | Preuve EUI | Chez nous | Valeur |
|---|---|---|---|---|---|
| Forme de bouton personnalisée (carré, ronde, etc.) + zoom d'icône | Masques de forme, rognage | oui | ABO/BarAppearance_Options.lua:1079,1134 ; AB/EUI_ActionBars_ButtonArt.lua | partiel : seul le recadrage (`iconZoom`) ActionBars.lua:566-575 ; pas de formes | G |
| Bordure de bouton : style, taille, décalages, « au-dessus des effets », couleur | Bordures texturées de boutons | oui | ABO/BarAppearance_Options.lua:598-824 | partiel : bordure fine thème ou classe seulement (StyleButton ActionBars.lua:566) | G |
| Fond d'icône Blizzard (opacité), emplacements vides | Gestion de l'art de fond | oui | ABO/BarAppearance_Options.lua:1274-1336 | absent | G |
| Textes de raccourci / macro / charges / recharge : masquer, taille, ancrage (9 positions), décalages, police, couleur | Réglage fin des 4 textes de bouton | oui | ABO/BarAppearance_Options.lua:1862-2424 | partiel : seulement afficher/masquer raccourcis et noms de macro (ActionBars.lua:1081-1082) | M |
| Taille de texte de recharge ajustée au bouton | Plafonne le compte à rebours | oui | ABO/BarAppearance_Options.lua:2423 | absent (texte de recharge coloré via NS.RegisterCooldown, ActionBars.lua:679, sans réglage) | G |
| Masquer le nombre de charges à 0 | Cache le « 0 » | oui | ABO/BarAppearance_Options.lua:1660 | absent | G |
| Nombres de recharge de charges (Charge Recharge Numbers), bascule des nombres de recharge Blizzard | Options de nombres de recharge | oui | ABO/BarAppearance_Options.lua:1284,1323 | absent | G |
| Opacité sous recharge / opacité du balayage de recharge | Alpha de l'icône en recharge, alpha du voile | oui | ABO/BarAppearance_Options.lua:1603,1610 | partiel : couleur du voile seulement (`cooldownColor`), alpha fixe 0.8 ActionBars.lua:643 | G |
| Désaturer en recharge | Icône grisée pendant la recharge | oui | ABO/BarAppearance_Options.lua:1417 | équivalent (`cooldownDesaturate`) | -- |
| Coloration hors de portée (couleur choisie) | Teinte l'icône quand la cible est hors portée | oui | ABO/BarAppearance_Options.lua:1473 ; AB/EUI_ActionBars_Range.lua | absent (la teinte Blizzard par défaut s'applique, ActionBars.lua:479-486 n'active que la vérif de portée) | M |
| Désactiver les infobulles de boutons | Pas de tooltip au survol | oui | ABO/BarAppearance_Options.lua:1429 | absent | G |
| Rang d'objet (diamant de qualité) | Affiche le rang des consommables | `?` | ABO/BarAppearance_Options.lua:1481 | absent | G |
| Bordure de couleur d'objet équipé | Bordure à la rareté de l'objet équipé | oui (défaut actif sur Forever) | ABO/BarAppearance_Options.lua:1667 ; AB/EllesmereUIActionBars.lua:715 | absent | M |
| Icône « One Button Assist » (rotation assistée) | Icône du bouton d'assistance | `?` non vérifié (C_ActionBar.IsAssistedCombatAction, AB/EUI_ActionBars_ButtonArt.lua:452) | ABO/BarAppearance_Options.lua:1347-1358 | absent | G |
| Survol assisté (Assisted Highlight : anneau, retrait, opacité, couleur, ajusté aux boutons rognés) | Mise en avant du sort suggéré | `?` non vérifié | ABO/AnimationsPage_Options.lua:545-598 | absent | G |
| Couleur d'objet de l'overlay du bouton | Teinte de l'overlay | oui | ABO/AnimationsPage_Options.lua:598 | absent | G |

### 3. Animations, lueurs, interactions

| Fonction | Ce qu'elle fait | Forever ? | Preuve EUI | Chez nous | Valeur |
|---|---|---|---|---|---|
| Lueur de proc personnalisée (styles, couleur, réglages) | Remplace la lueur Blizzard | oui | ABO/AnimationsPage_Options.lua:82-94 ; AB/EUI_ActionBars_Glows.lua | équivalent en partie : liste « Lueur des sorts en surbrillance » (`procGlow`, NS.Glow) ; pas de couleur propre par barre | -- |
| Couleur des interactions de barre (pressé/survol), coloré par classe | Teinte de l'overlay pressé et survolé | oui | ABO/AnimationsPage_Options.lua:322-339 | absent | G |
| Type d'overlay pressé, type de survol, bordure (taille, « Match Bar Border ») | Textures pressé/survol réglables | oui | ABO/AnimationsPage_Options.lua:349-432 ; AB/EUI_ActionBars_Pushed.lua | absent | G |
| Masquer les animations de lancement | Retire le balayage de cast | oui | ABO/AnimationsPage_Options.lua:453 | absent | G |
| Surbrillance du sort en cours (couleur, comme bordure) | Active spell highlight | oui | ABO/AnimationsPage_Options.lua:463-511 | absent | G |

### 4. Paging, raccourcis, interactions

| Fonction | Ce qu'elle fait | Forever ? | Preuve EUI | Chez nous | Valeur |
|---|---|---|---|---|---|
| Paging configurable par barre : états par barre (formes de classe, Maj/Ctrl/Alt, cible amie/hostile) | Une barre change de page selon modificateur, cible ou forme | oui | ABO/BarAppearance_Options.lua:1690-1830 ; AB/EUI_ActionBars_Paging.lua:32-49 | partiel : paging de forme de la barre 1 fixé en dur (PAGE_DRIVER ActionBars.lua:72) ; aucun réglage utilisateur | H |
| Désactiver le paging de forme (barre 1), désactiver le paging skyriding | Garder la page quel que soit la forme | oui (forme) / retail (skyriding) | ABO/BarAppearance_Options.lua:1754-1761 | absent | M |
| Flèches de pagination + numéro de page (barre 1), à droite | Boutons page précédente/suivante | oui | ABO/BarAppearance_Options.lua:1788,1840 ; AB/EUI_ActionBars_Paging.lua | absent | M |
| Sauter les barres visibles en changeant de page | Cycle de pages évitant les pages déjà affichées | oui | ABO/BarAppearance_Options.lua:1797 | absent | G |
| Mode raccourcis rapide (Quick Keybind Mode) sur boutons EUI et flèches | Intégration du mode de liaison rapide Blizzard | `?` non vérifié | AB/EUI_ActionBars_QuickKeybind.lua | partiel : notre propre mode `/musca kb` (ActionBars.lua:947-962) | -- |
| Clignotement du bouton Swiftmend (scan de luminosité) | Effet spécifique à un sort | retail `?` | AB/EUI_ActionBars_QuickKeybind.lua (en-tête) | absent | G |
| Raccourcis key-down (CVar ActionButtonUseKeyDown), touche tenue (ActionButtonUseKeyHeldSpell) | Presse-et-maintiens, empowered | oui | AB/EUI_ActionBars_Keybinds.lua:314-329 ; AB/EUI_ActionBars_Paging.lua:533 | partiel : lit la CVar Blizzard (`pressAndHold` ActionBars.lua:680-686), pas de logique propre | G |
| Verrou de barres (glisser) | Suit la CVar lockActionBars | oui | AB/EUI_ActionBars_Setup.lua:397 | équivalent (ActionBars.lua:656-662) | -- |
| Flyout de sorts reskinné aux formes/bordures de la barre | Habille le SpellFlyout | oui (sauf style Gamepad) | AB/EUI_ActionBars_Flyout.lua:1-4,222-228 | absent (flyout Blizzard natif) | G |
| Bouton de sortie de véhicule + masquage de la barre véhicule/override | Gère l'OverrideActionBar | oui | AB/EUI_ActionBars_Vehicle.lua ; ABO/MenuBagsRepPage_Options.lua:889-896 | partiel : bascule vers page 12 (ActionBars.lua:69-72), sans option de masquage | M |
| Verrou de position / mouvement en mode déverrouillage, sauvegarde de positions | Unlock Mode | oui | AB/EUI_ActionBars_Unlock.lua | équivalent (NS.Movers) | -- |
| Remplacement global du profil à la réinitialisation module | onReset du module | oui | EUI_ActionBars_Options.lua:944-949 | non vérifié (global) | G |

### 5. Barres de données (XP, réputation, Faveur) hébergées dans le module EUI

(Chez nous : module distinct « Barres de données MuscaUI », options.md. Seules les fonctions manquantes.)

| Fonction | Ce qu'elle fait | Forever ? | Preuve EUI | Chez nous | Valeur |
|---|---|---|---|---|---|
| Style de barre XP (EUI / Blizzard / autres arts) | Choix du rendu | oui | ABO/XPBarPage_Options.lua:335-345 | absent | G |
| Séparateurs 5 % / 10 %, style de ligne 5 %, texte des séparateurs | Graduations sur la barre | oui | ABO/XPBarPage_Options.lua:361-484 | absent | G |
| Textes multiples à positions (centre, gauche, droite, 4 coins) avec contenu choisi (Actuel, %, Max, Restant, Repos, Quêtes terminées, Niveau, XP/h, Niveau dans, Temps niveau, Temps session) | Slots de texte configurables | oui | ABO/XPBarPage_Options.lua:47-61,519-525,997 | partiel : un seul texte on/off (options.md « Texte sur la barre ») | M |
| Fond du texte | Fond derrière le texte | oui | ABO/XPBarPage_Options.lua:1055 | absent | G |
| Style de remplissage (dégradé, animation au gain d'XP, boucle, étirée), couleur repos, fond | Remplissage animé | oui | ABO/XPBarPage_Options.lua:1125-1217 | absent | G |
| Superposition d'XP de quêtes (terminées/incomplètes, zone courante) | XP des quêtes avant le remplissage | oui | ABO/XPBarPage_Options.lua:1260-1321 | absent | M |
| Bordure personnalisée, texture de barre, taille du texte, clic traversant, rotation du texte (verticale) | Réglages communs XP/Rep | oui | ABO/MenuBagsRepPage_Options.lua:154-776 | partiel : orientation, longueur, épaisseur seulement | G |
| Barres Blizzard XP/réputation (case « utiliser celles de Blizzard ») | Bascule vers l'original | oui | ABO/MenuBagsRepPage_Options.lua:870 | équivalent (« Cacher les barres Blizzard ») | -- |
| Barre de Faveur de la maison, paragon, renommée | Barres retail | retail (Favor gaté, AB/EUI_ActionBars_DataBars.lua:590-733) ; paragon/renommée `?` | AB/EUI_ActionBars_DataBars.lua:462-463 | sans objet / non vérifié | -- |

---

### 6. Sacs

| Fonction | Ce qu'elle fait | Forever ? | Preuve EUI | Chez nous | Valeur |
|---|---|---|---|---|---|
| Styles d'affichage : Grille / Liste (une ligne par emplacement, colonnes triables) / Compact (blocs par groupe) | Trois rendus de fenêtre | oui | OPT/EUI_Bags_Options.lua:206 ; BG/EllesmereUIBags_List.lua:1-10 ; BG/EllesmereUIBags_Compact.lua:1-12 | absent (grille seule, ordre des sacs ou sections) | M |
| Barre latérale de catégories (icônes, réordonner par glisser, menu contextuel : renommer, regrouper, masquer) | Navigation par catégorie | oui | BG/EUI_Bags_Sidebar.lua:36-49 ; OPT/EUI_Bags_Options.lua:357-450 | partiel : sections titrées (`layout="categories"`), renommage par zones de texte (options.md « Catégories »), pas de barre latérale ni de glisser | M |
| Catégories personnalisées par glisser-déposer (« + » assigner) | Assigner un objet à une catégorie | oui | BG/EUI_Bags_Select.lua:83-141,191 | partiel : « Groupes libres » en texte d'identifiants | M |
| Épinglage par mode sélection (clic sur l'objet, glisser) | Pin Selection Mode | oui | BG/EUI_Bags_Select.lua:23-102 | partiel : liste d'identifiants saisie (options.md « Objets épinglés ») | M |
| Marqueur de camelote (Junk Marker) + vente auto de la camelote chez le marchand | Marque des objets à vendre, bouton Sell Junk | oui | BG/EUI_Bags_Select.lua:467-468 | partiel : signale la camelote grise (pièce), pas de marquage manuel ni vente (Bags.lua:398) | H |
| Aspect de la camelote (grisé, pièce) | Junk Item Visuals | oui | OPT/EUI_Bags_Options.lua:815-840 | partiel : pièce seulement (`junk`) | G |
| Niveau d'objet : taille, couleur unique ou qualité, rang de piste (Gear Track) | Réglages d'ilvl | oui (piste d'amélioration `?` retail) | OPT/EUI_Bags_Options.lua:475-541 | partiel : on/off seulement | G |
| Texte BoE / Lié au bataillon (taille) ; mots-clés de recherche BoP/BoE/WuE | Affiche le lien d'équipement, recherche par lien | oui | OPT/EUI_Bags_Options.lua:554-587 ; BG/EUI_Bags_Slots.lua:403-423 | absent | H |
| Nom de l'ensemble d'équipement sur les pièces | Affiche l'ensemble d'appartenance | oui | OPT/EUI_Bags_Options.lua:606-632 | absent | M |
| Scinder l'équipement par ensemble ; grouper l'équipement par emplacement (Armory), fusion des doublons | Regroupements d'équipement | oui | OPT/EUI_Bags_Options.lua:424,761-801 | absent | G |
| Imbrication par extension (Nest by Expansion) | Grille découpée par extension | `?` non vérifié (retail : expansionID) | OPT/EUI_Bags_Options.lua:100,615 | absent | G |
| Catégories listées : masquer les vides, masquer l'onglet « Ajouter », taille du titre, masquer icônes repliées | Réglages de barre latérale | oui | OPT/EUI_Bags_Options.lua:358-450 | absent | G |
| Échelle de fenêtre, strate (frame strata), taille auto, fenêtre redimensionnable (poignée + verrou) | Dimensions de fenêtre | oui | OPT/EUI_Bags_Options.lua:238-264 ; BG/EUI_Bags_Refresh.lua:221-479 | absent (colonnes et taille de bouton seulement, options.md « Sacs ») | M |
| Sac par défaut à l'ouverture ; ouvrir avec la fenêtre du personnage | Comportement d'ouverture | oui | OPT/EUI_Bags_Options.lua:222,1093 | absent | M |
| Icône de recharge, zoom des icônes, bordure de qualité en option | Cosmétique des cases | oui | OPT/EUI_Bags_Options.lua:817,944 | partiel : bordure de qualité fixe (Bags.lua:401), pas de zoom | G |
| Options de tri : « Sort to Bottom », tri en vue liste/compact | Sort Options | oui | OPT/EUI_Bags_Options.lua:911-913 ; BG/EUI_Bags_Header.lua:246-337 | partiel : un bouton Trier API client (Bags.lua:461-469) ; pas d'option | G |
| Fusion des piles (partiels) + tri par phases | Tri maison fusion puis ordre | oui | BG/EUI_Bags_Header.lua:149-246 | équivalent : bouton « Empiler » (Bags.lua:472-479) | -- |
| Diviseur de pile maison | Remplace StackSplitFrame | oui | BG/EUI_Bags_Shared.lua:517 | absent | M |
| Suivi de l'or de tous les persos + infobulle historique (ledger) | Or par personnage, historique | oui | BG/EUI_Bags_Footer.lua:20-69 ; EllesmereUI/EllesmereUI_GoldLedger.lua | partiel : or du personnage seulement (Bags.lua:483) | M |
| Monnaies suivies dans le pied de fenêtre (Enabled Currencies) | Pied avec monnaies | oui | OPT/EUI_Bags_Options.lua:943 ; BG/EUI_Bags_Footer.lua:20 | absent | M |
| Actions rapides (Quick Actions) : Désenchanter, Crochetage, Compréhension (parchemins Forever) sur l'objet survolé | Marque les objets sur lesquels un sort connu s'applique | oui (Compréhension Forever) | BG/EllesmereUIBags_QuickActions.lua:21,70-77,310 | absent | M |
| Sacs spéciaux Forever (carquois, munitions, âme, herbes, enchantement) : catégorie propre | Sacs à famille unique triés à part | oui | BG/EllesmereUIBags.lua:105-125 | absent | H |
| Sac des clés (Keyring) | Emplacements clés Forever | oui | BG/EUI_Bags_Start.lua:525 | absent | M |
| Catégories de campement Forever (objets de camp) | Catégorie « Camp » | oui | BG/EllesmereUIBags_Categories.lua:52-70 | absent | G |
| Icônes de barre supérieure (sacs, camelote, actions rapides, tri) | Icônes d'en-tête au choix | oui | OPT/EUI_Bags_Options.lua:861-875 | absent | G |
| Compat tiers : Pawn (flèches), CanIMogIt, TradeSkillMaster | Intégrations | oui | BG/EUI_Bags_Data.lua (en-tête) ; BG/EUI_Bags_Slots.lua:541 ; BG/EllesmereUIBags_Bank.lua:1243 | partiel : flèche d'amélioration intégrée (`upgrade`), pas de Pawn | G |
| Support manette | Navigation par contrôleur | oui | BG/EUI_Bags_Shared.lua:411 ; BG/EUI_Bags_Start.lua:440 | absent | G |
| Reliquat : sac de réactifs détaché | Fenêtre séparée | oui | BG/EUI_Bags_Footer.lua:442 | équivalent (`detachReagents`) | -- |

### 7. Banque

| Fonction | Ce qu'elle fait | Forever ? | Preuve EUI | Chez nous | Valeur |
|---|---|---|---|---|---|
| Coffre de bataillon (Warbank) : onglets, vue consolidée OneWarbank, or de bataillon | Banque de compte | oui | BG/EllesmereUIBags_Bank.lua:85,496,1660 | absent : onglets du personnage seulement (Bank.lua:33-53) | H |
| Vues OneBank / OneWarbank (tout-en-un) et vue « Tous les onglets » | Vue consolidée triable | oui | BG/EllesmereUIBags_Bank.lua:3-12 | absent (un onglet à la fois) | H |
| Recherche et tri dans la banque | Barre de recherche, bouton Trier | oui | BG/EllesmereUIBags_Bank.lua:3-5 | absent (pas de champ recherche ni tri, Bank.lua entier ; seule « recherche des sacs » citée en tête) | H |
| Affichage banque : Grille / Liste / Compact | Mêmes styles que les sacs | oui | OPT/EUI_Bags_Options.lua:72-90 | absent | M |
| Regroupement par catégorie, imbrication par extension, masquer les vides quand groupé | Grouping | oui (extension `?`) | OPT/EUI_Bags_Options.lua:100-141 | absent | M |
| Barre latérale de catégories de banque, masquer les onglets | Sidebar de banque | oui | OPT/EUI_Bags_Options.lua:121-129 ; BG/EllesmereUIBags_Bank.lua:999,2759 | absent | M |
| Fenêtre des sacs de banque Forever (emplacements-sacs des onglets) | Poser un sac dans un onglet acheté | oui | BG/EllesmereUIBags_Bank.lua:367-385 | partiel : détecte onglets/sacs (Bank.lua:33-53), pas de fenêtre de pose de sacs | M |
| Invite d'achat du 1er onglet gratuit | Bouton d'achat Blizzard | oui | BG/EllesmereUIBags_Bank.lua:1132-1150 | absent | G |
| File d'attente de transferts (clics droits rapides) | Évite les collisions de dépôts | oui | BG/EllesmereUIBags_Bank.lua:1285 | absent | M |
| Dépôt auto (réactifs) | Bouton « Déposer les réactifs » | oui | (pas relevé côté EUI : non vérifié) | présent (Bank.lua:152-161) | -- |
| Déplacement libre, échelle, taille auto, redimensionnement, verrou | Fenêtre mobile | oui | BG/EllesmereUIBags_Bank.lua:685 ; BG/EUI_Bags_Refresh.lua:221 | partiel : déplaçable (NS.Movers, Bank.lua:203), colonnes et taille de bouton seulement | G |

Équivalents complets : opacité de barre, boutons par barre/par ligne, taille et espacement des boutons, survol lié, mode raccourcis (propre), glisser verrouillé, proc glow au style choisi, désaturation en recharge, couleur du voile, texte de raccourci/macro on/off, masquage des barres Blizzard, déplacement/déverrouillage, colonnes et taille de bouton des sacs et de la banque, niveau d'objet, pièce de camelote, flèche d'amélioration, objets récents en tête, sections de catégories avec renommage et ordre, groupes libres (texte), recherche par nom, tri API client, fusion des piles, or du personnage, emplacements libres, sac de réactifs détaché.

### Limites client révélées

- AB/EUI_ActionBars_Range.lua:39-40 : `btn.action` est protégé (valeur secrète) ; le lire en combat fait tainter. EUI utilise une table bouton->barre bâtie au setup.
- AB/EUI_ActionBars_Flyout.lua:222-228 : le style d'interface Gamepad de Forever montre et cache le SpellFlyout depuis du code sécurisé ; un hook de l'addon taint. EUI laisse le flyout Blizzard intact sous ce style.
- AB/EUI_ActionBars_Vehicle.lua:78-84 : OverrideActionBar est protégée et gérée par Edit Mode ; SetParent/Hide la taintent, seuls SetAlpha et la souris sont permis.
- AB/EUI_ActionBars_Pushed.lua:236-250 : l'état « checked » et l'argument de SetChecked peuvent être secrets ; garde `issecretvalue`.
- BG/EUI_Bags_Slots.lua:159-169 ; BG/EllesmereUIBags_Grid.lua:73 : un bouton sécurisé ContainerFrameItemButtonTemplate créé en combat est tainté (UseContainerItem bloqué, ADDON_ACTION_FORBIDDEN) ; écrire des propriétés sur les sous-objets du modèle taint.
- BG/EllesmereUIBags_Bank.lua:3342 : SetScript sur BankFrame le taint ; BG/EUI_Bags_Start.lua:518 : jamais Show/Hide sur les cadres de sacs Blizzard (reparentage seulement).
- BG/EllesmereUIBags_QuickActions.lua:8-13 : bouton SecureActionButtonTemplate déplacé/affiché hors combat seulement, masqué à PLAYER_REGEN_DISABLED.
- OPT/EllesmereUI_Widgets_Visibility.lua:83-98 : conditions skyriding et logement marquées `forever = "never"/"always"` (absentes sur Forever).

### Non couvert

- Corps des fichiers AB/EUI_ActionBars_Events.lua (2456 l.), Setup.lua (1670 l.), XPBar.lua (1768 l.), Apply.lua : lus seulement par en-têtes et grep ; comportements internes non inventoriés.
- BG/EllesmereUIBags_Bank.lua (3410 l.), BG/EUI_Bags_Sidebar.lua (1789 l.), BG/EllesmereUIBags_Grid.lua : en-têtes et sections seulement.
- Disponibilité Forever non tranchée dans ~/wow-ui-source/forever : One Button Assist / Assisted Highlight, rang d'objet, imbrication par extension, Encounter Bar, Quick Keybind Mode, paragon.
- Pages d'options non relues ligne à ligne : ABO/LivePreview_Options.lua (aperçu), détails des « cogs » (ABO/BarAppearance_Options.lua lignes 1-1000 en partie).
- Fonctions de visibilité partagées (OPT/EllesmereUI_Widgets_Visibility.lua, EllesmereUI/EllesmereUI_Visibility.lua) : lues en tête seulement ; zone probable d'un autre inventaire.

## 9. Chat, minimap, quêtes, barres de données, amis, recherche de groupe

Légende : EUI_Chat_Options = EllesmereUIOptions/EUI_Chat_Options.lua ; ECH = EllesmereUIChat/. Chat : EUI remplace l'affichage Blizzard par un moteur à lui (ScrollingMessageFrame propre, onglets fantômes) ; nous restons sur ChatFrame1 Blizzard re-habillé (MuscaUI_Chat/Chat.lua).

### 1. Chat

| Fonction | Ce qu'elle fait | Forever ? | Preuve EUI | Chez nous | Valeur |
|---|---|---|---|---|---|
| Moteur d'affichage propre (cadre de messages à nous, texte Blizzard masqué, liens servis par les zones invisibles Blizzard) | Contrôle total du rendu (abréviations, horodatage, couleurs) sans toucher aux cadres sécurisés | oui | ECH/EllesmereUIChat_Engine.lua:3-19 | absent (rendu Blizzard re-skinné, Chat.lua) | M |
| Fondu au repos (activer, délai 5-30 s, force 0-100 %) | Le chat s'estompe après inactivité, réveil sur message joueur | oui | EUI_Chat_Options:438-470 ; ECH/EUI_Chat_EditBox.lua:25 | partiel : « secondes avant le fondu des lignes » + « ne jamais estomper » (fondu des lignes, pas du panneau avec force) options.md:1208+ | M |
| Verrouiller la taille du chat principal | Cache la poignée de redimensionnement | oui | EUI_Chat_Options:91 ; ECH/EUI_Chat_Position.lua:5-8 | absent (tailles par sliders, poignée Blizzard non masquée) | G |
| Style de bordure du panneau + taille de bordure + « Cacher les bordures » + couleurs de bordure interne | Bordures du panneau (Slim, Slim Textured, Heavy Bronze sous Forever) | oui | EUI_Chat_Options:227,251,414,1431 ; ECH/EllesmereUIChat_Forever.lua:19-23 | absent (bordure du thème fixe) | G |
| Kit de style Forever (plaques bronze, onglets bronze, glyphes ocre) | Habillage visuel Forever du chat | oui | ECH/EllesmereUIChat_Forever.lua:1-23 ; EllesmereUIChat.lua:145 | absent | G |
| Police du chat (choix de police + contour/ombre/épais, taille) | Police dédiée au chat (liste de polices, option « globale ») | oui | EUI_Chat_Options:159,172,192-195 | partiel : taille seule, police du thème (options.md:1208+) | M |
| Taille de police et police de la zone de saisie, hauteur de la zone de saisie | Typographie et hauteur du champ de saisie | oui | EUI_Chat_Options:1320,1346,1353 | absent (zone de saisie : seulement haut/bas) | M |
| Barre latérale : visibilité (toujours/survol/jamais), côté droit, largeur, fond caché, séparée (fond+bordure, espacement), taille d'icônes, couleur d'icônes (accent/perso), déplacement libre des icônes (Maj+clic), ordre par glisser | Colonne d'icônes à côté du chat, très configurable | oui | EUI_Chat_Options:477-740 ; ECH/EUI_Chat_Sidebar.lua:3-6 | partiel : barre de raccourcis gauche/droite, ordre en texte libre, taille fixe 20 (Chat.lua:567-613 ; options.md:1208+) | M |
| Icônes de la barre : Amis (QuickJoin), Guilde, Durabilité, Copier, Portails M+, Voix/Canaux, Menu du chat, Réglages, bouton Défiler vers le bas | Raccourcis cliquables | oui (sauf Portails M+ : retail) | EUI_Chat_Options:487-497 ; ECH/EUI_Chat_SidebarIcons.lua:3-6 | partiel : copy, friends, channels, options seulement (Chat.lua:568-575) ; absents : guilde, durabilité, voix, défiler vers le bas | M |
| Bouton Défiler vers le bas ancré sur le panneau | Bouton retour au bas dans le coin du panneau | oui | EUI_Chat_Options:741 | absent | M |
| Onglets dans le panneau (fond continu), espacement, hauteur, marge intérieure | Géométrie des onglets | oui (hors styles stock/Forever : seule la typographie s'applique) | EUI_Chat_Options:761-790 | absent | G |
| Police d'onglet (choix), couleurs de texte actif/inactif, couleurs de fond actif/inactif, texture d'onglet, bordure d'onglet (style, taille, bordure de l'onglet actif, synchro avec le panneau) | Apparence détaillée des onglets | oui | EUI_Chat_Options:800-1280 | partiel : taille de police, couleur de l'onglet actif, soulignement (options.md:1208+) | G |
| Onglets fantômes sur la vraie barre Blizzard (aucune écriture sur les onglets) | Technique anti-taint | oui | ECH/EllesmereUIChat_Tabs.lua:3-23 | non applicable (nous touchons les onglets : Chat.lua OnWindowResized etc., non vérifié pour taint) | G |
| Cacher l'infobulle au survol | Supprime l'infobulle de lien au survol | oui | EUI_Chat_Options:1384 | absent | G |
| Son de chuchotement au choix (liste de sons avec aperçu) / couper le son | Remplace ou coupe le son de /w | oui | EUI_Chat_Options:1442-1475 ; ECH ApplyWhisperMute | partiel : son sur mot-clé uniquement, pas de remplacement du son de chuchotement (options.md:1208+) | M |
| Horodatage : « Utiliser le réglage Blizzard », 6 formats, « horodater tous les messages » | Formats 12/24 h avec ou sans secondes | oui | EUI_Chat_Options:1520-1560 | partiel : liste Aucun/… (formats exacts non vérifiés) | G |
| Noms de canaux raccourcis avec option « lettres » (G, T, LD, WD, LFG) | [Party]->[P], canaux monde en lettres | oui | EUI_Chat_Options:1559-1600 | partiel : numéros seulement, pas le mode lettres (options.md:1208+) | G |
| Couleur de classe dans le texte (dire, crier, groupe, raid) | Colore les noms de membres de groupe/raid dans le texte | oui | EUI_Chat_Options:1568 | partiel : nous avons « couleur de classe sur tous les canaux » (équivalent probable) | G |
| Page « Chat Bubbles » (liens vers BlizzardSkin) | Réglages des bulles | oui | EUI_Chat_Options:1610 | partiel : MuscaUI_Chat/ChatBubbles.lua + options « Bulles de dialogue » (options.md:735) | G |
| Liens : URL cliquables, popup de copie (texte du chat, URL), infobulle de lien | Copier le chat / URL | oui | ECH/EUI_Chat_Links.lua:3-8 | équivalent (copie, URL) | - |
| Historique de session (lignes par onglet, hors journal de combat) | Persiste le chat au /reload | oui | ECH/EllesmereUIChat_SessionHistory.lua:3-15 ; EUI_Chat_Options:1373 | équivalent (options.md « Historique ») | - |

Équivalents complets : fond/opacité/texture, taille de police du chat, onglets plats, URL cliquables, bouton de copie, historique persistant (lignes max, effacer), zone de saisie en haut, tailles de fenêtres.
Absents chez EUI mais présents chez nous : mots-clés surlignés + son, anti-spam de répétitions, deux fenêtres gauche/droite, horodatage.

### 2. Minimap

Preuve = EllesmereUIOptions/EUI_Minimap_Options.lua (EUI_Minimap_Options) ; modules dans EllesmereUIMinimap/ (EMM).

| Fonction | Ce qu'elle fait | Forever ? | Preuve EUI | Chez nous | Valeur |
|---|---|---|---|---|---|
| Visibilité (règles combat/groupe/etc.) + opacité de la carte | Cache ou estompe la minimap selon contexte | oui | EUI_Minimap_Options:105-125,254 | absent (aucune visibilité sur la minimap, options.md:1570-1589) | M |
| Forme : carrée, rectangulaire (décalage largeur/hauteur), ronde, ronde texturée ; Forever Circle / Forever Square | Choix de forme et de cadre | oui | EUI_Minimap_Options:180-240 ; EMM Styles | partiel : carré/rond seulement (« Carte carrée », options.md:1578) | M |
| Style de bordure (textures), taille, couleur (accent, classe, perso), décalage X/Y, « derrière » | Bordure de la carte détaillée | oui | EUI_Minimap_Options:341-460,560 | partiel : bordure du thème fixe | G |
| Taille de la carte jusqu'à 600 | Plage de taille | oui | EUI_Minimap_Options:270 | partiel : 100-400 (options.md:1578) | G |
| Taille des icônes sur la carte (groupe, objectifs, gisements) | Équivalent du réglage Edit Mode « Icon Size » | ? | EUI_Minimap_Options:320 | absent | G |
| Taille des boutons interactifs (courrier, calendrier, suivi, bascule du groupe) | Échelle des boutons Blizzard conservés | oui | EUI_Minimap_Options:304 | absent (tout le décor Blizzard est caché, MinimapFrame.lua:43-46) | G |
| Remise à zéro du zoom après N secondes (0-15) | Dézoome automatiquement | oui | EUI_Minimap_Options:585 ; EMM/EUI_Minimap_Buttons.lua:3 | absent | M |
| Rotation de la minimap (CVar rotateMinimap) | Carte tournante | ? (CVar existe dans Camelot/Skin.lua:21 de wow-ui-source) | EUI_Minimap_Options:593 | absent | M |
| Dégrouper des boutons d'addons (liste cochable, hors flyout) | Sort certains boutons du regroupement | oui | EUI_Minimap_Options:645 | partiel : mode groupé/individuel global (liste « Boutons d'addons », options.md:1584) | M |
| Taille des boutons dans le flyout (14-40) | Taille des boutons regroupés | oui | EUI_Minimap_Options:652 | équivalent (16-40) | - |
| Boutons supplémentaires : Grand Coffre, Amis en ligne, Portails M+, Bouton de groupe (cochables, réordonnables par glisser) | Rangée d'indicateurs custom | oui pour Amis/Groupe ; retail pour Coffre et Portails (non construits sur Forever) | EUI_Minimap_Options:755-810 ; EMM/EUI_Minimap_Indicators.lua:3-5 | absent (pas de boutons Amis ni Groupe) | M |
| Boutons « au survol de la carte seulement » (extras et dégroupés) | Masque la rangée hors survol | oui | EUI_Minimap_Options:759 | absent | M |
| Échelle du flyout Portails M+ | Taille du flyout | retail | EUI_Minimap_Options:840 | n/a | - |
| Clic milieu = ouvrir le micro-menu | Raccourci | oui | EUI_Minimap_Options:847 ; EMM Lifecycle:3 | absent | G |
| Infobulle Amis (plafond de lignes, afficher les notes), échelle d'infobulle perso | Infobulle custom amis/guilde/calendrier/courrier/suivi | oui | EUI_Minimap_Options:864-890 ; EMM/EUI_Minimap_Tooltips.lua:3-4 | absent | M |
| Infobulle calendrier avec liste des verrous d'instance (sur horloge ou FPS/MS : « Verrous ») | Survol de l'horloge montre les verrous | oui (la valeur « vault » est retirée sur Forever) | EUI_Minimap_Options:1686-1715 ; EMM Tooltips | absent | M |
| Position de la rangée de boutons (coin), déplacement libre (Maj+clic), espacement, distance, sens du flyout, fonds des boutons | Mise en page de la rangée | oui | EUI_Minimap_Options:915-990 | partiel : rangée fixe sous la carte (options.md:1584-1586) | G |
| Éléments Blizzard afficher/cacher individuellement : calendrier, courrier, suivi, ordre d'artisanat, difficulté, zoom +/- ; position de la rangée, position du courrier, décalages | Rend les boutons Blizzard un par un | oui (pour ceux qui existent sur Forever) | EUI_Minimap_Options:1139-1290 | absent : tout est caché en bloc (« Cacher le décor Blizzard », options.md:1580) ; pas de courrier/calendrier/suivi accessibles | H |
| Omnium Folio (landing page d'extension) : afficher, échelle, coin, décalages | Bouton de la page d'extension | retail (« No expansion landing page on WoW Forever ») | EUI_Minimap_Options:1029-1085 | n/a | - |
| Bouton du compartiment d'addons : afficher, échelle, coin, décalages | Compartiment Blizzard | ? (AddonCompartment.xml dans le dossier Mainline de wow-ui-source/forever) | EUI_Minimap_Options:1097-1130 ; EMM Styles:3 | absent (caché, MinimapFrame.lua:46) | G |
| Horloge : style (aucune/dans la carte/boîte au bord), position, échelle, décalages, AM/PM accentué | Horloge intégrée à la carte | oui | EUI_Minimap_Options:1319-1370 ; EMM/EUI_Minimap_Info.lua:3 | absent (horloge Blizzard cachée ; l'heure est sur TopBar) | M |
| Nom de zone : style (dans la carte/boîte au bord), position, sous-zone, coloration réactive (PvP), échelle, décalages | Nom de zone paramétrable | oui | EUI_Minimap_Options:1394-1470 | partiel : nom de zone au-dessus, activable seulement (options.md:1578) | G |
| Coordonnées : position (7 emplacements), échelle, décalages | Placement des coordonnées | oui | EUI_Minimap_Options:1491-1565 | partiel : 3 modes d'affichage + décimales (options.md:1580-1582) | G |
| FPS/MS : position, taille de texte, ms local/monde, intervalle 1-5 s, échelle, décalages | FPS et latence sur la carte | oui | EUI_Minimap_Options:1577-1670 | partiel : case seule (options.md:1583) | G |
| Difficulté d'instance en texte : position, taille, couleur réactive par palier | Texte de difficulté | oui | EUI_Minimap_Options:1724-1775 | partiel : compacte « 5 », « 10H » seulement | G |
| Texte accentué (couleur d'accent sur AM/PM, suffixes FPS/MS, lettre de difficulté) | Colorisation | oui | EUI_Minimap_Options:1797 | absent | G |
| Style Blizzard / Classique pour la minimap | Looks de base | oui | EMM/EUI_Minimap_Styles.lua:3-5 | absent | G |
| Compat Farming HUD | Support d'un addon externe | ? | EMM/EUI_Minimap_Lifecycle.lua:3-5 | absent | G |

Équivalents complets : zoom molette, taille du bouton d'addon, coordonnées sous la carte, nom de zone au-dessus, FPS/latence, difficulté compacte, cacher le décor.

### 3. Suivi de quêtes

Preuve = EUI_QuestTracker_Options.lua ; EQT = EllesmereUIQuestTracker/. Le suivi reste celui de Blizzard (ObjectiveTrackerFrame), simplement habillé (EQT.lua:1-9), comme chez nous.

| Fonction | Ce qu'elle fait | Forever ? | Preuve EUI | Chez nous | Valeur |
|---|---|---|---|---|---|
| Trier les quêtes suivies : ordre du journal, zone, niveau, nom, progression, type ; terminées en haut/bas/mêlées ; tri secondaire | Réordonne la liste suivie (RemoveWatch/AddWatch) | oui (Forever uniquement) | EUI_QuestTracker_Options:494-520 ; EQT/EllesmereUIQuestTracker_Forever.lua:1-9,388-405 | absent | H |
| Filtrer les quêtes (zone courante, masquer terminées, masquer bas niveau, masquer quotidiennes/hebdo, bouton de bascule sur l'en-tête) | Détrack automatique selon filtres | oui | EUI_QuestTracker_Options:523-545 ; EQT Forever | absent | H |
| Suivi automatique des quêtes de la zone / du donjon | Suit les quêtes de la zone, retire à la sortie | oui | EUI_QuestTracker_Options:527 | absent | H |
| Interrupteur « Outils de quête expérimentaux » (verrouille les trois ci-dessus) | Garde-fou | oui | EUI_QuestTracker_Options:449 | n/a | - |
| Annoncer la progression au groupe/instance (jamais en raid) | Message de progression en chat | oui | EUI_QuestTracker_Options:476 ; EQT Forever:643 | absent | M |
| Son d'objectif terminé / son de quête terminée (liste de sons dont voix de péon) | Sons personnalisés | oui | EUI_QuestTracker_Options:480-483 ; EQT Forever:653-670 | absent | M |
| Couleur des objectifs selon progression | Dégradé par avancement | oui (FOREVER) | EUI_QuestTracker_Options:366 | absent (couleurs fixes par état) | M |
| Estomper les objectifs terminés (opacité) | Dim des lignes finies | oui | EUI_QuestTracker_Options:396-406 | absent | G |
| Masquer tous les objectifs | Titres seuls | oui | EUI_QuestTracker_Options:216 | absent | M |
| Icônes de quête natives Blizzard ou icônes EUI (rechargement) | Style des icônes de quête | oui | EUI_QuestTracker_Options:200 | absent | G |
| Opacité du fond, ligne d'accent en haut | Fond et filet du tracker | oui | EUI_QuestTracker_Options:134-139 | absent (en-têtes sans fond seulement, options.md:1907+) | G |
| Couleurs : en-tête, ligne, focalisé (classe / accent / perso), police au choix | Palette complète | oui | EUI_QuestTracker_Options:235-365,181 | partiel : couleurs titres/objectifs/terminé + taille ; pas de police au choix ni de couleur de classe/accent | G |
| Masquer en raid : Toujours / Combat de boss | Règle de raid fine | oui | EUI_QuestTracker_Options:120 | partiel : « En raid » liste (options.md:1907+) ; « combat de boss » absent (non vérifié) | M |
| Auto-accept : empêcher l'acceptation multiple, Maj pour passer, ignorer quêtes bas niveau | Réglages fins d'acceptation auto | oui | EUI_QuestTracker_Options:559-590 ; EQT/QoL.lua:1-6 | partiel : une case + Maj (Automation.lua:281 ; options.md:1346) | M |
| Auto-turn-in : Maj pour passer | Rendu auto | oui | EUI_QuestTracker_Options:562,590 | équivalent | - |
| Liens Wowhead au clic droit (langue du client, aller aux commentaires) | Lien copiable dans le menu | oui | EUI_QuestTracker_Options:601-620 ; EQT/QuestLinks.lua | absent | M |
| Raccourci d'objet de quête | Touche vers l'objet de la quête | oui | EQT/QoL.lua:6-15 | équivalent (options.md:1907+) | - |
| Correctif taint SplashFrame (OnHide cloné) | Évite un taint du tracker | oui | EQT/QoL.lua:10-23 | non vérifié chez nous | G |

Équivalents complets : hauteur, tailles des titres/objectifs, replier en combat/instance, visibilité par conditions, mover, raccourci d'objet de quête.
Absents chez EUI mais présents chez nous : replier en instance/combat, hauteur réglable.

### 4. Barres de données (EllesmereUIDataBars)

Preuve = EllesmereUIOptions/EllesmereUIDataBars_Options.lua (EDB_Options, fichier à la racine du dossier, pas EUI_*) ; moteur = EllesmereUIDataBars/EllesmereUIDataBars.lua (EDB) ; blocs = EllesmereUIDataBars/Blocks/*.lua.
Côté nous, le rôle est partagé entre trois modules : Modules/DataBars.lua (barres XP et réputation), Modules/DataPanels.lua + Core/DataTexts.lua (panneaux à emplacements), Modules/TopBar.lua (barre du haut figée). EUI fusionne tout en un moteur de barres créées à volonté contenant des blocs.

| Fonction | Ce qu'elle fait | Forever ? | Preuve EUI | Chez nous | Valeur |
|---|---|---|---|---|---|
| Barres illimitées créées par l'utilisateur (modèles Bottom Info Bar, Minimap Companion, Micro Menu Strip, vide), renommer, supprimer | Moteur multi-barres | oui | EDB:1-15,2812-2860 | partiel : jusqu'à 12 panneaux de données à emplacements égaux (DataPanels.lua:61, options.md:1622+) ; pas de modèles prêts ni renommage | M |
| Blocs de largeur auto ou répartition égale, bloc « remplir l'espace restant », « centrer de force », marges gauche/droite par bloc, ajout/retrait/réordonnancement par glisser | Mise en page par bloc | oui | EDB:1-48 ; EDB_Options:2184-2230,1769 | partiel : emplacements égaux uniquement, échange par Maj+glisser (options.md:1622) | M |
| Réglages de barre : orientation, longueur pleine/personnalisée, épaisseur, accrochage au bord d'écran, strate, bordure cachée, style de fond (EllesmereUI / moderne), texture, opacité, atténuation, échelle du texte, surbrillance au survol des blocs | Habillage de barre | oui | EDB_Options:1807-2130 | partiel : largeur, hauteur, opacité du fond (DataPanels, options.md:1622+) | G |
| Règles de visibilité par barre (multi-conditions, survol) | Cache selon combat/groupe/etc. | oui | EDB:46,2196 | équivalent (visibilité des panneaux et de la barre du haut, options.md:1650+) | - |
| Style par bloc : couleur du texte (perso, classe, accent, couleur de pièce, couleurs de crest, dynamique), fond de bloc, couleur et affichage d'icône, échelle, alignement, décalages X/Y | Habillage par bloc | oui | EDB_Options:2184-2740 | absent | G |
| Bloc Horloge : heure locale/serveur, 24 h, courrier, repos | Horloge | oui | EDB_Options:2872-2890 ; Blocks/Clock.lua | équivalent (barre du haut : 24 h, serveur, zzz ; courrier : non vérifié) | - |
| Blocs FPS et Latence séparés (domicile, monde, les deux, icône) ; Combat ; Durabilité (icône) ; Sacs (affichage, alerte d'emplacements bas) | Textes de performance | oui | EDB_Options:2906-2925,3250-3265 ; Blocks/Stats.lua,Bags.lua | partiel : « perf » unique FPS+latence, durabilité et sacs présents sans alerte de seuil (TopBar.lua:694) | G |
| Bloc Lieu : largeur auto/manuelle, largeur max ; Coordonnées (décimales) | Zone et coordonnées | oui | EDB_Options:2938-3000 ; Blocks/Location.lua | partiel : coordonnées présentes (DataTexts « coords ») ; nom de zone absent comme texte | M |
| Bloc Or : décomposition (argent/cuivre), infobulle (session, personnages, jeton WoW), suivi d'or et historique multi-personnages | Or détaillé | oui (jeton WoW : non vérifié sur Forever) | EDB_Options:2825,3016-3035,3583-3585 ; Blocks/Gold.lua | partiel : registre d'or par personnage (GoldLedgerTooltip, TopBar.lua:310) ; session/jeton : non vérifié | M |
| Bloc Expérience/Réputation (mode auto/XP/rep, texte valeurs/pourcentage/format) | Barre XP et réputation dans une barre | oui | EDB_Options:3041-3070 ; Blocks/XPRep.lua | partiel : deux barres séparées XP + rép (DataBars.lua) ; pas de bascule auto en un bloc, pas de pourcentage | M |
| Bloc Spécialisation et spé de butin | Bascule de spé | retail (« one spec per class on WoW Forever ») | EDB:285-290 ; Blocks/Spec.lua:2 | n/a | - |
| Bloc Métiers / Métiers secondaires (icônes) | Compétences de métier | oui (3e entrée secondaire sur Forever) | EDB_Options:2770 ; Blocks/Profession.lua:54 | partiel : texte « professions » (DataTexts.lua:257) ; secondaires et icônes : non vérifié | M |
| Bloc Voyage (cooldowns pierre de foyer et téléports), choix de la pierre au clic gauche (aléatoire) | Pierres et téléports | oui (M+ téléports : retail) | EDB_Options:3122,2833 ; Blocks/Travel.lua:304 | partiel : bouton pierre de foyer fixe 6948 + menu Voyage dans la barre du haut seulement (TopBar.lua:13,385) ; pas de choix ni aléatoire | M |
| Bloc Micro-menu (icônes réglables : menu, guilde, social, perso, sorts, hauts faits, quêtes, recherche de groupe, PvP, logement, journal, collections, boutique, aide ; espacement ; items visibles) | Micro-boutons Blizzard re-créés | oui | EDB_Options:3148-3190,3653-3666 ; Blocks/MicroMenu.lua:269,552 | absent | M |
| Bloc Devise (n'importe quelle devise découverte) | Une devise | oui | EDB_Options:3192 ; Blocks/Currency.lua | équivalent (texte « currency », DataTexts.lua:332) | - |
| Bloc Niveau d'objet (équipé/total, décimales) | iLvl | oui | EDB_Options:3273-3290 | partiel : « itemlevel » (DataTexts.lua:278), équipé/total non vérifié | G |
| Bloc Audio (barre de volume, canal choisi) | Volume du son | oui | EDB_Options:2855 ; Blocks/Audio.lua | absent | G |
| Bloc Plugin LibDataBroker (un bloc par plugin, icône, libellé, texte, couleurs retirées, largeur max) | Texte de plugin broker | oui | EDB_Options:3312-3350 ; Blocks/LDB.lua | équivalent (ldb:<nom>, DataTexts.lua:382-405) | - |
| Bloc Ressources de classe (Supplies : composants/munitions/poisons par classe) | Compteur des consommables de classe | oui (FOREVER seul) | Blocks/Supplies.lua:1-2 ; EDB:285-287 | absent | M |
| Bloc Grand Coffre / Insignes (Crests) | Contenu saisonnier | retail | Blocks/GreatVault.lua:2 ; Blocks/Crests.lua:2 | n/a | - |
| Bloc Espaceur | Espacement | oui | Blocks/Spacer.lua | n/a (emplacements égaux) | G |
| Mode de visibilité « verrous d'instance » sur l'infobulle d'horloge | Voir section 2 | oui | EUI_Minimap_Options:1686 | absent | M |

Équivalents complets : visibilité multi-conditions, horloge, devise, plugin LDB, mover par barre, textes coordonnées/quêtes/régénération/vitesse/DPS (propres à nous).
Barres XP/rép : EUI propose les mêmes via le bloc xprep (voir ci-dessus).

### 5. Amis (EllesmereUIFriends)

Fait notable : sur Forever, le module EllesmereUIFriends « ne se charge jamais » ; ses fonctions sont reprises par la carte « Friends List » de Blizzard Skins+ (EllesmereUI/EllesmereUI_FriendsKit.lua:3-10 ; EllesmereUIBlizzardSkin/EllesmereUIBlizzardSkin_FriendsForever.lua ; options EUI_BlizzardSkin_Options.lua:1698-1760, hors de ma zone). Les lignes ci-dessous valent donc pour la carte Forever. Chez nous : FriendsFrame est seulement dans la liste générique des fenêtres habillées (Skin.lua:302 ; options.md:1460), sans réglage propre.

| Fonction | Ce qu'elle fait | Forever ? | Preuve EUI | Chez nous | Valeur |
|---|---|---|---|---|---|
| Tuiles « Social UI 12.1 » (carte d'ami : icône de classe, nom, personnage, infos, fond en dégradé pour les connectés, survol, sélection) | Redécore les cartes Blizzard de la liste d'amis | oui (dossier Blizzard_SocialUI présent dans wow-ui-source/forever) | EUI_FriendsKit.lua:771-870 | absent | M |
| Thème des icônes de classe (plusieurs styles) | Sprite de classe sur chaque ligne | oui | EUI_Friends_Options:134 ; EUI_FriendsKit.lua:885 | absent | G |
| Noms colorés par classe dans la liste | Colorise le nom | oui | EUI_Friends_Options:145 | absent | G |
| Bordure (taille, couleur perso/accent) | Cadre de la fenêtre | oui | EUI_Friends_Options:156-220 | absent | G |
| Couleurs d'accent et bannières de faction | Habillage par faction/état | oui | EUI_Friends_Options:224-240 | absent | G |
| Icônes de région (ami d'une autre région) | Petite carte pour amis hors région | oui (Battle.net) | EUI_Friends_Options:242 ; EUI_FriendsKit.lua:19-40 | absent | M |
| Accepter automatiquement les invitations de groupe des amis (+ guildmates) | Auto-accept | oui | EUI_Friends_Options:250-275 | équivalent : « Accepter les invitations de groupe des amis, de Battle.net et de la guilde » (options.md:1346) | - |
| Habillage direct de la liste native (sans groupes d'amis) ; onglet Raid habillé ; échelle, position, fond, tuile | Fenêtre d'amis habillée | retail pour le module ; Forever via BlizzardSkin | EllesmereUIFriends.lua:2-6,114-118,506 | partiel : habillage générique du cadre seulement | G |
| Neutralisation sous interface Gamepad / Social UI (évite le taint BNet) | Garde-fou | oui | EllesmereUIFriends.lua:78-81 ; EUI_FriendsKit.lua:1705,1803 | non vérifié | G |

Équivalents complets : acceptation automatique des invitations (amis, guilde).

### 6. Recherche de groupe (EllesmereUIGroupFinder)

Fait notable : le module est un habillage de la fenêtre « Donjons et raids » moderne (LFGList Mainline, saisonnier : clé M+, délves, boss de raid). Le .toc annonce 16001 (EllesmereUIGroupFinder.toc:1) mais aucun code du dossier n'est gaté par IS_FOREVER (grep vide). Le client Forever embarque deux piles : Blizzard_GroupFinder/Mainline/LFGList.lua ET Blizzard_GroupFinder_VanillaStyle (Browse/Listing) (wow-ui-source/forever/Interface/AddOns). Lequel est utilisé sur 1.60.1 : non vérifié, donc « ? » partout.
Preuve = EUI_GroupFinder_Options.lua (EGF_Options), EllesmereUIGroupFinder/EUI_GroupFinder_Search.lua (EGF_Search) et _Applications.lua (EGF_Apps).

| Fonction | Ce qu'elle fait | Forever ? | Preuve EUI | Chez nous | Valeur |
|---|---|---|---|---|---|
| Panneau de filtres client (donjons de la saison + filtre avancé, région, difficulté, classes à sorts utiles : Soif de sang, Résurrection de combat, etc., rôles manquants, Party Fit, note minimale du chef, « Non refusé », sur les boss de raid encore en vie, délves Bountiful/tier, styles de jeu) ; réinitialiser | Filtre les résultats sans toucher à la liste Blizzard (fondu) | ? | EGF_Search:135-760,859-884 ; EGF_Options:71 | absent (Modules/GroupFinder.lua se limite à inscription rapide et note) | H |
| Liste enrichie : icônes de spé à la place des icônes classe/rôle, taille d'icône des rôles, couronne du chef, note du chef affichée, rôles manquants sur les groupes de 5, noms colorés (nouveau/refusé), infobulle avec membres, abréviations des donjons, niveau de clé par donjon | Réglages « Group Settings » du panneau | ? (M+ et notes de score : retail) | EGF_Search:897-990 ; EGF_Options:59-60 ; EGF_Search « Group Settings » | absent | M |
| Annuler la plus ancienne candidature au clic quand la limite est atteinte | Débloque l'inscription au plafond | ? | EGF_Search (« Cancel Oldest Application ») | absent | M |
| Double-clic sur une ligne = s'inscrire, Maj pour garder le dialogue | Inscription rapide | ? | EGF_Search (« Quick Signup ») | équivalent : inscription auto quand un seul rôle est coché (options.md:1859) | - |
| Note de candidature persistante (bouton Copier) | Note mémorisée | ? | EGF_Search (« Persistent Signup Note ») | équivalent (options.md:1859, note mémorisée) | - |
| Barre des candidatures M+ (acceptées, refusées, retirées de la liste, annulées) par session / personnage / compte ; texture ; remise à zéro | Statistiques de candidatures | retail (M+) | EGF_Options:109-200 ; EGF_Apps:1-3 | absent | G |
| Interrupteur « Activer Group Finder » (rechargement) ; incompatible avec Premade Groups Filter | Activation | ? | EGF_Options:68-100 | n/a | - |

Équivalents complets : inscription rapide, note mémorisée.

### Limites client révélées

Nouveaux faits trouvés dans ces modules (tous issus de commentaires EUI ; « non vérifié » sur Forever sauf mention, car mesurés sur leurs clients) :
- Chat : appeler FCFDock_SelectWindow (ou toute gestion d'onglet) depuis du code insécurisé tache dock.selected/isDirty ; la création sécurisée d'une fenêtre de chuchotement meurt ensuite sur un calcul d'en-tête avec valeur secrète (ECH/EllesmereUIChat_Tabs.lua:8-14). Même doctrine : ne jamais hooksecurefunc un FCF_* (ECH/EllesmereUIChat_Engine.lua:21-23).
- Chat : les lignes de chat peuvent être des valeurs secrètes ; elles sont ignorées à la lecture/copie et jamais stockées dans l'historique (ECH/EUI_Chat_Links.lua:20-35 ; ECH/EllesmereUIChat_SessionHistory.lua:6-9). Marqueur d'échappement |K...|k pour les valeurs secrètes (EUI_Chat_Links.lua:28).
- Chat : Edit Mode réécrit la position de ChatFrame1 à chaque application de layout ; sur un préréglage Blizzard on ne peut pas l'écrire, il faut une garde qui la replace dans la même image (ECH/EUI_Chat_Position.lua:22-32).
- Suivi de quêtes : fixer le super-track depuis du code d'addon tache la carte du monde (EQT/EllesmereUIQuestTracker_Forever.lua:393-394).
- Suivi de quêtes : modifier la liste de suivi (AddWatch/RemoveWatch) déclenche QUEST_WATCH_LIST_CHANGED de façon synchrone, donc les gestionnaires Blizzard tournent sous notre taint ; sous restrictions d'auras le flush du suivi de scénario peut lever une erreur dure ; EUI ne le fait que hors combat, hors rencontre, carte fermée (Forever.lua:411-420).
- Suivi de quêtes : appeler ShowQuestComplete depuis l'addon (QUEST_AUTOCOMPLETE) tache les attributs de WorldMapFrame et casse les pins de carte en combat (QoL.lua:121-127). L'OnHide de SplashFrame appelant ObjectiveTrackerFrame:Update() tache le bouton de quête et le cadre d'argent (QoL.lua:10-23,37).
- Amis : habiller FriendsFrame sous le Social UI re-ancre des ScrollBox Blizzard et tache le chuchotement Battle.net (SetTellTarget sur une cible secrète) (EllesmereUIFriends.lua:78-81). Créer textures/cadres dans l'arbre RaidFrame tache définitivement ClaimRaidFrame -> RaidFrame:SetParent (EllesmereUIFriends.lua:116-118).
- Recherche de groupe : les résultats de LFGList sont secrets en contenu restreint, les filtres client s'arrêtent (EGF_Search:824) ; le rôle d'un membre peut être secret, Party Fit s'arrête (EGF_Search:770-772). Les cadres Blizzard ne bougent qu'hors combat (EGF_Search:70-72).
- Forever : pas de Grand Coffre, pas de crests, une seule spé par classe, pas de page d'extension (Omnium Folio), pas d'extension plus ancienne à ignorer (EDB:285-290 ; EUI_Minimap_Options:1029 ; EUI_QuestTracker_Options:577). Forever a un chat/minimap en « kit bronze » dessiné par un cadre de la micro-menu (ECH/EllesmereUIChat_Forever.lua:14-23).
- Forever : la classe est inconnue pour « Class Resources » : EUI ajoute un bloc « Supplies » propre à Forever (composants, munitions, poisons) (EDB:285-287 ; Blocks/Supplies.lua:1-2).

### Non couvert

- Rendu des fichiers Media (textures, sons du chat) et EllesmereUIChat_SidebarStock.lua (635 l.) lus seulement par en-tête.
- Contenu interne de EllesmereUIFriends.lua (3246 l.), EUI_GroupFinder_Search.lua (3803 l.), EllesmereUIDataBars.lua (3301 l.) et des blocs Blocks/*.lua : lus par en-têtes, tooltips d'options et grep, pas ligne à ligne.
- Page « Chat Bubbles » et carte « Friends List » (EllesmereUIOptions/EUI_BlizzardSkin_Options.lua), hors de ma zone.
- Formats d'horodatage exacts de MuscaUI_Chat (non lus), détails de TopBar (courrier de l'horloge), presence de « jeton WoW » sur Forever, et savoir si 1.60.1 utilise la pile LFGList Mainline ou VanillaStyle (non vérifié).
- Aucune vérification en jeu ; aucune lecture de ~/wow-ui-source au-delà des listes de dossiers et de quelques grep.

### Décompte approximatif des fonctions manquantes ou partielles
H : 6 (éléments Blizzard de la minimap individuels, tri/filtre/suivi auto de quêtes, filtres de recherche de groupe). M : ~38. G : ~40.

## 10. Habillage Blizzard, compteur de dégâts, M+, menu radial

Fichiers EUI : `O` = EllesmereUIOptions/EUI_BlizzardSkin_Options.lua. Chez nous : Modules/Skin.lua (`Skin`), docs/options.md sections « Habillage », « Fenêtres déplaçables », « Fiche de personnage ».

### 1. Habillage des fenêtres Blizzard (BlizzardSkin)

Contexte : EUI a une carte par fenêtre (liste `WINDOWS`, O:2178-2650) ; sur Forever il retire seulement greatvault, delvepicker, housing (O:2662-2670). Nous : ~49 cadres listés Skin.lua:301-309, un style chacun (thème / sombre / Blizzard), sans réglage propre par fenêtre.

| Fonction | Ce qu'elle fait (1 ligne) | Forever ? | Preuve EUI | Chez nous | Valeur |
|---|---|---|---|---|---|
| Looks globaux (EUI / Modern / Blizz Default / Forever) + « Appliquer à tout » | Choix de look pour toutes les fenêtres, par profil, interrupteur maître par profil | oui | O:2042-2047, O:3180-3250 ; EllesmereUIBlizzardSkin.lua:347-431 (look "forever") | partiel : 3 styles thème/sombre/Blizzard, défaut + exceptions par fenêtre, interrupteur général global (pas par profil) ; options.md « Panneaux » | M |
| Réglages globaux : barre d'accent sur l'onglet actif, opacité du remplissage de barre, couleur des liens (accent/perso) | Look commun à toutes les fenêtres | oui | O:3263-3320 | absent | G |
| Habillage des addons tiers (API de skin) + interrupteur par addon | Skin d'autres addons via l'API EUI | oui | O:3114-3178 | absent (pas d'API publique de skin) | G |
| Fiche de personnage entière : catégories de stats (Attributs, Secondaires, Tertiaires, Attaque, Défense, Crests), couleurs, ordre, rendements décroissants, surlignage stats sec./tert. | Panneau de stats refait, réordonnable | oui (CharacterSheetForever.lua, O:1380-1540) ; crests/Mythique+/Saison = retail | O:1380-1540 ; CharacterSheetForever.lua:60 | absent (on ne refait pas le panneau de stats ; seulement ilvl/enchant) | M |
| Fiche : détails par objet (niveau d'objet, piste d'amélioration, lettres de stats, stats tertiaires, gemmes), durabilité par objet (emplacement, étiquette), enchantements (aucun / icônes+survol / texte, taille), ilvl PvP, zoom d'icône | Texte sur chaque emplacement | oui (gemmes, lettres : gaté ; O:1037, 1055, 1158-1175) | O:1028-1300 | partiel : ilvl + « ! » enchant manquant + taille texte (options.md « Fiche de personnage ») ; absent : piste d'amélioration, lettres de stats, gemmes, durabilité par objet, texte d'enchant, ilvl PvP | M |
| Panneau de sertissage (Socket Panel) à côté de la fiche | Panneau de gemmes/sockets | retail (SocketPanel.lua:1469 retourne si Forever) | O:1102-1135 | absent | retail |
| Fiche : flyout d'équipement (ilvl, stats en lettres, masquer flèches des emplacements) | Infos dans la liste d'échange d'objet | partiel : ilvl oui, lettres non (O:1324, 1346 gatés `not IS_FOREVER`) | O:1320-1360 | absent | M |
| Panneau de saison / Grand Coffre | Raccourcis Omnium/Coffre | retail | O:1226-1320 ; GreatVault.lua | absent | retail |
| Score M+ sur la fiche | Cote Mythique+ | retail | O:1059 | absent | retail |
| Fenêtre d'inspection : activer, enchants (mode, taille), niveau d'objet, piste d'amélioration | Fiche d'inspection au thème avec infos | oui | O:1554-1640 ; InspectSheet.lua:169 | partiel : ilvl sur inspection (options.md « Fiche de personnage ») ; absent : enchants affichés, piste d'amélioration, skin complet | M |
| Cartes de fenêtres avec skin propre : Journal de rencontre (adventureguide), Collections, Talents+Grimoire, Métiers+Livre de métiers, Carte+Journal de quêtes, Guilde+Communautés, Calendrier, Hauts faits, Courrier, Catalyseur, Sertissage, Amélioration d'objet, Butin, Toasts de butin, Notifs ami BNet, Jets de butin, Historique de butin, Invitation de groupe, Appel (ready check), Micro-menu, Barre de sacs, Cabine d'essayage, Transmo, Marchand, HV, Macros, Options, Liste d'addons, Commandes d'artisanat, Entraîneur, Dialogue PNJ, Quêtes, Recette inspectée, Compagnon de gouffres, Liste d'amis, État de file, Choix de joueur, Échange, Progression Legacy | Un skin par fenêtre avec dropdown de style | oui (cartes gardées sur Forever, O:2662) ; contenu retail (catalyseur, commandes d'artisanat, gouffres) : non vérifié | partiel : nous habillons ~49 cadres (Skin.lua:301-309) en thème plat/sombre sur les cadres existants. Pas de cadres équivalents pour : Barre de sacs, Micro-menu, Toasts (butin, BNet), Historique de butin, Invitation de groupe (popup), État de file / popup de file, Progression Legacy, Compagnon, Choix de joueur, Catalyseur, Amélioration d'objet, Sertissage, Commandes d'artisanat, Recette inspectée | M |
| Grand Coffre, Sélecteur de palier de gouffre, Tableau de bord Housing | Skins retail | retail (retirés sur Forever, O:2662-2670) | O:2225, 2627, 2438 | absent | retail |
| Contenu extra par fenêtre : Marchand (liste, hauteur de ligne, ilvl, achat en masse), Toasts de butin (bandeau qualité, or, échelle), Courrier (liste des alts, tri, niveau mini), Amis (thème d'icônes de classe, acceptation auto d'invitations, guildiens), LFG (mémoriser les rôles) | Extras fonctionnels | marchand/butin/amis : oui ; LFG rôles et Courrier alts : retail (O:2333-2334, 1674 gatés) | O:1681, 1729-1770, 1810-1860, 1880-1910 | absent (Marchand liste/achat en masse, acceptation auto d'invitations d'amis, icônes de classe amis). Voir aussi chez nous : Butin dans l'autre module | M (achat en masse, amis auto) / G |
| Fenêtre LFG Forever (liste de groupes, navigateur, /qui, infobulle de groupe) | Skin de « Looking For Group » Forever | oui | GroupFinderForever.lua:14 ; O:2198-2212 | absent (PVEFrame dans la liste de cadres, style générique) | M |
| Liste d'amis Forever (skin propre) | Skin de la fenêtre amis Forever | oui | FriendsForever.lua:37 ; O:2599-2616 | partiel : FriendsFrame style générique | M |
| Barre de sacs, Progression Legacy (skins Forever) | Skins propres à Forever | oui | BagBarForever.lua:15 ; LegacySystemForever.lua:16 | absent | G |
| Pause menu (menu du jeu) : activer, mêmes réglages | Menu Échap reskin | oui | O:214-228 ; Dialogs.lua | partiel : GameMenuFrame dans la liste (Skin.lua:302) | G |
| Popups et menus : reskin, style de bordure, style de bordure des boutons, fond de bouton, couleurs, échelle de police, lueur d'acceptation de résurrection | Popups statiques / menus déroulants | oui | O:140-215 | partiel : StaticPopup1-4, DropDownList1-3 habillés (Skin.lua:307), aucun réglage fin (bordure, couleurs, échelle de police, lueur de résurrection) | G |
| Cadre de raccourcis rapides (Quick Keybind), dialogue d'inscription premade, dialogue LFG | Skins de dialogues | oui (premade : retail non vérifié) | Dialogs.lua:1-30 | absent | G |
| Infobulle : style de bordure, fond (opacité) | Réglage d'apparence | oui | O:728, 633 | absent (apparence fixe : 0.05/0.06/0.08/0.94, Skin.lua:17) | G |
| Infobulle : mode d'affichage (toujours / hors combat / hors combat de boss / jamais) + modificateur d'aperçu | Cacher les infobulles selon le contexte | oui (hors combat de boss : encounter = retail, non vérifié) | O:287-330 ; TooltipVisibility.lua | partiel : cases « masquer unités en combat » / « masquer toutes en combat » (options.md 1430-1431) ; absent : hors combat de boss, « jamais », modificateur pour lire quand même | M |
| Infobulle collée au curseur : position (point), décalage X/Y, sens de croissance, mover | Ancrage d'infobulle | oui | O:332-410 ; TooltipAnchor.lua | équivalent (curseur, mover, croissance, décalages ; options.md 1432-1435) | - |
| Infobulle : extras à cocher (titres de joueur, niveau d'objet, score M+, monture, rang de guilde, cible, « Infobulles détaillées ») | Lignes ajoutées sur l'infobulle d'unité | oui (score M+ retail) | O:417-460 | partiel : cible, rang de guilde, ilvl joueur ; absent : titres de joueur, monture, mode « détaillé » | M |
| Infobulle : ID de sort / icône / objet avec modificateur | Identifiants dans l'infobulle | oui | O:423-520 | partiel : une case unique « ID des sorts, objets et auras » ; absent : modificateur, séparation icône/objet | G |
| Infobulle : taille de pile max des objets (avec modificateur) | Ligne « pile max » | oui | O:527-570 | absent | G |
| Infobulle : buffs du joueur survolé (position, taille d'icône, par ligne, décalages) | Rangée d'auras sous l'infobulle | oui (auras secrètes en combat : non vérifié) | O:537-620 | absent | M |
| Infobulle : bande de vie (texture, hauteur, couleur) | Barre de vie stylisée | oui | O:624-720 ; TooltipSkin.lua | partiel : seulement masquer/afficher la barre (options.md 1440) | G |
| Barres de widget d'UI (reskin, taille mini), bouton d'action supplémentaire (reskin), barres de progression d'infobulle | Reskin HUD | oui | O:749-770, 845 ; EUI_BlizzardSkin_HUD.lua:1-8 | absent | G |
| Popup de file (reskin) + minuteur de file (taille de texte, hauteur de barre, décalage) | Popup « prêt pour l'instance » avec compte à rebours | oui | O:779-935 | absent (LFGDungeonReadyDialog non touché) | M |
| Bulles de dialogue : canaux (dire, crier, groupe, PNJ, émotes), masquer en instance, marge, largeur max, police, bordure | Bulles au thème | oui | O:3486-3573 ; ChatBubbles.lua | partiel : canaux dire/crier/groupe/PNJ, police, bordure canal (options.md 735-748) ; absent : émotes, marge, largeur max, masquer en instance | G |
| Dragon Riding (HUD vol dynamique) | HUD de vol | retail (DragonRiding.lua:2 retourne si Forever) | O:3700 | absent | retail |
| Fenêtres déplaçables (Window Mover / Shifter) | Déplacer et zoomer les fenêtres, réinit. | oui | O:4045-4056 ; EUI_QoL_Shifter_Options.lua:106-146 | partiel : déplacement Maj/Ctrl + remise en place (options.md 1377-1384) ; absent : zoom/échelle des fenêtres, réinit. d'une fenêtre précise, déplacer sans Maj, fenêtres de butin/événements en mode déverrouillage | M |

Équivalents complets : ancrage des infobulles (curseur, mover, croissance, décalages), cible et rang de guilde dans l'infobulle, couleurs de classe, infobulles masquées en combat (version simple), icônes d'auras rognées (zoom), thème plat/sombre/Blizzard par fenêtre.

### 2. Compteur de dégâts (EllesmereUIDamageMeters)

Nous : aucun module. docs/comparatif-quaziiui.md:41, 362-364 : « laissé à ForeverMeter » (addon tiers, dépendance requise CurseForge, CHANGELOG.md:42). Aucun appel à `C_DamageMeter` dans notre code (grep).

#### Ce qui marche sur Forever (vérifié dans ~/wow-ui-source/forever, version 1.60.1.70291)
- `Blizzard_DamageMeter` : `AllowLoadGameType: standard, camelot` (Blizzard_DamageMeter.toc:2) ; dossier Camelot/ avec un seul override (`DamageMeterEntryOverrides.lua`, `ShouldShowClassification` -> false).
- Le EUI DamageMeters est chargé sur Forever : TOC Interface 16001 (EllesmereUIDamageMeters.toc:1), code gaté `IS_FOREVER` pour le style (Style.lua:57, 105) et la fenêtre « Menace » (ForeverThreat.lua:2).
- API `C_DamageMeter` (Blizzard_APIDocumentationGenerated/DamageMeterDocumentation.lua, `Environment = "All"`) : `GetAvailableCombatSessions`, `GetCombatSessionFromID`, `GetCombatSessionFromType`, `GetCombatSessionSourceFromID`, `GetCombatSessionSourceFromType`, `GetSessionDurationSeconds`, `IsDamageMeterAvailable`, `ResetAllCombatSessions` ; événements `DAMAGE_METER_COMBAT_SESSION_UPDATED`, `DAMAGE_METER_CURRENT_SESSION_UPDATED`, `DAMAGE_METER_RESET`. Toutes les fonctions de données sont `SecretWhenInCombat` avec `SecretArguments = "AllowedWhenUntainted"` (lignes 23, 41, 59, 79) ; `GetAvailableCombatSessions` et `ResetAllCombatSessions` non.
- Enum `DamageMeterType` complet, 11 valeurs (DamageMeterConstantsDocumentation.lua:104-112) : DamageDone, Dps, HealingDone, Hps, Absorbs, Interrupts, Dispels, DamageTaken, AvoidableDamageTaken, Deaths, EnemyDamageTaken. EUI en utilise 8 (EllesmereUIDamageMeters.lua:31-39 : sans Dps, Hps, Absorbs). `DamageMeterSessionType` : Overall, Current, Expired. `DamageMeterCombineSessionType` : None, ChallengeMode, Arena, ArenaMultiRound.
- Champs : `combatSources[]` avec `classFilename`, `specIconID`, `isLocalPlayer`, `deathRecapID`, `classification` (NeverSecret), `sourceGUID` et `name` (ConditionalSecret), `totalAmount`, `amountPerSecond` ; sort par source : `spellID`, `overkillAmount`, `isAvoidable`, `isDeadly`, `combatSpellDetails` (cible par sort).
- CVar `damageMeterEnabled` : présent (Blizzard_DamageMeter/DamageMeter.lua:1, 171 ; réglage AdvancedOptions.lua). EUI le force à 0 pour cacher le compteur Blizzard (Lifecycle.lua:456).
- Éléments EUI marqués retail seulement : `noForever` = « Hide in Delves », « Auto Swap Current/Overall », « Default on M+ Start » (Window.lua:780, 819, 834) ; gouffres et clés absents de Forever d'après le commentaire Window.lua:843.
- Non vérifié : la disponibilité effective de `IsDamageMeterAvailable()` en jeu sur Forever (raison d'échec) ; je n'ai pas lancé le client.

#### Écarts

| Fonction | Ce qu'elle fait (1 ligne) | Forever ? | Preuve EUI | Chez nous | Valeur |
|---|---|---|---|---|---|
| Fenêtres de compteur (jusqu'à 5), mode par fenêtre : Dégâts, Soins, Dégâts subis, Dégâts évitables, Dégâts subis par l'ennemi, Interruptions, Dissipations, Morts | Affichage des barres triées par joueur via `C_DamageMeter` | oui | EllesmereUIDamageMeters.lua:31-39, MAX_WINDOWS:28 | absent (ForeverMeter externe) | H |
| Segments : Actuel / Global / liste des combats passés, synchronisation de la sélection, « Actuel en combat », réinit. des données (+ raccourci) | Navigation entre combats | oui | Window.lua:859-870, 824-834 ; State.lua:418, 529 | absent | H |
| Détail d'un joueur (breakdown par sort, plus de sorts, survol), infobulle de sorts, détail des morts (récap), dégâts subis par l'ennemi | Panneau de décomposition | oui (champs secrets en combat : données lisibles seulement hors combat) | Tooltip.lua:183-390 ; Format.lua:331-617 | absent | H |
| Barre du joueur toujours visible, marqueur du joueur, texture/hauteur/couleur/opacité/espacement des barres, icône (classe/spé, zoom, séparateurs, bordure), rang masquable, textes gauche/droite (taille, décalage, contour), format de nombres, unités anglaises forcées | Apparence des barres | oui | O:332-380, 657-1000, 1162-1420 | absent | M |
| En-tête (hauteur, opacité, icônes de survol, titre, séparateur), cadre (bordure, fond, opacité, largeur/hauteur), style « Forever » / « Classic WoW UI » | Habillage de la fenêtre | oui (style Forever : Style.lua:57, 105) | O:186-330, 397-640 ; Style.lua | absent | G |
| Visibilité : masquer en donjon / raid / PvP / hors instance, touche afficher/masquer | Règles d'affichage | oui (« gouffre » : retail) | Window.lua:772-788 ; O:1618-1640 | absent | M |
| Minuteur de combat autonome (police, taille, alignement, décimales, couleurs, ancrage aux fenêtres, grisé hors combat, déplacement, verrouillage) | Chronomètre indépendant | oui (durée : `GetSessionDurationSeconds`, State.lua:431) | Timer.lua ; O:1437-1610 | partiel : « Chronomètre de combat » dans Alertes (options.md, section Alertes), sans réglages de style ni ancrage | M |
| Fréquence de rafraîchissement (+ option « non sûre ») | Cadence de mise à jour | oui | O:137-185 ; Format/State | absent | G |
| Historique des sorts lancés : bandeau d'icônes (direction, taille, nombre, animation, visibilité par instance) et fenêtre à barres (échoués/interrompus en rouge) | Suivi de vos derniers sorts | oui (pierre de soin Forever : SpellHistory.lua:244-250) | SpellHistory.lua ; O:1694-1999 | absent | M |
| Fenêtre « Menace » (liste de menace dans une fenêtre du compteur) | Type de mode propre à Forever, alimenté par Forever Essentials (`_ThreatFeed`) | oui (Forever seulement) | ForeverThreat.lua:2-40 | absent (voir « Autre tank » pour la barre de l'autre tank, hors zone) | M |
| Cacher le compteur Blizzard (`damageMeterEnabled` à 0) | Évite le doublon | oui | Lifecycle.lua:456 | absent (le compteur Blizzard n'est pas touché) | M |
| Types Dps / Hps / Absorbs de `C_DamageMeter` | Modes supplémentaires disponibles dans l'API | oui (enum Forever) | non utilisés par EUI (EllesmereUIDamageMeters.lua:31-39) | absent | M |
| Auto-bascule Actuel/Global, mode par défaut au début d'une clé, masquer en gouffre | Réglages M+/gouffre | retail | Window.lua:780, 819, 834 | absent | retail |

Équivalents complets : aucun.

### 3. Timer M+, barres d'incantation ciblées, suivi d'interruptions (EllesmereUIMythicTimer + options MythicTimer / KickTracker)

Fait structurant : `EllesmereUIMythicTimer.toc:2` déclare `## AllowLoadGameType: standard` ; tout l'addon (timer, barres de sorts ciblés, barres cible/focus, Kick Tracker, Run Summary) n'est donc PAS chargé sur Forever (type de jeu camelot). Aucun `IS_FOREVER` dans ses fichiers ni dans ses deux fichiers d'options (grep). `Blizzard_ChallengesUI.toc:5` charge seulement `standard, mists` : pas de défis/clés côté Blizzard sur Forever. `LibKeystone` et `LibSpecialization` sont aussi `[AllowLoadGameType standard]` (EllesmereUI.toc:20-21). Le commentaire Window.lua:843 (DamageMeters) dit « WoW Forever has no delves and no keystones ».
Chez nous : rien (grep mythic/keystone : seulement MuscaUI_Minimap/MinimapFrame.lua ; hors zone). Équivalent partiel pour les barres d'incantation : cadres d'unité (UnitFrameElements.lua:1048-1102, options.md 804-810, 847-963 : couleur « interruption prête », importante, barre détachée avec mover).

| Fonction | Ce qu'elle fait (1 ligne) | Forever ? | Preuve EUI | Chez nous | Valeur |
|---|---|---|---|---|---|
| Timer M+ : cadre (échelle, largeur, fond, bordure), titre / donjon / niveau de clé / affixes, timer (taille, format, police, dans la barre), barre de timer +2/+3 (ticks, textures), forces ennemies (barre, % / compte, tirage en cours), boss et temps d'objectifs, comparaison de splits, mort | Chronomètre de clé complet | retail | EllesmereUIMythicTimer.lua:1-30, 3545 l. ; toc:2 | absent | retail |
| Historique de runs + Run Summary (/ov) : récap fin de clé par membre (spé, ilvl, score, butin, DPS, dégâts subis, interruptions, morts), historique par personnage | Résumé de clé via `C_ChallengeMode` + `C_DamageMeter` | retail | RunSummary.lua:1-12, 916-956 | absent | retail |
| « Where to Show » (seau de contenu : donjon, raid, gouffre, PvP, monde ; état de combat) commun aux outils M+ | Filtre d'affichage partagé | oui côté logique (`ns.MTWhere`), mais addon non chargé | Where.lua:1-10 | absent | M (si on porte les barres ci-dessous) |
| Barres de sorts ciblés : un groupe mobile de barres d'incantation, une par ennemi qui lance (nom, cible du sort, minuteur, teinte interruption prête, voile non-interruptible, importance, fondu hors portée d'interruption, marqueur de raid) | Vue d'ensemble des incantations ennemies | retail (addon non chargé) ; primitives présentes dans la doc Forever : `UnitCastingDuration`, `UnitChannelDuration`, `SetTimerDuration`, `SetAlphaFromBoolean`, `C_CurveUtil` (UnitDocumentation, SimpleStatusBarAPIDocumentation, CurveUtilDocumentation) ; test en jeu non vérifié | TargetedSpellBars.lua:1-14 ; O (MythicTimer_Options) « Cast Bars » | absent (les barres d'incantation existent seulement par unité : cible, focus, plaques) | M |
| Barres cible / focus autonomes (placées librement) : teinte interruption prête, bouclier non-interruptible, couleur sort important, repère « interruption prête en cours d'incantation » (tick + fenêtre), flash « interrompu » | Barres de cast détachées | idem (addon non chargé ; API Forever présentes) | TargetFocusBars.lua:1-12 ; O « Kick Ready Mid-Cast Hint », « Interrupted Flash » | partiel : barre détachée avec mover, teinte interruption prête, teinte importante (options.md 804-810, 849) ; absent : repère mi-incantation, flash « interrompu » | M |
| Kick Tracker, icônes sur plaques : icône sur la plaque d'un ennemi interrompu montrant qui a interrompu (icône de spé / sort / classe), swipe + décompte de recharge de l'interruption, « fantômes » quand le kicker est inconnu | Qui a interrompu quoi | retail (addon non chargé). Moteur : `C_DamageMeter` type Interrupts (présent sur Forever, DamageMeterConstantsDocumentation.lua:104-112) ; GUID de l'interrupteur et montants secrets en contenu restreint (KickEngine.lua:30-55) ; lecture des talents par `C_Traits` d'inspection hors clé (KickEngine.lua:399-417) non vérifiée sur Forever | KickPlates.lua:1-20 ; KickEngine.lua:1-60 ; O:KickTracker_Options | absent | M |
| Kick Tracker, barres : une rangée par membre avec interruption (icône, nom classe-colorée, recharge qui se vide), « Include Yourself », taille, texture, bordure, annonce de focus | Tableau des recharges d'interruption du groupe | idem | KickBars.lua:1-20 ; O:KickTracker_Options | absent | M |
| Annonce « focus » du Kick Tracker (texte éditable) | Message en groupe | idem, non vérifié (envoi chat) | O:KickTracker_Options (« Focus Announce », « Edit Announce Text ») | absent | G |
| Données d'interruption par classe/spé/talent (`EllesmereUI.KickData`) | Table de recharges | oui comme donnée ; non vérifié pour les talents Forever | KickEngine.lua:30-60 | absent | M |

Équivalents complets : aucun.

### 4. Menu radial (EllesmereUIQuickdraw + EUI_Quickdraw_Options)

Nous : Modules/RadialMenu.lua (377 l.), options.md « Menu radial » (1530-1590) : 4 palettes fixes (touche + liste texte d'entrées chacune), disposition Anneau / Éventail / Grille, rayon, taille d'icône, couleur de sélection, nom de l'entrée survolée, entrées spell/item/macro/mount/marker/menu (16 max), sous-menus par survol (`menu:N`, 0,3 s), bouton « Ajouter ce qui est sur le curseur ». Hors combat seulement (RadialMenu.lua:6-7).
EUI : TOC Interface 16001, aucun `AllowLoadGameType` : chargé sur Forever ; seul gating Forever = vault (sans contenu) et grimoire/talents séparés (Slots.lua:391-410), spécialisations = toute spé de la classe (Quickdraw.lua:821-853), `ForeverClassSpecIDs` (O:3058, 3082).

| Fonction | Ce qu'elle fait (1 ligne) | Forever ? | Preuve EUI | Chez nous | Valeur |
|---|---|---|---|---|---|
| Fonctionnement en combat (clic secure routé par `SetOverrideBindingClick` + `SecureHandlerWrapScript`, extraits de sélection par angle) | Menu utilisable en combat | ? : EUI n'a aucune branche Forever pour les extraits sécurisés (Secure.lua:141, Gates.lua:572-698, Runtime.lua:263) ; notre constat « les extraits sécurisés ne compilent pas sur ce client » (RadialMenu.lua:6) contredit cela : non vérifié en jeu | Secure.lua ; Gates.lua ; EllesmereUIQuickdraw.lua:1-35 | absent (hors combat seulement) | H |
| Nombre de menus illimité (« Add Action Menu », renommer, supprimer), un menu édité à la fois, « Apply All Settings » | Autant de menus que voulu | oui | O (« Add Action Menu », « Editing Action Menu », « Rename/Delete Action Menu », « Apply All Settings ») | partiel : 4 palettes fixes (RadialMenu.lua:PALETTE_COUNT) ; apparence commune à toutes | M |
| Mode « touche basculée » (« Toggle Menu Open », « Toggled Menu Select Action ») + « Menu Cancel Action » (touche d'annulation) | Ouvrir sans maintenir, choisir par une touche | oui | O:3287-3365 | absent (maintenir/relâcher seulement ; Échap non vérifié) | M |
| Détection de touche déjà utilisée (« Key Already Bound ») | Avertit d'un conflit de raccourci | oui | O (« Key Already Bound ») ; O:3365 | absent | M |
| Assignation d'un menu à une spé/classe (« Assign to Spec ») + touche partagée entre menus exclusifs | Menu différent par spé, même touche | oui (toute spé de la classe sur Forever, pas de changement de spé à chaud : non vérifié) | Quickdraw.lua:810-870 | absent | M |
| Dispositions : arc (étendue en degrés, rotation), éventail (direction, icônes visibles), grille (colonnes auto/fixes, espacement) ; « Distance from Center » | Géométrie réglable | oui | O (« Arc Span », « Arc Rotation », « Fan Direction », « Visible Icons », « Grid Columns », « Auto Columns », « Spacing ») ; Geometry.lua | partiel : arc / éventail / grille, rayon, taille ; absent : étendue et rotation de l'arc, colonnes de la grille, espacement, nombre d'icônes visibles | M |
| Pilotage à la molette (« Select Action with Mouse », « Invert Scroll ») en plus de l'angle du curseur | Choisir en faisant défiler | oui | O:3581-3590 ; Live.lua:153 (`OnMouseWheel` sécurisé) | absent | G |
| Ouvrir au curseur ou à une position fixe (X/Y), échelle | Placement du menu | oui | O (« Open At », « Fixed Position », « X/Y Offset », « Scale ») | absent (toujours au curseur) | M |
| Sous-menus imbriqués : forme (arc / grille), distance, taille d'icône, étendue max | Menus dans le menu | oui | O (« Nest Another Action Menu », « Nest Distance », « Nest Icon Size », « Arc Nest Shape », « Nest Width », « Max Nest Span », « Grid Nest Style ») ; Nests.lua | partiel : sous-menu par survol de 0,3 s, un niveau fixe par palette ; absent : réglages de forme/distance | M |
| Affichage des entrées : recharges, grisé des actions inutilisables, masquer les actions indisponibles, étiquette de texte | Retour visuel sur chaque entrée | oui | O (« Show Cooldowns », « Dim Unusable Actions », « Hide Unavailable Actions », « Show Action Text Label ») ; Actions.lua | partiel : nom de l'entrée survolée seulement (options.md 1540) ; absent : recharges, grisé, masquage | M |
| Sélecteur d'actions par catégorie : Sorts, Montures, Objets, Jouets, Macros, Mascottes, Tenues (transmo), Marqueurs de cible, Marqueurs de terrain, Spécialisations, Métiers, Panneaux d'interface (micro-menu), Pings, Pierres de foyer, Téléportations, Potions, Formes de druide, Postures, Objets de quête, « Custom Macro… » | Ajout d'une action sans saisir d'ID | oui (APIs en doc Forever : `C_ToyBoxInfo`, `C_PetJournal`, `C_TransmogOutfitInfo`, Ping* ; Vault sans contenu : Slots.lua:391 ; pings, outfits : disponibilité en jeu non vérifiée) | O (liste « Add an action ») ; Slots.lua ; Actions.lua | partiel : entrées texte spell/item/macro/mount/marker + bouton « curseur » ; absent : jouets, mascottes, tenues, spécialisations, métiers, panneaux d'interface, pings, groupes pierre de foyer / téléportations / potions / formes / postures / objets de quête, sélecteur visuel | M |
| Marqueurs de terrain : « Toggle World Markers », liste d'entrées, repères des marqueurs posés | Poser / retirer les marqueurs au sol | oui (non vérifié sur Forever) | O (« World Marker Entries », « Show Placed-Marker Pips ») | partiel : `marker:0-8` (options.md 1545) ; absent : bascule poser/retirer, pastilles de marqueurs posés | G |
| Rez dynamique (une entrée = le sort de résurrection de la classe) | Palette partagée entre classes | oui | Actions.lua:30-46 | absent | G |

Équivalents complets : sélection par angle depuis le curseur, maintenir/relâcher, sorts / objets / macros / montures / marqueurs, couleur de sélection, taille d'icône, plusieurs palettes avec touche propre, sous-menu par survol.

### Alertes (Modules/Alerts.lua)

La zone m'a assigné Alerts.lua comme équivalent. Côté EUI, la fonction voisine est QoL « Alerts » (EUI_QoL_Alerts_Options.lua), qui appartient à une autre zone : non inventoriée ici. Nous : entrée/sortie de combat, mort d'un membre, chronomètre de combat (options.md 298-326). Aucun écart relevé dans ma zone.

### Limites client révélées

- `C_DamageMeter` : toutes les fonctions de lecture de session sont `SecretWhenInCombat` + `SecretArguments = "AllowedWhenUntainted"` (DamageMeterDocumentation.lua:23, 41, 59, 79) ; `name` et `sourceGUID` d'une source sont `ConditionalSecret`, `classFilename`, `specIconID`, `isLocalPlayer`, `deathRecapID`, `classification` sont `NeverSecret` (:199-208). Un compteur natif Forever ne lit donc les montants et noms qu'hors combat (EUI contourne en passant des valeurs secrètes à des widgets natifs : Lifecycle.lua:226, KickEngine.lua:50-55).
- `GetAvailableCombatSessions` et `ResetAllCombatSessions` ne sont pas secrètes (DamageMeterDocumentation.lua:11-17, 124).
- `DamageMeterType` Forever = 11 types dont Dps, Hps, Absorbs, que EUI n'exploite pas (DamageMeterConstantsDocumentation.lua:104-112).
- `Blizzard_DamageMeter` : `AllowLoadGameType standard, camelot` (toc:2), avec un override Camelot minime (Camelot/DamageMeterEntryOverrides.lua) ; CVar `damageMeterEnabled` présente (DamageMeter.lua:1, 171).
- `EllesmereUIMythicTimer.toc:2` `AllowLoadGameType: standard` ; `Blizzard_ChallengesUI.toc:5` `standard, mists` : pas de M+/défis sur Forever, donc timer, RunSummary et Kick Tracker EUI non chargés.
- `LibKeystone`, `LibSpecialization` : `[AllowLoadGameType standard]` (EllesmereUI.toc:20-21) : absents de Forever.
- Écran de jeu Forever interface Gamepad : EUI désactive ses skins de fenêtres Blizzard pour la session car un hook de script sur ces cadres taint un chemin sécurisé (ADDON_ACTION_FORBIDDEN, gel possible) : EllesmereUIBlizzardSkin.lua:118-131 (`BlizzSkinPadStandDown`). Concerne notre Skin.lua (hooks sur fenêtres) : non vérifié chez nous.
- Skins retail sans objet sur Forever : Grand Coffre, sélecteur de gouffre, Housing (retirés O:2662-2670), Dragon Riding (DragonRiding.lua:2), liste d'alts du courrier (MailAlts.lua:2), panneau de sertissage (SocketPanel.lua:1469), stats en lettres dans le flyout (O:1324, 1346).
- Fenêtre « Sort cooldown / Spellbook » Forever : grimoire et talents sont deux boutons micro-menu distincts, le bouton combiné s'ouvre sur le dernier onglet (Quickdraw Slots.lua:397-405).

### Non couvert

- Contenu interne de EllesmereUIBlizzardSkin_WindowPacks.lua (14 018 lignes), CharacterSheet.lua (5 118), SocketPanel, InspectSheet, GroupFinder : je me suis fié aux cartes d'options et aux commentaires d'en-tête, pas aux détails de chaque pack ; l'étendue réelle de chaque skin sur Forever (catalyseur, commandes d'artisanat, compagnon, choix de joueur…) n'est pas vérifiée.
- Fenêtre `Window Mover / Shifter` : n'ai lu que les libellés (QoL, autre zone).
- Fichiers MythicTimer (Kick* ~7 400 lignes) : lus en-têtes et extraits grep seulement.
- Comportement en jeu (client Forever lancé) : rien exécuté ; les mentions « non vérifié » restent à tester en jeu (secrets en combat, `IsDamageMeterAvailable`, extraits sécurisés, pings, tenues).
- EUI_QoL_Alerts_Options.lua et EllesmereUIDamageMeters Appearance/Apply : non lus en détail.

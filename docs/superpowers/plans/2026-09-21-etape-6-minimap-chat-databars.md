# ForeverUI étape 6 — minimap, chat, barres de données, suivi de quêtes, panneaux sombres

> Cadrage : section 4 point 6. Socle : movers, `NS.HideBlizzardFrame`, `Media` (bordures, barres, polices), `NS.CVars`. Codé sans validation en jeu (« enchaîne les phases, on testera plus tard »). Version 1.8.0.

**Goal :** couvrir le reste de l'écran avec des cadres ForeverUI réglables, sans toucher aux systèmes Edit Mode plus que nécessaire.

## Modules

### `minimap` (`Modules/MinimapFrame.lua`)
- Support `ForeverUI_Minimap` (mover `minimap`, défaut TOPRIGHT -20 -50) ; `Minimap` réancrée dessus (jamais reparentée : `MinimapCluster` est géré par Edit Mode), hook `SetPoint` avec garde pour reprendre la main si Blizzard réancre.
- Carrée : `SetMaskTexture("Interface\\BUTTONS\\WHITE8X8")`, bordure et fond au thème. Taille réglable.
- Décor Blizzard caché (bordure haute, boussole, horloge, zoom, compartiment d'addons, bouton d'extension) ; boutons utiles (suivi, calendrier, difficulté, courrier, file d'attente) réancrés aux coins.
- Nom de zone ForeverUI au-dessus (couleur PvP), coordonnées optionnelles au-dessous (`C_Map`, pcall, 0,5 s).
- Molette = zoom. Boutons d'addons (LibDBIcon et autres boutons enfants de la minimap) regroupés dans une rangée sous la carte : toujours, au survol, ou jamais.
- Cède à ElvUI et SexyMap.

### `chat` (`Modules/Chat.lua`)
- Habillage des `ChatFrame1..NUM_CHAT_WINDOWS` : textures Blizzard cachées, fond au thème (`Media:CreateBackdrop`), police du thème + taille, onglets plats, boutons latéraux cachés, fondu coupé, `SetMaxLines`.
- URL cliquables (filtre `ChatFrame_AddMessageEventFilter` + lien `|Hurl:…|h`, `hooksecurefunc("SetItemRef")` ouvre une boîte de copie), copie du chat (bouton au survol, fenêtre à `EditBox`), noms de canaux courts (`[2. Commerce]` → `[2]`), couleur de classe sur tous les canaux (`SetChatColorNameByClass`), horodatage (CVar `showTimestamps`), zone de saisie en haut ou en bas avec fond au thème.
- Pas de mover ni de taille : `ChatFrame1` est un système Edit Mode. Cède à ElvUI, Prat-3.0, Chatter.

### `databars` (`Modules/DataBars.lua`)
- Barre d'expérience (`UnitXP`, `UnitXPMax`, `GetXPExhaustion`, cachée au niveau max) et barre de réputation (`GetWatchedFactionInfo` ou `C_Reputation.GetWatchedFactionData`), `Media:CreateStatusBar`, texte réglable, infobulle, movers `databar_xp` (BOTTOM 0 6) et `databar_rep` (BOTTOM 0 18). Largeur, hauteur, texte par barre.
- Cadres Blizzard cachés sans reparentage : `MainStatusTrackingBarContainer`, `SecondaryStatusTrackingBarContainer`, `StatusTrackingBarManager`, `MainMenuExpBar`, `ReputationWatchBar`.

### `questtracker` (`Modules/QuestTracker.lua`)
- `ObjectiveTrackerFrame` (ou `WatchFrame`) posé sur un support ForeverUI (mover `questtracker`, défaut TOPRIGHT -40 -260), hook `SetPoint` gardé ; hauteur réglable ; fond des en-têtes caché et polices au thème ; repli automatique en combat et/ou en instance (`SetCollapsed`, repli `ObjectiveTracker_Collapse/Expand`), rétabli à la sortie.

### `skin` (existant) : panneaux sombres
- Option `darkPanels` : `NineSlice`, `Bg`, `TitleBg` des panneaux Blizzard (liste `DARK_PANELS`, plus `Blizzard_*` chargés à la demande sur `ADDON_LOADED`) teintés `SetVertexColor(0.25, 0.25, 0.25)` ; rendu à 1,1,1 au disable.

## Locale, toc, README, tests
- Clés `MINIMAP_*`, `CHAT_*`, `DATABARS_*`, `QT_*`, `OPT_SKIN_DARK_PANELS`, movers.
- `ForeverUI.toc` 1.8.0 : `Modules\MinimapFrame.lua`, `Modules\Chat.lua`, `Modules\DataBars.lua`, `Modules\QuestTracker.lua` après `Modules\ActionBars.lua`.
- Mock : `Minimap`, zone/PvP, `C_Map`, `ChatFrame1..3`, `ChatFrame_AddMessageEventFilter`, `SetItemRef`, `ChatTypeInfo`, `SetChatColorNameByClass`, `UnitXP`, `GetXPExhaustion`, `GetWatchedFactionInfo`, `ObjectiveTrackerFrame`, cadres de suivi Blizzard, `CharacterFrame` avec `NineSlice`.
- Tests : `tests/test_minimap.lua`, `tests/test_chat.lua`, `tests/test_databars.lua`, `tests/test_questtracker.lua`, `test_skin` (panneaux sombres).

## Risques en jeu
- Edit Mode réancre `Minimap` ou `ObjectiveTrackerFrame` (hook gardé ; sinon `/reload`).
- Noms des sous-cadres de la minimap sur Forever (tout est optionnel, résolu par chemin `_G`).
- `GetNumMessages`/`GetMessageInfo` pour la copie du chat (repli : bouton absent si l'API manque).
- `ObjectiveTrackerFrame:SetCollapsed` selon la version du moteur (repli sur les fonctions globales, sinon rien).

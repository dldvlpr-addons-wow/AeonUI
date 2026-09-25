# ForeverUI étape 2 — unit frames propres

> Cadrage : `docs/superpowers/specs/2026-09-20-positionnement-et-prerequis-plan.md`, section 4 point 2. Socle : étape 1 livrée (1.3.0, 124 tests). Pas de commit sans demande explicite. Chaque tâche : test headless d'abord (`tests/run.sh`), mock enrichi pour chaque API touchée, puis vérification manuelle en jeu par le user.

**Goal :** remplacer les cadres Blizzard du joueur, de la cible, de la cible de la cible, du focus et du familier par des cadres ForeverUI : santé, puissance, barre d'incantation, auras, nom, niveau, indicateurs (combat, repos, chef, marqueur de raid), points de combo, couleurs de classe et de réaction, positionnés par les movers de l'étape 1, thème de l'étape 1. Livrable seul : version 1.4.0, module « Cadres d'unité ForeverUI » désactivé par défaut jusqu'à l'installation un clic v2 (étape 7).

**Architecture :** un module `unitframes` (`Modules/UnitFrames.lua`) et un fichier d'éléments (`Modules/UnitFrameElements.lua`, chargé avant). Chaque cadre est un `Button` sur `SecureUnitButtonTemplate` (clic gauche cible, clic droit menu, `RegisterUnitWatch`), enfant d'`UIParent`, créé et dimensionné hors combat. Les éléments (barres, textes, icônes) sont des régions non protégées : mises à jour libres en combat. Règle Midnight : **aucune valeur d'unité n'est comparée ni calculée en Lua** ; santé, puissance, durées et auras vont directement aux widgets (`SetMinMaxValues`, `SetValue`, `SetTimerDuration`, `AbbreviateNumbers`, conteneur d'auras du moteur), qui acceptent les valeurs secrètes. Quand une comparaison est inévitable (classe, réaction, niveau, combat, chef), `NS.IsSecret` d'abord, repli neutre sinon.

Le module existant `frames` (retouches Blizzard) reste tel quel : ses hooks sur `PlayerFrame`, `TargetFrame`, `FocusFrame` tournent sur des cadres masqués, sans effet ; ses noms de raid à la couleur de classe restent utiles jusqu'à l'étape 4. Une note dans ses options l'indique quand `unitframes` est actif.

**Hors périmètre de l'étape :** party et raid (étape 4), cadres de boss et d'arène, portraits, prédiction de soins et absorptions (contenu Classic, peu utile), barres d'auras, barre de puissance alternative, ancrage d'un cadre sur un autre (les movers gardent des positions absolues), profils par rôle. Notés pour plus tard si le terrain le demande.

## 0. Sondes préalables (`/fui diag`)

Trois API du moteur 12.x sont supposées présentes sur Forever parce qu'EllesmereUI les appelle ; leur présence se vérifie **avant** d'écrire les éléments, par une ligne « Unit frames » de `/fui diag` :

- `StatusBar:SetTimerDuration` et `UnitCastingDuration`, `UnitChannelDuration` : barre d'incantation sans lecture d'horloge en Lua.
- `AbbreviateNumbers`, `UnitHealthPercent`, `UnitPowerPercent` : textes de santé et de puissance à valeur secrète.
- `Blizzard_AuraContainer` (`C_AddOns.LoadAddOn`) et `CustomAuraContainerTemplate` : affichage d'auras par le moteur.

Chaque absence a son repli, décrit dans la tâche concernée. Le user colle la ligne du diag ; le plan se fige ensuite.

## Fichiers

| Fichier | Responsabilité |
|---|---|
| `Modules/UnitFrameElements.lua` (nouveau) | `NS.UnitFrameElements` : constructeurs et mises à jour d'un élément chacun : `Health`, `Power`, `CastBar`, `Name`, `Level`, `Indicators`, `RaidIcon`, `ComboPoints`, `Auras`. Fonctions pures testables : `HealthColor(unit)`, `PowerColor(unit)`, `LevelText(unit)` |
| `Modules/UnitFrames.lua` (nouveau) | module `unitframes` : masquage des cadres Blizzard, création des cinq boutons sécurisés, dispatch des événements, movers, options |
| `Core/Media.lua` | `Media:CreateStatusBar(parent)` : `StatusBar` avec `StatusBarTexture()`, fond et bordure du thème, enregistrée pour `RefreshBackdrops` et rafraîchie sur changement de texture |
| `Core/Compat.lua` | sonde « Unit frames » du diag ; `NS.HideBlizzardFrame(frame)` et `NS.ShowBlizzardFrame(frame)` (réutilisés à l'étape 4) |
| `Core/Database.lua` | défauts `unitframes` (voir tâche 2) ; `theme.statusbar` prend une option |
| `Config/Options.lua` | page du module ; option thème « Texture des barres » (cycle sur LibSharedMedia, masquée sans LSM) |
| `Config/FirstRun.lua` | rien : le module reste décoché par défaut, la case existe déjà via la liste des modules |
| `Modules/Frames.lua` | note dans `BuildOptions` quand `unitframes` est actif |
| `Locale/enUS.lua`, `Locale/frFR.lua` | clés `UNITFRAMES_*`, `OPT_UF_*`, `MOVER_UF_*`, `OPT_STATUSBAR` |
| `ForeverUI.toc` | `Modules\UnitFrameElements.lua` puis `Modules\UnitFrames.lua` après `Modules\Frames.lua` ; version 1.4.0 |
| `tests/wow_mock.lua` | `SecureUnitButtonTemplate` (attributs `unit`, `*type1`, `*type2`, erreur en combat), `RegisterUnitWatch`/`UnregisterUnitWatch`, `StatusBar` (`SetMinMaxValues`, `SetValue`, `GetValue`, `SetStatusBarColor`, `SetStatusBarTexture`, `SetTimerDuration`), `UnitPower`, `UnitPowerMax`, `UnitPowerType`, `UnitReaction`, `UnitLevel`, `UnitIsGroupLeader`, `UnitCastingInfo`, `UnitChannelInfo`, `UnitCastingDuration`, `UnitChannelDuration`, `GetRaidTargetIndex`, `SetRaidTargetIconTexture`, `AbbreviateNumbers`, `UnitHealthPercent`, `C_AddOns.LoadAddOn`, `CreateFrame("AuraContainer", …, "CustomAuraContainerTemplate")` avec `SetUnit`, `AddAuraGroup`, `AddAuraSlot`, `UpdateAllAuras` ; `Mock.units[unit]` étendu (`power`, `powerMax`, `powerType`, `reaction`, `level`, `leader`, `casting`) ; `Mock.SetSecret(value)` |
| `tests/test_unitframes.lua` (nouveau) | vérifications de l'étape |

## Tâches

### 1. Masquage des cadres Blizzard (`Core/Compat.lua`)

`NS.HideBlizzardFrame(frame)` : `UnregisterAllEvents`, `Hide`, `SetParent` sur un cadre caché `ForeverUI_Hidden` (enfant d'`UIParent`, `Hide()` une fois), puis `UnregisterAllEvents` sur les enfants connus (`healthbar`, `HealthBarsContainer.HealthBar`, `manabar`, `castBar`/`spellbar`, `BuffFrame`, `DebuffFrame`, `PetFrame`, `totFrame`, `CcRemoverFrame`) quand ils existent. `hooksecurefunc(frame, "SetParent")` : si Blizzard reparente (Edit Mode), on remet le parent caché au tick suivant hors combat. En combat sur un cadre protégé : différé par `NS:RunOutOfCombat`. `NS.ShowBlizzardFrame(frame)` rend le parent d'origine et `Show()` ; les événements Blizzard ne reviennent qu'au `/reload` : le disable du module l'annonce dans le chat (`MSG_UF_DISABLED_RELOAD`).

Cadres masqués par le module : `PlayerFrame`, `TargetFrame`, `TargetFrameToT`, `FocusFrame`, `FocusFrameToT`, `PetFrame`, `ComboFrame` (les points de combo Blizzard vivent sous `TargetFrame`), et la barre d'incantation joueur `PlayerCastingBarFrame` seulement si l'option « barre d'incantation » du joueur est cochée.

Tests : `HideBlizzardFrame` sur le mock `PlayerFrame` le cache et le reparente ; en combat sur un cadre protégé, reparenté seulement à la sortie du combat ; `ShowBlizzardFrame` rend le parent.

### 2. Module, base, movers (`Modules/UnitFrames.lua`)

```lua
NS.Modules:Register("unitframes", {
    titleKey = "UNITFRAMES_TITLE", descKey = "UNITFRAMES_DESC",
    yieldsTo = { "ElvUI" }, secure = true,
    defaults = {
        enabled = false,
        width = 220, height = 42, powerHeight = 6, castbarHeight = 18,
        healthText = "current",      -- "current" | "percent" | "both" | "none" ; "percent" seulement si UnitHealthPercent
        classColor = true,
        units = {
            player       = { enabled = true, castbar = true, auras = false, power = true },
            target       = { enabled = true, castbar = true, auras = true,  power = true },
            targettarget = { enabled = true, castbar = false, auras = false, power = false },
            focus        = { enabled = true, castbar = true, auras = true,  power = true },
            pet          = { enabled = true, castbar = false, auras = false, power = true },
        },
    },
})
```

`targettarget` et `pet` prennent la moitié de `width` et `height` sans barre d'incantation. Une seule taille commune : le user ajuste cinq cadres avec trois curseurs. Tailles par unité : plus tard, si demandé.

Création hors combat (`RunOutOfCombat`) au `OnEnable` : pour chaque unité activée, `CreateFrame("Button", "ForeverUI_UF_" .. unit, UIParent, "SecureUnitButtonTemplate")`, attributs `unit`, `*type1 = "target"`, `*type2 = "togglemenu"`, `RegisterForClicks("AnyUp")`, `RegisterUnitWatch(frame)`. `Media:CreateBackdrop(frame)`. Boutons créés une fois et réutilisés (`UnitFrames.frames[unit]`) : le disable fait `UnregisterUnitWatch` + `Hide` hors combat, jamais de destruction.

Movers : clés `uf_player`, `uf_target`, `uf_targettarget`, `uf_focus`, `uf_pet`, libellés `MOVER_UF_*`, défauts `CENTER -300 -200`, `CENTER 300 -200`, `CENTER 300 -260`, `CENTER 0 -320`, `CENTER -300 -260`. Le calque d'un cadre absent (pas de cible) reste visible au déverrouillage : `UnitWatch` cache le cadre réel, pas le calque, qui garde la taille enregistrée.

Événements : un seul frame écouteur ; `PLAYER_TARGET_CHANGED` → `Refresh("target")` et `Refresh("targettarget")` ; `PLAYER_FOCUS_CHANGED` → `Refresh("focus")` ; `UNIT_PET` (player) → `Refresh("pet")` ; `UNIT_TARGET` (target) → `Refresh("targettarget")` ; `PLAYER_ENTERING_WORLD` → tout. Événements d'unité enregistrés par `RegisterUnitEvent(frame, event, unit)` sur chaque bouton : `UNIT_HEALTH`, `UNIT_MAXHEALTH`, `UNIT_POWER_UPDATE`, `UNIT_MAXPOWER`, `UNIT_DISPLAYPOWER`, `UNIT_NAME_UPDATE`, `UNIT_LEVEL`, `UNIT_FACTION`, `UNIT_FLAGS`, `UNIT_SPELLCAST_*`, `RAID_TARGET_UPDATE` (global), `PLAYER_REGEN_*` et `PLAYER_UPDATE_RESTING` (player). `targettarget` n'a pas d'événements de santé fiables : ticker `C_Timer.NewTicker(0.5)` actif seulement quand le cadre est visible.

`THEME_CHANGED`, `PIXEL_CHANGED`, `OnRefresh` : `Layout(unit)` hors combat (tailles, positions d'éléments, textures, polices), puis `Refresh(unit)`.

Tests : enable crée cinq boutons avec attribut `unit` et `RegisterUnitWatch` ; en combat, création différée puis faite à `PLAYER_REGEN_ENABLED` ; disable cache et laisse les boutons ; cession ElvUI : rien créé ; movers enregistrés avec les cinq clés ; `PLAYER_TARGET_CHANGED` rafraîchit cible et cible de cible.

### 3. Santé et puissance (`Modules/UnitFrameElements.lua`, `Core/Media.lua`)

`Media:CreateStatusBar(parent)` : `CreateFrame("StatusBar", nil, parent)`, `SetStatusBarTexture(Media:StatusBarTexture())`, fond `theme.backdrop` (texture pleine derrière), enregistré dans le registre faible des backdrops ; `RefreshBackdrops` repose aussi la texture de barre. Option thème `theme.statusbar` (cycle sur `LSM:List("statusbar")`, « Plate » = `""`) : visible seulement si `LibStub("LibSharedMedia-3.0", true)`.

`Health` : `SetMinMaxValues(0, UnitHealthMax(unit))`, `SetValue(UnitHealth(unit))`, valeurs passées telles quelles. Couleur : `HealthColor(unit)` → classe si `classColor` et `UnitIsPlayer` vrai et `UnitClass` non secret (`NS.ClassColor`) ; sinon réaction (`UnitReaction(unit, "player")` non secret : ≥ 5 vert, 4 jaune, ≤ 3 rouge) ; sinon gris `0.6, 0.6, 0.6`. Texte : `healthText` :
- `current` : `AbbreviateNumbers(UnitHealth(unit))` si présent, sinon `UnitHealth` non secret formaté par `NS.FormatShort` (nouveau : k / M), sinon vide ;
- `percent` : `UnitHealthPercent(unit)` si présent (résultat passé à `string.format("%d%%")` seulement si non secret, sinon `AbbreviateNumbers`) ; l'option n'est proposée que si la sonde est verte ;
- `both`, `none`.

`Power` : `UnitPowerType(unit)` non secret → `PowerBarColor[token]` (Blizzard, table publique) sinon bleu mana ; `SetMinMaxValues(0, UnitPowerMax(unit))`, `SetValue(UnitPower(unit))`. Caché si `units[unit].power` faux ou `UnitPowerMax` non secret et égal à 0.

Tests : santé posée sur le widget sans comparaison (valeur secrète acceptée : `Mock.SetSecret(health)` puis `Refresh` sans erreur, `GetValue` = la valeur) ; couleur classe pour un joueur, réaction pour un PNJ, gris si classe secrète ; texte `current` abrégé ; puissance cachée à max 0 ; `UnitPowerType` secret → bleu.

### 4. Barre d'incantation (`UnitFrameElements.CastBar`)

`StatusBar` sous le cadre (hauteur `castbarHeight`), icône du sort à gauche, nom au centre, sans texte de temps (le temps restant serait une lecture d'horloge sur une fin secrète). `Start(unit)` : `UnitCastingInfo(unit)` → `name, text, texture, _, _, _, _, notInterruptible` ; sinon `UnitChannelInfo`. Durée : `UnitCastingDuration(unit)` ou `UnitChannelDuration(unit)` et `bar:SetTimerDuration(duration, nil, Enum.StatusBarTimerDirection.ElapsedTime | RemainingTime)`. Repli si `SetTimerDuration` absent : `startTime`, `endTime` non secrets → `OnUpdate` avec `GetTime()` ; secrets → barre pleine sans progression, nom seul (annoncé une fois dans le diag, pas au user). Couleur : accent du thème ; `notInterruptible` non secret et vrai → gris ; secret → accent. Événements : `UNIT_SPELLCAST_START`, `_STOP`, `_FAILED`, `_INTERRUPTED`, `_DELAYED`, `_CHANNEL_START`, `_CHANNEL_STOP`, `_CHANNEL_UPDATE`, `_INTERRUPTIBLE`, `_NOT_INTERRUPTIBLE`, plus `Refresh(unit)` au changement d'unité. `_INTERRUPTED` : barre rouge 0,5 s puis cachée.

Player : la barre Blizzard `PlayerCastingBarFrame` est masquée seulement quand `units.player.castbar` est coché (tâche 1).

Tests : `UNIT_SPELLCAST_START` montre la barre avec le nom et appelle `SetTimerDuration` avec la durée mockée ; `_STOP` la cache ; `_INTERRUPTED` la passe en rouge ; `notInterruptible` secret garde la couleur d'accent ; changement de cible sans incantation la cache.

### 5. Nom, niveau, indicateurs, marqueur, points de combo

- `Name` : `UnitName(unit)` (secret possible : `SetText` accepte, aucune troncature en Lua ; largeur limitée par `SetWidth` + `SetWordWrap(false)`), couleur classe si `classColor`.
- `Level` : `LevelText(unit)` : `UnitLevel` secret → `""` ; `-1` → `"??"` ; sinon le nombre. Couleur `GetQuestDifficultyColor(level)` seulement si non secret. Caché sur `player` au niveau max (`GetMaxPlayerLevel()` non secret).
- `Indicators` (player) : combat (`UnitAffectingCombat("player")` non secret, ou `PLAYER_REGEN_*`), repos (`IsResting()`), chef (`UnitIsGroupLeader("player")`). Sur `target` : combat seulement, garde secrète comme dans `Frames.UpdateTargetCombat`. Icônes Blizzard (`Interface\CharacterFrame\UI-StateIcon`, `Interface\GroupFrame\UI-Group-LeaderIcon`), 14 px, coin haut gauche.
- `RaidIcon` : `GetRaidTargetIndex(unit)` non secret → `SetRaidTargetIconTexture(texture, index)`, sinon caché. `RAID_TARGET_UPDATE`.
- `ComboPoints` (player, visible si `UnitPowerMax("player", Enum.PowerType.ComboPoints)` non secret et > 0 ; classes Classic : voleur, druide) : **une seule** `StatusBar` de 0 à max avec `SetValue(UnitPower("player", Enum.PowerType.ComboPoints))`, séparateurs 1 px dessinés à chaque graduation. Une barre plutôt que cinq pastilles : aucun `if cur >= i` en Lua, la valeur peut rester secrète. `UNIT_POWER_UPDATE` (ComboPoints), `PLAYER_TARGET_CHANGED`. Posée sous le cadre joueur, hauteur `powerHeight`.

Tests : `LevelText` pour 60, -1 et secret ; niveau caché au niveau max ; indicateur repos suit `Mock.resting` ; marqueur posé pour l'index 8 et caché sans marqueur ; points de combo : barre à max 5, valeur 3 posée telle quelle, cachée à max 0.

### 6. Auras (`UnitFrameElements.Auras`)

Voie principale, si la sonde le confirme : conteneur Blizzard. `C_AddOns.LoadAddOn("Blizzard_AuraContainer")` puis `CreateFrame("AuraContainer", nil, frame, "CustomAuraContainerTemplate")`, `SetUnit(unit)`, un groupe `HARMFUL` puis un groupe `HELPFUL` (`AddAuraGroup`, `AddAuraSlot`), `UpdateAllAuras()`. Le moteur lit, trie, affiche et tient les infobulles : ForeverUI ne lit aucune donnée d'aura. Signatures exactes de `AddAuraGroup` / `AddAuraSlot` (filtre, taille, nombre, sens) à confirmer par lecture de la source Blizzard `Blizzard_AuraContainer` (dépôt public wow-ui-source) **avant** de coder : à valider par le user, comme pour le Cooldown Manager.

Repli si le template est absent : débuffs seulement, par `NS.GetDebuff(unit, index)` existant (icône, durée, fin, stacks, type), 8 boutons maison sous le cadre, `Cooldown:SetCooldown(expiration - duration, duration)` seulement si les deux valeurs sont non secrètes, sinon icône sans spirale ; stacks affichés seulement si non secrets. Buffs : hors repli (lecture `HELPFUL` sur une cible hostile souvent refusée).

Disposition : sous la barre d'incantation (ou sous le cadre), icônes `Pixel:Scale(22)`, 8 par ligne, 2 lignes max, pousse vers le bas. Bordure 1 px à la couleur de dissipation quand elle est connue (`DebuffTypeColor`), sinon `theme.border`.

Tests (repli seulement, le conteneur moteur ne se mocke pas utilement) : 3 débuffs mockés → 3 boutons visibles ; débuff à durée secrète → pas d'appel `SetCooldown` ; unité sans débuff → aucun bouton ; template présent dans le mock → `SetUnit` appelé une fois et aucun bouton maison.

### 7. Options (`Config/Options.lua`, `Modules/Frames.lua`)

Page « Cadres d'unité ForeverUI » : curseurs largeur (120-400), hauteur (24-80), barre de puissance (0-16), barre d'incantation (0-30) ; cycle « Texte de santé » ; case « Couleur de classe » ; par unité, bloc indenté : case activée, case barre d'incantation, case auras, case puissance (`targettarget` : activée seulement) ; bouton « Déverrouiller » (`NS:SetUnlocked(true)`) ; note « Les cadres Blizzard remplacés reviennent après /reload ». Chaque `set` : `NS.Modules:Refresh("unitframes")` (recréation ou masquage différés hors combat par le module).

Thème : cycle `OPT_STATUSBAR` (tâche 3).

`Frames:BuildOptions` : `o:Note(L.FRAMES_NOTE_UNITFRAMES)` quand `NS.Modules:Get("unitframes").enabled`.

Tests : `Options:BuildMain()` avec `unitframes` activé ne lève pas ; option `percent` absente du cycle quand `UnitHealthPercent` est nil dans le mock.

### 8. Locale

`UNITFRAMES_TITLE` « Cadres d'unité ForeverUI », `UNITFRAMES_DESC`, `MOVER_UF_PLAYER/TARGET/TARGETTARGET/FOCUS/PET`, `OPT_UF_WIDTH`, `OPT_UF_HEIGHT`, `OPT_UF_POWER_HEIGHT`, `OPT_UF_CASTBAR_HEIGHT`, `OPT_UF_HEALTH_TEXT`, `HEALTH_TEXT_CURRENT/PERCENT/BOTH/NONE`, `OPT_UF_CLASS_COLOR`, `OPT_UF_UNIT_ENABLED`, `OPT_UF_UNIT_CASTBAR`, `OPT_UF_UNIT_AURAS`, `OPT_UF_UNIT_POWER`, `UF_UNIT_PLAYER/TARGET/TARGETTARGET/FOCUS/PET`, `OPT_UF_UNLOCK`, `NOTE_UF_RELOAD`, `MSG_UF_DISABLED_RELOAD`, `FRAMES_NOTE_UNITFRAMES`, `OPT_STATUSBAR`, `STATUSBAR_FLAT`. enUS et frFR complets, test de parité des clés existant.

### 9. README, version, copie dans le client

README : section « Cadres d'unité » (ce qui est remplacé, retour après `/reload`, réglages), compteur de tests, checklist en jeu ; `ForeverUI.toc` 1.4.0 ; copie fichier par fichier dans `_classic_beta_/Interface/AddOns/ForeverUI/`, `diff -rq` vide.

## Vérification en jeu (checklist user)

1. `/fui diag` : ligne « Unit frames » collée avant la tâche 3.
2. Activer le module : les cadres Blizzard disparaissent, cinq cadres ForeverUI apparaissent ; cible un PNJ hostile : cadre rouge, nom, niveau, santé qui bouge ; cible un joueur : couleur de classe.
3. En combat : santé et puissance vivent, aucune erreur `ADDON_ACTION_BLOCKED`, aucun message « valeur secrète ».
4. Barre d'incantation : PNJ qui incante → barre qui avance ; interruption → rouge puis disparition ; ta propre incantation sur le cadre joueur.
5. Auras : débuffs sur la cible visibles, infobulle au survol.
6. Voleur ou druide : points de combo sous le cadre joueur.
7. `/fui unlock` : les cinq calques bougent, aimant, position conservée après `/reload`.
8. Désactiver le module : message reload, `/reload` rend les cadres Blizzard.
9. Avec ElvUI chargé (le jour où il existe sur Forever) : module grisé « géré par ElvUI ».

## Suivi (hors étape)

- Preset Cooldown Manager reporté à l'étape 7, construit par code (aucune disposition personnelle exportable côté user).
- `Frames` module : quand `unitframes` couvrira aussi le raid (étape 4), ses retouches deviennent entièrement redondantes ; à retirer à ce moment, pas avant.

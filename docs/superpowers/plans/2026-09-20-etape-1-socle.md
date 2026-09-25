# ForeverUI étape 1 — socle : pixel perfect, movers, médias, cession ElvUI

> Cadrage : `docs/superpowers/specs/2026-09-20-positionnement-et-prerequis-plan.md`. Pas de commit sans demande explicite. Chaque tâche : test headless d'abord (`tests/run.sh`), mock enrichi pour chaque API touchée, puis vérification manuelle en jeu par le user.

**Goal :** poser ce dont toutes les étapes suivantes ont besoin : une échelle pixel perfect, un éditeur de position commun (« déverrouillage » ForeverUI), des primitives visuelles uniformes (fond, bordure 1 px, barre de statut, police avec contour), et la cession des modules de cadres quand ElvUI est chargé. Livrable seul : version 1.3.0, visible par l'utilisateur via l'éditeur de position et le thème.

**Architecture :** Lua pur, ordre de chargement du toc comme seul mécanisme de dépendance. Deux fichiers Core nouveaux (`Pixel`, `Movers`), `Media` étendu, `Modules` étendu. Les quatre modules déjà déplaçables migrent vers `Movers` ; `NS.AnchorMixin` disparaît. Aucune référence à EllesmereUI.

**Hors périmètre de l'étape :** ancrage d'un élément sur un autre élément (« anchor to anything »), égalisation largeur/hauteur entre éléments, redimensionnement à la souris. Notés pour l'étape 2 si les unit frames en ont besoin. Skinning des fenêtres Blizzard : étape 6.

## Fichiers

| Fichier | Responsabilité |
|---|---|
| `Core/Pixel.lua` (nouveau) | échelle pixel perfect : `NS.Pixel.mult`, `NS.Pixel:Scale(n)`, `NS.Pixel:Apply()` ; suit `UI_SCALE_CHANGED` et `DISPLAY_SIZE_CHANGED` |
| `Core/Movers.lua` (nouveau) | registre des éléments déplaçables, calque de déverrouillage, snap, nudge clavier, reset, grille ; remplace `NS.AnchorMixin` |
| `Core/Media.lua` | ajoute `CreateBackdrop`, `CreateBorder`, `StatusBarTexture`, contour de police, couleurs de thème `backdrop` et `border` |
| `Core/Modules.lua` | `module.yieldsTo` : liste d'addons qui font céder le module ; `Modules:IsYielded(name)` |
| `Core/Core.lua` | retire `NS.AnchorMixin` ; `NS:SetUnlocked` délègue à `Movers` |
| `Core/Database.lua` | défauts de thème : `fontOutline`, `pixelPerfect`, `backdrop`, `border` ; `anchors` inchangé (format `{ point, relPoint, x, y }` conservé) |
| `Modules/TopBar.lua`, `CoTank.lua`, `Alerts.lua`, `Reminders.lua` | migrent de `AnchorMixin` vers `Movers` ; mêmes clés d'ancrage (`topbar`, `cotank`, `alerts`, `combatTimer`, `reminders`) |
| `Modules/Frames.lua`, `Skin.lua`, `Nameplates.lua` | déclarent `yieldsTo = { "ElvUI" }` |
| `Config/Options.lua` | page Thème : contour, pixel perfect, couleurs fond et bordure, grille ; ligne de module cédé grisée avec « géré par ElvUI » |
| `Config/FirstRun.lua` | case de module cédé décochée et grisée avec la même mention |
| `Locale/enUS.lua`, `Locale/frFR.lua` | nouvelles clés (voir tâche 8) |
| `ForeverUI.toc` | `Core\Pixel.lua` après `Core\Core.lua`, `Core\Movers.lua` après `Core\Media.lua` |
| `tests/wow_mock.lua` | `GetPhysicalScreenSize`, `UIParent:SetScale/GetScale/GetEffectiveScale`, `C_AddOns.IsAddOnLoaded`, `IsShiftKeyDown`, `OnKeyDown`, `SetPropagateKeyboardInput`, `GetCursorPosition` |
| `tests/test_pixel.lua`, `tests/test_movers.lua` (nouveaux), `tests/test_modules.lua` | vérifications de l'étape |

## Tâches

### 1. Pixel perfect (`Core/Pixel.lua`)

Formule publique, aucune ligne reprise d'ElvUI : `mult = 768 / hauteurPhysique / UIParent:GetScale()`. `Scale(n)` renvoie `mult * floor(n / mult + 0.5)`, jamais 0 pour `n ~= 0`. `Apply()` : si `NS.db.theme.pixelPerfect`, `UIParent:SetScale(768 / hauteurPhysique)` borné à `[0.4, 1.15]` ; sinon ne touche pas à l'échelle. Recalcul de `mult` et `NS:Fire("PIXEL_CHANGED")` sur `UI_SCALE_CHANGED` et `DISPLAY_SIZE_CHANGED`. Écriture d'échelle hors combat seulement (`NS:RunOutOfCombat`). Pas de CVar `uiScale` modifié : `UIParent:SetScale` suffit et se rend au disable (échelle d'origine mémorisée).

Tests : `mult` pour 1080p et 1440p à échelle 1 ; `Scale(1)` vaut `mult`, `Scale(0.3)` ne vaut pas 0 ; `Apply` change l'échelle d'`UIParent` seulement si `pixelPerfect` ; désactivation rend l'échelle d'origine ; en combat l'écriture est différée puis exécutée à `PLAYER_REGEN_ENABLED`.

### 2. Médias (`Core/Media.lua`)

- `Media:CreateBackdrop(frame, inset)` : texture de fond `SetColorTexture` aux couleurs `theme.backdrop`, bordure 1 px par quatre textures (haut, bas, gauche, droite) épaisseur `Pixel:Scale(1)` couleur `theme.border`. Pas de `BackdropTemplate` : les quatre textures se recalculent sur `PIXEL_CHANGED` et `THEME_CHANGED`, un template ne le ferait pas.
- `Media:CreateBorder(frame, color)` : les quatre textures seules, pour un cadre qui a déjà son fond.
- `Media:StatusBarTexture()` : `Interface\Buttons\WHITE8X8` par défaut, texture LibSharedMedia si `theme.statusbar` en nomme une et qu'elle existe.
- `Media:CreateText` : ajoute le contour `theme.fontOutline` (`""`, `"OUTLINE"`, `"THICKOUTLINE"`) quand l'appelant ne force pas de flags ; ombre retirée si contour présent.
- Registre faible des backdrops créés pour `RefreshBackdrops()` sur `THEME_CHANGED` et `PIXEL_CHANGED`.

Défauts de thème : `fontOutline = ""`, `pixelPerfect = true`, `backdrop = { r = 0.05, g = 0.06, b = 0.08, a = 0.9 }`, `border = { r = 0, g = 0, b = 0, a = 1 }`, `statusbar = ""`.

Tests : backdrop créé a cinq textures ; changement de `theme.border` puis `THEME_CHANGED` recolore ; `StatusBarTexture` rend WHITE8X8 quand LSM absent ; `CreateText` applique le contour et retire l'ombre.

### 3. Movers (`Core/Movers.lua`)

API :

```lua
NS.Movers:Register(key, frame, label, defaultPoint, defaultX, defaultY)  -- une fois par cadre
NS.Movers:Load(key)        -- pose le cadre depuis db.anchors[key] ou le défaut
NS.Movers:Reset(key)       -- oublie la position sauvée
NS.Movers:SetUnlocked(bool)
NS.Movers:List()           -- clés triées, pour les options
```

Comportement :

- Le cadre réel n'est jamais rendu déplaçable : un **calque** (frame enfant d'`UIParent`, strata `DIALOG`) de la taille du cadre se pose dessus au déverrouillage, avec fond à la couleur d'accent, le libellé, et les coordonnées courantes. C'est le calque qui se déplace ; à la fin du glisser, le cadre réel reçoit le point du calque, puis `db.anchors[key]` est sauvé. Un cadre sécurisé (TopBar avec bouton de foyer) se repositionne donc sans `SetMovable` sur lui-même, et hors combat seulement.
- **Snap** pendant le glisser : bords et centre de l'écran, bords et centre des autres calques, seuil 8 px écran ; désactivable en maintenant Shift. Fonction pure `Movers.SnapDelta(x, y, w, h, candidats, seuil)` testée hors jeu.
- **Nudge** : flèches déplacent le calque sélectionné de 1 px, Shift de 10 px ; `SetPropagateKeyboardInput(false)` seulement quand un calque est sélectionné et déverrouillé, sinon le clavier passe.
- Clic droit sur un calque : reset de cette clé. Infobulle : libellé, point, x, y, « clic droit : réinitialiser ».
- **Grille** optionnelle (`theme.grid = 0 | 16 | 32`) dessinée sur `UIParent` au déverrouillage, textures `WHITE8X8` réutilisées entre affichages.
- Positions sauvées **arrondies au pixel** via `Pixel:Scale`, relatives à `UIParent`, format `db.anchors[key] = { point, relPoint, x, y }` inchangé : les positions existantes des utilisateurs restent valides.
- `Load` en combat : différé par `NS:RunOutOfCombat` si le cadre est protégé (`frame:IsProtected()`), immédiat sinon.
- `NS:SetUnlocked` (Core) appelle `Movers:SetUnlocked` puis émet `UNLOCK` comme aujourd'hui : les modules qui affichent un aperçu au déverrouillage (Alerts, Reminders, CoTank) ne changent pas.

Tests : `Register` + `Load` sans sauvegarde pose le défaut ; sauvegarde puis `Load` repose la position ; `Reset` revient au défaut ; `SnapDelta` colle au bord gauche à 5 px et pas à 12 px, priorité au candidat le plus proche ; nudge déplace de 1 puis 10 avec Shift et sauvegarde ; `Load` d'un cadre protégé en combat est différé ; positions sauvées arrondies au multiple de `mult`.

### 4. Migration des quatre modules

TopBar (mode `FREE`), CoTank, Alerts (`alerts`, `combatTimer`), Reminders : remplacer `Mixin(frame, NS.AnchorMixin)` + `EnablePositioning` par `NS.Movers:Register`, `LoadAnchor` par `Movers:Load`, `ResetAnchor` par `Movers:Reset`. Supprimer `NS.AnchorMixin` de `Core/Core.lua`. CoTank retire son `RegisterForDrag` et `SetMovable` maison (lignes 262-270 actuelles) : le calque s'en charge ; son aperçu sur soi-même au déverrouillage reste.

Tests : `tests/test_topbar.lua`, `test_modules.lua` existants passent sans changement de position sauvée ; `grep AnchorMixin` vide hors tests.

### 5. Cession à ElvUI (`Core/Modules.lua`)

`module.yieldsTo = { "ElvUI" }` sur Frames, Skin, Nameplates. `Modules:IsYielded(name)` : vrai si un des addons de la liste répond vrai à `C_AddOns.IsAddOnLoaded` (pcall, API absente = faux). `Apply(module, true)` ne fait rien si cédé et n'appelle pas `OnEnable` ; `module.db.enabled` reste tel que l'utilisateur l'a réglé. Évaluation à chaque `EnableAll` (login, changement de profil) : un ElvUI désactivé au prochain login rend les modules.

Une ligne « Addons tiers chargés : ElvUI » ajoutée à `/fui diag` (liste des noms de `yieldsTo` de tous les modules, ceux qui répondent chargés).

Tests : mock `C_AddOns.IsAddOnLoaded("ElvUI")` vrai : `EnableAll` n'active pas `frames`, `skin`, `nameplates`, active `topbar` ; `db.modules.frames.enabled` reste vrai ; mock faux : tout s'active ; API absente : rien de cédé.

### 6. Options (`Config/Options.lua`)

Page Thème, après la couleur d'accent : cycle « Contour de police » (aucun, fin, épais), case « Pixel perfect », couleurs « Fond » et « Bordure », cycle « Grille » (aucune, 16, 32), bouton « Déverrouiller » existant, bouton « Réinitialiser toutes les positions » (confirme par `StaticPopup`, puis `Movers:Reset` sur `Movers:List()`).

Liste des modules : un module cédé garde sa case cochée mais grisée, libellé suffixé « (géré par ElvUI) », infobulle explicative. Réutiliser `Layout:Check` avec un état désactivé ; ajouter `Layout:SetEnabled(widget, bool)` dans `Widgets` si absent.

Tests : construction de la page sans erreur avec ElvUI mocké chargé ; le toggle d'un module cédé change `db` sans appeler `OnEnable`.

### 7. FirstRun (`Config/FirstRun.lua`)

Page 1 : case d'un module cédé décochée et grisée, même suffixe. Le choix final n'active pas les modules cédés.

Test : avec ElvUI mocké, `choices.frames` est faux par défaut et la validation n'appelle pas `OnEnable` de `frames`.

### 8. Locale

Clés à ajouter dans `enUS` puis `frFR` : `OPT_FONT_OUTLINE`, `OUTLINE_NONE`, `OUTLINE_THIN`, `OUTLINE_THICK`, `OPT_PIXEL_PERFECT`, `OPT_PIXEL_PERFECT_HINT`, `OPT_BACKDROP_COLOR`, `OPT_BORDER_COLOR`, `OPT_GRID`, `GRID_NONE`, `OPT_RESET_POSITIONS`, `MSG_RESET_POSITIONS_CONFIRM`, `MSG_YIELDED` (« géré par %s »), `MSG_YIELDED_HINT`, `MOVER_TOOLTIP_RESET`, `MOVER_TOPBAR`, `MOVER_COTANK`, `MOVER_ALERTS`, `MOVER_COMBAT_TIMER`, `MOVER_REMINDERS`, `DIAG_THIRD_PARTY`.

Test existant `frFR contient toutes les clés enUS` couvre la complétude.

### 9. README, version, copie dans le client

`ForeverUI.toc` version 1.3.0. README : section « Déverrouillage » (glisser, snap, Shift, flèches, clic droit, grille), section « Compatibilité ElvUI », checklist en jeu : positions conservées après mise à jour, snap, nudge, reset, pixel perfect on/off, ElvUI simulé impossible en jeu (noté). Copie fichier par fichier dans `_classic_beta_/Interface/AddOns/ForeverUI/` (pas de `rsync --delete`).

## Ordre d'exécution

1 (Pixel) → 2 (Media) → 3 (Movers) → 4 (migration) → 5 (cession) → 6 (Options) → 7 (FirstRun) → 8 (Locale, au fil des tâches) → 9. Suite verte à chaque étape. Relecture finale par l'agent `relecteur` sur le diff complet avant de déclarer l'étape terminée.

## Points à valider en jeu par le user (fin d'étape)

1. `/fui unlock` : calques visibles sur TopBar (mode libre), CoTank, alertes, minuteur de combat, rappels ; glisser, snap sur le centre, Shift pour désactiver, flèches, clic droit.
2. `/reload` : positions conservées ; positions sauvées avant la mise à jour toujours respectées.
3. Thème : contour de police, couleurs fond et bordure visibles sur le cadre CoTank et les rappels ; pixel perfect : bordures nettes à 1 px, échelle `UIParent` changée puis rendue au décochage.
4. `/fui diag` : ligne « Addons tiers chargés : - ».
5. Entrer en combat déverrouillé : aucun message « action bloquée », TopBar intouchable jusqu'à la sortie de combat.

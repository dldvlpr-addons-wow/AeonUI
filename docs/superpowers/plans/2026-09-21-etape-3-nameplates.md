# ForeverUI étape 3 — plaques de nom propres

> Cadrage : `docs/superpowers/specs/2026-09-20-positionnement-et-prerequis-plan.md`, section 4 point 3. Socle : étapes 1 et 2 (`NS.UnitFrameElements`, movers, médias, cession ElvUI). Pas de commit sans demande explicite. Tests headless d'abord (`tests/run.sh`), puis vérification en jeu par le user.

**Goal :** remplacer l'habillage Blizzard de chaque plaque de nom par un cadre ForeverUI : santé (couleur réaction, classe pour les joueurs, menace pour les PNJ hostiles en combat), nom, niveau, barre d'incantation avec icône et couleur « ininterruptible », marqueur de raid, débuffs, surbrillance de la cible. Le module existant « Barres de nom » (chevrons) reste et continue de fonctionner par-dessus. Version 1.5.0.

**Architecture :** module `nameplateframes` (`Modules/NamePlateFrames.lua`), `secure = false` (rien de protégé n'est touché : nos cadres sont des enfants d'`UIParent` ancrés sur la plaque, jamais reparentés sous elle, comme les chevrons). Un cadre ForeverUI par plaque, réutilisé (pool par plaque Blizzard), monté à `NAME_PLATE_UNIT_ADDED`, démonté à `NAME_PLATE_UNIT_REMOVED`. Les éléments viennent de `NS.UnitFrameElements` (`Build`, `Layout`, `Update*`, `HandleCast`, auras en repli maison seulement : le conteneur moteur exige un `SetUnit` fixe et une plaque change d'unité). L'habillage Blizzard de la plaque (`plate.UnitFrame`) est masqué par `SetAlpha(0)` et coupé de ses événements ; rendu au disable (alpha 1 ; les événements reviennent au `/reload`, annoncé).

Contrainte Midnight : pas de `SetPoint` sur une plaque en combat ? Les chevrons du module Nameplates font déjà `SetAllPoints(plate)` en combat sans erreur observée (README point 21). On garde le même geste : le cadre ForeverUI est un enfant d'`UIParent`, on l'ancre sur la plaque.

**Hors périmètre :** plaques d'alliés détaillées (santé seule), icônes de quête (API `C_QuestLog` à sonder, Classic), barres de puissance sur plaque, styles par type de PNJ, « clic-cible » (la plaque Blizzard garde la souris : nos cadres n'interceptent pas le clic).

## Fichiers

| Fichier | Responsabilité |
|---|---|
| `Modules/NamePlateFrames.lua` (nouveau) | module `nameplateframes` : pool de cadres, montage/démontage, menace, surbrillance cible, masquage Blizzard, options |
| `Modules/UnitFrameElements.lua` | `Elements.ThreatColor(unit)` (pure) ; `UpdateHealth` accepte `frame.threatColor` (fonction) pour surcharger la couleur ; `Layout` sans castbar/combo quand `cfg.plate` |
| `Core/Compat.lua` | `NS.ThreatSituation(unit)` (pcall, `Known`) ; sonde diag « Menace » déjà là |
| `Locale/enUS.lua`, `Locale/frFR.lua` | `NPF_*`, `OPT_NPF_*` |
| `ForeverUI.toc` | `Modules\NamePlateFrames.lua` après `Modules\UnitFrames.lua` ; version 1.5.0 |
| `tests/wow_mock.lua` | `Mock.namePlates[unitToken] = plate` avec `plate.UnitFrame`, `Mock.AddNamePlate(unit)` / `Mock.RemoveNamePlate(unit)` (événements), `UnitThreatSituation` (`Mock.units[unit].threat`), `UnitIsUnit` déjà présent |
| `tests/test_nameplateframes.lua` | vérifications |
| `README.md` | section, tableau, checklist |

## Tâches

### 1. Module et pool
```lua
defaults = {
  enabled = false, width = 120, height = 10, castbarHeight = 10, fontDelta = -1,
  showName = true, showLevel = true, showCastbar = true, showAuras = true, auraSize = 18,
  friendlyHealth = false,         -- alliés : nom seul par défaut
  targetHighlight = true, threatColor = true, classColor = true,
  hideBlizzard = true,
}
```
- `plates[plate] = frame` (pool), `byUnit[unit] = frame`. `Mount(unit)` : plaque `C_NamePlate.GetNamePlateForUnit(unit)`, cadre du pool ou nouveau (`CreateFrame("Frame", nil, UIParent)`, strata `BACKGROUND`, `Elements.Build`), `frame.unit = unit`, `frame.cfg = {…plate = true…}`, `frame.global = db`, `ClearAllPoints` + `SetPoint("CENTER", plate, "CENTER", 0, 0)`, `Layout`, `UpdateAll`, `Show`. `Unmount(unit)` : `Hide`, `byUnit[unit] = nil`.
- Événements : `NAME_PLATE_UNIT_ADDED/REMOVED`, `PLAYER_TARGET_CHANGED`, `UNIT_THREAT_LIST_UPDATE` (unité), `UNIT_THREAT_SITUATION_UPDATE`, `RAID_TARGET_UPDATE`, `PLAYER_REGEN_*` ; événements d'unité (santé, nom, niveau, auras, incantation) enregistrés une fois sur le frame écouteur sans filtre d'unité, routés vers `byUnit[unit]` (les jetons `nameplateN` sont stables tant que la plaque est montée).
- Masquage Blizzard : `plate.UnitFrame:SetAlpha(0)` + `UnregisterAllEvents` à chaque montage si `hideBlizzard` ; disable : alpha 1, message reload.

### 2. Couleurs et surbrillance
- `Elements.ThreatColor(unit)` : `NS.ThreatSituation(unit)` connu : 3 rouge (agro), 2 orange, 1 jaune, 0/nil → nil (couleur normale).
- `UpdateHealth` : si `frame.threatColor` et une couleur de menace existe, elle prime.
- Surbrillance : bordure du cadre à la couleur d'accent quand `UnitIsUnit(unit, "target")` (réponse secrète → pas de surbrillance), alpha 1 ; autres plaques alpha 0,7 si une cible existe (option).

### 3. Options
Curseurs largeur, hauteur, hauteur castbar, taille des auras ; cases nom, niveau, castbar, auras, vie des alliés, surbrillance, menace, couleur de classe, masquer Blizzard ; note reload.

### 4. Tests
- Montage à `NAME_PLATE_UNIT_ADDED` : cadre visible ancré sur la plaque, santé posée ; démontage cache ; remontage réutilise le même cadre.
- Menace 3 → rouge ; secrète → couleur de réaction.
- Cible → bordure accent ; autre plaque → non.
- Castbar sur `UNIT_SPELLCAST_START` avec unité `nameplate1`.
- Disable : alpha du `UnitFrame` Blizzard rendu, message reload.
- Module `nameplates` (chevrons) toujours actif en même temps : aucune erreur.

## Vérification en jeu
1. Activer le module : les plaques Blizzard laissent place aux barres ForeverUI ; cible : bordure colorée.
2. En combat sur un PNJ : barre rouge quand tu as l'agro (tank), orange/jaune sinon ; aucune erreur « valeur secrète ».
3. PNJ qui incante : barre sous la plaque avec l'icône ; sort ininterruptible : gris.
4. Débuffs posés : icônes au-dessus de la plaque.
5. Désactiver : message reload ; `/reload` rend les plaques Blizzard.

# ForeverUI étapes 7 et 8 — installation un clic v2, profils par rôle

> Cadrage : section 4 points 7 et 8. Codé sans validation en jeu. Version 1.8.0 (avec l'étape 6).

## Étape 7 — installation un clic v2 (`Config/Install.lua`, `NS.Install`)
- Deux préréglages : `complete` (allume unitframes, nameplateframes, groupframes, actionbars, minimap, chat, databars, questtracker ; coupe `frames` devenu redondant ; pose les ancrages `COMPLETE_ANCHORS` dans `NS.db.anchors` ; applique les CVars recommandées de l'assistant ; importe la disposition Edit Mode `NS.PRESET_LAYOUTS.editMode` en pcall) et `light` (coupe ces modules, rallume `frames`).
- Un module cédé (ElvUI, Bartender4…) garde son réglage `enabled` dans la base mais n'est pas allumé.
- `NS.Modules:RefreshAll()` après les ancrages : chaque module recharge ses movers.
- Page 1 de l'assistant « Installation rapide » : cycle préréglage, cycle rôle, bouton « Installer maintenant » ; les pages existantes passent en 2 à 5. Slash `/fui install [complete|light] [dps|heal|tank]` (le dispatcher passe désormais le reste de la ligne au handler).

## Étape 8 — profils par rôle
- Les profils par personnage, la copie, la remise à zéro, la suppression et l'export/import existaient déjà (`Core/Database.lua`, section Profils des options).
- `Install.ROLES` : `dps` (groupe 80×30 sans puissance, focus avec auras, menace sur les plaques), `heal` (groupe 100×44 avec puissance, dispel, portée, texte en %, cible et focus avec auras, vie des alliés sur les plaques), `tank` (groupe 90×36, agro, co-tank allumé, menace). Fusion clé par clé : ce que le rôle ne couvre pas reste tel quel.
- Options > Profils : cycle rôle + « Appliquer ce rôle au profil actuel » + « Créer un profil de rôle pour ce personnage » (copie du profil actif nommée `<Perso - Royaume> - <Rôle>`, puis ajustée).

## Tests
- `tests/test_install.lua` : préréglage complet (modules, ancrages posés sur le cadre, CVars, rôle, `firstRunDone`), léger, rôle tank (co-tank), cession ElvUI, slash avec arguments et usage, profil de rôle sans toucher Default. `tests/test_setup.lua` : cinq pages.

## Risques en jeu
- L'import Edit Mode en fin d'installation crée ou remplace la disposition « ForeverUI » (5 dispositions max : message si plein, non bloquant).
- Ancrages du préréglage à ajuster à l'œil sur 1080p et ultra-large.

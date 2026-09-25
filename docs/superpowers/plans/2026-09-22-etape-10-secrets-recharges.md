# ForeverUI étape 10 : secrets et recharges

> Analyse : `docs/superpowers/specs/2026-09-22-analyse-elvui-15-26.md`, section 5 point 1. Validée par
> le user le 2026-09-22 (« ok démarre etape 10 »). Codé sans validation en jeu. Version 1.10.0.
> Mécanismes observés chez ElvUI Mainline (même moteur 12.x), aucun code repris.

**Goal :** laisser le moteur afficher les valeurs secrètes (vie, portée, recharges) au lieu de les
lire en Lua, avec un repli partout où le client n'a pas l'API.

## Livré

- `Core/Compat.lua`, section « Midnight » :
  - `NS.IsSecretUnit(unit)` : `C_Secrets.ShouldUnitIdentityBeSecret` (ou le global), faux si absent.
  - `NS.GradientRGB(fraction)`, `NS.HealthGradient(unit)` → `applied, r, g, b` : courbe `C_CurveUtil.CreateColorCurve` à trois points passée à `UnitHealthPercent(unit, true, curve)` ; composantes peut-être secrètes, jamais testées (l'appelant teste `applied`) ; repli calcul Lua si vie lisible ; `false` sinon.
  - `NS.SetRangeAlpha(frame, unit, outside)` : `SetAlphaFromBoolean` si présent, sinon test Lua, plein si secret ; portée non vérifiée, soi-même ou hors ligne = plein.
  - Texte de recharge : `NS.RegisterCooldown`, `NS.StyleCooldown`, `NS.RefreshCooldowns`, `NS.CooldownBreakpoints` ; formateur `C_StringUtil.CreateNumericRuleFormatter` par recharge, paliers « presque fini » (décimale), secondes, minutes, heures, jours, couleurs par code `|c` ; paliers heures et jours à 3540 s et 82800 s ; retiré proprement (formateur nil, `SetHideCountdownNumbers(false)`, la CVar décide).
  - `/fui diag` : ligne « Midnight » (six API, cadres de sonde réutilisés), CVar `countdownForCooldowns`.
- Enregistrement des recharges : boutons des barres d'action, icônes d'auras des cadres (`UnitFrameElements`), débuffs du co-tank, boutons du menu Voyage de la barre du haut.
- Interface épurée : `cooldownColors` (allume aussi la CVar `countdownForCooldowns`, dont dépend le compte à rebours natif), `cooldownExpiring` (3 s, 0 = jamais), trois couleurs ; note si le client n'a pas le formateur.
- Cadres d'unité et de groupe : `healthGradient` (prime sur la couleur de classe).
- Cadres de groupe : portée par `NS.SetRangeAlpha` (avant : abandon et alpha plein dès que la portée était secrète).
- Infobulles et couleur de classe : identité secrète = aucun détail, pas de couleur de classe.

Relecture (agent relecteur) : dégradé qui testait une couleur secrète (bloquant), chiffres cachés après retrait, CVar requise par le texte coloré, seuils heures et jours, portée de soi-même sous vérification secrète, pas de fonction inutilisée : corrigés.

## Tests

`tests/test_midnight.lua` (8 tests) : paliers, pose et retrait du formateur, client sans formateur, barres enregistrées, dégradé par courbe malgré une vie secrète et repli, portée secrète confiée au moteur, identité secrète, ligne de diagnostic. Mock : `CreateColor`, `C_CurveUtil`, `C_StringUtil`, `SetCountdownFormatter`, `SetHideCountdownNumbers`, `C_Secrets`.

## Risques en jeu

- Présence et signature exactes des API sur Forever : la ligne « Midnight » de `/fui diag` tranche.
- Format des paliers (`threshold`, `format`, `rounding`, `step`, `components.div`) déduit du comportement observé chez ElvUI : à vérifier à l'œil (texte « 1m » à 59 s, décimale sous le seuil).
- `SetCountdownFormatter(nil)` pour retirer le formateur : appelé sous `pcall` ; au pire le texte coloré reste jusqu'au `/reload`.

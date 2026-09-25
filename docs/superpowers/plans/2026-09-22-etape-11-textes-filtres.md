# ForeverUI étape 11 : formats de texte et filtres d'auras

> Analyse : `docs/superpowers/specs/2026-09-22-analyse-elvui-15-26.md`, feuille de route étape 11.
> Lancée par le user le 2026-09-22 (« go »). Codé sans validation en jeu. Version 1.11.0.
> Mécanismes inspirés des tags oUF et des filtres d'auras d'ElvUI, aucun code repris.

**Goal :** texte de vie et de puissance libre par cadre, et un seul jeu de filtres d'auras partagé
par les cadres d'unité, les plaques et le co-tank.

## Livré

- `Modules/UnitFrameElements.lua`, formats de texte :
  - Jetons `[cur]`, `[max]`, `[perc]`, `[missing]`, `[status]` ; texte libre autour ; jeton inconnu laissé tel quel.
  - `Elements.CompileFormat` : format compilé une fois en motif `%s` (cache vidé à 64 formats) ; `Elements.SetUnitText` passe les valeurs à `SetFormattedText`, qui accepte les secrets.
  - `[perc]` : `UnitHealthPercent(u, true, CurveConstants.ScaleTo100)` (ou `UnitPowerPercent`) formaté par `%.0f` sans être lu ; sinon pourcentage lisible, sinon calcul sur valeurs lisibles, sinon la valeur courante.
  - `[missing]` : `UnitHealthMissing` + `C_StringUtil.TruncateWhenZero` ; sinon calcul lisible, vide à plein.
  - `[status]` : Mort, Fantôme, Déconnecté sur valeurs lisibles, vide sinon.
  - Préréglages `TEXT_PRESETS` : valeur, pourcentage, valeur | pourcentage, valeur / maximum, manquant, aucun. Le format personnalisé du cadre prime sur le préréglage.
- `Core/Compat.lua`, filtres d'auras :
  - `NS.GetDebuff` rend en plus l'identifiant du sort et l'origine (joueur ou familier).
  - `NS.DISPEL_BY_CLASS` (démoniste compris), `NS.PlayerCanDispel`, `NS.AURA_FILTERS`, `NS.AuraFilterChoices`.
  - `NS.AuraPasses(mode, spellId, dispelName, isBoss, isMine)` : listes blanche et noire du profil d'abord (identifiant lisible seulement), puis filtre ; tout champ secret garde l'aura.
  - `NS.ParseSpellList` : liste « 1234, 5678 » en ensemble, mis en cache.
- `Core/Database.lua` : `auraLists = { whitelist, blacklist }` dans le profil.
- Cadres d'unité : `auraFilter`, `healthFormat`, `powerFormat` par unité ; préréglages étendus ; listes partagées dans les options. Conteneur moteur gardé pour « tout » et « les miens » (`HARMFUL|PLAYER`), repli maison pour les autres filtres ; changement de filtre = conteneur remplacé.
- Plaques : `auraFilter` (« les miens » par défaut), `healthFormat`, préréglages étendus.
- Groupe : préréglages étendus. `GroupFrames.DISPEL_BY_CLASS` pointe sur la table partagée (le démoniste compte désormais).
- Co-tank : `Keep` remplacé par `NS.AuraPasses`, filtres « les miens » et « boss » en plus.

## Tests

`tests/test_text_filters.lua` : compilation et rendu des jetons, préréglages, statut, pourcentage et manque secrets confiés au moteur, format du cadre sur la barre, filtres, champs secrets, listes, identifiant et origine de `GetDebuff`, cadre filtré. `test_unitframes` et `test_nameplateframes` adaptés. Mock : `SetFormattedText`.

## Risques en jeu

- `CurveConstants.ScaleTo100` et `UnitHealthMissing` peuvent manquer sur Forever : repli calcul, ou valeur courante si tout est secret.
- Les listes blanche et noire ne s'appliquent pas au conteneur d'auras du moteur (filtres « tout » et « les miens » des cadres d'unité).
- Saisie d'un format : rafraîchissement du module à chaque touche.
- Filtres « importants », « dissipables » et « boss » sur un cadre d'unité : repli maison, qui ne montre que les débuffs (les buffs disparaissent).
- Sans `CurveConstants.ScaleTo100`, le pourcentage ne lit pas `UnitHealthPercent` (fraction 0-1 ambiguë) : calcul sur valeurs lisibles.

Relecture (agent relecteur) : secrets comparés à nil avant `NS.IsSecret` et chaîne secrète testée par `or ""` (rendu des jetons), ancien préréglage `both` perdu, boss secret qui ouvrait le filtre « dissipables », conteneur d'auras remplacé qui restait vivant, pourcentage 0-1 lu comme 0-100 : corrigés.

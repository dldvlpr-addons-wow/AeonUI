# ForeverUI étape 13 : filtres de style des plaques

> Analyse : `docs/superpowers/specs/2026-09-22-analyse-elvui-15-26.md`, feuille de route étape 13.
> Lancée par le user le 2026-09-22 (« go étape 13 »). Codé sans validation en jeu. Version 1.13.0.
> ElvUI 15.26 n'a plus de filtres de style : mécanisme repris de ses anciennes versions, aucun code.

**Goal :** règles « si conditions alors habillage » sur les plaques de nom, sûres face aux valeurs secrètes.

## Livré

- `Modules/NamePlateFrames.lua` :
  - `styleRules` : cinq règles fixes dans les réglages (coupées par défaut), dans l'ordre de priorité.
  - Conditions : cible, incantation, combat de l'unité (tri-état peu importe / oui / non), réaction, classification (normal, élite, rare, boss), quête en cours (`C_QuestLog.UnitIsRelatedToActiveQuest`, sinon `UnitIsQuestBoss`), vie sous x % (valeurs lisibles), noms (sous-chaîne, sans casse, séparés par des virgules).
  - Condition illisible (secret, API absente) : la règle échoue. Nom de sort secret : l'unité incante.
  - Actions : couleur de la barre de vie, lueur (aplat qui déborde), taille (`SetScale`), opacité, masquer (alpha 0).
  - `NamePlateFrames.RuleMatches`, `:MatchStyle`, `:ApplyStyle`. Ordre fixe : `UpdateHealth` (couleur) puis `UpdateHighlight` (opacité) puis `ApplyStyle` : une règle qui cesse de correspondre ne laisse rien.
  - Événements : incantation, combat (`UNIT_FLAGS`), `UNIT_CLASSIFICATION_CHANGED`, `QUEST_LOG_UPDATE`, changement de cible, entrée et sortie de combat.
  - Options : un bloc par règle.
- `Config/Options.lua` : `o:Color` accepte une clé imbriquée.

## Tests

`tests/test_style_filters.lua` (5 tests) : défauts, incantation (couleur, lueur, retour, nom secret), vie basse, noms, priorité, vie et nom secrets, cible, réaction, combat, classification, quête et réponse secrète, options.

## Risques en jeu

- En combat, la vie et le nom des ennemis peuvent être secrets : « vie sous » et « noms » ne s'appliquent alors plus.
- Masquer ne coupe que notre cadre : la plaque Blizzard, invisible, reste cliquable.
- La taille agrandit notre cadre, pas la zone de clic de la plaque.

Relecture (agent relecteur) : icône de combat affichée sur les plaques par `UNIT_FLAGS` (routé vers la vie seulement), règles perdues à l'export et au miroir CVar (clés `rule1` à `rule5` au lieu d'indices ; échelle bornée 0,5 à 2 et opacité 0 à 1 pour une chaîne importée), `UNIT_AURA` qui recalculait toute la vie, cible et incantation évaluées sur « peu importe », réaction secrète lue comme hostile (échoue désormais), lueur en aplat sous une plaque alliée en nom seul, capitales accentuées non abaissées, `QUEST_LOG_UPDATE` sans règle de quête : corrigés.

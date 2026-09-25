# ForeverUI étape 12 : indicateurs de groupe

> Analyse : `docs/superpowers/specs/2026-09-22-analyse-elvui-15-26.md`, feuille de route étape 12.
> Lancée par le user le 2026-09-22 (« go étape 12 »). Codé sans validation en jeu. Version 1.12.0.
> Mécanismes observés chez ElvUI, aucun code repris.

**Goal :** appel prêt, invocation, résurrection, prédiction de soins, portrait optionnel, menace en
bordure ou lueur, cadres des tanks et assistants principaux.

## Livré

- `Modules/UnitFrameElements.lua` (cadres d'unité et de groupe) :
  - Prédiction de soins (`UnitGetIncomingHeals`) et absorptions (`UnitGetTotalAbsorbs`) : deux StatusBar accrochées au bout de la texture de vie, dans un cadre de rognage dédié (`SetClipsChildren`). Valeurs secrètes passées au widget ; API absente = barre cachée. Réglage global `healPrediction`.
  - Couche `frame.overlay` au-dessus des barres : textes et icônes restent lisibles.
  - Portrait 2D hors du cadre (`SetPortraitTexture`), `cfg.portrait`, côté `cfg.portraitSide`. Événements `UNIT_PORTRAIT_UPDATE`, `UNIT_MODEL_CHANGED`.
- `Modules/UnitFrames.lua` : `healPrediction` (vrai), `portrait` par unité (faux), côté gauche pour joueur et familier, droit sinon.
- `Modules/GroupFrames.lua` :
  - Icône centrale : résultat d'appel (`GetReadyCheckStatus`, gardé 6 s après `READY_CHECK_FINISHED`), sinon invocation (`C_IncomingSummon.IncomingSummonStatus`, atlas), sinon résurrection (`UnitHasIncomingResurrection`). Valeur secrète : rien. Option `statusIcons`.
  - Menace : statut 2 orange, 3 rouge ; `aggroStyle` bordure ou lueur (aplat qui déborde du bouton).
  - En-têtes `tank` et `assist` (`groupFilter` MAINTANK, MAINASSIST), options `mainTanks`, `mainAssists` (faux), visibles en raid, movers `uf_tank`, `uf_assist`.
  - `byUnit[jeton]` devient un ensemble de boutons (une unité peut être dans le raid et les tanks) ; `GetButton(unit, key)`.
- `Config/Install.lua` : ancrages `uf_tank`, `uf_assist` ; profil Soigneur avec les tanks principaux.

## Tests

`tests/test_group_indicators.lua` (6 tests) : appel et délai, invocation, résurrection, secret, menace bordure et lueur, prédiction et absorption secrète, tanks principaux et double bouton, portrait. Mock : `GetFrameLevel`, `SetClipsChildren`, `GetStatusBarTexture`, `SetAtlas`, `groupFilter` des en-têtes.

## Risques en jeu

- Forever peut ne pas exposer `UnitGetIncomingHeals` (prédiction Classic) ni `C_IncomingSummon` : fonctions silencieuses.
- Les atlas d'invocation peuvent manquer sur ce client : icône vide.
- Soins entrants au-delà de la vie max : barre rognée au cadre, pas plafonnée à la vie manquante.

Relecture (agent relecteur) : rognage posé sur la barre de vie qui coupait les icônes débordantes (cadre de rognage dédié aux barres de prédiction), résultat d'appel qui dépendait de `GetReadyCheckStatus` après la fin (état mémorisé par bouton, « en attente » devient « pas prêt »), cadrage d'atlas resté sur l'icône et atlas absent affiché (`SetTexCoord` remis, retour de `SetAtlas` testé), globales `READY_CHECK_*_TEXTURE` possiblement des atlas (chemins de fichiers) : corrigés. Aussi : `GetButton` rend nil au lieu de false, plus d'allocation par mise à jour de la prédiction.

# ForeverUI étape 14 : panneaux de données

> Analyse : `docs/superpowers/specs/2026-09-22-analyse-elvui-15-26.md`, feuille de route étape 14.
> Lancée par le user le 2026-09-22 (« go étape 14 »). Codé sans validation en jeu. Version 1.14.0.
> Mécanisme des data texts et panneaux d'ElvUI, aucun code repris.

**Goal :** panneaux libres sur les movers, textes d'information partagés avec la barre du haut,
nouveaux textes (coordonnées, quêtes, régénération, vitesse, DPS natif).

## Livré

- `Core/DataTexts.lua` : registre `NS.DataTexts` (`Register`, `Get`, `Choices`, `Render`). Un texte rend une chaîne, ou un motif et des valeurs passés à `SetFormattedText` (valeurs secrètes). Champs : `tooltip`, `click`, `events`, `interval`, `secret`, `noCombatTooltip`.
  - Coordonnées (`C_Map`, 0,5 s ; instance ou secret : tiret ; clic : carte), quêtes (journal plein en rouge ; clic : journal), régénération de mana par 5 s hors et en incantation (`GetManaRegen`), vitesse en % de la course (`GetUnitSpeed`), DPS du joueur par `C_DamageMeter` (valeur secrète abrégée par `AbbreviateNumbers`, jamais lue).
- `Modules/TopBar.lua` : amis, guilde, heure, or, durabilité, sacs et FPS inscrits au registre (avec leurs événements). Deux emplacements libres `extraLeft`, `extraRight` pour tout texte non secret (largeur mesurée), rafraîchis à 1 Hz.
- `Modules/DataPanels.lua` : module « Panneaux de données » (coupé par défaut), trois panneaux `panel1` à `panel3`, emplacements `slot1` à `slot6` (clés chaînes : exportés avec le profil) (le premier actif avec coordonnées, vitesse, régénération, quêtes), movers `datapanel1` à `datapanel3`, 1 à 6 emplacements de largeur égale, opacité, masquage en combat. Événements : union de ceux des textes affichés, `UNIT_*` limités au joueur ; minuterie 0,5 s pour les textes à intervalle.

Choix : la barre du haut n'est pas refondue en panneau. Son foyer et son menu Voyage sont des boutons sécurisés, déjà stables ; elle partage ses textes et accueille ceux du registre dans deux emplacements libres.

## Tests

`tests/test_data_panels.lua` (5 tests) : registre et choix, textes et secrets, DPS secret, panneau (mover, emplacements, minuterie, événement, masquage en combat, désactivation), emplacements libres de la barre. `test_config` : 23 sous-pages.

## Risques en jeu

- `C_DamageMeter` peut manquer sur Forever : DPS = tiret.
- `GetManaRegen` sur une classe sans mana : 0.
- Le module n'est pas dans l'installation un clic : à activer à la main.

Relecture (agent relecteur) : texte DPS qui testait en booléen la chaîne secrète d'`AbbreviateNumbers` (vide en combat), state drivers posés ou retirés en combat par un module non `secure` (module arrêté en erreur ; désormais `secure`, réglages appliqués à la sortie du combat), unité `nil` passée à `RegisterEventSafe` pour les événements non `UNIT_*`, clés numériques des panneaux perdues à l'export (`panel1`, `slot1`) : corrigés.

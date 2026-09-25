# ForeverUI étape 9 : parité ElvUI (« ElvUI killer »)

> Demande du user le 2026-09-22 : « il faut maintenant passer en elvui killer l'addon », référence
> le guide Wowhead « ElvUI Addon Guide ». Le contenu de la page n'a pas pu être lu (WebFetch ne rend
> que les commentaires, extension Chrome non connectée) : la matrice ci-dessous part des modules
> ElvUI connus. Codé sans validation en jeu. Version 1.9.0. Pas de commit sans demande explicite.

## Matrice ElvUI / ForeverUI

| Module ElvUI | ForeverUI avant l'étape 9 | Étape 9 | Reste |
|---|---|---|---|
| Général : échelle, pixel perfect, polices, textures, couleurs | fait (socle) | | |
| Movers : déverrouillage, aimant, grille, flèches, réinitialisation | fait (socle) | | ancrer un mover à un autre cadre |
| Assistant d'installation, profils, export/import, presets | fait (étapes 7-8) | écran d'absence dans le préréglage complet | |
| Barres d'action : 6 barres, pagination, posture, familier, micro-menu, sacs | fait (étape 5) | fondu au survol par barre, textes de raccourci et de macro masquables, mode raccourcis `/fui kb` | barres 7-10, bouton d'action supplémentaire, couleur hors portée ou sans ressource |
| Chiffres de recharge (Cooldown Text) | absent | CVar native `countdownForCooldowns` | couleurs par seuil (le natif n'en a pas) |
| Cadres d'unité : joueur, cible, ToT, focus, familier | fait (étape 2) | cible du focus, boss 1 à 5, fondu hors combat par unité | portrait, prédiction de soins, icônes PvP, appel, résurrection, barres d'auras, filtres d'auras, textes personnalisés (tags) |
| Groupe et raid | fait (étape 4) | | familiers du raid, tanks et assistants principaux |
| Plaques de nom | fait (étape 3) | | filtres de style |
| Infobulles | sombres, couleur de classe, masquage en combat | au curseur, cible de l'unité, rang de guilde, ID de sort, d'objet et d'aura, barre de vie masquable | niveau d'objet et talents par inspection |
| Chat, minimap, barres de données, suivi de quêtes | fait (étape 6) | | barre d'honneur |
| Data texts | barre du haut | | panneaux de data texts configurables |
| Auras du joueur | cadres Blizzard déplaçables + icônes recadrées | | en-têtes d'auras ForeverUI avec minuteurs |
| Habillage Blizzard | panneaux sombres | | reskin complet par cadre |
| Divers : AFK | absent | écran d'absence (module `afk`) | |
| Divers : jets de butin, cadre de butin, utilitaire de raid | absent | | à planifier |
| Sacs | absent | | reporté au cadrage v2 |
| Annonce d'interruption | absent | | impossible : journal de combat interdit sur Forever |

## Livré

- **Habillage > Infobulles** : `anchorCursor` (hook `GameTooltip_SetDefaultAnchor`, `ANCHOR_CURSOR`), `tooltipTarget` (ligne « Cible : », « >> VOUS << » en rouge, couleur de classe), `guildRank` (rang ajouté à la ligne de guilde), `tooltipIDs` (post-calls `Spell`, `Item`, `UnitAura`, `data.id`), `hideHealthBar`. Toute valeur secrète : la ligne est omise.
- **Interface épurée** : `cooldownNumbers` pose `countdownForCooldowns = 1` via `NS.CVars`, rendue à la coupure.
- **Barres d'action** : `bars[n].mouseover` (fondu par `OnUpdate` toutes les 0,1 s, visible au survol, sort tenu au curseur ou mode raccourcis ; `SetAlpha` permis en combat), `hotkeys`, `macroNames` (alpha des textes `HotKey` et `Name`). Mode raccourcis `/fui kb` ou bouton d'options : cadre clavier plein écran, touche avec modificateurs liée à la commande Blizzard du bouton survolé (`SetBinding` + `SaveBindings`), Échap efface ou ferme, fermé à l'entrée en combat.
- **Cadres d'unité** : `focustarget` (coupé par défaut, rafraîchi par sondage comme la ToT), `boss1` à `boss5` sur un bloc de réglages `units.boss`, un mover par boss, cadres Blizzard `BossTargetFrameContainer` et `BossNTargetFrame` masqués, `INSTANCE_ENCOUNTER_ENGAGE_UNIT`. Fondu hors combat par unité (`fader`, opacité commune `fadeAlpha`) : plein en combat, avec une cible, en incantation, blessé ou survolé ; valeur secrète = plein.
- **Écran d'absence** (`Modules/AFK.lua`) : `PLAYER_FLAGS_CHANGED` + `UnitIsAFK`, hors combat seulement ; `UIParent` caché, caméra `MoveViewLeftStart`, bandeau enfant de `WorldFrame` (nom, niveau, classe, guilde, minuteur) ; retour au retour du joueur, à `PLAYER_REGEN_DISABLED` ou sur un clic. Cède à ElvUI. Coupé par défaut, allumé par le préréglage complet.

## Tests

`tests/test_elvui_parity.lua` (10 tests), mock étendu (survol, lignes d'infobulle, post-calls par type, guilde, `SetBinding`, curseur, AFK, caméra). `tests/run.sh` : 194 ok.

## Risques en jeu

- `UIParent:Hide()` hors combat : vérifier qu'aucun blocage n'apparaît au retour en combat (l'événement arrive avant le verrouillage).
- `countdownForCooldowns` : présence de la CVar sur Forever (ignorée sinon, `NS.CVars:Set` ne crée rien).
- Fondu des barres et des cadres d'unité en combat : `SetAlpha` sur cadre protégé, attendu sans erreur.
- Mode raccourcis : les touches liées aux commandes Blizzard sont relayées par `BindBar` à `UPDATE_BINDINGS`.
- Boss : noms `BossTargetFrameContainer` et `BossNTargetFrame` sur ce moteur (absents = ignorés).

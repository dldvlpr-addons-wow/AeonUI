# ForeverUI v1 — plan d'implémentation

> Exécution inline (demande du user : « oui fait »). Pas de commit sans demande explicite.

**Goal :** addon ForeverUI (WoW Forever 16001) avec 4 modules activables, sans dépendance, testé hors jeu.
**Architecture :** Lua pur sur le modèle de KickAlert : Locale → Core (Compat, Core, Database, Modules, Media) → Modules → Config. Registre de modules à interface fixe (OnEnable/OnDisable/OnRefresh), file hors combat pour tout ce qui est sécurisé.
**Tech :** Lua 5.1 (client), tests sur `/opt/homebrew/bin/lua` avec shim `unpack`, mock repris de `~/Dev/kickAlert/tests/wow_mock.lua`.

## Fichiers

| Fichier | Responsabilité |
|---|---|
| `ForeverUI.toc` | métadonnées, ordre de chargement |
| `Locale/enUS.lua`, `frFR.lua`, `Locale.lua` | chaînes ; `NS.L` rempli sur place, `NS.SetLocale(code)` |
| `Core/Compat.lua` | feature-detection : sorts, auras, conteneurs, sons, timers, options, polices, `IsSecret` |
| `Core/Core.lua` | `NS:On/Fire`, `NS:RunOutOfCombat(fn)`, `NS.Print`, slash `/fui`, chargement DB |
| `Core/Database.lua` | `NS.Database:Init(saved)` fusion défauts + `Migrate` |
| `Core/Modules.lua` | `NS.Modules:Register/SetEnabled/Get/List/Refresh`, xpcall par module |
| `Core/Media.lua` | `NS.Media:Font()`, `:ApplyFont(fs, size)`, `:Accent()`, `:Play(preset)` |
| `Modules/TopBar.lua` | barre du haut + bouton foyer sécurisé |
| `Modules/Automation.lua` | réparation, vente, libération ALT, invitations, suppression rapide |
| `Modules/Reminders.lua` | règles de rappel (données) + moteur d'évaluation + affichage |
| `Modules/Skin.lua` | infobulles, flèches de cible, police |
| `Config/Options.lua` | page d'options scrollable, section par module |
| `Config/FirstRun.lua` | fenêtre de premier lancement |
| `tests/wow_mock.lua`, `tests/run_tests.lua`, `tests/run.sh` | vérification hors jeu |

## Tâches

1. **Squelette + tests** : `.toc`, mock copié/complété, `run.sh` (syntaxe, suite, cohérence toc). Test : l'addon se charge sans erreur, `ADDON_LOADED` crée `ForeverUIDB`.
2. **Core** : Database (défauts fusionnés, valeur existante conservée, migration version), bus, file hors combat. Tests : fusion ; `RunOutOfCombat` exécute tout de suite hors combat, diffère en combat puis exécute à `PLAYER_REGEN_ENABLED`.
3. **Modules** : registre. Tests : enable/disable appelle les callbacks, erreur d'un module capturée et n'empêche pas les autres, module `secure` différé en combat.
4. **Automation**. Tests : vente = seulement gris avec valeur, par lots de 10, arrêt à `MERCHANT_CLOSED` ; réparation guilde puis perso ; invitation ami/guilde acceptée, inconnu ignoré ; libération : bloqueur posé en instance seulement.
5. **Reminders**. Tests : buff manquant signalé si sort connu, pas si inconnu, pas en combat, valeur secrète ignorée ; durabilité ; sacs pleins.
6. **TopBar**. Tests : textes (amis, guilde, or, durabilité, sacs) ; disable cache la barre ; bouton foyer créé avec `type=item`.
7. **Skin**. Tests : couleurs d'infobulle appliquées puis restaurées au disable ; flèches attachées à la plaque de la cible.
8. **Options + FirstRun + Locale frFR**. Tests : construction sans erreur, toggle d'un module via la page, frFR contient toutes les clés enUS.
9. **README** (installation, commandes, checklist en jeu) + copie dans `_classic_beta_/Interface/AddOns/ForeverUI`.

Chaque tâche : écrire le test, le voir échouer, implémenter, `tests/run.sh` vert.

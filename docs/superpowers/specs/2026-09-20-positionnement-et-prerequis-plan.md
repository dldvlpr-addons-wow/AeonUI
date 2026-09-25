# ForeverUI — cadrage v2 : UI complète à cadres propres

> Validé par le user le 2026-09-20. Remplace le cadrage « couche légère » du matin. Rien de l'existant n'est supprimé : les douze modules restent et se rebranchent sur le socle.

## 1. Décision

ForeverUI devient une **UI complète pour WoW Forever, à cadres propres**, sur le modèle ElvUI et EllesmereUI : unit frames, nameplates, party/raid, barres d'action, minimap, chat, data bars, tous construits par ForeverUI, positionnés par un éditeur visuel maison. Le confort existant (Automation, Reminders, Alerts, CoTank, Gear, GroupFinder, Cursor) reste et s'appuie sur le même socle.

Contraintes posées par le user :

- **Compatibilité ElvUI** : ElvUI doit pouvoir être installé avec ForeverUI. Quand `C_AddOns.IsAddOnLoaded("ElvUI")` est vrai, les modules de cadres de ForeverUI ne s'activent pas ; le réglage utilisateur reste en base et le module revient seul si ElvUI est absent. Options et FirstRun affichent « géré par ElvUI ».
- **Aucun code, dépendance ni détection EllesmereUI** dans ForeverUI. EllesmereUI sert seulement de référence de lecture pour savoir ce que l'API Forever permet.
- Publication prévue : aucun média sous licence (pas de polices Naowh/Gotham, pas de code ElvUI, licence ElvUI restrictive). Polices du jeu + LibSharedMedia, textures plates générées par code, sons SOUNDKIT. GPL-3.0.
- Lua pur sans Ace, un seul `ForeverUI.toc` (le client Forever charge `<Addon>_Camelot.toc` puis le toc sans suffixe), tests headless sur `tests/wow_mock.lua`.

## 2. Ce que le terrain permet (vérifié le 2026-09-20)

- Forever 1.60.1, interface 16001, moteur 12.x, contenu Classic sans spécialisations ni M+. Restrictions Midnight : valeurs secrètes (`issecretvalue`), combat log interdit, pas de calcul ni d'automatisation sur les données de combat, cadres sécurisés intouchables en combat.
- **Cadres custom tournent sur Forever** : EllesmereUI 9.2.1 y charge unit frames, nameplates, raid frames, barres d'action, minimap, chat, bags, avec un toc multi-interface incluant 16001. Ce point était douteux le matin, il ne l'est plus.
- **ElvUI ne se charge pas sur Forever** : aucun `_Camelot.toc`, aucun toc nu. Le paquet local (`_classic_era_`, v13.94) vise `## Interface: 110107`, avant Midnight. Tukui n'a rien annoncé. La compatibilité ElvUI se code maintenant et se valide en jeu le jour où un ElvUI se charge.
- Natifs Blizzard disponibles : Edit Mode (`C_EditMode`), Cooldown Manager (`CooldownViewerSettings`, `C_CooldownViewer`), damage meter (`C_DamageMeter`, événements `DAMAGE_METER_*`). `/fui diag` les liste présents.
- Cooldown Manager : EllesmereUI ne fait que lire le gestionnaire natif (`GetLayoutManager`, `GetActiveLayoutID`, `GetActiveLayout`, `GetDataProvider():GetDisplayData()`). Aucune API de sérialisation observée. Sortie de `/fui diag` (ligne « Cooldown Manager ») encore attendue pour trancher.
- Menace : `UnitThreatSituation` appelé sans garde par EllesmereUI. Ligne « Menace » de `/fui diag` attendue.
- Persistance : EllesmereUI met ses SavedVariables à nil au logout sur Forever. ForeverUI a une persistance validée en jeu via `g_addonCategoriesCollapsed["ForeverUI"]`. Avantage concret à conserver.
- Concurrence réelle sur Forever : EllesmereUI (suite complète), Plater, Platynator, BetterBlizzPlates, BetterBlizzFrames, DBM, BigWigs. NaowhUI n'existe pas sur Forever.

## 3. Ce qu'il faut battre

La page EllesmereUI donne la liste : « every element is built from the ground up », éditeur visuel « Unlock Mode » (déplacer, ancrer à n'importe quoi, snap, égaliser largeur et hauteur, alignement pixel), modulaire, performance CPU, reskin Blizzard, et les modules : Action Bars, Unit Frames, Nameplates, Party/Raid, Cooldown Manager, Resource Bars, AuraBuff Reminders, Blizz reskins, Cursor, QoL, Minimap, Friends, Chat, Quest Tracker, Damage Meter, Bags, Data Bars.

Là où ForeverUI peut être meilleur :

1. Persistance qui marche sur Forever.
2. Français natif, enUS complet.
3. Un seul addon, un seul toc, zéro dépendance.
4. Installation en un clic qui donne un résultat fini : disposition, Cooldown Manager, damage meter natif, CVars, thème.
5. Cadres pensés pour Forever dès le départ : pas de spés, pas de M+, gardes valeurs secrètes partout, pas de code mort retail.

## 4. Ordre de bataille (validé)

Chaque étape est livrable et publiable seule.

1. **Socle** : pixel perfect, système de movers (déverrouillage ForeverUI), médias (police, textures plates, bordures 1 px, backdrop), cession à ElvUI. Plan : `docs/superpowers/plans/2026-09-20-etape-1-socle.md`.
2. **Unit frames** : joueur, cible, cible de la cible, focus, familier. Santé, puissance, cast bar, auras, indicateurs (combat, leader, rôle, repos), couleurs classe et réaction, formats de texte, gardes valeurs secrètes.
3. **Nameplates** propres : santé, cast bar, nom, niveau, surbrillance cible, icônes de quête, débuffs du joueur, couleur de menace si l'API répond.
4. **Party/raid frames** : grille, rôle, dispel, agro, portée, clic-cible.
5. **Barres d'action** propres : boutons, pages, keybinds, visibilité par état, avec les contournements de taint observés sur Forever.
6. **Minimap, chat, data bars, reskin Blizzard étendu, quest tracker.** TopBar devient une data bar du socle.
7. **Installation en un clic v2** : preset de disposition construit par code sur les movers ForeverUI (plus besoin d'Edit Mode pour nos cadres), Cooldown Manager garni, damage meter natif placé, CVars.
8. **Profils** : export, import, presets par rôle.

Reportés, non planifiés : boss mods, timer M+, WeakAuras-like, damage meter maison (le natif suffit), bags.

## 5. Existant conservé et rebranché

Douze modules v1.2.0 : TopBar, Automation, Reminders, Alerts, Nameplates, Frames, CoTank, GroupFinder, Cursor, Gear, Skin, Interface. Config : Widgets, Options, FirstRun. Persistance `g_addonCategoriesCollapsed`, miroir CVar, profils, locale.

- Nameplates et Frames actuels (tweaks sur cadres Blizzard) restent tels quels jusqu'aux étapes 2 et 3, puis deviennent le mode « cadres Blizzard » de ces modules, ou disparaissent si le mode cadres propres les couvre entièrement. Décision à l'étape concernée.
- `NS.AnchorMixin` (Core/Core.lua) est remplacé par le système de movers de l'étape 1 ; TopBar, CoTank, Alerts, Reminders migrent en gardant leurs positions sauvées (`db.anchors`).
- Preset Edit Mode et Cooldown Manager de FirstRun : conservés, utiles tant que nos cadres propres n'existent pas. `NS.PRESET_LAYOUTS` reste à remplir (chaîne exportée par le user, ou construction par code).

## 6. Toujours attendu du user

- `/reload` puis `/fui diag`, coller les lignes « Edit Mode », « Cooldown Manager », « Menace ».
- Le jour où un ElvUI se charge sur Forever : test de coexistence.

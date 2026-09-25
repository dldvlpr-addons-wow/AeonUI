# ForeverUI — conception v1

Date : 2026-09-19. Point de départ : NaowhUI 20260907.01 (analyse, pas de copie de code ni de médias).

## Contexte

WoW Forever 1.60.1 = contenu Classic sur moteur 12.x (Interface `16001`, nom de code `Camelot`).
Contraintes du moteur :

- `COMBAT_LOG_EVENT_UNFILTERED` interdit aux addons (le sonder déclenche ADDON_ACTION_FORBIDDEN).
- En combat, beaucoup de valeurs (auras, incantations hostiles, dégâts) sont **secrètes** :
  affichables, ni comparables ni additionnables. `issecretvalue(v)` permet de le détecter.
- Les frames sécurisées (boutons d'action, `SecureActionButtonTemplate`) ne se créent
  ni ne se modifient en combat.

NaowhUI ne tourne pas sur ce client (pas de `16001`) et son cœur est un installeur de profils
pour des addons tiers absents ou cassés ici (ElvUI, Plater, Details, WeakAuras, EllesmereUI).
ForeverUI en reprend l'**intention** (UI soignée + confort) sous forme d'addon autonome.

## Objectifs

1. Un seul dossier `ForeverUI/`, un seul `.toc`, **aucune dépendance** (ni Ace, ni LibStub requis).
2. Quatre modules activables un par un : Barre du haut, Confort automatique, Rappels, Habillage.
3. Publiable (CurseForge/Wago) : GPL-3.0-or-later, **aucun média tiers**. Polices du jeu
   (+ celles de LibSharedMedia si un autre addon l'embarque), sons via `SOUNDKIT`.
4. Testable hors du jeu : suite headless Lua 5.1 sur le mock de KickAlert.

Non-objectifs v1 : cadres d'unité, barres d'action, minimap, chat, profils multiples,
autres clients que Forever, locales autres que enUS/frFR.

## Architecture

```
ForeverUI/
  ForeverUI.toc            ## Interface: 16001 — SavedVariables: ForeverUIDB
  Locale/enUS.lua frFR.lua Locale.lua
  Core/Compat.lua          seul fichier qui touche aux API variables (repris de KickAlert)
  Core/Core.lua            espace de noms, bus interne, file hors combat, slash /fui
  Core/Database.lua        défauts, fusion, migrations (db.version)
  Core/Modules.lua         registre de modules
  Core/Media.lua           polices, sons, couleurs du thème
  Modules/TopBar.lua Automation.lua Reminders.lua Skin.lua
  Config/Options.lua       page Options > AddOns > ForeverUI
  Config/FirstRun.lua      fenêtre de premier lancement
  tests/                   wow_mock.lua, run_tests.lua, run.sh
```

Ordre de chargement = ordre du `.toc` (Locale → Core → Modules → Config).

### Registre de modules

```lua
NS.Modules:Register("topbar", {
    title = L.TOPBAR_TITLE, description = L.TOPBAR_DESC,
    defaults = { enabled = true, ... },   -- fusionné dans ForeverUIDB.modules.topbar
    OnEnable = function(self, db) end,    -- crée/affiche, enregistre les events
    OnDisable = function(self, db) end,   -- cache, désenregistre, restaure ce qui a été modifié
    OnRefresh = function(self, db) end,   -- un réglage a changé
    needsReload = false,                  -- true : le toggle affiche « nécessite /reload »
})
```

- `Modules:SetEnabled(name, bool)` : met à jour la DB puis appelle OnEnable/OnDisable.
- Si le joueur est en combat et que le module touche à des frames sécurisées
  (`secure = true`), l'appel part dans la **file hors combat** (`NS:RunOutOfCombat(fn)`)
  exécutée à `PLAYER_REGEN_ENABLED`, et un message le signale.
- Toute erreur dans un callback de module est capturée (`xpcall`) et affichée une fois :
  un module cassé ne casse pas les autres.

### Base de données

```lua
ForeverUIDB = {
  version = 1,
  locale = "auto",
  firstRunDone = false,
  modules = { topbar = {...}, automation = {...}, reminders = {...}, skin = {...} },
}
```

Fusion récursive des défauts (les valeurs existantes gagnent). `Database:Migrate()` applique
les migrations numérotées. Pas de profils en v1 (compte entier).

## Modules

### 1. Barre du haut (`topbar`)

Bande pleine largeur en haut de l'écran, hauteur 20 px, fond sombre semi-transparent.

| Élément | Affichage | Clic |
|---|---|---|
| Amis | `Amis 3` (WoW + Battle.net en ligne), infobulle = liste | Ouvre la liste d'amis |
| Guilde | `Guilde 12`, infobulle = membres en ligne colorés par classe | Ouvre la guilde |
| Heure | heure locale (ou serveur, réglable), 24 h | Ouvre le calendrier/horloge si dispo |
| Or | or du personnage | — |
| Durabilité | `Dura 87 %`, rouge sous 20 % | Ouvre la fiche personnage |
| Sacs | places libres | Ouvre les sacs |
| Perf | `60 fps · 45 ms` | — |
| Foyer | nom de la destination + temps de recharge | **Utilise la pierre de foyer** (bouton sécurisé `type=item`) |

- Mise à jour sur événements (`FRIENDLIST_UPDATE`, `BN_FRIEND_INFO_CHANGED`, `GUILD_ROSTER_UPDATE`,
  `PLAYER_MONEY`, `UPDATE_INVENTORY_DURABILITY`, `BAG_UPDATE_DELAYED`) ; horloge et perf via un
  ticker 1 s. Aucune de ces valeurs n'est secrète.
- Le bouton foyer est créé hors combat au premier enable ; en combat il reste cliquable mais
  n'est jamais modifié.
- Réglages : éléments affichés (case par élément), heure locale/serveur, opacité du fond.

### 2. Confort automatique (`automation`)

| Fonction | Défaut | Détail |
|---|---|---|
| Réparation auto | oui | À `MERCHANT_SHOW` si `CanMerchantRepair()`. Banque de guilde d'abord si autorisé (réglage), sinon or perso. Message : coût et source. |
| Vente des gris | oui | Objets de qualité Médiocre avec prix de vente > 0. Par lots de 10 avec 0,2 s d'écart (évite « objet occupé »). Message : total gagné. S'arrête si le marchand se ferme. |
| Maintien pour libérer l'esprit | oui, instances seulement | Couvre le bouton « Libérer l'esprit » ; maintenir ALT 1 s pour le libérer. Repris du principe NaowhUI (réécrit). |
| Invitations | non | Accepte les invitations de groupe venant d'amis, de Battle.net ou de la guilde. Jamais d'un inconnu. |
| Suppression rapide | oui | Pré-remplit le mot de confirmation dans la fenêtre de suppression d'objet. |

### 3. Rappels (`reminders`)

Hors combat uniquement (en combat les auras peuvent être secrètes, et un rappel en plein
combat est inutile). Une pile de lignes centrée en haut d'écran, déplaçable, avec un son
à l'apparition d'une ligne (réglable, coupable).

Rappels intégrés, chacun activable :

- **Buff de classe manquant** : seulement si le joueur connaît le sort.
  Mage : Armure de givre/glace/mage. Démoniste : Peau/Armure démoniaque. Prêtre : Feu intérieur.
  Druide : Marque du fauve. Chasseur : un Aspect. Paladin : une aura (ou une bénédiction sur soi).
  Guerrier : Cri de guerre en groupe. Voleur : **poison** sur les armes. Chaman : **arme enchantée**.
- **Durabilité faible** : sous un seuil (défaut 20 %).
- **Sacs pleins** : 0 place libre.
- **Camouflage** : voleur/druide félin, en instance, hors combat, non camouflé depuis 3 s. Défaut : non.

Évalué sur événements (`UNIT_AURA` joueur, `UPDATE_SHAPESHIFT_FORM`, `PLAYER_REGEN_ENABLED`,
`UNIT_INVENTORY_CHANGED`, `BAG_UPDATE_DELAYED`, `UPDATE_INVENTORY_DURABILITY`,
`ZONE_CHANGED_NEW_AREA`, `GROUP_ROSTER_UPDATE`). Les recherches d'aura se font par **nom**
(les rangs Classic ont un id par rang) et ignorent toute valeur secrète.

### 4. Habillage (`skin`)

- **Infobulles sombres** : fond et bordure de GameTooltip recolorés, bordure couleur de classe
  pour les joueurs, nom coloré par classe. Couleurs d'origine mémorisées et restaurées au disable.
- **Masquer les infobulles d'unité en combat** : défaut non.
- **Flèches de cible** : deux flèches de part et d'autre de la barre de nom de la cible,
  couleur réglable. Suivent `PLAYER_TARGET_CHANGED` / `NAME_PLATE_UNIT_ADDED/REMOVED`.
- **Police de ForeverUI** : une police pour tous les textes de l'addon (liste des polices du jeu
  + LibSharedMedia si présent), et une taille.
- **Thème** : couleur d'accent unique (défaut bleu Forever `#3FA9F5`) utilisée par la barre,
  les rappels et la page d'options.

## Options et premier lancement

- Page native **Options > AddOns > ForeverUI**, une section par module : titre, phrase
  d'explication, case « Activer », puis ses réglages. Libellés textuels explicites.
- `/fui` ouvre la page. `/fui reset` remet les défauts. `/fui unlock|lock` déplace les rappels.
  `/fui status` liste les modules et leur état.
- **Premier lancement** (`firstRunDone == false`) : une fenêtre unique avec les 4 modules
  cochables et leur description, bouton « Terminer ». Réouvrable par `/fui setup`.

## Erreurs et robustesse

- Tout appel d'API absent passe par `Compat` (feature-detection), jamais d'erreur Lua si une API manque.
- `issecretvalue` testé avant toute comparaison sur une valeur qui peut l'être.
- Rien de sécurisé modifié en combat : file hors combat.
- Chaque module enveloppé dans `xpcall` ; erreur affichée une fois avec le nom du module.

## Tests

`tests/run.sh` : syntaxe de tous les `.lua`, suite headless, cohérence `.toc` ↔ fichiers.
Suite headless (mock KickAlert complété) :
- défauts/migrations de la DB ;
- enable/disable de chaque module sans erreur, et restauration de l'état (skin) ;
- file hors combat (un enable en combat est différé puis appliqué à la sortie) ;
- vente des gris : ne vend que les gris avec valeur, par lots, s'arrête à la fermeture ;
- réparation : guilde puis perso selon réglages ;
- invitations : ami accepté, inconnu refusé ;
- rappels : buff manquant détecté seulement si sort connu, rien en combat, valeur secrète ignorée ;
- toutes les clés enUS présentes en frFR.

Vérification en jeu : checklist manuelle dans le README (le mock ne remplace pas le client).

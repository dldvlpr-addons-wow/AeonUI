# ForeverUI étape 4 — cadres de groupe et de raid (brouillon, à valider)

> Cadrage : section 4 point 4. Socle : `NS.UnitFrameElements` (étapes 2 et 3), movers, `NS.HideBlizzardFrame`. À relire par le user avant de coder.

**Goal :** remplacer `PartyFrame` et `CompactRaidFrameContainer` par des grilles ForeverUI : santé, nom court, rôle (LFG), chef, dispel (bordure à la couleur du type quand dissipable par toi), agro (bordure rouge sur menace 3), portée (alpha 0,4 hors portée), clic-cible et menus via boutons sécurisés. Version 1.6.0.

**Architecture :** module `groupframes` (`secure = true`, `yieldsTo = { "ElvUI" }`). Deux en-têtes `SecureGroupHeaderTemplate` (groupe : `showParty`, `showPlayer`, `showSolo` optionnel ; raid : `showRaid`, `groupBy = "GROUP"`, `groupingOrder = "1,2,3,4,5,6,7,8"`, `maxColumns`, `unitsPerColumn`, `columnSpacing`, `columnAnchorPoint`). Attribut `initialConfigFunction` (snippet restreint) : taille, `RegisterUnitWatch` implicite par l'en-tête, `*type1 target`, `*type2 togglemenu`. Chaque bouton reçoit ses éléments à la première apparition via `OnAttributeChanged("unit")` (hors combat : l'en-tête ne crée des boutons qu'hors combat). Visibilité par `RegisterStateDriver(header, "visibility", "[group:raid] show; hide")` et `[group:party,nogroup:raid] show; hide`. Un mover par en-tête (`uf_party`, `uf_raid`) : le calque prend la taille de l'en-tête.

Éléments par bouton : `health` (couleur classe), `name` (tronqué à `nameLength`), `power` optionnel (soigneurs), `roleIcon` (`UnitGroupRolesAssigned`, `GetPartyAssignment`), `leader`, `raidIcon`, `dispel` (bordure : `NS.GetDebuff` + `DebuffTypeColor`, seulement si non secret et si la classe du joueur dissipe ce type : table Classic par classe), `aggro` (`UnitThreatSituation(unit)` = 3), `range` (`UnitInRange(unit)` toutes les 0,25 s, alpha).

Réglages : largeur, hauteur, espacement, colonnes, tri (groupe/classe/rôle), afficher joueur en groupe, nom (longueur), puissance, rôles, dispel, agro, portée et alpha, seuil raid pour passer en « raid » (5/10/40), orientation (horizontal/vertical).

Masquage Blizzard : `PartyFrame` (Midnight) et `CompactRaidFrameContainer` + `CompactRaidFrameManager` via `NS.HideBlizzardFrame`, hors combat. Le module `frames` (noms de raid colorés) devient redondant quand `groupframes` est actif : note dans ses options, retrait envisagé plus tard.

Tests : mock `SecureGroupHeaderTemplate` (crée un bouton par `Mock.units.partyN/raidN`, appelle `initialConfigFunction` simulé et `OnAttributeChanged`), `UnitInRange`, `GetPartyAssignment`, `UnitGroupRolesAssigned` (déjà là). Vérifier : boutons créés hors combat seulement ; passage groupe → raid ; dispel colore la bordure pour un type dissipable et pas pour un autre ; hors portée alpha ; ElvUI cède.

Risques à trancher en jeu : `SecureGroupHeaderTemplate` sur Forever (EllesmereUI en a un module « Raid Frames », donc présent), taint du `CompactRaidFrameManager` masqué (préférer `SetAlpha(0)` + `UnregisterAllEvents` si erreurs), `UnitInRange` sur contenu Classic.

# ForeverUI étape 15 : chat et butin

> Analyse : `docs/superpowers/specs/2026-09-22-analyse-elvui-15-26.md`, feuille de route étape 15.
> Lancée par le user le 2026-09-22 (« go »). Codé sans validation en jeu. Version 1.15.0.
> Mécanismes du chat et du butin d'ElvUI, aucun code repris.

**Goal :** historique du chat conservé au /reload, mots-clés avec son, anti-spam tolérant,
fenêtre de butin et barres de jets.

## Livré

- `Modules/Chat.lua` :
  - Historique : l'enrobage d'`AddMessage` mémorise chaque ligne finale (texte, couleur) par personnage et par fenêtre dans `NS.global.chatHistory` (tableau numérique : persisté par la table hôte, jamais dans le miroir CVar ; journal de combat et lignes à code BNet `|K` exclus), borné à `historyLines`. Rejeu une fois par session à l'activation, entre deux séparateurs, sans être remémorisé. Bouton « Effacer l'historique ». Lignes secrètes ignorées.
  - Filtre de messages (`ChatFrame_AddMessageEventFilter`, repli `ChatFrameUtil`) : décision prise une fois par `lineID` et rejouée pour chaque fenêtre.
  - Mots-clés : liste séparée par des virgules, nom du personnage en option. Surlignage orange, sauf message à liens (compte quand même). Son `3081` au plus toutes les 5 s. Ses propres messages ignorés.
  - Anti-spam (coupé par défaut) : dire, crier, canaux. Clé = auteur + texte normalisé (sans liens ni couleurs, minuscules, sans ponctuation ni espaces, caractères UTF-8 répétés réduits). Masqué si vu dans `spamWindow` secondes. Purge au-delà de 500 clés.
- `Modules/Loot.lua` : module « Butin » (coupé par défaut, cède à ElvUI).
  - Fenêtre au thème, sous le curseur ou sur le mover `loot` : icône, quantité, nom et bordure en couleur de qualité (dorée pour un objet de quête). Clic : `LootSlot` et champs `LootFrame.selected*` du maître du butin. Échap ou croix : `CloseLoot`. Événements de `LootFrame` retirés tant que le module est actif, rendus à la coupure.
  - Barres de jets sur le mover `lootroll` : `START_LOOT_ROLL` retiré à `UIParent`, barre par jet (icône avec infobulle, nom, temps restant par `GetLootRollTimeLeft`), boutons besoin, cupidité, désenchanter, passer ; un choix refusé est grisé. `CANCEL_LOOT_ROLL` retire la barre. Confirmation d'objet lié laissée à Blizzard.

## Tests

`tests/test_chat_loot.lua` (5 tests) : historique (borne, secret, rejeu unique, effacement), normalisation et mots-clés (surlignage, lien, son limité, nom, secret), anti-spam (même ligne sur deux fenêtres, variante, chuchotement, fenêtre écoulée), fenêtre de butin (Blizzard coupé puis rendu, clic, emplacement vidé, Échap), barres de jets (choix grisés, jet, annulation, icône secrète). `test_config` : 24 sous-pages.

## Risques en jeu

- Signature du filtre de chat et position du `lineID` (11e argument) à confirmer sur Forever.
- `LootFrame` retail (ScrollBox) : les champs `selected*` du maître du butin peuvent ne plus servir.
- `GetLootRollItemInfo` : ordre des retours à confirmer (désenchantement surtout).
- Majuscules accentuées non repliées par l'anti-spam et les mots-clés.

Relecture (agent relecteur) : barre de jet retirée au clic (jet perdu si la confirmation d'objet lié est refusée ; désormais retirée par `CANCEL_LOOT_ROLL`), clic modifié qui ramassait au lieu de lier, historique partagé entre personnages, butin laissé ouvert sans fenêtre (rien d'affichable, fenêtre décochée, module coupé : `CloseLoot` désormais), fenêtre replacée au curseur à chaque `LOOT_SLOT_CHANGED`, mover `loot` absent avant le premier butin, `START_LOOT_ROLL` rendu à UIParent même si un autre addon l'avait retiré, journal de combat et codes BNet mémorisés : corrigés.

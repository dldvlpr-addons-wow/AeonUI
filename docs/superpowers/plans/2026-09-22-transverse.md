# ForeverUI transverse : recherche, profil au groupe, movers

> Analyse : `docs/superpowers/specs/2026-09-22-analyse-elvui-15-26.md`, point « Transverse ».
> Lancé par le user le 2026-09-22 (« go »). Codé sans validation en jeu. Version 1.18.0.

**Goal :** recherche dans les options, envoi de profil au groupe par messages d'addon, coordonnées et molette sur les movers.

## Livré

- **Recherche** (`Config/Widgets.lua`, `Config/Options.lua`) : chaque layout garde ses libellés (`Layout:Label`, appelé par Title, Check, Slider, Cycle, Color, Button, EditBox). `Options.Search(texte)` cherche, accents ignorés (`Modules.SortKey`), dans le titre, la description puis les libellés de chaque sous-page ; 8 résultats au plus, 2 lettres minimum. Case en tête de la page principale, résultats dans une liste flottante ; un clic ouvre la sous-page (`Options.OpenModule`, catégorie gardée à l'inscription).
- **Profil au groupe** (`Core/ProfileShare.lua`, bouton sous Profils) : chaîne d'export découpée en morceaux « n/total: » de 240 caractères, préfixe `ForeverUI`, canal RAID ou PARTY, un morceau toutes les 0,25 s, morceau refusé par la limite de débit renvoyé. Réception : membres du groupe seulement, soi ignoré, valeurs secrètes ignorées, 400 morceaux au plus, envoi abandonné oublié après 30 s, chaîne validée par `Deserialize`, puis confirmation `StaticPopup` avant `NS:ImportProfile` (remplace le profil actif).
- **Movers** (`Core/Movers.lua`) : molette sur un calque (1 px vertical, Maj horizontal, Ctrl 10 px), refusée en combat pour un cadre protégé. Case X / Y du mover sélectionné en haut de l'écran, Entrée applique (`Movers:ApplyCoords`), valeurs relues à chaque déplacement ; cachée au verrouillage et à l'entrée en combat.

## Tests

`tests/test_transverse.lua` (3 tests) : recherche (libellé, titre, une lettre, ouverture), envoi (hors groupe, débit, canal), réception (désordre, hors groupe, chaîne invalide, secret), molette et coordonnées.

## Risques en jeu

- Profil complet ≈ 27 Ko, soit ≈ 114 messages : avec la limite de débit du client (environ un message par seconde après une rafale), l'envoi peut durer deux minutes.
- Messages d'addon restreints en instance sur le moteur 12.x : envoi possible seulement hors instance.

Relecture (agent relecteur) : envoi rejoué sans fin sur tout code d'échec (désormais seuls `AddonMessageThrottle` et `ChannelThrottle` sont rejoués, 30 s au plus ; faux Classic rejoué seulement si le groupe n'a pas changé), second profil reçu pendant la question qui n'importait rien (profil passé en `data`), envois abandonnés gardés en mémoire (purge à chaque réception), calque qui prenait le clavier en combat après un clic ou la molette (touches avalées), coordonnées NaN ou hors écran acceptées, arrondi entier qui décalait l'autre axe d'un pixel (une décimale) : corrigés.

Point de sécurité traité à la demande du user (« règle le point de sécurité ») : `Database:ImportProfile` (import collé ou reçu du groupe) retire les nombres non finis, puis `Database.Sanitize` ramène chaque réglage chiffré dans les bornes de son curseur (`Database.bounds`, inscrites par `ModuleOptions:Slider`, plus taille de police, échelle, grille, seuil de raid), borne les couleurs entre 0 et 1, retire les ancres au-delà de 10 000, et garde les réglages sensibles du joueur (réparation, banque de guilde, vente, invitations, quêtes, suppression rapide). Test : `tests/test_transverse.lua`, `tests/test_setup.lua` adapté.

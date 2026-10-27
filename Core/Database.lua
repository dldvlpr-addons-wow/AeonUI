-- Core/Database.lua
-- MuscaUIDB (compte entier) :
--   version, locale, firstRunDone
--   profiles[nom] = { theme, anchors, modules[module] }   -- réglages d'interface
--   profileKeys["Perso - Royaume"] = nom du profil          -- absent = "Default"
--   specProfiles["Perso - Royaume"][index de spé] = nom      -- prime sur profileKeys
--   lastSpec["Perso - Royaume"] = index de spé                -- la spé n'est pas lisible dès la connexion
--   contextProfiles["Perso - Royaume"][contexte] = nom       -- donjon, raid, pvp, world : prime sur la spé
--   profileVariants[nom] = { parent = nom, diff }             -- profil dérivé : parent + écart (jamais exporté)
--   cvarBackup[cvar] = valeur d'origine, avant que MuscaUI ne la change
--   profileBackup = { reason, version, time, profiles, defaults } : profils d'avant la dernière migration,
--     import, remise à zéro ou restauration (un seul emplacement, ni exporté ni recopié dans le miroir CVar ;
--     réduite aux écarts aux défauts, joints en chaîne d'export, sauf celle d'une migration, complète)
--   migrationSnapshot : table entière d'avant une migration en échec, rejouée à la session suivante
-- NS.global pointe sur MuscaUIDB, NS.db sur le profil actif.
-- Les défauts sont fusionnés sans jamais écraser une valeur existante ; les migrations
-- sont numérotées et jouées une fois.
local _, NS = ...

local Database = {}
NS.Database = Database

Database.VERSION = 10
Database.DEFAULT_PROFILE = "Default"

Database.GLOBAL_DEFAULTS = {
    version = Database.VERSION,
    locale = "auto",          -- "auto" suit le client, sinon un code ("frFR", ...)
    firstRunDone = false,
    profiles = {},
    profileKeys = {},
    specProfiles = {},
    lastSpec = {},
    contextProfiles = {},
    profileVariants = {},     -- [nom] = { parent, diff } : voir Database:SyncVariants
    goldLedger = {},          -- [« Perso - Royaume »] = or en cuivre, relevé à la connexion et à chaque gain
    flightTimes = {},         -- [« départ:arrivée » en nodeID] = durée de vol lissée, en secondes
    -- flightInProgress (hors défauts : MergeDefaults remplacerait la table sauvegardée par le défaut) :
    -- vol en cours { from, to, name, start = GetServerTime }, repris après /reload.
    profileHotkeys = {},      -- [nom de profil] = touche qui bascule sur ce profil
    cvarBackup = {},
    chatClassColors = {},     -- [personnage] = { [chatType] = couleur de classe d'origine }
    tipsSeen = {},            -- [clé] = true : bulle d'aide de la fenêtre d'options déjà vue
    optionsMode = "simple",   -- fenêtre d'options : "simple" masque les réglages avancés, "advanced" les montre
    questWatches = {},        -- [personnage] = { removed = { [questID] = true }, auto = { [questID] = true } } : suivi de quêtes
}

Database.PROFILE_DEFAULTS = {
    theme = {
        font = "Fonts\\ARIALN.TTF",
        fontSize = 12,
        fontOutline = "",         -- "", "OUTLINE", "THICKOUTLINE"
        fontAllGameText = false,  -- police du thème sur tout le texte du jeu (après /reload)
        accent = { r = 0.25, g = 0.66, b = 0.96 },
        backdrop = { r = 0.05, g = 0.06, b = 0.08, a = 0.9 },
        border = { r = 0, g = 0, b = 0, a = 1 },
        borderSize = 1,           -- épaisseur des bordures en pixels physiques (1 à 4)
        statusbar = "",           -- nom LibSharedMedia, sinon texture plate
        pixelPerfect = true,
        uiScale = 1,              -- multiplicateur d'échelle (0,5 à 1,5) au-dessus de la base
        optionsScale = 1,         -- taille de la fenêtre d'options (0,8 à 1,5), en plus de uiScale
        grid = 0,                 -- 0, 16 ou 32 px, visible en mode déverrouillé
        snap = true,              -- aimant du mode déverrouillé (Maj le coupe le temps d'un glisser)
        moverCustom = false,      -- vrai : couleur du mode déverrouillé choisie (sinon l'accent)
        moverColor = { r = 1, g = 0.82, b = 0 },
        glowThickness = 2,        -- épaisseur des traits de la lueur « pixel », en pixels (1 à 4)
        glowSpeed = 1,            -- vitesse des lueurs animées (pixel, autocast), 0,5 à 2
        accentPreset = "custom",  -- "custom" (accent ci-dessus), "class", "faction" (lus pour chaque personnage)
        darkMode = false,         -- palette sombre partagée des barres de vie (Media:SetHealthColor)
        moduleMedia = {},         -- [module] = { font, statusbar } : exception au thème, absent = hérité
        classColors = {},         -- [CLASSE] = { r, g, b } : remplace RAID_CLASS_COLORS sur nos cadres, absent = Blizzard
        powerColors = {},         -- [JETON] = { r, g, b } : remplace PowerBarColor (MANA, RAGE...), absent = Blizzard
    },
    anchors = {},
    -- Listes d'identifiants de sorts partagées par tous les filtres d'auras (« 1234, 5678 »),
    -- tri des débuffs (boss, contrôle, dissipable) et lueur des contrôles (Glow.STYLES ou "none").
    auraLists = { whitelist = "", blacklist = "", prioritize = true, ccGlow = "pixel" },
    modules = {},
}

--- `report` (Database.NewImportReport, facultatif) : valeurs de mauvais type remplacées, dans `clamped`.
function Database.MergeDefaults(defaults, target, report)
    for key, value in pairs(defaults) do
        local wrongType = target[key] ~= nil and type(target[key]) ~= type(value)
        if wrongType and report then report.clamped = report.clamped + 1 end
        if type(value) == "table" then
            if type(target[key]) ~= "table" then target[key] = {} end
            Database.MergeDefaults(value, target[key], report)
        elseif target[key] == nil or wrongType then
            -- Type différent : scalaire venu d'une chaîne importée, le défaut le remplace.
            target[key] = value
        end
    end
    return target
end

function Database.DeepCopy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for k, v in pairs(value) do copy[k] = Database.DeepCopy(v) end
    return copy
end

local RENAMED_MODULES = { quickdraw = "radialmenu", shifter = "movablewindows" }

--- Réglages d'un module renommé repris sous son nouveau nom. Joué par la migration v7 et à
-- l'import : les chaînes d'avant la v10 ne portent pas de version.
function Database.RenameModules(profile)
    if type(profile) ~= "table" then return end
    local media = type(profile.theme) == "table" and type(profile.theme.moduleMedia) == "table"
        and profile.theme.moduleMedia or {}
    for old, new in pairs(RENAMED_MODULES) do
        if type(profile.modules) == "table" and profile.modules[new] == nil then
            profile.modules[new], profile.modules[old] = profile.modules[old], nil
        end
        if media[new] == nil then media[new], media[old] = media[old], nil end
    end
end

-- [version cible] = function(db)
Database.MIGRATIONS = {
    -- v1 -> v2 : réglages à plat -> profil "Default".
    [2] = function(db)
        db.profiles = db.profiles or {}
        db.profiles[Database.DEFAULT_PROFILE] = {
            theme = db.theme, anchors = db.anchors, modules = db.modules,
        }
        db.theme, db.anchors, db.modules = nil, nil, nil
    end,
    -- v2 -> v3 : l'échelle pixel perfect (défaut true) changerait l'unité d'interface et
    -- déplacerait les positions déjà sauvées : les profils existants restent à false.
    [3] = function(db)
        for _, profile in pairs(db.profiles or {}) do
            profile.theme = profile.theme or {}
            if profile.theme.pixelPerfect == nil then profile.theme.pixelPerfect = false end
        end
    end,
    -- v3 -> v4 : visibilités propres à chaque module -> réglage commun (Core/Visibility).
    -- Tables partielles : MergeDefaults complète le reste.
    [4] = function(db)
        for _, profile in pairs(db.profiles or {}) do
            local modules = type(profile.modules) == "table" and profile.modules or {}
            local topbar = modules.topbar
            if type(topbar) == "table" and topbar.hideInCombat ~= nil then
                if topbar.hideInCombat == true then topbar.visibility = { combat = "no" } end
                topbar.hideInCombat = nil
            end
            local panels = type(modules.datapanels) == "table" and modules.datapanels.panels
            for _, panel in pairs(type(panels) == "table" and panels or {}) do
                if type(panel) == "table" and panel.hideInCombat ~= nil then
                    if panel.hideInCombat == true then panel.visibility = { combat = "no" } end
                    panel.hideInCombat = nil
                end
            end
            local resource = modules.resourcebars
            if type(resource) == "table" and type(resource.visibility) == "string" then
                resource.visibility = resource.visibility == "combat" and { match = "any", combat = "yes", target = "yes" } or nil
            end
            local swing = modules.swingtimer
            if type(swing) == "table" and swing.combatOnly ~= nil then
                swing.visibility = swing.combatOnly and { combat = "yes" } or { combat = "ignore" }
                swing.combatOnly = nil
            end
        end
    end,
    -- v4 -> v5 : habillage, cases darkPanels et skinWindows -> interrupteur et style par fenêtre.
    -- Fidèle à l'existant : panneaux sombres -> style par défaut sombre, sinon Blizzard ; l'ancienne
    -- case « au thème » ne couvrait que la fiche, l'inspection et les amis.
    [5] = function(db)
        for _, profile in pairs(db.profiles or {}) do
            local skin = type(profile.modules) == "table" and profile.modules.skin
            if type(skin) == "table" and (skin.darkPanels == true or skin.skinWindows == true) then
                skin.windowStyle = skin.darkPanels == true and "dark" or "blizzard"
                if skin.skinWindows == true then
                    skin.windowStyles = { CharacterFrame = "theme", InspectFrame = "theme", FriendsFrame = "theme" }
                end
                skin.skinWindows = true
            end
            if type(skin) == "table" then skin.darkPanels = nil end
        end
    end,
    -- v5 -> v6 : refonte des cadres de groupe. Une valeur restée à l'ancien défaut est effacée
    -- (MergeDefaults pose le nouveau) ; une taille modifiée vaut aussi pour le raid.
    [6] = function(db)
        local OLD = { width = 90, height = 36, spacing = 4, raidSortBy = "GROUP", nameLength = 8,
                      roleIconSize = 12, roleIconPosition = "TOPLEFT", roleShowDamager = true,
                      aggroStyle = "border", auraSize = 16 }
        for _, profile in pairs(db.profiles or {}) do
            local group = type(profile.modules) == "table" and profile.modules.groupframes
            if type(group) == "table" then
                if group.width ~= nil and group.width ~= OLD.width then group.raidWidth = group.width end
                if group.height ~= nil and group.height ~= OLD.height then group.raidHeight = group.height end
                for key, old in pairs(OLD) do
                    if group[key] == old then group[key] = nil end
                end
            end
        end
    end,
    -- v6 -> v7 : modules renommés, réglages et police propre suivent le nouveau nom.
    [7] = function(db)
        for _, profile in pairs(db.profiles or {}) do Database.RenameModules(profile) end
    end,
    -- v7 -> v8 : les plaques ont leurs propres listes d'auras ; jamais remplies, elles reprennent
    -- les listes communes.
    [8] = function(db)
        for _, profile in pairs(db.profiles or {}) do
            local common = type(profile.auraLists) == "table" and profile.auraLists
            local plates = type(profile.modules) == "table" and profile.modules.nameplateframes
            if common and type(plates) == "table" then
                local own = type(plates.auraLists) == "table" and plates.auraLists or {}
                if (own.whitelist or "") == "" and (own.blacklist or "") == "" then
                    plates.auraLists = { whitelist = common.whitelist or "", blacklist = common.blacklist or "" }
                end
            end
        end
    end,
    -- v8 -> v9 : horloge et zoom de la minimap sortent du décor. Décor Blizzard gardé : ils restent affichés.
    [9] = function(db)
        for _, profile in pairs(db.profiles or {}) do
            local minimap = type(profile.modules) == "table" and profile.modules.minimap
            if type(minimap) == "table" and minimap.hideDecor == false then
                if minimap.showClock == nil then minimap.showClock = true end
                if minimap.showZoom == nil then minimap.showZoom = true end
            end
        end
    end,
    -- v9 -> v10 : cadres de groupe. Les quatre coins deviennent les quatre premiers indicateurs ; une
    -- taille de raid modifiée vaut pour les paliers 10 et 25 ; le filtre unique coche ses groupes de débuffs.
    [10] = function(db)
        for _, profile in pairs(db.profiles or {}) do
            local group = type(profile.modules) == "table" and profile.modules.groupframes
            if type(group) == "table" then
                local old = group.indicators
                if type(old) == "table" then
                    local list = {}
                    for index, corner in ipairs({ "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }) do
                        list[index] = { spells = type(old[corner]) == "string" and old[corner] or "", point = corner }
                    end
                    group.indicators = list
                end
                local width, height, columns = group.raidWidth, group.raidHeight, group.raidColumns
                if (width ~= nil and width ~= 96) or (height ~= nil and height ~= 44)
                    or (columns ~= nil and columns ~= 8) then
                    local function Tier() return { width = width or 96, height = height or 44, columns = columns or 8 } end
                    group.raidTiers = { Tier(), Tier() }
                end
                local wanted = ({ important = { boss = true, dispellable = true }, dispellable = { dispellable = true },
                                  boss = { boss = true } })[group.auraFilter]
                if wanted then
                    group.debuffGroups = {}
                    for _, key in ipairs({ "control", "boss", "dispellable", "nonPlayer", "duration" }) do
                        group.debuffGroups[key] = { enabled = wanted[key] == true }
                    end
                end
            end
        end
    end,
}

-- Migrations en échec de la session : { "v3 : message" }, lues par /musca diag.
Database.migrationErrors = {}
-- true si une migration a échoué et que la table a été rendue telle qu'avant (message à la connexion).
Database.migrationRolledBack = false

--- Chaque migration sous pcall : une table abîmée ne doit pas empêcher l'addon de charger.
-- En échec, la table revient telle qu'avant la première migration et garde son ancienne
-- version : jamais de profil à moitié migré. La session tourne ensuite sur des profils remplis
-- des défauts actuels, qui fausseraient le rejeu (v3, v7) : les profils d'avant sont gardés
-- intacts dans `migrationSnapshot` et la session suivante les reprend une seule fois (le reste
-- de la table, relevés du compte compris, reste celui de la session). Second échec : profils de
-- la session gardés, profils intacts rangés dans la sauvegarde (/musca restore les migrera).
-- En succès, les profils d'avant deviennent la sauvegarde.
function Database.Migrate(db)
    local pending = db.migrationSnapshot
    db.migrationSnapshot = nil
    local replayed = type(pending) == "table" and type(pending.profiles) == "table"
    local sessionProfiles = db.profiles
    if replayed then
        db.profiles, db.version = pending.profiles, pending.version
    end
    local from = tonumber(db.version) or Database.VERSION
    if from >= Database.VERSION then
        db.version = Database.VERSION
        return
    end
    local snapshot = Database.DeepCopy(db)
    for version = from + 1, Database.VERSION do
        local migrate = Database.MIGRATIONS[version]
        if migrate then
            local ok, err = pcall(migrate, db)
            if not ok then
                Database.migrationErrors[#Database.migrationErrors + 1] = "v" .. version .. " : " .. tostring(err)
                -- Même table (MuscaUIDB, rangée par référence dans la table hôte) : vidée puis remplie.
                for key in pairs(db) do db[key] = nil end
                for key, value in pairs(snapshot) do db[key] = value end
                db.version = from
                if replayed then
                    db.profileBackup = { reason = "migration", version = from, time = time(), profiles = snapshot.profiles }
                    db.profiles = sessionProfiles
                elseif type(snapshot.profiles) == "table" then
                    db.migrationSnapshot = { version = from, profiles = Database.DeepCopy(snapshot.profiles) }
                end
                Database.migrationRolledBack = true
                return
            end
        end
    end
    db.version = Database.VERSION
    if type(snapshot.profiles) == "table" then
        db.profileBackup = { reason = "migration", version = from, time = time(), profiles = snapshot.profiles }
    end
end

-- Un point inconnu (profil importé) ferait lever SetPoint après ClearAllPoints : module cassé.
local POINTS = {
    TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true, RIGHT = true,
    BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}

local ANCHOR_LIMIT = 10000

--- Coordonnée utilisable : nombre fini (ni NaN ni infini), à moins de ANCHOR_LIMIT.
local function Coordinate(value)
    return type(value) == "number" and value == value and math.abs(value) <= ANCHOR_LIMIT
end

--- Retire `node[key]` s'il est présent et pas `valid` ; compte le retrait dans `report.clamped`.
local function Discard(node, key, valid, report)
    if node[key] == nil or valid then return end
    node[key] = nil
    if report then report.clamped = report.clamped + 1 end
end

--- Complète un profil avec les défauts du cœur et de chaque module enregistré.
-- `report` (facultatif) : valeurs de mauvais type remplacées et positions écartées.
function Database.FillProfile(profile, report)
    Database.MergeDefaults(Database.PROFILE_DEFAULTS, profile, report)
    for _, module in ipairs(NS.Modules:List()) do
        -- Un scalaire à la place d'une table (chaîne importée hostile) est écarté.
        if type(profile.modules[module.name]) ~= "table" then
            if profile.modules[module.name] ~= nil and report then report.clamped = report.clamped + 1 end
            profile.modules[module.name] = {}
        end
        Database.MergeDefaults(module.defaults, profile.modules[module.name], report)
    end
    -- Exceptions par module : chaînes seulement (chemin de police, nom de texture).
    for name, own in pairs(profile.theme.moduleMedia) do
        Discard(profile.theme.moduleMedia, name, type(own) == "table", report)
        if type(own) == "table" then
            Discard(own, "font", type(own.font) == "string", report)
            Discard(own, "statusbar", type(own.statusbar) == "string", report)
        end
    end
    for key, anchor in pairs(profile.anchors) do
        -- Coordonnée lointaine ou non finie : position écartée, comptée une seule fois.
        if type(anchor) ~= "table" or not POINTS[anchor.point] or not POINTS[anchor.relPoint]
            or not Coordinate(anchor.x) or not Coordinate(anchor.y) then
            profile.anchors[key] = nil
            if report then report.anchors = report.anchors + 1 end
        else
            -- Ancrage à un autre mover (Movers) : champs mal typés écartés un à un.
            Discard(anchor, "target", type(anchor.target) == "string", report)
            local f = anchor.fallback
            Discard(anchor, "fallback", type(f) == "table" and POINTS[f.point] and POINTS[f.relPoint]
                and Coordinate(f.x) and Coordinate(f.y), report)
            Discard(anchor, "edgeX", Coordinate(anchor.edgeX), report)
            Discard(anchor, "edgeY", Coordinate(anchor.edgeY), report)
            -- Écarts de taille bornés par Sanitize (import) ; NaN écarté ici.
            for _, field in ipairs({ "widthOffset", "heightOffset" }) do
                Discard(anchor, field, type(anchor[field]) == "number" and anchor[field] == anchor[field], report)
            end
            Discard(anchor, "matchWidth", type(anchor.matchWidth) == "boolean", report)
            Discard(anchor, "matchHeight", type(anchor.matchHeight) == "boolean", report)
            -- Point d'écran épinglé et coin gardé quand la taille change (Movers).
            Discard(anchor, "pin", POINTS[anchor.pin], report)
            Discard(anchor, "grow", POINTS[anchor.grow], report)
        end
    end
    return profile
end

--- Prépare la table sauvegardée et la rend (sans la brancher : voir Database:Attach). `saved` peut être nil (premier lancement).
function Database:Init(saved)
    local db = type(saved) == "table" and saved or {}
    if db.version ~= nil then self.Migrate(db) end
    self.MergeDefaults(self.GLOBAL_DEFAULTS, db)
    db.profiles[self.DEFAULT_PROFILE] = db.profiles[self.DEFAULT_PROFILE] or {}
    for _, profile in pairs(db.profiles) do self.FillProfile(profile) end
    return db
end

--- Branche la table sauvegardée comme table globale active.
function Database:Attach(db)
    self.global = db
    return db
end

function Database.CharacterKey()
    return (UnitName("player") or "?") .. " - " .. ((_G.GetRealmName and GetRealmName()) or "?")
end

--- Profil lié à la spé active (ou à la dernière connue), et cette spé ; nil sans lien.
function Database:SpecProfile()
    local char = self.CharacterKey()
    local map = self.global.specProfiles[char]
    if type(map) ~= "table" then return nil end
    local spec = NS.GetActiveSpec() or self.global.lastSpec[char]
    local name = spec and map[spec]
    if type(name) == "string" and self.global.profiles[name] then return name, spec end
    return nil
end

--- Contexte du joueur : "dungeon", "raid", "pvp" (champ de bataille, arène) ou "world".
function Database.Context()
    local _, instanceType = IsInInstance()
    if instanceType == "party" then return "dungeon" end
    if instanceType == "raid" then return "raid" end
    if instanceType == "pvp" or instanceType == "arena" then return "pvp" end
    return "world"
end

--- Profil lié au contexte courant, et ce contexte ; nil sans lien.
function Database:ContextProfile()
    local map = self.global.contextProfiles[self.CharacterKey()]
    if type(map) ~= "table" then return nil end
    local context = self.Context()
    local name = map[context]
    if type(name) == "string" and self.global.profiles[name] then return name, context end
    return nil
end

function Database:ActiveProfileName()
    local name = self:ContextProfile() or self:SpecProfile() or self.global.profileKeys[self.CharacterKey()]
    if name and self.global.profiles[name] then return name end
    return self.DEFAULT_PROFILE
end

--- Lie (ou délie, `name` nil) un profil à la clé `key` du personnage dans `root`.
local function SetLink(root, char, key, name)
    local map = root[char]
    if type(map) ~= "table" then
        map = {}
        root[char] = map
    end
    map[key] = name
    if next(map) == nil then root[char] = nil end
end

local function GetLink(root, char, key)
    local map = root[char]
    return type(map) == "table" and map[key] or nil
end

--- Lie (ou délie, `name` nil) un profil à la spé `spec` du personnage.
function Database:SetSpecProfile(spec, name)
    SetLink(self.global.specProfiles, self.CharacterKey(), spec, name)
end

function Database:GetSpecProfile(spec)
    return GetLink(self.global.specProfiles, self.CharacterKey(), spec)
end

--- Lie (ou délie) un profil au contexte `context` (voir Database.Context) du personnage.
function Database:SetContextProfile(context, name)
    SetLink(self.global.contextProfiles, self.CharacterKey(), context, name)
end

function Database:GetContextProfile(context)
    return GetLink(self.global.contextProfiles, self.CharacterKey(), context)
end

function Database:ActiveProfile()
    return self.global.profiles[self:ActiveProfileName()]
end

--- Profils existants, "Default" en premier puis par ordre alphabétique.
function Database:ListProfiles()
    local names = {}
    for name in pairs(self.global.profiles) do
        if name ~= self.DEFAULT_PROFILE then names[#names + 1] = name end
    end
    table.sort(names)
    table.insert(names, 1, self.DEFAULT_PROFILE)
    return names
end

--- Associe `name` au personnage ; le crée par copie de `copyFrom` (ou des défauts) s'il n'existe pas.
function Database:UseProfile(name, copyFrom)
    local profiles = self.global.profiles
    if not profiles[name] then
        local source = copyFrom and profiles[copyFrom]
        profiles[name] = self.FillProfile(source and self.DeepCopy(source) or {})
    end
    -- Contexte ou spé liés à un profil : le choix vaut pour ce lien.
    local _, context = self:ContextProfile()
    local _, spec = self:SpecProfile()
    if context then
        self:SetContextProfile(context, name)
    elseif spec then
        self:SetSpecProfile(spec, name)
    elseif name == self.DEFAULT_PROFILE then
        self.global.profileKeys[self.CharacterKey()] = nil
    else
        self.global.profileKeys[self.CharacterKey()] = name
    end
    return profiles[name]
end

--- Supprime un profil (jamais "Default"). Les personnages qui l'utilisaient reviennent à "Default".
function Database:DeleteProfile(name)
    if name == self.DEFAULT_PROFILE or not self.global.profiles[name] then return false end
    -- Variantes de ce profil : refaites sur sa dernière version, puis profils simples.
    self:SyncVariants(NS.db)
    local variants = self.global.profileVariants
    variants[name] = nil
    for variant, entry in pairs(variants) do
        if type(entry) == "table" and entry.parent == name then variants[variant] = nil end
    end
    self.global.profiles[name] = nil
    self.global.profileHotkeys[name] = nil
    for key, value in pairs(self.global.profileKeys) do
        if value == name then self.global.profileKeys[key] = nil end
    end
    for _, root in ipairs({ self.global.specProfiles, self.global.contextProfiles }) do
        for _, map in pairs(root) do
            if type(map) == "table" then
                for key, value in pairs(map) do
                    if value == name then map[key] = nil end
                end
            end
        end
    end
    return true
end

--- Nom de profil acceptable : texte non vide, sans espace autour, 48 caractères au plus, sans
-- « | » (codes d'échappement du chat : |T, |H).
function Database.ValidProfileName(name)
    if type(name) ~= "string" then return nil end
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" or #name > 48 or name:find("|", 1, true) then return nil end
    return name
end

--- Renomme un profil (jamais "Default", jamais vers un nom pris) ; personnages, spés et
-- raccourci suivent. Rend le nouveau nom, ou nil.
function Database:RenameProfile(old, new)
    new = self.ValidProfileName(new)
    local profiles = self.global.profiles
    if not new or old == self.DEFAULT_PROFILE or not profiles[old] or profiles[new] then return nil end
    profiles[new], profiles[old] = profiles[old], nil
    for key, value in pairs(self.global.profileKeys) do
        if value == old then self.global.profileKeys[key] = new end
    end
    for _, root in ipairs({ self.global.specProfiles, self.global.contextProfiles }) do
        for _, map in pairs(root) do
            if type(map) == "table" then
                for key, value in pairs(map) do
                    if value == old then map[key] = new end
                end
            end
        end
    end
    local hotkeys = self.global.profileHotkeys
    hotkeys[new], hotkeys[old] = hotkeys[old], nil
    local variants = self.global.profileVariants
    variants[new], variants[old] = variants[old], nil
    for _, entry in pairs(variants) do
        if type(entry) == "table" and entry.parent == old then entry.parent = new end
    end
    return new
end

--------------------------------------------------------------------------------
-- Sauvegarde des profils : prise avant ce qui remplace des réglages d'un bloc
--------------------------------------------------------------------------------

--- Copie de `value` sans les scalaires égaux à `defaults` ni les tables vides (recréés par
-- FillProfile au retour : Init pour le miroir, RestoreBackup pour la sauvegarde).
local function Prune(value, defaults)
    local out = {}
    for key, child in pairs(value) do
        local default
        if type(defaults) == "table" then default = defaults[key] end   -- pas de `and/or` : false est un défaut
        if type(child) == "table" then
            local pruned = Prune(child, default)
            if next(pruned) ~= nil then out[key] = pruned end
        elseif child ~= default then
            out[key] = child
        end
    end
    return out
end

--- Défauts d'un profil : cœur et modules. `mirror` : ceux du miroir, plus larges que ceux de
-- FillProfile (module.mirrorDefaults, entrées créées à la demande).
local function ProfileDefaults(mirror)
    local defaults = Database.DeepCopy(Database.PROFILE_DEFAULTS)
    for _, module in ipairs(NS.Modules:List()) do
        defaults.modules[module.name] = mirror and module.mirrorDefaults or module.defaults
    end
    return defaults
end

-- Borne de lecture des défauts joints à la sauvegarde : une donnée à nous, qui grossit à chaque
-- module ajouté. La borne des imports collés (PastedLimit, 32 000) ne vaut que pour une chaîne tierce.
Database.BACKUP_DEFAULTS_LIMIT = 96000

-- Défauts de la session en chaîne d'export, calculés une fois (ils ne bougent pas en session).
local backupDefaults

--- Sauvegarde de `profiles` réduits aux écarts aux défauts de FillProfile (quelques Ko au lieu de
-- ~69 Ko par profil). Les défauts sont joints, compressés : une mise à jour qui en change un ne
-- change pas un profil restauré.
local function PrunedBackup(reason, profiles)
    local defaults, out = ProfileDefaults(false), {}
    -- Niveau 5 : ~35 ms au lieu de ~125 ms au niveau 9, pour une chaîne plus longue de ~2 %.
    backupDefaults = backupDefaults or Database.Export(defaults, 5)
    for name, profile in pairs(profiles) do
        if type(profile) == "table" then out[name] = Prune(profile, defaults) end
    end
    return { reason = reason, version = Database.VERSION, time = time(), profiles = out, defaults = backupDefaults }
end

--- Profils réduits aux écarts aux défauts, `reason` : "import", "reset", "restore" (ou
-- "migration", posée par Migrate, copie complète). Écrase la précédente. `version` : format des
-- profils, migrés à la restauration.
function Database:SaveBackup(reason)
    self.global.profileBackup = PrunedBackup(reason, self.global.profiles)
end

--- Sauvegarde utilisable, ou nil.
function Database:Backup()
    local backup = self.global.profileBackup
    if type(backup) == "table" and type(backup.profiles) == "table" then return backup end
    return nil
end

--- Échange les profils et la sauvegarde : restaurer deux fois revient au point de départ.
-- Profils d'une version antérieure migrés d'abord, puis complétés des défauts (modules ajoutés
-- depuis). false sans sauvegarde ou si la migration échoue (rien n'est changé). Second retour :
-- true si les défauts joints étaient illisibles (défauts actuels utilisés).
function Database:RestoreBackup()
    local backup = self:Backup()
    if not backup then return false end
    -- Sauvegarde réduite : ses défauts d'origine d'abord, avant la migration et les défauts actuels.
    -- Sur une copie : en échec de migration, la sauvegarde reste réduite et rejouable.
    local restored = backup.profiles
    local defaults = type(backup.defaults) == "string" and self.Deserialize(backup.defaults, self.BACKUP_DEFAULTS_LIMIT)
    -- Défauts joints illisibles : restauration sur les défauts actuels, signalée à l'appelant.
    local defaultsLost = backup.defaults ~= nil and not defaults
    if defaults then
        restored = self.DeepCopy(restored)
        for _, profile in pairs(restored) do
            if type(profile) == "table" then self.MergeDefaults(defaults, profile) end
        end
    end
    local version = tonumber(backup.version) or self.VERSION
    if version < self.VERSION then
        local rolledBack = self.migrationRolledBack
        local migrated = { version = version, profiles = restored }
        self.Migrate(migrated)
        self.migrationRolledBack = rolledBack
        if migrated.version ~= self.VERSION then
            -- Copie complète : `migrated.profiles` est la copie intacte, rejouable.
            if not defaults then backup.profiles = migrated.profiles end
            return false
        end
        restored = migrated.profiles
    end
    local current = self.global.profiles
    self.global.profiles = restored
    self.global.profileBackup = PrunedBackup("restore", current)
    local profiles = self.global.profiles
    for name, profile in pairs(profiles) do
        if type(profile) ~= "table" or not self.ValidProfileName(name) then profiles[name] = nil end
    end
    profiles[self.DEFAULT_PROFILE] = profiles[self.DEFAULT_PROFILE] or {}
    for _, profile in pairs(profiles) do self.FillProfile(profile) end
    self:CaptureVariants()   -- profils rendus tels quels : l'écart de chaque variante est repris d'eux
    return true, defaultsLost
end

--- Remet le profil actif aux défauts (profils sauvegardés avant).
function Database:ResetActiveProfile()
    self:SaveBackup("reset")
    local name = self:ActiveProfileName()
    self.global.profiles[name] = self.FillProfile({})
    return self.global.profiles[name]
end

-- Couleurs du thème qu'on peut recopier d'un profil à l'autre.
Database.THEME_COLOR_KEYS = { "accentPreset", "accent", "backdrop", "border", "moverCustom", "moverColor", "classColors", "powerColors" }

--- Recopie les couleurs du thème du profil `from` dans le profil `to` (sur place : le profil actif
-- garde ses tables). Faux si l'un manque ou s'ils sont identiques.
function Database:CopyThemeColors(from, to)
    local profiles = self.global.profiles
    local source, target = profiles[from], profiles[to]
    if from == to or not (source and target and source.theme and target.theme) then return false end
    for _, key in ipairs(self.THEME_COLOR_KEYS) do
        local value = source.theme[key]
        if type(value) == "table" and type(target.theme[key]) == "table" then
            -- vidée d'abord : une couleur de classe absente de la source redevient celle de Blizzard
            wipe(target.theme[key])
            for field, part in pairs(value) do target.theme[key][field] = self.DeepCopy(part) end
        elseif value ~= nil then
            target.theme[key] = self.DeepCopy(value)
        end
    end
    return true
end

--- Les couleurs du profil `from` copiées dans tous les autres profils ; écarts des variantes refaits.
function Database:CopyThemeColorsToAll(from)
    local count = 0
    self:SyncVariants(NS.db)   -- l'écart des variantes est calculé avant la copie : les couleurs copiées s'y ajoutent
    for name in pairs(self.global.profiles) do
        if self:CopyThemeColors(from, name) then count = count + 1 end
    end
    self:CaptureVariants()
    return count
end

--------------------------------------------------------------------------------
-- Profil dérivé (variante) : un parent plus l'écart, rangés dans la base du compte
--------------------------------------------------------------------------------
-- profiles[variante] reste un profil complet (la table que lisent les modules, l'export, le
-- miroir) ; profileVariants[variante].diff = Diff(variante, parent) est la seule vérité durable :
-- la variante est refaite du parent plus l'écart, et suit donc les changements du parent.

-- Clé présente chez le parent, retirée dans la variante (position remise à zéro, entrée de liste).
local REMOVED = "\001removed"

--- Comme Prune (valeurs égales au parent écartées), plus REMOVED pour chaque clé retirée.
local function Diff(value, base)
    local out = {}
    base = type(base) == "table" and base or {}
    for key, child in pairs(value) do
        if type(child) == "table" then
            local sub = Diff(child, base[key])
            if next(sub) ~= nil then out[key] = sub end
        elseif child ~= base[key] then
            out[key] = child
        end
    end
    for key in pairs(base) do
        if value[key] == nil then out[key] = REMOVED end
    end
    return out
end

local function Overlay(target, diff)
    for key, value in pairs(diff) do
        if value == REMOVED then target[key] = nil
        elseif type(value) == "table" and type(target[key]) == "table" then Overlay(target[key], value)
        else target[key] = Database.DeepCopy(value) end
    end
    return target
end

--- Parent existant de la variante `name`, ou nil (pas une variante, parent supprimé ou absent).
function Database:VariantParent(name)
    local entry = self.global.profileVariants[name]
    local parent = type(entry) == "table" and entry.parent
    if type(parent) == "string" and parent ~= name and self.global.profiles[parent] then return parent end
    return nil
end

--- Crée la variante `name` du profil `parent` (qui n'en est pas une). Rend le nom, ou nil.
function Database:CreateVariant(parent, name)
    name = self.ValidProfileName(name)
    local profiles = self.global.profiles
    if not name or profiles[name] or not profiles[parent] or self:VariantParent(parent) then return nil end
    profiles[name] = self.DeepCopy(profiles[parent])
    self.global.profileVariants[name] = { parent = parent, diff = {} }
    return name
end

--- `live` : table du profil en cours (NS.db, nil à la connexion). Variante en cours : son écart
-- est recalculé ; les autres sont refaites de leur parent plus leur écart. Variante sans profil
-- ou sans parent : redevient un profil simple. Tables seulement.
function Database:SyncVariants(live)
    local profiles, variants = self.global.profiles, self.global.profileVariants
    for name, entry in pairs(variants) do
        local parent = self:VariantParent(name)
        if not parent or not profiles[name] then
            variants[name] = nil
        elseif profiles[name] == live then
            entry.diff = Diff(live, profiles[parent])
        else
            -- Le miroir retire les tables vides : écart absent = aucun écart.
            profiles[name] = Overlay(self.DeepCopy(profiles[parent]), type(entry.diff) == "table" and entry.diff or {})
        end
    end
end

--- Écart de chaque variante repris de son profil complet (profils remplacés d'un bloc :
-- restauration, désinstallation).
function Database:CaptureVariants()
    local profiles = self.global.profiles
    for name, entry in pairs(self.global.profileVariants) do
        local parent = self:VariantParent(name)
        if parent and profiles[name] then entry.diff = Diff(profiles[name], profiles[parent]) end
    end
end

--- Réglages surchargés de la variante `name` : { section, module, key } triés (section
-- "modules" -> module et clé ; sinon "theme", "anchors", "auraLists" et clé). Vide hors variante.
function Database:VariantOverrides(name)
    local parent, list = self:VariantParent(name), {}
    if not parent or not self.global.profiles[name] then return list end
    local diff = Diff(self.global.profiles[name], self.global.profiles[parent])
    for section, values in pairs(diff) do
        if section == "modules" and type(values) == "table" then
            for module, settings in pairs(values) do
                if type(settings) == "table" then
                    for key in pairs(settings) do list[#list + 1] = { section = section, module = module, key = key } end
                else
                    list[#list + 1] = { section = section, module = module }
                end
            end
        elseif type(values) == "table" then
            for key in pairs(values) do list[#list + 1] = { section = section, key = key } end
        else
            list[#list + 1] = { section = section }
        end
    end
    table.sort(list, function(a, b)
        local ka = a.section .. "\001" .. tostring(a.module) .. "\001" .. tostring(a.key)
        local kb = b.section .. "\001" .. tostring(b.module) .. "\001" .. tostring(b.key)
        return ka < kb
    end)
    return list
end

--- Remet le réglage `override` (voir VariantOverrides) de la variante `name` à la valeur du parent.
function Database:RevertVariant(name, override)
    local parent = self:VariantParent(name)
    local mine, theirs = self.global.profiles[name], parent and self.global.profiles[parent]
    if not (mine and theirs) then return false end
    local path = { override.section }
    if override.module ~= nil then path[#path + 1] = override.module end
    if override.key ~= nil then path[#path + 1] = override.key end
    for i = 1, #path - 1 do
        mine, theirs = mine[path[i]], type(theirs) == "table" and theirs[path[i]] or nil
        if type(mine) ~= "table" then return false end
    end
    mine[path[#path]] = self.DeepCopy(type(theirs) == "table" and theirs[path[#path]] or nil)
    self.global.profileVariants[name].diff = Diff(self.global.profiles[name], self.global.profiles[parent])
    return true
end

--------------------------------------------------------------------------------
-- Export / import d'un profil en chaîne texte
--------------------------------------------------------------------------------
-- Format : AEON1:chemin.a.b=n12;chemin.c=b1;chemin.d=sTexte;chemin.e=t (table vide)
-- Un profil ne contient que des tables (clés chaînes ou entières) et des scalaires : l'aplatir est
-- sans perte, les tables vides sont recréées par FillProfile à l'import. Les caractères
-- de structure (% ; = .) et les non imprimables sont échappés en %XX, dans les clés
-- comme dans les valeurs. Jamais de loadstring : la chaîne vient d'un tiers.

Database.EXPORT_PREFIX = "AEON1:"

local function Escape(text)
    -- `|` aussi : une chaîne partagée ne doit pas réinjecter de codes d'interface (|c, |T, |H).
    -- `"` et `\` : le miroir CVar est écrit entre guillemets dans config-cache.wtf.
    -- `#` : marque d'une clé numérique dans un chemin (#1 = [1]).
    return (tostring(text):gsub('[%%;=%.%c|"\\#]', function(c) return string.format("%%%02X", c:byte()) end))
end

local function Unescape(text)
    return (text:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end))
end

local function Flatten(value, path, out)
    if type(value) == "table" then
        -- Clés chaînes, puis clés entières (listes comme actionbars.bars) écrites `#N`.
        local keys, indexes = {}, {}
        for key in pairs(value) do
            if type(key) == "string" then keys[#keys + 1] = key
            elseif type(key) == "number" and key == math.floor(key) then indexes[#indexes + 1] = key end
        end
        table.sort(keys)
        table.sort(indexes)
        if next(value) == nil and path ~= "" then
            out[#out + 1] = path .. "=t"     -- table vide : son existence compte (nom de profil)
        end
        for _, key in ipairs(keys) do
            Flatten(value[key], path == "" and Escape(key) or (path .. "." .. Escape(key)), out)
        end
        for _, key in ipairs(indexes) do
            Flatten(value[key], path == "" and ("#" .. key) or (path .. ".#" .. key), out)
        end
    elseif type(value) == "boolean" then
        out[#out + 1] = path .. "=b" .. (value and "1" or "0")
    elseif type(value) == "number" then
        out[#out + 1] = path .. "=n" .. string.format("%.14g", value)
    elseif type(value) == "string" then
        out[#out + 1] = path .. "=s" .. Escape(value)
    end
end

--- Profil -> chaîne imprimable sur une seule ligne.
function Database.Serialize(profile)
    local out = {}
    Flatten(profile, "", out)
    return Database.EXPORT_PREFIX .. table.concat(out, ";")
end

-- AEON2 : la chaîne AEON1 compressée (LibDeflate) puis rendue imprimable. Bornes : une chaîne
-- tierce ne doit pas faire gonfler la mémoire (un deflate peut multiplier la taille par 1000).
Database.COMPRESSED_PREFIX = "AEON2:"
local MAX_COMPRESSED, MAX_EXPANDED = 32000, 262144   -- comme le miroir CVar ; export complet par défaut : ~12 Ko compressé
local MAX_ENTRIES = 20000   -- valeurs d'une chaîne tierce : borne large, bien au-dessus d'un export réel

local function Deflate() return _G.LibStub and LibStub("LibDeflate", true) end

--- Chaîne d'export : AEON2 compressée si LibDeflate est chargée, sinon AEON1.
-- `level` : niveau de compression (défaut 9, la chaîne la plus courte à partager).
function Database.Export(profile, level)
    local text = Database.Serialize(profile)
    local deflate = Deflate()
    if not deflate then return text end
    local compressed = deflate:CompressDeflate(text, { level = level or 9 })
    return Database.COMPRESSED_PREFIX .. deflate:EncodeForPrint(compressed)
end

--- Chaîne de partage d'un profil (ou d'un extrait) : marquée de la version du schéma, pour que
-- l'import la migre (Database:ImportProfile).
function Database.ExportProfile(profile)
    local stamped = {}
    for key, value in pairs(profile) do stamped[key] = value end
    stamped.version = Database.VERSION
    return Database.Export(stamped)
end

--- AEON2 -> AEON1 ; nil si la chaîne est tronquée, trop grande ou illisible.
-- `maxCompressed` : borne propre au miroir CVar ; les chaînes reçues gardent 32 000.
local function Expand(text, maxCompressed)
    local deflate = Deflate()
    local body = text:sub(#Database.COMPRESSED_PREFIX + 1)
    if not deflate or #body > (maxCompressed or MAX_COMPRESSED) then return nil end
    local compressed = deflate:DecodeForPrint(body)
    local expanded = compressed and deflate:DecompressDeflate(compressed)
    if type(expanded) ~= "string" or #expanded > MAX_EXPANDED then return nil end
    return expanded
end

--- A l'allure d'une chaîne de profil (préfixe connu), sans la décompresser : un envoi reçu du
-- groupe n'est décompressé qu'après l'accord du joueur.
function Database.IsProfileString(text)
    text = (text or ""):gsub("^%s+", "")
    return text:sub(1, #Database.EXPORT_PREFIX) == Database.EXPORT_PREFIX
        or text:sub(1, #Database.COMPRESSED_PREFIX) == Database.COMPRESSED_PREFIX
end

--- Chaîne -> table (sans les défauts), ou nil + raison ("prefix" | "parse").
--- Chaîne AEON1 en clair (AEON2 décompressée) ; nil si illisible.
function Database.PlainText(text, maxCompressed)
    text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if text:sub(1, #Database.COMPRESSED_PREFIX) == Database.COMPRESSED_PREFIX then
        return Expand(text, maxCompressed)
    end
    return text
end

function Database.Deserialize(text, maxCompressed)
    text = Database.PlainText(text, maxCompressed)
    if not text then return nil, "parse" end
    if text:sub(1, #Database.EXPORT_PREFIX) ~= Database.EXPORT_PREFIX then return nil, "prefix" end
    -- AEON1 collée en clair : même borne que la chaîne décompressée.
    if #text > MAX_EXPANDED then return nil, "parse" end
    local result, count = {}, 0
    for pair in (text:sub(#Database.EXPORT_PREFIX + 1) .. ";"):gmatch("([^;]*);") do
        count = count + 1
        if count > MAX_ENTRIES then return nil, "parse" end   -- chaîne tierce : nombre de valeurs borné
        if pair ~= "" then
            local path, kind, raw = pair:match("^([^=]+)=([bnst])(.*)$")
            if not path then return nil, "parse" end
            local value
            if kind == "t" then value = {}
            elseif kind == "b" then value = raw == "1"
            elseif kind == "n" then value = tonumber(raw)
            else value = Unescape(raw) end
            if value == nil then return nil, "parse" end
            local node = result
            local parts = {}
            for part in path:gmatch("[^%.]+") do
                parts[#parts + 1] = tonumber(part:match("^#(%-?%d+)$")) or Unescape(part)
            end
            if #parts == 0 or #parts > 16 then return nil, "parse" end   -- chaîne tierce : pile bornée
            for i = 1, #parts - 1 do
                if type(node[parts[i]]) ~= "table" then node[parts[i]] = {} end
                node = node[parts[i]]
            end
            node[parts[#parts]] = value
        end
    end
    return result
end

--------------------------------------------------------------------------------
-- Profil importé : une chaîne peut venir d'un autre joueur (envoi au groupe). Les types sont
-- déjà rétablis par FillProfile ; ici les valeurs.
--------------------------------------------------------------------------------

-- [chemin "modules.cotank.debuffMax"] = { min, max }, inscrit par les curseurs des options.
Database.bounds = {}
-- Réglages qui agissent au nom du joueur (argent, invitations, quêtes, objets) : un profil
-- importé ne les change pas, le joueur garde les siens.
Database.SENSITIVE = {
    "modules.automation.repair", "modules.automation.repairGuild", "modules.automation.sellJunk",
    "modules.automation.acceptInvites", "modules.automation.autoQuests", "modules.automation.fastDelete",
    "modules.automation.announceReset",   -- message envoyé au groupe au nom du joueur
    "modules.radialmenu.key",   -- une touche reçue (W, ÉCHAP) prendrait la place d'un raccourci du joueur
    "modules.radialmenu.palettes.palette2.key", "modules.radialmenu.palettes.palette3.key",
    "modules.radialmenu.palettes.palette4.key",
    "modules.raidutility.countdownKey", "modules.raidutility.countdown2Key", "modules.raidutility.countdown3Key",
}
local SIZE_OFFSET_LIMIT = 500   -- écart de taille d'un mover qui reprend celle de sa cible
-- Réglages chiffrés sans curseur (listes de choix).
Database.bounds["theme.grid"] = { 0, 64 }
Database.bounds["modules.groupframes.raidThreshold"] = { 5, 40 }
local COLOR_KEYS = { r = true, g = true, b = true, a = true }

--- Ramène `value` entre `low` et `high` ; compte la correction dans `report.clamped`.
local function Clamp(value, low, high, report)
    local clamped = math.max(low, math.min(high, value))
    if clamped ~= value and report then report.clamped = report.clamped + 1 end
    return clamped
end

--- Composantes de couleur (r, g, b, a) ramenées entre 0 et 1, à toute profondeur.
local function ClampColors(node, depth, report)
    if depth > 16 then return end
    for key, value in pairs(node) do
        if type(value) == "table" then
            ClampColors(value, depth + 1, report)
        elseif COLOR_KEYS[key] and type(value) == "number" then
            node[key] = Clamp(value, 0, 1, report)
        end
    end
end

local function ResolvePath(root, path)
    local parent, leaf = root, path
    while type(parent) == "table" do
        local part, rest = leaf:match("^([^%.]+)%.(.+)$")
        if not part then return parent, leaf end
        parent, leaf = parent[tonumber(part) or part], rest
    end
    return nil
end

--- Nombres non finis (NaN, infini) retirés : FillProfile remettra le défaut. Positions laissées
-- à FillProfile (Coordinate), qui compte une position écartée une seule fois.
local function DropNonFinite(node, depth, report)
    if depth > 16 then return end
    for key, value in pairs(node) do
        if type(value) == "number" and (value ~= value or value == math.huge or value == -math.huge) then
            node[key] = nil
            if report then report.clamped = report.clamped + 1 end
        elseif type(value) == "table" and not (depth == 0 and key == "anchors") then
            DropNonFinite(value, depth + 1, report)
        end
    end
end

--- Corrections d'un import, à montrer au joueur : valeurs bornées ou retirées, positions
-- écartées, réglages sensibles gardés.
function Database.NewImportReport()
    return { clamped = 0, anchors = 0, sensitive = 0 }
end

--- Réglages sensibles présents dans un profil importé, relevés avant FillProfile : un défaut
-- posé ensuite n'est pas compté comme gardé.
function Database.SensitiveGiven(profile)
    local given = {}
    for _, path in ipairs(Database.SENSITIVE) do
        local parent, leaf = ResolvePath(profile, path)
        if parent and parent[leaf] ~= nil then given[path] = true end
    end
    return given
end

--- Valeurs d'un profil importé ramenées dans leurs bornes ; réglages sensibles repris de `current`.
-- `report` (Database.NewImportReport, facultatif) compte chaque correction ; un réglage
-- sensible n'y compte que s'il figure dans `given` (Database.SensitiveGiven).
function Database.Sanitize(profile, current, report, given)
    for path, range in pairs(Database.bounds) do
        local parent, leaf = ResolvePath(profile, path)
        local value = parent and parent[leaf]
        if type(value) == "number" then parent[leaf] = Clamp(value, range[1], range[2], report) end
    end
    ClampColors(profile, 0, report)
    -- Coordonnées lointaines ou non finies déjà écartées par FillProfile (Coordinate).
    for _, anchor in pairs(profile.anchors) do
        for _, field in ipairs({ "widthOffset", "heightOffset" }) do
            if anchor[field] then anchor[field] = Clamp(anchor[field], -SIZE_OFFSET_LIMIT, SIZE_OFFSET_LIMIT, report) end
        end
    end
    for _, path in ipairs(Database.SENSITIVE) do
        local parent, leaf = ResolvePath(profile, path)
        local mineParent, mineLeaf = ResolvePath(current or {}, path)
        if parent and mineParent and mineParent[mineLeaf] ~= nil then
            if report and given and given[path] and parent[leaf] ~= mineParent[mineLeaf] then
                report.sensitive = report.sensitive + 1
            end
            parent[leaf] = mineParent[mineLeaf]
        end
    end
    return profile
end

--- Remplace le profil actif par la chaîne importée (complétée des défauts, valeurs bornées,
-- réglages sensibles conservés). nil + raison si invalide.
-- Export du compte accepté seulement si `allowAccount` (collé à la main, jamais reçu du groupe).
-- `sections` (set, voir PartialProfile) : seules ces sections d'un profil simple sont reprises.
-- `anchorKeys` : positions retenues, calculées avant que Reload ne désactive les modules (leurs
-- movers quittent alors le registre) ; à défaut, Database.ImportedAnchors.
-- Profils sauvegardés avant (Database:RestoreBackup). Rend le profil et le rapport de corrections.
function Database:ImportProfile(text, allowAccount, sections, anchorKeys)
    local imported, reason = self.Deserialize(text, self.PastedLimit(allowAccount))
    if not imported then return nil, reason end
    if imported.account and not allowAccount then return nil, "account" end
    -- Chaîne d'une version antérieure : migrée comme la table du compte. Sans version (chaîne
    -- d'avant ce marquage), elle est prise pour actuelle.
    local version = tonumber(imported.version)
    imported.version = nil
    -- Chaîne tierce : la version borne la boucle de Migrate (-inf, NaN ou 1e-9 la rendraient sans fin).
    if version and (version ~= math.floor(version) or version < 1) then return nil, "migration" end
    if version and version < self.VERSION then
        -- Extrait : une migration écrite pour un profil complet peut créer une section absente, que
        -- MergePartial poserait ensuite sur celle du joueur. Seules les sections présentes restent.
        local present
        if imported.partial then
            present = { modules = {} }
            for key in pairs(imported) do present[key] = true end
            for key in pairs(type(imported.modules) == "table" and imported.modules or {}) do present.modules[key] = true end
        end
        local migrated = { version = version,
                           profiles = imported.account and imported.profiles or { imported = imported } }
        -- Échec propre à la chaîne : rien à annoncer à la connexion ni dans /musca diag.
        local rolledBack, errorCount = self.migrationRolledBack, #self.migrationErrors
        self.Migrate(migrated)
        self.migrationRolledBack = rolledBack
        for index = #self.migrationErrors, errorCount + 1, -1 do self.migrationErrors[index] = nil end
        if migrated.version ~= self.VERSION then return nil, "migration" end
        if imported.account then imported.profiles = migrated.profiles else imported = migrated.profiles.imported end
        if present then
            for key in pairs(imported) do
                if not present[key] then imported[key] = nil end
            end
            for key in pairs(type(imported.modules) == "table" and imported.modules or {}) do
                if not present.modules[key] then imported.modules[key] = nil end
            end
        end
    end
    self:SaveBackup("import")
    local report = self.NewImportReport()
    local name = self:ActiveProfileName()
    local current = self.global.profiles[name]
    -- Nombres non finis retirés de ce qui est repris seulement : le rapport ne compte pas une section écartée.
    self.RenameModules(imported)
    if imported.account then
        -- Export du compte : chaque profil créé ou remplacé sous son nom, le profil actif compris.
        for profileName, profile in pairs(type(imported.profiles) == "table" and imported.profiles or {}) do
            local valid = self.ValidProfileName(profileName)
            if valid and type(profile) == "table" then
                DropNonFinite(profile, 0, report)
                self.RenameModules(profile)
                local mine = self.global.profiles[valid] or current
                self.global.profileVariants[valid] = nil   -- profil importé : profil simple
                local given = self.SensitiveGiven(profile)
                self.global.profiles[valid] = self.Sanitize(self.FillProfile(profile, report), mine, report, given)
            end
        end
        -- Parent remplacé : ses variantes (l'active comprise, écart gardé par Reload) refaites dessus.
        self:SyncVariants(nil)
        return self.global.profiles[name], report
    end
    if sections then
        imported = self.PartialProfile(imported, sections, anchorKeys or self.ImportedAnchors(imported, sections))
    end
    DropNonFinite(imported, 0, report)   -- l'extrait seul : le profil actuel n'est pas compté
    if imported.partial then imported = self.MergePartial(current, imported) end
    local given = self.SensitiveGiven(imported)
    self.global.profiles[name] = self.Sanitize(self.FillProfile(imported, report), current, report, given)
    return self.global.profiles[name], report
end

--- Positions d'un profil importé qui appartiennent aux sections retenues (mover connu de ce
-- client) ; celles d'un module écarté ou inconnu restent celles du joueur.
function Database.ImportedAnchors(imported, sections)
    local keys = {}
    local registry = NS.Movers and NS.Movers.registry or {}
    for key in pairs(type(imported.anchors) == "table" and imported.anchors or {}) do
        local entry = registry[key]
        if entry and entry.module and sections[entry.module] then keys[#keys + 1] = key end
    end
    return keys
end

--- Sections d'un profil importé, dans l'ordre : "theme", "auraLists", puis les modules.
function Database.ImportedSections(imported)
    local list = {}
    for _, section in ipairs({ "theme", "auraLists" }) do
        if type(imported[section]) == "table" then list[#list + 1] = section end
    end
    local modules = {}
    for module, settings in pairs(type(imported.modules) == "table" and imported.modules or {}) do
        if type(module) == "string" and type(settings) == "table" then modules[#modules + 1] = module end
    end
    table.sort(modules)
    for _, module in ipairs(modules) do list[#list + 1] = module end
    return list
end

--- Tous les profils du compte, réduits à ce qui diffère des défauts (FillProfile les rend à
-- l'import), pour un export d'un bloc (Database.Export).
function Database:AccountExport()
    return { account = true, version = self.VERSION, profiles = self:MirrorTable().profiles }
end

--- Borne de la chaîne compressée collée à la main : celle du miroir, plus large que l'envoi reçu.
function Database.PastedLimit(allowAccount)
    return allowAccount and Database.MIRROR_SLOTS * Database.MIRROR_CHUNK or nil
end

--- Extrait d'un profil : les sections `sections` (set de "theme", "auraLists" ou noms de
-- modules) et les positions `anchorKeys` (liste de clés de movers). Marqué `partial`.
function Database.PartialProfile(profile, sections, anchorKeys)
    local out = { partial = true, modules = {}, anchors = {} }
    local modules = type(profile.modules) == "table" and profile.modules or {}   -- profil importé : rien n'est garanti
    for section in pairs(sections) do
        if section == "theme" or section == "auraLists" then
            out[section] = Database.DeepCopy(profile[section])
        elseif modules[section] then
            out.modules[section] = Database.DeepCopy(modules[section])
        end
    end
    for _, key in ipairs(anchorKeys or {}) do
        out.anchors[key] = Database.DeepCopy(profile.anchors[key])
    end
    return out
end

--- Profil actuel recouvert par un extrait : seules les sections présentes changent.
function Database.MergePartial(current, partial)
    local merged = Database.DeepCopy(current or {})
    merged.modules, merged.anchors = merged.modules or {}, merged.anchors or {}
    for _, section in ipairs({ "theme", "auraLists" }) do
        if type(partial[section]) == "table" then merged[section] = partial[section] end
    end
    for name, settings in pairs(type(partial.modules) == "table" and partial.modules or {}) do
        if type(settings) == "table" then merged.modules[name] = settings end
    end
    for key, anchor in pairs(type(partial.anchors) == "table" and partial.anchors or {}) do
        merged.anchors[key] = anchor
    end
    return merged
end

--------------------------------------------------------------------------------
-- Doubles de la table sauvegardée, pour un client qui ne la relit pas
--------------------------------------------------------------------------------
-- WoW Forever 1.60 écrit les SavedVariables de compte mais ne les relit jamais (ni au
-- /reload, ni au démarrage). Ce qu'il relit, vérifié en jeu :
--   1. WTF/SavedVariables/Blizzard_AddOnList.lua (global g_addonCategoriesCollapsed) : la
--      table y est rangée telle quelle sous la clé HOST_KEY. Survit à la fermeture du jeu.
--   2. config-cache.wtf : les CVars enregistrées par l'addon y survivent au /reload seulement.
--      La table, réduite à ce qui diffère des défauts, y est recopiée (format d'export
--      ci-dessus) en tranches de MIRROR_CHUNK caractères (4000 vérifié en jeu).
-- Au chargement : SavedVariables non vide, sinon table hôte, sinon miroir CVar.

Database.HOST = "g_addonCategoriesCollapsed"
Database.HOST_KEY = "MuscaUI"
Database.LEGACY_HOST_KEY = "AeonUI"

local function Host()
    local host = _G[Database.HOST]
    if type(host) == "table" then return host end
    return nil
end

--- Range la table globale dans la sauvegarde hôte (référence, pas copie). false si l'hôte manque.
function Database:HostGlobal()
    local host = Host()
    if not host or not self.global then return false end
    host[self.HOST_KEY] = self.global
    host[self.LEGACY_HOST_KEY] = nil
    return true
end

Database.MIRROR_CVAR = "MuscaUIMirror"
Database.MIRROR_SLOTS = 8
Database.MIRROR_CHUNK = 4000

local lastMirror, mirrorRegistered
local lastTooBig    -- texte refusé (trop grand) : ni recompressé ni signalé une seconde fois

local function MirrorApi()
    local api = _G.C_CVar
    if api and api.RegisterCVar and api.GetCVar and api.SetCVar then return api end
    return nil
end

--- Enregistre les tranches (à faire à chaque session, avant toute lecture). false si l'API manque.
function Database:RegisterMirror()
    local api = MirrorApi()
    if not api then return false end
    if mirrorRegistered then return true end
    for i = 1, self.MIRROR_SLOTS do
        if not pcall(api.RegisterCVar, self.MIRROR_CVAR .. i, "") then return false end
    end
    mirrorRegistered = true
    return true
end

--- Table reconstruite depuis le miroir, ou nil (absent, API manquante, chaîne illisible).
function Database:ReadMirror()
    if not self:RegisterMirror() then return nil end
    local parts = {}
    for i = 1, self.MIRROR_SLOTS do
        local chunk = C_CVar.GetCVar(self.MIRROR_CVAR .. i)
        if type(chunk) ~= "string" or chunk == "" then break end
        parts[#parts + 1] = chunk
    end
    if #parts == 0 then return nil end
    local text = table.concat(parts)
    local saved = self.Deserialize(text, self.MIRROR_SLOTS * self.MIRROR_CHUNK)
    -- lastMirror compare le texte en clair : une tranche compressée n'en dit rien.
    if saved and text:sub(1, #self.EXPORT_PREFIX) == self.EXPORT_PREFIX then lastMirror = text end
    return saved
end

-- Défauts de profil du miroir, refaits seulement si un module s'est enregistré depuis (Prune ne
-- les modifie pas).
local mirrorDefaults, mirrorModuleCount

--- Table globale réduite à ce qui diffère des défauts ; chaque profil reste présent, même vide.
function Database:MirrorTable()
    local moduleCount = #NS.Modules:List()
    if moduleCount ~= mirrorModuleCount then
        mirrorDefaults, mirrorModuleCount = ProfileDefaults(true), moduleCount
    end
    local defaults = setmetatable({ profiles = {} }, { __index = self.GLOBAL_DEFAULTS })
    for name in pairs(self.global.profiles) do defaults.profiles[name] = mirrorDefaults end
    -- Historique du chat : volumineux et changeant, il ferait vite déborder les tranches ;
    -- la table hôte le garde, le miroir n'est qu'un repli. Écarté avant Prune (pas de copie).
    -- Sauvegarde des profils et état d'avant une migration en échec : même raison, et jamais
    -- exportés avec le compte.
    local history, backup, snapshot = self.global.chatHistory, self.global.profileBackup, self.global.migrationSnapshot
    self.global.chatHistory, self.global.profileBackup, self.global.migrationSnapshot = nil, nil, nil
    local pruned = Prune(self.global, defaults)
    self.global.chatHistory, self.global.profileBackup, self.global.migrationSnapshot = history, backup, snapshot
    pruned.version = self.global.version or self.VERSION    -- Init n'applique les migrations que si elle existe
    pruned.profiles = pruned.profiles or {}
    for name in pairs(self.global.profiles) do pruned.profiles[name] = pruned.profiles[name] or {} end
    return pruned
end

--- Recopie la table globale si elle a changé depuis la dernière écriture. true si écrit.
-- Compressée (AEON2) quand LibDeflate est là, et seulement quand le texte a changé : pas de
-- compression toutes les 5 s. Trop grande pour les tranches : rien n'est écrit, le miroir
-- précédent reste, le joueur est prévenu une fois.
function Database:WriteMirror()
    self:HostGlobal()       -- Blizzard peut recréer sa table : rebrancher à chaque passage
    if not self.global or not self:RegisterMirror() then return false end
    local text = self.Serialize(self:MirrorTable())
    if text == lastMirror or text == lastTooBig then return false end
    local stored = text
    local deflate = Deflate()
    if deflate then
        -- Niveau 5 : ~30 ms contre ~280 ms au niveau 9, pour 15 % de place en plus.
        stored = self.COMPRESSED_PREFIX .. deflate:EncodeForPrint(deflate:CompressDeflate(text, { level = 5 }))
    end
    -- Au-delà de MAX_EXPANDED en clair, Expand refuserait de le relire : ne pas l'écrire.
    if #stored > self.MIRROR_SLOTS * self.MIRROR_CHUNK or #text > MAX_EXPANDED then
        if not lastTooBig and NS.Print then NS.Print(NS.L.MSG_MIRROR_TOO_BIG) end
        lastTooBig = text
        return false
    end
    local written = true
    for i = 1, self.MIRROR_SLOTS do
        local chunk = stored:sub((i - 1) * self.MIRROR_CHUNK + 1, i * self.MIRROR_CHUNK)
        if C_CVar.SetCVar(self.MIRROR_CVAR .. i, chunk) == false then written = false end
    end
    if written then lastMirror = text end    -- échec : on réessaie au tick suivant
    return written
end

--- Prépare la table sauvegardée ; vide ou absente : la table hôte, sinon le miroir CVar.
function Database:Load(saved)
    if type(saved) ~= "table" or next(saved) == nil then
        local host = Host()
        local hosted = host and host[self.HOST_KEY]
        -- Réglages repris de l'ancien nom de l'addon (AeonUI), tant que rien n'existe sous le nouveau.
        if (type(hosted) ~= "table" or next(hosted) == nil) and host then hosted = host[self.LEGACY_HOST_KEY] end
        if type(hosted) == "table" and next(hosted) ~= nil then saved = hosted else saved = self:ReadMirror() end
    end
    return self:Init(saved)
end

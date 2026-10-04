-- Core/Database.lua
-- AeonUIDB (compte entier) :
--   version, locale, firstRunDone
--   profiles[nom] = { theme, anchors, modules[module] }   -- réglages d'interface
--   profileKeys["Perso - Royaume"] = nom du profil          -- absent = "Default"
--   specProfiles["Perso - Royaume"][index de spé] = nom      -- prime sur profileKeys
--   lastSpec["Perso - Royaume"] = index de spé                -- la spé n'est pas lisible dès la connexion
--   contextProfiles["Perso - Royaume"][contexte] = nom       -- donjon, raid, pvp, world : prime sur la spé
--   cvarBackup[cvar] = valeur d'origine, avant que AeonUI ne la change
-- NS.global pointe sur AeonUIDB, NS.db sur le profil actif.
-- Les défauts sont fusionnés sans jamais écraser une valeur existante ; les migrations
-- sont numérotées et jouées une fois.
local _, NS = ...

local Database = {}
NS.Database = Database

Database.VERSION = 6
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
    goldLedger = {},          -- [« Perso - Royaume »] = or en cuivre, relevé à la connexion et à chaque gain
    profileHotkeys = {},      -- [nom de profil] = touche qui bascule sur ce profil
    cvarBackup = {},
    chatClassColors = {},     -- [personnage] = { [chatType] = couleur de classe d'origine }
    tipsSeen = {},            -- [clé] = true : bulle d'aide de la fenêtre d'options déjà vue
    optionsMode = "simple",   -- fenêtre d'options : "simple" masque les réglages avancés, "advanced" les montre
}

Database.PROFILE_DEFAULTS = {
    theme = {
        font = "Fonts\\ARIALN.TTF",
        fontSize = 12,
        fontOutline = "",         -- "", "OUTLINE", "THICKOUTLINE"
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
        accentPreset = "custom",  -- "custom" (accent ci-dessus), "class", "faction" (lus pour chaque personnage)
        darkMode = false,         -- palette sombre partagée des barres de vie (Media:SetHealthColor)
        moduleMedia = {},         -- [module] = { font, statusbar } : exception au thème, absent = hérité
    },
    anchors = {},
    -- Listes d'identifiants de sorts partagées par tous les filtres d'auras (« 1234, 5678 »),
    -- tri des débuffs (boss, contrôle, dissipable) et lueur des contrôles (Glow.STYLES ou "none").
    auraLists = { whitelist = "", blacklist = "", prioritize = true, ccGlow = "pixel" },
    modules = {},
}

function Database.MergeDefaults(defaults, target)
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            if type(target[key]) ~= "table" then target[key] = {} end
            Database.MergeDefaults(value, target[key])
        elseif target[key] == nil or type(target[key]) ~= type(value) then
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
}

-- Migrations en échec de la session : { "v3 : message" }, lues par /aeon diag.
Database.migrationErrors = {}

--- Chaque migration sous pcall : une table abîmée ne doit pas empêcher l'addon de charger.
-- En échec, la suite est jouée quand même ; FillProfile rétablit les types au chargement.
function Database.Migrate(db)
    local from = tonumber(db.version) or Database.VERSION
    for version = from + 1, Database.VERSION do
        local migrate = Database.MIGRATIONS[version]
        if migrate then
            local ok, err = pcall(migrate, db)
            if not ok then
                Database.migrationErrors[#Database.migrationErrors + 1] = "v" .. version .. " : " .. tostring(err)
            end
        end
    end
    db.version = Database.VERSION
end

-- Un point inconnu (profil importé) ferait lever SetPoint après ClearAllPoints : module cassé.
local POINTS = {
    TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true, RIGHT = true,
    BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}

--- Complète un profil avec les défauts du cœur et de chaque module enregistré.
function Database.FillProfile(profile)
    Database.MergeDefaults(Database.PROFILE_DEFAULTS, profile)
    for _, module in ipairs(NS.Modules:List()) do
        -- Un scalaire à la place d'une table (chaîne importée hostile) est écarté.
        if type(profile.modules[module.name]) ~= "table" then profile.modules[module.name] = {} end
        Database.MergeDefaults(module.defaults, profile.modules[module.name])
    end
    -- Exceptions par module : chaînes seulement (chemin de police, nom de texture).
    for name, own in pairs(profile.theme.moduleMedia) do
        if type(own) ~= "table" then
            profile.theme.moduleMedia[name] = nil
        else
            if type(own.font) ~= "string" then own.font = nil end
            if type(own.statusbar) ~= "string" then own.statusbar = nil end
        end
    end
    for key, anchor in pairs(profile.anchors) do
        if type(anchor) ~= "table" or not POINTS[anchor.point] or not POINTS[anchor.relPoint]
            or type(anchor.x) ~= "number" or type(anchor.y) ~= "number" then
            profile.anchors[key] = nil
        else
            -- Ancrage à un autre mover (Movers) : champs mal typés écartés un à un.
            if type(anchor.target) ~= "string" then anchor.target = nil end
            local f = anchor.fallback
            if type(f) ~= "table" or not POINTS[f.point] or not POINTS[f.relPoint]
                or type(f.x) ~= "number" or type(f.y) ~= "number" then
                anchor.fallback = nil
            end
            if type(anchor.edgeX) ~= "number" then anchor.edgeX = nil end
            if type(anchor.edgeY) ~= "number" then anchor.edgeY = nil end
            if type(anchor.matchWidth) ~= "boolean" then anchor.matchWidth = nil end
            if type(anchor.matchHeight) ~= "boolean" then anchor.matchHeight = nil end
            -- Point d'écran épinglé et coin gardé quand la taille change (Movers).
            if not POINTS[anchor.pin] then anchor.pin = nil end
            if not POINTS[anchor.grow] then anchor.grow = nil end
            if type(anchor.widthOffset) ~= "number" then anchor.widthOffset = nil end
            if type(anchor.heightOffset) ~= "number" then anchor.heightOffset = nil end
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
    return new
end

--- Remet le profil actif aux défauts.
function Database:ResetActiveProfile()
    local name = self:ActiveProfileName()
    self.global.profiles[name] = self.FillProfile({})
    return self.global.profiles[name]
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
local MAX_COMPRESSED, MAX_EXPANDED = 12000, 262144   -- export complet actuel : ~5,4 Ko

local function Deflate() return _G.LibStub and LibStub("LibDeflate", true) end

--- Chaîne d'export : AEON2 compressée si LibDeflate est chargée, sinon AEON1.
function Database.Export(profile)
    local text = Database.Serialize(profile)
    local deflate = Deflate()
    if not deflate then return text end
    local compressed = deflate:CompressDeflate(text, { level = 9 })
    return Database.COMPRESSED_PREFIX .. deflate:EncodeForPrint(compressed)
end

--- AEON2 -> AEON1 ; nil si la chaîne est tronquée, trop grande ou illisible.
-- `maxCompressed` : borne propre au miroir CVar (32 000) ; les chaînes reçues gardent 12 000.
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
    local result = {}
    for pair in (text:sub(#Database.EXPORT_PREFIX + 1) .. ";"):gmatch("([^;]*);") do
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
    "modules.quickdraw.key",   -- une touche reçue (W, ÉCHAP) prendrait la place d'un raccourci du joueur
    "modules.quickdraw.palettes.palette2.key", "modules.quickdraw.palettes.palette3.key",
    "modules.quickdraw.palettes.palette4.key",
    "modules.raidutility.countdownKey", "modules.raidutility.countdown2Key", "modules.raidutility.countdown3Key",
}
local ANCHOR_LIMIT = 10000
local SIZE_OFFSET_LIMIT = 500   -- écart de taille d'un mover qui reprend celle de sa cible
-- Réglages chiffrés sans curseur (listes de choix).
Database.bounds["theme.grid"] = { 0, 64 }
Database.bounds["modules.groupframes.raidThreshold"] = { 5, 40 }
local COLOR_KEYS = { r = true, g = true, b = true, a = true }

--- Composantes de couleur (r, g, b, a) ramenées entre 0 et 1, à toute profondeur.
local function ClampColors(node, depth)
    if depth > 16 then return end
    for key, value in pairs(node) do
        if type(value) == "table" then
            ClampColors(value, depth + 1)
        elseif COLOR_KEYS[key] and type(value) == "number" then
            node[key] = math.max(0, math.min(1, value))
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

--- Nombres non finis (NaN, infini) retirés : FillProfile remettra le défaut.
local function DropNonFinite(node, depth)
    if depth > 16 then return end
    for key, value in pairs(node) do
        if type(value) == "number" and (value ~= value or value == math.huge or value == -math.huge) then
            node[key] = nil
        elseif type(value) == "table" then
            DropNonFinite(value, depth + 1)
        end
    end
end

--- Valeurs d'un profil importé ramenées dans leurs bornes ; réglages sensibles repris de `current`.
function Database.Sanitize(profile, current)
    for path, range in pairs(Database.bounds) do
        local parent, leaf = ResolvePath(profile, path)
        local value = parent and parent[leaf]
        if type(value) == "number" then parent[leaf] = math.max(range[1], math.min(range[2], value)) end
    end
    ClampColors(profile, 0)
    for key, anchor in pairs(profile.anchors) do
        if math.abs(anchor.x) > ANCHOR_LIMIT or math.abs(anchor.y) > ANCHOR_LIMIT then profile.anchors[key] = nil end
        local f = anchor.fallback
        if f and (math.abs(f.x) > ANCHOR_LIMIT or math.abs(f.y) > ANCHOR_LIMIT) then anchor.fallback = nil end
        if anchor.edgeX and math.abs(anchor.edgeX) > ANCHOR_LIMIT then anchor.edgeX = nil end
        if anchor.edgeY and math.abs(anchor.edgeY) > ANCHOR_LIMIT then anchor.edgeY = nil end
        for _, field in ipairs({ "widthOffset", "heightOffset" }) do
            if anchor[field] then anchor[field] = math.max(-SIZE_OFFSET_LIMIT, math.min(SIZE_OFFSET_LIMIT, anchor[field])) end
        end
    end
    for _, path in ipairs(Database.SENSITIVE) do
        local parent, leaf = ResolvePath(profile, path)
        local mineParent, mineLeaf = ResolvePath(current or {}, path)
        if parent and mineParent and mineParent[mineLeaf] ~= nil then parent[leaf] = mineParent[mineLeaf] end
    end
    return profile
end

--- Remplace le profil actif par la chaîne importée (complétée des défauts, valeurs bornées,
-- réglages sensibles conservés). nil + raison si invalide.
-- Export du compte accepté seulement si `allowAccount` (collé à la main, jamais reçu du groupe).
function Database:ImportProfile(text, allowAccount)
    local imported, reason = self.Deserialize(text, self.PastedLimit(allowAccount))
    if not imported then return nil, reason end
    if imported.account and not allowAccount then return nil, "account" end
    local name = self:ActiveProfileName()
    local current = self.global.profiles[name]
    DropNonFinite(imported, 0)
    if imported.account then
        -- Export du compte : chaque profil créé ou remplacé sous son nom, le profil actif compris.
        for profileName, profile in pairs(type(imported.profiles) == "table" and imported.profiles or {}) do
            local valid = self.ValidProfileName(profileName)
            if valid and type(profile) == "table" then
                local mine = self.global.profiles[valid] or current
                self.global.profiles[valid] = self.Sanitize(self.FillProfile(profile), mine)
            end
        end
        return self.global.profiles[name]
    end
    if imported.partial then imported = self.MergePartial(current, imported) end
    self.global.profiles[name] = self.Sanitize(self.FillProfile(imported), current)
    return self.global.profiles[name]
end

--- Tous les profils du compte, réduits à ce qui diffère des défauts (FillProfile les rend à
-- l'import), pour un export d'un bloc (Database.Export).
function Database:AccountExport()
    return { account = true, profiles = self:MirrorTable().profiles }
end

--- Borne de la chaîne compressée collée à la main : celle du miroir, plus large que l'envoi reçu.
function Database.PastedLimit(allowAccount)
    return allowAccount and Database.MIRROR_SLOTS * Database.MIRROR_CHUNK or nil
end

--- Extrait d'un profil : les sections `sections` (set de "theme", "auraLists" ou noms de
-- modules) et les positions `anchorKeys` (liste de clés de movers). Marqué `partial`.
function Database.PartialProfile(profile, sections, anchorKeys)
    local out = { partial = true, modules = {}, anchors = {} }
    for section in pairs(sections) do
        if section == "theme" or section == "auraLists" then
            out[section] = Database.DeepCopy(profile[section])
        elseif profile.modules[section] then
            out.modules[section] = Database.DeepCopy(profile.modules[section])
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
Database.HOST_KEY = "AeonUI"

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
    return true
end

Database.MIRROR_CVAR = "AeonUIMirror"
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

--- Copie de `value` sans les scalaires égaux à `defaults` (recréés par Init au retour).
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

--- Table globale réduite à ce qui diffère des défauts ; chaque profil reste présent, même vide.
function Database:MirrorTable()
    local profileDefaults = self.DeepCopy(self.PROFILE_DEFAULTS)
    -- mirrorDefaults : défauts plus larges que ceux du module (entrées créées à la demande).
    for _, module in ipairs(NS.Modules:List()) do profileDefaults.modules[module.name] = module.mirrorDefaults or module.defaults end
    local defaults = self.DeepCopy(self.GLOBAL_DEFAULTS)
    for name in pairs(self.global.profiles) do defaults.profiles[name] = profileDefaults end
    -- Historique du chat : volumineux et changeant, il ferait vite déborder les tranches ;
    -- la table hôte le garde, le miroir n'est qu'un repli. Écarté avant Prune (pas de copie).
    local history = self.global.chatHistory
    self.global.chatHistory = nil
    local pruned = Prune(self.global, defaults)
    self.global.chatHistory = history
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
        if type(hosted) == "table" and next(hosted) ~= nil then saved = hosted else saved = self:ReadMirror() end
    end
    return self:Init(saved)
end

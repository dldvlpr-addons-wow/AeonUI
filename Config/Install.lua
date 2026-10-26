-- Config/Install.lua
-- Installation en un clic : trois profils de base (Dégâts, Soigneur, Tank), chacun = interface
-- MuscaUI complète + disposition ergonomique du rôle. Les préréglages complete/light restent
-- accessibles par /musca install complete|light [rôle] sur le profil actif. Profils de classe
-- (Install.CLASSES) : un par style jouable de la classe du joueur, rôle de base + style + classe,
-- par l'assistant ou /musca install class <style>. Tout passe par la base
-- de réglages et les movers : rien d'irréversible, /musca reset rend les défauts.
local _, NS = ...
local L = NS.L

local Install = {}
NS.Install = Install

Install.NEW_MODULES = { "unitframes", "nameplateframes", "groupframes", "actionbars", "minimap", "chat", "databars", "questtracker", "afk" }

-- Disposition de référence, en unités d'interface (1920×1080 en pixel perfect ; ancrée au centre et
-- aux bords pour les autres résolutions). Colonne centrale, du personnage vers le bas : icônes de
-- buff du gestionnaire de recharges, recharges essentielles, utilitaires, barre d'incantation,
-- barres d'action (trois rangées). Joueur à gauche et cible à droite de la colonne, familier et
-- cible de la cible alignés dessous, focus et barres de buff à l'extérieur. Minimap et suivi de
-- quêtes en haut à droite, buffs et débuffs à gauche de la minimap, groupe à gauche, chat en bas
-- à gauche (Edit Mode), micro-menu et sacs en bas à droite.
-- { point d'écran, x, y, coin du cadre gardé } : le coin (facultatif) reste en place quand le cadre
-- grandit (raid de 10 à 40), x et y sont alors ceux de ce coin.
local BASE_ANCHORS = {
    bar1 = { "BOTTOM", 0, 34 }, bar2 = { "BOTTOM", 0, 76 }, bar3 = { "BOTTOM", 0, 118 },
    bar4 = { "RIGHT", -40, 0 }, bar5 = { "RIGHT", -84, 0 }, bar6 = { "BOTTOM", 0, 160 },
    stance = { "BOTTOM", -320, 176 }, pet = { "BOTTOM", 0, 218 },
    databar_xp = { "BOTTOM", 0, 6 }, databar_rep = { "BOTTOM", 0, 20 },
    micromenu = { "BOTTOMRIGHT", -10, 10 }, bags = { "BOTTOMRIGHT", -10, 60 },
    minimap = { "TOPRIGHT", -20, -50 }, questtracker = { "TOPRIGHT", -40, -260 },
    buffs = { "TOPRIGHT", -230, -60 }, debuffs = { "TOPRIGHT", -230, -180 },
    cdm_bufficon = { "CENTER", 0, -90 }, cdm_essential = { "CENTER", 0, -150 }, cdm_utility = { "CENTER", 0, -205 },
    cdm_buffbar = { "CENTER", 500, -130 },
    uf_castbar_player = { "CENTER", 0, -260 },
    uf_player = { "CENTER", -330, -250 }, uf_target = { "CENTER", 330, -250 },
    uf_pet = { "CENTER", -385, -300 }, uf_targettarget = { "CENTER", 385, -300 },
    uf_focus = { "CENTER", -560, -130 }, uf_focustarget = { "CENTER", -560, -180 },
    uf_boss1 = { "RIGHT", -310, 260 }, uf_boss2 = { "RIGHT", -310, 190 }, uf_boss3 = { "RIGHT", -310, 120 },
    uf_boss4 = { "RIGHT", -310, 50 }, uf_boss5 = { "RIGHT", -310, -20 },
    uf_party = { "TOPLEFT", 20, -250 }, uf_raid = { "TOPLEFT", 20, -250 },
    uf_tank = { "CENTER", -560, 145, "TOP" }, uf_assist = { "CENTER", -560, 285, "TOP" },   -- en-têtes : grandissent vers le bas
    cotank = { "CENTER", -560, -40 }, alerts = { "CENTER", 0, 220 }, combatTimer = { "CENTER", 0, 180 },
}
Install.BASE_ANCHORS = BASE_ANCHORS

Install.PRESETS = {
    complete = {
        modules = { unitframes = true, nameplateframes = true, groupframes = true, actionbars = true, minimap = true,
                    chat = true, databars = true, questtracker = true, blizzardframes = true, afk = true, frames = false },
        anchors = BASE_ANCHORS, cvars = true, editMode = true, addons = true,
    },
    light = {
        modules = { unitframes = false, nameplateframes = false, groupframes = false, actionbars = false, minimap = false,
                    chat = false, databars = false, questtracker = false, blizzardframes = false, afk = false, frames = true },
    },
}

-- Réglages par rôle, fusionnés dans les modules (les clés absentes restent telles quelles).
-- `anchors` d'un rôle remplace les ancrages de base pour ces clés.
Install.ROLES = {
    -- Dégâts : disposition de base, barre d'incantation détachée sous les recharges, groupe et raid en
    -- colonnes à gauche, menace sur les plaques.
    dps = {
        groupframes = { width = 110, height = 48, raidWidth = 90, raidHeight = 40, power = false, range = true, dispel = false, horizontal = false },
        unitframes = { units = { player = { castbarDetached = true }, focus = { auras = true } } },
        nameplateframes = { threatColor = true },
        anchors = {},
    },
    -- Soigneur : joueur et cible écartés, raid en grille (8 groupes × 5) sous les recharges, groupe
    -- en ligne au même endroit, barre d'incantation sous le cadre du joueur, dispel et portée.
    heal = {
        groupframes = { width = 110, height = 52, raidWidth = 96, raidHeight = 44, power = true, powerHeight = 4, range = true, dispel = true, healthText = "percent",
                        horizontal = true, mainTanks = true, raidUnitsPerColumn = 5, raidColumns = 8 },
        unitframes = { units = { player = { castbarDetached = false }, target = { auras = true }, focus = { auras = true } } },
        nameplateframes = { friendlyHealth = true },
        anchors = {
            uf_player = { "CENTER", -520, -250 }, uf_target = { "CENTER", 520, -250 },
            uf_pet = { "CENTER", -575, -330 }, uf_targettarget = { "CENTER", 575, -330 },
            uf_focus = { "CENTER", -560, -130 }, cdm_buffbar = { "CENTER", 520, -120 },
            cdm_bufficon = { "CENTER", 0, -70 }, cdm_essential = { "CENTER", 0, -120 }, cdm_utility = { "CENTER", 0, -170 },
            uf_party = { "CENTER", 0, -274, "TOP" }, uf_raid = { "CENTER", 0, -205, "TOP" },
        },
    },
    -- Tank : comme dégâts, agro sur les cadres de groupe, co-tank au-dessus du focus.
    tank = {
        groupframes = { width = 120, height = 52, raidWidth = 90, raidHeight = 40, power = false, aggro = true, range = true, horizontal = false },
        unitframes = { units = { player = { castbarDetached = true } } },
        cotank = { enabled = true },
        nameplateframes = { threatColor = true },
        anchors = { uf_focus = { "CENTER", -560, -140 }, cotank = { "CENTER", -560, -40 } },
    },
}

-- Styles de jeu des profils de classe : rôle de base (disposition) puis réglages du style.
-- Colonne centrale mêlée et tank, sous les recharges utilitaires (-205) : vie, puissance, points de
-- combo, mana du druide, barre d'incantation, coups blancs. Lanceurs : barre d'incantation large
-- et recharge globale juste dessous. Soigneurs : recharge globale entre les recharges et le raid.
local MELEE_ANCHORS = {
    resourceHealth = { "CENTER", 0, -228 }, resourcePower = { "CENTER", 0, -242 },
    resourceCombo = { "CENTER", 0, -254 }, resourceDruidMana = { "CENTER", 0, -262 },
    uf_castbar_player = { "CENTER", 0, -280 }, swingTimer = { "CENTER", 0, -304 },
    movementAlert = { "CENTER", 0, 120 },
}
local MELEE_SWING = { enabled = true, mainHand = true, offHand = true, ranged = false, width = 220 }

Install.PLAYSTYLES = {
    tank = { role = "tank", overrides = {
        resourcebars = { enabled = true, health = true, power = true, width = 220 },
        swingtimer = MELEE_SWING,
        movementalert = { enabled = true },
        nameplateframes = { threatRole = "tank" },
        unitframes = { castGCD = false },
        anchors = MELEE_ANCHORS,
    } },
    heal = { role = "heal", overrides = {
        gcdbar = { enabled = true, width = 220, height = 4 },
        clickcast = { enabled = true },
        unitframes = { castGCD = true },
        nameplateframes = { threatRole = "dps" },
        anchors = { gcdBar = { "CENTER", 0, -190 } },
    } },
    melee = { role = "dps", overrides = {
        resourcebars = { enabled = true, health = false, power = true, width = 220 },
        swingtimer = MELEE_SWING,
        movementalert = { enabled = true },
        nameplateframes = { threatRole = "dps" },
        unitframes = { castGCD = false },
        anchors = MELEE_ANCHORS,
    } },
    caster = { role = "dps", overrides = {
        gcdbar = { enabled = true, width = 300, height = 4 },
        unitframes = { castGCD = true, castLatency = true, units = { player = { castbarWidth = 300, castbarHeight = 20 } } },
        nameplateframes = { threatRole = "dps" },
        anchors = { uf_castbar_player = { "CENTER", 0, -260 }, gcdBar = { "CENTER", 0, -276 } },
    } },
    ranged = { role = "dps", overrides = {
        swingtimer = { enabled = true, mainHand = false, offHand = false, ranged = true, width = 260 },
        movementalert = { enabled = true },
        nameplateframes = { threatRole = "dps" },
        unitframes = { castGCD = false, units = { player = { castbarWidth = 260 } } },
        anchors = { uf_castbar_player = { "CENTER", 0, -260 }, swingTimer = { "CENTER", 0, -282 },
                    movementAlert = { "CENTER", 0, 120 } },
    } },
}

-- Familier mis en avant (chasseur, démoniste) : cadre plus grand avec ses auras, barre de familier.
local PET_FOCUS = {
    unitframes = { units = { pet = { width = 160, height = 30, powerHeight = 5, auras = true, auraSize = 18 } } },
    actionbars = { petBar = "move" },
    reminders = { pet = true },
    anchors = { uf_pet = { "CENTER", -360, -305 }, pet = { "BOTTOM", 0, 218 } },
}

-- Profils de classe : styles jouables dans l'ordre d'affichage, réglages communs à la classe
-- (`all`), puis réglages propres à un style. Appliqués après le rôle et le style.
Install.CLASSES = {
    WARRIOR = { styles = { "melee", "tank" },
        all = { actionbars = { stanceBar = "move" }, swingtimer = { queueColor = { r = 1, g = 0.82, b = 0 } } },
        tank = { reminders = { expectedStance = "defensive" } },
    },
    PALADIN = { styles = { "melee", "heal", "tank" },
        all = { actionbars = { stanceBar = "move" } },
        melee = { swingtimer = { offHand = false } },
        tank = { reminders = { righteousFury = true }, swingtimer = { offHand = false } },
    },
    HUNTER = { styles = { "ranged" }, all = PET_FOCUS },
    ROGUE = { styles = { "melee" },
        all = { unitframes = { units = { player = { comboPips = true } } },
                resourcebars = { combo = true, comboHeight = 10 }, nameplateframes = { comboPoints = true } },
    },
    PRIEST = { styles = { "caster", "heal" },
        caster = { reminders = { shadowform = true } },
    },
    SHAMAN = { styles = { "caster", "melee", "heal" },
        all = { unitframes = { units = { player = { totems = true, totemSize = 30 } } },
                anchors = { uf_totems = { "CENTER", -330, -292 } } },
        melee = { swingtimer = { offHand = false } },
        -- Soigneur : joueur écarté à gauche, totems sous sa barre d'incantation, hors de la grille de raid.
        heal = { anchors = { uf_totems = { "CENTER", -520, -312 } } },
    },
    MAGE = { styles = { "caster" },
        all = { movementalert = { enabled = true }, anchors = { movementAlert = { "CENTER", 0, 120 } } },
    },
    WARLOCK = { styles = { "caster" }, all = PET_FOCUS },
    DRUID = { styles = { "caster", "melee", "heal", "tank" },
        all = { actionbars = { stanceBar = "move" }, resourcebars = { druidMana = true } },
        melee = { unitframes = { units = { player = { comboPips = true } } }, resourcebars = { combo = true },
                  reminders = { expectedStance = "cat" }, swingtimer = { offHand = false } },
        tank = { reminders = { expectedStance = "bear" }, swingtimer = { offHand = false }, resourcebars = { combo = false } },
    },
}

-- HUD de classe Musca-Auras (pack « <Classe> (Musca) » importé) : colonne centrée sous le personnage,
-- 334 de large, de y -30 à -400 environ. Le HUD dessine déjà ressource, coups blancs et incantation :
-- les barres MuscaUI de la colonne se coupent, la barre d'incantation rentre sous le cadre du joueur.
-- Joueur et cible à 300 du centre, familier et cible de la cible dessous, barre de familier à gauche,
-- groupe et raid à gauche, tanks et assistants principaux sous la grille de raid.
-- Posé après le rôle, le style et la classe : il gagne sur leurs ancrages de la colonne centrale.
local HUD_OVERRIDES = {
    unitframes = { units = { player = { castbarDetached = false } } },
    resourcebars = { enabled = false }, swingtimer = { enabled = false }, gcdbar = { enabled = false },
    anchors = {
        uf_player = { "CENTER", -300, -195 }, uf_target = { "CENTER", 300, -195 },
        uf_pet = { "CENTER", -355, -302 }, uf_targettarget = { "CENTER", 355, -302 },
        pet = { "BOTTOM", -360, 218 },   -- au-dessus de la barre de posture (BOTTOM -320,176)
        uf_party = { "TOPLEFT", 20, -250 }, uf_raid = { "TOPLEFT", 20, -250 },
        uf_tank = { "CENTER", -800, 40, "TOP" }, uf_assist = { "CENTER", -800, -170, "TOP" },
    },
}
Install.HUD_OVERRIDES = HUD_OVERRIDES
-- Totems du chaman sous la barre d'incantation attachée (emplacement des points de combo compris).
-- Pas pour les autres classes : leurs boutons de totem vides capteraient les clics du familier.
local HUD_TOTEMS = { uf_totems = { "CENTER", -300, -270 } }

--- Vrai si un HUD de classe Musca-Auras de la classe du joueur est importé (dossier d'addon
-- WeakAuras, groupe racine « <Classe> (Musca) » chargé pour cette classe). WeakAurasSaved est
-- partagé par le compte : sans le filtre de classe, le HUD d'un chaman viderait la colonne d'un mage.
local function MuscaHud()
    local api, classFile = _G.C_AddOns and C_AddOns.IsAddOnLoaded, Install.PlayerClass()
    if not (api and classFile) then return end
    local ok, loaded = pcall(api, "WeakAuras")
    local saved = ok and loaded and _G.WeakAurasSaved
    if type(saved) ~= "table" or type(saved.displays) ~= "table" then return end
    for id, data in pairs(saved.displays) do
        if type(id) == "string" and id:find(" %(Musca%)$") and type(data) == "table" and not data.parent
            and type(data.load) == "table" and type(data.load.class) == "table" and data.load.class.single == classFile then
            return data, saved.displays, id
        end
    end
end

function Install.HasMuscaHud() return MuscaHud() ~= nil end

-- Tolérance : une couleur relue des SavedVariables peut différer au dernier chiffre.
local function SameColor(color, r, g, b)
    return type(color[1]) == "number" and type(color[2]) == "number" and type(color[3]) == "number"
        and math.abs(color[1] - r) < 1e-3 and math.abs(color[2] - g) < 1e-3 and math.abs(color[3] - b) < 1e-3
end

-- Une icône rechargée par image : 59 WeakAuras.Add dans la même image gelaient le jeu 300 ms.
-- Une icône remplacée entre-temps (réimport) est sautée, son propre Add relance un repeint.
-- Une icône déjà en file n'y entre pas deux fois : le glisser de la roue d'accent relance un repeint toutes les 0,2 s.
local paintQueue, queuedData = {}, {}
local paintFrame = CreateFrame("Frame")
paintFrame:Hide()
paintFrame:SetScript("OnUpdate", function(self)
    if InCombatLockdown() then return end
    local entry = table.remove(paintQueue, 1)
    if entry then queuedData[entry.data] = nil end
    if entry and entry.displays[entry.id] == entry.data and _G.WeakAuras then _G.WeakAuras.Add(entry.data) end
    if #paintQueue == 0 then self:Hide() end
end)

--- Bordure des icônes du HUD Musca à la couleur d'accent MuscaUI. Seules les bordures noires du
-- pack et celles à l'accent du repeint précédent changent : une couleur choisie à la main dans
-- WeakAuras est gardée. Seules les icônes dont la couleur change sont rechargées : le repeint qui
-- suit chaque WeakAuras.Add (réimport du pack) s'arrête donc au second passage.
function Install.PaintHud()
    local root, displays, rootId = MuscaHud()
    local add = _G.WeakAuras and _G.WeakAuras.Add
    if not (root and add) or InCombatLockdown() then return end
    local r, g, b = NS.Media:Accent()
    -- Un accent par HUD : chaque classe est repeinte à la connexion de son personnage.
    local store = type(NS.global.hudBorder) == "table" and NS.global.hudBorder or {}
    local painted = store[rootId]
    local function Paint(data, id)
        for _, child in ipairs(type(data.controlledChildren) == "table" and data.controlledChildren or {}) do
            if type(displays[child]) == "table" then Paint(displays[child], child) end
        end
        local changed = false
        for _, sub in ipairs(type(data.subRegions) == "table" and data.subRegions or {}) do
            local color = sub.type == "subborder" and sub.border_color
            if type(color) == "table" and not SameColor(color, r, g, b) and (SameColor(color, 0, 0, 0)
                or type(painted) == "table" and SameColor(color, painted[1], painted[2], painted[3])) then
                sub.border_color = { r, g, b, color[4] or 1 }
                changed = true
            end
        end
        if changed and not queuedData[data] then
            queuedData[data] = true
            paintQueue[#paintQueue + 1] = { id = id, data = data, displays = displays }
            paintFrame:Show()
        end
    end
    Paint(root, rootId)
    store[rootId] = { r, g, b }
    NS.global.hudBorder = store
end

-- Import lancé par l'assistant : le HUD se place dès que le pack est importé (le joueur confirme
-- dans la fenêtre de Musca), sans second clic. Seul l'Add de la racine du HUD vaut confirmation.
-- Musca ne signale pas une annulation : l'attente cesse à la fermeture de l'assistant, sinon
-- le réglage d'une aura du HUD (Add de la racine) le placerait plus tard.
local hudPending, hudConfirmed = false, false
function Install.ForgetHudImport() hudPending, hudConfirmed = false, false end
function Install.ImportHud()
    local import = _G.WeakAuras and _G.WeakAuras.ImportClassPack
    if not import then return false end
    hudPending = true
    if import() then return true end
    hudPending = false
    return false
end

-- THEME_CHANGED arrive à chaque image pendant le glisser de la roue de couleur : un seul repeint
-- par tranche de 0,2 s. Tant que WeakAuras n'a pas fini sa connexion, le repeint attend.
local paintQueued = false
local function QueuePaint()
    if paintQueued then return end
    paintQueued = true
    C_Timer.After(0.2, function()
        paintQueued = false
        local weakAuras = _G.WeakAuras
        if weakAuras and weakAuras.IsLoginFinished and not weakAuras.IsLoginFinished() then return QueuePaint() end
        NS:RunOutOfCombat(function()
            if hudConfirmed and Install.HasMuscaHud() then
                hudPending, hudConfirmed = false, false
                Install.ApplyHud()   -- repeint compris
                NS.Modules:RefreshAll()   -- barre d'incantation rattachée au cadre du joueur
                NS:Fire("HUD_PLACED")
                NS.Print(L.SETUP_HUD_PLACED)
            else
                Install.PaintHud()
            end
        end)
    end)
end
-- Un réimport du pack (assistant ou bouton Class Pack de Musca) rend les bordures noires :
-- chaque WeakAuras.Add relance un repeint.
local function OnAdd(data)
    if hudPending and type(data) == "table" and data.id ~= nil and data.id == select(3, MuscaHud()) then
        hudConfirmed = true
    end
    QueuePaint()
end
local hookedWeakAuras
NS:On("LOGIN", function()
    local weakAuras = _G.WeakAuras
    if hookedWeakAuras ~= weakAuras and weakAuras and type(weakAuras.Add) == "function" then
        hooksecurefunc(weakAuras, "Add", OnAdd)
        hookedWeakAuras = weakAuras
    end
    QueuePaint()
end)
NS:On("THEME_CHANGED", QueuePaint)

local function Merge(target, overrides)
    for key, value in pairs(overrides) do
        if type(value) == "table" and type(target[key]) == "table" then Merge(target[key], value)
        else target[key] = value end
    end
end

local function SetAnchors(anchors)
    for key, anchor in pairs(anchors or {}) do
        local grow = anchor[4]
        NS.db.anchors[key] = { point = grow or anchor[1], relPoint = anchor[1], x = anchor[2], y = anchor[3], grow = grow }
        NS.Movers:Load(key)   -- sans effet si le mover n'est pas encore enregistré
    end
end

local function ApplyOverrides(overrides)
    for name, values in pairs(overrides) do
        local db = name ~= "anchors" and NS.db.modules[name]
        if db then
            Merge(db, NS.Database.DeepCopy(values))
            if values.enabled ~= nil and not NS.Modules:IsYielded(name) then NS.Modules:SetEnabled(name, values.enabled) end
        end
    end
    SetAnchors(overrides.anchors)
end

-- Disposition autour du HUD Musca, quand il est importé. Rejouée après chaque couche de réglages
-- (rôle, style, classe) qui repose des ancrages de la colonne centrale.
local function ApplyHud()
    if not Install.HasMuscaHud() then return false, "nohud" end
    ApplyOverrides(HUD_OVERRIDES)
    if Install.PlayerClass() == "SHAMAN" then SetAnchors(HUD_TOTEMS) end
    Install.PaintHud()
    return true
end
Install.ApplyHud = ApplyHud

-- Choix « HUD Musca Auras » de l'assistant : la disposition du HUD part avec le profil, en dernière
-- couche, sans attendre l'import du pack (ApplyHud ne la pose qu'une fois le pack là).
local function HudLayers()
    return { HUD_OVERRIDES, { anchors = Install.PlayerClass() == "SHAMAN" and HUD_TOTEMS or {} } }
end

-- Choix « Barres de combat » de l'assistant : pas de HUD posé même si le pack est déjà importé.
local barsChosen = false
local function ApplyHudUnlessBars()
    if not barsChosen then ApplyHud() end
end

function Install:ApplyRole(role)
    local overrides = self.ROLES[role]
    if not overrides then return false end
    ApplyOverrides(overrides)
    ApplyHudUnlessBars()
    return true
end

--- Applique un préréglage (et un rôle) au profil actif. Hors combat de préférence : les modules
-- sécurisés diffèrent d'eux-mêmes ce qu'ils ne peuvent pas faire en combat. `extra` : réglages
-- posés après le rôle (profils de classe), `label` : nom affiché à la place du rôle.
function Install:ApplyPreset(presetName, role, extra, label)
    local preset = self.PRESETS[presetName]
    if not preset then return false, "preset" end
    SetAnchors(preset.anchors)
    if role and role ~= "none" then self:ApplyRole(role) end
    for _, overrides in ipairs(extra or {}) do ApplyOverrides(overrides) end
    if preset.anchors then ApplyHudUnlessBars() end
    for name, enabled in pairs(preset.modules) do
        -- Un module cédé garde le réglage : il s'allumera le jour où l'addon tiers part.
        if NS.Modules:Get(name) then
            NS.db.modules[name].enabled = enabled
            if not NS.Modules:IsYielded(name) then NS.Modules:SetEnabled(name, enabled) end
        end
    end
    NS.Modules:RefreshAll()   -- repose les ancrages des modules déjà actifs
    if preset.cvars and NS.FirstRun then
        for _, entry in ipairs(NS.FirstRun.RECOMMENDED_CVARS) do NS.CVars:Set(entry.name, entry.value) end
    end
    if preset.editMode and NS.PRESET_LAYOUTS and NS.PRESET_LAYOUTS.editMode ~= "" then
        pcall(NS.ImportEditModeLayout, NS.PRESET_LAYOUTS.editMode, "MuscaUI")
    end
    -- Chat remis à zéro seulement si le module chat MuscaUI tourne (pas cédé à un autre addon de chat).
    if preset.addons and NS.AddonPlacements then
        local chat = NS.Modules:Get("chat")
        NS.AddonPlacements:ApplyAll(chat and chat.enabled and not NS.Modules:IsYielded("chat"))
    end
    NS.global.firstRunDone = true
    label = label or ((role and role ~= "none") and L["INSTALL_ROLE_" .. role:upper()])
    local roleLabel = label and (" (" .. label .. ")") or ""
    NS.Print(string.format(L.MSG_INSTALLED, L["INSTALL_PRESET_" .. presetName:upper()] .. roleLabel))
    return true
end

--------------------------------------------------------------------------------
-- Styles (page Style de l'assistant)
--------------------------------------------------------------------------------

-- Modules qui remplacent un cadre Blizzard : style MuscaUI = module actif (cadre Blizzard caché),
-- style Blizzard = module coupé, cadre d'origine rendu.
Install.STYLE_MODULES = { "unitframes", "groupframes", "nameplateframes", "actionbars", "minimap", "bags", "chat",
                          "databars", "questtracker" }
Install.STYLE_ORDER = { "aeon", "classic", "blizzard" }
local THEME_KEYS = { "font", "statusbar", "accent", "border", "backdrop", "accentPreset" }
-- aeon : thème par défaut, fenêtres Blizzard au thème. classic : police, or et texture de barre
-- du client vanilla, fenêtres Blizzard intactes. blizzard : cadres d'origine, thème inchangé.
Install.STYLES = {
    aeon = { modules = true, skinWindows = true, theme = "default" },
    classic = { modules = true, skinWindows = false, theme = {
        font = "Fonts\\FRIZQT__.TTF", statusbar = "blizzard:classic", accentPreset = "custom",
        accent = { r = 1, g = 0.82, b = 0 }, border = { r = 0.5, g = 0.42, b = 0.24, a = 1 },
        backdrop = { r = 0.02, g = 0.02, b = 0.02, a = 0.92 } } },
    blizzard = { modules = false, skinWindows = false },
}

--- Applique un style au profil actif : modules de remplacement, fenêtres Blizzard, thème.
function Install:ApplyStyle(name)
    local style = self.STYLES[name]
    if not style then return false end
    for _, module in ipairs(self.STYLE_MODULES) do
        if NS.Modules:Get(module) then
            NS.db.modules[module].enabled = style.modules
            if not NS.Modules:IsYielded(module) then NS.Modules:SetEnabled(module, style.modules) end
        end
    end
    if NS.db.modules.skin then
        NS.db.modules.skin.skinWindows = style.skinWindows
        NS.Modules:Refresh("skin")
    end
    local theme = style.theme == "default" and NS.Database.PROFILE_DEFAULTS.theme or style.theme
    if theme then
        for _, key in ipairs(THEME_KEYS) do NS.db.theme[key] = NS.Database.DeepCopy(theme[key]) end
        NS:Fire("THEME_CHANGED")
    end
    NS.Print(string.format(L.MSG_STYLE_APPLIED, L["STYLE_" .. name:upper()]))
    return true
end

--- Nom du profil de base d'un rôle (« Dégâts », « Soigneur », « Tank »).
function Install.ProfileName(role) return L["INSTALL_ROLE_" .. role:upper()] end

--- Installation en un clic : bascule sur le profil de base du rôle (créé depuis les défauts s'il
-- n'existe pas), puis y pose l'interface complète et la disposition du rôle.
function Install:Apply(role, hud)
    if not self.ROLES[role] then return false, "role" end
    NS:SwitchProfile(self.ProfileName(role))
    barsChosen = hud == false
    local ok, reason = self:ApplyPreset("complete", role, hud and HudLayers() or nil)
    barsChosen = false
    return ok, reason
end

--- Classe du joueur (« WARRIOR »…) et son nom affiché ; nil si illisible ou non gérée.
function Install.PlayerClass()
    local name, classFile = UnitClass("player")
    if NS.IsSecret(classFile) or not Install.CLASSES[classFile or ""] then return nil end
    return classFile, name
end

--- Styles jouables par la classe du joueur ({} si classe illisible ou non gérée).
function Install.ClassStyles()
    local classFile = Install.PlayerClass()
    return classFile and Install.CLASSES[classFile].styles or {}
end

function Install.CanPlay(style)
    for _, name in ipairs(Install.ClassStyles()) do
        if name == style then return true end
    end
    return false
end

--- Nom du profil de classe d'un style (« Druide - Tank »).
function Install.ClassProfileName(style)
    local _, name = Install.PlayerClass()
    return (name or "") .. " - " .. L["INSTALL_ROLE_" .. style:upper()]
end

local function ClassOverrides(style)
    local class = Install.CLASSES[Install.PlayerClass()]
    return { Install.PLAYSTYLES[style].overrides, class.all or {}, class[style] or {} }
end

local function Filled(entries, field)
    for _, entry in pairs(entries or {}) do
        local value = field and type(entry) == "table" and entry[field] or entry
        if type(value) == "string" and value ~= "" then return true end
    end
    return false
end

-- Liaison de clic posée par le joueur : un sort, macro ou objet saisi, ou un bijou (sans valeur).
local function HasClickBinding(bindings)
    for _, binding in pairs(bindings or {}) do
        if type(binding) == "table" and (binding.kind == "trinket1" or binding.kind == "trinket2") then return true end
    end
    return Filled(bindings, "spell")
end

-- Soigneur : liaisons de clic et coins des cadres de groupe propres à la classe, quand elle en a.
-- `keepPlayer` : seulement là où le joueur n'a encore rien posé (profil existant).
local function ApplyHealPresets(style, keepPlayer)
    if style ~= "heal" then return end
    local clickCast, groupFrames = NS.Modules:Get("clickcast"), NS.Modules:Get("groupframes")
    if clickCast and clickCast.enabled and not (keepPlayer and HasClickBinding(clickCast.db.bindings)) then
        clickCast:ApplyPreset()
    end
    if groupFrames and not (keepPlayer and Filled(groupFrames.db.indicators, "spells")) then groupFrames:ApplyIndicatorPreset() end
end

-- Remet aux défauts du module les clés posées par `overrides` (feuilles des sous-tables comprises).
local function ResetKeys(db, defaults, overrides)
    for key, value in pairs(overrides) do
        if type(value) == "table" and type(defaults[key]) == "table" and type(db[key]) == "table" then
            ResetKeys(db[key], defaults[key], value)
        elseif defaults[key] ~= nil then
            db[key] = NS.Database.DeepCopy(defaults[key])
        end
    end
end

--- Profil de classe : bascule sur le profil « Classe - Style » du joueur, puis pose l'interface
-- complète, la disposition du rôle, les réglages du style et ceux de la classe.
function Install:ApplyClass(style, hud)
    if not self.CanPlay(style) then return false, "style" end
    NS:SwitchProfile(self.ClassProfileName(style))
    local layers = ClassOverrides(style)
    for _, layer in ipairs(hud and HudLayers() or {}) do layers[#layers + 1] = layer end
    barsChosen = hud == false
    local ok = self:ApplyPreset("complete", self.PLAYSTYLES[style].role, layers, self.ClassProfileName(style))
    barsChosen = false
    ApplyHealPresets(style)
    return ok
end

--- Réglages d'un profil de classe (rôle, style, classe) posés sur le profil actuel, sans en
-- changer ni toucher au reste de l'interface. Les réglages de tous les styles et de toutes les
-- classes sont d'abord remis aux défauts (profil partagé entre personnages) : pas de rappel de
-- forme d'ours ni de barre de tank qui traîne.
function Install:ApplyClassSettings(style)
    if not self.CanPlay(style) then return false, "style" end
    local touched = {}
    for _, playstyle in pairs(self.PLAYSTYLES) do touched[#touched + 1] = playstyle.overrides end
    for _, class in pairs(self.CLASSES) do
        for key, overrides in pairs(class) do
            if key ~= "styles" then touched[#touched + 1] = overrides end
        end
    end
    for _, overrides in ipairs(touched) do
        for name, values in pairs(overrides) do
            local module = name ~= "anchors" and NS.Modules:Get(name)
            if module and NS.db.modules[name] then
                ResetKeys(NS.db.modules[name], module.defaults, values)
                if values.enabled ~= nil and not NS.Modules:IsYielded(name) then
                    NS.Modules:SetEnabled(name, module.defaults.enabled)
                end
            end
        end
    end
    self:ApplyRole(self.PLAYSTYLES[style].role)
    for _, overrides in ipairs(ClassOverrides(style)) do ApplyOverrides(overrides) end
    ApplyHud()
    ApplyHealPresets(style, true)
    NS.Modules:RefreshAll()
    return true
end

-- Config/Install.lua
-- Installation en un clic : trois profils de base (Dégâts, Soigneur, Tank), chacun = interface
-- AeonUI complète + disposition ergonomique du rôle. Les préréglages complete/light restent
-- accessibles par /aeon install complete|light [rôle] sur le profil actif. Tout passe par la base
-- de réglages et les movers : rien d'irréversible, /aeon reset rend les défauts.
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
    uf_tank = { "CENTER", -560, 120 }, uf_assist = { "CENTER", -560, 260 },
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
        groupframes = { width = 80, height = 30, power = false, range = true, dispel = false, horizontal = false },
        unitframes = { units = { player = { castbarDetached = true }, focus = { auras = true } } },
        nameplateframes = { threatColor = true },
        anchors = {},
    },
    -- Soigneur : joueur et cible écartés, raid en grille (8 groupes × 5) sous les recharges, groupe
    -- en ligne au même endroit, barre d'incantation sous le cadre du joueur, dispel et portée.
    heal = {
        groupframes = { width = 72, height = 32, power = true, powerHeight = 4, range = true, dispel = true, healthText = "percent",
                        horizontal = true, mainTanks = true, raidUnitsPerColumn = 5, raidColumns = 8 },
        unitframes = { units = { player = { castbarDetached = false }, target = { auras = true }, focus = { auras = true } } },
        nameplateframes = { friendlyHealth = true },
        anchors = {
            uf_player = { "CENTER", -520, -250 }, uf_target = { "CENTER", 520, -250 },
            uf_pet = { "CENTER", -575, -330 }, uf_targettarget = { "CENTER", 575, -330 },
            uf_focus = { "CENTER", -560, -130 }, cdm_buffbar = { "CENTER", 520, -120 },
            cdm_bufficon = { "CENTER", 0, -70 }, cdm_essential = { "CENTER", 0, -120 }, cdm_utility = { "CENTER", 0, -170 },
            uf_party = { "CENTER", 0, -290 }, uf_raid = { "CENTER", 0, -290 },
        },
    },
    -- Tank : comme dégâts, agro sur les cadres de groupe, co-tank au-dessus du focus.
    tank = {
        groupframes = { width = 90, height = 36, power = false, aggro = true, range = true, horizontal = false },
        unitframes = { units = { player = { castbarDetached = true } } },
        cotank = { enabled = true },
        nameplateframes = { threatColor = true },
        anchors = { uf_focus = { "CENTER", -560, -140 }, cotank = { "CENTER", -560, -40 } },
    },
}

local function Merge(target, overrides)
    for key, value in pairs(overrides) do
        if type(value) == "table" and type(target[key]) == "table" then Merge(target[key], value)
        else target[key] = value end
    end
end

local function SetAnchors(anchors)
    for key, anchor in pairs(anchors or {}) do
        NS.db.anchors[key] = { point = anchor[1], relPoint = anchor[1], x = anchor[2], y = anchor[3] }
    end
end

function Install:ApplyRole(role)
    local overrides = self.ROLES[role]
    if not overrides then return false end
    for name, values in pairs(overrides) do
        local db = name ~= "anchors" and NS.db.modules[name]
        if db then
            Merge(db, values)
            if values.enabled ~= nil and not NS.Modules:IsYielded(name) then NS.Modules:SetEnabled(name, values.enabled) end
        end
    end
    SetAnchors(overrides.anchors)
    return true
end

--- Applique un préréglage (et un rôle) au profil actif. Hors combat de préférence : les modules
-- sécurisés diffèrent d'eux-mêmes ce qu'ils ne peuvent pas faire en combat.
function Install:ApplyPreset(presetName, role)
    local preset = self.PRESETS[presetName]
    if not preset then return false, "preset" end
    SetAnchors(preset.anchors)
    if role and role ~= "none" then self:ApplyRole(role) end
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
        pcall(NS.ImportEditModeLayout, NS.PRESET_LAYOUTS.editMode, "AeonUI")
    end
    -- Chat remis à zéro seulement si le module chat AeonUI tourne (pas cédé à ElvUI ou Prat).
    if preset.addons and NS.AddonPlacements then
        local chat = NS.Modules:Get("chat")
        NS.AddonPlacements:ApplyAll(chat and chat.enabled and not NS.Modules:IsYielded("chat"))
    end
    NS.global.firstRunDone = true
    local roleLabel = (role and role ~= "none") and (" (" .. L["INSTALL_ROLE_" .. role:upper()] .. ")") or ""
    NS.Print(string.format(L.MSG_INSTALLED, L["INSTALL_PRESET_" .. presetName:upper()] .. roleLabel))
    return true
end

--- Nom du profil de base d'un rôle (« Dégâts », « Soigneur », « Tank »).
function Install.ProfileName(role) return L["INSTALL_ROLE_" .. role:upper()] end

--- Installation en un clic : bascule sur le profil de base du rôle (créé depuis les défauts s'il
-- n'existe pas), puis y pose l'interface complète et la disposition du rôle.
function Install:Apply(role)
    if not self.ROLES[role] then return false, "role" end
    NS:SwitchProfile(self.ProfileName(role))
    return self:ApplyPreset("complete", role)
end

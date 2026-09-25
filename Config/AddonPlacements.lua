-- Config/AddonPlacements.lua
-- Installation : chat à la manière d'ElvUI et addons tiers posés dans les zones libres de la
-- disposition AeonUI (Install.BASE_ANCHORS). Rien n'est une dépendance : un addon absent est
-- ignoré.
--
-- ForeverMeter et KickAlert gardent leurs réglages (même Mirror.lua que AeonUI) : posés une
-- fois. DBM et BigWigs perdent les leurs à chaque session (le client ne relit pas leurs
-- SavedVariables) : reposés à chaque connexion tant que l'installation l'a demandé.
local _, NS = ...

local AddonPlacements = {}
NS.AddonPlacements = AddonPlacements

-- { point, x, y } relatifs à UIParent, mêmes unités que BASE_ANCHORS (1920×1080), vérifiés contre
-- les tailles par défaut des cadres AeonUI. Chat principal en bas à gauche (Edit Mode), chat
-- butin/commerce en bas à droite sous la cible du soigneur, compteur entre les barres d'action et
-- la cible de la cible. Barres de boss à gauche de la colonne centrale (à droite : cadres boss1-5),
-- barres agrandies et alertes au-dessus du personnage, sous les annonces AeonUI, cadre d'infos
-- en haut à gauche, au-dessus du groupe.
-- ponytail: positions pensées pour 1920×1080 ; en 4K ou ultra-large, /aeon unlock et chaque addon.
local POINTS = {
    chatRight = { "BOTTOMRIGHT", -10, 100, 320, 160 },
    foreverMeter = { "BOTTOMRIGHT", -450, 20 },
    kickAlert = { "CENTER", 0, 130 },
    bossBars = { "CENTER", -300, 150 },
    bossBarsLarge = { "CENTER", 0, 20 },
    bossWarning = { "CENTER", 0, 330 },
    bossSpecialWarning = { "CENTER", 0, 75 },
    bossInfo = { "TOPLEFT", 20, -60 },
    bossRange = { "CENTER", -300, -60 },
}
AddonPlacements.POINTS = POINTS

-- Groupes de messages repris d'ElvUI (E:SetupChat).
local MAIN_GROUPS = { "SYSTEM", "CHANNEL", "SAY", "EMOTE", "YELL", "WHISPER", "PARTY", "PARTY_LEADER", "RAID",
    "RAID_LEADER", "RAID_WARNING", "INSTANCE_CHAT", "INSTANCE_CHAT_LEADER", "GUILD", "OFFICER", "MONSTER_SAY",
    "MONSTER_YELL", "MONSTER_EMOTE", "MONSTER_WHISPER", "MONSTER_BOSS_EMOTE", "MONSTER_BOSS_WHISPER", "ERRORS",
    "AFK", "DND", "IGNORED", "BG_HORDE", "BG_ALLIANCE", "BG_NEUTRAL", "ACHIEVEMENT", "GUILD_ACHIEVEMENT",
    "BN_WHISPER", "BN_INLINE_TOAST_ALERT" }
local RIGHT_GROUPS = { "CHANNEL", "COMBAT_XP_GAIN", "COMBAT_HONOR_GAIN", "COMBAT_FACTION_CHANGE", "SKILL", "LOOT",
    "CURRENCY", "MONEY" }
local CHANNEL_COLORS = { CHANNEL1 = { 0.76, 0.90, 0.91 }, CHANNEL2 = { 0.91, 0.62, 0.47 }, CHANNEL3 = { 0.91, 0.89, 0.47 } }

local function Place(frameName, p)
    local frame = _G[frameName]
    if not frame then return end
    frame:ClearAllPoints()
    frame:SetPoint(p[1], UIParent, p[1], p[2], p[3])
end

function AddonPlacements.Chat()
    local loot, trade = _G.LOOT or "Loot", _G.TRADE or "Trade"
    return NS.SetupChatWindows({
        name = loot .. " / " .. trade, point = POINTS.chatRight, fontSize = 12,
        mainGroups = MAIN_GROUPS, rightGroups = RIGHT_GROUPS,
        general = _G.GENERAL, trade = _G.TRADE, channelColors = CHANNEL_COLORS,
    }) ~= nil
end

function AddonPlacements.ForeverMeter()
    local db = _G.ForeverMeterDB
    local window = type(db) == "table" and type(db.windows) == "table" and db.windows[1]
    if type(window) ~= "table" then return false end
    local p = POINTS.foreverMeter
    window.point = { p[1], nil, p[1], p[2], p[3] }   -- format de ForeverMeter : relTo nil = UIParent
    window.anchor = nil
    Place("ForeverMeterFrame", p)
    return true
end

function AddonPlacements.KickAlert()
    local db = _G.KickAlertDB
    if type(db) ~= "table" or type(db.anchors) ~= "table" then return false end
    local p = POINTS.kickAlert
    db.anchors.Text = { point = p[1], relTo = "UIParent", relPoint = p[1], x = p[2], y = p[3] }
    Place("KickAlertText", p)
    return true
end

local function SetDBMPoint(options, prefix, p)
    options[prefix .. "Point"], options[prefix .. "X"], options[prefix .. "Y"] = p[1], p[2], p[3]
end

function AddonPlacements.DBM()
    local dbm = _G.DBM
    if type(dbm) ~= "table" or type(dbm.Options) ~= "table" then return false end
    SetDBMPoint(dbm.Options, "Warning", POINTS.bossWarning)
    SetDBMPoint(dbm.Options, "SpecialWarning", POINTS.bossSpecialWarning)
    SetDBMPoint(dbm.Options, "InfoFrame", POINTS.bossInfo)
    SetDBMPoint(dbm.Options, "RangeFrame", POINTS.bossRange)
    if dbm.RepositionFrames then pcall(dbm.RepositionFrames, dbm) end
    local bars = _G.DBT
    if type(bars) == "table" and type(bars.Options) == "table" then
        SetDBMPoint(bars.Options, "Timer", POINTS.bossBars)
        SetDBMPoint(bars.Options, "HugeTimer", POINTS.bossBarsLarge)
        if bars.Rearrange then pcall(bars.Rearrange, bars) end
    end
    return true
end

local function BigWigsPosition(p) return { p[1], p[1], p[2], p[3], "UIParent" } end

--- BigWigs_Plugins se charge à la demande (entrée en instance) : faux tant qu'il n'est pas là.
-- GetPlugin rend une copie réduite ({ db }) : la mise à jour passe par le cœur.
function AddonPlacements.BigWigs()
    local core = _G.BigWigs
    if type(core) ~= "table" or not core.GetPlugin then return false end
    local placed = false
    for name, positions in pairs({
        Bars = { normalPosition = POINTS.bossBars, expPosition = POINTS.bossBarsLarge },
        Messages = { normalPosition = POINTS.bossWarning, emphPosition = POINTS.bossSpecialWarning },
    }) do
        local ok, plugin = pcall(core.GetPlugin, core, name, true)
        local profile = ok and type(plugin) == "table" and plugin.db and plugin.db.profile
        if profile then
            for key, p in pairs(positions) do profile[key] = BigWigsPosition(p) end
            placed = true
        end
    end
    if placed and core.SendMessage then pcall(core.SendMessage, core, "BigWigs_ProfileUpdate") end
    return placed
end

--- Tout ce qui est présent. Chat à la première installation seulement (il remet les fenêtres à
-- zéro : un changement de rôle ne doit pas effacer les onglets du joueur), puis /reload proposé
-- (fenêtres touchées par un addon jusqu'au rechargement, comme après l'installation d'ElvUI).
function AddonPlacements:ApplyAll(withChat)
    if withChat and not NS.global.chatSetupDone and self.Chat() then
        NS.global.chatSetupDone = true
        if NS.Options and NS.Options.AskReload then NS.Options.AskReload(NS.L.MSG_CHAT_RELOAD) end
    end
    self.ForeverMeter()
    self.KickAlert()
    self.DBM()
    self.BigWigs()
    NS.global.addonPlacements = true
end

-- Connexion : DBM et BigWigs repartent de leurs défauts, on les repose.
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(_, event, name)
    if not (NS.global and NS.global.addonPlacements) then return end
    if event == "PLAYER_LOGIN" then
        local dbm = _G.DBM
        if type(dbm) == "table" and dbm.RegisterOnLoadCallback then
            pcall(dbm.RegisterOnLoadCallback, dbm, AddonPlacements.DBM)
        else
            AddonPlacements.DBM()
        end
        AddonPlacements.BigWigs()
    elseif name == "BigWigs_Plugins" then
        -- Bases des plugins créées après leur chargement : une image plus tard, puis un repli.
        C_Timer.After(0, function()
            if not AddonPlacements.BigWigs() then C_Timer.After(2, AddonPlacements.BigWigs) end
        end)
    end
end)

-- Modules/TopBar.lua
-- Bande d'informations en haut (ou en bas) de l'écran :
--   [Amis] [Guilde] [libre]    [Heure zzz]    [libre] [Or] [Dura] [Sacs] [Perf] [Voyage] [Foyer]
-- Ses textes sont inscrits au registre NS.DataTexts (réutilisés par les panneaux de données) ;
-- les deux emplacements libres montrent n'importe quel data text du registre.
-- Le bouton foyer et le menu Voyage contiennent des boutons sécurisés : le module est
-- `secure`. En combat on ne touche qu'aux textes, jamais aux tailles, ancrages ni à
-- l'affichage (le masquage en combat passe par un state driver, seul moyen autorisé).
local _, NS = ...
local L = NS.L
local Media = NS.Media

local HEARTHSTONE = 6948
local BAR_HEIGHT = 20
local HEARTH_WIDTH = 170
local PADDING = 14
local GUILD_ROSTER_THROTTLE = 15
local MEMORY_THROTTLE = 30
local TRAVEL_SIZE = 32
local TRAVEL_COLUMNS = 6

-- Remplace les portails M+ de NaowhUI : ce qui existe sur un client Classic.
-- Ordre d'affichage du menu Voyage ; seuls les sorts connus du personnage apparaissent.
local TRAVEL_SPELLS = {
    3561, 3562, 3565, 3567, 3563, 3566,              -- mage : téléportations
    10059, 11416, 11419, 11417, 11418, 11420,        -- mage : portails
    18960,                                           -- druide : Téléportation : Reflet-de-Lune
    556,                                             -- chaman : Rappel astral
}
NS.TRAVEL_SPELLS = TRAVEL_SPELLS

local TopBar = NS.Modules:Register("topbar", {
    titleKey = "TOPBAR_TITLE",
    descKey = "TOPBAR_DESC",
    secure = true,
    defaults = {
        enabled = true,
        position = "TOP",          -- "TOP" | "BOTTOM" | "FREE" (largeur ajustée, déplaçable en mode déverrouillé)
        backgroundAlpha = 0.75,
        serverTime = false,
        use24h = true,
        showResting = true,
        hideInCombat = false,
        perfInCombat = true,       -- FPS/latence restent visibles quand la barre se masque en combat
        shiftMinimap = true,       -- barre en haut : descendre la minimap pour ne pas la recouvrir
        extraLeft = "none",        -- data text de l'emplacement libre de gauche (NS.DataTexts)
        extraRight = "none",       -- data text de l'emplacement libre de droite
        show = {
            friends = true, guild = true, clock = true, gold = true,
            durability = true, bags = true, perf = true, travel = true, hearth = true,
        },
    },
})

local bar, hearth, travelMenu, ticker
local active = false   -- vrai entre OnEnable et OnDisable (module.enabled n'est posé qu'après OnEnable)
local elements = {}    -- [key] = bouton non sécurisé
local docked = {}      -- [clé] = rangée d'un autre module posée dans la barre (TopBar:Dock)
local DOCK_ORDER = { "micromenu", "bags" }
local travelButtons = {}
local lastRosterRequest, lastMemoryScan, memoryLines = -1000, -1000, {}

--------------------------------------------------------------------------------
-- Contenu des éléments
--------------------------------------------------------------------------------

local function Dim(text) return "|cff9d9d9d" .. text .. "|r" end

local function Accent(text) return "|c" .. Media:AccentHex() .. text .. "|r" end

local function RequestRoster(force)
    if not force and GetTime() - lastRosterRequest < GUILD_ROSTER_THROTTLE then return end
    lastRosterRequest = GetTime()
    NS.RequestGuildRoster()
end

local TEXT = {}

function TEXT.friends()
    local wow, bnet = NS.GetOnlineFriends()
    return Dim(L.TOPBAR_FRIENDS) .. " " .. Accent(tostring(wow + bnet))
end

function TEXT.guild()
    local online = NS.GetOnlineGuildMembers()
    if not online then return Dim(L.TOPBAR_NO_GUILD) end
    return Dim(L.TOPBAR_GUILD) .. " " .. Accent(tostring(online))
end

function TopBar.FormatClock(hour, minute, use24h)
    if use24h then return string.format("%02d:%02d", hour, minute) end
    -- Chaînes du jeu, déjà traduites.
    local suffix = hour < 12 and (_G.TIMEMANAGER_AM or "AM") or (_G.TIMEMANAGER_PM or "PM")
    local h = hour % 12
    if h == 0 then h = 12 end
    return string.format("%d:%02d %s", h, minute, suffix)
end

function TEXT.clock()
    local db = TopBar.db
    local hour, minute
    if db.serverTime and _G.GetGameTime then
        hour, minute = GetGameTime()
    else
        hour, minute = tonumber(date("%H")), tonumber(date("%M"))
    end
    local text = TopBar.FormatClock(hour, minute, db.use24h)
    if db.showResting and _G.IsResting and IsResting() then
        text = text .. " " .. Dim("zzz")
    end
    return text
end

function TEXT.gold()
    return NS.FormatMoney(GetMoney())
end

function TEXT.durability()
    local pct = NS.GetLowestDurability()
    if not pct then return Dim(L.TOPBAR_DURABILITY) .. " -" end
    local color = pct < 20 and "|cffff4040" or (pct < 50 and "|cffffc040" or "|cffffffff")
    return Dim(L.TOPBAR_DURABILITY) .. " " .. color .. math.floor(pct) .. "%|r"
end

function TEXT.bags()
    local free = 0
    for bag = 0, NS.NUM_BAGS do free = free + NS.GetBagFreeSlots(bag) end
    local color = free == 0 and "|cffff4040" or "|cffffffff"
    return Dim(L.TOPBAR_BAGS) .. " " .. color .. free .. "|r"
end

--- Couleur d'une mesure : blanc si bonne, jaune au-delà de `warn`, rouge au-delà de `bad`.
-- `higherIsBetter` inverse le sens (FPS).
function TopBar.Grade(value, warn, bad, higherIsBetter)
    if higherIsBetter then
        if value < bad then return "|cffff4040" end
        if value < warn then return "|cffffc040" end
    else
        if value > bad then return "|cffff4040" end
        if value > warn then return "|cffffc040" end
    end
    return "|cffffffff"
end

function TEXT.perf()
    local fps = math.floor(GetFramerate() + 0.5)
    local _, _, home, world = GetNetStats()
    local ms = math.max(home or 0, world or 0)
    return TopBar.Grade(fps, 50, 30, true) .. fps .. "|r " .. Dim(L.TOPBAR_FPS) .. "  "
        .. TopBar.Grade(ms, 100, 200, false) .. ms .. "|r " .. Dim(L.TOPBAR_MS)
end

function TEXT.travel()
    return Accent(L.TOPBAR_TRAVEL)
end

--- Data text d'un emplacement libre, ou nil.
local function Extra(slot)
    local key = TopBar.db[slot]
    local def = key ~= "none" and NS.DataTexts:Get(key) or nil
    if def and def.secret then return nil end   -- largeur inconnue : pas dans la barre
    return def
end

for _, slot in ipairs({ "extraLeft", "extraRight" }) do
    TEXT[slot] = function()
        local def = Extra(slot)
        if not def then return "" end
        local ok, text = pcall(def.text)
        return ok and text or ""
    end
end

local function HearthText()
    if NS.GetItemCount(HEARTHSTONE) == 0 then return Dim(L.TOPBAR_HEARTH) .. " -" end
    local remaining = NS.GetItemCooldownRemaining(HEARTHSTONE)
    if remaining > 0 then
        return Dim(L.TOPBAR_HEARTH) .. " " .. NS.FormatDuration(remaining)
    end
    local location = _G.GetBindLocation and GetBindLocation() or ""
    return Dim(L.TOPBAR_HEARTH) .. " " .. Accent(location)
end

--------------------------------------------------------------------------------
-- Mémoire des addons (infobulle Perf)
--------------------------------------------------------------------------------

--- Les `limit` addons les plus gourmands : { { name, kb } }. Rescanné au plus toutes les 30 s.
function TopBar.ScanMemory(limit)
    if GetTime() - lastMemoryScan < MEMORY_THROTTLE then return memoryLines end
    lastMemoryScan = GetTime()
    memoryLines = {}
    if not (_G.UpdateAddOnMemoryUsage and _G.GetAddOnMemoryUsage) then return memoryLines end
    UpdateAddOnMemoryUsage()
    local getNum = (C_AddOns and C_AddOns.GetNumAddOns) or _G.GetNumAddOns
    local getInfo = (C_AddOns and C_AddOns.GetAddOnInfo) or _G.GetAddOnInfo
    for i = 1, (getNum and getNum() or 0) do
        local kb = GetAddOnMemoryUsage(i)
        if kb and kb > 0 then memoryLines[#memoryLines + 1] = { name = (getInfo(i)), kb = kb } end
    end
    table.sort(memoryLines, function(a, b) return a.kb > b.kb end)
    for i = #memoryLines, (limit or 10) + 1, -1 do memoryLines[i] = nil end
    return memoryLines
end

local function FormatMemory(kb)
    if kb >= 1024 then return string.format(L.TOPBAR_MEMORY_MB, kb / 1024) end
    return string.format(L.TOPBAR_MEMORY_KB, kb)
end

--------------------------------------------------------------------------------
-- Infobulles et clics
--------------------------------------------------------------------------------

local TOOLTIP, CLICK = {}, {}

function TOOLTIP.friends(tt)
    tt:AddLine(L.TOPBAR_FRIENDS_ONLINE)
    local any = false
    if C_FriendList and C_FriendList.GetNumFriends then
        for i = 1, C_FriendList.GetNumFriends() do
            local info = C_FriendList.GetFriendInfoByIndex(i)
            if info and info.connected then
                any = true
                local r, g, b = NS.ClassColor(NS.ClassTokenFromLocalized(info.className))
                tt:AddDoubleLine(info.name .. " (" .. (info.level or "?") .. ")", info.area or "", r, g, b, 0.8, 0.8, 0.8)
            end
        end
    end
    if _G.BNGetNumFriends and C_BattleNet and C_BattleNet.GetFriendAccountInfo then
        for i = 1, (BNGetNumFriends()) do
            local account = C_BattleNet.GetFriendAccountInfo(i)
            local game = account and account.gameAccountInfo
            if game and game.isOnline then
                any = true
                tt:AddDoubleLine(account.accountName or "?", game.characterName or game.clientProgram or "",
                    0.51, 0.77, 1, 0.8, 0.8, 0.8)
            end
        end
    end
    if not any then tt:AddLine(L.TOPBAR_NOBODY, 0.6, 0.6, 0.6) end
    tt:AddLine(L.TOPBAR_CLICK_OPEN, 0.5, 0.5, 0.5)
end

-- Chaînes du jeu (« <AFK> », « <ABS> »…), déjà traduites, sans les chevrons.
local function StatusFlag(text, fallback) return ((text or fallback):gsub("[<>]", "")) end
local STATUS_TAG = {
    [1] = " |cffffc040" .. StatusFlag(_G.CHAT_FLAG_AFK, "AFK") .. "|r",
    [2] = " |cffff4040" .. StatusFlag(_G.CHAT_FLAG_DND, "DND") .. "|r",
}

function TOOLTIP.guild(tt)
    if not NS.GetOnlineGuildMembers() then
        tt:AddLine(L.TOPBAR_NO_GUILD)
        return
    end
    RequestRoster()
    tt:AddLine((GetGuildInfo("player")) or L.TOPBAR_GUILD)
    local shown, total = 0, NS.GetNumGuildMembers()
    for i = 1, total do
        local name, _, _, level, _, zone, _, _, online, status, class = NS.GetGuildRosterInfo(i)
        if online then
            shown = shown + 1
            if shown > 40 then
                tt:AddLine(L.TOPBAR_AND_MORE, 0.6, 0.6, 0.6)
                break
            end
            local r, g, b = NS.ClassColor(class)
            tt:AddDoubleLine((name or "?"):gsub("%-.*", "") .. " (" .. (level or "?") .. ")" .. (STATUS_TAG[status] or ""),
                zone or "", r, g, b, 0.8, 0.8, 0.8)
        end
    end
    tt:AddLine(L.TOPBAR_CLICK_OPEN, 0.5, 0.5, 0.5)
end

function TOOLTIP.clock(tt)
    tt:AddLine(date(L.TOPBAR_DATE_FORMAT))
    local hour, minute = tonumber(date("%H")), tonumber(date("%M"))
    tt:AddDoubleLine(L.TOPBAR_LOCAL_TIME, TopBar.FormatClock(hour, minute, TopBar.db.use24h), 0.8, 0.8, 0.8, 1, 1, 1)
    if _G.GetGameTime then
        local sh, sm = GetGameTime()
        tt:AddDoubleLine(L.TOPBAR_SERVER_TIME, TopBar.FormatClock(sh, sm, TopBar.db.use24h), 0.8, 0.8, 0.8, 1, 1, 1)
    end
    if _G.IsResting and IsResting() then tt:AddLine(L.TOPBAR_RESTING, 0.5, 0.8, 1) end
    tt:AddLine(L.TOPBAR_CLOCK_TIP, 0.5, 0.5, 0.5)
end

function TOOLTIP.durability(tt) tt:AddLine(L.TOPBAR_DURABILITY_TIP) end

function TOOLTIP.gold(tt)
    tt:AddLine(L.TOPBAR_GOLD_TIP)
    tt:AddLine(NS.FormatMoney(GetMoney()), 1, 1, 1)
end

function TOOLTIP.bags(tt) tt:AddLine(L.TOPBAR_BAGS_TIP) end

function TOOLTIP.perf(tt)
    local _, _, home, world = GetNetStats()
    tt:AddDoubleLine(L.TOPBAR_FPS, string.format("%.0f", GetFramerate()), 0.8, 0.8, 0.8, 1, 1, 1)
    tt:AddDoubleLine(L.TOPBAR_LATENCY_HOME, (home or 0) .. " " .. L.TOPBAR_MS, 0.8, 0.8, 0.8, 1, 1, 1)
    tt:AddDoubleLine(L.TOPBAR_LATENCY_WORLD, (world or 0) .. " " .. L.TOPBAR_MS, 0.8, 0.8, 0.8, 1, 1, 1)
    local list = TopBar.ScanMemory(10)
    if #list > 0 then
        tt:AddLine(" ")
        tt:AddLine(L.TOPBAR_MEMORY)
        for _, entry in ipairs(list) do
            tt:AddDoubleLine(entry.name, FormatMemory(entry.kb), 1, 1, 1, 0.8, 0.8, 0.8)
        end
    end
    tt:AddLine(L.TOPBAR_PERF_TIP, 0.5, 0.5, 0.5)
end

function TOOLTIP.travel(tt) tt:AddLine(L.TOPBAR_TRAVEL_TIP) end

function TOOLTIP.hearth(tt) tt:AddLine(L.TOPBAR_HEARTH_TIP) end

for _, slot in ipairs({ "extraLeft", "extraRight" }) do
    TOOLTIP[slot] = function(tt)
        local def = Extra(slot)
        if def and def.tooltip then def.tooltip(tt) end
    end
    CLICK[slot] = function(button, mouseButton)
        local def = Extra(slot)
        if def and def.click then def.click(button, mouseButton) end
    end
end

CLICK.friends = NS.ToggleFriends
CLICK.guild = NS.ToggleGuild
CLICK.clock = NS.ToggleClock
CLICK.durability = NS.ToggleCharacterSheet
CLICK.bags = NS.ToggleBags

function CLICK.perf()
    if IsShiftKeyDown() then
        collectgarbage("collect")
        NS.Print(L.TOPBAR_MEMORY_FREED)
    end
    lastMemoryScan = -1000
end

function CLICK.travel()
    -- Afficher une frame qui contient des boutons sécurisés est interdit en combat.
    if NS.InCombat() or not travelMenu then return end
    travelMenu:SetShown(not travelMenu:IsShown())
end

local function ShowTooltip(button)
    local fill = TOOLTIP[button.key]
    if not fill then return end
    -- Les listes (guilde, amis, mémoire) coûtent : pas en combat.
    if NS.InCombat() and (button.key == "guild" or button.key == "friends" or button.key == "perf") then return end
    local extra = TopBar.db[button.key] and NS.DataTexts:Get(TopBar.db[button.key])
    if NS.InCombat() and extra and extra.noCombatTooltip then return end
    GameTooltip:SetOwner(button, TopBar.db.position == "TOP" and "ANCHOR_BOTTOM" or "ANCHOR_TOP")
    GameTooltip:ClearLines()
    fill(GameTooltip)
    GameTooltip:Show()
end

local function HideTooltip() GameTooltip:Hide() end

--------------------------------------------------------------------------------
-- Menu Voyage
--------------------------------------------------------------------------------

--- Sorts de voyage connus du personnage.
function TopBar.TravelEntries()
    local list = {}
    for _, id in ipairs(TRAVEL_SPELLS) do
        if NS.KnowsSpell(id) then list[#list + 1] = id end
    end
    return list
end

local function TravelButton(index)
    local button = travelButtons[index]
    if button then return button end
    button = CreateFrame("Button", "AeonUITravelButton" .. index, travelMenu, "SecureActionButtonTemplate")
    button:SetSize(TRAVEL_SIZE, TRAVEL_SIZE)
    button:RegisterForClicks("AnyUp", "AnyDown")
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetAllPoints()
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    button.cooldown:SetAllPoints()
    NS.RegisterCooldown(button.cooldown)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        if GameTooltip.SetSpellByID then GameTooltip:SetSpellByID(self.spellID) end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", HideTooltip)
    -- Après le lancement (clic sécurisé), refermer le menu : hors combat, c'est permis.
    -- Au relâchement seulement : sans ActionButtonUseKeyDown, le sort part au relâchement, et
    -- un menu fermé à l'appui ne le recevrait jamais.
    button:HookScript("PostClick", function(_, _, down)
        if not down and not NS.InCombat() then travelMenu:Hide() end
    end)
    travelButtons[index] = button
    return button
end

--- (Re)construit le menu Voyage. Hors combat seulement : ce sont des boutons sécurisés.
local function BuildTravel()
    local entries = TopBar.TravelEntries()
    for i, id in ipairs(entries) do
        local button = TravelButton(i)
        button.spellID = id
        button:SetAttribute("type", "spell")
        button:SetAttribute("spell", id)
        button.icon:SetTexture(C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)
            or (_G.GetSpellTexture and GetSpellTexture(id)))
        button:ClearAllPoints()
        local col, row = (i - 1) % TRAVEL_COLUMNS, math.floor((i - 1) / TRAVEL_COLUMNS)
        button:SetPoint("TOPLEFT", travelMenu, "TOPLEFT", 6 + col * (TRAVEL_SIZE + 4), -6 - row * (TRAVEL_SIZE + 4))
        button:Show()
    end
    for i = #entries + 1, #travelButtons do travelButtons[i]:Hide() end
    local rows = math.max(1, math.ceil(#entries / TRAVEL_COLUMNS))
    local cols = math.max(1, math.min(TRAVEL_COLUMNS, #entries))
    travelMenu:SetSize(8 + cols * (TRAVEL_SIZE + 4), 8 + rows * (TRAVEL_SIZE + 4))
    return #entries
end

--- Temps de recharge affichés à l'ouverture (hors combat : valeurs lisibles).
local function RefreshTravelCooldowns()
    for _, button in ipairs(travelButtons) do
        if button:IsShown() and button.spellID then
            local start, duration = 0, 0
            if C_Spell and C_Spell.GetSpellCooldown then
                local info = C_Spell.GetSpellCooldown(button.spellID)
                if info then start, duration = info.startTime, info.duration end
            elseif _G.GetSpellCooldown then
                start, duration = GetSpellCooldown(button.spellID)
            end
            if not NS.IsSecret(start) and not NS.IsSecret(duration) then
                button.cooldown:SetCooldown(start or 0, duration or 0)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

local LEFT_ORDER = { "friends", "guild", "extraLeft" }
local RIGHT_ORDER = { "extraRight", "gold", "durability", "bags", "perf", "travel" }   -- de gauche à droite, avant le foyer
local TEXT_KEYS = { "friends", "guild", "clock", "gold", "durability", "bags", "perf", "travel", "extraLeft", "extraRight" }

local function CreateElement(key)
    -- Perf : fille d'UIParent, ancrée à la barre : elle peut rester visible quand la barre
    -- se masque en combat (state driver sur la barre seule).
    local button = CreateFrame("Button", nil, key == "perf" and UIParent or bar)
    button.key = key
    button:SetHeight(BAR_HEIGHT)
    if key == "perf" then
        button:SetFrameStrata("LOW")
        button:SetFrameLevel(5)
    end
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button.label = Media:CreateText(button, "OVERLAY")
    button.label:SetPoint("CENTER")
    button:SetScript("OnEnter", ShowTooltip)
    button:SetScript("OnLeave", HideTooltip)
    if CLICK[key] then
        button:SetScript("OnClick", function(self, mouseButton) CLICK[key](self, mouseButton) end)
    end
    elements[key] = button
    return button
end

local function Build()
    bar = CreateFrame("Frame", "AeonUITopBar", UIParent)
    bar:SetHeight(BAR_HEIGHT)
    bar:SetFrameStrata("LOW")
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()
    bar.line = bar:CreateTexture(nil, "BORDER")
    bar.line:SetHeight(1)

    for _, key in ipairs(TEXT_KEYS) do CreateElement(key) end

    -- Foyer : bouton sécurisé, taille fixe, ancré au bord de la barre et à rien d'autre.
    hearth = CreateFrame("Button", "AeonUITopBarHearth", bar, "SecureActionButtonTemplate")
    hearth.key = "hearth"
    hearth:SetSize(HEARTH_WIDTH, BAR_HEIGHT)
    hearth:RegisterForClicks("AnyUp", "AnyDown")
    hearth:SetAttribute("type", "item")
    hearth:SetAttribute("item", "item:" .. HEARTHSTONE)
    hearth.label = Media:CreateText(hearth, "OVERLAY")
    hearth.label:SetPoint("CENTER")
    hearth:SetScript("OnEnter", ShowTooltip)
    hearth:SetScript("OnLeave", HideTooltip)

    -- Menu Voyage : fermé d'office en combat par un state driver (OnEnable).
    travelMenu = CreateFrame("Frame", "AeonUITravel", bar)
    travelMenu:SetFrameStrata("DIALOG")
    travelMenu.bg = travelMenu:CreateTexture(nil, "BACKGROUND")
    travelMenu.bg:SetAllPoints()
    NS.SetSolidColor(travelMenu.bg, 0.04, 0.05, 0.07, 0.92)
    travelMenu:SetScript("OnShow", RefreshTravelCooldowns)
    travelMenu:Hide()
    tinsert(UISpecialFrames, "AeonUITravel")   -- Échap ferme le menu
end

--------------------------------------------------------------------------------
-- Minimap
--------------------------------------------------------------------------------
-- En haut de l'écran, la barre recouvre le nom de zone et les boutons du haut de la
-- minimap. On descend MinimapCluster de la hauteur de la barre, en gardant son ancrage
-- d'origine pour le rendre au disable. Si Blizzard le repositionne (Edit Mode, changement
-- de zone), le hook reprend la nouvelle position comme base et redécale.

local minimapBase        -- { point, relativeTo, relativePoint, x, y } avant décalage
local minimapShifting = false
local minimapHooked = false

local function WantMinimapShift()
    return active and TopBar.db.position == "TOP" and TopBar.db.shiftMinimap
end

local function ApplyMinimapShift()
    local cluster = _G.MinimapCluster
    if not cluster or not minimapBase then return end
    minimapShifting = true
    cluster:ClearAllPoints()
    local p = minimapBase
    local y = (p[5] or 0) - (WantMinimapShift() and BAR_HEIGHT or 0)
    cluster:SetPoint(p[1], p[2], p[3], p[4] or 0, y)
    minimapShifting = false
end

local function UpdateMinimapShift()
    local cluster = _G.MinimapCluster
    -- Sur un client à Edit Mode, MinimapCluster est un système géré : un ancrage posé par un
    -- addon casse l'enregistrement des dispositions. Le joueur la place lui-même.
    if C_EditMode then return end
    -- Un ancrage multiple (cadre étiré) ne se décale pas proprement : on n'y touche pas.
    if not cluster or (cluster.GetNumPoints and cluster:GetNumPoints() ~= 1) then return end
    if not minimapBase then
        if not WantMinimapShift() then return end
        minimapBase = { cluster:GetPoint(1) }
    end
    if not minimapHooked then
        minimapHooked = true
        hooksecurefunc(cluster, "SetPoint", function(frame)
            if minimapShifting or not WantMinimapShift() then return end
            minimapBase = { frame:GetPoint(1) }
            NS:RunOutOfCombat(ApplyMinimapShift)
        end)
    end
    ApplyMinimapShift()
    if not WantMinimapShift() then minimapBase = nil end
end

--------------------------------------------------------------------------------
-- Agencement (hors combat uniquement)
--------------------------------------------------------------------------------

local function ApplyVisibilityDrivers()
    if not _G.RegisterStateDriver then return end
    -- Le menu Voyage est toujours fermé en combat ; la barre seulement sur option.
    RegisterStateDriver(travelMenu, "visibility", "[combat] hide")
    local db = TopBar.db
    if db.hideInCombat then
        RegisterStateDriver(bar, "visibility", "[combat] hide; show")
    else
        UnregisterStateDriver(bar, "visibility")
        bar:Show()
    end
    if db.hideInCombat and db.show.perf and not db.perfInCombat then
        RegisterStateDriver(elements.perf, "visibility", "[combat] hide; show")
    else
        UnregisterStateDriver(elements.perf, "visibility")
    end
end

local function Layout()
    local db = TopBar.db
    local free = db.position == "FREE"
    if free then
        -- Mobile seulement en mode libre : le calque de déverrouillage n'existe qu'alors.
        NS.Movers:Register("topbar", bar, L.MOVER_TOPBAR, "TOP", 0, -20)
        NS.Movers:Load("topbar")
    else
        NS.Movers:Unregister("topbar")
        bar:ClearAllPoints()
        bar:SetPoint(db.position .. "LEFT", UIParent, db.position .. "LEFT", 0, 0)
        bar:SetPoint(db.position .. "RIGHT", UIParent, db.position .. "RIGHT", 0, 0)
    end
    NS.SetSolidColor(bar.bg, 0.04, 0.05, 0.07, db.backgroundAlpha)
    local r, g, b = Media:Accent()
    NS.SetSolidColor(bar.line, r, g, b, 0.8)
    bar.line:ClearAllPoints()
    local edge = db.position ~= "BOTTOM" and "BOTTOM" or "TOP"
    bar.line:SetPoint(edge .. "LEFT", bar, edge .. "LEFT")
    bar.line:SetPoint(edge .. "RIGHT", bar, edge .. "RIGHT")

    local show = {}
    for key, value in pairs(db.show) do show[key] = value end
    show.travel = show.travel and BuildTravel() > 0
    show.extraLeft, show.extraRight = Extra("extraLeft") ~= nil, Extra("extraRight") ~= nil

    local x = 6
    for _, key in ipairs(LEFT_ORDER) do
        local button = elements[key]
        button:ClearAllPoints()
        if show[key] then
            button:SetPoint("LEFT", bar, "LEFT", x, 0)
            button:Show()
            x = x + (button:GetWidth() or 0)
        else
            button:Hide()
        end
    end
    -- Rangées posées par d'autres modules (micro-menu, sacs), après les textes de gauche.
    for _, key in ipairs(DOCK_ORDER) do
        local frame = docked[key]
        if frame then
            frame:SetParent(bar)
            frame:ClearAllPoints()
            frame:SetPoint("LEFT", bar, "LEFT", x + 4, 0)
            frame:Show()
            x = x + (frame:GetWidth() or 0) + 8
        end
    end
    local leftWidth = x

    elements.clock:ClearAllPoints()
    elements.clock:SetPoint("CENTER", bar, "CENTER")
    elements.clock:SetShown(show.clock)

    hearth:ClearAllPoints()
    hearth:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
    hearth:SetShown(show.hearth)

    -- Les éléments de droite s'ancrent à la barre, jamais au foyer : une frame ancrée à
    -- une frame sécurisée devient elle-même verrouillée en combat.
    local offset = -4 - (show.hearth and HEARTH_WIDTH or 0)
    local travelOffset = offset
    for i = #RIGHT_ORDER, 1, -1 do
        local key = RIGHT_ORDER[i]
        local button = elements[key]
        button:ClearAllPoints()
        if show[key] then
            button:SetPoint("RIGHT", bar, "RIGHT", offset, 0)
            button:Show()
            if key == "travel" then travelOffset = offset end
            offset = offset - (button:GetWidth() or 0)
        else
            button:Hide()
        end
    end

    travelMenu:ClearAllPoints()
    if db.position ~= "BOTTOM" then
        travelMenu:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", travelOffset, -4)
    else
        travelMenu:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", travelOffset, 4)
    end
    if not show.travel then travelMenu:Hide() end

    -- Libre : largeur ajustée au contenu, l'horloge restant centrée.
    if free then
        local clockWidth = show.clock and (elements.clock:GetWidth() or 0) or 0
        bar:SetWidth(2 * math.max(leftWidth, -offset) + clockWidth + 2 * PADDING)
    end

    ApplyVisibilityDrivers()
    UpdateMinimapShift()
end

local function SetElementText(key, text)
    local button = elements[key]
    if button.label:GetText() == text then return false end
    button.label:SetText(text)
    local width = math.ceil((button.label:GetStringWidth() or 0) + PADDING * 2)
    local changed = math.abs((button:GetWidth() or 0) - width) > 0.5
    button:SetWidth(width)
    return changed
end

local layoutQueued = false

--- Met à jour les textes ; ré-agence si une largeur a changé (hors combat).
function TopBar:Update(keys)
    if not active then return end
    local resized = false
    for _, key in ipairs(keys or TEXT_KEYS) do
        if SetElementText(key, TEXT[key]()) then resized = true end
    end
    hearth.label:SetText(HearthText())
    if resized and not layoutQueued then
        -- Un seul Layout en file : le ticker 1 Hz en empilerait un par seconde de combat.
        layoutQueued = true
        NS:RunOutOfCombat(function()
            layoutQueued = false
            Layout()
        end)
    end
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

local EVENT_KEYS = {
    FRIENDLIST_UPDATE = { "friends" },
    BN_FRIEND_INFO_CHANGED = { "friends" },
    BN_FRIEND_ACCOUNT_ONLINE = { "friends" },
    BN_FRIEND_ACCOUNT_OFFLINE = { "friends" },
    GUILD_ROSTER_UPDATE = { "guild" },
    PLAYER_GUILD_UPDATE = { "guild" },
    PLAYER_MONEY = { "gold" },
    UPDATE_INVENTORY_DURABILITY = { "durability" },
    PLAYER_EQUIPMENT_CHANGED = { "durability" },
    BAG_UPDATE_DELAYED = { "bags" },
    PLAYER_UPDATE_RESTING = { "clock" },
    BAG_UPDATE_COOLDOWN = {},
}

-- Inscription au registre partagé : les panneaux de données réutilisent ces textes.
do
    local eventsOf = {}
    for event, keys in pairs(EVENT_KEYS) do
        for _, key in ipairs(keys) do
            eventsOf[key] = eventsOf[key] or {}
            table.insert(eventsOf[key], event)
        end
    end
    local noCombat = { friends = true, guild = true, perf = true }   -- listes coûteuses
    local interval = { clock = 1, perf = 1 }
    for _, key in ipairs({ "friends", "guild", "clock", "gold", "durability", "bags", "perf" }) do
        NS.DataTexts:Register(key, {
            text = TEXT[key], tooltip = TOOLTIP[key], click = CLICK[key],
            events = eventsOf[key], interval = interval[key], noCombatTooltip = noCombat[key],
        })
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(_, event)
    if event == "SPELLS_CHANGED" then
        NS:RunOutOfCombat(Layout)   -- un nouveau sort de voyage appris
        return
    end
    TopBar:Update(EVENT_KEYS[event])
end)

function TopBar:OnEnable()
    if not bar then Build() end
    for event in pairs(EVENT_KEYS) do NS.RegisterEventSafe(eventFrame, event) end
    NS.RegisterEventSafe(eventFrame, "PLAYER_ENTERING_WORLD")
    NS.RegisterEventSafe(eventFrame, "SPELLS_CHANGED")
    RequestRoster(true)
    ticker = C_Timer.NewTicker(1, function()
        TopBar:Update({ "clock", "perf", "extraLeft", "extraRight" })   -- ponytail: emplacements libres à 1 Hz, pas leurs événements
    end)
    bar:Show()
    active = true
    self:Update()
    Layout()
end

function TopBar:OnDisable()
    active = false
    eventFrame:UnregisterAllEvents()
    if ticker then ticker:Cancel() ticker = nil end
    if bar then
        if _G.UnregisterStateDriver then
            UnregisterStateDriver(bar, "visibility")
            UnregisterStateDriver(travelMenu, "visibility")
            UnregisterStateDriver(elements.perf, "visibility")
        end
        travelMenu:Hide()
        elements.perf:Hide()   -- fille d'UIParent, pas de la barre
        bar:Hide()
    end
    UpdateMinimapShift()   -- active = false : rend la position d'origine
end

function TopBar:OnRefresh()
    for _, button in pairs(elements) do button.label:SetText(nil) end
    self:Update()
    Layout()
end

function TopBar:GetFrame() return bar, elements, hearth, travelMenu end

-- Hauteur des boutons d'une rangée posée dans la barre.
TopBar.DOCK_SIZE = BAR_HEIGHT - 2

--- Pose `frame` dans la barre (hors combat : la rangée peut porter des boutons sécurisés).
function TopBar:Dock(key, frame)
    docked[key] = frame
    if active then Layout() end
end

--- Retire la rangée `key` : rendue à UIParent, cachée ; son module la replace s'il la garde.
function TopBar:Undock(key)
    local frame = docked[key]
    if not frame then return end
    docked[key] = nil
    frame:SetParent(UIParent)
    frame:Hide()
    if active then Layout() end
end

NS:On("UNLOCK", function()
    if active then NS:RunOutOfCombat(Layout) end
end)

--------------------------------------------------------------------------------
-- Options
--------------------------------------------------------------------------------

function TopBar:BuildOptions(o)
    o:Dropdown("position", L.OPT_TOPBAR_POSITION, {
        { name = L.OPT_TOP, value = "TOP" }, { name = L.OPT_BOTTOM, value = "BOTTOM" },
        { name = L.OPT_FREE, value = "FREE" },
    })
    o:Button(L.OPT_UNLOCK, function() NS:SetUnlocked(not NS.unlocked) end, 36)
    o:Button(L.OPT_TOPBAR_RESET_POSITION, function()
        NS.Movers:Reset("topbar")
        NS.Modules:Refresh("topbar")
    end, 36)
    o:Slider("backgroundAlpha", L.OPT_TOPBAR_ALPHA, 0, 1, 0.05, 20, "%.2f")
    if not C_EditMode then o:Check("shiftMinimap", L.OPT_TOPBAR_MINIMAP) end
    o:Check("hideInCombat", L.OPT_TOPBAR_HIDE_COMBAT)
    o:Check("perfInCombat", L.OPT_TOPBAR_PERF_COMBAT, 36)
    o.layout:Hint(L.HINT_TOPBAR_PERF_COMBAT)   -- grisée tant que la barre reste visible en combat
    o:Title(L.OPT_TOPBAR_CLOCK)
    o:Check("use24h", L.OPT_TOPBAR_24H)
    o:Check("serverTime", L.OPT_TOPBAR_SERVER_TIME)
    o:Check("showResting", L.OPT_TOPBAR_RESTING)
    o:Title(L.OPT_TOPBAR_ELEMENTS)
    for _, key in ipairs({ "friends", "guild", "clock", "gold", "durability", "bags", "perf", "travel", "hearth" }) do
        o:Check("show." .. key, L["OPT_TOPBAR_SHOW_" .. key:upper()])
    end
    local choices = function() return NS.DataTexts:Choices(true) end
    o:Dropdown("extraLeft", L.OPT_TOPBAR_EXTRA_LEFT, choices)
    o:Dropdown("extraRight", L.OPT_TOPBAR_EXTRA_RIGHT, choices)
end

-- Modules/GroupFrames.lua
-- Cadres de groupe et de raid AeonUI : en-têtes SecureGroupHeaderTemplate (groupe, raid, tanks
-- et assistants principaux) dont chaque bouton (SecureUnitButtonTemplate : clic gauche cible, clic
-- droit menu) reçoit les éléments de NS.UnitFrameElements plus : rôle, chef, menace, dispel, portée,
-- icône d'état (appel, invocation, résurrection).
--
-- L'en-tête crée et ordonne ses boutons lui-même, hors combat, d'après ses attributs ; un hook
-- de SecureGroupHeader_Update habille chaque bouton neuf (ce moteur n'a pas de loadstring :
-- aucun snippet restreint, donc pas d'initialConfigFunction), une fois par bouton. Les événements d'unité sont reçus
-- par un seul écouteur et routés par jeton (byUnit) : le jeton d'un bouton change avec le tri, et
-- une unité peut avoir deux boutons (raid et tanks principaux).
local _, NS = ...
local L = NS.L
local Elements = NS.UnitFrameElements
local Movers = NS.Movers

local GroupFrames = NS.Modules:Register("groupframes", {
    reloadOnDisable = true,   -- cadres Blizzard rendus au /reload seulement : les options le proposent
    titleKey = "GROUPFRAMES_TITLE",
    descKey = "GROUPFRAMES_DESC",
    yieldsTo = { "ElvUI" },
    secure = true,
    defaults = {
        enabled = false,
        width = 90, height = 36, powerHeight = 4, spacing = 4,
        showPlayer = true, showSolo = false,
        horizontal = false,             -- groupe : colonne (false) ou ligne (true)
        raidUnitsPerColumn = 5, raidColumns = 8, raidSortBy = "GROUP",   -- "GROUP" | "CLASS" | "ROLE" | "NAME"
        raidThreshold = 5,              -- cadres de raid au-delà de 5, 10 ou 40 membres (en dessous : disposition du groupe)
        nameLength = 8,                 -- caractères du nom (0 = entier)
        roleIcons = true, dispel = true, aggro = true,
        aggroStyle = "border",          -- "border" | "glow" : menace en bordure ou en lueur
        statusIcons = true,             -- appel, invocation, résurrection au centre
        healPrediction = true,          -- soins entrants et absorptions
        mainTanks = false, mainAssists = false,   -- raid : cadres des tanks et assistants principaux
        range = true, rangeAlpha = 0.4,
        healthText = "none", classColor = true, healthGradient = false, power = true,
        hideBlizzard = true,
    },
})

GroupFrames.headers = {}
local byUnit = {}               -- [jeton] = { [bouton] = true }
GroupFrames.byUnit = byUnit
local readyCheck = false        -- appel en cours ou résultat encore affiché
local readyFinished = false     -- appel fini : état mémorisé, « en attente » devient « pas prêt »
local readyToken = 0

--- Appelle fn(bouton) pour chaque bouton de l'unité, ou de toutes si unit est nil.
local function ForEach(unit, fn)
    if unit then
        for button in pairs(byUnit[unit] or {}) do fn(button) end
        return
    end
    for _, set in pairs(byUnit) do
        for button in pairs(set) do fn(button) end
    end
end

local active = false
local rangeTicker

local HEADER_KEYS = { "party", "raid", "tank", "assist" }
-- Tanks et assistants principaux : filtre d'en-tête, option, visible en raid seulement.
local ROLE_HEADERS = { tank = { filter = "MAINTANK", option = "mainTanks" },
                       assist = { filter = "MAINASSIST", option = "mainAssists" } }
GroupFrames.ROLE_HEADERS = ROLE_HEADERS

-- Chemins de fichiers, pas les globales READY_CHECK_*_TEXTURE (des noms d'atlas sur les clients récents).
local READY_TEXTURES = {
    ready = "Interface\\RaidFrame\\ReadyCheck-Ready",
    notready = "Interface\\RaidFrame\\ReadyCheck-NotReady",
    waiting = "Interface\\RaidFrame\\ReadyCheck-Waiting",
}
local REZ_TEXTURE = "Interface\\RaidFrame\\Raid-Icon-Rez"
-- Enum.SummonStatus : 1 en attente, 2 accepté, 3 refusé.
local SUMMON_ATLAS = { [1] = "Raid-Icon-SummonPending", [2] = "Raid-Icon-SummonAccepted", [3] = "Raid-Icon-SummonDeclined" }
local THREAT_COLORS = { [2] = { 1, 0.6, 0 }, [3] = { 0.9, 0.2, 0.2 } }   -- 2 agro instable, 3 agro ferme
local READY_LINGER = 6          -- secondes d'affichage du résultat de l'appel

local ROLE_ICON = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES"
local ROLE_COORDS = {
    TANK = { 0, 19 / 64, 22 / 64, 41 / 64 },
    HEALER = { 20 / 64, 39 / 64, 1 / 64, 20 / 64 },
    DAMAGER = { 20 / 64, 39 / 64, 22 / 64, 41 / 64 },
}
local LEADER_ICON = "Interface\\GroupFrame\\UI-Group-LeaderIcon"

GroupFrames.DISPEL_BY_CLASS = NS.DISPEL_BY_CLASS   -- table partagée (Core/Compat.lua)

local BLIZZARD = { "PartyFrame", "CompactPartyFrame", "CompactRaidFrameContainer" }

local function Known(value)
    if NS.IsSecret(value) or value == nil then return nil end
    return value
end

--------------------------------------------------------------------------------
-- Boutons
--------------------------------------------------------------------------------

local function Config()
    local db = GroupFrames.db
    return {
        width = db.width, height = db.height, power = db.power, powerHeight = db.powerHeight,
        castbar = false, auras = false, name = true, level = false, combo = false, portrait = false,
        nameLength = (tonumber(db.nameLength) or 0) > 0 and db.nameLength or nil,
    }
end

local function PlayerDispels()
    local _, classFile = UnitClass("player")
    classFile = Known(classFile)
    return classFile and GroupFrames.DISPEL_BY_CLASS[classFile] or nil
end

--- Type de débuff dissipable par le joueur porté par l'unité, ou nil.
function GroupFrames.DispellableType(unit)
    local dispels = PlayerDispels()
    if not dispels then return nil end
    for i = 1, 40 do
        local icon, _, _, _, dispelName = NS.GetDebuff(unit, i)
        if not NS.IsSecret(icon) and icon == nil then return nil end
        dispelName = Known(dispelName)
        if dispelName and dispels[dispelName] then return dispelName end
    end
    return nil
end

local function PaintBorder(button, r, g, b)
    if not button.border then return end
    for _, edge in pairs(button.border) do NS.SetSolidColor(edge, r, g, b, 1) end
end

--- Niveau de menace affichable (2 ou 3), sinon nil. Statut secret : rien.
local function Threat(unit)
    if not _G.UnitThreatSituation then return nil end
    local ok, status = pcall(UnitThreatSituation, unit)
    status = ok and Known(status) or nil
    return status and THREAT_COLORS[status] and status or nil
end

function GroupFrames:UpdateBorder(button)
    local unit = button.unit
    if not unit then return end
    local db = self.db
    local threat = db.aggro and Threat(unit)
    local glow = db.aggroStyle == "glow"
    if button.glow then
        if threat and glow then
            local c = THREAT_COLORS[threat]
            NS.SetSolidColor(button.glow, c[1], c[2], c[3], 0.6)
            button.glow:Show()
        else
            button.glow:Hide()
        end
    end
    if threat and not glow then
        local c = THREAT_COLORS[threat]
        PaintBorder(button, c[1], c[2], c[3])
        return
    end
    if db.dispel then
        local kind = GroupFrames.DispellableType(unit)
        local color = kind and _G.DebuffTypeColor and DebuffTypeColor[kind]
        if color then PaintBorder(button, color.r, color.g, color.b) return end
    end
    local c = NS.db.theme.border
    PaintBorder(button, c.r, c.g, c.b)
end

function GroupFrames:UpdateRole(button)
    local unit = button.unit
    if not unit or not self.db.roleIcons then button.role:Hide() button.leader:Hide() return end
    local role = _G.UnitGroupRolesAssigned and Known(UnitGroupRolesAssigned(unit)) or nil
    if (role == nil or role == "NONE") and _G.GetPartyAssignment then
        local ok, mainTank = pcall(GetPartyAssignment, "MAINTANK", unit)
        if ok and Known(mainTank) then role = "TANK" end
    end
    local coords = role and ROLE_COORDS[role]
    if coords then
        button.role:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
        button.role:Show()
    else
        button.role:Hide()
    end
    local leader = _G.UnitIsGroupLeader and Known(UnitIsGroupLeader(unit)) or nil
    button.leader:SetShown(leader and true or false)
end

--- Icône centrale : résultat d'appel, sinon invocation, sinon résurrection. Valeur secrète : rien.
function GroupFrames:UpdateStatus(button)
    local unit, icon = button.unit, button.status
    if not icon then return end
    icon:Hide()
    if not unit or not self.db.statusIcons then return end
    if readyCheck then
        -- Après la fin, l'API peut ne plus répondre : l'état mémorisé prend le relais.
        local state = _G.GetReadyCheckStatus and Known(GetReadyCheckStatus(unit)) or nil
        if state then button.readyState = state end
        state = state or button.readyState
        if readyFinished and state == "waiting" then state = "notready" end
        if state and READY_TEXTURES[state] then
            icon:SetTexCoord(0, 1, 0, 1)   -- efface le cadrage d'un atlas précédent
            icon:SetTexture(READY_TEXTURES[state])
            icon:Show()
            return
        end
    end
    if _G.C_IncomingSummon and C_IncomingSummon.IncomingSummonStatus then
        local ok, status = pcall(C_IncomingSummon.IncomingSummonStatus, unit)
        status = ok and Known(status) or nil
        -- Atlas absent sur ce client : SetAtlas rend false, rien n'est montré.
        if status and SUMMON_ATLAS[status] and icon.SetAtlas and icon:SetAtlas(SUMMON_ATLAS[status]) then
            icon:Show()
            return
        end
    end
    if _G.UnitHasIncomingResurrection and Known(UnitHasIncomingResurrection(unit)) then
        icon:SetTexCoord(0, 1, 0, 1)
        icon:SetTexture(REZ_TEXTURE)
        icon:Show()
    end
end

function GroupFrames:UpdateRange(button)
    local unit = button.unit
    if not unit or not self.db.range then button:SetAlpha(1) return end
    NS.SetRangeAlpha(button, unit, self.db.rangeAlpha)   -- portée secrète : le moteur choisit l'alpha
end

function GroupFrames:UpdateAll(button)
    if not button.unit then return end
    Elements.UpdateHealth(button)
    Elements.UpdatePower(button)
    Elements.UpdateName(button)
    Elements.UpdateRaidIcon(button)
    self:UpdateRole(button)
    self:UpdateBorder(button)
    self:UpdateStatus(button)
    self:UpdateRange(button)
end

local function OnUnitChanged(button, name, value)
    if name ~= "unit" then return end
    local old = button.unit
    if old and byUnit[old] then
        byUnit[old][button] = nil
        if not next(byUnit[old]) then byUnit[old] = nil end
    end
    button.unit = value
    button.readyState = nil      -- l'état d'appel suit l'unité, pas le bouton
    if value then
        byUnit[value] = byUnit[value] or {}
        byUnit[value][button] = true
        if active then GroupFrames:UpdateAll(button) end
    end
end

--- Habille un bouton créé par l'en-tête, hors combat (voir StyleChildren).
local function Style(header, buttonName)
    local button = _G[buttonName]
    if not button or button.styled then return end
    button.styled = true
    button.header = header
    button.cfg, button.global = Config(), GroupFrames.db
    -- La bordure du fond sert d'indicateur (agro, dispel) : THEME_CHANGED la repeint à la
    -- couleur du thème, puis Reconcile la recolore.
    local _, edges = NS.Media:CreateBackdrop(button)
    button.border = edges
    -- Lueur de menace : aplat coloré qui déborde du bouton, sous le fond.
    button.glow = button:CreateTexture(nil, "BACKGROUND", nil, -8)
    button.glow:SetPoint("TOPLEFT", button, "TOPLEFT", -3, 3)
    button.glow:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 3, -3)
    button.glow:Hide()
    Elements.Build(button)
    button.status = button.overlay:CreateTexture(nil, "OVERLAY", nil, 7)
    button.status:Hide()
    button.role = button.overlay:CreateTexture(nil, "OVERLAY")
    button.role:SetTexture(ROLE_ICON)
    button.leader = button.overlay:CreateTexture(nil, "OVERLAY")
    button.leader:SetTexture(LEADER_ICON)
    Elements.Layout(button)
    local icon = NS.Pixel:Scale(12)
    button.role:SetSize(icon, icon)
    button.role:ClearAllPoints()
    button.role:SetPoint("TOPLEFT", button.health, "TOPLEFT", 1, -1)
    button.leader:SetSize(icon, icon)
    button.leader:ClearAllPoints()
    button.leader:SetPoint("TOPRIGHT", button.health, "TOPRIGHT", -1, -1)
    local status = NS.Pixel:Scale(16)
    button.status:SetSize(status, status)
    button.status:ClearAllPoints()
    button.status:SetPoint("CENTER", button.health, "CENTER", 0, 0)
    button.name:ClearAllPoints()
    button.name:SetPoint("CENTER", button.health, "CENTER", 0, 0)
    button.name:SetJustifyH("CENTER")
    button.name:SetWidth(button:GetWidth() - 4)
    button:SetScript("OnAttributeChanged", OnUnitChanged)
    header.buttons[#header.buttons + 1] = button
    local unit = button:GetAttribute("unit")
    if unit then OnUnitChanged(button, "unit", unit) end
end

local function Relayout(button)
    button.cfg, button.global = Config(), GroupFrames.db
    Elements.Layout(button)
    button.name:ClearAllPoints()
    button.name:SetPoint("CENTER", button.health, "CENTER", 0, 0)
    button.name:SetWidth(button:GetWidth() - 4)
end

--------------------------------------------------------------------------------
-- En-têtes
--------------------------------------------------------------------------------

--- Habille les boutons que l'en-tête vient de créer (hors combat : l'en-tête ne crée qu'hors
-- combat). Les attributs de clic sont posés ici ; tailles et RegisterUnitWatch viennent de
-- l'en-tête (initial-width, initial-height).
local function StyleChildren(header)
    -- Un membre qui rejoint en combat : l'en-tête crée le bouton, mais SetAttribute est bloqué.
    if NS.InCombat() then NS:RunOutOfCombat(function() StyleChildren(header) end) return end
    for _, child in ipairs({ header:GetChildren() }) do
        if not child.styled and child.GetName and child:GetName() then
            child:SetAttribute("*type1", "target")
            child:SetAttribute("*type2", "togglemenu")
            child:RegisterForClicks("AnyUp")
            Style(header, child:GetName())
        end
    end
end

local headerHooked = false

local function NewHeader(key)
    local header = CreateFrame("Frame", "AeonUI_Group_" .. key, UIParent, "SecureGroupHeaderTemplate")
    header.key = key
    header.buttons = {}
    header:SetAttribute("template", "SecureUnitButtonTemplate")
    if not headerHooked and _G.SecureGroupHeader_Update then
        headerHooked = true
        hooksecurefunc("SecureGroupHeader_Update", function(updated)
            if updated.key and GroupFrames.headers[updated.key] == updated then StyleChildren(updated) end
        end)
    end
    GroupFrames.headers[key] = header
    return header
end

local function Apply(header)
    local db = GroupFrames.db
    local S = function(n) return NS.Pixel:Scale(n) end
    header:SetAttribute("initial-width", S(db.width))
    header:SetAttribute("initial-height", S(db.height))
    header:SetAttribute("showPlayer", db.showPlayer)
    if header.key == "party" then
        -- Seuil : jusqu'à `raidThreshold` membres, un raid garde la disposition du groupe (cet
        -- en-tête montre alors les membres du raid) ; au-delà, l'en-tête de raid prend le relais.
        local threshold = tonumber(db.raidThreshold) or 5
        local aboveThreshold = "[@raid" .. (threshold + 1) .. ",exists]"
        header:SetAttribute("showParty", true)
        header:SetAttribute("showRaid", threshold > 5)
        header:SetAttribute("showSolo", db.showSolo)
        if db.horizontal then
            header:SetAttribute("point", "LEFT")
            header:SetAttribute("xOffset", S(db.spacing))
            header:SetAttribute("yOffset", 0)
            header:SetAttribute("columnAnchorPoint", "TOP")
        else
            header:SetAttribute("point", "TOP")
            header:SetAttribute("xOffset", 0)
            header:SetAttribute("yOffset", -S(db.spacing))
            header:SetAttribute("columnAnchorPoint", "LEFT")
        end
        header:SetAttribute("columnSpacing", S(db.spacing))
        header:SetAttribute("maxColumns", math.max(1, math.ceil(threshold / 5)))
        header:SetAttribute("unitsPerColumn", 5)
        header:SetAttribute("groupBy", threshold > 5 and "GROUP" or nil)
        header:SetAttribute("groupingOrder", "1,2,3,4,5,6,7,8")
        header:SetAttribute("sortMethod", "INDEX")
        if threshold > 5 then
            RegisterStateDriver(header, "visibility", aboveThreshold .. " hide; [group] show; " .. (db.showSolo and "show" or "hide"))
        else
            RegisterStateDriver(header, "visibility", "[group:raid] hide; [group:party] show; " .. (db.showSolo and "show" or "hide"))
        end
    elseif ROLE_HEADERS[header.key] then
        -- Tanks et assistants principaux : une colonne, filtrée par assignation de raid.
        header:SetAttribute("showParty", false)
        header:SetAttribute("showRaid", true)
        header:SetAttribute("showSolo", false)
        header:SetAttribute("groupFilter", ROLE_HEADERS[header.key].filter)
        header:SetAttribute("groupBy", nil)
        header:SetAttribute("sortMethod", "INDEX")
        header:SetAttribute("point", "TOP")
        header:SetAttribute("xOffset", 0)
        header:SetAttribute("yOffset", -S(db.spacing))
        header:SetAttribute("maxColumns", 1)
        header:SetAttribute("unitsPerColumn", 10)
        RegisterStateDriver(header, "visibility", "[group:raid] show; hide")
    else
        header:SetAttribute("showParty", false)
        header:SetAttribute("showRaid", true)
        header:SetAttribute("showSolo", false)
        header:SetAttribute("point", "TOP")
        header:SetAttribute("xOffset", 0)
        header:SetAttribute("yOffset", -S(db.spacing))
        header:SetAttribute("columnAnchorPoint", "LEFT")
        header:SetAttribute("columnSpacing", S(db.spacing))
        header:SetAttribute("maxColumns", db.raidColumns)
        header:SetAttribute("unitsPerColumn", db.raidUnitsPerColumn)
        if db.raidSortBy == "GROUP" then
            header:SetAttribute("groupBy", "GROUP")
            header:SetAttribute("groupingOrder", "1,2,3,4,5,6,7,8")
            header:SetAttribute("sortMethod", "INDEX")
        elseif db.raidSortBy == "CLASS" then
            header:SetAttribute("groupBy", "CLASS")
            header:SetAttribute("groupingOrder", "WARRIOR,PALADIN,DRUID,PRIEST,SHAMAN,MAGE,WARLOCK,HUNTER,ROGUE")
            header:SetAttribute("sortMethod", "NAME")
        elseif db.raidSortBy == "ROLE" then
            header:SetAttribute("groupBy", "ASSIGNEDROLE")
            header:SetAttribute("groupingOrder", "TANK,HEALER,DAMAGER,NONE")
            header:SetAttribute("sortMethod", "NAME")
        else
            header:SetAttribute("groupBy", nil)
            header:SetAttribute("sortMethod", "NAME")
        end
        local threshold = tonumber(db.raidThreshold) or 5
        if threshold > 5 then
            RegisterStateDriver(header, "visibility", "[@raid" .. (threshold + 1) .. ",exists] show; hide")
        else
            RegisterStateDriver(header, "visibility", "[group:raid] show; hide")
        end
    end
    for _, button in ipairs(header.buttons) do Relayout(button) end
end

local MOVER_DEFAULTS = { party = { "TOPLEFT", 20, -200 }, raid = { "TOPLEFT", 20, -300 },
                         tank = { "CENTER", -560, 120 }, assist = { "CENTER", -560, 260 } }

function GroupFrames:Reconcile()
    for _, key in ipairs(HEADER_KEYS) do
        local role = ROLE_HEADERS[key]
        if role and not self.db[role.option] then
            local header = self.headers[key]
            if header then
                UnregisterStateDriver(header, "visibility")
                header:Hide()
                Movers:Unregister("uf_" .. key)
            end
        else
            local header = self.headers[key] or NewHeader(key)
            Apply(header)
            local d = MOVER_DEFAULTS[key]
            Movers:Register("uf_" .. key, header, L["MOVER_UF_" .. key:upper()], d[1], d[2], d[3])
            Movers:Load("uf_" .. key)   -- visibilité : pilote d'état, jamais Show() par-dessus
        end
    end
    if self.db.hideBlizzard then
        for _, name in ipairs(BLIZZARD) do NS.HideBlizzardFrame(name) end
        NS.HideBlizzardFrame("CompactRaidFrameManager", true)
    else
        for _, name in ipairs(BLIZZARD) do NS.ShowBlizzardFrame(name) end
        NS.ShowBlizzardFrame("CompactRaidFrameManager")
    end
    ForEach(nil, function(button) self:UpdateAll(button) end)
end

--- Bouton de l'unité ; `key` choisit l'en-tête (défaut : groupe ou raid d'abord).
function GroupFrames:GetButton(unit, key)
    local found
    for button in pairs(byUnit[unit] or {}) do
        local headerKey = button.header and button.header.key
        if headerKey == key then return button end
        if not key and not ROLE_HEADERS[headerKey] then return button end
        if not key then found = found or button end
    end
    return found
end

--------------------------------------------------------------------------------
-- Événements
--------------------------------------------------------------------------------

local UNIT_EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER",
                      "UNIT_NAME_UPDATE", "UNIT_CONNECTION", "UNIT_AURA", "UNIT_THREAT_SITUATION_UPDATE",
                      "UNIT_HEAL_PREDICTION", "UNIT_ABSORB_AMOUNT_CHANGED", "INCOMING_RESURRECT_CHANGED",
                      "INCOMING_SUMMON_CHANGED", "READY_CHECK_CONFIRM" }

local function OnReadyCheck(event)
    if event == "READY_CHECK" then
        readyCheck, readyFinished, readyToken = true, false, readyToken + 1
        ForEach(nil, function(button) button.readyState = nil end)
    elseif event == "READY_CHECK_FINISHED" then
        -- Le résultat reste affiché quelques secondes, sur l'état mémorisé de chaque bouton.
        if not readyCheck then return end
        readyFinished = true
        readyToken = readyToken + 1
        local token = readyToken
        C_Timer.After(READY_LINGER, function()
            if token ~= readyToken then return end
            readyCheck, readyFinished = false, false
            ForEach(nil, function(button)
                button.readyState = nil
                GroupFrames:UpdateStatus(button)
            end)
        end)
    end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, unit)
    if not active then return end
    if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ROLES_ASSIGNED" or event == "PARTY_LEADER_CHANGED"
        or event == "PLAYER_ENTERING_WORLD" then
        ForEach(nil, function(button) GroupFrames:UpdateAll(button) end)
    elseif event == "RAID_TARGET_UPDATE" then
        ForEach(nil, Elements.UpdateRaidIcon)
    elseif event == "READY_CHECK" or event == "READY_CHECK_FINISHED" then
        OnReadyCheck(event)
        ForEach(nil, function(button) GroupFrames:UpdateStatus(button) end)
    elseif unit and byUnit[unit] then
        ForEach(unit, function(button)
            if event == "UNIT_AURA" or event == "UNIT_THREAT_SITUATION_UPDATE" then
                GroupFrames:UpdateBorder(button)
            elseif event == "INCOMING_RESURRECT_CHANGED" or event == "INCOMING_SUMMON_CHANGED"
                    or event == "READY_CHECK_CONFIRM" then
                GroupFrames:UpdateStatus(button)
            elseif not Elements.OnEvent(button, event) then
                GroupFrames:UpdateAll(button)
            end
        end)
    end
end)

local function RangeTick()
    if not active then return end
    ForEach(nil, function(button) GroupFrames:UpdateRange(button) end)
end

--------------------------------------------------------------------------------
-- Cycle de vie
--------------------------------------------------------------------------------

function GroupFrames:OnEnable()
    active = true
    self:Reconcile()
    for _, event in ipairs({ "GROUP_ROSTER_UPDATE", "PLAYER_ROLES_ASSIGNED", "PARTY_LEADER_CHANGED",
                             "PLAYER_ENTERING_WORLD", "RAID_TARGET_UPDATE", "READY_CHECK", "READY_CHECK_FINISHED" }) do
        NS.RegisterEventSafe(events, event)
    end
    for _, event in ipairs(UNIT_EVENTS) do NS.RegisterEventSafe(events, event) end
    if not rangeTicker and C_Timer and C_Timer.NewTicker then rangeTicker = C_Timer.NewTicker(0.25, RangeTick) end
end

function GroupFrames:OnDisable()
    active = false
    events:UnregisterAllEvents()
    if rangeTicker then rangeTicker:Cancel() rangeTicker = nil end
    for key, header in pairs(self.headers) do
        UnregisterStateDriver(header, "visibility")
        header:Hide()
        Movers:Unregister("uf_" .. key)
    end
    for _, name in ipairs(BLIZZARD) do NS.ShowBlizzardFrame(name) end
    NS.ShowBlizzardFrame("CompactRaidFrameManager")
    if next(self.headers) then NS.Print(L.MSG_GF_DISABLED_RELOAD) end
end

function GroupFrames:OnRefresh()
    self:Reconcile()
end

NS:On("PIXEL_CHANGED", function()
    if active then NS:RunOutOfCombat(function() if active then GroupFrames:Reconcile() end end) end
end)

--------------------------------------------------------------------------------
-- Options
--------------------------------------------------------------------------------

function GroupFrames:BuildOptions(o)
    o.layout:Note(L.NOTE_GF_RELOAD, 20)
    o:Slider("width", L.OPT_UF_WIDTH, 40, 200, 2)
    o:Slider("height", L.OPT_UF_HEIGHT, 12, 80, 1)
    o:Slider("spacing", L.OPT_GF_SPACING, 0, 20, 1)
    o:Check("power", L.OPT_UF_UNIT_POWER)
    o:Slider("powerHeight", L.OPT_UF_POWER_HEIGHT, 0, 12, 1, 36)
    o:Dropdown("healthText", L.OPT_UF_HEALTH_TEXT, Elements.TextModeChoices)
    o:Check("classColor", L.OPT_UF_CLASS_COLOR)
    o:Check("healthGradient", L.OPT_UF_HEALTH_GRADIENT)
    o:Check("healPrediction", L.OPT_UF_HEAL_PREDICTION)
    o:Slider("nameLength", L.OPT_GF_NAME_LENGTH, 0, 20, 1)
    o:Check("hideBlizzard", L.OPT_NPF_HIDE_BLIZZARD)
    o.layout:Button(L.OPT_UF_UNLOCK, function() NS:SetUnlocked(not NS.unlocked) end, 20)
    o:Tab(L.UF_UNIT_PARTY)
    o:Check("showPlayer", L.OPT_GF_SHOW_PLAYER)
    o:Check("showSolo", L.OPT_GF_SHOW_SOLO)
    o:Check("horizontal", L.OPT_GF_HORIZONTAL)
    o:Tab(L.UF_UNIT_RAID)
    o:Slider("raidUnitsPerColumn", L.OPT_GF_UNITS_PER_COLUMN, 1, 10, 1)
    o:Slider("raidColumns", L.OPT_GF_COLUMNS, 1, 8, 1)
    o:Dropdown("raidSortBy", L.OPT_GF_SORT, {
        { name = L.GF_SORT_GROUP, value = "GROUP" }, { name = L.GF_SORT_CLASS, value = "CLASS" },
        { name = L.GF_SORT_ROLE, value = "ROLE" }, { name = L.GF_SORT_NAME, value = "NAME" } })
    o:Dropdown("raidThreshold", L.OPT_GF_RAID_THRESHOLD, {
        { name = "5", value = 5 }, { name = "10", value = 10 }, { name = "40", value = 40 } })
    o:Hint(L.OPT_GF_RAID_THRESHOLD_HINT)
    o:Check("mainTanks", L.OPT_GF_MAIN_TANKS)
    o:Check("mainAssists", L.OPT_GF_MAIN_ASSISTS)
    o:Tab(L.OPT_GF_INDICATORS)
    o:Check("roleIcons", L.OPT_GF_ROLES)
    o:Check("dispel", L.OPT_GF_DISPEL)
    o:Check("aggro", L.OPT_GF_AGGRO)
    o:Dropdown("aggroStyle", L.OPT_GF_AGGRO_STYLE, {
        { name = L.GF_AGGRO_BORDER, value = "border" }, { name = L.GF_AGGRO_GLOW, value = "glow" } }, 36)
    o:Check("statusIcons", L.OPT_GF_STATUS_ICONS)
    o:Check("range", L.OPT_GF_RANGE)
    o:Slider("rangeAlpha", L.OPT_GF_RANGE_ALPHA, 0.1, 0.9, 0.1, 36, "%.1f")
end

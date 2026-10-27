-- Modules/RaidUtility.lua
-- Utilitaire de raid : un bouton « Raid » sur son mover, visible en groupe, qui ouvre un panneau :
-- appel prêt, vérification des rôles, compte à rebours, marqueurs de cible et marqueurs au sol.
-- Variante « bande » : une seule ligne toujours ouverte, marqueur de cible et au sol sur le même
-- bouton. En raid sans être chef ni assistant, rien n'est montré (le serveur refuserait).
--
-- Module `secure` : les marqueurs au sol sont des boutons d'action sécurisés (PlaceRaidMarker est
-- protégé). La visibilité suit un state driver « [group] », valable en combat ; ouvrir ou fermer
-- le panneau, en revanche, se fait hors combat (panneau protégé par ses boutons sécurisés).
local _, NS = ...
local L = NS.L
local Media = NS.Media

local RaidUtility = NS.Modules:Register("raidutility", {
    titleKey = "RAIDUTILITY_TITLE",
    descKey = "RAIDUTILITY_DESC",
    secure = true,
    defaults = {
        enabled = false,
        countdown = 5,     -- trois comptes à rebours prêts à lancer (secondes)
        countdown2 = 10,
        countdown3 = 15,
        countdownKey = "",   -- touche de chaque compte à rebours, "" : aucune
        countdown2Key = "",
        countdown3Key = "",
        layout = "panel",    -- "panel" : bouton et panneau ; "band" : bande compacte d'une ligne
        show = "group",      -- "group" | "raid" | "always"
        bandScale = 1,
        toggleKey = "",      -- touche qui ouvre ou ferme le panneau
        panelScale = 1,      -- échelle du panneau (disposition « panel »)
        showRoleCheck = true,   -- boutons du panneau affichables un par un
        showConvert = true,
        showDisband = true,
    },
})

local COUNTDOWN_KEYS = { "countdown", "countdown2", "countdown3" }

local ICON_PATH = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_"
-- Marqueur au sol n -> icône de raid de même couleur (1 carré bleu, 2 triangle vert…).
local WORLD_MARKER_ICONS = { 6, 4, 3, 7, 1, 2, 5, 8 }
local ICON_TO_WORLD_MARKER = {}
for marker, icon in ipairs(WORLD_MARKER_ICONS) do ICON_TO_WORLD_MARKER[icon] = marker end
local BUTTON = 22
local WIDTH = 8 * (BUTTON + 2) + 10
local BAND_BUTTON = 26
local SHOW_DRIVERS = { group = "[group] show; hide", raid = "[group:raid] show; hide", always = "show" }

local toggle, panel, band

local function S(n) return NS.Pixel:Scale(n) end

local function TextButton(parent, label, onClick, name)
    local button = CreateFrame("Button", name, parent)
    Media:CreateBackdrop(button)
    button.label = Media:CreateText(button, "OVERLAY")
    button.label:SetPoint("CENTER")
    button.label:SetText(label)
    button:SetScript("OnClick", onClick)
    return button
end

local function IconButton(parent, texture)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(S(BUTTON), S(BUTTON))
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetAllPoints()
    button.icon:SetTexture(texture)
    return button
end

--------------------------------------------------------------------------------
-- Actions
--------------------------------------------------------------------------------

function RaidUtility.ReadyCheck()
    if _G.DoReadyCheck then DoReadyCheck() end
end

function RaidUtility.RoleCheck()
    if _G.InitiateRolePoll then InitiateRolePoll() end
end

--- Compte à rebours natif ; `0` l'annule.
function RaidUtility.Countdown(seconds)
    if _G.C_PartyInfo and C_PartyInfo.DoCountdown then C_PartyInfo.DoCountdown(seconds) end
end

--- Groupe -> raid, raid -> groupe (chef seulement, le serveur refuse sinon).
function RaidUtility.ToggleRaid()
    if not _G.C_PartyInfo then return end
    if IsInRaid() then
        if C_PartyInfo.ConvertToParty then C_PartyInfo.ConvertToParty() end
    elseif C_PartyInfo.ConvertToRaid then
        C_PartyInfo.ConvertToRaid()
    end
end

--- Chef : renvoie chaque membre lisible, puis quitte. Sinon : quitte seulement.
function RaidUtility.Disband()
    if not (_G.C_PartyInfo and C_PartyInfo.LeaveParty) then return end
    local leader = _G.UnitIsGroupLeader and UnitIsGroupLeader("player")
    if not NS.IsSecret(leader) and leader and C_PartyInfo.UninviteUnit then
        local me = UnitName("player")
        local prefix, count = "raid", GetNumGroupMembers()
        if not IsInRaid() then prefix, count = "party", count - 1 end
        for i = 1, count do
            local name, realm = UnitName(prefix .. i)
            if name and not NS.IsSecret(name) and not NS.IsSecret(realm) and name ~= me then
                if realm and realm ~= "" then name = name .. "-" .. realm end
                C_PartyInfo.UninviteUnit(name)
            end
        end
    end
    C_PartyInfo.LeaveParty()
end

StaticPopupDialogs["MUSCAUI_DISBAND"] = {
    text = "",   -- posé à l'ouverture : la langue peut changer après le chargement
    button1 = YES,
    button2 = NO,
    OnAccept = function() RaidUtility.Disband() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function UpdateLabels()
    if not panel then return end
    for i, key in ipairs(COUNTDOWN_KEYS) do
        panel.countdowns[i].label:SetFormattedText(L.RAIDUTILITY_SECONDS, RaidUtility.db[key])
    end
    panel.convert.label:SetText(IsInRaid() and L.RAIDUTILITY_TO_PARTY or L.RAIDUTILITY_TO_RAID)
end

--- Marqueur de raid sur la cible ; le même marqueur une seconde fois le retire. 0 : aucun.
function RaidUtility.MarkTarget(index)
    if not (_G.SetRaidTarget and UnitExists("target")) then return end
    local current = _G.GetRaidTargetIndex and GetRaidTargetIndex("target")
    if not NS.IsSecret(current) and current == index then index = 0 end
    SetRaidTarget("target", index)
end

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

local function Build()
    toggle = TextButton(UIParent, L.RAIDUTILITY_BUTTON, function()
        if NS.InCombat() then return end   -- panneau protégé : pas d'ouverture en combat
        panel:SetShown(not panel:IsShown())
    end, "MuscaUIRaidUtilityToggle")
    toggle:SetFrameStrata("MEDIUM")
    toggle:SetSize(S(80), S(20))

    panel = CreateFrame("Frame", "MuscaUIRaidUtility", toggle)
    Media:CreateBackdrop(panel)
    panel:SetPoint("TOP", toggle, "BOTTOM", 0, -S(4))
    panel:Hide()

    local hasCountdown = _G.C_PartyInfo and C_PartyInfo.DoCountdown and true or false
    -- { libellé, action, API présente sur ce client (sinon bouton grisé) }
    local actions = {
        { L.RAIDUTILITY_READY, RaidUtility.ReadyCheck, _G.DoReadyCheck ~= nil },
        { L.RAIDUTILITY_ROLES, RaidUtility.RoleCheck, _G.InitiateRolePoll ~= nil },
        { L.RAIDUTILITY_COUNTDOWN_CANCEL, function() RaidUtility.Countdown(0) end, hasCountdown },
        { "", RaidUtility.ToggleRaid, _G.C_PartyInfo and C_PartyInfo.ConvertToRaid ~= nil },
        { L.RAIDUTILITY_DISBAND, function()
            StaticPopupDialogs.MUSCAUI_DISBAND.text = L.RAIDUTILITY_DISBAND_CONFIRM
            StaticPopup_Show("MUSCAUI_DISBAND")
        end, _G.C_PartyInfo and C_PartyInfo.LeaveParty ~= nil },
    }
    local function Disable(button, available)
        if not available then button:Disable() button:SetAlpha(0.4) end
    end
    -- Rangée des trois comptes à rebours, avant l'annulation.
    local third = (WIDTH - 14) / 3
    panel.countdowns = {}
    panel.actions = {}
    -- Rangées du panneau, posées par LayoutPanel : { hauteur, clé de réglage, items = { { cadre, x } } }
    -- (sans x : pleine largeur).
    panel.rows = {}
    local HIDE_KEYS = { [2] = "showRoleCheck", [4] = "showConvert", [5] = "showDisband" }
    for i, action in ipairs(actions) do
        if i == 3 then
            local row = { 22, nil, items = {} }
            for n, key in ipairs(COUNTDOWN_KEYS) do
                local button = TextButton(panel, "", function() RaidUtility.Countdown(RaidUtility.db[key]) end,
                    "MuscaUIRaidCountdown" .. n)
                button:SetSize(S(third), S(20))
                Disable(button, hasCountdown)
                panel.countdowns[n] = button
                row.items[#row.items + 1] = { button, (n - 1) * (third + 2) }
            end
            panel.rows[#panel.rows + 1] = row
        end
        local button = TextButton(panel, action[1], action[2])
        button:SetHeight(S(20))
        Disable(button, action[3])
        panel.actions[i] = button
        panel.rows[#panel.rows + 1] = { 22, HIDE_KEYS[i], items = { { button } } }
    end
    panel.convert = panel.actions[4]
    panel:RegisterEvent("GROUP_ROSTER_UPDATE")
    panel:SetScript("OnEvent", UpdateLabels)
    panel:SetScript("OnShow", UpdateLabels)

    panel.targetMarkers = {}
    local targetRow = { BUTTON + 4, nil, items = {} }
    for index = 1, 8 do
        local button = IconButton(panel, ICON_PATH .. index)
        button:SetScript("OnClick", function() RaidUtility.MarkTarget(index) end)
        panel.targetMarkers[index] = button
        targetRow.items[#targetRow.items + 1] = { button, (index - 1) * (BUTTON + 2) }
    end
    panel.rows[#panel.rows + 1] = targetRow

    -- Marqueurs au sol : boutons sécurisés, clic gauche pose ou retire, clic droit retire.
    panel.worldMarkers = {}
    local worldRow = { BUTTON + 4, nil, items = {} }
    for marker = 1, 8 do
        local button = CreateFrame("Button", nil, panel, "SecureActionButtonTemplate")
        button:SetSize(S(BUTTON), S(BUTTON))
        button.icon = button:CreateTexture(nil, "ARTWORK")
        button.icon:SetAllPoints()
        button.icon:SetTexture(ICON_PATH .. WORLD_MARKER_ICONS[marker])
        button:RegisterForClicks("AnyUp", "AnyDown")
        button:SetAttribute("type", "worldmarker")
        button:SetAttribute("marker", marker)
        button:SetAttribute("*action1", "toggle")
        button:SetAttribute("*action2", "clear")
        panel.worldMarkers[marker] = button
        worldRow.items[#worldRow.items + 1] = { button, (marker - 1) * (BUTTON + 2) }
    end
    panel.rows[#panel.rows + 1] = worldRow
    local clear = CreateFrame("Button", nil, panel, "SecureActionButtonTemplate")
    Media:CreateBackdrop(clear)
    clear.label = Media:CreateText(clear, "OVERLAY")
    clear.label:SetPoint("CENTER")
    clear.label:SetText(L.RAIDUTILITY_CLEAR_WORLD)
    clear:RegisterForClicks("AnyUp", "AnyDown")
    clear:SetAttribute("type", "worldmarker")
    clear:SetAttribute("action", "clear")   -- sans marqueur : tous
    clear:SetHeight(S(20))
    panel.clearWorld = clear
    panel.rows[#panel.rows + 1] = { 24, nil, items = { { clear } } }
    RaidUtility.LayoutPanel()
end

--- Pose les rangées visibles du panneau (boutons masqués par réglage retirés, le reste remonte).
-- Cadres sécurisés dedans : hors combat seulement, repris à la sortie du combat.
function RaidUtility.LayoutPanel()
    if not panel then return end
    NS:RunOutOfCombat(function()
        local db = RaidUtility.db
        local y = -S(5)
        for _, row in ipairs(panel.rows) do
            local shown = not (row[2] and db[row[2]] == false)
            for _, item in ipairs(row.items) do
                local frame, x = item[1], item[2]
                frame:SetShown(shown)
                if shown then
                    frame:ClearAllPoints()
                    frame:SetPoint("TOPLEFT", panel, "TOPLEFT", S(5) + S(x or 0), y)
                    if not x then frame:SetPoint("RIGHT", panel, "RIGHT", -S(5), 0) end
                end
            end
            if shown then y = y - S(row[1]) end
        end
        panel:SetSize(S(WIDTH), -y + S(2))
        panel:SetScale(tonumber(db.panelScale) or 1)
    end)
end

local function Tooltip(button, text)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(text(), 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

--- Bande compacte : 8 marqueurs (clic gauche sur la cible, clic droit au sol, Maj pour retirer),
-- puis effacer, appel prêt / rôles, compte à rebours.
local function BuildBand()
    band = CreateFrame("Frame", "MuscaUIRaidBand", UIParent)
    Media:CreateBackdrop(band)
    band:SetFrameStrata("MEDIUM")
    band.buttons = {}
    local function Add(button, texture)
        button.icon = button:CreateTexture(nil, "ARTWORK")
        button.icon:SetAllPoints()
        button.icon:SetTexture(texture)
        band.buttons[#band.buttons + 1] = button
    end
    -- Marqueur de cible : SetRaidTarget n'est pas protégé, clic gauche en Lua (au relâchement) ;
    -- marqueur au sol : action sécurisée du clic droit.
    local function Marker(texture, index)
        local button = CreateFrame("Button", nil, band, "SecureActionButtonTemplate")
        Add(button, texture)
        button:RegisterForClicks("AnyUp", "AnyDown")
        button:SetAttribute("*type2", "worldmarker")
        button:SetAttribute("marker", index and ICON_TO_WORLD_MARKER[index] or nil)
        button:SetAttribute("*action2", index and "toggle" or "clear")
        button:SetAttribute("shift-action2", "clear")
        button:HookScript("OnClick", function(_, mouse, down)
            if mouse ~= "LeftButton" or down then return end
            if index and not IsShiftKeyDown() then RaidUtility.MarkTarget(index)
            elseif _G.SetRaidTarget and UnitExists("target") then SetRaidTarget("target", 0) end
        end)
        return button
    end
    band.markers = {}
    for index = 1, 8 do
        band.markers[index] = Marker(ICON_PATH .. index, index)
        Tooltip(band.markers[index], function() return L.RAIDUTILITY_TIP_MARKER end)
    end
    band.clear = Marker("Interface\\Buttons\\UI-GroupLoot-Pass-Up", nil)
    Tooltip(band.clear, function() return L.RAIDUTILITY_TIP_CLEAR end)

    band.ready = CreateFrame("Button", nil, band)
    Add(band.ready, "Interface\\RaidFrame\\ReadyCheck-Ready")
    band.ready:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    band.ready:SetScript("OnClick", function(_, mouse)
        if mouse == "RightButton" then RaidUtility.RoleCheck() else RaidUtility.ReadyCheck() end
    end)
    Tooltip(band.ready, function() return L.RAIDUTILITY_TIP_READY end)

    band.pull = CreateFrame("Button", nil, band)
    Add(band.pull, "Interface\\Icons\\INV_Misc_PocketWatch_01")
    band.pull:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    band.pull:SetScript("OnClick", function(_, mouse)
        local db = RaidUtility.db
        if mouse == "RightButton" then RaidUtility.Countdown(0)
        elseif IsShiftKeyDown() then RaidUtility.Countdown(db.countdown2)
        elseif IsControlKeyDown() then RaidUtility.Countdown(db.countdown3)
        else RaidUtility.Countdown(db.countdown) end
    end)
    Tooltip(band.pull, function()
        local db = RaidUtility.db
        return string.format(L.RAIDUTILITY_TIP_PULL, db.countdown, db.countdown2, db.countdown3)
    end)
end

--- Taille et places des boutons à l'échelle choisie (pas SetScale : le mover mesure en unités d'UIParent).
local function LayoutBand(scale)
    local size, gap = BAND_BUTTON * scale, 3 * scale
    for index, button in ipairs(band.buttons) do
        button:SetSize(S(size), S(size))
        button:ClearAllPoints()
        button:SetPoint("LEFT", band, "LEFT", S(4 * scale) + (index - 1) * S(size + gap), 0)
    end
    band:SetSize(S(8 * scale) + #band.buttons * S(size + gap) - S(gap), S(size + 8 * scale))
end

--- Raid sans être chef ni assistant : le serveur refuse les marqueurs et l'appel, rien n'est montré.
-- Identité secrète : pas de masquage.
function RaidUtility.Suppressed()
    if not IsInRaid() then return false end
    local everyone = _G.IsEveryoneAssistant and IsEveryoneAssistant()
    if NS.IsSecret(everyone) or everyone then return false end
    for _, api in ipairs({ "UnitIsGroupLeader", "UnitIsGroupAssistant" }) do
        local value = _G[api] and _G[api]("player")
        if NS.IsSecret(value) or value then return false end
    end
    return true
end

local active = false

--- Pilote d'état du cadre montré (bouton ou bande), hors combat.
local function ApplyDriver()
    if not active then return end
    local db = RaidUtility.db
    local shown = db.layout == "band" and band or toggle
    local driver = RaidUtility.Suppressed() and "hide" or SHOW_DRIVERS[db.show] or SHOW_DRIVERS.group
    RegisterStateDriver(shown, "visibility", driver)
end

--- Bouton et panneau, ou bande, selon la disposition ; l'autre est retiré avec son mover.
local function ApplyLayout()
    local db = RaidUtility.db
    local shown, hidden, key, other = toggle, band, "raidutility", "raidband"
    if db.layout == "band" then
        if not band then BuildBand() end
        shown, hidden, key, other = band, toggle, "raidband", "raidutility"
        LayoutBand(tonumber(db.bandScale) or 1)
        panel:Hide()
    end
    if hidden then
        UnregisterStateDriver(hidden, "visibility")
        hidden:Hide()
    end
    NS.Movers:Unregister(other)
    NS.Movers:Register(key, shown, key == "raidband" and L.MOVER_RAIDBAND or L.MOVER_RAIDUTILITY, "TOP", -300, -4)
    NS.Movers:Load(key)
    ApplyDriver()
end

local gate = CreateFrame("Frame")
gate:SetScript("OnEvent", function() NS:RunOutOfCombat(ApplyDriver) end)

--------------------------------------------------------------------------------
-- Cycle de vie
--------------------------------------------------------------------------------

function RaidUtility:GetFrames() return toggle, panel, band end

function RaidUtility:OnEnable()
    if not toggle then Build() end
    active = true
    ApplyLayout()
    for _, event in ipairs({ "GROUP_ROSTER_UPDATE", "PARTY_LEADER_CHANGED", "PLAYER_ENTERING_WORLD" }) do
        NS.RegisterEventSafe(gate, event)
    end
    UpdateLabels()
    self:Bind(true)
end

--- Touches des comptes à rebours (hors combat : SetOverrideBindingClick est protégé).
function RaidUtility:Bind(on)
    NS:RunOutOfCombat(function()
        ClearOverrideBindings(panel)
        if not on then return end
        for n, key in ipairs(COUNTDOWN_KEYS) do
            local binding = self.db[key .. "Key"]
            if type(binding) == "string" and binding ~= "" then
                SetOverrideBindingClick(panel, true, binding:upper(), panel.countdowns[n]:GetName(), "LeftButton")
            end
        end
        local toggleKey = self.db.toggleKey
        if self.db.layout ~= "band" and type(toggleKey) == "string" and toggleKey ~= "" then
            SetOverrideBindingClick(panel, true, toggleKey:upper(), toggle:GetName(), "LeftButton")
        end
    end)
end

function RaidUtility:OnRefresh()
    RaidUtility.LayoutPanel()
    ApplyLayout()
    UpdateLabels()
    self:Bind(true)
end

function RaidUtility:OnDisable()
    if not toggle then return end
    active = false
    gate:UnregisterAllEvents()
    for _, frame in ipairs({ toggle, band }) do
        UnregisterStateDriver(frame, "visibility")
        frame:Hide()
    end
    self:Bind(false)
    panel:Hide()
    NS.Movers:Unregister("raidutility")
    NS.Movers:Unregister("raidband")
end

function RaidUtility:BuildOptions(o)
    o:Dropdown("layout", L.OPT_RAIDUTILITY_LAYOUT, {
        { name = L.RAIDUTILITY_LAYOUT_PANEL, value = "panel" }, { name = L.RAIDUTILITY_LAYOUT_BAND, value = "band" } })
    o:Dropdown("show", L.OPT_RAIDUTILITY_SHOW, {
        { name = L.RAIDUTILITY_SHOW_GROUP, value = "group" }, { name = L.RAIDUTILITY_SHOW_RAID, value = "raid" },
        { name = L.RAIDUTILITY_SHOW_ALWAYS, value = "always" } })
    o:Hint(L.OPT_RAIDUTILITY_ASSIST_HINT)
    o:Check("showRoleCheck", L.OPT_G_QOL_RAID_SHOW_ROLES)
    o:Check("showConvert", L.OPT_G_QOL_RAID_SHOW_CONVERT)
    o:Check("showDisband", L.OPT_G_QOL_RAID_SHOW_DISBAND)
    o:Advanced()
    o:Slider("panelScale", L.OPT_G_QOL_RAID_PANEL_SCALE, 0.5, 2, 0.05, 36, "%.2f")
    o:Slider("bandScale", L.OPT_RAIDUTILITY_BAND_SCALE, 0.75, 1.5, 0.05, 36, "%.2f")
    o:EditBox("toggleKey", L.OPT_RAIDUTILITY_TOGGLE_KEY, 1)
    o:EndAdvanced()
    for i, key in ipairs(COUNTDOWN_KEYS) do
        o:Slider(key, string.format(L.OPT_RAIDUTILITY_COUNTDOWN_N, i), 3, 30, 1)
        o:Advanced()
        o:EditBox(key .. "Key", string.format(L.OPT_RAIDUTILITY_COUNTDOWN_KEY, i), 1)
        o:EndAdvanced()
    end
    o:Note(L.OPT_RAIDUTILITY_PULL_HINT)
    o:Button(L.OPT_UNLOCK, function() NS:SetUnlocked(not NS.unlocked) end, 20)
end

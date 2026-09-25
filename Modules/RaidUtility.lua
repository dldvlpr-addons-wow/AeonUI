-- Modules/RaidUtility.lua
-- Utilitaire de raid : un bouton « Raid » sur son mover, visible en groupe, qui ouvre un panneau :
-- appel prêt, vérification des rôles, compte à rebours, marqueurs de cible et marqueurs au sol.
--
-- Module `secure` : les marqueurs au sol sont des boutons d'action sécurisés (PlaceRaidMarker est
-- protégé). La visibilité suit un state driver « [group] », valable en combat ; ouvrir ou fermer
-- le panneau, en revanche, se fait hors combat (panneau protégé par ses boutons sécurisés).
-- Cède à ElvUI, qui a le sien.
local _, NS = ...
local L = NS.L
local Media = NS.Media

local RaidUtility = NS.Modules:Register("raidutility", {
    titleKey = "RAIDUTILITY_TITLE",
    descKey = "RAIDUTILITY_DESC",
    yieldsTo = { "ElvUI" },
    secure = true,
    defaults = {
        enabled = false,
        countdown = 10,
    },
})

local ICON_PATH = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_"
-- Marqueur au sol n -> icône de raid de même couleur (1 carré bleu, 2 triangle vert…).
local WORLD_MARKER_ICONS = { 6, 4, 3, 7, 1, 2, 5, 8 }
local BUTTON = 22
local WIDTH = 8 * (BUTTON + 2) + 10

local toggle, panel

local function S(n) return NS.Pixel:Scale(n) end

local function TextButton(parent, label, onClick)
    local button = CreateFrame("Button", nil, parent)
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
    end)
    toggle:SetFrameStrata("MEDIUM")
    toggle:SetSize(S(80), S(20))

    panel = CreateFrame("Frame", "AeonUIRaidUtility", toggle)
    Media:CreateBackdrop(panel)
    panel:SetPoint("TOP", toggle, "BOTTOM", 0, -S(4))
    panel:Hide()

    local hasCountdown = _G.C_PartyInfo and C_PartyInfo.DoCountdown and true or false
    -- { libellé, action, API présente sur ce client (sinon bouton grisé) }
    local actions = {
        { L.RAIDUTILITY_READY, RaidUtility.ReadyCheck, _G.DoReadyCheck ~= nil },
        { L.RAIDUTILITY_ROLES, RaidUtility.RoleCheck, _G.InitiateRolePoll ~= nil },
        { L.RAIDUTILITY_COUNTDOWN, function() RaidUtility.Countdown(RaidUtility.db.countdown) end, hasCountdown },
        { L.RAIDUTILITY_COUNTDOWN_CANCEL, function() RaidUtility.Countdown(0) end, hasCountdown },
    }
    local y = -S(5)
    panel.actions = {}
    for i, action in ipairs(actions) do
        local button = TextButton(panel, action[1], action[2])
        button:SetPoint("TOPLEFT", panel, "TOPLEFT", S(5), y)
        button:SetPoint("RIGHT", panel, "RIGHT", -S(5), 0)
        button:SetHeight(S(20))
        if not action[3] then button:Disable() button:SetAlpha(0.4) end
        panel.actions[i] = button
        y = y - S(22)
    end

    y = y - S(4)
    panel.targetMarkers = {}
    for index = 1, 8 do
        local button = IconButton(panel, ICON_PATH .. index)
        button:SetPoint("TOPLEFT", panel, "TOPLEFT", S(5) + (index - 1) * S(BUTTON + 2), y)
        button:SetScript("OnClick", function() RaidUtility.MarkTarget(index) end)
        panel.targetMarkers[index] = button
    end
    y = y - S(BUTTON + 4)

    -- Marqueurs au sol : boutons sécurisés, clic gauche pose ou retire, clic droit retire.
    panel.worldMarkers = {}
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
        button:SetPoint("TOPLEFT", panel, "TOPLEFT", S(5) + (marker - 1) * S(BUTTON + 2), y)
        panel.worldMarkers[marker] = button
    end
    y = y - S(BUTTON + 4)
    local clear = CreateFrame("Button", nil, panel, "SecureActionButtonTemplate")
    Media:CreateBackdrop(clear)
    clear.label = Media:CreateText(clear, "OVERLAY")
    clear.label:SetPoint("CENTER")
    clear.label:SetText(L.RAIDUTILITY_CLEAR_WORLD)
    clear:RegisterForClicks("AnyUp", "AnyDown")
    clear:SetAttribute("type", "worldmarker")
    clear:SetAttribute("action", "clear")   -- sans marqueur : tous
    clear:SetPoint("TOPLEFT", panel, "TOPLEFT", S(5), y)
    clear:SetPoint("RIGHT", panel, "RIGHT", -S(5), 0)
    clear:SetHeight(S(20))
    panel.clearWorld = clear
    y = y - S(24)
    panel:SetSize(S(WIDTH), -y + S(2))
end

--------------------------------------------------------------------------------
-- Cycle de vie
--------------------------------------------------------------------------------

function RaidUtility:GetFrames() return toggle, panel end

function RaidUtility:OnEnable()
    if not toggle then Build() end
    NS.Movers:Register("raidutility", toggle, L.MOVER_RAIDUTILITY, "TOP", -300, -4)
    NS.Movers:Load("raidutility")
    RegisterStateDriver(toggle, "visibility", "[group] show; hide")
end

function RaidUtility:OnDisable()
    if not toggle then return end
    UnregisterStateDriver(toggle, "visibility")
    panel:Hide()
    toggle:Hide()
    NS.Movers:Unregister("raidutility")
end

function RaidUtility:BuildOptions(o)
    o:Slider("countdown", L.OPT_RAIDUTILITY_COUNTDOWN, 3, 30, 1)
    o:Button(L.OPT_UNLOCK, function() NS:SetUnlocked(not NS.unlocked) end, 20)
end

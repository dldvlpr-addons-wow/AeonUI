-- Modules/Shifter.lua
-- Fenêtres Blizzard déplaçables à la souris : Maj + glisser pose la fenêtre pour de bon (gardé
-- dans le profil), Ctrl + glisser pour cette ouverture seulement. La position est reposée à
-- chaque ouverture et après le rangement des panneaux par Blizzard (UpdateUIPanelPositions).
-- Rien en combat : certaines fenêtres sont protégées.
local _, NS = ...
local L = NS.L

local Shifter = NS.Modules:Register("shifter", {
    titleKey = "SHIFTER_TITLE",
    descKey = "SHIFTER_DESC",
    defaults = {
        enabled = false,
        positions = {},           -- [nom du cadre] = { point, relativePoint, x, y } (relatif à UIParent)
    },
})

-- Fenêtres de base, puis celles chargées à la demande (rattrapées sur ADDON_LOADED).
local FRAMES = {
    "CharacterFrame", "SpellBookFrame", "PlayerSpellsFrame", "FriendsFrame", "QuestLogFrame", "QuestFrame",
    "GossipFrame", "MerchantFrame", "MailFrame", "BankFrame", "TaxiFrame", "TradeFrame", "DressUpFrame",
    "PVEFrame", "AddonList", "InspectFrame", "TalentFrame", "ClassTalentFrame", "AuctionFrame",
    "AuctionHouseFrame", "TradeSkillFrame", "ProfessionsFrame", "MacroFrame", "ClassTrainerFrame",
    "AchievementFrame", "CommunitiesFrame", "ItemSocketingFrame", "PetStableFrame",
}

local active = false
local hooked = setmetatable({}, { __mode = "k" })     -- [cadre] = nom
local temporary = setmetatable({}, { __mode = "k" })  -- [cadre] = position de cette ouverture
local dragging = setmetatable({}, { __mode = "k" })   -- [cadre] = "save" | "temporary"

local function Place(frame, position)
    if not position[1] then return end   -- position enregistrée sans point (ancienne version)
    frame:ClearAllPoints()
    frame:SetPoint(position[1], UIParent, position[2], position[3], position[4])
end

--- Repose la position gardée (ouverture en cours d'abord) ; rien en combat.
function Shifter.Restore(frame)
    if not active or NS.InCombat() then return end
    local position = temporary[frame] or Shifter.db.positions[hooked[frame]]
    if position then Place(frame, position) end
end

local function StartDrag(frame, button)
    if not active or button ~= "LeftButton" or NS.InCombat() then return end
    local mode = (IsShiftKeyDown() and "save") or (IsControlKeyDown() and "temporary") or nil
    if not mode then return end
    dragging[frame] = mode
    frame:StartMoving()
end

local function StopDrag(frame)
    local mode = dragging[frame]
    if not mode then return end
    dragging[frame] = nil
    frame:StopMovingOrSizing()
    if frame.SetUserPlaced then frame:SetUserPlaced(false) end   -- pas de cache de mise en page Blizzard
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    if not point then return end
    local position = { point, relativePoint, x, y }
    if mode == "save" then
        Shifter.db.positions[hooked[frame]] = position
        temporary[frame] = nil
    else
        temporary[frame] = position
    end
end

local function Hook(name)
    local frame = _G[name]
    if type(frame) ~= "table" or hooked[frame] or not frame.HookScript then return end
    hooked[frame] = name
    frame:SetMovable(true)
    if frame.SetClampedToScreen then frame:SetClampedToScreen(true) end
    frame:HookScript("OnMouseDown", StartDrag)
    frame:HookScript("OnMouseUp", StopDrag)
    frame:HookScript("OnShow", Shifter.Restore)
    frame:HookScript("OnHide", function(self) temporary[self] = nil StopDrag(self) end)
end

function Shifter.HookAll()
    if NS.InCombat() then return end   -- SetMovable d'un cadre protégé : refait hors combat
    for _, name in ipairs(FRAMES) do Hook(name) end
end

function Shifter.IsHooked(frame) return hooked[frame] ~= nil end

local panelsHooked = false
local events = CreateFrame("Frame")
events:SetScript("OnEvent", function() if active then Shifter.HookAll() end end)

function Shifter:OnEnable()
    active = true
    Shifter.HookAll()
    NS.RegisterEventSafe(events, "ADDON_LOADED")
    NS.RegisterEventSafe(events, "PLAYER_REGEN_ENABLED")
    if not panelsHooked and _G.UpdateUIPanelPositions then
        panelsHooked = true
        hooksecurefunc("UpdateUIPanelPositions", function()
            for frame in pairs(hooked) do
                if frame:IsShown() then Shifter.Restore(frame) end
            end
        end)
    end
end

function Shifter:OnDisable()
    active = false
    events:UnregisterAllEvents()
end

function Shifter:BuildOptions(o)
    o.layout:Note(L.NOTE_SHIFTER, 20)
    o:Button(L.OPT_SHIFTER_RESET, function() Shifter.db.positions = {} end, 20)
end

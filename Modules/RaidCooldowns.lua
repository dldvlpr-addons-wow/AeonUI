-- Modules/RaidCooldowns.lua
-- Deux icônes de raid, chacune gardée par ce que le client expose :
--   * rez en combat : charges partagées du groupe (C_Spell.GetSpellCharges(20484)), en
--     instance de groupe seulement, « charges | temps avant la prochaine » ;
--   * Furie sanguinaire / Héroïsme : temps restant de l'affaiblissement « Rassasié » ou
--     équivalent sur le joueur.
-- Sur un client qui ne renvoie ni charges ni ces sorts (contenu Classic), rien ne s'affiche.
local _, NS = ...
local L = NS.L
local Media = NS.Media

local RaidCooldowns = NS.Modules:Register("raidcooldowns", {
    titleKey = "RAIDCD_TITLE",
    descKey = "RAIDCD_DESC",
    defaults = {
        enabled = false,
        battleRes = true,
        bloodlust = true,
        size = 36,
    },
})

local BATTLE_RES_SPELL = 20484
-- Rassasié, Épuisement, Déplacement temporel et leurs équivalents : un seul actif à la fois.
RaidCooldowns.SATED = { 57723, 57724, 80354, 95809, 160455, 264689, 390435 }
local THROTTLE = 0.2

local active = false
local icons = {}   -- battleRes, bloodlust

--- "m:ss" (ou "s" sous la minute) pour un temps restant en secondes.
function RaidCooldowns.FormatTime(seconds)
    seconds = math.max(0, math.floor(seconds + 0.5))
    if seconds < 60 then return tostring(seconds) end
    return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function NewIcon(name, spellID)
    local icon = CreateFrame("Frame", name, UIParent)
    Media:CreateBackdrop(icon)
    icon.texture = icon:CreateTexture(nil, "ARTWORK")
    icon.texture:SetAllPoints()
    icon.texture:SetTexture(NS.GetSpellTexture(spellID))
    if icon.texture.SetTexCoord then icon.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
    icon.text = Media:CreateText(icon, "OVERLAY", 0, "OUTLINE")
    icon.text:SetPoint("TOP", icon, "BOTTOM", 0, -2)
    icon:Hide()
    return icon
end

--- Texte et visibilité de la rez en combat ; faux si rien à montrer.
local function BattleRes(icon)
    local inInstance, kind = false, nil
    if _G.IsInInstance then inInstance, kind = IsInInstance() end
    if not (inInstance and (kind == "party" or kind == "raid")) then return false end
    local current, _, start, duration = NS.GetSpellCharges(BATTLE_RES_SPELL)
    if not current then return false end
    local text = tostring(current)
    if duration > 0 then text = text .. " | " .. RaidCooldowns.FormatTime(start + duration - GetTime()) end
    icon.text:SetText(text)
    return true
end

--- Affaiblissement de Furie sanguinaire sur le joueur ; faux sinon.
local function Bloodlust(icon)
    for _, id in ipairs(RaidCooldowns.SATED) do
        local texture, _, expiration = NS.FindAuraBySpellID("player", id, "HARMFUL")
        if not NS.IsSecret(texture) and texture and not NS.IsSecret(expiration) and type(expiration) == "number" then
            icon.texture:SetTexture(texture)
            icon.text:SetText(RaidCooldowns.FormatTime(expiration - GetTime()))
            return true
        end
    end
    return false
end

function RaidCooldowns:Update()
    if not icons.battleRes then return end
    local db = self.db
    local preview = active and NS.unlocked
    icons.battleRes:SetShown(active and db.battleRes and (BattleRes(icons.battleRes) or preview) and true or false)
    icons.bloodlust:SetShown(active and db.bloodlust and (Bloodlust(icons.bloodlust) or preview) and true or false)
end

local function Build()
    icons.battleRes = NewIcon("AeonUIBattleRes", BATTLE_RES_SPELL)
    icons.bloodlust = NewIcon("AeonUIBloodlust", 2825)
    -- Décompte : rafraîchi 5 fois par seconde tant qu'une icône est visible.
    for _, icon in pairs(icons) do
        icon.elapsed = 0
        icon:SetScript("OnUpdate", function(self, elapsed)
            self.elapsed = self.elapsed + elapsed
            if self.elapsed < THROTTLE then return end
            self.elapsed = 0
            RaidCooldowns:Update()
        end)
    end
end

function RaidCooldowns:Layout()
    local size = self.db.size
    for _, icon in pairs(icons) do icon:SetSize(size, size) end
end

function RaidCooldowns:GetIcons() return icons end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function() RaidCooldowns:Update() end)

function RaidCooldowns:OnEnable()
    if not icons.battleRes then Build() end
    active = true
    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "SPELL_UPDATE_CHARGES", "ENCOUNTER_START", "ENCOUNTER_END",
                             "GROUP_ROSTER_UPDATE" }) do
        NS.RegisterEventSafe(events, event)
    end
    NS.RegisterEventSafe(events, "UNIT_AURA", "player")
    self:Layout()
    NS.Movers:Register("battleRes", icons.battleRes, L.MOVER_BATTLE_RES, "TOPRIGHT", -260, -200)
    NS.Movers:Register("bloodlust", icons.bloodlust, L.MOVER_BLOODLUST, "TOPRIGHT", -310, -200)
    NS.Movers:Load("battleRes")
    NS.Movers:Load("bloodlust")
    self:Update()
end

function RaidCooldowns:OnDisable()
    active = false
    events:UnregisterAllEvents()
    NS.Movers:Unregister("battleRes")
    NS.Movers:Unregister("bloodlust")
    self:Update()
end

function RaidCooldowns:OnRefresh()
    if not icons.battleRes then return end
    self:Layout()
    self:Update()
end

NS:On("UNLOCK", function() RaidCooldowns:Update() end)

function RaidCooldowns:BuildOptions(o)
    o:Note(L.RAIDCD_NOTE)
    o:Check("battleRes", L.OPT_RAIDCD_BATTLE_RES)
    o:Check("bloodlust", L.OPT_RAIDCD_BLOODLUST)
    o:Slider("size", L.OPT_RAIDCD_SIZE, 20, 64, 2)
end

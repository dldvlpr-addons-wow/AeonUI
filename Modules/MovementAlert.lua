-- Modules/MovementAlert.lua
-- Alertes de mouvement : les sorts de déplacement de la classe (Transfert, Sprint, Charge…)
-- affichés en icônes pendant leur recharge, et une annonce brève quand l'un revient. Rien à
-- l'écran tant que tout est prêt. Sorts lus par nom : un id par rang en Classic.
local _, NS = ...
local L = NS.L
local Media = NS.Media

local MovementAlert = NS.Modules:Register("movementalert", {
    titleKey = "MOVEMENT_TITLE",
    descKey = "MOVEMENT_DESC",
    defaults = {
        enabled = false,
        iconSize = 36,
        readyAlert = true,        -- « Transfert prêt » à la fin de la recharge
        extraSpells = "",         -- identifiants ajoutés à ceux de la classe
    },
})

-- Rang 1 de chaque sort ; le nom couvre les autres rangs.
local CLASS_SPELLS = {
    MAGE = { 1953 },              -- Transfert
    ROGUE = { 2983, 1856 },       -- Sprint, Disparition
    DRUID = { 1850, 16979 },      -- Célérité, Charge farouche
    WARRIOR = { 100, 20252 },     -- Charge, Interception
    PALADIN = { 1044 },           -- Bénédiction de liberté
    HUNTER = { 781 },             -- Désengagement
}
local READY_SECONDS = 1.5
local SPACING = 4

local active = false
local holder, readyText
local icons = {}
local wasReady = {}               -- [nom] = prêt au dernier passage

--- Sorts suivis, connus du joueur : { { id, name } } (classe puis liste libre, sans doublon).
function MovementAlert.TrackedSpells()
    local list, seen = {}, {}
    local ids = {}
    for _, id in ipairs(CLASS_SPELLS[select(2, UnitClass("player"))] or {}) do ids[#ids + 1] = id end
    for id in pairs(NS.ParseSpellList(MovementAlert.db.extraSpells)) do ids[#ids + 1] = id end
    for _, id in ipairs(ids) do
        local name = NS.GetSpellName(id)
        if name and not seen[name] and NS.KnowsSpell(id) then
            seen[name] = true
            list[#list + 1] = { id = NS.KnownSpellID(id), name = name }
        end
    end
    return list
end

local function Icon(index)
    local icon = icons[index]
    if icon then return icon end
    icon = CreateFrame("Frame", nil, holder)
    Media:CreateBackdrop(icon)
    icon.texture = icon:CreateTexture(nil, "ARTWORK")
    icon.texture:SetAllPoints(icon)
    icon.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon.cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    icon.cooldown:SetAllPoints(icon)
    icons[index] = icon
    return icon
end

local function Build()
    holder = CreateFrame("Frame", "AeonUIMovementAlert", UIParent)
    readyText = Media:CreateText(holder, "OVERLAY", 4, "OUTLINE")
    readyText:SetPoint("BOTTOM", holder, "TOP", 0, 6)
    readyText:Hide()
end

local readyToken = 0   -- seule la dernière annonce cache le texte
local function AnnounceReady(name)
    readyText:SetText(string.format(L.MOVEMENT_READY, name))
    readyText:Show()
    readyToken = readyToken + 1
    local token = readyToken
    C_Timer.After(READY_SECONDS, function() if token == readyToken then readyText:Hide() end end)
end

function MovementAlert:Update()
    if not holder then return end
    local size = self.db.iconSize
    local shown = 0
    for _, spell in ipairs(active and self.TrackedSpells() or {}) do
        local ready = NS.IsSpellReady(spell.id)
        if not ready or NS.unlocked then
            shown = shown + 1
            local icon = Icon(shown)
            icon:SetSize(size, size)
            icon:ClearAllPoints()
            icon:SetPoint("LEFT", holder, "LEFT", (shown - 1) * (size + SPACING), 0)
            icon.texture:SetTexture(NS.GetSpellTexture(spell.id))
            NS.SetSpellCooldown(icon.cooldown, spell.id)
            icon:Show()
        end
        if ready and wasReady[spell.name] == false and self.db.readyAlert then AnnounceReady(spell.name) end
        wasReady[spell.name] = ready
    end
    for index = shown + 1, #icons do icons[index]:Hide() end
    holder:SetSize(math.max(size, shown * (size + SPACING) - SPACING), size)
    holder:SetShown(active)
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function() MovementAlert:Update() end)

function MovementAlert:OnEnable()
    if not holder then Build() end
    active = true
    NS.RegisterEventSafe(events, "SPELL_UPDATE_COOLDOWN")
    NS.RegisterEventSafe(events, "SPELLS_CHANGED")
    NS.Movers:Register("movementAlert", holder, L.MOVEMENT_TITLE, "CENTER", 0, -210)
    NS.Movers:Load("movementAlert")
    wasReady = {}
    self:Update()
end

function MovementAlert:OnDisable()
    active = false
    events:UnregisterAllEvents()
    NS.Movers:Unregister("movementAlert")
    if readyText then readyText:Hide() end
    self:Update()
end

function MovementAlert:OnRefresh() self:Update() end

NS:On("UNLOCK", function() MovementAlert:Update() end)

function MovementAlert:BuildOptions(o)
    o:Slider("iconSize", L.OPT_MOVEMENT_ICON_SIZE, 16, 64, 1)
    o:Check("readyAlert", L.OPT_MOVEMENT_READY_ALERT)
    o:Advanced()
    o:EditBox("extraSpells", L.OPT_MOVEMENT_EXTRA_SPELLS, 1)
    o:EndAdvanced()
end

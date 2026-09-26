-- Modules/Tracker.lua
-- Suivi par identifiant : une rangée d'icônes pour les sorts et auras choisis par leur ID.
--   * aura présente (buff sur toi, ou débuff posé par toi sur la cible) : icône pleine, bordure
--     à l'accent, durée restante et stacks ;
--   * sinon, sort connu : icône et sa recharge ;
--   * sinon (aura absente, sort inconnu) : icône estompée.
-- Le moteur 12.x cache souvent l'identifiant des auras en combat : une aura illisible compte
-- comme absente. La recharge d'un sort passe par l'objet durée quand le client l'a (lisible
-- en combat). Aucune frame sécurisée : tout se met à jour en combat.
local _, NS = ...
local L = NS.L

local Tracker = NS.Modules:Register("tracker", {
    titleKey = "TRACKER_TITLE",
    descKey = "TRACKER_DESC",
    defaults = {
        enabled = false,
        spells = "",          -- identifiants séparés par des virgules ou des espaces, dans l'ordre d'affichage
        size = 36,
        spacing = 4,
        inactiveAlpha = 0.35,
    },
})

local active = false
local holder
local icons = {}
local ids = {}   -- identifiants suivis, dans l'ordre

--- "1234, 5678" -> { 1234, 5678 } (ordre gardé, doublons retirés).
function Tracker.ParseIDs(text)
    local list, seen = {}, {}
    for digits in tostring(text or ""):gmatch("%d+") do
        local id = tonumber(digits)
        if not seen[id] then
            seen[id] = true
            list[#list + 1] = id
        end
    end
    return list
end

local function Icon(index)
    local icon = icons[index]
    if icon then return icon end
    icon = CreateFrame("Frame", nil, holder)
    icon.texture = icon:CreateTexture(nil, "ARTWORK")
    icon.texture:SetAllPoints()
    icon.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon.border = NS.Media:CreateBorder(icon)
    icon.cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    icon.cooldown:SetAllPoints()
    NS.RegisterCooldown(icon.cooldown)
    icon.count = NS.Media:CreateText(icon, "OVERLAY", 0, "OUTLINE")
    icon.count:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -1, 1)
    icons[index] = icon
    return icon
end

local function SetBorder(icon, lit)
    local r, g, b, a
    if lit then r, g, b = NS.Media:Accent() a = 1
    else
        local c = NS.db.theme.border
        r, g, b, a = c.r, c.g, c.b, c.a or 1
    end
    for _, edge in pairs(icon.border) do NS.SetSolidColor(edge, r, g, b, a) end
end

--- Aura suivie : sur toi d'abord, puis tes débuffs sur la cible.
local function FindAura(id)
    local icon, duration, expiration, count = NS.FindAuraBySpellID("player", id, "HELPFUL")
    if NS.IsSecret(icon) or icon ~= nil then return icon, duration, expiration, count end
    return NS.FindAuraBySpellID("target", id, "HARMFUL|PLAYER")
end

local function Known(value)
    if NS.IsSecret(value) then return nil end
    return value
end

function Tracker:UpdateIcon(icon)
    local id = icon.spellID
    local auraIcon, duration, expiration, count = FindAura(id)
    if NS.IsSecret(auraIcon) or auraIcon ~= nil then
        icon.texture:SetTexture(auraIcon)
        local d, e = Known(duration), Known(expiration)
        if d and e and d > 0 then icon.cooldown:SetCooldown(e - d, d) else icon.cooldown:Clear() end
        local n = Known(count)
        icon.count:SetText(n and n > 1 and tostring(n) or "")
        icon:SetAlpha(1)
        SetBorder(icon, true)
        return
    end
    icon.texture:SetTexture(NS.GetSpellTexture(id))
    icon.count:SetText("")
    SetBorder(icon, false)
    if NS.KnowsSpell(id) then
        NS.SetSpellCooldown(icon.cooldown, id)
        icon:SetAlpha(1)
    else
        icon.cooldown:Clear()
        icon:SetAlpha(self.db.inactiveAlpha)
    end
end

function Tracker:Update()
    if not active then return end
    for i = 1, #ids do self:UpdateIcon(icons[i]) end
end

--- Rangée : une icône par identifiant, de gauche à droite.
function Tracker:Layout()
    local db = self.db
    ids = self.ParseIDs(db.spells)
    for i, id in ipairs(ids) do
        local icon = Icon(i)
        icon.spellID = id
        icon:SetSize(db.size, db.size)
        icon:ClearAllPoints()
        icon:SetPoint("LEFT", holder, "LEFT", (i - 1) * (db.size + db.spacing), 0)
        icon:Show()
    end
    for i = #ids + 1, #icons do icons[i]:Hide() end
    holder:SetSize(math.max(db.size, #ids * (db.size + db.spacing) - db.spacing), db.size)
    self:Update()
end

function Tracker:GetIcons() return icons, holder end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function() Tracker:Update() end)

function Tracker:OnEnable()
    if not holder then
        holder = CreateFrame("Frame", "AeonUITracker", UIParent)
        holder:SetSize(1, 1)
    end
    NS.Movers:Register("tracker", holder, L.MOVER_TRACKER, "CENTER", 0, -120)
    NS.Movers:Load("tracker")
    active = true
    for _, event in ipairs({ "SPELL_UPDATE_COOLDOWN", "SPELLS_CHANGED", "PLAYER_TARGET_CHANGED", "PLAYER_ENTERING_WORLD" }) do
        NS.RegisterEventSafe(events, event)
    end
    NS.RegisterEventSafe(events, "UNIT_AURA", "player", "target")
    holder:Show()
    self:Layout()
end

function Tracker:OnDisable()
    active = false
    events:UnregisterAllEvents()
    NS.Movers:Unregister("tracker")
    if holder then holder:Hide() end
end

function Tracker:OnRefresh() self:Layout() end

function Tracker:BuildOptions(o)
    o.layout:Note(L.NOTE_TRACKER, 20)
    o:EditBox("spells", L.OPT_TRACKER_SPELLS, 2)
    o:Slider("size", L.OPT_TRACKER_SIZE, 16, 64, 2)
    o:Slider("spacing", L.OPT_TRACKER_SPACING, 0, 20, 1)
    o:Slider("inactiveAlpha", L.OPT_TRACKER_INACTIVE_ALPHA, 0, 1, 0.05, nil, "%.2f")
    o:Button(L.OPT_UNLOCK, function() NS:SetUnlocked(not NS.unlocked) end)
end

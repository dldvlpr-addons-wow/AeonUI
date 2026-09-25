-- Modules/CoTank.lua
-- Barre de vie de l'AUTRE tank, cliquable pour le cibler. Affichée quand tu es tank
-- (rôle de groupe, assignation « tank principal », ou forcé dans les options) et qu'un
-- autre tank est dans le raid.
-- Le bouton est sécurisé (clic = cibler) : l'unité suivie et l'affichage ne changent
-- qu'hors combat. En combat, seule la vie bouge : la StatusBar accepte les valeurs
-- secrètes du moteur 12.x, on ne les compare jamais.
local _, NS = ...
local L = NS.L
local Media = NS.Media

local CoTank = NS.Modules:Register("cotank", {
    titleKey = "COTANK_TITLE",
    descKey = "COTANK_DESC",
    secure = true,
    defaults = {
        enabled = false,
        forceTank = false,        -- se considérer tank même sans rôle assigné
        partyToo = false,         -- aussi en groupe à 5
        width = 150,
        height = 20,
        classColor = true,
        showName = true,
        debuffs = true,           -- ses débuffs sous la barre (tentative : valeurs souvent secrètes)
        debuffFilter = "all",     -- NS.AURA_FILTERS (important = boss ou dissipable)
        debuffStacks = true,
        debuffMax = 4,
        debuffSize = 20,
    },
})

local MAX_DEBUFF_INDEX = 40


local active = false
local button
local watched              -- jeton d'unité suivi ("raid7"), ou nil
local debuffIcons = {}     -- filles d'UIParent, ancrées au bouton : Show/Hide libres en combat

--------------------------------------------------------------------------------
-- Détection des tanks
--------------------------------------------------------------------------------

function CoTank.IsTank(unit)
    if _G.UnitGroupRolesAssigned then
        local role = UnitGroupRolesAssigned(unit)
        if not NS.IsSecret(role) and role == "TANK" then return true end
    end
    if _G.GetPartyAssignment then
        local assigned = GetPartyAssignment("MAINTANK", unit)
        if not NS.IsSecret(assigned) and assigned then return true end
    end
    return false
end

--- Jeton de l'autre tank, ou nil.
function CoTank:FindOtherTank()
    local db = self.db
    local inRaid = IsInRaid()
    if not inRaid and not (db.partyToo and IsInGroup()) then return nil end
    if not (db.forceTank or CoTank.IsTank("player")) then return nil end
    local prefix, count = "raid", GetNumGroupMembers()
    if not inRaid then prefix, count = "party", GetNumGroupMembers() - 1 end
    for i = 1, count do
        local unit = prefix .. i
        if UnitExists(unit) and not UnitIsUnit(unit, "player") and CoTank.IsTank(unit) then
            return unit
        end
    end
    return nil
end

--------------------------------------------------------------------------------
-- Affichage
--------------------------------------------------------------------------------

local function Build()
    button = CreateFrame("Button", "AeonUICoTank", UIParent, "SecureUnitButtonTemplate")
    button:RegisterForClicks("AnyUp")
    button:SetAttribute("type1", "target")
    button.bg = Media:CreateBackdrop(button)   -- fond et bordure 1 px du thème
    button.health = CreateFrame("StatusBar", nil, button)
    button.health:SetPoint("TOPLEFT", 1, -1)
    button.health:SetPoint("BOTTOMRIGHT", -1, 1)
    button.health:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    button.name = Media:CreateText(button.health, "OVERLAY", 0, "OUTLINE")
    button.name:SetPoint("CENTER")
    button:Hide()
end

--- Vie : appelée aussi en combat (valeurs éventuellement secrètes, passées telles quelles).
function CoTank:UpdateHealth()
    if not button or not watched then return end
    button.health:SetMinMaxValues(0, UnitHealthMax(watched))
    button.health:SetValue(UnitHealth(watched))
end

local function HideDebuffIcons()
    for i = 1, #debuffIcons do debuffIcons[i]:Hide() end
end

--- Rangée d'icônes sous la barre : créée/redimensionnée hors combat (Refresh). Pas filles du
-- bouton sécurisé : un enfant hérite de sa protection, et Show/Hide seraient bloqués en combat.
local function EnsureDebuffIcons()
    local db = CoTank.db
    for i = 1, db.debuffMax do
        local icon = debuffIcons[i]
        if not icon then
            icon = CreateFrame("Frame", nil, UIParent)
            icon.texture = icon:CreateTexture(nil, "ARTWORK")
            icon.texture:SetAllPoints()
            icon.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            icon.cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
            icon.cooldown:SetAllPoints()
            NS.RegisterCooldown(icon.cooldown)
            icon.count = Media:CreateText(icon, "OVERLAY", -2, "OUTLINE")
            icon.count:SetPoint("BOTTOMRIGHT", 1, 0)
            debuffIcons[i] = icon
        end
        icon:SetSize(db.debuffSize, db.debuffSize)
        icon:ClearAllPoints()
        icon:SetPoint("TOPLEFT", button, "BOTTOMLEFT", (i - 1) * (db.debuffSize + 2), -2)
        icon:Hide()
    end
    for i = db.debuffMax + 1, #debuffIcons do debuffIcons[i]:Hide() end
end

--- Débuffs : appelée aussi en combat. Une valeur secrète n'est jamais comparée : la texture et
-- le balayage l'acceptent, le compteur et le filtre s'abstiennent.
function CoTank:UpdateDebuffs()
    if not button or not watched then return end
    local db = self.db
    local slot, shown = 1, math.min(db.debuffMax, #debuffIcons)
    if db.debuffs then
        for index = 1, MAX_DEBUFF_INDEX do
            if slot > shown then break end
            local texture, duration, expiration, applications, dispelName, isBossAura, spellId, isMine = NS.GetDebuff(watched, index)
            if not NS.IsSecret(texture) and texture == nil then break end
            if NS.AuraPasses(db.debuffFilter, spellId, dispelName, isBossAura, isMine) then
                local icon = debuffIcons[slot]
                icon.texture:SetTexture(texture)
                if not NS.IsSecret(duration) and not NS.IsSecret(expiration) and duration and expiration
                        and duration > 0 then
                    icon.cooldown:SetCooldown(expiration - duration, duration)
                else
                    icon.cooldown:Clear()
                end
                if db.debuffStacks and not NS.IsSecret(applications) and applications and applications > 1 then
                    icon.count:SetText(applications)
                else
                    icon.count:SetText("")
                end
                icon:Show()
                slot = slot + 1
            end
        end
    end
    for i = slot, #debuffIcons do debuffIcons[i]:Hide() end
end

local function Paint(unit)
    local db = CoTank.db
    local r, g, b = 0, 0.8, 0.2
    if db.classColor then
        local _, classFile = UnitClass(unit)
        if not NS.IsSecret(classFile) and classFile then r, g, b = NS.ClassColor(classFile) end
    end
    button.health:SetStatusBarColor(r, g, b)
    -- Pas de « and/or » sur le nom : il peut être secret (identité restreinte), SetText l'accepte.
    if db.showName then button.name:SetText(UnitName(unit)) else button.name:SetText("") end
end

--- Choisit l'unité et affiche/masque. Hors combat uniquement (bouton sécurisé).
function CoTank:Refresh()
    if not button then return end
    local db = self.db
    local unit = active and (self:FindOtherTank() or (NS.unlocked and "player")) or nil
    button:SetSize(db.width, db.height)
    EnsureDebuffIcons()
    watched = unit
    if unit then
        button:SetAttribute("unit", unit)
        Paint(unit)
        self:UpdateHealth()
        self:UpdateDebuffs()
        button:Show()
    else
        button:SetAttribute("unit", nil)
        button:Hide()
        HideDebuffIcons()
    end
end

function CoTank:GetButton() return button, watched, debuffIcons end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, unit)
    if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
        if unit == watched then CoTank:UpdateHealth() end
        return
    end
    if event == "UNIT_AURA" then
        if unit == watched then CoTank:UpdateDebuffs() end
        return
    end
    NS:RunOutOfCombat(function() CoTank:Refresh() end)
end)

function CoTank:OnEnable()
    if not button then Build() end
    active = true
    -- Mover lié au module : coupé, il n'apparaît plus au déverrouillage.
    NS.Movers:Register("cotank", button, L.MOVER_COTANK, "CENTER", 200, 0)
    NS.Movers:Load("cotank")
    for _, event in ipairs({ "GROUP_ROSTER_UPDATE", "PLAYER_ROLES_ASSIGNED", "ROLE_CHANGED_INFORM",
                             "PLAYER_ENTERING_WORLD", "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_AURA" }) do
        NS.RegisterEventSafe(events, event)
    end
    self:Refresh()
end

function CoTank:OnDisable()
    active = false
    events:UnregisterAllEvents()
    NS.Movers:Unregister("cotank")
    if button then
        watched = nil
        button:SetAttribute("unit", nil)
        button:Hide()
        HideDebuffIcons()
    end
end

function CoTank:OnRefresh() self:Refresh() end

-- Déverrouillé : aperçu sur soi-même pour placer la barre (hors combat).
NS:On("UNLOCK", function(unlocked)
    if not button then return end
    NS:RunOutOfCombat(function() CoTank:Refresh() end)
end)

function CoTank:BuildOptions(o)
    o:Check("forceTank", L.OPT_COTANK_FORCE)
    o:Check("partyToo", L.OPT_COTANK_PARTY)
    o:Check("classColor", L.OPT_COTANK_CLASS)
    o:Check("showName", L.OPT_COTANK_NAME)
    o:Slider("width", L.OPT_COTANK_WIDTH, 80, 300, 10)
    o:Slider("height", L.OPT_COTANK_HEIGHT, 12, 40, 2)
    o:Check("debuffs", L.OPT_COTANK_DEBUFFS)
    o:Dropdown("debuffFilter", L.OPT_COTANK_DEBUFF_FILTER, NS.AuraFilterChoices, 36)
    o:Check("debuffStacks", L.OPT_COTANK_DEBUFF_STACKS, 36)
    o:Slider("debuffMax", L.OPT_COTANK_DEBUFF_MAX, 1, 8, 1)
    o:Slider("debuffSize", L.OPT_COTANK_DEBUFF_SIZE, 12, 32, 2)
    o:Button(L.OPT_COTANK_PREVIEW, function() NS:SetUnlocked(not NS.unlocked) end)
end

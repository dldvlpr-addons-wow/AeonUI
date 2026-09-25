-- Modules/ResourceBars.lua
-- Barres de ressources du joueur, détachées des cadres d'unité et placées où l'on veut :
--   * vie (désactivée par défaut) ;
--   * puissance principale (mana, rage, énergie), couleur de Blizzard ;
--   * points de combo, une graduation par point (classes qui en ont) ;
--   * mana en forme de druide (ours, félin : la puissance affichée n'est plus le mana).
-- Chaque barre a son mover : ancrable sous le cadre du joueur, largeur reprise, etc.
-- Valeurs secrètes (moteur 12.x) : passées telles quelles à SetValue / SetText, jamais comparées.
local _, NS = ...
local L = NS.L
local Media = NS.Media
local Elements = NS.UnitFrameElements

local ResourceBars = NS.Modules:Register("resourcebars", {
    titleKey = "RESOURCEBARS_TITLE",
    descKey = "RESOURCEBARS_DESC",
    defaults = {
        enabled = false,
        width = 220,               -- longueur des barres (hauteur si verticales)
        orientation = "HORIZONTAL", -- "HORIZONTAL" ou "VERTICAL" (remplissage vers le haut)
        visibility = "always",     -- "always", "combat" (combat ou cible), "never" hors combat masqué
        outOfCombatAlpha = 1,
        health = false,
        healthHeight = 14,
        healthText = "curperc",
        classColor = true,
        power = true,
        powerHeight = 12,
        powerText = "current",
        threshold = 0,              -- repère sur la barre de puissance, en % (0 : aucun)
        combo = true,
        comboHeight = 8,
        druidMana = true,
        druidManaHeight = 6,
    },
})

local BARS = {
    { key = "health", mover = "resourceHealth", label = "MOVER_RESOURCE_HEALTH", y = -160 },
    { key = "power", mover = "resourcePower", label = "MOVER_RESOURCE_POWER", y = -178 },
    { key = "combo", mover = "resourceCombo", label = "MOVER_RESOURCE_COMBO", y = -194 },
    { key = "druidMana", mover = "resourceDruidMana", label = "MOVER_RESOURCE_DRUID_MANA", y = -206 },
}

local active = false
local bars = {}   -- [key] = StatusBar

local function Known(value)
    if NS.IsSecret(value) or value == nil then return nil end
    return value
end

local function ManaType() return Enum and Enum.PowerType and Enum.PowerType.Mana or 0 end

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

local function Build()
    for _, spec in ipairs(BARS) do
        local holder = CreateFrame("Frame", "AeonUIResource_" .. spec.key, UIParent)
        Media:CreateBackdrop(holder)
        local bar = Media:CreateStatusBar(holder)
        bar:SetAllPoints(holder)
        bar.text = Media:CreateText(bar, "OVERLAY", -2)
        bar.text:SetPoint("CENTER")
        bar.ticks = {}
        bar.holder = holder
        holder:Hide()
        bars[spec.key] = bar
    end
    local marker = bars.power:CreateTexture(nil, "OVERLAY")
    NS.SetSolidColor(marker, 1, 1, 1, 0.8)
    bars.power.marker = marker
end

--------------------------------------------------------------------------------
-- Mises à jour
--------------------------------------------------------------------------------

local function Visible(db, event)
    if not active then return false end
    if db.visibility ~= "combat" then return true end
    local inCombat = event == "PLAYER_REGEN_DISABLED" or (event ~= "PLAYER_REGEN_ENABLED" and NS.InCombat())
    return inCombat or (UnitExists("target") and Known(UnitCanAttack("player", "target")) and true or false)
end

local function UpdateHealth(db)
    local bar = bars.health
    bar:SetMinMaxValues(0, UnitHealthMax("player"))
    bar:SetValue(UnitHealth("player"))
    bar:SetStatusBarColor(Elements.HealthColor("player", db.classColor))
    Elements.SetUnitText(bar.text, "player", "health", Elements.TextFormat(nil, db.healthText))
    return true
end

local function UpdatePower(db)
    local bar = bars.power
    local max = UnitPowerMax("player")
    local knownMax = Known(max)
    if knownMax and knownMax <= 0 then return false end
    bar:SetMinMaxValues(0, max)
    bar:SetValue(UnitPower("player"))
    bar:SetStatusBarColor(Elements.PowerColor("player"))
    Elements.SetUnitText(bar.text, "player", "power", Elements.TextFormat(nil, db.powerText))
    local marker = bar.marker
    if (db.threshold or 0) > 0 then
        marker:ClearAllPoints()
        if bar.vertical then
            local y = (bar:GetHeight() or db.width) * db.threshold / 100
            marker:SetHeight(NS.Pixel:Scale(1))
            marker:SetPoint("LEFT", bar, "BOTTOMLEFT", 0, y)
            marker:SetPoint("RIGHT", bar, "BOTTOMRIGHT", 0, y)
        else
            local x = (bar:GetWidth() or db.width) * db.threshold / 100   -- largeur reprise d'une cible comprise
            marker:SetWidth(NS.Pixel:Scale(1))
            marker:SetPoint("TOP", bar, "TOPLEFT", x, 0)
            marker:SetPoint("BOTTOM", bar, "BOTTOMLEFT", x, 0)
        end
        marker:Show()
    else
        marker:Hide()
    end
    return true
end

-- Même rendu que les points de combo du cadre joueur (graduations comprises).
local comboHost = { comboAllowed = true, unit = "player" }
local function UpdateCombo()
    local bar = bars.combo
    comboHost.combo = bar
    bar.width = bar:GetWidth()
    Elements.UpdateCombo(comboHost)
    return bar:IsShown()
end

--- Mana d'un druide en forme : seulement si la puissance affichée n'est pas le mana.
local function UpdateDruidMana()
    local bar = bars.druidMana
    local powerType = Known(UnitPowerType("player"))
    if powerType == nil or powerType == ManaType() then return false end
    local max = UnitPowerMax("player", ManaType())
    local knownMax = Known(max)
    if not knownMax or knownMax <= 0 then return false end
    bar:SetMinMaxValues(0, max)
    bar:SetValue(UnitPower("player", ManaType()))
    local c = _G.PowerBarColor and PowerBarColor.MANA or { r = 0, g = 0.44, b = 0.87 }
    bar:SetStatusBarColor(c.r, c.g, c.b)
    bar.text:SetText("")
    return true
end

local UPDATERS = { health = UpdateHealth, power = UpdatePower, combo = UpdateCombo, druidMana = UpdateDruidMana }

function ResourceBars:Update(event)
    if not bars.power then return end
    local db = self.db
    local visible = Visible(db, event)
    local inCombat = event == "PLAYER_REGEN_DISABLED" or (event ~= "PLAYER_REGEN_ENABLED" and NS.InCombat())
    for _, spec in ipairs(BARS) do
        local bar = bars[spec.key]
        local holder = bar.holder
        -- En mode déverrouillé, une barre activée reste visible pour être placée.
        local wanted = db[spec.key] and (visible or (active and NS.unlocked))
        local shown = wanted and UPDATERS[spec.key](db) or false
        holder:SetShown(shown and true or false)
        holder:SetAlpha((inCombat or NS.unlocked) and 1 or db.outOfCombatAlpha)
    end
end

function ResourceBars:Layout()
    local db = self.db
    local vertical = db.orientation == "VERTICAL"
    for _, spec in ipairs(BARS) do
        local bar = bars[spec.key]
        local thickness = db[spec.key .. "Height"]
        -- Verticale : la longueur passe en hauteur, l'épaisseur en largeur.
        if vertical then bar.holder:SetSize(thickness, db.width) else bar.holder:SetSize(db.width, thickness) end
        bar.vertical = vertical
        bar:SetOrientation(vertical and "VERTICAL" or "HORIZONTAL")
        if bar.SetRotatesTexture then bar:SetRotatesTexture(vertical) end
    end
end

function ResourceBars:GetBars() return bars end

--------------------------------------------------------------------------------
-- Cycle de vie
--------------------------------------------------------------------------------

local UNIT_EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER" }
local EVENTS = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_TARGET_CHANGED",
                 "UPDATE_SHAPESHIFT_FORM", "PLAYER_ENTERING_WORLD" }

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event) ResourceBars:Update(event) end)

function ResourceBars:OnEnable()
    if not bars.power then Build() end
    active = true
    for _, event in ipairs(UNIT_EVENTS) do NS.RegisterEventSafe(events, event, "player") end
    for _, event in ipairs(EVENTS) do NS.RegisterEventSafe(events, event) end
    self:Layout()
    for _, spec in ipairs(BARS) do
        NS.Movers:Register(spec.mover, bars[spec.key].holder, L[spec.label], "CENTER", 0, spec.y)
        NS.Movers:Load(spec.mover)
    end
    self:Update()
end

function ResourceBars:OnDisable()
    active = false
    events:UnregisterAllEvents()
    for _, spec in ipairs(BARS) do NS.Movers:Unregister(spec.mover) end
    if bars.power then self:Update() end
end

function ResourceBars:OnRefresh()
    self:Layout()
    self:Update()
end

NS:On("UNLOCK", function() if bars.power then ResourceBars:Update() end end)

function ResourceBars:BuildOptions(o)
    local modes = Elements.TextModeChoices()
    o:Dropdown("orientation", L.OPT_BAR_ORIENTATION, {
        { name = L.OPT_BAR_HORIZONTAL, value = "HORIZONTAL" }, { name = L.OPT_BAR_VERTICAL, value = "VERTICAL" },
    })
    o:Slider("width", L.OPT_RESOURCE_WIDTH, 60, 500, 2)
    o:Dropdown("visibility", L.OPT_RESOURCE_VISIBILITY, {
        { name = L.OPT_RESOURCE_VIS_ALWAYS, value = "always" },
        { name = L.OPT_RESOURCE_VIS_COMBAT, value = "combat" },
    })
    o:Slider("outOfCombatAlpha", L.OPT_RESOURCE_ALPHA, 0, 1, 0.05, nil, "%.2f")
    o:Title(L.OPT_RESOURCE_HEALTH)
    o:Check("health", L.OPT_RESOURCE_SHOW)
    o:Slider("healthHeight", L.OPT_RESOURCE_HEIGHT, 4, 40, 1, 36)
    o:Dropdown("healthText", L.OPT_RESOURCE_TEXT, modes, 36)
    o:Check("classColor", L.OPT_RESOURCE_CLASS_COLOR, 36)
    o:Title(L.OPT_RESOURCE_POWER)
    o:Check("power", L.OPT_RESOURCE_SHOW)
    o:Slider("powerHeight", L.OPT_RESOURCE_HEIGHT, 4, 40, 1, 36)
    o:Dropdown("powerText", L.OPT_RESOURCE_TEXT, modes, 36)
    o:Slider("threshold", L.OPT_RESOURCE_THRESHOLD, 0, 100, 5, 36)
    o:Title(L.OPT_RESOURCE_COMBO)
    o:Check("combo", L.OPT_RESOURCE_SHOW)
    o:Slider("comboHeight", L.OPT_RESOURCE_HEIGHT, 4, 30, 1, 36)
    o:Title(L.OPT_RESOURCE_DRUID_MANA)
    o:Check("druidMana", L.OPT_RESOURCE_SHOW)
    o:Slider("druidManaHeight", L.OPT_RESOURCE_HEIGHT, 2, 30, 1, 36)
end

-- AeonUI_UnitFrames/ResourceBars.lua
-- Barres de ressources du joueur, détachées des cadres d'unité et placées où l'on veut :
--   * vie (désactivée par défaut) ;
--   * puissance principale (mana, rage, énergie), couleur de Blizzard ;
--   * points de combo, une graduation par point (classes qui en ont) ;
--   * mana en forme de druide (ours, félin : la puissance affichée n'est plus le mana).
-- Chaque barre a son mover : ancrable sous le cadre du joueur, largeur reprise, etc.
-- Valeurs secrètes (moteur 12.x) : passées telles quelles à SetValue / SetText, jamais comparées.
local NS = AeonUI
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
        visibility = NS.Visibility.Spec(),   -- conditions communes (Core/Visibility)
        outOfCombatAlpha = 1,
        health = false,
        healthHeight = 14,
        healthText = "curperc",
        classColor = true,
        power = true,
        powerHeight = 12,
        powerText = "current",
        threshold = 0,              -- repère sur la barre de puissance, en % (0 : aucun)
    -- Paliers de couleur (en %, 0 : coupé) et repères (« 25, 50 ») des barres de vie et de puissance.
    healthLow = 0, healthLowColor = { r = 0.9, g = 0.15, b = 0.15 },
    healthMid = 0, healthMidColor = { r = 0.95, g = 0.75, b = 0.1 },
    healthHashLines = "",
    powerLow = 0, powerLowColor = { r = 0.9, g = 0.15, b = 0.15 },
    powerMid = 0, powerMidColor = { r = 0.95, g = 0.75, b = 0.1 },
    powerHashLines = "",
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
end

--------------------------------------------------------------------------------
-- Mises à jour
--------------------------------------------------------------------------------

local function Visible(db, event)
    if not active then return false end
    return NS.Visibility.Evaluate(db.visibility, NS.Visibility.State(event))
end

local function UpdateHealth(db)
    local bar = bars.health
    bar:SetMinMaxValues(0, UnitHealthMax("player"))
    bar:SetValue(UnitHealth("player"))
    local r, g, b = Elements.HealthColor("player", db.classColor)
    Media:SetHealthColor(bar, Elements.BandColor("player", "health", bar.steps, r, g, b))
    Elements.SetUnitText(bar.text, "player", "health", Elements.TextFormat(nil, db.healthText))
    Elements.SetHashLines(bar, bar.hashPercents, bar.vertical, bar.vertical and bar:GetHeight() or bar:GetWidth() or db.width)
    return true
end

local function UpdatePower(db)
    local bar = bars.power
    local max = UnitPowerMax("player")
    local knownMax = Known(max)
    if knownMax and knownMax <= 0 then return false end
    bar:SetMinMaxValues(0, max)
    bar:SetValue(UnitPower("player"))
    local r, g, b = Elements.PowerColor("player")
    bar:SetStatusBarColor(Elements.BandColor("player", "power", bar.steps, r, g, b))
    Elements.SetUnitText(bar.text, "player", "power", Elements.TextFormat(nil, db.powerText))
    -- Largeur lue sur la barre : celle reprise d'une cible comprise.
    Elements.SetHashLines(bar, bar.hashPercents, bar.vertical, bar.vertical and bar:GetHeight() or bar:GetWidth() or db.width)
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
        bar.steps = Elements.Bands(db[spec.key .. "Low"], db[spec.key .. "LowColor"], db[spec.key .. "Mid"], db[spec.key .. "MidColor"])
        bar.hashPercents = Elements.HashPercents(db[spec.key .. "HashLines"], spec.key == "power" and db.threshold)
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
                 "UPDATE_SHAPESHIFT_FORM", "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE",
                 "ZONE_CHANGED_NEW_AREA", "PLAYER_MOUNT_DISPLAY_CHANGED" }

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

--- Paliers de couleur et repères d'une barre (`key` : "health" ou "power").
local function BandOptions(o, key)
    o:Advanced()
    o:Slider(key .. "Low", L.OPT_BAND_LOW, 0, 90, 5, 36)
    o:Color(key .. "LowColor", L.OPT_BAND_COLOR, 52)
    o:Slider(key .. "Mid", L.OPT_BAND_MID, 0, 95, 5, 36)
    o:Color(key .. "MidColor", L.OPT_BAND_COLOR, 52)
    o:EditBox(key .. "HashLines", L.OPT_HASH_LINES, 1, 36)
end

function ResourceBars:BuildOptions(o)
    local modes = Elements.TextModeChoices()
    o:Dropdown("orientation", L.OPT_BAR_ORIENTATION, {
        { name = L.OPT_BAR_HORIZONTAL, value = "HORIZONTAL" }, { name = L.OPT_BAR_VERTICAL, value = "VERTICAL" },
    })
    o:Slider("width", L.OPT_RESOURCE_WIDTH, 60, 500, 2)
    o:Advanced()
    o:Slider("outOfCombatAlpha", L.OPT_RESOURCE_ALPHA, 0, 1, 0.05, nil, "%.2f")
    o:EndAdvanced()
    o:Visibility("visibility", L.OPT_VISIBILITY,{ noMouseover = true })
    o:Title(L.OPT_RESOURCE_HEALTH)
    o:Check("health", L.OPT_RESOURCE_SHOW)
    o:Slider("healthHeight", L.OPT_RESOURCE_HEIGHT, 4, 40, 1, 36)
    o:Dropdown("healthText", L.OPT_RESOURCE_TEXT, modes, 36)
    o:Check("classColor", L.OPT_RESOURCE_CLASS_COLOR, 36)
    BandOptions(o, "health")
    o:Title(L.OPT_RESOURCE_POWER)
    o:Check("power", L.OPT_RESOURCE_SHOW)
    o:Slider("powerHeight", L.OPT_RESOURCE_HEIGHT, 4, 40, 1, 36)
    o:Dropdown("powerText", L.OPT_RESOURCE_TEXT, modes, 36)
    o:Advanced()
    o:Slider("threshold", L.OPT_RESOURCE_THRESHOLD, 0, 100, 5, 36)
    o:EndAdvanced()
    BandOptions(o, "power")
    o:Title(L.OPT_RESOURCE_COMBO)
    o:Check("combo", L.OPT_RESOURCE_SHOW)
    o:Slider("comboHeight", L.OPT_RESOURCE_HEIGHT, 4, 30, 1, 36)
    o:Title(L.OPT_RESOURCE_DRUID_MANA)
    o:Check("druidMana", L.OPT_RESOURCE_SHOW)
    o:Slider("druidManaHeight", L.OPT_RESOURCE_HEIGHT, 2, 30, 1, 36)
end

--- Aperçu des options : barres affichées dans leur ordre, à leur largeur et épaisseur (côte à
-- côte en orientation verticale) ; un clic ouvre la section de la barre.
ResourceBars.previewHeight = 150

function ResourceBars:BuildPreview(p)
    return function()
        local db = p.DB()
        p.Begin()
        local shown = {}
        local r, g, b = 0.2, 0.75, 0.2
        if db.classColor then r, g, b = p.ClassColor() end
        if db.health then shown[#shown + 1] = { key = "health", size = db.healthHeight, color = { r, g, b }, part = 0.8, title = L.OPT_RESOURCE_HEALTH } end
        if db.power then shown[#shown + 1] = { key = "power", size = db.powerHeight, color = { 0, 0.44, 0.87 }, part = 0.6, title = L.OPT_RESOURCE_POWER } end
        if db.combo then shown[#shown + 1] = { key = "combo", size = db.comboHeight, segments = 5, part = 3, title = L.OPT_RESOURCE_COMBO } end
        if db.druidMana then shown[#shown + 1] = { key = "druidMana", size = db.druidManaHeight, color = { 0.3, 0.5, 1 }, part = 0.7, title = L.OPT_RESOURCE_DRUID_MANA } end
        if #shown == 0 then return end
        local vertical = db.orientation == "VERTICAL"
        local thickness = 0
        for _, bar in ipairs(shown) do thickness = thickness + bar.size + 2 end
        thickness = thickness - 2
        local scale, originX, originY
        if vertical then scale, originX, originY = p.Fit(thickness, db.width, 8)
        else scale, originX, originY = p.Fit(db.width, thickness, 8) end
        local offset, length = 0, db.width * scale
        for _, bar in ipairs(shown) do
            local size = bar.size * scale
            local x, y, w, h
            if vertical then x, y, w, h = originX + offset, originY, size, length
            else x, y, w, h = originX, originY + offset, length, size end
            p.Edge(bar.key .. ":edge", x, y, w, h, 0, 0, 0, 1)
            if bar.segments then
                local cells = vertical and h or w
                local cell = (cells - (bar.segments - 1) * 2) / bar.segments
                for i = 1, bar.segments do
                    local lit = i <= bar.part
                    local cr, cg, cb = lit and 1 or 0.15, lit and 0.8 or 0.15, lit and 0.1 or 0.15
                    local at = (i - 1) * (cell + 2)
                    if vertical then p.Box(bar.key .. i, x, y + h - at - cell, w, cell, cr, cg, cb, 1)
                    else p.Box(bar.key .. i, x + at, y, cell, h, cr, cg, cb, 1) end
                end
            elseif vertical then
                p.Box(bar.key .. ":vbg", x, y, w, h, 0, 0, 0, 0.7, -4)
                p.Box(bar.key .. ":vfill", x, y + h * (1 - bar.part), w, h * bar.part, bar.color[1], bar.color[2], bar.color[3], 1)
            else
                p.Bar(bar.key, x, y, w, h, bar.color[1], bar.color[2], bar.color[3], bar.part)
            end
            p.Hotspot(p.Region(bar.key .. ":spot", x, y, w, h), bar.title)
            offset = offset + size + 2 * scale
        end
    end
end

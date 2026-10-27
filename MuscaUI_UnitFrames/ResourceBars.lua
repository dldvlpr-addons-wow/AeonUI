-- MuscaUI_UnitFrames/ResourceBars.lua
-- Barres de ressources du joueur, détachées des cadres d'unité et placées où l'on veut :
--   * vie (désactivée par défaut) ;
--   * puissance principale (mana, rage, énergie), couleur de Blizzard ;
--   * points de combo, une graduation par point (classes qui en ont) ;
--   * mana en forme de druide (ours, félin : la puissance affichée n'est plus le mana).
-- Chaque barre a son mover : ancrable sous le cadre du joueur, largeur reprise, etc.
-- Valeurs secrètes (moteur 12.x) : passées telles quelles à SetValue / SetText, jamais comparées.
local NS = MuscaUI
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
        smoothBars = false,         -- vie, puissance et mana animées vers leur nouvelle valeur
        health = false,
        healthHeight = 14,
        healthText = "curperc",
        classColor = true,
        power = true,
        powerHeight = 12,
        powerText = "current",
        threshold = 0,              -- repère sur la barre de puissance, en % (0 : aucun)
        manaSpark = false,          -- règle des 5 secondes sur la barre de puissance (mana)
        manaCostPrediction = true,  -- coût en mana de l'incantation en cours
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
        strata = "MEDIUM",          -- niveau d'affichage des barres ("LOW", "MEDIUM", "HIGH")
        healthOrientation = "inherit", powerOrientation = "inherit",   -- "inherit" : orientation commune
        comboOrientation = "inherit", druidManaOrientation = "inherit",
        healthAbsorb = false,       -- absorptions superposées à la barre de vie
        powerForceMana = false,     -- la barre de puissance montre le mana, quelle que soit la forme
        comboColor = { r = 1, g = 0.82, b = 0 },
        comboAlphaOwn = false,      -- opacité hors combat propre aux points de combo
        comboAlpha = 1,
        -- Texte des barres de vie et de puissance : ancre, décalages, taille ajoutée.
        healthTextAnchor = "CENTER", healthTextX = 0, healthTextY = 0, healthTextSizeBonus = 0,
        powerTextAnchor = "CENTER", powerTextX = 0, powerTextY = 0, powerTextSizeBonus = 0,
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
        local holder = CreateFrame("Frame", "MuscaUIResource_" .. spec.key, UIParent)
        Media:CreateBackdrop(holder)
        local bar = Media:CreateStatusBar(holder)
        bar:SetAllPoints(holder)
        -- Texte porté par un cadre au-dessus de l'overlay d'absorption.
        local textLayer = CreateFrame("Frame", nil, bar)
        textLayer:SetAllPoints(bar)
        textLayer:SetFrameLevel(bar:GetFrameLevel() + 2)
        bar.text = Media:CreateText(textLayer, "OVERLAY", -2)
        bar.text:SetPoint("CENTER")
        bar.ticks = {}
        bar.holder = holder
        if spec.key == "health" then
            -- Absorptions : remplissage inversé depuis le bout de la barre.
            -- StatusBar nue : le fond opaque de CreateStatusBar masquerait la vie et son texte.
            bar.absorb = CreateFrame("StatusBar", nil, bar)
            bar.absorb:SetAllPoints(bar)
            bar.absorb:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
            bar.absorb:SetFrameLevel(bar:GetFrameLevel() + 1)
            bar.absorb:SetStatusBarColor(0.9, 0.9, 1, 0.5)
            if bar.absorb.SetReverseFill then bar.absorb:SetReverseFill(true) end
            bar.absorb:Hide()
        end
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
    Elements.SetBarValue(bar, UnitHealth("player"), db)
    local r, g, b = Elements.HealthColor("player", db.classColor)
    Media:SetHealthColor(bar, Elements.BandColor("player", "health", bar.steps, r, g, b))
    Elements.SetUnitText(bar.text, "player", "health", Elements.TextFormat(nil, db.healthText))
    Elements.SetHashLines(bar, bar.hashPercents, bar.vertical, bar.vertical and bar:GetHeight() or bar:GetWidth() or db.width)
    local absorb = bar.absorb
    if absorb then
        local amount
        if db.healthAbsorb then
            local _, predicted = NS.GetHealPrediction(bar, "player")
            amount = predicted
            if not NS.IsSecret(amount) and amount == nil and _G.UnitGetTotalAbsorbs then amount = UnitGetTotalAbsorbs("player") end
        end
        if NS.IsSecret(amount) or amount ~= nil then   -- montant peut-être secret : passé sans comparaison
            absorb:SetOrientation(bar.vertical and "VERTICAL" or "HORIZONTAL")
            absorb:SetMinMaxValues(0, UnitHealthMax("player"))
            absorb:SetValue(amount)
            absorb:Show()
        else
            absorb:Hide()
        end
    end
    return true
end

local function UpdatePower(db)
    local bar = bars.power
    -- Mana forcé : type de puissance explicite (druide en forme), sinon la puissance affichée.
    local powerType = db.powerForceMana and ManaType() or nil
    if powerType then   -- classe sans mana (guerrier, voleur) : la barre de puissance reste
        local manaMax = Known(UnitPowerMax("player", powerType))
        if manaMax and manaMax <= 0 then powerType = nil end
    end
    local max = UnitPowerMax("player", powerType)
    local knownMax = Known(max)
    if knownMax and knownMax <= 0 then return false end
    bar:SetMinMaxValues(0, max)
    Elements.SetBarValue(bar, UnitPower("player", powerType), db)
    local r, g, b = Elements.PowerColor("player")
    if powerType then
        local mr, mg, mb = NS.PowerColor("MANA")
        if mr then r, g, b = mr, mg, mb end
    end
    if powerType then bar:SetStatusBarColor(r, g, b)   -- paliers calculés sur la puissance, pas sur le mana
    else bar:SetStatusBarColor(Elements.BandColor("player", "power", bar.steps, r, g, b)) end
    Elements.SetUnitText(bar.text, "player", powerType and "mana" or "power", Elements.TextFormat(nil, db.powerText))
    Elements.SetManaSpark(bar, db.manaSpark)
    Elements.SetManaCostPrediction(bar, db.manaCostPrediction)
    -- Largeur lue sur la barre : celle reprise d'une cible comprise.
    Elements.SetHashLines(bar, bar.hashPercents, bar.vertical, bar.vertical and bar:GetHeight() or bar:GetWidth() or db.width)
    return true
end

-- Même rendu que les points de combo du cadre joueur (graduations comprises).
local comboHost = { comboAllowed = true, unit = "player", cfg = {} }
local function UpdateCombo()
    local bar = bars.combo
    comboHost.combo = bar
    comboHost.cfg.comboColor = ResourceBars.db.comboColor
    bar.width = bar:GetWidth()
    Elements.UpdateCombo(comboHost)
    return bar:IsShown()
end

--- Mana d'un druide en forme : seulement si la puissance affichée n'est pas le mana.
local function UpdateDruidMana(db)
    local bar = bars.druidMana
    local powerType = Known(UnitPowerType("player"))
    if powerType == nil or powerType == ManaType() then return false end
    local max = UnitPowerMax("player", ManaType())
    local knownMax = Known(max)
    if not knownMax or knownMax <= 0 then return false end
    bar:SetMinMaxValues(0, max)
    Elements.SetBarValue(bar, UnitPower("player", ManaType()), db)
    local r, g, b = NS.PowerColor("MANA")
    if r then bar:SetStatusBarColor(r, g, b) else bar:SetStatusBarColor(0, 0.44, 0.87) end
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
        local wanted = db[spec.key] and (visible or (active and NS:Previewing()))
        bar.wanted = wanted
        local shown = wanted and UPDATERS[spec.key](db) or false
        holder:SetShown(shown and true or false)
        local idleAlpha = (spec.key == "combo" and db.comboAlphaOwn) and db.comboAlpha or db.outOfCombatAlpha
        holder:SetAlpha((inCombat or NS:Previewing()) and 1 or idleAlpha)
    end
end

function ResourceBars:Layout()
    local db = self.db
    for _, spec in ipairs(BARS) do
        local bar = bars[spec.key]
        local own = db[spec.key .. "Orientation"]
        local vertical = (own == "inherit" or own == nil) and db.orientation == "VERTICAL" or own == "VERTICAL"
        local thickness = db[spec.key .. "Height"]
        -- Verticale : la longueur passe en hauteur, l'épaisseur en largeur.
        if vertical then bar.holder:SetSize(thickness, db.width) else bar.holder:SetSize(db.width, thickness) end
        bar.vertical = vertical
        bar.steps = Elements.Bands(db[spec.key .. "Low"], db[spec.key .. "LowColor"], db[spec.key .. "Mid"], db[spec.key .. "MidColor"])
        bar.hashPercents = Elements.HashPercents(db[spec.key .. "HashLines"], spec.key == "power" and db.threshold)
        bar:SetOrientation(vertical and "VERTICAL" or "HORIZONTAL")
        if bar.SetRotatesTexture then bar:SetRotatesTexture(vertical) end
        bar.holder:SetFrameStrata(db.strata)
        if bar.text and db[spec.key .. "TextAnchor"] then   -- vie et puissance : texte réglable
            local anchor = db[spec.key .. "TextAnchor"]
            bar.text:ClearAllPoints()
            bar.text:SetPoint(anchor, bar, anchor, db[spec.key .. "TextX"], db[spec.key .. "TextY"])
            Media:SetTextSizeDelta(bar.text, -2 + db[spec.key .. "TextSizeBonus"])
        end
    end
end

function ResourceBars:GetBars() return bars end

--------------------------------------------------------------------------------
-- Cycle de vie
--------------------------------------------------------------------------------

-- Événement d'unité -> barres qu'il touche ; la visibilité n'en dépend pas.
local POWER_BARS = { "power", "combo", "druidMana" }
local UNIT_EVENT_BARS = {
    UNIT_HEALTH = { "health" }, UNIT_MAXHEALTH = { "health" },
    UNIT_ABSORB_AMOUNT_CHANGED = { "health" }, UNIT_HEAL_ABSORB_AMOUNT_CHANGED = { "health" },
    UNIT_POWER_FREQUENT = POWER_BARS, UNIT_MAXPOWER = POWER_BARS, UNIT_DISPLAYPOWER = POWER_BARS,
}
local EVENTS = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_TARGET_CHANGED",
                 "UPDATE_SHAPESHIFT_FORM", "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE",
                 "ZONE_CHANGED_NEW_AREA", "PLAYER_MOUNT_DISPLAY_CHANGED",
                 "COMBO_TARGET_CHANGED", "PLAYER_SOFT_ENEMY_CHANGED", "GAME_PAD_ACTIVE_CHANGED",
                 "PLAYER_UPDATE_RESTING" }
local PLAYER_EVENTS = { "UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE" }   -- visibilité « en véhicule »

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
    local keys = UNIT_EVENT_BARS[event]
    if not keys then ResourceBars:Update(event) return end
    if not (active and bars.power) then return end
    local db = ResourceBars.db
    for _, key in ipairs(keys) do
        local bar = bars[key]
        if bar.wanted then bar.holder:SetShown(UPDATERS[key](db) and true or false) end
    end
end)

--- Événements d'unité des seules barres activées.
local function RegisterUnitEvents(db)
    for event, keys in pairs(UNIT_EVENT_BARS) do
        local wanted = false
        for _, key in ipairs(keys) do wanted = wanted or db[key] end
        events:UnregisterEvent(event)
        if wanted then NS.RegisterEventSafe(events, event, "player") end
    end
end

function ResourceBars:OnEnable()
    if not bars.power then Build() end
    active = true
    RegisterUnitEvents(self.db)
    for _, event in ipairs(EVENTS) do NS.RegisterEventSafe(events, event) end
    for _, event in ipairs(PLAYER_EVENTS) do NS.RegisterEventSafe(events, event, "player") end
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
    if bars.power then
        Elements.SetManaSpark(bars.power, false)
        Elements.SetManaCostPrediction(bars.power, false)
        self:Update()
    end
end

function ResourceBars:OnRefresh()
    if active then RegisterUnitEvents(self.db) end
    self:Layout()
    self:Update()
end

NS:On("PREVIEW", function() if bars.power then ResourceBars:Update() end end)

--- Paliers de couleur et repères d'une barre (`key` : "health" ou "power").
local function TextOptions(o, key)
    o:Advanced()
    o:Dropdown(key .. "TextAnchor", L.OPT_G_RES_TEXT_ANCHOR, Elements.AuraTextPointChoices(), 36)
    o:Slider(key .. "TextX", L.OPT_G_RES_TEXT_X, -50, 50, 1, 36)
    o:Slider(key .. "TextY", L.OPT_G_RES_TEXT_Y, -30, 30, 1, 36)
    o:Slider(key .. "TextSizeBonus", L.OPT_G_RES_TEXT_SIZE, -4, 8, 1, 36)
    o:EndAdvanced()
end

--- Orientation propre à une barre (hérite de la commune par défaut).
local function OrientationOption(o, key)
    o:Advanced()
    o:Dropdown(key .. "Orientation", L.OPT_BAR_ORIENTATION, {
        { name = L.OPT_G_RES_ORIENTATION_INHERIT, value = "inherit" },
        { name = L.OPT_BAR_HORIZONTAL, value = "HORIZONTAL" }, { name = L.OPT_BAR_VERTICAL, value = "VERTICAL" },
    }, 36)
    o:EndAdvanced()
end

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
    o:Check("smoothBars", L.OPT_GF_G_SMOOTH)
    o:Advanced()
    o:Dropdown("strata", L.OPT_G_RES_STRATA, {
        { name = L.OPT_STRATA_LOW, value = "LOW" }, { name = L.OPT_STRATA_MEDIUM, value = "MEDIUM" },
        { name = L.OPT_STRATA_HIGH, value = "HIGH" },
    })
    o:Slider("outOfCombatAlpha", L.OPT_RESOURCE_ALPHA, 0, 1, 0.05, nil, "%.2f")
    o:EndAdvanced()
    o:Visibility("visibility", L.OPT_VISIBILITY,{ noMouseover = true })
    o:Title(L.OPT_RESOURCE_HEALTH)
    o:Check("health", L.OPT_RESOURCE_SHOW)
    o:Slider("healthHeight", L.OPT_RESOURCE_HEIGHT, 4, 40, 1, 36)
    o:Dropdown("healthText", L.OPT_RESOURCE_TEXT, modes, 36)
    o:Check("classColor", L.OPT_RESOURCE_CLASS_COLOR, 36)
    o:Check("healthAbsorb", L.OPT_G_RES_ABSORB, 36)
    TextOptions(o, "health")
    OrientationOption(o, "health")
    BandOptions(o, "health")
    o:Title(L.OPT_RESOURCE_POWER)
    o:Check("power", L.OPT_RESOURCE_SHOW)
    o:Slider("powerHeight", L.OPT_RESOURCE_HEIGHT, 4, 40, 1, 36)
    o:Check("powerForceMana", L.OPT_G_RES_FORCE_MANA, 36)
    o:Check("manaSpark", L.OPT_MANA_SPARK, 36)
    o:Check("manaCostPrediction", L.OPT_MANA_COST_PREDICTION, 36)
    o:Dropdown("powerText", L.OPT_RESOURCE_TEXT, modes, 36)
    o:Advanced()
    o:Slider("threshold", L.OPT_RESOURCE_THRESHOLD, 0, 100, 5, 36)
    o:EndAdvanced()
    TextOptions(o, "power")
    OrientationOption(o, "power")
    BandOptions(o, "power")
    o:Title(L.OPT_RESOURCE_COMBO)
    o:Check("combo", L.OPT_RESOURCE_SHOW)
    o:Slider("comboHeight", L.OPT_RESOURCE_HEIGHT, 4, 30, 1, 36)
    o:Color("comboColor", L.OPT_G_RES_COMBO_COLOR, 36)
    o:Check("comboAlphaOwn", L.OPT_G_RES_COMBO_ALPHA_OWN, 36)
    o:Slider("comboAlpha", L.OPT_RESOURCE_ALPHA, 0, 1, 0.05, 52, "%.2f")
    OrientationOption(o, "combo")
    o:Title(L.OPT_RESOURCE_DRUID_MANA)
    o:Check("druidMana", L.OPT_RESOURCE_SHOW)
    o:Slider("druidManaHeight", L.OPT_RESOURCE_HEIGHT, 2, 30, 1, 36)
    OrientationOption(o, "druidMana")
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

-- Modules/SwingTimer.lua
-- Minuteur d'attaque automatique : une barre par arme (main droite, main gauche, distance)
-- qui se vide jusqu'au prochain coup. Source : l'événement PLAYER_SWING (durée, type d'arme)
-- du moteur 12.x ; sans lui (pas de journal de combat sur ce client), le module reste inerte
-- et le dit dans ses options. Coup en file (Frappe héroïque, Enchaînement, Mutiler) :
-- la barre de main droite change de couleur.
-- Le moteur anime la barre (SetTimerDuration) ; le Lua ne tourne que pendant un coup, pour le
-- texte du temps restant et la fin du coup. Cible hors de portée : barre atténuée.
local _, NS = ...
local L = NS.L
local Media = NS.Media

local SwingTimer = NS.Modules:Register("swingtimer", {
    titleKey = "SWING_TITLE",
    descKey = "SWING_DESC",
    defaults = {
        enabled = false,
        mainHand = true,
        offHand = true,
        ranged = true,
        visibility = NS.Visibility.Spec({ combat = "yes" }),   -- conditions communes (Core/Visibility)
        width = 200,              -- longueur des barres (hauteur si verticales)
        orientation = "HORIZONTAL", -- "HORIZONTAL" (barres empilées) ou "VERTICAL" (côte à côte)
        height = 10,
        spacing = 2,
        showTime = true,          -- temps restant avant le coup
        showLabel = false,        -- étiquette de l'arme (MD, MG, Dist.)
        rangeCheck = true,        -- barre atténuée quand la cible est hors de portée
        rangeAlpha = 0.35,
        color = { r = 0.85, g = 0.85, b = 0.85 },
        offHandColor = { r = 0.6, g = 0.75, b = 0.95 },
        rangedColor = { r = 0.55, g = 0.85, b = 0.45 },
        queueColor = { r = 1, g = 0.55, b = 0.1 },
    },
})

local HANDS = { "mainHand", "offHand", "ranged" }
local COLOR_KEYS = { mainHand = "color", offHand = "offHandColor", ranged = "rangedColor" }
local LABEL_KEYS = { mainHand = "SWING_LABEL_MAIN", offHand = "SWING_LABEL_OFF", ranged = "SWING_LABEL_RANGED" }
local QUEUED_SPELLS = { 78, 845, 6807 }   -- Frappe héroïque, Enchaînement, Mutiler (tous rangs : même nom)

local active = false
local container
local bars = {}   -- [hand] = StatusBar
local live = 0    -- barres en cours de coup

--- Le client donne-t-il les coups d'arme ?
function SwingTimer.Available()
    return _G.C_SwingTimer ~= nil and NS.EventExists("PLAYER_SWING")
end

--- Enum.PlayerSwingType de chaque barre (0, 1, 2 sans l'énumération).
local function SwingType(hand)
    local types = Enum and Enum.PlayerSwingType
    if hand == "offHand" then return types and types.OffHand or 1 end
    if hand == "ranged" then return types and types.Ranged or 2 end
    return types and types.MainHand or 0
end

--- Type de coup (Enum.PlayerSwingType) -> clé de barre ; main droite par défaut.
function SwingTimer.HandFor(swingType)
    local types = Enum and Enum.PlayerSwingType
    if types then
        if swingType == types.OffHand then return "offHand" end
        if swingType == types.Ranged then return "ranged" end
    end
    return "mainHand"
end

local function QueuedName()
    if not (C_Spell and C_Spell.IsCurrentSpell) then return false end
    for _, id in ipairs(QUEUED_SPELLS) do
        local ok, current = pcall(C_Spell.IsCurrentSpell, NS.GetSpellName(id) or id)
        if ok and not NS.IsSecret(current) and current then return true end
    end
    return false
end

--- Fin du coup : barre vide, texte effacé.
local function Idle(bar)
    if bar.live then bar.live, live = false, live - 1 end
    bar.expires = nil
    if not NS.SetBarTimer(bar, GetTime() - 1, 1, true) then bar:SetValue(0) end
    bar.time:SetText("")
end

-- Pendant un coup seulement : temps restant, fin du coup, remplissage si le moteur ne le fait pas.
local function Tick()
    local now = GetTime()
    for _, bar in pairs(bars) do
        if bar.live then
            local remaining = bar.expires - now
            if remaining <= 0 then
                Idle(bar)
            else
                if not bar.engine then bar:SetValue(remaining) end
                if SwingTimer.db.showTime then bar.time:SetFormattedText("%.1f", remaining) end
            end
        end
    end
    if live <= 0 then container:SetScript("OnUpdate", nil) end
end

local function Build()
    container = CreateFrame("Frame", "AeonUISwingTimer", UIParent)
    for _, hand in ipairs(HANDS) do
        local bar = Media:CreateStatusBar(container)
        Media:CreateBackdrop(bar)
        bar.hand = hand
        bar.time = Media:CreateText(bar, "OVERLAY", -2)
        bar.label = Media:CreateText(bar, "OVERLAY", -2)
        bars[hand] = bar
    end
    container:Hide()
end

function SwingTimer:Layout()
    local db = self.db
    local vertical = db.orientation == "VERTICAL"
    local offset = 0
    for _, hand in ipairs(HANDS) do
        local bar = bars[hand]
        bar:ClearAllPoints()
        bar:SetOrientation(vertical and "VERTICAL" or "HORIZONTAL")
        if bar.SetRotatesTexture then bar:SetRotatesTexture(vertical) end
        bar.time:ClearAllPoints()
        bar.label:ClearAllPoints()
        if vertical then
            bar:SetSize(db.height, db.width)
            bar:SetPoint("LEFT", container, "LEFT", offset, 0)
            bar.time:SetPoint("BOTTOM", bar, "TOP", 0, 2)
            bar.label:SetPoint("TOP", bar, "BOTTOM", 0, -2)
        else
            bar:SetSize(db.width, db.height)
            bar:SetPoint("TOP", container, "TOP", 0, -offset)
            bar.time:SetPoint("RIGHT", bar, "RIGHT", -2, 0)
            bar.label:SetPoint("LEFT", bar, "LEFT", 2, 0)
        end
        bar.label:SetText(L[LABEL_KEYS[hand]])
        bar.label:SetShown(db.showLabel)
        bar.time:SetShown(db.showTime)
        -- Une barre par arme équipée (vitesse lue) : pas de main gauche sans arme.
        local speed = self:Speed(hand)
        local shown = db[hand] and (NS.IsSecret(speed) or speed ~= nil)
        bar:SetShown(shown)
        if shown then offset = offset + db.height + db.spacing end
        local c = db[COLOR_KEYS[hand]]
        bar:SetStatusBarColor(c.r, c.g, c.b)
        -- Portée suivie par le moteur seulement pour les barres montrées.
        local check = active and shown and db.rangeCheck
        NS.SetSwingRangeCheck(SwingType(hand), check)
        bar.rangeChecked = check
    end
    local thickness = math.max(db.height, offset - db.spacing)
    if vertical then container:SetSize(thickness, db.width) else container:SetSize(db.width, thickness) end
    self:UpdateRange()
end

--- Vitesse de l'arme (secondes) ou nil si aucune.
function SwingTimer:Speed(hand)
    if hand == "ranged" then
        if not _G.UnitRangedDamage then return nil end
        local speed = UnitRangedDamage("player")
        if NS.IsSecret(speed) then return speed end
        if not speed or speed <= 0 then return nil end
        return speed
    end
    if not _G.UnitAttackSpeed then return hand == "mainHand" and 2 or nil end
    local main, off = UnitAttackSpeed("player")
    local speed = hand == "mainHand" and main or off
    if NS.IsSecret(speed) then return speed end
    if not speed or speed <= 0 then return nil end
    return speed
end

function SwingTimer:Swing(duration, swingType)
    if NS.IsSecret(duration) or type(duration) ~= "number" or duration <= 0 then return end
    local bar = bars[SwingTimer.HandFor(swingType)]
    if not bar then return end
    local now = GetTime()
    bar:SetMinMaxValues(0, duration)
    bar.expires = now + duration
    bar.engine = NS.SetBarTimer(bar, now, duration, true)
    if not bar.engine then bar:SetValue(duration) end
    if self.db.showTime then bar.time:SetFormattedText("%.1f", duration) end
    if not bar.live then bar.live, live = true, live + 1 end
    container:SetScript("OnUpdate", Tick)
end

--- Barre atténuée quand la cible est hors de portée. nil (pas de vérification) : pleine opacité.
function SwingTimer:SetOutOfRange(hand, out)
    local bar = bars[hand]
    if bar then bar:SetAlpha(out and self.db.rangeAlpha or 1) end
end

function SwingTimer:UpdateRange()
    for hand, bar in pairs(bars) do
        local out = bar.rangeChecked and NS.IsSwingTargetInRange(SwingType(hand)) == false
        self:SetOutOfRange(hand, out)
    end
end

function SwingTimer:Update(event)
    if not container then return end
    local db = self.db
    if active then NS.Visibility:Refresh("swingTimer") else container:Hide() end
    local c = QueuedName() and db.queueColor or db.color
    bars.mainHand:SetStatusBarColor(c.r, c.g, c.b)
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_SWING" then
        SwingTimer:Swing(...)
    elseif event == "PLAYER_SWING_RANGE_UPDATE" then
        local swingType, inRange, checks = ...
        if NS.IsSecret(swingType) or NS.IsSecret(inRange) or NS.IsSecret(checks) then return end
        local hand = SwingTimer.HandFor(swingType)
        SwingTimer:SetOutOfRange(hand, bars[hand].rangeChecked and checks == true and inRange == false)
    elseif event == "PLAYER_TARGET_CHANGED" then
        SwingTimer:Layout()   -- le client peut couper le suivi de portée : réarmé, puis relu
    elseif event == "PLAYER_DEAD" then
        for _, bar in pairs(bars) do if bar.live then Idle(bar) end end
    elseif event == "UNIT_ATTACK_SPEED" or event == "PLAYER_EQUIPMENT_CHANGED" then
        SwingTimer:Layout()
    else
        SwingTimer:Update(event)
    end
end)

function SwingTimer:OnEnable()
    if not SwingTimer.Available() then return end
    if not container then Build() end
    active = true
    for _, event in ipairs({ "PLAYER_SWING", "PLAYER_SWING_RANGE_UPDATE", "PLAYER_TARGET_CHANGED", "PLAYER_DEAD",
                             "PLAYER_EQUIPMENT_CHANGED", "CURRENT_SPELL_CAST_CHANGED" }) do
        NS.RegisterEventSafe(events, event)
    end
    NS.RegisterEventSafe(events, "UNIT_ATTACK_SPEED", "player")
    self:Layout()
    NS.Movers:Register("swingTimer", container, L.MOVER_SWING, "CENTER", 0, -240)
    NS.Movers:Load("swingTimer")
    -- Déverrouillé : visible pour être placé.
    NS.Visibility:Register("swingTimer", container, function() return self.db.visibility end,
        { forceVisible = function() return NS.unlocked end })
    self:Update()
end

function SwingTimer:OnDisable()
    active = false
    events:UnregisterAllEvents()
    NS.Visibility:Unregister("swingTimer")
    NS.Movers:Unregister("swingTimer")
    if container then
        for _, hand in ipairs(HANDS) do NS.SetSwingRangeCheck(SwingType(hand), false) end
        self:Update()
    end
end

function SwingTimer:OnRefresh()
    if not container then return end
    self:Layout()
    self:Update()
end

NS:On("UNLOCK", function() SwingTimer:Update() end)

function SwingTimer:BuildOptions(o)
    if not SwingTimer.Available() then o:Note(L.SWING_UNAVAILABLE) end
    o:Check("mainHand", L.OPT_SWING_MAIN)
    o:Check("offHand", L.OPT_SWING_OFF)
    o:Check("ranged", L.OPT_SWING_RANGED)
    o:Check("showTime", L.OPT_SWING_SHOW_TIME)
    o:Advanced()
    o:Check("showLabel", L.OPT_SWING_SHOW_LABEL)
    o:Check("rangeCheck", L.OPT_SWING_RANGE_CHECK)
    o:Slider("rangeAlpha", L.OPT_SWING_RANGE_ALPHA, 0.1, 0.9, 0.05, 36, "%.2f")
    o:EndAdvanced()
    o:Dropdown("orientation", L.OPT_BAR_ORIENTATION, {
        { name = L.OPT_BAR_HORIZONTAL, value = "HORIZONTAL" }, { name = L.OPT_BAR_VERTICAL, value = "VERTICAL" },
    })
    o:Slider("width", L.OPT_RESOURCE_WIDTH, 60, 400, 2)
    o:Slider("height", L.OPT_RESOURCE_HEIGHT, 4, 30, 1)
    o:Color("color", L.OPT_SWING_COLOR)
    o:Advanced()
    o:Color("offHandColor", L.OPT_SWING_OFF_COLOR)
    o:Color("rangedColor", L.OPT_SWING_RANGED_COLOR)
    o:Color("queueColor", L.OPT_SWING_QUEUE_COLOR)
    o:Visibility("visibility", L.OPT_VISIBILITY)
end

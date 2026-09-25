-- Modules/SwingTimer.lua
-- Minuteur d'attaque automatique : une barre par arme (main droite, main gauche, distance)
-- qui se vide jusqu'au prochain coup. Source : l'événement PLAYER_SWING (durée, type d'arme)
-- du moteur 12.x ; sans lui (pas de journal de combat sur ce client), le module reste inerte
-- et le dit dans ses options. Coup en file (Frappe héroïque, Enchaînement, Mutiler) :
-- la barre de main droite change de couleur.
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
        combatOnly = true,
        width = 200,              -- longueur des barres (hauteur si verticales)
        orientation = "HORIZONTAL", -- "HORIZONTAL" (barres empilées) ou "VERTICAL" (côte à côte)
        height = 10,
        spacing = 2,
        color = { r = 0.85, g = 0.85, b = 0.85 },
        queueColor = { r = 1, g = 0.55, b = 0.1 },
    },
})

local HANDS = { "mainHand", "offHand", "ranged" }
local QUEUED_SPELLS = { 78, 845, 6807 }   -- Frappe héroïque, Enchaînement, Mutiler (tous rangs : même nom)

local active = false
local container
local bars = {}   -- [hand] = StatusBar

--- Le client donne-t-il les coups d'arme ?
function SwingTimer.Available()
    return _G.C_SwingTimer ~= nil and NS.EventExists("PLAYER_SWING")
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
        local ok, current = pcall(C_Spell.IsCurrentSpell, id)
        if ok and not NS.IsSecret(current) and current then return true end
    end
    return false
end

local function OnUpdate(bar)
    local remaining = (bar.expires or 0) - GetTime()
    if remaining <= 0 then
        bar:SetValue(0)
        bar:SetScript("OnUpdate", nil)
        return
    end
    bar:SetValue(remaining)
end

local function Build()
    container = CreateFrame("Frame", "AeonUISwingTimer", UIParent)
    for _, hand in ipairs(HANDS) do
        local bar = Media:CreateStatusBar(container)
        Media:CreateBackdrop(bar)
        bar.hand = hand
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
        if vertical then
            bar:SetSize(db.height, db.width)
            bar:SetPoint("LEFT", container, "LEFT", offset, 0)
        else
            bar:SetSize(db.width, db.height)
            bar:SetPoint("TOP", container, "TOP", 0, -offset)
        end
        -- Une barre par arme équipée (vitesse lue) : pas de main gauche sans arme.
        local speed = self:Speed(hand)
        local shown = db[hand] and speed ~= nil
        bar:SetShown(shown)
        if shown then offset = offset + db.height + db.spacing end
        local c = db.color
        bar:SetStatusBarColor(c.r, c.g, c.b)
    end
    local thickness = math.max(db.height, offset - db.spacing)
    if vertical then container:SetSize(thickness, db.width) else container:SetSize(db.width, thickness) end
end

--- Vitesse de l'arme (secondes) ou nil si aucune.
function SwingTimer:Speed(hand)
    if hand == "ranged" then
        if not _G.UnitRangedDamage then return nil end
        local speed = UnitRangedDamage("player")
        if NS.IsSecret(speed) or not speed or speed <= 0 then return nil end
        return speed
    end
    if not _G.UnitAttackSpeed then return hand == "mainHand" and 2 or nil end
    local main, off = UnitAttackSpeed("player")
    local speed = hand == "mainHand" and main or off
    if NS.IsSecret(speed) or not speed or speed <= 0 then return nil end
    return speed
end

function SwingTimer:Swing(duration, swingType)
    if NS.IsSecret(duration) or type(duration) ~= "number" or duration <= 0 then return end
    local bar = bars[SwingTimer.HandFor(swingType)]
    if not bar then return end
    bar:SetMinMaxValues(0, duration)
    bar.expires = GetTime() + duration
    bar:SetValue(duration)
    bar:SetScript("OnUpdate", OnUpdate)
end

function SwingTimer:Update(event)
    if not container then return end
    local db = self.db
    local inCombat = event == "PLAYER_REGEN_DISABLED" or (event ~= "PLAYER_REGEN_ENABLED" and NS.InCombat())
    container:SetShown(active and (inCombat or not db.combatOnly or NS.unlocked) and true or false)
    local c = QueuedName() and db.queueColor or db.color
    bars.mainHand:SetStatusBarColor(c.r, c.g, c.b)
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_SWING" then
        SwingTimer:Swing(...)
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
    NS.RegisterEventSafe(events, "PLAYER_SWING")
    NS.RegisterEventSafe(events, "UNIT_ATTACK_SPEED", "player")
    NS.RegisterEventSafe(events, "PLAYER_EQUIPMENT_CHANGED")
    NS.RegisterEventSafe(events, "CURRENT_SPELL_CAST_CHANGED")
    NS.RegisterEventSafe(events, "PLAYER_REGEN_DISABLED")
    NS.RegisterEventSafe(events, "PLAYER_REGEN_ENABLED")
    self:Layout()
    NS.Movers:Register("swingTimer", container, L.MOVER_SWING, "CENTER", 0, -240)
    NS.Movers:Load("swingTimer")
    self:Update()
end

function SwingTimer:OnDisable()
    active = false
    events:UnregisterAllEvents()
    NS.Movers:Unregister("swingTimer")
    if container then self:Update() end
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
    o:Check("combatOnly", L.OPT_SWING_COMBAT_ONLY)
    o:Dropdown("orientation", L.OPT_BAR_ORIENTATION, {
        { name = L.OPT_BAR_HORIZONTAL, value = "HORIZONTAL" }, { name = L.OPT_BAR_VERTICAL, value = "VERTICAL" },
    })
    o:Slider("width", L.OPT_RESOURCE_WIDTH, 60, 400, 2)
    o:Slider("height", L.OPT_RESOURCE_HEIGHT, 4, 30, 1)
    o:Color("color", L.OPT_SWING_COLOR)
    o:Color("queueColor", L.OPT_SWING_QUEUE_COLOR)
end

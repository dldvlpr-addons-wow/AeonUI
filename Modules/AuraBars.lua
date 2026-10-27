-- Modules/AuraBars.lua
-- Barres d'auras du joueur : une barre horizontale par buff ou débuff (icône, nom, temps
-- restant), la plus courte en premier, sur un mover. Débuffs à la couleur de leur type.
-- Quand le client offre le conteneur d'auras du moteur, c'est lui qui lit, trie et remplit les
-- barres (en combat compris) : débuffs d'abord, puis buffs, chacun du plus court au plus long.
-- Sinon, voie maison : objet durée du moteur quand il existe (secret compris), sinon valeurs
-- lisibles ; illisible (combat) : barre pleine, sans chiffre.
-- Enchantements d'arme temporaires (imprégnations, poisons, huiles…) : barres en tête de pile,
-- au-dessus des buffs ; le conteneur du moteur est ancré sous elles.
local _, NS = ...
local L = NS.L
local Media = NS.Media

local AuraBars = NS.Modules:Register("aurabars", {
    titleKey = "AURABARS_TITLE",
    descKey = "AURABARS_DESC",
    defaults = {
        enabled = false,
        show = "both",            -- "buffs", "debuffs", "both"
        hidePermanent = true,     -- auras sans durée (formes, auras de paladin) écartées
        weaponEnchants = true,    -- enchantements d'arme temporaires en tête de pile
        maxBars = 12,
        width = 220,
        height = 18,
        spacing = 2,
        growUp = false,
        sort = "shortest",        -- "shortest", "longest" (durée restante), "name"
        showBorder = true,
        textSizeBonus = 0,        -- points ajoutés à la taille des textes
        preciseBelow = 0,         -- dixièmes de seconde sous ce seuil (barres maison), 0 : jamais
        buffColor = { r = 0.25, g = 0.66, b = 0.96 },
    },
})

local MAX_AURAS = 40
local ENGINE_SORTS = { shortest = "expiration", longest = "expirationLongest", name = "name" }
local UPDATE_INTERVAL = 0.1

local active = false
local holder
local bars = {}
local list = {}
local engine            -- conteneur du moteur ; false : absent
local engineBars = {}   -- { bar, icon, harmful } des boutons du moteur, pour les retailler
local enchants = {}     -- enchantements d'arme, relus sur WEAPON_ENCHANT_CHANGED / WEAPON_SLOT_CHANGED

local function Known(value)
    if NS.IsSecret(value) then return nil end
    return value
end

--- Auras du joueur à afficher : { icon, name, duration, expiration, stacks, dispel, harmful, auraInstanceID },
-- la plus courte en premier (durée inconnue ensuite, permanentes à la fin).
function AuraBars.Collect()
    wipe(list)
    local db = AuraBars.db
    local filters = {}
    if db.show ~= "debuffs" then filters[#filters + 1] = "HELPFUL" end
    if db.show ~= "buffs" then filters[#filters + 1] = "HARMFUL" end
    for _, filter in ipairs(filters) do
        for index = 1, MAX_AURAS do
            local icon, duration, expiration, stacks, dispel, _, _, _, auraInstanceID, name = NS.GetAura("player", index, filter)
            if not NS.IsSecret(icon) and icon == nil then break end
            local knownDuration = Known(duration)
            if not (db.hidePermanent and knownDuration == 0) then
                list[#list + 1] = { icon = icon, name = name, duration = knownDuration, expiration = Known(expiration),
                                    stacks = Known(stacks), dispel = Known(dispel), harmful = filter == "HARMFUL",
                                    auraInstanceID = auraInstanceID }
            end
        end
    end
    local function Remaining(entry)
        if entry.duration == 0 then return math.huge end
        if not (entry.duration and entry.expiration) then return math.huge - 1 end
        return entry.expiration - GetTime()
    end
    local sort = db.sort
    table.sort(list, function(a, b)
        if sort == "name" then
            local nameA, nameB = Known(a.name) or "", Known(b.name) or ""
            if nameA ~= nameB then return nameA < nameB end
            return false
        end
        if sort == "longest" then return Remaining(a) > Remaining(b) end
        return Remaining(a) < Remaining(b)
    end)
    return list
end

local function FormatTime(seconds)
    local precise = AuraBars.db and AuraBars.db.preciseBelow or 0
    if seconds < precise then return string.format("%.1f", seconds) end
    seconds = math.floor(seconds + 0.5)   -- 599.9999 (expiration - GetTime() en flottants) donne 10m, pas 9m
    if seconds >= 3600 then return string.format("%dh", math.floor(seconds / 3600)) end
    if seconds >= 60 then return string.format("%dm", math.floor(seconds / 60)) end
    return tostring(seconds)
end

local function Bar(index)
    local bar = bars[index]
    if bar then return bar end
    bar = Media:CreateStatusBar(holder)
    bar.border = Media:CreateBorder(bar)
    bar.icon = bar:CreateTexture(nil, "ARTWORK")
    bar.icon:SetPoint("RIGHT", bar, "LEFT", -2, 0)
    bar.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    bar.name = Media:CreateText(bar, "OVERLAY")
    bar.name:SetPoint("LEFT", bar, "LEFT", 4, 0)
    bar.time = Media:CreateText(bar, "OVERLAY")
    bar.time:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
    bars[index] = bar
    return bar
end

local function Paint(bar, entry)
    local db = AuraBars.db
    local color = db.buffColor
    if entry.harmful then
        color = (entry.dispel and _G.DebuffTypeColor and DebuffTypeColor[entry.dispel])
            or (_G.DebuffTypeColor and DebuffTypeColor.none) or { r = 0.8, g = 0, b = 0 }
    end
    bar:SetStatusBarColor(color.r, color.g, color.b)
    bar.icon:SetTexture(entry.icon)
    local label = entry.name or ""
    if entry.stacks and entry.stacks > 1 then label = label .. " (" .. entry.stacks .. ")" end
    bar.name:SetText(label)
    bar.expiration = nil
    if entry.duration and entry.expiration and entry.duration > 0 then
        bar.expiration = entry.expiration
        if not NS.SetBarTimer(bar, entry.expiration - entry.duration, entry.duration, true) then
            bar:SetMinMaxValues(0, entry.duration)
            bar.manual = true
        end
    elseif not NS.SetAuraBarTimer(bar, "player", entry.auraInstanceID) then
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(1)
    end
    bar.time:SetText(bar.expiration and FormatTime(math.max(0, bar.expiration - GetTime())) or "")
end

--- Barre d'un bouton du moteur : icône à gauche, barre de durée, nom, temps, compteur. Débuffs à la
-- couleur de leur type (posée par le moteur), buffs à la couleur réglée.
local function InitEngineBar(slotButton, harmful)
    local db = AuraBars.db
    pcall(slotButton.SetSize, slotButton, db.width, db.height)
    pcall(slotButton.SetMouseClickEnabled, slotButton, false)
    pcall(slotButton.SetMouseMotionEnabled, slotButton, false)
    local frame = CreateFrame("Frame", nil, slotButton)
    frame:SetAllPoints(slotButton)
    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    icon:SetSize(db.height, db.height)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local bar = Media:CreateStatusBar(frame)
    bar:SetPoint("TOPLEFT", icon, "TOPRIGHT", 2, 0)
    bar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    local border = Media:CreateBorder(bar)
    local name = Media:CreateText(bar, "OVERLAY")
    name:SetPoint("LEFT", bar, "LEFT", 4, 0)
    local time = Media:CreateText(bar, "OVERLAY")
    time:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
    name:SetPoint("RIGHT", time, "LEFT", -4, 0)
    if name.SetWordWrap then name:SetWordWrap(false) end
    local count = Media:CreateText(bar, "OVERLAY", -2, "OUTLINE")
    count:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 0, 0)
    pcall(slotButton.SetIcon, slotButton, icon)
    pcall(slotButton.SetSpellName, slotButton, name)
    pcall(slotButton.SetDurationText, slotButton, time, {})
    pcall(slotButton.SetApplicationCount, slotButton, count)
    pcall(slotButton.SetDurationBar, slotButton, bar)
    if harmful then
        NS.AddDispelTexture(slotButton, bar:GetStatusBarTexture(), true)
    else
        local c = db.buffColor
        bar:SetStatusBarColor(c.r, c.g, c.b)
    end
    engineBars[#engineBars + 1] = { bar = bar, icon = icon, harmful = harmful, border = border,
                                    name = name, time = time, count = count }
end

--- Groupes du moteur d'après le réglage (hors combat : les boutons se retaillent).
local function LayoutEngine()
    if engine == nil then engine = NS.CreateAuraContainer(holder) or false end
    if not engine then return end
    local db = AuraBars.db
    local anchor = db.growUp and "BOTTOMRIGHT" or "TOPRIGHT"
    NS.SetAuraContainerFlow(engine, anchor, "LEFT", db.growUp and "UP" or "DOWN", nil, true)
    local candidates = { maxDuration = db.hidePermanent and math.huge or nil }
    local groups = {
        debuffs = { filter = "HARMFUL", shown = db.show ~= "buffs", index = 1, harmful = true },
        buffs = { filter = "HELPFUL", shown = db.show ~= "debuffs", index = 2, harmful = false },
    }
    for key, group in pairs(groups) do
        NS.SetAuraGroup(engine, key, { filter = group.filter, max = group.shown and db.maxBars or 0,
            index = group.index, width = db.width, height = db.height, spacing = db.spacing, sort = ENGINE_SORTS[db.sort] or "expiration",
            candidates = candidates, init = function(slotButton) InitEngineBar(slotButton, group.harmful) end })
        for _, slotButton in ipairs(NS.AuraGroupButtons(engine, key)) do
            pcall(slotButton.SetSize, slotButton, db.width, db.height)
        end
    end
    for _, entry in ipairs(engineBars) do
        entry.icon:SetSize(db.height, db.height)
        for _, edge in pairs(entry.border) do edge:SetShown(db.showBorder) end
        Media:SetTextSizeDelta(entry.name, db.textSizeBonus)
        Media:SetTextSizeDelta(entry.time, db.textSizeBonus)
        Media:SetTextSizeDelta(entry.count, -2 + db.textSizeBonus)
        if not entry.harmful then entry.bar:SetStatusBarColor(db.buffColor.r, db.buffColor.g, db.buffColor.b) end
    end
    NS.SetAuraContainerUnit(engine, "player", true)
end

--- Relit les enchantements d'arme (entrées au format de Collect).
local function ReadEnchants()
    wipe(enchants)
    if not (active and AuraBars.db.weaponEnchants) then return end
    for _, enchant in ipairs((NS.GetWeaponEnchants())) do
        enchants[#enchants + 1] = { icon = enchant.icon, name = enchant.name, duration = enchant.duration,
                                    expiration = enchant.expiration, stacks = enchant.charges }
    end
end

function AuraBars:Update()
    if not holder then return end
    local db = self.db
    local shown = 0
    local function Place(entry)
        if shown >= db.maxBars then return end
        shown = shown + 1
        local bar = Bar(shown)
        bar.manual = nil
        bar:SetSize(db.width - db.height - 2, db.height)
        bar.icon:SetSize(db.height, db.height)
        for _, edge in pairs(bar.border) do edge:SetShown(db.showBorder) end
        Media:SetTextSizeDelta(bar.name, db.textSizeBonus)
        Media:SetTextSizeDelta(bar.time, db.textSizeBonus)
        bar:ClearAllPoints()
        local offset = (shown - 1) * (db.height + db.spacing)
        if db.growUp then
            bar:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", 0, offset)
        else
            bar:SetPoint("TOPRIGHT", holder, "TOPRIGHT", 0, -offset)
        end
        Paint(bar, entry)
        bar:Show()
    end
    if active and db.show ~= "debuffs" then
        for _, entry in ipairs(enchants) do Place(entry) end
    end
    if engine then   -- le moteur lit et pose les auras, sous les barres d'arme
        local anchor = db.growUp and "BOTTOMRIGHT" or "TOPRIGHT"
        local offset = shown * (db.height + db.spacing)
        engine:ClearAllPoints()
        engine:SetPoint(anchor, holder, anchor, 0, db.growUp and offset or -offset)
    elseif active then
        for _, entry in ipairs(self.Collect()) do Place(entry) end
    end
    for index = shown + 1, #bars do bars[index]:Hide() end
    holder:SetSize(db.width, math.max(db.height, db.maxBars * (db.height + db.spacing) - db.spacing))
    holder:SetShown(active)
end

local function Build()
    holder = CreateFrame("Frame", "MuscaUIAuraBars", UIParent)
    local elapsed = 0
    holder:SetScript("OnUpdate", function(_, delta)
        elapsed = elapsed + delta
        if elapsed < UPDATE_INTERVAL then return end
        elapsed = 0
        local now = GetTime()
        for _, bar in ipairs(bars) do
            if bar:IsShown() and bar.expiration then
                local remaining = math.max(0, bar.expiration - now)
                bar.time:SetText(FormatTime(remaining))
                if bar.manual then bar:SetValue(remaining) end
            end
        end
    end)
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
    if event ~= "UNIT_AURA" then ReadEnchants() end
    AuraBars:Update()
end)

function AuraBars:OnEnable()
    if not holder then Build() end
    active = true
    NS.RegisterEventSafe(events, "UNIT_AURA", "player")
    NS.RegisterEventSafe(events, "PLAYER_ENTERING_WORLD")
    NS.RegisterEventSafe(events, "WEAPON_ENCHANT_CHANGED")
    NS.RegisterEventSafe(events, "WEAPON_SLOT_CHANGED")
    NS.Movers:Register("auraBars", holder, L.AURABARS_TITLE, "TOPRIGHT", -230, -300)
    NS.Movers:Load("auraBars")
    LayoutEngine()
    ReadEnchants()
    self:Update()
end

function AuraBars:OnDisable()
    active = false
    events:UnregisterAllEvents()
    NS.Movers:Unregister("auraBars")
    self:Update()
end

function AuraBars:OnRefresh()
    if holder then LayoutEngine() end
    ReadEnchants()
    self:Update()
end

function AuraBars:BuildOptions(o)
    o:Dropdown("show", L.OPT_AURABARS_SHOW, {
        { name = L.OPT_AURABARS_BOTH, value = "both" }, { name = L.OPT_AURABARS_BUFFS, value = "buffs" },
        { name = L.OPT_AURABARS_DEBUFFS, value = "debuffs" },
    })
    o:Dropdown("sort", L.OPT_G_RES_AURA_SORT, {
        { name = L.OPT_G_RES_AURA_SORT_SHORTEST, value = "shortest" },
        { name = L.OPT_G_RES_AURA_SORT_LONGEST, value = "longest" },
        { name = L.OPT_G_RES_AURA_SORT_NAME, value = "name" },
    })
    o:Check("hidePermanent", L.OPT_AURABARS_HIDE_PERMANENT)
    o:Check("weaponEnchants", L.OPT_AURABARS_WEAPON_ENCHANTS)
    o:Slider("maxBars", L.OPT_AURABARS_MAX, 1, 40, 1)
    o:Slider("width", L.OPT_RESOURCE_WIDTH, 100, 500, 2)
    o:Slider("height", L.OPT_RESOURCE_HEIGHT, 10, 40, 1)
    o:Advanced()
    o:Slider("spacing", L.OPT_AURABARS_SPACING, 0, 10, 1)
    o:Check("growUp", L.OPT_AURABARS_GROW_UP)
    o:Check("showBorder", L.OPT_G_RES_AURA_BORDER)
    o:Slider("textSizeBonus", L.OPT_G_QOL_REM_TEXT_SIZE, -4, 6, 1)
    o:Slider("preciseBelow", L.OPT_G_RES_AURA_PRECISE, 0, 60, 1, nil, "%d s")
    o:EndAdvanced()
    o:Color("buffColor", L.OPT_AURABARS_BUFF_COLOR)
end

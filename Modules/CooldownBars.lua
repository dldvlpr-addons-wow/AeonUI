-- Modules/CooldownBars.lua
-- Barres de recharges personnalisées : jusqu'à trois rangées d'icônes MuscaUI, une liste de sorts
-- chacune (identifiants, ramenés au rang appris, ou bijou « slot13 » / « slot14 »), choisie dans
-- le catalogue du gestionnaire de recharges ; recharge et charges du moteur, son « recharge
-- terminée », visibilité commune, sur leur mover. En complément des viewers Blizzard.
local _, NS = ...
local L = NS.L
local Media = NS.Media

local BAR_COUNT = 3
local TRINKET_SLOTS = { 13, 14 }
local CATALOG_CATEGORIES = { 0, 1, 2, 3, 5, 6, 7, 8 }
local SOUND_THROTTLE = 2

local function BarDefaults(enabled, y)
    return { enabled = enabled, spells = "", size = 36, spacing = 4, perRow = 12,
             hideReady = false, desaturate = true, y = y,
             visibility = NS.Visibility.Spec(), sound = true, soundPreset = "ping", soundFile = "" }
end

local CooldownBars = NS.Modules:Register("cooldownbars", {
    titleKey = "CDBARS_TITLE",
    descKey = "CDBARS_DESC",
    defaults = {
        enabled = false,
        bars = { bar1 = BarDefaults(true, -260), bar2 = BarDefaults(false, -310), bar3 = BarDefaults(false, -360) },
    },
})

local active = false
local loading = false  -- écran de chargement : aucun son
local frames = {}      -- [index] = { holder, icons }
local spellLists = {}  -- [index] = { text, list } : sorts connus, vidé sur SPELLS_CHANGED et OnRefresh

--- Jetons de la liste, dans l'ordre écrit : identifiants de sort et « slot13 » / « slot14 ».
function CooldownBars.Tokens(text)
    local tokens = {}
    for prefix, id in tostring(text or ""):gmatch("(%a*)(%d+)") do
        tokens[#tokens + 1] = prefix == "slot" and ("slot" .. id) or tonumber(id)
    end
    return tokens
end

--- Entrées affichables : { id, name } pour un sort connu, { slot } pour un bijou 13 ou 14.
function CooldownBars.Spells(text)
    local list, seen = {}, {}
    for _, token in ipairs(CooldownBars.Tokens(text)) do
        local slot = type(token) == "string" and tonumber(token:match("%d+"))
        if slot then
            if (slot == 13 or slot == 14) and not seen[token] then
                seen[token] = true
                list[#list + 1] = { slot = slot }
            end
        else
            local name = NS.GetSpellName(token)
            if name and not seen[name] and NS.KnowsSpell(token) then
                seen[name] = true
                list[#list + 1] = { id = NS.KnownSpellID(token), name = name }
            end
        end
    end
    return list
end

local function MoverKey(index) return "cooldownBar" .. index end

local function Icon(bar, index)
    local icon = bar.icons[index]
    if icon then return icon end
    icon = CreateFrame("Frame", nil, bar.holder)
    Media:CreateBackdrop(icon)
    icon.texture = icon:CreateTexture(nil, "ARTWORK")
    icon.texture:SetAllPoints(icon)
    icon.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon.cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    icon.cooldown:SetAllPoints(icon)
    NS.RegisterCooldown(icon.cooldown)
    -- fin de recharge sans événement (bijou) : barre relue à l'instant « prêt »
    icon.cooldown:HookScript("OnCooldownDone", function() if active then CooldownBars:UpdateBar(bar.index) end end)
    icon.count = Media:CreateText(icon, "OVERLAY", 0, "OUTLINE")
    icon.count:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -2, 2)
    bar.icons[index] = icon
    return icon
end

local function Frame(index)
    if frames[index] then return frames[index] end
    local bar = { holder = CreateFrame("Frame", "MuscaUICooldownBar" .. index, UIParent), icons = {}, index = index,
                  ready = {} }
    frames[index] = bar
    return bar
end

function CooldownBars:UpdateBar(index)
    local cfg = self.db.bars["bar" .. index]
    local bar = Frame(index)
    local on = active and cfg.enabled
    local shown = 0
    local perRow = math.max(1, cfg.perRow)
    local cached = spellLists[index]
    if on and (not cached or cached.text ~= cfg.spells) then
        cached = { text = cfg.spells, list = self.Spells(cfg.spells) }
        spellLists[index] = cached
    end
    local layout = cfg.size .. ":" .. cfg.spacing .. ":" .. perRow
    if bar.layout ~= layout then bar.layout, bar.placed, bar.holderKey = layout, {}, nil end
    local becameReady = false
    for _, spell in ipairs(on and cached.list or {}) do
        local texture, ready
        if spell.slot then
            _, texture = NS.GetInventorySlotItem(spell.slot)
            ready = NS.IsInventorySlotReady(spell.slot)
        else
            texture, ready = NS.GetSpellTexture(spell.id), NS.IsSpellReady(spell.id)
        end
        local key = spell.slot and ("slot" .. spell.slot) or spell.id
        if ready and bar.ready[key] == false then becameReady = true end
        bar.ready[key] = ready
        -- bijou absent : rien à montrer
        if texture and (not (cfg.hideReady and ready) or NS:Previewing()) then
            shown = shown + 1
            local icon = Icon(bar, shown)
            if not bar.placed[shown] then   -- position inchangée tant que la mise en page l'est
                bar.placed[shown] = true
                icon:SetSize(cfg.size, cfg.size)
                icon:ClearAllPoints()
                local row, column = math.floor((shown - 1) / perRow), (shown - 1) % perRow
                icon:SetPoint("TOPLEFT", bar.holder, "TOPLEFT", column * (cfg.size + cfg.spacing), -row * (cfg.size + cfg.spacing))
            end
            icon.texture:SetTexture(texture)
            if icon.texture.SetDesaturated then icon.texture:SetDesaturated(cfg.desaturate and ready == false) end
            local current, max
            if spell.slot then
                local start, duration = NS.GetInventorySlotCooldown(spell.slot)
                if start and duration > 0 then icon.cooldown:SetCooldown(start, duration) else icon.cooldown:SetCooldown(0, 0) end
            else
                NS.SetSpellCooldown(icon.cooldown, spell.id)
                current, max = NS.GetSpellCharges(spell.id)
            end
            if NS.IsSecret(current) then
                -- combat : le moteur affiche, rien n'est comparé
                if max > 1 then icon.count:SetText(current) else icon.count:SetText("") end
            else
                icon.count:SetText((current and max and max > 1) and tostring(current) or "")
            end
            icon:Show()
        end
    end
    for i = shown + 1, #bar.icons do bar.icons[i]:Hide() end
    if bar.holderKey ~= shown then
        bar.holderKey = shown
        local columns = math.max(1, math.min(shown, perRow))
        local rows = math.max(1, math.ceil(shown / perRow))
        bar.holder:SetSize(columns * (cfg.size + cfg.spacing) - cfg.spacing, rows * (cfg.size + cfg.spacing) - cfg.spacing)
    end
    bar.wanted = on and (shown > 0 or NS:Previewing()) or false
    bar.holder:SetShown(bar.wanted and bar.visible ~= false)
    if becameReady and cfg.sound and not loading and GetTime() - (bar.lastSound or -SOUND_THROTTLE) >= SOUND_THROTTLE then
        bar.lastSound = GetTime()
        NS.PlayPreset(cfg.soundPreset, cfg.soundFile)
    end
    if on and not bar.registered then
        bar.registered = true
        NS.Movers:Register(MoverKey(index), bar.holder, string.format(L.CDBARS_MOVER, index), "CENTER", 0, cfg.y)
        NS.Movers:Load(MoverKey(index))
        NS.Visibility:Register(MoverKey(index), bar.holder, function() return self.db.bars["bar" .. index].visibility end, {
            apply = function(frame, visible)
                bar.visible = visible
                frame:SetShown(bar.wanted and visible)
            end,
            forceVisible = function() return NS:Previewing() end,
        })
    elseif not on and bar.registered then
        bar.registered, bar.visible = nil, nil
        NS.Movers:Unregister(MoverKey(index))
        NS.Visibility:Unregister(MoverKey(index))
    end
end

function CooldownBars:Update()
    for index = 1, BAR_COUNT do self:UpdateBar(index) end
end

--- Oublie l'état « prêt » : aucun son pour ce qui revient pendant un chargement ou une remise à zéro.
local function ForgetReady()
    for _, bar in pairs(frames) do wipe(bar.ready) end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
    if event == "SPELLS_CHANGED" then wipe(spellLists) end
    if event == "LOADING_SCREEN_ENABLED" then loading = true ForgetReady() return end
    if event == "LOADING_SCREEN_DISABLED" then loading = false end
    if event == "PLAYER_ENTERING_WORLD" then ForgetReady() end
    CooldownBars:Update()
end)

function CooldownBars:OnEnable()
    active = true
    wipe(spellLists)   -- SPELLS_CHANGED non écouté pendant la désactivation
    ForgetReady()
    for _, event in ipairs({ "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_CHARGES", "SPELLS_CHANGED", "PLAYER_ENTERING_WORLD",
                             "PLAYER_EQUIPMENT_CHANGED", "LOADING_SCREEN_ENABLED", "LOADING_SCREEN_DISABLED" }) do
        NS.RegisterEventSafe(events, event)
    end
    self:Update()
end

function CooldownBars:OnDisable()
    active = false
    events:UnregisterAllEvents()
    self:Update()
end

local function RefreshVisibility()
    for index = 1, BAR_COUNT do NS.Visibility:Refresh(MoverKey(index)) end
end

function CooldownBars:OnRefresh()
    wipe(spellLists)
    self:Update()
    RefreshVisibility()
end

NS:On("PREVIEW", function()
    CooldownBars:Update()
    RefreshVisibility()
end)

--------------------------------------------------------------------------------
-- Options : sélecteur dans le catalogue du gestionnaire de recharges (API documentée seulement)
--------------------------------------------------------------------------------

local ICON_SIZE, ICON_GAP, PER_ROW, ROWS = 28, 4, 16, 4
local PICKER_HEIGHT = 32 + ROWS * (ICON_SIZE + ICON_GAP)

--- Catalogue : sorts choisis en tête dans l'ordre de la barre (même absents du catalogue, saisis à
-- la main en 1.0.2, pour pouvoir les retirer), puis sorts de toutes les catégories (appris ou non)
-- et les deux bijoux portés.
local function Catalog(tokens)
    local entries, order = {}, {}
    local function Add(entry)
        if not entries[entry.spellID] then
            entries[entry.spellID] = entry
            order[#order + 1] = entry.spellID
        end
    end
    for _, entry in ipairs(NS.GetCooldownViewerSpells(CATALOG_CATEGORIES, true)) do
        -- autres emplacements d'équipement : non affichables par nos barres
        if not entry.slot or entry.slot == 13 or entry.slot == 14 then Add(entry) end
    end
    for _, slot in ipairs(TRINKET_SLOTS) do
        local name, icon = NS.GetInventorySlotItem(slot)
        if name then Add({ spellID = "slot" .. slot, name = name, icon = icon, slot = slot }) end
    end
    local list, chosen = {}, {}
    for _, token in ipairs(tokens) do
        if not chosen[token] then
            chosen[token] = true
            local entry = entries[token]
            if not entry then
                local slot = type(token) == "string" and tonumber(token:match("%d+"))
                local name, icon
                if slot then name, icon = NS.GetInventorySlotItem(slot) else name, icon = NS.GetSpellName(token), NS.GetSpellTexture(token) end
                entry = { spellID = token, name = name or tostring(token), icon = icon or 134400, slot = slot }
            end
            list[#list + 1] = entry
        end
    end
    for _, token in ipairs(order) do
        if not chosen[token] then list[#list + 1] = entries[token] end
    end
    return list
end

--- Jeton avancé d'une place dans la liste (premier : inchangé).
function CooldownBars.MoveEarlier(text, token)
    local tokens = CooldownBars.Tokens(text)
    for i = 2, #tokens do
        if tokens[i] == token then tokens[i - 1], tokens[i] = tokens[i], tokens[i - 1] break end
    end
    for i, existing in ipairs(tokens) do tokens[i] = tostring(existing) end
    return table.concat(tokens, " ")
end

--- Jeton ajouté s'il manque, retiré sinon ; liste réécrite séparée par des espaces.
function CooldownBars.Toggle(text, token)
    local tokens, found = {}, false
    for _, existing in ipairs(CooldownBars.Tokens(text)) do
        if existing == token then found = true else tokens[#tokens + 1] = tostring(existing) end
    end
    if not found then tokens[#tokens + 1] = tostring(token) end
    return table.concat(tokens, " ")
end

local function SpellPicker(o, index)
    local layout = o.layout
    local picker = CreateFrame("Frame", nil, layout.parent)
    picker:SetSize(PER_ROW * (ICON_SIZE + ICON_GAP), PICKER_HEIGHT)
    layout:Place(picker, PICKER_HEIGHT, 36)
    local buttons, filter = {}, ""
    local function Config() return NS.db.modules.cooldownbars.bars["bar" .. index] end

    local search = CreateFrame("EditBox", nil, picker, "InputBoxTemplate")
    search:SetSize(240, 20)
    search:SetPoint("TOPLEFT", picker, "TOPLEFT", 6, -4)
    search:SetAutoFocus(false)
    local hint = picker:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    hint:SetPoint("LEFT", search, "LEFT", 2, 0)
    hint:SetText(L.OPT_SEARCH_PLACEHOLDER)
    local count = picker:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    count:SetPoint("LEFT", search, "RIGHT", 12, 0)

    local Paint
    local function Button(i)
        if buttons[i] then return buttons[i] end
        local button = CreateFrame("Button", nil, picker)
        button:SetSize(ICON_SIZE, ICON_SIZE)
        local row, column = math.floor((i - 1) / PER_ROW), (i - 1) % PER_ROW
        button:SetPoint("TOPLEFT", picker, "TOPLEFT", column * (ICON_SIZE + ICON_GAP), -32 - row * (ICON_SIZE + ICON_GAP))
        button.texture = button:CreateTexture(nil, "ARTWORK")
        button.texture:SetAllPoints()
        button.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        button.border = Media:CreateBorder(button)
        button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        button:SetScript("OnClick", function(self, mouseButton)
            local cfg = Config()
            if mouseButton == "RightButton" then
                cfg.spells = CooldownBars.MoveEarlier(cfg.spells, self.token)
            else
                cfg.spells = CooldownBars.Toggle(cfg.spells, self.token)
            end
            NS.Modules:Refresh("cooldownbars")
            Paint()
        end)
        button:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if self.slot and GameTooltip.SetInventoryItem then GameTooltip:SetInventoryItem("player", self.slot)
            elseif not self.slot and GameTooltip.SetSpellByID then GameTooltip:SetSpellByID(self.token)
            else GameTooltip:SetText(self.name or "") end
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function() GameTooltip:Hide() end)
        buttons[i] = button
        return button
    end

    function Paint()
        local chosen, tokens = {}, CooldownBars.Tokens(Config().spells)
        for _, token in ipairs(tokens) do chosen[token] = true end
        local accent, border = { Media:Accent() }, NS.db.theme.border
        local shown = 0
        for _, entry in ipairs(Catalog(tokens)) do
            local name = entry.name or ""
            if shown < PER_ROW * ROWS and (filter == "" or name:lower():find(filter, 1, true)) then
                shown = shown + 1
                local button = Button(shown)
                button.token, button.name, button.slot = entry.spellID, name, entry.slot
                button.texture:SetTexture(entry.icon)
                local on = chosen[entry.spellID]
                button:SetAlpha(on and 1 or 0.6)
                for _, edge in pairs(button.border) do
                    if on then NS.SetSolidColor(edge, accent[1], accent[2], accent[3], 1)
                    else NS.SetSolidColor(edge, border.r, border.g, border.b, border.a or 1) end
                end
                button:Show()
            end
        end
        for i = shown + 1, #buttons do buttons[i]:Hide() end
        local selected = 0
        for _ in pairs(chosen) do selected = selected + 1 end
        count:SetText(string.format(L.OPT_CDBARS_SELECTED, selected))
    end

    search:SetScript("OnTextChanged", function(self)
        filter = (self:GetText() or ""):lower()
        hint:SetShown(filter == "")
        Paint()
    end)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    -- relu à chaque affichage et quand le catalogue Blizzard arrive : aucun cache permanent
    picker:SetScript("OnShow", Paint)
    NS.RegisterEventSafe(picker, "COOLDOWN_VIEWER_DATA_LOADED")
    picker:SetScript("OnEvent", function() if picker:IsVisible() then Paint() end end)
    layout.refreshers[#layout.refreshers + 1] = Paint
    Paint()
end

function CooldownBars:BuildOptions(o)
    for index = 1, BAR_COUNT do
        local prefix = "bars.bar" .. index .. "."
        o:Title(string.format(L.CDBARS_MOVER, index))
        o:Check(prefix .. "enabled", L.OPT_CDBARS_ENABLED)
        o:Note(L.OPT_CDBARS_SPELLS, 36)
        SpellPicker(o, index)
        o:Slider(prefix .. "size", L.OPT_MOVEMENT_ICON_SIZE, 16, 64, 1, 36)
        o:Advanced()
        o:Slider(prefix .. "spacing", L.OPT_AURABARS_SPACING, 0, 12, 1, 36)
        o:Slider(prefix .. "perRow", L.OPT_CDBARS_PER_ROW, 1, 24, 1, 36)
        o:EndAdvanced()
        o:Check(prefix .. "hideReady", L.OPT_CDBARS_HIDE_READY, 36)
        o:Advanced()
        o:Check(prefix .. "desaturate", L.OPT_CDBARS_DESATURATE, 36)
        o:EndAdvanced()
        o:Check(prefix .. "sound", L.OPT_CDBARS_SOUND, 36)
        o:Advanced()
        o:Sound(prefix .. "soundPreset", prefix .. "soundFile", 52, function()
            local cfg = NS.db.modules.cooldownbars.bars["bar" .. index]
            NS.PlayPreset(cfg.soundPreset, cfg.soundFile)
        end)
        o:EndAdvanced()
        o:Visibility(prefix .. "visibility", string.format(L.OPT_CDBARS_VISIBILITY, index), { noMouseover = true })
    end
end

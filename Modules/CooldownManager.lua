-- Modules/CooldownManager.lua
-- Gestion sort par sort du gestionnaire de recharges Blizzard (quatre viewers) :
--   * masquer un sort de sa barre : les suivants remontent dans l'ordre Blizzard ;
--   * lueur (Core/Glow) quand le sort est prêt, ou en permanence (buff actif sur les barres de buff) ;
--   * habillage barre par barre : bordure du thème, taille des compteurs, barres de buff (texture,
--     couleur, nom et durée affichables), sans toucher à la mise en page Edit Mode.
-- Les items restent ceux de Blizzard : après chaque mise en page Blizzard (hook), chaque item
-- garde en mémoire sa place d'origine ; les items visibles prennent les premières places, les
-- masqués les dernières, à opacité 0. Jamais de Show/Hide sur un item : le viewer se remettrait
-- en page en cascade. Réglages par sort (spellID d'origine), communs à toutes les spés.
local _, NS = ...
local L = NS.L

local VIEWERS = {
    { name = "EssentialCooldownViewer", category = 0, label = "MOVER_CDM_ESSENTIAL", key = "essential" },
    { name = "UtilityCooldownViewer",   category = 1, label = "MOVER_CDM_UTILITY",   key = "utility" },
    { name = "BuffIconCooldownViewer",  category = 2, label = "MOVER_CDM_BUFFICON",  key = "bufficon" },
    { name = "BuffBarCooldownViewer",   category = 3, label = "MOVER_CDM_BUFFBAR",   key = "buffbar", bars = true },
}

local function ViewerSkin(border)
    return { border = border, fontSize = 0 }   -- fontSize 0 : police Blizzard des compteurs
end

local CooldownManager = NS.Modules:Register("cooldownmanager", {
    titleKey = "CDM_TITLE",
    descKey = "CDM_DESC",
    defaults = {
        enabled = false,
        glowColor = { r = 1, g = 0.82, b = 0.2 },
        glowStyle = "classic",   -- Core/Glow : "pixel" | "autocast" | "button" | "classic"
        spells = {},   -- [spellID] = { hidden = true, glow = "ready" | "always" }
        skin = {       -- habillage par viewer
            essential = ViewerSkin(true), utility = ViewerSkin(true), bufficon = ViewerSkin(true),
            buffbar = { border = true, fontSize = 0, barTexture = true, barColor = { r = 0.25, g = 0.66, b = 0.96 },
                        showName = true, showDuration = true },
        },
    },
})

local active = false
local hooked = {}

--- Réglage du sort, ou nil (un profil importé mal formé peut y mettre autre chose qu'une table).
local function Setting(spellID)
    -- NS.db et non module.db : les options sont construites avant l'activation des modules.
    local s = spellID and NS.db.modules.cooldownmanager.spells[spellID]
    return type(s) == "table" and s or nil
end

--- Items actifs du viewer, dans l'ordre Blizzard.
local function Items(viewer)
    local items = {}
    if viewer.itemFramePool then
        for item in viewer.itemFramePool:EnumerateActive() do items[#items + 1] = item end
    end
    table.sort(items, function(a, b) return (a.layoutIndex or 0) < (b.layoutIndex or 0) end)
    return items
end

local function SetGlow(item, on)
    local db = CooldownManager.db
    NS.Glow.Set(item, on, db.glowStyle, db.glowColor)
end

local function WantsGlow(item)
    local s = item.foreverSetting
    if not active or not s or s.hidden then return false end
    if s.glow == "always" then return true end
    return s.glow == "ready" and item.foreverSpell ~= nil and NS.IsSpellReady(item.foreverSpell)
end

function CooldownManager:UpdateGlows()
    for _, def in ipairs(VIEWERS) do
        local viewer = _G[def.name]
        if viewer then
            for _, item in ipairs(Items(viewer)) do SetGlow(item, WantsGlow(item)) end
        end
    end
end

--- Item affiché par Blizzard ? Visibilité secrète (issue d'une aura ou d'une recharge) : oui.
local function Visible(item)
    local shown = item:IsShown()
    if NS.IsSecret(shown) then return true end
    return shown
end

--- Visibles aux premières places d'origine, masqués parqués hors écran : Blizzard peut relever
-- l'alpha d'un item (recharge, aura), l'item parqué reste invisible.
function CooldownManager:ApplyViewer(viewer)
    local shown, slots = {}, {}
    for _, item in ipairs(Items(viewer)) do
        local spellID, live = NS.GetCooldownViewerSpell(item.cooldownID)
        item.foreverSpell = live
        item.foreverSetting = active and Setting(spellID) or nil
        if item.foreverSetting and item.foreverSetting.hidden then
            -- sa place revient aux suivants
            if Visible(item) and item.foreverHome then slots[#slots + 1] = item.foreverHome end
            item:ClearAllPoints()
            item:SetPoint("TOPRIGHT", UIParent, "TOPLEFT", -1000, 1000)
            item:SetAlpha(0)
            item.foreverHidden = true
        elseif item.foreverHome then
            if Visible(item) then
                shown[#shown + 1] = item
                slots[#slots + 1] = item.foreverHome
            elseif item.foreverHidden then   -- caché par Blizzard pendant qu'il était parqué
                local home = item.foreverHome
                item:ClearAllPoints()
                item:SetPoint(home[1], home[2], home[3], home[4], home[5])
            end
            if item.foreverHidden then
                item.foreverHidden = nil
                item:SetAlpha(1)
            end
        end
    end
    table.sort(slots, function(a, b) return a.index < b.index end)
    for i, item in ipairs(shown) do
        local home = slots[i]
        item:ClearAllPoints()
        item:SetPoint(home[1], home[2], home[3], home[4], home[5])
    end
end

--- Après une mise en page Blizzard (et seulement là) : chaque item note sa place d'origine.
local function OnViewerLayout(viewer)
    if not active then return end
    for index, item in ipairs(Items(viewer)) do
        local point, relativeTo, relativePoint, x, y = item:GetPoint(1)
        item.foreverHome = point and { point, relativeTo, relativePoint, x, y, index = index } or nil
    end
    CooldownManager:ApplyViewer(viewer)
    CooldownManager:UpdateGlows()
end

-- ponytail: un item de buff montré sans mise en page Blizzard garde la place de la dernière ;
-- hooker OnAcquireItemFrame si un trou apparaît en jeu.
-- Hook posé seulement si un sort a un réglage : un hook sur la mise en page d'un viewer (enfant
-- du conteneur du bas géré par Edit Mode) contamine cette mise en page (LayoutFrame « attempt
-- to call a nil value »). Sans réglage, rien à faire : aucun hook.
local function HookViewers()
    if not next(CooldownManager.db.spells) then return end
    for _, def in ipairs(VIEWERS) do
        local viewer = _G[def.name]
        -- Un seul hook : RefreshLayout peut appeler Layout, deux captures reliraient nos places.
        local method = viewer and (type(viewer.Layout) == "function" and "Layout" or "RefreshLayout")
        if method and type(viewer[method]) == "function" and not hooked[def.name] then
            hooked[def.name] = true
            hooksecurefunc(viewer, method, OnViewerLayout)
            OnViewerLayout(viewer)   -- premier passage : les places sont encore celles de Blizzard
        end
    end
end

--------------------------------------------------------------------------------
-- Habillage barre par barre
--------------------------------------------------------------------------------
-- Aucun hook (voir HookViewers) : repassé l'image qui suit les événements qui remettent les
-- viewers à jour. Propriétés visuelles seules : bordure, polices, texture et couleur de barre,
-- alpha du nom et de la durée ; jamais de point ni de taille.

local originalFonts = setmetatable({}, { __mode = "k" })   -- [FontString] = { police d'origine }

local function Counters(item)
    local list = {}
    local charges = item.ChargeCount and (item.ChargeCount.Current or item.ChargeCount)
    local stacks = item.Applications and (item.Applications.Applications or item.Applications)
    for _, text in ipairs({ charges, stacks }) do
        if type(text) == "table" and text.SetFont and text.GetFont then list[#list + 1] = text end
    end
    return list
end

local function StyleFont(text, size)
    if size > 0 then
        if not originalFonts[text] then originalFonts[text] = { text:GetFont() } end
        text:SetFont(NS.Media:Font(), size, "OUTLINE")
    elseif originalFonts[text] and originalFonts[text][1] then
        text:SetFont(unpack(originalFonts[text]))
        originalFonts[text] = nil
    end
end

local function BarParts(item)
    local bar = (item.GetBarFrame and item:GetBarFrame()) or item.Bar
    local icon = (item.GetIconFrame and item:GetIconFrame()) or item.Icon
    local name = (item.GetNameFontString and item:GetNameFontString()) or (bar and bar.Name)
    local duration = (item.GetDurationFontString and item:GetDurationFontString()) or (bar and bar.Duration)
    return bar, icon, name, duration
end

--- Habille (ou rend, inactif) un item de viewer selon le réglage de sa barre.
function CooldownManager.StyleItem(item, def)
    local cfg = CooldownManager.db.skin[def.key] or {}
    local on = active
    local bar, icon, name, duration
    if def.bars then bar, icon, name, duration = BarParts(item) end
    local holder = (def.bars and type(icon) == "table" and icon.CreateTexture and icon) or item
    if on and cfg.border and not holder.aeonBorder then holder.aeonBorder = NS.Media:CreateBorder(holder) end
    for _, edge in pairs(holder.aeonBorder or {}) do edge:SetShown(on and cfg.border and true or false) end
    for _, text in ipairs(Counters(item)) do StyleFont(text, on and (cfg.fontSize or 0) or 0) end
    if not (bar and bar.SetStatusBarTexture) then return end
    local styled = on and cfg.barTexture
    if styled then
        if not bar.aeonOriginal then
            local texture = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
            bar.aeonOriginal = { texture = texture and texture.GetTexture and texture:GetTexture(),
                                 color = { bar:GetStatusBarColor() } }
        end
        bar:SetStatusBarTexture(NS.Media:StatusBarTexture())
        local color = cfg.barColor
        bar:SetStatusBarColor(color.r, color.g, color.b)
        if bar.BarBG then bar.BarBG:SetAlpha(0) end
    elseif bar.aeonOriginal then
        if bar.aeonOriginal.texture then bar:SetStatusBarTexture(bar.aeonOriginal.texture) end
        local color = bar.aeonOriginal.color
        if color[1] then bar:SetStatusBarColor(color[1], color[2], color[3]) end
        if bar.BarBG then bar.BarBG:SetAlpha(1) end
        bar.aeonOriginal = nil
    end
    if name and name.SetAlpha then name:SetAlpha((on and not cfg.showName) and 0 or 1) end
    if duration and duration.SetAlpha then duration:SetAlpha((on and not cfg.showDuration) and 0 or 1) end
    if name and name.SetFont then StyleFont(name, on and (cfg.fontSize or 0) or 0) end
    if duration and duration.SetFont then StyleFont(duration, on and (cfg.fontSize or 0) or 0) end
end

function CooldownManager:ApplySkin()
    for _, def in ipairs(VIEWERS) do
        local viewer = _G[def.name]
        if viewer then
            for _, item in ipairs(Items(viewer)) do CooldownManager.StyleItem(item, def) end
        end
    end
end

local skinQueued = false
local function QueueSkin()
    if skinQueued then return end
    skinQueued = true
    C_Timer.After(0, function()
        skinQueued = false
        CooldownManager:ApplySkin()
    end)
end

function CooldownManager:ApplyAll()
    for _, def in ipairs(VIEWERS) do
        local viewer = _G[def.name]
        if viewer then self:ApplyViewer(viewer) end
    end
    self:UpdateGlows()
    self:ApplySkin()
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
    if not active then return end
    QueueSkin()   -- items créés ou recyclés par Blizzard : habillés l'image suivante
    if event == "SPELL_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_CHARGES" then
        CooldownManager:UpdateGlows()
    elseif event ~= "UNIT_AURA" then
        HookViewers()   -- Blizzard_CooldownViewer se charge à la demande
    end
end)

function CooldownManager:OnEnable()
    active = true
    for _, event in ipairs({ "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_CHARGES" }) do
        NS.RegisterEventSafe(events, event)
    end
    NS.RegisterEventSafe(events, "UNIT_AURA", "player")
    HookViewers()
    self:ApplyAll()   -- viewers déjà hookés (réactivation) : places notées gardées
end

function CooldownManager:OnDisable()
    active = false
    events:UnregisterAllEvents()
    self:ApplyAll()   -- inactif : tout revient à sa place d'origine, opaque, sans lueur
end

function CooldownManager:OnRefresh()
    if active then HookViewers() end
    self:ApplyAll()
end

--------------------------------------------------------------------------------
-- Options : choix du sort par icône, puis ses réglages
--------------------------------------------------------------------------------

local ICON_SIZE, ICON_GAP, PER_ROW, ROWS = 32, 4, 15, 4
local PICKER_HEIGHT = 32 + ROWS * (ICON_SIZE + ICON_GAP) + 70

local function Entry(spellID)
    local spells = CooldownManager.db.spells
    spells[spellID] = spells[spellID] or {}
    return spells[spellID]
end

--- Réglage changé : entrée vide retirée, barres remises en page.
local function Changed(spellID)
    local spells = CooldownManager.db.spells
    local entry = spells[spellID]
    if entry and not entry.hidden and (entry.glow or "none") == "none" then spells[spellID] = nil end
    NS.Modules:Refresh("cooldownmanager")
end

function CooldownManager:BuildOptions(o)
    local layout = o.layout
    o:Note(L.NOTE_CDM)
    o:Dropdown("glowStyle", L.OPT_GLOW_STYLE, NS.Glow.Choices())
    o:Color("glowColor", L.OPT_CDM_GLOW_COLOR)
    o:Title(L.OPT_CDM_SKIN_TITLE)
    for _, def in ipairs(VIEWERS) do
        local prefix = "skin." .. def.key .. "."
        o.layout:Header(L[def.label], 20)
        o:Check(prefix .. "border", L.OPT_CDM_SKIN_BORDER, 36)
        o:Advanced()
        o:Slider(prefix .. "fontSize", L.OPT_CDM_SKIN_FONT_SIZE, 0, 24, 1, 36)
        o:EndAdvanced()
        if def.bars then
            o:Check(prefix .. "barTexture", L.OPT_CDM_SKIN_BAR_TEXTURE, 36)
            o:Advanced()
            o:Color(prefix .. "barColor", L.OPT_CDM_SKIN_BAR_COLOR, 52)
            o:EndAdvanced()
            o:Check(prefix .. "showName", L.OPT_CDM_SKIN_SHOW_NAME, 36)
            o:Check(prefix .. "showDuration", L.OPT_CDM_SKIN_SHOW_DURATION, 36)
        end
    end
    o:Title(L.OPT_CDM_SPELLS_TITLE)

    local picker = CreateFrame("Frame", nil, layout.parent)
    picker:SetSize(PER_ROW * (ICON_SIZE + ICON_GAP), PICKER_HEIGHT)
    layout:Place(picker, PICKER_HEIGHT, 20)
    local category, selected, buttons, spells = 0, nil, {}, {}

    local categories = {}
    for _, def in ipairs(VIEWERS) do categories[#categories + 1] = { name = L[def.label], value = def.category } end
    local Paint
    local categoryButton = NS.Widgets.Dropdown(picker, 300, L.OPT_CDM_BAR, categories,
        function() return category end, function(value) category, selected = value, nil Paint() end)
    categoryButton:SetPoint("TOPLEFT", picker, "TOPLEFT", 0, 0)

    local empty = picker:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    empty:SetPoint("TOPLEFT", picker, "TOPLEFT", 0, -36)
    empty:SetText(L.OPT_CDM_EMPTY)

    local footer = -32 - ROWS * (ICON_SIZE + ICON_GAP) - 6
    local title = picker:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetPoint("TOPLEFT", picker, "TOPLEFT", 0, footer)
    local show = CreateFrame("CheckButton", nil, picker, "UICheckButtonTemplate")
    show:SetPoint("TOPLEFT", picker, "TOPLEFT", -4, footer - 18)
    local showText = show.Text or show.text or show:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    showText:SetPoint("LEFT", show, "RIGHT", 2, 0)
    showText:SetText(L.OPT_CDM_SHOW)
    show:SetScript("OnClick", function(self)
        if not selected then return end
        Entry(selected).hidden = not self:GetChecked() or nil
        Changed(selected)
        Paint()
    end)
    local glowChoices = {
        { name = L.OPT_CDM_GLOW_NONE, value = "none" },
        { name = L.OPT_CDM_GLOW_READY, value = "ready" },
        { name = L.OPT_CDM_GLOW_ALWAYS, value = "always" },
    }
    local glow = NS.Widgets.Dropdown(picker, 300, L.OPT_CDM_GLOW, glowChoices,
        function() local s = selected and Setting(selected) return s and s.glow or "none" end,
        function(value)
            if not selected then return end
            Entry(selected).glow = value ~= "none" and value or nil
            Changed(selected)
            Paint()
        end)
    glow:SetPoint("TOPLEFT", picker, "TOPLEFT", 200, footer - 20)

    local function Button(i)
        if buttons[i] then return buttons[i] end
        local button = CreateFrame("Button", nil, picker)
        button:SetSize(ICON_SIZE, ICON_SIZE)
        local row, column = math.floor((i - 1) / PER_ROW), (i - 1) % PER_ROW
        button:SetPoint("TOPLEFT", picker, "TOPLEFT", column * (ICON_SIZE + ICON_GAP), -32 - row * (ICON_SIZE + ICON_GAP))
        button.texture = button:CreateTexture(nil, "ARTWORK")
        button.texture:SetAllPoints()
        button.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        button.border = NS.Media:CreateBorder(button)
        button:SetScript("OnClick", function(self) selected = self.spellID Paint() end)
        button:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if GameTooltip.SetSpellByID then GameTooltip:SetSpellByID(self.spellID) else GameTooltip:SetText(self.name) end
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function() GameTooltip:Hide() end)
        buttons[i] = button
        return button
    end

    function Paint()
        spells = NS.GetCooldownViewerSpells(category)
        local accent = { NS.Media:Accent() }
        local selectedSpell
        for i = 1, math.min(#spells, PER_ROW * ROWS) do
            local spell, button = spells[i], Button(i)
            button.spellID, button.name = spell.spellID, spell.name
            button.texture:SetTexture(spell.icon)
            local s = Setting(spell.spellID)
            local hiddenSpell = s and s.hidden
            if button.texture.SetDesaturated then button.texture:SetDesaturated(hiddenSpell and true or false) end
            button:SetAlpha(hiddenSpell and 0.4 or 1)
            local isSelected = spell.spellID == selected
            if isSelected then selectedSpell = spell end
            local c = NS.db.theme.border
            for _, edge in pairs(button.border) do
                if isSelected then NS.SetSolidColor(edge, accent[1], accent[2], accent[3], 1)
                else NS.SetSolidColor(edge, c.r, c.g, c.b, c.a or 1) end
            end
            button:Show()
        end
        for i = #spells + 1, #buttons do buttons[i]:Hide() end
        empty:SetShown(#spells == 0)
        if not selectedSpell then selected = nil end
        title:SetText(selectedSpell and ((selectedSpell.icon and ("|T" .. selectedSpell.icon .. ":16|t ") or "") .. selectedSpell.name) or L.OPT_CDM_PICK)
        local s = selected and Setting(selected)
        show:SetChecked(not (s and s.hidden))
        NS.Widgets.SetEnabled(show, selected ~= nil)
        NS.Widgets.SetEnabled(glow, selected ~= nil)
        glow.Paint()
        categoryButton.Paint()
    end

    picker:SetScript("OnShow", Paint)   -- la liste suit la spé courante
    layout.refreshers[#layout.refreshers + 1] = Paint
    Paint()
end

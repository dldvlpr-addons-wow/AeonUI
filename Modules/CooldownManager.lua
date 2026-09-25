-- Modules/CooldownManager.lua
-- Gestion sort par sort du gestionnaire de recharges Blizzard (quatre viewers) :
--   * masquer un sort de sa barre : les suivants remontent dans l'ordre Blizzard ;
--   * lueur pulsée quand le sort est prêt, ou en permanence (buff actif sur les barres de buff).
-- Les items restent ceux de Blizzard : après chaque mise en page Blizzard (hook), chaque item
-- garde en mémoire sa place d'origine ; les items visibles prennent les premières places, les
-- masqués les dernières, à opacité 0. Jamais de Show/Hide sur un item : le viewer se remettrait
-- en page en cascade. Réglages par sort (spellID d'origine), communs à toutes les spés.
local _, NS = ...
local L = NS.L

local VIEWERS = {
    { name = "EssentialCooldownViewer", category = 0, label = "MOVER_CDM_ESSENTIAL" },
    { name = "UtilityCooldownViewer",   category = 1, label = "MOVER_CDM_UTILITY" },
    { name = "BuffIconCooldownViewer",  category = 2, label = "MOVER_CDM_BUFFICON" },
    { name = "BuffBarCooldownViewer",   category = 3, label = "MOVER_CDM_BUFFBAR" },
}

local CooldownManager = NS.Modules:Register("cooldownmanager", {
    titleKey = "CDM_TITLE",
    descKey = "CDM_DESC",
    yieldsTo = { "ElvUI" },
    defaults = {
        enabled = false,
        glowColor = { r = 1, g = 0.82, b = 0.2 },
        spells = {},   -- [spellID] = { hidden = true, glow = "ready" | "always" }
    },
})

local active = false
local hooked = {}

--- Réglage du sort, ou nil (un profil importé mal formé peut y mettre autre chose qu'une table).
local function Setting(spellID)
    local s = spellID and CooldownManager.db.spells[spellID]
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

local function Glow(item)
    if item.foreverGlow then return item.foreverGlow end
    local glow = item:CreateTexture(nil, "BACKGROUND", nil, -8)
    glow:SetPoint("TOPLEFT", item, "TOPLEFT", -4, 4)
    glow:SetPoint("BOTTOMRIGHT", item, "BOTTOMRIGHT", 4, -4)
    glow:Hide()
    if glow.CreateAnimationGroup then
        glow.pulse = glow:CreateAnimationGroup()
        glow.pulse:SetLooping("BOUNCE")
        local fade = glow.pulse:CreateAnimation("Alpha")
        fade:SetFromAlpha(0.9)
        fade:SetToAlpha(0.25)
        fade:SetDuration(0.6)
    end
    item.foreverGlow = glow
    return glow
end

local function SetGlow(item, on)
    if not on and not item.foreverGlow then return end
    local glow = Glow(item)
    if on then
        local c = CooldownManager.db.glowColor
        NS.SetSolidColor(glow, c.r, c.g, c.b, 1)
        if not glow:IsShown() then
            glow:Show()
            if glow.pulse then glow.pulse:Play() end
        end
    elseif glow:IsShown() then
        glow:Hide()
        if glow.pulse then glow.pulse:Stop() end
    end
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
            if item:IsShown() and item.foreverHome then slots[#slots + 1] = item.foreverHome end
            item:ClearAllPoints()
            item:SetPoint("TOPRIGHT", UIParent, "TOPLEFT", -1000, 1000)
            item:SetAlpha(0)
            item.foreverHidden = true
        elseif item.foreverHome then
            if item:IsShown() then
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
local function HookViewers()
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

function CooldownManager:ApplyAll()
    for _, def in ipairs(VIEWERS) do
        local viewer = _G[def.name]
        if viewer then self:ApplyViewer(viewer) end
    end
    self:UpdateGlows()
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
    if not active then return end
    if event == "SPELL_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_CHARGES" then
        CooldownManager:UpdateGlows()
    else
        HookViewers()   -- Blizzard_CooldownViewer se charge à la demande
    end
end)

function CooldownManager:OnEnable()
    active = true
    for _, event in ipairs({ "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_CHARGES" }) do
        NS.RegisterEventSafe(events, event)
    end
    HookViewers()
    self:ApplyAll()   -- viewers déjà hookés (réactivation) : places notées gardées
end

function CooldownManager:OnDisable()
    active = false
    events:UnregisterAllEvents()
    self:ApplyAll()   -- inactif : tout revient à sa place d'origine, opaque, sans lueur
end

function CooldownManager:OnRefresh() self:ApplyAll() end

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
    o:Color("glowColor", L.OPT_CDM_GLOW_COLOR)

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

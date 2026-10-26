-- Modules/CooldownManager.lua
-- Gestion sort par sort du gestionnaire de recharges Blizzard (quatre viewers) :
--   * masquer un sort de sa barre : les suivants remontent dans l'ordre Blizzard ;
--   * effet d'état : estompé ou caché selon recharge, prêt, utilisable (états jamais secrets) ;
--   * lueurs (Core/Glow) : proc, buff lié actif, prêt, charges au maximum, ou en permanence ;
--   * fenêtre après lancement : durée choisie, décompte et lueur ;
--   * raccourci clavier lu sur nos barres d'action, visibilité commune (Core/Visibility) par viewer ;
--   * habillage barre par barre : bordure du thème, taille des compteurs, barres de buff (texture,
--     couleur, nom et durée affichables), sans toucher à la mise en page Edit Mode.
-- Les items restent ceux de Blizzard : après chaque mise en page Blizzard (hook), chaque item
-- garde en mémoire sa place d'origine ; les items visibles prennent les premières places, les
-- masqués les dernières, à opacité 0. Jamais de Show/Hide sur un item : le viewer se remettrait
-- en page en cascade. Réglages par sort (spellID d'origine, « slot13 » pour un bijou), communs à
-- toutes les spés.
local _, NS = ...
local L = NS.L

local VIEWERS = {
    { name = "EssentialCooldownViewer", category = 0, label = "MOVER_CDM_ESSENTIAL", key = "essential" },
    { name = "UtilityCooldownViewer",   category = 1, label = "MOVER_CDM_UTILITY",   key = "utility" },
    { name = "BuffIconCooldownViewer",  category = 2, label = "MOVER_CDM_BUFFICON",  key = "bufficon" },
    { name = "BuffBarCooldownViewer",   category = 3, label = "MOVER_CDM_BUFFBAR",   key = "buffbar", bars = true },
}
local EXTRA_CATEGORIES = { 5, 6, 7, 8 }   -- communs et équipement, à placer dans un viewer
local DIM_ALPHA = 0.5

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
        procGlowStyle = "button",   -- "none" : alerte Blizzard seule
        procGlowColor = { r = 1, g = 0.82, b = 0.2 },
        buffGlowStyle = "pixel",
        buffGlowColor = { r = 0.3, g = 0.9, b = 0.4 },
        keybind = { enabled = true, font = "inherit", fontSize = 12, anchor = "TOPRIGHT" },
        visibility = { essential = NS.Visibility.Spec(), utility = NS.Visibility.Spec(),
                       bufficon = NS.Visibility.Spec(), buffbar = NS.Visibility.Spec() },
        -- [clé] = { hidden = true, glow = "ready" | "maxcharges" | "always",
        --           state = "dim" | "hideCooldown" | "hideReady" | "hideUnusable",
        --           window = secondes, buffGlow = sort qui brille tant que ce buff est actif }
        spells = {},
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

--- Hors recharge ? Bijou : recharge de l'emplacement. `anyCharge` : prêt dès une charge. nil : illisible.
local function Ready(item, anyCharge)
    if item.foreverSlot then return NS.IsInventorySlotReady(item.foreverSlot) end
    if item.foreverSpell then return NS.IsSpellReady(item.foreverSpell, anyCharge) end
    return nil
end

--- Effet d'état du réglage : "hide", "dim" ou nil (aucun, ou état illisible).
local function StateOf(item)
    local mode = item.foreverSetting and item.foreverSetting.state
    if not mode then return nil end
    if mode == "hideUnusable" then
        return item.foreverSpell and NS.IsSpellUsable(item.foreverSpell) == false and "hide" or nil
    end
    local ready = Ready(item)
    if ready == nil then return nil end
    if mode == "hideReady" then return ready and "hide" or nil end
    if ready then return nil end
    return mode == "dim" and "dim" or "hide"
end

--------------------------------------------------------------------------------
-- Fenêtre après lancement
--------------------------------------------------------------------------------

local function CloseWindow(item)
    local window = item.muscaWindow
    if not (window and window:IsShown()) then return end
    NS.Glow.Set(window, false)
    window:Hide()
end

local function OpenWindow(item, seconds)
    local window = item.muscaWindow
    if not window then
        window = CreateFrame("Frame", nil, item)
        window:SetAllPoints(item)
        window.cooldown = CreateFrame("Cooldown", nil, window, "CooldownFrameTemplate")
        window.cooldown:SetAllPoints(window)
        window.cooldown:SetReverse(true)
        window.cooldown:SetScript("OnCooldownDone", function() CloseWindow(item) end)
        item.muscaWindow = window
    end
    local db = CooldownManager.db
    window.key = item.foreverKey
    window:Show()
    window.cooldown:SetCooldown(GetTime(), seconds)
    NS.Glow.Set(window, not item.foreverSetting.windowNoGlow, db.glowStyle, db.glowColor)
end

--- Sort lancé par le joueur : ouvre la fenêtre des sorts réglés (même identifiant ou même nom,
-- un rang par identifiant). Identifiant secret : rien.
local function OpenWindows(spellID)
    if not spellID or NS.IsSecret(spellID) then return end
    local name = NS.GetSpellName(spellID)
    if NS.IsSecret(name) then name = nil end
    for _, def in ipairs(VIEWERS) do
        local viewer = _G[def.name]
        for _, item in ipairs(viewer and Items(viewer) or {}) do
            local s, live = item.foreverSetting, item.foreverSpell
            local liveName = live and name and NS.GetSpellName(live)
            if s and s.window and live and not item.foreverHidden
                and (live == spellID or item.foreverKey == spellID or (liveName and not NS.IsSecret(liveName) and liveName == name)) then
                OpenWindow(item, s.window)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Lueurs
--------------------------------------------------------------------------------

local litTargets, litSlots, litButtons = {}, {}, {}   -- buffs liés actifs, emplacements, nos boutons allumés

local function SetGlow(item)
    local db, s = CooldownManager.db, item.foreverSetting
    local on, style, color, proc = false, db.glowStyle, db.glowColor, false
    if active and not item.foreverHidden then
        local live = item.foreverSpell
        if db.procGlowStyle ~= "none" and live and NS.IsSpellOverlayed(live) then
            on, style, color, proc = true, db.procGlowStyle, db.procGlowColor, true
        elseif litTargets[item.foreverKey] or (live and litTargets[live]) then
            on, style, color = true, db.buffGlowStyle, db.buffGlowColor
        elseif s and s.glow == "always" then
            on = true
        elseif s and (s.glow == "ready" or s.glow == "maxcharges") then
            on = Ready(item, s.glow == "ready") and true or false
        end
    end
    NS.Glow.Set(item, on, style, color)
    -- notre lueur de proc remplace l'alerte Blizzard de l'item
    local alert = item.SpellActivationAlert
    if alert and alert.SetAlpha then alert:SetAlpha(proc and 0 or 1) end
    if item.muscaWindow and (not active or item.foreverKey ~= item.muscaWindow.key) then CloseWindow(item) end
end

function CooldownManager:UpdateGlows()
    for _, def in ipairs(VIEWERS) do
        local viewer = _G[def.name]
        if viewer then
            for _, item in ipairs(Items(viewer)) do SetGlow(item) end
        end
    end
end

--- Lueur de buff sur un de nos boutons d'action : cadre enfant (la lueur de proc d'ActionBars
-- occupe le bouton lui-même).
local function SetButtonGlow(button, on)
    local holder = button.muscaBuffGlow
    if not holder then
        holder = CreateFrame("Frame", nil, button)
        holder:SetAllPoints(button)
        button.muscaBuffGlow = holder
    end
    local db = CooldownManager.db
    NS.Glow.Set(holder, on, db.buffGlowStyle, db.buffGlowColor)
    litButtons[button] = on or nil
end

--- Buffs liés actifs (champs que Blizzard tient sur l'item, testés en vérité seulement), puis
-- lueur des boutons de nos barres qui portent le sort lié.
function CooldownManager:UpdateBuffGlows()
    wipe(litTargets)
    wipe(litSlots)
    for _, def in ipairs(VIEWERS) do
        local viewer = _G[def.name]
        if viewer and def.category >= 2 then
            for _, item in ipairs(Items(viewer)) do
                local s = active and Setting(NS.GetCooldownViewerSpell(item.cooldownID))
                if s and s.buffGlow and (item.auraInstanceID or item.wasSetFromAura) then litTargets[s.buffGlow] = true end
            end
        end
    end
    for target in pairs(litTargets) do
        for _, slot in ipairs(NS.FindSpellActionSlots(target)) do litSlots[slot] = true end
    end
    if not (next(litSlots) or next(litButtons)) then return end
    local bars = NS.Modules:Get("actionbars")
    for _, bar in pairs(bars and bars.bars or {}) do
        for _, button in ipairs(bar.buttons or {}) do
            local on = (bars.enabled and button.action and litSlots[button.action]) and true or false
            if on or litButtons[button] then SetButtonGlow(button, on) end
        end
    end
end

--------------------------------------------------------------------------------
-- Mise en page des items
--------------------------------------------------------------------------------

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
        local key, live, slot = NS.GetCooldownViewerSpell(item.cooldownID)
        item.foreverKey, item.foreverSpell, item.foreverSlot = key, live, slot
        item.foreverSetting = active and Setting(key) or nil
        item.foreverState = StateOf(item)
        if item.foreverSetting and (item.foreverSetting.hidden or item.foreverState == "hide") then
            -- sa place revient aux suivants
            if Visible(item) and item.foreverHome then slots[#slots + 1] = item.foreverHome end
            item:ClearAllPoints()
            item:SetPoint("TOPRIGHT", UIParent, "TOPLEFT", -1000, 1000)
            item:SetAlpha(0)
            item.foreverHidden, item.foreverDimmed = true, nil
        else
            if item.foreverHome then
                if Visible(item) then
                    shown[#shown + 1] = item
                    slots[#slots + 1] = item.foreverHome
                elseif item.foreverHidden then   -- caché par Blizzard pendant qu'il était parqué
                    local home = item.foreverHome
                    item:ClearAllPoints()
                    item:SetPoint(home[1], home[2], home[3], home[4], home[5])
                end
            end
            local dim = item.foreverState == "dim"
            if item.foreverHidden or (item.foreverDimmed or false) ~= dim then
                item:SetAlpha(dim and DIM_ALPHA or 1)
                item.foreverHidden, item.foreverDimmed = nil, dim or nil
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

--- États relus (recharge, utilisable) : viewer remis en page seulement si un effet a changé.
function CooldownManager:UpdateStates()
    for _, def in ipairs(VIEWERS) do
        local viewer = _G[def.name]
        for _, item in ipairs(viewer and Items(viewer) or {}) do
            if item.foreverSetting and StateOf(item) ~= item.foreverState then
                self:ApplyViewer(viewer)
                break
            end
        end
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
-- Visibilité par viewer (Core/Visibility) : alpha seulement, par-dessus l'opacité Edit Mode
--------------------------------------------------------------------------------

local function VisibilityKey(def) return "cdm_" .. def.key end

local function ForceVisible() return NS:Previewing() or NS.IsEditModeActive() end

local function RegisterVisibility()
    for _, def in ipairs(VIEWERS) do
        local viewer = _G[def.name]
        if viewer and not NS.Visibility.entries[VisibilityKey(def)] then
            NS.Visibility:Register(VisibilityKey(def), viewer, function() return CooldownManager.db.visibility[def.key] end, {
                apply = function(frame, visible) frame.muscaVisible = visible end,
                alpha = function() return viewer.muscaVisible == false and 0 or NS.GetCooldownViewerOpacity(viewer) end,
                forceVisible = ForceVisible,
            })
        end
    end
end

local function UnregisterVisibility()
    for _, def in ipairs(VIEWERS) do
        local viewer = _G[def.name]
        if NS.Visibility.entries[VisibilityKey(def)] then
            NS.Visibility:Unregister(VisibilityKey(def))
            viewer.muscaVisible = nil
            viewer:SetAlpha(NS.GetCooldownViewerOpacity(viewer))
        end
    end
end

local function RefreshVisibility()
    if not active then return end
    for _, def in ipairs(VIEWERS) do NS.Visibility:Refresh(VisibilityKey(def)) end
end

NS:On("PREVIEW", RefreshVisibility)
NS.OnEditModeToggle(CooldownManager, RefreshVisibility)

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

--- Raccourci du sort lu sur nos barres d'action (premier bouton lié qui porte le sort), mis en cache.
local keybinds = {}
local function Keybind(spellID)
    if keybinds[spellID] == nil then
        local text, bars = false, NS.Modules:Get("actionbars")
        if bars and bars.enabled then
            for _, slot in ipairs(NS.FindSpellActionSlots(spellID)) do
                for _, bar in pairs(bars.bars or {}) do
                    for _, button in ipairs(bar.buttons or {}) do
                        if not text and button.action == slot then text = NS.GetBindingText(bars.CommandFor(button)) or false end
                    end
                end
            end
        end
        keybinds[spellID] = text
    end
    return keybinds[spellID] or nil
end

--- Texte du raccourci sur un calque au-dessus du cadran de recharge.
local function StyleKeybind(item, def)
    local cfg = CooldownManager.db.keybind
    local text = active and cfg.enabled and def.category <= 1 and type(item.foreverKey) == "number"
        and Keybind(item.foreverKey) or nil
    local overlay = item.muscaOverlay
    if not text then
        if overlay then overlay:Hide() end
        return
    end
    if not overlay then
        overlay = CreateFrame("Frame", nil, item)
        overlay:SetAllPoints(item)
        overlay:SetFrameLevel(item:GetFrameLevel() + 10)
        overlay.text = overlay:CreateFontString(nil, "OVERLAY")
        item.muscaOverlay = overlay
    end
    local font, size = NS.Media:Font()
    overlay.text:SetFont(cfg.font ~= "inherit" and cfg.font or font, cfg.fontSize or size, NS.Media:Outline())
    overlay.text:ClearAllPoints()
    local inset = 2
    local x = cfg.anchor:find("LEFT") and inset or (cfg.anchor:find("RIGHT") and -inset or 0)
    local y = cfg.anchor:find("TOP") and -inset or (cfg.anchor:find("BOTTOM") and inset or 0)
    overlay.text:SetPoint(cfg.anchor, overlay, cfg.anchor, x, y)
    overlay.text:SetText(text)
    overlay:Show()
end

--- Habille (ou rend, inactif) un item de viewer selon le réglage de sa barre.
function CooldownManager.StyleItem(item, def)
    local cfg = CooldownManager.db.skin[def.key] or {}
    local on = active
    StyleKeybind(item, def)
    local bar, icon, name, duration
    if def.bars then bar, icon, name, duration = BarParts(item) end
    local holder = (def.bars and type(icon) == "table" and icon.CreateTexture and icon) or item
    if on and cfg.border and not holder.muscaBorder then holder.muscaBorder = NS.Media:CreateBorder(holder) end
    for _, edge in pairs(holder.muscaBorder or {}) do edge:SetShown(on and cfg.border and true or false) end
    for _, text in ipairs(Counters(item)) do StyleFont(text, on and (cfg.fontSize or 0) or 0) end
    if not (bar and bar.SetStatusBarTexture) then return end
    local styled = on and cfg.barTexture
    if styled then
        if not bar.muscaOriginal then
            local texture = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
            bar.muscaOriginal = { texture = texture and texture.GetTexture and texture:GetTexture(),
                                 color = { bar:GetStatusBarColor() } }
        end
        bar:SetStatusBarTexture(NS.Media:StatusBarTexture())
        local color = cfg.barColor
        bar:SetStatusBarColor(color.r, color.g, color.b)
        if bar.BarBG then bar.BarBG:SetAlpha(0) end
    elseif bar.muscaOriginal then
        if bar.muscaOriginal.texture then bar:SetStatusBarTexture(bar.muscaOriginal.texture) end
        local color = bar.muscaOriginal.color
        if color[1] then bar:SetStatusBarColor(color[1], color[2], color[3]) end
        if bar.BarBG then bar.BarBG:SetAlpha(1) end
        bar.muscaOriginal = nil
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

-- Mise à jour l'image suivante : items créés ou recyclés par Blizzard, alerte de proc créée à la demande.
local queued = false
local function QueueUpdate()
    if queued then return end
    queued = true
    C_Timer.After(0, function()
        queued = false
        if not active then return end
        CooldownManager:UpdateStates()
        CooldownManager:UpdateBuffGlows()
        CooldownManager:UpdateGlows()
        CooldownManager:ApplySkin()
    end)
end

function CooldownManager:ApplyAll()
    for _, def in ipairs(VIEWERS) do
        local viewer = _G[def.name]
        if viewer then self:ApplyViewer(viewer) end
    end
    self:UpdateBuffGlows()
    self:UpdateGlows()
    self:ApplySkin()
end

local BINDING_EVENTS = { UPDATE_BINDINGS = true, ACTIONBAR_SLOT_CHANGED = true, UPDATE_BONUS_ACTIONBAR = true,
                         SPELLS_CHANGED = true, PLAYER_ENTERING_WORLD = true,
                         ACTIONBAR_PAGE_CHANGED = true }

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, ...)
    if not active then return end
    if BINDING_EVENTS[event] then wipe(keybinds) end
    if event == "ADDON_LOADED" or event == "PLAYER_ENTERING_WORLD" then
        HookViewers()   -- Blizzard_CooldownViewer se charge à la demande
        RegisterVisibility()
    elseif event == "EDIT_MODE_LAYOUTS_UPDATED" then
        C_Timer.After(0, RefreshVisibility)   -- après l'opacité Edit Mode, posée sur le même événement
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        OpenWindows(select(3, ...))
    end
    QueueUpdate()
end)

function CooldownManager:OnEnable()
    active = true
    wipe(keybinds)
    for _, event in ipairs({ "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_CHARGES",
                             "SPELL_UPDATE_USABLE", "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE",
                             "UPDATE_BINDINGS", "ACTIONBAR_SLOT_CHANGED", "UPDATE_BONUS_ACTIONBAR", "ACTIONBAR_PAGE_CHANGED", "SPELLS_CHANGED",
                             "EDIT_MODE_LAYOUTS_UPDATED" }) do
        NS.RegisterEventSafe(events, event)
    end
    NS.RegisterEventSafe(events, "UNIT_AURA", "player")
    NS.RegisterEventSafe(events, "UNIT_SPELLCAST_SUCCEEDED", "player")
    HookViewers()
    RegisterVisibility()
    self:ApplyAll()   -- viewers déjà hookés (réactivation) : places notées gardées
end

function CooldownManager:OnDisable()
    active = false
    events:UnregisterAllEvents()
    UnregisterVisibility()
    self:ApplyAll()   -- inactif : tout revient à sa place d'origine, opaque, sans lueur
end

function CooldownManager:OnRefresh()
    if active then
        wipe(keybinds)
        HookViewers()
        RefreshVisibility()
    end
    self:ApplyAll()
end

--------------------------------------------------------------------------------
-- Options : choix du sort par icône, puis ses réglages
--------------------------------------------------------------------------------

local ICON_SIZE, ICON_GAP, PER_ROW, ROWS = 32, 4, 15, 4
local FOOTER_HEIGHT = 200
local PICKER_HEIGHT = 32 + ROWS * (ICON_SIZE + ICON_GAP) + FOOTER_HEIGHT
local WINDOW_SECONDS = { 3, 5, 8, 10, 15, 20, 30 }

local function Entry(spellID)
    local spells = CooldownManager.db.spells
    spells[spellID] = spells[spellID] or {}
    return spells[spellID]
end

--- Réglage changé : entrée vide retirée, barres remises en page.
local function Changed(spellID)
    local spells = CooldownManager.db.spells
    if type(spells[spellID]) == "table" and not next(spells[spellID]) then spells[spellID] = nil end
    NS.Modules:Refresh("cooldownmanager")
end

local function GlowChoices(withNone)
    local choices = NS.Glow.Choices()
    if withNone then table.insert(choices, 1, { name = L.OPT_CDM_GLOW_NONE, value = "none" }) end
    return choices
end

function CooldownManager:BuildOptions(o)
    local layout = o.layout
    o:Note(L.NOTE_CDM)
    o:Button(L.OPT_CDM_OPEN_SETTINGS, function() NS.OpenCooldownViewerSettings() end)
    o:Dropdown("glowStyle", L.OPT_GLOW_STYLE, GlowChoices())
    o:Color("glowColor", L.OPT_CDM_GLOW_COLOR)
    o:Dropdown("procGlowStyle", L.OPT_CDM_PROC_GLOW, GlowChoices(true))
    o:Advanced()
    o:Color("procGlowColor", L.OPT_CDM_PROC_GLOW_COLOR, 20)
    o:EndAdvanced()
    o:Dropdown("buffGlowStyle", L.OPT_CDM_BUFF_GLOW, GlowChoices())
    o:Advanced()
    o:Color("buffGlowColor", L.OPT_CDM_BUFF_GLOW_COLOR, 20)
    o:EndAdvanced()

    o:Title(L.OPT_CDM_KEYBIND_TITLE)
    o:Check("keybind.enabled", L.OPT_CDM_KEYBIND)
    o:Dropdown("keybind.font", L.OPT_CDM_KEYBIND_FONT, function()
        local choices = { { name = L.OPT_MEDIA_INHERIT, value = "inherit" } }
        for _, font in ipairs(NS.GetFontList()) do choices[#choices + 1] = { name = font.name, value = font.path, font = font.path } end
        return choices
    end, 20)
    o:Slider("keybind.fontSize", L.OPT_CDM_KEYBIND_SIZE, 8, 24, 1, 20)
    local anchors = {}
    for _, point in ipairs({ "TOPLEFT", "TOPRIGHT", "CENTER", "BOTTOMLEFT", "BOTTOMRIGHT" }) do
        anchors[#anchors + 1] = { name = L["POINT_" .. point], value = point }
    end
    o:Dropdown("keybind.anchor", L.OPT_CDM_KEYBIND_ANCHOR, anchors, 20)

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
    categories[#categories + 1] = { name = L.OPT_CDM_EXTRA, value = "extra" }
    local Paint
    local categoryButton = NS.Widgets.Dropdown(picker, 300, L.OPT_CDM_BAR, categories,
        function() return category end, function(value) category, selected = value, nil Paint() end)
    categoryButton:SetPoint("TOPLEFT", picker, "TOPLEFT", 0, 0)

    local empty = picker:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    empty:SetPoint("TOPLEFT", picker, "TOPLEFT", 0, -36)
    empty:SetText(L.OPT_CDM_EMPTY)

    --- Réglage du sort choisi : valeur (nil efface), puis remise en page.
    local function Set(field, value)
        if not selected then return end
        Entry(selected)[field] = value
        Changed(selected)
        Paint()
    end

    local footer = -32 - ROWS * (ICON_SIZE + ICON_GAP) - 6
    local title = picker:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetPoint("TOPLEFT", picker, "TOPLEFT", 0, footer)
    local show = CreateFrame("CheckButton", nil, picker, "UICheckButtonTemplate")
    show:SetPoint("TOPLEFT", picker, "TOPLEFT", -4, footer - 18)
    local showText = show.Text or show.text or show:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    showText:SetPoint("LEFT", show, "RIGHT", 2, 0)
    showText:SetText(L.OPT_CDM_SHOW)
    show:SetScript("OnClick", function(self) Set("hidden", not self:GetChecked() or nil) end)

    local function Field(field, default)
        return function() local s = selected and Setting(selected) return s and s[field] or default end
    end
    local glow = NS.Widgets.Dropdown(picker, 300, L.OPT_CDM_GLOW, {
        { name = L.OPT_CDM_GLOW_NONE, value = "none" },
        { name = L.OPT_CDM_GLOW_READY, value = "ready" },
        { name = L.OPT_CDM_GLOW_MAXCHARGES, value = "maxcharges" },
        { name = L.OPT_CDM_GLOW_ALWAYS, value = "always" },
    }, Field("glow", "none"), function(value) Set("glow", value ~= "none" and value or nil) end)
    glow:SetPoint("TOPLEFT", picker, "TOPLEFT", 200, footer - 20)
    local state = NS.Widgets.Dropdown(picker, 300, L.OPT_CDM_STATE, {
        { name = L.OPT_CDM_STATE_NONE, value = "none" },
        { name = L.OPT_CDM_STATE_DIM, value = "dim" },
        { name = L.OPT_CDM_STATE_HIDE_COOLDOWN, value = "hideCooldown" },
        { name = L.OPT_CDM_STATE_HIDE_READY, value = "hideReady" },
        { name = L.OPT_CDM_STATE_HIDE_UNUSABLE, value = "hideUnusable" },
    }, Field("state", "none"), function(value) Set("state", value ~= "none" and value or nil) end)
    state:SetPoint("TOPLEFT", picker, "TOPLEFT", 0, footer - 76)
    local windowChoices = { { name = L.OPT_CDM_WINDOW_OFF, value = 0 } }
    for _, seconds in ipairs(WINDOW_SECONDS) do
        windowChoices[#windowChoices + 1] = { name = string.format(L.OPT_CDM_SECONDS, seconds), value = seconds }
    end
    local window = NS.Widgets.Dropdown(picker, 300, L.OPT_CDM_WINDOW, windowChoices, Field("window", 0),
        function(value) Set("window", value > 0 and value or nil) end)
    window:SetPoint("TOPLEFT", picker, "TOPLEFT", 310, footer - 76)
    local windowGlow = CreateFrame("CheckButton", nil, picker, "UICheckButtonTemplate")
    windowGlow:SetPoint("TOPLEFT", picker, "TOPLEFT", 306, footer - 130)
    local windowGlowText = windowGlow.Text or windowGlow.text or windowGlow:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    windowGlowText:SetPoint("LEFT", windowGlow, "RIGHT", 2, 0)
    windowGlowText:SetText(L.OPT_CDM_WINDOW_GLOW)
    windowGlow:SetScript("OnClick", function(self) Set("windowNoGlow", not self:GetChecked() or nil) end)
    local buffTarget = NS.Widgets.Dropdown(picker, 300, L.OPT_CDM_BUFF_TARGET, function()
        local choices = { { name = L.OPT_CDM_GLOW_NONE, value = 0 } }
        for _, spell in ipairs(NS.GetCooldownViewerSpells({ 0, 1 })) do
            if type(spell.spellID) == "number" then choices[#choices + 1] = { name = spell.name, value = spell.spellID } end
        end
        return choices
    end, Field("buffGlow", 0), function(value) Set("buffGlow", value ~= 0 and value or nil) end)
    buffTarget:SetPoint("TOPLEFT", picker, "TOPLEFT", 0, footer - 76)

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
            if self.slot and GameTooltip.SetInventoryItem then GameTooltip:SetInventoryItem("player", self.slot)
            elseif not self.slot and GameTooltip.SetSpellByID then GameTooltip:SetSpellByID(self.spellID)
            else GameTooltip:SetText(self.name or "") end
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function() GameTooltip:Hide() end)
        buttons[i] = button
        return button
    end

    function Paint()
        local buffs = category == 2 or category == 3
        spells = NS.GetCooldownViewerSpells(category == "extra" and EXTRA_CATEGORIES or category)
        local accent = { NS.Media:Accent() }
        local selectedSpell
        for i = 1, math.min(#spells, PER_ROW * ROWS) do
            local spell, button = spells[i], Button(i)
            button.spellID, button.name, button.slot = spell.spellID, spell.name, spell.slot
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
        title:SetText(selectedSpell and ((selectedSpell.icon and ("|T" .. selectedSpell.icon .. ":16|t ") or "") .. (selectedSpell.name or "")) or L.OPT_CDM_PICK)
        local s = selected and Setting(selected)
        show:SetChecked(not (s and s.hidden))
        NS.Widgets.SetEnabled(show, selected ~= nil)
        -- buffs : lueur liée seulement ; recharges : lueur, état, fenêtre (pas pour un bijou)
        glow:SetShown(not buffs)
        state:SetShown(not buffs)
        window:SetShown(not buffs and not (selectedSpell and selectedSpell.slot))
        windowGlow:SetShown(window:IsShown())
        windowGlow:SetChecked(not (s and s.windowNoGlow))
        NS.Widgets.SetEnabled(windowGlow, s and s.window and true or false)
        buffTarget:SetShown(buffs)
        for _, widget in ipairs({ glow, state, window, buffTarget }) do
            NS.Widgets.SetEnabled(widget, selected ~= nil)
            widget.Paint()
        end
        categoryButton.Paint()
    end

    picker:SetScript("OnShow", Paint)   -- la liste suit la spé courante
    layout.refreshers[#layout.refreshers + 1] = Paint
    Paint()

    for _, def in ipairs(VIEWERS) do
        o:Visibility("visibility." .. def.key, string.format(L.OPT_CDM_VISIBILITY, L[def.label]), { noMouseover = true })
    end
end

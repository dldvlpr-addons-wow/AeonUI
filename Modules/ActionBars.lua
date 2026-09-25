-- Modules/ActionBars.lua
-- Barres d'action AeonUI : six barres de boutons Blizzard (ActionBarButtonTemplate : icône,
-- recharge, compteur, portée, raccourci et glisser-déposer dessinés par le code Blizzard, donc
-- sûrs face aux valeurs secrètes) posés sur des barres AeonUI protégées (SecureFrameTemplate).
--
-- Pagination sans snippet restreint (ce moteur n'a pas de loadstring : aucun gestionnaire
-- d'état ni initialConfigFunction ne compile) : un pilote d'attribut par bouton de la barre 1
-- (RegisterAttributeDriver "actionpage", formes, furtivité, pages 2-6), relu par le code
-- Blizzard (ID du bouton + (page - 1) * 12). Raccourcis : SetOverrideBindingClick depuis les
-- touches Blizzard (ACTIONBUTTONn, MULTIACTIONBARnBUTTONn). Les barres Blizzard remplacées
-- sont cachées et coupées de leurs événements (jamais reparentées : gérées par Edit Mode).
local _, NS = ...
local L = NS.L
local Movers = NS.Movers

local NUM_BUTTONS = 12

local function Bar(enabled, overrides)
    local cfg = { enabled = enabled, buttons = 12, perRow = 12, size = 36, spacing = 4, alpha = 1, mouseover = false }
    for k, v in pairs(overrides or {}) do cfg[k] = v end
    return cfg
end

local ActionBars = NS.Modules:Register("actionbars", {
    reloadOnDisable = true,   -- cadres Blizzard rendus au /reload seulement : les options le proposent
    titleKey = "ACTIONBARS_TITLE",
    descKey = "ACTIONBARS_DESC",
    yieldsTo = { "ElvUI", "Bartender4", "Dominos" },
    secure = true,
    defaults = {
        enabled = false,
        hideBlizzard = true,
        microMenu = "move",       -- "move" (mover) | "hide" | "keep"
        bags = "move",
        stanceBar = "move",       -- postures, formes, auras, furtivité : boutons Blizzard, déplaçables
        totemBar = "move",        -- barre de totems du chaman (MultiCastActionBarFrame), déplaçable
        petBar = "move",
        hotkeys = true,           -- texte du raccourci sur les boutons
        macroNames = true,        -- nom de la macro sur les boutons
        bars = { Bar(true), Bar(true), Bar(true), Bar(false, { perRow = 1 }), Bar(false, { perRow = 1 }), Bar(false) },
    },
})

ActionBars.bars = {}

-- Barre n -> touches Blizzard, page fixe, cadre Blizzard remplacé.
local BAR_DEFS = {
    { binding = "ACTIONBUTTON%d",          blizzard = { "MainActionBar", "MainMenuBar" }, main = true },
    { binding = "MULTIACTIONBAR1BUTTON%d", page = 6, blizzard = { "MultiBarBottomLeft" } },
    { binding = "MULTIACTIONBAR2BUTTON%d", page = 5, blizzard = { "MultiBarBottomRight" } },
    { binding = "MULTIACTIONBAR3BUTTON%d", page = 3, blizzard = { "MultiBarRight" } },
    { binding = "MULTIACTIONBAR4BUTTON%d", page = 4, blizzard = { "MultiBarLeft" } },
    { binding = "MULTIACTIONBAR5BUTTON%d", page = 13, blizzard = { "MultiBar5" } },
}

-- Formes et furtivité (contenu Classic) : bonusbar 1 chat/furtif, 2 prowl, 3 ours, 4 lune.
-- Véhicule, possession (Contrôle mental, Yeux de la bête) et barre de remplacement : page 12
-- (véhicule Blizzard) et barre 1 cachée pour laisser la barre Blizzard dédiée.
local SPECIAL_BAR = "[overridebar][vehicleui][possessbar]"
local PAGE_DRIVER = SPECIAL_BAR .. " 12; [bar:2] 2; [bar:3] 3; [bar:4] 4; [bar:5] 5; [bar:6] 6; "
    .. "[bonusbar:1] 7; [bonusbar:2] 8; [bonusbar:3] 9; [bonusbar:4] 10; [bonusbar:5] 11; 1"

local MOVER_DEFAULTS = {
    { "BOTTOM", 0, 40 }, { "BOTTOM", 0, 84 }, { "BOTTOM", 0, 128 },
    { "RIGHT", -40, 0 }, { "RIGHT", -84, 0 }, { "BOTTOM", 0, 172 },
}

local active = false

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

local function S(n) return NS.Pixel:Scale(n) end

--------------------------------------------------------------------------------
-- Valeurs secrètes et taint
--------------------------------------------------------------------------------
-- Un bouton créé par un addon est « tainté » : le code Blizzard qui tourne pour lui aussi. Or
-- SetCooldown refuse une valeur secrète en exécution taintée. Deux conséquences :
--   * nos boutons ne doivent pas rester dans les diffuseurs Blizzard (ActionBarButtonEventsFrame,
--     ActionBarActionEventsFrame) : leur boucle de dispatch deviendrait taintée et casserait les
--     boutons Blizzard suivants (barre de véhicule) ; on les en retire, et on leur dispatche
--     nous-mêmes les mêmes événements ;
--   * la recharge est peinte par nous, via l'objet durée (SetCooldownFromDurationObject), jamais
--     par SetCooldown sur une valeur secrète.

local BUTTON_EVENTS = {
    "PLAYER_ENTERING_WORLD", "ACTIONBAR_SHOWGRID", "ACTIONBAR_HIDEGRID", "ACTIONBAR_SLOT_CHANGED",
    "UPDATE_BINDINGS", "UPDATE_SHAPESHIFT_FORM", "ACTIONBAR_UPDATE_COOLDOWN", "ACTIONBAR_UPDATE_STATE",
    "ACTIONBAR_UPDATE_USABLE", "SPELL_UPDATE_CHARGES", "SPELL_UPDATE_ICON", "SPELL_UPDATE_USABLE",
    "PLAYER_TARGET_CHANGED", "TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE", "PLAYER_MOUNT_DISPLAY_CHANGED",
    "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", "PET_BAR_UPDATE",
    "PLAYER_EQUIPMENT_CHANGED", "LOSS_OF_CONTROL_ADDED", "LOSS_OF_CONTROL_UPDATE", "ACTIONBAR_PAGE_CHANGED",
    "UPDATE_BONUS_ACTIONBAR", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "BAG_UPDATE_COOLDOWN",
    "ACTION_RANGE_CHECK_UPDATE", "ACTION_USABLE_CHANGED",
}
local BUTTON_UNIT_EVENTS = {
    "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP",
    "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_SENT",
    "UNIT_INVENTORY_CHANGED", "UNIT_AURA",
}

--- Recharge d'un bouton sans jamais comparer ni transmettre une valeur secrète à SetCooldown.
function ActionBars.PaintCooldown(button)
    local cooldown, action = button.cooldown, button.action
    if not cooldown or not action then return end
    if C_ActionBar and C_ActionBar.GetActionCooldownDuration and cooldown.SetCooldownFromDurationObject then
        local info = C_ActionBar.GetActionCooldown and C_ActionBar.GetActionCooldown(action)
        local durationObject = info and info.isActive and C_ActionBar.GetActionCooldownDuration(action)
        if durationObject then cooldown:SetCooldownFromDurationObject(durationObject) else cooldown:Clear() end
        return
    end
    local start, duration, _, modRate = GetActionCooldown(action)
    if start == nil or (issecretvalue and (issecretvalue(start) or issecretvalue(duration))) then
        cooldown:Clear()
    else
        cooldown:SetCooldown(start, duration, modRate)
    end
end

--- Cache une barre Blizzard malgré Edit Mode, qui la remontre à chaque application de disposition.
-- Barre principale : jamais reparentée (art et pager gérés par Edit Mode) : cachée, alpha 0,
-- souris coupée, et un hook de Show réassure l'alpha. Autres barres : reparentées sous le
-- cadre caché (NS.HideBlizzardFrame ramène le parent si Blizzard le change). Les boutons sont
-- coupés de leurs événements et marqués statehidden (Blizzard les cache lui-même).
local mainBarHooked = {}
local function HideBlizzardBar(def)
    for _, name in ipairs(def.blizzard) do
        local frame = _G[name]
        if frame then
            if def.main then
                NS.HideBlizzardFrame(frame, true)
                frame:SetAlpha(0)
                frame:EnableMouse(false)
                for _, key in ipairs({ "EndCaps", "BorderArt", "Background", "ActionBarPageNumber" }) do
                    if frame[key] and frame[key].Hide then frame[key]:Hide() end
                end
                if not mainBarHooked[frame] then
                    mainBarHooked[frame] = true
                    hooksecurefunc(frame, "Show", function(self)
                        if active and NS.IsBlizzardFrameHidden(self) then self:SetAlpha(0) end
                    end)
                end
            else
                NS.HideBlizzardFrame(frame)
            end
            for _, button in ipairs(type(frame.actionButtons) == "table" and frame.actionButtons or {}) do
                button:UnregisterAllEvents()
                if button.SetAttributeNoHandler then button:SetAttributeNoHandler("statehidden", true) end
            end
        end
    end
end

local function ShowBlizzardBar(def)
    for _, name in ipairs(def.blizzard) do
        local frame = _G[name]
        if frame then
            NS.ShowBlizzardFrame(frame)
            if def.main then frame:SetAlpha(1) frame:EnableMouse(true) end
        end
    end
end

--- Le code Blizzard du bouton (ActionButton_ApplyCooldown, fonction globale : pas de méthode à
-- redéfinir) appelle cooldown:SetCooldown avec des valeurs secrètes : refusé sous notre taint.
-- La méthode est ombrée sur le Cooldown de nos boutons seulement : valeurs connues passées à
-- l'original, secrètes remplacées par la peinture par objet durée.
local function ShadowSetCooldown(button)
    local cooldown = button.cooldown
    if not cooldown or cooldown.foreverOriginalSetCooldown then return end
    cooldown.foreverOriginalSetCooldown = cooldown.SetCooldown
    cooldown.SetCooldown = function(self, start, duration, modRate)
        if issecretvalue and (issecretvalue(start) or issecretvalue(duration) or issecretvalue(modRate)) then
            ActionBars.PaintCooldown(button)
        else
            self.foreverOriginalSetCooldown(self, start, duration, modRate)
        end
    end
end

-- Micro-menu et sacs : systèmes Edit Mode, jamais reparentés ; posés sur un mover, ou cachés.
-- styled : ils ont aussi un style AeonUI (modes "aeonui" et "topbar", voir plus bas).
local SIDE_FRAMES = {
    micromenu = { names = { "MicroMenuContainer", "MicroButtonAndBagsBar" }, option = "microMenu", label = "MOVER_MICROMENU", default = { "BOTTOMRIGHT", -10, 10 }, styled = true },
    bags = { names = { "BagsBar" }, option = "bags", label = "MOVER_BAGS", default = { "BOTTOMRIGHT", -10, 60 }, styled = true },
    stance = { names = { "StanceBar", "StanceBarFrame" }, option = "stanceBar", label = "MOVER_STANCE", default = { "BOTTOM", -320, 176 } },
    pet = { names = { "PetActionBar", "PetActionBarFrame" }, option = "petBar", label = "MOVER_PET", default = { "BOTTOM", 0, 218 } },
    totem = { names = { "MultiCastActionBarFrame" }, option = "totemBar", label = "MOVER_TOTEM_BAR", default = { "BOTTOM", 320, 176 } },
}
local function SideFrame(def)
    local frame
    for _, name in ipairs(def.names) do frame = frame or _G[name] end
    return frame
end

-- Style AeonUI : boutons plats du thème qui relaient le clic au bouton Blizzard (action
-- sécurisée "click" : le panneau s'ouvre comme d'un clic direct, sans taint). Rangée sur son
-- mover ("aeonui") ou dans la barre du haut ("topbar"). Construite hors combat.
-- ponytail: pas d'alertes Blizzard (talent à dépenser…) ni de glisser-déposer sur les sacs.
local STYLED_SIZE = 24
local BAG_BUTTONS = { "MainMenuBarBackpackButton", "CharacterBag0Slot", "CharacterBag1Slot", "CharacterBag2Slot",
                      "CharacterBag3Slot", "CharacterReagentBag0Slot" }
local styled = {}   -- [clé] = rangée AeonUI

local STYLED_SOURCES = {
    -- Liste globale MICRO_BUTTONS si le client l'a ; sinon (moteur 12.x) les boutons « …MicroButton »
    -- enfants du micro-menu, dans l'ordre de sa disposition (layoutIndex).
    micromenu = function()
        local list = {}
        if _G.MICRO_BUTTONS then
            for _, name in ipairs(_G.MICRO_BUTTONS) do
                local button = _G[name]
                if button and button:IsShown() then list[#list + 1] = button end
            end
            return list
        end
        local function Collect(parent, depth)
            for _, child in ipairs({ parent:GetChildren() }) do
                local name = child.GetName and child:GetName()
                if name and name:find("MicroButton$") then
                    if child:IsShown() then list[#list + 1] = child end
                elseif depth < 2 then
                    Collect(child, depth + 1)
                end
            end
        end
        local root = _G.MicroMenu or _G.MicroMenuContainer or _G.MicroButtonAndBagsBar
        if root then Collect(root, 1) end
        local found = {}
        for i, button in ipairs(list) do found[button] = i end
        table.sort(list, function(a, b)
            local ia, ib = a.layoutIndex or found[a], b.layoutIndex or found[b]
            if ia == ib then return found[a] < found[b] end
            return ia < ib
        end)
        return list
    end,
    bags = function()
        local list = {}
        for _, name in ipairs(BAG_BUTTONS) do
            if _G[name] then list[#list + 1] = _G[name] end
        end
        return list
    end,
}

--- Même image que le bouton Blizzard : atlas du micro-bouton, icône du sac, sinon portrait.
local function CopyIcon(texture, source)
    local normal = source.GetNormalTexture and source:GetNormalTexture()
    local atlas = normal and normal.GetAtlas and normal:GetAtlas()
    if atlas then texture:SetAtlas(atlas) return end
    local icon = source.icon or source.Icon or _G[(source:GetName() or "") .. "IconTexture"]
    local file = (icon and icon.GetTexture and icon:GetTexture()) or (normal and normal:GetTexture())
    if file then texture:SetTexture(file) elseif _G.SetPortraitTexture then SetPortraitTexture(texture, "player") end
end

local function StyledTooltip(button)
    local source = button.source
    local text = source and (source.tooltipText or source.newbieText)
    if not text then return end
    GameTooltip:SetOwner(button, "ANCHOR_BOTTOM")
    GameTooltip:SetText(text)
    GameTooltip:Show()
end

local function BuildStyled(key, size)
    local frame = styled[key]
    if not frame then
        frame = CreateFrame("Frame", "AeonUI_Styled_" .. key, UIParent)
        frame.buttons = {}
        styled[key] = frame
    end
    local sources = STYLED_SOURCES[key]()
    for i, source in ipairs(sources) do
        local button = frame.buttons[i]
        if not button then
            button = CreateFrame("Button", frame:GetName() .. "Button" .. i, frame, "SecureActionButtonTemplate")
            button:RegisterForClicks("AnyUp", "AnyDown")
            button:SetAttribute("type", "click")
            NS.Media:CreateBackdrop(button)
            button.icon = button:CreateTexture(nil, "ARTWORK")
            button.icon:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
            button.icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
            button:SetScript("OnEnter", StyledTooltip)
            button:SetScript("OnLeave", function() GameTooltip:Hide() end)
            frame.buttons[i] = button
        end
        button.source = source
        button:SetAttribute("clickbutton", source)
        CopyIcon(button.icon, source)
        button:SetSize(size, size)
        button:ClearAllPoints()
        button:SetPoint("LEFT", frame, "LEFT", (i - 1) * (size + 2), 0)
        button:Show()
    end
    for i = #sources + 1, #frame.buttons do frame.buttons[i]:Hide() end
    frame:SetSize(math.max(1, #sources * (size + 2) - 2), size)
    return frame
end

local function ReleaseStyled(key)
    local frame = styled[key]
    if not frame then return end
    Movers:Unregister(key .. "_styled")
    local topBar = NS.Modules:Get("topbar")
    if topBar and topBar.Undock then topBar:Undock(key) end
    frame:Hide()
end

--- Rangée AeonUI : dans la barre du haut si demandé et active, sinon sur son mover.
local function ApplyStyled(key, def, mode)
    local topBar = NS.Modules:Get("topbar")
    if mode == "topbar" and topBar and topBar.enabled and topBar.Dock then
        Movers:Unregister(key .. "_styled")
        topBar:Dock(key, BuildStyled(key, topBar.DOCK_SIZE))
        return
    end
    if topBar and topBar.Undock then topBar:Undock(key) end
    local frame = BuildStyled(key, STYLED_SIZE)
    frame:SetParent(UIParent)
    frame:Show()
    Movers:Register(key .. "_styled", frame, L[def.label], def.default[1], def.default[2], def.default[3])
    Movers:Load(key .. "_styled")
end

local function ApplySideFrames()
    for key, def in pairs(SIDE_FRAMES) do
        local frame = SideFrame(def)
        if frame then
            local mode = ActionBars.db[def.option]
            local isStyled = def.styled and (mode == "aeonui" or mode == "topbar")
            if not isStyled and def.styled then ReleaseStyled(key) end
            if mode == "hide" or isStyled then
                Movers:Release(key)
                NS.HideRegion(frame)
                if isStyled then ApplyStyled(key, def, mode) end
            else
                NS.ShowRegion(frame)
                if mode == "move" then Movers:Adopt(key, frame, L[def.label], def.default[1], def.default[2], def.default[3])
                else Movers:Release(key) end
            end
        end
    end
end
local function ReleaseSideFrames()
    for key, def in pairs(SIDE_FRAMES) do
        Movers:Release(key)
        for _, name in ipairs(def.names) do NS.ShowRegion(name) end
        if def.styled then ReleaseStyled(key) end
    end
end
ActionBars.GetStyled = function(key) return styled[key] end

local function DetachFromBlizzardDispatch(button)
    for _, name in ipairs({ "ActionBarButtonEventsFrame", "ActionBarActionEventsFrame" }) do
        local dispatcher = _G[name]
        if dispatcher and dispatcher.UnregisterFrame then
            dispatcher:UnregisterFrame(button)
        elseif dispatcher and type(dispatcher.frames) == "table" then
            for i = #dispatcher.frames, 1, -1 do
                if dispatcher.frames[i] == button then tremove(dispatcher.frames, i) end
            end
            dispatcher.frames[button] = nil
        end
    end
end

-- Diffuseurs à clés (cadre -> cadre) : Update et CheckNeedsUpdate du modèle y réinscrivent le
-- bouton à chaque changement d'action ou de clignotement. Retiré après chaque passage de notre
-- dispatch : une clé écrite par nous rendrait taintée la boucle Blizzard (barre de véhicule).
local KEYED_DISPATCHERS = { "ActionBarActionEventsFrame", "ActionBarButtonUpdateFrame" }
local function ReleaseFromKeyedDispatchers(button)
    for _, name in ipairs(KEYED_DISPATCHERS) do
        local dispatcher = _G[name]
        local frames = dispatcher and dispatcher.frames
        if type(frames) == "table" and frames[button] then frames[button] = nil end
    end
end

-- Portée et utilisabilité : Blizzard range nos boutons dans des tables par action partagées avec
-- ses propres boutons (même action que la barre de véhicule). Méthodes remplacées sur nos boutons :
-- la vérification de portée est activée, les événements arrivent par notre dispatch.
-- ponytail: jamais désactivée au retrait, coût négligeable ; à refaire si le client plafonne.
local function WatchAction(_, action)
    if action and C_ActionBar and C_ActionBar.EnableActionRangeCheck then C_ActionBar.EnableActionRangeCheck(action, true) end
end
local function UnwatchAction() end

local dispatchFailures = {}   -- [event] = true : un seul message par événement et par session
local pendingFullUpdate = false

-- Ces deux événements mènent le code Blizzard à SetAttribute (pressAndHoldAction) : bloqué en
-- combat sous notre taint. Différés à la sortie du combat.
local COMBAT_DEFERRED = { ACTIONBAR_SLOT_CHANGED = true, PLAYER_ENTERING_WORLD = true }

local Dispatch
function Dispatch(event, ...)
    if COMBAT_DEFERRED[event] and NS.InCombat() then pendingFullUpdate = true return end
    for _, bar in pairs(ActionBars.bars) do
        if bar:IsShown() then
            for _, button in ipairs(bar.buttons) do
                if button:IsShown() and button.OnEvent then
                    local ok, err = true, nil
                    if event == "ACTION_USABLE_CHANGED" then
                        if button.UpdateUsable then ok, err = pcall(button.UpdateUsable, button) end
                    elseif event ~= "ACTION_RANGE_CHECK_UPDATE" or button.action == ... then
                        ok, err = pcall(button.OnEvent, button, event, ...)
                    end
                    ReleaseFromKeyedDispatchers(button)
                    if not ok and not dispatchFailures[event] then
                        dispatchFailures[event] = true
                        NS.Print(string.format(L.MSG_AB_EVENT_FAILED, event, tostring(err)))
                    end
                end
            end
        end
    end
    if event == "PLAYER_REGEN_ENABLED" and pendingFullUpdate then
        pendingFullUpdate = false
        Dispatch("PLAYER_ENTERING_WORLD")
    end
end

local function NewBar(index)
    local bar = CreateFrame("Frame", "AeonUI_Bar" .. index, UIParent, "SecureFrameTemplate")
    bar.index = index
    bar.buttons = {}
    for i = 1, NUM_BUTTONS do
        local button = CreateFrame("CheckButton", bar:GetName() .. "Button" .. i, bar, "ActionBarButtonTemplate")
        button:SetID(i)
        button.buttonType = BAR_DEFS[index].binding:sub(1, -3)   -- « ACTIONBUTTON » : texte du raccourci Blizzard
        button:SetAttribute("forever-button", true)
        button:SetAttribute("actionpage", BAR_DEFS[index].page or 1)
        button.UpdateCooldown = ActionBars.PaintCooldown    -- si le mixin appelle self:UpdateCooldown()
        ShadowSetCooldown(button)                           -- s'il passe par la fonction globale
        NS.RegisterCooldown(button.cooldown)                -- texte de recharge coloré (Interface)
        button.RegisterActionBarButtonCheckFrames = WatchAction
        button.UnregisterActionBarButtonCheckFrames = UnwatchAction
        DetachFromBlizzardDispatch(button)
        ReleaseFromKeyedDispatchers(button)
        -- Taille native du modèle : la taille voulue s'obtient par l'échelle (voir LayoutBar).
        local width = button:GetWidth()
        button.baseSize = (width and width > 0) and width or 36
        bar.buttons[i] = button
    end
    ActionBars.bars[index] = bar
    return bar
end

local function LayoutBar(bar, cfg)
    local size, spacing = S(cfg.size), S(cfg.spacing)
    local count = math.max(1, math.min(NUM_BUTTONS, cfg.buttons))
    local perRow = math.max(1, math.min(count, cfg.perRow))
    local rows = math.ceil(count / perRow)
    bar:SetSize(perRow * size + (perRow - 1) * spacing, rows * size + (rows - 1) * spacing)
    bar:SetAlpha(cfg.alpha or 1)
    local db = ActionBars.db
    for i, button in ipairs(bar.buttons) do
        if button.HotKey then button.HotKey:SetAlpha(db.hotkeys and 1 or 0) end
        if button.Name then button.Name:SetAlpha(db.macroNames and 1 or 0) end
        if i <= count then
            -- Mise à l'échelle plutôt que SetSize : icône, bordure, masque, recharge et textes du
            -- modèle Blizzard ont des tailles fixes ; l'échelle les fait tous suivre le bouton.
            -- Les décalages d'un cadre mis à l'échelle sont dans son propre repère : divisés.
            local scale = size / button.baseSize
            local col, row = (i - 1) % perRow, math.floor((i - 1) / perRow)
            button:SetScale(scale)
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", bar, "TOPLEFT", col * (size + spacing) / scale, -row * (size + spacing) / scale)
            button:Show()
        else
            button:Hide()
        end
    end
end

--- Raccourcis : la touche Blizzard du bouton n de cette barre clique notre bouton.
local function BindBar(bar)
    ClearOverrideBindings(bar)
    local pattern = BAR_DEFS[bar.index].binding
    for i, button in ipairs(bar.buttons) do
        if button:IsShown() then
            for _, key in ipairs({ GetBindingKey(string.format(pattern, i)) }) do
                SetOverrideBindingClick(bar, true, key, button:GetName())
            end
        end
    end
end

local function SetupBar(index)
    local cfg = ActionBars.db.bars[index]
    local bar = ActionBars.bars[index] or NewBar(index)
    LayoutBar(bar, cfg)
    if index == 1 then
        for _, button in ipairs(bar.buttons) do RegisterAttributeDriver(button, "actionpage", PAGE_DRIVER) end
    end
    RegisterStateDriver(bar, "visibility", (index == 1 and (SPECIAL_BAR .. " hide; ") or "") .. "[petbattle] hide; show")
    local d = MOVER_DEFAULTS[index]
    Movers:Register("bar" .. index, bar, string.format(L.MOVER_ACTIONBAR, index), d[1], d[2], d[3])
    Movers:Load("bar" .. index)
    BindBar(bar)
    bar:Show()
    if ActionBars.db.hideBlizzard then
        HideBlizzardBar(BAR_DEFS[index])
    elseif index == 1 and NS.IsBlizzardFrameHidden(BAR_DEFS[1].blizzard[1]) then
        NS.Print(L.MSG_AB_SHOW_RELOAD)   -- les barres Blizzard ne revivent qu'au /reload
    end
end

local function TeardownBar(index)
    local bar = ActionBars.bars[index]
    if bar then
        UnregisterStateDriver(bar, "visibility")
        if index == 1 then
            for _, button in ipairs(bar.buttons) do UnregisterAttributeDriver(button, "actionpage") end
        end
        ClearOverrideBindings(bar)
        bar:Hide()
    end
    Movers:Unregister("bar" .. index)
    ShowBlizzardBar(BAR_DEFS[index])
end

--------------------------------------------------------------------------------
-- Fondu au survol
--------------------------------------------------------------------------------
-- Une barre « au survol » reste invisible tant que la souris n'est pas dessus, ou qu'un sort
-- n'est pas tenu au curseur, ou que le mode raccourcis n'est pas ouvert. SetAlpha est permis
-- en combat sur un cadre protégé : rien n'attend la fin du combat.

local FADE_INTERVAL = 0.1
local fader = CreateFrame("Frame")
fader.elapsed = 0

function ActionBars:UpdateFade()
    local holding = _G.GetCursorInfo and GetCursorInfo() ~= nil
    for index, bar in pairs(self.bars) do
        local cfg = self.db.bars[index]
        if bar:IsShown() then
            local visible = not cfg.mouseover or holding or self.binding or bar:IsMouseOver()
            bar:SetAlpha(visible and (cfg.alpha or 1) or 0)
            -- L'éclat de fin de recharge ignore l'alpha du parent : coupé sur une barre invisible.
            for _, button in ipairs(bar.buttons) do
                local cooldown = button.cooldown
                if cooldown and cooldown.SetDrawBling then cooldown:SetDrawBling(visible and true or false) end
            end
        end
    end
end

local function RunFader()
    local needed = false
    for index in pairs(ActionBars.bars) do
        local cfg = ActionBars.db.bars[index]
        if cfg.enabled and cfg.mouseover then needed = true end
    end
    if active and needed then
        fader:SetScript("OnUpdate", function(self, dt)
            self.elapsed = self.elapsed + dt
            if self.elapsed < FADE_INTERVAL then return end
            self.elapsed = 0
            ActionBars:UpdateFade()
        end)
        ActionBars:UpdateFade()
    else
        fader:SetScript("OnUpdate", nil)
    end
end

--------------------------------------------------------------------------------
-- Mode raccourcis (/aeon kb)
--------------------------------------------------------------------------------
-- Survoler un bouton AeonUI et appuyer sur une touche : la touche est liée à la commande
-- Blizzard du bouton (ACTIONBUTTONn, MULTIACTIONBARnBUTTONn), que BindBar relaie ensuite.
-- Échap sur un bouton efface ses touches, Échap ailleurs ferme le mode. SetBinding est
-- interdit en combat : le mode se ferme à l'entrée en combat.

local MODIFIER_KEYS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true,
                        LMETA = true, RMETA = true, UNKNOWN = true }

local binder = CreateFrame("Frame", "AeonUI_KeyBinder", UIParent)
binder:SetFrameStrata("DIALOG")
binder:SetAllPoints(UIParent)
binder:EnableKeyboard(true)
binder:Hide()

function ActionBars.CommandFor(button)
    local bar = button:GetParent()
    return string.format(BAR_DEFS[bar.index].binding, button:GetID())
end

function ActionBars:HoveredButton()
    for _, bar in pairs(self.bars) do
        if bar:IsShown() then
            for _, button in ipairs(bar.buttons) do
                if button:IsShown() and button:IsMouseOver() then return button end
            end
        end
    end
end

function ActionBars:BindKey(key)
    if MODIFIER_KEYS[key] then return end
    local button = self:HoveredButton()
    if not button then
        if key == "ESCAPE" then self:SetKeyBindMode(false) end
        return
    end
    local command = self.CommandFor(button)
    if key == "ESCAPE" then
        for _, old in ipairs({ GetBindingKey(command) }) do SetBinding(old) end
        binder.status:SetText(string.format(L.MSG_AB_KB_CLEARED, command))
    else
        local combo = (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "")
            .. (IsShiftKeyDown() and "SHIFT-" or "") .. key
        SetBinding(combo, command)
        binder.status:SetText(string.format(L.MSG_AB_KB_BOUND, combo, command))
    end
    SaveBindings(GetCurrentBindingSet())
end

binder:SetScript("OnKeyDown", function(_, key) ActionBars:BindKey(key) end)

--- Bandeau à l'écran tant que le mode est ouvert : consigne, puis dernière touche liée.
-- Créé au premier usage (le thème n'existe qu'après la connexion).
local function BuildBanner()
    if binder.banner then return end
    local banner = CreateFrame("Frame", nil, binder)
    banner:SetPoint("TOP", UIParent, "TOP", 0, -140)
    banner:SetSize(620, 58)
    NS.Media:CreateBackdrop(banner)   -- fond et bordure du thème
    banner.text = NS.Media:CreateText(banner, "OVERLAY", 4, "OUTLINE")
    banner.text:SetPoint("TOP", banner, "TOP", 0, -10)
    banner.text:SetWidth(600)
    banner.text:SetTextColor(1, 0.82, 0)
    binder.status = NS.Media:CreateText(banner, "OVERLAY", 0, "OUTLINE")
    binder.status:SetPoint("BOTTOM", banner, "BOTTOM", 0, 10)
    binder.banner = banner
end

--- Refus (combat, module coupé) : message rouge au centre de l'écran, comme les erreurs du jeu.
local function Warn(message)
    local errors = _G.UIErrorsFrame
    if errors and errors.AddMessage then errors:AddMessage(message, 1, 0.1, 0.1) else NS.Print(message) end
end

function ActionBars:SetKeyBindMode(on)
    if on and (not active or NS.InCombat()) then
        Warn(active and L.MSG_AB_KB_COMBAT or L.MSG_AB_KB_INACTIVE)
        return
    end
    self.binding = on and true or nil
    if on then
        BuildBanner()
        binder.banner.text:SetText(L.MSG_AB_KB_ON)
        binder.status:SetText("")
    end
    binder:SetShown(on and true or false)
    self:UpdateFade()
end

function ActionBars:ToggleKeyBind() self:SetKeyBindMode(not self.binding) end

function ActionBars:Reconcile()
    for index = 1, #BAR_DEFS do
        if self.db.bars[index].enabled then SetupBar(index) else TeardownBar(index) end
    end
    ApplySideFrames()
    RunFader()
end

function ActionBars:GetBar(index) return self.bars[index] end

--------------------------------------------------------------------------------
-- Cycle de vie
--------------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, ...)
    if not active then return end
    if event == "PLAYER_REGEN_DISABLED" and ActionBars.binding then ActionBars:SetKeyBindMode(false) end
    if event == "UPDATE_BINDINGS" then
        NS:RunOutOfCombat(function()
            if not active then return end
            for _, bar in pairs(ActionBars.bars) do if bar:IsShown() then BindBar(bar) end end
        end)
    end
    Dispatch(event, ...)
end)
-- Clignotement et état différé : Blizzard les mène par ActionBarButtonUpdateFrame, dont nos
-- boutons sont retirés. Même travail ici, pour les seuls boutons qui le demandent.
events:SetScript("OnUpdate", function(_, elapsed)
    if not active then return end
    for _, bar in pairs(ActionBars.bars) do
        for _, button in ipairs(bar.buttons) do
            if button.needsUpdate and button.OnUpdate then
                pcall(button.OnUpdate, button, elapsed)
                ReleaseFromKeyedDispatchers(button)
            end
        end
    end
end)

function ActionBars:OnEnable()
    active = true
    self:Reconcile()
    for _, event in ipairs(BUTTON_EVENTS) do NS.RegisterEventSafe(events, event) end
    for _, event in ipairs(BUTTON_UNIT_EVENTS) do NS.RegisterEventSafe(events, event, "player") end
    Dispatch("PLAYER_ENTERING_WORLD")
end

-- Barre du haut coupée ou rallumée : les rangées qui y étaient posées (micro-menu, sacs)
-- reviennent sur leur mover, sinon elles disparaissent avec elle.
NS:On("MODULE_TOGGLED", function(name)
    if name == "topbar" and active then NS.Modules:Refresh("actionbars") end
end)

function ActionBars:OnDisable()
    if self.binding then self:SetKeyBindMode(false) end
    active = false
    RunFader()
    events:UnregisterAllEvents()
    local had = next(self.bars) ~= nil
    for index = 1, #BAR_DEFS do TeardownBar(index) end
    ReleaseSideFrames()
    if had then NS.Print(L.MSG_AB_DISABLED_RELOAD) end
end

function ActionBars:OnRefresh()
    self:Reconcile()
end

NS:On("PIXEL_CHANGED", function()
    if active then NS:RunOutOfCombat(function() if active then ActionBars:Reconcile() end end) end
end)

--------------------------------------------------------------------------------
-- Options
--------------------------------------------------------------------------------

function ActionBars:BuildOptions(o)
    o.layout:Note(L.NOTE_AB_RELOAD, 20)
    o:Check("hideBlizzard", L.OPT_AB_HIDE_BLIZZARD)
    local SIDE_CHOICES = {
        { name = L.AB_SIDE_MOVE, value = "move" }, { name = L.AB_SIDE_HIDE, value = "hide" }, { name = L.AB_SIDE_KEEP, value = "keep" },
    }
    -- Micro-menu et sacs : affichés ou non, style Blizzard ou AeonUI, où les poser.
    local STYLED_CHOICES = {
        { name = L.AB_SIDE_TOPBAR, value = "topbar" }, { name = L.AB_SIDE_AEONUI, value = "aeonui" },
    }
    for _, choice in ipairs(SIDE_CHOICES) do STYLED_CHOICES[#STYLED_CHOICES + 1] = choice end
    o:Dropdown("microMenu", L.OPT_AB_MICROMENU, STYLED_CHOICES)
    o:Dropdown("bags", L.OPT_AB_BAGS, STYLED_CHOICES)
    o:Dropdown("stanceBar", L.OPT_AB_STANCE, SIDE_CHOICES)
    o:Dropdown("totemBar", L.OPT_AB_TOTEM, SIDE_CHOICES)
    o:Dropdown("petBar", L.OPT_AB_PET, SIDE_CHOICES)
    o:Check("hotkeys", L.OPT_AB_HOTKEYS)
    o:Check("macroNames", L.OPT_AB_MACRO_NAMES)
    o.layout:Button(L.OPT_AB_KEYBIND, function() ActionBars:ToggleKeyBind() end, 20)
    o:Hint(L.OPT_AB_KEYBIND_HINT)
    o.layout:Button(L.OPT_UF_UNLOCK, function() NS:SetUnlocked(not NS.unlocked) end, 20)
    -- Un onglet par barre ; « Copier depuis » reprend les réglages d'une autre barre.
    local sources = {}
    for index = 1, #BAR_DEFS do
        sources[index] = { name = string.format(L.MOVER_ACTIONBAR, index), value = "bars." .. index }
    end
    for index = 1, #BAR_DEFS do
        local key = "bars." .. index .. "."
        o:Tab(string.format(L.MOVER_ACTIONBAR, index))
        o:Check(key .. "enabled", L.OPT_AB_BAR_ENABLED)
        o:CopyFrom("bars." .. index, sources, 36)
        o:Slider(key .. "buttons", L.OPT_AB_BUTTONS, 1, 12, 1, 36)
        o:Slider(key .. "perRow", L.OPT_AB_PER_ROW, 1, 12, 1, 36)
        o:Slider(key .. "size", L.OPT_AB_SIZE, 20, 64, 1, 36)
        o:Slider(key .. "spacing", L.OPT_AB_SPACING, 0, 16, 1, 36)
        o:Slider(key .. "alpha", L.OPT_AB_ALPHA, 0.1, 1, 0.1, 36, "%.1f")
        o:Check(key .. "mouseover", L.OPT_AB_MOUSEOVER, 36)
    end
end

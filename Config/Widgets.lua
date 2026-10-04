-- Config/Widgets.lua
-- Constructeurs de widgets Blizzard (pas de lib), partagés par Options, FirstRun et le mode
-- déplacement. Un « layout » pose les widgets en colonne et garde la liste des fonctions qui
-- les resynchronisent depuis la DB (Refresh), appelée à chaque ouverture du panneau.
-- Mise en page :
--   * cases à cocher consécutives au même retrait : deux par ligne quand les libellés tiennent ;
--   * boutons consécutifs au même retrait : côte à côte tant que la largeur le permet ;
--   * retrait = dépendance : un widget plus en retrait qu'une case qui le précède est grisé
--     tant que cette case est décochée ;
--   * Tab(libellé) ouvre un onglet : les widgets suivants vont dans son cadre.
-- Mode grille (NewLayout(..., { grid = true })) : fenêtre d'options. Chaque réglage est une
-- ligne « libellé à gauche, contrôle à droite », deux par rangée ; titres, notes et boutons
-- prennent toute la largeur. Chaque titre ouvre un bloc encadré ; les réglages moins courants
-- (Advanced) restent affichés en fin de bloc, atténués ; en mode simple, ils sont masqués, et le
-- bloc entier quand il n'a que ceux-là. Les positions sont calculées par Reflow.
local _, NS = ...

local Widgets = {}
NS.Widgets = Widgets

local CHECK_HEIGHT, BUTTON_HEIGHT, TAB_HEIGHT = 26, 30, 24
local DISABLED_ALPHA = 0.4
local MENU_ROWS, MENU_ROW_HEIGHT = 12, 20
local GRID_ROW, GRID_ROW_GAP, GRID_COLUMN_GAP, GRID_PADDING = 36, 4, 10, 12
local CHECKBOX_SIZE = 16
local GRID_TAB_HEIGHT = 28

--- Bulles d'aide déjà vues (posé par Options : NS.global.tipsSeen).
Widgets.TipSeen = function() return false end
Widgets.MarkTipSeen = function() end
--- Mode simple de la fenêtre d'options (posé par Options : NS.global.optionsMode).
Widgets.SimpleMode = function() return false end

local counter = 0
local function NextName()
    counter = counter + 1
    return "AeonUIWidget" .. counter
end

--- Largeur du texte d'un bouton (estimée si le client ne la donne pas).
local function TextWidth(button, text)
    local fontString = button.GetFontString and button:GetFontString()
    -- Largeur non bornée : une fois le texte borné par FitText, GetStringWidth rend la largeur tronquée.
    local measure = fontString and (fontString.GetUnboundedStringWidth or fontString.GetStringWidth)
    local width = measure and measure(fontString)
    return width or #tostring(text or "") * 7
end

--- Garde le texte d'un bouton à l'intérieur. Avec minWidth : largeur portée à celle du texte
-- (+ marges), au moins minWidth. Puis texte borné aux marges (droite : button.fitRight, 8 par
-- défaut), sur une ligne, tronqué « … » par le client s'il reste trop long.
function Widgets.FitText(button, minWidth)
    if minWidth then button:SetWidth(math.max(minWidth, TextWidth(button, button:GetText()) + 24)) end
    local fontString = button.GetFontString and button:GetFontString()
    if not fontString then return end
    fontString:ClearAllPoints()
    fontString:SetPoint("LEFT", button, "LEFT", 8, 0)
    fontString:SetPoint("RIGHT", button, "RIGHT", -(button.fitRight or 8), 0)
    if fontString.SetWordWrap then fontString:SetWordWrap(false) end
end

--- Poignée en bas à droite : la fenêtre se tire en largeur et en hauteur, dans les bornes données.
-- ponytail: les pages gardent leur largeur de construction ; élargir laisse de la place à droite.
function Widgets.AddResizeGrip(frame, minWidth, minHeight, maxWidth, maxHeight)
    if frame.SetResizable then frame:SetResizable(true) end
    if frame.SetResizeBounds then
        frame:SetResizeBounds(minWidth, minHeight, maxWidth, maxHeight)
    elseif frame.SetMinResize then
        frame:SetMinResize(minWidth, minHeight)
        frame:SetMaxResize(maxWidth, maxHeight)
    end
    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
    grip:SetFrameLevel(frame:GetFrameLevel() + 10)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    if grip.SetHighlightTexture then grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight") end
    if grip.SetPushedTexture then grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down") end
    grip:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function() frame:StopMovingOrSizing() end)
    return grip
end

--- Grise ou rend un widget (et les textes qu'il porte : SetAlpha agit sur ses régions).
local function SetWidgetEnabled(frame, enabled)
    if frame.Enable and frame.Disable then
        if enabled then frame:Enable() else frame:Disable() end
    end
    if frame.IsObjectType and frame:IsObjectType("EditBox") then
        frame:EnableMouse(enabled)
        if not enabled then frame:ClearFocus() end
    end
    frame:SetAlpha(enabled and 1 or DISABLED_ALPHA)
end
Widgets.SetEnabled = SetWidgetEnabled

local function ShowTooltip(owner, text)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(text, 1, 1, 1, 1, true)
    GameTooltip:Show()
end
Widgets.ShowTooltip = ShowTooltip

--------------------------------------------------------------------------------
-- Éléments plats : couleur d'accent repeinte au changement de thème.
--------------------------------------------------------------------------------

local accented = setmetatable({}, { __mode = "k" })   -- [objet] = fonction qui le repeint

--- Inscrit `paint` (repeint l'objet à l'accent courant) et l'appelle une première fois.
function Widgets.Accented(object, paint)
    accented[object] = paint
    paint()
end

NS:On("THEME_CHANGED", function()
    for _, paint in pairs(accented) do paint() end
end)

--- Bouton plat : fond sombre, liseré (accent pour `primary`), texte centré.
-- `template` : modèle en plus (InsecureActionButtonTemplate pour /reload).
function Widgets.FlatButton(parent, text, width, height, primary, template)
    local button = CreateFrame("Button", NextName(), parent, template)
    button:SetSize(width or 140, height or 26)
    local edge = button:CreateTexture(nil, "BACKGROUND", nil, -1)
    edge:SetPoint("TOPLEFT", button, "TOPLEFT", -1, 1)
    edge:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 1, -1)
    local fill = button:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints()
    NS.SetSolidColor(fill, 0.09, 0.1, 0.12, 0.95)
    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    NS.SetSolidColor(highlight, 1, 1, 1, 0.06)
    Widgets.Accented(button, function()
        if primary then
            local r, g, b = NS.Media:Accent()
            NS.SetSolidColor(edge, r, g, b, 0.9)
        else
            NS.SetSolidColor(edge, 0.24, 0.26, 0.3, 1)
        end
    end)
    local label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("CENTER")
    button:SetFontString(label)
    button:SetText(text or "")
    return button
end

--- Case carrée : cadre fin, pleine d'accent avec une coche blanche quand elle est cochée.
local function CheckBox(parent, size)
    size = size or CHECKBOX_SIZE
    local box = CreateFrame("CheckButton", NextName(), parent)
    box:SetSize(size, size)
    local border = box:CreateTexture(nil, "BACKGROUND", nil, -1)
    border:SetAllPoints()
    local fill = box:CreateTexture(nil, "BACKGROUND")
    fill:SetPoint("TOPLEFT", box, "TOPLEFT", 1, -1)
    fill:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -1, 1)
    local check = box:CreateTexture(nil, "ARTWORK")
    check:SetPoint("TOPLEFT", box, "TOPLEFT", -3, 3)
    check:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 3, -3)
    check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    if check.SetDesaturated then check:SetDesaturated(true) end
    check:SetVertexColor(1, 1, 1, 1)
    function box.Paint()
        local r, g, b = NS.Media:Accent()
        if box:GetChecked() then
            NS.SetSolidColor(border, r, g, b, 1)
            NS.SetSolidColor(fill, r, g, b, 0.85)
        else
            NS.SetSolidColor(border, 0.4, 0.42, 0.46, 1)
            NS.SetSolidColor(fill, 0.08, 0.08, 0.1, 1)
        end
        check:SetShown(box:GetChecked() == true)
    end
    local setChecked = box.SetChecked
    box.SetChecked = function(self, value)
        setChecked(self, value)
        self.Paint()
    end
    Widgets.Accented(box, box.Paint)
    return box
end
Widgets.CheckBox = CheckBox

--- Onglet souligné : texte seul, le choisi porte un trait d'accent sous son libellé.
local function TabButton(parent, label, fontObject)
    local button = CreateFrame("Button", NextName(), parent)
    local line = button:CreateTexture(nil, "ARTWORK")
    line:SetHeight(2)
    line:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 6, 0)
    line:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -6, 0)
    local text = button:CreateFontString(nil, "OVERLAY", fontObject or "GameFontHighlightSmall")
    text:SetPoint("CENTER", button, "CENTER", 0, 1)
    button:SetFontString(text)
    button:SetText(label)
    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    NS.SetSolidColor(highlight, 1, 1, 1, 0.04)
    function button.SetSelected(selected)
        button.selected = selected
        local r, g, b = NS.Media:Accent()
        NS.SetSolidColor(line, r, g, b, 1)
        line:SetShown(selected == true)
        if selected then text:SetTextColor(1, 1, 1) else text:SetTextColor(0.6, 0.62, 0.66) end
    end
    Widgets.Accented(button, function() button.SetSelected(button.selected) end)
    return button
end
Widgets.TabButton = TabButton

--------------------------------------------------------------------------------
-- Bulle d'aide : montrée une fois (clé retenue), fermée par le premier clic, où qu'il soit.
--------------------------------------------------------------------------------

local tip

local function DismissTip()
    if not (tip and tip:IsShown()) then return end
    Widgets.MarkTipSeen(tip.key)
    tip:Hide()
end
Widgets.DismissTip = DismissTip

--- Montre la bulle `key` sous `anchor` si elle n'a jamais été vue. Une seule à la fois.
function Widgets.Tip(anchor, key, text)
    if Widgets.TipSeen(key) or (tip and tip:IsShown()) then return end
    if not tip then
        tip = CreateFrame("Frame", "AeonUITip", UIParent)
        tip:SetFrameStrata("FULLSCREEN_DIALOG")
        tip:SetSize(240, 60)
        NS.Media:CreateBackdrop(tip)
        local bar = tip:CreateTexture(nil, "ARTWORK")
        bar:SetWidth(3)
        bar:SetPoint("TOPLEFT")
        bar:SetPoint("BOTTOMLEFT")
        Widgets.Accented(bar, function()
            local r, g, b = NS.Media:Accent()
            NS.SetSolidColor(bar, r, g, b, 1)
        end)
        tip.text = tip:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        tip.text:SetPoint("TOPLEFT", tip, "TOPLEFT", 14, -10)
        tip.text:SetPoint("TOPRIGHT", tip, "TOPRIGHT", -10, -10)
        tip.text:SetJustifyH("LEFT")
        -- Premier clic de souris n'importe où : la bulle est lue.
        pcall(tip.RegisterEvent, tip, "GLOBAL_MOUSE_DOWN")
        tip:SetScript("OnEvent", DismissTip)
    end
    tip.key = key
    tip.text:SetText(text)
    tip:SetHeight((tip.text:GetStringHeight() or 24) + 20)
    tip:SetScale((anchor:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1))
    tip:ClearAllPoints()
    tip:SetPoint("TOP", anchor, "BOTTOM", 0, -6)
    tip:Show()
    return tip
end

function Widgets.HideTip() if tip then tip:Hide() end end
function Widgets.GetTip() return tip end

--------------------------------------------------------------------------------
-- Liste déroulante : un menu partagé, ouvert sous le bouton qui l'appelle.
--------------------------------------------------------------------------------

local menu

local function PaintMenu()
    local r, g, b = NS.Media:Accent()
    local shown = 0
    for i, row in ipairs(menu.rows) do
        local choice = menu.choices[menu.offset + i]
        if choice then
            shown = i
            row.value = choice.value
            row.text:SetFontObject("GameFontHighlight")
            -- Aperçu : la police dans sa propre police, la texture de barre en fond de ligne.
            if choice.font then row.text:SetFont(choice.font, 13, "") end
            row.text:SetText(choice.name)
            if choice.value == menu.current then row.text:SetTextColor(r, g, b) else row.text:SetTextColor(1, 1, 1) end
            if choice.texture then
                row.preview:SetTexture(choice.texture)
                row.preview:SetVertexColor(r, g, b, 0.6)
                row.preview:Show()
            else
                row.preview:Hide()
            end
            row:Show()
        else
            row:Hide()
        end
    end
    menu:SetHeight(math.max(1, shown) * MENU_ROW_HEIGHT + 8)
    menu.more:SetShown(#menu.choices > MENU_ROWS)
end

local function BuildMenu()
    menu = CreateFrame("Frame", "AeonUIDropdownMenu", UIParent)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetClampedToScreen(true)
    menu:EnableMouse(true)
    menu:EnableMouseWheel(true)
    NS.Media:CreateBackdrop(menu)
    -- Clic hors du menu : un voile plein écran, juste dessous, le ferme.
    menu.blocker = CreateFrame("Button", nil, UIParent)
    menu.blocker:SetAllPoints(UIParent)
    menu.blocker:SetFrameStrata("FULLSCREEN")
    menu.blocker:SetScript("OnClick", function() menu:Hide() end)
    menu.blocker:Hide()
    menu:SetScript("OnHide", function() menu.blocker:Hide() end)
    menu.rows = {}
    for i = 1, MENU_ROWS do
        local row = CreateFrame("Button", nil, menu)
        row:SetHeight(MENU_ROW_HEIGHT)
        row:SetPoint("TOPLEFT", menu, "TOPLEFT", 4, -4 - (i - 1) * MENU_ROW_HEIGHT)
        row:SetPoint("RIGHT", menu, "RIGHT", -4, 0)
        row.preview = row:CreateTexture(nil, "BACKGROUND")
        row.preview:SetAllPoints()
        local highlight = row:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        NS.SetSolidColor(highlight, 1, 1, 1, 0.15)
        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.text:SetPoint("LEFT", row, "LEFT", 6, 0)
        row.text:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        row.text:SetJustifyH("LEFT")
        row:SetScript("OnClick", function(self)
            local pick = menu.onPick
            menu:Hide()
            pick(self.value)
        end)
        menu.rows[i] = row
    end
    -- Plus de choix que de lignes : la molette fait défiler, un repère le signale.
    menu.more = menu:CreateTexture(nil, "OVERLAY")
    menu.more:SetSize(16, 16)
    menu.more:SetPoint("BOTTOMRIGHT", menu, "BOTTOMRIGHT", -2, 0)
    menu.more:SetTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up")
    menu:SetScript("OnMouseWheel", function(_, delta)
        local last = math.max(0, #menu.choices - MENU_ROWS)
        menu.offset = math.min(last, math.max(0, menu.offset - delta))
        PaintMenu()
    end)
    menu:Hide()
end

--- Ouvre le menu sous `owner` ; un second clic sur le même bouton le ferme.
function Widgets.OpenMenu(owner, choices, current, onPick)
    if not menu then BuildMenu() end
    if menu:IsShown() and menu.owner == owner then menu:Hide() return end
    menu.owner, menu.choices, menu.current, menu.onPick = owner, choices, current, onPick
    -- Choix actuel visible dès l'ouverture.
    local index = 1
    for i, choice in ipairs(choices) do if choice.value == current then index = i end end
    menu.offset = math.min(math.max(0, #choices - MENU_ROWS), math.max(0, index - math.floor(MENU_ROWS / 2)))
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
    menu:SetWidth(math.max(160, owner:GetWidth() or 0))
    -- Même taille que la fenêtre qui l'ouvre (le menu est enfant d'UIParent).
    menu:SetScale((owner:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1))
    PaintMenu()
    menu.blocker:Show()
    menu:Show()
    if menu.Raise then menu:Raise() end
end

function Widgets.CloseMenu()
    if menu then menu:Hide() end
end

function Widgets.GetMenu() return menu end

--- Bouton « Libellé : choix » qui ouvre la liste. choices = { {name=, value=, font=?, texture=?} }
-- ou une fonction qui la rend (liste qui change : profils, polices). Rend le bouton ; Paint le repeint.
-- `flat` : bouton plat ; sans `label`, le bouton ne montre que le choix (libellé posé à côté).
function Widgets.Dropdown(parent, width, label, choices, get, set, flat)
    local button
    if flat then
        button = Widgets.FlatButton(parent, "", width, 24)
    else
        button = CreateFrame("Button", NextName(), parent, "UIPanelButtonTemplate")
        button:SetSize(width, 24)
    end
    local arrow = button:CreateTexture(nil, "OVERLAY")
    arrow:SetSize(20, 20)
    arrow:SetPoint("RIGHT", button, "RIGHT", -2, 0)
    arrow:SetTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up")
    button.fitRight = 24   -- la flèche
    local function list() return type(choices) == "function" and choices() or choices end
    local prefix = label and (label .. " : ") or ""
    function button.Paint()
        local value, text = get(), nil
        for _, choice in ipairs(list()) do
            if choice.value == value then text = prefix .. choice.name break end
        end
        if not text and value ~= nil then text = prefix .. tostring(value) end
        button:SetText(text or label or "")
    end
    button:SetScript("OnClick", function(self)
        Widgets.OpenMenu(self, list(), get(), function(value)
            set(value)
            self.Paint()
        end)
    end)
    button.Paint()
    Widgets.FitText(button)
    return button
end

--------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------

local Layout = {}
Layout.__index = Layout

--- parent : frame qui reçoit les widgets. x : marge gauche. width : largeur utile.
-- opts.grid : mise en page en grille (voir en tête) ; opts.tabHost : cadre qui reçoit la barre
-- d'onglets (en-tête fixe de la page) au lieu de la page elle-même.
function Widgets.NewLayout(parent, x, width, opts)
    opts = opts or {}
    local layout = setmetatable({ root = parent, parent = parent, x = x or 16, y = -16, width = width or 560,
                                  refreshers = {}, refreshing = false, labels = {},
                                  parents = {}, dependents = {} }, Layout)
    if opts.grid then
        layout.grid, layout.tabHost = true, opts.tabHost
        layout.rootItems, layout.groups, layout.pendingSpace = {}, {}, 0
        layout.items = layout.rootItems
    end
    return layout
end

--- Libellé posé sur la page, gardé pour la recherche : { text, frame, tab }.
function Layout:Label(text, frame)
    if type(text) == "string" then
        self.labels[#self.labels + 1] = { text = text, frame = frame, tab = self.currentTab }
    end
end

--------------------------------------------------------------------------------
-- Grille : éléments inscrits dans l'ordre, placés par Reflow.
--------------------------------------------------------------------------------

--- Largeur d'une colonne de la grille.
function Layout:ColumnWidth() return (self.width - GRID_COLUMN_GAP) / 2 end

--- Inscrit `frame` : span "half" (ligne de réglage, deux par rangée), "inline" (boutons côte à
-- côte) ou "full" (toute la largeur).
function Layout:GridAdd(frame, span, height, indent, width)
    local item = { frame = frame, span = span, height = height, indent = indent or 0, width = width,
                   before = self.pendingSpace, group = self.advancedGroup }
    self.pendingSpace = 0
    if item.group and span == "half" then item.group.count = item.group.count + 1 end
    -- Réglage courant posé après un groupe avancé refermé (Visibility) : remonté au-dessus de
    -- l'intertitre, les avancés restent en fin de bloc.
    if self.advancedAt and not self.advancedGroup then
        table.insert(self.items, self.advancedAt, item)
        self.advancedAt = self.advancedAt + 1
    else
        self.items[#self.items + 1] = item
    end
    self.last = frame
    return item
end

--- Éléments affichés : en mode simple, les réglages avancés sont masqués, et le bloc entier
-- (titre, cadre) quand il n'a que ceux-là.
local function ShownItems(items)
    local simple, hidden = Widgets.SimpleMode(), {}
    for i, item in ipairs(items) do hidden[i] = simple and item.group ~= nil end
    if simple then
        for i, item in ipairs(items) do
            if item.card then
                local advanced, common = false, false
                for j = i + 1, #items do
                    if items[j].card then break end
                    if hidden[j] then advanced = true else common = true end
                end
                hidden[i] = advanced and not common
            end
        end
    end
    local shown = {}
    for i, item in ipairs(items) do
        if hidden[i] then
            item.frame:Hide()
            item.frame.modeHidden = true
        elseif item.frame.modeHidden then
            item.frame:Show()
            item.frame.modeHidden = nil
        end
        for _, region in ipairs(item.regions or {}) do region:SetShown(not hidden[i]) end
        if not hidden[i] then shown[#shown + 1] = item end
    end
    return shown
end

--- Place les éléments de `items` dans `parent` à partir de `top` ; rend le bas atteint.
local function Flow(layout, parent, items, top)
    local y, column, inline = top, 0, nil
    local columnWidth = layout:ColumnWidth()
    local function closeRow()
        if column == 1 then y, column = y - GRID_ROW - GRID_ROW_GAP, 0 end
    end
    -- Bloc d'une section : du titre jusqu'à la section suivante (ou la fin).
    local card, cardTop
    local function closeCard()
        if not card then return end
        closeRow()
        y = y - 8
        card(parent, cardTop, y)
        card = nil
        y = y - 4
    end
    for _, item in ipairs(ShownItems(items)) do
        if item.card then
            closeCard()
            closeRow()
            inline = nil
            y = y - item.before
            card, cardTop = item.card, y
            y = y - 8
        end
        local frame = item.frame
        frame:ClearAllPoints()
        if item.span == "half" then
            inline = nil
            if column == 0 then y = y - item.before end
            local x = layout.x + (column == 1 and (columnWidth + GRID_COLUMN_GAP) or 0)
            frame:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
            frame.layoutY = y
            if column == 1 then y, column = y - GRID_ROW - GRID_ROW_GAP, 0 else column = 1 end
        elseif item.span == "inline" then
            closeRow()
            if inline and inline.indent == item.indent and inline.x + item.width <= layout.x + layout.width + 1 then
                frame:SetPoint("TOPLEFT", parent, "TOPLEFT", inline.x, inline.y)
                frame.layoutY = inline.y
                inline.x = inline.x + item.width
            else
                y = y - item.before
                local left = layout.x + item.indent
                frame:SetPoint("TOPLEFT", parent, "TOPLEFT", left, y)
                frame.layoutY = y
                inline = { x = left + item.width, y = y, indent = item.indent }
                y = y - item.height
            end
        else
            closeRow()
            inline = nil
            if not item.card then y = y - item.before end   -- carte : espace déjà pris au-dessus
            frame:SetPoint("TOPLEFT", parent, "TOPLEFT", layout.x + item.indent, y)
            frame.layoutY = y
            y = y - item.height
        end
    end
    closeRow()
    closeCard()
    return y
end

--- Recalcule les positions (fin de page).
function Layout:Reflow()
    self.commonBottom = Flow(self, self.root, self.rootItems, -12)
    for _, tab in ipairs(self.tabs or {}) do
        tab.section:ClearAllPoints()
        tab.section:SetPoint("TOPLEFT", self.root, "TOPLEFT", 0, self.commonBottom - 4)
        tab.height = -Flow(self, tab.section, tab.items, 0)
        tab.section:SetHeight(math.max(1, tab.height))
    end
    for _, group in ipairs(self.groups) do group.Paint() end
    self.root:SetHeight(self:Height())
end

--- Réglages moins courants, jusqu'au prochain titre ou onglet : affichés en fin de bloc, sous un
-- intertitre discret (`label` : format avec leur nombre), libellés atténués. Second appel dans le
-- même bloc (après EndAdvanced) : les réglages rejoignent le même intertitre.
-- Sans grille : sans effet (les réglages restent affichés).
function Layout:Advanced(label)
    if not self.grid then return end
    if self.advancedAt and self.blockAdvanced then
        self.advancedGroup = self.blockAdvanced
        return self.advancedGroup
    end
    local text = self.parent:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    local group = { count = 0 }
    function group.Paint() text:SetText(string.format(label, group.count)) end
    self.advancedGroup, self.advancedAt = nil, nil
    self:GridAdd(text, "full", 20, GRID_PADDING).group = group
    self.advancedAt = #self.items   -- place de l'intertitre dans le bloc
    self.groups[#self.groups + 1] = group
    self.advancedGroup, self.blockAdvanced = group, group
    return group
end

--- Fin des réglages avancés du bloc : les suivants redeviennent courants (placés avant l'intertitre).
function Layout:EndAdvanced() self.advancedGroup = nil end

--- Ligne de réglage de la grille : fond discret ; le libellé, porté par le contrôle, est grisé avec lui.
-- `build(row)` crée le contrôle dans la ligne et rend (contrôle, largeur occupée à droite).
function Layout:GridRow(label, indent, build)
    local row = CreateFrame("Frame", nil, self.parent)
    row:SetSize(self:ColumnWidth(), GRID_ROW)
    local separator = row:CreateTexture(nil, "BACKGROUND")
    separator:SetHeight(1)
    separator:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", GRID_PADDING, -GRID_ROW_GAP / 2)
    separator:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -GRID_PADDING, -GRID_ROW_GAP / 2)
    NS.SetSolidColor(separator, 1, 1, 1, 0.05)
    local control, controlWidth = build(row)
    local text = control:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    -- Retrait = dépendance : un léger décalage du libellé la montre.
    local shift = (indent or 0) > 20 and 10 or 0
    text:SetPoint("LEFT", row, "LEFT", GRID_PADDING + shift, 0)
    text:SetPoint("RIGHT", row, "RIGHT", -(GRID_PADDING + controlWidth + 8), 0)
    text:SetJustifyH("LEFT")
    if text.SetWordWrap then text:SetWordWrap(true) end
    if text.SetMaxLines then text:SetMaxLines(2) end
    text:SetText(label)
    if self.advancedGroup then text:SetTextColor(0.66, 0.68, 0.72) end
    control.gridRow, control.gridLabel = row, text
    -- Infobulle au survol de la ligne entière, libellé complet en tête (il peut être tronqué).
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(owner)
        if control.hint then ShowTooltip(owner, label .. "\n|cffcccccc" .. control.hint .. "|r")
        else ShowTooltip(owner, label) end
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self:GridAdd(row, "half", GRID_ROW, indent)
    self.last = control
    return control, row
end

--- Section de la grille : bloc encadré d'un liseré fin, titre dans une bande en tête.
function Layout:GridSection(fs)
    local SECTION_INSET, BAND_HEIGHT = 6, 30
    local function Region(layer, sublevel, alpha)
        local texture = self.parent:CreateTexture(nil, layer, nil, sublevel)
        NS.SetSolidColor(texture, 1, 1, 1, alpha)
        return texture
    end
    local fill, band = Region("BACKGROUND", -8, 0.02), Region("BACKGROUND", -7, 0.04)
    local top, bottom, left, right, under = Region("BORDER", 0, 0.1), Region("BORDER", 0, 0.1),
        Region("BORDER", 0, 0.1), Region("BORDER", 0, 0.1), Region("BORDER", 0, 0.1)
    Widgets.Accented(fs, function()
        local r, g, b = NS.Media:Accent()
        fs:SetTextColor(r, g, b)
    end)
    local item = self:GridAdd(fs, "full", 26, GRID_PADDING)
    item.regions = { fill, band, top, bottom, left, right, under }
    -- Posé par Flow une fois le bas du bloc connu.
    item.card = function(parent, y, bottomY)
        local x, width, height = self.x - SECTION_INSET, self.width + 2 * SECTION_INSET, y - bottomY
        local function Put(region, dx, dy, w, h)
            region:ClearAllPoints()
            region:SetPoint("TOPLEFT", parent, "TOPLEFT", x + dx, y - dy)
            region:SetSize(w, h)
        end
        Put(fill, 0, 0, width, height)
        Put(band, 0, 0, width, BAND_HEIGHT)
        Put(top, 0, 0, width, 1)
        Put(under, 0, BAND_HEIGHT, width, 1)
        Put(bottom, 0, height - 1, width, 1)
        Put(left, 0, 0, 1, height)
        Put(right, width - 1, 0, 1, height)
    end
    return fs
end

--- Début d'un widget au retrait `indent` : rend ses conditions (getters des cases dont il dépend).
-- Une case en seconde colonne dont dépend ce widget repasse seule sur sa ligne, au-dessus de lui.
function Layout:Advance(indent)
    indent = indent or 0
    local row = self.row
    if not self.grid and row and row.kind == "check" and #row.frames > 1 and indent > row.indent then
        local last = row.frames[#row.frames]
        last:ClearAllPoints()
        last:SetPoint("TOPLEFT", self.parent, "TOPLEFT", row.left, self.y)
        last.layoutY = self.y
        self.y = self.y - CHECK_HEIGHT
        self.row = nil
    end
    local parents = self:PopParents(indent)
    if #parents == 0 then return nil end
    local conditions = {}
    for i, parent in ipairs(parents) do conditions[i] = parent.get end
    return conditions
end

--- Oublie les cases de retrait >= `indent` : elles ne commandent plus les widgets suivants.
function Layout:PopParents(indent)
    local parents = self.parents
    while #parents > 0 and parents[#parents].indent >= indent do parents[#parents] = nil end
    return parents
end

--- Inscrit un widget grisé tant qu'une de ses conditions est fausse.
function Layout:Bind(frame, conditions)
    self.last = frame
    if conditions then self.dependents[#self.dependents + 1] = { frame = frame, conditions = conditions } end
end

function Layout:UpdateDependencies()
    for _, dependent in ipairs(self.dependents) do
        local enabled = true
        for _, get in ipairs(dependent.conditions) do
            if not get() then enabled = false break end
        end
        SetWidgetEnabled(dependent.frame, enabled)
    end
end

--- Pose `frame` au début d'une nouvelle ligne.
function Layout:Place(frame, height, indent)
    if self.grid then return self:GridAdd(frame, "full", height, indent) end
    self.row = nil
    frame:SetPoint("TOPLEFT", self.parent, "TOPLEFT", self.x + (indent or 0), self.y)
    frame.layoutY = self.y
    self.y = self.y - height
end

--- Pose `frame` à droite du widget précédent de même type et même retrait s'il reste la place,
-- sinon au début d'une nouvelle ligne. `width` : place occupée ; `offset` : décalage de pose.
function Layout:PlaceInRow(frame, kind, width, height, indent, offset)
    if self.grid then return self:GridAdd(frame, "inline", height, offset, width) end
    local row = self.row
    if row and row.kind == kind and row.indent == indent and row.nextX + width <= self.x + self.width + 1 then
        frame:SetPoint("TOPLEFT", self.parent, "TOPLEFT", row.nextX, row.y)
        frame.layoutY = row.y
        row.nextX = row.nextX + width
        row.frames[#row.frames + 1] = frame
        return
    end
    local left = self.x + offset
    self:Place(frame, height, offset)
    self.row = { kind = kind, indent = indent, y = frame.layoutY, left = left, nextX = left + width, frames = { frame } }
end

function Layout:Space(height)
    if self.grid then self.pendingSpace = self.pendingSpace + (height or 8) return end
    self.row = nil
    self.y = self.y - (height or 8)
end

function Layout:Refresh()
    self.refreshing = true
    local ok, err = pcall(function()
        for i = 1, #self.refreshers do self.refreshers[i]() end
        self:UpdateDependencies()
    end)
    self.refreshing = false   -- même après une erreur : sinon la page ne sauvegarde plus rien
    if not ok then error(err, 0) end
end

--- Explication au survol du dernier widget posé : la page reste courte, le libellé reste en texte.
function Layout:Hint(text)
    local frame = self.last
    if not frame or not text then return end
    -- Grille : l'infobulle de la ligne ajoute l'explication sous le libellé.
    if frame.gridRow then frame.hint = text return end
    -- Case grisée (module cédé) : l'infobulle reste lisible.
    if frame.SetMotionScriptsWhileDisabled then frame:SetMotionScriptsWhileDisabled(true) end
    frame:HookScript("OnEnter", function(owner) ShowTooltip(owner, text) end)
    frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

function Layout:Header(text)
    self:PopParents(0)   -- garde la case du module (retrait -1)
    self.advancedGroup, self.advancedAt = nil, nil
    local fs = self.parent:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
    fs:SetText(text)
    self:Place(fs, 34)
    return fs
end

--- Titre de section. Coupe les dépendances en retrait, garde les cases de premier niveau
-- (« Activer » d'un module grise toute sa page).
function Layout:Title(text)
    self:PopParents(1)
    self.advancedGroup, self.advancedAt = nil, nil
    self:Space(self.grid and 12 or 10)
    local fs = self.parent:CreateFontString(nil, "ARTWORK", self.grid and "GameFontNormal" or "GameFontNormalLarge")
    fs:SetText(text)
    self:Label(text, fs)   -- une section se vise aussi (aperçu, recherche)
    if self.grid then return self:GridSection(fs) end
    self:Place(fs, 24)
    local line = self.parent:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetWidth(self.width)
    local alpha = self.grid and 0.25 or 0.6
    Widgets.Accented(line, function()
        local r, g, b = NS.Media:Accent()
        NS.SetSolidColor(line, r, g, b, alpha)
    end)
    self:Place(line, 8)
    return fs
end

--- Phrase d'explication (le user veut des libellés textuels, pas des icônes seules).
function Layout:Note(text, indent)
    local conditions = self:Advance(indent)
    local fs = self.parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    fs:SetWidth(self.width - (indent or 0))
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    fs:SetTextColor(0.75, 0.75, 0.75)
    self:Place(fs, (fs:GetStringHeight() or 12) + 8, indent)
    self:Bind(fs, conditions)
    return fs
end

--- Case (grille : case à droite de la ligne, libellé cliquable lui aussi).
function Layout:GridCheck(label, get, set, indent, conditions)
    local cb, row = self:GridRow(label, indent, function(row)
        local box = CheckBox(row)
        box:SetPoint("RIGHT", row, "RIGHT", -GRID_PADDING, 0)
        return box, CHECKBOX_SIZE
    end)
    if cb.SetHitRectInsets then cb:SetHitRectInsets(-(self:ColumnWidth() - CHECKBOX_SIZE - GRID_PADDING * 2), 0, -8, -8) end
    if cb.SetMotionScriptsWhileDisabled then cb:SetMotionScriptsWhileDisabled(true) end
    cb:SetScript("OnEnter", function() row:GetScript("OnEnter")(row) end)
    cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    cb:SetScript("OnClick", function(button)
        if self.refreshing then return end
        set(button:GetChecked() and true or false)
        button.Paint()
        self:UpdateDependencies()
    end)
    self.refreshers[#self.refreshers + 1] = function() cb:SetChecked(get() and true or false) end
    self:Bind(cb, conditions)
    self.parents[#self.parents + 1] = { indent = indent, get = get }
    self:Label(label, cb)
    return cb
end

function Layout:Check(label, get, set, indent)
    indent = indent or 0
    local conditions = self:Advance(indent)
    if self.grid then return self:GridCheck(label, get, set, indent, conditions) end
    local cb = CreateFrame("CheckButton", NextName(), self.parent, "UICheckButtonTemplate")
    local text = _G[cb:GetName() .. "Text"] or cb.Text or cb.text
    if not text then
        text = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    end
    text:SetText(label)
    text:SetFontObject("GameFontHighlight")
    local labelWidth = text:GetStringWidth() or 0
    -- Le libellé est cliquable lui aussi.
    if cb.SetHitRectInsets then cb:SetHitRectInsets(0, -(labelWidth + 4), 0, 0) end
    cb:SetScript("OnClick", function(button)
        if self.refreshing then return end
        set(button:GetChecked() and true or false)
        self:UpdateDependencies()
    end)
    self.refreshers[#self.refreshers + 1] = function() cb:SetChecked(get() and true or false) end
    local column = (self.width - indent) / 2
    local width = labelWidth + 34 <= column and column or (self.width - indent)
    self:PlaceInRow(cb, "check", width, CHECK_HEIGHT, indent, indent - 4)
    self:Bind(cb, conditions)
    self.parents[#self.parents + 1] = { indent = indent, get = get }
    self:Label(label, cb)
    return cb
end

--- Valeur d'un curseur dans sa case de saisie : nombre nu, sans unité ni bruit flottant.
local function PlainNumber(value) return string.format("%g", tonumber(value) or 0) end

--- Curseur de la grille : glissière plate et case de saisie à droite de la ligne.
function Layout:GridSlider(label, minValue, maxValue, step, get, set, indent, format, conditions)
    local box
    local s = self:GridRow(label, indent, function(row)
        local slider = CreateFrame("Slider", NextName(), row)
        slider:SetOrientation("HORIZONTAL")
        slider:SetSize(90, 16)
        slider:EnableMouse(true)
        local track = slider:CreateTexture(nil, "BACKGROUND")
        track:SetHeight(4)
        track:SetPoint("LEFT", slider, "LEFT", 0, 0)
        track:SetPoint("RIGHT", slider, "RIGHT", 0, 0)
        NS.SetSolidColor(track, 0.24, 0.25, 0.28, 1)
        local thumb = slider:CreateTexture(nil, "ARTWORK")
        thumb:SetSize(10, 16)
        Widgets.Accented(thumb, function()
            local r, g, b = NS.Media:Accent()
            NS.SetSolidColor(thumb, r, g, b, 1)
        end)
        slider:SetThumbTexture(thumb)
        box = CreateFrame("EditBox", NextName(), slider)
        box:SetSize(42, 20)
        box:SetAutoFocus(false)
        box:SetFontObject("GameFontHighlightSmall")
        box:SetJustifyH("CENTER")
        local boxBackground = box:CreateTexture(nil, "BACKGROUND")
        boxBackground:SetAllPoints()
        NS.SetSolidColor(boxBackground, 0, 0, 0, 0.5)
        box:SetPoint("RIGHT", row, "RIGHT", -GRID_PADDING, 0)
        slider:SetPoint("RIGHT", box, "LEFT", -8, 0)
        return slider, 140
    end)
    s:SetMinMaxValues(minValue, maxValue)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    local function paint(value)
        if not (box.HasFocus and box:HasFocus()) then
            box:SetText(format and string.format(format, value) or PlainNumber(value))
        end
    end
    s:SetScript("OnValueChanged", function(_, value)
        value = math.floor(value / step + 0.5) * step
        paint(value)
        if not self.refreshing then set(value) end
    end)
    box:SetScript("OnEnterPressed", function(edit)
        -- La case montre la valeur avec son unité (« 20 s ») : seul le nombre compte.
        local typed = tonumber((((edit:GetText() or ""):gsub(",", ".")):match("[-+]?%d*%.?%d+")))
        edit:ClearFocus()
        if typed and typed == typed then s:SetValue(math.min(maxValue, math.max(minValue, typed))) end
        paint(get())
    end)
    box:SetScript("OnEscapePressed", function(edit) edit:ClearFocus() paint(get()) end)
    self.refreshers[#self.refreshers + 1] = function() s:SetValue(get()); paint(get()) end
    s.valueBox = box
    self:Bind(s, conditions)
    if conditions then self.dependents[#self.dependents + 1] = { frame = box, conditions = conditions } end
    self:Label(label, s)
    return s
end

function Layout:Slider(label, minValue, maxValue, step, get, set, indent, format)
    local conditions = self:Advance(indent)
    if self.grid then return self:GridSlider(label, minValue, maxValue, step, get, set, indent, format, conditions) end
    local s = CreateFrame("Slider", NextName(), self.parent, "OptionsSliderTemplate")
    s:SetWidth(240)
    s:SetMinMaxValues(minValue, maxValue)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    local low, high = _G[s:GetName() .. "Low"], _G[s:GetName() .. "High"]
    if low then low:SetText(minValue) end
    if high then high:SetText(maxValue) end
    local text = _G[s:GetName() .. "Text"]
    if not text then
        text = s:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        text:SetPoint("BOTTOM", s, "TOP", 0, 2)
    end
    -- Valeur exacte au clavier : Entrée applique, bornée et arrondie au pas.
    local box = CreateFrame("EditBox", NextName(), s, "InputBoxTemplate")
    box:SetSize(56, 20)
    box:SetAutoFocus(false)
    box:SetPoint("LEFT", s, "RIGHT", 14, 0)
    local function paint(value)
        text:SetText(label .. " : " .. string.format(format or "%s", value))
        if not (box.HasFocus and box:HasFocus()) then box:SetText(PlainNumber(value)) end
    end
    s:SetScript("OnValueChanged", function(_, value)
        value = math.floor(value / step + 0.5) * step
        paint(value)
        if not self.refreshing then set(value) end
    end)
    box:SetScript("OnEnterPressed", function(edit)
        local typed = tonumber(((edit:GetText() or ""):gsub(",", ".")))
        edit:ClearFocus()
        if typed and typed == typed then s:SetValue(math.min(maxValue, math.max(minValue, typed))) end
        paint(get())
    end)
    box:SetScript("OnEscapePressed", function(edit) edit:ClearFocus() paint(get()) end)
    -- SetValue ne déclenche rien si la valeur ne change pas : peindre explicitement.
    self.refreshers[#self.refreshers + 1] = function() s:SetValue(get()); paint(get()) end
    self:Space(16)
    self:Place(s, 40, (indent or 0) + 6)
    s.valueBox = box
    self:Bind(s, conditions)
    if conditions then self.dependents[#self.dependents + 1] = { frame = box, conditions = conditions } end
    self.last = s
    self:Label(label, s)
    return s
end

--- Liste déroulante « Libellé : choix ». Voir Widgets.Dropdown pour `choices`.
function Layout:Dropdown(label, choices, get, set, indent)
    local conditions = self:Advance(indent)
    if self.grid then
        local width = math.min(190, math.floor(self:ColumnWidth() * 0.48))
        local button = self:GridRow(label, indent, function(row)
            local dropdown = Widgets.Dropdown(row, width, nil, choices, get, function(value)
                if not self.refreshing then set(value) end
            end, true)
            dropdown:SetPoint("RIGHT", row, "RIGHT", -GRID_PADDING, 0)
            return dropdown, width
        end)
        self.refreshers[#self.refreshers + 1] = button.Paint
        self:Bind(button, conditions)
        self:Label(label, button)
        return button
    end
    local button = Widgets.Dropdown(self.parent, 300, label, choices, get, function(value)
        if not self.refreshing then set(value) end
    end)
    self.refreshers[#self.refreshers + 1] = button.Paint
    self:Place(button, 30, (indent or 0) + 4)
    self:Bind(button, conditions)
    self:Label(label, button)
    return button
end

function Layout:Color(label, color, onChange, indent)
    local conditions = self:Advance(indent)
    if self.grid then
        local swatch
        local b = self:GridRow(label, indent, function(row)
            local button = CreateFrame("Button", NextName(), row)
            button:SetSize(22, 22)
            local edge = button:CreateTexture(nil, "BACKGROUND")
            edge:SetAllPoints()
            NS.SetSolidColor(edge, 0.5, 0.5, 0.5, 1)
            swatch = button:CreateTexture(nil, "ARTWORK")
            swatch:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
            swatch:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
            button:SetPoint("RIGHT", row, "RIGHT", -GRID_PADDING, 0)
            return button, 22
        end)
        local function paint()
            local c = color()
            NS.SetSolidColor(swatch, c.r, c.g, c.b, 1)
        end
        b:SetScript("OnClick", function()
            NS.OpenColorPicker(color(), function()
                paint()
                onChange()
            end)
        end)
        self.refreshers[#self.refreshers + 1] = paint
        self:Bind(b, conditions)
        self:Label(label, b)
        return b
    end
    local b = CreateFrame("Button", NextName(), self.parent)
    b:SetSize(280, 24)
    local swatch = b:CreateTexture(nil, "ARTWORK")
    swatch:SetSize(20, 20)
    swatch:SetPoint("LEFT")
    local text = b:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    text:SetPoint("LEFT", swatch, "RIGHT", 8, 0)
    text:SetText(label)
    local function paint()
        local c = color()
        NS.SetSolidColor(swatch, c.r, c.g, c.b, 1)
    end
    b:SetScript("OnClick", function()
        NS.OpenColorPicker(color(), function()
            paint()
            onChange()
        end)
    end)
    self.refreshers[#self.refreshers + 1] = paint
    self:Place(b, 28, (indent or 0) + 4)
    self:Bind(b, conditions)
    self:Label(label, b)
    return b
end

--- `primary` (grille) : bouton mis en avant, liseré à l'accent.
function Layout:Button(label, onClick, indent, primary)
    indent = indent or 0
    local conditions = self:Advance(indent)
    local b = self.grid and Widgets.FlatButton(self.parent, label, 140, 26, primary)
        or CreateFrame("Button", NextName(), self.parent, "UIPanelButtonTemplate")
    b:SetText(label)
    local width = math.min(self.width - indent, math.max(140, TextWidth(b, label) + 32))
    b:SetSize(width, self.grid and 26 or 24)
    Widgets.FitText(b)
    b:SetScript("OnClick", onClick)
    self:PlaceInRow(b, "button", width + 8, BUTTON_HEIGHT, indent, indent + 4)
    self:Bind(b, conditions)
    self:Label(label, b)
    return b
end

--- Zone de texte pour copier/coller (chaîne de profil, disposition, note). `lines` = hauteur.
-- ponytail: pas de défilement ; une chaîne longue se copie quand même (SelectAll + Ctrl-C).
function Layout:EditBox(label, get, set, lines, indent)
    local conditions = self:Advance(indent)
    lines = lines or 1
    local text = self.parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    text:SetText(label)
    if self.grid and self.advancedGroup then
        text:SetTextColor(0.66, 0.68, 0.72)
        self.advancedGroup.count = self.advancedGroup.count + 1
    end
    self:Place(text, 16, indent)
    self:Bind(text, conditions)
    local width, height = self.width - (indent or 0) - 8, lines * 14 + 8
    -- Multi-lignes : dans un ScrollFrame, une chaîne exportée dépasse toujours la zone.
    local scroll
    if lines > 1 then
        scroll = CreateFrame("ScrollFrame", nil, self.parent)
        scroll:SetSize(width, height)
        scroll:EnableMouseWheel(true)
        scroll:EnableMouse(true)
    end
    local box = CreateFrame("EditBox", NextName(), scroll or self.parent)
    box:SetSize(width, height)
    box:SetMultiLine(lines > 1)
    box:SetAutoFocus(false)
    box:SetMaxLetters(0)
    box:SetFontObject("ChatFontNormal")
    box:SetTextInsets(4, 4, 4, 4)
    box.bg = (scroll or box):CreateTexture(nil, "BACKGROUND")
    box.bg:SetAllPoints()
    NS.SetSolidColor(box.bg, 0, 0, 0, 0.5)
    if scroll then
        scroll:SetScrollChild(box)
        scroll:SetScript("OnMouseWheel", function(s, delta)
            local range = s:GetVerticalScrollRange() or 0
            local value = s:GetVerticalScroll() - delta * 28
            if value < 0 then value = 0 elseif value > range then value = range end
            s:SetVerticalScroll(value)
        end)
        scroll:SetScript("OnMouseDown", function() box:SetFocus() end)
        -- Le curseur reste visible : suit la ligne éditée.
        box:SetScript("OnCursorChanged", function(_, _, y, _, h)
            local top, cur, visible = -y, scroll:GetVerticalScroll() or 0, scroll:GetHeight() or height
            if top < cur then scroll:SetVerticalScroll(top)
            elseif top + h > cur + visible then scroll:SetVerticalScroll(top + h - visible) end
        end)
    end
    box:SetScript("OnEscapePressed", box.ClearFocus)
    box:SetScript("OnTextChanged", function(edit, userInput)
        if userInput and not self.refreshing then set(edit:GetText() or "") end
    end)
    --- Tout sélectionner : prêt pour Ctrl-C.
    function box:SelectAll()
        self:SetFocus()
        self:HighlightText()
    end
    self.refreshers[#self.refreshers + 1] = function() box:SetText(get() or "") end
    self:Place(scroll or box, lines * 14 + 16, (indent or 0) + 2)
    box.layoutY = (scroll or box).layoutY   -- la recherche vise la box, posée via son ScrollFrame
    box.layoutFrame = scroll                 -- grille : position connue après Reflow
    if conditions then self.dependents[#self.dependents + 1] = { frame = box, conditions = conditions } end
    self.last = box
    self:Label(label, box)
    return box
end

--------------------------------------------------------------------------------
-- Onglets
--------------------------------------------------------------------------------

--- Ferme l'onglet en cours : sa hauteur est connue.
function Layout:CloseTab()
    local tab = self.currentTab and self.tabs[self.currentTab]
    if tab then tab.height = -self.y end
end

--- Ouvre un onglet : les widgets suivants vont dans son cadre, sous la barre d'onglets
-- posée au premier appel. Les onglets restent jusqu'en bas de la page.
function Layout:Tab(label)
    self:CloseTab()
    self:PopParents(1)
    self.row = nil   -- une ligne de cases ne se prolonge pas dans l'onglet suivant
    self.advancedGroup, self.advancedAt = nil, nil
    if self.grid then return self:GridTab(label) end
    local bar = self.tabBar
    if not bar then
        bar = CreateFrame("Frame", nil, self.root)
        bar:SetPoint("TOPLEFT", self.root, "TOPLEFT", self.x, self.y)
        bar:SetSize(self.width, TAB_HEIGHT)
        bar.nextX, bar.rows = 0, 1
        self.tabBar, self.tabs, self.tabTop = bar, {}, self.y
    end
    local index = #self.tabs + 1
    local button = CreateFrame("Button", NextName(), bar, "UIPanelButtonTemplate")
    button:SetText(label)
    local width = math.max(80, TextWidth(button, label) + 24)
    if bar.nextX > 0 and bar.nextX + width > self.width then
        bar.rows, bar.nextX = bar.rows + 1, 0
    end
    button:SetSize(width, TAB_HEIGHT - 2)
    Widgets.FitText(button)
    button:SetPoint("TOPLEFT", bar, "TOPLEFT", bar.nextX, -(bar.rows - 1) * TAB_HEIGHT)
    button:SetScript("OnClick", function() self:SelectTab(index) end)
    bar.nextX = bar.nextX + width + 4
    bar:SetHeight(bar.rows * TAB_HEIGHT)
    local section = CreateFrame("Frame", nil, self.root)
    section:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", -self.x, -8)
    section:SetSize(self.x + self.width, 1)
    if index > 1 then section:Hide() end
    self.tabs[index] = { button = button, section = section, label = label, height = 0 }
    self.parent, self.y, self.currentTab = section, 0, index
    return button
end

--- Onglet de la grille : onglet plat, barre dans `tabHost` (en-tête de la page) si donné.
function Layout:GridTab(label)
    local bar = self.tabBar
    if not bar then
        bar = CreateFrame("Frame", nil, self.tabHost or self.root)
        bar:SetSize(self.width, GRID_TAB_HEIGHT)
        bar.nextX, bar.rows = 0, 1
        if self.tabHost then
            bar:SetPoint("TOPLEFT", self.tabHost, "TOPLEFT", 0, 0)
        else
            self.tabBarItem = self:GridAdd(bar, "full", GRID_TAB_HEIGHT + 6, 0)
        end
        self.tabBar, self.tabs = bar, {}
    end
    local index = #self.tabs + 1
    local button = TabButton(bar, label)
    local width = math.max(60, TextWidth(button, label) + 28)
    if bar.nextX > 0 and bar.nextX + width > self.width then
        bar.rows, bar.nextX = bar.rows + 1, 0
    end
    button:SetSize(width, GRID_TAB_HEIGHT)
    button:SetPoint("TOPLEFT", bar, "TOPLEFT", bar.nextX, -(bar.rows - 1) * GRID_TAB_HEIGHT)
    button:SetScript("OnClick", function() self:SelectTab(index) end)
    bar.nextX = bar.nextX + width
    bar:SetHeight(bar.rows * GRID_TAB_HEIGHT)
    if self.tabBarItem then self.tabBarItem.height = bar.rows * GRID_TAB_HEIGHT + 6 end
    local section = CreateFrame("Frame", nil, self.root)
    section:SetSize(self.x + self.width, 1)
    if index > 1 then section:Hide() end
    self.tabs[index] = { button = button, section = section, label = label, height = 0, items = {} }
    self.parent, self.currentTab, self.items, self.pendingSpace = section, index, self.tabs[index].items, 0
    return button
end

--- Hauteur totale de la page (onglet affiché compris).
function Layout:Height()
    if self.grid then
        local tab = self.tabs and self.tabs[self.selectedTab or 1]
        return -(self.commonBottom or 0) + 4 + (tab and tab.height or 0) + 24
    end
    if not self.tabBar then return -self.y end
    local tab = self.tabs[self.selectedTab or 1]
    return -self.tabTop + self.tabBar:GetHeight() + 8 + tab.height
end

function Layout:SelectTab(index)
    if not (self.tabs and self.tabs[index]) then return end
    self.selectedTab = index
    for i, tab in ipairs(self.tabs) do
        tab.section:SetShown(i == index)
        if tab.button.SetSelected then
            tab.button.SetSelected(i == index)
        elseif tab.button.LockHighlight then
            if i == index then tab.button:LockHighlight() else tab.button:UnlockHighlight() end
        end
    end
    self.root:SetHeight(self:Height())
    if self.OnTabSelected then self.OnTabSelected() end
end

--- Vrai si le widget d'un libellé est masqué par le mode simple.
function Layout:ModeHidden(entry)
    local frame = entry.frame
    if not frame then return false end
    return (frame.modeHidden or (frame.gridRow and frame.gridRow.modeHidden)
        or (frame.layoutFrame and frame.layoutFrame.modeHidden)) == true
end

--- Distance du haut de la page au widget d'un libellé (onglet affiché si besoin).
function Layout:OffsetOf(entry)
    if self.grid then
        local frame = entry.frame and (entry.frame.layoutFrame or entry.frame.gridRow or entry.frame)
        local y = frame and frame.layoutY or 0
        if entry.tab then
            self:SelectTab(entry.tab)
            y = self.commonBottom - 4 + y
        end
        return -y
    end
    local y = entry.frame and entry.frame.layoutY or 0
    if entry.tab then
        self:SelectTab(entry.tab)
        y = self.tabTop - self.tabBar:GetHeight() - 8 + y
    end
    return -y
end

--- Fin de page : marge basse, hauteur du cadre, premier onglet, valeurs lues.
function Layout:Finish()
    if self.grid then
        self:Reflow()
        if self.tabBar then self:SelectTab(self.selectedTab or 1) end
        self:Refresh()
        if self.OnFinish then self.OnFinish() end
        return
    end
    self:Space(20)
    self:CloseTab()
    if self.tabBar then self:SelectTab(1) else self.root:SetHeight(-self.y) end
    self:Refresh()
end

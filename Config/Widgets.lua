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
local _, NS = ...

local Widgets = {}
NS.Widgets = Widgets

local CHECK_HEIGHT, BUTTON_HEIGHT, TAB_HEIGHT = 26, 30, 24
local DISABLED_ALPHA = 0.4
local MENU_ROWS, MENU_ROW_HEIGHT = 12, 20

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
function Widgets.Dropdown(parent, width, label, choices, get, set)
    local button = CreateFrame("Button", NextName(), parent, "UIPanelButtonTemplate")
    button:SetSize(width, 24)
    local arrow = button:CreateTexture(nil, "OVERLAY")
    arrow:SetSize(20, 20)
    arrow:SetPoint("RIGHT", button, "RIGHT", -2, 0)
    arrow:SetTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up")
    button.fitRight = 24   -- la flèche
    local function list() return type(choices) == "function" and choices() or choices end
    function button.Paint()
        local value, text = get(), label
        for _, choice in ipairs(list()) do
            if choice.value == value then text = label .. " : " .. choice.name break end
        end
        if value ~= nil and text == label then text = label .. " : " .. tostring(value) end
        button:SetText(text)
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
function Widgets.NewLayout(parent, x, width)
    return setmetatable({ root = parent, parent = parent, x = x or 16, y = -16, width = width or 560,
                          refreshers = {}, refreshing = false, labels = {},
                          parents = {}, dependents = {} }, Layout)
end

--- Libellé posé sur la page, gardé pour la recherche : { text, frame, tab }.
function Layout:Label(text, frame)
    if type(text) == "string" then
        self.labels[#self.labels + 1] = { text = text, frame = frame, tab = self.currentTab }
    end
end

--- Début d'un widget au retrait `indent` : rend ses conditions (getters des cases dont il dépend).
-- Une case en seconde colonne dont dépend ce widget repasse seule sur sa ligne, au-dessus de lui.
function Layout:Advance(indent)
    indent = indent or 0
    local row = self.row
    if row and row.kind == "check" and #row.frames > 1 and indent > row.indent then
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
    self.row = nil
    frame:SetPoint("TOPLEFT", self.parent, "TOPLEFT", self.x + (indent or 0), self.y)
    frame.layoutY = self.y
    self.y = self.y - height
end

--- Pose `frame` à droite du widget précédent de même type et même retrait s'il reste la place,
-- sinon au début d'une nouvelle ligne. `width` : place occupée ; `offset` : décalage de pose.
function Layout:PlaceInRow(frame, kind, width, height, indent, offset)
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
    -- Case grisée (module cédé) : l'infobulle reste lisible.
    if frame.SetMotionScriptsWhileDisabled then frame:SetMotionScriptsWhileDisabled(true) end
    frame:HookScript("OnEnter", function(owner) ShowTooltip(owner, text) end)
    frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

function Layout:Header(text)
    self.parents = {}
    local fs = self.parent:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
    fs:SetText(text)
    self:Place(fs, 34)
    return fs
end

--- Titre de section. Coupe les dépendances en retrait, garde les cases de premier niveau
-- (« Activer » d'un module grise toute sa page).
function Layout:Title(text)
    self:PopParents(1)
    self:Label(text)
    self:Space(10)
    local fs = self.parent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    fs:SetText(text)
    self:Place(fs, 24)
    local line = self.parent:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetWidth(self.width)
    local r, g, b = NS.Media:Accent()
    NS.SetSolidColor(line, r, g, b, 0.6)
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

function Layout:Check(label, get, set, indent)
    indent = indent or 0
    local conditions = self:Advance(indent)
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

function Layout:Slider(label, minValue, maxValue, step, get, set, indent, format)
    local conditions = self:Advance(indent)
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

function Layout:Button(label, onClick, indent)
    indent = indent or 0
    local conditions = self:Advance(indent)
    local b = CreateFrame("Button", NextName(), self.parent, "UIPanelButtonTemplate")
    b:SetText(label)
    local width = math.min(self.width - indent, math.max(140, TextWidth(b, label) + 32))
    b:SetSize(width, 24)
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

--- Hauteur totale de la page (onglet affiché compris).
function Layout:Height()
    if not self.tabBar then return -self.y end
    local tab = self.tabs[self.selectedTab or 1]
    return -self.tabTop + self.tabBar:GetHeight() + 8 + tab.height
end

function Layout:SelectTab(index)
    if not (self.tabs and self.tabs[index]) then return end
    self.selectedTab = index
    for i, tab in ipairs(self.tabs) do
        tab.section:SetShown(i == index)
        if tab.button.LockHighlight then
            if i == index then tab.button:LockHighlight() else tab.button:UnlockHighlight() end
        end
    end
    self.root:SetHeight(self:Height())
    if self.OnTabSelected then self.OnTabSelected() end
end

--- Distance du haut de la page au widget d'un libellé (onglet affiché si besoin).
function Layout:OffsetOf(entry)
    local y = entry.frame and entry.frame.layoutY or 0
    if entry.tab then
        self:SelectTab(entry.tab)
        y = self.tabTop - self.tabBar:GetHeight() - 8 + y
    end
    return -y
end

--- Fin de page : marge basse, hauteur du cadre, premier onglet, valeurs lues.
function Layout:Finish()
    self:Space(20)
    self:CloseTab()
    if self.tabBar then self:SelectTab(1) else self.root:SetHeight(-self.y) end
    self:Refresh()
end

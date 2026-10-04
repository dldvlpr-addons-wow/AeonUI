-- Config/OptionsWindow.lua
-- Fenêtre d'options propre à AeonUI (/aeon) : déplaçable, largeur et hauteur réglables, fermée par Échap.
--   * en haut : titre, puis les catégories en onglets (Général, puis les groupes de modules) ;
--   * à gauche : les pages de la catégorie choisie, chaque module avec un point d'état (vert actif,
--     gris coupé, orange cédé à un addon tiers) ; la recherche en bas ;
--   * à droite : la page choisie (cadres construits par Config/Options.lua) ; en haut à droite,
--     deux icônes : réinitialiser la page, recharger l'interface ;
--   * dans le bandeau, à droite : bascule mode simple / avancé (réglages avancés masqués ou non).
-- La recherche remplace la liste par les résultats ; un clic ouvre la page sur le réglage.
local _, NS = ...
local L = NS.L

local Window = { pages = {}, order = {}, rows = {}, query = "", category = "general" }
NS.OptionsWindow = Window

local WIDTH, HEIGHT, MIN_HEIGHT, MAX_WIDTH, MAX_HEIGHT = 1180, 720, 620, 1800, 1400
local SIDEBAR_WIDTH, ROW_HEIGHT, TOP_HEIGHT, CATEGORY_HEIGHT = 230, 24, 48, 32
local STATE_COLORS = { on = { 0.3, 0.85, 0.3 }, off = { 0.45, 0.45, 0.45 }, yielded = { 1, 0.6, 0.1 } }

local frame

--- État d'une page pour son point : "on", "off", "yielded" ou nil (pas de point).
-- Posé par Config/Options.lua, comme les crochets suivants.
Window.StateOf = function() return nil end
--- Groupe d'une page de module (clé de Window.groups).
Window.GroupOf = function() return nil end
--- Groupes de modules dans l'ordre de la liste : { { key, label } }.
Window.groups = {}
--- Bouton « Réinitialiser » de la page `key` : rend (libellé, action) ou nil.
Window.ResetOf = function() return nil end

--------------------------------------------------------------------------------
-- Liste de gauche
--------------------------------------------------------------------------------

local function Row(index)
    local row = Window.rows[index]
    if row then return row end
    row = CreateFrame("Button", nil, frame.listContent)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", frame.listContent, "TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
    row:SetPoint("RIGHT", frame.listContent, "RIGHT", 0, 0)
    row.selected = row:CreateTexture(nil, "BACKGROUND")
    row.selected:SetAllPoints()
    row.mark = row:CreateTexture(nil, "ARTWORK")
    row.mark:SetWidth(3)
    row.mark:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    row.mark:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    NS.SetSolidColor(highlight, 1, 1, 1, 0.06)
    row.dot = row:CreateTexture(nil, "ARTWORK")
    row.dot:SetSize(6, 6)
    row.dot:SetPoint("RIGHT", row, "RIGHT", -14, 0)
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.text:SetJustifyH("LEFT")
    if row.text.SetWordWrap then row.text:SetWordWrap(false) end
    row:SetScript("OnClick", function(self) if self.onClick then self.onClick() end end)
    Window.rows[index] = row
    return row
end

--- kind : "header", "page", "action" (commande) ou "empty". `key` : page d'un module.
local function PaintRow(row, kind, text, onClick, state, selected, key)
    local r, g, b = NS.Media:Accent()
    row.onClick, row.key = onClick, key
    row:EnableMouse(onClick ~= nil)
    row.text:SetText(text)
    row.text:SetFontObject(kind == "header" and "GameFontNormal" or "GameFontHighlight")
    row.text:ClearAllPoints()
    row.text:SetPoint("LEFT", row, "LEFT", kind == "header" and 8 or 16, kind == "header" and -3 or 0)
    row.text:SetPoint("RIGHT", row.dot, "LEFT", -6, 0)
    if kind == "header" then row.text:SetTextColor(r, g, b)
    elseif kind == "empty" then row.text:SetTextColor(0.6, 0.6, 0.6)
    elseif kind == "action" then row.text:SetTextColor(r, g, b)
    elseif selected then row.text:SetTextColor(1, 1, 1)
    else row.text:SetTextColor(0.8, 0.82, 0.86) end
    local color = STATE_COLORS[state or ""]
    if color then NS.SetSolidColor(row.dot, color[1], color[2], color[3], 1) end
    row.dot:SetShown(color ~= nil)
    NS.SetSolidColor(row.selected, r, g, b, selected and 0.18 or 0)
    NS.SetSolidColor(row.mark, r, g, b, 1)
    row.mark:SetShown(selected == true)
    row:Show()
end

--- Catégorie d'une page : "general" pour les pages générales, sinon le groupe du module (un module
-- sans groupe connu va dans le dernier).
function Window:CategoryOf(key)
    local page = self.pages[key]
    if not page or page.group ~= "modules" then return "general" end
    local last = self.groups[#self.groups]
    return self.GroupOf(key) or (last and last.key) or "general"
end

--- Onglets de catégorie en haut : Général, puis les groupes de modules.
local function PaintCategories()
    local categories = { { key = "general", label = L.OPT_GENERAL } }
    for _, group in ipairs(Window.groups) do categories[#categories + 1] = group end
    local tabs, x = frame.categoryTabs, 0
    for i, category in ipairs(categories) do
        local tab = tabs[i]
        if not tab then
            tab = NS.Widgets.TabButton(frame.categoryBar, "", "GameFontNormal")
            tab:SetHeight(CATEGORY_HEIGHT)
            tabs[i] = tab
        end
        tab:SetText(category.label)
        NS.Widgets.FitText(tab, 70)
        tab:ClearAllPoints()
        tab:SetPoint("BOTTOMLEFT", frame.categoryBar, "BOTTOMLEFT", x, 0)
        x = x + tab:GetWidth()
        tab:SetScript("OnClick", function() Window:ShowCategory(category.key) end)
        tab.SetSelected(category.key == Window.category)
        tab:Show()
    end
    for i = #categories + 1, #tabs do tabs[i]:Hide() end
end

--- Repeint la liste : pages de la catégorie, ou résultats de recherche (au moins deux lettres).
function Window:RenderList()
    if not frame then return end
    PaintCategories()
    local used = 0
    local function add(...)
        used = used + 1
        PaintRow(Row(used), ...)
    end
    local query = self.query:match("^%s*(.-)%s*$")
    if #query >= 2 then
        add("header", L.OPT_SEARCH_RESULTS)
        local results = NS.Options.Search(query)
        for _, result in ipairs(results) do
            local text = result.label and (result.title .. " > " .. result.label) or result.title
            add("page", text, function() NS.Options.Reveal(result) end)
        end
        if #results == 0 then add("empty", L.OPT_SEARCH_EMPTY) end
    else
        if self.category == "general" then
            add("action", L.OPT_UNLOCK, function() NS:SetUnlocked(not NS.unlocked) end)
        end
        for _, key in ipairs(self.order) do
            local page = self.pages[key]
            if self:CategoryOf(key) == self.category then
                add("page", page.title, function() Window:Show(key) end,
                    page.group == "modules" and self.StateOf(key) or nil, key == self.selected, key)
            end
        end
    end
    for i = used + 1, #self.rows do self.rows[i]:Hide() end
    frame.listContent:SetHeight(math.max(1, used * ROW_HEIGHT))
end

--------------------------------------------------------------------------------
-- Outils de la page : réinitialiser, recharger (icônes en haut à droite)
--------------------------------------------------------------------------------

--- Bouton « Recharger l'interface » : Forever bloque ReloadUI() appelé par un addon ; un bouton
-- d'action joue la macro /reload sur le clic du joueur.
local function SetupReload(button)
    button:RegisterForClicks("AnyUp")
    button:SetAttribute("useOnKeyDown", false)
    button:SetAttribute("type", "macro")
    button:SetAttribute("macrotext", "/reload")
end

--- Bouton icône carré avec infobulle.
local function IconButton(parent, texture, tooltip, template)
    local button = CreateFrame("Button", nil, parent, template)
    button:SetSize(26, 26)
    local fill = button:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints()
    NS.SetSolidColor(fill, 1, 1, 1, 0.06)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", button, "TOPLEFT", 5, -5)
    icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -5, 5)
    icon:SetTexture(texture)
    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    NS.SetSolidColor(highlight, 1, 1, 1, 0.12)
    button.tooltip = tooltip
    button:SetScript("OnEnter", function(self) NS.Widgets.ShowTooltip(self, self.tooltip) end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return button
end

local function BuildTools(content)
    local tools = CreateFrame("Frame", nil, frame)
    tools:SetSize(64, 26)
    tools:SetPoint("TOPRIGHT", content, "TOPRIGHT", -16, -18)
    tools:SetFrameLevel(frame:GetFrameLevel() + 20)
    local reload = IconButton(tools, "Interface\\Buttons\\UI-RefreshButton", L.OPT_RELOAD_UI, "InsecureActionButtonTemplate")
    reload:SetPoint("RIGHT", tools, "RIGHT", 0, 0)
    if NS.InCombat() then NS:RunOutOfCombat(function() SetupReload(reload) end) else SetupReload(reload) end
    local reset = IconButton(tools, "Interface\\PaperDollInfoFrame\\UI-GearManager-Undo", L.OPT_RESET_MODULE)
    reset:SetPoint("RIGHT", reload, "LEFT", -6, 0)
    reset:SetScript("OnClick", function(self) if self.action then self.action() end end)
    tools.reset, tools.reload = reset, reload
    frame.tools = tools
end

--- Outils de la page affichée : « Réinitialiser » suit la page.
local function PaintTools(key)
    local label, action = Window.ResetOf(key)
    local reset = frame.tools.reset
    reset.action, reset.tooltip = action, label
    reset:SetShown(label ~= nil)
end

--------------------------------------------------------------------------------
-- Fenêtre
--------------------------------------------------------------------------------

local function Build()
    frame = CreateFrame("Frame", "AeonUIOptionsWindow", UIParent)
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    if frame.SetToplevel then frame:SetToplevel(true) end
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    NS.Media:CreateBackdrop(frame)
    Window:ApplyScale()

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 2, 2)
    close:SetFrameLevel(frame:GetFrameLevel() + 10)

    -- Bandeau du haut : titre, catégories en onglets posés sur son trait bas.
    local top = CreateFrame("Frame", nil, frame)
    top:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    top:SetHeight(TOP_HEIGHT)
    local topBackground = top:CreateTexture(nil, "BACKGROUND")
    topBackground:SetAllPoints()
    NS.SetSolidColor(topBackground, 0, 0, 0, 0.35)
    local topEdge = top:CreateTexture(nil, "ARTWORK")
    topEdge:SetHeight(1)
    topEdge:SetPoint("BOTTOMLEFT")
    topEdge:SetPoint("BOTTOMRIGHT")
    NS.SetSolidColor(topEdge, 1, 1, 1, 0.08)

    local title = top:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    title:SetPoint("LEFT", top, "LEFT", 16, 0)
    title:SetText("|cff3fa9f5Aeon|rUI")
    local metadata = _G.C_AddOns and C_AddOns.GetAddOnMetadata
    local version = metadata and metadata("AeonUI", "Version")
    local versionText = top:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    versionText:SetPoint("LEFT", title, "RIGHT", 8, -2)
    versionText:SetText(version or "")

    local mode = NS.Widgets.FlatButton(top, "", 150, 24)
    mode:SetPoint("RIGHT", top, "RIGHT", -40, 0)
    mode:SetScript("OnClick", function()
        NS.Options.SetMode(NS.Widgets.SimpleMode() and "advanced" or "simple")
    end)
    mode:SetScript("OnEnter", function(self) NS.Widgets.ShowTooltip(self, L.OPT_MODE_HINT) end)
    mode:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.mode = mode

    local categoryBar = CreateFrame("Frame", nil, top)
    categoryBar:SetPoint("BOTTOMLEFT", top, "BOTTOMLEFT", SIDEBAR_WIDTH + 12, 0)
    categoryBar:SetPoint("TOPRIGHT", top, "TOPRIGHT", -202, 0)
    frame.categoryBar, frame.categoryTabs = categoryBar, {}

    -- Colonne de gauche : pages de la catégorie, recherche en bas.
    local sidebar = CreateFrame("Frame", nil, frame)
    sidebar:SetPoint("TOPLEFT", top, "BOTTOMLEFT", 0, 0)
    sidebar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    sidebar:SetWidth(SIDEBAR_WIDTH)
    local sidebarBackground = sidebar:CreateTexture(nil, "BACKGROUND")
    sidebarBackground:SetAllPoints()
    NS.SetSolidColor(sidebarBackground, 0, 0, 0, 0.2)
    local sidebarEdge = sidebar:CreateTexture(nil, "ARTWORK")
    sidebarEdge:SetWidth(1)
    sidebarEdge:SetPoint("TOPRIGHT")
    sidebarEdge:SetPoint("BOTTOMRIGHT")
    NS.SetSolidColor(sidebarEdge, 1, 1, 1, 0.08)

    local search = CreateFrame("EditBox", "AeonUIOptionsSearch", sidebar, "InputBoxTemplate")
    search:SetSize(SIDEBAR_WIDTH - 36, 22)
    search:SetPoint("BOTTOMLEFT", sidebar, "BOTTOMLEFT", 20, 14)
    search:SetAutoFocus(false)
    local placeholder = search:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    placeholder:SetPoint("LEFT", search, "LEFT", 2, 0)
    placeholder:SetText(L.OPT_SEARCH_PLACEHOLDER)
    search:SetScript("OnTextChanged", function(self)
        Window.query = self:GetText() or ""
        placeholder:SetShown(Window.query == "")
        Window:RenderList()
    end)
    search:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    frame.search = search

    local list = CreateFrame("ScrollFrame", nil, sidebar)
    list:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 0, -10)
    list:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", 0, 48)
    local listContent = CreateFrame("Frame", nil, list)
    listContent:SetSize(SIDEBAR_WIDTH, 1)
    list:SetScrollChild(listContent)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(self, delta)
        local range = self:GetVerticalScrollRange() or 0
        self:SetVerticalScroll(math.min(range, math.max(0, self:GetVerticalScroll() - delta * ROW_HEIGHT * 2)))
    end)
    frame.listContent = listContent

    -- Zone de droite : la page choisie ; outils en haut à droite.
    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 0, 0)
    content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 8)
    frame.content = content
    BuildTools(content)

    NS.Widgets.AddResizeGrip(frame, WIDTH, MIN_HEIGHT, MAX_WIDTH, MAX_HEIGHT)

    frame:SetScript("OnHide", function()
        NS.Widgets.CloseMenu()
        NS.Widgets.HideTip()
    end)
    table.insert(UISpecialFrames, "AeonUIOptionsWindow")
    frame:Hide()
end

--- Libellé de la bascule de mode.
function Window:PaintMode()
    if frame then frame.mode:SetText(NS.Widgets.SimpleMode() and L.OPT_MODE_SIMPLE or L.OPT_MODE_ADVANCED) end
end

local function Attach(page, key)
    local panel = page.panel
    panel:SetParent(frame.content)
    panel:ClearAllPoints()
    panel:SetAllPoints(frame.content)
    panel:SetShown(Window.selected == key and frame:IsShown())
end

--- Inscrit (ou remplace) une page. group : "general" ou "modules" ; l'ordre d'inscription est gardé.
-- `panel` : le cadre, ou une fonction qui le construit à la première ouverture de la page.
function Window:AddPage(key, title, panel, group)
    if not frame then Build() end
    local previous = self.pages[key]
    if previous then
        if previous.panel and previous.panel ~= panel then previous.panel:Hide() end
    else
        self.order[#self.order + 1] = key
    end
    local page = { title = title, group = group }
    if type(panel) == "function" then page.build = panel else page.panel = panel end
    self.pages[key] = page
    -- Page déjà construite remplacée : la nouvelle l'est tout de suite (état gardé à l'identique).
    if page.panel or (previous and previous.panel) then self:Ensure(key) end
    self:RenderList()
end

--- Construit la page `key` si elle ne l'est pas encore ; rend son cadre.
function Window:Ensure(key)
    local page = self.pages[key]
    if not page then return nil end
    if not page.panel then
        page.panel = page.build()
        page.build = nil
    end
    if page.panel:GetParent() ~= frame.content then Attach(page, key) end
    return page.panel
end

--- Vrai si la page est construite.
function Window:IsBuilt(key) return self.pages[key] ~= nil and self.pages[key].panel ~= nil end

--- Ouvre la fenêtre sur une page (la dernière vue, sinon la première).
function Window:Show(key)
    if not frame then Build() end
    key = key or self.selected or self.order[1]
    local page = self.pages[key]
    if not page then return end
    local current = self.selected and self.pages[self.selected]
    if current and current ~= page and current.panel then current.panel:Hide() end
    self.selected = key
    self.category = self:CategoryOf(key)
    self:PaintMode()
    frame:Show()
    self:Ensure(key):Show()
    PaintTools(key)
    self:RenderList()
end

--- Onglet de catégorie : recherche effacée, première page de la catégorie ouverte (la page
-- ouverte reste si la catégorie est déjà la sienne).
function Window:ShowCategory(category)
    if frame.search:GetText() ~= "" then frame.search:SetText("") end
    if category == self.category then return end
    for _, key in ipairs(self.order) do
        if self:CategoryOf(key) == category then return self:Show(key) end
    end
end

--- Taille de la fenêtre (réglage theme.optionsScale), en plus de l'échelle de l'interface.
function Window:ApplyScale()
    if frame then frame:SetScale(NS.db and NS.db.theme.optionsScale or 1) end
end

function Window:Hide()
    if frame then frame:Hide() end
end

function Window:IsShown() return frame ~= nil and frame:IsShown() end

function Window:GetFrame() return frame end

function Window:Selected() return self.selected end

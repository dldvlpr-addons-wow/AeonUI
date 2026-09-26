-- Config/OptionsWindow.lua
-- Fenêtre d'options propre à AeonUI (/aeon) : déplaçable, largeur et hauteur réglables, fermée par Échap.
--   * à gauche : recherche, pages générales (Général, Modules, Profils, Maintenance), puis une
--     page par module avec un repère d'état (vert actif, gris coupé, orange cédé à un addon tiers) ;
--   * à droite : la page choisie (cadres construits par Config/Options.lua).
-- La recherche remplace la liste par les résultats ; un clic ouvre la page sur le réglage.
local _, NS = ...
local L = NS.L

local Window = { pages = {}, order = {}, rows = {}, query = "" }
NS.OptionsWindow = Window

local WIDTH, HEIGHT, MIN_HEIGHT, MAX_WIDTH, MAX_HEIGHT = 900, 640, 420, 1600, 1400
local SIDEBAR_WIDTH, ROW_HEIGHT = 210, 22
local STATE_COLORS = { on = { 0.3, 0.85, 0.3 }, off = { 0.45, 0.45, 0.45 }, yielded = { 1, 0.6, 0.1 } }

local frame

--- État d'une page pour son repère : "on", "off", "yielded" ou nil (pas de repère).
-- Posé par Config/Options.lua.
Window.StateOf = function() return nil end

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
    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    NS.SetSolidColor(highlight, 1, 1, 1, 0.08)
    row.dot = row:CreateTexture(nil, "ARTWORK")
    row.dot:SetSize(8, 8)
    row.dot:SetPoint("LEFT", row, "LEFT", 8, 0)
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.text:SetPoint("LEFT", row, "LEFT", 22, 0)
    row.text:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.text:SetJustifyH("LEFT")
    if row.text.SetWordWrap then row.text:SetWordWrap(false) end
    row:SetScript("OnClick", function(self) if self.onClick then self.onClick() end end)
    Window.rows[index] = row
    return row
end

local function PaintRow(row, kind, text, onClick, state, selected)
    local r, g, b = NS.Media:Accent()
    row.onClick = onClick
    row:EnableMouse(onClick ~= nil)
    row.text:SetText(text)
    row.text:SetFontObject(kind == "header" and "GameFontNormalSmall" or "GameFontHighlight")
    if kind == "header" then row.text:SetTextColor(r, g, b)
    elseif kind == "empty" then row.text:SetTextColor(0.6, 0.6, 0.6)
    else row.text:SetTextColor(1, 1, 1) end
    local color = STATE_COLORS[state or ""]
    if color then NS.SetSolidColor(row.dot, color[1], color[2], color[3], 1) end
    row.dot:SetShown(color ~= nil)
    NS.SetSolidColor(row.selected, r, g, b, selected and 0.35 or 0)
    row:Show()
end

--- Repeint la liste : pages, ou résultats de recherche (au moins deux lettres).
function Window:RenderList()
    if not frame then return end
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
        local group
        for _, key in ipairs(self.order) do
            local page = self.pages[key]
            if page.group ~= group then
                group = page.group
                add("header", group == "modules" and L.OPT_MODULES or "AeonUI")
            end
            add("page", page.title, function() Window:Show(key) end, self.StateOf(key), key == self.selected)
        end
    end
    for i = used + 1, #self.rows do self.rows[i]:Hide() end
    frame.listContent:SetHeight(math.max(1, used * ROW_HEIGHT))
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

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -12)
    title:SetText("|cff3fa9f5Aeon|rUI")
    local metadata = _G.C_AddOns and C_AddOns.GetAddOnMetadata
    local version = metadata and metadata("AeonUI", "Version")
    if version then
        local versionText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        versionText:SetPoint("LEFT", title, "RIGHT", 8, -1)
        versionText:SetText(version)
    end
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 2, 2)

    -- Colonne de gauche : recherche puis liste défilante.
    local sidebar = CreateFrame("Frame", nil, frame)
    sidebar:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -40)
    sidebar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 8, 8)
    sidebar:SetWidth(SIDEBAR_WIDTH)
    local sidebarBackground = sidebar:CreateTexture(nil, "BACKGROUND")
    sidebarBackground:SetAllPoints()
    NS.SetSolidColor(sidebarBackground, 0, 0, 0, 0.25)

    local search = CreateFrame("EditBox", "AeonUIOptionsSearch", sidebar, "InputBoxTemplate")
    search:SetSize(SIDEBAR_WIDTH - 20, 20)
    search:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 12, -6)
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
    list:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 0, -32)
    list:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", 0, 4)
    local listContent = CreateFrame("Frame", nil, list)
    listContent:SetSize(SIDEBAR_WIDTH, 1)
    list:SetScrollChild(listContent)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(self, delta)
        local range = self:GetVerticalScrollRange() or 0
        self:SetVerticalScroll(math.min(range, math.max(0, self:GetVerticalScroll() - delta * ROW_HEIGHT * 2)))
    end)
    frame.listContent = listContent

    -- Zone de droite : la page choisie y est posée.
    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 8, 0)
    content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 8)
    frame.content = content

    NS.Widgets.AddResizeGrip(frame, WIDTH, MIN_HEIGHT, MAX_WIDTH, MAX_HEIGHT)

    frame:SetScript("OnHide", function() NS.Widgets.CloseMenu() end)
    table.insert(UISpecialFrames, "AeonUIOptionsWindow")
    frame:Hide()
end

--- Inscrit (ou remplace) une page. group : "general" ou "modules" ; l'ordre d'inscription est gardé.
function Window:AddPage(key, title, panel, group)
    if not frame then Build() end
    local previous = self.pages[key]
    if previous then
        if previous.panel ~= panel then previous.panel:Hide() end
    else
        self.order[#self.order + 1] = key
    end
    self.pages[key] = { title = title, panel = panel, group = group }
    panel:SetParent(frame.content)
    panel:ClearAllPoints()
    panel:SetAllPoints(frame.content)
    panel:SetShown(self.selected == key)
    self:RenderList()
end

--- Ouvre la fenêtre sur une page (la dernière vue, sinon la première).
function Window:Show(key)
    if not frame then Build() end
    key = key or self.selected or self.order[1]
    local page = self.pages[key]
    if not page then return end
    local current = self.selected and self.pages[self.selected]
    if current and current ~= page then current.panel:Hide() end
    self.selected = key
    frame:Show()
    page.panel:Show()
    self:RenderList()
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

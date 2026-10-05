-- Config/Options.lua
-- Pages de la fenêtre d'options (Config/OptionsWindow.lua) :
--   * pages générales : Général (langue, apparence, cadres mobiles), Modules (interrupteurs),
--     Profils (profil actif, partage, préréglages de rôle), Maintenance ;
--   * une page par module : en-tête fixe (titre et case du module, explication, recherche
--     dans la page, onglets), puis ce que le module décrit lui-même dans module:BuildOptions(o) ;
--     à droite, un aperçu cliquable si le module en décrit un (module:BuildPreview(p)).
-- Options > AddOns > AeonUI ne garde qu'un bouton qui ouvre la fenêtre.
-- Les getters relisent NS.db à chaque appel : changer de profil remplace la table.
local _, NS = ...
local L = NS.L
local Window = NS.OptionsWindow

local Options = {}
NS.Options = Options

local PAGE_X, PAGE_WIDTH, HEADER_TOP = 24, 880, 18
local PREVIEW_COLUMN = 270   -- colonne de l'aperçu, à droite des réglages

--------------------------------------------------------------------------------
-- Confirmations
--------------------------------------------------------------------------------

StaticPopupDialogs["AEONUI_RESET_POSITIONS"] = {
    text = "",   -- posé à l'ouverture : la langue peut changer après le chargement
    button1 = YES,
    button2 = NO,
    OnAccept = function() NS.Movers:ResetAll() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- Message complet passé en text_arg1 : un « % » dans un nom de profil ne casse pas le format.
local function Confirm(which, message, onAccept)
    StaticPopupDialogs[which] = {
        text = "%s", button1 = YES, button2 = NO, OnAccept = onAccept,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
    StaticPopup_Show(which, message)
end
Options.Confirm = Confirm

--- Bouton « Recharger » : Forever bloque ReloadUI() appelé par un addon, même sur un clic.
-- Un bouton d'action posé sur celui de la popup joue la macro /reload (clic matériel).
-- Popups partagées entre toutes les boîtes : le calque se cache avec la nôtre.
local function ReloadOverlay(popup)
    local button = (popup.GetButton and popup:GetButton(1)) or popup.button1
    if not button then return end
    local overlay = popup.AeonUIReload
    if not overlay then
        overlay = CreateFrame("Button", nil, button, "InsecureActionButtonTemplate")
        overlay:SetAllPoints(button)
        overlay:RegisterForClicks("AnyUp")
        overlay:SetAttribute("useOnKeyDown", false)
        overlay:SetAttribute("type", "macro")
        overlay:SetAttribute("macrotext", "/reload")
        popup.AeonUIReload = overlay
    end
    overlay:SetParent(button)
    overlay:SetAllPoints(button)
    overlay:SetFrameLevel(button:GetFrameLevel() + 5)
    overlay:Show()
end

--- Propose /reload (module coupé qui ne rend ses cadres Blizzard qu'au rechargement, langue).
local function AskReload(message)
    -- En combat, les attributs du calque ne s'écrivent pas : message seul, /reload à la main.
    if NS.InCombat() then
        StaticPopupDialogs.AEONUI_RELOAD_COMBAT = {
            text = "%s", button1 = _G.OKAY or "OK",
            timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
        }
        StaticPopup_Show("AEONUI_RELOAD_COMBAT", message .. "\n\n" .. L.MSG_RELOAD_TYPE)
        return
    end
    StaticPopupDialogs.AEONUI_RELOAD = {
        text = "%s", button1 = L.OPT_RELOAD_NOW, button2 = L.OPT_LATER,
        OnHide = function(popup) if popup and popup.AeonUIReload then popup.AeonUIReload:Hide() end end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
    local popup = StaticPopup_Show("AEONUI_RELOAD", message)
    if popup then ReloadOverlay(popup) end
end
Options.AskReload = AskReload

-- Cadre Blizzard rendu sans module coupé (profil, case d'unité, « Cacher Blizzard » décoché) :
-- il ne revient qu'au /reload. Popup déjà ouverte (module coupé) : son message est gardé.
NS:On("BLIZZARD_FRAMES_RELEASED", function()
    if not (_G.StaticPopup_Visible and StaticPopup_Visible("AEONUI_RELOAD")) then AskReload(L.MSG_RELOAD_BLIZZARD) end
end)

--- Active ou coupe un module depuis les options ; propose /reload si ses cadres Blizzard ne reviennent qu'ainsi.
local function SetModuleEnabled(name, value)
    local module = NS.Modules:Get(name)
    local wasRunning = module and module.enabled
    NS.Modules:SetEnabled(name, value)
    if not value and wasRunning and module.reloadOnDisable then
        AskReload(string.format(L.MSG_RELOAD_REQUIRED, module.title or name))
    end
end

local layouts = {}        -- [clé de page] = layout (pour Refresh, la recherche et les tests)
local scrolls = {}        -- [clé de page] = ScrollFrame de la page

--- Recherche dans la page : chaque frappe amène le premier réglage trouvé, Entrée le suivant.
local function PageSearch(header, key)
    local search = CreateFrame("EditBox", nil, header, "InputBoxTemplate")
    search:SetSize(200, 22)
    search:SetPoint("TOPRIGHT", header, "TOPRIGHT", -92, -HEADER_TOP - 4)   -- à gauche des outils de la fenêtre
    search:SetAutoFocus(false)
    local placeholder = search:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    placeholder:SetPoint("LEFT", search, "LEFT", 2, 0)
    placeholder:SetText(L.OPT_SEARCH_PAGE)
    local found, index = {}, 0
    local function reveal(typing)
        local result = found[index]
        if result then Options.Reveal(result, typing) end
    end
    search:SetScript("OnTextChanged", function(self)
        local text = self:GetText() or ""
        placeholder:SetShown(text == "")
        found, index = {}, 1
        if #text >= 2 then
            for _, result in ipairs(Options.Search(text, key)) do
                if result.entry then found[#found + 1] = result end
            end
        end
        reveal(true)
    end)
    search:SetScript("OnEnterPressed", function()
        if #found == 0 then return end
        index = index % #found + 1
        reveal()
    end)
    search:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)
    return search
end

--- Fine barre de défilement à droite de la page : position et part visible.
local function ScrollIndicator(panel, scroll)
    local thumb = panel:CreateTexture(nil, "OVERLAY")
    thumb:SetWidth(3)
    thumb:Hide()
    local function paint()
        local range, visible = scroll:GetVerticalScrollRange() or 0, scroll:GetHeight() or 0
        if range <= 0 or visible <= 0 then thumb:Hide() return end
        local height = math.max(24, visible * visible / (visible + range))
        local offset = (visible - height) * ((scroll:GetVerticalScroll() or 0) / range)
        local r, g, b = NS.Media:Accent()
        NS.SetSolidColor(thumb, r, g, b, 0.6)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 3, -offset)
        thumb:SetHeight(height)
        thumb:Show()
    end
    scroll:SetScript("OnScrollRangeChanged", paint)
    scroll:SetScript("OnVerticalScroll", paint)
    return paint
end

--- Page : en-tête fixe (titre, explication, recherche, onglets) puis contenu défilant en grille.
-- `sideWidth` : colonne fixe à droite (panel.side), les réglages défilent à sa gauche.
local function NewPage(key, title, description, sideWidth)
    local panel = CreateFrame("Frame", "AeonUIOptions" .. key)
    panel:Hide()
    local header = CreateFrame("Frame", nil, panel)
    header:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, 0)
    local headerBackground = header:CreateTexture(nil, "BACKGROUND")
    headerBackground:SetAllPoints()
    NS.SetSolidColor(headerBackground, 0, 0, 0, 0.2)
    local headerLine = header:CreateTexture(nil, "ARTWORK")
    headerLine:SetHeight(1)
    headerLine:SetPoint("BOTTOMLEFT")
    headerLine:SetPoint("BOTTOMRIGHT")
    NS.SetSolidColor(headerLine, 1, 1, 1, 0.08)
    local titleText = header:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    titleText:SetPoint("TOPLEFT", header, "TOPLEFT", PAGE_X, -HEADER_TOP)
    titleText:SetWidth(PAGE_WIDTH - 250)
    titleText:SetJustifyH("LEFT")
    if titleText.SetWordWrap then titleText:SetWordWrap(false) end
    titleText:SetTextColor(1, 1, 1)
    titleText:SetText(title)
    panel.header, panel.titleText = header, titleText
    local descriptionText = header:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    descriptionText:SetPoint("TOPLEFT", titleText, "BOTTOMLEFT", 0, -6)
    descriptionText:SetWidth(PAGE_WIDTH - 250)
    descriptionText:SetJustifyH("LEFT")
    descriptionText:SetTextColor(0.7, 0.72, 0.76)
    descriptionText:SetText(description or "")
    panel.search = PageSearch(header, key)
    local tabHost = CreateFrame("Frame", nil, header)
    tabHost:SetSize(PAGE_WIDTH, 1)

    local scroll = CreateFrame("ScrollFrame", nil, panel)
    scroll:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -12 - (sideWidth and sideWidth + 12 or 0), 0)
    if sideWidth then
        panel.side = CreateFrame("Frame", nil, panel)
        panel.side:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", -16, -12)
        panel.side:SetWidth(sideWidth)
    end
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local range = self:GetVerticalScrollRange() or 0
        local value = self:GetVerticalScroll() - delta * 40
        if value < 0 then value = 0 elseif value > range then value = range end
        self:SetVerticalScroll(value)
    end)
    local paintScroll = ScrollIndicator(panel, scroll)
    scroll:SetScript("OnSizeChanged", function(_, width)
        content:SetWidth(width)
        paintScroll()
    end)
    local width = sideWidth and (PAGE_WIDTH - sideWidth - 20) or PAGE_WIDTH
    local layout = NS.Widgets.NewLayout(content, PAGE_X, width, { grid = true, tabHost = tabHost })
    layout.description = description
    -- Hauteur de l'en-tête : explication (sur plusieurs lignes) et rangées d'onglets.
    local function FitHeader()
        local hasDescription = description and description ~= ""
        local top = HEADER_TOP + 30 + (hasDescription and ((descriptionText:GetStringHeight() or 14) + 6) or 0) + 12
        tabHost:ClearAllPoints()
        tabHost:SetPoint("TOPLEFT", header, "TOPLEFT", PAGE_X, -top)
        local tabs = layout.tabBar and layout.tabBar:GetHeight() or 0
        header:SetHeight(top + (tabs > 0 and tabs or -6))
    end
    FitHeader()
    layout.OnFinish = FitHeader
    -- Onglet changé : la page repart du haut (la hauteur change).
    layout.OnTabSelected = function()
        scroll:SetVerticalScroll(0)
        paintScroll()
    end
    panel:SetScript("OnShow", function() layout:Refresh() paintScroll() end)
    layouts[key], scrolls[key] = layout, scroll
    return panel, layout, content
end

--------------------------------------------------------------------------------
-- Aide passée aux modules : widgets liés à une clé de leur table de réglages.
--------------------------------------------------------------------------------

local ModuleOptions = {}
ModuleOptions.__index = ModuleOptions

function ModuleOptions:DB() return NS.db.modules[self.name] end

-- Clés imbriquées : "show.friends" -> db.show.friends, "units.player.width" -> db.units.player.width.
local function Resolve(db, key)
    local parent, leaf = db, key
    while true do
        local part, rest = leaf:match("^([^%.]+)%.(.+)$")
        if not part then break end
        parent, leaf = parent[tonumber(part) or part], rest
    end
    return parent, tonumber(leaf) or leaf
end

-- Une clé peut être une fonction qui rend la clé au moment de la lecture (widget qui suit une
-- sélection, ex. le panneau réglé dans DataPanels) ; KeyAt ajoute un suffixe aux deux formes.
local function KeyOf(key) if type(key) == "function" then return key() end return key end
local function KeyAt(key, suffix)
    if type(key) == "function" then return function() return key() .. suffix end end
    return key .. suffix
end
ModuleOptions.KeyAt = KeyAt

function ModuleOptions:Getter(key)
    return function() local t, k = Resolve(self:DB(), KeyOf(key)) return t[k] end
end

--- Réglage changé : module rafraîchi, puis l'aperçu de la page s'il y en a un.
function ModuleOptions:Changed()
    NS.Modules:Refresh(self.name)
    if self.preview then self.preview() end
end

function ModuleOptions:Setter(key, after)
    return function(value)
        local t, k = Resolve(self:DB(), KeyOf(key))
        t[k] = value
        self:Changed()
        if after then after(value) end
    end
end

function ModuleOptions:Check(key, label, indent, after)
    return self.layout:Check(label, self:Getter(key), self:Setter(key, after), indent or 20)
end

function ModuleOptions:Slider(key, label, minValue, maxValue, step, indent, format)
    -- Bornes gardées pour l'import : un profil reçu ne sort pas des limites du curseur.
    if type(key) == "string" then NS.Database.bounds["modules." .. self.name .. "." .. key] = { minValue, maxValue } end
    return self.layout:Slider(label, minValue, maxValue, step, self:Getter(key), self:Setter(key),
        indent or 20, format)
end

function ModuleOptions:Dropdown(key, label, choices, indent, after)
    return self.layout:Dropdown(label, choices, self:Getter(key), self:Setter(key, after), indent or 20)
end

function ModuleOptions:Color(key, label, indent)
    return self.layout:Color(label, self:Getter(key), function() self:Changed() end, indent or 20)
end

function ModuleOptions:Title(text) return self.layout:Title(text) end
function ModuleOptions:Tab(label) return self.layout:Tab(label) end
function ModuleOptions:Note(text, indent) return self.layout:Note(text, indent or 20) end
function ModuleOptions:Hint(text) return self.layout:Hint(text) end
function ModuleOptions:Button(label, onClick, indent, primary) return self.layout:Button(label, onClick, indent or 20, primary) end
--- Réglages suivants moins courants, en fin de bloc, jusqu'au prochain titre ou onglet.
function ModuleOptions:Advanced() return self.layout:Advanced(L.OPT_ADVANCED_SHOW) end
--- Fin des réglages avancés : les suivants du bloc redeviennent courants.
function ModuleOptions:EndAdvanced() self.layout:EndAdvanced() end
function ModuleOptions:EditBox(key, label, lines, indent)
    return self.layout:EditBox(label, self:Getter(key), self:Setter(key), lines, indent or 20)
end

--- Visibilité commune (Core/Visibility) du réglage `key` : combinaison, six conditions, survol.
-- Ouvre son propre bloc jusqu'au prochain titre : à appeler en fin de section.
-- opts.secure : cadre à state driver, l'instance n'y a pas de condition macro et n'est pas proposée.
-- opts.noMouseover : module qui n'évalue que les conditions (pas de fondu au survol).
function ModuleOptions:Visibility(key, label, opts)
    opts = opts or {}
    local indent, secure = 20, opts.secure
    self.layout:Title(label)
    self:Advanced()
    self:Dropdown(KeyAt(key, ".match"), L.OPT_VIS_MATCH, {
        { name = L.OPT_VIS_MATCH_ALL, value = "all" }, { name = L.OPT_VIS_MATCH_ANY, value = "any" },
    }, indent)
    local choices = {
        { name = L.OPT_VIS_IGNORE, value = "ignore" }, { name = L.OPT_VIS_YES, value = "yes" },
        { name = L.OPT_VIS_NO, value = "no" },
    }
    for _, condition in ipairs(NS.Visibility.CONDITIONS) do
        if not (secure and condition == "instance") then
            self:Dropdown(KeyAt(key, "." .. condition), L["OPT_VIS_" .. condition:upper()], choices, indent)
        end
    end
    if not opts.noMouseover then self:Check(KeyAt(key, ".mouseover"), L.OPT_VIS_MOUSEOVER, indent) end
    self.layout:EndAdvanced()         -- les réglages qui suivent restent visibles
    self.layout:PopParents(1)         -- ni ne dépendent de la case « survol »
end

--- Son : preset du client (si `presetKey`), fichier importé par le joueur et bouton d'écoute.
-- `play` remplace l'écoute par défaut (preset puis fichier) pour un son sans preset.
function ModuleOptions:Sound(presetKey, fileKey, indent, play)
    play = play or function() local db = self:DB() NS.PlayPreset(db[presetKey], db[fileKey]) end
    if presetKey then
        local choices = {}
        for _, preset in ipairs(NS.SOUND_PRESET_ORDER) do
            choices[#choices + 1] = { name = L["SOUND_" .. preset:upper()] or preset, value = preset }
        end
        self:Dropdown(presetKey, L.OPT_SOUND_PRESET, choices, indent, play)
    end
    self:EditBox(fileKey, L.OPT_SOUND_FILE, 1, indent)
    self:Note(L.OPT_SOUND_FILE_NOTE, indent)
    self:Button(L.OPT_SOUND_TEST, play, indent)
end

--- « Copier les réglages depuis… » : recopie dans la table `key` les valeurs d'une table sœur
-- (clés communes seulement, sans `enabled`). sources = { {name=, value=clé} }.
function ModuleOptions:CopyFrom(key, sources, indent)
    local choices = {}
    for _, source in ipairs(sources) do
        if source.value ~= key then choices[#choices + 1] = source end
    end
    return self.layout:Dropdown(L.OPT_COPY_FROM, choices, function() return nil end, function(sourceKey)
        local targetParent, targetKey = Resolve(self:DB(), key)
        local sourceParent, sourceField = Resolve(self:DB(), sourceKey)
        local target, source = targetParent[targetKey], sourceParent[sourceField]
        for field, value in pairs(source) do
            if field ~= "enabled" and target[field] ~= nil then target[field] = NS.Database.DeepCopy(value) end
        end
        self:Changed()
        self.layout:Refresh()
    end, indent or 20)
end

--------------------------------------------------------------------------------
-- Pages générales
--------------------------------------------------------------------------------

local function BuildGeneral()
    local panel, layout = NewPage("general", L.OPT_GENERAL, L.OPT_INTRO)
    local languages = { { name = L.OPT_LANGUAGE_AUTO, value = "auto" } }
    for _, entry in ipairs(NS.LOCALE_ORDER) do
        languages[#languages + 1] = { name = entry.name, value = entry.code }
    end
    layout:Dropdown(L.OPT_LANGUAGE, languages,
        function() return NS.global.locale end,
        function(value)
            NS.global.locale = value
            NS.SetLocale(value)
            AskReload(L.MSG_LANGUAGE_RELOAD)
        end)

    layout:Title(L.OPT_APPEARANCE)
    NS.Database.bounds["theme.uiScale"] = { NS.Pixel.MIN_USER_SCALE, NS.Pixel.MAX_USER_SCALE }
    -- Préréglage : classe et faction lues pour chaque personnage ; les couleurs fixes vont dans l'accent.
    layout:Dropdown(L.OPT_ACCENT_PRESET, {
            { name = L.ACCENT_CUSTOM, value = "custom" }, { name = L.ACCENT_CLASS, value = "class" },
            { name = L.ACCENT_FACTION, value = "faction" }, { name = L.ACCENT_AEON, value = "aeon" },
            { name = L.ACCENT_BRONZE, value = "bronze" },
        },
        function() return NS.db.theme.accentPreset end,
        function(value)
            local fixed = NS.Media.ACCENT_PRESETS[value]
            if fixed then
                local accent = NS.db.theme.accent
                accent.r, accent.g, accent.b = fixed.r, fixed.g, fixed.b
                value = "custom"
            end
            NS.db.theme.accentPreset = value
            NS:Fire("THEME_CHANGED")
            layout:Refresh()
        end)
    layout:Color(L.OPT_ACCENT, function() return NS.db.theme.accent end,
        function() NS.db.theme.accentPreset = "custom"; NS:Fire("THEME_CHANGED") end)
    layout:Color(L.OPT_BACKDROP_COLOR, function() return NS.db.theme.backdrop end,
        function() NS:Fire("THEME_CHANGED") end)
    layout:Color(L.OPT_BORDER_COLOR, function() return NS.db.theme.border end,
        function() NS:Fire("THEME_CHANGED") end)
    NS.Database.bounds["theme.borderSize"] = { 1, 4 }
    layout:Slider(L.OPT_BORDER_SIZE, 1, 4, 1,
        function() return NS.db.theme.borderSize or 1 end,
        function(value) NS.db.theme.borderSize = value; NS:Fire("THEME_CHANGED") end)
    layout:Check(L.OPT_PIXEL_PERFECT,
        function() return NS.db.theme.pixelPerfect end,
        function(value) NS.db.theme.pixelPerfect = value; NS:Fire("THEME_CHANGED") end)
    layout:Hint(L.OPT_PIXEL_PERFECT_HINT)
    layout:Slider(L.OPT_UI_SCALE, NS.Pixel.MIN_USER_SCALE, NS.Pixel.MAX_USER_SCALE, 0.05,
        function() return NS.db.theme.uiScale or 1 end,
        function(value) NS.db.theme.uiScale = value; NS:Fire("THEME_CHANGED") end, nil, "%.2f")
    layout:Hint(L.OPT_UI_SCALE_HINT)
    NS.Database.bounds["theme.optionsScale"] = { 0.8, 1.5 }
    layout:Slider(L.OPT_OPTIONS_SCALE, 0.8, 1.5, 0.05,
        function() return NS.db.theme.optionsScale or 1 end,
        function(value) NS.db.theme.optionsScale = value; NS.OptionsWindow:ApplyScale() end, nil, "%.2f")

    layout:Title(L.OPT_MOVERS)
    layout:Dropdown(L.OPT_GRID, {
            { name = L.GRID_NONE, value = 0 }, { name = "16 px", value = 16 }, { name = "32 px", value = 32 },
        },
        function() return NS.db.theme.grid end,
        function(value) NS.db.theme.grid = value; NS:Fire("THEME_CHANGED") end)
    layout:Button(L.OPT_UNLOCK, function() NS:SetUnlocked(not NS.unlocked) end)
    layout:Button(L.OPT_RESET_POSITIONS, function()
        StaticPopupDialogs.AEONUI_RESET_POSITIONS.text = L.MSG_RESET_POSITIONS_CONFIRM
        StaticPopup_Show("AEONUI_RESET_POSITIONS")
    end)
    layout:Finish()
    return panel
end

-- Modules dont les textes et les barres peuvent prendre une police et une texture propres.
local MEDIA_MODULES = { "unitframes", "groupframes", "nameplateframes", "resourcebars", "swingtimer", "databars" }

local function FontChoices(inherit)
    local fonts = inherit and { { name = L.OPT_MEDIA_INHERIT, value = "inherit" } } or {}
    for _, font in ipairs(NS.GetFontList()) do
        fonts[#fonts + 1] = { name = font.name, value = font.path, font = font.path }
    end
    return fonts
end

local function TextureChoices(inherit)
    local list = NS.Media:StatusBarChoices(L.STATUSBAR_FLAT)
    if inherit then table.insert(list, 1, { name = L.OPT_MEDIA_INHERIT, value = "inherit" }) end
    return list
end

--- Polices et textures : thème commun, mode sombre, puis exception par module.
local function BuildMedia()
    local panel, layout = NewPage("media", L.OPT_MEDIA, L.OPT_MEDIA_INTRO)
    local function changed() NS:Fire("THEME_CHANGED") end
    layout:Dropdown(L.OPT_FONT, function() return FontChoices(false) end,
        function() return NS.db.theme.font end,
        function(value) NS.db.theme.font = value; changed() end)
    NS.Database.bounds["theme.fontSize"] = { 9, 18 }
    layout:Slider(L.OPT_FONT_SIZE, 9, 18, 1,
        function() return NS.db.theme.fontSize end,
        function(value) NS.db.theme.fontSize = value; changed() end)
    layout:Dropdown(L.OPT_FONT_OUTLINE, {
            { name = L.OUTLINE_NONE, value = "" }, { name = L.OUTLINE_THIN, value = "OUTLINE" },
            { name = L.OUTLINE_THICK, value = "THICKOUTLINE" },
        },
        function() return NS.db.theme.fontOutline end,
        function(value) NS.db.theme.fontOutline = value; changed() end)
    layout:Dropdown(L.OPT_STATUSBAR, function() return TextureChoices(false) end,
        function() return NS.db.theme.statusbar end,
        function(value) NS.db.theme.statusbar = value; changed() end)
    layout:Check(L.OPT_DARK_MODE, function() return NS.db.theme.darkMode end,
        function(value)
            NS.db.theme.darkMode = value
            changed()
            for _, name in ipairs(MEDIA_MODULES) do NS.Modules:Refresh(name) end   -- couleurs de vie reposées
        end)
    layout:Hint(L.OPT_DARK_MODE_HINT)
    layout:Title(L.OPT_MEDIA_BY_MODULE)
    for _, name in ipairs(MEDIA_MODULES) do
        local module = NS.Modules:Get(name)
        if module and module.title then
            local function own() return NS.db.theme.moduleMedia[name] end
            local function set(field, value)
                local media = NS.db.theme.moduleMedia
                media[name] = media[name] or {}
                media[name][field] = value ~= "inherit" and value or nil
                if not next(media[name]) then media[name] = nil end
                changed()
            end
            layout:Dropdown(module.title .. " : " .. L.OPT_FONT, function() return FontChoices(true) end,
                function() return own() and own().font or "inherit" end,
                function(value) set("font", value) end, 20)
            layout:Dropdown(module.title .. " : " .. L.OPT_STATUSBAR, function() return TextureChoices(true) end,
                function() return own() and own().statusbar or "inherit" end,
                function(value) set("statusbar", value) end, 20)
        end
    end
    layout:Finish()
    return panel
end

local function BuildModuleList()
    local panel, layout = NewPage("modules", L.OPT_MODULES, L.OPT_MODULES_HINT)
    for _, module in ipairs(NS.Modules:SortedList()) do
        if module.title then
            local name = module.name
            -- Les addons se chargent à la connexion : l'état « cédé » ne bouge plus ensuite.
            local yieldedBy = NS.Modules:YieldedBy(name)
            local title = yieldedBy and (module.title .. " " .. L.MSG_YIELDED) or module.title
            local check = layout:Check(title,
                function() return NS.db.modules[name].enabled end,
                function(value) SetModuleEnabled(name, value) end, 4)
            if yieldedBy then
                check:Disable()
                layout:Hint(L.MSG_YIELDED_HINT)
            else
                layout:Hint(module.description)
            end
        end
    end
    layout:Finish()
    return panel
end

local function BuildProfiles()
    local panel, layout = NewPage("profiles", L.OPT_PROFILES, L.OPT_PROFILES_HINT)
    layout:Dropdown(L.OPT_PROFILE_ACTIVE, function()
            local list = {}
            for _, name in ipairs(NS.Database:ListProfiles()) do list[#list + 1] = { name = name, value = name } end
            return list
        end,
        function() return NS.Database:ActiveProfileName() end,
        function(value) NS:SwitchProfile(value) end)
    layout:Button(L.OPT_PROFILE_CHARACTER, function()
        NS:SwitchProfile(NS.Database.CharacterKey(), NS.Database:ActiveProfileName())
    end)
    layout:Button(L.OPT_PROFILE_RESET, function()
        Confirm("AEONUI_PROFILE_RESET",
            string.format(L.MSG_PROFILE_RESET_CONFIRM, NS.Database:ActiveProfileName()),
            function() NS:ResetProfile() end)
    end)
    layout:Button(L.OPT_PROFILE_DELETE, function()
        local name = NS.Database:ActiveProfileName()
        if name == NS.Database.DEFAULT_PROFILE then return end
        Confirm("AEONUI_PROFILE_DELETE", string.format(L.MSG_PROFILE_DELETE_CONFIRM, name), function()
            NS:SwitchProfile(NS.Database.DEFAULT_PROFILE)
            NS:RunOutOfCombat(function()
                NS.Database:DeleteProfile(name)
                NS:BindProfileHotkeys()   -- sa touche est libérée
            end)
        end)
    end)
    -- Renommer ou dupliquer le profil actif sous le nom saisi.
    local naming = { text = "" }
    layout:EditBox(L.OPT_PROFILE_NEW_NAME,
        function() return naming.text end, function(value) naming.text = value end, 1)
    layout:Button(L.OPT_PROFILE_RENAME, function()
        local renamed = NS.Database:RenameProfile(NS.Database:ActiveProfileName(), naming.text)
        if not renamed then NS.Print(L.MSG_PROFILE_NAME_INVALID) return end
        naming.text = ""
        NS:BindProfileHotkeys()
        NS:Fire("PROFILE_CHANGED")
    end)
    layout:Button(L.OPT_PROFILE_DUPLICATE, function()
        local name = NS.Database.ValidProfileName(naming.text)
        if not name or NS.global.profiles[name] then NS.Print(L.MSG_PROFILE_NAME_INVALID) return end
        naming.text = ""
        NS:SwitchProfile(name, NS.Database:ActiveProfileName())
    end)
    layout:EditBox(L.OPT_PROFILE_HOTKEY,
        function() return NS.global.profileHotkeys[NS.Database:ActiveProfileName()] or "" end,
        function(value)
            NS.global.profileHotkeys[NS.Database:ActiveProfileName()] = value ~= "" and value or nil
            NS:BindProfileHotkeys()
        end, 1)

    -- Partage : la chaîne exportée se colle sur un autre personnage ou chez un autre joueur.
    layout:Title(L.OPT_PROFILE_SHARE)
    local transfer = { text = "" }
    layout:Note(L.OPT_PROFILE_TRANSFER_HINT)
    local box = layout:EditBox(L.OPT_PROFILE_STRING,
        function() return transfer.text end, function(value) transfer.text = value end, 10)
    -- Export partiel : thème, listes d'auras et chaque module (avec les positions de ses movers).
    local exportPick = {}
    local function Picked(section) return exportPick[section] ~= false end
    layout:Note(L.OPT_PROFILE_EXPORT_PICK)
    layout:Check(L.OPT_PROFILE_EXPORT_THEME, function() return Picked("theme") end,
        function(value) exportPick.theme = value end)
    layout:Check(L.OPT_PROFILE_EXPORT_AURAS, function() return Picked("auraLists") end,
        function(value) exportPick.auraLists = value end)
    for _, module in ipairs(NS.Modules:SortedList()) do
        if module.title then
            layout:Check(module.title, function() return Picked(module.name) end,
                function(value) exportPick[module.name] = value end, 20)
        end
    end
    layout:Button(L.OPT_PROFILE_EXPORT, function()
        local sections, all = {}, true
        for _, section in ipairs({ "theme", "auraLists" }) do
            if Picked(section) then sections[section] = true else all = false end
        end
        for _, module in ipairs(NS.Modules:List()) do
            if Picked(module.name) then sections[module.name] = true else all = false end
        end
        local source = NS.db
        if not all then
            local anchorKeys = {}
            for key, entry in pairs(NS.Movers.registry) do
                if entry.module and sections[entry.module] and NS.db.anchors[key] then anchorKeys[#anchorKeys + 1] = key end
            end
            source = NS.Database.PartialProfile(NS.db, sections, anchorKeys)
        end
        transfer.text = NS.Database.Export(source)
        layout:Refresh()
        box:SelectAll()
    end)
    layout:Button(L.OPT_PROFILE_EXPORT_ACCOUNT, function()
        local text = NS.Database.Export(NS.Database:AccountExport())
        -- Au-delà de la borne de l'import collé, la chaîne serait refusée : rien plutôt qu'un export inutilisable.
        if not NS.Database.Deserialize(text, NS.Database.PastedLimit(true)) then NS.Print(L.MSG_EXPORT_ACCOUNT_TOO_LARGE) return end
        transfer.text = text
        layout:Refresh()
        box:SelectAll()
    end)
    layout:Button(L.OPT_PROFILE_IMPORT, function()
        local text = transfer.text
        local parsed = NS.Database.Deserialize(text, NS.Database.PastedLimit(true))
        if not (parsed and parsed.account) then NS:ImportProfile(text, false) return end
        -- Export du compte : les profils de même nom sont remplacés, le joueur confirme d'abord.
        local replaced = {}
        for profileName in pairs(type(parsed.profiles) == "table" and parsed.profiles or {}) do
            local valid = NS.Database.ValidProfileName(profileName)
            if valid and NS.global.profiles[valid] then replaced[#replaced + 1] = valid end
        end
        table.sort(replaced)
        Confirm("AEONUI_IMPORT_ACCOUNT", string.format(L.MSG_IMPORT_ACCOUNT_CONFIRM, #replaced,
            #replaced > 0 and table.concat(replaced, ", ") or "-"), function() NS:ImportProfile(text, true) end)
    end)
    layout:Button(L.OPT_PROFILE_SEND, function() NS.ProfileShare:Send() end)

    -- Un profil par spécialisation : bascule automatique au changement de spé.
    layout:Title(L.OPT_PROFILE_BY_SPEC)
    layout:Note(L.OPT_PROFILE_BY_SPEC_HINT)
    local specs = NS.GetSpecList()
    if #specs == 0 then layout:Note(L.OPT_PROFILE_BY_SPEC_NONE) end
    for _, spec in ipairs(specs) do
        layout:Dropdown(spec.name, function()
                local list = { { name = L.OPT_PROFILE_BY_SPEC_OFF, value = false } }
                for _, name in ipairs(NS.Database:ListProfiles()) do list[#list + 1] = { name = name, value = name } end
                return list
            end,
            function() return NS.Database:GetSpecProfile(spec.index) or false end,
            function(value)
                NS.Database:SetSpecProfile(spec.index, value or nil)
                NS:CheckSpecProfile()
            end)
    end

    -- Un profil par contexte : prime sur la spé, bascule à l'écran de chargement, hors combat.
    layout:Title(L.OPT_PROFILE_BY_CONTEXT)
    layout:Note(L.OPT_PROFILE_BY_CONTEXT_HINT)
    for _, context in ipairs({ "world", "dungeon", "raid", "pvp" }) do
        layout:Dropdown(L["PROFILE_CONTEXT_" .. context:upper()], function()
                local list = { { name = L.OPT_PROFILE_BY_SPEC_OFF, value = false } }
                for _, name in ipairs(NS.Database:ListProfiles()) do list[#list + 1] = { name = name, value = name } end
                return list
            end,
            function() return NS.Database:GetContextProfile(context) or false end,
            function(value)
                NS.Database:SetContextProfile(context, value or nil)
                NS:CheckSpecProfile()
            end)
    end

    -- Préréglages de rôle : appliqués au profil actuel, ou dans un profil neuf pour ce personnage.
    layout:Title(L.OPT_PROFILE_ROLES)
    local rolePick = { role = "heal" }
    layout:Note(L.OPT_PROFILE_ROLE_HINT)
    layout:Dropdown(L.INSTALL_ROLE, {
            { name = L.INSTALL_ROLE_DPS, value = "dps" }, { name = L.INSTALL_ROLE_HEAL, value = "heal" },
            { name = L.INSTALL_ROLE_TANK, value = "tank" },
        },
        function() return rolePick.role end, function(value) rolePick.role = value end)
    layout:Button(L.OPT_PROFILE_ROLE_APPLY, function()
        NS:RunOutOfCombat(function() NS.Install:ApplyRole(rolePick.role) NS.Modules:RefreshAll() end)
    end)
    layout:Button(L.OPT_PROFILE_ROLE_NEW, function()
        NS:RunOutOfCombat(function()
            -- Profil déjà là : simple bascule, Apply écraserait positions et réglages du joueur.
            local name = NS.Install.ProfileName(rolePick.role)
            if NS.global.profiles[name] then NS:SwitchProfile(name) else NS.Install:Apply(rolePick.role) end
        end)
    end)
    layout:Button(L.OPT_PROFILE_ROLE_CHARACTER, function()
        NS:RunOutOfCombat(function()
            local role = rolePick.role
            -- Nom et royaume : deux homonymes sur deux royaumes ont chacun le leur.
            local name = NS.Database.CharacterKey() .. " - " .. NS.Install.ProfileName(role)
            -- Déjà créé : simple bascule, ne rien écraser.
            if NS.global.profiles[name] then NS:SwitchProfile(name) return end
            -- Copie du profil actuel, puis le rôle par-dessus (hors combat : Reload est immédiat).
            NS:SwitchProfile(name, NS.Database:ActiveProfileName())
            NS.Install:ApplyRole(role)
            NS.Modules:RefreshAll()
        end)
    end)

    -- Profils de classe : styles jouables de la classe du joueur (section absente sans classe lisible).
    local styles = NS.Install.ClassStyles()
    if #styles > 0 then
        layout:Title(L.OPT_PROFILE_CLASSES)
        local classPick = { style = styles[1] }
        layout:Note(L.OPT_PROFILE_CLASS_HINT)
        local choices = {}
        for _, style in ipairs(styles) do choices[#choices + 1] = { name = L["INSTALL_ROLE_" .. style:upper()], value = style } end
        layout:Dropdown(L.OPT_PROFILE_CLASS_STYLE, choices,
            function() return classPick.style end, function(value) classPick.style = value end)
        layout:Button(L.OPT_PROFILE_CLASS_APPLY, function()
            NS:RunOutOfCombat(function() NS.Install:ApplyClassSettings(classPick.style) end)
        end)
        layout:Button(L.OPT_PROFILE_CLASS_SWITCH, function()
            NS:RunOutOfCombat(function()
                -- Profil déjà là : simple bascule, ApplyClass écraserait positions et réglages du joueur.
                local name = NS.Install.ClassProfileName(classPick.style)
                if NS.global.profiles[name] then NS:SwitchProfile(name) else NS.Install:ApplyClass(classPick.style) end
            end)
        end)
    end
    layout:Finish()
    return panel
end

local function BuildMaintenance()
    local panel, layout = NewPage("maintenance", L.OPT_MAINTENANCE, L.OPT_MAINTENANCE_HINT)
    layout:Button(L.OPT_FIRST_RUN, function() if NS.FirstRun then NS.FirstRun:Show() end end)
    layout:Button(L.OPT_DIAG, function() SlashCmdList.AEONUI("diag") end)
    layout:Button(L.OPT_UNINSTALL, function() SlashCmdList.AEONUI("uninstall") end)
    layout:Finish()
    return panel
end

--- Pages générales, inscrites dans la fenêtre et construites à leur première ouverture
-- (tests : construction avec un addon tiers chargé).
local function BuildMain()
    Window:AddPage("general", L.OPT_GENERAL, BuildGeneral, "general")
    Window:AddPage("media", L.OPT_MEDIA, BuildMedia, "general")
    Window:AddPage("modules", L.OPT_MODULES, BuildModuleList, "general")
    Window:AddPage("profiles", L.OPT_PROFILES, BuildProfiles, "general")
    Window:AddPage("maintenance", L.OPT_MAINTENANCE, BuildMaintenance, "general")
end

--------------------------------------------------------------------------------
-- Pages des modules
--------------------------------------------------------------------------------

--- Remet les réglages d'un module aux défauts, sur place (les modules gardent leur référence).
local function ResetModule(name)
    local module, db = NS.Modules:Get(name), NS.db.modules[name]
    local enabled = db.enabled
    for key in pairs(db) do db[key] = nil end
    NS.Database.MergeDefaults(module.defaults, db)
    db.enabled = enabled
    NS.Modules:Refresh(name)
    Options:Refresh()
end
Options.ResetModule = ResetModule

--------------------------------------------------------------------------------
-- Aperçu cliquable à droite d'une page de module
--------------------------------------------------------------------------------

local PREVIEW_HEIGHT = 140
local PREVIEW_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

--- Outils de dessin passés à module:BuildPreview(p). Chaque objet a un identifiant : il est créé
-- au premier appel puis réutilisé ; p.Begin() cache tout avant de repeindre. Coordonnées en
-- pixels depuis le coin haut gauche du canevas (y vers le bas).
--   p.width, p.height : taille du canevas ; p.DB() : réglages du module ;
--   p.Fit(w, h, marge) : échelle (au plus 2) et origine (x, y) qui centrent un dessin w x h ;
--   p.Box(id, x, y, w, h, r, g, b, a, sublevel) : rectangle plein ;
--   p.Edge(id, x, y, w, h[, r, g, b, a]) : liseré de 1 px autour d'une forme, dessiné dessous ;
--   p.Bar(id, x, y, w, h, r, g, b, part) : barre sur fond sombre, remplie à `part`, texture du module ;
--   p.Icon(id, x, y, taille, texture, zoom) : icône carrée ;
--   p.Text(id, x, y, texte, taille, point) : texte (point d'ancrage, TOPLEFT par défaut) ;
--   p.ClassColor(classFile) : couleur de classe (du joueur sans argument) ;
--   p.Region(id, x, y, w, h) : cadre invisible, support d'une zone cliquable ;
--   p.Hotspot(region, hint, tab) : un clic sur `region` ouvre le réglage (ou l'onglet) dont le
--     libellé vaut `hint`, dans l'onglet `tab` si donné.
local function PreviewKit(p, canvas, owner)
    local objects, spots = {}, {}
    local function get(id, create)
        local object = objects[id]
        if not object then
            object = create()
            objects[id] = object
        end
        object:Show()
        return object
    end
    local function place(region, x, y, width, height)
        region:ClearAllPoints()
        region:SetPoint("TOPLEFT", canvas, "TOPLEFT", x, -y)
        region:SetSize(math.max(1, width), math.max(1, height))
    end
    function p.Begin()
        for _, object in pairs(objects) do object:Hide() end
        for _, spot in pairs(spots) do spot:Hide() end
    end
    function p.Fit(width, height, margin)
        margin = margin or 8
        local scale = math.min(2, (p.width - 2 * margin) / math.max(1, width), (p.height - 2 * margin) / math.max(1, height))
        return scale, (p.width - width * scale) / 2, (p.height - height * scale) / 2
    end
    function p.Box(id, x, y, width, height, r, g, b, a, sublevel)
        local box = get(id, function() return canvas:CreateTexture(nil, "ARTWORK", nil, sublevel or 0) end)
        place(box, x, y, width, height)
        box:SetVertexColor(1, 1, 1, 1)
        NS.SetSolidColor(box, r, g, b, a or 1)
        return box
    end
    --- Liseré noir derrière une forme (sous-niveau le plus bas : jamais par-dessus).
    function p.Edge(id, x, y, width, height, r, g, b, a)
        return p.Box(id, x - 1, y - 1, width + 2, height + 2, r or 0, g or 0, b or 0, a or 1, -8)
    end
    function p.Bar(id, x, y, width, height, r, g, b, part)
        local background = p.Box(id .. ":bg", x, y, width, height, 0, 0, 0, 0.7, -4)
        local fill = get(id, function() return canvas:CreateTexture(nil, "ARTWORK", nil, 1) end)
        fill:SetTexture(NS.Media:StatusBarTexture(owner))
        fill:SetVertexColor(r, g, b, 1)
        place(fill, x, y, width * (part or 1), height)
        return background
    end
    function p.Icon(id, x, y, size, texture, zoom)
        local icon = get(id, function() return canvas:CreateTexture(nil, "ARTWORK", nil, 2) end)
        icon:SetTexture(texture or PREVIEW_ICON)
        zoom = zoom or 0.07
        icon:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
        place(icon, x, y, size, size)
        return icon
    end
    function p.Text(id, x, y, text, size, point)
        local fontString = get(id, function() return canvas:CreateFontString(nil, "OVERLAY") end)
        fontString:SetFont((NS.Media:Font(owner)), math.max(6, size or 11), "OUTLINE")
        fontString:ClearAllPoints()
        fontString:SetPoint(point or "TOPLEFT", canvas, "TOPLEFT", x, -y)
        fontString:SetText(text)
        return fontString
    end
    --- Couleur de classe (`classFile`, ou celle du joueur) ; vert si illisible.
    function p.ClassColor(classFile)
        if not classFile and _G.UnitClass then
            local _, own = UnitClass("player")
            if own and not NS.IsSecret(own) then classFile = own end
        end
        if classFile then return NS.ClassColor(classFile) end
        return 0.2, 0.75, 0.2
    end
    function p.Region(id, x, y, width, height)
        local region = get(id, function() return CreateFrame("Frame", nil, canvas) end)
        place(region, x, y, width, height)
        return region
    end
    function p.Hotspot(region, hint, tab)
        local spot = spots[region]
        if not spot then
            spot = CreateFrame("Button", nil, canvas)
            spot:SetAllPoints(region)
            local glow = spot:CreateTexture(nil, "HIGHLIGHT")
            glow:SetAllPoints()
            NS.Widgets.Accented(glow, function()
                local r, g, b = NS.Media:Accent()
                NS.SetSolidColor(glow, r, g, b, 0.3)
            end)
            spot:SetScript("OnClick", function(self) Options.RevealModule(owner, self.hint, self.tab) end)
            spot:SetScript("OnEnter", function(self) NS.Widgets.ShowTooltip(self, self.hint) end)
            spot:SetScript("OnLeave", function() GameTooltip:Hide() end)
            spots[region] = spot
        end
        spot:SetFrameLevel(canvas:GetFrameLevel() + 10)
        spot.hint, spot.tab = hint, tab
        spot:Show()
        return spot
    end
end

--- Aperçu dans la colonne de droite (panel.side), décrit par module:BuildPreview(p) (outils :
-- PreviewKit), qui rend la fonction qui le repeint. Il reste visible quand les réglages défilent ;
-- repeint à chaque réglage changé et au changement de thème.
local function BuildPreview(module, o, layout, preview)
    local height = module.previewHeight or PREVIEW_HEIGHT
    local width = PREVIEW_COLUMN - 16
    local background = preview:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    NS.SetSolidColor(background, 0, 0, 0, 0.3)
    local canvas = CreateFrame("Frame", nil, preview)
    canvas:SetPoint("TOPLEFT", preview, "TOPLEFT", 8, -8)
    canvas:SetSize(width, height)
    local hint = preview:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", canvas, "BOTTOMLEFT", 0, -8)
    hint:SetWidth(width)
    hint:SetJustifyH("LEFT")
    hint:SetText(L.OPT_PREVIEW_HINT)
    preview:SetHeight(height + 24 + (hint:GetStringHeight() or 12))
    local p = { canvas = canvas, width = width, height = height }
    function p.DB() return o:DB() end
    PreviewKit(p, canvas, module.name)
    local paint = module:BuildPreview(p)
    o.preview = paint
    layout.refreshers[#layout.refreshers + 1] = paint
    NS:On("THEME_CHANGED", function() if preview:IsVisible() then paint() end end)
    preview:SetScript("OnShow", function()
        NS.Widgets.Tip(canvas, "preview", L.OPT_TIP_PREVIEW)
    end)
    preview:SetScript("OnHide", function() NS.Widgets.HideTip() end)
    return preview
end

local function BuildModulePage(module)
    local panel, layout = NewPage(module.name, module.title, module.description,
        module.BuildPreview and PREVIEW_COLUMN)
    local name = module.name
    local o = setmetatable({ name = name, layout = layout }, ModuleOptions)
    if module.BuildPreview then BuildPreview(module, o, layout, panel.side) end
    -- Case du module à droite du titre : toute la page est grisée quand elle est décochée.
    local label = string.format(L.OPT_ENABLE, module.title)
    local function get() return NS.db.modules[name].enabled end
    local enable = NS.Widgets.CheckBox(panel.header, 18)
    enable:SetPoint("LEFT", panel.titleText, "LEFT", (panel.titleText:GetStringWidth() or 0) + 14, 0)
    enable:SetScript("OnClick", function(self)
        if layout.refreshing then return end
        SetModuleEnabled(name, self:GetChecked() and true or false)
        self.Paint()
        layout:UpdateDependencies()
    end)
    if enable.SetMotionScriptsWhileDisabled then enable:SetMotionScriptsWhileDisabled(true) end
    local yielded = NS.Modules:YieldedBy(name)
    enable:SetScript("OnEnter", function(self)
        NS.Widgets.ShowTooltip(self, yielded and (label .. "\n|cffcccccc" .. L.MSG_YIELDED_HINT .. "|r") or label)
    end)
    enable:SetScript("OnLeave", function() GameTooltip:Hide() end)
    if yielded then enable:Disable() end
    layout.refreshers[#layout.refreshers + 1] = function() enable:SetChecked(get() and true or false) end
    layout.parents[#layout.parents + 1] = { indent = -1, get = get }   -- jamais retiré par un retrait
    layout:Label(label, enable)
    if module.BuildOptions then module:BuildOptions(o) end
    layout:Finish()
    return panel
end

--------------------------------------------------------------------------------
-- Recherche : libellés de toutes les pages, accents ignorés.
--------------------------------------------------------------------------------

local MAX_RESULTS = 40

--- Pages dans l'ordre de la fenêtre : { key, title }.
local function SearchablePages(onlyKey)
    local list = {}
    for _, key in ipairs(Window.order) do
        if not onlyKey or key == onlyKey then list[#list + 1] = { key = key, title = Window.pages[key].title } end
    end
    return list
end

--- Texte comparable : minuscules, accents et ponctuation retirés (« l'agro » = « l agro »).
local function Normalize(text) return (NS.Modules.SortKey(text):gsub("%p", " ")) end

--- Chaque mot de `words` est-il dans `text` ?
local function HasAll(text, words)
    for _, word in ipairs(words) do
        if not text:find(word, 1, true) then return false end
    end
    return true
end

local function HasAny(text, words)
    for _, word in ipairs(words) do
        if text:find(word, 1, true) then return true end
    end
    return false
end

--- { { module = clé de page, title = titre, label = libellé trouvé ou nil, entry = widget } },
-- au plus MAX_RESULTS. Chaque mot de la requête doit figurer dans « page > onglet > libellé »,
-- dans n'importe quel ordre (« haut fps » trouve « Barre du haut > Garder FPS… ») ; le libellé
-- lui-même doit en contenir au moins un. Sinon, la page seule si son titre ou sa description
-- contient tous les mots.
function Options.Search(query, onlyKey)
    local words = {}
    for word in Normalize(query):gmatch("%S+") do words[#words + 1] = word end
    local results = {}
    if #table.concat(words) < 2 then return results end
    -- ponytail: index = libellés des pages construites ; la première recherche construit les autres
    -- d'un coup. Index sans cadres (libellés relevés à part) si ce pic se sent en jeu.
    for _, key in ipairs(Window.order) do
        if not onlyKey or key == onlyKey then Window:Ensure(key) end
    end
    local function add(result)
        if #results < MAX_RESULTS then results[#results + 1] = result end
    end
    for _, page in ipairs(SearchablePages(onlyKey)) do
        local layout = layouts[page.key]
        local module = NS.Modules:Get(page.key)
        local title = Normalize(page.title)
        local found = false
        for _, entry in ipairs(layout and layout.labels or {}) do
            -- Même libellé dans plusieurs onglets (Largeur par unité) : l'onglet le distingue.
            local label = entry.tab and (layout.tabs[entry.tab].label .. " > " .. entry.text) or entry.text
            local text = Normalize(label)
            if HasAny(text, words) and HasAll(title .. " " .. text, words) then
                add({ module = page.key, title = page.title, label = label, entry = entry })
                found = true
            end
        end
        if not found and HasAll(title .. " " .. Normalize(module and module.description or ""), words) then
            add({ module = page.key, title = page.title })
        end
    end
    return results
end

--- Surligne brièvement un widget (réglage trouvé par la recherche).
local function Flash(layout, frame)
    local glow = layout.flash
    if not glow then
        glow = layout.root:CreateTexture(nil, "BACKGROUND")
        glow.timer = CreateFrame("Frame", nil, layout.root)
        glow.timer:Hide()
        glow.timer:SetScript("OnUpdate", function(self, elapsed)
            self.left = self.left - elapsed
            glow:SetAlpha(math.max(0, self.left / 1.5))
            if self.left <= 0 then self:Hide() glow:Hide() end
        end)
        layout.flash = glow
    end
    local r, g, b = NS.Media:Accent()
    NS.SetSolidColor(glow, r, g, b, 0.35)
    glow:ClearAllPoints()
    -- Grille : la ligne du réglage entière ; sinon le widget, sur la largeur de la page.
    local row = frame.gridRow
    if row then
        glow:SetParent(row)
        glow:SetAllPoints(row)
    else
        glow:SetParent(layout.root)
        glow:SetPoint("TOPLEFT", frame, "TOPLEFT", -6, 6)
        glow:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -6, -6)
        glow:SetWidth(layout.width)
    end
    glow:SetAlpha(1)
    glow:Show()
    glow.timer.left = 1.5
    glow.timer:Show()
end

--- Ouvre la page d'un résultat et amène son réglage à l'écran. `typing` (recherche en cours de
-- frappe) : un réglage masqué par le mode simple ne fait pas basculer la fenêtre.
function Options.Reveal(result, typing)
    Window:Show(result.module)
    local layout, scroll = layouts[result.module], scrolls[result.module]
    if not (result.entry and result.entry.frame and layout) then return end
    -- Réglage avancé trouvé en mode simple : la fenêtre passe en mode avancé pour le montrer.
    if layout:ModeHidden(result.entry) then
        if typing then return end
        Options.SetMode("advanced")
    end
    local offset = layout:OffsetOf(result.entry)
    -- Onglet changé : la hauteur défilable est à recalculer avant de la lire.
    if scroll.UpdateScrollChildRect then scroll:UpdateScrollChildRect() end
    local range = scroll:GetVerticalScrollRange() or 0
    scroll:SetVerticalScroll(math.max(0, math.min(range, offset - 60)))
    -- Case de l'en-tête : hors de la zone défilante, déjà visible, pas de surlignage.
    local frame = result.entry.frame
    if layout.grid and not (frame.gridRow or frame.layoutY) then return end
    Flash(layout, frame)
end

--- Ouvre la page d'un module et surligne le réglage dont l'onglet ou le libellé vaut `hint`
-- (clic droit sur un mover : son libellé ; aperçu), dans l'onglet `inTab` si donné, sinon le
-- premier réglage de la page.
function Options.RevealModule(name, hint, inTab)
    Window:Show(name)
    local layout = layouts[name]
    local labels = layout and layout.labels or {}
    local wanted = hint and Normalize(hint)
    local wantedTab = inTab and Normalize(inTab)
    local chosen
    for _, entry in ipairs(labels) do
        local tab = entry.tab and layout.tabs[entry.tab].label
        local tabMatches = not wantedTab or (tab and Normalize(tab) == wantedTab)
        if wanted and tabMatches and ((tab and Normalize(tab) == wanted) or Normalize(entry.text) == wanted) then
            chosen = entry
            break
        end
    end
    if not chosen then   -- premier réglage de la grille (pas la case de l'en-tête)
        for _, entry in ipairs(labels) do
            if entry.frame and (entry.frame.gridRow or entry.frame.layoutY) then chosen = entry break end
        end
    end
    if chosen then Options.Reveal({ module = name, entry = chosen }) end
end

--- Ouvre la page d'un module.
function Options.OpenModule(name) Window:Show(name) end

--- Ouvre la fenêtre (/aeon) ; sans page demandée, un second appel la ferme.
function Options:Open(key)
    if not key and Window:IsShown() then Window:Hide() return end
    Window:Show(key)
end

function Options:BuildMain() return BuildMain() end

function Options:Refresh()
    for _, layout in pairs(layouts) do layout:Refresh() end
    Window:RenderList()
end

--- Mode de la fenêtre : "simple" (réglages avancés masqués) ou "advanced". Pages déjà construites replacées.
function Options.SetMode(mode)
    NS.global.optionsMode = mode
    for key, layout in pairs(layouts) do
        layout:Reflow()
        scrolls[key]:SetVerticalScroll(0)
    end
    Window:PaintMode()
end

function Options:GetLayout(key)
    if not layouts[key] then Window:Ensure(key) end
    return layouts[key]
end

Window.StateOf = function(key)
    local module = NS.Modules:Get(key)
    if not module then return nil end
    if NS.Modules:IsYielded(key) then return "yielded" end
    return module.enabled and "on" or "off"
end

-- Groupes de la liste de gauche ; un module absent d'ici va dans le dernier groupe.
local MODULE_GROUPS = {
    frames = { "unitframes", "frames", "groupframes", "nameplateframes", "nameplates", "resourcebars", "gcdbar",
               "swingtimer", "cotank", "clickcast" },
    combat = { "actionbars", "cooldownmanager", "cooldownbars", "aurabars", "tracker", "raidcooldowns", "reminders",
               "alerts", "movementalert", "radialmenu" },
    interface = { "topbar", "datapanels", "databars", "minimap", "chat", "chatbubbles", "questtracker", "bags", "bank",
                  "loot", "cursor", "blizzardframes", "movablewindows", "skin", "interface", "gear" },
    qol = { "automation", "afk", "groupfinder", "raidutility" },
}
local groupByModule = {}
for group, names in pairs(MODULE_GROUPS) do
    for _, name in ipairs(names) do groupByModule[name] = group end
end
Window.GroupOf = function(key) return groupByModule[key] end

Window.ResetOf = function(key)
    local module = NS.Modules:Get(key)
    if not module then return nil end
    return L.OPT_RESET_MODULE, function()
        Confirm("AEONUI_MODULE_RESET", string.format(L.MSG_RESET_MODULE_CONFIRM, module.title),
            function() ResetModule(key) end)
    end
end

NS.Widgets.TipSeen = function(key) return NS.global ~= nil and NS.global.tipsSeen[key] == true end
NS.Widgets.MarkTipSeen = function(key) if NS.global then NS.global.tipsSeen[key] = true end end
NS.Widgets.SimpleMode = function() return NS.global ~= nil and NS.global.optionsMode == "simple" end

-- Un module activé ailleurs, un changement de profil : resynchroniser les cases et les repères.
NS:On("MODULE_TOGGLED", function() Options:Refresh() end)
NS:On("PROFILE_CHANGED", function() Options:Refresh() end)
-- Mode déplacement : la fenêtre cacherait les calques ; la barre d'outils prend le relais.
NS:On("UNLOCK", function(unlocked) if unlocked then Window:Hide() end end)

--- Options > AddOns > AeonUI : un bouton vers la fenêtre.
local function BuildBlizzardPanel()
    local panel = CreateFrame("Frame", "AeonUIOptionsLauncher")
    local layout = NS.Widgets.NewLayout(panel, 16, PAGE_WIDTH)
    layout:Header("|cff3fa9f5Aeon|rUI")
    layout:Note(L.OPT_LAUNCHER_HINT)
    -- Pas de HideUIPanel : appelé par l'addon, il contamine le gestionnaire de panneaux, et
    -- tout panneau ouvert ensuite (Edit Mode) tourne contaminé. La fenêtre passe au-dessus.
    layout:Button(L.OPT_OPEN_WINDOW, function() Window:Show() end)
    return panel
end

--------------------------------------------------------------------------------
-- Bouton dans le menu Échap : sous Options (et Boutique), sections suivantes décalées.
--------------------------------------------------------------------------------

local MENU_TITLE = "|cff3fa9f5Aeon|rUI"
local MENU_HEIGHT = 35

-- Le menu reste ouvert sous la fenêtre : HideUIPanel contaminerait l'Edit Mode (voir plus haut).
local function ClickGameMenu()
    Options:Open()
end

local function Nudge(button)
    local point, relTo, relPoint, x, y = button:GetPoint()
    if point then button:SetPoint(point, relTo, relPoint, x, (y or 0) - MENU_HEIGHT) end
end

--- Menu du moteur récent (buttonPool, Layout) : repositionné à chaque Layout.
local function PositionModernButton(menu)
    local button = menu.AeonUI
    local firstSection = { [_G.GAMEMENU_OPTIONS or ""] = 1, [_G.BLIZZARD_STORE or ""] = 2 }
    local anchorIndex = (_G.StoreEnabled and StoreEnabled() and 2) or 1
    for other in menu.buttonPool:EnumerateActive() do
        local index = firstSection[other:GetText() or ""]
        if index == anchorIndex then
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", other, "BOTTOMLEFT", 0, -10)
        elseif not index then
            Nudge(other)
        end
    end
    menu:SetHeight(menu:GetHeight() + MENU_HEIGHT)
end

--- Menu Classic (GameMenuButton*) : inséré avant Déconnexion.
local function PositionClassicButton()
    local menu, logout = GameMenuFrame, _G.GameMenuButtonLogout
    local button = menu.AeonUI
    local _, relTo, _, _, offY = logout:GetPoint()
    if relTo ~= button then
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", relTo, "BOTTOMLEFT", 0, -1)
        logout:ClearAllPoints()
        logout:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, offY)
    end
    menu:SetHeight(menu:GetHeight() + logout:GetHeight() - 4)
end

function Options.SetupGameMenu()
    local menu = _G.GameMenuFrame
    if not menu or menu.AeonUI then return end
    local button
    if menu.buttonPool and menu.Layout then
        button = CreateFrame("Button", "AeonUI_GameMenuButton", menu, "MainMenuFrameButtonTemplate")
        button:SetSize(200, MENU_HEIGHT)
        menu.AeonUI = button
        hooksecurefunc(menu, "Layout", PositionModernButton)
    elseif _G.GameMenuButtonLogout and _G.GameMenuFrame_UpdateVisibleButtons then
        button = CreateFrame("Button", "AeonUI_GameMenuButton", menu, "GameMenuButtonTemplate")
        button:SetSize(GameMenuButtonLogout:GetSize())
        menu.AeonUI = button
        hooksecurefunc("GameMenuFrame_UpdateVisibleButtons", PositionClassicButton)
    else
        return
    end
    button:SetText(MENU_TITLE)
    button:SetScript("OnClick", ClickGameMenu)
end

NS:On("LOGIN", Options.SetupGameMenu)

NS:On("PROFILE_READY", function()
    -- Libellés des groupes lus ici : la langue est posée.
    Window.groups = {
        { key = "frames", label = L.OPT_GROUP_FRAMES }, { key = "combat", label = L.OPT_GROUP_COMBAT },
        { key = "interface", label = L.OPT_GROUP_INTERFACE }, { key = "qol", label = L.OPT_GROUP_QOL },
    }
    BuildMain()
    -- Pages inscrites seulement : chacune est construite à sa première ouverture.
    for _, module in ipairs(NS.Modules:SortedList()) do
        if module.title then
            Window:AddPage(module.name, module.title, function() return BuildModulePage(module) end, "modules")
        end
    end
    NS.RegisterOptionsPanel(BuildBlizzardPanel(), "AeonUI")
end)

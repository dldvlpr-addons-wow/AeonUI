-- Config/Options.lua
-- Pages de la fenêtre d'options (Config/OptionsWindow.lua) :
--   * pages générales : Général (langue, apparence, cadres mobiles), Modules (interrupteurs),
--     Profils (profil actif, partage, préréglages de rôle), Maintenance ;
--   * une page par module : titre, explication, « Activer », « Réinitialiser ce module », puis ce
--     que le module décrit lui-même dans module:BuildOptions(o).
-- Options > AddOns > AeonUI ne garde qu'un bouton qui ouvre la fenêtre.
-- Les getters relisent NS.db à chaque appel : changer de profil remplace la table.
local _, NS = ...
local L = NS.L
local Window = NS.OptionsWindow

local Options = {}
NS.Options = Options

local PAGE_WIDTH = 600

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

--- Propose /reload (module coupé qui ne rend ses cadres Blizzard qu'au rechargement, langue).
local function AskReload(message)
    StaticPopupDialogs.AEONUI_RELOAD = {
        text = "%s", button1 = L.OPT_RELOAD_NOW, button2 = L.OPT_LATER, OnAccept = function() ReloadUI() end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
    StaticPopup_Show("AEONUI_RELOAD", message)
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

--- Page scrollable : la hauteur visible dépend de la fenêtre.
local function NewPage(key)
    local panel = CreateFrame("Frame", "AeonUIOptions" .. key)
    panel:Hide()
    local scroll = CreateFrame("ScrollFrame", nil, panel)
    scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -8, 0)
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
    scroll:SetScript("OnSizeChanged", function(_, width) content:SetWidth(width) end)
    local layout = NS.Widgets.NewLayout(content, 16, PAGE_WIDTH)
    -- Onglet changé : la page repart du haut (la hauteur change).
    layout.OnTabSelected = function() scroll:SetVerticalScroll(0) end
    panel:SetScript("OnShow", function() layout:Refresh() end)
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

function ModuleOptions:Getter(key)
    return function() local t, k = Resolve(self:DB(), key) return t[k] end
end

function ModuleOptions:Setter(key, after)
    return function(value)
        local t, k = Resolve(self:DB(), key)
        t[k] = value
        NS.Modules:Refresh(self.name)
        if after then after(value) end
    end
end

function ModuleOptions:Check(key, label, indent, after)
    return self.layout:Check(label, self:Getter(key), self:Setter(key, after), indent or 20)
end

function ModuleOptions:Slider(key, label, minValue, maxValue, step, indent, format)
    -- Bornes gardées pour l'import : un profil reçu ne sort pas des limites du curseur.
    NS.Database.bounds["modules." .. self.name .. "." .. key] = { minValue, maxValue }
    return self.layout:Slider(label, minValue, maxValue, step, self:Getter(key), self:Setter(key),
        indent or 20, format)
end

function ModuleOptions:Dropdown(key, label, choices, indent, after)
    return self.layout:Dropdown(label, choices, self:Getter(key), self:Setter(key, after), indent or 20)
end

function ModuleOptions:Color(key, label, indent)
    return self.layout:Color(label, self:Getter(key), function() NS.Modules:Refresh(self.name) end, indent or 20)
end

function ModuleOptions:Title(text) return self.layout:Title(text) end
function ModuleOptions:Tab(label) return self.layout:Tab(label) end
function ModuleOptions:Note(text, indent) return self.layout:Note(text, indent or 20) end
function ModuleOptions:Hint(text) return self.layout:Hint(text) end
function ModuleOptions:Button(label, onClick, indent) return self.layout:Button(label, onClick, indent or 20) end
function ModuleOptions:EditBox(key, label, lines, indent)
    return self.layout:EditBox(label, self:Getter(key), self:Setter(key), lines, indent or 20)
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
        NS.Modules:Refresh(self.name)
        self.layout:Refresh()
    end, indent or 20)
end

--------------------------------------------------------------------------------
-- Pages générales
--------------------------------------------------------------------------------

local function BuildGeneral()
    local panel, layout = NewPage("general")
    layout:Header(L.OPT_GENERAL)
    layout:Note(L.OPT_INTRO)
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
    layout:Dropdown(L.OPT_FONT, function()
            local fonts = {}
            for _, font in ipairs(NS.GetFontList()) do
                fonts[#fonts + 1] = { name = font.name, value = font.path, font = font.path }
            end
            return fonts
        end,
        function() return NS.db.theme.font end,
        function(value) NS.db.theme.font = value; NS:Fire("THEME_CHANGED") end)
    NS.Database.bounds["theme.fontSize"] = { 9, 18 }
    NS.Database.bounds["theme.uiScale"] = { NS.Pixel.MIN_USER_SCALE, NS.Pixel.MAX_USER_SCALE }
    layout:Slider(L.OPT_FONT_SIZE, 9, 18, 1,
        function() return NS.db.theme.fontSize end,
        function(value) NS.db.theme.fontSize = value; NS:Fire("THEME_CHANGED") end)
    layout:Dropdown(L.OPT_FONT_OUTLINE, {
            { name = L.OUTLINE_NONE, value = "" }, { name = L.OUTLINE_THIN, value = "OUTLINE" },
            { name = L.OUTLINE_THICK, value = "THICKOUTLINE" },
        },
        function() return NS.db.theme.fontOutline end,
        function(value) NS.db.theme.fontOutline = value; NS:Fire("THEME_CHANGED") end)
    -- Texture des barres : seulement avec LibSharedMedia, sinon la texture plate suffit.
    local LSM = _G.LibStub and LibStub("LibSharedMedia-3.0", true)
    if LSM then
        layout:Dropdown(L.OPT_STATUSBAR, function()
                local list = { { name = L.STATUSBAR_FLAT, value = "" } }
                for _, name in ipairs(LSM:List("statusbar") or {}) do
                    list[#list + 1] = { name = name, value = name, texture = LSM:Fetch("statusbar", name, true) }
                end
                return list
            end,
            function() return NS.db.theme.statusbar end,
            function(value) NS.db.theme.statusbar = value; NS:Fire("THEME_CHANGED") end)
    end
    layout:Color(L.OPT_ACCENT, function() return NS.db.theme.accent end,
        function() NS:Fire("THEME_CHANGED") end)
    layout:Color(L.OPT_BACKDROP_COLOR, function() return NS.db.theme.backdrop end,
        function() NS:Fire("THEME_CHANGED") end)
    layout:Color(L.OPT_BORDER_COLOR, function() return NS.db.theme.border end,
        function() NS:Fire("THEME_CHANGED") end)
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

local function BuildModuleList()
    local panel, layout = NewPage("modules")
    layout:Header(L.OPT_MODULES)
    layout:Note(L.OPT_MODULES_HINT)
    for _, module in ipairs(NS.Modules:SortedList()) do
        if module.title then
            local name = module.name
            -- Les addons se chargent à la connexion : l'état « cédé » ne bouge plus ensuite.
            local yieldedBy = NS.Modules:YieldedBy(name)
            local title = yieldedBy and (module.title .. " " .. string.format(L.MSG_YIELDED, yieldedBy)) or module.title
            local check = layout:Check(title,
                function() return NS.db.modules[name].enabled end,
                function(value) SetModuleEnabled(name, value) end, 4)
            if yieldedBy then
                check:Disable()
                layout:Hint(string.format(L.MSG_YIELDED_HINT, yieldedBy, yieldedBy))
            else
                layout:Hint(module.description)
            end
        end
    end
    layout:Finish()
    return panel
end

local function BuildProfiles()
    local panel, layout = NewPage("profiles")
    layout:Header(L.OPT_PROFILES)
    layout:Note(L.OPT_PROFILES_HINT)
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
            NS:RunOutOfCombat(function() NS.Database:DeleteProfile(name) end)
        end)
    end)

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
    layout:Button(L.OPT_PROFILE_IMPORT, function() NS:ImportProfile(transfer.text) end)
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
    layout:Finish()
    return panel
end

local function BuildMaintenance()
    local panel, layout = NewPage("maintenance")
    layout:Header(L.OPT_MAINTENANCE)
    layout:Note(L.OPT_MAINTENANCE_HINT)
    layout:Button(L.OPT_FIRST_RUN, function() if NS.FirstRun then NS.FirstRun:Show() end end)
    layout:Button(L.OPT_DIAG, function() SlashCmdList.AEONUI("diag") end)
    layout:Button(L.OPT_UNINSTALL, function() SlashCmdList.AEONUI("uninstall") end)
    layout:Finish()
    return panel
end

--- Pages générales, inscrites dans la fenêtre (tests : construction avec un addon tiers chargé).
local function BuildMain()
    Window:AddPage("general", L.OPT_GENERAL, BuildGeneral(), "general")
    Window:AddPage("modules", L.OPT_MODULES, BuildModuleList(), "general")
    Window:AddPage("profiles", L.OPT_PROFILES, BuildProfiles(), "general")
    Window:AddPage("maintenance", L.OPT_MAINTENANCE, BuildMaintenance(), "general")
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

local function BuildModulePage(module)
    local panel, layout, content = NewPage(module.name)
    local name = module.name
    -- Titre tronqué avant le bouton de droite.
    local header = layout:Header(module.title)
    header:SetWidth(PAGE_WIDTH - 190)
    header:SetJustifyH("LEFT")
    if header.SetWordWrap then header:SetWordWrap(false) end
    local reset = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    reset:SetSize(180, 22)
    reset:SetPoint("TOPRIGHT", content, "TOPLEFT", layout.x + PAGE_WIDTH, -16)
    reset:SetText(L.OPT_RESET_MODULE)
    NS.Widgets.FitText(reset, 180)
    header:SetWidth(PAGE_WIDTH - reset:GetWidth() - 10)
    reset:SetScript("OnClick", function()
        Confirm("AEONUI_MODULE_RESET", string.format(L.MSG_RESET_MODULE_CONFIRM, module.title),
            function() ResetModule(name) end)
    end)
    layout:Note(module.description)
    -- « Activer » au premier niveau : tout le reste de la page est grisé quand il est décoché.
    local yieldedBy = NS.Modules:YieldedBy(name)
    local enable = layout:Check(string.format(L.OPT_ENABLE, module.title),
        function() return NS.db.modules[name].enabled end,
        function(value) SetModuleEnabled(name, value) end)
    if yieldedBy then
        enable:Disable()
        layout:Hint(string.format(L.MSG_YIELDED_HINT, yieldedBy, yieldedBy))
    end
    if module.BuildOptions then
        module:BuildOptions(setmetatable({ name = name, layout = layout }, ModuleOptions))
    end
    layout:Finish()
    Window:AddPage(name, module.title, panel, "modules")
end

--------------------------------------------------------------------------------
-- Recherche : libellés de toutes les pages, accents ignorés.
--------------------------------------------------------------------------------

local MAX_RESULTS = 40

--- Pages dans l'ordre de la fenêtre : { key, title }.
local function SearchablePages()
    local list = {}
    for _, key in ipairs(Window.order) do
        list[#list + 1] = { key = key, title = Window.pages[key].title }
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
function Options.Search(query)
    local words = {}
    for word in Normalize(query):gmatch("%S+") do words[#words + 1] = word end
    local results = {}
    if #table.concat(words) < 2 then return results end
    local function add(result)
        if #results < MAX_RESULTS then results[#results + 1] = result end
    end
    for _, page in ipairs(SearchablePages()) do
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
    glow:SetPoint("TOPLEFT", frame, "TOPLEFT", -6, 6)
    glow:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -6, -6)
    glow:SetWidth(layout.width)
    glow:SetAlpha(1)
    glow:Show()
    glow.timer.left = 1.5
    glow.timer:Show()
end

--- Ouvre la page d'un résultat et amène son réglage à l'écran.
function Options.Reveal(result)
    Window:Show(result.module)
    local layout, scroll = layouts[result.module], scrolls[result.module]
    if not (result.entry and result.entry.frame and layout) then return end
    local offset = layout:OffsetOf(result.entry)
    -- Onglet changé : la hauteur défilable est à recalculer avant de la lire.
    if scroll.UpdateScrollChildRect then scroll:UpdateScrollChildRect() end
    local range = scroll:GetVerticalScrollRange() or 0
    scroll:SetVerticalScroll(math.max(0, math.min(range, offset - 60)))
    Flash(layout, result.entry.frame)
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

function Options:GetLayout(key) return layouts[key] end

Window.StateOf = function(key)
    local module = NS.Modules:Get(key)
    if not module then return nil end
    if NS.Modules:IsYielded(key) then return "yielded" end
    return module.enabled and "on" or "off"
end

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
-- Bouton dans le menu Échap, comme ElvUI : sous Options (et Boutique), sections suivantes
-- décalées. ElvUI chargé aussi : le nôtre se range sous le sien.
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
        if index == anchorIndex and not menu.ElvUI then
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", other, "BOTTOMLEFT", 0, -10)
        elseif not index then
            Nudge(other)
        end
    end
    if menu.ElvUI then
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", menu.ElvUI, "BOTTOMLEFT", 0, 0)
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
    BuildMain()
    for _, module in ipairs(NS.Modules:SortedList()) do
        if module.title then BuildModulePage(module) end
    end
    NS.RegisterOptionsPanel(BuildBlizzardPanel(), "AeonUI")
end)

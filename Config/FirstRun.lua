-- Config/FirstRun.lua
-- Assistant d'installation en cinq pages : Installation un clic, Modules, Disposition (Edit
-- Mode), Cooldown Manager, CVars recommandées. Les pages 1 et 3 à 5 agissent au clic (rien à
-- mémoriser) ; seule la page Modules attend « Terminer ». Réouvrable par /aeon setup ou depuis les options.
local _, NS = ...
local L = NS.L

local FirstRun = {}
NS.FirstRun = FirstRun

local SIDEBAR_WIDTH = 180
local CONTENT_WIDTH = 720

-- CVars proposées à la page 4. Aucune n'est déjà gérée par Modules/Interface.lua : un seul
-- propriétaire par CVar. Toutes passent par NS.CVars, donc réversibles.
local RECOMMENDED_CVARS = {
    { name = "nameplateShowEnemies",        value = "1",   label = "SETUP_CVAR_NP_ENEMIES" },
    { name = "nameplateMotion",             value = "1",   label = "SETUP_CVAR_NP_STACK" },
    { name = "nameplateMaxDistance",        value = "60",  label = "SETUP_CVAR_NP_DISTANCE" },
    { name = "cameraDistanceMaxZoomFactor", value = "2.6", label = "SETUP_CVAR_CAMERA" },
    { name = "autoLootDefault",             value = "1",   label = "SETUP_CVAR_AUTOLOOT" },
    { name = "ffxGlow",                     value = "0",   label = "SETUP_CVAR_GLOW" },
}
FirstRun.RECOMMENDED_CVARS = RECOMMENDED_CVARS

local frame
local pages = {}          -- { key, title, build(layout), frame, layout }
local current = 1
local choices = {}        -- [nom du module] = bool, appliqué seulement à « Terminer »
local scratch = { editMode = "", cooldown = "", preset = "complete", role = "none" }   -- zones de texte et choix

local function Report(ok, reason)
    if ok then NS.Print(L.SETUP_APPLIED) return end
    NS.Print(L["SETUP_ERR_" .. string.upper(reason or "absent")] or L.SETUP_ERR_ABSENT)
end

--- Case liée à une CVar : cochée = valeur voulue posée (origine gardée), décochée = origine rendue.
local function CVarCheck(layout, name, value, label)
    if not NS.CVars:Exists(name) then return end
    local function same(current)
        -- Le client peut rendre "2.600000" pour "2.6" : comparer en nombre quand c'est possible.
        return current == value or (tonumber(current) ~= nil and tonumber(current) == tonumber(value))
    end
    layout:Check(label,
        -- Cochée = « AeonUI pose cette valeur » ; une CVar déjà à cette valeur reste décochée.
        function() return NS.CVars:IsChanged(name) and same(NS.CVars:Get(name)) end,
        function(checked)
            if checked then NS.CVars:Set(name, value) else NS.CVars:Restore(name) end
        end)
end

--- Trio Appliquer la disposition livrée / zone de texte / Importer / Exporter.
local function LayoutTools(layout, key, preset, import, export, canExport, noneMessages)
    local apply = layout:Button(L.SETUP_PRESET_APPLY, function()
        NS:RunOutOfCombat(function() Report(import(preset, "AeonUI")) end)
    end)
    if preset == "" then apply:Disable() end
    local box = layout:EditBox(L.SETUP_LAYOUT_STRING,
        function() return scratch[key] end, function(value) scratch[key] = value end, 10)
    layout:Button(L.SETUP_IMPORT, function()
        NS:RunOutOfCombat(function() Report(import(scratch[key], "AeonUI")) end)
    end)
    if canExport then
        layout:Button(L.SETUP_EXPORT, function()
            local text, reason = export()
            if not text then
                NS.Print((noneMessages and noneMessages[reason or "default"]) or L.SETUP_EXPORT_NONE)
                return
            end
            scratch[key] = text
            layout:Refresh()
            box:SelectAll()
        end)
    end
end

--------------------------------------------------------------------------------
-- Pages
--------------------------------------------------------------------------------

pages[1] = { key = "install", titleKey = "SETUP_PAGE_INSTALL", build = function(page)
    local layout = NS.Widgets.NewLayout(page, 20, CONTENT_WIDTH)
    layout:Header(L.FIRST_RUN_TITLE)
    layout:Note(L.INSTALL_HINT)
    for _, role in ipairs({ "dps", "heal", "tank" }) do
        layout:Button(string.format(L.INSTALL_ROLE_BUTTON, NS.Install.ProfileName(role)), function()
            NS:RunOutOfCombat(function()
                NS.Install:Apply(role)
                for _, module in ipairs(NS.Modules:List()) do choices[module.name] = NS.db.modules[module.name].enabled end
            end)
        end)
        layout:Note(L["INSTALL_ROLE_" .. role:upper() .. "_DESC"], 28)
    end
    -- Confort seulement : les cadres Blizzard restent, profil actuel, sans rôle.
    layout:Button(L.INSTALL_PRESET_LIGHT, function()
        NS:RunOutOfCombat(function()
            NS.Install:ApplyPreset("light")
            for _, module in ipairs(NS.Modules:List()) do choices[module.name] = NS.db.modules[module.name].enabled end
        end)
    end)
    layout:Note(L.INSTALL_NOTE)
    return { layout }
end }

pages[2] = { key = "modules", titleKey = "SETUP_PAGE_MODULES", build = function(page)
    local header = NS.Widgets.NewLayout(page, 20, CONTENT_WIDTH)
    header:Header(L.FIRST_RUN_TITLE)
    header:Note(L.FIRST_RUN_INTRO)
    -- Deux colonnes : douze modules empilés dépasseraient la hauteur d'un petit écran.
    local columns = { NS.Widgets.NewLayout(page, 20, 340), NS.Widgets.NewLayout(page, 380, 340) }
    local list = NS.Modules:SortedList()
    local half = math.ceil(#list / 2)
    for i, module in ipairs(list) do
        local column = columns[i <= half and 1 or 2]
        if column.y == -16 then column.y = header.y end
        local name = module.name
        local yieldedBy = NS.Modules:YieldedBy(name)
        local title = yieldedBy and (module.title .. " " .. string.format(L.MSG_YIELDED, yieldedBy)) or module.title
        local check = column:Check(title,
            function() return choices[name] and not yieldedBy end,
            function(value) choices[name] = value end)
        if yieldedBy then check:Disable() end
        column:Note(yieldedBy and string.format(L.MSG_YIELDED_HINT, yieldedBy, yieldedBy) or module.description, 28)
    end
    -- Descriptions toujours lisibles : pas de grisage par la case du module.
    for _, column in ipairs(columns) do column.dependents = {} end
    return { header, columns[1], columns[2] }
end }

pages[3] = { key = "layout", titleKey = "SETUP_PAGE_LAYOUT", build = function(page)
    local layout = NS.Widgets.NewLayout(page, 20, CONTENT_WIDTH)
    layout:Header(L.SETUP_PAGE_LAYOUT)
    layout:Note(L.SETUP_EDITMODE_HINT)
    LayoutTools(layout, "editMode", NS.PRESET_LAYOUTS.editMode,
        NS.ImportEditModeLayout, NS.ExportEditModeLayout, true)
    return { layout }
end }

pages[4] = { key = "cooldown", titleKey = "SETUP_PAGE_CDM", build = function(page)
    local layout = NS.Widgets.NewLayout(page, 20, CONTENT_WIDTH)
    layout:Header(L.SETUP_PAGE_CDM)
    layout:Note(L.SETUP_CDM_HINT)
    CVarCheck(layout, "cooldownViewerEnabled", "1", L.SETUP_CDM_ENABLE)
    LayoutTools(layout, "cooldown", NS.PRESET_LAYOUTS.cooldown,
        NS.ImportCooldownLayout, NS.ExportCooldownLayout, NS.CanExportCooldownLayout(),
        { default = L.SETUP_CDM_EXPORT_DEFAULT, absent = L.SETUP_CDM_EXPORT_FAILED })
    if not NS.CanExportCooldownLayout() then layout:Note(L.SETUP_CDM_NO_EXPORT) end
    return { layout }
end }

pages[5] = { key = "cvars", titleKey = "SETUP_PAGE_CVARS", build = function(page)
    local layout = NS.Widgets.NewLayout(page, 20, CONTENT_WIDTH)
    layout:Header(L.SETUP_PAGE_CVARS)
    layout:Note(L.SETUP_CVARS_HINT)
    for _, entry in ipairs(RECOMMENDED_CVARS) do
        CVarCheck(layout, entry.name, entry.value, L[entry.label])
    end
    return { layout }
end }

--------------------------------------------------------------------------------
-- Cadre
--------------------------------------------------------------------------------

local function Build()
    frame = CreateFrame("Frame", "AeonUIFirstRun", UIParent, "BackdropTemplate")
    frame:Hide()   -- avant le script OnHide : construire ne doit pas marquer l'assistant terminé
    frame:SetSize(SIDEBAR_WIDTH + CONTENT_WIDTH + 60, 520)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    NS.Widgets.AddResizeGrip(frame, SIDEBAR_WIDTH + CONTENT_WIDTH + 60, 420, 1600, 1400)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetAllPoints()
    NS.SetSolidColor(frame.bg, 0.05, 0.06, 0.08, 0.96)
    frame.edge = frame:CreateTexture(nil, "BORDER")
    frame.edge:SetPoint("TOPLEFT")
    frame.edge:SetPoint("TOPRIGHT")
    frame.edge:SetHeight(2)
    tinsert(UISpecialFrames, "AeonUIFirstRun")   -- Échap ferme la fenêtre
    -- Fermée par Échap ou autrement : ne plus la rouvrir à chaque connexion (/aeon setup reste là).
    frame:SetScript("OnHide", function() NS.global.firstRunDone = true end)

    -- Colonne latérale : un titre par page, la page courante en couleur d'accent.
    frame.sidebar = frame:CreateTexture(nil, "BORDER")
    frame.sidebar:SetPoint("TOPLEFT", 0, -2)
    frame.sidebar:SetPoint("BOTTOMLEFT", 0, 0)
    frame.sidebar:SetWidth(SIDEBAR_WIDTH)
    NS.SetSolidColor(frame.sidebar, 0, 0, 0, 0.35)
    for i, page in ipairs(pages) do
        local button = CreateFrame("Button", nil, frame)
        button:SetSize(SIDEBAR_WIDTH - 20, 24)
        button:SetPoint("TOPLEFT", 10, -20 - (i - 1) * 30)
        button.text = button:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        button.text:SetPoint("LEFT", 8, 0)
        button.text:SetPoint("RIGHT", -4, 0)
        button.text:SetJustifyH("LEFT")
        if button.text.SetWordWrap then button.text:SetWordWrap(false) end
        button.text:SetText(string.format("%d. %s", i, L[page.titleKey]))
        button:SetScript("OnClick", function() FirstRun:SetPage(i) end)
        page.tab = button
    end

    frame.progress = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    frame.progress:SetPoint("BOTTOM", 0, 20)

    frame.previous = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.previous:SetSize(110, 26)
    frame.previous:SetText(L.SETUP_PREV)
    NS.Widgets.FitText(frame.previous, 110)
    frame.previous:SetScript("OnClick", function() FirstRun:SetPage(current - 1) end)

    frame.next = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.next:SetSize(110, 26)
    frame.next:SetPoint("BOTTOMRIGHT", -16, 14)
    frame.next:SetText(L.SETUP_NEXT)
    NS.Widgets.FitText(frame.next, 110)
    frame.previous:SetPoint("RIGHT", frame.next, "LEFT", -10, 0)
    frame.next:SetScript("OnClick", function() FirstRun:SetPage(current + 1) end)

    local done = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    done:SetSize(120, 26)
    done:SetPoint("BOTTOMLEFT", SIDEBAR_WIDTH + 16, 14)
    done:SetText(L.FIRST_RUN_DONE)
    NS.Widgets.FitText(done, 120)
    done:SetScript("OnClick", function() FirstRun:Finish() end)

    local more = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    more:SetSize(200, 26)
    more:SetPoint("LEFT", done, "RIGHT", 8, 0)
    more:SetText(L.FIRST_RUN_OPTIONS)
    NS.Widgets.FitText(more, 200)
    more:SetScript("OnClick", function()
        FirstRun:Finish()
        NS.OpenOptions("modules")
    end)
end

--- Construit la page à la première visite : un ScrollFrame (la liste des modules ou des CVars
--- dépasse la fenêtre sur un petit écran) dont le contenu porte les layouts.
local function PageFrame(index)
    local page = pages[index]
    if page.frame then return page end
    page.frame = CreateFrame("ScrollFrame", nil, frame)
    page.frame:SetPoint("TOPLEFT", SIDEBAR_WIDTH + 10, -8)
    page.frame:SetPoint("BOTTOMRIGHT", -10, 50)
    page.content = CreateFrame("Frame", nil, page.frame)
    page.content:SetSize(CONTENT_WIDTH + 40, 1)
    page.frame:SetScrollChild(page.content)
    page.frame:EnableMouseWheel(true)
    page.frame:SetScript("OnMouseWheel", function(self, delta)
        local range = self:GetVerticalScrollRange() or 0
        local value = self:GetVerticalScroll() - delta * 40
        if value < 0 then value = 0 elseif value > range then value = range end
        self:SetVerticalScroll(value)
    end)
    page.layouts = page.build(page.content)
    local bottom = 0
    for _, layout in ipairs(page.layouts) do bottom = math.max(bottom, -layout.y) end
    page.content:SetHeight(bottom + 20)
    page.frame:Hide()
    return page
end

function FirstRun:SetPage(index)
    if index < 1 or index > #pages then return end
    if not frame then Build() end
    current = index
    local r, g, b = NS.Media:Accent()
    for i, page in ipairs(pages) do
        if page.frame then page.frame:Hide() end
        if i == index then page.tab.text:SetTextColor(r, g, b) else page.tab.text:SetTextColor(0.6, 0.6, 0.6) end
    end
    local page = PageFrame(index)
    for _, layout in ipairs(page.layouts) do layout:Refresh() end
    page.frame:Show()
    frame.progress:SetText(string.format(L.SETUP_PROGRESS, index, #pages))
    if index == 1 then frame.previous:Disable() else frame.previous:Enable() end
    if index == #pages then frame.next:Disable() else frame.next:Enable() end
end

function FirstRun:GetPage() return current end

function FirstRun:Show()
    if not frame then Build() end
    for _, module in ipairs(NS.Modules:List()) do
        choices[module.name] = NS.db.modules[module.name].enabled
    end
    local r, g, b = NS.Media:Accent()
    NS.SetSolidColor(frame.edge, r, g, b, 1)
    self:SetPage(1)
    frame:Show()
end

function FirstRun:Finish()
    for name, enabled in pairs(choices) do
        -- Un module cédé garde le réglage de l'utilisateur pour le jour où l'addon tiers part.
        if not NS.Modules:IsYielded(name) then NS.Modules:SetEnabled(name, enabled) end
    end
    NS.global.firstRunDone = true
    frame:Hide()
    NS.Print(L.FIRST_RUN_FINISHED)
end

function FirstRun:GetFrame() return frame end

NS:On("LOGIN", function()
    if NS.global.firstRunDone then return end
    -- Laisser l'interface Blizzard finir de s'installer ; jamais en combat (reload en combat).
    C_Timer.After(2, function() NS:RunOutOfCombat(function() FirstRun:Show() end) end)
end)

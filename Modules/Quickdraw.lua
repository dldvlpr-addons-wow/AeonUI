-- Modules/Quickdraw.lua
-- Menu radial : maintenir une touche ouvre un anneau (ou une grille) d'entrées autour du
-- curseur, relâcher sur une entrée la lance. Entrées : sorts, objets, macros, montures, et
-- sous-menus (« menu:2 ») : survoler l'entrée un instant ouvre la palette 2 à sa place.
-- Quatre palettes, chacune sa touche (facultative : une palette sans touche sert de sous-menu).
-- Hors combat seulement : sur ce client les extraits sécurisés ne compilent pas, et écrire les
-- attributs d'un bouton sécurisé est interdit en combat. En combat, la touche ne fait rien.
-- Mécanique : la touche est liée (SetOverrideBindingClick) à un bouton sécurisé qui reçoit
-- l'appui et le relâcher. À l'appui : palette ouverte, aucune action. Au relâcher : l'entrée
-- survolée devient l'action du bouton, que le clic exécute, puis la palette se ferme. Un seul
-- bouton pour toutes les touches : le clic lié porte le numéro de palette (« Palette2 »).
local _, NS = ...
local L = NS.L
local Media = NS.Media

local Quickdraw = NS.Modules:Register("quickdraw", {
    titleKey = "QUICKDRAW_TITLE",
    descKey = "QUICKDRAW_DESC",
    secure = true,
    defaults = {
        enabled = false,
        key = "",
        layout = "arc",           -- "arc", "fan" (bande en demi-cercle au-dessus du curseur) ou "grid"
        radius = 90,
        iconSize = 36,
        selectionColor = { r = 1, g = 0.82, b = 0 },   -- bordure de l'entrée survolée
        showLabel = true,         -- nom de l'entrée survolée sous le curseur
        entries = "",             -- une entrée par ligne : "spell:133", "item:6948", "macro:Nom", "mount:12", "menu:2"
        -- Palettes 2 à 4 : même apparence que la première, touche et entrées propres.
        palettes = { palette2 = { key = "", entries = "" }, palette3 = { key = "", entries = "" },
                     palette4 = { key = "", entries = "" } },
    },
})

local DEADZONE = 20
local atan2 = math.atan2 or math.atan
local MAX_ENTRIES = 16
local KINDS = { spell = true, item = true, macro = true, mount = true, menu = true, marker = true }   -- mount:0 : monture favorite au hasard
local PALETTE_COUNT = 4          -- ponytail: palettes fixes, liste dynamique si quatre ne suffisent pas
local SUBMENU_DELAY = 0.3        -- secondes de survol avant d'ouvrir un sous-menu

local button, palette
local icons = {}
local lists = {}                 -- [palette] = entrées lues
local entries = {}               -- entrées de la palette ouverte
local current                    -- palette ouverte
local hovered, hoveredSince

--------------------------------------------------------------------------------
-- Fonctions pures (testées hors jeu)
--------------------------------------------------------------------------------

--- Texte des options -> liste { kind, value } (lignes invalides ignorées, 16 au plus).
function Quickdraw.ParseEntries(text)
    local list = {}
    for line in (text or ""):gmatch("[^\r\n]+") do
        local kind, value = line:match("^%s*(%a+)%s*:%s*(.-)%s*$")
        kind = kind and kind:lower()
        if kind and KINDS[kind] and value ~= "" then
            if kind ~= "macro" then value = tonumber(value) end
            if kind == "menu" and value and not (value >= 1 and value <= PALETTE_COUNT) then value = nil end
            if kind == "marker" and value and not (value >= 0 and value <= 8) then value = nil end
            if value then list[#list + 1] = { kind = kind, value = value } end
        end
        if #list >= MAX_ENTRIES then break end
    end
    return list
end

--- Position (x, y) de l'entrée `index` sur `count`, par rapport au centre de la palette.
function Quickdraw.SlotPosition(layout, index, count, radius, size)
    if layout == "grid" then
        local columns = math.ceil(math.sqrt(count))
        local rows = math.ceil(count / columns)
        local column, row = (index - 1) % columns, math.floor((index - 1) / columns)
        local step = size + 6
        return (column - (columns - 1) / 2) * step, ((rows - 1) / 2 - row) * step
    end
    if layout == "fan" then
        -- Bande : demi-cercle au-dessus du curseur, de gauche à droite (162° à 18°).
        local angle = math.pi / 2
        if count > 1 then angle = math.pi * (0.9 - 0.8 * (index - 1) / (count - 1)) end
        return math.cos(angle) * radius, math.sin(angle) * radius
    end
    -- Anneau : la première entrée en haut, dans le sens des aiguilles d'une montre.
    local angle = math.pi / 2 - (index - 1) * 2 * math.pi / count
    return math.cos(angle) * radius, math.sin(angle) * radius
end

--- Entrée visée par un curseur décalé de (dx, dy) : la plus proche, nil dans la zone morte.
function Quickdraw.Pick(layout, dx, dy, count, radius, size)
    if count == 0 or (dx * dx + dy * dy) < DEADZONE * DEADZONE then return nil end
    local best, bestDistance
    for i = 1, count do
        local x, y = Quickdraw.SlotPosition(layout, i, count, radius, size)
        local distance
        if layout == "grid" then
            distance = (dx - x) ^ 2 + (dy - y) ^ 2
        else
            -- Anneau et bande : l'angle suffit, même loin du cercle (geste rapide).
            local diff = math.abs(atan2(dy, dx) - atan2(y, x))
            distance = math.min(diff, 2 * math.pi - diff)
        end
        if not bestDistance or distance < bestDistance then best, bestDistance = i, distance end
    end
    return best
end

--------------------------------------------------------------------------------
-- Entrées : icône, attributs, entrée déposée depuis le curseur
--------------------------------------------------------------------------------

--- Réglages de la palette `index` : la première à la racine, les autres dans `palettes`.
function Quickdraw:PaletteConfig(index)
    if index == 1 then return self.db end
    return self.db.palettes["palette" .. index]
end

local function EntryIcon(entry)
    if entry.kind == "spell" then return NS.GetSpellTexture(entry.value) end
    if entry.kind == "menu" then   -- icône de la première entrée du sous-menu
        local first = lists[entry.value] and lists[entry.value][1]
        return first and first.kind ~= "menu" and EntryIcon(first) or nil
    end
    if entry.kind == "item" then
        if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(entry.value) end
        return _G.GetItemIcon and GetItemIcon(entry.value) or nil
    end
    if entry.kind == "macro" then return _G.GetMacroInfo and select(2, GetMacroInfo(entry.value)) or nil end
    if entry.kind == "marker" then
        return entry.value > 0 and ("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. entry.value)
            or "Interface\\Buttons\\UI-GroupLoot-Pass-Up"
    end
    if entry.kind == "mount" and entry.value == 0 then return "Interface\\Icons\\Ability_Mount_RidingHorse" end
    if entry.kind == "mount" and C_MountJournal and C_MountJournal.GetMountInfoByID then
        return select(3, C_MountJournal.GetMountInfoByID(entry.value))
    end
    return nil
end

--- Nom affiché de l'entrée survolée ; nil si le client ne le connaît pas encore.
function Quickdraw.EntryName(entry)
    if entry.kind == "spell" then return NS.GetSpellName(entry.value) end
    if entry.kind == "item" then
        if C_Item and C_Item.GetItemNameByID then return C_Item.GetItemNameByID(entry.value) end
        return C_Item and C_Item.GetItemInfo and (C_Item.GetItemInfo(entry.value)) or nil
    end
    if entry.kind == "macro" then return entry.value end
    if entry.kind == "menu" then return string.format(L.QUICKDRAW_SUBMENU, entry.value) end
    if entry.kind == "marker" then return entry.value > 0 and _G["RAID_TARGET_" .. entry.value] or L.QUICKDRAW_MARKER_CLEAR end
    if entry.kind == "mount" and entry.value == 0 then return L.QUICKDRAW_RANDOM_MOUNT end
    if entry.kind == "mount" and C_MountJournal and C_MountJournal.GetMountInfoByID then
        return (C_MountJournal.GetMountInfoByID(entry.value))
    end
    return nil
end

--- Attributs du bouton sécurisé pour une entrée ; nil pour une monture (appel direct) ou un sous-menu.
function Quickdraw.Attributes(entry)
    if entry.kind == "spell" then return "spell", "spell", entry.value end
    if entry.kind == "item" then return "item", "item", "item:" .. entry.value end
    if entry.kind == "macro" then return "macro", "macro", entry.value end
    return nil
end

--- Ligne d'entrée pour ce que le joueur tient sur le curseur (sort, objet, macro, monture).
function Quickdraw.CursorEntry()
    if not _G.GetCursorInfo then return nil end
    local kind, a, b, c = GetCursorInfo()
    if kind == "spell" then
        local id = type(c) == "number" and c or a
        return id and ("spell:" .. id) or nil
    elseif kind == "item" then
        return a and ("item:" .. a) or nil
    elseif kind == "macro" then
        local name = _G.GetMacroInfo and GetMacroInfo(a)
        return name and ("macro:" .. name) or nil
    elseif kind == "mount" then
        return a and ("mount:" .. a) or nil
    end
    return nil
end

--------------------------------------------------------------------------------
-- Palette
--------------------------------------------------------------------------------

local function Paint()
    local db = Quickdraw.db
    local selection = db.selectionColor
    local border = NS.db.theme.border
    for i, icon in ipairs(icons) do
        if icon:IsShown() then
            local selected = i == hovered
            local c = selected and selection or border
            icon:SetAlpha(selected and 1 or 0.55)
            for _, edge in pairs(icon.edges) do NS.SetSolidColor(edge, c.r, c.g, c.b, c.a or 1) end
        end
    end
    local entry = hovered and entries[hovered]
    palette.label:SetText(db.showLabel and entry and Quickdraw.EntryName(entry) or "")
end

local Open

local function Track()
    local db = Quickdraw.db
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    local dx, dy = x / scale - palette.cx, y / scale - palette.cy
    local pick = Quickdraw.Pick(db.layout, dx, dy, #entries, db.radius, db.iconSize)
    if pick ~= hovered then
        hovered, hoveredSince = pick, GetTime()
        Paint()
    end
    -- Sous-menu survolé assez longtemps : sa palette s'ouvre, centrée sur l'entrée.
    local entry = hovered and entries[hovered]
    if entry and entry.kind == "menu" and entry.value ~= current and #(lists[entry.value] or {}) > 0
        and GetTime() - hoveredSince >= SUBMENU_DELAY then
        local sx, sy = Quickdraw.SlotPosition(db.layout, hovered, #entries, db.radius, db.iconSize)
        Open(entry.value, palette.cx + sx, palette.cy + sy)
    end
end

--- Ouvre la palette `index`, centrée sur (x, y) ou, par défaut, sur le curseur.
function Open(index, x, y)
    local db = Quickdraw.db
    current, entries = index, lists[index] or {}
    if not x then
        local scale = UIParent:GetEffectiveScale()
        x, y = GetCursorPosition()
        x, y = x / scale, y / scale
    end
    palette.cx, palette.cy = x, y
    palette:ClearAllPoints()
    palette:SetPoint("CENTER", UIParent, "BOTTOMLEFT", palette.cx, palette.cy)
    for i, entry in ipairs(entries) do
        local icon = icons[i]
        if not icon then
            icon = CreateFrame("Frame", nil, palette)
            icon.edges = select(2, Media:CreateBackdrop(icon))
            icon.texture = icon:CreateTexture(nil, "ARTWORK")
            icon.texture:SetAllPoints()
            icons[i] = icon
        end
        icon:SetSize(db.iconSize, db.iconSize)
        icon:ClearAllPoints()
        icon:SetPoint("CENTER", palette, "CENTER", Quickdraw.SlotPosition(db.layout, i, #entries, db.radius, db.iconSize))
        icon.texture:SetTexture(EntryIcon(entry) or 134400)
        icon:Show()
    end
    for i = #entries + 1, #icons do icons[i]:Hide() end
    hovered = nil
    Paint()
    palette:Show()
end

local function Close()
    palette:Hide()
    hovered, current = nil, nil
end

local function Build()
    palette = CreateFrame("Frame", "AeonUIQuickdrawPalette", UIParent)
    palette:SetFrameStrata("DIALOG")
    palette:SetSize(1, 1)
    palette.label = Media:CreateText(palette, "OVERLAY", 2)
    palette.label:SetPoint("TOP", palette, "CENTER", 0, -DEADZONE)
    palette:SetScript("OnUpdate", Track)
    palette:Hide()

    button = CreateFrame("Button", "AeonUIQuickdrawButton", UIParent, "SecureActionButtonTemplate")
    button:RegisterForClicks("AnyDown", "AnyUp")
    -- ActionButtonUseKeyDown à 1 : sans ceci, le modèle n'agit qu'à l'appui, avant nos attributs.
    button:SetAttribute("useOnKeyDown", false)
    button:SetScript("PreClick", function(self, mouseButton, down)
        -- En combat : pas d'attribut possible, la touche ne fait rien.
        if NS.InCombat() then return end
        self:SetAttribute("type", nil)
        if down then
            local index = tonumber(tostring(mouseButton):match("^Palette(%d)$")) or 1
            if #(lists[index] or {}) > 0 then Open(index) end
            return
        end
        if not palette:IsShown() then return end
        Track()
        local entry = hovered and entries[hovered]
        if not entry then return end
        local kind, attribute, value = Quickdraw.Attributes(entry)
        if kind then
            self:SetAttribute("type", kind)
            self:SetAttribute(attribute, value)
        elseif entry.kind == "mount" and C_MountJournal and C_MountJournal.SummonByID then
            C_MountJournal.SummonByID(entry.value)   -- 0 : favorite au hasard
        elseif entry.kind == "marker" then
            NS.Modules:Get("raidutility").MarkTarget(entry.value)   -- même marqueur une seconde fois : retiré
        end
    end)
    button:SetScript("PostClick", function(self, _, down)
        if down then return end
        if palette:IsShown() then Close() end   -- combat entré touche tenue : la palette se ferme quand même
        if not NS.InCombat() then self:SetAttribute("type", nil) end
    end)
end

function Quickdraw:GetButton() return button, palette end

--- Relie la touche au bouton (hors combat : SetOverrideBindingClick est protégé).
function Quickdraw:Bind(on)
    NS:RunOutOfCombat(function()
        ClearOverrideBindings(button)
        for index = 1, on and PALETTE_COUNT or 0 do
            local key = self:PaletteConfig(index).key
            if type(key) == "string" and key ~= "" then
                SetOverrideBindingClick(button, true, key:upper(), button:GetName(),
                    index == 1 and "LeftButton" or ("Palette" .. index))
            end
        end
    end)
end

local function ReadLists()
    for index = 1, PALETTE_COUNT do lists[index] = Quickdraw.ParseEntries(Quickdraw:PaletteConfig(index).entries) end
end

function Quickdraw:OnEnable()
    if not button then Build() end
    ReadLists()
    self:Bind(true)
end

function Quickdraw:OnDisable()
    if not button then return end
    Close()
    self:Bind(false)
end

function Quickdraw:OnRefresh()
    ReadLists()
    self:Bind(true)
end

function Quickdraw:BuildOptions(o)
    o:Note(L.QUICKDRAW_NOTE)
    o:EditBox("key", L.OPT_QUICKDRAW_KEY, 1)
    o:Dropdown("layout", L.OPT_QUICKDRAW_LAYOUT, {
        { name = L.OPT_QUICKDRAW_ARC, value = "arc" }, { name = L.OPT_QUICKDRAW_FAN, value = "fan" },
        { name = L.OPT_QUICKDRAW_GRID, value = "grid" },
    })
    o:Advanced()
    o:Slider("radius", L.OPT_QUICKDRAW_RADIUS, 50, 200, 5)
    o:EndAdvanced()
    o:Slider("iconSize", L.OPT_QUICKDRAW_ICON_SIZE, 20, 64, 2)
    o:Color("selectionColor", L.OPT_QUICKDRAW_SELECTION_COLOR)
    o:Check("showLabel", L.OPT_QUICKDRAW_SHOW_LABEL)
    o:Title(L.OPT_QUICKDRAW_ENTRIES)
    o:Note(L.OPT_QUICKDRAW_ENTRIES_HINT)
    o:Note(L.OPT_QUICKDRAW_SUBMENU_HINT)
    for index = 1, PALETTE_COUNT do
        local prefix = index == 1 and "" or ("palettes.palette" .. index .. ".")
        if index > 1 then
            o:Title(string.format(L.QUICKDRAW_SUBMENU, index))
            o:EditBox(prefix .. "key", L.OPT_QUICKDRAW_KEY, 1)
        end
        o:EditBox(prefix .. "entries", L.OPT_QUICKDRAW_ENTRIES, index == 1 and 8 or 5)
        o:Button(L.OPT_QUICKDRAW_ADD_CURSOR, function()
            local line = Quickdraw.CursorEntry()
            if not line then NS.Print(L.MSG_QUICKDRAW_CURSOR_EMPTY) return end
            local config = self:PaletteConfig(index)
            local text = config.entries
            config.entries = (text ~= "" and not text:find("\n$") and (text .. "\n") or text) .. line
            if ClearCursor then ClearCursor() end
            NS.Modules:Refresh("quickdraw")
            NS.Options:Refresh()
        end)
    end
end

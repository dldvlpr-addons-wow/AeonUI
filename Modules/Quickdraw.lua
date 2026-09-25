-- Modules/Quickdraw.lua
-- Menu radial : maintenir une touche ouvre un anneau (ou une grille) d'entrées autour du
-- curseur, relâcher sur une entrée la lance. Entrées : sorts, objets, macros, montures.
-- Hors combat seulement : sur ce client les extraits sécurisés ne compilent pas, et écrire les
-- attributs d'un bouton sécurisé est interdit en combat. En combat, la touche ne fait rien.
-- Mécanique : la touche est liée (SetOverrideBindingClick) à un bouton sécurisé qui reçoit
-- l'appui et le relâcher. À l'appui : palette ouverte, aucune action. Au relâcher : l'entrée
-- survolée devient l'action du bouton, que le clic exécute, puis la palette se ferme.
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
        layout = "arc",           -- "arc" ou "grid"
        radius = 90,
        iconSize = 36,
        entries = "",             -- une entrée par ligne : "spell:133", "item:6948", "macro:Nom", "mount:12"
    },
})

local DEADZONE = 20
local atan2 = math.atan2 or math.atan
local MAX_ENTRIES = 16
local KINDS = { spell = true, item = true, macro = true, mount = true }

local button, palette
local icons = {}
local entries = {}
local hovered

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
            -- Anneau : l'angle suffit, même loin du cercle (geste rapide).
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

local function EntryIcon(entry)
    if entry.kind == "spell" then return NS.GetSpellTexture(entry.value) end
    if entry.kind == "item" then
        if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(entry.value) end
        return _G.GetItemIcon and GetItemIcon(entry.value) or nil
    end
    if entry.kind == "macro" then return _G.GetMacroInfo and select(2, GetMacroInfo(entry.value)) or nil end
    if entry.kind == "mount" and C_MountJournal and C_MountJournal.GetMountInfoByID then
        return select(3, C_MountJournal.GetMountInfoByID(entry.value))
    end
    return nil
end

--- Attributs du bouton sécurisé pour une entrée ; nil pour une monture (appel direct).
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
    for i, icon in ipairs(icons) do
        if icon:IsShown() then icon:SetAlpha(i == hovered and 1 or 0.55) end
    end
end

local function Track()
    local db = Quickdraw.db
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    local dx, dy = x / scale - palette.cx, y / scale - palette.cy
    local pick = Quickdraw.Pick(db.layout, dx, dy, #entries, db.radius, db.iconSize)
    if pick ~= hovered then
        hovered = pick
        Paint()
    end
end

local function Open()
    local db = Quickdraw.db
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    palette.cx, palette.cy = x / scale, y / scale
    palette:ClearAllPoints()
    palette:SetPoint("CENTER", UIParent, "BOTTOMLEFT", palette.cx, palette.cy)
    for i, entry in ipairs(entries) do
        local icon = icons[i]
        if not icon then
            icon = CreateFrame("Frame", nil, palette)
            Media:CreateBackdrop(icon)
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
    hovered = nil
end

local function Build()
    palette = CreateFrame("Frame", "AeonUIQuickdrawPalette", UIParent)
    palette:SetFrameStrata("DIALOG")
    palette:SetSize(1, 1)
    palette:SetScript("OnUpdate", Track)
    palette:Hide()

    button = CreateFrame("Button", "AeonUIQuickdrawButton", UIParent, "SecureActionButtonTemplate")
    button:RegisterForClicks("AnyDown", "AnyUp")
    -- ActionButtonUseKeyDown à 1 : sans ceci, le modèle n'agit qu'à l'appui, avant nos attributs.
    button:SetAttribute("useOnKeyDown", false)
    button:SetScript("PreClick", function(self, _, down)
        -- En combat : pas d'attribut possible, la touche ne fait rien.
        if NS.InCombat() then return end
        self:SetAttribute("type", nil)
        if down then
            if #entries > 0 then Open() end
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
            C_MountJournal.SummonByID(entry.value)
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
        local key = self.db.key
        if on and type(key) == "string" and key ~= "" then
            SetOverrideBindingClick(button, true, key:upper(), button:GetName(), "LeftButton")
        end
    end)
end

function Quickdraw:OnEnable()
    if not button then Build() end
    entries = Quickdraw.ParseEntries(self.db.entries)
    self:Bind(true)
end

function Quickdraw:OnDisable()
    if not button then return end
    Close()
    self:Bind(false)
end

function Quickdraw:OnRefresh()
    entries = Quickdraw.ParseEntries(self.db.entries)
    self:Bind(true)
end

function Quickdraw:BuildOptions(o)
    o:Note(L.QUICKDRAW_NOTE)
    o:EditBox("key", L.OPT_QUICKDRAW_KEY, 1)
    o:Dropdown("layout", L.OPT_QUICKDRAW_LAYOUT, {
        { name = L.OPT_QUICKDRAW_ARC, value = "arc" }, { name = L.OPT_QUICKDRAW_GRID, value = "grid" },
    })
    o:Slider("radius", L.OPT_QUICKDRAW_RADIUS, 50, 200, 5)
    o:Slider("iconSize", L.OPT_QUICKDRAW_ICON_SIZE, 20, 64, 2)
    o:Title(L.OPT_QUICKDRAW_ENTRIES)
    o:Note(L.OPT_QUICKDRAW_ENTRIES_HINT)
    o:EditBox("entries", L.OPT_QUICKDRAW_ENTRIES, 8)
    o:Button(L.OPT_QUICKDRAW_ADD_CURSOR, function()
        local line = Quickdraw.CursorEntry()
        if not line then NS.Print(L.MSG_QUICKDRAW_CURSOR_EMPTY) return end
        local db = self.db
        db.entries = (db.entries ~= "" and not db.entries:find("\n$") and (db.entries .. "\n") or db.entries) .. line
        if ClearCursor then ClearCursor() end
        NS.Modules:Refresh("quickdraw")
        NS.Options:Refresh()
    end)
end

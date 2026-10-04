-- Core/Media.lua
-- Thème commun : police (taille, contour), couleur d'accent, fond, bordure 1 px, texture
-- de barre. Les textes et les fonds créés par AeonUI s'enregistrent ici et suivent le
-- thème sans /reload (THEME_CHANGED) et l'échelle (PIXEL_CHANGED).
-- Textures de barre maison (Media/Bars, tools/generate_bar_textures.lua), listées même sans
-- LibSharedMedia et inscrites dedans quand elle est là. Exception par module : police et texture
-- propres (theme.moduleMedia[module]), le module étant celui qui crée le texte ou la barre.
-- Accent : couleur libre, ou de classe, ou de faction, recalculée pour chaque personnage.
-- Mode sombre partagé (theme.darkMode) : barres de vie sombres, couleur de l'unité dans le manque.
local _, NS = ...

local Media = {}
NS.Media = Media

local FALLBACK_FONT = "Fonts\\FRIZQT__.TTF"
local FLAT_TEXTURE = "Interface\\Buttons\\WHITE8X8"
local registered = setmetatable({}, { __mode = "k" })   -- [fontString] = { sizeDelta, flags }
local backdrops = setmetatable({}, { __mode = "k" })    -- [frame] = { bg, edges, inset }

local function Theme() return NS.db and NS.db.theme end

local BAR_PATH = "Interface\\AddOns\\AeonUI\\Media\\Bars\\"
--- Textures de barre maison : { key (valeur de theme.statusbar), name, path }.
Media.BAR_TEXTURES = {
    { key = "aeon:smooth", name = "AeonUI Smooth", path = BAR_PATH .. "Smooth" },
    { key = "aeon:gloss", name = "AeonUI Gloss", path = BAR_PATH .. "Gloss" },
    { key = "aeon:soft", name = "AeonUI Soft", path = BAR_PATH .. "Soft" },
    { key = "aeon:stripes", name = "AeonUI Stripes", path = BAR_PATH .. "Stripes" },
    -- Texture du client vanilla (style Classic) ; LibSharedMedia l'a déjà sous le nom « Blizzard ».
    { key = "blizzard:classic", name = "Blizzard Classic", path = "Interface\\TargetingFrame\\UI-StatusBar" },
}
local BAR_BY_KEY = {}
for _, texture in ipairs(Media.BAR_TEXTURES) do BAR_BY_KEY[texture.key] = texture end

-- Préréglages d'accent fixes (écrits dans theme.accent) ; « class » et « faction » sont lus en jeu.
Media.ACCENT_PRESETS = {
    aeon = { r = 0.25, g = 0.66, b = 0.96 },
    bronze = { r = 0.8, g = 0.56, b = 0.28 },
}
local FACTION_COLORS = { Alliance = { 0.29, 0.52, 0.95 }, Horde = { 0.86, 0.2, 0.18 } }

-- Palette sombre partagée : remplissage des barres de vie, opacité de la couleur d'unité dessous.
Media.DARK = { fill = { 0.13, 0.13, 0.15 }, missingAlpha = 0.65 }

--- Réglage propre au module `owner` (police ou texture), nil : celui du thème.
local function Override(owner, field)
    local theme = Theme()
    local own = owner and theme and type(theme.moduleMedia) == "table" and theme.moduleMedia[owner]
    local value = type(own) == "table" and own[field] or nil
    if value == nil or value == "inherit" then return nil end
    return value
end

-- Langues dont les caractères manquent aux polices latines du jeu : police du client à la place.
local LOCALE_FONTS = { koKR = true, zhCN = true, zhTW = true, ruRU = true }
local LATIN_FONTS = { ["Fonts\\ARIALN.TTF"] = true, ["Fonts\\FRIZQT__.TTF"] = true }

function Media:Font(owner)
    local theme = Theme()
    local font = Override(owner, "font") or theme.font
    if LOCALE_FONTS[NS.activeLocale] and LATIN_FONTS[font] and _G.STANDARD_TEXT_FONT then
        font = STANDARD_TEXT_FONT
    end
    return font, theme.fontSize
end

--- Contour de police du thème : "", "OUTLINE" ou "THICKOUTLINE".
function Media:Outline()
    local theme = Theme()
    return theme and theme.fontOutline or ""
end

function Media:Accent()
    local theme = Theme()
    local preset = theme.accentPreset
    if preset == "class" and _G.UnitClass then
        local _, classFile = UnitClass("player")
        if classFile and not NS.IsSecret(classFile) then return NS.ClassColor(classFile) end
    elseif preset == "faction" and _G.UnitFactionGroup then
        local c = FACTION_COLORS[UnitFactionGroup("player") or ""]
        if c then return c[1], c[2], c[3] end
    end
    local c = theme.accent
    return c.r, c.g, c.b
end

function Media:AccentHex()
    local r, g, b = self:Accent()
    local function byte(v) return math.floor(v * 255 + 0.5) end
    return string.format("ff%02x%02x%02x", byte(r), byte(g), byte(b))
end

--------------------------------------------------------------------------------
-- Textes
--------------------------------------------------------------------------------

-- Polices Blizzard de repli par alphabet : noms coréens, chinois ou cyrilliques des autres joueurs,
-- absents des polices latines. Même hauteur que la police choisie (comme SystemFont_NamePlate).
local FALLBACK_MEMBERS = {
    { alphabet = "korean", file = "Fonts\\2002.TTF" },
    { alphabet = "simplifiedchinese", file = "Fonts\\ARKai_T.ttf" },
    { alphabet = "traditionalchinese", file = "Fonts\\blei00d.TTF" },
    { alphabet = "russian", file = "Fonts\\FRIZQT___CYR.TTF" },
}
-- ponytail: une famille par police, taille et contour, jamais libérée (une vingtaine par police) ;
-- à plafonner si le budget Font de LimitedLuaResources (300 par addon) devient actif.
local families, familyCount = {}, 0

--- Famille de polices (police choisie + replis), une par police, taille et contour ; nil sans
-- CreateFontFamily ou si le client la refuse.
local function FontFamily(path, height, flags)
    if not _G.CreateFontFamily then return nil end
    local key = path .. "|" .. height .. "|" .. flags
    if families[key] == nil then
        local members = { { alphabet = "roman", file = path, height = height, flags = flags } }
        for _, member in ipairs(FALLBACK_MEMBERS) do
            members[#members + 1] = { alphabet = member.alphabet, file = member.file, height = height, flags = flags }
        end
        familyCount = familyCount + 1
        local ok, family = pcall(CreateFontFamily, "AeonUIFontFamily" .. familyCount, members)
        families[key] = ok and family or false
    end
    return families[key] or nil
end

--- Police posée par famille (repli des glyphes) ; couleur et alignement du texte gardés, l'objet
-- Font pouvant porter les siens.
local function SetFamily(fontString, family)
    local r, g, b, a = fontString:GetTextColor()
    local justifyH, justifyV = fontString:GetJustifyH(), fontString:GetJustifyV()
    fontString:SetFontObject(family)
    if r then fontString:SetTextColor(r, g, b, a) end
    if justifyH then fontString:SetJustifyH(justifyH) end
    if justifyV then fontString:SetJustifyV(justifyV) end
end

local probe   -- texte caché : teste la police sans poser de police propre sur le vrai texte

local function Apply(fontString, sizeDelta, flags, owner)
    local path, size = Media:Font(owner)
    local effective = flags or Media:Outline()
    local height = size + (sizeDelta or 0)
    -- Police disparue (LibSharedMedia désinstallé) : SetFont échoue, une famille non.
    probe = probe or UIParent:CreateFontString(nil, "BACKGROUND")
    if probe:SetFont(path, height, effective) == false or not probe:GetFont() then path = FALLBACK_FONT end
    local family = FontFamily(path, height, effective)
    if family then
        SetFamily(fontString, family)
    else
        fontString:SetFont(path, height, effective)
    end
    -- Ombre et contour ensemble épaississent le texte : l'un ou l'autre.
    if effective ~= "" then fontString:SetShadowOffset(0, 0) else fontString:SetShadowOffset(1, -1) end
end

--- Crée un FontString aux couleurs du thème. sizeDelta s'ajoute à la taille du thème.
-- flags nil = contour du thème ; une valeur explicite ("" ou "OUTLINE") l'emporte.
function Media:CreateText(parent, layer, sizeDelta, flags)
    local fontString = parent:CreateFontString(nil, layer or "OVERLAY")
    local owner = NS.Modules and NS.Modules.calling
    registered[fontString] = { sizeDelta = sizeDelta or 0, flags = flags, owner = owner }
    Apply(fontString, sizeDelta, flags, owner)
    return fontString
end

--- Change le delta de taille d'un texte créé par CreateText (plaques : taille de police propre).
function Media:SetTextSizeDelta(fontString, sizeDelta)
    local style = registered[fontString]
    if not style then return end
    style.sizeDelta = sizeDelta or 0
    Apply(fontString, style.sizeDelta, style.flags, style.owner)
end

function Media:RefreshFonts()
    for fontString, style in pairs(registered) do
        Apply(fontString, style.sizeDelta, style.flags, style.owner)
    end
end

--------------------------------------------------------------------------------
-- Fonds, bordures, barres
--------------------------------------------------------------------------------

--- Texture des barres de statut : celle du module `owner` s'il en a une, sinon celle du thème ;
-- "" plate, "aeon:…" maison, autre nom : LibSharedMedia (plate si elle n'y est plus).
function Media:StatusBarTexture(owner)
    local theme = Theme()
    local name = Override(owner, "statusbar") or (theme and theme.statusbar)
    if BAR_BY_KEY[name] then return BAR_BY_KEY[name].path end
    if name and name ~= "" and _G.LibStub then
        local LSM = LibStub("LibSharedMedia-3.0", true)
        local path = LSM and LSM:Fetch("statusbar", name, true)
        if path then return path end
    end
    return FLAT_TEXTURE
end

--- Choix de texture de barre : plate, maison, puis LibSharedMedia (sans nos doublons).
function Media:StatusBarChoices(flatName)
    local list = { { name = flatName, value = "" } }
    for _, texture in ipairs(self.BAR_TEXTURES) do
        list[#list + 1] = { name = texture.name, value = texture.key, texture = texture.path }
    end
    local LSM = _G.LibStub and LibStub("LibSharedMedia-3.0", true)
    for _, name in ipairs(LSM and LSM:List("statusbar") or {}) do
        local path = LSM:Fetch("statusbar", name, true)
        if not name:find("^AeonUI ") then list[#list + 1] = { name = name, value = name, texture = path } end
    end
    return list
end

--- Inscrit les textures maison dans LibSharedMedia (autres addons compris), si elle est chargée.
function Media:RegisterSharedMedia()
    local LSM = _G.LibStub and LibStub("LibSharedMedia-3.0", true)
    if not LSM then return false end
    for _, texture in ipairs(self.BAR_TEXTURES) do
        if texture.key:find("^aeon:") then LSM:Register("statusbar", texture.name, texture.path) end
    end
    return true
end

local EDGES = { "top", "bottom", "left", "right" }

local function LayoutEdges(frame, edges, inset)
    local px = NS.Pixel:Scale(Theme() and Theme().borderSize or 1)
    local o = inset or 0
    edges.top:ClearAllPoints()
    edges.top:SetPoint("TOPLEFT", frame, "TOPLEFT", -o, o)
    edges.top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", o, o)
    edges.top:SetHeight(px)
    edges.bottom:ClearAllPoints()
    edges.bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -o, -o)
    edges.bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", o, -o)
    edges.bottom:SetHeight(px)
    edges.left:ClearAllPoints()
    edges.left:SetPoint("TOPLEFT", frame, "TOPLEFT", -o, o)
    edges.left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -o, -o)
    edges.left:SetWidth(px)
    edges.right:ClearAllPoints()
    edges.right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", o, o)
    edges.right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", o, -o)
    edges.right:SetWidth(px)
end

local function PaintEdges(edges, color)
    -- Couleur fixe encore vide (remplie par l'appelant juste après) : celle du thème en attendant.
    local c = (color and color.r) and color or Theme().border
    for _, side in ipairs(EDGES) do NS.SetSolidColor(edges[side], c.r, c.g, c.b, c.a or 1) end
end

--- Bordure de 1 pixel physique autour de `frame` (quatre textures), couleur du thème
-- ou `color` fixe. Retourne la table des quatre textures.
function Media:CreateBorder(frame, color, inset)
    local edges = {}
    -- OVERLAY : au-dessus de l'icône (ARTWORK) ou de la barre qu'elle entoure, sinon masquée.
    for _, side in ipairs(EDGES) do edges[side] = frame:CreateTexture(nil, "OVERLAY") end
    LayoutEdges(frame, edges, inset)
    PaintEdges(edges, color)
    local entry = backdrops[frame] or {}
    entry.edges, entry.inset, entry.borderColor = edges, inset, color
    backdrops[frame] = entry
    return edges
end

--- Fond plat aux couleurs du thème plus bordure 1 px. `inset` élargit le tout.
-- Pas de BackdropTemplate : les textures se recalculent à chaque changement d'échelle.
function Media:CreateBackdrop(frame, inset)
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    local o = inset or 0
    bg:SetPoint("TOPLEFT", frame, "TOPLEFT", -o, o)
    bg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", o, -o)
    local c = Theme().backdrop
    NS.SetSolidColor(bg, c.r, c.g, c.b, c.a or 1)
    local edges = self:CreateBorder(frame, nil, inset)
    backdrops[frame].bg = bg
    return bg, edges
end

local statusBars = setmetatable({}, { __mode = "k" })   -- [bar] = true

--- Barre de statut à la texture du thème, fond plat aux couleurs du thème derrière.
-- La barre suit THEME_CHANGED (texture, fond) sans /reload. `owner` : module dont elle suit la
-- texture propre, pour une barre créée hors d'un appel du module (événement) ; sinon le module appelant.
function Media:CreateStatusBar(parent, owner)
    local bar = CreateFrame("StatusBar", nil, parent)
    owner = owner or NS.Modules and NS.Modules.calling or true
    bar:SetStatusBarTexture(self:StatusBarTexture(owner ~= true and owner or nil))
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints(bar)
    local c = Theme().backdrop
    NS.SetSolidColor(bar.bg, c.r, c.g, c.b, c.a or 1)
    statusBars[bar] = owner
    return bar
end

--- Couleur d'une barre de vie (r, g, b peut-être secrets : jamais comparés ni calculés). Mode
-- sombre : remplissage de la palette, couleur de l'unité dans la partie manquante (le fond).
function Media:SetHealthColor(bar, r, g, b)
    if Theme().darkMode then
        local fill = self.DARK.fill
        bar:SetStatusBarColor(fill[1], fill[2], fill[3])
        if bar.bg then
            NS.SetSolidColor(bar.bg, r, g, b, 1)
            bar.bg:SetAlpha(self.DARK.missingAlpha)
            bar.darkened = true
        end
        return
    end
    bar:SetStatusBarColor(r, g, b)
    if bar.darkened then
        bar.darkened = nil
        local c = Theme().backdrop
        NS.SetSolidColor(bar.bg, c.r, c.g, c.b, c.a or 1)
        bar.bg:SetAlpha(1)
    end
end

function Media:RefreshBackdrops()
    local theme = Theme()
    for frame, entry in pairs(backdrops) do
        if entry.bg then
            local c = theme.backdrop
            NS.SetSolidColor(entry.bg, c.r, c.g, c.b, c.a or 1)
        end
        if entry.edges then
            LayoutEdges(frame, entry.edges, entry.inset)
            PaintEdges(entry.edges, entry.borderColor)
        end
    end
    for bar, owner in pairs(statusBars) do
        -- Barre tenue par le moteur (durée d'aura) : il peut refuser en combat, reposée à la sortie.
        local texture = self:StatusBarTexture(owner ~= true and owner or nil)
        if not pcall(bar.SetStatusBarTexture, bar, texture) then
            NS:RunOutOfCombat(function() pcall(bar.SetStatusBarTexture, bar, Media:StatusBarTexture(owner ~= true and owner or nil)) end)
        end
        if bar.bg and not bar.darkened then
            local c = theme.backdrop
            NS.SetSolidColor(bar.bg, c.r, c.g, c.b, c.a or 1)
        end
    end
end

NS:On("THEME_CHANGED", function()
    Media:RefreshFonts()
    Media:RefreshBackdrops()
end)
NS:On("PIXEL_CHANGED", function() Media:RefreshBackdrops() end)

NS:On("LOGIN", function() Media:RegisterSharedMedia() end)

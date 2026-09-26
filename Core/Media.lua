-- Core/Media.lua
-- Thème commun : police (taille, contour), couleur d'accent, fond, bordure 1 px, texture
-- de barre. Les textes et les fonds créés par AeonUI s'enregistrent ici et suivent le
-- thème sans /reload (THEME_CHANGED) et l'échelle (PIXEL_CHANGED).
local _, NS = ...

local Media = {}
NS.Media = Media

local FALLBACK_FONT = "Fonts\\FRIZQT__.TTF"
local FLAT_TEXTURE = "Interface\\Buttons\\WHITE8X8"
local registered = setmetatable({}, { __mode = "k" })   -- [fontString] = { sizeDelta, flags }
local backdrops = setmetatable({}, { __mode = "k" })    -- [frame] = { bg, edges, inset }

local function Theme() return NS.db and NS.db.theme end

-- Langues dont les caractères manquent à la police par défaut : police du client à la place.
local LOCALE_FONTS = { koKR = true, zhCN = true, zhTW = true, ruRU = true }

function Media:Font()
    local theme = Theme()
    local font = theme.font
    if LOCALE_FONTS[NS.activeLocale] and font == NS.Database.PROFILE_DEFAULTS.theme.font and _G.STANDARD_TEXT_FONT then
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
    local c = Theme().accent
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

local function Apply(fontString, sizeDelta, flags)
    local path, size = Media:Font()
    local effective = flags or Media:Outline()
    fontString:SetFont(path, size + (sizeDelta or 0), effective)
    if not fontString:GetFont() then
        -- Police disparue (LibSharedMedia désinstallé) : repli sur celle du jeu.
        fontString:SetFont(FALLBACK_FONT, size + (sizeDelta or 0), effective)
    end
    -- Ombre et contour ensemble épaississent le texte : l'un ou l'autre.
    if effective ~= "" then fontString:SetShadowOffset(0, 0) else fontString:SetShadowOffset(1, -1) end
end

--- Crée un FontString aux couleurs du thème. sizeDelta s'ajoute à la taille du thème.
-- flags nil = contour du thème ; une valeur explicite ("" ou "OUTLINE") l'emporte.
function Media:CreateText(parent, layer, sizeDelta, flags)
    local fontString = parent:CreateFontString(nil, layer or "OVERLAY")
    registered[fontString] = { sizeDelta = sizeDelta or 0, flags = flags }
    Apply(fontString, sizeDelta, flags)
    return fontString
end

--- Change le delta de taille d'un texte créé par CreateText (plaques : taille de police propre).
function Media:SetTextSizeDelta(fontString, sizeDelta)
    local style = registered[fontString]
    if not style then return end
    style.sizeDelta = sizeDelta or 0
    Apply(fontString, style.sizeDelta, style.flags)
end

function Media:RefreshFonts()
    for fontString, style in pairs(registered) do
        Apply(fontString, style.sizeDelta, style.flags)
    end
end

--------------------------------------------------------------------------------
-- Fonds, bordures, barres
--------------------------------------------------------------------------------

--- Texture plate pour les barres de statut : celle du thème via LibSharedMedia si elle existe.
function Media:StatusBarTexture()
    local theme = Theme()
    local name = theme and theme.statusbar
    if name and name ~= "" and _G.LibStub then
        local LSM = LibStub("LibSharedMedia-3.0", true)
        local path = LSM and LSM:Fetch("statusbar", name, true)
        if path then return path end
    end
    return FLAT_TEXTURE
end

local EDGES = { "top", "bottom", "left", "right" }

local function LayoutEdges(frame, edges, inset)
    local px = NS.Pixel:Scale(1)
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
    local c = color or Theme().border
    for _, side in ipairs(EDGES) do NS.SetSolidColor(edges[side], c.r, c.g, c.b, c.a or 1) end
end

--- Bordure de 1 pixel physique autour de `frame` (quatre textures), couleur du thème
-- ou `color` fixe. Retourne la table des quatre textures.
function Media:CreateBorder(frame, color, inset)
    local edges = {}
    for _, side in ipairs(EDGES) do edges[side] = frame:CreateTexture(nil, "BORDER") end
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
-- La barre suit THEME_CHANGED (texture, fond) sans /reload.
function Media:CreateStatusBar(parent)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetStatusBarTexture(self:StatusBarTexture())
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints(bar)
    local c = Theme().backdrop
    NS.SetSolidColor(bar.bg, c.r, c.g, c.b, c.a or 1)
    statusBars[bar] = true
    return bar
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
    local texture = self:StatusBarTexture()
    for bar in pairs(statusBars) do
        bar:SetStatusBarTexture(texture)
        if bar.bg then
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

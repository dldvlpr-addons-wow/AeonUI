-- Core/Glow.lua
-- Lueur commune à tous les modules, quatre styles :
--   * pixel : traits qui défilent le long du bord ;
--   * autocast : étincelles de tailles décroissantes qui tournent autour du cadre ;
--   * button : halo du clignotement d'action Blizzard (texture IconAlert), pulsé ;
--   * classic : aplat de couleur derrière le cadre, pulsé.
-- Pixel et autocast : un seul OnUpdate pour toutes les lueurs, posé seulement s'il en reste une.
-- Textures créées une fois par cadre et par style, puis réutilisées (budget de textures du client).
local _, NS = ...
local L = NS.L

local Glow = { animated = {} }
NS.Glow = Glow

Glow.STYLES = { "pixel", "autocast", "button", "classic" }
local KNOWN = {}
for _, style in ipairs(Glow.STYLES) do KNOWN[style] = true end

local DEFAULT_COLOR = { r = 0.95, g = 0.95, b = 0.32, a = 1 }
local PIXEL = { count = 8, length = 8, thickness = 2, period = 4, offset = 2 }
local AUTOCAST = { perGroup = 4, sizes = { 5, 4, 3, 2 }, periods = { 8, 7, 6, 5 }, offset = 1 }
local ICON_ALERT = "Interface\\SpellActivationOverlay\\IconAlert"
local ICON_ALERT_COORDS = { 0.00781250, 0.50781250, 0.27734375, 0.52734375 }   -- halo extérieur
local BUTTON_SPREAD = 0.2   -- halo : 20 % de la largeur du cadre de chaque côté

local function S(n) return NS.Pixel:Scale(n) end

--------------------------------------------------------------------------------
-- Pièces
--------------------------------------------------------------------------------

local function Pulse(texture)
    local group = texture:CreateAnimationGroup()
    group:SetLooping("BOUNCE")
    local fade = group:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0.3)
    fade:SetDuration(0.6)
    texture.pulse = group
end

local function Parts(frame, style)
    frame.aeonGlowParts = frame.aeonGlowParts or {}
    local parts = frame.aeonGlowParts[style]
    if parts then return parts end
    parts = {}
    if style == "pixel" then
        for i = 1, PIXEL.count do
            local line = frame:CreateTexture(nil, "OVERLAY", nil, 7)
            line.period, line.phase = PIXEL.period, (i - 1) / PIXEL.count
            parts[i] = line
        end
    elseif style == "autocast" then
        for group, size in ipairs(AUTOCAST.sizes) do
            for i = 1, AUTOCAST.perGroup do
                local spark = frame:CreateTexture(nil, "OVERLAY", nil, 7)
                spark:SetSize(S(size), S(size))
                spark.period = AUTOCAST.periods[group]
                spark.phase = (i - 1) / AUTOCAST.perGroup + group * 0.04   -- groupes décalés, en traîne
                parts[#parts + 1] = spark
            end
        end
    elseif style == "button" then
        local halo = frame:CreateTexture(nil, "OVERLAY", nil, 7)
        -- Fichier absent du client : aplat à la place.
        if halo:SetTexture(ICON_ALERT) == false then halo.solid = true end
        halo:SetTexCoord(unpack(ICON_ALERT_COORDS))
        halo:SetBlendMode("ADD")
        Pulse(halo)
        parts[1] = halo
    else
        local back = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
        back:SetPoint("TOPLEFT", frame, "TOPLEFT", -4, 4)
        back:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 4, -4)
        Pulse(back)
        parts[1] = back
    end
    for _, part in ipairs(parts) do part:Hide() end
    frame.aeonGlowParts[style] = parts
    return parts
end

--------------------------------------------------------------------------------
-- Animation (pixel, autocast)
--------------------------------------------------------------------------------

--- Point du périmètre à la distance `p` du coin haut gauche, sens horaire ; vrai sur un bord horizontal.
function Glow.PerimeterPoint(p, width, height)
    if p < width then return p, 0, true end
    p = p - width
    if p < height then return width, -p, false end
    p = p - height
    if p < width then return width - p, -height, true end
    p = p - width
    return 0, -(height - p), false
end

local function Animate(frame, style, now)
    local width, height = frame:GetWidth(), frame:GetHeight()
    if not (width and height) or width <= 0 or height <= 0 then return end
    local offset = S(style == "pixel" and PIXEL.offset or AUTOCAST.offset)
    width, height = width + 2 * offset, height + 2 * offset
    local perimeter = 2 * (width + height)
    local length, thickness = S(PIXEL.length), S(PIXEL.thickness)
    for _, part in ipairs(frame.aeonGlowParts[style]) do
        local p = ((now / part.period + part.phase) % 1) * perimeter
        local x, y, horizontal = Glow.PerimeterPoint(p, width, height)
        part:ClearAllPoints()
        part:SetPoint("CENTER", frame, "TOPLEFT", x - offset, y + offset)
        if style == "pixel" then
            if horizontal then part:SetSize(length, thickness) else part:SetSize(thickness, length) end
        end
    end
end

local driver = CreateFrame("Frame")
local function Tick()
    local now = GetTime()
    for frame, style in pairs(Glow.animated) do
        if frame:IsVisible() then Animate(frame, style, now) end
    end
end

local function UpdateDriver()
    driver:SetScript("OnUpdate", next(Glow.animated) and Tick or nil)
end

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

--- Lueur `style` (Glow.STYLES, pixel si inconnu) sur `frame`, couleur { r, g, b, a } (nil : jaune
-- pâle ; halo « button » : couleurs de la texture). Rappel avec le même style : couleur seule.
function Glow.Show(frame, style, color)
    if not KNOWN[style] then style = "pixel" end
    if frame.aeonGlow and frame.aeonGlow ~= style then Glow.Hide(frame) end
    local parts = Parts(frame, style)
    for _, part in ipairs(parts) do
        if style == "button" and not part.solid then
            if color then part:SetVertexColor(color.r, color.g, color.b, color.a or 1) else part:SetVertexColor(1, 1, 1, 1) end
        else
            local c = color or DEFAULT_COLOR
            NS.SetSolidColor(part, c.r, c.g, c.b, c.a or 1)
        end
    end
    if frame.aeonGlow == style then return end
    frame.aeonGlow = style
    if style == "button" then
        -- ponytail: halo calé sur la taille à l'allumage ; suivre OnSizeChanged si un cadre lueur change de taille.
        local spread = (frame:GetWidth() or 0) * BUTTON_SPREAD
        parts[1]:ClearAllPoints()
        parts[1]:SetPoint("TOPLEFT", frame, "TOPLEFT", -spread, spread)
        parts[1]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", spread, -spread)
    end
    for _, part in ipairs(parts) do
        part:Show()
        if part.pulse then part.pulse:Play() end
    end
    if style == "pixel" or style == "autocast" then
        Glow.animated[frame] = style
        Animate(frame, style, GetTime())
        UpdateDriver()
    end
end

function Glow.Hide(frame)
    local style = frame.aeonGlow
    if not style then return end
    frame.aeonGlow = nil
    for _, part in ipairs(frame.aeonGlowParts[style]) do
        part:Hide()
        if part.pulse then part.pulse:Stop() end
    end
    Glow.animated[frame] = nil
    UpdateDriver()
end

function Glow.Set(frame, on, style, color)
    if on then Glow.Show(frame, style, color) else Glow.Hide(frame) end
end

--- Style affiché sur `frame`, ou nil.
function Glow.Current(frame) return frame.aeonGlow end

--- Choix pour une liste déroulante d'options.
function Glow.Choices()
    local choices = {}
    for _, style in ipairs(Glow.STYLES) do
        choices[#choices + 1] = { name = L["GLOW_" .. style:upper()], value = style }
    end
    return choices
end

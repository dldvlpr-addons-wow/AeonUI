-- Core/Pixel.lua
-- Échelle « pixel perfect » : une unité d'interface = un pixel physique.
-- Formule publique : UIParent à l'échelle 768 / hauteur physique ; toute taille ou
-- position passe par Pixel:Scale pour tomber sur un pixel entier (bordures nettes à 1 px).
-- NS.db.theme.uiScale (0,5 à 1,5) multiplie cette base : plus grand ou plus petit au choix,
-- les tailles restent arrondies au pixel via Pixel:Scale.
-- Aucun CVar modifié : UIParent:SetScale suffit et se rend au décochage.
local _, NS = ...

local Pixel = { mult = 1, originalScale = nil, queued = false }
NS.Pixel = Pixel

local MIN_SCALE, MAX_SCALE = 0.4, 1.5
Pixel.MIN_USER_SCALE, Pixel.MAX_USER_SCALE = 0.5, 1.5

local function PhysicalHeight()
    if GetPhysicalScreenSize then
        local ok, _, height = pcall(GetPhysicalScreenSize)
        if ok and type(height) == "number" and height > 0 then return height end
    end
    return 768
end

--- Recalcule le multiplicateur depuis l'échelle courante d'UIParent.
function Pixel:Update()
    local scale = UIParent:GetScale() or 1
    if scale <= 0 then scale = 1 end
    self.mult = 768 / PhysicalHeight() / scale
end

--- Arrondit n au pixel physique le plus proche. Jamais 0 pour n non nul.
function Pixel:Scale(n)
    n = tonumber(n) or 0
    if n == 0 then return 0 end
    local m = self.mult
    local value = m * math.floor(n / m + 0.5)
    if value == 0 then value = n > 0 and m or -m end
    return value
end

--- Multiplicateur utilisateur, borné ; 1 par défaut.
function Pixel:UserScale()
    local value = tonumber(NS.db and NS.db.theme and NS.db.theme.uiScale) or 1
    if value < self.MIN_USER_SCALE then value = self.MIN_USER_SCALE
    elseif value > self.MAX_USER_SCALE then value = self.MAX_USER_SCALE end
    return value
end

--- Applique (ou rend) l'échelle d'UIParent selon NS.db.theme.pixelPerfect et uiScale, hors combat.
function Pixel:Apply()
    if self.queued then return end   -- THEME_CHANGED à chaque image de la roue de couleur : une seule file
    self.queued = true
    NS:RunOutOfCombat(function()
        self.queued = false
        local pixelPerfect = NS.db and NS.db.theme and NS.db.theme.pixelPerfect
        local user = self:UserScale()
        if pixelPerfect or user ~= 1 then
            if not self.originalScale then self.originalScale = UIParent:GetScale() or 1 end
            local base = pixelPerfect and (768 / PhysicalHeight()) or self.originalScale
            local scale = base * user
            if scale < MIN_SCALE then scale = MIN_SCALE elseif scale > MAX_SCALE then scale = MAX_SCALE end
            if math.abs((UIParent:GetScale() or 0) - scale) > 0.0005 then UIParent:SetScale(scale) end
            self.applied = scale
        elseif self.originalScale then
            UIParent:SetScale(self.originalScale)
            self.originalScale, self.applied = nil, nil
        end
        self:Update()
        NS:Fire("PIXEL_CHANGED")
    end)
end

Pixel:Update()

local events = CreateFrame("Frame")
events:RegisterEvent("UI_SCALE_CHANGED")
events:RegisterEvent("DISPLAY_SIZE_CHANGED")
events:SetScript("OnEvent", function()
    -- Blizzard vient de reposer son échelle : on remet la nôtre si demandée, sinon on suit.
    -- Le joueur a changé l'échelle du jeu pendant que la nôtre était posée : c'est la nouvelle
    -- échelle d'origine à rendre au décochage.
    local current = UIParent:GetScale() or 1
    if Pixel.originalScale and Pixel.applied and math.abs(current - Pixel.applied) > 0.0005 then
        Pixel.originalScale = current
    end
    if NS.db then Pixel:Apply() else Pixel:Update() end
end)

NS:On("LOGIN", function() Pixel:Apply() end)
NS:On("THEME_CHANGED", function() Pixel:Apply() end)

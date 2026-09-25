-- Core/Movers.lua
-- Déverrouillage : chaque cadre mobile s'enregistre ici avec une clé et une position par
-- défaut. Le cadre réel n'est jamais rendu déplaçable : en mode déverrouillé, un calque
-- coloré de sa taille se pose dessus et c'est lui qu'on glisse. Au lâcher, le calque
-- s'aimante (bords et centre de l'écran, autres calques), la position est arrondie au
-- pixel et sauvée dans NS.db.anchors[clé] = { point, relPoint, x, y } (format inchangé),
-- puis le cadre réel est reposé, hors combat s'il est protégé.
-- Clavier sur le calque sélectionné : flèches = 1 px, Maj+flèches = 10 px.
-- Clic droit sur un calque : options du module qui le possède ; Maj + clic droit : position
-- par défaut. Maj pendant le glisser : pas d'aimant. Barre d'outils en haut de l'écran :
-- grille, filtre par module, tout réinitialiser, verrouiller.
-- Ancrage : un mover peut suivre un autre mover (champs `target`, point relatif, x/y relatifs
-- à la cible), avec une position de secours (`fallback`) quand la cible n'est pas enregistrée,
-- un axe fixé à l'écran (`edgeX` / `edgeY`) et la largeur / hauteur de la cible (`matchWidth`,
-- `matchHeight`). Panneau des coordonnées : « Ancrer à… » puis clic sur la cible.
local _, NS = ...
local L = NS.L
local Media = NS.Media

local Movers = { registry = {}, overlays = {}, unlocked = false, selected = nil }
NS.Movers = Movers

local SNAP_THRESHOLD = 8
local ARROWS = { LEFT = { -1, 0 }, RIGHT = { 1, 0 }, UP = { 0, 1 }, DOWN = { 0, -1 } }
local MAX_GRID_LINES = 400

--------------------------------------------------------------------------------
-- Fonctions pures (testées hors jeu)
--------------------------------------------------------------------------------

--- Point d'ancrage le plus parlant pour un centre (cx, cy) sur un écran width x height :
-- tiers gauche/droit et haut/bas, sinon CENTER. Une position près d'un bord reste près
-- de ce bord quand la résolution change.
function Movers.PointFor(cx, cy, width, height)
    local h = cx < width / 3 and "LEFT" or cx > width * 2 / 3 and "RIGHT" or ""
    local v = cy > height * 2 / 3 and "TOP" or cy < height / 3 and "BOTTOM" or ""
    local point = v .. h
    return point == "" and "CENTER" or point
end

--- Décalage (x, y) du rectangle (left, bottom, width, height) par rapport au même point d'UIParent.
function Movers.OffsetFor(point, left, bottom, width, height, screenWidth, screenHeight)
    local x, y
    if point:find("LEFT") then x = left
    elseif point:find("RIGHT") then x = left + width - screenWidth
    else x = left + width / 2 - screenWidth / 2 end
    if point:find("TOP") then y = bottom + height - screenHeight
    elseif point:find("BOTTOM") then y = bottom
    else y = bottom + height / 2 - screenHeight / 2 end
    return x, y
end

--- Aimant : rapproche le rectangle des lignes verticales `xLines` et horizontales `yLines`
-- (bord ou centre) si l'écart est sous `threshold`. Retourne (dx, dy), 0 si rien n'accroche.
function Movers.SnapDelta(left, bottom, width, height, xLines, yLines, threshold)
    local function best(edges, lines)
        local chosen
        for _, line in ipairs(lines) do
            for _, edge in ipairs(edges) do
                local d = line - edge
                if math.abs(d) <= threshold and (not chosen or math.abs(d) < math.abs(chosen)) then chosen = d end
            end
        end
        return chosen or 0
    end
    local dx = best({ left, left + width / 2, left + width }, xLines)
    local dy = best({ bottom, bottom + height / 2, bottom + height }, yLines)
    return dx, dy
end

--- Coordonnées du point `point` (TOPLEFT, CENTER…) d'un rectangle { left, bottom, width, height }.
function Movers.PointPosition(point, rect)
    local x, y = rect.left + rect.width / 2, rect.bottom + rect.height / 2
    if point:find("LEFT") then x = rect.left elseif point:find("RIGHT") then x = rect.left + rect.width end
    if point:find("TOP") then y = rect.bottom + rect.height elseif point:find("BOTTOM") then y = rect.bottom end
    return x, y
end

--- Côté de la cible où coller l'enfant : l'axe où l'écart entre les deux rectangles est le plus
-- grand. Rend (point de l'enfant, point de la cible), ex. TOP / BOTTOM pour un enfant en dessous.
function Movers.SideFor(child, target)
    local cx, cy = Movers.PointPosition("CENTER", child)
    local tx, ty = Movers.PointPosition("CENTER", target)
    local gapX = math.abs(cx - tx) - (child.width + target.width) / 2
    local gapY = math.abs(cy - ty) - (child.height + target.height) / 2
    if gapY >= gapX then
        if cy < ty then return "TOP", "BOTTOM" end
        return "BOTTOM", "TOP"
    end
    if cx > tx then return "LEFT", "RIGHT" end
    return "RIGHT", "LEFT"
end

--- Décalage (x, y) qui laisse l'enfant où il est une fois ancré de `point` sur `relPoint` de la cible.
function Movers.RelativeOffset(point, relPoint, child, target)
    local cx, cy = Movers.PointPosition(point, child)
    local tx, ty = Movers.PointPosition(relPoint, target)
    return cx - tx, cy - ty
end

--- Vrai si ancrer `key` sur `target` ferait une boucle (la cible suit déjà `key`, directement ou non).
function Movers.WouldCreateCycle(key, target, anchors)
    local steps = 0
    while target and steps < 100 do
        if target == key then return true end
        local a = anchors[target]
        target = type(a) == "table" and a.target or nil
        steps = steps + 1
    end
    return steps >= 100
end

--------------------------------------------------------------------------------
-- Registre et positions
--------------------------------------------------------------------------------

local function Anchor(entry)
    local saved = NS.db and NS.db.anchors and NS.db.anchors[entry.key]
    if saved then return saved end
    return { point = entry.point, relPoint = entry.point, x = entry.x, y = entry.y }
end

local function CoordsText(entry)
    local a = Anchor(entry)
    return string.format("%s  %d, %d", a.point, math.floor(a.x + 0.5), math.floor(a.y + 0.5))
end

--- « Ancré à : <cible> », ou nil si le mover suit l'écran.
local function AnchoredText(entry)
    local a = Anchor(entry)
    local target = a.target and Movers.registry[a.target]
    return target and string.format(L.MOVER_ANCHORED_TO, target.label) or nil
end

--- Rectangle rendu d'un mover, en unités d'UIParent : son calque s'il est affiché, sinon son cadre.
local function Rect(entry)
    local region = entry.overlay and entry.overlay:IsShown() and entry.overlay or entry.frame
    local left, bottom = region:GetLeft(), region:GetBottom()
    if not (left and bottom) then return nil end
    return { left = left, bottom = bottom, width = region:GetWidth() or 0, height = region:GetHeight() or 0 }
end

--- Position absolue (relative à UIParent) d'un rectangle, arrondie au pixel.
local function AbsoluteAnchor(rect)
    local screenWidth, screenHeight = UIParent:GetWidth(), UIParent:GetHeight()
    local point = Movers.PointFor(rect.left + rect.width / 2, rect.bottom + rect.height / 2, screenWidth, screenHeight)
    local x, y = Movers.OffsetFor(point, rect.left, rect.bottom, rect.width, rect.height, screenWidth, screenHeight)
    return { point = point, relPoint = point, x = NS.Pixel:Scale(x), y = NS.Pixel:Scale(y) }
end

--- Movers enregistrés ancrés sur `key`.
local function Dependents(key)
    local list = {}
    local anchors = NS.db and NS.db.anchors
    if not anchors then return list end
    for other in pairs(Movers.registry) do
        local a = anchors[other]
        if a and a.target == key then list[#list + 1] = other end
    end
    return list
end

-- Le calque a sa propre taille : StartMoving le réancre sur un seul point, un calque
-- dimensionné par SetAllPoints retomberait à 0x0 pendant le glisser.
local function Attach(entry)
    local overlay = entry.overlay
    if not overlay then return end
    local width, height = entry.frame:GetWidth() or 0, entry.frame:GetHeight() or 0
    overlay:SetSize(width > 0 and width or 40, height > 0 and height or 20)
    overlay:ClearAllPoints()
    overlay:SetPoint("TOPLEFT", entry.frame, "TOPLEFT", 0, 0)
    overlay.coords:SetText(CoordsText(entry))
    if Movers.selected == entry.key and Movers.RefreshCoords then Movers.RefreshCoords() end
end

local BuildOverlay   -- défini plus bas

--- Enregistre (ou ré-enregistre) un cadre mobile. Ne le positionne pas : voir Load.
function Movers:Register(key, frame, label, defaultPoint, defaultX, defaultY)
    local entry = self.registry[key] or { key = key, overlay = self.overlays[key] }
    entry.frame, entry.label = frame, label or key
    -- Module qui enregistre le mover (clic droit : ses options ; filtre de la barre d'outils).
    entry.module = entry.module or NS.Modules.calling
    if entry.overlay then entry.overlay.entry = entry end
    entry.point, entry.x, entry.y = defaultPoint or "CENTER", defaultX or 0, defaultY or 0
    self.registry[key] = entry
    if self.unlocked then
        if not entry.overlay then BuildOverlay(entry) end
        Attach(entry)
        entry.overlay:SetShown(Movers:IsListed(entry))
    end
    return entry
end

--- Pose un cadre Blizzard sur un support déplaçable sans le reparenter (systèmes Edit Mode) :
-- le support porte le mover, le cadre y est réancré, et un hook de SetPoint reprend la main
-- si Blizzard le replace. Rend le support. Release(key) retire le mover ; le cadre garde sa
-- place jusqu'au /reload.
Movers.adopted = Movers.adopted or {}   -- [key] = { holder, frame, anchoring }
function Movers:Adopt(key, frame, label, defaultPoint, defaultX, defaultY, anchor)
    local entry = self.adopted[key]
    if not entry then
        entry = { holder = CreateFrame("Frame", "AeonUI_Holder_" .. key, UIParent), hooked = {} }
        entry.holder:SetFrameStrata("LOW")
        self.adopted[key] = entry
    end
    entry.frame = frame   -- un second Adopt peut résoudre un autre cadre (chargement différé)
    if not entry.hooked[frame] then
        entry.hooked[frame] = true
        hooksecurefunc(frame, "SetPoint", function(self)
            if entry.active and entry.frame == self and not entry.anchoring then Movers:Reanchor(key) end
        end)
    end
    entry.active = true
    entry.anchor = anchor or "TOPLEFT"
    local width, height = frame:GetWidth() or 0, frame:GetHeight() or 0
    entry.holder:SetSize(width > 0 and width or 40, height > 0 and height or 20)
    entry.holder:Show()
    self:Register(key, entry.holder, label, defaultPoint, defaultX, defaultY)
    self:Load(key)
    self:Reanchor(key)
    return entry.holder
end

function Movers:Reanchor(key)
    local entry = self.adopted[key]
    if not entry or not entry.active or entry.anchoring then return end
    local frame = entry.frame
    local function place()
        if not entry.active or entry.frame ~= frame then return end
        entry.anchoring = true
        local ok, err = pcall(function()
            NS.ClearPointsRaw(frame)   -- systèmes Edit Mode : sans leur surcharge Lua (Compat)
            NS.SetPointRaw(frame, entry.anchor, entry.holder, entry.anchor, 0, 0)
        end)
        entry.anchoring = false   -- toujours rendu : sinon la clé ne suit plus jamais son mover
        if not ok then geterrorhandler()(err) end
    end
    -- Cadre protégé en combat : Blizzard vient de le poser, on le reprend à la sortie.
    if frame.IsProtected and frame:IsProtected() and NS.InCombat() then
        if not entry.pending then
            entry.pending = true
            NS:RunOutOfCombat(function() entry.pending = false place() end)
        end
        return
    end
    place()
end

function Movers:Release(key)
    local entry = self.adopted[key]
    if not entry then return end
    entry.active = false
    entry.holder:Hide()
    self:Unregister(key)
end

--- Retire un cadre du déverrouillage (son calque disparaît). La position sauvée reste.
function Movers:Unregister(key)
    local entry = self.registry[key]
    if not entry then return end
    if entry.overlay then entry.overlay:Hide() end
    if self.selected == key then self.selected = nil end
    self.registry[key] = nil
    -- Les éléments ancrés dessus retombent sur leur position de secours.
    for _, other in ipairs(Dependents(key)) do self:Load(other) end
end

-- Taille reprise de la cible (largeur et/ou hauteur). `entry.sizing` : nos propres SetWidth ne
-- relancent pas le hook qui reprend la main quand le module redimensionne son cadre.
local function ApplySize(entry, a, target)
    if not (target and (a.matchWidth or a.matchHeight)) then return end
    local width, height = target.frame:GetWidth() or 0, target.frame:GetHeight() or 0
    entry.sizing = true
    local ok, err = pcall(function()
        if a.matchWidth and width > 0 then entry.frame:SetWidth(width) end
        if a.matchHeight and height > 0 then entry.frame:SetHeight(height) end
    end)
    entry.sizing = false
    if not ok then geterrorhandler()(err) end
end

-- Axe fixé à l'écran (ancrage croisé) : l'enfant suit sa cible sur un axe, garde sur l'autre
-- le bord gauche (edgeX) ou bas (edgeY) mémorisé. Recalculé à chaque pose.
local function ApplyEdges(frame, a, targetFrame)
    if not (a.edgeX or a.edgeY) then return end
    local left, bottom = frame:GetLeft(), frame:GetBottom()
    if not (left and bottom) then return end
    local x = a.x + (a.edgeX and (a.edgeX - left) or 0)
    local y = a.y + (a.edgeY and (a.edgeY - bottom) or 0)
    frame:ClearAllPoints()
    frame:SetPoint(a.point, targetFrame, a.relPoint, x, y)
end

-- Suivi des cadres déjà branchés (un cadre ré-enregistré garde ses hooks).
local sizeHooked = setmetatable({}, { __mode = "k" })
local targetHooked = setmetatable({}, { __mode = "k" })

local function HookSizes(entry, target)
    local frame = entry.frame
    if not sizeHooked[frame] then
        sizeHooked[frame] = true
        local function reapply()
            local current = Movers.registry[entry.key]
            if not current or current.frame ~= frame or current.sizing then return end
            local a = NS.db and NS.db.anchors[entry.key]
            if a and (a.matchWidth or a.matchHeight) then Movers:Load(entry.key) end
        end
        for _, method in ipairs({ "SetWidth", "SetHeight", "SetSize" }) do hooksecurefunc(frame, method, reapply) end
    end
    local targetFrame = target.frame
    if not targetHooked[targetFrame] then
        targetHooked[targetFrame] = true
        targetFrame:HookScript("OnSizeChanged", function()
            for key, t in pairs(Movers.registry) do
                if t.frame == targetFrame then
                    for _, other in ipairs(Dependents(key)) do Movers:Load(other) end
                end
            end
        end)
    end
end

local function Refit(entry)
    -- Taille rendue au module : il la repose lui-même à son rafraîchissement.
    if entry.module then NS.Modules:Refresh(entry.module) end
end

-- Ancien ancrage qui reprenait la taille de sa cible : le module la reprend.
local function RefitIfMatched(entry, old)
    if old and (old.matchWidth or old.matchHeight) then Refit(entry) end
end

local loading = {}   -- garde contre une boucle venue d'un profil importé

--- Pose le cadre depuis la position sauvée ou le défaut. Différé hors combat si protégé.
-- Ancré sur un autre mover : posé sur son cadre ; cible absente : position de secours.
-- Les éléments ancrés sur celui-ci sont reposés ensuite.
function Movers:Load(key)
    local entry = self.registry[key]
    if not entry or loading[key] then return false end
    local frame = entry.frame
    local function place()
        local a = Anchor(entry)
        -- Boucle venue d'un profil importé (A sur B, B sur A) : SetPoint lèverait une erreur.
        local target = a.target and not Movers.WouldCreateCycle(key, a.target, NS.db.anchors)
            and self.registry[a.target]
        frame:ClearAllPoints()
        if target then
            frame:SetPoint(a.point, target.frame, a.relPoint, a.x, a.y)
            ApplySize(entry, a, target)
            ApplyEdges(frame, a, target.frame)
            HookSizes(entry, target)
        else
            -- Cible absente sans secours : décalages relatifs inutilisables, position par défaut.
            local f = a.target and (a.fallback or { point = entry.point, relPoint = entry.point, x = entry.x, y = entry.y }) or a
            frame:SetPoint(f.point, UIParent, f.relPoint, f.x, f.y)
        end
        Attach(entry)
        loading[key] = true
        local ok, err = pcall(function()
            for _, other in ipairs(Dependents(key)) do self:Load(other) end
        end)
        loading[key] = nil   -- toujours rendu : sinon la clé ne serait plus jamais reposée
        if not ok then geterrorhandler()(err) end
    end
    local protected = frame.IsProtected and frame:IsProtected()
    if protected and NS.InCombat() then
        NS:RunOutOfCombat(place)
        return false
    end
    place()
    return true
end

--- Sauve une position arrondie au pixel physique. L'ancrage (cible, secours, axes fixés,
-- tailles reprises) déjà sauvé est conservé : x et y restent relatifs à la cible.
function Movers:Save(key, point, relPoint, x, y)
    local old = NS.db.anchors[key]
    local a = { point = point, relPoint = relPoint or point, x = NS.Pixel:Scale(x), y = NS.Pixel:Scale(y) }
    if old and old.target then
        a.target, a.fallback, a.edgeX, a.edgeY = old.target, old.fallback, old.edgeX, old.edgeY
        a.matchWidth, a.matchHeight = old.matchWidth, old.matchHeight
    end
    NS.db.anchors[key] = a
end

--- Ancre `key` sur le mover `targetKey`, au côté le plus proche, sans le déplacer. Refusé si
-- la cible suit déjà `key` (boucle), en combat pour un cadre protégé, ou sans rectangle rendu.
function Movers:AttachTo(key, targetKey)
    local entry, target = self.registry[key], self.registry[targetKey]
    if not (entry and target) or key == targetKey then return false end
    if Movers.WouldCreateCycle(key, targetKey, NS.db.anchors) then
        NS.Print(L.MOVER_ANCHOR_CYCLE)
        return false
    end
    local protected = entry.frame.IsProtected and entry.frame:IsProtected()
    if NS.InCombat() and protected then return false end
    -- Cadre protégé sur une cible qui ne l'est pas : la cible deviendrait protégée et son module
    -- ne pourrait plus la redimensionner en combat.
    if protected and not (target.frame.IsProtected and target.frame:IsProtected()) then
        NS.Print(L.MOVER_ANCHOR_PROTECTED)
        return false
    end
    local child, parent = Rect(entry), Rect(target)
    if not (child and parent) then return false end
    local point, relPoint = Movers.SideFor(child, parent)
    local x, y = Movers.RelativeOffset(point, relPoint, child, parent)
    NS.db.anchors[key] = { point = point, relPoint = relPoint, x = NS.Pixel:Scale(x), y = NS.Pixel:Scale(y),
                           target = targetKey, fallback = AbsoluteAnchor(child) }
    self:Load(key)
    return true
end

--- Rend `key` à l'écran, à l'endroit exact où il est.
function Movers:Detach(key)
    local entry = self.registry[key]
    local rect = entry and Rect(entry)
    if not rect then return false end
    local old = NS.db.anchors[key]
    NS.db.anchors[key] = AbsoluteAnchor(rect)
    self:Load(key)
    RefitIfMatched(entry, old)
    return true
end


--- Largeur ("width") ou hauteur ("height") reprise de la cible, ou rendue au module.
function Movers:SetMatch(key, axis, on)
    local a = NS.db.anchors[key]
    if not (a and a.target) then return false end
    if axis == "width" then a.matchWidth = on or nil else a.matchHeight = on or nil end
    if not on and self.registry[key] then Refit(self.registry[key]) end
    self:Load(key)
    return true
end

--- Axe ("x" ou "y") fixé à l'écran à la position actuelle, ou rendu à la cible.
function Movers:SetEdge(key, axis, on)
    local a = NS.db.anchors[key]
    local entry = self.registry[key]
    local rect = entry and Rect(entry)
    if not (a and a.target and rect) then return false end
    if axis == "x" then a.edgeX = on and rect.left or nil else a.edgeY = on and rect.bottom or nil end
    self:Load(key)
    return true
end

--- Centre `key` à l'écran. Largeur (ou hauteur) impaire en pixels physiques sur un écran pair :
-- le centre exact tombe entre deux pixels, décalé d'un demi-pixel pour garder des bords nets.
function Movers:CenterOnScreen(key)
    local entry = self.registry[key]
    if not entry then return false end
    if NS.InCombat() and entry.frame.IsProtected and entry.frame:IsProtected() then return false end
    local mult = NS.Pixel.mult
    local function half(size, screen)
        local pixels = math.floor(size / mult + 0.5)
        local screenPixels = math.floor(screen / mult + 0.5)
        return (screenPixels - pixels) % 2 == 1 and -mult / 2 or 0
    end
    local old = NS.db.anchors[key]
    NS.db.anchors[key] = { point = "CENTER", relPoint = "CENTER",
                           x = half(entry.frame:GetWidth() or 0, UIParent:GetWidth()),
                           y = half(entry.frame:GetHeight() or 0, UIParent:GetHeight()) }
    self:Load(key)
    RefitIfMatched(entry, old)
    return true
end

--- Oublie la position sauvée, enregistrée ou non (TopBar hors mode libre n'est pas enregistrée).
function Movers:Reset(key)
    local old = NS.db.anchors[key]
    NS.db.anchors[key] = nil
    if self.registry[key] then
        self:Load(key)
        RefitIfMatched(self.registry[key], old)
    end
end

function Movers:ResetAll()
    for key in pairs(NS.db.anchors) do NS.db.anchors[key] = nil end
    for key in pairs(self.registry) do self:Load(key) end
end

--- Décale la position sauvée de (dx, dy) unités d'interface.
function Movers:Nudge(key, dx, dy)
    local entry = self.registry[key]
    if not entry then return end
    local a = Anchor(entry)
    if a.target and not self.registry[a.target] and a.fallback then
        -- Cible absente : la position de secours est celle qu'on voit.
        a.fallback.x = NS.Pixel:Scale(a.fallback.x + dx)
        a.fallback.y = NS.Pixel:Scale(a.fallback.y + dy)
        self:Load(key)
        return
    end
    self:Save(key, a.point, a.relPoint, a.x + dx, a.y + dy)
    -- Axe fixé à l'écran : c'est lui qu'on décale.
    local saved = NS.db.anchors[key]
    if saved.edgeX then saved.edgeX = saved.edgeX + dx end
    if saved.edgeY then saved.edgeY = saved.edgeY + dy end
    self:Load(key)
    -- Ancré : le secours suit le déplacement, comme au glisser.
    local rect = saved.target and Rect(entry)
    if rect then saved.fallback = AbsoluteAnchor(rect) end
end

--- Clés enregistrées, triées.
function Movers:List()
    local keys = {}
    for key in pairs(self.registry) do keys[#keys + 1] = key end
    table.sort(keys)
    return keys
end

function Movers:Anchor(key)
    local entry = self.registry[key]
    return entry and Anchor(entry) or nil
end

--------------------------------------------------------------------------------
-- Calques
--------------------------------------------------------------------------------

local function PaintOverlay(entry, selected)
    local r, g, b = Media:Accent()
    NS.SetSolidColor(entry.overlay.bg, r, g, b, selected and 0.55 or 0.3)
    for _, edge in pairs(entry.overlay.edges) do NS.SetSolidColor(edge, r, g, b, 1) end
end

function Movers:Select(key)
    self.selected = key
    for other, entry in pairs(self.registry) do
        if entry.overlay then
            local isSelected = other == key
            PaintOverlay(entry, isSelected)
            -- En combat, OnKeyDown ne rend pas les touches (SetPropagateKeyboardInput protégé) :
            -- pas de clavier du tout, sinon le calque avalerait les raccourcis.
            entry.overlay:EnableKeyboard(isSelected and not NS.InCombat())
        end
    end
    if self.RefreshCoords then self.RefreshCoords() end
end

--------------------------------------------------------------------------------
-- Coordonnées saisies : X et Y du mover sélectionné, relatifs à son point d'ancrage.
--------------------------------------------------------------------------------

local coordsPanel

local function CoordsBox(label, anchor, onEnter)
    local box = CreateFrame("EditBox", nil, coordsPanel, "InputBoxTemplate")
    box:SetSize(60, 20)
    box:SetAutoFocus(false)
    box:SetPoint("LEFT", anchor, "RIGHT", 24, 0)
    box.label = Media:CreateText(coordsPanel, "OVERLAY")
    box.label:SetPoint("RIGHT", box, "LEFT", -6, 0)
    box.label:SetText(label)
    box:SetScript("OnEnterPressed", function(self) onEnter() self:ClearFocus() end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() Movers.RefreshCoords() end)
    return box
end

--- Applique les valeurs tapées au mover sélectionné (position sauvée puis cadre reposé).
function Movers:ApplyCoords(x, y)
    local entry = self.selected and self.registry[self.selected]
    x, y = tonumber(x), tonumber(y)
    if not (entry and x and y) then return false end
    -- NaN, infini ou hors écran : refusé (un cadre perdu ne se rattrape plus au glisser).
    if x ~= x or y ~= y or math.abs(x) > UIParent:GetWidth() or math.abs(y) > UIParent:GetHeight() then
        return false
    end
    if NS.InCombat() and entry.frame.IsProtected and entry.frame:IsProtected() then return false end
    local a = Anchor(entry)
    self:Save(entry.key, a.point, a.relPoint, x, y)
    self:Load(entry.key)
    return true
end

local function PanelButton(text, width, anchor, onClick)
    local button = CreateFrame("Button", nil, coordsPanel, "UIPanelButtonTemplate")
    button:SetSize(width, 22)
    button:SetPoint("LEFT", anchor, "RIGHT", 6, 0)
    button:SetText(text)
    NS.Widgets.FitText(button, width)
    button:SetScript("OnClick", onClick)
    return button
end

-- Case à cocher de l'ancrage (taille reprise, axe fixé) : `get(a)` lit l'état, `set(key, on)` l'écrit.
local function PanelCheck(text, anchor, get, set)
    local check = CreateFrame("CheckButton", nil, coordsPanel, "UICheckButtonTemplate")
    check:SetSize(22, 22)
    check:SetPoint("LEFT", anchor, "RIGHT", 10, 0)
    check.label = Media:CreateText(coordsPanel, "OVERLAY")
    check.label:SetPoint("LEFT", check, "RIGHT", 2, 0)
    check.label:SetText(text)
    check.get = get
    check:SetScript("OnClick", function(self)
        if Movers.selected then set(Movers.selected, self:GetChecked() and true or false) end
        Movers.RefreshCoords()
    end)
    return check
end

local function BuildCoordsPanel()
    coordsPanel = CreateFrame("Frame", "AeonUIMoverCoords", UIParent)
    coordsPanel:SetFrameStrata("FULLSCREEN_DIALOG")
    coordsPanel:SetSize(640, 62)
    coordsPanel:SetPoint("TOP", UIParent, "TOP", 0, -60)
    Media:CreateBackdrop(coordsPanel)
    coordsPanel.title = Media:CreateText(coordsPanel, "OVERLAY")
    coordsPanel.title:SetPoint("TOPLEFT", coordsPanel, "TOPLEFT", 8, -10)
    coordsPanel.title:SetWidth(120)
    coordsPanel.title:SetJustifyH("LEFT")
    local function apply() Movers:ApplyCoords(coordsPanel.x:GetText(), coordsPanel.y:GetText()) end
    coordsPanel.x = CoordsBox("X", coordsPanel.title, apply)
    coordsPanel.y = CoordsBox("Y", coordsPanel.x, apply)
    coordsPanel.center = PanelButton(L.MOVER_CENTER, 110, coordsPanel.y, function()
        if Movers.selected then Movers:CenterOnScreen(Movers.selected) end
    end)
    -- Seconde ligne : ancrage à un autre élément.
    coordsPanel.status = Media:CreateText(coordsPanel, "OVERLAY")
    coordsPanel.status:SetPoint("BOTTOMLEFT", coordsPanel, "BOTTOMLEFT", 8, 10)
    coordsPanel.status:SetWidth(170)
    coordsPanel.status:SetJustifyH("LEFT")
    coordsPanel.anchor = PanelButton(L.MOVER_ANCHOR_TO, 110, coordsPanel.status, function()
        local key = Movers.selected
        if not key then return end
        local a = NS.db.anchors[key]
        if a and a.target then
            Movers:Detach(key)
        else
            Movers.picking = Movers.picking ~= key and key or nil
        end
        Movers.RefreshCoords()
    end)
    coordsPanel.width = PanelCheck(L.MOVER_MATCH_WIDTH, coordsPanel.anchor,
        function(a) return a.matchWidth end, function(key, on) Movers:SetMatch(key, "width", on) end)
    coordsPanel.height = PanelCheck(L.MOVER_MATCH_HEIGHT, coordsPanel.width.label,
        function(a) return a.matchHeight end, function(key, on) Movers:SetMatch(key, "height", on) end)
    coordsPanel.edgeX = PanelCheck(L.MOVER_LOCK_X, coordsPanel.height.label,
        function(a) return a.edgeX ~= nil end, function(key, on) Movers:SetEdge(key, "x", on) end)
    coordsPanel.edgeY = PanelCheck(L.MOVER_LOCK_Y, coordsPanel.edgeX.label,
        function(a) return a.edgeY ~= nil end, function(key, on) Movers:SetEdge(key, "y", on) end)
    coordsPanel:Hide()
end

function Movers.RefreshCoords()
    if not coordsPanel then return end
    local entry = Movers.unlocked and Movers.selected and Movers.registry[Movers.selected]
    if not entry then coordsPanel:Hide() return end
    local a = Anchor(entry)
    coordsPanel.title:SetText(entry.label)
    -- Une décimale : réappliquer un axe inchangé ne le décale pas d'un pixel.
    coordsPanel.x:SetText(string.format("%.1f", a.x))
    coordsPanel.y:SetText(string.format("%.1f", a.y))
    local anchored = a.target ~= nil
    if Movers.picking == entry.key then
        coordsPanel.status:SetText(L.MOVER_PICK_TARGET)
    else
        coordsPanel.status:SetText(AnchoredText(entry) or L.MOVER_ANCHORED_SCREEN)
    end
    coordsPanel.anchor:SetText(anchored and L.MOVER_DETACH or L.MOVER_ANCHOR_TO)
    for _, check in ipairs({ coordsPanel.width, coordsPanel.height, coordsPanel.edgeX, coordsPanel.edgeY }) do
        check:SetChecked(anchored and check.get(a) and true or false)
        check:SetShown(anchored)
        check.label:SetShown(anchored)
    end
    coordsPanel:Show()
end

function Movers:GetCoordsPanel() return coordsPanel end

--- Lignes d'aimantation : écran (bords, centre) et autres calques visibles.
local function SnapLines(entry)
    local xLines = { 0, UIParent:GetWidth() / 2, UIParent:GetWidth() }
    local yLines = { 0, UIParent:GetHeight() / 2, UIParent:GetHeight() }
    for _, other in pairs(Movers.registry) do
        local o = other.overlay
        if other ~= entry and o and o:IsShown() and o:GetLeft() then
            local l, b, w, h = o:GetLeft(), o:GetBottom(), o:GetWidth(), o:GetHeight()
            xLines[#xLines + 1] = l; xLines[#xLines + 1] = l + w / 2; xLines[#xLines + 1] = l + w
            yLines[#yLines + 1] = b; yLines[#yLines + 1] = b + h / 2; yLines[#yLines + 1] = b + h
        end
    end
    return xLines, yLines
end

--- Fin de glisser : aimant, conversion en point d'ancrage, sauvegarde, repose du cadre.
function Movers:Drop(key)
    local entry = self.registry[key]
    local overlay = entry and entry.overlay
    if not overlay then return end
    local left, bottom = overlay:GetLeft(), overlay:GetBottom()
    local width, height = overlay:GetWidth(), overlay:GetHeight()
    if not left or not bottom then Attach(entry) return end
    if not (IsShiftKeyDown and IsShiftKeyDown()) then
        local xLines, yLines = SnapLines(entry)
        local dx, dy = Movers.SnapDelta(left, bottom, width, height, xLines, yLines, SNAP_THRESHOLD)
        left, bottom = left + dx, bottom + dy
    end
    -- Ancré : le glisser change le décalage par rapport à la cible, pas l'ancrage.
    local a = NS.db.anchors[key]
    local target = a and a.target and self.registry[a.target]
    local parent = target and Rect(target)
    if parent then
        local child = { left = left, bottom = bottom, width = width, height = height }
        local x, y = Movers.RelativeOffset(a.point, a.relPoint, child, parent)
        self:Save(key, a.point, a.relPoint, x, y)
        local saved = NS.db.anchors[key]
        saved.fallback = AbsoluteAnchor(child)
        if saved.edgeX then saved.edgeX = left end
        if saved.edgeY then saved.edgeY = bottom end
        self:Load(key)
        return
    end
    local screenWidth, screenHeight = UIParent:GetWidth(), UIParent:GetHeight()
    local point = Movers.PointFor(left + width / 2, bottom + height / 2, screenWidth, screenHeight)
    local x, y = Movers.OffsetFor(point, left, bottom, width, height, screenWidth, screenHeight)
    if a and a.target then
        -- Cible absente : c'est la position de secours qu'on déplace, l'ancrage attend son retour.
        a.fallback = { point = point, relPoint = point, x = NS.Pixel:Scale(x), y = NS.Pixel:Scale(y) }
    else
        self:Save(key, point, point, x, y)
    end
    self:Load(key)
end

local function OnKeyDown(overlay, key)
    local entry = overlay.entry
    local arrow = ARROWS[key]
    -- SetPropagateKeyboardInput est protégé en combat : le clavier des calques est coupé à
    -- l'entrée en combat (PLAYER_REGEN_DISABLED) et on ne l'appelle jamais dans cet état.
    if NS.InCombat() then return end
    if not arrow or Movers.selected ~= entry.key then
        overlay:SetPropagateKeyboardInput(true)
        return
    end
    overlay:SetPropagateKeyboardInput(false)
    local step = (IsShiftKeyDown and IsShiftKeyDown()) and 10 or 1
    Movers:Nudge(entry.key, arrow[1] * step, arrow[2] * step)
end

BuildOverlay = function(entry)
    local overlay = CreateFrame("Frame", nil, UIParent)
    overlay.entry = entry
    overlay:SetFrameStrata("DIALOG")
    overlay:EnableMouse(true)
    overlay:SetMovable(true)
    overlay:SetClampedToScreen(true)
    overlay:RegisterForDrag("LeftButton")
    overlay.bg = overlay:CreateTexture(nil, "BACKGROUND")
    overlay.bg:SetAllPoints()
    local r, g, b = Media:Accent()
    overlay.edges = Media:CreateBorder(overlay, { r = r, g = g, b = b, a = 1 })
    overlay.label = Media:CreateText(overlay, "OVERLAY", 0, "OUTLINE")
    overlay.label:SetPoint("CENTER", overlay, "CENTER", 0, 6)
    overlay.label:SetText(entry.label)
    overlay.coords = Media:CreateText(overlay, "OVERLAY", -2, "OUTLINE")
    overlay.coords:SetPoint("CENTER", overlay, "CENTER", 0, -8)
    overlay:SetScript("OnDragStart", function(self)
        if NS.InCombat() and entry.frame.IsProtected and entry.frame:IsProtected() then return end
        Movers:Select(entry.key)
        self.dragging = true
        self:StartMoving()
    end)
    overlay:SetScript("OnDragStop", function(self)
        if not self.dragging then return end   -- glisser refusé en combat : rien à sauver
        self.dragging = nil
        self:StopMovingOrSizing()
        Movers:Drop(entry.key)
    end)
    overlay:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" then return end
        -- Choix de la cible d'ancrage : ce clic désigne la cible, sans la sélectionner.
        local picking = Movers.picking
        if picking and picking ~= entry.key then
            Movers.picking = nil
            Movers:AttachTo(picking, entry.key)
            Movers:Select(picking)
            return
        end
        Movers:Select(entry.key)
    end)
    overlay:SetScript("OnMouseUp", function(_, button)
        if button ~= "RightButton" then return end
        if IsShiftKeyDown and IsShiftKeyDown() then
            Movers:Reset(entry.key)
        elseif entry.module then
            NS.OpenOptions(entry.module)
        end
    end)
    overlay:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(entry.label)
        GameTooltip:AddLine(CoordsText(entry), 1, 1, 1)
        local anchored = AnchoredText(entry)
        if anchored then GameTooltip:AddLine(anchored, 1, 1, 1) end
        GameTooltip:AddLine(L.MOVER_TOOLTIP_HINT, 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    overlay:SetScript("OnLeave", function() GameTooltip:Hide() end)
    overlay:SetScript("OnKeyDown", OnKeyDown)
    -- Molette : 1 px vertical ; Maj : horizontal ; Ctrl : 10 px.
    overlay:EnableMouseWheel(true)
    overlay:SetScript("OnMouseWheel", function(_, delta)
        if NS.InCombat() and entry.frame.IsProtected and entry.frame:IsProtected() then return end
        Movers:Select(entry.key)
        local step = delta * ((IsControlKeyDown and IsControlKeyDown()) and 10 or 1)
        if IsShiftKeyDown and IsShiftKeyDown() then Movers:Nudge(entry.key, step, 0)
        else Movers:Nudge(entry.key, 0, step) end
    end)
    overlay:EnableKeyboard(false)
    entry.overlay = overlay
    Movers.overlays[entry.key] = overlay
    PaintOverlay(entry, false)
    Attach(entry)
    return overlay
end

--------------------------------------------------------------------------------
-- Grille
--------------------------------------------------------------------------------

local grid

local function ShowGrid(size)
    if not grid then
        grid = CreateFrame("Frame", nil, UIParent)
        grid:SetAllPoints(UIParent)
        grid:SetFrameStrata("BACKGROUND")
        grid.lines = {}
    end
    -- Un pas infime (profil importé) ferait des milliards de tours de boucle : le jeu se fige.
    size = math.max(size, 8)
    local width, height = UIParent:GetWidth(), UIParent:GetHeight()
    local px = NS.Pixel:Scale(1)
    local r, g, b = Media:Accent()
    local used = 0
    local function line(vertical, offset, strong)
        used = used + 1
        if used > MAX_GRID_LINES then return end
        local tex = grid.lines[used]
        if not tex then
            tex = grid:CreateTexture(nil, "BACKGROUND")
            grid.lines[used] = tex
        end
        tex:ClearAllPoints()
        if vertical then
            tex:SetPoint("TOP", grid, "TOP", offset, 0)
            tex:SetPoint("BOTTOM", grid, "BOTTOM", offset, 0)
            tex:SetWidth(px)
        else
            tex:SetPoint("LEFT", grid, "LEFT", 0, offset)
            tex:SetPoint("RIGHT", grid, "RIGHT", 0, offset)
            tex:SetHeight(px)
        end
        NS.SetSolidColor(tex, r, g, b, strong and 0.6 or 0.25)
        tex:Show()
    end
    line(true, 0, true)
    line(false, 0, true)
    for offset = size, width / 2, size do line(true, offset); line(true, -offset) end
    for offset = size, height / 2, size do line(false, offset); line(false, -offset) end
    for i = used + 1, #grid.lines do grid.lines[i]:Hide() end
    grid:Show()
end

local function HideGrid()
    if grid then grid:Hide() end
end

--------------------------------------------------------------------------------
-- Déverrouillage
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Barre d'outils du mode déverrouillé
--------------------------------------------------------------------------------

local toolbar

--- Le calque suit le filtre de la barre d'outils (nil : tous).
function Movers:IsListed(entry)
    return self.filter == nil or entry.module == self.filter
end

--- Modules qui possèdent au moins un mover, triés par titre, précédés de « Tous ».
local function FilterChoices()
    local modules, seen = {}, {}
    for _, entry in pairs(Movers.registry) do
        local module = entry.module and NS.Modules:Get(entry.module)
        if module and not seen[module.name] then
            seen[module.name] = true
            modules[#modules + 1] = { name = module.title or module.name, value = module.name }
        end
    end
    table.sort(modules, function(a, b) return NS.Modules.SortKey(a.name) < NS.Modules.SortKey(b.name) end)
    table.insert(modules, 1, { name = L.MOVER_FILTER_ALL, value = false })
    return modules
end

local function BuildToolbar()
    toolbar = CreateFrame("Frame", "AeonUIMoverToolbar", UIParent)
    toolbar:SetFrameStrata("FULLSCREEN_DIALOG")
    toolbar:SetSize(860, 34)
    toolbar:SetPoint("TOP", UIParent, "TOP", 0, -16)
    Media:CreateBackdrop(toolbar)
    local title = Media:CreateText(toolbar, "OVERLAY")
    title:SetPoint("LEFT", toolbar, "LEFT", 10, 0)
    title:SetText(L.MOVER_TOOLBAR_TITLE)
    local grid = NS.Widgets.Dropdown(toolbar, 170, L.MOVER_GRID, {
            { name = L.GRID_NONE, value = 0 }, { name = "16 px", value = 16 }, { name = "32 px", value = 32 },
        },
        function() return NS.db.theme.grid end,
        function(value) NS.db.theme.grid = value; NS:Fire("THEME_CHANGED") end)
    grid:SetPoint("LEFT", toolbar, "LEFT", 150, 0)
    local filter = NS.Widgets.Dropdown(toolbar, 240, L.MOVER_FILTER, FilterChoices,
        function() return Movers.filter or false end,
        function(value)
            Movers.filter = value or nil
            Movers:SetUnlocked(true)
        end)
    filter:SetPoint("LEFT", grid, "RIGHT", 8, 0)
    local resetAll = CreateFrame("Button", nil, toolbar, "UIPanelButtonTemplate")
    resetAll:SetSize(140, 24)
    resetAll:SetPoint("LEFT", filter, "RIGHT", 8, 0)
    resetAll:SetText(L.MOVER_RESET_ALL)
    NS.Widgets.FitText(resetAll, 140)
    resetAll:SetScript("OnClick", function()
        StaticPopupDialogs.AEONUI_RESET_POSITIONS.text = L.MSG_RESET_POSITIONS_CONFIRM
        StaticPopup_Show("AEONUI_RESET_POSITIONS")
    end)
    local lock = CreateFrame("Button", nil, toolbar, "UIPanelButtonTemplate")
    lock:SetSize(120, 24)
    lock:SetPoint("LEFT", resetAll, "RIGHT", 8, 0)
    lock:SetText(L.MOVER_LOCK)
    NS.Widgets.FitText(lock, 120)
    lock:SetScript("OnClick", function() NS:SetUnlocked(false) end)
    toolbar.grid, toolbar.filter = grid, filter
    toolbar:Hide()
end

function Movers:GetToolbar() return toolbar end

function Movers:SetUnlocked(unlocked)
    self.unlocked = unlocked and true or false
    if not self.unlocked then self.filter = nil end
    self.picking = nil
    for _, entry in pairs(self.registry) do
        if self.unlocked and not entry.overlay then BuildOverlay(entry) end
        if entry.overlay then
            Attach(entry)
            entry.overlay:SetShown(self.unlocked and self:IsListed(entry))
            entry.overlay:EnableKeyboard(false)
            PaintOverlay(entry, false)
        end
    end
    self.selected = nil
    if self.unlocked and not coordsPanel then BuildCoordsPanel() end
    if self.unlocked and not toolbar and NS.Widgets then BuildToolbar() end
    if toolbar then
        toolbar:SetShown(self.unlocked)
        toolbar.grid.Paint()
        toolbar.filter.Paint()
    end
    Movers.RefreshCoords()
    local size = NS.db and NS.db.theme and NS.db.theme.grid or 0
    if self.unlocked and size > 0 then ShowGrid(size) else HideGrid() end
end

NS:On("THEME_CHANGED", function()
    if Movers.unlocked then Movers:SetUnlocked(true) end
end)

-- Entrée en combat : plus de clavier sur les calques (SetPropagateKeyboardInput protégé).
local combat = CreateFrame("Frame")
combat:RegisterEvent("PLAYER_REGEN_DISABLED")
combat:SetScript("OnEvent", function()
    if Movers.selected then Movers:Select(nil) end
end)

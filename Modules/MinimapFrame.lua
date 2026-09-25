-- Modules/MinimapFrame.lua
-- Minimap AeonUI : carte carrée à la taille voulue, bordure au thème, nom de zone et
-- coordonnées AeonUI, zoom à la molette, boutons d'addons regroupés sous la carte.
--
-- `Minimap` est reparentée sur notre support : laissée dans MinimapCluster, son rendu reste
-- découpé par le conteneur Blizzard et la carte ne s'affiche qu'après un ping (vérifié en jeu).
-- Reparentage différé d'une image et hors combat ; des hooks de SetParent et SetPoint reprennent
-- la main si Blizzard la replace. Le décor Blizzard (bordure, boussole, horloge, zoom) est caché ;
-- tout revient au /reload après désactivation.
local _, NS = ...
local L = NS.L
local Media = NS.Media

local MinimapFrame = NS.Modules:Register("minimap", {
    reloadOnDisable = true,   -- cadres Blizzard rendus au /reload seulement : les options le proposent
    titleKey = "MINIMAP_TITLE",
    descKey = "MINIMAP_DESC",
    yieldsTo = { "ElvUI", "SexyMap" },
    defaults = {
        enabled = false,
        size = 180,
        square = true,
        hideDecor = true,
        zoneText = true,
        coords = false,
        wheelZoom = true,
        buttonBar = "hover",      -- "hover" | "always" | "button" | "off"
        buttonSize = 24,
    },
})

local SQUARE_MASK = 130937   -- fileID du masque carré (Interface\\BUTTONS\\WHITE8X8)
local ROUND_MASK = 186178    -- fileID du masque rond Blizzard
local COORDS_INTERVAL = 0.5

-- Décor Blizzard caché (chemins résolus depuis _G, tout est optionnel selon le client).
local DECOR_HIDE = {
    "MinimapCluster.BorderTop", "MinimapCluster.Tracking.Background", "MinimapBackdrop",
    "MinimapCompassTexture", "MinimapBorder", "MinimapBorderTop", "MinimapNorthTag",
    "TimeManagerClockButton", "Minimap.ZoomIn", "Minimap.ZoomOut", "MinimapZoomIn", "MinimapZoomOut",
    "AddonCompartmentFrame", "ExpansionLandingPageMinimapButton", "MinimapToggleButton",
}
-- Boutons utiles réancrés aux coins de la carte : { chemin, point, x, y }.
local DECOR_PLACE = {
    { "MinimapCluster.Tracking", "TOPLEFT", 2, -2 }, { "MiniMapTracking", "TOPLEFT", 2, -2 },
    { "GameTimeFrame", "TOPRIGHT", -2, -2 },
    { "MinimapCluster.InstanceDifficulty", "TOPLEFT", 2, -28 }, { "MiniMapInstanceDifficulty", "TOPLEFT", 2, -28 },
    { "MinimapCluster.IndicatorFrame", "BOTTOMRIGHT", -2, 2 }, { "MiniMapMailFrame", "BOTTOMRIGHT", -2, 2 },
    { "QueueStatusButton", "BOTTOMLEFT", 2, 2 }, { "MiniMapBattlefieldFrame", "BOTTOMLEFT", 2, 2 },
    { "MiniMapLFGFrame", "BOTTOMLEFT", 2, 2 },
}
local PVP_COLORS = {
    sanctuary = { 0.41, 0.8, 0.94 }, arena = { 1, 0.1, 0.1 }, hostile = { 1, 0.1, 0.1 },
    friendly = { 0.1, 1, 0.1 }, contested = { 1, 0.7, 0 },
}

local active = false
local holder, buttonBar, buttonToggle
local decor = {}            -- objets Blizzard touchés (pour les rendre au disable)
local collected = {}        -- [bouton] = parent d'origine
local anchoring = false
local originalParent
local events = CreateFrame("Frame")
local hooked = false
local coordsTicker

local function Lookup(path)
    local value = _G
    for part in path:gmatch("[^%.]+") do
        value = value[part]
        if type(value) ~= "table" then return nil end
    end
    return value
end

local function S(n) return NS.Pixel:Scale(n) end

--------------------------------------------------------------------------------
-- Support, carte, décor
--------------------------------------------------------------------------------

local function AnchorMinimap()
    if anchoring or not holder then return end
    anchoring = true
    NS.ClearPointsRaw(Minimap)
    NS.SetPointRaw(Minimap, "CENTER", holder, "CENTER", 0, 0)
    anchoring = false
end

-- Le moteur ne redessine la carte (nouveau parent, taille, masque) qu'au changement de zoom.
-- Zoom décalé puis rendu l'image suivante : un aller-retour dans la même image est ignoré.
local redrawing = false
local function Redraw()
    if redrawing then return end
    redrawing = true
    local zoom = Minimap:GetZoom() or 0
    local levels = Minimap:GetZoomLevels() or 6
    Minimap:SetZoom(zoom < levels - 1 and zoom + 1 or zoom - 1)
    C_Timer.After(0, function()
        Minimap:SetZoom(zoom)
        redrawing = false
    end)
end

-- Hors combat seulement : SetParent d'un cadre Blizzard en combat souillerait l'interface.
local function ReparentMinimap()
    if not holder or Minimap:GetParent() == holder then return end
    if InCombatLockdown() then events:RegisterEvent("PLAYER_REGEN_ENABLED") return end
    originalParent = originalParent or Minimap:GetParent()
    Minimap:SetParent(holder)
    AnchorMinimap()
    Redraw()
end

local function Build()
    holder = CreateFrame("Frame", "AeonUI_Minimap", UIParent)
    holder:SetFrameStrata("LOW")
    -- Fond noir fixe : la carte est transparente hors terrain, la couleur de fond du thème
    -- transparaîtrait. Seule la bordure suit le thème.
    local bg = holder:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(holder)
    NS.SetSolidColor(bg, 0, 0, 0, 1)
    Media:CreateBorder(holder)
    holder.zone = Media:CreateText(holder, "OVERLAY", 0)
    holder.zone:SetPoint("BOTTOM", holder, "TOP", 0, 4)
    holder.zone:SetJustifyH("CENTER")
    holder.coords = Media:CreateText(holder, "OVERLAY", -2)
    holder.coords:SetPoint("TOP", holder, "BOTTOM", 0, -4)
    buttonBar = CreateFrame("Frame", "AeonUI_MinimapButtons", holder)
    buttonBar:EnableMouse(true)
    -- Mode "button" : un seul bouton sous la carte, un clic ouvre ou ferme la grille d'addons.
    buttonToggle = CreateFrame("Button", "AeonUI_MinimapButtonsToggle", holder)
    local toggleBg = buttonToggle:CreateTexture(nil, "BACKGROUND")
    toggleBg:SetAllPoints(buttonToggle)
    NS.SetSolidColor(toggleBg, 0, 0, 0, 0.8)
    Media:CreateBorder(buttonToggle)
    buttonToggle.text = Media:CreateText(buttonToggle, "OVERLAY", -2)
    buttonToggle.text:SetPoint("CENTER", buttonToggle, "CENTER", 0, 0)
    buttonToggle:SetScript("OnClick", function() buttonBar:SetShown(not buttonBar:IsShown()) end)
    if not hooked then
        hooked = true
        hooksecurefunc(Minimap, "SetPoint", function()
            if active and not anchoring then AnchorMinimap() end
        end)
        hooksecurefunc(Minimap, "SetParent", function()
            if active then C_Timer.After(0, function() if active then ReparentMinimap() end end) end
        end)
    end
end

local function ApplyDecor()
    local db = MinimapFrame.db
    for _, path in ipairs(DECOR_HIDE) do
        local object = Lookup(path)
        if object then
            decor[object] = true
            if db.hideDecor then NS.HideRegion(object) else NS.ShowRegion(object) end
        end
    end
    local zoneButton = Lookup("MinimapCluster.ZoneTextButton") or Lookup("MinimapZoneTextButton")
    if zoneButton then
        decor[zoneButton] = true
        if db.zoneText then NS.HideRegion(zoneButton) else NS.ShowRegion(zoneButton) end
    end
    if not db.hideDecor then return end
    for _, entry in ipairs(DECOR_PLACE) do
        local object = Lookup(entry[1])
        if object and object.ClearAllPoints then
            object:ClearAllPoints()
            object:SetPoint(entry[2], Minimap, entry[2], entry[3], entry[4])
        end
    end
end

local function OnMouseWheel(_, delta)
    if not active then return end
    local zoom = Minimap:GetZoom()
    if delta > 0 then Minimap:SetZoom(math.min(zoom + 1, Minimap:GetZoomLevels() - 1))
    else Minimap:SetZoom(math.max(zoom - 1, 0)) end
end

local function Layout()
    local db = MinimapFrame.db
    local size = S(db.size)
    holder:SetSize(size, size)
    Minimap:SetSize(size, size)
    if Minimap.SetMaskTexture then Minimap:SetMaskTexture(db.square and SQUARE_MASK or ROUND_MASK) end
    if Minimap.SetArchBlobRingScalar then Minimap:SetArchBlobRingScalar(db.square and 0 or 1) end
    if Minimap.SetQuestBlobRingScalar then Minimap:SetQuestBlobRingScalar(db.square and 0 or 1) end
    AnchorMinimap()
    ApplyDecor()
    C_Timer.After(0, function() if active then ReparentMinimap() end end)
    Redraw()
    Minimap:EnableMouseWheel(true)
    if db.wheelZoom then Minimap:SetScript("OnMouseWheel", OnMouseWheel)
    elseif Minimap:GetScript("OnMouseWheel") == OnMouseWheel then Minimap:SetScript("OnMouseWheel", nil) end
    if db.zoneText then holder.zone:Show() else holder.zone:Hide() end
    holder:Show()
end

--------------------------------------------------------------------------------
-- Zone et coordonnées
--------------------------------------------------------------------------------

function MinimapFrame.ZoneColor(pvpType)
    return unpack(PVP_COLORS[pvpType] or { 1, 0.82, 0 })
end

local function UpdateZone()
    if not holder or not MinimapFrame.db.zoneText then return end
    holder.zone:SetText(GetMinimapZoneText and GetMinimapZoneText() or "")
    local pvpType = GetZonePVPInfo and GetZonePVPInfo()
    holder.zone:SetTextColor(MinimapFrame.ZoneColor(pvpType))
end

function MinimapFrame.PlayerCoords()
    if not C_Map or not C_Map.GetBestMapForUnit then return nil end
    local ok, x, y = pcall(function()
        local mapID = C_Map.GetBestMapForUnit("player")
        if not mapID then return nil end
        local position = C_Map.GetPlayerMapPosition(mapID, "player")
        if not position then return nil end
        return position:GetXY()
    end)
    if ok and x and y and x > 0 and y > 0 then return x * 100, y * 100 end
    return nil
end

local function UpdateCoords()
    if not holder then return end
    local x, y = MinimapFrame.PlayerCoords()
    if x then holder.coords:SetText(string.format("%.1f, %.1f", x, y)) else holder.coords:SetText("") end
end

local function ApplyCoords()
    if coordsTicker then coordsTicker:Cancel() coordsTicker = nil end
    if MinimapFrame.db.coords then
        holder.coords:Show()
        UpdateCoords()
        coordsTicker = C_Timer.NewTicker(COORDS_INTERVAL, UpdateCoords)
    else
        holder.coords:Hide()
    end
end

--------------------------------------------------------------------------------
-- Boutons d'addons
--------------------------------------------------------------------------------

-- Boutons Blizzard enfants de la carte selon le client : jamais déplacés.
local BLIZZARD_PREFIXES = { "^Mini[mM]ap", "^AeonUI", "^Queue", "^GameTime", "^TimeManager", "^Expansion",
                            "^AddonCompartment", "^Garrison", "^Craft", "^Mail" }

function MinimapFrame.IsAddonButton(frame)
    local name = frame.GetName and frame:GetName()
    if not name then return false end
    if name:find("^LibDBIcon") then return true end
    for _, prefix in ipairs(BLIZZARD_PREFIXES) do
        if name:find(prefix) then return false end
    end
    return frame:GetObjectType() == "Button"
end

local function LayoutButtons()
    local db = MinimapFrame.db
    local size, spacing = S(db.buttonSize), S(2)
    local list = {}
    for button in pairs(collected) do list[#list + 1] = button end
    table.sort(list, function(a, b) return a:GetName() < b:GetName() end)
    -- Mode "button" : grille à la largeur de la carte ; sinon une seule rangée.
    local columns = #list
    if db.buttonBar == "button" then
        columns = math.max(1, math.floor((holder:GetWidth() + spacing) / (size + spacing)))
    end
    columns = math.max(1, math.min(columns, #list))
    for i, button in ipairs(list) do
        local column, row = (i - 1) % columns, math.floor((i - 1) / columns)
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", buttonBar, "TOPLEFT", column * (size + spacing), -row * (size + spacing))
        button:SetSize(size, size)
    end
    local rows = math.ceil(#list / columns)
    buttonBar:SetSize(math.max(1, columns * (size + spacing) - spacing), math.max(1, rows * (size + spacing) - spacing))
    buttonToggle.text:SetText(string.format(L.MINIMAP_ADDONS_TOGGLE, #list))
end

local function Collect()
    if MinimapFrame.db.buttonBar == "off" then return end
    for _, child in ipairs({ Minimap:GetChildren() }) do
        if not collected[child] and MinimapFrame.IsAddonButton(child) then
            collected[child] = { parent = child:GetParent(), point = { child:GetPoint(1) },
                                 width = child:GetWidth(), height = child:GetHeight() }
            child:SetParent(buttonBar)
        end
    end
    LayoutButtons()
end

local function Release()
    for button, saved in pairs(collected) do
        button:SetParent(saved.parent)
        button:SetSize(saved.width, saved.height)
        if saved.point[1] then
            button:ClearAllPoints()
            button:SetPoint(unpack(saved.point))
        end
        collected[button] = nil
    end
end

local function SetBarShown(shown)
    buttonBar:SetAlpha(shown and 1 or 0)
end

local function ApplyButtonBar()
    local mode = MinimapFrame.db.buttonBar
    if mode == "off" then Release() buttonBar:Hide() buttonToggle:Hide() return end
    buttonBar:ClearAllPoints()
    if mode == "button" then
        buttonToggle:ClearAllPoints()
        buttonToggle:SetPoint("TOP", MinimapFrame.db.coords and holder.coords or holder, "BOTTOM", 0, -2)
        buttonToggle:SetSize(holder:GetWidth(), S(16))
        buttonToggle:Show()
        buttonBar:SetPoint("TOP", buttonToggle, "BOTTOM", 0, -2)
        buttonBar:Hide()
    else
        buttonToggle:Hide()
        buttonBar:SetPoint("TOP", holder, "BOTTOM", 0, -2)
        buttonBar:Show()
    end
    Collect()
    SetBarShown(mode ~= "hover")
    if not buttonBar.hooked then
        buttonBar.hooked = true
        local function enter() if active and MinimapFrame.db.buttonBar == "hover" then SetBarShown(true) end end
        local function leave() if active and MinimapFrame.db.buttonBar == "hover" then SetBarShown(false) end end
        Minimap:HookScript("OnEnter", enter)
        Minimap:HookScript("OnLeave", leave)
        buttonBar:SetScript("OnEnter", enter)
        buttonBar:SetScript("OnLeave", leave)
    end
end

--------------------------------------------------------------------------------
-- Cycle de vie
--------------------------------------------------------------------------------

events:SetScript("OnEvent", function(_, event)
    if not active then return end
    UpdateZone()
    if event == "PLAYER_REGEN_ENABLED" then
        events:UnregisterEvent("PLAYER_REGEN_ENABLED")
        ReparentMinimap()
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then
        Redraw()
        Collect()
        C_Timer.After(2, function() if active then Collect() end end)   -- LibDBIcon crée ses boutons tard
    end
end)

function MinimapFrame:Apply()
    if not holder then Build() end
    NS.Movers:Register("minimap", holder, L.MOVER_MINIMAP, "TOPRIGHT", -20, -50)
    NS.Movers:Load("minimap")
    Layout()
    UpdateZone()
    ApplyCoords()
    ApplyButtonBar()
end

function MinimapFrame:OnEnable()
    if not _G.Minimap then return end
    active = true
    self:Apply()
    for _, event in ipairs({ "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" }) do
        NS.RegisterEventSafe(events, event)
    end
end

function MinimapFrame:OnDisable()
    if not active then return end
    active = false
    events:UnregisterAllEvents()
    if coordsTicker then coordsTicker:Cancel() coordsTicker = nil end
    Release()
    if originalParent and not InCombatLockdown() then Minimap:SetParent(originalParent) end
    for object in pairs(decor) do NS.ShowRegion(object) end
    if Minimap:GetScript("OnMouseWheel") == OnMouseWheel then Minimap:SetScript("OnMouseWheel", nil) end
    if Minimap.SetMaskTexture then Minimap:SetMaskTexture(ROUND_MASK) end
    holder:Hide()
    NS.Movers:Unregister("minimap")
    NS.Print(L.MSG_MINIMAP_DISABLED_RELOAD)
end

function MinimapFrame:OnRefresh()
    if active then self:Apply() end
end

NS:On("PIXEL_CHANGED", function() if active then MinimapFrame:Apply() end end)

--------------------------------------------------------------------------------
-- Options
--------------------------------------------------------------------------------

function MinimapFrame:BuildOptions(o)
    o.layout:Note(L.NOTE_MINIMAP_RELOAD, 20)
    o:Slider("size", L.OPT_MINIMAP_SIZE, 100, 400, 2)
    o:Check("square", L.OPT_MINIMAP_SQUARE)
    o:Check("hideDecor", L.OPT_MINIMAP_HIDE_DECOR)
    o:Check("zoneText", L.OPT_MINIMAP_ZONE)
    o:Check("coords", L.OPT_MINIMAP_COORDS)
    o:Check("wheelZoom", L.OPT_MINIMAP_WHEEL)
    o:Dropdown("buttonBar", L.OPT_MINIMAP_BUTTONS, {
        { name = L.MINIMAP_BUTTONS_HOVER, value = "hover" },
        { name = L.MINIMAP_BUTTONS_ALWAYS, value = "always" },
        { name = L.MINIMAP_BUTTONS_BUTTON, value = "button" },
        { name = L.MINIMAP_BUTTONS_OFF, value = "off" },
    })
    o:Slider("buttonSize", L.OPT_MINIMAP_BUTTON_SIZE, 16, 40, 1)
    o.layout:Button(L.OPT_UF_UNLOCK, function() NS:SetUnlocked(not NS.unlocked) end, 20)
end

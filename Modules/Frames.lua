-- Modules/Frames.lua
-- Retouches des cadres d'unité Blizzard (joueur, cible, focus, groupe, raid) :
--   * mode sombre : l'habillage des cadres (bordures, fonds) assombri ;
--   * barres de vie à la couleur de classe (joueurs) ;
--   * noms à la couleur de classe sur les cadres de raid ;
--   * indicateur « en combat » à côté du cadre de la cible.
-- On ne touche qu'à des couleurs et à nos propres textures : jamais à la position, la
-- taille ou la visibilité des cadres sécurisés. Tout est mémorisé et rendu au disable.
-- Les couleurs de barre acceptent des valeurs secrètes, mais on ne compare rien : une classe
-- secrète laisse la couleur Blizzard.
local _, NS = ...
local L = NS.L

local DARK = 0.3

local Frames = NS.Modules:Register("frames", {
    titleKey = "FRAMES_TITLE",
    descKey = "FRAMES_DESC",
    yieldsTo = { "ElvUI" },   -- ElvUI remplace ces cadres : le module cède sans toucher au réglage
    -- L'icône de combat est une frame enfant de TargetFrame (protégée) : sa création, et donc
    -- l'activation du module, attendent la fin du combat.
    secure = true,
    defaults = {
        enabled = false,
        darkMode = true,
        classHealth = true,
        classNamesRaid = true,
        targetCombat = true,
    },
})

local active = false
local darkened = {}   -- [texture] = { r, g, b, a } d'origine

--------------------------------------------------------------------------------
-- Cadres et barres de vie
--------------------------------------------------------------------------------

local UNIT_FRAMES = {
    { frame = "PlayerFrame", unit = "player" },
    { frame = "TargetFrame", unit = "target" },
    { frame = "FocusFrame", unit = "focus" },
}

local function Walk(node, ...)
    for i = 1, select("#", ...) do
        if not node then return nil end
        node = node[(select(i, ...))]
    end
    return node
end

--- Barre de vie d'un cadre : chemins du moteur 12.x (le focus réutilise le modèle de la
-- cible), puis anciens noms.
function Frames.HealthBar(frameName)
    local frame = _G[frameName]
    if not frame then return nil end
    local candidates = {
        Walk(frame, frameName .. "Content", frameName .. "ContentMain", "HealthBarsContainer", "HealthBar"),
        Walk(frame, "TargetFrameContent", "TargetFrameContentMain", "HealthBarsContainer", "HealthBar"),
        frame.healthbar, frame.HealthBar, _G[frameName .. "HealthBar"],
    }
    for i = 1, 5 do
        local bar = candidates[i]
        if bar and bar.SetStatusBarColor then return bar end
    end
    return nil
end

local function ClassColorForUnit(unit)
    if not UnitExists(unit) then return nil end
    local isPlayer = UnitIsPlayer(unit)
    if NS.IsSecret(isPlayer) or not isPlayer then return nil end
    local _, classFile = UnitClass(unit)
    if NS.IsSecret(classFile) or not classFile then return nil end
    return NS.ClassColor(classFile)
end

function Frames:ColorHealth(bar, unit)
    if not bar then return end
    local r, g, b
    if active and self.db.classHealth then r, g, b = ClassColorForUnit(unit) end
    if r then
        if bar.SetStatusBarDesaturated then bar:SetStatusBarDesaturated(true) end
        bar:SetStatusBarColor(r, g, b)
        bar.aeonUIColored = true
    elseif bar.aeonUIColored then
        -- Rendre la couleur Blizzard : vert désaturé -> vert d'origine.
        if bar.SetStatusBarDesaturated then bar:SetStatusBarDesaturated(false) end
        bar:SetStatusBarColor(0, 1, 0)
        bar.aeonUIColored = nil
    end
end

function Frames:ColorAll()
    for _, entry in ipairs(UNIT_FRAMES) do
        self:ColorHealth(Frames.HealthBar(entry.frame), entry.unit)
    end
end

--------------------------------------------------------------------------------
-- Mode sombre
--------------------------------------------------------------------------------
-- On assombrit les textures « d'habillage » : toutes sauf celles des barres (StatusBar),
-- du portrait et des icônes. Les couleurs d'origine sont gardées pour les rendre.

local function IsArtTexture(region)
    if not region.GetObjectType or region:GetObjectType() ~= "Texture" then return false end
    local parent = region:GetParent()
    if parent and parent.GetObjectType and parent:GetObjectType() == "StatusBar" then return false end
    local name = region.GetName and region:GetName() or ""
    if name:find("Portrait") or name:find("Icon") then return false end
    return true
end

local function Darken(frame, depth)
    if not frame or depth > 4 then return end
    for _, region in ipairs({ frame:GetRegions() }) do
        if IsArtTexture(region) and not darkened[region] then
            darkened[region] = { region:GetVertexColor() }
            region:SetVertexColor(DARK, DARK, DARK)
        end
    end
    -- Ni les barres, ni les boutons (icônes d'aura, menus), ni les cooldowns.
    local skip = { StatusBar = true, Button = true, CheckButton = true, Cooldown = true }
    for _, child in ipairs({ frame:GetChildren() }) do
        if child.GetObjectType and not skip[child:GetObjectType()] then Darken(child, depth + 1) end
    end
end

local function RestoreDark()
    for texture, color in pairs(darkened) do
        texture:SetVertexColor(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
    end
    darkened = {}
end

function Frames:ApplyDark()
    RestoreDark()
    if not (active and self.db.darkMode) then return end
    for _, entry in ipairs(UNIT_FRAMES) do Darken(_G[entry.frame], 0) end
end

--------------------------------------------------------------------------------
-- Noms de raid à la couleur de classe
--------------------------------------------------------------------------------

-- Appelé par le hook même module coupé : c'est là que la couleur d'origine est rendue.
local function ColorRaidName(frame)
    if not frame or not frame.name then return end
    local name = frame.name
    local r, g, b
    if active and Frames.db.classNamesRaid then
        local unit = frame.unit
        if not NS.IsSecret(unit) and unit and not unit:find("nameplate") then
            r, g, b = ClassColorForUnit(unit)
        end
    end
    if r then
        if not name.aeonUIOriginal then name.aeonUIOriginal = { name:GetTextColor() } end
        name:SetTextColor(r, g, b)
        name.aeonUIColored = true
    elseif name.aeonUIColored then
        name:SetTextColor(unpack(name.aeonUIOriginal))
        name.aeonUIColored = nil
    end
end

--------------------------------------------------------------------------------
-- Indicateur de combat de la cible
--------------------------------------------------------------------------------

local combatIcon

local function BuildCombatIcon()
    local target = _G.TargetFrame
    if not target then return end
    combatIcon = CreateFrame("Frame", "AeonUITargetCombat", target)
    combatIcon:SetSize(22, 22)
    combatIcon:SetPoint("LEFT", target, "RIGHT", -8, 8)
    combatIcon.texture = combatIcon:CreateTexture(nil, "OVERLAY")
    combatIcon.texture:SetAllPoints()
    combatIcon.texture:SetTexture("Interface\\CharacterFrame\\UI-StateIcon")
    combatIcon.texture:SetTexCoord(0.5, 1, 0, 0.5)   -- les épées croisées
    combatIcon:Hide()
end

function Frames:UpdateTargetCombat()
    if not combatIcon then return end
    local show = false
    if active and self.db.targetCombat and UnitExists("target") then
        local inCombat = UnitAffectingCombat("target")
        show = not NS.IsSecret(inCombat) and inCombat and true or false
    end
    combatIcon:SetShown(show)
end

--------------------------------------------------------------------------------
-- Cycle de vie
--------------------------------------------------------------------------------

local hooked = false
local function Hook()
    if hooked then return end
    -- Les hooks tournent aussi module coupé : ColorHealth/ColorRaidName rendent alors l'origine
    -- (Blizzard ne repeint pas les barres de groupe, leur couleur vient du XML).
    if _G.CompactUnitFrame_UpdateName then
        hooksecurefunc("CompactUnitFrame_UpdateName", ColorRaidName)
        hooked = true
    end
    if _G.UnitFrameHealthBar_Update then
        hooksecurefunc("UnitFrameHealthBar_Update", function(bar, unit)
            if unit then Frames:ColorHealth(bar, unit) end
        end)
        hooked = true
    end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, unit)
    if event == "UNIT_FLAGS" and unit ~= "target" then return end
    Frames:ColorAll()
    Frames:UpdateTargetCombat()
end)

function Frames:OnEnable()
    active = true
    Hook()
    if not combatIcon then BuildCombatIcon() end
    for _, event in ipairs({ "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "PLAYER_ENTERING_WORLD",
                             "UNIT_FLAGS", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
        NS.RegisterEventSafe(events, event)
    end
    self:ApplyDark()
    self:ColorAll()
    self:UpdateTargetCombat()
end

function Frames:OnDisable()
    active = false
    events:UnregisterAllEvents()
    self:ApplyDark()      -- active = false : tout est rendu
    self:ColorAll()
    self:UpdateTargetCombat()
end

function Frames:OnRefresh()
    self:ApplyDark()
    self:ColorAll()
    self:UpdateTargetCombat()
end

function Frames:BuildOptions(o)
    local unitframes = NS.db.modules.unitframes
    if unitframes and unitframes.enabled then o.layout:Note(L.FRAMES_NOTE_UNITFRAMES, 20) end
    o:Check("darkMode", L.OPT_FRAMES_DARK)
    o:Check("classHealth", L.OPT_FRAMES_CLASS_HEALTH)
    o:Check("classNamesRaid", L.OPT_FRAMES_CLASS_NAMES)
    o:Check("targetCombat", L.OPT_FRAMES_TARGET_COMBAT)
end

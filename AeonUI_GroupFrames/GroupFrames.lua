-- AeonUI_GroupFrames/GroupFrames.lua
-- Cadres de groupe et de raid AeonUI : en-têtes SecureGroupHeaderTemplate (groupe, raid, tanks
-- et assistants principaux) dont chaque bouton (SecureUnitButtonTemplate : clic gauche cible, clic
-- droit menu) reçoit les éléments de NS.UnitFrameElements plus : rôle, chef, menace, dispel, portée,
-- icône d'état (appel, invocation, résurrection), et des sorts suivis par coin (Renouveau,
-- Récupération…). En option : cadres extra (tanks par rôle, ou liste de noms) et cadres des boss
-- alliés (boss1 à boss5 assistables, rencontres d'escorte ou de soin).
--
-- L'en-tête crée et ordonne ses boutons lui-même, hors combat, d'après ses attributs ; un hook
-- de SecureGroupHeader_Update habille chaque bouton neuf (ce moteur n'a pas de loadstring :
-- aucun snippet restreint, donc pas d'initialConfigFunction), une fois par bouton. Les événements d'unité sont reçus
-- par un seul écouteur et routés par jeton (byUnit) : le jeton d'un bouton change avec le tri, et
-- une unité peut avoir deux boutons (raid et tanks principaux).
local NS = AeonUI
local L = NS.L
local Elements = NS.UnitFrameElements
local Movers = NS.Movers

local GroupFrames = NS.Modules:Register("groupframes", {
    reloadOnDisable = true,   -- cadres Blizzard rendus au /reload seulement : les options le proposent
    titleKey = "GROUPFRAMES_TITLE",
    descKey = "GROUPFRAMES_DESC",
    secure = true,
    defaults = {
        enabled = false,
        width = 120, height = 56,       -- groupe, cadres extra et boss alliés
        raidWidth = 96, raidHeight = 44,   -- raid, tanks et assistants principaux
        powerHeight = 4, spacing = 3,
        powerShowTank = true, powerShowHealer = true, powerShowDamager = false,   -- rôle inconnu : montrée
        showPlayer = true, showSolo = false,
        horizontal = false,             -- groupe : colonne (false) ou ligne (true)
        reverse = false,                -- groupe : croissance vers le haut (colonne) ou la gauche (ligne)
        partySortRole = true,           -- groupe : tanks, soigneurs puis dégâts
        raidUnitsPerColumn = 5, raidColumns = 8, raidSortBy = "ROLE",   -- "GROUP" | "CLASS" | "ROLE" | "NAME"
        raidUnitGrowth = "DOWN", raidGroupGrowth = "RIGHT",   -- membres, puis colonnes : GROWTH
        raidGroups = 8,                 -- raid : groupes 1 à N affichés
        raidThreshold = 5,              -- cadres de raid au-delà de 5, 10 ou 40 membres (en dessous : disposition du groupe)
        nameLength = 12,                -- caractères du nom (0 = entier)
        namePosition = "TOPLEFT",       -- "TOPLEFT" | "CENTER"
        roleIcons = true, dispel = true, aggro = true,
        roleIconStyle = "portrait",     -- "portrait" | "tiny" | "circle" (atlas, repli sur portrait)
        roleIconSize = 13, roleIconPosition = "BOTTOMLEFT",
        roleShowTank = true, roleShowHealer = true, roleShowDamager = false, roleHideInCombat = false,
        leaderIcon = false,             -- couronne du chef, au milieu du bord haut
        stateText = true,               -- mort, fantôme, hors ligne : fond teinté et texte au centre
        dispelMode = "mine",            -- "mine" : ce que le joueur dissipe ; "all" : tout débuff typé
        dispelFill = true,              -- voile de la couleur du type sur la vie, en plus de la bordure
        dispelGlow = false,             -- lueur de la couleur du type, en plus de la bordure
        aggroStyle = "glow",            -- "border" | "glow" : menace en bordure ou en lueur (liseré épais)
        statusIcons = true,             -- appel, invocation, résurrection au centre
        readyIcons = true, summonIcons = true, rezIcons = true, statusIconSize = 16,
        healPrediction = true,          -- soins entrants et absorptions
        mainTanks = false, mainAssists = false,   -- raid : cadres des tanks et assistants principaux
        range = true, rangeAlpha = 0.4,
        healthText = "none", classColor = true, healthGradient = false, power = true,
        vertical = false,               -- barre de vie remplie de bas en haut
        auras = true, auraSize = 18, auraMax = 3,
        auraPosition = "INSIDE",        -- "INSIDE" (bas droite de la vie) | "ABOVE" | "BELOW"
        auraBuffs = false,              -- buffs après les débuffs
        castbar = false, castbarHeight = 4,   -- incantation du membre, au bas de la vie
        auraFilter = "all",             -- débuffs montrés : NS.AURA_FILTERS
        portrait = false,               -- portrait 2D à gauche, dans le cadre
        targetHighlight = true,         -- bordure d'accent sur la cible (après menace et dispel)
        mouseoverHighlight = true,      -- voile clair au survol
        -- Sorts suivis : identifiants par coin (tous les rangs, lus par nom), icône et recharge.
        indicators = { TOPLEFT = "", TOPRIGHT = "", BOTTOMLEFT = "", BOTTOMRIGHT = "" },
        indicatorSize = 10, indicatorMine = true,   -- mine : seulement les auras posées par le joueur
        extraFrames = false, extraNames = "",       -- noms séparés par des virgules ; vide = tanks du groupe
        friendlyBoss = false,
        healerMana = "none",            -- "none" | "party" | "raid" | "both" : mana des soigneurs en texte
        hideBlizzard = true,
    },
})

GroupFrames.headers = {}
local byUnit = {}               -- [jeton] = { [bouton] = true }
GroupFrames.byUnit = byUnit
local readyCheck = false        -- appel en cours ou résultat encore affiché
local readyFinished = false     -- appel fini : état mémorisé, « en attente » devient « pas prêt »
local readyToken = 0
local inCombat = false          -- suivi par PLAYER_REGEN_* : le verrouillage n'est pas encore posé pendant DISABLED

--- Appelle fn(bouton) pour chaque bouton de l'unité, ou de toutes si unit est nil.
local function ForEach(unit, fn)
    if unit then
        for button in pairs(byUnit[unit] or {}) do fn(button) end
        return
    end
    for _, set in pairs(byUnit) do
        for button in pairs(set) do fn(button) end
    end
end

local active = false
local rangeTicker

local HEADER_KEYS = { "party", "raid", "tank", "assist", "extra" }
-- Tanks et assistants principaux : filtre d'en-tête, option, visible en raid seulement. Extra :
-- rôle TANK (ou liste de noms), en groupe comme en raid.
local ROLE_HEADERS = { tank = { filter = "MAINTANK", option = "mainTanks" },
                       assist = { filter = "MAINASSIST", option = "mainAssists" },
                       extra = { filter = "TANK", option = "extraFrames" } }
GroupFrames.ROLE_HEADERS = ROLE_HEADERS

-- Chemins de fichiers, pas les globales READY_CHECK_*_TEXTURE (des noms d'atlas sur les clients récents).
local READY_TEXTURES = {
    ready = "Interface\\RaidFrame\\ReadyCheck-Ready",
    notready = "Interface\\RaidFrame\\ReadyCheck-NotReady",
    waiting = "Interface\\RaidFrame\\ReadyCheck-Waiting",
}
local REZ_TEXTURE = "Interface\\RaidFrame\\Raid-Icon-Rez"
-- Enum.SummonStatus : 1 en attente, 2 accepté, 3 refusé.
local SUMMON_ATLAS = { [1] = "Raid-Icon-SummonPending", [2] = "Raid-Icon-SummonAccepted", [3] = "Raid-Icon-SummonDeclined" }
local THREAT_COLORS = Elements.THREAT_COLORS   -- 2 agro instable, 3 agro ferme
local READY_LINGER = 6          -- secondes d'affichage du résultat de l'appel

local ROLE_ICON = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES"
local ROLE_ATLAS = {
    tiny = { TANK = "roleicon-tiny-tank", HEALER = "roleicon-tiny-healer", DAMAGER = "roleicon-tiny-dps" },
    circle = { TANK = "UI-LFG-RoleIcon-Tank", HEALER = "UI-LFG-RoleIcon-Healer", DAMAGER = "UI-LFG-RoleIcon-DPS" },
}
local ROLE_SHOWN = { TANK = "roleShowTank", HEALER = "roleShowHealer", DAMAGER = "roleShowDamager" }
GroupFrames.ROLE_STYLES = { "portrait", "tiny", "circle" }
local REZ_OFFER = 60            -- secondes pendant lesquelles une résurrection reste à accepter
local ROLE_COORDS = {
    TANK = { 0, 19 / 64, 22 / 64, 41 / 64 },
    HEALER = { 20 / 64, 39 / 64, 1 / 64, 20 / 64 },
    DAMAGER = { 20 / 64, 39 / 64, 22 / 64, 41 / 64 },
}
local LEADER_ICON = "Interface\\GroupFrame\\UI-Group-LeaderIcon"

GroupFrames.DISPEL_BY_CLASS = NS.DISPEL_BY_CLASS   -- table partagée (Core/Compat.lua)
local ANY_DISPEL = { Magic = true, Curse = true, Poison = true, Disease = true }

-- Direction -> point d'ancrage et signe du décalage (x, y).
local GROWTH = { DOWN = { "TOP", 0, -1 }, UP = { "BOTTOM", 0, 1 }, RIGHT = { "LEFT", 1, 0 }, LEFT = { "RIGHT", -1, 0 } }
GroupFrames.GROWTH_ORDER = { "DOWN", "UP", "RIGHT", "LEFT" }
local VERTICAL = { DOWN = true, UP = true }

local BLIZZARD = { "PartyFrame", "CompactPartyFrame", "CompactRaidFrameContainer" }

local CORNERS = { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }
GroupFrames.CORNERS = CORNERS
-- Préréglage de classe (Classic : rangs 1, reconnus par nom) : soins sur la durée et bouclier.
local INDICATOR_PRESETS = {
    PRIEST = { BOTTOMRIGHT = "139", BOTTOMLEFT = "17" },      -- Rénovation, Mot de pouvoir : Bouclier
    DRUID = { BOTTOMRIGHT = "774", BOTTOMLEFT = "8936" },     -- Récupération, Rétablissement
}
GroupFrames.INDICATOR_PRESETS = INDICATOR_PRESETS
local BOSS_COUNT = 5

local function Known(value)
    if NS.IsSecret(value) or value == nil then return nil end
    return value
end

--------------------------------------------------------------------------------
-- Boutons
--------------------------------------------------------------------------------

local RAID_SIZED = { raid = true, tank = true, assist = true }

--- Largeur et hauteur des boutons de l'en-tête `key` : raid (tanks, assistants) ou groupe.
function GroupFrames.Size(key)
    local db = GroupFrames.db
    if RAID_SIZED[key] then return db.raidWidth, db.raidHeight end
    return db.width, db.height
end

local function Config(key)
    local db = GroupFrames.db
    local width, height = GroupFrames.Size(key)
    return {
        width = width, height = height, power = db.power, powerHeight = db.powerHeight,
        castbar = db.castbar, castbarHeight = db.castbarHeight,
        auras = db.auras, auraSize = db.auraSize, auraFilter = db.auraFilter, auraMax = db.auraMax,
        aurasAbove = db.auraPosition == "ABOVE", aurasInside = db.auraPosition == "INSIDE",
        debuffsOnly = not db.auraBuffs,
        vertical = db.vertical, name = true, level = false, combo = false,
        portrait = db.portrait, portraitInside = true,
        nameLength = (tonumber(db.nameLength) or 0) > 0 and db.nameLength or nil,
    }
end

local function PlayerDispels()
    local _, classFile = UnitClass("player")
    classFile = Known(classFile)
    return classFile and GroupFrames.DISPEL_BY_CLASS[classFile] or nil
end

--- Type de débuff dissipable par le joueur (any : de tout type dissipable) porté par l'unité, ou nil.
function GroupFrames.DispellableType(unit, any)
    local dispels = any and ANY_DISPEL or PlayerDispels()
    if not dispels then return nil end
    for i = 1, 40 do
        local icon, _, _, _, dispelName = NS.GetDebuff(unit, i)
        if not NS.IsSecret(icon) and icon == nil then return nil end
        dispelName = Known(dispelName)
        if dispelName and dispels[dispelName] then return dispelName end
    end
    return nil
end

local function PaintBorder(button, r, g, b)
    if not button.border then return end
    for _, edge in pairs(button.border) do NS.SetSolidColor(edge, r, g, b, 1) end
end

local Threat = Elements.ThreatStatus

function GroupFrames:UpdateBorder(button)
    local unit = button.unit
    if not unit then return end
    local db = self.db
    -- Avec le moteur, la couleur de dissipation est posée par son emplacement, par-dessus la bordure.
    local kind = db.dispel and not button.auraSlots and GroupFrames.DispellableType(unit, db.dispelMode == "all")
    local dispelColor = kind and _G.DebuffTypeColor and DebuffTypeColor[kind]
    NS.Glow.Set(button, db.dispelGlow and dispelColor and true, "pixel", dispelColor)
    if button.dispelTint then
        if db.dispelFill and dispelColor then
            NS.SetSolidColor(button.dispelTint, dispelColor.r, dispelColor.g, dispelColor.b, 0.35)
            button.dispelTint:Show()
        else
            button.dispelTint:Hide()
        end
    end
    local threat = db.aggro and Threat(unit)
    local glow = db.aggroStyle == "glow"
    if button.glow then
        if threat and glow then
            local c = THREAT_COLORS[threat]
            NS.SetSolidColor(button.glow, c[1], c[2], c[3], 0.6)
            button.glow:Show()
        else
            button.glow:Hide()
        end
    end
    if threat and not glow then
        local c = THREAT_COLORS[threat]
        PaintBorder(button, c[1], c[2], c[3])
        return
    end
    if dispelColor then PaintBorder(button, dispelColor.r, dispelColor.g, dispelColor.b) return end
    if db.targetHighlight and NS.IsTarget(unit) then   -- nil si secret : bordure du thème
        PaintBorder(button, NS.Media:Accent())
        return
    end
    local c = NS.db.theme.border
    PaintBorder(button, c.r, c.g, c.b)
end

--- Rôle assigné, ou TANK pour un tank principal ; nil si inconnu ou secret.
local function UnitRole(unit)
    local role = _G.UnitGroupRolesAssigned and Known(UnitGroupRolesAssigned(unit)) or nil
    if (role == nil or role == "NONE") and _G.GetPartyAssignment then
        local ok, mainTank = pcall(GetPartyAssignment, "MAINTANK", unit)
        if ok and Known(mainTank) then role = "TANK" end
    end
    return ROLE_COORDS[role] and role or nil
end

local POWER_SHOWN = { TANK = "powerShowTank", HEALER = "powerShowHealer", DAMAGER = "powerShowDamager" }

--- Barre de ressource selon le rôle (rôle inconnu : montrée) ; la vie reprend la place laissée.
-- Pas de Layout ici : il redimensionne le bouton sécurisé, interdit en combat.
function GroupFrames:UpdatePowerRole(button)
    local db = self.db
    local role = button.fake and button.fake.role or (button.unit and UnitRole(button.unit))
    local wanted = db.power and (db.powerHeight or 0) > 0 and (not role or db[POWER_SHOWN[role]]) and true or false
    button.cfg.power = wanted
    local px = NS.Pixel:Scale(1)
    local bottom = wanted and (NS.Pixel:Scale(db.powerHeight) + 2 * px) or px
    button.health:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -px, bottom)
    if button.cfg.vertical then   -- prédiction : même hauteur que la vie (enfants non protégés)
        local height = NS.Pixel:Scale(button.cfg.height) - px - bottom
        for _, bar in ipairs({ button.healPrediction, button.absorb, button.healAbsorb }) do bar:SetHeight(height) end
    end
    if not wanted then button.power:Hide() elseif button.unit then Elements.UpdatePower(button) end
end

function GroupFrames:UpdateRole(button)
    local unit = button.unit
    local db = self.db
    local fake = button.fake   -- membre fictif de l'aperçu
    if not unit and not fake then button.role:Hide() button.leader:Hide() return end
    local leader
    if fake then leader = fake.leader
    else leader = _G.UnitIsGroupLeader and Known(UnitIsGroupLeader(unit)) or nil end
    button.leader:SetShown(db.leaderIcon and leader and true or false)
    local role = db.roleIcons and (fake and fake.role or UnitRole(unit))
    local coords = role and ROLE_COORDS[role]
    if coords and db[ROLE_SHOWN[role]] and not (db.roleHideInCombat and inCombat) then
        -- Atlas absent de ce client : SetAtlas rend false, retour à la texture des portraits.
        local atlas = ROLE_ATLAS[db.roleIconStyle]
        if not (atlas and button.role.SetAtlas and button.role:SetAtlas(atlas[role])) then
            button.role:SetTexture(ROLE_ICON)
            button.role:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
        end
        button.role:Show()
    else
        button.role:Hide()
    end
end

-- Résurrection lancée puis finie sur une unité toujours morte : offre à accepter, [jeton] = expiration.
local rezCasting, rezOffered = {}, {}

--- Suit INCOMING_RESURRECT_CHANGED : l'API ne répond que pendant l'incantation, l'offre qui suit
-- reste affichée REZ_OFFER secondes tant que l'unité est morte.
local function TrackResurrection(unit)
    local incoming = _G.UnitHasIncomingResurrection and Known(UnitHasIncomingResurrection(unit))
    if incoming then rezCasting[unit] = true return end
    if rezCasting[unit] and Known(UnitIsDeadOrGhost(unit)) then
        rezOffered[unit] = GetTime() + REZ_OFFER
        C_Timer.After(REZ_OFFER + 0.1, function()
            ForEach(unit, function(button)
                GroupFrames:UpdateStatus(button)
                GroupFrames:UpdateState(button)
            end)
        end)
    end
    rezCasting[unit] = nil
end

local function ResurrectionShown(unit)
    if _G.UnitHasIncomingResurrection and Known(UnitHasIncomingResurrection(unit)) then return true end
    local expiry = rezOffered[unit]
    if not expiry then return false end
    if expiry > GetTime() and Known(UnitIsDeadOrGhost(unit)) then return true end
    rezOffered[unit] = nil
    return false
end

--- Icône centrale : résultat d'appel, sinon invocation, sinon résurrection. Valeur secrète : rien.
function GroupFrames:UpdateStatus(button)
    local unit, icon = button.unit, button.status
    if not icon then return end
    icon:Hide()
    local db = self.db
    if not unit or not db.statusIcons then return end
    if readyCheck and db.readyIcons then
        -- Après la fin, l'API peut ne plus répondre : l'état mémorisé prend le relais.
        local state = _G.GetReadyCheckStatus and Known(GetReadyCheckStatus(unit)) or nil
        if state then button.readyState = state end
        state = state or button.readyState
        if readyFinished and state == "waiting" then state = "notready" end
        if state and READY_TEXTURES[state] then
            icon:SetTexCoord(0, 1, 0, 1)   -- efface le cadrage d'un atlas précédent
            icon:SetTexture(READY_TEXTURES[state])
            icon:Show()
            return
        end
    end
    if db.summonIcons and _G.C_IncomingSummon and C_IncomingSummon.IncomingSummonStatus then
        local ok, status = pcall(C_IncomingSummon.IncomingSummonStatus, unit)
        status = ok and Known(status) or nil
        -- Atlas absent sur ce client : SetAtlas rend false, rien n'est montré.
        if status and SUMMON_ATLAS[status] and icon.SetAtlas and icon:SetAtlas(SUMMON_ATLAS[status]) then
            icon:Show()
            return
        end
    end
    if db.rezIcons and ResurrectionShown(unit) then
        icon:SetTexCoord(0, 1, 0, 1)
        icon:SetTexture(REZ_TEXTURE)
        icon:Show()
    end
end

local STATE_COLORS = { offline = { 0.4, 0.4, 0.4 }, dead = { 0.14, 0.09, 0.09 } }

--- Hors ligne, mort ou fantôme : vie vidée, fond teinté, texte au centre (caché pendant une
-- résurrection, l'icône d'état prend la place). Valeur secrète : état normal.
function GroupFrames:UpdateState(button)
    local unit, text = button.unit, button.stateText
    if not text then return end
    local state, label
    if button.fake then
        state = self.db.stateText and button.fake.state
        label = state and L[state == "offline" and "TEXT_STATUS_OFFLINE" or "TEXT_STATUS_DEAD"]
    elseif unit and self.db.stateText then
        if _G.UnitIsConnected and Known(UnitIsConnected(unit)) == false then
            state, label = "offline", L.TEXT_STATUS_OFFLINE
        elseif _G.UnitIsGhost and Known(UnitIsGhost(unit)) then
            state, label = "dead", L.TEXT_STATUS_GHOST
        elseif Known(UnitIsDead(unit)) then
            state, label = "dead", L.TEXT_STATUS_DEAD
        end
    end
    local fill = button.health:GetStatusBarTexture()
    if fill then fill:SetAlpha(state and 0 or 1) end
    button.health.text:SetAlpha(state and 0 or 1)
    if state then
        local c = STATE_COLORS[state]
        NS.SetSolidColor(button.stateTint, c[1], c[2], c[3], 1)
        button.stateTint:Show()
        text:SetText(label)
        text:SetShown(not (unit and self.db.rezIcons and self.db.statusIcons and ResurrectionShown(unit)))
    else
        button.stateTint:Hide()
        text:Hide()
    end
end

function GroupFrames:UpdateRange(button)
    local unit = button.unit
    if not unit or not self.db.range then button:SetAlpha(1) return end
    NS.SetRangeAlpha(button, unit, self.db.rangeAlpha)   -- portée secrète : le moteur choisit l'alpha
end

--------------------------------------------------------------------------------
-- Sorts suivis par coin
--------------------------------------------------------------------------------

--- Liste « 139, 17 » : { ids = { [id] = true }, names = { [nom] = true } }. Les noms couvrent les
-- autres rangs ; mise en cache tant que tous les noms sont lus.
local spellLists = {}
function GroupFrames.SpellList(text)
    text = tostring(text or "")
    if spellLists[text] then return spellLists[text] end
    local list, complete = { ids = {}, names = {}, empty = true }, true
    for id in text:gmatch("%d+") do
        id = tonumber(id)
        list.ids[id], list.empty = true, false
        local name = NS.GetSpellName(id)
        if name then list.names[name] = true else complete = false end
    end
    if complete then spellLists[text] = list end
    return list
end

--- Conteneur du moteur du bouton, pour ses emplacements (sorts suivis par coin, débuff dissipable) :
-- le moteur les remplit en combat compris, où l'addon ne lit plus les auras. nil sans moteur.
local function AuraSlots(button)
    if button.auraSlots == nil then
        button.auraSlots = not button.isPreview and NS.CreateAuraContainer(button.overlay) or false
        if button.auraSlots then button.auraSlots:SetPoint("CENTER", button.health, "CENTER") end
    end
    return button.auraSlots or nil
end

--- Identifiants suivis par le moteur : ceux de la liste, plus le rang appris du joueur (le moteur ne
-- compare pas les noms). ponytail: les autres rangs lancés par d'autres joueurs ne sont pas suivis.
local function IndicatorCandidates(list)
    local ids = {}
    for id in pairs(list.ids) do
        ids[id] = true
        ids[NS.KnownSpellID(id) or id] = true
    end
    return { includeSpellIDs = ids }
end

--- Coins suivis par le moteur : un emplacement par coin, collé à la création sur un cadre d'ancrage
-- à nous. Le moteur peut refuser de déplacer son bouton (auras secrètes) ; le cadre d'ancrage, jamais.
local function BuildIndicatorSlots(button, engine)
    local db = GroupFrames.db
    local size = NS.Pixel:Scale(db.indicatorSize)
    local filter = db.indicatorMine and "HELPFUL|PLAYER" or "HELPFUL"
    button.cornerAnchors = button.cornerAnchors or {}
    for _, corner in ipairs(CORNERS) do
        local anchor = button.cornerAnchors[corner] or CreateFrame("Frame", nil, button.overlay)
        button.cornerAnchors[corner] = anchor
        anchor:SetSize(size, size)
        anchor:ClearAllPoints()
        anchor:SetPoint(corner, button.health, corner, 0, 0)
        local list = GroupFrames.SpellList(db.indicators[corner])
        NS.SetAuraSlot(engine, corner, filter, not list.empty, function(slotButton)
            NS.InitAuraButton(slotButton, { size = size, noNumbers = true })
            pcall(slotButton.ClearAllPoints, slotButton)
            pcall(slotButton.SetAllPoints, slotButton, anchor)
        end, IndicatorCandidates(list))
    end
end

--- Débuff dissipable vu par le moteur : bordure teintée à sa couleur, lueur (liseré fixe) et fond
-- teinté selon le réglage. Le moteur choisit l'aura ; l'addon ne lit rien.
local function BuildDispelSlot(button, engine)
    local db = GroupFrames.db
    local filter, candidates = "HARMFUL|RAID", nil
    if db.dispelMode == "all" then filter, candidates = "HARMFUL", { includeDispelTypes = ANY_DISPEL } end
    NS.SetAuraSlot(engine, "dispel", filter, db.dispel, function(slotButton)
        pcall(slotButton.SetMouseClickEnabled, slotButton, false)
        pcall(slotButton.SetMouseMotionEnabled, slotButton, false)
        pcall(slotButton.SetAllPoints, slotButton, button)
        local fill = CreateFrame("Frame", nil, slotButton)   -- sous les textes, comme la teinte maison
        fill:SetAllPoints(button.health)
        fill:SetFrameLevel(button.health:GetFrameLevel() + 1)
        fill:SetAlpha(0.35)
        local tint = fill:CreateTexture(nil, "ARTWORK")
        tint:SetAllPoints(fill)
        NS.AddDispelTexture(slotButton, tint)
        local edges = CreateFrame("Frame", nil, slotButton)
        edges:SetAllPoints(button)
        NS.AddDispelEdges(slotButton, edges, NS.Pixel:Scale(NS.db.theme.borderSize or 1))
        local glow = CreateFrame("Frame", nil, slotButton)
        glow:SetAllPoints(button)
        NS.AddDispelEdges(slotButton, glow, NS.Pixel:Scale(2), NS.Pixel:Scale(2))
        button.dispelParts = { fill = fill, glow = glow }
    end, candidates)
    if button.dispelParts then
        button.dispelParts.fill:SetShown(db.dispelFill == true)
        button.dispelParts.glow:SetShown(db.dispelGlow == true)
    end
end

--- Icônes des coins configurés, créées hors combat (Style, Relayout).
local function BuildIndicators(button)
    local engine = AuraSlots(button)
    if engine then
        BuildIndicatorSlots(button, engine)
        BuildDispelSlot(button, engine)
        return
    end
    button.indicators = button.indicators or {}
    local size = NS.Pixel:Scale(GroupFrames.db.indicatorSize)
    for _, corner in ipairs(CORNERS) do
        local indicator = button.indicators[corner]
        if not indicator and (GroupFrames.db.indicators[corner] or "") ~= "" then
            indicator = CreateFrame("Frame", nil, button.overlay)
            indicator:SetFrameLevel(button.overlay:GetFrameLevel() + 2)
            NS.Media:CreateBackdrop(indicator)
            indicator.texture = indicator:CreateTexture(nil, "ARTWORK")
            indicator.texture:SetAllPoints(indicator)
            indicator.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            indicator.cooldown = CreateFrame("Cooldown", nil, indicator, "CooldownFrameTemplate")
            indicator.cooldown:SetAllPoints(indicator)
            if indicator.cooldown.SetHideCountdownNumbers then indicator.cooldown:SetHideCountdownNumbers(true) end
            indicator:Hide()
            button.indicators[corner] = indicator
        end
        if indicator then
            indicator:SetSize(size, size)
            indicator:ClearAllPoints()
            indicator:SetPoint(corner, button.health, corner, 0, 0)
        end
    end
end

--- Premier buff de la liste du coin présent sur l'unité ; identifiant ou nom secrets : ignorés.
function GroupFrames:UpdateIndicators(button, sameUnit)
    if button.auraSlots then   -- le moteur écoute UNIT_AURA ; ici, seulement l'unité
        NS.SetAuraContainerUnit(button.auraSlots, button.unit, not sameUnit)
        return
    end
    if not button.indicators then return end
    -- Lecture refusée (en combat) : sur UNIT_AURA (`sameUnit`), les coins gardent leur état, jamais
    -- « absent » par défaut ; unité changée ou mise à jour complète : cachés, jamais ceux d'un autre.
    if NS.AurasRefused(button.unit) then
        if not sameUnit then
            for _, indicator in pairs(button.indicators) do indicator:Hide() end
        end
        return
    end
    local filter = self.db.indicatorMine and "HELPFUL|PLAYER" or "HELPFUL"
    for corner, indicator in pairs(button.indicators) do
        local list = self.SpellList(self.db.indicators[corner])
        local found, unreadable
        for index = 1, list.empty and 0 or 40 do
            local icon, duration, expiration, _, _, _, spellId, _, _, name = NS.GetAura(button.unit, index, filter)
            if not NS.IsSecret(icon) and icon == nil then break end
            if NS.IsSecret(spellId) and NS.IsSecret(name) then unreadable = true end
            if (not NS.IsSecret(spellId) and list.ids[spellId]) or (not NS.IsSecret(name) and name and list.names[name]) then
                indicator.texture:SetTexture(icon)
                local d, e = Known(duration), Known(expiration)
                if d and e and d > 0 then indicator.cooldown:SetCooldown(e - d, d) else indicator.cooldown:Clear() end
                found = true
                break
            end
        end
        -- Aura illisible (en combat) et rien trouvé : l'indicateur garde son état, jamais « absent » par défaut.
        if found or not unreadable then indicator:SetShown(found or false) end
    end
end

--- Coins remplis du préréglage de la classe du joueur ; false sans préréglage.
function GroupFrames:ApplyIndicatorPreset()
    local _, classFile = UnitClass("player")
    local preset = INDICATOR_PRESETS[classFile]
    if not preset then return false end
    for _, corner in ipairs(CORNERS) do self.db.indicators[corner] = preset[corner] or "" end
    NS.Modules:Refresh("groupframes")
    return true
end

function GroupFrames:UpdateAll(button)
    if not button.unit then return end
    Elements.UpdateHealth(button)
    self:UpdatePowerRole(button)
    Elements.UpdateName(button)
    Elements.UpdateRaidIcon(button)
    Elements.UpdateAuras(button, true)
    self:UpdateIndicators(button)
    Elements.UpdatePortrait(button)
    self:UpdateRole(button)
    self:UpdateBorder(button)
    self:UpdateStatus(button)
    self:UpdateState(button)
    self:UpdateRange(button)
end

local function OnUnitChanged(button, name, value)
    if name ~= "unit" then return end
    local old = button.unit
    if old and byUnit[old] then
        byUnit[old][button] = nil
        if not next(byUnit[old]) then byUnit[old] = nil end
    end
    button.unit = value
    button.readyState = nil      -- l'état d'appel suit l'unité, pas le bouton
    if value then
        byUnit[value] = byUnit[value] or {}
        byUnit[value][button] = true
        if active then GroupFrames:UpdateAll(button) end
    end
end

--- Incantation dans le cadre : fine barre au bas de la vie, sans icône ni texte (place comptée).
local function PlaceCastbar(button)
    local castbar = button.castbar
    castbar:ClearAllPoints()
    castbar:SetPoint("BOTTOMLEFT", button.health, "BOTTOMLEFT", 0, 0)
    castbar:SetPoint("BOTTOMRIGHT", button.health, "BOTTOMRIGHT", 0, 0)
    castbar:SetHeight(NS.Pixel:Scale(button.cfg.castbarHeight or 4))
    castbar.iconFrame:Hide()
    castbar.text:Hide()
end

--- Icônes de rôle, de chef et d'état : taille et coin selon les réglages (Style, Relayout).
local function PlaceIcons(button)
    local db = GroupFrames.db
    local icon = NS.Pixel:Scale(db.roleIconSize or 12)
    local corner = db.roleIconPosition or "TOPLEFT"
    -- Coin pris par un sort suivi : l'icône de rôle se range à côté, vers l'intérieur.
    local taken = (db.indicators[corner] or "") ~= "" and NS.Pixel:Scale(db.indicatorSize) + 2 or 0
    button.role:SetSize(icon, icon)
    button.role:ClearAllPoints()
    button.role:SetPoint(corner, button.health, corner, corner:find("LEFT") and 1 + taken or -1 - taken,
        corner:find("TOP") and -1 or 1)
    if button.auras and button.cfg.aurasInside and (db.indicators.BOTTOMRIGHT or "") ~= "" then
        button.auras:ClearAllPoints()   -- auras intérieures décalées à gauche du sort suivi
        button.auras:SetPoint("BOTTOMRIGHT", button.health, "BOTTOMRIGHT",
            -NS.Pixel:Scale(db.indicatorSize) - 4, NS.Pixel:Scale(2))
    end
    local leader = NS.Pixel:Scale(12)
    button.leader:SetSize(leader, leader)
    button.leader:ClearAllPoints()
    button.leader:SetPoint("CENTER", button.health, "TOP", 0, 0)
    local mark = NS.Pixel:Scale(14)
    button.raidIcon:SetSize(mark, mark)
    button.raidIcon:ClearAllPoints()
    button.raidIcon:SetPoint("TOPRIGHT", button.health, "TOPRIGHT", -2, -2)
    local status = NS.Pixel:Scale(db.statusIconSize or 16)
    button.status:SetSize(status, status)
    button.status:ClearAllPoints()
    button.status:SetPoint("CENTER", button.health, "CENTER", 0, 0)
    -- Nom en haut à gauche (place laissée au marqueur) ou au centre ; l'état passe alors dessous.
    local inset = NS.Pixel:Scale(3)
    local centered = db.namePosition == "CENTER"
    button.name:ClearAllPoints()
    if centered then
        button.name:SetPoint("CENTER", button.health, "CENTER", 0, 0)
        button.name:SetWidth(button:GetWidth() - 2 * inset)
    else
        button.name:SetPoint("TOPLEFT", button.health, "TOPLEFT", inset, -inset)
        button.name:SetWidth(button:GetWidth() - 2 * inset - mark)
    end
    button.name:SetJustifyH(centered and "CENTER" or "LEFT")
    -- Texte de vie et d'état au même endroit : l'un s'efface quand l'autre s'affiche (UpdateState).
    for _, text in ipairs({ button.stateText, button.health.text }) do
        text:ClearAllPoints()
        if centered then
            text:SetPoint("TOP", button.name, "BOTTOM", 0, -1)
        else
            text:SetPoint("CENTER", button.health, "CENTER", 0, 0)
        end
    end
end

--- Habille un bouton créé par l'en-tête, hors combat (voir StyleChildren).
local function Style(header, buttonName)
    local button = type(buttonName) == "table" and buttonName or _G[buttonName]   -- aperçu : le bouton lui-même
    if not button or button.styled then return end
    button.styled = true
    button.header = header
    button.isPreview = type(buttonName) == "table"
    button.cfg, button.global = Config(header.key), GroupFrames.db
    -- La bordure du fond sert d'indicateur (agro, dispel) : THEME_CHANGED la repeint à la
    -- couleur du thème, puis Reconcile la recolore.
    local _, edges = NS.Media:CreateBackdrop(button)
    button.border = edges
    -- Lueur de menace : liseré coloré qui déborde du bouton, sous le fond.
    button.glow = button:CreateTexture(nil, "BACKGROUND", nil, -8)
    button.glow:SetPoint("TOPLEFT", button, "TOPLEFT", -2, 2)
    button.glow:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 2, -2)
    button.glow:Hide()
    Elements.Build(button)
    Elements.BuildAuras(button)
    -- Mort, hors ligne : teinte sur le fond de la vie (son remplissage est rendu transparent).
    button.stateTint = button.health:CreateTexture(nil, "BACKGROUND", nil, 1)
    button.stateTint:SetAllPoints(button.health)
    button.stateTint:Hide()
    button.stateText = NS.Media:CreateText(button.overlay, "OVERLAY", 0, "OUTLINE")
    button.stateText:Hide()
    button.dispelTint = button.overlay:CreateTexture(nil, "BACKGROUND")
    button.dispelTint:SetAllPoints(button.health)
    button.dispelTint:Hide()
    button.status = button.overlay:CreateTexture(nil, "OVERLAY", nil, 7)
    button.status:Hide()
    button.role = button.overlay:CreateTexture(nil, "OVERLAY")
    button.role:SetTexture(ROLE_ICON)
    button.leader = button.overlay:CreateTexture(nil, "OVERLAY")
    button.leader:SetTexture(LEADER_ICON)
    -- Survol : voile clair sur la vie ; les scripts d'origine du bouton (infobulle) restent.
    button.hover = button.overlay:CreateTexture(nil, "ARTWORK")
    button.hover:SetAllPoints(button.health)
    NS.SetSolidColor(button.hover, 1, 1, 1, 0.12)
    button.hover:Hide()
    button:HookScript("OnEnter", function(self) if GroupFrames.db.mouseoverHighlight then self.hover:Show() end end)
    button:HookScript("OnLeave", function(self) self.hover:Hide() end)
    Elements.Layout(button)
    PlaceCastbar(button)
    PlaceIcons(button)
    BuildIndicators(button)
    button:SetScript("OnAttributeChanged", OnUnitChanged)
    header.buttons[#header.buttons + 1] = button
    local unit = button:GetAttribute("unit")
    if unit then OnUnitChanged(button, "unit", unit) end
end

local function Relayout(button)
    button.cfg, button.global = Config(button.header.key), GroupFrames.db
    Elements.BuildAuras(button)
    Elements.Layout(button)
    PlaceCastbar(button)
    PlaceIcons(button)
    BuildIndicators(button)
end

--------------------------------------------------------------------------------
-- En-têtes
--------------------------------------------------------------------------------

--- Habille les boutons que l'en-tête vient de créer (hors combat : l'en-tête ne crée qu'hors
-- combat). Les attributs de clic sont posés ici ; tailles et RegisterUnitWatch viennent de
-- l'en-tête (initial-width, initial-height).
local function StyleChildren(header)
    -- Un membre qui rejoint en combat : l'en-tête crée le bouton, mais SetAttribute est bloqué.
    if NS.InCombat() then NS:RunOutOfCombat(function() StyleChildren(header) end) return end
    for _, child in ipairs({ header:GetChildren() }) do
        if not child.styled and child.GetName and child:GetName() then
            child:SetAttribute("*type1", "target")
            child:SetAttribute("*type2", "togglemenu")
            child:RegisterForClicks("AnyUp")
            Style(header, child:GetName())
            local clickCast = NS.Modules:Get("clickcast")
            if clickCast then clickCast:Apply(child) end
        end
    end
end

local headerHooked = false

local function NewHeader(key)
    local header = CreateFrame("Frame", "AeonUI_Group_" .. key, UIParent, "SecureGroupHeaderTemplate")
    header.key = key
    header.buttons = {}
    header:SetAttribute("template", "SecureUnitButtonTemplate")
    if not headerHooked and _G.SecureGroupHeader_Update then
        headerHooked = true
        hooksecurefunc("SecureGroupHeader_Update", function(updated)
            if updated.key and GroupFrames.headers[updated.key] == updated then
                NS.Modules:Within("groupframes", StyleChildren, updated)
            end
        end)
    end
    GroupFrames.headers[key] = header
    return header
end

--- Membres vers `unit`, colonnes vers `column` ; colonnes forcées perpendiculaires aux membres,
-- sinon l'en-tête ne passe jamais à la colonne suivante.
local function SetGrowth(header, unit, column, spacing)
    unit = GROWTH[unit] and unit or "DOWN"
    if not GROWTH[column] or VERTICAL[column] == VERTICAL[unit] then column = VERTICAL[unit] and "RIGHT" or "DOWN" end
    local g = GROWTH[unit]
    header:SetAttribute("point", g[1])
    header:SetAttribute("xOffset", g[2] * spacing)
    header:SetAttribute("yOffset", g[3] * spacing)
    header:SetAttribute("columnAnchorPoint", GROWTH[column][1])
    header:SetAttribute("columnSpacing", spacing)
end

local function Apply(header)
    local db = GroupFrames.db
    local S = function(n) return NS.Pixel:Scale(n) end
    local width, height = GroupFrames.Size(header.key)
    header:SetAttribute("initial-width", S(width))
    header:SetAttribute("initial-height", S(height))
    header:SetAttribute("showPlayer", db.showPlayer)
    if header.key == "party" then
        -- Seuil : jusqu'à `raidThreshold` membres, un raid garde la disposition du groupe (cet
        -- en-tête montre alors les membres du raid) ; au-delà, l'en-tête de raid prend le relais.
        local threshold = tonumber(db.raidThreshold) or 5
        local aboveThreshold = "[@raid" .. (threshold + 1) .. ",exists]"
        header:SetAttribute("showParty", true)
        header:SetAttribute("showRaid", threshold > 5)
        header:SetAttribute("showSolo", db.showSolo)
        local growth = db.horizontal and (db.reverse and "LEFT" or "RIGHT") or (db.reverse and "UP" or "DOWN")
        SetGrowth(header, growth, nil, S(db.spacing))
        header:SetAttribute("maxColumns", math.max(1, math.ceil(threshold / 5)))
        header:SetAttribute("unitsPerColumn", 5)
        if db.partySortRole then
            header:SetAttribute("groupBy", "ASSIGNEDROLE")
            header:SetAttribute("groupingOrder", "TANK,HEALER,DAMAGER,NONE")
        else
            header:SetAttribute("groupBy", threshold > 5 and "GROUP" or nil)
            header:SetAttribute("groupingOrder", "1,2,3,4,5,6,7,8")
        end
        header:SetAttribute("sortMethod", "INDEX")
        if threshold > 5 then
            RegisterStateDriver(header, "visibility", aboveThreshold .. " hide; [group] show; " .. (db.showSolo and "show" or "hide"))
        else
            RegisterStateDriver(header, "visibility", "[group:raid] hide; [group:party] show; " .. (db.showSolo and "show" or "hide"))
        end
    elseif ROLE_HEADERS[header.key] then
        -- Tanks et assistants principaux : une colonne, filtrée par assignation de raid. Extra :
        -- liste de noms (prioritaire pour l'en-tête) ou rôle, en groupe aussi.
        local extra = header.key == "extra"
        local names = extra and tostring(db.extraNames or ""):gsub("%s*,%s*", ","):match("^[%s,]*(.-)[%s,]*$") or ""
        names = names ~= "" and names or nil
        header:SetAttribute("showParty", extra)
        header:SetAttribute("showRaid", true)
        header:SetAttribute("showSolo", false)
        header:SetAttribute("nameList", names)
        header:SetAttribute("groupFilter", not names and ROLE_HEADERS[header.key].filter or nil)
        header:SetAttribute("groupBy", nil)
        header:SetAttribute("sortMethod", "INDEX")
        header:SetAttribute("point", "TOP")
        header:SetAttribute("xOffset", 0)
        header:SetAttribute("yOffset", -S(db.spacing))
        header:SetAttribute("maxColumns", 1)
        header:SetAttribute("unitsPerColumn", 10)
        RegisterStateDriver(header, "visibility", extra and "[group] show; hide" or "[group:raid] show; hide")
    else
        header:SetAttribute("showParty", false)
        header:SetAttribute("showRaid", true)
        header:SetAttribute("showSolo", false)
        SetGrowth(header, db.raidUnitGrowth, db.raidGroupGrowth, S(db.spacing))
        local groups = math.max(1, math.min(8, tonumber(db.raidGroups) or 8))
        header:SetAttribute("groupFilter", groups < 8 and ("1,2,3,4,5,6,7,8"):sub(1, groups * 2 - 1) or nil)
        header:SetAttribute("maxColumns", db.raidColumns)
        header:SetAttribute("unitsPerColumn", db.raidUnitsPerColumn)
        if db.raidSortBy == "GROUP" then
            header:SetAttribute("groupBy", "GROUP")
            header:SetAttribute("groupingOrder", "1,2,3,4,5,6,7,8")
            header:SetAttribute("sortMethod", "INDEX")
        elseif db.raidSortBy == "CLASS" then
            header:SetAttribute("groupBy", "CLASS")
            header:SetAttribute("groupingOrder", "WARRIOR,PALADIN,DRUID,PRIEST,SHAMAN,MAGE,WARLOCK,HUNTER,ROGUE")
            header:SetAttribute("sortMethod", "NAME")
        elseif db.raidSortBy == "ROLE" then
            header:SetAttribute("groupBy", "ASSIGNEDROLE")
            header:SetAttribute("groupingOrder", "TANK,HEALER,DAMAGER,NONE")
            header:SetAttribute("sortMethod", "NAME")
        else
            header:SetAttribute("groupBy", nil)
            header:SetAttribute("sortMethod", "NAME")
        end
        local threshold = tonumber(db.raidThreshold) or 5
        if threshold > 5 then
            RegisterStateDriver(header, "visibility", "[@raid" .. (threshold + 1) .. ",exists] show; hide")
        else
            RegisterStateDriver(header, "visibility", "[group:raid] show; hide")
        end
    end
    for _, button in ipairs(header.buttons) do Relayout(button) end
end

local MOVER_DEFAULTS = { party = { "TOPLEFT", 20, -200 }, raid = { "TOPLEFT", 20, -300 },
                         tank = { "CENTER", -560, 120 }, assist = { "CENTER", -560, 260 },
                         extra = { "CENTER", -560, -40 } }

--------------------------------------------------------------------------------
-- Boss alliés : boutons boss1 à boss5, montrés par pilote d'état quand le boss est assistable
--------------------------------------------------------------------------------

local bossHeader = { key = "boss", buttons = {} }   -- pas un en-tête sécurisé : Style y range ses boutons
GroupFrames.bossHeader = bossHeader

local function ApplyFriendlyBoss(on)
    local holder = bossHeader.holder
    if not on then
        if not holder then return end
        for _, button in ipairs(bossHeader.buttons) do
            UnregisterStateDriver(button, "visibility")
            button:Hide()
        end
        holder:Hide()
        Movers:Unregister("uf_friendlyboss")
        return
    end
    local db = GroupFrames.db
    local S = function(n) return NS.Pixel:Scale(n) end
    if not holder then
        holder = CreateFrame("Frame", "AeonUI_FriendlyBoss", UIParent)
        bossHeader.holder = holder
        for index = 1, BOSS_COUNT do
            local button = CreateFrame("Button", "AeonUI_FriendlyBossButton" .. index, holder, "SecureUnitButtonTemplate")
            button:SetSize(S(db.width), S(db.height))
            button:SetAttribute("unit", "boss" .. index)
            button:SetAttribute("*type1", "target")
            button:SetAttribute("*type2", "togglemenu")
            button:RegisterForClicks("AnyUp")
            Style(bossHeader, button:GetName())
            local clickCast = NS.Modules:Get("clickcast")
            if clickCast then clickCast:Apply(button) end
        end
    end
    for index, button in ipairs(bossHeader.buttons) do
        button:SetSize(S(db.width), S(db.height))
        button:ClearAllPoints()
        button:SetPoint("TOP", holder, "TOP", 0, -(index - 1) * (S(db.height) + S(db.spacing)))
        Relayout(button)
        RegisterStateDriver(button, "visibility", "[@boss" .. index .. ",help] show; hide")
    end
    holder:SetSize(S(db.width), BOSS_COUNT * S(db.height) + (BOSS_COUNT - 1) * S(db.spacing))
    holder:Show()
    Movers:Register("uf_friendlyboss", holder, L.MOVER_UF_FRIENDLYBOSS, "CENTER", 360, 200)
    Movers:Load("uf_friendlyboss")
end

--------------------------------------------------------------------------------
-- Aperçu : faux membres (boutons ordinaires, sans unité) posés à la place des en-têtes
--------------------------------------------------------------------------------

-- Nom, classe, rôle, vie en % ; puis au besoin : state (dead | offline), dispel, threat, leader, mark.
local PREVIEW_PARTY = {
    { name = "Brannoc", class = "WARRIOR", role = "TANK", hp = 72, threat = 3, leader = true, mark = 8 },
    { name = "Elowen", class = "PRIEST", role = "HEALER", hp = 100 },
    { name = "Thalindra", class = "MAGE", role = "DAMAGER", hp = 45, dispel = "Magic" },
    { name = "Grimjaw", class = "ROGUE", role = "DAMAGER", hp = 0, state = "dead" },
    { name = "Sylvaris", class = "HUNTER", role = "DAMAGER", hp = 100, state = "offline" },
}
local PREVIEW_RAID_CLASSES = { "PALADIN", "DRUID", "SHAMAN", "PRIEST", "MAGE", "WARLOCK", "HUNTER", "ROGUE", "WARRIOR" }
local POWER_COLORS = { WARRIOR = { 0.78, 0.25, 0.25 }, ROGUE = { 1, 0.96, 0.41 } }   -- sinon mana
local PREVIEW_NAMES = { "Brannoc", "Kaldrek", "Elowen", "Maerith", "Oswin", "Tessaly", "Thalindra", "Grimjaw",
                        "Sylvaris", "Durnhelm", "Ysolde", "Varric", "Nimue", "Corvash", "Liraen", "Haldor",
                        "Quenby", "Morwenna", "Taviel", "Ashgar" }
local PREVIEW_DEBUFF ={ icon = "Interface\\Icons\\Spell_Shadow_Possession", dispel = "Magic" }

local function PreviewRaid()
    local list = {}
    for i = 1, 20 do
        local role = i <= 2 and "TANK" or (i <= 6 and "HEALER" or "DAMAGER")
        local class = role == "TANK" and "WARRIOR" or PREVIEW_RAID_CLASSES[(i % #PREVIEW_RAID_CLASSES) + 1]
        if role == "HEALER" then class = ({ "PRIEST", "DRUID", "PALADIN", "SHAMAN" })[i - 2] end
        list[i] = { name = PREVIEW_NAMES[i], class = class, role = role, hp = 40 + (i * 37) % 61 }
    end
    list[1].threat, list[1].mark, list[1].leader = 3, 8, true
    list[5].dispel, list[9].state, list[14].state, list[14].hp = "Magic", "offline", "dead", 0
    return list
end

local previewHeaders = {}

--- Peint un faux membre : les mêmes régions que pour une unité, remplies à la main.
local function PaintPreview(button, fake)
    local db = GroupFrames.db
    button.fake = fake
    local class = RAID_CLASS_COLORS and RAID_CLASS_COLORS[fake.class]
    local r, g, b = 0.2, 0.75, 0.3
    if db.classColor and class then r, g, b = class.r, class.g, class.b end
    button.health:SetMinMaxValues(0, 100)
    button.health:SetValue(fake.hp)
    NS.Media:SetHealthColor(button.health, r, g, b)
    button.health.text:SetText(db.healthText ~= "none" and (fake.hp .. "%") or "")
    for _, bar in ipairs({ button.healPrediction, button.absorb, button.healAbsorb }) do bar:Hide() end
    button.name:SetText(Elements.TruncateName(fake.name, button.cfg.nameLength))
    if db.classColor and class then button.name:SetTextColor(class.r, class.g, class.b) else button.name:SetTextColor(1, 1, 1) end
    GroupFrames:UpdatePowerRole(button)
    if button.cfg.power then
        local p = POWER_COLORS[fake.class] or { 0, 0.44, 0.87 }
        button.power:SetMinMaxValues(0, 100)
        button.power:SetValue(fake.state and 0 or 80)
        button.power:SetStatusBarColor(p[1], p[2], p[3])
        button.power:Show()
    end
    GroupFrames:UpdateRole(button)
    if fake.mark and _G.SetRaidTargetIconTexture then
        SetRaidTargetIconTexture(button.raidIcon, fake.mark)
        button.raidIcon:Show()
    else
        button.raidIcon:Hide()
    end
    GroupFrames:UpdateState(button)
    local dispelColor = db.dispel and fake.dispel and _G.DebuffTypeColor and DebuffTypeColor[fake.dispel]
    button.dispelTint:SetShown(db.dispelFill and dispelColor and true or false)
    if dispelColor then NS.SetSolidColor(button.dispelTint, dispelColor.r, dispelColor.g, dispelColor.b, 0.35) end
    local threat = db.aggro and fake.threat and THREAT_COLORS[fake.threat]
    button.glow:SetShown(threat and db.aggroStyle == "glow" and true or false)
    if threat then NS.SetSolidColor(button.glow, threat[1], threat[2], threat[3], 0.6) end
    local border = (threat and db.aggroStyle ~= "glow" and { r = threat[1], g = threat[2], b = threat[3] })
        or dispelColor or NS.db.theme.border
    PaintBorder(button, border.r, border.g, border.b)
    Elements.PreviewAuras(button, fake.dispel and { PREVIEW_DEBUFF } or {})
    button.status:Hide()
    button:SetAlpha(fake.state == "offline" and db.range and db.rangeAlpha or 1)
end

--- Aperçu "party", "raid" ou nil (caché) ; suit les réglages de disposition du groupe ou du raid.
-- ponytail: croissance approchée depuis le coin haut gauche de l'en-tête ; une croissance vers le
-- haut ou la gauche déborde de l'autre côté de l'ancre, à reprendre si l'aperçu doit être exact.
function GroupFrames:SetPreview(mode)
    self.preview = active and not NS.InCombat() and mode or nil
    for key, holder in pairs(previewHeaders) do
        if key ~= self.preview then holder:Hide() end
    end
    mode = self.preview
    if not mode then return end
    local holder = previewHeaders[mode]
    if not holder then
        holder = CreateFrame("Frame", nil, UIParent)
        holder.key, holder.buttons = mode, {}
        holder:SetFrameStrata("MEDIUM")
        previewHeaders[mode] = holder
    end
    local db = self.db
    local fakes = mode == "raid" and PreviewRaid() or PREVIEW_PARTY
    for index = #holder.buttons + 1, #fakes do Style(holder, CreateFrame("Button", nil, holder)) end
    local S = function(n) return NS.Pixel:Scale(n) end
    local width, height = GroupFrames.Size(mode)
    local spacing = S(db.spacing)
    local unitGrowth, columnGrowth, perColumn
    if mode == "raid" then
        unitGrowth, perColumn = GROWTH[db.raidUnitGrowth] and db.raidUnitGrowth or "DOWN", db.raidUnitsPerColumn
        columnGrowth = db.raidGroupGrowth
        if not GROWTH[columnGrowth] or VERTICAL[columnGrowth] == VERTICAL[unitGrowth] then
            columnGrowth = VERTICAL[unitGrowth] and "RIGHT" or "DOWN"
        end
    else
        unitGrowth = db.horizontal and (db.reverse and "LEFT" or "RIGHT") or (db.reverse and "UP" or "DOWN")
        columnGrowth, perColumn = VERTICAL[unitGrowth] and "RIGHT" or "DOWN", 5
    end
    local u, c = GROWTH[unitGrowth], GROWTH[columnGrowth]
    local stepX, stepY = S(width) + spacing, S(height) + spacing
    local anchor = self.headers[mode] or self.headers.party
    holder:ClearAllPoints()
    holder:SetPoint("TOPLEFT", anchor or UIParent, "TOPLEFT", 0, 0)
    holder:SetSize(S(width), S(height))
    for index, button in ipairs(holder.buttons) do
        local fake = fakes[index]
        if fake then
            Relayout(button)
            local row, column = (index - 1) % perColumn, math.floor((index - 1) / perColumn)
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", holder, "TOPLEFT", (u[2] * row + c[2] * column) * stepX,
                (u[3] * row + c[3] * column) * stepY)
            PaintPreview(button, fake)
            button:Show()
        else
            button:Hide()
        end
    end
    holder:Show()
end

function GroupFrames:Reconcile()
    for _, key in ipairs(HEADER_KEYS) do
        local role = ROLE_HEADERS[key]
        if role and not self.db[role.option] then
            local header = self.headers[key]
            if header then
                UnregisterStateDriver(header, "visibility")
                header:Hide()
                Movers:Unregister("uf_" .. key)
            end
        else
            local header = self.headers[key] or NewHeader(key)
            Apply(header)
            local d = MOVER_DEFAULTS[key]
            Movers:Register("uf_" .. key, header, L["MOVER_UF_" .. key:upper()], d[1], d[2], d[3])
            Movers:Load("uf_" .. key)   -- visibilité : pilote d'état, jamais Show() par-dessus
        end
    end
    ApplyFriendlyBoss(self.db.friendlyBoss)
    if self.db.hideBlizzard then
        for _, name in ipairs(BLIZZARD) do NS.HideBlizzardFrame(name) end
        NS.HideBlizzardFrame("CompactRaidFrameManager", true)
    else
        for _, name in ipairs(BLIZZARD) do NS.ShowBlizzardFrame(name) end
        NS.ShowBlizzardFrame("CompactRaidFrameManager")
    end
    ForEach(nil, function(button) self:UpdateAll(button) end)
    if self.preview then self:SetPreview(self.preview) end
end

--- Bouton de l'unité ; `key` choisit l'en-tête (défaut : groupe ou raid d'abord).
function GroupFrames:GetButton(unit, key)
    local found
    for button in pairs(byUnit[unit] or {}) do
        local headerKey = button.header and button.header.key
        if headerKey == key then return button end
        if not key and not ROLE_HEADERS[headerKey] then return button end
        if not key then found = found or button end
    end
    return found
end

--------------------------------------------------------------------------------
-- Mana des soigneurs : une ligne « nom  pourcentage » par membre au rôle soigneur
--------------------------------------------------------------------------------

local HEALER_ROWS = 10
local ROW_HEIGHT = 14
local manaFrame
local manaUnits = {}            -- [jeton] = ligne
GroupFrames.manaUnits = manaUnits

local function HealerManaWanted()
    local mode = GroupFrames.db.healerMana
    if IsInRaid() then return mode == "raid" or mode == "both" end
    return IsInGroup() and (mode == "party" or mode == "both")
end

local function BuildHealerMana()
    manaFrame = CreateFrame("Frame", "AeonUI_HealerMana", UIParent)
    manaFrame:SetSize(NS.Pixel:Scale(140), HEALER_ROWS * NS.Pixel:Scale(ROW_HEIGHT))
    manaFrame.rows = {}
    for index = 1, HEALER_ROWS do
        local row = {}
        row.name = NS.Media:CreateText(manaFrame, "OVERLAY")
        row.name:SetPoint("TOPLEFT", manaFrame, "TOPLEFT", 0, -(index - 1) * NS.Pixel:Scale(ROW_HEIGHT))
        row.name:SetJustifyH("LEFT")
        row.value = NS.Media:CreateText(manaFrame, "OVERLAY")
        row.value:SetPoint("TOPRIGHT", manaFrame, "TOPRIGHT", 0, -(index - 1) * NS.Pixel:Scale(ROW_HEIGHT))
        row.value:SetJustifyH("RIGHT")
        manaFrame.rows[index] = row
    end
end

local function PaintMana(unit)
    local row = manaUnits[unit]
    if row then Elements.SetUnitText(row.value, unit, "mana", "[perc]") end
end

--- Lignes des soigneurs du groupe (rôle assigné) ; rôle ou classe secrets : membre sauté.
function GroupFrames:UpdateHealerMana()
    wipe(manaUnits)
    local mode = self.db.healerMana
    if not manaFrame then
        if not active or mode == "none" then return end
        BuildHealerMana()
    end
    if not active or mode == "none" then
        manaFrame:Hide()
        manaFrame.registered = false
        Movers:Unregister("uf_healermana")
        return
    end
    if not manaFrame.registered then   -- une fois : Load à chaque roster couperait un glisser en cours
        manaFrame.registered = true
        Movers:Register("uf_healermana", manaFrame, L.MOVER_UF_HEALERMANA, "CENTER", 320, 0)
        Movers:Load("uf_healermana")
    end
    manaFrame:Show()
    local units = {}
    if HealerManaWanted() then
        if IsInRaid() then
            for i = 1, GetNumGroupMembers() do units[#units + 1] = "raid" .. i end
        else
            units[1] = "player"
            for i = 1, GetNumGroupMembers() - 1 do units[#units + 1] = "party" .. i end
        end
    end
    local count = 0
    for _, unit in ipairs(units) do
        local role = _G.UnitGroupRolesAssigned and Known(UnitGroupRolesAssigned(unit))
        if role == "HEALER" and count < HEALER_ROWS then
            count = count + 1
            local row = manaFrame.rows[count]
            local _, classFile = UnitClass(unit)
            local color = Known(classFile) and RAID_CLASS_COLORS[classFile]
            row.name:SetText(UnitName(unit))   -- nom secret : affiché tel quel
            if color then row.name:SetTextColor(color.r, color.g, color.b) else row.name:SetTextColor(1, 1, 1) end
            manaUnits[unit] = row
            PaintMana(unit)
        end
    end
    for index, row in ipairs(manaFrame.rows) do
        row.name:SetShown(index <= count)
        row.value:SetShown(index <= count)
    end
end

--------------------------------------------------------------------------------
-- Événements
--------------------------------------------------------------------------------

local UNIT_EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER",
                      "UNIT_NAME_UPDATE", "UNIT_CONNECTION", "UNIT_AURA", "UNIT_THREAT_SITUATION_UPDATE",
                      "UNIT_HEAL_PREDICTION", "UNIT_ABSORB_AMOUNT_CHANGED", "UNIT_HEAL_ABSORB_AMOUNT_CHANGED",
                      "INCOMING_RESURRECT_CHANGED",
                      "INCOMING_SUMMON_CHANGED", "READY_CHECK_CONFIRM", "UNIT_PORTRAIT_UPDATE", "UNIT_MODEL_CHANGED" }

local function OnReadyCheck(event)
    if event == "READY_CHECK" then
        readyCheck, readyFinished, readyToken = true, false, readyToken + 1
        ForEach(nil, function(button) button.readyState = nil end)
    elseif event == "READY_CHECK_FINISHED" then
        -- Le résultat reste affiché quelques secondes, sur l'état mémorisé de chaque bouton.
        if not readyCheck then return end
        readyFinished = true
        readyToken = readyToken + 1
        local token = readyToken
        C_Timer.After(READY_LINGER, function()
            if token ~= readyToken then return end
            readyCheck, readyFinished = false, false
            ForEach(nil, function(button)
                button.readyState = nil
                GroupFrames:UpdateStatus(button)
            end)
        end)
    end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, unit)
    if not active then return end
    if unit and manaUnits[unit] and (event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER" or event == "UNIT_DISPLAYPOWER") then
        PaintMana(unit)
    end
    if event == "INCOMING_RESURRECT_CHANGED" and unit then TrackResurrection(unit) end
    if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ROLES_ASSIGNED" or event == "PARTY_LEADER_CHANGED"
        or event == "PLAYER_ENTERING_WORLD" or event == "INSTANCE_ENCOUNTER_ENGAGE_UNIT" then
        if event == "GROUP_ROSTER_UPDATE" then wipe(rezCasting) wipe(rezOffered) end   -- jetons décalés
        ForEach(nil, function(button) GroupFrames:UpdateAll(button) end)
        GroupFrames:UpdateHealerMana()
    elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        inCombat = event == "PLAYER_REGEN_DISABLED"
        if inCombat and GroupFrames.preview then GroupFrames:SetPreview(nil) end
        if GroupFrames.db.roleHideInCombat then ForEach(nil, function(button) GroupFrames:UpdateRole(button) end) end
    elseif event == "INCOMING_SUMMON_CHANGED" and not unit then
        ForEach(nil, function(button) GroupFrames:UpdateStatus(button) end)
    elseif event == "RAID_TARGET_UPDATE" then
        ForEach(nil, Elements.UpdateRaidIcon)
    elseif event == "PLAYER_TARGET_CHANGED" then
        ForEach(nil, function(button) GroupFrames:UpdateBorder(button) end)
    elseif event == "READY_CHECK" or event == "READY_CHECK_FINISHED" then
        OnReadyCheck(event)
        ForEach(nil, function(button) GroupFrames:UpdateStatus(button) end)
    elseif unit and byUnit[unit] then
        ForEach(unit, function(button)
            if event == "UNIT_AURA" or event == "UNIT_THREAT_SITUATION_UPDATE" then
                GroupFrames:UpdateBorder(button)
                if event == "UNIT_AURA" then
                    Elements.UpdateAuras(button)
                    GroupFrames:UpdateIndicators(button, true)
                end
            elseif event == "INCOMING_RESURRECT_CHANGED" or event == "INCOMING_SUMMON_CHANGED"
                    or event == "READY_CHECK_CONFIRM" then
                GroupFrames:UpdateStatus(button)
                GroupFrames:UpdateState(button)
            elseif not Elements.OnEvent(button, event) then
                GroupFrames:UpdateAll(button)
            elseif event == "UNIT_HEALTH" or event == "UNIT_CONNECTION" then
                if rezOffered[unit] then GroupFrames:UpdateStatus(button) end   -- relevé : l'offre disparaît
                GroupFrames:UpdateState(button)
            end
        end)
    end
end)

local function RangeTick()
    if not active then return end
    ForEach(nil, function(button) GroupFrames:UpdateRange(button) end)
end

--------------------------------------------------------------------------------
-- Cycle de vie
--------------------------------------------------------------------------------

function GroupFrames:OnEnable()
    active = true
    inCombat = NS.InCombat() and true or false
    self:Reconcile()
    for _, event in ipairs({ "GROUP_ROSTER_UPDATE", "PLAYER_ROLES_ASSIGNED", "PARTY_LEADER_CHANGED",
                             "PLAYER_ENTERING_WORLD", "RAID_TARGET_UPDATE", "READY_CHECK", "READY_CHECK_FINISHED",
                             "PLAYER_TARGET_CHANGED", "INSTANCE_ENCOUNTER_ENGAGE_UNIT",
                             "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
        NS.RegisterEventSafe(events, event)
    end
    for _, event in ipairs(UNIT_EVENTS) do NS.RegisterEventSafe(events, event) end
    self:RegisterCastEvents()
    self:UpdateHealerMana()
    if not rangeTicker and C_Timer and C_Timer.NewTicker then rangeTicker = C_Timer.NewTicker(0.25, RangeTick) end
end

function GroupFrames:OnDisable()
    active = false
    self:SetPreview(nil)
    events:UnregisterAllEvents()
    if rangeTicker then rangeTicker:Cancel() rangeTicker = nil end
    for key, header in pairs(self.headers) do
        UnregisterStateDriver(header, "visibility")
        header:Hide()
        Movers:Unregister("uf_" .. key)
    end
    ApplyFriendlyBoss(false)
    self:UpdateHealerMana()
    for _, name in ipairs(BLIZZARD) do NS.ShowBlizzardFrame(name) end
    NS.ShowBlizzardFrame("CompactRaidFrameManager")
    if next(self.headers) then NS.Print(L.MSG_GF_DISABLED_RELOAD) end
end

--- Incantations des membres suivies seulement avec l'option : un raid en envoie beaucoup.
function GroupFrames:RegisterCastEvents()
    for _, event in ipairs(Elements.CAST_EVENTS) do
        if self.db.castbar then NS.RegisterEventSafe(events, event)
        else events:UnregisterEvent(event) end
    end
end

function GroupFrames:OnRefresh()
    self:Reconcile()
    self:RegisterCastEvents()
    self:UpdateHealerMana()
end

NS:On("PIXEL_CHANGED", function()
    if active then NS:RunOutOfCombat(function() if active then GroupFrames:Reconcile() end end) end
end)

--------------------------------------------------------------------------------
-- Options
--------------------------------------------------------------------------------

function GroupFrames:BuildOptions(o)
    local function Preview(mode)
        return function() NS.Modules:Within("groupframes", function() GroupFrames:SetPreview(mode) end) end
    end
    o.layout:Note(L.NOTE_GF_RELOAD, 20)
    o.layout:Button(L.OPT_GF_PREVIEW_PARTY, Preview("party"), 20)
    o.layout:Button(L.OPT_GF_PREVIEW_RAID, Preview("raid"), 20)
    o.layout:Button(L.OPT_GF_PREVIEW_HIDE, Preview(nil), 20)
    o.layout:Button(L.OPT_UF_UNLOCK, function() NS:SetUnlocked(not NS.unlocked) end, 20)
    o:Advanced()
    o:Slider("spacing", L.OPT_GF_SPACING, 0, 20, 1)
    o:EndAdvanced()
    o:Check("hideBlizzard", L.OPT_NPF_HIDE_BLIZZARD)

    o:Tab(L.UF_UNIT_PARTY)
    o:Slider("width", L.OPT_UF_WIDTH, 40, 200, 2)
    o:Slider("height", L.OPT_UF_HEIGHT, 12, 80, 1)
    o:Check("partySortRole", L.OPT_GF_PARTY_SORT_ROLE)
    o:Check("showPlayer", L.OPT_GF_SHOW_PLAYER)
    o:Check("showSolo", L.OPT_GF_SHOW_SOLO)
    o:Advanced()
    o:Check("horizontal", L.OPT_GF_HORIZONTAL)
    o:Check("reverse", L.OPT_GF_REVERSE)
    o:EndAdvanced()

    o:Tab(L.UF_UNIT_RAID)
    o:Slider("raidWidth", L.OPT_UF_WIDTH, 40, 200, 2)
    o:Slider("raidHeight", L.OPT_UF_HEIGHT, 12, 80, 1)
    o:Dropdown("raidSortBy", L.OPT_GF_SORT, {
        { name = L.GF_SORT_ROLE, value = "ROLE" }, { name = L.GF_SORT_GROUP, value = "GROUP" },
        { name = L.GF_SORT_CLASS, value = "CLASS" }, { name = L.GF_SORT_NAME, value = "NAME" } })
    o:Slider("raidUnitsPerColumn", L.OPT_GF_UNITS_PER_COLUMN, 1, 10, 1)
    o:Slider("raidColumns", L.OPT_GF_COLUMNS, 1, 8, 1)
    local growth = {}
    for _, direction in ipairs(GroupFrames.GROWTH_ORDER) do
        growth[#growth + 1] = { name = L["GF_GROWTH_" .. direction], value = direction }
    end
    o:Advanced()
    o:Dropdown("raidUnitGrowth", L.OPT_GF_UNIT_GROWTH, growth)
    o:Dropdown("raidGroupGrowth", L.OPT_GF_GROUP_GROWTH, growth)
    o:Hint(L.OPT_GF_GROUP_GROWTH_HINT)
    o:EndAdvanced()
    o:Advanced()
    o:Slider("raidGroups", L.OPT_GF_RAID_GROUPS, 1, 8, 1)
    o:Dropdown("raidThreshold", L.OPT_GF_RAID_THRESHOLD, {
        { name = "5", value = 5 }, { name = "10", value = 10 }, { name = "40", value = 40 } })
    o:Hint(L.OPT_GF_RAID_THRESHOLD_HINT)
    o:EndAdvanced()
    o:Check("mainTanks", L.OPT_GF_MAIN_TANKS)
    o:Check("mainAssists", L.OPT_GF_MAIN_ASSISTS)
    o:Advanced()
    o:Check("extraFrames", L.OPT_GF_EXTRA_FRAMES)
    o:EditBox("extraNames", L.OPT_GF_EXTRA_NAMES, 1, 36)
    o:Hint(L.OPT_GF_EXTRA_NAMES_HINT)
    o:EndAdvanced()
    o:Check("friendlyBoss", L.OPT_GF_FRIENDLY_BOSS)
    o:Dropdown("healerMana", L.OPT_GF_HEALER_MANA, {
        { name = L.GF_HEALER_MANA_NONE, value = "none" }, { name = L.GF_HEALER_MANA_PARTY, value = "party" },
        { name = L.GF_HEALER_MANA_RAID, value = "raid" }, { name = L.GF_HEALER_MANA_BOTH, value = "both" } })

    o:Tab(L.OPT_GF_TAB_BARS)
    o:Check("classColor", L.OPT_UF_CLASS_COLOR)
    o:Advanced()
    o:Check("healthGradient", L.OPT_UF_HEALTH_GRADIENT)
    o:EndAdvanced()
    o:Check("healPrediction", L.OPT_UF_HEAL_PREDICTION)
    o:Advanced()
    o:Check("vertical", L.OPT_UF_VERTICAL)
    o:EndAdvanced()
    o:Check("power", L.OPT_UF_UNIT_POWER)
    o:Advanced()
    o:Slider("powerHeight", L.OPT_UF_POWER_HEIGHT, 0, 12, 1, 36)
    o:Check("powerShowTank", L.OPT_GF_ROLE_TANK, 36)
    o:Check("powerShowHealer", L.OPT_GF_ROLE_HEALER, 36)
    o:Check("powerShowDamager", L.OPT_GF_ROLE_DAMAGER, 36)
    o:Hint(L.OPT_GF_POWER_ROLES)
    o:EndAdvanced()
    o:Check("castbar", L.OPT_UF_UNIT_CASTBAR)
    o:Advanced()
    o:Slider("castbarHeight", L.OPT_UF_CASTBAR_HEIGHT, 2, 10, 1, 36)
    o:EndAdvanced()
    o:Check("portrait", L.OPT_UF_UNIT_PORTRAIT)

    o:Tab(L.OPT_GF_TAB_TEXTS)
    local corners = {}
    for _, corner in ipairs(CORNERS) do corners[#corners + 1] = { name = L["OPT_GF_CORNER_" .. corner], value = corner } end
    o:Advanced()
    o:Dropdown("namePosition", L.OPT_GF_NAME_POSITION, {
        { name = L.OPT_GF_CORNER_TOPLEFT, value = "TOPLEFT" }, { name = L.GF_NAME_CENTER, value = "CENTER" } })
    o:EndAdvanced()
    o:Slider("nameLength", L.OPT_GF_NAME_LENGTH, 0, 20, 1)
    o:Dropdown("healthText", L.OPT_UF_HEALTH_TEXT, Elements.TextModeChoices)
    o:Check("stateText", L.OPT_GF_STATE_TEXT)
    o:Check("roleIcons", L.OPT_GF_ROLES)
    local styles = {}
    for _, style in ipairs(GroupFrames.ROLE_STYLES) do
        styles[#styles + 1] = { name = L["GF_ROLE_STYLE_" .. style:upper()], value = style }
    end
    o:Advanced()
    o:Dropdown("roleIconStyle", L.OPT_GF_ROLE_STYLE, styles, 36)
    o:Slider("roleIconSize", L.OPT_GF_ROLE_SIZE, 8, 24, 1, 36)
    o:Dropdown("roleIconPosition", L.OPT_GF_ROLE_POSITION, corners, 36)
    o:EndAdvanced()
    o:Check("roleShowTank", L.OPT_GF_ROLE_TANK, 36)
    o:Check("roleShowHealer", L.OPT_GF_ROLE_HEALER, 36)
    o:Check("roleShowDamager", L.OPT_GF_ROLE_DAMAGER, 36)
    o:Advanced()
    o:Check("roleHideInCombat", L.OPT_GF_ROLE_HIDE_COMBAT, 36)
    o:EndAdvanced()
    o:Check("leaderIcon", L.OPT_GF_LEADER_ICON)
    o:Check("statusIcons", L.OPT_GF_STATUS_ICONS)
    o:Check("readyIcons", L.OPT_GF_READY_ICONS, 36)
    o:Check("summonIcons", L.OPT_GF_SUMMON_ICONS, 36)
    o:Check("rezIcons", L.OPT_GF_REZ_ICONS, 36)
    o:Advanced()
    o:Slider("statusIconSize", L.OPT_GF_STATUS_SIZE, 10, 32, 1, 36)
    o:EndAdvanced()

    o:Tab(L.OPT_GF_TAB_AURAS)
    o:Check("auras", L.OPT_UF_UNIT_AURAS)
    o:Advanced()
    o:Dropdown("auraPosition", L.OPT_GF_AURA_POSITION, {
        { name = L.GF_AURA_INSIDE, value = "INSIDE" }, { name = L.GF_AURA_ABOVE, value = "ABOVE" },
        { name = L.GF_AURA_BELOW, value = "BELOW" } }, 36)
    o:EndAdvanced()
    o:Slider("auraSize", L.OPT_UF_AURA_SIZE, 10, 32, 1, 36)
    o:Advanced()
    o:Slider("auraMax", L.OPT_GF_AURA_MAX, 1, 16, 1, 36)
    o:Dropdown("auraFilter", L.OPT_AURA_FILTER, NS.AuraFilterChoices, 36)
    o:EndAdvanced()
    o:Check("auraBuffs", L.OPT_GF_AURA_BUFFS, 36)

    o:Tab(L.OPT_GF_TAB_ALERTS)
    o:Check("dispel", L.OPT_GF_DISPEL)
    o:Advanced()
    o:Dropdown("dispelMode", L.OPT_GF_DISPEL_MODE, {
        { name = L.GF_DISPEL_MINE, value = "mine" }, { name = L.GF_DISPEL_ALL, value = "all" } }, 36)
    o:EndAdvanced()
    o:Check("dispelFill", L.OPT_GF_DISPEL_FILL, 36)
    o:Check("dispelGlow", L.OPT_GF_DISPEL_GLOW, 36)
    o:Check("aggro", L.OPT_GF_AGGRO)
    o:Advanced()
    o:Dropdown("aggroStyle", L.OPT_GF_AGGRO_STYLE, {
        { name = L.GF_AGGRO_GLOW, value = "glow" }, { name = L.GF_AGGRO_BORDER, value = "border" } }, 36)
    o:EndAdvanced()
    o:Check("targetHighlight", L.OPT_GF_TARGET_HIGHLIGHT)
    o:Check("mouseoverHighlight", L.OPT_GF_MOUSEOVER_HIGHLIGHT)
    o:Check("range", L.OPT_GF_RANGE)
    o:Advanced()
    o:Slider("rangeAlpha", L.OPT_GF_RANGE_ALPHA, 0.1, 0.9, 0.1, 36, "%.1f")
    o:EndAdvanced()

    o:Tab(L.OPT_GF_SPELL_INDICATORS)
    o:Advanced()
    o.layout:Note(L.NOTE_GF_SPELL_INDICATORS, 20)
    for _, corner in ipairs(CORNERS) do
        o:EditBox("indicators." .. corner, L["OPT_GF_CORNER_" .. corner], 1)
    end
    o:EndAdvanced()
    o:Slider("indicatorSize", L.OPT_GF_INDICATOR_SIZE, 6, 20, 1)
    o:Check("indicatorMine", L.OPT_GF_INDICATOR_MINE)
    o.layout:Button(L.CLICKCAST_PRESET, function()
        if not GroupFrames:ApplyIndicatorPreset() then NS.Print(L.MSG_GF_NO_PRESET) end
    end, 20)
end

--- Aperçu des options : un groupe de cinq et vingt membres de raid, à leur taille, avec couleurs
-- de classe, nom et ressource ; un clic ouvre l'onglet Groupe ou Raid.
GroupFrames.previewHeight = 360
local PREVIEW_MEMBERS = {
    { "Aelys", "PALADIN" }, { "Brann", "WARRIOR" }, { "Cyrene", "PRIEST" }, { "Dorn", "ROGUE" }, { "Elwin", "MAGE" },
    { "Faelan", "DRUID" }, { "Garrok", "SHAMAN" }, { "Hesper", "WARLOCK" }, { "Ilyra", "HUNTER" },
}
local PREVIEW_RAID_SIZE = 20

function GroupFrames:BuildPreview(p)
    local function member(id, index, x, y, width, height, db, scale)
        local who = PREVIEW_MEMBERS[(index - 1) % #PREVIEW_MEMBERS + 1]
        local r, g, b = 0.2, 0.75, 0.2
        if db.classColor then r, g, b = p.ClassColor(who[2]) end
        local power = db.power and db.powerHeight * scale or 0
        local healthHeight = height - (power > 0 and power + 1 or 0)
        p.Edge(id .. ":edge", x, y, width, height, 0, 0, 0, 1)
        p.Bar(id, x, y, width, healthHeight, r, g, b, 1 - (index % 4) * 0.18)
        if power > 0 then p.Bar(id .. ":power", x, y + healthHeight + 1, width, power, 0, 0.44, 0.87, 0.8) end
        local length = tonumber(db.nameLength) or 0
        local name = length > 0 and who[1]:sub(1, length) or who[1]
        p.Text(id .. ":name", x + 3, y + 2, name, math.min(11, healthHeight * 0.4))
    end
    return function()
        local db = p.DB()
        p.Begin()
        local spacing = db.spacing
        local partyWidth = db.horizontal and (5 * db.width + 4 * spacing) or db.width
        local partyHeight = db.horizontal and db.height or (5 * db.height + 4 * spacing)
        local perColumn = math.max(1, db.raidUnitsPerColumn)
        local columns = math.min(math.ceil(PREVIEW_RAID_SIZE / perColumn), math.max(1, db.raidColumns))
        local raidWidth = columns * db.raidWidth + (columns - 1) * spacing
        local raidHeight = math.min(PREVIEW_RAID_SIZE, perColumn) * (db.raidHeight + spacing) - spacing
        -- Groupe au-dessus du raid (colonne étroite).
        local gap = 24
        local scale, originX, originY = p.Fit(math.max(partyWidth, raidWidth), partyHeight + gap + raidHeight, 8)
        for i = 1, 5 do
            local offset = (i - 1) * ((db.horizontal and db.width or db.height) + spacing) * scale
            local x = originX + (db.horizontal and offset or 0)
            local y = originY + (db.horizontal and 0 or offset)
            member("party" .. i, i, x, y, db.width * scale, db.height * scale, db, scale)
        end
        p.Hotspot(p.Region("partyspot", originX, originY, partyWidth * scale, partyHeight * scale), L.UF_UNIT_PARTY)
        local raidTop = originY + (partyHeight + gap) * scale
        for i = 1, math.min(PREVIEW_RAID_SIZE, columns * perColumn) do
            local column, row = math.floor((i - 1) / perColumn), (i - 1) % perColumn
            member("raid" .. i, i + 1, originX + column * (db.raidWidth + spacing) * scale,
                raidTop + row * (db.raidHeight + spacing) * scale, db.raidWidth * scale, db.raidHeight * scale, db, scale)
        end
        p.Hotspot(p.Region("raidspot", originX, raidTop, raidWidth * scale, raidHeight * scale), L.UF_UNIT_RAID)
    end
end

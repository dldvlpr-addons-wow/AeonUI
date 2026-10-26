-- Modules/Reminders.lua
-- Pile de rappels affichée hors combat : buff de classe manquant, durabilité faible,
-- sacs pleins, camouflage oublié. En combat, rien n'est évalué (les auras peuvent y être
-- secrètes, et un rappel de buff en plein combat ne sert à rien) : la pile se cache.
--
-- Les règles sont des données. Un buff se cherche par NOM : en Classic chaque rang a son
-- propre id, et le nom couvre tous les rangs. Une règle ne s'applique que si le joueur
-- connaît au moins un des sorts listés.
local _, NS = ...
local L = NS.L
local Media = NS.Media

local MAX_LINES = 6
local SOUND_THROTTLE = 2

-- kind = "aura"   : satisfaite si un buff porte le nom d'un sort de `spells` ou `accept`
-- kind = "weapon" : satisfaite si l'arme principale est enchantée (poison, arme de chaman)
-- groupOnly : seulement en groupe. Tous ces ids sont des rangs 1 de Classic.
local CLASS_RULES = {
    { key = "mageArmor",    class = "MAGE",    kind = "aura",   spells = { 168, 7302, 6117 } },
    { key = "demonArmor",   class = "WARLOCK", kind = "aura",   spells = { 687, 706 } },
    { key = "innerFire",    class = "PRIEST",  kind = "aura",   spells = { 588 } },
    { key = "markOfTheWild", class = "DRUID",  kind = "aura",   spells = { 1126 }, accept = { 21849 } },
    { key = "aspect",       class = "HUNTER",  kind = "aura",
      spells = { 13165, 13163, 5118, 13159, 20043, 13161 } },
    { key = "paladinAura",  class = "PALADIN", kind = "aura",
      spells = { 465, 7294, 19746, 19876, 19888, 19891, 20218 } },
    { key = "battleShout",  class = "WARRIOR", kind = "aura",   spells = { 6673 }, groupOnly = true },
    -- Les poisons sont des objets, pas des sorts du grimoire : la condition est le passif Poisons.
    { key = "roguePoison",  class = "ROGUE",   kind = "weapon", spells = { 2842 } },
    { key = "shamanWeapon", class = "SHAMAN",  kind = "weapon", spells = { 8017, 8024, 8033, 8232 } },
    -- Optionnelles (option = clé de réglage qui doit être vraie) :
    { key = "shadowform",   class = "PRIEST",  kind = "aura",   spells = { 15473 }, option = "shadowform" },
    { key = "righteousFury", class = "PALADIN", kind = "aura",  spells = { 25780 }, option = "righteousFury" },
}
NS.REMINDER_CLASS_RULES = CLASS_RULES

-- Buffs de groupe, une famille par règle (interrupteur coverageRules[clé]) : membres vivants,
-- connectés et en vue qui n'en ont aucun (version de groupe acceptée, tous rangs par le nom).
-- Seulement si le joueur connaît un des sorts de `spells`. Bénédictions : n'importe laquelle suffit.
local COVERAGE_RULES = {
    { key = "arcaneIntellect", class = "MAGE", spells = { 1459 }, accept = { 23028 } },
    { key = "fortitude", class = "PRIEST", spells = { 1243 }, accept = { 21562 } },
    { key = "divineSpirit", class = "PRIEST", spells = { 14752 }, accept = { 27681 } },
    { key = "wildCoverage", class = "DRUID", spells = { 1126 }, accept = { 21849 } },
    { key = "thorns", class = "DRUID", spells = { 467 } },
    { key = "salvation", class = "PALADIN", spells = { 1038 }, accept = { 25895 } },
    { key = "blessings", class = "PALADIN", spells = { 19740, 19742, 20217, 19977, 20911 },
      accept = { 25782, 25894, 25898, 25890, 25899 } },
}
NS.REMINDER_COVERAGE_RULES = COVERAGE_RULES

local STEALTH_SPELLS = { ROGUE = 1784, DRUID = 5215 }
local CAT_FORM_ID = 1
local TRAVEL_FORM_IDS = { [3] = true, [4] = true, [27] = true, [29] = true }   -- voyage, aquatique, vol

-- Posture/forme attendue, choisie par le joueur (pas de spécialisation en Classic).
-- Guerrier : index de GetShapeshiftForm() (1 combat, 2 défensive, 3 berserker).
-- Druide : GetShapeshiftFormID() (5 ours, 8 ours redoutable, 1 félin, 31 sélénien).
NS.STANCE_CHOICES = {
    WARRIOR = { { key = "battle", index = 1, spell = 2457 }, { key = "defensive", index = 2, spell = 71 },
                { key = "berserker", index = 3, spell = 2458 } },
    DRUID = { { key = "bear", formID = 5, altFormID = 8, spell = 5487 }, { key = "cat", formID = 1, spell = 768 },
              { key = "moonkin", formID = 31, spell = 24858 } },
}

local PET_SPELLS = { HUNTER = 883, WARLOCK = 688 }   -- Appel du familier, Invocation d'un diablotin
local WELL_FED = 19705                               -- « Bien nourri »

local Reminders = NS.Modules:Register("reminders", {
    titleKey = "REM_TITLE",
    descKey = "REM_DESC",
    secure = true,             -- icônes sécurisées ancrées au cadre : tout hors combat
    defaults = {
        enabled = true,
        classBuffs = true,
        skipResting = true,        -- pas de rappel de buff en ville / auberge
        durability = true,
        durabilityThreshold = 20,
        bagsFull = true,
        stealth = false,
        stealthEverywhere = false, -- sinon : donjons et raids seulement
        stealthText = "",          -- vide = texte de la locale
        stealthColor = { r = 1, g = 0.55, b = 0.15 },
        expectedStance = "none",   -- guerrier/druide : clé de NS.STANCE_CHOICES, "none" = pas de rappel
        stanceText = "",           -- vide = texte de la locale ; %s = nom de la posture
        stanceColor = { r = 1, g = 0.55, b = 0.15 },
        repeatSound = 0,           -- secondes entre deux sons tant que camouflage/posture reste affiché, 0 = jamais
        pet = true,
        wellFed = false,
        groupCoverage = true,      -- membres du groupe sans ton buff de groupe
        coverageRules = { arcaneIntellect = true, fortitude = true, divineSpirit = true, wildCoverage = true,
                          thorns = true, salvation = true, blessings = true },   -- par famille, pile et cadres
        customBuffs = "",          -- identifiants de buffs à garder (« 1234, 5678 »), si le sort est connu
        castButtons = true,        -- icône cliquable qui lance le sort manquant, hors combat
        shadowform = false,
        righteousFury = false,
        sound = true,
        soundPreset = "ping",
        soundFile = "",            -- son importé, prioritaire sur le preset
    },
})

local active = false
local frame, lines
local shown = {}          -- [clé] = true pour les rappels actuellement affichés
local DEFAULT_COLOR = { r = 1, g = 0.55, b = 0.15 }
local lastSound = 0
local repeatTicker        -- rejoue le son tant que camouflage ou posture reste affiché
local stealthSince        -- GetTime() de la sortie de combat, pour le délai du camouflage

--------------------------------------------------------------------------------
-- Évaluation
--------------------------------------------------------------------------------

local function IsInGroupNow()
    return (_G.IsInGroup and IsInGroup()) or (_G.GetNumGroupMembers and GetNumGroupMembers() > 0)
end

--- Nom localisé du premier sort connu de la règle, ou nil si aucun n'est connu.
local function KnownSpellName(rule)
    for _, id in ipairs(rule.spells) do
        if NS.KnowsSpell(id) then return NS.GetSpellName(id) end
    end
    return nil
end

local function RuleNames(rule)
    local names = {}
    for _, list in ipairs({ rule.spells, rule.accept or {} }) do
        for _, id in ipairs(list) do
            local name = NS.GetSpellName(id)
            if name then names[name] = true end
        end
    end
    return names
end

--- Rappel de classe à afficher (texte) ou nil. Une réponse inconnue (secrète) vaut « rien ».
function Reminders:CheckClassRule(rule)
    if rule.option and not self.db[rule.option] then return nil end
    local known = KnownSpellName(rule)
    if not known then return nil end
    if rule.groupOnly and not IsInGroupNow() then return nil end
    local satisfied
    if rule.kind == "weapon" then
        satisfied = NS.HasMainHandEnchant()
    else
        satisfied = NS.PlayerHasBuff(RuleNames(rule))
    end
    if satisfied == nil or satisfied then return nil end
    return string.format(L.REM_MISSING, L["REM_RULE_" .. rule.key] or known)
end

local function StealthReminder(db, classFile)
    if not db.stealth then return nil end
    local spell = STEALTH_SPELLS[classFile]
    if not spell or not NS.KnowsSpell(spell) then return nil end
    if not db.stealthEverywhere then
        local _, instanceType = IsInInstance()
        if instanceType ~= "party" and instanceType ~= "raid" then return nil end
    end
    if classFile == "DRUID" and NS.GetShapeshiftFormID() ~= CAT_FORM_ID then return nil end
    if IsStealthed() or (_G.IsMounted and IsMounted()) then return nil end
    -- Laisser 3 s après le combat : le temps de boire, de looter ou de se recamoufler seul.
    if not stealthSince or GetTime() - stealthSince < 3 then return nil end
    return db.stealthText ~= "" and db.stealthText or L.REM_STEALTH
end

--- Gabarit du joueur s'il est valide, sinon celui de la locale.
local function StanceText(db, stanceName)
    if db.stanceText ~= "" then
        local ok, text = pcall(string.format, db.stanceText, stanceName)
        if ok then return text end
    end
    return string.format(L.REM_STANCE, stanceName)
end

local function StanceReminder(db, classFile)
    local choices = NS.STANCE_CHOICES[classFile]
    if not choices or db.expectedStance == "none" then return nil end
    local wanted
    for _, choice in ipairs(choices) do
        if choice.key == db.expectedStance then wanted = choice end
    end
    if not wanted or not NS.KnowsSpell(wanted.spell) then return nil end
    if _G.IsMounted and IsMounted() then return nil end
    if wanted.index then
        local current = GetShapeshiftForm()
        if NS.IsSecret(current) or current == wanted.index then return nil end
    else
        local current = NS.GetShapeshiftFormID()
        if NS.IsSecret(current) or current == wanted.formID or current == wanted.altFormID
            or TRAVEL_FORM_IDS[current] then return nil end
    end
    return StanceText(db, L["STANCE_" .. wanted.key])
end

local function PetReminder(db, classFile)
    local spell = PET_SPELLS[classFile]
    if not db.pet or not spell or not NS.KnowsSpell(spell) then return nil end
    if (_G.IsMounted and IsMounted()) or UnitExists("pet") then return nil end
    return L.REM_PET
end

local function WellFedReminder(db)
    if not db.wellFed then return nil end
    local _, instanceType = IsInInstance()
    if instanceType ~= "party" and instanceType ~= "raid" then return nil end
    local name = NS.GetSpellName(WELL_FED)
    if not name then return nil end
    local has = NS.PlayerHasBuff({ [name] = true })
    if has == nil or has then return nil end
    return L.REM_WELL_FED
end

--- Buffs de groupe que `unit` n'a pas, parmi les familles cochées que le joueur sait lancer :
-- liste de règles, vide si rien ne manque. nil quand la réponse est inconnue : combat, membre
-- absent, mort, hors ligne ou hors de vue, aura secrète. Seule détection, pour la pile et les cadres.
function Reminders.MissingBuffs(unit)
    if NS.InCombat() or not UnitExists(unit) then return nil end
    local dead = UnitIsDeadOrGhost(unit)
    local connected = not _G.UnitIsConnected or UnitIsConnected(unit)
    local visible = not _G.UnitIsVisible or UnitIsVisible(unit)
    if NS.IsSecret(dead) or dead or NS.IsSecret(connected) or not connected
        or NS.IsSecret(visible) or not visible then return nil end
    local _, classFile = UnitClass("player")
    local missing = {}
    for _, rule in ipairs(COVERAGE_RULES) do
        if rule.class == classFile and Reminders.db.coverageRules[rule.key] and KnownSpellName(rule) then
            local has = NS.UnitHasBuff(unit, RuleNames(rule))
            if has == nil then return nil end
            if not has then missing[#missing + 1] = rule end
        end
    end
    return missing
end
NS.MissingBuffs = Reminders.MissingBuffs

--- Membres du groupe, joueur compris. En raid, le jeton raidN du joueur est sauté : ses
-- UNIT_AURA arrivent sous « player ».
local function GroupUnits()
    local units = { "player" }
    local prefix, count = "party", GetNumGroupMembers() - 1
    if IsInRaid() then prefix, count = "raid", GetNumGroupMembers() end
    for i = 1, count do
        local unit = prefix .. i
        local isPlayer = prefix == "raid" and UnitIsUnit(unit, "player")
        if NS.IsSecret(isPlayer) or not isPlayer then units[#units + 1] = unit end
    end
    return units
end

-- Réponse gardée par membre, refaite pour le seul membre dont les auras changent (UNIT_AURA), ou
-- pour tous quand le groupe, le grimoire ou les réglages changent : pas de scrutation. Une
-- réponse inconnue (mort, hors de vue...) est relue à chaque évaluation.
local groupUnits, missingByUnit, staleUnits = {}, {}, {}
local coverageDirty = true

local function CoverageReminders(db, result)
    if not (db.groupCoverage and IsInGroupNow()) then return end
    if coverageDirty then
        coverageDirty, groupUnits = false, GroupUnits()
        wipe(missingByUnit)
        for _, unit in ipairs(groupUnits) do staleUnits[unit] = true end
    end
    for _, unit in ipairs(groupUnits) do
        if staleUnits[unit] or not missingByUnit[unit] then missingByUnit[unit] = Reminders.MissingBuffs(unit) end
    end
    wipe(staleUnits)
    for _, rule in ipairs(COVERAGE_RULES) do
        local missing, first = 0, nil
        for _, unit in ipairs(groupUnits) do
            for _, lacking in ipairs(missingByUnit[unit] or {}) do
                if lacking == rule then missing, first = missing + 1, first or unit end
            end
        end
        if missing > 0 then
            local known = KnownSpellName(rule)
            result[#result + 1] = { key = "coverage:" .. rule.key, spell = known, unit = first,
                                    text = string.format(L.REM_COVERAGE, known, missing) }
        end
    end
end

--- Buffs choisis par identifiant : rappel si le sort est connu et le buff absent.
local function CustomReminders(db, result)
    for id in pairs(NS.ParseSpellList(db.customBuffs)) do
        local name = NS.KnowsSpell(id) and NS.GetSpellName(id)
        if name and NS.PlayerHasBuff({ [name] = true }) == false then
            result[#result + 1] = { key = "custom:" .. id, spell = name, text = string.format(L.REM_MISSING, name) }
        end
    end
end

--- Liste ordonnée des rappels actifs : { { key =, text =, spell =, unit = }, ... } ; `spell` :
-- sort à lancer depuis l'icône cliquable, sur `unit` (le joueur sans unité).
function Reminders:Collect()
    local db = self.db
    local result = {}
    if NS.InCombat() or (_G.UnitAffectingCombat and UnitAffectingCombat("player")) then return result end
    if _G.UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then return result end
    if _G.UnitOnTaxi and UnitOnTaxi("player") then return result end

    local _, classFile = UnitClass("player")
    if db.classBuffs and not (db.skipResting and _G.IsResting and IsResting()) then
        for _, rule in ipairs(CLASS_RULES) do
            if rule.class == classFile then
                local text = self:CheckClassRule(rule)
                if text then
                    result[#result + 1] = { key = rule.key, text = text,
                                            spell = rule.kind == "aura" and KnownSpellName(rule) or nil }
                end
            end
        end
    end

    CoverageReminders(db, result)
    CustomReminders(db, result)

    local stealth = StealthReminder(db, classFile)
    if stealth then result[#result + 1] = { key = "stealth", text = stealth, color = db.stealthColor } end

    local stance = StanceReminder(db, classFile)
    if stance then result[#result + 1] = { key = "stance", text = stance, color = db.stanceColor } end

    local pet = PetReminder(db, classFile)
    if pet then result[#result + 1] = { key = "pet", text = pet } end

    local fed = WellFedReminder(db)
    if fed then result[#result + 1] = { key = "wellFed", text = fed } end

    if db.durability then
        local pct = NS.GetLowestDurability()
        if pct and pct < db.durabilityThreshold then
            result[#result + 1] = { key = "durability", text = string.format(L.REM_DURABILITY, math.floor(pct)) }
        end
    end

    if db.bagsFull then
        local free = 0
        for bag = 0, NS.NUM_BAGS do free = free + NS.GetBagFreeSlots(bag, true) end
        if free == 0 then result[#result + 1] = { key = "bags", text = L.REM_BAGS_FULL } end
    end
    return result
end

--------------------------------------------------------------------------------
-- Affichage
--------------------------------------------------------------------------------

local function Build()
    frame = CreateFrame("Frame", "MuscaUIReminders", UIParent)
    frame:SetSize(320, MAX_LINES * 22)
    frame:SetFrameStrata("MEDIUM")
    frame.hint = Media:CreateText(frame, "OVERLAY")
    frame.hint:SetPoint("BOTTOM", frame, "TOP", 0, 4)
    frame.hint:SetText(L.REM_DRAG_HINT)
    lines = {}
    for i = 1, MAX_LINES do
        local line = Media:CreateText(frame, "OVERLAY", 4, "OUTLINE")
        line:SetPoint("TOP", frame, "TOP", 0, -(i - 1) * 22)
        line.index = i
        lines[i] = line
    end
end

--- Icône qui lance le sort manquant : bouton sécurisé, fille d'UIParent, caché par le moteur dès
-- l'entrée en combat. Créé hors combat, au besoin.
local function CastButton(line)
    if line.castButton then return line.castButton end
    local button = CreateFrame("Button", "MuscaUIReminderCast" .. line.index, UIParent, "SecureActionButtonTemplate")
    button:SetSize(20, 20)
    button:RegisterForClicks("AnyUp", "AnyDown")
    button:SetAttribute("type", "spell")
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetAllPoints(button)
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button:Hide()
    RegisterStateDriver(button, "visibility", "[combat] hide")   -- l'affichage revient à Evaluate
    line.castButton = button
    return button
end

--- Icône cliquable de la ligne : sort et cible, hors combat seulement (bouton sécurisé).
local function SetCastButton(line, entry, enabled)
    if NS.InCombat() then return end
    local spell = enabled and entry and entry.spell
    if not spell then
        local button = line.castButton
        if button then
            button:SetAttribute("spell", nil)
            NS.Glow.Hide(button)
            button:Hide()
        end
        return
    end
    local button = CastButton(line)
    -- Un cadre protégé ne s'ancre pas à une FontString (moteur 12.x) : à gauche du texte, via le cadre.
    button:ClearAllPoints()
    button:SetPoint("RIGHT", frame, "TOP", -(line:GetStringWidth() or 0) / 2 - 6,
        -(line.index - 1) * 22 - (line:GetStringHeight() or 20) / 2)
    button:SetAttribute("spell", spell)
    button:SetAttribute("unit", entry.unit or "player")
    button.icon:SetTexture(NS.GetSpellTexture(spell))
    button:Show()
    NS.Glow.Show(button, "pixel")
end

local function ApplyUnlock(unlocked)
    if not frame then return end
    frame.hint:SetShown(unlocked)   -- le calque de déverrouillage colore déjà le cadre
end

local combatHidden = false

function Reminders:Evaluate()
    if not active then return end
    if NS.InCombat() or (_G.UnitAffectingCombat and UnitAffectingCombat("player")) then
        -- En combat rien n'est évalué : lignes cachées une seule fois, sortie immédiate.
        if not combatHidden then
            combatHidden = true
            for i = 1, MAX_LINES do
                lines[i]:SetText(nil)
                lines[i]:Hide()
            end
            shown = {}
            self:UpdateRepeat()
        end
        return {}
    end
    combatHidden = false
    local list = self:Collect()
    local now, fresh = {}, false
    for i = 1, MAX_LINES do
        local entry = list[i]
        if entry then
            lines[i]:SetText(entry.text)
            local color = entry.color or DEFAULT_COLOR
            lines[i]:SetTextColor(color.r, color.g, color.b)
            lines[i]:Show()
            now[entry.key] = true
            if not shown[entry.key] then fresh = true end
        else
            lines[i]:SetText(nil)
            lines[i]:Hide()
        end
        SetCastButton(lines[i], entry, self.db.castButtons)   -- après le texte : il se cale sur sa largeur
    end
    shown = now
    -- Les icônes sécurisées s'ancrent au cadre, qui devient protégé : en combat, les lignes vides suffisent.
    if not NS.InCombat() then frame:SetShown(#list > 0 or NS:Previewing()) end
    if fresh and self.db.sound and GetTime() - lastSound >= SOUND_THROTTLE then
        lastSound = GetTime()
        NS.PlayPreset(self.db.soundPreset, self.db.soundFile)
    end
    self:UpdateRepeat()
    return list
end

--- Un seul ticker, créé quand camouflage ou posture s'affiche, annulé dès qu'ils disparaissent.
function Reminders:UpdateRepeat()
    local wanted = active and self.db.sound and self.db.repeatSound > 0 and (shown.stealth or shown.stance)
    if repeatTicker and (not wanted or repeatTicker.interval ~= self.db.repeatSound) then
        repeatTicker:Cancel()
        repeatTicker = nil
    end
    if wanted and not repeatTicker then
        repeatTicker = C_Timer.NewTicker(self.db.repeatSound, function()
            if not (shown.stealth or shown.stance) then return Reminders:UpdateRepeat() end
            lastSound = GetTime()
            NS.PlayPreset(Reminders.db.soundPreset, Reminders.db.soundFile)
        end)
        repeatTicker.interval = self.db.repeatSound
    end
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

local events = CreateFrame("Frame")
local evaluatePending = false

--- Rafale d'events (UNIT_AURA, sacs…) : une seule évaluation 0,3 s plus tard.
local function ScheduleEvaluate()
    if evaluatePending then return end
    evaluatePending = true
    C_Timer.After(0.3, function()
        evaluatePending = false
        Reminders:Evaluate()
    end)
end

events:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_REGEN_ENABLED" then
        stealthSince = GetTime()
        -- Réévaluer après le délai du camouflage, sans ticker permanent.
        C_Timer.After(3.1, function() Reminders:Evaluate() end)
    elseif event == "PLAYER_REGEN_DISABLED" then
        stealthSince = nil
    else
        if event == "UNIT_AURA" or event == "UNIT_CONNECTION" then
            -- Auras d'un membre : lui seul est relu ; les autres unités (cible, plaques) n'en sont pas.
            if not (unit == "player" or unit:find("^party%d") or unit:find("^raid%d")) then return end
            staleUnits[unit] = true
        elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" or event == "SPELLS_CHANGED" then
            coverageDirty = true
        end
        return ScheduleEvaluate()
    end
    Reminders:Evaluate()
end)

local EVENTS = {
    "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED",
    "UPDATE_SHAPESHIFT_FORM", "UNIT_INVENTORY_CHANGED", "BAG_UPDATE_DELAYED",
    "UPDATE_INVENTORY_DURABILITY", "ZONE_CHANGED_NEW_AREA", "GROUP_ROSTER_UPDATE",
    "PLAYER_UPDATE_RESTING", "UPDATE_STEALTH", "PLAYER_ALIVE", "PLAYER_UNGHOST",
    "SPELLS_CHANGED", "UNIT_PET", "PLAYER_MOUNT_DISPLAY_CHANGED",
}

function Reminders:OnEnable()
    if not frame then Build() end
    active = true
    stealthSince = GetTime()
    for _, event in ipairs(EVENTS) do NS.RegisterEventSafe(events, event) end
    NS.RegisterEventSafe(events, "UNIT_AURA")
    NS.RegisterEventSafe(events, "UNIT_CONNECTION")
    -- Mover lié au module : coupé, il n'apparaît plus au déverrouillage.
    NS.Movers:Register("reminders", frame, L.MOVER_REMINDERS, "TOP", 0, -140)
    NS.Movers:Load("reminders")
    ApplyUnlock(NS:Previewing())
    shown = {}
    coverageDirty = true
    self:Evaluate()
end

function Reminders:OnDisable()
    active = false
    events:UnregisterAllEvents()
    NS.Movers:Unregister("reminders")
    if frame then
        frame:Hide()
        for _, line in ipairs(lines) do SetCastButton(line, nil, false) end
    end
    shown = {}
    self:UpdateRepeat()
end

function Reminders:OnRefresh()
    coverageDirty = true
    NS:Fire("MISSING_BUFFS_CHANGED")   -- familles cochées : icônes des cadres
    self:Evaluate()
end

function Reminders:GetFrame() return frame, lines end

NS:On("PREVIEW", function(unlocked)
    ApplyUnlock(unlocked)
    coverageDirty = true
    if active then Reminders:Evaluate() end
end)

--------------------------------------------------------------------------------
-- Options
--------------------------------------------------------------------------------

function Reminders:BuildOptions(o)
    o:Title(L.OPT_REM_BUFFS)
    o:Check("classBuffs", L.OPT_REM_CLASS)
    o:Check("skipResting", L.OPT_REM_RESTING, 36)
    o:Check("shadowform", L.OPT_REM_SHADOWFORM, 36)
    o:Check("righteousFury", L.OPT_REM_FURY, 36)
    o:Check("pet", L.OPT_REM_PET)
    o:Check("wellFed", L.OPT_REM_WELL_FED)
    o:Check("groupCoverage", L.OPT_REM_COVERAGE)
    local _, playerClass = UnitClass("player")
    for _, rule in ipairs(COVERAGE_RULES) do
        if rule.class == playerClass then o:Check("coverageRules." .. rule.key, L["REM_RULE_" .. rule.key], 36) end
    end
    o:Advanced()
    o:EditBox("customBuffs", L.OPT_REM_CUSTOM, 1)
    o:EndAdvanced()
    o:Check("castButtons", L.OPT_REM_CAST_BUTTONS)
    local _, classFile = UnitClass("player")
    local choices = NS.STANCE_CHOICES[classFile]
    if choices then
        local list = { { name = L.STANCE_none, value = "none" } }
        for _, choice in ipairs(choices) do list[#list + 1] = { name = L["STANCE_" .. choice.key], value = choice.key } end
        o:Dropdown("expectedStance", L.OPT_REM_STANCE, list)
        o:Advanced()
        o:EditBox("stanceText", L.OPT_REM_STANCE_TEXT, 1, 36)
        o:Color("stanceColor", L.OPT_REM_COLOR, 36)
        o:EndAdvanced()
    end
    o:Check("stealth", L.OPT_REM_STEALTH)
    o:Advanced()
    o:Check("stealthEverywhere", L.OPT_REM_STEALTH_EVERYWHERE, 36)
    o:EditBox("stealthText", L.OPT_REM_STEALTH_TEXT, 1, 36)
    o:Color("stealthColor", L.OPT_REM_COLOR, 36)
    o:EndAdvanced()
    o:Title(L.OPT_REM_GEAR)
    o:Check("durability", L.OPT_REM_DURABILITY)
    o:Advanced()
    o:Slider("durabilityThreshold", L.OPT_REM_DURABILITY_THRESHOLD, 5, 50, 5, 36, "%d %%")
    o:EndAdvanced()
    o:Check("bagsFull", L.OPT_REM_BAGS)
    o:Title(L.OPT_REM_ALERT)
    o:Check("sound", L.OPT_REM_SOUND)
    o:Sound("soundPreset", "soundFile", 36)
    o:Advanced()
    o:Slider("repeatSound", L.OPT_REM_REPEAT, 0, 30, 1, 36, "%d s")
    o:EndAdvanced()
    o:Button(L.OPT_UNLOCK, function() NS:SetUnlocked(not NS.unlocked) end)
end

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

--- Liste ordonnée des rappels actifs : { { key =, text = }, ... }.
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
                if text then result[#result + 1] = { key = rule.key, text = text } end
            end
        end
    end

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
        for bag = 0, NS.NUM_BAGS do free = free + NS.GetBagFreeSlots(bag) end
        if free == 0 then result[#result + 1] = { key = "bags", text = L.REM_BAGS_FULL } end
    end
    return result
end

--------------------------------------------------------------------------------
-- Affichage
--------------------------------------------------------------------------------

local function Build()
    frame = CreateFrame("Frame", "AeonUIReminders", UIParent)
    frame:SetSize(320, MAX_LINES * 22)
    frame:SetFrameStrata("MEDIUM")
    frame.hint = Media:CreateText(frame, "OVERLAY")
    frame.hint:SetPoint("BOTTOM", frame, "TOP", 0, 4)
    frame.hint:SetText(L.REM_DRAG_HINT)
    lines = {}
    for i = 1, MAX_LINES do
        local line = Media:CreateText(frame, "OVERLAY", 4, "OUTLINE")
        line:SetPoint("TOP", frame, "TOP", 0, -(i - 1) * 22)
        lines[i] = line
    end
end

local function ApplyUnlock(unlocked)
    if not frame then return end
    frame.hint:SetShown(unlocked)   -- le calque de déverrouillage colore déjà le cadre
end

function Reminders:Evaluate()
    if not active then return end
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
    end
    shown = now
    frame:SetShown(#list > 0 or NS.unlocked)
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
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" then
        stealthSince = GetTime()
        -- Réévaluer après le délai du camouflage, sans ticker permanent.
        C_Timer.After(3.1, function() Reminders:Evaluate() end)
    elseif event == "PLAYER_REGEN_DISABLED" then
        stealthSince = nil
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
    NS.RegisterEventSafe(events, "UNIT_AURA", "player")
    -- Mover lié au module : coupé, il n'apparaît plus au déverrouillage.
    NS.Movers:Register("reminders", frame, L.MOVER_REMINDERS, "TOP", 0, -140)
    NS.Movers:Load("reminders")
    ApplyUnlock(NS.unlocked)
    shown = {}
    self:Evaluate()
end

function Reminders:OnDisable()
    active = false
    events:UnregisterAllEvents()
    NS.Movers:Unregister("reminders")
    if frame then frame:Hide() end
    shown = {}
    self:UpdateRepeat()
end

function Reminders:OnRefresh()
    self:Evaluate()
end

function Reminders:GetFrame() return frame, lines end

NS:On("UNLOCK", function(unlocked)
    ApplyUnlock(unlocked)
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
    local _, classFile = UnitClass("player")
    local choices = NS.STANCE_CHOICES[classFile]
    if choices then
        local list = { { name = L.STANCE_none, value = "none" } }
        for _, choice in ipairs(choices) do list[#list + 1] = { name = L["STANCE_" .. choice.key], value = choice.key } end
        o:Dropdown("expectedStance", L.OPT_REM_STANCE, list)
        o:EditBox("stanceText", L.OPT_REM_STANCE_TEXT, 1, 36)
        o:Color("stanceColor", L.OPT_REM_COLOR, 36)
    end
    o:Check("stealth", L.OPT_REM_STEALTH)
    o:Check("stealthEverywhere", L.OPT_REM_STEALTH_EVERYWHERE, 36)
    o:EditBox("stealthText", L.OPT_REM_STEALTH_TEXT, 1, 36)
    o:Color("stealthColor", L.OPT_REM_COLOR, 36)
    o:Title(L.OPT_REM_GEAR)
    o:Check("durability", L.OPT_REM_DURABILITY)
    o:Slider("durabilityThreshold", L.OPT_REM_DURABILITY_THRESHOLD, 5, 50, 5, 36, "%d %%")
    o:Check("bagsFull", L.OPT_REM_BAGS)
    o:Title(L.OPT_REM_ALERT)
    o:Check("sound", L.OPT_REM_SOUND)
    o:Sound("soundPreset", "soundFile", 36)
    o:Slider("repeatSound", L.OPT_REM_REPEAT, 0, 30, 1, 36, "%d s")
    o:Button(L.OPT_UNLOCK, function() NS:SetUnlocked(not NS.unlocked) end)
end

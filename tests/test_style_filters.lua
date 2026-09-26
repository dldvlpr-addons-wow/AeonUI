-- tests/test_style_filters.lua : étape 13, filtres de style des plaques de nom.
local T = ...
local NS, test, eq, truthy, reset = T.NS, T.test, T.eq, T.truthy, T.reset
local NPF = NS.Modules:Get("nameplateframes")

local function Enable() NS.Modules:SetEnabled("nameplateframes", true) end
local function Disable()
    NS.Modules:SetEnabled("nameplateframes", false)
    Mock.namePlates = {}
end
local function Enemy(token, fields)
    local unit = { name = "Loup affamé", health = 300, healthMax = 400, level = 12, hostile = true }
    for k, v in pairs(fields or {}) do unit[k] = v end
    Mock.units[token] = unit
    Mock.AddNamePlate(token)
    return NPF:GetFrame(token)
end
local function Rule(i, fields)
    local rule = NPF.db.styleRules["rule" .. i]
    for k, v in pairs(fields) do rule[k] = v end
    return rule
end
local function ResetRules()
    for i = 1, 5 do
        Rule(i, { enabled = false, target = "any", casting = "any", combat = "any", reaction = "any",
                  classification = "any", quest = false, healthBelow = 0, names = "",
                  color = false, glow = false, scale = 1, alpha = 1, hide = false })
    end
end

test("style : règles coupées par défaut, cinq emplacements", function()
    reset()
    for i = 1, 5 do eq(NPF.db.styleRules["rule" .. i].enabled, false) end
end)

test("style : règles exportées avec le profil (clés chaînes)", function()
    reset()
    ResetRules()
    Rule(2, { enabled = true, names = "Loup" })
    local copy = NS.Database.Deserialize(NS.Database.Serialize(NS.db))
    truthy(copy.modules.nameplateframes.styleRules.rule2.enabled == true, "règle 2 exportée")
    eq(copy.modules.nameplateframes.styleRules.rule2.names, "Loup")
    ResetRules()
end)

test("style : pas d'icône de combat sur la plaque, réaction secrète, nom accentué, échelle bornée", function()
    reset()
    ResetRules()
    Enable()
    local frame = Enemy("nameplate1", { name = "Écorcheur", combat = true })
    Mock.FireEvent("UNIT_FLAGS", "nameplate1")
    eq(frame.combat:IsShown(), false, "UNIT_FLAGS : pas d'indicateur de combat")
    Rule(1, { enabled = true, names = "écorcheur", scale = 0 })
    NS.Modules:Refresh("nameplateframes")
    eq(frame.scale, 0.5, "capitale accentuée reconnue, échelle 0 bornée à 0,5")
    Rule(1, { names = "", scale = 1, reaction = "hostile", hide = true })
    NS.Modules:Refresh("nameplateframes")
    eq(frame:GetAlpha(), 0, "hostile lisible : masquée")
    local canAttack = _G.UnitCanAttack
    local secret = Mock.SetSecret("hostile?")
    _G.UnitCanAttack = function() return secret end
    NS.Modules:Refresh("nameplateframes")
    truthy(frame:GetAlpha() > 0, "réaction secrète : la règle échoue")
    _G.UnitCanAttack = canAttack
    ResetRules()
    Disable()
end)

test("style : incantation colore et allume la lueur, puis tout revient", function()
    reset()
    ResetRules()
    Enable()
    local frame = Enemy("nameplate1")
    Rule(1, { enabled = true, casting = "yes", color = true, glow = true, colorValue = { r = 0.1, g = 0.2, b = 0.9 } })
    NS.Modules:Refresh("nameplateframes")
    eq(frame.styleGlow:IsShown(), false, "n'incante pas")
    Mock.units.nameplate1.casting = { name = "Hurlement", startTime = 0, endTime = 1000 }
    Mock.FireEvent("UNIT_SPELLCAST_START", "nameplate1")
    eq(frame.health.barColor[3], 0.9, "barre colorée")
    truthy(frame.styleGlow:IsShown(), "lueur")
    Mock.units.nameplate1.casting = nil
    Mock.FireEvent("UNIT_SPELLCAST_STOP", "nameplate1")
    eq(frame.styleGlow:IsShown(), false, "fin d'incantation : lueur éteinte")
    truthy(frame.health.barColor[3] ~= 0.9, "couleur rendue")
    Mock.units.nameplate1.casting = Mock.SetSecret("sort?")
    Mock.FireEvent("UNIT_SPELLCAST_START", "nameplate1")
    truthy(frame.styleGlow:IsShown(), "nom de sort secret : une incantation existe")
    Mock.units.nameplate1.casting = nil
    ResetRules()
    Disable()
end)

test("style : vie basse agrandit, nom masque, ordre de priorité", function()
    reset()
    ResetRules()
    Enable()
    Rule(1, { enabled = true, names = "totem, affamé", hide = true })
    Rule(2, { enabled = true, healthBelow = 50, scale = 1.5 })
    local wolf = Enemy("nameplate1", { health = 100 })
    eq(wolf:GetAlpha(), 0, "nom listé : masqué (règle 1 prioritaire)")
    eq(wolf.scale, 1)
    local bear = Enemy("nameplate2", { name = "Ours", health = 100 })
    eq(bear.scale, 1.5, "vie sous 50 % : agrandi")
    Mock.units.nameplate2.health = 390
    Mock.FireEvent("UNIT_HEALTH", "nameplate2")
    eq(bear.scale, 1, "vie remontée : taille normale")
    Mock.units.nameplate2.health = Mock.SetSecret(10)
    Mock.FireEvent("UNIT_HEALTH", "nameplate2")
    eq(bear.scale, 1, "vie secrète : règle illisible, échoue")
    Mock.units.nameplate1.name = Mock.SetSecret("Loup?")
    Mock.FireEvent("UNIT_NAME_UPDATE", "nameplate1")
    truthy(wolf:GetAlpha() > 0, "nom secret : règle échoue, plaque rendue")
    ResetRules()
    Disable()
end)

test("style : cible, réaction, combat, classification, quête", function()
    reset()
    ResetRules()
    Enable()
    local frame = Enemy("nameplate1", { combat = true })
    local rule = Rule(1, { enabled = true, target = "no", reaction = "hostile", combat = "yes", alpha = 0.3 })
    NS.Modules:Refresh("nameplateframes")
    eq(frame:GetAlpha(), 0.3, "hostile en combat, pas ciblé")
    Mock.units.target = Mock.units.nameplate1
    Mock.FireEvent("PLAYER_TARGET_CHANGED")
    eq(frame:GetAlpha(), 1, "ciblé : règle ne correspond plus")
    Mock.units.target = nil
    Rule(1, { target = "any", combat = "any", classification = "elite" })
    local classes = { nameplate1 = "rareelite" }
    _G.UnitClassification = function(unit) return classes[unit] end
    NS.Modules:Refresh("nameplateframes")
    eq(frame:GetAlpha(), 0.3, "rare élite compte comme élite")
    classes.nameplate1 = "normal"
    Mock.FireEvent("UNIT_CLASSIFICATION_CHANGED", "nameplate1")
    truthy(frame:GetAlpha() > 0.3, "normal : non")
    Rule(1, { classification = "any", quest = true })
    _G.C_QuestLog = _G.C_QuestLog or {}
    local related = true
    C_QuestLog.UnitIsRelatedToActiveQuest = function() return related end
    Mock.FireEvent("QUEST_LOG_UPDATE")
    eq(frame:GetAlpha(), 0.3, "unité de quête")
    related = Mock.SetSecret("quête?")
    Mock.FireEvent("QUEST_LOG_UPDATE")
    truthy(frame:GetAlpha() > 0.3, "réponse secrète : non")
    C_QuestLog.UnitIsRelatedToActiveQuest, _G.UnitClassification = nil, nil
    rule.enabled = false
    ResetRules()
    Disable()
end)

test("style : options construites avec couleur imbriquée", function()
    reset()
    Enable()
    NS.Options:BuildMain()
    truthy(NPF.db.styleRules.rule1.colorValue.r, "couleur lisible")
    Disable()
end)

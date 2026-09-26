-- tests/test_text_filters.lua : étape 11, formats de texte à jetons et filtres d'auras partagés.
local T = ...
local NS, L, test, eq, truthy, reset = T.NS, T.L, T.test, T.eq, T.truthy, T.reset
local Elements = NS.UnitFrameElements

local function Target(fields)
    local unit = { name = "Cible", health = 1500, healthMax = 3000, power = 20, powerMax = 100, hostile = true }
    for k, v in pairs(fields or {}) do unit[k] = v end
    Mock.units.target = unit
    return unit
end

--------------------------------------------------------------------------------
-- Formats de texte
--------------------------------------------------------------------------------

test("textes : jetons compilés, texte libre gardé, % échappé, jeton inconnu laissé tel quel", function()
    reset()
    Target()
    local entry = Elements.CompileFormat("[cur] / [max] 100% [foo]")
    eq(entry.pattern, "%s / %s 100%% [foo]")
    eq(#entry.tokens, 2)
    eq(Elements.RenderText("target", "health", "[cur] / [max] ([perc])"), "1.5k / 3.0k (50%)")
    eq(Elements.RenderText("target", "power", "[cur]/[max]"), "20/100")
    eq(Elements.RenderText("target", "health", "texte seul"), "texte seul")
    eq(Elements.RenderText("target", "health", ""), "")
    eq(Elements.RenderText("target", "health", "[missing]"), "1.5k")
    Mock.units.target.health = 3000
    eq(Elements.RenderText("target", "health", "[missing]"), "", "vie pleine : rien")
end)

test("textes : préréglages, format du cadre prioritaire", function()
    eq(Elements.TextFormat(nil, "curmax"), "[cur] / [max]")
    eq(Elements.TextFormat("", "percent"), "[perc]")
    eq(Elements.TextFormat("[perc]", "current"), "[perc]", "format personnalisé prime")
    eq(Elements.TextFormat(nil, "inconnu"), "")
    for _, choice in ipairs(Elements.TextModeChoices()) do truthy(choice.name, "libellé " .. choice.value) end
end)

test("textes : statut mort, fantôme, déconnecté ; secret = rien", function()
    reset()
    Target({ dead = true })
    eq(Elements.RenderText("target", "health", "[status]"), L.TEXT_STATUS_DEAD)
    Mock.units.target.dead = Mock.SetSecret("mort?")
    eq(Elements.RenderText("target", "health", "[status]"), "")
    _G.UnitIsConnected = function() return false end
    eq(Elements.RenderText("target", "health", "[status]"), L.TEXT_STATUS_OFFLINE)
    _G.UnitIsConnected = nil
end)

test("textes : pourcentage et manque secrets passent par le moteur sans être lus", function()
    reset()
    Target({ health = Mock.SetSecret(1234), healthMax = Mock.SetSecret(5000) })
    _G.CurveConstants = { ScaleTo100 = "scale" }
    local args
    _G.UnitHealthPercent = function(...) args = { ... } return 42.4 end
    eq(Elements.RenderText("target", "health", "[perc]"), "42%")
    eq(args[2], true); eq(args[3], "scale")
    _G.UnitHealthMissing = function() return 7 end
    local truncated
    C_StringUtil.TruncateWhenZero = function(v) truncated = v return "t" .. v end
    eq(Elements.RenderText("target", "health", "[missing]"), "t7", "TruncateWhenZero reçoit la valeur")
    eq(truncated, 7)
    _G.CurveConstants, _G.UnitHealthPercent, _G.UnitHealthMissing, C_StringUtil.TruncateWhenZero = nil, nil, nil, nil
end)

test("textes : la barre de vie du cadre suit le format du cadre", function()
    reset()
    Target()
    local db = NS.db.modules.unitframes
    db.units.target.healthFormat = "[cur] - [perc]"
    NS.Modules:SetEnabled("unitframes", true)
    local frame = NS.Modules:Get("unitframes").frames.target
    Elements.UpdateHealth(frame)
    eq(frame.health.text:GetText(), "1.5k - 50%")
    db.units.target.healthFormat = ""
    Elements.UpdateHealth(frame)
    eq(frame.health.text:GetText(), "1.5k", "vide : préréglage « current »")
    NS.Modules:SetEnabled("unitframes", false)
end)

--------------------------------------------------------------------------------
-- Filtres d'auras
--------------------------------------------------------------------------------

test("auras : filtres tout, miens, boss, dissipables, importants", function()
    reset()
    NS.db.auraLists.whitelist, NS.db.auraLists.blacklist = "", ""
    local P = NS.AuraPasses
    eq(P("all", 1, nil, false, false), true)
    eq(P("mine", 1, nil, false, true), true)
    eq(P("mine", 1, nil, false, false), false)
    eq(P("boss", 1, nil, true, false), true)
    eq(P("boss", 1, nil, false, false), false)
    Mock.units.player.class = "MAGE"
    eq(P("dispellable", 1, "Curse", false, false), true)
    eq(P("dispellable", 1, "Magic", false, false), false)
    eq(P("important", 1, "Magic", true, false), true, "boss")
    eq(P("important", 1, nil, false, false), false)
    Mock.units.player.class = "WARLOCK"
    eq(P("dispellable", 1, "Magic", false, false), true, "chasseur corrompu")
end)

test("auras : champ secret gardé, listes blanche et noire du profil", function()
    reset()
    local P = NS.AuraPasses
    eq(P("mine", 1, nil, false, Mock.SetSecret("à moi?")), true)
    eq(P("dispellable", 1, Mock.SetSecret("Poison?"), false, false), true)
    Mock.units.player.class = "MAGE"
    eq(P("dispellable", 1, "Magic", Mock.SetSecret("boss?"), false), false, "boss secret sans effet sur « dissipables »")
    eq(P("boss", 1, nil, Mock.SetSecret("boss2?"), false), true)
    NS.db.auraLists.whitelist, NS.db.auraLists.blacklist = "111, 222", "333"
    eq(P("mine", 222, nil, false, false), true, "liste blanche")
    eq(P("all", 333, nil, false, true), false, "liste noire")
    eq(P("all", Mock.SetSecret(333), nil, false, true), true, "identifiant secret : listes ignorées")
    NS.db.auraLists.whitelist, NS.db.auraLists.blacklist = "", ""
    eq(NS.ParseSpellList("12 ;x34")[34], true)
    eq(NS.Modules:Get("groupframes").DISPEL_BY_CLASS, NS.DISPEL_BY_CLASS, "table partagée")
end)

test("auras : GetDebuff rend l'identifiant et l'origine ; cadre d'unité filtré", function()
    reset()
    Target()
    Mock.debuffs.target = {
        { icon = "a", spellId = 1, isFromPlayerOrPlayerPet = false },
        { icon = "b", spellId = 2, isFromPlayerOrPlayerPet = true },
    }
    local _, _, _, _, _, _, spellId, isMine = NS.GetDebuff("target", 2)
    eq(spellId, 2); eq(isMine, true)
    local db = NS.db.modules.unitframes
    db.units.target.auraFilter = "mine"
    NS.Modules:SetEnabled("unitframes", true)
    local frame = NS.Modules:Get("unitframes").frames.target
    Elements.UpdateAuras(frame)
    eq(frame.auras.native, false, "filtre « miens » : repli maison sans conteneur moteur dans le mock")
    eq(frame.auras.buttons[1].icon.texture, "b")
    truthy(not frame.auras.buttons[2]:IsShown())
    db.units.target.auraFilter = "all"
    NS.Modules:SetEnabled("unitframes", false)
    Mock.debuffs.target = nil
end)

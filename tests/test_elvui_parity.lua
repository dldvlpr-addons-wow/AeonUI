-- tests/test_elvui_parity.lua : étape 9, parité ElvUI (infobulles, chiffres de recharge, barres au
-- survol et mode raccourcis, cible du focus et boss, fondu hors combat, écran d'absence).
local T = ...
local NS, L, test, eq, truthy, reset = T.NS, T.L, T.test, T.eq, T.truthy, T.reset

local function HasLine(tooltip, text)
    for _, line in ipairs(tooltip.lines or {}) do if line == text then return true end end
    return false
end

--------------------------------------------------------------------------------
-- Infobulles
--------------------------------------------------------------------------------

test("infobulles : rang de guilde, cible « vous », barre de vie masquée", function()
    reset()
    local db = NS.db.modules.skin
    Mock.units.mouseover = { name = "Thrall", class = "SHAMAN", isPlayer = true }
    Mock.units.mouseovertarget = Mock.units.player
    Mock.guilds.mouseover = { "Horde", "Chef" }
    GameTooltipStatusBar:Show()
    db.hideHealthBar = true
    Mock.ShowUnitTooltip("mouseover")
    truthy(GameTooltipTextLeft2:GetText():find("[Chef]", 1, true), "rang après la guilde")
    truthy(HasLine(GameTooltip, string.format(L.TOOLTIP_TARGET, L.TOOLTIP_TARGET_YOU)), "cible = vous")
    eq(GameTooltipStatusBar:IsShown(), false, "barre de vie masquée")
    db.hideHealthBar = false
    db.tooltipTarget, db.guildRank = false, false
    Mock.ShowUnitTooltip("mouseover")
    eq(GameTooltipTextLeft2:GetText(), "Horde", "rang coupé")
    eq(HasLine(GameTooltip, string.format(L.TOOLTIP_TARGET, L.TOOLTIP_TARGET_YOU)), false, "cible coupée")
    db.tooltipTarget, db.guildRank = true, true
    Mock.guilds = {}
end)

test("infobulles : valeurs secrètes, lignes omises sans erreur", function()
    reset()
    Mock.units.mouseover = { name = "Thrall", class = "SHAMAN", isPlayer = true }
    Mock.units.mouseovertarget = { name = Mock.SetSecret("Secret"), isPlayer = true }
    Mock.guilds.mouseover = { "Horde", Mock.SetSecret("Officier") }
    Mock.ShowUnitTooltip("mouseover")
    eq(GameTooltipTextLeft2:GetText(), "Horde", "rang secret : ligne intacte")
    eq(#(GameTooltip.lines or {}), 0, "nom de cible secret : pas de ligne")
    Mock.guilds = {}
end)

test("infobulles : identifiants de sort et d'objet, au curseur", function()
    reset()
    local db = NS.db.modules.skin
    Mock.ShowDataTooltip(Enum.TooltipDataType.Spell, { id = 133 })
    eq(HasLine(GameTooltip, string.format(L.TOOLTIP_ID, "133")), false, "coupé par défaut")
    db.tooltipIDs = true
    Mock.ShowDataTooltip(Enum.TooltipDataType.Item, { id = 6948 })
    truthy(HasLine(GameTooltip, string.format(L.TOOLTIP_ID, "6948")), "ID d'objet")
    Mock.ShowDataTooltip(Enum.TooltipDataType.Spell, { id = Mock.SetSecret(9999) })
    eq(#GameTooltip.lines, 0, "ID secret : rien")
    db.tooltipIDs = false
    GameTooltip_SetDefaultAnchor(GameTooltip, UIParent)
    eq(GameTooltip.anchor, "ANCHOR_NONE")
    db.anchorCursor = true
    GameTooltip_SetDefaultAnchor(GameTooltip, UIParent)
    eq(GameTooltip.anchor, "ANCHOR_CURSOR")
    db.anchorCursor = false
end)

--------------------------------------------------------------------------------
-- Chiffres de recharge
--------------------------------------------------------------------------------

test("interface : chiffres de recharge par la CVar native, rendue à la coupure", function()
    reset()
    NS.db.modules.interface.cooldownNumbers = true
    NS.Modules:Refresh("interface")
    eq(Mock.cvars.countdownForCooldowns, "1")
    NS.db.modules.interface.cooldownNumbers = false
    NS.Modules:Refresh("interface")
    eq(Mock.cvars.countdownForCooldowns, "0")
end)

--------------------------------------------------------------------------------
-- Barres d'action
--------------------------------------------------------------------------------

local AB = NS.Modules:Get("actionbars")

test("barres : visible au survol seulement, textes de raccourci et de macro masquables", function()
    reset()
    Mock.mouseOver, Mock.cursorItem = nil, nil
    local db = NS.db.modules.actionbars
    NS.Modules:SetEnabled("actionbars", true)
    local bar2 = AB:GetBar(2)
    eq(bar2:GetAlpha(), 1)
    db.bars[2].mouseover = true
    NS.Modules:Refresh("actionbars")
    eq(bar2:GetAlpha(), 0, "invisible sans survol")
    eq(AB:GetBar(1):GetAlpha(), 1, "barre 1 non concernée")
    Mock.SetMouseOver(bar2)
    AB:UpdateFade()
    eq(bar2:GetAlpha(), 1, "survolée")
    Mock.SetMouseOver(nil)
    Mock.cursorItem = "spell"
    AB:UpdateFade()
    eq(bar2:GetAlpha(), 1, "sort tenu au curseur")
    Mock.cursorItem = nil
    Mock.SetCombat(true)
    Mock.SetMouseOver(bar2)
    AB:UpdateFade()
    eq(bar2:GetAlpha(), 1, "en combat aussi")
    Mock.SetCombat(false)
    Mock.SetMouseOver(nil)
    db.hotkeys, db.macroNames = false, false
    NS.Modules:Refresh("actionbars")
    eq(AB:GetBar(1).buttons[1].HotKey:GetAlpha(), 0)
    eq(AB:GetBar(1).buttons[1].Name:GetAlpha(), 0)
    db.hotkeys, db.macroNames, db.bars[2].mouseover = true, true, false
    NS.Modules:SetEnabled("actionbars", false)
end)

test("barres : mode raccourcis lie, efface, se ferme en combat", function()
    reset()
    Mock.mouseOver, Mock.shift, Mock.saved = nil, false, 0
    AB:SetKeyBindMode(true)
    eq(AB.binding, nil, "module coupé : refusé")
    NS.Modules:SetEnabled("actionbars", true)
    AB:SetKeyBindMode(true)
    truthy(AB.binding and AeonUI_KeyBinder:IsShown(), "mode ouvert")
    local bar1 = AB:GetBar(1)
    Mock.SetMouseOver(bar1.buttons[3])
    Mock.shift = true
    AB:BindKey("LSHIFT")
    eq(Mock.bindings.ACTIONBUTTON3, nil, "modificateur seul ignoré")
    AB:BindKey("F")
    Mock.shift = false
    eq(Mock.bindings.ACTIONBUTTON3, "SHIFT-F")
    eq(Mock.saved, 1, "raccourcis sauvegardés")
    Mock.FireEvent("UPDATE_BINDINGS")
    eq(Mock.overrideBindings[bar1]["SHIFT-F"], "AeonUI_Bar1Button3", "relayé à notre bouton")
    AB:BindKey("ESCAPE")
    eq(Mock.bindings.ACTIONBUTTON3, nil, "Échap sur le bouton efface")
    Mock.SetMouseOver(nil)
    AB:BindKey("ESCAPE")
    eq(AB.binding, nil, "Échap ailleurs ferme")
    AB:SetKeyBindMode(true)
    Mock.SetCombat(true)
    eq(AB.binding, nil, "combat : fermé")
    AB:SetKeyBindMode(true)
    eq(AB.binding, nil, "combat : refusé")
    Mock.SetCombat(false)
    NS.Modules:SetEnabled("actionbars", false)
end)

--------------------------------------------------------------------------------
-- Cadres d'unité
--------------------------------------------------------------------------------

local UF = NS.Modules:Get("unitframes")

test("unitframes : boss 1 à 5 sur un réglage commun, cible du focus en option", function()
    reset()
    NS.Modules:SetEnabled("unitframes", true)
    for i = 1, 5 do
        local frame = UF:GetFrame("boss" .. i)
        truthy(frame, "boss" .. i)
        eq(frame.cfg, NS.db.modules.unitframes.units.boss, "réglage partagé")
        truthy(NS.Movers:Anchor("uf_boss" .. i), "mover boss" .. i)
    end
    eq(UF:GetFrame("boss1"):IsShown(), false, "pas de boss")
    Mock.units.boss1 = { name = "Ragnaros", health = 100, healthMax = 100 }
    Mock.FireEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
    truthy(UF:GetFrame("boss1"):IsShown(), "boss engagé")
    eq(UF:GetFrame("boss2"):IsShown(), false)
    eq(UF:GetFrame("focustarget"), nil, "cible du focus coupée par défaut")
    NS.db.modules.unitframes.units.focustarget.enabled = true
    NS.Modules:Refresh("unitframes")
    truthy(UF:GetFrame("focustarget"), "cible du focus créée")
    NS.db.modules.unitframes.units.focustarget.enabled = false
    NS.Modules:SetEnabled("unitframes", false)
end)

test("unitframes : fondu hors combat, plein dès qu'il se passe quelque chose", function()
    reset()
    Mock.mouseOver = nil
    local db = NS.db.modules.unitframes
    db.units.player.fader = true
    NS.Modules:SetEnabled("unitframes", true)
    local player = UF:GetFrame("player")
    eq(player:GetAlpha(), db.fadeAlpha, "repos : estompé")
    eq(UF:GetFrame("target") and UF:GetFrame("target"):GetAlpha() or 1, 1, "cible sans fondu")
    Mock.SetCombat(true)
    UF:UpdateFade()
    eq(player:GetAlpha(), 1, "combat")
    Mock.SetCombat(false)
    Mock.units.player.health = 50
    UF:UpdateFade()
    eq(player:GetAlpha(), 1, "blessé")
    Mock.units.player.health = Mock.SetSecret(77)
    UF:UpdateFade()
    eq(player:GetAlpha(), 1, "santé secrète : plein")
    Mock.units.player.health = 100
    Mock.SetMouseOver(player)
    UF:UpdateFade()
    eq(player:GetAlpha(), 1, "survolé")
    Mock.SetMouseOver(nil)
    Mock.units.target = { name = "Loup", health = 10, healthMax = 10 }
    UF:UpdateFade()
    eq(player:GetAlpha(), 1, "une cible")
    Mock.units.target = nil
    UF:UpdateFade()
    eq(player:GetAlpha(), db.fadeAlpha, "de nouveau au repos")
    db.units.player.fader = false
    NS.Modules:Refresh("unitframes")
    eq(player:GetAlpha(), 1, "option coupée : plein")
    NS.Modules:SetEnabled("unitframes", false)
end)

--------------------------------------------------------------------------------
-- Écran d'absence
--------------------------------------------------------------------------------

local AFK = NS.Modules:Get("afk")

test("absence : interface retirée, caméra qui tourne, retour au combat", function()
    reset()
    NS.Modules:SetEnabled("afk", true)
    Mock.afk = true
    Mock.FireEvent("PLAYER_FLAGS_CHANGED", "player")
    truthy(AFK:IsShown(), "écran affiché")
    eq(UIParent:IsShown(), false, "interface retirée")
    truthy(Mock.cameraSpin, "caméra qui tourne")
    eq(AeonUI_AFK.name:GetText(), "Testeur")
    Mock.Advance(66)
    truthy(AeonUI_AFK.timer:GetText():match("^01:0[56]$"), "minuteur")
    Mock.SetCombat(true)
    eq(AFK:IsShown(), false, "combat : retour")
    truthy(UIParent:IsShown())
    eq(Mock.cameraSpin, nil)
    Mock.FireEvent("PLAYER_FLAGS_CHANGED", "player")
    eq(AFK:IsShown(), false, "jamais en combat")
    Mock.SetCombat(false)
    Mock.FireEvent("PLAYER_FLAGS_CHANGED", "player")
    truthy(AFK:IsShown())
    Mock.afk = false
    Mock.FireEvent("PLAYER_FLAGS_CHANGED", "player")
    eq(AFK:IsShown(), false, "retour du joueur")
    truthy(UIParent:IsShown())
end)

test("absence : ElvUI chargé, le module cède", function()
    reset()
    NS.Modules:SetEnabled("afk", false)
    Mock.loadedAddons.ElvUI = true
    NS.Modules:SetEnabled("afk", true)
    eq(AFK.enabled, false, "cédé")
    Mock.afk = true
    Mock.FireEvent("PLAYER_FLAGS_CHANGED", "player")
    eq(AFK:IsShown(), false)
    Mock.afk = false
    Mock.loadedAddons.ElvUI = nil
    NS.Modules:SetEnabled("afk", true)
    truthy(AFK.enabled)
end)

-- tests/test_unitframe_extensions.lua : échelle, auras séparées, style d'aura, annulation, combo de la cible, barre d'incantation.
local T = ...
local NS, test, eq, truthy, reset = T.NS, T.test, T.eq, T.truthy, T.reset
local Elements = NS.UnitFrameElements
local UF = NS.Modules:Get("unitframes")

local function Enable() NS.Modules:SetEnabled("unitframes", true) end
local function Disable() NS.Modules:SetEnabled("unitframes", false) end
local function Frame(unit) return UF:GetFrame(unit) end
local function Target()
    Mock.units.target = { name = "Cible", health = 500, healthMax = 1000, power = 20, powerMax = 100, level = 30, hostile = true }
    Mock.RefreshUnitWatch()
    return Mock.units.target
end

test("unitframes : échelle du cadre multiplie les dimensions sans toucher la base", function()
    reset()
    Enable()
    local cfg = NS.db.modules.unitframes.units.target
    local base, baseHeight = cfg.width, cfg.height
    local playerCfg = NS.db.modules.unitframes.units.player
    local totemSize = playerCfg.totemSize
    Mock.units.player.class = "SHAMAN"
    playerCfg.totems = true
    cfg.scale, playerCfg.scale = 2, 2
    NS.Modules:Refresh("unitframes")
    eq(Frame("target"):GetWidth(), base * 2, "largeur doublée")
    eq(Frame("target"):GetHeight(), baseHeight * 2, "hauteur doublée")
    eq(UF:GetTotemBar().buttons[1]:GetWidth(), totemSize * 2, "totems à l'échelle")
    eq(cfg.width, base, "base inchangée")
    cfg.scale, playerCfg.scale = 1, 1
    Mock.units.player.class = nil
    NS.Modules:Refresh("unitframes")
    eq(Frame("target"):GetWidth(), base)
    Disable()
end)

test("unitframes : combo sur le cadre de la cible", function()
    reset()
    Enable()
    Target()
    NS.db.modules.unitframes.units.target.combo = true
    NS.Modules:Refresh("unitframes")
    Mock.units.player.comboMax, Mock.units.player.combo = 5, 3
    Mock.FireEvent("PLAYER_TARGET_CHANGED")
    Mock.FireEvent("UNIT_POWER_FREQUENT", "player")
    local combo = Frame("target").combo
    truthy(combo and combo:IsShown(), "combo visible sur la cible")
    eq(combo:GetValue(), 3)
    Mock.units.player.combo = 0
    Mock.units.player.comboMax = 0
    Mock.FireEvent("UNIT_POWER_FREQUENT", "player")
    eq(combo:IsShown(), false, "sans ressource : caché")
    Disable()
end)

test("unitframes : barre d'incantation, canalisation, verrou, rang, minuteur", function()
    reset()
    Enable()
    local target = Target()
    Mock.FireEvent("PLAYER_TARGET_CHANGED")
    local bar = Frame("target").castbar
    local global = UF.db
    -- Verrou : gris par l'événement, retour à l'accent à l'événement inverse.
    target.casting = { name = "Boule de feu", duration = 2, startTime = 1000000, endTime = 1002000 }
    Mock.FireEvent("UNIT_SPELLCAST_START", "target")
    local accent = bar.barColor[1]
    Mock.FireEvent("UNIT_SPELLCAST_NOT_INTERRUPTIBLE", "target")
    eq(bar.barColor[1], 0.6, "gris")
    global.castLockedColor = { r = 0.1, g = 0.2, b = 0.3 }
    Mock.FireEvent("UNIT_SPELLCAST_NOT_INTERRUPTIBLE", "target")
    eq(bar.barColor[1], 0.1, "gris configuré")
    Mock.FireEvent("UNIT_SPELLCAST_INTERRUPTIBLE", "target")
    eq(bar.barColor[1], accent, "accent rendu")
    target.casting = nil
    Mock.FireEvent("UNIT_SPELLCAST_STOP", "target")
    -- Canalisation : couleur propre.
    global.castChannel, global.castChannelColor = true, { r = 0.5, g = 0.4, b = 0.3 }
    target.channel = { name = "Canal", duration = 4 }
    Mock.FireEvent("UNIT_SPELLCAST_CHANNEL_START", "target")
    eq(bar.barColor[1], 0.5, "couleur de canalisation")
    global.castChannel = false
    target.channel = nil
    Mock.FireEvent("UNIT_SPELLCAST_CHANNEL_STOP", "target")
    -- Rang et minuteur.
    global.castRank, global.castTimer = true, true
    NS.Modules:Refresh("unitframes")
    C_Spell.GetSpellSubtext = function() return "Rang 4" end
    target.casting = { name = "Éclair", duration = { GetRemainingDuration = function() return 1.5 end }, spellID = 99, startTime = 1000000, endTime = 1002000 }
    Mock.FireEvent("UNIT_SPELLCAST_START", "target")
    eq(bar.text:GetText(), "Éclair (Rang 4)", "rang ajouté")
    Mock.Advance(0.2)
    eq(bar.timeText:GetText(), "1.5", "minuteur du moteur")
    C_Spell.GetSpellSubtext = nil
    global.castRank, global.castTimer, global.castLockedColor = false, false, nil
    target.casting = nil
    Disable()
end)

test("unitframes : buffs séparés, style d'aura, annulation au clic droit", function()
    reset()
    Mock.auraContainer = true
    NS.auraContainerProbe = nil
    Enable()
    Frame("player").auras = nil   -- cadre d'un test précédent : conteneur rebâti avec le moteur
    local cfg = NS.db.modules.unitframes.units.player
    cfg.auras, cfg.auraSplit = true, true
    UF.db.auraStealGlow, UF.db.auraCancel = true, true
    NS.Modules:Refresh("unitframes")
    local frame = Frame("player")
    local mainBuffs = frame.auras.engine.groups.buffs
    truthy(mainBuffs == nil or mainBuffs.MaxFrameCount == 0, "conteneur principal : plus de buffs")
    local host = frame.buffAuras
    truthy(host and host.engine and host.engine.groups.buffs, "second conteneur de buffs")
    local button = host.engine.groups.buffs.buttons[1]
    truthy(button, "bouton de buff créé par le moteur")
    if button then
        eq(button.cancelButtons, "RightButtonUp", "clic droit annule")
        eq(button.clickEnabled, true, "clics actifs hors combat")
        -- Client réel : InCombatLockdown() reste faux pendant PLAYER_REGEN_DISABLED.
        Mock.FireEvent("PLAYER_REGEN_DISABLED")
        eq(button.clickEnabled, false, "clics coupés dès l'entrée en combat")
        Mock.FireEvent("PLAYER_REGEN_ENABLED")
        eq(button.clickEnabled, true, "clics rendus")
    end
    Frame("player").auras, Frame("player").buffAuras = nil, nil
    cfg.auras, cfg.auraSplit = true, false
    UF.db.auraStealGlow, UF.db.auraCancel = false, false
    NS.Modules:Refresh("unitframes")
    Disable()
end)

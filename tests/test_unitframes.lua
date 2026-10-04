-- tests/test_unitframes.lua : cadres d'unité AeonUI (étape 2).
local T = ...
local NS, test, eq, truthy, reset = T.NS, T.test, T.eq, T.truthy, T.reset
local Elements = NS.UnitFrameElements
local UF = NS.Modules:Get("unitframes")

local function Enable() NS.Modules:SetEnabled("unitframes", true) end
local function Disable() NS.Modules:SetEnabled("unitframes", false) end
local function Frame(unit) return UF:GetFrame(unit) end
local function Target(fields)
    local unit = { name = "Cible", health = 500, healthMax = 1000, power = 20, powerMax = 100, level = 30, hostile = true }
    for k, v in pairs(fields or {}) do unit[k] = v end
    Mock.units.target = unit
    Mock.RefreshUnitWatch()
    return unit
end

--------------------------------------------------------------------------------
-- Masquage des cadres Blizzard
--------------------------------------------------------------------------------

test("unitframes : HideBlizzardFrame cache, reparente, rend", function()
    reset()
    local original = PlayerFrame:GetParent()
    truthy(NS.HideBlizzardFrame("PlayerFrame"))
    eq(PlayerFrame:IsShown(), false)
    eq(PlayerFrame:GetParent():GetName(), "AeonUI_Hidden")
    truthy(NS.IsBlizzardFrameHidden("PlayerFrame"))
    -- Blizzard le reparente (Edit Mode) : ramené.
    PlayerFrame:SetParent(UIParent)
    eq(PlayerFrame:GetParent():GetName(), "AeonUI_Hidden", "reparentage Blizzard annulé")
    truthy(NS.ShowBlizzardFrame("PlayerFrame"))
    eq(PlayerFrame:GetParent(), original)
    eq(PlayerFrame:IsShown(), false, "pas de Show() contaminé : revient au /reload")
    eq(NS.IsBlizzardFrameHidden("PlayerFrame"), false)
    eq(NS.HideBlizzardFrame("CadreInexistant"), false)
end)

test("unitframes : masquage d'un cadre protégé différé en combat", function()
    reset()
    Mock.SetCombat(true)
    NS.HideBlizzardFrame("PetFrame")
    truthy(PetFrame:IsShown(), "en combat : rien")
    Mock.SetCombat(false)
    eq(PetFrame:IsShown(), false, "à la sortie du combat : caché")
    NS.ShowBlizzardFrame("PetFrame")
end)

--------------------------------------------------------------------------------
-- Cycle de vie
--------------------------------------------------------------------------------

test("unitframes : activation crée cinq boutons sécurisés et masque Blizzard", function()
    reset()
    Enable()
    for _, unit in ipairs(UF.UNITS) do
      if unit ~= "focustarget" then   -- coupée par défaut
        local frame = Frame(unit)
        truthy(frame, unit)
        eq(frame:GetAttribute("unit"), unit)
        eq(frame:GetAttribute("*type1"), "target")
        eq(frame:GetAttribute("*type2"), "togglemenu")
        truthy(frame.secure, "sécurisé")
        truthy(NS.Movers:Anchor("uf_" .. unit), "mover " .. unit)
      end
    end
    truthy(Frame("player"):IsShown(), "joueur visible")
    eq(Frame("target"):IsShown(), false, "pas de cible : caché par UnitWatch")
    truthy(NS.IsBlizzardFrameHidden("PlayerFrame"))
    truthy(NS.IsBlizzardFrameHidden("TargetFrame"))
    truthy(NS.IsBlizzardFrameHidden("PlayerCastingBarFrame"), "castbar joueur cochée")
    Disable()
    eq(NS.IsBlizzardFrameHidden("PlayerFrame"), false)
    eq(Frame("player"):IsShown(), false)
    truthy(Mock.FindPrinted("/reload"), "message reload")
end)

test("unitframes : en combat, activation différée puis faite", function()
    reset()
    Mock.SetCombat(true)
    eq(NS.Modules:SetEnabled("unitframes", true), "deferred")
    eq(UF.enabled, false)
    Mock.SetCombat(false)
    truthy(UF.enabled)
    truthy(Frame("player"):IsShown())
    Disable()
end)


test("unitframes : unité désactivée retirée, réactivée reposée", function()
    reset()
    Enable()
    NS.db.modules.unitframes.units.pet.enabled = false
    NS.Modules:Refresh("unitframes")
    eq(Frame("pet").watched, false)
    eq(NS.IsBlizzardFrameHidden("PetFrame"), false)
    eq(NS.Movers:Anchor("uf_pet"), nil)
    NS.db.modules.unitframes.units.pet.enabled = true
    NS.Modules:Refresh("unitframes")
    truthy(Frame("pet").watched)
    Disable()
end)

--------------------------------------------------------------------------------
-- Santé, puissance, couleurs, textes
--------------------------------------------------------------------------------

test("unitframes : santé secrète posée sur le widget sans erreur", function()
    reset()
    Enable()
    Target({ health = Mock.SetSecret(4242), healthMax = Mock.SetSecret(8484) })
    Mock.FireEvent("PLAYER_TARGET_CHANGED")
    local health = Frame("target").health
    eq(health:GetValue(), 4242)
    local _, max = health:GetMinMaxValues()
    eq(max, 8484)
    eq(health.text:GetText(), "***", "AbbreviateNumbers reçoit la valeur secrète")
    Disable()
end)

test("unitframes : couleurs classe, réaction, secret", function()
    reset()
    Mock.units.player.class = "MAGE"
    local r = Elements.HealthColor("player", true)
    eq(r, RAID_CLASS_COLORS.MAGE.r, "classe du joueur")
    Target({ hostile = true })
    local hr, hg = Elements.HealthColor("target", true)
    truthy(hr > 0.8 and hg < 0.3, "hostile rouge")
    Mock.units.target.hostile, Mock.units.target.reaction = false, 4
    local nr, ng = Elements.HealthColor("target", true)
    truthy(nr > 0.8 and ng > 0.7, "neutre jaune")
    Mock.units.target.isPlayer, Mock.units.target.class = true, Mock.SetSecret("SECRETCLASS")
    Mock.units.target.reaction = Mock.SetSecret(77)
    local gr, gg, gb = Elements.HealthColor("target", true)
    eq(gr, 0.6); eq(gg, 0.6); eq(gb, 0.6)
end)

test("unitframes : textes de vie, niveau, puissance", function()
    reset()
    Target({ health = 1500, healthMax = 3000, level = 30 })
    local function Health(mode) return Elements.RenderText("target", "health", Elements.TextFormat(nil, mode)) end
    eq(Health("current"), "1.5k")
    eq(Health("none"), "")
    eq(Health("percent"), "50%", "sans UnitHealthPercent : calcul sur valeurs lisibles")
    _G.UnitHealthPercent = function() return 0.42 end
    eq(Health("percent"), "50%", "sans ScaleTo100 : fraction ignorée, calcul")
    eq(Health("both"), "1.5k | 50%", "ancien mode « both » gardé")
    Mock.units.target.healthMax = Mock.SetSecret(3001)
    _G.UnitHealthPercent = function() return Mock.SetSecret(51) end
    eq(Health("percent"), "1.5k", "pourcentage et maximum secrets : repli valeur")
    _G.UnitHealthPercent = nil
    Mock.units.target.healthMax = 3000
    eq(Elements.LevelText("target"), "30")
    Mock.units.target.level = -1
    eq(Elements.LevelText("target"), "??")
    Mock.units.target.level = Mock.SetSecret(61)
    eq(Elements.LevelText("target"), "")
    Mock.units.target.powerType = "RAGE"
    local pr = Elements.PowerColor("target")
    eq(pr, 1, "rage rouge")
    Mock.units.target.powerType = Mock.SetSecret("SECRETPOWER")
    local sr, sg, sb = Elements.PowerColor("target")
    eq(sb, 0.87, "type secret : mana")
end)

test("unitframes : barre de puissance cachée à max 0, niveau caché au niveau max", function()
    reset()
    Enable()
    Target({ powerMax = 0 })
    Mock.FireEvent("PLAYER_TARGET_CHANGED")
    eq(Frame("target").power:IsShown(), false)
    Mock.units.target.powerMax = 100
    Mock.FireEvent("UNIT_MAXPOWER", "target")
    truthy(Frame("target").power:IsShown())
    Mock.units.player.level = 60
    Mock.FireEvent("PLAYER_LEVEL_UP")
    eq(Frame("player").level:IsShown(), false, "niveau max caché")
    Mock.units.player.level = 42
    Mock.FireEvent("PLAYER_LEVEL_UP")
    eq(Frame("player").level:GetText(), "42")
    Disable()
end)

--------------------------------------------------------------------------------
-- Barre d'incantation
--------------------------------------------------------------------------------

test("unitframes : castbar démarre, s'arrête, s'interrompt", function()
    reset()
    Enable()
    local target = Target()
    Mock.FireEvent("PLAYER_TARGET_CHANGED")
    local bar = Frame("target").castbar
    eq(bar:IsShown(), false)
    target.casting = { name = "Boule de feu", texture = "icone", duration = 2.5, startTime = 1000000, endTime = 1002500 }
    Mock.FireEvent("UNIT_SPELLCAST_START", "target")
    truthy(bar:IsShown())
    eq(bar.text:GetText(), "Boule de feu")
    eq(bar.timer.duration, 2.5, "SetTimerDuration reçoit la durée")
    eq(bar.timer.direction, Enum.StatusBarTimerDirection.ElapsedTime)
    target.casting.notInterruptible = Mock.SetSecret(true)
    Mock.FireEvent("UNIT_SPELLCAST_NOT_INTERRUPTIBLE", "target")
    eq(bar.barColor[1], 0.6, "secret : le moteur choisit le gris")
    target.casting = nil
    Mock.FireEvent("UNIT_SPELLCAST_STOP", "target")
    eq(bar:IsShown(), false)
    target.channel = { name = "Canal", duration = 4 }
    Mock.FireEvent("UNIT_SPELLCAST_CHANNEL_START", "target")
    truthy(bar:IsShown())
    eq(bar.timer.direction, Enum.StatusBarTimerDirection.RemainingTime)
    Mock.FireEvent("UNIT_SPELLCAST_INTERRUPTED", "target")
    truthy(bar:IsShown(), "tenue après interruption")
    eq(bar.barColor[1], 0.9)
    Mock.Advance(0.6)
    eq(bar:IsShown(), false, "cachée après la tenue")
    target.channel = nil
    Disable()
end)

test("unitframes : castbar du joueur : tops de canalisation, latence, fin de recharge globale", function()
    reset()
    Enable()
    local player = Mock.units.player
    local bar = Frame("player").castbar
    local function Lines()
        local n = 0
        for _, line in ipairs(bar.hashLines or {}) do if line:IsShown() then n = n + 1 end end
        return n
    end
    player.channel = { name = "Blizzard", spellID = 10, duration = 8, startTime = 1000000, endTime = 1008000 }
    Mock.FireEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
    eq(Lines(), 7, "huit tops : sept repères")
    eq(bar.latency:IsShown(), false, "pas de latence sur une canalisation")
    player.channel = nil
    player.casting = { name = "Éclair de givre", duration = 3, startTime = 1000000, endTime = 1003000 }
    UF.db.castGCD = true
    Mock.FireEvent("UNIT_SPELLCAST_START", "player")
    eq(Lines(), 1, "repère de fin de recharge globale")
    truthy(bar.latency:IsShown(), "zone de latence")
    UF.db.castGCD, UF.db.castLatency = false, false
    Mock.FireEvent("UNIT_SPELLCAST_START", "player")
    eq(Lines(), 0)
    eq(bar.latency:IsShown(), false)
    player.casting.startTime = Mock.SetSecret(1000000)
    UF.db.castLatency = true
    Mock.FireEvent("UNIT_SPELLCAST_START", "player")
    eq(bar.latency:IsShown(), false, "durée secrète : aucun repère")
    player.casting = nil
    Disable()
end)

test("unitframes : castbar sans SetTimerDuration : progression manuelle, plein si secret", function()
    reset()
    Enable()
    local target = Target()
    Mock.FireEvent("PLAYER_TARGET_CHANGED")
    local bar = Frame("target").castbar
    local saved = Mock.FrameMeta.SetTimerDuration
    Mock.FrameMeta.SetTimerDuration = nil
    target.casting = { name = "Lent", startTime = Mock.now * 1000, endTime = (Mock.now + 2) * 1000 }
    Mock.FireEvent("UNIT_SPELLCAST_START", "target")
    truthy(bar:IsShown())
    Mock.Advance(1)
    truthy(math.abs(bar:GetValue() - 1) < 0.1, "1 s écoulée")
    Mock.Advance(1.1)
    eq(bar:IsShown(), false, "finie")
    target.casting = { name = "Secret", startTime = Mock.SetSecret(123456), endTime = Mock.SetSecret(654321) }
    Mock.FireEvent("UNIT_SPELLCAST_START", "target")
    truthy(bar:IsShown())
    eq(bar:GetValue(), 1, "pleine, sans progression")
    Mock.FrameMeta.SetTimerDuration = saved
    target.casting = nil
    Mock.FireEvent("UNIT_SPELLCAST_STOP", "target")
    Disable()
end)

--------------------------------------------------------------------------------
-- Indicateurs, marqueur, combo
--------------------------------------------------------------------------------

test("unitframes : repos, combat, chef, marqueur de raid", function()
    reset()
    Enable()
    local player = Frame("player")
    Mock.resting = true
    Mock.FireEvent("PLAYER_UPDATE_RESTING")
    truthy(player.resting:IsShown())
    Mock.SetCombat(true)
    truthy(player.combat:IsShown())
    eq(player.resting:IsShown(), false)
    Mock.SetCombat(false)
    Mock.units.player.leader = true
    Mock.FireEvent("GROUP_ROSTER_UPDATE")
    truthy(player.leader:IsShown())
    Target({ raidIcon = 8 })
    Mock.FireEvent("PLAYER_TARGET_CHANGED")
    truthy(Frame("target").raidIcon:IsShown())
    eq(Frame("target").raidIcon.raidIndex, 8)
    Mock.units.target.raidIcon = nil
    Mock.FireEvent("RAID_TARGET_UPDATE")
    eq(Frame("target").raidIcon:IsShown(), false)
    Disable()
end)

test("unitframes : points de combo = une barre graduée, cachée sans ressource", function()
    reset()
    Enable()
    local combo = Frame("player").combo
    eq(combo:IsShown(), false, "mage : pas de combo")
    Mock.units.player.comboMax, Mock.units.player.combo = 5, 3
    Mock.FireEvent("UNIT_POWER_UPDATE", "player")
    truthy(combo:IsShown())
    eq(combo:GetValue(), 3)
    local _, max = combo:GetMinMaxValues()
    eq(max, 5)
    local ticks = 0
    for _, tick in ipairs(combo.ticks) do if tick:IsShown() then ticks = ticks + 1 end end
    eq(ticks, 4, "quatre graduations pour cinq points")
    Mock.units.player.combo = Mock.SetSecret(2)
    Mock.FireEvent("UNIT_POWER_UPDATE", "player")
    eq(combo:GetValue(), 2, "valeur secrète acceptée")
    Disable()
end)

test("unitframes : points de combo en pastilles, bornées de i-1 à i, valeur secrète passée telle quelle", function()
    reset()
    UF.db.units.player.comboPips = true
    Enable()
    Mock.units.player.comboMax, Mock.units.player.combo = 5, Mock.SetSecret(3)
    Mock.FireEvent("UNIT_POWER_UPDATE", "player")
    local frame = Frame("player")
    eq(frame.combo:IsShown(), false, "barre graduée remplacée")
    truthy(frame.comboPips:IsShown())
    eq(#frame.comboPips.pips, 5)
    local low, high = frame.comboPips.pips[4]:GetMinMaxValues()
    eq(low, 3) eq(high, 4)
    eq(frame.comboPips.pips[4]:GetValue(), 3, "pastille 4 vide, sans comparaison en Lua")
    Mock.units.player.comboMax = 0
    Mock.FireEvent("UNIT_POWER_UPDATE", "player")
    eq(frame.comboPips:IsShown(), false, "sans ressource : cachées")
    Disable()
end)

test("unitframes : couleur de réaction réglable, engagé par un autre prioritaire", function()
    reset()
    local hostile = UF.db.reactionColors.hostile
    UF.db.reactionColors.hostile = { r = 0.1, g = 0.2, b = 0.3 }
    Target({ reaction = 2 })
    local r, g, b = Elements.HealthColor("target", true)
    eq(r, 0.1) eq(g, 0.2) eq(b, 0.3)
    local original = _G.UnitIsTapDenied
    _G.UnitIsTapDenied = function() return true end
    r = Elements.HealthColor("target", true)
    eq(r, UF.db.reactionColors.tapped.r, "engagé par un autre")
    _G.UnitIsTapDenied = original
    UF.db.reactionColors.hostile = hostile
end)

test("unitframes : visibilité commune = pilote d'état qui exige aussi l'unité", function()
    reset()
    UF.db.units.target.visibility.combat = "yes"
    Enable()
    eq(Mock.stateDrivers[Frame("target")].visibility, "[@target,noexists] hide; [nocombat] hide; show")
    UF.db.units.target.visibility.combat = "ignore"
    NS.Modules:Refresh("unitframes")
    eq(Mock.stateDrivers[Frame("target")].visibility, nil, "sans condition : RegisterUnitWatch")
    Disable()
end)

test("unitframes : texte central libre, jetons [name] et [level]", function()
    reset()
    UF.db.units.target.centerFormat = "[name] ([level])"
    Enable()
    Target({ name = "Loup", level = 12 })
    Mock.FireEvent("PLAYER_TARGET_CHANGED")
    eq(Frame("target").health.centerText:GetText(), "Loup (12)")
    Target({ name = "Boss", level = -1 })
    Mock.FireEvent("PLAYER_TARGET_CHANGED")
    eq(Frame("target").health.centerText:GetText(), "Boss (??)")
    Disable()
end)

test("unitframes : couleur et hauteur des absorptions réglables", function()
    reset()
    UF.db.absorbColor = { r = 0.1, g = 0.2, b = 0.3, a = 0.4 }
    UF.db.absorbHeight = 50
    Enable()
    local absorb = Frame("player").absorb
    local r, _, b = absorb:GetStatusBarColor()
    eq(r, 0.1) eq(b, 0.3)
    truthy(absorb:GetHeight() < Frame("player"):GetHeight(), "moitié de la vie")
    Disable()
end)

test("unitframes : portée d'attaque atténue la cible, jamais le joueur", function()
    reset()
    UF.db.units.target.rangeFade = true
    UF.db.rangeAlpha = 0.5
    Enable()
    Target()
    local original = C_Spell.IsSpellInRange
    Mock.spells[133] = "Boule de feu"
    C_Spell.IsSpellInRange = function() return false end
    UF:UpdateFade()
    eq(Frame("target"):GetAlpha(), 0.5, "hors de portée")
    C_Spell.IsSpellInRange = function() return true end
    UF:UpdateFade()
    eq(Frame("target"):GetAlpha(), 1, "à portée")
    C_Spell.IsSpellInRange = function() return Mock.SetSecret(false) end
    Target({ hostile = false })
    UF:UpdateFade()
    eq(Frame("target"):GetAlpha(), 1, "allié : jamais atténué, même réponse secrète")
    C_Spell.IsSpellInRange, Mock.spells[133] = original, nil
    Disable()
end)

test("visibilité : clauses de masquage, toutes ou au moins une", function()
    local V = NS.Visibility
    eq(V.HideClauses(V.Spec()), "")
    eq(V.HideClauses(V.Spec({ combat = "yes", mounted = "no" })), "[nocombat] hide; [mounted] hide; ")
    eq(V.HideClauses(V.Spec({ combat = "yes", mounted = "no", match = "any" })), "[nocombat,mounted] hide; ")
    eq(V.HideClauses(V.Spec({ instance = "yes" })), "", "instance : pas de condition macro")
end)

--------------------------------------------------------------------------------
-- Auras
--------------------------------------------------------------------------------

test("unitframes : auras en repli maison (débuffs, secret sans spirale)", function()
    reset()
    Enable()
    Target()
    Mock.debuffs.target = {
        { icon = "a", duration = 10, expirationTime = Mock.now + 5, applications = 3, dispelName = "Magic" },
        { icon = "b", duration = Mock.SetSecret(12), expirationTime = Mock.SetSecret(99999) },
        { icon = "c", duration = 0, expirationTime = 0 },
    }
    Mock.FireEvent("PLAYER_TARGET_CHANGED")
    local auras = Frame("target").auras
    truthy(auras, "conteneur créé (cible : auras cochées)")
    eq(auras.native, false)
    truthy(auras.buttons[1]:IsShown()); truthy(auras.buttons[3]:IsShown())
    eq(auras.buttons[4]:IsShown(), false)
    eq(auras.buttons[1].cooldown.cooldownDuration, 10)
    eq(auras.buttons[1].count:GetText(), "3")
    eq(auras.buttons[1].border.top.color[3], 1, "bordure Magie bleue")
    eq(auras.buttons[2].cooldown.cooldownDuration, nil, "durée secrète : pas de spirale")
    eq(auras.buttons[2].count:GetText(), "")
    Mock.debuffs.target = {}
    Mock.FireEvent("UNIT_AURA", "target")
    eq(auras.buttons[1]:IsShown(), false)
    Disable()
end)

test("unitframes : débuffs priorisés (boss, contrôle) et lueur des contrôles", function()
    reset()
    Enable()
    Target()
    Mock.debuffs.target = {
        { icon = "plain", auraInstanceID = 1 },
        { icon = "stun", auraInstanceID = 2, cc = true },
        { icon = "boss", auraInstanceID = 3, isBossAura = true },
        { icon = "hidden", auraInstanceID = Mock.SetSecret(4), cc = true },
    }
    Mock.FireEvent("PLAYER_TARGET_CHANGED")
    local buttons = Frame("target").auras.buttons
    eq(buttons[1].icon.texture, "boss", "boss en tête")
    eq(buttons[2].icon.texture, "stun", "contrôle ensuite")
    eq(NS.Glow.Current(buttons[2]), "pixel", "lueur du contrôle")
    eq(NS.Glow.Current(buttons[1]), nil)
    eq(buttons[3].icon.texture, "plain")
    eq(NS.Glow.Current(buttons[4]), nil, "identifiant secret : pas de contrôle signalé")
    NS.db.auraLists.prioritize, NS.db.auraLists.ccGlow = false, "none"
    Mock.FireEvent("UNIT_AURA", "target")
    eq(buttons[1].icon.texture, "plain", "ordre du jeu sans priorité")
    eq(NS.Glow.Current(buttons[2]), nil, "lueur coupée")
    NS.db.auraLists.prioritize, NS.db.auraLists.ccGlow = true, "pixel"
    Mock.debuffs.target = {}
    Disable()
end)

test("unitframes : conteneur du moteur quand le client l'offre ; vie verticale", function()
    reset()
    Mock.auraContainer = true
    NS.auraContainerProbe = nil
    truthy(NS.AuraContainerAvailable())
    Enable()
    local cfg = NS.db.modules.unitframes.units.pet
    cfg.auras, cfg.vertical, cfg.auraFilter = true, true, "mine"
    NS.db.auraLists.blacklist = "123"
    NS.Modules:Refresh("unitframes")
    local frame = Frame("pet")
    local engine = frame.auras and frame.auras.engine
    eq(frame.auras.native, true, "voie du moteur")
    eq(engine.groups.debuffs.filter, "HARMFUL|PLAYER|!CROWD_CONTROL", "filtre « les miens », contrôles à part")
    eq(engine.groups.crowdControl.filter, "HARMFUL|CROWD_CONTROL|PLAYER")
    eq(engine.groups.debuffs.options.candidateFilters.excludeSpellIDs[123], true, "liste noire")
    eq(engine.groups.listed, nil, "liste blanche vide : groupe non déclaré")
    eq(engine.groups.buffs.options.layout.forceNewLine, true, "buffs sur une ligne neuve")
    local button = engine.groups.debuffs.buttons[1]
    truthy(button.SetIcon and button.SetDurationCooldown and button.SetApplicationCount, "régions confiées au moteur")
    eq(button.SetMouseClickEnabled, false, "clics laissés au cadre")
    Elements.UpdateAll(frame)
    eq(engine:GetUnit(), frame.unit, "unité posée")
    local refreshes = #engine.calls
    Elements.OnEvent(frame, "UNIT_AURA")
    eq(#engine.calls, refreshes, "UNIT_AURA : le moteur s'en charge")
    Elements.UpdateAll(frame)
    eq(engine.calls[#engine.calls], "UpdateAllAuras", "changement d'unité : tout relu")
    cfg.debuffsOnly = true
    NS.Modules:Refresh("unitframes")
    eq(engine.groups.buffs.MaxFrameCount, 0, "débuffs seuls : buffs vidés")
    cfg.debuffsOnly, cfg.auraFilter, NS.db.auraLists.blacklist = nil, "all", ""
    eq(frame.health.orientation, "VERTICAL")
    eq(frame.healPrediction.orientation, "VERTICAL")
    NS.db.modules.unitframes.units.pet.auras = false
    NS.db.modules.unitframes.units.pet.vertical = false
    NS.Modules:Refresh("unitframes")
    eq(frame.health.orientation, "HORIZONTAL")
    Frame("pet").auras = nil
    Disable()
end)

--------------------------------------------------------------------------------
-- Options, thème
--------------------------------------------------------------------------------

test("unitframes : options construites module actif, sans pourcentage sans API", function()
    reset()
    Enable()
    NS.Options:BuildMain()
    local built = {}
    UF:BuildOptions(setmetatable({ name = "unitframes", layout = setmetatable({}, { __index = function()
        return function(_, ...) built[#built + 1] = select(1, ...) end
    end }) }, { __index = function(_, k) return function(_, ...) built[#built + 1] = select(1, ...) end end }))
    truthy(#built > 20, "un widget par réglage")
    Disable()
end)

test("unitframes : THEME_CHANGED repose la texture des barres", function()
    reset()
    Enable()
    local health = Frame("player").health
    eq(health.barTexture, "Interface\\Buttons\\WHITE8X8")
    NS.db.theme.statusbar = "Inexistante"
    NS:Fire("THEME_CHANGED")
    eq(health.barTexture, "Interface\\Buttons\\WHITE8X8", "sans LSM : texture plate")
    NS.db.theme.statusbar = ""
    Disable()
end)

test("unitframes : barre d'incantation détachée = son propre mover, rattachée = plus de mover", function()
    reset()
    Enable()
    local Movers = NS.Movers
    eq(Movers.registry.uf_castbar_player, nil, "attachée par défaut : pas de mover")
    NS.db.modules.unitframes.units.player.castbarDetached = true
    NS.db.modules.unitframes.units.player.castbarWidth = 300
    UF:Reconcile()
    truthy(Movers.registry.uf_castbar_player, "détachée : mover uf_castbar_player")
    local castbar = Frame("player").castbar
    truthy(castbar.detached)
    local point, rel = castbar:GetPoint()
    eq(rel, UIParent, "posée sur UIParent par le mover")
    NS.db.modules.unitframes.units.player.castbarDetached = false
    UF:Reconcile()
    eq(Movers.registry.uf_castbar_player, nil, "rattachée : mover retiré")
    Disable()
end)

test("unitframes : barre de totems, emplacement vide transparent, secret affiché", function()
    reset()
    local totems = {}   -- [slot] = { have, icon, start, duration }
    _G.GetTotemInfo = function(slot)
        local t = totems[slot]
        if not t then return false, "", 0, 0, "" end
        return t[1], "Totem", t[3], t[4], t[2]
    end
    Enable()
    local bar = UF:GetTotemBar()
    truthy(bar and bar:IsShown(), "barre posée avec le cadre du joueur")
    eq(bar.buttons[1]:GetAttribute("type2"), "destroytotem")
    eq(bar.buttons[1]:GetAlpha(), 0, "vide")
    totems[1] = { true, 136098, 100, 60 }
    Mock.FireEvent("PLAYER_TOTEM_UPDATE")
    eq(bar.buttons[1]:GetAlpha(), 1, "totem posé")
    eq(bar.buttons[2]:GetAlpha(), 0)
    totems[2] = { Mock.SetSecret({}), 136099, 0, 0 }   -- table unique : seule elle est secrète
    Mock.FireEvent("PLAYER_TOTEM_UPDATE")
    eq(bar.buttons[2]:GetAlpha(), 1, "présence secrète : affiché")
    Disable()
    eq(bar:IsShown(), false, "module coupé : barre retirée")
    _G.GetTotemInfo = nil
end)

test("unitframes : élite, écusson JcJ, bordure de menace, humeur du familier", function()
    reset()
    Enable()
    Target({ classification = "elite", pvp = true, faction = "Horde" })
    Mock.FireEvent("PLAYER_TARGET_CHANGED")
    local target = Frame("target")
    truthy(target.classification:IsShown(), "élite")
    eq(target.classification.atlas, "nameplates-icon-elite-gold")
    truthy(target.pvp:IsShown(), "écusson")
    eq(target.pvp.texture, "Interface\\TargetingFrame\\UI-PVP-Horde")
    Mock.units.target.pvp = false
    Mock.FireEvent("UNIT_FACTION", "target")
    eq(target.pvp:IsShown(), false, "plus marqué JcJ")
    local player = Frame("player")
    Mock.units.player.threat = 3
    Mock.FireEvent("UNIT_THREAT_SITUATION_UPDATE", "player")
    eq(player.border.top.color[1], 0.9, "agro ferme : rouge")
    Mock.units.player.threat = nil
    Mock.FireEvent("UNIT_THREAT_SITUATION_UPDATE", "player")
    eq(player.border.top.color[1], NS.db.theme.border.r, "menace retombée")
    Mock.units.pet = { name = "Loup", health = 50, healthMax = 50 }
    Mock.petHappiness = { 3, 125, 1 }
    Mock.FireEvent("UNIT_PET", "player")
    local pet = Frame("pet")
    truthy(pet.happiness:IsShown(), "humeur visible")
    eq(pet.happiness.texture.atlas, "UI-PetHappiness")
    Mock.petHappiness = nil
    Mock.FireEvent("UNIT_HAPPINESS", "pet")
    eq(pet.happiness:IsShown(), false, "pas de familier de chasseur")
    Mock.units.pet = nil
    Disable()
end)

test("unitframes : castbar avec cible du sort, interruption prête, éclair à l'interruption", function()
    reset()
    Enable()
    local target = Target()
    Mock.units.targettarget = { name = "Testeur" }
    Mock.FireEvent("PLAYER_TARGET_CHANGED")
    local bar = Frame("target").castbar
    Mock.spells[2139], Mock.knownSpells[2139] = "Contresort", true
    local ready = true
    C_Spell.GetSpellCooldownDuration = function(spell)
        if spell == 2139 then return { IsZero = function() return ready end } end
    end
    Mock.FireEvent("SPELLS_CHANGED")
    target.casting = { name = "Soins", startTime = 1000000, endTime = 1002500 }
    Mock.FireEvent("UNIT_SPELLCAST_START", "target")
    eq(bar.text:GetText(), "Soins > Testeur", "cible du sort")
    eq(bar.barColor[2], UF.db.interruptReadyColor.g, "interruption prête")
    ready = false
    Mock.Advance(0.15)
    eq(bar.barColor[1], NS.db.theme.accent.r, "interruption en recharge : accent")
    target.casting.notInterruptible = Mock.SetSecret(true)
    Mock.FireEvent("UNIT_SPELLCAST_NOT_INTERRUPTIBLE", "target")
    eq(bar.barColor[1], 0.6, "non interruptible secret : le moteur choisit le gris")
    Mock.FireEvent("UNIT_SPELLCAST_INTERRUPTED", "target")
    truthy(bar.flash:IsShown(), "éclair")
    Mock.Advance(0.6)
    eq(bar.flash:IsShown(), false)
    target.casting, Mock.units.targettarget = nil, nil
    C_Spell.GetSpellCooldownDuration = nil
    Mock.spells[2139], Mock.knownSpells[2139] = nil, nil
    Mock.FireEvent("SPELLS_CHANGED")
    Disable()
end)

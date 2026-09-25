-- tests/test_modules.lua : alertes, barres de nom, cadres, autre tank, curseur, fiche,
-- habillage, interface.
local T = ...
local NS, test, eq, truthy, reset = T.NS, T.test, T.eq, T.truthy, T.reset
local M = function(name) return NS.Modules:Get(name) end

--------------------------------------------------------------------------------
-- Alertes
--------------------------------------------------------------------------------

test("alertes : entrée et sortie de combat", function()
    reset()
    Mock.SetCombat(true)
    local flash = M("alerts"):GetFlash()
    eq(flash.text:GetText(), "+ Combat")
    truthy(flash:IsShown())
    Mock.SetCombat(false)
    eq(flash.text:GetText(), "- Combat")
    Mock.Advance(3)
    eq(flash:IsShown(), false, "s'efface")
end)

test("son importé : prioritaire sur le preset, repli si fichier absent ou vide", function()
    Mock.sounds = {}
    NS.PlayPreset("raidwarning", "  Interface\\AddOns\\MesSons\\alerte.ogg ")
    eq(Mock.sounds[1].file, "Interface\\AddOns\\MesSons\\alerte.ogg", "fichier joué, espaces retirés")
    NS.PlayPreset("raidwarning", "569593")
    eq(Mock.sounds[2].file, 569593, "FileDataID")
    NS.PlayPreset("raidwarning", "Interface\\AddOns\\Absent.ogg")
    eq(Mock.sounds[3].kit, 8959, "fichier absent : preset")
    NS.PlayPreset("raidwarning", "")
    eq(Mock.sounds[4].kit, 8959, "vide : preset")
end)

test("alertes : entrée seule, texte et couleur personnalisés, preset de son", function()
    reset()
    local db = NS.db.modules.alerts
    db.combatShow, db.combatInText, db.combatInColor = "enter", "Fight!", { r = 0.1, g = 0.2, b = 0.9 }
    db.combatSound, db.combatSoundPreset = true, "readycheck"
    Mock.sounds = {}
    Mock.SetCombat(true)
    local flash = M("alerts"):GetFlash()
    eq(flash.text:GetText(), "Fight!")
    eq(flash.text.textColor[3], 0.9, "couleur d'entrée")
    eq(#Mock.sounds, 1, "son d'entrée")
    Mock.Advance(3)
    Mock.SetCombat(false)
    eq(flash:IsShown(), false, "pas d'alerte de sortie")
    eq(#Mock.sounds, 1)
    db.combatShow, db.combatInText, db.combatSound = "both", "", false
    db.combatInColor = { r = 1, g = 0.3, b = 0.3 }
end)

test("alertes : mort d'un membre annoncée une seule fois, secret ignoré", function()
    reset()
    Mock.groupSize = 2
    Mock.units.party1 = { guid = "Player-7", name = "Tankou", class = "WARRIOR", isPlayer = true }
    Mock.FireEvent("UNIT_HEALTH", "party1")
    eq(M("alerts"):GetFlash():IsShown(), false, "vivant")
    Mock.units.party1.dead = true
    Mock.FireEvent("UNIT_HEALTH", "party1")
    eq(M("alerts"):GetFlash().text:GetText(), "Tankou died")
    eq(M("alerts"):CheckDeath("party1"), false, "déjà annoncé")
    Mock.FireEvent("GROUP_ROSTER_UPDATE")
    eq(M("alerts"):CheckDeath("party1"), false, "arrivée dans le groupe : pas rejoué")
    Mock.units.party1.dead = false
    Mock.FireEvent("UNIT_HEALTH", "party1")
    Mock.units.party1.dead = true
    eq(M("alerts"):CheckDeath("party1"), true, "nouvelle mort après résurrection")
    Mock.secret["Player-7"] = true
    eq(M("alerts"):CheckDeath("party1"), false, "GUID secret")
end)

--------------------------------------------------------------------------------
-- Barres de nom
--------------------------------------------------------------------------------

local function Target(hostile)
    local enemy = { guid = "Creature-1", name = "Loup", hostile = hostile }
    Mock.units.target, Mock.units.nameplate1 = enemy, enemy
    local plate = CreateFrame("Frame")
    Mock.namePlates.nameplate1 = plate
    Mock.FireEvent("PLAYER_TARGET_CHANGED")
    return plate, enemy
end

test("chevrons : suivent la plaque d'une cible hostile", function()
    reset()
    local plate = Target(true)
    local arrows = M("nameplates"):GetArrows()
    eq(arrows:IsShown(), true)
    eq(arrows:GetParent(), UIParent, "jamais reparenté sur une plaque protégée")
    eq(arrows.points[1][2], plate, "ancré sur la plaque")
    Mock.FireEvent("NAME_PLATE_UNIT_REMOVED", "nameplate1")
    eq(arrows:IsShown(), false, "plaque retirée")
end)

test("chevrons : pas sur une cible amicale (réglable)", function()
    reset()
    Target(false)
    eq(M("nameplates"):GetArrows():IsShown(), false)
    NS.db.modules.nameplates.hostileOnly = false
    NS.Modules:Refresh("nameplates")
    eq(M("nameplates"):GetArrows():IsShown(), true)
    NS.db.modules.nameplates.hostileOnly = true
end)

test("chevrons : le gauche s'écarte pendant une incantation", function()
    reset()
    Target(true)
    local arrows = M("nameplates"):GetArrows()
    eq(select(4, arrows.left:GetPoint()), -4, "écart normal")
    Mock.FireEvent("UNIT_SPELLCAST_START", "target")
    eq(select(4, arrows.left:GetPoint()), -12, "écart + recul")
    Mock.FireEvent("UNIT_SPELLCAST_STOP", "target")
    eq(select(4, arrows.left:GetPoint()), -4)
    -- incantation secrète au changement de cible : elle compte comme « en cours »
    local _, enemy = Target(true)
    enemy.casting = "Sort secret"
    Mock.secret["Sort secret"] = true
    Mock.FireEvent("PLAYER_TARGET_CHANGED")
    eq(select(4, arrows.left:GetPoint()), -12, "secret = incante")
end)

--------------------------------------------------------------------------------
-- Cadres d'unité
--------------------------------------------------------------------------------

test("cadres : vie couleur de classe et mode sombre, tout rendu au disable", function()
    reset()
    Mock.units.target = { guid = "Player-8", class = "ROGUE", isPlayer = true }
    NS.Modules:SetEnabled("frames", true)
    local bar = M("frames").HealthBar("TargetFrame")
    truthy(bar, "barre de vie trouvée par le chemin 12.x")
    eq(bar.barColor[2], 0.96, "jaune voleur")
    eq(TargetFrame.border.vertex[1], 0.3, "habillage assombri")
    NS.Modules:SetEnabled("frames", false)
    eq(bar.barColor[2], 1, "vert Blizzard rendu")
    eq(TargetFrame.border.vertex[1], 1, "habillage rendu")
end)

test("cadres : épées croisées quand la cible est en combat", function()
    reset()
    NS.Modules:SetEnabled("frames", true)
    Mock.units.target = { guid = "Creature-2", combat = true }
    Mock.FireEvent("PLAYER_TARGET_CHANGED")
    truthy(AeonUITargetCombat:IsShown(), "affichées")
    Mock.secret[true] = true
    Mock.FireEvent("UNIT_FLAGS", "target")
    eq(AeonUITargetCombat:IsShown(), false, "valeur secrète : masquées")
    Mock.secret = {}
    NS.Modules:SetEnabled("frames", false)
end)

--------------------------------------------------------------------------------
-- Autre tank
--------------------------------------------------------------------------------

test("autre tank : trouvé dans le raid, cliquable, vie suivie", function()
    reset()
    NS.Modules:SetEnabled("cotank", true)
    Mock.inRaid, Mock.groupSize = true, 3
    Mock.roles = { player = "TANK", raid2 = "TANK" }
    Mock.units.raid1 = Mock.units.player
    Mock.units.raid2 = { guid = "Player-9", name = "Mur", class = "WARRIOR", health = 40, healthMax = 100 }
    Mock.FireEvent("GROUP_ROSTER_UPDATE")
    local button, watched = M("cotank"):GetButton()
    eq(watched, "raid2")
    eq(button:GetAttribute("unit"), "raid2")
    eq(button.health.value, 40)
    Mock.units.raid2.health = 10
    Mock.FireEvent("UNIT_HEALTH", "raid2")
    eq(button.health.value, 10, "vie mise à jour")
end)

test("autre tank : changement de raid en combat attendu, pas de tank = masqué", function()
    reset()
    Mock.inRaid, Mock.groupSize = true, 2
    Mock.roles = { player = "TANK" }
    Mock.units.raid1 = Mock.units.player
    Mock.SetCombat(true)
    Mock.FireEvent("GROUP_ROSTER_UPDATE")
    local button = M("cotank"):GetButton()
    eq(button:GetAttribute("unit"), "raid2", "inchangé en combat")
    Mock.SetCombat(false)
    eq(button:IsShown(), false, "plus d'autre tank")
    NS.Modules:SetEnabled("cotank", false)
end)

test("autre tank : ses débuffs posent icône et balayage ; secret = icône sans balayage", function()
    reset()
    NS.Modules:SetEnabled("cotank", true)
    Mock.inRaid, Mock.groupSize = true, 3
    Mock.roles = { player = "TANK", raid2 = "TANK" }
    Mock.units.raid1 = Mock.units.player
    Mock.units.raid2 = { guid = "Player-9", name = "Mur", class = "WARRIOR", health = 40, healthMax = 100 }
    Mock.debuffs.raid2 = { { icon = 1234, duration = 10, expirationTime = Mock.now + 6 } }
    Mock.FireEvent("GROUP_ROSTER_UPDATE")
    local _, watched, icons = M("cotank"):GetButton()
    eq(watched, "raid2")
    eq(#icons, 4, "debuffMax icônes")
    eq(icons[1]:IsShown(), true)
    eq(icons[1].cooldown.cooldownDuration, 10)
    eq(icons[2]:IsShown(), false)
    -- En combat, valeurs secrètes : icône posée, aucun balayage, aucune erreur.
    local secretDuration, secretExpiration = 77, 88
    Mock.secret[secretDuration], Mock.secret[secretExpiration] = true, true
    Mock.debuffs.raid2 = { { icon = 1234, duration = secretDuration, expirationTime = secretExpiration },
                           { icon = 5678, duration = 5, expirationTime = Mock.now + 5 } }
    Mock.SetCombat(true)
    Mock.FireEvent("UNIT_AURA", "raid2")
    eq(icons[1]:IsShown(), true)
    eq(icons[1].cooldown.cooldownDuration, nil, "pas de balayage sur un secret")
    eq(icons[2]:IsShown(), true)
    eq(icons[2].cooldown.cooldownDuration, 5)
    Mock.SetCombat(false)
    -- Coupé : rangée masquée.
    NS.db.modules.cotank.debuffs = false
    NS.Modules:Refresh("cotank")
    eq(icons[1]:IsShown(), false)
    NS.db.modules.cotank.debuffs = true
    NS.Modules:SetEnabled("cotank", false)
end)

test("autre tank : filtre des débuffs (boss, dissipable) et compteur de stacks", function()
    reset()
    Mock.units.player.class = "PRIEST"
    NS.Modules:SetEnabled("cotank", true)
    Mock.inRaid, Mock.groupSize = true, 3
    Mock.roles = { player = "TANK", raid2 = "TANK" }
    Mock.units.raid1 = Mock.units.player
    Mock.units.raid2 = { guid = "Player-9", name = "Mur", class = "WARRIOR", health = 40, healthMax = 100 }
    Mock.debuffs.raid2 = {
        { icon = 1, applications = 3 },
        { icon = 2, isBossAura = true },
        { icon = 3, dispelName = "Magic" },
        { icon = 4, dispelName = "Curse" },
    }
    Mock.FireEvent("GROUP_ROSTER_UPDATE")
    local _, watched, icons = M("cotank"):GetButton()
    eq(watched, "raid2")
    eq(icons[4]:IsShown(), true, "all : les 4")
    eq(tostring(icons[1].count:GetText()), "3", "stacks")
    eq(icons[2].count:GetText(), "", "pas de stacks")
    NS.db.modules.cotank.debuffFilter = "important"
    NS.Modules:Refresh("cotank")
    eq(icons[1].texture.texture, 2, "boss d'abord")
    eq(icons[2].texture.texture, 3, "puis dissipable")
    eq(icons[3]:IsShown(), false, "malédiction et stacks écartés")
    NS.db.modules.cotank.debuffFilter = "dispellable"
    NS.Modules:Refresh("cotank")
    eq(icons[1].texture.texture, 3)
    eq(icons[2]:IsShown(), false)
    -- Champ secret : jamais comparé, débuff gardé.
    local secretBoss = 91
    Mock.secret[secretBoss] = true
    Mock.debuffs.raid2 = { { icon = 5, isBossAura = secretBoss, dispelName = "Curse" } }
    Mock.FireEvent("UNIT_AURA", "raid2")
    eq(icons[1]:IsShown(), false, "dissipables : boss secret sans effet, malédiction écartée")
    NS.db.modules.cotank.debuffFilter = "important"
    NS.Modules:Refresh("cotank")
    eq(icons[1]:IsShown(), true, "importants : boss secret gardé")
    NS.db.modules.cotank.debuffFilter = "all"
    NS.db.modules.cotank.debuffStacks = false
    Mock.debuffs.raid2 = { { icon = 1, applications = 3 } }
    NS.Modules:Refresh("cotank")
    eq(icons[1].count:GetText(), "", "compteur coupé")
    NS.Modules:SetEnabled("cotank", false)
end)

--------------------------------------------------------------------------------
-- Recherche de groupe
--------------------------------------------------------------------------------

test("recherche de groupe : sans dialogue, activation silencieuse", function()
    reset()
    _G.LFGListApplicationDialog = nil
    NS.Modules:SetEnabled("groupfinder", true)
    eq(M("groupfinder").enabled, true)
    eq(M("groupfinder").failed, nil)
    NS.Modules:SetEnabled("groupfinder", false)
end)

test("recherche de groupe : un seul rôle coché = inscription automatique", function()
    reset()
    local dialog = Mock.ShowLFGDialog({ tank = true })
    dialog:Hide()
    NS.Modules:SetEnabled("groupfinder", true)
    Mock.ShowLFGDialog({ tank = true })
    Mock.Advance(0.1)
    eq(dialog.SignUpButton.clicks, 1, "inscrit")
    Mock.ShowLFGDialog({ tank = true, healer = true })
    Mock.Advance(0.1)
    eq(dialog.SignUpButton.clicks, 0, "deux rôles : au joueur de choisir")
    Mock.shift = true
    Mock.ShowLFGDialog({ tank = true })
    Mock.Advance(0.1)
    eq(dialog.SignUpButton.clicks, 0, "Maj : à la main")
    Mock.shift = false
    NS.Modules:SetEnabled("groupfinder", false)
    Mock.ShowLFGDialog({ tank = true })
    Mock.Advance(0.1)
    eq(dialog.SignUpButton.clicks, 0, "module coupé")
end)

test("recherche de groupe : note pré-remplie à l'ouverture, mémorisée à l'inscription", function()
    reset()
    NS.Modules:SetEnabled("groupfinder", true)
    NS.db.modules.groupfinder.persistNote = true
    NS.db.modules.groupfinder.quickSignup = false
    NS.db.modules.groupfinder.note = "Tank 60 dispo"
    local dialog = Mock.ShowLFGDialog({ tank = true })
    eq(dialog.Description.EditBox:GetText(), "Tank 60 dispo", "pré-remplie")
    dialog.Description.EditBox:SetText("Heal dispo")
    dialog.SignUpButton:Click()
    eq(NS.db.modules.groupfinder.note, "Heal dispo", "mémorisée")
    NS.Modules:SetEnabled("groupfinder", false)
end)

--------------------------------------------------------------------------------
-- Curseur
--------------------------------------------------------------------------------

test("curseur : anneau seulement en combat par défaut", function()
    reset()
    NS.Modules:SetEnabled("cursor", true)
    local ring, crosshair = M("cursor"):GetFrames()
    eq(ring:IsShown(), false)
    Mock.SetCombat(true)
    eq(ring:IsShown(), true)
    eq(crosshair:IsShown(), false, "réticule coupé par défaut")
    Mock.SetCombat(false)
    -- En jeu, InCombatLockdown est encore faux pendant PLAYER_REGEN_DISABLED.
    Mock.FireEvent("PLAYER_REGEN_DISABLED")
    eq(ring:IsShown(), true, "entrée en combat, verrouillage pas encore posé")
    Mock.FireEvent("PLAYER_REGEN_ENABLED")
    eq(ring:IsShown(), false)
    NS.Modules:SetEnabled("cursor", false)
end)

--------------------------------------------------------------------------------
-- Fiche de personnage
--------------------------------------------------------------------------------

test("fiche : niveau d'objet, moyenne, repère d'enchantement", function()
    reset()
    Mock.equipped[1] = { link = "item:100:0:0", level = 60, quality = 4 }
    Mock.equipped[5] = { link = "item:200:1891:0", level = 58, quality = 3 }
    NS.db.modules.gear.missingEnchant = true
    M("gear"):Update()
    local level, warning
    for _, region in ipairs({ CharacterHeadSlot:GetRegions() }) do
        if region.text == "60" then level = region end
        if region.text == "!" then warning = region end
    end
    truthy(level and level:IsShown(), "niveau 60 affiché")
    truthy(warning and warning:IsShown(), "casque sans enchantement signalé")
    for _, region in ipairs({ CharacterChestSlot:GetRegions() }) do
        if region.text == "!" then eq(region:IsShown(), false, "plastron enchanté : pas de repère") end
    end
    eq(M("gear").EnchantID("item:200:1891:0"), 1891)
    eq(M("gear").EnchantID("item:100:0:0"), 0)
    NS.db.modules.gear.missingEnchant = false
end)

--------------------------------------------------------------------------------
-- Habillage
--------------------------------------------------------------------------------

test("icônes : recadrées au zoom réglé, coordonnées d'origine rendues au disable", function()
    reset()
    local icon = BuffFrame.auraFrames[1].Icon
    NS.db.modules.skin.iconZoomAmount = 10
    NS.Modules:Refresh("skin")
    eq(icon:GetTexCoord(), 0.1, "zoom 10 % appliqué")
    NS.Modules:SetEnabled("skin", false)
    eq(icon:GetTexCoord(), 0.07, "liseré d'origine rendu, pas une constante")
    NS.Modules:SetEnabled("skin", true)
    NS.db.modules.skin.iconZoomAmount = 8
    NS.Modules:Refresh("skin")
end)

test("infobulles : sombres, rendues au disable", function()
    reset()
    GameTooltip:Show()
    eq(GameTooltip.center[1], 0.05)
    NS.Modules:SetEnabled("skin", false)
    eq(GameTooltip.center[4], 0.8)
    GameTooltip:Show()
    eq(GameTooltip.center[4], 0.8, "plus de restyle")
    NS.Modules:SetEnabled("skin", true)
end)

test("infobulles : couleur de classe, sauf unité secrète", function()
    reset()
    Mock.units.mouseover = { guid = "Player-5", class = "ROGUE", isPlayer = true }
    Mock.ShowUnitTooltip("mouseover")
    eq(GameTooltipTextLeft1.textColor[2], 0.96)
    GameTooltipTextLeft1.textColor = nil
    Mock.secret.mouseover = true
    Mock.ShowUnitTooltip("mouseover")
    eq(GameTooltipTextLeft1.textColor, nil)
end)

test("infobulles : toutes masquées en combat si demandé", function()
    reset()
    NS.db.modules.skin.hideAllTooltipsInCombat = true
    Mock.SetCombat(true)
    GameTooltip:Show()
    eq(GameTooltip:IsShown(), false)
    Mock.SetCombat(false)
    GameTooltip:Show()
    eq(GameTooltip:IsShown(), true)
    NS.db.modules.skin.hideAllTooltipsInCombat = false
end)

--------------------------------------------------------------------------------
-- Interface épurée
--------------------------------------------------------------------------------

test("interface : tutoriels coupés, rendus au disable", function()
    reset()
    eq(Mock.cvars.showTutorials, "0", "coupés par défaut")
    NS.Modules:SetEnabled("interface", false)
    eq(Mock.cvars.showTutorials, "1", "valeur d'origine rendue")
    NS.Modules:SetEnabled("interface", true)
    eq(Mock.cvars.showTutorials, "0")
end)

test("interface : alertes de sort masquées pour la classe, opacité", function()
    reset()
    local db = NS.db.modules.interface
    db.hideProcClasses.MAGE = true
    db.alertOpacity, db.alertOpacityValue = true, 0.4
    NS.Modules:Refresh("interface")
    eq(Mock.cvars.displaySpellActivationOverlays, "0")
    eq(Mock.cvars.spellActivationOverlayOpacity, "0.40")
    db.hideProcClasses.MAGE = nil
    db.alertOpacity = false
    NS.Modules:Refresh("interface")
    eq(Mock.cvars.displaySpellActivationOverlays, "1")
    eq(Mock.cvars.spellActivationOverlayOpacity, "0.65")
end)

test("interface : messages d'erreur masqués puis rendus", function()
    reset()
    NS.db.modules.interface.hideErrors = true
    NS.Modules:Refresh("interface")
    eq(UIErrorsFrame.events.UI_ERROR_MESSAGE, nil)
    NS.db.modules.interface.hideErrors = false
    NS.Modules:Refresh("interface")
    eq(UIErrorsFrame.events.UI_ERROR_MESSAGE, true)
end)

test("cession ElvUI : les modules de cadres restent éteints, le réglage est conservé", function()
    reset()
    NS.db.modules.skin.enabled = true
    Mock.loadedAddons.ElvUI = true
    NS.Modules:DisableAll()
    NS.Modules:EnableAll()
    eq(NS.Modules:Get("skin").enabled, false, "skin cédé")
    eq(NS.Modules:Get("nameplates").enabled, false, "nameplates cédé")
    eq(NS.Modules:Get("topbar").enabled, true, "topbar indifférent à ElvUI")
    eq(NS.db.modules.skin.enabled, true, "réglage utilisateur intact")
    eq(NS.Modules:YieldedBy("skin"), "ElvUI")
    eq(NS.Modules:YieldedBy("topbar"), nil)
    eq(table.concat(NS.Modules:LoadedThirdParty(), ","), "ElvUI")
    eq(NS.Modules:SetEnabled("skin", true), "done", "le toggle répond")
    eq(NS.Modules:Get("skin").enabled, false, "mais n'active rien tant qu'ElvUI est là")
    local lines = NS.Diagnostic()
    truthy(lines[#lines]:find("ElvUI", 1, true), "diag liste l'addon tiers")
    Mock.loadedAddons = {}
    NS.Modules:DisableAll()
    NS.Modules:EnableAll()
    eq(NS.Modules:Get("skin").enabled, true, "ElvUI parti : le module revient seul")
    truthy(NS.Diagnostic()[#lines]:find("%- *$"), "diag : aucun addon tiers")
end)

--------------------------------------------------------------------------------
-- Suivi par ID
--------------------------------------------------------------------------------

test("suivi par ID : ordre gardé, aura présente allumée, absente estompée", function()
    reset()
    local tracker = M("tracker")
    eq(table.concat(tracker.ParseIDs("1126, 588 1126;6673"), ","), "1126,588,6673", "ordre, doublon retiré")
    NS.db.modules.tracker.spells = "1126, 588"
    Mock.buffs = { "Mark of the Wild" }
    Mock.knownSpells[588] = nil
    NS.Modules:SetEnabled("tracker", true)
    local icons = tracker:GetIcons()
    truthy(icons[1]:IsShown() and icons[2]:IsShown())
    eq(icons[1]:GetAlpha(), 1, "aura présente")
    eq(icons[2]:GetAlpha(), NS.db.modules.tracker.inactiveAlpha, "aura absente, sort inconnu")
    Mock.buffs = {}
    Mock.FireEvent("UNIT_AURA", "player")
    eq(icons[1]:GetAlpha(), NS.db.modules.tracker.inactiveAlpha, "aura retirée")
    NS.db.modules.tracker.spells = "588"
    NS.Modules:Refresh("tracker")
    eq(icons[2]:IsShown(), false, "liste raccourcie")
    NS.Modules:SetEnabled("tracker", false)
end)

test("movers : rappels, alertes et co-tank retirés quand leur module est coupé", function()
    reset()
    for _, pair in ipairs({ { "reminders", "reminders" }, { "alerts", "alerts" }, { "alerts", "combatTimer" },
                            { "cotank", "cotank" } }) do
        local module, key = pair[1], pair[2]
        local was = NS.Modules:Get(module).enabled
        NS.Modules:SetEnabled(module, true)
        truthy(NS.Movers.registry[key], key .. " : présent module actif")
        NS.Modules:SetEnabled(module, false)
        eq(NS.Movers.registry[key], nil, key .. " : retiré module coupé")
        NS.Modules:SetEnabled(module, was)
    end
end)

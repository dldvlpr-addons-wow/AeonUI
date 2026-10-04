-- tests/test_groupframes.lua : cadres de groupe et de raid AeonUI (étape 4).
local T = ...
local NS, test, eq, truthy, reset = T.NS, T.test, T.eq, T.truthy, T.reset
local GF = NS.Modules:Get("groupframes")
local Elements = NS.UnitFrameElements

local function Enable() NS.Modules:SetEnabled("groupframes", true) end
local function Disable() NS.Modules:SetEnabled("groupframes", false) end

test("groupe : activation, en-têtes, groupe de trois, désactivation", function()
    reset()
    Enable()
    local party, raid = GF.headers.party, GF.headers.raid
    truthy(party and raid)
    eq(party:GetAttribute("showParty"), true)
    eq(party:GetAttribute("showRaid"), false)
    eq(raid:GetAttribute("showRaid"), true)
    eq(raid:GetAttribute("groupBy"), "ASSIGNEDROLE", "raid trié par rôle")
    eq(party:GetAttribute("groupBy"), "ASSIGNEDROLE", "groupe trié par rôle")
    truthy(Mock.stateDrivers[party].visibility:find("group:party"), "state driver groupe")
    truthy(NS.Movers:Anchor("uf_party") and NS.Movers:Anchor("uf_raid"))
    truthy(NS.IsBlizzardFrameHidden("CompactRaidFrameContainer"))
    Mock.SetGroup(3, false)
    eq(#party.children, 3)
    eq(GF:GetButton("player"):GetAttribute("unit"), "player")
    local ami = GF:GetButton("party1")
    truthy(ami, "party1 stylé")
    eq(ami.health:GetValue(), 800)
    eq(ami.name:GetText(), "Ami1")
    eq(ami.health.barColor[1], RAID_CLASS_COLORS.PRIEST.r, "couleur de classe")
    truthy(ami.power:IsShown())
    Disable()
    eq(party:IsShown(), false)
    eq(NS.IsBlizzardFrameHidden("CompactRaidFrameContainer"), false)
    truthy(Mock.FindPrinted("/reload"))
end)

test("groupe : raid de dix, tri par classe", function()
    reset()
    Enable()
    Mock.SetGroup(10, true)
    eq(#GF.headers.raid.children, 10)
    truthy(GF:GetButton("raid7"))
    GF.db.raidSortBy = "CLASS"
    NS.Modules:Refresh("groupframes")
    eq(GF.headers.raid:GetAttribute("groupBy"), "CLASS")
    GF.db.raidSortBy = "ROLE"
    Disable()
end)

test("groupe : bordure dispel selon la classe du joueur, agro rouge", function()
    reset()
    Mock.units.player.class = "PRIEST"
    Enable()
    Mock.SetGroup(2, false)
    local ami = GF:GetButton("party1")
    Mock.debuffs.party1 = { { icon = "p", dispelName = "Poison" } }
    Mock.FireEvent("UNIT_AURA", "party1")
    eq(ami.border.top.color[1], NS.db.theme.border.r, "poison : prêtre ne dissipe pas")
    Mock.debuffs.party1 = { { icon = "m", dispelName = "Magic" } }
    Mock.FireEvent("UNIT_AURA", "party1")
    eq(ami.border.top.color[3], 1, "magie : bordure bleue")
    Mock.debuffs.party1 = { { icon = "s", dispelName = Mock.SetSecret("Curse") } }
    Mock.FireEvent("UNIT_AURA", "party1")
    eq(ami.border.top.color[1], NS.db.theme.border.r, "type secret : rien")
    Mock.units.party1.threat = 3
    Mock.FireEvent("UNIT_THREAT_SITUATION_UPDATE", "party1")
    truthy(ami.glow:IsShown(), "agro : liseré")
    eq(ami.glow.color[1], 0.9, "agro : rouge")
    Mock.units.player.class = "MAGE"
    Disable()
end)

test("groupe : auras au-dessus du cadre, vie verticale sur option", function()
    reset()
    Enable()
    Mock.SetGroup(2, false)
    local ami = GF:GetButton("party1")
    Mock.debuffs.party1 = { { icon = "d", duration = 0, expirationTime = 0 } }
    Mock.FireEvent("UNIT_AURA", "party1")
    truthy(ami.auras and ami.auras.buttons[1]:IsShown(), "débuff affiché")
    eq(ami.auras.buttons[1].icon.texture, "d")
    eq(ami.health.orientation, "HORIZONTAL")
    GF.db.vertical = true
    NS.Modules:Refresh("groupframes")
    eq(ami.health.orientation, "VERTICAL")
    GF.db.vertical = false
    GF.db.auras = false
    NS.Modules:Refresh("groupframes")
    eq(ami.auras:IsShown(), false)
    GF.db.auras = true
    Disable()
end)

test("groupe : portée, rôle, chef", function()
    reset()
    Enable()
    Mock.SetGroup(2, false)
    local ami = GF:GetButton("party1")
    Mock.units.party1.inRange = false
    Mock.Advance(0.3)
    eq(ami:GetAlpha(), 0.4, "hors de portée")
    Mock.units.party1.inRange = true
    Mock.Advance(0.3)
    eq(ami:GetAlpha(), 1)
    Mock.roles.party1 = "HEALER"
    Mock.units.party1.leader = true
    GF.db.leaderIcon = true
    Mock.FireEvent("PLAYER_ROLES_ASSIGNED")
    truthy(ami.role:IsShown(), "icône de rôle")
    truthy(ami.leader:IsShown(), "icône de chef")
    Mock.roles.party1 = "NONE"
    Mock.FireEvent("PLAYER_ROLES_ASSIGNED")
    eq(ami.role:IsShown(), false)
    GF.db.leaderIcon = false
    Disable()
end)

test("groupe : en combat différé, options construites", function()
    reset()
    Mock.SetCombat(true)
    eq(NS.Modules:SetEnabled("groupframes", true), "deferred")
    Mock.SetCombat(false)
    truthy(GF.enabled)
    NS.Options:BuildMain()
    Disable()
    NS.db.modules.groupframes.enabled = false
end)

test("groupe : nom tronqué (UTF-8), tri par rôle, seuil raid 10", function()
    reset()
    eq(Elements.TruncateName("Élodiebrune", 6), "Élodie")
    eq(Elements.TruncateName("Bob", 8), "Bob")
    eq(Elements.TruncateName("Bob", 0), "Bob", "0 = entier")
    Enable()
    Mock.SetGroup(3)
    Mock.units.party1.name = "Aurelienlelong"
    Mock.FireEvent("UNIT_NAME_UPDATE", "party1")
    eq(GF:GetButton("party1").name:GetText(), "Aurelienlelo", "12 caractères par défaut")
    GF.db.raidSortBy = "ROLE"
    GF.db.raidThreshold = 10
    NS.Modules:Refresh("groupframes")
    eq(GF.headers.raid:GetAttribute("groupBy"), "ASSIGNEDROLE")
    eq(GF.headers.party:GetAttribute("showRaid"), true, "seuil 10 : l'en-tête de groupe montre un petit raid")
    eq(GF.headers.party:GetAttribute("maxColumns"), 2)
    truthy(Mock.stateDrivers[GF.headers.raid].visibility:find("@raid11", 1, true), "raid visible à partir de 11 membres")
    GF.db.raidSortBy, GF.db.raidThreshold = "ROLE", 5
    NS.Modules:Refresh("groupframes")
    eq(GF.headers.party:GetAttribute("showRaid"), false)
    Disable()
end)

test("groupe : filtre de débuffs, portrait dans le cadre, cible et survol en surbrillance", function()
    reset()
    Enable()
    Mock.SetGroup(2, false)
    GF.db.auraFilter, GF.db.portrait = "boss", true
    NS.Modules:Refresh("groupframes")
    local ami = GF:GetButton("party1")
    eq(ami.cfg.auraFilter, "boss", "filtre transmis au cadre")
    truthy(ami.portrait:IsShown(), "portrait montré")
    eq(select(2, ami.portrait:GetPoint()), ami, "portrait dans le cadre")
    Mock.units.target = Mock.units.party1
    Mock.FireEvent("PLAYER_TARGET_CHANGED")
    local r = NS.Media:Accent()
    eq(ami.border.top.color[1], r, "cible : bordure d'accent")
    Mock.units.target = nil
    Mock.FireEvent("PLAYER_TARGET_CHANGED")
    eq(ami.border.top.color[1], NS.db.theme.border.r, "plus ciblé : bordure du thème")
    ami.scripts.OnEnter(ami)
    truthy(ami.hover:IsShown(), "survol")
    ami.scripts.OnLeave(ami)
    eq(ami.hover:IsShown(), false)
    GF.db.auraFilter, GF.db.portrait = "all", false
    Disable()
end)

test("groupe : clic-sort par liaison et préréglage de classe, incantation dans le cadre", function()
    reset()
    Enable()
    Mock.SetGroup(2, false)
    local clickCast = NS.Modules:Get("clickcast")
    local bindings = clickCast.db.bindings
    bindings.b1.spell, bindings.b1.mouse, bindings.b1.modifier = " Soins ", "2", "ctrl"
    NS.Modules:SetEnabled("clickcast", true)
    local ami = GF:GetButton("party1")
    eq(ami:GetAttribute("ctrl-type2"), "spell")
    eq(ami:GetAttribute("ctrl-spell2"), "Soins", "nom sans espaces autour")
    eq(ami:GetAttribute("*type2"), "togglemenu", "clic droit simple : menu gardé")
    Mock.spells[475] = "Remove Lesser Curse"
    Mock.knownSpells[475] = true
    eq(clickCast:ApplyPreset(), 1, "mage : une dissipation connue")
    eq(ami:GetAttribute("shift-spell1"), "Remove Lesser Curse")
    eq(ami:GetAttribute("ctrl-spell2"), nil, "ancienne liaison retirée")
    NS.Modules:SetEnabled("clickcast", false)
    eq(ami:GetAttribute("shift-type1"), nil, "désactivé : attributs retirés")
    Mock.spells[475], Mock.knownSpells[475] = nil, nil
    bindings.b1.spell = ""
    -- Incantation d'un membre : barre au bas de la vie, événements suivis sur option.
    GF.db.castbar = true
    NS.Modules:Refresh("groupframes")
    Mock.units.party1.casting = { name = "Soins", duration = 2 }
    Mock.FireEvent("UNIT_SPELLCAST_START", "party1")
    truthy(ami.castbar:IsShown(), "incantation montrée")
    eq(select(2, ami.castbar:GetPoint()), ami.health, "dans le cadre")
    Mock.units.party1.casting = nil
    GF.db.castbar = false
    NS.Modules:Refresh("groupframes")
    Disable()
end)

test("groupe : moteur, coins suivis et dissipation par emplacements, sans lecture d'aura", function()
    reset()
    Mock.spells[139] = "Renew"
    GF.db.indicators.BOTTOMRIGHT, GF.db.dispelMode = "139", "all"
    Enable()
    Mock.SetGroup(2, false)
    local ami = GF:GetButton("party1")
    Mock.auraContainer = true
    ami.auraSlots = nil
    NS.Modules:Refresh("groupframes")
    local engine = ami.auraSlots
    truthy(engine, "conteneur du moteur")
    eq(engine.slots.BOTTOMRIGHT.filter, "HELPFUL|PLAYER", "les miens (réglage par défaut)")
    eq(engine.slots.BOTTOMRIGHT.candidates.includeSpellIDs[139], true, "sort suivi par identifiant")
    eq(engine.slots.TOPLEFT, nil, "coin vide : pas d'emplacement")
    eq(engine.slots.BOTTOMRIGHT.button.points[1][2], ami.cornerAnchors.BOTTOMRIGHT, "collé au cadre d'ancrage")
    eq(ami.cornerAnchors.BOTTOMRIGHT.points[1][2], ami.health, "ancrage au coin de la vie")
    eq(engine.slots.dispel.filter, "HARMFUL", "dissipation de tout type")
    eq(engine.slots.dispel.candidates.includeDispelTypes.Magic, true)
    eq(ami.dispelParts.fill:IsShown(), true, "voile réglé")
    eq(ami.dispelParts.glow:IsShown(), false, "lueur coupée")
    Mock.debuffs.party1 = { { name = "Mal", icon = "x", dispelName = "Magic", spellId = 1 } }
    GF:UpdateAll(ami)
    eq(engine:GetUnit(), "party1")
    eq(ami.dispelTint:IsShown(), false, "voile maison inutilisé")
    local refreshes = #engine.calls
    Mock.FireEvent("UNIT_AURA", "party1")
    eq(#engine.calls, refreshes, "UNIT_AURA : le moteur s'en charge")
    GF.db.indicators.BOTTOMRIGHT, GF.db.dispel = "", false
    NS.Modules:Refresh("groupframes")
    eq(engine.slots.BOTTOMRIGHT.enabled, false, "coin vidé : emplacement coupé")
    eq(engine.slots.dispel.enabled, false)
    ami.auraSlots, ami.dispelParts = nil, nil
    Mock.debuffs.party1 = nil
    Disable()
end)

test("groupe : sorts suivis par coin (tous rangs), préréglage de classe, cadres extra et boss alliés", function()
    reset()
    Mock.spells[139], Mock.spells[6074] = "Renew", "Renew"
    GF.db.indicators.BOTTOMRIGHT = "139"
    Enable()
    Mock.SetGroup(2, false)
    local ami = GF:GetButton("party1")
    local indicator = ami.indicators.BOTTOMRIGHT
    truthy(indicator and not ami.indicators.TOPLEFT, "coin configuré seulement")
    eq(indicator:IsShown(), false)
    Mock.units.party1.buffs = { "Mark of the Wild", "Renew" }   -- rang 2 : identifiant 6074 ou 139, même nom
    Mock.FireEvent("UNIT_AURA", "party1")
    eq(indicator:IsShown(), true)
    Mock.units.party1.buffs = { "Mark of the Wild" }
    Mock.FireEvent("UNIT_AURA", "party1")
    eq(indicator:IsShown(), false)
    Mock.units.player.class = "DRUID"
    truthy(GF:ApplyIndicatorPreset())
    eq(GF.db.indicators.BOTTOMRIGHT, "774")
    truthy(ami.indicators.BOTTOMLEFT, "coin du préréglage créé")
    Mock.units.player.class = "WARRIOR"
    eq(GF:ApplyIndicatorPreset(), false)
    Mock.units.player.class = "MAGE"

    GF.db.extraFrames, GF.db.friendlyBoss = true, true
    NS.Modules:Refresh("groupframes")
    local extra = GF.headers.extra
    eq(extra:GetAttribute("groupFilter"), "TANK")
    eq(extra:GetAttribute("showParty"), true)
    truthy(Mock.stateDrivers[extra].visibility:find("%[group%] show"))
    GF.db.extraNames = " Arthas , Jaina, "
    NS.Modules:Refresh("groupframes")
    eq(extra:GetAttribute("nameList"), "Arthas,Jaina")
    eq(extra:GetAttribute("groupFilter"), nil)
    local boss = GF:GetButton("boss2")
    truthy(boss, "bouton boss2")
    eq(Mock.stateDrivers[boss].visibility, "[@boss2,help] show; hide")
    truthy(NS.Movers:Anchor("uf_friendlyboss") and NS.Movers:Anchor("uf_extra"))
    GF.db.friendlyBoss = false
    NS.Modules:Refresh("groupframes")
    eq(Mock.stateDrivers[boss].visibility, nil)
    eq(GF.bossHeader.holder:IsShown(), false)
    GF.db.extraFrames, GF.db.extraNames = false, ""
    for _, corner in ipairs(GF.CORNERS) do GF.db.indicators[corner] = "" end
    Mock.spells[139], Mock.spells[6074] = nil, nil
    Disable()
end)

test("groupe : mort et hors ligne, ressource selon le rôle, auras dans le cadre", function()
    reset()
    Enable()
    Mock.SetGroup(3, false)
    local ami, autre = GF:GetButton("party1"), GF:GetButton("party2")
    Mock.units.party1.dead = true
    Mock.FireEvent("UNIT_HEALTH", "party1")
    truthy(ami.stateText:IsShown(), "mort : texte")
    eq(ami.stateText:GetText(), NS.L.TEXT_STATUS_DEAD)
    eq(ami.health:GetStatusBarTexture().alpha, 0, "mort : vie vidée")
    Mock.units.party1.dead = false
    Mock.units.party1.offline = true
    Mock.FireEvent("UNIT_CONNECTION", "party1")
    eq(ami.stateText:GetText(), NS.L.TEXT_STATUS_OFFLINE)
    Mock.units.party1.offline = false
    Mock.FireEvent("UNIT_CONNECTION", "party1")
    eq(ami.stateText:IsShown(), false, "revenu")
    eq(ami.health:GetStatusBarTexture().alpha, 1)
    Mock.roles.party1, Mock.roles.party2 = "DAMAGER", "HEALER"
    Mock.FireEvent("PLAYER_ROLES_ASSIGNED")
    eq(ami.power:IsShown(), false, "dégâts : pas de ressource")
    truthy(autre.power:IsShown(), "soigneur : ressource")
    Mock.debuffs.party1 = { { icon = "a" }, { icon = "b" }, { icon = "c" }, { icon = "d" } }
    Mock.FireEvent("UNIT_AURA", "party1")
    truthy(ami.auras.buttons[3]:IsShown())
    eq(ami.auras.buttons[4]:IsShown(), false, "3 auras au plus")
    eq(ami.auras.inside, true, "dans le cadre")
    Mock.roles.party1, Mock.roles.party2 = nil, nil
    Disable()
end)

test("groupe : tailles du raid séparées, aperçu groupe et raid", function()
    reset()
    Enable()
    eq(GF.headers.raid:GetAttribute("initial-width"), NS.Pixel:Scale(GF.db.raidWidth))
    eq(GF.headers.party:GetAttribute("initial-width"), NS.Pixel:Scale(GF.db.width))
    GF:SetPreview("party")
    eq(GF.preview, "party")
    GF:SetPreview("raid")
    eq(GF.preview, "raid")
    Mock.SetCombat(true)
    Mock.FireEvent("PLAYER_REGEN_DISABLED")
    eq(GF.preview, nil, "combat : aperçu caché")
    Mock.SetCombat(false)
    Mock.FireEvent("PLAYER_REGEN_ENABLED")
    Disable()
end)

test("groupe : migration v6, anciens défauts remplacés, réglages modifiés gardés", function()
    local db = { version = 5, profiles = { A = { modules = { groupframes = {
        width = 90, height = 50, spacing = 4, nameLength = 5, raidSortBy = "GROUP", aggroStyle = "border" } } } } }
    NS.Database.Migrate(db)
    local group = db.profiles.A.modules.groupframes
    eq(group.width, nil, "ancien défaut effacé")
    eq(group.height, 50, "hauteur modifiée gardée")
    eq(group.raidHeight, 50, "hauteur modifiée reprise pour le raid")
    eq(group.nameLength, 5)
    eq(group.raidSortBy, nil)
    eq(group.aggroStyle, nil)
end)

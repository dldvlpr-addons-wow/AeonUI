-- tests/test_groupframes.lua : cadres de groupe et de raid MuscaUI (étape 4).
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
    Mock.Advance(0.05)   -- passe de groupe regroupée à la frame suivante
    truthy(ami.role:IsShown(), "icône de rôle")
    truthy(ami.leader:IsShown(), "icône de chef")
    Mock.roles.party1 = "NONE"
    Mock.FireEvent("PLAYER_ROLES_ASSIGNED")
    Mock.Advance(0.05)
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
    GF.db.raidThreshold = 25
    NS.Modules:Refresh("groupframes")
    eq(GF.headers.party:GetAttribute("maxColumns"), 5, "seuil 25 : cinq groupes de 5")
    truthy(Mock.stateDrivers[GF.headers.raid].visibility:find("@raid26", 1, true), "raid visible à partir de 26 membres")
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

test("groupe : membre qui rejoint en combat, habillé et lié à la sortie du combat", function()
    reset()
    Enable()
    Mock.SetGroup(2, false)
    local clickCast = NS.Modules:Get("clickcast")
    local bindings = clickCast.db.bindings
    bindings.b1.spell, bindings.b1.mouse, bindings.b1.modifier = "Soins", "1", "shift"
    NS.Modules:SetEnabled("clickcast", true)
    local size = #GF.headers.party.children + 1   -- bouton neuf, jamais habillé par un test précédent
    Mock.SetCombat(true)
    Mock.SetGroup(size, false)
    local child = GF.headers.party.children[size]
    truthy(child, "bouton créé par l'en-tête")
    eq(child:GetAttribute("*type1"), nil, "combat : aucun attribut posé par l'addon")
    clickCast:Apply(GF:GetButton("party1"))   -- appel direct en combat : différé, sans erreur
    Mock.SetCombat(false)
    eq(child:GetAttribute("*type1"), "target", "sortie de combat : habillé")
    eq(child:GetAttribute("shift-spell1"), "Soins", "et lié")
    truthy(GF:GetButton("party" .. (size - 1)), "dernier membre stylé")
    NS.Modules:SetEnabled("clickcast", false)
    bindings.b1.spell = ""
    Mock.SetGroup(0, false)
    Disable()
end)

test("groupe : clic-sort macro, bijou, touche au survol et cadres d'unité", function()
    reset()
    Enable()
    Mock.SetGroup(2, false)
    local clickCast = NS.Modules:Get("clickcast")
    local bindings = clickCast.db.bindings
    bindings.b1.kind, bindings.b1.spell, bindings.b1.mouse, bindings.b1.modifier = "macro", "Soin souris", "1", "alt"
    bindings.b2.kind, bindings.b2.spell, bindings.b2.mouse, bindings.b2.key = "trinket1", "", "0", "SHIFT-F"
    NS.Modules:SetEnabled("clickcast", true)
    local ami = GF:GetButton("party1")
    eq(ami:GetAttribute("alt-type1"), "macro")
    eq(ami:GetAttribute("alt-macro1"), "Soin souris", "macro par nom, sans copie du corps")
    eq(ami:GetAttribute("*type-muscacast2"), "item")
    eq(ami:GetAttribute("*item-muscacast2"), "13", "bijou 1 : emplacement équipé")
    eq(ami:GetAttribute("muscacast-key2"), "SHIFT-F")
    eq(ami:GetAttribute("type0"), nil, "souris « aucun » : pas de clic")
    truthy(ami.wrapped.OnEnter:find("SetBindingClick"), "touche liée au survol")
    eq(ami.wrapped.OnLeave, "self:ClearBindings()")
    eq(ami.wrapped.OnHide, "self:ClearBindings()", "bouton caché : touche déliée")
    -- Avertissement d'option, sans bloquer l'attribut.
    truthy(clickCast.Warning(bindings.b1), "macro absente signalée")
    Mock.macros["Soin souris"] = 1
    eq(clickCast.Warning(bindings.b1), nil)
    Mock.macros["Soin souris"] = nil
    -- Saisie : touche déjà prise par un raccourci du joueur refusée.
    eq(clickCast.CaptureKey("1"), nil, "1 = ACTIONBUTTON1")
    truthy(Mock.FindPrinted("ACTIONBUTTON1"))
    Mock.shift = true
    eq(clickCast.CaptureKey("G"), "SHIFT-G")
    eq(clickCast.CaptureKey("LSHIFT"), nil, "modificateur seul ignoré")
    Mock.shift = false
    eq(clickCast.CaptureKey("ESCAPE"), "", "Échap efface")
    -- Cadres d'unité MuscaUI_UF_* : liés, sauf case décochée.
    NS.Modules:SetEnabled("unitframes", true)
    local target = NS.Modules:Get("unitframes").frames.target
    eq(target:GetAttribute("alt-macro1"), "Soin souris", "cible liée")
    eq(target:GetAttribute("*type1"), "target", "clic simple gardé")
    clickCast.db.unitFrames = false
    NS.Modules:Refresh("clickcast")
    eq(target:GetAttribute("alt-macro1"), nil, "case décochée : cadres d'unité sans liaison")
    eq(ami:GetAttribute("alt-macro1"), "Soin souris", "groupe toujours lié")
    clickCast.db.unitFrames = true
    NS.Modules:SetEnabled("unitframes", false)
    NS.Modules:SetEnabled("clickcast", false)
    eq(ami:GetAttribute("muscacast-key2"), nil, "désactivé : touche retirée")
    bindings.b1.kind, bindings.b1.spell, bindings.b1.mouse, bindings.b1.modifier = "spell", "", "1", "shift"
    bindings.b2.kind, bindings.b2.mouse, bindings.b2.key = "spell", "1", ""
    Mock.SetGroup(0, false)
    Disable()
end)

test("groupe : moteur, coins suivis et dissipation par emplacements, sans lecture d'aura", function()
    reset()
    Mock.spells[139] = "Renew"
    GF.db.indicators[4].spells, GF.db.dispelMode = "139", "all"
    Enable()
    Mock.SetGroup(2, false)
    local ami = GF:GetButton("party1")
    Mock.auraContainer = true
    ami.auraSlots = nil
    NS.Modules:Refresh("groupframes")
    local engine = ami.auraSlots
    truthy(engine, "conteneur du moteur")
    eq(engine.slots.indicator4.filter, "HELPFUL|PLAYER", "les miens (réglage par défaut)")
    eq(engine.slots.indicator4.candidates.includeSpellIDs[139], true, "sort suivi par identifiant")
    eq(engine.slots.indicator1, nil, "indicateur vide : pas d'emplacement")
    eq(engine.slots.indicator4.button.points[1][2], ami.indicatorAnchors[4], "collé au cadre d'ancrage")
    eq(ami.indicatorAnchors[4].points[1][2], ami.health, "ancrage au point de la vie")
    eq(ami.indicatorAnchors[4].points[1][1], "BOTTOMRIGHT", "point de l'indicateur 4")
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
    GF.db.indicators[4].spells, GF.db.dispel = "", false
    NS.Modules:Refresh("groupframes")
    eq(engine.slots.indicator4.enabled, false, "indicateur vidé : emplacement coupé")
    eq(engine.slots.dispel.enabled, false)
    ami.auraSlots, ami.dispelParts = nil, nil
    Mock.debuffs.party1 = nil
    Disable()
end)

test("groupe : sorts suivis par coin (tous rangs), préréglage de classe, cadres extra et boss alliés", function()
    reset()
    Mock.spells[139], Mock.spells[6074] = "Renew", "Renew"
    GF.db.indicators[4].spells = "139"
    Enable()
    Mock.SetGroup(2, false)
    local ami = GF:GetButton("party1")
    local indicator = ami.indicators[4]
    truthy(indicator and not ami.indicators[1], "indicateur configuré seulement")
    eq(indicator:IsShown(), false)
    Mock.units.party1.buffs = { "Mark of the Wild", "Renew" }   -- rang 2 : identifiant 6074 ou 139, même nom
    Mock.FireEvent("UNIT_AURA", "party1")
    eq(indicator:IsShown(), true)
    Mock.units.party1.buffs = { "Mark of the Wild" }
    Mock.FireEvent("UNIT_AURA", "party1")
    eq(indicator:IsShown(), false)
    Mock.units.player.class = "DRUID"
    truthy(GF:ApplyIndicatorPreset())
    local hots = GF.db.indicators[1]
    truthy(hots.spells:find("774", 1, true) and hots.spells:find("139", 1, true), "soins sur la durée, tous rangs")
    eq(hots.point, "BOTTOMRIGHT", "premier indicateur libre : point du préréglage")
    eq(GF.db.indicators[4].spells, "139", "indicateur rempli gardé")
    truthy(ami.indicators[2], "indicateur du préréglage créé")
    eq(GF:ApplyIndicatorPreset("hots"), false, "même préréglage : rien en double")
    truthy(GF:ApplyIndicatorPreset("defensives"))
    eq(GF.db.indicators[3].point, "TOP", "ajouté au suivant libre")
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
    for index = 1, GF.MAX_INDICATORS do GF.db.indicators[index].spells = "" end
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
    Mock.Advance(0.05)
    eq(ami.power:IsShown(), false, "dégâts : pas de ressource")
    truthy(autre.power:IsShown(), "soigneur : ressource")
    Mock.debuffs.party1 = { { icon = "a" }, { icon = "b" }, { icon = "c" }, { icon = "d" } }
    Mock.FireEvent("UNIT_AURA", "party1")
    truthy(ami.auras.buttons[3]:IsShown())
    eq(ami.auras.buttons[4] and ami.auras.buttons[4]:IsShown() or false, false, "3 auras au plus")
    eq(ami.auras.inside, true, "dans le cadre")
    Mock.roles.party1, Mock.roles.party2 = nil, nil
    Disable()
end)

test("groupe : tailles du raid séparées, aperçu groupe et raid", function()
    reset()
    Enable()
    eq(GF.headers.raid:GetAttribute("initial-width"), NS.Pixel:Scale(GF.db.raidTiers[1].width), "seul : palier 10")
    eq(GF.headers.party:GetAttribute("initial-width"), NS.Pixel:Scale(GF.db.width))
    GF:SetPreview(5)
    eq(GF.preview, "party")
    GF:SetPreview(20)
    eq(GF.preview, "raid")
    eq(GF:GetPreview().buttons[1]:GetWidth(), NS.Pixel:Scale(GF.db.raidTiers[2].width), "aperçu de 20 : palier 25")
    Mock.SetCombat(true)
    Mock.FireEvent("PLAYER_REGEN_DISABLED")
    eq(GF.preview, nil, "combat : aperçu caché")
    Mock.SetCombat(false)
    Mock.FireEvent("PLAYER_REGEN_ENABLED")
    eq(GF.preview, "raid", "repris après le combat")
    GF:SetPreview(nil)
    Disable()
end)

test("groupe : paliers du raid comptés sur les groupes affichés, rejoués après le combat", function()
    reset()
    Enable()
    local raid, tiers = GF.headers.raid, GF.db.raidTiers
    Mock.SetGroup(30, true)
    Mock.Advance(0.05)
    eq(raid:GetAttribute("initial-width"), NS.Pixel:Scale(GF.db.raidWidth), "30 membres : au-delà de 25")
    eq(raid:GetAttribute("maxColumns"), GF.db.raidColumns)
    GF.db.raidGroups = 4
    NS.Modules:Refresh("groupframes")
    eq(raid:GetAttribute("initial-width"), NS.Pixel:Scale(tiers[2].width), "4 groupes affichés : 20 membres")
    eq(raid:GetAttribute("maxColumns"), tiers[2].columns)
    local button = GF:GetButton("raid1")
    eq(button:GetWidth(), NS.Pixel:Scale(tiers[2].width), "bouton existant retaillé")
    Mock.SetCombat(true)
    Mock.SetGroup(8, true)
    Mock.Advance(0.05)
    eq(raid:GetAttribute("initial-width"), NS.Pixel:Scale(tiers[2].width), "combat : rien ne bouge")
    Mock.SetCombat(false)
    Mock.FireEvent("PLAYER_REGEN_ENABLED")
    eq(raid:GetAttribute("initial-width"), NS.Pixel:Scale(tiers[1].width), "rejoué à la sortie du combat")
    GF.db.raidGroups = 8
    Mock.SetGroup(0, false)
    Disable()
end)

test("groupe : joueur en dernier par sortDir, sans effet avec le tri par rôle", function()
    reset()
    Enable()
    local party = GF.headers.party
    eq(party:GetAttribute("sortDir"), "ASC")
    GF.db.playerPosition = "last"
    NS.Modules:Refresh("groupframes")
    eq(party:GetAttribute("sortDir"), "ASC", "tri par rôle : le joueur reste dans son bloc")
    GF.db.partySortRole = false
    NS.Modules:Refresh("groupframes")
    eq(party:GetAttribute("sortDir"), "DESC")
    eq(GF.headers.raid:GetAttribute("sortDir"), nil, "raid : inchangé")
    GF.db.playerPosition, GF.db.partySortRole = "first", true
    Disable()
end)

test("groupe : aperçu 5 à 40, effectif cohérent et disposition de l'en-tête", function()
    reset()
    local roster = GF.PreviewRoster(40)
    local roles, groups = {}, {}
    for _, fake in ipairs(roster) do
        roles[fake.role] = (roles[fake.role] or 0) + 1
        groups[fake.group] = (groups[fake.group] or 0) + 1
    end
    eq(#roster, 40)
    eq(roles.TANK, 3, "trois tanks à 40")
    eq(roles.HEALER, 9, "neuf soigneurs à 40")
    for group = 1, 8 do eq(groups[group], 5, "groupe " .. group .. " complet") end
    eq(roster[1].group, 1, "ordre du raid : groupe 1 d'abord")
    eq(GF.PreviewRoster(5)[1].role, "TANK")

    Enable()
    GF.db.raidThreshold, GF.db.raidGroups, GF.db.raidSortBy = 5, 4, "ROLE"
    GF.db.raidUnitGrowth, GF.db.raidGroupGrowth = "UP", "RIGHT"
    NS.Modules:Refresh("groupframes")
    GF:SetPreview(40)
    local holder = GF:GetPreview()
    eq(GF.preview, "raid", "au-delà du seuil : place du raid")
    local shown = {}
    for _, button in ipairs(holder.buttons) do
        if button:IsShown() then shown[#shown + 1] = button end
    end
    eq(#shown, 20, "quatre groupes gardés")
    eq(shown[1].fake.role, "TANK", "trié par rôle")
    eq(shown[1]:GetPoint(), "BOTTOMLEFT", "croissance vers le haut : coin bas gauche")
    for _, button in ipairs(shown) do truthy(button.fake.group <= 4, "groupe filtré") end

    GF.db.raidThreshold = 25
    NS.Modules:Refresh("groupframes")
    GF:SetPreview(20)
    eq(GF.preview, "party", "sous le seuil : place du groupe")
    local buttons = GF:GetPreview().buttons
    local _, _, _, x5, y5 = buttons[5]:GetPoint()
    local _, _, _, x6, y6 = buttons[6]:GetPoint()
    eq(x5, 0)
    truthy(y5 < 0, "membres vers le bas")
    truthy(x6 > 0 and y6 == 0, "sixième membre : colonne suivante")

    NS:Fire("OPTIONS_HIDDEN")
    eq(GF.previewSize, nil, "options fermées : aperçu retiré")
    GF:SetPreview(10)
    NS:SetUnlocked(true)
    eq(GF.previewSize, 10, "mode déplacement : aperçu gardé")
    NS:SetUnlocked(false)
    eq(GF.previewSize, nil, "verrouillé, options fermées : retiré")
    GF.db.raidThreshold, GF.db.raidGroups, GF.db.raidSortBy = 5, 8, "GROUP"
    GF.db.raidUnitGrowth, GF.db.raidGroupGrowth = "DOWN", "RIGHT"
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

test("groupe : UNIT_POWER_UPDATE rafraîchit la puissance seule, sans repeindre le cadre", function()
    reset()
    Enable()
    Mock.SetGroup(2, false)
    local updatePower, updateAll, powers, alls = Elements.UpdatePower, GF.UpdateAll, 0, 0
    Elements.UpdatePower = function(button, ...) if button.unit == "party1" then powers = powers + 1 end return updatePower(button, ...) end
    GF.UpdateAll = function(self, button, ...) if button.unit == "party1" then alls = alls + 1 end return updateAll(self, button, ...) end
    Mock.FireEvent("UNIT_POWER_UPDATE", "party1")
    Elements.UpdatePower, GF.UpdateAll = updatePower, updateAll
    truthy(powers > 0, "puissance relue")
    eq(alls, 0, "pas de repeinture complète")
    Disable()
end)

test("groupe : migration v10, coins en indicateurs, taille de raid en paliers, filtre en cases", function()
    local db = { version = 9, profiles = { A = { modules = { groupframes = {
        indicators = { TOPLEFT = "139", BOTTOMRIGHT = "774" }, raidWidth = 90, raidHeight = 40, auraFilter = "boss" } } } } }
    NS.Database.Migrate(db)
    local group = db.profiles.A.modules.groupframes
    eq(group.indicators[1].spells, "139")
    eq(group.indicators[1].point, "TOPLEFT")
    eq(group.indicators[4].spells, "774")
    eq(group.indicators[4].point, "BOTTOMRIGHT")
    eq(group.indicators.TOPLEFT, nil, "anciennes clés retirées")
    eq(group.raidTiers[1].width, 90, "taille modifiée reprise par les paliers")
    eq(group.raidTiers[2].height, 40)
    eq(group.debuffGroups.boss.enabled, true, "filtre boss : case boss")
    eq(group.debuffGroups.control.enabled, false)
end)

test("groupe : catalogue des préréglages, identifiants entiers et uniques", function()
    for _, name in ipairs(GF.PRESET_ORDER) do
        for _, entry in ipairs(GF.INDICATOR_PRESETS[name]) do
            local seen = {}
            for id in entry.spells:gmatch("[^,%s]+") do
                local number = tonumber(id)
                truthy(number and number > 0 and number == math.floor(number), name .. " : identifiant " .. id)
                eq(seen[number], nil, name .. " : doublon " .. id)
                seen[number] = true
            end
            truthy(GF.POINTS and entry.point, name .. " : point")
        end
    end
    -- Nombre d'identifiants (rangs et auras) par entrée : un rang retiré par erreur fait échouer.
    local expected = { hots = { 21, 19 }, defensives = { 11 }, externals = { 8 }, raidCooldowns = { 6 }, movement = { 8 } }
    for name, counts in pairs(expected) do
        for index, count in ipairs(counts) do
            local _, found = GF.INDICATOR_PRESETS[name][index].spells:gsub("%d+", "")
            eq(found, count, name .. " " .. index .. " : nombre d'identifiants")
        end
    end
    truthy(GF.INDICATOR_PRESETS.defensives[1].spells:find("12976", 1, true), "Dernier rempart : identifiant de l'aura")
end)

test("groupe : débuffs par cases chaînées par négation, case ancrée en emplacement", function()
    Mock.auraContainer = true
    local engine = CreateFrame("AuraContainer")
    engine.declared = {}
    local frame = { auras = { engine = engine, groupSizes = { control = 22, boss = 20, dispellable = 18,
        nonPlayer = 18, duration = 18 } }, health = CreateFrame("Frame"), overlay = CreateFrame("Frame") }
    local groups = { control = { enabled = true, point = "CENTER" }, boss = { enabled = false },
        dispellable = { enabled = true, point = "flow", max = 3 }, nonPlayer = { enabled = true, point = "flow", max = 2 },
        duration = { enabled = true, point = "flow", max = 3 } }
    Elements.ConfigureDebuffGroups(frame, groups, "all", {}, 1)
    eq(engine.slots.controlSlot.filter, "HARMFUL|CROWD_CONTROL", "contrôle ancré : emplacement")
    eq(engine.slots.controlSlot.button.points[1][2], frame.debuffAnchors.control)
    eq(engine.groups.control, nil, "contrôle ancré : pas de rangée")
    eq(engine.groups.boss, nil, "case décochée : rien")
    eq(engine.groups.dispellable.filter, "HARMFUL|RAID|!CROWD_CONTROL", "contrôle exclu ensuite")
    eq(engine.groups.nonPlayer.options.candidateFilters.isFromPlayerOrPlayerPet, false)
    eq(engine.groups.duration.filter, "HARMFUL|!CROWD_CONTROL|!RAID", "cases précédentes exclues")
    eq(engine.groups.duration.options.candidateFilters.isFromPlayerOrPlayerPet, true, "non-joueur exclu")
    eq(engine.groups.duration.options.candidateFilters.isBossAura, nil, "boss décoché : pas exclu")
    eq(engine.groups.nonPlayer.options.maxFrameCount, 2)
    Mock.auraContainer = nil
end)

test("groupe : préréglage du filtre unique coche les cases", function()
    GF.ApplyAuraFilterPreset("boss")
    eq(GF.db.debuffGroups.boss.enabled, true)
    eq(GF.db.debuffGroups.control.enabled, false)
    GF.ApplyAuraFilterPreset("all")
    for _, key in ipairs(Elements.DEBUFF_GROUPS) do eq(GF.db.debuffGroups[key].enabled, true, key) end
end)

test("groupe : cible du membre, bouton sécurisé enfant, nom et vie de <unité>target", function()
    reset()
    Enable()
    Mock.SetGroup(2, false)
    local ami = GF:GetButton("party1")
    local frame = ami.memberTarget
    truthy(frame, "bouton créé hors combat")
    eq(frame:GetAttribute("useparent-unit"), true)
    eq(frame:GetAttribute("unitsuffix"), "target")
    eq(frame:GetAttribute("*type1"), "target")
    eq(frame.points[1][2], ami, "ancré au bouton du membre")
    Mock.units.party1target = { name = "Ogre", health = 30, healthMax = 60 }
    Mock.FireEvent("UNIT_TARGET", "party1")
    eq(frame.name.text, "Ogre")
    Mock.units.party1target.health = 20
    Mock.FireEvent("UNIT_HEALTH", "party1target")   -- jamais envoyé par le client : ignoré
    eq(frame.health:GetValue(), 30, "jeton composé : pas d'événement")
    GF.db.range = false
    GF:UpdateRangeTicker()
    Mock.Advance(0.3)
    eq(frame.health:GetValue(), 20, "vie de la cible relue par le ticker, portée coupée")
    GF.db.range = true
    Mock.units.party1target = nil
    GF.db.memberTarget = false
    NS.Modules:Refresh("groupframes")
    eq(frame:IsShown(), false, "option coupée : caché")
    GF.db.memberTarget = true
    Mock.units.party1target = { name = "Ogre", health = 30, healthMax = 60 }
    NS.Modules:Refresh("groupframes")
    eq(frame:IsShown(), true, "option remise : affiché")
    Mock.SetGroup(4, true)
    Mock.FireEvent("GROUP_ROSTER_UPDATE")
    Mock.Advance(0.1)
    eq(frame:IsShown(), false, "en raid : caché, même sous l'en-tête de groupe")
    Mock.units.party1target = nil
    Mock.SetGroup(1, false)
    Disable()
end)

test("groupe : icônes des buffs de groupe manquants, détection de Reminders, cachées en combat", function()
    reset()
    Mock.units.player.class = "PRIEST"
    Mock.spells[1243], Mock.spells[21562] = "Power Word: Fortitude", "Prayer of Fortitude"
    Mock.knownSpells[1243] = true
    Enable()
    Mock.SetGroup(2, false)
    local ami = GF:GetButton("party1")
    Mock.FireEvent("UNIT_AURA", "party1")
    truthy(ami.missingIcons[1] and ami.missingIcons[1]:IsShown(), "robustesse manquante")
    Mock.units.party1.buffs = { "Prayer of Fortitude" }
    Mock.FireEvent("UNIT_AURA", "party1")
    eq(ami.missingIcons[1]:IsShown(), false, "version de groupe acceptée")
    Mock.units.party1.buffs = nil
    Mock.FireEvent("UNIT_AURA", "party1")
    Mock.SetCombat(true)
    Mock.FireEvent("PLAYER_REGEN_DISABLED")
    eq(ami.missingIcons[1]:IsShown(), false, "combat : rien")
    Mock.SetCombat(false)
    Mock.FireEvent("PLAYER_REGEN_ENABLED")
    eq(ami.missingIcons[1]:IsShown(), true, "sortie de combat : relu")
    Mock.units.party1.hidden = true
    Mock.FireEvent("UNIT_AURA", "party1")
    eq(ami.missingIcons[1]:IsShown(), false, "hors de vue : inconnu, pas d'icône")
    Mock.units.party1.hidden = nil
    NS.db.modules.reminders.coverageRules.fortitude = false
    Mock.FireEvent("UNIT_AURA", "party1")
    eq(ami.missingIcons[1]:IsShown(), false, "famille décochée")
    NS.db.modules.reminders.coverageRules.fortitude = true
    Mock.knownSpells[1243] = nil
    Mock.FireEvent("SPELLS_CHANGED")
    eq(ami.missingIcons[1]:IsShown(), false, "sort oublié : plus d'icône")
    Mock.knownSpells[1243] = true
    Mock.FireEvent("SPELLS_CHANGED")
    eq(ami.missingIcons[1]:IsShown(), true, "sort appris : icône sans attendre UNIT_AURA")
    Mock.knownSpells[1243], Mock.spells[1243], Mock.spells[21562] = nil, nil, nil
    Mock.units.player.class = "MAGE"
    Mock.SetGroup(1, false)
    Disable()
end)

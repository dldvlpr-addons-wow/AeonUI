-- tests/test_actionbars.lua : barres d'action AeonUI (étape 5).
local T = ...
local NS, test, eq, truthy, reset = T.NS, T.test, T.eq, T.truthy, T.reset
local AB = NS.Modules:Get("actionbars")

local function Enable() NS.Modules:SetEnabled("actionbars", true) end
local function Disable() NS.Modules:SetEnabled("actionbars", false) end

test("barres : activation crée trois barres de douze boutons Blizzard, pagine, lie les touches", function()
    reset()
    Enable()
    local bar1 = AB:GetBar(1)
    truthy(bar1 and bar1:IsShown())
    eq(bar1.template, "SecureFrameTemplate")
    eq(#bar1.buttons, 12)
    eq(bar1.buttons[3].template, "ActionBarButtonTemplate")
    eq(bar1.buttons[3]:GetID(), 3)
    eq(bar1.buttons[3].buttonType, "ACTIONBUTTON")
    eq(bar1.buttons[3]:GetAttribute("actionpage"), 1)
    eq(AB:GetBar(2).buttons[1]:GetAttribute("actionpage"), 6, "barre 2 = page 6 (BottomLeft)")
    eq(AB:GetBar(2).buttons[1].buttonType, "MULTIACTIONBAR1BUTTON")
    truthy(Mock.attributeDrivers[bar1.buttons[1]].actionpage:find("bonusbar:1"), "pilote de page par bouton")
    eq(Mock.attributeDrivers[AB:GetBar(2).buttons[1]], nil, "barre 2 : page fixe")
    eq(Mock.overrideBindings[bar1]["1"], "AeonUI_Bar1Button1")
    eq(Mock.overrideBindings[AB:GetBar(2)]["F1"], "AeonUI_Bar2Button1")
    eq(AB:GetBar(4), nil, "barre 4 coupée par défaut")
    truthy(NS.IsBlizzardFrameHidden("MainActionBar"))
    eq(MainActionBar:GetParent(), UIParent, "barre principale jamais reparentée (Edit Mode)")
    eq(MainActionBar:GetAlpha(), 0)
    MainActionBar:Show()
    eq(MainActionBar:GetAlpha(), 0, "Edit Mode la remontre : alpha réassuré")
    truthy(NS.IsBlizzardFrameHidden("MultiBarBottomLeft"))
    eq(MultiBarBottomLeft:GetParent(), AeonUI_Hidden, "autres barres sous le cadre caché")
    truthy(NS.Movers:Anchor("bar1"))
    Disable()
    eq(bar1:IsShown(), false)
    eq(Mock.overrideBindings[bar1], nil)
    eq(NS.IsBlizzardFrameHidden("MainActionBar"), false)
    eq(MainActionBar:GetAlpha(), 1)
    truthy(Mock.FindPrinted("/reload"))
end)

test("barres : survol en combat sans SetAttribute protégé, infobulle gardée", function()
    reset()
    Enable()
    local button = AB:GetBar(1).buttons[1]
    local texture = button.NewActionTexture
    Mock.SetCombat(true)
    button:GetScript("OnEnter")(button)
    truthy(button.tooltipShown, "infobulle")
    eq(button.NewActionTexture, texture, "texture rendue après le survol")
    Mock.SetCombat(false)
    button.pressAndHoldAction = nil
    button:GetScript("OnEnter")(button)
    eq(button.pressAndHoldAction, false, "hors combat : mise à jour Blizzard complète")
end)

test("barres : glisser-déposer par gestionnaire sécurisé, verrou des barres respecté", function()
    reset()
    Enable()
    local button = AB:GetBar(2).buttons[3]
    Mock.cvars.lockActionBars = "1"
    Mock.FireEvent("CVAR_UPDATE", "lockActionBars")
    local function Run(script, kind, modified)
        local saved = _G.IsModifiedClick
        _G.IsModifiedClick = function() return modified end
        local body = assert(button.wrapped and button.wrapped[script], script .. " enveloppé")
        local chunk = assert((loadstring or load)("local self, button, kind, value = ... " .. body))
        local results = { chunk(button, "LeftButton", kind, 1) }
        _G.IsModifiedClick = saved
        return results[1], results[2]
    end
    local kind, slot = Run("OnReceiveDrag", "spell")
    eq(kind, "action")
    eq(slot, 63, "barre 2 = page 6, bouton 3")
    eq(Run("OnReceiveDrag", nil), false, "curseur vide : rien")
    eq(Run("OnDragStart", nil, false), false, "barres verrouillées : pas de prise")
    eq(select(2, Run("OnDragStart", nil, true)), 63, "touche de prise : autorisée")
    Mock.cvars.lockActionBars = "0"
    Mock.FireEvent("CVAR_UPDATE", "lockActionBars")
    eq(select(2, Run("OnDragStart", nil, false)), 63, "déverrouillées")
    Mock.cvars.lockActionBars = nil
end)

test("barres : Update en combat (OnShow, page) sans SetAttribute, attribut reposé à la sortie", function()
    reset()
    Enable()
    local button = AB:GetBar(1).buttons[1]
    Mock.SetCombat(true)
    button.pressAndHoldAction = nil
    button:Update()
    eq(button.pressAndHoldAction, nil, "rien posé en combat")
    Mock.SetCombat(false)
    local onEvent = button.OnEvent
    button.OnEvent = function(self, event, ...) self:Update() return onEvent(self, event, ...) end
    Mock.FireEvent("PLAYER_REGEN_ENABLED")
    button.OnEvent = onEvent
    eq(button.pressAndHoldAction, false, "reposé à la sortie du combat")
end)

test("barres : disposition boutons par ligne, boutons cachés au-delà du compte", function()
    reset()
    Enable()
    local db = NS.db.modules.actionbars.bars[1]
    db.buttons, db.perRow, db.size, db.spacing = 6, 3, 30, 2
    NS.Modules:Refresh("actionbars")
    local bar = AB:GetBar(1)
    eq(bar:GetWidth(), 3 * 30 + 2 * 2)
    eq(bar:GetHeight(), 2 * 30 + 2)
    truthy(bar.buttons[6]:IsShown())
    eq(bar.buttons[7]:IsShown(), false)
    -- Taille par l'échelle (modèle de 36 dans le mock) : icône et bordure suivent le bouton.
    local button = bar.buttons[5]
    local scale = button:GetScale()
    eq(scale, 30 / 36, "échelle = taille voulue / taille native")
    local _, _, _, x, y = button:GetPoint()
    truthy(math.abs(x * scale - 32) < 1e-9 and math.abs(y * scale + 32) < 1e-9, "position en unités de la barre")
    db.buttons, db.perRow, db.size, db.spacing = 12, 12, 36, 4
    Disable()
end)

test("barres : rebind sur UPDATE_BINDINGS hors combat, cède à Bartender4", function()
    reset()
    Enable()
    Mock.bindings.ACTIONBUTTON1 = "Q"
    Mock.SetCombat(true)
    Mock.FireEvent("UPDATE_BINDINGS")
    eq(Mock.overrideBindings[AB:GetBar(1)]["1"], "AeonUI_Bar1Button1", "en combat : inchangé")
    Mock.SetCombat(false)
    eq(Mock.overrideBindings[AB:GetBar(1)]["Q"], "AeonUI_Bar1Button1", "après le combat : relié")
    Mock.bindings.ACTIONBUTTON1 = "1"
    NS.Options:BuildMain()
    Disable()
    Mock.loadedAddons.Bartender4 = true
    Enable()
    eq(AB.enabled, false)
    Mock.loadedAddons.Bartender4 = nil
    NS.db.modules.actionbars.enabled = false
end)

test("barres : boutons retirés des diffuseurs Blizzard, recharge peinte sans valeur secrète", function()
    reset()
    Enable()
    local button = AB:GetBar(1).buttons[1]
    for _, frame in ipairs(ActionBarButtonEventsFrame.frames) do truthy(frame ~= button, "hors du diffuseur Blizzard") end
    for _, frame in ipairs(ActionBarActionEventsFrame.frames) do truthy(frame ~= button, "hors du diffuseur d'unité") end
    local blizzardSetCooldown = rawget(button.cooldown, "SetCooldown")
    -- Sans objet durée : SetCooldown seulement sur des valeurs connues.
    Mock.actionCooldown = { start = 10, duration = 5 }
    Mock.FireEvent("ACTIONBAR_UPDATE_COOLDOWN")
    eq(button.lastEvent, "ACTIONBAR_UPDATE_COOLDOWN", "événement dispatché par AeonUI")
    eq(button.action, 1)
    eq(button.cooldown.painted[1], 10)
    Mock.actionCooldown = { start = Mock.SetSecret(20), duration = 5 }
    Mock.FireEvent("ACTIONBAR_UPDATE_COOLDOWN")
    eq(button.cooldown.painted, nil, "valeur secrète : recharge effacée, aucune erreur")
    eq(Mock.FindPrinted("Blizzard"), nil, "aucun échec signalé")
    eq(rawget(button.cooldown, "SetCooldown"), blizzardSetCooldown, "SetCooldown ombré à demeure, rendu tel quel après le dispatch")
    eq(button.UpdateCooldown, nil)
    -- Hors de notre dispatch (fin d'animation d'incantation) : valeur secrète repeinte par nous.
    Mock.actionCooldown = { start = 30, duration = 5 }
    button.cooldown:SetCooldown(Mock.SetSecret(31), 5)
    eq(button.cooldown.painted[1], 30, "secret hors dispatch : relu, jamais transmis")
    button.cooldown:SetCooldown(40, 5)
    eq(button.cooldown.painted[1], 40, "valeur connue : SetCooldown d'origine")
    Mock.actionCooldown = { start = Mock.SetSecret(20), duration = 5 }
    -- Avec l'API Midnight : objet durée transmis tel quel.
    local object = { secret = true }
    _G.C_ActionBar = {
        GetActionCooldown = function() return { isActive = true } end,
        GetActionCooldownDuration = function() return object end,
    }
    Mock.FireEvent("ACTIONBAR_UPDATE_COOLDOWN")
    eq(button.cooldown.painted, object)
    _G.C_ActionBar.GetActionCooldown = function() return { isActive = false } end
    Mock.FireEvent("ACTIONBAR_UPDATE_COOLDOWN")
    eq(button.cooldown.painted, nil)
    _G.C_ActionBar = nil
    Disable()
end)

test("barres : réinscription par le modèle Blizzard retirée à chaque dispatch", function()
    reset()
    Enable()
    local button = AB:GetBar(1).buttons[1]
    local rangeTable = {}
    _G.ActionBarButtonRangeCheckFrame = { RegisterFrame = function(_, action, frame) rangeTable[frame] = action end }
    local original = button.OnEvent
    button.OnEvent = function(self, ...)
        ActionBarActionEventsFrame.frames[self] = self            -- Update : diffuseur à clés
        self:RegisterActionBarButtonCheckFrames(1)                 -- UpdateAction : portée par action
        return original(self, ...)
    end
    Mock.FireEvent("ACTIONBAR_SLOT_CHANGED")
    eq(ActionBarActionEventsFrame.frames[button], nil, "retiré du diffuseur à clés")
    eq(rangeTable[button], nil, "jamais inscrit dans la table de portée Blizzard")
    button.OnEvent = original
    _G.ActionBarButtonRangeCheckFrame = nil
    Disable()
end)

test("barres : ACTIONBAR_SLOT_CHANGED différé en combat, rejoué à la sortie", function()
    reset()
    Enable()
    local button = AB:GetBar(1).buttons[1]
    Mock.SetCombat(true)
    button.lastEvent = nil
    Mock.FireEvent("ACTIONBAR_SLOT_CHANGED")
    eq(button.lastEvent, nil, "pas dispatché en combat")
    Mock.FireEvent("ACTIONBAR_UPDATE_COOLDOWN")
    eq(button.lastEvent, "ACTIONBAR_UPDATE_COOLDOWN", "les autres passent")
    Mock.SetCombat(false)
    eq(button.lastEvent, "PLAYER_ENTERING_WORLD", "mise à jour complète à la sortie")
    Disable()
end)

test("barres : micro-menu et sacs sur movers, cachés sur option, rendus au disable", function()
    reset()
    Enable()
    local _, relTo = MicroMenuContainer:GetPoint()
    eq(relTo, AeonUI_Holder_micromenu, "micro-menu posé sur son support")
    eq(MicroMenuContainer:GetParent(), UIParent, "jamais reparenté")
    truthy(NS.Movers:Anchor("micromenu") and NS.Movers:Anchor("bags"))
    local _, stanceHolder = StanceBar:GetPoint()
    eq(stanceHolder, AeonUI_Holder_stance, "barre de posture sur son support")
    truthy(NS.Movers:Anchor("stance") and NS.Movers:Anchor("pet"))
    MicroMenuContainer:ClearAllPoints()
    MicroMenuContainer:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 0)
    local _, again = MicroMenuContainer:GetPoint()
    eq(again, AeonUI_Holder_micromenu, "Edit Mode le replace : le hook reprend la main")
    NS.db.modules.actionbars.bags = "hide"
    NS.Modules:Refresh("actionbars")
    truthy(NS.IsRegionHidden(BagsBar))
    eq(AeonUI_Holder_bags:IsShown(), false)
    NS.db.modules.actionbars.bags = "move"
    Disable()
    eq(NS.IsRegionHidden(BagsBar), false)
    eq(AeonUI_Holder_micromenu:IsShown(), false)
end)

test("barres d'action : micro-menu et sacs au style AeonUI, sur mover ou dans la barre du haut", function()
    reset()
    local character = CreateFrame("Button", "CharacterMicroButton", UIParent)
    _G.MICRO_BUTTONS = { "CharacterMicroButton", "AbsentMicroButton" }
    local backpack = CreateFrame("Button", "MainMenuBarBackpackButton", UIParent)
    local AB = NS.Modules:Get("actionbars")
    NS.db.modules.actionbars.microMenu = "aeonui"
    NS.db.modules.actionbars.bags = "topbar"
    NS.Modules:SetEnabled("actionbars", true)
    local micro, bags = AB.GetStyled("micromenu"), AB.GetStyled("bags")
    truthy(micro and micro:IsShown(), "rangée AeonUI du micro-menu")
    eq(micro.buttons[1]:GetAttribute("type"), "click")
    eq(micro.buttons[1]:GetAttribute("clickbutton"), character, "relaie le bouton Blizzard")
    eq(micro.buttons[2], nil, "bouton absent ignoré")
    truthy(NS.IsRegionHidden("MicroMenuContainer"), "cadre Blizzard caché")
    local topBar = NS.Modules:Get("topbar"):GetFrame()
    eq(bags:GetParent(), topBar, "sacs dans la barre du haut")
    eq(bags.buttons[1]:GetAttribute("clickbutton"), backpack)
    NS.Modules:SetEnabled("topbar", false)
    eq(bags:GetParent(), UIParent, "barre du haut coupée : sacs rendus à leur mover")
    truthy(bags:IsShown(), "sacs toujours visibles")
    NS.Modules:SetEnabled("topbar", true)
    eq(bags:GetParent(), topBar, "barre du haut rallumée : sacs y reviennent")
    NS.db.modules.actionbars.microMenu = "keep"
    NS.Modules:Refresh("actionbars")
    eq(micro:IsShown(), false, "style Blizzard : rangée retirée")
    eq(NS.IsRegionHidden("MicroMenuContainer"), false, "cadre Blizzard rendu")
    NS.Modules:SetEnabled("actionbars", false)
    eq(bags:IsShown(), false, "module coupé : rangée retirée")
    NS.db.modules.actionbars.microMenu, NS.db.modules.actionbars.bags = "move", "move"
    _G.MICRO_BUTTONS = nil
end)

test("barres d'action : micro-menu AeonUI sans MICRO_BUTTONS (moteur 12.x)", function()
    reset()
    _G.MICRO_BUTTONS = nil
    local menu = _G.MicroMenu or CreateFrame("Frame", "MicroMenu", MicroMenuContainer)
    local spells = CreateFrame("Button", "SpellbookMicroButton", menu)
    spells.layoutIndex = 2
    local quests = CreateFrame("Button", "QuestLogMicroButton", menu)
    quests.layoutIndex = 1
    NS.db.modules.actionbars.microMenu = "aeonui"
    NS.Modules:SetEnabled("actionbars", true)
    local micro = NS.Modules:Get("actionbars").GetStyled("micromenu")
    eq(micro.buttons[1]:GetAttribute("clickbutton"), quests, "ordre de la disposition Blizzard")
    eq(micro.buttons[2]:GetAttribute("clickbutton"), spells)
    NS.Modules:SetEnabled("actionbars", false)
    NS.db.modules.actionbars.microMenu = "move"
    spells:Hide() quests:Hide()
end)

test("barres d'action : visibilité commune dans le driver, survol lié entre barres « au survol »", function()
    reset()
    local db = NS.db.modules.actionbars
    db.bars[2].mouseover, db.bars[3].mouseover = true, true
    db.bars[2].visibility = NS.Visibility.Spec({ combat = "yes" })
    Enable()
    local bar1, bar2, bar3 = AB:GetBar(1), AB:GetBar(2), AB:GetBar(3)
    eq(Mock.stateDrivers[bar2].visibility, "[petbattle] hide; [combat] show; hide")
    truthy(Mock.stateDrivers[bar1].visibility:find("^%[overridebar%]"), "barre 1 : barres spéciales d'abord")
    Mock.mouseOver = bar2
    Mock.Advance(0.2)
    eq(bar2:GetAlpha(), 1, "survolée")
    eq(bar3:GetAlpha(), 0, "survol non lié")
    db.linkedMouseover = true
    Mock.Advance(0.2)
    eq(bar3:GetAlpha(), 1, "survol lié")
    Mock.mouseOver = nil
    Disable()
    db.bars[2].mouseover, db.bars[3].mouseover, db.linkedMouseover = false, false, false
    db.bars[2].visibility = NS.Visibility.Spec()
end)

test("barres : style AeonUI, recharge grisée hors GCD, lueur de proc, barre 7 sur la page 14", function()
    reset()
    local db = NS.db.modules.actionbars
    db.iconStyle, db.classBorder, db.procGlow = "aeon", true, "pixel"
    db.bars[7].enabled = true
    local cooldown = { isActive = true, isOnGCD = false, duration = 8 }
    _G.C_ActionBar = { GetActionCooldown = function() return cooldown end }
    local overlayed = false
    _G.GetActionInfo = function() return "spell", 133 end
    _G.IsSpellOverlayed = function() return overlayed end
    Enable()
    local button = AB:GetBar(1).buttons[1]
    eq(button.icon.texCoord[1], db.iconZoom, "icône recadrée")
    truthy(button.aeonBorder.top:IsShown(), "bordure fine")
    eq(button.aeonBorder.top.color[1], RAID_CLASS_COLORS.MAGE.r, "couleur de classe")
    eq(button.icon:IsDesaturated(), true, "recharge : icône grisée")
    cooldown = { isActive = true, isOnGCD = true, duration = 1.5 }
    Mock.FireEvent("ACTIONBAR_UPDATE_COOLDOWN")
    eq(button.icon:IsDesaturated(), false, "recharge globale : pas grisée")
    cooldown = { isActive = true, duration = 1.5 }
    Mock.FireEvent("ACTIONBAR_UPDATE_COOLDOWN")
    eq(button.icon:IsDesaturated(), false, "recharge globale sans isOnGCD : pas grisée")
    cooldown = { isActive = true, duration = Mock.SetSecret(8) }
    Mock.FireEvent("ACTIONBAR_UPDATE_COOLDOWN")
    eq(button.icon:IsDesaturated(), false, "durée secrète, isOnGCD inconnu : pas grisée")
    cooldown = { isActive = true, isOnGCD = false, duration = Mock.SetSecret(8) }
    Mock.FireEvent("ACTIONBAR_UPDATE_COOLDOWN")
    eq(button.icon:IsDesaturated(), true, "durée secrète, vraie recharge : grisée")
    Mock.secret[8] = nil
    cooldown = { isActive = Mock.SetSecret(true), isOnGCD = false }
    Mock.FireEvent("ACTIONBAR_UPDATE_COOLDOWN")
    eq(button.icon:IsDesaturated(), false, "secret : icône intacte")
    Mock.secret[true] = nil   -- le mock marque la valeur elle-même
    overlayed = true
    Mock.FireEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
    eq(NS.Glow.Current(button), "pixel", "proc : lueur AeonUI")
    overlayed = false
    Mock.FireEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
    eq(NS.Glow.Current(button), nil)
    local bar7 = AB:GetBar(7)
    eq(bar7.buttons[1]:GetAttribute("actionpage"), 14, "barre 7 = page 14")
    eq(bar7.buttons[1].buttonType, "MULTIACTIONBAR6BUTTON")
    db.iconStyle = "blizzard"
    NS.Modules:Refresh("actionbars")
    eq(button.icon.texCoord[1], 0, "style Blizzard rendu")
    eq(button.aeonBorder.top:IsShown(), false)
    Disable()
    db.classBorder, db.procGlow, db.bars[7].enabled = false, "blizzard", false
    _G.C_ActionBar, _G.GetActionInfo, _G.IsSpellOverlayed = nil, nil, nil
end)

test("barres : inscription Blizzard hors dispatch retirée aussitôt, jumeaux cachés hors de tout diffuseur", function()
    reset()
    local twin = CreateFrame("CheckButton", "MultiBarBottomLeftButton3", MultiBarBottomLeft)
    tinsert(ActionBarButtonEventsFrame.frames, twin)
    MultiBarBottomLeft.actionButtons = { twin }
    Enable()
    local button = AB:GetBar(1).buttons[1]
    ActionBarActionEventsFrame:RegisterFrame(button)             -- Update Blizzard : page changée en combat
    for _, frame in pairs(ActionBarActionEventsFrame.frames) do truthy(frame ~= button, "notre bouton retiré sur place") end
    ActionBarActionEventsFrame:RegisterFrame(twin)
    for _, frame in pairs(ActionBarActionEventsFrame.frames) do truthy(frame ~= twin, "jumeau caché retiré") end
    for _, frame in pairs(ActionBarButtonEventsFrame.frames) do truthy(frame ~= twin, "diffuseur principal : jumeau retiré") end
    ActionBarButtonEventsFrame:RegisterFrame(twin)
    for _, frame in pairs(ActionBarButtonEventsFrame.frames) do truthy(frame ~= twin, "réinscription retirée") end
    ActionBarActionEventsFrame.frames[twin] = twin                -- inscription directe, sans RegisterFrame
    Mock.FireEvent("ACTIONBAR_UPDATE_COOLDOWN")
    eq(ActionBarActionEventsFrame.frames[twin], nil, "balayé au dispatch suivant")
    Disable()
    MultiBarBottomLeft.actionButtons = nil
    for i = #ActionBarButtonEventsFrame.frames, 1, -1 do
        if ActionBarButtonEventsFrame.frames[i] == twin then tremove(ActionBarButtonEventsFrame.frames, i) end
    end
end)

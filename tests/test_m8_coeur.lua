-- tests/test_m8_coeur.lua : lot M8 (cœur) : visibilité au repos et en véhicule, couleurs de classe et de
-- ressource du thème, cycle des cadres superposés, réglages graphiques bas, police sur tout le texte.
local T = ...
local NS, test, eq, truthy, reset = T.NS, T.test, T.eq, T.truthy, T.reset
local Visibility, Movers = NS.Visibility, NS.Movers

test("visibilité : repos et véhicule lus en Lua, sans condition macro", function()
    reset()
    Mock.resting, Mock.inVehicle = true, false
    local state = Visibility.State()
    eq(state.resting, true); eq(state.vehicle, false)
    Mock.resting, Mock.inVehicle = false, true
    state = Visibility.State()
    eq(state.resting, false); eq(state.vehicle, true)
    local spec = Visibility.Spec({ resting = "yes", vehicle = "no" })
    truthy(Visibility.Evaluate(spec, { resting = true, vehicle = false }))
    eq(Visibility.Evaluate(spec, { resting = true, vehicle = true }), false, "en véhicule : caché")
    eq(Visibility.Macro(spec), nil, "aucune macro")
    eq(Visibility.MACRO.resting, nil); eq(Visibility.MACRO.vehicle, nil)
    Mock.resting, Mock.inVehicle = nil, nil
end)

test("couleurs : classe et ressource du thème, sinon Blizzard", function()
    reset()
    local r, g, b = NS.ClassColor("MAGE")
    eq(r, 0.25); eq(g, 0.78); eq(b, 0.92)
    NS.db.theme.classColors.MAGE = { r = 0.1, g = 0.2, b = 0.3 }
    r, g, b = NS.ClassColor("MAGE")
    eq(r, 0.1); eq(g, 0.2); eq(b, 0.3)
    eq((NS.ClassColor(nil)), 1, "classe inconnue : blanc")
    r, g, b = NS.PowerColor(nil, 1)
    eq(r, 1); eq(g, 0); eq(b, 0)
    NS.db.theme.powerColors.RAGE = { r = 0.5, g = 0.4, b = 0.3 }
    eq((NS.PowerColor("RAGE", 1)), 0.5)
    eq(NS.PowerColor("RUNIC_POWER"), nil, "inconnue : nil")
    -- Profil importé invalide : entrée nombre ou incomplète, repli Blizzard.
    NS.db.theme.classColors.MAGE = 5
    eq((NS.ClassColor("MAGE")), 0.25, "nombre : Blizzard")
    NS.db.theme.classColors.MAGE = { g = 0.5 }
    eq((NS.ClassColor("MAGE")), 0.25, "incomplète : Blizzard")
    NS.db.theme.powerColors.RAGE = { r = 0.5 }
    eq((NS.PowerColor("RAGE", 1)), 1, "incomplète : Blizzard")
    NS.db.theme.classColors.MAGE, NS.db.theme.powerColors.RAGE = nil, nil
end)

test("couleurs : copie de profil, une couleur absente de la source redevient Blizzard", function()
    reset()
    local db = NS.Database
    local profiles = NS.global.profiles
    local active = db:ActiveProfileName()
    profiles.M8Source = db.FillProfile({})
    profiles.M8Source.theme.classColors.ROGUE = { r = 0.9, g = 0.8, b = 0.7 }
    NS.db.theme.classColors.MAGE = { r = 0.1, g = 0.2, b = 0.3 }
    truthy(db:CopyThemeColors("M8Source", active))
    eq(NS.db.theme.classColors.ROGUE.r, 0.9)
    eq(NS.db.theme.classColors.MAGE, nil, "absente de la source : retirée")
    truthy(NS.db.theme.classColors.ROGUE ~= profiles.M8Source.theme.classColors.ROGUE, "copie, pas la même table")
    wipe(NS.db.theme.classColors)
    profiles.M8Source = nil
end)

test("movers : Alt + molette passe d'un cadre superposé à l'autre", function()
    reset()
    local keys = { "m8B", "m8A", "m8C", "m8D" }
    for _, key in ipairs(keys) do
        local frame = CreateFrame("Frame", "MuscaUITestM8" .. key, UIParent)
        frame:SetSize(100, 20)
        Movers:Register(key, frame, key, "CENTER", 0, 0)
    end
    NS:SetUnlocked(true)
    for _, key in ipairs(keys) do
        local under = key ~= "m8D"   -- m8D ailleurs à l'écran
        Movers.registry[key].overlay.IsMouseOver = function() return under end
    end
    eq(Movers:CycleOverlap("m8A", -1), "m8B")
    eq(Movers.selected, "m8B")
    truthy(Movers.registry.m8B.overlay:GetFrameLevel() > Movers.registry.m8A.overlay:GetFrameLevel(), "passé au-dessus")
    eq(Movers:CycleOverlap("m8C", -1), "m8A", "après le dernier : le premier")
    eq(Movers:CycleOverlap("m8A", 1), "m8C", "molette vers le haut : précédent")
    Movers.registry.m8B.overlay.IsMouseOver = function() return false end
    Movers.registry.m8C.overlay.IsMouseOver = function() return false end
    eq(Movers:CycleOverlap("m8A", -1), nil, "seul sous la souris : rien")
    NS:SetUnlocked(false)
    for _, key in ipairs(keys) do Movers:Unregister(key); NS.db.anchors[key] = nil end
end)

test("FPS : réglages graphiques bas puis rendus", function()
    reset()
    Mock.cvars.graphicsShadowQuality, Mock.cvars.graphicsSSAO = "4", "3"
    NS.CVars:ApplyLowGraphics()
    eq(Mock.cvars.graphicsShadowQuality, "0"); eq(Mock.cvars.graphicsSSAO, "0")
    eq(Mock.cvars.graphicsLiquidDetail, nil, "absente du client : ignorée")
    -- Changée par le joueur après nous : son choix reste.
    Mock.cvars.graphicsSSAO = "2"
    NS.CVars:RestoreLowGraphics()
    eq(Mock.cvars.graphicsShadowQuality, "4"); eq(Mock.cvars.graphicsSSAO, "2")
    eq(NS.global.cvarBackup.graphicsShadowQuality, nil)
    Mock.cvars.graphicsShadowQuality, Mock.cvars.graphicsSSAO = nil, nil
end)

test("police sur tout le texte du jeu : globales et objets Font", function()
    reset()
    local font = { path = "TestFont.ttf", size = 14, flags = "OUTLINE" }
    function font:GetObjectType() return "Font" end
    function font:GetFont() return self.path, self.size, self.flags end
    function font:SetFont(path, size, flags) self.path, self.size, self.flags = path, size, flags end
    _G.MuscaUITestM8Font = font
    -- Nos familles de polices gardent la police choisie par module.
    local text = NS.Media:CreateText(UIParent)
    local family = text.fontFamily
    truthy(family, "famille créée")
    family.GetObjectType = font.GetObjectType
    family.SetFont = function() family.rewritten = true end
    family.GetFont = function() return "x", 12, "" end
    local saved = { STANDARD_TEXT_FONT, UNIT_NAME_FONT, DAMAGE_TEXT_FONT }
    NS.Media:ApplyToGameText()
    local path = NS.Media:Font()
    eq(STANDARD_TEXT_FONT, path); eq(UNIT_NAME_FONT, path); eq(DAMAGE_TEXT_FONT, path)
    eq(font.path, path); eq(font.size, 14); eq(font.flags, "OUTLINE")
    STANDARD_TEXT_FONT, UNIT_NAME_FONT, DAMAGE_TEXT_FONT = saved[1], saved[2], saved[3]
    _G.MuscaUITestM8Font = nil
    eq(family.rewritten, nil, "famille MuscaUI épargnée")
    family.GetObjectType, family.SetFont, family.GetFont = nil, nil, nil
end)

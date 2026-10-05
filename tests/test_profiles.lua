-- tests/test_profiles.lua : export compressé, export partiel, profil par spécialisation.
local T = ...
local NS, test, eq, truthy, reset = T.NS, T.test, T.eq, T.truthy, T.reset
local Database = NS.Database

test("profils : export AEON2 compressé, relu à l'identique ; AEON1 toujours accepté", function()
    reset()
    local text = Database.Export(NS.db)
    eq(text:sub(1, 6), "AEON2:")
    truthy(#text < #Database.Serialize(NS.db), "plus court que AEON1")
    truthy(Database.IsProfileString(text))
    local copy = Database.Deserialize(text)
    eq(Database.Serialize(copy), Database.Serialize(NS.db), "aller-retour sans perte")
    truthy(Database.Deserialize(Database.Serialize(NS.db)), "AEON1 relu")
    eq(Database.Deserialize("AEON2:@@@"), nil, "AEON2 illisible refusé")
    eq(Database.Deserialize("AEON2:" .. string.rep("a", 40000)), nil, "AEON2 trop long refusé")
end)

test("profils : un export partiel ne change que ses sections à l'import", function()
    reset()
    local fontSize, cursorSize = NS.db.theme.fontSize, NS.db.modules.cursor.enabled
    local source = Database.DeepCopy(NS.db)
    source.theme.fontSize = 20
    source.modules.cursor.enabled = not cursorSize
    source.anchors.testPartial = { point = "TOP", relPoint = "TOP", x = 1, y = 2 }
    local text = Database.Export(Database.PartialProfile(source, { cursor = true }, { "testPartial" }))
    local name, original = Database:ActiveProfileName(), NS.db
    local profile = Database:ImportProfile(text)
    NS.global.profiles[name] = original   -- les modules gardent la table d'origine
    eq(profile.theme.fontSize, fontSize, "thème non exporté : gardé")
    eq(profile.modules.cursor.enabled, not cursorSize, "module exporté : remplacé")
    eq(profile.anchors.testPartial.x, 1, "position du module importée")
    eq(profile.partial, nil, "marque retirée")
    eq(NS.db, original)
end)

test("profils : chaîne antérieure à la v7, réglages des modules renommés repris", function()
    reset()
    local name, original = Database:ActiveProfileName(), NS.db
    local text = Database.Serialize({ modules = {
        quickdraw = { enabled = true, entries = "spell:133", layout = "grid" }, shifter = { enabled = true } } })
    local profile = Database:ImportProfile(text)
    NS.global.profiles[name] = original
    eq(profile.modules.radialmenu.entries, "spell:133")
    eq(profile.modules.radialmenu.layout, "grid")
    eq(profile.modules.movablewindows.enabled, true)
    eq(profile.modules.quickdraw, nil, "ancienne clé retirée")
end)

test("profils : renommer, dupliquer, raccourci par profil", function()
    reset()
    local char = Database.CharacterKey()
    NS:SwitchProfile("Ancien", Database.DEFAULT_PROFILE)
    NS.global.profileHotkeys.Ancien = "ctrl-1"
    NS.global.specProfiles.Autre = { [1] = "Ancien" }
    eq(Database:RenameProfile("Ancien", "  Nouveau  "), "Nouveau", "espaces retirés")
    eq(NS.global.profiles.Ancien, nil)
    eq(NS.db, NS.global.profiles.Nouveau, "profil actif : même table")
    eq(NS.global.profileKeys[char], "Nouveau", "personnage suit")
    eq(NS.global.specProfiles.Autre[1], "Nouveau", "spé suit")
    eq(NS.global.profileHotkeys.Nouveau, "ctrl-1", "raccourci suit")
    eq(Database:RenameProfile(Database.DEFAULT_PROFILE, "X"), nil, "Default jamais renommé")
    eq(Database:RenameProfile("Nouveau", Database.DEFAULT_PROFILE), nil, "nom pris")
    eq(Database:RenameProfile("Nouveau", "   "), nil, "nom vide")
    -- Raccourci : la touche bascule sur son profil.
    NS:SwitchProfile(Database.DEFAULT_PROFILE)
    NS:BindProfileHotkeys()
    local button = _G.AeonUIProfileHotkey
    eq(Mock.overrideBindings[button]["CTRL-1"], "AeonUIProfileHotkey")
    button:GetScript("OnClick")(button, "P1")
    eq(Database:ActiveProfileName(), "Nouveau", "touche : profil rebranché")
    -- Dupliquer = profil neuf copié de l'actif.
    NS.db.theme.fontSize = 17
    NS:SwitchProfile("Copie", Database:ActiveProfileName())
    eq(NS.global.profiles.Copie.theme.fontSize, 17)
    truthy(NS.global.profiles.Copie ~= NS.global.profiles.Nouveau, "copie indépendante")
    NS:SwitchProfile(Database.DEFAULT_PROFILE)
    Database:DeleteProfile("Copie")
    Database:DeleteProfile("Nouveau")
    eq(NS.global.profileHotkeys.Nouveau, nil, "raccourci retiré avec le profil")
    NS.global.specProfiles.Autre = nil
    NS:BindProfileHotkeys()
    eq(Mock.overrideBindings[button], nil)
end)

test("profils : export du compte, importé seulement collé à la main", function()
    reset()
    NS:SwitchProfile("Second", Database.DEFAULT_PROFILE)
    NS.global.profiles.Second.theme.fontSize = 15
    NS:SwitchProfile(Database.DEFAULT_PROFILE)
    local text = Database.Export(Database:AccountExport())
    Database:DeleteProfile("Second")
    eq(NS:ImportProfile(text), false, "reçu du groupe : refusé")
    eq(NS.global.profiles.Second, nil)
    eq(NS:ImportProfile(text, true), true)
    eq(NS.global.profiles.Second.theme.fontSize, 15, "profil recréé")
    truthy(NS.global.profiles[Database.DEFAULT_PROFILE].theme, "profil actif rempli")
    eq(NS.db, NS.global.profiles[Database.DEFAULT_PROFILE], "rebranché sur le profil actif")
    Database:DeleteProfile("Second")
end)

test("profils : un profil par spé, choisi au changement de spé", function()
    reset()
    local char = Database.CharacterKey()
    Database:UseProfile("SpecTwo")
    Database:UseProfile(Database.DEFAULT_PROFILE)
    local spec = 1
    _G.GetNumSpecializations = function() return 2 end
    _G.GetSpecialization = function() return spec end
    eq(NS.GetActiveSpec(), 1)
    Database:SetSpecProfile(2, "SpecTwo")
    eq(Database:ActiveProfileName(), Database.DEFAULT_PROFILE, "spé 1 sans lien : profil du perso")
    spec = 2
    eq(Database:ActiveProfileName(), "SpecTwo", "spé 2 liée")
    NS:CheckSpecProfile()
    eq(NS.db, NS.global.profiles.SpecTwo, "profil rebranché")
    eq(NS.global.lastSpec[char], 2, "dernière spé mémorisée")
    -- Spé illisible (connexion) : la dernière connue sert.
    _G.GetSpecialization = function() return nil end
    eq(Database:ActiveProfileName(), "SpecTwo")
    -- Choisir un profil dans la liste met à jour le lien de la spé.
    _G.GetSpecialization = function() return 2 end
    Database:UseProfile(Database.DEFAULT_PROFILE)
    eq(Database:GetSpecProfile(2), Database.DEFAULT_PROFILE)
    Database:SetSpecProfile(2, nil)
    eq(NS.global.specProfiles[char], nil, "table vidée")
    Database:DeleteProfile("SpecTwo")
    _G.GetSpecialization, _G.GetNumSpecializations = nil, nil
    NS.global.lastSpec[char] = nil
    NS:CheckSpecProfile()
    eq(NS.db, NS.global.profiles[Database.DEFAULT_PROFILE])
end)

test("profils : un profil par contexte, prioritaire, basculé après le combat", function()
    reset()
    local char = Database.CharacterKey()
    Database:UseProfile("Raid")
    Database:UseProfile(Database.DEFAULT_PROFILE)
    Database:SetContextProfile("raid", "Raid")
    eq(Database:ActiveProfileName(), Database.DEFAULT_PROFILE, "hors instance : profil du perso")
    Mock.instanceType = "raid"
    Mock.SetCombat(true)
    NS:CheckSpecProfile()
    eq(NS.db, NS.global.profiles[Database.DEFAULT_PROFILE], "en combat : rien ne bascule")
    Mock.SetCombat(false)
    eq(NS.db, NS.global.profiles.Raid, "bascule à la fin du combat")
    -- Choisir un profil en raid met à jour le lien du contexte, pas celui du perso.
    Database:UseProfile(Database.DEFAULT_PROFILE)
    eq(Database:GetContextProfile("raid"), Database.DEFAULT_PROFILE)
    eq(NS.global.profileKeys[char], nil)
    Database:SetContextProfile("raid", "Raid")
    eq(Database:RenameProfile("Raid", "Raid 40"), "Raid 40")
    eq(Database:GetContextProfile("raid"), "Raid 40", "lien renommé")
    Database:DeleteProfile("Raid 40")
    eq(Database:GetContextProfile("raid"), nil, "lien retiré avec le profil")
    Mock.instanceType = "none"
    NS:CheckSpecProfile()
    eq(NS.db, NS.global.profiles[Database.DEFAULT_PROFILE])
end)

test("profils : nom refusé s'il contient « | » (codes du chat)", function()
    eq(Database.ValidProfileName("Tank|Tinterface|t"), nil)
    eq(Database.ValidProfileName("  Tank  "), "Tank")
end)

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

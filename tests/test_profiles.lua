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

test("sauvegarde : prise avant l'import, restaurer échange, restaurer deux fois revient au départ", function()
    reset()
    local name, original = Database:ActiveProfileName(), NS.db
    local fontSize = NS.db.theme.fontSize
    truthy(Database:ImportProfile(Database.Serialize({ theme = { fontSize = fontSize + 5 } })), "importé")
    local backup = Database:Backup()
    eq(backup.reason, "import")
    eq(Database.FillProfile(Database.DeepCopy(backup.profiles[name])).theme.fontSize, fontSize, "profil d'avant l'import")
    truthy(NS:RestoreBackup())
    eq(NS.db.theme.fontSize, fontSize, "restauré et rebranché")
    eq(Database:Backup().reason, "restore")
    eq(Database:Backup().profiles[name].theme.fontSize, fontSize + 5, "l'import devient la sauvegarde")
    NS:RestoreBackup()
    eq(NS.db.theme.fontSize, fontSize + 5, "deuxième restauration : retour à l'import")
    NS.global.profiles[name] = original
    NS:SwitchProfile(name)
    NS.global.profileBackup = nil
    eq(NS.db, original)
    eq(NS:RestoreBackup(), false, "sans sauvegarde : rien")
end)

test("sauvegarde d'un ancien format : migrée avant d'être restaurée", function()
    reset()
    local original = Database.Serialize(NS.db)
    NS.global.profileBackup = { reason = "migration", version = 6, time = 0,
                                profiles = { Default = { modules = { quickdraw = { key = "SHIFT-Q" } } } } }
    truthy(Database:RestoreBackup())
    eq(NS.global.profiles.Default.modules.radialmenu.key, "SHIFT-Q", "v7 appliquée")
    eq(NS.global.profiles.Default.modules.quickdraw, nil)
    Database:RestoreBackup()
    eq(Database.Serialize(NS.global.profiles.Default), original, "retour au départ")
    NS.global.profileBackup = nil
end)

test("import sélectif par les options : positions des modules cochés reprises malgré Reload", function()
    reset()
    local name, original = Database:ActiveProfileName(), NS.db
    local source = Database.DeepCopy(NS.db)
    source.anchors.reminders = { point = "TOP", relPoint = "TOP", x = 123, y = -80 }
    truthy(NS:ImportProfile(Database.Export(source), false, { reminders = true }))
    eq(NS.db.anchors.reminders.x, 123)
    NS.global.profiles[name] = original
    NS:SwitchProfile(name)
    NS.global.profileBackup = nil
    eq(NS.db, original)
end)

test("sauvegarde : absente du miroir CVar et de l'export du compte", function()
    reset()
    Database:SaveBackup("reset")
    eq(Database:MirrorTable().profileBackup, nil, "miroir sans sauvegarde")
    eq(Database.Serialize(Database:AccountExport()):find("profileBackup", 1, true), nil, "export sans sauvegarde")
    NS.global.profileBackup = nil
end)

test("import : chaîne refusée au-delà de 20 000 valeurs ou de 256 Ko, export réel loin des bornes", function()
    eq(Database.Deserialize("AEON1:" .. string.rep("a=b1;", 20001)), nil, "trop de valeurs")
    eq(Database.Deserialize("AEON1:" .. string.rep("x", 262200)), nil, "trop long")
    truthy(Database.Deserialize("AEON1:" .. string.rep("a=b1;", 1000)), "1000 valeurs acceptées")
    local _, count = Database.Serialize(NS.db):gsub(";", "")
    truthy(count < 5000, "export complet : " .. count .. " valeurs")
end)

test("import : rapport des corrections (valeur bornée, couleur, position écartée)", function()
    reset()
    local name, original = Database:ActiveProfileName(), NS.db
    local text = Database.Serialize({
        theme = { accent = { r = 2, g = 0, b = 0, a = 1 } },
        modules = { groupframes = { raidThreshold = 99 } },
        anchors = { testFar = { point = "TOP", relPoint = "TOP", x = 99999, y = 0 } },
    })
    local profile, report = Database:ImportProfile(text)
    NS.global.profiles[name] = original
    NS.global.profileBackup = nil
    eq(profile.theme.accent.r, 1, "couleur ramenée à 1")
    eq(profile.modules.groupframes.raidThreshold, 40, "valeur bornée")
    eq(profile.anchors.testFar, nil, "position hors écran écartée")
    eq(report.clamped, 2)
    eq(report.anchors, 1)
end)

test("import sélectif : seules les sections cochées remplacent le profil", function()
    reset()
    local name, original = Database:ActiveProfileName(), NS.db
    local fontSize, cursorEnabled = NS.db.theme.fontSize, NS.db.modules.cursor.enabled
    local source = Database.DeepCopy(NS.db)
    source.theme.fontSize = fontSize + 5
    source.modules.cursor.enabled = not cursorEnabled
    local imported = Database.Deserialize(Database.Export(source))
    local sections = Database.ImportedSections(imported)
    eq(sections[1], "theme", "thème listé en premier")
    local profile = Database:ImportProfile(Database.Export(source), false, { cursor = true })
    NS.global.profiles[name] = original
    NS.global.profileBackup = nil
    eq(profile.theme.fontSize, fontSize, "section décochée : gardée")
    eq(profile.modules.cursor.enabled, not cursorEnabled, "section cochée : importée")
end)

test("import : rapport des types faux et positions mal formées ; réglage sensible absent non compté", function()
    reset()
    local name, original = Database:ActiveProfileName(), NS.db
    local repair = NS.db.modules.automation.repair
    NS.db.modules.automation.repair = not repair   -- différent du défaut que FillProfile posera
    local text = Database.Serialize({
        theme = { fontSize = "gros" },
        anchors = { testBad = { point = "NOWHERE", relPoint = "TOP", x = 0, y = 0 } },
    })
    local profile, report = Database:ImportProfile(text)
    eq(profile.modules.automation.repair, not repair, "réglage sensible gardé")
    eq(report.clamped, 1, "type faux remplacé par le défaut")
    eq(report.anchors, 1, "position mal formée écartée")
    eq(report.sensitive, 0, "absent de la chaîne : pas compté")
    _, report = Database:ImportProfile(Database.Serialize({ modules = { automation = { repair = repair } } }))
    eq(report.sensitive, 1, "présent et différent : compté")
    original.modules.automation.repair = repair
    NS.global.profiles[name] = original
    NS.global.profileBackup = nil
end)

test("sauvegarde : réduite aux écarts aux défauts, restaurée à l'identique", function()
    reset()
    local name, original = Database:ActiveProfileName(), NS.db
    local before = Database.Serialize(NS.db)
    Database:SaveBackup("reset")
    local saved = Database:Backup().profiles[name]
    eq(saved.theme and saved.theme.fontSize, nil, "défaut omis")
    truthy(#Database.Serialize(saved) < #before / 4, "bien plus petite que le profil")
    truthy(NS:RestoreBackup())
    eq(Mock.FindPrinted(NS.L.MSG_BACKUP_DEFAULTS_LOST), nil, "défauts joints lus : pas d'avertissement")
    eq(Database.Serialize(NS.db), before, "profil restauré identique")
    NS.global.profiles[name] = original
    NS:SwitchProfile(name)
    NS.global.profileBackup = nil
end)

test("import par les options : export AEON2 de plus de 12 000 caractères collé, importé par le bouton", function()
    reset()
    local name, original = Database:ActiveProfileName(), NS.db
    local ids = {}
    for i = 1, 4000 do ids[i] = tostring(math.random(100000, 999999)) end
    local whitelist = table.concat(ids, ", ")
    local text = Database.Export({ auraLists = { whitelist = whitelist } })
    truthy(text:sub(1, 6) == "AEON2:" and #text > 12000 and #text < Database.PastedLimit(true), "chaîne réelle au-delà de l'envoi")
    local layout, box, import = NS.Options:GetLayout("profiles")
    for _, entry in ipairs(layout.labels) do
        if entry.text == NS.L.OPT_PROFILE_STRING then box = entry.frame end
        if entry.text == NS.L.OPT_PROFILE_IMPORT then import = entry.frame end
    end
    box:SetText(text)
    box:GetScript("OnTextChanged")(box, true)
    Mock.acceptPopups = true
    import:Click()
    Mock.acceptPopups = false
    truthy(NS.db.auraLists.whitelist == whitelist, "liste reprise")
    NS.global.profiles[name] = original
    NS:SwitchProfile(name)
    NS.global.profileBackup = nil
end)

test("sauvegarde : un défaut changé après coup ne change pas le profil restauré", function()
    reset()
    local name, original = Database:ActiveProfileName(), NS.db
    local fontSize = NS.db.theme.fontSize
    Database:SaveBackup("reset")
    local plain = Database.PlainText(Database:Backup().defaults, Database.PastedLimit(true))
    -- Marge sous les bornes de Deserialize : au-delà, la restauration retomberait sur les défauts actuels.
    truthy(#Database:Backup().defaults < Database.PastedLimit(true) / 2 and plain and #plain < 262144 / 2, "défauts joints relisibles")
    Database.PROFILE_DEFAULTS.theme.fontSize = fontSize + 5
    local ok = pcall(NS.RestoreBackup, NS)
    Database.PROFILE_DEFAULTS.theme.fontSize = fontSize
    truthy(ok, "restauration sans erreur")
    eq(NS.db.theme.fontSize, fontSize, "valeur d'origine, pas le nouveau défaut")
    NS.global.profiles[name] = original
    NS:SwitchProfile(name)
    NS.global.profileBackup = nil
end)

test("sauvegarde : défauts joints illisibles, restauration signalée", function()
    reset()
    local name, original = Database:ActiveProfileName(), NS.db
    Database:SaveBackup("reset")
    Database:Backup().defaults = "AEON2:@@@"
    NS:RestoreBackup()
    truthy(Mock.FindPrinted(NS.L.MSG_BACKUP_DEFAULTS_LOST), "avertissement affiché")
    NS.global.profiles[name] = original
    NS:SwitchProfile(name)
    NS.global.profileBackup = nil
end)

test("import : rapport sans double compte, ni section écartée, champs de position comptés", function()
    reset()
    local name, original = Database:ActiveProfileName(), NS.db
    local text = Database.Serialize({ theme = { fontSize = 14 } }) .. ";modules.cursor.scale=n1e999"
    local _, report = Database:ImportProfile(text, false, { theme = true })
    eq(report.clamped, 0, "infini d'une section écartée : pas compté")
    _, report = Database:ImportProfile(Database.Serialize({
        theme = { moduleMedia = { cursor = 5 } },
        anchors = {
            testFar = { point = "TOP", relPoint = "TOP", x = 20000, y = 0, widthOffset = 9999, target = 5 },
            testField = { point = "TOP", relPoint = "TOP", x = 0, y = 0, target = 5 },
        },
    }) .. ";anchors.testInfinite.point=sTOP;anchors.testInfinite.relPoint=sTOP;anchors.testInfinite.x=n1e999"
       .. ";anchors.testInfinite.y=n0;anchors.testFallback.point=sTOP;anchors.testFallback.relPoint=sTOP"
       .. ";anchors.testFallback.x=n0;anchors.testFallback.y=n0;anchors.testFallback.fallback.point=sTOP"
       .. ";anchors.testFallback.fallback.relPoint=sTOP;anchors.testFallback.fallback.x=n1e999;anchors.testFallback.fallback.y=n0")
    eq(report.anchors, 2, "position lointaine ou infinie : comptée une fois, sans ses champs")
    eq(report.clamped, 3, "exception de module scalaire, champ mal typé, repli infini compté une fois")
    NS.global.profiles[name] = original
    NS:SwitchProfile(name)
    NS.global.profileBackup = nil
end)

test("profil reçu du groupe : aperçu ouvert, export du compte refusé", function()
    reset()
    NS:SwitchProfile("Second", Database.DEFAULT_PROFILE)
    NS:SwitchProfile(Database.DEFAULT_PROFILE)
    local text = Database.Export(Database:AccountExport())
    Database:DeleteProfile("Second")
    NS.Options:ShowImport(text)
    local import
    for _, entry in ipairs(NS.Options:GetLayout("profiles").labels) do
        if entry.text == NS.L.OPT_PROFILE_IMPORT then import = entry.frame end
    end
    Mock.acceptPopups = true
    import:Click()
    Mock.acceptPopups = false
    eq(NS.global.profiles.Second, nil, "aucun profil recréé")
    truthy(Mock.FindPrinted(NS.L.MSG_IMPORT_FAILED), "refus annoncé")
end)

test("restauration en combat : annoncée, faite à la fin du combat", function()
    reset()
    local name, original = Database:ActiveProfileName(), NS.db
    local fontSize = NS.db.theme.fontSize
    Database:SaveBackup("reset")
    NS.db.theme.fontSize = fontSize + 3
    Mock.SetCombat(true)
    truthy(NS:RestoreBackup())
    truthy(NS:RestoreBackup(), "seconde demande : déjà en attente")
    truthy(Mock.FindPrinted(NS.L.MSG_BACKUP_AFTER_COMBAT), "joueur prévenu")
    eq(Database:Backup().reason, "reset", "rien avant la fin du combat")
    Mock.SetCombat(false)
    eq(Database:Backup().reason, "restore", "restaurée à la sortie du combat")
    eq(NS.db.theme.fontSize, fontSize, "un seul échange, pas deux")
    NS.global.profiles[name] = original
    NS:SwitchProfile(name)
    NS.global.profileBackup = nil
end)

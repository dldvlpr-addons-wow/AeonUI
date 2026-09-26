-- tests/test_core.lua : base de données, profils, CVars, file hors combat, registre.
local T = ...
local NS, test, eq, truthy, reset = T.NS, T.test, T.eq, T.truthy, T.reset

local MODULES = { "topbar", "automation", "reminders", "alerts", "nameplates", "frames", "cotank",
                  "groupfinder", "cursor", "gear", "skin", "interface" }

test("DB : table globale + profil Default complet pour chaque module", function()
    eq(AeonUIDB.version, NS.Database.VERSION, "version")
    eq(g_addonCategoriesCollapsed.AeonUI, AeonUIDB, "table hôte Blizzard = même table")
    local profile = AeonUIDB.profiles.Default
    truthy(profile, "profil Default")
    eq(NS.db, profile, "NS.db pointe sur le profil actif")
    for _, name in ipairs(MODULES) do
        truthy(profile.modules[name], "réglages de " .. name)
        eq(type(profile.modules[name].enabled), "boolean", name .. ".enabled")
    end
end)

test("migration v1 -> v2 : les réglages à plat deviennent le profil Default", function()
    local db = NS.Database:Init({
        version = 1, locale = "frFR", firstRunDone = true,
        theme = { fontSize = 14 }, anchors = { reminders = { point = "TOP", relPoint = "TOP", x = 0, y = -80 } },
        modules = { automation = { sellJunk = false } },
    })
    local profile = db.profiles.Default
    eq(db.locale, "frFR", "langue gardée")
    eq(db.firstRunDone, true, "premier lancement gardé")
    eq(profile.theme.fontSize, 14, "thème migré")
    eq(profile.modules.automation.sellJunk, false, "réglage migré")
    eq(profile.modules.automation.repair, true, "défaut ajouté")
    eq(profile.anchors.reminders.point, "TOP", "ancrage migré")
    eq(db.theme, nil, "plus de réglages à plat")
    eq(NS.Database.global, AeonUIDB, "Init ne rebranche pas la table active")
end)

test("profils : copie pour le personnage, isolée de Default, suppression", function()
    reset()
    NS:SwitchProfile("Testeur - Forever", "Default")
    eq(NS.Database:ActiveProfileName(), "Testeur - Forever")
    NS.db.modules.automation.sellJunk = false
    eq(AeonUIDB.profiles.Default.modules.automation.sellJunk, true, "Default intact")
    eq(NS.Modules:Get("topbar").enabled, true, "modules rebranchés")
    NS:SwitchProfile("Default")
    eq(NS.db, AeonUIDB.profiles.Default)
    eq(NS.db.modules.automation.sellJunk, true)
    truthy(NS.Database:DeleteProfile("Testeur - Forever"), "supprimé")
    eq(NS.Database:DeleteProfile("Default"), false, "Default indélébile")
end)

test("chaque langue traduit toutes les clés de enUS, sans clé en trop ni format perdu", function()
    local function formats(text)
        local list = {}
        for spec in text:gmatch("%%[%d%.%-]*[sdfgx%%]") do list[#list + 1] = spec end
        return table.concat(list, " ")
    end
    for _, entry in ipairs(NS.LOCALE_ORDER) do
        local code = entry.code
        local locale = NS.locales[code]
        truthy(locale, "langue chargée : " .. code)
        for key, value in pairs(NS.locales.enUS) do
            truthy(locale[key], "clé " .. code .. " manquante : " .. key)
            eq(formats(locale[key]), formats(value), code .. " " .. key .. " : formats")
        end
        for key in pairs(locale) do
            truthy(NS.locales.enUS[key], "clé " .. code .. " en trop : " .. key)
        end
    end
end)

test("langue changée après l'enregistrement : titres des modules retraduits", function()
    NS.SetLocale("frFR")
    eq(NS.Modules:Get("topbar").title, NS.locales.frFR.TOPBAR_TITLE)
    eq(NS.Modules:Get("cursor").description, NS.locales.frFR.CURSOR_DESC)
    NS.SetLocale("enUS")
    eq(NS.Modules:Get("topbar").title, NS.locales.enUS.TOPBAR_TITLE)
end)

test("clés dynamiques traduites (règles, postures, éléments, sons)", function()
    for _, rule in ipairs(NS.REMINDER_CLASS_RULES) do truthy(T.L["REM_RULE_" .. rule.key], rule.key) end
    for _, choices in pairs(NS.STANCE_CHOICES) do
        for _, choice in ipairs(choices) do truthy(T.L["STANCE_" .. choice.key], choice.key) end
    end
    for _, key in ipairs({ "FRIENDS", "GUILD", "CLOCK", "GOLD", "DURABILITY", "BAGS", "PERF", "TRAVEL", "HEARTH" }) do
        truthy(T.L["OPT_TOPBAR_SHOW_" .. key], key)
    end
    for _, preset in ipairs(NS.SOUND_PRESET_ORDER) do truthy(T.L["SOUND_" .. preset:upper()], preset) end
end)

test("modules actifs selon leurs défauts après la connexion", function()
    for _, module in ipairs(NS.Modules:List()) do
        eq(module.enabled, module.defaults.enabled, module.name)
    end
end)

test("RunOutOfCombat : immédiat hors combat, différé en combat", function()
    reset()
    local runs = 0
    eq(NS:RunOutOfCombat(function() runs = runs + 1 end), true)
    Mock.SetCombat(true)
    eq(NS:RunOutOfCombat(function() runs = runs + 1 end), false)
    eq(runs, 1, "rien en combat")
    Mock.SetCombat(false)
    eq(runs, 2, "exécuté à la sortie")
end)

test("module sécurisé désactivé en combat : attend la fin du combat", function()
    reset()
    local bar = NS.Modules:Get("topbar"):GetFrame()
    Mock.SetCombat(true)
    eq(NS.Modules:SetEnabled("topbar", false), "deferred")
    eq(bar:IsShown(), true, "visible en combat")
    Mock.SetCombat(false)
    eq(bar:IsShown(), false, "cachée après")
    NS.Modules:SetEnabled("topbar", true)
end)

test("un module en erreur est isolé et signalé", function()
    reset()
    local boom = NS.Modules:Register("boom", {
        title = "Boom", defaults = { enabled = false }, OnEnable = function() error("kaboom") end,
    })
    NS.db.modules.boom = { enabled = false }
    NS.Modules:SetEnabled("boom", true)
    eq(boom.enabled, false)
    eq(boom.failed, true)
    truthy(Mock.FindPrinted("Boom"), "erreur affichée")
    eq(NS.Modules:Get("skin").enabled, true, "les autres continuent")
end)

test("CVars : valeur d'origine gardée puis rendue, CVar inconnue ignorée", function()
    reset()
    Mock.cvars.autoLootDefault = "0"
    truthy(NS.CVars:Set("autoLootDefault", 1))
    eq(Mock.cvars.autoLootDefault, "1")
    NS.CVars:Set("autoLootDefault", 0)
    NS.CVars:Set("autoLootDefault", 1)
    eq(AeonUIDB.cvarBackup.autoLootDefault, "0", "l'origine n'est jamais écrasée")
    NS.CVars:Restore("autoLootDefault")
    eq(Mock.cvars.autoLootDefault, "0", "rendue")
    eq(NS.CVars:IsChanged("autoLootDefault"), false)
    eq(NS.CVars:Set("cvarInexistante", 1), false)
end)

test("CVars : écriture différée en combat", function()
    reset()
    Mock.SetCombat(true)
    NS.CVars:Set("autoLootDefault", 1)
    eq(Mock.cvars.autoLootDefault, "0", "rien en combat")
    Mock.SetCombat(false)
    eq(Mock.cvars.autoLootDefault, "1")
    NS.CVars:Restore("autoLootDefault")
end)

test("CVars : posée puis rendue pendant le même combat = valeur d'origine à la sortie", function()
    reset()
    Mock.SetCombat(true)
    NS.CVars:Set("autoLootDefault", 1)
    eq(NS.CVars:IsChanged("autoLootDefault"), true, "sauvegarde immédiate")
    eq(NS.CVars:Restore("autoLootDefault"), true)
    Mock.SetCombat(false)
    eq(Mock.cvars.autoLootDefault, "0", "jamais restée à 1")
    eq(NS.CVars:IsChanged("autoLootDefault"), false)
end)

test("CVars : coupée puis remise pendant le même combat = origine toujours gardée", function()
    reset()
    Mock.cvars.autoLootDefault = "0"
    NS.CVars:Set("autoLootDefault", 1)
    Mock.SetCombat(true)
    NS.CVars:Restore("autoLootDefault")
    NS.CVars:Set("autoLootDefault", 1)
    Mock.SetCombat(false)
    eq(Mock.cvars.autoLootDefault, "1", "le dernier choix gagne")
    eq(AeonUIDB.cvarBackup.autoLootDefault, "0", "origine gardée")
    NS.CVars:Restore("autoLootDefault")
    eq(Mock.cvars.autoLootDefault, "0", "rendue plus tard")
end)

test("CVars : écriture refusée à la déconnexion = sauvegarde gardée", function()
    reset()
    Mock.cvars.autoLootDefault = "0"
    NS.CVars:Set("autoLootDefault", 1)
    local setCVar = C_CVar.SetCVar
    C_CVar.SetCVar = function() return false end   -- CVar protégée en combat
    NS.CVars:RestoreAll(true)
    C_CVar.SetCVar = setCVar
    eq(AeonUIDB.cvarBackup.autoLootDefault, "0", "origine gardée pour la prochaine fois")
    NS.CVars:Restore("autoLootDefault")
    eq(Mock.cvars.autoLootDefault, "0")
end)

test("diagnostic : liste les API présentes et absentes", function()
    local lines = NS.Diagnostic()
    truthy(lines[1]:find("16001", 1, true), "interface")
    truthy(lines[2]:find("C_UnitAuras", 1, true), "API présente listée")
    truthy(lines[3]:find("C_CooldownViewer", 1, true), "API absente listée")
    truthy(lines[5]:find("prédéfinie", 1, true), "Edit Mode : disposition Blizzard active")
    truthy(lines[6]:find("CreateLayoutsFromSerializedData", 1, true), "CDM : méthode d'import listée")
    truthy(lines[6]:find("GetSerializer", 1, true) and lines[6]:find("SerializeLayouts", 1, true), "CDM : sérialiseur et sa méthode d'export listés")
    truthy(lines[7]:find("^Menace : "), "menace : une ligne")
end)

-- Texte du miroir en clair : tranches recollées, AEON2 décompressée.
local function MirrorText()
    local parts = {}
    for i = 1, NS.Database.MIRROR_SLOTS do
        local chunk = Mock.cvars["AeonUIMirror" .. i]
        if not chunk or chunk == "" then break end
        parts[#parts + 1] = chunk
    end
    return NS.Database.PlainText(table.concat(parts), NS.Database.MIRROR_SLOTS * NS.Database.MIRROR_CHUNK) or ""
end

test("miroir CVar : la table globale revient entière quand la SavedVariables est vide", function()
    reset()
    local Database = NS.Database
    NS.db.modules.automation.sellJunk = false
    NS.global.firstRunDone = true
    NS.global.profileKeys["Autre - Forever"] = "Tank"
    NS.global.profiles.Tank = Database.FillProfile({ theme = { fontSize = 15 } })
    NS.global.profiles.Vide = Database.FillProfile({})
    truthy(Database:WriteMirror(), "première écriture")
    eq(Database:WriteMirror(), false, "rien ne change : pas de réécriture")
    truthy(Mock.cvars.AeonUIMirror1 ~= "", "tranche 1 remplie")
    eq(Mock.cvars.AeonUIMirror2, "", "sans les défauts, une tranche suffit")
    truthy(Mock.cvars.AeonUIMirror1:find("^AEON2:"), "miroir compressé")
    truthy(MirrorText():find("profiles.Vide=t", 1, true), "profil sans écart présent par nom")
    eq(MirrorText():find("automation.repair", 1, true), nil, "défaut non recopié")
    NS.global.profiles.Tank, NS.global.profiles.Vide, NS.global.profileKeys["Autre - Forever"] = nil, nil, nil
    NS.global.firstRunDone = false
    NS.db.modules.automation.sellJunk = true

    g_addonCategoriesCollapsed.AeonUI = nil      -- chemin miroir CVar seul
    local restored = Database:Load(nil)
    eq(restored.firstRunDone, true, "assistant marqué fait")
    eq(restored.profileKeys["Autre - Forever"], "Tank", "association personnage/profil")
    eq(restored.profiles.Tank.theme.fontSize, 15, "profil secondaire")
    eq(restored.profiles.Vide.theme.fontSize, 12, "profil vide recréé et complété")
    eq(restored.profiles.Default.modules.automation.sellJunk, false, "réglage modifié")
    eq(restored.profiles.Default.modules.automation.repair, true, "défauts complétés")
    eq(restored.profiles.Default.theme.fontSize, 12, "défauts du thème complétés")
    eq(Database.Deserialize(MirrorText()).version, Database.VERSION, "version présente dans le miroir")
    local fromEmpty = Database:Load({})
    eq(fromEmpty.firstRunDone, true, "table vide = même repli que nil")
    local kept = Database:Load({ version = Database.VERSION, firstRunDone = false })
    eq(kept.firstRunDone, false, "SavedVariables non vide : prioritaire sur le miroir")
end)

test("table hôte : prioritaire sur le miroir CVar, SavedVariables prioritaire sur tout", function()
    reset()
    local Database = NS.Database
    NS.db.theme.fontSize = 13
    Database:WriteMirror()
    NS.db.theme.fontSize = 12
    g_addonCategoriesCollapsed.AeonUI = { profiles = { Default = { theme = { fontSize = 17 } } } }
    eq(Database:Load(nil).profiles.Default.theme.fontSize, 17, "table hôte avant le miroir CVar")
    eq(Database:Load({ version = Database.VERSION }).profiles.Default.theme.fontSize, 12, "SavedVariables non vide avant tout")
    g_addonCategoriesCollapsed.AeonUI = {}
    eq(Database:Load(nil).profiles.Default.theme.fontSize, 13, "table hôte vide : miroir CVar")
    g_addonCategoriesCollapsed = {}
    Database:WriteMirror()
    eq(g_addonCategoriesCollapsed.AeonUI, AeonUIDB, "table hôte recréée : rebranchée à l'écriture")
    Database:WriteMirror()
end)

test("miroir CVar : découpage en tranches, refus au-delà de la capacité", function()
    reset()
    local Database = NS.Database
    local chunk, slots = Database.MIRROR_CHUNK, Database.MIRROR_SLOTS
    Database.MIRROR_CHUNK = 128
    NS.db.modules.automation.sellJunk = false
    truthy(Database:WriteMirror(), "écriture découpée")
    NS.db.modules.automation.sellJunk = true
    truthy(Mock.cvars.AeonUIMirror2 ~= "", "au moins deux tranches")
    g_addonCategoriesCollapsed.AeonUI = nil      -- chemin miroir CVar seul
    local restored = Database:Load(nil)
    eq(restored.profiles.Default.modules.automation.sellJunk, false, "recollé sans perte")
    -- Trop grand pour 8 x 128, même compressé : rien n'est écrit, le miroir précédent reste
    -- lisible, le joueur est prévenu une seule fois.
    local before = Mock.cvars.AeonUIMirror1
    local noise = {}
    for i = 1, 400 do noise[i] = tostring((i * 7919) % 10007) end   -- peu compressible
    NS.global.profiles.Gros = Database.FillProfile({ theme = { font = table.concat(noise) } })
    Mock.printed = {}
    local written = Database:WriteMirror()
    local again = Database:WriteMirror()
    NS.global.profiles.Gros = nil
    Database.MIRROR_CHUNK, Database.MIRROR_SLOTS = chunk, slots
    eq(written, false, "trop grand : refusé")
    eq(again, false)
    eq(Mock.cvars.AeonUIMirror1, before, "tranche 1 intacte")
    eq(#Mock.printed, 1, "prévenu une seule fois")
    -- Sans l'API, tout est inerte.
    local api = _G.C_CVar
    _G.C_CVar = { GetCVar = api.GetCVar, SetCVar = api.SetCVar }
    eq(Database:WriteMirror(), false, "API absente : pas d'écriture")
    eq(Database:ReadMirror(), nil, "API absente : pas de lecture")
    _G.C_CVar = api
end)

test("miroir CVar : recopie à la déconnexion et par le ticker", function()
    reset()
    NS.Database:WriteMirror()
    NS.db.modules.automation.repair = false
    Mock.FireEvent("PLAYER_LOGOUT")
    truthy(MirrorText():find("automation%.repair=b0"), "écrit à PLAYER_LOGOUT")
    NS.db.modules.automation.repair = true
    Mock.Advance(6)
    eq(MirrorText():find("automation.repair", 1, true), nil, "écrit par le ticker (défaut retiré)")
end)

test("miroir CVar : l'historique du chat n'y entre pas, les réglages passent toujours", function()
    reset()
    local key = NS.Database.CharacterKey()
    NS.global.chatHistory = { [key] = {} }
    for window = 1, 3 do
        local lines = {}
        for i = 1, 500 do lines[i] = { text = "ligne " .. i .. " fenêtre " .. window .. " " .. ((i * 7919) % 10007) } end
        NS.global.chatHistory[key]["ChatFrame" .. window] = lines
    end
    NS.db.modules.automation.repair = false
    truthy(NS.Database:WriteMirror(), "écrit malgré 1500 lignes d'historique")
    eq(MirrorText():find("chatHistory", 1, true), nil, "historique absent du miroir")
    truthy(MirrorText():find("automation%.repair=b0"), "réglage présent")
    NS.db.modules.automation.repair = true
    NS.global.chatHistory = nil
end)

test("miroir CVar : jamais écrit s'il ne pourrait pas être relu (trop grand une fois décompressé)", function()
    reset()
    NS.Database:WriteMirror()
    local before = Mock.cvars.AeonUIMirror1
    NS.global.profiles.Enorme = NS.Database.FillProfile({ theme = { font = string.rep("x", 270000) } })
    local written = NS.Database:WriteMirror()   -- compressé, il tiendrait dans les tranches
    NS.global.profiles.Enorme = nil
    eq(written, false, "refusé")
    eq(Mock.cvars.AeonUIMirror1, before, "miroir précédent gardé")
end)

test("import : une chaîne compressée de plus de 12 000 caractères reste refusée, le miroir l'accepte", function()
    local noise = {}
    for i = 1, 6000 do noise[i] = tostring((i * 7919) % 10007) end   -- peu compressible
    local text = NS.Database.Export({ theme = { font = table.concat(noise, ",") } })
    truthy(#text > 12000 + #NS.Database.COMPRESSED_PREFIX, "vraie chaîne AEON2 au-delà de la borne")
    eq(NS.Database.Deserialize(text), nil, "borne des imports inchangée")
    truthy(NS.Database.Deserialize(text, 32000), "borne du miroir")
end)

test("médias : fond et bordure 1 px suivent le thème et l'échelle", function()
    reset()
    local Media = NS.Media
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetSize(50, 50)
    local bg, edges = Media:CreateBackdrop(frame)
    truthy(bg and edges.top and edges.bottom and edges.left and edges.right, "cinq textures")
    eq(edges.top.color[1], 0, "bordure noire par défaut")
    NS.db.theme.border = { r = 1, g = 0, b = 0, a = 1 }
    NS:Fire("THEME_CHANGED")
    eq(edges.top.color[1], 1, "bordure recolorée après THEME_CHANGED")
    eq(edges.left:GetWidth(), NS.Pixel:Scale(1), "épaisseur = 1 pixel physique")
    UIParent:SetScale(768 / 1080)
    NS.Pixel:Update()
    NS:Fire("PIXEL_CHANGED")
    eq(edges.left:GetWidth(), 1, "recalculée après PIXEL_CHANGED")
    UIParent:SetScale(768 / 1080)
    NS.Pixel:Update()
    NS.db.theme.border = { r = 0, g = 0, b = 0, a = 1 }
end)

test("médias : texture de barre plate sans LibSharedMedia, contour de police du thème", function()
    reset()
    local Media = NS.Media
    eq(Media:StatusBarTexture(), "Interface\\Buttons\\WHITE8X8")
    local frame = CreateFrame("Frame", nil, UIParent)
    local plain = Media:CreateText(frame, "OVERLAY")
    local _, _, flags = plain:GetFont()
    eq(flags, "", "sans contour par défaut")
    eq(plain.shadowOffset[1], 1, "ombre présente sans contour")
    NS.db.theme.fontOutline = "OUTLINE"
    NS:Fire("THEME_CHANGED")
    _, _, flags = plain:GetFont()
    eq(flags, "OUTLINE", "contour du thème appliqué au texte existant")
    eq(plain.shadowOffset[1], 0, "ombre retirée avec le contour")
    local forced = Media:CreateText(frame, "OVERLAY", 0, "")
    _, _, flags = forced:GetFont()
    eq(flags, "", "flags explicites prioritaires")
    NS.db.theme.fontOutline = ""
    NS:Fire("THEME_CHANGED")
end)

test("migration v2 -> v3 : les profils existants gardent leur échelle (pixelPerfect = false)", function()
    local Database = NS.Database
    local db = { version = 2, profiles = { Default = { theme = { fontSize = 13 }, anchors = {}, modules = {} } },
                 profileKeys = {}, cvarBackup = {} }
    Database.Migrate(db)
    eq(db.version, 3)
    eq(db.profiles.Default.theme.pixelPerfect, false, "profil existant : pas de changement d'échelle")
    local fresh = Database.FillProfile({})
    eq(fresh.theme.pixelPerfect, true, "profil neuf : pixel perfect")
end)

test("pixel : un seul Apply en file pendant le combat", function()
    reset()
    local Pixel = NS.Pixel
    Mock.SetCombat(true)
    Pixel:Apply(); Pixel:Apply(); Pixel:Apply()
    eq(Pixel.queued, true)
    Mock.SetCombat(false)
    eq(Pixel.queued, false, "file vidée à la sortie du combat")
end)

test("Edit Mode : cacher et poser passent par les méthodes *Base, jamais par la surcharge Lua", function()
    local frame = CreateFrame("Frame", "AeonUITestEditModeSystem", UIParent)
    local calls = {}
    frame.HideBase, frame.Hide = frame.Hide, function() calls.hideOverride = true end
    frame.SetPointBase, frame.SetPoint = frame.SetPoint, function() calls.pointOverride = true end
    frame.ClearAllPointsBase, frame.ClearAllPoints = frame.ClearAllPoints, function() calls.clearOverride = true end
    frame:Show()
    NS.HideBlizzardFrame(frame, true)
    eq(frame:IsShown(), false, "caché par HideBase")
    NS.ClearPointsRaw(frame)
    NS.SetPointRaw(frame, "CENTER", UIParent, "CENTER", 0, 0)
    eq(calls.hideOverride, nil, "HideOverride jamais appelée")
    eq(calls.pointOverride, nil, "SetPointOverride jamais appelée")
    eq(calls.clearOverride, nil, "ClearAllPointsOverride jamais appelée")
    NS.ShowBlizzardFrame(frame)
end)

test("Edit Mode : une barre cachée par HideRegion et réaffichée par UpdateVisibility est recachée", function()
    local function EditModeBar(name)
        local bar = CreateFrame("Frame", name, UIParent)
        bar.ShowBase, bar.HideBase = bar.Show, bar.Hide
        bar.isShownExternal = true
        bar.Show = function() error("ShowOverride appelée depuis l'addon") end
        bar.UpdateVisibility = function(self) self:ShowBase() end
        return bar
    end
    local stance = EditModeBar("AeonUITestStanceBar")
    NS.HideRegion(stance)
    stance:UpdateVisibility()
    eq(stance:IsShown(), false, "HideRegion : recachée après UpdateVisibility")
    NS.ShowRegion(stance)
    eq(stance:IsShown(), true, "ShowRegion : ShowBase, jamais ShowOverride")
end)

-- tests/test_g_coeur.lua : conditions de visibilité cible douce / manette, couleur et filtre par nom
-- du mode déverrouillé, copie des couleurs entre profils, réglages communs des lueurs.
local T = ...
local NS, test, eq, truthy, reset = T.NS, T.test, T.eq, T.truthy, T.reset
local Visibility, Movers = NS.Visibility, NS.Movers

test("visibilité : cible douce et manette s'évaluent comme les autres conditions", function()
    local spec = Visibility.Spec({ softtarget = "yes", gamepad = "no" })
    truthy(Visibility.Evaluate(spec, { softtarget = true, gamepad = false }), "cible douce, sans manette")
    eq(Visibility.Evaluate(spec, { softtarget = true, gamepad = true }), false, "manette active : caché")
    eq(Visibility.Evaluate(spec, { softtarget = false, gamepad = false }), false, "sans cible douce : caché")
    spec.match = "any"
    truthy(Visibility.Evaluate(spec, { softtarget = false, gamepad = false }), "au moins une : manette absente suffit")
    eq(Visibility.Macro(Visibility.Spec({ softtarget = "yes", gamepad = "yes" })), nil, "pas de condition macro")
end)

test("visibilité : la manette filtre un cadre sécurisé sans condition macro", function()
    local spec = Visibility.Spec({ gamepad = "yes" })
    eq(Visibility.SecureLuaHidden(spec, { gamepad = false }), true, "sans manette : caché")
    eq(Visibility.SecureLuaHidden(spec, { gamepad = true }), false, "manette : visible")
    eq(Visibility.SecureLuaHidden(Visibility.Spec(), { gamepad = false }), false, "indifférent : rien")
    eq(Visibility.SecureLuaHidden({}, { gamepad = false }), false, "ancien profil sans le champ")
end)

test("visibilité : l'état suit la cible douce et le mode manette du client", function()
    reset()
    eq(Visibility.State().softtarget, false, "pas de cible douce")
    Mock.units.softenemy = { name = "Cible" }
    eq(Visibility.State().softtarget, true, "cible douce")
    Mock.units.softenemy = nil
    local previousPad, previousUsing = _G.C_GamePad, _G.IsUsingGamepad
    _G.C_GamePad = { IsEnabled = function() return true end }
    _G.IsUsingGamepad = function() return false end
    eq(NS.GamepadActive(), false, "manette activée mais clavier en main")
    _G.IsUsingGamepad = function() return true end
    eq(NS.GamepadActive(), true, "manette active")
    eq(Visibility.State().gamepad, true, "état manette")
    _G.C_GamePad = nil
    eq(NS.GamepadActive(), false, "API absente")
    _G.C_GamePad, _G.IsUsingGamepad = previousPad, previousUsing
end)

test("mode déverrouillé : couleur de l'accent par défaut, couleur choisie sinon", function()
    reset()
    local ar, ag, ab = NS.Media:Accent()
    local r, g, b = NS.Media:MoverColor()
    eq(r, ar); eq(g, ag); eq(b, ab)
    NS.db.theme.moverCustom = true
    NS.db.theme.moverColor = { r = 1, g = 0, b = 0.5 }
    r, g, b = NS.Media:MoverColor()
    eq(r, 1); eq(g, 0); eq(b, 0.5)
end)

test("mode déverrouillé : filtre par nom (sans casse) et remise à zéro au verrouillage", function()
    reset()
    local one = CreateFrame("Frame", nil, UIParent)
    local two = CreateFrame("Frame", nil, UIParent)
    one:SetSize(10, 10); two:SetSize(10, 10)
    Movers:Register("gTestAlpha", one, "Barre Alpha", "CENTER", 0, 0)
    Movers:Register("gTestBeta", two, "Cadre Beta", "CENTER", 0, 50)
    NS:SetUnlocked(true)
    Movers:SetNameFilter("  ALPHA ")
    truthy(Movers:IsListed(Movers.registry.gTestAlpha), "nom trouvé")
    eq(Movers:IsListed(Movers.registry.gTestBeta), false, "autre nom écarté")
    eq(Movers.registry.gTestBeta.overlay:IsShown(), false, "calque caché")
    Movers:SetNameFilter("")
    truthy(Movers:IsListed(Movers.registry.gTestBeta), "filtre vide : tous")
    Movers:SetNameFilter("beta")
    NS:SetUnlocked(false)
    eq(Movers.nameFilter, nil, "filtre oublié au verrouillage")
end)

test("profils : couleurs copiées vers tous les profils, le reste intact", function()
    reset()
    local db = NS.Database
    local profiles = NS.global.profiles
    profiles.GTestOther = db.FillProfile({})
    profiles.GTestOther.theme.fontSize = 17
    local active = db:ActiveProfileName()
    NS.db.theme.accent.r, NS.db.theme.accent.g, NS.db.theme.accent.b = 0.9, 0.1, 0.2
    NS.db.theme.moverCustom = true
    truthy(db:CopyThemeColorsToAll(active) >= 1, "au moins un profil reçoit")
    local other = profiles.GTestOther.theme
    eq(other.accent.r, 0.9); eq(other.accent.g, 0.1)
    eq(other.moverCustom, true)
    eq(other.fontSize, 17, "police du profil gardée")
    eq(db:CopyThemeColors(active, active), false, "même profil : rien")
    profiles.GTestOther = nil
end)

test("profils : une variante garde l'accent et la bordure copiés, et son propre écart", function()
    reset()
    local db = NS.Database
    local profiles = NS.global.profiles
    local active = db:ActiveProfileName()
    local variant = db:CreateVariant(active, "GTestVariant")
    truthy(variant, "variante créée")
    profiles[variant].theme.fontSize = 19
    db:CaptureVariants()
    -- Tirer les couleurs d'un autre profil dans le profil actif.
    profiles.GTestSource = db.FillProfile({})
    profiles.GTestSource.theme.border.r = 0.3
    profiles.GTestSource.theme.accent.g = 0.6
    truthy(db:CopyThemeColors("GTestSource", active), "copie")
    db:SyncVariants(NS.db)
    eq(profiles[variant].theme.border.r, 0.3, "bordure suivie par la variante")
    eq(profiles[variant].theme.accent.g, 0.6, "accent suivi par la variante")
    eq(profiles[variant].theme.fontSize, 19, "écart propre gardé")
    -- Appliquer les couleurs à tous les profils, variante comprise.
    NS.db.theme.border.r = 0.7
    db:CopyThemeColorsToAll(active)
    db:SyncVariants(nil)
    eq(profiles[variant].theme.border.r, 0.7, "bordure gardée après « à tous »")
    eq(profiles[variant].theme.fontSize, 19, "écart propre gardé après « à tous »")
    profiles.GTestSource, profiles[variant], NS.global.profileVariants[variant] = nil, nil, nil
end)

test("lueurs : réglages communs bornés, défauts = rendu d'origine", function()
    reset()
    local thickness, speed = NS.Glow.Settings()
    eq(thickness, 2); eq(speed, 1)
    NS.db.theme.glowThickness, NS.db.theme.glowSpeed = 9, 0.1
    thickness, speed = NS.Glow.Settings()
    eq(thickness, 4, "épaisseur bornée"); eq(speed, 0.5, "vitesse bornée")
    NS.db.theme.glowThickness, NS.db.theme.glowSpeed = nil, nil
    thickness, speed = NS.Glow.Settings()
    eq(thickness, 2); eq(speed, 1)
end)

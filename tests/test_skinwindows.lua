-- tests/test_skinwindows.lua : fiche de personnage et amis au thème, réversible.
local T = ...
local NS, test, eq, truthy, reset = T.NS, T.test, T.eq, T.truthy, T.reset

test("habillage : fiche de personnage au thème puis rendue, bordure de qualité sur l'équipement", function()
    reset()
    local Skin = NS.Modules:Get("skin")
    local slot = _G.CharacterHeadSlot or CreateFrame("Button", "CharacterHeadSlot", CharacterFrame)
    slot.icon = slot.icon or slot:CreateTexture()
    Mock.equipped[1] = { quality = 4 }
    local qualityColor = C_Item.GetItemQualityColor
    C_Item.GetItemQualityColor = function() return 0.64, 0.21, 0.93 end
    NS.db.modules.skin.skinWindows = true
    Skin:OnRefresh()
    eq(CharacterFrame.NineSlice:GetAlpha(), 0, "art Blizzard effacé")
    eq(CharacterFrame.Bg:GetAlpha(), 0)
    truthy(slot.icon.texCoord[1] > 0, "icône recadrée")
    NS.db.modules.skin.skinWindows = false
    Skin:OnRefresh()
    eq(CharacterFrame.NineSlice:GetAlpha(), 1, "art rendu")
    eq(CharacterFrame.Bg:GetAlpha(), 1)
    C_Item.GetItemQualityColor = qualityColor
    Mock.equipped[1] = nil
end)

test("habillage : panneaux sombres, titre lisible ; infobulle interdite jamais stylée", function()
    reset()
    local Skin = NS.Modules:Get("skin")
    local panel = CreateFrame("Frame", nil, UIParent)
    panel.TitleContainer = CreateFrame("Frame", nil, panel)
    local art = panel.TitleContainer:CreateTexture()
    local title = panel.TitleContainer:CreateFontString()
    Skin.DarkenPanel(panel, true)
    eq(art.vertex[1], 0.25, "art de la barre de titre assombri")
    eq(title.vertex, nil, "texte du titre intact")

    local forbidden = CreateFrame("GameTooltip", "AeonForbiddenTooltip", UIParent)
    forbidden.IsForbidden = function() return true end
    forbidden.NineSlice = { SetCenterColor = function() error("infobulle interdite touchée") end }
    SharedTooltip_SetBackdropStyle(forbidden)   -- le hook du module passe par StyleTooltip
end)

test("habillage : inspection habillée comme la fiche, emplacements peints à INSPECT_READY", function()
    reset()
    local Skin = NS.Modules:Get("skin")
    local inspect = _G.InspectFrame or CreateFrame("Frame", "InspectFrame", UIParent)
    inspect.NineSlice = inspect.NineSlice or CreateFrame("Frame", nil, inspect)
    local slot = _G.InspectHeadSlot or CreateFrame("Button", "InspectHeadSlot", inspect)
    slot.icon = slot.icon or slot:CreateTexture()
    Mock.equipped[1] = { link = 40, quality = 4 }
    inspect.unit = nil
    NS.db.modules.skin.skinWindows = true
    Skin:OnRefresh()
    eq(inspect.NineSlice:GetAlpha(), 0, "art de l'inspection effacé")
    eq(slot.icon.texCoord and slot.icon.texCoord[1] or 0, 0, "unité inconnue : emplacement laissé")
    inspect.unit = "target"
    Mock.FireEvent("INSPECT_READY", "Target-1")
    truthy(slot.icon.texCoord[1] > 0, "icône recadrée une fois l'unité lue")
    NS.db.modules.skin.skinWindows = false
    Skin:OnRefresh()
    eq(inspect.NineSlice:GetAlpha(), 1, "art rendu")
    eq(slot.icon.texCoord[1], 0, "recadrage rendu")
    Mock.equipped[1] = nil
    inspect.unit = nil
end)

test("habillage : style par fenêtre (exception sur le défaut), popup, interrupteur général, migration v5", function()
    reset()
    local Skin = NS.Modules:Get("skin")
    local db = NS.db.modules.skin
    local popup = _G.StaticPopup1 or CreateFrame("Frame", "StaticPopup1", UIParent)
    popup.Border = popup.Border or CreateFrame("Frame", nil, popup)
    local edge = popup.Border:CreateTexture()
    db.skinWindows, db.windowStyle = true, "theme"
    db.windowStyles.StaticPopup1 = "dark"
    db.windowStyles.FriendsFrame = "blizzard"
    Skin:OnRefresh()
    eq(Skin:WindowStyle("CharacterFrame"), "theme")
    eq(CharacterFrame.NineSlice:GetAlpha(), 0, "défaut : thème")
    eq(popup.Border:GetAlpha(), 1, "popup : pas effacée")
    eq(edge.vertex[1], 0.25, "popup : bordure assombrie")
    eq(Skin:WindowStyle("StaticPopup1"), "dark")
    eq(Skin:WindowStyle("FriendsFrame"), "blizzard")
    db.windowStyles.StaticPopup1 = ""
    eq(Skin:WindowStyle("StaticPopup1"), "theme", "vide : style par défaut")
    db.skinWindows = false
    Skin:OnRefresh()
    eq(Skin:WindowStyle("CharacterFrame"), "blizzard", "interrupteur coupé")
    eq(CharacterFrame.NineSlice:GetAlpha(), 1, "art rendu")
    eq(edge.vertex[1], 1, "teinte rendue")
    db.windowStyles = {}

    local old = { version = 4, profiles = {
        A = { modules = { skin = { darkPanels = true, skinWindows = true } } },
        B = { modules = { skin = { darkPanels = false, skinWindows = true } } } } }
    NS.Database.Migrate(old)
    local a, b = old.profiles.A.modules.skin, old.profiles.B.modules.skin
    eq(a.windowStyle, "dark")
    eq(a.windowStyles.CharacterFrame, "theme", "fiche au thème gardée")
    eq(a.skinWindows, true)
    eq(a.darkPanels, nil)
    eq(b.windowStyle, "blizzard", "sans panneaux sombres : seules les trois fenêtres au thème")
    eq(b.windowStyles.FriendsFrame, "theme")
    eq(b.skinWindows, true)
end)

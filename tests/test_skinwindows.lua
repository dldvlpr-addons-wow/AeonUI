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

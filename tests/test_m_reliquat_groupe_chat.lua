-- tests/test_m_reliquat_groupe_chat.lua : nom au-dessus des auras, décalages des textes d'aura,
-- contour et ombre du chat, cases du texte de combat flottant.
local T = ...
local NS, test, eq, truthy, reset = T.NS, T.test, T.eq, T.truthy, T.reset
local GF = NS.Modules:Get("groupframes")
local Interface = NS.Modules:Get("interface")

test("groupes : nom au-dessus des auras, hôte au niveau supérieur puis retour à l'overlay", function()
    reset()
    GF.db.nameAboveAuras = true
    NS.Modules:SetEnabled("groupframes", true)
    Mock.SetGroup(2, false)
    local button = GF:GetButton("party1")
    truthy(button.nameHost, "hôte créé")
    eq(button.name:GetParent(), button.nameHost, "nom sur l'hôte")
    GF.db.nameAboveAuras = false
    NS.Modules:Refresh("groupframes")
    eq(button.name:GetParent(), button.overlay, "nom revenu sur l'overlay")
    NS.Modules:SetEnabled("groupframes", false)
end)

test("groupes : décalages des textes d'aura transmis au style", function()
    reset()
    GF.db.auraCountOffsetX, GF.db.auraDurationOffsetY = 3, -2
    NS.Modules:SetEnabled("groupframes", true)
    Mock.SetGroup(2, false)
    local button = GF:GetButton("party1")
    Mock.auraContainer = true
    NS.auraContainerProbe = nil
    button.auras = nil
    NS.Modules:Refresh("groupframes")
    local style = button.auras and button.auras.auraStyle
    truthy(style, "style posé")
    eq(style.countOffsetX, 3, "décalage des piles")
    eq(style.durationOffsetY, -2, "décalage de la durée")
    GF.db.auraCountOffsetX, GF.db.auraDurationOffsetY = 0, 0
    button.auras = nil
    NS.Modules:SetEnabled("groupframes", false)
end)

test("chat : contour propre au chat et ombre", function()
    reset()
    local Chat = NS.Modules:Get("chat")
    NS.Modules:SetEnabled("chat", true)
    Chat.db.fontOutline, Chat.db.fontShadow = "THICKOUTLINE", true
    Chat:OnRefresh()
    eq(ChatFrame1.fontFlags, "THICKOUTLINE", "contour du chat")
    eq(ChatFrame1.shadowOffset[1], 1, "ombre")
    Chat.db.fontOutline, Chat.db.fontShadow = "", false
    Chat:OnRefresh()
    eq(ChatFrame1.fontFlags, "", "sans contour : flags non nil")
    eq(ChatFrame1.shadowOffset[1], 0, "décochée : ombre d'origine du mock rétablie")
    Chat.db.fontOutline = "inherit"
    NS.Modules:SetEnabled("chat", false)
end)

test("interface : cases du texte flottant seulement pour les CVars présentes", function()
    reset()
    Mock.cvars.floatingCombatTextAuras_v2 = "0"
    local labels = {}
    local noop = function() end
    local o = setmetatable({ layout = { Check = function(_, label) labels[#labels + 1] = label end, Slider = noop } },
        { __index = function() return noop end })
    Interface:BuildOptions(o)
    local found = false
    for _, label in ipairs(labels) do if label == NS.L.OPT_UI_FCT_AURAS then found = true end end
    truthy(found, "case des auras")
    for _, label in ipairs(labels) do truthy(label ~= NS.L.OPT_UI_FCT_HONOR, "CVar absente : pas de case") end
    Mock.cvars.floatingCombatTextAuras_v2 = nil
end)

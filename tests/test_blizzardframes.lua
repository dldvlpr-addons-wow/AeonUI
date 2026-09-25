-- tests/test_blizzardframes.lua : cadres Blizzard déplaçables (recharges, buffs).
local T = ...
local NS, test, eq, truthy, reset = T.NS, T.test, T.eq, T.truthy, T.reset

test("cadres Blizzard : viewers et buffs adoptés par des movers, laissés à Edit Mode sur option, rendus au disable", function()
    reset()
    NS.Modules:SetEnabled("blizzardframes", true)
    local point, relTo = EssentialCooldownViewer:GetPoint()
    eq(point, "CENTER"); eq(relTo, AeonUI_Holder_cdm_essential)
    eq(EssentialCooldownViewer:GetParent(), UIParent, "jamais reparenté")
    local bpoint, brel = BuffFrame:GetPoint()
    eq(bpoint, "TOPRIGHT"); eq(brel, AeonUI_Holder_buffs)
    truthy(NS.Movers:Anchor("cdm_buffbar") and NS.Movers:Anchor("debuffs"))
    EssentialCooldownViewer:ClearAllPoints()
    EssentialCooldownViewer:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 0)
    local _, again = EssentialCooldownViewer:GetPoint()
    eq(again, AeonUI_Holder_cdm_essential, "Edit Mode le replace : le hook reprend la main")
    NS.db.modules.blizzardframes.buffs = "keep"
    NS.Modules:Refresh("blizzardframes")
    eq(AeonUI_Holder_buffs:IsShown(), false)
    eq(NS.Movers:List()[1] ~= nil, true)
    NS.db.modules.blizzardframes.buffs = "move"
    NS.Modules:SetEnabled("blizzardframes", false)
    eq(AeonUI_Holder_cdm_essential:IsShown(), false)
    truthy(Mock.FindPrinted("/reload"))
end)

test("gestionnaire de recharges : sort masqué rendu transparent, les suivants remontent, lueur quand prêt", function()
    reset()
    local viewer = EssentialCooldownViewer
    local items = {}
    for i, spellID in ipairs({ 100, 200, 300 }) do
        local item = CreateFrame("Frame", nil, viewer)
        item.layoutIndex, item.cooldownID = i, spellID
        items[i] = item
    end
    viewer.itemFramePool = { EnumerateActive = function() local i = 0 return function() i = i + 1 return items[i] end end }
    viewer.Layout = function()
        for i, item in ipairs(items) do item:ClearAllPoints() item:SetPoint("LEFT", viewer, "LEFT", (i - 1) * 40, 0) item:Show() end
    end
    _G.C_CooldownViewer = { GetCooldownViewerCooldownInfo = function(id) return { spellID = id } end }
    C_Spell.GetSpellCooldown = function(id) return { isActive = id ~= 300, isOnGCD = false } end
    NS.db.modules.cooldownmanager.spells = { [100] = { hidden = true }, [300] = { glow = "ready" } }
    NS.Modules:SetEnabled("cooldownmanager", true)
    viewer:Layout()
    eq(items[1]:GetAlpha(), 0, "masqué")
    eq(select(4, items[2]:GetPoint()), 0, "le deuxième prend la première place")
    eq(select(4, items[3]:GetPoint()), 40, "le troisième remonte")
    eq(select(2, items[1]:GetPoint()), UIParent, "le masqué est parqué hors de la barre")
    items[1]:SetAlpha(1)   -- Blizzard relève l'alpha
    NS.Modules:Refresh("cooldownmanager")
    eq(items[1]:GetAlpha(), 0, "remasqué")
    eq(select(4, items[3]:GetPoint()), 40, "nouveau passage sans Layout : places inchangées")
    eq(items[3].foreverGlow:IsShown(), true, "prêt : lueur")
    eq(items[2].foreverGlow, nil, "sans réglage : aucune lueur")
    NS.Modules:SetEnabled("cooldownmanager", false)
    eq(items[1]:GetAlpha(), 1, "rendu au disable")
    eq(select(4, items[1]:GetPoint()), 0, "place d'origine rendue")
    eq(items[3].foreverGlow:IsShown(), false)
    viewer.itemFramePool, viewer.Layout, _G.C_CooldownViewer, C_Spell.GetSpellCooldown = nil, nil, nil, nil
end)

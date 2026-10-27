-- tests/test_g_lot1.lua : débuffs de bruit des cadres de groupe, reset d'une fenêtre déplaçable,
-- infobulle des boutons d'action.
local T = ...
local NS, test, eq, truthy, reset = T.NS, T.test, T.eq, T.truthy, T.reset
local GF = NS.Modules:Get("groupframes")

test("groupes : débuffs de bruit (Rassasié, Longanimité, Âme affaiblie) écartés par défaut", function()
    reset()
    eq(GF.db.hideNoiseDebuffs, true, "coché par défaut")
    NS.Modules:SetEnabled("groupframes", true)
    Mock.SetGroup(2, false)
    Mock.auraContainer = true
    NS.auraContainerProbe = nil
    local button = GF:GetButton("party1")
    button.auras = nil
    NS.Modules:Refresh("groupframes")
    local engine = button.auras and button.auras.engine
    truthy(engine, "moteur")
    local exclude = engine.groups.duration.options.candidateFilters.excludeSpellIDs
    truthy(exclude, "liste d'exclusion")
    for _, id in ipairs({ 57723, 57724, 80354, 25771, 6788 }) do eq(exclude[id], true, "id " .. id) end
    GF.db.hideNoiseDebuffs = false
    button.auras = nil
    NS.Modules:Refresh("groupframes")
    exclude = button.auras.engine.groups.duration.options.candidateFilters.excludeSpellIDs
    eq(exclude and exclude[25771], nil, "décoché : rien d'écarté")
    GF.db.hideNoiseDebuffs = true
    button.auras = nil
    NS.Modules:SetEnabled("groupframes", false)
end)

test("fenêtres déplaçables : réinitialiser une seule fenêtre", function()
    reset()
    local MovableWindows = NS.Modules:Get("movablewindows")
    local positions = NS.db.modules.movablewindows.positions
    positions.MerchantFrame = { "TOPLEFT", "BOTTOMLEFT", 1, 2 }
    positions.MailFrame = { "TOPLEFT", "BOTTOMLEFT", 3, 4 }
    MovableWindows.ResetWindow("MerchantFrame")
    eq(NS.db.modules.movablewindows.positions.MerchantFrame, nil, "fenêtre oubliée")
    truthy(NS.db.modules.movablewindows.positions.MailFrame, "les autres gardées")
end)

test("barres : infobulle des boutons masquée selon le réglage", function()
    reset()
    local AB = NS.Modules:Get("actionbars")
    NS.Modules:SetEnabled("actionbars", true)
    local button = AB:GetBar(1).buttons[1]
    local function Hover()
        GameTooltip:Show()
        button:GetScript("OnEnter")(button)
        return GameTooltip:IsShown()
    end
    AB.db.buttonTooltip = "show"
    truthy(Hover(), "toujours : visible")
    AB.db.buttonTooltip = "hideInCombat"
    truthy(Hover(), "hors combat : visible")
    Mock.SetCombat(true)
    eq(Hover(), false, "en combat : masquée")
    Mock.SetCombat(false)
    AB.db.buttonTooltip = "hide"
    eq(Hover(), false, "jamais : masquée")
    AB.db.buttonTooltip = "show"
    NS.Modules:SetEnabled("actionbars", false)
end)

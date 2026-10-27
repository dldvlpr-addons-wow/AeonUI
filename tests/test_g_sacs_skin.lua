-- tests/test_g_sacs_skin.lua : lot G « sacs, habillage, quêtes » : infobulles (opacité, bordure,
-- modificateur, pile max, barre de vie), sacs (couleur du niveau, camelote grise, zoom, tri vers
-- le bas), suivi de quêtes (objectifs estompés, fond, couleur de classe).
local T = ...
local NS, L, test, eq, truthy, reset = T.NS, T.L, T.test, T.eq, T.truthy, T.reset

local function HasLine(tooltip, text)
    for _, line in ipairs(tooltip.lines or {}) do if line == text then return true end end
    return false
end

test("infobulles : opacité du fond et style de bordure", function()
    reset()
    NS.Modules:SetEnabled("skin", true)
    local db = NS.db.modules.skin
    db.tooltipOpacity, db.tooltipBorder = 50, "none"
    NS.Modules:Refresh("skin")
    eq(GameTooltip.center[4], 0.5, "fond à 50 %")
    eq(GameTooltip.border[4], 0, "bordure masquée")
    db.tooltipBorder = "theme"
    NS.Modules:Refresh("skin")
    eq(GameTooltip.border[1], NS.db.theme.border.r, "couleur de bordure du thème")
end)

test("infobulles : identifiants et pile max derrière le modificateur", function()
    reset()
    local db = NS.db.modules.skin
    Mock.items[6948] = { maxStack = 20 }
    db.tooltipIDs, db.tooltipStackSize, db.tooltipIDModifier = true, true, "shift"
    Mock.shift = false
    Mock.ShowDataTooltip(Enum.TooltipDataType.Item, { id = 6948 })
    eq(#(GameTooltip.lines or {}), 0, "sans Maj : rien")
    Mock.shift = true
    Mock.ShowDataTooltip(Enum.TooltipDataType.Item, { id = 6948 })
    truthy(HasLine(GameTooltip, string.format(L.TOOLTIP_ID, "6948")), "ID avec Maj")
    truthy(HasLine(GameTooltip, string.format(L.OPT_G_SKIN_LINE_STACK_SIZE, 20)), "pile max")
    Mock.items[6948].maxStack = 1
    Mock.ShowDataTooltip(Enum.TooltipDataType.Item, { id = 6948 })
    eq(HasLine(GameTooltip, string.format(L.OPT_G_SKIN_LINE_STACK_SIZE, 1)), false, "objet non empilable : pas de ligne")
    Mock.shift = false
    db.tooltipIDs, db.tooltipStackSize, db.tooltipIDModifier = false, false, "always"
end)

test("infobulles : hauteur de la barre de vie réglée puis rendue", function()
    reset()
    NS.Modules:SetEnabled("skin", true)
    local db = NS.db.modules.skin
    db.healthBarHeight = 14
    NS.Modules:Refresh("skin")
    eq(GameTooltipStatusBar:GetHeight(), 14)
    db.healthBarHeight = 0
    NS.Modules:Refresh("skin")
    eq(GameTooltipStatusBar:GetHeight(), 8, "hauteur Blizzard rendue")
end)

test("sacs : niveau blanc, camelote grisée, recadrage, rendus au disable", function()
    reset()
    Mock.items[10] = { sellPrice = 5 }
    Mock.items[20] = { sellPrice = 900, equipLoc = "INVTYPE_HEAD" }
    Mock.equipped[1] = { link = 20, level = 45, quality = 3 }
    Mock.bags[0][1] = { itemID = 10, quality = 0 }
    Mock.bags[0][2] = { itemID = 20, quality = 3 }
    local db = NS.db.modules.bags
    db.itemLevelColor, db.junkGray, db.iconZoom, db.qualityBorder = "white", true, 10, false
    for index = 1, 40 do
        local button = ContainerFrame1.pool[index] or CreateFrame("Button", nil, ContainerFrame1)
        ContainerFrame1.pool[index] = button
        button.icon = button.icon or button:CreateTexture(nil, "BACKGROUND")
    end
    NS.Modules:SetEnabled("bags", true)
    OpenAllBags()
    local _, buttons = NS.Modules:Get("bags"):GetWindow()
    local junk, helm = buttons[0][1], buttons[0][2]
    eq(helm.muscaLevel.textColor[3], 1, "niveau blanc")
    eq(junk.icon.desaturatedTexture, true, "camelote grisée")
    eq(junk.icon.texCoord[1], 0.1, "icône recadrée")
    eq(helm.muscaBorder.top.color[1], NS.db.theme.border.r, "bordure de qualité retirée")
    db.junkGray, db.iconZoom = false, 0
    NS.Modules:Refresh("bags")
    eq(junk.icon.desaturatedTexture, false, "gris retiré")
    NS.Modules:SetEnabled("bags", false)
    db.itemLevelColor, db.qualityBorder = "quality", true
end)

test("sacs : tri vers le bas, état du client rendu au disable", function()
    reset()
    local state = false
    C_Container.GetSortBagsRightToLeft = function() return state end
    C_Container.SetSortBagsRightToLeft = function(value) state = value end
    NS.db.modules.bags.sortToBottom = true
    NS.Modules:SetEnabled("bags", true)
    eq(state, true, "tri vers le bas actif")
    NS.Modules:SetEnabled("bags", false)
    eq(state, false, "réglage d'origine rendu")
    eq(NS.db.modules.bags.sortToBottomOriginal, nil, "origine effacée")
    -- /reload avec l'option active : l'origine gardée en base n'est pas recapturée.
    NS.db.modules.bags.sortToBottomOriginal = false
    state = true
    NS.Modules:SetEnabled("bags", true)
    NS.Modules:SetEnabled("bags", false)
    eq(state, false, "origine de la base rendue après rechargement")
    -- option jamais cochée : rien n'est écrit.
    NS.db.modules.bags.sortToBottom = false
    state = true
    NS.Modules:SetEnabled("bags", true)
    NS.Modules:SetEnabled("bags", false)
    eq(state, true, "réglage du client intact")
    NS.db.modules.bags.sortToBottom = true
    NS.db.modules.bags.sortToBottom = false
    C_Container.GetSortBagsRightToLeft, C_Container.SetSortBagsRightToLeft = nil, nil
end)

test("suivi de quêtes : objectifs terminés estompés, fond, couleur de classe", function()
    reset()
    local db = NS.db.modules.questtracker
    local function Block(id)
        local block = { id = id, HeaderText = ObjectiveTrackerFrame:CreateFontString(), usedLines = {} }
        block.usedLines[1] = { Text = ObjectiveTrackerFrame:CreateFontString(), SetAlpha = function(self, a) self.alpha = a end }
        block.usedLines[2] = { Text = ObjectiveTrackerFrame:CreateFontString(), SetAlpha = function(self, a) self.alpha = a end }
        return block
    end
    local open = Block(2)
    ObjectiveTrackerFrame.modules[1].usedBlocks = { QuestTemplate = { [2] = open } }
    local before = _G.C_QuestLog
    _G.C_QuestLog = {
        IsComplete = function() return false end,
        GetQuestObjectives = function() return { { finished = true }, { finished = false } } end,
    }
    db.dimCompleted, db.backgroundOpacity, db.accentLine, db.colorSource = 40, 60, true, "class"
    NS.Modules:SetEnabled("questtracker", true)
    eq(open.usedLines[1].alpha, 0.4, "objectif fini estompé")
    eq(open.usedLines[2].alpha, nil, "objectif en cours intact")
    local holder = _G.MuscaUI_QuestTracker
    truthy(holder.background:IsShown(), "fond")
    truthy(holder.accentLine:IsShown(), "filet d'accent")
    db.dimCompleted = 100
    NS.Modules:Refresh("questtracker")
    eq(open.usedLines[1].alpha, 1, "opacité rendue")
    NS.Modules:SetEnabled("questtracker", false)
    ObjectiveTrackerFrame.modules[1].usedBlocks = nil
    _G.C_QuestLog = before
    db.dimCompleted, db.backgroundOpacity, db.accentLine, db.colorSource = 100, 0, false, "custom"
end)

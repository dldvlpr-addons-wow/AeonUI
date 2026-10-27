-- tests/test_m9_qol.lua : lot M9 (fonctions Forever et qualité de vie) : cadrans GCD et incantation du
-- curseur, forme active, filtres du fil de butin, or par heure, menu d'équipement, annonce sonore et
-- vocale, /way, carte estompée en déplacement, barres de jet cachées après un délai.
local T = ...
local NS, test, eq, truthy, reset = T.NS, T.test, T.eq, T.truthy, T.reset

local saved = {}
local function Set(name, value)
    if saved[name] == nil then saved[name] = { _G[name] } end
    _G[name] = value
end
local function Restore()
    for name, box in pairs(saved) do _G[name] = box[1] end
    saved = {}
end

test("curseur : cadrans de recharge globale et d'incantation", function()
    reset()
    local Cursor = NS.Modules:Get("cursor")
    NS.Modules:SetEnabled("cursor", true)
    Cursor.db.gcdRing, Cursor.db.castRing = true, true
    NS.Modules:Refresh("cursor")
    local ring = _G.MuscaUICursorRing
    local gcdApi = C_Spell.GetSpellCooldownDuration
    C_Spell.GetSpellCooldownDuration = function(id) if id == 29515 then return Mock.gcdDuration end end
    Mock.gcdDuration = { gcd = true }
    Mock.FireEvent("SPELL_UPDATE_COOLDOWN")
    eq(ring.gcd.painted, Mock.gcdDuration, "GCD : objet durée posé")
    local cast = { cast = true }
    Set("UnitCastingDuration", function() return cast end)
    Mock.FireEvent("UNIT_SPELLCAST_START", "player")
    truthy(ring.cast:IsShown(), "incantation : cadran visible")
    eq(ring.cast.painted, cast)
    Mock.FireEvent("UNIT_SPELLCAST_STOP", "player")
    eq(ring.cast:IsShown(), false, "fin : cadran caché")
    Set("UnitCastingDuration", function() return nil end)
    Mock.FireEvent("UNIT_SPELLCAST_START", "player")
    eq(ring.cast:IsShown(), false, "sans durée : caché")
    Restore()
    Mock.gcdDuration, C_Spell.GetSpellCooldownDuration = nil, gcdApi
    Cursor.db.gcdRing, Cursor.db.castRing = false, false
    NS.Modules:SetEnabled("cursor", false)
end)

test("forme active : icône de la forme, cachée sans forme", function()
    reset()
    Mock.shapeshiftForm, Mock.formIcons[2] = 2, 132115
    NS.Modules:SetEnabled("activeform", true)
    local holder = _G.MuscaUIActiveForm
    truthy(holder:IsShown(), "forme : visible")
    eq(holder.icon:GetTexture(), 132115)
    Mock.shapeshiftForm = 0
    Mock.FireEvent("UPDATE_SHAPESHIFT_FORM")
    eq(holder:IsShown(), false, "aucune forme : caché")
    NS.Modules:SetEnabled("activeform", false)
    Mock.shapeshiftForm, Mock.formIcons[2] = nil, nil
end)

test("fil de butin : qualité minimale, niveau, prix, or par heure", function()
    reset()
    Set("LOOT_ITEM_SELF", "You receive loot: %s.")
    Set("YOU_LOOT_MONEY", "You loot %s")
    Set("GOLD_AMOUNT", "%d Gold")
    Set("SILVER_AMOUNT", "%d Silver")
    Set("COPPER_AMOUNT", "%d Copper")
    local LootFeed = NS.Modules:Get("lootfeed")
    local db = LootFeed.db
    db.minQuality, db.itemLevel, db.itemPrice, db.goldPerHour = 2, true, true, true
    NS.Modules:SetEnabled("lootfeed", false)
    NS.Modules:SetEnabled("lootfeed", true)   -- session d'or remise à zéro
    local grey = "|Hitem:501|h[Gris]|h"
    local sword = "|Hitem:502|h[Épée]|h"
    Mock.items[grey] = { quality = 0, sellPrice = 5 }
    Mock.items[sword] = { quality = 3, sellPrice = 250, level = 31, equipLoc = "INVTYPE_WEAPON" }
    Mock.FireEvent("CHAT_MSG_LOOT", "You receive loot: " .. grey .. ".")
    Mock.FireEvent("CHAT_MSG_LOOT", "You receive loot: " .. sword .. ".")
    local entries = {}
    for _, line in ipairs(LootFeed.Lines()) do if line.key then entries[line.key] = line.entry end end
    eq(entries["item:501"], nil, "médiocre : filtré")
    local entry = entries["item:502"]
    truthy(entry, "rare : affiché")
    eq(entry.level, 31); eq(entry.price, 250)
    Mock.items[sword].equipLoc = "INVTYPE_NON_EQUIP_IGNORE"
    Mock.Advance(LootFeed.db.duration + 1, 0.5)   -- ligne expirée : la suivante est neuve
    Mock.FireEvent("CHAT_MSG_LOOT", "You receive loot: " .. sword .. ".")
    for _, line in ipairs(LootFeed.Lines()) do if line.key == "item:502" then entry = line.entry end end
    eq(entry.level, nil, "non équipable : sans niveau")
    NS.Modules:SetEnabled("lootfeed", false)
    NS.Modules:SetEnabled("lootfeed", true)
    Mock.FireEvent("CHAT_MSG_LOOT", "You loot 1 Gold")
    eq(LootFeed.GoldPerHour(), 10000 * 60, "1 or en moins d'une minute : 60 or / h")
    Mock.Advance(240, 1)
    eq(LootFeed.GoldPerHour(), 10000 * 3600 / 240, "1 or en 4 min : 15 or / h")
    db.minQuality, db.itemLevel, db.itemPrice, db.goldPerHour = 0, false, false, false
    Mock.items[grey], Mock.items[sword] = nil, nil
    NS.Modules:Refresh("lootfeed")
    Restore()
end)

test("équipement : niveau d'objet dans le menu d'équipement", function()
    reset()
    local Gear = NS.Modules:Get("gear")
    Gear.db.flyout = true
    NS.Modules:Refresh("gear")
    local itemLocation = { IsValid = function() return true end }
    Set("EQUIPMENTFLYOUT_FIRST_SPECIAL_LOCATION", 0xFFFFFFFD)
    Set("EquipmentManager_GetLocationData", function() return { isBags = true, bag = 0, slot = 3 } end)
    Set("ItemLocation", { CreateFromBagAndSlot = function() return itemLocation end })
    local level, quality = C_Item.GetCurrentItemLevel, C_Item.GetItemQuality
    C_Item.GetCurrentItemLevel = function(location) return location == itemLocation and 42 or nil end
    C_Item.GetItemQuality = function() return 4 end
    local button = CreateFrame("Button", nil, UIParent)
    button.location = 7
    Gear.UpdateFlyoutButton(button)
    eq(button.muscaLevel.text, 42)
    truthy(button.muscaLevel:IsShown())
    button.location = 0xFFFFFFFD
    Gear.UpdateFlyoutButton(button)
    eq(button.muscaLevel:IsShown(), false, "bouton spécial : rien")
    Gear.db.flyout = false
    button.location = 7
    Gear.UpdateFlyoutButton(button)
    eq(button.muscaLevel:IsShown(), false, "option coupée : rien")
    C_Item.GetCurrentItemLevel, C_Item.GetItemQuality = level, quality
    Restore()
    NS.Modules:Refresh("gear")
end)

test("mouvement : son et voix à la fin de la recharge", function()
    reset()
    local MovementAlert = NS.Modules:Get("movementalert")
    local tracked, isReady, play = MovementAlert.TrackedSpells, NS.IsSpellReady, NS.PlayPreset
    local ready, played = false, nil
    MovementAlert.TrackedSpells = function() return { { id = 2983, name = "Sprint" } } end
    NS.IsSpellReady = function() return ready end
    NS.PlayPreset = function(preset) played = preset end
    Mock.spoken = nil
    NS.Modules:SetEnabled("movementalert", true)
    local db = MovementAlert.db
    db.readyAlert, db.readySound, db.readySpeak = true, true, true
    NS.Modules:Refresh("movementalert")   -- vide la liste de sorts en cache
    ready = true
    MovementAlert:Update()
    eq(played, "ping", "son joué")
    truthy(Mock.spoken and Mock.spoken[2]:find("Sprint"), "texte lu")
    eq(Mock.spoken[1], 3, "voix standard")
    NS.Modules:SetEnabled("movementalert", false)
    db.readyAlert, db.readySound, db.readySpeak = true, false, false
    MovementAlert.TrackedSpells, NS.IsSpellReady, NS.PlayPreset = tracked, isReady, play
    Set("C_VoiceChat", nil)
    eq(NS.SpeakText("x"), false, "sans API : rien")
    Restore()
end)

test("interface : /way et carte estompée en déplacement", function()
    reset()
    local Interface = NS.Modules:Get("interface")
    eq(Interface.CVAR_RULES.mapFade({ mapFadeMoving = false }), nil, "défaut : CVar intacte")
    eq(Interface.CVAR_RULES.mapFade({ mapFadeMoving = true }), "1")
    local point
    Set("UiMapPoint", { CreateFromCoordinates = function(mapID, x, y) return { mapID, x, y } end })
    C_Map.SetUserWaypoint = function(p) point = p end
    Mock.mapID = 1429
    eq(SlashCmdList.MUSCAUIWAY, nil, "option coupée : /way libre")
    Interface.db.slashWay = true
    NS.Modules:Refresh("interface")
    SlashCmdList.MUSCAUIWAY("45.2 61.8")
    eq(point[1], 1429); eq(point[2], 0.452); eq(point[3], 0.618)
    point = nil
    SlashCmdList.MUSCAUIWAY("abc")
    eq(point, nil, "saisie invalide : rien")
    Interface.db.slashWay = false
    SlashCmdList.MUSCAUIWAY, _G.SLASH_MUSCAUIWAY1 = nil, nil
    C_Map.SetUserWaypoint, Mock.mapID = nil, nil
    Restore()
end)

test("interface : point de route retiré à l'arrivée", function()
    reset()
    local Interface = NS.Modules:Get("interface")
    local waypoint = { uiMapID = 1429, position = { x = 0.5, y = 0.5 } }
    C_Map.GetUserWaypoint = function() return waypoint end
    C_Map.GetMapWorldSize = function() return 1000, 1000 end
    C_Map.ClearUserWaypoint = function() waypoint = nil end
    Mock.mapPosition = { 0.505, 0.5 }   -- 5 yards : posé sous les pieds
    Interface.db.wayArrival = true
    NS.Modules:Refresh("interface")
    Mock.Advance(1.5, 0.5)
    truthy(waypoint, "jamais quitté : point gardé")
    Mock.mapPosition = { 0.53, 0.5 }    -- 30 yards
    Mock.Advance(1.5, 0.5)
    truthy(waypoint, "loin : point gardé")
    eq(math.floor(NS.UserWaypointDistance() + 0.5), 30)
    Mock.mapPosition = { 0.505, 0.5 }   -- 5 yards
    Mock.Advance(1.5, 0.5)
    eq(waypoint, nil, "arrivé : point retiré")
    eq(NS.UserWaypointDistance(), nil, "sans point : nil")
    Interface.db.wayArrival = false
    NS.Modules:Refresh("interface")
    C_Map.GetUserWaypoint, C_Map.GetMapWorldSize, C_Map.ClearUserWaypoint, Mock.mapPosition = nil, nil, nil, nil
end)

test("jets de groupe : barre cachée après le délai", function()
    reset()
    local Loot = NS.Modules:Get("loot")
    NS.Modules:SetEnabled("loot", true)
    Loot.db.rolls, Loot.db.rollHideDelay = true, 5
    NS.Modules:Refresh("loot")
    Mock.rollItems[7] = { "icone", "Épée", 1, 4, false, true, true, false }
    Mock.rollTimeLeft = 60000
    Mock.FireEvent("START_LOOT_ROLL", 7, 60000)
    local _, _, bars = Loot:GetFrames()
    local bar
    for _, candidate in ipairs(bars) do if candidate.rollID == 7 then bar = candidate end end
    truthy(bar and bar:IsShown(), "barre affichée")
    Mock.Advance(4, 0.5)
    truthy(bar:IsShown(), "avant le délai : visible")
    Mock.Advance(2, 0.5)
    eq(bar:IsShown(), false, "après le délai : cachée")
    Loot.db.rollHideDelay = 0
    Mock.rollItems[7], Mock.rollTimeLeft = nil, nil
    NS.Modules:SetEnabled("loot", false)
end)

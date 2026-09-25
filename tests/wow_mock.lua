-- tests/wow_mock.lua
-- Mock minimal du client WoW Forever (moteur 12.x, contenu Classic), dérivé de celui de
-- KickAlert. Le temps est piloté à la main : Mock.Advance(dt) fait avancer GetTime,
-- les timers et les OnUpdate. Chaque état de jeu utile aux tests est une table Mock.*.

local Mock = {}
_G.Mock = Mock

Mock.now = 1000
Mock.groupHeaders = {}
Mock.printed = {}
Mock.frames = {}
Mock.sounds = {}

--------------------------------------------------------------------------------
-- Utilitaires
--------------------------------------------------------------------------------

function _G.print(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    local line = table.concat(parts, " ")
    Mock.printed[#Mock.printed + 1] = line
    if Mock.verbose then io.write(line, "\n") end
end

function _G.strjoin(sep, ...) return table.concat({ ... }, sep) end

function _G.tostringall(...)
    local n = select("#", ...)
    local out = {}
    for i = 1, n do out[i] = tostring((select(i, ...))) end
    return unpack(out, 1, n)
end

_G.tinsert = table.insert
_G.strmatch = string.match
_G.tremove = table.remove
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
_G.date = os.date
_G.debugstack = function() return debug.traceback() end

function _G.Mixin(object, ...)
    for i = 1, select("#", ...) do
        for k, v in pairs((select(i, ...))) do object[k] = v end
    end
    return object
end

function _G.GetTime() return Mock.now end
function _G.GetBuildInfo() return "1.60.1", "60000", "Sep 1 2026", 16001 end
function _G.GetLocale() return Mock.locale or "enUS" end
function _G.GetFramerate() return 60 end
function _G.GetNetStats() return 0, 0, 45, 50 end
function _G.GetGameTime() return 13, 37 end
function _G.GetBindLocation() return "Orgrimmar" end

_G.UISpecialFrames = {}
_G.SlashCmdList = {}
_G.DELETE_ITEM_CONFIRM_STRING = "DELETE"
_G.NUM_BAG_SLOTS = 4
_G.Enum = { ItemQuality = { Poor = 0, Common = 1 }, TooltipDataType = { Unit = 2 } }
_G.RAID_CLASS_COLORS = {
    MAGE = { r = 0.25, g = 0.78, b = 0.92 }, ROGUE = { r = 1, g = 0.96, b = 0.41 },
    PRIEST = { r = 1, g = 1, b = 1 }, WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
}

_G.LOCALIZED_CLASS_NAMES_MALE = { WARRIOR = "Guerrier", MAGE = "Mage" }
_G.LOCALIZED_CLASS_NAMES_FEMALE = { WARRIOR = "Guerrière", MAGE = "Mage" }

_G.SOUNDKIT = { RAID_WARNING = 8959, IG_MAINMENU_OPTION_CHECKBOX_ON = 856, READY_CHECK = 8960 }
function _G.PlaySound(id, channel)
    Mock.sounds[#Mock.sounds + 1] = { kit = id, channel = channel }
    return true
end
--- Fichier absent du dossier du jeu : le client renvoie willPlay = false.
Mock.soundFiles = { ["Interface\\AddOns\\MesSons\\alerte.ogg"] = true, [569593] = true }
function _G.PlaySoundFile(file, channel)
    if not Mock.soundFiles[file] then return false end
    Mock.sounds[#Mock.sounds + 1] = { file = file, channel = channel }
    return true
end

--- Valeurs « secrètes » du moteur 12.x : toute valeur présente dans cet ensemble l'est.
Mock.secret = {}
function _G.issecretvalue(value) return value ~= nil and Mock.secret[value] == true end

--- Vrai hooksecurefunc : appelle l'original puis le hook, comme le client.
function _G.hooksecurefunc(a, b, c)
    local tbl, name, hook = _G, a, b
    if type(a) == "table" then tbl, name, hook = a, b, c end
    local original = tbl[name]
    tbl[name] = function(...)
        local r = { original(...) }
        hook(...)
        return unpack(r)
    end
end

--------------------------------------------------------------------------------
-- Combat et joueur
--------------------------------------------------------------------------------

Mock.combat = false
function _G.InCombatLockdown() return Mock.combat end

--- Entrée/sortie de combat avec les events correspondants.
function Mock.SetCombat(inCombat)
    Mock.combat = inCombat
    Mock.units.player.combat = inCombat
    Mock.FireEvent(inCombat and "PLAYER_REGEN_DISABLED" or "PLAYER_REGEN_ENABLED")
end

Mock.units = {
    player = { guid = "Player-1", name = "Testeur", class = "MAGE", isPlayer = true },
}

function _G.UnitExists(unit) return Mock.units[unit] ~= nil end
function _G.UnitGUID(unit) local u = Mock.units[unit] return u and u.guid end
function _G.UnitName(unit) local u = Mock.units[unit] return u and u.name end
function _G.UnitClass(unit)
    local u = Mock.units[unit]
    return u and u.class, u and u.class
end
function _G.UnitIsPlayer(unit) local u = Mock.units[unit] return u ~= nil and u.isPlayer == true end
function _G.UnitIsUnit(a, b) return Mock.units[a] ~= nil and Mock.units[a] == Mock.units[b] end
function _G.UnitIsDead(unit) local u = Mock.units[unit] return u ~= nil and u.dead == true end
function _G.UnitIsDeadOrGhost(unit) return UnitIsDead(unit) end
function _G.UnitAffectingCombat(unit) local u = Mock.units[unit] return u ~= nil and u.combat == true end
function _G.UnitOnTaxi() return false end
function _G.IsResting() return Mock.resting == true end
function _G.IsMounted() return false end
function _G.IsStealthed() return Mock.stealthed == true end
function _G.IsAltKeyDown() return Mock.altDown == true end
function _G.GetShapeshiftFormID() return Mock.formID end

Mock.groupSize = 0
function _G.IsInGroup() return Mock.groupSize > 0 end
function _G.GetNumGroupMembers() return Mock.groupSize end

Mock.instanceType = "none"
function _G.IsInInstance() return Mock.instanceType ~= "none", Mock.instanceType end

--------------------------------------------------------------------------------
-- Sorts et auras
--------------------------------------------------------------------------------

Mock.spells = {
    [168] = "Frost Armor", [7302] = "Ice Armor", [6117] = "Mage Armor",
    [588] = "Inner Fire", [1784] = "Stealth", [8679] = "Instant Poison", [2823] = "Deadly Poison", [2842] = "Poisons",
    [6673] = "Battle Shout", [1126] = "Mark of the Wild", [21849] = "Gift of the Wild",
}
Mock.knownSpells = {}      -- [id] = true

local function SpellId(identifier)
    if type(identifier) == "number" then return identifier end
    for id, name in pairs(Mock.spells) do
        if name == identifier then return id end
    end
end

_G.C_Spell = {
    GetSpellInfo = function(identifier)
        local id = SpellId(identifier)
        if not id or not Mock.spells[id] then return nil end
        -- Par nom, le client ne répond que pour un sort du grimoire.
        if type(identifier) == "string" and not Mock.knownSpells[id] then return nil end
        return { name = Mock.spells[id], spellID = id, iconID = 1 }
    end,
}
function _G.IsPlayerSpell(id) return Mock.knownSpells[id] == true end

Mock.buffs = {}            -- liste de noms de buffs du joueur
_G.C_UnitAuras = {
    GetAuraDataByIndex = function(unit, index)
        if unit ~= "player" then return nil end
        local name = Mock.buffs[index]
        if not name then return nil end
        return { name = name, spellId = SpellId(name), icon = 1 }
    end,
}

Mock.mainHandEnchant = false
function _G.GetWeaponEnchantInfo() return Mock.mainHandEnchant end

--------------------------------------------------------------------------------
-- Sacs, objets, marchand
--------------------------------------------------------------------------------

-- Mock.bags[bag][slot] = { itemID, quality, stackCount, hasNoValue, isLocked }
Mock.bags = { [0] = {}, {}, {}, {}, {} }
Mock.bagSize = 16
Mock.items = {}            -- [itemID] = { sellPrice = }
Mock.used = {}             -- cases utilisées : { bag, slot }

_G.C_Container = {
    GetContainerNumSlots = function() return Mock.bagSize end,
    GetContainerNumFreeSlots = function(bag)
        local used = 0
        for _ in pairs(Mock.bags[bag] or {}) do used = used + 1 end
        return Mock.bagSize - used
    end,
    GetContainerItemInfo = function(bag, slot)
        local item = Mock.bags[bag] and Mock.bags[bag][slot]
        if not item then return nil end
        return { itemID = item.itemID, quality = item.quality, stackCount = item.stackCount or 1,
                 hasNoValue = item.hasNoValue, isLocked = item.isLocked, hyperlink = item.itemID }
    end,
    UseContainerItem = function(bag, slot)
        Mock.used[#Mock.used + 1] = { bag = bag, slot = slot }
        if Mock.merchantOpen then Mock.bags[bag][slot] = nil end
    end,
    GetItemCooldown = function() return 0, 0, 1 end,
    GetContainerItemCooldown = function() return 0, 0, 1 end,
    SortBags = function() Mock.sorted = (Mock.sorted or 0) + 1 end,
}
-- Fenêtres de sacs Blizzard : ContainerFrame1 (sac à dos) et ContainerFrame2.
Mock.containerFrames = {}

_G.C_Item = {
    GetItemInfo = function(item)
        local info = Mock.items[item]
        if not info then return nil end
        return "item" .. item, nil, 0, 1, 1, "Junk", "Junk", 20, "", 1, info.sellPrice
    end,
    GetItemCount = function(itemID) return itemID == 6948 and 1 or 0 end,
    -- Mock.items[itemID].equipLoc
    GetItemInfoInstant = function(item)
        local info = Mock.items[item]
        return item, nil, nil, info and info.equipLoc or ""
    end,
}

Mock.money = 100000
Mock.repairCost = 0
Mock.canGuildRepair = false
Mock.guildWithdraw = 0
Mock.repairs = {}
Mock.merchantOpen = false
function _G.GetMoney() return Mock.money end
function _G.CanMerchantRepair() return Mock.merchantOpen end
function _G.GetRepairAllCost() return Mock.repairCost, Mock.repairCost > 0 end
function _G.CanGuildBankRepair() return Mock.canGuildRepair end
function _G.GetGuildBankWithdrawMoney() return Mock.guildWithdraw end
Mock.guildBankEmpty = false   -- banque autorisée mais vide : la réparation guilde ne fait rien
function _G.RepairAllItems(guild)
    Mock.repairs[#Mock.repairs + 1] = guild and "guild" or "self"
    if not (guild and Mock.guildBankEmpty) then Mock.repairCost = 0 end
end

Mock.durability = {}       -- [slot] = { cur, max }
function _G.GetInventoryItemDurability(slot)
    local d = Mock.durability[slot]
    if not d then return nil end
    return d[1], d[2]
end

--------------------------------------------------------------------------------
-- Social
--------------------------------------------------------------------------------

Mock.friends = {}          -- [guid] = name
Mock.guildies = {}         -- [guid] = true
Mock.inGuild = false
Mock.acceptedGroup = 0

_G.C_FriendList = {
    GetNumOnlineFriends = function()
        local n = 0
        for _ in pairs(Mock.friends) do n = n + 1 end
        return n
    end,
    GetNumFriends = function() return 0 end,
    IsFriend = function(guid) return Mock.friends[guid] ~= nil end,
    GetFriendInfo = function() return nil end,
}
function _G.BNGetNumFriends() return 0, 2 end
function _G.IsGuildMember(guid) return Mock.guildies[guid] == true end
function _G.IsInGuild() return Mock.inGuild end
function _G.GetNumGuildMembers() return 50, 12 end
function _G.AcceptGroup() Mock.acceptedGroup = Mock.acceptedGroup + 1 end
_G.C_GuildInfo = { GuildRoster = function() end }

--------------------------------------------------------------------------------
-- Frames
--------------------------------------------------------------------------------

local FrameMeta = {}
FrameMeta.__index = FrameMeta
Mock.FrameMeta = FrameMeta

local function NoOp() end
for _, name in ipairs({
    "SetMovable", "EnableMouse", "EnableMouseWheel", "SetClampedToScreen", "RegisterForDrag",
    "StartMoving", "StopMovingOrSizing", "SetFrameStrata", "SetFrameLevel",
    "SetJustifyH", "SetAlpha", "RegisterForClicks", "SetFontObject",
    "SetScrollChild", "SetVerticalScroll", "SetMinMaxValues", "SetValueStep",
    "SetObeyStepOnDrag", "SetAutoFocus", "ClearFocus", "SetVertexColor", "ClearLines", "AddLine",
    "AddDoubleLine", "SetOwner", "SetMultiLine", "HighlightText", "SetClampRectInsets", "SetFocus",
    "SetNormalTexture",
}) do
    FrameMeta[name] = NoOp
end
function FrameMeta:SetTexture(texture) self.texture = texture end

function FrameMeta:SetText(text) self.text = text end
function FrameMeta:SetFormattedText(format, ...) self.text = string.format(format, ...) end
function FrameMeta:GetText() return self.text end
function FrameMeta:SetFont(path, size, flags) self.font, self.fontSize, self.fontFlags = path, size, flags end
function FrameMeta:GetFont() return self.font, self.fontSize, self.fontFlags end
function FrameMeta:GetStringWidth() return #(self.text or "") * 6 end
function FrameMeta:GetStringHeight() return 12 end
function FrameMeta:SetTextColor(r, g, b) self.textColor = { r, g, b } end
function FrameMeta:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
function FrameMeta:GetName() return self.frameName end
function FrameMeta:SetSize(w, h) self.width, self.height = w, h end
function FrameMeta:SetWidth(w) self.width = w end
function FrameMeta:SetHeight(h) self.height = h end
function FrameMeta:GetWidth() return self.width or 0 end
function FrameMeta:GetHeight() return self.height or 0 end
function FrameMeta:SetParent(parent) self.parent = parent end
function FrameMeta:GetFrameLevel() return self.frameLevel or 1 end
function FrameMeta:SetClipsChildren(clips) self.clipsChildren = clips end
function FrameMeta:GetStatusBarTexture()
    self.statusBarTexture = self.statusBarTexture or setmetatable({ shown = true }, { __index = FrameMeta })
    return self.statusBarTexture
end
-- Mock.missingAtlas[nom] = true : atlas absent du client, SetAtlas rend false.
Mock.missingAtlas = {}
function FrameMeta:SetAtlas(atlas)
    if Mock.missingAtlas[atlas] then return false end
    self.atlas, self.texture = atlas, nil
    return true
end
function FrameMeta:GetParent() return self.parent end
function FrameMeta:Show() self.shown = true; if self.scripts.OnShow then self.scripts.OnShow(self) end end
function FrameMeta:Hide()
    local was = self.shown
    self.shown = false
    if was and self.scripts.OnHide then self.scripts.OnHide(self) end
end
function FrameMeta:SetShown(shown) if shown then self:Show() else self:Hide() end end
function FrameMeta:IsShown() return self.shown == true end
function FrameMeta:IsVisible()
    if not self.shown then return false end
    local parent = self.parent
    while parent do
        if parent.shown == false then return false end
        parent = parent.parent
    end
    return true
end
function FrameMeta:SetChecked(v) self.checked = v end
function FrameMeta:GetChecked() return self.checked end
function FrameMeta:SetValue(v)
    self.value = v
    if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, v) end
end
function FrameMeta:GetVerticalScroll() return 0 end
function geterrorhandler() return error end
function FrameMeta:GetVerticalScrollRange() return 0 end
function FrameMeta:SetAttribute(k, v)
    if Mock.combat and self.secure then error("ADDON_ACTION_BLOCKED: SetAttribute en combat") end
    self.attributes[k] = v
    if self.scripts.OnAttributeChanged then self.scripts.OnAttributeChanged(self, k, v) end
end
function FrameMeta:GetAttribute(k) return self.attributes[k] end

function FrameMeta:SetPoint(point, relTo, relPoint, x, y)
    if type(relTo) == "string" then relTo = _G[relTo] end
    self.points = self.points or {}
    self.points[#self.points + 1] = { point, relTo, relPoint, x, y }
end
function FrameMeta:SetAllPoints(relTo) self.points = { { "ALL", relTo or self.parent } } end
function FrameMeta:GetPoint()
    local p = self.points and self.points[1]
    if not p then return nil end
    return p[1], p[2], p[3], p[4], p[5]
end
function FrameMeta:ClearAllPoints() self.points = nil end
function FrameMeta:GetNumPoints() return self.points and #self.points or 0 end

function FrameMeta:SetScript(script, fn) self.scripts[script] = fn end
function FrameMeta:GetScript(script) return self.scripts[script] end
function FrameMeta:HookScript(script, fn)
    local previous = self.scripts[script]
    self.scripts[script] = function(...)
        if previous then previous(...) end
        fn(...)
    end
end

function FrameMeta:RegisterEvent(event)
    if Mock.unknownEvents[event] then error("Attempted to register unknown event '" .. event .. "'") end
    self.events[event] = true
end
function FrameMeta:RegisterUnitEvent(event) self:RegisterEvent(event) end
function FrameMeta:UnregisterEvent(event) self.events[event] = nil end
function FrameMeta:UnregisterAllEvents() self.events = {} end
function FrameMeta:IsEventRegistered(event) return self.events[event] == true end

local function NewObject(parent)
    return setmetatable({ scripts = {}, events = {}, attributes = {}, shown = true, parent = parent }, FrameMeta)
end
function FrameMeta:CreateTexture() return NewObject(self) end
function FrameMeta:CreateFontString() return NewObject(self) end

Mock.unknownEvents = { COMBAT_LOG_EVENT_UNFILTERED = true }

function _G.CreateFrame(frameType, name, parent, template)
    if frameType == "AuraContainer" then
        if not Mock.auraContainer then error("Unknown frame type 'AuraContainer'") end
        local container = NewObject(parent)
        container.frameType, container.calls, container.groups = frameType, {}, {}
        for _, method in ipairs({ "SetFlowLayoutAnchorPoint", "SetFlowLayoutGrowthDirection",
                                  "SetFlowLayoutMaximumLineSize", "SetAuraGroupLayout", "UpdateAllAuras" }) do
            container[method] = function(self, ...) self.calls[#self.calls + 1] = method end
        end
        container.SetUnit = function(self, unit) self.unit = unit end
        container.AddAuraGroup = function(self, key, filter, options)
            self.groups[#self.groups + 1] = { key = key, filter = filter, options = options }
            if options and options.initializeFrame then options.initializeFrame(NewObject(self)) end
        end
        Mock.frames[#Mock.frames + 1] = container
        return container
    end
    local frame = NewObject(parent)
    frame.frameType, frame.frameName, frame.template = frameType, name, template
    frame.secure = template ~= nil and template:find("Secure") ~= nil
    if template == "SecureGroupHeaderTemplate" then
        frame.children = {}
        Mock.groupHeaders[#Mock.groupHeaders + 1] = frame
    end
    if name then _G[name] = frame end
    -- Les modèles Blizzard créent des sous-objets nommés : on reproduit ceux que l'addon lit.
    if name and template and template:find("CheckButton") then _G[name .. "Text"] = NewObject(frame) end
    if name and template == "OptionsSliderTemplate" then
        _G[name .. "Text"], _G[name .. "Low"], _G[name .. "High"] = NewObject(frame), NewObject(frame), NewObject(frame)
    end
    if Mock.combat and frame.secure then error("ADDON_ACTION_BLOCKED: frame sécurisée créée en combat") end
    if template == "ActionBarButtonTemplate" then Mock.SetupActionButton(frame) end
    Mock.frames[#Mock.frames + 1] = frame
    return frame
end

-- Bouton d'action Blizzard (mixin minimal) : OnLoad l'inscrit dans les diffuseurs, OnEvent met à jour.
function Mock.SetupActionButton(button)
    button.HotKey, button.Name = NewObject(button), NewObject(button)
    button.cooldown = NewObject(button)
    button.cooldown.SetCooldown = function(self, start, duration)
        if issecretvalue(start) or issecretvalue(duration) then error("Secret values are only allowed during untainted execution") end
        self.painted = { start, duration }
    end
    button.cooldown.SetCooldownFromDurationObject = function(self, object) self.painted = object end
    button.cooldown.Clear = function(self) self.painted = nil end
    -- Comme le client : fonction globale, pas une méthode redéfinissable.
    button.OnEvent = function(self, event)
        self.lastEvent = event
        self.action = (self:GetAttribute("actionpage") - 1) * 12 + self:GetID()
        local start, duration = GetActionCooldown(self.action)
        self.cooldown:SetCooldown(start, duration)
    end
    tinsert(ActionBarButtonEventsFrame.frames, button)
    tinsert(ActionBarActionEventsFrame.frames, button)
end
local function NewDispatcher(name)
    local frame = CreateFrame("Frame", name, UIParent)
    frame.frames = {}
    function frame:RegisterFrame(button) tinsert(self.frames, button) end
    function frame:UnregisterFrame(button)
        for i = #self.frames, 1, -1 do if self.frames[i] == button then tremove(self.frames, i) end end
    end
    return frame
end
NewDispatcher("ActionBarButtonEventsFrame")
NewDispatcher("ActionBarActionEventsFrame")
Mock.actionCooldown = { start = 0, duration = 0 }
function _G.GetActionCooldown() return Mock.actionCooldown.start, Mock.actionCooldown.duration, 1, 1 end

-- Échelle, rectangle écran, clavier, protection (socle : Pixel et Movers)
function FrameMeta:SetScale(scale) self.scale = scale end
function FrameMeta:GetScale() return self.scale or 1 end
function FrameMeta:GetEffectiveScale()
    local scale = self:GetScale()
    if self.parent and self.parent.GetEffectiveScale then scale = scale * self.parent:GetEffectiveScale() end
    return scale
end
function FrameMeta:IsProtected() return self.secure == true end
function FrameMeta:SetShadowOffset(x, y) self.shadowOffset = { x, y } end
function FrameMeta:EnableKeyboard(enabled) self.keyboard = enabled end
function FrameMeta:SetPropagateKeyboardInput(propagate) self.propagateKeyboard = propagate end
-- Rectangle : Mock.SetRect(frame, left, bottom, width, height) simule la position rendue.
function Mock.SetRect(frame, left, bottom, width, height)
    frame.rect = { left = left, bottom = bottom }
    frame.width, frame.height = width, height
end
function FrameMeta:GetLeft() return self.rect and self.rect.left end
function FrameMeta:GetBottom() return self.rect and self.rect.bottom end
function FrameMeta:GetRight() return self.rect and self.rect.left + (self.width or 0) end
function FrameMeta:GetTop() return self.rect and self.rect.bottom + (self.height or 0) end
function FrameMeta:GetCenter()
    if not self.rect then return nil end
    return self.rect.left + (self.width or 0) / 2, self.rect.bottom + (self.height or 0) / 2
end

Mock.screen = { width = 1920, height = 1080 }
function _G.GetPhysicalScreenSize() return Mock.screen.width, Mock.screen.height end
Mock.loadedAddons = {}

_G.UIParent = CreateFrame("Frame", "UIParent")
for i = 1, 2 do CreateFrame("Frame", "ContainerFrame" .. i, UIParent):Hide() end
function _G.OpenAllBags() ContainerFrame1:Show() ContainerFrame2:Show() end
function _G.CloseAllBags() ContainerFrame1:Hide() ContainerFrame2:Hide() end
_G.LootFrame = CreateFrame("Frame", "LootFrame", UIParent)
for _, event in ipairs({ "LOOT_OPENED", "LOOT_SLOT_CLEARED", "LOOT_CLOSED" }) do LootFrame:RegisterEvent(event) end
UIParent:RegisterEvent("START_LOOT_ROLL")
Mock.SetRect(UIParent, 0, 0, 1920, 1080)
CreateFrame("Frame", "MicroMenuContainer", UIParent):SetSize(300, 40)
CreateFrame("Frame", "BagsBar", UIParent):SetSize(200, 40)
CreateFrame("Frame", "StanceBar", UIParent):SetSize(120, 30)
for _, name in ipairs({ "EssentialCooldownViewer", "UtilityCooldownViewer", "BuffIconCooldownViewer", "BuffBarCooldownViewer", "DebuffFrame" }) do CreateFrame("Frame", name, UIParent):SetSize(200, 40) end
CreateFrame("Frame", "PetActionBar", UIParent):SetSize(300, 30)
_G.MinimapCluster = CreateFrame("Frame", "MinimapCluster", UIParent)
MinimapCluster:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", 0, 0)
MinimapCluster.MinimapContainer = CreateFrame("Frame", nil, MinimapCluster)
_G.Minimap = CreateFrame("Minimap", "Minimap", MinimapCluster.MinimapContainer)
Minimap.zoom, Minimap.scripts = 0, Minimap.scripts or {}
function Minimap:GetZoom() return self.zoom end
function Minimap:SetZoom(z) self.zoom = z end
function Minimap:GetZoomLevels() return 6 end
function Minimap:SetMaskTexture(mask) self.mask = mask end
MinimapCluster.BorderTop = Minimap:CreateTexture()
MinimapCluster.ZoneTextButton = CreateFrame("Button", nil, MinimapCluster)
MinimapCluster.Tracking = CreateFrame("Button", nil, MinimapCluster)
_G.MinimapCompassTexture = Minimap:CreateTexture()
_G.GameTimeFrame = CreateFrame("Button", "GameTimeFrame", MinimapCluster)
function _G.GetMinimapZoneText() return Mock.zoneText or "Durotar" end
function _G.GetZonePVPInfo() return Mock.pvpType end
_G.C_Map = {
    GetBestMapForUnit = function() return Mock.mapID end,
    GetPlayerMapPosition = function() return Mock.mapPosition and { GetXY = function() return Mock.mapPosition[1], Mock.mapPosition[2] end } end,
}

--------------------------------------------------------------------------------
-- Infobulles, popups, nameplates, options
--------------------------------------------------------------------------------

local function NewTooltip(name)
    local tooltip = CreateFrame("GameTooltip", name, UIParent)
    tooltip.NineSlice = {
        SetCenterColor = function(_, r, g, b, a) tooltip.center = { r, g, b, a } end,
        SetBorderColor = function(_, r, g, b, a) tooltip.border = { r, g, b, a } end,
    }
    _G[name .. "TextLeft1"] = NewObject(tooltip)
    return tooltip
end
-- Forever : plus de tooltip:GetUnit(), seulement TooltipUtil.
_G.TooltipUtil = {
    GetDisplayedUnit = function() return Mock.tooltipUnit and "Name", Mock.tooltipUnit end,
}
NewTooltip("GameTooltip")
NewTooltip("ItemRefTooltip")

_G.GAME_TOOLTIP_BACKDROP_STYLE_DEFAULT = { name = "default" }
function _G.SharedTooltip_SetBackdropStyle(tooltip)
    tooltip.center = { 0, 0, 0, 0.8 }
    tooltip.border = { 1, 1, 1, 1 }
end

Mock.tooltipCallbacks = {}
_G.TooltipDataProcessor = {
    AddTooltipPostCall = function(kind, fn) Mock.tooltipCallbacks[#Mock.tooltipCallbacks + 1] = fn end,
}
function Mock.ShowUnitTooltip(unit)
    Mock.tooltipUnit = unit
    GameTooltip:Show()
    for _, fn in ipairs(Mock.tooltipCallbacks) do fn(GameTooltip) end
end

-- Popups : Mock.popups[which] = frame visible. Mock.acceptPopups : OnAccept joué aussitôt.
Mock.popups = {}
_G.StaticPopupDialogs = {}
_G.YES, _G.NO = "Yes", "No"
function _G.StaticPopup_Show(which, _, _, data)
    local dialog = StaticPopupDialogs[which]
    if Mock.acceptPopups and dialog and dialog.OnAccept then
        dialog.OnAccept(nil, data)
        return nil
    end
    local popup = CreateFrame("Frame", nil, UIParent)
    popup.data = data
    popup.button1 = CreateFrame("Button", nil, popup)
    popup.editBox = CreateFrame("EditBox", nil, popup)
    Mock.popups[which] = popup
    return popup
end
function _G.StaticPopup_Hide(which) Mock.popups[which] = nil end
function _G.StaticPopup_Visible(which)
    local popup = Mock.popups[which]
    if popup then return true, popup end
    return nil
end

Mock.namePlates = {}
_G.C_NamePlate = {
    GetNamePlateForUnit = function(unit)
        for token, plate in pairs(Mock.namePlates) do
            if UnitIsUnit(token, unit) then return plate end
        end
    end,
    GetNamePlates = function()
        local list = {}
        for _, plate in pairs(Mock.namePlates) do list[#list + 1] = plate end
        return list
    end,
}

--- Plaque de nom pour une unité déjà décrite dans Mock.units[unit] : événement ADDED compris.
function Mock.AddNamePlate(unit)
    local plate = CreateFrame("Frame", nil, UIParent)
    plate.secure = true
    plate.namePlateUnitToken = unit
    plate.UnitFrame = CreateFrame("Frame", nil, plate)
    plate.UnitFrame.alpha = 1
    Mock.namePlates[unit] = plate
    Mock.FireEvent("NAME_PLATE_UNIT_ADDED", unit)
    return plate
end
function Mock.RemoveNamePlate(unit)
    Mock.FireEvent("NAME_PLATE_UNIT_REMOVED", unit)
    Mock.namePlates[unit] = nil
end
function _G.UnitThreatSituation(unitA, unitB) local u = Mock.units[unitB or unitA] return u and u.threat or nil end
function _G.UnitInRange(unit)
    local u = Mock.units[unit]
    if not u then return false, false end
    return u.inRange ~= false, true
end

-- SecureGroupHeaderTemplate : l'en-tête peuple ses boutons d'après ses attributs à chaque
-- GROUP_ROSTER_UPDATE (le client le fait aussi à l'affichage). Mock.SetGroup(n, isRaid) prépare
-- les unités et déclenche l'événement.
function Mock.UpdateGroupHeaders()
    for _, header in ipairs(Mock.groupHeaders) do
        local units = {}
        local get = function(k) return header:GetAttribute(k) end
        if get("showRaid") and Mock.inRaid then
            local filter = get("groupFilter")   -- MAINTANK, MAINASSIST : Mock.units[u].assignment
            for i = 1, Mock.groupSize do
                local u = Mock.units["raid" .. i]
                if not filter or (u and u.assignment == filter) then units[#units + 1] = "raid" .. i end
            end
        elseif get("showParty") and Mock.groupSize > 0 and not Mock.inRaid then
            if get("showPlayer") then units[#units + 1] = "player" end
            for i = 1, Mock.groupSize - 1 do units[#units + 1] = "party" .. i end
        elseif get("showSolo") and Mock.groupSize == 0 then
            units[1] = "player"
        end
        header.children = header.children or {}
        for i, unit in ipairs(units) do
            local child = header.children[i]
            if not child then
                child = CreateFrame("Button", header:GetName() .. "UnitButton" .. i, header, get("template"))
                header.children[i] = child
                child:SetSize(get("initial-width") or 0, get("initial-height") or 0)
            end
            child:SetAttribute("unit", unit)
            child:Show()
        end
        for i = #units + 1, #header.children do
            header.children[i]:SetAttribute("unit", nil)
            header.children[i]:Hide()
        end
        SecureGroupHeader_Update(header)   -- le client l'appelle à chaque mise à jour ; l'addon s'y accroche
    end
end
-- Sans snippet restreint (pas de loadstring sur ce moteur) : l'addon s'accroche à cette fonction.
function _G.SecureGroupHeader_Update(header) end
function Mock.SetGroup(size, isRaid)
    Mock.groupSize, Mock.inRaid = size, isRaid == true
    if isRaid then
        for i = 1, size do
            Mock.units["raid" .. i] = Mock.units["raid" .. i] or { name = "Raid" .. i, class = "WARRIOR", isPlayer = true, health = 900, healthMax = 1000, power = 50, powerMax = 100 }
        end
    else
        for i = 1, size - 1 do
            Mock.units["party" .. i] = Mock.units["party" .. i] or { name = "Ami" .. i, class = "PRIEST", isPlayer = true, health = 800, healthMax = 1000, power = 30, powerMax = 100 }
        end
    end
    Mock.FireEvent("GROUP_ROSTER_UPDATE")
end

_G.Settings = {
    RegisterCanvasLayoutCategory = function(panel, name)
        return { GetID = function() return name end }
    end,
    RegisterAddOnCategory = function() end,
    OpenToCategory = function(id) Mock.openedOptions = id end,
}

--------------------------------------------------------------------------------
-- Events et temps
--------------------------------------------------------------------------------

function Mock.FireEvent(event, ...)
    for i = 1, #Mock.frames do
        local frame = Mock.frames[i]
        if frame.events[event] and frame.scripts.OnEvent then
            frame.scripts.OnEvent(frame, event, ...)
        end
    end
end

Mock.timers = {}
local TimerMeta = {}
TimerMeta.__index = TimerMeta
function TimerMeta:Cancel() self.cancelled = true end

local function NewTimer(delay, callback, interval)
    local timer = setmetatable({ at = Mock.now + delay, callback = callback, interval = interval }, TimerMeta)
    Mock.timers[#Mock.timers + 1] = timer
    return timer
end

-- Messages d'addon : Mock.addonMessages = { { prefix, text, channel } }. Mock.addonThrottle : nombre
-- d'envois refusés par la limite de débit avant d'accepter.
Mock.addonMessages = {}
Mock.addonThrottle = 0
_G.C_ChatInfo = {
    RegisterAddonMessagePrefix = function(prefix) Mock.addonPrefix = prefix return true end,
    SendAddonMessage = function(prefix, text, channel)
        if Mock.addonThrottle > 0 then Mock.addonThrottle = Mock.addonThrottle - 1 return 3 end
        Mock.addonMessages[#Mock.addonMessages + 1] = { prefix, text, channel }
        return 0
    end,
}
function _G.Ambiguate(name) return (name:gsub("%-.*", "")) end
Mock.groupMembers = {}
function _G.UnitInParty(name) return Mock.groupMembers[name] == true end
function _G.UnitInRaid(name) return nil end

_G.C_Timer = {
    NewTimer = function(delay, cb) return NewTimer(delay, cb) end,
    NewTicker = function(interval, cb) return NewTimer(interval, cb, interval) end,
    After = function(delay, cb) NewTimer(delay, cb) end,
}

function Mock.Advance(seconds, step)
    step = step or 0.05
    local remaining = seconds
    while remaining > 1e-9 do
        local delta = math.min(step, remaining)
        Mock.now = Mock.now + delta
        remaining = remaining - delta
        for i = 1, #Mock.frames do
            local frame = Mock.frames[i]
            if frame.shown and frame.scripts.OnUpdate then frame.scripts.OnUpdate(frame, delta) end
        end
        for i = #Mock.timers, 1, -1 do
            local timer = Mock.timers[i]
            if timer.cancelled then
                table.remove(Mock.timers, i)
            elseif timer.at <= Mock.now + 1e-9 then
                if timer.interval then
                    timer.at = timer.at + timer.interval
                else
                    table.remove(Mock.timers, i)
                end
                timer.callback()
            end
        end
    end
end

function Mock.FindPrinted(pattern)
    for i = 1, #Mock.printed do
        if Mock.printed[i]:find(pattern, 1, true) then return Mock.printed[i] end
    end
end


--------------------------------------------------------------------------------
-- Compléments v2 : état de jeu supplémentaire
--------------------------------------------------------------------------------

function _G.GetRealmName() return "Forever" end
Mock.shift = false
function _G.IsShiftKeyDown() return Mock.shift == true end
function _G.IsInRaid() return Mock.inRaid == true end
Mock.roles = {}                 -- [unit] = "TANK" | ...
function _G.UnitGroupRolesAssigned(unit) return Mock.roles[unit] or "NONE" end
function _G.GetPartyAssignment() return false end
function _G.UnitHealth(unit) local u = Mock.units[unit] return u and u.health or 0 end
function _G.UnitHealthMax(unit) local u = Mock.units[unit] return u and u.healthMax or 0 end
function _G.UnitCanAttack(_, unit) local u = Mock.units[unit] return u ~= nil and u.hostile == true end
function _G.UnitCastingInfo(unit) local u = Mock.units[unit] return u and u.casting or nil end
function _G.UnitChannelInfo() return nil end
Mock.shapeshiftForm = 0
function _G.GetShapeshiftForm() return Mock.shapeshiftForm end

-- State drivers : on retient le dernier enregistré par frame.
Mock.stateDrivers = {}
function _G.RegisterStateDriver(frame, state, value)
    if Mock.combat then error("ADDON_ACTION_BLOCKED: RegisterStateDriver en combat") end
    Mock.stateDrivers[frame] = Mock.stateDrivers[frame] or {}
    Mock.stateDrivers[frame][state] = value
end
Mock.attributeDrivers = {}
function _G.RegisterAttributeDriver(frame, attribute, value)
    if Mock.combat then error("ADDON_ACTION_BLOCKED: RegisterAttributeDriver en combat") end
    Mock.attributeDrivers[frame] = Mock.attributeDrivers[frame] or {}
    Mock.attributeDrivers[frame][attribute] = value
end
function _G.UnregisterAttributeDriver(frame, attribute)
    if Mock.attributeDrivers[frame] then Mock.attributeDrivers[frame][attribute] = nil end
end
function _G.UnregisterStateDriver(frame, state)
    if Mock.stateDrivers[frame] then Mock.stateDrivers[frame][state] = nil end
end

-- Sauvegarde de Blizzard_AddOnList (table hôte des doubles de réglages, Database.lua)
_G.g_addonCategoriesCollapsed = {}

-- CVars
Mock.cvars = {
    showTutorials = "1", spellActivationOverlayOpacity = "0.65", displaySpellActivationOverlays = "1",
    alwaysShowActionBars = "0", scriptErrors = "1", autoLootDefault = "0", showTimestamps = "none",
}
_G.C_CVar = {
    RegisterCVar = function(name, default)
        if Mock.cvars[name] == nil then Mock.cvars[name] = tostring(default) end
    end,
    GetCVar = function(name) return Mock.cvars[name] end,
    SetCVar = function(name, value)
        if Mock.cvars[name] == nil then return false end
        Mock.cvars[name] = tostring(value)
        return true
    end,
}

-- Butin
Mock.lootCount = 0
Mock.looted = {}
function _G.GetNumLootItems() return Mock.lootCount end
function _G.LootSlot(slot) Mock.looted[#Mock.looted + 1] = slot end
Mock.lootSlots = {}        -- [slot] = { texture, name, quantity, quality, isQuestItem }
Mock.closedLoot = 0
function _G.GetLootSlotInfo(slot)
    local item = Mock.lootSlots[slot]
    if not item then return nil end
    return item[1], item[2], item[3], nil, item[4], false, item[5]
end
function _G.CloseLoot() Mock.closedLoot = Mock.closedLoot + 1 end
Mock.rollItems = {}        -- [rollID] = { texture, name, count, quality, bop, canNeed, canGreed, canDisenchant }
Mock.rolls = {}            -- { { rollID, rollType } }
Mock.rollTimeLeft = 30000
function _G.GetLootRollItemInfo(rollID)
    local item = Mock.rollItems[rollID]
    if not item then return nil end
    return unpack(item, 1, 8)
end
function _G.RollOnLoot(rollID, rollType) Mock.rolls[#Mock.rolls + 1] = { rollID, rollType } end
function _G.GetLootRollTimeLeft() return Mock.rollTimeLeft end
Mock.chatFilters = {}      -- [event] = { filtre, ... }
function _G.ChatFrame_AddMessageEventFilter(event, filter)
    Mock.chatFilters[event] = Mock.chatFilters[event] or {}
    table.insert(Mock.chatFilters[event], filter)
end

-- Quêtes
Mock.questLog = {}
local function QuestLog(action) Mock.questLog[#Mock.questLog + 1] = action end
function _G.AcceptQuest() QuestLog("accept") end
function _G.ConfirmAcceptQuest() QuestLog("confirm") end
function _G.IsQuestCompletable() return Mock.questCompletable == true end
function _G.CompleteQuest() QuestLog("complete") end
Mock.questChoices = 0
function _G.GetNumQuestChoices() return Mock.questChoices end
function _G.GetQuestReward(choice) QuestLog("reward:" .. tostring(choice)) end
Mock.gossip = { active = {}, available = {} }
_G.C_GossipInfo = {
    GetActiveQuests = function() return Mock.gossip.active end,
    GetAvailableQuests = function() return Mock.gossip.available end,
    SelectActiveQuest = function(id) QuestLog("gossip-turnin:" .. id) end,
    SelectAvailableQuest = function(id) QuestLog("gossip-accept:" .. id) end,
}

-- Chat
Mock.chat = {}
function _G.SendChatMessage(message, channel) Mock.chat[#Mock.chat + 1] = { message = message, channel = channel } end
_G.INSTANCE_RESET_SUCCESS = "%s has been reset."

-- Inventaire (fiche de personnage)
Mock.equipped = {}              -- [slotID] = { link, level, quality }
local SLOT_IDS = {
    HeadSlot = 1, NeckSlot = 2, ShoulderSlot = 3, BackSlot = 15, ChestSlot = 5, WristSlot = 9,
    HandsSlot = 10, WaistSlot = 6, LegsSlot = 7, FeetSlot = 8, Finger0Slot = 11, Finger1Slot = 12,
    Trinket0Slot = 13, Trinket1Slot = 14, MainHandSlot = 16, SecondaryHandSlot = 17, RangedSlot = 18,
}
function _G.GetInventorySlotInfo(name) return SLOT_IDS[name] end
function _G.GetInventoryItemLink(_, slot) local e = Mock.equipped[slot] return e and e.link end
function _G.GetInventoryItemQuality(_, slot) local e = Mock.equipped[slot] return e and e.quality end
C_Item.GetDetailedItemLevelInfo = function(link)
    for _, e in pairs(Mock.equipped) do if e.link == link then return e.level end end
end
for name in pairs(SLOT_IDS) do CreateFrame("Button", "Character" .. name, UIParent) end
function _G.GetInventoryItemTexture(_, slot) local e = Mock.equipped[slot] return e and (e.texture or "icone") end
_G.InspectFrame = CreateFrame("Frame", "InspectFrame", UIParent)
InspectFrame:Hide()
for name in pairs(SLOT_IDS) do CreateFrame("Button", "Inspect" .. name, InspectFrame) end
Mock.inspects = {}
function _G.CanInspect(unit) return Mock.units[unit] ~= nil end
function _G.NotifyInspect(unit) Mock.inspects[#Mock.inspects + 1] = unit end
Mock.raidActions = {}
local function RaidAction(name) return function(...) Mock.raidActions[#Mock.raidActions + 1] = { name, ... } end end
_G.DoReadyCheck = RaidAction("ready")
_G.InitiateRolePoll = RaidAction("roles")
_G.SetRaidTarget = RaidAction("mark")
_G.C_PartyInfo = _G.C_PartyInfo or {}
C_PartyInfo.DoCountdown = RaidAction("countdown")
CreateFrame("Frame", "CharacterFrame", UIParent)
CreateFrame("Frame", "PaperDollFrame", CharacterFrame)

-- Curseur
function _G.GetCursorPosition() return 500, 400 end
function FrameMeta:GetEffectiveScale() return 1 end

-- Mémoire des addons
Mock.addons = { { name = "AeonUI", kb = 300 }, { name = "Gros", kb = 4096 }, { name = "Petit", kb = 10 } }
function _G.UpdateAddOnMemoryUsage() end
function _G.GetAddOnMemoryUsage(i) return Mock.addons[i] and Mock.addons[i].kb end
_G.C_AddOns = {
    GetNumAddOns = function() return #Mock.addons end,
    GetAddOnInfo = function(i) return Mock.addons[i] and Mock.addons[i].name end,
    IsAddOnLoaded = function(name) return Mock.loadedAddons[name] == true end,
}

-- Régions et enfants (mode sombre des cadres)
function FrameMeta:GetObjectType() return self.objectType or self.frameType or "Frame" end
function FrameMeta:SetVertexColor(r, g, b, a) self.vertex = { r, g, b, a } end
function FrameMeta:GetVertexColor()
    local v = self.vertex or { 1, 1, 1, 1 }
    return v[1], v[2], v[3], v[4]
end
-- Coordonnées de texture : 8 valeurs comme le client (ULx,ULy,LLx,LLy,URx,URy,LRx,LRy),
-- ou 4 (left,right,top,bottom) converties.
function FrameMeta:SetTexCoord(...)
    local n = select("#", ...)
    if n == 4 then
        local l, r, t, b = ...
        self.texCoord = { l, t, l, b, r, t, r, b }
    else
        self.texCoord = { ... }
    end
end
function FrameMeta:GetTexCoord()
    local c = self.texCoord or { 0, 0, 0, 1, 1, 0, 1, 1 }
    return c[1], c[2], c[3], c[4], c[5], c[6], c[7], c[8]
end

local baseCreateTexture = FrameMeta.CreateTexture
function FrameMeta:CreateTexture(...)
    local texture = baseCreateTexture(self, ...)
    texture.objectType = "Texture"
    self.regions = self.regions or {}
    self.regions[#self.regions + 1] = texture
    return texture
end
local baseCreateFontString = FrameMeta.CreateFontString
function FrameMeta:CreateFontString(...)
    local fontString = baseCreateFontString(self, ...)
    fontString.objectType = "FontString"
    self.regions = self.regions or {}
    self.regions[#self.regions + 1] = fontString
    return fontString
end
function FrameMeta:GetRegions() return unpack(self.regions or {}) end
function FrameMeta:GetChildren()
    local children = {}
    for _, frame in ipairs(Mock.frames) do
        if frame.parent == self then children[#children + 1] = frame end
    end
    return unpack(children)
end
function FrameMeta:SetStatusBarColor(r, g, b) self.barColor = { r, g, b } end
function FrameMeta:SetStatusBarDesaturated(v) self.desaturated = v end
function FrameMeta:SetStatusBarTexture() end
function FrameMeta:SetMinMaxValues(lo, hi) self.min, self.max = lo, hi end
function FrameMeta:SetOrientation(o) self.orientation = o end
function FrameMeta:GetOrientation() return self.orientation or "HORIZONTAL" end
function FrameMeta:StartMoving() end
function FrameMeta:SetCooldown(start, duration) self.cooldownStart, self.cooldownDuration = start, duration end

-- Cadres d'unité Blizzard (chemin du moteur 12.x)
local function UnitFrameMock(name, contentName)
    local frame = CreateFrame("Frame", name, UIParent)
    frame.secure = true
    local content = CreateFrame("Frame", nil, frame)
    frame[contentName .. "Content"] = content
    local main = CreateFrame("Frame", nil, content)
    content[contentName .. "ContentMain"] = main
    local container = CreateFrame("Frame", nil, main)
    main.HealthBarsContainer = container
    container.HealthBar = CreateFrame("StatusBar", nil, container)
    frame.border = frame:CreateTexture(nil, "ARTWORK")
    return frame
end
UnitFrameMock("PlayerFrame", "PlayerFrame")
UnitFrameMock("TargetFrame", "TargetFrame")
UnitFrameMock("FocusFrame", "TargetFrame")

-- Erreurs rouges
CreateFrame("Frame", "UIErrorsFrame", UIParent)
UIErrorsFrame:RegisterEvent("UI_ERROR_MESSAGE")

_G.Settings.RegisterCanvasLayoutSubcategory = function(parent, panel, name)
    Mock.subcategories = Mock.subcategories or {}
    Mock.subcategories[#Mock.subcategories + 1] = name
    return { GetID = function() return name end }
end

--------------------------------------------------------------------------------
-- Compléments v3 : zones de texte, Edit Mode, Cooldown Manager, addons, LFG, débuffs
--------------------------------------------------------------------------------

for _, name in ipairs({ "SetMultiLine", "SetMaxLetters", "SetTextInsets", "HighlightText", "SetFocus" }) do
    FrameMeta[name] = NoOp
end
function FrameMeta:Enable() self.disabled = nil end
function FrameMeta:Disable() self.disabled = true end
function FrameMeta:IsEnabled() return not self.disabled end
function FrameMeta:Click(button)
    self.clicks = (self.clicks or 0) + 1
    if self.scripts.OnClick then self.scripts.OnClick(self, button or "LeftButton") end
end
function FrameMeta:Clear() self.cooldownStart, self.cooldownDuration = nil, nil end
--- Saisie utilisateur dans une EditBox (déclenche OnTextChanged avec userInput=true).
function FrameMeta:Type(text)
    self.text = text
    if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self, true) end
end

-- Edit Mode
_G.Enum.EditModePresetLayoutsMeta = { NumValues = 2 }
_G.Enum.EditModeLayoutType = { Account = 0, Character = 1 }
Mock.editMode = { layouts = { layouts = {}, activeLayout = 1 }, added = {} }
_G.C_EditMode = {
    GetLayouts = function() return Mock.editMode.layouts end,
    SaveLayouts = function(layouts) Mock.editMode.layouts = layouts end,
    ConvertStringToLayoutInfo = function(text)
        if text == "" or text == "cassé" then return nil end
        return { blob = text }
    end,
    ConvertLayoutInfoToString = function(info) return info.blob end,
    OnLayoutAdded = function(index) Mock.editMode.added[#Mock.editMode.added + 1] = index end,
    SetActiveLayout = function(index) Mock.editMode.layouts.activeLayout = index end,
}

-- Cooldown Manager
Mock.cooldownLayouts = { created = {}, active = nil, saved = 0, exportable = "CDM-BLOB" }
local cooldownManager = {
    CreateLayoutsFromSerializedData = function(_, text)
        if text == "" or text == "cassé" then error("invalid") end
        Mock.cooldownLayouts.created[#Mock.cooldownLayouts.created + 1] = text
        return { #Mock.cooldownLayouts.created }
    end,
    SetActiveLayoutByID = function(_, id) Mock.cooldownLayouts.active = id end,
    SaveLayouts = function() Mock.cooldownLayouts.saved = Mock.cooldownLayouts.saved + 1 end,
    -- Comme en jeu (1.60.1) : GetActiveLayout + GetSerializer():CreateEncodeOutput({ layout }).
    GetActiveLayoutID = function() return Mock.cooldownLayouts.active end,
    GetSerializer = function()
        return { SerializeLayouts = function(_, layoutID)
            if layoutID == nil then error("layoutID attendu") end
            return Mock.cooldownLayouts.exportable
        end }
    end,
}
_G.CooldownViewerSettings = { GetLayoutManager = function() return cooldownManager end }

Mock.cvars.cooldownViewerEnabled = "0"
Mock.cvars.nameplateShowEnemies = "0"
Mock.cvars.nameplateMotion = "0"
Mock.cvars.nameplateMaxDistance = "40"
Mock.cvars.cameraDistanceMaxZoomFactor = "1.9"
Mock.cvars.ffxGlow = "1"

-- Liste des addons : état d'activation (0 = désactivé partout) et ordre d'arguments accepté.
_G.Enum.AddOnEnableState = { None = 0, Some = 1, All = 2 }
Mock.addonEnableState = 2
Mock.addonArgOrder = 1          -- 1 = (addon, perso), 2 = (perso, addon), 0 = aucun ne répond
C_AddOns.GetAddOnEnableState = function(a, b)
    local expectAddonFirst = Mock.addonArgOrder == 1
    if Mock.addonArgOrder == 0 then return nil end
    if (expectAddonFirst and a == "AeonUI") or (not expectAddonFirst and b == "AeonUI") then
        return Mock.addonEnableState
    end
    return nil
end
C_AddOns.DisableAddOn = function() end

-- Dialogue de candidature LFGList : Mock.ShowLFGDialog({ tank = true, healer = false }).
function Mock.ShowLFGDialog(roles)
    local dialog = _G.LFGListApplicationDialog or CreateFrame("Frame", "LFGListApplicationDialog", UIParent)
    if not dialog.SignUpButton then
        dialog.SignUpButton = CreateFrame("Button", nil, dialog)
        for _, name in ipairs({ "TankButton", "HealerButton", "DamagerButton" }) do
            dialog[name] = CreateFrame("Frame", nil, dialog)
            dialog[name].CheckButton = CreateFrame("CheckButton", nil, dialog[name])
        end
        dialog.Description = { EditBox = CreateFrame("EditBox", nil, dialog) }
        dialog:Hide()
    end
    dialog.TankButton.CheckButton:SetChecked(roles.tank == true)
    dialog.HealerButton.CheckButton:SetChecked(roles.healer == true)
    dialog.DamagerButton.CheckButton:SetChecked(roles.damager == true)
    dialog.SignUpButton.clicks = 0
    dialog.Description.EditBox:SetText("")
    dialog:Show()
    return dialog
end

-- Débuffs d'une unité : Mock.debuffs[unit] = { { icon=, duration=, expirationTime= }, ... }
Mock.debuffs = {}
local baseGetAuraDataByIndex = C_UnitAuras.GetAuraDataByIndex
C_UnitAuras.GetAuraDataByIndex = function(unit, index, filter)
    if filter == "HARMFUL" then
        local list = Mock.debuffs[unit]
        return list and list[index] or nil
    end
    return baseGetAuraDataByIndex(unit, index, filter)
end

--------------------------------------------------------------------------------
-- Cadres d'unité (étape 2)
--------------------------------------------------------------------------------

function Mock.SetSecret(value) Mock.secret[value] = true return value end

-- RegisterUnitWatch : visible tant que l'unité existe. Mock.RefreshUnitWatch() après un
-- changement d'unités ; FireEvent le fait aussi.
Mock.unitWatch = {}
function _G.RegisterUnitWatch(frame) Mock.unitWatch[frame] = true Mock.RefreshUnitWatch() end
function _G.UnregisterUnitWatch(frame) Mock.unitWatch[frame] = nil end
function Mock.RefreshUnitWatch()
    for frame in pairs(Mock.unitWatch) do
        local unit = frame:GetAttribute("unit")
        if unit and UnitExists(unit) then frame:Show() else frame:Hide() end
    end
end
local baseFireEvent = Mock.FireEvent
function Mock.FireEvent(event, ...)
    Mock.RefreshUnitWatch()
    if event == "GROUP_ROSTER_UPDATE" and Mock.UpdateGroupHeaders then Mock.UpdateGroupHeaders() end
    return baseFireEvent(event, ...)
end

function FrameMeta:SetStatusBarTexture(texture) self.barTexture = texture end
function FrameMeta:GetValue() return self.value end
function FrameMeta:GetMinMaxValues() return self.min, self.max end
function FrameMeta:SetTimerDuration(duration, interpolation, direction)
    self.timer = { duration = duration, interpolation = interpolation, direction = direction }
end
function FrameMeta:SetWordWrap() end
function FrameMeta:SetAlpha(alpha) self.alpha = alpha end
function FrameMeta:GetAlpha() return self.alpha or 1 end

Enum.StatusBarTimerDirection = { ElapsedTime = 0, RemainingTime = 1 }
Enum.StatusBarInterpolation = { Immediate = 0, ExponentialEaseOut = 1 }
Enum.PowerType = { Mana = 0, Rage = 1, Focus = 2, Energy = 3, ComboPoints = 4 }
_G.PowerBarColor = {
    MANA = { r = 0, g = 0, b = 1 }, RAGE = { r = 1, g = 0, b = 0 }, ENERGY = { r = 1, g = 1, b = 0 },
    [0] = { r = 0, g = 0, b = 1 }, [1] = { r = 1, g = 0, b = 0 }, [3] = { r = 1, g = 1, b = 0 },
}
_G.DebuffTypeColor = { Magic = { r = 0.2, g = 0.6, b = 1 }, Poison = { r = 0, g = 0.6, b = 0 } }

function _G.UnitPower(unit, powerType)
    local u = Mock.units[unit]
    if not u then return 0 end
    if powerType == 4 then return u.combo or 0 end
    return u.power or 0
end
function _G.UnitPowerMax(unit, powerType)
    local u = Mock.units[unit]
    if not u then return 0 end
    if powerType == 4 then return u.comboMax or 0 end
    return u.powerMax or 0
end
function _G.UnitPowerType(unit)
    local u = Mock.units[unit]
    local token = u and u.powerType or "MANA"
    local ids = { MANA = 0, RAGE = 1, FOCUS = 2, ENERGY = 3 }
    if Mock.secret[token] then return token, token end   -- jeton secret : l'id l'est aussi
    return ids[token] or 0, token
end
function _G.UnitReaction(unit)
    local u = Mock.units[unit]
    if not u then return nil end
    if u.reaction then return u.reaction end
    return u.hostile and 2 or 5
end
function _G.UnitLevel(unit) local u = Mock.units[unit] return u and u.level or 1 end
function _G.GetMaxPlayerLevel() return 60 end
function _G.GetQuestDifficultyColor(level) return { r = 1, g = 1, b = 0 } end
function _G.UnitIsGroupLeader(unit) local u = Mock.units[unit] return u ~= nil and u.leader == true end
function _G.UnitCastingInfo(unit)
    local u = Mock.units[unit]
    local cast = u and u.casting
    if type(cast) == "table" then
        return cast.name, cast.text or cast.name, cast.texture, cast.startTime, cast.endTime, false,
               cast.castID, cast.notInterruptible, cast.spellID
    end
    return cast
end
function _G.UnitChannelInfo(unit)
    local u = Mock.units[unit]
    local cast = u and u.channel
    if not cast then return nil end
    return cast.name, cast.text or cast.name, cast.texture, cast.startTime, cast.endTime, false,
           cast.notInterruptible, cast.spellID
end
function _G.UnitCastingDuration(unit) local u = Mock.units[unit] return u and u.casting and u.casting.duration or 0 end
function _G.UnitChannelDuration(unit) local u = Mock.units[unit] return u and u.channel and u.channel.duration or 0 end
function _G.GetRaidTargetIndex(unit) local u = Mock.units[unit] return u and u.raidIcon or nil end
function _G.SetRaidTargetIconTexture(texture, index) texture.raidIndex = index end
function _G.AbbreviateNumbers(n)
    if Mock.secret[n] then return "***" end
    if type(n) ~= "number" then return tostring(n) end
    if n >= 1e6 then return string.format("%.1fM", n / 1e6) end
    if n >= 1e3 then return string.format("%.1fk", n / 1e3) end
    return tostring(n)
end
C_AddOns.LoadAddOn = function(name) Mock.loadedAddons[name] = true return true end
Mock.auraContainer = false

-- Barres d'action : raccourcis Blizzard et surcharges
function FrameMeta:SetID(id) self.id = id end
function FrameMeta:GetID() return self.id or 0 end
Mock.bindings = { ACTIONBUTTON1 = "1", ACTIONBUTTON2 = "2", MULTIACTIONBAR1BUTTON1 = "F1" }
function _G.GetBindingKey(command) return Mock.bindings[command] end
Mock.overrideBindings = {}
function _G.SetOverrideBindingClick(owner, _, key, buttonName)
    if Mock.combat then error("ADDON_ACTION_BLOCKED: SetOverrideBindingClick en combat") end
    Mock.overrideBindings[owner] = Mock.overrideBindings[owner] or {}
    Mock.overrideBindings[owner][key] = buttonName
end
function _G.ClearOverrideBindings(owner) Mock.overrideBindings[owner] = nil end
function _G.GetActionBarPage() return 1 end

for _, name in ipairs({ "TargetFrameToT", "FocusFrameToT", "PetFrame", "ComboFrame", "PlayerCastingBarFrame",
                        "PartyFrame", "CompactRaidFrameContainer", "CompactRaidFrameManager",
                        "MainMenuBar", "MainActionBar", "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight", "MultiBarLeft", "MultiBar5" }) do
    local frame = CreateFrame("Frame", name, UIParent)
    frame.secure = true
end

-- Auras du joueur (Skin recadre leurs icônes). Une icône avec le liseré Blizzard (0.07).
-- Suivi de quêtes et panneaux (étape 6)
_G.ObjectiveTrackerFrame = CreateFrame("Frame", "ObjectiveTrackerFrame", UIParent)
ObjectiveTrackerFrame:SetSize(260, 400)
ObjectiveTrackerFrame.Header = { Background = ObjectiveTrackerFrame:CreateTexture(), Text = ObjectiveTrackerFrame:CreateFontString() }
ObjectiveTrackerFrame.Header.Text:SetFont("Fonts\\MORPHEUS.TTF", 16, "")
ObjectiveTrackerFrame.modules = { { Header = { Background = ObjectiveTrackerFrame:CreateTexture(), Text = ObjectiveTrackerFrame:CreateFontString() } } }
function ObjectiveTrackerFrame:SetCollapsed(collapsed) self.isCollapsed = collapsed end
function ObjectiveTrackerFrame:IsCollapsed() return self.isCollapsed == true end
CharacterFrame.NineSlice = CreateFrame("Frame", nil, CharacterFrame)
CharacterFrame.NineSlice.TopEdge = CharacterFrame.NineSlice:CreateTexture()
CharacterFrame.Bg = CharacterFrame:CreateTexture()
-- Barres de données (étape 6)
Mock.xp = { cur = 250, max = 1000, rested = 100 }
function _G.UnitXP() return Mock.xp.cur end
function _G.UnitXPMax() return Mock.xp.max end
function _G.GetXPExhaustion() return Mock.xp.rested end
function _G.GetWatchedFactionInfo()
    local f = Mock.watchedFaction
    if not f then return nil end
    return f.name, f.standing, f.min, f.max, f.value
end
_G.FACTION_STANDING_LABEL4 = "Neutre"
_G.FACTION_STANDING_LABEL5 = "Amical"
for _, name in ipairs({ "MainStatusTrackingBarContainer", "StatusTrackingBarManager" }) do CreateFrame("Frame", name, UIParent) end
-- Chat (étape 6)
_G.NUM_CHAT_WINDOWS = 3
_G.CHAT_FRAME_TEXTURES = { "Background", "TopLeftTexture", "BottomLeftTexture" }
_G.ChatFontNormal = {}
_G.ChatTypeInfo = { SAY = { colorNameByClass = false }, GUILD = { colorNameByClass = false } }
function _G.SetChatColorNameByClass(chatType, on) ChatTypeInfo[chatType].colorNameByClass = on end
function _G.SetItemRef(link) Mock.lastItemRef = link end
for i = 1, NUM_CHAT_WINDOWS do
    local name = "ChatFrame" .. i
    local frame = CreateFrame("ScrollingMessageFrame", name, UIParent)
    frame.font, frame.fontSize, frame.fontFlags = "Fonts\\FRIZQT__.TTF", 14, ""
    frame.messages, frame.maxLines = {}, 128
    function frame:AddMessage(text, r, g, b) self.messages[#self.messages + 1] = { text = text, r = r, g = g, b = b } end
    function frame:GetNumMessages() return #self.messages end
    function frame:GetMessageInfo(index) local m = self.messages[index] return m and m.text, m and m.r, m and m.g, m and m.b end
    function frame:SetFading(fading) self.fading = fading end
    function frame:SetMaxLines(n) self.maxLines = n end
    function frame:GetMaxLines() return self.maxLines end
    for _, suffix in ipairs(CHAT_FRAME_TEXTURES) do _G[name .. suffix] = frame:CreateTexture() end
    local tab = CreateFrame("Button", name .. "Tab", frame)
    tab.Text = tab:CreateFontString()
    _G[name .. "TabLeft"] = tab:CreateTexture()
    _G[name .. "ButtonFrame"] = CreateFrame("Frame", name .. "ButtonFrame", frame)
    frame.editBox = CreateFrame("EditBox", name .. "EditBox", frame)
    _G[name .. "EditBoxLeft"] = frame.editBox:CreateTexture()
end
for _, name in ipairs({ "ChatFrameMenuButton", "ChatFrameChannelButton", "QuickJoinToastButton" }) do CreateFrame("Button", name, UIParent) end
_G.BuffFrame = CreateFrame("Frame", "BuffFrame", UIParent)
BuffFrame.auraFrames = { CreateFrame("Button", nil, BuffFrame) }
BuffFrame.auraFrames[1].Icon = BuffFrame.auraFrames[1]:CreateTexture()
BuffFrame.auraFrames[1].Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
function BuffFrame:UpdateAuraButtons() end

--------------------------------------------------------------------------------
-- Étape 9 : parité ElvUI (infobulles, raccourcis, survol, boss, absence)
--------------------------------------------------------------------------------

-- Survol : Mock.SetMouseOver(frame) ; un seul cadre survolé à la fois.
function FrameMeta:IsMouseOver() return Mock.mouseOver == self end
function Mock.SetMouseOver(frame) Mock.mouseOver = frame end

-- Infobulles : lignes ajoutées gardées, post-calls par type de données.
function FrameMeta:AddLine(text) self.lines = self.lines or {} self.lines[#self.lines + 1] = text end
function FrameMeta:ClearLines() self.lines = {} end
function FrameMeta:SetOwner(owner, anchor) self.owner, self.anchor = owner, anchor end
Enum.TooltipDataType.Item, Enum.TooltipDataType.Spell, Enum.TooltipDataType.UnitAura = 0, 1, 7
Mock.tooltipCallbacks = {}
TooltipDataProcessor.AddTooltipPostCall = function(kind, fn)
    Mock.tooltipCallbacks[#Mock.tooltipCallbacks + 1] = { kind = kind, fn = fn }
end
function Mock.ShowDataTooltip(kind, data)
    GameTooltip:ClearLines()
    GameTooltip:Show()
    for _, entry in ipairs(Mock.tooltipCallbacks) do
        if entry.kind == kind then entry.fn(GameTooltip, data) end
    end
end
function Mock.ShowUnitTooltip(unit)
    Mock.tooltipUnit = unit
    GameTooltipTextLeft2:SetText(Mock.guilds and Mock.guilds[unit] and Mock.guilds[unit][1] or "Level 60")
    Mock.ShowDataTooltip(Enum.TooltipDataType.Unit)
end
function GameTooltip:SetUnit(unit) Mock.ShowUnitTooltip(unit) end
_G.GameTooltipTextLeft2 = NewObject(GameTooltip)
_G.GameTooltipStatusBar = CreateFrame("StatusBar", "GameTooltipStatusBar", GameTooltip)
function _G.GameTooltip_SetDefaultAnchor(tooltip, parent) tooltip:SetOwner(parent, "ANCHOR_NONE") end
Mock.guilds = {}   -- [unit] = { guilde, rang }
function _G.GetGuildInfo(unit) local g = Mock.guilds[unit] if g then return g[1], g[2] end end

-- Raccourcis
function _G.IsControlKeyDown() return Mock.ctrl == true end
Mock.saved = 0
function _G.SetBinding(key, command)
    if Mock.combat then error("ADDON_ACTION_BLOCKED: SetBinding en combat") end
    for existing, bound in pairs(Mock.bindings) do if bound == key then Mock.bindings[existing] = nil end end
    if command then Mock.bindings[command] = key end
end
function _G.GetCurrentBindingSet() return 1 end
function _G.SaveBindings() Mock.saved = Mock.saved + 1 end
function _G.GetCursorInfo() return Mock.cursorItem end

-- Chiffres de recharge (CVar native)
Mock.cvars.countdownForCooldowns = "0"

-- Écran d'absence
_G.WorldFrame = CreateFrame("Frame", "WorldFrame")
function _G.UnitIsAFK(unit) return unit == "player" and Mock.afk == true end
function _G.MoveViewLeftStart(speed) Mock.cameraSpin = speed end
function _G.MoveViewLeftStop() Mock.cameraSpin = nil end

--------------------------------------------------------------------------------
-- Étape 10 : API Midnight d'affichage (formateur de recharge, courbe, alpha booléen, identité)
--------------------------------------------------------------------------------

function _G.CreateColor(r, g, b, a)
    return { r = r, g = g, b = b, a = a or 1, GetRGB = function(self) return self.r, self.g, self.b end }
end
_G.C_CurveUtil = {
    CreateColorCurve = function()
        local curve = { points = {} }
        function curve:AddPoint(x, color) self.points[#self.points + 1] = { x = x, color = color } end
        return curve
    end,
}
--- Évalue une courbe comme le moteur (ici : le point le plus proche par valeur inférieure).
function Mock.EvaluateCurve(curve, x)
    local best = curve.points[1]
    for _, point in ipairs(curve.points) do if point.x <= x then best = point end end
    return best.color
end
_G.C_StringUtil = {
    CreateNumericRuleFormatter = function()
        return { SetBreakpoints = function(self, points) self.breakpoints = points end }
    end,
}
_G.Enum.NumericRuleFormatRounding = { Up = 1, Down = 2 }
function FrameMeta:SetCountdownFormatter(formatter) self.countdownFormatter = formatter end
function FrameMeta:SetHideCountdownNumbers(hide) self.hideCountdown = hide end
Mock.secretUnits = {}
_G.C_Secrets = { ShouldUnitIdentityBeSecret = function(unit) return Mock.secretUnits[unit] == true end }

return Mock

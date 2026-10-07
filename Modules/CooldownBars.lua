-- Modules/CooldownBars.lua
-- Barres de recharges personnalisées : jusqu'à trois rangées d'icônes AeonUI, une liste de sorts
-- chacune (identifiants, ramenés au rang appris), recharge et charges du moteur, sur leur
-- mover. En complément des viewers Blizzard, pour les sorts qu'ils ne proposent pas.
local _, NS = ...
local L = NS.L
local Media = NS.Media

local BAR_COUNT = 3

local function BarDefaults(enabled, y)
    return { enabled = enabled, spells = "", size = 36, spacing = 4, perRow = 12,
             hideReady = false, desaturate = true, y = y }
end

local CooldownBars = NS.Modules:Register("cooldownbars", {
    titleKey = "CDBARS_TITLE",
    descKey = "CDBARS_DESC",
    defaults = {
        enabled = false,
        bars = { bar1 = BarDefaults(true, -260), bar2 = BarDefaults(false, -310), bar3 = BarDefaults(false, -360) },
    },
})

local active = false
local frames = {}      -- [index] = { holder, icons }

--- Sorts de la liste connus du joueur : { { id, name } }, dans l'ordre écrit.
function CooldownBars.Spells(text)
    local list, seen = {}, {}
    for id in tostring(text or ""):gmatch("%d+") do
        id = tonumber(id)
        local name = NS.GetSpellName(id)
        if name and not seen[name] and NS.KnowsSpell(id) then
            seen[name] = true
            list[#list + 1] = { id = NS.KnownSpellID(id), name = name }
        end
    end
    return list
end

local function MoverKey(index) return "cooldownBar" .. index end

local function Icon(bar, index)
    local icon = bar.icons[index]
    if icon then return icon end
    icon = CreateFrame("Frame", nil, bar.holder)
    Media:CreateBackdrop(icon)
    icon.texture = icon:CreateTexture(nil, "ARTWORK")
    icon.texture:SetAllPoints(icon)
    icon.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon.cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    icon.cooldown:SetAllPoints(icon)
    NS.RegisterCooldown(icon.cooldown)
    icon.count = Media:CreateText(icon, "OVERLAY", 0, "OUTLINE")
    icon.count:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -2, 2)
    bar.icons[index] = icon
    return icon
end

local function Frame(index)
    if frames[index] then return frames[index] end
    local bar = { holder = CreateFrame("Frame", "AeonUICooldownBar" .. index, UIParent), icons = {} }
    frames[index] = bar
    return bar
end

function CooldownBars:UpdateBar(index)
    local cfg = self.db.bars["bar" .. index]
    local bar = Frame(index)
    local on = active and cfg.enabled
    local shown = 0
    local perRow = math.max(1, cfg.perRow)
    for _, spell in ipairs(on and self.Spells(cfg.spells) or {}) do
        local ready = NS.IsSpellReady(spell.id)
        if not (cfg.hideReady and ready) or NS.unlocked then
            shown = shown + 1
            local icon = Icon(bar, shown)
            icon:SetSize(cfg.size, cfg.size)
            icon:ClearAllPoints()
            local row, column = math.floor((shown - 1) / perRow), (shown - 1) % perRow
            icon:SetPoint("TOPLEFT", bar.holder, "TOPLEFT", column * (cfg.size + cfg.spacing), -row * (cfg.size + cfg.spacing))
            icon.texture:SetTexture(NS.GetSpellTexture(spell.id))
            if icon.texture.SetDesaturated then icon.texture:SetDesaturated(cfg.desaturate and not ready) end
            NS.SetSpellCooldown(icon.cooldown, spell.id)
            local current, max = NS.GetSpellCharges(spell.id)
            if NS.IsSecret(current) then
                -- combat : le moteur affiche, rien n'est comparé
                if max > 1 then icon.count:SetText(current) else icon.count:SetText("") end
            else
                icon.count:SetText((current and max and max > 1) and tostring(current) or "")
            end
            icon:Show()
        end
    end
    for i = shown + 1, #bar.icons do bar.icons[i]:Hide() end
    local columns = math.max(1, math.min(shown, perRow))
    local rows = math.max(1, math.ceil(shown / perRow))
    bar.holder:SetSize(columns * (cfg.size + cfg.spacing) - cfg.spacing, rows * (cfg.size + cfg.spacing) - cfg.spacing)
    bar.holder:SetShown(on and (shown > 0 or NS.unlocked) or false)
    if on and not bar.registered then
        bar.registered = true
        NS.Movers:Register(MoverKey(index), bar.holder, string.format(L.CDBARS_MOVER, index), "CENTER", 0, cfg.y)
        NS.Movers:Load(MoverKey(index))
    elseif not on and bar.registered then
        bar.registered = nil
        NS.Movers:Unregister(MoverKey(index))
    end
end

function CooldownBars:Update()
    for index = 1, BAR_COUNT do self:UpdateBar(index) end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function() CooldownBars:Update() end)

function CooldownBars:OnEnable()
    active = true
    for _, event in ipairs({ "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_CHARGES", "SPELLS_CHANGED", "PLAYER_ENTERING_WORLD" }) do
        NS.RegisterEventSafe(events, event)
    end
    self:Update()
end

function CooldownBars:OnDisable()
    active = false
    events:UnregisterAllEvents()
    self:Update()
end

function CooldownBars:OnRefresh() self:Update() end

NS:On("UNLOCK", function() CooldownBars:Update() end)

function CooldownBars:BuildOptions(o)
    for index = 1, BAR_COUNT do
        local prefix = "bars.bar" .. index .. "."
        o:Title(string.format(L.CDBARS_MOVER, index))
        o:Check(prefix .. "enabled", L.OPT_CDBARS_ENABLED)
        o:EditBox(prefix .. "spells", L.OPT_CDBARS_SPELLS, 2, 36)
        o:Slider(prefix .. "size", L.OPT_MOVEMENT_ICON_SIZE, 16, 64, 1, 36)
        o:Advanced()
        o:Slider(prefix .. "spacing", L.OPT_AURABARS_SPACING, 0, 12, 1, 36)
        o:Slider(prefix .. "perRow", L.OPT_CDBARS_PER_ROW, 1, 24, 1, 36)
        o:EndAdvanced()
        o:Check(prefix .. "hideReady", L.OPT_CDBARS_HIDE_READY, 36)
        o:Advanced()
        o:Check(prefix .. "desaturate", L.OPT_CDBARS_DESATURATE, 36)
        o:EndAdvanced()
    end
end

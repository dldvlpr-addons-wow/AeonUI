-- AeonUI_GroupFrames/ClickCast.lua
-- Clic-sort sur les cadres de groupe et de raid : un clic (bouton de souris + modificateur) lance
-- un sort sur le membre cliqué. Liaisons posées en attributs sécurisés (« shift-type1 » = "spell",
-- « shift-spell1 » = nom du sort), donc hors combat seulement ; les clics sans liaison gardent
-- cible (gauche) et menu (droit). Préréglages par classe : dissipations, résurrection, soins.
local NS = AeonUI
local L = NS.L

local NUM_BINDINGS = 8
-- Clés chaînes (b1…b8) : l'export de profil et le miroir CVar n'aplatissent que celles-là.
local BINDING_KEYS, BINDINGS = {}, {}
for i = 1, NUM_BINDINGS do
    BINDING_KEYS[i] = "b" .. i
    BINDINGS[BINDING_KEYS[i]] = { mouse = "1", modifier = "shift", spell = "" }
end

local ClickCast = NS.Modules:Register("clickcast", {
    titleKey = "CLICKCAST_TITLE",
    descKey = "CLICKCAST_DESC",
    secure = true,
    defaults = {
        enabled = false,
        bindings = BINDINGS,   -- mouse : "1" à "5" ; modifier : "none", "shift", "ctrl", "alt"
    },
})

-- Sorts de référence par classe (rang 1 : lancé par son nom, le rang le plus haut part).
ClickCast.PRESETS = {
    PRIEST = { 527, 528, 2006, 17, 139, 2061 },      -- Dissipation, Guérison des maladies, Résurrection, Bouclier, Rénovation, Soins rapides
    PALADIN = { 4987, 1152, 7328, 1022, 19750 },     -- Épuration, Purification, Rédemption, Bénédiction de protection, Éclair lumineux
    DRUID = { 2782, 2893, 20484, 774, 8936 },        -- Délivrance de la malédiction, Abolir le poison, Renaissance, Récupération, Rétablissement
    SHAMAN = { 526, 2870, 2008, 331 },               -- Guérison du poison, Guérison des maladies, Esprit ancestral, Vague de soins
    MAGE = { 475 },                                  -- Délivrance de la malédiction mineure
}
-- Ordre des liaisons d'un préréglage : Maj, Ctrl, Alt sur le clic gauche, puis sur le clic droit.
local PRESET_SLOTS = {
    { "1", "shift" }, { "1", "ctrl" }, { "1", "alt" }, { "2", "shift" }, { "2", "ctrl" }, { "2", "alt" },
    { "3", "none" }, { "3", "shift" },
}

local active = false

--- Préfixe d'attribut d'un modificateur ("shift-", "" sans modificateur).
local function Prefix(modifier)
    if modifier == "shift" or modifier == "ctrl" or modifier == "alt" then return modifier .. "-" end
    return ""
end

--- Liaisons valides du profil : { attribut de type, attribut de sort, nom du sort }.
function ClickCast:Bindings()
    local list = {}
    if not active then return list end
    for _, key in ipairs(BINDING_KEYS) do
        local binding = self.db.bindings[key]
        local spell = binding and tostring(binding.spell or ""):match("^%s*(.-)%s*$")
        local mouse = binding and tonumber(binding.mouse)
        if spell and spell ~= "" and mouse and mouse >= 1 and mouse <= 5 then
            local prefix = Prefix(binding.modifier)
            list[#list + 1] = { prefix .. "type" .. mouse, prefix .. "spell" .. mouse, spell }
        end
    end
    return list
end

--- Pose les liaisons sur `button` (hors combat), en retirant celles posées avant.
function ClickCast:Apply(button)
    for _, name in ipairs(button.clickCastAttributes or {}) do button:SetAttribute(name, nil) end
    local applied = {}
    for _, binding in ipairs(self:Bindings()) do
        button:SetAttribute(binding[1], "spell")
        button:SetAttribute(binding[2], binding[3])
        applied[#applied + 1] = binding[1]
        applied[#applied + 1] = binding[2]
    end
    button.clickCastAttributes = applied
end

--- Liaisons reposées sur tous les boutons de groupe existants (hors combat).
function ClickCast:ApplyAll()
    NS:RunOutOfCombat(function()
        local groupFrames = NS.Modules:Get("groupframes")
        for _, header in pairs(groupFrames and groupFrames.headers or {}) do
            for _, button in ipairs(header.buttons or {}) do self:Apply(button) end
        end
        for _, button in ipairs(groupFrames and groupFrames.bossHeader.buttons or {}) do self:Apply(button) end
    end)
end

--- Remplit les liaisons avec les sorts connus du préréglage de la classe du joueur.
function ClickCast:ApplyPreset()
    local _, classFile = UnitClass("player")
    local preset = not NS.IsSecret(classFile) and ClickCast.PRESETS[classFile or ""] or {}
    local slot = 0
    for _, key in ipairs(BINDING_KEYS) do self.db.bindings[key].spell = "" end
    for _, id in ipairs(preset) do
        local name = NS.KnowsSpell(id) and NS.GetSpellName(id)
        if name and slot < NUM_BINDINGS then
            slot = slot + 1
            local binding = self.db.bindings[BINDING_KEYS[slot]]
            binding.mouse, binding.modifier, binding.spell = PRESET_SLOTS[slot][1], PRESET_SLOTS[slot][2], name
        end
    end
    self:ApplyAll()
    return slot
end

function ClickCast:OnEnable()
    active = true
    self:ApplyAll()
end

function ClickCast:OnDisable()
    active = false
    self:ApplyAll()   -- sans liaison : attributs retirés
end

function ClickCast:OnRefresh()
    self:ApplyAll()
end

function ClickCast:BuildOptions(o)
    o:Note(L.CLICKCAST_NOTE)
    o:Button(L.CLICKCAST_PRESET, function()
        NS.Print(string.format(L.MSG_CLICKCAST_PRESET, ClickCast:ApplyPreset()))
        o.layout:Refresh()
    end)
    local mice = {}
    for i = 1, 5 do mice[#mice + 1] = { name = L["CLICKCAST_MOUSE_" .. i], value = tostring(i) } end
    local modifiers = {
        { name = L.CLICKCAST_MODIFIER_NONE, value = "none" }, { name = L.CLICKCAST_MODIFIER_SHIFT, value = "shift" },
        { name = L.CLICKCAST_MODIFIER_CTRL, value = "ctrl" }, { name = L.CLICKCAST_MODIFIER_ALT, value = "alt" },
    }
    for i, key in ipairs(BINDING_KEYS) do
        local prefix = "bindings." .. key .. "."
        o:Title(string.format(L.CLICKCAST_BINDING, i))
        o:EditBox(prefix .. "spell", L.CLICKCAST_SPELL, 1, 36)
        o:Dropdown(prefix .. "mouse", L.CLICKCAST_MOUSE, mice, 36)
        o:Dropdown(prefix .. "modifier", L.CLICKCAST_MODIFIER, modifiers, 36)
    end
end

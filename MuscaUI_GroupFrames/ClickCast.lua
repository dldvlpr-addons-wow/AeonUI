-- MuscaUI_GroupFrames/ClickCast.lua
-- Clic-sort sur les cadres de groupe et de raid : un clic (bouton de souris + modificateur) ou une
-- touche au survol lance un sort, une macro ou un objet sur le membre visé. Liaisons posées en
-- attributs sécurisés (« shift-type1 » = "spell", « shift-spell1 » = nom du sort), donc hors combat
-- seulement ; les clics sans liaison gardent cible (gauche) et menu (droit). Touche : un en-tête
-- sécurisé lie la touche au bouton survolé (SetBindingClick, bouton virtuel « muscacastN ») et la
-- délie à la sortie ou quand le bouton se cache. Préréglages par classe : dissipations, résurrection, soins.
-- Touche : molette comprise (MOUSEWHEELUP / DOWN) ; clic : combinaisons de modificateurs ; sort glissé
-- depuis le grimoire (rang inférieur épinglé « Nom(Rang 3) ») ; option « rez » : sur un mort, le clic
-- lance la résurrection de la classe à la place du sort lié (échange d'attribut en PreClick sécurisé).
local NS = MuscaUI
local L = NS.L

local NUM_BINDINGS = 16
-- Clés chaînes (b1…b16) : l'export de profil et le miroir CVar n'aplatissent que celles-là.
-- `spell` porte la valeur de l'action quel que soit son type (nom de sort, de macro ou d'objet).
local BINDING_KEYS, BINDINGS = {}, {}
for i = 1, NUM_BINDINGS do
    BINDING_KEYS[i] = "b" .. i
    BINDINGS[BINDING_KEYS[i]] = { mouse = "1", modifier = "shift", kind = "spell", spell = "", key = "", oocOnly = false }
end

local ClickCast = NS.Modules:Register("clickcast", {
    titleKey = "CLICKCAST_TITLE",
    descKey = "CLICKCAST_DESC",
    secure = true,
    defaults = {
        enabled = false,
        unitFrames = true,     -- liaisons aussi sur les cadres d'unité MuscaUI_UF_*
        resurrect = false,     -- membre mort : le clic lance la résurrection de la classe
        nativeClicks = true,   -- cadres de groupe : clic gauche = cibler, clic droit = menu ; false : rien sans liaison
        -- mouse : "0" (aucun) à "5" ; modifier : "none" ou une combinaison « alt-ctrl-shift » (ordre libre) ;
        -- kind : "spell", "macro", "item", "trinket1", "trinket2" ; key : touche au survol ("" = aucune) ;
        -- oocOnly : liaison sans effet en combat (le clic retombe sur la cible ou le menu natifs)
        bindings = BINDINGS,
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
-- Résurrection hors combat de la classe (le nom sans rang lance le rang le plus haut connu).
-- Pas le druide : Renaissance est un rez de combat à longue recharge, un clic de soin la consommerait.
local RESURRECTIONS = { PRIEST = 2006, PALADIN = 7328, SHAMAN = 2008 }
-- Ordre des liaisons d'un préréglage : Maj, Ctrl, Alt sur le clic gauche, puis sur le clic droit.
local PRESET_SLOTS = {
    { "1", "shift" }, { "1", "ctrl" }, { "1", "alt" }, { "2", "shift" }, { "2", "ctrl" }, { "2", "alt" },
    { "3", "none" }, { "3", "shift" },
}

-- Type d'action -> type sécurisé ; bijoux : emplacement équipé, suivi après un changement de bijou.
local KINDS = { spell = "spell", macro = "macro", item = "item", trinket1 = "item", trinket2 = "item" }
local TRINKET_SLOTS = { trinket1 = "13", trinket2 = "14" }

-- Touche au survol : liée au bouton survolé, priorité sur les raccourcis du joueur tant que la
-- souris y reste. ClearBindings ne retire que les liaisons dont le bouton est propriétaire.
local KEY_ATTRIBUTE = "muscacast-key"
local ON_ENTER = string.format([[
    for i = 1, %d do
        local key = self:GetAttribute("%s" .. i)
        if key then self:SetBindingClick(true, key, self, "muscacast" .. i) end
    end
]], NUM_BINDINGS, KEY_ATTRIBUTE)
local ON_LEAVE = "self:ClearBindings()"
-- Résurrection : si l'unité du bouton est morte, les attributs de sort listés (« muscacast-rezN » =
-- nom d'attribut) prennent le sort de rez le temps du clic, puis reviennent à leur valeur.
-- Deux wraps : PreClick échange (avant OnClick, qui lit l'attribut), PostClick restaure (après).
-- Un seul corps par script (rez puis hors combat), sans `function` ni `return` : l'environnement
-- restreint refuse le mot-clé function, et un return anticipé couperait le second bloc.
local PRE_CLICK = [[
    local unit, rez = self:GetAttribute("unit"), self:GetAttribute("muscacast-rez")
    if not self:GetAttribute("muscacast-swapped") and unit and rez and UnitExists(unit) and (UnitIsDead(unit) or UnitIsGhost(unit)) then
        for i = 1, self:GetAttribute("muscacast-rezcount") or 0 do
            local name = self:GetAttribute("muscacast-rez" .. i)
            self:SetAttribute("muscacast-orig" .. i, self:GetAttribute(name))
            self:SetAttribute(name, rez)
        end
        self:SetAttribute("muscacast-swapped", true)
    end
    -- « Hors combat seulement » : les attributs de type listés (« muscacast-oocN ») sont retirés le
    -- temps d'un clic en combat, puis rendus.
    if not self:GetAttribute("muscacast-oocswapped") and PlayerInCombat() then
        for i = 1, self:GetAttribute("muscacast-ooccount") or 0 do
            local name = self:GetAttribute("muscacast-ooc" .. i)
            self:SetAttribute("muscacast-oocorig" .. i, self:GetAttribute(name))
            self:SetAttribute(name, nil)
        end
        self:SetAttribute("muscacast-oocswapped", true)
    end
]]
local POST_CLICK = [[
    if self:GetAttribute("muscacast-swapped") then
        self:SetAttribute("muscacast-swapped", nil)
        for i = 1, self:GetAttribute("muscacast-rezcount") or 0 do
            self:SetAttribute(self:GetAttribute("muscacast-rez" .. i), self:GetAttribute("muscacast-orig" .. i))
        end
    end
    if self:GetAttribute("muscacast-oocswapped") then
        self:SetAttribute("muscacast-oocswapped", nil)
        for i = 1, self:GetAttribute("muscacast-ooccount") or 0 do
            self:SetAttribute(self:GetAttribute("muscacast-ooc" .. i), self:GetAttribute("muscacast-oocorig" .. i))
        end
    end
]]
local keyHeader = CreateFrame("Frame", "MuscaUI_ClickCastHeader", UIParent, "SecureHandlerBaseTemplate")

local active = false
local appliedRez   -- rez posé par la dernière application (SPELLS_CHANGED : réappliquer s'il change)

--- Préfixe d'attribut d'un modificateur ou d'une combinaison ("alt-ctrl-shift-", "" sans modificateur).
-- Ordre imposé par SecureTemplates (alt, ctrl, shift), quel que soit l'ordre saisi dans le profil.
local MODIFIER_ORDER = { "alt", "ctrl", "shift" }
local function Prefix(modifier)
    if type(modifier) ~= "string" then return "" end
    local wrapped, prefix = "-" .. modifier .. "-", ""
    for _, name in ipairs(MODIFIER_ORDER) do
        if wrapped:find("-" .. name .. "-", 1, true) then prefix = prefix .. name .. "-" end
    end
    return prefix
end

--- Nom du sort de résurrection connu de la classe du joueur ; nil sans (classe sans rez, non appris).
local function ResurrectionName()
    local _, classFile = UnitClass("player")
    local id = not NS.IsSecret(classFile) and RESURRECTIONS[classFile or ""]
    return id and NS.KnowsSpell(id) and NS.GetSpellName(id) or nil
end

--- Texte à poser dans la liaison pour le sort `spellID` (glissé du grimoire) : « Nom(Rang 3) » pour
-- un rang inférieur au rang connu le plus haut (épinglé), « Nom » sinon (suit les rangs appris).
function ClickCast.SpellText(spellID)
    local name = spellID and NS.GetSpellName(spellID)
    if not name then return nil end
    local subtext = NS.GetSpellRankText(spellID)
    if subtext and NS.KnownSpellID(spellID) ~= spellID then return name .. "(" .. subtext .. ")" end
    return name
end

--- Type sécurisé et valeur d'une liaison ; nil sans valeur.
local function Action(binding)
    local kind = KINDS[binding.kind] and binding.kind or "spell"
    if TRINKET_SLOTS[kind] then return "item", TRINKET_SLOTS[kind] end
    local value = tostring(binding.spell or ""):match("^%s*(.-)%s*$")
    if value == "" then return nil end
    return KINDS[kind], value
end

--- Liaisons valides du profil : { attribut de type, attribut de valeur, type, valeur, touche, rang, hors combat }.
-- Clic : « shift-type1 » ; touche : « *type-muscacastN » (la touche porte déjà son modificateur).
function ClickCast:Bindings()
    local list = {}
    if not active then return list end
    for i, key in ipairs(BINDING_KEYS) do
        local binding = self.db.bindings[key]
        local kind, value = Action(binding or {})
        if kind then
            local mouse = tonumber(binding.mouse)
            if mouse and mouse >= 1 and mouse <= 5 then
                local prefix = Prefix(binding.modifier)
                list[#list + 1] = { prefix .. "type" .. mouse, prefix .. kind .. mouse, kind, value, nil, nil, binding.oocOnly == true }
            end
            if type(binding.key) == "string" and binding.key ~= "" then
                local suffix = "-muscacast" .. i
                list[#list + 1] = { "*type" .. suffix, "*" .. kind .. suffix, kind, value, binding.key, i, binding.oocOnly == true }
            end
        end
    end
    return list
end

--- Pose les liaisons sur `button`, en retirant celles posées avant. En combat : à la sortie.
function ClickCast:Apply(button)
    if NS.InCombat() then NS:RunOutOfCombat(function() self:Apply(button) end) return end
    for _, name in ipairs(button.clickCastAttributes or {}) do button:SetAttribute(name, nil) end
    button:SetAttribute("muscacast-swapped", nil)
    local applied = {}
    local rez = self.db.resurrect and ResurrectionName()
    appliedRez = rez
    local rezCount, combatCount = 0, 0
    local unitFrame = (button:GetName() or ""):match("^MuscaUI_UF_")
    if not unitFrame then   -- clics sans liaison : cible et menu natifs, ou rien
        local native = not (active and self.db.nativeClicks == false)
        button:SetAttribute("*type1", native and "target" or nil)
        button:SetAttribute("*type2", native and "togglemenu" or nil)
    end
    if not (unitFrame and not self.db.unitFrames) then
        for _, binding in ipairs(self:Bindings()) do
            button:SetAttribute(binding[1], binding[3])
            button:SetAttribute(binding[2], binding[4])
            applied[#applied + 1] = binding[1]
            applied[#applied + 1] = binding[2]
            if rez and binding[3] == "spell" then
                rezCount = rezCount + 1
                button:SetAttribute("muscacast-rez" .. rezCount, binding[2])
                applied[#applied + 1] = "muscacast-rez" .. rezCount
            end
            if binding[7] then
                combatCount = combatCount + 1
                button:SetAttribute("muscacast-ooc" .. combatCount, binding[1])
                applied[#applied + 1] = "muscacast-ooc" .. combatCount
            end
            if binding[5] then
                button:SetAttribute(KEY_ATTRIBUTE .. binding[6], binding[5])
                applied[#applied + 1] = KEY_ATTRIBUTE .. binding[6]
            end
        end
    end
    if rezCount > 0 then
        button:SetAttribute("muscacast-rez", rez)
        button:SetAttribute("muscacast-rezcount", rezCount)
        applied[#applied + 1], applied[#applied + 2] = "muscacast-rez", "muscacast-rezcount"
    end
    button:SetAttribute("muscacast-oocswapped", nil)
    button:SetAttribute("muscacast-ooccount", combatCount)
    applied[#applied + 1] = "muscacast-ooccount"
    button.clickCastAttributes = applied
    if not button.clickCastWrapped then
        button.clickCastWrapped = true
        keyHeader:WrapScript(button, "OnEnter", ON_ENTER)
        keyHeader:WrapScript(button, "OnLeave", ON_LEAVE)
        keyHeader:WrapScript(button, "PreClick", PRE_CLICK)
        keyHeader:WrapScript(button, "PostClick", POST_CLICK)
        keyHeader:WrapScript(button, "OnHide", ON_LEAVE)   -- groupe qui change en combat : aucune touche restée liée
    end
end

--- Liaisons reposées sur tous les boutons de groupe et cadres d'unité existants (hors combat).
function ClickCast:ApplyAll()
    NS:RunOutOfCombat(function()
        local groupFrames = NS.Modules:Get("groupframes")
        for _, header in pairs(groupFrames and groupFrames.headers or {}) do
            for _, button in ipairs(header.buttons or {}) do self:Apply(button) end
        end
        for _, button in ipairs(groupFrames and groupFrames.bossHeader.buttons or {}) do self:Apply(button) end
        local unitFrames = NS.Modules:Get("unitframes")
        for _, frame in pairs(unitFrames and unitFrames.frames or {}) do self:Apply(frame) end
    end)
end

--- Remplit les liaisons avec les sorts connus du préréglage de la classe du joueur.
function ClickCast:ApplyPreset()
    local _, classFile = UnitClass("player")
    local preset = not NS.IsSecret(classFile) and ClickCast.PRESETS[classFile or ""] or {}
    local slot = 0
    for _, key in ipairs(BINDING_KEYS) do
        local binding = self.db.bindings[key]
        binding.kind, binding.spell, binding.key = "spell", "", ""
    end
    for _, id in ipairs(preset) do
        local name = NS.KnowsSpell(id) and NS.GetSpellName(id)
        if name and slot < #PRESET_SLOTS then
            slot = slot + 1
            local binding = self.db.bindings[BINDING_KEYS[slot]]
            binding.mouse, binding.modifier, binding.kind, binding.spell = PRESET_SLOTS[slot][1], PRESET_SLOTS[slot][2], "spell", name
        end
    end
    self:ApplyAll()
    return slot
end

--- Avertissement d'option : macro absente ou objet inconnu (n'empêche jamais la liaison).
function ClickCast.Warning(binding)
    local kind, value = Action(binding)
    if binding.kind == "macro" and kind and not NS.MacroExists(value) then
        return string.format(L.CLICKCAST_MACRO_MISSING, value)
    end
    if binding.kind == "item" and kind and not tonumber(value) and not NS.ItemKnown(value) then
        return string.format(L.CLICKCAST_ITEM_MISSING, value)
    end
    return nil
end

--- Touche capturée (modificateurs compris) ; refusée si un raccourci du joueur la prend déjà.
-- Renvoie la touche retenue, "" pour Échap (effacer), nil si refusée ou modificateur seul.
-- Molette : une touche comme une autre (MOUSEWHEELUP / MOUSEWHEELDOWN), modificateurs compris.
function ClickCast.WheelKey(delta) return delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN" end
local MODIFIER_KEYS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true,
                        LMETA = true, RMETA = true, UNKNOWN = true }
function ClickCast.CaptureKey(pressed)
    if MODIFIER_KEYS[pressed] then return nil end
    if pressed == "ESCAPE" then return "" end
    local combo = (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "")
        .. (IsShiftKeyDown() and "SHIFT-" or "") .. pressed
    -- Molette seule : liée au zoom caméra par défaut, mais la liaison au survol est locale au cadre.
    local action = not pressed:find("^MOUSEWHEEL") and NS.KeyBindingAction(combo)
    if action then
        NS.Print(string.format(L.MSG_CLICKCAST_KEY_TAKEN, combo, action))
        return nil
    end
    return combo
end

-- Sort appris : le rez de la classe peut apparaître ou changer de nom ; réappliqué hors combat.
local spellsWatcher = CreateFrame("Frame")
NS.RegisterEventSafe(spellsWatcher, "SPELLS_CHANGED")
spellsWatcher:SetScript("OnEvent", function()
    if active and ClickCast.db.resurrect and ResurrectionName() ~= appliedRez then ClickCast:ApplyAll() end
end)

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

--- Bouton de saisie de touche : clic, puis touche (Échap efface).
local function KeyButton(o, path)
    local get, set = o:Getter(path), o:Setter(path)
    local button
    local function Paint()
        local key = get()
        button:SetText(string.format(L.CLICKCAST_KEY, key ~= nil and key ~= "" and key or L.CLICKCAST_KEY_NONE))
    end
    local function Stop(self)
        self:EnableKeyboard(false)
        self:EnableMouseWheel(false)
    end
    local function Capture(self, pressed)
        Stop(self)
        local key = ClickCast.CaptureKey(pressed)
        if key then set(key) end
        Paint()
    end
    button = o:Button(string.format(L.CLICKCAST_KEY, L.CLICKCAST_KEY_NONE), function(self)
        self:EnableKeyboard(true)
        self:EnableMouseWheel(true)   -- OnKeyDown ne reçoit pas la molette
        self:SetText(L.CLICKCAST_KEY_WAITING)
    end)
    o.layout:Hint(L.CLICKCAST_KEY_HINT)
    button:SetScript("OnKeyDown", function(self, pressed)
        if MODIFIER_KEYS[pressed] then return end
        Capture(self, pressed)
    end)
    button:SetScript("OnMouseWheel", function(self, delta) Capture(self, ClickCast.WheelKey(delta)) end)
    button:HookScript("OnHide", Stop)
    o.layout.refreshers[#o.layout.refreshers + 1] = Paint
end

--- Champ de sort qui accepte un sort glissé du grimoire (GetCursorInfo : "spell", index, livre, id).
function ClickCast.AcceptDrop(box, onText)
    local function Receive()
        local kind, _, _, spellID = GetCursorInfo()
        if kind ~= "spell" then return end
        local text = ClickCast.SpellText(spellID)
        if not text then return end
        ClearCursor()
        onText(text)
    end
    box:SetScript("OnReceiveDrag", Receive)
    box:HookScript("OnMouseUp", Receive)   -- clic tenant le sort : même effet que le dépôt
end

function ClickCast:BuildOptions(o)
    o:Note(L.CLICKCAST_NOTE)
    o:Check("unitFrames", L.CLICKCAST_UNIT_FRAMES)
    o:Check("nativeClicks", L.OPT_GF_G_CC_NATIVE)
    o.layout:Hint(L.OPT_GF_G_CC_NATIVE_HINT)
    o:Check("resurrect", L.CLICKCAST_REZ)
    o.layout:Hint(L.CLICKCAST_REZ_HINT)
    o:Button(L.CLICKCAST_PRESET, function()
        NS.Print(string.format(L.MSG_CLICKCAST_PRESET, ClickCast:ApplyPreset()))
        o.layout:Refresh()
    end)
    local mice = { { name = L.CLICKCAST_MODIFIER_NONE, value = "0" } }
    for i = 1, 5 do mice[#mice + 1] = { name = L["CLICKCAST_MOUSE_" .. i], value = tostring(i) } end
    -- Aucun, chaque modificateur, puis les combinaisons (noms composés des libellés existants).
    local modifiers = { { name = L.CLICKCAST_MODIFIER_NONE, value = "none" } }
    local labels = { alt = L.CLICKCAST_MODIFIER_ALT, ctrl = L.CLICKCAST_MODIFIER_CTRL, shift = L.CLICKCAST_MODIFIER_SHIFT }
    for _, combo in ipairs({ "shift", "ctrl", "alt", "ctrl-shift", "alt-shift", "alt-ctrl", "alt-ctrl-shift" }) do
        local names = {}
        for _, part in ipairs(MODIFIER_ORDER) do
            if ("-" .. combo .. "-"):find("-" .. part .. "-", 1, true) then names[#names + 1] = labels[part] end
        end
        modifiers[#modifiers + 1] = { name = table.concat(names, " + "), value = combo }
    end
    local kinds = {
        { name = L.CLICKCAST_KIND_SPELL, value = "spell" }, { name = L.CLICKCAST_KIND_MACRO, value = "macro" },
        { name = L.CLICKCAST_KIND_ITEM, value = "item" }, { name = L.CLICKCAST_KIND_TRINKET1, value = "trinket1" },
        { name = L.CLICKCAST_KIND_TRINKET2, value = "trinket2" },
    }
    for i, key in ipairs(BINDING_KEYS) do
        if i % 8 == 1 then o:Tab(string.format("%d - %d", i, i + 7)) end   -- 8 liaisons par onglet
        local prefix = "bindings." .. key .. "."
        local warning
        local function Warn()
            if warning then warning:SetText(ClickCast.Warning(self.db.bindings[key]) or "") end
        end
        o:Title(string.format(L.CLICKCAST_BINDING, i))
        o:Dropdown(prefix .. "kind", L.CLICKCAST_KIND, kinds, 36, Warn)
        local box = o:EditBox(prefix .. "spell", L.CLICKCAST_SPELL, 1, 36)
        box:HookScript("OnTextChanged", Warn)
        o.layout:Hint(L.CLICKCAST_SPELL_HINT)
        ClickCast.AcceptDrop(box, function(text) o:Setter(prefix .. "spell")(text) box:SetText(text) end)
        warning = o:Note(" ", 36)
        warning:SetTextColor(1, 0.5, 0.25)
        o.layout.refreshers[#o.layout.refreshers + 1] = Warn
        o:Dropdown(prefix .. "mouse", L.CLICKCAST_MOUSE, mice, 36)
        o:Dropdown(prefix .. "modifier", L.CLICKCAST_MODIFIER, modifiers, 36)
        KeyButton(o, prefix .. "key")
        o:Check(prefix .. "oocOnly", L.OPT_GF_G_CC_OOC, 36)
    end
end

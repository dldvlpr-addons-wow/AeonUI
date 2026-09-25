-- Modules/GroupFinder.lua
-- Outil de recherche de groupe (LFGList) : inscription en un clic et note de candidature
-- mémorisée. Le dialogue Blizzard n'est pas validé sur Forever : tout est derrière Attach(),
-- et sans dialogue le module reste silencieux.
--   * inscription rapide : quand le dialogue de candidature s'ouvre avec un seul rôle
--     coché, on clique « S'inscrire » à sa place (Maj enfoncée = pas d'auto-clic) ;
--   * note persistante : le texte de la dernière candidature est pré-rempli.
local _, NS = ...
local L = NS.L

local GroupFinder = NS.Modules:Register("groupfinder", {
    titleKey = "LFG_TITLE",
    descKey = "LFG_DESC",
    defaults = {
        enabled = false,
        quickSignup = true,
        persistNote = false,
        note = "",
    },
})

local active = false
local attached = false

local ROLE_BUTTONS = { "TankButton", "HealerButton", "DamagerButton" }

local function Dialog() return _G.LFGListApplicationDialog end

local function NoteBox(dialog)
    if dialog.Description and dialog.Description.EditBox then return dialog.Description.EditBox end
    return _G.LFGListApplicationDialogDescription
end

--- Un seul rôle coché = intention sans ambiguïté ; sinon c'est au joueur de choisir.
function GroupFinder.CheckedRoles(dialog)
    local count = 0
    for _, name in ipairs(ROLE_BUTTONS) do
        local button = dialog[name]
        if button and button.CheckButton and button:IsShown() and button.CheckButton:GetChecked() then
            count = count + 1
        end
    end
    return count
end

local function SignUp(dialog)
    local button = dialog.SignUpButton
    if active and not NS.InCombat() and dialog:IsShown() and button and button:IsEnabled() then button:Click() end
end

local function WantsSignUp(dialog)
    local db = GroupFinder.db
    return db.quickSignup and not IsShiftKeyDown() and GroupFinder.CheckedRoles(dialog) == 1
end

-- Avec LFGListApplicationDialog_Show, le clic part dans son post-hook : dialogue rempli et
-- toujours dans le double-clic du joueur (un clic différé peut être refusé : ADDON_ACTION_FORBIDDEN).
local function OnDialogFilled(dialog)
    if active and WantsSignUp(dialog) then SignUp(dialog) end
end

local function OnDialogShown(dialog)
    if not active then return end
    local db = GroupFinder.db
    local box = NoteBox(dialog)
    if db.persistNote and db.note ~= "" and box then box:SetText(db.note) end
    if _G.LFGListApplicationDialog_Show or not WantsSignUp(dialog) then return end
    -- Repli sans la fonction Blizzard : une frame plus tard, le dialogue est rempli après OnShow.
    C_Timer.After(0, function() SignUp(dialog) end)
end

local function RememberNote()
    if not active or not GroupFinder.db.persistNote then return end
    local box = NoteBox(Dialog())
    if box then GroupFinder.db.note = box:GetText() or "" end
end

--- Pose les hooks une seule fois. false si le dialogue n'existe pas (encore).
local function Attach()
    if attached then return true end
    local dialog = Dialog()
    if not dialog then return false end
    dialog:HookScript("OnShow", OnDialogShown)
    if _G.LFGListApplicationDialog_Show then hooksecurefunc("LFGListApplicationDialog_Show", OnDialogFilled) end
    if dialog.SignUpButton then dialog.SignUpButton:HookScript("OnClick", RememberNote) end
    attached = true
    return true
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function()
    if Attach() then events:UnregisterAllEvents() end
end)

function GroupFinder:OnEnable()
    active = true
    -- Le dialogue arrive avec Blizzard_LookingForGroupUI, chargé à la demande.
    if not Attach() then NS.RegisterEventSafe(events, "ADDON_LOADED") end
end

function GroupFinder:OnDisable()
    active = false
    events:UnregisterAllEvents()
end

function GroupFinder:BuildOptions(o)
    o:Check("quickSignup", L.OPT_LFG_QUICK)
    o:Hint(L.OPT_LFG_QUICK_HINT)
    o:Check("persistNote", L.OPT_LFG_NOTE)
    o:EditBox("note", L.OPT_LFG_NOTE_TEXT, 2)
end

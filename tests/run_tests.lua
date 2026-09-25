-- tests/run_tests.lua
-- Suite headless : lua tests/run_tests.lua (depuis la racine du dépôt).
-- Charge l'addon dans l'ordre du .toc avec le même vararg (addonName, ns) que le client,
-- puis exécute chaque fichier tests/test_*.lua avec la boîte à outils T.

unpack = unpack or table.unpack   -- client = Lua 5.1, machine de dev = 5.4+

package.path = "tests/?.lua;" .. package.path
require("wow_mock")

--------------------------------------------------------------------------------
-- Chargement dans l'ordre du .toc
--------------------------------------------------------------------------------

local NS = {}
for raw in io.lines("AeonUI.toc") do
    local line = raw:gsub("\r", ""):gsub("%s+$", "")
    if line:match("%.lua$") then
        local chunk = assert(loadfile((line:gsub("\\", "/"))))
        chunk("AeonUI", NS)
    end
end

Mock.FireEvent("ADDON_LOADED", "AeonUI")
Mock.FireEvent("PLAYER_LOGIN")
Mock.FireEvent("PLAYER_ENTERING_WORLD")

--------------------------------------------------------------------------------
-- Boîte à outils
--------------------------------------------------------------------------------

local T = { NS = NS, L = NS.L, passed = 0, failed = 0 }

function T.test(name, fn)
    Mock.printed = {}
    Mock.sounds = {}
    local ok, err = xpcall(fn, debug.traceback)
    if ok then
        T.passed = T.passed + 1
    else
        T.failed = T.failed + 1
        io.write("FAIL ", name, "\n", tostring(err), "\n")
    end
end

function T.eq(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s : attendu %s, obtenu %s", message or "valeur",
            tostring(expected), tostring(actual)), 2)
    end
end

function T.truthy(value, message)
    if not value then error((message or "attendu vrai") .. " (obtenu " .. tostring(value) .. ")", 2) end
end

--- Remet l'état de jeu simulé à zéro entre deux tests.
function T.reset()
    Mock.combat = false
    Mock.units = { player = { guid = "Player-1", name = "Testeur", class = "MAGE", isPlayer = true,
                              health = 100, healthMax = 100 } }
    Mock.instanceType = "none"
    Mock.buffs, Mock.knownSpells = {}, {}
    Mock.bags = { [0] = {}, {}, {}, {}, {} }
    Mock.used, Mock.repairs, Mock.looted, Mock.questLog, Mock.chat = {}, {}, {}, {}, {}
    Mock.durability, Mock.equipped = {}, {}
    Mock.secret = {}
    Mock.resting, Mock.shift, Mock.altDown, Mock.inRaid = false, false, false, false
    Mock.groupSize = 0
    Mock.roles = {}
    Mock.merchantOpen = false
    Mock.popups = {}
    Mock.namePlates = {}
    Mock.shapeshiftForm, Mock.formID = 0, nil
    Mock.mainHandEnchant = false
    Mock.debuffs = {}
    Mock.addonEnableState, Mock.addonArgOrder = 2, 1
    Mock.editMode = { layouts = { layouts = {}, activeLayout = 1 }, added = {} }
    Mock.cooldownLayouts = { created = {}, active = nil, saved = 0, exportable = "CDM-BLOB" }
    Mock.loadedAddons = {}
    Mock.screen = { width = 1920, height = 1080 }
    Mock.auraContainer = false
    Mock.zoneText, Mock.pvpType, Mock.mapID, Mock.mapPosition = nil, nil, nil, nil
    Mock.xp, Mock.watchedFaction = { cur = 250, max = 1000, rested = 100 }, nil
    ObjectiveTrackerFrame.isCollapsed = nil
    NS.auraContainerProbe = nil
    Mock.namePlates = {}
    Mock.inRaid = false
    Mock.overrideBindings, Mock.attributeDrivers = {}, {}
    Mock.actionCooldown, _G.C_ActionBar = { start = 0, duration = 0 }, nil
    -- /aeon uninstall rend l'échelle dans tous les profils : l'état par défaut (pixel perfect) revient.
    if NS.db and NS.db.theme and (NS.db.theme.pixelPerfect ~= true or NS.db.theme.uiScale ~= 1) then
        NS.db.theme.pixelPerfect, NS.db.theme.uiScale = true, 1
        NS.Pixel.queued = false
        NS.Pixel:Apply()
    end
end

--------------------------------------------------------------------------------
-- Exécution
--------------------------------------------------------------------------------

local FILES = {
    "tests/test_core.lua", "tests/test_pixel.lua", "tests/test_movers.lua", "tests/test_topbar.lua", "tests/test_automation.lua",
    "tests/test_reminders.lua", "tests/test_modules.lua", "tests/test_config.lua",
    "tests/test_setup.lua", "tests/test_unitframes.lua", "tests/test_nameplateframes.lua", "tests/test_groupframes.lua", "tests/test_actionbars.lua", "tests/test_minimap.lua", "tests/test_chat.lua", "tests/test_databars.lua", "tests/test_questtracker.lua", "tests/test_install.lua", "tests/test_blizzardframes.lua",
    "tests/test_elvui_parity.lua",
    "tests/test_midnight.lua",
    "tests/test_text_filters.lua",
    "tests/test_group_indicators.lua",
    "tests/test_style_filters.lua",
    "tests/test_data_panels.lua",
    "tests/test_chat_loot.lua",
    "tests/test_raid.lua",
    "tests/test_bags.lua",
    "tests/test_transverse.lua",
    "tests/test_options_window.lua",
    "tests/test_profiles.lua",
    "tests/test_resourcebars.lua",
    "tests/test_raidcooldowns.lua",
    "tests/test_quickdraw.lua",
    "tests/test_skinwindows.lua",
}
for _, file in ipairs(FILES) do
    T.reset()
    assert(loadfile(file))(T)
end

io.write(string.format("%d ok, %d échec(s)\n", T.passed, T.failed))
os.exit(T.failed == 0 and 0 or 1)

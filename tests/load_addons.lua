-- tests/load_addons.lua
-- Charge le cœur puis les addons AeonUI_* dans l'ordre du client : fichiers du cœur,
-- ADDON_LOADED "AeonUI", fichiers des enfants, puis connexion. `afterFile` est appelé après chaque fichier.
local CHILD_ADDONS = {
    "AeonUI_Bags", "AeonUI_ActionBars", "AeonUI_UnitFrames", "AeonUI_GroupFrames",
    "AeonUI_Nameplates", "AeonUI_Chat", "AeonUI_Minimap", "AeonUI_QuestTracker",
}

local function LoadToc(folder, toc, NS, afterFile)
    for raw in io.lines(folder .. toc) do
        local line = raw:gsub("\r", ""):gsub("%s+$", "")
        if line:match("%.lua$") then
            assert(loadfile(folder .. line:gsub("\\", "/")))("AeonUI", NS)
            if afterFile then afterFile() end
        end
    end
end

return function(NS, afterFile)
    LoadToc("", "AeonUI.toc", NS, afterFile)
    Mock.FireEvent("ADDON_LOADED", "AeonUI")
    for _, name in ipairs(CHILD_ADDONS) do
        LoadToc(name .. "/", name .. ".toc", NS, afterFile)
        Mock.FireEvent("ADDON_LOADED", name)
    end
    Mock.FireEvent("PLAYER_LOGIN")
    Mock.FireEvent("PLAYER_ENTERING_WORLD")
end

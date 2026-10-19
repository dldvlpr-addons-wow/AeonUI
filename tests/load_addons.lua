-- tests/load_addons.lua
-- Charge le cœur puis les addons MuscaUI_* dans l'ordre du client : fichiers du cœur,
-- ADDON_LOADED "MuscaUI", fichiers des enfants, puis connexion. `afterFile` est appelé après chaque fichier.
local CHILD_ADDONS = {
    "MuscaUI_Bags", "MuscaUI_ActionBars", "MuscaUI_UnitFrames", "MuscaUI_GroupFrames",
    "MuscaUI_Nameplates", "MuscaUI_Chat", "MuscaUI_Minimap", "MuscaUI_QuestTracker",
}

local function LoadToc(folder, toc, NS, afterFile)
    for raw in io.lines(folder .. toc) do
        local line = raw:gsub("\r", ""):gsub("%s+$", "")
        if line:match("%.lua$") then
            assert(loadfile(folder .. line:gsub("\\", "/")))("MuscaUI", NS)
            if afterFile then afterFile() end
        end
    end
end

return function(NS, afterFile)
    LoadToc("", "MuscaUI.toc", NS, afterFile)
    Mock.FireEvent("ADDON_LOADED", "MuscaUI")
    for _, name in ipairs(CHILD_ADDONS) do
        LoadToc(name .. "/", name .. ".toc", NS, afterFile)
        Mock.FireEvent("ADDON_LOADED", name)
    end
    Mock.FireEvent("PLAYER_LOGIN")
    Mock.FireEvent("PLAYER_ENTERING_WORLD")
end

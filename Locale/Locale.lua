-- Locale/Locale.lua : résolution de la langue. Chargé après les traductions.
-- NS.L est rempli sur place, jamais remplacé : les modules en gardent une référence
-- locale dès le chargement.
local _, NS = ...

NS.locales = NS.locales or {}
NS.L = NS.L or {}

-- Nom écrit dans sa propre langue : qui cherche sa langue ne lit pas forcément l'actuelle.
NS.LOCALE_ORDER = {
    { code = "enUS", name = "English" },
    { code = "frFR", name = "Français" },
    { code = "deDE", name = "Deutsch" },
    { code = "esES", name = "Español (España)" },
    { code = "esMX", name = "Español (México)" },
    { code = "itIT", name = "Italiano" },
    { code = "ptBR", name = "Português (Brasil)" },
    { code = "ruRU", name = "Русский" },
    { code = "koKR", name = "한국어" },
    { code = "zhCN", name = "简体中文" },
    { code = "zhTW", name = "繁體中文" },
}

function NS.ClientLocale()
    local code = GetLocale and GetLocale() or "enUS"
    return NS.locales[code] and code or "enUS"
end

--- Applique une langue. `code` vaut "auto" (ou nil) pour suivre le client.
-- enUS sert de base : une clé non traduite reste lisible au lieu d'afficher nil.
function NS.SetLocale(code)
    if not code or code == "auto" then code = NS.ClientLocale() end
    if not NS.locales[code] then code = "enUS" end
    for key in pairs(NS.L) do NS.L[key] = nil end
    for key, value in pairs(NS.locales.enUS) do NS.L[key] = value end
    if code ~= "enUS" then
        for key, value in pairs(NS.locales[code]) do NS.L[key] = value end
    end
    NS.activeLocale = code
    -- Les modules déjà enregistrés gardent des libellés copiés : les retraduire.
    if NS.Modules then
        for _, module in ipairs(NS.Modules:List()) do
            if module.titleKey then module.title = NS.L[module.titleKey] end
            if module.descKey then module.description = NS.L[module.descKey] end
        end
    end
    return code
end

-- Langue du client au chargement ; Core.lua réapplique le choix sauvegardé à ADDON_LOADED.
NS.SetLocale("auto")

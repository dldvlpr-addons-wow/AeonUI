-- tests/test_pixel.lua
local T = ...
local NS, test, eq, truthy, reset = T.NS, T.test, T.eq, T.truthy, T.reset
local Pixel = NS.Pixel

local function approx(a, b, message)
    if math.abs(a - b) > 0.0001 then
        error(string.format("%s : attendu %.5f, obtenu %.5f", message or "valeur", b, a), 2)
    end
end

test("pixel : multiplicateur 1080p et 1440p à l'échelle 1", function()
    reset()
    UIParent:SetScale(1)
    Mock.screen = { width = 1920, height = 1080 }
    Pixel:Update()
    approx(Pixel.mult, 768 / 1080, "1080p")
    Mock.screen = { width = 2560, height = 1440 }
    Pixel:Update()
    approx(Pixel.mult, 768 / 1440, "1440p")
end)

test("pixel : Scale arrondit au pixel et ne rend jamais 0", function()
    reset()
    Mock.screen = { width = 1920, height = 1080 }
    UIParent:SetScale(768 / 1080)
    Pixel:Update()
    approx(Pixel.mult, 1, "à l'échelle pixel perfect, une unité = un pixel")
    eq(Pixel:Scale(0), 0)
    approx(Pixel:Scale(1), 1, "1 px")
    approx(Pixel:Scale(0.3), 1, "jamais 0 pour une valeur positive")
    approx(Pixel:Scale(-0.3), -1, "jamais 0 pour une valeur négative")
    approx(Pixel:Scale(2.6), 3, "arrondi au plus proche")
    UIParent:SetScale(1)
    Pixel:Update()
    approx(Pixel:Scale(1), Pixel.mult, "Scale(1) = mult")
end)

test("pixel : Apply change l'échelle d'UIParent seulement si pixelPerfect, et la rend", function()
    reset()
    Mock.screen = { width = 1920, height = 1080 }
    UIParent:SetScale(1)
    Pixel.originalScale = nil
    NS.db.theme.pixelPerfect = false
    Pixel:Apply()
    approx(UIParent:GetScale(), 1, "désactivé : échelle intacte")
    NS.db.theme.pixelPerfect = true
    Pixel:Apply()
    approx(UIParent:GetScale(), 768 / 1080, "activé : échelle pixel perfect")
    NS.db.theme.pixelPerfect = false
    Pixel:Apply()
    approx(UIParent:GetScale(), 1, "désactivé à nouveau : échelle d'origine rendue")
    eq(Pixel.originalScale, nil)
end)

test("pixel : uiScale multiplie la base, avec ou sans pixel perfect, borné, rendu à 1", function()
    reset()
    Mock.screen = { width = 1920, height = 1080 }
    UIParent:SetScale(0.8)
    Pixel.originalScale = nil
    NS.db.theme.pixelPerfect = false
    NS.db.theme.uiScale = 1.25
    Pixel:Apply()
    approx(UIParent:GetScale(), 1, "sans pixel perfect : échelle du jeu × 1,25")
    NS.db.theme.pixelPerfect = true
    Pixel:Apply()
    approx(UIParent:GetScale(), 768 / 1080 * 1.25, "pixel perfect × 1,25")
    NS.db.theme.uiScale = 9
    Pixel:Apply()
    approx(UIParent:GetScale(), 768 / 1080 * 1.5, "multiplicateur borné à 1,5")
    NS.db.theme.pixelPerfect = false
    NS.db.theme.uiScale = 1
    Pixel:Apply()
    approx(UIParent:GetScale(), 0.8, "tout rendu : échelle d'origine")
    eq(Pixel.originalScale, nil)
end)

test("pixel : Apply borne l'échelle et attend la fin du combat", function()
    reset()
    Mock.screen = { width = 1024, height = 400 }   -- 768/400 = 1.92 > 1.5
    UIParent:SetScale(1)
    Pixel.originalScale = nil
    NS.db.theme.pixelPerfect = true
    Mock.SetCombat(true)
    Pixel:Apply()
    approx(UIParent:GetScale(), 1, "en combat : rien tout de suite")
    Mock.SetCombat(false)
    approx(UIParent:GetScale(), 1.5, "à la sortie du combat : échelle bornée")
    NS.db.theme.pixelPerfect = true
    Mock.screen = { width = 1920, height = 1080 }
    Pixel:Apply()
    approx(UIParent:GetScale(), 768 / 1080, "état d'après connexion rétabli")
end)

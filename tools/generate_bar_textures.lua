-- tools/generate_bar_textures.lua
-- Textures de barre d'AeonUI (Media/Bars/*.tga), dessinées ici pixel par pixel : aucun média tiers.
-- Niveaux de gris sur fond blanc, teintés en jeu par SetStatusBarColor. TGA 32 bits non compressé,
-- origine en haut à gauche, 256 x 32 (puissances de deux, exigées par le client).
-- Usage, depuis la racine du dépôt : lua tools/generate_bar_textures.lua
local WIDTH, HEIGHT = 256, 32

-- Luminosité (0 à 1) du pixel (x, y), y = 0 en haut.
local SHADES = {
    Smooth = function(_, y) return 1 - 0.28 * y / (HEIGHT - 1) end,
    Gloss = function(_, y)
        if y < HEIGHT / 2 then return 1 - 0.15 * y / (HEIGHT / 2) end
        return 0.7 + 0.08 * (y - HEIGHT / 2) / (HEIGHT / 2)
    end,
    Stripes = function(x, y)
        local base = 0.95 - 0.12 * y / (HEIGHT - 1)
        return ((x + y) % 8 < 3) and base - 0.1 or base
    end,
    Soft = function(_, y)
        local t = y / (HEIGHT - 1)
        return 0.78 + 0.22 * math.sin(math.pi * t)
    end,
}

local function Byte(v) return math.floor(math.max(0, math.min(1, v)) * 255 + 0.5) end

local function Write(path, shade)
    local header = string.char(0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        WIDTH % 256, math.floor(WIDTH / 256), HEIGHT % 256, math.floor(HEIGHT / 256), 32, 0x28)
    local rows = {}
    for y = 0, HEIGHT - 1 do
        local row = {}
        for x = 0, WIDTH - 1 do
            local v = Byte(shade(x, y))
            row[#row + 1] = string.char(v, v, v, 255)   -- BGRA
        end
        rows[#rows + 1] = table.concat(row)
    end
    local file = assert(io.open(path, "wb"))
    file:write(header, table.concat(rows))
    file:close()
end

for name, shade in pairs(SHADES) do
    Write("Media/Bars/" .. name .. ".tga", shade)
    print("Media/Bars/" .. name .. ".tga")
end

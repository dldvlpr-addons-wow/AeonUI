-- AeonUI_Chat/Chat.lua
-- Chat AeonUI : fenêtres de chat habillées (fond au thème, police du thème, onglets plats,
-- boutons latéraux cachés, sans fondu), URL cliquables, copie du chat, noms de canaux courts,
-- couleur de classe partout, horodatage, zone de saisie en haut ou en bas. Historique rejoué au
-- /reload, mots-clés surlignés avec son, anti-spam tolérant (texte normalisé).
--
-- Historique : lignes finales de chaque fenêtre dans NS.global.chatHistory (compte entier).
-- Exclu du miroir CVar (limité, Database:MirrorTable) ; la table hôte le garde.
-- Midnight : un message secret (rencontre) passe tel quel, sans transformation ni mémoire.
--
-- Fenêtres : ChatFrame1 à gauche et la première fenêtre détachée à droite, chacune adoptée sur
-- un mover (/aeon unlock) avec sa taille dans les options ; Edit Mode et le glissé d'onglet ne les
-- déplacent plus tant que l'option est active.
-- Les textes passent par un enrobage d'AddMessage par fenêtre (URL, canaux courts) : hors
-- combat ou pas, rien de protégé ici. Cède aux addons de la liste yieldsTo.
local NS = AeonUI
local L = NS.L
local Media = NS.Media

local Chat = NS.Modules:Register("chat", {
    titleKey = "CHAT_TITLE",
    descKey = "CHAT_DESC",
    yieldsTo = { "Prat-3.0", "Chatter" },
    defaults = {
        enabled = false,
        skin = true,
        fontSize = 12,
        hideButtons = true,
        flatTabs = true,
        noFade = true,
        fadeTime = 120,           -- secondes avant qu'une ligne s'estompe (fondu actif)
        maxLines = 1000,
        urls = true,
        copy = true,
        shortChannels = true,
        classColors = true,
        timestamps = "none",      -- "none" | "%H:%M " | "%H:%M:%S "
        editBoxTop = false,
        background = { r = 0.05, g = 0.06, b = 0.08, a = 0.6 },   -- fond des fenêtres (couleur + opacité)
        backgroundTexture = "",   -- texture du fond (Media:StatusBarChoices), teintée par `background` ; "" : plat
        hideScrollBar = false,    -- barre de défilement et bouton « vers le bas » cachés (molette gardée)
        history = true, historyLines = 100,        -- lignes rejouées au /reload, par fenêtre
        keywords = "",                             -- mots-clés séparés par des virgules
        keywordName = true,                        -- ton nom compte comme mot-clé
        keywordSound = true,
        keywordSoundFile = "",                     -- son importé, sinon celui des chuchotements
        antiSpam = false, spamWindow = 60,         -- même message du même auteur dans la fenêtre (s) : caché
        tabFontSize = 12,                          -- onglets plats : taille, couleur de l'onglet actif, soulignement
        tabActiveColor = { r = 0.25, g = 0.66, b = 0.96 },
        tabUnderline = true,
        sidebar = "none",                          -- barre de raccourcis : "none", "left", "right" de la fenêtre 1
        sidebarButtons = "copy, friends, channels, options",   -- ordre des boutons (liste libre)
        windows = true,                            -- fenêtre 1 à gauche, fenêtre détachée à droite, sur movers
        leftWidth = 430, leftHeight = 180,
        rightWidth = 320, rightHeight = 160,       -- AddonPlacements.POINTS.chatRight
    },
})

local SIDE_BUTTONS = { "ChatFrameMenuButton", "ChatFrameChannelButton", "ChatFrameToggleVoiceDeafenButton",
                       "ChatFrameToggleVoiceMuteButton", "QuickJoinToastButton", "ChatFrameToggleButton" }
local TAB_TEXTURES = { "Left", "Middle", "Right", "SelectedLeft", "SelectedMiddle", "SelectedRight",
                       "HighlightLeft", "HighlightMiddle", "HighlightRight", "ActiveLeft", "ActiveMiddle", "ActiveRight" }
local EDITBOX_TEXTURES = { "Left", "Mid", "Right", "FocusLeft", "FocusMid", "FocusRight" }
local URL_COLOR = "|cff3399ff"
local URL_PATTERNS = { "%f[%S](https?://%S+)", "%f[%S](www%.[%w_%-]+%.%S+)" }

local KEYWORD_SOUND = 3081          -- SOUNDKIT.TELL_MESSAGE
local KEYWORD_SOUND_THROTTLE = 5
local HIGHLIGHT = "|cffff7f3f"
local KEYWORD_EVENTS = { "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_CHANNEL", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
                         "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
                         "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER" }
local SPAM_EVENTS = { CHAT_MSG_SAY = true, CHAT_MSG_YELL = true, CHAT_MSG_CHANNEL = true }

local active = false
local replaying = false     -- rejeu de l'historique : ces lignes ne sont pas remémorisées
local frames = {}          -- [ChatFrame] = { backdrop, original = { font = {…}, addMessage } }
local hooked = false
local copyFrame
-- Couleurs de classe d'origine du personnage, gardées dans la base : un /reload relirait
-- sinon les valeurs déjà forcées par AeonUI et l'origine serait perdue.
local function ClassColorBackup()
    return NS.global.chatClassColors[NS.Database.CharacterKey()]
end

--------------------------------------------------------------------------------
-- Transformations de texte (pures, testables)
--------------------------------------------------------------------------------

--- Habille les URL d'un lien |Hurl:…|h cliquable.
function Chat.LinkURLs(text)
    if text:find("|Hurl:", 1, true) then return text end
    for _, pattern in ipairs(URL_PATTERNS) do
        text = text:gsub(pattern, function(url)
            local trailing = url:match("[%.,;:!%?%)]+$") or ""
            url = url:sub(1, #url - #trailing)
            return "|Hurl:" .. url .. "|h" .. URL_COLOR .. "[" .. url .. "]|r|h" .. trailing
        end)
    end
    return text
end

--- « [2. Commerce] » devient « [2] ».
function Chat.ShortenChannels(text)
    return (text:gsub("|Hchannel:([^|]+)|h%[(%d+)%.%s[^%]]+%]|h", "|Hchannel:%1|h[%2]|h"))
end

function Chat.Transform(text)
    local db = Chat.db
    if NS.IsSecret(text) or type(text) ~= "string" then return text end
    if db.shortChannels then text = Chat.ShortenChannels(text) end
    if db.urls then text = Chat.LinkURLs(text) end
    return text
end

--- Ligne de chat sans textures ni liens, pour la copie.
function Chat.CleanLine(text)
    text = text:gsub("|T[^|]*|t", ""):gsub("|A[^|]*|a", "")
    text = text:gsub("|H[^|]*|h([^|]*)|h", "%1")
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[^:|]*:", ""):gsub("|r", "")
    return text
end

--------------------------------------------------------------------------------
-- Historique
--------------------------------------------------------------------------------

--- Historique du personnage courant : chuchotements et guilde d'un personnage ne se rejouent
-- pas sur un autre.
local function History()
    NS.global.chatHistory = NS.global.chatHistory or {}
    local key = NS.Database.CharacterKey()
    NS.global.chatHistory[key] = NS.global.chatHistory[key] or {}
    return NS.global.chatHistory[key]
end

--- Mémorise une ligne affichée (texte final, couleur). Secret ou vide : rien.
function Chat.Remember(frame, text, r, g, b)
    local db = Chat.db
    if not db.history or NS.IsSecret(text) or type(text) ~= "string" or text == "" then return end
    if frame == _G.COMBATLOG then return end            -- journal de combat : trop de lignes
    if text:find("|K", 1, true) then return end          -- code BNet : valable pour la session seule
    local name = frame.GetName and frame:GetName()
    if not name then return end
    local history = History()
    local lines = history[name] or {}
    history[name] = lines
    if NS.IsSecret(r) or NS.IsSecret(g) or NS.IsSecret(b) then r, g, b = nil, nil, nil end
    lines[#lines + 1] = { text = text, r = r, g = g, b = b }
    local limit = math.max(0, tonumber(db.historyLines) or 100)
    while #lines > limit do table.remove(lines, 1) end   -- ponytail: décalage O(n), n ≤ 500
end

--- Rejoue l'historique de chaque fenêtre, une fois par session, sous un séparateur.
function Chat:ReplayHistory(frameList)
    if self.replayed or not self.db.history then return end
    self.replayed = true   -- une fois par session
    local history = History()
    replaying = true
    for _, frame in ipairs(frameList) do
        local lines = history[frame:GetName()]
        if lines and #lines > 0 then
            frame:AddMessage("|cff9d9d9d" .. L.CHAT_HISTORY_SEPARATOR .. "|r")
            for _, line in ipairs(lines) do frame:AddMessage(line.text, line.r, line.g, line.b) end
            frame:AddMessage("|cff9d9d9d" .. L.CHAT_HISTORY_END .. "|r")
        end
    end
    replaying = false
end

function Chat:ClearHistory()
    if NS.global.chatHistory then NS.global.chatHistory[NS.Database.CharacterKey()] = nil end
end

--------------------------------------------------------------------------------
-- Mots-clés et anti-spam (filtres de messages)
--------------------------------------------------------------------------------

--- Texte comparable : sans liens ni couleurs, minuscules, sans ponctuation ni espaces, lettres
-- répétées réduites (« Heeeelp !! » et « help » donnent la même clé).
function Chat.Normalize(text)
    text = Chat.CleanLine(text):lower()
    text = text:gsub("[%p%s%c]", "")
    local out, last = {}, nil
    for char in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do   -- caractère UTF-8
        if char ~= last then out[#out + 1] = char end
        last = char
    end
    return table.concat(out)
end

--- Mots-clés actifs (minuscules), nom du personnage compris sur option.
function Chat.Keywords()
    local list = {}
    for raw in (Chat.db.keywords or ""):gmatch("[^,]+") do
        local word = raw:match("^%s*(.-)%s*$"):lower()
        if word ~= "" then list[#list + 1] = word end
    end
    if Chat.db.keywordName then
        local name = UnitName("player")
        if not NS.IsSecret(name) and name then list[#list + 1] = name:lower() end
    end
    return list
end

--- Message surligné aux mots-clés trouvés, ou nil si aucun. Messages à liens : pas de surlignage
-- (les positions d'un lien ne se touchent pas), mais le mot-clé compte.
function Chat.HighlightKeywords(message, keywords)
    local lower = message:lower()
    local found = false
    for _, word in ipairs(keywords) do
        if lower:find(word, 1, true) then found = true break end
    end
    if not found then return nil end
    if message:find("|H", 1, true) then return message end
    local out, pos = {}, 1
    while pos <= #message do
        local first, last
        for _, word in ipairs(keywords) do
            local s, e = lower:find(word, pos, true)
            if s and (not first or s < first) then first, last = s, e end
        end
        if not first then break end
        out[#out + 1] = message:sub(pos, first - 1)
        out[#out + 1] = HIGHLIGHT .. message:sub(first, last) .. "|r"
        pos = last + 1
    end
    out[#out + 1] = message:sub(pos)
    return table.concat(out)
end

local spamSeen, spamCount = {}, 0     -- [auteur .. clé] = GetTime()
local decisions = {}                  -- [lineID] = { hide, message } : un message, plusieurs fenêtres
local decisionCount = 0
local lastSound = -1000

local function PlayKeywordSound()
    if not NS.PlayCustomSound(Chat.db.keywordSoundFile) then PlaySound(KEYWORD_SOUND, "Master") end
end

local function Decide(event, message, author, lineID)
    local db = Chat.db
    local shortAuthor = author:gsub("%-.*", "")
    local mine = shortAuthor == UnitName("player")
    if db.antiSpam and SPAM_EVENTS[event] and not mine then
        local key = author .. "\0" .. Chat.Normalize(message)
        local now = GetTime()
        local seen = spamSeen[key]
        if seen and now - seen < (tonumber(db.spamWindow) or 60) then return true end
        if not seen then spamCount = spamCount + 1 end
        spamSeen[key] = now
        if spamCount > 500 then spamSeen, spamCount = {}, 0 end   -- ponytail: purge brutale
    end
    if not mine then
        local keywords = Chat.Keywords()
        local highlighted = #keywords > 0 and Chat.HighlightKeywords(message, keywords)
        if highlighted then
            if db.keywordSound and GetTime() - lastSound >= KEYWORD_SOUND_THROTTLE then
                lastSound = GetTime()
                PlayKeywordSound()
            end
            return false, highlighted
        end
    end
    return false, nil
end

--- Filtre de messages : décision prise une fois par lineID, rejouée pour chaque fenêtre.
function Chat.MessageFilter(_, event, message, author, ...)
    if not active then return false end
    if NS.IsSecret(message) or NS.IsSecret(author) or type(message) ~= "string" or type(author) ~= "string" then
        return false
    end
    local lineID = select(9, ...)
    local decision = (not NS.IsSecret(lineID) and lineID ~= nil) and decisions[lineID] or nil
    if not decision then
        local hide, replaced = Decide(event, message, author, lineID)
        decision = { hide = hide, message = replaced }
        if not NS.IsSecret(lineID) and lineID ~= nil then
            decisions[lineID] = decision
            decisionCount = decisionCount + 1
            if decisionCount > 200 then decisions, decisionCount = { [lineID] = decision }, 1 end
        end
    end
    if decision.hide then return true end
    if decision.message then return false, decision.message, author, ... end
    return false
end

local filtersAdded = false
local function AddFilters()
    if filtersAdded then return end
    local add = _G.ChatFrame_AddMessageEventFilter
        or (_G.ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter)
    if not add then return end
    filtersAdded = true
    for _, event in ipairs(KEYWORD_EVENTS) do add(event, Chat.MessageFilter) end
end

--------------------------------------------------------------------------------
-- Habillage
--------------------------------------------------------------------------------

-- CHAT_FRAMES inclut les fenêtres temporaires (chuchotement : ChatFrame11 et au-delà).
local function Windows()
    local list, seen = {}, {}
    for _, name in ipairs(_G.CHAT_FRAMES or {}) do
        local frame = _G[name]
        if frame and not seen[frame] then seen[frame] = true list[#list + 1] = frame end
    end
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local frame = _G["ChatFrame" .. i]
        if frame and not seen[frame] then seen[frame] = true list[#list + 1] = frame end
    end
    return list
end

--------------------------------------------------------------------------------
-- Fenêtres gauche et droite : posées sur des movers (/aeon unlock), tailles des options
--------------------------------------------------------------------------------

local CHAT_MIN_WIDTH, CHAT_MIN_HEIGHT = 296, 120   -- bornes de redimensionnement du client

-- Cadre déjà posé sur le mover de droite, nil sinon.
local function ManagedRight()
    local entry = NS.Movers.adopted.chatRight
    return entry and entry.active and entry.frame or nil
end

--- Fenêtre de droite : celle déjà gérée si elle est toujours affichée et détachée du dock, sinon
-- la première fenêtre affichée et détachée, hors ChatFrame1 (fenêtres temporaires exclues).
function Chat.RightWindow()
    if not _G.GetChatWindowInfo then return nil end
    local max = (Constants and Constants.ChatFrameConstants and Constants.ChatFrameConstants.MaxChatWindows)
        or NUM_CHAT_WINDOWS or 10
    local current, first = ManagedRight(), nil
    for id = 2, max do
        local frame = _G["ChatFrame" .. id]
        local shown, _, docked = select(7, GetChatWindowInfo(id))
        if frame and shown and not docked then
            if frame == current then return frame end
            first = first or frame
        end
    end
    return first
end

local function PlaceWindow(key, frame, width, height, point, x, y)
    width, height = math.max(width, CHAT_MIN_WIDTH), math.max(height, CHAT_MIN_HEIGHT)
    frame:SetSize(width, height)
    -- Rappel du module : le mover reste rattaché au chat (clic droit, filtre de la barre d'outils).
    local holder = NS.Modules:Within("chat", function()
        return NS.Movers:Adopt(key, frame, L["MOVER_" .. key:upper()], point, x, y, point)
    end)
    holder:SetSize(width, height)
end

function Chat.ApplyWindows()
    local db = Chat.db
    local managed = active and db.windows
    if managed and _G.ChatFrame1 then
        PlaceWindow("chatLeft", ChatFrame1, db.leftWidth, db.leftHeight, "BOTTOMLEFT", 10, 40)
    else
        NS.Movers:Release("chatLeft")
    end
    local right = managed and Chat.RightWindow()
    if right then
        PlaceWindow("chatRight", right, db.rightWidth, db.rightHeight, "BOTTOMRIGHT", -10, 100)
    else
        NS.Movers:Release("chatRight")
    end
end

-- Redimensionnement à la main (bouton du chat, Edit Mode) : la taille devient celle des options.
-- Glisser l'onglet d'une fenêtre gérée la ramène sur son mover : la place vient de /aeon unlock.
local function OnWindowResized(frame)
    if not (active and Chat.db.windows) then return end
    local db = Chat.db
    if frame == ChatFrame1 or frame.isDocked then
        db.leftWidth, db.leftHeight = math.floor(ChatFrame1:GetWidth() + 0.5), math.floor(ChatFrame1:GetHeight() + 0.5)
    elseif frame == ManagedRight() then   -- pas une fenêtre qui vient d'être détachée
        db.rightWidth, db.rightHeight = math.floor(frame:GetWidth() + 0.5), math.floor(frame:GetHeight() + 0.5)
    end
    Chat.ApplyWindows()
end

local function SetTexturesAlpha(prefix, holder, suffixes, alpha)
    for _, suffix in ipairs(suffixes) do
        local texture = _G[prefix .. suffix] or (holder and holder[suffix])
        if texture and texture.SetAlpha then texture:SetAlpha(alpha) end
    end
end

local function Entry(frame)
    local entry = frames[frame]
    if entry then return entry end
    entry = { original = { font = { frame:GetFont() }, timeVisible = frame.GetTimeVisible and frame:GetTimeVisible() } }
    local bg, edges = Media:CreateBackdrop(frame)
    entry.backdrop = { bg = bg, edges = edges }
    entry.original.addMessage = frame.AddMessage
    frame.AddMessage = function(self, text, ...)
        if active then
            text = Chat.Transform(text)
            if not replaying then Chat.Remember(self, text, ...) end
        end
        return entry.original.addMessage(self, text, ...)
    end
    frames[frame] = entry
    return entry
end

local function TexturePath(key)
    if not key or key == "" then return nil end
    for _, choice in ipairs(Media:StatusBarChoices("")) do
        if choice.value == key then return choice.texture end
    end
end

local function ShowBackdrop(entry, shown, color, texture)
    local b = entry.backdrop
    local path = TexturePath(texture)
    if color and path then
        b.bg:SetTexture(path)
        b.bg:SetVertexColor(color.r, color.g, color.b, color.a or 1)
    elseif color then
        b.bg:SetVertexColor(1, 1, 1, 1)
        NS.SetSolidColor(b.bg, color.r, color.g, color.b, color.a or 1)
    end
    if shown then b.bg:Show() else b.bg:Hide() end
    for _, edge in pairs(b.edges or {}) do if shown then edge:Show() else edge:Hide() end end
end

local function SkinWindow(frame)
    local db, name = Chat.db, frame:GetName()
    local entry = Entry(frame)
    local index = name:match("ChatFrame(%d+)")
    ShowBackdrop(entry, db.skin, db.background, db.backgroundTexture)
    for _, key in ipairs({ "ScrollBar", "ScrollToBottomButton" }) do
        if db.hideScrollBar then NS.HideRegion(frame[key]) else NS.ShowRegion(frame[key]) end
    end
    if db.skin then
        SetTexturesAlpha(name, frame, CHAT_FRAME_TEXTURES or {}, 0)
        local path = Media:Font()
        frame:SetFont(path, db.fontSize, Media:Outline())
        if frame.SetClampRectInsets then frame:SetClampRectInsets(0, 0, 0, 0) end
    else
        SetTexturesAlpha(name, frame, CHAT_FRAME_TEXTURES or {}, 1)
        frame:SetFont(unpack(entry.original.font))
    end
    if frame.SetFading then frame:SetFading(not db.noFade) end
    if not db.noFade and frame.SetTimeVisible then frame:SetTimeVisible(db.fadeTime) end
    if frame.SetMaxLines and frame.GetMaxLines and frame:GetMaxLines() ~= db.maxLines then frame:SetMaxLines(db.maxLines) end

    local tab = _G[name .. "Tab"] or frame.Tab
    if tab then
        SetTexturesAlpha(name .. "Tab", tab, TAB_TEXTURES, db.flatTabs and 0 or 1)
    end
    local buttonFrame = _G[name .. "ButtonFrame"] or frame.buttonFrame
    if buttonFrame then
        if db.hideButtons then NS.HideRegion(buttonFrame) else NS.ShowRegion(buttonFrame) end
    end

    local editBox = frame.editBox or _G[name .. "EditBox"]
    if editBox then
        SetTexturesAlpha(name .. "EditBox", editBox, EDITBOX_TEXTURES, db.skin and 0 or 1)
        if db.skin and not entry.editBackdrop then
            local bg, edges = Media:CreateBackdrop(editBox)
            entry.editBackdrop = { bg = bg, edges = edges }
        end
        if entry.editBackdrop then ShowBackdrop({ backdrop = entry.editBackdrop }, db.skin) end
        if index == "1" then
            if not entry.original.editPoints then
                entry.original.editPoints = {}
                for i = 1, editBox:GetNumPoints() do entry.original.editPoints[i] = { editBox:GetPoint(i) } end
            end
            editBox:ClearAllPoints()
            if db.editBoxTop then
                editBox:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 24)
                editBox:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", 0, 24)
            else
                editBox:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, -4)
                editBox:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", 0, -4)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Onglets
--------------------------------------------------------------------------------

local TAB_INACTIVE = 0.65

local function SelectedFrame() return _G.SELECTED_CHAT_FRAME or _G.ChatFrame1 end

--- Onglet plat : couleur de l'onglet actif, soulignement ; rien sans onglets plats.
local function StyleTab(frame)
    local entry, name = frames[frame], frame:GetName()
    local tab = _G[name .. "Tab"] or frame.Tab
    if not (entry and tab) then return end
    local db = Chat.db
    local text = tab.Text or _G[name .. "TabText"]
    local styled = active and db.flatTabs
    local selected = frame == SelectedFrame()
    if styled and text then
        text:SetFont(Media:Font(), db.tabFontSize, Media:Outline())
        local color = db.tabActiveColor
        if selected then text:SetTextColor(color.r, color.g, color.b) else text:SetTextColor(TAB_INACTIVE, TAB_INACTIVE, TAB_INACTIVE) end
    end
    if styled and db.tabUnderline and not entry.tabUnderline then
        entry.tabUnderline = tab:CreateTexture(nil, "OVERLAY")
        entry.tabUnderline:SetHeight(2)
        entry.tabUnderline:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 4, 2)
        entry.tabUnderline:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -4, 2)
    end
    if entry.tabUnderline then
        local color = db.tabActiveColor
        NS.SetSolidColor(entry.tabUnderline, color.r, color.g, color.b, 1)
        entry.tabUnderline:SetShown(styled and db.tabUnderline and selected)
    end
end

function Chat.StyleTabs()
    for frame in pairs(frames) do StyleTab(frame) end
end

--------------------------------------------------------------------------------
-- Barre de raccourcis
--------------------------------------------------------------------------------

local SIDEBAR_SIZE = 20
local SIDEBAR_ACTIONS = {
    copy = { icon = "Interface\\Buttons\\UI-GuildButton-PublicNote-Up", label = "CHAT_SIDEBAR_COPY",
             run = function() Chat:CopyWindow(SelectedFrame()) end },
    friends = { icon = "Interface\\FriendsFrame\\UI-Toast-FriendOnlineIcon", label = "CHAT_SIDEBAR_FRIENDS",
                run = function() if _G.ToggleFriendsFrame then ToggleFriendsFrame() end end },
    channels = { icon = "Interface\\FriendsFrame\\UI-Toast-ChatInviteIcon", label = "CHAT_SIDEBAR_CHANNELS",
                 run = function() if _G.ToggleChannelFrame then ToggleChannelFrame() end end },
    options = { icon = "Interface\\Buttons\\UI-OptionsButton", label = "CHAT_SIDEBAR_OPTIONS",
                run = function() NS.OpenOptions("chat") end },
}
local sidebar

--- Actions de la liste, dans son ordre, inconnues et doublons écartés.
function Chat.SidebarActions(text)
    local list, seen = {}, {}
    for word in tostring(text or ""):lower():gmatch("%a+") do
        if SIDEBAR_ACTIONS[word] and not seen[word] then seen[word] = true list[#list + 1] = word end
    end
    return list
end

local function SidebarButton(index)
    sidebar.buttons = sidebar.buttons or {}
    local button = sidebar.buttons[index]
    if button then return button end
    button = CreateFrame("Button", nil, sidebar)
    button:SetSize(SIDEBAR_SIZE, SIDEBAR_SIZE)
    Media:CreateBackdrop(button)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("TOPLEFT", 2, -2)
    button.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    button:SetScript("OnClick", function(self) SIDEBAR_ACTIONS[self.action].run() end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L[SIDEBAR_ACTIONS[self.action].label])
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    sidebar.buttons[index] = button
    return button
end

local function ApplySidebar()
    local side, anchor = Chat.db.sidebar, _G.ChatFrame1
    if not active or side == "none" or not anchor then
        if sidebar then sidebar:Hide() end
        return
    end
    if not sidebar then sidebar = CreateFrame("Frame", "AeonUIChatSidebar", UIParent) end
    local actions = Chat.SidebarActions(Chat.db.sidebarButtons)
    sidebar:SetSize(SIDEBAR_SIZE, math.max(1, #actions * (SIDEBAR_SIZE + 2) - 2))
    sidebar:ClearAllPoints()
    if side == "left" then
        sidebar:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -4, 0)
    else
        sidebar:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 4, 0)
    end
    for index, action in ipairs(actions) do
        local button = SidebarButton(index)
        button.action = action
        button.icon:SetTexture(SIDEBAR_ACTIONS[action].icon)
        button:ClearAllPoints()
        button:SetPoint("TOP", sidebar, "TOP", 0, -(index - 1) * (SIDEBAR_SIZE + 2))
        button:Show()
    end
    for index = #actions + 1, #(sidebar.buttons or {}) do sidebar.buttons[index]:Hide() end
    sidebar:Show()
end

function Chat:GetSidebar() return sidebar end

local function ApplySideButtons()
    for _, name in ipairs(SIDE_BUTTONS) do
        if Chat.db.hideButtons then NS.HideRegion(name) else NS.ShowRegion(name) end
    end
end

local function ApplyClassColors()
    if not ChatTypeInfo then return end
    if Chat.db.classColors then
        local key = NS.Database.CharacterKey()
        local backup = NS.global.chatClassColors[key] or {}
        NS.global.chatClassColors[key] = backup
        for chatType, info in pairs(ChatTypeInfo) do
            if backup[chatType] == nil then backup[chatType] = info.colorNameByClass and true or false end
            if SetChatColorNameByClass then pcall(SetChatColorNameByClass, chatType, true) end
        end
    elseif ClassColorBackup() and SetChatColorNameByClass then
        for chatType, wasOn in pairs(ClassColorBackup()) do pcall(SetChatColorNameByClass, chatType, wasOn) end
        NS.global.chatClassColors[NS.Database.CharacterKey()] = nil
    end
end

local function ApplyTimestamps()
    if Chat.db.timestamps == "none" then
        if NS.CVars:IsChanged("showTimestamps") then NS.CVars:Restore("showTimestamps") end
    else
        NS.CVars:Set("showTimestamps", Chat.db.timestamps)
    end
end

--------------------------------------------------------------------------------
-- Copie du chat et URL
--------------------------------------------------------------------------------

local function CopyFrame()
    if copyFrame then return copyFrame end
    copyFrame = CreateFrame("Frame", "AeonUI_ChatCopy", UIParent)
    copyFrame:SetSize(560, 380)
    copyFrame:SetPoint("CENTER")
    copyFrame:SetFrameStrata("DIALOG")
    copyFrame:EnableMouse(true)
    copyFrame:SetMovable(true)
    copyFrame:RegisterForDrag("LeftButton")
    copyFrame:SetScript("OnDragStart", copyFrame.StartMoving)
    copyFrame:SetScript("OnDragStop", copyFrame.StopMovingOrSizing)
    Media:CreateBackdrop(copyFrame)
    copyFrame.title = Media:CreateText(copyFrame, "OVERLAY", 1)
    copyFrame.title:SetPoint("TOPLEFT", 10, -8)
    copyFrame.title:SetText(L.CHAT_COPY_TITLE)
    local close = CreateFrame("Button", nil, copyFrame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function() copyFrame:Hide() end)
    local scroll = CreateFrame("ScrollFrame", "AeonUI_ChatCopyScroll", copyFrame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 10, -30)
    scroll:SetPoint("BOTTOMRIGHT", -30, 10)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetWidth(510)
    -- Police posée à la main : l'interligne de ChatFontNormal décale le curseur du texte.
    edit:SetFont(Media:Font(), Chat.db.fontSize or 12, "")
    edit:SetScript("OnEscapePressed", function() copyFrame:Hide() end)
    scroll:SetScrollChild(edit)
    copyFrame.edit = edit
    tinsert(UISpecialFrames, "AeonUI_ChatCopy")
    return copyFrame
end

function Chat:ShowText(text)
    local frame = CopyFrame()
    frame.edit:SetText(text)
    frame:Show()
    frame.edit:HighlightText()
    frame.edit:SetFocus()
end

function Chat:CopyWindow(frame)
    if not frame.GetNumMessages then return end
    local lines = {}
    for i = 1, frame:GetNumMessages() do
        local text = frame:GetMessageInfo(i)
        if not NS.IsSecret(text) and text then lines[#lines + 1] = Chat.CleanLine(text) end
    end
    self:ShowText(table.concat(lines, "\n"))
end

local function CopyButton(frame)
    local entry = Entry(frame)
    if entry.copyButton then return entry.copyButton end
    local button = CreateFrame("Button", frame:GetName() .. "AeonUICopy", frame)
    button:SetSize(20, 20)
    button:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)
    button:SetAlpha(0)
    button.text = Media:CreateText(button, "OVERLAY", 2)
    button.text:SetPoint("CENTER")
    button.text:SetText("[c]")
    button:SetScript("OnClick", function() Chat:CopyWindow(frame) end)
    local function show() if active and Chat.db.copy then button:SetAlpha(1) end end
    local function hide() button:SetAlpha(0) end
    frame:HookScript("OnEnter", show)
    frame:HookScript("OnLeave", hide)
    button:SetScript("OnEnter", show)
    button:SetScript("OnLeave", hide)
    entry.copyButton = button
    return button
end

--------------------------------------------------------------------------------
-- Cycle de vie
--------------------------------------------------------------------------------

function Chat:Apply()
    for _, frame in ipairs(Windows()) do
        SkinWindow(frame)
        local button = CopyButton(frame)
        if self.db.copy and frame.GetNumMessages then button:Show() else button:Hide() end
    end
    ApplySideButtons()
    ApplyClassColors()
    ApplyTimestamps()
    Chat.StyleTabs()
    ApplySidebar()
    Chat.ApplyWindows()
end

local function Restore()
    for frame, entry in pairs(frames) do
        ShowBackdrop(entry, false)
        if entry.editBackdrop then ShowBackdrop({ backdrop = entry.editBackdrop }, false) end
        local name = frame:GetName()
        SetTexturesAlpha(name, frame, CHAT_FRAME_TEXTURES or {}, 1)
        SetTexturesAlpha(name .. "Tab", _G[name .. "Tab"] or frame.Tab, TAB_TEXTURES, 1)
        local editBox = frame.editBox or _G[name .. "EditBox"]
        if editBox then SetTexturesAlpha(name .. "EditBox", editBox, EDITBOX_TEXTURES, 1) end
        if editBox and entry.original.editPoints and #entry.original.editPoints > 0 then
            editBox:ClearAllPoints()
            for _, point in ipairs(entry.original.editPoints) do editBox:SetPoint(unpack(point)) end
        end
        frame:SetFont(unpack(entry.original.font))
        if frame.SetFading then frame:SetFading(true) end
        if entry.original.timeVisible and frame.SetTimeVisible then frame:SetTimeVisible(entry.original.timeVisible) end
        NS.ShowRegion(_G[name .. "ButtonFrame"] or frame.buttonFrame)
        NS.ShowRegion(frame.ScrollBar)
        NS.ShowRegion(frame.ScrollToBottomButton)
        if entry.copyButton then entry.copyButton:Hide() end
        if entry.tabUnderline then entry.tabUnderline:Hide() end
        local tabText = (_G[name .. "Tab"] or frame.Tab or {}).Text
        if tabText and tabText.SetFont then tabText:SetFont(unpack(entry.original.font)) end
    end
    for _, name in ipairs(SIDE_BUTTONS) do NS.ShowRegion(name) end
    ApplySidebar()
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function()
    if active then Chat:Apply() end
end)

function Chat:OnEnable()
    active = true
    if not hooked then
        hooked = true
        hooksecurefunc("SetItemRef", function(link)
            if active and type(link) == "string" and link:sub(1, 4) == "url:" then Chat:ShowText(link:sub(5)) end
        end)
        if _G.FCF_OpenTemporaryWindow then hooksecurefunc("FCF_OpenTemporaryWindow", function() if active then Chat:Apply() end end) end
        -- Changement d'onglet, et Blizzard qui recolore les onglets : on repasse derrière.
        for _, name in ipairs({ "FCF_Tab_OnClick", "FCFTab_UpdateColors" }) do
            if _G[name] then hooksecurefunc(name, function() if active then Chat.StyleTabs() end end) end
        end
        if _G.FCF_SavePositionAndDimensions then hooksecurefunc("FCF_SavePositionAndDimensions", OnWindowResized) end
        if _G.ChatFrame1 and ChatFrame1.EditMode_OnResized then
            hooksecurefunc(ChatFrame1, "EditMode_OnResized", function() OnWindowResized(ChatFrame1) end)
        end
    end
    self:Apply()
    AddFilters()
    self:ReplayHistory(Windows())
    NS.RegisterEventSafe(events, "UPDATE_CHAT_WINDOWS")
    NS.RegisterEventSafe(events, "UPDATE_FLOATING_CHAT_WINDOWS")
    -- Edit Mode repose ChatFrame1 (taille comprise) au chargement de sa disposition.
    NS.RegisterEventSafe(events, "EDIT_MODE_LAYOUTS_UPDATED")
    NS.RegisterEventSafe(events, "PLAYER_ENTERING_WORLD")
end

function Chat:OnDisable()
    active = false
    events:UnregisterAllEvents()
    Chat.ApplyWindows()
    Restore()
    if ClassColorBackup() then
        local keep = self.db.classColors
        self.db.classColors = false
        ApplyClassColors()
        self.db.classColors = keep
    end
    if NS.CVars:IsChanged("showTimestamps") then NS.CVars:Restore("showTimestamps") end
end

function Chat:OnRefresh()
    if active then self:Apply() end
end

NS:On("THEME_CHANGED", function() if active then Chat:Apply() end end)

--------------------------------------------------------------------------------
-- Options
--------------------------------------------------------------------------------

function Chat:BuildOptions(o)
    o:Check("skin", L.OPT_CHAT_SKIN)
    o.layout:Color(L.OPT_CHAT_BACKGROUND, function() return o:DB().background end,
        function() Chat:OnRefresh() end, 20)
    o:Advanced()
    o:Dropdown("backgroundTexture", L.OPT_CHAT_BACKGROUND_TEXTURE, function() return Media:StatusBarChoices(L.OPT_CHAT_TEXTURE_FLAT) end, 36)
    o:EndAdvanced()
    o:Check("hideScrollBar", L.OPT_CHAT_HIDE_SCROLLBAR)
    o:Slider("fontSize", L.OPT_CHAT_FONT_SIZE, 9, 20, 1)
    o:Check("flatTabs", L.OPT_CHAT_FLAT_TABS)
    o:Advanced()
    o:Slider("tabFontSize", L.OPT_CHAT_TAB_FONT_SIZE, 8, 20, 1, 36)
    o:Color("tabActiveColor", L.OPT_CHAT_TAB_ACTIVE_COLOR, 36)
    o:Check("tabUnderline", L.OPT_CHAT_TAB_UNDERLINE, 36)
    o:EndAdvanced()
    o:Dropdown("sidebar", L.OPT_CHAT_SIDEBAR, {
        { name = L.OPT_CHAT_SIDEBAR_NONE, value = "none" }, { name = L.OPT_CHAT_SIDEBAR_LEFT, value = "left" },
        { name = L.OPT_CHAT_SIDEBAR_RIGHT, value = "right" },
    })
    o:Advanced()
    o:EditBox("sidebarButtons", L.OPT_CHAT_SIDEBAR_BUTTONS, 1, 36)
    o.layout:Hint(L.OPT_CHAT_SIDEBAR_HINT)
    o:EndAdvanced()
    o:Check("hideButtons", L.OPT_CHAT_HIDE_BUTTONS)
    o:Check("noFade", L.OPT_CHAT_NO_FADE)
    o:Advanced()
    o:Slider("fadeTime", L.OPT_CHAT_FADE_TIME, 5, 600, 5, 36)
    o:Slider("maxLines", L.OPT_CHAT_MAX_LINES, 128, 4096, 128)
    o:EndAdvanced()
    o:Check("editBoxTop", L.OPT_CHAT_EDITBOX_TOP)
    o:Check("urls", L.OPT_CHAT_URLS)
    o:Check("copy", L.OPT_CHAT_COPY)
    o:Check("shortChannels", L.OPT_CHAT_SHORT_CHANNELS)
    o:Check("classColors", L.OPT_CHAT_CLASS_COLORS)
    o:Dropdown("timestamps", L.OPT_CHAT_TIMESTAMPS, {
        { name = L.CHAT_TIMESTAMPS_NONE, value = "none" },
        { name = "12:34", value = "%H:%M " },
        { name = "12:34:56", value = "%H:%M:%S " },
    })
    o:Title(L.OPT_CHAT_HISTORY_TITLE)
    o:Check("history", L.OPT_CHAT_HISTORY)
    o:Advanced()
    o:Slider("historyLines", L.OPT_CHAT_HISTORY_LINES, 20, 500, 10, 36)
    o:EndAdvanced()
    -- Pas en retrait : l'historique déjà gardé s'efface même option décochée.
    o:Button(L.OPT_CHAT_HISTORY_CLEAR, function() Chat:ClearHistory() end, 20)
    o:Title(L.OPT_CHAT_KEYWORDS_TITLE)
    o:EditBox("keywords", L.OPT_CHAT_KEYWORDS)
    o:Check("keywordName", L.OPT_CHAT_KEYWORD_NAME)
    o:Check("keywordSound", L.OPT_CHAT_KEYWORD_SOUND)
    o:Advanced()
    o:Sound(nil, "keywordSoundFile", 36, PlayKeywordSound)
    o:EndAdvanced()
    o:Title(L.OPT_CHAT_SPAM_TITLE)
    o:Check("antiSpam", L.OPT_CHAT_ANTI_SPAM)
    o:Advanced()
    o:Slider("spamWindow", L.OPT_CHAT_SPAM_WINDOW, 10, 600, 10, 36)
    o:EndAdvanced()
    o:Title(L.OPT_CHAT_WINDOWS_TITLE)
    o:Check("windows", L.OPT_CHAT_WINDOWS)
    o:Slider("leftWidth", L.OPT_CHAT_LEFT_WIDTH, CHAT_MIN_WIDTH, 900, 2, 36)
    o:Slider("leftHeight", L.OPT_CHAT_LEFT_HEIGHT, CHAT_MIN_HEIGHT, 600, 2, 36)
    o:Slider("rightWidth", L.OPT_CHAT_RIGHT_WIDTH, CHAT_MIN_WIDTH, 900, 2, 36)
    o:Slider("rightHeight", L.OPT_CHAT_RIGHT_HEIGHT, CHAT_MIN_HEIGHT, 600, 2, 36)
    o:Button(L.OPT_UF_UNLOCK, function() NS:SetUnlocked(not NS.unlocked) end, 36)
    -- Remet toutes les fenêtres à zéro : général à gauche, butin / commerce détaché à droite.
    o:Button(L.OPT_CHAT_SETUP_WINDOWS, function()
        NS.Options.Confirm("AEONUI_CHAT_SETUP", L.MSG_CHAT_SETUP_CONFIRM, function()
            NS:RunOutOfCombat(function()
                if NS.AddonPlacements.Chat() then
                    Chat:OnRefresh()
                    NS.Options.AskReload(L.MSG_CHAT_RELOAD)
                end
            end)
        end)
    end, 36)
end

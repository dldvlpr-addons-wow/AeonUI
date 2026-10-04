-- AeonUI_Chat/ChatBubbles.lua
-- Bulles de dialogue au thème : fond, police, bordure à la couleur du canal, et choix des canaux
-- affichés (dire, crier, groupe, PNJ). Le canal d'une bulle se lit en rapprochant son texte des
-- derniers messages reçus : les bulles n'en portent pas la trace.
--
-- Midnight : une bulle interdite (instance) ou un texte secret est laissé tel quel.
local NS = AeonUI
local L = NS.L
local Media = NS.Media

local ChatBubbles = NS.Modules:Register("chatbubbles", {
    titleKey = "BUBBLES_TITLE",
    descKey = "BUBBLES_DESC",
    defaults = {
        enabled = false,
        say = true, yell = true, party = true, npc = true,   -- canaux affichés ; décoché = bulle masquée
        fontSize = 12,
        channelBorder = true,     -- bordure à la couleur du canal, sinon celle du thème
    },
})

local CHANNELS = {
    CHAT_MSG_SAY = "say", CHAT_MSG_YELL = "yell", CHAT_MSG_PARTY = "party", CHAT_MSG_PARTY_LEADER = "party",
    CHAT_MSG_MONSTER_SAY = "npc", CHAT_MSG_MONSTER_YELL = "npc", CHAT_MSG_MONSTER_PARTY = "npc",
}
local CHAT_TYPES = { say = "SAY", yell = "YELL", party = "PARTY", npc = "MONSTER_SAY" }
local RECENT_LIMIT, RECENT_SECONDS = 30, 30

local active = false
local recent = {}               -- { { text, channel, time } }, le plus récent en dernier
local styled = setmetatable({}, { __mode = "k" })   -- [bulle] = { holder, text, backdrop }

--- Canal du message le plus récent portant ce texte, ou nil.
function ChatBubbles.ChannelOf(text)
    if NS.IsSecret(text) or not text then return nil end
    local now = GetTime()
    for i = #recent, 1, -1 do
        local message = recent[i]
        if now - message.time > RECENT_SECONDS then break end
        if message.text == text then return message.channel end
    end
    return nil
end

local function Remember(text, channel)
    if NS.IsSecret(text) or type(text) ~= "string" then return end
    recent[#recent + 1] = { text = text, channel = channel, time = GetTime() }
    if #recent > RECENT_LIMIT then table.remove(recent, 1) end
end

--- Cadre de la bulle (enfant du moteur retail, sinon la bulle) et son texte.
local function Parts(bubble)
    local holder = bubble:GetChildren() or bubble
    local text = holder.String
    if not text then
        for _, region in ipairs({ holder:GetRegions() }) do
            if region.GetObjectType and region:GetObjectType() == "FontString" then text = region break end
        end
    end
    return holder, text
end

local function Style(bubble)
    if bubble.IsForbidden and bubble:IsForbidden() then return end
    local entry = styled[bubble]
    if not entry then
        local holder, text = Parts(bubble)
        if not text then return end
        entry = { holder = holder, text = text, font = { text:GetFont() }, textures = {} }
        for _, region in ipairs({ holder:GetRegions() }) do
            if region.GetObjectType and region:GetObjectType() == "Texture" then entry.textures[#entry.textures + 1] = region end
        end
        local bg, edges = Media:CreateBackdrop(holder)
        entry.backdrop = { bg = bg, edges = edges }
        styled[bubble] = entry
    end
    local db = ChatBubbles.db
    for _, texture in ipairs(entry.textures) do texture:SetAlpha(0) end
    if entry.holder.Tail then entry.holder.Tail:SetAlpha(0) end
    entry.backdrop.bg:Show()
    entry.text:SetFont(Media:Font(), db.fontSize, Media:Outline())
    local channel = ChatBubbles.ChannelOf(entry.text:GetText())
    local info = channel and _G.ChatTypeInfo and ChatTypeInfo[CHAT_TYPES[channel]]
    local border = NS.db.theme.border
    local r, g, b = border.r, border.g, border.b
    if db.channelBorder and info and info.r then r, g, b = info.r, info.g, info.b end
    for _, edge in pairs(entry.backdrop.edges or {}) do NS.SetSolidColor(edge, r, g, b, 1) edge:Show() end
    bubble:SetAlpha((channel and not db[channel]) and 0 or 1)
end

local function Unstyle(bubble, entry)
    for _, texture in ipairs(entry.textures) do texture:SetAlpha(1) end
    if entry.holder.Tail then entry.holder.Tail:SetAlpha(1) end
    entry.backdrop.bg:Hide()
    for _, edge in pairs(entry.backdrop.edges or {}) do edge:Hide() end
    if entry.font[1] then entry.text:SetFont(unpack(entry.font)) end
    bubble:SetAlpha(1)
end

function ChatBubbles:Scan()
    if not (active and _G.C_ChatBubbles and C_ChatBubbles.GetAllChatBubbles) then return end
    for _, bubble in pairs(C_ChatBubbles.GetAllChatBubbles() or {}) do Style(bubble) end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, text)
    Remember(text, CHANNELS[event])
    -- La bulle apparaît à la frame suivante, texte déjà posé.
    C_Timer.After(0, function() ChatBubbles:Scan() end)
end)

function ChatBubbles:OnEnable()
    active = true
    for event in pairs(CHANNELS) do NS.RegisterEventSafe(events, event) end
end

function ChatBubbles:OnDisable()
    active = false
    events:UnregisterAllEvents()
    for bubble, entry in pairs(styled) do Unstyle(bubble, entry) end
    recent = {}
end

function ChatBubbles:OnRefresh()
    self:Scan()
end

function ChatBubbles:BuildOptions(o)
    o.layout:Note(L.NOTE_BUBBLES_INSTANCE, 20)
    o:Check("say", L.BUBBLES_SAY)
    o:Check("yell", L.BUBBLES_YELL)
    o:Check("party", L.BUBBLES_PARTY)
    o:Check("npc", L.BUBBLES_NPC)
    o:Slider("fontSize", L.OPT_CHAT_FONT_SIZE, 8, 20, 1)
    o:Check("channelBorder", L.OPT_BUBBLES_CHANNEL_BORDER)
end

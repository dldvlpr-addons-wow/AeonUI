-- Core/ProfileShare.lua
-- Envoi du profil actif aux membres du groupe par messages d'addon. Le profil (chaîne d'export)
-- part en morceaux numérotés ; le destinataire le rassemble puis confirme avant d'importer.
-- Rien n'est importé sans clic sur « Oui ». Seuls les membres du groupe sont écoutés.
local _, NS = ...
local L = NS.L

local ProfileShare = {}
NS.ProfileShare = ProfileShare

local PREFIX = "AeonUI"
local CHUNK = 240                 -- 255 octets par message, en-tête compris
local SEND_INTERVAL = 0.25
local MAX_CHUNKS = 400            -- ~96 Ko : au-delà, envoi ignoré
local INCOMPLETE_TIMEOUT = 30
local MAX_RETRIES = 120           -- 30 s de refus d'affilée : envoi abandonné
local incoming = {}               -- [expéditeur] = { total, parts = {}, count, time }
local sending

local ChatInfo = _G.C_ChatInfo or {}
local function SendMessage(...)
    local send = ChatInfo.SendAddonMessage or _G.SendAddonMessage
    return send(...)
end
local registerPrefix = ChatInfo.RegisterAddonMessagePrefix or _G.RegisterAddonMessagePrefix
if registerPrefix then registerPrefix(PREFIX) end

local function Channel()
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
    return nil
end

--- Morceaux « n/total:texte » d'une chaîne.
function ProfileShare.Split(text)
    local total = math.ceil(#text / CHUNK)
    local parts = {}
    for i = 1, total do
        parts[i] = i .. "/" .. total .. ":" .. text:sub((i - 1) * CHUNK + 1, i * CHUNK)
    end
    return parts
end

--- Résultat d'un envoi : "sent", "throttled" (limite de débit ou verrouillage, à rejouer) ou "failed".
-- 12.x rend Enum.SendAddonMessageResult (0 succès, 3 et 8 limite de débit, 11 verrouillage) ;
-- Classic un booléen, faux aussi bien pour la limite que pour un groupe quitté.
local function SendStatus(result, channel)
    if result == nil or result == true or result == 0 then return "sent" end
    if type(result) == "number" then
        local codes = _G.Enum and Enum.SendAddonMessageResult
        local throttle = codes and codes.AddonMessageThrottle or 3
        local channelThrottle = codes and codes.ChannelThrottle or 8
        local lockdown = codes and codes.AddOnMessageLockdown or 11
        return (result == throttle or result == channelThrottle or result == lockdown) and "throttled" or "failed"
    end
    return Channel() == channel and "throttled" or "failed"
end

--- Envoie le profil actif au groupe. Faux si pas de groupe ou envoi déjà en cours.
function ProfileShare:Send()
    local channel = Channel()
    if not (channel and (ChatInfo.SendAddonMessage or _G.SendAddonMessage)) or sending then
        NS.Print(sending and L.MSG_PROFILE_SENDING or L.MSG_PROFILE_NO_GROUP)
        return false
    end
    local parts = ProfileShare.Split(NS.Database.Export(NS.db))
    local index, retries = 1, 0
    sending = C_Timer.NewTicker(SEND_INTERVAL, function()
        local ok, result = pcall(SendMessage, PREFIX, parts[index], channel)
        local status = ok and SendStatus(result, channel) or "failed"
        if status == "sent" then
            index, retries = index + 1, 0
        elseif status == "throttled" then
            retries = retries + 1   -- même morceau au tour suivant
            if retries > MAX_RETRIES then status = "failed" end
        end
        if status == "failed" or index > #parts then
            sending:Cancel()
            sending = nil
            NS.Print(status == "failed" and L.MSG_PROFILE_SEND_FAILED or string.format(L.MSG_PROFILE_SENT, #parts))
        end
    end)
    NS.Print(string.format(L.MSG_PROFILE_SENDING_PARTS, #parts))
    return true
end

StaticPopupDialogs["AEONUI_PROFILE_RECEIVED"] = {
    text = "",
    button1 = YES,
    button2 = NO,
    -- Profil passé en `data` : une seconde réception remplace la fenêtre sans perdre le sien.
    OnAccept = function(_, data) if data then NS:ImportProfile(data) end end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function InGroup(sender)
    local name = _G.Ambiguate and Ambiguate(sender, "none") or sender
    local inParty = _G.UnitInParty and UnitInParty(name)
    local inRaid = _G.UnitInRaid and UnitInRaid(name)
    if NS.IsSecret(inParty) or NS.IsSecret(inRaid) then return false end
    return (inParty and true or false) or inRaid ~= nil
end

--- Un morceau reçu ; le profil complet ouvre la confirmation.
function ProfileShare.Receive(text, sender)
    if NS.IsSecret(text) or NS.IsSecret(sender) or type(text) ~= "string" or type(sender) ~= "string" then return end
    local me = UnitName("player")
    if NS.IsSecret(me) or (_G.Ambiguate and Ambiguate(sender, "none") or sender) == me then return end
    if not InGroup(sender) then return end
    local index, total, body = text:match("^(%d+)/(%d+):(.*)$")
    index, total = tonumber(index), tonumber(total)
    if not (index and total) or total < 1 or total > MAX_CHUNKS or index < 1 or index > total then return end
    -- Envois abandonnés : oubliés après 30 s, quel que soit l'expéditeur.
    local now = GetTime()
    for name, old in pairs(incoming) do
        if now - old.time > INCOMPLETE_TIMEOUT then incoming[name] = nil end
    end
    local entry = incoming[sender]
    -- Nouvel envoi : autre nombre de morceaux, ou envoi précédent abandonné depuis 30 s.
    if not entry or entry.total ~= total then
        entry = { total = total, parts = {}, count = 0 }
        incoming[sender] = entry
    end
    entry.time = GetTime()
    if not entry.parts[index] then entry.count = entry.count + 1 end
    entry.parts[index] = body
    if entry.count < total then return end
    incoming[sender] = nil
    local profile = table.concat(entry.parts)
    -- Préfixe seulement : la décompression attend l'accord du joueur (voir Database.Export).
    if not NS.Database.IsProfileString(profile) then return end
    StaticPopupDialogs.AEONUI_PROFILE_RECEIVED.text = string.format(L.MSG_PROFILE_RECEIVED, sender)
    StaticPopup_Show("AEONUI_PROFILE_RECEIVED", nil, nil, profile)
end

local events = CreateFrame("Frame")
NS.RegisterEventSafe(events, "CHAT_MSG_ADDON")
events:SetScript("OnEvent", function(_, _, prefix, text, _, sender)
    if not NS.IsSecret(prefix) and prefix == PREFIX then ProfileShare.Receive(text, sender) end
end)

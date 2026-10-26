-- Modules/FlightTimer.lua
-- Minuteur de vol : barre de compte à rebours pendant un trajet en griffon. La durée de chaque
-- trajet (nœud de départ -> nœud d'arrivée) s'apprend au premier vol complet, puis se lisse par
-- moyenne mobile. Trajet inconnu : temps écoulé et destination, sans décompte. Vol interrompu
-- (mort, déconnexion, atterrissage anticipé) : rien d'appris. Reprise après /reload.
local _, NS = ...
local L = NS.L
local Media = NS.Media

local FlightTimer = NS.Modules:Register("flighttimer", {
    titleKey = "FLIGHT_TITLE",
    descKey = "FLIGHT_DESC",
    defaults = {
        enabled = true,
    },
})

local MIN_FLIGHT = 5          -- secondes : en dessous, pas un vol (clic annulé, téléportation)
local SMOOTHING = 0.3         -- poids du dernier vol dans la moyenne mobile
local PENDING_WINDOW = 10     -- secondes entre TakeTaxiNode et la perte de contrôle
local FADE_SECONDS = 0.3

local active = false
local hooked = false
local holder, bar, label, fadeOut
local ticker
local pending                 -- { from, to, name, at } posé par TakeTaxiNode
local flight                  -- vol en cours, partagé avec NS.global.flightInProgress
local flightClock             -- GetTime() du départ, recalculé à la reprise

function FlightTimer.RouteKey(from, to) return from .. ":" .. to end

local function Times()
    NS.global.flightTimes = NS.global.flightTimes or {}
    return NS.global.flightTimes
end

--- Durée apprise du trajet, ou nil.
function FlightTimer.KnownDuration(from, to)
    if not (from and to) then return nil end
    return Times()[FlightTimer.RouteKey(from, to)]
end

--- Mémorise un vol complet de `seconds` : première mesure telle quelle, ensuite moyenne mobile.
function FlightTimer.Learn(from, to, seconds)
    if not (from and to) or seconds < MIN_FLIGHT then return end
    local times, key = Times(), FlightTimer.RouteKey(from, to)
    local old = times[key]
    times[key] = old and (old * (1 - SMOOTHING) + seconds * SMOOTHING) or seconds
end

local function Elapsed() return flightClock and math.max(0, GetTime() - flightClock) or 0 end

local function Build()
    holder = CreateFrame("Frame", "MuscaUIFlightTimer", UIParent)
    holder:SetSize(220, 16)
    Media:CreateBackdrop(holder)
    bar = Media:CreateStatusBar(holder)
    bar:SetAllPoints(holder)
    bar:SetStatusBarColor(0.35, 0.65, 1)
    label = Media:CreateText(bar, "OVERLAY", 0, "OUTLINE")
    label:SetPoint("CENTER", holder, "CENTER", 0, 0)
    fadeOut = holder:CreateAnimationGroup()
    local alpha = fadeOut:CreateAnimation("Alpha")
    alpha:SetFromAlpha(1)
    alpha:SetToAlpha(0)
    alpha:SetDuration(FADE_SECONDS)
    fadeOut:SetScript("OnFinished", function() holder:Hide() end)
    holder:Hide()
end

local function ShowHolder()
    fadeOut:Stop()
    holder:SetAlpha(1)
    holder:Show()
end

local function HideHolder()
    if holder:IsShown() and not fadeOut:IsPlaying() then fadeOut:Play() end
end

local function Prefix() return flight.name and (flight.name .. "  ") or "" end

-- Texte (et barre animée à la main sans l'API moteur), une fois par seconde en vol.
local function Tick()
    if not flight then return end
    local elapsed = Elapsed()
    local duration = FlightTimer.KnownDuration(flight.from, flight.to)
    if duration then
        label:SetText(Prefix() .. NS.FormatDuration(math.max(0, duration - elapsed)))
        if bar.manual then bar:SetValue(math.max(0, duration - elapsed)) end
    else
        label:SetText(Prefix() .. "+" .. NS.FormatDuration(elapsed))
    end
end

function FlightTimer:Update()
    if not holder then return end
    if not active then
        holder:Hide()
        return
    end
    if flight then
        local duration = FlightTimer.KnownDuration(flight.from, flight.to)
        bar.manual = nil
        if not duration then
            bar:SetMinMaxValues(0, 1)
            bar:SetValue(1)
        elseif not NS.SetBarTimer(bar, flightClock, duration, true) then
            bar.manual = true
            bar:SetMinMaxValues(0, duration)
        end
        Tick()
        ShowHolder()
    elseif NS:Previewing() then
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(0.6)
        label:SetText(L.MOVER_FLIGHT .. "  1:30")
        ShowHolder()
    else
        HideHolder()
    end
end

local function StartTicker()
    if not ticker then ticker = C_Timer.NewTicker(1, Tick) end
end

local function StopTicker()
    if ticker then ticker:Cancel() end
    ticker = nil
end

--- Départ : `saved` reprend un vol après /reload, sinon le vol choisi par TakeTaxiNode.
function FlightTimer.Start(saved)
    if saved then
        flight = saved
        local now = NS.ServerTime()
        flightClock = GetTime() - (now and saved.start and math.max(0, now - saved.start) or 0)
    else
        flight = { from = pending.from, to = pending.to, name = pending.name, start = NS.ServerTime() }
        flightClock = GetTime()
    end
    pending = nil
    NS.global.flightInProgress = flight
    StartTicker()
    FlightTimer:Update()
end

--- Arrivée (`completed`) ou abandon : apprend la durée d'un vol complet et non interrompu.
function FlightTimer.Stop(completed)
    if not flight then return end
    if completed and not flight.interrupted then FlightTimer.Learn(flight.from, flight.to, Elapsed()) end
    flight, flightClock = nil, nil
    NS.global.flightInProgress = false
    StopTicker()
    FlightTimer:Update()
end

--- Vol en cours (tests).
function FlightTimer.Current() return flight end

local function OnTakeTaxi(slot)
    if not active then return end
    local nodes = NS.GetTaxiNodes()
    local destination = nodes[slot]
    if not destination then return end
    local from
    for _, node in pairs(nodes) do
        if node.current then from = node.nodeID end
    end
    pending = { from = from, to = destination.nodeID, name = destination.name, at = GetTime() }
end

local function OnEarlyLanding()
    if flight then flight.interrupted = true end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, isLogin, isReloadingUi)
    if event == "PLAYER_CONTROL_LOST" then
        if pending and not flight and GetTime() - pending.at <= PENDING_WINDOW then FlightTimer.Start() end
    elseif event == "PLAYER_CONTROL_GAINED" then
        if flight and not NS.OnTaxi() then FlightTimer.Stop(true) end
    elseif event == "PLAYER_DEAD" then
        OnEarlyLanding()
    elseif event == "PLAYER_ENTERING_WORLD" then
        local saved = NS.global.flightInProgress
        if flight or not saved then return end
        if isReloadingUi and NS.OnTaxi() then
            FlightTimer.Start(saved)
        else
            NS.global.flightInProgress = false   -- connexion : vol perdu (déconnexion), rien d'appris
        end
    end
end)

function FlightTimer:OnEnable()
    if not holder then Build() end
    active = true
    if not hooked then
        hooked = true
        NS.HookTaxi(OnTakeTaxi, OnEarlyLanding)
    end
    for _, event in ipairs({ "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED", "PLAYER_DEAD",
                             "PLAYER_ENTERING_WORLD" }) do
        NS.RegisterEventSafe(events, event)
    end
    NS.Movers:Register("flightTimer", holder, L.MOVER_FLIGHT, "TOP", 0, -140)
    NS.Movers:Load("flightTimer")
    self:Update()
end

function FlightTimer:OnDisable()
    active = false
    events:UnregisterAllEvents()
    pending, flight, flightClock = nil, nil, nil
    NS.global.flightInProgress = false
    StopTicker()
    NS.Movers:Unregister("flightTimer")
    self:Update()
end

function FlightTimer:OnRefresh() self:Update() end

NS:On("PREVIEW", function() FlightTimer:Update() end)

function FlightTimer:BuildOptions(o)
    o:Hint(L.OPT_FLIGHT_HINT)
end

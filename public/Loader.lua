--[[
    UniversalAdmin Loader - Local Script
    Handles authentication, then fetches the main Admin script.
    Public endpoint: anyone can load this. The admin script is protected behind auth.
]]

--[[
    UniversalAdmin - Local Script
    A universal Roblox admin system using CoreGui.
    Designed to run as a local script (client-side).

    Discord key auth (optional overrides before running):
      getgenv().UA_AuthApiBase = "https://YOUR-API.up.railway.app"  -- no trailing slash
      getgenv().UA_DiscordInvite = "https://discord.gg/YOUR_INVITE" -- Join Discord button

    Default UA_AuthApiBase points at the production Railway API if unset.

    Center top-bar icon: set CONFIG.AdminTopBarDecalId to your uploaded decal's numeric id.
]]

-------------------------------------------------
-- CONFIGURATION
-------------------------------------------------
local CONFIG = {
    Prefix = ";",
    ToggleKey = Enum.KeyCode.Semicolon,


		-- Public Loader.lua URL for auto-reexec after rejoin.
		-- After auth, Loader fetches the protected Admin.lua.
		LoaderUrl = "https://discord-key-auth-production.up.railway.app/Loader.lua",
		-- Protected admin script endpoint (requires ?token=JWT query param).
		AdminScriptUrl = "https://discord-key-auth-production.up.railway.app/Admin.lua",
    -- Shown in Premium upsell toasts; override with getgenv().UA_DiscordInvite if needed.
    DiscordInvite = "https://discord.gg/KZw9SkPZr4",

    -- Top bar center image: Roblox decal asset id (Creator Dashboard URL number).
    AdminTopBarDecalId = 124242419648785,
    -- Nametag icon decal (left icon in UA tag card).
    UserTagDecalId = 124242419648785,
    -- Direct image/texture id for nametag icon (preferred when provided).
    UserTagImageId = 119909165185829,

    -- Version & changelog (updated by release tool)
    Version = "1.1.1",
    Changelog = {
        "Latest version"
    },

    -- UI Theme
    Theme = {
        Background      = Color3.fromRGB(18, 18, 24),
        Surface         = Color3.fromRGB(26, 26, 36),
        SurfaceHover    = Color3.fromRGB(34, 34, 48),
        Border          = Color3.fromRGB(45, 45, 65),
        AccentPrimary   = Color3.fromRGB(99, 102, 241),   -- Indigo
        AccentSecondary = Color3.fromRGB(139, 92, 246),    -- Purple
        Text            = Color3.fromRGB(240, 240, 245),
        TextDim         = Color3.fromRGB(140, 140, 165),
        TextMuted       = Color3.fromRGB(90, 90, 115),
        Success         = Color3.fromRGB(52, 211, 153),
        Error           = Color3.fromRGB(248, 113, 113),
        Warning         = Color3.fromRGB(251, 191, 36),
        CornerRadius    = UDim.new(0, 8),
        CornerRadiusLg  = UDim.new(0, 12),
        Font            = Enum.Font.GothamMedium,
        FontBold        = Enum.Font.GothamBold,
        FontMono        = Enum.Font.Code,
    },
}

-------------------------------------------------
-- SERVICES
-------------------------------------------------
local Players        = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService   = game:GetService("TweenService")
local TextService    = game:GetService("TextService")
local CoreGui        = game:GetService("CoreGui")
local RunService     = game:GetService("RunService")
local SoundService   = game:GetService("SoundService")
local TeleportService = game:GetService("TeleportService")

local LocalPlayer = Players.LocalPlayer
local UA_RUNTIME = rawget(_G, "UA_RUNTIME")
if type(UA_RUNTIME) ~= "table" then
    UA_RUNTIME = {}
    _G.UA_RUNTIME = UA_RUNTIME
end
UA_RUNTIME.active = true

-- Shared state table (reduces local variable count under Luau's 200 limit)
_G.UA_State = {}
local S = _G.UA_State

-- UTILITY
-------------------------------------------------
local Theme = CONFIG.Theme

local function normalizeTierString(tier)
    local raw = string.lower(tostring(tier or ""):gsub("^%s+", ""):gsub("%s+$", ""))
    if raw == "owner" then return "Owner" end
    if raw == "premium" then return "Premium" end
    return "Member"
end

local function tierToDisplayLabel(tier)
    local t = normalizeTierString(tier)
    if t == "Owner" then
        return "Owner"
    end
    if t == "Premium" then
        return "Premium User"
    end
    return "Standard User"
end

local function formatTierWithRemaining(tier, expiresAtIso)
    local base = tierToDisplayLabel(tier)
    if type(expiresAtIso) ~= "string" or expiresAtIso == "" then
        return base
    end
    local okParsed, dt = pcall(function()
        return DateTime.fromIsoDate(expiresAtIso)
    end)
    if not okParsed or not dt then
        return base
    end
    local sec = math.max(0, dt.UnixTimestamp - DateTime.now().UnixTimestamp)
    local days = math.max(1, math.ceil(sec / 86400))
    return base .. " - " .. tostring(days) .. "d"
end

local function tierLevel(tier)
    local t = normalizeTierString(tier)
    if t == "Owner" then return 3 end
    if t == "Premium" then return 2 end
    return 1
end

local function encodeAccentColor(c)
    if typeof(c) ~= "Color3" then return nil end
    local r = math.clamp(math.floor(c.R * 255 + 0.5), 0, 255)
    local g = math.clamp(math.floor(c.G * 255 + 0.5), 0, 255)
    local b = math.clamp(math.floor(c.B * 255 + 0.5), 0, 255)
    return tostring(r) .. "," .. tostring(g) .. "," .. tostring(b)
end

local function decodeAccentColor(raw)
    if type(raw) ~= "string" then return nil end
    local r, g, b = string.match(raw, "^(%d+),(%d+),(%d+)$")
    r, g, b = tonumber(r), tonumber(g), tonumber(b)
    if not r or not g or not b then return nil end
    return Color3.fromRGB(math.clamp(r, 0, 255), math.clamp(g, 0, 255), math.clamp(b, 0, 255))
end

-------------------------------------------------
-- PERSISTENT SETTINGS (executor filesystem)
-- Uses writefile/readfile/isfile which most major executors support.
-- Saves prefix, nickname, accent color, custom commands, hotkeys, UI pos.
-------------------------------------------------
local HttpService = game:GetService("HttpService")
local SETTINGS_DIR  = "UniversalAdmin"
local SETTINGS_FILE = "UniversalAdmin/settings.json"

local function fsHasWrite()
    return type(writefile) == "function" and type(readfile) == "function" and type(isfile) == "function"
end

local function ensureDir()
    if type(makefolder) == "function" and type(isfolder) == "function" then
        if not isfolder(SETTINGS_DIR) then
            pcall(makefolder, SETTINGS_DIR)
        end
    end
end

-- Will be populated from file on load; applied at UI-build time.
local persistedConfig = {
    prefix        = nil,
    nickname      = nil,
    accentPrimary = nil,  -- {r,g,b}
    accentSecondary = nil,
    customCommands = {},  -- { { name = "foo", source = "..." }, ... }
    recentCommands = {}, -- most recent executed commands (for ;recent)
    flyHotkey     = nil,
    noclipHotkey  = nil,
    clickFlingBind = nil,
    clickFlingTriggerBind = nil,
    clickFlingFov  = nil,
    clickFlingMode = nil,
    topBarPos     = nil,  -- { xScale, xOffset, yScale, yOffset }
    loginUser     = nil,  -- username string; when set, skip login & show "Welcome back"
    loginKey      = nil,  -- script auth key tied to loginUser
    authToken     = nil,  -- JWT from script-login (Discord /kick, /message, presence)
    scriptFingerprint = nil, -- remote script ETag/Last-Modified snapshot for update notices
    accountTier   = nil,  -- API tier string (e.g. Member); shown as "Standard User" in UI
    accountExpiresAt = nil, -- API license expiry ISO (for "Tier - Nd")
    hotkeyAlwaysActive = {},  -- { fly = true, noclip = true, ... }
    waypoints = {}, -- { ["placeId"] = { name = { x, y, z } } }
    profiles = {}, -- { profileName = { ...settings } }
    alerts = { join = true, leave = true, uaUsers = true, spectateRespawn = true },
    spectateCard = true,
	uiScale = nil,  -- nil = 100%; stored as integer percent (50-200)
	settingsUpdatedAt = nil,  -- os.time() for cloud-sync conflict resolution
}

-- Per-command "always active hotkey" tracking.
-- When false, the hotkey only works while the panel is open or the feature is on.
-- Commands without panels (camlock, blink) default to always-active.
local hotkeyAlwaysActive = { camlock = true, blink = true }

local function hasTierAtLeast(minTier)
    return tierLevel((persistedConfig and persistedConfig.accountTier) or "Member") >= tierLevel(minTier)
end

local function loadPersistedConfig()
    if not fsHasWrite() then return end
    local ok, contents = pcall(function()
        if isfile(SETTINGS_FILE) then
            return readfile(SETTINGS_FILE)
        end
        return nil
    end)
    if not ok or not contents then return end
    local okDecode, decoded = pcall(function() return HttpService:JSONDecode(contents) end)
    if okDecode and type(decoded) == "table" then
        for k, v in pairs(decoded) do
            persistedConfig[k] = v
        end
    end
end

local function savePersistedConfig()
    if not fsHasWrite() then return end
    ensureDir()
    local ok, encoded = pcall(function() return HttpService:JSONEncode(persistedConfig) end)
    if not ok or not encoded then return end
    pcall(function() writefile(SETTINGS_FILE, encoded) end)
    local syncFn = UA_RUNTIME._requestSettingsSync
    if type(syncFn) == "function" then syncFn() end
end

loadPersistedConfig()

-- Apply early-boot persisted values to CONFIG so UI construction picks them up
if persistedConfig.prefix and type(persistedConfig.prefix) == "string" and #persistedConfig.prefix >= 1 then
    CONFIG.Prefix = persistedConfig.prefix
end
if persistedConfig.accentPrimary and type(persistedConfig.accentPrimary) == "table" then
    local a = persistedConfig.accentPrimary
    if type(a.r) == "number" and type(a.g) == "number" and type(a.b) == "number" then
        Theme.AccentPrimary = Color3.fromRGB(a.r, a.g, a.b)
    end
end
if persistedConfig.accentSecondary and type(persistedConfig.accentSecondary) == "table" then
    local a = persistedConfig.accentSecondary
    if type(a.r) == "number" and type(a.g) == "number" and type(a.b) == "number" then
        Theme.AccentSecondary = Color3.fromRGB(a.r, a.g, a.b)
    end
end
if persistedConfig.hotkeyAlwaysActive and type(persistedConfig.hotkeyAlwaysActive) == "table" then
    for k, v in pairs(persistedConfig.hotkeyAlwaysActive) do
        if v == true then hotkeyAlwaysActive[k] = true end
    end
end

if persistedConfig.uiScale and type(persistedConfig.uiScale) == "number" then pcall(function() if CoreGui then end end) end -- uiScale applied by Admin.lua
end
local function create(className, properties, children)
    local inst = Instance.new(className)
    for k, v in pairs(properties or {}) do
        inst[k] = v
    end
    for _, child in ipairs(children or {}) do
        child.Parent = inst
    end
    return inst
end

local function tween(obj, tweenInfo, goals)
    local t = TweenService:Create(obj, tweenInfo, goals)
    t:Play()
    return t
end

local function liftColor(c, amt)
    amt = tonumber(amt) or 0
    return Color3.new(
        math.clamp(c.R + amt, 0, 1),
        math.clamp(c.G + amt, 0, 1),
        math.clamp(c.B + amt, 0, 1)
    )
end
local uiMotion = {
    reduced = persistedConfig and persistedConfig.reducedMotion == true or false,
}
local function motionTween(duration, style, dir)
    local d = tonumber(duration) or 0.2
    if uiMotion.reduced then
        d = math.max(0.08, d * 0.55)
    end
    return TweenInfo.new(d, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out)
end

-------------------------------------------------
-- REJOIN / TELEPORT AUTO-REEXEC
-------------------------------------------------
local function getQueueOnTeleport()
    local candidates = {
        rawget(getfenv(0), "queue_on_teleport"),
        (syn and syn.queue_on_teleport) or nil,
        (fluxus and fluxus.queue_on_teleport) or nil,
        (Krnl and Krnl.queue_on_teleport) or nil,
    }
    if getgenv then
        local env = getgenv()
        table.insert(candidates, env.queue_on_teleport)
        if env.syn and env.syn.queue_on_teleport then
            table.insert(candidates, env.syn.queue_on_teleport)
        end
    end
    for _, fn in ipairs(candidates) do
        if type(fn) == "function" then return fn end
    end
    return nil
end

local function getLoaderUrlForReexec()
    local loaderUrl = CONFIG.LoaderUrl
    if (not loaderUrl or loaderUrl == "") and getgenv then
        local g = getgenv().UA_LoaderUrl
        if type(g) == "string" and g ~= "" then
            loaderUrl = g
        end
    end
    return loaderUrl
end

local function buildHttpGetReexecSnippet()
    local loaderUrl = getLoaderUrlForReexec()
    if not loaderUrl or loaderUrl == "" then
        return nil
    end
    return string.format(
        "task.wait(3); local ok, err = pcall(function() loadstring(game:HttpGet(%q))() end); if not ok then warn('UA auto-reexec failed: '..tostring(err)) end",
        loaderUrl
    )
end

local function buildRejoinTeleportSnippet()
    return buildHttpGetReexecSnippet()
        or [[task.wait(3); if _G.UA_Source then pcall(function() loadstring(_G.UA_Source)() end) end]]
end
-- Queue HttpGet loader on teleport/rejoin when CONFIG.LoaderUrl is set (no empty UA_Source-only queue)
task.defer(function()
    local queueFn = getQueueOnTeleport()
    local snippet = buildHttpGetReexecSnippet()
    if queueFn and snippet then
        pcall(function() queueFn(snippet) end)
    end
end)

-------------------------------------------------
-- AUTHENTICATION & ADMIN FETCH
-------------------------------------------------
-------------------------------------------------
-- LOGIN SCREEN
-- Gates the script behind username/password against the Discord key-auth API
-- (register + redeem key in Discord, then sign in here). Persists username +
-- key for faster "welcome back" via /auth/script-login-key.
-- Wrapped in IIFE: avoids adding another local on the main chunk (Luau ~200 limit).
-------------------------------------------------
;(function()

local function normalizeApiBase(url)
    if type(url) ~= "string" or url == "" then
        return url
    end
    return url:gsub("/+$", "")
end

local AUTH_API_BASE = normalizeApiBase(
    (getgenv and getgenv().UA_AuthApiBase)
        or "https://discord-key-auth-production.up.railway.app"
)
local DISCORD_INVITE = (getgenv and type(getgenv().UA_DiscordInvite) == "string" and getgenv().UA_DiscordInvite ~= "")
    and getgenv().UA_DiscordInvite
    or CONFIG.DiscordInvite
UA_RUNTIME._discordInvite = DISCORD_INVITE

local function clearSavedLogin()
    persistedConfig.loginUser = nil
    persistedConfig.loginKey = nil
    persistedConfig.authToken = nil
    persistedConfig.accountTier = nil
    persistedConfig.accountExpiresAt = nil
    savePersistedConfig()
end

local function getRequestFn()
    return request
        or http_request
        or (syn and syn.request)
        or (fluxus and fluxus.request)
end

local function postJson(url, bodyTable)
    local req = getRequestFn()
    if not req then
        return nil, "No supported HTTP request function in executor"
    end
    local ok, res = pcall(function()
        return req({
            Url = url,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = HttpService:JSONEncode(bodyTable),
        })
    end)
    if not ok or not res then
        return nil, "HTTP request failed"
    end
    if tonumber(res.StatusCode) ~= 200 then
        local msg = tostring(res.StatusCode or "unknown")
        local body = tostring(res.Body or "")
        local parsed
        pcall(function() parsed = HttpService:JSONDecode(body) end)
        if type(parsed) == "table" and parsed.error then
            return nil, tostring(parsed.error)
        end
        return nil, "Auth failed (" .. msg .. ")"
    end
    local parsed
    local okDecode = pcall(function() parsed = HttpService:JSONDecode(res.Body or "{}") end)
    if not okDecode or type(parsed) ~= "table" then
        return nil, "Invalid auth response"
    end
    return parsed, nil
end

--- Auth POST that returns `error` body `code` on 401 (ACCESS_BANNED, LOGIN_LOCKOUT, etc.)
local function postJsonAuth(url, bodyTable)
    local req = getRequestFn()
    if not req then
        return nil, "No supported HTTP request function in executor", nil, nil
    end
    local ok, res = pcall(function()
        return req({
            Url = url,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = HttpService:JSONEncode(bodyTable),
        })
    end)
    if not ok or not res then
        return nil, "HTTP request failed", nil, nil
    end
    local body = tostring(res.Body or "")
    local parsed = nil
    pcall(function()
        parsed = HttpService:JSONDecode(body)
    end)
    if tonumber(res.StatusCode) ~= 200 then
        local msg = "Auth failed"
        if type(parsed) == "table" and parsed.error then
            msg = tostring(parsed.error)
        end
        local code = (type(parsed) == "table" and parsed.code) and tostring(parsed.code) or nil
        return nil, msg, code, parsed
    end
    if type(parsed) ~= "table" or parsed.ok ~= true then
        return nil, "Invalid auth response", nil, parsed
    end
    return parsed, nil, nil, parsed
end

-- Bearer JSON request (POST with body or GET without) for /client/presence and /client/commands
local function authHttpJson(method, url, token, bodyTable)
    local req = getRequestFn()
    if not req then
        return nil, "No supported HTTP request function in executor"
    end
    local headers = { Authorization = "Bearer " .. token }
    if bodyTable ~= nil then
        headers["Content-Type"] = "application/json"
    end
    local args = { Url = url, Method = method, Headers = headers }
    if bodyTable ~= nil then
        args.Body = HttpService:JSONEncode(bodyTable)
    end
    local ok, res = pcall(function()
        return req(args)
    end)
    if not ok or not res then
        return nil, "HTTP request failed"
    end
    if tonumber(res.StatusCode) ~= 200 then
        local msg = "HTTP " .. tostring(res.StatusCode or "?")
        local body = tostring(res.Body or "")
        local p
        pcall(function() p = HttpService:JSONDecode(body) end)
        if type(p) == "table" and type(p.error) == "string" then
            msg = tostring(p.error)
        end
        return nil, msg
    end
    local parsed
    local okDecode = pcall(function() parsed = HttpService:JSONDecode(res.Body or "{}") end)
    if not okDecode or type(parsed) ~= "table" then
        return nil, "Invalid JSON"
    end
    return parsed, nil
end
UA_RUNTIME._authHttpJson = authHttpJson
UA_RUNTIME._authApiBase = AUTH_API_BASE
UA_RUNTIME.refreshAuthTokenViaSavedKey = refreshAuthTokenViaSavedKey
UA_RUNTIME.getClientHwid = getClientHwid
UA_RUNTIME.getRequestFn = getRequestFn
UA_RUNTIME.postJsonAuth = postJsonAuth
UA_RUNTIME._loaderUrl = CONFIG.LoaderUrl
UA_RUNTIME._adminScriptUrl = CONFIG.AdminScriptUrl

requestPeerActionFn = function(targetIdentity, action, payload)
    local tok = persistedConfig.authToken
    if type(tok) ~= "string" or tok == "" then
        return nil, "Not authenticated"
    end
    return authHttpJson("POST", AUTH_API_BASE .. "/client/peer-action", tok, {
        token = tok,
        target = targetIdentity,
        action = action,
        payload = payload or {},
    })
end

local remoteAdminBridgeStarted = false
local updateWatcherStarted = false

local function getLoaderUrlForUpdateCheck()
    if type(CONFIG.LoaderUrl) == "string" and CONFIG.LoaderUrl ~= "" then
        return CONFIG.LoaderUrl
    end
    if getgenv then
        local g = getgenv().UA_LoaderUrl
        if type(g) == "string" and g ~= "" then
            return g
        end
    end
    return AUTH_API_BASE .. "/Loader.lua"
end

local function fetchRemoteScriptFingerprint()
    local req = getRequestFn()
    if not req then
        return nil
    end
    local loaderUrl = getLoaderUrlForUpdateCheck()
    local ok, res = pcall(function()
        return req({
            Url = loaderUrl,
            Method = "GET",
        })
    end)
    if not ok or not res or tonumber(res.StatusCode) ~= 200 then
        return nil
    end
    local headers = res.Headers or {}
    local fp = headers.ETag or headers.Etag or headers["Last-Modified"] or headers["last-modified"]
    if type(fp) ~= "string" or fp == "" then
        fp = tostring(#tostring(res.Body or ""))
    end
    return fp
end

local function checkForScriptUpdate()
    local fp = fetchRemoteScriptFingerprint()
    if not fp or fp == "" then
        return
    end
    local prev = persistedConfig.scriptFingerprint
    if type(prev) == "string" and prev ~= "" and prev ~= fp then
        notify("New update - will be applied next execute", "info", 6)
    end
    if prev ~= fp then
        persistedConfig.scriptFingerprint = fp
        savePersistedConfig()
    end
end

local function showCenterAdminMessage(opts)
    opts = opts or {}
    local msg = tostring(opts.body or opts.message or "")
    if msg == "" then
        return
    end
    local titleText = tostring(opts.title or "Message received")
    local senderText = opts.sender and tostring(opts.sender) or nil
    local isDanger = tostring(opts.accent or "") == "danger"
    local strokeColor = isDanger and Theme.Error or Theme.AccentPrimary
    local duration = tonumber(opts.autoCloseSec) or 15
    local existing = CoreGui:FindFirstChild("UniversalAdmin_RemoteMessage")
    if existing then
        pcall(function() existing:Destroy() end)
    end
    local sg = Instance.new("ScreenGui")
    sg.Name = "UniversalAdmin_RemoteMessage"
    sg.ResetOnSpawn = false
    sg.IgnoreGuiInset = true
    sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    sg.DisplayOrder = 2000000100
    sg.Parent = CoreGui

    local box = Instance.new("Frame")
    box.AnchorPoint = Vector2.new(0.5, 0.5)
    box.Position = UDim2.new(0.5, 0, 0.5, 0)
    box.Size = UDim2.new(0, 520, 0, 0)
    box.BackgroundColor3 = Theme.Surface
    box.BackgroundTransparency = 0.05
    box.BorderSizePixel = 0
    box.Parent = sg
    local bc = Instance.new("UICorner")
    bc.CornerRadius = UDim.new(0, 12)
    bc.Parent = box
    local bs = Instance.new("UIStroke")
    bs.Color = strokeColor
    bs.Thickness = 1.5
    bs.Transparency = 0.25
    bs.Parent = box

    local title = Instance.new("TextLabel")
    title.AnchorPoint = Vector2.new(0.5, 0)
    title.Position = UDim2.new(0.5, 0, 0, 12)
    title.Size = UDim2.new(1, -80, 0, 22)
    title.BackgroundTransparency = 1
    title.Text = titleText
    title.TextColor3 = Theme.Text
    title.TextSize = 18
    title.Font = Theme.FontBold
    title.TextXAlignment = Enum.TextXAlignment.Center
    title.Parent = box

    local meta = Instance.new("TextLabel")
    meta.AnchorPoint = Vector2.new(0.5, 0)
    meta.Position = UDim2.new(0.5, 0, 0, 35)
    meta.Size = UDim2.new(1, -80, 0, 16)
    meta.BackgroundTransparency = 1
    meta.Text = senderText and ("From: " .. senderText) or ""
    meta.TextColor3 = Theme.TextMuted
    meta.TextSize = 11
    meta.Font = Theme.Font
    meta.TextXAlignment = Enum.TextXAlignment.Center
    meta.Parent = box

    local closeBtn = Instance.new("TextButton")
    closeBtn.AnchorPoint = Vector2.new(1, 0)
    closeBtn.Position = UDim2.new(1, -10, 0, 8)
    closeBtn.Size = UDim2.new(0, 24, 0, 24)
    closeBtn.BackgroundTransparency = 1
    closeBtn.Text = "X"
    closeBtn.TextColor3 = Theme.TextMuted
    closeBtn.TextSize = 14
    closeBtn.Font = Theme.FontBold
    closeBtn.Parent = box

    local lbl = Instance.new("TextLabel")
    lbl.AnchorPoint = Vector2.new(0.5, 0)
    lbl.Position = UDim2.new(0.5, 0, 0, 56)
    lbl.Size = UDim2.new(1, -30, 0, 72)
    lbl.BackgroundTransparency = 1
    lbl.Text = msg
    lbl.TextWrapped = true
    lbl.TextXAlignment = Enum.TextXAlignment.Center
    lbl.TextYAlignment = Enum.TextYAlignment.Top
    lbl.TextColor3 = Theme.Text
    lbl.TextSize = 16
    lbl.Font = Theme.Font
    lbl.Parent = box

    local closed = false
    local function closeNow()
        if closed then return end
        closed = true
        local out = TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
        tween(box, out, { Size = UDim2.new(0, 520, 0, 0), BackgroundTransparency = 1 })
        tween(title, out, { TextTransparency = 1 })
        tween(meta, out, { TextTransparency = 1 })
        tween(closeBtn, out, { TextTransparency = 1 })
        tween(lbl, out, { TextTransparency = 1 })
        task.delay(0.22, function()
            if sg and sg.Parent then
                sg:Destroy()
            end
        end)
    end

    closeBtn.MouseButton1Click:Connect(closeNow)

    tween(box, TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Size = UDim2.new(0, 520, 0, 140) })

    -- Typewriter reveal animation
    pcall(function()
        local len = utf8.len(msg) or #msg
        lbl.MaxVisibleGraphemes = 0
        for i = 1, len do
            if closed then break end
            lbl.MaxVisibleGraphemes = i
            task.wait(0.018)
        end
    end)

    task.delay(duration, closeNow)
end

local function startUpdateWatcher()
    if updateWatcherStarted then
        return
    end
    updateWatcherStarted = true
    task.spawn(function()
        task.wait(4)
        while UA_RUNTIME.active do
            pcall(function()
                checkForScriptUpdate()
            end)
            task.wait(120)
        end
    end)
end

local function refreshAuthTokenViaSavedKey()
    if type(persistedConfig.loginUser) ~= "string" or persistedConfig.loginUser == "" then
        return false
    end
    local data, err, banCode = postJsonAuth(AUTH_API_BASE .. "/auth/script-login-key", {
        username = persistedConfig.loginUser,
        key = persistedConfig.loginKey,
        hwid = getClientHwid(),
    })
    if banCode == "ACCESS_BANNED" or banCode == "LOGIN_LOCKOUT" then
        return false
    end
    if data and data.ok == true and type(data.token) == "string" and data.token ~= "" then
        persistedConfig.authToken = data.token
        if data.tier then
            persistedConfig.accountTier = data.tier
        end
        if data.expiresAt then
            persistedConfig.accountExpiresAt = tostring(data.expiresAt)
        end
        savePersistedConfig()
        pcall(function()
            if broadcastPresence then broadcastPresence() end
            if refreshNametags then refreshNametags() end
        end)
        return true
    end
    return false
end

local function getClientHwid()
    local candidates = {
        gethwid,
        (syn and syn.gethwid),
        (krnl and krnl.gethwid),
        (fluxus and fluxus.gethwid),
        (getexecutorhwid),
    }
    for _, fn in ipairs(candidates) do
        if type(fn) == "function" then
            local ok, value = pcall(fn)
            if ok and value ~= nil then
                local s = tostring(value)
                if s ~= "" then
                    return s
                end
            end
        end
    end
    return nil
end

local function fetchScriptAccessStatus()
    local data, _err = postJson(AUTH_API_BASE .. "/auth/access-status", {
        hwid = getClientHwid(),
    })
    if type(data) ~= "table" or data.ok ~= true then
        return { canLogin = true }
    end
    if data.canLogin == false then
        return data
    end
    return { canLogin = true }
end

local function ackRemoteCommand(tok, cmdId, okAck, errText)
    if type(cmdId) ~= "number" then
        return
    end
    authHttpJson("POST", AUTH_API_BASE .. "/client/ack", tok, {
        token = tok,
        commandId = cmdId,
        status = okAck and "ok" or "error",
        error = errText and tostring(errText) or nil,
    })
end

local function remoteAdminBridgeTick(tok)
    local base = AUTH_API_BASE
    local data, err = authHttpJson("POST", base .. "/client/commands", tok, { token = tok })
    if err and string.find(err, "HTTP 401", 1, true) then
        if refreshAuthTokenViaSavedKey() then
            tok = persistedConfig.authToken
            data, err = authHttpJson("POST", base .. "/client/commands", tok, { token = tok })
        else
            return
        end
    end
    if err or not data or type(data.commands) ~= "table" then
        return
    end
    for _, cmd in ipairs(data.commands) do
        if type(cmd) == "table" then
            local cmdId = tonumber(cmd.id)
            if cmd.action == "kick" then
                ackRemoteCommand(tok, cmdId, true, nil)
                LocalPlayer:Kick("Removed by Universal Admin (Discord)")
                return
            elseif (cmd.action == "message" or cmd.action == "warn") and type(cmd.payload) == "table" then
                local okShow, showErr = pcall(function()
                    showCenterAdminMessage(cmd.payload)
                end)
                ackRemoteCommand(tok, cmdId, okShow, okShow and nil or showErr)
            elseif cmd.action == "ua_bring" and type(cmd.payload) == "table" then
                local okBring, bringErr = pcall(function()
                    local targetName = tostring(cmd.payload.destinationUsername or "")
                    local target = Players:FindFirstChild(targetName)
                    local myChar = LocalPlayer.Character
                    local myHrp = myChar and myChar:FindFirstChild("HumanoidRootPart")
                    local toChar = target and target.Character
                    local toHrp = toChar and toChar:FindFirstChild("HumanoidRootPart")
                    if not myHrp or not toHrp then
                        error("bring target missing character")
                    end
                    myHrp.CFrame = toHrp.CFrame * CFrame.new(0, 0, 3)
                end)
                ackRemoteCommand(tok, cmdId, okBring, okBring and nil or bringErr)
            elseif cmd.action == "ua_freeze" and type(cmd.payload) == "table" then
                local okFreeze, freezeErr = pcall(function()
                    local sec = tonumber(cmd.payload.durationSec) or 6
                    peerOps.startLocalFreeze(sec)
                end)
                ackRemoteCommand(tok, cmdId, okFreeze, okFreeze and nil or freezeErr)
            elseif cmd.action == "ua_fling" and type(cmd.payload) == "table" then
                local okFling, flingErr = pcall(function()
                    local p = tonumber(cmd.payload.power) or 1800
                    for _ = 1, 6 do
                        peerOps.runLocalVelocityFling(p)
                        task.wait(0.035)
                    end
                end)
                ackRemoteCommand(tok, cmdId, okFling, okFling and nil or flingErr)
            elseif cmd.action == "ua_loopfling_start" and type(cmd.payload) == "table" then
                local okLoop, loopErr = pcall(function()
                    peerOps.startRemoteInfiniteLoopFling(tonumber(cmd.payload.power) or 1800)
                end)
                ackRemoteCommand(tok, cmdId, okLoop, okLoop and nil or loopErr)
            elseif cmd.action == "ua_loopfling_stop" then
                local okStop, stopErr = pcall(function()
                    peerOps.stopRemoteInfiniteLoopFling()
                end)
                ackRemoteCommand(tok, cmdId, okStop, okStop and nil or stopErr)
            elseif cmd.action == "ua_loopfling" and type(cmd.payload) == "table" then
                local okLoop, loopErr = pcall(function()
                    peerOps.startLocalPeerLoopFling(tonumber(cmd.payload.durationSec) or 4, tonumber(cmd.payload.power) or 300)
                end)
                ackRemoteCommand(tok, cmdId, okLoop, okLoop and nil or loopErr)
            elseif cmd.action == "ua_kill" then
                local okKill, killErr = pcall(function()
                    local char = LocalPlayer.Character
                    local hum = char and char:FindFirstChildOfClass("Humanoid")
                    if hum then
                        hum.Health = 0
                    elseif char then
                        char:BreakJoints()
                    else
                        error("missing character")
                    end
                end)
                ackRemoteCommand(tok, cmdId, okKill, okKill and nil or killErr)
            elseif cmd.action == "friend_join_request" and type(cmd.payload) == "table" then
                local okShow, showErr = pcall(function()
                    showJoinRequestPopup(cmd.payload, tok, cmdId)
                end)
                ackRemoteCommand(tok, cmdId, okShow, okShow and nil or showErr)
            elseif cmd.action == "friend_join_response" and type(cmd.payload) == "table" then
                local okHandle, handleErr = pcall(function()
                    handleJoinResponse(cmd.payload)
                end)
                ackRemoteCommand(tok, cmdId, okHandle, okHandle and nil or handleErr)
            else
                ackRemoteCommand(tok, cmdId, false, "unknown action")
            end
        end
    end
end

local function startRemoteAdminBridge()
    if remoteAdminBridgeStarted then
        return
    end
    if type(persistedConfig.authToken) ~= "string" or persistedConfig.authToken == "" then
        if not refreshAuthTokenViaSavedKey() then
            return
        end
    end
    remoteAdminBridgeStarted = true
    task.spawn(function()
        task.wait(0.05)
        local lastPresenceAt = 0
        local lastCommandsAt = 0
        local lastTokenRefreshAt = os.clock()
        while UA_RUNTIME.active do
            local tok = persistedConfig.authToken
            if type(tok) ~= "string" or tok == "" then
                pcall(function()
                    refreshAuthTokenViaSavedKey()
                end)
                tok = persistedConfig.authToken
            end
            if type(tok) ~= "string" or tok == "" then
                task.wait(10)
                continue
            end
            local now = os.clock()
            if now - lastTokenRefreshAt >= (45 * 60) then
                pcall(function()
                    if refreshAuthTokenViaSavedKey() then
                        lastTokenRefreshAt = now
                    end
                end)
                tok = persistedConfig.authToken
            end
            if now - lastPresenceAt >= 1.5 then
                pcall(function()
                    local pData, pErr = authHttpJson("POST", AUTH_API_BASE .. "/client/presence", tok, {
                        token = tok,
                        robloxUserId = tostring(LocalPlayer.UserId),
                        robloxUsername = tostring(LocalPlayer.Name),
                        placeId = tostring(game.PlaceId),
                        gameId = tostring(game.JobId),
                        hwid = getClientHwid(),
                        accentPrimary = encodeAccentColor(Theme.AccentPrimary),
                    })
                    if pData and type(pData.peers) == "table" and applyServerPresenceRoster then
                        uaLivePeersCache = pData.peers
                        applyServerPresenceRoster(pData.peers)
                        if refreshNametags then refreshNametags() end
                    end
                    if pErr and string.find(pErr, "HTTP 401", 1, true) then
                        refreshAuthTokenViaSavedKey()
                    end
                end)
                lastPresenceAt = now
            end
            if now - lastCommandsAt >= 0.35 then
                pcall(function()
                    remoteAdminBridgeTick(tok)
                end)
                lastCommandsAt = now
            end
            task.wait(0.1)
        end
        pcall(function()
            local tok = persistedConfig.authToken
            if type(tok) == "string" and tok ~= "" then
                authHttpJson("POST", AUTH_API_BASE .. "/session/end", tok, {
                    token = tok,
                })
            end
        end)
        uaLivePeersCache = {}
        pcall(function()
            if applyServerPresenceRoster then applyServerPresenceRoster({}) end
            if refreshNametags then refreshNametags() end
        end)
        remoteAdminBridgeStarted = false
    end)
end

local function scriptAuthLogin(username, password)
    local data, err, code = postJsonAuth(AUTH_API_BASE .. "/auth/script-login", {
        username = username,
        password = password,
        hwid = getClientHwid(),
    })
    if not data then
        return false, err or "Auth failed", code
    end
    return true, data, nil
end

-- Separate function so showLoginScreen does not exceed Luau local register limits.
local function fadeOutLoginCard(L, onSuccess, userName)
    local fadeDur = 0.32
    local fadeOut = TweenInfo.new(fadeDur, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
    local card, back, loginGui, submitBtn = L.card, L.back, L.loginGui, L.submitBtn
    for _, d in ipairs(card:GetDescendants()) do
        if d:IsA("UIGradient") then
            pcall(function()
                tween(d, fadeOut, { Transparency = NumberSequence.new(1) })
            end)
        end
    end
    for _, d in ipairs(card:GetDescendants()) do
        pcall(function()
            if d:IsA("UIGradient") then
                return
            end
            if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
                tween(d, fadeOut, { TextTransparency = 1, BackgroundTransparency = 1 })
            elseif d:IsA("Frame") then
                tween(d, fadeOut, { BackgroundTransparency = 1 })
            elseif d:IsA("UIStroke") then
                tween(d, fadeOut, { Transparency = 1 })
            elseif d:IsA("ImageLabel") then
                tween(d, fadeOut, { ImageTransparency = 1, BackgroundTransparency = 1 })
            end
        end)
    end
    tween(card, fadeOut, {
        BackgroundTransparency = 1,
        Size = UDim2.new(0, 420, 0, 400),
    })
    local cardStroke = card:FindFirstChildOfClass("UIStroke")
    if cardStroke then
        tween(cardStroke, fadeOut, { Transparency = 1 })
    end
    task.delay(fadeDur, function()
        submitBtn.Visible = false
        tween(back, fadeOut, {
            BackgroundTransparency = 1,
        })
        for _, d in ipairs(back:GetChildren()) do
            if d:IsA("Frame") then
                tween(d, fadeOut, { BackgroundTransparency = 1 })
            end
        end
        task.delay(fadeDur, function()
            if loginGui.Parent then loginGui:Destroy() end
            if onSuccess then onSuccess(userName) end
        end)
    end)
end

local function dismissWelcomeBackAfterDelay(wbGui, card, onDone, savedUser)
    task.delay(1.5, function()
        local fadeOut = TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
        for _, ch in ipairs(card:GetDescendants()) do
            pcall(function()
                if ch:IsA("TextLabel") then
                    tween(ch, fadeOut, { TextTransparency = 1, BackgroundTransparency = 1 })
                elseif ch:IsA("ImageLabel") then
                    tween(ch, fadeOut, { ImageTransparency = 1, BackgroundTransparency = 1 })
                elseif ch:IsA("Frame") then
                    tween(ch, fadeOut, { BackgroundTransparency = 1 })
                elseif ch:IsA("UIStroke") then
                    tween(ch, fadeOut, { Transparency = 1 })
                elseif ch:IsA("UIGradient") then
                    tween(ch, fadeOut, { Transparency = NumberSequence.new(1) })
                end
            end)
        end
        tween(card, fadeOut, {
            BackgroundTransparency = 1,
            Size = UDim2.new(0, 320, 0, 150),
        })
        local cs = card:FindFirstChildOfClass("UIStroke")
        if cs then tween(cs, fadeOut, { Transparency = 1 }) end
        task.delay(0.3, function()
            if wbGui.Parent then wbGui:Destroy() end
            if onDone then onDone(savedUser) end
        end)
    end)
end

-- Each piece is its own function so no single function accumulates 200+ VM registers
-- (Luau counts temporaries from big expressions like ColorSequence.new(...)).
local function loginMkLoginRootGui()
    local g = Instance.new("ScreenGui")
    g.Name = "UniversalAdmin_Login"
    g.ResetOnSpawn = false
    g.IgnoreGuiInset = true
    g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    g.DisplayOrder = 2000000000
    g.Parent = CoreGui
    return g
end

local function loginMkBackdropWithVeil(gui)
    local back = Instance.new("Frame")
    back.Name = "Backdrop"
    back.Size = UDim2.new(1, 0, 1, 0)
    back.BackgroundColor3 = Color3.fromRGB(8, 8, 14)
    back.BackgroundTransparency = 0
    back.BorderSizePixel = 0
    back.Parent = gui
    local veil = Instance.new("Frame")
    veil.Size = UDim2.new(1, 0, 1, 0)
    veil.BackgroundColor3 = Theme.AccentPrimary
    veil.BackgroundTransparency = 0.95
    veil.BorderSizePixel = 0
    veil.Parent = back
    local vg = Instance.new("UIGradient")
    vg.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Theme.AccentPrimary),
        ColorSequenceKeypoint.new(1, Theme.AccentSecondary),
    })
    vg.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.8),
        NumberSequenceKeypoint.new(1, 1),
    })
    vg.Rotation = 120
    vg.Parent = veil
    return back
end

local function loginMkCenterCard(back)
    local card = Instance.new("Frame")
    card.Name = "Card"
    card.AnchorPoint = Vector2.new(0.5, 0.5)
    card.Position = UDim2.new(0.5, 0, 0.5, 0)
    card.Size = UDim2.new(0, 0, 0, 0)
    card.BackgroundColor3 = Color3.fromRGB(16, 16, 22)
    card.BackgroundTransparency = 0
    card.BorderSizePixel = 0
    card.Parent = back
    local cc = Instance.new("UICorner")
    cc.CornerRadius = UDim.new(0, 14)
    cc.Parent = card
    local cs = Instance.new("UIStroke")
    cs.Color = Theme.AccentPrimary
    cs.Thickness = 1.5
    cs.Transparency = 0.3
    cs.Parent = card
    return card
end

local function loginMkCardTopAccent(card)
    local bar = Instance.new("Frame")
    bar.AnchorPoint = Vector2.new(0.5, 0)
    bar.Size = UDim2.new(1, -40, 0, 2)
    bar.Position = UDim2.new(0.5, 0, 0, 0)
    bar.BorderSizePixel = 0
    bar.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    bar.Parent = card
    local tg = Instance.new("UIGradient")
    tg.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Theme.AccentPrimary),
        ColorSequenceKeypoint.new(0.5, Theme.AccentSecondary),
        ColorSequenceKeypoint.new(1, Theme.AccentPrimary),
    })
    tg.Parent = bar
end

local function loginMkCardTitleLabels(card)
    local t1 = Instance.new("TextLabel")
    t1.Position = UDim2.new(0, 32, 0, 26)
    t1.Size = UDim2.new(1, -64, 0, 26)
    t1.BackgroundTransparency = 1
    t1.Text = "UNIVERSAL ADMIN"
    t1.TextColor3 = Theme.Text
    t1.TextSize = 22
    t1.Font = Theme.FontBold
    t1.TextXAlignment = Enum.TextXAlignment.Left
    t1.Parent = card
    local t2 = Instance.new("TextLabel")
    t2.Position = UDim2.new(0, 32, 0, 52)
    t2.Size = UDim2.new(1, -64, 0, 14)
    t2.BackgroundTransparency = 1
    t2.Text = "Sign in to continue"
    t2.TextColor3 = Theme.TextDim
    t2.TextSize = 11
    t2.Font = Theme.Font
    t2.TextXAlignment = Enum.TextXAlignment.Left
    t2.Parent = card
end

local function loginBuildBackdropAndCard(L)
    L.loginGui = loginMkLoginRootGui()
    L.back = loginMkBackdropWithVeil(L.loginGui)
    L.card = loginMkCenterCard(L.back)
    loginMkCardTopAccent(L.card)
    loginMkCardTitleLabels(L.card)
end

local function loginStyleInputBox(box)
    local cr = Instance.new("UICorner")
    cr.CornerRadius = UDim.new(0, 6)
    cr.Parent = box
    local st = Instance.new("UIStroke")
    st.Color = Theme.Border
    st.Thickness = 1
    st.Transparency = 0.5
    st.Parent = box
    local pd = Instance.new("UIPadding")
    pd.PaddingLeft = UDim.new(0, 10)
    pd.PaddingRight = UDim.new(0, 10)
    pd.Parent = box
end

local function loginBuildUserPassFields(L)
    local ul = Instance.new("TextLabel")
    ul.Position = UDim2.new(0, 32, 0, 88)
    ul.Size = UDim2.new(1, -64, 0, 12)
    ul.BackgroundTransparency = 1
    ul.Text = "USERNAME"
    ul.TextColor3 = Theme.TextDim
    ul.TextSize = 10
    ul.Font = Theme.FontBold
    ul.TextXAlignment = Enum.TextXAlignment.Left
    ul.Parent = L.card

    local ub = Instance.new("TextBox")
    ub.Position = UDim2.new(0, 32, 0, 104)
    ub.Size = UDim2.new(1, -64, 0, 34)
    ub.BackgroundColor3 = Color3.fromRGB(24, 24, 32)
    ub.BorderSizePixel = 0
    ub.Text = ""
    ub.PlaceholderText = "enter username"
    ub.PlaceholderColor3 = Theme.TextMuted
    ub.TextColor3 = Theme.Text
    ub.TextSize = 13
    ub.Font = Theme.FontMono
    ub.TextXAlignment = Enum.TextXAlignment.Left
    ub.ClearTextOnFocus = false
    ub.Parent = L.card
    loginStyleInputBox(ub)
    L.userBox = ub

    local pl = Instance.new("TextLabel")
    pl.Position = UDim2.new(0, 32, 0, 150)
    pl.Size = UDim2.new(1, -64, 0, 12)
    pl.BackgroundTransparency = 1
    pl.Text = "PASSWORD"
    pl.TextColor3 = Theme.TextDim
    pl.TextSize = 10
    pl.Font = Theme.FontBold
    pl.TextXAlignment = Enum.TextXAlignment.Left
    pl.Parent = L.card

    local pb = Instance.new("TextBox")
    pb.Position = UDim2.new(0, 32, 0, 166)
    pb.Size = UDim2.new(1, -64, 0, 34)
    pb.BackgroundColor3 = Color3.fromRGB(24, 24, 32)
    pb.BorderSizePixel = 0
    pb.Text = ""
    pb.PlaceholderText = "enter password"
    pb.PlaceholderColor3 = Theme.TextMuted
    pb.TextColor3 = Theme.Text
    pb.TextSize = 13
    pb.Font = Theme.FontMono
    pb.TextXAlignment = Enum.TextXAlignment.Left
    pb.ClearTextOnFocus = false
    pb.Parent = L.card
    loginStyleInputBox(pb)
    L.passBox = pb
end

local function loginInstallPasswordMask(L)
    local function maskPass()
        L.passBox.Text = string.rep("*", #L.passRealText)
    end
    L.passBox:GetPropertyChangedSignal("Text"):Connect(function()
        local t = L.passBox.Text
        if t == string.rep("*", #L.passRealText) then return end
        if #t < #L.passRealText then
            L.passRealText = L.passRealText:sub(1, #t)
        else
            L.passRealText = L.passRealText .. t:sub(#L.passRealText + 1)
        end
        maskPass()
    end)
end

local function loginDiscordClicked(L)
    L.errLabel.TextColor3 = Theme.TextDim
    if DISCORD_INVITE ~= "" then
        local clip = (setclipboard or (syn and syn.write_clipboard) or (toclipboard) or (writeclipboard))
        if type(clip) == "function" then
            pcall(function()
                clip(DISCORD_INVITE)
            end)
            L.errLabel.Text = "Copied discord link to clipboard"
        else
            L.errLabel.Text = DISCORD_INVITE
        end
    else
        L.errLabel.Text = "Set getgenv().UA_DiscordInvite = \"https://discord.gg/...\" before running"
    end
    if L.accessBlocked and type(L.accessBlockBannerText) == "string" and L.accessBlockBannerText ~= "" then
        task.delay(2, function()
            if L.errLabel and L.errLabel.Parent then
                L.errLabel.TextColor3 = Theme.Error
                L.errLabel.Text = L.accessBlockBannerText
            end
        end)
        return
    end
    task.delay(3, function()
        if L.errLabel and L.errLabel.Parent then
            L.errLabel.Text = ""
            L.errLabel.TextColor3 = Theme.Error
        end
    end)
end

local function loginUnloadClicked(L)
    tween(L.card, smoothOut, { BackgroundTransparency = 1 })
    for _, d in ipairs(L.card:GetDescendants()) do
        pcall(function()
            if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
                tween(d, smoothOut, { TextTransparency = 1, BackgroundTransparency = 1 })
            elseif d:IsA("Frame") then
                tween(d, smoothOut, { BackgroundTransparency = 1 })
            elseif d:IsA("UIStroke") then
                tween(d, smoothOut, { Transparency = 1 })
            end
        end)
    end
    task.delay(0.3, function()
        tween(L.back, smoothOut, { BackgroundTransparency = 1 })
        task.delay(0.3, function()
            if L.loginGui.Parent then L.loginGui:Destroy() end
            pcall(function()
                if nametagState and nametagState.tags then
                    for _, tag in pairs(nametagState.tags) do
                        if tag and tag.Parent then tag:Destroy() end
                    end
                    nametagState.tags = {}
                end
            end)
            pcall(function()
                for _, player in ipairs(Players:GetPlayers()) do
                    local char = player.Character
                    if char then
                        for _, d in ipairs(char:GetDescendants()) do
                            if d:IsA("BillboardGui") and d.Name:sub(1, 3) == "UA_" then
                                d:Destroy()
                            end
                        end
                    end
                end
            end)
            pcall(function() if CoreGui:FindFirstChild("UniversalAdmin") then CoreGui.UniversalAdmin:Destroy() end end)
            for _, child in ipairs(CoreGui:GetChildren()) do
                if child.Name:sub(1, 15) == "UniversalAdmin" then
                    pcall(function() child:Destroy() end)
                end
            end
        end)
    end)
end

local function loginBuildErrAndSubmit(L)
    local el = Instance.new("TextLabel")
    el.Position = UDim2.new(0, 32, 0, 208)
    el.Size = UDim2.new(1, -64, 0, 14)
    el.BackgroundTransparency = 1
    el.Text = ""
    el.TextColor3 = Theme.Error
    el.TextSize = 11
    el.Font = Theme.Font
    el.TextXAlignment = Enum.TextXAlignment.Left
    el.TextWrapped = true
    el.Parent = L.card
    L.errLabel = el

    local sb = Instance.new("TextButton")
    sb.Position = UDim2.new(0, 32, 0, 230)
    sb.Size = UDim2.new(1, -64, 0, 38)
    sb.BackgroundColor3 = Theme.AccentPrimary
    sb.BackgroundTransparency = 0.1
    sb.BorderSizePixel = 0
    sb.AutoButtonColor = false
    sb.Text = "LOGIN"
    sb.TextColor3 = Theme.Text
    sb.TextSize = 13
    sb.Font = Theme.FontBold
    sb.Parent = L.card
    L.submitBtn = sb
    local sbc = Instance.new("UICorner")
    sbc.CornerRadius = UDim.new(0, 6)
    sbc.Parent = sb
    local sbs = Instance.new("UIStroke")
    sbs.Color = Theme.AccentPrimary
    sbs.Thickness = 1
    sbs.Transparency = 0.2
    sbs.Parent = sb
    local sbg = Instance.new("UIGradient")
    sbg.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Theme.AccentPrimary),
        ColorSequenceKeypoint.new(1, Theme.AccentSecondary),
    })
    sbg.Rotation = 45
    sbg.Parent = sb
end

local function loginBuildDiscordUnloadFooter(L)
    local hint = Instance.new("TextLabel")
    hint.Position = UDim2.new(0, 32, 0, 282)
    hint.Size = UDim2.new(1, -64, 0, 12)
    hint.BackgroundTransparency = 1
    hint.Text = "Join our Discord to create an account & get a key"
    hint.TextColor3 = Theme.TextMuted
    hint.TextSize = 10
    hint.Font = Theme.Font
    hint.TextXAlignment = Enum.TextXAlignment.Left
    hint.Parent = L.card
    L.joinHint = hint

    local db = Instance.new("TextButton")
    db.Position = UDim2.new(0, 32, 0, 300)
    db.Size = UDim2.new(0.5, -36, 0, 30)
    db.BackgroundColor3 = Color3.fromRGB(88, 101, 242)
    db.BackgroundTransparency = 0.1
    db.BorderSizePixel = 0
    db.AutoButtonColor = false
    db.Text = "Join Discord"
    db.TextColor3 = Color3.fromRGB(255, 255, 255)
    db.TextSize = 12
    db.Font = Theme.FontBold
    db.Parent = L.card
    L.discordBtn = db
    local dbc = Instance.new("UICorner")
    dbc.CornerRadius = UDim.new(0, 6)
    dbc.Parent = db

    local ub = Instance.new("TextButton")
    ub.Position = UDim2.new(0.5, 4, 0, 300)
    ub.Size = UDim2.new(0.5, -36, 0, 30)
    ub.BackgroundColor3 = Theme.Surface
    ub.BackgroundTransparency = 0.1
    ub.BorderSizePixel = 0
    ub.AutoButtonColor = false
    ub.Text = "Unload"
    ub.TextColor3 = Theme.TextDim
    ub.TextSize = 12
    ub.Font = Theme.FontBold
    ub.Parent = L.card
    L.unloadBtn = ub
    local ubc = Instance.new("UICorner")
    ubc.CornerRadius = UDim.new(0, 6)
    ubc.Parent = ub
    local ubs = Instance.new("UIStroke")
    ubs.Color = Theme.Border
    ubs.Thickness = 1
    ubs.Transparency = 0.5
    ubs.Parent = ub

    local foot = Instance.new("TextLabel")
    foot.Position = UDim2.new(0, 32, 0, 344)
    foot.Size = UDim2.new(1, -64, 0, 12)
    foot.BackgroundTransparency = 1
    foot.Text = "v1.0 · Discord key-auth (Railway)"
    foot.TextColor3 = Theme.TextMuted
    foot.TextSize = 10
    foot.Font = Theme.Font
    foot.TextXAlignment = Enum.TextXAlignment.Left
    foot.Parent = L.card
end

local function loginApplyHardwareBlock(L, message, code)
    if not L then
        return
    end
    L.accessBlocked = true
    L.submitted = false
    local msg = tostring(message or "Access denied")
    if code == "ACCESS_BANNED" and DISCORD_INVITE ~= "" then
        msg = msg .. "\n\nAppeal in Discord: " .. DISCORD_INVITE
    end
    L.accessBlockBannerText = msg
    if L.joinHint then
        L.joinHint.Visible = false
    end
    L.errLabel.TextWrapped = true
    L.errLabel.Position = UDim2.new(0, 32, 0, 190)
    L.errLabel.Size = UDim2.new(1, -64, 0, 76)
    L.errLabel.Text = msg
    L.errLabel.TextColor3 = Theme.Error
    L.userBox.TextEditable = false
    L.passBox.TextEditable = false
    L.userBox.BackgroundColor3 = Color3.fromRGB(40, 40, 48)
    L.passBox.BackgroundColor3 = Color3.fromRGB(40, 40, 48)
    L.userBox.TextTransparency = 0.4
    L.passBox.TextTransparency = 0.4
    L.submitBtn.Text = "BLOCKED"
    L.submitBtn.Position = UDim2.new(0, 32, 0, 276)
    L.submitBtn.AutoButtonColor = false
    pcall(function()
        L.submitBtn.Active = false
    end)
    tween(L.submitBtn, quickTween, { BackgroundTransparency = 0.55 })
    if L.discordBtn then
        L.discordBtn.Position = UDim2.new(0, 32, 0, 326)
    end
    if L.unloadBtn then
        L.unloadBtn.Position = UDim2.new(0.5, 4, 0, 326)
    end
end

local function loginRunAuthRequest(L, onSuccess, user, pass)
    local okAuth, authResult, authCode = scriptAuthLogin(user, pass)
    if not okAuth then
        L.submitted = false
        clearSavedLogin()
        if authCode == "ACCESS_BANNED" or authCode == "LOGIN_LOCKOUT" then
            loginApplyHardwareBlock(L, authResult, authCode)
            return
        end
        L.submitBtn.Text = "LOGIN"
        L.userBox.TextEditable = true
        L.passBox.TextEditable = true
        L.errLabel.TextColor3 = Theme.Error
        L.errLabel.Text = tostring(authResult or "Invalid account/password")
        return
    end
    local displayName = (persistedConfig.nickname and persistedConfig.nickname ~= "") and persistedConfig.nickname or user
    L.submitBtn.Text = "Welcome, " .. displayName .. "!"
    tween(L.submitBtn, quickTween, { BackgroundColor3 = Theme.Success })
    persistedConfig.loginUser = user
    persistedConfig.loginKey = tostring(authResult.key or "")
    persistedConfig.accountTier = authResult.tier or "Member"
    persistedConfig.accountExpiresAt = authResult.expiresAt and tostring(authResult.expiresAt) or nil
    if type(authResult.token) == "string" and authResult.token ~= "" then
        persistedConfig.authToken = authResult.token
    end
    savePersistedConfig()
    pcall(function()
        if broadcastPresence then broadcastPresence() end
        if refreshNametags then refreshNametags() end
    end)
    local submitStroke = L.submitBtn:FindFirstChildOfClass("UIStroke")
    if submitStroke then
        tween(submitStroke, quickTween, { Color = Theme.Success })
    end
    task.delay(1.0, function()
        fadeOutLoginCard(L, onSuccess, user)
    end)
end

local function loginAttemptAuth(L, onSuccess)
    if L.accessBlocked then
        return
    end
    if L.submitted then return end
    local user = L.userBox.Text
    local pass = L.passRealText
    if #user == 0 then
        L.errLabel.TextColor3 = Theme.Error
        L.errLabel.Text = "Username required"
        return
    end
    if #pass == 0 then
        L.errLabel.TextColor3 = Theme.Error
        L.errLabel.Text = "Password required"
        return
    end
    L.submitted = true
    L.errLabel.Text = ""
    L.submitBtn.Text = "VERIFYING..."
    L.userBox.TextEditable = false
    L.passBox.TextEditable = false
    task.spawn(function()
        loginRunAuthRequest(L, onSuccess, user, pass)
    end)
end

local function loginWireSubmitHover(L)
    L.submitBtn.MouseEnter:Connect(function()
        tween(L.submitBtn, quickTween, { BackgroundTransparency = 0 })
    end)
    L.submitBtn.MouseLeave:Connect(function()
        tween(L.submitBtn, quickTween, { BackgroundTransparency = 0.1 })
    end)
end

local function loginWireDiscordHover(L)
    L.discordBtn.MouseEnter:Connect(function()
        tween(L.discordBtn, quickTween, { BackgroundTransparency = 0 })
    end)
    L.discordBtn.MouseLeave:Connect(function()
        tween(L.discordBtn, quickTween, { BackgroundTransparency = 0.1 })
    end)
    L.discordBtn.MouseButton1Click:Connect(function()
        loginDiscordClicked(L)
    end)
end

local function loginWireUnloadHover(L)
    L.unloadBtn.MouseEnter:Connect(function()
        tween(L.unloadBtn, quickTween, { BackgroundColor3 = Theme.Error, BackgroundTransparency = 0.2 })
        tween(L.unloadBtn, quickTween, { TextColor3 = Theme.Text })
    end)
    L.unloadBtn.MouseLeave:Connect(function()
        tween(L.unloadBtn, quickTween, { BackgroundColor3 = Theme.Surface, BackgroundTransparency = 0.1 })
        tween(L.unloadBtn, quickTween, { TextColor3 = Theme.TextDim })
    end)
    L.unloadBtn.MouseButton1Click:Connect(function()
        loginUnloadClicked(L)
    end)
end

local function loginWireSubmitAndFocus(L, onSuccess)
    L.submitBtn.MouseButton1Click:Connect(function()
        loginAttemptAuth(L, onSuccess)
    end)
    L.userBox.FocusLost:Connect(function(enter)
        if enter then L.passBox:CaptureFocus() end
    end)
    L.passBox.FocusLost:Connect(function(enter)
        if enter then loginAttemptAuth(L, onSuccess) end
    end)
end

local function loginWireAnimateIn(L)
    local ti = TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
    tween(L.card, ti, { Size = UDim2.new(0, 400, 0, 380) })
    task.delay(0.3, function()
        L.userBox:CaptureFocus()
    end)
end

local function loginWireEvents(L, onSuccess)
    loginWireSubmitHover(L)
    loginWireDiscordHover(L)
    loginWireUnloadHover(L)
    loginWireSubmitAndFocus(L, onSuccess)
    loginWireAnimateIn(L)
end

local function showLoginScreen(onSuccess)
    pcall(function() TopBar.Visible = false end); pcall(function() MainFrame.Visible = false end); pcall(function() Backdrop.Visible = false end)
    local L = { passRealText = "", submitted = false, accessBlocked = false }
    loginBuildBackdropAndCard(L)
    loginBuildUserPassFields(L)
    loginInstallPasswordMask(L)
    loginBuildErrAndSubmit(L)
    loginBuildDiscordUnloadFooter(L)
    loginWireEvents(L, onSuccess)
    task.defer(function()
        local st = fetchScriptAccessStatus()
        if type(st) == "table" and st.canLogin == false then
            loginApplyHardwareBlock(L, st.message, st.code)
        end
    end)
end

-------------------------------------------------
-- SETTINGS SYNC (cloud sync via auth API)
-------------------------------------------------
local SYNC_EXCLUDE_KEYS = {
    loginUser = true,
    loginKey = true,
    authToken = true,
    scriptFingerprint = true,
}

local _syncDebounce = { lastPush = 0, pending = false, minInterval = 30 }

local function _getSyncPayload()
    local payload = {}
    for k, v in pairs(persistedConfig) do
        if not SYNC_EXCLUDE_KEYS[k] then
            payload[k] = v
        end
    end
    payload.settingsUpdatedAt = os.time()
    return payload
end

local function syncSettingsToServer()
    local tok = persistedConfig.authToken
    if type(tok) ~= "string" or tok == "" then return end
    local fn = authHttpJson
    local base = AUTH_API_BASE
    if not fn or not base then return end

    local payload = _getSyncPayload()
    pcall(function()
        fn("POST", base .. "/client/settings", tok, payload)
    end)
end

local function syncSettingsFromServer()
    local tok = persistedConfig.authToken
    if type(tok) ~= "string" or tok == "" then return nil, "Not authenticated" end
    local fn = authHttpJson
    local base = AUTH_API_BASE
    if not fn or not base then return nil, "API not ready" end

    local data, err = fn("GET", base .. "/client/settings", tok, nil)
    if not data or err then
        return nil, err
    end

    local serverTime = tonumber(data.settingsUpdatedAt) or 0
    local localTime = tonumber(persistedConfig.settingsUpdatedAt) or 0

    if serverTime > localTime and type(data.settings) == "table" then
        for k, v in pairs(data.settings) do
            if not SYNC_EXCLUDE_KEYS[k] then
                persistedConfig[k] = v
            end
        end
        persistedConfig.settingsUpdatedAt = serverTime
        savePersistedConfig()
        return true, "Server settings applied"
    elseif serverTime <= localTime then
        syncSettingsToServer()
        return true, "Local settings synced"
    end
    return true
end

local function _requestSettingsSync()
    local tok = persistedConfig.authToken
    if type(tok) ~= "string" or tok == "" then return end

    local now = os.clock()
    if now - _syncDebounce.lastPush < _syncDebounce.minInterval then
        if not _syncDebounce.pending then
            _syncDebounce.pending = true
            task.delay(_syncDebounce.minInterval, function()
                _syncDebounce.pending = false
                _syncDebounce.lastPush = os.clock()
                syncSettingsToServer()
            end)
        end
        return
    end
    _syncDebounce.lastPush = now
    syncSettingsToServer()
end
UA_RUNTIME._requestSettingsSync = _requestSettingsSync

local function revealMainUI(username)
    -- Store auth context in _G for Admin.lua (fast in-memory path)
    _G.UA_AuthContext = {
        token = persistedConfig.authToken,
        username = persistedConfig.loginUser or username,
        tier = persistedConfig.accountTier or "Member",
        expiresAt = persistedConfig.accountExpiresAt,
        key = persistedConfig.loginKey,
    }

    -- Fetch and execute the protected Admin.lua
    task.spawn(function()
        local adminUrl = CONFIG.AdminScriptUrl
        if type(persistedConfig.authToken) == "string" and persistedConfig.authToken ~= "" then
            adminUrl = adminUrl .. "?token=" .. persistedConfig.authToken
        end

        local reqFn = getRequestFn()
        if not reqFn then
            warn("UA Loader: No HTTP function available to fetch Admin.lua")
            return
        end

        local ok, res = pcall(function()
            return reqFn({ Url = adminUrl, Method = "GET" })
        end)
        if not ok or not res or tonumber(res.StatusCode) ~= 200 then
            local errMsg = res and tostring(res.Body or res.StatusCode or "unknown") or "request failed"
            warn("UA Loader: Failed to fetch Admin.lua: " .. errMsg)
            if res and tonumber(res.StatusCode) == 401 then
                clearSavedLogin()
            end
            return
        end

        local adminSource = tostring(res.Body or "")
        if adminSource == "" then
            warn("UA Loader: Empty Admin.lua response")
            return
        end

        local loadOk, loadErr = pcall(function()
            loadstring(adminSource)()
        end)
        if not loadOk then
            warn("UA Loader: Admin.lua execution failed: " .. tostring(loadErr))
        end
    end)
end

-- Decide: show full login or "welcome back" depending on saved state.
local function _uaRunLoginFlow()
    startUpdateWatcher()
    if type(persistedConfig.loginUser) == "string" and #persistedConfig.loginUser > 0 then
        local okSaved = false
        pcall(function()
            local data, err, banCode = postJsonAuth(AUTH_API_BASE .. "/auth/script-login-key", {
                username = persistedConfig.loginUser,
                key = persistedConfig.loginKey,
                hwid = getClientHwid(),
            })
            if banCode == "ACCESS_BANNED" or banCode == "LOGIN_LOCKOUT" then
                clearSavedLogin()
                okSaved = false
                return
            end
            if data and data.ok == true then
                if data.tier then
                    persistedConfig.accountTier = data.tier
                end
                if data.expiresAt then
                    persistedConfig.accountExpiresAt = tostring(data.expiresAt)
                end
                if type(data.token) == "string" and data.token ~= "" then
                    persistedConfig.authToken = data.token
                end
                savePersistedConfig()
                pcall(function()
                    if broadcastPresence then broadcastPresence() end
                    if refreshNametags then refreshNametags() end
                end)
            end
            okSaved = data and data.ok == true and not err
        end)
        if okSaved then
            -- Start bridge immediately on saved-login path (before welcome card dismiss)
            -- so /kick and /message can hit as soon as possible.
            revealMainUI(persistedConfig.loginUser)
        else
            clearSavedLogin()
            showLoginScreen(revealMainUI)
        end
    else
        showLoginScreen(revealMainUI)
    end
end
_uaRunLoginFlow()
end)()

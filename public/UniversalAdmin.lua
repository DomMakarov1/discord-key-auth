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

    -- If your executor supports queue_on_teleport, set this to the
    -- HttpGet loader URL for this script. `;rejoin` will re-execute the
    -- same loader after you land in the new server.
    -- Raw script URL for auto-reexec after rejoin. Your auth API serves GET /UniversalAdmin.lua
    -- (see discord-key-auth). Set to "" to skip HttpGet (still queues _G.UA_Source if you set it).
    LoaderUrl = "https://discord-key-auth-production.up.railway.app/UniversalAdmin.lua",

    -- Top bar center image: Roblox decal asset id (Creator Dashboard URL number).
    AdminTopBarDecalId = 124242419648785,

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

-- UTILITY
-------------------------------------------------
local Theme = CONFIG.Theme

local function tierToDisplayLabel(tier)
    if tier == "Premium" then
        return "Premium"
    end
    if tier == "Member" or tier == nil or tier == "" then
        return "Standard User"
    end
    return tostring(tier)
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
    flyHotkey     = nil,
    noclipHotkey  = nil,
    clickFlingBind = nil,
    clickFlingTriggerBind = nil,
    clickFlingFov  = nil,
    clickFlingMode = nil,
    topBarPos     = nil,  -- { xScale, xOffset, yScale, yOffset }
    loginUser     = nil,  -- username string; when set, skip login & show "Welcome back"
    loginKey      = nil,  -- script auth key tied to loginUser
    accountTier   = nil,  -- API tier string (e.g. Member); shown as "Standard User" in UI
    hotkeyAlwaysActive = {},  -- { fly = true, noclip = true, ... }
}

-- Per-command "always active hotkey" tracking.
-- When false, the hotkey only works while the panel is open or the feature is on.
-- Commands without panels (camlock, blink) default to always-active.
local hotkeyAlwaysActive = { camlock = true, blink = true }

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

local smoothIn  = TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local smoothOut = TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
local quickTween = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- Sound helpers
local function playSound(assetId, volume)
    local sound = Instance.new("Sound")
    sound.SoundId = "rbxassetid://" .. tostring(assetId)
    sound.Volume = volume or 0.5
    sound.Parent = SoundService
    sound:Play()
    sound.Ended:Once(function()
        sound:Destroy()
    end)
end

local function playNotifSound()
    playSound(87437544236708, 0.4)
end

local function playClickSound()
    playSound(6895079853, 0.3)
end

-- Global drag system (shared between all draggable panels)
local activeDrag = nil

local function makeDraggable(dragHandle, targetFrame)
    dragHandle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            activeDrag = {
                target = targetFrame,
                startMouse = input.Position,
                startPos = targetFrame.Position,
            }
        end
    end)
end

-------------------------------------------------
-- FORWARD DECLARATIONS
-- Some functions are referenced inside Command Execute closures but defined later.
-- Declaring them here lets the closures capture them as upvalues.
-------------------------------------------------
local openUI, closeUI, toggleUI
local isOpen = false
local openHelp, closeHelp

-------------------------------------------------
-- COMMAND REGISTRY
-------------------------------------------------
local Commands = {}

Commands["help"] = {
    Name = "help",
    Aliases = {"cmds", "commands"},
    Description = "Show all available commands",
    Args = {},
    Local = true,
    Execute = function() end,
}

Commands["fly"] = {
    Name = "fly",
    Aliases = {"flight"},
    Description = "Toggle flight mode",
    Args = {"speed"},
    Execute = function() end,
}

Commands["speed"] = {
    Name = "speed",
    Aliases = {"ws", "walkspeed"},
    Description = "Set your walk speed (use 'reset' to restore default)",
    Args = {"number|reset"},
    Default = 16,
    Execute = function() end,
}

Commands["noclip"] = {
    Name = "noclip",
    Aliases = {"nc", "clip"},
    Description = "Toggle noclip (walk through walls)",
    Args = {},
    Execute = function() end,
}

Commands["esp"] = {
    Name = "esp",
    Aliases = {"highlight"},
    Description = "Toggle player ESP highlights",
    Args = {},
    Local = true,
    Execute = function() end,
}

Commands["tp"] = {
    Name = "tp",
    Aliases = {"teleport"},
    Description = "Teleport to a player",
    Args = {"player"},
    PlayerArg = 1,
    Execute = function() end,
}

Commands["goto"] = {
    Name = "goto",
    Aliases = {"to"},
    Description = "Teleport to a player (alias)",
    Args = {"player"},
    PlayerArg = 1,
    Execute = function() end,
}

Commands["rejoin"] = {
    Name = "rejoin",
    Aliases = {"rj"},
    Description = "Rejoin the current server (auto re-executes this script)",
    Args = {},
    Execute = function() end,
}

Commands["god"] = {
    Name = "god",
    Aliases = {"godmode"},
    Description = "Toggle god mode",
    Args = {},
    Execute = function() end,
}

Commands["reset"] = {
    Name = "reset",
    Aliases = {"die", "kill"},
    Description = "Reset your character",
    Args = {},
    Execute = function() end,
}

Commands["jpower"] = {
    Name = "jpower",
    Aliases = {"jp", "jumppower"},
    Description = "Set your jump power (use 'reset' to restore default)",
    Args = {"number|reset"},
    Default = 50,
    Execute = function() end,
}

Commands["gravity"] = {
    Name = "gravity",
    Aliases = {"grav"},
    Description = "Set workspace gravity (use 'reset' to restore default)",
    Args = {"number|reset"},
    Default = 196.2,
    Local = true,
    Execute = function() end,
}

Commands["f3x"] = {
    Name = "f3x",
    Aliases = {"buildtools", "build"},
    Description = "Give F3X building tools (local)",
    Args = {},
    Local = true,
    Execute = function() end,
}

Commands["playerlist"] = {
    Name = "playerlist",
    Aliases = {"players", "plist"},
    Description = "Open player list with actions",
    Args = {},
    Local = true,
    Execute = function() end,
}

Commands["fling"] = {
    Name = "fling",
    Aliases = {},
    Description = "Fling a target player",
    Args = {"player"},
    PlayerArg = 1,
    Execute = function() end,
}

Commands["antifling"] = {
    Name = "antifling",
    Aliases = {"af"},
    Description = "Toggle anti-fling protection",
    Args = {},
    Local = true,
    Execute = function() end,
}

Commands["spectate"] = {
    Name = "spectate",
    Aliases = {"spec", "view"},
    Description = "Spectate a player (type 'off' to stop)",
    Args = {"player|off"},
    PlayerArg = 1,
    Local = true,
    Execute = function() end,
}

Commands["freecam"] = {
    Name = "freecam",
    Aliases = {"fc"},
    Description = "Toggle freecam (fly camera)",
    Args = {},
    Local = true,
    Execute = function() end,
}

Commands["prefix"] = {
    Name = "prefix",
    Aliases = {},
    Description = "Change the command prefix",
    Args = {"newprefix"},
    Local = true,
    Execute = function() end,
}

Commands["clickfling"] = {
    Name = "clickfling",
    Aliases = {"cfling", "mousefling"},
    Description = "Toggle click-fling and use trigger bind to fling closest player to cursor",
    Args = {},
    Execute = function() end,
}

Commands["bring"] = {
    Name = "bring",
    Aliases = {},
    Description = "Teleport a player to you (if the game replicates your position to them)",
    Args = {"player"},
    PlayerArg = 1,
    Execute = function() end,
}

Commands["respawn"] = {
    Name = "respawn",
    Aliases = {"re", "refresh"},
    Description = "Quick respawn and return to your current spot",
    Args = {},
    Execute = function() end,
}

Commands["chat"] = {
    Name = "chat",
    Aliases = {"say"},
    Description = "Send a chat message (useful for commands that require chatting)",
    Args = {"...message"},
    Execute = function() end,
}

Commands["hidechar"] = {
    Name = "hidechar",
    Aliases = {"hidec"},
    Description = "Hide your character model locally",
    Args = {},
    Local = true,
    Execute = function() end,
}

Commands["hideui"] = {
    Name = "hideui",
    Aliases = {"hui"},
    Description = "Toggle the UniversalAdmin UI visibility",
    Args = {},
    Local = true,
    Execute = function() end,
}

Commands["copy"] = {
    Name = "copy",
    Aliases = {},
    Description = "Copy text to your clipboard",
    Args = {"...text"},
    Local = true,
    Execute = function() end,
}

Commands["settings"] = {
    Name = "settings",
    Aliases = {"config", "options"},
    Description = "Open the settings panel",
    Args = {},
    Local = true,
    Execute = function() end,
}

Commands["infjump"] = {
    Name = "infjump",
    Aliases = {"infinityjump", "ij"},
    Description = "Toggle infinite jumping",
    Args = {},
    Execute = function() end,
}

Commands["invisible"] = {
    Name = "invisible",
    Aliases = {},
    Description = "Toggle local invisibility (client-side only)",
    Args = {},
    Local = true,
    Execute = function() end,
}

Commands["unload"] = {
    Name = "unload",
    Aliases = {"exit", "quit"},
    Description = "Unload UniversalAdmin (removes all UI and stops all toggles)",
    Args = {},
    Local = true,
    Execute = function() end,
}

Commands["clicktp"] = {
    Name = "clicktp",
    Aliases = {"ctp"},
    Description = "Toggle click-to-teleport: open UI with bind, click to TP",
    Args = {},
    Local = true,
    Execute = function() end,
}

Commands["fullbright"] = {
    Name = "fullbright",
    Aliases = {"fb", "bright"},
    Description = "Toggle fullbright (maximum ambient lighting)",
    Args = {},
    Local = true,
    Execute = function() end,
}

Commands["remotespy"] = {
    Name = "remotespy",
    Aliases = {"rspy"},
    Description = "Toggle remote spy - logs RemoteEvent/Function calls",
    Args = {},
    Local = true,
    Execute = function() end,
}

Commands["dex"] = {
    Name = "dex",
    Aliases = {"explorer"},
    Description = "Load Dex explorer via loadstring",
    Args = {},
    Local = true,
    Execute = function() end,
}

Commands["chatlog"] = {
    Name = "chatlog",
    Aliases = {"chatlogs", "logs"},
    Description = "Open chat log browser - search by player/time/content",
    Args = {},
    Local = true,
    Execute = function() end,
}

Commands["antiafk"] = {
    Name = "antiafk",
    Aliases = {"afk"},
    Description = "Toggle anti-AFK (prevents disconnect from inactivity)",
    Args = {},
    Local = true,
    Execute = function() end,
}

Commands["trail"] = {
    Name = "trail",
    Aliases = {},
    Description = "Toggle a neon trail behind your character",
    Args = {},
    Local = true,
    Execute = function() end,
}

Commands["pinghop"] = {
    Name = "pinghop",
    Aliases = {"phop"},
    Description = "Server list sorted by ping — pick one to join",
    Args = {},
    Local = true,
    Execute = function() end,
}

Commands["admincheck"] = {
    Name = "admincheck",
    Aliases = {"admins"},
    Description = "Check if any high-rank group members are in the server",
    Args = {},
    Local = true,
    Execute = function() end,
}

Commands["invis"] = {
    Name = "invis",
    Aliases = {"invisible"},
    Description = "Toggle seat-method server-side invisibility",
    Args = {},
    Local = true,
    Execute = function() end,
}

Commands["hitbox"] = {
    Name = "hitbox",
    Aliases = {"hb", "expandhitbox"},
    Description = "Scale up other players' HumanoidRootParts (invisible PvP advantage)",
    Args = {"size"},
    Default = 10,
    Local = true,
    Execute = function() end,
}

Commands["camlock"] = {
    Name = "camlock",
    Aliases = {"cl", "lockon", "aimlock"},
    Description = "Smooth camera lock onto a player's head/torso (bindable)",
    Args = {"player|off"},
    PlayerArg = 1,
    Local = true,
    Execute = function() end,
}

Commands["smoothfly"] = {
    Name = "smoothfly",
    Aliases = {"sfly", "planefly"},
    Description = "Inertia-based flight with momentum and camera banking",
    Args = {"speed"},
    Execute = function() end,
}

Commands["blink"] = {
    Name = "blink",
    Aliases = {"dash", "tp forward"},
    Description = "Instant forward teleport with FOV zoom and sound",
    Args = {"distance"},
    Default = 50,
    Local = true,
    Execute = function() end,
}

local function getMatchingCommands(query)
    local results = {}
    query = query:lower()
    if query == "" then
        for name, cmd in pairs(Commands) do
            table.insert(results, cmd)
        end
    else
        for name, cmd in pairs(Commands) do
            if name:sub(1, #query) == query then
                table.insert(results, cmd)
            else
                for _, alias in ipairs(cmd.Aliases or {}) do
                    if alias:sub(1, #query) == query then
                        table.insert(results, cmd)
                        break
                    end
                end
            end
        end
    end
    table.sort(results, function(a, b) return a.Name < b.Name end)
    return results
end

local function executeCommand(input)
    local parts = input:split(" ")
    local cmdName = parts[1]:lower()
    table.remove(parts, 1)

    local cmd = Commands[cmdName]
    if not cmd then
        -- check aliases
        for _, c in pairs(Commands) do
            for _, alias in ipairs(c.Aliases or {}) do
                if alias == cmdName then
                    cmd = c
                    break
                end
            end
            if cmd then break end
        end
    end

    if cmd then
        local ok, err = pcall(cmd.Execute, parts)
        if not ok then
            return false, "Error: " .. tostring(err)
        end
        return true, "Executed: " .. cmd.Name
    end
    return false, "Unknown command: " .. cmdName
end

-------------------------------------------------
-- UI CONSTRUCTION
-------------------------------------------------
-- Destroy any previous instance
local existing = CoreGui:FindFirstChild("UniversalAdmin")
if existing then existing:Destroy() end

local ScreenGui = create("ScreenGui", {
    Name = "UniversalAdmin",
    ResetOnSpawn = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    IgnoreGuiInset = true,
    DisplayOrder = 999,
    Parent = CoreGui,
})

-------------------------------------------------
-- TOP INFO BAR (always visible)
-------------------------------------------------
local _defaultTopBarPos = UDim2.new(0.5, 0, 0, 18)
if persistedConfig.topBarPos and type(persistedConfig.topBarPos) == "table" then
    local p = persistedConfig.topBarPos
    if type(p.xScale) == "number" and type(p.xOffset) == "number"
        and type(p.yScale) == "number" and type(p.yOffset) == "number" then
        _defaultTopBarPos = UDim2.new(p.xScale, p.xOffset, p.yScale, p.yOffset)
    end
end

-- Used for the center badge fill so it matches one layer of bar grey (see AdminIconHolder).
local TOP_BAR_BG_TRANSPARENCY = 0.1

local TopBar = create("Frame", {
    Name = "TopBar",
    AnchorPoint = Vector2.new(0.5, 0),
    Position = _defaultTopBarPos,
    Size = UDim2.new(0, 500, 0, 38),
    ClipsDescendants = false,
    Visible = false,
    BackgroundColor3 = Theme.Background,
    BackgroundTransparency = TOP_BAR_BG_TRANSPARENCY,
    BorderSizePixel = 0,
    Active = true,
    Parent = ScreenGui,
}, {
    create("UICorner", { CornerRadius = Theme.CornerRadius }),
    create("UIStroke", {
        Color = Theme.Border,
        Thickness = 1,
        Transparency = 0.4,
    }),
})

-- Top bar is draggable from anywhere on itself
makeDraggable(TopBar, TopBar)

-- Player avatar (left side) — circular head only, no ring (stroke removed)
local AvatarContainer = create("Frame", {
    Name = "AvatarContainer",
    AnchorPoint = Vector2.new(0, 0.5),
    Position = UDim2.new(0, 4, 0.5, 0),
    Size = UDim2.new(0, 34, 0, 34),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ZIndex = 5,
    Parent = TopBar,
})

local AvatarImage = create("ImageLabel", {
    Name = "Avatar",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.new(0.5, 0, 0.5, 0),
    Size = UDim2.new(1, 0, 1, 0),
    BackgroundTransparency = 1,
    Image = "rbxthumb://type=AvatarHeadShot&id=" .. LocalPlayer.UserId .. "&w=150&h=150",
    Parent = AvatarContainer,
}, {
    create("UICorner", { CornerRadius = UDim.new(1, 0) }),
})

-- Left section: display name + account tier (shifted right for avatar)
local TopBarLeft = create("Frame", {
    Name = "LeftSection",
    Size = UDim2.new(0, 220, 1, 0),
    Position = UDim2.new(0, 44, 0, 0),
    BackgroundTransparency = 1,
    Parent = TopBar,
})

local PlayerNameLabel = create("TextLabel", {
    Name = "PlayerName",
    Size = UDim2.new(1, 0, 0, 15),
    Position = UDim2.new(0, 0, 0, 5),
    BackgroundTransparency = 1,
    Text = (persistedConfig.nickname and persistedConfig.nickname ~= "") and persistedConfig.nickname or LocalPlayer.DisplayName,
    TextColor3 = Theme.Text,
    TextSize = 13,
    Font = Theme.FontBold,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextTruncate = Enum.TextTruncate.AtEnd,
    Parent = TopBarLeft,
})

local AccountTypeLabel = create("TextLabel", {
    Name = "AccountType",
    Size = UDim2.new(1, 0, 0, 12),
    Position = UDim2.new(0, 0, 0, 22),
    BackgroundTransparency = 1,
    Text = tierToDisplayLabel(persistedConfig.accountTier),
    TextColor3 = Theme.TextMuted,
    TextSize = 10,
    Font = Theme.Font,
    TextXAlignment = Enum.TextXAlignment.Left,
    Parent = TopBarLeft,
})

-- Center: admin icon — rbxthumb Asset URL loads reliably for Decals; raw rbxassetid://
-- on a Decal id often shows nothing in ImageLabel (GUI wants the texture id, not the wrapper).
local _adminDecalId = tonumber(CONFIG.AdminTopBarDecalId) or 0
local _adminIconUrl = _adminDecalId > 0
    and ("rbxthumb://type=Asset&id=%d&w=420&h=420"):format(_adminDecalId)
    or ""

-- Opaque fill ≈ Theme.Background over a dark backdrop with the same transparency as
-- the bar (single layer of grey). Semi-transparent fill on top of the bar doubled alpha;
-- fully transparent fill left the overflow ring showing the game behind.
local _topBarFillOpaque = (function()
    local bg = Theme.Background
    local v = 1 - TOP_BAR_BG_TRANSPARENCY
    return Color3.new(bg.R * v, bg.G * v, bg.B * v)
end)()

local AdminIconHolder = create("Frame", {
    Name = "AdminIcon",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.new(0.5, 0, 0.5, 0),
    Size = UDim2.new(0, 46, 0, 46),
    BackgroundColor3 = _topBarFillOpaque,
    BackgroundTransparency = 0,
    BorderSizePixel = 0,
    ZIndex = 8,
    Parent = TopBar,
}, {
    create("UICorner", { CornerRadius = UDim.new(1, 0) }),
    create("UIStroke", {
        Color = Theme.AccentPrimary,
        Thickness = 1.5,
        Transparency = 0.35,
    }),
})

local AdminIconImage = create("ImageLabel", {
    Name = "AdminIconImage",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.new(0.5, 0, 0.5, 0),
    Size = UDim2.new(1, -4, 1, -4),
    BackgroundTransparency = 1,
    Image = _adminIconUrl,
    ImageTransparency = 0,
    ScaleType = Enum.ScaleType.Fit,
    ZIndex = 9,
    Parent = AdminIconHolder,
}, {
    create("UICorner", { CornerRadius = UDim.new(1, 0) }),
})

if _adminIconUrl ~= "" then
    pcall(function()
        game:GetService("ContentProvider"):PreloadAsync({ AdminIconImage })
    end)
end

-- Right section: action buttons only (larger, white)
local TopBarRight = create("Frame", {
    Name = "RightSection",
    Size = UDim2.new(0, 200, 1, 0),
    Position = UDim2.new(1, -12, 0, 0),
    AnchorPoint = Vector2.new(1, 0),
    BackgroundTransparency = 1,
    Parent = TopBar,
})

local ButtonRow = create("Frame", {
    Name = "ButtonRow",
    Size = UDim2.new(1, 0, 0, 26),
    Position = UDim2.new(1, 0, 0.5, 0),
    AnchorPoint = Vector2.new(1, 0.5),
    BackgroundTransparency = 1,
    Parent = TopBarRight,
}, {
    create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 10),
        VerticalAlignment = Enum.VerticalAlignment.Center,
        HorizontalAlignment = Enum.HorizontalAlignment.Right,
    }),
})

local iconSymbols = {
    { Symbol = ":::", Tooltip = "Commands" },
    { Symbol = ">_",  Tooltip = "Console" },
    { Symbol = "~",   Tooltip = "Network" },
    { Symbol = "#",   Tooltip = "Settings" },
}

local topBarButtons = {}
local topBarIconWhite = Color3.fromRGB(255, 255, 255)
for i, icon in ipairs(iconSymbols) do
    local btn = create("TextButton", {
        Name = "IconBtn_" .. icon.Tooltip,
        Size = UDim2.new(0, 40, 0, 26),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        LayoutOrder = i,
        Text = icon.Symbol,
        TextColor3 = topBarIconWhite,
        TextSize = 16,
        Font = Theme.FontBold,
        TextStrokeTransparency = 0.55,
        TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
        Parent = ButtonRow,
    })

    btn.MouseEnter:Connect(function()
        tween(btn, quickTween, { TextColor3 = Theme.AccentPrimary })
    end)
    btn.MouseLeave:Connect(function()
        tween(btn, quickTween, { TextColor3 = topBarIconWhite })
    end)

    topBarButtons[icon.Tooltip] = btn
end

-- Backdrop overlay (dims screen when UI is open)
-- Click-outside capture for the command palette (invisible, but captures clicks)
local Backdrop = create("Frame", {
    Name = "Backdrop",
    Size = UDim2.new(1, 0, 1, 0),
    BackgroundColor3 = Color3.fromRGB(0, 0, 0),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Active = true, -- capture input even when transparent
    Visible = false,
    Parent = ScreenGui,
})

-- Main container - centered command palette style
local MainFrame = create("Frame", {
    Name = "MainFrame",
    AnchorPoint = Vector2.new(0.5, 0.3),
    Position = UDim2.new(0.5, 0, 0.3, 0),
    Size = UDim2.new(0, 520, 0, 0), -- starts collapsed
    Visible = false,
    BackgroundColor3 = Theme.Background,
    BackgroundTransparency = 0,
    BorderSizePixel = 0,
    ClipsDescendants = true,
    Parent = ScreenGui,
}, {
    create("UICorner", { CornerRadius = Theme.CornerRadiusLg }),
    create("UIStroke", {
        Color = Theme.Border,
        Thickness = 1,
        Transparency = 0.3,
    }),
})

-- Gradient glow effect on top border (shrunk to avoid rounded corners)
local GlowBar = create("Frame", {
    Name = "GlowBar",
    AnchorPoint = Vector2.new(0.5, 0),
    Size = UDim2.new(1, -32, 0, 2),
    Position = UDim2.new(0.5, 0, 0, 0),
    BorderSizePixel = 0,
    BackgroundColor3 = Color3.fromRGB(255, 255, 255),
    Parent = MainFrame,
}, {
    create("UIGradient", {
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Theme.AccentPrimary),
            ColorSequenceKeypoint.new(0.5, Theme.AccentSecondary),
            ColorSequenceKeypoint.new(1, Theme.AccentPrimary),
        }),
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(0.1, 0),
            NumberSequenceKeypoint.new(0.9, 0),
            NumberSequenceKeypoint.new(1, 1),
        }),
        Rotation = 0,
    }),
})

-- Header area with search icon and input
local HeaderFrame = create("Frame", {
    Name = "Header",
    Size = UDim2.new(1, 0, 0, 52),
    Position = UDim2.new(0, 0, 0, 2),
    BackgroundTransparency = 1,
    Parent = MainFrame,
})

-- Search/command icon
local CmdIcon = create("TextLabel", {
    Name = "CmdIcon",
    Size = UDim2.new(0, 40, 0, 52),
    Position = UDim2.new(0, 8, 0, 0),
    BackgroundTransparency = 1,
    Text = ">_",
    TextColor3 = Theme.AccentPrimary,
    TextSize = 18,
    Font = Theme.FontMono,
    Parent = HeaderFrame,
})

-- Command input box
local CommandInput = create("TextBox", {
    Name = "CommandInput",
    Size = UDim2.new(1, -96, 0, 52),
    Position = UDim2.new(0, 48, 0, 0),
    BackgroundTransparency = 1,
    Text = "",
    PlaceholderText = "Type a command...",
    PlaceholderColor3 = Theme.TextMuted,
    TextColor3 = Theme.Text,
    TextSize = 16,
    Font = Theme.Font,
    TextXAlignment = Enum.TextXAlignment.Left,
    ClearTextOnFocus = false,
    Parent = HeaderFrame,
})

-- Keybind hint
local KeyHint = create("TextLabel", {
    Name = "KeyHint",
    Size = UDim2.new(0, 36, 0, 24),
    Position = UDim2.new(1, -44, 0.5, -12),
    AnchorPoint = Vector2.new(0, 0),
    BackgroundColor3 = Theme.SurfaceHover,
    BackgroundTransparency = 0,
    Text = "ESC",
    TextColor3 = Theme.TextMuted,
    TextSize = 11,
    Font = Theme.FontBold,
    Parent = HeaderFrame,
}, {
    create("UICorner", { CornerRadius = UDim.new(0, 4) }),
    create("UIStroke", {
        Color = Theme.Border,
        Thickness = 1,
        Transparency = 0.5,
    }),
})

-- Divider below header
local Divider = create("Frame", {
    Name = "Divider",
    Size = UDim2.new(1, -24, 0, 1),
    Position = UDim2.new(0, 12, 0, 54),
    BackgroundColor3 = Theme.Border,
    BackgroundTransparency = 0.5,
    BorderSizePixel = 0,
    Parent = MainFrame,
})

-- Results / suggestions scroll area
local ResultsFrame = create("ScrollingFrame", {
    Name = "Results",
    Size = UDim2.new(1, -16, 1, -96),
    Position = UDim2.new(0, 8, 0, 58),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ScrollBarThickness = 3,
    ScrollBarImageColor3 = Theme.AccentPrimary,
    ScrollBarImageTransparency = 0.5,
    CanvasSize = UDim2.new(0, 0, 0, 0),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
    Parent = MainFrame,
}, {
    create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 2),
    }),
    create("UIPadding", {
        PaddingBottom = UDim.new(0, 6),
    }),
})

-- Status bar at the bottom (rounded bottom corners to match parent)
local StatusBar = create("Frame", {
    Name = "StatusBar",
    Size = UDim2.new(1, 0, 0, 30),
    Position = UDim2.new(0, 0, 1, -30),
    BackgroundColor3 = Theme.Surface,
    BackgroundTransparency = 0,
    BorderSizePixel = 0,
    Parent = MainFrame,
}, {
    create("UICorner", { CornerRadius = Theme.CornerRadiusLg }),
})

local StatusText = create("TextLabel", {
    Name = "StatusText",
    Size = UDim2.new(1, -24, 1, 0),
    Position = UDim2.new(0, 12, 0, 0),
    BackgroundTransparency = 1,
    Text = "UniversalAdmin loaded  |  Press ; to toggle",
    TextColor3 = Theme.TextMuted,
    TextSize = 12,
    Font = Theme.Font,
    TextXAlignment = Enum.TextXAlignment.Left,
    Parent = StatusBar,
})

local CommandCount = create("TextLabel", {
    Name = "CommandCount",
    Size = UDim2.new(0, 100, 1, 0),
    Position = UDim2.new(1, -112, 0, 0),
    BackgroundTransparency = 1,
    Text = "0 commands",
    TextColor3 = Theme.TextMuted,
    TextSize = 12,
    Font = Theme.Font,
    TextXAlignment = Enum.TextXAlignment.Right,
    Parent = StatusBar,
})

-------------------------------------------------
-- NOTIFICATION SYSTEM (toast popups)
-------------------------------------------------
local NotifHolder = create("Frame", {
    Name = "Notifications",
    Size = UDim2.new(0, 300, 1, 0),
    Position = UDim2.new(1, -16, 0, 0),
    AnchorPoint = Vector2.new(1, 0),
    BackgroundTransparency = 1,
    Parent = ScreenGui,
}, {
    create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 8),
        VerticalAlignment = Enum.VerticalAlignment.Bottom,
        HorizontalAlignment = Enum.HorizontalAlignment.Right,
    }),
    create("UIPadding", {
        PaddingBottom = UDim.new(0, 16),
    }),
})

local function notify(message, notifType, duration)
    notifType = notifType or "info"
    duration = duration or 3

    local accentColor = Theme.AccentPrimary
    if notifType == "success" then accentColor = Theme.Success
    elseif notifType == "error" then accentColor = Theme.Error
    elseif notifType == "warning" then accentColor = Theme.Warning end

    local notif = create("Frame", {
        Size = UDim2.new(0, 280, 0, 0),
        BackgroundColor3 = Theme.Surface,
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        AutomaticSize = Enum.AutomaticSize.Y,
        Parent = NotifHolder,
    }, {
        create("UICorner", { CornerRadius = Theme.CornerRadius }),
        create("UIStroke", {
            Color = accentColor,
            Thickness = 1,
            Transparency = 0.5,
        }),
        create("UIPadding", {
            PaddingTop = UDim.new(0, 10),
            PaddingBottom = UDim.new(0, 10),
            PaddingLeft = UDim.new(0, 12),
            PaddingRight = UDim.new(0, 10),
        }),
        create("TextLabel", {
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            Text = message,
            TextColor3 = Theme.Text,
            TextSize = 13,
            Font = Theme.Font,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextWrapped = true,
        }),
    })

    -- Play notification sound
    playNotifSound()

    -- Animate in
    notif.BackgroundTransparency = 1
    tween(notif, smoothIn, { BackgroundTransparency = 0 })

    -- Auto dismiss
    task.delay(duration, function()
        local t = tween(notif, smoothOut, { BackgroundTransparency = 1 })
        t.Completed:Wait()
        notif:Destroy()
    end)
end

-------------------------------------------------
-- HELP / COMMANDS PANEL
-------------------------------------------------
local HelpPanel = create("Frame", {
    Name = "HelpPanel",
    AnchorPoint = Vector2.new(0.5, 0.3),
    Position = UDim2.new(0.5, 0, 0.3, 0),
    Size = UDim2.new(0, 480, 0, 0),
    BackgroundColor3 = Theme.Background,
    BackgroundTransparency = 0,
    BorderSizePixel = 0,
    ClipsDescendants = true,
    Visible = false,
    Parent = ScreenGui,
}, {
    create("UICorner", { CornerRadius = Theme.CornerRadiusLg }),
    create("UIStroke", {
        Color = Theme.Border,
        Thickness = 1,
        Transparency = 0.3,
    }),
})

-- Help panel header (draggable handle)
local HelpHeader = create("Frame", {
    Name = "HelpHeader",
    Size = UDim2.new(1, 0, 0, 44),
    BackgroundTransparency = 1,
    Parent = HelpPanel,
})

makeDraggable(HelpHeader, HelpPanel)

create("TextLabel", {
    Name = "HelpTitle",
    Size = UDim2.new(1, -80, 1, 0),
    Position = UDim2.new(0, 16, 0, 0),
    BackgroundTransparency = 1,
    Text = "Commands",
    TextColor3 = Theme.AccentPrimary,
    TextSize = 16,
    Font = Theme.FontBold,
    TextXAlignment = Enum.TextXAlignment.Left,
    Parent = HelpHeader,
})

local HelpCloseBtn = create("TextLabel", {
    Name = "CloseBtn",
    Size = UDim2.new(0, 28, 0, 28),
    Position = UDim2.new(1, -40, 0.5, -14),
    BackgroundTransparency = 1,
    Text = "X",
    TextColor3 = Theme.TextMuted,
    TextSize = 14,
    Font = Theme.FontBold,
    Parent = HelpHeader,
})

create("Frame", {
    Name = "HelpDivider",
    Size = UDim2.new(1, -24, 0, 1),
    Position = UDim2.new(0, 12, 0, 44),
    BackgroundColor3 = Theme.Border,
    BackgroundTransparency = 0.5,
    BorderSizePixel = 0,
    Parent = HelpPanel,
})

local HelpScroll = create("ScrollingFrame", {
    Name = "HelpScroll",
    Size = UDim2.new(1, -16, 1, -52),
    Position = UDim2.new(0, 8, 0, 48),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ScrollBarThickness = 3,
    ScrollBarImageColor3 = Theme.AccentPrimary,
    ScrollBarImageTransparency = 0.5,
    CanvasSize = UDim2.new(0, 0, 0, 0),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
    Parent = HelpPanel,
}, {
    create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 4),
    }),
    create("UIPadding", {
        PaddingBottom = UDim.new(0, 8),
    }),
})

local helpOpen = false

local function populateHelp()
    for _, child in ipairs(HelpScroll:GetChildren()) do
        if child:IsA("Frame") then child:Destroy() end
    end

    local sorted = {}
    for _, cmd in pairs(Commands) do
        table.insert(sorted, cmd)
    end
    table.sort(sorted, function(a, b) return a.Name < b.Name end)

    for i, cmd in ipairs(sorted) do
        local argsText = ""
        if cmd.Args and #cmd.Args > 0 then
            for _, arg in ipairs(cmd.Args) do
                argsText = argsText .. " [" .. arg .. "]"
            end
        end

        local usage = CONFIG.Prefix .. cmd.Name .. argsText

        local entry = create("Frame", {
            Name = "HelpEntry_" .. cmd.Name,
            Size = UDim2.new(1, -4, 0, 38),
            BackgroundColor3 = Theme.Surface,
            BackgroundTransparency = 0.3,
            BorderSizePixel = 0,
            LayoutOrder = i,
            Parent = HelpScroll,
        }, {
            create("UICorner", { CornerRadius = UDim.new(0, 6) }),
            create("TextLabel", {
                Name = "Usage",
                Size = UDim2.new(0, 220, 0, 16),
                Position = UDim2.new(0, 10, 0, 4),
                BackgroundTransparency = 1,
                Text = usage,
                TextColor3 = Theme.AccentPrimary,
                TextSize = 13,
                Font = Theme.FontMono,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd,
            }),
            create("TextLabel", {
                Name = "Desc",
                Size = UDim2.new(1, -20, 0, 14),
                Position = UDim2.new(0, 10, 0, 20),
                BackgroundTransparency = 1,
                Text = cmd.Description or "No description",
                TextColor3 = Theme.TextDim,
                TextSize = 11,
                Font = Theme.Font,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd,
            }),
        })

        if cmd.Local then
            create("Frame", {
                Name = "LocalBadge",
                Size = UDim2.new(0, 44, 0, 16),
                Position = UDim2.new(1, -56, 0, 4),
                BackgroundColor3 = Theme.AccentPrimary,
                BackgroundTransparency = 0.75,
                BorderSizePixel = 0,
                Parent = entry,
            }, {
                create("UICorner", { CornerRadius = UDim.new(0, 4) }),
                create("UIStroke", {
                    Color = Theme.AccentPrimary,
                    Thickness = 1,
                    Transparency = 0.3,
                }),
                create("TextLabel", {
                    Size = UDim2.new(1, 0, 1, 0),
                    BackgroundTransparency = 1,
                    Text = "LOCAL",
                    TextColor3 = Theme.AccentPrimary,
                    TextSize = 10,
                    Font = Theme.FontBold,
                }),
            })
        end
    end
end

openHelp = function()
    if helpOpen then return end
    helpOpen = true

    populateHelp()
    HelpPanel.Visible = true
    HelpPanel.Size = UDim2.new(0, 480, 0, 0)
    HelpPanel.BackgroundTransparency = 1

    tween(HelpPanel, smoothIn, { Size = UDim2.new(0, 480, 0, 340), BackgroundTransparency = 0 })
    playClickSound()
end

closeHelp = function()
    if not helpOpen then return end
    helpOpen = false

    local t = tween(HelpPanel, smoothOut, { Size = UDim2.new(0, 480, 0, 0), BackgroundTransparency = 1 })
    t.Completed:Wait()
    HelpPanel.Visible = false
end

HelpCloseBtn.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        playClickSound()
        closeHelp()
    end
end)

HelpCloseBtn.MouseEnter:Connect(function()
    tween(HelpCloseBtn, quickTween, { TextColor3 = Theme.Error })
end)
HelpCloseBtn.MouseLeave:Connect(function()
    tween(HelpCloseBtn, quickTween, { TextColor3 = Theme.TextMuted })
end)

-- Wire up the help command's execute
Commands["help"].Execute = function(args)
    task.defer(function()
        closeUI()
        task.wait(0.3)
        openHelp()
    end)
end

-------------------------------------------------
-- TOOL PANEL UTILITY (reusable draggable panels)
-------------------------------------------------
local openPanelCount = 0

local function createToolPanel(opts)
    -- opts: { Name, Title, Icon, Width, Height, Position }
    local width = opts.Width or 260
    local height = opts.Height or 240
    local defaultPos = opts.Position or UDim2.new(0.5, -width/2 + (openPanelCount * 20), 0.5, -height/2 + (openPanelCount * 20))
    openPanelCount = openPanelCount + 1

    local panel = create("Frame", {
        Name = opts.Name or "ToolPanel",
        Size = UDim2.new(0, width, 0, height),
        Position = defaultPos,
        BackgroundColor3 = Theme.Background,
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        Visible = false,
        Parent = ScreenGui,
    }, {
        create("UICorner", { CornerRadius = Theme.CornerRadiusLg }),
        create("UIStroke", {
            Color = Theme.Border,
            Thickness = 1,
            Transparency = 0.3,
        }),
    })

    -- Gradient glow on top
    create("Frame", {
        Name = "GlowBar",
        AnchorPoint = Vector2.new(0.5, 0),
        Size = UDim2.new(1, -32, 0, 2),
        Position = UDim2.new(0.5, 0, 0, 0),
        BorderSizePixel = 0,
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        Parent = panel,
    }, {
        create("UIGradient", {
            Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Theme.AccentPrimary),
                ColorSequenceKeypoint.new(0.5, Theme.AccentSecondary),
                ColorSequenceKeypoint.new(1, Theme.AccentPrimary),
            }),
            Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 1),
                NumberSequenceKeypoint.new(0.1, 0),
                NumberSequenceKeypoint.new(0.9, 0),
                NumberSequenceKeypoint.new(1, 1),
            }),
        }),
    })

    -- Header
    local header = create("Frame", {
        Name = "Header",
        Size = UDim2.new(1, 0, 0, 36),
        Position = UDim2.new(0, 0, 0, 2),
        BackgroundTransparency = 1,
        Parent = panel,
    })

    local titleText = (opts.Icon and (opts.Icon .. "  ") or "") .. (opts.Title or "Panel")
    create("TextLabel", {
        Name = "Title",
        Size = UDim2.new(1, -80, 1, 0),
        Position = UDim2.new(0, 14, 0, 0),
        BackgroundTransparency = 1,
        Text = titleText,
        TextColor3 = Theme.Text,
        TextSize = 14,
        Font = Theme.FontBold,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = header,
    })

    local minBtn = create("TextButton", {
        Name = "MinBtn",
        Size = UDim2.new(0, 22, 0, 22),
        Position = UDim2.new(1, -50, 0.5, -11),
        BackgroundTransparency = 1,
        AutoButtonColor = false,
        Text = "_",
        TextColor3 = Theme.TextMuted,
        TextSize = 16,
        Font = Theme.FontBold,
        Parent = header,
    })

    local closeBtn = create("TextButton", {
        Name = "CloseBtn",
        Size = UDim2.new(0, 22, 0, 22),
        Position = UDim2.new(1, -24, 0.5, -11),
        BackgroundTransparency = 1,
        AutoButtonColor = false,
        Text = "X",
        TextColor3 = Theme.TextMuted,
        TextSize = 12,
        Font = Theme.FontBold,
        Parent = header,
    })

    -- Header divider
    create("Frame", {
        Name = "HeaderDivider",
        Size = UDim2.new(1, -24, 0, 1),
        Position = UDim2.new(0, 12, 0, 38),
        BackgroundColor3 = Theme.Border,
        BackgroundTransparency = 0.5,
        BorderSizePixel = 0,
        Parent = panel,
    })

    -- Content area
    local content = create("Frame", {
        Name = "Content",
        Size = UDim2.new(1, -24, 1, -52),
        Position = UDim2.new(0, 12, 0, 44),
        BackgroundTransparency = 1,
        Parent = panel,
    })

    -- Hover effects for close and minimize buttons
    closeBtn.MouseEnter:Connect(function()
        tween(closeBtn, quickTween, { TextColor3 = Theme.Error })
    end)
    closeBtn.MouseLeave:Connect(function()
        tween(closeBtn, quickTween, { TextColor3 = Theme.TextMuted })
    end)
    minBtn.MouseEnter:Connect(function()
        tween(minBtn, quickTween, { TextColor3 = Theme.AccentPrimary })
    end)
    minBtn.MouseLeave:Connect(function()
        tween(minBtn, quickTween, { TextColor3 = Theme.TextMuted })
    end)

    -- Make draggable via header
    makeDraggable(header, panel)

    -- State
    local isOpen = false
    local isMinimized = false
    local fullHeight = height

    local function show()
        if isOpen then return end
        isOpen = true
        panel.Visible = true
        panel.Size = UDim2.new(0, width, 0, 0)
        panel.BackgroundTransparency = 1
        tween(panel, smoothIn, { Size = UDim2.new(0, width, 0, fullHeight), BackgroundTransparency = 0 })
        playClickSound()
    end

    local function hide()
        if not isOpen then return end
        isOpen = false
        isMinimized = false
        local t = tween(panel, smoothOut, { Size = UDim2.new(0, width, 0, 0), BackgroundTransparency = 1 })
        playClickSound()
        task.spawn(function()
            t.Completed:Wait()
            if not isOpen then
                panel.Visible = false
                panel.Size = UDim2.new(0, width, 0, fullHeight)
                panel.BackgroundTransparency = 0
            end
        end)
    end

    local function toggle()
        if isOpen then hide() else show() end
    end

    local function minimize()
        isMinimized = not isMinimized
        playClickSound()
        if isMinimized then
            tween(panel, quickTween, { Size = UDim2.new(0, width, 0, 38) })
        else
            tween(panel, quickTween, { Size = UDim2.new(0, width, 0, fullHeight) })
        end
    end

    closeBtn.MouseButton1Click:Connect(hide)
    minBtn.MouseButton1Click:Connect(minimize)

    return {
        Panel = panel,
        Content = content,
        Header = header,
        Show = show,
        Hide = hide,
        Toggle = toggle,
        Minimize = minimize,
        IsOpen = function() return isOpen end,
    }
end

-------------------------------------------------
-- UI COMPONENT HELPERS (toggle, stepper, hotkey)
-------------------------------------------------
local function createLabel(text, parent, position)
    return create("TextLabel", {
        Size = UDim2.new(1, 0, 0, 14),
        Position = position,
        BackgroundTransparency = 1,
        Text = text,
        TextColor3 = Theme.TextDim,
        TextSize = 11,
        Font = Theme.FontBold,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = parent,
    })
end

local function createToggleButton(parent, position, initialState)
    local state = initialState or false
    local btn = create("TextButton", {
        Size = UDim2.new(1, 0, 0, 32),
        Position = position,
        BackgroundColor3 = state and Theme.AccentPrimary or Theme.Surface,
        BackgroundTransparency = state and 0.6 or 0,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Text = state and "ENABLED" or "DISABLED",
        TextColor3 = state and Theme.AccentPrimary or Theme.TextDim,
        TextSize = 12,
        Font = Theme.FontBold,
        Parent = parent,
    }, {
        create("UICorner", { CornerRadius = UDim.new(0, 6) }),
        create("UIStroke", {
            Color = state and Theme.AccentPrimary or Theme.Border,
            Thickness = 1,
            Transparency = state and 0.4 or 0.5,
        }),
    })

    local stroke = btn:FindFirstChildOfClass("UIStroke")
    local callback = nil

    local function setState(newState)
        state = newState
        local target = {
            BackgroundColor3 = state and Theme.AccentPrimary or Theme.Surface,
            BackgroundTransparency = state and 0.6 or 0,
            TextColor3 = state and Theme.AccentPrimary or Theme.TextDim,
        }
        tween(btn, quickTween, target)
        if stroke then
            tween(stroke, quickTween, {
                Color = state and Theme.AccentPrimary or Theme.Border,
                Transparency = state and 0.4 or 0.5,
            })
        end
        btn.Text = state and "ENABLED" or "DISABLED"
    end

    btn.MouseButton1Click:Connect(function()
        playClickSound()
        setState(not state)
        if callback then callback(state) end
    end)

    return {
        Button = btn,
        SetState = setState,
        GetState = function() return state end,
        OnToggle = function(cb) callback = cb end,
    }
end

local function createStepper(parent, position, initialValue, minVal, maxVal, step)
    local value = initialValue or 50
    minVal = minVal or 0
    maxVal = maxVal or 500
    step = step or 10

    local container = create("Frame", {
        Size = UDim2.new(1, 0, 0, 28),
        Position = position,
        BackgroundTransparency = 1,
        Parent = parent,
    })

    local function makeSideBtn(text, xPos)
        return create("TextButton", {
            Size = UDim2.new(0, 28, 1, 0),
            Position = xPos,
            BackgroundColor3 = Theme.Surface,
            BorderSizePixel = 0,
            AutoButtonColor = false,
            Text = text,
            TextColor3 = Theme.TextDim,
            TextSize = 14,
            Font = Theme.FontBold,
            Parent = container,
        }, {
            create("UICorner", { CornerRadius = UDim.new(0, 6) }),
            create("UIStroke", {
                Color = Theme.Border,
                Thickness = 1,
                Transparency = 0.5,
            }),
        })
    end

    local minusBtn = makeSideBtn("-", UDim2.new(0, 0, 0, 0))
    local plusBtn = makeSideBtn("+", UDim2.new(1, -28, 0, 0))

    local box = create("TextBox", {
        Size = UDim2.new(1, -64, 1, 0),
        Position = UDim2.new(0, 32, 0, 0),
        BackgroundColor3 = Theme.Surface,
        BorderSizePixel = 0,
        Text = tostring(value),
        TextColor3 = Theme.Text,
        TextSize = 13,
        Font = Theme.FontMono,
        ClearTextOnFocus = false,
        Parent = container,
    }, {
        create("UICorner", { CornerRadius = UDim.new(0, 6) }),
        create("UIStroke", {
            Color = Theme.Border,
            Thickness = 1,
            Transparency = 0.5,
        }),
    })

    local callback = nil
    local function setValue(v)
        v = math.clamp(math.floor(v), minVal, maxVal)
        value = v
        box.Text = tostring(v)
        if callback then callback(v) end
    end

    minusBtn.MouseButton1Click:Connect(function()
        playClickSound()
        setValue(value - step)
    end)
    plusBtn.MouseButton1Click:Connect(function()
        playClickSound()
        setValue(value + step)
    end)
    box.FocusLost:Connect(function()
        local n = tonumber(box.Text)
        if n then
            setValue(n)
        else
            box.Text = tostring(value)
        end
    end)

    -- Hover effects
    for _, btn in ipairs({minusBtn, plusBtn}) do
        btn.MouseEnter:Connect(function()
            tween(btn, quickTween, { BackgroundColor3 = Theme.SurfaceHover })
        end)
        btn.MouseLeave:Connect(function()
            tween(btn, quickTween, { BackgroundColor3 = Theme.Surface })
        end)
    end

    return {
        Container = container,
        SetValue = setValue,
        GetValue = function() return value end,
        OnChange = function(cb) callback = cb end,
    }
end

local function createCycleButton(parent, position, options, initialValue, formatFn)
    options = options or {}
    local index = 1
    for i, v in ipairs(options) do
        if v == initialValue then
            index = i
            break
        end
    end
    local callback = nil

    local function asText(v)
        if formatFn then
            local ok, txt = pcall(formatFn, v)
            if ok and txt ~= nil then return tostring(txt) end
        end
        return tostring(v)
    end

    local btn = create("TextButton", {
        Size = UDim2.new(1, 0, 0, 32),
        Position = position,
        BackgroundColor3 = Theme.Surface,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Text = "< " .. asText(options[index]) .. " >",
        TextColor3 = Theme.Text,
        TextSize = 12,
        Font = Theme.FontBold,
        Parent = parent,
    }, {
        create("UICorner", { CornerRadius = UDim.new(0, 6) }),
        create("UIStroke", {
            Color = Theme.Border,
            Thickness = 1,
            Transparency = 0.5,
        }),
    })

    btn.MouseButton1Click:Connect(function()
        if #options == 0 then return end
        playClickSound()
        index = (index % #options) + 1
        local v = options[index]
        btn.Text = "< " .. asText(v) .. " >"
        if callback then callback(v) end
    end)

    return {
        Button = btn,
        SetValue = function(v)
            for i, opt in ipairs(options) do
                if opt == v then
                    index = i
                    btn.Text = "< " .. asText(opt) .. " >"
                    return
                end
            end
        end,
        GetValue = function()
            return options[index]
        end,
        OnChange = function(cb)
            callback = cb
        end,
    }
end

local function createHotkeyButton(parent, position, initialKey)
    local currentKey = initialKey or Enum.KeyCode.F
    local listening = false
    local callback = nil

    local container = create("Frame", {
        Size = UDim2.new(1, 0, 0, 28),
        Position = position,
        BackgroundTransparency = 1,
        Parent = parent,
    })

    local btn = create("TextButton", {
        Size = UDim2.new(0, 50, 1, 0),
        Position = UDim2.new(0, 0, 0, 0),
        BackgroundColor3 = Theme.Surface,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Text = currentKey.Name,
        TextColor3 = Theme.AccentPrimary,
        TextSize = 12,
        Font = Theme.FontMono,
        Parent = container,
    }, {
        create("UICorner", { CornerRadius = UDim.new(0, 6) }),
        create("UIStroke", {
            Color = Theme.AccentPrimary,
            Thickness = 1,
            Transparency = 0.5,
        }),
    })

    local hintLabel = create("TextLabel", {
        Size = UDim2.new(1, -60, 1, 0),
        Position = UDim2.new(0, 58, 0, 0),
        BackgroundTransparency = 1,
        Text = "Click to rebind",
        TextColor3 = Theme.TextMuted,
        TextSize = 11,
        Font = Theme.Font,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = container,
    })

    btn.MouseButton1Click:Connect(function()
        if listening then return end
        playClickSound()
        listening = true
        btn.Text = "..."
        hintLabel.Text = "Press any key"

        local conn
        conn = UserInputService.InputBegan:Connect(function(input, gp)
            if input.UserInputType == Enum.UserInputType.Keyboard then
                currentKey = input.KeyCode
                btn.Text = currentKey.Name
                hintLabel.Text = "Click to rebind"
                listening = false
                if callback then callback(currentKey) end
                conn:Disconnect()
            end
        end)
    end)

    return {
        Container = container,
        GetKey = function() return currentKey end,
        OnChange = function(cb) callback = cb end,
    }
end

-------------------------------------------------
-- FLY PANEL + MECHANICS
-------------------------------------------------
local flyState = {
    enabled = false,
    speed = 50,
    hotkey = Enum.KeyCode.F,
    superman = false,
    bodyVelocity = nil,
    bodyGyro = nil,
    connection = nil,
    savedAutoRotate = nil,
    supermanPoseConn = nil,
    supermanJointSaves = nil,
    savedAnimateDisabled = nil,
}

-- Forward ref so startFly can reset the toggle if R15 check fails
local flySupermanToggleRef

local function isR15(humanoid)
    if not humanoid then return false end
    return humanoid.RigType == Enum.HumanoidRigType.R15
end

-- Apply a proper superman pose by directly manipulating R15 Motor6D joints.
-- This is more reliable than trying to find an authored animation that
-- matches exactly, and also replicates (joint C0 changes on owned parts
-- replicate like any other transform).
local function applySupermanPose()
    local char = LocalPlayer.Character
    if not char then return false end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not humanoid then return false end

    if not isR15(humanoid) then
        notify("Superman pose requires R15", "error", 2)
        return false
    end

    local upperTorso = char:FindFirstChild("UpperTorso")
    local lowerTorso = char:FindFirstChild("LowerTorso")
    if not upperTorso or not lowerTorso then
        notify("R15 torso parts missing", "error", 2)
        return false
    end

    local rightShoulder = upperTorso:FindFirstChild("RightShoulder")
    local leftShoulder  = upperTorso:FindFirstChild("LeftShoulder")
    local rightHip      = lowerTorso:FindFirstChild("RightHip")
    local leftHip       = lowerTorso:FindFirstChild("LeftHip")
    local waist         = upperTorso:FindFirstChild("Waist")

    -- Disable the stock Animate script so idle/walk don't fight our pose
    local animateScript = char:FindFirstChild("Animate")
    if animateScript then
        flyState.savedAnimateDisabled = animateScript.Disabled
        animateScript.Disabled = true
    end

    -- Stop anything currently playing so the bind pose is clean
    local animator = humanoid:FindFirstChildOfClass("Animator")
    if animator then
        for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
            pcall(function() track:Stop(0) end)
        end
    end

    -- Save original transforms and write new ones
    local saves = {}
    local function pose(joint, rotation)
        if not joint or not joint:IsA("Motor6D") then return end
        saves[joint] = { C0 = joint.C0, Transform = joint.Transform }
        joint.C0 = joint.C0 * rotation
        joint.Transform = CFrame.new()
    end

    -- Right arm extended forward (superhero punching pose)
    pose(rightShoulder, CFrame.Angles(0, 0, math.rad(-90)) * CFrame.Angles(math.rad(90), 0, 0))
    -- Left arm tucked back slightly
    pose(leftShoulder,  CFrame.Angles(0, 0, math.rad(90))  * CFrame.Angles(math.rad(-20), 0, 0))
    -- Legs extended straight back (slight spread)
    pose(rightHip, CFrame.Angles(math.rad(10), math.rad(5), 0))
    pose(leftHip,  CFrame.Angles(math.rad(10), math.rad(-5), 0))
    -- Straight torso
    pose(waist, CFrame.new())

    flyState.supermanJointSaves = saves

    -- Continuously re-write Transform so any sneaky animation that starts
    -- doesn't undo our pose.
    flyState.supermanPoseConn = RunService.Stepped:Connect(function()
        for joint in pairs(saves) do
            if joint and joint.Parent then
                joint.Transform = CFrame.new()
            end
        end
    end)

    if flyState.savedAutoRotate == nil then
        flyState.savedAutoRotate = humanoid.AutoRotate
    end
    humanoid.AutoRotate = false

    return true
end

local function clearSupermanPose()
    if flyState.supermanPoseConn then
        flyState.supermanPoseConn:Disconnect()
        flyState.supermanPoseConn = nil
    end

    if flyState.supermanJointSaves then
        for joint, snap in pairs(flyState.supermanJointSaves) do
            if joint and joint.Parent then
                joint.C0 = snap.C0
                joint.Transform = snap.Transform
            end
        end
        flyState.supermanJointSaves = nil
    end

    local char = LocalPlayer.Character
    if char then
        local animateScript = char:FindFirstChild("Animate")
        if animateScript and flyState.savedAnimateDisabled ~= nil then
            animateScript.Disabled = flyState.savedAnimateDisabled
        end
        local humanoid = char:FindFirstChildOfClass("Humanoid")
        if humanoid and flyState.savedAutoRotate ~= nil then
            humanoid.AutoRotate = flyState.savedAutoRotate
        end
    end
    flyState.savedAnimateDisabled = nil
    flyState.savedAutoRotate = nil
end

local function stopFly()
    flyState.enabled = false
    if flyState.connection then
        flyState.connection:Disconnect()
        flyState.connection = nil
    end
    if flyState.bodyVelocity then
        flyState.bodyVelocity:Destroy()
        flyState.bodyVelocity = nil
    end
    if flyState.bodyGyro then
        flyState.bodyGyro:Destroy()
        flyState.bodyGyro = nil
    end
    clearSupermanPose()
    local char = LocalPlayer.Character
    if char then
        local humanoid = char:FindFirstChildOfClass("Humanoid")
        if humanoid then
            humanoid.PlatformStand = false
            pcall(function() humanoid:ChangeState(Enum.HumanoidStateType.Running) end)
            pcall(function() humanoid:SetStateEnabled(Enum.HumanoidStateType.Freefall, true) end)
            pcall(function() humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true) end)
            pcall(function() humanoid:SetStateEnabled(Enum.HumanoidStateType.Running, true) end)
        end
    end
end

local function startFly()
    -- Clean up any stale fly state first
    if flyState.enabled then stopFly() end

    local char = LocalPlayer.Character
    if not char then
        notify("No character found", "error")
        return false
    end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not hrp or not humanoid then
        notify("Character not fully loaded", "error")
        return false
    end

    flyState.enabled = true
    humanoid.PlatformStand = true
    -- Fallback: also set Physics state & disable interfering states
    pcall(function() humanoid:ChangeState(Enum.HumanoidStateType.Physics) end)
    pcall(function() humanoid:SetStateEnabled(Enum.HumanoidStateType.Freefall, false) end)
    pcall(function() humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false) end)
    pcall(function() humanoid:SetStateEnabled(Enum.HumanoidStateType.Running, false) end)

    flyState.bodyVelocity = Instance.new("BodyVelocity")
    flyState.bodyVelocity.MaxForce = Vector3.new(1e6, 1e6, 1e6)
    flyState.bodyVelocity.Velocity = Vector3.new(0, 0, 0)
    flyState.bodyVelocity.Parent = hrp

    flyState.bodyGyro = Instance.new("BodyGyro")
    flyState.bodyGyro.MaxTorque = Vector3.new(1e6, 1e6, 1e6)
    flyState.bodyGyro.P = 9000
    flyState.bodyGyro.D = 500
    flyState.bodyGyro.Parent = hrp

    if flyState.superman then
        local ok = applySupermanPose()
        if not ok then
            flyState.superman = false
            if flySupermanToggleRef then flySupermanToggleRef.SetState(false) end
        end
    end

    flyState.connection = RunService.RenderStepped:Connect(function()
        if not flyState.enabled or not flyState.bodyVelocity or not flyState.bodyGyro then return end
        local cam = workspace.CurrentCamera
        if not cam then return end
        local cf = cam.CFrame
        local moveDir = Vector3.new(0, 0, 0)

        if UserInputService:IsKeyDown(Enum.KeyCode.W) then
            moveDir = moveDir + cf.LookVector
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then
            moveDir = moveDir - cf.LookVector
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then
            moveDir = moveDir - cf.RightVector
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then
            moveDir = moveDir + cf.RightVector
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
            moveDir = moveDir + Vector3.new(0, 1, 0)
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
            moveDir = moveDir - Vector3.new(0, 1, 0)
        end

        if moveDir.Magnitude > 0 then
            moveDir = moveDir.Unit
        end

        flyState.bodyVelocity.Velocity = moveDir * flyState.speed
        if flyState.superman and flyState.supermanJointSaves then
            -- Tilt the character so it lays flat pointing where the camera looks
            flyState.bodyGyro.CFrame = cf * CFrame.Angles(math.rad(-90), 0, 0)
        else
            flyState.bodyGyro.CFrame = cf
        end
    end)

    return true
end

local function setSuperman(enabled)
    flyState.superman = enabled
    if flyState.enabled then
        if enabled then
            local ok = applySupermanPose()
            if not ok then
                flyState.superman = false
                return false
            end
        else
            clearSupermanPose()
        end
    end
    return true
end

-- Fly panel
local flyPanel = createToolPanel({
    Name = "FlyPanel",
    Title = "Flight Control",
    Width = 260,
    Height = 340,
    Position = UDim2.new(0.5, -400, 0.5, -170),
})

local flyToggle = createToggleButton(flyPanel.Content, UDim2.new(0, 0, 0, 4))
flyToggle.OnToggle(function(enabled)
    if enabled then
        if not startFly() then
            flyToggle.SetState(false)
        else
            notify("Flight enabled", "success", 2)
        end
    else
        stopFly()
        notify("Flight disabled", "info", 2)
    end
end)

createLabel("SPEED", flyPanel.Content, UDim2.new(0, 0, 0, 46))
local flySpeedStepper = createStepper(flyPanel.Content, UDim2.new(0, 0, 0, 62), flyState.speed, 10, 500, 10)
flySpeedStepper.OnChange(function(v)
    flyState.speed = v
end)

createLabel("HOTKEY", flyPanel.Content, UDim2.new(0, 0, 0, 98))
local flyHotkeyBtn = createHotkeyButton(flyPanel.Content, UDim2.new(0, 0, 0, 114), flyState.hotkey)
flyHotkeyBtn.OnChange(function(newKey)
    flyState.hotkey = newKey
    notify("Flight hotkey set to " .. newKey.Name, "info", 2)
end)

createLabel("SUPERMAN POSE", flyPanel.Content, UDim2.new(0, 0, 0, 150))
local flySupermanToggle = createToggleButton(flyPanel.Content, UDim2.new(0, 0, 0, 166), flyState.superman)
flySupermanToggleRef = flySupermanToggle
flySupermanToggle.OnToggle(function(enabled)
    local ok = setSuperman(enabled)
    if enabled and not ok then
        flySupermanToggle.SetState(false)
        return
    end
    notify("Superman pose " .. (enabled and "on" or "off"), "info", 2)
end)

createLabel("ALWAYS ACTIVE HOTKEY", flyPanel.Content, UDim2.new(0, 0, 0, 210))
do
    local t = createToggleButton(flyPanel.Content, UDim2.new(0, 0, 0, 226), hotkeyAlwaysActive["fly"] or false)
    t.OnToggle(function(enabled)
        hotkeyAlwaysActive["fly"] = enabled
        persistedConfig.hotkeyAlwaysActive["fly"] = enabled or nil
        savePersistedConfig()
        notify("Fly hotkey " .. (enabled and "always active" or "panel-only"), "info", 2)
    end)
end

create("TextLabel", {
    Size = UDim2.new(1, 0, 0, 14),
    Position = UDim2.new(0, 0, 0, 270),
    BackgroundTransparency = 1,
    Text = "WASD Move  ·  Space Up  ·  Shift Down",
    TextColor3 = Theme.TextMuted,
    TextSize = 10,
    Font = Theme.Font,
    TextXAlignment = Enum.TextXAlignment.Center,
    Parent = flyPanel.Content,
})

-- Wire up fly command
Commands["fly"].Execute = function(args)
    if args and args[1] then
        local n = tonumber(args[1])
        if n then
            flyState.speed = math.clamp(n, 10, 500)
            flySpeedStepper.SetValue(flyState.speed)
        end
    end
    task.defer(function()
        if not flyPanel.IsOpen() then
            flyPanel.Show()
        end
    end)
end

-------------------------------------------------
-- NOCLIP MECHANICS + PANEL
-------------------------------------------------
local noclipState = {
    enabled = false,
    hotkey = Enum.KeyCode.N,
    connection = nil,
}

local function stopNoclip()
    noclipState.enabled = false
    if noclipState.connection then
        noclipState.connection:Disconnect()
        noclipState.connection = nil
    end
end

local function startNoclip()
    noclipState.enabled = true
    noclipState.connection = RunService.Stepped:Connect(function()
        local char = LocalPlayer.Character
        if not char then return end
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") and part.CanCollide then
                part.CanCollide = false
            end
        end
    end)
end

local noclipPanel = createToolPanel({
    Name = "NoclipPanel",
    Title = "Noclip",
    Width = 240,
    Height = 230,
    Position = UDim2.new(0.5, -120, 0.5, -115),
})

local noclipToggle = createToggleButton(noclipPanel.Content, UDim2.new(0, 0, 0, 4))
noclipToggle.OnToggle(function(enabled)
    if enabled then
        startNoclip()
        notify("Noclip enabled", "success", 2)
    else
        stopNoclip()
        notify("Noclip disabled", "info", 2)
    end
end)

createLabel("HOTKEY", noclipPanel.Content, UDim2.new(0, 0, 0, 46))
local noclipHotkeyBtn = createHotkeyButton(noclipPanel.Content, UDim2.new(0, 0, 0, 62), noclipState.hotkey)
noclipHotkeyBtn.OnChange(function(newKey)
    noclipState.hotkey = newKey
    notify("Noclip hotkey set to " .. newKey.Name, "info", 2)
end)

createLabel("ALWAYS ACTIVE HOTKEY", noclipPanel.Content, UDim2.new(0, 0, 0, 100))
do
    local t = createToggleButton(noclipPanel.Content, UDim2.new(0, 0, 0, 116), hotkeyAlwaysActive["noclip"] or false)
    t.OnToggle(function(enabled)
        hotkeyAlwaysActive["noclip"] = enabled
        persistedConfig.hotkeyAlwaysActive["noclip"] = enabled or nil
        savePersistedConfig()
        notify("Noclip hotkey " .. (enabled and "always active" or "panel-only"), "info", 2)
    end)
end

Commands["noclip"].Execute = function()
    task.defer(function()
        if not noclipPanel.IsOpen() then
            noclipPanel.Show()
        end
    end)
end

-------------------------------------------------
-- ESP MECHANICS + PANEL
-------------------------------------------------
-- Extended ESP: highlight/chams, names, health bars, distance, boxes, skeletons.
-- Each feature is independently toggleable. Color is configurable.
local espState = {
    enabled = false,
    objects = {},   -- [player] = { highlight, billboard, skeleton={...}, box, ... }
    connections = {},
    renderConn = nil,
    options = {
        color       = Color3.fromRGB(99, 102, 241),
        highlight   = true,
        chams       = false,
        names       = true,
        healthBars  = true,
        distance    = true,
        boxes       = false,
        skeletons   = false,
    },
}

local ESP_BONE_PAIRS_R15 = {
    { "Head", "UpperTorso" },
    { "UpperTorso", "LowerTorso" },
    { "UpperTorso", "LeftUpperArm" },
    { "LeftUpperArm", "LeftLowerArm" },
    { "LeftLowerArm", "LeftHand" },
    { "UpperTorso", "RightUpperArm" },
    { "RightUpperArm", "RightLowerArm" },
    { "RightLowerArm", "RightHand" },
    { "LowerTorso", "LeftUpperLeg" },
    { "LeftUpperLeg", "LeftLowerLeg" },
    { "LeftLowerLeg", "LeftFoot" },
    { "LowerTorso", "RightUpperLeg" },
    { "RightUpperLeg", "RightLowerLeg" },
    { "RightLowerLeg", "RightFoot" },
}

local function clearESPForPlayer(player)
    local objs = espState.objects[player]
    if not objs then return end
    if objs.highlight and objs.highlight.Parent then objs.highlight:Destroy() end
    if objs.billboard and objs.billboard.Parent then objs.billboard:Destroy() end
    if objs.box and objs.box.Parent then objs.box:Destroy() end
    if objs.skeletonHolder and objs.skeletonHolder.Parent then objs.skeletonHolder:Destroy() end
    espState.objects[player] = nil
end

local function clearESP()
    for p in pairs(espState.objects) do
        clearESPForPlayer(p)
    end
    espState.objects = {}
end

local function buildEspForPlayer(player)
    if player == LocalPlayer then return end
    local char = player.Character
    if not char then return end
    clearESPForPlayer(player)

    local entry = {}
    espState.objects[player] = entry

    -- Highlight (handles both highlight-only and chams styles)
    if espState.options.highlight or espState.options.chams then
        local h = Instance.new("Highlight")
        h.FillColor = espState.options.color
        h.OutlineColor = espState.options.color
        h.FillTransparency = espState.options.chams and 0.4 or 0.8
        h.OutlineTransparency = 0.1
        h.DepthMode = espState.options.chams
            and Enum.HighlightDepthMode.AlwaysOnTop
            or Enum.HighlightDepthMode.Occluded
        h.Parent = char
        entry.highlight = h
    end

    -- Name / Health / Distance billboard
    local head = char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart")
    if head and (espState.options.names or espState.options.healthBars or espState.options.distance) then
        local bb = Instance.new("BillboardGui")
        bb.Name = "UA_ESP_Info"
        bb.Size = UDim2.new(0, 180, 0, 44)
        bb.StudsOffset = Vector3.new(0, 2.8, 0)
        bb.AlwaysOnTop = true
        bb.LightInfluence = 0
        bb.Parent = head

        if espState.options.names then
            local nameLabel = Instance.new("TextLabel")
            nameLabel.Name = "Name"
            nameLabel.Size = UDim2.new(1, 0, 0, 14)
            nameLabel.Position = UDim2.new(0, 0, 0, 0)
            nameLabel.BackgroundTransparency = 1
            nameLabel.Text = player.DisplayName
            nameLabel.TextColor3 = espState.options.color
            nameLabel.TextStrokeTransparency = 0.3
            nameLabel.TextSize = 13
            nameLabel.Font = Enum.Font.GothamBold
            nameLabel.Parent = bb
            entry.nameLabel = nameLabel
        end

        if espState.options.distance then
            local distLabel = Instance.new("TextLabel")
            distLabel.Name = "Distance"
            distLabel.Size = UDim2.new(1, 0, 0, 12)
            distLabel.Position = UDim2.new(0, 0, 0, 14)
            distLabel.BackgroundTransparency = 1
            distLabel.Text = "--"
            distLabel.TextColor3 = Color3.fromRGB(200, 200, 220)
            distLabel.TextStrokeTransparency = 0.4
            distLabel.TextSize = 11
            distLabel.Font = Enum.Font.Gotham
            distLabel.Parent = bb
            entry.distLabel = distLabel
        end

        if espState.options.healthBars then
            local barBg = Instance.new("Frame")
            barBg.Name = "HealthBg"
            barBg.Size = UDim2.new(0.7, 0, 0, 4)
            barBg.Position = UDim2.new(0.15, 0, 0, 30)
            barBg.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
            barBg.BorderSizePixel = 0
            barBg.Parent = bb
            local barFill = Instance.new("Frame")
            barFill.Name = "HealthFill"
            barFill.Size = UDim2.new(1, 0, 1, 0)
            barFill.BackgroundColor3 = Color3.fromRGB(80, 220, 110)
            barFill.BorderSizePixel = 0
            barFill.Parent = barBg
            entry.healthFill = barFill
        end

        entry.billboard = bb
    end

    -- 2D box (ScreenGui with Frame, projected)
    if espState.options.boxes then
        if not espState.boxGui then
            local sg = Instance.new("ScreenGui")
            sg.Name = "UA_ESP_Boxes"
            sg.ResetOnSpawn = false
            sg.IgnoreGuiInset = true
            sg.DisplayOrder = 400
            sg.Parent = CoreGui
            espState.boxGui = sg
        end
        local box = Instance.new("Frame")
        box.Name = "Box_" .. player.Name
        box.BackgroundTransparency = 1
        box.BorderSizePixel = 0
        box.Parent = espState.boxGui
        local stroke = Instance.new("UIStroke")
        stroke.Color = espState.options.color
        stroke.Thickness = 1.5
        stroke.Transparency = 0.2
        stroke.Parent = box
        entry.box = box
        entry.boxStroke = stroke
    end

    -- Skeleton (line segments between joints using Frames in 2D projection)
    if espState.options.skeletons then
        if not espState.skeletonGui then
            local sg = Instance.new("ScreenGui")
            sg.Name = "UA_ESP_Skeleton"
            sg.ResetOnSpawn = false
            sg.IgnoreGuiInset = true
            sg.DisplayOrder = 399
            sg.Parent = CoreGui
            espState.skeletonGui = sg
        end
        local holder = Instance.new("Folder")
        holder.Name = "Skel_" .. player.Name
        holder.Parent = espState.skeletonGui
        entry.skeletonHolder = holder
        entry.skeletonLines = {}
        for _, pair in ipairs(ESP_BONE_PAIRS_R15) do
            local line = Instance.new("Frame")
            line.BackgroundColor3 = espState.options.color
            line.BorderSizePixel = 0
            line.AnchorPoint = Vector2.new(0, 0.5)
            line.Size = UDim2.new(0, 0, 0, 2)
            line.Parent = holder
            table.insert(entry.skeletonLines, { line = line, a = pair[1], b = pair[2] })
        end
    end
end

local function updateEspRender()
    local cam = workspace.CurrentCamera
    if not cam then return end
    local myChar = LocalPlayer.Character
    local myHrp = myChar and myChar:FindFirstChild("HumanoidRootPart")

    for player, entry in pairs(espState.objects) do
        local char = player.Character
        if not char then
            clearESPForPlayer(player)
        else
            local hum = char:FindFirstChildOfClass("Humanoid")
            local head = char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart")

            -- Distance / health updates
            if entry.distLabel and myHrp and head then
                local dist = (head.Position - myHrp.Position).Magnitude
                entry.distLabel.Text = string.format("%d studs", math.floor(dist))
            end
            if entry.healthFill and hum then
                local pct = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
                entry.healthFill.Size = UDim2.new(pct, 0, 1, 0)
                if pct > 0.6 then
                    entry.healthFill.BackgroundColor3 = Color3.fromRGB(80, 220, 110)
                elseif pct > 0.3 then
                    entry.healthFill.BackgroundColor3 = Color3.fromRGB(250, 200, 60)
                else
                    entry.healthFill.BackgroundColor3 = Color3.fromRGB(240, 80, 80)
                end
            end

            -- Box projection
            if entry.box then
                local hrp = char:FindFirstChild("HumanoidRootPart")
                if hrp then
                    local size = Vector3.new(4, 6, 0)
                    local topWorld = (hrp.CFrame * CFrame.new(0, size.Y / 2, 0)).Position
                    local botWorld = (hrp.CFrame * CFrame.new(0, -size.Y / 2, 0)).Position
                    local topS, topOn = cam:WorldToViewportPoint(topWorld)
                    local botS, botOn = cam:WorldToViewportPoint(botWorld)
                    if topOn and botOn and topS.Z > 0 and botS.Z > 0 then
                        local h = math.abs(botS.Y - topS.Y)
                        local w = h * 0.6
                        entry.box.Visible = true
                        entry.box.Size = UDim2.new(0, w, 0, h)
                        entry.box.Position = UDim2.new(0, topS.X - w / 2, 0, topS.Y)
                    else
                        entry.box.Visible = false
                    end
                end
            end

            -- Skeleton
            if entry.skeletonLines then
                for _, seg in ipairs(entry.skeletonLines) do
                    local partA = char:FindFirstChild(seg.a)
                    local partB = char:FindFirstChild(seg.b)
                    if partA and partB then
                        local a, aOn = cam:WorldToViewportPoint(partA.Position)
                        local b, bOn = cam:WorldToViewportPoint(partB.Position)
                        if aOn and bOn and a.Z > 0 and b.Z > 0 then
                            local dx = b.X - a.X
                            local dy = b.Y - a.Y
                            local len = math.sqrt(dx * dx + dy * dy)
                            seg.line.Visible = true
                            seg.line.Position = UDim2.new(0, a.X, 0, a.Y)
                            seg.line.Size = UDim2.new(0, len, 0, 2)
                            seg.line.Rotation = math.deg(math.atan2(dy, dx))
                        else
                            seg.line.Visible = false
                        end
                    else
                        seg.line.Visible = false
                    end
                end
            end
        end
    end
end

local function startESP()
    espState.enabled = true
    for _, player in ipairs(Players:GetPlayers()) do
        buildEspForPlayer(player)
    end
    espState.connections.added = Players.PlayerAdded:Connect(function(player)
        player.CharacterAdded:Connect(function()
            task.wait(0.5)
            if espState.enabled then buildEspForPlayer(player) end
        end)
    end)
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            player.CharacterAdded:Connect(function()
                task.wait(0.5)
                if espState.enabled then buildEspForPlayer(player) end
            end)
        end
    end
    espState.renderConn = RunService.RenderStepped:Connect(updateEspRender)
end

local function stopESP()
    espState.enabled = false
    for _, conn in pairs(espState.connections) do
        if conn then conn:Disconnect() end
    end
    espState.connections = {}
    if espState.renderConn then espState.renderConn:Disconnect() end
    espState.renderConn = nil
    clearESP()
    if espState.boxGui and espState.boxGui.Parent then espState.boxGui:Destroy() end
    espState.boxGui = nil
    if espState.skeletonGui and espState.skeletonGui.Parent then espState.skeletonGui:Destroy() end
    espState.skeletonGui = nil
end

local function rebuildEspIfEnabled()
    if espState.enabled then
        clearESP()
        if espState.boxGui and espState.boxGui.Parent then espState.boxGui:Destroy() end
        espState.boxGui = nil
        if espState.skeletonGui and espState.skeletonGui.Parent then espState.skeletonGui:Destroy() end
        espState.skeletonGui = nil
        for _, player in ipairs(Players:GetPlayers()) do
            buildEspForPlayer(player)
        end
    end
end

do
    local espPanel = createToolPanel({
        Name = "ESPPanel",
        Title = "Player ESP",
        Width = 280,
        Height = 430,
        Position = UDim2.new(0.5, 160, 0.5, -210),
    })

    local y = 4
    createLabel("MASTER TOGGLE", espPanel.Content, UDim2.new(0, 0, 0, y))
    y = y + 16
    local espToggle = createToggleButton(espPanel.Content, UDim2.new(0, 0, 0, y))
    espToggle.OnToggle(function(enabled)
        if enabled then
            startESP()
            notify("ESP enabled", "success", 2)
        else
            stopESP()
            notify("ESP disabled", "info", 2)
        end
    end)
    y = y + 40

    -- Feature toggle row helper
    local function addFeature(label, key)
        createLabel(label, espPanel.Content, UDim2.new(0, 0, 0, y))
        y = y + 16
        local t = createToggleButton(espPanel.Content, UDim2.new(0, 0, 0, y), espState.options[key])
        t.OnToggle(function(enabled)
            espState.options[key] = enabled
            rebuildEspIfEnabled()
        end)
        y = y + 40
    end

    addFeature("HIGHLIGHT (occluded)", "highlight")
    addFeature("CHAMS (always on top)", "chams")
    addFeature("NAMES", "names")
    addFeature("HEALTH BARS", "healthBars")
    addFeature("DISTANCE", "distance")
    addFeature("BOXES", "boxes")
    addFeature("SKELETONS", "skeletons")

    -- Color swatches
    createLabel("COLOR", espPanel.Content, UDim2.new(0, 0, 0, y))
    y = y + 16
    local colorRow = create("Frame", {
        Size = UDim2.new(1, 0, 0, 24),
        Position = UDim2.new(0, 0, 0, y),
        BackgroundTransparency = 1,
        Parent = espPanel.Content,
    }, {
        create("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            Padding = UDim.new(0, 4),
            SortOrder = Enum.SortOrder.LayoutOrder,
        }),
    })
    local colors = {
        Color3.fromRGB(99, 102, 241),
        Color3.fromRGB(239, 68, 68),
        Color3.fromRGB(34, 197, 94),
        Color3.fromRGB(59, 130, 246),
        Color3.fromRGB(236, 72, 153),
        Color3.fromRGB(250, 204, 21),
        Color3.fromRGB(245, 245, 245),
    }
    for i, c in ipairs(colors) do
        local sw = create("TextButton", {
            Size = UDim2.new(0, 24, 0, 24),
            BackgroundColor3 = c,
            BorderSizePixel = 0,
            AutoButtonColor = false,
            Text = "",
            LayoutOrder = i,
            Parent = colorRow,
        }, {
            create("UICorner", { CornerRadius = UDim.new(0, 5) }),
        })
        sw.MouseButton1Click:Connect(function()
            playClickSound()
            espState.options.color = c
            rebuildEspIfEnabled()
        end)
    end

    Commands["esp"].Execute = function()
        task.defer(function()
            if not espPanel.IsOpen() then
                espPanel.Show()
            end
        end)
    end
end

-------------------------------------------------
-- INSTANT COMMANDS (no panel)
-------------------------------------------------
local godState = { enabled = false, connection = nil }

local function isResetArg(s)
    if not s then return false end
    s = tostring(s):lower()
    return s == "reset" or s == "default" or s == "restore"
end

Commands["speed"].Execute = function(args)
    if not args or not args[1] then
        error("Usage: ;speed <number|reset>")
    end
    local char = LocalPlayer.Character
    if not char then error("No character") end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not humanoid then error("No humanoid") end

    if isResetArg(args[1]) then
        local def = Commands["speed"].Default or 16
        humanoid.WalkSpeed = def
        notify("WalkSpeed restored to default (" .. def .. ")", "info", 2)
        return
    end

    local n = tonumber(args[1])
    if not n then error("Speed must be a number or 'reset'") end
    humanoid.WalkSpeed = n
    notify("WalkSpeed set to " .. n, "success", 2)
end

Commands["jpower"].Execute = function(args)
    if not args or not args[1] then
        error("Usage: ;jpower <number|reset>")
    end
    local char = LocalPlayer.Character
    if not char then error("No character") end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not humanoid then error("No humanoid") end

    if isResetArg(args[1]) then
        local def = Commands["jpower"].Default or 50
        humanoid.JumpPower = def
        humanoid.UseJumpPower = true
        notify("JumpPower restored to default (" .. def .. ")", "info", 2)
        return
    end

    local n = tonumber(args[1])
    if not n then error("Jump power must be a number or 'reset'") end
    humanoid.JumpPower = n
    humanoid.UseJumpPower = true
    notify("JumpPower set to " .. n, "success", 2)
end

Commands["gravity"].Execute = function(args)
    if not args or not args[1] then
        error("Usage: ;gravity <number|reset>")
    end

    if isResetArg(args[1]) then
        local def = Commands["gravity"].Default or 196.2
        workspace.Gravity = def
        notify("Gravity restored to default (" .. def .. ")", "info", 2)
        return
    end

    local n = tonumber(args[1])
    if not n then error("Gravity must be a number or 'reset'") end
    workspace.Gravity = n
    notify("Gravity set to " .. n, "success", 2)
end

local function findPlayerByName(query)
    if not query then return nil end
    local q = query:lower()
    -- Exact name match first
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and (player.Name:lower() == q or player.DisplayName:lower() == q) then
            return player
        end
    end
    -- Prefix match
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            if player.Name:lower():sub(1, #q) == q
                or player.DisplayName:lower():sub(1, #q) == q then
                return player
            end
        end
    end
    -- Substring match
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            if player.Name:lower():find(q, 1, true)
                or player.DisplayName:lower():find(q, 1, true) then
                return player
            end
        end
    end
    return nil
end

-- Resolve a player selector string like "Bob", "all", "others", "me",
-- "random", or "@Bob" to a list of Player instances.
local function resolvePlayerList(query, opts)
    opts = opts or {}
    if not query or query == "" then return {} end
    local q = tostring(query):lower()

    if q == "all" or q == "everyone" or q == "*" then
        return Players:GetPlayers()
    elseif q == "others" or q == "other" then
        local list = {}
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer then table.insert(list, p) end
        end
        return list
    elseif q == "me" or q == "self" then
        return { LocalPlayer }
    elseif q == "random" or q == "rand" or q == "?" then
        local pool = {}
        for _, p in ipairs(Players:GetPlayers()) do
            if not opts.excludeSelf or p ~= LocalPlayer then
                table.insert(pool, p)
            end
        end
        if #pool == 0 then return {} end
        return { pool[math.random(1, #pool)] }
    elseif q == "nearest" or q == "near" then
        local myChar = LocalPlayer.Character
        local myHrp = myChar and myChar:FindFirstChild("HumanoidRootPart")
        if not myHrp then return {} end
        local best, bestDist = nil, math.huge
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer and p.Character then
                local hrp = p.Character:FindFirstChild("HumanoidRootPart")
                if hrp then
                    local d = (hrp.Position - myHrp.Position).Magnitude
                    if d < bestDist then best, bestDist = p, d end
                end
            end
        end
        return best and { best } or {}
    end

    -- Strip leading @ if present for explicit name lookup
    if q:sub(1, 1) == "@" then q = q:sub(2) end
    local single = findPlayerByName(q)
    if single then return { single } end
    return {}
end

local function teleportToPlayer(target)
    local myChar = LocalPlayer.Character
    local targetChar = target.Character
    if not myChar or not targetChar then error("Character not available") end

    local myHrp = myChar:FindFirstChild("HumanoidRootPart")
    local targetHrp = targetChar:FindFirstChild("HumanoidRootPart")
    if not myHrp or not targetHrp then error("HumanoidRootPart not found") end

    myHrp.CFrame = targetHrp.CFrame * CFrame.new(0, 0, 3)
    notify("Teleported to " .. target.DisplayName, "success", 2)
end

local function tpCommandExec(args)
    if not args or not args[1] then
        error("Usage: ;tp <player|random|nearest>")
    end
    local targets = resolvePlayerList(args[1], { excludeSelf = true })
    if #targets == 0 then error("Player not found: " .. args[1]) end
    -- Only honor the first resolved target for tp
    teleportToPlayer(targets[1])
end

Commands["tp"].Execute = tpCommandExec
Commands["goto"].Execute = tpCommandExec

-- Discover whatever queue_on_teleport function the executor provides so
-- we can re-run the loader on the other side of a rejoin.
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

Commands["rejoin"].Execute = function()
    local queueFn = getQueueOnTeleport()
    local snippet = buildRejoinTeleportSnippet()

    if queueFn then
        pcall(function() queueFn(snippet) end)
        notify("Auto-reexec queued, rejoining...", "info", 3)
    else
        notify("No queue_on_teleport support, rejoining...", "info", 3)
    end

    task.wait(0.5)
    TeleportService:Teleport(game.PlaceId, LocalPlayer)
end

-- Queue HttpGet loader on teleport/rejoin when CONFIG.LoaderUrl is set (no empty UA_Source-only queue)
task.defer(function()
    local queueFn = getQueueOnTeleport()
    local snippet = buildHttpGetReexecSnippet()
    if queueFn and snippet then
        pcall(function() queueFn(snippet) end)
    end
end)

Commands["reset"].Execute = function()
    local char = LocalPlayer.Character
    if not char then error("No character") end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if humanoid then
        humanoid.Health = 0
        notify("Character reset", "info", 2)
    end
end

Commands["god"].Execute = function()
    godState.enabled = not godState.enabled
    if godState.enabled then
        local function applyGod()
            local char = LocalPlayer.Character
            if not char then return end
            local humanoid = char:FindFirstChildOfClass("Humanoid")
            if humanoid then
                humanoid.MaxHealth = math.huge
                humanoid.Health = math.huge
            end
        end
        applyGod()
        godState.connection = LocalPlayer.CharacterAdded:Connect(function()
            task.wait(0.5)
            if godState.enabled then applyGod() end
        end)
        notify("God mode enabled", "success", 2)
    else
        if godState.connection then
            godState.connection:Disconnect()
            godState.connection = nil
        end
        local char = LocalPlayer.Character
        if char then
            local humanoid = char:FindFirstChildOfClass("Humanoid")
            if humanoid then
                humanoid.MaxHealth = 100
                humanoid.Health = 100
            end
        end
        notify("God mode disabled", "info", 2)
    end
end

-------------------------------------------------
-- BUILD PANEL (modern btools replacement)
-- Client-side raycast-driven delete/clone/color/spawn
-------------------------------------------------
local buildState = {
    tool = nil, -- "delete" | "clone" | "color" | "spawn" | nil
    color = Color3.fromRGB(255, 255, 255),
    connections = {},
}

local function clearBuildConnections()
    for _, c in ipairs(buildState.connections) do
        if c then c:Disconnect() end
    end
    buildState.connections = {}
end

local function raycastFromMouse()
    local cam = workspace.CurrentCamera
    if not cam then return nil end
    local mouse = UserInputService:GetMouseLocation()
    local ray = cam:ViewportPointToRay(mouse.X, mouse.Y, 0)
    local params = RaycastParams.new()
    local ignoreList = {}
    if LocalPlayer.Character then table.insert(ignoreList, LocalPlayer.Character) end
    params.FilterDescendantsInstances = ignoreList
    params.FilterType = Enum.RaycastFilterType.Exclude
    return workspace:Raycast(ray.Origin, ray.Direction * 500, params)
end

local function handleBuildClick()
    local tool = buildState.tool
    if not tool then return end
    local hit = raycastFromMouse()
    if not hit or not hit.Instance then return end
    local part = hit.Instance
    if not part:IsA("BasePart") then return end
    if part.Locked then
        notify("Part is locked", "error", 2)
        return
    end

    if tool == "delete" then
        part:Destroy()
    elseif tool == "clone" then
        local copy = part:Clone()
        copy.CFrame = part.CFrame + Vector3.new(0, part.Size.Y + 0.5, 0)
        copy.Parent = part.Parent
    elseif tool == "color" then
        part.Color = buildState.color
    elseif tool == "spawn" then
        local newPart = Instance.new("Part")
        newPart.Size = Vector3.new(4, 1, 4)
        newPart.Anchored = true
        newPart.Color = buildState.color
        newPart.Material = Enum.Material.SmoothPlastic
        newPart.CFrame = CFrame.new(hit.Position + Vector3.new(0, 0.5, 0))
        newPart.Parent = workspace
    end
end

local function setBuildTool(newTool)
    buildState.tool = newTool
    clearBuildConnections()
    if newTool then
        table.insert(buildState.connections, UserInputService.InputBegan:Connect(function(input, gp)
            if gp then return end
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                handleBuildClick()
            end
        end))
        notify("Build tool: " .. newTool:upper(), "info", 2)
    end
end

local buildPanel = createToolPanel({
    Name = "BuildPanel",
    Title = "Build Tools",
    Width = 280,
    Height = 280,
    Position = UDim2.new(0.5, 140, 0.5, 50),
})

local buildToolBtns = {}
local function makeBuildToolBtn(name, label, yPos)
    local btn = create("TextButton", {
        Size = UDim2.new(0.5, -4, 0, 32),
        Position = UDim2.new(0, 0, 0, yPos),
        BackgroundColor3 = Theme.Surface,
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Text = label,
        TextColor3 = Theme.TextDim,
        TextSize = 12,
        Font = Theme.FontBold,
        Parent = buildPanel.Content,
    }, {
        create("UICorner", { CornerRadius = UDim.new(0, 6) }),
        create("UIStroke", {
            Color = Theme.Border,
            Thickness = 1,
            Transparency = 0.5,
        }),
    })
    buildToolBtns[name] = btn
    btn.MouseButton1Click:Connect(function()
        playClickSound()
        local newTool = buildState.tool == name and nil or name
        setBuildTool(newTool)
        for n, b in pairs(buildToolBtns) do
            local active = (n == newTool)
            local stroke = b:FindFirstChildOfClass("UIStroke")
            tween(b, quickTween, {
                BackgroundColor3 = active and Theme.AccentPrimary or Theme.Surface,
                BackgroundTransparency = active and 0.6 or 0,
                TextColor3 = active and Theme.AccentPrimary or Theme.TextDim,
            })
            if stroke then
                tween(stroke, quickTween, {
                    Color = active and Theme.AccentPrimary or Theme.Border,
                    Transparency = active and 0.4 or 0.5,
                })
            end
        end
    end)
    btn.MouseEnter:Connect(function()
        if buildState.tool ~= name then
            tween(btn, quickTween, { BackgroundColor3 = Theme.SurfaceHover })
        end
    end)
    btn.MouseLeave:Connect(function()
        if buildState.tool ~= name then
            tween(btn, quickTween, { BackgroundColor3 = Theme.Surface })
        end
    end)
    return btn
end

local deleteBtn = makeBuildToolBtn("delete", "DELETE", 4)
deleteBtn.Position = UDim2.new(0, 0, 0, 4)
local cloneBtn = makeBuildToolBtn("clone", "CLONE", 4)
cloneBtn.Position = UDim2.new(0.5, 4, 0, 4)
local colorBtn = makeBuildToolBtn("color", "PAINT", 40)
colorBtn.Position = UDim2.new(0, 0, 0, 40)
local spawnBtn = makeBuildToolBtn("spawn", "SPAWN", 40)
spawnBtn.Position = UDim2.new(0.5, 4, 0, 40)

createLabel("COLOR", buildPanel.Content, UDim2.new(0, 0, 0, 86))
-- Color palette
local paletteColors = {
    Color3.fromRGB(255, 255, 255),
    Color3.fromRGB(248, 113, 113),
    Color3.fromRGB(251, 191, 36),
    Color3.fromRGB(52, 211, 153),
    Color3.fromRGB(99, 102, 241),
    Color3.fromRGB(139, 92, 246),
    Color3.fromRGB(236, 72, 153),
    Color3.fromRGB(30, 30, 30),
}

local paletteRow = create("Frame", {
    Size = UDim2.new(1, 0, 0, 28),
    Position = UDim2.new(0, 0, 0, 104),
    BackgroundTransparency = 1,
    Parent = buildPanel.Content,
}, {
    create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        Padding = UDim.new(0, 4),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }),
})

local selectedSwatch = nil
for i, color in ipairs(paletteColors) do
    local swatch = create("TextButton", {
        Size = UDim2.new(0, 28, 0, 28),
        BackgroundColor3 = color,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Text = "",
        LayoutOrder = i,
        Parent = paletteRow,
    }, {
        create("UICorner", { CornerRadius = UDim.new(0, 4) }),
        create("UIStroke", {
            Color = (i == 1) and Theme.AccentPrimary or Theme.Border,
            Thickness = (i == 1) and 2 or 1,
            Transparency = 0.3,
        }),
    })
    if i == 1 then selectedSwatch = swatch end
    swatch.MouseButton1Click:Connect(function()
        playClickSound()
        buildState.color = color
        if selectedSwatch then
            local s = selectedSwatch:FindFirstChildOfClass("UIStroke")
            if s then s.Color = Theme.Border; s.Thickness = 1 end
        end
        selectedSwatch = swatch
        local s = swatch:FindFirstChildOfClass("UIStroke")
        if s then s.Color = Theme.AccentPrimary; s.Thickness = 2 end
    end)
end

create("TextLabel", {
    Size = UDim2.new(1, 0, 0, 14),
    Position = UDim2.new(0, 0, 0, 146),
    BackgroundTransparency = 1,
    Text = "Click a tool, then click a part",
    TextColor3 = Theme.TextDim,
    TextSize = 11,
    Font = Theme.Font,
    TextXAlignment = Enum.TextXAlignment.Center,
    Parent = buildPanel.Content,
})

create("TextLabel", {
    Size = UDim2.new(1, 0, 0, 12),
    Position = UDim2.new(0, 0, 0, 162),
    BackgroundTransparency = 1,
    Text = "Client-side only · others won't see changes",
    TextColor3 = Theme.TextMuted,
    TextSize = 10,
    Font = Theme.Font,
    TextXAlignment = Enum.TextXAlignment.Center,
    Parent = buildPanel.Content,
})

Commands["f3x"].Execute = function()
    notify("Loading F3X tools...", "info", 2)
    task.defer(function()
        local ok, err = pcall(function()
            local model = game:GetService("InsertService"):LoadLocalAsset("rbxassetid://142785488")
                or game:GetObjects("rbxassetid://142785488")[1]
            if model then
                model.Parent = LocalPlayer.Backpack or LocalPlayer:WaitForChild("Backpack")
                -- Tag so unload can find it
                model:SetAttribute("UA_Local", true)
                notify("F3X tools added to backpack", "success", 2)
            else
                notify("Failed to load F3X model", "error", 3)
            end
        end)
        if not ok then
            notify("F3X error: " .. tostring(err), "error", 3)
        end
    end)
end

-------------------------------------------------
-- FLING / ANTIFLING
-------------------------------------------------
antiFlingState = antiFlingState or { enabled = false, connection = nil, heartbeatConn = nil, safePos = nil }
startAntiFling, stopAntiFling = startAntiFling, stopAntiFling

-- Serialise fling operations so we never try to run two at once and end
-- up with tangled camera/character state.
local flingInProgress = false

FLING_DATA = FLING_DATA or {
    timeout = 0.1, -- brief attack window for blink-fling
    modes = { "blink", "slam", "hitbox" },
    labels = { blink = "Blink", slam = "Slam", hitbox = "Hitbox Expander" },
}
targetingState = targetingState or {
    silent = false,
    velocityResolver = false,
    velocityCache = {},
    resolverLead = 0.12,
}

local function flingPlayer(target, modeOverride)
    if flingInProgress then
        notify("Already flinging", "info", 1.5)
        return
    end
    if not target or not target.Character then error("Target has no character") end
    if target == LocalPlayer then error("Cannot fling yourself") end
    local mode = (type(modeOverride) == "string" and FLING_DATA.labels[modeOverride]) and modeOverride or "blink"
    local targetChar = target.Character
    local targetHrp = targetChar:FindFirstChild("HumanoidRootPart")
    if not targetHrp then error("Target has no HumanoidRootPart") end

    local myChar = LocalPlayer.Character
    if not myChar then error("No character") end
    local myHrp = myChar:FindFirstChild("HumanoidRootPart")
    local myHum = myChar:FindFirstChildOfClass("Humanoid")
    if not myHrp or not myHum then error("Local character missing") end

    local function getResolvedCFrame(tHrp)
        if not tHrp then return nil end
        if not targetingState.velocityResolver then return tHrp.CFrame end
        local key = tostring(target.UserId)
        local now = os.clock()
        local cache = targetingState.velocityCache[key]
        local predictedPos = tHrp.Position
        if cache then
            local dt = now - cache.t
            if dt > 0.001 then
                local rawVel = (tHrp.Position - cache.pos) / dt -- distance over time
                local smoothVel = cache.vel and cache.vel:Lerp(rawVel, 0.35) or rawVel
                local accel = cache.vel and ((smoothVel - cache.vel) / dt) or Vector3.zero
                local dist = (tHrp.Position - myHrp.Position).Magnitude
                local lead = math.clamp((targetingState.resolverLead or 0.12) + (dist / 3200), 0.1, 0.24)
                predictedPos = predictedPos + (smoothVel * lead) + (0.5 * accel * lead * lead)
                targetingState.velocityCache[key] = { pos = tHrp.Position, t = now, vel = smoothVel }
                return CFrame.new(predictedPos) * (tHrp.CFrame - tHrp.CFrame.Position)
            end
        end
        targetingState.velocityCache[key] = { pos = tHrp.Position, t = now, vel = Vector3.zero }
        return CFrame.new(predictedPos) * (tHrp.CFrame - tHrp.CFrame.Position)
    end

    local targetHum = targetChar:FindFirstChildOfClass("Humanoid")
    if myHrp.Anchored or targetHrp.Anchored then return false end
    if not targetHum or targetHum.Health <= 0 or myHum.Health <= 0 then return false end

    local antiWasEnabled = antiFlingState.enabled
    if not antiWasEnabled and startAntiFling then
        startAntiFling()
    end

    flingInProgress = true

    -- === SAVE STATE ===
    local savedCFrame = myHrp.CFrame
    local savedVelocity = myHrp.AssemblyLinearVelocity
    local savedRotVelocity = myHrp.AssemblyAngularVelocity
    local previousState = myHum:GetState()

    -- === CAMERA LOCK / SILENT VISUAL SPOOF ===
    local cam = workspace.CurrentCamera
    local savedCamCFrame  = cam and cam.CFrame or nil
    local savedCamType    = cam and cam.CameraType or nil
    local savedCamSubject = cam and cam.CameraSubject or nil
    local silentSpoofConn = nil
    local silentVisualCF = savedCFrame
    local camPosOffset = (savedCamCFrame and (savedCamCFrame.Position - savedCFrame.Position)) or Vector3.zero
    local camRotOnly = (savedCamCFrame and (savedCamCFrame - savedCamCFrame.Position)) or CFrame.new()
    local animateScript = myChar:FindFirstChild("Animate")
    local animateWasEnabled = animateScript and animateScript.Enabled or nil

    if cam then
        cam.CameraType = Enum.CameraType.Scriptable
        cam.CFrame = savedCamCFrame
    end
    local camLockConn = cam and RunService.RenderStepped:Connect(function(dt)
        if targetingState.silent then
            local moveDir = myHum.MoveDirection
            if moveDir.Magnitude > 0.01 then
                silentVisualCF = silentVisualCF + (moveDir.Unit * myHum.WalkSpeed * dt)
            end
            pcall(function()
                myHrp.CFrame = silentVisualCF
                if cam then
                    cam.CFrame = CFrame.new(silentVisualCF.Position + camPosOffset) * camRotOnly
                end
            end)
        elseif cam and savedCamCFrame then
            pcall(function() cam.CFrame = savedCamCFrame end)
        end
    end)
    silentSpoofConn = camLockConn

    pcall(function()
        if not targetingState.silent then
            myHum:ChangeState(Enum.HumanoidStateType.Physics)
        elseif animateScript then
            -- Prevent local limb jitter while spoofing position every frame.
            animateScript.Enabled = false
        end
    end)

    local attemptOrder = { mode, "blink", "slam", "hitbox" }
    local function uniqueModes(list)
        local out, seen = {}, {}
        for _, m in ipairs(list) do
            if FLING_DATA.labels[m] and not seen[m] then
                table.insert(out, m)
                seen[m] = true
            end
        end
        return out
    end

    local okMode, modeResult = pcall(function()
        local function detectSuccess(tHrp, startPos)
            if not tHrp or not tHrp.Parent then return false end
            local moved = (tHrp.Position - startPos).Magnitude >= 10
            local ok, vel = pcall(function() return tHrp.AssemblyLinearVelocity end)
            return moved or (ok and vel and vel.Magnitude >= 30)
        end
        local tried = uniqueModes(attemptOrder)
        for _, activeMode in ipairs(tried) do
            local tRoot = targetChar:FindFirstChild("HumanoidRootPart")
            if not tRoot then return false end
            local startPos = tRoot.Position
            local startTime = os.clock()
            local timeout = (activeMode == "slam" and 0.16) or (activeMode == "hitbox" and 0.14) or FLING_DATA.timeout
            local savedSize = myHrp.Size
            if activeMode == "hitbox" then pcall(function() myHrp.Size = Vector3.new(12, 12, 12) end) end
            local flung = false
            repeat
                local tHrp = targetChar:FindFirstChild("HumanoidRootPart")
                if not tHrp then break end
                if activeMode == "slam" then
                    local angle = (os.clock() - startTime) * 45
                    local orbit = CFrame.Angles(0, math.rad(angle), 0) * CFrame.new(1.6, 0, 0)
                    local resolved = getResolvedCFrame(tHrp) or tHrp.CFrame
                    myHrp.CFrame = resolved * orbit
                    pcall(function()
                        myHrp.AssemblyLinearVelocity = targetingState.silent and Vector3.zero or Vector3.new(2600, 300, 2600)
                        myHrp.AssemblyAngularVelocity = Vector3.new(85000, 70000, 85000)
                    end)
                elseif activeMode == "hitbox" then
                    local offset = Vector3.new(math.random(-2, 2) * 0.2, 0, math.random(-2, 2) * 0.2)
                    local resolved = getResolvedCFrame(tHrp) or tHrp.CFrame
                    myHrp.CFrame = resolved * CFrame.new(offset)
                    pcall(function()
                        myHrp.AssemblyAngularVelocity = Vector3.new(85000, 85000, 85000)
                        myHrp.AssemblyLinearVelocity = targetingState.silent and Vector3.zero or Vector3.new(6000, 0, 6000)
                    end)
                else
                    local offset = Vector3.new(math.random(-1, 1) * 0.1, 0, math.random(-1, 1) * 0.1)
                    local resolved = getResolvedCFrame(tHrp) or tHrp.CFrame
                    myHrp.CFrame = resolved * CFrame.new(offset)
                    pcall(function()
                        myHrp.AssemblyAngularVelocity = Vector3.new(99999, 99999, 99999)
                        myHrp.AssemblyLinearVelocity = Vector3.zero
                    end)
                end
                RunService.Heartbeat:Wait()
                pcall(function()
                    local maxLinear = targetingState.silent and 60 or 180
                    local maxAngular = targetingState.silent and 120000 or 180000
                    if myHrp.AssemblyLinearVelocity.Magnitude > maxLinear then
                        myHrp.AssemblyLinearVelocity = Vector3.zero
                    end
                    if targetingState.silent then
                        myHrp.AssemblyLinearVelocity = Vector3.zero
                    end
                    if myHrp.AssemblyAngularVelocity.Magnitude > maxAngular then
                        myHrp.AssemblyAngularVelocity = Vector3.new(90000, 90000, 90000)
                    end
                end)
                flung = detectSuccess(tHrp, startPos)
            until flung or (os.clock() - startTime >= timeout) or (activeMode == "blink" and not targetChar:FindFirstChild("Head"))

            -- If first pass misses (especially on moving targets), do a very short
            -- high-speed circular sweep around predicted position to catch desync.
            if not flung then
                local tNow = targetChar:FindFirstChild("HumanoidRootPart")
                if tNow then
                    local movingMag = 0
                    pcall(function()
                        movingMag = tNow.AssemblyLinearVelocity.Magnitude
                    end)
                    local sweepDur = math.clamp(0.07 + (movingMag / 800), 0.07, 0.16)
                    local sweepStart = os.clock()
                    repeat
                        local th = targetChar:FindFirstChild("HumanoidRootPart")
                        if not th then break end
                        local resolved = getResolvedCFrame(th) or th.CFrame
                        local a = (os.clock() - sweepStart) * 65
                        local radius = 1.2 + (math.random() * 0.9)
                        local lift = (math.random() - 0.5) * 0.8
                        local offset = CFrame.Angles(0, a, 0) * CFrame.new(radius, lift, 0)
                        myHrp.CFrame = resolved * offset
                        pcall(function()
                            myHrp.AssemblyAngularVelocity = Vector3.new(100000, 100000, 100000)
                            myHrp.AssemblyLinearVelocity = targetingState.silent and Vector3.zero or Vector3.new(2600, 0, 2600)
                        end)
                        RunService.Heartbeat:Wait()
                        flung = detectSuccess(th, startPos)
                    until flung or (os.clock() - sweepStart >= sweepDur)
                end
            end
            if activeMode == "hitbox" then pcall(function() myHrp.Size = savedSize end) end
            if flung then
                return activeMode
            end
        end
        return false
    end)
    local usedMode = okMode and modeResult or false
    local flung = usedMode and true or false

    -- === INSTANT RESTORE ===
    if myHrp and myHrp.Parent and not targetingState.silent then
        pcall(function()
            myHrp.AssemblyAngularVelocity = savedRotVelocity
            myHrp.AssemblyLinearVelocity = savedVelocity
            myHrp.CFrame = savedCFrame
        end)
        -- Stabilize for a few physics frames so recoil from collisions does not launch us.
        for i = 1, 8 do
            RunService.Heartbeat:Wait()
            pcall(function()
                myHrp.CFrame = savedCFrame
                myHrp.AssemblyAngularVelocity = Vector3.zero
                myHrp.AssemblyLinearVelocity = (i < 8) and Vector3.zero or savedVelocity
            end)
        end
    end
    if myHrp and myHrp.Parent and targetingState.silent then
        local finalSilentCF = silentVisualCF
        pcall(function()
            myHrp.CFrame = finalSilentCF
            myHrp.AssemblyLinearVelocity = Vector3.zero
            myHrp.AssemblyAngularVelocity = Vector3.zero
        end)
        -- Settle at spoofed local position (not fling physics position) to avoid vertical pop.
        for _ = 1, 4 do
            RunService.Heartbeat:Wait()
            pcall(function()
                myHrp.CFrame = finalSilentCF
                myHrp.AssemblyLinearVelocity = Vector3.zero
                myHrp.AssemblyAngularVelocity = Vector3.zero
            end)
        end
    end

    pcall(function()
        if not targetingState.silent then
            myHum:ChangeState(previousState)
        elseif animateScript and animateWasEnabled ~= nil then
            animateScript.Enabled = animateWasEnabled
            myHum:ChangeState(Enum.HumanoidStateType.Running)
        end
    end)

    -- === RESTORE CAMERA ===
    if camLockConn then camLockConn:Disconnect() end
    if silentSpoofConn and silentSpoofConn ~= camLockConn then silentSpoofConn:Disconnect() end
    if cam then
        cam.CameraSubject = savedCamSubject
        cam.CameraType    = savedCamType or Enum.CameraType.Custom
    end

    flingInProgress = false

    if not antiWasEnabled and stopAntiFling and antiFlingState.enabled then
        stopAntiFling()
    end

    if not okMode then
        notify("Fling mode failed: " .. tostring(modeResult), "error", 2.2)
        return false
    end

    if flung then
        if not targetingState.silent then
            notify("Flung " .. target.DisplayName .. " [" .. (FLING_DATA.labels[usedMode] or mode) .. "]", "success", 2)
        end
    end

    return flung
end

Commands["fling"].Execute = function(args)
    if not args or not args[1] then error("Usage: ;fling <player|all|others|random> [blink|slam|hitbox]") end
    local targets = resolvePlayerList(args[1], { excludeSelf = true })
    if #targets == 0 then error("No players found: " .. args[1]) end
    local mode = "blink"
    if args[2] then
        local requested = tostring(args[2]):lower()
        if not FLING_DATA.labels[requested] then
            error("Unknown fling mode: " .. tostring(args[2]) .. " (use blink/slam/hitbox)")
        end
        mode = requested
    end
    for _, t in ipairs(targets) do
        if t ~= LocalPlayer then
            local ok, err = pcall(flingPlayer, t, mode)
            if not ok then
                notify("Fling failed on " .. t.DisplayName .. ": " .. tostring(err), "error", 2)
            end
        end
    end
end

startAntiFling = function()
    antiFlingState.enabled = true

    -- Record a safe position we can teleport back to
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    antiFlingState.safePos = hrp and hrp.CFrame or nil
    antiFlingState.lastGoodPos = antiFlingState.safePos
    antiFlingState.recovering = false

    local function isGrounded(cf)
        if not cf then return false end
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Blacklist
        params.FilterDescendantsInstances = { LocalPlayer.Character }
        local result = workspace:Raycast(cf.Position, Vector3.new(0, -8, 0), params)
        return result ~= nil
    end

    local function getRecoveryCFrame(current)
        local fallback = antiFlingState.lastGoodPos or antiFlingState.safePos or current
        if not fallback then return nil end
        local basePos = fallback.Position + Vector3.new(0, 4, 0)
        return CFrame.new(basePos) * (fallback - fallback.Position)
    end

    -- Main loop: runs every physics step (before physics sim)
    antiFlingState.connection = RunService.Stepped:Connect(function()
        local c = LocalPlayer.Character
        if not c then return end
        local h = c:FindFirstChild("HumanoidRootPart")
        if not h then return end

        -- 1) Only cancel unrealistic spikes, do not freeze normal movement.
        pcall(function()
            if h.AssemblyLinearVelocity.Magnitude > 100 then
                h.AssemblyLinearVelocity = Vector3.zero
            end
            if h.AssemblyAngularVelocity.Magnitude > 65 then
                h.AssemblyAngularVelocity = Vector3.zero
            end
            if h.AssemblyLinearVelocity.Y < -120 then
                h.AssemblyLinearVelocity = Vector3.new(h.AssemblyLinearVelocity.X, 0, h.AssemblyLinearVelocity.Z)
            end
        end)

        -- 2) Remove likely fling movers attached by other scripts/exploits.
        for _, child in ipairs(h:GetChildren()) do
            if (child:IsA("BodyAngularVelocity") or child:IsA("BodyVelocity")
                or child:IsA("BodyThrust") or child:IsA("BodyForce")
                or child:IsA("AngularVelocity") or child:IsA("LinearVelocity")
                or child:IsA("VectorForce") or child:IsA("AlignPosition")) then
                child:Destroy()
            end
        end

        -- 3) If we got displaced massively in one frame, snap back
        if antiFlingState.safePos then
            local dist = (h.Position - antiFlingState.safePos.Position).Magnitude
            local fallenY = (workspace.FallenPartsDestroyHeight or -500) - 15
            local underMap = h.Position.Y < fallenY
            if dist > 90 or underMap then
                antiFlingState.recovering = true
                local recoverCF = getRecoveryCFrame(h.CFrame)
                pcall(function()
                    if recoverCF then
                        h.CFrame = recoverCF
                    end
                    h.AssemblyLinearVelocity = Vector3.zero
                    h.AssemblyAngularVelocity = Vector3.zero
                end)
                task.delay(0.2, function()
                    antiFlingState.recovering = false
                end)
            else
                local speed = h.AssemblyLinearVelocity.Magnitude
                if speed <= 55 and not antiFlingState.recovering and isGrounded(h.CFrame) then
                    antiFlingState.safePos = h.CFrame
                    antiFlingState.lastGoodPos = h.CFrame
                end
            end
        else
            antiFlingState.safePos = h.CFrame
            antiFlingState.lastGoodPos = h.CFrame
        end
    end)

    -- Secondary loop: runs on Heartbeat (after physics) as a second pass
    antiFlingState.heartbeatConn = RunService.Heartbeat:Connect(function()
        local c = LocalPlayer.Character
        if not c then return end
        local h = c:FindFirstChild("HumanoidRootPart")
        if not h then return end
        pcall(function()
            if h.AssemblyLinearVelocity.Magnitude > 110 then
                h.AssemblyLinearVelocity = Vector3.zero
            end
            if h.AssemblyAngularVelocity.Magnitude > 70 then
                h.AssemblyAngularVelocity = Vector3.zero
            end
            if h.AssemblyLinearVelocity.Y < -120 then
                h.AssemblyLinearVelocity = Vector3.new(h.AssemblyLinearVelocity.X, 0, h.AssemblyLinearVelocity.Z)
            end
        end)
    end)
end

stopAntiFling = function()
    antiFlingState.enabled = false
    if antiFlingState.connection then
        antiFlingState.connection:Disconnect()
        antiFlingState.connection = nil
    end
    if antiFlingState.heartbeatConn then
        antiFlingState.heartbeatConn:Disconnect()
        antiFlingState.heartbeatConn = nil
    end
    antiFlingState.safePos = nil
    antiFlingState.lastGoodPos = nil
    antiFlingState.recovering = false
end

Commands["antifling"].Execute = function()
    if antiFlingState.enabled then
        stopAntiFling()
        notify("Anti-fling disabled", "info", 2)
    else
        startAntiFling()
        notify("Anti-fling enabled", "success", 2)
    end
end

-------------------------------------------------
-- CLICK-FLING
-- Toggleable mode with two binds:
-- 1) toggle bind enables/disables click-fling
-- 2) trigger bind flings the closest player to your cursor once
-- Includes mode selector plus silent/resolver toggles.
-------------------------------------------------
clickFlingState = clickFlingState or {
    enabled   = false,
    bind      = Enum.KeyCode.E,
    triggerBind = Enum.KeyCode.R,
    mode      = "blink",
    circle    = nil,
    renderConn = nil,
    inputConn  = nil,
    screenGui  = nil,
}
if type(persistedConfig.clickFlingMode) == "string" and FLING_DATA.labels[persistedConfig.clickFlingMode] then
    clickFlingState.mode = persistedConfig.clickFlingMode
end
if type(persistedConfig.clickFlingBind) == "string" and Enum.KeyCode[persistedConfig.clickFlingBind] then
    clickFlingState.bind = Enum.KeyCode[persistedConfig.clickFlingBind]
end
if type(persistedConfig.clickFlingTriggerBind) == "string" and Enum.KeyCode[persistedConfig.clickFlingTriggerBind] then
    clickFlingState.triggerBind = Enum.KeyCode[persistedConfig.clickFlingTriggerBind]
end

local function stopClickFling()
    clickFlingState.enabled = false
    if clickFlingState.renderConn then clickFlingState.renderConn:Disconnect() end
    if clickFlingState.inputConn  then clickFlingState.inputConn:Disconnect()  end
    clickFlingState.renderConn = nil
    clickFlingState.inputConn  = nil
    if clickFlingState.circle and clickFlingState.circle.Parent then
        clickFlingState.circle:Destroy()
    end
    if clickFlingState.screenGui and clickFlingState.screenGui.Parent then
        clickFlingState.screenGui:Destroy()
    end
    clickFlingState.circle = nil
    clickFlingState.screenGui = nil
end

local function startClickFling()
    if clickFlingState.enabled then return end
    clickFlingState.enabled = true
    notify("Click-fling enabled — press " .. clickFlingState.triggerBind.Name .. " to fling closest to cursor", "success", 2)
end

local function getClosestPlayerToMouse()
    local camera = workspace.CurrentCamera
    if not camera then return nil end
    local mouse = UserInputService:GetMouseLocation()
    local bestPlayer, bestDist = nil, math.huge
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and p.Character then
            local part = p.Character:FindFirstChild("Head") or p.Character:FindFirstChild("HumanoidRootPart")
            if part then
                local screen, onScreen = camera:WorldToViewportPoint(part.Position)
                if onScreen and screen.Z > 0 then
                    local dx = screen.X - mouse.X
                    local dy = screen.Y - mouse.Y
                    local dist = math.sqrt(dx * dx + dy * dy)
                    if dist < bestDist then
                        bestDist = dist
                        bestPlayer = p
                    end
                end
            end
        end
    end
    return bestPlayer
end

-- Click-fling panel
clickFlingPanel = createToolPanel({
    Name = "ClickFlingPanel",
    Title = "Click Fling",
    Width = 260,
    Height = 425,
    Position = UDim2.new(0.5, -130, 0.5, -175),
})

createLabel("ENABLED", clickFlingPanel.Content, UDim2.new(0, 0, 0, 4))
clickFlingToggle = createToggleButton(clickFlingPanel.Content, UDim2.new(0, 0, 0, 20))
clickFlingToggle.OnToggle(function(enabled)
    if enabled then
        startClickFling()
    else
        stopClickFling()
        notify("Click-fling disabled", "info", 2)
    end
end)

createLabel("FLING MODE", clickFlingPanel.Content, UDim2.new(0, 0, 0, 59))
local clickFlingModeCycle = createCycleButton(
    clickFlingPanel.Content,
    UDim2.new(0, 0, 0, 75),
    FLING_DATA.modes,
    clickFlingState.mode,
    function(v) return FLING_DATA.labels[v] or v end
)
clickFlingModeCycle.OnChange(function(newMode)
    clickFlingState.mode = newMode
    persistedConfig.clickFlingMode = newMode
    savePersistedConfig()
    notify("Click-fling mode: " .. (FLING_DATA.labels[newMode] or newMode), "info", 2)
end)

createLabel("TOGGLE BIND", clickFlingPanel.Content, UDim2.new(0, 0, 0, 113))
local clickFlingBindBtn = createHotkeyButton(clickFlingPanel.Content, UDim2.new(0, 0, 0, 129), clickFlingState.bind)
clickFlingBindBtn.OnChange(function(newKey)
    clickFlingState.bind = newKey
    persistedConfig.clickFlingBind = newKey.Name
    savePersistedConfig()
    notify("Click-fling bind set to " .. newKey.Name, "info", 2)
end)

createLabel("FLING TRIGGER BIND", clickFlingPanel.Content, UDim2.new(0, 0, 0, 167))
local clickFlingTriggerBindBtn = createHotkeyButton(clickFlingPanel.Content, UDim2.new(0, 0, 0, 183), clickFlingState.triggerBind)
clickFlingTriggerBindBtn.OnChange(function(newKey)
    clickFlingState.triggerBind = newKey
    persistedConfig.clickFlingTriggerBind = newKey.Name
    savePersistedConfig()
    notify("Click-fling trigger bind set to " .. newKey.Name, "info", 2)
end)

createLabel("SILENT MODE", clickFlingPanel.Content, UDim2.new(0, 0, 0, 221))
local silentToggle = createToggleButton(clickFlingPanel.Content, UDim2.new(0, 0, 0, 237), targetingState.silent)
silentToggle.OnToggle(function(enabled)
    targetingState.silent = enabled
    setToggleState("silent", enabled)
    notify("Silent mode " .. (enabled and "enabled" or "disabled"), "info", 2)
end)

createLabel("VELOCITY RESOLVER", clickFlingPanel.Content, UDim2.new(0, 0, 0, 275))
local resolverToggle = createToggleButton(clickFlingPanel.Content, UDim2.new(0, 0, 0, 291), targetingState.velocityResolver)
resolverToggle.OnToggle(function(enabled)
    targetingState.velocityResolver = enabled
    if not enabled then targetingState.velocityCache = {} end
    setToggleState("resolver", enabled)
    notify("Velocity resolver " .. (enabled and "enabled" or "disabled"), "info", 2)
end)

createLabel("ALWAYS ACTIVE HOTKEY", clickFlingPanel.Content, UDim2.new(0, 0, 0, 329))
do
    local t = createToggleButton(clickFlingPanel.Content, UDim2.new(0, 0, 0, 345), hotkeyAlwaysActive["clickfling"] or false)
    t.OnToggle(function(enabled)
        hotkeyAlwaysActive["clickfling"] = enabled
        persistedConfig.hotkeyAlwaysActive["clickfling"] = enabled or nil
        savePersistedConfig()
        notify("Click-fling hotkey " .. (enabled and "always active" or "panel-only"), "info", 2)
    end)
end

create("TextLabel", {
    Size = UDim2.new(1, 0, 0, 14),
    Position = UDim2.new(0, 0, 0, 381),
    BackgroundTransparency = 1,
    Text = "Use trigger bind to fling closest player to cursor",
    TextColor3 = Theme.TextMuted,
    TextSize = 10,
    Font = Theme.Font,
    TextXAlignment = Enum.TextXAlignment.Center,
    Parent = clickFlingPanel.Content,
})

Commands["clickfling"].Execute = function()
    task.defer(function()
        if not clickFlingPanel.IsOpen() then
            clickFlingPanel.Show()
        end
    end)
end

-------------------------------------------------
-- SPECTATE / FREECAM
-------------------------------------------------
local spectateState = { target = nil }
local freecamState = { enabled = false, connection = nil, cf = nil }

local function stopSpectate()
    if spectateState.target then
        local cam = workspace.CurrentCamera
        if cam and LocalPlayer.Character then
            local myHum = LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
            if myHum then
                cam.CameraSubject = myHum
            end
        end
        spectateState.target = nil
    end
end

Commands["spectate"].Execute = function(args)
    if not args or not args[1] then error("Usage: ;spectate <player|off|random|nearest>") end
    if args[1]:lower() == "off" then
        stopSpectate()
        notify("Spectate off", "info", 2)
        return
    end
    local targets = resolvePlayerList(args[1], { excludeSelf = true })
    local target = targets[1]
    if not target then error("Player not found: " .. args[1]) end
    if not target.Character then error("Target has no character") end
    local hum = target.Character:FindFirstChildOfClass("Humanoid")
    if not hum then error("Target has no humanoid") end

    local cam = workspace.CurrentCamera
    if cam then
        cam.CameraSubject = hum
        spectateState.target = target
        notify("Spectating " .. target.DisplayName, "success", 2)
    end
end

local function stopFreecam()
    freecamState.enabled = false
    if freecamState.connection then
        freecamState.connection:Disconnect()
        freecamState.connection = nil
    end
    local cam = workspace.CurrentCamera
    if cam then
        cam.CameraType = Enum.CameraType.Custom
        if LocalPlayer.Character then
            local hum = LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
            if hum then cam.CameraSubject = hum end
        end
    end
end

local function startFreecam()
    local cam = workspace.CurrentCamera
    if not cam then return end
    freecamState.enabled = true
    freecamState.cf = cam.CFrame
    cam.CameraType = Enum.CameraType.Scriptable
    freecamState.connection = RunService.RenderStepped:Connect(function(dt)
        if not freecamState.enabled then return end
        local speed = 50 * dt
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then speed = speed * 3 end
        local moveDir = Vector3.new(0, 0, 0)
        local cf = freecamState.cf
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then moveDir = moveDir + cf.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then moveDir = moveDir - cf.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then moveDir = moveDir - cf.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then moveDir = moveDir + cf.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.E) then moveDir = moveDir + Vector3.new(0, 1, 0) end
        if UserInputService:IsKeyDown(Enum.KeyCode.Q) then moveDir = moveDir - Vector3.new(0, 1, 0) end
        if moveDir.Magnitude > 0 then moveDir = moveDir.Unit end
        freecamState.cf = cf + moveDir * speed
        cam.CFrame = freecamState.cf
    end)
end

Commands["freecam"].Execute = function()
    if freecamState.enabled then
        stopFreecam()
        notify("Freecam off", "info", 2)
    else
        startFreecam()
        notify("Freecam on · WASD/E/Q · Shift boost", "success", 3)
    end
end

-------------------------------------------------
-- PREFIX COMMAND
-------------------------------------------------
Commands["prefix"].Execute = function(args)
    if not args or not args[1] then error("Usage: ;prefix <newprefix>") end
    local newPrefix = args[1]
    if #newPrefix > 3 then error("Prefix must be 1-3 characters") end
    CONFIG.Prefix = newPrefix
    notify("Prefix changed to '" .. newPrefix .. "'", "success", 3)
end

-------------------------------------------------
-- TEXT INPUT UTILITY (reusable across panels)
-------------------------------------------------
local function createTextInput(parent, position, placeholder, initialText)
    local container = create("Frame", {
        Size = UDim2.new(1, 0, 0, 32),
        Position = position,
        BackgroundColor3 = Theme.Surface,
        BorderSizePixel = 0,
        Parent = parent,
    }, {
        create("UICorner", { CornerRadius = UDim.new(0, 6) }),
        create("UIStroke", {
            Color = Theme.Border,
            Thickness = 1,
            Transparency = 0.5,
        }),
    })

    local box = create("TextBox", {
        Size = UDim2.new(1, -16, 1, 0),
        Position = UDim2.new(0, 8, 0, 0),
        BackgroundTransparency = 1,
        Text = initialText or "",
        PlaceholderText = placeholder or "",
        PlaceholderColor3 = Theme.TextMuted,
        TextColor3 = Theme.Text,
        TextSize = 12,
        Font = Theme.Font,
        TextXAlignment = Enum.TextXAlignment.Left,
        ClearTextOnFocus = false,
        Parent = container,
    })

    local stroke = container:FindFirstChildOfClass("UIStroke")
    box.Focused:Connect(function()
        if stroke then
            tween(stroke, quickTween, { Color = Theme.AccentPrimary, Transparency = 0.2 })
        end
    end)
    box.FocusLost:Connect(function()
        if stroke then
            tween(stroke, quickTween, { Color = Theme.Border, Transparency = 0.5 })
        end
    end)

    return {
        Container = container,
        Box = box,
        GetText = function() return box.Text end,
        SetText = function(t) box.Text = t or "" end,
    }
end

-------------------------------------------------
-- SETTINGS PANEL
-------------------------------------------------
local settingsPanel
do

local function applyAccentColor(primary, secondary)
    Theme.AccentPrimary = primary
    Theme.AccentSecondary = secondary or primary
    -- Recolor known UIGradients in the UI
    for _, d in ipairs(ScreenGui:GetDescendants()) do
        if d:IsA("UIGradient") then
            local seq = d.Color
            local keys = seq.Keypoints
            if #keys >= 2 then
                local newKeys = {}
                for i, kp in ipairs(keys) do
                    local t = kp.Time
                    local c
                    if t <= 0.01 then
                        c = Theme.AccentPrimary
                    elseif t >= 0.99 then
                        c = Theme.AccentPrimary
                    else
                        c = Theme.AccentSecondary
                    end
                    table.insert(newKeys, ColorSequenceKeypoint.new(t, c))
                end
                pcall(function() d.Color = ColorSequence.new(newKeys) end)
            end
        end
    end
end

settingsPanel = createToolPanel({
    Name = "SettingsPanel",
    Title = "Settings",
    Icon = "#",
    Width = 320,
    Height = 440,
    Position = UDim2.new(0.5, -160, 0.5, -220),
})

local _settingsY = 4

createLabel("PREFIX", settingsPanel.Content, UDim2.new(0, 0, 0, _settingsY))
_settingsY = _settingsY + 16
local prefixInput = createTextInput(settingsPanel.Content, UDim2.new(0, 0, 0, _settingsY), "e.g. ;", CONFIG.Prefix)
prefixInput.Box.FocusLost:Connect(function()
    local newPrefix = prefixInput.GetText()
    if #newPrefix < 1 or #newPrefix > 3 then
        notify("Prefix must be 1-3 characters", "error", 2)
        prefixInput.SetText(CONFIG.Prefix)
        return
    end
    CONFIG.Prefix = newPrefix
    persistedConfig.prefix = newPrefix
    savePersistedConfig()
    notify("Prefix changed to '" .. newPrefix .. "'", "success", 2)
end)
_settingsY = _settingsY + 40

createLabel("NICKNAME", settingsPanel.Content, UDim2.new(0, 0, 0, _settingsY))
_settingsY = _settingsY + 16
local nickInput = createTextInput(settingsPanel.Content, UDim2.new(0, 0, 0, _settingsY), LocalPlayer.DisplayName, PlayerNameLabel.Text)
nickInput.Box.FocusLost:Connect(function()
    local n = nickInput.GetText()
    if #n == 0 then
        nickInput.SetText(PlayerNameLabel.Text)
        return
    end
    PlayerNameLabel.Text = n
    persistedConfig.nickname = n
    savePersistedConfig()
    notify("Nickname updated", "success", 2)
end)
_settingsY = _settingsY + 40

createLabel("ACCENT COLOR", settingsPanel.Content, UDim2.new(0, 0, 0, _settingsY))
_settingsY = _settingsY + 16
local swatchesFrame = create("Frame", {
    Size = UDim2.new(1, 0, 0, 28),
    Position = UDim2.new(0, 0, 0, _settingsY),
    BackgroundTransparency = 1,
    Parent = settingsPanel.Content,
}, {
    create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        Padding = UDim.new(0, 6),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }),
})

local swatchColors = {
    { Color3.fromRGB(99, 102, 241),  Color3.fromRGB(139, 92, 246)  }, -- indigo/purple
    { Color3.fromRGB(239, 68, 68),   Color3.fromRGB(251, 146, 60)  }, -- red/orange
    { Color3.fromRGB(34, 197, 94),   Color3.fromRGB(16, 185, 129)  }, -- green
    { Color3.fromRGB(59, 130, 246),  Color3.fromRGB(14, 165, 233)  }, -- blue/cyan
    { Color3.fromRGB(236, 72, 153),  Color3.fromRGB(244, 114, 182) }, -- pink
    { Color3.fromRGB(250, 204, 21),  Color3.fromRGB(251, 191, 36)  }, -- yellow
    { Color3.fromRGB(156, 163, 175), Color3.fromRGB(209, 213, 219) }, -- gray
}
for i, pair in ipairs(swatchColors) do
    local sw = create("TextButton", {
        Size = UDim2.new(0, 28, 0, 28),
        BackgroundColor3 = pair[1],
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Text = "",
        LayoutOrder = i,
        Parent = swatchesFrame,
    }, {
        create("UICorner", { CornerRadius = UDim.new(0, 6) }),
        create("UIGradient", {
            Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, pair[1]),
                ColorSequenceKeypoint.new(1, pair[2]),
            }),
            Rotation = 45,
        }),
    })
    sw.MouseButton1Click:Connect(function()
        playClickSound()
        applyAccentColor(pair[1], pair[2])
        persistedConfig.accentPrimary = {
            r = math.floor(pair[1].R * 255 + 0.5),
            g = math.floor(pair[1].G * 255 + 0.5),
            b = math.floor(pair[1].B * 255 + 0.5),
        }
        persistedConfig.accentSecondary = {
            r = math.floor(pair[2].R * 255 + 0.5),
            g = math.floor(pair[2].G * 255 + 0.5),
            b = math.floor(pair[2].B * 255 + 0.5),
        }
        savePersistedConfig()
        notify("Accent color updated", "success", 2)
    end)
end
_settingsY = _settingsY + 40

createLabel("CUSTOM COMMAND", settingsPanel.Content, UDim2.new(0, 0, 0, _settingsY))
_settingsY = _settingsY + 16
local cmdNameInput = createTextInput(settingsPanel.Content, UDim2.new(0, 0, 0, _settingsY), "name (e.g. hello)", "")
_settingsY = _settingsY + 36
local cmdSrcInput = createTextInput(settingsPanel.Content, UDim2.new(0, 0, 0, _settingsY), "lua body (e.g. notify('hi'))", "")
_settingsY = _settingsY + 36

local addCmdBtn = create("TextButton", {
    Size = UDim2.new(1, 0, 0, 30),
    Position = UDim2.new(0, 0, 0, _settingsY),
    BackgroundColor3 = Theme.AccentPrimary,
    BackgroundTransparency = 0.4,
    BorderSizePixel = 0,
    AutoButtonColor = false,
    Text = "ADD CUSTOM COMMAND",
    TextColor3 = Theme.Text,
    TextSize = 12,
    Font = Theme.FontBold,
    Parent = settingsPanel.Content,
}, {
    create("UICorner", { CornerRadius = UDim.new(0, 6) }),
    create("UIStroke", {
        Color = Theme.AccentPrimary,
        Thickness = 1,
        Transparency = 0.3,
    }),
})
local function registerCustomCommand(cname, csrc)
    local fn, err = loadstring("return function(args) " .. csrc .. " end")
    if not fn then return false, tostring(err) end
    local ok, executor = pcall(fn)
    if not ok or type(executor) ~= "function" then
        return false, tostring(executor)
    end
    Commands[cname] = {
        Name = cname,
        Aliases = {},
        Description = "Custom: " .. csrc:sub(1, 40),
        Args = {"...args"},
        Local = true,
        Custom = true,
        Execute = executor,
    }
    return true
end

-- Replay any persisted custom commands from disk
if type(persistedConfig.customCommands) == "table" then
    for _, entry in ipairs(persistedConfig.customCommands) do
        if type(entry) == "table" and type(entry.name) == "string" and type(entry.source) == "string" then
            if not Commands[entry.name] then
                pcall(registerCustomCommand, entry.name, entry.source)
            end
        end
    end
end

addCmdBtn.MouseButton1Click:Connect(function()
    playClickSound()
    local cname = cmdNameInput.GetText():lower():gsub("%s+", "")
    local csrc = cmdSrcInput.GetText()
    if cname == "" or csrc == "" then
        notify("Name and source required", "error", 2)
        return
    end
    if Commands[cname] then
        notify("Command '" .. cname .. "' already exists", "error", 2)
        return
    end
    local ok, err = registerCustomCommand(cname, csrc)
    if not ok then
        notify("Compile error: " .. tostring(err), "error", 4)
        return
    end
    persistedConfig.customCommands = persistedConfig.customCommands or {}
    table.insert(persistedConfig.customCommands, { name = cname, source = csrc })
    savePersistedConfig()
    cmdNameInput.SetText("")
    cmdSrcInput.SetText("")
    notify("Added custom command ;" .. cname, "success", 3)
end)
_settingsY = _settingsY + 40

Commands["settings"].Execute = function()
    task.defer(function()
        if not settingsPanel.IsOpen() then
            settingsPanel.Show()
        end
    end)
end

end -- do (settings panel scope)

-------------------------------------------------
-- NEW COMMANDS (bring, refresh, chat, hidechar, hideui, copy)
-------------------------------------------------
Commands["bring"].Execute = function(args)
    if not args or not args[1] then error("Usage: ;bring <player|all|others>") end
    local myChar = LocalPlayer.Character
    local myHrp = myChar and myChar:FindFirstChild("HumanoidRootPart")
    if not myHrp then error("You have no character") end
    local targets = resolvePlayerList(args[1], { excludeSelf = true })
    if #targets == 0 then error("No players found: " .. args[1]) end
    local count = 0
    for i, p in ipairs(targets) do
        if p ~= LocalPlayer and p.Character then
            local hrp = p.Character:FindFirstChild("HumanoidRootPart")
            if hrp then
                pcall(function()
                    hrp.CFrame = myHrp.CFrame * CFrame.new(math.cos(i) * 4, 0, math.sin(i) * 4)
                end)
                count = count + 1
            end
        end
    end
    notify("Attempted bring on " .. count .. " target(s)", "info", 2)
end

Commands["respawn"].Execute = function()
    local char = LocalPlayer.Character
    if not char then error("No character") end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    local savedCFrame = hrp and hrp.CFrame
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if humanoid then
        humanoid.Health = 0
    end
    if savedCFrame then
        local conn
        conn = LocalPlayer.CharacterAdded:Connect(function(newChar)
            if conn then conn:Disconnect() conn = nil end
            task.wait(0.1)
            local newHrp = newChar:WaitForChild("HumanoidRootPart", 5)
            if newHrp then
                pcall(function() newHrp.CFrame = savedCFrame end)
            end
        end)
        task.delay(10, function()
            if conn then conn:Disconnect() conn = nil end
        end)
    end
    notify("Refreshing character...", "info", 2)
end

Commands["chat"].Execute = function(args)
    if not args or not args[1] then error("Usage: ;chat <message>") end
    local msg = table.concat(args, " ")
    local ok, err = pcall(function()
        local chatEvents = game:GetService("ReplicatedStorage"):FindFirstChild("DefaultChatSystemChatEvents")
        if chatEvents then
            local sayMsg = chatEvents:FindFirstChild("SayMessageRequest")
            if sayMsg then
                sayMsg:FireServer(msg, "All")
                return
            end
        end
        local TextChatService = game:GetService("TextChatService")
        local generalChannel = TextChatService:FindFirstChild("TextChannels")
            and TextChatService.TextChannels:FindFirstChild("RBXGeneral")
        if generalChannel then
            generalChannel:SendAsync(msg)
            return
        end
        error("No chat system found")
    end)
    if not ok then
        notify("Chat failed: " .. tostring(err), "error", 3)
    end
end

local hideCharState = { hidden = false, savedTransparency = {} }
Commands["hidechar"].Execute = function()
    local char = LocalPlayer.Character
    if not char then error("No character") end
    if hideCharState.hidden then
        for part, t in pairs(hideCharState.savedTransparency) do
            if part and part.Parent then
                pcall(function() part.LocalTransparencyModifier = t end)
            end
        end
        hideCharState.savedTransparency = {}
        hideCharState.hidden = false
        notify("Character shown", "info", 2)
    else
        hideCharState.savedTransparency = {}
        for _, d in ipairs(char:GetDescendants()) do
            if d:IsA("BasePart") or d:IsA("Decal") then
                hideCharState.savedTransparency[d] = d.LocalTransparencyModifier
                pcall(function() d.LocalTransparencyModifier = 1 end)
            end
        end
        hideCharState.hidden = true
        notify("Character hidden locally", "success", 2)
    end
end

local hideUIState = { hidden = false }
Commands["hideui"].Execute = function()
    hideUIState.hidden = not hideUIState.hidden
    ScreenGui.Enabled = not hideUIState.hidden
    if not hideUIState.hidden then
        notify("UI shown", "info", 2)
    end
end

Commands["copy"].Execute = function(args)
    if not args or not args[1] then error("Usage: ;copy <text>") end
    local text = table.concat(args, " ")
    local clip = (setclipboard or (syn and syn.write_clipboard) or (toclipboard) or (writeclipboard))
    if not clip then
        error("Clipboard not supported by executor")
    end
    local ok, err = pcall(clip, text)
    if not ok then
        error("Copy failed: " .. tostring(err))
    end
    notify("Copied " .. #text .. " chars to clipboard", "success", 2)
end

-------------------------------------------------
-- TOGGLE STATE REGISTRY
-- Each toggleable command publishes its on/off state here so the
-- command palette can show an "ON" tag next to currently-enabled ones.
-------------------------------------------------
local toggleStates = {}
local setToggleState, getToggleState
function setToggleState(name, on)
    toggleStates[name] = on and true or nil
end
function getToggleState(name)
    return toggleStates[name] == true
end

do

-------------------------------------------------
-- UNLOAD
-------------------------------------------------
Commands["unload"].Execute = function()
    notify("Unloading UniversalAdmin...", "info", 2)
    task.delay(0.3, function()
        -- Stop all toggles best-effort
        pcall(function() if stopFly then stopFly() end end)
        pcall(function() if stopNoclip then stopNoclip() end end)
        pcall(function() if stopESP then stopESP() end end)
        pcall(function() if stopClickFling then stopClickFling() end end)
        pcall(function() if stopSpectate then stopSpectate() end end)
        pcall(function() if stopFreecam then stopFreecam() end end)
        pcall(function() if stopAntiFling then stopAntiFling() end end)
        -- Clean up nametag BillboardGuis (parented to character Heads, not CoreGui)
        pcall(function()
            if nametagState and nametagState.tags then
                for player, tag in pairs(nametagState.tags) do
                    if tag and tag.Parent then tag:Destroy() end
                end
                nametagState.tags = {}
            end
        end)
        -- Remove any UA_ BillboardGuis left on player characters
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
        -- Destroy all UI
        pcall(function() if ScreenGui and ScreenGui.Parent then ScreenGui:Destroy() end end)
        for _, child in ipairs(CoreGui:GetChildren()) do
            if child.Name:sub(1, 15) == "UniversalAdmin" then
                pcall(function() child:Destroy() end)
            end
        end
    end)
end

-------------------------------------------------
-- CLICK-TP
-- Click anywhere in the world to teleport there. Toggleable with
-- a configurable bind key via its own panel.
-------------------------------------------------
local clickTpState = {
    enabled = false,
    bind    = Enum.KeyCode.T,
    conn    = nil,
}

local function stopClickTp()
    clickTpState.enabled = false
    if clickTpState.conn then clickTpState.conn:Disconnect() end
    clickTpState.conn = nil
    setToggleState("clicktp", false)
end

local function startClickTp()
    if clickTpState.enabled then return end
    clickTpState.enabled = true
    setToggleState("clicktp", true)
    clickTpState.conn = UserInputService.InputBegan:Connect(function(input, gp)
        if gp then return end
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
        -- Check modifier/bind: require bind key to be held while clicking.
        -- If bind is None, accept any click.
        local heldOk = true
        if clickTpState.bind and clickTpState.bind ~= Enum.KeyCode.Unknown then
            heldOk = UserInputService:IsKeyDown(clickTpState.bind)
        end
        if not heldOk then return end
        local char = LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then return end
        local cam = workspace.CurrentCamera
        if not cam then return end
        local mouse = UserInputService:GetMouseLocation()
        local unitRay = cam:ViewportPointToRay(mouse.X, mouse.Y)
        local rayParams = RaycastParams.new()
        rayParams.FilterDescendantsInstances = { char }
        rayParams.FilterType = Enum.RaycastFilterType.Exclude
        local result = workspace:Raycast(unitRay.Origin, unitRay.Direction * 5000, rayParams)
        if result then
            pcall(function()
                hrp.CFrame = CFrame.new(result.Position + Vector3.new(0, 3, 0))
            end)
        end
    end)
end

local clickTpPanel = createToolPanel({
    Name = "ClickTpPanel",
    Title = "Click Teleport",
    Width = 260,
    Height = 200,
    Position = UDim2.new(0.5, -130, 0.5, -100),
})

createLabel("ENABLED", clickTpPanel.Content, UDim2.new(0, 0, 0, 4))
local clickTpToggle = createToggleButton(clickTpPanel.Content, UDim2.new(0, 0, 0, 20))
clickTpToggle.OnToggle(function(enabled)
    if enabled then
        startClickTp()
        notify("Click-teleport enabled (hold " .. clickTpState.bind.Name .. " + click)", "success", 3)
    else
        stopClickTp()
        notify("Click-teleport disabled", "info", 2)
    end
end)

createLabel("BIND (hold + click to TP)", clickTpPanel.Content, UDim2.new(0, 0, 0, 60))
local clickTpBindBtn = createHotkeyButton(clickTpPanel.Content, UDim2.new(0, 0, 0, 76), clickTpState.bind)
clickTpBindBtn.OnChange(function(newKey)
    clickTpState.bind = newKey
    notify("Click-TP bind: hold " .. newKey.Name .. " + click", "info", 2)
end)

create("TextLabel", {
    Size = UDim2.new(1, 0, 0, 14),
    Position = UDim2.new(0, 0, 0, 120),
    BackgroundTransparency = 1,
    Text = "Hold bind + left click anywhere to teleport",
    TextColor3 = Theme.TextMuted,
    TextSize = 10,
    Font = Theme.Font,
    TextXAlignment = Enum.TextXAlignment.Center,
    Parent = clickTpPanel.Content,
})

Commands["clicktp"].Execute = function()
    task.defer(function()
        if not clickTpPanel.IsOpen() then
            clickTpPanel.Show()
        end
    end)
end

-------------------------------------------------
-- FULLBRIGHT
-------------------------------------------------
local fullbrightState = {
    enabled = false,
    savedBrightness = nil,
    savedAmbient = nil,
    savedOutdoor = nil,
    savedFogEnd = nil,
    savedGlobalShadows = nil,
    savedClockTime = nil,
    conn = nil,
}

local function stopFullbright()
    fullbrightState.enabled = false
    setToggleState("fullbright", false)
    if fullbrightState.conn then fullbrightState.conn:Disconnect() end
    fullbrightState.conn = nil
    local Lighting = game:GetService("Lighting")
    pcall(function()
        if fullbrightState.savedBrightness ~= nil then Lighting.Brightness = fullbrightState.savedBrightness end
        if fullbrightState.savedAmbient ~= nil then Lighting.Ambient = fullbrightState.savedAmbient end
        if fullbrightState.savedOutdoor ~= nil then Lighting.OutdoorAmbient = fullbrightState.savedOutdoor end
        if fullbrightState.savedFogEnd ~= nil then Lighting.FogEnd = fullbrightState.savedFogEnd end
        if fullbrightState.savedGlobalShadows ~= nil then Lighting.GlobalShadows = fullbrightState.savedGlobalShadows end
        if fullbrightState.savedClockTime ~= nil then Lighting.ClockTime = fullbrightState.savedClockTime end
    end)
end

local function startFullbright()
    fullbrightState.enabled = true
    setToggleState("fullbright", true)
    local Lighting = game:GetService("Lighting")
    fullbrightState.savedBrightness    = Lighting.Brightness
    fullbrightState.savedAmbient       = Lighting.Ambient
    fullbrightState.savedOutdoor       = Lighting.OutdoorAmbient
    fullbrightState.savedFogEnd        = Lighting.FogEnd
    fullbrightState.savedGlobalShadows = Lighting.GlobalShadows
    fullbrightState.savedClockTime     = Lighting.ClockTime

    local function apply()
        Lighting.Brightness      = 2
        Lighting.Ambient         = Color3.fromRGB(178, 178, 178)
        Lighting.OutdoorAmbient  = Color3.fromRGB(178, 178, 178)
        Lighting.FogEnd          = 1e9
        Lighting.GlobalShadows   = false
        Lighting.ClockTime       = 14
    end
    pcall(apply)
    -- Hold it against games that re-apply lighting every frame
    fullbrightState.conn = RunService.RenderStepped:Connect(function()
        if not fullbrightState.enabled then return end
        pcall(apply)
    end)
end

Commands["fullbright"].Execute = function()
    if fullbrightState.enabled then
        stopFullbright()
        notify("Fullbright off", "info", 2)
    else
        startFullbright()
        notify("Fullbright on", "success", 2)
    end
end

-------------------------------------------------
-- REMOTE SPY
-- Hooks __namecall to log RemoteEvent:FireServer / RemoteFunction:InvokeServer.
-- Requires the executor to provide hookmetamethod + getnamecallmethod.
-- Output goes to the console via `print` - user can pipe to rconsole too.
-------------------------------------------------
local remoteSpyState = { enabled = false, oldNamecall = nil }

local function stopRemoteSpy()
    remoteSpyState.enabled = false
    setToggleState("remotespy", false)
    -- Note: hookmetamethod cannot be cleanly unhooked on most executors
    -- without the original ref. We leave the flag off so the hook passes through.
end

local function startRemoteSpy()
    if remoteSpyState.enabled then return end
    if type(hookmetamethod) ~= "function" or type(getnamecallmethod) ~= "function" then
        error("remotespy requires executor with hookmetamethod + getnamecallmethod")
    end
    remoteSpyState.enabled = true
    setToggleState("remotespy", true)

    if not remoteSpyState.hooked then
        remoteSpyState.hooked = true
        local old
        old = hookmetamethod(game, "__namecall", function(self, ...)
            if remoteSpyState.enabled then
                local method = getnamecallmethod()
                if method == "FireServer" or method == "InvokeServer" then
                    local ok, path = pcall(function() return self:GetFullName() end)
                    local args = {...}
                    local argStr = {}
                    for i, v in ipairs(args) do
                        argStr[i] = tostring(v)
                    end
                    local line = "[RemoteSpy] " .. method .. " " .. (ok and path or "?")
                        .. " (" .. table.concat(argStr, ", ") .. ")"
                    print(line)
                    if type(rconsoleprint) == "function" then
                        pcall(rconsoleprint, line .. "\n")
                    end
                end
            end
            return old(self, ...)
        end)
        remoteSpyState.oldNamecall = old
    end
end

Commands["remotespy"].Execute = function()
    if remoteSpyState.enabled then
        stopRemoteSpy()
        notify("Remote spy off", "info", 2)
    else
        local ok, err = pcall(startRemoteSpy)
        if not ok then
            notify(tostring(err), "error", 4)
            return
        end
        notify("Remote spy on - check console (print)", "success", 3)
    end
end

-------------------------------------------------
-- DEX EXPLORER
-------------------------------------------------
local dexState = { loaded = false }
local function loadDex()
    if dexState.loaded then
        notify("Dex already loaded", "info", 2)
        return
    end
    local ok, err = pcall(function()
        loadstring(game:HttpGet("https://rawscripts.net/raw/Universal-Script-SECURE-DEX-AND-REMOTE-SPY-205256"))()
    end)
    if ok then
        dexState.loaded = true
        notify("Dex explorer loaded", "success", 3)
    else
        notify("Dex load failed: " .. tostring(err), "error", 4)
    end
end

Commands["dex"].Execute = loadDex

-------------------------------------------------
-- CHAT LOG
-------------------------------------------------
local chatLogState = {
    entries = {},  -- { { player, name, text, time, timestamp } }
    conns = {},
}

local function addChatEntry(player, text)
    if not player or not text then return end
    table.insert(chatLogState.entries, {
        player = player,
        name = player.Name,
        display = player.DisplayName,
        text = tostring(text),
        time = os.date("%H:%M:%S"),
        timestamp = os.time(),
    })
    -- Cap history at 500 to keep memory bounded
    if #chatLogState.entries > 500 then
        table.remove(chatLogState.entries, 1)
    end
end

-- Hook legacy Chatted signal for every player
local function hookPlayerChat(player)
    if chatLogState.conns[player] then return end
    chatLogState.conns[player] = player.Chatted:Connect(function(msg)
        addChatEntry(player, msg)
    end)
end

for _, p in ipairs(Players:GetPlayers()) do hookPlayerChat(p) end
Players.PlayerAdded:Connect(hookPlayerChat)
Players.PlayerRemoving:Connect(function(p)
    if chatLogState.conns[p] then
        chatLogState.conns[p]:Disconnect()
        chatLogState.conns[p] = nil
    end
end)

-- Hook TextChatService for new chat system
pcall(function()
    local TextChatService = game:GetService("TextChatService")
    TextChatService.MessageReceived:Connect(function(textChatMessage)
        local src = textChatMessage.TextSource
        if src then
            local p = Players:GetPlayerByUserId(src.UserId)
            if p then
                addChatEntry(p, textChatMessage.Text)
            end
        end
    end)
end)

local chatLogPanel = createToolPanel({
    Name = "ChatLogPanel",
    Title = "Chat Logs",
    Width = 420,
    Height = 360,
    Position = UDim2.new(0.5, -210, 0.5, -180),
})

local chatSearchInput = createTextInput(chatLogPanel.Content, UDim2.new(0, 0, 0, 4),
    "Search by player / text (e.g. @player or words)", "")
local chatScroll = create("ScrollingFrame", {
    Size = UDim2.new(1, 0, 1, -46),
    Position = UDim2.new(0, 0, 0, 42),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ScrollBarThickness = 4,
    ScrollBarImageColor3 = Theme.AccentPrimary,
    CanvasSize = UDim2.new(0, 0, 0, 0),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
    Parent = chatLogPanel.Content,
}, {
    create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 4),
    }),
})

local function refreshChatLog(query)
    for _, c in ipairs(chatScroll:GetChildren()) do
        if c:IsA("Frame") then c:Destroy() end
    end
    query = (query or ""):lower()
    local nameFilter
    if query:sub(1, 1) == "@" then
        nameFilter = query:sub(2)
        query = ""
    end
    local i = 0
    -- Newest first
    for idx = #chatLogState.entries, 1, -1 do
        local e = chatLogState.entries[idx]
        local show = true
        if nameFilter and nameFilter ~= "" then
            show = e.name:lower():find(nameFilter, 1, true) ~= nil
                or e.display:lower():find(nameFilter, 1, true) ~= nil
        elseif query ~= "" then
            show = e.text:lower():find(query, 1, true) ~= nil
                or e.name:lower():find(query, 1, true) ~= nil
                or e.display:lower():find(query, 1, true) ~= nil
        end
        if show then
            i = i + 1
            local row = create("Frame", {
                Size = UDim2.new(1, -4, 0, 36),
                BackgroundColor3 = Theme.Surface,
                BorderSizePixel = 0,
                LayoutOrder = i,
                Parent = chatScroll,
            }, {
                create("UICorner", { CornerRadius = UDim.new(0, 6) }),
            })
            create("TextLabel", {
                Size = UDim2.new(0, 60, 0, 14),
                Position = UDim2.new(0, 8, 0, 4),
                BackgroundTransparency = 1,
                Text = e.time,
                TextColor3 = Theme.TextMuted,
                TextSize = 10,
                Font = Theme.FontMono,
                TextXAlignment = Enum.TextXAlignment.Left,
                Parent = row,
            })
            create("TextLabel", {
                Size = UDim2.new(1, -80, 0, 14),
                Position = UDim2.new(0, 72, 0, 4),
                BackgroundTransparency = 1,
                Text = e.display .. "  @" .. e.name,
                TextColor3 = Theme.AccentPrimary,
                TextSize = 11,
                Font = Theme.FontBold,
                TextXAlignment = Enum.TextXAlignment.Left,
                Parent = row,
            })
            create("TextLabel", {
                Size = UDim2.new(1, -16, 0, 14),
                Position = UDim2.new(0, 8, 0, 18),
                BackgroundTransparency = 1,
                Text = e.text,
                TextColor3 = Theme.Text,
                TextSize = 12,
                Font = Theme.Font,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd,
                Parent = row,
            })
        end
    end
    if i == 0 then
        create("TextLabel", {
            Size = UDim2.new(1, -4, 0, 24),
            BackgroundTransparency = 1,
            Text = "No matching messages",
            TextColor3 = Theme.TextMuted,
            TextSize = 12,
            Font = Theme.Font,
            Parent = chatScroll,
        })
    end
end

chatSearchInput.Box:GetPropertyChangedSignal("Text"):Connect(function()
    refreshChatLog(chatSearchInput.GetText())
end)

Commands["chatlog"].Execute = function()
    refreshChatLog("")
    task.defer(function()
        if not chatLogPanel.IsOpen() then
            chatLogPanel.Show()
        end
    end)
end

-------------------------------------------------
-- ANTI-AFK
-------------------------------------------------
local antiAfkState = { enabled = false, conn = nil }

local function stopAntiAfk()
    antiAfkState.enabled = false
    setToggleState("antiafk", false)
    if antiAfkState.conn then antiAfkState.conn:Disconnect() end
    antiAfkState.conn = nil
end

local function startAntiAfk()
    antiAfkState.enabled = true
    setToggleState("antiafk", true)
    antiAfkState.conn = LocalPlayer.Idled:Connect(function()
        local VirtualUser = game:GetService("VirtualUser")
        pcall(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end)
    end)
end

Commands["antiafk"].Execute = function()
    if antiAfkState.enabled then
        stopAntiAfk()
        notify("Anti-AFK off", "info", 2)
    else
        startAntiAfk()
        notify("Anti-AFK on", "success", 2)
    end
end

-------------------------------------------------
-- PINGHOP — Server browser sorted by ping
-------------------------------------------------
Commands["pinghop"].Execute = function()
    notify("Fetching servers...", "info", 2)
    task.defer(function()
        local HttpService = game:GetService("HttpService")
        local placeId = game.PlaceId
        local cursor = ""
        local servers = {}

        -- Use executor HTTP request functions (more reliable than game:HttpGet for APIs)
        local function httpGet(url)
            local reqFn = (type(request) == "function" and request)
                or (type(http_request) == "function" and http_request)
                or (type(syn) == "table" and type(syn.request) == "function" and syn.request)
                or (type(http) == "table" and type(http.request) == "function" and http.request)
                or nil
            if reqFn then
                local resp = reqFn({ Url = url, Method = "GET" })
                if resp and resp.Body then return resp.Body end
            end
            return game:HttpGet(url)
        end

        local ok, err = pcall(function()
            for _ = 1, 5 do  -- max 5 pages
                local url = "https://games.roblox.com/v1/games/" .. placeId
                    .. "/servers/0?sortOrder=1&excludeFullGames=true&limit=25"
                if cursor ~= "" then url = url .. "&cursor=" .. cursor end
                local resp = httpGet(url)
                if not resp or resp == "" then break end
                local data = HttpService:JSONDecode(resp)
                if data and data.data then
                    for _, srv in ipairs(data.data) do
                        if srv.playing and srv.maxPlayers and srv.id and srv.ping then
                            table.insert(servers, {
                                id = srv.id,
                                playing = srv.playing,
                                maxPlayers = srv.maxPlayers,
                                ping = srv.ping or 999,
                            })
                        end
                    end
                end
                cursor = data and data.nextPageCursor or ""
                if cursor == "" or cursor == nil then break end
            end
        end)

        if not ok or #servers == 0 then
            notify("Failed to fetch servers" .. (err and (": " .. tostring(err)) or ""), "error", 3)
            return
        end

        table.sort(servers, function(a, b) return a.ping < b.ping end)

        -- Build UI panel
        local panel = createToolPanel({
            Name = "PingHopPanel",
            Title = "Server Hop (" .. #servers .. " servers)",
            Width = 340,
            Height = 380,
            Position = UDim2.new(0.5, -170, 0.5, -190),
        })

        local scroll = create("ScrollingFrame", {
            Size = UDim2.new(1, 0, 1, -4),
            Position = UDim2.new(0, 0, 0, 4),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ScrollBarThickness = 4,
            ScrollBarImageColor3 = Theme.AccentPrimary,
            CanvasSize = UDim2.new(0, 0, 0, 0),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            Parent = panel.Content,
        }, {
            create("UIListLayout", {
                SortOrder = Enum.SortOrder.LayoutOrder,
                Padding = UDim.new(0, 4),
            }),
        })

        for i, srv in ipairs(servers) do
            if i > 50 then break end
            local pingColor = srv.ping < 100 and Theme.Success
                or srv.ping < 200 and Color3.fromRGB(255, 200, 50)
                or Theme.Error
            local isCurrent = srv.id == game.JobId
            local row = create("TextButton", {
                Size = UDim2.new(1, 0, 0, 32),
                BackgroundColor3 = isCurrent and Color3.fromRGB(30, 40, 30) or Theme.Surface,
                BackgroundTransparency = 0.3,
                BorderSizePixel = 0,
                AutoButtonColor = false,
                Text = "",
                LayoutOrder = i,
                Parent = scroll,
            }, {
                create("UICorner", { CornerRadius = UDim.new(0, 6) }),
            })

            create("TextLabel", {
                Size = UDim2.new(0, 80, 1, 0),
                Position = UDim2.new(0, 8, 0, 0),
                BackgroundTransparency = 1,
                Text = srv.ping .. "ms",
                TextColor3 = pingColor,
                TextSize = 13,
                Font = Theme.FontBold,
                TextXAlignment = Enum.TextXAlignment.Left,
                Parent = row,
            })

            create("TextLabel", {
                Size = UDim2.new(0, 100, 1, 0),
                Position = UDim2.new(0, 90, 0, 0),
                BackgroundTransparency = 1,
                Text = srv.playing .. "/" .. srv.maxPlayers .. " players",
                TextColor3 = Theme.TextDim,
                TextSize = 11,
                Font = Theme.Font,
                TextXAlignment = Enum.TextXAlignment.Left,
                Parent = row,
            })

            create("TextLabel", {
                Size = UDim2.new(0, 60, 1, 0),
                Position = UDim2.new(1, -68, 0, 0),
                BackgroundTransparency = 1,
                Text = isCurrent and "CURRENT" or "JOIN",
                TextColor3 = isCurrent and Theme.TextMuted or Theme.AccentPrimary,
                TextSize = 11,
                Font = Theme.FontBold,
                TextXAlignment = Enum.TextXAlignment.Right,
                Parent = row,
            })

            if not isCurrent then
                row.MouseEnter:Connect(function()
                    tween(row, quickTween, { BackgroundTransparency = 0.1 })
                end)
                row.MouseLeave:Connect(function()
                    tween(row, quickTween, { BackgroundTransparency = 0.3 })
                end)
                row.MouseButton1Click:Connect(function()
                    notify("Joining server...", "info", 2)
                    pcall(function()
                        game:GetService("TeleportService"):TeleportToPlaceInstance(placeId, srv.id)
                    end)
                end)
            end
        end

        panel.Show()
    end)
end

-------------------------------------------------
-- ADMINCHECK — Detect high-rank group members
-------------------------------------------------
Commands["admincheck"].Execute = function()
    notify("Checking for admins...", "info", 2)
    task.defer(function()
        local HttpService = game:GetService("HttpService")
        local creatorType = game.CreatorType
        local groupId = nil

        if creatorType == Enum.CreatorType.Group then
            groupId = game.CreatorId
        else
            notify("Game is not group-owned — can't check group ranks", "info", 3)
            return
        end

        local admins = {}
        for _, player in ipairs(Players:GetPlayers()) do
            local ok, rank = pcall(function()
                return player:GetRankInGroup(groupId)
            end)
            if ok and rank and rank >= 200 then
                local okRole, role = pcall(function()
                    return player:GetRoleInGroup(groupId)
                end)
                table.insert(admins, {
                    name = player.DisplayName .. " (@" .. player.Name .. ")",
                    rank = rank,
                    role = okRole and role or ("Rank " .. rank),
                })
            end
        end

        if #admins == 0 then
            notify("No admins found in this server", "success", 3)
            return
        end

        table.sort(admins, function(a, b) return a.rank > b.rank end)

        local panel = createToolPanel({
            Name = "AdminCheckPanel",
            Title = "Admins Found (" .. #admins .. ")",
            Width = 320,
            Height = math.min(60 + #admins * 40, 340),
            Position = UDim2.new(0.5, -160, 0.5, -100),
        })

        local scroll = create("ScrollingFrame", {
            Size = UDim2.new(1, 0, 1, -4),
            Position = UDim2.new(0, 0, 0, 4),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ScrollBarThickness = 4,
            ScrollBarImageColor3 = Theme.AccentPrimary,
            CanvasSize = UDim2.new(0, 0, 0, 0),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            Parent = panel.Content,
        }, {
            create("UIListLayout", {
                SortOrder = Enum.SortOrder.LayoutOrder,
                Padding = UDim.new(0, 4),
            }),
        })

        for i, admin in ipairs(admins) do
            local row = create("Frame", {
                Size = UDim2.new(1, 0, 0, 34),
                BackgroundColor3 = Theme.Surface,
                BackgroundTransparency = 0.3,
                BorderSizePixel = 0,
                LayoutOrder = i,
                Parent = scroll,
            }, {
                create("UICorner", { CornerRadius = UDim.new(0, 6) }),
            })

            create("TextLabel", {
                Size = UDim2.new(1, -80, 1, 0),
                Position = UDim2.new(0, 8, 0, 0),
                BackgroundTransparency = 1,
                Text = admin.name,
                TextColor3 = Theme.Error,
                TextSize = 12,
                Font = Theme.FontBold,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd,
                Parent = row,
            })

            create("TextLabel", {
                Size = UDim2.new(0, 70, 1, 0),
                Position = UDim2.new(1, -78, 0, 0),
                BackgroundTransparency = 1,
                Text = admin.role,
                TextColor3 = Theme.TextMuted,
                TextSize = 10,
                Font = Theme.Font,
                TextXAlignment = Enum.TextXAlignment.Right,
                Parent = row,
            })
        end

        panel.Show()
        notify(#admins .. " admin(s) found!", "error", 3)
    end)
end

-------------------------------------------------
-- INVIS — Seat-method server-side invisibility
-- Creates a VehicleSeat, welds it to Torso, makes the character
-- sit so the server thinks we're in a seat far away. Togglable.
-------------------------------------------------
local invisSeatState = { enabled = false, seat = nil, weld = nil }

local function stopInvisSeat()
    invisSeatState.enabled = false
    setToggleState("invis", false)
    pcall(function()
        local myChar = LocalPlayer.Character
        if myChar then
            local hum = myChar:FindFirstChildOfClass("Humanoid")
            if hum then
                hum.Sit = false
                pcall(function() hum:ChangeState(Enum.HumanoidStateType.Running) end)
            end
        end
    end)
    if invisSeatState.weld and invisSeatState.weld.Parent then
        invisSeatState.weld:Destroy()
    end
    invisSeatState.weld = nil
    if invisSeatState.seat and invisSeatState.seat.Parent then
        invisSeatState.seat:Destroy()
    end
    invisSeatState.seat = nil
end

local function startInvisSeat()
    local myChar = LocalPlayer.Character
    if not myChar then
        notify("No character", "error", 2)
        return false
    end
    local hrp = myChar:FindFirstChild("HumanoidRootPart")
    local hum = myChar:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum then
        notify("Character not fully loaded", "error", 2)
        return false
    end

    stopInvisSeat()  -- clean up any previous

    -- Create a VehicleSeat AT the character's current position (not far away)
    local seat = Instance.new("VehicleSeat")
    seat.Name = "UA_InvisSeat"
    seat.CFrame = hrp.CFrame * CFrame.new(0, -0.5, 0)
    seat.Anchored = true   -- anchor first to prevent physics launch
    seat.CanCollide = false
    seat.Transparency = 1
    seat.Size = Vector3.new(0.001, 0.001, 0.001)
    seat.Parent = workspace

    -- Try to properly trigger the sit via firetouchinterest (most executors support this)
    if type(firetouchinterest) == "function" then
        pcall(function()
            firetouchinterest(hrp, seat, 0)  -- touch begin
            task.wait(0.15)
            firetouchinterest(hrp, seat, 1)  -- touch end
        end)
    else
        -- Fallback: direct sit
        hum.Sit = true
    end

    task.wait(0.2)

    -- Remove engine-created SeatWeld so the character isn't locked to the seat
    for _, child in ipairs(seat:GetChildren()) do
        if child:IsA("Weld") or child:IsA("WeldConstraint") then
            child:Destroy()
        end
    end
    for _, child in ipairs(hrp:GetChildren()) do
        if child:IsA("Weld") and child.Name == "SeatWeld" then
            child:Destroy()
        end
    end

    -- Now move seat far away — server thinks character is at the seat position
    seat.Anchored = false
    seat.CFrame = CFrame.new(0, 1e6, 0)

    invisSeatState.seat = seat
    invisSeatState.enabled = true
    setToggleState("invis", true)
    return true
end

Commands["invis"].Execute = function()
    if invisSeatState.enabled then
        stopInvisSeat()
        notify("Invisibility off", "info", 2)
    else
        if startInvisSeat() then
            notify("Invisibility on (server-side)", "success", 2)
        end
    end
end

end -- do (new toggleable commands scope)

-------------------------------------------------
-- INFINITE JUMP
-------------------------------------------------
local infJumpState = { enabled = false, connection = nil }

Commands["infjump"].Execute = function()
    if infJumpState.enabled then
        infJumpState.enabled = false
        if infJumpState.connection then
            infJumpState.connection:Disconnect()
            infJumpState.connection = nil
        end
        notify("Infinite jump disabled", "info", 2)
    else
        infJumpState.enabled = true
        infJumpState.connection = UserInputService.JumpRequest:Connect(function()
            local char = LocalPlayer.Character
            if not char then return end
            local humanoid = char:FindFirstChildOfClass("Humanoid")
            if humanoid then
                humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
            end
        end)
        notify("Infinite jump enabled", "success", 2)
    end
end

-------------------------------------------------
-- LOCAL INVISIBILITY
-------------------------------------------------
local invisState = { enabled = false, saved = {} }

Commands["invisible"].Execute = function()
    local char = LocalPlayer.Character
    if not char then error("No character") end

    if invisState.enabled then
        for part, transparency in pairs(invisState.saved) do
            if part and part.Parent then
                part.LocalTransparencyModifier = transparency
            end
        end
        invisState.saved = {}
        invisState.enabled = false
        notify("Invisibility disabled", "info", 2)
        return
    end

    invisState.saved = {}
    for _, desc in ipairs(char:GetDescendants()) do
        if desc:IsA("BasePart") or desc:IsA("Decal") then
            invisState.saved[desc] = desc.LocalTransparencyModifier
            desc.LocalTransparencyModifier = 1
        end
    end
    invisState.enabled = true
    notify("Invisibility enabled (client-side only)", "success", 2)
end

-------------------------------------------------
-- TRAIL
-------------------------------------------------
local trailState = { enabled = false, attachments = {}, trail = nil }

local function clearTrail()
    if trailState.trail and trailState.trail.Parent then
        trailState.trail:Destroy()
    end
    for _, att in ipairs(trailState.attachments) do
        if att and att.Parent then att:Destroy() end
    end
    trailState.trail = nil
    trailState.attachments = {}
end

Commands["trail"].Execute = function()
    if trailState.enabled then
        trailState.enabled = false
        clearTrail()
        notify("Trail disabled", "info", 2)
        return
    end

    local char = LocalPlayer.Character
    if not char then error("No character") end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then error("No HumanoidRootPart") end

    clearTrail()

    local att1 = Instance.new("Attachment")
    att1.Name = "UA_TrailTop"
    att1.Position = Vector3.new(0, 2, 0)
    att1.Parent = hrp

    local att2 = Instance.new("Attachment")
    att2.Name = "UA_TrailBottom"
    att2.Position = Vector3.new(0, -2, 0)
    att2.Parent = hrp

    local trail = Instance.new("Trail")
    trail.Name = "UA_Trail"
    trail.Attachment0 = att1
    trail.Attachment1 = att2
    trail.Lifetime = 0.7
    trail.MinLength = 0.05
    trail.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(99, 102, 241)),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(139, 92, 246)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(236, 72, 153)),
    })
    trail.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.2),
        NumberSequenceKeypoint.new(1, 1),
    })
    trail.LightEmission = 1
    trail.Parent = hrp

    trailState.attachments = { att1, att2 }
    trailState.trail = trail
    trailState.enabled = true
    notify("Trail enabled", "success", 2)
end

-------------------------------------------------
-- HITBOX EXPANDER
-------------------------------------------------
local hitboxState = { enabled = false, size = 10, connection = nil }

do -- hitbox scope

local function applyHitboxes(size)
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            local hrp = player.Character:FindFirstChild("HumanoidRootPart")
            if hrp then
                hrp.Size = Vector3.new(size, size, size)
                hrp.Transparency = 1
                hrp.CanCollide = false
            end
        end
    end
end

local function resetHitboxes()
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            local hrp = player.Character:FindFirstChild("HumanoidRootPart")
            if hrp then
                hrp.Size = Vector3.new(2, 2, 1)
                hrp.Transparency = 1
            end
        end
    end
end

local function startHitbox(size)
    hitboxState.size = size or hitboxState.size
    hitboxState.enabled = true
    applyHitboxes(hitboxState.size)
    hitboxState.connection = RunService.Heartbeat:Connect(function()
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and player.Character then
                local hrp = player.Character:FindFirstChild("HumanoidRootPart")
                if hrp and hrp.Size.X ~= hitboxState.size then
                    hrp.Size = Vector3.new(hitboxState.size, hitboxState.size, hitboxState.size)
                    hrp.Transparency = 1
                    hrp.CanCollide = false
                end
            end
        end
    end)
end

local function stopHitbox()
    hitboxState.enabled = false
    if hitboxState.connection then
        hitboxState.connection:Disconnect()
        hitboxState.connection = nil
    end
    resetHitboxes()
end

Commands["hitbox"].Execute = function(args)
    if hitboxState.enabled then
        if args and args[1] then
            local n = tonumber(args[1])
            if n then
                hitboxState.size = math.clamp(n, 2, 50)
                applyHitboxes(hitboxState.size)
                notify("Hitbox size set to " .. hitboxState.size, "info", 2)
                return
            end
        end
        stopHitbox()
        setToggleState("hitbox", false)
        notify("Hitbox expander disabled", "info", 2)
    else
        local size = 10
        if args and args[1] then
            local n = tonumber(args[1])
            if n then size = math.clamp(n, 2, 50) end
        end
        startHitbox(size)
        setToggleState("hitbox", true)
        notify("Hitbox expander enabled (size " .. size .. ")", "success", 2)
    end
end

end -- do (hitbox scope)

-------------------------------------------------
-- CAMLOCK (smooth camera lock onto player)
-------------------------------------------------
local camlockState = {
    enabled = false,
    target = nil,
    hotkey = Enum.KeyCode.J,
    connection = nil,
    sensitivity = 0.15,
}

local stopCamlock, startCamlock

stopCamlock = function()
    camlockState.enabled = false
    camlockState.target = nil
    if camlockState.connection then
        camlockState.connection:Disconnect()
        camlockState.connection = nil
    end
    setToggleState("camlock", false)
end

startCamlock = function(target)
    if camlockState.enabled then stopCamlock() end

    local targetChar = target.Character
    if not targetChar then
        notify("Target has no character", "error", 2)
        return false
    end

    camlockState.enabled = true
    camlockState.target = target
    setToggleState("camlock", true)

    camlockState.connection = RunService.RenderStepped:Connect(function(dt)
        if not camlockState.enabled then return end
        local cam = workspace.CurrentCamera
        if not cam then return end

        local tChar = camlockState.target and camlockState.target.Character
        if not tChar or not tChar.Parent then
            stopCamlock()
            notify("Camlock target lost", "warning", 2)
            return
        end

        local targetPart = tChar:FindFirstChild("Head") or tChar:FindFirstChild("HumanoidRootPart")
        if not targetPart then return end

        local targetPos = targetPart.Position
        local camPos = cam.CFrame.Position
        local desiredCF = CFrame.lookAt(camPos, targetPos)
        local alpha = math.clamp(camlockState.sensitivity * (dt * 60), 0.01, 1)
        cam.CFrame = cam.CFrame:Lerp(desiredCF, alpha)
    end)

    return true
end

Commands["camlock"].Execute = function(args)
    if not args or not args[1] then
        if camlockState.enabled then
            stopCamlock()
            notify("Camlock disabled", "info", 2)
            return
        end
        error("Usage: ;camlock <player|off>")
    end

    local q = args[1]:lower()
    if q == "off" or q == "stop" or q == "disable" then
        stopCamlock()
        notify("Camlock disabled", "info", 2)
        return
    end

    local targets = resolvePlayerList(args[1], { excludeSelf = true })
    if #targets == 0 then error("Player not found: " .. args[1]) end

    if startCamlock(targets[1]) then
        notify("Camlock -> " .. targets[1].DisplayName, "success", 2)
    end
end

-------------------------------------------------
-- SMOOTH FLY (inertia + momentum + camera banking)
-------------------------------------------------
local smoothFlyState = {
    enabled = false,
    speed = 80,
    hotkey = Enum.KeyCode.G,
    velocity = Vector3.zero,
    bodyPos = nil,
    bodyGyro = nil,
    connection = nil,
    savedAutoRotate = nil,
    bankAngle = 0,
}

local stopSmoothFly, startSmoothFly
local smoothFlyToggle -- forward ref for hotkey handler

do -- smoothfly scope

local ACCEL = 3.0
local DECEL = 2.5
local BANK_MAX = 18
local BANK_SPEED = 4

stopSmoothFly = function()
    smoothFlyState.enabled = false
    smoothFlyState.velocity = Vector3.zero
    smoothFlyState.bankAngle = 0
    if smoothFlyState.connection then
        smoothFlyState.connection:Disconnect()
        smoothFlyState.connection = nil
    end
    if smoothFlyState.bodyPos then
        smoothFlyState.bodyPos:Destroy()
        smoothFlyState.bodyPos = nil
    end
    if smoothFlyState.bodyGyro then
        smoothFlyState.bodyGyro:Destroy()
        smoothFlyState.bodyGyro = nil
    end
    local char = LocalPlayer.Character
    if char then
        local humanoid = char:FindFirstChildOfClass("Humanoid")
        if humanoid then
            humanoid.PlatformStand = false
            if smoothFlyState.savedAutoRotate ~= nil then
                humanoid.AutoRotate = smoothFlyState.savedAutoRotate
            end
            pcall(function() humanoid:ChangeState(Enum.HumanoidStateType.Running) end)
            pcall(function() humanoid:SetStateEnabled(Enum.HumanoidStateType.Freefall, true) end)
            pcall(function() humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true) end)
            pcall(function() humanoid:SetStateEnabled(Enum.HumanoidStateType.Running, true) end)
        end
    end
    smoothFlyState.savedAutoRotate = nil
    setToggleState("smoothfly", false)
end

startSmoothFly = function()
    if smoothFlyState.enabled then stopSmoothFly() end

    local char = LocalPlayer.Character
    if not char then notify("No character found", "error"); return false end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not hrp or not humanoid then notify("Character not fully loaded", "error"); return false end

    smoothFlyState.enabled = true
    smoothFlyState.velocity = Vector3.zero
    smoothFlyState.bankAngle = 0
    smoothFlyState.savedAutoRotate = humanoid.AutoRotate
    humanoid.AutoRotate = false
    humanoid.PlatformStand = true
    pcall(function() humanoid:ChangeState(Enum.HumanoidStateType.Physics) end)
    pcall(function() humanoid:SetStateEnabled(Enum.HumanoidStateType.Freefall, false) end)
    pcall(function() humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false) end)
    pcall(function() humanoid:SetStateEnabled(Enum.HumanoidStateType.Running, false) end)

    smoothFlyState.bodyPos = Instance.new("BodyPosition")
    smoothFlyState.bodyPos.MaxForce = Vector3.new(1e6, 1e6, 1e6)
    smoothFlyState.bodyPos.D = 500
    smoothFlyState.bodyPos.P = 7000
    smoothFlyState.bodyPos.Position = hrp.Position
    smoothFlyState.bodyPos.Parent = hrp

    smoothFlyState.bodyGyro = Instance.new("BodyGyro")
    smoothFlyState.bodyGyro.MaxTorque = Vector3.new(1e6, 1e6, 1e6)
    smoothFlyState.bodyGyro.P = 9000
    smoothFlyState.bodyGyro.D = 600
    smoothFlyState.bodyGyro.Parent = hrp

    setToggleState("smoothfly", true)

    smoothFlyState.connection = RunService.RenderStepped:Connect(function(dt)
        if not smoothFlyState.enabled or not smoothFlyState.bodyPos or not smoothFlyState.bodyGyro then return end
        local cam = workspace.CurrentCamera
        if not cam then return end

        local hrpNow = char:FindFirstChild("HumanoidRootPart")
        if not hrpNow then stopSmoothFly(); return end

        local cf = cam.CFrame
        local inputDir = Vector3.zero

        if UserInputService:IsKeyDown(Enum.KeyCode.W) then
            inputDir = inputDir + cf.LookVector
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then
            inputDir = inputDir - cf.LookVector
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then
            inputDir = inputDir - cf.RightVector
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then
            inputDir = inputDir + cf.RightVector
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
            inputDir = inputDir + Vector3.new(0, 1, 0)
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
            inputDir = inputDir - Vector3.new(0, 1, 0)
        end

        local hasInput = inputDir.Magnitude > 0.01
        if hasInput then
            inputDir = inputDir.Unit
        end

        local targetVel = hasInput and (inputDir * smoothFlyState.speed) or Vector3.zero
        local accelRate = hasInput and ACCEL or DECEL
        smoothFlyState.velocity = smoothFlyState.velocity:Lerp(targetVel, math.clamp(accelRate * dt, 0, 1))

        if smoothFlyState.velocity.Magnitude < 0.5 and not hasInput then
            smoothFlyState.velocity = Vector3.zero
        end

        smoothFlyState.bodyPos.Position = hrpNow.Position + smoothFlyState.velocity * dt

        local lateralInput = 0
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then lateralInput = lateralInput - 1 end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then lateralInput = lateralInput + 1 end

        local targetBank = lateralInput * BANK_MAX
        smoothFlyState.bankAngle = smoothFlyState.bankAngle + (targetBank - smoothFlyState.bankAngle) * math.clamp(BANK_SPEED * dt, 0, 1)

        local bankCF = cf * CFrame.Angles(0, 0, math.rad(-smoothFlyState.bankAngle))
        smoothFlyState.bodyGyro.CFrame = bankCF

        pcall(function()
            hrpNow.AssemblyLinearVelocity = Vector3.zero
            hrpNow.AssemblyAngularVelocity = Vector3.zero
        end)
    end)

    return true
end

-- SmoothFly panel
local sfPanel = createToolPanel({
    Name = "SmoothFlyPanel",
    Title = "Smooth Flight",
    Width = 260,
    Height = 260,
    Position = UDim2.new(0.5, -130, 0.5, -130),
})

smoothFlyToggle = createToggleButton(sfPanel.Content, UDim2.new(0, 0, 0, 4))
smoothFlyToggle.OnToggle(function(enabled)
    if enabled then
        if not startSmoothFly() then
            smoothFlyToggle.SetState(false)
        else
            notify("Smooth flight enabled", "success", 2)
        end
    else
        stopSmoothFly()
        notify("Smooth flight disabled", "info", 2)
    end
end)

createLabel("SPEED", sfPanel.Content, UDim2.new(0, 0, 0, 46))
local sfSpeedStepper = createStepper(sfPanel.Content, UDim2.new(0, 0, 0, 62), smoothFlyState.speed, 10, 500, 10)
sfSpeedStepper.OnChange(function(v)
    smoothFlyState.speed = v
end)

createLabel("HOTKEY", sfPanel.Content, UDim2.new(0, 0, 0, 98))
local sfHotkeyBtn = createHotkeyButton(sfPanel.Content, UDim2.new(0, 0, 0, 114), smoothFlyState.hotkey)
sfHotkeyBtn.OnChange(function(newKey)
    smoothFlyState.hotkey = newKey
    notify("Smooth flight hotkey set to " .. newKey.Name, "info", 2)
end)

createLabel("ALWAYS ACTIVE HOTKEY", sfPanel.Content, UDim2.new(0, 0, 0, 150))
do
    local t = createToggleButton(sfPanel.Content, UDim2.new(0, 0, 0, 166), hotkeyAlwaysActive["smoothfly"] or false)
    t.OnToggle(function(enabled)
        hotkeyAlwaysActive["smoothfly"] = enabled
        persistedConfig.hotkeyAlwaysActive["smoothfly"] = enabled or nil
        savePersistedConfig()
        notify("Smooth flight hotkey " .. (enabled and "always active" or "panel-only"), "info", 2)
    end)
end

create("TextLabel", {
    Size = UDim2.new(1, 0, 0, 14),
    Position = UDim2.new(0, 0, 0, 206),
    BackgroundTransparency = 1,
    Text = "Momentum flight  ·  Banking turns  ·  WASD+Space/Shift",
    TextColor3 = Theme.TextMuted,
    TextSize = 10,
    Font = Theme.Font,
    TextXAlignment = Enum.TextXAlignment.Center,
    Parent = sfPanel.Content,
})

Commands["smoothfly"].Execute = function(args)
    if args and args[1] then
        local n = tonumber(args[1])
        if n then
            smoothFlyState.speed = math.clamp(n, 10, 500)
            sfSpeedStepper.SetValue(smoothFlyState.speed)
        end
    end
    task.defer(function()
        if not sfPanel.IsOpen() then
            sfPanel.Show()
        end
    end)
end

end -- do (smoothfly scope)

-------------------------------------------------
-- BLINK / DASH (instant forward teleport + FOV effect + sound)
-------------------------------------------------
local blinkState = {
    defaultDist = 50,
    cooldown = false,
    hotkey = Enum.KeyCode.B,
}

local doBlink

do -- blink scope

doBlink = function(distance)
    if blinkState.cooldown then return end
    blinkState.cooldown = true

    local char = LocalPlayer.Character
    if not char then blinkState.cooldown = false; return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then blinkState.cooldown = false; return end

    local cam = workspace.CurrentCamera
    if not cam then blinkState.cooldown = false; return end

    local dist = distance or blinkState.defaultDist
    local lookDir = cam.CFrame.LookVector
    local startCF = hrp.CFrame
    local targetPos = startCF.Position + lookDir * dist

    -- Raycast to avoid blinking into solid geometry
    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    rayParams.FilterDescendantsInstances = { char }
    local rayResult = workspace:Raycast(startCF.Position, lookDir * dist, rayParams)
    if rayResult then
        targetPos = rayResult.Position - lookDir * 2
    end

    -- FOV zoom effect
    local savedFOV = cam.FieldOfView
    local zoomInInfo = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    local zoomOutInfo = TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

    tween(cam, zoomInInfo, { FieldOfView = savedFOV + 30 })

    -- Sound effect (whoosh)
    playSound(3398628969, 0.6)

    -- Teleport (preserve rotation)
    hrp.CFrame = CFrame.new(targetPos) * (startCF - startCF.Position)

    pcall(function()
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
    end)

    -- FOV restore
    task.delay(0.08, function()
        if cam then
            tween(cam, zoomOutInfo, { FieldOfView = savedFOV })
        end
    end)

    -- Brief cooldown
    task.delay(0.3, function()
        blinkState.cooldown = false
    end)
end

Commands["blink"].Execute = function(args)
    local dist = blinkState.defaultDist
    if args and args[1] then
        local n = tonumber(args[1])
        if n then dist = math.clamp(n, 5, 500) end
    end
    doBlink(dist)
end

end -- do (blink scope)

-------------------------------------------------
-- PLAYER LIST PANEL
-------------------------------------------------
local playerListPanel = createToolPanel({
    Name = "PlayerListPanel",
    Title = "Players",
    Width = 300,
    Height = 360,
    Position = UDim2.new(0.5, -150, 0.5, -180),
})

local playerListScroll = create("ScrollingFrame", {
    Name = "PlayerListScroll",
    Size = UDim2.new(1, 0, 1, 0),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ScrollBarThickness = 3,
    ScrollBarImageColor3 = Theme.AccentPrimary,
    ScrollBarImageTransparency = 0.5,
    CanvasSize = UDim2.new(0, 0, 0, 0),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
    Parent = playerListPanel.Content,
}, {
    create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 6),
    }),
    create("UIPadding", {
        PaddingTop = UDim.new(0, 2),
        PaddingBottom = UDim.new(0, 6),
    }),
})

local function createPlayerRow(player, index)
    local row = create("Frame", {
        Name = "Player_" .. player.Name,
        Size = UDim2.new(1, -4, 0, 54),
        BackgroundColor3 = Theme.Surface,
        BackgroundTransparency = 0.3,
        BorderSizePixel = 0,
        LayoutOrder = index,
        Parent = playerListScroll,
    }, {
        create("UICorner", { CornerRadius = UDim.new(0, 8) }),
        create("UIStroke", {
            Color = Theme.Border,
            Thickness = 1,
            Transparency = 0.6,
        }),
    })

    -- Avatar
    create("ImageLabel", {
        Size = UDim2.new(0, 40, 0, 40),
        Position = UDim2.new(0, 8, 0.5, -20),
        BackgroundColor3 = Theme.Background,
        BorderSizePixel = 0,
        Image = "rbxthumb://type=AvatarHeadShot&id=" .. player.UserId .. "&w=150&h=150",
        Parent = row,
    }, {
        create("UICorner", { CornerRadius = UDim.new(1, 0) }),
        create("UIStroke", {
            Color = Theme.AccentPrimary,
            Thickness = 1,
            Transparency = 0.4,
        }),
    })

    -- Name
    create("TextLabel", {
        Size = UDim2.new(0, 130, 0, 16),
        Position = UDim2.new(0, 56, 0, 8),
        BackgroundTransparency = 1,
        Text = player.DisplayName,
        TextColor3 = Theme.Text,
        TextSize = 13,
        Font = Theme.FontBold,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = row,
    })

    create("TextLabel", {
        Size = UDim2.new(0, 130, 0, 12),
        Position = UDim2.new(0, 56, 0, 26),
        BackgroundTransparency = 1,
        Text = "@" .. player.Name,
        TextColor3 = Theme.TextDim,
        TextSize = 10,
        Font = Theme.Font,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = row,
    })

    create("TextLabel", {
        Size = UDim2.new(0, 130, 0, 12),
        Position = UDim2.new(0, 56, 0, 38),
        BackgroundTransparency = 1,
        Text = "ID: " .. player.UserId,
        TextColor3 = Theme.TextMuted,
        TextSize = 9,
        Font = Theme.FontMono,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = row,
    })

    -- Action buttons
    local function makeAction(text, xOffset, onClick, color)
        local btn = create("TextButton", {
            Size = UDim2.new(0, 42, 0, 20),
            Position = UDim2.new(1, xOffset, 0.5, -10),
            BackgroundColor3 = color or Theme.Surface,
            BackgroundTransparency = 0.2,
            BorderSizePixel = 0,
            AutoButtonColor = false,
            Text = text,
            TextColor3 = color or Theme.TextDim,
            TextSize = 10,
            Font = Theme.FontBold,
            Parent = row,
        }, {
            create("UICorner", { CornerRadius = UDim.new(0, 4) }),
            create("UIStroke", {
                Color = color or Theme.Border,
                Thickness = 1,
                Transparency = 0.4,
            }),
        })
        btn.MouseButton1Click:Connect(function()
            playClickSound()
            local ok, err = pcall(onClick)
            if not ok then notify(tostring(err), "error", 3) end
        end)
        btn.MouseEnter:Connect(function()
            tween(btn, quickTween, { BackgroundTransparency = 0 })
        end)
        btn.MouseLeave:Connect(function()
            tween(btn, quickTween, { BackgroundTransparency = 0.2 })
        end)
        return btn
    end

    makeAction("GOTO", -140, function()
        teleportToPlayer(player)
    end, Theme.AccentPrimary)

    makeAction("FLING", -94, function()
        flingPlayer(player)
    end, Theme.Warning)

    makeAction("SPEC", -48, function()
        local cam = workspace.CurrentCamera
        if cam and player.Character then
            local hum = player.Character:FindFirstChildOfClass("Humanoid")
            if hum then
                cam.CameraSubject = hum
                spectateState.target = player
                notify("Spectating " .. player.DisplayName, "info", 2)
            end
        end
    end, Theme.AccentSecondary)
end

local function refreshPlayerList()
    for _, child in ipairs(playerListScroll:GetChildren()) do
        if child:IsA("Frame") then child:Destroy() end
    end
    local i = 0
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            i = i + 1
            createPlayerRow(player, i)
        end
    end
end

Players.PlayerAdded:Connect(function()
    if playerListPanel.IsOpen() then
        task.wait(0.5)
        refreshPlayerList()
    end
end)

Players.PlayerRemoving:Connect(function()
    if playerListPanel.IsOpen() then
        task.defer(refreshPlayerList)
    end
end)

Commands["playerlist"].Execute = function()
    refreshPlayerList()
    task.defer(function()
        if not playerListPanel.IsOpen() then
            playerListPanel.Show()
        end
    end)
end

-------------------------------------------------
-- UA USER NAMETAGS
-- Rendered as BillboardGuis parented to each target's Head with
-- AlwaysOnTop so they draw above all other BillboardGuis in the world,
-- but NOT above ScreenGuis (which is what we want - the command palette
-- should always take priority over a nametag).
-- Shown above LocalPlayer by default; best-effort cross-client detection
-- via a UA_Present attribute for other script users (attribute
-- replication is FE-dependent).
-------------------------------------------------
local nametagState = { tags = {} }

local function removeNametag(player)
    local tag = nametagState.tags[player]
    if tag and tag.Parent then tag:Destroy() end
    nametagState.tags[player] = nil
end

local function buildNametagGui()
    local holder = Instance.new("BillboardGui")
    holder.Name = "UA_Nametag"
    holder.Size = UDim2.new(0, 180, 0, 52)
    holder.StudsOffset = Vector3.new(0, 3.2, 0)
    holder.AlwaysOnTop = true
    holder.LightInfluence = 0
    holder.MaxDistance = 400

    local card = Instance.new("Frame")
    card.Name = "Card"
    card.Size = UDim2.new(1, -8, 1, -8)
    card.Position = UDim2.new(0, 4, 0, 4)
    card.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
    card.BackgroundTransparency = 0.1
    card.BorderSizePixel = 0
    card.Parent = holder

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = card

    local gradient = Instance.new("UIGradient")
    gradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(40, 30, 60)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(18, 18, 24)),
    })
    gradient.Rotation = 90
    gradient.Parent = card

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(139, 92, 246)
    stroke.Thickness = 1.5
    stroke.Transparency = 0.25
    stroke.Parent = card

    local accent = Instance.new("Frame")
    accent.Name = "Accent"
    accent.AnchorPoint = Vector2.new(0.5, 0)
    accent.Size = UDim2.new(1, -28, 0, 2)
    accent.Position = UDim2.new(0.5, 0, 0, 0)
    accent.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    accent.BorderSizePixel = 0
    accent.Parent = card
    local accentGrad = Instance.new("UIGradient")
    accentGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(99, 102, 241)),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(139, 92, 246)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(99, 102, 241)),
    })
    accentGrad.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1),
        NumberSequenceKeypoint.new(0.2, 0),
        NumberSequenceKeypoint.new(0.8, 0),
        NumberSequenceKeypoint.new(1, 1),
    })
    accentGrad.Parent = accent

    local iconFrame = Instance.new("Frame")
    iconFrame.Name = "IconFrame"
    iconFrame.Size = UDim2.new(0, 28, 0, 28)
    iconFrame.Position = UDim2.new(0, 8, 0.5, -14)
    iconFrame.BackgroundColor3 = Color3.fromRGB(99, 102, 241)
    iconFrame.BackgroundTransparency = 0.15
    iconFrame.BorderSizePixel = 0
    iconFrame.Rotation = 45
    iconFrame.Parent = card

    local iconCorner = Instance.new("UICorner")
    iconCorner.CornerRadius = UDim.new(0, 4)
    iconCorner.Parent = iconFrame

    local iconStroke = Instance.new("UIStroke")
    iconStroke.Color = Color3.fromRGB(139, 92, 246)
    iconStroke.Thickness = 1
    iconStroke.Transparency = 0.2
    iconStroke.Parent = iconFrame

    local iconInner = Instance.new("TextLabel")
    iconInner.Size = UDim2.new(1, 0, 1, 0)
    iconInner.BackgroundTransparency = 1
    iconInner.Text = "U"
    iconInner.TextColor3 = Color3.fromRGB(240, 240, 245)
    iconInner.TextSize = 14
    iconInner.Font = Enum.Font.GothamBold
    iconInner.Rotation = -45
    iconInner.Parent = iconFrame

    local topLabel = Instance.new("TextLabel")
    topLabel.Name = "TopLabel"
    topLabel.Size = UDim2.new(1, -50, 0, 14)
    topLabel.Position = UDim2.new(0, 44, 0, 4)
    topLabel.BackgroundTransparency = 1
    topLabel.Text = "UA USER"
    topLabel.TextColor3 = Color3.fromRGB(139, 92, 246)
    topLabel.TextSize = 9
    topLabel.Font = Enum.Font.GothamBold
    topLabel.TextXAlignment = Enum.TextXAlignment.Left
    topLabel.Parent = card

    local nameLabel = Instance.new("TextLabel")
    nameLabel.Name = "NameLabel"
    nameLabel.Size = UDim2.new(1, -50, 0, 18)
    nameLabel.Position = UDim2.new(0, 44, 0, 18)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Text = ""
    nameLabel.TextColor3 = Color3.fromRGB(240, 240, 245)
    nameLabel.TextSize = 14
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.TextXAlignment = Enum.TextXAlignment.Left
    nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
    nameLabel.Parent = card

    return holder, nameLabel
end

local function applyNametag(player)
    if not player.Character then return end
    local head = player.Character:FindFirstChild("Head")
    if not head then return end
    removeNametag(player)
    local gui, nameLabel = buildNametagGui()
    nameLabel.Text = player.DisplayName
    gui.Parent = head
    nametagState.tags[player] = gui
end

local function broadcastPresence()
    local char = LocalPlayer.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if hrp then
        pcall(function() hrp:SetAttribute("UA_Present", true) end)
    end
    pcall(function() LocalPlayer:SetAttribute("UA_Present", true) end)
end

local function isScriptUser(player)
    if player == LocalPlayer then return true end
    local okP, present = pcall(function() return player:GetAttribute("UA_Present") end)
    if okP and present then return true end
    local char = player.Character
    if char then
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if hrp then
            local okH, hPresent = pcall(function() return hrp:GetAttribute("UA_Present") end)
            if okH and hPresent then return true end
        end
    end
    return false
end

local function refreshNametags()
    for _, player in ipairs(Players:GetPlayers()) do
        if isScriptUser(player) then
            if not nametagState.tags[player] and player.Character then
                applyNametag(player)
            end
        else
            if nametagState.tags[player] then
                removeNametag(player)
            end
        end
    end
end

local function watchPlayer(player)
    player.CharacterAdded:Connect(function(char)
        char:WaitForChild("Head", 10)
        task.wait(0.2)
        if player == LocalPlayer then broadcastPresence() end
        if isScriptUser(player) then
            applyNametag(player)
        end
    end)
    player.AttributeChanged:Connect(function(attr)
        if attr == "UA_Present" then refreshNametags() end
    end)
    if player.Character then
        if player == LocalPlayer then broadcastPresence() end
        if isScriptUser(player) then
            applyNametag(player)
        end
    end
end

for _, p in ipairs(Players:GetPlayers()) do
    task.spawn(watchPlayer, p)
end

Players.PlayerAdded:Connect(function(p)
    watchPlayer(p)
end)

Players.PlayerRemoving:Connect(function(p)
    removeNametag(p)
end)

-- Respawn handler: clean up fly/noclip on death
LocalPlayer.CharacterAdded:Connect(function()
    if flyState.enabled then
        stopFly()
        flyToggle.SetState(false)
    end
    if noclipState.enabled then
        stopNoclip()
        noclipToggle.SetState(false)
    end
end)

-- Wire up top bar Commands button to open help panel
if topBarButtons["Commands"] then
    topBarButtons["Commands"].MouseButton1Click:Connect(function()
        playClickSound()
        openHelp()
    end)
end

-- Console/Network/Settings buttons are wired after toggleUI() is declared below

-------------------------------------------------
-- SUGGESTION ENTRY BUILDER
-------------------------------------------------
local function createLocalBadge(parent, rightOffset)
    local badge = create("Frame", {
        Name = "LocalBadge",
        Size = UDim2.new(0, 44, 0, 16),
        Position = UDim2.new(1, rightOffset or -54, 0, 6),
        BackgroundColor3 = Theme.AccentPrimary,
        BackgroundTransparency = 0.75,
        BorderSizePixel = 0,
        Parent = parent,
    }, {
        create("UICorner", { CornerRadius = UDim.new(0, 4) }),
        create("UIStroke", {
            Color = Theme.AccentPrimary,
            Thickness = 1,
            Transparency = 0.3,
        }),
        create("TextLabel", {
            Size = UDim2.new(1, 0, 1, 0),
            BackgroundTransparency = 1,
            Text = "LOCAL",
            TextColor3 = Theme.AccentPrimary,
            TextSize = 10,
            Font = Theme.FontBold,
        }),
    })
    return badge
end

local function createSuggestionEntry(cmd, index)
    local entry = create("Frame", {
        Name = "Entry_" .. cmd.Name,
        Size = UDim2.new(1, -4, 0, 44),
        BackgroundColor3 = Theme.Surface,
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        LayoutOrder = index,
    }, {
        create("UICorner", { CornerRadius = UDim.new(0, 6) }),
    })

    local cmdLabel = create("TextLabel", {
        Size = UDim2.new(0, 200, 0, 20),
        Position = UDim2.new(0, 12, 0, 6),
        BackgroundTransparency = 1,
        Text = CONFIG.Prefix .. cmd.Name,
        TextColor3 = Theme.Text,
        TextSize = 14,
        Font = Theme.FontBold,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = entry,
    })

    local descLabel = create("TextLabel", {
        Size = UDim2.new(1, -24, 0, 16),
        Position = UDim2.new(0, 12, 0, 24),
        BackgroundTransparency = 1,
        Text = cmd.Description or "No description",
        TextColor3 = Theme.TextDim,
        TextSize = 12,
        Font = Theme.Font,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = entry,
    })

    local rightEdge = -12

    -- ON badge if the command is currently toggled on
    if getToggleState and getToggleState(cmd.Name) then
        local onBadge = create("Frame", {
            Name = "OnBadge",
            Size = UDim2.new(0, 28, 0, 16),
            Position = UDim2.new(1, rightEdge - 28, 0, 6),
            BackgroundColor3 = Theme.Success,
            BackgroundTransparency = 0.75,
            BorderSizePixel = 0,
            Parent = entry,
        }, {
            create("UICorner", { CornerRadius = UDim.new(0, 4) }),
            create("UIStroke", {
                Color = Theme.Success,
                Thickness = 1,
                Transparency = 0.2,
            }),
            create("TextLabel", {
                Size = UDim2.new(1, 0, 1, 0),
                BackgroundTransparency = 1,
                Text = "ON",
                TextColor3 = Theme.Success,
                TextSize = 10,
                Font = Theme.FontBold,
            }),
        })
        -- Tint the entry background slightly to make it more obvious
        entry.BackgroundColor3 = Color3.new(
            Theme.Surface.R + 0.05,
            Theme.Surface.G + 0.08,
            Theme.Surface.B + 0.05
        )
        cmdLabel.TextColor3 = Theme.Success
        rightEdge = rightEdge - 34
    end

    if cmd.Local then
        createLocalBadge(entry, rightEdge - 44)
        rightEdge = rightEdge - 50
    end

    if cmd.Aliases and #cmd.Aliases > 0 then
        create("TextLabel", {
            Size = UDim2.new(0, 80, 0, 18),
            Position = UDim2.new(1, rightEdge - 80, 0.5, -9),
            BackgroundTransparency = 1,
            Text = table.concat(cmd.Aliases, ", "),
            TextColor3 = Theme.TextMuted,
            TextSize = 11,
            Font = Theme.FontMono,
            TextXAlignment = Enum.TextXAlignment.Right,
            Parent = entry,
        })
    end

    -- Hover effect
    entry.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement then
            tween(entry, quickTween, { BackgroundColor3 = Theme.SurfaceHover })
        end
    end)
    entry.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement then
            tween(entry, quickTween, { BackgroundColor3 = Theme.Surface })
        end
    end)

    -- Click to fill input
    entry.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            playClickSound()
            CommandInput.Text = cmd.Name .. " "
            CommandInput:CaptureFocus()
        end
    end)

    entry.Parent = ResultsFrame
    return entry
end

-------------------------------------------------
-- UI STATE MANAGEMENT
-- NOTE: isOpen, openUI, closeUI, toggleUI are forward-declared at the top
-------------------------------------------------
local expandedHeight = 380

local function clearResults()
    for _, child in ipairs(ResultsFrame:GetChildren()) do
        if child:IsA("Frame") then
            child:Destroy()
        end
    end
end

local function resolveCommandFromToken(token)
    if not token or token == "" then return nil end
    token = token:lower()
    if Commands[token] then return Commands[token] end
    for _, cmd in pairs(Commands) do
        for _, alias in ipairs(cmd.Aliases or {}) do
            if alias:lower() == token then return cmd end
        end
    end
    return nil
end

local function createPlayerPickerEntry(player, index)
    local entry = create("Frame", {
        Name = "PlayerPick_" .. player.Name,
        Size = UDim2.new(1, -4, 0, 52),
        BackgroundColor3 = Theme.Surface,
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        LayoutOrder = index,
        Parent = ResultsFrame,
    }, {
        create("UICorner", { CornerRadius = UDim.new(0, 6) }),
    })

    create("ImageLabel", {
        Size = UDim2.new(0, 40, 0, 40),
        Position = UDim2.new(0, 8, 0.5, -20),
        BackgroundColor3 = Theme.Background,
        BorderSizePixel = 0,
        Image = "rbxthumb://type=AvatarHeadShot&id=" .. player.UserId .. "&w=150&h=150",
        Parent = entry,
    }, {
        create("UICorner", { CornerRadius = UDim.new(1, 0) }),
        create("UIStroke", {
            Color = Theme.AccentPrimary,
            Thickness = 1,
            Transparency = 0.4,
        }),
    })

    create("TextLabel", {
        Size = UDim2.new(1, -64, 0, 18),
        Position = UDim2.new(0, 56, 0, 8),
        BackgroundTransparency = 1,
        Text = player.DisplayName,
        TextColor3 = Theme.Text,
        TextSize = 14,
        Font = Theme.FontBold,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = entry,
    })

    create("TextLabel", {
        Size = UDim2.new(1, -64, 0, 14),
        Position = UDim2.new(0, 56, 0, 26),
        BackgroundTransparency = 1,
        Text = "@" .. player.Name .. "  ·  ID " .. player.UserId,
        TextColor3 = Theme.TextDim,
        TextSize = 11,
        Font = Theme.FontMono,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = entry,
    })

    entry.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement then
            tween(entry, quickTween, { BackgroundColor3 = Theme.SurfaceHover })
        end
    end)
    entry.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement then
            tween(entry, quickTween, { BackgroundColor3 = Theme.Surface })
        end
    end)
    entry.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            playClickSound()
            -- Complete the command with the selected player's name
            local cmdText = CommandInput.Text
            -- Parse the current command and replace the player arg
            if cmdText:sub(1, #CONFIG.Prefix) == CONFIG.Prefix then
                cmdText = cmdText:sub(#CONFIG.Prefix + 1)
            end
            local parts = {}
            for part in cmdText:gmatch("%S+") do table.insert(parts, part) end
            if #parts >= 1 then
                CommandInput.Text = parts[1] .. " " .. player.Name
                CommandInput.CursorPosition = #CommandInput.Text + 1
            end
        end
    end)
end

-- Refresh all toggle states from their underlying state variables.
-- Called before populating the command palette so ON badges are accurate.
local function refreshToggleStates()
    local function safe(name, value)
        if value then
            toggleStates[name] = true
        else
            toggleStates[name] = nil
        end
    end
    -- Main-scope state tables (all declared as locals in this file)
    if flyState then safe("fly", flyState.enabled) end
    if noclipState then safe("noclip", noclipState.enabled) end
    if espState then safe("esp", espState.enabled) end
    if antiFlingState then safe("antifling", antiFlingState.enabled) end
    if infJumpState then safe("infjump", infJumpState.enabled) end
    if godState then safe("god", godState.enabled) end
    if invisState then safe("invisible", invisState.enabled) end
    if trailState then safe("trail", trailState.enabled) end
    if freecamState then safe("freecam", freecamState.enabled) end
    if clickFlingState then safe("clickfling", clickFlingState.enabled) end
    safe("silent", targetingState and targetingState.silent)
    safe("resolver", targetingState and targetingState.velocityResolver)
    if hitboxState then safe("hitbox", hitboxState.enabled) end
    if camlockState then safe("camlock", camlockState.enabled) end
    if smoothFlyState then safe("smoothfly", smoothFlyState.enabled) end
    -- Note: clicktp/fullbright/remotespy/antiafk set their own via setToggleState
end

local function populateSuggestions(query)
    clearResults()
    refreshToggleStates()

    -- Detect player-arg mode: if the query contains a space and the first token
    -- resolves to a command that has PlayerArg set, show a player picker.
    local trimmed = query
    local spaceIdx = trimmed:find(" ")
    if spaceIdx then
        local firstToken = trimmed:sub(1, spaceIdx - 1)
        local rest = trimmed:sub(spaceIdx + 1)
        local cmd = resolveCommandFromToken(firstToken)
        if cmd and cmd.PlayerArg then
            local filter = rest:lower()
            local players = {}
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= LocalPlayer then
                    if filter == ""
                        or p.Name:lower():find(filter, 1, true)
                        or p.DisplayName:lower():find(filter, 1, true) then
                        table.insert(players, p)
                    end
                end
            end
            table.sort(players, function(a, b) return a.DisplayName:lower() < b.DisplayName:lower() end)

            if #players == 0 then
                create("Frame", {
                    Name = "EmptyPlayers",
                    Size = UDim2.new(1, -4, 0, 60),
                    BackgroundTransparency = 1,
                    Parent = ResultsFrame,
                }, {
                    create("TextLabel", {
                        Size = UDim2.new(1, 0, 1, 0),
                        BackgroundTransparency = 1,
                        Text = filter == "" and "No other players in server" or 'No players matching "' .. filter .. '"',
                        TextColor3 = Theme.TextMuted,
                        TextSize = 13,
                        Font = Theme.Font,
                    }),
                })
            else
                for i, p in ipairs(players) do
                    createPlayerPickerEntry(p, i)
                end
            end
            CommandCount.Text = #players .. " player" .. (#players ~= 1 and "s" or "")
            return
        end
    end

    local matches = getMatchingCommands(query)

    if #matches == 0 then
        -- "No commands found" message
        create("Frame", {
            Name = "EmptyState",
            Size = UDim2.new(1, -4, 0, 80),
            BackgroundTransparency = 1,
            Parent = ResultsFrame,
        }, {
            create("TextLabel", {
                Size = UDim2.new(1, 0, 1, 0),
                BackgroundTransparency = 1,
                Text = query == "" and "No commands registered yet" or 'No commands matching "' .. query .. '"',
                TextColor3 = Theme.TextMuted,
                TextSize = 14,
                Font = Theme.Font,
                Parent = ResultsFrame,
            }),
        })
    else
        for i, cmd in ipairs(matches) do
            createSuggestionEntry(cmd, i)
        end
    end

    CommandCount.Text = #matches .. " command" .. (#matches ~= 1 and "s" or "")
end

openUI = function()
    if isOpen then return end
    isOpen = true

    Backdrop.Visible = true
    Backdrop.BackgroundTransparency = 1 -- stay fully transparent, only for click capture
    MainFrame.Visible = true
    MainFrame.Size = UDim2.new(0, 520, 0, 0)
    MainFrame.BackgroundTransparency = 1

    -- Populate initial suggestions
    CommandInput.Text = ""
    populateSuggestions("")

    -- Animate open (no dim, the palette is a floating overlay)
    tween(MainFrame, smoothIn, { Size = UDim2.new(0, 520, 0, expandedHeight), BackgroundTransparency = 0 })

    -- Focus input after animation starts
    task.delay(0.1, function()
        CommandInput:CaptureFocus()
    end)
end

closeUI = function()
    if not isOpen then return end
    isOpen = false

    local t = tween(MainFrame, smoothOut, { Size = UDim2.new(0, 520, 0, 0), BackgroundTransparency = 1 })
    CommandInput:ReleaseFocus()

    t.Completed:Wait()
    Backdrop.Visible = false
    MainFrame.Visible = false
    clearResults()
end

toggleUI = function()
    if isOpen then
        closeUI()
    else
        openUI()
    end
end

-- Wire up remaining top bar buttons now that toggleUI() is defined
if topBarButtons["Console"] then
    topBarButtons["Console"].MouseButton1Click:Connect(function()
        playClickSound()
        toggleUI()
    end)
end

if topBarButtons["Network"] then
    topBarButtons["Network"].MouseButton1Click:Connect(function()
        playClickSound()
        notify("Network panel coming soon", "info", 3)
    end)
end

if topBarButtons["Settings"] then
    topBarButtons["Settings"].MouseButton1Click:Connect(function()
        playClickSound()
        if settingsPanel.IsOpen() then
            settingsPanel.Hide()
        else
            settingsPanel.Show()
        end
    end)
end

-------------------------------------------------
-- INPUT HANDLING
-------------------------------------------------
-- Keyboard toggle (;)
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end

    if input.KeyCode == CONFIG.ToggleKey then
        -- Small delay to prevent the ; character from appearing in the textbox
        task.defer(function()
            toggleUI()
        end)
    end
end)

-- ESC to close
UserInputService.InputBegan:Connect(function(input, _)
    if input.KeyCode == Enum.KeyCode.Escape then
        if helpOpen then
            closeHelp()
        elseif isOpen then
            closeUI()
        end
    end
end)

-- Hotkeys: only fire if always-active is on, the panel is open, or the feature is
-- currently enabled (so you can always turn off something that's running).
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
    -- Extra guard: ignore hotkeys if any TextBox has focus (some executors
    -- don't set gameProcessed for CoreGui TextBoxes)
    if UserInputService:GetFocusedTextBox() then return end

    if input.KeyCode == flyState.hotkey then
        if not (hotkeyAlwaysActive["fly"] or flyPanel.IsOpen() or flyState.enabled) then return end
        if flyState.enabled then
            stopFly()
            flyToggle.SetState(false)
            notify("Flight disabled", "info", 2)
        else
            if startFly() then
                flyToggle.SetState(true)
                notify("Flight enabled", "success", 2)
            end
        end
    elseif input.KeyCode == noclipState.hotkey then
        if not (hotkeyAlwaysActive["noclip"] or noclipPanel.IsOpen() or noclipState.enabled) then return end
        if noclipState.enabled then
            stopNoclip()
            noclipToggle.SetState(false)
            notify("Noclip disabled", "info", 2)
        else
            startNoclip()
            noclipToggle.SetState(true)
            notify("Noclip enabled", "success", 2)
        end
    elseif input.KeyCode == clickFlingState.bind then
        if not (hotkeyAlwaysActive["clickfling"] or clickFlingPanel.IsOpen() or clickFlingState.enabled) then return end
        if clickFlingState.enabled then
            stopClickFling()
            clickFlingToggle.SetState(false)
            notify("Click-fling disabled", "info", 2)
        else
            startClickFling()
            clickFlingToggle.SetState(true)
        end
    elseif input.KeyCode == clickFlingState.triggerBind then
        if not (hotkeyAlwaysActive["clickfling"] or clickFlingPanel.IsOpen() or clickFlingState.enabled) then return end
        if not clickFlingState.enabled then return end
        if flingInProgress then return end
        local target = (targetingState.silent and camlockState.enabled and camlockState.target) or getClosestPlayerToMouse()
        if not target then
            notify("No player near cursor to fling", "warning", 2)
            return
        end
        task.spawn(function()
            local ok, err = pcall(flingPlayer, target, clickFlingState.mode)
            if not ok then
                notify("Click-fling failed: " .. tostring(err), "error", 2)
            end
        end)
    elseif input.KeyCode == camlockState.hotkey then
        if not (hotkeyAlwaysActive["camlock"] or camlockState.enabled) then return end
        if camlockState.enabled then
            stopCamlock()
            notify("Camlock disabled", "info", 2)
        else
            -- Lock onto nearest player
            local myChar = LocalPlayer.Character
            local myHrp = myChar and myChar:FindFirstChild("HumanoidRootPart")
            if myHrp then
                local best, bestDist = nil, math.huge
                for _, p in ipairs(Players:GetPlayers()) do
                    if p ~= LocalPlayer and p.Character then
                        local thrp = p.Character:FindFirstChild("HumanoidRootPart")
                        if thrp then
                            local d = (thrp.Position - myHrp.Position).Magnitude
                            if d < bestDist then best, bestDist = p, d end
                        end
                    end
                end
                if best then
                    if startCamlock(best) then
                        notify("Camlock -> " .. best.DisplayName, "success", 2)
                    end
                else
                    notify("No players to lock onto", "warning", 2)
                end
            end
        end
    elseif input.KeyCode == smoothFlyState.hotkey then
        if not (hotkeyAlwaysActive["smoothfly"] or sfPanel.IsOpen() or smoothFlyState.enabled) then return end
        if smoothFlyState.enabled then
            stopSmoothFly()
            smoothFlyToggle.SetState(false)
            notify("Smooth flight disabled", "info", 2)
        else
            if startSmoothFly() then
                smoothFlyToggle.SetState(true)
                notify("Smooth flight enabled", "success", 2)
            end
        end
    elseif input.KeyCode == blinkState.hotkey then
        if not hotkeyAlwaysActive["blink"] then return end
        doBlink(blinkState.defaultDist)
    end
end)

-- Click outside the palette (on backdrop) to close it.
-- Safety check: only close if click is actually outside the MainFrame bounds.
Backdrop.InputBegan:Connect(function(input)
    if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
    if not isOpen then return end

    local mousePos = input.Position
    local framePos = MainFrame.AbsolutePosition
    local frameSize = MainFrame.AbsoluteSize
    local insideX = mousePos.X >= framePos.X and mousePos.X <= framePos.X + frameSize.X
    local insideY = mousePos.Y >= framePos.Y and mousePos.Y <= framePos.Y + frameSize.Y

    if not (insideX and insideY) then
        closeUI()
    end
end)

-- Live search / filtering
CommandInput:GetPropertyChangedSignal("Text"):Connect(function()
    local text = CommandInput.Text
    -- Strip leading prefix if user typed it
    if text:sub(1, #CONFIG.Prefix) == CONFIG.Prefix then
        text = text:sub(#CONFIG.Prefix + 1)
    end
    populateSuggestions(text)
end)

-- Execute on enter
CommandInput.FocusLost:Connect(function(enterPressed)
    if not enterPressed then return end

    local text = CommandInput.Text
    if text == "" then return end

    -- Strip prefix if present
    if text:sub(1, #CONFIG.Prefix) == CONFIG.Prefix then
        text = text:sub(#CONFIG.Prefix + 1)
    end

    playClickSound()
    local success, msg = executeCommand(text)
    if success then
        notify(msg, "success")
    else
        notify(msg, "error")
    end

    CommandInput.Text = ""
    populateSuggestions("")
end)

-------------------------------------------------
-- CHAT HOOK (intercept ; prefix in chat)
-------------------------------------------------
local function hookChat()
    -- Wait for the chat system to load
    local chatBar = nil

    -- Try to find the default chat bar
    local function findChatBar()
        local playerGui = LocalPlayer:WaitForChild("PlayerGui", 5)
        if not playerGui then return nil end

        -- Default Roblox chat
        local chat = playerGui:FindFirstChild("Chat")
        if chat then
            local frame = chat:FindFirstChild("Frame")
            if frame then
                local chatBarFrame = frame:FindFirstChild("ChatBarParentFrame")
                    or frame:FindFirstChild("ChatBar")
                if chatBarFrame then
                    for _, desc in ipairs(chatBarFrame:GetDescendants()) do
                        if desc:IsA("TextBox") then
                            return desc
                        end
                    end
                end
            end
        end
        return nil
    end

    task.spawn(function()
        -- Retry a few times since chat may load late
        for attempt = 1, 10 do
            chatBar = findChatBar()
            if chatBar then break end
            task.wait(1)
        end

        if not chatBar then return end

        chatBar.FocusLost:Connect(function(enterPressed)
            if not enterPressed then return end

            local text = chatBar.Text
            if text:sub(1, #CONFIG.Prefix) == CONFIG.Prefix then
                local cmdText = text:sub(#CONFIG.Prefix + 1)
                if cmdText ~= "" then
                    -- Clear the chat bar so message doesn't send
                    chatBar.Text = ""

                    local success, msg = executeCommand(cmdText)
                    if success then
                        notify(msg, "success")
                    else
                        notify(msg, "error")
                    end
                end
            end
        end)

        -- Live suggestion overlay when typing ; in chat
        chatBar:GetPropertyChangedSignal("Text"):Connect(function()
            local text = chatBar.Text
            if text:sub(1, #CONFIG.Prefix) == CONFIG.Prefix then
                local query = text:sub(#CONFIG.Prefix + 1)
                if not isOpen then
                    openUI()
                end
                CommandInput.Text = query
                populateSuggestions(query)
            end
        end)
    end)
end

hookChat()

-------------------------------------------------
-- TEXT CHAT SERVICE HOOK (new chat system)
-------------------------------------------------
local function hookTextChatService()
    local success, TextChatService = pcall(function()
        return game:GetService("TextChatService")
    end)
    if not success or not TextChatService then return end

    local function onSendingMessage(msg)
        if msg and msg.Text and msg.Text:sub(1, #CONFIG.Prefix) == CONFIG.Prefix then
            local cmdText = msg.Text:sub(#CONFIG.Prefix + 1)
            if cmdText ~= "" then
                local ok, result = executeCommand(cmdText)
                if ok then
                    notify(result, "success")
                else
                    notify(result, "error")
                end
            end
        end
    end

    -- Hook into TextChatService SendAsync
    pcall(function()
        local channel = TextChatService:WaitForChild("TextChannels", 5)
        if channel then
            local rbxGeneral = channel:FindFirstChild("RBXGeneral")
            if rbxGeneral then
                rbxGeneral.ShouldDeliverCallback = function(msg)
                    if msg.Text:sub(1, #CONFIG.Prefix) == CONFIG.Prefix then
                        onSendingMessage(msg)
                        return false -- don't send to chat
                    end
                    return true
                end
            end
        end
    end)
end

hookTextChatService()

-------------------------------------------------
-- DRAGGABLE UI (unified system)
-------------------------------------------------
makeDraggable(HeaderFrame, MainFrame)

UserInputService.InputChanged:Connect(function(input)
    if activeDrag and input.UserInputType == Enum.UserInputType.MouseMovement then
        local delta = input.Position - activeDrag.startMouse
        local startPos = activeDrag.startPos
        activeDrag.target.Position = UDim2.new(
            startPos.X.Scale, startPos.X.Offset + delta.X,
            startPos.Y.Scale, startPos.Y.Offset + delta.Y
        )
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        if activeDrag and activeDrag.target == TopBar then
            local pos = TopBar.Position
            persistedConfig.topBarPos = {
                xScale = pos.X.Scale, xOffset = pos.X.Offset,
                yScale = pos.Y.Scale, yOffset = pos.Y.Offset,
            }
            savePersistedConfig()
        end
        activeDrag = nil
    end
end)

-------------------------------------------------
-- INITIALIZATION
-------------------------------------------------
-- Hide the whole main ScreenGui until auth completes so the top bar / palette never
-- flash for a frame while the welcome-back or login UI is preparing.
ScreenGui.Enabled = false
Backdrop.Visible = false

-------------------------------------------------
-- LOGIN SCREEN
-- Gates the script behind username/password against the Discord key-auth API
-- (register + redeem key in Discord, then sign in here). Persists username +
-- key for faster "welcome back" via /auth/script-login-key.
-- Wrapped in IIFE: main script chunk hits Luau's ~200 local limit; `do` blocks
-- don't create a new function, so login locals still counted on main chunk.
-------------------------------------------------
local startLoginFlow = (function()

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
local DISCORD_INVITE = (getgenv and type(getgenv().UA_DiscordInvite) == "string" and getgenv().UA_DiscordInvite)
    or ""

local function clearSavedLogin()
    persistedConfig.loginUser = nil
    persistedConfig.loginKey = nil
    persistedConfig.accountTier = nil
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

local function scriptAuthLogin(username, password)
    local data, err = postJson(AUTH_API_BASE .. "/auth/script-login", {
        username = username,
        password = password,
    })
    if not data then
        return false, err or "Auth failed"
    end
    if data.ok ~= true then
        return false, tostring(data.error or "Auth rejected")
    end
    return true, data
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
        local opened = false
        pcall(function()
            local gs = game:GetService("GuiService")
            if gs.OpenBrowserWindow then
                gs:OpenBrowserWindow(DISCORD_INVITE)
                opened = true
            end
        end)
        if not opened and type(setclipboard) == "function" then
            setclipboard(DISCORD_INVITE)
            L.errLabel.Text = "Discord invite copied to clipboard"
        elseif not opened then
            L.errLabel.Text = DISCORD_INVITE
        else
            L.errLabel.Text = "Opening Discord…"
        end
    else
        L.errLabel.Text = "Set getgenv().UA_DiscordInvite = \"https://discord.gg/...\" before running"
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
            pcall(function() if ScreenGui and ScreenGui.Parent then ScreenGui:Destroy() end end)
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

local function loginRunAuthRequest(L, onSuccess, user, pass)
    local okAuth, authResult = scriptAuthLogin(user, pass)
    if not okAuth then
        L.submitted = false
        clearSavedLogin()
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
    if persistedConfig.loginKey == "" then
        clearSavedLogin()
        L.submitted = false
        L.submitBtn.Text = "LOGIN"
        L.userBox.TextEditable = true
        L.passBox.TextEditable = true
        L.errLabel.TextColor3 = Theme.Error
        L.errLabel.Text = "No affiliated active key found"
        return
    end
    savePersistedConfig()
    local submitStroke = L.submitBtn:FindFirstChildOfClass("UIStroke")
    if submitStroke then
        tween(submitStroke, quickTween, { Color = Theme.Success })
    end
    task.delay(1.0, function()
        fadeOutLoginCard(L, onSuccess, user)
    end)
end

local function loginAttemptAuth(L, onSuccess)
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
    TopBar.Visible = false
    MainFrame.Visible = false
    Backdrop.Visible = false
    local L = { passRealText = "", submitted = false }
    loginBuildBackdropAndCard(L)
    loginBuildUserPassFields(L)
    loginInstallPasswordMask(L)
    loginBuildErrAndSubmit(L)
    loginBuildDiscordUnloadFooter(L)
    loginWireEvents(L, onSuccess)
end

local function revealMainUI(username)
    -- Determine display name: prefer saved nickname > login username > fallback
    local displayName = (persistedConfig.nickname and persistedConfig.nickname ~= "")
        and persistedConfig.nickname
        or (username or LocalPlayer.DisplayName)

    if AccountTypeLabel then
        AccountTypeLabel.Text = tierToDisplayLabel(persistedConfig.accountTier)
    end

    ScreenGui.Enabled = true

    -- Slide the top bar down from above the screen
    -- (AvatarContainer is a child of TopBar, so it follows automatically)
    TopBar.Visible = true
    local targetPos = _defaultTopBarPos
    TopBar.Position = UDim2.new(targetPos.X.Scale, targetPos.X.Offset, 0, -50)

    -- Save original transparencies so we restore to correct values (not all 0)
    local savedProps = {}
    TopBar.BackgroundTransparency = 1
    for _, d in ipairs(TopBar:GetDescendants()) do
        if d:IsA("TextLabel") or d:IsA("TextButton") then
            savedProps[d] = { TextTransparency = d.TextTransparency, BackgroundTransparency = d.BackgroundTransparency }
            d.TextTransparency = 1
        elseif d:IsA("UIStroke") then
            savedProps[d] = { Transparency = d.Transparency }
            d.Transparency = 1
        elseif d:IsA("ImageLabel") then
            savedProps[d] = { ImageTransparency = d.ImageTransparency }
            d.ImageTransparency = 1
        elseif d:IsA("Frame") and d ~= TopBar then
            savedProps[d] = { BackgroundTransparency = d.BackgroundTransparency }
            d.BackgroundTransparency = 1
        end
    end

    -- Animate down to target position
    local slideInfo = TweenInfo.new(0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
    tween(TopBar, slideInfo, {
        Position = targetPos,
        BackgroundTransparency = 0.1,
    })
    -- Fade in children with slight delay, restoring original values
    task.delay(0.15, function()
        local tweenIn = TweenInfo.new(0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
        for d, props in pairs(savedProps) do
            pcall(function() tween(d, tweenIn, props) end)
        end
    end)

    task.delay(0.4, function()
        notify("Welcome, " .. displayName .. "!", "success", 3)
        task.delay(0.3, function()
            notify("Press " .. CONFIG.Prefix .. " to open command palette", "info", 5)
        end)
    end)
end

-- "Welcome back" — Instance.new only (same register-limit issue as login UI).
local function showWelcomeBack(savedUser, onDone)
    TopBar.Visible = false
    MainFrame.Visible = false
    Backdrop.Visible = false

    local disp = (persistedConfig.nickname and persistedConfig.nickname ~= "") and persistedConfig.nickname or savedUser
    local avUrl = "https://www.roblox.com/headshot-thumbnail/image?userId="
        .. LocalPlayer.UserId .. "&width=150&height=150&format=png"

    local wbGui = Instance.new("ScreenGui")
    wbGui.Name = "UniversalAdmin_WelcomeBack"
    wbGui.ResetOnSpawn = false
    wbGui.IgnoreGuiInset = true
    wbGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    wbGui.DisplayOrder = 2000000000
    wbGui.Parent = CoreGui

    local card = Instance.new("Frame")
    card.Name = "WelcomeCard"
    card.AnchorPoint = Vector2.new(0.5, 0.5)
    card.Position = UDim2.new(0.5, 0, 0.5, 0)
    card.Size = UDim2.new(0, 0, 0, 0)
    card.BackgroundColor3 = Color3.fromRGB(16, 16, 22)
    card.BorderSizePixel = 0
    card.Parent = wbGui
    local wcc = Instance.new("UICorner")
    wcc.CornerRadius = UDim.new(0, 14)
    wcc.Parent = card
    local wcs = Instance.new("UIStroke")
    wcs.Color = Theme.AccentPrimary
    wcs.Thickness = 1.5
    wcs.Transparency = 0.3
    wcs.Parent = card

    local ab = Instance.new("Frame")
    ab.AnchorPoint = Vector2.new(0.5, 0)
    ab.Size = UDim2.new(1, -40, 0, 2)
    ab.Position = UDim2.new(0.5, 0, 0, 0)
    ab.BorderSizePixel = 0
    ab.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    ab.Parent = card
    local abg = Instance.new("UIGradient")
    abg.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Theme.AccentPrimary),
        ColorSequenceKeypoint.new(0.5, Theme.AccentSecondary),
        ColorSequenceKeypoint.new(1, Theme.AccentPrimary),
    })
    abg.Parent = ab

    local av = Instance.new("ImageLabel")
    av.AnchorPoint = Vector2.new(0.5, 0)
    av.Position = UDim2.new(0.5, 0, 0, 18)
    av.Size = UDim2.new(0, 48, 0, 48)
    av.BackgroundColor3 = Theme.Surface
    av.BorderSizePixel = 0
    av.Image = avUrl
    av.Parent = card
    local avc = Instance.new("UICorner")
    avc.CornerRadius = UDim.new(1, 0)
    avc.Parent = av
    local avs = Instance.new("UIStroke")
    avs.Color = Theme.AccentPrimary
    avs.Thickness = 2
    avs.Transparency = 0.3
    avs.Parent = av

    local tl1 = Instance.new("TextLabel")
    tl1.AnchorPoint = Vector2.new(0.5, 0)
    tl1.Position = UDim2.new(0.5, 0, 0, 76)
    tl1.Size = UDim2.new(1, -40, 0, 24)
    tl1.BackgroundTransparency = 1
    tl1.Text = "Welcome back, " .. disp .. "!"
    tl1.TextColor3 = Theme.Text
    tl1.TextSize = 18
    tl1.Font = Theme.FontBold
    tl1.Parent = card

    local tl2 = Instance.new("TextLabel")
    tl2.AnchorPoint = Vector2.new(0.5, 0)
    tl2.Position = UDim2.new(0.5, 0, 0, 104)
    tl2.Size = UDim2.new(1, -40, 0, 12)
    tl2.BackgroundTransparency = 1
    tl2.Text = "UNIVERSAL ADMIN"
    tl2.TextColor3 = Theme.TextMuted
    tl2.TextSize = 10
    tl2.Font = Theme.FontBold
    tl2.Parent = card

    local wbt = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
    tween(card, wbt, { Size = UDim2.new(0, 300, 0, 140) })

    dismissWelcomeBackAfterDelay(wbGui, card, onDone, savedUser)
end

-- Decide: show full login or "welcome back" depending on saved state.
    return function()
        if persistedConfig.loginUser and persistedConfig.loginKey
            and type(persistedConfig.loginUser) == "string" and #persistedConfig.loginUser > 0
            and type(persistedConfig.loginKey) == "string" and #persistedConfig.loginKey > 0 then
            local okSaved = false
            pcall(function()
                local data, err = postJson(AUTH_API_BASE .. "/auth/script-login-key", {
                    username = persistedConfig.loginUser,
                    key = persistedConfig.loginKey,
                })
                if data and data.ok == true and data.tier then
                    persistedConfig.accountTier = data.tier
                    savePersistedConfig()
                end
                okSaved = data and data.ok == true and not err
            end)
            if okSaved then
                showWelcomeBack(persistedConfig.loginUser, revealMainUI)
            else
                clearSavedLogin()
                showLoginScreen(revealMainUI)
            end
        else
            showLoginScreen(revealMainUI)
        end
    end
end)()

startLoginFlow();

-- IIFE: main chunk is at Luau's ~200 local limit; `do` does not get a fresh register pool.
(function()
    local totalCommands = 0
    for _ in pairs(Commands) do totalCommands = totalCommands + 1 end
    StatusText.Text = "UniversalAdmin  |  " .. totalCommands .. " commands loaded"
end)()

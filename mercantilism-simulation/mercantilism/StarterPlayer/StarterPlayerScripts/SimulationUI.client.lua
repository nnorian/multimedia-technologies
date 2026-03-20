-- SimulationUI.client.lua (v4 — resource economy, relationship display)
-- LocalScript: creates and manages the simulation HUD
-- Place in StarterPlayer/StarterPlayerScripts

local Players      = game:GetService("Players")
local RS           = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(RS:WaitForChild("GameConfig"))

-- Wait for SimEvents folder
local simEvents       = RS:WaitForChild("SimEvents", 30)
local wealthUpdated   = simEvents and simEvents:WaitForChild("WealthUpdated", 30)
local tickLogEvent    = simEvents and simEvents:WaitForChild("TickLog", 30)
local simEndedEvent   = simEvents and simEvents:WaitForChild("SimulationEnded", 30)
local comparisonEvent = simEvents and simEvents:WaitForChild("ComparisonReady", 30)
local dataExportEvent = simEvents and simEvents:WaitForChild("DataExport", 30)

local localPlayer = Players.LocalPlayer
local playerGui   = localPlayer:WaitForChild("PlayerGui")

-- ─── Color Utilities ──────────────────────────────────────────────────────────

local COLORS = {
    DARK_BG     = Color3.fromRGB(20, 20, 30),
    DARK_PANEL  = Color3.fromRGB(15, 15, 25),
    GOLD        = Color3.fromRGB(255, 215, 0),
    WHITE       = Color3.fromRGB(255, 255, 255),
    GREEN       = Color3.fromRGB(80, 220, 80),
    RED         = Color3.fromRGB(220, 80, 80),
    ORANGE      = Color3.fromRGB(255, 140, 0),
    LIGHT_GRAY  = Color3.fromRGB(180, 180, 180),
    HEADER_BG   = Color3.fromRGB(10, 10, 20),
    CYAN        = Color3.fromRGB(80, 180, 255),
}

-- ─── Number Formatting ────────────────────────────────────────────────────────

local function formatGold(n)
    n = math.floor(n or 0)
    local s = tostring(math.abs(n))
    local result = ""
    local len = #s
    for i = 1, len do
        if i > 1 and (len - i + 1) % 3 == 0 then
            result = result .. ","
        end
        result = result .. s:sub(i, i)
    end
    if n < 0 then result = "-" .. result end
    return result .. "g"
end

local function signedStr(n)
    n = math.floor(n or 0)
    if n >= 0 then
        return "+" .. tostring(n)
    else
        return tostring(n)
    end
end

-- ─── ScreenGui Setup ──────────────────────────────────────────────────────────

local screenGui = Instance.new("ScreenGui")
screenGui.Name         = "MercantilismUI"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent       = playerGui

-- ─── Helpers ────────────────────────────────────────────────────────────────

local function makeFrame(props)
    local f = Instance.new("Frame")
    f.Name                  = props.Name or "Frame"
    f.Size                  = props.Size or UDim2.new(1, 0, 1, 0)
    f.Position              = props.Position or UDim2.new(0, 0, 0, 0)
    f.BackgroundColor3      = props.BackgroundColor3 or COLORS.DARK_BG
    f.BackgroundTransparency = props.BackgroundTransparency or 0
    f.BorderSizePixel       = 0
    f.Parent                = props.Parent or screenGui
    if props.ZIndex then f.ZIndex = props.ZIndex end
    return f
end

local function makeLabel(props)
    local l = Instance.new("TextLabel")
    l.Name                  = props.Name or "Label"
    l.Size                  = props.Size or UDim2.new(1, 0, 1, 0)
    l.Position              = props.Position or UDim2.new(0, 0, 0, 0)
    l.BackgroundTransparency = 1
    l.Text                  = props.Text or ""
    l.TextColor3            = props.TextColor3 or COLORS.WHITE
    l.Font                  = props.Font or Enum.Font.Gotham
    l.TextSize              = props.TextSize or 14
    l.TextXAlignment        = props.TextXAlignment or Enum.TextXAlignment.Center
    l.TextYAlignment        = props.TextYAlignment or Enum.TextYAlignment.Center
    l.TextScaled            = props.TextScaled or false
    l.Parent                = props.Parent or screenGui
    if props.ZIndex then l.ZIndex = props.ZIndex end
    return l
end

local function addCorner(parent, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius or 4)
    c.Parent = parent
end

-- ─── Notifications ────────────────────────────────────────────────────────────

local notifQueue   = {}
local notifBusy    = false
local NOTIF_HOLD   = 2.0

local function processNotifQueue()
    if notifBusy or #notifQueue == 0 then return end
    notifBusy = true

    local entry = table.remove(notifQueue, 1)
    local text, color = entry[1], entry[2]

    local notifFrame = makeFrame({
        Name                   = "EventNotif",
        Size                   = UDim2.new(0, 340, 0, 28),
        Position               = UDim2.new(0.5, -170, 0, 6),
        BackgroundColor3       = Color3.fromRGB(8, 8, 18),
        BackgroundTransparency = 1,
        Parent                 = screenGui,
        ZIndex                 = 25,
    })
    addCorner(notifFrame, 4)
    do
        local stroke = Instance.new("UIStroke")
        stroke.Color     = color
        stroke.Thickness = 1
        stroke.Transparency = 1
        stroke.Parent = notifFrame
    end

    local notifLabel = makeLabel({
        Name        = "NotifText",
        Size        = UDim2.new(1, -12, 1, 0),
        Position    = UDim2.new(0, 6, 0, 0),
        Text        = text,
        TextColor3  = color,
        Font        = Enum.Font.GothamBold,
        TextSize    = 10,
        TextWrapped = true,
        ZIndex      = 26,
        Parent      = notifFrame,
    })
    notifLabel.TextTransparency = 1

    local stroke = notifFrame:FindFirstChildOfClass("UIStroke")

    local tweenIn = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    TweenService:Create(notifFrame, tweenIn, {
        BackgroundTransparency = 0.12,
        Position = UDim2.new(0.5, -170, 0, 4),
    }):Play()
    TweenService:Create(notifLabel, tweenIn, { TextTransparency = 0 }):Play()
    if stroke then
        TweenService:Create(stroke, tweenIn, { Transparency = 0.15 }):Play()
    end

    task.delay(NOTIF_HOLD, function()
        local tweenOut = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
        TweenService:Create(notifFrame, tweenOut, {
            BackgroundTransparency = 1,
            Position = UDim2.new(0.5, -170, 0, -2),
        }):Play()
        local t = TweenService:Create(notifLabel, tweenOut, { TextTransparency = 1 })
        t:Play()
        if stroke then
            TweenService:Create(stroke, tweenOut, { Transparency = 1 }):Play()
        end
        t.Completed:Connect(function()
            notifFrame:Destroy()
            notifBusy = false
            processNotifQueue()
        end)
    end)
end

local function queueNotification(text, color)
    if #notifQueue >= 6 then return end
    table.insert(notifQueue, { text, color or COLORS.GOLD })
    processNotifQueue()
end

-- ─── 1. Top-Left Info Badge ─────────────────────────────────────────────────

local infoBadge = makeFrame({
    Name                  = "InfoBadge",
    Size                  = UDim2.new(0, 220, 0, 52),
    Position              = UDim2.new(0, 8, 0, 8),
    BackgroundColor3      = COLORS.HEADER_BG,
    BackgroundTransparency = 0.25,
    Parent                = screenGui,
})
addCorner(infoBadge, 6)

local headerTitle = makeLabel({
    Name       = "Title",
    Size       = UDim2.new(1, -8, 0, 14),
    Position   = UDim2.new(0, 4, 0, 3),
    Text       = "REALM OF MERCANTILISM",
    TextColor3 = COLORS.GOLD,
    Font       = Enum.Font.GothamBold,
    TextSize   = 9,
    TextXAlignment = Enum.TextXAlignment.Left,
    Parent     = infoBadge,
})

local scenarioLabel = makeLabel({
    Name       = "ScenarioLabel",
    Size       = UDim2.new(0.5, 0, 0, 14),
    Position   = UDim2.new(0, 4, 0, 18),
    Text       = "Loading...",
    TextColor3 = COLORS.LIGHT_GRAY,
    Font       = Enum.Font.GothamBold,
    TextSize   = 9,
    TextXAlignment = Enum.TextXAlignment.Left,
    Parent     = infoBadge,
})

local tickLabel = makeLabel({
    Name       = "TickLabel",
    Size       = UDim2.new(0.5, -4, 0, 14),
    Position   = UDim2.new(0.5, 0, 0, 18),
    Text       = "Tick 0/24",
    TextColor3 = COLORS.LIGHT_GRAY,
    Font       = Enum.Font.Gotham,
    TextSize   = 9,
    TextXAlignment = Enum.TextXAlignment.Right,
    Parent     = infoBadge,
})

local globalWealthLabel = makeLabel({
    Name       = "GlobalWealth",
    Size       = UDim2.new(1, -8, 0, 14),
    Position   = UDim2.new(0, 4, 0, 34),
    Text       = "Global: 4,000g",
    TextColor3 = COLORS.GOLD,
    Font       = Enum.Font.GothamBold,
    TextSize   = 10,
    TextXAlignment = Enum.TextXAlignment.Left,
    Parent     = infoBadge,
})

local progressBarBg = makeFrame({
    Name                  = "ProgressBarBg",
    Size                  = UDim2.new(1, 0, 0, 3),
    Position              = UDim2.new(0, 0, 1, -3),
    BackgroundColor3      = Color3.fromRGB(40, 40, 60),
    Parent                = infoBadge,
})

local progressBarFill = makeFrame({
    Name                  = "ProgressBarFill",
    Size                  = UDim2.new(0, 0, 1, 0),
    Position              = UDim2.new(0, 0, 0, 0),
    BackgroundColor3      = COLORS.GOLD,
    Parent                = progressBarBg,
})

-- ─── 2. Bottom Nation Strip (4 cards with resource bars) ──────────────────────

local CARD_W = 185
local CARD_H = 105
local CARD_GAP = 6
local STRIP_W = CARD_W * 4 + CARD_GAP * 3

local nationStrip = makeFrame({
    Name                  = "NationStrip",
    Size                  = UDim2.new(0, STRIP_W, 0, CARD_H + 8),
    Position              = UDim2.new(0.5, -STRIP_W/2, 1, -(CARD_H + 14)),
    BackgroundTransparency = 1,
    Parent                = screenGui,
})

local nationRows = {}

-- Resource bar colors
local RES_BAR_COLORS = {
    Meat  = Color3.fromRGB(180, 40, 40),
    Logs  = Color3.fromRGB(120, 80, 30),
    Ore   = Color3.fromRGB(100, 110, 130),
    Herbs = Color3.fromRGB(50, 160, 60),
}

local function createNationRows()
    for _, row in ipairs(nationRows) do
        row.frame:Destroy()
    end
    nationRows = {}

    for i, nationData in ipairs(Config.NATIONS) do
        local cardX = (i - 1) * (CARD_W + CARD_GAP)
        local card = makeFrame({
            Name                  = "Card_" .. nationData.id,
            Size                  = UDim2.new(0, CARD_W, 0, CARD_H),
            Position              = UDim2.new(0, cardX, 0, 4),
            BackgroundColor3      = Color3.fromRGB(15, 15, 28),
            BackgroundTransparency = 0.2,
            Parent                = nationStrip,
        })
        addCorner(card, 5)

        -- Color accent bar on left edge
        local accent = makeFrame({
            Name                  = "Accent",
            Size                  = UDim2.new(0, 3, 1, -6),
            Position              = UDim2.new(0, 2, 0, 3),
            BackgroundColor3      = nationData.color,
            Parent                = card,
        })
        addCorner(accent, 2)

        -- Nation name
        local nameLabel = makeLabel({
            Name       = "Name",
            Size       = UDim2.new(0.55, 0, 0, 13),
            Position   = UDim2.new(0, 10, 0, 3),
            Text       = nationData.name,
            TextColor3 = COLORS.WHITE,
            Font       = Enum.Font.GothamBold,
            TextSize   = 9,
            TextXAlignment = Enum.TextXAlignment.Left,
            Parent     = card,
        })

        -- Economy tier badge (top-right)
        local tierBadge = makeLabel({
            Name       = "Tier",
            Size       = UDim2.new(0, 40, 0, 13),
            Position   = UDim2.new(1, -48, 0, 3),
            Text       = "RAW",
            TextColor3 = COLORS.LIGHT_GRAY,
            Font       = Enum.Font.GothamBold,
            TextSize   = 7,
            TextXAlignment = Enum.TextXAlignment.Right,
            Parent     = card,
        })

        -- Status badge
        local statusBadge = makeLabel({
            Name       = "Status",
            Size       = UDim2.new(0, 12, 0, 13),
            Position   = UDim2.new(1, -10, 0, 3),
            Text       = "●",
            TextColor3 = COLORS.GREEN,
            Font       = Enum.Font.GothamBold,
            TextSize   = 8,
            TextXAlignment = Enum.TextXAlignment.Right,
            Parent     = card,
        })

        -- Wealth
        local wealthLabel = makeLabel({
            Name       = "Wealth",
            Size       = UDim2.new(1, -12, 0, 14),
            Position   = UDim2.new(0, 10, 0, 16),
            Text       = "1,000g",
            TextColor3 = COLORS.GOLD,
            Font       = Enum.Font.GothamBold,
            TextSize   = 11,
            TextXAlignment = Enum.TextXAlignment.Left,
            Parent     = card,
        })

        -- Balance + Navy
        local balanceLabel = makeLabel({
            Name       = "Balance",
            Size       = UDim2.new(0.5, 0, 0, 11),
            Position   = UDim2.new(0, 10, 0, 31),
            Text       = "+0",
            TextColor3 = COLORS.GREEN,
            Font       = Enum.Font.Gotham,
            TextSize   = 8,
            TextXAlignment = Enum.TextXAlignment.Left,
            Parent     = card,
        })

        local navyLabel = makeLabel({
            Name       = "Navy",
            Size       = UDim2.new(0.5, -10, 0, 11),
            Position   = UDim2.new(0.5, 0, 0, 31),
            Text       = "1W 2T",
            TextColor3 = COLORS.LIGHT_GRAY,
            Font       = Enum.Font.Gotham,
            TextSize   = 8,
            TextXAlignment = Enum.TextXAlignment.Right,
            Parent     = card,
        })

        -- ── Resource Bars (4 tiny bars showing stock levels) ────────────────
        local resourceBars = {}
        local barY = 44
        for ri, res in ipairs(Config.RAW_RESOURCES) do
            -- Resource label
            local resLabel = makeLabel({
                Name       = "ResLabel_" .. res,
                Size       = UDim2.new(0, 28, 0, 9),
                Position   = UDim2.new(0, 10, 0, barY),
                Text       = res:sub(1, 4),
                TextColor3 = RES_BAR_COLORS[res] or COLORS.LIGHT_GRAY,
                Font       = Enum.Font.GothamBold,
                TextSize   = 6,
                TextXAlignment = Enum.TextXAlignment.Left,
                Parent     = card,
            })

            -- Bar background
            local barBg = makeFrame({
                Name                  = "ResBg_" .. res,
                Size                  = UDim2.new(0, 90, 0, 5),
                Position              = UDim2.new(0, 40, 0, barY + 2),
                BackgroundColor3      = Color3.fromRGB(30, 30, 45),
                Parent                = card,
            })
            addCorner(barBg, 2)

            -- Min need marker (thin vertical line)
            local minMarker = makeFrame({
                Name                  = "MinMarker_" .. res,
                Size                  = UDim2.new(0, 1, 1, 2),
                Position              = UDim2.new(Config.RESOURCE_MIN_NEED / Config.RESOURCE_MAX_STOCK, 0, 0, -1),
                BackgroundColor3      = COLORS.RED,
                BackgroundTransparency = 0.3,
                Parent                = barBg,
            })

            -- Bar fill
            local barFill = makeFrame({
                Name                  = "ResFill_" .. res,
                Size                  = UDim2.new(0.4, 0, 1, 0),
                Position              = UDim2.new(0, 0, 0, 0),
                BackgroundColor3      = RES_BAR_COLORS[res] or COLORS.LIGHT_GRAY,
                Parent                = barBg,
            })
            addCorner(barFill, 2)

            -- Stock number
            local stockLabel = makeLabel({
                Name       = "Stock_" .. res,
                Size       = UDim2.new(0, 30, 0, 9),
                Position   = UDim2.new(0, 134, 0, barY),
                Text       = "40",
                TextColor3 = COLORS.LIGHT_GRAY,
                Font       = Enum.Font.Gotham,
                TextSize   = 6,
                TextXAlignment = Enum.TextXAlignment.Right,
                Parent     = card,
            })

            resourceBars[res] = {
                fill = barFill,
                stockLabel = stockLabel,
                resLabel = resLabel,
            }

            barY = barY + 11
        end

        -- ── Diplo dots (bottom row) ─────────────────────────────────────────
        local diploDots = {}
        local dotX = 10
        for _, otherData in ipairs(Config.NATIONS) do
            if otherData.id ~= nationData.id then
                local dot = makeLabel({
                    Name       = "D" .. otherData.id,
                    Size       = UDim2.new(0, 52, 0, 10),
                    Position   = UDim2.new(0, dotX, 0, barY + 1),
                    Text       = "· " .. otherData.name:sub(1,3) .. " 50",
                    TextColor3 = Color3.fromRGB(90, 90, 110),
                    Font       = Enum.Font.GothamBold,
                    TextSize   = 6,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    Parent     = card,
                })
                diploDots[otherData.id] = dot
                dotX = dotX + 56
            end
        end

        table.insert(nationRows, {
            nationId      = nationData.id,
            frame         = card,
            wealthLabel   = wealthLabel,
            balanceLabel  = balanceLabel,
            navyLabel     = navyLabel,
            statusBadge   = statusBadge,
            tierBadge     = tierBadge,
            diploDots     = diploDots,
            resourceBars  = resourceBars,
        })
    end
end

createNationRows()

-- ─── 3. Trade Log ─────────────────────────────────────────────────────────────

local logPanel = makeFrame({
    Name                  = "LogPanel",
    Size                  = UDim2.new(0, 220, 0, 180),
    Position              = UDim2.new(1, -228, 1, -300),
    BackgroundColor3      = COLORS.DARK_PANEL,
    BackgroundTransparency = 0.3,
    Parent                = screenGui,
})
addCorner(logPanel, 5)

local logTitle = makeLabel({
    Name       = "LogTitle",
    Size       = UDim2.new(1, 0, 0, 18),
    Position   = UDim2.new(0, 0, 0, 0),
    Text       = "TRADE LOG",
    TextColor3 = COLORS.GOLD,
    Font       = Enum.Font.GothamBold,
    TextSize   = 9,
    Parent     = logPanel,
})

local scrollFrame = Instance.new("ScrollingFrame")
scrollFrame.Name              = "LogScroll"
scrollFrame.Size              = UDim2.new(1, -4, 1, -22)
scrollFrame.Position          = UDim2.new(0, 2, 0, 20)
scrollFrame.BackgroundTransparency = 1
scrollFrame.ScrollBarThickness = 3
scrollFrame.ScrollBarImageColor3 = COLORS.GOLD
scrollFrame.CanvasSize        = UDim2.new(0, 0, 0, 0)
scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
scrollFrame.Parent            = logPanel

local logListLayout = Instance.new("UIListLayout")
logListLayout.SortOrder       = Enum.SortOrder.LayoutOrder
logListLayout.FillDirection   = Enum.FillDirection.Vertical
logListLayout.VerticalAlignment = Enum.VerticalAlignment.Top
logListLayout.Padding         = UDim.new(0, 1)
logListLayout.Parent          = scrollFrame

local logEntries = {}
local MAX_LOG_ENTRIES = 12

local function getLogColor(message)
    local lower = message:lower()
    if lower:find("%[event%]") then
        if lower:find("plague") or lower:find("crash") or lower:find("mutiny") then
            return COLORS.RED
        elseif lower:find("gold rush") or lower:find("boom") or lower:find("trade wind") then
            return COLORS.GREEN
        else
            return COLORS.ORANGE
        end
    elseif lower:find("bankrupt") then
        return Color3.fromRGB(220, 60, 60)
    elseif lower:find("%[decay%]") or lower:find("abandon") or lower:find("disrepair") or lower:find("desert") then
        return Color3.fromRGB(200, 120, 40)
    elseif lower:find("plunder") or lower:find("raid") or lower:find("intercept") then
        return COLORS.ORANGE
    elseif lower:find("tariff") or lower:find("retaliat") then
        return COLORS.RED
    elseif lower:find("earned") or lower:find("income") then
        return COLORS.GREEN
    elseif lower:find("%[resource%]") then
        return COLORS.ORANGE
    elseif lower:find("tech") or lower:find("mfg") or lower:find("manufacture") then
        return COLORS.CYAN
    else
        return COLORS.LIGHT_GRAY
    end
end

local function addLogEntry(message)
    local displayText = message
    if #displayText > 70 then
        displayText = displayText:sub(1, 67) .. "..."
    end

    local entryLabel = Instance.new("TextLabel")
    entryLabel.Name                  = "LogEntry"
    entryLabel.Size                  = UDim2.new(1, -6, 0, 0)
    entryLabel.AutomaticSize         = Enum.AutomaticSize.Y
    entryLabel.BackgroundTransparency = 1
    entryLabel.Text                  = displayText
    entryLabel.TextColor3            = getLogColor(message)
    entryLabel.Font                  = Enum.Font.Gotham
    entryLabel.TextSize              = 9
    entryLabel.TextWrapped           = true
    entryLabel.TextXAlignment        = Enum.TextXAlignment.Left
    entryLabel.TextYAlignment        = Enum.TextYAlignment.Top
    entryLabel.LayoutOrder           = 0
    entryLabel.Parent                = scrollFrame

    for _, entry in ipairs(logEntries) do
        entry.LayoutOrder = entry.LayoutOrder + 1
    end

    table.insert(logEntries, 1, entryLabel)

    while #logEntries > MAX_LOG_ENTRIES do
        local old = table.remove(logEntries)
        old:Destroy()
    end

    scrollFrame.CanvasPosition = Vector2.new(0, 0)
end

-- ─── 4. Sparkline ─────────────────────────────────────────────────────────────

local SPARK_COUNT  = 10
local sparkHistory = {}

local sparkFrame = makeFrame({
    Name                  = "SparkFrame",
    Size                  = UDim2.new(0, 120, 0, 30),
    Position              = UDim2.new(1, -128, 0, 8),
    BackgroundColor3      = COLORS.HEADER_BG,
    BackgroundTransparency = 0.3,
    Parent                = screenGui,
})
addCorner(sparkFrame, 4)

local sparkBars = {}
local barWidth  = math.floor((120 - 12) / SPARK_COUNT) - 2
for i = 1, SPARK_COUNT do
    local bar = makeFrame({
        Name                  = "SparkBar" .. i,
        Size                  = UDim2.new(0, barWidth, 0, 3),
        Position              = UDim2.new(0, 6 + (i - 1) * (barWidth + 2), 1, -5),
        BackgroundColor3      = COLORS.GOLD,
        BackgroundTransparency = 0.2,
        Parent                = sparkFrame,
    })
    addCorner(bar, 1)
    table.insert(sparkBars, bar)
end

local function updateSparkline(globalWealth)
    table.insert(sparkHistory, globalWealth)
    if #sparkHistory > SPARK_COUNT then
        table.remove(sparkHistory, 1)
    end
    local maxW = 0
    for _, w in ipairs(sparkHistory) do
        if w > maxW then maxW = w end
    end
    for i, bar in ipairs(sparkBars) do
        local w     = sparkHistory[i] or 0
        local frac  = maxW > 0 and (w / maxW) or 0
        local hpx   = math.max(2, math.floor(frac * 22))
        bar.Size     = UDim2.new(0, barWidth, 0, hpx)
        bar.Position = UDim2.new(0, 6 + (i - 1) * (barWidth + 2), 1, -hpx - 3)
        if i > 1 and sparkHistory[i] and sparkHistory[i - 1] then
            if sparkHistory[i] > sparkHistory[i - 1] then
                bar.BackgroundColor3 = COLORS.GREEN
            elseif sparkHistory[i] < sparkHistory[i - 1] then
                bar.BackgroundColor3 = COLORS.RED
            else
                bar.BackgroundColor3 = COLORS.GOLD
            end
        else
            bar.BackgroundColor3 = COLORS.GOLD
        end
    end
end

-- ─── 5. Scenario Comparison Panel ─────────────────────────────────────────────

local scenarioResults = {}

local comparisonPanel = makeFrame({
    Name                  = "ComparisonPanel",
    Size                  = UDim2.new(0, 500, 0, 300),
    Position              = UDim2.new(0.5, -250, 0.5, -150),
    BackgroundColor3      = COLORS.DARK_PANEL,
    BackgroundTransparency = 0.05,
    Parent                = screenGui,
    ZIndex                = 10,
})
comparisonPanel.Visible = false
addCorner(comparisonPanel, 8)

local compTitle = makeLabel({
    Name = "CompTitle", Size = UDim2.new(1, 0, 0, 34),
    Text = "SCENARIO COMPARISON", TextColor3 = COLORS.GOLD,
    Font = Enum.Font.GothamBold, TextSize = 18, ZIndex = 11,
    Parent = comparisonPanel,
})

local mercHeader = makeLabel({
    Name = "MercHeader", Size = UDim2.new(0.45, 0, 0, 24),
    Position = UDim2.new(0.05, 0, 0, 36),
    Text = "MERCANTILIST", TextColor3 = COLORS.RED,
    Font = Enum.Font.GothamBold, TextSize = 13, ZIndex = 11,
    Parent = comparisonPanel,
})

local freeHeader = makeLabel({
    Name = "FreeHeader", Size = UDim2.new(0.45, 0, 0, 24),
    Position = UDim2.new(0.5, 0, 0, 36),
    Text = "FREE TRADE", TextColor3 = COLORS.GREEN,
    Font = Enum.Font.GothamBold, TextSize = 13, ZIndex = 11,
    Parent = comparisonPanel,
})

local divider = makeFrame({
    Name = "Divider", Size = UDim2.new(0, 2, 0, 180),
    Position = UDim2.new(0.5, -1, 0, 58),
    BackgroundColor3 = Color3.fromRGB(60, 60, 80), ZIndex = 11,
    Parent = comparisonPanel,
})

local mercGlobalLabel = makeLabel({
    Name = "MercGlobal", Size = UDim2.new(0.45, 0, 0, 18),
    Position = UDim2.new(0.05, 0, 0, 64), Text = "Global: —",
    TextColor3 = COLORS.LIGHT_GRAY, Font = Enum.Font.Gotham,
    TextSize = 11, ZIndex = 11, Parent = comparisonPanel,
})
local mercWinnerLabel = makeLabel({
    Name = "MercWinner", Size = UDim2.new(0.45, 0, 0, 18),
    Position = UDim2.new(0.05, 0, 0, 84), Text = "Winner: —",
    TextColor3 = COLORS.LIGHT_GRAY, Font = Enum.Font.Gotham,
    TextSize = 11, ZIndex = 11, Parent = comparisonPanel,
})
local mercNationsLabel = makeLabel({
    Name = "MercNations", Size = UDim2.new(0.45, 0, 0, 90),
    Position = UDim2.new(0.05, 0, 0, 104), Text = "",
    TextColor3 = COLORS.LIGHT_GRAY, Font = Enum.Font.Gotham,
    TextSize = 10, TextYAlignment = Enum.TextYAlignment.Top,
    ZIndex = 11, Parent = comparisonPanel,
})

local freeGlobalLabel = makeLabel({
    Name = "FreeGlobal", Size = UDim2.new(0.45, 0, 0, 18),
    Position = UDim2.new(0.5, 5, 0, 64), Text = "Global: —",
    TextColor3 = COLORS.LIGHT_GRAY, Font = Enum.Font.Gotham,
    TextSize = 11, ZIndex = 11, Parent = comparisonPanel,
})
local freeWinnerLabel = makeLabel({
    Name = "FreeWinner", Size = UDim2.new(0.45, 0, 0, 18),
    Position = UDim2.new(0.5, 5, 0, 84), Text = "Winner: —",
    TextColor3 = COLORS.LIGHT_GRAY, Font = Enum.Font.Gotham,
    TextSize = 11, ZIndex = 11, Parent = comparisonPanel,
})
local freeNationsLabel = makeLabel({
    Name = "FreeNations", Size = UDim2.new(0.45, 0, 0, 90),
    Position = UDim2.new(0.5, 5, 0, 104), Text = "",
    TextColor3 = COLORS.LIGHT_GRAY, Font = Enum.Font.Gotham,
    TextSize = 10, TextYAlignment = Enum.TextYAlignment.Top,
    ZIndex = 11, Parent = comparisonPanel,
})

local conclusionLabel = makeLabel({
    Name = "Conclusion", Size = UDim2.new(0.9, 0, 0, 30),
    Position = UDim2.new(0.05, 0, 0, 230), Text = "",
    TextColor3 = COLORS.GOLD, Font = Enum.Font.GothamBold,
    TextSize = 12, TextWrapped = true, ZIndex = 11,
    Parent = comparisonPanel,
})

local closeBtn = Instance.new("TextButton")
closeBtn.Name = "CloseBtn"
closeBtn.Size = UDim2.new(0, 80, 0, 26)
closeBtn.Position = UDim2.new(0.5, -40, 1, -34)
closeBtn.BackgroundColor3 = Color3.fromRGB(80, 30, 30)
closeBtn.BorderSizePixel = 0
closeBtn.Text = "Close"
closeBtn.TextColor3 = COLORS.WHITE
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 11
closeBtn.ZIndex = 12
closeBtn.Parent = comparisonPanel
addCorner(closeBtn, 4)

closeBtn.MouseButton1Click:Connect(function()
    comparisonPanel.Visible = false
end)

local function showComparison(mercData, freeData)
    local mercWealth = mercData and mercData.globalWealth or 0
    local freeWealth = freeData and freeData.globalWealth or 0

    mercGlobalLabel.Text = "Global: " .. formatGold(mercWealth)
    mercWinnerLabel.Text = "Winner: " .. (mercData and mercData.winnerName or "—")
    freeGlobalLabel.Text = "Global: " .. formatGold(freeWealth)
    freeWinnerLabel.Text = "Winner: " .. (freeData and freeData.winnerName or "—")

    if mercData and mercData.nations then
        local lines = {}
        for _, n in ipairs(mercData.nations) do
            table.insert(lines, n.name .. ": " .. formatGold(n.wealth))
        end
        mercNationsLabel.Text = table.concat(lines, "\n")
    end
    if freeData and freeData.nations then
        local lines = {}
        for _, n in ipairs(freeData.nations) do
            table.insert(lines, n.name .. ": " .. formatGold(n.wealth))
        end
        freeNationsLabel.Text = table.concat(lines, "\n")
    end

    if mercWealth > 0 then
        local pct = math.floor(((freeWealth - mercWealth) / mercWealth) * 100)
        if pct > 0 then
            conclusionLabel.Text = string.format("Free trade generated %d%% more total wealth.", pct)
            conclusionLabel.TextColor3 = COLORS.GREEN
        elseif pct < 0 then
            conclusionLabel.Text = string.format("Mercantilism generated %d%% more total wealth.", math.abs(pct))
            conclusionLabel.TextColor3 = COLORS.RED
        else
            conclusionLabel.Text = "Both scenarios generated equal total wealth."
            conclusionLabel.TextColor3 = COLORS.GOLD
        end
    end

    comparisonPanel.Visible = true
end

-- ─── Update Functions ─────────────────────────────────────────────────────────

local firstUpdateReceived = false

local function updateLeaderboard(summary)
    if not summary or not summary.nations then return end

    if not firstUpdateReceived then
        firstUpdateReceived = true
    end

    -- Scenario label
    local scenarioDisplay = summary.scenario or "—"
    if scenarioDisplay == Config.SCENARIOS.MERCANTILIST then
        scenarioDisplay = "Mercantilist"
        scenarioLabel.TextColor3 = COLORS.RED
    elseif scenarioDisplay == Config.SCENARIOS.FREE_TRADE then
        scenarioDisplay = "Free Trade"
        scenarioLabel.TextColor3 = COLORS.GREEN
    end
    scenarioLabel.Text = scenarioDisplay

    -- Tick + progress
    local tick = summary.tick or 0
    local progress = tick / Config.MAX_TICKS
    tickLabel.Text = string.format("Tick %d/%d", tick, Config.MAX_TICKS)
    progressBarFill:TweenSize(
        UDim2.new(progress, 0, 1, 0),
        Enum.EasingDirection.Out, Enum.EasingStyle.Linear, 0.5, true
    )

    -- Richest nation colors the progress bar
    local richestColor = COLORS.GOLD
    local richestWealth = 0
    local nationDataById = {}
    for _, nd in ipairs(Config.NATIONS) do
        nationDataById[nd.id] = nd
    end
    for _, ns in ipairs(summary.nations) do
        if ns.wealth > richestWealth then
            richestWealth = ns.wealth
            local nd = nationDataById[ns.id]
            if nd then richestColor = nd.color end
        end
    end
    progressBarFill.BackgroundColor3 = richestColor

    -- Global wealth + sparkline
    globalWealthLabel.Text = "Global: " .. formatGold(summary.globalWealth)
    updateSparkline(summary.globalWealth or 0)

    -- Nation cards
    local nationSummaryById = {}
    for _, ns in ipairs(summary.nations) do
        nationSummaryById[ns.id] = ns
    end

    for _, row in ipairs(nationRows) do
        local ns = nationSummaryById[row.nationId]
        if ns then
            row.wealthLabel.Text = formatGold(ns.wealth)

            local balance = ns.tradeBalance or 0
            row.balanceLabel.Text = signedStr(balance) .. "g"
            row.balanceLabel.TextColor3 = balance >= 0 and COLORS.GREEN or COLORS.RED

            row.navyLabel.Text = string.format("%dW %dT", ns.warships or 0, ns.tradeShips or 0)

            -- Economy tier badge
            if row.tierBadge then
                local tier = ns.economyTier or 1
                if tier >= 3 then
                    row.tierBadge.Text = "TECH"
                    row.tierBadge.TextColor3 = COLORS.CYAN
                elseif tier >= 2 then
                    row.tierBadge.Text = "MFG"
                    row.tierBadge.TextColor3 = COLORS.GOLD
                else
                    row.tierBadge.Text = "RAW"
                    row.tierBadge.TextColor3 = COLORS.LIGHT_GRAY
                end
            end

            -- Status badge
            if row.statusBadge then
                local level = ns.degradationLevel or "healthy"
                if level == "healthy" then
                    row.statusBadge.Text = "●"
                    row.statusBadge.TextColor3 = COLORS.GREEN
                elseif level == "struggling" then
                    row.statusBadge.Text = "⚠"
                    row.statusBadge.TextColor3 = Color3.fromRGB(255, 200, 0)
                elseif level == "critical" then
                    row.statusBadge.Text = "✦"
                    row.statusBadge.TextColor3 = COLORS.ORANGE
                else
                    row.statusBadge.Text = "✗"
                    row.statusBadge.TextColor3 = COLORS.RED
                end
            end

            -- Resource bars
            if row.resourceBars and ns.resources then
                for _, res in ipairs(Config.RAW_RESOURCES) do
                    local barData = row.resourceBars[res]
                    if barData then
                        local stock = ns.resources[res] or 0
                        local fraction = math.clamp(stock / Config.RESOURCE_MAX_STOCK, 0, 1)
                        barData.fill.Size = UDim2.new(fraction, 0, 1, 0)
                        barData.stockLabel.Text = tostring(math.floor(stock))

                        -- Color the bar based on urgency
                        if stock < Config.RESOURCE_MIN_NEED then
                            barData.fill.BackgroundColor3 = COLORS.RED
                            barData.stockLabel.TextColor3 = COLORS.RED
                        elseif stock >= Config.RESOURCE_MAX_STOCK * 0.9 then
                            barData.fill.BackgroundColor3 = Color3.fromRGB(60, 180, 60)
                            barData.stockLabel.TextColor3 = COLORS.GREEN
                        else
                            barData.fill.BackgroundColor3 = RES_BAR_COLORS[res] or COLORS.LIGHT_GRAY
                            barData.stockLabel.TextColor3 = COLORS.LIGHT_GRAY
                        end
                    end
                end
            end

            -- Diplo dots with relationship scores
            if row.diploDots then
                local relationData = summary.relations and summary.relations[ns.id]
                local diploRelations = ns.diplomaticRelations

                for _, otherData in ipairs(Config.NATIONS) do
                    if otherData.id ~= ns.id then
                        local dot = row.diploDots[otherData.id]
                        if dot then
                            local pName = otherData.name:sub(1, 3)
                            local relScore = relationData and relationData[tostring(otherData.id)] or 50
                            local state = diploRelations and diploRelations[tostring(otherData.id)] or "neutral"

                            if state == "allied" then
                                dot.Text = "● " .. pName .. " " .. math.floor(relScore)
                                dot.TextColor3 = COLORS.GREEN
                            elseif state == "embargo" then
                                dot.Text = "✗ " .. pName .. " " .. math.floor(relScore)
                                dot.TextColor3 = COLORS.RED
                            else
                                dot.Text = "· " .. pName .. " " .. math.floor(relScore)
                                -- Color based on relationship score
                                if relScore >= 70 then
                                    dot.TextColor3 = Color3.fromRGB(100, 180, 100)
                                elseif relScore <= 30 then
                                    dot.TextColor3 = Color3.fromRGB(180, 100, 100)
                                else
                                    dot.TextColor3 = Color3.fromRGB(90, 90, 110)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

-- ─── Remote Event Connections ─────────────────────────────────────────────────

if wealthUpdated then
    wealthUpdated.OnClientEvent:Connect(function(summary)
        updateLeaderboard(summary)
    end)
end

if tickLogEvent then
    tickLogEvent.OnClientEvent:Connect(function(logString)
        if logString and logString ~= "" then
            local lines = logString:split("\n")
            for i = #lines, 1, -1 do
                local line = lines[i]
                if line and line ~= "" then
                    addLogEntry(line)

                    local lower = line:lower()
                    if lower:find("%[event%]") then
                        local evtColor = COLORS.GOLD
                        if lower:find("plague") or lower:find("crash") or lower:find("mutiny") then
                            evtColor = COLORS.RED
                        elseif lower:find("gold rush") or lower:find("boom") or lower:find("trade wind") then
                            evtColor = COLORS.GREEN
                        elseif lower:find("storm") then
                            evtColor = COLORS.ORANGE
                        end
                        queueNotification(line:gsub("%[EVENT%] ", ""), evtColor)
                    elseif lower:find("%[privateer%]") then
                        queueNotification(line:gsub("%[PRIVATEER%] ", ""), COLORS.ORANGE)
                    elseif lower:find("%[sabotage%]") and not lower:find("fails") then
                        queueNotification(line:gsub("%[SABOTAGE%] ", ""), Color3.fromRGB(220, 80, 200))
                    elseif lower:find("%[diplomacy%]") and lower:find("embargo") then
                        queueNotification(line:gsub("%[DIPLOMACY%] ", ""), COLORS.RED)
                    elseif lower:find("%[diplomacy%]") and lower:find("treaty") then
                        queueNotification(line:gsub("%[DIPLOMACY%] ", ""), COLORS.GREEN)
                    elseif lower:find("%[bankrupt%]") then
                        queueNotification(line:gsub("%[BANKRUPT%] ", ""), COLORS.RED)
                    elseif lower:find("%[plunder%]") then
                        queueNotification(line:gsub("%[PLUNDER%] ", ""), COLORS.ORANGE)
                    elseif lower:find("%[decay%]") then
                        queueNotification(line:gsub("%[DECAY%] ", ""), Color3.fromRGB(200, 120, 40))
                    elseif lower:find("%[resource%]") then
                        queueNotification(line:gsub("%[RESOURCE%] ", ""), COLORS.ORANGE)
                    end
                end
            end
        end
    end)
end

if simEndedEvent then
    simEndedEvent.OnClientEvent:Connect(function(results)
        if results and results.scenario then
            scenarioResults[results.scenario] = results
            addLogEntry(string.format(
                "[SIM END] %s done! Global: %s | Winner: %s",
                results.scenario, formatGold(results.globalWealth),
                results.winnerName or "?"
            ))
        end
    end)
end

if comparisonEvent then
    comparisonEvent.OnClientEvent:Connect(function(mercData, freeData)
        if mercData then scenarioResults[Config.SCENARIOS.MERCANTILIST] = mercData end
        if freeData then scenarioResults[Config.SCENARIOS.FREE_TRADE]   = freeData end
        showComparison(
            scenarioResults[Config.SCENARIOS.MERCANTILIST],
            scenarioResults[Config.SCENARIOS.FREE_TRADE]
        )
    end)
end

-- ─── 6. Data Export Panel ─────────────────────────────────────────────────────

local dataExportOverlay = makeFrame({
    Name                  = "DataExportOverlay",
    Size                  = UDim2.new(1, 0, 1, 0),
    Position              = UDim2.new(0, 0, 0, 0),
    BackgroundColor3      = Color3.fromRGB(0, 0, 0),
    BackgroundTransparency = 0.35,
    Parent                = screenGui,
    ZIndex                = 30,
})
dataExportOverlay.Visible = false

local dataPanel = makeFrame({
    Name                  = "DataPanel",
    Size                  = UDim2.new(0, 700, 0, 460),
    Position              = UDim2.new(0.5, -350, 0.5, -230),
    BackgroundColor3      = COLORS.DARK_PANEL,
    BackgroundTransparency = 0.02,
    Parent                = dataExportOverlay,
    ZIndex                = 31,
})
addCorner(dataPanel, 8)

local dataPanelTitle = makeLabel({
    Name       = "DataTitle",
    Size       = UDim2.new(1, 0, 0, 30),
    Position   = UDim2.new(0, 0, 0, 6),
    Text       = "DATA EXPORT — Select All & Copy (Ctrl+A, Ctrl+C)",
    TextColor3 = COLORS.GOLD,
    Font       = Enum.Font.GothamBold,
    TextSize   = 12,
    ZIndex     = 32,
    Parent     = dataPanel,
})

local DATA_TABS = { "Tick Data", "Events", "Aggregates" }
local dataTabButtons = {}
local dataContents = { "", "", "" }
local activeDataTab = 1

local tabBar = makeFrame({
    Name                  = "TabBar",
    Size                  = UDim2.new(1, -16, 0, 26),
    Position              = UDim2.new(0, 8, 0, 38),
    BackgroundTransparency = 1,
    Parent                = dataPanel,
    ZIndex                = 32,
})

for i, tabName in ipairs(DATA_TABS) do
    local tabBtn = Instance.new("TextButton")
    tabBtn.Name = "Tab" .. i
    tabBtn.Size = UDim2.new(0, 120, 1, 0)
    tabBtn.Position = UDim2.new(0, (i - 1) * 126, 0, 0)
    tabBtn.BackgroundColor3 = i == 1 and COLORS.GOLD or Color3.fromRGB(40, 40, 60)
    tabBtn.BorderSizePixel = 0
    tabBtn.Text = tabName
    tabBtn.TextColor3 = i == 1 and Color3.fromRGB(10, 10, 20) or COLORS.LIGHT_GRAY
    tabBtn.Font = Enum.Font.GothamBold
    tabBtn.TextSize = 10
    tabBtn.ZIndex = 33
    tabBtn.Parent = tabBar
    addCorner(tabBtn, 4)
    dataTabButtons[i] = tabBtn
end

local dataScroll = Instance.new("ScrollingFrame")
dataScroll.Name              = "DataScroll"
dataScroll.Size              = UDim2.new(1, -16, 1, -100)
dataScroll.Position          = UDim2.new(0, 8, 0, 68)
dataScroll.BackgroundColor3  = Color3.fromRGB(8, 8, 16)
dataScroll.BackgroundTransparency = 0
dataScroll.BorderSizePixel   = 0
dataScroll.ScrollBarThickness = 6
dataScroll.ScrollBarImageColor3 = COLORS.GOLD
dataScroll.CanvasSize        = UDim2.new(0, 0, 0, 0)
dataScroll.AutomaticCanvasSize = Enum.AutomaticSize.XY
dataScroll.ZIndex            = 32
dataScroll.Parent            = dataPanel
addCorner(dataScroll, 4)

local dataTextBox = Instance.new("TextBox")
dataTextBox.Name                  = "DataText"
dataTextBox.Size                  = UDim2.new(1, -8, 1, 0)
dataTextBox.Position              = UDim2.new(0, 4, 0, 0)
dataTextBox.BackgroundTransparency = 1
dataTextBox.Text                  = ""
dataTextBox.TextColor3            = Color3.fromRGB(200, 210, 220)
dataTextBox.Font                  = Enum.Font.Code
dataTextBox.TextSize              = 9
dataTextBox.TextXAlignment        = Enum.TextXAlignment.Left
dataTextBox.TextYAlignment        = Enum.TextYAlignment.Top
dataTextBox.TextWrapped           = false
dataTextBox.MultiLine             = true
dataTextBox.ClearTextOnFocus      = false
dataTextBox.TextEditable          = false
dataTextBox.ZIndex                = 33
dataTextBox.AutomaticSize         = Enum.AutomaticSize.XY
dataTextBox.Parent                = dataScroll

local function switchDataTab(tabIndex)
    activeDataTab = tabIndex
    dataTextBox.Text = dataContents[tabIndex] or ""
    dataScroll.CanvasPosition = Vector2.new(0, 0)
    for i, btn in ipairs(dataTabButtons) do
        if i == tabIndex then
            btn.BackgroundColor3 = COLORS.GOLD
            btn.TextColor3 = Color3.fromRGB(10, 10, 20)
        else
            btn.BackgroundColor3 = Color3.fromRGB(40, 40, 60)
            btn.TextColor3 = COLORS.LIGHT_GRAY
        end
    end
end

for i, btn in ipairs(dataTabButtons) do
    btn.MouseButton1Click:Connect(function()
        switchDataTab(i)
    end)
end

local dataCloseBtn = Instance.new("TextButton")
dataCloseBtn.Name = "DataCloseBtn"
dataCloseBtn.Size = UDim2.new(0, 80, 0, 26)
dataCloseBtn.Position = UDim2.new(0.5, -40, 1, -32)
dataCloseBtn.BackgroundColor3 = Color3.fromRGB(80, 30, 30)
dataCloseBtn.BorderSizePixel = 0
dataCloseBtn.Text = "Close"
dataCloseBtn.TextColor3 = COLORS.WHITE
dataCloseBtn.Font = Enum.Font.GothamBold
dataCloseBtn.TextSize = 11
dataCloseBtn.ZIndex = 33
dataCloseBtn.Parent = dataPanel
addCorner(dataCloseBtn, 4)

dataCloseBtn.MouseButton1Click:Connect(function()
    dataExportOverlay.Visible = false
end)

if dataExportEvent then
    dataExportEvent.OnClientEvent:Connect(function(tickCSV, eventCSV, aggregates)
        dataContents[1] = tickCSV or ""
        dataContents[2] = eventCSV or ""
        dataContents[3] = aggregates or ""
        switchDataTab(1)
        dataExportOverlay.Visible = true
        addLogEntry("[DATA] Export ready — click Data Export to view")
    end)
end

-- ─── Initial state ─────────────────────────────────────────────────────────

scenarioLabel.Text = "Loading..."

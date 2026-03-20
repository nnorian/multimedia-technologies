-- GameManager.server.lua (v4 — resource economy, relationship-based trade, animations)
-- Server Script: main game loop, orchestrates the simulation
-- Place in ServerScriptService

local RS          = game:GetService("ReplicatedStorage")
local RunService  = game:GetService("RunService")

local Config            = require(RS:WaitForChild("GameConfig"))
local NationState       = require(RS:WaitForChild("NationState"))
local TradeSystem       = require(RS:WaitForChild("TradeSystem"))
local NavalSystem       = require(RS:WaitForChild("NavalSystem"))
local DegradationSystem = require(RS:WaitForChild("DegradationSystem"))
local DiplomacySystem   = require(RS:WaitForChild("DiplomacySystem"))
local DataCollector     = require(RS:WaitForChild("DataCollector"))

-- ─── RemoteEvent Setup ────────────────────────────────────────────────────────

local simEventsFolder = Instance.new("Folder")
simEventsFolder.Name   = "SimEvents"
simEventsFolder.Parent = RS

local function makeRemote(name)
    local re = Instance.new("RemoteEvent")
    re.Name   = name
    re.Parent = simEventsFolder
    return re
end

local wealthUpdatedEvent   = makeRemote("WealthUpdated")
local tickLogEvent         = makeRemote("TickLog")
local simEndedEvent        = makeRemote("SimulationEnded")
local comparisonEvent      = makeRemote("ComparisonReady")
local startSimulationEvent = makeRemote("StartSimulation")
local dataExportEvent      = makeRemote("DataExport")

-- ─── Wait for MapSetup to finish ─────────────────────────────────────────────

task.wait(3)

-- ─── Trade Route Visual Update ────────────────────────────────────────────────

local function updateTradeRouteVisuals(allNations)
    local tradeRoutes = workspace:FindFirstChild("TradeRouteVisuals")
    if not tradeRoutes then return end

    local nationsByName = {}
    for _, n in ipairs(allNations) do
        nationsByName[n.name] = n
    end

    for _, routePart in ipairs(tradeRoutes:GetChildren()) do
        if routePart:IsA("BasePart") then
            local n1Name, n2Name = routePart.Name:match("^(.-)_to_(.+)$")
            if n1Name and n2Name then
                local n1 = nationsByName[n1Name]
                local n2 = nationsByName[n2Name]
                if n1 and n2 then
                    local state = DiplomacySystem.getState(n1.id, n2.id)
                    if state == DiplomacySystem.State.EMBARGO then
                        routePart.Color        = Color3.fromRGB(200, 40, 40)
                        routePart.Transparency = 0.35
                    elseif state == DiplomacySystem.State.ALLIED then
                        routePart.Color        = Color3.fromRGB(255, 215, 0)
                        routePart.Transparency = 0.30
                    else
                        routePart.Color        = Color3.fromRGB(255, 255, 200)
                        routePart.Transparency = 0.70
                    end
                end
            end
        end
    end
end

-- ─── Ship Animation Helper ────────────────────────────────────────────────────

local function animateShip(shipModel, fromPos, toPos, duration)
    if not shipModel or not shipModel.PrimaryPart then return nil end

    local startCF  = shipModel:GetPivot()
    local yaw      = math.atan2(toPos.X - fromPos.X, toPos.Z - fromPos.Z)
    local targetCF = CFrame.new(toPos) * CFrame.Angles(0, yaw, 0)

    local bindable = Instance.new("BindableEvent")
    local elapsed  = 0
    local conn
    conn = RunService.Heartbeat:Connect(function(dt)
        elapsed = elapsed + dt
        local t = math.min(elapsed / duration, 1)
        local s = t * t * (3 - 2 * t)
        shipModel:PivotTo(startCF:Lerp(targetCF, s))
        if t >= 1 then
            conn:Disconnect()
            bindable:Fire()
            task.defer(function() bindable:Destroy() end)
        end
    end)

    return { Completed = bindable.Event }
end

local animatingShips = {}

local function isAnimating(shipModel)
    return animatingShips[shipModel] == true
end

local function markAnimating(shipModel, active)
    animatingShips[shipModel] = active or nil
end

-- ─── Explosion Animation (for raids) ─────────────────────────────────────────

local function playExplosion(position)
    -- Create a burst of fiery spheres at the position
    local explosionParts = {}
    local center = position + Vector3.new(0, 3, 0)

    -- Main explosion sphere
    local mainBlast = Instance.new("Part")
    mainBlast.Name = "ExplosionMain"
    mainBlast.Shape = Enum.PartType.Ball
    mainBlast.Size = Vector3.new(4, 4, 4)
    mainBlast.Position = center
    mainBlast.Anchored = true
    mainBlast.CanCollide = false
    mainBlast.Color = Color3.fromRGB(255, 120, 20)
    mainBlast.Material = Enum.Material.Neon
    mainBlast.Transparency = 0
    mainBlast.Parent = workspace
    table.insert(explosionParts, mainBlast)

    -- Shrapnel pieces
    for i = 1, 6 do
        local shard = Instance.new("Part")
        shard.Name = "Shrapnel" .. i
        shard.Size = Vector3.new(1.5, 1.5, 1.5)
        shard.Position = center + Vector3.new(
            (math.random() - 0.5) * 6,
            math.random() * 4,
            (math.random() - 0.5) * 6
        )
        shard.Anchored = true
        shard.CanCollide = false
        shard.Color = i <= 3 and Color3.fromRGB(255, 80, 10) or Color3.fromRGB(255, 200, 50)
        shard.Material = Enum.Material.Neon
        shard.Transparency = 0.1
        shard.Parent = workspace
        table.insert(explosionParts, shard)
    end

    -- Smoke ring
    local smoke = Instance.new("Part")
    smoke.Name = "ExplosionSmoke"
    smoke.Shape = Enum.PartType.Ball
    smoke.Size = Vector3.new(8, 8, 8)
    smoke.Position = center
    smoke.Anchored = true
    smoke.CanCollide = false
    smoke.Color = Color3.fromRGB(60, 60, 60)
    smoke.Material = Enum.Material.SmoothPlastic
    smoke.Transparency = 0.4
    smoke.Parent = workspace
    table.insert(explosionParts, smoke)

    -- Animate: expand and fade over 1.5 seconds
    local elapsed = 0
    local duration = 1.5
    local conn
    conn = RunService.Heartbeat:Connect(function(dt)
        elapsed = elapsed + dt
        local t = math.min(elapsed / duration, 1)

        -- Main blast grows and fades
        mainBlast.Size = Vector3.new(4 + t * 10, 4 + t * 10, 4 + t * 10)
        mainBlast.Transparency = t
        mainBlast.Color = Color3.fromRGB(
            math.floor(255 * (1 - t * 0.5)),
            math.floor(120 * (1 - t)),
            math.floor(20 * (1 - t))
        )

        -- Shrapnel flies outward and fades
        for _, shard in ipairs(explosionParts) do
            if shard.Name:find("Shrapnel") then
                local dir = (shard.Position - center).Unit
                shard.Position = shard.Position + dir * dt * 15
                shard.Transparency = t * 0.8
                shard.Size = Vector3.new(1.5 * (1 - t * 0.5), 1.5 * (1 - t * 0.5), 1.5 * (1 - t * 0.5))
            end
        end

        -- Smoke expands slower
        smoke.Size = Vector3.new(8 + t * 16, 6 + t * 8, 8 + t * 16)
        smoke.Transparency = 0.4 + t * 0.6

        if t >= 1 then
            conn:Disconnect()
            for _, part in ipairs(explosionParts) do
                part:Destroy()
            end
        end
    end)
end

-- ─── Sinking Animation (for storms) ──────────────────────────────────────────

local function playSinking(shipModel)
    if not shipModel or not shipModel.PrimaryPart then return end

    local startPos = shipModel:GetPivot().Position
    local startCF = shipModel:GetPivot()
    local elapsed = 0
    local duration = 3.0

    -- Create water splash particles
    local splashParts = {}
    for i = 1, 4 do
        local splash = Instance.new("Part")
        splash.Name = "WaterSplash" .. i
        splash.Shape = Enum.PartType.Ball
        splash.Size = Vector3.new(2, 1, 2)
        splash.Position = startPos + Vector3.new(
            (math.random() - 0.5) * 8, 0.5, (math.random() - 0.5) * 8
        )
        splash.Anchored = true
        splash.CanCollide = false
        splash.Color = Color3.fromRGB(80, 150, 220)
        splash.Material = Enum.Material.Neon
        splash.Transparency = 0.3
        splash.Parent = workspace
        table.insert(splashParts, splash)
    end

    local conn
    conn = RunService.Heartbeat:Connect(function(dt)
        elapsed = elapsed + dt
        local t = math.min(elapsed / duration, 1)
        local s = t * t -- accelerating descent

        -- Ship sinks down and tilts
        local sinkY = startPos.Y - s * 12
        local tiltAngle = s * math.rad(25)
        local sinkCF = CFrame.new(startPos.X, sinkY, startPos.Z)
            * CFrame.Angles(tiltAngle, startCF.Rotation.Y, tiltAngle * 0.5)
        shipModel:PivotTo(sinkCF)

        -- Make ship transparent as it sinks
        for _, part in ipairs(shipModel:GetDescendants()) do
            if part:IsA("BasePart") then
                part.Transparency = math.min(0.9, t * 0.9)
            end
        end

        -- Splash particles rise and fade
        for _, splash in ipairs(splashParts) do
            splash.Position = splash.Position + Vector3.new(0, dt * 3, 0)
            splash.Size = splash.Size + Vector3.new(dt * 2, dt, dt * 2)
            splash.Transparency = 0.3 + t * 0.7
        end

        if t >= 1 then
            conn:Disconnect()
            -- Clean up splashes
            for _, splash in ipairs(splashParts) do
                splash:Destroy()
            end
            -- Move ship far away (it's "sunk")
            shipModel:PivotTo(CFrame.new(0, -100, 0))
            -- Reset transparency for potential reuse
            for _, part in ipairs(shipModel:GetDescendants()) do
                if part:IsA("BasePart") then
                    part.Transparency = 0
                end
            end
        end
    end)
end

-- ─── Update Cargo Stripe Colors ──────────────────────────────────────────────
-- Changes the cargo stripe and hold colors on trade ships to reflect what they're carrying

local function updateShipCargoColor(shipModel, resourceName)
    if not shipModel then return end
    local cargoColor = Config.RESOURCE_COLORS[resourceName]
    if not cargoColor then return end

    local cargoStripeL = shipModel:FindFirstChild("CargoStripeL")
    local cargoStripeR = shipModel:FindFirstChild("CargoStripeR")
    local cargoHold = shipModel:FindFirstChild("CargoHold")

    if cargoStripeL then cargoStripeL.Color = cargoColor end
    if cargoStripeR then cargoStripeR.Color = cargoColor end
    if cargoHold then cargoHold.Color = cargoColor end
end

-- ─── Utility: update treasury BillboardGui ────────────────────────────────────

local function updateTreasuryLabels()
    local islandsFolder = workspace:FindFirstChild("Islands")
    if not islandsFolder then return end

    for _, nation in ipairs(NationState.getAllNations()) do
        local islandModel = islandsFolder:FindFirstChild(nation.name)
        if islandModel then
            local labelAnchor = islandModel:FindFirstChild("LabelAnchor")
            if labelAnchor then
                local treasuryBillboard = labelAnchor:FindFirstChild("TreasuryLabel")
                if treasuryBillboard then
                    local bg = treasuryBillboard:FindFirstChildOfClass("Frame")
                    if bg then
                        local wealthText = bg:FindFirstChild("WealthText")
                        if wealthText then
                            wealthText.Text = "Treasury: " .. math.floor(nation.wealth) .. "g"
                        end
                    end
                end
            end
        end
    end
end

-- ─── Utility: format number with commas ──────────────────────────────────────

local function formatNumber(n)
    local s = tostring(math.floor(n))
    local result = ""
    local len = #s
    for i = 1, len do
        if i > 1 and (len - i + 1) % 3 == 0 then
            result = result .. ","
        end
        result = result .. s:sub(i, i)
    end
    return result
end

-- ─── Random Market Events ───────────────────────────────────────────────────

local EVENTS = {
    {
        name = "GOLD_RUSH",
        apply = function(nation, logs)
            local bonus = Config.EVENT_GOLD_RUSH_BONUS
            nation.wealth = nation.wealth + bonus
            table.insert(logs, string.format(
                "[EVENT] ★ GOLD RUSH! %s discovers a hidden vein — +%dg windfall!",
                nation.name, bonus
            ))
            return bonus
        end,
    },
    {
        name = "PLAGUE",
        apply = function(nation, logs)
            local loss = math.min(Config.EVENT_PLAGUE_LOSS, nation.wealth * 0.3)
            nation.wealth = math.max(0, nation.wealth - loss)
            table.insert(logs, string.format(
                "[EVENT] ☠ PLAGUE strikes %s! Treasury loses %dg to quarantine costs!",
                nation.name, math.floor(loss)
            ))
            return -math.floor(loss)
        end,
    },
    {
        name = "STORM",
        apply = function(nation, logs)
            if nation.tradeShips > 1 then
                nation.tradeShips = nation.tradeShips - 1
                table.insert(logs, string.format(
                    "[EVENT] ⛈ GREAT STORM! %s loses a trade ship to the tempest! Ships: %d",
                    nation.name, nation.tradeShips
                ))

                -- Play sinking animation on the lost ship
                local shipsFolder = workspace:FindFirstChild("Ships")
                if shipsFolder then
                    local shipName = nation.name .. "_TradeShip_" .. (nation.tradeShips + 1)
                    local shipModel = shipsFolder:FindFirstChild(shipName)
                    if shipModel then
                        playSinking(shipModel)
                    end
                end

                return 0
            else
                local dmg = math.min(80, nation.wealth * 0.15)
                nation.wealth = math.max(0, nation.wealth - dmg)
                table.insert(logs, string.format(
                    "[EVENT] ⛈ STORM batters %s's port — %dg in repairs!",
                    nation.name, math.floor(dmg)
                ))
                return -math.floor(dmg)
            end
        end,
    },
    {
        name = "MARKET_BOOM",
        apply = function(nation, logs)
            local bonus = math.floor(nation.wealth * 0.25)
            nation.wealth = nation.wealth + bonus
            table.insert(logs, string.format(
                "[EVENT] ★ MARKET BOOM! Demand surges for %s's %s — +%dg!",
                nation.name, nation.resource, bonus
            ))
            return bonus
        end,
    },
    {
        name = "MARKET_CRASH",
        apply = function(nation, logs)
            local loss = math.floor(nation.wealth * 0.25)
            nation.wealth = math.max(0, nation.wealth - loss)
            table.insert(logs, string.format(
                "[EVENT] ★ MARKET CRASH! Prices collapse for %s's %s — -%dg!",
                nation.name, nation.resource, loss
            ))
            return -loss
        end,
    },
    {
        name = "MUTINY",
        apply = function(nation, logs)
            if nation.warships > 1 then
                nation.warships = nation.warships - 1
                nation.navyCost = nation.warships * Config.WARSHIP_COST_PER_TICK
                table.insert(logs, string.format(
                    "[EVENT] ⚔ MUTINY aboard %s's fleet! A warship crew defects! Warships: %d",
                    nation.name, nation.warships
                ))
            else
                table.insert(logs, string.format(
                    "[EVENT] ⚔ Mutiny rumours in %s — quelled before spreading.",
                    nation.name
                ))
            end
            return 0
        end,
    },
    {
        name = "TRADE_WIND",
        apply = function(nation, logs)
            if nation.tradeShips < 5 then
                nation.tradeShips = nation.tradeShips + 1
                table.insert(logs, string.format(
                    "[EVENT] ★ TRADE WINDS favour %s! A new merchant vessel joins the fleet! Ships: %d",
                    nation.name, nation.tradeShips
                ))
                return 0
            else
                local bonus = 100
                nation.wealth = nation.wealth + bonus
                table.insert(logs, string.format(
                    "[EVENT] ★ TRADE WINDS bring a foreign merchant to %s — +%dg!",
                    nation.name, bonus
                ))
                return bonus
            end
        end,
    },
}

local function resolveRandomEvents(allNations, logs)
    if math.random() > Config.EVENT_CHANCE_PER_TICK then
        return nil, nil, 0
    end

    local nation = allNations[math.random(1, #allNations)]
    local event  = EVENTS[math.random(1, #EVENTS)]
    local amount = event.apply(nation, logs)
    return nation, event, amount or 0
end

-- ─── Helpers: parse log lines for structured data ───────────────────────────

local function parseDiplomacyLogs(tick, logs)
    for _, msg in ipairs(logs) do
        local lower = msg:lower()
        if lower:find("treaty") then
            local a, b = msg:match("%[DIPLOMACY%] (.+) & (.+) forge")
            if a and b then
                DataCollector.recordEvent(tick, "alliance_formed", a, b, "", 0)
            end
        elseif lower:find("embargo") and lower:find("declares") then
            local a, b = msg:match("%[DIPLOMACY%] (.+) declares a trade EMBARGO on (.+)!")
            if a and b then
                DataCollector.recordEvent(tick, "embargo_declared", a, b, "", 0)
            end
        elseif lower:find("dissolves") then
            local a, b = msg:match("%[DIPLOMACY%] (.+) dissolves alliance with (.+)")
            if a and b then
                DataCollector.recordEvent(tick, "alliance_broken", a, b:match("^(.-)%s*—") or b, "", 0)
            end
        elseif lower:find("lifts embargo") then
            local a, b = msg:match("%[DIPLOMACY%] (.+) lifts embargo on (.+)")
            if a and b then
                DataCollector.recordEvent(tick, "embargo_lifted", a, b:match("^(.-)%s*—") or b, "", 0)
            end
        elseif lower:find("commissions") then
            local a, count = msg:match("%[PRIVATEER%] (.+) commissions (%d+)")
            if a and count then
                DataCollector.recordEvent(tick, "privateer_commissioned", a, "", "", tonumber(count) or 0)
            end
        end
    end
end

local function parsePrivateerLogs(tick, logs)
    for _, msg in ipairs(logs) do
        local attacker, victim, amount = msg:match("%[PRIVATEER%] (.+)'s corsairs intercept (.+)'s merchant fleet for (%d+)g")
        if attacker and victim and amount then
            DataCollector.recordEvent(tick, "privateer_raid", attacker, victim, "", tonumber(amount) or 0)
        end
    end
end

local function parseSabotageLogs(tick, logs)
    for _, msg in ipairs(logs) do
        local lower = msg:lower()
        if lower:find("burn") then
            local attacker, target, cost = msg:match("%[SABOTAGE%] (.+) agents burn (.+)'s dockyard.- %((%d+)g")
            if attacker and target then
                DataCollector.recordEvent(tick, "sabotage_success", attacker, target, "", tonumber(cost) or 0)
            end
        elseif lower:find("uncovered") or lower:find("fails") then
            local attacker, target, cost = msg:match("%[SABOTAGE%] (.+)'s sabotage against (.+) is.- %((%d+)g")
            if attacker and target then
                DataCollector.recordEvent(tick, "sabotage_failed", attacker, target, "", tonumber(cost) or 0)
            end
        end
    end
end

-- ─── Main Simulation Function ─────────────────────────────────────────────────

local function runSimulation(scenario)
    NationState.init(scenario)
    DiplomacySystem.init(NationState.getAllNations())
    DataCollector.beginScenario(scenario)
    print("=== Starting " .. scenario .. " simulation ===")

    local tickLogs = {}
    local allIslandPositions = {}

    for _, nationData in ipairs(Config.NATIONS) do
        allIslandPositions[nationData.id] = nationData.position + Vector3.new(0, 3, 0)
    end

    for tick = 1, Config.MAX_TICKS do
        tickLogs = {}
        table.insert(tickLogs, string.format("[Tick %d / %d] Scenario: %s", tick, Config.MAX_TICKS, scenario))

        local allNations = NationState.getAllNations()

        -- 1. Update economy tiers for all nations
        for _, nation in ipairs(allNations) do
            NationState.updateEconomyTier(nation)
        end

        -- 2. Produce & consume resources
        for _, nation in ipairs(allNations) do
            NationState.produceResources(nation)
            NationState.consumeResources(nation)
        end

        -- 2b. Resource needs influence relations
        -- Nations seek out suppliers of resources they urgently need
        for _, nation in ipairs(allNations) do
            for _, res in ipairs(Config.RAW_RESOURCES) do
                if res ~= nation.resource then
                    local stock = nation.resources[res] or 0

                    -- Find who produces this resource
                    local supplier = nil
                    for _, other in ipairs(allNations) do
                        if other.resource == res then
                            supplier = other
                            break
                        end
                    end

                    if supplier then
                        local diploState = DiplomacySystem.getState(nation.id, supplier.id)

                        if stock < Config.RESOURCE_MIN_NEED then
                            -- Urgently need this resource — warm up to the supplier
                            NationState.changeRelation(nation.id, supplier.id,
                                Config.RELATION_NEED_SUPPLIER_BOOST)

                            table.insert(tickLogs, string.format(
                                "[RESOURCE] ⚠ %s urgently needs %s from %s! (stock: %d/%d) — seeking trade",
                                nation.name, res, supplier.name,
                                math.floor(stock), Config.RESOURCE_MIN_NEED
                            ))

                            -- If embargoed by the supplier we desperately need, relations tank harder
                            if diploState == "embargo" then
                                NationState.changeRelation(nation.id, supplier.id,
                                    Config.RELATION_NEED_EMBARGO_PENALTY)
                                table.insert(tickLogs, string.format(
                                    "[RESOURCE] ✗ %s is embargoed by %s and starving for %s! Relations deteriorating!",
                                    nation.name, supplier.name, res
                                ))
                            end

                        elseif stock < Config.RESOURCE_MIN_NEED * 2 then
                            -- Moderately low — slight warmth to supplier
                            NationState.changeRelation(nation.id, supplier.id, 1)

                        elseif stock >= Config.RESOURCE_MAX_STOCK * 0.9 then
                            -- Saturated — we don't need them as much, no special boost
                            -- But if supplier is also saturated on our resource and hoarding,
                            -- it breeds resentment
                            local supplierStock = supplier.resources[nation.resource] or 0
                            if supplierStock >= Config.RESOURCE_MAX_STOCK * 0.9
                                and diploState ~= "allied" then
                                -- Both saturated, no interdependency = relations drift apart
                                NationState.changeRelation(nation.id, supplier.id, -1)
                            end
                        end
                    end
                end
            end
        end

        -- 3. Animate ships (fire-and-forget)
        local shipsFolder = workspace:FindFirstChild("Ships")
        if shipsFolder then
            for _, nation in ipairs(allNations) do
                for i = 1, nation.tradeShips do
                    local shipName = nation.name .. "_TradeShip_" .. i
                    local shipModel = shipsFolder:FindFirstChild(shipName)
                    if shipModel and shipModel.PrimaryPart and not isAnimating(shipModel) then
                        local otherNations = {}
                        for _, other in ipairs(allNations) do
                            if other.id ~= nation.id then
                                table.insert(otherNations, other)
                            end
                        end
                        if #otherNations > 0 then
                            local targetNation = otherNations[math.random(1, #otherNations)]

                            -- Update cargo color based on what we're exporting
                            updateShipCargoColor(shipModel, nation.resource)

                            local fromPos = shipModel.PrimaryPart.Position
                            local toPos = allIslandPositions[targetNation.id]
                            local distance = (toPos - fromPos).Magnitude
                            local travelTime = math.max(2, distance / Config.SHIP_SPEED)
                            markAnimating(shipModel, true)
                            task.spawn(function()
                                local anim = animateShip(shipModel, fromPos, toPos, travelTime)
                                if anim then
                                    anim.Completed:Wait()
                                    local returnPos = allIslandPositions[nation.id]
                                    local returnAnim = animateShip(shipModel, toPos, returnPos, travelTime)
                                    if returnAnim then returnAnim.Completed:Wait() end
                                end
                                markAnimating(shipModel, false)
                            end)
                        end
                    end
                end

                for i = 1, nation.warships do
                    local shipName = nation.name .. "_WarShip_" .. i
                    local shipModel = shipsFolder:FindFirstChild(shipName)
                    if shipModel and shipModel.PrimaryPart and not isAnimating(shipModel) then
                        local fromPos = shipModel.PrimaryPart.Position
                        local homePos = allIslandPositions[nation.id]
                        local patrolOffset = Vector3.new(
                            (math.random() - 0.5) * 80,
                            0,
                            (math.random() - 0.5) * 80
                        )
                        local toPos = homePos + patrolOffset
                        local distance = (toPos - fromPos).Magnitude
                        local travelTime = math.max(1.5, distance / Config.SHIP_SPEED)
                        markAnimating(shipModel, true)
                        task.spawn(function()
                            local anim = animateShip(shipModel, fromPos, toPos, travelTime)
                            if anim then anim.Completed:Wait() end
                            markAnimating(shipModel, false)
                        end)
                    end
                end
            end
        end

        -- 3b. Random market events
        local eventLogs = {}
        local eventNation, eventInfo, eventAmount = resolveRandomEvents(allNations, eventLogs)
        for _, msg in ipairs(eventLogs) do
            table.insert(tickLogs, msg)
            print(msg)
        end
        if eventNation and eventInfo then
            DataCollector.recordEvent(tick, "random_event", eventNation.name, "",
                eventInfo.name, eventAmount)
        end

        -- 4. Tariff decisions (AI) — now relationship-aware
        for _, nation in ipairs(allNations) do
            TradeSystem.evaluateTariffPolicy(nation, allNations, tick, NationState, scenario)
        end
        NationState.tickRetaliationCountdowns()

        -- 4b. Diplomatic decisions — now relationship-driven
        local diplomacyLogs = {}
        if scenario == Config.SCENARIOS.MERCANTILIST then
            for _, nation in ipairs(allNations) do
                DiplomacySystem.evaluateDiplomacy(nation, allNations, tick, diplomacyLogs, NationState)
            end
            parseDiplomacyLogs(tick, diplomacyLogs)
            for _, msg in ipairs(diplomacyLogs) do
                table.insert(tickLogs, msg)
                print(msg)
            end
        end

        -- 5. Calculate economics with resource-based trade
        local exportResults  = {}
        local importResults  = {}
        local navyCostResults = {}

        for _, nation in ipairs(allNations) do
            local exports, breakdown, tradeDetails = TradeSystem.calculateExports(
                nation, allNations, scenario,
                DiplomacySystem.getState,
                NationState.getRelation
            )
            local imports  = TradeSystem.calculateImports(nation, exports, scenario)
            local navyCost = NavalSystem.calculateNavalCost(nation, scenario)

            exportResults[nation.id]   = exports
            importResults[nation.id]   = imports
            navyCostResults[nation.id] = navyCost

            -- Successful trade improves relations
            -- Extra boost when delivering urgently needed resources
            if tradeDetails then
                for partnerId, resources in pairs(tradeDetails) do
                    if #resources > 0 then
                        NationState.changeRelation(nation.id, partnerId, Config.RELATION_TRADE_BOOST)

                        -- Check if we delivered a resource the partner urgently needed
                        local partner = NationState.getNation(partnerId)
                        if partner then
                            for _, deliveredRes in ipairs(resources) do
                                if deliveredRes ~= "ManufacturedGoods" and deliveredRes ~= "Technology" then
                                    if partner.resources[deliveredRes]
                                        and partner.resources[deliveredRes] < Config.RESOURCE_MIN_NEED * 2 then
                                        -- We supplied something they really needed!
                                        NationState.changeRelation(nation.id, partnerId,
                                            Config.RELATION_NEED_FULFILLED_BOOST)
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end

        -- 6. Resolve plunder — with explosion animations
        local plunderGainedMap = {}
        local plunderLostMap   = {}
        local plunderLog = NavalSystem.resolvePlunder(allNations, scenario)
        for key, amount in pairs(plunderLog) do
            if type(key) == "number" then
                plunderGainedMap[key] = (plunderGainedMap[key] or 0) + amount
                local plunderer = NationState.getNation(key)
                if plunderer and amount > 0 then
                    local logMsg = string.format(
                        "[PLUNDER] %s gained %dg from raids!",
                        plunderer.name, math.floor(amount)
                    )
                    table.insert(tickLogs, logMsg)
                    print(logMsg)

                    -- Play explosion at a random point between the two nations
                    -- and damage relations
                    for _, victim in ipairs(allNations) do
                        if victim.id ~= key then
                            local victimLost = plunderLog["lost_" .. victim.id]
                            if victimLost and victimLost > 0 then
                                -- Explosion animation at midpoint
                                local attackerPos = allIslandPositions[key]
                                local victimPos = allIslandPositions[victim.id]
                                local midPoint = (attackerPos + victimPos) / 2
                                    + Vector3.new((math.random() - 0.5) * 30, 0, (math.random() - 0.5) * 30)
                                playExplosion(midPoint)

                                -- Raids severely damage relations
                                NationState.changeRelation(key, victim.id, Config.RELATION_RAID_PENALTY)
                            end
                        end
                    end
                end
            elseif type(key) == "string" and key:sub(1, 5) == "lost_" then
                local victimId = tonumber(key:sub(6))
                if victimId then
                    plunderLostMap[victimId] = (plunderLostMap[victimId] or 0) + amount
                end
            end
        end

        -- Record plunder events
        for nationId, gained in pairs(plunderGainedMap) do
            local n = NationState.getNation(nationId)
            if n and gained > 0 then
                DataCollector.recordEvent(tick, "plunder", n.name, "", "", gained)
            end
        end

        -- 6b. Resolve privateers
        local privateerLogs = {}
        DiplomacySystem.resolvePrivateers(allNations, scenario, privateerLogs)
        parsePrivateerLogs(tick, privateerLogs)
        for _, msg in ipairs(privateerLogs) do
            table.insert(tickLogs, msg)
            print(msg)
        end

        -- 6c. Harbour sabotage — now relationship-driven
        local sabotageLogs = {}
        DiplomacySystem.resolveSabotage(allNations, scenario, sabotageLogs, NationState)
        parseSabotageLogs(tick, sabotageLogs)
        for _, msg in ipairs(sabotageLogs) do
            table.insert(tickLogs, msg)
            print(msg)
        end

        -- 7. Update navy sizes (arms race)
        for _, nation in ipairs(allNations) do
            NavalSystem.updateNavySize(nation, allNations, tick, scenario)
        end

        -- 7b. Relationship maintenance: alliance boosts, embargo drains, decay
        for _, nation in ipairs(allNations) do
            for _, other in ipairs(allNations) do
                if other.id > nation.id then
                    local state = DiplomacySystem.getState(nation.id, other.id)
                    if state == "allied" then
                        NationState.changeRelation(nation.id, other.id, Config.RELATION_ALLIANCE_BOOST)
                    elseif state == "embargo" then
                        NationState.changeRelation(nation.id, other.id, Config.RELATION_EMBARGO_DRAIN)
                    end
                end
            end
        end
        NationState.decayRelations()

        -- 8. Apply wealth changes + record tick data
        for _, nation in ipairs(allNations) do
            local exports  = exportResults[nation.id]
            local imports  = importResults[nation.id]
            local navyCost = navyCostResults[nation.id]
            local plunder  = nation.plunderGained or 0

            local delta = exports - imports + plunder - navyCost
            NationState.updateWealth(nation.id, delta)
            NationState.recordTickData(nation.id, exports, imports, plunder, navyCost)

            local trend = ""
            if delta > 50 then trend = " ▲"
            elseif delta > 0 then trend = " △"
            elseif delta < -50 then trend = " ▼"
            elseif delta < 0 then trend = " ▽"
            end
            local balanceSign = delta >= 0 and "+" or ""

            -- Economy tier display
            local tierStr = "RAW"
            if nation.economyTier == Config.ECONOMY_TIER.MANUFACTURE then tierStr = "MFG" end
            if nation.economyTier == Config.ECONOMY_TIER.TECHNOLOGY then tierStr = "TECH" end

            table.insert(tickLogs, string.format(
                "[%s] [%s] Earned %dg — Spent %dg — Navy %dg — Raided %dg → %s%dg net%s | Treasury: %dg",
                nation.name, tierStr,
                math.floor(exports), math.floor(imports),
                math.floor(navyCost), math.floor(plunder),
                balanceSign, math.floor(delta), trend,
                math.floor(nation.wealth)
            ))
        end

        -- 8.5 Apply degradation effects
        local degradeLogs = {}
        for _, nation in ipairs(allNations) do
            DegradationSystem.applyDegradation(nation, scenario, degradeLogs)
            DegradationSystem.updateIslandVisuals(nation)
        end
        for _, msg in ipairs(degradeLogs) do
            table.insert(tickLogs, msg)
        end

        -- 8.6 Record tick snapshot
        for _, nation in ipairs(allNations) do
            local tariffCount = 0
            if nation.tariffs then
                for _, active in pairs(nation.tariffs) do
                    if active then tariffCount = tariffCount + 1 end
                end
            end

            local allianceCount, embargoCount = 0, 0
            for _, other in ipairs(allNations) do
                if other.id ~= nation.id then
                    local st = DiplomacySystem.getState(nation.id, other.id)
                    if st == "allied" then allianceCount = allianceCount + 1 end
                    if st == "embargo" then embargoCount = embargoCount + 1 end
                end
            end

            DataCollector.recordTick(tick, nation.id, {
                wealth            = nation.wealth,
                wealth_delta      = exportResults[nation.id] - importResults[nation.id]
                                  + (nation.plunderGained or 0) - navyCostResults[nation.id],
                exports           = exportResults[nation.id],
                imports           = importResults[nation.id],
                plunder_gained    = plunderGainedMap[nation.id] or 0,
                plunder_lost      = plunderLostMap[nation.id] or 0,
                navy_cost         = navyCostResults[nation.id],
                trade_ships       = nation.tradeShips,
                warships          = nation.warships,
                degradation_level = nation.degradationLevel or "healthy",
                tariff_count      = tariffCount,
                alliance_count    = allianceCount,
                embargo_count     = embargoCount,
                privateer_count   = DiplomacySystem.getPrivateers(nation.id),
                economy_tier      = nation.economyTier or 1,
            })
        end

        -- 9. Update BillboardGuis
        updateTreasuryLabels()

        -- 10. Advance tick
        NationState.advanceTick()

        -- 11. Fire WealthUpdated RemoteEvent
        local summary     = NationState.getSummary()
        local diploData   = DiplomacySystem.getSummary(allNations)
        for _, ns in ipairs(summary.nations) do
            local d = diploData[ns.id]
            if d then
                ns.privateers          = d.privateers
                ns.diplomaticRelations = d.relations
            end
        end
        summary.diploData = diploData
        wealthUpdatedEvent:FireAllClients(summary)

        updateTradeRouteVisuals(allNations)

        -- 12. Fire TickLog
        local tickLogString = table.concat(tickLogs, "\n")
        tickLogEvent:FireAllClients(tickLogString)

        print(string.format("[GameManager] Tick %d complete | Global Wealth: %sg",
            tick, formatNumber(NationState.getGlobalWealth())))

        -- 13. Wait for next tick
        task.wait(Config.TICK_DURATION)
    end

    -- Build final results
    local finalNations = NationState.getAllNations()
    local globalWealth = NationState.getGlobalWealth()

    local winnerNation = finalNations[1]
    for _, nation in ipairs(finalNations) do
        if nation.wealth > winnerNation.wealth then
            winnerNation = nation
        end
    end

    local finalResults = {
        scenario     = scenario,
        globalWealth = globalWealth,
        winnerName   = winnerNation.name,
        winnerWealth = winnerNation.wealth,
        nations      = {},
    }
    for _, nation in ipairs(finalNations) do
        table.insert(finalResults.nations, {
            id     = nation.id,
            name   = nation.name,
            wealth = nation.wealth,
        })
    end

    simEndedEvent:FireAllClients(finalResults)

    print(string.format("=== %s Simulation Complete ===", scenario))
    print(string.format("Global Wealth: %sg", formatNumber(globalWealth)))
    for _, nation in ipairs(finalNations) do
        print(string.format("  %s: %sg", nation.name, formatNumber(nation.wealth)))
    end

    return finalResults
end

-- ─── StartSimulation Remote Handler ──────────────────────────────────────────

startSimulationEvent.OnServerEvent:Connect(function(player, scenarioName)
    print(string.format("[GameManager] Player '%s' requested simulation restart: %s", player.Name, tostring(scenarioName)))
    task.spawn(function()
        local result = runSimulation(scenarioName or Config.SCENARIOS.MERCANTILIST)
        print("[GameManager] Player-triggered simulation complete.")
    end)
end)

-- ─── Auto-run Sequence ────────────────────────────────────────────────────────

DataCollector.init()

local mercResult = runSimulation(Config.SCENARIOS.MERCANTILIST)

task.wait(5)

local freeResult = runSimulation(Config.SCENARIOS.FREE_TRADE)

task.wait(2)

local mercWealth  = mercResult.globalWealth
local freeWealth  = freeResult.globalWealth
local percentDiff = 0
if mercWealth > 0 then
    percentDiff = math.floor(((freeWealth - mercWealth) / mercWealth) * 100)
end

print(string.format(
    "[GameManager] Comparison: Mercantilist total wealth = %sg | Free Trade total wealth = %sg | Difference = %d%%",
    formatNumber(mercWealth), formatNumber(freeWealth), percentDiff
))

comparisonEvent:FireAllClients(mercResult, freeResult)

-- ─── Export Data for Scientific Analysis ────────────────────────────────────

local csvData    = DataCollector.getCSV()
local eventCsv   = DataCollector.getEventLog()
local aggregates = DataCollector.computeAggregates()

dataExportEvent:FireAllClients(csvData, eventCsv, aggregates)

print("\n=== TICK DATA CSV ===")
for line in csvData:gmatch("[^\n]+") do
    print(line)
end
print("\n=== EVENT LOG CSV ===")
for line in eventCsv:gmatch("[^\n]+") do
    print(line)
end
print("\n=== AGGREGATE STATISTICS ===")
for line in aggregates:gmatch("[^\n]+") do
    print(line)
end

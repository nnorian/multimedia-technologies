-- NationState.lua
-- ModuleScript: manages in-memory state for all nations
-- Place in ReplicatedStorage

local RS = game:GetService("ReplicatedStorage")
local Config = require(RS:WaitForChild("GameConfig"))

local NationState = {}

-- Private state
local _nations = {}               -- keyed by nationId
local _nationList = {}            -- ordered array
local _globalWealthHistory = {}
local _currentTick = 0
local _scenario = nil
local _retaliationCountdown = {}  -- keyed by nationId -> { [aggressorId] = ticksRemaining }
local _tariffs = {}               -- _tariffs[fromId][targetId] = true/false
local _relations = {}             -- _relations[id1][id2] = score (0-100)

-- ─── Initialization ──────────────────────────────────────────────────────────

function NationState.init(scenario)
    _nations = {}
    _nationList = {}
    _globalWealthHistory = {}
    _currentTick = 0
    _scenario = scenario
    _retaliationCountdown = {}
    _tariffs = {}
    _relations = {}

    for _, nationData in ipairs(Config.NATIONS) do
        -- Build resource inventory: start with some stock of each resource
        local resources = {}
        for _, res in ipairs(Config.RAW_RESOURCES) do
            resources[res] = Config.RESOURCE_START_STOCK
        end
        -- Own resource starts higher (they produce it)
        resources[nationData.resource] = Config.RESOURCE_MAX_STOCK * 0.7

        local nation = {
            id             = nationData.id,
            name           = nationData.name,
            color          = nationData.color,
            resource       = nationData.resource,  -- primary raw resource produced
            position       = nationData.position,
            wealth         = Config.INITIAL_WEALTH,
            tradeShips     = Config.INITIAL_TRADE_SHIPS,
            warships       = Config.INITIAL_WARSHIPS,
            navyCost       = Config.INITIAL_WARSHIPS * Config.WARSHIP_COST_PER_TICK,
            tariffs        = {},
            exportEarnings = 0,
            importSpending = 0,
            plunderGained  = 0,
            tradeBalance             = 0,
            consecutiveNegativeTicks = 0,
            degradationLevel         = "healthy",
            tickHistory              = {},

            -- New: resource system
            resources      = resources,       -- { Meat=N, Logs=N, Ore=N, Herbs=N }
            economyTier    = Config.ECONOMY_TIER.RAW,  -- 1=raw, 2=manufacture, 3=technology
            -- Track what cargo each trade ship is currently carrying (for visuals)
            shipCargo      = {},  -- shipCargo[shipIndex] = resourceName or "ManufacturedGoods" or "Technology"
        }
        _nations[nation.id] = nation
        table.insert(_nationList, nation)

        _retaliationCountdown[nation.id] = {}
        _tariffs[nation.id] = {}
        _relations[nation.id] = {}
    end

    -- Initialize bilateral relations
    for _, n in ipairs(_nationList) do
        for _, m in ipairs(_nationList) do
            if m.id ~= n.id then
                _relations[n.id][m.id] = Config.RELATION_INITIAL
            end
        end
    end
end

-- ─── Getters ─────────────────────────────────────────────────────────────────

function NationState.getNation(id)
    return _nations[id]
end

function NationState.getAllNations()
    return _nationList
end

function NationState.getGlobalWealth()
    local total = 0
    for _, nation in ipairs(_nationList) do
        total = total + nation.wealth
    end
    return total
end

function NationState.getGlobalWealthHistory()
    return _globalWealthHistory
end

function NationState.getCurrentTick()
    return _currentTick
end

function NationState.getScenario()
    return _scenario
end

-- ─── Relationship System ────────────────────────────────────────────────────

function NationState.getRelation(id1, id2)
    if not _relations[id1] then return Config.RELATION_INITIAL end
    return _relations[id1][id2] or Config.RELATION_INITIAL
end

function NationState.changeRelation(id1, id2, delta)
    if not _relations[id1] then _relations[id1] = {} end
    if not _relations[id2] then _relations[id2] = {} end
    local current1 = _relations[id1][id2] or Config.RELATION_INITIAL
    local current2 = _relations[id2][id1] or Config.RELATION_INITIAL
    -- Symmetric change
    _relations[id1][id2] = math.clamp(current1 + delta, 0, 100)
    _relations[id2][id1] = math.clamp(current2 + delta, 0, 100)
end

function NationState.setRelation(id1, id2, value)
    if not _relations[id1] then _relations[id1] = {} end
    if not _relations[id2] then _relations[id2] = {} end
    _relations[id1][id2] = math.clamp(value, 0, 100)
    _relations[id2][id1] = math.clamp(value, 0, 100)
end

-- Decay relations toward neutral each tick
function NationState.decayRelations()
    for _, n in ipairs(_nationList) do
        for _, m in ipairs(_nationList) do
            if m.id > n.id then
                local current = _relations[n.id][m.id] or Config.RELATION_INITIAL
                if current > Config.RELATION_INITIAL then
                    NationState.changeRelation(n.id, m.id, -Config.RELATION_DECAY_RATE)
                elseif current < Config.RELATION_INITIAL then
                    NationState.changeRelation(n.id, m.id, Config.RELATION_DECAY_RATE)
                end
            end
        end
    end
end

function NationState.getRelationsSummary()
    local result = {}
    for _, n in ipairs(_nationList) do
        result[n.id] = {}
        for _, m in ipairs(_nationList) do
            if m.id ~= n.id then
                result[n.id][tostring(m.id)] = _relations[n.id][m.id] or Config.RELATION_INITIAL
            end
        end
    end
    return result
end

-- ─── Economy Tier ───────────────────────────────────────────────────────────

function NationState.updateEconomyTier(nation)
    if nation.wealth >= Config.TIER_THRESHOLD_TECHNOLOGY then
        nation.economyTier = Config.ECONOMY_TIER.TECHNOLOGY
    elseif nation.wealth >= Config.TIER_THRESHOLD_MANUFACTURE then
        nation.economyTier = Config.ECONOMY_TIER.MANUFACTURE
    else
        nation.economyTier = Config.ECONOMY_TIER.RAW
    end
end

-- ─── Resource Management ────────────────────────────────────────────────────

-- Produce own resource each tick
function NationState.produceResources(nation)
    nation.resources[nation.resource] = math.min(
        Config.RESOURCE_MAX_STOCK,
        (nation.resources[nation.resource] or 0) + Config.RESOURCE_OWN_PRODUCTION
    )
end

-- Consume resources each tick
function NationState.consumeResources(nation)
    for _, res in ipairs(Config.RAW_RESOURCES) do
        nation.resources[res] = math.max(0, (nation.resources[res] or 0) - Config.RESOURCE_CONSUMPTION)
    end
end

-- Check if nation needs a specific resource (below saturation)
function NationState.needsResource(nation, resourceName)
    local stock = nation.resources[resourceName] or 0
    return stock < Config.RESOURCE_MAX_STOCK
end

-- Check if nation urgently needs a resource (below minimum)
function NationState.urgentlyNeedsResource(nation, resourceName)
    local stock = nation.resources[resourceName] or 0
    return stock < Config.RESOURCE_MIN_NEED
end

-- Add resource to nation's stockpile
function NationState.addResource(nation, resourceName, amount)
    nation.resources[resourceName] = math.min(
        Config.RESOURCE_MAX_STOCK,
        (nation.resources[resourceName] or 0) + amount
    )
end

-- ─── Wealth Management ───────────────────────────────────────────────────────

function NationState.updateWealth(nationId, delta)
    local nation = _nations[nationId]
    if not nation then
        warn("[NationState] updateWealth: nation not found for id " .. tostring(nationId))
        return
    end
    nation.wealth = math.max(0, nation.wealth + delta)
end

-- ─── Tick Data Recording ─────────────────────────────────────────────────────

function NationState.recordTickData(nationId, exports, imports, plunder, navyCost)
    local nation = _nations[nationId]
    if not nation then
        warn("[NationState] recordTickData: nation not found for id " .. tostring(nationId))
        return
    end

    nation.exportEarnings = exports
    nation.importSpending = imports
    nation.plunderGained  = plunder
    nation.navyCost       = navyCost
    nation.tradeBalance   = exports - imports

    table.insert(nation.tickHistory, {
        tick      = _currentTick,
        exports   = exports,
        imports   = imports,
        plunder   = plunder,
        navyCost  = navyCost,
        wealth    = nation.wealth,
    })
end

-- ─── Tick Advancement ────────────────────────────────────────────────────────

function NationState.advanceTick()
    _currentTick = _currentTick + 1
    local globalWealth = NationState.getGlobalWealth()
    table.insert(_globalWealthHistory, {
        tick   = _currentTick,
        wealth = globalWealth,
    })
end

-- ─── Tariff Management ───────────────────────────────────────────────────────

function NationState.setTariff(fromId, targetId, enabled)
    local nation = _nations[fromId]
    if not nation then
        warn("[NationState] setTariff: nation not found for id " .. tostring(fromId))
        return
    end

    if _tariffs[fromId] == nil then
        _tariffs[fromId] = {}
    end

    local wasAlreadySet = _tariffs[fromId][targetId] == true
    _tariffs[fromId][targetId] = enabled or false
    nation.tariffs[targetId] = enabled or false

    if enabled and not wasAlreadySet then
        local targetNation = _nations[targetId]
        if targetNation then
            if _retaliationCountdown[targetId] == nil then
                _retaliationCountdown[targetId] = {}
            end
            _retaliationCountdown[targetId][fromId] = Config.RETALIATION_DELAY
        end
        -- Tariffs damage relations
        NationState.changeRelation(fromId, targetId, -8)
    end
end

function NationState.hasTariff(fromId, targetId)
    if _tariffs[fromId] == nil then
        return false
    end
    return _tariffs[fromId][targetId] == true
end

function NationState.tickRetaliationCountdowns()
    for retaliatorId, countdowns in pairs(_retaliationCountdown) do
        local toRemove = {}
        for aggressorId, remaining in pairs(countdowns) do
            local newRemaining = remaining - 1
            if newRemaining <= 0 then
                local retaliator = _nations[retaliatorId]
                local aggressor  = _nations[aggressorId]
                if retaliator and aggressor then
                    if not NationState.hasTariff(retaliatorId, aggressorId) then
                        if _tariffs[retaliatorId] == nil then
                            _tariffs[retaliatorId] = {}
                        end
                        _tariffs[retaliatorId][aggressorId] = true
                        retaliator.tariffs[aggressorId] = true
                        print(string.format(
                            "[NationState] %s retaliates against %s with tariffs!",
                            retaliator.name, aggressor.name
                        ))
                    end
                end
                table.insert(toRemove, aggressorId)
            else
                countdowns[aggressorId] = newRemaining
            end
        end
        for _, aggressorId in ipairs(toRemove) do
            countdowns[aggressorId] = nil
        end
    end
end

-- ─── Summary ─────────────────────────────────────────────────────────────────

function NationState.getSummary()
    local summary = {
        tick              = _currentTick,
        scenario          = _scenario,
        globalWealth      = NationState.getGlobalWealth(),
        globalWealthHistory = _globalWealthHistory,
        nations           = {},
        relations         = NationState.getRelationsSummary(),
    }

    for _, nation in ipairs(_nationList) do
        local tariffList = {}
        for targetId, active in pairs(nation.tariffs) do
            if active then
                table.insert(tariffList, targetId)
            end
        end

        -- Serialize resources
        local resSerialized = {}
        for _, res in ipairs(Config.RAW_RESOURCES) do
            resSerialized[res] = math.floor(nation.resources[res] or 0)
        end

        table.insert(summary.nations, {
            id             = nation.id,
            name           = nation.name,
            colorR         = nation.color.R,
            colorG         = nation.color.G,
            colorB         = nation.color.B,
            resource       = nation.resource,
            wealth         = nation.wealth,
            tradeShips     = nation.tradeShips,
            warships       = nation.warships,
            navyCost       = nation.navyCost,
            exportEarnings = nation.exportEarnings,
            importSpending = nation.importSpending,
            plunderGained  = nation.plunderGained,
            tradeBalance             = nation.tradeBalance,
            activeTariffs            = tariffList,
            degradationLevel         = nation.degradationLevel or "healthy",
            consecutiveNegativeTicks = nation.consecutiveNegativeTicks or 0,
            -- New fields
            economyTier    = nation.economyTier or 1,
            resources      = resSerialized,
        })
    end

    return summary
end

return NationState

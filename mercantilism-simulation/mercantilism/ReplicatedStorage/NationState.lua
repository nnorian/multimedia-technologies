-- NationState.lua
-- ModuleScript: manages in-memory state for all nations
-- Place in ReplicatedStorage
-- NOTE: This module is intended for server-side use only.
-- Clients receive state updates via RemoteEvents.

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

-- ─── Initialization ──────────────────────────────────────────────────────────

function NationState.init(scenario)
    _nations = {}
    _nationList = {}
    _globalWealthHistory = {}
    _currentTick = 0
    _scenario = scenario
    _retaliationCountdown = {}
    _tariffs = {}

    for _, nationData in ipairs(Config.NATIONS) do
        local nation = {
            id             = nationData.id,
            name           = nationData.name,
            color          = nationData.color,
            resource       = nationData.resource,
            position       = nationData.position,
            wealth         = Config.INITIAL_WEALTH,
            tradeShips     = Config.INITIAL_TRADE_SHIPS,
            warships       = Config.INITIAL_WARSHIPS,
            navyCost       = Config.INITIAL_WARSHIPS * Config.WARSHIP_COST_PER_TICK,
            tariffs        = {},       -- tariffs[targetId] = true means this nation imposes tariff on targetId
            exportEarnings = 0,
            importSpending = 0,
            plunderGained  = 0,
            tradeBalance             = 0,
            consecutiveNegativeTicks = 0,    -- ticks in a row with negative trade balance
            degradationLevel         = "healthy",
            tickHistory              = {},   -- array of { tick, exports, imports, plunder, navyCost, wealth }
        }
        _nations[nation.id] = nation
        table.insert(_nationList, nation)

        _retaliationCountdown[nation.id] = {}
        _tariffs[nation.id] = {}
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

-- setTariff(fromId, targetId, enabled)
-- If enabled = true, starts a retaliation countdown for the target nation.
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

    -- Start retaliation countdown for the targeted nation (they may retaliate)
    if enabled and not wasAlreadySet then
        local targetNation = _nations[targetId]
        if targetNation then
            if _retaliationCountdown[targetId] == nil then
                _retaliationCountdown[targetId] = {}
            end
            -- The target will retaliate against fromId after RETALIATION_DELAY ticks
            _retaliationCountdown[targetId][fromId] = Config.RETALIATION_DELAY
        end
    end
end

-- hasTariff(fromId, targetId) → bool
-- Returns true if nation fromId has imposed a tariff on targetId.
function NationState.hasTariff(fromId, targetId)
    if _tariffs[fromId] == nil then
        return false
    end
    return _tariffs[fromId][targetId] == true
end

-- tickRetaliationCountdowns()
-- Decrements counters; when a countdown reaches 0,
-- the nation retaliates by setting tariffs on whoever tariffed them.
function NationState.tickRetaliationCountdowns()
    for retaliatorId, countdowns in pairs(_retaliationCountdown) do
        local toRemove = {}
        for aggressorId, remaining in pairs(countdowns) do
            local newRemaining = remaining - 1
            if newRemaining <= 0 then
                -- Retaliate: set tariff on the aggressor
                local retaliator = _nations[retaliatorId]
                local aggressor  = _nations[aggressorId]
                if retaliator and aggressor then
                    -- Only retaliate if not already tariffing them
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

-- getSummary() → structured table of all nation data suitable for RemoteEvent firing
function NationState.getSummary()
    local summary = {
        tick              = _currentTick,
        scenario          = _scenario,
        globalWealth      = NationState.getGlobalWealth(),
        globalWealthHistory = _globalWealthHistory,
        nations           = {},
    }

    for _, nation in ipairs(_nationList) do
        -- Serialize Color3 and Vector3 as plain tables for RemoteEvent compatibility
        local tariffList = {}
        for targetId, active in pairs(nation.tariffs) do
            if active then
                table.insert(tariffList, targetId)
            end
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
        })
    end

    return summary
end

return NationState

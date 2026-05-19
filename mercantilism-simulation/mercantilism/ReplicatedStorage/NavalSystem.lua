-- NavalSystem.lua
-- ModuleScript: naval combat, plunder, and arms race calculations
-- Place in ReplicatedStorage

local RS = game:GetService("ReplicatedStorage")
local Config = require(RS:WaitForChild("GameConfig"))

local NavalSystem = {}

-- ─── Plunder Resolution ───────────────────────────────────────────────────────

-- resolvePlunder(nations, scenario)
-- Applies plunder directly to the nations table entries.
-- Returns plunderResults: table { [victimId] = totalStolen, [plunderId/attackerId] = totalGained }
-- Gains and losses are both tracked in the same table with separate keys.
function NavalSystem.resolvePlunder(nations, scenario, getDiploState)
    -- Skip plunder in free trade scenario
    if scenario == Config.SCENARIOS.FREE_TRADE then
        return {}
    end

    local plunderResults = {}
    local plunderLog = {}

    for _, nation in ipairs(nations) do
        plunderLog[nation.id] = { gained = 0, lost = 0 }
    end

    -- For each attacker nation, attempt to plunder each rival (skip allies)
    for _, attacker in ipairs(nations) do
        if attacker.warships > 0 then
            for _, victim in ipairs(nations) do
                if victim.id ~= attacker.id then
                    -- Skip allied nations — warships don't raid allies
                    local diploState = getDiploState and getDiploState(attacker.id, victim.id) or "neutral"
                    if diploState ~= "allied" then
                        for _ = 1, attacker.warships do
                            if victim.tradeShips > 0 then
                                local roll = math.random()
                                if roll <= Config.PLUNDER_SUCCESS_RATE then
                                    local amount = math.min(Config.PLUNDER_AMOUNT, victim.wealth)
                                    if amount > 0 then
                                        victim.wealth  = math.max(0, victim.wealth - amount)
                                        attacker.wealth = attacker.wealth + amount
                                        plunderLog[victim.id].lost    = plunderLog[victim.id].lost + amount
                                        plunderLog[attacker.id].gained = plunderLog[attacker.id].gained + amount
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- Update plunderGained field on each nation and build results table
    for _, nation in ipairs(nations) do
        local log = plunderLog[nation.id]
        nation.plunderGained = log.gained

        -- Flatten into the return format: victimId → totalStolen, attackerId → totalGained
        -- (We use positive numbers for both; callers distinguish by context)
        if log.gained > 0 then
            plunderResults[nation.id] = plunderResults[nation.id] or 0
            plunderResults[nation.id] = plunderResults[nation.id] + log.gained
        end
        if log.lost > 0 then
            -- Store losses as negative to differentiate
            local lostKey = "lost_" .. nation.id
            plunderResults[lostKey] = log.lost
        end
    end

    return plunderResults
end

-- ─── Naval Cost Calculation ───────────────────────────────────────────────────

-- calculateNavalCost(nation, scenario) → number
function NavalSystem.calculateNavalCost(nation, scenario)
    if scenario == Config.SCENARIOS.FREE_TRADE then
        -- In free trade, only baseline maintenance applies
        return Config.ARMS_RACE_BETA
    end

    -- Mercantilist: full warship maintenance
    return nation.warships * Config.WARSHIP_COST_PER_TICK
end

-- ─── Navy Size Update (Arms Race) ────────────────────────────────────────────

-- updateNavySize(nation, allNations, currentTick, scenario)
-- Arms race reaction: respond to rivals' naval buildup.
function NavalSystem.updateNavySize(nation, allNations, currentTick, scenario)
    -- Only act in mercantilist scenario
    if scenario ~= Config.SCENARIOS.MERCANTILIST then
        return
    end

    -- Only act after tick 1
    if currentTick <= 1 then
        return
    end

    -- Find the maximum rival naval cost
    local maxRivalCost = 0
    for _, other in ipairs(allNations) do
        if other.id ~= nation.id then
            local rivalCost = other.warships * Config.WARSHIP_COST_PER_TICK
            if rivalCost > maxRivalCost then
                maxRivalCost = rivalCost
            end
        end
    end

    -- Arms race reaction function: C_i(t+1) = alpha * C_j(t) + beta
    local targetCost = Config.ARMS_RACE_ALPHA * maxRivalCost + Config.ARMS_RACE_BETA

    -- Convert target cost to warship count
    local targetWarships = math.floor(targetCost / Config.WARSHIP_COST_PER_TICK)
    targetWarships = math.max(1, math.min(Config.MAX_WARSHIPS, targetWarships))

    -- Only build if we can afford it (require 10-tick buffer, not 5)
    local canAfford = nation.wealth > (Config.WARSHIP_COST_PER_TICK * 10)
    if targetWarships > nation.warships and canAfford then
        nation.warships = nation.warships + 1
        print(string.format(
            "[NavalSystem] %s builds a new warship (now %d warships). Arms race escalation.",
            nation.name, nation.warships
        ))
    elseif targetWarships < nation.warships then
        -- Voluntary disarmament when threat recedes (alpha < 1 makes this reachable)
        nation.warships = math.max(1, nation.warships - 1)
        print(string.format(
            "[NavalSystem] %s decommissions a warship (now %d). Threat has receded.",
            nation.name, nation.warships
        ))
    end

    -- Update navy cost
    nation.navyCost = nation.warships * Config.WARSHIP_COST_PER_TICK
end

return NavalSystem

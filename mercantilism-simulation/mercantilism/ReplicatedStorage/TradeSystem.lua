-- TradeSystem.lua
-- ModuleScript: pure trade calculations
-- Place in ReplicatedStorage

local RS                = game:GetService("ReplicatedStorage")
local Config            = require(RS:WaitForChild("GameConfig"))
local DegradationSystem = require(RS:WaitForChild("DegradationSystem"))

local TradeSystem = {}

-- ─── Resource Demand Matrix ───────────────────────────────────────────────────
-- resourceDemand[resource] = { list of resources that demand it }
-- Equivalently: which producing nations want each resource?
--   Iron   ← demanded by nations producing Grain, Wood
--   Grain  ← demanded by nations producing Spices, Iron
--   Spices ← demanded by nations producing Wood, Grain
--   Wood   ← demanded by nations producing Iron, Spices

-- demandedBy[resource] = set of producer-resources that want it
local demandedBy = {
    Iron   = { Grain = true, Wood = true },
    Grain  = { Spices = true, Iron = true },
    Spices = { Wood = true, Grain = true },
    Wood   = { Iron = true, Spices = true },
}

-- Returns true if `buyerResource` (the buyer nation's primary resource)
-- means that buyer nation demands `sellerResource`.
local function isResourceDemanded(sellerResource, buyerResource)
    local demanders = demandedBy[sellerResource]
    if not demanders then return false end
    return demanders[buyerResource] == true
end

-- ─── Export Calculation ───────────────────────────────────────────────────────

-- calculateExports(nation, allNations, scenario, getDiploState)
-- getDiploState: optional function(id1, id2) → diplomatic state string
-- Returns: totalExports (number), breakdown (table: nationId → amount)
function TradeSystem.calculateExports(nation, allNations, scenario, getDiploState)
    local totalExports = 0
    local breakdown = {}

    -- Identify trade partners (all other nations)
    local partners = {}
    for _, other in ipairs(allNations) do
        if other.id ~= nation.id then
            table.insert(partners, other)
        end
    end

    local numRoutes = #partners
    if numRoutes == 0 then
        return 0, {}
    end

    -- Free trade applies a global income multiplier
    local freeTradeMultiplier = 1.0
    if scenario == Config.SCENARIOS.FREE_TRADE then
        freeTradeMultiplier = 1 + Config.FREE_TRADE_BONUS
    end

    for _, partner in ipairs(partners) do
        -- Check embargo first: complete trade block (like Navigation Acts — zero traffic allowed)
        if getDiploState and getDiploState(nation.id, partner.id) == "embargo" then
            breakdown[partner.id] = 0
            -- no income from this route at all
        else
            -- Base income per route, split evenly across trade ships
            local routeIncome = Config.BASE_EXPORT_INCOME * (nation.tradeShips / numRoutes)

            -- Resource bonus if our resource is demanded by the partner
            if isResourceDemanded(nation.resource, partner.resource) then
                routeIncome = routeIncome + Config.RESOURCE_BONUS
            end

            -- Apply free trade multiplier
            routeIncome = routeIncome * freeTradeMultiplier

            -- Alliance bonus: allied nations give preferential market access
            if getDiploState and getDiploState(nation.id, partner.id) == "allied" then
                routeIncome = routeIncome * (1 + Config.ALLIANCE_TRADE_BONUS)
            end

            -- Tariff reduction: if partner has imposed tariffs on us, reduce income
            if scenario == Config.SCENARIOS.MERCANTILIST then
                if partner.tariffs and partner.tariffs[nation.id] then
                    routeIncome = routeIncome * (1 - Config.TARIFF_RATE)
                end
            end

            routeIncome = math.max(0, routeIncome)
            breakdown[partner.id] = routeIncome
            totalExports = totalExports + routeIncome
        end
    end

    -- Apply degradation export penalty (struggling/critical/bankrupt nations earn less
    -- because their infrastructure is decayed and trading partners lose confidence)
    local penalty = DegradationSystem.getExportPenalty(nation)
    if penalty < 1.0 then
        totalExports = totalExports * penalty
        for id, amt in pairs(breakdown) do
            breakdown[id] = amt * penalty
        end
    end

    return totalExports, breakdown
end

-- ─── Import Calculation ───────────────────────────────────────────────────────

-- calculateImports(nation, exports, scenario)
-- Returns: import spending (number)
function TradeSystem.calculateImports(nation, exports, scenario)
    local base = exports * Config.IMPORT_SPEND_RATIO

    if scenario == Config.SCENARIOS.MERCANTILIST then
        -- Count how many tariffs this nation has actively imposed
        local activeTariffCount = 0
        if nation.tariffs then
            for _, active in pairs(nation.tariffs) do
                if active then
                    activeTariffCount = activeTariffCount + 1
                end
            end
        end

        if activeTariffCount > 0 then
            -- Reduce imports proportionally to tariff usage (capped at 80% reduction)
            local reductionFactor = Config.TARIFF_RATE * activeTariffCount * 0.4
            reductionFactor = math.min(reductionFactor, 0.80)
            base = base * (1 - reductionFactor)
        end
    end

    return math.max(0, base)
end

-- ─── Tariff Policy AI ────────────────────────────────────────────────────────

-- evaluateTariffPolicy(nation, allNations, currentTick, nationState, scenario)
-- AI decision: imposes tariffs if trade balance is negative (mercantilist only,
-- after TARIFF_START_TICK).
function TradeSystem.evaluateTariffPolicy(nation, allNations, currentTick, nationState, scenario)
    -- Only act in mercantilist scenario
    if scenario ~= Config.SCENARIOS.MERCANTILIST then
        return
    end

    -- Only act after TARIFF_START_TICK
    if currentTick < Config.TARIFF_START_TICK then
        return
    end

    -- If trade balance is negative, impose tariffs on all partners
    if nation.tradeBalance < 0 then
        print(string.format(
            "[TradeSystem] %s has negative trade balance (%d g). Imposing tariffs on all partners.",
            nation.name, math.floor(nation.tradeBalance)
        ))

        for _, other in ipairs(allNations) do
            if other.id ~= nation.id then
                -- Only set if not already tariffing them
                if not nationState.hasTariff(nation.id, other.id) then
                    nationState.setTariff(nation.id, other.id, true)
                    print(string.format(
                        "[TradeSystem] %s imposes tariff on %s.",
                        nation.name, other.name
                    ))
                end
            end
        end
    end
end

return TradeSystem

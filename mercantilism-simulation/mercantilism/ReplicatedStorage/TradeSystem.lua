-- TradeSystem.lua
-- ModuleScript: relationship-based trade with resource buying/selling
-- Place in ReplicatedStorage

local RS                = game:GetService("ReplicatedStorage")
local Config            = require(RS:WaitForChild("GameConfig"))
local DegradationSystem = require(RS:WaitForChild("DegradationSystem"))

local TradeSystem = {}

-- ─── Resource Trade: determines what a nation wants to buy ──────────────────

-- Returns a list of { resource, urgency } that the buyer needs
-- Urgency: 2 = urgent (below min), 1 = normal need, 0 = saturated
local function getBuyingNeeds(nation)
    local needs = {}
    for _, res in ipairs(Config.RAW_RESOURCES) do
        -- Nations don't buy their own primary resource (they produce it)
        if res ~= nation.resource then
            local stock = nation.resources[res] or 0
            if stock < Config.RESOURCE_MIN_NEED then
                table.insert(needs, { resource = res, urgency = 2 })
            elseif stock < Config.RESOURCE_MAX_STOCK then
                table.insert(needs, { resource = res, urgency = 1 })
            end
            -- urgency 0 = saturated, not added (won't buy)
        end
    end
    return needs
end

-- ─── Export Calculation (relationship-based) ────────────────────────────────

-- calculateExports(nation, allNations, scenario, getDiploState, getRelation)
-- Trade is now driven by:
--   1. What the buyer needs (resource saturation)
--   2. The bilateral relationship score
--   3. Diplomatic state (alliance/embargo)
--   4. Economy tier (manufactured goods / technology)
function TradeSystem.calculateExports(nation, allNations, scenario, getDiploState, getRelation)
    local totalExports = 0
    local breakdown = {}
    local tradeDetails = {} -- for logging what resources were traded

    local partners = {}
    for _, other in ipairs(allNations) do
        if other.id ~= nation.id then
            table.insert(partners, other)
        end
    end

    if #partners == 0 then
        return 0, {}, {}
    end

    local freeTradeMultiplier = 1.0
    if scenario == Config.SCENARIOS.FREE_TRADE then
        freeTradeMultiplier = 1 + Config.FREE_TRADE_BONUS
    end

    -- How many ships service each route
    local shipsPerRoute = nation.tradeShips / #partners

    for _, partner in ipairs(partners) do
        local routeIncome = 0
        local routeResources = {}

        -- Check embargo
        if getDiploState and getDiploState(nation.id, partner.id) == "embargo" then
            breakdown[partner.id] = 0
        else
            -- Get what the partner wants to buy
            local partnerNeeds = getBuyingNeeds(partner)

            -- Sell raw resources that partner needs
            for _, need in ipairs(partnerNeeds) do
                if need.resource == nation.resource then
                    -- We produce this! Calculate trade value
                    local basePrice = Config.BASE_EXPORT_INCOME / #partners
                    local tradeAmount = math.min(
                        Config.RESOURCE_TRADE_AMOUNT * shipsPerRoute,
                        nation.resources[need.resource] or 0
                    )

                    if tradeAmount > 0 then
                        local price = basePrice * Config.RAW_PRICE

                        -- Urgent need premium
                        if need.urgency == 2 then
                            price = price * Config.RESOURCE_URGENT_PREMIUM
                        end

                        routeIncome = routeIncome + price
                        table.insert(routeResources, need.resource)

                        -- Transfer resources
                        nation.resources[need.resource] = math.max(0,
                            (nation.resources[need.resource] or 0) - tradeAmount)
                        partner.resources[need.resource] = math.min(
                            Config.RESOURCE_MAX_STOCK,
                            (partner.resources[need.resource] or 0) + tradeAmount)
                    end
                end
            end

            -- Economy tier 2: Manufactured goods (made from raw products, higher value)
            if nation.economyTier >= Config.ECONOMY_TIER.MANUFACTURE then
                -- Manufactured goods are always in demand (unless partner also manufactures)
                local mfgDemand = partner.economyTier < Config.ECONOMY_TIER.MANUFACTURE
                if mfgDemand then
                    local mfgPrice = (Config.BASE_EXPORT_INCOME / #partners) * Config.MANUFACTURED_PRICE
                    routeIncome = routeIncome + mfgPrice * shipsPerRoute
                    table.insert(routeResources, "ManufacturedGoods")
                end
            end

            -- Economy tier 3: Technology (alliance-only export, very high value)
            if nation.economyTier >= Config.ECONOMY_TIER.TECHNOLOGY then
                local diploState = getDiploState and getDiploState(nation.id, partner.id) or "neutral"
                if diploState == "allied" then
                    local techPrice = (Config.BASE_EXPORT_INCOME / #partners) * Config.TECHNOLOGY_PRICE
                    routeIncome = routeIncome + techPrice * shipsPerRoute
                    table.insert(routeResources, "Technology")
                end
            end

            -- Relationship modifier: better relations = better trade terms
            if getRelation then
                local rel = getRelation(nation.id, partner.id)
                if rel > Config.RELATION_INITIAL then
                    local bonus = (rel - Config.RELATION_INITIAL) * Config.RELATION_TRADE_BONUS_RATE
                    routeIncome = routeIncome * (1 + bonus)
                elseif rel < Config.RELATION_INITIAL then
                    local penalty = (Config.RELATION_INITIAL - rel) * Config.RELATION_TRADE_PENALTY_RATE
                    routeIncome = routeIncome * math.max(0.3, 1 - penalty)
                end
            end

            -- Free trade bonus
            routeIncome = routeIncome * freeTradeMultiplier

            -- Alliance bonus
            if getDiploState and getDiploState(nation.id, partner.id) == "allied" then
                routeIncome = routeIncome * (1 + Config.ALLIANCE_TRADE_BONUS)
            end

            -- Tariff penalty
            if scenario == Config.SCENARIOS.MERCANTILIST then
                if partner.tariffs and partner.tariffs[nation.id] then
                    routeIncome = routeIncome * (1 - Config.TARIFF_RATE)
                end
            end

            routeIncome = math.max(0, routeIncome)
            breakdown[partner.id] = routeIncome
            tradeDetails[partner.id] = routeResources
            totalExports = totalExports + routeIncome
        end
    end

    -- Apply degradation export penalty
    local penalty = DegradationSystem.getExportPenalty(nation)
    if penalty < 1.0 then
        totalExports = totalExports * penalty
        for id, amt in pairs(breakdown) do
            breakdown[id] = amt * penalty
        end
    end

    return totalExports, breakdown, tradeDetails
end

-- ─── Import Calculation ───────────────────────────────────────────────────────

function TradeSystem.calculateImports(nation, exports, scenario)
    local base = exports * Config.IMPORT_SPEND_RATIO

    if scenario == Config.SCENARIOS.MERCANTILIST then
        local activeTariffCount = 0
        if nation.tariffs then
            for _, active in pairs(nation.tariffs) do
                if active then
                    activeTariffCount = activeTariffCount + 1
                end
            end
        end

        if activeTariffCount > 0 then
            local reductionFactor = Config.TARIFF_RATE * activeTariffCount * 0.4
            reductionFactor = math.min(reductionFactor, 0.80)
            base = base * (1 - reductionFactor)
        end
    end

    return math.max(0, base)
end

-- ─── Tariff Policy AI ────────────────────────────────────────────────────────

function TradeSystem.evaluateTariffPolicy(nation, allNations, currentTick, nationState, scenario)
    if scenario ~= Config.SCENARIOS.MERCANTILIST then
        return
    end

    if currentTick < Config.TARIFF_START_TICK then
        return
    end

    -- Now tariff decisions are relationship-based too
    if nation.tradeBalance < 0 then
        for _, other in ipairs(allNations) do
            if other.id ~= nation.id then
                local relation = nationState.getRelation(nation.id, other.id)
                -- Only tariff nations we have poor relations with
                if relation < 60 then
                    if not nationState.hasTariff(nation.id, other.id) then
                        nationState.setTariff(nation.id, other.id, true)
                        print(string.format(
                            "[TradeSystem] %s imposes tariff on %s (relation: %d).",
                            nation.name, other.name, math.floor(relation)
                        ))
                    end
                end
            end
        end
    end
end

return TradeSystem

-- DiplomacySystem.lua
-- ModuleScript: diplomatic relations, privateers, and harbour sabotage
-- Place in ReplicatedStorage

local RS     = game:GetService("ReplicatedStorage")
local Config = require(RS:WaitForChild("GameConfig"))

local DiplomacySystem = {}

-- ─── Diplomatic State Constants ───────────────────────────────────────────────

DiplomacySystem.State = {
    NEUTRAL = "neutral",
    ALLIED  = "allied",   -- shared trade bonus; neither side plunders the other
    EMBARGO = "embargo",  -- complete trade block, stronger than tariff (100% cut)
}

-- ─── Private State ────────────────────────────────────────────────────────────

local _diplo      = {}   -- _diplo[id1][id2] = state string  (symmetric)
local _privateers = {}   -- _privateers[nationId] = count

-- ─── Initialization ───────────────────────────────────────────────────────────

function DiplomacySystem.init(nationList)
    _diplo      = {}
    _privateers = {}
    for _, n in ipairs(nationList) do
        _diplo[n.id]      = {}
        _privateers[n.id] = 0
        for _, m in ipairs(nationList) do
            if m.id ~= n.id then
                _diplo[n.id][m.id] = DiplomacySystem.State.NEUTRAL
            end
        end
    end
end

-- ─── State Access ─────────────────────────────────────────────────────────────

function DiplomacySystem.getState(id1, id2)
    if not _diplo[id1] then return DiplomacySystem.State.NEUTRAL end
    return _diplo[id1][id2] or DiplomacySystem.State.NEUTRAL
end

-- setState is always symmetric (both sides share the same relation)
function DiplomacySystem.setState(id1, id2, state)
    if not _diplo[id1] then _diplo[id1] = {} end
    if not _diplo[id2] then _diplo[id2] = {} end
    _diplo[id1][id2] = state
    _diplo[id2][id1] = state
end

function DiplomacySystem.getPrivateers(nationId)
    return _privateers[nationId] or 0
end

-- ─── Privateer Resolution ───────────────────────────────────────────────────

function DiplomacySystem.resolvePrivateers(nations, scenario, logs)
    if scenario == Config.SCENARIOS.FREE_TRADE then
        return {}
    end

    local results = {}

    for _, attacker in ipairs(nations) do
        local pc = _privateers[attacker.id] or 0
        if pc > 0 then
            for _, victim in ipairs(nations) do
                if victim.id ~= attacker.id then
                    local state = DiplomacySystem.getState(attacker.id, victim.id)
                    -- Allies are never targeted by privateers
                    if state ~= DiplomacySystem.State.ALLIED then
                        local successRate = Config.PRIVATEER_SUCCESS_RATE
                        -- Privateers are 40% more effective against embargoed trade
                        if state == DiplomacySystem.State.EMBARGO then
                            successRate = successRate * 1.4
                        end

                        for _ = 1, pc do
                            if victim.tradeShips > 0 and math.random() <= successRate then
                                local amount = math.min(Config.PRIVATEER_PLUNDER_AMOUNT, victim.wealth)
                                if amount > 0 then
                                    victim.wealth   = math.max(0, victim.wealth - amount)
                                    attacker.wealth = attacker.wealth + amount
                                    results[attacker.id] = (results[attacker.id] or 0) + amount
                                    if logs then
                                        table.insert(logs, string.format(
                                            "[PRIVATEER] %s's corsairs intercept %s's merchant fleet for %dg!",
                                            attacker.name, victim.name, math.floor(amount)
                                        ))
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return results
end

-- ─── Harbour Sabotage ─────────────────────────────────────────────────────────

function DiplomacySystem.resolveSabotage(nations, scenario, logs)
    if scenario == Config.SCENARIOS.FREE_TRADE then
        return
    end

    for _, attacker in ipairs(nations) do
        -- Only nations with surplus wealth consider sabotage
        if attacker.wealth >= Config.SABOTAGE_COST * 3 then
            -- Pick target: rival with the most trade ships
            local target = nil
            local mostShips = 1
            for _, victim in ipairs(nations) do
                if victim.id ~= attacker.id then
                    local state = DiplomacySystem.getState(attacker.id, victim.id)
                    if state ~= DiplomacySystem.State.ALLIED and victim.tradeShips > mostShips then
                        mostShips = victim.tradeShips
                        target    = victim
                    end
                end
            end

            if target and math.random() < Config.SABOTAGE_ATTEMPT_CHANCE then
                attacker.wealth = math.max(0, attacker.wealth - Config.SABOTAGE_COST)

                if math.random() < Config.SABOTAGE_SUCCESS_RATE then
                    target.tradeShips = math.max(1, target.tradeShips - 1)
                    if logs then
                        table.insert(logs, string.format(
                            "[SABOTAGE] %s agents burn %s's dockyard! %s loses a trade ship. (%dg operation)",
                            attacker.name, target.name, target.name, Config.SABOTAGE_COST
                        ))
                    end
                else
                    if logs then
                        table.insert(logs, string.format(
                            "[SABOTAGE] %s's sabotage against %s is uncovered and fails! (%dg wasted)",
                            attacker.name, target.name, Config.SABOTAGE_COST
                        ))
                    end
                end
            end
        end
    end
end

-- ─── Diplomatic AI ────────────────────────────────────────────────────────────
-- More aggressive v3: evaluates every 2 ticks from tick 3, higher probabilities

function DiplomacySystem.evaluateDiplomacy(nation, allNations, tick, logs)
    -- Evaluate from tick 3 onwards, every 2 ticks (faster diplomacy)
    if tick < 3 then return end
    if tick % 2 ~= 0 then return end

    for _, partner in ipairs(allNations) do
        if partner.id ~= nation.id then
            local state = DiplomacySystem.getState(nation.id, partner.id)

            -- ── Alliance Formation ─────────────────────────────────────────
            if state == DiplomacySystem.State.NEUTRAL then
                local bothHealthy = nation.wealth  > Config.INITIAL_WEALTH * 1.05
                               and partner.wealth > Config.INITIAL_WEALTH * 1.05
                local lowMutualThreat = (partner.warships <= 3) and (nation.warships <= 3)

                if bothHealthy and lowMutualThreat and math.random() < 0.30 then
                    DiplomacySystem.setState(nation.id, partner.id, DiplomacySystem.State.ALLIED)
                    if logs then
                        table.insert(logs, string.format(
                            "[DIPLOMACY] %s & %s forge a commercial treaty!",
                            nation.name, partner.name
                        ))
                    end
                end

                -- ── Embargo Declaration ───────────────────────────────────
                local beingDrained = partner.warships >= 3 and nation.wealth < Config.INITIAL_WEALTH * 0.80
                if beingDrained and math.random() < 0.40 then
                    DiplomacySystem.setState(nation.id, partner.id, DiplomacySystem.State.EMBARGO)
                    if logs then
                        table.insert(logs, string.format(
                            "[DIPLOMACY] %s declares a trade EMBARGO on %s!",
                            nation.name, partner.name
                        ))
                    end
                end
            end

            -- ── Alliance Breakdown ────────────────────────────────────────
            -- Alliances break when wealth disparity grows too large
            if state == DiplomacySystem.State.ALLIED then
                local ratio = partner.wealth / math.max(1, nation.wealth)
                if ratio > 1.8 and math.random() < 0.35 then
                    DiplomacySystem.setState(nation.id, partner.id, DiplomacySystem.State.NEUTRAL)
                    if logs then
                        table.insert(logs, string.format(
                            "[DIPLOMACY] %s dissolves alliance with %s — wealth gap too great!",
                            nation.name, partner.name
                        ))
                    end
                end
            end

            -- ── Embargo Lifted ────────────────────────────────────────────
            if state == DiplomacySystem.State.EMBARGO then
                if partner.wealth < Config.DEGRADE_THRESHOLD_CRITICAL and math.random() < 0.40 then
                    DiplomacySystem.setState(nation.id, partner.id, DiplomacySystem.State.NEUTRAL)
                    if logs then
                        table.insert(logs, string.format(
                            "[DIPLOMACY] %s lifts embargo on %s — target no longer a threat.",
                            nation.name, partner.name
                        ))
                    end
                end
            end
        end
    end

    -- ── Privateer Commission ──────────────────────────────────────────────────
    if (_privateers[nation.id] or 0) == 0 then
        local maxRivalWarships = 0
        for _, other in ipairs(allNations) do
            if other.id ~= nation.id and other.warships > maxRivalWarships then
                maxRivalWarships = other.warships
            end
        end

        if maxRivalWarships >= 2 and nation.wealth > Config.PRIVATEER_COMMISSION_COST * 1.5 then
            if math.random() < 0.35 then
                local count = math.min(3, math.floor(nation.wealth / (Config.PRIVATEER_COMMISSION_COST * 1.5)))
                count = math.max(1, count)
                nation.wealth = math.max(0, nation.wealth - Config.PRIVATEER_COMMISSION_COST * count)
                _privateers[nation.id] = count
                if logs then
                    table.insert(logs, string.format(
                        "[PRIVATEER] %s commissions %d corsair(s)! (%dg spent)",
                        nation.name, count, Config.PRIVATEER_COMMISSION_COST * count
                    ))
                end
            end
        end
    end
end

-- ─── Summary (for RemoteEvent serialisation) ─────────────────────────────────

function DiplomacySystem.getSummary(nationList)
    local result = {}
    for _, n in ipairs(nationList) do
        local relations = {}
        for _, m in ipairs(nationList) do
            if m.id ~= n.id then
                relations[tostring(m.id)] = DiplomacySystem.getState(n.id, m.id)
            end
        end
        result[n.id] = {
            privateers = _privateers[n.id] or 0,
            relations  = relations,
        }
    end
    return result
end

return DiplomacySystem

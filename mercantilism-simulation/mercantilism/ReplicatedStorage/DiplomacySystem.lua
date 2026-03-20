-- DiplomacySystem.lua
-- ModuleScript: relationship-driven diplomacy, privateers, and harbour sabotage
-- Place in ReplicatedStorage

local RS     = game:GetService("ReplicatedStorage")
local Config = require(RS:WaitForChild("GameConfig"))

local DiplomacySystem = {}

-- ─── Diplomatic State Constants ───────────────────────────────────────────────

DiplomacySystem.State = {
    NEUTRAL = "neutral",
    ALLIED  = "allied",
    EMBARGO = "embargo",
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
                    if state ~= DiplomacySystem.State.ALLIED then
                        local successRate = Config.PRIVATEER_SUCCESS_RATE
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

function DiplomacySystem.resolveSabotage(nations, scenario, logs, nationState)
    if scenario == Config.SCENARIOS.FREE_TRADE then
        return
    end

    for _, attacker in ipairs(nations) do
        if attacker.wealth >= Config.SABOTAGE_COST * 3 then
            -- Pick target: rival with worst relationship (not allied)
            local target = nil
            local worstRelation = 100
            for _, victim in ipairs(nations) do
                if victim.id ~= attacker.id then
                    local state = DiplomacySystem.getState(attacker.id, victim.id)
                    if state ~= DiplomacySystem.State.ALLIED and victim.tradeShips > 1 then
                        local rel = nationState and nationState.getRelation(attacker.id, victim.id) or 50
                        if rel < worstRelation then
                            worstRelation = rel
                            target = victim
                        end
                    end
                end
            end

            if target and worstRelation < 40 and math.random() < Config.SABOTAGE_ATTEMPT_CHANCE then
                attacker.wealth = math.max(0, attacker.wealth - Config.SABOTAGE_COST)

                if math.random() < Config.SABOTAGE_SUCCESS_RATE then
                    target.tradeShips = math.max(1, target.tradeShips - 1)
                    -- Sabotage worsens relations heavily
                    if nationState then
                        nationState.changeRelation(attacker.id, target.id, -20)
                    end
                    if logs then
                        table.insert(logs, string.format(
                            "[SABOTAGE] %s agents burn %s's dockyard! %s loses a trade ship. (%dg operation)",
                            attacker.name, target.name, target.name, Config.SABOTAGE_COST
                        ))
                    end
                else
                    -- Failed sabotage still damages relations
                    if nationState then
                        nationState.changeRelation(attacker.id, target.id, -10)
                    end
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

-- ─── Diplomatic AI (relationship-driven) ────────────────────────────────────
-- Decisions now based on bilateral relationship scores, not just wealth

function DiplomacySystem.evaluateDiplomacy(nation, allNations, tick, logs, nationState)
    if tick < 3 then return end
    if tick % 2 ~= 0 then return end

    for _, partner in ipairs(allNations) do
        if partner.id ~= nation.id then
            local state = DiplomacySystem.getState(nation.id, partner.id)
            local relation = nationState and nationState.getRelation(nation.id, partner.id) or 50

            -- ── Check resource dependency ─────────────────────────────────
            -- Does this nation urgently need the partner's resource?
            local needsPartnerResource = false
            local partnerProduces = partner.resource
            if partnerProduces and nation.resources then
                local stock = nation.resources[partnerProduces] or 0
                needsPartnerResource = stock < Config.RESOURCE_MIN_NEED
            end

            -- ── Alliance Formation (relationship + resource-driven) ─────────
            if state == DiplomacySystem.State.NEUTRAL then
                -- Lower threshold if we desperately need their resource
                local allianceThreshold = Config.RELATION_ALLIANCE_THRESHOLD
                if needsPartnerResource then
                    allianceThreshold = allianceThreshold - 15  -- easier to ally with needed suppliers
                end

                if relation >= allianceThreshold and math.random() < 0.35 then
                    DiplomacySystem.setState(nation.id, partner.id, DiplomacySystem.State.ALLIED)
                    if nationState then
                        nationState.changeRelation(nation.id, partner.id, 10)
                    end
                    local reason = needsPartnerResource
                        and string.format(" (needs %s!)", partnerProduces) or ""
                    if logs then
                        table.insert(logs, string.format(
                            "[DIPLOMACY] %s & %s forge a commercial treaty!%s (relation: %d)",
                            nation.name, partner.name, reason, math.floor(relation)
                        ))
                    end
                end

                -- ── Embargo Declaration ───────────────────────────────────────
                -- Won't embargo a nation whose resource we urgently need
                if not needsPartnerResource
                    and relation <= Config.RELATION_EMBARGO_THRESHOLD
                    and math.random() < 0.40 then
                    DiplomacySystem.setState(nation.id, partner.id, DiplomacySystem.State.EMBARGO)
                    if nationState then
                        nationState.changeRelation(nation.id, partner.id, -10)
                    end
                    if logs then
                        table.insert(logs, string.format(
                            "[DIPLOMACY] %s declares a trade EMBARGO on %s! (relation: %d)",
                            nation.name, partner.name, math.floor(relation)
                        ))
                    end
                elseif needsPartnerResource
                    and relation <= Config.RELATION_EMBARGO_THRESHOLD then
                    -- Would embargo, but can't afford to — we need their resource
                    if logs then
                        table.insert(logs, string.format(
                            "[DIPLOMACY] %s holds off embargo on %s — too dependent on %s supply!",
                            nation.name, partner.name, partnerProduces
                        ))
                    end
                end
            end

            -- ── Alliance Breakdown (when relations deteriorate) ──────────────
            if state == DiplomacySystem.State.ALLIED then
                local ratio = partner.wealth / math.max(1, nation.wealth)
                -- Harder to break alliance if we need their resource
                local breakThreshold = needsPartnerResource and 40 or 55
                if relation < breakThreshold or (ratio > 1.8 and not needsPartnerResource and math.random() < 0.35) then
                    DiplomacySystem.setState(nation.id, partner.id, DiplomacySystem.State.NEUTRAL)
                    if logs then
                        table.insert(logs, string.format(
                            "[DIPLOMACY] %s dissolves alliance with %s — relations strained! (relation: %d)",
                            nation.name, partner.name, math.floor(relation)
                        ))
                    end
                end
            end

            -- ── Embargo Lifted (when relations improve or resource desperation) ─
            if state == DiplomacySystem.State.EMBARGO then
                -- Lift embargo more readily if we urgently need their resource
                local liftChance = 0.30
                local liftThreshold = 40
                if needsPartnerResource then
                    liftChance = 0.55      -- much more likely to lift
                    liftThreshold = 20     -- even at very low relations
                end

                if relation > liftThreshold and math.random() < liftChance then
                    DiplomacySystem.setState(nation.id, partner.id, DiplomacySystem.State.NEUTRAL)
                    if nationState then
                        nationState.changeRelation(nation.id, partner.id, 5)
                    end
                    local reason = needsPartnerResource
                        and string.format(" — desperate for %s!", partnerProduces)
                        or " — relations warming."
                    if logs then
                        table.insert(logs, string.format(
                            "[DIPLOMACY] %s lifts embargo on %s%s (relation: %d)",
                            nation.name, partner.name, reason, math.floor(relation)
                        ))
                    end
                end
            end
        end
    end

    -- ── Privateer Commission (relationship-driven) ──────────────────────────
    if (_privateers[nation.id] or 0) == 0 then
        -- Commission privateers against nations with low relations
        local worstRelation = 100
        local worstRival = nil
        for _, other in ipairs(allNations) do
            if other.id ~= nation.id then
                local rel = nationState and nationState.getRelation(nation.id, other.id) or 50
                if rel < worstRelation and other.tradeShips > 0 then
                    worstRelation = rel
                    worstRival = other
                end
            end
        end

        if worstRival and worstRelation < Config.RELATION_RAID_THRESHOLD
            and nation.wealth > Config.PRIVATEER_COMMISSION_COST * 1.5 then
            if math.random() < 0.35 then
                local count = math.min(3, math.floor(nation.wealth / (Config.PRIVATEER_COMMISSION_COST * 1.5)))
                count = math.max(1, count)
                nation.wealth = math.max(0, nation.wealth - Config.PRIVATEER_COMMISSION_COST * count)
                _privateers[nation.id] = count
                if logs then
                    table.insert(logs, string.format(
                        "[PRIVATEER] %s commissions %d corsair(s) against %s! (%dg spent, relation: %d)",
                        nation.name, count, worstRival.name,
                        Config.PRIVATEER_COMMISSION_COST * count, math.floor(worstRelation)
                    ))
                end
            end
        end
    end
end

-- ─── Summary ─────────────────────────────────────────────────────────────────

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

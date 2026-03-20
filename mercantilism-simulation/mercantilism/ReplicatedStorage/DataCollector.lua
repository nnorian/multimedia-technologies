-- DataCollector.lua
-- ModuleScript: collects per-tick simulation data for statistical analysis
-- Place in ReplicatedStorage

local RS     = game:GetService("ReplicatedStorage")
local Config = require(RS:WaitForChild("GameConfig"))

local DataCollector = {}

-- ─── Internal Storage ───────────────────────────────────────────────────────

local _tickRows  = {}   -- per-nation per-tick snapshots
local _eventRows = {}   -- discrete events (random, diplomacy, sabotage, privateer, plunder)
local _scenario  = ""

-- nation name lookup
local _nationNames = {}
for _, nd in ipairs(Config.NATIONS) do
    _nationNames[nd.id] = nd.name
end

-- ─── API ────────────────────────────────────────────────────────────────────

function DataCollector.init()
    _tickRows  = {}
    _eventRows = {}
    _scenario  = ""
end

function DataCollector.beginScenario(scenarioName)
    _scenario = scenarioName
end

-- Record end-of-tick snapshot for one nation
function DataCollector.recordTick(tick, nationId, fields)
    local row = {
        scenario          = _scenario,
        tick              = tick,
        nation            = _nationNames[nationId] or tostring(nationId),
        wealth            = math.floor(fields.wealth or 0),
        wealth_delta      = math.floor(fields.wealth_delta or 0),
        exports           = math.floor(fields.exports or 0),
        imports           = math.floor(fields.imports or 0),
        plunder_gained    = math.floor(fields.plunder_gained or 0),
        plunder_lost      = math.floor(fields.plunder_lost or 0),
        navy_cost         = math.floor(fields.navy_cost or 0),
        trade_ships       = fields.trade_ships or 0,
        warships          = fields.warships or 0,
        degradation_level = fields.degradation_level or "healthy",
        tariff_count      = fields.tariff_count or 0,
        alliance_count    = fields.alliance_count or 0,
        embargo_count     = fields.embargo_count or 0,
        privateer_count   = fields.privateer_count or 0,
        economy_tier      = fields.economy_tier or 1,
    }
    table.insert(_tickRows, row)
end

-- Record a discrete event
function DataCollector.recordEvent(tick, eventType, actorName, targetName, detail, amount)
    table.insert(_eventRows, {
        scenario   = _scenario,
        tick       = tick,
        event_type = eventType,
        actor      = actorName or "",
        target     = targetName or "",
        detail     = detail or "",
        amount     = math.floor(amount or 0),
    })
end

-- ─── CSV Export ─────────────────────────────────────────────────────────────

local TICK_COLUMNS = {
    "scenario","tick","nation","wealth","wealth_delta","exports","imports",
    "plunder_gained","plunder_lost","navy_cost","trade_ships","warships",
    "degradation_level","tariff_count","alliance_count","embargo_count","privateer_count",
    "economy_tier"
}

local EVENT_COLUMNS = {
    "scenario","tick","event_type","actor","target","detail","amount"
}

local function rowToCSV(row, columns)
    local parts = {}
    for _, col in ipairs(columns) do
        local v = row[col]
        if v == nil then v = "" end
        table.insert(parts, tostring(v))
    end
    return table.concat(parts, ",")
end

function DataCollector.getCSV()
    local lines = { table.concat(TICK_COLUMNS, ",") }
    for _, row in ipairs(_tickRows) do
        table.insert(lines, rowToCSV(row, TICK_COLUMNS))
    end
    return table.concat(lines, "\n")
end

function DataCollector.getEventLog()
    local lines = { table.concat(EVENT_COLUMNS, ",") }
    for _, row in ipairs(_eventRows) do
        table.insert(lines, rowToCSV(row, EVENT_COLUMNS))
    end
    return table.concat(lines, "\n")
end

-- ─── Aggregate Statistics ───────────────────────────────────────────────────

function DataCollector.computeAggregates()
    local out = {}
    local function line(s) table.insert(out, s) end
    local function blank() table.insert(out, "") end

    -- Helper: filter tick rows
    local function filterRows(scenario, nationName)
        local result = {}
        for _, r in ipairs(_tickRows) do
            if (not scenario or r.scenario == scenario) and
               (not nationName or r.nation == nationName) then
                table.insert(result, r)
            end
        end
        return result
    end

    local function avg(rows, field)
        if #rows == 0 then return 0 end
        local sum = 0
        for _, r in ipairs(rows) do sum = sum + (r[field] or 0) end
        return sum / #rows
    end

    local function sum(rows, field)
        local total = 0
        for _, r in ipairs(rows) do total = total + (r[field] or 0) end
        return total
    end

    local nationNames = {}
    for _, nd in ipairs(Config.NATIONS) do
        table.insert(nationNames, nd.name)
    end

    -- ── 1. Tariff-Wealth Correlation (Mercantilist) ─────────────────────────
    line("=== TARIFF-WEALTH CORRELATION (Mercantilist) ===")
    line("Nation,Avg_Delta_WITH_Tariffs,Avg_Delta_WITHOUT_Tariffs,Difference")
    for _, name in ipairs(nationNames) do
        local rows = filterRows("mercantilist", name)
        local withT, withoutT = {}, {}
        for _, r in ipairs(rows) do
            if r.tariff_count > 0 then
                table.insert(withT, r)
            else
                table.insert(withoutT, r)
            end
        end
        local avgWith    = avg(withT, "wealth_delta")
        local avgWithout = avg(withoutT, "wealth_delta")
        line(string.format("%s,%d,%d,%d", name,
            math.floor(avgWith), math.floor(avgWithout),
            math.floor(avgWith - avgWithout)))
    end
    blank()

    -- ── 2. Alliance Trade Impact ────────────────────────────────────────────
    line("=== ALLIANCE TRADE IMPACT (Mercantilist) ===")
    line("Nation,Avg_Exports_WITH_Alliance,Avg_Exports_WITHOUT,Difference")
    for _, name in ipairs(nationNames) do
        local rows = filterRows("mercantilist", name)
        local withA, withoutA = {}, {}
        for _, r in ipairs(rows) do
            if r.alliance_count > 0 then
                table.insert(withA, r)
            else
                table.insert(withoutA, r)
            end
        end
        local avgWith    = avg(withA, "exports")
        local avgWithout = avg(withoutA, "exports")
        line(string.format("%s,%d,%d,%d", name,
            math.floor(avgWith), math.floor(avgWithout),
            math.floor(avgWith - avgWithout)))
    end
    blank()

    -- ── 3. Arms Race Burden ─────────────────────────────────────────────────
    line("=== ARMS RACE BURDEN (Mercantilist) ===")
    line("Nation,Total_Navy_Cost,Total_Exports,Navy_Pct_of_Exports")
    for _, name in ipairs(nationNames) do
        local rows = filterRows("mercantilist", name)
        local totalNavy   = sum(rows, "navy_cost")
        local totalExport = sum(rows, "exports")
        local pct = totalExport > 0 and math.floor(totalNavy / totalExport * 100) or 0
        line(string.format("%s,%d,%d,%d%%", name,
            math.floor(totalNavy), math.floor(totalExport), pct))
    end
    blank()

    -- ── 4. Random Event Distribution ────────────────────────────────────────
    line("=== RANDOM EVENT DISTRIBUTION ===")
    line("Event,Count,Scenarios")
    local eventCounts = {}
    for _, e in ipairs(_eventRows) do
        if e.event_type == "random_event" then
            local key = e.detail
            if not eventCounts[key] then
                eventCounts[key] = { count = 0, scenarios = {} }
            end
            eventCounts[key].count = eventCounts[key].count + 1
            eventCounts[key].scenarios[e.scenario] = true
        end
    end
    for evName, data in pairs(eventCounts) do
        local scens = {}
        for s, _ in pairs(data.scenarios) do table.insert(scens, s) end
        line(string.format("%s,%d,%s", evName, data.count, table.concat(scens, "/")))
    end
    blank()

    -- ── 5. Plunder & Privateer Totals ───────────────────────────────────────
    line("=== PLUNDER & PRIVATEER TOTALS ===")
    line("Scenario,Nation,Total_Plunder_Gained,Total_Plunder_Lost,Total_Privateer_Gained,Total_Privateer_Lost")
    for _, scen in ipairs({"mercantilist", "freetrade"}) do
        for _, name in ipairs(nationNames) do
            local plunderGained, plunderLost = 0, 0
            local privateerGained, privateerLost = 0, 0
            for _, e in ipairs(_eventRows) do
                if e.scenario == scen then
                    if e.event_type == "plunder" and e.actor == name then
                        plunderGained = plunderGained + e.amount
                    elseif e.event_type == "plunder" and e.target == name then
                        plunderLost = plunderLost + e.amount
                    elseif e.event_type == "privateer_raid" and e.actor == name then
                        privateerGained = privateerGained + e.amount
                    elseif e.event_type == "privateer_raid" and e.target == name then
                        privateerLost = privateerLost + e.amount
                    end
                end
            end
            line(string.format("%s,%s,%d,%d,%d,%d", scen, name,
                plunderGained, plunderLost, privateerGained, privateerLost))
        end
    end
    blank()

    -- ── 6. Scenario Comparison ──────────────────────────────────────────────
    line("=== SCENARIO COMPARISON ===")
    line("Metric,Mercantilist,Free_Trade,Difference_Pct")

    local mercRows = filterRows("mercantilist", nil)
    local freeRows = filterRows("freetrade", nil)

    -- Final wealth per scenario (last tick rows)
    local function finalWealth(rows)
        local maxTick = 0
        for _, r in ipairs(rows) do
            if r.tick > maxTick then maxTick = r.tick end
        end
        local total = 0
        for _, r in ipairs(rows) do
            if r.tick == maxTick then total = total + r.wealth end
        end
        return total
    end

    local mercFinal = finalWealth(mercRows)
    local freeFinal = finalWealth(freeRows)
    local diffPct = mercFinal > 0 and math.floor((freeFinal - mercFinal) / mercFinal * 100) or 0

    line(string.format("Total_Global_Wealth,%d,%d,%d%%", mercFinal, freeFinal, diffPct))
    line(string.format("Avg_Nation_Wealth,%d,%d,%d%%",
        math.floor(mercFinal / 4), math.floor(freeFinal / 4), diffPct))
    line(string.format("Total_Exports,%d,%d,",
        math.floor(sum(mercRows, "exports")), math.floor(sum(freeRows, "exports"))))
    line(string.format("Total_Navy_Cost,%d,%d,",
        math.floor(sum(mercRows, "navy_cost")), math.floor(sum(freeRows, "navy_cost"))))
    line(string.format("Total_Plunder_Gained,%d,%d,",
        math.floor(sum(mercRows, "plunder_gained")), math.floor(sum(freeRows, "plunder_gained"))))
    blank()

    -- ── 7. Gini Coefficient ─────────────────────────────────────────────────
    local function gini(wealthList)
        local n = #wealthList
        if n < 2 then return 0 end
        table.sort(wealthList)
        local totalWealth = 0
        for _, w in ipairs(wealthList) do totalWealth = totalWealth + w end
        if totalWealth == 0 then return 0 end
        local sumDiffs = 0
        for i = 1, n do
            for j = 1, n do
                sumDiffs = sumDiffs + math.abs(wealthList[i] - wealthList[j])
            end
        end
        return sumDiffs / (2 * n * totalWealth)
    end

    local function finalWealthList(rows)
        local maxTick = 0
        for _, r in ipairs(rows) do
            if r.tick > maxTick then maxTick = r.tick end
        end
        local list = {}
        for _, r in ipairs(rows) do
            if r.tick == maxTick then table.insert(list, r.wealth) end
        end
        return list
    end

    local mercGini = gini(finalWealthList(mercRows))
    local freeGini = gini(finalWealthList(freeRows))
    line("=== WEALTH INEQUALITY (Gini Coefficient, 0=equal 1=unequal) ===")
    line(string.format("Mercantilist Gini: %.3f", mercGini))
    line(string.format("Free Trade Gini:   %.3f", freeGini))
    blank()

    -- ── 8. Per-Nation Final Comparison ───────────────────────────────────────
    line("=== PER-NATION FINAL WEALTH ===")
    line("Nation,Mercantilist,Free_Trade,Difference")
    for _, name in ipairs(nationNames) do
        local mercNRows = filterRows("mercantilist", name)
        local freeNRows = filterRows("freetrade", name)
        local mFinal = finalWealth(mercNRows)
        local fFinal = finalWealth(freeNRows)
        line(string.format("%s,%d,%d,%d", name, mFinal, fFinal, fFinal - mFinal))
    end

    return table.concat(out, "\n")
end

return DataCollector

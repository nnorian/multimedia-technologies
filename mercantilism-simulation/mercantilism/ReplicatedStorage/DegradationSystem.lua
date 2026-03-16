-- DegradationSystem.lua
-- ModuleScript: handles fleet degradation, trade contraction, and island visual decay
-- when a nation's trading performance is poor.
-- Place in ReplicatedStorage

local RS     = game:GetService("ReplicatedStorage")
local Config = require(RS:WaitForChild("GameConfig"))

local DegradationSystem = {}

-- ─── Degradation Level Constants ─────────────────────────────────────────────

DegradationSystem.Level = {
    HEALTHY    = "healthy",
    STRUGGLING = "struggling",
    CRITICAL   = "critical",
    BANKRUPT   = "bankrupt",
}

-- Island colors per degradation level
local ISLAND_COLORS = {
    healthy    = Color3.fromRGB(95,  130, 60),   -- lush green
    struggling = Color3.fromRGB(180, 155, 60),   -- sandy yellow
    critical   = Color3.fromRGB(130, 90,  40),   -- dry brown
    bankrupt   = Color3.fromRGB(70,  65,  65),   -- ash grey
}

-- ─── Helpers ─────────────────────────────────────────────────────────────────

-- getDegradationLevel(nation) → Level string
function DegradationSystem.getDegradationLevel(nation)
    local w = nation.wealth
    if w >= Config.DEGRADE_THRESHOLD_STRUGGLING then
        return DegradationSystem.Level.HEALTHY
    elseif w >= Config.DEGRADE_THRESHOLD_CRITICAL then
        return DegradationSystem.Level.STRUGGLING
    elseif w >= Config.DEGRADE_THRESHOLD_BANKRUPT then
        return DegradationSystem.Level.CRITICAL
    else
        return DegradationSystem.Level.BANKRUPT
    end
end

-- getExportPenalty(nation) → multiplier (0–1)
-- Applied in TradeSystem to reduce export income when a nation is degraded.
function DegradationSystem.getExportPenalty(nation)
    local level = DegradationSystem.getDegradationLevel(nation)
    if level == DegradationSystem.Level.HEALTHY then
        return 1.0
    elseif level == DegradationSystem.Level.STRUGGLING then
        return Config.DEGRADE_EXPORT_PENALTY_STRUGGLING
    elseif level == DegradationSystem.Level.CRITICAL then
        return Config.DEGRADE_EXPORT_PENALTY_CRITICAL
    else
        return Config.DEGRADE_EXPORT_PENALTY_BANKRUPT
    end
end

-- ─── Core: Apply Degradation Effects ─────────────────────────────────────────

-- applyDegradation(nation, scenario, logs)
-- Modifies `nation` in-place (tradeShips, warships, navyCost, degradationLevel).
-- Appends event strings to `logs`.
function DegradationSystem.applyDegradation(nation, scenario, logs)
    local level = DegradationSystem.getDegradationLevel(nation)
    nation.degradationLevel = level

    -- Track consecutive ticks with negative trade balance
    if (nation.tradeBalance or 0) < 0 then
        nation.consecutiveNegativeTicks = (nation.consecutiveNegativeTicks or 0) + 1
    else
        nation.consecutiveNegativeTicks = 0
    end

    -- ── STRUGGLING ────────────────────────────────────────────────────────────
    -- After several consecutive losing ticks, abandon one trade route.
    if level == DegradationSystem.Level.STRUGGLING then
        local consec = nation.consecutiveNegativeTicks or 0
        if consec >= Config.DEGRADE_CONSEC_TICKS_FOR_SHIP_LOSS
            and nation.tradeShips > Config.DEGRADE_MIN_TRADE_SHIPS
        then
            nation.tradeShips = nation.tradeShips - 1
            nation.consecutiveNegativeTicks = 0
            local msg = string.format(
                "[DECAY] %s abandons a trade route after %d losing seasons. Trade ships: %d",
                nation.name, consec, nation.tradeShips
            )
            table.insert(logs, msg)
            print(msg)
        end
    end

    -- ── CRITICAL ──────────────────────────────────────────────────────────────
    -- Warship desertion + chance of trade-ship breakdown.
    if level == DegradationSystem.Level.CRITICAL then
        -- Warship desertion: soldiers go unpaid and leave
        if nation.warships > 1 and math.random() < Config.DEGRADE_DESERTION_CHANCE then
            nation.warships = nation.warships - 1
            nation.navyCost = nation.warships * Config.WARSHIP_COST_PER_TICK
            local msg = string.format(
                "[DECAY] %s loses a warship — soldiers desert; unpaid wages. Warships: %d",
                nation.name, nation.warships
            )
            table.insert(logs, msg)
            print(msg)
        end

        -- Trade-ship breakdown: vessel falls to disrepair
        if nation.tradeShips > Config.DEGRADE_MIN_TRADE_SHIPS
            and math.random() < Config.DEGRADE_SHIP_LOSS_CHANCE_CRITICAL
        then
            nation.tradeShips = nation.tradeShips - 1
            local msg = string.format(
                "[DECAY] %s loses a trade ship — vessel falls to disrepair. Trade ships: %d",
                nation.name, nation.tradeShips
            )
            table.insert(logs, msg)
            print(msg)
        end
    end

    -- ── BANKRUPT ──────────────────────────────────────────────────────────────
    -- Rapid fleet collapse; both ship types lost at high probability.
    if level == DegradationSystem.Level.BANKRUPT then
        if nation.tradeShips > Config.DEGRADE_MIN_TRADE_SHIPS
            and math.random() < Config.DEGRADE_SHIP_LOSS_CHANCE_BANKRUPT
        then
            nation.tradeShips = nation.tradeShips - 1
            local msg = string.format(
                "[BANKRUPT] %s loses a trade ship — treasury empty, fleet collapses. Ships: %d",
                nation.name, nation.tradeShips
            )
            table.insert(logs, msg)
            print(msg)
        end

        if nation.warships > 1
            and math.random() < Config.DEGRADE_SHIP_LOSS_CHANCE_BANKRUPT
        then
            nation.warships = nation.warships - 1
            nation.navyCost = nation.warships * Config.WARSHIP_COST_PER_TICK
            local msg = string.format(
                "[BANKRUPT] %s loses a warship — navy abandoned. Warships: %d",
                nation.name, nation.warships
            )
            table.insert(logs, msg)
            print(msg)
        end
    end
end

-- ─── Visual: Island Color Update ─────────────────────────────────────────────

-- updateIslandVisuals(nation)
-- Changes the island's base color and transparency in Workspace to reflect
-- the nation's current degradation level.
function DegradationSystem.updateIslandVisuals(nation)
    local level = DegradationSystem.getDegradationLevel(nation)
    local targetColor = ISLAND_COLORS[level]

    local islandsFolder = workspace:FindFirstChild("Islands")
    if not islandsFolder then return end

    local islandModel = islandsFolder:FindFirstChild(nation.name)
    if not islandModel then return end

    local islandBase = islandModel:FindFirstChild("IslandBase")
    if not islandBase then return end

    islandBase.Color = targetColor

    -- Bankrupt islands look visibly derelict (slightly transparent)
    islandBase.Transparency = (level == DegradationSystem.Level.BANKRUPT) and 0.18 or 0
end

return DegradationSystem

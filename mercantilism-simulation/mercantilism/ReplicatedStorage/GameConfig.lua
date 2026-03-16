-- GameConfig.lua
-- ModuleScript: pure constants for the Mercantilism Simulation
-- Place in ReplicatedStorage

local Config = {}

Config.NATIONS = {
    { id = 1, name = "Ironhaven",    color = Color3.fromRGB(0, 36, 125),  resource = "Iron",   position = Vector3.new(-160, 1, -160) },
    { id = 2, name = "Goldspire",    color = Color3.fromRGB(0, 85, 164),  resource = "Grain",  position = Vector3.new(160, 1, -160)  },
    { id = 3, name = "Emberveil",    color = Color3.fromRGB(170, 21, 27), resource = "Spices", position = Vector3.new(-160, 1, 160)  },
    { id = 4, name = "Drifthollow",  color = Color3.fromRGB(255, 174, 0), resource = "Wood",   position = Vector3.new(160, 1, 160)   },
}

Config.INITIAL_WEALTH         = 1000
Config.TICK_DURATION          = 12      -- seconds per trading season
Config.MAX_TICKS              = 24

Config.BASE_EXPORT_INCOME     = 95      -- up from 75: bigger trade swings
Config.RESOURCE_BONUS         = 35      -- up from 25: specialisation matters more
Config.IMPORT_SPEND_RATIO     = 0.55

Config.TARIFF_RATE            = 0.50    -- up from 0.40: tariffs bite harder
Config.TARIFF_START_TICK      = 2       -- earlier tariff wars (was 3)
Config.RETALIATION_DELAY      = 1       -- faster retaliation (was 2)

Config.INITIAL_TRADE_SHIPS    = 2
Config.INITIAL_WARSHIPS       = 1
Config.WARSHIP_COST_PER_TICK  = 30      -- up from 20: arms race drains faster
Config.PLUNDER_SUCCESS_RATE   = 0.45    -- up from 0.35: more raiding
Config.PLUNDER_AMOUNT         = 85      -- up from 55: huge plunder swings
Config.MAX_WARSHIPS           = 8

Config.ARMS_RACE_ALPHA        = 1.25    -- up from 1.15: faster escalation
Config.ARMS_RACE_BETA         = 15      -- up from 10

Config.FREE_TRADE_BONUS       = 0.40    -- up from 0.35: free trade advantage clearer

-- Degradation thresholds (wealth levels) — tighter bands for more drama
Config.DEGRADE_THRESHOLD_STRUGGLING       = 600   -- was 500
Config.DEGRADE_THRESHOLD_CRITICAL         = 250   -- was 200
Config.DEGRADE_THRESHOLD_BANKRUPT         = 100   -- was 75

-- Degradation effects
Config.DEGRADE_MIN_TRADE_SHIPS            = 1
Config.DEGRADE_CONSEC_TICKS_FOR_SHIP_LOSS = 2     -- was 3: faster decay
Config.DEGRADE_DESERTION_CHANCE           = 0.50   -- was 0.40
Config.DEGRADE_SHIP_LOSS_CHANCE_CRITICAL  = 0.40   -- was 0.30
Config.DEGRADE_SHIP_LOSS_CHANCE_BANKRUPT  = 0.65   -- was 0.55

-- Export income multipliers per degradation level
Config.DEGRADE_EXPORT_PENALTY_STRUGGLING  = 0.80   -- was 0.85
Config.DEGRADE_EXPORT_PENALTY_CRITICAL    = 0.55   -- was 0.65
Config.DEGRADE_EXPORT_PENALTY_BANKRUPT    = 0.30   -- was 0.40

Config.OCEAN_SIZE   = Vector3.new(520, 2, 520)
Config.ISLAND_SIZE  = Vector3.new(60, 14, 60)
Config.SHIP_SPEED   = 45

Config.SCENARIOS = { MERCANTILIST = "mercantilist", FREE_TRADE = "freetrade" }

-- ─── Privateer System ─────────────────────────────────────────────────────────
Config.PRIVATEER_COMMISSION_COST  = 120    -- was 150: cheaper to commission
Config.PRIVATEER_SUCCESS_RATE     = 0.55   -- was 0.50
Config.PRIVATEER_PLUNDER_AMOUNT   = 65     -- was 40: big privateer hauls

-- ─── Sabotage System ─────────────────────────────────────────────────────────
Config.SABOTAGE_COST              = 70     -- was 80: cheaper operations
Config.SABOTAGE_ATTEMPT_CHANCE    = 0.28   -- was 0.18: much more frequent
Config.SABOTAGE_SUCCESS_RATE      = 0.55   -- was 0.45: higher success

-- ─── Diplomacy ────────────────────────────────────────────────────────────────
Config.ALLIANCE_TRADE_BONUS       = 0.30   -- was 0.22: alliances matter more
Config.EMBARGO_TRADE_MULTIPLIER   = 0.0    -- complete trade block

-- ─── Random Market Events (NEW in v3) ───────────────────────────────────────
Config.EVENT_CHANCE_PER_TICK      = 0.40   -- 40% chance of a random event each tick
Config.EVENT_GOLD_RUSH_BONUS      = 250    -- windfall gold
Config.EVENT_PLAGUE_LOSS          = 200    -- plague drains treasury
Config.EVENT_STORM_SHIP_LOSS      = true   -- storms can sink ships
Config.EVENT_MARKET_BOOM_MULT     = 1.60   -- 60% export bonus for one tick
Config.EVENT_MARKET_CRASH_MULT    = 0.40   -- 60% export penalty for one tick

return Config

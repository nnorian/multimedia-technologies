-- GameConfig.lua
-- ModuleScript: pure constants for the Mercantilism Simulation
-- Place in ReplicatedStorage

local Config = {}

-- ─── Resource Types ──────────────────────────────────────────────────────────
-- 4 raw resources each country produces one of
Config.RAW_RESOURCES = { "Meat", "Logs", "Ore", "Herbs" }

-- Colors for each resource (used on boat cargo stripe)
Config.RESOURCE_COLORS = {
    Meat  = Color3.fromRGB(180, 40, 40),   -- red
    Logs  = Color3.fromRGB(120, 80, 30),   -- brown
    Ore   = Color3.fromRGB(100, 110, 130),  -- steel-grey
    Herbs = Color3.fromRGB(50, 160, 60),   -- green
    ManufacturedGoods = Color3.fromRGB(200, 170, 60), -- gold-ish
    Technology        = Color3.fromRGB(80, 180, 255),  -- cyan
}

-- ─── Economy Tiers ──────────────────────────────────────────────────────────
-- Each nation progresses through tiers as wealth grows
Config.ECONOMY_TIER = {
    RAW          = 1,  -- can only produce & export raw resources
    MANUFACTURE  = 2,  -- can produce manufactured goods (higher value)
    TECHNOLOGY   = 3,  -- can produce technology (highest value, alliance-only export)
}
Config.TIER_THRESHOLD_MANUFACTURE = 1400  -- wealth needed to unlock tier 2
Config.TIER_THRESHOLD_TECHNOLOGY  = 2200  -- wealth needed to unlock tier 3

-- Price multipliers per tier of goods
Config.RAW_PRICE             = 1.0
Config.MANUFACTURED_PRICE    = 2.2   -- manufactured goods sell for 2.2x raw price
Config.TECHNOLOGY_PRICE      = 4.0   -- technology sells for 4x raw price

-- ─── Resource Needs & Saturation ─────────────────────────────────────────────
-- Each nation needs all 4 raw resources to function
-- They produce their own, must buy the other 3
Config.RESOURCE_MIN_NEED      = 20    -- below this → urgent buyer (pays premium)
Config.RESOURCE_MAX_STOCK     = 100   -- above this → saturated, won't buy more
Config.RESOURCE_START_STOCK   = 40    -- starting stock for each resource
Config.RESOURCE_OWN_PRODUCTION = 15   -- amount of own resource produced per tick
Config.RESOURCE_CONSUMPTION    = 8    -- amount of each resource consumed per tick
Config.RESOURCE_URGENT_PREMIUM = 1.5  -- 50% price premium when below min need
Config.RESOURCE_TRADE_AMOUNT   = 12   -- units shipped per trade ship per route

-- ─── Nations ─────────────────────────────────────────────────────────────────

Config.NATIONS = {
    { id = 1, name = "Ironhaven",    color = Color3.fromRGB(0, 36, 125),  resource = "Ore",   position = Vector3.new(-160, 1, -160) },
    { id = 2, name = "Goldspire",    color = Color3.fromRGB(0, 85, 164),  resource = "Herbs", position = Vector3.new(160, 1, -160)  },
    { id = 3, name = "Emberveil",    color = Color3.fromRGB(170, 21, 27), resource = "Meat",  position = Vector3.new(-160, 1, 160)  },
    { id = 4, name = "Drifthollow",  color = Color3.fromRGB(255, 174, 0), resource = "Logs",  position = Vector3.new(160, 1, 160)   },
}

Config.INITIAL_WEALTH         = 1000
Config.TICK_DURATION          = 12      -- seconds per trading season
Config.MAX_TICKS              = 24

Config.BASE_EXPORT_INCOME     = 95      -- base gold per trade route
Config.RESOURCE_BONUS         = 35      -- bonus when resource is demanded
Config.IMPORT_SPEND_RATIO     = 0.55

Config.TARIFF_RATE            = 0.50
Config.TARIFF_START_TICK      = 2
Config.RETALIATION_DELAY      = 1

Config.INITIAL_TRADE_SHIPS    = 2
Config.INITIAL_WARSHIPS       = 1
Config.WARSHIP_COST_PER_TICK  = 30
Config.PLUNDER_SUCCESS_RATE   = 0.45
Config.PLUNDER_AMOUNT         = 85
Config.MAX_WARSHIPS           = 8

Config.ARMS_RACE_ALPHA        = 1.25
Config.ARMS_RACE_BETA         = 15

Config.FREE_TRADE_BONUS       = 0.40

-- Degradation thresholds
Config.DEGRADE_THRESHOLD_STRUGGLING       = 600
Config.DEGRADE_THRESHOLD_CRITICAL         = 250
Config.DEGRADE_THRESHOLD_BANKRUPT         = 100

-- Degradation effects
Config.DEGRADE_MIN_TRADE_SHIPS            = 1
Config.DEGRADE_CONSEC_TICKS_FOR_SHIP_LOSS = 2
Config.DEGRADE_DESERTION_CHANCE           = 0.50
Config.DEGRADE_SHIP_LOSS_CHANCE_CRITICAL  = 0.40
Config.DEGRADE_SHIP_LOSS_CHANCE_BANKRUPT  = 0.65

-- Export income multipliers per degradation level
Config.DEGRADE_EXPORT_PENALTY_STRUGGLING  = 0.80
Config.DEGRADE_EXPORT_PENALTY_CRITICAL    = 0.55
Config.DEGRADE_EXPORT_PENALTY_BANKRUPT    = 0.30

Config.OCEAN_SIZE   = Vector3.new(520, 2, 520)
Config.ISLAND_SIZE  = Vector3.new(60, 14, 60)
Config.SHIP_SPEED   = 45

Config.SCENARIOS = { MERCANTILIST = "mercantilist", FREE_TRADE = "freetrade" }

-- ─── Privateer System ─────────────────────────────────────────────────────────
Config.PRIVATEER_COMMISSION_COST  = 120
Config.PRIVATEER_SUCCESS_RATE     = 0.55
Config.PRIVATEER_PLUNDER_AMOUNT   = 65

-- ─── Sabotage System ─────────────────────────────────────────────────────────
Config.SABOTAGE_COST              = 70
Config.SABOTAGE_ATTEMPT_CHANCE    = 0.28
Config.SABOTAGE_SUCCESS_RATE      = 0.55

-- ─── Diplomacy ────────────────────────────────────────────────────────────────
Config.ALLIANCE_TRADE_BONUS       = 0.30
Config.EMBARGO_TRADE_MULTIPLIER   = 0.0

-- ─── Relationship System ─────────────────────────────────────────────────────
-- Bilateral relationship score drives interactions (not just internal state)
Config.RELATION_INITIAL          = 50   -- neutral starting point (0-100 scale)
Config.RELATION_ALLIANCE_THRESHOLD = 75  -- above this → can form alliance
Config.RELATION_EMBARGO_THRESHOLD  = 25  -- below this → can declare embargo
Config.RELATION_RAID_THRESHOLD     = 35  -- below this → more likely to raid
Config.RELATION_TRADE_BONUS_RATE   = 0.003 -- per point above 50, trade gets bonus
Config.RELATION_TRADE_PENALTY_RATE = 0.005 -- per point below 50, trade gets penalty
Config.RELATION_DECAY_RATE         = 1   -- relations drift toward 50 per tick
Config.RELATION_RAID_PENALTY       = -15 -- raiding hurts relations
Config.RELATION_TRADE_BOOST        = 2   -- successful trade improves relations
Config.RELATION_ALLIANCE_BOOST     = 5   -- being allied improves relations
Config.RELATION_EMBARGO_DRAIN      = -3  -- embargo worsens relations

-- Resource-need driven diplomacy
Config.RELATION_NEED_SUPPLIER_BOOST   = 4   -- boost toward nation producing resource we urgently need
Config.RELATION_NEED_EMBARGO_PENALTY  = -6  -- extra penalty when embargoed by a needed supplier
Config.RELATION_NEED_FULFILLED_BOOST  = 3   -- boost when a supplier actually delivered what we needed
Config.RELATION_NEED_DESPERATE_RAID   = -8  -- worsens relations with hoarders (saturated, won't share)

-- ─── Random Market Events ───────────────────────────────────────────────────
Config.EVENT_CHANCE_PER_TICK      = 0.40
Config.EVENT_GOLD_RUSH_BONUS      = 250
Config.EVENT_PLAGUE_LOSS          = 200
Config.EVENT_STORM_SHIP_LOSS      = true
Config.EVENT_MARKET_BOOM_MULT     = 1.60
Config.EVENT_MARKET_CRASH_MULT    = 0.40

return Config

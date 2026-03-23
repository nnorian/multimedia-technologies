# Mercantilism Simulation — Economic Model & Interaction Rules

## Overview

This document describes the complete economic model implemented in the simulation. The system models four competing nations in a mercantilist trade environment, comparing it against a free-trade alternative. Each nation produces one raw resource, trades with others, builds navies, forms alliances, imposes tariffs, and engages in espionage — all driven by bilateral relationship scores.

The simulation runs **24 ticks** (trading seasons) per scenario, with each tick lasting **12 seconds** of real time.

---

## 1. Nations

| Nation | Primary Resource | Color | Starting Position |
|---|---|---|---|
| Ironhaven | Ore | Dark blue `(0, 36, 125)` | (-160, 1, -160) |
| Goldspire | Herbs | Blue `(0, 85, 164)` | (160, 1, -160) |
| Emberveil | Meat | Red `(170, 21, 27)` | (-160, 1, 160) |
| Drifthollow | Logs | Amber `(255, 174, 0)` | (160, 1, 160) |

**Starting conditions per nation:**
- Wealth: **1,000g**
- Trade ships: **2**
- Warships: **1**
- Own resource stock: **70 units** (70% of max)
- Other resources stock: **40 units each**
- Economy tier: **RAW** (tier 1)
- All bilateral relationships: **50** (neutral)

---

## 2. Resource System

### 2.1 Resource Types

Four raw resources exist: **Meat**, **Logs**, **Ore**, **Herbs**. Each nation is the sole producer of one resource and must acquire the other three through trade.

### 2.2 Production & Consumption (per tick)

| Parameter | Value |
|---|---|
| Own resource production | +15 units |
| Consumption of each resource | -8 units |
| Maximum stock (saturation) | 100 units |
| Minimum need threshold (urgent) | 20 units |

Each tick, a nation produces 15 units of its own resource (capped at 100) and consumes 8 units of all four resources. This creates a structural **deficit of 8 units per tick** for each of the three non-produced resources, forcing nations to trade.

### 2.3 Buying Behavior

A nation's import demand is determined by its current stock levels:

| Stock Level | Buying Behavior | Price Modifier |
|---|---|---|
| **< 20** (urgent) | Actively seeks resource, pays premium | **×1.5** (50% premium) |
| **20–99** (normal need) | Willing to buy at market price | ×1.0 |
| **≥ 100** (saturated) | Will **not buy** — trade route blocked | N/A |

A nation never buys its own primary resource (it produces it).

### 2.4 Trade Amount

Each trade ship delivers **12 units** of resource per route per tick, limited by the seller's available stock. Ships are divided equally among trade partners:

```
units_delivered = min(12 × (trade_ships / num_partners), seller_stock)
```

---

## 3. Economy Tiers (Production Progression)

Nations progress through three economy tiers as their wealth grows:

| Tier | Name | Wealth Threshold | Unlocks | Price Multiplier |
|---|---|---|---|---|
| 1 | **RAW** | 0g (start) | Raw resource exports only | ×1.0 |
| 2 | **MANUFACTURE** | ≥ 1,400g | Manufactured goods production | ×2.2 |
| 3 | **TECHNOLOGY** | ≥ 2,200g | Technology production | ×4.0 |

### Tier Rules

- **Manufactured goods** (tier 2): Sold to any trade partner whose economy tier is **lower than MANUFACTURE**. Represents value-added processing of raw materials.
- **Technology** (tier 3): Sold **only to allied nations**. Represents advanced knowledge transfer that requires trust. This creates a strong incentive to maintain alliances at higher economic levels.
- Tier is recalculated at the start of each tick based on current wealth. If wealth drops below a threshold, the nation **regresses** to a lower tier.

---

## 4. Wealth Formula

Each tick, a nation's wealth changes according to:

```
W_i(t) = W_i(t-1) + X_i - M_i + P_i - C_i
```

Where:
- **X_i** = export income (gold earned from selling resources and goods)
- **M_i** = import spending (gold spent on buying resources)
- **P_i** = plunder gained (gold seized through naval raiding)
- **C_i** = navy maintenance cost (upkeep of warships)

Wealth cannot go below 0.

---

## 5. Trade System

### 5.1 Export Income Calculation

For each trade partner, export income is calculated as:

```
route_income = base_price × price_multiplier × urgency_premium × relationship_modifier × free_trade_bonus × alliance_bonus × tariff_penalty × degradation_penalty
```

**Base price per route:**
```
base_price = BASE_EXPORT_INCOME / number_of_partners = 95 / 3 ≈ 31.7g
```

**Price multiplier** (by goods type):
| Goods | Multiplier |
|---|---|
| Raw resource | ×1.0 |
| Manufactured goods | ×2.2 |
| Technology | ×4.0 |

**Urgency premium**: ×1.5 when buyer's stock is below 20 units.

**Relationship modifier** (based on bilateral score, neutral = 50):
- Above 50: `income × (1 + (relation - 50) × 0.003)` — up to +15% at relation 100
- Below 50: `income × max(0.3, 1 - (50 - relation) × 0.005)` — up to -25% at relation 0, floored at 70% reduction

**Free trade bonus** (free trade scenario only): ×1.40

**Alliance bonus**: ×1.30 for allied trade partners

**Tariff penalty**: ×0.50 (50% income reduction per active tariff imposed by partner)

**Degradation penalty** (based on nation health):
| Level | Penalty |
|---|---|
| Healthy | ×1.00 |
| Struggling | ×0.80 |
| Critical | ×0.55 |
| Bankrupt | ×0.30 |

### 5.2 Import Spending

```
imports = exports × IMPORT_SPEND_RATIO = exports × 0.55
```

If the nation has active tariffs (mercantilist only), import costs are further reduced:
```
reduction = TARIFF_RATE × active_tariff_count × 0.4   (capped at 80%)
imports = imports × (1 - reduction)
```

### 5.3 Embargo Effect

When two nations are in an **embargo** state, **all trade between them is blocked** — both export income and resource transfer on that route are zero (`EMBARGO_TRADE_MULTIPLIER = 0.0`).

---

## 6. Bilateral Relationship System

### 6.1 Structure

Every pair of nations has a **symmetric** relationship score on a 0–100 scale, initialized at **50** (neutral). This score drives all diplomatic, trade, and military decisions.

### 6.2 Relationship Modifiers (per tick)

| Action/Condition | Modifier | When Applied |
|---|---|---|
| Successful trade (per partner) | **+2** | After trade calculation |
| Delivered urgently needed resource | **+3** | When partner's stock < 40 for delivered resource |
| Being allied | **+5** | End of tick, per allied pair |
| Urgently need partner's resource (stock < 20) | **+4** | After production/consumption |
| Moderately low stock (< 40) of partner's resource | **+1** | After production/consumption |
| Raiding/plundering a nation | **-15** | After successful plunder |
| Imposing a tariff | **-8** | When tariff is set |
| Embargo active | **-3** | End of tick, per embargoed pair |
| Sabotage (successful) | **-20** | After sabotage success |
| Sabotage (failed but uncovered) | **-10** | After sabotage failure |
| Embargoed by needed supplier | **-6** | When stock < 20 and embargoed by supplier |
| Both saturated, not allied | **-1** | When both nations have stock ≥ 90 of each other's resource |
| Natural decay | **±1 toward 50** | End of tick, all pairs |

### 6.3 Relationship Thresholds

| Threshold | Value | Effect |
|---|---|---|
| Alliance formation | **≥ 75** (or ≥ 60 if needing partner's resource) | Can form commercial treaty |
| Embargo declaration | **≤ 25** | Can declare trade embargo |
| Raid threshold | **< 35** | More likely to commission privateers |
| Tariff threshold | **< 60** | Will impose tariffs on this partner |

---

## 7. Diplomacy System

Diplomatic AI evaluates every **2 ticks** starting from **tick 3** (mercantilist scenario only). Decisions are deterministic thresholds with probabilistic execution.

### 7.1 Alliance Formation

**Conditions**: Relation ≥ 75 (or ≥ 60 if urgently needing partner's resource) AND current state is NEUTRAL.

**Probability**: 35% per evaluation.

**Effects**:
- State changes to ALLIED for both nations
- Relations boosted by +10
- Alliance trade bonus (+30%) applied to route
- Technology exports (tier 3) unlocked on route

### 7.2 Embargo Declaration

**Conditions**: Relation ≤ 25 AND current state is NEUTRAL AND nation does **not** urgently need partner's resource.

**Probability**: 40% per evaluation.

**Effects**:
- State changes to EMBARGO for both nations
- Relations worsened by -10
- All trade on that route blocked (0 income, 0 resource transfer)

**Resource dependency override**: If the nation urgently needs the partner's resource (stock < 20), the embargo is **blocked** regardless of relationship score. The simulation logs this as "too dependent on supply."

### 7.3 Alliance Breakdown

**Conditions**: Current state is ALLIED AND (relation < 55, OR partner's wealth > 1.8× own wealth with 35% chance).

**Resource dependency modifier**: If urgently needing partner's resource, the break threshold drops to **40** instead of 55, making alliances with needed suppliers harder to break.

**Effects**:
- State reverts to NEUTRAL
- No direct relation change (but loss of +5/tick alliance boost)

### 7.4 Embargo Lifting

**Conditions**: Current state is EMBARGO AND relation > 40.

**Probability**: 30% per evaluation.

**Resource dependency modifier**: If urgently needing partner's resource:
- Probability increases to **55%**
- Threshold drops to relation > **20**
- Logged as "desperate for [resource]!"

**Effects**:
- State reverts to NEUTRAL
- Relations boosted by +5

---

## 8. Tariff System

### 8.1 Tariff Imposition (Mercantilist Only)

A nation imposes tariffs when:
1. Its trade balance is **negative** (imports > exports)
2. The target partner's relationship score is **< 60**
3. Current tick ≥ **2** (TARIFF_START_TICK)

### 8.2 Retaliation

When a nation has a tariff imposed on it, it retaliates after a **1-tick delay** by imposing a reciprocal tariff.

### 8.3 Tariff Effects

- Tariff reduces the imposing nation's **import costs** (beneficial)
- Tariff reduces the **export income** of the partner trading into that nation by 50%
- Tariff imposition damages relations by **-8**

---

## 9. Naval System

### 9.1 Fleet Composition

| Ship Type | Starting Count | Max | Function |
|---|---|---|---|
| Trade ships | 2 | No hard cap | Generate export income, carry resources |
| Warships | 1 | 8 | Raid enemy trade for plunder, cost maintenance |

### 9.2 Plunder (Mercantilist Only)

Each warship has a **45% chance per tick** to intercept a rival's trade ship:
```
if random() ≤ 0.45 AND victim.tradeShips > 0:
    amount = min(85g, victim.wealth)
    victim.wealth  -= amount
    attacker.wealth += amount
```

**Relationship impact**: Each successful raid applies **-15** to bilateral relations.

### 9.3 Arms Race (Richardson Model)

Warship buildup follows the Richardson arms race model:
```
C_target = 1.25 × max_rival_naval_cost + 15
target_warships = floor(C_target / WARSHIP_COST_PER_TICK)
```

A nation builds **+1 warship per tick** toward this target, capped at 8, only if it can afford it (wealth > 5× warship cost).

### 9.4 Naval Maintenance Cost

**Mercantilist**: `cost = warships × 30g per tick`

**Free Trade**: `cost = 15g per tick` (fixed baseline, no warship maintenance)

---

## 10. Privateer System (Mercantilist Only)

### 10.1 Commission

A nation commissions privateers when:
1. It has **0 active privateers**
2. Its worst bilateral relationship is **< 35**
3. Its wealth > **180g** (1.5× commission cost)

**Probability**: 35% per evaluation.

**Count**: `min(3, floor(wealth / 180))`, minimum 1.

**Cost**: **120g per privateer**.

### 10.2 Resolution

Each privateer attacks non-allied nations:
- **Base success rate**: 55%
- **Against embargoed targets**: 55% × 1.4 = **77%**
- **Plunder per success**: min(65g, victim's wealth)

### 10.3 Key Differences from Regular Plunder

| | Regular Plunder | Privateer Raids |
|---|---|---|
| Requires | Warships | Commissioned privateers |
| Success rate | 45% | 55% (77% vs embargoed) |
| Amount per hit | 85g | 65g |
| Targets | All rivals | Non-allied nations only |
| Cost | 30g/tick maintenance | 120g one-time per corsair |

---

## 11. Sabotage System (Mercantilist Only)

### 11.1 Conditions

A nation attempts sabotage when:
1. Its wealth ≥ **210g** (3× sabotage cost)
2. Target has the **worst relationship** with attacker (below 40)
3. Target has **> 1 trade ship**

**Attempt probability**: 28% per tick.
**Cost**: 70g per operation.

### 11.2 Outcomes

| Outcome | Probability | Effect |
|---|---|---|
| **Success** | 55% | Target loses 1 trade ship, relations -20 |
| **Failure** | 45% | 70g wasted, relations -10 |

---

## 12. Degradation System

### 12.1 Degradation Levels

| Level | Wealth Threshold | Effects |
|---|---|---|
| **Healthy** | ≥ 600g | No penalties |
| **Struggling** | 250–599g | Export penalty ×0.80; lose trade ship after 2 consecutive negative ticks |
| **Critical** | 100–249g | Export penalty ×0.55; 50% chance to lose warship; 40% chance to lose trade ship |
| **Bankrupt** | < 100g | Export penalty ×0.30; 65% chance to lose trade ship; 65% chance to lose warship |

Trade ships cannot drop below **1** (minimum fleet).

### 12.2 Visual Effects

Island base color changes with degradation:
| Level | Color |
|---|---|
| Healthy | Lush green |
| Struggling | Sandy yellow |
| Critical | Dry brown |
| Bankrupt | Ash grey (+ 18% transparency) |

---

## 13. Random Market Events

Each tick has a **40% chance** of triggering one random event affecting one random nation:

| Event | Effect |
|---|---|
| **Gold Rush** | +250g windfall |
| **Plague** | Lose min(200g, 30% of wealth) |
| **Great Storm** | Lose 1 trade ship (or 15% wealth if only 1 ship); plays sinking animation |
| **Market Boom** | +25% of current wealth |
| **Market Crash** | -25% of current wealth |
| **Mutiny** | Lose 1 warship (if > 1) |
| **Trade Wind** | Gain 1 trade ship (if < 5) or +100g |

---

## 14. Scenario Comparison

The simulation runs two scenarios back-to-back:

### 14.1 Mercantilist Scenario

All systems are active:
- Tariffs, retaliation
- Naval plunder, arms race
- Diplomacy (alliances, embargoes)
- Privateers, sabotage
- Resource-need-driven relations

### 14.2 Free Trade Scenario

Cooperative trade environment:
- **No tariffs**
- **No plunder** (plunder resolution returns empty)
- **No privateers** (privateer resolution returns empty)
- **No sabotage** (sabotage resolution skipped)
- **No diplomatic decisions** (no alliances, embargoes)
- **+40% export income bonus** (free trade multiplier)
- **Fixed 15g naval cost** (no warship maintenance)
- Resource production, consumption, trade, and saturation still active

### 14.3 Expected Outcome

Free trade should produce **higher total global wealth** (positive-sum trade) but the mercantilist scenario creates more interesting dynamics with winners and losers, demonstrating the core tension of mercantilist economic theory.

---

## 15. Tick Execution Order

Each tick executes the following steps in order:

1. **Update economy tiers** — check wealth thresholds for all nations
2. **Produce & consume resources** — +15 own resource, -8 all resources
3. **Resource-need relationship adjustments** — boost relations with needed suppliers, penalize embargo by needed supplier
4. **Animate ships** — visual movement of trade ships and warships
5. **Random market events** — 40% chance of one event
6. **Tariff decisions** — AI evaluates tariff policy (mercantilist only)
7. **Diplomatic decisions** — alliance/embargo/privateer commission (mercantilist only, every 2 ticks from tick 3)
8. **Calculate trade** — export/import for all nations, transfer resources, relationship boosts for successful trade
9. **Resolve plunder** — warship raids with explosion animations
10. **Resolve privateers** — corsair interceptions
11. **Resolve sabotage** — harbour sabotage attempts
12. **Update navy sizes** — arms race (Richardson model)
13. **Relationship maintenance** — alliance boost, embargo drain, natural decay
14. **Apply wealth changes** — W(t) = W(t-1) + exports - imports + plunder - navy cost
15. **Apply degradation** — check thresholds, apply fleet losses
16. **Record data** — snapshot for statistical analysis
17. **Broadcast state** — send updated data to all clients

---

## 16. Data Collection & Analysis

The simulation records two datasets:

### 16.1 Per-Tick Snapshots (CSV)

Columns: `scenario, tick, nation, wealth, wealth_delta, exports, imports, plunder_gained, plunder_lost, navy_cost, trade_ships, warships, degradation_level, tariff_count, alliance_count, embargo_count, privateer_count, economy_tier`

### 16.2 Event Log (CSV)

Columns: `scenario, tick, event_type, actor, target, detail, amount`

Event types: `random_event, plunder, alliance_formed, embargo_declared, alliance_broken, embargo_lifted, privateer_commissioned, privateer_raid, sabotage_success, sabotage_failed`

### 16.3 Computed Aggregates

1. **Tariff-wealth correlation** — average wealth delta with vs without active tariffs
2. **Alliance trade impact** — average exports with vs without active alliances
3. **Arms race burden** — total navy cost as percentage of total exports
4. **Random event distribution** — count of each event type per scenario
5. **Plunder & privateer totals** — per-nation, per-scenario gains and losses
6. **Scenario comparison** — total global wealth, average nation wealth, total exports, total navy cost
7. **Gini coefficient** — wealth inequality measure (0 = perfect equality, 1 = total inequality)
8. **Per-nation final wealth** — comparison across scenarios

---

## 17. Constants Reference

### Economy
| Constant | Value | Description |
|---|---|---|
| `INITIAL_WEALTH` | 1,000g | Starting treasury |
| `BASE_EXPORT_INCOME` | 95g | Base gold per tick from all routes combined |
| `RESOURCE_BONUS` | 35g | Bonus when resource is in demand |
| `IMPORT_SPEND_RATIO` | 0.55 | Imports = 55% of exports |
| `FREE_TRADE_BONUS` | 0.40 | +40% export income in free trade |

### Resources
| Constant | Value | Description |
|---|---|---|
| `RESOURCE_MIN_NEED` | 20 | Below this = urgent buyer |
| `RESOURCE_MAX_STOCK` | 100 | Above this = saturated |
| `RESOURCE_START_STOCK` | 40 | Starting stock per resource |
| `RESOURCE_OWN_PRODUCTION` | 15 | Own resource produced per tick |
| `RESOURCE_CONSUMPTION` | 8 | Each resource consumed per tick |
| `RESOURCE_URGENT_PREMIUM` | 1.5 | 50% price premium for urgent buys |
| `RESOURCE_TRADE_AMOUNT` | 12 | Units per trade ship per route |

### Economy Tiers
| Constant | Value | Description |
|---|---|---|
| `TIER_THRESHOLD_MANUFACTURE` | 1,400g | Wealth to unlock tier 2 |
| `TIER_THRESHOLD_TECHNOLOGY` | 2,200g | Wealth to unlock tier 3 |
| `RAW_PRICE` | 1.0 | Raw goods multiplier |
| `MANUFACTURED_PRICE` | 2.2 | Manufactured goods multiplier |
| `TECHNOLOGY_PRICE` | 4.0 | Technology multiplier |

### Military
| Constant | Value | Description |
|---|---|---|
| `INITIAL_TRADE_SHIPS` | 2 | Starting trade ships |
| `INITIAL_WARSHIPS` | 1 | Starting warships |
| `WARSHIP_COST_PER_TICK` | 30g | Maintenance per warship per tick |
| `PLUNDER_SUCCESS_RATE` | 0.45 | Raid success chance per warship |
| `PLUNDER_AMOUNT` | 85g | Gold seized per successful raid |
| `MAX_WARSHIPS` | 8 | Maximum warships per nation |
| `ARMS_RACE_ALPHA` | 1.25 | Richardson model coefficient |
| `ARMS_RACE_BETA` | 15 | Richardson model constant |

### Privateers
| Constant | Value | Description |
|---|---|---|
| `PRIVATEER_COMMISSION_COST` | 120g | Cost per privateer |
| `PRIVATEER_SUCCESS_RATE` | 0.55 | Base interception chance |
| `PRIVATEER_PLUNDER_AMOUNT` | 65g | Gold per privateer success |

### Sabotage
| Constant | Value | Description |
|---|---|---|
| `SABOTAGE_COST` | 70g | Operation cost |
| `SABOTAGE_ATTEMPT_CHANCE` | 0.28 | Probability of attempt per tick |
| `SABOTAGE_SUCCESS_RATE` | 0.55 | Success probability |

### Diplomacy
| Constant | Value | Description |
|---|---|---|
| `ALLIANCE_TRADE_BONUS` | 0.30 | +30% trade on allied routes |
| `EMBARGO_TRADE_MULTIPLIER` | 0.0 | Complete trade block |
| `TARIFF_RATE` | 0.50 | 50% income reduction per tariff |
| `TARIFF_START_TICK` | 2 | Earliest tick for tariff imposition |
| `RETALIATION_DELAY` | 1 | Ticks before retaliatory tariff |

### Relationships
| Constant | Value | Description |
|---|---|---|
| `RELATION_INITIAL` | 50 | Starting relationship score |
| `RELATION_ALLIANCE_THRESHOLD` | 75 | Score needed for alliance |
| `RELATION_EMBARGO_THRESHOLD` | 25 | Score threshold for embargo |
| `RELATION_RAID_THRESHOLD` | 35 | Score below which raids happen |
| `RELATION_TRADE_BONUS_RATE` | 0.003 | Trade bonus per point above 50 |
| `RELATION_TRADE_PENALTY_RATE` | 0.005 | Trade penalty per point below 50 |
| `RELATION_DECAY_RATE` | 1 | Drift toward 50 per tick |
| `RELATION_RAID_PENALTY` | -15 | Relation hit from raiding |
| `RELATION_TRADE_BOOST` | +2 | Relation gain from trading |
| `RELATION_ALLIANCE_BOOST` | +5 | Relation gain from being allied |
| `RELATION_EMBARGO_DRAIN` | -3 | Relation loss from embargo |
| `RELATION_NEED_SUPPLIER_BOOST` | +4 | Boost toward needed supplier |
| `RELATION_NEED_EMBARGO_PENALTY` | -6 | Extra penalty when embargoed by supplier |
| `RELATION_NEED_FULFILLED_BOOST` | +3 | Boost when supplier delivers needed resource |
| `RELATION_NEED_DESPERATE_RAID` | -8 | Penalty toward hoarding nations |

### Degradation
| Constant | Value | Description |
|---|---|---|
| `DEGRADE_THRESHOLD_STRUGGLING` | 600g | Below this = struggling |
| `DEGRADE_THRESHOLD_CRITICAL` | 250g | Below this = critical |
| `DEGRADE_THRESHOLD_BANKRUPT` | 100g | Below this = bankrupt |
| `DEGRADE_EXPORT_PENALTY_STRUGGLING` | 0.80 | 20% export reduction |
| `DEGRADE_EXPORT_PENALTY_CRITICAL` | 0.55 | 45% export reduction |
| `DEGRADE_EXPORT_PENALTY_BANKRUPT` | 0.30 | 70% export reduction |

### Random Events
| Constant | Value | Description |
|---|---|---|
| `EVENT_CHANCE_PER_TICK` | 0.40 | 40% chance per tick |
| `EVENT_GOLD_RUSH_BONUS` | 250g | Gold rush windfall |
| `EVENT_PLAGUE_LOSS` | 200g | Maximum plague damage |

---

## 18. Academic Framework

### Economic Theories Modeled

| Simulation Mechanic | Economic Concept | Academic Source |
|---|---|---|
| Tariff → retaliation cascade | Trade war / Nash equilibrium | Nash (1950); Smoot-Hawley Tariff Act (1930) |
| Free trade raises global wealth | Positive-sum trade theory | Adam Smith, *Wealth of Nations* (1776), Book IV |
| Resource specialization & trade | Comparative advantage | David Ricardo, *Principles of Political Economy* (1817), Ch. 7 |
| Arms race formula | Richardson arms race model | Lewis F. Richardson, *Arms and Insecurity* (1960) |
| Privateer / alliance / embargo AI | Iterated Prisoner's Dilemma | Robert Axelrod, *The Evolution of Cooperation* (1984) |
| Tariff deadweight loss | Consumer/producer surplus loss | Paul Samuelson, *Economics* (1948) |
| Resource dependency shaping alliances | Interdependence theory | Robert Keohane & Joseph Nye, *Power and Interdependence* (1977) |
| Gini coefficient measurement | Wealth inequality | Corrado Gini, *Variabilità e mutabilità* (1912) |

### Historical Parallels

| Mechanic | Historical Event |
|---|---|
| Tariff + retaliation | Navigation Acts 1651/1660 (England vs Netherlands) |
| Naval arms race | Anglo-Dutch Wars 1652–1674 |
| Privateer commission | Francis Drake's Letters of Marque (1577); Jean Bart (1690s) |
| Harbour sabotage | Dutch Medway Raid 1667 |
| Embargo declaration | Navigation Acts excluding Dutch carriers |
| Alliance + trade bonus | Cobden-Chevalier Treaty 1860; Anglo-Portuguese Treaty 1386 |
| Mercantilist policy | Jean-Baptiste Colbert's France under Louis XIV (1661–1683) |
| Trade company monopoly | VOC (Dutch East India Company) joint-stock trade |
| Resource dependency diplomacy | British dependence on Baltic timber for naval shipbuilding |

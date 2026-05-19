# Mercantilism Simulation — Economic Model

> **Version:** v5.3 | **Last updated:** 2026-04-08
> All constants reflect the current `GameConfig.lua`. Outdated values are noted where relevant.

---

## Table of Contents

1. [Overview](#1-overview)
2. [Nations](#2-nations)
3. [Tick Execution Order](#3-tick-execution-order)
4. [Wealth Formula](#4-wealth-formula)
5. [Resource System](#5-resource-system)
6. [Economy Tier System](#6-economy-tier-system)
7. [Trade System](#7-trade-system)
8. [Relationship System](#8-relationship-system)
9. [Diplomacy System](#9-diplomacy-system)
10. [Tariff System](#10-tariff-system)
11. [Naval & Plunder System](#11-naval--plunder-system)
12. [Privateer System](#12-privateer-system)
13. [Sabotage System](#13-sabotage-system)
14. [Degradation System](#14-degradation-system)
15. [Random Market Events](#15-random-market-events)
16. [State Machines](#16-state-machines)
17. [Scenario Comparison](#17-scenario-comparison)
18. [Data Collection](#18-data-collection)
19. [Constants Reference](#19-constants-reference)
20. [Academic Framework](#20-academic-framework)

---

## 1. Overview

The simulation models four competing IT-sector nations in a **mercantilist** trade environment and compares it against a **free-trade** alternative. Each nation:

- Produces one raw resource and must import the other three through trade
- Builds navies, forms alliances, imposes tariffs, and engages in espionage
- Accumulates wealth through exports, plunder, and economic diplomacy
- Progresses through three economy tiers as wealth grows

The simulation runs **24 ticks** (trading seasons) per scenario, each tick lasting **12 real seconds**. Both scenarios run back-to-back and the final global wealth totals are compared.

**Academic thesis being tested:**
> *Free trade produces higher global wealth (positive-sum) while mercantilism creates winners and losers through zero-sum redistribution.*

---

## 2. Nations

| Nation | Primary Resource | Color | Map Position |
|---|---|---|---|
| **Endava** | Ore | Dark blue `(0, 36, 125)` | Top-left (-160, 1, -160) |
| **Amdaris** | Herbs | Blue `(0, 85, 164)` | Top-right (160, 1, -160) |
| **GridDynamics** | Meat | Red `(170, 21, 27)` | Bottom-left (-160, 1, 160) |
| **Globant** | Logs | Amber `(255, 174, 0)` | Bottom-right (160, 1, 160) |

**Starting state per nation (tick 0):**

| Attribute | Value |
|---|---|
| Wealth | 1,000g |
| Trade ships | 2 |
| Warships | 1 |
| Own resource stock | 70 units |
| Other resource stocks | 40 units each |
| Economy tier | RAW (1) |
| All bilateral relations | 50 (neutral) |
| Diplomatic state with all | NEUTRAL |
| Active tariffs | none |
| Active privateers | 0 |

---

## 3. Tick Execution Order

Every tick the following steps execute **in this exact sequence**:

```
1.  Update economy tiers          (wealth threshold check)
2.  Produce & consume resources   (+20 own, -4 all)
3.  Resource-need relation boosts (warm toward needed suppliers)
4.  Animate ships                 (visual, fire-and-forget)
5.  Random market events          (40% chance)
6.  Tariff AI decisions           (mercantilist only, tick ≥ 2)
7.  Diplomatic AI decisions       (mercantilist only, every 2 ticks from tick 3)
8.  Calculate trade               (exports, imports, resource transfer)
9.  Resolve plunder               (warship raids + explosion animations)
10. Resolve privateers            (corsair interceptions)
11. Resolve sabotage              (harbour sabotage attempts)
12. Update navy sizes             (Richardson arms race)
13. Relationship maintenance      (alliance boost, embargo drain, decay)
14. Apply wealth changes          (W = W + exports - imports + plunder - navy)
15. Apply degradation             (fleet losses, export penalties)
16. Allied foreign aid            (critical/bankrupt ally rescue)
17. Record tick snapshot          (CSV data collector)
18. Broadcast to clients          (WealthUpdated RemoteEvent)
```

---

## 4. Wealth Formula

```
W_i(t) = W_i(t−1) + X_i − M_i + P_i − C_i
```

| Symbol | Meaning |
|---|---|
| `W_i(t)` | Nation i's wealth at end of tick t |
| `X_i` | Export income earned this tick |
| `M_i` | Import spending this tick |
| `P_i` | Plunder gained (raids + privateers) |
| `C_i` | Navy maintenance cost |

Wealth is floored at **0** — nations cannot go negative.

**Note:** Plunder *losses* are applied directly to `nation.wealth` inside `NavalSystem.resolvePlunder()`, before step 14. The `wealth_delta` column in the CSV reflects only *gains* (X − M + P_gained − C); subtract `plunder_lost` from the CSV to get the true net change.

---

## 5. Resource System

### 5.1 Resources

| Resource | Produced by | Cargo Color |
|---|---|---|
| Ore | Endava | Steel-grey |
| Herbs | Amdaris | Green |
| Meat | GridDynamics | Red |
| Logs | Globant | Brown |

### 5.2 Production & Consumption (per tick)

Each tick, **before** trade:

```
own_resource_stock += 20          (capped at 200)
all_4_resources    -= 4 each      (floored at 0)
```

**Net own-stock change per tick:**
```
+20 (production) − 4 (consumption) − 4 × (ships/partners) per partner ≈ +4/tick
```
Own stock grows slowly and never depletes over a 24-tick game.

**Net imported-resource change per tick:**
```
+4 (received from supplier) − 4 (consumption) = 0
```
Imported stocks remain stable at their starting level (~40 units) throughout the game.

### 5.3 Buying Behavior

A nation **will not buy its own primary resource**. For the other three:

| Stock Level | Buying State | Price Modifier |
|---|---|---|
| **< 15** (urgent) | Actively seeks resource | **×1.5** (50% premium) |
| **15 – 199** (normal) | Willing to buy at base price | ×1.0 |
| **≥ 200** (saturated) | Will NOT buy — route income blocked | — |

Saturation at 200 units takes 40+ ticks to reach — beyond the 24-tick game length, so income never collapses from saturation.

### 5.4 Units Transferred per Trade

```
units_delivered = min(RESOURCE_TRADE_AMOUNT × (tradeShips / numPartners), seller_stock)
               = min(6 × (2/3), seller_stock)
               = min(4, seller_stock)
```

The buyer gains up to 4 units per tick per seller. The seller's stock is checked — if stock is 0, no trade occurs and **the route income floor applies instead** (see §7.2).

---

## 6. Economy Tier System

### 6.1 Tiers

| Tier | Name | Wealth Required | Exports | Price Multiplier |
|---|---|---|---|---|
| 1 | **RAW** | 0g | Raw resources only | ×1.0 |
| 2 | **MANUFACTURE** | ≥ 1,400g | Raw + Manufactured goods | ×2.2 on MFG |
| 3 | **TECHNOLOGY** | ≥ 2,200g | Raw + MFG + Technology | ×4.0 on TECH |

### 6.2 Rules

- **Manufactured goods** sell to any partner with `economyTier < MANUFACTURE`. Scaled by `shipsPerRoute`.
- **Technology** sells **only to allied partners**. Restricted because advanced knowledge transfer requires diplomatic trust.
- Tier is **recalculated every tick**. A wealth drop below a threshold causes **immediate regression**.

### 6.3 Tier State Machine

```
        wealth ≥ 1400g              wealth ≥ 2200g
RAW ──────────────────→ MANUFACTURE ──────────────────→ TECHNOLOGY
 ↑                           |                               |
 └───────────────────────────┘ wealth < 1400g                │
 ↑                                                           │
 └───────────────────────────────────────────────────────────┘
                            wealth < 1400g
```

Regression is instant — there is no hysteresis. A nation at 2,205g that loses 10g regresses from TECHNOLOGY to MANUFACTURE on the next tick.

---

## 7. Trade System

### 7.1 Export Income Formula

For each non-embargoed partner:

```
route_income =
  base_price
  × urgency_premium      (if partner urgently needs your resource)
  × [+ manufactured_price × shipsPerRoute]   (if tier ≥ 2)
  × [+ technology_price  × shipsPerRoute]    (if tier ≥ 3 AND allied)
  × relationship_modifier
  × free_trade_multiplier
  × alliance_bonus
  × (1 − tariff_penalty) if partner has tariff on you
  × distance_efficiency
```

Then, after all routes are summed:
```
total_exports = sum(route_incomes) × degradation_penalty
```

**Base price per route:**
```
base_price = BASE_EXPORT_INCOME / num_partners = 160 / 3 ≈ 53.3g
```
This is earned **only when** the partner needs your resource (`need.resource == nation.resource`). If no resource need exists, the floor applies (see §7.2).

**Multipliers summary:**

| Factor | Value | Condition |
|---|---|---|
| Urgency premium | ×1.5 | Partner stock < 15 |
| Manufactured goods | base × 2.2 × shipsPerRoute | Seller tier ≥ 2, buyer tier < 2 |
| Technology | base × 4.0 × shipsPerRoute | Seller tier ≥ 3 AND allied |
| Relationship bonus | ×(1 + (rel−50) × 0.003) | Relation > 50; max +15% at 100 |
| Relationship penalty | ×max(0.3, 1−(50−rel)×0.005) | Relation < 50; max −35% at 0 |
| Free trade bonus | ×1.65 | Free trade scenario only |
| Alliance bonus | ×1.30 | Allied diplomatic state |
| Tariff penalty | ×0.50 | Partner has active tariff on you |
| Distance efficiency | 1/(1 + dist/320 × 0.3) | Always; ~0.77 adjacent, ~0.70 diagonal |
| Degradation penalty | ×0.80/0.55/0.30 | Struggling/Critical/Bankrupt |

### 7.2 Route Income Floor

When `routeIncome == 0` (no resource demand, not embargoed):
```
routeIncome = BASE_ROUTE_INCOME_FLOOR × shipsPerRoute = 10 × (2/3) ≈ 6.7g
```
This models base commerce (services, luxury goods) that happens even when primary goods aren't traded. Modifiers (distance, tariff, relationship) still apply afterward.

### 7.3 Import Spending

```
imports = exports × IMPORT_SPEND_RATIO = exports × 0.55
```

If the nation has active tariffs (mercantilist only), import costs decrease:
```
reduction = min(0.80, TARIFF_RATE × tariff_count × 0.4)
imports   = imports × (1 − reduction)
```

### 7.4 Trade Net (typical healthy nation, RAW tier)

```
exports ≈ 53.3 × 3 routes × 0.74 distance = ~118g
imports ≈ 118 × 0.55                        = ~65g
navy    = 1 warship × 30g                   = ~30g
net     = 118 − 65 − 30                     = +23g/tick   (mercantilist)

free trade: exports × 1.65 ≈ 195g; imports ≈ 107g; navy = 20g (flat)
net = 195 − 107 − 20 = +68g/tick
```

---

## 8. Relationship System

### 8.1 Structure

Every pair (A, B) has **two independent scores**: `A→B` and `B→A`, both on a 0–100 scale, initialized at **50** (neutral).

- `getRelationFrom(A, B)` → A's view of B (used for A's own diplomatic decisions)
- `getRelation(A, B)` → average of both directions (used for trade modifiers and display)

### 8.2 Modifiers per Tick

**Symmetric** (both directions change equally):

| Event | Delta | When |
|---|---|---|
| Successful trade with partner | **+3** | After trade calculation |
| Delivered urgently needed resource | **+3** | Stock < 30 of delivered resource |
| Being allied | **+5** | End-of-tick maintenance |
| Urgently needs partner's resource (stock < 15) | **+4** | After production step |
| Moderately low stock (< 30) of partner's resource | **+1** | After production step |
| Embargo active | **−1** | End-of-tick maintenance |
| Embargoed by needed supplier | **−6** | When stock < 15 + embargoed |
| Both saturated + not allied | **−1** | When both stocks ≥ 180 |
| Allied foreign aid given | **+8** | After aid transfer |
| Natural decay toward 50 | **±1/tick** | Each direction independently |

**Asymmetric** (aggressor and victim feel differently):

| Event | Aggressor (A→B) | Victim (B→A) | When |
|---|---|---|---|
| Raid / plunder | **−3** | **−10** | After successful plunder |
| Sabotage (success) | **−8** | **−30** | After sabotage success |
| Sabotage (fail, uncovered) | **−8** | **−15** | After sabotage failure |
| Tariff imposed | **−3** | **−12** | When tariff is set |

### 8.3 Thresholds

| Threshold | Value | Unlocks |
|---|---|---|
| Alliance formation | ≥ **75** (or ≥ 60 if needing partner's resource) | Commercial treaty |
| Embargo declaration | ≤ **22** | Trade embargo |
| Privateer commission trigger | < **30** | Corsair commissioning |
| Tariff trigger | partner wealth > own × **1.15** AND relation < 60 | Tariff imposition |

### 8.4 Net Balance Analysis

At neutral (50) with active trade, no raids:
```
+3 (trade) − 1 (decay above 50) = +2/tick  →  relations rise toward alliance
```

Under raids (0.20 hit rate × −10 victim penalty):
```
+3 (trade) − 2 (expected raid damage) − 1 (decay) = 0/tick  →  stable near 50
```

Under sustained raiding + tariff imposition:
```
−2 (raids) − 12 (tariff) − 1 (decay) = −15 in tariff tick → can reach 22 (embargo) in ~2 tariff cycles
```

---

## 9. Diplomacy System

Diplomatic AI evaluates every **2 ticks** starting from **tick 3** (mercantilist only).

### 9.1 Diplomatic States

Each nation pair has one state: **NEUTRAL**, **ALLIED**, or **EMBARGO**.

### 9.2 Alliance Formation

**Trigger**: State = NEUTRAL, `getRelationFrom(self, partner) ≥ 75`
(threshold drops to 60 if urgently needing partner's resource)

**Probability**: 35% per evaluation cycle.

**Effects**:
- Both sides → ALLIED
- Relations +10 (symmetric)
- Alliance trade bonus (+30%) applied to route
- Technology exports unlocked on this route

### 9.3 Embargo Declaration

**Trigger**: State = NEUTRAL, `getRelationFrom(self, partner) ≤ 22`

**Blocked if**: Nation urgently needs partner's resource (stock < 15)

**Probability**: 15% per evaluation cycle.

**Effects**:
- Both sides → EMBARGO
- Relations −10 (symmetric)
- All trade on this route blocked (0 income, 0 resource transfer)

### 9.4 Alliance Breakdown

**Trigger**: State = ALLIED AND (`getRelationFrom < 55` OR `partner.wealth > own.wealth × 1.8` with 35% chance)

**Resource dependency**: If urgently needing partner's resource, breakdown threshold drops to 40 (harder to break).

**Effects**: Both sides → NEUTRAL (no relation change).

### 9.5 Embargo Lifting

**Trigger**: State = EMBARGO AND `getRelationFrom > 40`
(threshold drops to 20 if urgently needing partner's resource)

**Probability**: 30% (or 55% if desperately needing partner's resource).

**Effects**: Both sides → NEUTRAL. Relations +5.

### 9.6 Privateer Commission

**Trigger**: 0 active privateers, worst bilateral relation < 30, wealth > 180g.

**Probability**: 35%.

**Count**: `min(3, floor(wealth / 180))`, minimum 1.
**Cost**: 120g per privateer.

---

## 10. Tariff System

### 10.1 Imposition (Mercantilist only, tick ≥ 2)

A nation imposes a tariff on a rival when **both** conditions hold:
1. `rival.wealth > nation.wealth × 1.15` — rival has 15%+ more wealth (competitive protectionism)
2. `getRelationFrom(self, rival) < 60` — relations are strained

This models the historical mercantilist response: protect domestic industry when falling behind a wealthier competitor.

> **Previous behavior (before v5.3):** Tariff fired when `tradeBalance < 0`. Since `imports = exports × 0.55` always, trade balance is always positive — tariffs **never fired**. This was a bug.

### 10.2 Retaliation

When a tariff is imposed, the victim retaliates after **1 tick** by imposing a reciprocal tariff. This creates a tariff war cascade:

```
Tick N:   Endava → tariff on Amdaris     (Amdaris relation drops −12)
Tick N+1: Amdaris → tariff on Endava     (retaliation)
          Both nations lose 50% of mutual trade income
```

### 10.3 Effects

- The imposing nation's **import costs** decrease (beneficial for the imposer)
- The partner's **export income** from this route drops by 50%
- Relations: imposer −3, target −12 (asymmetric)

---

## 11. Naval & Plunder System

### 11.1 Fleet

| Type | Start | Max | Cost/tick |
|---|---|---|---|
| Trade ships | 2 | unlimited* | 0 |
| Warships | 1 | **4** | **30g each** |

*Trade ships can be lost to storms/sabotage/degradation; minimum is 1.

### 11.2 Plunder (Mercantilist only)

For each warship of attacker, for each non-allied victim:
```
if random() ≤ 0.20 AND victim.tradeShips > 0:
    amount = min(50g, victim.wealth)
    victim.wealth  -= amount
    attacker.wealth += amount
```

**Allied nations are never raided** — the ally check occurs before the roll.

**Relation impact** (asymmetric): aggressor −3, victim −10.

**Expected plunder per warship per tick:**
```
3 victims × 0.20 rate × 50g = 30g gained
3 attackers × 1 warship each × 0.20 × 50g = 30g lost
Net average = 0 (zero-sum redistribution)
```

### 11.3 Arms Race (Richardson Model)

```
C_target = α × max_rival_cost + β
         = 0.70 × max_rival_naval_cost + 20
```

- **α = 0.70 < 1** → convergent arms race (does not escalate indefinitely)
- At symmetric start (all 1 warship, 30g cost): `target = 0.70×30+20 = 41g → 1 warship` → no escalation from equal equilibrium
- **Voluntary disarmament**: if `targetWarships < current`, the nation decommissions 1 warship/tick
- Requires `wealth > WARSHIP_COST × 10 = 300g` to build
- Capped at **4 warships**

**Free trade**: Fixed cost of **20g/tick** (ARMS_RACE_BETA only, no warship maintenance).

---

## 12. Privateer System

### 12.1 Resolution (Mercantilist only)

For each nation with `privateers > 0`, for each non-allied victim:
```
success_rate = 0.55
if diplomaticState == EMBARGO: success_rate × 1.4 = 0.77

if random() ≤ success_rate AND victim.tradeShips > 0:
    amount = min(65g, victim.wealth)
    victim.wealth  -= amount
    attacker.wealth += amount
```

### 12.2 Privateers vs Regular Plunder

| | Regular plunder | Privateers |
|---|---|---|
| Source | Warships (permanent) | Commissioned corsairs (one-time) |
| Success rate | 20% | 55% (77% vs embargoed) |
| Amount per hit | 50g | 65g |
| Cost | 30g/tick maintenance | 120g upfront per corsair |
| Targets | All non-allied | All non-allied |

---

## 13. Sabotage System

### 13.1 Conditions (Mercantilist only)

A nation attempts harbour sabotage when:
1. `wealth ≥ 210g` (3× cost)
2. Target has the **worst relationship score** (below 40) of all non-allied rivals
3. Target has **> 1 trade ship**

**Attempt probability per tick**: 28%.
**Cost**: 70g per operation (deducted win or lose).

### 13.2 Outcomes

| Outcome | Chance | Effect on Target | Relation Change |
|---|---|---|---|
| **Success** | 55% | Loses 1 trade ship | Aggressor −8, Victim −30 |
| **Failure** (uncovered) | 45% | No ship loss | Aggressor −8, Victim −15 |

---

## 14. Degradation System

### 14.1 Degradation Levels

Checked at step 15 of each tick. Level is determined by **current wealth**:

| Level | Wealth Range | Export Penalty | Fleet Effects |
|---|---|---|---|
| **Healthy** | ≥ 600g | ×1.00 | None |
| **Struggling** | 250–599g | ×0.80 | Lose 1 trade ship after 2 consecutive negative-balance ticks |
| **Critical** | 100–249g | ×0.55 | 50% chance to lose a warship; 40% chance to lose a trade ship |
| **Bankrupt** | < 100g | ×0.30 | 65% chance to lose a trade ship; 65% chance to lose a warship |

Trade ships cannot drop below **1** (minimum fleet).

### 14.2 Allied Foreign Aid (Recovery Mechanic)

After degradation is applied (step 16), if a nation is **critical** or **bankrupt**:

```
for each allied nation with wealth ≥ 500g:
    aid = floor(donor.wealth × 0.10)
    donor.wealth    -= aid
    recipient.wealth += aid
    relations(both) += 8
```

This breaks the death spiral: wealthy allies act as economic insurance. It creates a strategic incentive to form alliances **before** a crisis.

### 14.3 Visual Feedback

| Level | Island Color |
|---|---|
| Healthy | Lush green |
| Struggling | Sandy yellow |
| Critical | Dry brown |
| Bankrupt | Ash grey (+ 18% transparency) |

---

## 15. Random Market Events

**40% chance** per tick of one event affecting one randomly selected nation:

| Event | Effect |
|---|---|
| **Gold Rush** | +250g windfall |
| **Plague** | −min(200g, 30% of wealth) |
| **Great Storm** | Lose 1 trade ship; if only 1 ship, lose 15% wealth instead |
| **Market Boom** | +25% of current wealth |
| **Market Crash** | −25% of current wealth |
| **Mutiny** | Lose 1 warship (if > 1) |
| **Trade Wind** | Gain 1 trade ship (if < 5); else +100g |

Events fire at step 5, before trade — they can affect the same tick's trade calculations. Nation selection is uniform random; over 24 ticks, expect ~2.4 events per nation on average.

---

## 16. State Machines

### 16.1 Nation — Degradation State Machine

```
                 wealth ≥ 600
              ┌──────────────────┐
              │                  │
              ▼                  │ foreign aid /
┌─────────────────────┐          │ Gold Rush event
│       HEALTHY       │          │
│    wealth ≥ 600g    │          │
│  export penalty ×1  │          │
└─────────────────────┘          │
          │                      │
          │ wealth < 600         │
          ▼                      │
┌─────────────────────┐          │
│     STRUGGLING      │──────────┘
│  250g ≤ wealth < 600│
│  export penalty ×0.8│
│  lose trade ship    │
│  after 2 neg. ticks │
└─────────────────────┘
          │
          │ wealth < 250
          ▼
┌─────────────────────┐
│      CRITICAL       │
│  100g ≤ wealth < 250│
│  export penalty ×0.55│
│  50% lose warship   │
│  40% lose tradeship │
└─────────────────────┘
          │                  ↑ allied aid
          │ wealth < 100     │ kicks in here
          ▼                  │
┌─────────────────────┐      │
│      BANKRUPT       │──────┘
│    wealth < 100g    │
│  export penalty ×0.3│
│  65% lose tradeship │
│  65% lose warship   │
└─────────────────────┘
```

Each level re-evaluates **every tick** based on current wealth. Recovery is possible in one tick with a large enough Gold Rush event or foreign aid transfer.

---

### 16.2 Diplomatic State Machine (per nation pair)

Evaluated every 2 ticks from tick 3 (mercantilist only).

```
                    relation ≥ 75
                    35% chance
              ┌─────────────────────┐
              │                     ▼
┌─────────────────────┐    ┌─────────────────────┐
│       NEUTRAL       │    │       ALLIED        │
│  base trade terms   │    │  +30% trade bonus   │
│  plunder possible   │    │  tech exports open  │
│  privateers possible│    │  no raids/privateers│
└─────────────────────┘    │  +5 relation/tick   │
              ▲             └─────────────────────┘
              │                     │
              │  relation < 55      │
              │  OR rival 1.8× richer│
              └─────────────────────┘

              │
              │ relation ≤ 22
              │ 15% chance
              ▼
┌─────────────────────┐
│       EMBARGO       │
│   trade = 0g        │
│   resource blocked  │
│  −1 relation/tick   │
└─────────────────────┘
              │
              │ relation > 40
              │ 30% chance
              ▼
          NEUTRAL  (embargo lifted, +5 relation)
```

**Important**: ALLIED and EMBARGO are **mutually exclusive**. A pair can only be in one state. State is symmetric — both nations share the same state for the pair.

---

### 16.3 Economy Tier State Machine

```
              wealth ≥ 1400g
RAW (1) ─────────────────────────────→ MANUFACTURE (2)
  ↑     ←─────────────────────────────         │
  │            wealth < 1400g                  │ wealth ≥ 2200g
  │                                            ▼
  │                                    TECHNOLOGY (3)
  │                                            │
  └────────────────────────────────────────────┘
                   wealth < 1400g
```

- Tier advances are **instant** when the threshold is crossed.
- Regression is also **instant** — no hysteresis or momentum.
- Technology tier gives 4× price multiplier but **only on allied routes**.

---

### 16.4 Tariff State Machine (per pair, mercantilist only)

```
                  rival.wealth > own × 1.15
                  AND relation < 60
                  AND tick ≥ 2
NO TARIFF ───────────────────────────────→ TARIFF ACTIVE
    ↑                                            │
    │                                            │ victim retaliates
    │     (no automated removal;                 │ after 1 tick
    │      tariff persists until                 ▼
    │      relations improve or             MUTUAL TARIFF
    │      wealth gap closes)          (both nations imposing)
    └──────────────────────────────────────────────┘
           (relation change or wealth equalization)
```

Tariffs are **not automatically removed**. Once imposed, they persist. The only way to remove them is through a restarted simulation or if the code is extended to add removal logic.

---

### 16.5 Privateer State Machine

```
                 worst relation < 30
                 wealth > 180g
                 35% chance
NO PRIVATEERS ──────────────────────────→ ACTIVE (1–3 corsairs)
                                                  │
                                                  │ privateers resolve
                                                  │ (attack non-allied per tick)
                                                  │
                                                  ▼
                                           (count depletes;
                                            privateers are
                                            one-time commissions
                                            — count resets to 0
                                            after each evaluation
                                            if none re-commissioned)
```

---

### 16.6 Nation — Full Per-Tick State Transition

Below is the complete state an individual nation transitions through each tick:

```
START OF TICK
│
├─ [1] Tier recalculated from wealth
├─ [2] Resources: own +20 (cap 200), all −4 (floor 0)
├─ [3] Relations adjusted for resource needs
├─ [5] Random event may fire (40%)
├─ [6] Tariff policy: impose tariff if rival 15%+ richer + poor relation
├─ [7] Diplomatic AI: evaluate alliance/embargo/privateer every 2 ticks
│
├─ [8] TRADE CALCULATION
│   ├─ For each partner:
│   │   ├─ If EMBARGO → income = 0, no resource transfer
│   │   ├─ Else → earn base_price (if partner needs your resource)
│   │   │        + floor income (if no resource income)
│   │   │        × modifiers (urgency, tier, relation, distance, tariff)
│   │   └─ Transfer resource units to partner
│   └─ Total exports applied; imports = exports × 0.55
│
├─ [9]  Plunder: each warship rolls 20% per rival (skip allies)
├─ [10] Privateers raid non-allied nations
├─ [11] Sabotage: 28% chance if wealthy + poor relations
├─ [12] Navy size updated (Richardson model)
├─ [13] Relations maintained (alliance +5, embargo −1, decay ±1)
│
├─ [14] WEALTH UPDATE
│   wealth += exports − imports + plunder_gained − navy_cost
│
├─ [15] DEGRADATION
│   ├─ Level set from wealth (healthy/struggling/critical/bankrupt)
│   └─ Fleet losses applied (random, level-dependent)
│
├─ [16] ALLIED AID
│   └─ If critical/bankrupt → allies with ≥ 500g send 10% of their wealth
│
└─ [17–18] Data recorded and broadcast to clients
```

---

## 17. Scenario Comparison

### 17.1 Mercantilist Scenario

All systems active. Nations impose tariffs, raid each other, form and break alliances, commission privateers, and engage in sabotage. The arms race drives permanent naval costs. Global wealth is lower due to:
- Naval maintenance costs (30g/warship/tick)
- Trade disruption from tariffs and embargoes
- Plunder (zero-sum redistribution, not wealth creation)

Expected final global wealth: **~9,000–10,000g**

### 17.2 Free Trade Scenario

Cooperative environment:
- **No tariffs, plunder, privateers, sabotage**
- **No diplomatic AI** (no alliances or embargoes formed)
- Free trade bonus: **×1.65** on all exports
- Fixed naval cost: **20g/tick** (no warship maintenance)
- Resources still trade normally

Expected final global wealth: **~11,000–12,000g** (~15–25% more than mercantilist)

### 17.3 Academic Result

```
W_global(free) > W_global(mercantilist)
```

This validates Adam Smith's thesis: free trade is positive-sum (both parties gain), while mercantilism is largely zero-sum (plunder and tariffs redistribute rather than create wealth).

The Gini coefficient is also computed: mercantilism typically shows higher inequality (one nation wins big via plunder/tier-3 advantage) while free trade distributes wealth more evenly.

---

## 18. Data Collection

### 18.1 Per-Tick CSV

```
scenario, tick, nation, wealth, wealth_delta, exports, imports,
plunder_gained, plunder_lost, navy_cost, trade_ships, warships,
degradation_level, tariff_count, alliance_count, embargo_count,
privateer_count, economy_tier
```

**Note on `wealth_delta`:** This is `exports − imports + plunder_gained − navy_cost`. It does NOT include `plunder_lost`. Actual net wealth change = `wealth_delta − plunder_lost`.

### 18.2 Event Log CSV

```
scenario, tick, event_type, actor, target, detail, amount
```

Event types: `random_event`, `plunder`, `alliance_formed`, `embargo_declared`, `alliance_broken`, `embargo_lifted`, `privateer_commissioned`, `privateer_raid`, `sabotage_success`, `sabotage_failed`

### 18.3 Computed Aggregates

| Aggregate | Description |
|---|---|
| Tariff–wealth correlation | Avg wealth delta with vs without active tariffs |
| Alliance trade impact | Avg exports with vs without active alliances |
| Arms race burden | Total navy cost as % of total exports |
| Gini coefficient | Wealth inequality (0=equal, 1=one nation holds all) |
| Scenario comparison | Global wealth, avg wealth, total exports, total navy cost |
| Per-nation final wealth | Ranked comparison across both scenarios |

---

## 19. Constants Reference

### Nations & Simulation
| Constant | Value | Description |
|---|---|---|
| `INITIAL_WEALTH` | 1,000g | Starting treasury |
| `TICK_DURATION` | 12s | Real seconds per tick |
| `MAX_TICKS` | 24 | Ticks per scenario |

### Resources
| Constant | Current | Description |
|---|---|---|
| `RESOURCE_MIN_NEED` | **15** | Urgent buy threshold (was 20) |
| `RESOURCE_MAX_STOCK` | **200** | Saturation cap (was 100) |
| `RESOURCE_START_STOCK` | 40 | Starting stock per resource |
| `RESOURCE_OWN_PRODUCTION` | **20** | Own production per tick (was 15) |
| `RESOURCE_CONSUMPTION` | **4** | Consumption per resource per tick (was 8) |
| `RESOURCE_URGENT_PREMIUM` | 1.5 | Premium when stock < MIN_NEED |
| `RESOURCE_TRADE_AMOUNT` | **6** | Units shipped per ship per route (was 12) |

### Trade
| Constant | Current | Description |
|---|---|---|
| `BASE_EXPORT_INCOME` | **160g** | Total base income split across routes (was 95) |
| `BASE_ROUTE_INCOME_FLOOR` | **10g** | Minimum per active route (new in v5.2) |
| `IMPORT_SPEND_RATIO` | 0.55 | Imports = 55% of exports |
| `FREE_TRADE_BONUS` | **0.65** | Multiplier in free trade scenario (was 0.40) |
| `ALLIANCE_TRADE_BONUS` | 0.30 | +30% on allied routes |

### Economy Tiers
| Constant | Value | Description |
|---|---|---|
| `TIER_THRESHOLD_MANUFACTURE` | 1,400g | Wealth for tier 2 |
| `TIER_THRESHOLD_TECHNOLOGY` | 2,200g | Wealth for tier 3 |
| `RAW_PRICE` | 1.0 | Raw resource multiplier |
| `MANUFACTURED_PRICE` | 2.2 | Manufactured goods multiplier |
| `TECHNOLOGY_PRICE` | 4.0 | Technology multiplier |

### Military
| Constant | Current | Description |
|---|---|---|
| `INITIAL_WARSHIPS` | 1 | Starting warships |
| `WARSHIP_COST_PER_TICK` | 30g | Maintenance per warship |
| `MAX_WARSHIPS` | **4** | Cap (was 8) |
| `PLUNDER_SUCCESS_RATE` | **0.20** | Raid chance per warship (was 0.45) |
| `PLUNDER_AMOUNT` | **50g** | Gold per successful raid (was 85) |
| `ARMS_RACE_ALPHA` | **0.70** | Richardson coefficient (was 1.25; now < 1 = convergent) |
| `ARMS_RACE_BETA` | **20** | Richardson constant (was 15) |

### Tariffs
| Constant | Current | Description |
|---|---|---|
| `TARIFF_RATE` | 0.50 | 50% income reduction |
| `TARIFF_START_TICK` | 2 | Earliest tick |
| `TARIFF_RIVAL_WEALTH_RATIO` | **1.15** | Trigger: rival 15%+ richer (new v5.3) |
| `RETALIATION_DELAY` | 1 | Ticks before retaliation |

### Relationships
| Constant | Current | Description |
|---|---|---|
| `RELATION_INITIAL` | 50 | Neutral starting score |
| `RELATION_ALLIANCE_THRESHOLD` | 75 | Score for alliance |
| `RELATION_EMBARGO_THRESHOLD` | **22** | Score for embargo (was 25, then 10) |
| `RELATION_RAID_THRESHOLD` | **30** | Privateer trigger (was 35) |
| `RELATION_DECAY_RATE` | **1** | Drift/tick toward 50 (was 3 in v5.2) |
| `RELATION_TRADE_BOOST` | **3** | Per trade (was 2) |
| `RELATION_ALLIANCE_BOOST` | 5 | Per allied tick |
| `RELATION_EMBARGO_DRAIN` | **−1** | Per embargoed tick (was −3) |
| `RELATION_RAID_VICTIM` | **−10** | Victim penalty per raid (was −25) |
| `RELATION_RAID_AGGRESSOR` | **−3** | Attacker penalty (was −5) |
| `RELATION_SABOTAGE_VICTIM_OK` | −30 | Successful sabotage |
| `RELATION_TARIFF_VICTIM` | −12 | Tariff target resentment |

### Degradation & Aid
| Constant | Value | Description |
|---|---|---|
| `DEGRADE_THRESHOLD_STRUGGLING` | 600g | Below = struggling |
| `DEGRADE_THRESHOLD_CRITICAL` | 250g | Below = critical |
| `DEGRADE_THRESHOLD_BANKRUPT` | 100g | Below = bankrupt |
| `FOREIGN_AID_RATIO` | 0.10 | Donor gives 10% of wealth |
| `FOREIGN_AID_MIN_DONOR_WEALTH` | 500g | Donor must have ≥ 500g |

---

## 20. Academic Framework

### Economic Theories Modeled

| Mechanic | Theory | Source |
|---|---|---|
| Free trade raises global wealth | Positive-sum trade / comparative advantage | Adam Smith (1776); Ricardo (1817) |
| Tariff → retaliation cascade | Trade war / Nash equilibrium | Nash (1950); Smoot-Hawley (1930) |
| Arms race formula | Richardson mutual-reaction model | Richardson, *Arms and Insecurity* (1960) |
| Alliance / embargo / privateer AI | Iterated Prisoner's Dilemma | Axelrod, *Evolution of Cooperation* (1984) |
| Resource dependency diplomacy | Interdependence theory | Keohane & Nye, *Power and Interdependence* (1977) |
| Gini inequality measurement | Wealth distribution | Gini (1912) |

### Version History of Key Changes

| Version | Key Fix | Impact |
|---|---|---|
| v4.0 | Bilateral relationship system | Diplomacy driven by scores, not wealth |
| v4.1 | Resource-need diplomacy | Alliance/embargo shaped by supply dependency |
| v5.0 | Allied foreign aid; ally-safe raids; asymmetric relations | Death spiral recovery; realistic diplomacy |
| v5.1 | ALPHA < 1; plunder rate/amount halved; MAX_WARSHIPS 8→4 | Stopped universal bankruptcy by tick 8 |
| v5.2 | Resource balance (CONSUMPTION 8→4, TRADE_AMOUNT 12→6); embargo threshold 25→10; route floor income | Stopped free trade income collapse by tick 5 |
| v5.3 | Tariff trigger fixed (wealth rivalry, not negative balance); EMBARGO_THRESHOLD 10→22; DECAY 3→1; FREE_TRADE_BONUS 0.40→0.65; nation names → Endava/Amdaris/GridDynamics/Globant | Diplomacy now fires; correct academic result (free trade > mercantilist) |

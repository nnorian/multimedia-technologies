# Mathematical Model Analysis — Issues & Improvement Proposals

## 1. Trade Pricing Model

### Current Model
```
route_income = (95 / 3) × tier_mult × urgency × rel_mod × free_trade × alliance × tariff × degrade
```

### Issues

**1.1 No supply-demand price discovery.** Prices are fixed multipliers. A resource with 3 urgent buyers and 1 seller commands the same base price as one with 0 buyers. Real markets adjust prices to clear supply and demand. The only demand signal is the binary urgency premium (×1.5 when stock < 20), which is a step function rather than a continuous response.

**Improvement:** Replace the fixed base price with a market-clearing mechanism. Let price respond to aggregate demand:
```
demand_pressure = Σ (MAX_STOCK - buyer_stock) / MAX_STOCK   for all buyers of this resource
supply = seller_stock / MAX_STOCK
price = base × (demand_pressure / supply)^elasticity
```
Where `elasticity ∈ (0, 1)` controls how responsive prices are. This creates natural price fluctuation without random events.

**1.2 Multiplicative modifier chain creates extreme variance.** With 7 multiplicative factors, edge cases produce extreme outcomes. A bankrupt nation (×0.30) under tariff (×0.50) with bad relations (×0.70 floor) gets: `31.7 × 0.30 × 0.50 × 0.70 = 3.3g` per route — near zero and unrecoverable. Conversely, an allied (×1.30) tech exporter (×4.0) with great relations (×1.15) and urgent buyer (×1.5) gets: `31.7 × 4.0 × 1.5 × 1.15 × 1.30 = 284g` per route — almost 3× the total base income. This creates runaway divergence.

**Improvement:** Switch to an additive bonus/penalty system with a multiplicative core, or apply diminishing returns:
```
effective_multiplier = 1 + log(product_of_all_multipliers)
```
This compresses extreme values while preserving ordering.

**1.3 Import spending is structurally decoupled from actual resource purchases.** `imports = exports × 0.55` means import costs are a fixed tax on exports, not a payment for received goods. A nation that receives 0 resources still "pays" 55% of its export earnings as imports. Conversely, a nation receiving huge resource deliveries pays the same ratio.

**Improvement:** Tie import spending to actual resource units received:
```
import_cost = Σ (units_received × resource_market_price)
```
This creates a real balance-of-trade calculation where nations can run actual surpluses or deficits.

---

## 2. Richardson Arms Race Model

### Current Model
```
C_target = α × max(rival_naval_costs) + β
         = 1.25 × max_rival_cost + 15
```

### Issues

**2.1 Only reacts to the single strongest rival.** The real Richardson model (1960) uses the sum of all rivals' arms as the stimulus. By reacting only to the maximum, a nation surrounded by three moderately-armed rivals behaves identically to one facing a single moderate rival. This underestimates the collective threat.

**Improvement:** Use the full Richardson mutual-reaction form:
```
dC_i/dt = α × Σ(C_j, j≠i) - β × C_i + γ_i
```
Where:
- `α` = reaction coefficient (fear of others' arms)
- `β` = fatigue coefficient (economic cost of own arms)
- `γ_i` = grievance term (base hostility independent of rivals' arms)

The grievance term `γ_i` should be driven by the relationship system:
```
γ_i = Σ max(0, RELATION_INITIAL - relation(i,j))   for all j
```
This means a nation with universally poor relations arms faster even if rivals aren't armed.

**2.2 No fatigue/cost-feedback term.** In Richardson's model, a nation's own arms expenditure acts as a brake (nations tire of spending). The current model has no such term — it only builds up, never voluntarily disarms. The wealth check (`wealth > 5 × warship_cost`) is a hard cutoff, not a gradual deterrent.

**Improvement:** Add a disarmament path:
```
if C_current > C_target and no active embargo/raid in last 3 ticks:
    warships -= 1  (gradual drawdown when threat recedes)
```

**2.3 One warship per tick is unrealistically slow.** Building is capped at +1/tick, but the target can be much higher (e.g., 5 warships). This creates a guaranteed multi-tick lag that doesn't model urgency well. A nation under active plunder should arm faster.

**Improvement:** Scale build rate by urgency:
```
build_rate = 1 + floor(plunder_lost_last_tick / PLUNDER_AMOUNT)
```

---

## 3. Relationship System

### Current Model
Additive modifiers clamped to [0, 100], symmetric changes, linear decay toward 50.

### Issues

**3.1 Symmetric relationship changes are unrealistic.** When A raids B, both get -15. But A chose to raid (should lose less — they expected this) while B was victimized (should resent more). Sabotage is the same: the attacker and victim both lose the same relationship points, which doesn't model the asymmetry of aggression.

**Improvement:** Make changes asymmetric:
```
-- Raid: A raids B
changeRelation(A→B, -5)   -- attacker views victim slightly worse (dehumanization)
changeRelation(B→A, -25)  -- victim deeply resents attacker
```
This requires making `_relations[A][B] ≠ _relations[B][A]` (asymmetric matrix). Diplomatic decisions would use the perspective of the deciding nation.

**3.2 Ceiling and floor effects create dead zones.** Once a relationship hits 0 or 100, additional negative/positive events have no effect. A nation at relation 0 that gets raided again suffers no additional diplomatic consequence. Similarly, allied nations at 100 have no way to differentiate between a "strong ally" and a "critical ally."

**Improvement:** Either expand the scale (e.g., -100 to +100), or use a logistic transformation that compresses near the edges but never truly saturates:
```
effective_relation = 100 / (1 + e^(-0.1 × (raw_score - 50)))
```
Store raw_score unbounded; display the logistic-mapped value.

**3.3 Linear decay toward 50 is too simple.** Decay of ±1 per tick means a relation of 90 (strong alliance) takes 40 ticks to return to neutral — longer than the entire simulation (24 ticks). But a relation of 60 (slightly positive) decays in 10 ticks. This means early alliances are essentially permanent while late-game relationship building is wiped out.

**Improvement:** Use proportional decay (decay faster when further from neutral):
```
decay = sign(relation - 50) × max(1, |relation - 50| × 0.08)
```
A relation of 90 decays by 3.2/tick (reaches 50 in ~12 ticks). A relation of 60 decays by 0.8/tick. This creates more dynamic relationship cycling.

**3.4 Too many simultaneous modifiers create noisy, unpredictable outcomes.** In a single tick, a nation-pair can accumulate: trade boost (+2), resource need boost (+4), fulfilled boost (+3), alliance boost (+5), decay (-1) = net +13. Next tick with a raid: trade boost (+2), raid penalty (-15), resource need (+4) = net -9. The relationship oscillates wildly between ticks.

**Improvement:** Apply a momentum/inertia system:
```
effective_delta = 0.3 × raw_delta + 0.7 × previous_delta
```
This smooths relationship changes and creates trends rather than noise.

---

## 4. Diplomatic Decision Model

### Current Model
Fixed thresholds + flat probability rolls: `if relation ≥ 75 and random() < 0.35 then ally`.

### Issues

**4.1 No cost-benefit analysis.** The AI doesn't weigh the economic value of an alliance/embargo. It allies at relation 75 regardless of whether the partner is wealthy (valuable ally) or bankrupt (worthless ally). A rational agent would consider: "What do I gain from this alliance?"

**Improvement:** Weight the probability by expected value:
```
alliance_value = (partner.exports_to_me / my_total_imports) × (1 + ALLIANCE_TRADE_BONUS)
embargo_cost = (my_exports_to_partner / my_total_exports)
probability = base_probability × (1 + alliance_value)   -- for alliance
probability = base_probability × (1 - embargo_cost)      -- for embargo (less likely if costly)
```

**4.2 Evaluation every 2 ticks creates artificial rigidity.** Diplomatic decisions only fire on even ticks from tick 3 onward. If a critical event (massive raid, resource crisis) happens on tick 7, the nation must wait until tick 8 to respond diplomatically. In a 24-tick simulation, this delay is 4% of the total runtime.

**Improvement:** Allow reactive diplomacy: certain events (raid, resource crisis) trigger immediate diplomatic evaluation for affected pairs, in addition to the regular 2-tick cycle.

**4.3 No memory or grudge system.** Past betrayals (broken alliance, failed sabotage) are only reflected in the relationship score, which decays. A nation that was sabotaged at tick 5 has largely "forgotten" by tick 15 due to decay. Real diplomacy has long-term grudges and trust deficits.

**Improvement:** Track a separate `trust` variable per pair that only decreases (never decays):
```
trust starts at 100
trust -= 30 on alliance betrayal
trust -= 15 on sabotage
alliance_threshold = base_threshold + (100 - trust) × 0.5
```
A nation that betrayed you once needs relation 90+ to re-ally, not 75.

---

## 5. Plunder & Piracy Model

### Current Model
```
for each warship of attacker:
    for each victim (all other nations):
        if random() ≤ 0.45 and victim.tradeShips > 0:
            steal min(85g, victim.wealth)
```

### Issues

**5.1 Quadratic scaling of raids.** With W warships and N-1 victims, each attacker makes `W × (N-1)` independent raid rolls per tick. At max warships (8) against 3 victims, that's 24 rolls at 45% each = expected 10.8 successful raids × 85g = **918g per tick** in plunder. This massively exceeds trade income (~95g). A heavily armed nation has no incentive to trade at all.

**Improvement:** Cap raids per warship to 1 successful intercept per tick, or use a defender-strength model:
```
raid_success = PLUNDER_RATE × (attacker_warships / (attacker_warships + victim_warships + victim_tradeShips))
```
This makes defense meaningful and prevents runaway piracy.

**5.2 Raids are indiscriminate.** Warships attack ALL non-self nations, including allies. There's no check for diplomatic state. This contradicts the relationship system — you're simultaneously gaining +5 relation from alliance and losing -15 from raiding the same nation.

**Improvement:** Skip plunder rolls against allied nations (the privateer system already does this correctly).

**5.3 No diminishing returns on plundering the same victim.** A bankrupt victim (wealth < 85g) gets plundered for their remaining wealth multiple times per tick (each roll steals `min(85, remaining_wealth)`, and wealth updates immediately). This can drain a nation to 0 in a single tick from one attacker.

**Improvement:** Track per-victim plunder cap per tick:
```
max_plunder_per_victim_per_tick = victim.wealth × 0.15  -- can't steal more than 15% per season
```

---

## 6. Degradation System

### Current Model
Threshold-based: wealth < 600 → struggling → export penalty 0.80 → lower income → lower wealth → ...

### Issues

**6.1 Positive feedback death spiral with no escape mechanism.** The degradation system creates a reinforcing loop:
```
low wealth → export penalty → less income → lower wealth → worse penalty → ...
```
At "bankrupt" (< 100g), exports are ×0.30, meaning a nation earns ~28g from trade but pays 30g per warship. This is a guaranteed net loss with no recovery path except the 40% random event chance (Gold Rush = +250g or Trade Wind). The system is designed to collapse nations, not to allow recovery through strategic action.

**Improvement:** Add a recovery mechanic — for instance, foreign aid from allies:
```
if ally.degradation == "critical" or "bankrupt":
    allied_nation sends aid = 10% of own wealth
    ally.wealth += aid
```
Or introduce debt/loans:
```
if wealth < CRITICAL and not indebted:
    wealth += emergency_loan (200g)
    export_income reduced by 20% for next 5 ticks (repayment)
```

**6.2 Step function transitions create discontinuities.** The export penalty jumps from 1.00 → 0.80 → 0.55 → 0.30 at exact wealth thresholds (600, 250, 100). A nation at 601g has full exports; at 599g it suddenly loses 20%. This creates threshold gaming where the optimal strategy changes discontinuously.

**Improvement:** Use a continuous degradation curve:
```
penalty = min(1.0, wealth / HEALTHY_THRESHOLD)^0.5
```
At wealth 600: penalty = 1.0. At 300: penalty = 0.71. At 100: penalty = 0.41. Smooth transition, no step discontinuities.

---

## 7. Resource Production Model

### Current Model
```
production: +15 own resource per tick (constant)
consumption: -8 all resources per tick (constant)
```

### Issues

**7.1 Production is independent of economic state.** A bankrupt nation with 1 trade ship produces the same 15 units as a thriving tech exporter. Real economies lose productive capacity when they degrade. Infrastructure decay, labor flight, and supply chain disruption should reduce output.

**Improvement:** Scale production by degradation:
```
production = BASE_PRODUCTION × degradation_penalty
```
Where `degradation_penalty` is the same 1.0 / 0.80 / 0.55 / 0.30 curve. A bankrupt nation produces only 4.5 units instead of 15.

**7.2 Consumption is constant regardless of stock or wealth.** A nation consumes 8 units even if it has 2 units remaining (clamped to 0). There's no behavioral adaptation — in reality, a nation running low on a resource would ration.

**Improvement:** Introduce elastic consumption:
```
consumption = BASE_CONSUMPTION × min(1.0, stock / RESOURCE_MIN_NEED)
```
When stock is at 10 (half of MIN_NEED), consumption drops to 4. This creates a natural buffer against total depletion.

**7.3 No inter-resource dependencies.** Meat, Logs, Ore, and Herbs are consumed independently. In reality, manufacturing requires multiple inputs (you need ore AND logs to build ships, herbs AND meat to feed armies). The tier 2 "manufactured goods" should consume raw materials.

**Improvement:** Manufactured goods production should deduct raw materials:
```
if tier >= MANUFACTURE:
    for each non-primary resource with stock > 20:
        deduct 3 units → produce manufactured_goods_value
```
This creates a real manufacturing cost and makes resource scarcity affect higher-tier production.

---

## 8. Economy Tier Model

### Current Model
```
if wealth ≥ 2200 → TECHNOLOGY
elif wealth ≥ 1400 → MANUFACTURE
else → RAW
```

### Issues

**8.1 Instant regression destroys progression meaning.** A tech-capable nation that gets raided for 100g immediately loses technology capability. Real technological advancement doesn't vanish because of a single bad quarter. This makes tier 3 extremely fragile and discourages the investment-heavy strategy needed to reach it.

**Improvement:** Add tier momentum/hysteresis:
```
-- Advancement: must sustain wealth above threshold for 3 consecutive ticks
-- Regression: only regress if wealth drops below 80% of previous tier threshold
```
So tier 3 unlocks at 2200g sustained for 3 ticks, and only regresses if wealth drops below 1120g (80% of 1400g). This creates meaningful progression.

**8.2 Manufactured goods demand disappears when buyer catches up.** Manufactured goods are only sold to partners with `economyTier < MANUFACTURE`. Once all nations reach tier 2, nobody buys manufactured goods from anyone. This creates a paradox: economic growth eliminates trade value.

**Improvement:** Instead of a binary demand check, use comparative advantage:
```
mfg_demand = max(0, seller.economyTier - buyer.economyTier)
mfg_price = base × (1 + mfg_demand × 0.6)
```
Even nations at the same tier can trade, but with no premium. Higher-tier nations still have an edge.

**8.3 Technology as alliance-only export creates a rich-get-richer loop.** Only wealthy nations reach tier 3, and they only sell tech to allies (who are likely also wealthy due to the alliance trade bonus). Poor nations can never access technology, can never compete, and the wealth gap compounds.

**Improvement:** Allow technology purchase by non-allies at reduced effect or higher price:
```
if allied: tech price ×4.0 (full benefit, buyer gets +10% production)
if neutral and relation > 60: tech price ×6.0 (buyer gets +5% production, seller premium)
if neutral and relation ≤ 60: blocked
```

---

## 9. Random Event Model

### Current Model
40% chance per tick, uniform selection from 7 events, uniform nation selection.

### Issues

**9.1 Uniform nation selection creates unfair variance.** Over 24 ticks, expected events per nation = `24 × 0.40 / 4 = 2.4`, but with high variance. One nation might get 5 events (multiple plagues) while another gets 0. In a competitive simulation, this randomness can dominate strategic play.

**Improvement:** Use a round-robin or weighted selection that ensures more even distribution:
```
-- Track events per nation, favor those with fewer
weight_i = 1 / (1 + events_received_i)
selection = weighted_random(weights)
```

**9.2 Some events are vastly more impactful than others.** Gold Rush (+250g = 25% of starting wealth) vs Mutiny (lose 1 warship = save 30g/tick for ~7 remaining ticks = 210g indirect benefit). The variance between best and worst event is enormous.

**Improvement:** Scale event magnitude by game phase:
```
event_magnitude = base_magnitude × (1 + tick / MAX_TICKS × 0.5)
```
Early events are smaller; late events are more dramatic (mimics historical escalation).

**9.3 Events are independent of nation state.** A plague is equally likely for a wealthy nation as a bankrupt one. Gold rushes don't depend on exploration investment. This reduces strategic depth.

**Improvement:** Make some events state-dependent:
```
plague_chance × (1 + max(0, 4 - nation.resources["Herbs"]) × 0.1)  -- herbs = medicine
storm_chance × (1 + max(0, 4 - nation.tradeShips) × 0.1)           -- fewer ships = less scouting
```

---

## 10. Structural / Simulation-Wide Issues

**10.1 Zero-sum plunder in a positive-sum trade world creates strategic dominance of aggression.** In the mercantilist scenario, plunder (85g per hit, 45% rate, per warship per victim) has higher expected value than trade (~32g per route). The rational strategy is to maximize warships and minimize trade ships, which contradicts the simulation's intent to model trade dynamics.

**Expected income analysis:**
```
Trade: 95g base / 3 routes = 31.7g per route
Plunder: 0.45 × 85g = 38.3g per warship per victim × 3 victims = 114.8g per warship
Warship cost: 30g per warship
Net plunder: 84.8g per warship >> 31.7g per trade route
```

**Improvement:** Either reduce plunder rate/amount or make plunder risk trade ship losses:
```
-- Defenders sink attacking warship with small probability
if raid_successful:
    if random() < 0.10: attacker loses the warship
```

**10.2 24 ticks is too few for emergent behavior.** Many model dynamics (arms race convergence, relationship cycling, tier progression) require 30+ ticks to play out. With diplomacy evaluating every 2 ticks from tick 3, there are only 10 diplomatic evaluation windows. The Richardson model needs ~10 ticks just to reach steady state.

**10.3 No spatial model despite spatial visuals.** Nations have positions and ships animate between them, but distance has no gameplay effect. Trade between neighbors and trade across the map have identical cost and speed. Storms don't depend on route length.

**Improvement:** Add distance-based trade cost:
```
distance = (pos_A - pos_B).Magnitude
trade_efficiency = 1 / (1 + distance / REFERENCE_DISTANCE × 0.3)
route_income = base × trade_efficiency
storm_risk = base_storm_chance × (distance / REFERENCE_DISTANCE)
```

**10.4 No population or labor model.** All production is automatic. There's no concept of labor allocation between sectors (raw production, manufacturing, military, trade). This prevents modeling opportunity costs — the core insight of classical economics.

---

## Summary of Priority Improvements

| Priority | Issue | Current Impact | Fix Complexity |
|---|---|---|---|
| **Critical** | Plunder >> trade income (10.1) | Breaks strategic balance | Low — adjust constants |
| **Critical** | Death spiral with no recovery (6.1) | Nations collapse irreversibly | Low — add aid/loans |
| **High** | No supply-demand pricing (1.1) | Flat, unresponsive market | Medium — new price function |
| **High** | Warship raids hit allies (5.2) | Contradicts diplomacy | Low — add state check |
| **High** | Import cost decoupled from goods (1.3) | Unrealistic balance-of-trade | Medium — restructure |
| **High** | Symmetric relationship changes (3.1) | Unrealistic diplomacy | Medium — asymmetric matrix |
| **Medium** | Richardson model oversimplified (2.1) | Weak arms dynamics | Medium — full model |
| **Medium** | Instant tier regression (8.1) | Fragile progression | Low — add hysteresis |
| **Medium** | Multiplicative extreme values (1.2) | Runaway divergence | Low — compress extremes |
| **Medium** | No inter-resource deps (7.3) | Flat manufacturing | Medium — input costs |
| **Low** | Step-function degradation (6.2) | Minor discontinuity | Low — continuous curve |
| **Low** | Constant production/consumption (7.1, 7.2) | Oversimplified | Low — scale by state |
| **Low** | Uniform random events (9.1) | Variance-driven outcomes | Low — weighted selection |
| **Low** | No spatial trade cost (10.3) | Wasted visual design | Medium — distance calc |

---

## Recommended Reading

- Richardson, L.F. (1960). *Arms and Insecurity*. Boxwood Press. — Full arms race differential equation model.
- Axelrod, R. (1984). *The Evolution of Cooperation*. Basic Books. — Iterated games, tit-for-tat, reputation.
- Krugman, P. (1991). "Increasing Returns and Economic Geography." *Journal of Political Economy*, 99(3). — Spatial trade models.
- Walras, L. (1874). *Elements of Pure Economics*. — General equilibrium and market-clearing prices.
- Schelling, T. (1960). *The Strategy of Conflict*. Harvard UP. — Focal points, commitment, asymmetric information in diplomacy.
- Epstein, J. & Axtell, R. (1996). *Growing Artificial Societies*. MIT Press. — Agent-based economic simulation design, especially resource consumption/production coupling.

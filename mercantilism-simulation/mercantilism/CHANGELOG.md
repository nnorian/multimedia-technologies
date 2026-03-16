# Mercantilism Simulation — Changelog

## v3.0 — Mystical Nations & Dynamic Events (2026-03-16)

### Summary
Major overhaul focused on three goals:
1. Replace real-world country names with mystical/fantasy equivalents
2. Make the simulation far more dynamic with bigger financial swings and random events
3. Improve notification visibility so players don't miss key moments

---

### Nation Renames

All real-world country references removed. New mystical nation names:

| Old Name | New Name | Resource | Visual Theme |
|---|---|---|---|
| England | **Ironhaven** | Iron | Dark iron citadel, forge glow, dark pines |
| France | **Goldspire** | Grain | Golden palace, glowing spires, enchanted garden |
| Spain | **Emberveil** | Spices | Volcanic fortress, ember dome, lava pools |
| Netherlands | **Drifthollow** | Wood | Timber longhouses, enchanted windmill, spirit lanterns |

---

### Random Market Events (NEW)

A new event system fires with 40% probability each tick, targeting a random nation:

| Event | Effect |
|---|---|
| **Gold Rush** | +250g windfall |
| **Plague** | Lose up to 30% wealth (max 200g) |
| **Great Storm** | Lose a trade ship (or 15% wealth if only 1 ship) |
| **Market Boom** | +25% of current wealth |
| **Market Crash** | -25% of current wealth |
| **Mutiny** | Lose a warship |
| **Trade Winds** | Gain a trade ship (or +100g if fleet is full) |

Events are logged as `[EVENT]` and always trigger screen notifications.

---

### Rebalanced Constants (More Volatile Economy)

| Parameter | Old | New | Effect |
|---|---|---|---|
| `BASE_EXPORT_INCOME` | 75 | **95** | Bigger base trade income |
| `RESOURCE_BONUS` | 25 | **35** | Specialisation rewarded more |
| `TARIFF_RATE` | 0.40 | **0.50** | Tariffs bite 50% instead of 40% |
| `TARIFF_START_TICK` | 3 | **2** | Earlier tariff wars |
| `RETALIATION_DELAY` | 2 | **1** | Faster retaliation |
| `WARSHIP_COST_PER_TICK` | 20 | **30** | Arms race drains faster |
| `PLUNDER_SUCCESS_RATE` | 0.35 | **0.45** | More raiding |
| `PLUNDER_AMOUNT` | 55 | **85** | Huge plunder swings |
| `ARMS_RACE_ALPHA` | 1.15 | **1.25** | Faster naval escalation |
| `FREE_TRADE_BONUS` | 0.35 | **0.40** | Free trade advantage clearer |
| `PRIVATEER_PLUNDER_AMOUNT` | 40 | **65** | Big privateer hauls |
| `SABOTAGE_ATTEMPT_CHANCE` | 0.18 | **0.28** | Much more sabotage |
| `SABOTAGE_SUCCESS_RATE` | 0.45 | **0.55** | Higher success rate |
| `ALLIANCE_TRADE_BONUS` | 0.22 | **0.30** | Alliances matter more |
| `DEGRADE_THRESHOLD_STRUGGLING` | 500 | **600** | Tighter degradation bands |

---

### Diplomacy AI — More Aggressive

- Evaluates every **2 ticks** (was 3) from **tick 3** (was 4)
- Alliance formation at **105%** initial wealth (was 110%), **30%** chance (was 20%)
- Embargo declaration at **3 rival warships** (was 4), **40%** chance (was 30%)
- Alliance breakdown at **1.8x** wealth ratio (was 2.2x), **35%** chance (was 25%)
- Privateers commission at **2 rival warships** (was 3), up to **3 corsairs** (was 2)
- All real-world historical references removed from log messages

---

### UI Improvements — More Visible Notifications

- Notification pop-up wider: **620px** (was 520px) and taller: **82px** (was 68px)
- Notification text size: **18pt** (was 15pt)
- Notification hold time: **3.5s** (was 2.5s)
- Queue cap raised to **8** (was 5)
- **All plunder events** now trigger notifications (removed 150g threshold)
- **All decay events** now trigger notifications
- **Random events** always trigger colour-coded notifications
- Log entry text size: **12pt** (was 10pt)
- Header title changed to "REALM OF MERCANTILISM"
- Event log entries colour-coded for random events (red/green/orange)

---

## v2.0 — Professor Feedback Update (2026-03-12)

### Summary
Major expansion addressing four points of professor feedback:
1. More visually engaging HUD
2. Real political interactions (privateers, sabotage)
3. Dynamic country interactions (alliances, embargoes)
4. Real-world economics references for the conference paper

---

### New File: `ReplicatedStorage/DiplomacySystem.lua`

A new module managing all diplomatic relations between nations.

**Diplomatic states** (symmetric between any two nations):
| State | Effect |
|---|---|
| `neutral` | Default; normal trade, normal plunder |
| `allied` | +22% export income on the shared route; no privateers attack each other |
| `embargo` | 100% trade block on that route (zero income both ways) |

**Privateer system**
- Nations under naval threat (rival warships ≥ 3) commission 1–2 privateers at a cost of 150g.
- Privateers intercept enemy merchant ships at a 50% success rate (vs. warships' 35%), yielding 40g per hit.
- Privateers never attack allied nations.
- Against embargoed targets, success rate scales up ×1.4.
- Historical reference: Francis Drake's Letters of Marque from Elizabeth I (1577–1580); Jean Bart raiding English convoys for Louis XIV (1690s).

**Harbour sabotage**
- Nations with surplus wealth (≥ 240g) have an 18% chance per tick of attempting a sabotage operation (80g cost).
- On success (45% chance): target loses one trade ship.
- On failure: gold is wasted and the log records the failed operation.
- Historical reference: Dutch Medway Raid (1667) — Dutch fleet burned English warships at Chatham; English burning of Dutch herring fleets.

**Diplomatic AI** (mercantilist scenario only, re-evaluates every 3 ticks from tick 4)
- Forms alliances when both nations are above 110% initial wealth and have low mutual naval threat.
- Declares embargoes when a rival has ≥ 4 warships and own wealth has fallen below 75% of starting value.
- Breaks alliances when wealth ratio exceeds 2.2× (jealousy/rivalry).
- Lifts embargoes when target nation falls below the critical wealth threshold.
- Historical reference: Axelrod (1984) *The Evolution of Cooperation* — Prisoner's Dilemma structure of trade policy.

**Key functions:**
```
DiplomacySystem.init(nationList)
DiplomacySystem.getState(id1, id2) → "neutral" | "allied" | "embargo"
DiplomacySystem.setState(id1, id2, state)
DiplomacySystem.evaluateDiplomacy(nation, allNations, tick, logs)
DiplomacySystem.resolvePrivateers(nations, scenario, logs) → results
DiplomacySystem.resolveSabotage(nations, scenario, logs)
DiplomacySystem.getSummary(nationList) → table { [id] = { privateers, relations } }
```

---

### Modified: `ReplicatedStorage/GameConfig.lua`

Added constants at the bottom:

```lua
-- Privateer system
Config.PRIVATEER_COMMISSION_COST  = 150
Config.PRIVATEER_SUCCESS_RATE     = 0.50
Config.PRIVATEER_PLUNDER_AMOUNT   = 40

-- Sabotage system
Config.SABOTAGE_COST              = 80
Config.SABOTAGE_ATTEMPT_CHANCE    = 0.18
Config.SABOTAGE_SUCCESS_RATE      = 0.45

-- Diplomacy
Config.ALLIANCE_TRADE_BONUS       = 0.22   -- +22% income on allied routes
Config.EMBARGO_TRADE_MULTIPLIER   = 0.0    -- complete trade block
```

---

### Modified: `ReplicatedStorage/TradeSystem.lua`

**`calculateExports` signature extended:**
```lua
TradeSystem.calculateExports(nation, allNations, scenario, getDiploState)
```
- `getDiploState` is optional (`nil` in free-trade scenario).
- If `getDiploState(nation.id, partner.id) == "embargo"` → route income set to 0 (complete block).
- If `getDiploState(nation.id, partner.id) == "allied"` → route income multiplied by `1 + ALLIANCE_TRADE_BONUS`.
- Embargo check happens before all other calculations; alliance bonus is applied after the free-trade multiplier and before the tariff reduction.

Historical reference added as inline comment: Anglo-Portuguese Treaty of Windsor (1386) — oldest active alliance in the world, showing alliance trade access predates mercantilism.

---

### Modified: `ServerScriptService/GameManager.server.lua`

**New require:**
```lua
local DiplomacySystem = require(RS:WaitForChild("DiplomacySystem"))
```

**`runSimulation` initialisation:**
```lua
DiplomacySystem.init(NationState.getAllNations())
```

**New helper `updateTradeRouteVisuals(allNations)`:**
Called every tick to recolour the neon route lines in `workspace.TradeRouteVisuals`:
- White (transparency 0.70) = neutral
- Gold (transparency 0.30) = allied
- Red (transparency 0.35) = embargo

**New tick-loop steps (after step 6 / plunder resolution):**
- Step 4b: `DiplomacySystem.evaluateDiplomacy` for each nation (mercantilist only)
- Step 6b: `DiplomacySystem.resolvePrivateers` — privateers intercept trade ships
- Step 6c: `DiplomacySystem.resolveSabotage` — harbour sabotage attempts

**`getDiploState` passed to TradeSystem:**
```lua
TradeSystem.calculateExports(nation, allNations, scenario,
    scenario == Config.SCENARIOS.MERCANTILIST and DiplomacySystem.getState or nil)
```

**WealthUpdated payload extended:**
Each nation summary now includes:
- `ns.privateers` — count of commissioned privateers
- `ns.diplomaticRelations` — table of `[partnerId] = state` strings

---

### Modified: `StarterPlayer/StarterPlayerScripts/SimulationUI.client.lua`

#### 1. Animated event notification system

New functions `processNotifQueue()` and `queueNotification(text, color)`.

A queued pop-up appears centre-screen (z-index 25) for significant events:
- Slides up 20px and fades in over 0.35s
- Holds for 2.5s
- Slides up another 20px and fades out over 0.4s
- Destroyed on completion; next queued notification then starts

Notifications are triggered from the `tickLogEvent` handler by pattern-matching log lines:
| Pattern | Colour |
|---|---|
| `[PRIVATEER]` | Orange |
| `[SABOTAGE]` (success only) | Purple `(220, 80, 200)` |
| `[DIPLOMACY]` + `embargo` | Red |
| `[DIPLOMACY]` + `treaty` | Green |
| `[BANKRUPT]` | Red |
| `[PLUNDER]` > 150g | Orange |

Queue capped at 5 entries to prevent flooding after a silence.

#### 2. Wealth sparkline

Global wealth frame expanded from 80px → 110px tall, repositioned to `UDim2.new(0.5, -210, 1, -120)`.

A `sparkContainer` frame holds 10 `SparkBar` rectangles, each tracking one tick of global wealth:
- Bars are bottom-anchored and scale in height relative to the max value in the 10-tick window.
- Green bar = wealth rose vs previous tick.
- Red bar = wealth fell.
- Gold bar = unchanged / first reading.
- `updateSparkline(globalWealth)` called every tick from `updateLeaderboard`.

#### 3. Diplomatic status in leaderboard rows

Each nation row expanded from 86px → 108px tall; leaderboard panel from 420px → 500px tall; row spacing from 92px → 114px.

A `DIPLOMACY` label and three partner dots appear at y=86 in each row:
- `● Eng` in green = allied with England
- `✗ Eng` in red = embargo on England
- `· Eng` in grey = neutral

Dots update every tick from `ns.diplomaticRelations` in the WealthUpdated payload.

---

## v1.0 — Initial Build

### Files
| File | Role |
|---|---|
| `ReplicatedStorage/GameConfig.lua` | All simulation constants |
| `ReplicatedStorage/NationState.lua` | In-memory nation state, tariff management, tick history |
| `ReplicatedStorage/TradeSystem.lua` | Export/import calculations, tariff AI |
| `ReplicatedStorage/NavalSystem.lua` | Plunder resolution, arms race (Richardson model) |
| `ReplicatedStorage/DegradationSystem.lua` | Fleet decay, export penalties, island colour changes |
| `ServerScriptService/MapSetup.server.lua` | World geometry (ocean, islands, ports, ships, neon routes) |
| `ServerScriptService/GameManager.server.lua` | Main simulation loop, ship animation, RemoteEvents |
| `StarterPlayer/StarterPlayerScripts/SimulationUI.client.lua` | HUD: leaderboard, event log, comparison panel |

### Core mechanics
- **4 nations:** England (Iron), France (Grain), Spain (Spices), Netherlands (Wood)
- **2 scenarios:** Mercantilist vs Free Trade — run back-to-back, final `W_global` compared
- **Arms race:** Richardson model `C_i(t+1) = 1.15 × C_j(t) + 10`
- **Tariffs:** 40% income reduction per imposed tariff; retaliation after 2-tick delay
- **Plunder:** Each warship has 35% chance per tick to intercept a rival trade ship for 55g
- **Degradation levels:** healthy → struggling → critical → bankrupt (wealth thresholds: 500 / 200 / 75)
- **Wealth formula per tick:** `W_i(t) = W_i(t-1) + X_i - M_i + P_i - C_i`
  - `X_i` = exports, `M_i` = imports, `P_i` = plunder gained, `C_i` = navy cost

---

## Academic Paper Reference Map

| Simulation mechanic | Economic concept | Source |
|---|---|---|
| Tariff → retaliation cascade | Trade war / Nash equilibrium | Nash (1950); Smoot-Hawley (1930) |
| Free trade raises `W_global` | Positive-sum trade | Adam Smith, *Wealth of Nations* (1776) Book IV |
| Resource demand matrix | Comparative advantage | Ricardo, *Principles* (1817) Ch. 7 |
| Arms race formula | Richardson arms race model | Richardson, *Arms and Insecurity* (1960) |
| Privateer / alliance / embargo AI | Iterated Prisoner's Dilemma | Axelrod, *Evolution of Cooperation* (1984) |
| Tariff deadweight loss | Consumer/producer surplus loss | Samuelson, *Economics* (1948) |

### Key historical events mapped to mechanics
| Mechanic | Historical parallel |
|---|---|
| Tariff + retaliation | Navigation Acts 1651/1660 (England vs Netherlands) |
| Naval arms race | Anglo-Dutch Wars 1652–1674 |
| Privateer commission | Francis Drake's Letters of Marque (1577); Jean Bart (1690s) |
| Harbour sabotage | Dutch Medway Raid 1667 |
| Embargo declaration | Navigation Acts excluding Dutch carriers |
| Alliance + trade bonus | Cobden-Chevalier Treaty 1860; Anglo-Portuguese Treaty 1386 |
| Colbert's France | French mercantilist policy under Louis XIV (1661–1683) |
| VOC / Netherlands | Dutch East India Company joint-stock trade ships |
| Spain's Spices resource | Manila Galleon fleet; Spanish colonial monopoly |

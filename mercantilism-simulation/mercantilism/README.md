# Mercantilism Simulation

A Roblox game simulating mercantilist vs free-trade economics between four fantasy nations (Ironhaven, Goldspire, Emberveil, Drifthollow).

## How to Run

Open the latest versioned `.rbxl` file in Roblox Studio and hit **Play**.

---

## How to produce a new versioned `.rbxl` after code changes

All simulation logic lives in the `.lua` source files. The `.rbxl` is a binary
Roblox place file that embeds those scripts. To build a new versioned file after
making code changes, use **remodel**.

### Prerequisites

**remodel** must be installed once:

```bash
cargo install remodel
# adds ~/.cargo/bin/remodel
```

Requires Rust/Cargo. On Arch Linux it is already available:

```bash
cargo --version   # cargo 1.94.0 or later
```

### Workflow

#### 1. Make your code changes

Edit the source `.lua` files in `ReplicatedStorage/` and `ServerScriptService/`.

#### 2. Update CHANGELOG.md

Add a version entry describing what changed and why.

#### 3. Edit `patch_v52.lua` for the new version number

Open `patch_v52.lua` and update the two filename lines:

```lua
-- top: source base file (last stable version)
local game = remodel.readPlaceFile("MercantilismSimulation_v5.2.rbxl")

-- bottom: output file
remodel.writePlaceFile(game, "MercantilismSimulation_v5.3.rbxl")
```

#### 4. Run the patch script

From the `mercantilism/` directory:

```bash
~/.cargo/bin/remodel run patch_v52.lua
```

The new `.rbxl` file is created. Open it in Roblox Studio to test.

### Adding a new script to the patch

Add an entry to the `patches` table in `patch_v52.lua`:

```lua
{ parent = RS,  name = "MyNewModule", file = "ReplicatedStorage/MyNewModule.lua" },
```

Use `RS` for `ReplicatedStorage` and `SSS` for `ServerScriptService`.

### How it works internally

`remodel.setRawProperty(instance, "Source", "String", src)` — note `"String"`
with a capital S is the correct Roblox type name. `"string"` (lowercase) does
not work.

### Version naming convention

| Change type | Example |
|---|---|
| New feature or system | v5 → v6 |
| Bug fix or balance change | v5.2 → v5.3 |

---

## Project structure

```
mercantilism/
├── ReplicatedStorage/
│   ├── GameConfig.lua              constants
│   ├── NationState.lua             nation state & relationships
│   ├── TradeSystem.lua             export/import calculations
│   ├── NavalSystem.lua             plunder & arms race
│   ├── DiplomacySystem.lua         alliances, embargoes, privateers
│   └── DegradationSystem.lua       fleet decay & export penalties
├── ServerScriptService/
│   └── GameManager.server.lua      main simulation loop
├── StarterPlayer/StarterPlayerScripts/
│   └── SimulationUI.client.lua     HUD
├── patch_v52.lua                   remodel build script
├── default.project.json            Rojo project config (live sync alternative)
├── CHANGELOG.md                    version history
└── MercantilismSimulation_vX.Y.rbxl   versioned place files
```

---

## Live sync alternative (Rojo)

If you prefer live sync instead of building a new file each time:

1. Install the [Rojo plugin](https://www.roblox.com/library/13916111004/Rojo) in Roblox Studio
2. Run `rojo serve` in this directory
3. Open any `.rbxl` in Studio and click **Connect** in the Rojo plugin

Changes to `.lua` files will sync instantly into the open Studio session.

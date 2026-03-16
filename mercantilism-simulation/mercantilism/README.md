# Mercantilism Simulation

A Roblox game simulating mercantilist vs free-trade economics between four historical nations (England, France, Spain, Netherlands).

## How to Run

### Prerequisites

- [Roblox Studio](https://www.roblox.com/create) installed
- [Rojo](https://github.com/rojo-rbx/rojo) installed

**Install Rojo via cargo:**
```bash
cargo install rojo
```

Make sure `~/.cargo/bin` is in your PATH:
```bash
export PATH="$HOME/.cargo/bin:$PATH"
```

### Build and Open

Build the project into a `.rbxl` file:
```bash
rojo build -o MercantilismSimulation.rbxl
```

Then open `MercantilismSimulation.rbxl` in Roblox Studio and hit **Play**.

### Live Sync (Alternative)

If you want changes to sync live while editing the Lua files:

1. Install the [Rojo plugin](https://www.roblox.com/library/13916111004/Rojo) in Roblox Studio
2. Run `rojo serve` in the project directory
3. Connect via the Rojo plugin in Studio

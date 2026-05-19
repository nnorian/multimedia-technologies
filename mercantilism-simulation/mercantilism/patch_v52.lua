local game = remodel.readPlaceFile("MercantilismSimulation_v5.2.rbxl")

local RS  = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")

local patches = {
    { parent = RS,  name = "GameConfig",     file = "ReplicatedStorage/GameConfig.lua" },
    { parent = RS,  name = "NationState",    file = "ReplicatedStorage/NationState.lua" },
    { parent = RS,  name = "TradeSystem",    file = "ReplicatedStorage/TradeSystem.lua" },
    { parent = RS,  name = "NavalSystem",    file = "ReplicatedStorage/NavalSystem.lua" },
    { parent = RS,  name = "DiplomacySystem",file = "ReplicatedStorage/DiplomacySystem.lua" },
    { parent = SSS, name = "GameManager",    file = "ServerScriptService/GameManager.server.lua" },
}

for _, p in ipairs(patches) do
    local instance = p.parent:FindFirstChild(p.name)
    if instance then
        local src = remodel.readFile(p.file)
        remodel.setRawProperty(instance, "Source", "String", src)
        print("Patched: " .. p.name)
    else
        print("WARNING: not found: " .. p.name)
    end
end

remodel.writePlaceFile(game, "MercantilismSimulation_v5.3.rbxl")
print("Done! Saved: MercantilismSimulation_v5.3.rbxl")

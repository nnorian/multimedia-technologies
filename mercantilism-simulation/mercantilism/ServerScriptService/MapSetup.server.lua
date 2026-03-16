-- MapSetup.server.lua (v3 — mystical nations)
-- Builds the world geometry: sea, island cities, tall-mast ships, and trade routes.
-- Place in ServerScriptService

local RS      = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local Config  = require(RS:WaitForChild("GameConfig"))

-- ─── Atmosphere & Lighting ────────────────────────────────────────────────────

Lighting.Ambient        = Color3.fromRGB(70, 80, 110)
Lighting.OutdoorAmbient = Color3.fromRGB(115, 130, 160)
Lighting.FogEnd         = 900
Lighting.FogColor       = Color3.fromRGB(165, 195, 220)
Lighting.TimeOfDay      = "10:30:00"
Lighting.Brightness     = 2.2

do
    local atmo = Instance.new("Atmosphere")
    atmo.Density  = 0.30
    atmo.Offset   = 0.07
    atmo.Color    = Color3.fromRGB(185, 160, 115)
    atmo.Decay    = Color3.fromRGB(88, 110, 148)
    atmo.Glare    = 0.06
    atmo.Haze     = 1.0
    atmo.Parent   = Lighting
end

-- ─── Helpers ──────────────────────────────────────────────────────────────────

local function makePart(props)
    local part = Instance.new("Part")
    part.Anchored      = true
    part.CanCollide    = props.CanCollide == true  -- default false for decorative parts
    part.Name          = props.Name     or "Part"
    part.Size          = props.Size     or Vector3.new(4, 4, 4)
    part.CFrame        = props.CFrame   or CFrame.new(props.Position or Vector3.new(0, 0, 0))
    part.Material      = props.Material or Enum.Material.SmoothPlastic
    part.Color         = props.Color    or Color3.fromRGB(200, 200, 200)
    part.Transparency  = props.Transparency or 0
    part.TopSurface    = Enum.SurfaceType.Smooth
    part.BottomSurface = Enum.SurfaceType.Smooth
    if props.Shape then part.Shape = props.Shape end
    return part
end

local function makeWedge(props)
    local part = Instance.new("WedgePart")
    part.Anchored      = true
    part.CanCollide    = false
    part.Name          = props.Name     or "Wedge"
    part.Size          = props.Size     or Vector3.new(4, 4, 4)
    part.CFrame        = props.CFrame   or CFrame.new(props.Position or Vector3.new(0, 0, 0))
    part.Material      = props.Material or Enum.Material.SmoothPlastic
    part.Color         = props.Color    or Color3.fromRGB(200, 200, 200)
    part.Transparency  = props.Transparency or 0
    part.TopSurface    = Enum.SurfaceType.Smooth
    part.BottomSurface = Enum.SurfaceType.Smooth
    return part
end

-- Shorthand: make a part and immediately parent it
local function p(props, parent)
    local part = makePart(props)
    part.Parent = parent
    return part
end
local function w(props, parent)
    local part = makeWedge(props)
    part.Parent = parent
    return part
end

-- ─── City building helpers ────────────────────────────────────────────────────

-- Simple house: box body + pitched roof (two wedges)
local function makeHouse(model, base, wallC, roofC, width, depth, height)
    p({ Name="HouseWall", Size=Vector3.new(width, height, depth),
        Position=base + Vector3.new(0, height/2, 0),
        Color=wallC, Material=Enum.Material.Brick }, model)
    local ridgeH = math.floor(width * 0.45)
    local topY   = base.Y + height + ridgeH/2
    -- Front slope
    w({ Name="RoofA", Size=Vector3.new(width+0.4, ridgeH, depth/2+0.4),
        CFrame=CFrame.new(base + Vector3.new(0, topY, -depth/4-0.2)),
        Color=roofC, Material=Enum.Material.Brick }, model)
    -- Back slope (mirrored)
    w({ Name="RoofB", Size=Vector3.new(width+0.4, ridgeH, depth/2+0.4),
        CFrame=CFrame.new(base + Vector3.new(0, topY, depth/4+0.2)) * CFrame.Angles(0, math.pi, 0),
        Color=roofC, Material=Enum.Material.Brick }, model)
end

-- Square tower with optional crenellations
local function makeTower(model, base, color, w_, h, battlement)
    p({ Name="TowerBody", Size=Vector3.new(w_, h, w_),
        Position=base + Vector3.new(0, h/2, 0),
        Color=color, Material=Enum.Material.SmoothPlastic }, model)
    -- Parapet ring
    p({ Name="TowerParapet", Size=Vector3.new(w_+2, 2, w_+2),
        Position=base + Vector3.new(0, h+1, 0),
        Color=color, Material=Enum.Material.SmoothPlastic }, model)
    if battlement then
        -- 3 merlons per face × 4 faces
        for face = 0, 3 do
            local angle  = face * math.pi/2
            local outDir = Vector3.new(math.sin(angle), 0, math.cos(angle))
            local sideDir= Vector3.new(math.cos(angle), 0,-math.sin(angle))
            for k = -1, 1 do
                p({ Name="Merlon", Size=Vector3.new(1.5, 2.5, 1.5),
                    Position=base + Vector3.new(0, h+3, 0)
                             + outDir*(w_/2+0.5) + sideDir*(k*2.5),
                    Color=color, Material=Enum.Material.SmoothPlastic }, model)
            end
        end
    end
end

-- Slender spire (pointy top on a tower)
local function makeSpire(model, base, color, w_, h)
    p({ Name="SpireBase", Size=Vector3.new(w_, h*0.7, w_),
        Position=base + Vector3.new(0, h*0.35, 0),
        Color=color, Material=Enum.Material.SmoothPlastic }, model)
    w({ Name="SpireTip", Size=Vector3.new(w_+1, h*0.55, w_/2+0.5),
        CFrame=CFrame.new(base + Vector3.new(0, h*0.72 + h*0.55/2, 0)),
        Color=color, Material=Enum.Material.SmoothPlastic }, model)
    w({ Name="SpireTipB", Size=Vector3.new(w_+1, h*0.55, w_/2+0.5),
        CFrame=CFrame.new(base + Vector3.new(0, h*0.72 + h*0.55/2, 0))
              * CFrame.Angles(0, math.pi, 0),
        Color=color, Material=Enum.Material.SmoothPlastic }, model)
end

-- Tree
local function makeTree(model, pos, leafColor)
    p({ Name="Trunk", Size=Vector3.new(1.2, 4.5, 1.2),
        Position=pos + Vector3.new(0, 2.25, 0),
        Color=Color3.fromRGB(90, 58, 25), Material=Enum.Material.Wood }, model)
    p({ Name="Leaves", Size=Vector3.new(5.5, 5.5, 5.5),
        Position=pos + Vector3.new(0, 7.5, 0),
        Color=leafColor, Material=Enum.Material.Grass,
        Shape=Enum.PartType.Ball }, model)
end

-- Mystical windmill
local function makeWindmill(model, base, bodyColor)
    local h = 18
    p({ Name="WindmillBase", Size=Vector3.new(9, h, 9),
        Position=base + Vector3.new(0, h/2, 0),
        Color=bodyColor, Material=Enum.Material.Brick }, model)
    -- Roof (two wedges)
    w({ Name="MillRoofA", Size=Vector3.new(10, 6, 5.5),
        CFrame=CFrame.new(base + Vector3.new(0, h+3, -2.5)),
        Color=Color3.fromRGB(75, 48, 22), Material=Enum.Material.Wood }, model)
    w({ Name="MillRoofB", Size=Vector3.new(10, 6, 5.5),
        CFrame=CFrame.new(base + Vector3.new(0, h+3, 2.5)) * CFrame.Angles(0, math.pi, 0),
        Color=Color3.fromRGB(75, 48, 22), Material=Enum.Material.Wood }, model)
    -- Hub
    p({ Name="MillHub", Size=Vector3.new(2.5, 2.5, 2.5),
        Position=base + Vector3.new(0, h-3, 5.5),
        Color=Color3.fromRGB(140, 90, 40), Material=Enum.Material.Wood }, model)
    -- 4 blades arranged in X pattern
    for i = 0, 3 do
        local angle = i * math.pi/2
        local ox = math.sin(angle) * 7
        local oy = math.cos(angle) * 7
        p({ Name="Blade"..i, Size=Vector3.new(2, 12, 0.6),
            CFrame=CFrame.new(base + Vector3.new(ox, h-3+oy, 5.5))
                  * CFrame.Angles(0, 0, angle),
            Color=Color3.fromRGB(210, 195, 140), Material=Enum.Material.Wood }, model)
    end
end

-- ─── Ship builder helpers ─────────────────────────────────────────────────────

-- Weld a non-hull part to the hull so it moves with PivotTo
local function weldTo(part, hull)
    part.Anchored = false
    local wc  = Instance.new("WeldConstraint")
    wc.Part0  = hull
    wc.Part1  = part
    wc.Parent = hull
    return part
end

-- Build a trade ship model (all non-hull parts welded so PivotTo moves everything)
local function buildTradeShip(name, parent, spawnPos, nationColor)
    local model = Instance.new("Model")
    model.Name   = name
    model.Parent = parent

    local hullColor = nationColor
    local deckColor = Color3.new(nationColor.R*0.72, nationColor.G*0.72, nationColor.B*0.72)
    local woodDark  = Color3.fromRGB(90, 55, 18)

    -- Hull (anchored, PrimaryPart)
    local hull = p({ Name="Hull", Size=Vector3.new(6, 3, 14),
        Position=spawnPos,
        Color=hullColor, Material=Enum.Material.Wood,
        CanCollide=false }, model)
    model.PrimaryPart = hull

    -- Bow section: narrower block extending forward
    weldTo(p({ Name="Bow", Size=Vector3.new(4, 3, 5),
        Position=spawnPos + Vector3.new(0, 0, -9.5),
        Color=hullColor, Material=Enum.Material.Wood }, model), hull)

    -- Bowsprit: thin pole angled forward-up
    weldTo(p({ Name="Bowsprit", Size=Vector3.new(0.7, 0.7, 6),
        CFrame=CFrame.new(spawnPos + Vector3.new(0, 1.5, -13.5)) * CFrame.Angles(0.28, 0, 0),
        Color=woodDark, Material=Enum.Material.Wood }, model), hull)

    -- Deck
    weldTo(p({ Name="Deck", Size=Vector3.new(5.5, 0.5, 13),
        Position=spawnPos + Vector3.new(0, 1.8, 0),
        Color=deckColor, Material=Enum.Material.Wood }, model), hull)

    -- Stern cabin
    weldTo(p({ Name="Cabin", Size=Vector3.new(4.5, 2.5, 3.5),
        Position=spawnPos + Vector3.new(0, 3, 5.5),
        Color=deckColor, Material=Enum.Material.Wood }, model), hull)

    -- Mast
    local mastBase = spawnPos + Vector3.new(0, 1.8, -1)
    weldTo(p({ Name="Mast", Size=Vector3.new(1, 16, 1),
        Position=mastBase + Vector3.new(0, 8, 0),
        Color=woodDark, Material=Enum.Material.Wood }, model), hull)

    -- Main sail (cream canvas)
    weldTo(p({ Name="MainSail", Size=Vector3.new(7, 8, 0.35),
        Position=mastBase + Vector3.new(0, 11, 0),
        Color=Color3.fromRGB(240, 235, 205), Material=Enum.Material.Fabric,
        Transparency=0.08 }, model), hull)

    -- Crow's nest
    weldTo(p({ Name="CrowsNest", Size=Vector3.new(2.5, 0.8, 2.5),
        Position=mastBase + Vector3.new(0, 15, 0),
        Color=woodDark, Material=Enum.Material.Wood }, model), hull)

    -- Nation flag at masthead
    weldTo(p({ Name="Flag", Size=Vector3.new(2.5, 1.2, 0.2),
        Position=mastBase + Vector3.new(1.5, 15.8, 0),
        Color=nationColor, Material=Enum.Material.SmoothPlastic }, model), hull)

    return model
end

-- Build a warship model (wider, two masts, cannon ports — all parts welded)
local function buildWarShip(name, parent, spawnPos, nationColor)
    local model = Instance.new("Model")
    model.Name   = name
    model.Parent = parent

    local hullColor = Color3.new(nationColor.R*0.60, nationColor.G*0.60, nationColor.B*0.60)
    local deckColor = Color3.new(nationColor.R*0.45, nationColor.G*0.45, nationColor.B*0.45)
    local woodDark  = Color3.fromRGB(80, 48, 15)

    -- Hull (anchored, PrimaryPart)
    local hull = p({ Name="Hull", Size=Vector3.new(8, 4, 18),
        Position=spawnPos,
        Color=hullColor, Material=Enum.Material.Wood,
        CanCollide=false }, model)
    model.PrimaryPart = hull

    -- Bow section
    weldTo(p({ Name="Bow", Size=Vector3.new(5.5, 4, 6),
        Position=spawnPos + Vector3.new(0, 0, -12),
        Color=hullColor, Material=Enum.Material.Wood }, model), hull)

    -- Bowsprit
    weldTo(p({ Name="Bowsprit", Size=Vector3.new(0.9, 0.9, 8),
        CFrame=CFrame.new(spawnPos + Vector3.new(0, 2, -17)) * CFrame.Angles(0.28, 0, 0),
        Color=woodDark, Material=Enum.Material.Wood }, model), hull)

    -- Deck
    weldTo(p({ Name="Deck", Size=Vector3.new(7.5, 0.5, 17.5),
        Position=spawnPos + Vector3.new(0, 2.3, 0),
        Color=deckColor, Material=Enum.Material.Wood }, model), hull)

    -- Stern cabin (raised quarterdeck)
    weldTo(p({ Name="SternCabin", Size=Vector3.new(7, 3.5, 5),
        Position=spawnPos + Vector3.new(0, 4, 7),
        Color=deckColor, Material=Enum.Material.Wood }, model), hull)

    -- Cannon ports (3 per side)
    for side = -1, 1, 2 do
        for k = -1, 1 do
            weldTo(p({ Name="Cannon", Size=Vector3.new(1.5, 1, 2.5),
                Position=spawnPos + Vector3.new(side * 5.2, 0.5, k * 4),
                Color=Color3.fromRGB(35, 35, 35), Material=Enum.Material.Metal }, model), hull)
        end
    end

    -- Front mast
    local m1Base = spawnPos + Vector3.new(0, 2.3, -4)
    weldTo(p({ Name="Mast1", Size=Vector3.new(1, 20, 1),
        Position=m1Base + Vector3.new(0, 10, 0),
        Color=woodDark, Material=Enum.Material.Wood }, model), hull)
    weldTo(p({ Name="Sail1", Size=Vector3.new(9, 11, 0.35),
        Position=m1Base + Vector3.new(0, 13.5, 0),
        Color=Color3.fromRGB(210, 205, 180), Material=Enum.Material.Fabric,
        Transparency=0.08 }, model), hull)
    weldTo(p({ Name="CrowsNest1", Size=Vector3.new(3, 0.8, 3),
        Position=m1Base + Vector3.new(0, 19, 0),
        Color=woodDark, Material=Enum.Material.Wood }, model), hull)

    -- Rear mast (shorter)
    local m2Base = spawnPos + Vector3.new(0, 2.3, 4)
    weldTo(p({ Name="Mast2", Size=Vector3.new(1, 14, 1),
        Position=m2Base + Vector3.new(0, 7, 0),
        Color=woodDark, Material=Enum.Material.Wood }, model), hull)
    weldTo(p({ Name="Sail2", Size=Vector3.new(6, 7, 0.35),
        Position=m2Base + Vector3.new(0, 9.5, 0),
        Color=Color3.fromRGB(210, 205, 180), Material=Enum.Material.Fabric,
        Transparency=0.08 }, model), hull)

    -- War flag at front masthead
    weldTo(p({ Name="Flag", Size=Vector3.new(3, 1.5, 0.2),
        Position=m1Base + Vector3.new(1.8, 20.2, 0),
        Color=nationColor, Material=Enum.Material.SmoothPlastic }, model), hull)

    return model
end

-- ─── 1. Ocean ─────────────────────────────────────────────────────────────────

local ocean = makePart({
    Name       = "Ocean",
    Size       = Config.OCEAN_SIZE,
    Position   = Vector3.new(0, 0, 0),
    Color      = Color3.fromRGB(22, 78, 160),
    Material   = Enum.Material.Water,
    Transparency = 0.1,
    CanCollide = false,
})
ocean.Parent = workspace

-- Seabed layer gives depth illusion
p({ Name="Seabed", Size=Vector3.new(Config.OCEAN_SIZE.X, 4, Config.OCEAN_SIZE.Z),
    Position=Vector3.new(0, -4, 0),
    Color=Color3.fromRGB(20, 50, 90), Material=Enum.Material.SmoothPlastic,
    CanCollide=true }, workspace)

-- A few decorative cloud blocks high up
local cloudColor = Color3.fromRGB(240, 245, 255)
for _, cp in ipairs({
    {x= 80, z=  0, y=200, w=60, d=25},
    {x=-90, z= 70, y=220, w=80, d=30},
    {x= 30, z=-80, y=190, w=50, d=20},
    {x=-50, z=-50, y=210, w=70, d=28},
}) do
    p({ Name="Cloud", Size=Vector3.new(cp.w, 12, cp.d),
        Position=Vector3.new(cp.x, cp.y, cp.z),
        Color=cloudColor, Material=Enum.Material.Neon,
        Transparency=0.55, CanCollide=false }, workspace)
    -- Shadow blob on the ocean
    p({ Name="CloudShadow", Size=Vector3.new(cp.w*0.8, 0.3, cp.d*0.8),
        Position=Vector3.new(cp.x, 0.5, cp.z),
        Color=Color3.fromRGB(15, 55, 120), Material=Enum.Material.SmoothPlastic,
        Transparency=0.6, CanCollide=false }, workspace)
end

-- ─── 2. Islands with cities ───────────────────────────────────────────────────

local islandsFolder = Instance.new("Folder")
islandsFolder.Name   = "Islands"
islandsFolder.Parent = workspace

local mapCenter = Vector3.new(0, 1, 0)

for _, nd in ipairs(Config.NATIONS) do
    local islandModel = Instance.new("Model")
    islandModel.Name   = nd.name
    islandModel.Parent = islandsFolder

    local cx  = nd.position.X
    local cz  = nd.position.Z
    local top = nd.position.Y + Config.ISLAND_SIZE.Y   -- Y of the island top surface = 15

    -- ── IslandBase (referenced by DegradationSystem) ──────────────────────────
    local islandBaseY = nd.position.Y + Config.ISLAND_SIZE.Y / 2
    local islandBase = makePart({
        Name       = "IslandBase",
        Size       = Config.ISLAND_SIZE,
        Position   = Vector3.new(cx, islandBaseY, cz),
        Color      = Color3.fromRGB(95, 130, 60),
        Material   = Enum.Material.Grass,
        CanCollide = true,
    })
    islandBase.Parent = islandModel
    islandModel.PrimaryPart = islandBase

    -- Sandy beach ring
    p({ Name="SandRing",
        Size=Vector3.new(Config.ISLAND_SIZE.X+12, 2, Config.ISLAND_SIZE.Z+12),
        Position=Vector3.new(cx, 1, cz),
        Color=Color3.fromRGB(220, 195, 120), Material=Enum.Material.Sand,
        CanCollide=true }, islandModel)

    -- ── City Walls ────────────────────────────────────────────────────────────
    local wallColor  = Color3.fromRGB(145, 125, 100)
    local wallH      = 8
    local wallThick  = 3
    local wallRadius = Config.ISLAND_SIZE.X / 2 - 2  -- ~28 studs from center

    -- North & South walls (gaps left for port-facing side)
    for _, side in ipairs({-1, 1}) do
        p({ Name="Wall_NS", Size=Vector3.new(Config.ISLAND_SIZE.X - 12, wallH, wallThick),
            Position=Vector3.new(cx, top + wallH/2, cz + side * wallRadius),
            Color=wallColor, Material=Enum.Material.Brick }, islandModel)
    end
    -- East & West walls
    for _, side in ipairs({-1, 1}) do
        p({ Name="Wall_EW", Size=Vector3.new(wallThick, wallH, Config.ISLAND_SIZE.Z - 12),
            Position=Vector3.new(cx + side * wallRadius, top + wallH/2, cz),
            Color=wallColor, Material=Enum.Material.Brick }, islandModel)
    end
    -- Corner towers (4 corners)
    for _, cx2 in ipairs({cx - wallRadius, cx + wallRadius}) do
        for _, cz2 in ipairs({cz - wallRadius, cz + wallRadius}) do
            makeTower(islandModel, Vector3.new(cx2, top, cz2), wallColor, 5, 12, true)
        end
    end

    -- ── Nation-specific city layout ───────────────────────────────────────────
    local wallC  = nd.color
    local roofC  = Color3.fromRGB(
        math.floor(nd.color.R*255*0.55),
        math.floor(nd.color.G*255*0.55),
        math.floor(nd.color.B*255*0.55))
    local stoneC = Color3.fromRGB(180, 170, 155)

    if nd.name == "Ironhaven" then
        -- Dark iron citadel in centre
        makeTower(islandModel, Vector3.new(cx, top, cz), Color3.fromRGB(60, 65, 80), 10, 28, true)
        -- Flanking forge towers
        makeTower(islandModel, Vector3.new(cx-10, top, cz-8), Color3.fromRGB(70, 70, 85), 6, 18, true)
        makeTower(islandModel, Vector3.new(cx+10, top, cz-8), Color3.fromRGB(70, 70, 85), 6, 18, true)
        -- Forge glow (neon accent)
        p({ Name="ForgeGlow", Size=Vector3.new(6, 3, 6),
            Position=Vector3.new(cx, top+1.5, cz+12),
            Color=Color3.fromRGB(255, 100, 30), Material=Enum.Material.Neon,
            Transparency=0.3 }, islandModel)
        -- Smithy houses
        makeHouse(islandModel, Vector3.new(cx-16, top, cz+8),  Color3.fromRGB(90,85,80), Color3.fromRGB(50,50,55), 8, 10, 6)
        makeHouse(islandModel, Vector3.new(cx+15, top, cz+10), Color3.fromRGB(85,80,78), Color3.fromRGB(48,48,52), 7,  9, 5)
        -- Dark pines
        makeTree(islandModel, Vector3.new(cx+18, top, cz-14), Color3.fromRGB(25,70,35))
        makeTree(islandModel, Vector3.new(cx-18, top, cz-16), Color3.fromRGB(30,75,38))
        makeTree(islandModel, Vector3.new(cx+20, top, cz+2),  Color3.fromRGB(22,65,32))

    elseif nd.name == "Goldspire" then
        -- Grand golden palace
        p({ Name="Palace", Size=Vector3.new(22, 10, 14),
            Position=Vector3.new(cx, top+5, cz-4),
            Color=Color3.fromRGB(245, 225, 160), Material=Enum.Material.SmoothPlastic }, islandModel)
        -- Palace wings
        p({ Name="WingL", Size=Vector3.new(8, 8, 8),
            Position=Vector3.new(cx-15, top+4, cz-4),
            Color=Color3.fromRGB(245, 225, 160), Material=Enum.Material.SmoothPlastic }, islandModel)
        p({ Name="WingR", Size=Vector3.new(8, 8, 8),
            Position=Vector3.new(cx+15, top+4, cz-4),
            Color=Color3.fromRGB(245, 225, 160), Material=Enum.Material.SmoothPlastic }, islandModel)
        -- Golden spire at centre (neon glow)
        makeSpire(islandModel, Vector3.new(cx, top+10, cz-4), Color3.fromRGB(255, 200, 50), 5, 26)
        p({ Name="SpireGlow", Size=Vector3.new(3, 4, 3),
            Position=Vector3.new(cx, top+38, cz-4),
            Color=Color3.fromRGB(255, 220, 80), Material=Enum.Material.Neon,
            Transparency=0.2 }, islandModel)
        -- Side spires
        makeSpire(islandModel, Vector3.new(cx-15, top+8, cz-4), Color3.fromRGB(220, 180, 60), 3, 16)
        makeSpire(islandModel, Vector3.new(cx+15, top+8, cz-4), Color3.fromRGB(220, 180, 60), 3, 16)
        -- Enchanted garden (glowing topiary)
        for k = -1, 1 do
            p({ Name="Topiary", Size=Vector3.new(3.5, 3.5, 3.5),
                Position=Vector3.new(cx + k*8, top+1.75, cz+16),
                Color=Color3.fromRGB(80, 180, 60), Material=Enum.Material.Neon,
                Shape=Enum.PartType.Ball, Transparency=0.3 }, islandModel)
        end
        makeTree(islandModel, Vector3.new(cx-22, top, cz+10), Color3.fromRGB(60,140,50))
        makeTree(islandModel, Vector3.new(cx+22, top, cz+12), Color3.fromRGB(65,145,52))

    elseif nd.name == "Emberveil" then
        -- Volcanic fortress base
        p({ Name="FortBase", Size=Vector3.new(18, 6, 18),
            Position=Vector3.new(cx, top+3, cz),
            Color=Color3.fromRGB(120, 50, 30), Material=Enum.Material.Brick }, islandModel)
        -- Central ember tower
        makeTower(islandModel, Vector3.new(cx, top+6, cz), Color3.fromRGB(160, 60, 40), 8, 22, false)
        -- Glowing ember dome
        p({ Name="EmberDome", Size=Vector3.new(9, 9, 9),
            Position=Vector3.new(cx, top+6+22+4.5, cz),
            Color=Color3.fromRGB(255, 80, 20), Material=Enum.Material.Neon,
            Shape=Enum.PartType.Ball, Transparency=0.15 }, islandModel)
        -- Flanking towers
        makeTower(islandModel, Vector3.new(cx-9, top+6, cz), Color3.fromRGB(140, 55, 35), 5, 14, true)
        makeTower(islandModel, Vector3.new(cx+9, top+6, cz), Color3.fromRGB(140, 55, 35), 5, 14, true)
        -- Spice market houses
        makeHouse(islandModel, Vector3.new(cx-18, top, cz+12), Color3.fromRGB(180,100,50), Color3.fromRGB(130,40,25), 8, 10, 6)
        makeHouse(islandModel, Vector3.new(cx+16, top, cz+14), Color3.fromRGB(175,95,48),  Color3.fromRGB(125,38,22), 7,  9, 5)
        -- Lava pools (small neon accents)
        p({ Name="LavaPool", Size=Vector3.new(5, 0.5, 5),
            Position=Vector3.new(cx+18, top+0.3, cz-10),
            Color=Color3.fromRGB(255, 60, 10), Material=Enum.Material.Neon,
            Transparency=0.2 }, islandModel)
        makeTree(islandModel, Vector3.new(cx-20, top, cz-12), Color3.fromRGB(80,100,40))
        makeTree(islandModel, Vector3.new(cx,    top, cz+20), Color3.fromRGB(75,95,38))

    elseif nd.name == "Drifthollow" then
        -- Timber longhouses with stepped gables
        local houseColors = {
            Color3.fromRGB(140, 100, 55),
            Color3.fromRGB(120, 90, 50),
            Color3.fromRGB(110, 80, 42),
            Color3.fromRGB(130, 95, 52),
        }
        for k, hc in ipairs(houseColors) do
            local hx = cx - 18 + (k-1) * 12
            p({ Name="Longhouse"..k, Size=Vector3.new(9, 12, 8),
                Position=Vector3.new(hx, top+6, cz-8),
                Color=hc, Material=Enum.Material.Wood }, islandModel)
            for step = 1, 3 do
                p({ Name="Gable"..step, Size=Vector3.new(9 - step*2.5, 2, 1.5),
                    Position=Vector3.new(hx, top+12+step*2, cz-12.5),
                    Color=hc, Material=Enum.Material.Wood }, islandModel)
            end
        end
        -- Enchanted windmill with glowing blades
        makeWindmill(islandModel, Vector3.new(cx+14, top, cz+8), Color3.fromRGB(130, 90, 45))
        -- Spirit lanterns (neon floating lights)
        for _, lpos in ipairs({Vector3.new(cx-10,top+8,cz+14), Vector3.new(cx+5,top+6,cz+18)}) do
            p({ Name="SpiritLantern", Size=Vector3.new(2, 2, 2),
                Position=lpos,
                Color=Color3.fromRGB(100, 255, 180), Material=Enum.Material.Neon,
                Shape=Enum.PartType.Ball, Transparency=0.2 }, islandModel)
        end
        -- Dense forest
        makeTree(islandModel, Vector3.new(cx-22, top, cz+14), Color3.fromRGB(35,100,38))
        makeTree(islandModel, Vector3.new(cx+2,  top, cz+20), Color3.fromRGB(40,105,42))
        makeTree(islandModel, Vector3.new(cx-8,  top, cz+22), Color3.fromRGB(30,95,35))
    end

    -- ── Port (dock extending toward map centre) ───────────────────────────────
    local toCenter   = (mapCenter - nd.position)
    local toCenterXZ = Vector3.new(toCenter.X, 0, toCenter.Z)
    local portDir    = toCenterXZ.Magnitude > 0.01 and toCenterXZ.Unit or Vector3.new(0,0,1)
    local portLength = 22
    local portEdge   = Config.ISLAND_SIZE.X / 2
    local portCentre = Vector3.new(
        cx  + portDir.X * (portEdge + portLength/2),
        2,
        cz  + portDir.Z * (portEdge + portLength/2))
    local portCF = CFrame.lookAt(portCentre, portCentre + portDir)
    p({ Name="Port", Size=Vector3.new(9, 2, portLength),
        CFrame=portCF,
        Color=Color3.fromRGB(100, 72, 35), Material=Enum.Material.Wood,
        CanCollide=true }, islandModel)
    -- Dock pillars
    for pillar = -1, 1, 2 do
        p({ Name="DockPillar", Size=Vector3.new(1.2, 4, 1.2),
            Position=portCentre + portDir*(portLength/2-2)
                     + Vector3.new(-portDir.Z, -1, portDir.X) * (4.5 * pillar),
            Color=Color3.fromRGB(80, 55, 25), Material=Enum.Material.Wood }, islandModel)
    end
    -- Lighthouse near port entrance
    local lhBase = portCentre + portDir*(portLength/2+4)
                   + Vector3.new(-portDir.Z, -1, portDir.X) * 6
    p({ Name="LighthouseBody", Size=Vector3.new(3.5, 14, 3.5),
        Position=lhBase + Vector3.new(0, 7, 0),
        Color=Color3.fromRGB(235, 230, 220), Material=Enum.Material.SmoothPlastic }, islandModel)
    p({ Name="LighthouseTop", Size=Vector3.new(4, 3, 4),
        Position=lhBase + Vector3.new(0, 15.5, 0),
        Color=Color3.fromRGB(80, 30, 30), Material=Enum.Material.SmoothPlastic }, islandModel)
    p({ Name="LighthouseLight", Size=Vector3.new(2.5, 2, 2.5),
        Position=lhBase + Vector3.new(0, 18, 0),
        Color=Color3.fromRGB(255, 240, 80), Material=Enum.Material.Neon,
        Transparency=0.1 }, islandModel)

    -- ── Billboard labels (referenced by GameManager) ──────────────────────────
    -- Anchor high above the island so labels don't cover buildings
    local labelY  = islandBaseY + Config.ISLAND_SIZE.Y + 40
    local labelPart = makePart({
        Name       = "LabelAnchor",
        Size       = Vector3.new(1, 1, 1),
        Position   = Vector3.new(cx, labelY, cz),
        Transparency = 1,
        CanCollide = false,
    })
    labelPart.Parent = islandModel

    local nameBillboard = Instance.new("BillboardGui")
    nameBillboard.Name        = "NameLabel"
    nameBillboard.Size        = UDim2.new(0, 170, 0, 44)
    nameBillboard.StudsOffset = Vector3.new(0, 6, 0)
    nameBillboard.AlwaysOnTop = true
    nameBillboard.Parent      = labelPart

    local nameBg = Instance.new("Frame")
    nameBg.Size                 = UDim2.new(1, 0, 1, 0)
    nameBg.BackgroundColor3     = nd.color
    nameBg.BackgroundTransparency = 0.25
    nameBg.BorderSizePixel      = 0
    nameBg.Parent               = nameBillboard
    do
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 5)
        corner.Parent = nameBg
    end

    local nameText = Instance.new("TextLabel")
    nameText.Size              = UDim2.new(1, 0, 1, 0)
    nameText.BackgroundTransparency = 1
    nameText.Text              = nd.name
    nameText.TextColor3        = Color3.fromRGB(255, 255, 255)
    nameText.TextScaled        = true
    nameText.Font              = Enum.Font.GothamBold
    nameText.Parent            = nameBg

    local treasuryBillboard = Instance.new("BillboardGui")
    treasuryBillboard.Name        = "TreasuryLabel"
    treasuryBillboard.Size        = UDim2.new(0, 130, 0, 24)
    treasuryBillboard.StudsOffset = Vector3.new(0, -4, 0)
    treasuryBillboard.AlwaysOnTop = true
    treasuryBillboard.Parent      = labelPart

    local treasuryBg = Instance.new("Frame")
    treasuryBg.Size               = UDim2.new(1, 0, 1, 0)
    treasuryBg.BackgroundColor3   = Color3.fromRGB(10, 10, 10)
    treasuryBg.BackgroundTransparency = 0.35
    treasuryBg.BorderSizePixel    = 0
    treasuryBg.Parent             = treasuryBillboard
    do
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 4)
        corner.Parent = treasuryBg
    end

    local wealthText = Instance.new("TextLabel")
    wealthText.Name              = "WealthText"
    wealthText.Size              = UDim2.new(1, 0, 1, 0)
    wealthText.BackgroundTransparency = 1
    wealthText.Text              = "Treasury: 1,000g"
    wealthText.TextColor3        = Color3.fromRGB(255, 220, 50)
    wealthText.TextScaled        = true
    wealthText.Font              = Enum.Font.Gotham
    wealthText.Parent            = treasuryBg

    -- NationId value (referenced by GameManager)
    local idVal = Instance.new("IntValue")
    idVal.Name   = "NationId"
    idVal.Value  = nd.id
    idVal.Parent = islandModel
end

-- ─── 3. Ships ─────────────────────────────────────────────────────────────────

local shipsFolder = Instance.new("Folder")
shipsFolder.Name   = "Ships"
shipsFolder.Parent = workspace

for _, nd in ipairs(Config.NATIONS) do
    local toCenter   = (mapCenter - nd.position)
    local toCenterXZ = Vector3.new(toCenter.X, 0, toCenter.Z)
    local portDir    = toCenterXZ.Magnitude > 0.01 and toCenterXZ.Unit or Vector3.new(0,0,1)
    local portSpawn  = Vector3.new(
        nd.position.X + portDir.X * (Config.ISLAND_SIZE.X / 2),
        3,
        nd.position.Z + portDir.Z * (Config.ISLAND_SIZE.X / 2))

    for i = 1, Config.INITIAL_TRADE_SHIPS do
        local offset = Vector3.new(portDir.Z, 0, -portDir.X) * ((i - 1) * 9 - 4)
        buildTradeShip(nd.name .. "_TradeShip_" .. i, shipsFolder,
            portSpawn + offset, nd.color)
    end

    for i = 1, Config.INITIAL_WARSHIPS do
        local offset = Vector3.new(portDir.Z, 0, -portDir.X) * ((i - 1) * 11)
                     + portDir * 14
        buildWarShip(nd.name .. "_WarShip_" .. i, shipsFolder,
            portSpawn + offset, nd.color)
    end
end

-- ─── 4. Trade Route Visuals ───────────────────────────────────────────────────

local tradeRoutesFolder = Instance.new("Folder")
tradeRoutesFolder.Name   = "TradeRouteVisuals"
tradeRoutesFolder.Parent = workspace

local nations = Config.NATIONS
for i = 1, #nations do
    for j = i + 1, #nations do
        local n1, n2 = nations[i], nations[j]
        local p1 = Vector3.new(n1.position.X, 0.6, n1.position.Z)
        local p2 = Vector3.new(n2.position.X, 0.6, n2.position.Z)
        local mid  = (p1 + p2) / 2
        local dist = (p2 - p1).Magnitude

        local routePart = makePart({
            Name         = n1.name .. "_to_" .. n2.name,
            Size         = Vector3.new(1.5, 0.5, dist),
            CFrame       = CFrame.lookAt(mid, p2),
            Color        = Color3.fromRGB(255, 255, 200),
            Transparency = 0.65,
            CanCollide   = false,
        })
        routePart.Material = Enum.Material.Neon
        routePart.Parent   = tradeRoutesFolder
    end
end

-- ─── 5. TickComplete BindableEvent ────────────────────────────────────────────

local tickComplete = Instance.new("BindableEvent")
tickComplete.Name   = "TickComplete"
tickComplete.Parent = RS

print("[MapSetup] World created successfully (v3 — mystical nations)")

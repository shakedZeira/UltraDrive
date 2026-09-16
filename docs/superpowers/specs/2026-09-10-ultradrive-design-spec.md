# UltraDrive Design Specification

## Overview
UltraDrive is a hybrid open-world + circuit racing game built in Godot 4.7+ combining Forza Horizon 6's open-world festival exploration with Gran Turismo 7's simulation-grade track racing and car collecting.

## Game Vision
- **Open World**: Coastal highways, mountain passes, city streets, countryside — free roam, festivals, exploration events
- **Dedicated Tracks**: Circuit racing, rally stages, drift courses — simulation-grade physics
- **Career Mode**: License tests, championships, open world events, car collecting
- **Garage**: Car collection, tuning (suspension, tire pressure, gear ratios, aero), cosmetic customization

## Core Gameplay Loop
1. Player explores open world freely
2. Discovers events (races, time trials, drift challenges, exploration)
3. Earns currency and XP from events
4. Unlocks new cars via Garage purchases or event rewards
5. Tests skill via License Tests to unlock harder events
6. Progresses through Championship tiers
7. Participates in Festival events (open world spectacles)

## Game Modes

### Free Roam (Open World)
- No restrictions on where to drive
- Day/night and weather cycle active
- Traffic AI on roads
- Discoverable festival sites, gas stations, viewpoint landmarks
- Random events (street races, police chases — stretch goal)

### Circuit Race
- Pre-built track, 3-12 AI opponents
- Qualifying lap + main race
- Mechanical damage model (visual + handling impact)
- Weather variants

### Rally Stage
- Point-to-point timed stages
- Pace notes (codriver calls — stretch goal)
- Surface changes (tarmac → gravel → mud)
- Time penalty system

### Drift Challenge
- Judged drift zones (angle × speed × duration)
- Combo scoring system
- Anti-drift-grip toggle for setup tuning

### Time Trial
- Ghost replay comparison
- Leaderboard (local and online — stretch goal)
- Sector timing

### License Tests
- Structured skill progression challenges
- Bronze / Silver / Gold ratings
- Each license tier unlocks harder events

## Car Classes
All cars are fictional (no real-world brands). Classes based on performance:
| Class | Power (HP) | Weight (kg) | Power/Weight | Example Archetype |
|-------|-----------|-------------|--------------|-------------------|
| D | 80-150 | 900-1200 | 0.09-0.13 | Kei car, compact |
| C | 150-250 | 1100-1400 | 0.12-0.18 | Hot hatch, sports sedan |
| B | 250-400 | 1200-1500 | 0.18-0.27 | Sports coupe, muscle |
| A | 400-600 | 1300-1600 | 0.27-0.37 | Performance, supercar |
| S | 600-900 | 1200-1500 | 0.40-0.60 | Hypercar, race car |

## Vehicle Physics Specification

### Tire Model (Pacejka-Inspired Magic Formula)
```
Fy = D * sin(C * atan(B*α - E*(B*α - atan(B*α))))
```
Where:
- **B**: Stiffness factor (controls grip peak sharpness)
- **C**: Shape factor (determines curve shape — typically 1.3-1.9 for car tires)
- **D**: Peak force (normal_force × μ — friction coefficient × vertical load)
- **E**: Curvature factor (controls post-peak grip falloff)
- **α**: Slip angle (angle between wheel heading and velocity vector)

### Suspension Model
Per-wheel independent suspension:
- Spring-damper system: `F = -k*(x - rest_length) - c*dot(x)`
- Travel: 80-120mm typical range
- Anti-roll bar: distributes force between left/right wheels
- Ride height affects center of gravity dynamically

### Drivetrain
- Engine torque curve (RPM-dependent, varies per car)
- Transmission: 5-8 gear ratios (configurable per car)
- Differential: Open, Limited Slip (LSD), Locked
- Drive layouts: FWD, RWD, AWD (configurable per car)
- Clutch simulation (simplified for arcade feel)

### Weight Transfer
- Longitudinal: braking shifts weight forward, acceleration shifts backward
- Lateral: cornering shifts weight to outside wheels
- Center of gravity: affects rollover threshold and handling balance
- Dynamic weight affects tire normal forces → affects grip

### Drift Mechanics
- Handbrake reduces rear tire grip multiplier
- Counter-steer detection applies corrective yaw torque
- Speed-dependent grip cap: drift emerges naturally when lateral force exceeds grip limit
- Surface-dependent: tarmac (high grip), gravel (low grip), wet (reduced grip)

### Handling Modes
Player can switch between two handling profiles:
- **Arcade**: Forgiving grip, reduced weight transfer, boosted drift, stronger anti-flip
- **Simulation**: Realistic grip, full weight transfer, harder drift threshold, realistic rollover

## Open World Specification

### Map Scale
- Target: 8km × 8km playable area (64 km²)
- Terrain height variation: ±300m from sea level
- Roads: ~40km of drivable roads (mix of highways, mountain passes, city streets)

### Terrain System
- Terrain3D plugin for clipmap-based LOD terrain
- ProtonScatter for procedural foliage placement
- Chunk-based streaming: 256m × 256m terrain tiles
- 9-level LOD hierarchy (distance-based detail reduction)

### World Streaming (OWDB)
- Open World Database addon for chunk-based object streaming
- Load radius: ~500m around player camera
- Object categories: buildings (large chunks), props (medium chunks), foliage (fine chunks)
- Memory budget: max 2GB RAM for world data

### Road System
- Spline-based road network
- Lane markings, shoulders, curbs, barriers
- Intersection/roundabout support
- Dynamic road conditions (wet, icy, gravel sections)

### Weather System
- Dynamic weather states: Clear, Cloudy, Rain, Storm, Fog, Snow
- Transition blending between states (smooth 30-second transitions)
- Road surface affected by weather (wet = reduced grip, ice = very low grip)
- Day/night cycle: 1 real hour = 1 game day (24:1 ratio) — configurable

### Traffic AI
- Non-player vehicles on roads (10-30 active at a time)
- Follow road splines, obey lane rules
- Collision avoidance with player and other traffic
- Varied vehicle types and speeds

## Race System Specification

### Checkpoint System
- Invisible checkpoint zones along track
- Anti-cheat: checkpoints enforce correct driving direction and order
- Cut detection: if player skips checkpoints → penalty or disqualification

### Lap System
- Configurable lap count (1-10 laps)
- Sector timing (3 sectors per track)
- Best lap / personal best tracking

### Rubber-Banding AI
- AI opponents adjust performance based on gap to player
- Within 2s: AI runs at 100% pace
- 5s+ ahead: AI pace reduced to 95%
- 5s+ behind: AI pace boosted to 105%
- Configurable per difficulty setting (Easy/Medium/Hard/Expert)

### Race Start
- Grid position determined by qualifying time or reverse championship standings
- Standing start with countdown (5-4-3-2-1-GO)
- False start penalty (2-second time penalty)

## Career Mode Specification

### License System
5 license tiers: B, A, S, Race, Elite
Each tier has 3 tests (bronze/silver/gold):
- **B License**: Basic driving (acceleration, braking, cornering, parallel park)
- **A License**: Advanced (racing line, overtaking, braking zones, speed control)
- **S License**: Expert (drifting, high-speed corners, wet weather, rally basics)
- **Race License**: Full race (race craft, pit strategy, endurance)
- **Elite License**: Time attack (precision driving, sector optimization)

### Championship System
5 championship tiers, each with 4 races:
- Each championship has a theme (city circuit, mountain pass, mixed terrain, etc.)
- Points system: 1st=25, 2nd=18, 3rd=15... (F1-style)
- Must have minimum license tier to enter
- Prize money + car unlock rewards

### Garage System
- Player owns a garage (physical space in open world)
- Cars displayed on ramps/platforms
- Purchase new cars from dealership (menu-based)
- Sell unwanted cars
- View car stats, photos, and driving history

### Car Tuning
Adjustable parameters per car:
- Tire pressure (front/rear independently)
- Suspension stiffness (spring rate)
- Suspension damping
- Ride height
- Gear ratios (individual or preset)
- Differential type and lock percentage
- Downforce (aero — for cars with wings)
- Brake balance (front/rear distribution)

## UI/UX Specification

### HUD (In-Race)
- Speedometer (analog dial + digital readout)
- Tachometer (RPM gauge)
- Current gear indicator
- Mini-map (top-down, shows player, opponents, checkpoints)
- Position indicator (1st/2nd/3rd...)
- Lap counter and sector times
- Speed boost indicator (if applicable)
- Damage indicator (visual + handling feedback)

### Menus
- **Main Menu**: Play, Garage, Settings, Quit
- **World Map**: Fast travel points, event markers, player location
- **Garage Menu**: View cars, select car, tune car, sell car
- **Race Menu**: Track info, AI difficulty, weather, number of laps
- **Settings**: Video, Audio, Controls, Gameplay

### Minimap
- Circular minimap centered on player
- Shows road network, player position/direction
- Event markers (races, drift zones, etc.)
- Can zoom in/out
- Toggle on/off during gameplay

## Technical Architecture

### Engine: Godot 4.7+ (latest stable)
- Vulkan Forward+ renderer
- Jolt Physics GDExtension addon
- GDScript primary, C# for performance-critical systems only

### Rendering Budget (1080p High, 60 FPS target)
- MSAA: 2x
- SSAO: Medium
- Glow/Bloom: Low
- Shadow resolution: 2048x2048 (directional light)
- Draw distance: 800m (terrain), 500m (objects), 300m (foliage)
- Reflection probes: static baked + 1 dynamic per frame

### Input System
- PS5 DualSense via DS4Windows (emulates XInput)
- InputAction-based (Godot's built-in system — no hardcoded buttons)
- Keyboard fallback (WASD/arrows)
- Controller: triggers = throttle/brake, left stick = steering, right stick = camera, D-pad = UI navigation, A/Cross = select, B/Circle = back, Y/Triangle = handbrake, X/Square = reset car

### Data Persistence
- JSON save files stored in user:// (mapped to AppData on Windows)
- Save slots: 3 slots (user can choose)
- Data saved: money, XP, owned cars, car tunings, best times, completed events, license progress

### Performance Targets
- **Target**: 1080p, High preset, 60 FPS
- **Minimum GPU**: GTX 1650 / RX 5500 XT
- **Recommended GPU**: RTX 3060 / RX 6600
- **RAM**: 8GB minimum, 16GB recommended
- **Storage**: 15GB installed

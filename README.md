# Foundry Frontier — Godot Rewrite

A clean Godot 4 rewrite of Foundry Frontier, designed around a data-driven factory simulation rather than a direct port of the Phaser codebase.

## Current vertical slice

- 48×32 procedurally seeded industrial grid
- Iron, copper, and coal resource fields
- Camera movement, pan, and zoom
- Directional building placement and visible output arrows
- Electric miners, belts, furnaces, assemblers, generators, storage, and a protected Command Core
- Power generation, demand, and brownout efficiency
- Data-driven items, recipes, and building definitions
- Per-machine recipe selection
- Technology tree that gates buildings and recipes behind research
- Delivery contracts that reward credits and research
- Area dismantling with refunds
- Inspector, build dock, status feedback, credits, research, and power HUD
- JSON save/load through `user://foundry_frontier_save.json`

## Open the project

1. Install Godot 4.3 or newer.
2. Import `project.godot`.
3. Run the project with F6/F5.

## Controls

| Control | Action |
| --- | --- |
| WASD / arrows | Move camera |
| Middle mouse drag | Pan camera |
| Mouse wheel | Zoom |
| 1 – 6 | Select belt / miner / furnace / generator / assembler / storage |
| Left click | Place or inspect |
| Left click + drag | Lay a line of belts (auto-oriented to the drag) |
| Right click | Remove a single structure (65% refund) |
| R | Rotate placement direction |
| X | Select area dismantle |
| Esc | Inspect mode (stop building) |
| F5 | Save |

## Architecture

- `scripts/core/` — persistent state and data registry
- `scripts/world/` — grid, simulation, placement, power, logistics, drawing
- `scripts/ui/` — HUD and inspector
- `data/` — item, machine, and recipe definitions
- `scenes/` — Godot scene composition

## Next milestones

1. Replace placeholder vector drawing with authored sprite scenes and normal maps.
2. Convert belts to explicit two-lane item entities with curved paths and pooling.
3. Add recipe selection, technology tree, mission progression, and production codex.
4. Add chunked world rendering, simulation profiling, audio, particles, and shaders.
5. Add automated GUT tests and desktop export workflows.

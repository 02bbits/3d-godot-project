# Nine GridMap arenas

## Expansion and playable floors

The four approved arena footprints are retained. Their horizontal dimensions
increased by exactly 20%: the 4 m module became 4.8 m, with mesh and collision
transforms enlarged together. Ground area therefore increased by 44%. Floor
thickness, player dimensions, and vertical distances retain their existing scale.

Eight arenas have three major playable heights at 0, 4 and 8 m above the ground
floor base. Spire has four at 0, 4, 8 and 12 m. Ramps also pass through intermediate
heights; those transitions are not counted as additional floors. Floor surfaces
are 0.5 m above their base. Blue identifies the middle galleries; yellow identifies
the upper floors and approaches. Stacked routes have room for the player's capsule.

All nine maps use baked, directly editable GridMaps and reflect on both X and Z
axes. No generator executes during a match. Outer edges remain open. Existing
player kill-height behavior handles falls. The new scenes are registered in
world.gd's MAP_PATHS, which also populates the lobby selector and map rotation.

| Arena | Footprint | Playable floor bases | Tiles per floor | Structure |
| --- | --- | --- | --- | --- |
| Cross | 100.8 x 100.8 m | 0, 4, 8 m | 233/45/9 | Cruciform terraces with a raised crossing and four ground bypasses |
| Lanes | 72 x 110.4 m | 0, 4, 8 m | 267/87/55 | Double-H silhouette with twin upper galleries, three links and a lower court |
| Pillars | 100.8 x 100.8 m | 0, 4, 8 m | 269/28/9 | Clover outline with a raised octagonal pavilion and open lower courtyard |
| Ring | 100.8 x 100.8 m | 0, 4, 8 m | 320/101/9 | Octagonal outer loop with an open moat and four bridges to a raised hub |
| Citadel | 120 x 120 m | 0, 4, 8 m | 481/96/25 | Diamond bastions, an elevated fortress ring and a high central keep |
| Foundry | 120 x 72 m | 0, 4, 8 m | 287/87/39 | Twin industrial courtyards, gallery loops and an overhead gantry |
| Causeway | 72 x 129.6 m | 0, 4, 8 m | 345/127/49 | Forked hourglass with broad end plazas and three stacked central routes |
| Butterfly | 110.4 x 110.4 m | 0, 4, 8 m | 293/141/45 | Four diagonal wings feeding a central sky pavilion |
| Spire | 120 x 120 m | 0, 4, 8, 12 m | 397/136/28/9 | Four playable heights around a central tower with a skylight and crown |

## Asset analysis and details

The source is the project's existing KayKit Prototype library. Its modular
meshes are centered on X/Z, have bottom-origin Y coordinates, and already contain
triangle collision shapes. The derived `resources/worlds/arena_mesh_library.tres`
changes each selected mesh transform and its collision transform together.

| Source asset | Authored module | Purpose |
| --- | --- | --- |
| Floor / Floor_Prototype | 4.8 x 4.8 m, 0.5 m thick | Ground and middle decks |
| Primitive_Floor | 4.8 x 4.8 m, compressed to 0.5 m thick | Upper decks |
| Primitive_Slope | 2 m rise over 4.8 m run | About 22.6 degree approaches |
| Cube_Prototype_Large_A / Primitive_Cube | 4.8 x 4.8 m, 2 m high | Foundations and supports |
| Cube_Prototype_Small | 2.4 x 2.4 m, 1.5 m high | Low cover |
| Cube_Prototype_Large_B | 4.8 x 4.8 m, 4 m high | Sightline blockers |
| Primitive_Doorway / Window / Pillar | Compressed to 3.5 m high | Gates, gantry frames, pavilion columns |
| Wall_Decorated | 3.5 m high | Detailed wall segments |
| Floor_Dirt | 4.8 x 4.8 m | Warm approach and plaza inlays |
| Barrels and decorated pallets | Matched horizontal enlargement | Supply clusters and stacked cover detail |
| Primitive_Wall_Half | Compressed to 1.5 m high | Selected balcony cover |

Details are placed around routes rather than filling them indiscriminately.
They include mirrored supply clusters, stock stacked on tall cover, windowed wall
segments, warm floor inlays, short balcony panels, and recognizable upper-tier
architecture. Ramp cells and approach/exit cells are kept clear of cargo. Upper
floor tiles above ramp shafts are removed to avoid head collisions.

The central upper landmarks differ: Cross and Pillars have gateways, Lanes has
gallery frames, Ring has a hub column, Citadel has a four-gate keep, Foundry has
gantry arches, Causeway has observation frames, Butterfly has a pavilion, and
Spire has a tower crown.

## Editing

The following GridMaps separate authored content. These editor layers do not
represent the count of playable floors.

| GridMap | Responsibility |
| --- | --- |
| Tiles | Ground slabs and floor inlays |
| Foundations | Thickness below the ground |
| Decks | Middle floor at 4 m |
| SkyDecks | Upper floor at 8 m |
| CrownDecks | Spire's crown at 12 m |
| Supports / RampFootings | Platform and slope supports |
| Ramps | Approaches between each pair of floors |
| Structures | Arches, windows and columns |
| Cover | Low cover, tall blocks and cargo |
| Details | Wall segments, supplies and balcony panels |

The cell size is 4.8 x 2 x 4.8 m. X/Z offsets center cell `(0, 0, 0)` on the
world origin. Spawn markers retain their stable names, `spawn_point` group, and
floor-base Y convention, and face inward. Existing arena UIDs are preserved;
the five new scenes have distinct UIDs. The original KayKit assets are unchanged.

## Final verification

- Godot 4.7.2 loaded and rendered every arena and the shared mesh library.
- All authored placements passed reflection and cell-count checks.
- All 36 spawn positions have a floor and clear space for a 2 m tall,
  0.4 m radius capsule.
- A CharacterBody3D using gravity 24 successfully traversed all 154 ramp lanes
  without jumping, including transitions onto the third and fourth floors.
- Final rendered views were inspected after the upper architecture pass.
- The required headless runtime startup completed without errors; the existing
  main.tscn/testing_area.tscn UID warning remains and resolves by resource path.
- The five new map paths are appended to the existing dynamic lobby/rotation
  registry. Git diff formatting checks pass.
- The modifier checker listed in AGENTS.md is absent from this checkout;
  no modifier logic or resources changed.

Live multiplayer balance and movement-modifier combinations need playtesting.

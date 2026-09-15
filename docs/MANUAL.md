# FPS Project — Manual

A multiplayer FPS prototype built with Godot 4.7 (Forward Plus, Jolt physics) and the **Fusion** addon (GDExtension binding to Photon). All game code is GDScript.

This document is the onboarding manual: how to run the project, how each system works, where things live, and how to extend them.

---

## 1. Getting started

### Prerequisites
- **Godot 4.7** (project was built with 4.7.2). Older 4.x versions will not open the Fusion GDExtension (min 4.6 required by the addon).
- No account/setup needed for Photon: the app id is embedded in `project.godot` under `[fusion]` → `connection/app_id`.
- **Region is pinned to `fusion/connection/default_region` (`asia`)** in `multiplayer.gd::_connect_to_photon`. Passing no region makes Fusion pick `best` per machine, and clients in different Photon regions cannot see each other's rooms (`Game does not exist`, code 22) — two editor instances on one machine always agree, so this only breaks exported clients on other machines. Change the setting (not the call) to move regions.

### Opening and running
1. Open the project folder in Godot 4.7. First open triggers an import pass (FBX assets, sounds) — let it finish.
2. The main scene is `world.tscn` (set in `project.godot` → `run/main_scene`). Press **F5** (Run Project).
3. On start, the **lobby overlay** appears: type a room name (a random one is prefilled) and **Create Room** to host, or **Join Room** to join an existing one. Joining a room spawns your player; the overlay hides and the mouse is captured.
4. To play together, one instance creates a room; every other instance joins with the **same room name** (or double-clicks it in the room browser list). Both instances then see each other's player as a red capsule.

### Testing multiplayer locally
Run the project **twice** (two editor instances, or one editor + one exported build). In one, **Create Room** (keep the prefilled name); in the other, type the same name and **Join Room** (or pick it from the browser list after Refresh). Each sees the other's player as a red capsule.

- Left mouse button: shoot
- R: reload
- WASD/Space/Ctrl/Shift: the Jeheno controller's walk/run/jump/crouch/dash/slide/wallrun moves

There is an automated two-client network check in `tools/`:

```
# terminal 1
godot --headless res://tools/rpc_test.tscn -- --sender
# terminal 2 (start a few seconds later)
godot --headless res://tools/rpc_test.tscn
```

The sender fires a shot through the production code path; the receiver prints `TEST PASS` when the visual bullet/impact appears on its side. Use this to verify netcode after changes.

---

## 2. Project structure

```
world.tscn                  main scene (root "World", script scripts/network/multiplayer.gd)
scripts/
  network/multiplayer.gd    room connect/join + player spawn/despawn bootstrap
  player/
	player.tscn             the spawnable player scene (FusionSpawner spawnable)
	player_character_scene.tscn   older duplicate (unused)
	gun.tscn / gun.gd       the weapon: shooting, muzzle flash particles, sounds
	gun.gd
  entities/
	bullet/bullet.gd        the projectile logic
	enemy/enemy.gd          enemy logic (local-only, see limitations)
  scenes/…                  older duplicate scenes (unused)
  effects/impact.gd         one-shot impact particle burst + sound
  performance/LightOptimizer.gd   retunes all lights at startup (perf guard)
scenes/
  entities/bullet.tscn      the bullet (Area3D, capsule mesh, collision)
  effects/impact.tscn       impact VFX scene (GPUParticles3D + AudioStreamPlayer3D)
  testing/testing_area.tscn the playable map
assets/
  KayKit_Prototype_Bits_1.1_FREE/   map kit (Floor/Wall/primitives/props FBX)
  audio/                    CC0 Kenney sounds (laser shots, impacts, reload clicks)
  Zombie/                   unused zombie enemy art
addons/
  fusion/                   Fusion GDExtension (Photon) — do not edit
  JehenoAdvancedFirstPersonController/  first person controller asset (state machine movement)
tools/                      one-off debug scripts and the rpc_test scene
Prefabs/, Meshes/, CyberMap.scn, model.obj, materials.mtl
							leftovers of an abandoned cyberpunk map (unused, see §7)
```

> Note: `scripts/player/gun.tscn` is the **active** gun scene (referenced by `player.tscn`). The copies under `scenes/player/` and `scenes/main/` are legacy.

---

## 3. Networking model (Fusion / Photon)

Fusion is a Photon wrapper exposed as the global `Fusion` singleton. Key facts for working in this codebase:

| Concept | Where | What it does |
|---|---|---|
| `FusionSpawner` | `world.tscn` root level | Spawns networked scenes. `scripts/network/multiplayer.gd` validates a map spawn marker before calling `spawner.spawn()` and tracks the local player. Departed replicas are removed through Fusion when possible, with a local fallback after the owner is gone. |
| Lobby overlay | `world.tscn` → `Lobby` (`scripts/ui/lobby.gd`) | Create/Join room by name, room browser (`Fusion.get_room_list` + `room_list_updated`), status/errors via `multiplayer.room_error`. Shown at startup and again on `room_left`; hides on `room_joined`. |
| `FusionSharedReplicator` | child of each player (`player.tscn`) | Shared-authority replication. Root transform/velocity replication is enabled; the custom config (`scripts/network/view_config.tres`) adds interpolated `view_pitch` and `view_yaw` so remote copies aim their visible gun. |
| `Fusion.rpc(callable, ...args)` | room broadcast | Calls the method (by `Callable(target, "method")`) on **every peer**, mapped to each peer's corresponding replica of that node. The sending peer also receives its own broadcast, so RPC handlers usually start with `if is_remote: ...`. |
| `Fusion.rpc_to(target, callable, args)` | | Targeted RPC. `Fusion.TARGET_OWNER` routes to the owner client of a replica. |
| Authority | `FusionSharedReplicator.has_authority()` | False on remote copies. `player_character_script.gd::setup_network_control()` uses it to set `is_remote`, disable local physics/input/camera, and put the body on render layer 1 with a red tint. |

### RPC methods on the player
All in `addons/JehenoAdvancedFirstPersonController/PlayerCharacter/StateMachine/player_character_script.gd`:

- `rpc_take_damage(amount)` — routes damage to the victim's authoritative machine
- `shot_fx(from, dir)` — remote replicas replay the shot (anim + muzzle flash + sound + visual bullet)
- `reload_fx()` — remote replicas replay the reload anim + sound
- `died_fx()` / `respawn_fx()` — remote replicas hide/show the dead player's model/weapon

> The `@rpc("any_peer")` annotations on these methods configure Fusion's RPC routing — keep them.

### Spawn positions
Spawn points are authored as `Marker3D` nodes under `scenes/testing/testing_area.tscn/SpawnPoints` and grouped as `spawn_point` (emitted by `tools/gen_testing_area.py`). `multiplayer.gd` validates each candidate against the map floor, floor angle, player capsule, ceiling, and existing players before spawning. Candidate order starts from the local Photon player id, then falls back through the remaining markers.

Normal restart is an in-room respawn. The existing network player is reset instead of disconnecting Photon or reloading `world.tscn`. Health, stamina, velocity, movement state, weapon ammo/reload state, hitbox, camera, HUD, mouse mode, and dead visuals are reset together.

### Known networking limitations
- **Shared Authority remains client-authoritative.** This is suitable for trusted co-op, not a cheat-resistant competitive FPS. Client-Server Fusion topology is still required for competitive production.
- The bundled Fusion preview crashes when the optional pre-spawn callback, `PlayerAttached` ownership, extra custom replication properties, or **instantiating the player scene outside the tree** (its `FusionSharedReplicator` registers with the native client and corrupts the real spawn) are used. The implementation therefore assigns the validated transform immediately after `spawn()`, mirrors the hitbox capsule with `CapsuleShape3D.new()` for spawn validation, performs explicit local cleanup, and syncs dead/respawn visuals with RPCs. Upgrade the native Fusion addon before replacing those fallbacks.
- The room is created/joined from the lobby (`Fusion.create_room` / `Fusion.join_room` in `scripts/network/multiplayer.gd`, driven by `scripts/ui/lobby.gd`) with a 6-player cap (matches the six spawn markers), a 10s player TTL for crashed clients, and a 30s empty-room TTL. There is no dedicated room-join-failed signal in this Fusion build, so a failed create/join (name taken, room full, room gone) is detected by an 8s watchdog and surfaced as `room_error` to the lobby. The room browser (`Fusion.get_room_list` + `room_list_updated`) lists every public room of this shared worldwide demo app id. Hard-killed clients leave ghosts until the player TTL reaps them; graceful exits call `Fusion.leave_room()` from `_exit_tree`.
- Enemies are spawned per-client by a local spawner (`scripts/entities/enemy/spawner.gd`) and are not networked at all.

---

## 4. Shooting system

### Fire flow (local shooter, `scripts/player/gun.gd`)
`_shoot()` (triggered by LMB in `_unhandled_input`):
1. Checks ammo/reload/cooldown, plays the `shoot` animation.
2. Forces the muzzle raycast (`Muzzle/WeaponRaycast`, 60m) to find the aim point.
3. `_spawn_bullet(muzzle_pos, aim_target, visual_only=false)` — instantiates `scenes/entities/bullet.tscn` under the current scene, oriented along the aim direction.
4. `_play_fire_fx()` — muzzle flash particles + flash light + random laser sound.
5. `_route_fx("shot_fx", [muzzle_pos, aim_fwd])` — broadcasts the shot to all peers via Fusion.rpc.

### Bullet (`scenes/entities/bullet.tscn` + `scripts/entities/bullet/bullet.gd`)
- Area3D moving at 140 m/s along its local -Z, 3s lifetime.
- On `body_entered`:
  - **authoritative bullets** (`visual_only == false`): damage enemies (`take_damage(1)`) directly, damage players via `Fusion.rpc_to(TARGET_OWNER, rpc_take_damage, 10)` so health decrements on the victim's own machine;
  - **visual bullets** (`visual_only == true`, spawned by remote replicas): no damage — the shooter's own bullet is the damage authority.
- Both kinds spawn the impact VFX (`scenes/effects/impact.tscn`) at the hit point and free themselves.

### Shot visibility across clients (how it works)
The shooter broadcasts `shot_fx(muzzle_pos, aim_dir)`. On every other client, Fusion invokes it on that player's replica; the handler calls `gun.fire_visual(from, dir)` which:
- plays the shoot animation,
- triggers the same muzzle flash/light/sound on the replica's gun,
- spawns a **visual-only** bullet (same scene, `visual_only = true`) that still produces impact particles locally when it hits geometry.

Damage stays authoritative on the shooter's client only — no double damage.

### Damage model
- Enemy hit: 1 damage (`enemy.take_damage`)
- Player hit: 10 damage via owner-targeted RPC
- Gun stats: 30 mag / 90 reserve / 0.15s fire interval / 1.2s reload (exports on `gun.gd`)

---

## 5. Gun VFX & audio

All combat VFX is built with **traditional Godot particle systems** (GPUParticles3D scenes), not runtime script-generated meshes:

- **Muzzle flash** — `scripts/player/gun.tscn` → `Muzzle/MuzzleFlash` (one-shot GPUParticles3D: spark cone along the muzzle's local -X, additive emissive quads, hot-white → pink → cyan color ramp) + `Muzzle/FlashLight` (OmniLight3D, energy 3.0, faded out over 0.12s by a tween in `gun.gd::_play_fire_fx()`). Trigger with `muzzle_flash.restart()`.
- **Impact** — `scenes/effects/impact.tscn` (root GPUParticles3D + script `scripts/effects/impact.gd`): one-shot 16-particle spark burst + `AudioStreamPlayer3D` playing a random impact sound with pitch variation. Frees itself on the particles' `finished` signal.
- **Sounds** (`assets/audio/`, all CC0 from Kenney's Sci-Fi/RPG packs — see `LICENSE-Kenney-CC0.txt`):
  - shoot: `laserLarge_000..002.ogg` (random pick + ±5% pitch)
  - impact: `impactMetal_000/001.ogg`
  - reload: `metalLatch.ogg` / `metalClick.ogg`

To add VFX: author a GPUParticles3D node in the scene editor (one_shot + explosiveness 1.0 for bursts), trigger with `restart()`, free via the `finished` signal. To add sounds: drop `.ogg` files under `assets/audio/`, let Godot import, assign to an `AudioStreamPlayer3D`.

> `scripts/performance/LightOptimizer.gd` clamps every Light3D at startup (energy ≤ 4.0, omni range ≤ 25, shadows off). Keep new VFX lights under those caps.

The old script-generated effect classes (`MuzzleEffect.gd`, `BulletEffect.gd` — ~1200 lines of tween-built meshes) were deleted when the particle versions replaced them.

---

## 6. Map

The playable map is `scenes/testing/testing_area.tscn`, instanced by `world.tscn`. It is hand-placed KayKit Prototype Bits kitbash — **no GridMap, no CSG**, just instanced FBX scenes under organized container nodes. The whole map (pad, walls, obstacles, targets, spawn markers) is generated by `tools/gen_testing_area.py`; edit its spec lists and re-run it rather than hand-editing the scene:

- `Pad` — 4m-grid floor tiles (`Floor.fbx`), currently x ∈ [-18, 18], z ∈ [-36, 8] (120 tiles, 40m × 48m)
- `Walls` — `Wall.fbx` perimeter: side walls at x = ±20 (rotated 90°, two stacked rings per row position — the wall FBX is narrower than a tile), back walls at z ≈ -38 and z ≈ +10 (identity rotation, two stacked rings each)
- `Obstacles` — crates, barrels, cans, pallets, stairs, slopes, pillars (each an FBX instance): center lanes kept clear, mirrored stair/slope/platform clusters in the north zone (z < -24), flank cover clusters on the east/west extensions
- `Targets` — target stands + target plates for shooting practice, spread across all zones
- `SpawnPoints` — ten validated markers: six in the original center lanes, four in the new west/east/north perimeter lanes

### Expanding the map
1. Edit the spec lists in `tools/gen_testing_area.py` (`COL_X`, `ROW_Z`, `OBS`, `TARGETS`, `SPAWNS`) and re-run it, then `/usr/bin/godot --headless --import`.
2. Keep center lanes (x -6..6 in the old zone) clear for firing lines; keep new props ≥4m from spawn markers and ≥1 tile from tile seams (a marker on a seam fails the floor raycast).
3. Run `tools/check_spawns.gd` — every marker must report OK (the runtime validator is unforgiving; a failing marker silently shifts joins to other lanes).

FBX kit lives at `assets/KayKit_Prototype_Bits_1.1_FREE/Assets/fbx/`. The old Jeheno map kit (jump pads, conveyor/slippery zones) is available under `addons/JehenoAdvancedFirstPersonController/Map/`.

---

## 7. Known issues & deferred work

- `TODO.md` at the root tracks: health/stamina bar fix, stamina drain for slide/wallrun, unused-file cleanup.
- Restart is an in-room respawn; disconnecting Photon is reserved for leaving/shutting down.
- Inactive players are removed immediately. Reconnect grace requires stable account identity and room-level reservation state. On a TTL reap Photon can zero the departed player's replica owner id before `player_left` arrives, so cleanup falls back to `_sweep_departed_replicas()`: any remote replica whose owner is not an active room player is freed.
- Dead state is synchronized to current peers with RPCs and sent to a joining peer after `player_joined`. It is not a custom replicated property because the bundled Fusion preview crashes when the config is extended.
- Enemies are local-only, not networked.
- `CyberMap.scn`, `Prefabs/`, `Meshes/`, `model.obj`, `*.depren` files and the copies in `scenes/player/`, `scenes/main/`, `scripts/entities/enemy/` of old scenes are leftovers of an abandoned cyberpunk map and the old single-player world — candidates for cleanup (careful: `Prefabs/` holds the cyberpunk prefab kit if a themed map is ever revived).
- There is no server-authoritative damage, team, score, or match-state system yet.

## 8. Conventions

- GDScript only (the Fusion addon also ships a C# wrapper, unused by game code).
- snake_case files/functions, PascalCase class names, tabs for indentation.
- Deferred work is marked inline: `# HUD: ...` comments, `# ponytail: ...` for deliberate simplifications (naming the limitation and the upgrade path).
- Debug/one-off scripts live in `tools/`; the two-client netcode check (`tools/rpc_test.tscn`) is the regression check for shot networking.

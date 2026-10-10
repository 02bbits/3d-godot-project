# Multi-Modifier-FPS — Project Documentation

Godot **4.7.2**, GDScript only, Forward+, Jolt Physics, Photon Fusion (shared mode).
No tests, no CI, no build step. Main scene: `res://scenes/worlds/main.tscn`.

This document describes the project as it exists today. It began as a **port of the
sibling `/fps` project ("3D-Rounds")** — networking, movement and the modifier framework
came over first; the lobby flow, match/round system, map rotation, spectator mode and
modular weapon system have since been built here. See §13.

---

## 1. What the project currently is

An online round-based FPS:

- Menu flow: main menu → name → create/join lobby → waiting lobby → match.
- Lobbies: room browser (Waiting rooms only), optional client-side password, 2–4
  players, configurable round count (1–10), published player names.
- One FPS player per client, spawned through the Fusion spawner when the host starts.
- Full movement state machine: walk/run/bunny-hop, slide, dash, wallrun/walljump.
- Modular hitscan weapons: one shared weapon scene + a `WeaponDefinition` resource per
  weapon (meshes, transforms, damage, sounds). Camera-center aim.
- Match system: last player alive wins a match point, first to 2 wins the round,
  eliminated players spectate, first to `rounds_total` rounds wins the game; top-3
  results and an automatic return to the waiting lobby after 5 s.
- Map rotation: five maps, swapped with a fade every round win.
- Health/stamina bars with a delayed white catch-up bar; scoreboard, match banner,
  results screen, speed-based reticle.
- Modifier framework (definitions, manager, caps) — **not reachable in game**: nothing
  calls `ModifierManager.set_build()`. `match_manager.round_completed` is the future
  draft hook.

---

## 2. Scene graph

### `scenes/worlds/main.tscn` (root `world`, `scripts/worlds/world.gd`)

```
world (Node3D)
├── Sun (DirectionalLight3D)
├── WorldEnvironment
├── MapRoot (Node3D)              the active map; swapped at runtime
│   └── TestingArea               testing_area.tscn
├── PlayerSpawner                 FusionSpawner (spawn_path ".", player.tscn)
├── MatchManager                  match_manager.gd
└── MenuLayer (CanvasLayer 10)    above the player HUD (CanvasLayer 1)
	└── ConnectionMenu            connection_menu.tscn + connection_ui.gd
```

`world.gd` also creates a fade `CanvasLayer` (layer 100) at runtime for map swaps.

### `scenes/player/player.tscn` (spawnable; `player.gd` is the leaf script)

Groups `player`, `PlayerCharacter`. Root `collision_layer = 3` (map + players).

```
PlayerCharacter (CharacterBody3D)
├── StateMachine            initial_state = IdleState
│   └── Idle/Walk/Run/Jump/Inair/Crouch/Slide/Dash/Wallrun (one script each)
├── Health                  net_health is the single source of truth
├── FusionSharedReplicator  owner_mode = PlayerAttached; 17 replicated properties (§5)
├── ModifierManager
├── CameraHolder            camera_script.gd (yaw, tilt, FOV, zoom)
│   └── Camera (unique %)   cull_mask 1, FOV 90; the weapon is instanced here at runtime
│       ├── HeadLookTarget
│       └── CameraBasedRaycasts (LeftWallCheck, RightWallCheck)
├── Hitbox (capsule)
├── VisualRoot
│   ├── ScalingRoot         character model + rig
│   └── HandAttachement     the world weapon model is reparented here
├── Raycasts                Ceiling/Floor/WallrunFloor/SlideFloor checks
├── Sounds                  JumpSound, LandSound
├── AnimationTree/AnimationPlayer
└── HUD (CanvasLayer)
	├── ViewModel           SubViewportContainer > transparent SubViewport (layer-4 camera)
	├── Reticle             reticle.gd: dot + 4 Line2D spread by speed
	├── Healthbar/Staminabar
	├── DeathScreen         spectator overlay (ELIMINATED + target + hint)
	├── SpeedLinesContainer
	├── Scoreboard          RoundLabel + ScoreGrid
	├── ResultsPanel        GAME OVER + top-3 + "Returning to the lobby..."
	└── MatchBanner         transient match/round winner banner
```

### `scenes/weapons/weapon.tscn` (shared by every weapon)

```
Weapon (Node3D, scripts/weapons/weapon.gd)
├── ViewModel (Node3D)      definition.viewmodel_scene instanced here; render layer 4
├── WorldModel (Node3D)     definition.world_model_scene; reparented to the hand
├── Muzzle (Marker3D)       definition.muzzle_transform; tracer origin
├── ShootSound/ReloadSound  AudioStreamPlayer3D (unit_size 30)
└── HitConfirm (CanvasLayer 20)  hit marker, kill banner, kill sound
```

---

## 3. Lobby, connection and spawn flow

`scripts/ui/connection_ui.gd` + `scripts/worlds/world.gd` + `scripts/worlds/match_manager.gd`.

1. **Menu pages** (ConnectionMenu, `MenuLayer` CanvasLayer 10): MainMenu → NameScreen →
   PlayChoice → CreateLobby / BrowseLobbies / PasswordPrompt → Lobby. The menu root
   hides entirely during gameplay; ESC opens InGameMenu (Resume, Leave Lobby).
2. **Name**: saved to `user://user_config.cfg` and used as the **Photon user id**
   (`Fusion.connect_to_photon(nickname, Fusion.get_default_region())`). Changing the
   name while connected disconnects and reconnects (`_connected_name` tracks the
   identity; `_reconnecting` suppresses the disconnect reload).
3. **Create lobby**: room name, optional password, player count 2–4, rounds 1–10.
   Custom properties `phase="waiting"`, `passworded`, `password`, `rounds`; only
   `phase`/`passworded` are lobby properties (the password never reaches the browser).
4. **Join lobby**: the browser lists rooms with `phase=="waiting"` that are open and
   not full. Passworded rooms prompt; the password is checked **after joining** and a
   mismatch leaves and returns to the prompt with "Wrong password" (client-side gate).
5. **Names**: on `room_joined` each client publishes `name_<player_id>` as a room
   property; the lobby roster polls it every second (fallback: Photon player name, then
   "Player N").
6. **Start** (host, requires ≥2 players): writes `phase="playing"`, `match_phase="fight"`,
   `round=1`, then closes/unlists the room.
7. **Spawn**: `match_manager` emits `game_started` when it sees `phase=="playing"`.
   `world.gd::_start_game` spawns the local player through the `FusionSpawner`; the
   master calls `Fusion.register_current_scene()`. `_spawn_local_player` immediately
   calls `player.claim_local_role()` — the node returned by the spawner is this client's
   own copy, so a client can't get stuck as a remote copy waiting on authority.
8. **Respawn**: `match_manager.respawn_requested` → `world.respawn_player` hands the
   player a unique `spawn_point` marker (sorted player numbers index the sorted marker
   list, so two players can't share one) and calls `player.reset_for_respawn()`.
9. **Return to lobby**: after the game-over results (5 s), the host resets the room to
   `phase="waiting"`, clears match/score state, reopens and re-lists the room; every
   client despawns its player and the menu returns to the Lobby page.
10. **Disconnect**: `STATUS_DISCONNECTED` reloads the scene unless it was an expected
	leave (`_room_leave_handled`) or a deliberate reconnect (`_reconnecting`).

---

## 4. Match and round system (`scripts/worlds/match_manager.gd`)

Master-authoritative; every client polls the room's custom properties every 0.25 s
(Fusion exposes no property-changed signal).

- **Match** = one elimination bout. The last player alive scores 1 match point
  (`round_scores`). A draw (nobody alive) scores nothing.
- **Round** = first to 2 match wins; the winner's `rounds_won` is persisted and
  `round_scores` reset. `round_completed` fires on the host (future modifier draft).
- **Game over** after `rounds_total` rounds: results screen, then `_return_to_lobby`
  after 5 s (`GAME_OVER_SECONDS`).
- **Intermission**: 3 s normally, 5 s after a round win so the map transition fits.
- **`_match_ready`**: the host waits until all expected players have been seen alive
  before evaluating, so a laggy respawn can't hand the match to the first client back.
- **Map rotation**: `map_index` advances on every non-final round win; `map_changed`
  fires on host and clients.
- **Host migration**: the game-over countdown restarts if a new host takes over.

Room properties written: `match_phase` ("fight"/"intermission"/"game_over"/""), `round`,
`map_index`, `last_result`, `result_serial`, `rounds_won_<id>`, `round_score_<id>`.
Flat per-player int properties are deliberate — Photon handles them reliably and writing
every player keeps keys from going stale. The host also bumps `game_serial` on every
Start; a client detects the return to lobby from `phase != "playing"` (so a missed
`game_over` window can't strand it) and, if it stalled through the whole waiting window,
from a changed `game_serial` — either way it despawns its previous player before the
next game.

Signals: `game_started`, `respawn_requested`, `map_changed(index)`,
`returned_to_lobby`, `round_completed(round)`.

---

## 5. Networking model (Fusion, shared mode)

One client is the Photon master; each client owns its own player replica
(`owner_mode = PlayerAttached`). `FusionSpawner` creates the replica on every peer.

### Replicated state (player.tscn replicator config)

- root transform; `view_yaw`/`view_pitch` (interpolated angles); `body_yaw`;
  `net_velocity`; `net_wallrun_side`; `net_crouched`; `net_is_grounded`
- `Health:net_health` (victim owner writes, replicas receive)
- event counters: `net_fire_count`, `net_reload_count`, `net_hit_count`,
  `net_dash_count`, `net_jump_count`, `net_land_count` (owner bumps; setters replay
  visuals/sounds on every peer)
- `net_hit_position` / `net_hit_normal` (last shot impact, for tracers/impacts)
- `net_nickname` (floating label)

### RPCs (`@rpc("any_peer")`, kept on the leaf `player.gd`)

| RPC | Sent | Effect |
|---|---|---|
| `rpc_take_damage(amount, attacker_id)` | shooter → victim owner (`Fusion.rpc_to(TARGET_OWNER, …)`) | victim runs the defensive pipeline + `Health.apply` |
| `died_fx(attacker_id)` | victim → all peers | remote copies go dead, emit `Health.died`, the attacker's client flashes the kill banner |
| `respawn_fx()` | victim → all peers | remote copies restore alive visuals |
| `rpc_draft_pick(index, use_reroll)` | leftover from `/fps` | inert (no `draft_manager` node) |

`Fusion.rpc(Callable(node, "method"), args…)` invokes the method on every peer's replica
of that node (sender included). `Fusion.rpc_to(Fusion.TARGET_OWNER, …)` routes to the
owner client of that replica.

### Damage pipeline (player-vs-player)

1. Weapon (`weapon.gd::_apply_damage`): base `definition.damage` → attacker
   `ModifierManager.on_damage_dealt(ctx)` (can mutate ctx) → clamp relative to base
   (`clampf(amount, damage*0.5, damage*2.5)`) → `rpc_take_damage`.
2. Victim (`player_lifecycle.gd::take_damage`): `ModifierManager.on_damage_taken(ctx)` →
   clamp `clampf(amount, max_health*0.4, max_health*1.5)` → `Health.apply`.
3. `Health.apply` subtracts, emits `damaged`, and on ≤0 emits `died(attacker_id)`.

Note the asymmetric clamp: outgoing damage is relative to the weapon's base damage,
incoming relative to **max_health** — at 100 HP every hit lands in [40, 150].

### Death, spectator and respawn

- Local `_die`: `dead = true`, hides the weapon, disables hitbox/physics/state
  machine/camera/weapon, shows the spectator overlay, broadcasts `died_fx`.
- The overlay holds the screen dark for 1 s, then fades the dim out smoothly while the
  centered "ELIMINATED" block fades away and the spectating line + hint fade in at the
  top center (see §9).
- There is **no auto-respawn**: eliminated players spectate until the match ends.
- `world.gd` runs the spectator camera: while the local player is dead, a runtime
  `Camera3D` follows a living player in third person; the local player's movement
  bindings cycle targets (A/D by default, arrows included; targets are stored as
  instance IDs so a freed replica can't crash the list).
- `match_manager` respawns everyone between matches (`respawn_fx` syncs remote copies).

### Remote copy behavior (`_disable_remote_copy`)

Physics/state machine/camera/weapon/input off, HUD hidden, `cam.current = false`,
`physics_interpolation_mode = OFF` (so Godot's interpolation doesn't fight Fusion's root
smoothing), model visible to others. `_enable_local_copy` restores interpolation when a
copy flips remote→local.

---

## 6. Player controller

The player script is split by responsibility into an inheritance chain — each layer only
calls downward, never upward: `player_base.gd` (exports, shared state, node refs) →
`player_movement.gd` (keybinds, timers, stamina, gravity, tweens) → `player_network.gd`
(replicated counters, view/animation sync, ownership role) → `player_lifecycle.gd`
(damage, death, respawn) → `player.gd` (leaf: `PlayerCharacter`, `_ready`/`_process`/
`_physics_process`, `@rpc` entry points, weapon setup).

### State machine (`scripts/player/state_machine/`)

- `State` (`state_script.gd`): `enter/exit/update/physics_update` hooks + `transitioned`
  signal; each subclass sets `state_name`.
- `state_machine_script.gd`: collects `State` children into `states` keyed by
  **lowercased node name**, waits for `play_char.ready` (guarded with `is_node_ready()`
  so an already-ready parent can't hang the await), enters `initial_state`, and switches
  state when a `transitioned(self, "XState")` arrives from the current state. It emits
  `change_fov`, wired in `player.tscn` to `CameraHolder.change_fov`.
- States: Idle, Walk, Run, Jump, Inair, Crouch, Slide, Dash, Wallrun.
- Transitions live in each state's `input_management()`/`applies()`; jump buffering and
  coyote time are tracked on the player. `player.gd::_process` ticks
  wallrun/slide/dash/jump cooldowns and stamina; `_physics_process` calls
  `move_and_slide()`.

### Movement values (`player_base.gd` exports)

| | speed | accel / decel | notes |
|---|---|---|---|
| Walk | 5.1 | 8 / 13 | backward ×0.75 |
| Run | 7.65 | 7 / 13 | backward ×0.7; stamina drain |
| Crouch | 2.0 | 6 / 8 | backward ×0.7 |
| Slide | 8.2 | 23 / – | 1.2 s, loses 4 m/s per s |
| Dash | 34 | – | 0.1 s, 0.8 s cooldown, 3 s recharge |
| Wallrun | 9.65 | 2.3 / 7 | 3.5 s, fall-gravity multiplier exported |

Jump: `jump_height` 2.7 (user-tuned), rise 0.3 s, fall 0.25 s; 1 air jump; walljump push
11.9 + y 7.65. Max accumulated speed 25.5 (bunny-hop increments 3.0/tick). Stamina:
100 max, drain 15/s while Run/Jump/Wallrun, regen 15/s after 0.7 s; double jump 20,
dash 10. **Jumps are blocked at 0 stamina** (`jump_state_script.gd::jump` early-returns).

### Camera

Crouch and slide tween `CameraHolder.position.y` down and restore it on exit
(`camera_height_for(hitbox_height)`); the base height is captured in `player.gd::_ready`
(`cam_base_height`). The camera holder also handles FOV changes, zoom and tilt.

### Collision layers / masks

| Layer | Used by |
|---|---|
| 1 | map geometry, targets, world weapon models |
| 2 | player body + hitbox (the local model is on layer 2, invisible to its own camera) |
| 3 | raycast-only helpers (`CameraBasedRaycasts`) |

Weapon aim uses mask 7 (map + players + helpers); wall checks mask 5; floor/ceiling
checks mask 1. Camera `cull_mask = 1`; the viewmodel renders on render layer 4 and is
only seen by the viewmodel camera.

---

## 7. Weapons (modular)

- `scenes/weapons/weapon.tscn` — the shared weapon scene: controller, `ViewModel` and
  `WorldModel` mounts, `Muzzle`, shoot/reload sounds, `HitConfirm`.
- `scripts/weapons/weapon.gd` — all shared logic: input, fire cooldown, ammo/reload,
  modifier stats, damage routing, tracer/feedback, recoil, visibility.
- `scripts/weapons/weapon_definition.gd` (`WeaponDefinition`) — per-weapon resource:
  `display_name`, `damage`, `mag_size`, `reserve_max`, `fire_interval`, `reload_time`,
  `range`, `viewmodel_scene`/`viewmodel_transform`, `world_model_scene`/
  `world_model_transform`, `muzzle_transform`, `shoot_sounds`, `reload_sounds`.
- `resources/weapons/pistol.tres` — the equipped weapon. The player exports
  `weapon_definition`; `player.gd::_setup_weapon()` instantiates `weapon.tscn` under the
  camera and calls `weapon.setup(self, definition)`.

**Adding a weapon** = a new `.tres` (plus model scenes) and changing the player's single
`weapon_definition` export. No shared script or player-scene edits.

### Firing (traditional FPS aim)

`weapon.gd::_shoot`:
1. Camera-center ray (`camera.global_position` along `-camera.basis.z`, mask 7, shooter
   excluded) → the aim point under the reticle.
2. Muzzle ray to that aim point → keeps cover in front of the gun honest.
3. Damage, hit normal and the tracer use the resulting hit (muzzle hit if blocked, else
   the camera hit).

Replication: the owner bumps `net_fire_count` / `net_reload_count`; every peer replays
`on_fire_event` (tracer, model muzzle flashes, shoot sound) and `reload_visual` (sound +
character reload animation). Damage goes through the pipeline in §5.

Feedback: floating damage number + hit marker on the shooter; the attacker's client
flashes `ELIMINATED` (`hit_confirm.gd`). The tracer (`scenes/entities/bullet.tscn`) is
cosmetic with its mask forced to 1 so it never touches players.

Targets (`target.gd`): StaticBody3D, 100 HP, 2 s respawn, group `enemy`, master-owned
replicator; `rpc_take_damage` + the replicated `net_health` drive die/revive visuals on
every client.

---

## 8. Modifier system

```
modifier.gd            Resource base: id, display_name, description, tags, rarity,
					   stackable/max_stacks, exclusive_group, stat_adds, stat_mults
					   hooks: on_damage_dealt / on_damage_taken / on_kill / on_round_start
modifier_db.gd         static registry: id -> def (loads .tres), get_def(), all_ids()
defs/*.tres            10 stat-only modifiers
modifier_manager.gd    per-player node: set_build/clear, stat cache, caps, hook dispatch
```

Registered modifiers (`modifier_db.gd`):

| id | effect | notes |
|---|---|---|
| `swift_boots` | move_speed ×1.15 | stackable ×2 |
| `feather` | gravity ×0.8 | exclusive group `gravity` |
| `dash_surge` | dash_cooldown ×0.65 | |
| `hair_trigger` | fire_rate ×1.2 | stackable ×2 |
| `extended_mag` | mag_size ×1.4 | stackable ×2 |
| `fast_hands` | reload_time ×0.7 | |
| `heavy_rounds` | damage ×1.15, fire_rate ×0.95 | |
| `plating` | max_health +25 | stackable ×2, heals on apply |
| `glass_cannon` | damage ×1.5, max_health ×0.7 | chaos |
| `low_gravity` | gravity ×0.6 | chaos, exclusive `gravity` |

Behavioral modifiers (`impl/*.gd` in `/fps`) were **not ported** — `modifier_db.gd` has a
`ponytail:` note where they would be re-added.

### How stats resolve

- `ModifierManager.get_stat(stat, base)` = `(base + Σadds) × Πmults`, clamped per stat by
  `STAT_CAPS` (`damage` [0.5, 2.5], `damage_taken` [0.4, 1.5], `move_speed` [0.5, 1.6],
  `fire_rate` [0.5, 2.0], `reload_time` [0.3, 2.0], `mag_size` [0.5, 2.5], `max_health`
  [0.4, 1.6], `gravity` [0.2, 1.2], `dash_cooldown` [0.3, 2.0]).
- `set_build(ids)` duplicates each def (behavioral mods carry per-instance state),
  enforces exclusive groups (last pick wins), rebuilds the add/mult cache, then
  `_apply_player_stats()`.
- `_apply_player_stats()` runs **only on the local copy** (`is_remote` early-return) and
  snapshots controller bases once (`_bases`). It writes walk/run/crouch/wallrun/slide/
  dash speeds, jump/fall gravity, `time_bef_reload_dash_ref`, and max health (heals the
  difference when it grows).
- Consumed by gameplay: `fire_rate`, `reload_time`, `mag_size`, `damage` in `weapon.gd`;
  `damage_taken` in `player.take_damage`; the rest in `_apply_player_stats`.

**No code path grants a modifier today.** The only way to exercise the system is to call
`set_build(["swift_boots", …])` from a debug script/tool. The `round_completed` signal
on `match_manager` is the intended future draft hook.

---

## 9. UI

| Piece | File | Notes |
|---|---|---|
| Menu flow | `scripts/ui/connection_ui.gd` + `scenes/ui/connection_menu.tscn` | main menu, name, create/join, browser, password, lobby, in-game menu; lives in `MenuLayer` (CanvasLayer 10); Lilita One font |
| Lobby roster | same | published names, host, count; host-only Start (disabled with <2 players) |
| HUD | `scripts/player/hud/hud_script.gd` | keeps bar max in sync, rebuilds the scoreboard, hides the gameplay HUD while a popup is up |
| Health bar | `scenes/ui/healthbar/*` | red bar drops immediately; the white bar holds the gap and slides down after a 0.4 s delay (0.35 s slide) |
| Stamina bar | `scenes/ui/staminabar/*` | same delayed style; binds to the HUD's own `play_char` (not a group lookup) |
| Reticle | `scenes/player/reticle.gd` | center dot + 4 Line2D spread by planar speed (`get_real_velocity()`) |
| Spectator overlay | `scripts/player/death_screen.gd` | 1 s dark hold, then dim fades out; "ELIMINATED" drops, spectated name + A/D hint move to the top center |
| Scoreboard | player HUD | `Player / Rounds / Match` + `Round X / N` |
| Results | player HUD | GAME OVER + top-3 by rounds won; auto-returns to the lobby after 5 s |
| Match banner | player HUD | "X wins the match!/round N!" or a draw |
| Hit confirm | `scripts/player/hit_confirm.gd` | hit marker, kill banner, kill sound |
| Speed lines | `scripts/player/shader/speed_lines_shader.gdshader` | shown by DashState |

The UI is a view only: it reads player/network/match state and never owns gameplay state.

---

## 10. Maps and assets

Five maps, rotated every round win:

- `scenes/worlds/testing_area.tscn` — the original KayKit arena (GridMap tiles +
  obstacles), 10 `spawn_point` markers.
- `scenes/worlds/arena_pillars|lanes|cross|ring.tscn` — baked GridMap arenas (60 m,
  4 m floor tiles item 18, 4×4×4 wall blocks item 12, 10 spawn markers each). The cell
  data is serialized in the scene files (visible in the editor). They were generated
  once with Godot's serializer; the `spawn_point` groups are patched into the saved text
  because `PackedScene.pack()` drops programmatically added groups.

`world.gd` holds `MAP_PATHS`; `MapRoot` holds the active map. On `map_changed` the world
waits 3 s (so the round-win banner plays), fades out (0.35 s, CanvasLayer 100), swaps the
`MapRoot` child, waits 1 s (`MAP_SETTLE_SECONDS`) for the new map to finish building,
re-collects spawn points, and fades back in. Respawns that arrive mid-swap wait for it
to finish. Map geometry is local-only; every client swaps on the shared `map_index`, so
no networked scene objects are needed.

Other assets: `assets/KayKit_Prototype/` (meshlib + GLB), `assets/audio/` (Kenney CC0),
`assets/photon/...` (animations, fonts), `assets/hud/crosshair.png` (now unused — the
reticle replaced it), `assets/clouds/*.tres` (unused). `addons/fusion/` is the Photon
Fusion GDExtension; its `cs/` C# sources are unused. Every `.gd`/`.tscn` has a committed
`.uid` sidecar — keep them.

---

## 11. Running and verifying

```bash
godot --path .                            # run the game (needs a display)
godot --headless --path . --quit          # import + parse every script; prints errors/warnings
godot --headless --path . --quit-after 3  # also instantiates the main scene for a few frames
```

Expected noise on every run: warnings that `play_char_*` actions were added to the
runtime InputMap (see §12). `Fusion` is a GDExtension singleton; without a display or
network only the parse/import check is meaningful. There is no test suite, no linter and
no export preset committed. Verification so far has been headless smoke scripts plus
two-client manual runs.

---

## 12. Quirks and landmines

- **Input actions are runtime-registered.** `project.godot` has no `[input]` section;
  `player_movement.gd` and `camera_script.gd` add `play_char_*` actions with default keys
  on `_ready` if missing (and warn). They do not persist.
- **Modifiers are inert.** Nothing calls `set_build()`; `match_manager.round_completed`
  is the future draft hook. `rpc_draft_pick` and the `input_mode` group lookups remain
  inert leftovers from `/fps`.
- **Room properties are polled.** Fusion has no property-changed signal; the match
  manager polls every 0.25 s. Flat per-player properties are used deliberately — nested
  dictionaries were avoided for Photon reliability.
- **Passwords are a client-side gate.** The password lives in the room's custom
  properties (not the lobby list) and is checked after joining; a modified client could
  bypass it. Server enforcement needs Photon plugins/auth.
- **Damage-taken clamp uses `max_health` as scale** (at 100 HP every hit is in
  [40, 150]); retune when balancing TTK. The pistol's base damage is 30.
- **`reserve_max = 999`** in `pistol.tres` is "infinite ammo for debugging"; it is still
  consumed by reloads.
- **Unvalidated spawns.** `world.gd::respawn_player` deterministically assigns a distinct
  `spawn_point` marker per player with a fixed lift; there is no floor/capsule/ceiling
  check.
- **Map swap timing** assumes the round intermission (5 s) outlasts the 3 s banner delay,
  the fades and the 1 s map settle; keep `MAP_SWAP_DELAY`, `MAP_SETTLE_SECONDS` and
  `ROUND_INTERMISSION_SECONDS` in sync.
- **Physics tuning is baked in**: gravity 24 (not 9.8), Jolt, interpolation on, jitter
  fix off. Remote copies turn interpolation off intentionally.
- **D3D12 on Windows** is forced in `project.godot`; Forward+ everywhere.
- **The viewmodel is local-only.** It renders in a transparent SubViewport that shares
  the game's `World3D` (so it stays lit), on render layer 4 with a fixed FOV; the
  gameplay camera never sees it and it does not depth-test against walls (it draws over
  them by design).
- **Health/stamina bars bind to the HUD's `play_char`**, never a group lookup — remote
  copies are in the `player` group too, and a group lookup would attach to the wrong
  copy on clients.

---

## 13. Lineage and what is still missing vs `/fps`

Ported from `/fps` ("3D-Rounds"): player controller + state machine, health, targets,
tracer/hit confirm, modifier core, Fusion spawn/replication/RPC backbone, map.

Built in this project: lobby flow (menu, browser, passwords, rounds, published names),
match/round system with scoring + results + return to lobby, spectator mode, map
rotation with fade, modular weapon system with camera-center aim, HUD scoreboard/banner,
delayed health/stamina bars, speed reticle.

Still missing (present in `/fps` or future work):

- Draft manager/UI (offers, picks, rerolls, builds) and `set_build` wiring — hook:
  `match_manager.round_completed`.
- Behavioral modifier implementations (`vampire_bullets`, `berserker`, `sniper_focus`,
  `second_wind`).
- Spawn validation (floor raycast, capsule clearance, deterministic slots) and
  respawn-at-farthest-from-enemy selection.
- Input mode controller (mouse/input gating per UI mode), metrics logging, two-client
  integration tests.
- Weapon switching/inventory — the current design supports one equipped weapon via the
  player's `weapon_definition` export.

## Animation

Where clips live: the AnimationPlayer in `player.tscn` owns GLB libraries (General,
Movement, MovementAdvanced, CombatRanged, plus inline AimingFull). You reference clips as
"Library/Clip" (e.g. `Movement/Walking_A`). The AnimationTree decides when they play
through its graphs:

- Root SM: Spawn → Alive → Death
- Alive/Movement SM: Locomotion (BlendSpace2D), Crouch, Jump, Airborne, Dash, Land
- Alive/Weapon SM: Idle, Fire, Reload
- HitA/HitB: one-shot nodes

Pick the recipe by intent:

1. **One-shot event** (emote, reaction) — add an `AnimationNodeAnimation` +
   `AnimationNodeOneShot` in the Alive blend tree wired like HitA/HitB, then trigger:
   `animation_tree.set("parameters/Alive/MyShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)`
2. **Networked one-shot** — use the counter pattern already in `player_network.gd`:
   ```gdscript
   var net_emote_count: int = 0:
	   set(value):
		   var previous := net_emote_count
		   net_emote_count = value
		   if is_node_ready() and value > previous:
			   animation_tree.set("parameters/Alive/Emote/request",
				   AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
   ```
   Increment it where the event happens (`net_emote_count += 1`, like
   `weapon.gd::_shoot` does with `net_fire_count`); Fusion replicates it and every peer
   replays the animation.
3. **Movement state** — add a state + transitions in the Movement SM. Transitions can
   advance automatically via `advance_expression` (see `net_crouched` in `player.tscn`),
   or drive from code with `movement_state_machine.travel("MyState")` (like Dash in
   `player_network.gd`). Reset it in `reset_for_respawn` if needed.
4. **Locomotion blend** — add an `AnimationNodeAnimation` and a `blend_point_N` to the
   BlendSpace2D (see `Walking_A` in `player.tscn`). `_animate_locomotion` feeds
   `parameters/Alive/Movement/Locomotion/blend_position` from horizontal velocity /
   `run_speed`.

Rules: keep `@rpc` entry points on the leaf `player.gd`, put setters/methods in the layer
that owns them, and author graph edits in the editor's AnimationTree panel — hand-editing
state machines in `.tscn` is how typos happen. New clips must target the same rig
(Rig_Medium: `upperarm.r`, `wrist.r`, etc.) or need a `RetargetModifier3D`. Quick check
after adding: `godot --headless --path . --quit`.

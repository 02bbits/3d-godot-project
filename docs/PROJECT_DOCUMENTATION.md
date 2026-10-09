# Multi-Modifier-FPS — Project Documentation

Godot **4.7.2**, GDScript only, Forward+, Jolt Physics, Photon Fusion (shared mode).
No tests, no CI, no build step. Main scene: `res://scenes/worlds/main.tscn`.

This document describes the project as it exists today. It is a **port of the sibling
`/fps` project ("3D-Rounds")**: networking, movement, and the modifier framework came
over; the match/round/draft systems did not. See §12.

---

## 1. What the project currently is

An online movement/shooting sandbox:

- Connection menu (nickname + room name, join-or-create, up to 8 players).
- One FPS player per client, spawned through the Fusion spawner on room join.
- Full movement state machine: walk/run/bunny-hop, slide, dash, wallrun/walljump.
- Hitscan gun with cosmetic tracers, hit marker, damage numbers, kill banner.
- Shootable targets shared across clients (master-authoritative).
- Health/stamina bars, death screen, automatic 3 s respawn.
- Modifier framework (definitions, manager, caps) — **not reachable in game**: nothing
  calls `ModifierManager.set_build()`. No draft UI, no pickups, no rounds/match flow.

---

## 2. Scene graph

### `scenes/worlds/main.tscn` (root node `world`, `scripts/worlds/world.gd`)

```
world (Node3D)
├── Sun (DirectionalLight3D)
├── WorldEnvironment
├── TestingArea            testing_area.tscn — map, targets, 10 spawn markers
├── PlayerSpawner          FusionSpawner  (spawn_path ".", spawnable_scenes = player.tscn)
└── ConnectionMenu         connection_ui.gd (Control, mouse-driven)
```

### `scenes/player/player.tscn` (spawnable, `scripts/player/player.gd` — leaf of the player script chain, see §5)

Groups: `player`, `PlayerCharacter`. `collision_layer = 2`.

```
PlayerCharacter (CharacterBody3D)
├── StateMachine            state_machine_script.gd, initial_state = IdleState
│   └── IdleState · CrouchState · WalkState · RunState · JumpState ·
│       InairState · SlideState · DashState · WallrunState   (child nodes, one script each)
├── Health                  health.gd — net_health is the single source of truth
├── FusionReplicator        FusionSharedReplicator, owner_mode = PlayerAttached
│                           config: Health:net_health, view_yaw, view_pitch + root transform
├── ModifierManager         modifier_manager.gd
├── RespawnTimer            one-shot, 3 s
├── CameraHolder            camera_script.gd (yaw, tilt, FOV, zoom)
│   └── Camera (unique %)   cull_mask = 1, FOV 90
│       ├── Weapon          gun.tscn
│       │   └── HitConfirm  CanvasLayer 20 (hit marker, kill banner, kill sound)
│       └── CameraBasedRaycasts (LeftWallCheck, RightWallCheck)
├── Hitbox (capsule)        collision layer 2
├── Model (capsule)         layers = 2 (hidden from own camera)
├── Raycasts                CeilingCheck, FloorCheck, WallrunFloorCheck, SlideFloorCheck
└── HUD (CanvasLayer)       healthbar, staminabar, DeathScreen, SpeedLines, Crosshair
```

---

## 3. Connection and spawn flow

All in `scripts/ui/connection_ui.gd` + `scripts/worlds/world.gd`.

1. **Connect** (`_connect`): builds `user_id = "user_" + randi()` (the nickname field
   is saved to `user://user_config.cfg` but is *not* used as the network identity),
   calls `Fusion.connect_to_photon(user_id)` with **no region argument**, then polls up
   to 15 s for the connection.
2. **Join room**: `Fusion.join_or_create_room(room_name, options)` — max 8 players,
   custom property `game_mode = "fps"`, lobby property `["game_mode"]`. There is no
   password, room browser, or version check.
3. **ESC** toggles the menu; it can only be hidden once `world.local_player != null`.
   Mouse capture follows menu visibility (`_show_menu`).
4. **`Fusion.room_joined`** (`world.gd::_on_room_joined`):
   - every client spawns its own player: `player_spawner.spawn()` (no scene argument —
	 uses the first spawnable scene);
   - the master client calls `Fusion.register_current_scene()` so networked scene
	 objects (the targets) are shared.
5. **Role resolution**: `player.gd::_ready` → `player_network.gd::setup_network_control()` reads
   `FusionSharedReplicator.has_authority()` and applies one role (see §4). It emits
   `network_ready` / sets `network_role_ready`. `world.gd` waits for that before
   picking a **random** marker from group `spawn_point` and calling
   `reset_for_respawn()`.
6. **Disconnect**: `_on_connection_status_changed(status == STATUS_DISCONNECTED)` calls
   `get_tree().reload_current_scene()`.

---

## 4. Networking model (Fusion, shared mode)

One client is the Photon master client; each client owns its own player replica
(`owner_mode = PlayerAttached`). `FusionSpawner` creates the replica on every peer.

### Replicated state

| State | Where set | How |
|---|---|---|
| Player transform / velocity | owner | replicator root replication |
| `view_yaw` / `view_pitch` | owner writes in `_process`; remote reads and applies to camera | replicator custom properties (`player.tscn` config) |
| Health | victim owner writes `net_health`; remote copies receive it | `Health:net_health` property |
| Target health | master writes `Target:net_health` | target replicator (`owner_mode = MasterClient`) |

### RPCs (`@rpc("any_peer")`, kept on the leaf script `player.gd`)

| RPC | Sent | Effect |
|---|---|---|
| `rpc_take_damage(amount, attacker_id)` | shooter → victim owner via `Fusion.rpc_to(TARGET_OWNER, …)` | victim runs defensive pipeline + `Health.apply` |
| `shot_fx(from, dir)` | shooter → all replicas | remote copies replay shot visuals (`gun.fire_visual`) |
| `reload_fx()` | shooter → all replicas | remote copies replay reload animation/sound |
| `died_fx(attacker_id)` | victim → all peers | remote copies hide dead model, emit `Health.died`, flash kill banner on the attacker's client |
| `respawn_fx()` | victim → all peers | remote copies restore visuals |
| `rpc_draft_pick(index, use_reroll)` | leftover from `/fps`; looks for a `draft_manager` group node that does not exist here | inert |

`Fusion.rpc(Callable(node, "method"), args…)` invokes the method on **every peer's**
replica of that node (sender included). `Fusion.rpc_to(Fusion.TARGET_OWNER, …)` routes
to the owner client of that replica.

### Damage pipeline (player-vs-player)

1. Shooter (`gun.gd::_apply_damage`): base `damage` (34) → attacker `ModifierManager`
   hooks (`on_damage_dealt`, can mutate ctx) → clamp relative to base:
   `clampf(amount, damage*0.5, damage*2.5)` → `rpc_take_damage`.
2. Victim (`player_lifecycle.gd::take_damage`): `ModifierManager.on_damage_taken(ctx)` → clamp
   `clampf(amount, max_health*0.4, max_health*1.5)` → `Health.apply`.
3. `Health.apply` subtracts, emits `damaged`, and on ≤ 0 emits `died(attacker_id)`.

Note the asymmetric clamp: outgoing damage is clamped relative to weapon base damage,
incoming damage relative to **max_health**. At 100 HP that means every hit lands in
[40, 150] — a base 34 damage hit becomes 40.

### Death and respawn

- Local `_die`: `dead = true`, hide model/weapon, disable hitbox and all processing,
  show DeathScreen, start `RespawnTimer` (3 s), broadcast `died_fx`.
- `request_restart` (timer or Restart button) → `world.respawn_player` picks a random
  `spawn_point` marker → `player.reset_for_respawn()` restores everything, broadcasts
  `respawn_fx`. Remote copies apply dead/alive visuals through the RPCs; health resyncs
  through `net_health`.

### Remote copy behavior (`_disable_remote_copy`)

Physics/state machine/camera/weapon/input off, HUD hidden, `cam.current = false`,
`physics_interpolation_mode = OFF` (so Godot's interpolation does not fight Fusion's
root smoothing), model moved to render layer 1 and tinted red (visible to others).
`_process` keeps running only to apply replicated `view_yaw`/`view_pitch`.

---

## 5. Player controller

The player script is split by responsibility into an inheritance chain — each layer
only calls downward, never upward: `player_base.gd` (exports, shared state, node refs)
→ `player_movement.gd` (keybinds, timers, stamina, gravity, tweens) →
`player_network.gd` (replicated counters, view/animation sync, ownership role) →
`player_lifecycle.gd` (damage, death, respawn) → `player.gd` (leaf: `PlayerCharacter`,
`_ready`/`_process`/`_physics_process`, `@rpc` entry points).

### State machine (`scripts/player/state_machine/`)

- `State` (`state_script.gd`): `enter/exit/update/physics_update` hooks +
  `transitioned` signal; each subclass sets `state_name`.
- `state_machine_script.gd`: collects `State` children into `states` keyed by
  **lowercased node name**, awaits `play_char.ready`, enters `initial_state`, and
  switches state when a `transitioned(self, "XState")` arrives from the current state.
  It emits `change_fov`, wired in `player.tscn` to `CameraHolder.change_fov`.
- States: Idle, Walk, Run, Jump, Inair, Crouch, Slide, Dash, Wallrun.
- Transitions live in each state's `input_management()`/`applies()`; jump buffering and
  coyote time are tracked on the player. `player.gd::_process` ticks
  wallrun/slide/dash/jump cooldowns and stamina (defined in `player_movement.gd`);
  `_physics_process` calls `move_and_slide()`.

### Movement values (`player_base.gd` exports)

| | speed | accel / decel | notes |
|---|---|---|---|
| Walk | 5.1 | 8 / 13 | backward ×0.75 |
| Run | 7.65 | 7 / 13 | backward ×0.7; stamina drain |
| Crouch | 2.0 | 6 / 8 | backward ×0.7 |
| Slide | 8.2 | 23 / – | 1.2 s, loses 4 m/s per s |
| Dash | 34 | – | 0.1 s, 0.8 s cooldown, 3 s recharge |
| Wallrun | 9.65 | 2.3 / 7 | 3.5 s, fall gravity ×0.08 |

Jump: height 1.7, rise 0.3 s, fall 0.25 s (derived `jump_gravity ≈ -37.8`,
`fall_gravity ≈ -54.4`), 1 air jump, walljump push 11.9 + y 7.65. Max accumulated
speed 25.5 (bunny-hop increments 3.0/tick). Stamina: 100 max, drain 15/s while
Run/Jump/Wallrun, regen 15/s after 0.7 s; double jump 20, dash 10.

### Collision layers / masks

| Layer | Used by |
|---|---|
| 1 | map geometry, targets, weapon/gun visuals |
| 2 | player body + hitbox |
| 3 | raycast-only helpers (`CameraBasedRaycasts`) |

`WeaponRaycast` mask 7 (map + players + helper); wall checks mask 5; floor/ceiling
checks default mask 1. Camera `cull_mask = 1`; local model on layer 2 (invisible to
self), remote models switched to layer 1 (visible).

---

## 6. Modifier system

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

Behavioral modifiers (`impl/*.gd` in `/fps`) were **not ported** — `modifier_db.gd` has
a `ponytail:` note where they would be re-added.

### How stats resolve

- `ModifierManager.get_stat(stat, base)` = `(base + Σadds) × Πmults`, clamped per stat
  by `STAT_CAPS` (`damage` [0.5, 2.5], `damage_taken` [0.4, 1.5], `move_speed`
  [0.5, 1.6], `fire_rate` [0.5, 2.0], `reload_time` [0.3, 2.0], `mag_size` [0.5, 2.5],
  `max_health` [0.4, 1.6], `gravity` [0.2, 1.2], `dash_cooldown` [0.3, 2.0]).
- `set_build(ids)` duplicates each def (behavioral mods carry per-instance state),
  enforces exclusive groups (last pick wins), rebuilds the add/mult cache, then
  `_apply_player_stats()`.
- `_apply_player_stats()` runs **only on the local copy** (`is_remote` early-return)
  and snapshots controller bases once (`_bases`). It writes walk/run/crouch/wallrun/
  slide/dash speeds, jump/fall gravity, `time_bef_reload_dash_ref`, and max health
  (heals the difference when it grows).
- Consumed by gameplay: `fire_rate`, `reload_time`, `mag_size` in `gun.gd`;
  `damage` in `gun.gd`; `damage_taken` in `player.take_damage`; the rest in
  `_apply_player_stats`.

**No code path grants a modifier today.** The only way to exercise the system is to
call `set_build(["swift_boots", …])` from a debug script/tool.

---

## 7. Combat and targets

- `gun.gd`: hitscan `WeaponRaycast` (60 m), 34 damage, mag 24, reserve 999
  (`reserve_max` is flagged "INFINITE AMMO FOR DEBUGGING"), 0.15 s interval, 1.2 s
  reload; LMB shoot, R reload (only when mouse is captured and not remote).
- `_shoot` raycasts, applies damage, spawns a **cosmetic** tracer
  (`scenes/entities/bullet.tscn`, 300 m/s, 0.6 s life, mask forced to 1 so it never
  touches players), plays muzzle flash/light/sound, then broadcasts `shot_fx`.
- Feedback: hit marker + floating damage number on the shooter; death is broadcast and
  the attacker's client flashes `ELIMINATED` (`hit_confirm.gd`).
- Targets (`target.gd`): StaticBody3D, 100 HP, 2 s respawn, added to group `enemy`,
  damaged via `rpc_take_damage` on the master (`owner_mode = MasterClient`); the
  replicated `net_health` drives die/revive visuals on every client.

---

## 8. UI

| Piece | File | Notes |
|---|---|---|
| Connection menu | `scripts/ui/connection_ui.gd` + `scenes/ui/connection_menu.tscn` | nickname, room name, connect/disconnect, status, ESC menu |
| HUD | `scripts/player/hud/hud_script.gd` | speed-lines toggle; keeps bar max values in sync |
| Health / stamina bars | `scenes/ui/healthbar|staminabar/*` | ghost "damage" bar with 0.4 s delay; resolve the player via `get_first_node_in_group("player")` |
| Death screen | `scripts/player/death_screen.gd` | Restart button; RespawnTimer also auto-restarts |
| Hit confirm | `scripts/player/hit_confirm.gd` | hit marker fade, kill banner, kill sound |
| Crosshair | `assets/hud/crosshair.png` | plain TextureRect |
| Speed lines | `scripts/player/shader/speed_lines_shader.gdshader` | shown by DashState |

UI is a view only: it reads player/network state and never owns gameplay state.

---

## 9. Map and assets

- `scenes/worlds/testing_area.tscn`: KayKit Prototype kitbash (FBX instances, no
  GridMap/CSG). 120 floor tiles, walls, crates/barrels/pillars/slopes/stairs,
  target stands + `target.tscn` instances, and 10 `Marker3D` spawn points (group
  `spawn_point`, y = 0 in local space). Main scene offsets the whole area by
  `(-0.83, 39.12, -0.32)`.
- `assets/KayKit_Prototype/`, `assets/audio/` (Kenney CC0: shots, impacts, reload),
  `assets/fonts/Ticketing.ttf`, `assets/hud/crosshair.png`.
- `assets/clouds/*.tres` are unused `NoiseTexture2D` resources.
- `addons/fusion/` is the Photon Fusion GDExtension (`Fusion` singleton) plus the
  **unused** C# wrapper sources under `addons/fusion/cs/`; all game code is GDScript
  and the project has no .NET configuration.
- Every `.gd`/`.tscn` has a committed `.uid` sidecar — keep them.

---

## 10. Running and verifying

```bash
godot --path .                          # run the game (needs a display)
godot --headless --path . --quit        # import + parse every script; prints errors/warnings
```

Expected noise on every run: warnings that `play_char_*` actions were added to the
runtime InputMap (see §11). `Fusion` is a GDExtension singleton; without a display or
network, only the parse/import check is meaningful.

There is no test suite, no linter, and no export preset committed.

---

## 11. Quirks and landmines

- **Input actions are runtime-registered.** `project.godot` has no `[input]` section;
  `player_movement.gd` and `camera_script.gd` add `play_char_*` actions with default
  keys on `_ready` if missing (and warn). They do not persist.
- **No region is passed to Photon.** `connection_ui.gd` calls
  `Fusion.connect_to_photon(user_id)`; the sibling `/fps` project found that an empty
  region lets Fusion pick "best" per machine, and clients in different regions cannot
  see each other's rooms ("Game does not exist", code 22). The
  `[fusion] connection/default_region` setting in `project.godot` is not read anywhere
  in this project's code.
- **Nickname is decorative.** `_save_nickname()` writes `user://user_config.cfg`, but
  the Photon user id is `"user_" + randi()`; the nickname is never sent.
- **Modifiers are inert.** Nothing calls `set_build()`; no draft/pickups/rounds.
- **Leftover `/fps` hooks.** `rpc_draft_pick` looks for a `draft_manager` group node and
  the death code looks for an `input_mode` group node; neither exists, so those calls
  are no-ops (mouse stays captured on death; the 3 s timer resurrects anyway).
- **Damage-taken clamp uses `max_health` as scale**, so at 100 HP every hit is clamped
  into [40, 150] — a base 34 hit deals 40. Revisit when tuning TTK.
- **Health bars bind by group lookup** (`get_first_node_in_group("player")`), and every
  replica including remote copies is in group `player` — the bar can attach to a remote
  copy depending on tree order. Radically safer to use the local player, as
  `hud_script.gd` does through its `play_char` export.
- **Random, unvalidated spawns.** `world.gd::respawn_player` picks any `spawn_point`
  marker; there is no floor/capsule/ceiling check (the sibling project had one).
- **`reserve_max = 999`** is marked "INFINITE AMMO FOR DEBUGGING"; it is still consumed
  by reloads.
- **Physics tuning is baked in**: gravity 24 (not 9.8), Jolt, interpolation on, jitter
  fix off. Remote copies turn interpolation off intentionally.
- **D3D12 on Windows** is forced in `project.godot`; Forward+ everywhere.

---

## 12. Lineage and what is still missing vs `/fps`

Ported from `/fps` ("3D-Rounds"): player controller + state machine, gun/tracer/hit
confirm, health, targets, modifier core (`modifier.gd`, `modifier_db.gd`,
`modifier_manager.gd`, `defs/*.tres`), Fusion spawn/replication/RPC backbone, map.

Not ported yet (present in `/fps`):

- Room browser + passworded rooms, 6-player cap, room TTLs, phase metadata.
- Match manager (rounds, countdown, kills/points, auto-restart) and the room
  custom-property sync channel.
- Draft manager/UI (offers, picks, rerolls, builds) and `set_build` wiring.
- Behavioral modifier implementations (`vampire_bullets`, `berserker`,
  `sniper_focus`, `second_wind`).
- Spawn validation (floor raycast, capsule clearance, deterministic slots),
  respawn-at-farthest-from-enemy selection.
- Input mode controller (mouse/input gating per UI mode), match HUD, metrics logging,
  two-client integration tests (`rpc_test`, `match_test`, `mod_smoke`).

When porting the draft/match systems, the existing integration points are:
`ModifierManager.set_build()`, the inert `rpc_draft_pick` on the player leaf, the
`draft_manager` group lookup, and the `input_mode` group lookups in
`player_lifecycle.gd`.

## Animation

Where clips live: the AnimationPlayer (player.tscn:1173) owns GLB libraries (General, Movement, MovementAdvanced, CombatRanged, plus inline AimingFull). You reference clips as "Library/Clip" (e.g. Movement/Walking_A). The AnimationTree decides when they play through its graphs:
- Root SM: Spawn → Alive → Death
- Alive/Movement SM: Locomotion (BlendSpace2D), Crouch, Jump, Airborne, Dash, Land
- Alive/Weapon SM: Idle, Fire, Reload
- HitA/HitB: one-shot nodes
Pick the recipe by intent:
1. One-shot event (emote, reaction) — add an AnimationNodeAnimation + AnimationNodeOneShot in the Alive blend tree wired like HitA/HitB, then trigger:
animation_tree.set("parameters/Alive/MyShot/request",
	AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
2. Networked one-shot — use the counter pattern already in player_network.gd:10:
var net_emote_count: int = 0:
	set(value):
		var previous := net_emote_count
		net_emote_count = value
		if is_node_ready() and value > previous:
			animation_tree.set("parameters/Alive/Emote/request",
				AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
Increment it where the event happens (net_emote_count += 1, like gun.gd:86); Fusion replicates it and every peer replays the animation.
3. Movement state — add a state + transitions in the Movement SM. Transitions can advance automatically via advance_expression (see net_crouched at player.tscn:226), or drive from code with movement_state_machine.travel("MyState") (like Dash at player_network.gd:33). Reset it in reset_for_respawn if needed.
4. Locomotion blend — add an AnimationNodeAnimation and a blend_point_N to the BlendSpace2D (see Walking_A at player.tscn:228). _animate_locomotion feeds parameters/Alive/Movement/Locomotion/blend_position from horizontal velocity / run_speed.
Rules: keep @rpc entry points on the leaf player.gd, put setters/methods in the layer that owns them, and author graph edits in the editor's AnimationTree panel — hand-editing state machines in .tscn is how typos happen. New clips must target the same rig (Rig_Medium: upperarm.r, wrist.r, etc.) or need a RetargetModifier3D. Quick check after adding: godot --headless --path . --quit.

Note:
Bug:
Wrong password -> Main menu
What supposed to be:
Wrong password -> reenter the form
Jump cost no stamina
Crouching no camera change
Cant ESC after winning screen

Fire through wall
- Add health bar delay change
UI: No winning notification for each match
Map: No environement light
Sound: widen radius

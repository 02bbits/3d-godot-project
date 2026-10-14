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
- Match system: last player alive wins a match point, first to N (lobby setting,
  default 2) wins the round,
  eliminated players spectate, first to `rounds_total` rounds wins the game; top-3
  results and an automatic return to the waiting lobby after 5 s.
- Map rotation: five maps; the game opens on the lobby's starting map (or a random
  one) and every round win swaps to a random *different* map behind a wipe.
- Match flow (`scenes/ui/match_flow.tscn`): slow motion from the last elimination until
  the next screen (countdown, the wipe into the draft, the lobby), a
  result card (who won, the score, what's next), a wipe that hides the respawn, then a
  "GET READY" card (round · match · map) with a 3-2-1 countdown and FIGHT!. Players are
  frozen (look only) during the draft and the countdown.
- Waiting room ready-up: every non-host player readies; the host can start once all
  are ready. A status line always says what the room is waiting for.
- Robot colors: each player picks a body color on the name screen; it replicates
  (`net_color`) and recolors only the robot shell (`scripts/player/robot_color.gd`).
- HUD from `docs/Modifier Arena — HUD.pdf`: segmented health with a ghost bar,
  stamina, ammo pips (≤24, ×N groups) with reload ring and dash cooldown, compact
  scoreboard + TAB board (kills, match wins, ping), outlined reticle; results screen. The gun has procedural sway/bob/sprint tilt, spring recoil and a
  reload animation.
- Modifier draft (`docs/Modifier Arena — Modifier System-selection.pdf`): before round 1
  and after every non-final round each player picks 1 of 3 modifier cards (20 s, then
  auto-pick). Four types (Stats, Weapon, Ability, Environment), three rarities, level
  limits; 33 modifiers; HUD tray + TAB list + status chips. Full guide:
  `docs/MODIFIER_GUIDE.md`, idea backlog: `docs/MODIFIER_CONCEPTS.md`.

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
├── DraftScreen (CanvasLayer 5)   ui/mods/draft_screen.tscn: the modifier draft overlay
├── Spectator (Node3D)            worlds/spectator.tscn: third-person rig while eliminated
├── MapCamera (Node3D)            worlds/map_camera.tscn: flyover of the coming map behind the draft
├── MatchFlow (CanvasLayer 8)     ui/match_flow.tscn: wipe, result/countdown cards, slow-mo
└── MenuLayer (CanvasLayer 10)    above the player HUD (CanvasLayer 1)
	└── ConnectionMenu            connection_menu.tscn + connection_ui.gd
```

`world.gd` routes respawns and map swaps through `MatchFlow.cover()` / `reveal()` (the
wipe) and freezes the local player in the `LOCKED_PHASES` ("draft", "countdown").

### `scenes/player/player.tscn` (spawnable; `player.gd` is the leaf script)

Groups `player`, `PlayerCharacter`. Root `collision_layer = 3` (map + players).

```
PlayerCharacter (CharacterBody3D)
├── StateMachine            initial_state = IdleState
│   └── Idle/Walk/Run/Jump/Inair/Crouch/Slide/Dash/Wallrun (one script each)
├── Health                  net_health is the single source of truth
├── FusionSharedReplicator  owner_mode = PlayerAttached; 21 replicated properties (§5)
├── ModifierManager         `player.mods`: build, stats, hooks, statuses (§8)
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
	├── Reticle             hud/reticle.tscn: dot + 4 lines spread by speed
	├── Vitals              hud/vitals.tscn: health (10 HP segments, ghost) + stamina
	├── AmmoPanel           hud/ammo_panel.tscn: pips, reload ring, RELOAD prompt, dash
	├── ModTray             hud/mod_tray.tscn: modifier icons above the vitals + pick toast
	├── StatusChips         hud/status_chips.tscn: active statuses (ZAPPED, LIFTED…) under the reticle
	├── DeathScreen         spectator overlay (ELIMINATED + target + hint)
	├── SpeedLinesContainer
	├── ScoreCard           hud/scoreboard_card.tscn: compact top-right card (top 3 + you)
	├── TabBoard            hud/scoreboard_full.tscn: shown while TAB is held, with the
	│                       modifier list (hud/mod_list.tscn) beside the board
	├── ResultsPanel        GAME OVER + top-3 + "Returning to the lobby..."
```

### `scenes/weapons/weapon.tscn` (shared by every weapon)

```
Weapon (Node3D, scripts/weapons/weapon.gd)
├── ViewModel (Node3D)      definition.viewmodel_scene; render layer 4; reparented (with
│                           Muzzle) into the motion pivot (viewmodel_motion.gd) under
│                           the viewmodel camera
├── WorldModel (Node3D)     definition.world_model_scene; reparented to the hand
├── Muzzle (Marker3D)       definition.muzzle_transform; local tracers start at its
│                           projection into the gameplay camera, remote ones at the
│                           world model's MuzzleFlash
├── ShootSound/ReloadSound  AudioStreamPlayer3D (unit_size 30)
└── HitConfirm (CanvasLayer 20)  hit marker, kill banner, kill sound
```

---

## 3. Lobby, connection and spawn flow

`scripts/ui/connection_ui.gd` (flow + joining) with per-page scripts —
`create_lobby_form.gd`, `browse_page.gd`, `lobby_page.gd`, `settings_menu.gd`,
`robot_color_picker.gd` — plus `scripts/worlds/world.gd` + `scripts/worlds/match_manager.gd`.
Shared menu pieces are scenes in `scenes/ui/`: `stepper.tscn` (the `[-] value [+]`
control), `robot_icon.tscn` (mascot; bob/blink, selection ring, palette badge),
`card_art_create.tscn` / `card_art_join.tscn` (play-choice card art, looped by an
AnimationPlayer), `room_row.tscn`, `player_chip.tscn`, `empty_slot.tscn`. Plus
`menu_fx.gd` (page entrances, button hover/press, main-menu intro) and the animated
blueprint backdrop `scripts/ui/shader/blueprint_bg.gdshader`.

**UI is built from nodes, not `_draw()`.** Layout and look live in `.tscn` scenes and
theme type variations (`resources/ui/menu_theme.tres` for menus,
`resources/ui/hud_theme.tres` for the HUD); scripts only set values, visibility and
variations. Repeated items (pips, health ticks, score rows, dots/diamonds) are a
template child duplicated by `NodeUtil.fit_children()` (`scripts/ui/node_util.gd`).
Icons that need curves are SVGs in `assets/ui/` (HUD icons import as `DPITexture`, so
they stay sharp at any UI scale). Containers reset a child's rotation and scale, so a
rotated piece (score diamonds) sits inside an unrotated holder.

1. **Menu pages** (ConnectionMenu, `MenuLayer` CanvasLayer 10): MainMenu → NameScreen →
   PlayChoice → CreateLobby / BrowseLobbies / PasswordPrompt → Lobby. The menu root
   hides entirely during gameplay; ESC opens InGameMenu (Resume, Settings, Leave
   Lobby) as a card over the dimmed game (`InGameDim`) instead of the backdrop.
2. **Name**: saved to `user://user_config.cfg` and used as the **Photon user id**
   (`Fusion.connect_to_photon(nickname, Fusion.get_default_region())`). Changing the
   name while connected disconnects and reconnects (`_connected_name` tracks the
   identity; `_reconnecting` suppresses the disconnect reload). Clicking the robot
   icon opens the color picker; the color is saved as `[player] color` (random on
   first run).
3. **Create lobby**: room name, optional password, Public/Private, player count 2–4,
   rounds 1–10, match wins per round 1–5 (`match_wins`), starting map (`start_map`,
   -1 = random; Start resolves it into `map_index`). The Photon room name is a generated 5-character **code** (shown in
   the waiting room, click to copy); the typed name is the `title` property. Custom
   properties `title`, `private`, `phase="waiting"`, `passworded`, `password`,
   `rounds`, `match_wins`, `start_map`; only `title`/`phase`/`passworded` are lobby properties (the password
   never reaches the browser). Private rooms are created invisible and stay invisible
   after a game.
4. **Join lobby**: the browser lists visible rooms with `phase=="waiting"` that are open
   and not full; the JoinCard also joins any room directly by code. Passworded rooms
   prompt; the password is checked **after joining** and a mismatch leaves and returns
   to the prompt with "Wrong password" (client-side gate).
5. **Names**: on `room_joined` each client publishes `name_<player_id>` as a room
   property; the lobby roster polls it every 0.5 s (fallback: Photon player name, then
   "Player N").
6. **Ready**: each non-host player toggles `ready_<player_id>` (room property) with READY
   UP / CANCEL READY; chips show Ready / Not ready. The host's START MATCH stays disabled
   until ≥2 players are in and every other player is ready; the status line names who
   the room is waiting for. Returning to the lobby after a game clears every ready flag.
7. **Start** (host): writes `phase="playing"`, `match_phase="draft"`, `draft_round=1`,
   `round=1`, then closes/unlists the room.
8. **Spawn**: `match_manager` emits `game_started` when it sees `phase=="playing"`.
   `world.gd::_start_game` spawns the local player through the `FusionSpawner`; the
   master calls `Fusion.register_current_scene()`. `_spawn_local_player` immediately
   calls `player.claim_local_role()` — the node returned by the spawner is this client's
   own copy, so a client can't get stuck as a remote copy waiting on authority.
9. **Respawn**: `match_manager.respawn_requested` → `world.respawn_player` puts the
   player on its host-assigned marker: at every countdown the host shuffles distinct
   `spawn_point` slots for all players (`spawn_<owner id>` room properties,
   `match_manager.spawn_slot_of`), then `player.reset_for_respawn()`. Before the first
   assignment (the game-start spawn behind the draft) each client indexes the sorted
   markers by its place among the sorted room player numbers.
10. **Return to lobby**: after the game-over results (5 s), the host resets the room to
   `phase="waiting"`, clears match/score state, reopens and re-lists the room; every
   client despawns its player and the menu returns to the Lobby page.
11. **Disconnect**: `STATUS_DISCONNECTED` reloads the scene unless it was an expected
	leave (`_room_leave_handled`) or a deliberate reconnect (`_reconnecting`).

---

## 4. Match and round system (`scripts/worlds/match_manager.gd`)

Master-authoritative; every client polls the room's custom properties every 0.25 s
(Fusion exposes no property-changed signal).

- **Match** = one elimination bout. The last player alive scores 1 match point
  (`round_scores`). A draw (nobody alive) scores nothing.
- **Round** = first to `match_wins_per_round` match wins (room `match_wins`, default
  2); the winner's `rounds_won` is persisted and
  `round_scores` reset.
- **Draft** (`match_phase = "draft"`): the game starts in a draft for round 1 (Start
  writes it), and every non-final round win goes intermission → draft → next round.
  `draft_round` is the round being drafted for. Each client rolls its own offers and
  publishes its pick through its player's replicated `net_mods` / `net_draft_round`;
  the host ends the draft once every room player has `net_draft_round >= draft_round`,
  or after `ModRules.DRAFT_SECONDS` + 2 s.
- **Countdown** (`match_phase = "countdown"`, `COUNTDOWN_SECONDS` = 4): every match
  opens with it (after a draft or a normal intermission). `respawn_requested` fires on
  entry; world.gd respawns the local player behind the wipe, and the player stays
  frozen (`set_input_locked`: no move/jump/dash/shoot, mouse look allowed, gravity
  runs) until "fight". `match_number` counts matches within the round.
- **Phase changes** emit `phase_changed(phase, previous)` on every peer (from the phase
  itself, so host and clients share one path). The draft screen, the match-flow overlay
  and the input lock all key off it.
- **Game over** after `rounds_total` rounds: results screen, then `_return_to_lobby`
  after 5 s (`GAME_OVER_SECONDS`).
- **Intermission**: 3 s normally, 5 s after a round win so the map transition fits.
- **`_match_ready`**: the host waits until all expected players have been seen alive
  before evaluating, so a laggy respawn can't hand the match to the first client back.
- **Map rotation**: on every non-final round win the host picks a random map other
  than the current one; `map_changed` fires on host and clients.
- **Host migration**: the game-over and draft countdowns restart if a new host takes
  over; a draft still advances the round (derived from `draft_round`).

Room properties written: `match_phase` ("draft"/"fight"/"intermission"/"game_over"/""),
`round`, `draft_round`, `match_number`, `result_kind` ("draw"/"match"/"round"/"game"),
`map_index`, `last_result`, `result_serial`, `rounds_won_<id>`, `round_score_<id>`.
Flat per-player int properties are deliberate — Photon handles them reliably and writing
every player keeps keys from going stale. The host also bumps `game_serial` on every
Start; a client detects the return to lobby from `phase != "playing"` (so a missed
`game_over` window can't strand it) and, if it stalled through the whole waiting window,
from a changed `game_serial` — either way it despawns its previous player before the
next game.

Signals: `game_started`, `respawn_requested`, `map_changed(index)`,
`returned_to_lobby`, `phase_changed(phase, previous)`.

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
- `net_color` (robot shell color, html; `RobotColor.apply` on every peer)
- `net_ping` (owner's `Fusion.get_rtt()` in ms, refreshed every second; TAB board)
- `net_mods` (the modifier build: picked ids, comma separated; every copy rebuilds from
  it) and `net_draft_round` (last draft picked in)

### RPCs (`@rpc("any_peer")`, kept on the leaf `player.gd`)

| RPC | Sent | Effect |
|---|---|---|
| `rpc_take_damage(amount, attacker_id)` | shooter → victim owner (`Fusion.rpc_to(TARGET_OWNER, …)`) | victim runs the defensive pipeline + `Health.apply` |
| `died_fx(attacker_id)` | victim → all peers | remote copies go dead, emit `Health.died`, the attacker's client flashes the kill banner |
| `respawn_fx()` | victim → all peers | remote copies restore alive visuals |
| `rpc_apply_status(id)` | shooter → victim owner | applies a timed status modifier (e.g. Frost Rounds' `chilled`); ids that aren't statuses are ignored |
| `rpc_knockback(x, y, z)` | modifier → victim owner | adds the shove to the victim's velocity (Charge) |

`Fusion.rpc(Callable(node, "method"), args…)` invokes the method on every peer's replica
of that node (sender included). `Fusion.rpc_to(Fusion.TARGET_OWNER, …)` routes to the
owner client of that replica.

### Damage pipeline (player-vs-player)

1. Weapon (`weapon.gd::_shoot`): camera ray → `mods.on_fire(shot)` (may retarget, e.g.
   Homing Rounds) → `_apply_damage`: `mods.get_stat(&"damage", definition.damage)`
   (capped) → `mods.on_damage_dealt(ctx)` (can mutate; `ctx.statuses` are sent with
   `rpc_apply_status`) → `rpc_take_damage`; lifesteal heals the shooter.
2. Victim (`player_lifecycle.gd::take_damage`): `mods.get_stat(&"damage_taken", amount)`
   (capped) → `mods.on_damage_taken(ctx)` (e.g. Second Wind) → `Health.apply`.
3. `Health.apply` subtracts, emits `damaged`, and on ≤0 emits `died(attacker_id)`.

Caps live in `ModRules.STATS` and apply inside `get_stat`; hooks run after the caps, so
a behaviour has the final say. The pistol does 34 (3 hits kill at 100 HP).

### Death, spectator and respawn

- Local `_die`: `dead = true`, hides the weapon, disables hitbox/physics/state
  machine/camera/weapon, shows the spectator overlay, broadcasts `died_fx`.
- The overlay holds the screen dark for 1 s, then fades the dim out smoothly while the
  centered "ELIMINATED" block fades away and the spectating line + hint fade in at the
  top center (see §9).
- There is **no auto-respawn**: eliminated players spectate until the match ends.
- **Kill height**: a local player below `kill_height` (export, −20) dies at once via
  `Health.apply` (no damage pipeline, no Second Wind, no kill credit).
- **Hit feedback** (victim only, `player_lifecycle.gd::_on_damaged`): a red flash in the
  screen corner nearest the damage source (`scenes/player/hud/hit_flash.tscn`; the
  direction is resolved from the attacker's replica and converted to camera space, and
  all four corners light when the source is unknown, e.g. fall damage) and a short view
  shake
  (`camera_script.gd::shake()`, projection offsets only, so aim never moves).
- Map flyover (`scenes/worlds/map_camera.tscn` + `scripts/worlds/map_camera.gd`): when the
  phase becomes `"draft"`, `world.gd::_on_phase_changed` makes it the current camera and
  it circles the map in MapRoot from outside its edge (exports: orbit seconds, height and
  distance ratios). It restarts on a map swap, and `_respawn_local_player` stops it behind
  the countdown wipe, so the cut back to first person is hidden. The spectator stands
  down while it runs. The draft screen dims to 40% and names the next map.
- Spectating (`scenes/worlds/spectator.tscn` + `scripts/worlds/spectator.gd`, driven by
  `world.gd::_update_spectator`): while the local player is dead the rig sits on a living
  player's head and a `SpringArm3D` (map-only mask, sphere probe) holds the camera 3.5 m
  behind it without clipping walls. The mouse orbits (same sensitivity as first person,
  read in `_input` because the death screen covers the view); the player's own A/D
  cycles targets (stored as instance IDs so a freed replica can't crash the list). The
  rig has physics interpolation **off**: it moves every frame, and an interpolated
  camera moved in `_process` renders stale tick poses and judders.
- `match_manager` respawns everyone between matches (`respawn_fx` syncs remote copies).

### Remote copy behavior (`_disable_remote_copy`)

Physics/state machine/camera/weapon/input off, HUD hidden, `cam.current = false`,
`physics_interpolation_mode = OFF` (so Godot's interpolation doesn't fight Fusion's root
smoothing), model visible to others. `_enable_local_copy` restores interpolation when a
copy flips remote→local.

**Opponent outline** (`scripts/player/player_outline.gd`, `PlayerOutline.set_enabled`):
remote copies get an inverted-hull `material_overlay` on every robot mesh
(`resources/ui/player_outline.tres`, shader `scripts/player/shader/outline.gdshader`:
`color`, `width_px` in screen pixels); your own copy never does. The robot is
flat-shaded, so each mesh is swapped once for a cached copy whose `TANGENT` holds the
smoothed normal (no normal maps use the tangents; skinning moves them like normals) and
the hull grows along that, which keeps it continuous. The hit flash borrows the overlay
slot and `_clear_hit_flash` hands the outline back.

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
checks mask 1. Camera `cull_mask = 1`; the viewmodel renders on render layer 4 in its
own SubViewport world and is only seen by the viewmodel camera (lights must include
layer 4 to affect it — see §12).

---

## 7. Weapons (modular)

- `scenes/weapons/weapon.tscn` — the shared weapon scene: controller, `ViewModel` and
  `WorldModel` mounts, `Muzzle`, shoot/reload sounds, `HitConfirm`.
- `scripts/weapons/weapon.gd` — all shared logic: input, fire cooldown, ammo/reload,
  modifier stats, damage routing, tracer/feedback, visibility; `mag_size()` and
  `reload_progress()` feed the HUD.
- `scripts/weapons/viewmodel_motion.gd` — the viewmodel pivot. Composes idle breathing,
  step bob, sprint tilt (drops while shooting/reloading), strafe roll, look sway,
  air/slide/dash poses, landing dip, spring recoil (`kick()`), the reload animation
  (`start_reload()`: tilt over, mag out/in jolts, rack) and the respawn raise. Rotations
  pivot on the grip (`viewmodel_transform.origin`). Local player only.
- Camera recoil: each `WeaponDefinition` has `recoil_pitch_degrees`, `recoil_yaw_degrees`
  (random ±) and `recoil_recovery`; `weapon.recoil()` passes them to
  `camera_script.gd::add_recoil` (kicks the real camera, so aim moves; settles back).
  0 = no recoil (the default for new weapons); pistol 1.2°/0.4°, hand cannon 3.5°/1.0°.
- `scripts/weapons/weapon_definition.gd` (`WeaponDefinition`) — per-weapon resource:
  `display_name`, `damage`, `mag_size`, `fire_interval`, `reload_time`,
  `range`, `viewmodel_scene`/`viewmodel_transform`, `world_model_scene`/
  `world_model_transform`, `muzzle_transform`, `shoot_sounds`, `reload_sounds`.
- `resources/weapons/pistol.tres` — the equipped weapon. The player exports
  `weapon_definition`; `player.gd::_setup_weapon()` instantiates `weapon.tscn` under the
  camera and calls `weapon.setup(self, definition)`.

**Adding a weapon** = a new `.tres` (plus model scenes) and changing the player's single
`weapon_definition` export. No shared script or player-scene edits.

### Firing (traditional FPS aim)

`weapon.gd::_shoot`:
1. One ray through the screen center (mask 7, shooter excluded) from the camera's
   **interpolated** pose (`get_global_transform_interpolated()`) — what the player
   actually sees; the physics-tick pose runs up to a tick ahead while moving.
2. Damage, hit normal and the tracer use that hit — exactly under the reticle (the
   reticle's bars sit around its control's center for the same reason).
3. The tracer starts at the drawn barrel (viewmodel muzzle projected into the gameplay
   camera; the world model's MuzzleFlash on remote copies) and stops at the hit.

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

Full developer guide: **`docs/MODIFIER_GUIDE.md`** (architecture, recipes, balancing).

```
scripts/modifiers/
  modifier.gd           Modifier Resource: data (type, rarity, max_level, percent/flat
						per level, weapon, exclusive_group, duration) + hooks + describe()
  mod_rules.gd          ModRules: offer count, draft timer, rarities (colour, weight),
						types (name, icon), STATS table (labels, caps, player bindings)
  modifier_db.gd        ModifierDB: discovers resources/modifiers/*.tres (+ status/),
						validates them, roll_offers()
  modifier_manager.gd   per player (`player.mods`): build sync, get_stat, stat/weapon
						application, statuses, hook dispatch
  behaviors/*.gd        Modifier subclasses: status_on_hit (any on-hit status),
						range_damage, homing_rounds, explosive_rounds, executioner,
						second_wind, regenerator, bloodthirst, ghost_dash, charge,
						medic_rain; status behaviours lifted, zapped
resources/modifiers/    one .tres per draftable modifier (file name = id)
resources/modifiers/status/  timed statuses applied by hits (chilled, marked, lifted, zapped)
scenes/ui/mods/         draft_screen, mod_card, mod_icon
tools/check_modifiers.gd  validation: godot --headless --path . --script res://tools/check_modifiers.gd
```

- Build: `player.net_mods` (replicated) → `ModifierManager.sync_build()` on every copy →
  `refresh()` on every manager: active set = own picks + other players' environment
  modifiers + statuses.
- Stats: `get_stat(stat, base) = (base + Σflat) × (1 + Σpercent/100)`, clamped by
  `ModRules.STATS` caps. Stacking is additive. Player-bound stats (speeds, stamina,
  traction, gravity, air jumps, dash charges/cooldown) are written onto the controller
  by the local copy; `max_health` also heals the difference; weapon stats are read in
  `weapon.gd`.
- 33 modifiers (9 Common, 15 Rare, 9 Epic) across the four types; the table is in the
  guide.
- Hooks: `on_fire`, `on_impact`, `on_damage_dealt`, `on_damage_taken`, `on_kill`,
  `on_respawn`, `on_physics`, `on_dash`, `on_shot_fx` (every peer), `on_applied`
  (statuses). Shared APIs for behaviours: `weapon.deal_damage(target, amount, at)`,
  `rpc_knockback`, `player.stun(seconds)` (freezes controls like the match-flow lock,
  via one `_sync_controls()`).

---

## 9. UI

| Piece | File | Notes |
|---|---|---|
| Menu flow | `scripts/ui/connection_ui.gd` + `scenes/ui/connection_menu.tscn` | main menu, name, create/join, browser, password, lobby, in-game menu; styled by `resources/ui/menu_theme.tres` (Lilita One headings/buttons, Rubik body, robot icons from `scenes/ui/robot_icon.tscn`); lives in `MenuLayer` (CanvasLayer 10) |
| Lobby roster | `scripts/ui/lobby_page.gd` | `player_chip.tscn` per player (robot icon, name, Host or Ready / Not ready badge) + `empty_slot.tscn` "Waiting for player"; room info panel; status line (who the room waits for); READY UP / CANCEL READY for guests; host-only START MATCH (enabled once ≥2 players and everyone else is ready) |
| HUD | `scripts/player/hud/hud_script.gd` | builds scoreboard rows every 0.25 s, shows the TAB board while TAB is held (mouse captured; the compact card hides meanwhile), feeds the modifier tray/list from `build_changed`. Every frame `_refresh_hud_visibility` shows your own widgets (gun, reticle, vitals, ammo, modifiers, statuses) only while alive and playing — hidden while spectating, drafting and on the results; the compact scoreboard stays while spectating; the spectator overlay hides behind the draft |
| HUD theme | `resources/ui/hud_theme.tres` | HUD palette and Lilita/Rubik (400–700 `FontVariation`s) as type variations: `HudCard`, `HudSlot`, bar fills, `HudDot(On)`, `HudDiamond(On)`, label styles, and the `Mod*` modifier styles (white header/tile/pip styles tinted per rarity with `self_modulate`); sizes are the mockup's px × 0.79 (HUD) and pt × 0.96 (draft) |
| Modifier draft | `scenes/ui/mods/draft_screen.tscn` + `scripts/ui/mods/draft_screen.gd` | dimmed overlay: round pill, CHOOSE A MODIFIER, `mod_card.tscn` offers (rarity header, type chip, icon, per-pick stat lines, level pips, NEW / MAX LEVEL / SINGLE USE tag), other players' Picked/Choosing, auto-pick timer; click or 1–3; debug builds: F2 opens a local draft |
| Modifier tray | `scenes/player/hud/mod_tray.tscn` + `mod_tray.gd` | own modifiers + active environment ones as `mod_icon.tscn` (rarity tile, type glyph, level badge yellow at max), 8 then "+N"; a fresh pick pops its icon and shows a 3 s toast when gameplay resumes |
| Modifier list | `scenes/player/hud/mod_list.tscn` + `mod_list.gd` | beside the TAB board: icon, name, summary at level, level pips |
| Vitals | `scenes/player/hud/vitals.tscn` + `vitals.gd` | health: red ProgressBar, a tick every 10 HP, pale ghost ProgressBar holds lost health 0.4 s then drains (0.35 s), icon throbs ≤25%; stamina: blue ProgressBar |
| Ammo panel | `scenes/player/hud/ammo_panel.tscn` + `ammo_panel.gd` | ≤24 pips, each `ceil(mag/24)` rounds (×N chip, half pip = partial group); red ≤25%; "RELOAD · R" when empty; reload ring (radial `TextureProgressBar`) + pips refill with `reload_progress()`; dash icon is a bottom-to-top ProgressBar while recovering (`time_bef_reload_dash` / `time_bef_can_dash_again`) |
| Reticle | `scenes/player/hud/reticle.tscn` + `scenes/player/reticle.gd` | the original crosshair: center dot + 4 `Line2D` ticks lerped out by planar speed (`RETICLE_DISTANCE` px per m/s, `RETICLE_SPEED` per-frame lerp), around the control's center so it sits on the shot ray |
| Spectator overlay | `scripts/player/death_screen.gd` | 1 s dark hold, then dim fades out; "ELIMINATED" drops, spectated name + "Mouse to look around · A / D to switch player" move to the top center |
| Scoreboard | `scoreboard_card.tscn` / `scoreboard_full.tscn` + `scoreboard.gd`, rows `score_row(_full).tscn` + `score_row.gd` | yellow dots = this round's match wins ("kills", `match_wins_per_round`), blue diamonds = rounds won, out of a majority of `rounds_total`; sorted by wins, then kills |
| Results | player HUD | GAME OVER + top-3 by rounds won; auto-returns to the lobby after 5 s |
| Match flow | `scenes/ui/match_flow.tscn` + `scripts/ui/match_flow.gd` | slow motion from the last elimination until the next screen (`SLOW_MO_SCALE` 0.3, 1.0 disables; match timers run on real time so it never stretches an intermission); result card: round · match, winner, score, what's next; wipe (`cover()`/`reveal()`, AnimationPlayer); countdown card: round/total · match · map, "GET READY", what you can do, 3-2-1, FIGHT! |
| Hit confirm | `scripts/player/hit_confirm.gd` | hit marker, kill banner, kill sound |
| Hit flash | `scenes/player/hud/hit_flash.tscn` + `hit_flash.gd` | four corner gradients (one GradientTexture2D, flipped per corner); the corner nearest the damage source flashes (front hits → top corners, behind → bottom, unknown source → all four), alpha scales with the damage, tween fade |
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
waits 3 s (so the round-win card plays), wipes in (`MatchFlow.cover()`), swaps the
`MapRoot` child, waits 1 s (`MAP_SETTLE_SECONDS`) for the new map to finish building,
re-collects spawn points, and wipes back out. Respawns that arrive mid-swap wait for it
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
godot --headless --path . --script res://tools/check_modifiers.gd  # modifier validation
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
- **Modifier picks are client-trusted**, like damage: each client rolls its own offers
  and writes its own `net_mods`. The `input_mode` group lookups are inert leftovers
  from `/fps`.
- **Room properties are polled.** Fusion has no property-changed signal; the match
  manager polls every 0.25 s. Flat per-player properties are used deliberately — nested
  dictionaries were avoided for Photon reliability.
- **Passwords are a client-side gate.** The password lives in the room's custom
  properties (not the lobby list) and is checked after joining; a modified client could
  bypass it. Server enforcement needs Photon plugins/auth.
- **TTK knob:** pistol damage 34 in `resources/weapons/pistol.tres` (3 hits at 100 HP).
  Until the modifier pass the damage-taken clamp scaled every hit to ≥40.
- **Ammo is infinite:** there is no reserve; a reload always swaps in a full magazine
  (`mag_size()`, after modifiers).
- **Unvalidated spawns.** Markers are distinct per player (host-assigned) and lifted by a
  fixed amount; there is no floor/capsule/ceiling check. More players than markers
  wrap around and share.
- **Map swap timing** assumes the round intermission (5 s) outlasts the 3 s result-card delay,
  the fades and the 1 s map settle; keep `MAP_SWAP_DELAY`, `MAP_SETTLE_SECONDS` and
  `ROUND_INTERMISSION_SECONDS` in sync.
- **Physics tuning is baked in**: gravity 24 (not 9.8), Jolt, interpolation on, jitter
  fix off. Remote copies turn interpolation off intentionally.
- **D3D12 on Windows** is forced in `project.godot`; Forward+ everywhere.
- **The viewmodel is local-only.** It renders in a transparent SubViewport on its **own
  `World3D`** (map lights don't cross worlds in this Godot build), on render layer 4
  with a fixed FOV; the gameplay camera never sees it and it does not depth-test
  against walls (it draws over them by design). Its world copies the map's environment
  at `_ready` (sky ambient/reflections) and `SunMirror` (`viewmodel_sun.gd`, layer 4)
  mirrors the map sun (group `sun`) each frame, so the gun picks up directional shading.
  The viewmodel camera has physics interpolation **off** and copies the gameplay
  camera's *interpolated* pose each frame (otherwise the gun shakes when turning);
  remote copies disable their SubViewport entirely.
- **Settings** (`scripts/ui/settings_menu.gd`, Settings page; rows are nodes in the
  page, slider ranges on the HSlider nodes): steppers for window
  mode, vsync, max FPS, post effects; sliders (themed in `menu_theme.tres`) for render
  scale (FSR), UI scale (`content_scale_factor`, 50–100%, applied on release), mouse
  sensitivity (`CameraObject.mouse_sensitivity`) and master volume. Saved under
  `[settings]` in `user://user_config.cfg`, applied on load.
- **HUD widgets bind to the HUD's `play_char`**, never a group lookup — remote
  copies are in the `player` group too, and a group lookup would attach to the wrong
  copy on clients.

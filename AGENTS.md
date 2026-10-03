# Multi-Modifier-FPS

Godot 4.7.2 FPS, GDScript only (no C#/.NET). No tests, no CI, no build step.

## Commands

- `godot` is on PATH (4.7.2). Verify changes with:
  `godot --headless --path . --quit` — imports + parses every script; errors and warnings print here.
- Run the game: `godot --path .` (main scene: `res://scenes/worlds/main.tscn`). Needs a display.

## Project quirks (don't fight these)

- **Physics:** Jolt Physics, gravity **24** (not the 9.8 default), physics interpolation on, jitter fix off. Movement code is tuned for these.
- **Input actions are registered at runtime.** `scripts/player/player_movement.gd` (called from `player.gd::_ready`) builds `play_char_*` actions with default keybinds if they're missing from the project InputMap. Runtime registration is temporary (warns in console) — bind actions in Project Settings to persist.
- **Rendering:** D3D12 forced on Windows (`project.godot`), Forward Plus.
- **Networking:** Photon Fusion (Shared Mode) via GDExtension in `addons/fusion` (its `cs/` C# sources are unused). App ID + region live in `project.godot` `[fusion]`, but `connection_ui.gd` calls `Fusion.connect_to_photon()` **without a region**, so cross-machine clients in different Photon regions cannot see each other's rooms (the sibling `/fps` project passes the region explicitly). Room-first flow: `scripts/ui/connection_ui.gd` connects/joins; `scripts/worlds/world.gd` spawns the local player through `FusionSpawner` on `room_joined` and the master client registers the scene. `player.tscn` and `target.tscn` carry `FusionSharedReplicator` nodes (`PlayerAttached` / `MasterClient` ownership); each player copy runs input only when it is positively identified as the local owner.
- Every `.gd`/`.tscn` has a committed `.uid` sidecar — keep them, don't delete.

## Modifier system (the core of this game)

- Stat-only modifier = a `.tres` dropped in `scripts/modifiers/defs/` **plus one line** in `modifier_db.gd::_build_defs()`. Missing the registry line = modifier doesn't exist.
- Behavioral modifier = subclass `Modifier` (`scripts/modifiers/modifier.gd`) and override hooks (`on_damage_dealt`, `on_damage_taken`, `on_kill`). Hooks mutate the ctx Dictionary.
- All final stat math goes through `ModifierManager.get_stat()` — caps per stat are enforced in `STAT_CAPS` there, nowhere else.
- **No acquisition path yet:** nothing in-game calls `ModifierManager.set_build()` (no draft/pickups), and `rpc_draft_pick` / `input_mode` group lookups are inert leftovers from `/fps`. Exercise mods from a debug script. Full map: `docs/PROJECT_DOCUMENTATION.md`.

## Player state machine

- `scripts/player/state_machine/`: each state is a `State` subclass attached as a **child node** of the StateMachine. States register by lowercased node name; transitions fire the `transitioned` signal with that name.
- The StateMachine awaits the player character's `ready` before entering `initial_state` — don't call state logic from the player's own `_ready`.

## Player script layout

- `player.gd` is the leaf of an inheritance chain: `player_base.gd` (exports, shared state, node refs) → `player_movement.gd` (keybinds, timers, stamina, gravity, tweens) → `player_network.gd` (replicated state, view/animation sync, ownership role) → `player_lifecycle.gd` (damage, death, respawn) → `player.gd` (`class_name PlayerCharacter`, `_ready`/`_process`/`_physics_process`, `@rpc` entry points). A layer can only call methods defined in itself or its parents, so keep `@rpc` methods on the leaf.
- Keep scripts under ~400 lines; split by responsibility the same way when one grows past it.

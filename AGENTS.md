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
- **Networking:** Photon Fusion (Shared Mode) via GDExtension in `addons/fusion` (its `cs/` C# sources are unused). App ID + region live in `project.godot` `[fusion]`; `connection_ui.gd` connects with `Fusion.connect_to_photon(nickname, Fusion.get_default_region())` (the nickname is the Photon user id). Room-first flow: `scripts/ui/connection_ui.gd` connects/joins; `scripts/worlds/match_manager.gd` owns match state through polled room custom properties; `scripts/worlds/world.gd` spawns the local player through `FusionSpawner` when the host starts the game and the master registers the scene. `player.tscn` and `target.tscn` carry `FusionSharedReplicator` nodes (`PlayerAttached` / `MasterClient` ownership); each player copy runs input only when it is positively identified as the local owner (`claim_local_role()` on the locally spawned node).
- **Lobby/match/weapon systems are built here** (not in the original port): menu + room browser + passwords + rounds, round/match scoring with spectator and map rotation, and a modular weapon system (shared `scenes/weapons/weapon.tscn` + a `WeaponDefinition` `.tres` per weapon). Full map: `docs/PROJECT_DOCUMENTATION.md`.
- Every `.gd`/`.tscn` has a committed `.uid` sidecar — keep them, don't delete.

## Modifier system (the core of this game)

Full guide: `docs/MODIFIER_GUIDE.md`. Ideas backlog: `docs/MODIFIER_CONCEPTS.md`.

- A modifier is a `.tres` in `resources/modifiers/` (file name = id). It's **auto-discovered**: no registry line. Statuses (timed, applied by hits) live in `resources/modifiers/status/`.
- Stat-only = data only (`percent` / `flat` per level, by `ModRules.STATS` key). Behavioural = subclass `Modifier` in `scripts/modifiers/behaviors/` and override hooks (`on_fire`, `on_damage_dealt`, `on_damage_taken`, `on_kill`, `on_respawn`); hooks mutate the ctx Dictionary.
- `scripts/modifiers/mod_rules.gd` (`ModRules`) is the one tuning file: offer count, draft timer, rarity colours/weights, type icons, and the STATS table (labels, caps, player-property bindings). A new stat is one row there.
- All stat math goes through `player.mods.get_stat()` (caps enforced there, nowhere else). Stacking is additive.
- The build replicates as the player's `net_mods`; environment modifiers apply to every player. The draft is `match_phase = "draft"` (before round 1 and between rounds); every match then opens with `"countdown"` (players respawned behind a wipe and frozen via `set_input_locked`). Listen to `match_manager.phase_changed` for anything that depends on the phase.
- Validate after any modifier change: `godot --headless --path . --script res://tools/check_modifiers.gd` → `MODIFIERS OK`.

## Player state machine

- `scripts/player/state_machine/`: each state is a `State` subclass attached as a **child node** of the StateMachine. States register by lowercased node name; transitions fire the `transitioned` signal with that name.
- The StateMachine awaits the player character's `ready` before entering `initial_state` — don't call state logic from the player's own `_ready`.

## Player script layout

- `player.gd` is the leaf of an inheritance chain: `player_base.gd` (exports, shared state, node refs) → `player_movement.gd` (keybinds, timers, stamina, gravity, tweens) → `player_network.gd` (replicated state, view/animation sync, ownership role) → `player_lifecycle.gd` (damage, death, respawn) → `player.gd` (`class_name PlayerCharacter`, `_ready`/`_process`/`_physics_process`, `@rpc` entry points). A layer can only call methods defined in itself or its parents, so keep `@rpc` methods on the leaf.
- Keep scripts under ~400 lines; split by responsibility the same way when one grows past it.

## Development requirements

Keep the code easy to pick up and extend without rewriting what exists:

- **Data, not code.** Tunable numbers live in resources (`.tres`) or the one rules table of their system (`ModRules`, `WeaponDefinition`); no magic numbers in logic.
- **Extend by adding files.** New modifiers, weapons and statuses are new `.tres` / subclasses that plug into existing APIs (hooks, `get_stat`, `equip_weapon`). If a feature needs an edit to shared code, add a general extension point (a hook, a stat row) once, not a special case.
- **Nodes and scenes for UI.** Build UI in `.tscn` files styled by theme type variations (`hud_theme.tres`, `menu_theme.tres`); scripts only set values, visibility and variations. Repeated items duplicate a template child with `NodeUtil.fit_children`. No `_draw()`.
- **Signals up, calls down.** Children emit signals; owners call methods on children. Don't reach across the tree; pass references with exports or the owner.
- **UI answers four questions** at every moment: where am I (round, match, map, page), what can I do (controls, enabled actions, why a button is disabled), what happens next (countdowns, "waiting for…"), and what have I done / what happened (picks, ready state, results).
- **One responsibility per script**, under ~400 lines; doc comment at the top saying what it owns.
- **Verify before handing off:** `godot --headless --path . --quit` (clean) and the modifier check above.

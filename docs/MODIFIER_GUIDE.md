# Modifier Guide

How the modifier system works and how to extend it. Read this before adding or
tuning a modifier. Ideas waiting to be built are in `MODIFIER_CONCEPTS.md`; the
UI mockup is `Modifier Arena — Modifier System-selection.pdf`.

**Goal of the architecture:** new content is *new files* that plug into existing
APIs. Adding a modifier should never require editing the draft, the HUD, the
manager or another modifier.

---

## 1. The rules of the game

- Before round 1 and after every round except the last, every player is shown
  **3 cards** and picks **1** (20 s, then a random card is picked for them).
- **Types** (set the icon):
  | Type | Meaning |
  |---|---|
  | Stats | player stats: damage, speed, health, healing |
  | Weapon | how the gun behaves, or a weapon replacement |
  | Ability | a new capability (extra jump, extra dash, survive a lethal hit…) |
  | Environment | changes the match **for every player** |
- **Rarity** (sets the colour and how often the card shows up): Common (blue,
  weight 60), Rare (orange, 30), Epic (purple, 10). Rarity is fixed per modifier.
- **Levels:** a modifier can be picked up to `max_level` times; each pick adds
  its values again. At max level it leaves your pool for good.
- **Environment** modifiers apply to everyone from the moment one player picks
  them, for the rest of the game, and leave every player's pool.
- **Exclusive groups:** owning a modifier of a group removes the group's other
  modifiers from your pool (e.g. only one weapon replacement).
- Builds reset when a new game starts.

---

## 2. Where things live

| Path | What |
|---|---|
| `resources/modifiers/*.tres` | one file per draftable modifier. **The file name is the id.** Auto-discovered. |
| `resources/modifiers/status/*.tres` | timed status effects applied by hits (never drafted) |
| `scripts/modifiers/modifier.gd` | `Modifier` resource: fields, `describe()`, hooks |
| `scripts/modifiers/behaviors/*.gd` | `Modifier` subclasses with behaviour |
| `scripts/modifiers/mod_rules.gd` | `ModRules`: **every shared tuning knob** (offer count, timer, rarities, types, stats) |
| `scripts/modifiers/modifier_db.gd` | `ModifierDB`: discovery, validation, `roll_offers()` |
| `scripts/modifiers/modifier_manager.gd` | `ModifierManager`, one per player (`player.mods`) |
| `scenes/ui/mods/` | draft screen, card, icon |
| `scenes/player/hud/mod_tray.tscn`, `mod_list.tscn` | HUD tray and TAB list |
| `assets/ui/mods/*.svg` | type glyphs |
| `tools/check_modifiers.gd` | validation script (run it after every change) |

---

## 3. Data flow

```
draft_screen ── player.mods.pick(id) ──► player.net_mods  (replicated "a,a,b")
											  │ setter, on every copy of that player
											  ▼
							  ModifierManager.sync_build(csv)
											  │ call_group("modifier_manager", "refresh")
											  ▼
			  refresh(): active = own picks + others' Environment mods + statuses
                 ├─ _rebuild_cache()       Σflat / Σpercent per stat
                 ├─ _apply_player_stats()  local copy only: controller properties
                 ├─ _apply_weapon()        every copy: weapon replacement
                 └─ build_changed          HUD tray + TAB list redraw
```

Who runs what:

| Code | Runs on |
|---|---|
| Rolling offers, picking | each client, for its own player |
| `get_stat`, player stat application | the local copy (the one that simulates) |
| `on_fire`, `on_impact`, `on_damage_dealt`, `on_kill` | the shooter's client |
| `on_damage_taken`, `on_respawn`, `on_physics`, `on_dash`, statuses (`on_applied`) | the victim's / owner's client |
| `on_shot_fx` (visuals of a shot) | every peer (each copy carries the shooter's modifiers) |
| Weapon replacement visuals | every copy |
| Ending the draft | the host (`match_manager.gd`, waits for every `net_draft_round`) |

Picks are client-trusted, like damage.

---

## 4. Modifier fields (`.tres`)

| Field | Meaning |
|---|---|
| `display_name` | card title |
| `description` | one flavour line under the title |
| `type` | `STATS` / `WEAPON` / `ABILITY` / `ENVIRONMENT` (icon; ENVIRONMENT = everyone) |
| `rarity` | `COMMON` / `RARE` / `EPIC` |
| `max_level` | 1–5 picks |
| `percent` | per level, `{&"stat": 15.0}` = +15 % per level |
| `flat` | per level, `{&"stat": 15.0}` = +15 per level |
| `weapon` | a `WeaponDefinition` that replaces the owner's weapon |
| `exclusive_group` | modifiers sharing it never stack |
| `duration` | > 0 makes it a status (only in `status/`) |

Card lines (stat label, signed value, green/red) are generated from
`percent`/`flat` with the labels in `ModRules.STATS`. You never write UI text
for stats.

---

## 5. Recipes

### A. A stat-only modifier (most modifiers)

Create `resources/modifiers/thick_skin.tres` (or duplicate an existing one in
the editor and edit it in the inspector):

```ini
[gd_resource type="Resource" script_class="Modifier" format=3]

[ext_resource type="Script" path="res://scripts/modifiers/modifier.gd" id="1_script"]

[resource]
script = ExtResource("1_script")
display_name = "Thick Skin"
description = "Shrug off a little of every hit."
type = 0
rarity = 0
max_level = 3
percent = Dictionary[StringName, float]({ &"damage_taken": -8.0 })
```

That's it: it is in the draft pool, the card, the tray and the TAB list.

### B. A new stat

Add one row to `ModRules.STATS`:

```gdscript
&"jump_height": {"label": "Jump height", "min": 0.5, "max": 2.0, "good": 1,
		"player": [&"jump_velocity"]},
```

- `player`: controller properties this stat scales. `ModifierManager` snapshots
  their base values and writes the modified values on the local copy. Nothing
  else may write those properties.
- No `player` key: read it where it applies, e.g.
  `var spread := play_char.mods.get_stat(&"spread", definition.spread)`.
- `min`/`max` cap the final value as multiples of the base (absolute limits
  when the base is 0). `good` colours the card value (+1 higher is better,
  -1 lower is better). `suffix` is the unit shown after flat values.

### C. A behaviour modifier

1. Subclass `Modifier` in `scripts/modifiers/behaviors/my_mod.gd` and override
   only the hooks you need. Export the tuning values so they stay in the `.tres`.
   Override `describe()` to add card lines:

   ```gdscript
   extends Modifier

   ## Ability: kills refill your magazine.

   func on_kill(_ctx: Dictionary, me: Node) -> void:
   	me.weapon.ammo = me.weapon.mag_size()


   func describe(at_level: int = 1) -> Array[Dictionary]:
   	var lines := super(at_level)
   	lines.append(line("On kill", "Full magazine", TONE_GOOD))
   	return lines
   ```

2. Create its `.tres` in `resources/modifiers/` with
   `[ext_resource type="Script" path="res://scripts/modifiers/behaviors/my_mod.gd" ...]`.

Behaviour state (e.g. "used this life") lives in instance variables: every
player gets its own copy, kept across refreshes. Reset per-life state in
`on_respawn`. Examples: `second_wind.gd`, `homing_rounds.gd`, `regenerator.gd`,
`charge.gd`. One script can serve several modifiers with different exported
values (`range_damage.gd` is both Close Quarters and Marksman).

### D. A status effect on hit (slow, mark, stun, lift…)

1. Make the status: a `Modifier` `.tres` in `resources/modifiers/status/` with
   `duration > 0`:
   - stat-only: its stat changes (`status/chilled.tres`, `status/marked.tres`);
   - with behaviour: a script overriding `on_applied(me)` (once per hit,
     e.g. `zapped.gd` calls `me.stun(duration)`) or `on_physics(delta, me)`
     (every tick while active, e.g. `lifted.gd` sets `me.velocity.y`).
2. The on-hit modifier is `behaviors/status_on_hit.gd` with
   `status_id = &"your_status"` — no new script (Frost Rounds, Marked Target,
   Zap Gun, Anti-gravity Gun). The weapon sends the id with
   `rpc_apply_status`; the victim's client applies it for `duration` seconds
   (re-hits refresh the timer). Active statuses show as chips under the
   victim's reticle.

### D2. Area damage, knockback and stuns

- `me.weapon.deal_damage(target, amount, at)` sends damage to a player or
  practice target and shows the hit marker (Explosive Gun's blast in
  `on_impact`, Charge's ram). It skips the shot's hooks on purpose.
- `Fusion.rpc_to(Fusion.TARGET_OWNER, Callable(target, "rpc_knockback"), x, y, z)`
  shoves another player (its owner adds the velocity).
- `me.stun(seconds)` freezes the owner's movement and shooting; it never
  lifts the match-flow lock.
- Visuals every peer must see go in `on_shot_fx` (e.g. spawn an exported
  effect scene at `hit.position`).

### E. A weapon replacement

1. Make a `WeaponDefinition` in `resources/weapons/` (stats, models, sounds).
2. A modifier with `weapon = ExtResource(...)`, usually
   `exclusive_group = &"weapon"`. See `hand_cannon.tres`. The swap happens on
   every copy, so other players see the new gun. Weapon stats from other
   modifiers still apply to it.

### F. An Environment modifier

Same as A with `type = 3`. It applies to every player while anyone owns it.
Keep it `max_level = 1`.

### G. A new hook

When no hook fits (e.g. "on reload"):

1. Add the virtual method to `modifier.gd` (with a doc comment of its ctx keys).
2. Add a dispatcher to `modifier_manager.gd`, like `on_kill`.
3. Call it at the one place in game code where the event happens
   (`play_char.mods.on_reload(ctx)`).

Existing modifiers are untouched: the base method does nothing.

### H. Active abilities (planned)

A right-click ability would be a hook `on_ability(me)`, an input action
`play_char_ability_action`, and a cooldown stat; the first Ability modifier
that needs it adds them (recipe G).

---

## 6. Hooks reference

| Hook | When | ctx |
|---|---|---|
| `on_fire(shot, me)` | owner fires, after the camera ray | `origin`, `direction`, `range`, `hit` (ray result: `collider`, `position`, `normal`). Replace `hit` to retarget. |
| `on_damage_dealt(ctx, me)` | owner hits a player or target, after the damage stat | `amount`, `attacker_id`, `distance`, `hit_player`, `victim`, `statuses` |
| `on_damage_taken(ctx, me)` | owner is hit, after the damage_taken stat | `amount`, `attacker_id` |
| `on_kill(ctx, me)` | owner eliminated someone | `victim` |
| `on_respawn(me)` | owner (re)spawns | — |
| `on_physics(delta, me)` | every physics tick of the owner's own copy, before it moves | — (override `me.velocity`, heal over time, check areas) |
| `on_dash(me)` | owner starts a dash | — |
| `on_impact(shot, me)` | owner's shot landed, after every `on_fire` | `shot` as above; `hit` is empty on a miss |
| `on_shot_fx(hit, me)` | the shot's visuals, on **every peer** | `position`, `normal` (ZERO on a miss) |
| `on_applied(me)` | a status was applied (or re-applied) to its owner | — |

Hooks run **after** the stat caps, so a behaviour has the final say (Second
Wind lowers a lethal hit).

---

## 7. Balancing

**Stacking is additive per stat:** two +25 % damage picks = +50 %, not
+56 %. `get_stat(stat, base) = (base + Σflat) × (1 + Σpercent / 100)`, then
the cap from `ModRules.STATS`.

**Power budget per pick:**

| Rarity | Budget | Levels |
|---|---|---|
| Common | one stat, about 10–15 % (or +10–15 flat) | up to 3 |
| Rare | about 20–25 %, or two stats with a trade-off, or a mild behaviour | 1–2 |
| Epic | game-changing (behaviour, weapon swap, environment), often with a downside | 1 |

**Knobs, in order of reach:**
1. Per-modifier values in its `.tres`.
2. Caps in `ModRules.STATS` (the ceiling no build can pass).
3. Rarity weights in `ModRules.RARITIES`.
4. `ModRules.OFFER_COUNT` and `DRAFT_SECONDS`.
5. Time to kill: pistol `damage = 34` in `resources/weapons/pistol.tres`
   (3 hits at 100 HP). Health, damage and lifesteal mods are tuned against it.

A 5-round game gives 5 picks. Max-level stacks hit at most: move speed +45 %
(cap +60 %), damage +100 % with Glass Cannon and 2× Heavy Rounds (cap +150 %).

**Starter set** (values per level):

| Modifier | Type | Rarity | Lv | Effect |
|---|---|---|---|---|
| Swift Boots | Stats | Common | 3 | move speed +15 % |
| Plating | Stats | Common | 3 | max health +15 |
| Marathon | Stats | Common | 2 | stamina (max and regen) +25 % |
| Siphon | Stats | Rare | 2 | lifesteal +15 % of damage dealt |
| Glass Cannon | Stats | Epic | 1 | damage +50 %, max health −30 % |
| Hair Trigger | Weapon | Common | 3 | fire rate +12 % |
| Extended Mag | Weapon | Common | 2 | magazine +40 % |
| Fast Hands | Weapon | Common | 2 | reload time −20 % |
| Heavy Rounds | Weapon | Rare | 2 | damage +25 %, fire rate −10 % |
| Frost Rounds | Weapon | Rare | 1 | hits slow the target 30 % for 1.5 s |
| Homing Rounds | Weapon | Epic | 1 | misses within 6° of an enemy hit them |
| Hand Cannon | Weapon | Epic | 1 | weapon: 70 damage, 5 rounds, slow |
| Spring Coil | Ability | Rare | 2 | +1 air jump |
| Dash Surge | Ability | Rare | 2 | dash cooldown −20 % |
| Twin Dash | Ability | Epic | 1 | +1 dash charge |
| Second Wind | Ability | Epic | 1 | once per life, survive a lethal hit at 1 HP |
| Ice Rink | Environment | Rare | 1 | traction −60 %, everyone |
| Paper Armor | Environment | Rare | 1 | max health −25 %, everyone |
| Low Gravity | Environment | Epic | 1 | gravity −40 %, everyone |
| Thick Skin | Stats | Common | 3 | damage taken −8 % |
| Close Quarters | Stats | Common | 3 | +12 % damage within 8 m |
| Marksman | Stats | Common | 3 | +12 % damage beyond 20 m |
| Bloodthirst | Stats | Rare | 2 | each kill heals 25 HP |
| Regenerator | Stats | Rare | 2 | 3 HP/s after 4 s without damage |
| Executioner | Weapon | Rare | 2 | +30 % damage to players below 30 % health |
| Marked Target | Weapon | Rare | 1 | hits mark the target: damage taken +15 % for 3 s |
| Zap Gun | Weapon | Rare | 1 | hits stun the target 0.5 s (no move/shoot), then 1.5 s immunity |
| Explosive Gun | Weapon | Epic | 1 | landed shots explode: 50 % damage within 3 m (direct target too), shooter immune |
| Anti-gravity Gun | Weapon | Epic | 1 | hits lift the target at its walk speed for 2 s |
| Ghost Dash | Ability | Rare | 1 | untouchable while dashing and 0.25 s after |
| Charge | Ability | Epic | 1 | a dash rams players within 2.5 m: 40 damage + knockback |
| Turbo | Environment | Rare | 1 | move speed and fire rate +25 %, everyone |
| Medic Rain | Environment | Rare | 1 | everyone regenerates 2 HP/s |

---

## 8. UI (nothing to do per modifier)

- Cards, tray icons and TAB rows are filled from the data: rarity colour and
  name from `ModRules.RARITIES`, type name and glyph from `ModRules.TYPES`,
  lines from `describe()`, summary from `summary()`.
- A new **type**: add the enum value in `modifier.gd`, a row in
  `ModRules.TYPES` and a glyph SVG in `assets/ui/mods/` (48×48, cream fill
  `#F4EEE2`, ink stroke `#0E1015`; import as `DPITexture` like the others).
- Styles are `Mod*` variations in `resources/ui/hud_theme.tres`; rarity colour
  is applied with `self_modulate` on white styles.

---

## 9. Testing

1. `godot --headless --path . --script res://tools/check_modifiers.gd` →
   `MODIFIERS OK`. It catches unknown stat keys, missing names, duplicate ids,
   misplaced statuses, cards without lines, broken offer rules and stat math.
2. `godot --headless --path . --quit`: no errors or warnings.
3. In a debug build, **F2** opens a local draft at any time during a game, so
   you can stack modifiers and feel them without finishing rounds.
4. Two instances for anything networked: environment mods, statuses, weapon
   replacements, the draft bar's Picked/Choosing.

---

## 10. Checklist for a new modifier

- [ ] `.tres` in `resources/modifiers/` with a clear snake_case file name
- [ ] `display_name`, one-line `description`, `type`, `rarity`, `max_level`
- [ ] values fit the rarity budget (§7); new stats added to `ModRules.STATS`
- [ ] behaviour (if any) in `behaviors/`, tuning values exported, `describe()` adds its lines
- [ ] `check_modifiers.gd` prints `MODIFIERS OK`
- [ ] tried in game (F2), and with two clients if it's global or networked
- [ ] `docs/MODIFIER_CONCEPTS.md`: mark the idea ✓

## Pitfalls

- Typed dictionary keys must be StringNames: `&"move_speed"`, not `"move_speed"`.
- Don't write a property listed in a STATS `player` binding anywhere else; the
  manager owns it after the first apply.
- Stats only affect the local copy; for something other players must *see*, use
  replicated state (like `net_mods` and the weapon swap).
- Hooks run on one client (see §3). Anything another client must react to goes
  through an RPC (like `rpc_apply_status`) or replicated state.

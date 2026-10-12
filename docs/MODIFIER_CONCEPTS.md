# Modifier Concepts

Ideas backlog. ✓ = shipped (see `MODIFIER_GUIDE.md` §7 for exact values). Numbers are
per level and follow the rarity budget in the guide (§7). The tag says what building
it takes; recipes are in the guide (§5).

| Tag | Building it takes |
|---|---|
| [data] | a `.tres` only |
| [new stat] | a row in `ModRules.STATS` (+ a player binding or a `get_stat` call where it applies), then a `.tres` |
| [hook] | a behaviour subclass using the existing hooks |
| [status] | a status `.tres` in `status/` + a hook that applies it |
| [weapon] | a `WeaponDefinition` (models, sounds) + a `.tres` |
| [new hook] | a new hook first (guide recipe G), then a behaviour |
| [new system] | engine work beyond a hook (new nodes, replicated state, visuals) |

# Stats-based

| Idea | Rarity | Lv | Effect | Tag |
|---|---|---|---|---|
| ✓ Swift Boots | Common | 3 | move speed +15 % | [data] |
| ✓ Plating | Common | 3 | max health +15 | [data] |
| ✓ Marathon | Common | 2 | stamina max + regen +25 % | [data] |
| ✓ Siphon | Rare | 2 | lifesteal +15 % of damage dealt | [data] |
| ✓ Glass Cannon | Epic | 1 | damage +50 %, max health −30 % | [data] |
| ✓ Thick Skin | Common | 3 | damage taken −8 % | [data] |
| Bulwark | Rare | 1 | max health +40, move speed −15 % | [data] |
| Featherweight | Common | 2 | jump height +15 % | [new stat] |
| Sprinter | Common | 2 | stamina drain −20 % | [new stat] |
| ✓ Bloodthirst | Rare | 2 | each kill heals 25 HP | [hook] |
| Adrenaline | Rare | 1 | +30 % move speed for 3 s after a kill (self status) | [status] |
| Last Stand | Epic | 1 | +40 % damage while below 30 % health | [hook] |
| ✓ Regenerator | Rare | 2 | regenerate 3 HP/s after 4 s without taking damage | [hook] (`on_physics`) |
| ✓ Close Quarters | Common | 3 | +12 % damage to enemies within 8 m (`ctx.distance`) | [hook] |
| ✓ Marksman | Common | 3 | +12 % damage to enemies beyond 20 m | [hook] |
| Iron Lungs | Common | 2 | stamina regen starts 30 % sooner | [new stat] |
| Momentum | Rare | 2 | +5 % damage per 2 m/s you move above walking speed | [hook] |
| Underdog | Rare | 1 | +20 % damage and +15 % speed while you have the fewest round wins | [hook] (reads match state on respawn) |
| Leech Field | Rare | 1 | heal 2 HP/s while an enemy is within 6 m | [hook] (`on_physics`) |
| Hot Streak | Epic | 1 | each kill this life: +10 % damage and speed (max 3), lost on death | [hook] + [status] |
| Juggernaut | Epic | 1 | max health +60, move speed −25 %, no dash | [data] + [new stat] |

# Weapon

| Idea | Rarity | Lv | Effect | Tag |
|---|---|---|---|---|
| ✓ Hair Trigger | Common | 3 | fire rate +12 % | [data] |
| ✓ Extended Mag | Common | 2 | magazine +40 % | [data] |
| ✓ Fast Hands | Common | 2 | reload time −20 % | [data] |
| ✓ Heavy Rounds | Rare | 2 | damage +25 %, fire rate −10 % | [data] |
| ✓ Frost Rounds | Rare | 1 | hits slow the target 30 % for 1.5 s | [status] |
| ✓ Homing Rounds | Epic | 1 | misses within 6° of an enemy hit them | [hook] |
| ✓ Hand Cannon | Epic | 1 | weapon: 70 damage, 5 rounds, slow fire | [weapon] |
| ✓ Marked Target | Rare | 1 | hit enemies take +15 % damage for 3 s | [status] |
| Shock Rounds | Rare | 1 | hits double the target's dash cooldown for 2 s | [status] |
| Long Barrel | Common | 2 | range +25 %, damage +5 % | [new stat] |
| Tap Fire | Common | 2 | the first shot after 0.5 s idle deals +30 % | [hook] |
| Bottomless Mag | Epic | 1 | every 4th shot doesn't use ammo | [hook] |
| Quick Draw | Rare | 1 | a kill reloads instantly | [hook] |
| Ricochet | Epic | 1 | a hit bounces to the nearest other enemy within 8 m for 50 % | [hook] |
| Explosive Rounds | Epic | 1 | hits splash 40 % damage within 2.5 m | [hook] |
| Burst Rifle / Railgun | Epic | 1 | weapon replacements | [weapon] (needs models) |
| Shotgun | Epic | 1 | 6 pellets per shot | [new system] (multi-ray `on_fire`) |
| Hollow Point | Common | 3 | damage +8 %, magazine −5 % | [data] |
| Drum Mag | Rare | 1 | magazine ×2, reload time +40 % | [data] |
| Akimbo | Epic | 1 | fire rate +60 %, damage −25 % | [data] |
| Quickscope | Common | 2 | +15 % damage while zoomed | [hook] (reads the camera zoom) |
| ✓ Executioner | Rare | 2 | +30 % damage to enemies below 30 % health | [hook] (victim's `net_health`) |
| Piercing Rounds | Rare | 1 | a shot passes through the first player and hits one behind for 60 % | [hook] |
| Chain Lightning | Epic | 1 | a hit arcs 15 damage to every other enemy within 5 m of the target | [hook] |
| Speed Loader | Rare | 1 | reloading an empty magazine is 50 % faster | [new hook] (`on_reload`) |
| Sniper | Epic | 1 | weapon: 1 round, 90 damage, long range | [weapon] (needs a model) |

| ✓ Zap Gun | Rare | 1 | hits stun the target 0.5 s (no move/jump/dash/shoot), then 1.5 s immunity | [status] (`on_applied`) |
| ✓ Explosive Gun | Epic | 1 | landed shots explode for 50 % damage within 3 m, direct target included | [hook] (`on_impact`, `on_shot_fx`) |
| ✓ Anti-gravity Gun | Epic | 1 | hits lift the target at its walk speed for 2 s | [status] (`on_physics`) |

# Environment-based

All apply to every player once anyone picks them.

| Idea | Rarity | Lv | Effect | Tag |
|---|---|---|---|---|
| ✓ Low Gravity | Epic | 1 | gravity −40 % | [data] |
| ✓ Ice Rink | Rare | 1 | traction −60 % (slippery floors) | [data] |
| ✓ Paper Armor | Rare | 1 | max health −25 % | [data] |
| Heavy World | Rare | 1 | gravity +20 % | [data] |
| ✓ Turbo | Rare | 1 | move speed and fire rate +25 % | [data] |
| Vampire Night | Epic | 1 | lifesteal +20 % | [data] |
| Sudden Death | Epic | 1 | max health −50 % | [data] |
| Bottomless Clips | Epic | 1 | magazines ×4 | [new stat] (the `mag_size` cap stops at ×2.5) |
| Fog of War | Rare | 1 | thick fog on the map | [new hook] (a world-level hook for visuals) |
| Lights Out | Epic | 1 | darkness; only muzzle flashes light the map | [new hook] |
| Shrinking Arena | Epic | 1 | a damage zone closes in during each match | [new system] |
| Bouncy Floors | Rare | 1 | landing bounces you back up | [new hook] (`on_land`) |
| Moon Jump | Rare | 1 | jump height +40 % | [new stat] |
| Hyper Reload | Rare | 1 | reload time −40 % | [data] |
| Glass Arena | Epic | 1 | damage +50 % | [data] |
| Long Walls | Rare | 1 | wallrun time ×2 | [new stat] |
| ✓ Medic Rain | Rare | 1 | everyone regenerates 2 HP/s | [hook] (`on_physics`) |
| Marked Leader | Rare | 1 | the player leading the round takes +20 % damage | [hook] (reads match state) |
| One in the Chamber | Epic | 1 | every magazine holds 1 round; a kill refills it | [new stat] + [hook] |
| Tiny Robots | Epic | 1 | every model and hitbox shrinks to 70 % | [new system] |

# Special Mods

Abilities: a new capability rather than a number. Single level unless a second level
adds something new. Right-click actives need the planned `on_ability` hook (guide §5 H).

| Idea | Rarity | Lv | Effect | Tag |
|---|---|---|---|---|
| ✓ Spring Coil | Rare | 2 | +1 air jump | [data] |
| ✓ Dash Surge | Rare | 2 | dash cooldown −20 % | [data] |
| ✓ Twin Dash | Epic | 1 | +1 dash charge | [data] |
| ✓ Second Wind | Epic | 1 | once per life, a lethal hit leaves 1 HP | [hook] |
| Wall Runner | Common | 2 | wallrun time +40 % | [new stat] |
| Slide Master | Common | 2 | slide speed +20 % | [new stat] |
| ✓ Ghost Dash | Rare | 1 | untouchable while dashing and 0.25 s after | [hook] (`on_dash`) |
| Ground Pound | Rare | 1 | crouch in the air to slam down and damage nearby players | [new hook] (`on_land`) |
| Blink | Epic | 1 | right-click: short teleport forward | [new hook] (`on_ability`) |
| Grapple | Epic | 1 | right-click: pull toward the aimed surface | [new hook] + [new system] |
| Overshield | Rare | 1 | a 25 HP shield that refills after 5 s without damage | [new system] |
| Cloak | Epic | 1 | invisible after standing still for 2 s | [new system] (replicated visibility) |
| Rocket Jump | Rare | 1 | shooting the floor under you launches you upward | [hook] (`on_fire` + an impulse) |
| Air Brake | Common | 1 | hold crouch in the air to fall slowly | [new system] |
| Phoenix | Epic | 1 | when you die, explode for 40 damage within 4 m | [new hook] (`on_death`) |
| Scout's Eyes | Rare | 1 | enemies you hit stay outlined through walls for 3 s | [status] + [new system] (outline) |
| Wall Cling | Rare | 1 | stick to a wall and hang for up to 2 s | [new system] |
| Shockwave | Epic | 1 | right-click: knock back every enemy within 6 m | [new hook] (`on_ability`) |
| Decoy | Epic | 1 | right-click: a hologram copy runs forward for 4 s | [new hook] + [new system] |
| ✓ Charge | Epic | 1 | a dash rams players within 2.5 m: 40 damage and knockback | [hook] (`on_dash`, `on_physics`) |

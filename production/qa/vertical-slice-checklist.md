# GRAVEBAG vertical-slice checklist (Godot 4.6)

Source: `design/game-brief.md` (playable single-player slice; clean-room, one class).
How to use: play the slice headless or in-editor, answer each item yes/no by
observation. Any NO is a slice failure — file it with the observed behaviour.

## 1. Move / aim / shoot
- [ ] YES/NO — WASD moves the character in all four directions with no stuck keys.
- [ ] YES/NO — Character/weapon faces the mouse cursor (mouse aim observed).
- [ ] YES/NO — Hold-click (or autofire key I) fires projectiles toward the cursor.
- [ ] YES/NO — Space fires the class ability (observable effect, cooldown or cost).
- [ ] YES/NO — F/V quaff potions from the stack (counts decrement, effect applies).

## 2. Enemy bullet patterns (all 3 visible in the realm)
- [ ] YES/NO — Radial rings: at least one enemy sprays a full ring of bullets.
- [ ] YES/NO — Spiral: at least one enemy sprays a rotating spiral stream.
- [ ] YES/NO — Aimed bursts: at least one enemy fires bursts aimed at the player.

## 3. Bag drop / pickup
- [ ] YES/NO — Kills drop color-tiered bags (brown/pink public seen).
- [ ] YES/NO — Purple+ drops are soulbound (only the earner can pick up).
- [ ] YES/NO — Blue potion bags and white rare bags drop and are pickable.
- [ ] YES/NO — Walking over an eligible bag picks up loot into gear/inventory.
- [ ] YES/NO — No copied RotMG assets/stats: all sprites/names are clean-room.

## 4. XP to fame
- [ ] YES/NO — Kills grant XP; XP bar fills toward level 20.
- [ ] YES/NO — Past level 20, further XP converts to fame (fame counter rises).

## 5. Death to grave
- [ ] YES/NO — Death at 0 HP is permanent: character and carried gear are lost.
- [ ] YES/NO — Earned fame banks to the account on death (persists after death).
- [ ] YES/NO — A grave marker is left behind where the character died.

## 6. HUD right rail
- [ ] YES/NO — Minimap renders in the right rail and tracks the player.
- [ ] YES/NO — HP/MP bars display and update on damage/spell use.
- [ ] YES/NO — XP/fame bar displays and updates on kills.
- [ ] YES/NO — Gear + inventory panels display picked-up items.
- [ ] YES/NO — Potion stacks display remaining F/V counts.

## 7. Nexus escape
- [ ] YES/NO — R instantly escapes to the safe Nexus (no enemies, no damage).
- [ ] YES/NO — Non-goals hold for the slice: single-player only, one class, no
  trading/guilds/pets, no Steamworks.

## Automated gates (run, do not eyeball)
- [ ] YES/NO — `bash scripts/smoke.sh` passes (imports project, main scene runs
  5s, prints `GRAVEBAG ready`, zero script errors).
- [ ] YES/NO — `bash tests/run_all.sh` passes (all `src/**/selftest.gd` PASS,
  or clean "nothing to run" when no selftests exist yet).

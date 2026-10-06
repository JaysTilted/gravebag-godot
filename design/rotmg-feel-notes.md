# RotMG feel notes (harvested from Phaser builders, engine-agnostic)

Authoritative for colors, bindings, and aim rules until playtesting says otherwise.

## Sprite style (textures builder)
- Flat fillRect blocks on coarse grids, dark `#0c0c14` outlines, smoothing off.
- Tier bags brown/pink/purple/blue/white with flat halo, knot, trim band.
- Dense bright enemy shots with white cores vs thin cyan player needle.

## Bindings (controls builder, 14/14 tests green)
- `KeyboardEvent.code` strings + synthetic `MouseLeft` token; remappable table.
- WASD/arrows move; Space = ability; R/F5 = nexus-escape; F/V = potions;
  I = autofire toggle; Digit1-8 = inventory slots.
- `aimDir(player, cursor, facing)`: 8px deadzone holds facing (default up),
  atan2 snapped to 45° with exact 0/±1/±√2/2 cleanup.
- `strafeIntent`: normalized WASD, diagonals stay magnitude 1.

## HUD (hud builder, draft)
- Minimap 176px: player yellow `0xffe500`, foes red `0xff3b4a`,
  tier-colored bags, gate/portal blue `0x3d8bff`, skull quest marker.
- Bars: HP red / MP blue / XP purple `0x8a3dff` flips to fame orange
  `0xff8a1a` at level 20. 4 gear + 8 inventory slots, potion counts,
  monospace uppercase, rectangles/graphics/text only.

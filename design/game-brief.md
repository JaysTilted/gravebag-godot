# GRAVEBAG — game brief (Godot 4.6 cutover)

One moonlit realm. Leave with the bag, or get greedy.

## Pitch
A clean-room Realm of the Mad God-like: cooperative-feel bullet-hell looter,
single-player vertical slice first. WASD move + mouse aim, hold-click / autofire
(I) to shoot toward the cursor, Space ability, R instant escape to the safe
Nexus, F/V potions. Enemies spray radial rings, spirals, aimed bursts.
Kills drop color-tiered bags (brown/pink public, purple+ soulbound, blue
potions, white rare). XP to 20, then fame; death is permanent — lose the
character and carried gear, fame banks to the account, grave left behind.
Right-rail HUD: minimap, HP/MP, XP/fame bar, gear + inventory, potion stacks.

## Non-goals (slice)
Multiplayer, 19 classes (one class first), trading, guilds, pets, Steamworks
integration (comes at release track). No copied assets, code, stats, or music
from any RotMG source — all clean-room. Patterns only.

## Proof
`bash scripts/smoke.sh` passes: headless Godot imports the project, runs the
main scene 5s, prints GRAVEBAG ready, zero script errors.

## Sources (evidence, not assets)
- RotMG look/loop, doom-repo patterns, YouTube feel: prior researcher reports
- Studio framework: `.claude/` (agents, skills, rules, Godot 4.6 engine reference)
- Phaser original: github.com/JaysTilted/gravebag (design reference only)

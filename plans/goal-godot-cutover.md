# Goal: GRAVEBAG Godot cutover — playable RotMG-like slice (clean-room)

## End state
In this repo on `master`, GRAVEBAG is a playable Godot 4.6 game that feels like
RotMG YouTube gameplay: WASD move + mouse aim, hold-click / autofire to shoot,
Space ability, R nexus-escape, F/V potions, radial/spiral/aimed enemy bullets,
color-tiered loot bags on the ground, XP to 20 then fame, permadeath with grave
+ fame tally, right-rail HUD with minimap. Studio pipeline active: design brief
→ epics → stories → dev waves → QA, mapped from `.claude/` onto the Pi fleet.

## Proof
- `bash scripts/smoke.sh` passes (headless import, main scene 5s, ready line, no script errors)

## Working method (adapted from `.claude/`, Claude Code-isms removed)
- Roles per wave: gameplay-programmer, qa-tester,romettere — framed as bounded
  generalist tasks, one writer per worktree, orchestrator integrates.
- Skills used: start (done — existing work), setup-engine (Godot 4.6 pinned),
  create-epics/create-stories (tracked in production/), dev-story/story-done,
  code-review, smoke-check, launch-checklist (release track).
- Rules enforced in task text: GDScript standards from `.claude/rules/`,
  engine API only per `docs/engine-reference/godot/` (model cutoff gap).
- Clean-room: no RotMG assets/code/stats/music. Patterns only.

## Wave plan
1. Player: WASD + mouse aim, autofire, 8-way pixel-art sprite, HP/MP.
2. Enemies + bullets: 3 shot patterns (radial/spiral/aimed), telegraphs, HP.
3. Loot + XP: tiered bags on ground, pickup, XP→20→fame, death→grave+tally.
4. HUD: right rail (minimap, bars, slots, potions), nexus escape.
5. Realm loop: nexus hub → portal → scaling realm → boss → extract.

## Sources
- `design/game-brief.md`; researcher reports (RotMG DNA, doom patterns, YouTube feel)
- Phaser original (reference only): github.com/JaysTilted/gravebag

## Stop
Done when slice plays like the RotMG videos and smoke is green on master,
or Jay says stop.

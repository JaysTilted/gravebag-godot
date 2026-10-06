# Original client numerical facts

Inspected the pinned upstream `client-release.swf` offline, not its artwork. SHA256: `226e61c8ad1e1dab0827e84330aee90794744b4d33cf8db28f4feef0a58b48be`.

Tool: official JPEXS FFDec26.3.0, ZIP SHA256 `35f4930eb7c380afe66f2117f90b006deac0631473ad7500bb39c78f68645ecd`. Tool and decompiled inspection files stay in ignored `build/ffdec/`; neither is shipped.

Facts independently implemented in Godot:

- `GameObject` initializes contact radius0.5 tile. Inspected `Character` inherits it without an override; inspected `Player` has no radius assignment.
- `Projectile` candidate checks compare both absolute tile-axis differences against that radius: square/AABB, not circle. Each sample chooses one nearest eligible target; multihit uses a per-projectile hit collection.
- The original client tests the current projectile point, not a swept segment. Rendering/interpolated positions determine client contact; the C# server still performs damage/credit/death.
- `Player` ground checks use a per-square last-damage timestamp and strict `now > lastDamage +500ms`, protecting objects and immunity. Ground requests never apply local damage.
- `Player` splits movement into dominant-axis steps <=0.4 tile, checking half-cell neighbors for solid geometry.
- Original client's wavy angle amplitude is `PI/64` with fractional seconds and6*PI frequency. The C# server has a different `PI*64`/integer-seconds expression; that server code is unchanged. Frontend projection follows the inspected original client.

Evidence: staged inspection in `build/ffdec/geometry/` and `geometry-extra/`, and scout report `/home/jay/.pi/agent/runs/scout-muwyex26a/evidence/report.md`. No wholesale ActionScript implementation or original textures were copied into the runtime.

Still pending: a complete original client tick/position reconciliation trace, all special subclass geometry, and full GUI coverage. Source backend retention is complete; these are frontend acceptance items, not claims of completed gameplay parity.

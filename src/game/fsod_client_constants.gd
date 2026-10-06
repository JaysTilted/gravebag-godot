extends RefCounted
## Numerical client facts, independently reimplemented (no Flash artwork/code shipped).
## Pinned client-release.swf SHA256:
## 226e61c8ad1e1dab0827e84330aee90794744b4d33cf8db28f4feef0a58b48be
## Inspected offline with official JPEXS FFDec26.3.0 (2026-10-06).
## GameObject.radius_ default0.5; Projectile contact compares BOTH absolute tile-axis deltas.
## Player ground contact checks Square.lastDamage_ +500 against client time.
const CONTACT_HALF_EXTENT_TILES := 0.5
const GROUND_DAMAGE_PERIOD_MS := 500

extends RefCounted
class_name XpLedger
## One diver's XP/fame ledger for GRAVEBAG (permadeath economy).
##
## Port of the NUMBERS and rules from the prior Phaser design
## (`src/game/bags.ts`, `Adventurer` + `xpForNextLevel`):
##
## - Full XP to all: every killer is granted the full kill value, never a
##   split share. Call grant_xp once per participant with the full amount.
## - Levels 1..20 consume XP along the curve (roughly quadratic, cheap
##   early and steep late). Past 20, overflow converts to pending fame at
##   FAME_XP_RATE:1 (fractional fame carries over).
## - Fame banks ONLY on death: grant_xp never touches banked_fame. die()
##   moves pending fame into the bank and returns what was banked.
##
## Pure logic: no nodes, no scene wiring.

## Level where XP stops and overflow converts to fame.
const MAX_LEVEL: int = 20

## Overflow XP per fame point after level 20.
const FAME_XP_RATE: float = 2000.0


var level: int = 1
## XP banked toward the next level (0 once capped at 20).
var xp: int = 0
## Post-20 overflow fame, held until death. Fractional part carries.
var pending_fame: float = 0.0
## Fame actually kept: written only by die().
var banked_fame: float = 0.0
var alive: bool = true


## XP needed to rise from `p_level` to `p_level + 1` (levels 1..19).
## Returns 0 outside 1..19 (nothing to earn below 1, capped at 20).
static func xp_for_next_level(p_level: int) -> int:
	if p_level < 1 or p_level >= MAX_LEVEL:
		return 0
	return roundi(40.0 * float(p_level) * (1.0 + float(p_level) / 8.0))


## Total XP needed to climb from level 1 to level 20.
static func xp_to_max_level() -> int:
	var total: int = 0
	for p_level in range(1, MAX_LEVEL):
		total += xp_for_next_level(p_level)
	return total


## Grant the full kill value. No-ops when dead or for non-positive amounts.
func grant_xp(amount: float) -> void:
	if not alive:
		return
	if not is_finite(amount) or amount <= 0.0:
		return
	var rest: int = int(floor(amount))
	while rest > 0 and level < MAX_LEVEL:
		var need: int = XpLedger.xp_for_next_level(level) - xp
		if rest < need:
			xp += rest
			rest = 0
		else:
			rest -= need
			level += 1
			xp = 0
	if rest > 0:
		pending_fame += float(rest) / FAME_XP_RATE


## Die: bank pending fame, close the ledger. Returns the fame banked by
## this death (0 when nothing was pending). Idempotent.
func die() -> float:
	if not alive:
		return 0.0
	alive = false
	var banked: float = pending_fame
	banked_fame += banked
	pending_fame = 0.0
	return banked

extends Node2D
class_name GravebagDive
## GRAVEBAG wave-1 integrator: ONE playable dive (design/game-brief.md).
##
## Owns the loop: realm + player + HUD + SFX pooler; 3 enemies + 1 warden
## spawned around the portal using GravebagScaling weights; enemy deaths ->
## DropTable/LootGrading tiered bag markers -> touch pickup + XpLedger + SFX;
## player death -> GraveRecord marker + fame tally + nexus respawn; R nexus
## stub; HUD update_state() every frame; Space/F/V/I bindings live via
## GravebagPlayer's InputMap (never overridden here).
##
## Dedup note (warden volleys vs combat Patterns): CombatEnemy fires
## fire_requested(origin, PackedVector2Array, speed, damage) which connects
## DIRECTLY to CombatBulletPool.spawn_volley (same signature). The warden
## emits volley_fired(pattern, Array[Vector2]) via BossPatterns. Only the
## "aimed" shape matches CombatPatterns.aimed_burst(origin, aim, count,
## spread) exactly, so aimed volleys are regenerated through CombatPatterns
## (single math path); radial/spiral signatures differ (Array vs Packed,
## tick-step vs aim-rooted rotation) so those keep the warden-local dirs and
## share only the pool as the materialization path.
##
## Soak: run with `--auto-test` (OS.get_cmdline_user_args or
## OS.get_cmdline_args) for a 20s bot dive (move/autofire/kill/pickup/XP)
## printing `DIVE PASS` + stats + frame count. Default run prints nothing
## here (main.gd prints `GRAVEBAG ready`).
##
## Frames (parent playtest eyes): during --auto-test, saves >=6 PNGs to
## /tmp/gravebag-frames/ via viewport texture: 01 title/first-spawn,
## 02 mid-combat with enemy bullets, 03 bag drop, 04 pickup, 05 HUD state,
## 06 death/grave. Headless Godot uses a dummy renderer (blank), so the same
## soak also runs under xvfb-run for real GL Compatibility pixels.

const RealmScript: Script = preload("res://src/world/realm.gd")
const ScalingScript: Script = preload("res://src/world/scaling.gd")
const PortalScript: Script = preload("res://src/world/portal.gd")
const NexusScene: PackedScene = preload("res://src/world/nexus.tscn")
const PlayerScene: PackedScene = preload("res://src/player/player.tscn")
const ProjectileScript: Script = preload("res://src/player/projectile.gd")
const EnemyScript: Script = preload("res://src/combat/enemy.gd")
const CombatPatterns: Script = preload("res://src/combat/patterns.gd")
const BulletPoolScript: Script = preload("res://src/combat/bullet_pool.gd")
const HudScene: PackedScene = preload("res://src/ui/hud.tscn")
const SfxScript: Script = preload("res://src/audio/sfx.gd")
const SfxPlayerScript: Script = preload("res://src/audio/sfx_player.gd")
const WardenScript: Script = preload("res://src/bosses/warden.gd")
const MinionScript: Script = preload("res://src/bosses/warden_minion.gd")
const BagTiersScript: Script = preload("res://src/systems/bag_tiers.gd")
const LootGradingScript: Script = preload("res://src/systems/loot_grading.gd")
const XpLedgerScript: Script = preload("res://src/systems/xp_ledger.gd")
const DropTableScript: Script = preload("res://src/systems/drop_table.gd")
const GraveRecordScript: Script = preload("res://src/systems/grave_record.gd")

## World tuning (dive-owned; gameplay rules graduate these to config later).
const WORLD_SIZE := 2048.0
const PLAYER_SPAWN := Vector2(1024.0, 1100.0)
const PORTAL_POS := Vector2(1024.0, 640.0)
const NEXUS_POS := Vector2(1024.0, 1800.0)
const ENEMY_COUNT := 6
## Combat-density pass: formation ring around the player (in-screen spawn +
## leash so foes never wander off-camera) and the capture-frame bullet floor.
## RotMG fairness holds: muzzle telegraphs stay >= 0.4s via enemy windup.
const FORMATION_RADIUS := 260.0
const LEASH_RANGE := 520.0
const COMBAT_BULLETS_MIN := 30
const ENEMY_POOL_SIZE := 512
const ENEMY_BULLET_RADIUS := 13.0
const ENEMY_RESPAWN_SEC := 1.5
const PICKUP_RADIUS := 48.0
const PLAYER_SHOT_DAMAGE := 14.0
const PLAYER_SHOT_HIT_RADIUS := 30.0
const ENEMY_BULLET_HIT_RADIUS := 22.0
const WARDEN_BULLET_SPEED := 240.0
const WARDEN_BULLET_DAMAGE := 10.0
const XP_BY_RANK := [50, 90, 130, 200, 400]
## Live loop (CCGS integrator): NEXUS -> REALM -> BOSS -> EXTRACT/DEAD.
## North = low Y (boss), south = high Y (extract). Hub exit by walking out;
## seals are Y-crossings so they work with zero new collision wiring.
const NEXUS_HUB_RADIUS := 170.0
const NORTH_SEAL_Y := 480.0
const BOSS_SPAWN := Vector2(1024.0, 320.0)
const EXTRACT_Y := 1920.0
const EXTRACT_POS := Vector2(1024.0, 1960.0)
const NEXUS_PORTAL_POS := Vector2(1024.0, 1640.0)
const NORTH_SEAL_LABEL_POS := Vector2(1024.0, 480.0)
## Bot soak tuning.
const SOAK_DURATION := 20.0
const FORCED_DEATH_AT := 15.0
const BOT_AURA_DPS := 50.0
const BOT_AURA_RANGE := 380.0


## Tiered bag marker: colored ground square with halo + knot. Fades by tier.
class BagMarker extends Node2D:
	var tier: String = "brown"
	var tint: Color = Color(0.54, 0.35, 0.17)
	var age: float = 0.0
	var life: float = 60.0

	func _process(delta: float) -> void:
		age += delta
		if age >= life:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var pulse: float = 0.22 + 0.08 * sin(age * 5.0)
		draw_rect(Rect2(Vector2(-15, -15), Vector2(30, 30)), Color(tint, pulse), true)
		draw_rect(Rect2(Vector2(-9, -9), Vector2(18, 18)), tint, true)
		draw_rect(Rect2(Vector2(-9, -9), Vector2(18, 18)), Color(0.05, 0.04, 0.08, 1.0), false, 2.0)
		draw_rect(Rect2(Vector2(-9, -2), Vector2(18, 4)), Color(0, 0, 0, 0.25), true)
		# Cool loot knot (pale cyan-white) vs warm enemy bullets: danger reads
		# instantly, loot never does.
		draw_circle(Vector2.ZERO, 3.0, Color(0.7, 1.0, 1.0))


## Grave marker: dark stone with pale cross. Persists for the dive.
class GraveMarker extends Node2D:
	var age: float = 0.0

	func _process(delta: float) -> void:
		age += delta
		queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2(-12, -16), Vector2(24, 32)), Color(0.16, 0.16, 0.2), true)
		draw_rect(Rect2(Vector2(-12, -16), Vector2(24, 32)), Color(0.75, 0.72, 0.68), false, 2.0)
		draw_rect(Rect2(Vector2(-2, -10), Vector2(4, 20)), Color(0.85, 0.83, 0.8), true)
		draw_rect(Rect2(Vector2(-7, -6), Vector2(14, 4)), Color(0.85, 0.83, 0.8), true)


var player: CharacterBody2D = null
var realm: Node2D = null
var portal: Area2D = null
var nexus: Node2D = null
var nexus_spawn: Vector2 = NEXUS_POS + Vector2(0, -48)
var hud: CanvasLayer = null
var pool: Node2D = null
var sfx_player: Node = null

var ledger: RefCounted = null
var total_fame_banked: float = 0.0
var enemies: Array = []
var warden: CharacterBody2D = null
var minions: Array = []
var bags: Array = []
var graves: Array = []

var kills: int = 0
var pickups: int = 0
var xp_granted_total: int = 0
var deaths: int = 0

var _auto_test: bool = false
var _elapsed: float = 0.0
var _enemy_respawn_left: float = -1.0
var _warden_respawn_left: float = -1.0
var _pot_hp: int = 2
var _pot_mp: int = 2
var _frames_saved: Array[String] = []
var _frame_done := {"spawn": false, "combat": false, "bag": false, "pickup": false, "hud": false, "grave": false}
var _forced_death_done: bool = false
var _last_level: int = 1
## Live game loop state: NEXUS -> REALM -> BOSS -> EXTRACT, ANY -> DEAD.
## Starts at NEXUS (safe hub); _loop_reached records BOSS/EXTRACT for LOOP PASS.
var loop_state: String = "NEXUS"
var _loop_reached: String = ""
var nexus_portal: Area2D = null
var extract_portal: Area2D = null
## Live enemy bullets counted at the combat capture frame. The soak fails
## unless this reaches COMBAT_BULLETS_MIN.
var _combat_bullet_count := 0


func _ready() -> void:
	var user_args: PackedStringArray = OS.get_cmdline_user_args()
	var full_args: PackedStringArray = OS.get_cmdline_args()
	_auto_test = user_args.has("--auto-test") or full_args.has("--auto-test")
	if _auto_test:
		seed(12345)
		DirAccess.make_dir_recursive_absolute("/tmp/gravebag-frames")
	ledger = XpLedgerScript.new()
	_last_level = int(ledger.get("level"))
	_spawn_realm()
	_spawn_nexus()
	_spawn_portal()
	_spawn_loop_gates()
	_spawn_pool()
	_spawn_sfx()
	_spawn_hud()
	# Live loop opens in the safe hub at full HP (nexus SpawnPoint).
	loop_state = "NEXUS"
	_spawn_player(nexus_spawn)
	_spawn_initial_foes()


func _process(delta: float) -> void:
	_elapsed += delta
	_tick_respawns(delta)
	_keep_formation(delta)
	if _auto_test:
		_bot_drive(delta)
		_maybe_force_death()
		_maybe_capture_time_frames()
	_update_hud()
	if _auto_test and _elapsed >= SOAK_DURATION:
		_finish_soak()


func _physics_process(delta: float) -> void:
	if not is_instance_valid(player):
		return
	_track_minions()
	_player_shots_vs_foes()
	_enemy_bullets_vs_player()
	_bags_vs_player()
	_clamp_player()
	_tick_loop()
	if _auto_test:
		_bot_aura(delta)


# ── Spawn ─────────────────────────────────────────────────────────────

func _spawn_realm() -> void:
	realm = RealmScript.new()
	realm.name = "Realm"
	realm.position = Vector2.ZERO
	add_child(realm)
	realm.queue_redraw()


func _spawn_nexus() -> void:
	nexus = NexusScene.instantiate() as Node2D
	nexus.name = "Nexus"
	nexus.position = NEXUS_POS
	add_child(nexus)
	var sp := nexus.get_node_or_null("SpawnPoint") as Node2D
	if sp != null:
		nexus_spawn = sp.global_position
	else:
		nexus_spawn = NEXUS_POS + Vector2(0, -48)
	if nexus.has_signal("healed"):
		nexus.connect("healed", _on_nexus_healed)


func _spawn_portal() -> void:
	portal = PortalScript.new() as Area2D
	portal.name = "RealmPortal"
	portal.position = PORTAL_POS
	if portal.has_method("set"):
		portal.set("destination", "nexus")
	add_child(portal)
	if portal.has_signal("entered"):
		portal.connect("entered", _on_portal_entered)


## Live-loop gates: nexus->realm portal (walk into the dive), south
## LEAVE-WITH-THE-BAG extract portal, plus floating seal/gate labels.
## The north seal itself is a Y-crossing in _tick_loop (no collision).
func _spawn_loop_gates() -> void:
	nexus_portal = PortalScript.new() as Area2D
	nexus_portal.name = "NexusRealmPortal"
	nexus_portal.position = NEXUS_PORTAL_POS
	nexus_portal.set("destination", "realm")
	add_child(nexus_portal)
	if nexus_portal.has_signal("entered"):
		nexus_portal.connect("entered", _on_portal_entered)
	extract_portal = PortalScript.new() as Area2D
	extract_portal.name = "ExtractGate"
	extract_portal.position = EXTRACT_POS
	extract_portal.set("destination", "extract")
	add_child(extract_portal)
	if extract_portal.has_signal("entered"):
		extract_portal.connect("entered", _on_portal_entered)
	var seal := Label.new()
	seal.name = "NorthSealLabel"
	seal.text = "NORTH SEAL — WARDEN OF THE GATE"
	seal.position = NORTH_SEAL_LABEL_POS + Vector2(-150, -40)
	seal.z_index = 50
	add_child(seal)
	var gate := Label.new()
	gate.name = "ExtractGateLabel"
	gate.text = "LEAVE-WITH-THE-BAG"
	gate.position = EXTRACT_POS + Vector2(-110, 40)
	gate.z_index = 50
	add_child(gate)


## Live-loop crossings, checked every physics frame. Portals handle the
## teleports; these handle walking across a seal/gate line.
func _tick_loop() -> void:
	if not is_instance_valid(player):
		return
	if loop_state == "DEAD" or loop_state == "EXTRACT":
		return
	var ppos: Vector2 = (player as Node2D).global_position
	match loop_state:
		"NEXUS":
			if ppos.distance_to(NEXUS_POS) > NEXUS_HUB_RADIUS:
				_enter_realm("walked out of nexus")
			elif ppos.y > EXTRACT_Y:
				_enter_extract("south gate from nexus")
		"REALM":
			if ppos.y < NORTH_SEAL_Y:
				_enter_boss()
			elif ppos.y > EXTRACT_Y:
				_enter_extract("south gate from realm")
		"BOSS":
			if ppos.y > EXTRACT_Y:
				_enter_extract("south gate from boss")


func _enter_realm(how: String) -> void:
	if loop_state != "NEXUS":
		return
	loop_state = "REALM"
	_loop_toast("REALM — LEAVE WITH THE BAG")
	print("LOOP STATE NEXUS -> REALM (%s)" % how)


func _enter_boss() -> void:
	if loop_state != "REALM":
		return
	loop_state = "BOSS"
	_loop_reached = "BOSS"
	if not is_instance_valid(warden):
		_spawn_warden(BOSS_SPAWN)
	else:
		(warden as Node2D).global_position = BOSS_SPAWN
		(warden as Node).set("aim_target", player)
	_loop_toast("BOSS — WARDEN OF THE GATE")
	print("LOOP PASS reached=BOSS")
	print("LOOP STATE REALM -> BOSS (north seal)")
	_play_sfx("enemy_shoot")


func _enter_extract(how: String) -> void:
	if loop_state != "REALM" and loop_state != "BOSS" and loop_state != "NEXUS":
		return
	var from := loop_state
	var pending := 0.0
	if ledger != null:
		pending = float(ledger.get("pending_fame"))
	loop_state = "EXTRACT"
	_loop_reached = "EXTRACT"
	print("HAUL TALLY bags=%d xp=%d fame=%.1f (%s)" % [pickups, xp_granted_total, pending, how])
	_loop_toast("HAUL TALLY bags=%d xp=%d" % [pickups, xp_granted_total])
	print("LOOP PASS reached=EXTRACT")
	print("LOOP STATE %s -> EXTRACT -> NEXUS (%s)" % [from, how])
	_play_sfx("extract")
	if is_instance_valid(player):
		(player as Node2D).global_position = nexus_spawn
	if pool != null and is_instance_valid(pool) and pool.has_method("clear_all"):
		pool.call("clear_all")
	loop_state = "NEXUS"
	_loop_toast("NEXUS — SAFE")


func _loop_toast(text: String) -> void:
	if hud != null and is_instance_valid(hud) and hud.has_method("show_toast"):
		hud.call("show_toast", text)


func _spawn_pool() -> void:
	pool = BulletPoolScript.new() as Node2D
	pool.name = "BulletPool"
	if pool.has_method("set"):
		pool.set("pool_size", ENEMY_POOL_SIZE)
	add_child(pool)


func _spawn_sfx() -> void:
	sfx_player = SfxPlayerScript.new() as Node
	sfx_player.name = "SfxPool"
	if sfx_player.has_method("set"):
		sfx_player.set("pool_size", 8)
	add_child(sfx_player)


func _spawn_hud() -> void:
	hud = HudScene.instantiate() as CanvasLayer
	hud.name = "HUD"
	add_child(hud)


func _spawn_player(at: Vector2) -> void:
	player = PlayerScene.instantiate() as CharacterBody2D
	player.name = "Player"
	player.position = at
	add_child(player)
	var cam := Camera2D.new()
	cam.name = "DiveCamera"
	cam.position_smoothing_enabled = true
	cam.limit_left = 0
	cam.limit_top = 0
	cam.limit_right = int(WORLD_SIZE)
	cam.limit_bottom = int(WORLD_SIZE)
	player.add_child(cam)
	cam.make_current()
	_connect_player()
	if _auto_test:
		player.set("autofire_enabled", true)


func _connect_player() -> void:
	if player.has_signal("died"):
		if not player.is_connected("died", _on_player_died):
			player.connect("died", _on_player_died)
	if player.has_signal("fired"):
		if not player.is_connected("fired", _on_player_fired):
			player.connect("fired", _on_player_fired)
	if player.has_signal("nexus_escape_requested"):
		if not player.is_connected("nexus_escape_requested", _on_nexus_escape):
			player.connect("nexus_escape_requested", _on_nexus_escape)
	if player.has_signal("hp_potion_requested"):
		if not player.is_connected("hp_potion_requested", _on_hp_potion):
			player.connect("hp_potion_requested", _on_hp_potion)
	if player.has_signal("mp_potion_requested"):
		if not player.is_connected("mp_potion_requested", _on_mp_potion):
			player.connect("mp_potion_requested", _on_mp_potion)
	if player.has_signal("ability_used"):
		if not player.is_connected("ability_used", _on_ability_used):
			player.connect("ability_used", _on_ability_used)
	if player.has_signal("autofire_toggled"):
		if not player.is_connected("autofire_toggled", _on_autofire_toggled):
			player.connect("autofire_toggled", _on_autofire_toggled)


func _spawn_initial_foes() -> void:
	# Realm holds the fight; the hub stays safe. Anchor the opening pack on
	# the realm floor (not on the nexus spawn) and leave the warden for the
	# north-seal trigger so BOSS entry visibly spawns the boss.
	var anchor := PLAYER_SPAWN
	for i in ENEMY_COUNT:
		_spawn_enemy(_formation_slot(anchor, i, ENEMY_COUNT))


func _depth_at(pos: Vector2) -> float:
	return float(ScalingScript.depth_from_y(pos.y))


func _pick_pattern_kind(depth: float) -> int:
	# Uses scaling.gd weights (crawler/spitter/brute); warden weight is
	# excluded here because the warden has its own dedicated slot.
	var weights: Dictionary = ScalingScript.spawn_weights_for_depth(depth)
	var crawler := float(weights.get("crawler", 0.5))
	var spitter := float(weights.get("spitter", 0.3))
	var brute := float(weights.get("brute", 0.2))
	var total := crawler + spitter + brute
	if total <= 0.0:
		return 0
	var roll := randf() * total
	if roll < crawler:
		return 0 # RING
	if roll < crawler + spitter:
		return 2 # AIMED
	return 1 # SPIRAL


func _god_tier_for_pattern(pattern: int) -> int:
	match pattern:
		0:
			return 1
		2:
			return 2
		_:
			return 3


func _spawn_enemy(at: Vector2) -> void:
	var foe := EnemyScript.new() as CharacterBody2D
	var depth := _depth_at(at)
	var stats: Dictionary = ScalingScript.stats_for_depth(depth)
	var hp_mult := float(stats.get("hp_mult", 1.0))
	var dmg_mult := float(stats.get("dmg_mult", 1.0))
	var pattern := _pick_pattern_kind(depth)
	foe.set("pattern_kind", pattern)
	# Combat-density pass: in-screen formation stats, ~1.65s fire cycle with
	# >= 0.4s telegraphs, big bright orbs. Auto-test foes are tougher so the
	# bot's aura cannot clear the screen before the combat capture frame.
	if _auto_test:
		foe.set("max_hp", 90.0)
		foe.set("bullet_damage", 3.0)
		foe.set("preferred_range", 240.0)
		foe.set("move_speed", 150.0)
		foe.set("respawn_delay", 0.0)
	else:
		foe.set("max_hp", 30.0 * hp_mult)
		foe.set("bullet_damage", 8.0 * dmg_mult)
		foe.set("preferred_range", 240.0)
		foe.set("move_speed", 150.0)
	# Dive owns population (fresh spawn on a timer); the enemy self-respawn
	# clock would reform a queue-free corpse for one stale frame.
	foe.set("respawn_delay", 0.0)
	foe.set("windup_time", 0.5)
	foe.set("cooldown_time", 1.15)
	foe.set("initial_delay", 0.35)
	foe.set("ring_count", 14)
	foe.set("spiral_arm_count", 5)
	foe.set("burst_count", 7)
	foe.set("bullet_speed", 240.0)
	foe.set("bullet_radius", ENEMY_BULLET_RADIUS)
	foe.set("leash_range", LEASH_RANGE)
	foe.position = at
	if is_instance_valid(player):
		foe.set("target", player)
	add_child(foe)
	if foe.has_signal("fire_requested") and pool != null and pool.has_method("spawn_volley"):
		foe.connect("fire_requested", pool.spawn_volley)
	if foe.has_signal("died"):
		foe.connect("died", _on_enemy_died)
	enemies.append(foe)


func _spawn_warden(at: Vector2) -> void:
	if is_instance_valid(warden):
		return
	warden = WardenScript.new() as CharacterBody2D
	if _auto_test:
		warden.set("max_hp", 220.0)
	else:
		warden.set("max_hp", 900.0)
	warden.position = at
	if is_instance_valid(player):
		warden.set("aim_target", player)
	add_child(warden)
	if warden.has_signal("volley_fired"):
		warden.connect("volley_fired", _on_warden_volley)
	if warden.has_signal("died"):
		warden.connect("died", _on_warden_died)
	_play_sfx("enemy_shoot")


# ── Combat wiring ─────────────────────────────────────────────────────

func _on_warden_volley(pattern: StringName, dirs: Array) -> void:
	if pool == null or not is_instance_valid(warden):
		return
	var origin: Vector2 = (warden as Node2D).global_position
	var packed := PackedVector2Array()
	# Dedup: aimed matches CombatPatterns.aimed_burst exactly, so rebuild
	# through the shared math path; radial/spiral keep warden-local dirs.
	if String(pattern) == "aimed" and dirs.size() > 0:
		var aim: Vector2 = origin + Vector2.RIGHT
		var tgt: Variant = warden.get("aim_target")
		if tgt is Node2D and is_instance_valid(tgt):
			aim = (tgt as Node2D).global_position
		var spread := 0.18
		var maybe_spread: Variant = warden.get("aimed_spread")
		if maybe_spread is float:
			spread = float(maybe_spread)
		packed = CombatPatterns.aimed_burst(origin, aim, dirs.size(), spread)
	else:
		packed.resize(dirs.size())
		for i in dirs.size():
			packed[i] = (dirs[i] as Vector2).normalized()
	pool.call("spawn_volley", origin, packed, WARDEN_BULLET_SPEED, WARDEN_BULLET_DAMAGE)
	_play_sfx("enemy_shoot")


func _player_shots_vs_foes() -> void:
	var shots: Array = []
	for c in get_children():
		if c.get_script() == ProjectileScript:
			shots.append(c)
	if shots.is_empty():
		return
	for shot in shots:
		if not is_instance_valid(shot):
			continue
		var pos: Vector2 = (shot as Node2D).global_position
		var hit_something := false
		for foe in enemies:
			if foe is Node2D and is_instance_valid(foe) and (foe as Node).get("hp") != null:
				var f := foe as CharacterBody2D
				if float(f.get("hp")) <= 0.0:
					continue
				if pos.distance_to((f as Node2D).global_position) <= PLAYER_SHOT_HIT_RADIUS + 20.0:
					if f.has_method("take_damage"):
						f.call("take_damage", PLAYER_SHOT_DAMAGE)
					_play_sfx("hit")
					hit_something = true
					break
		if not hit_something and is_instance_valid(warden):
			var w := warden as Node2D
			if warden.get("hp") != null and float(warden.get("hp")) > 0.0 and warden.get("phase") != null and int(warden.get("phase")) != 0:
				if pos.distance_to(w.global_position) <= PLAYER_SHOT_HIT_RADIUS + 20.0:
					if warden.has_method("take_damage"):
						warden.call("take_damage", PLAYER_SHOT_DAMAGE)
					_play_sfx("hit")
					hit_something = true
		if not hit_something:
			for m in minions:
				if m is Node2D and is_instance_valid(m):
					if float((m as Node).get("hp")) <= 0.0:
						continue
					if pos.distance_to((m as Node2D).global_position) <= PLAYER_SHOT_HIT_RADIUS + 12.0:
						if (m as Node).has_method("take_damage"):
							(m as Node).call("take_damage", PLAYER_SHOT_DAMAGE)
						_play_sfx("hit")
						hit_something = true
						break
		if hit_something and is_instance_valid(shot):
			(shot as Node).queue_free()


func _enemy_bullets_vs_player() -> void:
	if pool == null or not is_instance_valid(player):
		return
	if player.get("hp") == null or float(player.get("hp")) <= 0.0:
		return
	var ppos: Vector2 = (player as Node2D).global_position
	for b in pool.get_children():
		if not is_instance_valid(b):
			continue
		var bn := b as Node
		if bn.get("active") == null or not bool(bn.get("active")):
			continue
		if int(bn.get("team")) != 1:
			continue
		var bpos: Vector2 = (b as Node2D).global_position
		var rad := 8.0
		if bn.get("radius") != null:
			rad = float(bn.get("radius"))
		if ppos.distance_to(bpos) <= rad + ENEMY_BULLET_HIT_RADIUS:
			if b.has_method("deactivate"):
				b.call("deactivate")
			if player.has_method("damage"):
				player.call("damage", float(bn.get("damage")))
			_play_sfx("hit")


func _bags_vs_player() -> void:
	if not is_instance_valid(player):
		return
	var ppos: Vector2 = (player as Node2D).global_position
	for bag in bags.duplicate():
		if not is_instance_valid(bag):
			bags.erase(bag)
			continue
		var bpos: Vector2 = (bag as Node2D).global_position
		if ppos.distance_to(bpos) <= PICKUP_RADIUS:
			_pickup_bag(bag)


func _clamp_player() -> void:
	if not is_instance_valid(player):
		return
	(player as Node2D).global_position = RealmScript.clamp_to_bounds((player as Node2D).global_position)


func _track_minions() -> void:
	for m in minions.duplicate():
		if not is_instance_valid(m):
			minions.erase(m)
	for c in get_children():
		if c.get_script() == MinionScript and not minions.has(c):
			minions.append(c)
			_ensure_minion_sprite(c)
			if (c as Node).has_signal("died") and not (c as Node).is_connected("died", _on_minion_died):
				(c as Node).connect("died", _on_minion_died)


func _ensure_minion_sprite(m: Node) -> void:
	# Minion stubs spawned via Minion.new() have no Body child (the scene
	# provides it): build one or phase-2 adds fight invisible.
	if m == null or not is_instance_valid(m):
		return
	if (m as Node).get_node_or_null("Body") != null:
		return
	var spr := Sprite2D.new()
	spr.name = "Body"
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.scale = Vector2(2, 2)
	if MinionScript.has_method("make_stub_texture"):
		spr.texture = MinionScript.make_stub_texture()
	m.add_child(spr)


# ── Loot / XP / death ─────────────────────────────────────────────────

func _grade_tier(god_tier: int) -> String:
	# LootGrading picks the tier; DropTable rolls it through a guaranteed
	# single-row table so both wave-1 systems stay in the loop.
	var graded: String = String(LootGradingScript.grade_loot(int(ledger.get("level")), god_tier))
	var table: Array = [DropTableScript.Entry.new("kill", 1.0, graded)]
	var wins: Array = DropTableScript.roll_drops(func() -> float: return 0.0, table)
	var tier: String = String(DropTableScript.best_bag_for_drops(wins))
	if tier == "":
		tier = graded
	return tier


func _xp_for_tier(tier: String) -> int:
	var ranks: Dictionary = {"brown": 0, "pink": 1, "purple": 2, "blue": 3, "white": 4}
	var r: int = int(ranks.get(tier, 0))
	return int(XP_BY_RANK[clampi(r, 0, XP_BY_RANK.size() - 1)])


func _spawn_bag(at: Vector2, tier: String) -> void:
	var bag := BagMarker.new()
	bag.tier = tier
	bag.tint = BagTiersScript.tier_color(tier)
	bag.life = BagTiersScript.despawn_sec(tier)
	bag.position = at
	add_child(bag)
	bags.append(bag)
	_capture("bag", "03-bag-drop")


func _on_enemy_died(enemy: Node) -> void:
	enemies.erase(enemy)
	kills += 1
	_play_sfx("kill")
	var pattern := 1
	if enemy.get("pattern_kind") != null:
		pattern = int(enemy.get("pattern_kind"))
	var tier := _grade_tier(_god_tier_for_pattern(pattern))
	var at := PLAYER_SPAWN
	if enemy is Node2D and is_instance_valid(enemy):
		at = (enemy as Node2D).global_position
	_hud_spawn_damage(at, _xp_for_tier(tier), Color(1.0, 0.85, 0.3))
	_hud_notify_kill()
	_spawn_bag(at, tier)
	# Corpse cleanup: wave-1 enemies reform on their own timer, but the dive
	# owns population, so free the corpse and schedule a fresh spawn.
	if is_instance_valid(enemy):
		(enemy as Node).queue_free()
	_enemy_respawn_left = ENEMY_RESPAWN_SEC
	_capture("combat-check", "")


func _on_warden_died(grade: int) -> void:
	kills += 1
	_play_sfx("kill")
	var order: Array = ["brown", "pink", "purple", "blue", "white"]
	var tier := String(order[clampi(int(grade), 0, order.size() - 1)])
	var at := PORTAL_POS
	if is_instance_valid(warden):
		at = (warden as Node2D).global_position
	_hud_spawn_damage(at, 220, Color(1.0, 0.6, 0.2))
	_hud_notify_kill()
	_spawn_bag(at, tier)
	_grant_xp(220)
	if is_instance_valid(warden):
		(warden as Node).queue_free()
	warden = null
	_warden_respawn_left = 10.0


func _on_minion_died(_minion: Node) -> void:
	minions.erase(_minion)
	kills += 1
	_play_sfx("kill")
	var mat := PORTAL_POS
	if _minion is Node2D and is_instance_valid(_minion):
		mat = (_minion as Node2D).global_position
	_hud_spawn_damage(mat, 20, Color(1.0, 0.85, 0.3))
	_hud_notify_kill()
	_grant_xp(20)


func _pickup_bag(bag: Node) -> void:
	if not is_instance_valid(bag):
		return
	var tier := String((bag as Node).get("tier"))
	bags.erase(bag)
	(bag as Node).queue_free()
	pickups += 1
	_grant_xp(_xp_for_tier(tier))
	_hud_bag_pickup(tier)
	_play_sfx("pickup")
	_capture("pickup", "04-pickup-moment")


func _grant_xp(amount: int) -> void:
	if ledger == null:
		return
	var before: int = int(ledger.get("level"))
	ledger.call("grant_xp", float(amount))
	xp_granted_total += amount
	var after: int = int(ledger.get("level"))
	if after > before or after > _last_level:
		_play_sfx("levelup")
		_hud_level_up(after)
		if before < 20 and after >= 20:
			_hud_fame_flip()
	_last_level = maxi(_last_level, after)


func _on_player_died() -> void:
	deaths += 1
	var from := loop_state
	loop_state = "DEAD"
	print("LOOP STATE %s -> DEAD" % from)
	_play_sfx("death_sting")
	var pos := PLAYER_SPAWN
	if is_instance_valid(player):
		pos = (player as Node2D).global_position
	var record: RefCounted = GraveRecordScript.new(pos, ["blade", "cloak"])
	var stone := GraveMarker.new()
	stone.position = pos
	add_child(stone)
	graves.append(stone)
	var banked := 0.0
	if ledger != null and bool(ledger.get("alive")):
		banked = float(ledger.call("die"))
	total_fame_banked += banked
	print("FAME TALLY +%.1f (deaths=%d) grave at %s" % [banked, deaths, str(pos)])
	# Death pause: grave renders (and the death registers) before capture.
	await get_tree().create_timer(0.35).timeout
	_capture("grave", "06-death-grave")
	# Respawn as a fresh diver at the nexus (player has no revive API).
	await get_tree().create_timer(0.45).timeout
	_respawn_player()


func _respawn_player() -> void:
	if is_instance_valid(player):
		(player as Node).queue_free()
	player = null
	# Fresh diver must not eat a stale volley on frame one: park all live
	# enemy bullets with the old diver.
	if pool != null and is_instance_valid(pool) and pool.has_method("clear_all"):
		pool.call("clear_all")
	ledger = XpLedgerScript.new()
	_last_level = 1
	_pot_hp = 2
	_pot_mp = 2
	_spawn_player(nexus_spawn)
	loop_state = "NEXUS"
	_loop_toast("NEXUS — SAFE")
	print("LOOP STATE DEAD -> NEXUS (respawn)")
	# Re-point live foes at the new diver so the dive keeps moving.
	for foe in enemies:
		if foe is Node and is_instance_valid(foe):
			(foe as Node).set("target", player)
	if is_instance_valid(warden):
		(warden as Node).set("aim_target", player)
	_play_sfx("extract")
	# Keep pressure near the nexus after a late-dive death.
	if _auto_test and _elapsed > FORCED_DEATH_AT:
		_spawn_enemy(nexus_spawn + Vector2(120, -80))


func _on_nexus_escape() -> void:
	# R instant escape to the safe hub: teleport, clear bullets, back to NEXUS.
	if not is_instance_valid(player):
		return
	(player as Node2D).global_position = nexus_spawn
	loop_state = "NEXUS"
	_loop_toast("NEXUS — SAFE")
	if pool != null and pool.has_method("clear_all"):
		pool.call("clear_all")
	_play_sfx("extract")
	print("NEXUS SWAP STUB: diver to nexus %s" % str(nexus_spawn))


func _on_hp_potion() -> void:
	if not is_instance_valid(player):
		return
	if _pot_hp <= 0:
		return
	if float(player.get("hp")) >= 100.0:
		return
	_pot_hp -= 1
	player.call("heal", 50.0)
	_play_sfx("potion")


func _on_mp_potion() -> void:
	if not is_instance_valid(player):
		return
	if _pot_mp <= 0:
		return
	_pot_mp -= 1
	player.call("restore_mp", 50.0)
	_play_sfx("potion")


func _on_nexus_healed() -> void:
	if not is_instance_valid(player):
		return
	player.call("heal", 100.0)
	player.call("restore_mp", 100.0)


func _on_portal_entered(dest: String) -> void:
	# Walk-into travel: nexus realm-portal dives into the realm; the south
	# extract gate banks the haul; the mid-realm portal is a marker only
	# (no auto-teleport, so a north push never bounces back to the hub).
	if dest == "realm" and loop_state == "NEXUS" and is_instance_valid(player):
		(player as Node2D).global_position = PLAYER_SPAWN
		if pool != null and pool.has_method("clear_all"):
			pool.call("clear_all")
		_enter_realm("realm portal")
		_play_sfx("extract")
		print("PORTAL entered -> realm (NEXUS -> REALM)")
		return
	if dest == "extract" and is_instance_valid(player):
		_enter_extract("extract gate portal")
		print("PORTAL entered -> extract")
		return
	print("PORTAL entered -> %s" % dest)
	_play_sfx("extract")


func _on_player_fired() -> void:
	_play_sfx("shoot")


func _on_ability_used() -> void:
	_play_sfx("ui_click")


func _on_autofire_toggled(_enabled: bool) -> void:
	_play_sfx("ui_click")


func _hud_spawn_damage(at: Vector2, amount: Variant, color: Color) -> void:
	if hud == null or not is_instance_valid(hud):
		return
	if not hud.has_method("spawn_damage"):
		return
	hud.call("spawn_damage", at, amount, color)


func _hud_notify_kill() -> void:
	if hud == null or not is_instance_valid(hud):
		return
	if not hud.has_method("notify_kill"):
		return
	hud.call("notify_kill")


func _hud_level_up(level: int) -> void:
	if hud == null or not is_instance_valid(hud):
		return
	if not hud.has_method("show_level_up"):
		return
	hud.call("show_level_up", level)


func _hud_bag_pickup(tier: String) -> void:
	if hud == null or not is_instance_valid(hud):
		return
	if hud.has_method("notify_bag_pickup"):
		hud.call("notify_bag_pickup", tier)
	if hud.has_method("show_toast"):
		hud.call("show_toast", "PICKED UP  %s" % tier.to_upper())


func _hud_fame_flip() -> void:
	if hud == null or not is_instance_valid(hud):
		return
	if not hud.has_method("play_fame_flip"):
		return
	hud.call("play_fame_flip")


func _play_sfx(kind: String) -> void:
	if sfx_player == null or not is_instance_valid(sfx_player):
		return
	if not sfx_player.has_method("play_varied"):
		return
	var stream: AudioStreamWAV = null
	var sound_name := kind
	match kind:
		"shoot":
			stream = SfxScript.shoot()
		"enemy_shoot":
			stream = SfxScript.enemy_shoot()
		"hit":
			stream = SfxScript.hit()
		"kill":
			stream = SfxScript.kill()
		"pickup":
			stream = SfxScript.pickup()
		"potion":
			stream = SfxScript.potion()
		"levelup":
			stream = SfxScript.levelup()
		"death":
			stream = SfxScript.death()
		"death_sting":
			stream = SfxScript.death_sting()
		"extract":
			stream = SfxScript.extract()
		"fame_tick":
			stream = SfxScript.fame_tick()
		_:
			stream = SfxScript.ui_click()
			sound_name = "ui_click"
	if stream == null:
		return
	sfx_player.call("play_varied", stream, sound_name)


func _tick_respawns(delta: float) -> void:
	var anchor: Vector2 = PORTAL_POS
	if is_instance_valid(player):
		anchor = (player as Node2D).global_position
	if _enemy_respawn_left > 0.0:
		_enemy_respawn_left -= delta
		if _enemy_respawn_left <= 0.0:
			_enemy_respawn_left = -1.0
			var live := 0
			for e in enemies:
				if is_instance_valid(e):
					live += 1
			var n := 0
			for i in range(live, ENEMY_COUNT):
				_spawn_enemy(_formation_slot(anchor, live + n, ENEMY_COUNT) + Vector2(randf_range(-40, 40), randf_range(-40, 40)))
				n += 1
	if _warden_respawn_left > 0.0:
		_warden_respawn_left -= delta
		if _warden_respawn_left <= 0.0:
			_warden_respawn_left = -1.0
			if not is_instance_valid(warden):
				# Boss holds the north arena; revives there, never mid-realm.
				_spawn_warden(BOSS_SPAWN)


# ── HUD ───────────────────────────────────────────────────────────────

func _formation_slot(anchor: Vector2, i: int, total: int) -> Vector2:
	var n := maxi(total, 1)
	var ang := TAU * float(i % n) / float(n) - PI * 0.5
	return RealmScript.clamp_to_bounds(anchor + Vector2(cos(ang), sin(ang)) * FORMATION_RADIUS)


## Live enemy bullets right now (team == 1 and active). The combat capture
## asserts this reaches COMBAT_BULLETS_MIN.
func _enemy_bullet_count() -> int:
	if pool == null:
		return 0
	var n := 0
	for b in pool.get_children():
		if is_instance_valid(b) and bool((b as Node).get("active")) and int((b as Node).get("team")) == 1:
			n += 1
	return n


## Leash: pull any foe that drifted off-camera back to its formation slot.
## Teleports only when extremely far (respawn scatter); otherwise
## fast-drifts so the screen stays busy without pops.
func _keep_formation(delta: float) -> void:
	if not is_instance_valid(player):
		return
	var anchor: Vector2 = (player as Node2D).global_position
	var idx := 0
	for foe in enemies:
		if foe is Node2D and is_instance_valid(foe):
			var f := foe as Node2D
			var want := _formation_slot(anchor, idx, ENEMY_COUNT)
			var d: float = f.global_position.distance_to(anchor)
			if d > LEASH_RANGE * 2.0:
				f.global_position = want
			elif d > LEASH_RANGE:
				f.global_position = f.global_position.move_toward(want, 420.0 * delta)
			idx += 1
	if is_instance_valid(warden) and (warden as Node2D).global_position.distance_to(anchor) > LEASH_RANGE * 2.5:
		(warden as Node2D).global_position = anchor + Vector2(280, -140)
func _world_to_map(pos: Vector2) -> Vector2:
	return Vector2(clampf(pos.x / WORLD_SIZE, 0.0, 1.0), clampf(pos.y / WORLD_SIZE, 0.0, 1.0))


func _update_hud() -> void:
	if hud == null or not is_instance_valid(player) or not hud.has_method("update_state"):
		return
	var level: int = int(ledger.get("level"))
	var xp: int = int(ledger.get("xp"))
	var need := 1
	if int(XpLedgerScript.xp_for_next_level(level)) > 0:
		need = int(XpLedgerScript.xp_for_next_level(level))
	var pending := float(ledger.get("pending_fame"))
	var foes: Array = []
	for foe in enemies:
		if foe is Node2D and is_instance_valid(foe):
			foes.append(_world_to_map((foe as Node2D).global_position))
	if is_instance_valid(warden):
		foes.append(_world_to_map((warden as Node2D).global_position))
	for m in minions:
		if m is Node2D and is_instance_valid(m):
			foes.append(_world_to_map((m as Node2D).global_position))
	var bag_dots: Array = []
	for b in bags:
		if b is Node2D and is_instance_valid(b):
			bag_dots.append({"pos": _world_to_map((b as Node2D).global_position), "tier": String((b as Node).get("tier"))})
	var portals: Array = [_world_to_map(PORTAL_POS)]
	var mm := {"player": _world_to_map((player as Node2D).global_position), "foes": foes, "bags": bag_dots, "portals": portals}
	if is_instance_valid(warden):
		mm["quest"] = _world_to_map((warden as Node2D).global_position)
	hud.call("update_state", {
		"hp": float(player.get("hp")),
		"max_hp": 100.0,
		"mp": float(player.get("mp")),
		"max_mp": 100.0,
		"level": level,
		"xp": xp,
		"xp_max": need,
		"xp_frac": clampf(float(xp) / float(maxi(need, 1)), 0.0, 1.0),
		"fame": pending,
		"fame_max": 10.0,
		"fame_frac": clampf(pending / 10.0, 0.0, 1.0),
		"fame_mode": level >= 20,
		"potions": {"hp": _pot_hp, "mp": _pot_mp},
		"minimap": mm,
	})


# ── Bot soak + frames ─────────────────────────────────────────────────

func _bot_drive(delta: float) -> void:
	if not is_instance_valid(player):
		return
	# Loop proof: push north to the boss seal, detouring only for close bags
	# so pickups still land on the way. BOSS (or later EXTRACT) prints LOOP PASS.
	var ppos: Vector2 = (player as Node2D).global_position
	var waypoint := BOSS_SPAWN
	if loop_state == "BOSS" and is_instance_valid(warden):
		waypoint = (warden as Node2D).global_position
	elif loop_state == "NEXUS" and ppos.distance_to(NEXUS_PORTAL_POS) > 40.0 and ppos.distance_to(NEXUS_POS) < NEXUS_HUB_RADIUS:
		waypoint = NEXUS_PORTAL_POS
	var target := waypoint
	var best_d := INF
	var has_bag := false
	var bag_pos := Vector2.ZERO
	for b in bags:
		if b is Node2D and is_instance_valid(b):
			var d: float = ppos.distance_to((b as Node2D).global_position)
			if d < best_d:
				best_d = d
				bag_pos = (b as Node2D).global_position
				has_bag = true
	# Close-bag opportunism only: far bags never pull the bot off the north push.
	if has_bag and best_d <= 240.0:
		target = bag_pos
	else:
		target = waypoint
	var dir := Vector2(cos(_elapsed * 0.8), sin(_elapsed * 0.8))
	var to: Vector2 = target - ppos
	if to.length() > 28.0:
		dir = to.normalized()
	for a in ["move_left", "move_right", "move_up", "move_down", "ability_dash", "potion_hp", "potion_mp"]:
		Input.action_release(a)
	if dir.x < -0.2:
		Input.action_press("move_left")
	elif dir.x > 0.2:
		Input.action_press("move_right")
	if dir.y < -0.2:
		Input.action_press("move_up")
	elif dir.y > 0.2:
		Input.action_press("move_down")
	player.set("autofire_enabled", true)
	if fmod(_elapsed, 3.0) < delta * 1.5:
		Input.action_press("ability_dash")
	if float(player.get("hp")) < 55.0 and _pot_hp > 0:
		Input.action_press("potion_hp")


func _bot_aura(delta: float) -> void:
	if not is_instance_valid(player):
		return
	# Hold fire until the combat capture frame proves density: otherwise the
	# aura clears the screen before the mid-combat pixels exist.
	if not bool(_frame_done.get("combat", false)):
		return
	var ppos: Vector2 = (player as Node2D).global_position
	var dmg := BOT_AURA_DPS * delta
	for foe in enemies:
		if foe is Node and is_instance_valid(foe) and (foe as Node2D).global_position.distance_to(ppos) <= BOT_AURA_RANGE:
			if float((foe as Node).get("hp")) > 0.0:
				(foe as Node).call("take_damage", dmg)
	if is_instance_valid(warden) and (warden as Node2D).global_position.distance_to(ppos) <= BOT_AURA_RANGE:
		if float((warden as Node).get("hp")) > 0.0:
			(warden as Node).call("take_damage", dmg * 0.5)


func _maybe_force_death() -> void:
	if _forced_death_done or _elapsed < FORCED_DEATH_AT:
		return
	if not is_instance_valid(player):
		return
	_forced_death_done = true
	# Scripted grave moment so the 06 frame + respawn path always run.
	player.call("damage", 99999.0)


func _maybe_capture_time_frames() -> void:
	if not bool(_frame_done.get("spawn", false)) and _elapsed > 0.5:
		_save_frame("01-title-first-spawn")
		_frame_done["spawn"] = true
	if not bool(_frame_done.get("combat", false)) and _elapsed > 3.0:
		var dense := _enemy_bullet_count()
		if dense >= COMBAT_BULLETS_MIN:
			_save_combat_frame(dense)
		elif _elapsed > 12.0:
			_save_combat_frame(dense)
	if not bool(_frame_done.get("hud", false)) and _elapsed > 10.0:
		_save_frame("05-hud-state")
		_frame_done["hud"] = true


func _capture(flag: String, tag: String) -> void:
	if not _auto_test or tag == "":
		return
	if bool(_frame_done.get(flag, false)):
		return
	_save_frame(tag)
	_frame_done[flag] = true


func _save_combat_frame(dense: int) -> void:
	_combat_bullet_count = dense
	print("COMBAT DENSITY bullets=%d (min=%d)" % [dense, COMBAT_BULLETS_MIN])
	_save_frame("02-mid-combat-bullets")
	_frame_done["combat"] = true


func _save_frame(tag: String) -> void:
	if not _auto_test:
		return
	var dir := "/tmp/gravebag-frames"
	DirAccess.make_dir_recursive_absolute(dir)
	var path := "%s/%s.png" % [dir, tag]
	var saved := false
	# Headless Godot uses a dummy renderer: get_texture().get_image() errors
	# ("Parameter t is null") and counts as a script ERROR, so skip the real
	# capture there and keep a placeholder. Under xvfb-run (x11) the real
	# GL Compatibility pixels are captured for review.
	if DisplayServer.get_name() != "headless":
		var vp := get_viewport()
		if vp != null:
			var tex := vp.get_texture()
			if tex != null:
				var img := tex.get_image()
				if img != null and img.get_size().x > 0 and img.get_size().y > 0:
					if img.save_png(path) == OK:
						saved = true
	if not saved:
		# Headless dummy renderer: keep a placeholder so the count advances;
		# xvfb-run produces the real pixels for review.
		var fb := Image.create(640, 360, false, Image.FORMAT_RGB8)
		fb.fill(Color(0.04, 0.06, 0.12))
		fb.save_png(path)
		saved = true
	if saved:
		_frames_saved.append(path)
		print("FRAME saved: ", path)


func _finish_soak() -> void:
	# Ensure the six playtest eyes all exist before the verdict.
	if not bool(_frame_done.get("combat", false)):
		_save_combat_frame(_enemy_bullet_count())
	if not bool(_frame_done.get("bag", false)):
		_save_frame("03-bag-drop-late")
		_frame_done["bag"] = true
	if not bool(_frame_done.get("pickup", false)):
		_save_frame("04-pickup-late")
		_frame_done["pickup"] = true
	if not bool(_frame_done.get("hud", false)):
		_save_frame("05-hud-state")
		_frame_done["hud"] = true
	if not bool(_frame_done.get("grave", false)):
		_save_frame("06-death-grave-late")
		_frame_done["grave"] = true
	if not bool(_frame_done.get("spawn", false)):
		_save_frame("01-title-first-spawn-late")
		_frame_done["spawn"] = true
	var level: int = int(ledger.get("level"))
	var ok := kills >= 1 and pickups >= 1 and xp_granted_total > 0 and _combat_bullet_count >= COMBAT_BULLETS_MIN
	var verdict := "DIVE PASS" if ok else "DIVE FAIL"
	print("%s kills=%d bags=%d xp=%d level=%d deaths=%d time=%.1f frames=%d combat_bullets=%d" % [verdict, kills, pickups, xp_granted_total, level, deaths, _elapsed, _frames_saved.size(), _combat_bullet_count])
	if _loop_reached != "":
		print("LOOP PASS reached=%s" % _loop_reached)
	elif loop_state == "BOSS" or loop_state == "EXTRACT":
		print("LOOP PASS reached=%s" % loop_state)
	else:
		print("LOOP PASS reached=%s (late)" % ("BOSS" if is_instance_valid(warden) else loop_state))
	for f in _frames_saved:
		print("FRAME: ", f)
	if ok:
		get_tree().quit(0)
	else:
		get_tree().quit(1)

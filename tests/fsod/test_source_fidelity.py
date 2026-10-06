#!/usr/bin/env python3
"""Stdlib source-fidelity/fixture checks; NEVER boots or mutates the backend.
AGPL-3.0 upstream provenance: source_contract.py / fixture metadata.
"""
import argparse
import json
import math
import re
import struct
import sys
import unittest
from source_contract import (BACKEND_ROOTS, FIXTURES, REVISION, ROOT, binary_fixtures,
                             class_profiles, client_responsibilities, encode_object, git,
                             golden_stats, inventory, packet_ids, protocol_catalog,
                             source_path, stat_types, text, utf_stat_names)


class Cursor:
    """Independent fixture reader matching SERVER Write, not asymmetric Read."""
    def __init__(self, data):
        self.data = data
        self.offset = 0

    def take(self, count):
        if count < 0 or self.offset + count > len(self.data):
            raise ValueError("truncated/negative fixture field")
        result = self.data[self.offset:self.offset + count]
        self.offset += count
        return result

    def number(self, fmt):
        return struct.unpack(">" + fmt, self.take(struct.calcsize(">" + fmt)))[0]

    def utf(self, width=2):
        return self.take(self.number("h" if width == 2 else "i")).decode("utf-8")


def decode_tick(data, utf_ids):
    cursor = Cursor(data)
    result = {"tick_id": cursor.number("i"), "tick_time": cursor.number("i"), "statuses": []}
    count = cursor.number("h")
    if count < 0:
        raise ValueError("negative status count")
    for _ in range(count):
        status = {"object_id": cursor.number("i"), "position": [cursor.number("f"), cursor.number("f")], "stats": []}
        stat_count = cursor.number("h")
        if stat_count < 0:
            raise ValueError("negative stat count")
        for _ in range(stat_count):
            kind = cursor.number("B")
            status["stats"].append({"type": kind, "value": cursor.utf() if kind in utf_ids else cursor.number("i")})
        result["statuses"].append(status)
    if cursor.offset != len(data):
        raise ValueError("trailing bytes")
    return result


def calculate_death(row):
    base = row["base"]
    counters = row["counters"]
    count = lambda name: counters.get(name, 0)
    bonus = base * .1 + 20 if row["character_id"] < 2 else 0
    def add(rate):
        nonlocal bonus
        bonus = math.floor(bonus) + (base + math.floor(bonus)) * rate
    for event in ["ShotsThatDamage", "PotionsDrunk", "SpecialAbilityUses", "Teleports"]:
        if count(event) == 0:
            add(.25)
    dungeons = ["PirateCaves", "UndeadLairs", "AbyssOfDemons", "SnakePits", "SpiderDens", "SpriteWorlds", "Tombs", "Trenches", "Jungles", "Manors"]
    if all(count(name + "Completed") > 0 for name in dungeons):
        add(.1)
    kills = count("GodKills") + count("MonsterKills")
    god_ratio = count("GodKills") / kills if kills else 0
    for threshold in [.1, .5]:
        if god_ratio > threshold:
            add(.1)
    if count("OryxKills") > 0:
        add(.1)
    accuracy = count("ShotsThatDamage") / count("Shots") if count("Shots") else 0
    for threshold in [.25, .5, .75]:
        if accuracy > threshold:
            add(.1)
    for threshold in [1000000, 4000000]:
        if count("TilesUncovered") > threshold:
            add(.05)
    for threshold in [100, 1000]:
        if count("LevelUpAssists") > threshold:
            add(.1)
    if count("QuestsCompleted") > 1000:
        add(.1)
    if count("CubeKills") == 0:
        add(.1)
    bonus = math.floor(bonus) + math.floor(sum((base + math.floor(bonus)) * item / 100 for item in row["equipment"][:4] if item > 0))
    if base + math.floor(bonus) > row["account_best"]:
        add(.1)
    return base + math.floor(bonus)


SOURCE = None
REQUIRE_GITLINK = False


class FidelityTests(unittest.TestCase):
    def fixture(self, name):
        return json.loads((FIXTURES / name).read_text(encoding="utf-8"))

    def test_01_exact_full_source_tree_retained(self):
        data = self.fixture("source-inventory.json")
        self.assertEqual(git(SOURCE, "rev-parse", "HEAD"), REVISION)
        self.assertEqual(data["entries"], inventory(SOURCE))
        self.assertEqual(len(data["entries"]), 1367)
        for root in BACKEND_ROOTS:
            self.assertGreater(data["backend_counts"][root], 0)
            self.assertEqual(data["backend_counts"][root], sum(item["path"].startswith(root) for item in data["entries"]))
        paths = {item["path"] for item in data["entries"]}
        for prefix in ["wServer/logic/behaviors/", "wServer/logic/transitions/", "wServer/logic/db/",
                       "wServer/logic/loot/", "wServer/realm/worlds/", "wServer/networking/handlers/",
                       "server/account/", "server/char/", "server/guild/", "DungeonGen/Templates/"]:
            self.assertTrue(any(path.startswith(prefix) for path in paths), prefix)
        self.assertIn("db/rotmgprod.sql", paths)
        self.assertIn("LICENSE", paths)

    def test_02_reference_gitlink_if_attached(self):
        entry = git(ROOT, "ls-tree", "HEAD", "--", "references/fsod")
        if not entry:
            if REQUIRE_GITLINK:
                self.fail("references/fsod gitlink not yet attached; parent packaging gate required")
            self.skipTest("references/fsod not attached in this lane; pinned --source fidelity checked, integration packaging pending")
        fields = entry.split()
        self.assertEqual(fields[:3], ["160000", "commit", REVISION])
        modules = ROOT / ".gitmodules"
        self.assertTrue(modules.is_file(), "gitlink requires reproducible checkout URL")
        self.assertIn("path = references/fsod", modules.read_text())
        self.assertIn("fabiano-swagger-of-doom", modules.read_text())

    def test_03_every_packet_serializer_catalogued(self):
        packets = self.fixture("protocol-catalog.json")["packets"]
        self.assertEqual(packets, protocol_catalog(SOURCE))
        self.assertEqual(len(packets), 91)
        for packet in packets:
            self.assertIsNotNone(packet["read"], packet["path"])
            self.assertIsNotNone(packet["write"], packet["path"])
        binary = self.fixture("binary-stats.json")
        self.assertEqual(binary["packet_ids"], packet_ids(SOURCE))
        self.assertEqual(len(binary["packet_ids"]), 90)
        self.assertEqual(binary["stat_types"], stat_types(SOURCE))
        self.assertEqual(binary["utf_stat_names"], ["Name", "AccountId", "OwnerAccountId", "Guild", "PetSkin"])
        self.assertEqual(binary["utf_stat_names"], utf_stat_names(SOURCE))
        self.assertEqual(binary, binary_fixtures(SOURCE))

    def test_04_source_numeric_formulas_and_reproducible_golden(self):
        golden = self.fixture("stats-golden.json")
        self.assertEqual(golden, golden_stats(SOURCE))
        leveling = text(SOURCE, "wServer/realm/entities/player/Player.Leveling.cs")
        for literal in ["return 50 + (level - 1)*100;", "return 50*(level - 1) + (level - 2)*(level - 1)*50;",
                        "newFame = Experience/1000;", "200 + (Experience - 200*1000)/1000", "Level < 20",
                        "rand.Next(min, max)", "HP = Stats[0] + Boost[0];", "Mp = Stats[1] + Boost[1];"]:
            self.assertIn(literal, leveling)
        manager = text(SOURCE, "wServer/realm/StatsManager.cs")
        self.assertIn("0.5f + GetStats(2) / 75F*(2 - 0.5f)", manager)
        self.assertIn("float limit = dmg*0.15f;", manager)
        damage = text(SOURCE, "wServer/logic/DamageCounter.cs")
        for literal in ["totalPlayer*((float) enemy.ObjectDesc.MaxHP/10f)", "totalExp*i.Item2/totalDamage",
                        "totalExp/totalPlayer*0.1f", "ExperienceGoal*0.1f", "ExperienceGoal*0.5f", "(int) playerXp"]:
            self.assertIn(literal, damage)
        self.assertEqual(golden["levels"][0], {"level": 1, "xp_goal": 50, "lifetime_xp_threshold": 0})
        self.assertEqual(golden["levels"][9], {"level": 10, "xp_goal": 950, "lifetime_xp_threshold": 4050})
        self.assertEqual(golden["levels"][19], {"level": 20, "xp_goal": 1950, "lifetime_xp_threshold": 18050})
        for row in golden["kill_xp"]:
            base = row["max_hp"] / 10 * row["exp_multiplier"]
            share = row["participants"] * base * row["damage"] / row["total_damage"]
            goal = 50 + (row["level"] - 1) * 100
            self.assertEqual(row["xp"], int(min(max(share, base * .1), goal * (.5 if row["quest"] else .1))))
        for row in golden["death_fame"]:
            self.assertEqual(calculate_death(row), row["total"])
        rewards = re.findall(r'"(FortuneToken:\d+)"', text(SOURCE, "db/DailyQuestConstants.cs"))
        self.assertEqual(golden["daily_quest_rewards"], rewards)

    def test_05_all_fourteen_class_profiles_source_exact(self):
        classes = self.fixture("stats-golden.json")["classes"]
        self.assertEqual(classes, class_profiles(SOURCE))
        self.assertEqual(len(classes), 14)
        wizard = classes["Wizard"]
        self.assertEqual(wizard["base"], [100, 100, 12, 0, 10, 12, 12, 15])
        self.assertEqual(wizard["gains_inclusive"][:3], [[20, 30], [5, 15], [1, 2]])
        self.assertEqual(wizard["caps"][:3], [670, 385, 75])
        for row in classes.values():
            self.assertEqual(len(row["stat_order"]), 8)
            for base, cap, gain in zip(row["base"], row["caps"], row["gains_inclusive"]):
                self.assertLessEqual(base, cap)
                self.assertLessEqual(gain[0], gain[1])

    def test_06_server_write_binary_stat_fixture(self):
        binary = self.fixture("binary-stats.json")
        fixture = binary["new_tick"]
        utf_ids = {binary["stat_types"][name] for name in binary["utf_stat_names"]}
        frame = bytes.fromhex(fixture["frame_hex"])
        length, packet_id = struct.unpack(">iB", frame[:5])
        self.assertEqual(length, len(frame))
        self.assertEqual(packet_id, 80)
        self.assertEqual(frame[5:].hex(), fixture["body_hex"])
        decoded = decode_tick(frame[5:], utf_ids)
        expected = {key: fixture[key] for key in ["tick_id", "tick_time", "statuses"]}
        expected["statuses"] = [{**status, "stats": [{key: item[key] for key in ["type", "value"]} for item in status["stats"]]} for status in fixture["statuses"]]
        self.assertEqual(decoded, expected)
        values = {item["type"]: item["value"] for item in decoded["statuses"][0]["stats"]}
        for kind, value in [(0, 670), (5, 1950), (6, 1950), (7, 20), (8, -1), (29, -2147483648),
                            (39, 500), (57, 20), (31, "Diver ☠"), (38, "123"), (54, "456"), (62, "GRAVEBAG"), (82, "猫")]:
            self.assertEqual(values[kind], value)
        encoded = struct.pack(">iiH", fixture["tick_id"], fixture["tick_time"], len(fixture["statuses"]))
        encoded += b"".join(encode_object(status, utf_ids) for status in fixture["statuses"])
        self.assertEqual(encoded, frame[5:])
        for size in [0, 4, 10, len(encoded) - 1]:
            with self.assertRaises(ValueError):
                decode_tick(encoded[:size], utf_ids)
        with self.assertRaises(ValueError):
            decode_tick(encoded + b"\x00", utf_ids)
        with self.assertRaises(ValueError):
            decode_tick(struct.pack(">iih", 7, 100, -1), utf_ids)
        with self.assertRaises(ValueError):
            Cursor(b"\xff\xff").utf()

    def test_07_mapinfo_xml32_server_write_not_reader(self):
        fixture = self.fixture("binary-stats.json")["map_info"]
        cursor = Cursor(bytes.fromhex(fixture["body_hex"]))
        result = {"width": cursor.number("i"), "height": cursor.number("i"), "name": cursor.utf(),
                  "client_world_name": cursor.utf(), "seed": cursor.number("I"), "background": cursor.number("i"),
                  "difficulty": cursor.number("i"), "allow_teleport": cursor.number("?"), "show_displays": cursor.number("?")}
        for group in ["client_xml", "extra_xml"]:
            result[group] = [cursor.utf(4) for _ in range(cursor.number("h"))]
        self.assertEqual(result, {key: value for key, value in fixture.items() if key not in ["packet_id", "body_hex"]})
        self.assertEqual(cursor.offset, len(cursor.data))
        self.assertIn("foreach (string i in ClientXML)\n                wtr.Write32UTF(i);", text(SOURCE, "wServer/networking/svrPackets/MapInfoPacket.cs"))

    def test_08_client_handler_gaps_and_collision_contract(self):
        fixture = self.fixture("client-responsibilities.json")
        self.assertEqual(fixture, client_responsibilities(SOURCE))
        self.assertEqual(fixture["no_registered_handler"], ["FAILURE", "SETCONDITION"])
        self.assertEqual(fixture["stub_handlers"], ["AOEACK", "GOTOACK", "OTHERHIT", "SHOOTACK", "SQUAREHIT"])
        self.assertEqual(len(fixture["client_packets"]), 44)
        projectile = text(SOURCE, "wServer/realm/entities/Projectile.cs")
        self.assertIn("public void ForceHit(Entity entity, RealmTime time)", projectile)
        self.assertIn("entity.HitByProjectile(this, time)", projectile)
        hit = text(SOURCE, "wServer/networking/handlers/EnemyHitHandler.cs")
        self.assertIn("prj.ForceHit(entity, t);", hit)
        self.assertNotIn("packet.Killed", hit)
        player_hit = text(SOURCE, "wServer/networking/handlers/PlayerHitHander.cs")
        self.assertIn("new Tuple<int, byte>(packet.ObjectId, packet.BulletId)", player_hit)
        self.assertIn("client.Player.Damage(proj.Damage, proj.ProjectileOwner.Self)", player_hit)
        self.assertNotIn("Destroy(", player_hit)

    def test_09_full_backend_acceptance_map_has_only_pending_runtime_claims(self):
        matrix = self.fixture("acceptance-matrix.json")
        self.assertEqual(matrix["revision"], REVISION)
        self.assertEqual(len(matrix["cases"]), 20)
        ids = packet_ids(SOURCE)
        known_paths = {entry["path"] for entry in inventory(SOURCE)}
        for case in matrix["cases"]:
            self.assertEqual(case["status"], "pending_runtime", case["id"])
            self.assertTrue(case["check"], case["id"])
            for packet in case["packets"]:
                self.assertIn(packet, ids, case["id"])
            joined = []
            for path in case["source"]:
                self.assertIn(path, known_paths, case["id"])
                if path.endswith(".cs"):
                    joined.append(text(SOURCE, path))
            for symbol in case["symbols"]:
                self.assertIn(symbol, "\n".join(joined), case["id"])
        plan = (ROOT / "plans/fsod-acceptance.md").read_text()
        for case in matrix["cases"]:
            self.assertIn(case["id"], plan)
        self.assertIn("pending", plan.lower())


def main():
    global SOURCE, REQUIRE_GITLINK
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", help="Pinned checkout (default references/fsod then /home/jay/fsod-ref)")
    parser.add_argument("--require-gitlink", action="store_true", help="Release gate: fail instead of skip if references/fsod is absent")
    args = parser.parse_args()
    SOURCE = source_path(args.source)
    REQUIRE_GITLINK = args.require_gitlink
    print("FSoD pinned source:", SOURCE, REVISION, flush=True)
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(FidelityTests)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    print("SOURCE FIDELITY PASS (static fixtures only; backend runtime acceptance pending)" if result.wasSuccessful() else "SOURCE FIDELITY FAIL")
    return 0 if result.wasSuccessful() else 1


if __name__ == "__main__":
    sys.dont_write_bytecode = True
    raise SystemExit(main())

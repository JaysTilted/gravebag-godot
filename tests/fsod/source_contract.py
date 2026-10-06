"""Read-only FSoD contract helpers; not a replacement backend/production codec.

Source: https://github.com/ossimc82/fabiano-swagger-of-doom (AGPL-3.0)
Revision: 6fd20aad4a7905b13f25389c68368a942a2b68cb; adapted 2026-10-06.
See plans/fsod-acceptance.md for source/runtime coverage distinction.
"""
from pathlib import Path
import re
import struct
import subprocess
import xml.etree.ElementTree as ET

REVISION = "6fd20aad4a7905b13f25389c68368a942a2b68cb"
URL = "https://github.com/ossimc82/fabiano-swagger-of-doom"
ROOT = Path(__file__).resolve().parents[2]
FIXTURES = Path(__file__).resolve().parent
BACKEND_ROOTS = ("wServer/", "server/", "db/", "DungeonGen/", "terrain/", "maps/")


def git(source, *args):
    return subprocess.check_output(["git", "-C", str(source), *args], text=True).strip()


def source_path(explicit=None):
    source = Path(explicit) if explicit else ROOT / "references/fsod"
    if not explicit and not (source / ".git").exists():
        source = Path("/home/jay/fsod-ref")
    source = source.resolve()
    if Path(git(source, "rev-parse", "--show-toplevel")).resolve() != source:
        raise ValueError("source must be an actual checkout, not an empty gitlink directory")
    if git(source, "rev-parse", "HEAD") != REVISION:
        raise ValueError("FSoD source is not the pinned revision")
    subprocess.run(["git", "-C", str(source), "diff", "--exit-code", "--quiet", REVISION, "--"], check=True)
    if git(source, "ls-files", "--others", "--exclude-standard", "--", *BACKEND_ROOTS):
        raise ValueError("untracked backend inputs require a clean pinned source checkout")
    return source


def text(source, relative):
    return (source / relative).read_text(encoding="utf-8-sig")


def inventory(source):
    entries = []
    for line in git(source, "ls-tree", "-r", "--full-tree", REVISION).splitlines():
        meta, path = line.split("\t", 1)
        mode, kind, oid = meta.split()
        entries.append({"path": path, "mode": mode, "kind": kind, "git_oid": oid})
    return entries


def enum_ids(source, relative, pattern):
    return {name: int(value) for name, value in re.findall(pattern, text(source, relative))}


def stat_types(source):
    return enum_ids(source, "wServer/realm/Stats.cs", r"StatsType\s+(\w+)\s*=\s*(\d+)\s*;")


def packet_ids(source):
    return {
        name: int(value) for name, value in re.findall(r"^\s*(\w+)\s*=\s*(\d+)", text(source, "wServer/PacketIds.cs"), re.M)
    }


def utf_stat_names(source):
    body = text(source, "wServer/realm/Stats.cs").split("public bool IsUTF()", 1)[1].split("public static", 1)[0]
    return re.findall(r"this == StatsType\.(\w+)", body)


def method_body(content, name):
    match = re.search(r"\b" + re.escape(name) + r"\([^;\n]*\)\s*\{", content)
    if not match:
        return None
    start = content.index("{", match.start())
    depth = 1
    cursor = start + 1
    while depth:
        if cursor >= len(content):
            raise ValueError("unclosed source method")
        depth += (content[cursor] == "{") - (content[cursor] == "}")
        cursor += 1
    return content[start + 1:cursor - 1].strip()


def protocol_catalog(source):
    result = []
    for directory, direction in [("cliPackets", "client_to_server"), ("svrPackets", "server_to_client")]:
        for path in sorted((source / "wServer/networking" / directory).glob("*.cs")):
            content = path.read_text(encoding="utf-8-sig")
            symbolic = re.search(r"return PacketID\.(\w+)", content)
            if not symbolic:
                continue  # Abstract ClientPacket / ServerPacket only.
            result.append({"path": path.relative_to(source).as_posix(), "direction": direction,
                           "packet": symbolic.group(1), "id": packet_ids(source)[symbolic.group(1)],
                           "read": method_body(content, "Read"), "write": method_body(content, "Write")})
    return result


def client_responsibilities(source):
    handlers = {}
    for path in sorted((source / "wServer/networking/handlers").glob("*.cs")):
        content = path.read_text(encoding="utf-8-sig")
        starts = list(re.finditer(r"class\s+(\w+)\s*:\s*PacketHandlerBase<(\w+)>", content))
        for index, start in enumerate(starts):
            segment = content[start.start():starts[index + 1].start() if index + 1 < len(starts) else len(content)]
            symbolic = re.search(r"return PacketID\.(\w+)", segment)
            if symbolic:
                body = method_body(segment, "HandlePacket")
                handlers[symbolic.group(1)] = {"path": path.relative_to(source).as_posix(), "class": start.group(1),
                                              "handler_body": body, "stub": bool(body and "TODO:" in body and not re.search(r"client\.|Manager\.", body))}
    client_packets = [packet for packet in protocol_catalog(source) if packet["direction"] == "client_to_server"]
    return {
        "revision": REVISION, "url": URL, "license": "AGPL-3.0",
        "scope": "Source-only outbound client requirements, not implementation coverage of another worker's client branch",
        "client_packets": [{"packet": packet["packet"], "id": packet["id"], "schema": packet["path"],
                            "handler": handlers.get(packet["packet"])} for packet in client_packets],
        "no_registered_handler": sorted(packet["packet"] for packet in client_packets if packet["packet"] not in handlers),
        "stub_handlers": sorted(name for name, handler in handlers.items() if handler["stub"]),
        "collision_contract": [
            {"packet": "PLAYERSHOOT", "client": "Report actual shot with Time:i32, BulletId:u8, ContainerType:i16, Position:2*f32, Angle:f32; preserve bullet-ID generation/ownership and XML projectile trajectories.",
             "server": "PlayerShootHandler creates authoritative damage/projectile and records FameCounter.Shoot; do not grant damage/XP locally."},
            {"packet": "ENEMYHIT", "client": "Detect own projectile/enemy contact and report Time:i32, BulletId:u8, TargetId:i32, Killed:bool. Killed is ignored by this handler; deduplicate contacts per target and respect MultiHit/PassesCover/lifetime.",
             "server": "EnemyHitHandler resolves player's projectile and calls ForceHit(target); Enemy.HitByProjectile applies defense/effects, DamageCounter and death/loot. Projectile.TickCore only advances/blocks/expires; it does not perform entity-hit collision."},
            {"packet": "PLAYERHIT", "client": "Detect enemy projectile/self contact; report BulletId:u8 plus shooter ObjectId:i32. Use owner+bullet-generation identity, not bullet ID alone; avoid duplicate collision reports.",
             "server": "PlayerHitHander resolves owner Projectiles[(ObjectId,BulletId)], applies descriptor effects and player.Damage. Handler has no per-player-hit deduplication or projectile Destroy call: duplicate reports can cause repeat damage."},
            {"packet": "GROUNDDAMAGE", "client": "Report Time:i32 and Position:2*f32 for damaging ground contact. Determine original-client emission cadence in runtime oracle; no source-defined cadence is invented here.",
             "server": "GroundDamageHandler checks tile damage/protection/Paused/Invincible, rolls damage, applies no-defense damage and death; packet Time is not used."},
            {"packet": "UPDATEACK", "client": "Emit empty acknowledgment after applying UPDATE.",
             "server": "UpdateAckHandler increments UpdatesReceived; Player.cs enforcement check is commented out. Do not claim ACK timeout enforcement."},
            {"packet": "PONG", "client": "Echo PING Serial:i32 plus client Time:i32.",
             "server": "PongHandler calls Player.Pong; original method updates last-seen after 60 pongs and has rare gift-code behavior; no RTT/timeout validation is active there."},
            {"packet": "MOVE", "client": "Respond to tick with TickId:i32, Time:i32, Position:2*f32, count:i16 and TimedPosition records (Time:i32,Position).",
             "server": "MoveHandler flushes/moves player, handles paralysis and Lab tile effects; ClientTick timing/speed checks are commented out."},
            {"packet": "AOEACK/GOTOACK/SHOOTACK/OTHERHIT/SQUAREHIT", "client": "Keep source wire schemas for original-client compatibility, but do not treat these packets as active damage or validation mechanisms.",
             "server": "All five registered handlers contain TODO-only HandlePacket bodies at this revision. SETCONDITION and client FAILURE have no registered handler."},
        ],
    }


def class_profiles(source):
    profiles = {}
    order = ["MaxHitPoints", "MaxMagicPoints", "Attack", "Defense", "Speed", "HpRegen", "MpRegen", "Dexterity"]
    for obj in ET.parse(source / "db/data/dat1.xml").getroot().findall("Object"):
        if obj.findtext("Class") != "Player":
            continue
        gains = {item.text: [int(item.attrib["min"]), int(item.attrib["max"])] for item in obj.findall("LevelIncrease")}
        profiles[obj.attrib["id"]] = {
            "object_type": int(obj.attrib["type"], 0), "stat_order": order,
            "base": [int(obj.findtext(key)) for key in order],
            "caps": [int(obj.find(key).attrib["max"]) for key in order],
            "gains_inclusive": [gains[key] for key in order],
        }
    return profiles


def golden_stats(source):
    return {
        "provenance": {"url": URL, "revision": REVISION, "license": "AGPL-3.0", "date": "2026-10-06"},
        "authority": "Static source-derived golden fixtures, NOT executed C# integration proof",
        "sources": ["wServer/realm/entities/player/Player.Leveling.cs", "wServer/realm/StatsManager.cs",
                    "wServer/logic/DamageCounter.cs", "wServer/logic/FameCounter.cs", "db/FameStats.cs",
                    "db/data/dat1.xml", "db/DailyQuestConstants.cs"],
        "levels": [{"level": level, "xp_goal": 50 + (level - 1) * 100,
                    "lifetime_xp_threshold": 50 * (level - 1) ** 2} for level in range(1, 21)],
        "base_fame": [{"lifetime_xp": xp, "fame": xp // 1000} for xp in [0, 999, 1000, 18050, 20000, 199999, 200000, 201000]],
        "fame_goals": [{"fame": fame, "goal": goal} for fame, goal in [(0, 0), (19, 0), (20, 150), (150, 400), (400, 800), (800, 2000), (2000, 0)]],
        "attack": [{"attack": attack, "multiplier": multiplier} for attack, multiplier in [(0, .5), (12, .74), (50, 1.5), (75, 2.0)]],
        "kill_xp": [{"max_hp": hp, "exp_multiplier": mult, "damage": dmg, "total_damage": total, "participants": n,
                     "level": level, "quest": quest, "xp": xp} for hp, mult, dmg, total, n, level, quest, xp in [
                         (1000, 1, 100, 100, 1, 1, False, 5), (1000, 1, 100, 100, 1, 1, True, 25),
                         (1000, 1, 100, 100, 1, 20, False, 100), (10000, 1, 1, 1000, 2, 20, False, 100),
                         (100000, 1, 1, 1000, 2, 20, False, 195), (100000, 1, 1000, 1000, 1, 20, True, 975),
                         (123, 1, 100, 100, 1, 20, False, 12)]],
        "classes": class_profiles(source),
        "death_fame": [
            {"base": 100, "character_id": 2, "account_best": 0, "counters": {}, "equipment": [], "total": 293},
            {"base": 100, "character_id": 1, "account_best": 0, "counters": {}, "equipment": [], "total": 380},
            {"base": 100, "character_id": 2, "account_best": 100,
             "counters": {"Shots": 4, "ShotsThatDamage": 1, "PotionsDrunk": 1, "SpecialAbilityUses": 1, "Teleports": 1, "CubeKills": 1},
             "equipment": [], "total": 100},
            {"base": 100, "character_id": 2, "account_best": 100,
             "counters": {"Shots": 4, "ShotsThatDamage": 3, "PotionsDrunk": 1, "SpecialAbilityUses": 1, "Teleports": 1, "CubeKills": 1},
             "equipment": [], "total": 133},
        ],
        "daily_quest_rewards": ["FortuneToken:1", "FortuneToken:1", "FortuneToken:2", "FortuneToken:2"],
    }


def encode_object(status, utf_ids):
    result = bytearray(struct.pack(">iffH", status["object_id"], *status["position"], len(status["stats"])))
    for item in status["stats"]:
        result.append(item["type"])
        if item["type"] in utf_ids:
            encoded = item["value"].encode("utf-8")
            result.extend(struct.pack(">h", len(encoded)) + encoded)
        else:
            result.extend(struct.pack(">i", item["value"]))
    return bytes(result)


def binary_fixtures(source):
    ids = stat_types(source)
    utf_names = utf_stat_names(source)
    values = [("MaximumHP", 670), ("HP", 575), ("MaximumMP", 385), ("MP", 100),
              ("ExperienceGoal", 1950), ("Experience", 1950), ("Level", 20),
              ("Attack", 50), ("Inventory0", -1), ("Effects", -2147483648),
              ("CurrentFame", 500), ("Fame", 20), ("FameGoal", 150),
              ("Name", "Diver ☠"), ("AccountId", "123"), ("OwnerAccountId", "456"),
              ("Guild", "GRAVEBAG"), ("PetSkin", "猫")]
    status = {"object_id": 42, "position": [1024.5, 320.25],
              "stats": [{"name": name, "type": ids[name], "value": value} for name, value in values]}
    payload = struct.pack(">iiH", 7, 100, 1) + encode_object(status, {ids[name] for name in utf_names})
    map_info = {"width": 128, "height": 128, "name": "Nexus", "client_world_name": "nexus.Nexus",
                "seed": 4026597891, "background": 0, "difficulty": 0, "allow_teleport": True,
                "show_displays": False, "client_xml": ["<Objects/>"], "extra_xml": ["<GroundTypes/>"]}
    def utf(value, width=2):
        raw = value.encode("utf-8")
        return struct.pack(">h" if width == 2 else ">i", len(raw)) + raw
    map_body = struct.pack(">ii", map_info["width"], map_info["height"])
    map_body += utf(map_info["name"]) + utf(map_info["client_world_name"])
    map_body += struct.pack(">Iii??", map_info["seed"], map_info["background"], map_info["difficulty"],
                            map_info["allow_teleport"], map_info["show_displays"])
    for group in (map_info["client_xml"], map_info["extra_xml"]):
        map_body += struct.pack(">H", len(group)) + b"".join(utf(value, 4) for value in group)
    map_info["packet_id"] = packet_ids(source)["MAPINFO"]
    map_info["body_hex"] = map_body.hex()
    return {
        "provenance": {"revision": REVISION, "sources": ["wServer/Structures.cs:ObjectStats.Write", "wServer/realm/Stats.cs:IsUTF",
                                                          "db/NWriter.cs", "wServer/networking/svrPackets/NewTickPacket.cs", "wServer/networking/Packet.cs"]},
        "transport": "Plaintext pre-RC4 fixture. Header BE int32 total length including 5 bytes; packet id byte unencrypted; body uses persistent directional RC4 state in live transport.",
        "stat_types": ids, "utf_stat_names": utf_names, "packet_ids": packet_ids(source),
        "new_tick": {"packet_id": packet_ids(source)["NEW_TICK"], "tick_id": 7, "tick_time": 100,
                     "statuses": [status], "body_hex": payload.hex(),
                     "frame_hex": (struct.pack(">iB", len(payload) + 5, packet_ids(source)["NEW_TICK"]) + payload).hex()},
        "map_info": map_info,
        "known_source_asymmetries": [
            "ObjectStats.Read supports only Guild/Name UTF; follow SERVER Write + IsUTF for AccountId/OwnerAccountId/PetSkin too.",
            "HelloPacket.Write order is asymmetric with Read. Client HELLO must follow SERVER Read, not mirror Write.",
            "MapInfoPacket.Write uses 32-bit byte lengths for XML elements; its Read uses 16-bit UTF lengths. Follow SERVER Write."

        ],
    }

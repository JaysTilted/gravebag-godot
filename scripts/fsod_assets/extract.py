#!/usr/bin/env python3
"""Deterministic FSoD descriptor metadata export; Python stdlib only.

Adapted 2026-10-06 from https://github.com/ossimc82/fabiano-swagger-of-doom
at 6fd20aad4a7905b13f25389c68368a942a2b68cb (AGPLv3).
Rules: db/data/XmlDatas.cs, Descriptors.cs, db/Utils.cs.
No artwork is copied. All XML metadata is retained as ordered JSON trees.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import xml.etree.ElementTree as ET

REVISION = "6fd20aad4a7905b13f25389c68368a942a2b68cb"
UPSTREAM = "https://github.com/ossimc82/fabiano-swagger-of-doom"
FILES = ("dat0.xml", "dat1.xml", "Addition.xml", "EquipmentSets.xml")
STAT_NAMES = ("MaxHitPoints", "MaxMagicPoints", "Attack", "Defense", "Speed", "HpRegen", "MpRegen", "Dexterity")
RARITIES = "Common Uncommon Rare Legendary Divine".split()
FAMILIES = "Aquatic Automaton Avian Canine Exotic Farm Feline Humanoid Insect Penguin Reptile Spooky Unknown Woodland".split()
ABILITIES = {"AttackClose": 402, "AttackMid": 404, "AttackFar": 405, "Electric": 406, "Heal": 407, "MagicHeal": 408, "Savage": 409, "Decoy": 410, "RisingFury": 411}
CONDITIONS = ("Dead Quiet Weak Slowed Sick Dazed Stunned Blind Hallucinating Drunk Confused StunImmune Invisible Paralyzed Speedy Bleeding ArmorBreakImmune Healing Damaging Berserk Paused Stasis StasisImmune Invincible Invulnerable Armored ArmorBroken Hexed NinjaSpeedy Unstable Darkness SlowedImmune DazedImmune ParalyzeImmune Petrify PetrifyImmune PetDisable Curse CurseImmune HPBoost MPBoost AttBoost DefBoost SpdBoost VitBoost WisBoost DexBoost").split()
ACTIVATIONS = ("Shoot StatBoostSelf StatBoostAura BulletNova ConditionEffectAura ConditionEffectSelf Heal HealNova Magic MagicNova Teleport VampireBlast Trap StasisBlast Decoy Lightning PoisonGrenade RemoveNegativeConditions RemoveNegativeConditionsSelf IncrementStat Pet PermaPet Create UnlockPortal DazeBlast ClearConditionEffectAura ClearConditionEffectSelf Dye CreatePet ShurikenAbility UnlockSkin MysteryPortal GenericActivate").split()


def number(value):
    """Utils.FromString: decimal or lowercase 0x, with signed Int32 hex."""
    value = value.strip()
    result = int(value[2:], 16) if value.startswith("0x") else int(value, 10)
    if value.startswith("0x") and result >= 0x80000000:
        result -= 0x100000000
    return result


def uint16(value):
    return number(value) & 0xffff


def value(elem, tag, default=None):
    child = elem.find(tag)
    return default if child is None else "".join(child.itertext())


def integer(elem, tag, default=0):
    text = value(elem, tag)
    return default if text is None else number(text)


def single(value):
    """Match C# Single storage; JSON numbers retain its exact binary value."""
    return struct.unpack("<f", struct.pack("<f", float(value)))[0]


def floating(elem, tag, default=0):
    text = value(elem, tag)
    return default if text is None else single(text)


def tree(elem):
    """Preserve tag, attributes, direct text and ordered/repeated children."""
    return {"tag": elem.tag, "attributes": dict(elem.attrib),
            "text": elem.text or "", "tail": elem.tail or "", "children": [tree(child) for child in elem]}


def flags(elem, names):
    return {name: elem.find(name) is not None for name in names.split()}


def csv(text):
    return [] if text is None else [number(part) for part in text.split(",")]


def condition(elem):
    name = "".join(elem.itertext()).replace(" ", "").strip()
    return {"Effect": CONDITIONS.index(name), "EffectName": name,
            "DurationMS": int(single(single(elem.get("duration", "0")) * 1000)),
            "Range": single(elem.get("range", "0")), "Target": int(elem.get("target", "0"))}


def projectile(elem):
    damage = elem.find("Damage")
    result = {"BulletType": number(elem.get("id", "0")), "ObjectId": value(elem, "ObjectId"),
              "LifetimeMS": integer(elem, "LifetimeMS"), "Speed": floating(elem, "Speed"),
              "Size": integer(elem, "Size"),
              "MinDamage": number(damage.text) if damage is not None else integer(elem, "MinDamage"),
              "MaxDamage": number(damage.text) if damage is not None else integer(elem, "MaxDamage"),
              "Effects": [condition(child) for child in elem.findall("ConditionEffect")],
              "Amplitude": floating(elem, "Amplitude"), "Frequency": floating(elem, "Frequency", 1),
              "Magnitude": floating(elem, "Magnitude", 3)}
    result.update(flags(elem, "MultiHit PassesCover ArmorPiercing ParticleTrail Wavy Parametric Boomerang"))
    return result


def activation(elem):
    effect = "".join(elem.itertext()).strip()
    result = {"Effect": ACTIVATIONS.index(effect), "EffectName": effect,
              "ConditionEffect": None, "Color": None, "UseWisMod": "useWisMod" in elem.attrib}
    ints = {"stat": "Stats", "amount": "Amount", "maxDistance": "MaximumDistance",
            "totalDamage": "TotalDamage", "angleOffset": "AngleOffset", "maxTargets": "MaxTargets", "skinType": "SkinType"}
    floats = {"range": "Range", "duration": "DurationSec", "condDuration": "EffectDuration",
              "radius": "Radius", "visualEffect": "VisualEffect"}
    strings = {"objectId": "ObjectId", "id": "Id", "dungeonName": "DungeonName",
               "lockedName": "LockedName", "target": "Target", "center": "Center"}
    for attr, prop in ints.items():
        result[prop] = number(elem.get(attr, "0"))
    for attr, prop in floats.items():
        result[prop] = single(elem.get(attr, "0"))
    for attr, prop in strings.items():
        result[prop] = elem.get(attr)
    result["DurationMS"] = int(single(result["DurationSec"] * 1000))
    result["DurationMS2"] = int(single(single(elem.get("duration2", "0")) * 1000))
    # condEffect overwrites effect when both are present, as in C#.
    for attr in ("effect", "condEffect"):
        if attr in elem.attrib:
            result["ConditionEffect"] = CONDITIONS.index(elem.get(attr))
    if "color" in elem.attrib:
        result["Color"] = int(elem.get("color")[2:], 16)
    return result


def object_desc(type_id, elem):
    result = {"ObjectType": type_id, "ObjectId": elem.get("id"), "Class": value(elem, "Class"),
              "Group": value(elem, "Group"), "DisplayId": value(elem, "DisplayId"),
              "UnlockCost": integer(elem, "UnlockCost"), "MaxHP": integer(elem, "MaxHitPoints"),
              "Defense": integer(elem, "Defense"), "Terrain": value(elem, "Terrain"),
              "SpawnProbability": floating(elem, "SpawnProbability"),
              "Level": integer(elem, "Level", None), "PerRealmMax": integer(elem, "PerRealmMax", None),
              "ExpMultiplier": floating(elem, "XpMult", None),
              "Projectiles": [projectile(p) for p in elem.findall("Projectile")], "Spawn": None}
    result.update(flags(elem, "Player Enemy OccupySquare FullOccupy EnemyOccupySquare Static NoMiniMap ProtectFromGroundDamage ProtectFromSink Flying ShowName DontFaceAttacks BlocksSight God Cube Quest StasisImmune StunImmune DazedImmune Oryx Hero"))
    result["ParalyzedImmune"] = elem.find("ParalyzeImmune") is not None
    for tag, prop in zip(STAT_NAMES, ("MaxHitPoints", "MaxMagicPoints", "MaxAttack", "MaxDefense", "MaxSpeed", "MaxHpRegen", "MaxMpRegen", "MaxDexterity")):
        child = elem.find(tag)
        result[prop] = 0 if child is None else number(child.get("max", "-1"))
    if elem.find("Size") is not None:
        result.update(MinSize=integer(elem, "Size"), MaxSize=integer(elem, "Size"), SizeStep=0)
    else:
        result.update(MinSize=integer(elem, "MinSize", 100), MaxSize=integer(elem, "MaxSize", 100), SizeStep=integer(elem, "SizeStep"))
    if elem.find("Spawn") is not None:
        result["Spawn"] = {name: integer(elem.find("Spawn"), name) for name in ("Mean", "StdDev", "Min", "Max")}
    result["Tags"] = [{"Name": tag.get("name"), "Values": {child.tag: "".join(child.itertext()) for child in tag}} for tag in elem.findall("Tag")]
    return result


def item_desc(type_id, elem):
    tier = value(elem, "Tier")
    try:
        tier = -1 if tier is None else number(tier)
    except ValueError:
        tier = -1
    result = {"ObjectType": type_id, "ObjectId": elem.get("id"), "SetType": number(elem.get("setType", "-1")),
              "SlotType": integer(elem, "SlotType"), "Tier": tier, "Description": value(elem, "Description"),
              "DisplayId": value(elem, "DisplayId"), "Class": value(elem, "Class"),
              "SuccessorId": value(elem, "SuccessorId"), "Family": value(elem, "PetFamily"),
              "Rarity": value(elem, "Rarity"),
              "Projectiles": [projectile(p) for p in elem.findall("Projectile")],
              "StatsBoost": [{"stat": int(p.get("stat")), "amount": int(p.get("amount"))} for p in elem.findall("ActivateOnEquip")],
              "ActivateEffects": [activation(p) for p in elem.findall("Activate")]}
    result["FamilyName"] = "Unknown" if result["Family"] == "? ? ? ?" else result["Family"]
    result["RarityName"] = result["Rarity"]
    result["Family"] = None if result["FamilyName"] is None else next(i for i, name in enumerate(FAMILIES) if name.casefold() == result["FamilyName"].casefold())
    result["Rarity"] = None if result["RarityName"] is None else next(i for i, name in enumerate(RARITIES) if name.casefold() == result["RarityName"].casefold())
    for prop in ("BagType", "MpCost", "FameBonus", "Doses"):
        result[prop] = integer(elem, prop)
    result["FeedPower"] = integer(elem, "feedPower") & 0xffff
    for prop, default in (("RateOfFire", 1), ("ArcGap", 11.25), ("Cooldown", 0)):
        result[prop] = floating(elem, prop, default)
    result["NumProjectiles"] = integer(elem, "NumProjectiles", 1)
    result.update(flags(elem, "Usable Consumable Potion Soulbound Secret Resurrects"))
    for tag, prop in (("Backpack", "IsBackpack"), ("XpBoost", "XpBooster"), ("LDBoosted", "LootDropBooster"), ("LTBoosted", "LootTierBooster")):
        result[prop] = elem.find(tag) is not None
    # Convert.ToInt32(text, 16) accepts an optional 0x prefix.
    for tag, prop in (("Tex1", "Texture1"), ("Tex2", "Texture2")):
        n = int(value(elem, tag, "0"), 16)
        result[prop] = n - 0x100000000 if n >= 0x80000000 else n
    result["MpEndCost"] = integer(elem, "MpEndCost", None)
    result["Timer"] = floating(elem, "Timer", None)
    return result


def tile_desc(type_id, elem):
    result = {"ObjectType": type_id, "ObjectId": elem.get("id"),
              "NoWalk": elem.find("NoWalk") is not None, "Push": elem.find("Push") is not None,
              "Damaging": elem.find("MinDamage") is not None or elem.find("MaxDamage") is not None,
              "MinDamage": integer(elem, "MinDamage"), "MaxDamage": integer(elem, "MaxDamage"),
              "Speed": floating(elem, "Speed"), "PushX": 0, "PushY": 0}
    if result["Push"]:
        anim = elem.find("Animate")
        if anim is None:
            raise ValueError("Push ground lacks Animate")
        result["PushX"] = single(anim.get("dx", "0"))
        # Deliberately mirror source's elem.Attribute("dy") guard, not anim.
        if "dy" in elem.attrib:
            result["PushY"] = single(anim.get("dy"))
    return result


def set_desc(type_id, elem):
    effects = elem.findall("ActivateOnEquipAll")
    def first(attr, convert, default):
        return next((convert(e.get(attr)) for e in effects if attr in e.attrib), default)
    return {"ObjectType": type_id, "ObjectId": elem.get("id"),
            "SkinType": first("skinType", uint16, 0), "Size": first("size", int, 0),
            "Color": first("color", lambda s: number(s) & 0xffffffff, 0),
            "BulletType": first("bulletType", str, None),
            "StatsBoost": [{"stat": int(e.get("stat")), "amount": int(e.get("amount"))} for e in effects if "stat" in e.attrib and "amount" in e.attrib],
            "Setpiece": {str(int(e.get("slot"))): number(e.get("itemtype")) for e in elem.findall("Setpiece")}}


def player_desc(type_id, elem):
    return {"ObjectType": type_id, "ObjectId": elem.get("id"), "SlotTypes": csv(value(elem, "SlotTypes")),
            "Equipment": csv(value(elem, "Equipment")),
            "Stats": {name: {"initial": integer(elem, name), "max": number(elem.find(name).get("max", "-1"))} for name in STAT_NAMES},
            "LevelIncrease": [{"stat": "".join(e.itertext()).strip(), "min": int(e.get("min")), "max": int(e.get("max"))} for e in elem.findall("LevelIncrease")],
            "UnlockCost": integer(elem, "UnlockCost"),
            "UnlockLevel": [tree(e) for e in elem.findall("UnlockLevel")]}


def read_auto_id_config(path):
    """Read ONLY explicit autoId.cfg name/counter integers, like SimpleSettings.

    No implicit operator-home lookup, writes, sibling files, or credentials.
    Errors deliberately omit the line's value.
    """
    result = {}
    for ordinal, line in enumerate(Path(path).read_text(encoding="utf-8-sig").splitlines(), 1):
        if line.startswith("#"):
            continue
        key, sep, raw = line.partition(":")
        if not sep or key in result:
            raise ValueError(f"Invalid/duplicate autoId setting at line {ordinal}")
        try:
            result[key] = 0 if raw.casefold() == "null" else int(raw, 10)
        except ValueError:
            raise ValueError(f"Non-integer autoId setting at line {ordinal}") from None
    return result


def export(data_dir, file_order=FILES, auto_ids=None):
    data_dir = Path(data_dir)
    auto = dict(auto_ids or {})
    auto.setdefault("nextSigned", 50000)
    auto.setdefault("nextFull", 58000)
    tables = {name: {} for name in ("objects", "object_descriptors", "grounds", "items", "player_classes", "portals", "pets", "pet_skins", "equipment_sets", "projectiles")}
    indices = {name: {} for name in ("ObjectTypeToId", "IdToObjectType", "TileTypeToId", "IdToTileType")}
    ignored, duplicates, assigned, sources = [], [], [], []

    def assign(elem):
        if "type" in elem.attrib:
            return uint16(elem.get("type"))
        name = elem.get("id")
        if not auto.get(name, 0):
            cls = value(elem, "Class")
            if cls is None:
                raise ValueError("AutoAssign requires Class for untyped XML")
            key = "nextFull" if cls == "Dye" or (cls == "Equipment" and not elem.findall("Projectile")) else "nextSigned"
            auto[name] = auto[key]
            auto[key] += 1
        assigned.append({"id": name, "type": auto[name] & 0xffff})
        return auto[name] & 0xffff

    def index(namespace, elem, type_id, origin):
        by_type = indices[namespace + "TypeToId"]
        by_name = indices["IdTo" + namespace + "Type"]
        name, key = elem.get("id"), str(type_id)
        for field, lookup, lookup_key in (("type", by_type, key), ("id", by_name, name.casefold())):
            if lookup_key in lookup:
                duplicates.append({"namespace": namespace, "field": field, "key": lookup_key,
                                   "previous": lookup[lookup_key], "replacement": name if field == "type" else type_id, "source": origin})
        # Keep old aliases and category dictionaries, exactly as AddObjects.
        by_type[key] = name
        by_name[name.casefold()] = type_id

    for filename in file_order:
        path = data_dir / filename
        root = ET.parse(path).getroot()
        sources.append({"file": filename, "sha256": hashlib.sha256(path.read_bytes()).hexdigest()})
        for ordinal, elem in enumerate(root.iter("Object")):
            origin = {"file": filename, "ordinal": ordinal}
            cls = value(elem, "Class")
            if cls is None:
                ignored.append({"reason": "missing Class", "source": origin, "xml": tree(elem)})
                continue
            type_id = assign(elem)
            if cls in ("PetBehavior", "PetAbility"):
                ignored.append({"reason": cls, "source": origin, "xml": tree(elem)})
                continue
            index("Object", elem, type_id, origin)
            # AddObjects inserts assigned type into ext XML after descriptor
            # construction; ObjectTypeToElement sees that same mutated element.
            if "type" not in elem.attrib and elem.get("ext", "").casefold() == "true":
                elem.set("type", str(type_id))
            key = str(type_id)
            tables["objects"][key] = {"type": type_id, "id": elem.get("id"), "class": cls,
                                      "source": origin, "xml": tree(elem)}
            if cls in ("Equipment", "Dye"):
                tables["items"][key] = item_desc(type_id, elem)
            elif cls in ("Portal", "GuildHallPortal"):
                tables["portals"][key] = {"ObjectType": type_id, "ObjectId": elem.get("id"), "DisplayId": value(elem, "DisplayId", ""),
                                         "NexusPortal": elem.find("NexusPortal") is not None, "DungeonName": value(elem, "DungeonName"),
                                         "TimeoutTime": 70 if elem.get("id") == "The Shatters" else 30}
            elif cls == "Pet":
                tables["pets"][key] = {"ObjectType": type_id, "ObjectId": elem.get("id"), "DisplayId": value(elem, "DisplayId"),
                                      "PetFamily": FAMILIES.index("Unknown" if value(elem, "Family") == "? ? ? ?" else value(elem, "Family")),
                                      "PetRarity": RARITIES.index(value(elem, "Rarity")),
                                      "FirstAbility": None if value(elem, "FirstAbility") is None else ABILITIES[value(elem, "FirstAbility").replace(" ", "")],
                                      "DefaultSkin": value(elem, "DefaultSkin"), "Size": integer(elem, "Size")}
            elif cls == "PetSkin":
                tables["pet_skins"][key] = {"ObjectType": type_id, "ObjectId": elem.get("id"), "DisplayId": value(elem, "DisplayId")}
            else:
                tables["object_descriptors"][key] = object_desc(type_id, elem)
            if elem.find("Player") is not None:
                tables["player_classes"][key] = player_desc(type_id, elem)
            tables["projectiles"][key] = [projectile(p) for p in elem.findall("Projectile")]
        for ordinal, elem in enumerate(root.iter("Ground")):
            type_id = assign(elem)
            origin = {"file": filename, "ordinal": ordinal}
            index("Tile", elem, type_id, origin)
            tables["grounds"][str(type_id)] = {"source": origin, "descriptor": tile_desc(type_id, elem), "xml": tree(elem)}
        for ordinal, elem in enumerate(root.iter("EquipmentSet")):
            type_id = assign(elem)
            key = str(type_id)
            if key in tables["equipment_sets"]:
                duplicates.append({"namespace": "EquipmentSet", "field": "type", "key": key, "source": {"file": filename, "ordinal": ordinal}})
            tables["equipment_sets"][key] = {"source": {"file": filename, "ordinal": ordinal}, "descriptor": set_desc(type_id, elem), "xml": tree(elem)}

    counts = {name: len(table) for name, table in tables.items()}
    counts["projectile_descriptors"] = sum(map(len, tables["projectiles"].values()))
    counts["ignored_objects"] = len(ignored)
    missing = []
    for key, projectiles in tables["projectiles"].items():
        for ordinal, desc in enumerate(projectiles):
            if desc["ObjectId"].casefold() not in indices["IdToObjectType"]:
                missing.append({"kind": "projectile_object", "owner_type": int(key), "index": ordinal, "id": desc["ObjectId"]})
    for key, desc in tables["player_classes"].items():
        for type_id in desc["Equipment"]:
            if type_id != -1 and str(type_id) not in tables["items"]:
                missing.append({"kind": "starter_item", "owner_type": int(key), "type": type_id})
    for key, record in tables["equipment_sets"].items():
        for type_id in record["descriptor"]["Setpiece"].values():
            if str(type_id) not in tables["items"]:
                missing.append({"kind": "set_item", "owner_type": int(key), "type": type_id})
    tables["indices"] = indices
    tables["ignored_objects"] = {"records": ignored}
    tables["manifest"] = {"schema_version": 1, "upstream": UPSTREAM, "source_revision": REVISION,
                          "license": "AGPLv3", "adapted_date": "2026-10-06", "sources": sources,
                          "load_order": list(file_order), "counts": counts, "duplicates": duplicates,
                          "auto_assigned": assigned, "auto_ids": auto, "missing_references": missing,
                          "auto_id_mode": "supplied-map" if auto_ids is not None else "fresh-server-defaults",
                          "runtime_auto_ids_supplied": auto_ids is not None,
                          "enums": {"ConditionEffectIndex": dict(zip(CONDITIONS, range(len(CONDITIONS)))),
                                    "ActivateEffects": dict(zip(ACTIVATIONS, range(len(ACTIVATIONS)))),
                                    "Rarity": dict(zip(RARITIES, range(len(RARITIES)))),
                                    "Family": dict(zip(FAMILIES, range(len(FAMILIES)))), "Ability": ABILITIES},
                          "stat_fields": list(STAT_NAMES),
                          "notes": ["XML file enumeration is unspecified in XmlDatas.cs; this export pins the recorded order.",
                                    "Untyped Addition objects use AutoAssign; existing server autoId.cfg must override fresh defaults.",
                                    "Raw ordered XML metadata is authoritative for client-only fields; no artwork or SWF is included.",
                                    "TileDesc PushY intentionally preserves the upstream Ground dy guard."]}
    return tables


def serialize(table):
    return json.dumps(table, sort_keys=True, ensure_ascii=False, indent=2, allow_nan=False) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=Path(__file__).resolve().parents[2] / "references/fsod/db/data")
    parser.add_argument("--output", type=Path, default=Path(__file__).resolve().parents[2] / "src/data/fsod")
    auto_group = parser.add_mutually_exclusive_group()
    auto_group.add_argument("--auto-id-map", type=Path, help="JSON object matching autoId.cfg name/counter integers; no source modification")
    auto_group.add_argument("--auto-id-config", type=Path, help="Explicit runtime autoId.cfg after backend bootstrap; reads IDs/counters only")
    parser.add_argument("--check", action="store_true", help="Compare deterministic regeneration without writing")
    args = parser.parse_args()
    auto_ids = None if args.auto_id_map is None else json.loads(args.auto_id_map.read_text())
    if args.auto_id_config is not None:
        auto_ids = read_auto_id_config(args.auto_id_config)
    tables = export(args.source, auto_ids=auto_ids)
    if args.auto_id_config is not None:
        tables["manifest"]["auto_id_mode"] = "runtime-autoId.cfg"
    if args.check:
        mismatches = [name for name, table in tables.items() if not (args.output / (name + ".json")).exists() or (args.output / (name + ".json")).read_text() != serialize(table)]
        if mismatches:
            parser.exit(1, "FSOD DATA FAIL: regeneration differs: " + ", ".join(mismatches) + "\n")
    else:
        args.output.mkdir(parents=True, exist_ok=True)
        for name, table in tables.items():
            (args.output / (name + ".json")).write_text(serialize(table), encoding="utf-8")
    print("FSOD DATA PASS " + json.dumps(tables["manifest"]["counts"], sort_keys=True))


if __name__ == "__main__":
    main()

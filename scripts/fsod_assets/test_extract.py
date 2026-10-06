#!/usr/bin/env python3
"""Source-rule unit fixtures; no operator files or live server required."""
import sys
import tempfile
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET

sys.dont_write_bytecode = True
from extract import export, item_desc, object_desc, projectile, set_desc, number, single, read_auto_id_config


class SourceRules(unittest.TestCase):
    def fixture(self, xml, auto_ids=None):
        with tempfile.TemporaryDirectory(prefix="fsod-rule-") as root:
            Path(root, "fixture.xml").write_text(xml)
            return export(root, ("fixture.xml",), auto_ids)

    def test_type_and_case_insensitive_name_overwrites_keep_old_aliases(self):
        result = self.fixture('''<Objects>
          <Object type="0x10" id="Old"><Class>GameObject</Class><Defense>1</Defense></Object>
          <Object type="0x10" id="New"><Class>GameObject</Class><Defense>2</Defense></Object>
          <Object type="0x11" id="new"><Class>GameObject</Class></Object>
        </Objects>''')
        self.assertEqual(result["indices"]["ObjectTypeToId"], {"16": "New", "17": "new"})
        self.assertEqual(result["indices"]["IdToObjectType"], {"old": 16, "new": 17})
        self.assertEqual(result["object_descriptors"]["16"]["Defense"], 2)
        self.assertEqual(len(result["manifest"]["duplicates"]), 2)

    def test_category_dictionary_not_purged_and_source_order_preserved(self):
        result = self.fixture('''<Objects>
          <Object type="8" id="Item"><Class>Equipment</Class><SlotType>9</SlotType><Description>x</Description></Object>
          <Object type="8" id="Wall"><Class>Wall</Class></Object>
          <Object type="9" id="Ignored"/>
          <Object type="10" id="Ability"><Class>PetAbility</Class></Object>
        </Objects>''')
        self.assertEqual(result["objects"]["8"]["id"], "Wall")
        self.assertEqual(result["items"]["8"]["ObjectId"], "Item")
        self.assertEqual(result["object_descriptors"]["8"]["ObjectId"], "Wall")
        self.assertEqual(len(result["ignored_objects"]["records"]), 2)
        self.assertNotIn("ignored", result["indices"]["IdToObjectType"])

    def test_auto_assign_default_and_supplied_ids(self):
        xml = '''<Objects>
          <Object id="Weapon" ext="true"><Class>Equipment</Class><SlotType>1</SlotType><Description>x</Description><Projectile><ObjectId>Shot</ObjectId><LifetimeMS>1</LifetimeMS><Speed>1</Speed><Damage>2</Damage></Projectile></Object>
          <Object id="Armor" ext="true"><Class>Equipment</Class><SlotType>7</SlotType><Description>x</Description></Object>
          <Object id="Enemy" ext="true"><Class>Character</Class></Object>
        </Objects>'''
        result = self.fixture(xml)
        self.assertEqual(result["indices"]["IdToObjectType"], {"weapon": 50000, "armor": 58000, "enemy": 50001})
        self.assertEqual(result["objects"]["50000"]["xml"]["attributes"]["type"], "50000")
        result = self.fixture(xml, {"Weapon": 1234, "nextSigned": 51000, "nextFull": 59000})
        self.assertEqual(result["indices"]["IdToObjectType"], {"weapon": 1234, "armor": 59000, "enemy": 51000})

    def test_ground_duplicate_name_and_push_y_source_bug(self):
        result = self.fixture('''<Grounds><Ground type="1" id="Tile"><Speed>.8</Speed><Push/><Animate dx="1" dy="2"/></Ground><Ground type="2" id="tile"/></Grounds>''')
        self.assertEqual(result["indices"]["IdToTileType"]["tile"], 2)
        ground = result["grounds"]["1"]["descriptor"]
        self.assertEqual(ground["PushX"], 1)
        self.assertEqual(ground["PushY"], 0)  # Ground lacks dy attribute.
        self.assertEqual(ground["Speed"], single(.8))
        self.assertEqual(result["grounds"]["2"]["descriptor"]["Speed"], 0)

    def test_projectile_defaults_repeated_effects_and_fixed_damage(self):
        elem = ET.fromstring('''<Projectile id="2"><ObjectId>Shot</ObjectId><LifetimeMS>150</LifetimeMS><Speed>12.2</Speed><Damage>10</Damage><MultiHit/><Wavy/><ConditionEffect duration="1.5">Armor Broken</ConditionEffect><ConditionEffect>Weak</ConditionEffect></Projectile>''')
        p = projectile(elem)
        self.assertEqual((p["BulletType"], p["MinDamage"], p["MaxDamage"]), (2, 10, 10))
        self.assertEqual((p["Size"], p["Amplitude"], p["Frequency"], p["Magnitude"]), (0, 0, 1, 3))
        self.assertEqual(p["Effects"][0]["Effect"], 26)
        self.assertEqual(p["Effects"][0]["DurationMS"], 1500)
        self.assertEqual(len(p["Effects"]), 2)
        self.assertTrue(p["MultiHit"] and p["Wavy"])
        self.assertFalse(p["PassesCover"])

    def test_item_defaults_stats_and_activation_condition_precedence(self):
        elem = ET.fromstring('''<Object id="Item"><Class>Equipment</Class><SlotType>9</SlotType><Description>x</Description><Tier>UT</Tier><Soulbound/><ActivateOnEquip stat="20" amount="3"/><Activate effect="Weak" condEffect="Slowed" duration="1.1" useWisMod="false">ConditionEffectSelf</Activate></Object>''')
        item = item_desc(10, elem)
        self.assertEqual((item["Tier"], item["SetType"], item["BagType"], item["ArcGap"]), (-1, -1, 0, 11.25))
        self.assertEqual(item["StatsBoost"], [{"stat": 20, "amount": 3}])
        self.assertTrue(item["Soulbound"])
        self.assertIsNone(item["MpEndCost"])
        self.assertEqual(item["ActivateEffects"][0]["ConditionEffect"], 3)
        self.assertEqual(item["ActivateEffects"][0]["DurationMS"], 1100)
        self.assertTrue(item["ActivateEffects"][0]["UseWisMod"])  # Presence, not truth value.

    def test_object_defaults_size_stat_caps_and_last_tag_value(self):
        elem = ET.fromstring('''<Object id="Enemy"><Class>Character</Class><Size>140</Size><SizeStep>10</SizeStep><MaxHitPoints>100</MaxHitPoints><Defense max="25">3</Defense><ParalyzeImmune/><Tag name="t"><A>first</A><A>last</A></Tag></Object>''')
        desc = object_desc(11, elem)
        self.assertEqual((desc["MinSize"], desc["MaxSize"], desc["SizeStep"]), (140, 140, 0))
        self.assertEqual((desc["MaxHP"], desc["MaxHitPoints"], desc["MaxDefense"], desc["MaxAttack"]), (100, -1, 25, 0))
        self.assertEqual(desc["Tags"], [{"Name": "t", "Values": {"A": "last"}}])
        self.assertIsNone(desc["ExpMultiplier"])
        self.assertTrue(desc["ParalyzedImmune"])

    def test_explicit_auto_id_config_and_sanitized_invalid_value(self):
        with tempfile.TemporaryDirectory(prefix="fsod-config-") as root:
            path = Path(root, "autoId.cfg")
            path.write_text("# fixture\nnextSigned:51000\nEnemy:1234\n")
            self.assertEqual(read_auto_id_config(path), {"nextSigned": 51000, "Enemy": 1234})
            path.write_text("Enemy:not-an-id\n")
            with self.assertRaisesRegex(ValueError, "Non-integer autoId setting at line 1") as error:
                read_auto_id_config(path)
            self.assertNotIn("not-an-id", str(error.exception))

    def test_set_skin_first_value_and_int32_hex(self):
        elem = ET.fromstring('''<EquipmentSet id="Set"><Setpiece slot="2" itemtype="0xa0d"/><ActivateOnEquipAll skinType="0x123" stat="20" amount="8"/><ActivateOnEquipAll skinType="0x456"/></EquipmentSet>''')
        desc = set_desc(1, elem)
        self.assertEqual(desc["SkinType"], 0x123)
        self.assertEqual(desc["Setpiece"], {"2": 0xa0d})
        self.assertEqual(desc["StatsBoost"], [{"stat": 20, "amount": 8}])
        self.assertEqual(number("0xffffffff"), -1)


if __name__ == "__main__":
    unittest.main()

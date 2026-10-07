"""Synthetic negative-control unit tests; these are NOT live gameplay proof."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import verify as v


class ProofTests(unittest.TestCase):
    result = {'exit_code': 0, 'timed_out': False}
    logs = {
        'recovery': 'FSOD LIVE REALM NexusPortal.Cube\nFSOD LIVE DEATH original_server=true visited_realm=true xp=0\nFSOD LIVE FRAME 07-original-recovery 1280x720\nFSOD LIVE RECOVERY PASS dead_character_id=1 new_character_id=2 original_server=true',
        'combat': 'FSOD LIVE REALM NexusPortal.Cube\nFSOD LIVE FRAME 04-original-combat 1280x720\nFSOD LIVE COMBAT PASS realm=true original_server_xp=25 hp=100 ticks=625 frames=4',
        'damage': 'FSOD LIVE REALM NexusPortal.Cube\nFSOD LIVE FRAME 05-original-damage 1280x720\nFSOD LIVE DAMAGE PASS original_server_hp=93 maximum=100 realm=true',
        'loot': 'FSOD LIVE REALM NexusPortal.Cube\nFSOD LIVE FRAME 06-original-loot 1280x720\nFSOD LIVE LOOT REQUEST source_bag=304321 type=2569 destination_slot=4; awaiting actual server snapshot\nFSOD LIVE LOOT PASS original_server_item=2569 inventory_slot=4 source_bag=304321',
    }

    def test_valid_fixtures(self):
        for kind, log in self.logs.items(): v.validate_run(kind, self.result, log)

    def test_result_file_presence_is_not_success(self):
        with self.assertRaises(ValueError): v.validate_run('combat', {}, self.logs['combat'])

    def test_deadline_rejected_even_with_marker(self):
        with self.assertRaises(ValueError): v.validate_run('combat', {'exit_code': 0, 'timed_out': True}, self.logs['combat'])

    def test_failure_exit_rejected_even_with_marker(self):
        with self.assertRaises(ValueError): v.validate_run('combat', {'exit_code': 1, 'timed_out': False}, self.logs['combat'])

    def test_script_error_rejected(self):
        with self.assertRaises(ValueError): v.validate_run('loot', self.result, self.logs['loot'] + '\nSCRIPT ERROR: bad method')

    def test_realm_only_is_not_combat(self):
        with self.assertRaises(ValueError): v.validate_run('combat', self.result, 'FSOD LIVE REALM NexusPortal.Cube')

    def test_headless_zero_frames_is_not_render_proof(self):
        with self.assertRaises(ValueError): v.validate_run('combat', self.result, self.logs['combat'].replace('frames=4', 'frames=0'))

    def test_missing_damage_frame_rejected(self):
        with self.assertRaises(ValueError): v.validate_run('damage', self.result, self.logs['damage'].replace('FSOD LIVE FRAME 05-original-damage 1280x720\n', ''))

    def test_loot_requires_request_and_readback(self):
        with self.assertRaises(ValueError): v.validate_run('loot', self.result, self.logs['loot'].replace('FSOD LIVE LOOT REQUEST', 'NOT A REQUEST'))

    def test_dead_character_cannot_be_reused(self):
        with self.assertRaises(ValueError): v.validate_run('recovery', self.result, self.logs['recovery'].replace('new_character_id=2', 'new_character_id=1'))

    def test_recovery_requires_real_death(self):
        with self.assertRaises(ValueError): v.validate_run('recovery', self.result, self.logs['recovery'].replace('FSOD LIVE DEATH', 'NOT DEATH'))

    def test_png_header_dimensions(self):
        with tempfile.TemporaryDirectory() as tmp:
            png = Path(tmp) / 'frame.png'
            png.write_bytes(b'\x89PNG\r\n\x1a\n' + b'\0\0\0\rIHDR' + (1280).to_bytes(4, 'big') + (720).to_bytes(4, 'big'))
            self.assertEqual(v.png_dimensions(png), (1280, 720))
            png.write_text('not a picture')
            with self.assertRaises(ValueError): v.png_dimensions(png)

    def test_stale_head_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            record = Path(tmp) / 'record.json'
            record.write_text(json.dumps({'head': 'old', 'source_sha256': {}}))
            with patch.object(v, 'RECORD', record), patch.object(v, 'head', return_value='new'):
                with self.assertRaisesRegex(ValueError, 'stale'): v.verify()

    def test_uncommitted_source_change_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            record = Path(tmp) / 'record.json'
            record.write_text(json.dumps({'head': 'same', 'source_sha256': {'game.gd': 'old'}}))
            with patch.object(v, 'RECORD', record), patch.object(v, 'head', return_value='same'), patch.object(v, 'source_hashes', return_value={'game.gd': 'new'}):
                with self.assertRaisesRegex(ValueError, 'stale'): v.verify()


if __name__ == '__main__': unittest.main()

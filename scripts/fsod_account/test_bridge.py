#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
# Fixture tests for the local FSoD bridge; no original service/DB required.
import contextlib
import io
import json
import os
import struct
import threading
import unittest
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from unittest.mock import patch

import bridge

ACCOUNT = b'<Account><AccountId>42</AccountId><VerifiedEmail/><AuthToken>fixture-only</AuthToken><Password>fixture-only</Password><Name>fixture-only</Name></Account>'
CHARS = b'<Chars xmlns="rotmg" nextCharId="4" maxNumChars="2"><Account><AccountId>42</AccountId><VerifiedEmail/></Account><Char id="3"><ObjectType>782</ObjectType><Level>1</Level><Equipment>fixture-only</Equipment></Char><Servers><Server><DNS>do-not-follow.invalid</DNS></Server></Servers></Chars>'


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_args):
        pass

    def do_POST(self):
        data = self.rfile.read(int(self.headers['Content-Length']))
        self.server.requests.append((self.path, urllib.parse.parse_qs(data.decode(), keep_blank_values=True), self.headers['Content-Type']))
        code, body, headers = self.server.responses.get(self.path, (200, b'<Error>fixture-only</Error>', {}))
        self.send_response(code)
        for name, value in headers.items():
            self.send_header(name, value)
        self.end_headers()
        self.wfile.write(body)


@contextlib.contextmanager
def fixture(responses):
    server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    server.daemon_threads = True
    server.responses = responses
    server.requests = []
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        yield server, f'http://127.0.0.1:{server.server_port}'
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)
        if thread.is_alive():
            raise AssertionError('fixture server failed to stop')


class BridgeTests(unittest.TestCase):
    def assert_error(self, code, function, *args, **kwargs):
        with self.assertRaises(bridge.BridgeError) as error:
            function(*args, **kwargs)
        self.assertEqual(str(error.exception), code)

    def test_loopback_canonicalization(self):
        for value, expected in [
            ('http://localhost:8080/', 'http://127.0.0.1:8080'),
            ('http://127.0.0.1:1234', 'http://127.0.0.1:1234'),
            ('http://127.2.3.4', 'http://127.2.3.4:80'),
            ('http://[::1]:8088', 'http://[::1]:8088'),
        ]:
            self.assertEqual(bridge.loopback_url(value), expected)

    def test_reject_nonloopback_and_url_escapes(self):
        for value in [
            'https://127.0.0.1', 'http://example.com', 'http://192.168.1.2',
            'http://0.0.0.0', 'http://[::]', 'http://[::ffff:127.0.0.1]',
            'http://2130706433', 'http://127.1', 'http://0177.0.0.1',
            'http://localhost.evil.invalid', 'http://localhost@evil.invalid',
            'http://user:fixture-only@127.0.0.1', 'http://127.0.0.1/a',
            'http://127.0.0.1?token=fixture-only', 'http://127.0.0.1#x',
            'http://[::1%lo]:80', 'http://127.0.0.1:0', 'http://127.0.0.1:65536',
            ' http://127.0.0.1', 'http://127.0.0.1\n', 'file:///tmp/account',
            'http://127.0.0.1\\@evil.invalid', 'http://[::1',
        ]:
            with self.subTest(value=value):
                self.assert_error('invalid_loopback_url', bridge.loopback_url, value)

    def test_metadata_allowlist_and_namespace(self):
        self.assertEqual(bridge.account_metadata(bridge._xml(ACCOUNT)), {'account_id': 42, 'verified_email': True})
        metadata = bridge.characters_metadata(bridge._xml(CHARS))
        self.assertEqual(metadata, {'account': {'account_id': 42, 'verified_email': True}, 'next_char_id': 4, 'max_char_slots': 2, 'count': 1, 'characters': [{'id': 3, 'object_type': 782, 'level': 1}]})
        self.assertNotIn('fixture-only', json.dumps(metadata))
        self.assertNotIn('do-not-follow', json.dumps(metadata))
        self.assertFalse(bridge.account_metadata(bridge._xml(b'<Account><AccountId>1</AccountId></Account>'))['verified_email'])
        self.assertEqual(bridge.characters_metadata(bridge._xml(b'<Chars nextCharId="1" maxNumChars="2"><Account><AccountId>1</AccountId></Account></Chars>'))['count'], 0)

    def test_invalid_xml_and_error_redaction(self):
        for body, code in [
            (b'<Error>fixture-only</Error>', 'backend_error'),
            (b'', 'invalid_response_size'),
            (b'x' * (bridge.MAX_RESPONSE_BYTES + 1), 'invalid_response_size'),
            (b'<html>stacktrace fixture-only', 'malformed_response'),
            (b'\xff', 'malformed_response'),
            (b'<!DOCTYPE a [<!ENTITY x "fixture-only">]><a>&x;</a>', 'unsafe_xml'),
            ('<Account/>'.encode('utf-16'), 'malformed_response'),
            (b'<Account>\x00</Account>', 'unsafe_xml'),
            (b'<Account xmlns="evil"/>', 'unexpected_namespace'),
        ]:
            self.assert_error(code, bridge._xml, body)

    def test_invalid_metadata_schema(self):
        for body in [
            b'<Account/>',
            b'<Account><AccountId>fixture-only</AccountId></Account>',
            b'<Account><AccountId>-1</AccountId></Account>',
            b'<Account><AccountId>0</AccountId></Account>',
            b'<Account><AccountId>1</AccountId><AccountId>2</AccountId></Account>',
            b'<Account><AccountId>9223372036854775808</AccountId></Account>',
        ]:
            self.assert_error('invalid_response_schema', bridge.account_metadata, bridge._xml(body))
        duplicated = CHARS.replace(b'</Chars>', b'<Char id="3"><ObjectType>782</ObjectType><Level>1</Level></Char></Chars>')
        self.assert_error('invalid_response_schema', bridge.characters_metadata, bridge._xml(duplicated))
        self.assert_error('unexpected_response', bridge.characters_metadata, bridge._xml(b'<Success/>'))

    def test_bootstrap_real_http_fixture(self):
        responses = {'/account/register': (200, b'<Success/>', {}), '/account/verify': (200, ACCOUNT, {}), '/char/list': (200, CHARS, {})}
        with fixture(responses) as (server, url):
            with patch.dict(os.environ, {'http_proxy': 'http://192.0.2.1:9', 'HTTP_PROXY': 'http://192.0.2.1:9', 'no_proxy': '', 'NO_PROXY': ''}):
                result = bridge.Client(url).bootstrap('fixture-only', mail_disabled=True, local_server_list=True)
            self.assertEqual(result['account']['account_id'], 42)
            self.assertFalse(result['game_session_tested'])
            self.assertRegex(result['guid'], r'^fsod-dev-[0-9a-f]{32}@gmail\.invalid$')
            self.assertNotIn('fixture-only', json.dumps(result))
            self.assertEqual([request[0] for request in server.requests], ['/account/register', '/account/verify', '/char/list'])
            fields = server.requests[0][1]
            self.assertEqual(set(fields), {'ignore', 'guid', 'newGUID', 'newPassword', 'entrytag', 'isAgeVerified'})
            self.assertEqual(fields['entrytag'], [''])
            self.assertEqual(fields['newGUID'], [result['guid']])
            self.assertEqual(fields['newPassword'], ['fixture-only'])
            for path, fields, content_type in server.requests:
                self.assertNotIn('?', path)
                self.assertEqual(content_type, 'application/x-www-form-urlencoded')
            self.assertEqual(server.requests[1][1], {'guid': [result['guid']], 'password': ['fixture-only']})

    def test_redirect_refused_without_following(self):
        with fixture({'/account/verify': (302, b'', {'Location': 'http://192.0.2.1:9/?token=fixture-only'})}) as (server, url):
            self.assert_error('redirect_refused', bridge.Client(url).verify, 'dev@gmail.invalid', 'fixture-only')
            self.assertEqual(len(server.requests), 1)

    def test_http_status_and_body_errors_are_sanitized(self):
        for code, body, expected in [(500, b'fixture-only', 'request_failed'), (200, b'<Error>fixture-only</Error>', 'backend_error'), (200, b'<Success/>', 'unexpected_response')]:
            with fixture({'/account/verify': (code, body, {})}) as (_server, url):
                self.assert_error(expected, bridge.Client(url).verify, 'dev@gmail.invalid', 'fixture-only')

    def test_registration_requires_mail_attestation(self):
        client = bridge.Client()
        with patch.object(client, '_request') as request:
            self.assert_error('mail_disabled_attestation_required', client.register_dev, 'fixture-only')
            self.assert_error('local_server_list_attestation_required', client.characters, 'dev@gmail.invalid', 'fixture-only')
            self.assert_error('local_server_list_attestation_required', client.bootstrap, 'fixture-only', mail_disabled=True)
            request.assert_not_called()
        self.assert_error('endpoint_refused', client._request, '/admin/performCommand', {})

    def test_timeout_and_credentials_rejected_before_io(self):
        for timeout in [0, -1, float('nan'), float('inf'), 31]:
            self.assert_error('invalid_timeout', bridge.Client, timeout=timeout)
        client = bridge.Client()
        with patch.object(client, '_request') as request:
            for guid, password, code in [('x\n', 'fixture-only', 'invalid_guid'), ('valid', '', 'invalid_password'), ('valid', 'x' * 1025, 'invalid_password'), ('valid', 'x\n', 'invalid_password')]:
                self.assert_error(code, client.verify, guid, password)
            request.assert_not_called()

    def test_character_payloads_not_transports(self):
        self.assertEqual(bridge.create_body(), b'\x03\x0e\x00\x00')
        self.assertEqual(bridge.create_body(65535, 65535), struct.pack('>HH', 65535, 65535))
        self.assertEqual(bridge.load_body(3), b'\x00\x00\x00\x03\x00')
        self.assertEqual(bridge.load_body(3, True), b'\x00\x00\x00\x03\x01')
        for values in [(-1, 0), (65536, 0), (True, 0), (1.0, 0)]:
            self.assert_error('invalid_character_fields', bridge.create_body, *values)
        for value in [0, -1, 2147483648, True, '1']:
            self.assert_error('invalid_character_fields', bridge.load_body, value)

    def test_cli_validation_and_redaction(self):
        for argv, code in [
            (['--base-url', 'http://user:fixture-only@example.com', 'create-body'], 'invalid_loopback_url'),
            (['bootstrap'], 'mail_disabled_attestation_required'),
            (['bootstrap', '--mail-disabled'], 'local_server_list_attestation_required'),
            (['chars', '--guid', 'dev@gmail.invalid'], 'local_server_list_attestation_required'),
            (['--unknown', 'fixture-only'], 'invalid_arguments'),
            (['create-body', '--class-type', 'fixture-only'], 'invalid_arguments'),
            (['--timeout', 'nan', 'create-body'], 'invalid_timeout'),
        ]:
            with contextlib.redirect_stdout(io.StringIO()) as out:
                self.assertEqual(bridge.main(argv), 2)
            self.assertEqual(json.loads(out.getvalue()), {'ok': False, 'error': code})
            self.assertNotIn('fixture-only', out.getvalue())
        with contextlib.redirect_stdout(io.StringIO()) as out:
            self.assertEqual(bridge.main(['load-body', '--character-id', '3']), 0)
        self.assertEqual(json.loads(out.getvalue())['body_hex'], '0000000300')

    def test_cli_password_stdin_real_fixture(self):
        with fixture({'/account/verify': (200, ACCOUNT, {})}) as (_server, url):
            with patch('sys.stdin', io.StringIO('fixture-only\n')), contextlib.redirect_stdout(io.StringIO()) as out:
                code = bridge.main(['--base-url', url, 'verify', '--guid', 'dev@gmail.invalid', '--password-stdin'])
            self.assertEqual(code, 0)
            self.assertNotIn('fixture-only', out.getvalue())


class PublicEncryptionTests(unittest.TestCase):
    def test_source_key_is_public_protocol_key(self):
        import base64
        import rsa_public
        from cryptography.hazmat.primitives import serialization
        key = serialization.load_pem_public_key(rsa_public.PUBLIC_KEY_PEM)
        self.assertEqual(key.key_size, 1024)
        self.assertEqual(key.public_numbers().e, 65537)
        first = rsa_public.encrypt('offline-fixture')
        second = rsa_public.encrypt('offline-fixture')
        self.assertEqual(len(base64.b64decode(first, validate=True)), 128)
        self.assertNotEqual(first, second)  # Real randomized PKCS#1 padding.
        self.assertEqual(rsa_public.encrypt(''), '')
        self.assertEqual(len(base64.b64decode(rsa_public.encrypt('x' * 117))), 128)
        with self.assertRaises(rsa_public.EncryptionError):
            rsa_public.encrypt('x' * 118)
        with self.assertRaises(rsa_public.EncryptionError):
            rsa_public.encrypt('\u00e9' * 59)  # Length limit is UTF-8 bytes.

    def test_pkcs1_server_format_roundtrip_with_generated_fixture_key(self):
        import base64
        import rsa_public
        from cryptography.hazmat.primitives import serialization
        from cryptography.hazmat.primitives.asymmetric import padding, rsa
        private = rsa.generate_private_key(public_exponent=65537, key_size=1024)
        public = private.public_key().public_bytes(serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo)
        for plaintext in ['offline-fixture', '\u00e9\u6f22']:
            encrypted = rsa_public.encrypt(plaintext, public)
            self.assertEqual(private.decrypt(base64.b64decode(encrypted), padding.PKCS1v15()).decode('utf-8'), plaintext)
        # This private key is generated in memory for this test only, not FSoD's.

    def test_json_stdin_ciphertext_only_and_errors(self):
        import rsa_public
        cases = [
            ('{broken', 'invalid_input'),
            ('{"guid": "fixture-only", "password": null}', 'invalid_plaintext'),
            ('{"guid":"fixture-only","password":"x","token":"x"}', 'invalid_input'),
            ('{"guid":"x","guid":"y","password":"x"}', 'invalid_input'),
            ('x' * 4097, 'input_too_large'),
        ]
        for payload, code in cases:
            with patch('sys.stdin', io.StringIO(payload)), contextlib.redirect_stdout(io.StringIO()) as out:
                self.assertEqual(rsa_public.main(), 2)
            self.assertEqual(json.loads(out.getvalue()), {'ok': False, 'error': code})
            self.assertNotIn('fixture-only', out.getvalue())
        with patch('sys.stdin', io.StringIO('{"guid":"fixture-only","password":"fixture-only"}')), contextlib.redirect_stdout(io.StringIO()) as out:
            self.assertEqual(rsa_public.main(), 0)
        result = json.loads(out.getvalue())
        self.assertEqual(set(result), {'guid_ciphertext', 'password_ciphertext'})
        self.assertNotIn('fixture-only', out.getvalue())

    def test_library_required_no_raw_rsa_fallback(self):
        import rsa_public
        import sys
        with patch.dict(sys.modules, {'cryptography.hazmat.primitives': None}):
            with self.assertRaises(rsa_public.EncryptionError) as error:
                rsa_public.encrypt('offline-fixture')
        self.assertEqual(str(error.exception), 'cryptography_dependency_required')


class LoginProfileTests(unittest.TestCase):
    def test_profile_keys_permissions_and_plaintext_absence(self):
        import tempfile
        from pathlib import Path
        import login_profile
        with tempfile.TemporaryDirectory(prefix='fsod-profile-') as temporary:
            directory = Path(temporary) / '.private'
            path = Path(login_profile.write_profile('fixture-guid', 'fixture-password', private_dir=directory))
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            self.assertEqual(directory.stat().st_mode & 0o777, 0o700)
            text = path.read_text()
            self.assertNotIn('fixture-guid', text)
            self.assertNotIn('fixture-password', text)
            profile = json.loads(text)
            self.assertEqual(set(profile), {'host', 'port', 'character_id', 'class_type', 'skin_type', 'hello'})
            self.assertEqual((profile['host'], profile['port'], profile['character_id'], profile['class_type'], profile['skin_type']), ('127.0.0.1', 2050, -1, 782, 0))
            hello = profile['hello']
            self.assertEqual(set(hello), {'BuildVersion', 'GameId', 'GUID', 'IgnoredInt', 'Password', 'Secret', 'randomint1', 'KeyTime', 'Key', 'MapInfo', 'obf1', 'obf2', 'obf3', 'obf4', 'obf5'})
            self.assertEqual(hello['BuildVersion'], '27.3.2')
            self.assertEqual(hello['GameId'], -2)
            self.assertEqual(hello['IgnoredInt'], 0)
            self.assertEqual(hello['Key'], [])
            self.assertEqual(hello['MapInfo'], [])
            second = Path(login_profile.write_profile('fixture-guid', 'fixture-password', 3, private_dir=directory))
            self.assertNotEqual(path, second)
            self.assertEqual(json.loads(second.read_text())['character_id'], 3)

    def test_profile_refuses_symlink_and_invalid_characters(self):
        import tempfile
        from pathlib import Path
        import login_profile
        for value in [-2, 0, 2147483648, True]:
            with self.assertRaises(login_profile.ProfileError):
                login_profile.profile_data('fixture-guid', 'fixture-password', value)
        with tempfile.TemporaryDirectory(prefix='fsod-profile-') as temporary:
            target = Path(temporary) / 'target'
            target.mkdir()
            link = Path(temporary) / '.private'
            link.symlink_to(target, target_is_directory=True)
            with self.assertRaises(login_profile.ProfileError):
                login_profile.write_profile('fixture-guid', 'fixture-password', private_dir=link)
            self.assertEqual(list(target.iterdir()), [])

    def test_bootstrap_profile_cli_outputs_metadata_only(self):
        import tempfile
        from pathlib import Path
        import login_profile
        responses = {'/account/register': (200, b'<Success/>', {}), '/account/verify': (200, ACCOUNT, {}), '/char/list': (200, CHARS, {})}
        with tempfile.TemporaryDirectory(prefix='fsod-profile-') as temporary, fixture(responses) as (_server, url):
            original_writer = login_profile.write_profile
            def writer(*args):
                return original_writer(*args, private_dir=Path(temporary) / '.private')
            with patch.object(login_profile, 'write_profile', side_effect=writer), patch('sys.stdin', io.StringIO('fixture-password\n')), contextlib.redirect_stdout(io.StringIO()) as out:
                code = bridge.main(['--base-url', url, 'bootstrap', '--mail-disabled', '--local-server-list', '--password-stdin', '--profile'])
            self.assertEqual(code, 0)
            result = json.loads(out.getvalue())
            self.assertTrue(Path(result['profile_path']).is_absolute())
            self.assertNotIn('guid', result)
            self.assertNotIn('fixture-password', out.getvalue())
            self.assertNotIn('GUID', out.getvalue())
            self.assertNotIn('Password', out.getvalue())
            self.assertNotIn('ciphertext', out.getvalue())

    def test_existing_profile_character_must_be_listed_and_preflight(self):
        responses = {'/account/verify': (200, ACCOUNT, {}), '/char/list': (200, CHARS, {})}
        with fixture(responses) as (server, url):
            with patch('sys.stdin', io.StringIO('fixture-password\n')), contextlib.redirect_stdout(io.StringIO()) as out:
                code = bridge.main(['--base-url', url, 'profile', '--guid', 'dev@gmail.invalid', '--local-server-list', '--password-stdin', '--character-id', '99'])
            self.assertEqual(code, 2)
            self.assertEqual(json.loads(out.getvalue())['error'], 'character_not_listed')
            server.requests.clear()
            with patch('sys.stdin', io.StringIO('x' * 118 + '\n')), contextlib.redirect_stdout(io.StringIO()) as out:
                code = bridge.main(['--base-url', url, 'bootstrap', '--mail-disabled', '--local-server-list', '--password-stdin', '--profile'])
            self.assertEqual(code, 2)
            self.assertEqual(json.loads(out.getvalue())['error'], 'plaintext_too_long')
            self.assertEqual(server.requests, [])


if __name__ == '__main__':
    unittest.main(verbosity=2)

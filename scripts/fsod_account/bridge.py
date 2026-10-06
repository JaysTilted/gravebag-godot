#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
# Original Python bridge, following FSoD endpoint/protocol definitions at
# 6fd20aad4a7905b13f25389c68368a942a2b68cb (ossimc82/Fabian Fischer et al.).
# Sources: server/account/{register,verify}.cs, server/char/list.cs,
# db/Models.cs, wServer/networking/cliPackets/{Create,Load}Packet.cs.
# See LICENSE and plans/fsod-account-integration.md. No cipher/private keys copied.
"""Loopback-only account bootstrap; character payload helpers are NOT transport."""

import argparse
import getpass
import ipaddress
import json
import math
import re
import struct
import sys
import urllib.error
import urllib.parse
import urllib.request
import uuid
import xml.etree.ElementTree as ET

SOURCE_REVISION = "6fd20aad4a7905b13f25389c68368a942a2b68cb"
DEFAULT_BASE_URL = "http://127.0.0.1:8080"
MAX_RESPONSE_BYTES = 1024 * 1024
ENDPOINTS = frozenset(("/account/register", "/account/verify", "/char/list"))


class BridgeError(Exception):
    """Only fixed codes may cross the output boundary; never server/URL bodies."""


class SafeParser(argparse.ArgumentParser):
    def error(self, message):
        raise BridgeError("invalid_arguments")


def loopback_url(value):
    """Canonical literal destination: no DNS, credentials, proxy or URL suffix."""
    if not isinstance(value, str) or any(c.isspace() or ord(c) < 32 for c in value):
        raise BridgeError("invalid_loopback_url")
    try:
        parsed = urllib.parse.urlsplit(value)
        port = parsed.port
        host = parsed.hostname
        if (parsed.scheme != "http" or parsed.username is not None
                or parsed.password is not None or parsed.path not in ("", "/")
                or parsed.query or parsed.fragment or not host):
            raise ValueError()
        if host == "localhost":
            host = "127.0.0.1"  # Avoid even localhost DNS/rebinding.
        address = ipaddress.ip_address(host)
        if not address.is_loopback or "%" in host or getattr(address, "ipv4_mapped", None):
            raise ValueError()
        if port is not None and not 1 <= port <= 65535:
            raise ValueError()
        literal = f"[{address}]" if address.version == 6 else str(address)
        return f"http://{literal}:{port if port is not None else 80}"
    except (ValueError, TypeError):
        raise BridgeError("invalid_loopback_url") from None


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise BridgeError("redirect_refused")


def _timeout(value):
    if not isinstance(value, (float, int)) or not math.isfinite(value) or not 0.1 <= value <= 30:
        raise BridgeError("invalid_timeout")
    return float(value)


def _credentials(guid, password):
    if not isinstance(guid, str) or re.fullmatch(r"[A-Za-z0-9._+@-]{1,128}", guid) is None:
        raise BridgeError("invalid_guid")
    if (not isinstance(password, str) or not 1 <= len(password) <= 1024
            or any(ord(c) < 32 or ord(c) == 127 for c in password)):
        raise BridgeError("invalid_password")


class Client:
    def __init__(self, base_url=DEFAULT_BASE_URL, timeout=5.0):
        self.base_url = loopback_url(base_url)
        self.timeout = _timeout(timeout)
        self._opener = urllib.request.build_opener(
            urllib.request.ProxyHandler({}), NoRedirect())

    def _request(self, path, fields):
        if path not in ENDPOINTS:
            raise BridgeError("endpoint_refused")
        # POST only: credentials never enter access-log URLs.
        request = urllib.request.Request(
            self.base_url + path,
            data=urllib.parse.urlencode(fields).encode("utf-8"),
            headers={"Content-Type": "application/x-www-form-urlencoded", "Accept": "application/xml"},
            method="POST",
        )
        try:
            with self._opener.open(request, timeout=self.timeout) as response:
                if response.status != 200:
                    raise BridgeError("http_error")
                body = response.read(MAX_RESPONSE_BYTES + 1)
        except BridgeError:
            raise
        except (urllib.error.URLError, OSError, ValueError):
            raise BridgeError("request_failed") from None
        return _xml(body)

    def register_dev(self, password, *, mail_disabled=False):
        # Attestation is mandatory: the original register endpoint can send mail.
        # This flag does NOT alter backend configuration or disable authentication.
        if mail_disabled is not True:
            raise BridgeError("mail_disabled_attestation_required")
        suffix = uuid.uuid4().hex
        guid = f"fsod-dev-{suffix}@gmail.invalid"
        _credentials(guid, password)
        # Source register checks exactly six keys; fresh guest avoids its broken
        # existing-account upgrade SQL. gmail.invalid passes its domain-label
        # whitelist but is deliberately not a real mailbox.
        root = self._request("/account/register", {
            "ignore": "true", "guid": f"fsod-guest-{suffix}",
            "newGUID": guid, "newPassword": password,
            "entrytag": "", "isAgeVerified": "true",
        })
        if _tag(root) != "Success":
            raise BridgeError("unexpected_response")
        return guid

    def verify(self, guid, password):
        _credentials(guid, password)
        root = self._request("/account/verify", {"guid": guid, "password": password})
        if _tag(root) != "Account":
            raise BridgeError("unexpected_response")
        return account_metadata(root)

    def characters(self, guid, password, *, local_server_list=False):
        # Original char/list can geocode/probe configured nonlocal server entries.
        # Require runtime attestation before asking it to enumerate any servers.
        if local_server_list is not True:
            raise BridgeError("local_server_list_attestation_required")
        _credentials(guid, password)
        return characters_metadata(self._request("/char/list", {"guid": guid, "password": password}))

    def bootstrap(self, password, *, mail_disabled=False, local_server_list=False):
        if local_server_list is not True:
            raise BridgeError("local_server_list_attestation_required")
        guid = self.register_dev(password, mail_disabled=mail_disabled)
        account = self.verify(guid, password)
        characters = self.characters(guid, password, local_server_list=local_server_list)
        if account["account_id"] != characters["account"]["account_id"]:
            raise BridgeError("account_mismatch")
        return {"ok": True, "operation": "bootstrap", "guid": guid,
                "account": account, "characters": characters,
                "game_session_tested": False, "source_revision": SOURCE_REVISION}


def _tag(element):
    tag = element.tag
    if tag.startswith("{"):
        namespace, tag = tag[1:].split("}", 1)
        if namespace != "rotmg":
            raise BridgeError("unexpected_namespace")
    return tag


def _xml(body):
    if not isinstance(body, bytes) or not body or len(body) > MAX_RESPONSE_BYTES:
        raise BridgeError("invalid_response_size")
    # The original endpoints use UTF-8 XML. Reject DTD/entities before parsing,
    # including UTF-16/NUL attempts that could evade a byte-level declaration scan.
    try:
        text = body.decode("utf-8-sig")
    except UnicodeError:
        raise BridgeError("malformed_response") from None
    if "\x00" in text or "<!DOCTYPE" in text.upper() or "<!ENTITY" in text.upper():
        raise BridgeError("unsafe_xml")
    try:
        root = ET.fromstring(text)
    except (ET.ParseError, ValueError):
        raise BridgeError("malformed_response") from None
    if _tag(root) == "Error":
        # Never echo original error text: it may contain tokens/passwords.
        raise BridgeError("backend_error")
    return root


def _child(root, name, required=True):
    matches = [item for item in root if _tag(item) == name]
    if len(matches) > 1 or (required and not matches):
        raise BridgeError("invalid_response_schema")
    return matches[0] if matches else None


def _integer(value, minimum=0, maximum=2147483647):
    if not isinstance(value, str) or re.fullmatch(r"[0-9]{1,20}", value) is None:
        raise BridgeError("invalid_response_schema")
    number = int(value)
    if not minimum <= number <= maximum:
        raise BridgeError("invalid_response_schema")
    return number


def account_metadata(root):
    if _tag(root) != "Account":
        raise BridgeError("unexpected_response")
    # Allowlist only numeric identifiers + boolean presence; no Names, passwords,
    # tokens, URLs, arbitrary text, vaults, credit/admin values or raw XML.
    account_id = _integer(_child(root, "AccountId").text, minimum=1, maximum=9223372036854775807)
    return {"account_id": account_id,
            "verified_email": _child(root, "VerifiedEmail", required=False) is not None}


def characters_metadata(root):
    if _tag(root) != "Chars":
        raise BridgeError("unexpected_response")
    characters = []
    seen = set()
    for item in root:
        if _tag(item) == "Char":
            char_id = _integer(item.get("id"), minimum=1)
            if char_id in seen:
                raise BridgeError("invalid_response_schema")
            seen.add(char_id)
            characters.append({"id": char_id,
                               "object_type": _integer(_child(item, "ObjectType").text, maximum=65535),
                               "level": _integer(_child(item, "Level").text, minimum=1)})
    return {"account": account_metadata(_child(root, "Account")),
            "next_char_id": _integer(root.get("nextCharId"), minimum=1),
            "max_char_slots": _integer(root.get("maxNumChars")),
            "count": len(characters), "characters": characters}


def create_body(class_type=782, skin_type=0):
    """CREATE=78 body only (two network-order ushort fields); default Wizard."""
    if any(type(value) is not int or not 0 <= value <= 65535 for value in (class_type, skin_type)):
        raise BridgeError("invalid_character_fields")
    return struct.pack(">HH", class_type, skin_type)


def load_body(character_id, from_arena=False):
    """LOAD=8 body only: signed network-order int32 + one boolean byte."""
    if type(character_id) is not int or not 1 <= character_id <= 2147483647 or type(from_arena) is not bool:
        raise BridgeError("invalid_character_fields")
    return struct.pack(">i?", character_id, from_arena)


def _password(args):
    if args.password_stdin:
        password = sys.stdin.readline(1026)
        if password.endswith("\n"):
            password = password[:-1]
            if password.endswith("\r"):
                password = password[:-1]
    elif sys.stdin.isatty():
        password = getpass.getpass("Local dev account password: ")
    else:
        raise BridgeError("password_stdin_required")
    return password


def main(argv=None):
    try:
        parser = SafeParser(description=__doc__)
        parser.add_argument("--base-url", default=DEFAULT_BASE_URL)
        parser.add_argument("--timeout", type=float, default=5.0)
        commands = parser.add_subparsers(dest="command", required=True, parser_class=SafeParser)
        for name in ("bootstrap", "verify", "chars", "profile"):
            command = commands.add_parser(name)
            command.add_argument("--password-stdin", action="store_true")
            if name == "bootstrap":
                command.add_argument("--mail-disabled", action="store_true")
            else:
                command.add_argument("--guid", required=True)
            if name in ("bootstrap", "chars", "profile"):
                command.add_argument("--local-server-list", action="store_true")
            if name == "bootstrap":
                command.add_argument("--profile", action="store_true")
            if name in ("bootstrap", "profile"):
                command.add_argument("--character-id", type=int, default=-1)
                command.add_argument("--class-type", type=int, default=782)
                command.add_argument("--skin-type", type=int, default=0)
        create = commands.add_parser("create-body")
        create.add_argument("--class-type", type=int, default=782)
        create.add_argument("--skin-type", type=int, default=0)
        load = commands.add_parser("load-body")
        load.add_argument("--character-id", type=int, required=True)
        load.add_argument("--from-arena", action="store_true")
        args = parser.parse_args(argv)
        client = Client(args.base_url, args.timeout)  # Validate CLI URL even for pure helpers.
        if args.command == "create-body":
            result = {"ok": True, "packet_id": 78, "body_hex": create_body(args.class_type, args.skin_type).hex(), "transport": False}
        elif args.command == "load-body":
            result = {"ok": True, "packet_id": 8, "body_hex": load_body(args.character_id, args.from_arena).hex(), "transport": False}
        else:
            if args.command == "bootstrap" and not args.mail_disabled:
                raise BridgeError("mail_disabled_attestation_required")
            if args.command in ("bootstrap", "chars", "profile") and not args.local_server_list:
                raise BridgeError("local_server_list_attestation_required")
            password = _password(args)
            wants_profile = args.command == "profile" or (args.command == "bootstrap" and args.profile)
            if wants_profile:
                from login_profile import ProfileError, profile_data
                try:
                    profile_data(args.guid if args.command == "profile" else "fsod-dev-preflight@gmail.invalid",
                                 password, args.character_id, args.class_type, args.skin_type)
                except ProfileError as error:
                    raise BridgeError(str(error)) from None
            if args.command == "bootstrap":
                result = client.bootstrap(password, mail_disabled=args.mail_disabled, local_server_list=args.local_server_list)
            elif args.command == "verify":
                result = {"ok": True, "account": client.verify(args.guid, password)}
            elif args.command == "profile":
                result = {"ok": True, "account": client.verify(args.guid, password),
                          "characters": client.characters(args.guid, password, local_server_list=args.local_server_list),
                          "game_session_tested": False}
            else:
                result = {"ok": True, "characters": client.characters(args.guid, password, local_server_list=args.local_server_list)}
            if wants_profile:
                from login_profile import ProfileError, write_profile
                if result["account"]["account_id"] != result["characters"]["account"]["account_id"]:
                    raise BridgeError("account_mismatch")
                listed = result["characters"]["characters"]
                if args.character_id != -1 and not any(item["id"] == args.character_id for item in listed):
                    raise BridgeError("character_not_listed")
                guid = result.pop("guid") if args.command == "bootstrap" else args.guid
                try:
                    result["profile_path"] = write_profile(guid, password, args.character_id, args.class_type, args.skin_type)
                except ProfileError as error:
                    raise BridgeError(str(error)) from None
        print(json.dumps(result, sort_keys=True))
        return 0
    except BridgeError as exc:
        print(json.dumps({"ok": False, "error": str(exc)}, sort_keys=True))
        return 2
    except (OSError, EOFError, KeyboardInterrupt):
        print(json.dumps({"ok": False, "error": "input_or_connection_failed"}, sort_keys=True))
        return 2


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
# Public key preserved from FSoD wServer/RSA.cs:35-40 at
# 6fd20aad4a7905b13f25389c68368a942a2b68cb (ossimc82/Fabian Fischer et al.).
# Encryption format: RSA PKCS#1 v1.5, UTF-8 input, Base64 output (RSA.cs:53-70).
# No private PEM, backend credentials or cipher-stream state is included.
"""Offline HELLO credential encryption. JSON stdin; only ciphertext JSON stdout."""

import base64
import json
import sys

PUBLIC_KEY_PEM = b"""-----BEGIN PUBLIC KEY-----
MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQCbqweYUxzW0IiCwuBAzx6Htskr
hWW+B0iX4LMu2xqRh4gh52HUVu9nNiXso7utTKCv/HNK19v5xoWp3Cne23sicp2o
VGgKMFSowBFbtr+fhsq0yHv+JxixkL3WLnXcY3xREz7LOzVMoybUCmJzzhnzIsLP
iIPdpI1PxFDcnFbdRQIDAQAB
-----END PUBLIC KEY-----
"""


class EncryptionError(Exception):
    pass


def encrypt(plaintext, public_key_pem=PUBLIC_KEY_PEM):
    if not isinstance(plaintext, str):
        raise EncryptionError("invalid_plaintext")
    if plaintext == "":
        return ""  # Original RSA.Decrypt treats empty input as empty string.
    try:
        from cryptography.hazmat.primitives import serialization
        from cryptography.hazmat.primitives.asymmetric import padding, rsa
    except ImportError:
        raise EncryptionError("cryptography_dependency_required") from None
    try:
        key = serialization.load_pem_public_key(public_key_pem)
        if not isinstance(key, rsa.RSAPublicKey):
            raise ValueError()
        data = plaintext.encode("utf-8")
        if len(data) > (key.key_size + 7) // 8 - 11:
            raise EncryptionError("plaintext_too_long")
        ciphertext = key.encrypt(data, padding.PKCS1v15())
    except EncryptionError:
        raise
    except (ValueError, TypeError, UnicodeError):
        raise EncryptionError("encryption_failed") from None
    return base64.b64encode(ciphertext).decode("ascii")


def main():
    try:
        # The actual source public key is 1024 bits: each UTF-8 value <=117 bytes.
        # Bound input before JSON parsing; no arguments, secret files or network.
        raw = sys.stdin.read(4097)
        if len(raw) > 4096:
            raise EncryptionError("input_too_large")
        try:
            def unique_fields(pairs):
                out = {}
                for name, value in pairs:
                    if name in out:
                        raise EncryptionError("invalid_input")
                    out[name] = value
                return out
            payload = json.loads(raw, object_pairs_hook=unique_fields)
        except (ValueError, TypeError):
            raise EncryptionError("invalid_input") from None
        if not isinstance(payload, dict) or set(payload) != {"guid", "password"}:
            raise EncryptionError("invalid_input")
        result = {"guid_ciphertext": encrypt(payload["guid"]),
                  "password_ciphertext": encrypt(payload["password"])}
        print(json.dumps(result, sort_keys=True))
        return 0
    except EncryptionError as exc:
        print(json.dumps({"ok": False, "error": str(exc)}, sort_keys=True))
        return 2
    except (OSError, EOFError, KeyboardInterrupt):
        print(json.dumps({"ok": False, "error": "input_failed"}, sort_keys=True))
        return 2


if __name__ == "__main__":
    sys.exit(main())

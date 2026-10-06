# SPDX-License-Identifier: AGPL-3.0-only
# Original profile writer for FSoD HELLO.Read at revision
# 6fd20aad4a7905b13f25389c68368a942a2b68cb. See LICENSE/integration notes.
# Original source: wServer/networking/cliPackets/HelloPacket.cs:5-46,
# networking/Client.cs:30, realm/World.cs:26. No plaintext credentials persisted.
import json
import os
from pathlib import Path
import stat
import uuid

from rsa_public import EncryptionError, encrypt

PRIVATE_DIR = Path(__file__).resolve().parent / '.private'
BUILD_VERSION = '27.3.2'


class ProfileError(Exception):
    pass


def profile_data(guid, password, character_id=-1, class_type=782, skin_type=0):
    if (type(character_id) is not int or (character_id != -1 and not 1 <= character_id <= 2147483647)
            or any(type(v) is not int or not 0 <= v <= 65535 for v in (class_type, skin_type))):
        raise ProfileError('invalid_character_fields')
    try:
        return {'host': '127.0.0.1', 'port': 2050, 'character_id': character_id,
                'class_type': class_type, 'skin_type': skin_type,
                'hello': {'BuildVersion': BUILD_VERSION, 'GameId': -2,
                          'GUID': encrypt(guid), 'IgnoredInt': 0, 'Password': encrypt(password),
                          'randomint1': 0, 'Secret': '', 'KeyTime': 0,
                          'Key': [], 'MapInfo': [], 'obf1': '', 'obf2': '',
                          'obf3': '', 'obf4': '', 'obf5': ''}}
    except EncryptionError as error:
        raise ProfileError(str(error)) from None


def write_profile(guid, password, character_id=-1, class_type=782, skin_type=0, *, private_dir=PRIVATE_DIR):
    """Create an exclusive 0600 file beneath an owned 0700 no-symlink directory."""
    data = profile_data(guid, password, character_id, class_type, skin_type)
    directory = Path(private_dir).absolute()
    directory_fd = None
    filename = None
    created = False
    try:
        directory.mkdir(mode=0o700, exist_ok=True)
        directory_fd = os.open(directory, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        info = os.fstat(directory_fd)
        if info.st_uid != os.getuid() or not stat.S_ISDIR(info.st_mode):
            raise ProfileError('unsafe_profile_directory')
        os.fchmod(directory_fd, 0o700)
        filename = f'dev-{uuid.uuid4().hex}.json'
        fd = os.open(filename, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=directory_fd)
        created = True
        with os.fdopen(fd, 'w', encoding='utf-8') as stream:
            os.fchmod(stream.fileno(), 0o600)
            json.dump(data, stream, sort_keys=True)
            stream.write('\n')
            stream.flush()
            os.fsync(stream.fileno())
        return str(directory / filename)
    except (OSError, ProfileError):
        if created and directory_fd is not None:
            os.unlink(filename, dir_fd=directory_fd)
        raise ProfileError('profile_write_failed') from None
    finally:
        if directory_fd is not None:
            os.close(directory_fd)

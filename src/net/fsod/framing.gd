extends RefCounted
## SPDX-License-Identifier: AGPL-3.0-only
## FSoD wServer/networking/{Packet,NetworkHandler,Client}.cs, revision
## 6fd20aad4a7905b13f25389c68368a942a2b68cb. Frame: BE int32 length INCLUDING
## five-byte clear header, u8 ID, directional continuous RC4 encrypted body.
## Public protocol constants, NOT account credentials. Client direction is
## inverse of Client.cs server SendKey/ReceiveKey. Header never consumes RC4.
const RC4 := preload("res://src/net/fsod/rc4.gd")
const Binary := preload("res://src/net/fsod/binary.gd")
const CLIENT_SEND_KEY := [0x31, 0x1f, 0x80, 0x69, 0x14, 0x51, 0xc7, 0x1d, 0x09, 0xa1, 0x3a, 0x2a, 0x6e]
const CLIENT_RECEIVE_KEY := [0x72, 0xc5, 0x58, 0x3c, 0xaf, 0xb6, 0x81, 0x89, 0x95, 0xcd, 0xd7, 0x4b, 0x80]
# NetworkHandler.BUFFER_SIZE = int.MaxValue/4096 = 524287 body bytes.
const MAX_FRAME := 524292
const MAX_BUFFER := MAX_FRAME * 2
const MAX_FRAMES_PER_FEED := 1024
var error := ""
var _buffer := PackedByteArray()
var _receive := RC4.new()
var _send := RC4.new()

func _init(server_fixture_mode: bool = false) -> void:
	reset(server_fixture_mode)

func reset(server_fixture_mode: bool = false) -> void:
	error = ""
	_buffer.clear()
	_receive.initialize(PackedByteArray(CLIENT_SEND_KEY if server_fixture_mode else CLIENT_RECEIVE_KEY))
	_send.initialize(PackedByteArray(CLIENT_RECEIVE_KEY if server_fixture_mode else CLIENT_SEND_KEY))

func buffered_bytes() -> int:
	return _buffer.size()

func pack(id: int, payload: PackedByteArray) -> PackedByteArray:
	if not error.is_empty(): return PackedByteArray()
	if id < 0 or id > 255 or payload.size() + 5 > MAX_FRAME:
		error = "invalid packet id or excessive outbound frame"
		return PackedByteArray()
	var b := Binary.new()
	b.write_value("i32", payload.size() + 5)
	b.write_value("u8", id)
	var frame: PackedByteArray = b.bytes()
	frame.append_array(_send.crypt(payload))
	return frame

## Arbitrary partial/coalesced TCP bytes. Decrypt ONLY complete bodies ONCE.
## Unknown IDs still consume cipher stream correctly. Sticky error requires a
## new connection; never attempt to resynchronize on attacker-supplied bytes.
func feed(chunk: PackedByteArray) -> Array:
	var out: Array = []
	if not error.is_empty(): return out
	if chunk.size() > MAX_BUFFER - _buffer.size():
		error = "receive buffer exceeds bound"
		_buffer.clear()
		return out
	_buffer.append_array(chunk)
	var used := 0
	while _buffer.size() - used >= 5 and out.size() < MAX_FRAMES_PER_FEED:
		var length := (int(_buffer[used]) << 24) | (int(_buffer[used + 1]) << 16) | (int(_buffer[used + 2]) << 8) | int(_buffer[used + 3])
		if length < 5 or length > MAX_FRAME:
			error = "invalid frame length"
			_buffer.clear()
			return []
		if _buffer.size() - used < length: break
		out.append({"id": int(_buffer[used + 4]), "payload": _receive.crypt(_buffer.slice(used + 5, used + length))})
		used += length
	if used > 0: _buffer = _buffer.slice(used)
	return out

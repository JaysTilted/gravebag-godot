extends RefCounted
## SPDX-License-Identifier: AGPL-3.0-only
## Protocol adaptation from FSoD wServer/RC4.cs (BouncyCastle RC4Engine),
## revision 6fd20aad4a7905b13f25389c68368a942a2b68cb. Standard RC4 KSA/PRGA.
## Stateful per CONNECTION and DIRECTION, never restarted per packet.
var _s := PackedInt32Array()
var _i := 0
var _j := 0

func initialize(key: PackedByteArray) -> void:
	assert(not key.is_empty())
	_s.resize(256)
	_i = 0
	_j = 0
	for n in 256:
		_s[n] = n
	var j := 0
	for n in 256:
		j = (j + _s[n] + int(key[n % key.size()])) & 255
		var temp := _s[n]
		_s[n] = _s[j]
		_s[j] = temp

func crypt(input: PackedByteArray) -> PackedByteArray:
	assert(_s.size() == 256)
	var out := input.duplicate()
	for n in out.size():
		_i = (_i + 1) & 255
		_j = (_j + _s[_i]) & 255
		var temp := _s[_i]
		_s[_i] = _s[_j]
		_s[_j] = temp
		out[n] = out[n] ^ _s[(_s[_i] + _s[_j]) & 255]
	return out

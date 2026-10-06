extends RefCounted
## SPDX-License-Identifier: AGPL-3.0-only
## FSoD db/NReader.cs and NWriter.cs at 6fd20aad4a7905b13f25389c68368a942a2b68cb.
## Bounds-checked network-endian primitives. Error is sticky, no unchecked reads.
const MAX_STRING_BYTES := 524287
var stream := StreamPeerBuffer.new()
var error := ""

func _init(data: PackedByteArray = PackedByteArray()) -> void:
	stream.big_endian = true
	stream.data_array = data

func remaining() -> int:
	return stream.get_size() - stream.get_position()

func bytes() -> PackedByteArray:
	return stream.data_array

func fail(reason: String) -> void:
	if error.is_empty():
		error = reason

func need(size: int) -> bool:
	if not error.is_empty():
		return false
	if size < 0 or size > remaining():
		fail("truncated or invalid length")
		return false
	return true

func read_value(kind: String) -> Variant:
	match kind:
		"u8", "bool":
			if not need(1): return 0
			var value := stream.get_u8()
			if kind == "bool":
				if value > 1: fail("invalid boolean")
				return value != 0
			return value
		"i16", "u16":
			if not need(2): return 0
			return stream.get_16() if kind == "i16" else stream.get_u16()
		"i32", "u32":
			if not need(4): return 0
			return stream.get_32() if kind == "i32" else stream.get_u32()
		"f32":
			if not need(4): return 0.0
			var value := stream.get_float()
			if not is_finite(value): fail("non-finite float")
			return value
		"utf", "utf32", "bytes16", "bytes32":
			var size := int(read_value("i16" if kind in ["utf", "bytes16"] else "i32"))
			if size > MAX_STRING_BYTES or not need(size):
				fail("string/bytes length exceeds bound")
				return "" if kind.begins_with("utf") else PackedByteArray()
			var result: PackedByteArray = stream.get_data(size)[1]
			if kind.begins_with("utf"):
				var text := result.get_string_from_utf8()
				if text.to_utf8_buffer() != result: fail("invalid UTF8")
				return text
			return result
	fail("unknown binary type " + kind)
	return null

func write_value(kind: String, value: Variant) -> void:
	if not error.is_empty(): return
	match kind:
		"u8", "i16", "u16", "i32", "u32":
			if typeof(value) != TYPE_INT:
				fail("integer required: " + kind)
				return
			var ranges := {"u8": [0, 255], "i16": [-32768, 32767], "u16": [0, 65535],
				"i32": [-2147483648, 2147483647], "u32": [0, 4294967295]}
			if value < ranges[kind][0] or value > ranges[kind][1]:
				fail("integer out of range: " + kind)
				return
			match kind:
				"u8": stream.put_u8(value)
				"i16": stream.put_16(value)
				"u16": stream.put_u16(value)
				"i32": stream.put_32(value)
				"u32": stream.put_u32(value)
		"bool":
			if typeof(value) != TYPE_BOOL:
				fail("boolean required")
				return
			stream.put_u8(1 if value else 0)
		"f32":
			if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or abs(float(value)) > 3.402823466e38:
				fail("finite float32 required")
				return
			stream.put_float(value)
		"utf", "utf32", "bytes16", "bytes32":
			var data: PackedByteArray
			if kind.begins_with("utf"):
				if typeof(value) != TYPE_STRING:
					fail("string required")
					return
				data = value.to_utf8_buffer()
			else:
				if typeof(value) != TYPE_PACKED_BYTE_ARRAY:
					fail("bytes required")
					return
				data = value
			var limit := 32767 if kind in ["utf", "bytes16"] else MAX_STRING_BYTES
			if data.size() > limit:
				fail("string/bytes length exceeds bound")
				return
			write_value("i16" if kind in ["utf", "bytes16"] else "i32", data.size())
			stream.put_data(data)
		_:
			fail("unknown binary type " + kind)

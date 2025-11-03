local test_case_lib = require("./utils/test_case")
local utf16le = require("@peparser/utf16le")

local test_case = test_case_lib.test_case

local function test_encode_basic()
	local result = utf16le.encode("Hello")

	assert(buffer.len(result) == 12, "Should be 12 bytes (5 chars * 2 + null terminator)")
	assert(buffer.readu8(result, 0) == 0x48, "First byte should be 0x48")
	assert(buffer.readu8(result, 1) == 0x00, "Second byte should be 0x00")
	assert(buffer.readu16(result, 10) == 0, "Should have null terminator")
end

local function test_encode_empty()
	local result = utf16le.encode("")

	assert(buffer.len(result) == 2, "Empty string should have null terminator (2 bytes)")
	assert(buffer.readu16(result, 0) == 0, "Should be null terminator")
end

local function test_encode_special_chars()
	local result = utf16le.encode("ABC")

	assert(buffer.len(result) == 8, "Should be 8 bytes (3 chars * 2 + null terminator)")
	assert(buffer.readu16(result, 0) == 0x41, "'A'")
	assert(buffer.readu16(result, 2) == 0x42, "'B'")
	assert(buffer.readu16(result, 4) == 0x43, "'C'")
	assert(buffer.readu16(result, 6) == 0, "Null terminator")
end

local function test_decode_basic()
	local buf = buffer.create(4)

	buffer.writeu8(buf, 0, 0x48)
	buffer.writeu8(buf, 1, 0x00)
	buffer.writeu8(buf, 2, 0x69)
	buffer.writeu8(buf, 3, 0x00)

	local result = utf16le.decode(buf, 0, 4)
	assert(result == "Hi", "Should decode to Hi")
end

local function test_decode_empty()
	local buf = buffer.create(0)
	local result = utf16le.decode(buf, 0, 0)

	assert(result == "", "Empty buffer should decode to empty string")
end

local function test_decode_with_offset()
	local buf = buffer.create(8)
	buffer.writeu8(buf, 0, 0xFF)
	buffer.writeu8(buf, 1, 0xFF)
	buffer.writeu8(buf, 2, 0x41)
	buffer.writeu8(buf, 3, 0x00)
	buffer.writeu8(buf, 4, 0x42)
	buffer.writeu8(buf, 5, 0x00)

	local result = utf16le.decode(buf, 2, 4)
	assert(result == "AB", "Should decode from offset 2")
end

local function test_roundtrip_ascii()
	local original = "The quick brown fox"
	local encoded = utf16le.encode(original)
	local decoded = utf16le.decode(encoded, 0, buffer.len(encoded))

	assert(decoded == original, "Roundtrip failed for ASCII")
end

local function test_size_calculation()
	assert(buffer.len(utf16le.encode("")) == 2, "Empty string size should have a null terminator")
	assert(buffer.len(utf16le.encode("A")) == 4, "Single char should be 4 bytes (char and null)")
	assert(buffer.len(utf16le.encode("Hello")) == 12, "Five chars should be 12 bytes")
end

local function test_write_with_length()
	local buf = buffer.create(100)
	local str = "Test"

	local bytes_written = utf16le.write_with_length(buf, 0, str)
	assert(bytes_written > 2, "Should write length prefix + data")

	local length = buffer.readu16(buf, 0)
	assert(length == 4, "Length prefix should be 4")
end

local function test_read_with_length()
	local buf = buffer.create(100)
	local str = "Hello"
	utf16le.write_with_length(buf, 0, str)

	local result, bytes_read = utf16le.read_with_length(buf, 0)
	assert(result == str, "Should read back the same string")
	assert(bytes_read > 2, "Should report bytes read including length prefix")
end

local function test_size_with_length()
	assert(utf16le.size_with_length("") == 2, "Empty string with length should be 2 bytes")
	assert(utf16le.size_with_length("A") == 4, "Single char with length should be 4 bytes")
	assert(utf16le.size_with_length("Test") == 10, "4 chars with length should be 10 bytes")
end

local function test_roundtrip_with_length()
	local buf = buffer.create(100)
	local original = "Resource Name"

	local written = utf16le.write_with_length(buf, 0, original)
	local decoded, read = utf16le.read_with_length(buf, 0)

	assert(decoded == original, "Roundtrip with length failed")
	assert(written == read, "Written and read byte counts should match")
end

local function test_multiple_strings_sequential()
	local buf = buffer.create(200)
	local strings = { "First", "Second", "Third" }
	local offset = 0

	for _, str in strings do
		offset += utf16le.write_with_length(buf, offset, str)
	end

	offset = 0
	for i, expected in strings do
		local decoded, bytes_read = utf16le.read_with_length(buf, offset)
		assert(decoded == expected, `String {i} mismatch: expected '{expected}', got '{decoded}'`)
		offset += bytes_read
	end
end

local function test_null_character_handling()
	local str = "ABC"
	local encoded = utf16le.encode(str)

	local decoded = utf16le.decode(encoded, 0, buffer.len(encoded) - 2)
	assert(decoded == str, "String should be preserved")
end

local function test_encode_emoji()
	local emoji = "😀"
	local encoded = utf16le.encode(emoji)

	assert(buffer.len(encoded) == 6, "Emoji should encode to 6 bytes for surrogate pair + null terminator")

	local high = buffer.readu16(encoded, 0)
	local low = buffer.readu16(encoded, 2)

	assert(high == 0xD83D, `High surrogate should be 0xD83D, got 0x{string.format("%X", high)}`)
	assert(low == 0xDE00, `Low surrogate should be 0xDE00, got 0x{string.format("%X", low)}`)
	assert(buffer.readu16(encoded, 4) == 0, "Should have null terminator")
end

local function test_decode_emoji()
	local buf = buffer.create(4)

	buffer.writeu16(buf, 0, 0xD83D)
	buffer.writeu16(buf, 2, 0xDE00)

	local decoded = utf16le.decode(buf, 0, 4)
	assert(decoded == "😀", `Should decode to emoji, got '{decoded}'`)
end

local function test_roundtrip_emoji()
	local emoji_str = "Hello 😀🎉🚀 World"
	local encoded = utf16le.encode(emoji_str)
	local decoded = utf16le.decode(encoded, 0, buffer.len(encoded))

	assert(decoded == emoji_str, "Roundtrip failed for emoji string")
end

local function test_encode_cjk_characters()
	local chinese = "你好世界"
	local encoded = utf16le.encode(chinese)

	assert(buffer.len(encoded) == 10, "Chinese characters should encode correctly")
	assert(buffer.readu16(encoded, 0) == 0x4F60, "First character should be 0x4F60")
	assert(buffer.readu16(encoded, 2) == 0x597D, "Second character should be 0x597D")
end

local function test_roundtrip_cjk()
	local cjk_str = "日本語テスト"
	local encoded = utf16le.encode(cjk_str)
	local decoded = utf16le.decode(encoded, 0, buffer.len(encoded))

	assert(decoded == cjk_str, "Roundtrip failed for CJK characters")
end

local function test_encode_mixed_multibyte()
	local mixed = "A©你😀"
	local encoded = utf16le.encode(mixed)
	local decoded = utf16le.decode(encoded, 0, buffer.len(encoded))

	assert(decoded == mixed, "Roundtrip failed for mixed multibyte string")
end

local function test_decode_unpaired_high_surrogate()
	local buf = buffer.create(4)

	buffer.writeu16(buf, 0, 0xD800)
	buffer.writeu16(buf, 2, 0x0041)

	local decoded = utf16le.decode(buf, 0, 4)

	assert(decoded:find("�"), "Should contain replacement character for unpaired high surrogate")
end

local function test_decode_unpaired_low_surrogate()
	local buf = buffer.create(2)
	buffer.writeu16(buf, 0, 0xDC00)

	local decoded = utf16le.decode(buf, 0, 2)

	assert(decoded:find("�"), "Should contain replacement character for unpaired low surrogate")
end

local function test_decode_truncated_surrogate_pair()
	local buf = buffer.create(2)
	buffer.writeu16(buf, 0, 0xD83D)

	local decoded = utf16le.decode(buf, 0, 2)

	assert(decoded:find("�"), "Should contain replacement character for truncated surrogate pair")
end

local function test_decode_invalid_surrogate_sequence()
	local buf = buffer.create(4)
	buffer.writeu16(buf, 0, 0xD800)
	buffer.writeu16(buf, 2, 0xD801)

	local decoded = utf16le.decode(buf, 0, 4)

	assert(decoded:find("�"), "Should contain replacement character for invalid surrogate sequence")
end

local function test_read_with_length_buffer_overflow()
	local buf = buffer.create(10)

	buffer.writeu16(buf, 0, 100)

	local success = pcall(function()
		utf16le.read_with_length(buf, 0)
	end)

	assert(not success, "Should error on buffer overflow")
end

local function test_read_with_length_missing_length_field()
	local buf = buffer.create(1)

	local success = pcall(function()
		utf16le.read_with_length(buf, 0)
	end)

	assert(not success, "Should error on missing length field")
end

local function test_encode_invalid_utf8()
	local invalid_utf8 = string.char(0xFF, 0xFE)

	local success = pcall(function()
		utf16le.encode(invalid_utf8)
	end)

	assert(not success, "Should error on invalid UTF-8 input")
end

local function test_roundtrip_extended_characters()
	local tests = {
		"Ω",
		"Ñ",
		"€",
		"™",
		"♠♣♥♦",
	}

	for _, str in tests do
		local encoded = utf16le.encode(str)
		local decoded = utf16le.decode(encoded, 0, buffer.len(encoded))
		assert(decoded == str, `Roundtrip failed for '{str}'`)
	end
end

return function()
	test_case("encode_basic", test_encode_basic)
	test_case("encode_empty", test_encode_empty)
	test_case("encode_special_chars", test_encode_special_chars)
	test_case("decode_basic", test_decode_basic)
	test_case("decode_empty", test_decode_empty)
	test_case("decode_with_offset", test_decode_with_offset)
	test_case("roundtrip_ascii", test_roundtrip_ascii)
	test_case("size_calculation", test_size_calculation)
	test_case("write_with_length", test_write_with_length)
	test_case("read_with_length", test_read_with_length)
	test_case("size_with_length", test_size_with_length)
	test_case("roundtrip_with_length", test_roundtrip_with_length)
	test_case("multiple_strings_sequential", test_multiple_strings_sequential)
	test_case("null_character_handling", test_null_character_handling)

	test_case("encode_emoji", test_encode_emoji)
	test_case("decode_emoji", test_decode_emoji)
	test_case("roundtrip_emoji", test_roundtrip_emoji)
	test_case("encode_cjk_characters", test_encode_cjk_characters)
	test_case("roundtrip_cjk", test_roundtrip_cjk)
	test_case("encode_mixed_multibyte", test_encode_mixed_multibyte)
	test_case("roundtrip_extended_characters", test_roundtrip_extended_characters)

	test_case("decode_unpaired_high_surrogate", test_decode_unpaired_high_surrogate)
	test_case("decode_unpaired_low_surrogate", test_decode_unpaired_low_surrogate)
	test_case("decode_truncated_surrogate_pair", test_decode_truncated_surrogate_pair)
	test_case("decode_invalid_surrogate_sequence", test_decode_invalid_surrogate_sequence)
	test_case("read_with_length_buffer_overflow", test_read_with_length_buffer_overflow)
	test_case("read_with_length_missing_length_field", test_read_with_length_missing_length_field)
	test_case("encode_invalid_utf8", test_encode_invalid_utf8)
end

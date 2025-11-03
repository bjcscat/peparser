local function encode(str: string): buffer
	assert(utf8.len(str) ~= nil, "Input string must be a valid UTF-8 string")

	local codepoints = {}
	local i = 1
	local len = #str

	while i <= len do
		local byte = string.byte(str, i)
		local codepoint: number
		local advance: number

		if byte < 0x80 then
			codepoint = byte
			advance = 1
		elseif byte < 0xE0 then
			local byte2 = string.byte(str, i + 1) or 0
			codepoint = bit32.lshift(bit32.band(byte, 0x1F), 6) + bit32.band(byte2, 0x3F)
			advance = 2
		elseif byte < 0xF0 then
			local byte2 = string.byte(str, i + 1) or 0
			local byte3 = string.byte(str, i + 2) or 0
			codepoint = bit32.lshift(bit32.band(byte, 0x0F), 12)
				+ bit32.lshift(bit32.band(byte2, 0x3F), 6)
				+ bit32.band(byte3, 0x3F)
			advance = 3
		else
			local byte2 = string.byte(str, i + 1) or 0
			local byte3 = string.byte(str, i + 2) or 0
			local byte4 = string.byte(str, i + 3) or 0
			codepoint = bit32.lshift(bit32.band(byte, 0x07), 18)
				+ bit32.lshift(bit32.band(byte2, 0x3F), 12)
				+ bit32.lshift(bit32.band(byte3, 0x3F), 6)
				+ bit32.band(byte4, 0x3F)
			advance = 4
		end

		table.insert(codepoints, codepoint)
		i += advance
	end

	local utf16_units = 0
	for _, cp in codepoints do
		if cp > 0xFFFF then
			utf16_units += 2
		else
			utf16_units += 1
		end
	end

	local output = buffer.create((utf16_units + 1) * 2)
	local write_pos = 0

	for _, cp in codepoints do
		if cp > 0xFFFF then
			local adjusted = cp - 0x10000
			local high_surrogate = bit32.rshift(adjusted, 10) + 0xD800
			local low_surrogate = bit32.band(adjusted, 0x3FF) + 0xDC00

			buffer.writeu16(output, write_pos, high_surrogate)
			write_pos += 2
			buffer.writeu16(output, write_pos, low_surrogate)
			write_pos += 2
		else
			buffer.writeu16(output, write_pos, cp)
			write_pos += 2
		end
	end

	buffer.writeu16(output, write_pos, 0)

	return output
end

local function decode(buf: buffer, offset: number, length: number): string
	local result = {}
	local i = 0
	local char_count = length // 2

	while i < char_count do
		local unit = buffer.readu16(buf, offset + i * 2)

		if unit == 0 then
			break
		end

		local codepoint: number

		if unit >= 0xD800 and unit <= 0xDBFF then
			i += 1
			if i < char_count then
				local low_surrogate = buffer.readu16(buf, offset + i * 2)
				if low_surrogate >= 0xDC00 and low_surrogate <= 0xDFFF then
					codepoint = bit32.lshift(unit - 0xD800, 10) + (low_surrogate - 0xDC00) + 0x10000
				else
					codepoint = 0xFFFD
					i -= 1
				end
			else
				codepoint = 0xFFFD
			end
		elseif unit >= 0xDC00 and unit <= 0xDFFF then
			codepoint = 0xFFFD
		else
			codepoint = unit
		end

		if codepoint < 0x80 then
			table.insert(result, string.char(codepoint))
		elseif codepoint < 0x800 then
			table.insert(
				result,
				string.char(bit32.bor(0xC0, bit32.rshift(codepoint, 6)), bit32.bor(0x80, bit32.band(codepoint, 0x3F)))
			)
		elseif codepoint < 0x10000 then
			table.insert(
				result,
				string.char(
					bit32.bor(0xE0, bit32.rshift(codepoint, 12)),
					bit32.bor(0x80, bit32.band(bit32.rshift(codepoint, 6), 0x3F)),
					bit32.bor(0x80, bit32.band(codepoint, 0x3F))
				)
			)
		else
			table.insert(
				result,
				string.char(
					bit32.bor(0xF0, bit32.rshift(codepoint, 18)),
					bit32.bor(0x80, bit32.band(bit32.rshift(codepoint, 12), 0x3F)),
					bit32.bor(0x80, bit32.band(bit32.rshift(codepoint, 6), 0x3F)),
					bit32.bor(0x80, bit32.band(codepoint, 0x3F))
				)
			)
		end

		i += 1
	end

	return table.concat(result)
end

local function read_with_length(buf: buffer, offset: number): (string, number)
	local buf_len = buffer.len(buf)
	if offset + 2 > buf_len then
		error(string.format("Malformed UTF-16LE string: missing length at offset 0x%X", offset), 2)
	end
	local length = buffer.readu16(buf, offset)
	offset += 2
	local byte_length = length * 2
	local remaining = buf_len - offset
	if byte_length > remaining then
		error(
			string.format(
				"Malformed UTF-16LE string: claimed length 0x%X (%d bytes) exceeds remaining %d bytes at offset 0x%X",
				length,
				byte_length,
				remaining,
				offset
			),
			2
		)
	end

	local str = decode(buf, offset, byte_length)
	offset += byte_length

	return str, offset
end

local function write_with_length(buf: buffer, offset: number, str: string): number
	local encoded = encode(str)

	local encoded_size = buffer.len(encoded) - 2
	local utf16_unit_count = encoded_size // 2

	buffer.writeu16(buf, offset, utf16_unit_count)
	offset += 2

	buffer.copy(buf, offset, encoded, 0, encoded_size)
	offset += encoded_size

	return offset
end

local function size_with_length(str: string): number
	local encoded = encode(str)

	return buffer.len(encoded)
end

return {
	encode = encode,
	decode = decode,
	read_with_length = read_with_length,
	write_with_length = write_with_length,
	size_with_length = size_with_length,
}

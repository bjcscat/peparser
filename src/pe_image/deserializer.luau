local types = require("../types")

local function parse_error(context: string, detail: string)
	error(string.format("Malformed PE %s: %s", context, detail), 2)
end

local function ensure(condition: boolean, context: string, detail: string)
	if not condition then
		parse_error(context, detail)
	end
end

local function parse(source_buffer: buffer): types.Image
	local buffer_size = buffer.len(source_buffer)
	local offset = 0

	local function ensure_buffer_size(next_bytes: number, context: string)
		local remaining = buffer_size - offset
		if remaining < next_bytes then
			parse_error(
				context,
				string.format("expected %d bytes, found %d (offset 0x%X)", next_bytes, math.max(remaining, 0), offset)
			)
		end
	end

	ensure_buffer_size(64, "DOS Header")

	-- DOS Header

	local dos_header = types.dos_header.read(source_buffer, offset)

	ensure(dos_header.e_lfanew ~= 0, "DOS Header", "e_lfanew is zero")

	-- TODO: maybe read the rich header?

	offset = dos_header.e_lfanew

	-- COFF Header

	ensure_buffer_size(4, "PE Signature")

	local pe_signature = buffer.readu32(source_buffer, offset)
	ensure(pe_signature == 0x00004550, "PE Signature", "invalid PE signature")

	offset += 4

	ensure_buffer_size(20, "COFF Header")

	local coff_header
	coff_header, offset = types.coff_header.read(source_buffer, offset)

	-- Optional Header (Standard COFF + Windows)

	local optional_header = {
		standard_coff = {},
		windows = {},
	}

	ensure(coff_header.size_of_optional_header > 0, "COFF Header", "size_of_optional_header is invalid")
	ensure_buffer_size(coff_header.size_of_optional_header, "Windows Optional Header")

	local standard_coff
	standard_coff, offset =
		types.standard_coff_optional_header.read(source_buffer, offset, coff_header.size_of_optional_header)

	optional_header.standard_coff = standard_coff

	ensure(standard_coff.magic == 0x10b or standard_coff.magic == 0x20b, "Optional Header", "unrecognized magic value")

	local windows_header
	if standard_coff.magic == 0x10b then
		windows_header, offset = types.windows_pe32.read(
			source_buffer,
			offset,
			coff_header.size_of_optional_header - types.standard_coff_optional_header.size
		)
		optional_header.windows = windows_header :: types.WindowsHeader
	elseif standard_coff.magic == 0x20b then
		windows_header, offset = types.windows_pe64.read(
			source_buffer,
			offset,
			coff_header.size_of_optional_header - types.standard_coff_optional_header.size
		)
	else
		error("unreachable")
	end

	optional_header.windows = windows_header :: types.WindowsHeader

	-- Data Directories

	local data_directory_size = math.min(windows_header.number_of_rva_and_sizes * 8, 16 * 8)

	ensure_buffer_size(data_directory_size, "Data Directories")

	local data_directory_clone = buffer.create(16 * 8) -- max 16 directories, 8 bytes each
	buffer.copy(data_directory_clone, 0, source_buffer, offset, data_directory_size)

	local function read_data_directory(index: number): types.DataDirectory?
		local dir_offset = index * 8
		local virtual_address = buffer.readu32(data_directory_clone, dir_offset)
		local size = buffer.readu32(data_directory_clone, dir_offset + 4)

		return if virtual_address == 0 and size == 0
			then nil
			else {
				virtual_address = virtual_address,
				size = size,
			}
	end

	local data_directories: types.DataDirectories = {
		export_table = read_data_directory(0),
		import_table = read_data_directory(1),
		resource_table = read_data_directory(2),
		exception_table = read_data_directory(3),
		certificate_table = read_data_directory(4),
		base_relocation_table = read_data_directory(5),
		debug = read_data_directory(6),
		global_ptr = read_data_directory(8),
		tls_table = read_data_directory(9),
		load_config_table = read_data_directory(10),
		bound_import = read_data_directory(11),
		iat = read_data_directory(12),
		delay_import_descriptor = read_data_directory(13),
		clr_runtime_header = read_data_directory(14),
	}

	offset += data_directory_size

	-- sections

	local sections: { types.Section } = {}
	local section_table_bytes = coff_header.number_of_sections * types.section_header.size

	ensure_buffer_size(section_table_bytes, "Section headers")

	for i = 1, coff_header.number_of_sections do
		local header
		header, offset = types.section_header.read(source_buffer, offset)

		ensure(
			header.pointer_to_raw_data + header.size_of_raw_data <= buffer_size,
			"Section data",
			string.format(
				"section %d raw data (offset 0x%X size 0x%X) exceeds file size %d",
				i,
				header.pointer_to_raw_data,
				header.size_of_raw_data,
				buffer_size
			)
		)

		local section: types.Section = {
			header = header,
			data = buffer.create(header.size_of_raw_data),
		}

		buffer.copy(section.data, 0, source_buffer, header.pointer_to_raw_data, header.size_of_raw_data)
		table.insert(sections, section)
	end

	return {
		source = source_buffer,
		dos_header = dos_header,
		coff_header = coff_header,
		optional_header = optional_header :: types.OptionalHeader,
		data_directories = data_directories,
		sections = sections,
	}
end

return parse

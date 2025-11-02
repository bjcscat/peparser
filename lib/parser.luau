local utf16le = require("./utf16le")
local types = require("./types")

type Image = types.Image
type Section = types.Section
type ResourceNode = types.ResourceNode
type ResourceEntry = types.ResourceEntry
type ResourceDirectory = types.ResourceDirectory
type ResourceDataEntry = types.ResourceDataEntry

local dos_header_struct = types.dos_header_struct
local coff_header_struct = types.coff_header_struct
local standard_header_struct = types.standard_header_struct
local windows_pe32_struct = types.windows_pe32_struct
local windows_pe64_struct = types.windows_pe64_struct
local image_data_directory_struct = types.image_data_directory_struct
local section_header_struct = types.section_header_struct
local resource_directory_struct = types.resource_directory_struct
local resource_directory_entry_struct = types.resource_directory_entry_struct
local resource_data_entry_struct = types.resource_data_entry_struct

local NT_SIGNATURE = 0x00004550
local PE_32_MAGIC = 0x010b
local PE_64_MAGIC = 0x020b
local RESOURCE_DIRECTORY_FLAG = 0x80000000
local RESOURCE_NAME_FLAG = 0x80000000
local RESOURCE_OFFSET_MASK = 0x7FFFFFFF
local DOS_MAGIC = 0x5A4D

local function parse_error(context: string, detail: string)
	error(string.format("Malformed PE %s: %s", context, detail), 2)
end

local function ensure(condition: boolean, context: string, detail: string)
	if not condition then
		parse_error(context, detail)
	end
end

local function format_resource_path(path: { number | string }): string
	if #path == 0 then
		return "<root>"
	end
	local segments = table.create(#path)
	for index, segment in path do
		if type(segment) == "string" then
			segments[index] = string.format('"%s"', segment)
		else
			segments[index] = string.format("%d", segment)
		end
	end
	return table.concat(segments, "/")
end

local function parse(b: buffer): Image
	local buffer_size = buffer.len(b)
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

	local function read_u32(): number
		ensure_buffer_size(4, "NT headers")
		local n = buffer.readu32(b, offset)
		offset += 4
		return n
	end

	ensure_buffer_size(64, "DOS header")
	local dos_header, new_offset = dos_header_struct.read(b, offset)
	offset = new_offset
	ensure(
		dos_header.e_magic == DOS_MAGIC,
		"DOS header",
		string.format("expected magic 0x%04X, got 0x%04X", DOS_MAGIC, dos_header.e_magic)
	)
	ensure(
		dos_header.e_lfanew >= 64 and dos_header.e_lfanew + 4 <= buffer_size,
		"DOS header",
		string.format("e_lfanew 0x%X outside file bounds (size %d)", dos_header.e_lfanew, buffer_size)
	)

	offset = dos_header.e_lfanew
	ensure_buffer_size(4, "NT signature")

	local nt_signature = read_u32()
	ensure(
		nt_signature == NT_SIGNATURE,
		"NT signature",
		string.format("expected 0x%08X, got 0x%08X", NT_SIGNATURE, nt_signature)
	)

	-- Read COFF
	local coff_header
	coff_header, offset = coff_header_struct.read(b, offset)
	ensure(coff_header.number_of_sections >= 0, "COFF header", "negative section count")
	local optional_header_start = offset

	-- Read standard header
	local standard_header
	standard_header, offset = standard_header_struct.read(b, offset)
	ensure(
		standard_header.magic == PE_32_MAGIC or standard_header.magic == PE_64_MAGIC,
		"Optional header",
		string.format("unsupported magic 0x%04X", standard_header.magic)
	)

	local is_pe32 = standard_header.magic == PE_32_MAGIC

	-- Read Windows fields
	local windows_headers
	if is_pe32 then
		windows_headers, offset = windows_pe32_struct.read(b, offset)
	else
		windows_headers, offset = windows_pe64_struct.read(b, offset)
	end
	ensure(windows_headers.section_alignment ~= 0, "Optional header", "section_alignment is zero")
	ensure(windows_headers.file_alignment ~= 0, "Optional header", "file_alignment is zero")
	ensure(windows_headers.number_of_rva_and_sizes >= 0, "Optional header", "negative data directory count")

	local data_directories = {}
	for i = 1, windows_headers.number_of_rva_and_sizes do
		ensure_buffer_size(image_data_directory_struct.size, "Data directories")
		data_directories[i], offset = image_data_directory_struct.read(b, offset)
	end

	local optional_header_consumed = offset - optional_header_start
	ensure(
		optional_header_consumed == coff_header.size_of_optional_header,
		"COFF header",
		string.format(
			"size_of_optional_header mismatch (declared %d, consumed %d)",
			coff_header.size_of_optional_header,
			optional_header_consumed
		)
	)

	local section_headers = {}
	local section_table_bytes = coff_header.number_of_sections * section_header_struct.size

	ensure_buffer_size(section_table_bytes, "Section headers")

	for i = 1, coff_header.number_of_sections do
		section_headers[i], offset = section_header_struct.read(b, offset)
	end

	local sections: { Section } = {}
	for i, header in section_headers do
		local section_data: buffer? = nil
		if header.size_of_raw_data > 0 and header.pointer_to_raw_data > 0 then
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
			section_data = buffer.create(header.size_of_raw_data)
			buffer.copy(section_data, 0, b, header.pointer_to_raw_data, header.size_of_raw_data)
		end

		sections[i] = {
			header = header,
			data = section_data,
		}
	end

	-- Helper to convert RVA to file offset
	local function rva_to_file_offset(rva: number, sections: { Section }): number?
		for _, section in sections do
			local header = section.header
			local virtual_span = math.max(header.virtual_size, header.size_of_raw_data)
			if rva >= header.virtual_address and rva < header.virtual_address + virtual_span then
				return header.pointer_to_raw_data + (rva - header.virtual_address)
			end
		end
		return nil
	end

	local function read_resource_data(
		data_entry: ResourceDataEntry,
		sections: { Section },
		resource_path: string
	): buffer
		if data_entry.size == 0 then
			return buffer.create(0)
		end

		local file_offset = rva_to_file_offset(data_entry.offset_to_data, sections)
		ensure(
			file_offset ~= nil,
			"Resource data",
			string.format("%s points to RVA 0x%X outside any section", resource_path, data_entry.offset_to_data)
		)

		local resolved_offset = file_offset :: number
		ensure(
			resolved_offset + data_entry.size <= buffer_size,
			"Resource data",
			string.format(
				"%s payload (offset 0x%X size 0x%X) exceeds file size %d",
				resource_path,
				resolved_offset,
				data_entry.size,
				buffer_size
			)
		)

		local resource_data = buffer.create(data_entry.size)
		buffer.copy(resource_data, 0, b, resolved_offset, data_entry.size)
		return resource_data
	end

	local function parse_resource_data_entry(
		base_offset: number,
		data_offset: number,
		sections: { Section },
		name_or_id: number | string,
		path: { number | string },
		resource_bounds: number
	): ResourceNode
		local saved_offset = offset
		offset = base_offset + data_offset

		ensure(
			data_offset >= 0,
			"Resource directory",
			string.format("%s has negative data offset", format_resource_path(path))
		)
		ensure(
			data_offset + resource_data_entry_struct.size <= resource_bounds,
			"Resource directory",
			string.format(
				"data entry for %s extends past resource data (offset 0x%X)",
				format_resource_path(path),
				data_offset
			)
		)

		local data_entry
		data_entry, offset = resource_data_entry_struct.read(b, offset)

		local resource_data = read_resource_data(data_entry, sections, format_resource_path(path))

		offset = saved_offset

		return {
			directory = nil,
			entries = nil,
			data_entry = data_entry,
			data = resource_data,
			name_or_id = name_or_id,
		}
	end

	local function parse_resource_directory(
		base_offset: number,
		dir_offset: number,
		path: { number | string },
		resource_bounds: number
	): ResourceNode
		local saved_offset = offset
		offset = base_offset + dir_offset

		ensure(
			dir_offset >= 0,
			"Resource directory",
			string.format("%s has negative directory offset", format_resource_path(path))
		)
		ensure(
			dir_offset + resource_directory_struct.size <= resource_bounds,
			"Resource directory",
			string.format(
				"directory for %s extends past resource data (offset 0x%X)",
				format_resource_path(path),
				dir_offset
			)
		)

		local directory
		directory, offset = resource_directory_struct.read(b, offset)

		local total_entries = directory.number_of_named_entries + directory.number_of_id_entries
		local entries: { ResourceEntry } = {}

		for i = 1, total_entries do
			local dir_entry
			dir_entry, offset = resource_directory_entry_struct.read(b, offset)

			local is_directory = bit32.band(dir_entry.offset_to_data_or_directory, RESOURCE_DIRECTORY_FLAG) ~= 0
			local child_offset = bit32.band(dir_entry.offset_to_data_or_directory, RESOURCE_OFFSET_MASK)
			ensure(
				child_offset < resource_bounds,
				"Resource directory",
				string.format(
					"entry %d under %s references offset 0x%X beyond resource data size 0x%X",
					i,
					format_resource_path(path),
					child_offset,
					resource_bounds
				)
			)

			local name_or_id: number | string = dir_entry.name_or_id
			local is_named = bit32.band(dir_entry.name_or_id, RESOURCE_NAME_FLAG) ~= 0

			if is_named then
				local string_offset = bit32.band(dir_entry.name_or_id, RESOURCE_OFFSET_MASK)
				local string_pos = base_offset + string_offset
				local str_saved_offset = offset
				offset = string_pos

				ensure(
					string_offset < resource_bounds,
					"Resource string table",
					string.format(
						"named entry under %s references string offset 0x%X beyond resource data size 0x%X",
						format_resource_path(path),
						string_offset,
						resource_bounds
					)
				)

				name_or_id, offset = utf16le.read_with_length(b, offset)
				offset = str_saved_offset
			end

			local child_node: ResourceNode?
			if is_directory then
				table.insert(path, name_or_id)
				child_node = parse_resource_directory(base_offset, child_offset, path, resource_bounds)
				table.remove(path)
			else
				table.insert(path, name_or_id)
				child_node =
					parse_resource_data_entry(base_offset, child_offset, sections, name_or_id, path, resource_bounds)
				table.remove(path)
			end

			if child_node then
				child_node.name_or_id = name_or_id
			end

			entries[i] = {
				name_or_id = name_or_id,
				is_directory = is_directory,
				node = child_node,
			}
		end

		offset = saved_offset

		return {
			directory = directory,
			entries = entries,
			data_entry = nil,
			data = nil,
			name_or_id = 0,
		}
	end

	-- parse resources
	local resources: ResourceNode? = nil
	if #data_directories >= 3 and data_directories[3].size > 0 then
		local resource_dir = data_directories[3]
		local resource_offset = rva_to_file_offset(resource_dir.virtual_address, sections)
		if resource_offset then
			ensure(
				resource_dir.size + resource_offset <= buffer_size,
				"Resource directory",
				string.format(
					"directory size 0x%X at file offset 0x%X exceeds file size %d",
					resource_dir.size,
					resource_offset,
					buffer_size
				)
			)
			local resource_bounds = resource_dir.size
			resources = parse_resource_directory(resource_offset, 0, {}, resource_bounds)
		else
			parse_error(
				"Resource directory",
				string.format("virtual address 0x%X does not map to any section", resource_dir.virtual_address)
			)
		end
	end

	return {
		dos_header = dos_header,
		nt_headers = {
			coff_header = coff_header,
			standard_header = standard_header,
			windows_headers = windows_headers,
		},
		sections = sections,
		data_directories = data_directories,
		resources = resources,
	}
end

return {
	parse = parse,
}

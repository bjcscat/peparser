local RESOURCE_DIRECTORY_FLAG = 0x80000000
local RESOURCE_NAME_FLAG = 0x80000000
local RESOURCE_OFFSET_MASK = 0x7FFFFFFF

local types = require("../types")
local utf16le = require("../utf16le")

type ResourceNode = types.ResourceNode
type ResourceEntry = types.ResourceEntry
type ResourceDirectory = types.ResourceDirectory
type ResourceDataEntry = types.ResourceDataEntry
type ResourceId = types.ResourceId
type Section = types.Section

local resource_directory = types.resource_directory
local resource_directory_entry = types.resource_directory_entry
local resource_data_entry = types.resource_data_entry

local function parse_error(context: string, detail: string)
	error(string.format("Malformed PE %s: %s", context, detail), 2)
end

local function ensure(condition: boolean, context: string, detail: string)
	if not condition then
		parse_error(context, detail)
	end
end

local function format_resource_path(path: { ResourceId }): string
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

local function parse(
	source_buffer: buffer,
	resource_rva: number,
	resource_size: number,
	sections: { Section }
): ResourceNode?
	if resource_size == 0 then
		return nil
	end

	local function rva_to_file_offset(rva: number): number?
		for _, section in sections do
			local header = section.header
			local virtual_span = math.max(header.virtual_size, header.size_of_raw_data)
			if rva >= header.virtual_address and rva < header.virtual_address + virtual_span then
				return header.pointer_to_raw_data + (rva - header.virtual_address)
			end
		end
		return nil
	end

	local resource_file_offset = rva_to_file_offset(resource_rva)
	if not resource_file_offset then
		parse_error(
			"Resource directory",
			string.format("virtual address 0x%X does not map to any section", resource_rva)
		)
		error("unreachable")
	end

	local base_offset = resource_file_offset :: number
	local buffer_size = buffer.len(source_buffer)
	local offset = 0

	local function read_resource_data(data_entry: ResourceDataEntry, resource_path: string): buffer
		if data_entry.size == 0 then
			return buffer.create(0)
		end

		local file_offset = rva_to_file_offset(data_entry.offset_to_data)
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
		buffer.copy(resource_data, 0, source_buffer, resolved_offset, data_entry.size)
		return resource_data
	end

	local function parse_resource_data_entry(
		base_offset: number,
		data_offset: number,
		resource_id: ResourceId,
		path: { ResourceId },
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
			data_offset + resource_data_entry.size <= resource_bounds,
			"Resource directory",
			string.format(
				"data entry for %s extends past resource data (offset 0x%X)",
				format_resource_path(path),
				data_offset
			)
		)

		local data_entry
		data_entry, offset = resource_data_entry.read(source_buffer, offset)

		local resource_data = read_resource_data(data_entry, format_resource_path(path))

		offset = saved_offset

		return {
			directory = nil,
			entries = nil,
			data_entry = data_entry,
			data = resource_data,
			id = resource_id,
		}
	end

	local function parse_resource_directory(
		base_offset: number,
		dir_offset: number,
		path: { ResourceId },
		resource_bounds: number,
		parent_id: ResourceId
	): ResourceNode
		local saved_offset = offset
		offset = base_offset + dir_offset

		ensure(
			dir_offset >= 0,
			"Resource directory",
			string.format("%s has negative directory offset", format_resource_path(path))
		)
		ensure(
			dir_offset + resource_directory.size <= resource_bounds,
			"Resource directory",
			string.format(
				"directory for %s extends past resource data (offset 0x%X)",
				format_resource_path(path),
				dir_offset
			)
		)

		local directory
		directory, offset = resource_directory.read(source_buffer, offset)

		local total_entries = directory.number_of_named_entries + directory.number_of_id_entries
		local entries: { ResourceEntry } = {}

		for i = 1, total_entries do
			local dir_entry
			dir_entry, offset = resource_directory_entry.read(source_buffer, offset)

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

			local resource_id: ResourceId = dir_entry.name_or_id
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

				resource_id, offset = utf16le.read_with_length(source_buffer, offset)
				offset = str_saved_offset
			end

			local child_node: ResourceNode?
			if is_directory then
				table.insert(path, resource_id)
				child_node = parse_resource_directory(base_offset, child_offset, path, resource_bounds, resource_id)
				table.remove(path)
			else
				table.insert(path, resource_id)
				child_node = parse_resource_data_entry(base_offset, child_offset, resource_id, path, resource_bounds)
				table.remove(path)
			end

			entries[i] = {
				id = resource_id,
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
			id = parent_id,
		}
	end

	return parse_resource_directory(base_offset, 0, {}, resource_size, 0)
end

return parse

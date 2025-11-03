local utf16le = require("../utf16le")
local types = require("../types")

type ResourceNode = types.ResourceNode
type ResourceId = types.ResourceId

local resource_directory = types.resource_directory
local resource_directory_entry = types.resource_directory_entry
local resource_data_entry = types.resource_data_entry

local RESOURCE_DIRECTORY_FLAG = 0x80000000
local RESOURCE_NAME_FLAG = 0x80000000
local ALIGNMENT = 8

local function align(value: number, alignment: number): number
	if alignment == 0 then
		return value
	end
	return math.ceil(value / alignment) * alignment
end

type DataEntry = {
	node: ResourceNode,
	data: buffer,
	data_offset: number,
}

type StringEntry = {
	str: string,
	offset: number,
}

local function serialize(root: ResourceNode, base_rva: number): buffer
	local data_entries: { DataEntry } = {}
	local data_offsets: { [ResourceNode]: number } = {}
	local string_entries: { StringEntry } = {}
	local string_offsets: { [string]: number } = {}

	local string_table_size = 0
	local current_data_offset = 0

	local function register_data_node(node: ResourceNode)
		local data = node.data
		if not data then
			return
		end

		data_offsets[node] = current_data_offset
		table.insert(data_entries, {
			node = node,
			data = data,
			data_offset = current_data_offset,
		})

		current_data_offset += buffer.len(data)
		current_data_offset = align(current_data_offset, ALIGNMENT)
	end

	local function collect_strings(node: ResourceNode)
		if type(node.id) == "string" then
			local name = node.id :: string
			if not string_offsets[name] then
				string_offsets[name] = string_table_size
				table.insert(string_entries, {
					str = name,
					offset = string_table_size,
				})
				string_table_size += utf16le.size_with_length(name)
			end
		end

		if node.entries then
			for _, entry in node.entries do
				local child = entry.node
				if child then
					collect_strings(child)
				end
			end
		end
	end

	collect_strings(root)

	local function calculate_tree_size(node: ResourceNode): number
		local size = 0
		if node.directory and node.entries then
			size += 16
			size += #node.entries * 8

			for _, entry in node.entries do
				local child = entry.node
				if child then
					if entry.is_directory then
						size += calculate_tree_size(child)
					else
						size += 16
						register_data_node(child)
					end
				end
			end
		end
		return size
	end

	local tree_size = calculate_tree_size(root)
	local tree_size_aligned = align(tree_size, ALIGNMENT)
	local string_table_base = tree_size_aligned
	local data_offset = align(string_table_base + string_table_size, ALIGNMENT)
	local total_size = data_offset + current_data_offset

	local output = buffer.create(total_size)

	local write_offset = 0

	local function write_tree(node: ResourceNode)
		if not node.directory or not node.entries then
			return
		end

		write_offset = resource_directory.write(output, write_offset, node.directory)

		local entries_start = write_offset
		write_offset += #node.entries * 8

		local sorted_entries = table.clone(node.entries)
		table.sort(sorted_entries, function(a, b)
			local a_is_string = type(a.id) == "string"
			local b_is_string = type(b.id) == "string"
			
			if a_is_string ~= b_is_string then
				return a_is_string -- strings before numbers
			end
			
			if a_is_string then
				return (a.id :: string) < (b.id :: string)
			else
				return (a.id :: number) < (b.id :: number)
			end
		end)

		for index, entry in sorted_entries do
			local entry_write_pos = entries_start + (index - 1) * 8
			local offset_value = 0
			local id_value: number

			if type(entry.id) == "string" then
				local name = entry.id :: string
				local name_offset = string_offsets[name] or 0
				id_value = bit32.bor(string_table_base + name_offset, RESOURCE_NAME_FLAG)
			else
				id_value = entry.id :: number
			end

			local child = entry.node
			if child then
				if entry.is_directory then
					local child_offset = write_offset
					write_tree(child)
					offset_value = bit32.bor(child_offset, RESOURCE_DIRECTORY_FLAG)
				else
					local node_data = child.data
					if node_data then
						local data_entry_record = {
							offset_to_data = base_rva + data_offset + (data_offsets[child] or 0),
							size = buffer.len(node_data),
							code_page = child.data_entry and child.data_entry.code_page or 0,
							reserved = 0,
						}
						local saved_offset = write_offset
						write_offset = resource_data_entry.write(output, write_offset, data_entry_record)
						offset_value = saved_offset
					end
				end
			end

			resource_directory_entry.write(output, entry_write_pos, {
				name_or_id = id_value,
				offset_to_data_or_directory = offset_value,
			})
		end
	end

	write_tree(root)

	write_offset = string_table_base
	for _, str_entry in string_entries do
		write_offset = utf16le.write_with_length(output, write_offset, str_entry.str)
	end

	for _, data_entry in data_entries do
		local data_pos = data_offset + data_entry.data_offset
		buffer.copy(output, data_pos, data_entry.data, 0, buffer.len(data_entry.data))
	end

	return output
end

return serialize

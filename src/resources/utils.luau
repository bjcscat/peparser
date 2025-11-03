local types = require("../types")

type ResourceNode = types.ResourceNode
type ResourceEntry = types.ResourceEntry
type ResourceDirectory = types.ResourceDirectory
type ResourceDataEntry = types.ResourceDataEntry
type ResourceId = types.ResourceId

local resource_utils = {}

function resource_utils.create_directory(id: ResourceId, named_count: number?, id_count: number?): ResourceNode
	return {
		directory = {
			characteristics = 0,
			time_date_stamp = 0,
			major_version = 0,
			minor_version = 0,
			number_of_named_entries = named_count or 0,
			number_of_id_entries = id_count or 0,
		},
		entries = {},
		data_entry = nil,
		data = nil,
		id = id,
	}
end

function resource_utils.create_data(id: ResourceId, data: buffer, code_page: number?): ResourceNode
	return {
		directory = nil,
		entries = nil,
		data_entry = {
			offset_to_data = 0,
			size = buffer.len(data),
			code_page = code_page or 0,
			reserved = 0,
		},
		data = data,
		id = id,
	}
end

function resource_utils.add_entry(parent: ResourceNode, child: ResourceNode): boolean
	if not parent.directory or not parent.entries then
		return false
	end

	local is_directory = child.directory ~= nil
	local entry: ResourceEntry = {
		id = child.id,
		is_directory = is_directory,
		node = child,
	}

	table.insert(parent.entries, entry)

	if type(child.id) == "string" then
		parent.directory.number_of_named_entries += 1
	else
		parent.directory.number_of_id_entries += 1
	end

	return true
end

function resource_utils.find_entry(node: ResourceNode, id: ResourceId): ResourceNode?
	if not node.entries then
		return nil
	end

	for _, entry in node.entries do
		if entry.id == id then
			return entry.node
		end
	end

	return nil
end

function resource_utils.find_by_path(root: ResourceNode?, path: { ResourceId }): ResourceNode?
	if not root then
		return nil
	end

	local current = root
	for _, id in path do
		local next_node = resource_utils.find_entry(current, id)
		if not next_node then
			return nil
		end
		current = next_node
	end

	return current
end

function resource_utils.ensure_path(
	root: ResourceNode,
	path: { ResourceId },
	data: buffer?,
	code_page: number?
): ResourceNode
	local current: ResourceNode = root
	for i, id in path do
		local next_node = resource_utils.find_entry(current, id)

		if not next_node then
			if i == #path and data then
				next_node = resource_utils.create_data(id, data, code_page)
			else
				next_node = resource_utils.create_directory(id, 0, 0)
			end
			resource_utils.add_entry(current, next_node)
			current = next_node
		else
			if i == #path and data and next_node.data_entry then
				next_node.data = data
				next_node.data_entry.size = buffer.len(data)
				if code_page then
					next_node.data_entry.code_page = code_page
				end
			end
			current = next_node
		end
	end

	return current
end

function resource_utils.remove_entry(parent: ResourceNode, id: ResourceId): boolean
	if not parent.directory or not parent.entries then
		return false
	end

	for i, entry in parent.entries do
		if entry.id == id then
			table.remove(parent.entries, i)

			if type(id) == "string" then
				parent.directory.number_of_named_entries -= 1
			else
				parent.directory.number_of_id_entries -= 1
			end

			return true
		end
	end

	return false
end

function resource_utils.set_data(node: ResourceNode, data: buffer, code_page: number?)
	if not node.data_entry then
		return
	end

	node.data = data
	node.data_entry.size = buffer.len(data)
	if code_page then
		node.data_entry.code_page = code_page
	end
end

return resource_utils
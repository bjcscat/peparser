local resource_serializer = require("./resource_serializer")
local types = require("./types")

type Image = types.Image
type Section = types.Section
type ResourceNode = types.ResourceNode

local function get_section_name(section: Section): string
	local name = ""
	for _, byte in section.header.name do
		if byte == 0 then
			break
		end
		name ..= string.char(byte :: number)
	end
	return name
end

local function find_section(image: Image, name: string): Section?
	for _, section in image.sections do
		if get_section_name(section) == name then
			return section
		end
	end
	return nil
end

local function create_section(
	name: string,
	virtual_size: number,
	virtual_address: number,
	raw_size: number,
	raw_pointer: number,
	characteristics: number
): Section
	local name_bytes = table.create(8, 0)
	for i = 1, math.min(#name, 8) do
		name_bytes[i] = string.byte(name, i)
	end

	return {
		header = {
			name = name_bytes,
			virtual_size = virtual_size,
			virtual_address = virtual_address,
			size_of_raw_data = raw_size,
			pointer_to_raw_data = raw_pointer,
			pointer_to_relocations = 0,
			pointer_to_linenumbers = 0,
			number_of_relocations = 0,
			number_of_linenumbers = 0,
			characteristics = characteristics,
		},
		data = nil,
	}
end

local function add_section(image: Image, section: Section): boolean
	table.insert(image.sections, section)
	image.nt_headers.coff_header.number_of_sections += 1
	return true
end

local function remove_section(image: Image, name: string): boolean
	for i, section in image.sections do
		if get_section_name(section) == name then
			table.remove(image.sections, i)
			image.nt_headers.coff_header.number_of_sections -= 1
			return true
		end
	end
	return false
end

local function set_section_data(section: Section, data: buffer)
	section.data = data
	section.header.size_of_raw_data = buffer.len(data)
	section.header.virtual_size = buffer.len(data)
end

local function update_resources(image: Image, resources: ResourceNode?): Image
	if not resources then
		image.resources = nil

		if #image.data_directories >= 3 then
			image.data_directories[3] = {
				virtual_address = 0,
				size = 0,
			}
		end
		return image
	end

	local rsrc_section = find_section(image, ".rsrc")

	local rsrc_rva = rsrc_section and rsrc_section.header.virtual_address or 0
	local resource_buffer = resource_serializer.serialize(resources, rsrc_rva)
	local resource_size = buffer.len(resource_buffer)

	if rsrc_section then
		rsrc_section.data = resource_buffer
		rsrc_section.header.virtual_size = resource_size
		rsrc_section.header.size_of_raw_data = resource_size

		if #image.data_directories >= 3 then
			image.data_directories[3] = {
				virtual_address = rsrc_section.header.virtual_address,
				size = resource_size,
			}
		end
	else
		local new_section = create_section(
			".rsrc",
			resource_size,
			0, -- virtual address (will be set during relocation)
			resource_size, -- unaligned raw size
			0, -- file pointer (will be set during relocation)
			0x40000040 -- IMAGE_SCN_CNT_INITIALIZED_DATA | IMAGE_SCN_MEM_READ
		)

		new_section.data = resource_buffer
		add_section(image, new_section)

		if #image.data_directories >= 3 then
			image.data_directories[3] = {
				virtual_address = 0, -- Will be set during relocation
				size = resource_size,
			}
		end

		image.resources = resources
	end

	image.resources = resources

	return image
end

local function finalize_resources(image: Image): Image
	if not image.resources then
		return image
	end

	local rsrc_section = find_section(image, ".rsrc")
	if not rsrc_section then
		return image
	end

	local rsrc_rva = rsrc_section.header.virtual_address
	local resource_buffer = resource_serializer.serialize(image.resources, rsrc_rva)
	local resource_size = buffer.len(resource_buffer)

	rsrc_section.data = resource_buffer
	rsrc_section.header.virtual_size = resource_size
	rsrc_section.header.size_of_raw_data = resource_size

	if #image.data_directories >= 3 then
		image.data_directories[3] = {
			virtual_address = rsrc_section.header.virtual_address,
			size = resource_size,
		}
	end

	return image
end

return {
	find_section = find_section,
	get_section_name = get_section_name,
	update_resources = update_resources,
	finalize_resources = finalize_resources,
	create_section = create_section,
	add_section = add_section,
	remove_section = remove_section,
	set_section_data = set_section_data,
}

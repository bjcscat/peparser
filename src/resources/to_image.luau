local types = require("../types")
local serializer = require("./serializer")
local pe_serializer = require("../pe_image/serializer")

type Image = types.Image
type ResourceNode = types.ResourceNode
type Section = types.Section

local function find_or_create_resource_section(image: Image): (Section, number)
	for i, section in image.sections do
		if section.header.name == ".rsrc" then
			return section, i
		end
	end
	
	local new_section: Section = {
		header = {
			name = ".rsrc",
			virtual_size = 0,
			virtual_address = 0,
			size_of_raw_data = 0,
			pointer_to_raw_data = 0,
			pointer_to_relocations = 0,
			pointer_to_linenumbers = 0,
			number_of_relocations = 0,
			number_of_linenumbers = 0,
			characteristics = 0x40000040, -- IMAGE_SCN_CNT_INITIALIZED_DATA | IMAGE_SCN_MEM_READ
		},
		data = buffer.create(0),
	}
	
	table.insert(image.sections, new_section)
	return new_section, #image.sections
end

local function to_image(image: Image, resources: ResourceNode?): Image
	if not resources then
		image.data_directories.resource_table = nil
		
		for i, section in image.sections do
			if section.header.name == ".rsrc" then
				table.remove(image.sections, i)
				break
			end
		end
		
		return image
	end
	
	local rsrc_section = find_or_create_resource_section(image)
	local resource_rva = rsrc_section.header.virtual_address
	
	if resource_rva == 0 then
		local last_section: Section? = nil
		for _, section in image.sections do
            -- ignore the .rsrc section we just created
			if section ~= rsrc_section and section.header.virtual_address > 0 then
				if not last_section or section.header.virtual_address > last_section.header.virtual_address then
					last_section = section
				end
			end
		end
		
		if last_section then
			local section_alignment = image.optional_header.windows.section_alignment
			resource_rva = last_section.header.virtual_address + last_section.header.virtual_size
			resource_rva = math.ceil(resource_rva / section_alignment) * section_alignment
		else
			resource_rva = image.optional_header.windows.size_of_headers
		end
	end
	
	local resource_data = serializer(resources, resource_rva)
	local resource_size = buffer.len(resource_data)
	
	local file_alignment = image.optional_header.windows.file_alignment
	local aligned_raw_size = math.ceil(resource_size / file_alignment) * file_alignment
	
	local padded_data = buffer.create(aligned_raw_size)
	buffer.copy(padded_data, 0, resource_data, 0, resource_size)
	
	rsrc_section.data = padded_data
	rsrc_section.header.virtual_size = resource_size
	rsrc_section.header.size_of_raw_data = aligned_raw_size
	rsrc_section.header.virtual_address = resource_rva
	
	image.data_directories.resource_table = {
		virtual_address = resource_rva,
		size = resource_size,
	}
    
	image = pe_serializer.relocate_sections(image)
	
	return image
end

return to_image

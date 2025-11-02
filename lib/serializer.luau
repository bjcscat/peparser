local types = require("./types")

type Image = types.Image
type Section = types.Section
type SectionAddressMap = {
	old_rva: number,
	old_size: number,
	new_rva: number,
}

local dos_header_struct = types.dos_header_struct
local coff_header_struct = types.coff_header_struct
local standard_header_struct = types.standard_header_struct
local windows_pe32_struct = types.windows_pe32_struct
local windows_pe64_struct = types.windows_pe64_struct
local image_data_directory_struct = types.image_data_directory_struct
local section_header_struct = types.section_header_struct

local NT_SIGNATURE = 0x00004550
local PE_32_MAGIC = 0x010b
local DEFAULT_SECTION_ALIGNMENT = 4 * 1024 -- 4KiB
local DEFAULT_FILE_ALIGNMENT = 512 -- 512 bytes

local function align(value: number, alignment: number): number
	if alignment == 0 then
		return value
	end

	return math.ceil(value / alignment) * alignment
end

local function calculate_headers_size(image: Image, is_pe32: boolean): number
	local size = 0

	-- DOS header
	size += 64

	-- DOS stub
	size = image.dos_header.e_lfanew

	-- NT signature
	size += 4

	-- COFF header
	size += 20

	-- (standard + windows-specific + data directories)
	size += 28 -- Standard header
	if is_pe32 then
		size += 68 -- PE32 Windows header base
	else
		size += 88 -- PE64 Windows header base
	end
	size += #image.data_directories * 8 -- Each data directory is 8 bytes

	-- Section headers
	size += #image.sections * 40 -- Each section header is 40 bytes

	return size
end

-- Relocate all sections and update their addresses
local function relocate_sections(image: Image): Image
	local is_pe32 = image.nt_headers.standard_header.magic == PE_32_MAGIC
	local windows_headers = image.nt_headers.windows_headers

	local section_alignment = windows_headers.section_alignment
	local file_alignment = windows_headers.file_alignment

	if section_alignment == 0 then
		section_alignment = DEFAULT_SECTION_ALIGNMENT
	end

	if file_alignment == 0 then
		file_alignment = DEFAULT_FILE_ALIGNMENT
	end

	local headers_size = calculate_headers_size(image, is_pe32)
	headers_size = align(headers_size, file_alignment)
	windows_headers.size_of_headers = headers_size

	local section_mappings: { SectionAddressMap } = {}

	local current_file_offset = headers_size
	local current_rva = align(headers_size, section_alignment)

	for _, section in image.sections do
		local header = section.header

		local old_rva = header.virtual_address
		local old_size = math.max(header.virtual_size, header.size_of_raw_data)
		if old_size == 0 and section.data then
			old_size = buffer.len(section.data)
		end

		header.virtual_address = current_rva
		header.pointer_to_raw_data = current_file_offset

		if section.data then
			local actual_data_size = buffer.len(section.data)
			header.size_of_raw_data = align(actual_data_size, file_alignment)

			if header.virtual_size < actual_data_size then
				header.virtual_size = actual_data_size
			end
		else
			header.size_of_raw_data = 0
			if header.virtual_size == 0 then
				header.virtual_size = 0
			end
		end

		section_mappings[#section_mappings + 1] = {
			old_rva = old_rva,
			old_size = old_size,
			new_rva = header.virtual_address,
		}

		current_file_offset += header.size_of_raw_data
		current_rva = align(current_rva + header.virtual_size, section_alignment)
	end

	windows_headers.size_of_image = current_rva

	-- Update data directories to point to new RVAs
	for _, directory in image.data_directories do
		if directory.size > 0 then
			local old_dir_rva = directory.virtual_address
			for _, mapping in section_mappings do
				local old_rva = mapping.old_rva
				local old_size = mapping.old_size
				if old_size > 0 and old_dir_rva >= old_rva and old_dir_rva < old_rva + old_size then
					local offset = old_dir_rva - old_rva
					directory.virtual_address = mapping.new_rva + offset
					break
				end
			end
		end
	end

	return image
end

local function serialize(image: Image, relocate: boolean?): buffer
	if relocate == nil then
		relocate = true
	end

	if relocate then
		image = relocate_sections(image)
	end
	local is_pe32 = image.nt_headers.standard_header.magic == PE_32_MAGIC

	-- Calculate total size needed
	local total_size = image.nt_headers.windows_headers.size_of_headers

	for _, section in image.sections do
		if section.header.size_of_raw_data > 0 then
			local section_end = section.header.pointer_to_raw_data + section.header.size_of_raw_data
			total_size = math.max(total_size, section_end)
		end
	end

	local output = buffer.create(total_size)
	local offset = 0

	-- Write DOS header
	offset = dos_header_struct.write(output, offset, image.dos_header)

	-- Position to NT headers
	offset = image.dos_header.e_lfanew

	-- Write NT signature
	buffer.writeu32(output, offset, NT_SIGNATURE)
	offset += 4

	-- Write COFF header
	offset = coff_header_struct.write(output, offset, image.nt_headers.coff_header)

	-- Write standard header
	offset = standard_header_struct.write(output, offset, image.nt_headers.standard_header)

	-- Write windows headers
	if is_pe32 then
		offset = windows_pe32_struct.write(output, offset, image.nt_headers.windows_headers :: types.PE32WindowsHeader)
	else
		offset = windows_pe64_struct.write(output, offset, image.nt_headers.windows_headers :: types.PE64WindowsHeader)
	end

	-- Write data directories
	for _, directory in image.data_directories do
		offset = image_data_directory_struct.write(output, offset, directory)
	end

	-- Write section headers
	for _, section in image.sections do
		offset = section_header_struct.write(output, offset, section.header)
	end

	for _, section in image.sections do
		if section.data and section.header.pointer_to_raw_data > 0 and section.header.size_of_raw_data > 0 then
			local aligned_data = buffer.create(section.header.size_of_raw_data)

			local data_size = math.min(buffer.len(section.data), section.header.size_of_raw_data)
			buffer.copy(aligned_data, 0, section.data, 0, data_size)

			buffer.copy(output, section.header.pointer_to_raw_data, aligned_data, 0, section.header.size_of_raw_data)
		end
	end

	return output
end

return {
	serialize = serialize,
	relocate_sections = relocate_sections,
	align = align,
	calculate_headers_size = calculate_headers_size,
}

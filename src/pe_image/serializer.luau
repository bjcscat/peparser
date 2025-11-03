local types = require("../types")

type Image = types.Image
type Section = types.Section
type DataDirectory = types.DataDirectory

local dos_header = types.dos_header
local coff_header = types.coff_header
local standard_coff_optional_header = types.standard_coff_optional_header
local windows_pe32 = types.windows_pe32
local windows_pe64 = types.windows_pe64
local image_data_directory = types.image_data_directory
local section_header = types.section_header

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

local function get_data_directory_array(data_dirs: types.DataDirectories): { DataDirectory }
	local array: { DataDirectory } = {}

	array[1] = data_dirs.export_table or { virtual_address = 0, size = 0 }
	array[2] = data_dirs.import_table or { virtual_address = 0, size = 0 }
	array[3] = data_dirs.resource_table or { virtual_address = 0, size = 0 }
	array[4] = data_dirs.exception_table or { virtual_address = 0, size = 0 }
	array[5] = data_dirs.certificate_table or { virtual_address = 0, size = 0 }
	array[6] = data_dirs.base_relocation_table or { virtual_address = 0, size = 0 }
	array[7] = data_dirs.debug or { virtual_address = 0, size = 0 }
	array[8] = { virtual_address = 0, size = 0 } -- architecture (reserved)
	array[9] = data_dirs.global_ptr or { virtual_address = 0, size = 0 }
	array[10] = data_dirs.tls_table or { virtual_address = 0, size = 0 }
	array[11] = data_dirs.load_config_table or { virtual_address = 0, size = 0 }
	array[12] = data_dirs.bound_import or { virtual_address = 0, size = 0 }
	array[13] = data_dirs.iat or { virtual_address = 0, size = 0 }
	array[14] = data_dirs.delay_import_descriptor or { virtual_address = 0, size = 0 }
	array[15] = data_dirs.clr_runtime_header or { virtual_address = 0, size = 0 }
	array[16] = { virtual_address = 0, size = 0 } -- reserved

	return array
end

local function calculate_headers_size(image: Image, is_pe32: boolean): number
	local size = 0

	-- DOS header
	size += dos_header.size

	-- DOS stub (everything between DOS header and NT headers)
	size = image.dos_header.e_lfanew

	-- NT signature
	size += 4

	-- COFF header
	size += coff_header.size

	-- Optional header (standard + windows-specific + data directories)
	size += standard_coff_optional_header.size
	if is_pe32 then
		size += windows_pe32.size
	else
		size += windows_pe64.size
	end

	-- Data directories (16 max)
	size += 16 * image_data_directory.size

	-- Section headers
	size += #image.sections * section_header.size

	return size
end

type SectionAddressMap = {
	old_rva: number,
	old_size: number,
	new_rva: number,
}

local function relocate_sections(image: Image): Image
	local is_pe32 = image.optional_header.standard_coff.magic == PE_32_MAGIC
	local windows_headers = image.optional_header.windows

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

	-- update RVAs in data directories
	local data_dirs_array = get_data_directory_array(image.data_directories)
	for _, directory in data_dirs_array do
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

local function serialize(image: Image, should_relocate: boolean?): buffer
	if should_relocate == nil then
		should_relocate = true
	end

	-- Make a copy to avoid mutating the input
	local working_image = table.clone(image)
	working_image.optional_header = table.clone(image.optional_header)
	working_image.optional_header.windows = table.clone(image.optional_header.windows)
	working_image.sections = table.clone(image.sections)
	for i, section in working_image.sections do
		working_image.sections[i] = { header = table.clone(section.header), data = section.data }
	end

	if should_relocate then
		working_image = relocate_sections(working_image)
	end

	local is_pe32 = working_image.optional_header.standard_coff.magic == PE_32_MAGIC
	local total_size = working_image.optional_header.windows.size_of_headers

	for _, section in working_image.sections do
		if section.header.size_of_raw_data > 0 then
			local section_end = section.header.pointer_to_raw_data + section.header.size_of_raw_data
			total_size = math.max(total_size, section_end)
		end
	end

	local output = buffer.create(total_size)
	local offset = 0

	-- Write DOS header
	offset = dos_header.write(output, offset, working_image.dos_header)

	-- move to COFF header
	offset = working_image.dos_header.e_lfanew

	-- Write the NT signature
	buffer.writeu32(output, offset, NT_SIGNATURE)
	offset += 4

	-- Write COFF header
	local coff = table.clone(working_image.coff_header)
	coff.number_of_sections = #working_image.sections

	offset = coff_header.write(output, offset, coff)

	-- Write standard header
	offset = standard_coff_optional_header.write(output, offset, working_image.optional_header.standard_coff)

	-- Write windows headers
	local windows = working_image.optional_header.windows
	if is_pe32 then
		offset = windows_pe32.write(output, offset, windows :: types.PE32WindowsHeader)
	else
		offset = windows_pe64.write(output, offset, windows :: types.PE64WindowsHeader)
	end

	-- Write data directories
	local data_dirs_array = get_data_directory_array(working_image.data_directories)
	for i = 1, 16 do
		offset = image_data_directory.write(output, offset, data_dirs_array[i])
	end

	-- Write section headers
	for _, section in working_image.sections do
		offset = section_header.write(output, offset, section.header)
	end

	for _, section in working_image.sections do
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

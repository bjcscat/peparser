local struct = require("./struct")

local version_i16_struct = struct.struct({
	{ major = struct.i16 },
	{ minor = struct.i16 },
})

export type Version = typeof(version_i16_struct.__inner)

local dos_header_struct = struct.struct({
	{ e_magic = struct.u16 },
	{ e_cblp = struct.u16 },
	{ e_cp = struct.u16 },
	{ e_crlc = struct.u16 },
	{ e_cparhdr = struct.u16 },
	{ e_minalloc = struct.u16 },
	{ e_maxalloc = struct.u16 },
	{ e_ss = struct.u16 },
	{ e_sp = struct.u16 },
	{ e_csum = struct.u16 },
	{ e_ip = struct.u16 },
	{ e_cs = struct.u16 },
	{ e_lfarlc = struct.u16 },
	{ e_ovno = struct.u16 },
	{ e_res = struct.array(struct.u16, 4) },
	{ e_oemid = struct.u16 },
	{ e_oeminfo = struct.u16 },
	{ e_res2 = struct.array(struct.u16, 10) },
	{ e_lfanew = struct.u32 },
})

export type DOSHeader = typeof(dos_header_struct.__inner)

local coff_header_struct = struct.struct({
	{ machine = struct.u16 },
	{ number_of_sections = struct.u16 },
	{ time_date_stamp = struct.u32 },
	{ pointer_to_symbol_table = struct.u32 },
	{ number_of_symbols = struct.u32 },
	{ size_of_optional_header = struct.u16 },
	{ characteristics = struct.u16 },
})

export type COFFHeader = typeof(coff_header_struct.__inner)

local standard_header_struct = struct.struct({
	{ magic = struct.u16 },
	{
		linker_version = struct.struct({
			{ major = struct.u8 },
			{ minor = struct.u8 },
		}),
	},
	{ size_of_code = struct.u32 },
	{ size_of_initialized_data = struct.u32 },
	{ size_of_uninitialized_data = struct.u32 },
	{ address_of_entry_point = struct.u32 },
	{ base_of_code = struct.u32 },
})

export type StandardHeader = typeof(standard_header_struct.__inner)

local windows_pe32_struct = struct.struct({
	{ image_base = struct.u32 },
	{ section_alignment = struct.u32 },
	{ file_alignment = struct.u32 },
	{ operating_system_version = version_i16_struct },
	{ image_version = version_i16_struct },
	{ subsystem_version = version_i16_struct },
	{ win32_version_value = struct.u32 },
	{ size_of_image = struct.u32 },
	{ size_of_headers = struct.u32 },
	{ check_sum = struct.u32 },
	{ subsystem = struct.u16 },
	{ dll_characteristics = struct.u16 },
	{ size_of_stack_reserve = struct.u32 },
	{ size_of_stack_commit = struct.u32 },
	{ size_of_heap_reserve = struct.u32 },
	{ size_of_heap_commit = struct.u32 },
	{ loader_flags = struct.u32 },
	{ number_of_rva_and_sizes = struct.u32 },
})

local windows_pe64_struct = struct.struct({
	{ image_base = struct.u64 },
	{ section_alignment = struct.u32 },
	{ file_alignment = struct.u32 },
	{ operating_system_version = version_i16_struct },
	{ image_version = version_i16_struct },
	{ subsystem_version = version_i16_struct },
	{ win32_version_value = struct.u32 },
	{ size_of_image = struct.u32 },
	{ size_of_headers = struct.u32 },
	{ check_sum = struct.u32 },
	{ subsystem = struct.u16 },
	{ dll_characteristics = struct.u16 },
	{ size_of_stack_reserve = struct.u64 },
	{ size_of_stack_commit = struct.u64 },
	{ size_of_heap_reserve = struct.u64 },
	{ size_of_heap_commit = struct.u64 },
	{ loader_flags = struct.u32 },
	{ number_of_rva_and_sizes = struct.u32 },
})

export type PE32WindowsHeader = typeof(windows_pe32_struct.__inner)
export type PE64WindowsHeader = typeof(windows_pe64_struct.__inner)
export type WindowsHeader = PE32WindowsHeader | PE64WindowsHeader

local image_data_directory_struct = struct.struct({
	{ virtual_address = struct.u32 },
	{ size = struct.u32 },
})

export type ImageDataDirectory = typeof(image_data_directory_struct.__inner)

local section_header_struct = struct.struct({
	{ name = struct.array(struct.u8, 8) },
	{ virtual_size = struct.u32 },
	{ virtual_address = struct.u32 },
	{ size_of_raw_data = struct.u32 },
	{ pointer_to_raw_data = struct.u32 },
	{ pointer_to_relocations = struct.u32 },
	{ pointer_to_linenumbers = struct.u32 },
	{ number_of_relocations = struct.u16 },
	{ number_of_linenumbers = struct.u16 },
	{ characteristics = struct.u32 },
})

export type SectionHeader = typeof(section_header_struct.__inner)

export type Section = {
	header: SectionHeader,
	data: buffer?,
}

local resource_directory_struct = struct.struct({
	{ characteristics = struct.u32 },
	{ time_date_stamp = struct.u32 },
	{ major_version = struct.u16 },
	{ minor_version = struct.u16 },
	{ number_of_named_entries = struct.u16 },
	{ number_of_id_entries = struct.u16 },
})

export type ResourceDirectory = typeof(resource_directory_struct.__inner)

local resource_directory_entry_struct = struct.struct({
	{ name_or_id = struct.u32 },
	{ offset_to_data_or_directory = struct.u32 },
})

export type ResourceDirectoryEntry = typeof(resource_directory_entry_struct.__inner)

local resource_data_entry_struct = struct.struct({
	{ offset_to_data = struct.u32 },
	{ size = struct.u32 },
	{ code_page = struct.u32 },
	{ reserved = struct.u32 },
})

export type ResourceDataEntry = typeof(resource_data_entry_struct.__inner)

export type ResourceNode = {
	directory: ResourceDirectory?,
	entries: { ResourceEntry }?,
	data_entry: ResourceDataEntry?,
	data: buffer?,
	name_or_id: number | string,
}

export type ResourceEntry = {
	name_or_id: number | string,
	is_directory: boolean,
	node: ResourceNode?,
}

export type NTHeaders = {
	coff_header: COFFHeader,
	standard_header: StandardHeader,
	windows_headers: WindowsHeader,
}

export type Image = {
	dos_header: DOSHeader,
	nt_headers: NTHeaders,
	sections: { Section },
	data_directories: { ImageDataDirectory },
	resources: ResourceNode?,
}

return {
	version_i16_struct = version_i16_struct,
	dos_header_struct = dos_header_struct,
	coff_header_struct = coff_header_struct,
	standard_header_struct = standard_header_struct,
	windows_pe32_struct = windows_pe32_struct,
	windows_pe64_struct = windows_pe64_struct,
	image_data_directory_struct = image_data_directory_struct,
	section_header_struct = section_header_struct,
	resource_directory_struct = resource_directory_struct,
	resource_directory_entry_struct = resource_directory_entry_struct,
	resource_data_entry_struct = resource_data_entry_struct,
}

local struct = require("./struct")

local version_i16 = struct.struct({
	{ major = struct.i16 },
	{ minor = struct.i16 },
})

export type Version = typeof(version_i16.__inner)

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

local standard_coff_optional_header = struct.struct({
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

export type StandardCOFFOptionalHeader = typeof(standard_coff_optional_header.__inner)

local windows_pe32 = struct.struct({
	{ image_base = struct.u32 },
	{ section_alignment = struct.u32 },
	{ file_alignment = struct.u32 },
	{ operating_system_version = version_i16 },
	{ image_version = version_i16 },
	{ subsystem_version = version_i16 },
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

local windows_pe64 = struct.struct({
	{ image_base = struct.u64 },
	{ section_alignment = struct.u32 },
	{ file_alignment = struct.u32 },
	{ operating_system_version = version_i16 },
	{ image_version = version_i16 },
	{ subsystem_version = version_i16 },
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

export type PE32WindowsHeader = typeof(windows_pe32.__inner)
export type PE64WindowsHeader = typeof(windows_pe64.__inner)
export type WindowsHeader = PE32WindowsHeader | PE64WindowsHeader

local image_data_directory = struct.struct({
	{ virtual_address = struct.u32 },
	{ size = struct.u32 },
})

export type DataDirectory = typeof(image_data_directory.__inner)

export type DataDirectories = {
	export_table: DataDirectory?,
	import_table: DataDirectory?,
	resource_table: DataDirectory?,
	exception_table: DataDirectory?,
	certificate_table: DataDirectory?,
	base_relocation_table: DataDirectory?,
	debug: DataDirectory?,
	-- architecture: ImageDataDirectory?,
	global_ptr: DataDirectory?,
	tls_table: DataDirectory?,
	load_config_table: DataDirectory?,
	bound_import: DataDirectory?,
	iat: DataDirectory?,
	delay_import_descriptor: DataDirectory?,
	clr_runtime_header: DataDirectory?,
	-- reserved: ImageDataDirectory,
}

local DATA_DIRECTORIES = {
	EXPORT = 0, -- Export Directory
	IMPORT = 1, -- Import Directory
	RESOURCE = 2, -- Resource Directory
	EXCEPTION = 3, -- Exception Directory
	SECURITY = 4, -- Security Directory
	BASERELOC = 5, -- Base Relocation Table
	DEBUG = 6, -- Debug Directory
	-- IMAGE_DIRECTORY_ENTRY_COPYRIGHT       7
	-- IMAGE_DIRECTORY_ENTRY_ARCHITECTURE    7
	GLOBALPTR = 8, -- RVA of GP
	TLS = 9, -- TLS Directory
	LOAD_CONFIG = 10, -- Load Configuration Directory
	BOUND_IMPORT = 11, -- Bound Import Directory in headers
	IAT = 12, -- Import Address Table
	DELAY_IMPORT = 13, -- Delay Load Import Descriptors
	COM_DESCRIPTOR = 14, -- COM Runtime descriptor
}

local section_header = struct.struct({
	{ name = struct.null_terminated_string(8) },
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

export type SectionHeader = typeof(section_header.__inner)

export type Section = {
	header: SectionHeader,
	data: buffer,
}

local resource_directory = struct.struct({
	{ characteristics = struct.u32 },
	{ time_date_stamp = struct.u32 },
	{ major_version = struct.u16 },
	{ minor_version = struct.u16 },
	{ number_of_named_entries = struct.u16 },
	{ number_of_id_entries = struct.u16 },
})

export type ResourceDirectory = typeof(resource_directory.__inner)

local resource_directory_entry = struct.struct({
	{ name_or_id = struct.u32 },
	{ offset_to_data_or_directory = struct.u32 },
})

export type ResourceDirectoryEntry = typeof(resource_directory_entry.__inner)

local resource_data_entry = struct.struct({
	{ offset_to_data = struct.u32 },
	{ size = struct.u32 },
	{ code_page = struct.u32 },
	{ reserved = struct.u32 },
})

export type ResourceDataEntry = typeof(resource_data_entry.__inner)

export type ResourceId = number | string
export type ResourcePath = { ResourceId }

export type ResourceNode = {
	directory: ResourceDirectory?,
	entries: { ResourceEntry }?,
	data_entry: ResourceDataEntry?,
	data: buffer?,
	id: ResourceId,
}

export type ResourceEntry = {
	id: ResourceId,
	is_directory: boolean,
	node: ResourceNode?,
}

export type OptionalHeader = {
	standard_coff: StandardCOFFOptionalHeader,
	windows: WindowsHeader,
}

export type NTHeaders = {
	coff_header: COFFHeader,
	optional_header: OptionalHeader,
}

export type Image = {
    source: buffer,
    
    dos_header: DOSHeader,
	coff_header: COFFHeader,
	optional_header: OptionalHeader,
	data_directories: DataDirectories,
    sections: { Section },
}

return {
	DATA_DIRECTORIES = DATA_DIRECTORIES,

	version_i16 = version_i16,
	dos_header = dos_header_struct,
	coff_header = coff_header_struct,
	standard_coff_optional_header = standard_coff_optional_header,
	windows_pe32 = windows_pe32,
	windows_pe64 = windows_pe64,
	image_data_directory = image_data_directory,
	section_header = section_header,
	resource_directory = resource_directory,
	resource_directory_entry = resource_directory_entry,
	resource_data_entry = resource_data_entry,
}

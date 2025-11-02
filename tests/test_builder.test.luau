local peparser = require("../lib")
local test_case_lib = require("./utils/test_case")

local test_case = test_case_lib.test_case

local function test_find_section(exe_data: buffer)
	local image = peparser.parse(exe_data)

	local text_section = peparser.builder.find_section(image, ".text")
	if text_section then
		assert(text_section.header, "Found section has no header")
	end

	local fake_section = peparser.builder.find_section(image, ".fakesection")
	assert(fake_section == nil, "Should not find nonexistent section")
end

local function test_get_section_name(exe_data: buffer)
	local image = peparser.parse(exe_data)

	for _, section in image.sections do
		local name = peparser.builder.get_section_name(section)
		assert(type(name) == "string", "Section name should be a string")
		assert(#name > 0, "Section name should not be empty")
		assert(#name <= 8, "Section name should be 8 characters or less")
	end
end

local function test_update_resources(exe_data: buffer)
	local image = peparser.parse(exe_data)

	local resources = peparser.resources.create_directory(0, 0, 0)
	local RT_RCDATA = 10
	local test_data = buffer.fromstring("test resource data")

	peparser.resources.ensure_path(resources, { RT_RCDATA, 123, 1033 }, test_data, 0)

	local updated_image = peparser.builder.update_resources(image, resources)

	assert(updated_image.resources, "Resources not set on image")

	local found = peparser.resources.find_by_path(updated_image.resources, { RT_RCDATA, 123, 1033 })
	assert(found, "Resource not found after update")
	assert(found.data == test_data, "Resource data mismatch")
end

local function test_update_resources_preserves_existing(exe_data: buffer)
	local image = peparser.parse(exe_data)

	if image.resources then
		local original_resources = image.resources
		local updated_image = peparser.builder.update_resources(image, original_resources)

		assert(updated_image.resources == original_resources, "Resources not preserved")
	end
end

local function test_create_section()
	local section = peparser.builder.create_section(".test", 100, 0x1000, 100, 0, 0x40000040)

	assert(section.header, "Section header not created")
	assert(peparser.builder.get_section_name(section) == ".test", "Section name mismatch")
	assert(section.header.virtual_address == 0x1000, "Virtual address not set")
	assert(section.header.characteristics == 0x40000040, "Characteristics not set")
end

local function test_add_section(exe_data: buffer)
	local image = peparser.parse(exe_data)

	local original_count = #image.sections
	local new_section = peparser.builder.create_section(".new", 100, 0x10000, 100, 0, 0x40000040)
	new_section.data = buffer.fromstring("data")

	local success = peparser.builder.add_section(image, new_section)

	assert(success, "add_section returned false")
	assert(#image.sections == original_count + 1, "Section not added")
	assert(image.nt_headers.coff_header.number_of_sections == original_count + 1, "COFF header not updated")

	local found = peparser.builder.find_section(image, ".new")
	assert(found, "New section not found")
end

local function test_remove_section(exe_data: buffer)
	local image = peparser.parse(exe_data)

	if #image.sections > 0 then
		local original_count = #image.sections
		local first_section_name = peparser.builder.get_section_name(image.sections[1])

		local success = peparser.builder.remove_section(image, first_section_name)

		assert(success, "remove_section returned false")
		assert(#image.sections == original_count - 1, "Section not removed")
		assert(image.nt_headers.coff_header.number_of_sections == original_count - 1, "COFF header not updated")

		local found = peparser.builder.find_section(image, first_section_name)
		assert(found == nil, "Section still found after removal")
	end
end

local function test_set_section_data(exe_data: buffer)
	local image = peparser.parse(exe_data)

	if #image.sections > 0 then
		local first_section = image.sections[1]
		local _first_section_name = peparser.builder.get_section_name(first_section)
		local new_data = buffer.fromstring("new section data")

		peparser.builder.set_section_data(first_section, new_data)

		assert(first_section.data == new_data, "Section data not updated")
		assert(first_section.header.size_of_raw_data == buffer.len(new_data), "Size not updated")
	end
end

return function(exe_content: buffer): boolean
	test_case("find_section", test_find_section, exe_content)
	test_case("get_section_name", test_get_section_name, exe_content)
	test_case("update_resources", test_update_resources, exe_content)
	test_case("update_resources_preserves_existing", test_update_resources_preserves_existing, exe_content)
	test_case("create_section", test_create_section)
	test_case("add_section", test_add_section, exe_content)
	test_case("remove_section", test_remove_section, exe_content)
	test_case("set_section_data", test_set_section_data, exe_content)

	return not test_case_lib.has_failed
end

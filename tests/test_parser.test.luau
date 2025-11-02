local peparser = require("../lib")
local test_case_lib = require("./utils/test_case")

local test_case = test_case_lib.test_case

local function test_parse_valid_executable(exe_data: buffer)
	local image = peparser.parse(exe_data)

	assert(image, "Failed to parse executable")
	assert(image.dos_header.e_magic == 0x5A4D, "DOS magic is incorrect")
	assert(#image.sections > 0, "No sections found")
end

local function test_parse_sections(exe_data: buffer)
	local image = peparser.parse(exe_data)

	assert(#image.sections > 0, "Expected at least one section")

	for i, section in image.sections do
		assert(section.header, string.format("Section %d has no header", i))
		assert(section.data or section.header.size_of_raw_data == 0, string.format("Section %d missing data", i))
	end
end

local function test_parse_resources(exe_data: buffer)
	local image = peparser.parse(exe_data)

	if image.resources then
		assert(image.resources.directory ~= nil, "Root resource directory is missing")
		assert(image.resources.entries ~= nil, "Root resource entries are missing")
	end
end

local function test_section_lookup(exe_data: buffer)
	local image = peparser.parse(exe_data)

	local text_section = peparser.builder.find_section(image, ".text")
	if text_section then
		local section_name = peparser.builder.get_section_name(text_section)
		assert(section_name == ".text", "Section name mismatch")
	end

	local nonexistent = peparser.builder.find_section(image, ".nonexistent")
	assert(nonexistent == nil, "Found nonexistent section")
end

local function test_invalid_executable()
	local invalid_data = buffer.fromstring("Not a PE file")

	local ok = pcall(function()
		peparser.parse(invalid_data)
	end)

	assert(not ok, "Expected parse to fail on invalid data")
end

return function(exe_content: buffer): boolean
	test_case("parse_valid_executable", test_parse_valid_executable, exe_content)
	test_case("parse_sections", test_parse_sections, exe_content)
	test_case("parse_resources", test_parse_resources, exe_content)
	test_case("section_lookup", test_section_lookup, exe_content)
	test_case("invalid_executable", test_invalid_executable, exe_content)

	return not test_case_lib.has_failed
end

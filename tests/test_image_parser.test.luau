local peparser = require("@peparser")
local test_case_lib = require("./utils/test_case")

local test_case = test_case_lib.test_case

local function test_parse_valid_executable(exe_data: buffer)
	local image = peparser.image.parse(exe_data)

	assert(image, "Failed to parse executable")
	assert(image.dos_header.e_magic == 0x5A4D, "DOS magic is incorrect")
	assert(#image.sections > 0, "No sections found")
end

local function test_parse_sections(exe_data: buffer)
	local image = peparser.image.parse(exe_data)

	assert(#image.sections > 0, "Expected at least one section")

	for i, section in image.sections do
		assert(section.header, string.format("Section %d has no header", i))
		assert(section.data or section.header.size_of_raw_data == 0, string.format("Section %d missing data", i))
	end
end

local function test_parse_resources(exe_data: buffer)
	local image = peparser.image.parse(exe_data)

	local resources = peparser.resources.from_image(image)
    
	if resources then
		assert(resources.directory ~= nil, "Root resource directory is missing")
		assert(resources.entries ~= nil, "Root resource entries are missing")
	end
end

local function test_section_data(exe_data: buffer)
	local image = peparser.image.parse(exe_data)

	local text_section = nil
	for _, section in image.sections do
		if section.header.name == ".text" then
			text_section = section
			break
		end
	end

	if text_section then
		assert(text_section.header.name == ".text", "Section name mismatch")
	end
end

local function test_invalid_executable()
	local invalid_data = buffer.fromstring("Not a PE file")

	local ok = pcall(function()
		peparser.image.parse(invalid_data)
	end)

	assert(not ok, "Should fail on invalid PE file")
end

return function(exe_data: buffer)
	test_case("Parse valid executable", test_parse_valid_executable, exe_data)
	test_case("Parse sections", test_parse_sections, exe_data)
	test_case("Parse resources", test_parse_resources, exe_data)
	test_case("Section data lookup", test_section_data, exe_data)
	test_case("Invalid executable", test_invalid_executable)
end

local peparser = require("@peparser")
local test_case_lib = require("./utils/test_case")

local test_case = test_case_lib.test_case

local function test_roundtrip_basic(exe_data: buffer)
	local image1 = peparser.image.parse(exe_data)

	local serialized = peparser.image.serialize(image1)
	local image2 = peparser.image.parse(serialized)

	assert(image2.dos_header.e_magic == image1.dos_header.e_magic, "DOS magic changed")
	assert(#image2.sections == #image1.sections, "Section count changed")
end

local function test_roundtrip_sections(exe_data: buffer)
	local image1 = peparser.image.parse(exe_data)

	local serialized = peparser.image.serialize(image1)
	local image2 = peparser.image.parse(serialized)

	for i, section1 in image1.sections do
		local section2 = image2.sections[i]
		assert(section2, string.format("Section %d missing after roundtrip", i))

		local name1 = buffer.tostring(buffer.create(8, section1.header.name))
		local name2 = buffer.tostring(buffer.create(8, section2.header.name))

		assert(name1 == name2, string.format("Section %d name changed: %s -> %s", i, name1, name2))
		assert(
			section2.header.size_of_raw_data > 0 or section1.header.size_of_raw_data == 0,
			string.format("Section %d raw data size invalid", i)
		)
	end
end

local function test_serialize_with_relocation(exe_data: buffer)
	local image = peparser.image.parse(exe_data)

	local output1 = peparser.image.serialize(image)
	assert(buffer.len(output1) > 0, "Serialized buffer is empty")

	local reparsed = peparser.image.parse(output1)
	assert(#reparsed.sections == #image.sections, "Section count mismatch after serialize with relocation")
end

local function test_alignment()
	assert(peparser.image.align(100, 512) == 512, "align(100, 512) should be 512")
	assert(peparser.image.align(512, 512) == 512, "align(512, 512) should be 512")
	assert(peparser.image.align(513, 512) == 1024, "align(513, 512) should be 1024")
	assert(peparser.image.align(0, 512) == 0, "align(0, 512) should be 0")
end

local function test_headers_size_calculation(exe_data: buffer)
	local image = peparser.image.parse(exe_data)

	local is_pe32 = image.optional_header.standard_coff.magic == 0x010b
	local headers_size = peparser.image.calculate_headers_size(image, is_pe32)
	assert(headers_size > 0, "Headers size should be positive")
	assert(headers_size < 65536, "Headers size seems unreasonably large")
end

local function test_relocation_updates_rva(exe_data: buffer)
	local image = peparser.image.parse(exe_data)
	local relocated = peparser.image.relocate_sections(image)

	assert(relocated, "Relocation returned nil")
	assert(#relocated.sections == #image.sections, "Section count changed after relocation")
end

local function test_serialize_with_resources(exe_data: buffer)
	local image = peparser.image.parse(exe_data)
	local resources = peparser.resources.from_image(image)

	if resources then
		local test_data = buffer.fromstring("test resource data")
		local new_resource = peparser.resources.create_data(999, test_data, 0)
		peparser.resources.add_entry(resources, new_resource)

		image = peparser.resources.to_image(image, resources)

		local serialized = peparser.image.serialize(image, false) -- already relocated
		assert(buffer.len(serialized) > 0, "Serialization with added resource failed")

		local reparsed = peparser.image.parse(serialized)
		local reparsed_resources = peparser.resources.from_image(reparsed)
		assert(reparsed_resources, "Resources section lost after roundtrip")

		local found = peparser.resources.find_entry(reparsed_resources, 999)
		assert(found, "Added resource not found after roundtrip")
	end
end

local function test_serialize_with_named_resources(exe_data: buffer)
	local image = peparser.image.parse(exe_data)
	local resources = peparser.resources.from_image(image)

	if not resources then
		resources = peparser.resources.create_directory(0, 0, 0)
	end

	local RT_RCDATA = 10
	local RESOURCE_NAME = "TESTNAMED"
	local LANG_NEUTRAL = 0

	local test_data = buffer.fromstring("Named resource test data")

	peparser.resources.ensure_path(assert(resources), { RT_RCDATA, RESOURCE_NAME, LANG_NEUTRAL }, test_data, 0)

	image = peparser.resources.to_image(image, resources)

	local serialized = peparser.image.serialize(image, false)
	assert(buffer.len(serialized) > 0, "Serialization with named resource failed")

	local reparsed = peparser.image.parse(serialized)
	local reparsed_resources = peparser.resources.from_image(reparsed)
	assert(reparsed_resources, "Resources lost after roundtrip")

	local found = peparser.resources.find_by_path(reparsed_resources, { RT_RCDATA, RESOURCE_NAME, LANG_NEUTRAL })
	assert(found, "Named resource not found after roundtrip")
	assert(found.data, "Named resource has no data after roundtrip")

	local data_str = buffer.tostring(found.data)
	assert(data_str == "Named resource test data", "Named resource data corrupted after roundtrip")
end

local function test_serialize_without_relocation(exe_data: buffer)
	local image = peparser.image.parse(exe_data)

	local serialized = peparser.image.serialize(image, false)
	assert(buffer.len(serialized) > 0, "Serialization without relocation failed")

	local reparsed = peparser.image.parse(serialized)
	assert(#reparsed.sections == #image.sections, "Section count mismatch")
end

local function test_section_data_preservation(exe_data: buffer)
	local image = peparser.image.parse(exe_data)

	if #image.sections > 0 then
		local section = image.sections[1]
		if section.data then
			local original_size = buffer.len(section.data)

			local serialized = peparser.image.serialize(image)
			local reparsed = peparser.image.parse(serialized)

			local new_section = reparsed.sections[1]
			if new_section.data then
				assert(buffer.len(new_section.data) >= original_size, "Section data was truncated")
			end
		end
	end
end

return function(exe_data: buffer)
	test_case("roundtrip_basic", test_roundtrip_basic, exe_data)
	test_case("roundtrip_sections", test_roundtrip_sections, exe_data)
	test_case("serialize_with_relocation", test_serialize_with_relocation, exe_data)
	test_case("alignment", test_alignment)
	test_case("headers_size_calculation", test_headers_size_calculation, exe_data)
	test_case("relocation_updates_rva", test_relocation_updates_rva, exe_data)
	test_case("serialize_with_resources", test_serialize_with_resources, exe_data)
	test_case("serialize_with_named_resources", test_serialize_with_named_resources, exe_data)
	test_case("serialize_without_relocation", test_serialize_without_relocation, exe_data)
	test_case("section_data_preservation", test_section_data_preservation, exe_data)
end

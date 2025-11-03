local peparser = require("@peparser")
local test_case_lib = require("./utils/test_case")

local test_case = test_case_lib.test_case

local function test_create_directory()
	local dir = peparser.resources.create_directory(1, 0, 0)
	assert(dir, "Failed to create directory")
	local entries = dir.entries or {}
	assert(#entries == 0, "Directory should start empty")
end

local function test_create_data()
	local data = buffer.fromstring("test data")
	local resource = peparser.resources.create_data(42, data, 1033)
	assert(resource, "Failed to create data resource")
	assert(resource.data == data, "Data not stored correctly")
end

local function test_add_entry()
	local dir = peparser.resources.create_directory(1, 0, 0)
	local resource = peparser.resources.create_data(2, buffer.fromstring("test"), 0)
	peparser.resources.add_entry(dir, resource)
	local entries = dir.entries or {}
	assert(#entries == 1, "Entry not added")
end

local function test_find_entry()
	local dir = peparser.resources.create_directory(1, 0, 0)
	local resource1 = peparser.resources.create_data(2, buffer.fromstring("test1"), 0)
	local resource2 = peparser.resources.create_data(3, buffer.fromstring("test2"), 0)
	peparser.resources.add_entry(dir, resource1)
	peparser.resources.add_entry(dir, resource2)
	local found = peparser.resources.find_entry(dir, 3)
	assert(found, "Entry not found")
end

local function test_find_by_path()
	local root = peparser.resources.create_directory(0, 0, 0)
	local type_dir = peparser.resources.create_directory(10, 0, 0)
	peparser.resources.add_entry(root, type_dir)
	local id_dir = peparser.resources.create_directory(1, 0, 0)
	peparser.resources.add_entry(type_dir, id_dir)
	local lang_data = peparser.resources.create_data(1033, buffer.fromstring("test"), 0)
	peparser.resources.add_entry(id_dir, lang_data)
	local found = peparser.resources.find_by_path(root, { 10, 1, 1033 })
	assert(found, "Resource not found by path")
end

local function test_ensure_path()
	local root = peparser.resources.create_directory(0, 0, 0)
	local data = buffer.fromstring("test data")
	peparser.resources.ensure_path(root, { 24, 1, 0 }, data, 0)
	local found = peparser.resources.find_by_path(root, { 24, 1, 0 })
	assert(found, "Resource not created by ensure_path")
	assert(found.data, "Data not stored")
end

local function test_remove_entry()
	local dir = peparser.resources.create_directory(1, 0, 0)
	local resource = peparser.resources.create_data(2, buffer.fromstring("test"), 0)
	peparser.resources.add_entry(dir, resource)
	local entries = dir.entries or {}
	assert(#entries == 1, "Entry not added")
	local removed = peparser.resources.remove_entry(dir, 2)
	assert(removed, "Entry not removed")
	entries = dir.entries or {}
	assert(#entries == 0, "Entry still in directory")
end

local function test_set_data()
	local root = peparser.resources.create_directory(0, 0, 0)
	local old_data = buffer.fromstring("old data")
	local new_data = buffer.fromstring("new data")
	peparser.resources.ensure_path(root, { 10, 1, 0 }, old_data, 0)
	local found = peparser.resources.find_by_path(root, { 10, 1, 0 })
	assert(found, "Resource not found")
	peparser.resources.set_data(found, new_data)
	assert(found.data == new_data, "Data not updated")
end

local function test_parse_and_modify_resources(exe_data: buffer)
	local image = peparser.image.parse(exe_data)
	local resources = peparser.resources.from_image(image)
	if not resources then
		return
	end
	local test_data = buffer.fromstring("Added via test")
	local new_resource = peparser.resources.create_data(999, test_data, 0)
	peparser.resources.add_entry(resources, new_resource)
	image = peparser.resources.to_image(image, resources)
	local serialized = peparser.image.serialize(image, false)
	local reparsed = peparser.image.parse(serialized)
	local reparsed_resources = peparser.resources.from_image(reparsed)
	assert(reparsed_resources, "Resources lost after roundtrip")
	local found = peparser.resources.find_entry(reparsed_resources, 999)
	assert(found, "Added resource not found after roundtrip")
end

local function test_resource_types()
	local TYPES = peparser.resources.TYPES
	assert(TYPES.MANIFEST == 24, "MANIFEST type should be 24")
	assert(TYPES.ICON == 3, "ICON type should be 3")
end

local function test_make_path()
	local path = peparser.resources.make_path(24, 1, 0)
	assert(#path == 3, "Path should have 3 elements")
	assert(path[1] == 24, "First element should be 24")
	assert(path[2] == 1, "Second element should be 1")
	assert(path[3] == 0, "Third element should be 0")
end

return function(exe_data: buffer)
	test_case("create_directory", test_create_directory)
	test_case("create_data", test_create_data)
	test_case("add_entry", test_add_entry)
	test_case("find_entry", test_find_entry)
	test_case("find_by_path", test_find_by_path)
	test_case("ensure_path", test_ensure_path)
	test_case("remove_entry", test_remove_entry)
	test_case("set_data", test_set_data)
	test_case("parse_and_modify_resources", test_parse_and_modify_resources, exe_data)
	test_case("resource_types", test_resource_types)
	test_case("make_path", test_make_path)
end

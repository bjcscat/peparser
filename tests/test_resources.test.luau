local peparser = require("../lib")
local test_case_lib = require("./utils/test_case")

local test_case = test_case_lib.test_case

local function test_create_directory()
	local dir = peparser.resources.create_directory("root", 0, 0)

	assert(dir.directory, "Directory structure not created")
	assert(dir.entries, "Entries table not created")
	assert(dir.name_or_id == "root", "name_or_id not set correctly")
	assert(dir.directory.number_of_named_entries == 0, "Initial named count should be 0")
	assert(dir.directory.number_of_id_entries == 0, "Initial id count should be 0")
end

local function test_create_data()
	local test_buffer = buffer.fromstring("Hello, World!")
	local data_node = peparser.resources.create_data(123, test_buffer, 1252)

	assert(not data_node.directory, "Data node should not have directory")
	assert(not data_node.entries, "Data node should not have entries")
	assert(data_node.data_entry, "Data entry not created")
	assert(data_node.data == test_buffer, "Data buffer not set")
	assert(data_node.data_entry.size == buffer.len(test_buffer), "Size mismatch")
	assert(data_node.data_entry.code_page == 1252, "Code page not set correctly")
end

local function test_add_entry()
	local root = peparser.resources.create_directory(0, 0, 0)
	local child_id = peparser.resources.create_directory(10, 0, 0)
	local child_named = peparser.resources.create_directory("TEST", 0, 0)

	assert(peparser.resources.add_entry(root, child_id), "Failed to add ID entry")
	assert(root.directory and root.directory.number_of_id_entries == 1, "ID count not incremented")
	assert(root.directory and root.directory.number_of_named_entries == 0, "Named count should be 0")

	assert(peparser.resources.add_entry(root, child_named), "Failed to add named entry")
	assert(root.directory and root.directory.number_of_id_entries == 1, "ID count changed unexpectedly")
	assert(root.directory and root.directory.number_of_named_entries == 1, "Named count not incremented")
end

local function test_find_entry()
	local root = peparser.resources.create_directory(0, 0, 0)
	local child1 = peparser.resources.create_directory(10, 0, 0)
	local child2 = peparser.resources.create_directory("NAMED", 0, 0)

	peparser.resources.add_entry(root, child1)
	peparser.resources.add_entry(root, child2)

	local found_id = peparser.resources.find_entry(root, 10)
	assert(found_id == child1, "Failed to find entry by ID")

	local found_named = peparser.resources.find_entry(root, "NAMED")
	assert(found_named == child2, "Failed to find entry by name")

	local not_found = peparser.resources.find_entry(root, 999)
	assert(not_found == nil, "Should not find nonexistent entry")
end

local function test_find_by_path()
	local root = peparser.resources.create_directory(0, 0, 0)
	local level1 = peparser.resources.create_directory(10, 0, 0)
	local level2 = peparser.resources.create_directory("RESOURCE", 0, 0)
	local data_buf = buffer.fromstring("test")
	local level3 = peparser.resources.create_data(1033, data_buf)

	peparser.resources.add_entry(root, level1)
	peparser.resources.add_entry(level1, level2)
	peparser.resources.add_entry(level2, level3)

	local found = peparser.resources.find_by_path(root, { 10, "RESOURCE", 1033 })
	assert(found == level3, "Failed to find resource by path")

	local not_found = peparser.resources.find_by_path(root, { 10, "WRONG", 1033 })
	assert(not_found == nil, "Should not find nonexistent path")
end

local function test_ensure_path()
	local root = peparser.resources.create_directory(0, 0, 0)
	local data_buf = buffer.fromstring("test data")

	local RT_RCDATA = 10
	local path = { RT_RCDATA, "MYRESOURCE", 1033 }

	local result = peparser.resources.ensure_path(root, path, data_buf, 0)
	assert(result, "ensure_path returned nil")
	assert(result.data == data_buf, "Data not set correctly")

	local found = peparser.resources.find_by_path(root, path)
	assert(found == result, "Created resource not found at path")

	local new_buf = buffer.fromstring("updated data")
	local updated = peparser.resources.ensure_path(root, path, new_buf, 0)
	assert(updated.data == new_buf, "Data not updated")
end

local function test_remove_entry()
	local root = peparser.resources.create_directory(0, 0, 0)
	local child1 = peparser.resources.create_directory(10, 0, 0)
	local child2 = peparser.resources.create_directory("NAMED", 0, 0)

	peparser.resources.add_entry(root, child1)
	peparser.resources.add_entry(root, child2)

	assert(root.directory and root.directory.number_of_id_entries == 1, "Initial ID count wrong")
	assert(root.directory and root.directory.number_of_named_entries == 1, "Initial named count wrong")

	local removed = peparser.resources.remove_entry(root, 10)
	assert(removed, "Failed to remove ID entry")
	assert(root.directory and root.directory.number_of_id_entries == 0, "ID count not decremented")

	local removed_named = peparser.resources.remove_entry(root, "NAMED")
	assert(removed_named, "Failed to remove named entry")
	assert(root.directory and root.directory.number_of_named_entries == 0, "Named count not decremented")
end

local function test_ensure_path_creates_intermediate()
	local root = peparser.resources.create_directory(0, 0, 0)
	local path: { number | string } = { 1, 2, 3 }
	local data_buf = buffer.fromstring("deep data")

	local result = peparser.resources.ensure_path(root, path, data_buf, 0)
	assert(result, "ensure_path returned nil")

	local level1 = peparser.resources.find_entry(root, 1)
	assert(level1, "Level 1 not created")
	assert(level1.directory, "Level 1 should be directory")

	local level2 = peparser.resources.find_entry(level1, 2)
	assert(level2, "Level 2 not created")
	assert(level2.directory, "Level 2 should be directory")

	local level3 = peparser.resources.find_entry(level2, 3)
	assert(level3, "Level 3 not created")
	assert(level3.data, "Level 3 should have data")
	assert(level3.data == data_buf, "Level 3 data mismatch")
end

local function test_remove_entry_updates_counts()
	local root = peparser.resources.create_directory(0, 0, 0)

	peparser.resources.add_entry(root, peparser.resources.create_directory("NAMED1", 0, 0))
	peparser.resources.add_entry(root, peparser.resources.create_directory("NAMED2", 0, 0))
	peparser.resources.add_entry(root, peparser.resources.create_directory(1, 0, 0))
	peparser.resources.add_entry(root, peparser.resources.create_directory(2, 0, 0))

	if root.directory then
		assert(root.directory.number_of_named_entries == 2, "Should have 2 named entries")
		assert(root.directory.number_of_id_entries == 2, "Should have 2 ID entries")

		local removed = peparser.resources.remove_entry(root, "NAMED1")
		assert(removed, "Should have removed NAMED1")
		assert(root.directory.number_of_named_entries == 1, "Should have 1 named entry after removal")
		assert(root.directory.number_of_id_entries == 2, "Should still have 2 ID entries")

		removed = peparser.resources.remove_entry(root, 1)
		assert(removed, "Should have removed ID 1")
		assert(root.directory.number_of_named_entries == 1, "Should still have 1 named entry")
		assert(root.directory.number_of_id_entries == 1, "Should have 1 ID entry after removal")
	end
end

local function test_find_by_path_deep()
	local root = peparser.resources.create_directory(0, 0, 0)
	local path: { number | string } = { "TYPE", "NAME", 1033 }
	local data_buf = buffer.fromstring("localized data")

	peparser.resources.ensure_path(root, path, data_buf, 0)

	local found = peparser.resources.find_by_path(root, path)
	assert(found, "Should find resource by path")
	assert(found.data == data_buf, "Data should match")

	local partial_path: { number | string } = { "TYPE", "NAME" }
	local partial = peparser.resources.find_by_path(root, partial_path)
	assert(partial, "Should find partial path")
	assert(partial.directory, "Partial path should be directory")
end

return function()
	test_case("create_directory", test_create_directory)
	test_case("create_data", test_create_data)
	test_case("add_entry", test_add_entry)
	test_case("find_entry", test_find_entry)
	test_case("find_by_path", test_find_by_path)
	test_case("ensure_path", test_ensure_path)
	test_case("remove_entry", test_remove_entry)
	test_case("ensure_path_creates_intermediate", test_ensure_path_creates_intermediate)
	test_case("remove_entry_updates_counts", test_remove_entry_updates_counts)
	test_case("find_by_path_deep", test_find_by_path_deep)

	return not test_case_lib.has_failed
end

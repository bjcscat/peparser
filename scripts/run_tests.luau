local fs = require("@lute/fs")
local process = require("@lute/process")
local task = require("@lute/task")

local base64 = require("../tests/utils/base64")

local function open_with_retry(path: string, mode: string): fs.FileHandle
	local file_handle: fs.FileHandle
	for attempt = 1, 10 do
		local success
		success, file_handle = pcall(fs.open :: any, path, mode)

		if success then
			return file_handle
		elseif attempt < 10 then
			print(`Attempt {attempt} failed to open {path}, retrying...`)
			task.wait(0.1)
		else
			error(`Failed to open {path} after multiple attempts: {file_handle}`)
		end
	end

	error("unreachable")
end

local test_paths = {}
for _, entry in fs.listdir("./tests") do
	if entry.name:sub(-9) == "test.luau" then
		table.insert(test_paths, entry.name:sub(1, -11))
	end
end

table.sort(test_paths)

local function write_test_info(test_names: { string }, exe_files: { { name: string, contents: buffer } })
	local test_names_quoted: { string } = {}

	for _, name in test_names do
		table.insert(test_names_quoted, `"{name}"`)
	end

	local exe_files_table: { string } = {}
	for _, exe in exe_files do
		table.insert(
			exe_files_table,
			`\{name = "{exe.name}", contents = [[{buffer.tostring(base64.encode(exe.contents))}]]\}`
		)
	end

	fs.writestringtofile(
		"test_info.luau",
		`return \{test_names = \{{table.concat(test_names_quoted, ", ")}\}, exe_files = \{{table.concat(
			exe_files_table,
			", "
		)}\}\}`
	)
end

local exe_files: { { name: string, contents: buffer } } = {}
for _, entry in fs.listdir("./tests/artifacts") do
	if entry.name:sub(-4) == "exe_" then
		local contents = buffer.fromstring(fs.readasync(`tests/artifacts/{entry.name}`))
		table.insert(exe_files, { name = entry.name, contents = contents })
	end
end

write_test_info(test_paths, exe_files)

process.run({
	"luau",
	"--coverage",
	"tests/test_collator.luau",
}, { stdio = "inherit" })

print("Filtering int64 from coverage report...")

local function filter_paths_from_coverage(input: string, paths: { string }): string
	local filtered_lines: { string } = {}
	local skip_until_end = false

	local function matches(line: string): boolean
		for _, p in paths do
			if string.find(line, p) then
				return true
			end
		end
		return false
	end

	for line in string.gmatch(input, "[^\r\n]+") do
		if matches(line) then
			skip_until_end = true
		elseif line == "end_of_record" then
			if not skip_until_end then
				table.insert(filtered_lines, line)
			end
			skip_until_end = false
		elseif not skip_until_end then
			table.insert(filtered_lines, line)
		end
	end

	return table.concat(filtered_lines, "\n")
end

local coverage_data: string = fs.readfiletostring("coverage.out")
local out = filter_paths_from_coverage(coverage_data, {
	"int64%.luau",
	"base64%.luau",
	"test_case%.luau",
	"test_info%.luau",
	"test_collator%.luau",
})

local coverage_handle = open_with_retry("coverage.out", "w")
fs.write(coverage_handle, out)
fs.close(coverage_handle)

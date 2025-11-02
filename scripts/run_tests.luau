local fs = require("@lute/fs")
local process = require("@lute/process")

local base64 = require("../tests/utils/base64")

local test_paths = {}
for _, entry in fs.listdir("./tests") do
	if entry.name:sub(-9) == "test.luau" then
		table.insert(test_paths, entry.name:sub(1, -11)) -- remove .test.luau
	end
end

table.sort(test_paths)

local function write_test_info(test_names: { string }, exe_contents: buffer)
	local test_names_quoted: { string } = {}

	for _, name in test_names do
		table.insert(test_names_quoted, `"{name}"`)
	end

	fs.writestringtofile(
		"test_info.luau",
		`return \{test_names = \{{table.concat(test_names_quoted, ", ")}\}, contents = [[{buffer.tostring(
			base64.encode(exe_contents)
		)}]]\}`
	)
end

write_test_info(test_paths, buffer.fromstring(fs.readasync("tests/artifacts/do_nothing.exe_")))

process.run({
	"luau",
	"--coverage",
	"tests/test_collator.luau",
}, { stdio = "inherit" })

print("Filtering int64 from coverage report...")

local coverage_data = fs.readasync("coverage.out")
local filtered_lines = {}
local skip_until_end = false

for line in string.gmatch(coverage_data, "[^\r\n]+") do
	if line == "SF:./lib/int64.luau" then
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

local coverage = fs.open("coverage.out", "w")
fs.write(coverage, table.concat(filtered_lines, "\n"))
fs.close(coverage)

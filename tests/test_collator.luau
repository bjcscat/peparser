local base64 = require("./utils/base64")
local test_case = require("./utils/test_case")

local test_data = (require)("../test_info")

local exe_buffers: { { name: string, contents: buffer } } = {}
for _, exe_file in test_data.exe_files do
	table.insert(
		exe_buffers,
		{
			name = exe_file.name,
			contents = base64.decode(buffer.fromstring(exe_file.contents)),
		} :: typeof(exe_buffers[1])
	)
end

local total_suites = 0
local passed_suites = 0
local failed_suites = 0
local total_cases = 0
local passed_cases = 0
local failed_cases = 0

for _, exe_buffer in exe_buffers do
	print("\n" .. string.rep("=", 60))
	print(`Testing with: {exe_buffer.name}`)
	print(string.rep("=", 60))

	for _, test_name in test_data.test_names do
		test_case.reset_stats()
		total_suites += 1

		print(`[{test_name}]`)

		local success, err = pcall(function()
			return (require)(`./{test_name}.test`)(exe_buffer.contents)
		end)

		if not success then
			print(`  ✗ Suite errored: {err}`)
			failed_suites += 1
		elseif not test_case.has_failed then
			print(`  → Passed ({test_case.passed_tests}/{test_case.total_tests} cases)`)
			passed_suites += 1
			total_cases += test_case.total_tests
			passed_cases += test_case.passed_tests
		else
			print(`  → Failed ({test_case.failed_tests}/{test_case.total_tests} cases failed)`)
			failed_suites += 1
			total_cases += test_case.total_tests
			passed_cases += test_case.passed_tests
			failed_cases += test_case.failed_tests
		end
		print("")
	end
end

print(string.rep("=", 50))
print(`Test Summary:`)
print(`  Suites: {passed_suites}/{total_suites} passed`)
print(`  Cases:  {passed_cases}/{total_cases} passed`)
if failed_suites > 0 then
	print(`  Failed: {failed_suites} suite(s), {failed_cases} case(s)`)
	error("Test failures detected")
end
